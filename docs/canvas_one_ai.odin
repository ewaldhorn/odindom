// CANVAS ONE — AI ship & obstacle dodging system.
//
// This was present in GoDOM's original demo/demo.go but dropped from ZigDOM's port; ported here
// directly from the Go source since it's part of what "the demo" actually is.
package main

import "../canvas"
import "../colour"

// ------------------------------------------------------------------------------------------------
MAX_C_ONE_OBSTACLES :: 4

// ------------------------------------------------------------------------------------------------
COneObstacle :: struct {
	origin_x: f32,
	progress: f32,
	speed:    f32,
	active:   bool,
	kind:     u8, // 0=asteroid, 1=bolt, 2=enemy
}

// ------------------------------------------------------------------------------------------------
c_one_obstacles:     [MAX_C_ONE_OBSTACLES]COneObstacle
c_one_spawn_timer:   u32
c_one_ship_x:        f32 = 400
c_one_ship_target_x: f32 = 400
c_one_ship_bank:     f32
c_one_decision_tick: u32
c_one_dodge_score:   u32
c_one_inited:        bool

// ------------------------------------------------------------------------------------------------
max_f32 :: proc "contextless" (a, b: f32) -> f32 {
	return a if a > b else b
}

// ------------------------------------------------------------------------------------------------
init_c_one_ai :: proc "contextless" (w: i32) {
	c_one_ship_x = f32(w) / 2
	c_one_ship_target_x = f32(w) / 2
	c_one_inited = true
}

// ------------------------------------------------------------------------------------------------
spawn_c_one_obstacle :: proc "contextless" (w: i32) {
	for &o in c_one_obstacles {
		if !o.active {
			side: f32 = next_random() % 2 == 0 ? -1 : 1
			spread := f32(next_random() % 260) + 40
			o = COneObstacle {
				origin_x = side * spread,
				progress = 0.02,
				speed    = 0.0045 + f32(next_random() % 10) * 0.0003,
				active   = true,
				kind     = u8(next_random() % 3),
			}
			return
		}
	}
}

