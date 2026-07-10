// ------------------------------------------------------------------------------------------------
// synth-worklet.js — AudioWorkletProcessor: 1980s Retrowave Synthesizer
// Pure Web Audio API JS — reused as-is from the GoDOM/ZigDOM ports; runs on the dedicated audio
// thread and has no dependency on the WASM module itself beyond postMessage play/crash events.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// Music Theory & Sequencer Data
// ------------------------------------------------------------------------------------------------

// A minor Chord Progression: Am -> F -> C -> G (64 steps total, 16 steps per bar)
// MIDI note pitches:
const CHORD_BASS_LOW = [33.0, 29.0, 36.0, 31.0];   // A1, F1, C2, G1
const CHORD_BASS_HIGH = [45.0, 41.0, 48.0, 43.0];  // A2, F2, C3, G2

const CHORD_ARPS = [
  [57.0, 60.0, 64.0, 69.0], // Am (A3, C4, E4, A4)
  [53.0, 57.0, 60.0, 65.0], // F  (F3, A3, C4, F4)
  [60.0, 64.0, 67.0, 72.0], // C  (C4, E4, G4, C5)
  [55.0, 59.0, 62.0, 67.0], // G  (G3, B3, D4, G4)
];

// Dotted eighth/sixteenth arpeggiator repeating pattern
const ARP_PATTERN = [0, 1, 2, 3, 2, 1, 0, 2];

// Step duration at 125 BPM: (44100 * 60) / (125 * 4) = 5292 samples per 16th note step
const SAMPLES_PER_STEP = 5292;
const SAMPLE_RATE = 44100;

// ------------------------------------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------------------------------------

function midiToFreq(midi) {
  return 440.0 * Math.pow(2.0, (midi - 69.0) / 12.0);
}

function softClip(x) {
  return x / (1.0 + Math.abs(x));
}

// Simple xorshift32 PRNG for drum noise synthesis
function xorshift32(state) {
  let x = state;
  x ^= x << 13;
  x ^= x >>> 17;
  x ^= x << 5;
  return x >>> 0;
}

// ------------------------------------------------------------------------------------------------
// Envelope Stage
// ------------------------------------------------------------------------------------------------
const EnvStage = Object.freeze({ ATTACK: 0, DECAY: 1, SUSTAIN: 2, RELEASE: 3, IDLE: 4 });

// ------------------------------------------------------------------------------------------------
// Synthesizer State
// ------------------------------------------------------------------------------------------------

class SynthEngine {
  constructor() {
    // Sequencer counters
    this.currentSample = 0;
    this.currentStep = 0;

    // Voice 1: Bass (Detuned Dual-Sawtooth)
    this.bassPhase1 = 0.0;
    this.bassPhase2 = 0.0;
    this.bassFreq1 = 0.0;
    this.bassFreq2 = 0.0;
    this.bassEnvAmp = 0.0;
    this.bassEnvStage = EnvStage.IDLE;

    // Voice 2: Arp Lead (Triangle)
    this.arpPhase = 0.0;
    this.arpFreq = 0.0;
    this.arpEnvAmp = 0.0;
    this.arpEnvStage = EnvStage.IDLE;

    // Voice 3: Kick Drum (sine wave with frequency sweep)
    this.kickPhase = 0.0;
    this.kickEnvAmp = 0.0;
    this.kickEnvStage = EnvStage.IDLE;

    // Voice 4: Snare Drum (tone + noise burst)
    this.snarePhase = 0.0;
    this.snareNoiseState = 1;
    this.snareEnvAmp = 0.0;
    this.snareEnvStage = EnvStage.IDLE;

    // Voice 5: Hi-hat (differentiated noise for high-pass effect)
    this.hatNoiseState = 2;
    this.hatPrevNoise = 0.0;
    this.hatEnvAmp = 0.0;
    this.hatEnvStage = EnvStage.IDLE;

    // Voice 6: Crash Cymbal (noise burst → bandpass → long decay)
    this.crashNoiseState = 3;
    this.crashPrevNoise1 = 0.0;
    this.crashPrevNoise2 = 0.0;
    this.crashEnvAmp = 0.0;
    this.crashEnvStage = EnvStage.IDLE;

    // Drum layering timer (resets on each play start)
    this.totalElapsed = 0;

    // Dotted-eighth echo delay line (approx 360ms delay at 44.1kHz = 15876 samples)
    this.delayBuffer = new Float32Array(16000);
    this.delayWritePtr = 0;

    // Playing state
    this.playing = false;
  }

