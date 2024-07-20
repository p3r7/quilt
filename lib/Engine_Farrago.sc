Engine_Farrago : CroneEngine {
	var <synth;
	var params;

	alloc {
		var server = Crone.server;
		var def;

		def = SynthDef(\Farrago, {
			arg out = 0,
			gate = 0,
			vel = 0.5,
			freq = 200,
			freq_sag = 0.1,
			mod = 3,
			syncRatio = 1,
			syncPhase = 0.0,
			index1 = 0.0,
			index2 = 0.0,
			index3 = 0.0,
			index4 = 0.0,
			amp1 = 0.5,
			amp2 = 0.5,
			amp3 = 0.5,
			amp4 = 0.5,
			// npolar projection
			npolarProj = 1.0,
			npolarRotFreq = 10,
			npolarRotFreq_sag = 0.1,
			npolarProjSliced = 1.0,
			npolarRotFreqSliced = 10,
			npolarRotFreqSliced_sag = 0.1,
			// amp env
			amp_offset = 0.0,
			attack = 0.1, decay = 0.1, sustain = 0.7, release = 0.5,
			// filter env
			fenv_a = 1.0,
			fktrack = 0.1,
			fattack = 0.1, fdecay = 0.1, fsustain = 0.7, frelease = 0.5,
			// filter
			cutoff = 1200,
			cutoff_sag = 0.1,
			resonance = 0.0,
			// saturation/compression
			sat_threshold = 0.5;

			// frequencies
			var semitoneDiff, hzTrack;
			var freqSagLfo, freq2;
			var cutoffSagLfo, cutoff2;
			var npolarRotFreqSagLfo, npolarRotFreq2;
			var npolarRotFreqSlicedSagLfo, npolarRotFreqSliced2;
			// basic waveforms
			var sin, saw, triangle, square;
			// looked-up waveforms (by index)
			var signal1, signal2, signal3, signal4;
			// amp enveloppe
			var env, scaledEnv;
			// filter enveloppe
			var fenv, instantCutoff;
			// processed waveform
			var mixed, phased, filtered, ironed, saturated, compressed;

			// CMOS-derived waveforms
			var crossing, counter, crossingSliced, counterSliced;
			// computed modulation index, associated phaser signals
			var modphase, phase, phase2, phaseSliced, phaseSliced2;

			// NB: this sounds meh and is heavy in processing...
			// TODO: implement standard vibrrato w/ slightly detuned voices

			// semitoneDiff = freq * (2 ** (1/12) - 1);
			// freqSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * freq_sag * semitoneDiff;
			// freq2 = freq + freqSagLfo;

			// cutoffSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * cutoff_sag * semitoneDiff;
			// cutoff2 = cutoff + cutoffSagLfo;

			// npolarRotFreqSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * npolarRotFreq_sag * semitoneDiff;
			// npolarRotFreq2 = npolarRotFreq + npolarRotFreqSagLfo;

			// npolarRotFreqSlicedSagLfo = Lag.kr(LFNoise1.kr(1), 0.1) * npolarRotFreqSliced_sag * semitoneDiff;
			// npolarRotFreqSliced2 = npolarRotFreqSliced + npolarRotFreqSlicedSagLfo;

			freq2 = freq;
			cutoff2 = cutoff;
			npolarRotFreq2 = npolarRotFreq;
			npolarRotFreqSliced2 = npolarRotFreqSliced;

			hzTrack = freq2.cpsmidi / 12;

			sin = SinOsc.ar(freq2);
			saw = Saw.ar(freq2);
			triangle = LFTri.ar(freq2);
			square = Pulse.ar(freq: freq2, width: 0.5);

			crossing = LFSaw.ar(freq2 * 2, iphase: syncPhase, mul: 0.5);
			counter = PulseCount.ar(crossing) % mod;

			crossingSliced = LFSaw.ar(freq2 * syncRatio * 2, iphase: syncPhase, mul: 0.5);
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

			env = EnvGen.kr(Env.adsr(attack, decay, sustain, release), gate, doneAction: 0);
			scaledEnv = (1 - amp_offset) * env + amp_offset;

			fenv = EnvGen.kr(Env.adsr(fattack, fdecay, fsustain, frelease), gate, doneAction: 0) * fenv_a;

			instantCutoff = (cutoff2 * (1 + (fktrack * 2 * hzTrack) + (fenv * 2 * hzTrack))).clip(20, 20000);

			filtered = MoogFF.ar(in: phased,
				freq: instantCutoff,
				gain: resonance) * 0.5 * vel * scaledEnv;

			ironed = BPeakEQ.ar(filtered, 200, rq: 1, db: 6 * (1-sat_threshold));

			saturated = (ironed * (2 - sat_threshold)).tanh;

			compressed = Compander.ar(
				saturated, //
				ironed, // ctr signal -> input, but pre-saturation
				thresh: sat_threshold.clip(0.1, 1),
				slopeBelow: 1,  // 1 means no comp pre-knee
				slopeAbove: 0.5, // post-knee
				clampTime: 0.01, // fast attack
				relaxTime: 0.1 // fast release
			);

			Out.ar(0, compressed ! 2);
		}).add;

		def.send(server);
		server.sync;

		// synth = Synth.new(\Farrago, [\out, context.out_b], target: context.xg);
		synth = PolyDef.new(\Farrago, context, 8);

		params = Dictionary.newFrom([
			\freq, 80,
			\freq_sag, 0.1,
			\vel, 0.5,
			\mod, 3,
			\syncRatio, 1,
			\syncPhase, 0.0,
			\index1, 0.0,
			\index2, 0.0,
			\index3, 0.0,
			\index4, 0.0,
			\amp1, 0.5,
			\amp2, 0.5,
			\amp3, 0.5,
			\amp4, 0.5,
			// npolar projection
			\npolarProj, 1.0,
			\npolarRotFreq, 10,
			\npolarRotFreq_sag, 0.1,
			\npolarProjSliced, 1.0,
			\npolarRotFreqSliced, 10,
			\npolarRotFreqSliced_sag, 0.1,
			// amp env
			\amp_offset, 0.0,
			\attack, 0.1,
			\decay, 0.1,
			\sustain, 0.7,
			\release, 0.5,
			// filter env
			\fenv_a, 1.0,
			\fktrack, 0.1,
			\fattack, 0.1,
			\fdecay, 0.1,
			\fsustain, 0.7,
			\frelease, 0.5,
			// filter
			\cutoff, 1200,
			\cutoff_sag, 0.1,
			\resonance, 0.0,
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
				synth.setParam(voiceId, key, msg[1]);
			});
			// all voices
			this.addCommand(key ++ "_all", "f", { arg msg;
				params[key] = msg[1];
				synth.setParamAll(key, msg[1]);
			});
		});

		this.addCommand("noteOn", "iif", { arg msg;
			var noteId = msg[1];
			var freq = msg[2];
			var vel = msg[3];
			var voiceID = synth.noteOn(noteId, freq, vel);
		});
		this.addCommand("noteOff", "i", { arg msg;
			var noteId = msg[1];
			synth.noteOff(noteId);
		});

		this.addCommand("voice_count", "i", { arg msg;
			var voiceCount = msg[1];
			synth.setPolyphony(voiceCount);
		});
	}

	free {
		synth.free();
	}
}


