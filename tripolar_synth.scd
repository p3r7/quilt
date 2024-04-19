
(
s.waitForBoot {
	var synth;
    var freq = 220, rate1 = 0.1, rate2 = 0.13, rate3 = 0.4;
	var mod = 3;
	var syncRatio = 4;
	var syncPhase = 0.2;

	var bus = Bus.audio(s, 1);

    synth = {
        var triangle = LFTri.ar(freq);
		var sin = SinOsc.ar(freq);
		var saw = Saw.ar(freq);

		// NB: failed attempts at doing zero crossing detection
		//var previous = Delay1.ar(triangle);
        //var crossing = (triangle * previous <= 0) && (previous != 0);
		//var crossing = (triangle * previous <= 0).asInteger * (previous != 0).asInteger;

		var crossing = LFSaw.ar(freq * syncRatio * 2, iphase: syncPhase, mul: 0.5);

		//var square = LFSaw.ar(freq, mul: 0.5).sign;
		//var crossing = (Delay1.ar(square) == -1) & (square == 1);

		var counter = PulseCount.ar(crossing) % mod;

		//var signal1 = Select.ar((counter == 0).asInteger, [DC.ar(0), triangle]) * SinOsc.kr(rate1).range(0, 1);
		//var signal2 = Select.ar((counter == 1).asInteger, [DC.ar(0), triangle]) * SinOsc.kr(rate2).range(0, 1);
		//var signal3 = Select.ar((counter == 2).asInteger, [DC.ar(0), triangle]) * SinOsc.kr(rate3).range(0, 1);

		var mod1 = (counter <= 0);
		var mod2 = (counter <= 1) - mod1;
		var mod3 = (counter <= 2) - mod2 - mod1;
		var mod4 = (counter <= 3) - mod3 - mod2 - mod1;
		var mod5 = (counter <= 4) - mod4 - mod3 - mod2 - mod1;

		//var signal1 = mod1 * triangle * SinOsc.kr(rate1, 0).range(0, 1);
		//var signal2 = mod2 * sin * SinOsc.kr(rate2, 0.1).range(0, 1);
        //var signal3 = mod3 * saw * SinOsc.kr(rate3, 0.2).range(0, 1);

		var signal1 = triangle * SinOsc.kr(rate1, 0).range(0, 1);
		var signal2 = sin * SinOsc.kr(rate2, 0.1).range(0, 1);
        var signal3 = saw * SinOsc.kr(rate3, 0.2).range(0, 1);

        //var mixed = signal1 + signal2 + signal3;

		//var mixed = Select.ar(counter, [triangle, sin, saw, triangle, sin, saw]);
		var mixed = Select.ar(counter, [signal1, signal2, sin, signal3, signal1, sin, signal3]);

		var filtered = MoogFF.ar(in: mixed, freq: 4000, gain: 0.0);

		//Out.ar(bus, signal1);

        //Out.ar(0, mixed);
		//Out.ar(0, signal1);
		[filtered]
    }.scope;

	//ScopeOut.ar(bus, s.sampleRate);
    //Window.closeAll;
};
)

(
{
    var a;
	//a = SinOsc.ar(90);
	a = LFTri.ar(90, 0, 0.1);
    //a = SinOsc.ar(SinOsc.kr(1, 0, 600,700), 0, 0.1);

    [a, ZeroCrossing.ar(a) * 0.0005]
}.scope;
)


// --------------•
(
{
    var a;
    a = SinOsc.ar(SinOsc.kr(1, 0, 600,700), 0, 0.1);
    //[a, ZeroCrossing.ar(a) * 0.0005]
	ZeroCrossing.ar(a) * 0.0005
}.scope;
)

