--
--     =========quilt.==========
--     ------------------------
--     ///////\/\\\\\\\
--     >><<<>><<<><><>>><<>>><<
--     \/\/\\/\/\//\/\/
--     ------------------------
-- ▼▼ ==================== @eigen
--
--     ------instructions------
--
-- global:
-- - E1: change page
--
-- main page (1):
-- - b1: binaurality
-- - b2: vintage
-- - b3: cutoff
-- - E2: npolar mod index
-- - b4: npolar mod depth
-- - b5: npolar mod freq
-- - E3: sliced mod index
-- - b6: sliced mod depth
-- - b7: sliced mod freq


-- -------------------------------------------------------------------------
-- deps

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local UI = require "ui"
local EnvGraph = require "envgraph"
local FilterGraph = require "filtergraph"

local bleached = include("lib/bleached")

voiceutils = include("lib/voiceutils")

include("lib/core")
include("lib/consts")

engine.name = "Quilt"


-- -------------------------------------------------------------------------
-- consts

local WAVESHAPES = {"SIN", "SAW", "TRI", "SQR"}

function screen_size()
  if seamstress then
    return screen.get_size()
  elseif norns then
    return 128, 64
  end
end

S_LVL_MOD = 2

CS_MIDLOWFREQ = ControlSpec.new(25, 1000, 'exp', 0, 440, "Hz")

-- FIXME: still baseline volume even when amp sustain is at 0?!
local DEFAULT_A = 0.55
local DEFAULT_D = 0.3
local DEFAULT_S = 0.5
local DEFAULT_R = 1.0
local ENV_ATTACK  = ControlSpec.new(0.002, 2, "lin", 0, DEFAULT_A, "s")
local ENV_DECAY   = ControlSpec.new(0.002, 2, "lin", 0, DEFAULT_D, "s")
local ENV_SUSTAIN = ControlSpec.new(0,     1, "lin", 0, DEFAULT_S, "")
local ENV_RELEASE = ControlSpec.new(0.002, 4, "lin", 0, DEFAULT_R, "s")
local ENVGRAPH_T_MAX = 0.3


-- -------------------------------------------------------------------------
-- state

screen_dirty = true

BASE_FREQ = 110/2
FREQ = BASE_FREQ
effective_period = 2
effective_freq = FREQ

PITCH_COMPENSATION_MOD = true
-- PITCH_COMPENSATION_MOD = false
-- PITCH_COMPENSATION_SYNC = true
PITCH_COMPENSATION_SYNC = false

rot_angle = 0
rot_angle_sliced = 0

has_bleached = false


-- -------------------------------------------------------------------------
-- state - voices

-- NB: we use midi note id as to track active voices
-- we use prepend it w/ a prefix to allow more than one voice to play the same note

voices = {}
paired_voices = {} -- NB: voices get paired as we augment "binaurality"
note_id_voice_map = {}

STATE = {
  last_played_voice = nil,

  voices = voices,
  curr_voice_id = 1,
  next_voice_id = 1,
  note_id_voice_map = note_id_voice_map,
  nb_meta_voices = NB_VOICES,
  nb_dual_meta_voices = 0,
}

for i=1,NB_VOICES do
  voices[i] = {
    active = false,
    hz = 20,
    vel = 0,
    rot_angle = 0,
    pan = 0,
    is_leader = false,
    paired_leader = nil,
    paired_follower = nil,

    -- enveloppes
    note_just_on      = false,
    t_since_note_on   = 0,
    note_just_off     = false,
    t_since_note_off  = 0,

    aenv = 0,
    aenv_offset = 0,
    fenv = 0,
    fenv_offset = 0,
  }
end


-- -------------------------------------------------------------------------
-- ui - pages

