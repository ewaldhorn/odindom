// OdinDOM example: canvas_cmd basics — one tree, one duck, no interaction.
//
// canvas/click-rect draws by writing bytes into a pixel buffer and blitting it with
// putImageData. That works great for flat-shaded pixel art, but it can't do gradients,
// anti-aliased curves, or text — and driving the *real* Canvas2D API one method call at a time
// (fillRect, arc, fill, ...) would mean one WASM<->JS crossing per call, which gets expensive at
// 60fps.
//
// canvas_cmd solves that: you record a whole frame's worth of Canvas2D commands into one packed
// byte buffer, then flush it to the browser with a SINGLE foreign call. The JS side just walks
// the buffer and replays each command onto a real CanvasRenderingContext2D.
//
// This example draws the smallest possible animated scene with it: a static tree and a duck that
// swims back and forth, bobbing on the water. See docs/canvas_four.odin for a fancier version of
// the same idea (multiple trees/ducks, click-to-ripple, a live op-count HUD).
package main

import "base:runtime"
import "core:math"
import "../../canvas_cmd"
import "../../dom"

// ------------------------------------------------------------------------------------------------
// Scene layout
// ------------------------------------------------------------------------------------------------
CANVAS_W :: 480
CANVAS_H :: 300
HORIZON_Y :: 190 // sky/ground split

POND_CX :: 240
POND_CY :: 220
POND_RX :: 170
POND_RY :: 45

TREE_X :: 110
TREE_W :: 70
TREE_H :: 110

DUCK_W :: 48
DUCK_H :: 36
DUCK_MIN_X :: POND_CX - POND_RX + 60
DUCK_MAX_X :: POND_CX + POND_RX - 60

// Sprite ids we choose for the offscreen bakes below — canvas_cmd just treats these as small
// integer keys into a JS-side Map, so any distinct values work.
SPRITE_TREE :: 0
SPRITE_DUCK :: 1

// The only callback this example needs: one animation tick per frame (see start_animation_loop
// below). A real app would add more IDs here for clicks, buttons, etc. — see click-rect.
CB_ANIMATION_TICK :: 0

// ------------------------------------------------------------------------------------------------
// State
// ------------------------------------------------------------------------------------------------

// The 2D rendering context canvas_cmd flushes commands onto (not a canvas.Canvas — that's the
// unrelated pixel-buffer path used by click-rect).
ctx: dom.Handle

// A reusable command buffer. reset() at the start of every frame, flush() at the end — no
// per-frame allocation.
cmd: canvas_cmd.Buffer

time: f32 // seconds since start, drives the duck's bob/swim animation

duck_x: f32 = 180
duck_speed: f32 = 24 // px/sec; sign flips when duck_x hits the pond edges

// ------------------------------------------------------------------------------------------------
// Entry point
// ------------------------------------------------------------------------------------------------
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()

	dom.init()

	canvas_h := dom.canvas_create(dom.get_element_by_id("app"), CANVAS_W, CANVAS_H)
	ctx = dom.canvas_get_context(canvas_h)

	bake_sprites()

	dom.start_animation_loop(CB_ANIMATION_TICK)
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case CB_ANIMATION_TICK:
		draw_frame()
	}
}

