# Click-Rect Example: Step-by-Step Guide

This example is the simplest application in the OdinDOM repository. It displays a 300x300 canvas with a colored rectangle in the center. Clicking the rectangle toggles its color between blue and white.

This guide explains how this example works from the ground up, assuming you have basic Odin knowledge but no experience with **WebAssembly (WASM)** or **graphics rendering**.

---

## The Big Picture: How WebAssembly Runs in the Browser

To understand how this program works, we first need to understand the relationship between Odin, WebAssembly, and the browser:

```
┌────────────────────────────────────────────────────────┐
│                        BROWSER                         │
│                                                        │
│   ┌───────────────┐                  ┌─────────────┐   │
│   │  Web Page     │  Instantiates    │ JavaScript  │   │
│   │  (index.html) │─────────────────>│ (odindom.js)│   │
│   └───────┬───────┘                  └──────┬──────┘   │
│           │                                 │          │
│           │ Displays                        │ Bridges  │
│           v                                 v          │
│   ┌───────────────┐                  ┌─────────────┐   │
│   │ HTML Canvas   │<─────────────────│ WebAssembly │   │
│   │    Element    │  Copies Pixels   │ (compiled   │   │
│   │               │                  │ main.wasm)  │   │
│   └───────────────┘                  └─────────────┘   │
│                                                        │
└────────────────────────────────────────────────────────┘
```

1. **The Web Page (`index.html`)** loads our JavaScript bridge (`odindom.js`) and tells it to load and run the compiled WebAssembly file (`click-rect.wasm`).
2. **WebAssembly (WASM)** is compiled binary code (your Odin code). Browsers run WASM at near-native speed, but WASM is sandboxed—it cannot directly touch the webpage, print to the screen, or listen to mouse clicks.
3. **The JS Bridge (`odindom.js`)** acts as the mediator. It handles the browser's DOM (Document Object Model) and links browser events (like a click) back to Odin.

---

## How Computer Graphics Work (Software Rendering)

Instead of using complex 3D graphics APIs (like WebGL or WebGPU), this project uses a simple **Software Renderer**. 

### 1. The Pixel Buffer
In computer graphics, an image is a 2D grid of pixels. In our program:
* The canvas size is **300 pixels wide** by **300 pixels high** (defined by `CANVAS_W` and `CANVAS_H`).
* Each pixel is represented by **4 bytes** of color information:
  1. **R** (Red, 0-255)
  2. **G** (Green, 0-255)
  3. **B** (Blue, 0-255)
  4. **A** (Alpha/Transparency, 0-255)

Because we have $300 \times 300$ pixels, and each pixel needs 4 bytes, our image data is just a flat array of bytes in memory:
$$\text{Array Size} = 300 \times 300 \times 4 = 360,000 \text{ bytes}$$

In Odin, we declare this buffer like this:
```odin
pixels: [CANVAS_W * CANVAS_H * 4]byte
```

### 2. Rendering
1. **Odin writes color bytes** directly to specific positions in this `pixels` array (e.g., drawing a blue square in the middle of a black screen).
2. Once the drawing is complete, Odin calls `canvas.render(&c)`.
3. The JavaScript bridge copies the whole `pixels` byte array from WebAssembly memory straight onto the actual `<canvas>` element on the webpage.

### 3. The Coordinate System
Screen coordinates start at the **top-left corner `(0,0)`**:
* **X** increases as you move **right**.
* **Y** increases as you move **down**.

```
(0,0) --------------------------> +X
  |
  |       (RECT_X: 100, RECT_Y: 100)
  |             ┌──────────────┐
  |             │  Rectangle   │
  |             │   100x100    │
  |             └──────────────┘ (200,200)
  |
  v
 +Y
```

---

## Code Walkthrough

Let's go step-by-step through `main.odin` to see how it is put together.

### Step 1: Initializing Variables and Buffers
At the top of the file, we set up our variables:

```odin
blue := colour.Colour{r = 30, g = 100, b = 255, a = 255}
is_white := false

pixels: [CANVAS_W * CANVAS_H * 4]byte
c: canvas.Canvas
```
* `blue` defines our starting rectangle color.
* `is_white` is a boolean flag that tracks the state of the rectangle (whether it should be drawn white or blue).
* `pixels` is our raw pixel buffer in memory.
* `c` is a canvas structure that knows how to write colors to `pixels`.

