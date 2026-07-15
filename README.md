# OdinDOM

OdinDOM is a port of [GoDOM](../godom) (a Go WebAssembly DOM library) to [Odin](https://odin-lang.org), targeting the `js_wasm32` backend. 

Since Odin lacks Go's `syscall/js` for wrapping live JavaScript values, OdinDOM uses a handle-table design inspired by [ZigDOM](../zigdom).

## Quick Start

Run the following command to build the projects and start a local development server:

```sh
./run.sh
```

Once the server is running, open these URLs in your browser:
* **Interactive Demo:** [http://localhost:9000/docs/index.html](http://localhost:9000/docs/index.html)
* **Click Rect Example:** [http://localhost:9000/examples/click-rect/index.html](http://localhost:9000/examples/click-rect/index.html)
* **canvas_cmd Example:** [http://localhost:9000/examples/canvas-cmd/index.html](http://localhost:9000/examples/canvas-cmd/index.html)

> ⚠️ **Warning:** Do not open the HTML files directly (via `file://`). Browsers block WebAssembly fetches over local file paths due to CORS. You must access them through a local server (like the one started by `./run.sh`).

## Packages

| Package | Port of GoDOM's... | Notes |
| :--- | :--- | :--- |
| `dom` | `dom` | Provides DOM access. Uses a `distinct u32` handle table for JS interop since Odin lacks `syscall/js`. |
| `html` | `html` | HTML element builder. Same tags and modifiers as GoDOM, but uses plain procedures instead of dot-chaining. |
| `colour` | `colour` | Color utilities and PRNG (single-threaded for WASM). |
| `canvas` | `canvas` + `canvas_*` | Drawing primitives (Bresenham lines, circles, shapes), blitted to a canvas via `putImageData`. |
| `sound` | `sound` | Triangle-wave click synthesizer. |
| `canvas_cmd` | — | Retained draw-command buffer for driving a *real* `CanvasRenderingContext2D` (gradients, text, sprites) via one packed `foreign` flush per frame, instead of a pixel-buffer blit. Demoed by the demo's Canvas 4 (Grove & Pond). |

## How It Works

Because WebAssembly cannot directly access JavaScript objects, OdinDOM uses a **handle-table** system:

1. **JavaScript side (`web/odindom.js`):** Stores live JS objects (DOM elements, canvas contexts, events) in an array.
2. **Odin side (`dom/dom.odin`):** Receives and passes a `u32` wrapper called `dom.Handle` (the array index of the object) rather than the object itself.
3. **Communication:** Every DOM operation runs over a `foreign import` boundary.

### Key Implementation Details

* **Automatic Marshalling:** Odin `string` and `[]byte` values automatically marshal as `(pointer, length)` pairs across `foreign` imports. This allows passing strings and slices directly without manually unpacking them on the JS side.
* **Tiny Runtime Footprint:** A minimal program compiled with `-target:js_wasm32 -no-entry-point` only imports two functions for memory/panic support: `odin_env.write` and `odin_env.rand_bytes`. If you use `core:math` trigonometric functions, standard Math functions like `sin`, `cos`, and `pow` are automatically resolved via thin wrappers in `web/odindom.js`.

### No Method Chaining

GoDOM and ZigDOM support chained method calls (e.g., `html.Div().Class("x").Text("y")`). 

Odin has no methods or Uniform Function Call Syntax (UFCS). Because of this language design, OdinDOM uses plain procedures that pass the handle sequentially. This is the standard, idiomatic way to write Odin:

```odin
p := html.p()
html.set_id(p, "greeting")
html.text(p, "Hello")
html.append_to(p, parent)
```

### Event Callbacks

Odin does not support closures or Go's `js.FuncOf`. Instead, callbacks are dispatched using unique integer IDs. 

Your application must export two procedures to bridge JS and Odin:

```odin
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()
	// Build UI and bind an event:
	// dom.add_event_listener(elem, "click", MY_CALLBACK_ID)
}

@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case MY_CALLBACK_ID: // Handle event
	}
}
```

> 💡 **Note:** `context = runtime.default_context()` is required at the entry of every exported C-style procedure to re-establish Odin's thread-local runtime context.

#### Reading Event Data

When an event fires, `odindom.js` registers the active event in the handle table right before running the callback. You can inspect event properties (like click coordinates) using `dom.get`:

```odin
evt := dom.last_event_handle()
x, _ := strconv.parse_int(dom.get(evt, "offsetX"))
```

## Building

To build all examples and the demo site:

```sh
./build.sh
```

To compile a single target directly (e.g., `click-rect`):

```sh
odin build examples/click-rect \
  -out:examples/click-rect/click-rect.wasm \
  -target:js_wasm32 -o:size -no-entry-point
```

* `-target:js_wasm32` targets WebAssembly.
* `-no-entry-point` is required because the resulting WASM binary is loaded as a library and driven by JavaScript exports rather than running a standard `main` procedure.

## Examples

### 1. Click Rect (`examples/click-rect`)

A simple canvas rectangle that toggles colors when clicked. This is a direct port of GoDOM's basic click example and is used to verify canvas click coordinates.

---

### 2. canvas_cmd Basics (`examples/canvas-cmd`)

The smallest possible `canvas_cmd` demo: one tree, one duck swimming and bobbing on a pond, no interaction. Shows how to batch a frame of real Canvas2D commands (gradients, arcs, sprite baking) into a single WASM&harr;JS call, as a starting point before looking at the fuller `docs/canvas_four.odin` scene.

---

### 3. Full Interactive Demo (`docs`)

This is a complete port of GoDOM's original `demo/demo.go`. Unlike the simplified ZigDOM port, this version includes all original features, such as the full AI ship navigation and a high-precision wall-clock timer for the step sequencer.

The demo features:

#### 🎮 Four Interactive Canvases
* **Canvas 1: Synthwave AI Ship (`docs/canvas_one_ai.odin`)**
  An autopilot spacecraft navigating a synthwave starfield. It detects and dodges spawning obstacles (asteroids, energy bolts, enemies) with real-time threat evaluation and a live-score HUD.
* **Canvas 2: Ball Physics (`docs/canvas_two.odin`)**
  An interactive 14-ball physical simulation with collision detection, motion trails, and drag-to-push mouse interaction. You can dynamically cycle the gravity direction (down, left, up, right, or zero-g).
* **Canvas 3: Drum Sequencer (`docs/canvas_three.odin`)**
  A 16-step drum machine. It uses high-precision timing via `dom.now()` (`performance.now()`) to ensure the BPM remains perfectly stable regardless of your browser's frame rate.
* **Canvas 4: Grove & Pond (`docs/canvas_four.odin`)**
  An animated scene of trees and swimming ducks, rendered entirely through the `canvas_cmd` package — every gradient, path, and sprite blit for the frame is packed into one byte buffer and flushed to the real Canvas2D context with a single `foreign` call. A live HUD shows how many commands were batched into that one WASM↔JS crossing. Click the pond to spawn ripples.

#### 📝 DOM & HTML Showcase
* Demonstrates OdinDOM's HTML-builder utilities.
* Interactive DOM widgets including adding and clearing customizable side-notes, handle API inspection, and dynamic DOM manipulation.

#### 🎵 Audio Synthesizer
* Renders real-time synthwave sound effects and beats using an `AudioWorkletProcessor`.

---

### Verification & Testing

Since there is no traditional test suite, correctness is verified end-to-end in a headless Chrome environment. The verification checks:
* Gravity-mode switching in the physics engine.
* Interactive elements (adding/clearing side-notes).
* Step-sequencer state synchronization (verifying `odindom_drum_is_beat_active` changes before and after simulated clicks).
* Canvas 4's `canvas_cmd` HUD (batched command count) and click-to-ripple interaction on the pond.
