// Package canvas_cmd implements a retained draw-command buffer for driving a real JS
// CanvasRenderingContext2D from Odin/WASM.
//
// WHY: OdinDOM's `canvas` package rasterizes into a pixel buffer and blits it via putImageData,
// which cannot reproduce gradients, text/emoji, or the full Canvas 2D drawing API. Games that
// need those (e.g. procedurally drawn city builders) instead want to issue real Canvas2D calls —
// but doing so one method at a time across the WASM<->JS boundary is expensive at 60fps.
//
// This package lets Odin record an entire frame's worth of draw operations into one packed byte
// buffer, then flush it with a SINGLE foreign call. The JS side (odindom.js `dom_canvas_cmd_flush`)
// walks the buffer and replays each op onto the context. Encoding logic stays in Odin; JS is a
// mechanical dispatcher.
//
// WIRE FORMAT (little-endian):
//   command := opcode:u8  followed by that opcode's typed args
//   f32 arg := 4 bytes IEEE-754 LE
//   str arg := len:u16 LE  followed by `len` UTF-8 bytes
//   u8  arg := 1 byte
//
// The Buffer is a fixed-capacity, preallocated arena reused every frame (reset() rewinds the
// cursor) — no per-frame heap churn, no allocator dependency.
package canvas_cmd

import "../dom"

foreign import odindom_env "odindom_env"

@(default_calling_convention = "contextless")
foreign odindom_env {
	// dom_canvas_cmd_flush replays the packed command buffer onto the 2D context `ctx`.
	dom_canvas_cmd_flush :: proc(ctx: dom.Handle, buf: []byte) ---

	// dom_measure_text returns the rendered width (px) of `text` in `font`, measured on a
	// dedicated offscreen context so it never disturbs the render context's state.
	dom_measure_text :: proc(font, text: string) -> f64 ---
}

// ------------------------------------------------------------------------------------------------
// Opcodes — keep in sync with the switch in odindom.js `dom_canvas_cmd_flush`.
// ------------------------------------------------------------------------------------------------
OP_SET_FILL          :: 0x01 // str
OP_SET_STROKE        :: 0x02 // str
OP_SET_LINE_WIDTH    :: 0x03 // f32
OP_SET_FONT          :: 0x04 // str
OP_SET_TEXT_ALIGN    :: 0x05 // str
OP_SET_TEXT_BASELINE :: 0x06 // str
OP_SET_GLOBAL_ALPHA  :: 0x07 // f32
OP_SET_LINE_CAP      :: 0x08 // str

OP_FILL_RECT   :: 0x10 // f32 x4
OP_STROKE_RECT :: 0x11 // f32 x4
OP_CLEAR_RECT  :: 0x12 // f32 x4

OP_BEGIN_PATH :: 0x20
OP_MOVE_TO    :: 0x21 // f32 x2
OP_LINE_TO    :: 0x22 // f32 x2
OP_CLOSE_PATH :: 0x23
OP_ARC        :: 0x24 // x,y,r,a0,a1 (f32) + ccw (u8)
OP_ELLIPSE    :: 0x25 // x,y,rx,ry,rot,a0,a1 (f32) + ccw (u8)
OP_RECT       :: 0x26 // f32 x4
OP_FILL       :: 0x28
OP_STROKE     :: 0x29
OP_CLIP       :: 0x2A

OP_FILL_TEXT   :: 0x30 // str, x, y (f32)
OP_STROKE_TEXT :: 0x31 // str, x, y (f32)

OP_BEZIER_CURVE_TO :: 0x27 // cx1,cy1,cx2,cy2,x,y (f32)

OP_SAVE            :: 0x40
OP_RESTORE         :: 0x41
OP_TRANSLATE       :: 0x42 // f32 x2
OP_SCALE           :: 0x43 // f32 x2
OP_ROTATE          :: 0x44 // f32
OP_SET_TRANSFORM   :: 0x45 // a,b,c,d,e,f (f32)
OP_RESET_TRANSFORM :: 0x46

OP_LINEAR_GRADIENT     :: 0x50 // grad_id(u16), x0,y0,x1,y1 (f32)
OP_RADIAL_GRADIENT     :: 0x51 // grad_id(u16), x0,y0,r0,x1,y1,r1 (f32)
OP_ADD_COLOR_STOP      :: 0x52 // grad_id(u16), offset(f32), color(str)
OP_USE_GRADIENT_FILL   :: 0x53 // grad_id(u16)
OP_USE_GRADIENT_STROKE :: 0x54 // grad_id(u16)

