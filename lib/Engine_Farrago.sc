PolyDef {
	var voices, maxVoices, nextVoiceId, currVoice, noteIdMap;

	*new { |context|
        ^super.new.init(context)
	}

	init { | context |
		// voices = Array.fill(8, { Synth(\Farrago) });
		voices = Array.fill(8, { Synth.new(\Farrago, [\out, context.out_b], target: context.xg) });
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

	setParam { |key, value|
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
			freq = 80,
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
			npolarProjSliced = 1.0,
			npolarRotFreqSliced = 10,
			// amp env
			amp_offset = 0.0,
			attack = 0.1, decay = 0.1, sustain = 0.7, release = 0.5,
			// filter
			cutoff = 1200,
			resonance = 0.0;

			// basic waveforms
			var sin, saw, triangle, square;
			// looked-up waveforms (by index)
			var signal1, signal2, signal3, signal4;
			// enveloppes
			var env, scaledEnv;
			// composite waveform
			var mixed, phased, filtered;

			// CMOS-derived waveforms
			var crossing, counter, crossingSliced, counterSliced;
			// computed modulation index, associated phaser signals
			var modphase, phase, phase2, phaseSliced, phaseSliced2;

			sin = SinOsc.ar(freq);
			saw = Saw.ar(freq);
			triangle = LFTri.ar(freq);
			square = Pulse.ar(freq: freq, width: 0.5);

			crossing = LFSaw.ar(freq * 2, iphase: syncPhase, mul: 0.5);
			counter = PulseCount.ar(crossing) % mod;

			crossingSliced = LFSaw.ar(freq * syncRatio * 2, iphase: syncPhase, mul: 0.5);
			counterSliced = PulseCount.ar(crossingSliced) % mod;

			modphase = if(mod % 2 == 0, { mod - 1 }, { mod });

			// REVIEW: use wavetable instead?
			signal1 = Select.ar(index1, [sin, triangle, saw, square]);// * amp1 * SinOsc.kr(npolarRotFreq, 0.0);
			signal2 = Select.ar(index2, [sin, triangle, saw, square]);// * amp2 * SinOsc.kr(npolarRotFreq, 2pi / mod);
			signal3 = Select.ar(index3, [sin, triangle, saw, square]);// * amp3 * SinOsc.kr(npolarRotFreq, 2 * 2pi / mod);
			signal4 = Select.ar(index4, [sin, triangle, saw, square]);// * amp4 * SinOsc.kr(npolarRotFreq, 3 * 2pi / mod);

			mixed = Select.ar(counterSliced, [signal1, signal2, signal3, signal4]);

			phase = SinOsc.ar(npolarRotFreq, counter * 2pi/modphase, npolarProj);
			phase2 = if(mod % 2 == 0, { phase }, { (1.0 - phase) });

			phaseSliced = SinOsc.ar(npolarRotFreqSliced, counterSliced * 2pi/modphase, npolarProjSliced);
			phaseSliced2 = if(mod % 2 == 0, { phaseSliced }, { (1.0 - phaseSliced) });

			phased = mixed * phase2 * phaseSliced2;

			env = EnvGen.kr(Env.adsr(attack, decay, sustain, release), gate, doneAction: 0);
			scaledEnv = (1 - amp_offset) * env + amp_offset;

			filtered = MoogFF.ar(in: phased, freq: cutoff, gain: resonance) * 0.5 * vel * scaledEnv;

			Out.ar(0, filtered ! 2);
		}).add;

		def.send(server);
		server.sync;

		def.send(server);
		server.sync;

		// synth = Synth.new(\Farrago, [\out, context.out_b], target: context.xg);
		synth = PolyDef.new(context);

		params = Dictionary.newFrom([
			\freq, 80,
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
			\npolarProjSliced, 1.0,
			\npolarRotFreqSliced, 10,
			// amp env
			\amp_offset, 0.0,
			\attack, 0.1,
			\decay, 0.1,
			\sustain, 0.7,
			\release, 0.5,
			// filter
			\cutoff, 1200,
			\resonance, 0.0,
		]);

		params.keysDo({ arg key;
			this.addCommand(key, "f", { arg msg;
				params[key] = msg[1];
				synth.setParam(key, msg[1]);
			});
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
	}

	free {
		synth.free();
	}
}
