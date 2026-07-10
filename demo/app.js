"use strict";

// ------------------------------------------------------------------------------------------------
// app.js — demo-specific glue: Web Audio playback, drum machine tone synthesis, and scale-corrected
// canvas click/touch interaction. Ported from GoDOM's docs/app.js; the only WASM-interop-specific
// changes are the exported function names (odindom_* instead of go_*) and how the pre-rendered
// click buffer is read back (a raw pointer + length into WASM memory, since Odin has no
// CopyBytesToJS-style helper that hands back a ready-made typed array like Go's syscall/js does).
// ------------------------------------------------------------------------------------------------

let audioCtx = null;
let synthNode = null;
let gainNode = null;
let audioPlaying = false;
let globalVolume = 0.2;

// Cached DOM elements
let volumeSlider = null;
let volumeLabel = null;

// Cached audio buffers
let clickAudioBuffer = null;
let noiseBuffer = null;

// Pooled GainNodes for drum hits — avoids allocating a new node per hit
const DRUM_GAIN_POOL_SIZE = 8;
let drumGainPool = null;
let drumGainIdx = 0;

let wasmExports = null;

function ensureDrumGainPool() {
  if (!drumGainPool) {
    const ctx = ensureAudioCtx();
    drumGainPool = Array.from({ length: DRUM_GAIN_POOL_SIZE }, () => {
      const g = ctx.createGain();
      g.connect(ensureGainNode());
      return g;
    });
  }
  return drumGainPool;
}

function ensureAudioCtx() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  return audioCtx;
}

function ensureGainNode() {
  const ctx = ensureAudioCtx();
  if (!gainNode) {
    gainNode = ctx.createGain();
    gainNode.gain.setValueAtTime(globalVolume, ctx.currentTime);
    gainNode.connect(ctx.destination);
  }
  return gainNode;
}

function updateVolumeUI() {
  if (!volumeSlider) volumeSlider = document.getElementById("volumeSlider");
  if (!volumeLabel) volumeLabel = document.getElementById("volumeLabel");
  if (volumeSlider) volumeSlider.value = globalVolume;
  if (volumeLabel) {
    const pct = Math.round(globalVolume * 100);
    volumeLabel.innerText = globalVolume === 0 ? "Vol: OFF" : `Vol: ${pct}%`;
  }
}

function applyVolume() {
  if (gainNode && audioCtx) {
    gainNode.gain.setValueAtTime(globalVolume, audioCtx.currentTime);
  }
}

function adjustVolume(delta) {
  globalVolume = Math.max(0, Math.min(1, Math.round((globalVolume + delta) * 100) / 100));
  applyVolume();
  updateVolumeUI();
}

globalThis.changeVolume = function (val) {
  globalVolume = parseFloat(val);
  applyVolume();
  updateVolumeUI();
};

globalThis.toggleAudio = async function () {
  const ctx = ensureAudioCtx();

  if (!synthNode) {
    // Load the AudioWorkletProcessor module (dedicated audio thread)
    await ctx.audioWorklet.addModule('synth-worklet.js');

    // Create the synth AudioWorkletNode and connect through shared gain
    synthNode = new AudioWorkletNode(ctx, 'synth-worklet');
    synthNode.connect(ensureGainNode());
  }

  if (ctx.state === "suspended") {
    await ctx.resume();
  }

  audioPlaying = !audioPlaying;

  // Send play state to the worklet's dedicated audio thread
  synthNode.port.postMessage({ type: 'play', value: audioPlaying });

  const btn = document.getElementById("audioToggleButton");
  if (btn) {
    btn.innerText = audioPlaying ? "🔊 Mute Soundtrack" : "🔇 Play Soundtrack";
    btn.classList.toggle("playing", audioPlaying);
  }
};

// Click sound — pre-rendered 50ms UI click read back from OdinDOM's WASM memory.

