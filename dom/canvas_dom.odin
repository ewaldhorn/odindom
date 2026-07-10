package dom

// ------------------------------------------------------------------------------------------------
// Canvas & Context2D utilities
// ------------------------------------------------------------------------------------------------

foreign import odindom_env "odindom_env"

@(default_calling_convention = "contextless")
foreign odindom_env {
	dom_canvas_create        :: proc(parent: Handle, width, height: u32) -> Handle ---
	dom_canvas_get_context   :: proc(canvas: Handle) -> Handle ---
	dom_canvas_render        :: proc(canvas, ctx: Handle, pixels: []byte, width, height: u32) ---
	dom_start_animation_loop :: proc(cb_id: u32) ---
	dom_ctx_begin_path       :: proc(ctx: Handle) ---
	dom_ctx_fill             :: proc(ctx: Handle) ---
	dom_ctx_arc              :: proc(ctx: Handle, x, y, radius, start_angle, end_angle: f64, ccw: b32) ---
	dom_ctx_fill_style       :: proc(ctx: Handle, style: string) ---
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

// ------------------------------------------------------------------------------------------------
// Context2D wraps the canvas 2D rendering context.
Context2D :: struct {
	ctx: Handle,
}

// ------------------------------------------------------------------------------------------------
// begin_path begins a new path in the rendering context.
begin_path :: proc "contextless" (c: Context2D) {
	dom_ctx_begin_path(c.ctx)
}

// ------------------------------------------------------------------------------------------------
// fill fills the current path with the current fill style.
fill :: proc "contextless" (c: Context2D) {
	dom_ctx_fill(c.ctx)
}

// ------------------------------------------------------------------------------------------------
// arc draws a circular arc on the rendering context.
arc :: proc "contextless" (c: Context2D, x, y, radius, start_angle, end_angle: f64, ccw: bool) {
	dom_ctx_arc(c.ctx, x, y, radius, start_angle, end_angle, b32(ccw))
}

// ------------------------------------------------------------------------------------------------
// fill_style sets the fill style/color of the rendering context.
fill_style :: proc "contextless" (c: Context2D, style: string) {
	dom_ctx_fill_style(c.ctx, style)
}