local page_list = {'main', 'amp', 'filter', 'rot_mod', 'rot_mod_sliced'}
local pages = UI.Pages.new(1, #page_list)

local env_graph
local fenv_graph
local f_graph


-- -------------------------------------------------------------------------
-- freq / period calculation

function find_effective_period(poles)
  local n = #poles

  for period = 1, math.floor(n/2) do
    local is_periodic = true
    for i = 1, period do
      for j = i + period, n, period do
        if poles[i] ~= poles[j] then
          is_periodic = false
          break
        end
      end
      if not is_periodic then
        break
      end
    end
    if is_periodic then
      return period
    end
  end
  return n
end


function recompute_effective_freq(freq, mod)
  if freq == nil then
    freq = params:get("freq")
  end
  if mod == nil then
    mod = params:get("mod")
  end

  local poles = {}
  local sign = 1
  local rev = (mod % 2 == 0) and 1 or -1
  for i=1,mod do
    local wi = math.floor(mod1(i, #WAVESHAPES))
    local pole = params:get("index"..wi)
    poles[i] = sign * pole
    poles[mod+i] = rev * sign * pole
    sign = -sign
  end

  -- tab.print(poles)

  effective_period = find_effective_period(poles)
  if effective_period > mod then
    effective_period = effective_period / 4.3
  end
  -- print("effective_period="..effective_period)

  effective_freq = freq * 2 / effective_period
end


-- -------------------------------------------------------------------------
-- controllers

local function bleached_cc_main(row, pot, v, precision)
  if row == 1 and pot == 1 then
    -- params:set("freq", util.linexp(0, precision, CS_MIDLOWFREQ.minval, CS_MIDLOWFREQ.maxval, v))

    -- binaural knob
    v = util.linlin(0, precision, 0, 1, v)
    -- NB: issue w/ bleached that doesn't go up to the full range
    if v > 0.99 then
      v = 1
    end
    params:set("binaurality", v)

  elseif row == 1 and pot == 2 then
    -- vintage kob
    -- params:set("freq_sag", util.linlin(0, precision, 0, 1, v))
    -- params:set("cutoff_sag", util.linlin(0, precision, 0, 1, v))

    params:set("pitch_offness", util.linlin(0, precision, 0, 1, v))
    -- params:set("pitch_offness", util.linexp(0, precision, 0+1, 1+1, v) - 1)
    -- params:set("cutoff_offness", util.linlin(0, precision, 0, 1, v))
    params:set("sat_threshold", util.linlin(0, precision, 1, 0.1, v))
  elseif row == 1 and pot == 3 then
    params:set("cutoff", util.linexp(0, precision, ControlSpec.FREQ.minval, ControlSpec.FREQ.maxval, v))
  elseif row == 2 and pot == 1 then
    params:set("npolar_rot_amount", util.linlin(0, precision, 0, 1, v))
  elseif row == 2 and pot == 2 then
    params:set("npolar_rot_freq", util.linexp(0, precision, ControlSpec.WIDEFREQ.minval, ControlSpec.WIDEFREQ.maxval, v))
  elseif row == 2 and pot == 3 then
    params:set("npolar_rot_amount_sliced", util.linlin(0, precision, 0, 1, v))
  elseif row == 2 and pot == 4 then
    params:set("npolar_rot_freq_sliced", util.linexp(0, precision, ControlSpec.WIDEFREQ.minval, ControlSpec.WIDEFREQ.maxval, v))
  end
end

local function bleached_cc_amp(row, pot, v, precision)
  if row == 2 and pot == 1 then
    params:set("amp_attack", util.linexp(0, precision, ENV_ATTACK.minval, ENV_ATTACK.maxval, v))
  elseif row == 2 and pot == 2 then
    params:set("amp_decay", util.linexp(0, precision, ENV_DECAY.minval, ENV_DECAY.maxval, v))
  elseif row == 2 and pot == 3 then
    params:set("amp_sustain", util.linlin(0, precision, ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, v))
  elseif row == 2 and pot == 4 then
    params:set("amp_release", util.linexp(0, precision, ENV_RELEASE.minval, ENV_RELEASE.maxval, v))
  end
end

local function bleached_cc_filter(row, pot, v, precision)
  if row == 1 and pot == 1 then
    params:set("fenv_pct", util.linlin(0, precision, 0, 1, v))
  elseif row == 1 and pot == 2 then
    params:set("res", util.linlin(0, precision, 0, 4, v))
  elseif row == 1 and pot == 3 then
    params:set("cutoff", util.linexp(0, precision, ControlSpec.FREQ.minval, ControlSpec.FREQ.maxval, v))
  elseif row == 2 and pot == 1 then
    params:set("filter_attack", util.linexp(0, precision, ENV_ATTACK.minval, ENV_ATTACK.maxval, v))
  elseif row == 2 and pot == 2 then
    params:set("filter_decay", util.linexp(0, precision, ENV_DECAY.minval, ENV_DECAY.maxval, v))
  elseif row == 2 and pot == 3 then
    params:set("filter_sustain", util.linlin(0, precision, ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, v))
  elseif row == 2 and pot == 4 then
    params:set("filter_release", util.linexp(0, precision, ENV_RELEASE.minval, ENV_RELEASE.maxval, v))
  end
end

local function bleached_cc_cb(midi_msg)
  has_bleached = true

  -- if params:string("auto_bind_controller") == "no" then
  --   return
  -- end

  bleached.register_val(midi_msg.cc, midi_msg.val)
  if bleached.is_final_val_update(midi_msg.cc) then
    local row = bleached.cc_to_row(midi_msg.cc)
    local pot = bleached.cc_to_row_pot(midi_msg.cc)
    local v = bleached.last_val

    local precision = 127
    if bleached.is_14_bits() then
      precision = 16383
    end

    local curr_page = page_list[pages.index]
    if curr_page == 'main' then
      bleached_cc_main(row, pot, v, precision)
    elseif curr_page == 'amp' then
      bleached_cc_amp(row, pot, v, precision)
    elseif curr_page == 'filter' then
      bleached_cc_filter(row, pot, v, precision)
    end

  end
end


function aftertouch(v)
  -- review: don't use params for this but global state vars
  engine.cutoff_all(util.linexp(0, 1, params:get("cutoff"), math.min(params:get("cutoff") + ControlSpec.FREQ.maxval/10,ControlSpec.FREQ.maxval), v))
  engine.npolarRotFreq_all(util.linexp(0, 1, params:get("npolar_rot_freq"), math.min(params:get("npolar_rot_freq") + util.expexp(ControlSpec.WIDEFREQ.minval, ControlSpec.WIDEFREQ.maxval, 0, params:get("npolar_rot_freq"), params:get("npolar_rot_freq")), ControlSpec.WIDEFREQ.maxval), v))
  -- engine.npolarRotFreqSliced_all(util.linexp(0, 1, params:get("npolar_rot_freq_sliced"), math.min(params:get("npolar_rot_freq_sliced") + 100,ControlSpec.WIDEFREQ.maxval) , v))
end

function midi_event(data)
  local msg = midi.to_msg(data)

  if not msg.ch then
    return
  end

  if params:string("midi_channel") ~= "All" and msg.ch ~= (params:get("midi_channel") - 1) then
    return
  end

  if msg.type == "note_off" then
    voiceutils.note_off(STATE, msg.note)
  elseif msg.type == "note_on" then
    voiceutils.note_on(STATE, msg.note, msg.vel / 127)
  elseif msg.type == "channel_pressure" then
    aftertouch(msg.val / 127)
  end
end


-- -------------------------------------------------------------------------
-- init

local clock_redraw, clock_rot, clock_env

function fmt_phase(param)
  return param:get() .. "°"
end

function fmt_percent(param)
  local value = param:get()
  return string.format("%.2f", value * 100) .. "%"
end


function init()

  if norns then
    screen.aa(1)
  end

  -- --------------------------------
  -- controlspecs

  local pct_control_on = controlspec.new(0, 1, "lin", 0, 1.0, "")
  local pct_control_off = controlspec.new(0, 1, "lin", 0, 0.0, "")
  local pct_control_bipolar = controlspec.new(-1, 1, "lin", 0, 0.0, "")
  local phase_control = controlspec.new(0, 2 * math.pi, "lin", 0, 0.0, "")
  local vib_rate_control = controlspec.new(0, 30, "lin", 0, 10.0, "")
  local vib_depth_control = controlspec.new(0, 10, "lin", 0, 0.0, "")


  -- --------------------------------
  -- Ui graphs

  -- NB: those got chosen to mimic the ARP 2600
  -- FIXME: ENV_SUSTAIN is too much "all or nothing" in terms of perceived volume
  -- REVIEW: first redraw w/ actual values of env params instead of default?
  env_graph = EnvGraph.new_adsr(0, 1, 0, 1,
                                util.explin(ENV_ATTACK.minval, ENV_ATTACK.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_A),
                                util.explin(ENV_DECAY.minval, ENV_DECAY.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_D),
                                util.linlin(ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, 0, 1, DEFAULT_S),
                                util.explin(ENV_RELEASE.minval, ENV_RELEASE.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_R),
                                1,-4
  )
  env_graph:set_position_and_size(8, 22, 49, 36)
  env_graph:set_show_x_axis(true)

  fenv_graph = EnvGraph.new_adsr(0, 1, 0, 1,
                                 util.explin(ENV_ATTACK.minval, ENV_ATTACK.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_A),
                                 util.explin(ENV_DECAY.minval, ENV_DECAY.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_D),
                                 util.linlin(ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, 0, 1, DEFAULT_S),
                                 util.explin(ENV_RELEASE.minval, ENV_RELEASE.maxval, 0, ENVGRAPH_T_MAX, DEFAULT_R),
                                 1, -4)
  fenv_graph:set_position_and_size(8, 22, 49, 36)
  fenv_graph:set_show_x_axis(true)

  f_graph = FilterGraph.new(ControlSpec.FREQ.minval, ControlSpec.FREQ.maxval, -60, 32.5,
                            "lowpass",
                            12,
                            2000,
                            0)
  f_graph:set_position_and_size(64+8, 22, 49, 36)

  f_instant_graph = FilterGraph.new(ControlSpec.FREQ.minval, ControlSpec.FREQ.maxval, -60, 32.5,
                                    "lowpass",
                                    12,
                                    2000,
                                    0)
  f_instant_graph:set_position_and_size(64+8, 22, 49, 36)


  -- --------------------------------
  -- midi

  params:add{type = "number", id = "midi_device", name = "MIDI Device",
             min = 1, max = 4, default = 2,
             action = function(v)
               if m ~= nil then
                 m.event = nil
               end
               m = midi.connect(v)
               m.event = midi_event
  end}

  local MIDI_CHANNELS = {"All"}
  for i = 1, 16 do table.insert(MIDI_CHANNELS, i) end
  params:add{type = "option", id = "midi_channel", name = "MIDI Channel", options = MIDI_CHANNELS}


  -- --------------------------------
  -- global

  params:add{type = "number", id = "voice_count", name = "# voices",
             min = 1, max = 8, default = 8,
             action = engine.voice_count}

  params:add{type = "control", id = "binaurality", name = "binaurality",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = function(v)
               local binaural_index = NB_VOICES * v;

               -- voice pairing
               local prev_nb_dual_meta_voices = STATE.nb_dual_meta_voices
               STATE.nb_dual_meta_voices = util.round(binaural_index / 2)
               STATE.nb_meta_voices = NB_VOICES - STATE.nb_dual_meta_voices

               if STATE.nb_dual_meta_voices ~= prev_nb_dual_meta_voices then
                 -- if voiceutils.some_voices_need_pair(STATE) then
                 --   print("some voices need paired voices!")
                 -- end

                 local voice_id = 0
                 while voiceutils.some_voices_need_pair(STATE) do
                   voice_id = voice_id+1
                   if voice_id > NB_VOICES then
                     -- print("!!!!!!! ERROR !!!!!!! - reach max voice pairing attempts. this might be a bug.")
                     break
                   end
                   if voiceutils.is_solo_leader(STATE, voice_id) then
                     local follower_id = voiceutils.get_free_follower_voice(STATE, voice_id)
                     if follower_id then
                       -- print(" -> pairing: " .. voice_id .." <- " .. follower_id)
                       voiceutils.pair_voices(STATE, voice_id, follower_id)
                     else
                       -- print("!!!!!!! ERROR !!!!!!! - premature end of pairing. this might be a bug.")
                       break
                     end
                   end
                 end

                 -- if voiceutils.some_voices_need_unpair(STATE) then
                 --   print("some paired voices need to be unpaired!")
                 --   print(STATE.nb_active_dual_voices.." > "..STATE.nb_dual_meta_voices)
                 -- end

                 voice_id = 0
                 while voiceutils.some_voices_need_unpair(STATE) do
                   voice_id = voice_id+1
                   if voice_id > NB_VOICES then
                     -- print("!!!!!!! ERROR !!!!!!! - reach max voice unpairing attempts. this might be a bug.")
                     break
                   end
                   if voiceutils.is_paired_leader(STATE, voice_id) then
                     voiceutils.unpair_follower_voices(STATE, voice_id)
                   end
                 end
               end

               -- panning
               local pan_pct = v;
               for i=1, NB_VOICES do
                 local v_pan_dir = (mod1(i, 2) == 1) and -1 or 1
                 local v_pan_pct = 1

                 if i >= math.floor(binaural_index) then
                   v_pan_pct = 1 - util.linlin(binaural_index, NB_VOICES, 0, 1, i)
                 end
                 -- print("pan "..i.." -> "..(pan_pct * v_pan_dir * v_pan_pct))
                 voices[i].pan = pan_pct * v_pan_dir * v_pan_pct
                 engine.pan(i, pan_pct * v_pan_dir * v_pan_pct / 2)
               end
  end}

  params:add{type = "control", id = "pan_lfo_freq", name = "binaural pan freq",
             controlspec = vib_rate_control, formatter = Formatters.format_freq,
             action = engine.pan_lfo_freq_all}


  -- --------------------------------
  params:add_separator("main osc", "main osc")

  params:add_trigger("random", "random")
  params:set_action("random",
                    function(v)
                      print("shuffling wave")

                      for i=1,4 do
                        params:set("index"..i, math.random(#WAVESHAPES))
                      end
                      recompute_effective_freq()
                      screen_dirty=true
  end)

  -- FIXME: should call recompute_effective_freq() after change of value!
  -- use a clock instead?

  params:add{type = "option", id = "index1", name = "index1", options = WAVESHAPES,
             action = function(v)
               engine.index1_all(v-1)
               screen_dirty = true
  end}

  params:add{type = "option", id = "index2", name = "index2", options = WAVESHAPES,
             action = function(v)
               engine.index2_all(v-1)
               screen_dirty = true
  end}
  params:add{type = "option", id = "index3", name = "index3", options = WAVESHAPES,
             action = function(v)
               engine.index3_all(v-1)
               screen_dirty = true
  end}
  params:add{type = "option", id = "index4", name = "index4", options = WAVESHAPES,
             action = function(v)
               engine.index4_all(v-1)
               screen_dirty = true
  end}

  params:add{type = "control", id = "freq", name = "freq",
             controlspec = CS_MIDLOWFREQ, formatter = Formatters.format_freq,
             action = function(v)
               BASE_FREQ = v
               local mod = params:get("mod")

               recompute_effective_freq(BASE_FREQ, mod)

               local div = 1
               if PITCH_COMPENSATION_SYNC then
                 div = params:get("sync_ratio")/4
               end
               local mult = 1

               if PITCH_COMPENSATION_MOD then
                 mult = effective_period/2
               end
               FREQ = mult * (BASE_FREQ/div)
               engine.freq_curr(FREQ)

               voices[STATE.curr_voice_id].hz = FREQ
  end}
  -- params:set("freq", BASE_FREQ)

  params:add{type = "control", id = "freq_sag", name = "freq sag",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.freq_sag_all}
  params:set("freq_sag", 0.1)


  params:add{type = "control", id = "vib_rate", name = "vibrato rate",
             controlspec = vib_rate_control, formatter = Formatters.format_freq,
             action = engine.vib_rate_all}

  params:add{type = "control", id = "vib_depth", name = "vibrato depth",
             controlspec = vib_depth_control,
             action = engine.vib_depth_all}


  -- --------------------------------
  params:add_separator("mod osc", "mod osc")

  params:add{type = "number", id = "mod", name = "mod",
             min = 2, max = 15, default = 3,
             action = function(v)
               engine.mod_all(v)
               local mod = v

               recompute_effective_freq(BASE_FREQ, mod)

               local div = 1
               if PITCH_COMPENSATION_SYNC then
                 div = params:get("sync_ratio")/4
               end
               local mult = 1

               if PITCH_COMPENSATION_MOD then
                 mult = effective_period/2
               end
               FREQ = mult * (BASE_FREQ/div)
               engine.freq_curr(FREQ)

               screen_dirty = true
  end}

  params:add{type = "control", id = "npolar_rot_amount", name = "rot amount",
             controlspec = pct_control_on, formatter = fmt_percent,
             action = engine.npolarProj_all}
  params:add{type = "control", id = "npolar_rot_freq", name = "rot freq",
             controlspec = ControlSpec.WIDEFREQ, formatter = Formatters.format_freq,
             action = engine.npolarRotFreq_all}
  params:add{type = "control", id = "npolar_rot_freq_sag", name = "rot freq sag",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.npolarRotFreq_sag_all}
  params:set("npolar_rot_freq_sag", 0.1)

  params:add{type = "control", id = "npolar_rot_amount_sliced", name = "rot amount sliced",
             controlspec = pct_control_on, formatter = fmt_percent,
             action = engine.npolarProjSliced_all}
  params:add{type = "control", id = "npolar_rot_freq_sliced", name = "rot freq sliced",
             controlspec = ControlSpec.WIDEFREQ, formatter = Formatters.format_freq,
             action = engine.npolarRotFreqSliced_all}
  params:add{type = "control", id = "npolar_rot_freq_sliced_sag", name = "rot freq sliced sag",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.npolarRotFreqSliced_sag_all}
  params:set("npolar_rot_freq_sliced_sag", 0.1)

  params:add{type = "number", id = "sync_ratio", name = "sync_ratio",
             min = 1, max = 10, default = 1,
             action = function(v)
               engine.syncRatio_all(v)

               recompute_effective_freq()

               local div = 1
               if PITCH_COMPENSATION_SYNC then
                 div = v/4
               end
               local mult = 1
               if PITCH_COMPENSATION_MOD then
                 mult = params:get("mod") / 2
               end
               FREQ = mult * (BASE_FREQ/div)
               engine.freq_curr(FREQ)


               -- BASE_FREQ = BASE_FREQ / v
               -- FREQ = params:get("mod") * BASE_FREQ/2
               -- engine.freq_curr(FREQ)

               screen_dirty = true
  end}

  params:add{type = "number", id = "sync_phase", name = "sync_phase",
             min = 0, max = 360, default = 0,
             formatter = fmt_phase,
             action = function(v)
               local a = util.linlin(0, 360, 0, 2 * math.pi, v)
               engine.syncPhase_all(a)
               screen_dirty = true
  end}


  -- --------------------------------
  params:add_separator("filter", "filter")

  params:add{type = "control", id = "fenv_pct", name = "filter env %",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.fenv_a_all}
  params:set("fenv_pct", 0.1)

  params:add{type = "control", id = "fktrack", name = "filter kbd track",
             controlspec = pct_control_bipolar, action = engine.fktrack_all}
  params:set("fktrack", 0.2)

  params:add{type = "control", id = "cutoff", name = "cutoff",
             controlspec = ControlSpec.FREQ, formatter = Formatters.format_freq,
             action = function(v)
               engine.cutoff_all(v)
               update_intant_cutoff(v)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}

  params:add{type = "control", id = "cutoff_sag", name = "cutoff sag",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.cutoff_sag_all}
  params:set("cutoff_sag", 0.1)

  local moog_res = controlspec.new(0, 4, "lin", 0, 0.0, "")
  params:add{type = "control", id = "res", name = "res",
             controlspec = moog_res,
             action = function(v)
               engine.resonance_all(v)
               f_graph:edit(nil, nil, nil, v/moog_res.maxval)
               f_instant_graph:edit(nil, nil, nil, v/moog_res.maxval)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}




  -- --------------------------------
  params:add_separator("amp env", "amp env")

  params:add{type = "control", id = "amp_offset", name = "Amp Offset",
             controlspec = pct_control_off, formatter = format_percent,
             action = engine.amp_offset_all}
  params:add{type = "control", id = "amp_attack", name = "Amp Attack",
             controlspec = ENV_ATTACK, formatter = Formatters.format_secs,
             action = function(v)
               engine.attack_all(v)
               local nv = util.explin(ENV_ATTACK.minval, ENV_ATTACK.maxval, 0, ENVGRAPH_T_MAX, v)
               env_graph:edit_adsr(nv, nil, nil, nil)
               if page_list[pages.index] == 'amp' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "amp_decay", name = "Amp Decay",
             controlspec = ENV_DECAY, formatter = Formatters.format_secs,
             action = function(v)
               engine.decay_all(v)
               local nv = util.explin(ENV_DECAY.minval, ENV_DECAY.maxval, 0, ENVGRAPH_T_MAX, v)
               env_graph:edit_adsr(nil, nv, nil, nil)
               if page_list[pages.index] == 'amp' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "amp_sustain", name = "Amp Sustain",
             controlspec = ENV_SUSTAIN,
             action = function(v)
               engine.sustain_all(v)
               local nv = util.linlin(ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, 0, 1, v)
               env_graph:edit_adsr(nil, nil, nv, nil)
               if page_list[pages.index] == 'amp' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "amp_release", name = "Amp Release",
             controlspec = ENV_RELEASE, formatter = Formatters.format_secs,
             action = function(v)
               engine.release_all(v)
               local nv = util.explin(ENV_RELEASE.minval, ENV_RELEASE.maxval, 0, ENVGRAPH_T_MAX, v)
               env_graph:edit_adsr(nil, nil, nil, nv)
               if page_list[pages.index] == 'amp' then
                 screen_dirty = true
               end
  end}


  -- --------------------------------
  params:add_separator("filter env", "filter env")

  -- filter env
  params:add{type = "control", id = "filter_attack", name = "Filter Attack",
             controlspec = ENV_ATTACK, formatter = Formatters.format_secs,
             action = function(v)
               engine.fdecay_all(v)
               local nv = util.explin(ENV_ATTACK.minval, ENV_ATTACK.maxval, 0, ENVGRAPH_T_MAX, v)
               fenv_graph:edit_adsr(nv, nil, nil, nil)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "filter_decay", name = "Filter Decay",
             controlspec = ENV_DECAY, formatter = Formatters.format_secs,
             action = function(v)
               engine.fdecay_all(v)
               local nv = util.explin(ENV_DECAY.minval, ENV_DECAY.maxval, 0, ENVGRAPH_T_MAX, v)
               fenv_graph:edit_adsr(nil, nv, nil, nil)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "filter_sustain", name = "Filter Sustain",
             controlspec = ENV_SUSTAIN,
             action = function(v)
               engine.fsustain_all(v)
               local nv = util.linlin(ENV_SUSTAIN.minval, ENV_SUSTAIN.maxval, 0, 1, v)
               fenv_graph:edit_adsr(nil, nil, nv, nil)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}
  params:add{type = "control", id = "filter_release", name = "Filter Release",
             controlspec = ENV_RELEASE, formatter = Formatters.format_secs,
             action = function(v)
               engine.frelease_all(v)
               local nv = util.explin(ENV_RELEASE.minval, ENV_RELEASE.maxval, 0, ENVGRAPH_T_MAX, v)
               fenv_graph:edit_adsr(nil, nil, nil, nv)
               if page_list[pages.index] == 'filter' then
                 screen_dirty = true
               end
  end}
  params:set("filter_attack", 1.0)
  params:set("filter_release", 4.0)


  -- --------------------------------
  params:add_separator("vintage", "vintage")

  local pct_sat_threshold = controlspec.new(0.1, 1, "lin", 0, 0.5, "")
  params:add{type = "control", id = "sat_threshold", name = "sat/comp threshold",
             controlspec = pct_sat_threshold,
             action = engine.sat_threshold_all}

  params:add{type = "control", id = "pitch_offness", name = "pitch offness",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.pitch_offness_pct_all}

  params:add{type = "control", id = "cutoff_offness", name = "cutoff offness",
             controlspec = pct_control_off, formatter = fmt_percent,
             action = engine.cutoff_offness_pct_all}


  -- --------------------------------
  params:add_separator("internal_trimmers", "internal trimmers")

  for i=1,NB_VOICES do
    params:add_group("internal_trimmers_v"..i, "voice #"..i, 3)

    params:add{type = "control", id = "pitch_offness_max_"..i, name = "max pitch offness #"..i,
               controlspec = pct_control_bipolar, formatter = fmt_percent,
               action = function(v)
                 engine.pitch_offness_max(i, v)
    end}

    params:add{type = "control", id = "cutoff_offness_max_"..i, name = "max cutoff offness #"..i,
               controlspec = pct_control_bipolar, formatter = fmt_percent,
               action = function(v)
                 engine.cutoff_offness_max(i, v)
    end}

    params:add{type = "control", id = "pan_lfo_phase_"..i, name = "pan lfo phase #"..i,
               controlspec = phase_control, formatter = fmt_phase,
               action = function(v)
                 engine.pan_lfo_phase(i, v)
    end}
  end


  -- --------------------------------
  -- init vintage

  for i=1,NB_VOICES do
    local sign = (math.random(2) == 2) and 1 or -1
    params:set("pitch_offness_max_"..i, sign * (math.random(100+1)-1)/100)
    sign = (math.random(2) == 2) and 1 or -1
    params:set("cutoff_offness_max_"..i, sign * (math.random(100+1)-1)/100)

    params:set("pan_lfo_phase_"..i, 2 * math.pi / i)
  end

  -- params:set("index1", 2)
  -- params:set("index2", 2)
  -- params:set("index3", 2)
  -- params:set("index4", 2)

  -- params:set("index1", 3)
  -- params:set("index2", 3)
  -- params:set("index3", 3)
  -- params:set("index4", 3)

  params:bang()

  -- params:set("index1", 1)
  -- params:set("index2", 1)
  -- params:set("index3", 1)
  -- params:set("index4", 1)

  -- params:set("index1", 4)
  -- params:set("index2", 4)
  -- params:set("index3", 4)
  -- params:set("index4", 4)

  bleached.init(bleached_cc_cb)
  bleached.switch_cc_mode(bleached.M_CC14)

  clock_redraw = clock.run(function()
      while true do
        clock.sleep(1/FPS)
        if screen_dirty then
          redraw()
        end
      end
  end)

  clock_rot = clock.run(function()
      while true do
        clock.sleep(1/ROT_FPS)
        rot_tick()
      end
  end)

  clock_env = clock.run(function()
      while true do
        clock.sleep(1/ENV_FPS)
        env_tick()
      end
  end)
end

function cleanup()
  bleached.switch_cc_mode(bleached.M_CC)
end


-- -------------------------------------------------------------------------
-- controls

function enc(n, d)
  local s = math.abs(d) / d
  if n == 1 then
    pages:set_index_delta(d, false)
  elseif n == 2 then
    params:set("mod", params:get("mod") + s)
  elseif n == 3 then
    params:set("sync_ratio", params:get("sync_ratio") + s)
  end
  screen_dirty = true
end

local k1 = false
local k2 = false
local k3 = false

function key(n, v)
  if n == 1 then
    k1 = (v == 1)
  end
  if n == 2 then
    k2 = (v == 1)
  end
  if n == 3 then
    k3 = (v == 1)
  end

  if k1 and k3 then
    params:set("random", 1)
  end
end


-- -------------------------------------------------------------------------
-- waveforms

function nsin(x)
  return math.sin(x * 2 * math.pi)
end

function nsaw(x)
  if x < 0 then
    return linlin(0, 1, 1, -1, -x)
  end
  return linlin(0, 1, 1, -1, x)
  -- return (1 - (x + 0.25) % 1) * 2 - 1
end

function ntri(x)
  return math.abs((x * 2 - 0.5) % 2 - 1) * 2 - 1
end

function nsqr(x)
  x = x + 0.25
  local square = math.abs(x * 2 % 2 - 1) - 0.5
  square = square > 0 and 1 or math.floor(square) * 1
  return square * -1
end

function nwave(waveshape, x)
  local wave_map = {
    ["SIN"] = nsin,
    ["SAW"] = nsaw,
    ["TRI"] = ntri,
    ["SQR"] = nsqr,
  }
  return wave_map[waveshape](x)
end


-- -------------------------------------------------------------------------
-- display recalculations

function update_voice_fenv(voice_id)
  if voices[voice_id].active then
    if voices[voice_id].t_since_note_on <= params:get("filter_attack") then
      voices[voice_id].fenv = util.linlin(0, params:get("filter_attack"), 0, 1, voices[voice_id].t_since_note_on)
    else
      voices[voice_id].fenv = util.linlin(0, params:get("filter_decay"), 1, params:get("filter_sustain"), voices[voice_id].t_since_note_on - params:get("filter_attack"))
    end
  else
    voices[voice_id].fenv = util.linlin(0, params:get("filter_release"), voices[voice_id].fenv, 0, voices[voice_id].t_since_note_off)
  end

  voices[voice_id].fenv_cutoff_offset = util.linlin(0, 1, 0, 15000, voices[voice_id].fenv * params:get("fenv_pct"))
end

function update_intant_cutoff(base_cutoff)
  if not base_cutoff then
    base_cutoff = params:get("cutoff")
  end
  local intant_cutoff = base_cutoff
  if STATE.last_played_voice then
    intant_cutoff = intant_cutoff + voices[STATE.last_played_voice].fenv_cutoff_offset
  end
  f_graph:edit(nil, nil, base_cutoff)
  f_instant_graph:edit(nil, nil, intant_cutoff)
end

function env_tick()
  -- TODO: recompute cutoff
  -- TODO: recompute amp

  local elapsed_t = 1/ENV_FPS

  for i=1,NB_VOICES do
    if voices[i].active then
      if voices[i].note_just_on then
        voices[i].t_since_note_on = 0
        voices[i].note_just_on = false
      end
      voices[i].t_since_note_on = voices[i].t_since_note_on + elapsed_t
    else
      if voices[i].note_just_off then
        voices[i].t_since_note_off = 0
        voices[i].note_just_off = false
      end
      voices[i].t_since_note_off = voices[i].t_since_note_off + elapsed_t
    end

    update_voice_fenv(i)
    update_intant_cutoff()
  end
end

function rot_tick()
  local tick = (1 / ROT_FPS) * params:get("npolar_rot_freq")
  rot_angle = rot_angle + tick
  while rot_angle > 1 do
    rot_angle = rot_angle - 1
  end

  local tick_sliced = (1 / ROT_FPS) * params:get("npolar_rot_freq_sliced")
  rot_angle_sliced = rot_angle_sliced + tick_sliced
  while rot_angle_sliced > 1 do
    rot_angle_sliced = rot_angle_sliced - 1
  end

  for i=1,NB_VOICES do
    local tick_v = (1 / ROT_FPS) * voices[i].hz
    voices[i].rot_angle = voices[i].rot_angle + tick_v
    while voices[i].rot_angle > 1 do
      voices[i].rot_angle = voices[i].rot_angle - 1
    end
  end

  -- print(rot_angle)
  screen_dirty = true
end


-- -------------------------------------------------------------------------
-- screen

-- NB: mod1_a, mod2_a, mod1hz, mod2hz are used to displaying the ring mod effect
-- i'm pretty sure the math is plain wrong, but it does look right...
function draw_wave(waveshape,
                   x, w,
                   y, a,
                   sign, dir,
                   segment, nb_segments,
                   mod1_a, mod2_a,
                   mod1hz, mod2hz)
  if dir == nil then
    dir = 1
  end
  if segment == nil then
    segment = 1
  end
  if nb_segments == nil then
    nb_segments = 1
  end

  local half_wave_w = w * nb_segments
  local w_offset = util.linlin(1, nb_segments+1, 0, half_wave_w, segment)

  local x0 = x
  local xn = x0 + dir * half_wave_w
  local xn_pos = x0 + half_wave_w
  local x1 = x0 + dir * w_offset
  local x2 = x1 + dir * w

  -- print("("..x0 ..","..xn..") - ("..x1 ..","..x2..") - "..sign..","..dir)

  for i=x1,x2,dir do
    local startn = 0
    local endn = 1/2
    if sign == -1 then
      local startn = 1/2
      local endn = 1
      -- print(linlin(x0, xn, startn, endn, i))
    end
    local nx = math.abs(linlin(x0, xn, startn, endn, i))

    local mod_a = 0
    if mod1hz then
      -- print(mod1hz)
      local nxa = math.abs(linlin(x0, xn, 0, mod1hz, i))
      mod_a = mod_a + nsin(nxa) * mod1_a
    end
    if mod2hz then
      local nxb = math.abs(linlin(x0, xn, 0, mod2hz, i))
      mod_a = mod_a + nsin(nxb) * mod2_a
    end
    local rm_visual_speed = math.max(mod1hz*mod1_a, mod2hz*mod2_a)
    local rm_visual_a = util.explin(0.000001, 2500, 4, 10, rm_visual_speed)
    rm_visual_a = 4

    screen.line(i, y + nwave(waveshape, nx) * a * sign * -1 + sign * mod_a * rm_visual_a)
  end
end

function draw_mod_wave(x, w, y, a, sign, dir)
  screen.level(S_LVL_MOD)
  if dir == nil then
    dir = 1
  end
  local mod = params:get("sync_ratio")
  w = util.round(w/mod)
  a = util.round(a/mod)
  screen.move(x, y)
  for i=1,mod do
    screen.line(x + dir * (i-1) * w, y + i * sign * a)
    screen.line(x + dir * i * w, y + i * sign * a)
  end
  screen.stroke()
  screen.level(15)
end

function draw_poles(x, y, radius, speed, rot_angle, is_active)
  local l = is_active and 15 or 5
  screen.level(0)
  screen.move(x + radius + 2, y)
  screen.circle(x, y, radius + 2)
  screen.fill()

  screen.level(l)
  screen.move(x + radius, y)
  screen.circle(x, y, radius)
  screen.stroke()

  local nb_poles = 2
  local amount = 0

  if speed > ROT_FPS/2 then
    screen.level(util.round(util.linlin(0, l, 2, 10, nb_poles)))
    local ratio = speed / (ROT_FPS/2)
    local r = util.explin(1, ControlSpec.WIDEFREQ.maxval / ROT_FPS, 1, radius, ratio)
    screen.move(x, y)
    screen.circle(x, y, r)
    screen.fill()
  end

  for i=1, nb_poles do
    local r2 = radius

    local angle = (i-1) * 2 * math.pi / nb_poles
    local angle2 = angle/(2 * math.pi) + rot_angle
    while angle2 > 1 do
      angle2 = angle2 - 1
    end

    screen.level(l)
    screen.move(x, y)
    screen.line(x + r2 * cos(angle2) * -1, y + r2 * sin(angle2))
    screen.stroke()
  end
end

function draw_mod_poles(x, y, radius, nb_poles, amount, rot_angle, speed)
  screen.level(0)
  screen.move(x + radius + 2, y)
  screen.circle(x, y, radius + 2)
  screen.fill()

  screen.level(15)
  screen.move(x + radius, y)
  screen.circle(x, y, radius)
  screen.stroke()

  -- NB: we're gettting the notorious "wagon-wheel effect" which makes effective speed less readable
  -- so we add artifacts to give a sense of scale of speeds past ROT_FPS
  if speed > ROT_FPS/2 then
    -- screen.level(util.round(util.linlin(1, 15, nb_poles)))
    screen.level(util.round(util.linlin(0, 15, 2, 10, nb_poles)))
    local ratio = speed / (ROT_FPS/2)
    local r = util.explin(1, ControlSpec.WIDEFREQ.maxval / ROT_FPS, 1, radius, ratio)
    -- print(ratio .. " -> " .. r)

    local y2 = y
    if amount <= 0.5 then
      y2 = util.round(y - amount * r)
      local rtop = r - amount * r
      screen.move(x + rtop, y2)
      screen.circle(x, y2, rtop)
      screen.fill()
    else
      local abtm = amount - 0.5
      -- local atop = 1 - abtm

      -- local rtop = atop * r
      local rtop = r - 0.5 * r
      local rbtm = abtm * r

      y2 = util.round(y - rtop)
      screen.move(x + rtop, y2)
      screen.circle(x, y2, rtop)
      screen.fill()

      y2 = util.round(y + rbtm)
      screen.move(x + rbtm, y2)
      screen.circle(x, y2, rbtm)
      screen.fill()
    end
  end

  for i=1, nb_poles do

    local r2 = radius * linlin(0, 1, 1, amp_for_pole(i, nb_poles, rot_angle, 1, dir), amount)
    r2 = math.abs(r2)

    local angle = (i-1) * 2 * math.pi / nb_poles
    local angle2 = angle/(2 * math.pi) + rot_angle
    while angle2 > 1 do
      angle2 = angle2 - 1
    end

    -- screen.line(x + radius * cos(angle2) * -1, y + radius * sin(angle2))

    -- screen.level(3)
    -- screen.move(x, y)
    -- screen.line(x + radius * cos(angle2) * -1, y + radius * sin(angle2))
    -- screen.stroke()

    screen.level(15)
    screen.move(x, y)
    screen.line(x + r2 * cos(angle2) * -1, y + r2 * sin(angle2))
    screen.stroke()
  end


end

function draw_scope_grid(screen_w, screen_h)
  screen.level(5)
  screen.move(screen_w/2, 0)
  screen.line(screen_w/2, screen_h)
  screen.stroke()

  screen.move(0, screen_h/2)
  screen.line(screen_w, screen_h/2)
  screen.stroke()

  screen.level(15)
end

function amp_for_pole(n, mod, rot_angle, a, dir)
  if dir == nil then
    dir = 1
  end

  local angle = (n-1) * 2 * math.pi / mod
  local pole_angle = angle/(2 * math.pi) +  dir * rot_angle
  while pole_angle > 1 do
    pole_angle = pole_angle - 1
  end
  while pole_angle < 0 do
    pole_angle = pole_angle + 1
  end

  local sign = 1
  if pole_angle > 0.5 then
    sign = -1
  end

  -- FIXME: dirty patch, weird that it's needed
  if (mod == 2 and n == 2) then
    sign = -sign
  end

  if pole_angle < 0.25 then
    return sign * linlin(0, 0.25, 0, a, pole_angle)
  elseif pole_angle < 0.5 then
    return sign * linlin(0.25, 0.5, a, 0, pole_angle)
  elseif pole_angle < 0.75 then
    return sign * linlin(0.5, 0.75, 0, a, pole_angle)
  else
    return sign * linlin(0.75, 1, a, 0, pole_angle)
  end
end

function draw_page_main()
  local screen_w, screen_h = screen_size()

  local sync_ratio = params:get("sync_ratio") -- nb of sub-segments
  local mod = params:get("mod")
  local mod_sliced = mod * sync_ratio
  local half_waves = mod
  local half_wave_w = util.round(screen_w/(half_waves*2))
  local segment_w = half_wave_w / sync_ratio
  local abscissa = screen_h/2
  local a = abscissa * 3/6

  local freq = voices[STATE.curr_voice_id].hz

  local sign = 1
  local x_offset = screen_w/2

  local p_pargin = 1
  local p_radius = 10

  -- poles - main osc voices
  for i=1,params:get("voice_count") do
    -- params:get("binaurality")
    draw_poles((p_radius+p_pargin) + (p_radius+p_pargin) * ((i-1) * 0.5), p_radius+p_pargin, p_radius, voices[i].hz, voices[i].rot_angle, voices[i].active)
    if i == STATE.next_voice_id then
      screen.pixel(
        util.round((p_radius+p_pargin) + (p_radius+p_pargin) * ((i-1) * 0.5)),
        util.round(2*p_radius+p_pargin) + 3)
      screen.fill()
    elseif i == STATE.curr_voice_id then
      screen.pixel(
        util.round((p_radius+p_pargin) + (p_radius+p_pargin) * ((i-1) * 0.5)),
        util.round(2*p_radius+p_pargin) + 2)
      screen.pixel(
        util.round((p_radius+p_pargin) + (p_radius+p_pargin) * ((i-1) * 0.5)) + 1,
        util.round(2*p_radius+p_pargin) + 3)
      screen.pixel(
        util.round((p_radius+p_pargin) + (p_radius+p_pargin) * ((i-1) * 0.5)),
        util.round(2*p_radius+p_pargin) + 4)
      screen.fill()
    end
  end

  -- poles - mod osc
  draw_mod_poles(screen_w-(p_radius+p_pargin)*(2 + 0.3), p_radius+p_pargin, p_radius, params:get("mod"), params:get("npolar_rot_amount"), rot_angle, params:get("npolar_rot_freq"))
  draw_mod_poles(screen_w-(p_radius+p_pargin), p_radius+p_pargin, p_radius, params:get("sync_ratio"), params:get("npolar_rot_amount_sliced"), rot_angle_sliced, params:get("npolar_rot_freq_sliced"))

  screen.aa(0)
  draw_scope_grid(screen_w, screen_h)

  -- mod wave
  for i=1,half_waves do
    draw_mod_wave(x_offset + (i-1) * half_wave_w, half_wave_w, abscissa, a, sign)
    sign = sign * -1
  end

  for i=1,half_waves do
    draw_mod_wave(x_offset - (i-1) * half_wave_w, half_wave_w, abscissa, a, -sign, -1)
    sign = sign * -1
  end

  screen.aa(1)

  -- signal wave
  sign = 1
  screen.move(x_offset, abscissa)
  for i=1,half_waves do
    for j=1,sync_ratio do
      -- local wi = util.clamp(mod1((i-1) * j, #WAVESHAPES), 1, #WAVESHAPES)
      local wi = mod1(i + (j - 1), #WAVESHAPES)
      local waveshape = params:string("index"..wi)
      local mod1_a = linlin(0, 1, 1, amp_for_pole(i, mod, rot_angle, 1), params:get("npolar_rot_amount"))
      local mod2_a =  linlin(0, 1, 1, amp_for_pole(i*j, mod_sliced, rot_angle_sliced, 1), params:get("npolar_rot_amount_sliced"))
      local pole_a = a * mod1_a * mod2_a
      draw_wave(waveshape,
                x_offset + (i-1) * half_wave_w, segment_w,
                abscissa, pole_a,
                sign, 1,
                j, sync_ratio,
                params:get("npolar_rot_amount"), params:get("npolar_rot_amount_sliced"),
                params:get("npolar_rot_freq") / freq, params:get("npolar_rot_freq_sliced") / freq)
    end
    sign = sign * -1
  end
  screen.stroke()

  sign = 1
  screen.move(x_offset, abscissa)
  for i=1,half_waves do
    for j=1,sync_ratio do
      -- local wi = math.floor(mod1(i * j, #WAVESHAPES))
      local wi = mod1(i + (j - 1), #WAVESHAPES)
      local waveshape = params:string("index"..wi)
      local mod1_a = linlin(0, 1, 1, -amp_for_pole(i, mod, rot_angle, 1, -1), params:get("npolar_rot_amount"))
      local mod2_a =  linlin(0, 1, 1, -amp_for_pole(i*j, mod_sliced, rot_angle_sliced, 1, -1), params:get("npolar_rot_amount_sliced"))
      local pole_a = a * mod1_a * mod2_a

      draw_wave(waveshape,
                x_offset - (i-1) * half_wave_w, segment_w,
                abscissa, pole_a,
                -sign, -1,
                j, sync_ratio,
                params:get("npolar_rot_amount"), params:get("npolar_rot_amount_sliced"),
                params:get("npolar_rot_freq") / freq, params:get("npolar_rot_freq_sliced") / freq)
    end
    sign = sign * -1
  end
  screen.stroke()

  -- metrics
  screen.move(0, screen_h)
  local msg = "f="..Formatters.format_freq_raw(params:get("freq")).." -> "..Formatters.format_freq_raw(effective_freq)
  if PITCH_COMPENSATION_MOD then
    msg = msg .. " -> " .. (effective_freq * effective_period/2)
  end
  screen.text(msg)
end

function draw_page_rot_mod()
  local screen_w, screen_h = screen_size()

  local p_pargin = 1
  local p_radius = 10

  draw_mod_poles(screen_w-(p_radius+p_pargin)*(2 + 0.3), p_radius+p_pargin, p_radius, params:get("mod"), params:get("npolar_rot_amount"), rot_angle, params:get("npolar_rot_freq"))
end

function draw_page_rot_mod_sliced()
  local screen_w, screen_h = screen_size()

  local p_pargin = 1
  local p_radius = 10

  draw_mod_poles(screen_w-(p_radius+p_pargin), p_radius+p_pargin, p_radius, params:get("sync_ratio"), params:get("npolar_rot_amount_sliced"), rot_angle_sliced, params:get("npolar_rot_freq_sliced"))
end

function redraw()
  screen.clear()

  pages:redraw()

  local curr_page = page_list[pages.index]
  if curr_page == 'main' then
    draw_page_main()
  elseif curr_page == 'amp' then
    env_graph:redraw()
  elseif curr_page == 'filter' then
    fenv_graph:redraw()
    f_graph:redraw()
    f_instant_graph:redraw()
  elseif curr_page == 'rot_mod' then
    draw_page_rot_mod()
  elseif curr_page == 'rot_mod_sliced' then
    draw_page_rot_mod_sliced()
  end

  screen.update()
  screen_dirty = false
end
