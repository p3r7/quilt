-- farrago.
-- @eigen


-- -------------------------------------------------------------------------
-- deps

local ControlSpec = require "controlspec"
local Formatters = require "formatters"
local MusicUtil = require "musicutil"

local bleached = include("lib/bleached")

include("lib/core")

engine.name = "Farrago"


-- -------------------------------------------------------------------------
-- consts

ROT_FPS = 30 -- NB: there is no point in making it faster than FPS

FPS = 15
if norns.version == "update	231108" then
  FPS = 30
end

local WAVESHAPES = {"SIN", "SAW", "TRI", "SQR"}

function screen_size()
  if seamstress then
    return screen.get_size()
  elseif norns then
    return 128, 64
  end
end

S_LVL_MOD = 2


-- -------------------------------------------------------------------------
-- state

screen_dirty = true

rot_angle = 0
rot_angle_sliced = 0

has_bleached = false


-- -------------------------------------------------------------------------
-- controllers

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

    if row == 1 and pot == 1 then
      --
    elseif row == 1 and pot == 2 then
      --
    elseif row == 1 and pot == 3 then
      params:set("cutoff", util.linexp(0, precision, ControlSpec.FREQ.minval, ControlSpec.FREQ.maxval, v))
    elseif row == 2 and pot == 1 then
      params:set("npolar_rot_amount", util.linlin(0, precision, 0, 1, v))
    elseif row == 2 and pot == 2 then
      params:set("npolar_rot_freq", util.linexp(0, precision, 1, 15000, v))
    elseif row == 2 and pot == 3 then
      params:set("npolar_rot_amount_sliced", util.linlin(0, precision, 0, 1, v))
    elseif row == 2 and pot == 4 then
      params:set("npolar_rot_freq_sliced", util.linexp(0, precision, 1, 15000, v))
    end
  end
end


-- -------------------------------------------------------------------------
-- init

local clock_redraw, clock_rot

function fmt_phase(param)
  return param:get() .. "°"
end

function fmt_percent(param)
  local value = param:get()
  return string.format("%.2f", value * 100) .. "%"
end

BASE_FREQ = 440/2
FREQ = BASE_FREQ

-- PITCH_COMPENSATION_MOD = true
PITCH_COMPENSATION_MOD = false
-- PITCH_COMPENSATION_SYNC = false
PITCH_COMPENSATION_SYNC = false

