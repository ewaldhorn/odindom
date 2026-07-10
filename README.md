# OdinDOM

A port of [GoDOM](../godom) to [Odin](https://odin-lang.org), targeting Odin's `js_wasm32`
backend. A [ZigDOM](../zigdom) port of the same library already exists; OdinDOM follows its
handle-table interop design where Odin's own constraints require a different approach than Go's.

## Quick start

```sh
./run.sh   # builds every example + the demo, then serves the repo root on :9000
```

Then open `http://localhost:9000/examples/click-rect/index.html` or
`http://localhost:9000/demo/index.html`. This matches the `run.sh` convention used by
[GoDOM](../godom) and [ZigDOM](../zigdom) — build, then serve on `:9000` via
`http-server -c-1` (cache disabled, so a rebuilt `.wasm` is always picked up).

**Do not open the HTML files directly (`file://...`).** Every example loads its `.wasm` via
`fetch()`, which Chrome/Firefox/Safari all block under CORS for the `file://` origin — you'll see
a `TypeError: Failed to fetch` in the console with no useful indication of why. This must be
served over `http://` or `https://`.

## Packages

| Package  | Port of GoDOM's...    | Notes |
|----------|------------------------|-------|
| `dom`    | `dom`                  | `Handle` is a `distinct u32` id into a JS-side object table (see below), not a `js.Value` wrapper — Odin has no equivalent of `syscall/js`. |
| `html`   | `html`                 | Same tag set and modifier set as GoDOM, but no `.Class(x).Text(y)` chaining — see "No method-call syntax" below. |
| `colour` | `colour`               | Identical API; PRNG is not atomic (WASM here is single-threaded, so no `sync/atomic` needed). |
| `canvas` | `canvas` + `canvas_*`  | Identical drawing primitives (Bresenham line/circle, filled/border circle, rectangle, triangle). |
| `sound`  | `sound`                | Identical triangle-wave click synthesizer. |

## How it works

Odin's `js_wasm32` target has no `syscall/js`-equivalent capable of wrapping arbitrary live JS
values, so — like ZigDOM — OdinDOM implements its own **handle table**: `web/odindom.js` keeps a
JS-side array of live objects (DOM elements, the 2D context, event objects, …) and hands Odin back
a `u32` index (`dom.Handle`) instead of the object itself. Every DOM operation is a `foreign
import` call across that boundary (see `dom/dom.odin`).

Two things made this port straightforward to verify:

- **Odin strings and slices already marshal as `(ptr, len)` pairs** across `foreign import`
  calls — confirmed empirically before writing any real code (see the ABI notes below). This
  meant the interop layer could pass `string` and `[]byte` directly instead of manually splitting
  pointers and lengths, unlike ZigDOM's Zig code.
- **The runtime footprint is tiny.** A minimal Odin program compiled with
  `-target:js_wasm32 -no-entry-point` only imports two things beyond your own foreign functions:
  `odin_env.write` and `odin_env.rand_bytes` (pulled in by the default heap allocator and panic
  path). Using `core:math` trig/pow functions additionally pulls in `odin_env.sin` / `.cos` /
  `.pow` / `.ln` / `.exp` / `.fmuladd` — `web/odindom.js` implements all of these as one-liners
  wrapping the equivalent `Math.*` call, mirroring what Odin's own (much larger) official
  `odin.js` runtime does.

### No method-call syntax

GoDOM and ZigDOM both read fluently: `html.Div().Class("x").Text("y").AppendTo(parent)`. That's
real dot-chaining in Go and Zig — Zig's `struct { pub fn method(self: *const T, ...) }` are
genuine namespaced methods. **Odin has no methods on types and no UFCS** (verified directly — a
`proc(self: ^T, ...)` cannot be called as `value.proc(...)`). So `html` builder calls take and
return `dom.Handle` (aliased as `html.Elm`) as plain procedures:

```odin
p := html.p()
html.set_id(p, "greeting")
html.text(p, "Hello")
html.append_to(p, parent)
```

This is the idiomatic Odin shape (see `examples/click-rect` and `demo`) rather than a workaround —
forcing a chained illusion would fight the language.

### Event callbacks

GoDOM passes a `js.Value` closure directly to `AddEventListener`. Odin has nothing like
`js.FuncOf`, so — again following ZigDOM — callbacks are dispatched by small integer id. Your
program's `main` package must export two procedures:

```odin
@(export)
odindom_main :: proc "c" () {
	context = runtime.default_context()
	// ... build your UI, call dom.add_event_listener(elem, "click", MY_CALLBACK_ID) ...
}

@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
	context = runtime.default_context()
	switch id {
	case MY_CALLBACK_ID: /* ... */
	}
}
```

`context = runtime.default_context()` is required in every exported proc — Odin's `context` is
thread-local runtime state that must be re-established at each JS→Odin boundary crossing.

To read event fields (e.g. `offsetX`/`offsetY` on a click), `odindom.js` hands the raw JS `Event`
object into the handle table and calls `odindom_set_last_event(handle)` immediately before
`odindom_invoke_callback`, so inside your callback:

```odin
evt := dom.last_event_handle()
x, _ := strconv.parse_int(dom.get(evt, "offsetX"))
```

(`dom.get` mirrors GoDOM's `Handle.Get`, which also stringifies the underlying JS value.)

## Building

```sh
./build.sh                       # builds every example + the demo to <name>.wasm
odin build examples/click-rect \
  -out:examples/click-rect/click-rect.wasm \
  -target:js_wasm32 -o:size -no-entry-point
```

`-no-entry-point` is required since these are libraries driven by JS, not `package main` programs
with an entry `main` proc.

Then serve the repo root with `./run.sh` (or any static file server — just not `file://`, see
"Quick start" above) and open `examples/click-rect/index.html` or `demo/index.html`.

## Examples

- **`examples/click-rect`** — direct port of GoDOM's `examples/click-rect`: a canvas rectangle
  that toggles colour on click, verified against real click coordinates.
- **`demo`** — a full port of GoDOM's `demo/demo.go`, ported directly from the Go source (not from
  ZigDOM's simplified version, which drops the AI ship system and uses a coarser sequencer clock —
  see `demo/canvas_one_ai.odin` and `dom.now()` below). Three canvases: a synthwave gallery with an
  AI-controlled ship that dodges spawning obstacles (asteroids/bolts/enemies) and a live dodge-count
  score HUD, an animated 14-ball physics simulation with switchable gravity
  (down/left/up/right/zero-g), collision, motion trails, and drag-to-push interaction, and a 16-step
  drum machine sequencer stepped by real wall-clock time (`dom.now()`, i.e. `performance.now()`) so
  BPM stays accurate regardless of frame rate. Plus the full DOM/`html`-builder showcase (random
  aside notes/tags/quips, handle-based API demos, wrapped elements) and a synthwave soundtrack via
  an `AudioWorkletProcessor`. `demo/app.js`, `demo/styles.css`, and `demo/synth-worklet.js` are
  adapted directly from GoDOM's/ZigDOM's own demo assets (pure CSS/Web-Audio JS, not Odin-specific)
  rather than rewritten from scratch.

Both were verified running end-to-end in a real headless Chrome instance — not just compiled —
including gravity-mode cycling, aside note add/clear, and drum-pad step toggling checked against
`odindom_drum_is_beat_active` before/after a dispatched click.
