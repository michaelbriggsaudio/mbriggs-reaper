-- ============================================================================
-- launcher_template_sr.lua - the source of the Screen Reader entrypoint
-- ============================================================================
--
-- gen_launchers.lua copies this to Dev/Launcher/build/
-- ReaAssist_Screen_Reader_Mode.lua unchanged. There is nothing to embed:
-- decision 10a.4 has this entrypoint set its mode flag and delegate to the
-- standard launcher beside it, so one copy of the engine exists on disk and a
-- ReaPack sync that commits the two files in either order still lands a
-- coherent pair.
--
-- The shipped path is an action identity and can never move:
--
--   Scripts/mbriggs-reaper/ReaAssist/ReaAssist_Screen_Reader_Mode.lua
--
-- CFG.VERSION compatibility marker: required by pre-1.5 updater verification.
--
-- The ruled fallback is the rest of this file. When the sibling launcher is
-- not there, or is there and will not load, this says so in a native dialog
-- AND through OSARA and tells the user how to get it back. It never fails
-- silently, because a Screen Reader user who presses an action and hears
-- nothing has no way to find out why.
-- ============================================================================

local TITLE = "ReaAssist - Screen Reader Mode"
local SIBLING = "ReaAssist.lua"
local HOME_REL = "Scripts/mbriggs-reaper/ReaAssist/"

local sep = package.config:sub(1, 1)

local function announce(text)
  if reaper.osara_outputMessage then
    pcall(reaper.osara_outputMessage, TITLE .. ": " .. text)
  end
end

local function tell(short, long)
  -- Speech first. reaper.MB blocks until the user dismisses it, and a screen
  -- reader user needs to know what the dialog is before it takes the focus.
  announce(short)
  pcall(reaper.MB, long, TITLE, 0)
end

local function exists(path)
  local f = path and io.open(path, "rb") or nil
  if not f then return false end
  f:close()
  return true
end

-- Beside this file first, because that is what "the sibling launcher" means
-- and it survives an install that is not under the resource folder. The
-- resource path is the backstop for a REAPER build that does not hand a script
-- its own filename.
local function sibling_path()
  local ok, _, filename = pcall(reaper.get_action_context)
  if ok and type(filename) == "string" and filename ~= "" then
    local dir = filename:match("^(.*[\\/])")
    if dir then return dir .. SIBLING end
  end
  local resource = reaper.GetResourcePath()
  if type(resource) == "string" and resource ~= "" then
    return resource .. sep .. (HOME_REL .. SIBLING):gsub("/", sep)
  end
  return nil
end

local path = sibling_path()

if not path or not exists(path) then
  tell(
    "The main ReaAssist file is missing, so Screen Reader Mode cannot start.",
    "ReaAssist Screen Reader Mode could not start, because the main ReaAssist "
    .. "file is missing.\n\nOpen ReaPack, choose Synchronize packages, and let "
    .. "it put ReaAssist back. If ReaAssist was installed from the website, "
    .. "reinstall it from https://reaassist.app\n\nExpected file:\n"
    .. tostring(path or "unknown"))
  return
end

local chunk, err = loadfile(path)
if not chunk then
  tell(
    "The main ReaAssist file is damaged, so Screen Reader Mode cannot start.",
    "ReaAssist Screen Reader Mode could not start, because the main ReaAssist "
    .. "file would not load.\n\nOpen ReaPack, choose Synchronize packages, and "
    .. "let it put ReaAssist back. If ReaAssist was installed from the "
    .. "website, reinstall it from https://reaassist.app\n\nFile:\n"
    .. tostring(path) .. "\n\nDetail: " .. tostring(err))
  return
end

-- The flag the standard launcher reads and clears on its first lines. Set
-- immediately before the call so nothing else can be running between the two.
rawset(_G, "ReaAssist_LAUNCHER_MODE", "sr")
chunk()
