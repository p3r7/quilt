local voiceutils = {}


-- -------------------------------------------------------------------------
-- deps

local MusicUtil = require "musicutil"

include("lib/consts")


-- -------------------------------------------------------------------------
-- notes

function voiceutils.note_on(STATE, note_num, vel)
  local note_id, voice_ids = voiceutils.allocate_voice(STATE, note_num)
  local hz = MusicUtil.note_num_to_freq(note_num)

  print("------")
  print("alloc: ")
  tab.print(voice_ids)

  local main_voice_id = voice_ids[1]

  for i, voice_id in pairs(voice_ids) do
    local leader_id = nil
    if i > 1 then
      leader_id = main_voice_id
    end
    voiceutils.voice_on(STATE, voice_id, hz, vel, leader_id)
  end

  STATE.nb_active_meta_voices = STATE.nb_active_meta_voices+1
end

function voiceutils.note_off(STATE, note_num)
  local note_id, voice_ids = voiceutils.unallocate_voice(STATE, note_num)

  print("------")
  print("unalloc: ")
  tab.print(voice_ids)

  for _, voice_id in pairs(voice_ids) do
    voiceutils.voice_off(STATE, voice_id)
  end

  STATE.nb_active_meta_voices = STATE.nb_active_meta_voices-1
end


-- -------------------------------------------------------------------------
-- voices

-- REVIEW: store note_id so that we can remove voice from STATE.note_id_voice_map when dimnishing binaurality!

function voiceutils.voice_on(STATE, voice_id, hz, vel, leader_id)
  local was_active = STATE.voices[voice_id].active
  STATE.voices[voice_id].active = true
  STATE.voices[voice_id].hz = hz
  STATE.voices[voice_id].vel = vel
  STATE.voices[voice_id].paired_leader = leader_id
  engine.noteOn(voice_id, hz, vel)
  if not was_active then
    STATE.nb_active_voices = STATE.nb_active_voices + 1
  end
end

function voiceutils.voice_off(STATE, voice_id)
  if not STATE.voices[voice_id].active then
    return
  end
  STATE.voices[voice_id].active = false
  STATE.voices[voice_id].vel = 0
  STATE.voices[voice_id].paired_leader = nil
  engine.noteOff(voice_id)
  STATE.nb_active_voices = STATE.nb_active_voices - 1
end


-- -------------------------------------------------------------------------
-- meta-voices

function voiceutils.nb_active_same_note(STATE, note_id)
  local count = 0
  for vnote_id, voice_ids in pairs(STATE.note_id_voice_map) do
    -- print(vnote_id .. " VS " .. note_id)
    if (vnote_id % 1000) == (note_id % 1000) then
      count = count + 1
    end
  end
  return count
end

-- REVIEW: maybe only pair odd/even voices (left/right pan)?
function voiceutils.get_free_follower(STATE, voice_id)
  local max_tries = NB_VOICES
  local paired_voice_id = mod1(voice_id+1, params:get("voice_count"))
  local try = 1
  while STATE.voices[paired_voice_id].active do
    if try > params:get("voice_count") then
      paired_voice_id = nil
      -- break
    end
    paired_voice_id = mod1(paired_voice_id+1, params:get("voice_count"))
    try = try + 1
  end
  return paired_voice_id
end

function voiceutils.get_follower_maybe(STATE, voice_id)
  if STATE.voices[voice_id].leader_id then
    return
  end

  if STATE.nb_active_meta_voices < STATE.nb_dual_meta_voices
    and STATE.nb_active_voices < params:get("voice_count") then
    print("yes")
    return voiceutils.get_free_follower(STATE, voice_id)
  end
end


-- -------------------------------------------------------------------------
-- allocation - meta voice

function voiceutils.allocate_voice(STATE, note_num)
  local allocated_voice_ids = {}

  print("------")
  print("pre-alloc: ")
  print(STATE.curr_voice_id)

  STATE.curr_voice_id = STATE.next_voice_id;
  table.insert(allocated_voice_ids, STATE.curr_voice_id)

  local id_prefix = voiceutils.nb_active_same_note(STATE, note_num) + 1
  local note_id = id_prefix * 1000 + note_num

  local follower_id = voiceutils.get_follower_maybe(STATE, STATE.curr_voice_id)
  if follower_id then
    -- print("-> pair! " .. follower_id)
    table.insert(allocated_voice_ids, follower_id)
    STATE.next_voice_id = mod1(follower_id+1, params:get("voice_count"))
  else
    STATE.next_voice_id = mod1(STATE.curr_voice_id+1, params:get("voice_count"))
  end

  STATE.note_id_voice_map[note_id] = allocated_voice_ids

  -- if paired_voices[STATE.curr_voice_id] then
  --   print("-> pair!")
  --   table.insert(allocated_voice_ids, paired_voices[STATE.curr_voice_id])
  --   print("   "..paired_voices[STATE.curr_voice_id])

  --   STATE.next_voice_id = mod1(STATE.next_voice_id+1, params:get("voice_count"))
  -- end


  -- while paired_voices[STATE.curr_voice_id] ~= nil do
  -- STATE.next_voice_id = mod1(STATE.next_voice_id+1, params:get("voice_count"))
  -- end

  return note_id, allocated_voice_ids
end

function voiceutils.unallocate_voice(STATE, note_num)
  local id_prefix = voiceutils.nb_active_same_note(STATE, note_num)
  print("id_prefix="..id_prefix)
  local note_id = id_prefix * 1000 + note_num
  print("note_id="..note_id)

  local voice_ids = STATE.note_id_voice_map[note_id]
  if voice_ids == nil then
    print("crap")
    return note_id, {}
  end

  -- -- REVIEW: this is bad
  -- if voices[voice_id].paired_leader then
  --   table.insert(unallocated_voice_ids, voices[voice_id].paired_leader)
  -- else
  --   for i=1,NB_VOICES do
  --     if voices[i].paired_leader == voice_id then
  --       table.insert(unallocated_voice_ids, voices[i].paired_leader)
  --     end
  --   end
  -- end

  STATE.note_id_voice_map[note_id] = nil

  return note_id, voice_ids
end


-- -------------------------------------------------------------------------

function voiceutils.enforce_associated_voices(STATE, leader_id, follower_id)
  if STATE.voices[leader_id].active and not STATE.voices[follower_id].active then
    local hz = STATE.voices[leader_id].hz
    local vel = STATE.voices[leader_id].vel
    voiceutils.voice_on(STATE, follower_id, hz, vel, leader_id)
  end
end

function voiceutils.enforce_associated_voices_flex(STATE, a_id, b_id)
  if STATE.voices[a_id].active and not STATE.voices[b_id].active then
    voiceutils.enforce_associated_voices(STATE, a_id, b_id)
  elseif STATE.voices[b_id].active and not STATE.voices[a_id].active then
    voiceutils.enforce_associated_voices(STATE, b_id, a_id)
  end
end


-- -------------------------------------------------------------------------

return voiceutils
