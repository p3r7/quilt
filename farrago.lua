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

  params:add{type = "number", id = "mod", name = "mod", min = 1, max = 10, default = 3, action = function(v)
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
-- screen

-- TODO: improve
function draw_sin(x1, w, y, a, sign)
  local x2 = x1 + w
  screen.move(x1, y)
  for i=x1,x2 do
    screen.line(i, y + math.sin(util.linlin(x1, x2, 0, math.pi, i)) * a * sign)
  end
end

function draw_tri(x1, w, y, a, sign)
  local x2 = x1 + w
  screen.move(x1, y)
  screen.line((x1 + x2)/2, y+(sign * a))
  screen.line(x2, y)
end

function draw_saw(x1, w, y, a, sign)
  local x2 = x1 + w
  screen.move(x1, y)
  screen.line(x2, y+(sign * a))
  screen.line(x2, y)
end

function draw_sqr(x1, w, y, a, sign)
  local x2 = x1 + w
  screen.move(x1, y)
  screen.line(x1, y+(sign * a))
  screen.line(x2, y+(sign * a))
  screen.line(x2, y)
end

function draw_wave(waveshape, x, w, y, a, sign)
  if waveshape == "SIN" then
    draw_sin(x, w, y, a, sign)
  elseif waveshape == "TRI" then
    draw_tri(x, w, y, a, sign)
  elseif waveshape == "SAW" then
    draw_saw(x, w, y, a, sign)
  elseif waveshape == "SQR" then
    draw_sqr(x, w, y, a, sign)
  end
end

function redraw()
  local screen_w, screen_h = screen_size()

  screen.clear()

  local unique_wave_segments = params:get("mod")
  local wave_segments = unique_wave_segments * 2
  local segment_w = screen_w/wave_segments
  local abscissa = screen_h/2
  local a = abscissa * 3/4

  local sign = 1
  for i=1,wave_segments do
    local waveshape = params:string("index"..mod1(i, #WAVESHAPES))
    draw_wave(waveshape, (i-1) * segment_w, segment_w, abscissa, a, sign)
    sign = sign * -1
  end
  screen.stroke()

  screen.update()
  screen_dirty = false
end
