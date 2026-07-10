package dom

// ------------------------------------------------------------------------------------------------
// Canvas utilities
// ------------------------------------------------------------------------------------------------

foreign import odindom_env "odindom_env"

@(default_calling_convention = "contextless")
foreign odindom_env {
	dom_canvas_create        :: proc(parent: Handle, width, height: u32) -> Handle ---
	dom_canvas_get_context   :: proc(canvas: Handle) -> Handle ---
	dom_canvas_render        :: proc(canvas, ctx: Handle, pixels: []byte, width, height: u32) ---
	dom_start_animation_loop :: proc(cb_id: u32) ---
}

// ------------------------------------------------------------------------------------------------
// canvas_create creates a canvas element and appends it to parent.
canvas_create :: proc "contextless" (parent: Handle, width, height: int) -> Handle {
	return dom_canvas_create(parent, u32(width), u32(height))
}

// ------------------------------------------------------------------------------------------------
// canvas_get_context retrieves the 2D rendering context of the canvas.
canvas_get_context :: proc "contextless" (canvas: Handle) -> Handle {
	return dom_canvas_get_context(canvas)
}

// ------------------------------------------------------------------------------------------------
// canvas_render blits the pixel buffer into the canvas via putImageData.
canvas_render :: proc "contextless" (canvas, ctx: Handle, pixels: []byte, width, height: int) {
	dom_canvas_render(canvas, ctx, pixels, u32(width), u32(height))
}

// ------------------------------------------------------------------------------------------------
// start_animation_loop drives a 60 FPS animation cycle via requestAnimationFrame, invoking the
// host app's callback dispatcher with cb_id on every frame.
start_animation_loop :: proc "contextless" (cb_id: u32) {
	dom_start_animation_loop(cb_id)
}

