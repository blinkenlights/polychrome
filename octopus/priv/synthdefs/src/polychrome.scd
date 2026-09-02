// SynthDefs for the audiovisual pixelfun stack.
//
// Compiled to .scsyndef with `mix sound.synthdefs`, which is the only time
// sclang is needed — at runtime Elixir talks to scsynth directly.
//
// Every synth writes to a single channel (`out`) because one channel is one
// panel, and frees itself when its envelope ends, so no note-off is required.
(
var dir = thisProcess.argv[0];

if(dir.isNil) {
    "usage: sclang polychrome.scd <output-directory>".postln;
    1.exit;
};

dir.mkdir;

// Short bell-ish ping. The workhorse for the ring chase.
SynthDef(\pc_ping, { |out = 0, freq = 440, amp = 0.3, dur = 0.25|
    var env = EnvGen.kr(Env.perc(0.003, dur, amp, -4), doneAction: 2);
    var sig = SinOsc.ar(freq) + (SinOsc.ar(freq * 2.01) * 0.3);
    Out.ar(out, sig * env);
}).writeDefFile(dir);

// Dry filtered noise click. Used by the metronome, and for percussion.
SynthDef(\pc_click, { |out = 0, freq = 2000, amp = 0.3, dur = 0.03|
    var env = EnvGen.kr(Env.perc(0.001, dur, amp, -8), doneAction: 2);
    var sig = BPF.ar(WhiteNoise.ar, freq.clip(80, 12000), 0.4);
    Out.ar(out, sig * env * 3);
}).writeDefFile(dir);

// Plucked string, for melodic material that still reads as percussive.
SynthDef(\pc_pluck, { |out = 0, freq = 220, amp = 0.3, dur = 1.5|
    var env = EnvGen.kr(Env.linen(0.001, dur, 0.05, amp), doneAction: 2);
    var sig = Pluck.ar(WhiteNoise.ar(0.6), 1, 0.2, freq.reciprocal, dur, 0.4);
    Out.ar(out, LPF.ar(sig, 4000) * env);
}).writeDefFile(dir);

// Held tone with a slowly opening filter — the voice for drone scenes.
SynthDef(\pc_drone, { |out = 0, freq = 110, amp = 0.2, dur = 8|
    var env = EnvGen.kr(Env.linen(dur * 0.3, dur * 0.4, dur * 0.3, amp), doneAction: 2);
    var sig = Saw.ar(freq) + Saw.ar(freq * 1.005);
    var cutoff = freq * LFNoise2.kr(0.1).range(3, 9);
    Out.ar(out, RLPF.ar(sig, cutoff.clip(60, 8000), 0.4) * env * 0.5);
}).writeDefFile(dir);

// Sustained voice with a gate: started once, then steered by /n_set and let go
// with gate 0. The amp lag is what makes a picture drive a voice without
// zipper noise — probe values arrive at 30 fps, the ear wants a slope.
SynthDef(\pc_voice, { |out = 0, freq = 220, amp = 0, cutoff = 2000, gate = 1, dur = 0|
    var env = EnvGen.kr(Env.asr(1.5, 1, 2.5), gate, doneAction: 2);
    var sig = Saw.ar(freq) + Saw.ar(freq * 1.004) + SinOsc.ar(freq / 2, 0, 0.4);
    var filtered = RLPF.ar(sig, Lag.kr(cutoff, 0.5).clip(60, 12000), 0.5);
    // A held voice is let go with gate 0. Fired as a one-shot it would never
    // get one and would sing until the next panic, so a positive dur frees the
    // node on its own: the safety net for a sustaining synth used as a note.
    EnvGen.kr(Env.new([1, 1, 0], [dur, 0]), dur > 0, doneAction: 2);
    Out.ar(out, filtered * Lag.kr(amp, 0.25) * env * 0.25);
}).writeDefFile(dir);

("[synthdefs] wrote pc_ping, pc_click, pc_pluck, pc_drone, pc_voice to " ++ dir).postln;
0.exit;
)
