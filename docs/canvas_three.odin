// CANVAS THREE — Retro Drum Machine (512×320, animated 16-step sequencer)
package main

import "../canvas"
import "../colour"
import "../dom"

// ------------------------------------------------------------------------------------------------
foreign import odindom_demo_env "odindom_demo_env"

@(default_calling_convention = "contextless")
foreign odindom_demo_env {
	drum_play_hit :: proc(track: u32) ---
}

// ------------------------------------------------------------------------------------------------
DRUM_TRACKS     :: 6
DRUM_STEPS      :: 16
DRUM_CANVAS_W   :: 512
DRUM_CANVAS_H   :: 320
DRUM_GRID_X     :: 74
DRUM_GRID_Y     :: 82
DRUM_CELL_W     :: 24
DRUM_CELL_H     :: 24
DRUM_CELL_GAP   :: 3
DRUM_CELL_PITCH_X :: DRUM_CELL_W + DRUM_CELL_GAP
DRUM_CELL_PITCH_Y :: DRUM_CELL_H + 6

// ------------------------------------------------------------------------------------------------
canvas_three_buffer: [DRUM_CANVAS_W * DRUM_CANVAS_H * 4]byte
canvas_three:        canvas.Canvas

// ------------------------------------------------------------------------------------------------
drum_pattern := [DRUM_TRACKS][DRUM_STEPS]bool {
	{true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false},
	{false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false},
	{true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false},
	{false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, true},
	{false, false, false, false, false, false, true, false, false, false, false, false, false, false, true, false},
	{false, true, false, false, false, true, false, false, false, true, false, false, false, true, false, false},
}

// ------------------------------------------------------------------------------------------------
drum_current_step: u32
drum_playing:      bool
drum_bpm:          u32 = 120
drum_last_step_ms: f64

// ------------------------------------------------------------------------------------------------
drum_labels := [DRUM_TRACKS]string{"K", "SN", "HH", "OH", "CL", "RM"}

drum_neon := [DRUM_TRACKS]colour.Colour {
	{r = 0, g = 240, b = 220, a = 255},
	{r = 255, g = 0, b = 180, a = 255},
	{r = 255, g = 230, b = 0, a = 255},
	{r = 255, g = 153, b = 0, a = 255},
	{r = 160, g = 0, b = 255, a = 255},
	{r = 0, g = 255, b = 100, a = 255},
}

drum_dim := [DRUM_TRACKS]colour.Colour {
	{r = 10, g = 42, b = 40, a = 255},
	{r = 42, g = 0, b = 30, a = 255},
	{r = 42, g = 37, b = 0, a = 255},
	{r = 42, g = 24, b = 0, a = 255},
	{r = 26, g = 0, b = 48, a = 255},
	{r = 0, g = 40, b = 16, a = 255},
}

// ------------------------------------------------------------------------------------------------
on_drum_canvas_click :: proc() {
	if !is_ready {
		return
	}
	if interact_x < 0 || interact_y < 0 {
		return
	}
	rel_x := interact_x - DRUM_GRID_X
	rel_y := interact_y - DRUM_GRID_Y
	interact_x = -1
	interact_y = -1
	if rel_x < 0 || rel_y < 0 {
		return
	}

	step_i := rel_x / DRUM_CELL_PITCH_X
	track_i := rel_y / DRUM_CELL_PITCH_Y
	if step_i < 0 || step_i >= DRUM_STEPS || track_i < 0 || track_i >= DRUM_TRACKS {
		return
	}
	if rel_x % DRUM_CELL_PITCH_X >= DRUM_CELL_W {
		return
	}
	if rel_y % DRUM_CELL_PITCH_Y >= DRUM_CELL_H {
		return
	}

	drum_pattern[track_i][step_i] = !drum_pattern[track_i][step_i]
	if drum_pattern[track_i][step_i] {
		drum_play_hit(u32(track_i))
	}
}

// ------------------------------------------------------------------------------------------------
on_drum_play_pause :: proc() {
	if !is_ready {
		return
	}
	drum_playing = !drum_playing
	set_drum_button_text()
	if drum_playing {
		drum_last_step_ms = dom.now()
		play_current_drum_step()
	}
}

