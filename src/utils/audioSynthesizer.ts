// Procedural Web Audio API sound generator for ambient focus and notifications

class AudioSynthesizer {
  private ctx: AudioContext | null = null;
  private ambientSourceNodes: { [key: string]: { stop: () => void; gain: GainNode } } = {};
  private masterGain: GainNode | null = null;

  private initContext() {
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this.ctx = new AudioCtx();
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.setValueAtTime(0.5, this.ctx.currentTime);
      this.masterGain.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  public setMasterVolume(vol: number) {
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setValueAtTime(Math.max(0, Math.min(1, vol)), this.ctx.currentTime);
    }
  }

  // Play a harmonic zen chime for session start/completion
  public playChime(type: 'success' | 'alert' = 'success') {
    try {
      this.initContext();
      if (!this.ctx) return;

      const now = this.ctx.currentTime;
      const freqs = type === 'success' ? [528, 660, 792, 1056] : [440, 392, 349];
      
      freqs.forEach((freq, index) => {
        if (!this.ctx) return;
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();

        osc.type = 'sine';
        osc.frequency.setValueAtTime(freq, now + index * 0.12);

        gain.gain.setValueAtTime(0.001, now + index * 0.12);
        gain.gain.exponentialRampToValueAtTime(0.18, now + index * 0.12 + 0.05);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + index * 0.12 + 1.8);

        osc.connect(gain);
        gain.connect(this.masterGain || this.ctx.destination);

        osc.start(now + index * 0.12);
        osc.stop(now + index * 0.12 + 2.0);
      });
    } catch {
      // Audio not permitted yet before user gesture
    }
  }

  // Stop ambient background sound
  public stopAmbient() {
    Object.keys(this.ambientSourceNodes).forEach(key => {
      try {
        this.ambientSourceNodes[key].stop();
      } catch {
        // already stopped
      }
      delete this.ambientSourceNodes[key];
    });
  }

  // Start procedural ambient sound
  public startAmbient(type: 'rain' | 'white_noise' | 'drone' | 'waves', volume: number = 0.4) {
    this.stopAmbient();
    if (type === 'none' as unknown as string) return;

    try {
      this.initContext();
      if (!this.ctx) return;

      const now = this.ctx.currentTime;
      const bufferSize = this.ctx.sampleRate * 2;
      const noiseBuffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
      const output = noiseBuffer.getChannelData(0);

      for (let i = 0; i < bufferSize; i++) {
        output[i] = Math.random() * 2 - 1;
      }

      if (type === 'white_noise' || type === 'rain' || type === 'waves') {
        const whiteNoise = this.ctx.createBufferSource();
        whiteNoise.buffer = noiseBuffer;
        whiteNoise.loop = true;

        const filter = this.ctx.createBiquadFilter();
        const gain = this.ctx.createGain();
        gain.gain.setValueAtTime(volume * 0.25, now);

        if (type === 'rain') {
          filter.type = 'bandpass';
          filter.frequency.setValueAtTime(1000, now);
          filter.Q.setValueAtTime(0.7, now);
        } else if (type === 'waves') {
          filter.type = 'lowpass';
          filter.frequency.setValueAtTime(450, now);
          // Modulate filter for wave crests
          const lfo = this.ctx.createOscillator();
          const lfoGain = this.ctx.createGain();
          lfo.frequency.setValueAtTime(0.12, now); // slow wave period
          lfoGain.gain.setValueAtTime(250, now);
          lfo.connect(lfoGain);
          lfoGain.connect(filter.frequency);
          lfo.start(now);
        } else {
          // Soft pink/brown noise
          filter.type = 'lowpass';
          filter.frequency.setValueAtTime(800, now);
        }

        whiteNoise.connect(filter);
        filter.connect(gain);
        gain.connect(this.masterGain || this.ctx.destination);

        whiteNoise.start(now);
        this.ambientSourceNodes[type] = {
          stop: () => {
            whiteNoise.stop();
            whiteNoise.disconnect();
          },
          gain
        };
      } else if (type === 'drone') {
        // Deep binaural sine drone
        const osc1 = this.ctx.createOscillator();
        const osc2 = this.ctx.createOscillator();
        const osc3 = this.ctx.createOscillator();
        const droneGain = this.ctx.createGain();

        droneGain.gain.setValueAtTime(volume * 0.2, now);

        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(136.1, now); // Earth Om frequency
        osc2.type = 'triangle';
        osc2.frequency.setValueAtTime(204.15, now);
        osc3.type = 'sine';
        osc3.frequency.setValueAtTime(272.2, now);

        const filter = this.ctx.createBiquadFilter();
        filter.type = 'lowpass';
        filter.frequency.setValueAtTime(320, now);

        osc1.connect(filter);
        osc2.connect(filter);
        osc3.connect(filter);
        filter.connect(droneGain);
        droneGain.connect(this.masterGain || this.ctx.destination);

        osc1.start(now);
        osc2.start(now);
        osc3.start(now);

        this.ambientSourceNodes['drone'] = {
          stop: () => {
            osc1.stop();
            osc2.stop();
            osc3.stop();
            osc1.disconnect();
            osc2.disconnect();
            osc3.disconnect();
          },
          gain: droneGain
        };
      }
    } catch {
      // Audio autoplay policy
    }
  }
}

export const soundEngine = new AudioSynthesizer();
