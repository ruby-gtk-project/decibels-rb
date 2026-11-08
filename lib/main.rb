# frozen_string_literal: true

require 'adwaita'

require_relative 'translation'

# Bound before anything below is required: several of those files translate
# strings into frozen class-body constants, which only ever run once, at
# load time.
Translation.bind_text_domain

require_relative 'about_dialog'
require_relative 'mpris'
require_relative 'shortcuts_dialog'
require_relative 'style'
require_relative 'window'

# App is the application object.
#
# Ported from upstream's src/main.ts and src/application.ts: an application
# that handles open, carries the app.new-window, app.quit, app.about and
# app.shortcuts actions its primary menu and shortcuts dialog name, binds the
# accelerators upstream binds, and presents one Window per activation. Opening
# files follows upstream's vfunc_open: a single file goes into the current
# window when that window has nothing open, and anything else gets a window of
# its own.
class App
  include Translation

  APP_ID = 'org.rubygtkproject.Decibels'
  APP_NAME = _('Audio Player')
  VERSION = '0.1.0'

  # The icon name the empty page shows, which upstream derives from the
  # application id the same way.
  SYMBOLIC_ICON = "#{APP_ID}-symbolic"

  # Upstream sets the first three in src/application.ts. window.close is a
  # Gtk.Window built-in; upstream reaches it with a class-level Gtk.Shortcut
  # instead, but the accelerator is the same Ctrl+W. app.shortcuts is named by
  # data/header.blp and data/shortcuts-dialog.blp.
  ACCELS = {
    'app.new-window' => ['<Control>n'],
    'app.quit'       => ['<Control>q'],
    'app.shortcuts'  => ['<Control>question'],
    'win.open-file'  => ['<Control>o'],
    'window.close'   => ['<Control>w'],
  }.freeze

  ACTIONS = {
    'new-window' => :present_new_window,
    'quit'       => :quit,
    'about'      => :show_about_dialog,
    'shortcuts'  => :show_shortcuts_dialog,
  }.freeze

  def build
    app.tap do
      app.signal_connect('startup') { startup }
      app.signal_connect('activate') { present_new_window }
      app.signal_connect('open') { |_app, files, _hint| open(files) }
      # Deferred to an idle tick: AdwApplicationWindow fires this signal from
      # inside its own constructor (registering itself as the active window
      # as it builds), and a new window is not fully wrapped by the Ruby
      # bindings until that constructor returns. Reading `app.active_window`
      # synchronously from this handler re-enters the GObject introspection
      # loader for the same, still-under-construction window and it raises
      # "ruby wrapper for this GObject* already exists." Running it a tick
      # later costs nothing visible — MPRIS retargets a moment after the
      # window is already on screen either way.
      app.signal_connect('notify::active-window') do
        GLib::Idle.add do
          mpris.sync_active_window
          false
        end
      end

      ACTIONS.each do |name, handler|
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect('activate') { public_send(handler) }
          app.add_action(action)
        end
      end

      ACCELS.each { |action, accels| app.set_accels_for_action(action, accels) }
    end
  end

  # Gio::ApplicationFlags::HANDLES_OPEN, as upstream: the application takes
  # file arguments itself rather than letting GIO treat them as an error.
  def app = @app ||= Gtk::Application.new(APP_ID, :handles_open)

  def style = @style ||= Style.new

  def windows = @windows ||= []

  # The org.mpris.MediaPlayer2 D-Bus service, ported from upstream's
  # src/mpris.ts and src/application.ts. Built lazily since the first
  # window (and therefore the first stream worth reporting) only exists
  # once `present_new_window` has run at least once.
  def mpris = @mpris ||= Mpris.new(self)

  # The stream belonging to the application's currently active window, if
  # any — what upstream's `active_window_changed_cb` reads off
  # `this.active_window` directly, since this port's windows are composed
  # rather than subclassed (see window.rb's class comment).
  def active_stream = windows.find { |window| window.window == app.active_window }&.stream

  def present_new_window
    Window.new(app, SYMBOLIC_ICON).build.tap do |window|
      windows.push(window)
      window.present
      mpris.build
      mpris.sync_active_window
    end
  end

  def show_about_dialog
    AboutDialog.new(APP_ID, VERSION).build.present(app.active_window)
  end

  def show_shortcuts_dialog
    ShortcutsDialog.new.build.present(app.active_window)
  end

  def quit = app.quit

  # The custom symbolic icons live beside lib/, both in the checkout and in
  # the installed tree, and are found through the icon theme's search path
  # rather than upstream's GResource bundle.
  def icons_path = @icons_path ||= File.expand_path('../data/icons', __dir__)

  private

    def startup
      style.load
      Gtk::IconTheme.get_for_display(Gdk::Display.default).add_search_path(icons_path)
    end

    def open(files)
      Array(files).then do |list|
        if list.size == 1 && reusable_window
          reusable_window.load_file(list.first)
        else
          list.each { |file| present_new_window.load_file(file) }
        end
      end
    end

    # The window upstream would load a single file into: the active one, when
    # it has no file open yet.
    def reusable_window
      windows.find { |window| window.window == app.active_window && window.file.nil? }
    end
end