// ------------------------------------------------------------------------
// helper class - poly synth

// this class allows turning any mono synthdef into a polyphonic variant w/ note stealing

PolyDef {
	var voices, maxVoices, nextVoiceId, currVoice, noteIdMap;

	*new { |synthName, context, count|
        ^super.new.init(synthName, context, count)
	}

	init { |synthName, context, count|
		voices = Array.fill(count, { Synth.new(synthName, [\out, context.out_b], target: context.xg) });
		maxVoices = voices.size;
		nextVoiceId = 0;
		currVoice = voices[0];

		noteIdMap = Dictionary.new;
	}

	noteOn { |noteId, freq, vel|
		var currVoiceId = nextVoiceId;
		var voice = voices[nextVoiceId];
		nextVoiceId = (nextVoiceId + 1) % maxVoices;
		currVoice = voice;

		voice.set(\freq, freq, \vel, vel, \gate, 1);

		noteIdMap[noteId] = currVoiceId;
	}

	noteOff { |noteId|
		var voiceId = noteIdMap[noteId];
		if (voiceId.notNil) {
            var voice = voices[voiceId];
            voice.set(\gate, 0);
            noteIdMap.removeAt(noteId);
		};
		// voices.do { |voice|
		// 	if (voice.get(\freq) == freq) {
		// 		voice.set(\gate, 0);
		// 	}
		// };
	}

	setPolyphony { |nbVoices|
		maxVoices = nbVoices;
		if (nextVoiceId > (nbVoices-1)) {
			nextVoiceId = 0
		}
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