globalThis.playClickSound = function () {
  const ctx = ensureAudioCtx();
  if (ctx.state === "suspended") {
    ctx.resume();
  }

  // Lazy AudioBuffer creation from pre-rendered WASM samples
  if (!clickAudioBuffer) {
    const ptr = wasmExports.odindom_get_click_buffer_ptr();
    const len = wasmExports.odindom_get_click_buffer_len();
    const samples = new Float32Array(wasmExports.memory.buffer, ptr, len);
    clickAudioBuffer = ctx.createBuffer(1, len, 44100);
    clickAudioBuffer.copyToChannel(samples, 0);
  }

  const source = ctx.createBufferSource();
  source.buffer = clickAudioBuffer;
  source.connect(ensureGainNode()); // route through shared volume gain
  source.start();
};

// Drum machine — tone map per track
const DRUM_FREQS = [60, 200, 8000, 6000, 1200, 400]; // kick, snare, hh-c, hh-o, clap, rim
const DRUM_TYPES = ["sine", "triangle", "square", "square", "noise", "noise"];

globalThis.drumHit = function (track) {
  const ctx = ensureAudioCtx();
  if (ctx.state === "suspended") {
    ctx.resume();
  }

  const pool = ensureDrumGainPool();
  const gain = pool[drumGainIdx];
  drumGainIdx = (drumGainIdx + 1) % DRUM_GAIN_POOL_SIZE;
  gain.gain.cancelScheduledValues(ctx.currentTime);
  gain.gain.setValueAtTime(0.4, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.08);

  if (DRUM_TYPES[track] === "noise") {
    if (!noiseBuffer) {
      noiseBuffer = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.05), ctx.sampleRate);
      const data = noiseBuffer.getChannelData(0);
      for (let i = 0; i < data.length; i += 1) data[i] = Math.random() * 2 - 1;
    }

    const src = ctx.createBufferSource();
    src.buffer = noiseBuffer;
    src.connect(gain);
    src.start();
    src.stop(ctx.currentTime + 0.06);
    return;
  }

  const osc = ctx.createOscillator();
  osc.type = DRUM_TYPES[track] || "sine";
  osc.frequency.setValueAtTime(DRUM_FREQS[track] || 220, ctx.currentTime);
  osc.frequency.exponentialRampToValueAtTime(20, ctx.currentTime + 0.06);
  osc.connect(gain);
  osc.start();
  osc.stop(ctx.currentTime + 0.1);
};

// Arrow key volume control (↑ = +1%, ↓ = −1%) & Space crash
document.addEventListener('keydown', function (e) {
  if (e.key === 'ArrowUp') {
    e.preventDefault();
    adjustVolume(+0.01);
  } else if (e.key === 'ArrowDown') {
    e.preventDefault();
    adjustVolume(-0.01);
  } else if (e.code === 'Space') {
    // Easter egg: crash cymbal accent
    if (synthNode && synthNode.port) {
      e.preventDefault();
      synthNode.port.postMessage({ type: 'crash' });
    }
  }
});

