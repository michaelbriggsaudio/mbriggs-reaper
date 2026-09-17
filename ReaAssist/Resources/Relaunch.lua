-- Relaunch.lua
-- -----------------------
-- Marker: CFG.VERSION (consumed by Updater post-download integrity check
-- in ReaAssist.lua; required literal string for any .lua file in the
-- manifest, do not remove).
--
-- Tiny helper that re-fires the root action after the running instance
-- has exited. Invoked by Updater.try_auto_restart in ReaAssist.lua
-- when an auto-update or repair finishes and the script needs to
-- relaunch itself to load the new files.
-- Updates supply a one-time relaunch_mode request. Its owner must match the
-- running instance or have already closed. Older callers with no mode request
-- reopen the standard action after closing, as approved for historical updates.
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
--      old action's state. Empirically chosen and validated against
--      our internal restart tooling.
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

-- Consume the one-time request before any layout or restart refusal. An
-- already closed caller has no running marker; a different owner is refused.
local request = reaper.GetExtState(EXT_NS, "relaunch_mode")
reaper.DeleteExtState(EXT_NS, "relaunch_mode", false)
local request_owner, request_mode = request:match("^([^|]+)|([a-z]+)$")
if request_mode ~= "sr" and request_mode ~= "standard" then request_owner = nil end
local screen_reader = request_owner ~= nil and request_mode == "sr"
local foreign_owner = false
if request_owner then
  local running = reaper.GetExtState(EXT_NS, "running")
  foreign_owner = running ~= "" and running:match("^([^|]+)|") ~= request_owner
end

-- Resolve the ReaAssist entrypoint without depending on any main-script
-- globals (this file runs in its own Lua state). Avoid `..` in the
-- constructed path: REAPER's action registry stores the exact path string,
-- so `.../ReaAssist/Resources/../ReaAssist.lua` registers as a DIFFERENT
-- action than `.../ReaAssist/ReaAssist.lua` even though they point at the
-- same file, and every auto-restart cycle would add a new duplicate entry to
-- the user's Actions list. Walk up by trimming the last path segment instead.
--
-- What gets fired has to be the shipped entrypoint, which is the launcher at
-- the package root, not the body beside this file. Firing the body directly
-- would restart the application with no journal resolution and no
-- completeness check in front of it, which is the one thing the launcher
-- exists to guarantee, and it would register a second action at a path
-- ReaPack does not own.
--
-- This file ships as Resources/Relaunch.lua, so its parent is the app root.
-- Decision 10a.1 makes that App/, one below the package root; a
-- pre-restructure install has the two the same and the walk stops after one
-- step. Structural, so both layouts take the same path through this code.
--
-- The App segment is stripped only when the directory above really is a
-- package root, proven by a marker-verified permanent launcher being in it. A
-- flat install that happens to live in a directory called App would otherwise
-- send this helper up a level to fire whatever ReaAssist.lua it found there.
-- A launcher is decided by a marker in its header rather than by its name,
-- because a name is not evidence. Local copy of the rule; the master copy is
-- RA.holds_launcher / RA.package_dir_for in ReaAssist.lua.
--
-- **This file does not share the master's fallback, and that is the point.**
-- Everywhere else, an App-spelled directory with nothing provable above it
-- resolves flat, because flat keeps every path inside the folder the body is
-- in and that is the safe direction for a path. Here the safe direction is the
-- other one. Resolving flat means firing App/ReaAssist.lua, which is the body:
-- it starts with no journal resolution and no completeness check in front of
-- it, which is the one thing the launcher exists to guarantee, and it
-- registers a second action at a path ReaPack does not own. A two-level
-- install that has lost both launchers has exactly that shape, and it is
-- indistinguishable from a flat install in a folder called App. So this helper
-- refuses rather than guessing, and the user is told to reopen ReaAssist from
-- the Action List, which is the same route every other failure here offers.
-- A genuine flat install has no App segment at all and is untouched by any of
-- this.
local script_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*[\\/])")
local app_dir = script_dir:gsub("[^\\/]+[\\/]$", "")
local function holds_launcher(dir)
  if type(dir) ~= "string" or dir == "" then return false end
  -- Two halves on purpose. This file is not one a probe opens, but the rule is
  -- copied verbatim between all five call sites and one of them is. Do not
  -- join them.
  local marker = "The shipped path is an action identity"
    .. " and can never move"
  for _, name in ipairs({ "ReaAssist.lua",
                          "ReaAssist_Screen_Reader_Mode.lua" }) do
    local f = io.open(dir .. name, "rb")
    if f then
      local head = f:read(4096)
      f:close()
      if head and head:find(marker, 1, true) then return true end
    end
  end
  return false
