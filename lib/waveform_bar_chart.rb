# frozen_string_literal: true

# WaveformBarChart computes an audio waveform's bars for drawing.
#
# Ported from upstream's src/waveform-bar-chart.ts, a Gdk.Paintable that
# turns a flat array of peak values (0..1) into equidistant bars, mipmapping
# the data down when fewer bars are needed than were supplied and linearly
# interpolating between peaks when more are needed than were supplied.
#
# The Ruby bindings cannot implement a GInterface's vfuncs (see WorldModel's
# note in the gnome-contacts port for the same limitation), so this is a
# plain Ruby object rather than a real Gdk::Paintable: instead of painting
# itself, it hands back the bar geometry — an array of [x, height] pairs for
# a given width — and WaveformScale paints them. The mipmap/interpolation
# algorithm itself is unchanged from upstream.
class WaveformBarChart
  DEFAULT_BAR_WIDTH = 2.0
  DEFAULT_BAR_PADDING = 1.0
  DEFAULT_MIPMAP_BIAS = 0.25

  attr_reader :bar_width, :bar_padding, :mipmap_bias

  def initialize(bar_width: DEFAULT_BAR_WIDTH, bar_padding: DEFAULT_BAR_PADDING, mipmap_bias: DEFAULT_MIPMAP_BIAS)
    @bar_width = bar_width
    @bar_padding = bar_padding
    @mipmap_bias = mipmap_bias
    @peaks_mipmaps = []
    @on_peaks_changed = []
  end

  # Fires whenever #peaks= replaces the data, which is what upstream's
  # notify::peaks drives the scale's grow-in animation from.
  def on_peaks_changed(&block)
    @on_peaks_changed << block
  end

  def peaks = @peaks_mipmaps.first

  # An empty array means the same thing as nil here — no peaks to draw —
  # and has to be treated that way: `#bars` only skips drawing when
  # `@peaks_mipmaps` is empty, and `Math.log2(0)` in `#mipmap_for` would
  # crash the next draw if an empty peaks array were wrapped into it as
  # `[[]]` instead.
  def peaks=(peaks)
    if peaks.nil? || peaks.empty?
      @peaks_mipmaps = []
    else
      @peaks_mipmaps = [peaks]
    end
    @on_peaks_changed.each(&:call)
  end

  # Upstream's vfunc_get_intrinsic_width: the width the bars would need at
  # their natural size, with no mipmapping or interpolation.
  def intrinsic_width
    (bar_width + (2 * bar_padding)) * (peaks&.length || 0)
  end

  # Upstream's vfunc_snapshot, split into "compute the bars" (this method)
  # and "paint them" (WaveformScale#draw_waveform). Returns an array of
  # [x, bar_height] pairs, one per bar that fits in `width` at `height`.
  def bars(width, height)
    [].tap do |result|
      unless @peaks_mipmaps.empty?
        bars_into(result, width, height)
      end
    end
  end

  private

    def bars_into(result, width, height)
      bar_total = bar_width + (2 * bar_padding)
      peak_coefficient = height - 1
      needed_bars = [1, (width / bar_total).floor].max
      x_offset = ((width % bar_total) / 2) + bar_padding

      mipmap = mipmap_for(needed_bars)
      scaling_ratio = mipmap.length / needed_bars.to_f

      draw_x = x_offset
      (0..needed_bars).each do |i|
        peaks_x = i * scaling_ratio
        peaks_y1 = mipmap[peaks_x.floor] || 0
        peaks_y2 = mipmap[peaks_x.ceil] || 0
        lerp_factor = peaks_x % 1
        interpolated_value = (peaks_y1 * (1 - lerp_factor)) + (peaks_y2 * lerp_factor)

        bar_height = 1 + (interpolated_value * peak_coefficient)
        result << [draw_x, bar_height]
        draw_x += bar_total
      end
    end

    # Upstream generates mipmaps lazily and caches them on peaks_mipmaps;
    # this keeps that cache but computes the needed level up front instead
    # of growing it level by level inside the draw loop.
    def mipmap_for(needed_bars)
      base = @peaks_mipmaps.first
      required = (Math.log2(base.length) - Math.log2(needed_bars) + mipmap_bias).floor
      used = [0, required].max

      while @peaks_mipmaps.length <= used
        current = @peaks_mipmaps.last
        halved = Array.new(current.length / 2) { |i| (current[i * 2] + current[(i * 2) + 1]) / 2.0 }
        @peaks_mipmaps << halved
      end

      @peaks_mipmaps[used]
    end
end
