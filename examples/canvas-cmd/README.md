# canvas_cmd Example: One Tree, One Duck

This example is the smallest possible demo of OdinDOM's `canvas_cmd` package: a static tree and a
duck that swims back and forth across a pond, bobbing gently on the water. Nothing is clickable —
the whole point of this example is to show how a frame gets drawn, not how to wire up interaction
(see [`examples/click-rect`](../click-rect) for that).

This guide assumes you've already read the `click-rect` example's README (WASM basics, the
handle-table, `odindom_main`/`odindom_invoke_callback`). It focuses on what's *different* about
`canvas_cmd`.

---

## Why not just use `canvas` (like click-rect)?

`click-rect` draws by writing raw RGBA bytes into a `[]byte` pixel buffer and blitting the whole
thing to a `<canvas>` with `putImageData`. That's simple and fast, but it's a dead end for:

* **Gradients** — the sky and pond in this example are gradients; a pixel buffer would need you to
  compute every pixel's color by hand.
* **Anti-aliased curves** — `canvas.colour_filled_circle` draws a *pixelated* circle (Bresenham).
  The duck and tree canopy in this example are smooth, because they're real `arc()`/`ellipse()`
  calls on the browser's Canvas2D renderer.
* **Text, images, and the rest of the Canvas2D API** — fonts, `drawImage`, shadows, clipping —
  none of that exists in a raw pixel buffer.

So instead, `canvas_cmd` drives a *real* `CanvasRenderingContext2D` — the same object you'd get
from `canvas.getContext("2d")` in plain JS. The catch: Odin has no `syscall/js`, so every
individual Canvas2D call (`fillRect`, `arc`, `fill`, ...) would normally mean one
WASM&harr;JS `foreign` crossing. At 60 frames per second, with a scene made of dozens of draw
calls, that adds up.

`canvas_cmd`'s fix: record an entire frame's worth of commands into one packed byte buffer in
WASM memory, then make exactly **one** `foreign` call (`dom_canvas_cmd_flush`) to hand the whole
buffer to JS. JS walks the buffer and replays each command onto the context. Encoding logic lives
in Odin (`canvas_cmd.odin`); JS is just a mechanical dispatcher (`web/odindom.js`).

```
┌──────────────────────────────┐        ONE foreign call         ┌──────────────────────────┐
│ WASM (Odin)                  │ ───────────────────────────────>│ JS (odindom.js)          │
│  set_fill(...)                │   dom_canvas_cmd_flush(ctx, buf) │  while (more bytes) {    │
│  fill_rect(...)               │                                  │    switch (opcode) {     │
│  begin_path() ; arc(...)      │                                  │      case FILL_RECT: ... │
│  fill()                       │                                  │      case ARC: ...       │
│  draw_sprite(...)             │                                  │      ...                 │
│  ... (packed into `cmd`)      │                                  │    }                     │
└──────────────────────────────┘                                  └──────────────────────────┘
```

---

## Sprites: don't re-encode art you're not changing

The tree in this scene never changes. Re-recording its trunk + three canopy circles into the
command buffer every single frame would be wasted work — small, but pointless. `canvas_cmd`'s
answer is **sprite baking**:

1. `bake_begin(&cmd, sprite_id, w, h)` — subsequent draw commands target an *offscreen* canvas
   (created lazily on the JS side, cached by `sprite_id`) instead of the visible one.
2. Draw the artwork as normal (paths, fills, arcs — whatever it takes).
3. `bake_end(&cmd)` — subsequent commands go back to drawing on the real, visible canvas.
4. From then on, every frame just calls `draw_sprite(&cmd, sprite_id, x, y)` — one cheap command
   that tells JS "blit that offscreen canvas here," no matter how much artwork went into it.

This example bakes the tree and the duck once, in `bake_sprites()`, called a single time from
`odindom_main`. `draw_frame()` — which runs every animation frame — only ever calls `draw_sprite`/
`draw_sprite_scaled` for them, never re-encodes their paths.

> The duck needs to flip horizontally depending on which way it's swimming. Rather than baking two
> mirrored sprites, this example passes a **negative width** to `draw_sprite_scaled` — the same
> trick you'd use with `ctx.drawImage(img, x, y, -w, h)` in plain JS.

---

## Code Walkthrough

### 1. Getting a 2D context (not a `canvas.Canvas`!)

