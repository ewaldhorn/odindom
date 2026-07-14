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
      // canvas_cmd persistent state (survives across frames/flushes):
      const _cmdGradients = new Map(); // grad_id -> CanvasGradient
      const _cmdSprites = new Map();   // sprite_id -> { canvas, ctx } offscreen bake target
      let _cmdMeasureCtx = null;       // dedicated ctx for measureText

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
          dom_set_style: (elem, kPtr, kLen, vPtr, vLen) => {
            jsValues[elem].style[getStr(kPtr, kLen)] = getStr(vPtr, vLen);
          },
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

          // -- Retained draw-command buffer (canvas_cmd package) --
          // Walks a packed byte buffer produced by Odin and replays each op onto the 2D context.
          // Wire format documented in canvas_cmd/canvas_cmd.odin. One foreign call per frame.
          dom_canvas_cmd_flush: (ctx, bufPtr, bufLen) => {
            const buf = wasmMemory.buffer;
            const bytes = new Uint8Array(buf, bufPtr, bufLen);
            const view = new DataView(buf, bufPtr, bufLen);
            let p = 0;
            const f = () => { const v = view.getFloat32(p, true); p += 4; return v; };
            const u8 = () => bytes[p++];
            const u16 = () => { const v = view.getUint16(p, true); p += 2; return v; };
            const str = () => {
              const n = view.getUint16(p, true); p += 2;
              const s = decoder.decode(new Uint8Array(buf, bufPtr + p, n)); p += n;
              return s;
            };
            // `c` is the active target: the flush context, or a sprite's offscreen context while
            // baking. Gradients and sprites persist across frames, keyed by app-chosen ids.
            const mainCtx = jsValues[ctx];
            let c = mainCtx;
            const grads = _cmdGradients;
            const sprites = _cmdSprites;
            while (p < bufLen) {
              switch (bytes[p++]) {
                case 0x01: c.fillStyle = str(); break;
                case 0x02: c.strokeStyle = str(); break;
                case 0x03: c.lineWidth = f(); break;
                case 0x04: c.font = str(); break;
                case 0x05: c.textAlign = str(); break;
                case 0x06: c.textBaseline = str(); break;
                case 0x07: c.globalAlpha = f(); break;
                case 0x08: c.lineCap = str(); break;
                case 0x10: c.fillRect(f(), f(), f(), f()); break;
                case 0x11: c.strokeRect(f(), f(), f(), f()); break;
                case 0x12: c.clearRect(f(), f(), f(), f()); break;
                case 0x20: c.beginPath(); break;
                case 0x21: c.moveTo(f(), f()); break;
                case 0x22: c.lineTo(f(), f()); break;
                case 0x23: c.closePath(); break;
                case 0x24: { const x = f(), y = f(), r = f(), a0 = f(), a1 = f(); c.arc(x, y, r, a0, a1, u8() !== 0); break; }
                case 0x25: { const x = f(), y = f(), rx = f(), ry = f(), rot = f(), a0 = f(), a1 = f(); c.ellipse(x, y, rx, ry, rot, a0, a1, u8() !== 0); break; }
                case 0x26: c.rect(f(), f(), f(), f()); break;
                case 0x27: c.bezierCurveTo(f(), f(), f(), f(), f(), f()); break;
                case 0x28: c.fill(); break;
                case 0x29: c.stroke(); break;
                case 0x2A: c.clip(); break;
                case 0x30: { const s = str(); c.fillText(s, f(), f()); break; }
                case 0x31: { const s = str(); c.strokeText(s, f(), f()); break; }
                case 0x40: c.save(); break;
                case 0x41: c.restore(); break;
                case 0x42: c.translate(f(), f()); break;
                case 0x43: c.scale(f(), f()); break;
                case 0x44: c.rotate(f()); break;
                case 0x45: c.setTransform(f(), f(), f(), f(), f(), f()); break;
                case 0x46: c.resetTransform(); break;
                case 0x50: { const id = u16(); grads.set(id, c.createLinearGradient(f(), f(), f(), f())); break; }
                case 0x51: { const id = u16(); grads.set(id, c.createRadialGradient(f(), f(), f(), f(), f(), f())); break; }
                case 0x52: { const g = grads.get(u16()); const o = f(); const col = str(); if (g) g.addColorStop(o, col); break; }
                case 0x53: { const g = grads.get(u16()); if (g) c.fillStyle = g; break; }
                case 0x54: { const g = grads.get(u16()); if (g) c.strokeStyle = g; break; }
                case 0x60: { const s = sprites.get(u16()); const dx = f(), dy = f(); if (s) c.drawImage(s.canvas, dx, dy); break; }
                case 0x61: { const s = sprites.get(u16()); const dx = f(), dy = f(), dw = f(), dh = f(); if (s) c.drawImage(s.canvas, dx, dy, dw, dh); break; }
                case 0x62: { const s = sprites.get(u16()); const sx = f(), sy = f(), sw = f(), sh = f(), dx = f(), dy = f(), dw = f(), dh = f(); if (s) c.drawImage(s.canvas, sx, sy, sw, sh, dx, dy, dw, dh); break; }
                case 0x70: { c.shadowColor = str(); c.shadowBlur = f(); break; }
                case 0x71: { c.shadowColor = "rgba(0,0,0,0)"; c.shadowBlur = 0; break; }
                case 0x80: {
                  const id = u16(), w = u16(), h = u16();
                  let s = sprites.get(id);
                  if (!s || s.canvas.width !== w || s.canvas.height !== h) {
                    const cv = document.createElement("canvas");
                    cv.width = w; cv.height = h;
                    s = { canvas: cv, ctx: cv.getContext("2d") };
                    sprites.set(id, s);
                  } else {
                    s.ctx.clearRect(0, 0, w, h);
                  }
                  c = s.ctx;
                  break;
                }
                case 0x81: c = mainCtx; break;
                default: return; // unknown opcode — bail rather than desync
              }
            }
          },
          dom_measure_text: (fontPtr, fontLen, textPtr, textLen) => {
            if (!_cmdMeasureCtx) {
              _cmdMeasureCtx = document.createElement("canvas").getContext("2d");
            }
            _cmdMeasureCtx.font = getStr(fontPtr, fontLen);
            return _cmdMeasureCtx.measureText(getStr(textPtr, textLen)).width;
          },
          // -- Logging --
          dom_log: (ptr, len) => { console.log(getStr(ptr, len)); },
          dom_alert: (ptr, len) => { alert(getStr(ptr, len)); },
          dom_now: () => performance.now(),

          // -- Generic method-call / numeric-property bridge --
          dom_call_method0: (elem, namePtr, nameLen) => {
            jsValues[elem][getStr(namePtr, nameLen)]();
          },
          dom_call_method_ret: (elem, namePtr, nameLen) => {
            return getHandle(jsValues[elem][getStr(namePtr, nameLen)]());
          },
          dom_call_method1f: (elem, namePtr, nameLen, a) => {
            jsValues[elem][getStr(namePtr, nameLen)](a);
          },
          dom_call_method2f: (elem, namePtr, nameLen, a, b) => {
            jsValues[elem][getStr(namePtr, nameLen)](a, b);
          },
          dom_call_method1h: (elem, namePtr, nameLen, arg) => {
            jsValues[elem][getStr(namePtr, nameLen)](jsValues[arg]);
          },
          dom_set_property_f64: (elem, keyPtr, keyLen, value) => {
            jsValues[elem][getStr(keyPtr, keyLen)] = value;
          },

          // -- Web Audio --
          dom_new_audio_context: () => {
            const Ctor = globalThis.AudioContext || globalThis.webkitAudioContext;
            return Ctor ? getHandle(new Ctor()) : 0;
          },

          // -- localStorage --
          dom_local_storage_get_item: (keyPtr, keyLen, outPtr, outLen) => {
            const val = localStorage.getItem(getStr(keyPtr, keyLen));
            if (val === null) return -1;
            return putStr(outPtr, val, outLen);
          },
          dom_local_storage_set_item: (keyPtr, keyLen, valPtr, valLen) => {
            localStorage.setItem(getStr(keyPtr, keyLen), getStr(valPtr, valLen));
          },
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
