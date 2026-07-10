// Package colour provides structures, constants, and utilities for working with RGBA colours.
package colour

// ------------------------------------------------------------------------------------------------
// Colour represents an RGBA colour structure.
Colour :: struct {
	r, g, b, a: u8,
}

// ------------------------------------------------------------------------------------------------
// Predefined colours.
White :: Colour{r = 255, g = 255, b = 255, a = 255}
Black :: Colour{r = 0, g = 0, b = 0, a = 255}
Empty :: Colour{r = 0, g = 0, b = 0, a = 0}

// ------------------------------------------------------------------------------------------------
// is_empty returns true if the colour is fully transparent (all RGBA components are zero).
is_empty :: proc "contextless" (c: Colour) -> bool {
	return c.r == 0 && c.g == 0 && c.b == 0 && c.a == 0
}

// ------------------------------------------------------------------------------------------------
// convert_to_grayscale converts the colour to grayscale in-place using luminance weighting.
convert_to_grayscale :: proc "contextless" (c: ^Colour) {
	r := f32(c.r)
	g := f32(c.g)
	b := f32(c.b)
	shade := u8(0.299 * r + 0.587 * g + 0.114 * b)
	c.r = shade
	c.g = shade
	c.b = shade
}

// ------------------------------------------------------------------------------------------------
// rng_state is the current state of the seedable Xorshift64 PRNG.
@(private)
rng_state: u64 = 1337

// ------------------------------------------------------------------------------------------------
// seed re-seeds the colour PRNG with the specified seed value.
// The seed value s must be non-zero; a value of zero is silently ignored.
seed :: proc "contextless" (s: u64) {
	if s != 0 {
		rng_state = s
	}
}

// ------------------------------------------------------------------------------------------------
// next_random generates the next pseudorandom 32-bit unsigned integer using Xorshift64.
@(private)
next_random :: proc "contextless" () -> u32 {
	rng_state ~= rng_state << 13
	rng_state ~= rng_state >> 7
	rng_state ~= rng_state << 17
	return u32(rng_state)
}

// ------------------------------------------------------------------------------------------------
// random_colour returns a random fully-opaque colour.
random_colour :: proc "contextless" () -> Colour {
	return Colour{r = u8(next_random()), g = u8(next_random()), b = u8(next_random()), a = 255}
}
