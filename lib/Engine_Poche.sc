// Engine_Poche — the voices of a pocket drum machine, and the strip they go through.
//
// Fourteen synthesised voices (no samples), each played by `hit`:
//
//   1 kick    2 snare   3 clap    4 hat      5 open hat   6 rim     7 tom
//   8 cowbell 9 shaker 10 zap    11 bass    12 lead      13 stab  14 sweep
//
// `a` and `b` are the two knobs. For a drum they are 0..1 (tone, decay);
// for bass, lead and stab `a` is a frequency in Hz and `b` is 0..1.
//
// Every voice goes to a stereo mix bus and, by `send`, to an echo bus. The
// master synth reads both: echo (ping-pong), a DJ filter, a crusher, a little
// room, a drive and a limiter.

Engine_Poche : CroneEngine {
	var voices, mixBus, sendBus, chokeBus, chokeCount = 0, master;
	var defs;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;

		// Shared by every voice: pan, level, and the echo send.
		var emit = { arg sig;
			var st = Pan2.ar(sig * \amp.kr(0.8), \pan.kr(0));
			Out.ar(\out.kr(0), st);
			Out.ar(\sendOut.kr(0), st * \send.kr(0));
		};

		SynthDef(\poche_kick, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var base = a.linexp(0, 1, 38, 82);
			var dec = b.linexp(0, 1, 0.12, 1.1);
			var penv = EnvGen.ar(Env([5, 1.6, 1], [0.012, 0.09], [-4, -4]));
			var env = EnvGen.ar(Env.perc(0.001, dec, 1, -6), doneAction: 2);
			var body = SinOsc.ar(base * penv, 0.5pi);
			var click = HPF.ar(WhiteNoise.ar, 2500) * EnvGen.ar(Env.perc(0.0005, 0.006)) * 0.5;
			emit.(((body * env * 1.3) + click).tanh);
		}).add;

		SynthDef(\poche_snare, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var tone = a.linexp(0, 1, 150, 260);
			var dec = b.linexp(0, 1, 0.08, 0.45);
			var body = (SinOsc.ar(tone * EnvGen.ar(Env([1.6, 1], [0.03]))) * 0.6)
				+ (SinOsc.ar(tone * 1.85) * 0.3);
			var noise = BPF.ar(WhiteNoise.ar, 4500, 1.2) * 1.6;
			body = body * EnvGen.ar(Env.perc(0.001, dec * 0.6));
			noise = noise * EnvGen.ar(Env.perc(0.001, dec, 1, -5), doneAction: 2);
			emit.((body + noise).tanh * 0.9);
		}).add;

		SynthDef(\poche_clap, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var dec = b.linexp(0, 1, 0.12, 0.6);
			var freq = a.linexp(0, 1, 800, 1800);
			var bursts = EnvGen.ar(Env(
				[0, 1, 0.25, 1, 0.25, 1, 0.25, 1, 0],
				[0.0005, 0.009, 0.0005, 0.009, 0.0005, 0.009, 0.0005, dec],
				[0, -3, 0, -3, 0, -3, 0, -5]), doneAction: 2);
			emit.(BPF.ar(WhiteNoise.ar, freq, 0.6) * bursts * 2.2);
		}).add;

		// The metallic six of a classic analogue hat: square waves at odd ratios.
		SynthDef(\poche_hat, {
			var a = \a.kr(0.5), b = \b.kr(0.3);
			var tone = a.linexp(0, 1, 0.8, 1.3);
			var dec = b.linexp(0, 1, 0.025, 0.14);
			var metal = Mix(Pulse.ar([205.3, 304.4, 369.6, 522.7, 540, 800] * tone, 0.5));
			var sig = HPF.ar(BPF.ar(metal, 10000, 0.6), 7000);
			var env = EnvGen.ar(Env.perc(0.0008, dec, 1, -6), doneAction: 2);
			emit.(sig * env * 0.55);
		}).add;

		// Chokeable: a closed hat raises `choke` above the `gen` this one was born with.
		SynthDef(\poche_ohat, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var tone = a.linexp(0, 1, 0.8, 1.3);
			var dec = b.linexp(0, 1, 0.15, 0.9);
			var cut = In.kr(\choke.kr(0)) > \gen.kr(0);
			var metal = Mix(Pulse.ar([205.3, 304.4, 369.6, 522.7, 540, 800] * tone, 0.5));
			var sig = HPF.ar(BPF.ar(metal, 9000, 0.7), 6000);
			var env = EnvGen.ar(Env.perc(0.002, dec, 1, -4), doneAction: 2) * Lag.kr(1 - cut, 0.006);
			FreeSelf.kr(DelayN.kr(cut, 0.05, 0.05));
			emit.(sig * env * 0.5);
		}).add;

		SynthDef(\poche_rim, {
			var a = \a.kr(0.5), b = \b.kr(0.3);
			var f = a.linexp(0, 1, 1200, 2600);
			var env = EnvGen.ar(Env.perc(0.0005, b.linexp(0, 1, 0.015, 0.08)), doneAction: 2);
			emit.(((SinOsc.ar(f) * 0.6) + (BPF.ar(WhiteNoise.ar, f * 1.6, 0.3) * 1.5)) * env);
		}).add;

		SynthDef(\poche_tom, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var f = a.linexp(0, 1, 65, 260);
			var penv = EnvGen.ar(Env([1.5, 1], [0.08], -4));
			var env = EnvGen.ar(Env.perc(0.002, b.linexp(0, 1, 0.15, 0.8)), doneAction: 2);
			var skin = BPF.ar(WhiteNoise.ar, f * 4, 0.5) * EnvGen.ar(Env.perc(0.001, 0.02)) * 0.4;
			emit.(((SinOsc.ar(f * penv) + skin) * env).tanh);
		}).add;

		SynthDef(\poche_cowbell, {
			var a = \a.kr(0.5), b = \b.kr(0.4);
			var f = a.linexp(0, 1, 0.8, 1.25);
			var osc = Mix(Pulse.ar([540, 800] * f, 0.5)) * 0.4;
			var sig = (BPF.ar(osc, 2640 * f, 1.0) * 2) + BPF.ar(osc, 800 * f, 0.8);
			var env = EnvGen.ar(Env([0, 1, 0.35, 0], [0.001, 0.02, b.linexp(0, 1, 0.1, 0.6)], [0, -4, -4]), doneAction: 2);
			emit.(sig * env * 0.8);
		}).add;

		SynthDef(\poche_shaker, {
			var a = \a.kr(0.3), b = \b.kr(0.3);
			var env = EnvGen.ar(Env([0, 1, 0], [a.linexp(0, 1, 0.004, 0.05), b.linexp(0, 1, 0.03, 0.25)], [2, -6]), doneAction: 2);
			emit.(HPF.ar(WhiteNoise.ar, 6000) * env * 0.6);
		}).add;

		SynthDef(\poche_zap, {
			var a = \a.kr(0.5), b = \b.kr(0.4);
			var top = a.linexp(0, 1, 1500, 6000);
			var dec = b.linexp(0, 1, 0.05, 0.4);
			var f = EnvGen.ar(Env([top, 60], [dec], -8));
			var env = EnvGen.ar(Env.perc(0.001, dec), doneAction: 2);
			emit.((SinOsc.ar(f) * 2).tanh * env * 0.5);
		}).add;

		SynthDef(\poche_bass, {
			var freq = \a.kr(55), b = \b.kr(0.5);
			var dec = b.linexp(0, 1, 0.12, 1.2);
			var fenv = EnvGen.ar(Env.perc(0.002, dec * 0.7));
			var osc = (Saw.ar(freq * [1, 1.004]).sum * 0.5) + (Pulse.ar(freq / 2, 0.5) * 0.4);
			var cut = (freq * 2) + (fenv * b.linexp(0, 1, 400, 4500));
			var sig = RLPF.ar(osc, cut.clip(30, 18000), 0.35);
			var env = EnvGen.ar(Env.perc(0.004, dec, 1, -4), doneAction: 2);
			emit.((sig * env * 1.2).tanh * 0.8);
		}).add;

		SynthDef(\poche_lead, {
			var freq = \a.kr(440), b = \b.kr(0.5);
			var vib = SinOsc.kr(5.5, 0, freq * 0.006) * EnvGen.kr(Env([0, 0, 1], [0.15, 0.2]));
			var osc = Pulse.ar(freq + vib, LFTri.kr(0.4).range(0.25, 0.5));
			var dec = b.linexp(0, 1, 0.08, 0.9);
			var sig = LPF.ar(osc, (freq * 6).clip(200, 16000));
			emit.(sig * EnvGen.ar(Env.perc(0.003, dec, 1, -3), doneAction: 2) * 0.4);
		}).add;

		// Root, fifth, octave and a minor tenth: a stab that sits under anything.
		SynthDef(\poche_stab, {
			var freq = \a.kr(220), b = \b.kr(0.5);
			var notes = freq * [1, 1.4983, 2, 2.3784];
			var osc = Mix(Saw.ar(notes * LFNoise1.kr(3 ! 4).range(0.997, 1.003))) * 0.18;
			var dec = b.linexp(0, 1, 0.1, 1.5);
			var fenv = EnvGen.ar(Env.perc(0.005, dec * 0.5));
			var sig = RLPF.ar(osc, (800 + (fenv * 5000)).clip(100, 16000), 0.5);
			emit.(sig * EnvGen.ar(Env.perc(0.005, dec, 1, -4), doneAction: 2));
		}).add;

		SynthDef(\poche_sweep, {
			var a = \a.kr(0.5), b = \b.kr(0.5);
			var dur = b.linexp(0, 1, 0.1, 1.5);
			var from = a.linexp(0, 1, 300, 3000);
			var f = EnvGen.ar(Env([from, from * 6], [dur], 3));
			var env = EnvGen.ar(Env([0, 1, 0], [dur * 0.8, dur * 0.2], [3, -4]), doneAction: 2);
			emit.(BPF.ar(WhiteNoise.ar, f, 0.4) * env * 1.4);
		}).add;

		SynthDef(\poche_master, {
			var dry = In.ar(\in.kr(0), 2);
			var wet = In.ar(\fxin.kr(0), 2);
			var filt = Lag.kr(\filt.kr(0), 0.05);
			var crush = Lag.kr(\crush.kr(0), 0.05);
			var drive = Lag.kr(\drive.kr(0), 0.05);
			var fb, dl, sig, lp, hp, rate, steps, crushed, room;
			// echo: a ping-pong on the send, darkened a little on every pass
			fb = LocalIn.ar(2);
			dl = DelayC.ar(wet + (fb.reverse * \dfb.kr(0.35)), 2.0, Lag.kr(\dtime.kr(0.3), 0.2));
			LocalOut.ar(LPF.ar(HPF.ar(dl, 150), 5500));
			sig = dry + (dl * \dmix.kr(0.6));
			// the DJ filter: below zero closes a low-pass, above zero opens a high-pass
			lp = filt.clip(-1, 0).linexp(-1, 0, 180, 20000);
			hp = filt.clip(0, 1).linexp(0, 1, 20, 5000);
			sig = RHPF.ar(RLPF.ar(sig, lp, 0.6), hp, 0.6);
			// crush: fewer samples, fewer bits
			rate = crush.linexp(0, 1, 48000, 2200);
			steps = 2 ** crush.linlin(0, 1, 16, 3);
			crushed = (Latch.ar(sig, Impulse.ar(rate)) * steps).round / steps;
			sig = SelectX.ar((crush * 20).clip(0, 1), [sig, crushed]);
			room = FreeVerb2.ar(sig[0], sig[1], 1, 0.7, 0.5);
			sig = sig + (room * \verb.kr(0.12));
			sig = SelectX.ar(drive, [sig, (sig * 4).tanh * 0.6]);
			sig = Limiter.ar(sig * \level.kr(1), 0.95, 0.01);
			Out.ar(\out.kr(0), sig);
		}).add;

		defs = [\poche_kick, \poche_snare, \poche_clap, \poche_hat, \poche_ohat, \poche_rim, \poche_tom,
			\poche_cowbell, \poche_shaker, \poche_zap, \poche_bass, \poche_lead, \poche_stab, \poche_sweep];

		s.sync;

		mixBus = Bus.audio(s, 2);
		sendBus = Bus.audio(s, 2);
		chokeBus = Bus.control(s, 1);
		chokeBus.set(0);
		voices = Group.tail(context.xg);
		s.sync;
		master = Synth.tail(context.xg, \poche_master, [
			\in, mixBus, \fxin, sendBus, \out, context.out_b
		]);

		// hit(voice, amp, a, b, pan, send)
		this.addCommand("hit", "ifffff", { arg msg;
			var id = msg[1].asInteger.clip(1, defs.size) - 1;
			var args = [\out, mixBus, \sendOut, sendBus, \amp, msg[2], \a, msg[3], \b, msg[4],
				\pan, msg[5], \send, msg[6]];
			if (id == 3) {
				chokeCount = chokeCount + 1;
				chokeBus.set(chokeCount);
			};
			if (id == 4) {
				args = args ++ [\choke, chokeBus.index, \gen, chokeCount];
			};
			Synth(defs[id], args, voices);
		});

		[\filt, \crush, \drive, \dtime, \dfb, \dmix, \verb, \level].do({ arg key;
			this.addCommand(key, "f", { arg msg; master.set(key, msg[1]) });
		});
	}

	// Called twice when one script follows another: a clear frees the engine,
	// and loading the next one frees it again before either has finished.
	free {
		if (master.notNil) { master.free; master = nil };
		if (voices.notNil) { voices.free; voices = nil };
		if (mixBus.notNil) { mixBus.free; mixBus = nil };
		if (sendBus.notNil) { sendBus.free; sendBus = nil };
		if (chokeBus.notNil) { chokeBus.free; chokeBus = nil };
	}
}
