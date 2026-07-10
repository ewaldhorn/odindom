// CANVAS ONE — Dark Synthwave Gallery (800×600, static; redrawn on "Refresh" click)
package main

import "../canvas"
import "../colour"
import "core:math"

// ------------------------------------------------------------------------------------------------
canvas_one_buffer: [800 * 600 * 4]byte
canvas_one:        canvas.Canvas

// ------------------------------------------------------------------------------------------------
// Theme definitions for Canvas One
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
Theme :: struct {
	bg, panel, cyan, magenta, yellow, violet, sun_start, sun_end: colour.Colour,
	glow_start, glow_mid, glow_end:                               colour.Colour,
}

// ------------------------------------------------------------------------------------------------
current_theme_idx: int

// ------------------------------------------------------------------------------------------------
themes := []Theme {
	{
		bg = {r = 5, g = 5, b = 16, a = 255},
		panel = {r = 12, g = 12, b = 36, a = 255},
		cyan = {r = 0, g = 240, b = 220, a = 255},
		magenta = {r = 255, g = 0, b = 180, a = 255},
		yellow = {r = 255, g = 230, b = 0, a = 255},
		violet = {r = 160, g = 0, b = 255, a = 255},
		sun_start = {r = 255, g = 230, b = 0, a = 255},
		sun_end = {r = 255, g = 0, b = 180, a = 255},
		glow_start = {r = 255, g = 0, b = 180, a = 31},
		glow_mid = {r = 255, g = 180, b = 30, a = 56},
		glow_end = {r = 255, g = 230, b = 0, a = 82},
	},
	{
		bg = {r = 12, g = 4, b = 4, a = 255},
		panel = {r = 24, g = 8, b = 8, a = 255},
		cyan = {r = 255, g = 120, b = 0, a = 255},
		magenta = {r = 255, g = 40, b = 0, a = 255},
		yellow = {r = 255, g = 200, b = 0, a = 255},
		violet = {r = 100, g = 0, b = 0, a = 255},
		sun_start = {r = 255, g = 200, b = 0, a = 255},
		sun_end = {r = 255, g = 40, b = 0, a = 255},
		glow_start = {r = 255, g = 40, b = 0, a = 31},
		glow_mid = {r = 255, g = 120, b = 0, a = 56},
		glow_end = {r = 255, g = 200, b = 0, a = 82},
	},
	{
		bg = {r = 20, g = 10, b = 30, a = 255},
		panel = {r = 40, g = 20, b = 60, a = 255},
		cyan = {r = 0, g = 255, b = 255, a = 255},
		magenta = {r = 255, g = 105, b = 180, a = 255},
		yellow = {r = 255, g = 255, b = 150, a = 255},
		violet = {r = 138, g = 43, b = 226, a = 255},
		sun_start = {r = 0, g = 255, b = 255, a = 255},
		sun_end = {r = 255, g = 105, b = 180, a = 255},
		glow_start = {r = 255, g = 105, b = 180, a = 31},
		glow_mid = {r = 138, g = 43, b = 226, a = 56},
		glow_end = {r = 0, g = 255, b = 255, a = 82},
	},
	{
		bg = {r = 2, g = 8, b = 4, a = 255},
		panel = {r = 4, g = 16, b = 8, a = 255},
		cyan = {r = 0, g = 255, b = 100, a = 255},
		magenta = {r = 0, g = 180, b = 50, a = 255},
		yellow = {r = 200, g = 255, b = 200, a = 255},
		violet = {r = 0, g = 80, b = 20, a = 255},
		sun_start = {r = 200, g = 255, b = 200, a = 255},
		sun_end = {r = 0, g = 180, b = 50, a = 255},
		glow_start = {r = 0, g = 180, b = 50, a = 31},
		glow_mid = {r = 0, g = 80, b = 20, a = 56},
		glow_end = {r = 0, g = 255, b = 100, a = 82},
	},
}

