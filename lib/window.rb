# frozen_string_literal: true

require 'adwaita'

require_relative 'drag_overlay'
require_relative 'empty_state'
require_relative 'error_state'

# Window is one audio-player window.
#
# Ported from upstream's src/window.ts and data/window.blp: an
# Adw.ApplicationWindow whose content is the drag overlay wrapped around a
# Gtk.Stack of pages, with the win.open-file and win.show-file actions and the
# file dialog upstream opens from them. "Show in Files" starts out disabled and
# becomes available once a file has been accepted, which is what makes the menu
# item appear at all — upstream marks it `hidden-when: "action-disabled"`.
#
# The window itself is composed rather than subclassed: the Ruby bindings let
# Adw.ApplicationWindow be instantiated but not usefully derived from, so the
# widget is held by this class and the pages reach it through callbacks instead
# of Gtk.Widget#get_root.
class Window
  WIDTH = 650
  HEIGHT = 450
  MIN_HEIGHT = 260
  TITLE = 'Audio Player'

  CANNOT_BE_PLAYED = 'File Cannot Be Played'
  NOT_FOUND = 'No available audio file found'
  NO_SELECTION = 'No file was selected'
  UNREADABLE = 'Couldn’t read the file'
  DIRECTORY_TITLE = 'Directories Cannot Be Played'
  DIRECTORY_MESSAGE = 'Please select a file.'
  IRREGULAR = 'The selected file is not a regular file.'

  attr_reader :app, :file

  def initialize(app, icon_name)
    @app = app
    @icon_name = icon_name
    @file = nil
  end

  def build
    tap do
      window.tap do |win|
        # Upstream puts every window in a group of its own so a modal file
        # dialog in one window leaves the others usable.
        window_group.add_window(win)

        win.content = drag_overlay.build
        win.add_action(open_file_action)
        win.add_action(show_file_action)
      end

      drag_overlay.content = stack

      stack.tap do |pages|
        pages.add_named(empty_state.build, 'empty')
        pages.add_named(error_state.build, 'error')
        pages.visible_child_name = 'empty'
      end

      open_file_action.signal_connect('activate') { open_file }
      show_file_action.signal_connect('activate') { show_file }
    end
  end

  def present = window.present

  # Upstream's load_file: query the file, reject anything that is not a
  # regular file with the matching error page, and otherwise take it as the
  # window's current file.
  def load_file(file)
    file_info(file).then do |info|
      if info.nil?
        show_error(CANNOT_BE_PLAYED, NOT_FOUND)
      else
        accept(file, info.file_type)
      end
    end
  end

  def load_uri(uri) = load_file(Gio::File.new_for_uri(uri))

  def open_file
    file_dialog.open(window, nil) do |dialog, result|
      chosen(dialog, result)
    end
  end

  def show_file
    file.then do |current|
      if current
        Gtk::FileLauncher.new(current).open_containing_folder(window, nil)
      end
    end
  end

  def show_error(title, error)
    tap do
      show_file_action.enabled = false
      stack.visible_child_name = 'error'
      error_state.show_error(title, error)
    end
  end

  def window
    @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
      win.title = TITLE
      win.set_default_size(WIDTH, HEIGHT)
      win.height_request = MIN_HEIGHT
    end
  end

  def window_group = @window_group ||= Gtk::WindowGroup.new

  def drag_overlay
    @drag_overlay ||= DragOverlay.new(
      on_file:  method(:load_file),
      on_error: ->(message) { show_error(CANNOT_BE_PLAYED, message) },
    )
  end

  def stack = @stack ||= Gtk::Stack.new

  def empty_state = @empty_state ||= EmptyState.new(@icon_name)

  def error_state = @error_state ||= ErrorState.new

  def open_file_action = @open_file_action ||= Gio::SimpleAction.new('open-file')

  def show_file_action
    @show_file_action ||= Gio::SimpleAction.new('show-file').tap do |action|
      action.enabled = false
    end
  end

  def file_dialog
    @file_dialog ||= Gtk::FileDialog.new.tap do |dialog|
      dialog.modal = true
      dialog.title = 'Open File'
      dialog.filters = filters
    end
  end

  def filters
    @filters ||= Gio::ListStore.new(Gtk::FileFilter.gtype).tap do |store|
      store.append(audio_filter)
    end
  end

  def audio_filter
    @audio_filter ||= Gtk::FileFilter.new.tap do |filter|
      filter.name = 'Audio files'
      filter.add_mime_type('audio/*')
    end
  end

  private

    def accept(file, type)
      case type
      when Gio::FileType::REGULAR
        @file = file
        show_file_action.enabled = true
      when Gio::FileType::DIRECTORY
        show_error(DIRECTORY_TITLE, DIRECTORY_MESSAGE)
      else
        show_error(CANNOT_BE_PLAYED, IRREGULAR)
      end
    end

    def file_info(file)
      begin
        file.query_info('standard::*', :nofollow_symlinks)
      rescue Gio::Error
        nil
      end
    end

    # The dialog reports a dismissal as an error, which upstream swallows.
    def chosen(dialog, result)
      begin
        dialog.open_finish(result).then do |file|
          if file
            load_file(file)
          else
            show_error(CANNOT_BE_PLAYED, NO_SELECTION)
          end
        end
      rescue Gtk::DialogError::Dismissed
        nil
      rescue StandardError => error
        show_error(UNREADABLE, error)
      end
    end
end