### Step 2: Redrawing the Screen
Whenever we want to draw or update the visual display, we call `redraw`:

```odin
redraw :: proc() {
    // 1. Fill the entire canvas buffer with black bytes
    canvas.clear_screen(&c, colour.Black)

    // 2. Choose the color based on our state flag
    if is_white {
        canvas.colour_filled_rectangle(&c, RECT_X, RECT_Y, RECT_W, RECT_H, colour.White)
    } else {
        canvas.colour_filled_rectangle(&c, RECT_X, RECT_Y, RECT_W, RECT_H, blue)
    }

    // 3. Ask JS to copy our pixels buffer onto the HTML canvas on the webpage
    canvas.render(&c)
}
```

### Step 3: Bootstrapping (The Main Entry Point)
When the browser loads the page and instantiates WebAssembly, it automatically runs our exported main procedure:

```odin
@(export)
odindom_main :: proc "c" () {
    // Re-establish Odin's thread-local runtime environment
    context = runtime.default_context()

    // Initialize the OdinDOM library
    dom.init()

    // Create the canvas element in the webpage inside the <div id="app">
    c = canvas.new_canvas(CANVAS_W, CANVAS_H, pixels[:], "app")

    // Draw our initial frame (black background with a blue rectangle)
    redraw()

    // Tell JavaScript: "Listen for clicks on the '#app' div. If clicked,
    // invoke our callback with callback ID: CB_CANVAS_CLICK (0)"
    dom.add_event_listener_by_id("app", "click", CB_CANVAS_CLICK)
}
```

* `@(export)`: Tells the Odin compiler to make this function visible to JavaScript.
* `proc "c"`: Tells Odin to compile this function using standard C calling conventions, which is what the WebAssembly engine understands.
* `context = runtime.default_context()`: WebAssembly triggers this function from JavaScript outside of Odin. This line sets up Odin's internal system variables (like memory allocators and logger state) so the language functions correctly.

### Step 4: Handling Mouse Clicks
When a click occurs on the app, JavaScript calls our exported callback function:

```odin
@(export)
odindom_invoke_callback :: proc "c" (id: u32) {
    context = runtime.default_context()
    switch id {
    case CB_CANVAS_CLICK:
        // 1. Fetch a handle to the last browser event that was triggered
        evt := dom.last_event_handle()

        // 2. Ask JavaScript for the relative mouse coordinates on the canvas.
        // Because DOM properties are returned as strings, we parse them into integers.
        x, _ := strconv.parse_int(dom.get(evt, "offsetX"))
        y, _ := strconv.parse_int(dom.get(evt, "offsetY"))

        // 3. Check if the click landed inside our rectangle bounds:
        //    - X must be between RECT_X (100) and RECT_X + RECT_W (200)
        //    - Y must be between RECT_Y (100) and RECT_Y + RECT_H (200)
        if x >= RECT_X && x < RECT_X + RECT_W && y >= RECT_Y && y < RECT_Y + RECT_H {
            // Toggle the state flag and redraw!
            is_white = !is_white
            redraw()
        }
    }
}
```

* **No Closures:** Because Odin is compiled directly to machine-level WASM without a heavy runtime or JavaScript-style closure support, we cannot pass direct inline functions to browser events. Instead, we use unique integer IDs (`CB_CANVAS_CLICK`) so JavaScript can simply say, "Event ID `0` occurred."
* **Hit Detection:** Simple math checks if the coordinate point `(x, y)` is within the boundary box of our rectangle.

---

## How to Build and Run This

To compile and see your code in action:

1. **Build the WebAssembly binary:**
   From the repository root, run:
   ```sh
   odin build examples/click-rect \
     -out:examples/click-rect/click-rect.wasm \
     -target:js_wasm32 -o:size -no-entry-point
   ```
   *(The `-target:js_wasm32` compiles it to WebAssembly, and `-no-entry-point` is required because we are exporting library procedures driven by JavaScript instead of running a normal Odin terminal `main()`)*

2. **Serve the project:**
   Start the local static file server from the root of the project:
   ```sh
   ./run.sh
   ```

3. **Open the browser:**
   Navigate to [http://localhost:9000/examples/click-rect/index.html](http://localhost:9000/examples/click-rect/index.html) and click the rectangle!
