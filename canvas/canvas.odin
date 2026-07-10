// Package canvas provides a 2D pixel buffer and drawing operations for HTML5 canvas.
package canvas

import "../colour"
import "../dom"
import "core:fmt"

// ------------------------------------------------------------------------------------------------
// Point represents a 2D coordinate vector.
Point :: struct {
	x, y: i32,
}

// ------------------------------------------------------------------------------------------------
// Canvas represents the in-memory pixel buffer and its associated HTML canvas.
Canvas :: struct {
	width:         int,
	height:        int,
	pixels:        []byte,
	active_colour: colour.Colour,
	canvas_handle: dom.Handle,
	ctx_handle:    dom.Handle,
}

// ================================================================================================
// Constructors
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// new_canvas creates a canvas in-memory and associates it with a new canvas element appended to
// the DOM element identified by parent_id. Panics if no such element exists.
new_canvas :: proc(width, height: int, pixels: []byte, parent_id: string) -> Canvas {
	parent_handle := dom.get_element_by_id(parent_id)
	if !dom.is_valid(parent_handle) {
		fmt.panicf("odindom: new_canvas: no DOM element with id %s", parent_id)
	}
	canvas_h := dom.canvas_create(parent_handle, width, height)
	ctx_h := dom.canvas_get_context(canvas_h)

	return Canvas {
		width         = width,
		height        = height,
		pixels        = pixels,
		active_colour = colour.Black,
		canvas_handle = canvas_h,
		ctx_handle    = ctx_h,
	}
}

// ------------------------------------------------------------------------------------------------
// new_offscreen_canvas creates a Canvas backed only by a pixel buffer, with no DOM or JS objects
// attached. Useful for benchmarking and unit testing. Calling render() on an offscreen canvas is
// a no-op.
new_offscreen_canvas :: proc(width, height: int, pixels: []byte) -> Canvas {
	return Canvas{width = width, height = height, pixels = pixels, active_colour = colour.Black}
}

// ================================================================================================
// Core rendering
// ================================================================================================

// ------------------------------------------------------------------------------------------------
// render blits the pixel buffer into JavaScript and updates the canvas.
// It is a no-op if the canvas was created with new_offscreen_canvas.
render :: proc "contextless" (c: ^Canvas) {
	if !dom.is_valid(c.ctx_handle) {
		return
	}
	dom.canvas_render(c.canvas_handle, c.ctx_handle, c.pixels, c.width, c.height)
}

// ------------------------------------------------------------------------------------------------
// clear_screen fills the entire canvas with the specified colour.
clear_screen :: proc "contextless" (c: ^Canvas, col: colour.Colour) {
	if len(c.pixels) < 4 {
		return
	}
	c.pixels[0] = col.r
	c.pixels[1] = col.g
	c.pixels[2] = col.b
	c.pixels[3] = col.a

	for bp := 4; bp < len(c.pixels); bp *= 2 {
		copy(c.pixels[bp:], c.pixels[:bp])
	}
}

// ------------------------------------------------------------------------------------------------
// set_colour sets the active drawing colour.
set_colour :: proc "contextless" (c: ^Canvas, col: colour.Colour) {
	c.active_colour = col
}

// ------------------------------------------------------------------------------------------------
// get_colour retrieves the active drawing colour.
get_colour :: proc "contextless" (c: ^Canvas) -> colour.Colour {
	return c.active_colour
}

