# frozen_string_literal: true

# Drives the whole port headlessly: builds the application, opens a window,
# walks it through the empty state, both error states, a successfully
# accepted and played file, the drag overlay's wiring, the header bar's
# menu, both dialogs, the app-level actions/accelerators, and the player
# page's own widgets. It screenshots each state.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_decibels.rb
#
# GTK4 here has no offscreen backend - gtk_init fails outright with no
# display - so xvfb-run is not optional on this machine.

require 'fileutils'
require 'tmpdir'

# A scratch config/data directory, so a run never reads or writes the real one.
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('decibels-drive')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'
require 'playback_rate_button'
require 'volume_button'
require 'waveform_bar_chart'
require 'waveform_scale'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

ROOT = File.expand_path('..', __dir__)
MISSING_FILE = '/definitely/missing-file-decibels.mp3'

# A real, decodable audio file: the window now actually loads and plays
# whatever is accepted (MediaStream discovers and plays it through GstPlay),
# so the fixture has to be real audio, not merely "a regular file" the way
# the application's own .desktop file stood in before there was anything to
# play it with. 2000 buffers at the default 1024 samples/buffer, 44.1kHz is
# ~46s - long enough that a 10s skip-forward/skip-back pair (the player
# page's transport buttons) lands mid-file instead of overrunning into EOS.
REGULAR_FILE = File.join(Dir.mktmpdir('decibels-drive-fixture'), 'fixture.wav')
system("gst-launch-1.0 -q audiotestsrc num-buffers=2000 ! audioconvert ! wavenc ! filesink location=#{REGULAR_FILE}", exception: true)

