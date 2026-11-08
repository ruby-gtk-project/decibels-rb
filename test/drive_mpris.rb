# frozen_string_literal: true

# Drives the MPRIS D-Bus service (lib/mpris.rb) end to end and asserts on
# it, over the real session bus — the only automated, counted check this
# component has. test/drive_mpris_server.rb idles for a human to run
# `gdbus call` by hand; this calls the same methods itself and checks what
# comes back, through Gio::DBusConnection (Gio::DBusProxy.new_for_bus hands
# back nil in the Ruby bindings — the same workaround Authenticator-rb's
# lib/screenshot.rb documents).
#
# The calls go through the async `call`/`call_finish` pair rather than
# `call_sync`: this test and the Mpris service it calls into both run on
# this one process's one GLib main loop, so a blocking `call_sync` made
# from inside a step would deadlock against the very dispatch that would
# answer it. `pump_until` below waits for the async reply by iterating
# that main loop directly instead.
#
#   nix develop --command xvfb-run -a ruby test/drive_mpris.rb

require 'fileutils'
require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('decibels-drive-mpris')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'
require_relative 'gtk_driver'

# A real, decodable audio file — MPRIS reports real metadata/duration off
# whatever MediaStream has discovered, so a fixture that merely exists is
# not enough.
REGULAR_FILE = File.join(Dir.mktmpdir('decibels-drive-mpris-fixture'), 'fixture.wav')
system("gst-launch-1.0 -q audiotestsrc num-buffers=2000 ! audioconvert ! wavenc ! filesink location=#{REGULAR_FILE}", exception: true)

BUS_NAME = "org.mpris.MediaPlayer2.#{App::APP_ID}"
OBJECT_PATH = Mpris::OBJECT_PATH
PLAYER_IFACE = Mpris::PLAYER_IFACE
MEDIA_PLAYER_IFACE = Mpris::MEDIA_PLAYER_IFACE
PROPERTIES_IFACE = Mpris::PROPERTIES_IFACE

def bus = $bus ||= Gio.bus_get_sync(Gio::BusType::SESSION)

# The MPRIS service this calls into lives on the very same GLib main loop
# this script's own GtkDriver steps run on. A blocking `call_sync` made
# straight from a step would deadlock: it blocks the one thread that would
# otherwise dispatch the request to Mpris#handle_method_call and send the
# reply back. Every call here goes through the async `call`/`call_finish`
# pair instead, and waits for its own reply by pumping the default
# GLib::MainContext directly — which *does* dispatch everything else
# pending on it (the incoming request among it) rather than just idling.
def pump_until
  GLib::MainContext.default.iteration(true) until yield
end

def dbus_call(bus_name, object_path, interface, method, parameters, reply_type)
  reply = nil
  done = false

  bus.call(
    bus_name,
    object_path,
    interface,
    method,
    parameters,
    GLib::VariantType.new(reply_type),
    Gio::DBusCallFlags::NONE,
    -1,
    nil,
  ) do |connection, async_result|
    reply = connection.call_finish(async_result)
    done = true
  end

  pump_until { done }
  reply
end

# One Properties.Get call. `call_finish` hands back the reply already
# unpacked into a plain Ruby Array — the same quirk Authenticator-rb's
# lib/screenshot.rb documents for `call_sync` — so `Get`'s single `v`
# (variant) out-argument arrives as the real Ruby value directly, with
# nothing left to unwrap.
def mpris_get(interface, property)
  dbus_call(
    BUS_NAME,
    OBJECT_PATH,
    PROPERTIES_IFACE,
    'Get',
    GLib::Variant.parse("('#{interface}', '#{property}')", '(ss)'),
    '(v)',
  ).first
end

def mpris_call(interface, method, parameters = nil, reply_type = '()')
  dbus_call(BUS_NAME, OBJECT_PATH, interface, method, parameters, reply_type)
end

