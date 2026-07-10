package canvas

import "../colour"

// ------------------------------------------------------------------------------------------------
// pixel_offset returns the offset in the pixels slice for the pixel at (x, y).
// It returns false if the coordinates are out of bounds.
@(private)
pixel_offset :: proc "contextless" (c: ^Canvas, x, y: i32) -> (int, bool) {
	if x < 0 || y < 0 {
		return 0, false
	}
	ux := int(x)
	uy := int(y)
	if ux >= c.width || uy >= c.height {
		return 0, false
	}
	return (uy * c.width + ux) * 4, true
}

// ------------------------------------------------------------------------------------------------
// put_pixel draws a pixel at (x, y) using the active drawing colour.
put_pixel :: proc "contextless" (c: ^Canvas, x, y: i32) {
	off, ok := pixel_offset(c, x, y)
	if !ok {
		return
	}
	c.pixels[off] = c.active_colour.r
	c.pixels[off + 1] = c.active_colour.g
	c.pixels[off + 2] = c.active_colour.b
	c.pixels[off + 3] = c.active_colour.a
}

// ------------------------------------------------------------------------------------------------
// colour_put_pixel draws a pixel at (x, y) with the specified colour.
colour_put_pixel :: proc "contextless" (c: ^Canvas, x, y: i32, col: colour.Colour) {
	off, ok := pixel_offset(c, x, y)
	if !ok {
		return
	}
	c.pixels[off] = col.r
	c.pixels[off + 1] = col.g
	c.pixels[off + 2] = col.b
	c.pixels[off + 3] = col.a
}

// ------------------------------------------------------------------------------------------------
// blend_pixel alpha-composites col over the existing pixel at (x, y), using col.a (0-255) as the
// blend weight. Destination alpha is left at 255 (canvas backgrounds are always opaque).
blend_pixel :: proc "contextless" (c: ^Canvas, x, y: i32, col: colour.Colour) {
	off, ok := pixel_offset(c, x, y)
	if !ok || col.a == 0 {
		return
	}
	if col.a == 255 {
		c.pixels[off] = col.r
		c.pixels[off + 1] = col.g
		c.pixels[off + 2] = col.b
		c.pixels[off + 3] = col.a
		return
	}
	a := u32(col.a)
	inv := 255 - a
	c.pixels[off] = u8((u32(col.r) * a + u32(c.pixels[off]) * inv) / 255)
	c.pixels[off + 1] = u8((u32(col.g) * a + u32(c.pixels[off + 1]) * inv) / 255)
	c.pixels[off + 2] = u8((u32(col.b) * a + u32(c.pixels[off + 2]) * inv) / 255)
}

// ------------------------------------------------------------------------------------------------
// get_pixel retrieves the colour of the pixel at (x, y).
// It returns false if the coordinates are out of bounds.
get_pixel :: proc "contextless" (c: ^Canvas, x, y: i32) -> (colour.Colour, bool) {
	off, ok := pixel_offset(c, x, y)
	if !ok {
		return colour.Empty, false
	}
	return colour.Colour{r = c.pixels[off], g = c.pixels[off + 1], b = c.pixels[off + 2], a = c.pixels[off + 3]}, true
}
