# frozen_string_literal: true

require 'gstreamer'

# WaveformGenerator extracts a waveform's peak levels from an audio URI.
#
# Ported from upstream's src/waveform-generator.ts: a small
# `uridecodebin ! audioconvert ! audio/x-raw,channels=1 ! level ! fakesink`
# pipeline that samples an RMS level every 100ms, converts each sample from
# decibels back to a linear value with `10 ** (db / 20)`, and once the
# pipeline reaches end-of-stream normalizes the whole run against its own
# highest peak. #restart tears the pipeline down and clears the result,
# which is what upstream's `reset` does before a new file is discovered.
#
# Upstream exposes the result as a GObject `peaks` property PlayerState binds
# to the waveform's paintable; this port takes an on_peaks_changed callback
# instead, the same adaptation the rest of this house style gives every
# upstream GObject property (see PlaybackRateButton, VolumeButton in this
# same port).
class WaveformGenerator
  # Upstream's APWaveformGenerator#INTERVAL: a 100ms sampling interval, in
  # nanoseconds, for the `level` element.
  INTERVAL_NS = 100_000_000

  attr_reader :peaks

  def initialize
    @peaks = []
    @loaded_peaks = []
    @pipeline = nil
    @bus = nil
    @watch_id = nil
    @on_peaks_changed = []
  end

  def on_peaks_changed(&block)
    @on_peaks_changed << block
  end

  # Upstream's restart: stop watching the old pipeline's bus, drop it to
  # NULL, and clear both the in-progress and published peaks.
  def restart
    teardown
    @loaded_peaks = []
    @peaks = []
    @on_peaks_changed.each(&:call)
  end

  # Upstream's generate_peaks_async: build the pipeline, point the
  # decodebin at `uri`, and start it playing. Peaks arrive as "level"
  # element messages on the bus and are finished off at end-of-stream.
  def generate_peaks_async(uri)
    teardown
    @loaded_peaks = []

    @pipeline = Gst.parse_launch(
      'uridecodebin name=uridecodebin ! audioconvert ! audio/x-raw,channels=1 ! ' \
      "level name=level interval=#{INTERVAL_NS} ! fakesink name=faked qos=false sync=false",
    )

    @pipeline.get_by_name('uridecodebin').set_property('uri', uri)
    @pipeline.set_state(Gst::State::PLAYING)

    @bus = @pipeline.bus
    @bus.add_signal_watch
    @watch_id = @bus.signal_connect('message') { |_bus, message| handle_message(message) }
  end

  private

    def handle_message(message)
      case message.type
      when Gst::MessageType::ELEMENT
        handle_level(message)
      when Gst::MessageType::EOS
        finish
      end
    end

    # Upstream reads the "rms" field's zeroth channel out of the "level"
    # element's structure and converts it from decibels to a linear value.
    def handle_level(message)
      structure = message.structure
      if structure && structure.name == 'level'
        rms = structure.get_value('rms')&.value
        if rms && rms[0]
          @loaded_peaks << (10**(rms[0] / 20.0))
        end
      end
    end

    # Upstream's EOS branch: normalize every sample against the run's own
    # highest peak so the waveform always fills its drawing height.
    def finish
      highest_peak = @loaded_peaks.max || 0

      if highest_peak <= 0
        peak_coefficient = 1
      else
        peak_coefficient = 1.0 / highest_peak
      end

      @peaks = @loaded_peaks.map { |value| value * peak_coefficient }
      @loaded_peaks = []
      @pipeline&.set_state(Gst::State::NULL)
      @on_peaks_changed.each(&:call)
    end

    def teardown
      if @watch_id && @bus
        @bus.disconnect(@watch_id)
        @bus.remove_signal_watch
      end
      @pipeline&.set_state(Gst::State::NULL)
      @watch_id = nil
      @bus = nil
      @pipeline = nil
    end
end