// ------------------------------------------------------------------------------------------------
update_c_one_obstacles :: proc "contextless" (w, h, horizon: i32) {
	c_one_spawn_timer += 1
	if c_one_spawn_timer > 280 {
		c_one_spawn_timer = 0
		spawn_c_one_obstacle(w)
	}

	cx := f32(w) / 2
	for &o in c_one_obstacles {
		if !o.active {
			continue
		}
		o.progress += o.speed
		if o.progress >= 1.05 {
			o.active = false
			final_x := cx + o.origin_x
			if abs(final_x - c_one_ship_x) > 45 {
				c_one_dodge_score += 1
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------
update_c_one_ship_ai :: proc "contextless" (w, h, horizon: i32) {
	cx := f32(w) / 2

	best_threat: f32 = 0
	threat_orig_x: f32 = 0

	for &o in c_one_obstacles {
		if !o.active || o.progress < 0.15 {
			continue
		}
		final_x := cx + o.origin_x
		dist := abs(final_x - c_one_ship_x)
		danger_zone: f32 = 100
		threat := o.progress * max_f32(0, 1.0 - dist / danger_zone)
		if threat > best_threat {
			best_threat = threat
			threat_orig_x = o.origin_x
		}
	}

	c_one_decision_tick += 1

	if best_threat > 0.28 && c_one_decision_tick > 30 {
		// Commit to a dodge and don't re-evaluate for a while.
		if threat_orig_x > 0 {
			c_one_ship_target_x = cx - 110 - f32(next_random() % 50)
		} else {
			c_one_ship_target_x = cx + 110 + f32(next_random() % 50)
		}
		c_one_decision_tick = 0
	} else if c_one_decision_tick > 120 {
		// Gentle idle drift back toward center.
		c_one_ship_target_x = cx + f32(int(next_random() % 80) - 40)
		c_one_decision_tick = 0
	}

	margin: f32 = 110
	w_f := f32(w)
	if c_one_ship_target_x < margin {
		c_one_ship_target_x = margin
	}
	if c_one_ship_target_x > w_f - margin {
		c_one_ship_target_x = w_f - margin
	}

	diff := c_one_ship_target_x - c_one_ship_x
	c_one_ship_x += diff * 0.018

	c_one_ship_bank = diff * 0.003
	if c_one_ship_bank > 1.0 {
		c_one_ship_bank = 1.0
	}
	if c_one_ship_bank < -1.0 {
		c_one_ship_bank = -1.0
	}
}

// ------------------------------------------------------------------------------------------------
draw_c_one_obstacle :: proc(o: ^COneObstacle, cx, horizon, h: i32, t: Theme) {
	screen_x := i32(f32(cx) + o.origin_x * o.progress)
	screen_y := i32(f32(horizon) + o.progress * f32(h - 10 - horizon))
	sz := i32(3 + i32(16 * o.progress))

	if screen_y <= horizon || screen_y >= h - 5 {
		return
	}

	final_x := f32(cx) + o.origin_x
	is_near_miss := o.progress > 0.6 && abs(final_x - c_one_ship_x) < 85

	switch o.kind {
	case 0: // asteroid
		col := t.magenta
		if is_near_miss {
			col = colour.White
		}
		canvas.colour_circle(&canvas_one, screen_x, screen_y, sz, col)
		canvas.colour_line(&canvas_one, screen_x - sz - 2, screen_y, screen_x + sz + 2, screen_y, col)
		canvas.colour_line(&canvas_one, screen_x, screen_y - sz, screen_x, screen_y + sz, col)
		canvas.colour_line(&canvas_one, screen_x - sz / 2, screen_y - sz / 2, screen_x + sz / 2, screen_y + sz / 2, col)
	case 1: // energy bolt
		col := t.yellow
		if is_near_miss {
			col = colour.White
		}
		canvas.colour_line(&canvas_one, screen_x, screen_y - sz * 2, screen_x, screen_y + sz, col)
		canvas.colour_line(&canvas_one, screen_x - sz, screen_y - sz, screen_x + sz, screen_y - sz, col)
		canvas.colour_line(&canvas_one, screen_x - sz / 2, screen_y, screen_x + sz / 2, screen_y, col)
	case 2: // enemy ship
		col := t.violet
		ec := t.cyan
		if is_near_miss {
			col = colour.White
			ec = colour.White
		}
		canvas.colour_line(&canvas_one, screen_x - sz * 2, screen_y - sz / 2, screen_x, screen_y + sz, col)
		canvas.colour_line(&canvas_one, screen_x + sz * 2, screen_y - sz / 2, screen_x, screen_y + sz, col)
		canvas.colour_line(&canvas_one, screen_x - sz * 2, screen_y - sz / 2, screen_x + sz * 2, screen_y - sz / 2, ec)
		canvas.colour_line(&canvas_one, screen_x - sz / 2, screen_y - sz / 4, screen_x + sz / 2, screen_y - sz / 4, ec)
	}
}

// ------------------------------------------------------------------------------------------------
draw_c_one_obstacles :: proc(cx, horizon, h: i32, t: Theme) {
	for &o in c_one_obstacles {
		if o.active {
			draw_c_one_obstacle(&o, cx, horizon, h, t)
		}
	}
}

// ------------------------------------------------------------------------------------------------
draw_c_one_hud :: proc(w, h: i32, t: Theme) {
	score := c_one_dodge_score
	hundreds := u8((score / 100) % 10)
	tens := u8((score / 10) % 10)
	ones := u8(score % 10)

	draw_one_text("SCORE", 20, 20, 3, t.cyan)
	draw_one_glyph(u8('0') + hundreds, 86, 20, 3, t.yellow)
	draw_one_glyph(u8('0') + tens, 98, 20, 3, t.yellow)
	draw_one_glyph(u8('0') + ones, 110, 20, 3, t.yellow)
}

// ------------------------------------------------------------------------------------------------
// Tiny-font text renderer for Canvas One's HUD — shares get_glyph_rows() with canvas_three.odin's
// drum-machine labels (same package, one 3×5 bitmap font).
draw_one_text :: proc(text: string, x, y, scale: i32, c: colour.Colour) {
	cursor := x
	for ch in text {
		if ch == ' ' {
			cursor += 4 * scale
		} else {
			draw_one_glyph(u8(ch), cursor, y, scale, c)
			cursor += 4 * scale
		}
	}
}

// ------------------------------------------------------------------------------------------------
draw_one_glyph :: proc(ch: u8, x, y, scale: i32, c: colour.Colour) {
	rows := get_glyph_rows(ch)
	for row, row_idx in rows {
		for col_idx in 0 ..< len(row) {
			if row[col_idx] == '1' {
				canvas.colour_filled_rectangle(&canvas_one, x + i32(col_idx) * scale, y + i32(row_idx) * scale, scale, scale, c)
			}
		}
	}
}