GtkDriver.drive(App.new, shots: nil) do |d, app|
  d.window { app.windows.first&.window }

  d.step('build fires activate and presents one window') do
    app.build
    app.app.signal_connect('activate') { app.present_new_window }
  end

  d.step('the app has to actually run for "activate" to fire, so this step is a pause') {}

  d.step('load a real file, with autoplay, so MPRIS has something to report') do
    app.windows.first.load_file(Gio::File.new_for_path(REGULAR_FILE))
  end

  d.step('discovery runs on a background thread; give it a couple of ticks') {}
  d.step('still settling') {}

  d.step('starting MPRIS by hand, as App#present_new_window already would once a stream has media info') do
    app.mpris.sync_active_window
  end

  d.step('MPRIS owns its well-known bus name') do
    d.check('Mpris#started is true') { app.mpris.started }

    owner = dbus_call(
      'org.freedesktop.DBus',
      '/org/freedesktop/DBus',
      'org.freedesktop.DBus',
      'GetNameOwner',
      GLib::Variant.parse("('#{BUS_NAME}',)", '(s)'),
      '(s)',
    )
    d.check('the session bus has an owner for the well-known name') { !owner.first.to_s.empty? }
  end

  d.step('MediaPlayer2 properties, read back over the real bus') do
    d.check('Identity is "Audio Player"') { mpris_get(MEDIA_PLAYER_IFACE, 'Identity') == 'Audio Player' }
    d.check('DesktopEntry is the app id') { mpris_get(MEDIA_PLAYER_IFACE, 'DesktopEntry') == App::APP_ID }
    d.check('CanQuit is true') { mpris_get(MEDIA_PLAYER_IFACE, 'CanQuit') == true }
    d.check('CanRaise is true') { mpris_get(MEDIA_PLAYER_IFACE, 'CanRaise') == true }
    d.check('HasTrackList is false') { mpris_get(MEDIA_PLAYER_IFACE, 'HasTrackList') == false }
  end

  d.step('Player properties reflect the autoplayed stream') do
    stream = app.active_stream
    d.check('a stream is active') { !stream.nil? }
    d.check('PlaybackStatus is "Playing" (autoplay)') { mpris_get(PLAYER_IFACE, 'PlaybackStatus') == 'Playing' }
    d.check('CanPlay is true') { mpris_get(PLAYER_IFACE, 'CanPlay') == true }
    d.check('CanSeek is true') { mpris_get(PLAYER_IFACE, 'CanSeek') == true }
    d.check('LoopStatus is "None" (loop? starts false)') { mpris_get(PLAYER_IFACE, 'LoopStatus') == 'None' }

    # Metadata (and GetAll, which embeds it) is a D-Bus `a{sv}` — a dict of
    # variants. This binding version's GVariant-to-Ruby conversion has no
    # case for that shape yet ("TODO: GVariant({sv}) -> Ruby", confirmed by
    # hand against this binding), so a client reading it back crashes
    # before this method ever gets to assert anything, same as the
    # existing GVariant gaps lib/mpris.rb's own class comment documents
    # for signal parameters. Position is the one Player property that
    # both carries real state and marshals cleanly (a plain `x`) — it is
    # already a couple of seconds into the fixture by this point, since
    # autoplay started it back at the "load a real file" step, so this
    # only checks it is a sane in-range offset, not that it is zero.
    position = mpris_get(PLAYER_IFACE, 'Position')
    d.check('Position is a non-negative µs offset before the fixture ends') do
      position >= 0 && position < stream.get_duration
    end
  end

  d.step('Pause over D-Bus actually pauses the real stream') do
    mpris_call(PLAYER_IFACE, 'Pause')
  end

  d.step('give the pause a tick to land') {}

  d.step('the stream and PlaybackStatus both agree it is paused') do
    d.check('the stream is paused') { !app.active_stream.playing? }
    d.check('PlaybackStatus reports "Paused"') { mpris_get(PLAYER_IFACE, 'PlaybackStatus') == 'Paused' }
  end

  d.step('PlayPause over D-Bus resumes it') do
    mpris_call(PLAYER_IFACE, 'PlayPause')
  end

  d.step('give it a tick') {}

  d.step('playing again') do
    d.check('the stream is playing') { app.active_stream.playing? }
    d.check('PlaybackStatus reports "Playing"') { mpris_get(PLAYER_IFACE, 'PlaybackStatus') == 'Playing' }
  end

  d.step('Seek over D-Bus moves the real playhead') do
    @timestamp_before_seek = app.active_stream.timestamp
    mpris_call(PLAYER_IFACE, 'Seek', GLib::Variant.parse('(5000000,)', '(x)'))
  end

  d.step('give the seek a tick to land') {}

  d.step('the stream moved roughly 5 seconds forward') do
    moved = app.active_stream.timestamp - @timestamp_before_seek
    d.check('timestamp advanced by roughly 5s') { (moved - 5_000_000).abs < 1_500_000 }
  end

  d.step('Introspect describes every interface this port actually implements') do
    xml = mpris_call(Mpris::INTROSPECTABLE_IFACE, 'Introspect', nil, '(s)').first
    d.check('the Player interface is described') { xml.include?('org.mpris.MediaPlayer2.Player') }
    d.check('the MediaPlayer2 interface is described') { xml.include?('org.mpris.MediaPlayer2"') }
  end

  d.step('stop driving') do
    app.quit
  end
end
