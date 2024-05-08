Engine_Farrago : CroneEngine {
	var <synth;
	var params;

	alloc {
		var server = Crone.server;
		var def;

		def = SynthDef(\Farrago, {
			arg out = 0,
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
			// filter
			cutoff = 1200,
			resonance = 0.0;

			var sin = SinOsc.ar(freq);
			var saw = Saw.ar(freq);
			var triangle = LFTri.ar(freq);
			var square = Pulse.ar(freq: freq, width: 0.5);

			var crossing = LFSaw.ar(freq * syncRatio * 2, iphase: syncPhase, mul: 0.5);
			var counter = PulseCount.ar(crossing) % mod;

			var modphase = if(mod % 2 == 0, { mod - 1 }, { mod });

			// REVIEW: use wavetable instead?
			var signal1 = Select.ar(index1, [sin, triangle, saw, square]);// * amp1 * SinOsc.kr(npolarRotFreq, 0.0);
			var signal2 = Select.ar(index2, [sin, triangle, saw, square]);// * amp2 * SinOsc.kr(npolarRotFreq, 2pi / mod);
			var signal3 = Select.ar(index3, [sin, triangle, saw, square]);// * amp3 * SinOsc.kr(npolarRotFreq, 2 * 2pi / mod);
			var signal4 = Select.ar(index4, [sin, triangle, saw, square]);// * amp4 * SinOsc.kr(npolarRotFreq, 3 * 2pi / mod);

			var mixed = Select.ar(counter, [signal1, signal2, signal3, signal4]);

			var phase = SinOsc.ar(npolarRotFreq, counter * 2pi/modphase, npolarProj);
			var phase2 = if(mod % 2 == 0, { phase }, { (1.0 - phase) });

			var phased = mixed * phase2;

			var filtered = MoogFF.ar(in: phased, freq: cutoff, gain: resonance) * 0.5;

			Out.ar(0, filtered ! 2);
		}).add;

		def.send(server);
		server.sync;

		synth = Synth.new(\Farrago, [\out, context.out_b], target: context.xg);

		params = Dictionary.newFrom([
			\freq, 80,
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
			// filter
			\cutoff, 1200,
			\resonance, 0.0,
		]);

		params.keysDo({ arg key;
			this.addCommand(key, "f", { arg msg;
				params[key] = msg[1];
				synth.set(key, msg[1]);
			});
		});
	}

	free {
		synth.free;
	}
}
