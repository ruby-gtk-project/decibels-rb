# frozen_string_literal: true

require 'adwaita'
require_relative 'translation'

# ShortcutsDialog lists the keyboard shortcuts.
#
# A direct port of upstream's data/shortcuts-dialog.blp: an Adw.ShortcutsDialog
# with three sections — General, Player and Playback Rate — and the ten items
# it declares, in order. Items upstream gives an `action-name` take their
# accelerator from the application; the ones it spells out as `accelerator`
# are listed here with the same accelerator strings. Every title and label
# carries upstream's own `C_("shortcut window", ...)` context — ported here
# as Translation#p_, the name ruby-gettext's extractor recognizes — since
# the same English word (e.g. "Open File") can translate differently inside
# a shortcuts window than it would elsewhere.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  include Translation

  SECTIONS = {
    p_('shortcut window', 'General')       => [
      [p_('shortcut window', 'Show Shortcuts'), 'app.shortcuts'],
      [p_('shortcut window', 'New Window'), 'app.new-window'],
      [p_('shortcut window', 'Quit'), 'app.quit'],
    ],
    p_('shortcut window', 'Player')        => [
      [p_('shortcut window', 'Open File'), 'win.open-file'],
      [p_('shortcut window', 'Pause/Play'), 'space'],
      [p_('shortcut window', 'Go Back 10 Seconds'), 'Left'],
      [p_('shortcut window', 'Go Forward 10 Seconds'), 'Right'],
    ],
    p_('shortcut window', 'Playback Rate') => [
      [p_('shortcut window', 'Increase Playback Rate'), '<Ctrl>plus plus'],
      [p_('shortcut window', 'Decrease Playback Rate'), '<Ctrl>minus minus'],
      [p_('shortcut window', 'Reset Playback Rate'), '<Ctrl>0 0'],
    ],
  }.freeze

  # Upstream's items are either `action-name:` or `accelerator:`; an entry
  # naming an action always looks like "scope.action".
  ACTION = /\A[a-z]+\.[a-z-]+\z/

  def build
    tap do |dialog|
      SECTIONS.each { |title, items| dialog.add(section(title, items)) }
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |group|
        group.title = title
        items.each { |label, accelerator| group.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — the Ruby bindings advertise the
    # signature as "title: utf8, accelerator: utf8" but only accept it
    # positionally. An item naming an action is built with an empty
    # accelerator and has its action set afterwards.
    def item(label, accelerator)
      Adwaita::ShortcutsItem.new(label, '').tap do |entry|
        if ACTION.match?(accelerator)
          entry.action_name = accelerator
        else
          entry.accelerator = accelerator
        end
      end
    end
end