  triggerBass(midiNote) {
    const baseF = midiToFreq(midiNote);
    this.bassFreq1 = baseF;
    this.bassFreq2 = baseF * 1.006; // detune for chorus effect
    this.bassEnvStage = EnvStage.ATTACK;
  }

  triggerArp(midiNote) {
    this.arpFreq = midiToFreq(midiNote);
    this.arpEnvStage = EnvStage.ATTACK;
  }

  triggerKick() {
    this.kickPhase = 0.0;
    this.kickEnvStage = EnvStage.ATTACK;
  }

  triggerSnare() {
    this.snarePhase = 0.0;
    this.snareEnvStage = EnvStage.ATTACK;
  }

  triggerHat() {
    this.hatEnvStage = EnvStage.ATTACK;
  }

  triggerCrash() {
    this.crashEnvStage = EnvStage.ATTACK;
  }

  handleSequencerStep() {
    const stepInChord = this.currentStep % 16;
    const chordIdx = Math.floor(this.currentStep / 16);

    // 1. Trigger the Arpeggiator Lead on every step (sixteenth notes)
    const arpNoteIdx = ARP_PATTERN[stepInChord % ARP_PATTERN.length];
    const arpNote = CHORD_ARPS[chordIdx][arpNoteIdx % CHORD_ARPS[chordIdx].length];
    this.triggerArp(arpNote);

    // 2. Trigger the driving octave Bass on even steps (eighth notes)
    if (this.currentStep % 2 === 0) {
      const isOffbeat = (this.currentStep % 4) === 2;
      const bassNote = isOffbeat ? CHORD_BASS_HIGH[chordIdx] : CHORD_BASS_LOW[chordIdx];
      this.triggerBass(bassNote);
    }

    // 3. Drum patterns — layered in at 30s and 60s
    const stepInBar = this.currentStep % 16;
    if (this.totalElapsed >= 1323000) {       // 30 seconds: Layer 1
      // Kick on beats 1 and 3 (steps 0, 8)
      if (stepInBar === 0 || stepInBar === 8) {
        this.triggerKick();
      }
      // Hi-hat on beats 2 and 4 (steps 4, 12)
      if (stepInBar === 4 || stepInBar === 12) {
        this.triggerHat();
      }
      if (this.totalElapsed >= 2646000) {     // 60 seconds: Layer 2
        // Snare on beats 2 and 4
        if (stepInBar === 4 || stepInBar === 12) {
          this.triggerSnare();
        }
        // Extra hi-hat on eighth-note offbeats (steps 2, 6, 10, 14)
        if (stepInBar === 2 || stepInBar === 6 || stepInBar === 10 || stepInBar === 14) {
          this.triggerHat();
        }
      }
      if (this.totalElapsed >= 3969000) {     // 90 seconds: Layer 3
        // Syncopated snare accents on offbeat eighths (steps 3, 7, 11, 15)
        if (stepInBar === 3 || stepInBar === 7 || stepInBar === 11 || stepInBar === 15) {
          this.triggerSnare();
        }
      }
    }
  }

