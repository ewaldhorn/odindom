// ------------------------------------------------------------------------------------------------
// odindom.js — JS glue for Odin WASM DOM manipulation.
//
// Provides two import modules to the WASM instance:
//   - "odin_env":    the handful of runtime hooks Odin's core library needs on the `js_wasm32`
//                     target (heap RNG seed, panic/print output, and float math intrinsics that
//                     have no native WASM opcode).
//   - "odindom_env": the DOM handle-table bridge that this library's `dom` package calls into.
//
// The host app must export two procedures for the loader to call:
//   - odindom_main             :: proc "c" ()          -- called once after instantiation
//   - odindom_invoke_callback  :: proc "c" (id: u32)    -- called for every registered event /
//                                                           animation-frame callback
// ------------------------------------------------------------------------------------------------

(() => {
  "use strict";

  const decoder = new TextDecoder("utf-8");
  const encoder = new TextEncoder("utf-8");

  // ----------------------------------------------------------------------------------------------
  // JS Value Handle Table
  // Stores references to live JS objects (DOM elements, document, etc.) indexed by integer
  // handles passed to/from Odin. Index 0 is always null / invalid.
  // ----------------------------------------------------------------------------------------------

  const jsValues = [null];
  let nextHandle = 1;

  function getHandle(value) {
    if (value === undefined || value === null) return 0;
    const id = nextHandle++;
    jsValues[id] = value;
    return id;
  }

  // ----------------------------------------------------------------------------------------------
  globalThis.OdinDom = {
    // extraImports: optional object of additional foreign import modules to merge in, e.g.
    // `{ odindom_demo_env: { drum_play_hit: (track) => { ... } } }` for app-specific foreign
    // procs declared outside the shared `dom` package (see docs/canvas_three.odin).
    instantiate: async function (wasmUrl, extraImports) {
      let wasmMemory;
      let wasmExports;
      let _renderCache = null; // cached Uint8ClampedArray + ImageData for dom_canvas_render

      function getStr(ptr, len) {
        return decoder.decode(new Uint8Array(wasmMemory.buffer, ptr, len));
      }
      function putStr(ptr, str, maxLen) {
        const encoded = encoder.encode(str);
        const len = maxLen !== undefined ? Math.min(encoded.length, maxLen) : encoded.length;
        new Uint8Array(wasmMemory.buffer, ptr, len).set(encoded.subarray(0, len));
        return len;
      }

      const importObject = {
        // ------------------------------------------------------------------------------------
        // Odin core-library runtime hooks (js_wasm32 target)
        // ------------------------------------------------------------------------------------
        odin_env: {
          write: (fd, ptr, len) => {
            const str = getStr(ptr, len);
            if (fd === 1) { console.log(str); return; }
            if (fd === 2) { console.error(str); return; }
          },
          trap: () => { throw new Error("odin: trap"); },
          abort: () => { throw new Error("odin: abort"); },
          alert: (ptr, len) => { alert(getStr(ptr, len)); },
          evaluate: (ptr, len) => { eval.call(null, getStr(ptr, len)); },
          open: (urlPtr, urlLen, namePtr, nameLen, specsPtr, specsLen) => {
            window.open(getStr(urlPtr, urlLen), getStr(namePtr, nameLen), getStr(specsPtr, specsLen));
          },
          time_now: () => BigInt(Date.now()),
          tick_now: () => performance.now(),
          time_sleep: () => {},
          sqrt: Math.sqrt,
          sin: Math.sin,
          cos: Math.cos,
          pow: Math.pow,
          fmuladd: (x, y, z) => x * y + z,
          ln: Math.log,
          exp: Math.exp,
          ldexp: (x, exp) => x * Math.pow(2, exp),
          rand_bytes: (ptr, len) => {
            crypto.getRandomValues(new Uint8Array(wasmMemory.buffer, ptr, len));
          },
        },

        // ------------------------------------------------------------------------------------
        // OdinDOM handle-table bridge
        // ------------------------------------------------------------------------------------
        odindom_env: {
          // -- Generic JS value access --
          dom_get_global: (ptr, len) => getHandle(globalThis[getStr(ptr, len)]),
          dom_get_property: (handle, keyPtr, keyLen) => getHandle(jsValues[handle][getStr(keyPtr, keyLen)]),

          // -- Element creation --
          dom_create_element: (tagPtr, tagLen) => getHandle(document.createElement(getStr(tagPtr, tagLen))),

          // -- Element manipulation --
          dom_append_child: (parent, child) => { jsValues[parent].appendChild(jsValues[child]); },
          dom_remove_all_children: (elem) => { jsValues[elem].replaceChildren(); },
          dom_set_inner_text: (elem, ptr, len) => { jsValues[elem].innerText = getStr(ptr, len); },
          dom_set_inner_html: (elem, ptr, len) => { jsValues[elem].innerHTML = getStr(ptr, len); },
          dom_set_property_str: (elem, keyPtr, keyLen, valPtr, valLen) => {
            jsValues[elem][getStr(keyPtr, keyLen)] = getStr(valPtr, valLen);
          },
          dom_get_property_str: (elem, keyPtr, keyLen, outPtr, outLen) => {
            const key = getStr(keyPtr, keyLen);
            const val = String(jsValues[elem][key]);
            return putStr(outPtr, val, outLen);
          },
          dom_set_class_name: (elem, ptr, len) => { jsValues[elem].className = getStr(ptr, len); },
          dom_class_list_add: (elem, ptr, len) => { jsValues[elem].classList.add(getStr(ptr, len)); },
          dom_class_list_remove: (elem, ptr, len) => { jsValues[elem].classList.remove(getStr(ptr, len)); },
          dom_set_display: (elem, ptr, len) => { jsValues[elem].style.display = getStr(ptr, len); },
          dom_call_focus: (elem) => { jsValues[elem].focus(); },
          dom_get_element_by_id: (ptr, len) => {
            const el = document.getElementById(getStr(ptr, len));
            return el ? getHandle(el) : 0;
          },

          // -- Style injection --
          dom_add_style_element: (ptr, len) => {
            const style = document.createElement("style");
            style.type = "text/css";
            style.innerHTML = getStr(ptr, len);
            document.head.appendChild(style);
          },

          // -- Events --
          dom_add_event_listener: (elem, eventPtr, eventLen, cbId) => {
            const event = getStr(eventPtr, eventLen);
            jsValues[elem].addEventListener(event, (evt) => {
              wasmExports.odindom_set_last_event(getHandle(evt));
              wasmExports.odindom_invoke_callback(cbId);
            });
          },

          // -- Canvas --
          dom_canvas_create: (parent, width, height) => {
            const canvas = document.createElement("canvas");
            canvas.width = width;
            canvas.height = height;
            jsValues[parent].appendChild(canvas);
            return getHandle(canvas);
          },
          dom_canvas_get_context: (canvas) => getHandle(jsValues[canvas].getContext("2d")),
          dom_canvas_render: (canvas, ctx, pixelsPtr, pixelsLen, width, height) => {
            const ctxEl = jsValues[ctx];
            if (
              !_renderCache ||
              _renderCache.pixelsPtr !== pixelsPtr ||
              _renderCache.width !== width ||
              _renderCache.height !== height ||
              _renderCache.array.buffer !== wasmMemory.buffer
            ) {
              const array = new Uint8ClampedArray(wasmMemory.buffer, pixelsPtr, width * height * 4);
              _renderCache = { array, imgData: new ImageData(array, width, height), pixelsPtr, width, height };
            }
            ctxEl.putImageData(_renderCache.imgData, 0, 0);
          },
          dom_start_animation_loop: (cbId) => {
            const tick = () => {
              wasmExports.odindom_invoke_callback(cbId);
              requestAnimationFrame(tick);
            };
            requestAnimationFrame(tick);
          },
          // -- Logging --
          dom_log: (ptr, len) => { console.log(getStr(ptr, len)); },
          dom_alert: (ptr, len) => { alert(getStr(ptr, len)); },
          dom_now: () => performance.now(),
        },
      };

      if (extraImports) {
        for (const mod of Object.keys(extraImports)) {
          importObject[mod] = { ...(importObject[mod] || {}), ...extraImports[mod] };
        }
      }

      let wasm;
      if (typeof WebAssembly.instantiateStreaming === "function") {
        wasm = await WebAssembly.instantiateStreaming(fetch(wasmUrl), importObject);
      } else {
        const bytes = await (await fetch(wasmUrl)).arrayBuffer();
        wasm = await WebAssembly.instantiate(bytes, importObject);
      }

      wasmExports = wasm.instance.exports;
      wasmMemory = wasmExports.memory;

      wasmExports.odindom_main();

      return wasmExports;
    },
  };
})();
