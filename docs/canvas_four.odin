// CANVAS FOUR — Grove & Pond (800×500, animated ducks + trees)
//
// Unlike canvas one/two/three, which rasterize into a pixel buffer and blit it via putImageData,
// this scene is drawn entirely with `canvas_cmd`: every shape, gradient, and sprite blit for the
// whole frame is recorded into one packed byte buffer and flushed to the real Canvas2D context
// with a SINGLE foreign call (see canvas_four_op_count in the HUD, updated below). Trees and ducks
// are baked once into offscreen sprite canvases at init and then just re-blitted every frame —
// cheap regardless of how many WASM<->JS-avoiding draw ops went into the original artwork.
package main

import "../canvas_cmd"
import "../dom"
import "core:fmt"
import "core:math"

CANVAS_FOUR_W :: 800
CANVAS_FOUR_H :: 500
HORIZON_Y :: 320

POND_CX :: 400
POND_CY :: 400
POND_RX :: 320
POND_RY :: 78

SPRITE_TREE_SMALL :: 0
SPRITE_TREE_BIG   :: 1
SPRITE_DUCK       :: 2

TREE_SMALL_W :: 70
TREE_SMALL_H :: 110
TREE_BIG_W   :: 100
TREE_BIG_H   :: 150
DUCK_W       :: 48
DUCK_H       :: 36

// ------------------------------------------------------------------------------------------------
canvas_four_ctx: dom.Handle
canvas_four_cmd: canvas_cmd.Buffer
canvas_four_op_count: int
canvas_four_time: f32

// ------------------------------------------------------------------------------------------------
Tree :: struct {
	x, y: f32,
	big:  bool,
}

MAX_TREES :: 6
trees: [MAX_TREES]Tree

// ------------------------------------------------------------------------------------------------
Duck :: struct {
	x, base_y: f32,
	speed:     f32,
	phase:     f32,
	last_cos:  f32, // bob velocity sign from the previous frame, used to detect the low point of the bob
}

MAX_DUCKS :: 4
DUCK_MIN_X :: POND_CX - POND_RX + 60
DUCK_MAX_X :: POND_CX + POND_RX - 60
ducks: [MAX_DUCKS]Duck

// ------------------------------------------------------------------------------------------------
Ripple :: struct {
	x, y: f32,
	age:  f32, // seconds since spawn; -1 = inactive
}

MAX_RIPPLES :: 6
RIPPLE_LIFETIME :: 1.2
ripples: [MAX_RIPPLES]Ripple

// ------------------------------------------------------------------------------------------------
init_canvas_four :: proc() {
	parent := dom.get_element_by_id("canvasFourDiv")
	canvas_h := dom.canvas_create(parent, CANVAS_FOUR_W, CANVAS_FOUR_H)
	canvas_four_ctx = dom.canvas_get_context(canvas_h)

	trees = [MAX_TREES]Tree {
		{x = 40, y = HORIZON_Y, big = false},
		{x = 130, y = HORIZON_Y, big = true},
		{x = 690, y = HORIZON_Y, big = true},
		{x = 760, y = HORIZON_Y, big = false},
		{x = 220, y = HORIZON_Y - 6, big = false},
		{x = 600, y = HORIZON_Y - 6, big = false},
	}

	ducks = [MAX_DUCKS]Duck {
		{x = 150, base_y = 400, speed = 26, phase = 0.0},
		{x = 420, base_y = 420, speed = -20, phase = 1.4},
		{x = 300, base_y = 440, speed = 18, phase = 2.8},
		{x = 560, base_y = 405, speed = -24, phase = 4.2},
	}

	for &r in ripples {
		r.age = -1
	}

	bake_canvas_four_sprites()
}

