package canvas

import "../colour"
import "core:math"

// ------------------------------------------------------------------------------------------------
// abs32 returns the absolute value of the 32-bit integer v.
// min(i32) is clamped to max(i32) to avoid overflow on negation.
@(private)
abs32 :: proc "contextless" (v: i32) -> i32 {
	if v >= 0 {
		return v
	}
	if v == min(i32) {
		return max(i32)
	}
	return -v
}

// ------------------------------------------------------------------------------------------------
// line draws a 1-pixel line from (x1, y1) to (x2, y2) using Bresenham's algorithm and the active
// colour.
line :: proc "contextless" (c: ^Canvas, x1, y1, x2, y2: i32) {
	x1, y1 := x1, y1
	diff_x := abs32(x2 - x1)
	diff_y := abs32(y2 - y1)
	slope_x: i32 = x1 < x2 ? 1 : -1
	slope_y: i32 = y1 < y2 ? 1 : -1
	err := diff_x - diff_y
	for {
		put_pixel(c, x1, y1)
		if x1 == x2 && y1 == y2 {
			break
		}
		e2 := 2 * err
		if e2 > -diff_y {
			err -= diff_y
			x1 += slope_x
		}
		if e2 < diff_x {
			err += diff_x
			y1 += slope_y
		}
	}
}

// ------------------------------------------------------------------------------------------------
// colour_line draws a line from (x1, y1) to (x2, y2) with the specified colour.
colour_line :: proc "contextless" (c: ^Canvas, x1, y1, x2, y2: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	line(c, x1, y1, x2, y2)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// line_point draws a line between two Points using the active colour.
line_point :: proc "contextless" (c: ^Canvas, p1, p2: Point) {
	line(c, p1.x, p1.y, p2.x, p2.y)
}

// ------------------------------------------------------------------------------------------------
// colour_line_point draws a line between two Points with the specified colour.
colour_line_point :: proc "contextless" (c: ^Canvas, p1, p2: Point, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	line_point(c, p1, p2)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// circle draws an outline circle at (mid_x, mid_y) with the specified radius using the active
// colour. Uses the Bresenham midpoint circle algorithm — integer arithmetic only, no
// trigonometry.
circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius: i32) {
	if radius <= 0 {
		return
	}
	x := radius
	y: i32 = 0
	err := 1 - radius
	for x >= y {
		put_pixel(c, mid_x + x, mid_y + y)
		put_pixel(c, mid_x - x, mid_y + y)
		put_pixel(c, mid_x + x, mid_y - y)
		put_pixel(c, mid_x - x, mid_y - y)
		put_pixel(c, mid_x + y, mid_y + x)
		put_pixel(c, mid_x - y, mid_y + x)
		put_pixel(c, mid_x + y, mid_y - x)
		put_pixel(c, mid_x - y, mid_y - x)
		y += 1
		if err <= 0 {
			err += 2 * y + 1
		} else {
			x -= 1
			err += 2 * (y - x) + 1
		}
	}
}

// ------------------------------------------------------------------------------------------------
// colour_circle draws an outline circle at (mid_x, mid_y) with the specified radius and colour.
colour_circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	circle(c, mid_x, mid_y, radius)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// filled_circle draws a filled circle at (mid_x, mid_y) with the specified radius using the
// active colour.
filled_circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius: i32) {
	if radius <= 0 {
		return
	}
	r2 := i64(radius) * i64(radius)
	for dy := -radius; dy <= radius; dy += 1 {
		dy64 := i64(dy)
		chord := i32(math.sqrt(f64(r2 - dy64 * dy64)))
		for dx := -chord; dx <= chord; dx += 1 {
			put_pixel(c, mid_x + dx, mid_y + dy)
		}
	}
}

// ------------------------------------------------------------------------------------------------
// colour_filled_circle draws a filled circle at (mid_x, mid_y) with the specified radius and
// colour.
colour_filled_circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	filled_circle(c, mid_x, mid_y, radius)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// border_circle draws a ring (annulus) at (mid_x, mid_y) with the specified radius and border
// width using the active colour.
border_circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius, border_width: i32) {
	if radius <= 0 || border_width <= 0 {
		return
	}
	inner_radius := radius - border_width
	if inner_radius <= 0 {
		filled_circle(c, mid_x, mid_y, radius)
		return
	}
	outer_r2 := i64(radius) * i64(radius)
	inner_r2 := i64(inner_radius) * i64(inner_radius)
	for dy := -radius; dy <= radius; dy += 1 {
		for dx := -radius; dx <= radius; dx += 1 {
			d2 := i64(dx) * i64(dx) + i64(dy) * i64(dy)
			if d2 <= outer_r2 && d2 > inner_r2 {
				put_pixel(c, mid_x + dx, mid_y + dy)
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------
// colour_border_circle draws a ring (annulus) at (mid_x, mid_y) with the specified radius,
// border width, and colour.
colour_border_circle :: proc "contextless" (c: ^Canvas, mid_x, mid_y, radius, border_width: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	border_circle(c, mid_x, mid_y, radius, border_width)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// filled_rectangle draws a filled rectangle starting at (x_start, y_start) with the specified
// width and height using the active colour.
filled_rectangle :: proc "contextless" (c: ^Canvas, x_start, y_start, width, height: i32) {
	for y: i32 = 0; y < height; y += 1 {
		for x: i32 = 0; x < width; x += 1 {
			put_pixel(c, x_start + x, y_start + y)
		}
	}
}

// ------------------------------------------------------------------------------------------------
// colour_filled_rectangle draws a filled rectangle starting at (x_start, y_start) with the
// specified width, height, and colour.
colour_filled_rectangle :: proc "contextless" (c: ^Canvas, x_start, y_start, width, height: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	filled_rectangle(c, x_start, y_start, width, height)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// rectangle_outline draws the 1-pixel outline of a rectangle starting at (x_start, y_start) with
// the specified width and height using the active colour.
@(private)
rectangle_outline :: proc "contextless" (c: ^Canvas, x_start, y_start, width, height: i32) {
	x2 := x_start + width - 1
	y2 := y_start + height - 1
	line(c, x_start, y_start, x2, y_start)
	line(c, x2, y_start, x2, y2)
	line(c, x_start, y2, x2, y2)
	line(c, x_start, y_start, x_start, y2)
}

// ------------------------------------------------------------------------------------------------
// rectangle draws an outline rectangle starting at (x_start, y_start) with the specified width,
// height, and border thickness using the active colour.
rectangle :: proc "contextless" (c: ^Canvas, x_start, y_start, width, height, thickness: i32) {
	for t: i32 = 0; t < thickness; t += 1 {
		if width - t * 2 <= 0 || height - t * 2 <= 0 {
			break
		}
		rectangle_outline(c, x_start + t, y_start + t, width - t * 2, height - t * 2)
	}
}

// ------------------------------------------------------------------------------------------------
// colour_rectangle draws an outline rectangle starting at (x_start, y_start) with the specified
// width, height, thickness, and colour.
colour_rectangle :: proc "contextless" (c: ^Canvas, x_start, y_start, width, height, thickness: i32, col: colour.Colour) {
	old := c.active_colour
	c.active_colour = col
	rectangle(c, x_start, y_start, width, height, thickness)
	c.active_colour = old
}

// ------------------------------------------------------------------------------------------------
// triangle draws a wireframe triangle through the three Points using the active colour.
triangle :: proc "contextless" (c: ^Canvas, p1, p2, p3: Point) {
	line_point(c, p1, p2)
	line_point(c, p2, p3)
	line_point(c, p1, p3)
}
