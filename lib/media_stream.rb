# frozen_string_literal: true

require 'gtk4'
require 'gstreamer'
require_relative 'translation'
require_relative 'waveform_generator'

# GStreamer's boxed/value GTypes (TagList, Structure, and the rest GstPlay's
# and GstPbutils' own types are built from) only exist once `Gst.init` has
# run, so it has to happen before either typelib below is loaded — loading
# them first corrupts the GI loader's bookkeeping instead of raising.
Gst.init

# GstPlay carries Play, PlayMessage, PlayState and friends; loading it also
# pulls in GstAudio (the cubic/linear volume conversion upstream uses) as a
# side effect of its own typelib dependencies. GstPbutils carries Discoverer.
# Neither ships a ruby-gnome gem of its own, so both are loaded generically
# through GObjectIntrospection, the same way the dev shell's flake.nix notes
# there is "no dedicated ruby-gnome gem for either".
module GstPlay
  unless const_defined?(:Play)
    GObjectIntrospection::Loader.new(self).load('GstPlay')
  end
end

module GstPbutils
  unless const_defined?(:Discoverer)
    GObjectIntrospection::Loader.new(self).load('GstPbutils')
  end
end

# MediaStream is the playback model: one object per open file.
#
# Ported from upstream's src/stream.ts: a Gtk.MediaStream subclass that plays
# through GstPlay rather than GTK's own media backend, so that upstream can
# read tag-derived title/artist, offer a 0.5x-3.0x playback rate and drive
# WaveformGenerator from the same URI. Gtk::MediaStream is reused here for
# exactly what upstream reuses it for: the play/pause/seek state machine,
# the playing?/muted?/volume/timestamp properties, and the prepared/seeking
# bookkeeping that #update and #stream_prepared already give it — there is
# no video, so none of that is about painting anything.
#
# Upstream's APPlaySignalAdapter wraps the Play's bus in a second GObject
# that re-emits each "gst-play-message-data" application message as a typed
# signal. This port skips that layer and decodes the same application
# messages directly off the bus in #handle_message: the Ruby bindings
# marshal GLib::Error-carrying signal parameters (PlaySignalAdapter's
# "error" and "warning") in a way that corrupts memory and aborts the
# process on emission, confirmed by hand against this binding version, so
# this file never connects to those signals — it calls
# `GstPlay.play_message_parse_error` on the raw message instead, which
# returns the same GLib::Error safely.
#
# Likewise, GstPbutils::Discoverer#discover_uri_async's "discovered" signal
# carries a GLib::Error parameter and crashes the same way on arrival, so
# discovery here runs the synchronous, blocking `discover_uri` on a Ruby
# Thread and hands the result back to the main loop with GLib::Idle.add —
# the exception that method raises for a bad URI is an ordinary Ruby
# exception, not a signal parameter, and marshals back safely.
class MediaStream < Gtk::MediaStream
  include Translation

  type_register

  LOWER_RATE = 0.5
  UPPER_RATE = 3.0
  DEFAULT_RATE = 1.0

  CANNOT_BE_PLAYED = _("File uses a format that cannot be played. Additional media codecs may be required.")
  DISCOVER_FAILED = _("An error happened while trying to get information about the file. Please try again.")
  INVALID_URI = _('File uses an invalid URI')
  TIMED_OUT = _('Reading the file’s information timed out. Please try again.')
  NO_AUDIO = _('The selected file doesn’t contain any audio')

  attr_reader :waveform_generator, :file, :media_info

  def initialize
    super()
    @tags = nil
    @file = nil
    @media_info = nil
    @autoplay = true
    @rate = DEFAULT_RATE
    @is_buffering = false
    @discoverer_generation = 0
    @on_error = []
    @on_loaded = []
    @on_media_info_updated = []
    @waveform_generator = WaveformGenerator.new
  end

  def on_error(&block) = @on_error << block

  def on_loaded(&block) = @on_loaded << block

  # Fired once GstPlay's MEDIA_INFO_UPDATED message has set @media_info —
  # the point at which #title/#artist/#get_duration stop being guesses.
  # mpris.rb uses this to defer switching the MPRIS service to a newly
  # active window's stream until it actually has something playing,
  # mirroring upstream's own "notify::media-info" listener.
  def on_media_info_updated(&block) = @on_media_info_updated << block

  def rate = @rate

  def rate=(value)
    clamped = value.clamp(LOWER_RATE, UPPER_RATE)
    if clamped != @rate
      @rate = clamped
      backend.rate = clamped
    end
  end

  def is_buffering? = @is_buffering

  # Upstream's title getter: the tag, then the file's display name, then
  # the raw URI, then a fallback.
  def title
    tag_title = string_tag('title')
    file_name = @file && display_name(@file)

    if tag_title
      tag_title
    elsif file_name
      file_name
    else
      backend.uri || _('Unknown File')
    end
  end

  def artist = string_tag('artist')

  def has_audio? = !!(@media_info && @media_info.number_of_audio_streams > 0)

  def has_video? = !!(@media_info && @media_info.number_of_video_streams > 0)

  # Upstream's get_duration: the media info's duration, guarded against
  # GStreamer's "unknown" sentinel, in whole seconds.
  def get_duration
    if @media_info
      safe_duration(@media_info.duration) / Gst::USECOND
    else
      0
    end
  end

  def get_uri = backend.uri

  # Upstream's set_file: reset, remember the file, and discover its URI.
  def set_file(file, autoplay: true)
    reset
    @file = nil
    @autoplay = autoplay
    discover(file.uri) { @file = file }
  end

  def set_uri(uri, autoplay: true)
    reset
    @file = nil
    @autoplay = autoplay
    discover(uri)
  end

  def stop
    if prepared?
      stream_unprepared
    end
    backend.pipeline.set_state(Gst::State::NULL)
  end

  # Upstream's skip_seconds: seek by `seconds`, clamped at the start, and
  # treat overrunning the end as reaching end-of-stream.
  def skip_seconds(seconds)
    duration = get_duration
    new_timestamp = [timestamp + (seconds * Gst::MSECOND), 0].max

    if duration != 0 && new_timestamp > duration
      handle_eos
    else
      seek(new_timestamp)
    end
  end

  # Upstream's get_action_group: player.play, player.pause, player.play-pause,
  # player.skip-seconds and win.toggle-mute (here player.toggle-mute, since
  # this group is installed on the player page rather than the window).
  def action_group
    @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      group.add_action(play_action)
      group.add_action(pause_action)
      group.add_action(play_pause_action)
      group.add_action(skip_seconds_action)
      group.add_action(Gio::PropertyAction.new('toggle-mute', self, 'muted'))
    end
  end

  # vfuncs — Gtk::MediaStream's abstract play/pause/seek/update_audio.

  def virtual_do_play
    backend.play
    true
  end

  def virtual_do_pause
    backend.pause
    true
  end

  def virtual_do_seek(requested_timestamp)
    update(requested_timestamp)
    backend.seek((requested_timestamp * Gst::USECOND).to_i)
  end

  def virtual_do_update_audio(wants_muted, requested_volume)
    backend.mute = wants_muted
    backend.volume = requested_volume
  end

  # Upstream's reset: drop the tags, restart the discoverer and the
  # waveform generator, and stop the current pipeline. Public because
  # Window#build's close-request handler calls it directly, mirroring
  # upstream's vfunc_close_request.
  def reset
    @tags = nil
    @media_info = nil
    @discoverer_generation += 1
    waveform_generator.restart
    stop
  end

  private

    def backend = @backend ||= build_backend

    def build_backend
      GstPlay::Play.new.tap do |player|
        # Upstream explicitly defaults the volume to 100%, or GstPlay
        # remembers whatever the last pipeline on the process left it at.
        player.volume = 1.0
        player.video_track_enabled = false

        config = player.config
        GstPlay::Play.config_set_seek_accurate(config, true)
        player.config = config

        player.pipeline.set_property('video-sink', Gst::ElementFactory.make('fakesink', nil))

        player.signal_connect('notify::rate') { @rate = player.rate }

        bus = player.message_bus
        bus.add_signal_watch
        bus.signal_connect('message') { |_bus, message| handle_message(message) }
      end
    end

    def handle_message(message)
      if GstPlay::Play.play_message?(message)
        dispatch_message(message)
      end
    end

    def dispatch_message(message)
      case GstPlay.play_message_parse_type(message)
      when GstPlay::PlayMessage::URI_LOADED then handle_uri_loaded
      when GstPlay::PlayMessage::POSITION_UPDATED then handle_position_updated(message)
      when GstPlay::PlayMessage::DURATION_CHANGED then notify('duration')
      when GstPlay::PlayMessage::STATE_CHANGED then handle_state_changed(message)
      when GstPlay::PlayMessage::BUFFERING then handle_buffering(message)
      when GstPlay::PlayMessage::END_OF_STREAM then handle_eos
      when GstPlay::PlayMessage::MEDIA_INFO_UPDATED then handle_media_info_updated(message)
      when GstPlay::PlayMessage::VOLUME_CHANGED then self.volume = backend.volume
      when GstPlay::PlayMessage::MUTE_CHANGED then self.muted = backend.mute?
      when GstPlay::PlayMessage::SEEK_DONE then handle_seek_done(message)
      when GstPlay::PlayMessage::ERROR then handle_error(message)
      when GstPlay::PlayMessage::WARNING then handle_warning(message)
      end
    end

    def handle_uri_loaded
      @on_loaded.each(&:call)

      # Calling backend.pause loads the file immediately instead of waiting
      # for playback to start, matching upstream's uri_loaded_cb.
      if @autoplay
        play
      else
        backend.pause
      end
    end

    def handle_position_updated(message)
      position = GstPlay.play_message_parse_position_updated(message)
      unless seeking? && position.zero?
        if prepared?
          update(position / Gst::USECOND)
        end
      end
    end

    def handle_state_changed(message)
      state = GstPlay.play_message_parse_state_changed(message)
      if state == GstPlay::PlayState::BUFFERING
        @is_buffering = true
      elsif @is_buffering && state != GstPlay::PlayState::STOPPED
        @is_buffering = false
      end
    end

    def handle_buffering(message)
      percent = GstPlay.play_message_parse_buffering_percent(message)
      if percent < 100
        if !@is_buffering && playing?
          pause
          @is_buffering = true
        end
      else
        @is_buffering = false
        if playing?
          play
        end
      end
    end

    def handle_eos
      was_playing = playing?
      pause
      seek(0)
      if loop? && was_playing
        play
      end
    end

    def handle_media_info_updated(message)
      info = GstPlay.play_message_parse_media_info_updated(message)
      @media_info = info
      @tags = info.tags
      @on_media_info_updated.each(&:call)

      unless prepared?
        stream_prepared(
          info.number_of_audio_streams > 0,
          info.number_of_video_streams > 0,
          info.seekable?,
          safe_duration(info.duration) / Gst::USECOND,
        )

        if info.number_of_audio_streams <= 0
          report_error(NO_AUDIO)
        end
      end
    end

    def handle_seek_done(message)
      position = GstPlay.play_message_parse_seek_done(message)
      if seeking?
        seek_success
      end
      if prepared?
        update(position / Gst::USECOND)
      end
    end

    def handle_error(message)
      error, = GstPlay.play_message_parse_error(message)
      report_error(error)
    end

    def handle_warning(message)
      warning, = GstPlay.play_message_parse_warning(message)
      warn("player warning: #{warning.message}")
    end

    def string_tag(name)
      found, value = @tags&.get_string(name) || [false, nil]

      if found && value && !value.empty?
        value
      else
        nil
      end
    end

    def display_name(file)
      info = file.query_info('standard::display-name', :nofollow_symlinks)
      info&.get_attribute_string('standard::display-name')
    rescue Gio::Error
      nil
    end

    def safe_duration(value)
      if value && value < GLib::MAXUINT64
        value
      else
        0
      end
    end

    # Discovery runs `discover_uri` (blocking) on a Ruby Thread and hands
    # the result back to the main loop with GLib::Idle.add, rather than
    # using Discoverer's async "discovered" signal — see the class comment.
    def discover(uri, &on_success)
      generation = @discoverer_generation

      Thread.new do
        begin
          info = discoverer.discover_uri(uri)
          GLib::Idle.add do
            discovered(
              generation,
              info,
              nil,
              uri,
              on_success,
            )
            false
          end
        rescue => error
          GLib::Idle.add do
            discovered(
              generation,
              nil,
              error,
              uri,
              on_success,
            )
            false
          end
        end
      end
    end

    def discoverer = @discoverer ||= GstPbutils::Discoverer.new(GLib::MAXINT32)

    def discovered(generation, info, error, uri, on_success)
      if generation == @discoverer_generation
        apply_discovered(
          info,
          error,
          uri,
          on_success,
        )
      end
    end

    def apply_discovered(info, error, uri, on_success)
      if error
        report_error(discoverer_error_message(error))
      else
        @tags = info.tags
        on_success&.call
        backend.uri = uri
        waveform_generator.generate_peaks_async(uri)
      end
    end

    def discoverer_error_message(error)
      case error
      when Gst::ResourceError::NotFound then INVALID_URI
      when Gst::CoreError::MissingPlugin then CANNOT_BE_PLAYED
      else error.message || DISCOVER_FAILED
      end
    end

    def report_error(error)
      stop
      @on_error.each { |block| block.call(error) }
    end

    def play_action
      Gio::SimpleAction.new('play').tap do |action|
        action.signal_connect('activate') { play }
      end
    end

    def pause_action
      Gio::SimpleAction.new('pause').tap do |action|
        action.signal_connect('activate') { pause }
      end
    end

    def play_pause_action
      Gio::SimpleAction.new('play-pause').tap do |action|
        action.signal_connect('activate') { playing? ? pause : play }
      end
    end

    def skip_seconds_action
      Gio::SimpleAction.new('skip-seconds', GLib::VariantType.new('i')).tap do |action|
        action.signal_connect('activate') { |_action, seconds| skip_seconds(seconds) }
      end
    end
end
