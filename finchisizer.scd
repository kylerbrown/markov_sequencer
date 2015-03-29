/* Finchesizer

To use:
- Boot up the server.
- Change adrs_touchOSC to the IP address of the tablet.
("Local IP address" on TouchOSC)
- Then execute the main block of code.

In TouchOSC (on the tablet), fix these settings:
Host: the IP address of the computer running SuperCollider.
- On a Mac, you can get that with "ifconfig en1" in Terminal,
and taking the "inet" IP address, not "broadcast".
Port (outgoing): 57120 (default for supercollider)
Port (incoming): 58100

Presets are loaded into the bank of presets in RAM.
This is an array of arrays of dicts.
Biggest array holds the presets available in RAM.
Subarrays hold a group of synths.
Each dict holds the settins for a single synth.

Pressing 'save' on the *Host computer* GUI brings up a dialog box
to save the current group to a YAML file.
Load presets by specifying adding the filename to the "presets" array.

*/

// Figure out good ranges/scales for the control parameters.
// Instead of changing the parameters from [0,1] to a useful range in the
//    SynthDef, create a function to change those values. That way, we
//    can save the meaningful values, instead of the TouchOSC parameters.
// Call this function when going from TouchOSC to the parameter dictionaries,
// which then get set into the synth. To go from preset dictionary values back
// to [0,1] for TouchOSC, call `descale' on the control value.



// Values sent back to TouchOSC need to be in the interval [0,1].


// Add pan?
// Also multiple ipads at once
// Preprogrammed syllables - gestures
//  -- Do this with separate SynthDefs
// Buttons that send to preset combinations of parameters
// Shift up bifurcation line