function init()

  if norns then
    screen.aa(1)
  end

  local pct_control_on = controlspec.new(0, 1, "lin", 0, 1.0, "")
  local phase_control = controlspec.new(0, 2 * math.pi, "lin", 0, 0.0, "")

  params:add_trigger("random", "random")
  params:set_action("random",
                    function(v)
                      print("shuffling wave")

                      for i=1,4 do
                        params:set("index"..i, math.random(#WAVESHAPES))
                      end
                      screen_dirty=true
  end)


  params:add{type = "number", id = "mod", name = "mod", min = 2, max = 31, default = 3, action = function(v)
               engine.mod(v)

               local div = 1
               if PITCH_COMPENSATION_SYNC then
                 div = params:get("sync_ratio")/2
               end
               local mult = 1
               if PITCH_COMPENSATION_MOD then
                 mult = v / 4
               end
               FREQ = mult * (BASE_FREQ/div)
               engine.freq(FREQ)

               screen_dirty = true
  end}

  params:add{type = "control", id = "npolar_rot_amount", name = "rot amount", controlspec = pct_control_on, formatter = fmt_percent, action = engine.npolarProj}
  params:add{type = "number", id = "npolar_rot_freq", name = "rot freq", min = 1, max = 15000, default = 1, action = engine.npolarRotFreq}

  params:add{type = "control", id = "npolar_rot_amount_sliced", name = "rot amount sliced", controlspec = pct_control_on, formatter = fmt_percent, action = engine.npolarProjSliced}
  params:add{type = "number", id = "npolar_rot_freq_sliced", name = "rot freq sliced", min = 1, max = 15000, default = 1, action = engine.npolarRotFreqSliced}

  params:add{type = "number", id = "sync_ratio", name = "sync_ratio", min = 1, max = 10, default = 1,
             action = function(v)
               engine.syncRatio(v)

               local div = 1
               if PITCH_COMPENSATION_SYNC then
                 div = v/2
               end
               local mult = 1
               if PITCH_COMPENSATION_MOD then
                 mult = params:get("mod") / 4
               end
               FREQ = mult * (BASE_FREQ/div)
               engine.freq(FREQ)


               -- BASE_FREQ = BASE_FREQ / v
               -- FREQ = params:get("mod") * BASE_FREQ/2
               -- engine.freq(FREQ)

               screen_dirty = true
  end}

  params:add{type = "control", id = "sync_phase", name = "sync_phase", min = 0, max = 360, default = 0, formatter = fmt_phase,
             action = function(v)
               local a = util.linlin(0, 360, 0, 2 * math.pi, v)
               engine.syncPhase(a)
               screen_dirty = true
  end}

  params:add{type = "option", id = "index1", name = "index1", options = WAVESHAPES, action = function(v)
               engine.index1(v-1)
               screen_dirty = true
  end}
  params:add{type = "option", id = "index2", name = "index2", options = WAVESHAPES, action = function(v)
               engine.index2(v-1)
               screen_dirty = true
  end}
  params:add{type = "option", id = "index3", name = "index3", options = WAVESHAPES, action = function(v)
               engine.index3(v-1)
               screen_dirty = true
  end}
  params:add{type = "option", id = "index4", name = "index4", options = WAVESHAPES, action = function(v)
               engine.index4(v-1)
               screen_dirty = true
  end}

  params:add{type = "control", id = "cutoff", name = "cutoff", controlspec = ControlSpec.FREQ, formatter = Formatters.format_freq}
  params:set_action("cutoff", function (v)
                      engine.cutoff(v)
  end)

  local moog_res = controlspec.new(0, 4, "lin", 0, 0.0, "")
  params:add{type = "control", id = "res", name = "res", controlspec = moog_res}
  params:set_action("res", function (v)
                      engine.resonance(v)
  end)

  bleached.init(bleached_cc_cb)

  params:bang()

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
        lfo_tick()
      end
  end)

end


-- -------------------------------------------------------------------------
-- controls

function enc(n, d)
  local s = math.abs(d) / d
  if n == 1 then
    params:set("mod", params:get("mod") + s)
  elseif n == 2 then
    params:set("sync_ratio", params:get("sync_ratio") + s)
  end
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
  square = square > 0 and 0.5 or math.floor(square) * 0.5
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
-- LFOs

function lfo_tick()
  local tick = (1 / ROT_FPS) * params:get("npolar_rot_freq") * 2
  rot_angle = rot_angle + tick
  while rot_angle > 1 do
    rot_angle = rot_angle - 1
  end

  local tick_sliced = (1 / ROT_FPS) * params:get("npolar_rot_freq_sliced") * 2
  rot_angle_sliced = rot_angle_sliced + tick_sliced
  while rot_angle_sliced > 1 do
    rot_angle_sliced = rot_angle_sliced - 1
  end

  -- print(rot_angle)
  screen_dirty = true
end


-- -------------------------------------------------------------------------
-- screen

function draw_wave(waveshape, x, w, y, a, sign, dir, segment, nb_segments)
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
    screen.line(i, y + nwave(waveshape, nx) * a * sign * -1)
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

function draw_poles(x, y, radius, nb_poles, amount, rot_angle)
  screen.level(0)
  screen.move(x + radius + 2, y)
  screen.circle(x, y, radius + 2)
  screen.fill()

  screen.level(15)
  screen.move(x + radius, y)
  screen.circle(x, y, radius)
  screen.stroke()

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

NO_CLEAR_COUNT = 0

function redraw()
  local screen_w, screen_h = screen_size()

  if NO_CLEAR_COUNT == 0 or NO_CLEAR_COUNT > 3 then
    screen.clear()
    NO_CLEAR_COUNT = 0
  end
  -- NO_CLEAR_COUNT = NO_CLEAR_COUNT + 1

  local sync_ratio = params:get("sync_ratio") -- nb of sub-segments
  local mod = params:get("mod")
  local mod_sliced = mod * sync_ratio
  local half_waves = mod
  local half_wave_w = util.round(screen_w/(half_waves*2))
  local segment_w = half_wave_w / sync_ratio
  local abscissa = screen_h/2
  local a = abscissa * 3/6

  local sign = 1
  local x_offset = screen_w/2

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
      local wi = math.floor(mod1(i * j, #WAVESHAPES))
      local waveshape = params:string("index"..wi)
      local pole_a = a * (linlin(0, 1, 1, amp_for_pole(i, mod, rot_angle, 1), params:get("npolar_rot_amount")) * linlin(0, 1, 1, amp_for_pole(i*j, mod_sliced, rot_angle_sliced, 1), params:get("npolar_rot_amount_sliced")))
      draw_wave(waveshape, x_offset + (i-1) * half_wave_w, segment_w, abscissa, pole_a, sign, 1, j, sync_ratio)
    end
    sign = sign * -1
  end
  screen.stroke()

  sign = 1
  screen.move(x_offset, abscissa)
  for i=1,half_waves do
    for j=1,sync_ratio do
      local wi = math.floor(mod1(i * j, #WAVESHAPES))
      local waveshape = params:string("index"..wi)
      local pole_a = a * (linlin(0, 1, 1, -amp_for_pole(i, mod, rot_angle, 1, -1), params:get("npolar_rot_amount")) * linlin(0, 1, 1, -amp_for_pole(i*j, mod_sliced, rot_angle_sliced, 1, -1), params:get("npolar_rot_amount_sliced")))
      draw_wave(waveshape, x_offset - (i-1) * half_wave_w, segment_w, abscissa, pole_a, -sign, -1, j, sync_ratio)
    end
    sign = sign * -1
  end
  screen.stroke()

  -- poles

  local p_pargin = 1
  local p_radius = 10
  draw_poles(screen_w-(p_radius+p_pargin)*(2 + 0.3), p_radius+p_pargin, p_radius, params:get("mod"), params:get("npolar_rot_amount"), rot_angle)
  draw_poles(screen_w-(p_radius+p_pargin), p_radius+p_pargin, p_radius, params:get("sync_ratio"), params:get("npolar_rot_amount_sliced"), rot_angle_sliced)

  screen.update()
  screen_dirty = false
end
