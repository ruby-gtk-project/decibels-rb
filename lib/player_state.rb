# frozen_string_literal: true

require 'adwaita'
require_relative 'header_bar'
require_relative 'waveform_scale'
require_relative 'playback_rate_button'
require_relative 'volume_button'
require_relative 'media_stream' # GstAudio's cubic/linear volume conversion loads as its side effect.

# PlayerState is the page shown once a file has been accepted.
#
# Ported from upstream's src/player.ts and data/player.blp: an Adw.Bin whose
# toolbar view carries the shared header bar on top, the waveform and
# timestamp/duration labels in the middle and the transport controls on the
# bottom — a playback-rate button, skip-back/play-pause/skip-forward and a
# volume button.
#
# Upstream wires every control to `window.stream` through GObject property
# bindings set up in vfunc_root. This port takes the stream directly in its
# constructor instead (there is no root-widget lookup to replace it with) and
# wires each control with a plain `signal_connect` on the stream's own
# notifications, the same adaptation PlaybackRateButton and VolumeButton
# themselves already use one level down.
class PlayerState < Adwaita::Bin
  attr_reader :header_bar

  def initialize(stream)
    super()
    @stream = stream
    @header_bar = HeaderBar.new
    @updating_waveform = false
  end

  def build
    tap do |bin|
      bin.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar.build)
        view.content = clamp
        view.add_bottom_bar(controls)
      end

      clamp.child = content_box

      content_box.tap do |box|
        box.append(waveform)
        box.append(labels)
      end

      waveform.tap do |w|
        w.on_position_changed { |position| seek_to(position) }
        w.add_controller(scroll_controller)
      end

      labels.tap do |box|
        box.append(timestamp_label)
        box.append(duration_label)
      end

      connect_stream
      sync_from_stream
    end
  end

  private

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def clamp
      @clamp ||= Adwaita::Clamp.new.tap do |c|
        c.orientation = :vertical
        c.maximum_size = 600
        c.tightening_threshold = 300
      end
    end

    def content_box = @content_box ||= Gtk::Box.new(:vertical, 0)

    def waveform
      @waveform ||= WaveformScale.new.tap do |w|
        w.vexpand = true
        w.margin_start = 14
        w.margin_end = 14
      end
    end

    def scroll_controller
      @scroll_controller ||= Gtk::EventControllerScroll.new(:both_axes).tap do |controller|
        controller.signal_connect('scroll') { |_c, dx, dy| handle_scroll(dx, dy) }
      end
    end

    def labels
      @labels ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.margin_start = 24
        box.margin_end = 24
        box.set_direction(:ltr)
      end
    end

    def timestamp_label
      @timestamp_label ||= Gtk::Label.new('00:00').tap do |label|
        label.add_css_class('caption')
        label.add_css_class('numeric')
        label.set_direction(:ltr)
      end
    end

    def duration_label
      @duration_label ||= Gtk::Label.new('00:00').tap do |label|
        label.hexpand = true
        label.halign = :end
        label.add_css_class('caption')
        label.add_css_class('numeric')
        label.set_direction(:ltr)
      end
    end

    def controls
      @controls ||= Gtk::CenterBox.new.tap do |box|
        box.margin_start = 9
        box.margin_end = 9
        box.margin_bottom = 9
        box.add_css_class('toolbar')
        box.start_widget = playback_rate_button
        box.center_widget = playback_box
        box.end_widget = volume_button
      end
    end

    def playback_rate_button
      @playback_rate_button ||= PlaybackRateButton.new(on_rate_change: method(:change_rate)).tap do |button|
        button.valign = :center
        button.tooltip_text = 'Adjust Playback Speed'
      end
    end

    def volume_button
      @volume_button ||= VolumeButton.new(
        on_volume_change: method(:change_volume),
        on_mute_toggle:   method(:toggle_mute),
      ).tap do |button|
        button.valign = :center
      end
    end

    def playback_box
      @playback_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.set_direction(:ltr)
        box.append(skip_back_button)
        box.append(playback_button)
        box.append(skip_forward_button)
      end
    end

    def skip_back_button
      @skip_back_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'skip-backwards-10-symbolic'
        button.valign = :center
        button.tooltip_text = 'Skip Back 10s'
        button.add_css_class('circular')
        button.signal_connect('clicked') { @stream.skip_seconds(-10) }
      end
    end

    def skip_forward_button
      @skip_forward_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'skip-forward-10-symbolic'
        button.valign = :center
        button.tooltip_text = 'Skip Forward 10s'
        button.add_css_class('circular')
        button.signal_connect('clicked') { @stream.skip_seconds(10) }
      end
    end

    def playback_button
      @playback_button ||= Gtk::Button.new.tap do |button|
        button.width_request = 42
        button.height_request = 42
        button.add_css_class('pill')
        button.child = playback_image
        button.signal_connect('clicked') { toggle_play_pause }
      end
    end

    def playback_image
      @playback_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = 'play-large-symbolic'
        image.icon_size = :large
      end
    end

    def connect_stream
      @stream.signal_connect('notify::playing') { sync_playback }
      @stream.signal_connect('notify::timestamp') { sync_position }
      @stream.signal_connect('notify::duration') { sync_duration }
      @stream.signal_connect('notify::volume') { sync_volume }
      @stream.signal_connect('notify::muted') { sync_mute }
      @stream.waveform_generator.on_peaks_changed { waveform.peaks = @stream.waveform_generator.peaks }
    end

    def sync_from_stream
      sync_playback
      sync_position
      sync_duration
      sync_volume
      sync_mute
    end

    def sync_playback
      if @stream.playing?
        playback_image.icon_name = 'pause-large-symbolic'
        playback_button.tooltip_text = 'Pause'
      else
        playback_image.icon_name = 'play-large-symbolic'
        playback_button.tooltip_text = 'Play'
      end
    end

    # Upstream's timestamp binding also guards against overwriting the
    # handle while the user is actively dragging it — the waveform widget
    # reports that through its own state flags there; this port's
    # WaveformScale exposes nothing equivalent, so the guard flag set by
    # #seek_to stands in for it.
    def sync_position
      unless @updating_waveform
        duration = @stream.get_duration
        fraction = 0.0
        if duration.positive?
          fraction = (@stream.timestamp.to_f / duration).clamp(0.0, 1.0)
        end
        waveform.position = fraction
      end
      timestamp_label.label = micro_to_string(@stream.timestamp)
    end

    def sync_duration = duration_label.label = micro_to_string(@stream.get_duration)

    def sync_volume = volume_button.volume = get_cubic_volume(@stream.volume)

    def sync_mute = volume_button.muted = @stream.muted?

    def seek_to(position)
      @updating_waveform = true
      @stream.seek(position * @stream.get_duration)
      @updating_waveform = false
    end

    def handle_scroll(dx, dy)
      delta = dy
      if dx != 0
        delta = dx
      end
      @stream.skip_seconds(delta * 10)
    end

    def toggle_play_pause
      if @stream.playing?
        @stream.pause
      else
        @stream.play
      end
    end

    def change_rate(rate) = @stream.rate = rate

    def change_volume(cubic_volume) = @stream.volume = get_linear_volume(cubic_volume)

    def toggle_mute(muted) = @stream.muted = muted

    # Upstream's get_cubic_volume / get_linear_volume: GstAudio's cubic
    # scale is what the volume slider shows; GStreamer (and this stream's
    # own `volume` property) work in the linear one.
    def get_cubic_volume(linear)
      GstAudio.stream_volume_convert_volume(
        GstAudio::StreamVolumeFormat::LINEAR,
        GstAudio::StreamVolumeFormat::CUBIC,
        linear,
      )
    end

    def get_linear_volume(cubic)
      GstAudio.stream_volume_convert_volume(
        GstAudio::StreamVolumeFormat::CUBIC,
        GstAudio::StreamVolumeFormat::LINEAR,
        cubic,
      )
    end

    def micro_to_string(micro) = seconds_to_string(micro / 1_000_000)

    # Upstream's seconds_to_string: "mm:ss", with an "hh:" prefix once the
    # duration passes an hour.
    def seconds_to_string(total_seconds)
      hours = total_seconds / 3600
      minutes = (total_seconds / 60) % 60
      seconds = total_seconds % 60

      prefix = ''
      if hours.positive?
        prefix = format('%02d:', hours)
      end

      format(
        '%s%02d:%02d',
        prefix,
        minutes,
        seconds,
      )
    end
end