// ------------------------------------------------------------------------------------------------
set_drum_button_text :: proc() {
	btn := dom.get_element_by_id("drumPlayButton")
	if !dom.is_valid(btn) {
		return
	}
	dom.set_inner_text(btn, "⏹ Drum Machine" if drum_playing else "▶ Drum Machine")
}

// ------------------------------------------------------------------------------------------------
// Advances the sequencer using wall-clock time (dom.now(), i.e. performance.now()) rather than a
// frame-tick count, so BPM stays accurate regardless of the browser's actual frame rate.
update_drum_sequencer :: proc() {
	if !drum_playing {
		return
	}
	step_ms := 60000.0 / f64(drum_bpm) / 4.0
	now := dom.now()
	for now - drum_last_step_ms >= step_ms {
		drum_last_step_ms += step_ms
		drum_current_step = (drum_current_step + 1) % DRUM_STEPS
		play_current_drum_step()
	}
}

// ------------------------------------------------------------------------------------------------
play_current_drum_step :: proc() {
	for track in 0 ..< DRUM_TRACKS {
		if drum_pattern[track][drum_current_step] {
			drum_play_hit(u32(track))
		}
	}
}

// ------------------------------------------------------------------------------------------------
perform_demo_on_canvas_three :: proc() {
	update_drum_sequencer()

	bg := colour.Colour{r = 5, g = 5, b = 16, a = 255}
	panel := colour.Colour{r = 12, g = 12, b = 34, a = 255}
	border := colour.Colour{r = 0, g = 240, b = 220, a = 255}
	muted := colour.Colour{r = 68, g = 68, b = 112, a = 255}

	canvas.clear_screen(&canvas_three, bg)
	canvas.colour_rectangle(&canvas_three, 8, 8, DRUM_CANVAS_W - 16, DRUM_CANVAS_H - 16, 2, border)
	canvas.colour_rectangle(&canvas_three, 14, 14, DRUM_CANVAS_W - 28, DRUM_CANVAS_H - 28, 1, panel)

	draw_tiny_text("DRUM 120 BPM", 26, 26, 2, border)
	if drum_playing {
		draw_tiny_text("RUN", 400, 26, 2, drum_neon[5])
	} else {
		draw_tiny_text("PAUSE", 400, 26, 2, muted)
	}

	for step in 0 ..< DRUM_STEPS {
		x := i32(DRUM_GRID_X + step * DRUM_CELL_PITCH_X)
		step_label_y := i32(DRUM_GRID_Y - 24)
		if step % 4 == 0 {
			canvas.colour_line(&canvas_three, x - 5, DRUM_GRID_Y - 6, x - 5, DRUM_GRID_Y + DRUM_TRACKS * DRUM_CELL_PITCH_Y - 2, muted)
		}
		draw_tiny_digit(u8((step + 1) % 10), x + 8, step_label_y, 1, muted)
	}

	for track in 0 ..< DRUM_TRACKS {
		y := i32(DRUM_GRID_Y + track * DRUM_CELL_PITCH_Y)
		draw_tiny_text(drum_labels[track], 24, y + 8, 2, drum_neon[track])
		canvas.colour_filled_circle(&canvas_three, 60, y + 12, 4, drum_neon[track])

		for step in 0 ..< DRUM_STEPS {
			x := i32(DRUM_GRID_X + step * DRUM_CELL_PITCH_X)
			cell_colour := drum_neon[track] if drum_pattern[track][step] else drum_dim[track]
			canvas.colour_filled_rectangle(&canvas_three, x, y, DRUM_CELL_W, DRUM_CELL_H, cell_colour)
			canvas.colour_rectangle(&canvas_three, x, y, DRUM_CELL_W, DRUM_CELL_H, 1, panel)

			if drum_pattern[track][step] {
				canvas.colour_filled_rectangle(&canvas_three, x + 5, y + 5, DRUM_CELL_W - 10, DRUM_CELL_H - 10, colour.White)
				canvas.colour_filled_rectangle(&canvas_three, x + 7, y + 7, DRUM_CELL_W - 14, DRUM_CELL_H - 14, drum_neon[track])
			}
		}
	}

	playhead_x := i32(DRUM_GRID_X + int(drum_current_step) * DRUM_CELL_PITCH_X)
	canvas.colour_rectangle(&canvas_three, playhead_x - 2, DRUM_GRID_Y - 4, DRUM_CELL_W + 4, DRUM_TRACKS * DRUM_CELL_PITCH_Y - 4, 2, colour.White)
	canvas.colour_filled_rectangle(&canvas_three, playhead_x + 2, DRUM_GRID_Y + DRUM_TRACKS * DRUM_CELL_PITCH_Y + 4, DRUM_CELL_W - 4, 5, colour.White)
	canvas.render(&canvas_three)
}

