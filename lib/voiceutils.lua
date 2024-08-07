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
    voiceutils.voice_on(STATE, voice_id, hz, vel, note_id, leader_id)
  end

  if #voice_ids > 1 then
    STATE.nb_active_dual_voices = STATE.nb_active_dual_voices + 1
  end
  STATE.nb_active_meta_voices = STATE.nb_active_meta_voices + 1
  voiceutils.recompute_next_voice(STATE)
end

function voiceutils.note_off(STATE, note_num)
  local note_id, voice_ids = voiceutils.unallocate_voice(STATE, note_num)

  print("------")
  print("unalloc: ")
  tab.print(voice_ids)

  for _, voice_id in pairs(voice_ids) do
    voiceutils.voice_off(STATE, voice_id)
  end

  if #voice_ids > 1 then
    STATE.nb_active_dual_voices = STATE.nb_active_dual_voices - 1
  end
  STATE.nb_active_meta_voices = STATE.nb_active_meta_voices - 1
  voiceutils.recompute_next_voice(STATE)
end


-- -------------------------------------------------------------------------
-- voices

-- REVIEW: use stored note_id so that we can remove voice from STATE.note_id_voice_map when dimnishing binaurality!

function voiceutils.voice_on(STATE, voice_id, hz, vel, note_id, leader_id)
  local was_active = STATE.voices[voice_id].active
  STATE.voices[voice_id].active = true
  STATE.voices[voice_id].hz = hz
  STATE.voices[voice_id].vel = vel
  STATE.voices[voice_id].note_id = note_id
  if leader_id then
    STATE.voices[voice_id].is_leader = false
    STATE.voices[voice_id].paired_leader = leader_id
    STATE.voices[leader_id].is_leader = true
    STATE.voices[leader_id].paired_follower = voice_id
  else
    STATE.voices[voice_id].is_leader = true
  end
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
  STATE.voices[voice_id].is_leader = false
  STATE.voices[voice_id].paired_leader = nil
  STATE.voices[voice_id].paired_follower = nil
  STATE.voices[voice_id].note_id = nil
  engine.noteOff(voice_id)
  STATE.nb_active_voices = STATE.nb_active_voices - 1
end


-- -------------------------------------------------------------------------
-- free follower voices

function voiceutils.get_free_follower_voice(STATE, leader_voice_id)
  local voice_count = NB_VOICES

  -- prioritize assigning neighbor voice if free
  if (leader_voice_id % 2 == 0) then -- even
    if not STATE.voices[leader_voice_id-1].active then
      return leader_voice_id-1
    end
  else -- odd
    if leader_voice_id+1 <= voice_count and not STATE.voices[leader_voice_id+1].active then
      return leader_voice_id+1
    end
  end

  return voiceutils.get_next_free_voice(STATE, STATE.next_voice_id, 2)
end


-- -------------------------------------------------------------------------
-- free voices

function voiceutils.get_next_free_voice(STATE, next_voice_id, step)
  -- TODO: tweak this to support when reducing polyphony
  -- local voice_count = params:get("voice_count")
  local voice_count = NB_VOICES

  if not step then
    step = 1
  end

  -- there is no free voice next, so we'll do voice stealing on the pre-computed voice
  if STATE.nb_active_voices >= voice_count then
      return next_voice_id
  end

  -- there is at least one free voice, move to it!
  local max_tries = voice_count
  local try = 0
  while STATE.voices[next_voice_id].active do
    next_voice_id = mod1(next_voice_id+step, voice_count)
    try = try + 1
    if try > voice_count/step then
      print("!!!!!!! ERROR !!!!!!! - reach max voice alloc attempts. this is a bug.")
      return nil
    end
  end

  return next_voice_id
end


function voiceutils.recompute_next_voice(STATE)
  -- pre-computed next voice is free, everything is good
  if not STATE.voices[STATE.next_voice_id].active then
    return
  end

  -- there is no free voice next, so we'll do voice stealing on the pre-computed voice
  if STATE.nb_active_voices >= params:get("voice_count") then
    return
  end

  -- move to next free voice
  local next_voice_id = voiceutils.get_next_free_voice(STATE, STATE.next_voice_id)
  if next_voice_id then
    STATE.next_voice_id = next_voice_id
  end
end


-- -------------------------------------------------------------------------
-- meta-voices

function voiceutils.some_voices_need_pair(STATE)
  return ( STATE.nb_active_dual_voices < STATE.nb_dual_meta_voices
           and STATE.nb_active_voices < STATE.nb_active_meta_voices * 2)
end

function voiceutils.some_voices_need_unpair(STATE)
  return ( STATE.nb_active_dual_voices > STATE.nb_dual_meta_voices )
end

function voiceutils.is_solo_leader(STATE, voice_id)
  return ( voices[voice_id].active
           and voices[voice_id].is_leader
           and not voices[voice_id].paired_follower )
end

function voiceutils.is_paired_leader(STATE, voice_id)
  return ( voices[voice_id].active
           and voices[voice_id].is_leader
           and voices[voice_id].paired_follower )
end

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
  if STATE.voices[voice_id].paired_leader then
    return
  end

  if STATE.nb_active_meta_voices < STATE.nb_dual_meta_voices
    and STATE.nb_active_voices < params:get("voice_count") then
    -- print("yes")
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

function voiceutils.pair_voices(STATE, leader_id, follower_id)
  if STATE.voices[leader_id].active and not STATE.voices[follower_id].active then
    local hz = STATE.voices[leader_id].hz
    local vel = STATE.voices[leader_id].vel
    local note_id = STATE.voices[leader_id].note_id
    voiceutils.voice_on(STATE, follower_id, hz, vel, note_id, leader_id)
    -- REVIEW: this might not be the best spot for this?
    STATE.note_id_voice_map[note_id] = {leader_id, follower_id}
    STATE.nb_active_dual_voices = STATE.nb_active_dual_voices + 1
  end
end

function voiceutils.unpair_follower_voices(STATE, leader_id)
  local follower_id = STATE.voices[leader_id].paired_follower
  if not follower_id then
    return
  end

  local note_id = STATE.voices[leader_id].note_id

  STATE.voices[leader_id].paired_follower = nil
  STATE.voices[follower_id].paired_leader = nil
  voiceutils.voice_off(STATE, follower_id)

  -- REVIEW: this might not be the best spot for this?
  STATE.note_id_voice_map[note_id] = {leader_id}
  STATE.nb_active_dual_voices = STATE.nb_active_dual_voices - 1
end

function voiceutils.pair_voices_flex(STATE, a_id, b_id)
  if STATE.voices[a_id].active and not STATE.voices[b_id].active then
    voiceutils.enforce_associated_voices(STATE, a_id, b_id)
  elseif STATE.voices[b_id].active and not STATE.voices[a_id].active then
    voiceutils.enforce_associated_voices(STATE, b_id, a_id)
  end
end


-- -------------------------------------------------------------------------

return voiceutils
