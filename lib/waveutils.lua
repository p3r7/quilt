local waveutils = {}


-- -------------------------------------------------------------------------
-- deps

include("lib/consts")


-- -------------------------------------------------------------------------
-- freq / period calculation

function waveutils.effective_period(poles)
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

function waveutils.get_effective_freq(freq, mod)
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

  local effective_period, effective_freq

  effective_period = waveutils.effective_period(poles)
  if effective_period > mod then
    effective_period = effective_period / 4.3
  end
  -- print("effective_period="..effective_period)

  effective_freq = freq * 2 / effective_period

  return effective_period, effective_freq
end

function waveutils.compensated_freq(STATE, freq, mod)
  local effective_period, effective_freq = waveutils.get_effective_freq(freq, mod)

  local div = 1
  if STATE.PITCH_COMPENSATION_SYNC then
    div = params:get("sync_ratio")/4
  end

  local mult = 1
  if STATE.PITCH_COMPENSATION_MOD then
    mult = STATE.effective_period/2
  end

  local compensated_freq = mult * (freq/div)
  return compensated_freq
end

-- -------------------------------------------------------------------------

return waveutils