function initializeInteractions() {
  // Wire click sound to action buttons (skip audioToggleButton — that's the synth)
  ['addSomethingButton', 'clearAsideButton', 'refreshButton', 'drumPlayButton', 'gravityButton'].forEach(function (id) {
    const btn = document.getElementById(id);
    if (btn) btn.addEventListener('click', playClickSound);
  });

  // Touch / Click interaction for the physics canvas (canvas two)
  const canvasTwoDiv = document.getElementById("canvasTwoDiv");
  if (canvasTwoDiv) {
    let canvas = null;
    let isDragging = false;
    let cachedRectTwo = null;

    window.addEventListener('resize', () => { cachedRectTwo = null; });

    const handleInteraction = (clientX, clientY) => {
      if (!canvas) canvas = canvasTwoDiv.querySelector("canvas");
      if (!canvas) return;
      if (!cachedRectTwo) cachedRectTwo = canvas.getBoundingClientRect();
      if (cachedRectTwo.width === 0 || cachedRectTwo.height === 0) return;
      // Map from CSS pixels to canvas pixel space
      const scaleX = canvas.width / cachedRectTwo.width;
      const scaleY = canvas.height / cachedRectTwo.height;
      const x = Math.round((clientX - cachedRectTwo.left) * scaleX);
      const y = Math.round((clientY - cachedRectTwo.top) * scaleY);
      wasmExports.odindom_set_interaction(x, y);
      wasmExports.odindom_invoke_callback(4); // 4 = onCanvasInteraction
    };

    canvasTwoDiv.addEventListener("mousedown", (e) => {
      if (e.target.tagName === "CANVAS") {
        e.preventDefault();
        isDragging = true;
        handleInteraction(e.clientX, e.clientY);
      }
    });

    // Continue pushing balls while dragging across the canvas
    canvasTwoDiv.addEventListener("mousemove", (e) => {
      if (isDragging) {
        e.preventDefault();
        handleInteraction(e.clientX, e.clientY);
      }
    });

    document.addEventListener("mouseup", () => { isDragging = false; });

    canvasTwoDiv.addEventListener("touchstart", (e) => {
      if (e.target.tagName === "CANVAS") {
        e.preventDefault();
        const touch = e.touches[0];
        handleInteraction(touch.clientX, touch.clientY);
      }
    }, { passive: false });

    // Continuous touch drag
    canvasTwoDiv.addEventListener("touchmove", (e) => {
      if (e.target.tagName === "CANVAS") {
        e.preventDefault();
        const touch = e.touches[0];
        handleInteraction(touch.clientX, touch.clientY);
      }
    }, { passive: false });
  }

  // Touch / Click interaction for the sequencer canvas (canvas three)
  const canvasThreeDiv = document.getElementById("canvasThreeDiv");
  if (canvasThreeDiv) {
    let canvas = null;
    let cachedRectThree = null;

    window.addEventListener('resize', () => { cachedRectThree = null; });

    const handleInteraction = (clientX, clientY) => {
      if (!canvas) canvas = canvasThreeDiv.querySelector("canvas");
      if (!canvas) return;
      if (!cachedRectThree) cachedRectThree = canvas.getBoundingClientRect();
      if (cachedRectThree.width === 0 || cachedRectThree.height === 0) return;
      // Map from CSS pixels to canvas pixel space
      const scaleX = canvas.width / cachedRectThree.width;
      const scaleY = canvas.height / cachedRectThree.height;
      const x = Math.round((clientX - cachedRectThree.left) * scaleX);
      const y = Math.round((clientY - cachedRectThree.top) * scaleY);
      wasmExports.odindom_set_interaction(x, y);
      wasmExports.odindom_invoke_callback(6); // 6 = onDrumCanvasClick
    };

    canvasThreeDiv.addEventListener("mousedown", (e) => {
      if (e.target.tagName === "CANVAS") {
        e.preventDefault();
        handleInteraction(e.clientX, e.clientY);
      }
    });

    canvasThreeDiv.addEventListener("touchstart", (e) => {
      if (e.target.tagName === "CANVAS") {
        e.preventDefault();
        const touch = e.touches[0];
        handleInteraction(touch.clientX, touch.clientY);
      }
    }, { passive: false });
  }

  // Show controls as flex
  const controls = document.getElementById("controls");
  if (controls) controls.style.display = "flex";
}

// Instantiate the OdinDOM WASM module. The demo needs one foreign import beyond the shared
// odindom_env DOM bridge — odindom_demo_env.drum_play_hit — for the drum machine sequencer
// (see demo/canvas_three.odin), routed through to the Web Audio synthesis above.
OdinDom.instantiate("demo.wasm", {
  odindom_demo_env: {
    drum_play_hit: (track) => { drumHit(track); },
  },
}).then((exports) => {
  wasmExports = exports;
  document.getElementById("loading").style.display = "none";
  initializeInteractions();
}).catch((err) => {
  console.error("OdinDOM demo failed to load:", err);
  document.getElementById("loading").innerText = "Failed to load WASM: " + err.message;
});