// ------------------------------------------------------------------------------------------------
// Tiny 3×5 bitmap font
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
get_glyph_rows :: proc(ch: u8) -> [5]string {
	switch ch {
	case '0': return [5]string{"111", "101", "101", "101", "111"}
	case '1': return [5]string{"010", "110", "010", "010", "111"}
	case '2': return [5]string{"111", "001", "111", "100", "111"}
	case '3': return [5]string{"111", "001", "111", "001", "111"}
	case '4': return [5]string{"101", "101", "111", "001", "001"}
	case '5': return [5]string{"111", "100", "111", "001", "111"}
	case '6': return [5]string{"111", "100", "111", "101", "111"}
	case '7': return [5]string{"111", "001", "010", "010", "010"}
	case '8': return [5]string{"111", "101", "111", "101", "111"}
	case '9': return [5]string{"111", "101", "111", "001", "111"}
	case 'A': return [5]string{"010", "101", "111", "101", "101"}
	case 'B': return [5]string{"110", "101", "110", "101", "110"}
	case 'C': return [5]string{"111", "100", "100", "100", "111"}
	case 'D': return [5]string{"110", "101", "101", "101", "110"}
	case 'E': return [5]string{"111", "100", "110", "100", "111"}
	case 'H': return [5]string{"101", "101", "111", "101", "101"}
	case 'I': return [5]string{"111", "010", "010", "010", "111"}
	case 'K': return [5]string{"101", "101", "110", "101", "101"}
	case 'L': return [5]string{"100", "100", "100", "100", "111"}
	case 'M': return [5]string{"101", "111", "111", "101", "101"}
	case 'N': return [5]string{"101", "111", "111", "111", "101"}
	case 'O': return [5]string{"111", "101", "101", "101", "111"}
	case 'P': return [5]string{"110", "101", "110", "100", "100"}
	case 'R': return [5]string{"110", "101", "110", "101", "101"}
	case 'S': return [5]string{"111", "100", "111", "001", "111"}
	case 'U': return [5]string{"101", "101", "101", "101", "111"}
	case: return [5]string{"000", "000", "000", "000", "000"}
	}
}

// ------------------------------------------------------------------------------------------------
draw_tiny_text :: proc(text: string, x, y, scale: i32, c: colour.Colour) {
	cursor := x
	for ch in text {
		if ch == ' ' {
			cursor += 4 * scale
		} else {
			draw_tiny_glyph(u8(ch), cursor, y, scale, c)
			cursor += 4 * scale
		}
	}
}

// ------------------------------------------------------------------------------------------------
draw_tiny_digit :: proc(digit: u8, x, y, scale: i32, c: colour.Colour) {
	draw_tiny_glyph('0' + digit, x, y, scale, c)
}

// ------------------------------------------------------------------------------------------------
draw_tiny_glyph :: proc(ch: u8, x, y, scale: i32, c: colour.Colour) {
	rows := get_glyph_rows(ch)
	for row, row_idx in rows {
		for col_idx in 0 ..< len(row) {
			if row[col_idx] == '1' {
				canvas.colour_filled_rectangle(&canvas_three, x + i32(col_idx) * scale, y + i32(row_idx) * scale, scale, scale, c)
			}
		}
	}
}