// ------------------------------------------------------------------------------------------------
perform_demo_on_canvas_one :: proc() {
	w := i32(canvas_one.width)
	h := i32(canvas_one.height)
	horizon := h / 2 + 50
	active_theme := themes[current_theme_idx]

	// Cross-seed the colour PRNG from the demo PRNG so each refresh looks different.
	colour.seed(u64(next_random()) | 1)

	canvas.clear_screen(&canvas_one, active_theme.bg)
	canvas.colour_rectangle(&canvas_one, 8, 8, w - 16, h - 16, 2, active_theme.panel)

	if !c_one_inited {
		init_c_one_ai(w)
	}

	// State-based pixel demo: set_colour + put_pixel (top corner markers).
	canvas.set_colour(&canvas_one, active_theme.cyan)
	canvas.put_pixel(&canvas_one, 10, 10)
	canvas.put_pixel(&canvas_one, w - 11, 10)

	draw_starfield(w, horizon, canvas_one_time, active_theme)
	draw_retro_sun(w / 2, horizon - 20, 85, active_theme)
	draw_mountain_silhouettes(w, horizon, active_theme)
	draw_laser_grid(w, h, horizon, grid_offset, active_theme)

	update_c_one_obstacles(w, h, horizon)
	update_c_one_ship_ai(w, h, horizon)

	draw_c_one_obstacles(w / 2, horizon, h, active_theme)
	draw_vector_ship(i32(c_one_ship_x), h - 55, canvas_one_time, active_theme)
	draw_c_one_hud(w, h, active_theme)
	draw_sun_glow(w, horizon - 20, canvas_one_time, active_theme)

	canvas.render(&canvas_one)
}

// ------------------------------------------------------------------------------------------------
draw_starfield :: proc(w, horizon: i32, time: u32, t: Theme) {
	colour.seed(999)
	for i in 0 ..< 90 {
		rx := i32(colour.random_colour().r) * 3 + i32(colour.random_colour().g) % 50
		ry := i32(colour.random_colour().b) % (horizon - 30)
		if rx < 12 || rx >= w - 12 || ry < 12 {
			continue
		}

		r_val := colour.random_colour().g
		twinkle_phase := (r_val + u8(time % 256)) % 12
		if twinkle_phase == 0 {
			continue
		}

		dice := r_val % 8
		if dice == 0 {
			canvas.colour_put_pixel(&canvas_one, rx, ry, colour.White)
			if twinkle_phase > 2 {
				canvas.colour_put_pixel(&canvas_one, rx - 1, ry, t.cyan)
				canvas.colour_put_pixel(&canvas_one, rx + 1, ry, t.cyan)
				canvas.colour_put_pixel(&canvas_one, rx, ry - 1, t.magenta)
				canvas.colour_put_pixel(&canvas_one, rx, ry + 1, t.magenta)
			}
		} else if dice < 3 {
			canvas.colour_put_pixel(&canvas_one, rx, ry, t.magenta)
		} else if dice < 6 {
			canvas.colour_put_pixel(&canvas_one, rx, ry, t.cyan)
		} else {
			canvas.colour_put_pixel(&canvas_one, rx, ry, colour.White)
		}
	}
}

// ------------------------------------------------------------------------------------------------
draw_retro_sun :: proc(cx, cy, r: i32, t: Theme) {
	for dy := -r; dy <= r; dy += 1 {
		y := cy + dy
		r_f := f64(r)
		dy_f := f64(dy)
		chord := i32(math.sqrt(r_f * r_f - dy_f * dy_f))

		if dy > 0 {
			val := dy % 12
			if val < dy / 6 + 1 {
				continue
			}
		}

		ratio := f32(dy + r) / f32(2 * r)
		red := u8(f32(t.sun_start.r) * (1.0 - ratio) + f32(t.sun_end.r) * ratio)
		green := u8(f32(t.sun_start.g) * (1.0 - ratio) + f32(t.sun_end.g) * ratio)
		blue := u8(f32(t.sun_start.b) * (1.0 - ratio) + f32(t.sun_end.b) * ratio)
		c := colour.Colour{r = red, g = green, b = blue, a = 255}

		canvas.colour_line(&canvas_one, cx - chord, y, cx + chord, y, c)
	}

	// Outline ring around the retro sun — exercises colour_circle.
	canvas.colour_circle(&canvas_one, cx, cy, r + 4, t.cyan)
}