OP_DRAW_SPRITE        :: 0x60 // sprite_id(u16), dx,dy (f32)
OP_DRAW_SPRITE_SCALED :: 0x61 // sprite_id(u16), dx,dy,dw,dh (f32)
OP_DRAW_SPRITE_SUB    :: 0x62 // sprite_id(u16), sx,sy,sw,sh,dx,dy,dw,dh (f32)

OP_SET_SHADOW   :: 0x70 // color(str), blur(f32)
OP_CLEAR_SHADOW :: 0x71

OP_BAKE_BEGIN :: 0x80 // sprite_id(u16), w(u16), h(u16) — subsequent ops target the sprite canvas
OP_BAKE_END   :: 0x81 // — subsequent ops target the main context again

// ------------------------------------------------------------------------------------------------
// Buffer is a fixed-capacity command arena, reused across frames.
// ------------------------------------------------------------------------------------------------
CAPACITY :: 1 << 20 // 1 MiB — comfortably fits a full frame of a large city.

Buffer :: struct {
	data:      [CAPACITY]u8,
	len:       int,
	overflowed: bool,
}

// reset rewinds the buffer to empty. Call once at the start of every frame.
reset :: proc "contextless" (b: ^Buffer) {
	b.len = 0
	b.overflowed = false
}

// flush replays the recorded commands onto ctx, then leaves the buffer as-is (call reset() next
// frame). No-op if nothing was recorded.
flush :: proc "contextless" (ctx: dom.Handle, b: ^Buffer) {
	if b.len == 0 {
		return
	}
	dom_canvas_cmd_flush(ctx, b.data[:b.len])
}

// ------------------------------------------------------------------------------------------------
// Low-level encoders (private).
// ------------------------------------------------------------------------------------------------

@(private)
put_u8 :: proc "contextless" (b: ^Buffer, v: u8) {
	if b.len + 1 > CAPACITY {
		b.overflowed = true
		return
	}
	b.data[b.len] = v
	b.len += 1
}

@(private)
put_f32 :: proc "contextless" (b: ^Buffer, v: f32) {
	if b.len + 4 > CAPACITY {
		b.overflowed = true
		return
	}
	bits := transmute(u32)v
	b.data[b.len + 0] = u8(bits)
	b.data[b.len + 1] = u8(bits >> 8)
	b.data[b.len + 2] = u8(bits >> 16)
	b.data[b.len + 3] = u8(bits >> 24)
	b.len += 4
}

@(private)
put_u16 :: proc "contextless" (b: ^Buffer, v: u16) {
	if b.len + 2 > CAPACITY {
		b.overflowed = true
		return
	}
	b.data[b.len + 0] = u8(v)
	b.data[b.len + 1] = u8(v >> 8)
	b.len += 2
}

@(private)
put_str :: proc "contextless" (b: ^Buffer, s: string) {
	n := len(s)
	if n > 0xFFFF {
		n = 0xFFFF
	}
	if b.len + 2 + n > CAPACITY {
		b.overflowed = true
		return
	}
	b.data[b.len + 0] = u8(n)
	b.data[b.len + 1] = u8(n >> 8)
	b.len += 2
	bytes := transmute([]u8)s
	for i in 0 ..< n {
		b.data[b.len + i] = bytes[i]
	}
	b.len += n
}

// ------------------------------------------------------------------------------------------------
// State setters.
// ------------------------------------------------------------------------------------------------

set_fill :: proc "contextless" (b: ^Buffer, color: string) {
	put_u8(b, OP_SET_FILL);put_str(b, color)
}
set_stroke :: proc "contextless" (b: ^Buffer, color: string) {
	put_u8(b, OP_SET_STROKE);put_str(b, color)
}
set_line_width :: proc "contextless" (b: ^Buffer, w: f32) {
	put_u8(b, OP_SET_LINE_WIDTH);put_f32(b, w)
}
set_font :: proc "contextless" (b: ^Buffer, font: string) {
	put_u8(b, OP_SET_FONT);put_str(b, font)
}
set_text_align :: proc "contextless" (b: ^Buffer, align: string) {
	put_u8(b, OP_SET_TEXT_ALIGN);put_str(b, align)
}
set_text_baseline :: proc "contextless" (b: ^Buffer, baseline: string) {
	put_u8(b, OP_SET_TEXT_BASELINE);put_str(b, baseline)
}
set_global_alpha :: proc "contextless" (b: ^Buffer, a: f32) {
	put_u8(b, OP_SET_GLOBAL_ALPHA);put_f32(b, a)
}
set_line_cap :: proc "contextless" (b: ^Buffer, cap: string) {
	put_u8(b, OP_SET_LINE_CAP);put_str(b, cap)
}

