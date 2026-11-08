# frozen_string_literal: true

require 'adwaita'
require_relative 'header_bar'
require_relative 'translation'

# ErrorState is the page shown when a file cannot be played.
#
# Ported from upstream's src/error.ts and data/error.blp: an Adw.Bin holding a
# toolbar view over an Adw.StatusPage with the custom no-sound-symbolic icon
# and a pill suggested-action button that re-opens the file dialog. The
# status page's title carries the error's headline and its description the
# message, exactly as upstream's show_error does.
class ErrorState < Adwaita::Bin
  include Translation

  TITLE = _('File Cannot Be Played')
  UNKNOWN_ERROR = _('An unknown error happened')

  attr_reader :header_bar

  def initialize
    super()
    @header_bar = HeaderBar.new
  end

  def build
    tap do |bin|
      bin.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar.build)
        view.content = status_page

        status_page.tap do |page|
          page.child = box

          box.tap { |content| content.append(try_again_button) }
        end
      end
    end
  end

  # `error` is upstream's `unknown`: a GLib::Error, a Ruby exception, a plain
  # string, or nothing at all.
  def show_error(title, error)
    tap do
      status_page.title = title
      status_page.description = message_for(error)
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'no-sound-symbolic'
      page.title = TITLE
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 12)

  def try_again_button
    @try_again_button ||= Gtk::Button.new(label: _('_Try Again…')).tap do |button|
      button.use_underline = true
      button.action_name = 'win.open-file'
      button.can_shrink = true
      button.halign = :center
      button.add_css_class('pill')
      button.add_css_class('suggested-action')
    end
  end

  private

    def message_for(error)
      case error
      when nil then UNKNOWN_ERROR
      when String then error
      when GLib::Error, StandardError then error.message
      else error.to_s
      end
    end
end
