# frozen_string_literal: true

require 'adwaita'

# PlaybackRateButton is the speedometer menu button that sets playback speed.
#
# Ported from upstream's src/playback-rate-button.ts and
# data/playback-rate-button.blp: an Adw.Bin around a flat MenuButton showing
# a speedometer icon and the current rate ("× 1.0"), whose popover holds a
# vertical, inverted Gtk::Scale from 0.5 to 3.0 in steps of 0.5, marked at
# 0.5, 1, 2 and 3.
#
# Upstream reaches its rate through `window.stream` via GObject property
# bindings set up in vfunc_root; this port takes a callback instead, in
# keeping with the rest of this house style (see DownloadProgress in the
# gnome-podcasts port for the same adaptation), and exposes #rate= so the
# owning page can sync the button back when the stream's rate changes for
# a reason other than this button.
class PlaybackRateButton < Adwaita::Bin
  LOWER = 0.5
  UPPER = 3.0
  STEP = 0.5
  DEFAULT_RATE = 1.0

  def initialize(on_rate_change:)
    super()
    @on_rate_change = on_rate_change
    @rate = DEFAULT_RATE
    self.child = menu_button
  end

  attr_reader :rate

  # Syncs the label and slider from the stream without re-firing the
  # callback, the same role upstream's bind_property(SYNC_CREATE) plays.
  def rate=(rate)
    @rate = rate.clamp(LOWER, UPPER)
    adjustment.value = @rate
    label.label = format('× %.1f', @rate)
  end

  private

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class('flat')
        button.add_css_class('numeric')
        button.child = button_content
        button.popover = popover
      end
    end

    def button_content
      @button_content ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.append(Gtk::Image.new(icon_name: 'speedometer-symbolic'))
        box.append(label)
      end
    end

    def label = @label ||= Gtk::Label.new(format('× %.1f', DEFAULT_RATE))

    def popover
      @popover ||= Gtk::Popover.new.tap do |popover|
        popover.child = popover_box
      end
    end

    def popover_box
      @popover_box ||= Gtk::Box.new(:vertical, 4).tap do |box|
        box.margin_start = 4
        box.margin_end = 4
        box.margin_top = 4
        box.margin_bottom = 4
        box.append(scale)
      end
    end

    def scale
      @scale ||= Gtk::Scale.new(:vertical, adjustment).tap do |scale|
        scale.height_request = 200
        scale.vexpand = true
        scale.inverted = true
        scale.add_mark(LOWER, :bottom, nil)
        scale.add_mark(1.0, :bottom, nil)
        scale.add_mark(2.0, :bottom, nil)
        scale.add_mark(UPPER, :bottom, nil)
        scale.signal_connect('change-value') { |_s, _scroll, value| change_rate(value) }
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        DEFAULT_RATE,
        LOWER,
        UPPER,
        STEP,
        STEP,
        0,
      )
    end

    def change_rate(value)
      self.rate = value
      @on_rate_change.call(rate)
      false
    end
end