// ------------------------------------------------------------------------------------------------
// Rectangles.
// ------------------------------------------------------------------------------------------------

fill_rect :: proc "contextless" (b: ^Buffer, x, y, w, h: f32) {
	put_u8(b, OP_FILL_RECT);put_f32(b, x);put_f32(b, y);put_f32(b, w);put_f32(b, h)
}
stroke_rect :: proc "contextless" (b: ^Buffer, x, y, w, h: f32) {
	put_u8(b, OP_STROKE_RECT);put_f32(b, x);put_f32(b, y);put_f32(b, w);put_f32(b, h)
}
clear_rect :: proc "contextless" (b: ^Buffer, x, y, w, h: f32) {
	put_u8(b, OP_CLEAR_RECT);put_f32(b, x);put_f32(b, y);put_f32(b, w);put_f32(b, h)
}

// ------------------------------------------------------------------------------------------------
// Paths.
// ------------------------------------------------------------------------------------------------

begin_path :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_BEGIN_PATH)}
close_path :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_CLOSE_PATH)}
fill :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_FILL)}
stroke :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_STROKE)}
clip :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_CLIP)}

move_to :: proc "contextless" (b: ^Buffer, x, y: f32) {
	put_u8(b, OP_MOVE_TO);put_f32(b, x);put_f32(b, y)
}
line_to :: proc "contextless" (b: ^Buffer, x, y: f32) {
	put_u8(b, OP_LINE_TO);put_f32(b, x);put_f32(b, y)
}
rect :: proc "contextless" (b: ^Buffer, x, y, w, h: f32) {
	put_u8(b, OP_RECT);put_f32(b, x);put_f32(b, y);put_f32(b, w);put_f32(b, h)
}

arc :: proc "contextless" (b: ^Buffer, x, y, r, a0, a1: f32, ccw: bool = false) {
	put_u8(b, OP_ARC)
	put_f32(b, x);put_f32(b, y);put_f32(b, r);put_f32(b, a0);put_f32(b, a1)
	put_u8(b, ccw ? 1 : 0)
}

ellipse :: proc "contextless" (b: ^Buffer, x, y, rx, ry, rot, a0, a1: f32, ccw: bool = false) {
	put_u8(b, OP_ELLIPSE)
	put_f32(b, x);put_f32(b, y);put_f32(b, rx);put_f32(b, ry)
	put_f32(b, rot);put_f32(b, a0);put_f32(b, a1)
	put_u8(b, ccw ? 1 : 0)
}

// ------------------------------------------------------------------------------------------------
// Text.
// ------------------------------------------------------------------------------------------------

fill_text :: proc "contextless" (b: ^Buffer, text: string, x, y: f32) {
	put_u8(b, OP_FILL_TEXT);put_str(b, text);put_f32(b, x);put_f32(b, y)
}
stroke_text :: proc "contextless" (b: ^Buffer, text: string, x, y: f32) {
	put_u8(b, OP_STROKE_TEXT);put_str(b, text);put_f32(b, x);put_f32(b, y)
}

// ------------------------------------------------------------------------------------------------
// Transforms.
// ------------------------------------------------------------------------------------------------

save :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_SAVE)}
restore :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_RESTORE)}
translate :: proc "contextless" (b: ^Buffer, x, y: f32) {
	put_u8(b, OP_TRANSLATE);put_f32(b, x);put_f32(b, y)
}
scale :: proc "contextless" (b: ^Buffer, x, y: f32) {
	put_u8(b, OP_SCALE);put_f32(b, x);put_f32(b, y)
}
rotate :: proc "contextless" (b: ^Buffer, a: f32) {
	put_u8(b, OP_ROTATE);put_f32(b, a)
}
bezier_curve_to :: proc "contextless" (b: ^Buffer, cx1, cy1, cx2, cy2, x, y: f32) {
	put_u8(b, OP_BEZIER_CURVE_TO)
	put_f32(b, cx1);put_f32(b, cy1);put_f32(b, cx2);put_f32(b, cy2);put_f32(b, x);put_f32(b, y)
}
// set_transform replaces the current transform matrix: [a c e / b d f / 0 0 1].
set_transform :: proc "contextless" (b: ^Buffer, a, bb, c, d, e, f: f32) {
	put_u8(b, OP_SET_TRANSFORM)
	put_f32(b, a);put_f32(b, bb);put_f32(b, c);put_f32(b, d);put_f32(b, e);put_f32(b, f)
}
reset_transform :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_RESET_TRANSFORM)}