// ------------------------------------------------------------------------------------------------
draw_mountain_silhouettes :: proc(w, horizon: i32, t: Theme) {
	bg_pts := [][2]i32 {
		{8, horizon},
		{120, horizon - 75},
		{240, horizon - 25},
		{350, horizon - 105},
		{480, horizon - 45},
		{620, horizon - 95},
		{710, horizon - 35},
		{w - 8, horizon},
	}

	fg_pts := [][2]i32 {
		{8, horizon},
		{90, horizon - 40},
		{180, horizon - 15},
		{290, horizon - 65},
		{390, horizon - 30},
		{510, horizon - 75},
		{640, horizon - 20},
		{730, horizon - 50},
		{w - 8, horizon},
	}

	for idx in 0 ..< len(bg_pts) - 1 {
		p1 := bg_pts[idx]
		p2 := bg_pts[idx + 1]
		for x := p1[0]; x <= p2[0]; x += 1 {
			ratio := f32(x - p1[0]) / f32(p2[0] - p1[0])
			y := i32((1.0 - ratio) * f32(p1[1]) + ratio * f32(p2[1]))
			canvas.colour_line(&canvas_one, x, y + 1, x, horizon, t.bg)
		}
	}
	for idx in 0 ..< len(bg_pts) - 1 {
		canvas.colour_line(&canvas_one, bg_pts[idx][0], bg_pts[idx][1], bg_pts[idx + 1][0], bg_pts[idx + 1][1], t.violet)
	}

	for idx in 0 ..< len(fg_pts) - 1 {
		p1 := fg_pts[idx]
		p2 := fg_pts[idx + 1]
		for x := p1[0]; x <= p2[0]; x += 1 {
			ratio := f32(x - p1[0]) / f32(p2[0] - p1[0])
			y := i32((1.0 - ratio) * f32(p1[1]) + ratio * f32(p2[1]))
			canvas.colour_line(&canvas_one, x, y + 1, x, horizon, t.bg)
		}
	}
	for idx in 0 ..< len(fg_pts) - 1 {
		canvas.colour_line(&canvas_one, fg_pts[idx][0], fg_pts[idx][1], fg_pts[idx + 1][0], fg_pts[idx + 1][1], t.cyan)
	}
}

// ------------------------------------------------------------------------------------------------
draw_laser_grid :: proc(w, h, horizon: i32, scroll_offset: f64, t: Theme) {
	cx_f := f64(w / 2)
	h_f := f64(horizon)
	h_range := f64(h - horizon)
	curve_phase := f64(canvas_one_time) * 0.003
	curve_amp := 30.0
	segments := 12

	for x := i32(-120); x <= w + 120; x += 35 {
		ex := f64(x)
		for s in 0 ..< segments {
			t0 := f64(s) / f64(segments)
			t1 := f64(s + 1) / f64(segments)

			y0_f := h_f + t0 * h_range
			y1_f := h_f + t1 * h_range

			c0 := curve_amp * t0 * math.sin(t0 * math.PI * 2.0 + curve_phase)
			c1 := curve_amp * t1 * math.sin(t1 * math.PI * 2.0 + curve_phase)

			x0_f := cx_f + (ex - cx_f) * t0 + c0
			x1_f := cx_f + (ex - cx_f) * t1 + c1

			canvas.colour_line(&canvas_one, i32(x0_f), i32(y0_f), i32(x1_f), i32(y1_f), t.violet)
			canvas.colour_line(&canvas_one, i32(x0_f), i32(y0_f + 2), i32(x1_f), i32(y1_f + 2), t.cyan)
		}
	}

	i := 0.0
	for {
		exponent := i + scroll_offset
		dist := 6.0 * math.pow(1.25, exponent)
		y := horizon + i32(dist)
		if y >= h - 8 {
			break
		}
		if y >= horizon + 8 {
			y_f := f64(y)
			prog := (y_f - h_f) / h_range
			c := curve_amp * prog * math.sin(prog * math.PI * 2.0 + curve_phase)
			left := i32(10.0 + c)
			right := i32(f64(w - 10) + c)
			canvas.colour_line(&canvas_one, left, y, right, y, t.violet)
			canvas.colour_line(&canvas_one, left, y, right, y, t.magenta)
		}
		i += 1.0
	}
}

