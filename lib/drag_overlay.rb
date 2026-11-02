# frozen_string_literal: true

require 'adwaita'

# DragOverlay reveals a drop target over the window's content.
#
# Ported from upstream's src/drag-overlay.ts and data/drag-overlay.blp, which
# in turn is adapted from Amberol's drag_overlay.rs: an Adw.Bin carrying the
# drag-overlay style class, a Gtk.Overlay for the real content and a
# Gtk.Revealer holding the "Drop Here to Open" status page. While a drag hovers
# the revealer crossfades in and the content underneath gains the blurred
# class.
#
# Upstream routes its `content` child through vfunc_add_child so Blueprint can
# write `[content]`; this port exposes that as a `content=` writer instead.
class DragOverlay < Adwaita::Bin
  TITLE = 'Drop Here to Open'
  NO_FILES = 'Unable to access dropped files'

  def initialize(on_file:, on_error:)
    super()
    @on_file = on_file
    @on_error = on_error
    add_css_class('drag-overlay')
  end

  def build
    tap do |bin|
      bin.child = overlay

      overlay.tap do |widget|
        widget.add_overlay(revealer)

        revealer.tap { |rev| rev.child = status_page }
      end

      drop_target.tap do |target|
        target.signal_connect('notify::current-drop') { notify_current_drop }
        target.signal_connect('drop') { |_target, value, _x, _y| dropped(value) }
      end

      bin.add_controller(drop_target)
    end
  end

  def content=(widget)
    overlay.child = widget
  end

  def overlay = @overlay ||= Gtk::Overlay.new

  def revealer
    @revealer ||= Gtk::Revealer.new.tap do |rev|
      rev.can_target = false
      rev.transition_type = :crossfade
    end
  end

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'folder-music-symbolic'
      page.title = TITLE
      page.add_css_class('drag-overlay-status-page')
    end
  end

  def drop_target
    @drop_target ||= Gtk::DropTarget.new(Gdk::FileList.gtype, :copy)
  end

  private

    def notify_current_drop
      drop_target.current_drop.nil?.then do |empty|
        revealer.reveal_child = !empty

        if empty
          overlay.child&.remove_css_class('blurred')
        else
          overlay.child&.add_css_class('blurred')
        end
      end
    end

    def dropped(value)
      if value.is_a?(Gdk::FileList)
        accept(value.files.first)
      else
        false
      end
    end

    def accept(file)
      if file.nil?
        @on_error.call(NO_FILES)
        false
      else
        @on_file.call(file)
        true
      end
    end
end
