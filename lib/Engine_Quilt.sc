Engine_Quilt : CroneEngine {
	var <synth;
	var params;

	alloc {
		var server = Crone.server;
		var def;

		~sawBuffer = Buffer.alloc(server, 512, 1);
		~sawValues = (0..(~sawBuffer.numFrames-1)).collect { |i| (i / (~sawBuffer.numFrames-1)) * 2 - 1 };
		~sawBuffer.loadCollection(~sawValues);

		// ------------------------------------
		// helper fns

		~hzToVolts = { |freq|
			(freq / 20).log2;
		};

		~voltsToHz = { |volts|
			20 * (2 ** volts);
		};

		~instantCutoff = { |baseCutoffHz, cutoffOffnessPct, keyHz, keyTrackPct, keyTrackNegOffsetPct, eg, envelopePct|
			var baseCutoffVolts = ~hzToVolts.(baseCutoffHz);
			var cutoffOffnessVolts = cutoffOffnessPct * 10 / 4; // NB: max offness by 2.5 volt

			var keyVolts = ~hzToVolts.(keyHz);
			var keyTrackNegOffsetVolts = keyTrackNegOffsetPct * 10;
			var egVolts = eg * 10;

			var keyModVolts = (keyVolts - keyTrackNegOffsetVolts) * keyTrackPct;
			var egModVolts  = egVolts  * envelopePct;

			var totalVolts = baseCutoffVolts + cutoffOffnessVolts + keyModVolts + egModVolts;

			var instantCutoffHz = ~voltsToHz.(totalVolts);

			instantCutoffHz = instantCutoffHz.clip(20, 20000);

			instantCutoffHz;
		};


		// ------------------------------------

		def = SynthDef(\Quilt, {
			arg out = 0,
			gate = 0,
			gate_pair_in = 0,
			gate_pair_out = 0,
			vel = 0.5,
			freq = 200,
			raw_osc_cutoff = 10000,
			phased_cutoff = 10000,
			freq_sag = 0.1,
			vib_rate = 5,
			vib_depth = 0.0,
			// segmented oscilators
			index1 = 0.0,
			index2 = 0.0,
			index3 = 0.0,
			index4 = 0.0,
			amp1 = 0.5,
			amp2 = 0.5,
			amp3 = 0.5,
			amp4 = 0.5,
			// npolar projection
			mod = 3,
			syncRatio = 1,
			syncPhase = 0.0,
			npolarProj = 1.0,
			npolarRotFreq = 10,
			npolarRotFreq_sag = 0.1,
			npolarProjSliced = 1.0,
			npolarRotFreqSliced = 10,
			npolarRotFreqSliced_sag = 0.1,
			// phase mod
			pmFreq = 0.5,
			pmAmt = 0,
			// amp env
			amp_offset = 0.0,
			attack = 0.1, decay = 0.1, sustain = 0.7, release = 0.5,
			// filter env
			fenv_a = 1.0,
			fktrack = 0.1,
			fktrack_neg_offset = 0.0,
			fattack = 0.1, fdecay = 0.1, fsustain = 0.7, frelease = 0.5,
			// filter
			cutoff = 1200,
			cutoff_sag = 0.1,
			resonance = 0.0,
			// panning
			pan = 0,
			pan_lfo_amount = 0.1,
			pan_lfo_freq = 5,
			pan_lfo_phase = 0,
			// offness
			phase_offset = 0.0,
			pitch_offness_max = 0.0,
			pitch_offness_pct = 0.0,
			cutoff_offness_max = 0.0,
			cutoff_offness_pct = 0.0,
			// saturation/compression
			sat_threshold = 0.5;

			// frequencies
			var semitoneDiff, hzTrack, fsemitoneDiff;
			var vibrato, freqSagLfo, freq2;
			var cutoffSagLfo, cutoff2;
			var npolarRotFreqSagLfo, npolarRotFreq2;
			var npolarRotFreqSlicedSagLfo, npolarRotFreqSliced2;
			// basic waveforms
			var sin, saw, triangle, square;
			// looked-up waveforms (by index)
			var signal1, signal2, signal3, signal4;
			// amp enveloppe
			var env, pairingInEnv, pairingOutEnv, scaledEnv;
			// filter enveloppe
			var fenv, instantCutoff;
			// processed waveform
			var mixed, phased, filtered, ironed, saturated, compressed;

			// CMOS-derived waveforms
			var crossing, counter, crossingSliced, counterSliced;
			// computed modulation index, associated phaser signals
			var modphase, phase, phase2, phaseSliced, phaseSliced2;
			var pm;

			vibrato = SinOsc.kr(vib_rate, 0, vib_depth);

			// NB: this sounds meh and is heavy in processing...
			// TODO: implement standard vibrrato w/ slightly detuned voices

			semitoneDiff = freq * (2 ** (1/12) - 1);
			fsemitoneDiff = cutoff * (2 ** (1/12) - 1);
			// freqSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * freq_sag * semitoneDiff;
			// freq2 = freq + freqSagLfo + vibrato;

			// cutoffSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * cutoff_sag * semitoneDiff;
			// cutoff2 = cutoff + cutoffSagLfo;

			// npolarRotFreqSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * npolarRotFreq_sag * semitoneDiff;
			// npolarRotFreq2 = npolarRotFreq + npolarRotFreqSagLfo;

			// npolarRotFreqSlicedSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * npolarRotFreqSliced_sag * semitoneDiff;
			// npolarRotFreqSliced2 = npolarRotFreqSliced + npolarRotFreqSlicedSagLfo;

			freq2 = freq + vibrato + ((semitoneDiff) * pitch_offness_max * pitch_offness_pct);
			// cutoff2 = cutoff + (7000 * cutoff_offness_max * cutoff_offness_pct);
			npolarRotFreq2 = npolarRotFreq;
			npolarRotFreqSliced2 = npolarRotFreqSliced;

			hzTrack = freq2.cpsmidi / 12;

			sin = SinOsc.ar(freq2) * 0.5; // FIX: needed to half amp for sine
			saw = MoogFF.ar(in: Saw.ar(freq2), freq: raw_osc_cutoff);
			triangle = MoogFF.ar(in: LFTri.ar(freq2), freq: raw_osc_cutoff);
			square = MoogFF.ar(in: Pulse.ar(freq: freq2, width: 0.5), freq: raw_osc_cutoff);

			pm = SinOsc.ar(pmFreq) * pmAmt;

			crossing = Osc.ar(~sawBuffer, freq2 * 2, pi + (pm + syncPhase).linlin(-1, 1, -2pi, 2pi)) * 0.25;
			counter = PulseCount.ar(crossing) % mod;

			crossingSliced = Osc.ar(~sawBuffer, freq2 * syncRatio * 2, pi + (pm + syncPhase).linlin(-1, 1, -2pi, 2pi)) * 0.25;
			counterSliced = PulseCount.ar(crossingSliced) % mod;

			modphase = if(mod % 2 == 0, { mod - 1 }, { mod });

			// REVIEW: use wavetable instead?
			signal1 = Select.ar(index1, [sin, triangle, saw, square]);// * amp1 * SinOsc.kr(npolarRotFreq, 0.0);
			signal2 = Select.ar(index2, [sin, triangle, saw, square]);// * amp2 * SinOsc.kr(npolarRotFreq, 2pi / mod);
			signal3 = Select.ar(index3, [sin, triangle, saw, square]);// * amp3 * SinOsc.kr(npolarRotFreq, 2 * 2pi / mod);
			signal4 = Select.ar(index4, [sin, triangle, saw, square]);// * amp4 * SinOsc.kr(npolarRotFreq, 3 * 2pi / mod);

			mixed = Select.ar(counterSliced, [signal1, signal2, signal3, signal4]);

			phase = SinOsc.ar(npolarRotFreq2, counter * 2pi/modphase, npolarProj);
			phase2 = if(mod % 2 == 0, { phase }, { (1.0 - phase) });

			phaseSliced = SinOsc.ar(npolarRotFreqSliced2, counterSliced * 2pi/modphase, npolarProjSliced);
			phaseSliced2 = if(mod % 2 == 0, { phaseSliced }, { (1.0 - phaseSliced) });

			phased = mixed * phase2 * phaseSliced2;

			phased =  MoogFF.ar(in: phased, freq: phased_cutoff);

			env = EnvGen.kr(Env.adsr(attack, decay, sustain, release), gate, doneAction: 0);
			// NB: enveloppes for when a voice is dynamically paired
			pairingInEnv  = EnvGen.kr(Env.adsr(0.7, 0, sustain, 0), gate_pair_in, doneAction: 0);
			pairingOutEnv = EnvGen.kr(Env.adsr(0, 0, sustain, 0.7), gate_pair_out, doneAction: 0);
			scaledEnv = (1 - amp_offset) * (env + pairingInEnv + pairingOutEnv) + amp_offset;

			// fenv = EnvGen.kr(Env.adsr(fattack, fdecay, fsustain, frelease), gate, doneAction: 0) * (fenv_a / 2);
			fenv = EnvGen.kr(Env.adsr(fattack, fdecay, fsustain, frelease), gate, doneAction: 0);

			// instantCutoff = (cutoff2 + (fktrack * (freq2.cpsmidi).clip(21, 127).linexp(21, 127, 27.5, 12543.85)) + fenv.linlin(0, 1, 0, 15000)).clip(20, 20000);
			instantCutoff = ~instantCutoff.(cutoff, cutoff_offness_max * cutoff_offness_pct,
				freq2, fktrack, fktrack_neg_offset,
				fenv, fenv_a);

			filtered = MoogFF.ar(in: phased,
				freq: instantCutoff,
				gain: resonance) * 0.5 * vel * scaledEnv;

			ironed = BPeakEQ.ar(filtered, 200, rq: 1, db: 6 * (1-sat_threshold));

			saturated = (ironed * (2 - sat_threshold)).tanh;

			// compressed = Compander.ar(
			// 	saturated, //
			// 	ironed, // ctr signal -> input, but pre-saturation
			// 	thresh: sat_threshold.clip(0.1, 1),
			// 	slopeBelow: 1,  // 1 means no comp pre-knee
			// 	slopeAbove: 0.5, // post-knee
			// 	clampTime: 0.01, // fast attack
			// 	relaxTime: 0.1 // fast release
			// );

			compressed = saturated;

			Out.ar(0, Pan2.ar(compressed, pan * (1 - (pan_lfo_amount * SinOsc.kr(pan_lfo_freq, pan_lfo_phase, 0.5, 0.5)))));
		}).add;

		def.send(server);
		server.sync;

		synth = PolyDef.new(\Quilt, context, 8);

		params = Dictionary.newFrom([
			\freq, 80,
			\freq_sag, 0.1,
			\vel, 0.5,
			\vib_rate, 5,
			\vib_depth, 0.0,
			\raw_osc_cutoff, 10000,
			\phased_cutoff,  10000,
			// offness
			\pitch_offness_max, 0.0,
			\pitch_offness_pct, 0.0,
			\cutoff_offness_max, 0.0,
			\cutoff_offness_pct, 0.0,
			// segmented oscilators
			\index1, 0.0,
			\index2, 0.0,
			\index3, 0.0,
			\index4, 0.0,
			\amp1, 0.5,
			\amp2, 0.5,
			\amp3, 0.5,
			\amp4, 0.5,
			// npolar projection
			\mod, 3,
			\syncRatio, 1,
			\syncPhase, 0.0,
			\npolarProj, 1.0,
			\npolarRotFreq, 10,
			\npolarRotFreq_sag, 0.1,
			\npolarProjSliced, 1.0,
			\npolarRotFreqSliced, 10,
			\npolarRotFreqSliced_sag, 0.1,
			// phase mod
			\pmFreq, 0.5,
			\pmAmt, 0,
			// amp env
			\amp_offset, 0.0,
			\attack, 0.1,
			\decay, 0.1,
			\sustain, 0.7,
			\release, 0.5,
			// filter env
			\fenv_a, 1.0,
			\fktrack, 0.1,
			\fktrack_neg_offset, 0.0,
			\fattack, 0.1,
			\fdecay, 0.1,
			\fsustain, 0.7,
			\frelease, 0.5,
			// filter
			\cutoff, 1200,
			\cutoff_sag, 0.1,
			\resonance, 0.0,
			// panning
			\pan, 0.0,
			// TODO: it works well but is almost "too much" -> only on last part of travel of binaurality knob
			\pan_lfo_freq, 5,
			\pan_lfo_phase, 0.0,
			\pan_lfo_amount, 0.0,
			// sat/comp
			\sat_threshold, 0.5
		]);

		params.keysDo({ arg key;
			// current voice
			this.addCommand(key ++ "_curr", "f", { arg msg;
				params[key] = msg[1];
				synth.setParamCurrent(key, msg[1]);
			});
			// specific voice
			this.addCommand(key, "if", { arg msg;
				var voiceId = msg[1];
				params[key] = msg[2];
				synth.setParam(voiceId, key, msg[2]);
			});
			// all voices
			this.addCommand(key ++ "_all", "f", { arg msg;
				params[key] = msg[1];
				synth.setParamAll(key, msg[1]);
			});
		});

		this.addCommand("noteOn", "iif", { arg msg;
			var noteId = msg[1] - 1;
			var freq = msg[2];
			var vel = msg[3];
			var voiceID = synth.noteOn(noteId, freq, vel);
		});
		this.addCommand("noteOnPaired", "iif", { arg msg;
			var noteId = msg[1] - 1;
			var freq = msg[2];
			var vel = msg[3];
			var voiceID = synth.noteOnPaired(noteId, freq, vel);
		});
		this.addCommand("noteOff", "i", { arg msg;
			var noteId = msg[1] - 1;
			synth.noteOff(noteId);
		});

		this.addCommand("voice_count", "i", { arg msg;
			var voiceCount = msg[1];
			synth.setPolyphony(voiceCount);
		});
	}

	free {
		synth.free();
		~sawBuffer.free;
		~sawValues.free;
	}
}


