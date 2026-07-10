// CANVAS TWO — Ball Physics Simulation (600×450, animated, switchable gravity, drag-to-push)
package main

import "../canvas"
import "../colour"
import "../dom"
import "core:fmt"
import "core:math"

// ------------------------------------------------------------------------------------------------
canvas_two_buffer: [600 * 450 * 4]byte
canvas_two:        canvas.Canvas

// ------------------------------------------------------------------------------------------------
MAX_BALLS  :: 14
TRAIL_LEN  :: 10

// ------------------------------------------------------------------------------------------------
Ball :: struct {
	x, y, vx, vy: f32,
	radius:       f32,
	col:          colour.Colour,
}

// ------------------------------------------------------------------------------------------------
balls:        [MAX_BALLS]Ball
ball_trails:  [MAX_BALLS][TRAIL_LEN][2]f32
trail_head:   [MAX_BALLS]int

// ------------------------------------------------------------------------------------------------
// Gravity: 0=down, 1=left, 2=up, 3=right, 4=zero-g.
gravity_mode: int
gravity_mode_names := [5]string{"DOWN", "LEFT", "UP", "RIGHT", "ZERO-G"}

// ------------------------------------------------------------------------------------------------
on_cycle_gravity :: proc() {
	if !is_ready {
		return
	}
	gravity_mode = (gravity_mode + 1) % 5
	update_gravity_button_text()
}

// ------------------------------------------------------------------------------------------------
update_gravity_button_text :: proc() {
	btn := dom.get_element_by_id("gravityButton")
	if !dom.is_valid(btn) {
		return
	}
	dom.set_inner_text(btn, fmt.tprintf("Gravity: %s", gravity_mode_names[gravity_mode]))
}

// ------------------------------------------------------------------------------------------------
init_balls :: proc() {
	w := f32(canvas_two.width)
	h := f32(canvas_two.height)

	// Each row: x%, y%, vx*100, vy*100, radius.
	init_data := [MAX_BALLS][5]i32 {
		{20, 30, 270, -180, 12},
		{70, 20, -300, 120, 14},
		{50, 60, 180, 300, 11},
		{15, 70, -135, -270, 13},
		{80, 75, 330, -90, 9},
		{40, 40, -225, -225, 16},
		{60, 80, 150, 375, 12},
		{30, 15, -375, 150, 10},
		{85, 45, -165, -300, 17},
		{10, 50, 450, 135, 9},
		{55, 25, -270, -120, 13},
		{75, 60, 120, -330, 15},
		{25, 85, 300, 90, 11},
		{90, 10, -195, 255, 12},
	}

	ball_colours := [MAX_BALLS]colour.Colour {
		{r = 0, g = 240, b = 220, a = 255}, // cyan
		{r = 255, g = 0, b = 180, a = 255}, // magenta
		{r = 0, g = 255, b = 100, a = 255}, // green
		{r = 255, g = 230, b = 0, a = 255}, // yellow
		{r = 160, g = 0, b = 255, a = 255}, // violet
		{r = 255, g = 100, b = 0, a = 255}, // orange
		{r = 0, g = 160, b = 255, a = 255}, // sky blue
		{r = 255, g = 0, b = 80, a = 255}, // hot red
		{r = 100, g = 255, b = 200, a = 255}, // mint
		{r = 255, g = 160, b = 0, a = 255}, // amber
		{r = 200, g = 0, b = 255, a = 255}, // purple
		{r = 0, g = 255, b = 255, a = 255}, // electric cyan
		{r = 255, g = 80, b = 180, a = 255}, // pink
		{r = 80, g = 255, b = 0, a = 255}, // lime
	}

	for i in 0 ..< MAX_BALLS {
		d := init_data[i]
		balls[i] = Ball {
			x      = w * f32(d[0]) / 100.0,
			y      = h * f32(d[1]) / 100.0,
			vx     = f32(d[2]) / 100.0,
			vy     = f32(d[3]) / 100.0,
			radius = f32(d[4]),
			col    = ball_colours[i],
		}
		for t in 0 ..< TRAIL_LEN {
			ball_trails[i][t][0] = balls[i].x
			ball_trails[i][t][1] = balls[i].y
		}
		trail_head[i] = 0
	}
}