// ------------------------------------------------------------------------------------------------
// bake_canvas_four_sprites records tree and duck artwork once into offscreen sprite canvases and
// flushes immediately. Every subsequent frame just re-blits these sprites (draw_sprite*) instead
// of re-encoding the underlying paths/gradients, keeping the per-frame buffer tiny.
bake_canvas_four_sprites :: proc() {
	b := &canvas_four_cmd
	canvas_cmd.reset(b)

	bake_tree_sprite(b, SPRITE_TREE_SMALL, TREE_SMALL_W, TREE_SMALL_H, 0.85)
	bake_tree_sprite(b, SPRITE_TREE_BIG, TREE_BIG_W, TREE_BIG_H, 1.0)
	bake_duck_sprite(b, SPRITE_DUCK, DUCK_W, DUCK_H)

	canvas_cmd.flush(canvas_four_ctx, b)
}

// ------------------------------------------------------------------------------------------------
bake_tree_sprite :: proc(b: ^canvas_cmd.Buffer, id: u16, w, h: u16, tint: f32) {
	canvas_cmd.bake_begin(b, id, w, h)

	fw := f32(w)
	fh := f32(h)
	trunk_w := fw * 0.18
	trunk_h := fh * 0.32

	canvas_cmd.set_fill(b, "#5b3a22")
	canvas_cmd.fill_rect(b, fw / 2 - trunk_w / 2, fh - trunk_h, trunk_w, trunk_h)

	canopy_colours := [3]string{"#1f5c2e", "#2c7a3d", "#3f9650"}
	cy := fh - trunk_h
	for i in 0 ..< 3 {
		r := fw * (0.30 - f32(i) * 0.03) * tint
		ox := fw / 2 + f32(i - 1) * fw * 0.14
		oy := cy - f32(i) * fh * 0.12 - r * 0.5
		canvas_cmd.set_fill(b, canopy_colours[i])
		canvas_cmd.begin_path(b)
		canvas_cmd.arc(b, ox, oy, r, 0, math.TAU)
		canvas_cmd.fill(b)
	}

	canvas_cmd.bake_end(b)
}

// ------------------------------------------------------------------------------------------------
bake_duck_sprite :: proc(b: ^canvas_cmd.Buffer, id: u16, w, h: u16) {
	canvas_cmd.bake_begin(b, id, w, h)

	fw := f32(w)
	fh := f32(h)

	canvas_cmd.set_fill(b, "#ffd23d")
	canvas_cmd.begin_path(b)
	canvas_cmd.ellipse(b, fw * 0.5, fh * 0.62, fw * 0.40, fh * 0.34, 0, 0, math.TAU)
	canvas_cmd.fill(b)

	canvas_cmd.set_fill(b, "#f2b705")
	canvas_cmd.begin_path(b)
	canvas_cmd.ellipse(b, fw * 0.44, fh * 0.60, fw * 0.19, fh * 0.18, 0.3, 0, math.TAU)
	canvas_cmd.fill(b)

	canvas_cmd.set_fill(b, "#ffd23d")
	canvas_cmd.begin_path(b)
	canvas_cmd.arc(b, fw * 0.78, fh * 0.32, fh * 0.24, 0, math.TAU)
	canvas_cmd.fill(b)

	canvas_cmd.set_fill(b, "#f5a623")
	canvas_cmd.begin_path(b)
	canvas_cmd.move_to(b, fw * 0.94, fh * 0.30)
	canvas_cmd.line_to(b, fw * 1.04, fh * 0.34)
	canvas_cmd.line_to(b, fw * 0.94, fh * 0.40)
	canvas_cmd.close_path(b)
	canvas_cmd.fill(b)

	canvas_cmd.set_fill(b, "#222222")
	canvas_cmd.begin_path(b)
	canvas_cmd.arc(b, fw * 0.83, fh * 0.28, fh * 0.035, 0, math.TAU)
	canvas_cmd.fill(b)

	canvas_cmd.bake_end(b)
}