// ------------------------------------------------------------------------
// helper class - poly synth

// this class allows turning any mono synthdef into a polyphonic variant w/ note stealing

PolyDef {
	var voices, maxVoices, currVoice;

	*new { |synthName, context, count|
        ^super.new.init(synthName, context, count)
	}

	init { |synthName, context, count|
		voices = Array.fill(count, { Synth.new(synthName, [\out, context.out_b], target: context.xg) });
		maxVoices = voices.size;
		currVoice = voices[0];
	}

	noteOn { |voiceId, freq, vel|
		var voice = voices[voiceId];
		currVoice = voice;
		voice.set(\freq, freq, \vel, vel,
			\gate, 1, \pair_gate_in, 0);
	}

	noteOnPaired { |voiceId, freq, vel|
		var voice = voices[voiceId];
		currVoice = voice;
		voice.set(\freq, freq, \vel, vel,
			\gate, 0, \gate_pair_in, 1);
	}

	noteOff { |voiceId, noteId|
		var voice = voices[voiceId];
		voice.set(\gate, 0, \gate_pair_in, 0, \gate_pair_out, 0);
	}

	setPolyphony { |nbVoices|
		maxVoices = nbVoices;
	}

	setParam { |voiceId, key, value|
		var voice = voices[voiceId];
		voice.set(key, value);
	}
	setParamCurrent { |key, value|
		// if (currVoice.notNil) {
		currVoice.set(key, value);
		// };
	}
	setParamAll { |key, value|
		voices.do { |voice|
			voice.set(key, value);
		};
	}

	free {
		voices.do { |voice|
			voice.set(\gate, 0);
			voice.free;
		};
	}
}