# frozen_string_literal: true

require 'adwaita'
require_relative 'translation'

# HeaderBar is the header bar every page of the window carries.
#
# Ported from upstream's src/header.ts and data/header.blp: an Adw.Bin around
# an Adw.HeaderBar whose only packed child is the primary menu button, plus a
# title/subtitle pair that is rendered as an Adw.WindowTitle only once a title
# has actually been set.
class HeaderBar < Adwaita::Bin
  include Translation

  # The primary menu: three sections, five items, in upstream's order. The
  # third element of each item is upstream's `hidden-when: "action-disabled"`,
  # which only "Show in Files" carries.
  MENU_SECTIONS = [
    [
      [_('New Window'), 'app.new-window', false],
      [_('Open…'), 'win.open-file', false],
    ],
    [
      [_('Show in _Files'), 'win.show-file', true],
    ],
    [
      [_('_Keyboard Shortcuts'), 'app.shortcuts', false],
      [_('_About Audio Player'), 'app.about', false],
    ],
  ].freeze

  attr_reader :title, :subtitle

  def initialize
    super()
    @title = nil
    @subtitle = nil
  end

  def build
    tap do |bin|
      bin.child = header_bar

      header_bar.tap { |bar| bar.pack_start(menu_button) }
    end
  end

  def title=(title)
    @title = title
    render_title
  end

  def subtitle=(subtitle)
    @subtitle = subtitle
    render_title
  end

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def menu_button
    @menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'open-menu-symbolic'
      button.menu_model = primary_menu
      button.primary = true
      button.tooltip_text = _('Main Menu')
    end
  end

  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      MENU_SECTIONS.each { |items| menu.append_section(nil, section(items)) }
    end
  end

  private

    def render_title
      if @title.nil? || @title.empty?
        header_bar.title_widget = nil
      else
        window_title.tap do |widget|
          widget.title = @title
          widget.subtitle = @subtitle.to_s
          header_bar.title_widget = widget
        end
      end
    end

    def window_title = @window_title ||= Adwaita::WindowTitle.new('', '')

    def section(items)
      Gio::Menu.new.tap do |menu|
        items.each { |label, action, hidden| menu.append_item(item(label, action, hidden)) }
      end
    end

    def item(label, action, hidden_when_disabled)
      Gio::MenuItem.new(label, action).tap do |entry|
        if hidden_when_disabled
          entry.set_attribute_value('hidden-when', GLib::Variant.new('action-disabled'))
        end
      end
    end
end