(
var adrs_touchOSC;
var active_synth, active_group, finch_defaults, n_synths, nPresets;
var switch_synth_control, switch_group_control;
var update_touchosc_disp, update_synth_param, update_synths_in_group;
var saveYAMLDict, saveYAML, loadYAML;
var load_preset_file, load_presets_dialog, save_presets_dialog, activate_preset_group;
var finch_param_arr; // Array of dicts -- a group of synths
var preset_arr; // Array of Arrays of Dicts - for holding preset synth groups in RAM
var save_synth_settings, load_synth_settings;
var save_all_settings, load_group_settings;
var win, btns;
var presets, preset_dir;
var rescale, descale;

// Which presets to load on starting up the script
preset_dir = "/Users/gbrookshire/Documents/projects/music/sc/markov_sequencer/presets/";
presets = ["blank.yaml", "1.yaml", "2.yaml", "3.yaml", "low.yaml"];

n_synths = 4;
nPresets = 6;
active_synth = 0; // Which finch is being controlled by TouchOSC
active_group = 0; // Which preset group is active now
adrs_touchOSC = NetAddr("192.168.1.139", 58100);

finch_defaults = Dictionary[
	\pressure -> 0,
	\tension -> 0,
	\time_const -> 0,
	\volume -> 0,
	\pdepth -> 0,
	\prate -> 0,
	\tdepth -> 0,
	\trate -> 0
];
finch_param_arr = Array.fill(n_synths, {finch_defaults.copy});
preset_arr = Array.fill(nPresets, {finch_param_arr.copy});


///// Useful functions

// Rescale parameters from [0,1] to a scale meaningful for the synth.
rescale = {arg pname, val;
	var scaling_funs;
	scaling_funs = Dictionary[
		\pressure -> {|x| x - 0.2},
		\tension -> {|x| x - 0.2},
		\time_const -> {|x| x.linexp(0, 1, 1000, 48000)},
		\volume -> {|x| x * 6},
		\pdepth -> {|x| x * 0.2},
		\prate -> {|x| x.linexp(0, 1, 0.05, 50)},
		\tdepth -> {|x| x * 0.2},
		\trate -> {|x| x.linexp(0, 1, 0.05, 50)}
	];
	scaling_funs[pname].value(val)
};
// Go from meaningful values to [0,1] for TouchOSC
descale = {arg pname, val;
	var scaling_funs;
	scaling_funs = Dictionary[
		\pressure -> {|x| x + 0.2},
		\tension -> {|x| x + 0.2},
		\time_const -> {|x| x.explin(1000, 48000, 0, 1)},
		\volume -> {|x| x / 6},
		\pdepth -> {|x| x / 0.2},
		\prate -> {|x| x.explin(0.05, 50, 0, 1)},
		\tdepth -> {|x| x / 0.2},
		\trate -> {|x| x.explin(0.05, 50, 0, 1)}
	];
	scaling_funs[pname].value(val)
};


// Update the parameter of a synth in the array and in the synth
update_synth_param = {arg pname, pval;
	// Update the array of parameters
	finch_param_arr[active_synth].put(pname, pval);
	// Update the synth
	x[active_synth].set(pname.asSymbol, pval);
};
update_synths_in_group = {
	var prev_active = active_synth;
	(0..3).do({arg n_synth; // Loop through synths in the group
		active_synth = n_synth;
		finch_param_arr[active_synth].keys.do({arg pname;
			update_synth_param.value(pname, finch_param_arr[n_synth][pname]);
		})
	});
	active_synth = prev_active;
};

// Change TouchOSC control to a new synth
switch_synth_control = {arg new_synth;
	var old_synth, active_params;
	old_synth = active_synth;
	// Update active_synth
	active_synth = new_synth;
	// Update TouchOSC display to reflect new active synth
	active_params = finch_param_arr.at(new_synth);
	update_touchosc_disp.value(active_params);
};

// Change to a different preset group
switch_group_control = {arg new_group;
	("Activating synth group" + new_group.asString).postln;
	finch_param_arr = preset_arr[new_group];
	active_group = new_group;
	update_synths_in_group.value;
	// Activate LED to show which preset is being used.
	// Turn off other LEDs.
	// address: /2/led1 through /2/led6
	(1..6).do({|i|
		adrs_touchOSC.sendMsg('/2/led' ++ i.asSymbol, 0);
	});
	adrs_touchOSC.sendMsg('/2/led' ++ (new_group + 1).asSymbol, 1);

};

// Update display on TouchOSC to show params of active synth
update_touchosc_disp = {arg param_dict;
	param_dict.keys.do({arg pname;
		var msg, val;
		case
		{pname == \volume} {msg = '/1/volume'}
		{pname == \time_const} {msg = '/1/time_const'}
		{or(pname == \pressure, pname == \tension)} {
			msg = '/1/xy';
			val = [param_dict[\pressure], param_dict[\pressure]];
		}
		{or(pname == \prate, pname == \pdepth)} {
			msg = '/1/pressure_mod';
			val = [param_dict[\prate], param_dict[\pdepth]];
		}
		{or(pname == \trate, pname == \tdepth)} {
			msg = '/1/tension_mod';
			val = [param_dict[\trate], param_dict[\tdepth]];
		}
		{pname == \time_smooth} {}
		{true} {("Param " + pname + " not known.").postln;};
		if(val.isNil, {val = param_dict[pname]}, {});
		adrs_touchOSC.sendMsg(msg, *val);
	});
};

// Read and write as YAML files.
saveYAMLDict = {arg file_pointer, dict;
	dict.keys.do({arg param;
		var line;
		line = "  " ++ param ++ ": " ++ dict[param].asString ++ "\n";
		file_pointer.write(line);
	});
};
saveYAML = {arg fname;
	var file_pointer;
	file_pointer = File(fname, "w");
	finch_param_arr.do({arg param_dict, i;
		file_pointer.write("- \n");
		saveYAMLDict.value(file_pointer, param_dict);
	});
	file_pointer.close();
};
loadYAML = {arg fname;
	var raw, cooked;
	if (not(fname.endsWith(".yaml")),
		{"Chosen file is not a .yaml file.".warn},
		{}
	);
	raw = fname.parseYAMLFile;
	("Loading" + raw.size.asString + "presets...").postln;
	cooked = Array.fill(raw.size, {|i|
		var cooked_dict, raw_dict;
		raw_dict = raw[i];
		cooked_dict = Dictionary[];
		raw_dict.keys.do({arg param_name;
			cooked_dict[param_name.asSymbol] = raw_dict[param_name].asFloat;
		});
		cooked_dict
	});
};

load_preset_file = {arg fn;
	var file_cont, msg;
	// Function that does something to a filename string.
	fn.postln;
	file_cont = loadYAML.(fn);
	preset_arr[active_group] = file_cont;
	finch_param_arr = file_cont;
	// Set label to show filename
	// address: /2/label1 through /2/label6
	msg = '/2/label' ++ (active_group+1).asSymbol;
	adrs_touchOSC.sendMsg(msg, fn.asString.split($/).last);
	// Update all the synths in the group
	update_synths_in_group.value;
};

load_presets_dialog = {
	File.openDialog(
		"Load settings",
		{|fn| load_preset_file.value(fn)},
		{}
	);
};

save_presets_dialog = {
	File.saveDialog(
		"Save settings as preset",
		"X.yaml",
		{|fn| saveYAML.value(fn)},
		{}
	);
};

// activate_preset_group = {arg n_group;
// 	("Activate preset" + n_group.asString).postln;
// 	load_group_settings.value(n_group);
// 	// Activate LED to show which preset is being used.
// 	// Turn off other LEDs.
// 	// address: /2/led1 through /2/led6
// 	(1..6).do({|i|
// 		adrs_touchOSC.sendMsg('/2/led' ++ i.asSymbol, 0);
// 	});
// 	adrs_touchOSC.sendMsg('/2/led' ++ n_group.asSymbol, 1);
// };

// // Save to RAM
// save_synth_settings = {arg voice, preset_loc;
// 	preset_arr[preset_loc][voice] = finch_param_arr[voice];
// };
// Load from RAM
load_synth_settings = {arg voice, preset_loc;
	finch_param_arr[voice] = preset_arr[preset_loc, voice];
};
// // Save all current to RAM
// save_all_settings = {arg preset_loc;
// 	finch_param_arr.do({arg param_dict, i;
// 		save_synth_settings.value(i, preset_loc);
// 	});
// };
// // Load all current to RAM
// load_group_settings = {arg preset_loc;
// 	active_group = preset_loc;
// 	update_synths_in_group.value;
// 	// finch_param_arr.do({arg param_dict, i;
// 	// 	load_synth_settings.value(i, preset_loc);
// 	// });
// };


///// Finchesizer

SynthDef(\finch, {arg pressure=0, tension=0, time_const=0, volume=0,
	pdepth=0, prate=0, tdepth=0, trate=0, time_smooth=0;
	var sig;

	// All control values from TouchOSC vary between 0 and 1.
	// Adjust to meaningful values here.
	pressure = pressure - 0.02;
	tension = tension - 0.02;
	time_const = time_const.linexp(0, 1, 1000, 48000);
	volume = volume * 6;
	pdepth = pdepth * 0.2;
	prate = prate.linexp(0, 1, 0.05, 50);
	tdepth = tdepth * 0.2;
	trate = trate.linexp(0, 1, 0.05, 50);

	time_smooth = time_smooth.linexp(0, 1, 0.05, 20); // smooth changes in control vals

	sig = SyrinxL.ar(
		freq:22050,
		a: pressure.lag(time_smooth) + SinOsc.kr(prate, mul:pdepth),
		b: tension.lag(time_smooth) + SinOsc.kr(trate, mul:tdepth),
		g: time_const.lag(time_smooth),
		h: 0.00001,
		mul: volume.lag(time_smooth));
	Out.ar(0, sig);
}).add;


///// Effects

SynthDef(\bitcrusher, {arg bit_depth=10, bit_rate=10000;
	var sig;
	sig = In.ar(0);
	// Reduce the sampling rate
	sig = Latch.ar(sig, SinOsc.ar(bit_rate));
	// Reduce the bit depth
	sig = ((sig * (2 ** bit_depth)).round) / (2 ** bit_depth);
	ReplaceOut.ar(0, sig);
}).add;

SynthDef(\verb, {arg mix=0.33, room=0.5, damp=0.5;
	var sig;
	sig = In.ar(0);
	sig = FreeVerb.ar(sig, mix:mix, room:room, damp:damp);
	ReplaceOut.ar(0, sig);
}).add;

///// OSC responders

OSCdef.new(
	\volume_resp,
	{|msg, time, addr, port|
		update_synth_param.(\volume, msg[1]);
	},
	'/1/volume'
);
OSCdef.new(
	\finch_resp,
	{|msg, time, addr, port|
		update_synth_param.(\tension, msg[1]);
		update_synth_param.(\pressure, msg[2]);
	},
	'/1/xy'
);
OSCdef.new(
	\timeconst_resp,
	{|msg, time, addr, port|
		update_synth_param.(\time_const, msg[1]);
	},
	'/1/time_const'
);
OSCdef.new(
	\pressure_mod_resp,
	{|msg, time, addr, port|
		update_synth_param.(\prate, msg[1]);
		update_synth_param.(\pdepth, msg[2]);
	},
	'/1/pressure_mod'
);
OSCdef.new(
	\tension_mod_resp,
	{|msg, time, addr, port|
		update_synth_param.(\trate, msg[1]);
		update_synth_param.(\tdepth, msg[2]);
	},
	'/1/tension_mod'
);
OSCdef.new(
	\time_smooth_resp,
	{|msg, time, addr, port|
		var old_synth = active_synth;
		(0..3).do({arg new_synth;
			switch_synth_control.value(new_synth);
			update_synth_param.(\time_smooth, msg[1]);
		});
		switch_synth_control.value(old_synth);
	},
	'/2/time_smooth'
);


// Responders for selecting which finchesizer to control
(1..n_synths).do({arg n_finch;
	OSCdef.new(
		'finch_select' ++ n_finch.asString ++ '_resp',
		{|msg, time, addr, port|
			if (
				msg[1] == 1,
				{
					var new_synth;
					// Sorry...
					new_synth = msg[0].asString.at(18).asInt - 49;
					switch_synth_control.(new_synth);
				},
				{}
			);
		},
		'/1/finch_select/1/' ++ n_finch.asString;
	);
});

OSCdef.new(
	\dump_resp,
	{|msg, time, addr, port|
		finch_param_arr[active_synth].postln
	},
	'/1/dump'
);

// Presets
(1..nPresets).do({arg nPreset; // Switch to a new preset.
	OSCdef.new(
		'pm_select_' ++ nPreset.asString,
		{|msg, time, addr, port|
			switch_group_control.value(nPreset - 1);
		},
		'/2/preset_mult_bank/' ++ nPreset.asString ++ '/1';
	);
});


// Effects
OSCdef.new(
	\bc_on_resp,
	{|msg, time, addr, port|
		if (msg[1] == 1,
			{y = Synth.tail(s, \bitcrusher);},
			{y.free;});
	},
	'/1/bc_on'
);
OSCdef.new(
	\bc_depth_resp,
	{|msg, time, addr, port|
		var bd;
		bd = (msg[1] * 12).round + 3;
		y.set(\bit_depth, bd);
	},
	'/1/bc_depth'
);
OSCdef.new(
	\bc_rate_resp,
	{|msg, time, addr, port|
		y.set(\bit_rate, msg[1] * 20000);
	},
	'/1/bc_rate'
);

OSCdef.new(
	\verb_on_resp,
	{|msg, time, addr, port|
		if (msg[1] == 1,
			{z = Synth.tail(s, \verb);},
			{z.free;});
	},
	'/1/verb_on'
);
OSCdef.new(
	\verb_mix_resp,
	{|msg, time, addr, port|
		z.set(\mix, msg[1]);
	},
	'/1/verb_mix'
);
OSCdef.new(
	\verb_room_resp,
	{|msg, time, addr, port|
		z.set(\room, msg[1]);
	},
	'/1/verb_room'
);
OSCdef.new(
	\verb_damp_resp,
	{|msg, time, addr, port|
		z.set(\damp, msg[1]);
	},
	'/1/verb_room'
);


// Set up the GUI for saving and loading
h = 50;
win = GUI.window.new("finchesizer",
	Rect(100, 100, (h + 7) * 2, h + 10));
win.view.decorator = FlowLayout(win.view.bounds);
win.view.background = Color(0,0,0);
win.front;
btns = Array.newClear(2);
b = Button(win, Rect(25, 25, 2*h, h));
b.states = [["save as preset"]];
b.action = {|val| save_presets_dialog.value};
btns.put(1, b);



///// Rev up the finchesizers
Task({
	s.sync; // wait for the server
	// x = Synth.tail(s, \finch);

	// Eliminating the group like this makes it harder to apply bitcrushing
	x = Array.fill(n_synths, {Synth.new(\finch)});

	// Load presets
	presets.do({arg fname, i;
		switch_group_control.value(i);
		load_preset_file.value(preset_dir ++ fname);
	});
	switch_group_control.value(0);

}).play;

)

/*
// Test out the finchesizer
x = Synth.tail(s, \finch);
x[0].set(\pressure, 0.5);
x[0].set(\tension, 0.1);
x[0].set(\volume, 0.6);
x[0].free;

// Set up effects in a chain like this.
y = Synth.tail(s, \bitcrusher, [\bit_depth, 1, \bit_rate, 100]);
y.free;

z = Synth.tail(s, \verb);
z.set(\mix, 0.8);
z.set(\room, 0.1);
z.set(\damp, 0.6);
z.free;
*/

(
)