// Package sound provides audio synthesis utilities for the browser.
package sound

import "core:math"

// ------------------------------------------------------------------------------------------------
// SAMPLE_RATE defines the audio sample rate (44.1kHz).
SAMPLE_RATE :: 44100.0

// ------------------------------------------------------------------------------------------------
// fill_click pre-renders a 50ms triangle wave click sound with exponential decay.
fill_click :: proc "contextless" (buf: []f32) {
	freq_start: f32 = 2000.0
	freq_end: f32 = 600.0
	decay_rate: f32 = 20.0

	phase: f32 = 0.0
	buf_len := f32(len(buf))

	for i := 0; i < len(buf); i += 1 {
		t := f32(i) / SAMPLE_RATE
		progress := f32(i) / buf_len
		freq := freq_start + (freq_end - freq_start) * progress

		phase += freq / SAMPLE_RATE
		for phase >= 1.0 {
			phase -= 1.0
		}

		osc: f32
		if phase < 0.5 {
			osc = -1.0 + 4.0 * phase
		} else {
			osc = 3.0 - 4.0 * phase
		}

		decay := math.exp(-decay_rate * t)
		buf[i] = osc * decay * 0.25
	}
}