GtkDriver.drive(App.new, shots: SHOTS) do |d, app|
  d.window { app.windows.first&.window }

  d.step('build fires activate and presents one window') do
    app.build
    app.app.signal_connect('activate') { app.present_new_window }
  end

  d.step('the app has to actually run for "activate" to fire, so this step is a pause') {}

  d.step('the window builds and shows the empty state') do
    d.check('exactly one window') { app.windows.length == 1 }
    window = app.windows.first
    d.check('it wraps an Adwaita::ApplicationWindow') { window.window.is_a?(Adwaita::ApplicationWindow) }
    d.check('its title is Audio Player') { window.window.title == Window::TITLE }
    d.check('the empty page is showing') { window.stack.visible_child_name == 'empty' }
    d.check('show-file starts disabled') { !window.show_file_action.enabled? }
    d.check('no file is open yet') { window.file.nil? }
    d.check('the empty state carries the app icon') do
      window.empty_state.status_page.icon_name == app.class::SYMBOLIC_ICON
    end
    d.check('the open button names win.open-file') do
      window.empty_state.open_button.action_name == 'win.open-file'
    end
    d.shot('01-empty')
  end

  d.step('the header bar menu matches upstream, section by section') do
    menu = app.windows.first.empty_state.header_bar.primary_menu
    d.check('three sections') { menu.n_items == 3 }
    sections = (0...menu.n_items).map { |i| menu.get_item_link(i, 'section') }
    first = sections[0]
    d.check('section 1 has New Window then Open…') do
      first.get_item_attribute_value(0, 'action', nil) == 'app.new-window' &&
        first.get_item_attribute_value(1, 'action', nil) == 'win.open-file'
    end
    second = sections[1]
    d.check('Show in Files is hidden-when action-disabled') do
      second.get_item_attribute_value(0, 'hidden-when', nil) == 'action-disabled'
    end
    third = sections[2]
    d.check('section 3 has Shortcuts then About') do
      third.get_item_attribute_value(0, 'action', nil) == 'app.shortcuts' &&
        third.get_item_attribute_value(1, 'action', nil) == 'app.about'
    end
  end

  d.step('setting a header title renders a WindowTitle widget') do
    bar = app.windows.first.empty_state.header_bar
    bar.title = 'Example.mp3'
    d.check('the title widget appeared') { bar.header_bar.title_widget.is_a?(Adwaita::WindowTitle) }
    d.check('it carries the title') { bar.header_bar.title_widget.title == 'Example.mp3' }
    bar.title = nil
    d.check('clearing the title removes the widget') { bar.header_bar.title_widget.nil? }
  end

  d.step('every icon the app names is in the theme') do
    theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)
    [
      'no-sound-symbolic', 'play-large-symbolic', 'pause-large-symbolic',
      'speedometer-symbolic', 'skip-backwards-10-symbolic', 'skip-forward-10-symbolic',
      "#{App::APP_ID}-symbolic",
    ].each do |icon|
      d.check("the icon theme resolves #{icon}") { theme.has_icon?(icon) }
    end
  end

  d.step('loading a directory shows the directory error') do
    app.windows.first.load_file(Gio::File.new_for_path(ROOT))
  end

  d.step('the directory error page is showing') do
    window = app.windows.first
    d.check('the error page is showing') { window.stack.visible_child_name == 'error' }
    d.check('show-file is still disabled') { !window.show_file_action.enabled? }
    d.check('the title is the directory title') { window.error_state.status_page.title == Window::DIRECTORY_TITLE }
    d.check('the description is the directory message') do
      window.error_state.status_page.description == Window::DIRECTORY_MESSAGE
    end
    d.shot('02-directory-error')
  end

  d.step('loading a missing path shows "cannot be played"') do
    app.windows.first.load_file(Gio::File.new_for_path(MISSING_FILE))
  end

  d.step('the missing-file error replaced the directory error') do
    window = app.windows.first
    d.check('still the error page') { window.stack.visible_child_name == 'error' }
    d.check('the title is "File Cannot Be Played"') { window.error_state.status_page.title == Window::CANNOT_BE_PLAYED }
    d.check('the description names no available file') do
      window.error_state.status_page.description == Window::NOT_FOUND
    end
    d.shot('03-missing-error')
  end

  d.step('loading a real regular file is accepted') do
    app.windows.first.load_file(Gio::File.new_for_path(REGULAR_FILE))
  end

  d.step('the file is now the window\'s current file') do
    window = app.windows.first
    d.check('the file was recorded') { window.file&.basename == File.basename(REGULAR_FILE) }
    d.check('show-file is enabled now') { window.show_file_action.enabled? }
    d.check('the stack switched to the player page') { window.stack.visible_child_name == 'player' }
    d.shot('03a-player-empty')
  end

  d.step('discovery runs on a background thread, so this step is a pause for it to settle') {}

  d.step('the stream discovered the real file and started autoplaying') do
    window = app.windows.first
    d.check('a positive duration was discovered') { window.stream.get_duration.positive? }
    d.check('autoplay started it playing') { window.stream.playing? }
    d.check('the play/pause button shows the pause icon') do
      window.player_state.send(:playback_image).icon_name == 'pause-large-symbolic'
    end
    d.shot('03b-player-playing')
  end

  d.step('clicking the real play/pause button pauses the stream') do
    window = app.windows.first
    window.player_state.send(:playback_button).signal_emit('clicked')
  end

  d.step('playback paused and the button flipped back to play') do
    window = app.windows.first
    player = window.player_state
    d.check('the stream is paused') { !window.stream.playing? }
    d.check('the icon switched to play') { player.send(:playback_image).icon_name == 'play-large-symbolic' }
    d.check('the tooltip says Play') { player.send(:playback_button).tooltip_text == 'Play' }
  end

  d.step('clicking skip-forward advances the timestamp through the real stream') do
    window = app.windows.first
    @before_skip = window.stream.timestamp
    window.player_state.send(:skip_forward_button).signal_emit('clicked')
  end

  d.step('skip-forward moved the timestamp ahead') do
    window = app.windows.first
    d.check('the timestamp advanced') { window.stream.timestamp > @before_skip }
    d.check('the timestamp label updated') { window.player_state.send(:timestamp_label).label != '00:00' }
  end

  d.step('clicking skip-back brings the timestamp back down') do
    window = app.windows.first
    @before_skip_back = window.stream.timestamp
    window.player_state.send(:skip_back_button).signal_emit('clicked')
  end

  d.step('skip-back moved the timestamp down again') do
    window = app.windows.first
    d.check('the timestamp decreased') { window.stream.timestamp < @before_skip_back }
    d.shot('03c-player-skipped')
  end

  # Gtk::Widget#activate_action is a ruby-gnome binding gap: it never routes
  # through a group registered with #insert_action_group on that same
  # widget, confirmed here with a trivial Gio::SimpleActionGroup outside
  # this app entirely (window.activate_action('grp.ping', nil) never fires
  # an action that window.lookup_action_group would find and fire directly).
  # The group itself - the thing this port actually builds and wires with
  # `win.insert_action_group('player', stream.action_group)` - works, so
  # these steps drive it the way that is actually reachable.
  d.step('firing player.play-pause on the installed action group resumes playback') do
    window = app.windows.first
    window.stream.action_group.activate_action('play-pause', nil)
  end

  d.step('the action toggled playback back on, same as the button would') do
    window = app.windows.first
    d.check('the stream is playing again') { window.stream.playing? }
    d.check('the icon switched back to pause') { window.player_state.send(:playback_image).icon_name == 'pause-large-symbolic' }
  end

  d.step('firing player.toggle-mute on the installed action group mutes the stream') do
    window = app.windows.first
    window.stream.action_group.activate_action('toggle-mute', nil)
  end

  d.step('the stream and the real volume button both reflect the mute') do
    window = app.windows.first
    d.check('the stream reports muted') { window.stream.muted? }
    d.check('the volume button mirrors it') { window.player_state.send(:volume_button).muted }
    d.check('its icon switched to muted') { window.player_state.send(:volume_button).send(:menu_button).icon_name == 'audio-volume-muted-symbolic' }
    window.stream.action_group.activate_action('toggle-mute', nil)
  end

  d.step('the unmute landed too') do
    window = app.windows.first
    d.check('the stream is unmuted again') { !window.stream.muted? }
  end

  d.step('moving the playback-rate button\'s real slider changes the stream\'s rate') do
    window = app.windows.first
    # rate= alone only syncs the display (as the standalone-widget steps
    # above already proved); #change_rate is what the slider's own
    # "change-value" signal calls, so this fires that same private path
    # rather than the public setter, to go through the callback for real.
    window.player_state.send(:playback_rate_button).send(:change_rate, 1.5)
  end

  d.step('the rate change callback reached the real stream') do
    window = app.windows.first
    d.check('the stream rate updated') { window.stream.rate == 1.5 }
    window.player_state.send(:playback_rate_button).send(:change_rate, PlaybackRateButton::DEFAULT_RATE)
  end

  d.step('pausing again before the drag-overlay steps reuse this window') do
    window = app.windows.first
    if window.stream.playing?
      window.stream.pause
    end
  end

  d.step('the drag overlay accepts a dropped file through the same path') do
    window = app.windows.first
    window.drag_overlay.send(:accept, Gio::File.new_for_path(REGULAR_FILE))
    d.check('the drop still landed on the same file') { window.file&.basename == File.basename(REGULAR_FILE) }
  end

  d.step('the drag overlay reports a failed drop as an error') do
    app.windows.first.drag_overlay.send(:accept, nil)
  end

  d.step('the failed-drop error settled, a tick later') do
    window = app.windows.first
    d.check('"Unable to access dropped files" is now showing') do
      window.error_state.status_page.description == DragOverlay::NO_FILES
    end
    d.check('the error page is back') { window.stack.visible_child_name == 'error' }
    d.shot('04-drag-overlay-error')
  end

  d.step('the drag overlay carries its own CSS class and starts closed') do
    overlay = app.windows.first.drag_overlay
    d.check('the drag-overlay class is on the bin') { overlay.has_css_class?('drag-overlay') }
    d.check('the revealer starts closed') { !overlay.revealer.reveal_child? }
    d.check('nothing is drop-targeted yet') { overlay.drop_target.current_drop.nil? }
  end

  d.step('the file dialog is configured the way upstream opens it') do
    dialog = app.windows.first.file_dialog
    d.check('it is modal') { dialog.modal? }
    d.check('its title is "Open File"') { dialog.title == 'Open File' }
    d.check('one filter, named "Audio files"') do
      dialog.filters.n_items == 1 && dialog.filters.get_item(0).name == 'Audio files'
    end
  end

  d.step('the shortcuts dialog opens over the window') do
    app.show_shortcuts_dialog
  end

  d.step('it is the window\'s visible dialog') do
    window = app.windows.first
    d.check('the shortcuts dialog is showing') { window.window.visible_dialog.is_a?(ShortcutsDialog) }
    d.shot('05-shortcuts')
    window.window.visible_dialog&.close
  end

  d.step('closing it clears visible_dialog') do
    window = app.windows.first
    d.check('nothing is showing now') { window.window.visible_dialog.nil? }
  end

  d.step('the about dialog reads its fields from the installed metainfo') do
    app.show_about_dialog
  end

  d.step('it is the window\'s visible dialog, filled in') do
    window = app.windows.first
    dialog = window.window.visible_dialog
    d.check('the about dialog is showing') { dialog.is_a?(AboutDialog) }
    d.check('the application name came from the metainfo') { dialog.application_name == 'Audio Player' }
    d.check('the version was passed through') { dialog.version == App::VERSION }
    d.check('a license was recognised') { dialog.license_type != :unknown }
    d.check('developers were set') { !dialog.developers.empty? }
    d.shot('06-about')
    dialog.close
  end

  d.step('app.new-window presents a second, independent window') do
    app.present_new_window
  end

  d.step('both windows exist, each with its own state') do
    d.check('two windows now') { app.windows.length == 2 }
    d.check('they are different toplevels') { !app.windows[0].window.equal?(app.windows[1].window) }
    d.check('the new one starts on the empty page') { app.windows[1].stack.visible_child_name == 'empty' }
    d.check('the first window\'s file survived') { app.windows[0].file&.basename == File.basename(REGULAR_FILE) }
    d.shot('07-second-window', app.windows[1].window)
  end

  d.step('the accelerators match what upstream binds') do
    d.check('app.new-window is Ctrl+N') { app.app.get_accels_for_action('app.new-window') == ['<Control>n'] }
    d.check('app.quit is Ctrl+Q') { app.app.get_accels_for_action('app.quit') == ['<Control>q'] }
    d.check('app.shortcuts is Ctrl+?') { app.app.get_accels_for_action('app.shortcuts') == ['<Control>question'] }
    d.check('win.open-file is Ctrl+O') { app.app.get_accels_for_action('win.open-file') == ['<Control>o'] }
    d.check('window.close is Ctrl+W') { app.app.get_accels_for_action('window.close') == ['<Control>w'] }
  end

  d.step('every app action it declares actually resolves') do
    %w[new-window quit about shortcuts].each do |name|
      d.check("app.#{name} is a real action") { !app.app.lookup_action(name).nil? }
    end
  end

  # The playback half of the port - PlaybackRateButton, VolumeButton,
  # WaveformBarChart and WaveformScale - has no player page to host it yet
  # (.reports/component-inventory.md). They are still real, built widgets, so
  # this drives each standalone in a throwaway window rather than skipping
  # them.
  d.step('the playback-rate button renders and reports rate changes') do
    @rate_changes = []
    @rate_button = PlaybackRateButton.new(on_rate_change: ->(rate) { @rate_changes << rate })
    @scratch_window = Gtk::Window.new.tap do |win|
      win.child = @rate_button
      win.set_default_size(80, 220)
      win.present
    end
  end

  d.step('the playback-rate button starts at the default rate') do
    d.check('default rate is 1.0') { @rate_button.rate == PlaybackRateButton::DEFAULT_RATE }
    d.shot('08-playback-rate', @scratch_window)
  end

  d.step('setting the rate clamps and does not re-fire the callback') do
    @rate_button.rate = 10.0
    d.check('the rate clamped to the upper bound') { @rate_button.rate == PlaybackRateButton::UPPER }
    d.check('rate= alone never calls the callback') { @rate_changes.empty? }
    @scratch_window.close
  end

  d.step('the volume button renders and reports volume/mute changes') do
    @volume_changes = []
    @mute_changes = []
    @volume_button = VolumeButton.new(
      on_volume_change: ->(volume) { @volume_changes << volume },
      on_mute_toggle:   ->(muted) { @mute_changes << muted },
    )
    @scratch_window = Gtk::Window.new.tap do |win|
      win.child = @volume_button
      win.set_default_size(260, 60)
      win.present
    end
  end

  d.step('the volume button starts half up and unmuted') do
    d.check('default volume is 0.5') { @volume_button.volume == VolumeButton::DEFAULT_VOLUME }
    d.check('not muted') { !@volume_button.muted }
    # 0.5 is the midpoint itself, and update_icons's volume > 0.5 test is
    # strict, so the default volume renders as "low", not "medium".
    d.check('icon reflects the default (low) volume') { @volume_button.send(:menu_button).icon_name == 'audio-volume-low-symbolic' }
    d.shot('09-volume', @scratch_window)
  end

  d.step('toggling mute flips the icon through the real button, not the setter') do
    @volume_button.send(:mute_button).active = true
    d.check('the callback fired with true') { @mute_changes == [true] }
    d.check('the icon switched to muted') { @volume_button.send(:menu_button).icon_name == 'audio-volume-muted-symbolic' }
    @volume_button.send(:mute_button).active = false
    d.check('unmuting fired again') { @mute_changes == [true, false] }
    @scratch_window.close
  end

  d.step('the waveform bar chart mipmaps peaks into bar geometry') do
    @bar_chart = WaveformBarChart.new
    d.check('no bars with no peaks') { @bar_chart.bars(200, 64).empty? }
    @bar_chart.peaks = Array.new(64) { |i| (i / 63.0) }
    bars = @bar_chart.bars(200, 64)
    d.check('bars were produced') { !bars.empty? }
    d.check('every bar height fits the given height') { bars.all? { |_x, height| height <= 64 } }
    d.check('x positions are non-decreasing') { bars.map(&:first) == bars.map(&:first).sort }
  end

  d.step('the waveform bar chart notifies when peaks change') do
    seen = []
    @bar_chart.on_peaks_changed { seen << @bar_chart.peaks.dup }
    @bar_chart.peaks = [0.1, 0.2, 0.3]
    d.check('the callback saw the new peaks') { seen == [[0.1, 0.2, 0.3]] }
  end

  d.step('the waveform scale renders peaks and reports a seek position') do
    @seeks = []
    @scale = WaveformScale.new
    @scale.on_position_changed { |pos| @seeks << pos }
    @scale.peaks = Array.new(200) { rand }
    @scratch_window = Gtk::Window.new.tap do |win|
      win.child = @scale
      win.set_default_size(300, 64)
      win.present
    end
  end

  d.step('the scale animates the bars growing in, then settles') do
    d.check('position starts at zero') { @scale.position.zero? }
    d.shot('10-waveform-scale', @scratch_window)
  end

  d.step('clicking the scale seeks and fires the callback') do
    # A real click reports gdouble coordinates, so this uses a Float too -
    # Integer x would silently floor-divide against the Integer width.
    @scale.send(:seek_to, @scale.width / 2.0)
    d.check('position moved toward the middle') { @scale.position.between?(0.3, 0.7) }
    d.check('the callback fired with that position') { @seeks == [@scale.position] }
    @scratch_window.close
  end

  d.step('opening a single file re-opens into the window that has none, not a new one') do
    reusable = app.windows.find { |window| window.file.nil? }
    app.send(:open, [Gio::File.new_for_path(REGULAR_FILE)])
    d.check('still two windows, no new one') { app.windows.length == 2 }
    d.check('the file went into the empty window') { reusable.file&.basename == File.basename(REGULAR_FILE) }
  end

  d.step('opening two files at once opens a window for each') do
    before = app.windows.length
    app.send(:open, [Gio::File.new_for_path(REGULAR_FILE), Gio::File.new_for_path(MISSING_FILE)])
    d.check('two new windows appeared') { app.windows.length == before + 2 }
  end
end
