# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# A direct port of upstream's data/shortcuts-dialog.blp: an Adw.ShortcutsDialog
# with three sections — General, Player and Playback Rate — and the ten items
# it declares, in order. Items upstream gives an `action-name` take their
# accelerator from the application; the ones it spells out as `accelerator`
# are listed here with the same accelerator strings.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'General'       => [
      ['Show Shortcuts', 'app.shortcuts'],
      ['New Window', 'app.new-window'],
      ['Quit', 'app.quit'],
    ],
    'Player'        => [
      ['Open File', 'win.open-file'],
      ['Pause/Play', 'space'],
      ['Go Back 10 Seconds', 'Left'],
      ['Go Forward 10 Seconds', 'Right'],
    ],
    'Playback Rate' => [
      ['Increase Playback Rate', '<Ctrl>plus plus'],
      ['Decrease Playback Rate', '<Ctrl>minus minus'],
      ['Reset Playback Rate', '<Ctrl>0 0'],
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
