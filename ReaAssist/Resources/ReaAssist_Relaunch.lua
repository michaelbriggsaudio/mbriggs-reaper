-- ReaAssist_Relaunch.lua
-- -----------------------
-- Marker: CFG.VERSION (consumed by Updater post-download integrity check
-- in ReaAssist.lua; required literal string for any .lua file in the
-- manifest, do not remove).
--
-- Tiny helper that re-fires ReaAssist.lua after the running instance
-- has exited. Invoked by Updater.try_auto_restart in ReaAssist.lua
-- when an auto-update or repair finishes and the script needs to
-- relaunch itself to load the new files.
--
-- Why this exists:
--   reaper.Main_OnCommand on ReaAssist's own command id, fired from
--   inside ReaAssist's still-running defer chain, is intercepted by
--   REAPER's action-system re-entrance handling. The single-instance
--   handshake at the top of ReaAssist.lua interprets the re-entrance
--   as a toggle-off and exits the new instance immediately. Net effect:
--   ReaAssist closes and nothing relaunches.
--
-- How it works:
--   1. Main ReaAssist fires this helper via Main_OnCommand (one action
--      firing a DIFFERENT action, so no re-entrance) then closes its
--      own window via S.script_open = false.
--   2. This helper polls the "running" ExtState in a defer loop until
--      the old ReaAssist's cleanup path (or atexit) clears it.
--   3. A small 0.25s grace window lets REAPER finish tearing down the
--      old action's state -- matches the successful pattern used by
--      Dev/ReaAssist_Debug_Helper.lua's Restart Plugin button.
--   4. The helper re-registers ReaAssist (idempotent if already known,
--      returns the same cmd_id) and fires Main_OnCommand on it from
--      this separate script context. REAPER reads that as a fresh
--      launch of an action that is not currently running.
--   5. The helper's defer chain ends and it exits.
--
-- Safety bounds:
--   - MAX_WAIT caps the polling loop so a pathologically stuck close
--     (or the user cancelling) cannot keep this helper deferring for
--     ever. At 10s elapsed with "running" still live, the helper gives
--     up; the user is left with a closed ReaAssist they can relaunch
--     by hand. This is the same failure mode as CMD_ID == 0 in the
--     main script (launched via "Load ReaScript..." rather than an
--     installed action), which is already documented in the repair
--     popup's "Close and reopen ReaAssist" copy.

local EXT_NS        = "reaassist"
local GRACE_S       = 0.25  -- wait after "running" clears before launching
local MAX_WAIT_S    = 10    -- abort if the old instance never exits

-- Resolve the sibling ReaAssist.lua path without depending on any
-- main-script globals (this file runs in its own Lua state). Avoid
-- `..` in the constructed path: REAPER's action registry stores the
-- exact path string, so `.../ReaAssist/Resources/../ReaAssist.lua`
-- registers as a DIFFERENT action than `.../ReaAssist/ReaAssist.lua`
-- even though they point at the same file, and every auto-restart
-- cycle would add a new duplicate entry to the user's Actions list.
-- Walk up one directory by trimming the last path segment instead.
local script_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*[\\/])")
local parent_dir = script_dir:gsub("[^\\/]+[\\/]$", "")
local REAASSIST_PATH = parent_dir .. "ReaAssist.lua"

local start_t     = reaper.time_precise()
local cleared_at  = nil
local launched    = false

local function tick()
  local now = reaper.time_precise()

  if launched then return end

  if (now - start_t) > MAX_WAIT_S then
    -- Gave up waiting; exit without relaunching.
    return
  end

  local running = reaper.GetExtState(EXT_NS, "running")
  if running == "" then
    cleared_at = cleared_at or now
    if (now - cleared_at) >= GRACE_S then
      launched = true
      -- Re-register ReaAssist as a REAPER action (idempotent: returns
      -- the existing cmd_id if the script is already known). commit
      -- true so the registration survives REAPER's next start, which
      -- is where the user's permanent toolbar button is anchored.
      local cmd_id = reaper.AddRemoveReaScript(true, 0, REAASSIST_PATH, true)
      if cmd_id and cmd_id ~= 0 then
        reaper.Main_OnCommand(cmd_id, 0)
      end
      return  -- no further defer; script exits
    end
  else
    -- Old instance still holds its lock; reset the grace timer so the
    -- 0.25s window is measured from when "running" first disappears.
    cleared_at = nil
  end

  reaper.defer(tick)
end

tick()
