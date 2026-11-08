# frozen_string_literal: true

require 'adwaita'
require_relative 'translation'

# VolumeButton is the mute/volume menu button on the player's bottom bar.
#
# Ported from upstream's src/volume-button.ts and data/volume-button.blp: an
# Adw.Bin around a flat MenuButton whose icon reflects the current volume and
# mute state, opening upward to a popover with a circular mute toggle and a
# horizontal Gtk::Scale from 0 to 1 in steps of 0.2, marked at the midpoint.
#
# Upstream exposes volume/muted as GObject properties the player page binds
# bidirectionally; this port takes callbacks instead (the same adaptation as
# PlaybackRateButton) and exposes #volume= / #muted= so the page can sync the
# button from the stream without re-firing them.
class VolumeButton < Adwaita::Bin
  include Translation

  LOWER = 0.0
  UPPER = 1.0
  STEP = 0.2
  DEFAULT_VOLUME = 0.5

  def initialize(on_volume_change:, on_mute_toggle:)
    super()
    @on_volume_change = on_volume_change
    @on_mute_toggle = on_mute_toggle
    @volume = DEFAULT_VOLUME
    @muted = false
    self.child = menu_button
    update_icons
  end

  attr_reader :volume, :muted

  def volume=(volume)
    @volume = volume.clamp(LOWER, UPPER)
    adjustment.value = @volume
    update_icons
  end

  def muted=(muted)
    @muted = muted
    mute_button.active = muted
    update_icons
  end

  private

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.direction = :up
        button.add_css_class('flat')
        button.add_css_class('numeric')
        button.popover = popover
      end
    end

    def popover
      @popover ||= Gtk::Popover.new.tap do |popover|
        popover.width_request = 250
        popover.child = popover_box
      end
    end

    def popover_box
      @popover_box ||= Gtk::Box.new(:horizontal, 4).tap do |box|
        box.margin_start = 4
        box.margin_end = 4
        box.margin_top = 4
        box.margin_bottom = 4
        box.append(mute_button)
        box.append(scale)
      end
    end

    def mute_button
      @mute_button ||= Gtk::ToggleButton.new.tap do |button|
        button.add_css_class('circular')
        button.add_css_class('flat')
        button.tooltip_text = _('Mute/Unmute')
        button.signal_connect('toggled') { toggle_mute(button.active?) }
      end
    end

    def scale
      @scale ||= Gtk::Scale.new(:horizontal, adjustment).tap do |scale|
        scale.hexpand = true
        scale.add_mark((LOWER + UPPER) / 2, :bottom, nil)
        scale.signal_connect('value-changed') { change_volume(adjustment.value) }
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        DEFAULT_VOLUME,
        LOWER,
        UPPER,
        STEP,
        STEP,
        0,
      )
    end

    def change_volume(value)
      @volume = value.clamp(LOWER, UPPER)
      update_icons
      @on_volume_change.call(@volume)
    end

    def toggle_mute(active)
      @muted = active
      update_icons
      @on_mute_toggle.call(@muted)
    end

    def update_icons
      menu_button.icon_name = menu_button_icon
      mute_button.icon_name = mute_button_icon
      self.tooltip_text = tooltip_text
    end

    def mute_button_icon
      muted ? 'audio-volume-muted-symbolic' : 'audio-volume-high-symbolic'
    end

    def menu_button_icon
      if muted || volume.zero?
        'audio-volume-muted-symbolic'
      elsif volume >= 1.0
        'audio-volume-high-symbolic'
      elsif volume > 0.5
        'audio-volume-medium-symbolic'
      else
        'audio-volume-low-symbolic'
      end
    end

    def tooltip_text
      if muted || volume.zero?
        _('Muted')
      elsif volume >= 1.0
        _('Full Volume')
      else
        format(p_('volume percentage', '%d %%'), (volume * 100).round)
      end
    end
end
