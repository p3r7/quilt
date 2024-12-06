
local frequtil = {}


-- -------------------------------------------------------------------------
-- consts

local V_PER_OCTAVE   = 1
local BASE_MIDI_NOTE = 12     -- C0 (0V)
local BASE_FREQ      = 20     -- 0V
local MAX_FREQ       = 20000


-- -------------------------------------------------------------------------
-- volts

function frequtil.volts_to_hz(volts)
  return BASE_FREQ * (2 ^ volts)
end

function frequtil.hz_to_volts(freq)
  return math.log(freq / BASE_FREQ) / math.log(2)
end

function frequtil.midi_note_to_volts(midi_note)
  return (midi_note - BASE_MIDI_NOTE) / 12
end


-- -------------------------------------------------------------------------
-- cutoff computation

function frequtil.instant_cutoff(base_cutoff_hz, cutoff_offness,
                                 key_note, key_track_pct, key_track_neg_offset_pct,
                                 eg, eg_pct)
  local base_cutoff_volts = frequtil.hz_to_volts(base_cutoff_hz)
  local cutoff_offness_volts = cutoff_offness * 10 / 4

  local key_volts = frequtil.midi_note_to_volts(key_note)
  local key_track_neg_offset_volts = key_track_neg_offset_pct * 10
  local eg_volts = eg * 10

  local key_mod_volts = (key_volts - key_track_neg_offset_volts) * key_track_pct
  local eg_mod_volts  = eg_volts  * eg_pct

  local total_volts = base_cutoff_volts + cutoff_offness_volts + key_mod_volts + eg_mod_volts

  local instant_cutoff_hz = frequtil.volts_to_hz(total_volts)

  instant_cutoff_hz = math.max(BASE_FREQ, math.min(instant_cutoff_hz, MAX_FREQ))

  return instant_cutoff_hz
end


-- -------------------------------------------------------------------------

return frequtil