// ------------------------------------------------------------------------------------------------
draw_vector_ship :: proc(cx, cy: i32, time: u32, t: Theme) {
	time_f := f32(time)
	bob_y := i32(4.0 * math.sin(time_f * 0.06))
	sway_x := i32(2.0 * math.cos(time_f * 0.04))

	scx := cx + sway_x
	scy := cy + bob_y

	bank_off := i32(c_one_ship_bank * 14)
	dodging := abs(c_one_ship_bank) > 0.15

	flame_len := i32(26.0 + 4.0 * math.sin(time_f * 0.25))
	if dodging {
		flame_len += 8
	}

	canvas.colour_line(&canvas_one, scx - 8, scy + 12, scx, scy + flame_len, t.cyan)
	canvas.colour_line(&canvas_one, scx + 8, scy + 12, scx, scy + flame_len, t.cyan)
	canvas.colour_line(&canvas_one, scx - 8, scy + 12, scx + 8, scy + 12, t.cyan)
	if dodging {
		canvas.colour_line(&canvas_one, scx - 4, scy + 14, scx, scy + flame_len + 6, t.yellow)
		canvas.colour_line(&canvas_one, scx + 4, scy + 14, scx, scy + flame_len + 6, t.yellow)
	}

	canvas.colour_line(&canvas_one, scx - 35, scy + 10 + bank_off, scx + 35, scy + 10 - bank_off, t.magenta)
	canvas.colour_line(&canvas_one, scx - 35, scy + 10 + bank_off, scx - 12, scy - 20, t.magenta)
	canvas.colour_line(&canvas_one, scx + 35, scy + 10 - bank_off, scx + 12, scy - 20, t.magenta)

	canvas.colour_line(&canvas_one, scx - 12, scy - 20, scx, scy - 40, t.yellow)
	canvas.colour_line(&canvas_one, scx + 12, scy - 20, scx, scy - 40, t.yellow)
	canvas.colour_line(&canvas_one, scx - 12, scy - 20, scx + 12, scy - 20, t.yellow)

	canvas.colour_line(&canvas_one, scx - 6, scy - 10, scx, scy - 25, t.cyan)
	canvas.colour_line(&canvas_one, scx + 6, scy - 10, scx, scy - 25, t.cyan)
	canvas.colour_line(&canvas_one, scx - 6, scy - 10, scx + 6, scy - 10, t.cyan)

	// Demo colour_line_point + colour.convert_to_grayscale + canvas.Point type.
	shadow := t.cyan
	colour.convert_to_grayscale(&shadow)
	tri1 := canvas.Point{x = scx - 4, y = scy + flame_len + 4}
	tri2 := canvas.Point{x = scx + 4, y = scy + flame_len + 4}
	tri3 := canvas.Point{x = scx, y = scy + flame_len + 16}
	canvas.colour_line_point(&canvas_one, tri1, tri2, shadow)
	canvas.colour_line_point(&canvas_one, tri2, tri3, shadow)
	canvas.colour_line_point(&canvas_one, tri1, tri3, shadow)
}

// ------------------------------------------------------------------------------------------------
// draw_sun_glow blends three concentric translucent circles into canvas_one's pixel buffer to
// haze the retro sun, rasterized in-buffer (blend_filled_circle) rather than via Context2D so it
// rides along in the frame's single canvas.render() bridge crossing instead of adding its own.
draw_sun_glow :: proc(w, cy: i32, time: u32, t: Theme) {
	cx := w / 2
	time_f := f64(time)
	pulse := 3.0 * math.sin(time_f * 0.05)

	canvas.blend_filled_circle(&canvas_one, cx, cy, i32(130.0 + pulse), t.glow_start)
	canvas.blend_filled_circle(&canvas_one, cx, cy, i32(95.0 - pulse), t.glow_mid)
	canvas.blend_filled_circle(&canvas_one, cx, cy, i32(50.0 + pulse), t.glow_end)
}
