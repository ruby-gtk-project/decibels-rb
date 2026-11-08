# frozen_string_literal: true

require 'gtk4'
require_relative 'translation'

# Mpris puts the app on the desktop's org.mpris.MediaPlayer2 D-Bus media
# controls (sound indicators, media-key daemons, "now playing" widgets).
#
# Ported from upstream's src/mpris.ts, whose `DBusInterface` base class walks
# `Gio.DBusNodeInfo#interfaces` generically, converts camelCase method names
# to snake_case and reads/builds every GVariant off the introspected
# signature with `GLib.Variant.new`/`#unpack`/`VariantBuilder`. That generic
# path isn't available here: this binding version raises
# `NotImplementedError: TODO: Ruby -> GVariant(...)` from `GLib::Variant.new`
# for several of the signatures this interface needs, and has no
# `GLib::VariantBuilder` at all. `GLib::Variant.parse(text, type)` — GVariant
# *text* format in, a typed Variant out — has no such gap, so this port
# builds every tuple, `a{sv}` dict and signal body that way instead, one
# method/property name at a time. This is the same shape showtime-rb's and
# blanket-rb's own `Mpris` classes already ship in this org, which is what
# establishes it as the house answer to this gap rather than a reason to
# skip MPRIS.
#
# Upstream is one MPRIS object shared by every window, retargeted at
# whichever window's stream is currently active (`Application#mpris` plus
# its `active_window_changed_cb`). This port keeps the same shape: `App`
# hands this class itself, and `#sync_active_window` — called whenever the
# application's active window changes — finds that window's stream through
# `App#active_stream` and switches to it, deferring the switch until the
# stream actually has a track loaded so a brand new, still-empty window
# never gets reported as playing "Unknown File".
class Mpris
  include Translation

  OBJECT_PATH = '/org/mpris/MediaPlayer2'

  INTROSPECTABLE_IFACE = 'org.freedesktop.DBus.Introspectable'
  PROPERTIES_IFACE = 'org.freedesktop.DBus.Properties'
  MEDIA_PLAYER_IFACE = 'org.mpris.MediaPlayer2'
  PLAYER_IFACE = 'org.mpris.MediaPlayer2.Player'

  INTERFACES = [INTROSPECTABLE_IFACE, PROPERTIES_IFACE, MEDIA_PLAYER_IFACE, PLAYER_IFACE].freeze

  NODE_XML = <<~XML
    <node>
      <interface name="org.freedesktop.DBus.Introspectable">
        <method name="Introspect">
          <arg name="data" direction="out" type="s"/>
        </method>
      </interface>
      <interface name="org.freedesktop.DBus.Properties">
        <method name="Get">
          <arg name="interface" direction="in" type="s"/>
          <arg name="property" direction="in" type="s"/>
          <arg name="value" direction="out" type="v"/>
        </method>
        <method name="Set">
          <arg name="interface_name" direction="in" type="s"/>
          <arg name="property_name" direction="in" type="s"/>
          <arg name="value" direction="in" type="v"/>
        </method>
        <method name="GetAll">
          <arg name="interface" direction="in" type="s"/>
          <arg name="properties" direction="out" type="a{sv}"/>
        </method>
        <signal name="PropertiesChanged">
          <arg name="interface_name" type="s"/>
          <arg name="changed_properties" type="a{sv}"/>
          <arg name="invalidated_properties" type="as"/>
        </signal>
      </interface>
      <interface name="org.mpris.MediaPlayer2">
        <method name="Raise"/>
        <method name="Quit"/>
        <property name="CanQuit" type="b" access="read"/>
        <property name="Fullscreen" type="b" access="readwrite"/>
        <property name="CanRaise" type="b" access="read"/>
        <property name="HasTrackList" type="b" access="read"/>
        <property name="Identity" type="s" access="read"/>
        <property name="DesktopEntry" type="s" access="read"/>
        <property name="SupportedUriSchemes" type="as" access="read"/>
        <property name="SupportedMimeTypes" type="as" access="read"/>
      </interface>
      <interface name="org.mpris.MediaPlayer2.Player">
        <method name="Next"/>
        <method name="Previous"/>
        <method name="Pause"/>
        <method name="PlayPause"/>
        <method name="Stop"/>
        <method name="Play"/>
        <method name="Seek">
          <arg direction="in" name="Offset" type="x"/>
        </method>
        <method name="SetPosition">
          <arg direction="in" name="TrackId" type="o"/>
          <arg direction="in" name="Position" type="x"/>
        </method>
        <method name="OpenUri">
          <arg direction="in" name="Uri" type="s"/>
        </method>
        <signal name="Seeked">
          <arg name="Position" type="x"/>
        </signal>
        <property name="PlaybackStatus" type="s" access="read"/>
        <property name="LoopStatus" type="s" access="readwrite"/>
        <property name="Rate" type="d" access="readwrite"/>
        <property name="Shuffle" type="b" access="readwrite"/>
        <property name="Metadata" type="a{sv}" access="read"/>
        <property name="Position" type="x" access="read"/>
        <property name="MinimumRate" type="d" access="read"/>
        <property name="MaximumRate" type="d" access="read"/>
        <property name="CanGoNext" type="b" access="read"/>
        <property name="CanGoPrevious" type="b" access="read"/>
        <property name="CanPlay" type="b" access="read"/>
        <property name="CanPause" type="b" access="read"/>
        <property name="CanSeek" type="b" access="read"/>
        <property name="CanControl" type="b" access="read"/>
      </interface>
    </node>
  XML

  # Upstream's `_get_song_dbus_path`: a single fixed object path, since this
  # is a single-track player with no real tracklist to assign ids from.
  SONG_DBUS_PATH = "#{OBJECT_PATH}/TrackList/NoTrack"

  attr_reader :started

  # `app` is the port's App — the one object this class needs, since it
  # delegates the active window's stream, the raw Gtk::Application (for
  # Raise/Quit) and the application id through it.
  def initialize(app)
    @app = app
    @started = false
    @stream = nil
    @stream_listeners = []
    @pending_stream = nil
  end

  # Registers every interface on the session bus and owns the well-known
  # name. Idempotent, so it is safe to call once per launch.
  def build
    @build ||= bus.tap do |connection|
      INTERFACES.each do |name|
        connection.register_object(OBJECT_PATH, interface_info(name)) do |*closure_args|
          handle_method_call(*closure_args.last(4))
        end
      end

      Gio.bus_own_name_on_connection(connection, bus_name, Gio::BusNameOwnerFlags::NONE)
      @started = true
    end
  end

  def bus = @bus ||= Gio.bus_get_sync(Gio::BusType::SESSION)

  def bus_name = "org.mpris.MediaPlayer2.#{App::APP_ID}"

  def interface_info(name) = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(name)

  # Ported from upstream's `Application#active_window_changed_cb`: switch
  # to the active window's stream, unless it has not loaded a track yet —
  # in which case wait for that stream's own "media info updated" instead
  # of reporting it as the active player while it would still show
  # "Unknown File".
  def sync_active_window
    stream = @app.active_stream

    if stream && stream.media_info
      switch_stream(stream)
    elsif stream && @pending_stream != stream
      @pending_stream = stream
      stream.on_media_info_updated do
        if @app.active_stream == stream
          switch_stream(stream)
        end
      end
    end
  end

  private

    # Ported from upstream's `MPRIS#switch_stream`: tear down the previous
    # stream's listeners, wire up the new one, and push its current state
    # to the bus immediately in case a client is already connected.
    def switch_stream(stream)
      unless stream == @stream
        disconnect_listeners
        @stream = stream
        @pending_stream = nil
        connect_listeners(stream)

        unless started
          build
        end

        properties_changed(PLAYER_IFACE, %w[PlaybackStatus LoopStatus Metadata Position])
      end
    end

    def connect_listeners(stream)
      @stream_listeners = [
        stream.signal_connect('notify::playing') { properties_changed(PLAYER_IFACE, %w[PlaybackStatus]) },
        stream.signal_connect('notify::loop') { properties_changed(PLAYER_IFACE, %w[LoopStatus]) },
        stream.signal_connect('notify::seeking') do
          unless stream.seeking?
            emit_seeked(stream)
          end
        end,
      ]
      stream.on_media_info_updated do
        if stream == @stream
          properties_changed(PLAYER_IFACE, %w[Metadata])
        end
      end
    end

    def disconnect_listeners
      if @stream
        @stream_listeners.each { |listener_id| @stream.signal_handler_disconnect(listener_id) }
      end
      @stream_listeners = []
    end

    def emit_seeked(stream)
      bus.emit_signal(
        nil,
        OBJECT_PATH,
        PLAYER_IFACE,
        'Seeked',
        GLib::Variant.parse("(#{stream.timestamp.to_i},)", '(x)'),
      )
    end

    def handle_method_call(interface_name, method_name, parameters, invocation)
      case [interface_name, method_name]
      when [INTROSPECTABLE_IFACE, 'Introspect']
        invocation.return_value(GLib::Variant.parse("(#{quote(NODE_XML)},)", '(s)'))
      when [PROPERTIES_IFACE, 'Get']
        handle_get(parameters, invocation)
      when [PROPERTIES_IFACE, 'Set']
        handle_set(parameters, invocation)
      when [PROPERTIES_IFACE, 'GetAll']
        handle_get_all(parameters, invocation)
      when [MEDIA_PLAYER_IFACE, 'Raise']
        @app.app.activate
        invocation.return_value(nil)
      when [MEDIA_PLAYER_IFACE, 'Quit']
        @app.app.quit
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Next']
        @stream&.skip_seconds(10)
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Previous']
        @stream&.skip_seconds(-10)
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Pause']
        @stream&.pause
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'PlayPause']
        if @stream
          if @stream.playing?
            @stream.pause
          else
            @stream.play
          end
        end
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Stop']
        @stream&.stop
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Play']
        @stream&.play
        invocation.return_value(nil)
      when [PLAYER_IFACE, 'Seek']
        handle_seek(parameters, invocation)
      when [PLAYER_IFACE, 'SetPosition']
        handle_set_position(parameters, invocation)
      when [PLAYER_IFACE, 'OpenUri']
        # Upstream's own `_open_uri`: a single-track player with no "open
        # by URI" path of its own, so this is an intentional no-op.
        invocation.return_value(nil)
      else
        invocation.return_dbus_error("#{interface_name}.UnknownMethod", "Unknown method #{method_name}")
      end
    rescue StandardError => error
      invocation.return_dbus_error("#{interface_name}.Error", error.message)
    end

    # `parameters` arrives already unwrapped to a Ruby Array of its tuple's
    # own already-unwrapped values.
    def handle_get(parameters, invocation)
      _interface, name = parameters
      invocation.return_value(GLib::Variant.parse("(#{property_text(name)},)", '(v)'))
    end

    def handle_set(parameters, invocation)
      interface_name, property_name, value = parameters
      apply_set(interface_name, property_name, value)
      invocation.return_value(nil)
    end

    def handle_get_all(parameters, invocation)
      interface, = parameters
      names = property_names(interface)
      body = names.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(', ')
      invocation.return_value(GLib::Variant.parse("({#{body}},)", '(a{sv})'))
    end

    # Ported from upstream's `_seek`: relative to the current position,
    # clamped at the start, and treated as end-of-stream once it would
    # overrun the track's duration.
    def handle_seek(parameters, invocation)
      offset, = parameters

      if @stream
        new_position = @stream.timestamp + offset

        if new_position < 0
          @stream.seek(0)
        elsif new_position <= @stream.get_duration
          @stream.seek(new_position)
        else
          @stream.seek(0)
          @stream.pause
        end
      end

      invocation.return_value(nil)
    end

    # Ported from upstream's `_set_position`: only seeks when the track id
    # given matches the one and only track this player currently has.
    def handle_set_position(parameters, invocation)
      track_id, position = parameters

      if @stream && track_id == SONG_DBUS_PATH
        @stream.seek(position)
      end

      invocation.return_value(nil)
    end

    def apply_set(interface_name, property_name, value)
      if interface_name == PLAYER_IFACE && property_name == 'LoopStatus'
        case value
        when 'None'
          @stream&.loop = false
        when 'Track', 'Playlist'
          @stream&.loop = true
        end
      end
      # Upstream's own `_set`: Rate, Volume, Shuffle and MediaPlayer2's
      # Fullscreen are all advertised as readwrite but none is wired to
      # anything — matching the real MPRIS implementations this port's
      # clients already talk to.
    end

    def property_names(interface)
      case interface
      when MEDIA_PLAYER_IFACE
        %w[CanQuit Fullscreen CanSetFullscreen CanRaise HasTrackList Identity DesktopEntry
           SupportedUriSchemes SupportedMimeTypes]
      when PLAYER_IFACE
        %w[PlaybackStatus LoopStatus Rate Shuffle Metadata Position MinimumRate MaximumRate
           CanGoNext CanGoPrevious CanPlay CanPause CanSeek CanControl]
      else
        []
      end
    end

    # The GVariant text format fragment for a property's *boxed* value —
    # what belongs inside the angle brackets of a variant. Ported from
    # upstream's `_get_all`, one property at a time instead of one object
    # literal, since several of its values (Rate, MinimumRate,
    # MaximumRate) are upstream's own hardcoded constants rather than
    # reads off the stream.
    def property_text(name)
      case name
      when 'CanQuit', 'CanRaise'
        '<true>'
      when 'Fullscreen', 'CanSetFullscreen', 'HasTrackList'
        '<false>'
      when 'Identity'
        "<#{quote(_('Audio Player'))}>"
      when 'DesktopEntry'
        "<#{quote(App::APP_ID)}>"
      when 'SupportedUriSchemes', 'SupportedMimeTypes'
        '<@as []>'
      when 'PlaybackStatus'
        "<#{quote(playback_status)}>"
      when 'LoopStatus'
        "<#{quote(loop_status)}>"
      when 'Rate', 'MinimumRate', 'MaximumRate'
        '<1.0>'
      when 'Shuffle'
        '<false>'
      when 'Metadata'
        "<#{metadata_text}>"
      when 'Position'
        "<@x #{position_usec}>"
      when 'CanGoNext', 'CanGoPrevious', 'CanPlay', 'CanPause', 'CanSeek', 'CanControl'
        '<true>'
      else
        raise ArgumentError, "No such property '#{name}'"
      end
    end

    def playback_status
      if @stream.nil?
        'Stopped'
      elsif @stream.playing?
        'Playing'
      else
        'Paused'
      end
    end

    def loop_status
      if @stream&.loop?
        'Track'
      else
        'None'
      end
    end

    def position_usec = (@stream&.timestamp || 0).to_i

    # Ported from upstream's `_get_metadata`: no track beyond the one this
    # single-track player currently has, so a fixed object path stands in
    # whether or not one is loaded.
    def metadata_text
      if @stream.nil?
        "@a{sv} {#{quote('mpris:trackid')}: <@o #{quote(SONG_DBUS_PATH)}>}"
      else
        fields = {
          'mpris:trackid' => "<@o #{quote(SONG_DBUS_PATH)}>",
          'mpris:length'  => "<@x #{@stream.get_duration.to_i}>",
          'xesam:title'   => "<#{quote(@stream.title)}>",
        }
        if @stream.artist
          fields['xesam:artist'] = "<@as [#{quote(@stream.artist)}]>"
        end

        "@a{sv} {#{fields.map { |key, value| "#{quote(key)}: #{value}" }.join(', ')}}"
      end
    end

    def properties_changed(interface_name, changed_properties)
      body = changed_properties.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(', ')

      bus.emit_signal(
        nil,
        OBJECT_PATH,
        PROPERTIES_IFACE,
        'PropertiesChanged',
        GLib::Variant.parse("(#{quote(interface_name)}, {#{body}}, @as [])", '(sa{sv}as)'),
      )
    end

    ESCAPES = {"\\" => '\\\\', '"' => '\\"', "\n" => '\\n'}.freeze

    def quote(value) = %("#{value.to_s.gsub(/[\\"\n]/) { |char| ESCAPES.fetch(char) }}")
end