// ------------------------------------------------------------------------------------------------
// Gradients. Create with an app-chosen `id` (small integers, reused each frame), add stops, then
// activate as the fill or stroke style. Gradients are recreated per-frame since they bake in
// absolute coordinates.
// ------------------------------------------------------------------------------------------------

linear_gradient :: proc "contextless" (b: ^Buffer, id: u16, x0, y0, x1, y1: f32) {
	put_u8(b, OP_LINEAR_GRADIENT);put_u16(b, id)
	put_f32(b, x0);put_f32(b, y0);put_f32(b, x1);put_f32(b, y1)
}
radial_gradient :: proc "contextless" (b: ^Buffer, id: u16, x0, y0, r0, x1, y1, r1: f32) {
	put_u8(b, OP_RADIAL_GRADIENT);put_u16(b, id)
	put_f32(b, x0);put_f32(b, y0);put_f32(b, r0);put_f32(b, x1);put_f32(b, y1);put_f32(b, r1)
}
add_color_stop :: proc "contextless" (b: ^Buffer, id: u16, offset: f32, color: string) {
	put_u8(b, OP_ADD_COLOR_STOP);put_u16(b, id);put_f32(b, offset);put_str(b, color)
}
use_gradient_fill :: proc "contextless" (b: ^Buffer, id: u16) {
	put_u8(b, OP_USE_GRADIENT_FILL);put_u16(b, id)
}
use_gradient_stroke :: proc "contextless" (b: ^Buffer, id: u16) {
	put_u8(b, OP_USE_GRADIENT_STROKE);put_u16(b, id)
}

// ------------------------------------------------------------------------------------------------
// Shadows.
// ------------------------------------------------------------------------------------------------

set_shadow :: proc "contextless" (b: ^Buffer, color: string, blur: f32) {
	put_u8(b, OP_SET_SHADOW);put_str(b, color);put_f32(b, blur)
}
clear_shadow :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_CLEAR_SHADOW)}

// ------------------------------------------------------------------------------------------------
// Sprites — bake once into an offscreen canvas, then blit cheaply with draw_sprite.
//
// Usage:
//   bake_begin(b, id, w, h)     // subsequent draw ops render into sprite `id`'s canvas
//   ... draw the sprite art ...
//   bake_end(b)                 // back to the main context
// then per frame:
//   draw_sprite(b, id, x, y)
// ------------------------------------------------------------------------------------------------

bake_begin :: proc "contextless" (b: ^Buffer, id: u16, w, h: u16) {
	put_u8(b, OP_BAKE_BEGIN);put_u16(b, id);put_u16(b, w);put_u16(b, h)
}
bake_end :: proc "contextless" (b: ^Buffer) {put_u8(b, OP_BAKE_END)}

draw_sprite :: proc "contextless" (b: ^Buffer, id: u16, dx, dy: f32) {
	put_u8(b, OP_DRAW_SPRITE);put_u16(b, id);put_f32(b, dx);put_f32(b, dy)
}
draw_sprite_scaled :: proc "contextless" (b: ^Buffer, id: u16, dx, dy, dw, dh: f32) {
	put_u8(b, OP_DRAW_SPRITE_SCALED);put_u16(b, id)
	put_f32(b, dx);put_f32(b, dy);put_f32(b, dw);put_f32(b, dh)
}
draw_sprite_sub :: proc "contextless" (
	b: ^Buffer,
	id: u16,
	sx, sy, sw, sh, dx, dy, dw, dh: f32,
) {
	put_u8(b, OP_DRAW_SPRITE_SUB);put_u16(b, id)
	put_f32(b, sx);put_f32(b, sy);put_f32(b, sw);put_f32(b, sh)
	put_f32(b, dx);put_f32(b, dy);put_f32(b, dw);put_f32(b, dh)
}

// ------------------------------------------------------------------------------------------------
// Text measurement (synchronous, does not use the buffer).
// ------------------------------------------------------------------------------------------------

measure_text :: proc "contextless" (font, text: string) -> f32 {
	return f32(dom_measure_text(font, text))
}