// ------------------------------------------------------------------------------------------------
update_canvas_two :: proc() {
	w := f32(canvas_two.width)
	h := f32(canvas_two.height)

	dampen: f32 = gravity_mode == 4 ? 1.0 : 0.95 // elastic walls in zero-g

	bg := colour.Colour{r = 8, g = 8, b = 15, a = 255}
	canvas.clear_screen(&canvas_two, bg)

	// Record trail positions before updating physics.
	for i in 0 ..< MAX_BALLS {
		trail_head[i] = (trail_head[i] + 1) % TRAIL_LEN
		ball_trails[i][trail_head[i]][0] = balls[i].x
		ball_trails[i][trail_head[i]][1] = balls[i].y
	}

	// Apply gravity based on mode.
	gx, gy: f32
	switch gravity_mode {
	case 0: gy = 0.08
	case 1: gx = -0.08
	case 2: gy = -0.08
	case 3: gx = 0.08
	}

	for &ball in balls {
		ball.vx += gx
		ball.vy += gy
		ball.x += ball.vx
		ball.y += ball.vy

		r := ball.radius
		if ball.x - r < 0.0 {
			ball.x = r
			ball.vx = abs(ball.vx) * dampen
		}
		if ball.x + r > w {
			ball.x = w - r
			ball.vx = -abs(ball.vx) * dampen
		}
		if ball.y - r < 0.0 {
			ball.y = r
			ball.vy = abs(ball.vy) * dampen
		}
		if ball.y + r > h {
			ball.y = h - r
			ball.vy = -abs(ball.vy) * dampen
		}
	}

	// Ball-to-ball collision (elastic, equal mass).
	for i in 0 ..< MAX_BALLS {
		for j in i + 1 ..< MAX_BALLS {
			ba := &balls[i]
			bb := &balls[j]
			dx := bb.x - ba.x
			dy := bb.y - ba.y
			dist_sq := dx * dx + dy * dy
			min_dist := ba.radius + bb.radius + 1.0

			if dist_sq < min_dist * min_dist && dist_sq > 0.0001 {
				dist := math.sqrt(dist_sq)
				nx := dx / dist
				ny := dy / dist

				overlap := min_dist - dist
				ba.x -= nx * overlap * 0.5
				ba.y -= ny * overlap * 0.5
				bb.x += nx * overlap * 0.5
				bb.y += ny * overlap * 0.5

				dvx := ba.vx - bb.vx
				dvy := ba.vy - bb.vy
				dvn := dvx * nx + dvy * ny
				if dvn > 0 {
					ba.vx -= dvn * nx
					ba.vy -= dvn * ny
					bb.vx += dvn * nx
					bb.vy += dvn * ny
				}
			}
		}
	}

	// Draw trails.
	for i in 0 ..< MAX_BALLS {
		ball := &balls[i]
		for t in 1 ..< TRAIL_LEN {
			idx := (trail_head[i] - t + TRAIL_LEN) % TRAIL_LEN
			tx := i32(ball_trails[i][idx][0])
			ty := i32(ball_trails[i][idx][1])
			alpha := f32(TRAIL_LEN - t) / f32(TRAIL_LEN)
			tr := colour.Colour {
				r = u8(f32(ball.col.r) * alpha * 0.35),
				g = u8(f32(ball.col.g) * alpha * 0.35),
				b = u8(f32(ball.col.b) * alpha * 0.35),
				a = 255,
			}
			trail_r := i32(ball.radius * alpha * 0.75)
			if trail_r < 2 {
				trail_r = 2
			}
			canvas.colour_filled_circle(&canvas_two, tx, ty, trail_r, tr)
		}
	}

	// Draw balls with velocity-based glow.
	for i in 0 ..< MAX_BALLS {
		ball := &balls[i]
		bx := i32(ball.x)
		by := i32(ball.y)
		br := i32(ball.radius)

		speed := math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
		glow_extra := i32(speed * 0.4)
		if glow_extra > 10 {
			glow_extra = 10
		}

		glow := colour.Colour {
			r = max(ball.col.r / 3, 20),
			g = max(ball.col.g / 3, 20),
			b = max(ball.col.b / 3, 20),
			a = 255,
		}
		canvas.colour_filled_circle(&canvas_two, bx, by, br + 4 + glow_extra, glow)
		canvas.colour_filled_circle(&canvas_two, bx, by, br, ball.col)

		hs := i32(ball.radius / 3.0)
		canvas.colour_put_pixel(&canvas_two, bx - hs, by - hs, colour.White)

		if i == 0 {
			canvas.colour_border_circle(&canvas_two, bx, by, br + 8 + glow_extra, 2, colour.White)
		}
	}

	canvas.render(&canvas_two)
}

// ------------------------------------------------------------------------------------------------
// Applies an outward velocity impulse to every ball, away from the tap point. The interaction
// coordinates are reset afterwards so re-fires (e.g. a stray callback) are harmless.
on_canvas_interaction :: proc() {
	if !is_ready {
		return
	}
	if interact_x < 0 || interact_y < 0 {
		return
	}
	ix := f32(interact_x)
	iy := f32(interact_y)
	interact_x = -1
	interact_y = -1

	for &ball in balls {
		dx := ball.x - ix
		dy := ball.y - iy
		dist_sq := dx * dx + dy * dy
		if dist_sq < 1.0 {
			continue
		}
		dist := math.sqrt(dist_sq)
		impulse := min(180.0 / dist, 12.0) // inverse-distance, capped
		ball.vx += (dx / dist) * impulse
		ball.vy += (dy / dist) * impulse
	}
}
