package main

import "base:runtime"
import "core:strconv"
import "../../canvas"
import "../../colour"
import "../../dom"

// ------------------------------------------------------------------------------------------------
CANVAS_W :: 300
CANVAS_H :: 300

// Rectangle centered in the 300x300 canvas
RECT_X :: 100
RECT_Y :: 100
RECT_W :: 100
RECT_H :: 100

CB_CANVAS_CLICK :: 0

// ------------------------------------------------------------------------------------------------
blue := colour.Colour{r = 30, g = 100, b = 255, a = 255}
is_white := false

pixels: [CANVAS_W * CANVAS_H * 4]byte
c: canvas.Canvas

// ------------------------------------------------------------------------------------------------
redraw :: proc() {
	canvas.clear_screen(&c, colour.Black)
	if is_white {
		canvas.colour_filled_rectangle(&c, RECT_X, RECT_Y, RECT_W, RECT_H, colour.White)
	} else {
		canvas.colour_filled_rectangle(&c, RECT_X, RECT_Y, RECT_W, RECT_H, blue)
	}
	canvas.render(&c)
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()

	dom.init()
	c = canvas.new_canvas(CANVAS_W, CANVAS_H, pixels[:], "app")
	redraw()

	// Click events on the canvas bubble up to its parent "app" div.
	// offsetX/offsetY are relative to the event target (the canvas), so they map directly to
	// pixel coordinates.
	dom.add_event_listener_by_id("app", "click", CB_CANVAS_CLICK)
}

// ------------------------------------------------------------------------------------------------
@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case CB_CANVAS_CLICK:
		evt := dom.last_event_handle()
		x, _ := strconv.parse_int(dom.get(evt, "offsetX"))
		y, _ := strconv.parse_int(dom.get(evt, "offsetY"))

		// Only toggle if the click landed on the rectangle.
		if x >= RECT_X && x < RECT_X + RECT_W && y >= RECT_Y && y < RECT_Y + RECT_H {
			is_white = !is_white
			redraw()
		}
	}
}