  nextSample() {
    // Check sequencer step boundaries
    if (this.currentSample >= SAMPLES_PER_STEP) {
      this.currentSample = 0;
      this.currentStep = (this.currentStep + 1) % 64;
      this.handleSequencerStep();
    }

    // Gate Off (note release) transitions:
    // Arpeggiator release starts at 75% of sixteenth note step
    if (this.currentSample === 3969) {
      if (this.arpEnvStage !== EnvStage.IDLE) this.arpEnvStage = EnvStage.RELEASE;
    }
    // Bass release starts at 50% of eighth note step (which is step 1, half-sample count)
    if (this.currentStep % 2 === 1 && this.currentSample === 2646) {
      if (this.bassEnvStage !== EnvStage.IDLE) this.bassEnvStage = EnvStage.RELEASE;
    }

    this.currentSample += 1;
    this.totalElapsed += 1;

    // ----------------------------------------------------------------------------------------
    // Render Bass Voice (Detuned Dual-Sawtooth)
    // ----------------------------------------------------------------------------------------
    let bassOut = 0.0;
    if (this.bassEnvStage !== EnvStage.IDLE) {
      // Oscillator 1
      this.bassPhase1 += this.bassFreq1 / SAMPLE_RATE;
      if (this.bassPhase1 >= 1.0) this.bassPhase1 -= 1.0;
      const osc1 = -1.0 + 2.0 * this.bassPhase1;

      // Oscillator 2 (slightly detuned)
      this.bassPhase2 += this.bassFreq2 / SAMPLE_RATE;
      if (this.bassPhase2 >= 1.0) this.bassPhase2 -= 1.0;
      const osc2 = -1.0 + 2.0 * this.bassPhase2;

      // Envelope calculations
      const attackRate = 1.0 / (0.005 * SAMPLE_RATE);    // 5ms attack
      const decayRate = (1.0 - 0.45) / (0.10 * SAMPLE_RATE);  // 100ms decay to 45% sustain
      const releaseRate = 0.45 / (0.12 * SAMPLE_RATE);   // 120ms release

      switch (this.bassEnvStage) {
        case EnvStage.ATTACK:
          this.bassEnvAmp += attackRate;
          if (this.bassEnvAmp >= 1.0) {
            this.bassEnvAmp = 1.0;
            this.bassEnvStage = EnvStage.DECAY;
          }
          break;
        case EnvStage.DECAY:
          this.bassEnvAmp -= decayRate;
          if (this.bassEnvAmp <= 0.45) {
            this.bassEnvAmp = 0.45;
            this.bassEnvStage = EnvStage.SUSTAIN;
          }
          break;
        case EnvStage.SUSTAIN:
          break;
        case EnvStage.RELEASE:
          this.bassEnvAmp -= releaseRate;
          if (this.bassEnvAmp <= 0.0) {
            this.bassEnvAmp = 0.0;
            this.bassEnvStage = EnvStage.IDLE;
          }
          break;
        default:
          break;
      }

      bassOut = 0.5 * (osc1 + osc2) * this.bassEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Arpeggiator Lead Voice (Triangle)
    // ----------------------------------------------------------------------------------------
    let arpOut = 0.0;
    if (this.arpEnvStage !== EnvStage.IDLE) {
      this.arpPhase += this.arpFreq / SAMPLE_RATE;
      if (this.arpPhase >= 1.0) this.arpPhase -= 1.0;

      // Triangle Wave
      const osc = this.arpPhase < 0.5
        ? -1.0 + 4.0 * this.arpPhase
        : 3.0 - 4.0 * this.arpPhase;

      // Envelope calculations
      const attackRate = 1.0 / (0.015 * SAMPLE_RATE);   // 15ms attack
      const decayRate = (1.0 - 0.35) / (0.15 * SAMPLE_RATE);  // 150ms decay to 35% sustain
      const releaseRate = 0.35 / (0.22 * SAMPLE_RATE);  // 220ms release

      switch (this.arpEnvStage) {
        case EnvStage.ATTACK:
          this.arpEnvAmp += attackRate;
          if (this.arpEnvAmp >= 1.0) {
            this.arpEnvAmp = 1.0;
            this.arpEnvStage = EnvStage.DECAY;
          }
          break;
        case EnvStage.DECAY:
          this.arpEnvAmp -= decayRate;
          if (this.arpEnvAmp <= 0.35) {
            this.arpEnvAmp = 0.35;
            this.arpEnvStage = EnvStage.SUSTAIN;
          }
          break;
        case EnvStage.SUSTAIN:
          break;
        case EnvStage.RELEASE:
          this.arpEnvAmp -= releaseRate;
          if (this.arpEnvAmp <= 0.0) {
            this.arpEnvAmp = 0.0;
            this.arpEnvStage = EnvStage.IDLE;
          }
          break;
        default:
          break;
      }

      arpOut = osc * this.arpEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Kick Drum (sine wave with frequency sweep)
    // ----------------------------------------------------------------------------------------
    let kickOut = 0.0;
    if (this.kickEnvStage !== EnvStage.IDLE) {
      // Frequency sweep: 150Hz → 40Hz tied to envelope decay
      const sweepPos = 1.0 - this.kickEnvAmp;
      const freq = 150.0 + (40.0 - 150.0) * Math.min(sweepPos, 1.0);
      this.kickPhase += freq / SAMPLE_RATE;
      if (this.kickPhase >= 1.0) this.kickPhase -= 1.0;
      const osc = Math.sin(2.0 * Math.PI * this.kickPhase);

      const attackRate = 1.0 / (0.001 * SAMPLE_RATE);   // 1ms attack
      const decayRate = 1.0 / (0.300 * SAMPLE_RATE);    // 300ms decay

      switch (this.kickEnvStage) {
        case EnvStage.ATTACK:
          this.kickEnvAmp += attackRate;
          if (this.kickEnvAmp >= 1.0) { this.kickEnvAmp = 1.0; this.kickEnvStage = EnvStage.DECAY; }
          break;
        case EnvStage.DECAY:
          this.kickEnvAmp -= decayRate;
          if (this.kickEnvAmp <= 0.0) { this.kickEnvAmp = 0.0; this.kickEnvStage = EnvStage.IDLE; }
          break;
        default:
          break;
      }
      kickOut = osc * this.kickEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Snare Drum (200Hz tone + noise burst)
    // ----------------------------------------------------------------------------------------
    let snareOut = 0.0;
    if (this.snareEnvStage !== EnvStage.IDLE) {
      this.snarePhase += 200.0 / SAMPLE_RATE;
      if (this.snarePhase >= 1.0) this.snarePhase -= 1.0;
      const tone = Math.sin(2.0 * Math.PI * this.snarePhase);
      this.snareNoiseState = xorshift32(this.snareNoiseState);
      const noise = (this.snareNoiseState & 0x7FFFFFFF) / 0x7FFFFFFF * 2.0 - 1.0;

      const attackRate = 1.0 / (0.001 * SAMPLE_RATE);   // 1ms attack
      const decayRate = 1.0 / (0.150 * SAMPLE_RATE);    // 150ms decay

      switch (this.snareEnvStage) {
        case EnvStage.ATTACK:
          this.snareEnvAmp += attackRate;
          if (this.snareEnvAmp >= 1.0) { this.snareEnvAmp = 1.0; this.snareEnvStage = EnvStage.DECAY; }
          break;
        case EnvStage.DECAY:
          this.snareEnvAmp -= decayRate;
          if (this.snareEnvAmp <= 0.0) { this.snareEnvAmp = 0.0; this.snareEnvStage = EnvStage.IDLE; }
          break;
        default:
          break;
      }
      snareOut = (tone * 0.5 + noise * 0.5) * this.snareEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Hi-hat (differentiated noise for high-pass effect)
    // ----------------------------------------------------------------------------------------
    let hatOut = 0.0;
    if (this.hatEnvStage !== EnvStage.IDLE) {
      this.hatNoiseState = xorshift32(this.hatNoiseState);
      const noise = (this.hatNoiseState & 0x7FFFFFFF) / 0x7FFFFFFF * 2.0 - 1.0;
      const hpNoise = noise - this.hatPrevNoise;
      this.hatPrevNoise = noise;

      const attackRate = 1.0 / (0.001 * SAMPLE_RATE);   // 1ms attack
      const decayRate = 1.0 / (0.060 * SAMPLE_RATE);    // 60ms decay

      switch (this.hatEnvStage) {
        case EnvStage.ATTACK:
          this.hatEnvAmp += attackRate;
          if (this.hatEnvAmp >= 1.0) { this.hatEnvAmp = 1.0; this.hatEnvStage = EnvStage.DECAY; }
          break;
        case EnvStage.DECAY:
          this.hatEnvAmp -= decayRate;
          if (this.hatEnvAmp <= 0.0) { this.hatEnvAmp = 0.0; this.hatEnvStage = EnvStage.IDLE; }
          break;
        default:
          break;
      }
      hatOut = hpNoise * this.hatEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Crash Cymbal (noise → cascaded 2-pole bandpass → long decay)
    // ----------------------------------------------------------------------------------------
    let crashOut = 0.0;
    if (this.crashEnvStage !== EnvStage.IDLE) {
      // White noise generator into 2-pole bandpass (cascade of HP + LP)
      this.crashNoiseState = xorshift32(this.crashNoiseState);
      const noise = (this.crashNoiseState & 0x7FFFFFFF) / 0x7FFFFFFF * 2.0 - 1.0;
      // First high-pass (differentiator) → removes rumble
      const hp = noise - this.crashPrevNoise1;
      this.crashPrevNoise1 = noise;
      // Second high-pass → pushes energy into the bright shimmer range
      const hp2 = hp - this.crashPrevNoise2;
      this.crashPrevNoise2 = hp;

      const attackRate = 1.0 / (0.003 * SAMPLE_RATE);   // 3ms attack
      const decayRate = 1.0 / (0.800 * SAMPLE_RATE);    // 800ms decay

      switch (this.crashEnvStage) {
        case EnvStage.ATTACK:
          this.crashEnvAmp += attackRate;
          if (this.crashEnvAmp >= 1.0) { this.crashEnvAmp = 1.0; this.crashEnvStage = EnvStage.DECAY; }
          break;
        case EnvStage.DECAY:
          this.crashEnvAmp -= decayRate;
          if (this.crashEnvAmp <= 0.0) { this.crashEnvAmp = 0.0; this.crashEnvStage = EnvStage.IDLE; }
          break;
        default:
          break;
      }
      crashOut = hp2 * this.crashEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Mix & Echo Delay Effect
    // ----------------------------------------------------------------------------------------

    // Drum volume layering: subtle at 30s, full at 60s
    const drumVol = (this.totalElapsed >= 2646000) ? 1.0 : (this.totalElapsed >= 1323000 ? 0.35 : 0.0);

    const mixed = (bassOut * 0.32) + (arpOut * 0.20)
                + (kickOut * 0.40 * drumVol)
                + (snareOut * 0.22 * drumVol)
                + (hatOut * 0.10 * drumVol)
                + (crashOut * 0.50);

    // Fetch spatial echo from delay line (3 sixteenth notes = 15876 samples)
    const delaySamples = 15876;
    const delayCapacity = this.delayBuffer.length;
    const readPtr = (this.delayWritePtr + (delayCapacity - delaySamples)) % delayCapacity;
    const echo = this.delayBuffer[readPtr];

    // Write feedback to circular buffer
    this.delayBuffer[this.delayWritePtr] = mixed + (echo * 0.45);
    this.delayWritePtr = (this.delayWritePtr + 1) % delayCapacity;

    // Combine Dry and Wet (echo) signals
    const finalOut = mixed * 0.75 + echo * 0.32;

    return softClip(finalOut);
  }
}

// ------------------------------------------------------------------------------------------------
// AudioWorkletProcessor
// ------------------------------------------------------------------------------------------------

class SynthWorkletProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.synth = new SynthEngine();

    // Listen for control messages from the main thread
    this.port.onmessage = (event) => {
      const msg = event.data;
      if (typeof msg !== 'object' || msg === null) return;
      switch (msg.type) {
        case 'play':
          this.synth.playing = typeof msg.value === 'boolean' ? msg.value : false;
          // Reset sequencer and drum timer on play start for clean loop entry
          if (msg.value) {
            this.synth.currentSample = 0;
            this.synth.currentStep = 0;
            this.synth.totalElapsed = 0;
          }
          break;
        case 'crash':
          if (this.synth.playing) {
            this.synth.triggerCrash();
          }
          break;
      }
    };
  }

  process(inputs, outputs, parameters) {
      try {
          const output = outputs[0];
          if (!output || output.length === 0) return true;

          const channelData = output[0];
          if (!channelData || channelData.length === 0) return true;

          if (!this.synth.playing) {
              channelData.fill(0);
              return true;
          }

          for (let i = 0; i < channelData.length; i++) {
              channelData[i] = this.synth.nextSample();
          }

      } catch (err) {
          console.error("Synth worklet error:", err);

          // output silence instead of dying
          const out = outputs[0]?.[0];
          if (out) out.fill(0);
      }

      return true;
  }
}

registerProcessor('synth-worklet', SynthWorkletProcessor);
