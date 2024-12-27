

(
s.waitForBoot {

var win, ly, freqSlider, ampSlider, freqLabel, ampLabel,
  mod1Label, mod1Slider, mod1AmtLabel, mod1AmtSlider, mod1FreqLabel, mod1FreqSlider,
  mod2Label, mod2Slider, mod2AmtLabel, mod2AmtSlider, mod2FreqLabel, mod2FreqSlider;
var lh = 30;
var def;

// ------------------------------------
// helper fns

//~updateScopeRange = { |freq|
//    var period = 1 / freq;
//    ScopeView.scope.range_(0, 2 * period); // NB: we display 2 periods
//};

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

			sin = SinOsc.ar(freq2);
			saw = MoogFF.ar(in: Saw.ar(freq2), freq: 10000);
			triangle = MoogFF.ar(in: LFTri.ar(freq2), freq: 10000);
			square = MoogFF.ar(in: Pulse.ar(freq: freq2, width: 0.5), freq: 10000);

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

			phased =  MoogFF.ar(in: phased, freq: 10000);

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

	[
			phased, mixed,
			crossing, counter/mod,
			crossingSliced, counterSliced/mod,
			signal1, signal2, signal3, signal4
		].scope(name: "QuiltScope", zoom: 2.0);

			Out.ar(0, Pan2.ar(compressed, pan * (1 - (pan_lfo_amount * SinOsc.kr(pan_lfo_freq, pan_lfo_phase, 0.5, 0.5)))));
		}).add;


def.send(s);
s.sync;

	// ------------------------------------

~synth = Synth.new(\Quilt);

win = Window("Synth Controls", Rect(100, 100, 300, 300)).front;

ly = 10;

freqLabel = StaticText(win, Rect(10, ly, 50, 20));
freqLabel.string = "f";
freqSlider = Slider(win, Rect(70, ly, 200, 20));
freqSlider.action = { |slider|
	var freq = slider.value.linexp(0, 1, 20, 2000);
	~synth.set(\freq, freq);
	//~updateScopeRange.value(freq);
};
ly = ly + lh;

ampLabel = StaticText(win, Rect(10, ly, 50, 20));
ampLabel.string = "a";
ampSlider = Slider(win, Rect(70, ly, 200, 20));
ampSlider.action = { |slider|
    ~synth.set(\amp_offset, slider.value);
};
ly = ly + lh;

mod1Label = StaticText(win, Rect(10, ly, 50, 20));
mod1Label.string = "m1";
mod1Slider = Slider(win, Rect(70, ly, 200, 20));
mod1Slider.action = { |slider|
    ~synth.set(\mod, slider.value.linexp(0, 1, 2, 15));
};
ly = ly + lh;

mod1AmtLabel = StaticText(win, Rect(10, ly, 50, 20));
mod1AmtLabel.string = "m1 a";
mod1AmtSlider = Slider(win, Rect(70, ly, 200, 20));
mod1AmtSlider.action = { |slider|
    ~synth.set(\npolarProj, slider.value);
};
ly = ly + lh;

mod1FreqLabel = StaticText(win, Rect(10, ly, 50, 20));
mod1FreqLabel.string = "m1 f";
mod1FreqSlider = Slider(win, Rect(70, ly, 200, 20));
mod1FreqSlider.action = { |slider|
    ~synth.set(\npolarRotFreq, slider.value.linexp(0, 1, 20, 2000));
};
ly = ly + lh;

mod2Label = StaticText(win, Rect(10, ly, 50, 20));
mod2Label.string = "m2";
mod2Slider = Slider(win, Rect(70, ly, 200, 20));
mod2Slider.action = { |slider|
    ~synth.set(\syncRatio, slider.value.linexp(0, 1, 1, 8));
};
ly = ly + lh;

mod2AmtLabel = StaticText(win, Rect(10, ly, 50, 20));
mod2AmtLabel.string = "m2 a";
mod2AmtSlider = Slider(win, Rect(70, ly, 200, 20));
mod2AmtSlider.action = { |slider|
    ~synth.set(\npolarProjSliced, slider.value);
};
ly = ly + lh;

mod2FreqLabel = StaticText(win, Rect(10, ly, 50, 20));
mod2FreqLabel.string = "m2 f";
mod2FreqSlider = Slider(win, Rect(70, ly, 200, 20));
mod2FreqSlider.action = { |slider|
    ~synth.set(\npolarRotFreqSliced, slider.value.linexp(0, 1, 20, 2000));
};
ly = ly + lh;

win.onClose = {
    ~synth.free;
};

};
)