end
local package_dir = app_dir
local unresolved_layout = false
do
  local parent, leaf = app_dir:match("^(.*[\\/])([^\\/]+)[\\/]$")
  if leaf == "App" then
    if parent and holds_launcher(parent) then
      package_dir = parent
    else
      unresolved_layout = true
    end
  end
end
local REAASSIST_PATH = (not unresolved_layout) and (package_dir ..
  (screen_reader and "ReaAssist_Screen_Reader_Mode.lua" or "ReaAssist.lua")) or nil

local start_t     = reaper.time_precise()
local cleared_at  = nil
local launched    = false
local notified    = false

local function say(msg)
  if reaper and type(reaper.osara_outputMessage) == "function" then
    pcall(reaper.osara_outputMessage, msg)
  end
  if reaper and type(reaper.ShowMessageBox) == "function" then
    reaper.ShowMessageBox(msg, "ReaAssist", 0)
  elseif reaper and type(reaper.MB) == "function" then
    reaper.MB(msg, "ReaAssist", 0)
  end
end

local function notify_manual_reopen()
  if notified then return end
  notified = true
  say("ReaAssist could not finish its automatic restart.\n\n" ..
    "Close and reopen ReaAssist manually from REAPER's Action List.")
end

-- The refusal. Same vocabulary as the guard above, because it is the same
-- instruction: ReaAssist is closed and the user reopens it themselves. What
-- differs is the reason, and it is worth saying plainly rather than reporting
-- a restart that "did not finish", because nothing was attempted.
local function notify_unresolved_layout()
  if notified then return end
  notified = true
  say("ReaAssist could not restart itself, because it could not tell which "
    .. "ReaAssist entry point belongs to this installation.\n\n"
    .. "Open ReaAssist again from REAPER's Action List. If it does not open, "
    .. "reinstall from https://reaassist.app")
end

local function tick()
  local now = reaper.time_precise()

  if launched then return end

  if (now - start_t) > MAX_WAIT_S then
    -- Gave up waiting; exit without relaunching.
    notify_manual_reopen()
    return
  end

  local running = reaper.GetExtState(EXT_NS, "running")
  if running == "" then
    cleared_at = cleared_at or now
    if (now - cleared_at) >= GRACE_S then
      launched = true
      if not request_owner and request ~= "" then
        notified = true
        say("ReaAssist has closed. Open ReaAssist again to continue.")
        return
      end
      local target = io.open(REAASSIST_PATH, "rb")
      if not target then
        notify_manual_reopen()
        return
      end
      target:close()
      -- Re-register ReaAssist as a REAPER action (idempotent: returns
      -- the existing cmd_id if the script is already known). commit
      -- true so the registration survives REAPER's next start, which
      -- is where the user's permanent toolbar button is anchored.
      local registered, cmd_id = pcall(reaper.AddRemoveReaScript, true, 0, REAASSIST_PATH, true)
      if registered and cmd_id and cmd_id ~= 0 then
        if not pcall(reaper.Main_OnCommand, cmd_id, 0) then notify_manual_reopen() end
      else
        notify_manual_reopen()
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

-- Nothing is fired and no defer chain is started when the layout could not be
-- resolved. The wait loop exists to fire one action, so a run that has no
-- action to fire says so now rather than after ten seconds of polling.
if foreign_owner then
  notify_manual_reopen()
elseif REAASSIST_PATH then
  tick()
else
  notify_unresolved_layout()
end