// ------------------------------------------------------------------------------------------------
// bake_sprites records the tree and duck artwork ONCE into offscreen sprite canvases
// (bake_begin/bake_end), then flushes that recording immediately. From then on, every frame just
// re-blits the finished sprites (draw_sprite) instead of re-encoding the paths/arcs that make up
// their artwork — the per-frame buffer stays tiny regardless of how detailed the art is.
bake_sprites :: proc() {
	canvas_cmd.reset(&cmd)

	// --- Tree: a brown trunk + three overlapping green circles for the canopy. ---
	canvas_cmd.bake_begin(&cmd, SPRITE_TREE, TREE_W, TREE_H)

	trunk_w := f32(TREE_W) * 0.18
	trunk_h := f32(TREE_H) * 0.32
	canvas_cmd.set_fill(&cmd, "#5b3a22")
	canvas_cmd.fill_rect(&cmd, f32(TREE_W) / 2 - trunk_w / 2, f32(TREE_H) - trunk_h, trunk_w, trunk_h)

	canopy_colours := [3]string{"#1f5c2e", "#2c7a3d", "#3f9650"}
	canopy_y := f32(TREE_H) - trunk_h
	for i in 0 ..< 3 {
		r := f32(TREE_W) * (0.30 - f32(i) * 0.03)
		ox := f32(TREE_W) / 2 + f32(i - 1) * f32(TREE_W) * 0.14
		oy := canopy_y - f32(i) * f32(TREE_H) * 0.12 - r * 0.5
		canvas_cmd.set_fill(&cmd, canopy_colours[i])
		canvas_cmd.begin_path(&cmd)
		canvas_cmd.arc(&cmd, ox, oy, r, 0, math.TAU)
		canvas_cmd.fill(&cmd)
	}

	canvas_cmd.bake_end(&cmd)

	// --- Duck: white body + wing ellipses, a round head, an orange beak path, a dark eye dot. ---
	canvas_cmd.bake_begin(&cmd, SPRITE_DUCK, DUCK_W, DUCK_H)

	fw := f32(DUCK_W)
	fh := f32(DUCK_H)

	canvas_cmd.set_fill(&cmd, "#fefefe")
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.ellipse(&cmd, fw * 0.5, fh * 0.62, fw * 0.40, fh * 0.34, 0, 0, math.TAU)
	canvas_cmd.fill(&cmd)

	canvas_cmd.set_fill(&cmd, "#e4e4e4")
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.ellipse(&cmd, fw * 0.44, fh * 0.60, fw * 0.19, fh * 0.18, 0.3, 0, math.TAU)
	canvas_cmd.fill(&cmd)

	canvas_cmd.set_fill(&cmd, "#fefefe")
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.arc(&cmd, fw * 0.78, fh * 0.32, fh * 0.24, 0, math.TAU)
	canvas_cmd.fill(&cmd)

	canvas_cmd.set_fill(&cmd, "#f5a623")
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.move_to(&cmd, fw * 0.94, fh * 0.30)
	canvas_cmd.line_to(&cmd, fw * 1.04, fh * 0.34)
	canvas_cmd.line_to(&cmd, fw * 0.94, fh * 0.40)
	canvas_cmd.close_path(&cmd)
	canvas_cmd.fill(&cmd)

	canvas_cmd.set_fill(&cmd, "#222222")
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.arc(&cmd, fw * 0.83, fh * 0.28, fh * 0.035, 0, math.TAU)
	canvas_cmd.fill(&cmd)

	canvas_cmd.bake_end(&cmd)

	canvas_cmd.flush(ctx, &cmd)
}

// ------------------------------------------------------------------------------------------------
// draw_frame re-records the whole scene into `cmd` and flushes it with ONE foreign call. This is
// the steady-state per-frame cost: a sky gradient, a ground fill, a pond gradient, one sprite
// blit for the tree, and one sprite blit for the duck — six draw commands, one bridge crossing.
draw_frame :: proc() {
	time += 1.0 / 60.0

	canvas_cmd.reset(&cmd)

	// Sky: a vertical gradient from dawn orange to pale blue.
	canvas_cmd.linear_gradient(&cmd, 0, 0, 0, 0, HORIZON_Y)
	canvas_cmd.add_color_stop(&cmd, 0, 0.0, "#ffd9a0")
	canvas_cmd.add_color_stop(&cmd, 0, 1.0, "#9fd4ff")
	canvas_cmd.use_gradient_fill(&cmd, 0)
	canvas_cmd.fill_rect(&cmd, 0, 0, CANVAS_W, HORIZON_Y)

	// Ground: flat green fill below the horizon.
	canvas_cmd.set_fill(&cmd, "#3f8c3f")
	canvas_cmd.fill_rect(&cmd, 0, HORIZON_Y, CANVAS_W, CANVAS_H - HORIZON_Y)

	// Pond: a gradient-filled ellipse sitting on the ground.
	canvas_cmd.linear_gradient(&cmd, 1, 0, POND_CY - POND_RY, 0, POND_CY + POND_RY)
	canvas_cmd.add_color_stop(&cmd, 1, 0.0, "#bfe6ff")
	canvas_cmd.add_color_stop(&cmd, 1, 1.0, "#3f8fc4")
	canvas_cmd.use_gradient_fill(&cmd, 1)
	canvas_cmd.begin_path(&cmd)
	canvas_cmd.ellipse(&cmd, POND_CX, POND_CY, POND_RX, POND_RY, 0, 0, math.TAU)
	canvas_cmd.fill(&cmd)

	// Tree: one sprite blit, no re-encoding of its artwork.
	canvas_cmd.draw_sprite(&cmd, SPRITE_TREE, TREE_X - TREE_W / 2, HORIZON_Y - TREE_H)

	// Duck: swims back and forth across the pond, bobbing gently on a sine wave. Flips
	// horizontally (negative width) when swimming left.
	duck_x += duck_speed * (1.0 / 60.0)
	if duck_x < DUCK_MIN_X {
		duck_x = DUCK_MIN_X
		duck_speed = -duck_speed
	}
	if duck_x > DUCK_MAX_X {
		duck_x = DUCK_MAX_X
		duck_speed = -duck_speed
	}
	bob := math.sin(time * 2.4) * 4.0

	dw: f32 = DUCK_W
	if duck_speed < 0 {
		dw = -DUCK_W
	}
	canvas_cmd.draw_sprite_scaled(
		&cmd,
		SPRITE_DUCK,
		duck_x - DUCK_W / 2,
		POND_CY + bob - DUCK_H / 2,
		dw,
		DUCK_H,
	)

	canvas_cmd.flush(ctx, &cmd)
}
