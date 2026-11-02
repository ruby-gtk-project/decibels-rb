# frozen_string_literal: true

require 'adwaita'
require_relative 'header_bar'

# EmptyState is the page shown before any file has been opened.
#
# Ported from upstream's src/empty.ts and data/empty.blp: an Adw.Bin holding a
# toolbar view whose top bar is the shared header bar and whose content is an
# Adw.StatusPage with the application's own symbolic icon and a pill
# suggested-action button bound to win.open-file.
class EmptyState < Adwaita::Bin
  TITLE = 'Play Audio Files'
  DESCRIPTION = 'Drag and drop audio files here'

  attr_reader :header_bar

  def initialize(icon_name)
    super()
    @icon_name = icon_name
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

          box.tap { |content| content.append(open_button) }
        end
      end
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = @icon_name
      page.title = TITLE
      page.description = DESCRIPTION
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 12)

  def open_button
    @open_button ||= Gtk::Button.new(label: '_Open…').tap do |button|
      button.use_underline = true
      button.action_name = 'win.open-file'
      button.can_shrink = true
      button.halign = :center
      button.add_css_class('pill')
      button.add_css_class('suggested-action')
    end
  end
end
