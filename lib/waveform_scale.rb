# frozen_string_literal: true

require 'adwaita'
require_relative 'waveform_bar_chart'

# WaveformScale is a slider showing an audio waveform behind the handle.
#
# Ported from upstream's src/waveform-scale.ts: a widget drawing a bar chart
# built from WaveformBarChart, painted in the accent color up to the current
# playback position and in a dimmed foreground color after it, with a thin
# line marking the position itself. Clicking or dragging anywhere along it
# seeks there and fires a position-changed callback. Dropping in new peaks
# animates the bars growing in from flat.
#
# Two differences from upstream, both the same adaptation the Thermometer
# class in the gnome-weather port documents: the Ruby bindings expose
# neither Gtk::Widget vfunc overrides nor a custom CSS element name, so this
# is a Gtk::DrawingArea with a draw_func rather than a Gtk::Widget subclass
# overriding vfunc_snapshot, and GSK's push_mask/pop duotone trick is
# replaced with painting each bar directly in whichever of the two colors it
# falls under — the same visual result without a mask node.
class WaveformScale < Gtk::DrawingArea
  GROW_DURATION_MS = 250
  GROW_FRAME_MS = 16

  attr_reader :bar_chart, :position

  def initialize
    super()
    @bar_chart = WaveformBarChart.new
    @position = 0.0
    @height_mul = 0.0
    @grow_source = nil
    @on_position_changed = []

    bar_chart.on_peaks_changed { animate_grow_in }

    set_content_height(64)
    set_draw_func { |_area, cr, width, height| draw(cr, width, height) }

    add_controller(click_gesture)
    add_controller(drag_gesture)
  end

  def on_position_changed(&block)
    @on_position_changed << block
  end

  # Upstream's position setter: sync the handle from the stream's timestamp
  # without firing position-changed, which is reserved for the user
  # dragging or clicking the scale themselves.
  def position=(position)
    @position = position.clamp(0.0, 1.0)
    queue_draw
  end

  def peaks=(peaks)
    bar_chart.peaks = peaks
  end

  private

    def click_gesture
      @click_gesture ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.signal_connect('pressed') { |_g, _n_press, x, _y| seek_to(x) }
      end
    end

    def drag_gesture
      @drag_gesture ||= Gtk::GestureDrag.new.tap do |gesture|
        gesture.signal_connect('drag-begin') { |g| g.set_state(:claimed) }
        gesture.signal_connect('drag-update') do |g, offset_x, _offset_y|
          seek_to(g.start_point[0] + offset_x)
        end
      end
    end

    def seek_to(x)
      current_width = width
      if current_width > 0
        self.position = (x / current_width).clamp(0.0, 1.0)
        @on_position_changed.each { |block| block.call(position) }
      end
    end

    # Upstream's Adw.TimedAnimation driving height-mul: a plain tick timer
    # since there is no GObject property for Adw to animate on this widget.
    def animate_grow_in
      if @grow_source
        GLib::Source.remove(@grow_source)
      end

      @height_mul = 0.0
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @grow_source = GLib::Timeout.add(GROW_FRAME_MS) do
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        progress = (elapsed * 1000 / GROW_DURATION_MS).clamp(0.0, 1.0)
        @height_mul = progress
        queue_draw

        if progress >= 1.0
          @grow_source = nil
          false
        else
          true
        end
      end
    end

    def draw(cr, width, height)
      if width > 0 && height > 0
        draw_bars(cr, width, height)
      end
    end

    def draw_bars(cr, width, height)
      left_color = Adwaita::StyleManager.default.accent_color_rgba
      right_color = dimmed_foreground_color
      play_x = (width * position).round

      bar_chart.bars(width, height * @height_mul).each do |x, bar_height|
        top = (height - bar_height) / 2
        if x < play_x
          cr.set_source_rgba(*rgba_components(left_color))
        else
          cr.set_source_rgba(*rgba_components(right_color))
        end
        cr.rectangle(
          x,
          top,
          bar_chart.bar_width,
          bar_height,
        )
        cr.fill
      end

      cr.set_source_rgba(*rgba_components(left_color))
      cr.rectangle(
        play_x,
        0,
        2,
        height,
      )
      cr.fill
    end

    def dimmed_foreground_color
      color.tap do |rgba|
        if Adwaita::StyleManager.default.high_contrast?
          rgba.alpha *= 0.9
        else
          rgba.alpha *= 0.55
        end
      end
    end

    def rgba_components(rgba) = [rgba.red, rgba.green, rgba.blue, rgba.alpha]
end
