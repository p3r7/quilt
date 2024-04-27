-- farrago.
-- @eigen


-- -------------------------------------------------------------------------
-- deps

local ControlSpec = require "controlspec"
local Formatters = require "formatters"
local MusicUtil = require "musicutil"

include("lib/core")

engine.name = "Farrago"


-- -------------------------------------------------------------------------
-- consts

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



-- -------------------------------------------------------------------------
-- state

screen_dirty = true


-- -------------------------------------------------------------------------
-- init

local clock_redraw

function init()

  if norns then
    screen.aa(1)
  end

  local pct_control_on = controlspec.new(0, 1, "lin", 0, 1.0, "")

  params:add{type = "number", id = "mod", name = "mod", min = 2, max = 15, default = 3, action = function(v)
               engine.mod(v)
               screen_dirty = true
  end}

  params:add{type = "number", id = "sync_ratio", name = "sync_ratio", min = 1, max = 10, default = 1, action = function(v)
               engine.syncRatio(v)
               screen_dirty = true
  end}

  params:add{type = "number", id = "sync_phase", name = "sync_phase", min = 0.0, max = 2 * math.pi, default = 0.0, action = function(v)
               engine.syncPhase(v)
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


  clock_redraw = clock.run(function()
      while true do
        clock.sleep(1/FPS)
        if screen_dirty then
          redraw()
        end
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

-- -------------------------------------------------------------------------
-- screen

function draw_sin(x, w, y, a, sign, dir, segment, nb_segments)
  local half_wave_w = w * nb_segments
  local w_offset = util.linlin(1, nb_segments+1, 0, half_wave_w, segment)

  local x0 = x
  local xn = x0 + dir * half_wave_w
  local x1 = x0 + dir * w_offset
  local x2 = x1 + dir * w

  -- print("--------------")
  -- print(segment .. "/" .. nb_segments .. ": " .. x0 .." .. " .. xn .. ", " .. x .. " -> " .. x1 .." .. " .. x2)
  -- print("w="..half_wave_w.." -> "..w)

  -- screen.move(x1, y)
  for i=x1,x2,dir do
    -- print("a="..linlin(x0, xn, 0, math.pi, i))
    screen.line(i, y + math.sin(linlin(x0, xn, 0, math.pi, i)) * a * sign * dir)
  end
end

function draw_saw(x1, w, y, a, sign, dir, segment, nb_segments)
  local x2 = x1 + dir * w
  screen.move(x1, y)
  screen.line(x2, y+(sign * a))
  screen.line(x2, y)
end

function draw_tri(x1, w, y, a, sign, dir, segment, nb_segments)
  local x2 = x1 + dir * w
  screen.move(x1, y)
  screen.line((x1 + x2)/2, y+(sign * a))
  screen.line(x2, y)
end

function draw_sqr(x1, w, y, a, sign, dir, segment, nb_segments)
  local x2 = x1 + dir * w
  screen.move(x1, y)
  screen.line(x1, y+(sign * a))
  screen.line(x2, y+(sign * a))
  screen.line(x2, y)
end

function draw_wave(waveshape, x, w, y, a, sign, dir, segment, nb_segments)
  if dir == nil then
    dir = 1
  end
  if waveshape == "SIN" then
    draw_sin(x, w, y, a, sign, dir, segment, nb_segments)
  elseif waveshape == "TRI" then
    draw_tri(x, w, y, a, sign, dir, segment, nb_segments)
  elseif waveshape == "SAW" then
    draw_saw(x, w, y, a, sign, dir, segment, nb_segments)
  elseif waveshape == "SQR" then
    draw_sqr(x, w, y, a, sign, dir, segment, nb_segments)
  end
end

function draw_mod_wave(x, w, y, a, sign, dir)
  screen.level(5)
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

function draw_poles(x, y, radius, nb_poles)
  screen.move(x + radius, y)
  screen.circle(x, y, radius)
  screen.stroke()

  for i=1, nb_poles do
    screen.move(x, y)
    local angle = (i-1) * 2 * math.pi / nb_poles
    local angle2 = angle/(2 * math.pi)
    screen.line(x + radius * cos(angle2) * -1, y + radius * sin(angle2))
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

function redraw()
  local screen_w, screen_h = screen_size()

  screen.clear()

  -- draw_scope_grid(screen_w, screen_h)

  local sync_ratio = params:get("sync_ratio") -- nb of sub-segments
  local half_waves = params:get("mod")
  local half_wave_w = util.round(screen_w/(half_waves*2))
  local segment_w = half_wave_w / sync_ratio
  local abscissa = screen_h/2
  local a = abscissa * 3/6

  local sign = 1
  local x_offset = screen_w/2

  -- -- mod wave
  -- for i=1,half_waves do
  --   draw_mod_wave(x_offset + (i-1) * half_wave_w, half_wave_w, abscissa, a, sign)
  --   sign = sign * -1
  -- end

  -- for i=1,half_waves do
  --   draw_mod_wave(x_offset - (i-1) * half_wave_w, half_wave_w, abscissa, a, -sign, -1)
  --   sign = sign * -1
  -- end

  -- signal wave
  sign = 1
  screen.move(x_offset, abscissa)
  for i=1,half_waves do
    for j=1,sync_ratio do
      local wi = math.floor(mod1(i * j, #WAVESHAPES))
      local waveshape = params:string("index"..wi)
      draw_wave(waveshape, x_offset + (i-1) * half_wave_w, segment_w, abscissa, a, sign, 1, j, sync_ratio)
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
      draw_wave(waveshape, x_offset - (i-1) * half_wave_w, segment_w, abscissa, a, -sign, -1, j, sync_ratio)
    end
    sign = sign * -1
  end
  screen.stroke()

  -- poles

  local p_pargin = 1
  local p_radius = 10
  draw_poles(screen_w-(p_radius+p_pargin), p_radius+p_pargin, p_radius, params:get("mod"))

  screen.update()
  screen_dirty = false
end