```odin
canvas_h := dom.canvas_create(dom.get_element_by_id("app"), CANVAS_W, CANVAS_H)
ctx = dom.canvas_get_context(canvas_h)
```

`click-rect` calls `canvas.new_canvas(...)`, which returns a `canvas.Canvas` (a pixel buffer +
render helper). `canvas_cmd` doesn't use that type at all — it just needs the raw
`dom.Handle` of the `<canvas>` element's 2D context, which `dom_canvas_cmd_flush` replays commands
onto directly. `dom.canvas_create` + `dom.canvas_get_context` are the same two lower-level calls
`canvas.new_canvas` uses internally — see `dom/canvas_dom.odin`.

### 2. Baking the sprites once

```odin
bake_sprites :: proc() {
	canvas_cmd.reset(&cmd)

	canvas_cmd.bake_begin(&cmd, SPRITE_TREE, TREE_W, TREE_H)
	// ... trunk fill_rect, three canopy arc()+fill() calls ...
	canvas_cmd.bake_end(&cmd)

	canvas_cmd.bake_begin(&cmd, SPRITE_DUCK, DUCK_W, DUCK_H)
	// ... body/wing ellipses, head arc, beak path, eye dot ...
	canvas_cmd.bake_end(&cmd)

	canvas_cmd.flush(ctx, &cmd)
}
```

Note the explicit `flush(ctx, &cmd)` at the end — baking only takes effect once JS actually
receives and replays the buffer. `reset()` at the top rewinds the buffer to empty; it's a
fixed-capacity arena reused every time, so there's no per-call allocation.

### 3. The per-frame draw

```odin
draw_frame :: proc() {
	time += 1.0 / 60.0
	canvas_cmd.reset(&cmd)

	// sky gradient, ground fill, pond gradient — see below
	// ...

	canvas_cmd.draw_sprite(&cmd, SPRITE_TREE, TREE_X - TREE_W / 2, HORIZON_Y - TREE_H)

	// duck position/animation math, then:
	canvas_cmd.draw_sprite_scaled(&cmd, SPRITE_DUCK, duck_x - DUCK_W/2, POND_CY + bob - DUCK_H/2, dw, DUCK_H)

	canvas_cmd.flush(ctx, &cmd)
}
```

Gradients (`linear_gradient` / `add_color_stop` / `use_gradient_fill`) are re-recorded every frame
— unlike sprites, they bake in absolute pixel coordinates, so they can't be baked once and reused
if anything about the scene could move. In this example nothing about the sky/pond actually
changes frame to frame, but recomputing them costs almost nothing next to the fixed cost of the
one `flush()` call, so there's no reason to bother baking them too.

Six draw commands (gradient×2, two fills, two sprite blits) get packed into `cmd` and handed to JS
in a single `foreign` call — that's the whole per-frame WASM&harr;JS cost, regardless of how
detailed the tree or duck artwork is.

### 4. Driving it every frame

```odin
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()
	dom.init()
	// ... create canvas, bake sprites ...
	dom.start_animation_loop(CB_ANIMATION_TICK)
}

@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case CB_ANIMATION_TICK:
		draw_frame()
	}
}
```

`dom.start_animation_loop(cb_id)` asks the browser for `requestAnimationFrame` callbacks and
invokes `odindom_invoke_callback(cb_id)` on each one — this is the *only* reason this example
needs `odindom_invoke_callback` at all, since (unlike `click-rect`) nothing here is clickable.

---

## How to Build and Run This

1. **Build the WebAssembly binary** (from the repository root):
   ```sh
   odin build examples/canvas-cmd \
     -out:examples/canvas-cmd/canvas-cmd.wasm \
     -target:js_wasm32 -o:size -no-entry-point
   ```
   Or just run `./build.sh` from the repo root, which builds every example.

2. **Serve the project:**
   ```sh
   ./run.sh
   ```

3. **Open the browser:**
   Navigate to
   [http://localhost:9000/examples/canvas-cmd/index.html](http://localhost:9000/examples/canvas-cmd/index.html)
   and watch the duck swim.

## Where to go next

* `docs/canvas_four.odin` — the same idea scaled up: multiple trees, multiple ducks, a
  click-to-ripple interaction, and a live HUD showing how many commands got batched into each
  frame's single `flush()` call.
* `canvas_cmd/canvas_cmd.odin` — the full package: every opcode, every drawing/gradient/shadow/
  transform helper, and the wire-format documentation at the top of the file.