// ------------------------------------------------------------------------------------------------
// update_canvas_four re-records the whole scene into one buffer and flushes it with a single
// foreign call. canvas_four_op_count tallies the commands that went into that one call, so the HUD
// can show what a naive per-op bridge crossing would have cost.
update_canvas_four :: proc() {
	if !is_ready {
		return
	}

	b := &canvas_four_cmd
	canvas_cmd.reset(b)
	canvas_four_op_count = 0
	canvas_four_time += 1.0 / 60.0

	draw_canvas_four_sky(b)
	draw_canvas_four_ground(b)
	draw_canvas_four_pond(b)
	draw_canvas_four_trees(b)
	draw_canvas_four_ripples(b)
	draw_canvas_four_ducks(b)

	canvas_cmd.flush(canvas_four_ctx, b)
	update_canvas_four_hud()
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_sky :: proc(b: ^canvas_cmd.Buffer) {
	canvas_cmd.linear_gradient(b, 0, 0, 0, 0, HORIZON_Y)
	canvas_cmd.add_color_stop(b, 0, 0.0, "#ffd9a0")
	canvas_cmd.add_color_stop(b, 0, 0.5, "#ffb6c9")
	canvas_cmd.add_color_stop(b, 0, 1.0, "#9fd4ff")
	canvas_cmd.use_gradient_fill(b, 0)
	canvas_cmd.fill_rect(b, 0, 0, CANVAS_FOUR_W, HORIZON_Y)
	canvas_four_op_count += 5

	sun_x: f32 = 640
	sun_y: f32 = 90
	canvas_cmd.radial_gradient(b, 1, sun_x, sun_y, 0, sun_x, sun_y, 120)
	canvas_cmd.add_color_stop(b, 1, 0.0, "#fff6d8")
	canvas_cmd.add_color_stop(b, 1, 1.0, "rgba(255,246,216,0)")
	canvas_cmd.use_gradient_fill(b, 1)
	canvas_cmd.begin_path(b)
	canvas_cmd.arc(b, sun_x, sun_y, 120, 0, math.TAU)
	canvas_cmd.fill(b)
	canvas_four_op_count += 6

	canvas_cmd.set_fill(b, "#fff2c4")
	canvas_cmd.begin_path(b)
	canvas_cmd.arc(b, sun_x, sun_y, 34, 0, math.TAU)
	canvas_cmd.fill(b)
	canvas_four_op_count += 3
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_ground :: proc(b: ^canvas_cmd.Buffer) {
	canvas_cmd.linear_gradient(b, 2, 0, HORIZON_Y, 0, CANVAS_FOUR_H)
	canvas_cmd.add_color_stop(b, 2, 0.0, "#4d8c3f")
	canvas_cmd.add_color_stop(b, 2, 1.0, "#2f6329")
	canvas_cmd.use_gradient_fill(b, 2)
	canvas_cmd.fill_rect(b, 0, HORIZON_Y, CANVAS_FOUR_W, CANVAS_FOUR_H - HORIZON_Y)
	canvas_four_op_count += 4
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_pond :: proc(b: ^canvas_cmd.Buffer) {
	canvas_cmd.linear_gradient(b, 3, 0, POND_CY - POND_RY, 0, POND_CY + POND_RY)
	canvas_cmd.add_color_stop(b, 3, 0.0, "#bfe6ff")
	canvas_cmd.add_color_stop(b, 3, 1.0, "#3f8fc4")
	canvas_cmd.use_gradient_fill(b, 3)
	canvas_cmd.begin_path(b)
	canvas_cmd.ellipse(b, POND_CX, POND_CY, POND_RX, POND_RY, 0, 0, math.TAU)
	canvas_cmd.fill(b)
	canvas_four_op_count += 5

	canvas_cmd.set_stroke(b, "rgba(255,255,255,0.35)")
	canvas_cmd.set_line_width(b, 2)
	canvas_cmd.begin_path(b)
	canvas_cmd.ellipse(b, POND_CX, POND_CY, POND_RX, POND_RY, 0, 0, math.TAU)
	canvas_cmd.stroke(b)
	canvas_four_op_count += 4
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_trees :: proc(b: ^canvas_cmd.Buffer) {
	for t in trees {
		id: u16 = t.big ? SPRITE_TREE_BIG : SPRITE_TREE_SMALL
		w: f32 = t.big ? TREE_BIG_W : TREE_SMALL_W
		h: f32 = t.big ? TREE_BIG_H : TREE_SMALL_H
		canvas_cmd.draw_sprite(b, id, t.x - w / 2, t.y - h)
		canvas_four_op_count += 1
	}
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_ducks :: proc(b: ^canvas_cmd.Buffer) {
	dt: f32 = 1.0 / 60.0
	for &d in ducks {
		d.x += d.speed * dt
		if d.x < DUCK_MIN_X {
			d.x = DUCK_MIN_X
			d.speed = -d.speed
		}
		if d.x > DUCK_MAX_X {
			d.x = DUCK_MAX_X
			d.speed = -d.speed
		}
		theta := canvas_four_time * 2.4 + d.phase
		bob := math.sin(theta) * 4.0

		// A duck "bounces" on the water at the low point of its bob — the moment its downward
		// velocity (sin's derivative, cos) crosses back to positive. Spawn a ripple right there.
		cos_theta := math.cos(theta)
		if d.last_cos < 0 && cos_theta >= 0 {
			spawn_canvas_four_ripple(d.x, d.base_y + 4.0)
		}
		d.last_cos = cos_theta

		dw: f32 = DUCK_W
		if d.speed < 0 {
			dw = -DUCK_W
		}
		dx := d.x - DUCK_W / 2
		dy := d.base_y + bob - DUCK_H / 2

		canvas_cmd.draw_sprite_scaled(b, SPRITE_DUCK, dx, dy, dw, DUCK_H)
		canvas_four_op_count += 1
	}
}

// ------------------------------------------------------------------------------------------------
draw_canvas_four_ripples :: proc(b: ^canvas_cmd.Buffer) {
	dt: f32 = 1.0 / 60.0
	for &r in ripples {
		if r.age < 0 {
			continue
		}
		r.age += dt
		if r.age > RIPPLE_LIFETIME {
			r.age = -1
			continue
		}
		t := r.age / RIPPLE_LIFETIME
		radius := 8.0 + t * 46.0
		alpha := (1.0 - t) * 0.6
		canvas_cmd.set_stroke(b, fmt.tprintf("rgba(255,255,255,%.2f)", alpha))
		canvas_cmd.set_line_width(b, 2)
		canvas_cmd.begin_path(b)
		canvas_cmd.ellipse(b, r.x, r.y, radius, radius * 0.35, 0, 0, math.TAU)
		canvas_cmd.stroke(b)
		canvas_four_op_count += 4
	}
}

// ------------------------------------------------------------------------------------------------
update_canvas_four_hud :: proc() {
	elem := dom.get_element_by_id("canvasFourHud")
	if !dom.is_valid(elem) {
		return
	}
	dom.set_inner_text(
		elem,
		fmt.tprintf(
			"%d Canvas2D commands batched into 1 WASM→JS call this frame (canvas_cmd) — vs %d individual bridge crossings without it",
			canvas_four_op_count,
			canvas_four_op_count,
		),
	)
}

// ------------------------------------------------------------------------------------------------
// spawn_canvas_four_ripple activates a ripple at (x, y), reusing the oldest ripple slot once all
// MAX_RIPPLES are in flight. Shared by click interaction and the ducks' bob-bounce trigger.
spawn_canvas_four_ripple :: proc(x, y: f32) {
	for &r in ripples {
		if r.age < 0 {
			r.x = x
			r.y = y
			r.age = 0
			return
		}
	}

	oldest := 0
	oldest_age: f32 = -1
	for i in 0 ..< MAX_RIPPLES {
		if ripples[i].age > oldest_age {
			oldest_age = ripples[i].age
			oldest = i
		}
	}
	ripples[oldest] = Ripple{x = x, y = y, age = 0}
}

// ------------------------------------------------------------------------------------------------
// on_canvas_four_interaction spawns a ripple at the click/tap point. Interaction coordinates are
// reset after consuming, same as canvas two, so a stray re-fire is a no-op.
on_canvas_four_interaction :: proc() {
	if !is_ready {
		return
	}
	if interact_x < 0 || interact_y < 0 {
		return
	}
	x := f32(interact_x)
	y := f32(interact_y)
	interact_x = -1
	interact_y = -1

	spawn_canvas_four_ripple(x, y)
}
