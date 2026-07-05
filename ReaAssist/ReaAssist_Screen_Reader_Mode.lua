-- @description ReaAssist - Screen Reader Mode
-- @author Michael Briggs
-- @version 1.4.2
-- @about
--   Accessible ReaAssist entry point for screen-reader users.
-- CFG.VERSION marker: do not remove; website installers verify this file.

local sep = package.config:sub(1, 1)
local title = "ReaAssist - Screen Reader Mode"
local ext_ns = "reaassist"
local osara_url = "https://osara.reaperaccessibility.com/snapshots/"
local reagirl_url = "https://reaassist.app/vendor/reagirl/1.3/reagirl.lua"
local reagirl_sha256 =
  "0c2ab56c38cd8613430c78f920ad8246b28de37e134a750a51d7161b10cf6fdf"
local reagirl_min_bytes = 1000000
local reagirl_max_bytes = 2 * 1024 * 1024
local reagirl_timeout = 120
local _, script_path = reaper.get_action_context()

local function is_native_reaper_function(fn)
  if type(fn) ~= "function" then return false end
  local ok, info = pcall(debug.getinfo, fn, "S")
  return ok and info and info.what == "C"
end

if is_native_reaper_function(reaper.JS_Dialog_BrowseForSaveFile) then
  reaper.ReaAssist_Native_JS_Dialog_BrowseForSaveFile =
    reaper.JS_Dialog_BrowseForSaveFile
elseif not is_native_reaper_function(
    reaper.ReaAssist_Native_JS_Dialog_BrowseForSaveFile) then
  reaper.ReaAssist_Native_JS_Dialog_BrowseForSaveFile = nil
end

local function file_exists(path)
  local f = path and io.open(path, "rb") or nil
  if not f then return false end
  f:close()
  return true
end

local function dir_name(path)
  return path and path:match("^(.+[\\/])") or ""
end

local function join_path(base, ...)
  if not base or base == "" then return nil end
  local path = base
  if not path:match("[\\/]$") then path = path .. sep end
  for i = 1, select("#", ...) do
    local part = tostring(select(i, ...) or "")
    if part ~= "" then
      if not path:match("[\\/]$") then path = path .. sep end
      path = path .. part
    end
  end
  return path
end

local function add_dir(list, seen, dir)
  if not dir or dir == "" or seen[dir] then return end
  seen[dir] = true
  list[#list + 1] = dir
end

local function debug_script_path()
  local info = debug and debug.getinfo and debug.getinfo(1, "S") or nil
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then return source:sub(2) end
  return ""
end

local function find_main_path(action_path)
  local dirs, seen = {}, {}
  add_dir(dirs, seen, dir_name(debug_script_path()))
  add_dir(dirs, seen, dir_name(action_path))
  for _, dir in ipairs(dirs) do
    local nested = join_path(dir, "mbriggs-reaper", "ReaAssist", "ReaAssist.lua")
    if file_exists(nested) then
      return nested, dir_name(nested)
    end

    local adjacent = join_path(dir, "ReaAssist.lua")
    if file_exists(adjacent) then return adjacent, dir end
  end
  return nil, dirs[1] or ""
end

local main_path, app_dir = find_main_path(script_path)
local script_dir = app_dir or dir_name(script_path)

local function message_box(message, flags)
  return reaper.ShowMessageBox(tostring(message or ""), title, flags or 0)
end

local function set_prefer_screen_reader(value)
  if reaper.SetExtState then
    reaper.SetExtState(ext_ns, "prefer_screen_reader",
      value and "1" or "0", true)
  end
end

local function prefer_screen_reader_value()
  return reaper.GetExtState and reaper.GetExtState(
    ext_ns, "prefer_screen_reader") or ""
end

local function prompt_for_screen_reader_preference()
  if prefer_screen_reader_value() ~= "" then return end
  local choice = message_box(
    "Do you want ReaAssist to open in Screen Reader Mode by default?\n\n" ..
    "Choose OK if you use this accessible interface most of the time.\n\n" ..
    "Choose Cancel if you only want to open Screen Reader Mode from its own REAPER action.",
    1)
  set_prefer_screen_reader(choice == 1)
end

local function safe_url(url)
  url = tostring(url or "")
  if not url:match("^https?://") then return "" end
  return url:gsub("[^%w%-%.%_%~%:%/%?%#%[%]%@%!%&%*%+%,%;%=%{%}%%]", "")
end

local function shell_quote(value)
  return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function open_url(url)
  url = safe_url(url)
  if url == "" then return false end
  if reaper.CF_ShellExecute then
    local ok, result = pcall(reaper.CF_ShellExecute, url)
    return ok and result ~= false
  end
  local os_name = reaper.GetOS and tostring(reaper.GetOS() or "") or ""
  local result, _, code
  if os_name:match("^Win") then
    result, _, code = os.execute('start "" "' .. url .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    result, _, code = os.execute(
      "open " .. shell_quote(url) .. " >/dev/null 2>&1 &")
  else
    result, _, code = os.execute(
      "xdg-open " .. shell_quote(url) .. " >/dev/null 2>&1 &")
  end
  return result == true or result == 0 or code == 0
end

local function open_path(path)
  path = tostring(path or "")
  if path == "" then return false end
  if reaper.CF_ShellExecute then
    local ok, result = pcall(reaper.CF_ShellExecute, path)
    return ok and result ~= false
  end
  local os_name = reaper.GetOS and tostring(reaper.GetOS() or "") or ""
  local result, _, code
  if os_name:match("^Win") then
    result, _, code = os.execute('start "" "' .. path .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    result, _, code = os.execute(
      "open " .. shell_quote(path) .. " >/dev/null 2>&1 &")
  else
    result, _, code = os.execute(
      "xdg-open " .. shell_quote(path) .. " >/dev/null 2>&1 &")
  end
  return result == true or result == 0 or code == 0
end

local function copy_url(url)
  if not reaper.CF_SetClipboard then return false end
  return pcall(reaper.CF_SetClipboard, tostring(url or ""))
end

local function osara_note_path()
  if script_dir == "" then return nil end
  local temp_dir = script_dir .. "Data" .. sep .. "Temp"
  return temp_dir .. sep .. "ScreenReader_OSARA_Required.txt", temp_dir
end

local function write_osara_note(message)
  local path, temp_dir = osara_note_path()
  if not path then return nil end
  if reaper and reaper.RecursiveCreateDirectory then
    pcall(reaper.RecursiveCreateDirectory, temp_dir, 0)
  end
  local f = io.open(path, "w")
  if f then
    local text = tostring(message or "")
      :gsub("\r\n", "\n")
      :gsub("\r", "\n")
      :gsub("\n", "\r\n")
    f:write(text)
    f:close()
    return path
  end
  return nil
end

local function show_missing_osara_fallback()
  local base_message =
    "Screen Reader Mode needs OSARA, the REAPER accessibility extension.\n\n" ..
    "Yes: open the official OSARA download page and make Screen Reader Mode the default for ReaAssist.\n\n" ..
    "No: keep the normal ReaAssist action opening the visual interface.\n\n" ..
    "Install OSARA with REAPER closed. Then reopen REAPER and run ReaAssist_Screen_Reader_Mode.lua again."

  local note_message =
    "ReaAssist Screen Reader Mode needs OSARA, the REAPER accessibility extension.\n\n" ..
    "To finish setup:\n" ..
    "1. Download OSARA from the official snapshots page.\n" ..
    "2. Close REAPER.\n" ..
    "3. Install OSARA.\n" ..
    "4. Reopen REAPER and run ReaAssist_Screen_Reader_Mode.lua again.\n\n" ..
    "OSARA download page:\n" .. osara_url .. "\n"

  local note_path = osara_note_path()
  local message = base_message
  local wrote_note = write_osara_note(note_message)
  if note_path and not wrote_note then
    message = base_message .. "\n\nReaAssist could not save a setup note."
  end

  local choice = message_box(message, 4)
  if choice == 6 then
    set_prefer_screen_reader(true)
    local copied = copy_url(osara_url)
    local opened = open_url(osara_url)
    local followup = opened
      and "The official OSARA download page should now be opening.\n\n"
      or "ReaAssist could not open the official OSARA download page automatically.\n\n"
    followup = followup ..
      "Download OSARA, close REAPER, and install OSARA. Then reopen REAPER and run ReaAssist_Screen_Reader_Mode.lua again.\n\n" ..
      "ReaAssist will open in Screen Reader Mode by default after OSARA is installed."
    if copied then
      followup = followup ..
        "\n\nThe OSARA download page link was copied to the clipboard."
    end
    if wrote_note then
      followup = followup ..
        "\n\nA text copy of these instructions was saved to:\n" .. note_path
    end
    message_box(followup, 0)
  else
    set_prefer_screen_reader(false)
    message_box(
      "Screen Reader Mode default is off. The normal ReaAssist action will open the visual interface.\n\n" ..
      "You can still run ReaAssist_Screen_Reader_Mode.lua again after installing OSARA.",
      0)
  end
end

if not reaper.osara_outputMessage then
  show_missing_osara_fallback()
  return
end

prompt_for_screen_reader_preference()

local ScreenReader = {}

function ScreenReader.interpolate_text(text, values)
  if I18N and I18N.interpolate then return I18N.interpolate(text, values) end
  text = tostring(text or "")
  if type(values) ~= "table" then return text end
  return (text:gsub("{([%w_]+)}", function(name)
    local value = values[name]
    if value == nil then return "{" .. name .. "}" end
    return tostring(value)
  end))
end

function ScreenReader.translation_code()
  local fallback_code = I18N and I18N.fallback_code or "en"
  local code = I18N and I18N.lang_code and I18N.lang_code() or fallback_code
  code = tostring(code or fallback_code)
  if not ScreenReader.language_supported_in_screen_reader(code) then
    return fallback_code
  end
  return code
end

function ScreenReader.t(key, values, fallback)
  key = tostring(key or "")
  if I18N and I18N.t then
    local text = I18N.t(key, values, { code = ScreenReader.translation_code() })
    if type(text) == "string" and text ~= "" and text ~= key then
      if key:match("%.meaning$") then
        return ScreenReader.reagirl_sentence(text)
      end
      return text
    end
  elseif AppController and AppController.t then
    local text = AppController.t(key, values, fallback)
    if key:match("%.meaning$") then
      return ScreenReader.reagirl_sentence(text)
    end
    return text
  elseif RA and RA.t then
    local text = RA.t(key, values, fallback)
    if key:match("%.meaning$") then
      return ScreenReader.reagirl_sentence(text)
    end
    return text
  end
  local text = ScreenReader.interpolate_text(fallback or key, values)
  if key:match("%.meaning$") then
    return ScreenReader.reagirl_sentence(text)
  end
  return text
end

function ScreenReader.reagirl_sentence(text)
  text = tostring(text or ""):gsub("%s+$", "")
  if text == "" then return "." end
  if text:sub(-1) == "." or text:sub(-1) == "?"
      or text:sub(-1) == "!" then return text end
  local terminal_map = {
    ["\227\128\130"] = ".", -- U+3002 ideographic full stop
    ["\239\188\142"] = ".", -- U+FF0E fullwidth full stop
    ["\239\189\161"] = ".", -- U+FF61 halfwidth ideographic full stop
    ["\239\188\159"] = "?", -- U+FF1F fullwidth question mark
    ["\239\188\129"] = "!", -- U+FF01 fullwidth exclamation mark
    ["\216\159"] = "?",     -- U+061F Arabic question mark
  }
  for suffix, replacement in pairs(terminal_map) do
    if text:sub(-#suffix) == suffix then
      return text:sub(1, -#suffix - 1):gsub("%s+$", "") .. replacement
    end
  end
  return text .. "."
end

function ScreenReader.shortcut_label(label, shortcut)
  label = tostring(label or "")
  shortcut = tostring(shortcut or "")
  if label == "" or shortcut == "" then return label end
  local suffix = " (" .. shortcut .. ")"
  if label:sub(-#suffix) == suffix then return label end
  return label .. suffix
end

function ScreenReader.t_shortcut(key, fallback, shortcut)
  return ScreenReader.shortcut_label(
    ScreenReader.t(key, nil, fallback), shortcut)
end

function ScreenReader.close_label()
  return ScreenReader.t_shortcut("common.close", "Close", "F4")
end

function ScreenReader.back_label(key, fallback)
  return ScreenReader.t_shortcut(key, fallback, "F9")
end

function ScreenReader.cancel_back_label()
  return ScreenReader.t_shortcut("settings.fx_cache.action.cancel",
    "Cancel", "F9")
end

function ScreenReader.text_size_idx()
  local labels = CFG and CFG.SCREEN_READER_TEXT_SIZE_LABELS or nil
  local max_idx = labels and #labels or 4
  local idx = tonumber(prefs and prefs.screen_reader_text_size_idx or 1) or 1
  if idx < 1 or idx > max_idx then idx = 1 end
  return math.floor(idx)
end

function ScreenReader.text_size_label(idx)
  idx = idx or ScreenReader.text_size_idx()
  local labels = CFG and CFG.SCREEN_READER_TEXT_SIZE_LABELS or nil
  if labels and labels[idx] then
    return ScreenReader.t("a11y.sr.text_size." .. tostring(idx), nil,
      labels[idx])
  end
  local fallback = { "Default", "Large", "Extra Large", "Huge" }
  return fallback[idx] or fallback[1]
end

function ScreenReader.text_size_factor()
  local idx = ScreenReader.text_size_idx()
  local factors = CFG and CFG.SCREEN_READER_TEXT_SIZE_FACTORS or nil
  return tonumber(factors and factors[idx]) or 1.0
end

function ScreenReader.text_size_font_px()
  local idx = ScreenReader.text_size_idx()
  local sizes = CFG and CFG.SCREEN_READER_TEXT_FONT_SIZES or nil
  return math.floor(tonumber(sizes and sizes[idx]) or 15)
end

function ScreenReader.scaled_ui_px(value)
  local scaled = tonumber(value or 0) * ScreenReader.text_size_factor()
  return math.max(1, math.floor(scaled + 0.5))
end

function ScreenReader.large_text_layout()
  return ScreenReader.text_size_idx() >= 3
end

function ScreenReader.control_width_px(value)
  if not ScreenReader.large_text_layout() then return value end
  return ScreenReader.scaled_ui_px(value)
end

function ScreenReader.caption_width_px(value)
  if not ScreenReader.large_text_layout() then return value end
  return ScreenReader.scaled_ui_px(value)
end

function ScreenReader.window_width_px(value)
  if not ScreenReader.large_text_layout() then return value end
  return math.min(1120, ScreenReader.scaled_ui_px(value))
end

function ScreenReader.window_height_px(value)
  if not ScreenReader.large_text_layout() then return value end
  return math.min(720, ScreenReader.scaled_ui_px(value))
end

function ScreenReader.target_window_size(w, h)
  return ScreenReader.window_width_px(w), ScreenReader.window_height_px(h)
end

function ScreenReader.current_language_code()
  local code = prefs and prefs.language_code
  if CFG and CFG.is_valid_language_code
      and CFG.is_valid_language_code(code) then
    return code
  end
  if CFG and CFG.current_language_code then
    return CFG.current_language_code()
  end
  return "en"
end

function ScreenReader.language_supported_in_screen_reader(code)
  code = tostring(code or "")
  if code == "" then return true end
  if CFG and CFG.is_valid_language_code then
    return CFG.is_valid_language_code(code)
  end
  return code == "en"
end

function ScreenReader.language_display_label(code, fallback)
  local cfg_lang = CFG and CFG.language_for_code and CFG.language_for_code(code)
  if type(cfg_lang) == "table" then
    return cfg_lang.label_en or cfg_lang.prompt_name or cfg_lang.label_native
      or fallback or cfg_lang.code or code
  end
  return fallback or code
end

function ScreenReader.reagirl_system_font_dirs()
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  local dirs = {}
  if os_name:match("Win") then
    local windir = os.getenv("WINDIR") or os.getenv("SystemRoot") or "C:\\Windows"
    dirs[#dirs + 1] = windir .. "\\Fonts\\"
  elseif os_name:match("OSX") or os_name:match("macOS") then
    dirs[#dirs + 1] = "/System/Library/Fonts/"
    dirs[#dirs + 1] = "/Library/Fonts/"
  end
  return dirs
end

function ScreenReader.reagirl_font_file_exists(files)
  if not files or #files == 0 then return true end
  local dirs = ScreenReader.reagirl_system_font_dirs()
  for _, file in ipairs(files) do
    file = tostring(file or "")
    if file ~= "" and ScreenReader.file_exists(file) then return true end
    for _, dir in ipairs(dirs) do
      if ScreenReader.file_exists(dir .. file) then return true end
    end
  end
  return false
end

function ScreenReader.reagirl_cjk_font_candidates(code)
  code = tostring(code or "")
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if os_name:match("Win") then
    if code == "zh-Hans" then
      return {
        { face = "Microsoft YaHei UI", files = { "msyh.ttc" } },
        { face = "Microsoft YaHei", files = { "msyh.ttc" } },
        { face = "DengXian", files = { "Deng.ttf" } },
        { face = "SimSun", files = { "simsun.ttc" } },
      }
    elseif code == "zh-Hant" then
      return {
        { face = "Microsoft JhengHei UI", files = { "msjh.ttc" } },
        { face = "Microsoft JhengHei", files = { "msjh.ttc" } },
        { face = "MingLiU", files = { "mingliu.ttc" } },
      }
    elseif code == "ja" then
      return {
        { face = "Yu Gothic UI", files = { "YuGothR.ttc", "YuGothM.ttc" } },
        { face = "Yu Gothic", files = { "YuGothR.ttc", "YuGothM.ttc" } },
        { face = "Meiryo", files = { "meiryo.ttc" } },
        { face = "MS Gothic", files = { "msgothic.ttc" } },
      }
    elseif code == "ko" then
      return {
        { face = "Malgun Gothic", files = { "malgun.ttf" } },
        { face = "Gulim", files = { "gulim.ttc" } },
      }
    end
  elseif os_name:match("OSX") or os_name:match("macOS") then
    if code == "zh-Hans" then
      return {
        { face = "PingFang SC", files = { "PingFang.ttc" } },
        { face = "Heiti SC", files = { "STHeiti Light.ttc", "STHeiti Medium.ttc" } },
      }
    elseif code == "zh-Hant" then
      return {
        { face = "PingFang TC", files = { "PingFang.ttc" } },
        { face = "Heiti TC", files = { "STHeiti Light.ttc", "STHeiti Medium.ttc" } },
      }
    elseif code == "ja" then
      return {
        { face = "Hiragino Sans", files = { "Hiragino Sans GB.ttc" } },
        { face = "Hiragino Kaku Gothic ProN" },
      }
    elseif code == "ko" then
      return {
        { face = "Apple SD Gothic Neo", files = { "AppleSDGothicNeo.ttc" } },
      }
    end
  else
    if code == "zh-Hans" then
      return {
        { face = "Noto Sans CJK SC" },
        { face = "Noto Sans SC" },
        { face = "WenQuanYi Micro Hei" },
      }
    elseif code == "zh-Hant" then
      return {
        { face = "Noto Sans CJK TC" },
        { face = "Noto Sans TC" },
        { face = "WenQuanYi Micro Hei" },
      }
    elseif code == "ja" then
      return {
        { face = "Noto Sans CJK JP" },
        { face = "Noto Sans JP" },
      }
    elseif code == "ko" then
      return {
        { face = "Noto Sans CJK KR" },
        { face = "Noto Sans KR" },
      }
    end
  end
  return nil
end

function ScreenReader.reagirl_font_face_for_language(code)
  local candidates = ScreenReader.reagirl_cjk_font_candidates(code)
  if not candidates then return nil end
  local fallback = candidates[1] and candidates[1].face or nil
  for _, candidate in ipairs(candidates) do
    if candidate.face and ScreenReader.reagirl_font_file_exists(candidate.files) then
      return candidate.face
    end
  end
  return fallback
end

function ScreenReader.apply_reagirl_language_font()
  if not (reagirl and reagirl.Font_Face) then return end
  if not S._screen_reader_reagirl_base_font_face then
    S._screen_reader_reagirl_base_font_face = reagirl.Font_Face
  end
  local code = ScreenReader.current_language_code()
  local face = ScreenReader.reagirl_font_face_for_language(code)
  if face and face ~= "" then
    reagirl.Font_Face = face
    S._screen_reader_reagirl_active_font_face = face
    return
  end
  reagirl.Font_Face = S._screen_reader_reagirl_base_font_face
    or reagirl.Font_Face
  S._screen_reader_reagirl_active_font_face = reagirl.Font_Face
end

function ScreenReader.reagirl_window_section(name)
  return "Reagirl_Window_" .. tostring(name or "")
end

function ScreenReader.store_reagirl_window_size(name, w, h)
  if not (reaper and reaper.SetExtState and name) then return end
  local target_w, target_h = ScreenReader.target_window_size(w, h)
  local section = ScreenReader.reagirl_window_section(name)
  reaper.SetExtState(section, "stored", "true", true)
  reaper.SetExtState(section, "w", tostring(target_w), true)
  reaper.SetExtState(section, "h", tostring(target_h), true)
  reaper.SetExtState(section, "dock", "0", true)
  reaper.SetExtState(section, "x", "", true)
  reaper.SetExtState(section, "y", "", true)
  reaper.SetExtState(section, "newstate", "", false)
end

function ScreenReader.stored_reagirl_window_too_small(name, w, h)
  if not (reaper and reaper.GetExtState and name) then return false end
  local section = ScreenReader.reagirl_window_section(name)
  if reaper.GetExtState(section, "stored") ~= "true" then return false end
  local stored_w = tonumber(reaper.GetExtState(section, "w"))
  local stored_h = tonumber(reaper.GetExtState(section, "h"))
  if not (stored_w and stored_h) then return true end
  local target_w, target_h = ScreenReader.target_window_size(w, h)
  return stored_w < target_w or stored_h < target_h
end

function ScreenReader.open_reagirl_window(name, title, description, w, h)
  local target_w, target_h = ScreenReader.target_window_size(w, h)
  if ScreenReader.stored_reagirl_window_too_small(name, w, h) then
    ScreenReader.store_reagirl_window_size(name, w, h)
  end
  local ok = reagirl.Gui_Open(name, true, title, description,
    target_w, target_h, 0, nil, nil)
  return ok == 1
end

function ScreenReader.next_line_for_large_text()
  if ScreenReader.large_text_layout() then reagirl.NextLine() end
end

function ScreenReader.next_line_for_spacious_layout()
  ScreenReader.next_line_for_large_text()
end

function ScreenReader.apply_reagirl_contrast()
  if not reagirl then return end
  local contrast = tostring(prefs and prefs.screen_reader_contrast or "auto")
  if contrast == "light" and reagirl.Color_SetToLightTheme then
    pcall(reagirl.Color_SetToLightTheme)
  elseif reagirl.Color_SetToDarkTheme then
    pcall(reagirl.Color_SetToDarkTheme)
  end
end

function ScreenReader.apply_reagirl_visual_preferences()
  if not reagirl then return end
  ScreenReader.apply_reagirl_contrast()
  ScreenReader.apply_reagirl_language_font()
  reagirl.Font_Size = ScreenReader.text_size_font_px()
  if reagirl.SetFont and reagirl.Font_Face then
    pcall(reagirl.SetFont, 1, reagirl.Font_Face, reagirl.Font_Size, 0)
  end
end

function ScreenReader.begin_reagirl_ui()
  ScreenReader.apply_reagirl_visual_preferences()
  reagirl.Gui_New()
  reagirl.NextLine_SetDefaults(
    ScreenReader.scaled_ui_px(18),
    ScreenReader.scaled_ui_px(18))
  reagirl.NextLine_SetMargin(
    ScreenReader.scaled_ui_px(14),
    ScreenReader.scaled_ui_px(12))
end

function ScreenReader.announce(text)
  if reaper.osara_outputMessage and text and text ~= "" then
    pcall(reaper.osara_outputMessage, tostring(text))
  end
end

function ScreenReader.finish()
  if AppController and AppController.close_instance then
    AppController.close_instance()
  elseif S then
    S.script_open = false
  end
end

function ScreenReader.file_exists(path)
  local f = path and io.open(path, "rb") or nil
  if not f then return false end
  f:close()
  return true
end

function ScreenReader.read_file(path)
  if not path then return nil, "missing path" end
  local f, err = io.open(path, "rb")
  if not f then return nil, tostring(err or "could not open file") end
  local data = f:read("*a")
  local ok, close_err = f:close()
  if not ok then return nil, tostring(close_err or "could not close file") end
  return data or ""
end

function ScreenReader.write_file(path, data)
  if not path then return false end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(tostring(data or ""))
  return f:close()
end

function ScreenReader.startup_failure_note_path()
  local temp_dir = (RA and RA.TEMP_DIR) or
    (script_dir .. "Data" .. sep .. "Temp" .. sep)
  if reaper and reaper.RecursiveCreateDirectory then
    pcall(reaper.RecursiveCreateDirectory, temp_dir, 0)
  end
  return temp_dir .. "ScreenReader_Startup_Failure.txt"
end

function ScreenReader.report_startup_failure(message, announce_text)
  local msg = tostring(message or "")
  local note_path = ScreenReader.startup_failure_note_path()
  local wrote_note = ScreenReader.write_file(note_path, msg)
  local spoken = tostring(announce_text or msg)
  if wrote_note then
    spoken = spoken .. " " .. ScreenReader.t(
      "a11y.sr.startup_failure_note_saved", nil,
      "Details saved to the ReaAssist Temp folder.")
  else
    spoken = spoken .. " " .. ScreenReader.t(
      "a11y.sr.startup_failure_note_failed", nil,
      "ReaAssist could not save a text copy of this failure.")
  end
  ScreenReader.announce(spoken)
end

function ScreenReader.reagirl_vendor_dir()
  return RA.DATA_DIR .. "Vendor" .. RA.SEP
end

function ScreenReader.reagirl_dest_path()
  return ScreenReader.reagirl_vendor_dir() .. "reagirl.lua"
end

function ScreenReader.reagirl_download_paths()
  local dest = ScreenReader.reagirl_dest_path()
  return dest, dest .. ".download", dest .. ".exit"
end

function ScreenReader.verify_reagirl_file(path)
  if not ScreenReader.file_exists(path) then return false, "missing_reagirl" end
  local data, err = ScreenReader.read_file(path)
  if not data then return false, "read_failed: " .. tostring(err) end
  if #data < reagirl_min_bytes or #data > reagirl_max_bytes then
    return false, "size_mismatch"
  end
  if not (RA and RA.sha256_hex) then return false, "sha_unavailable" end
  local hash = tostring(RA.sha256_hex(data) or ""):lower()
  if hash ~= reagirl_sha256 then return false, "sha_mismatch" end
  if not data:find("function reagirl.Gui_New", 1, true)
      or not data:find("function reagirl.Gui_Open", 1, true) then
    return false, "api_missing"
  end
  return true, data
end

function ScreenReader.reagirl_path()
  local path = ScreenReader.reagirl_dest_path()
  local ok, err = ScreenReader.verify_reagirl_file(path)
  if ok then
    if S then S._screen_reader_reagirl_load_error = nil end
    return path
  end
  if err and err ~= "missing_reagirl" then pcall(os.remove, path) end
  if S then S._screen_reader_reagirl_load_error = err end
  return nil
end

function ScreenReader.wrap_reagirl_sentence_validators()
  if not reagirl or reagirl._reaassist_sentence_wrapped then return end
  local function wrap(name, sentence_arg_idx)
    local original = reagirl[name]
    if type(original) ~= "function" then return end
    reagirl[name] = function(...)
      local args = table.pack(...)
      args[sentence_arg_idx] = ScreenReader.reagirl_sentence(
        args[sentence_arg_idx])
      return original(table.unpack(args, 1, args.n))
    end
  end
  wrap("Gui_Open", 4)
  wrap("Label_Add", 4)
  wrap("Checkbox_Add", 4)
  wrap("Button_Add", 6)
  wrap("Inputbox_Add", 6)
  wrap("DropDownMenu_Add", 6)
  wrap("UI_Element_GetSetMeaningOfUIElement", 3)
  reagirl._reaassist_sentence_wrapped = true
end

function ScreenReader.load_reagirl()
  if reagirl and reagirl.Gui_New then
    ScreenReader.wrap_reagirl_sentence_validators()
    return true
  end
  local path = ScreenReader.reagirl_path()
  if not path then
    return false, S and S._screen_reader_reagirl_load_error or "missing_reagirl"
  end
  local ok, err = pcall(dofile, path)
  if not ok then return false, tostring(err) end
  if not (reagirl and reagirl.Gui_New and reagirl.Gui_Open) then
    return false, "reagirl_api_missing"
  end
  ScreenReader.wrap_reagirl_sentence_validators()
  if S then
    S._screen_reader_reagirl_path = path
    S._screen_reader_reagirl_load_error = nil
  end
  return true
end

function ScreenReader.reagirl_download_error_detail(error_text)
  local err = tostring(error_text or "unknown error")
  local curl_exit = err:match("^curl exit%s+(.+)$")
  if err == "download timed out" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.timeout", nil,
      "The download timed out. Check your internet connection and try again.")
  end
  if curl_exit then
    return ScreenReader.t("a11y.sr.reagirl_download_error.curl_exit", {
      code = curl_exit,
    }, "The download command failed with curl exit " .. curl_exit ..
      ". Check your internet connection or security software and try again.")
  end
  if err == "size_mismatch" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.size_mismatch",
      nil, "The downloaded accessible UI library had an unexpected size. Try again in a moment.")
  end
  if err == "sha_mismatch" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.sha_mismatch",
      nil, "The downloaded accessible UI library did not pass the integrity check. Try again in a moment.")
  end
  if err == "api_missing" or err == "reagirl_api_missing" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.api_missing",
      nil, "The downloaded file did not contain the expected accessible UI library API. Try again in a moment.")
  end
  if err == "sha_unavailable" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.sha_unavailable",
      nil, "ReaAssist could not verify the accessible UI library download. Restart REAPER and try again.")
  end
  if err:match("^read_failed") then
    return ScreenReader.t("a11y.sr.reagirl_download_error.read_failed", {
      error = err,
    }, "ReaAssist could not read the downloaded accessible UI library: " .. err)
  end
  if err == "could not install downloaded file" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.install_failed",
      nil, "The file downloaded, but ReaAssist could not save it in Data\\Vendor. Check folder permissions and try again.")
  end
  if err == "download could not start" then
    return ScreenReader.t("a11y.sr.reagirl_download_error.start_failed",
      nil, "The download could not start. Check your internet connection or security software and try again.")
  end
  return ScreenReader.t("a11y.sr.reagirl_download_error.unknown", {
    error = err,
  }, "The download failed: " .. err)
end

function ScreenReader.fail_reagirl_download(error_text)
  local d = S and S._screen_reader_reagirl_download or nil
  if d then
    pcall(os.remove, d.out_path)
    pcall(os.remove, d.exit_path)
  end
  if S then S._screen_reader_reagirl_download = nil end
  local detail = ScreenReader.reagirl_download_error_detail(error_text)
  local msg = ScreenReader.t("a11y.sr.reagirl_download_failed", {
    error = detail,
    url = reagirl_url,
  }, "Could not download the accessible UI library: " ..
    detail)
  ScreenReader.report_startup_failure(msg, detail)
  ScreenReader.finish()
end

function ScreenReader.poll_reagirl_download()
  local d = S and S._screen_reader_reagirl_download or nil
  if not d then return ScreenReader.finish() end
  local now = reaper.time_precise and reaper.time_precise() or os.time()
  if not ScreenReader.file_exists(d.exit_path) then
    if now - (d.send_time or now) > reagirl_timeout + 15 then
      return ScreenReader.fail_reagirl_download("download timed out")
    end
    if now - (d.last_announce_time or d.send_time or now) >= 15 then
      d.last_announce_time = now
      ScreenReader.announce(ScreenReader.t(
        "a11y.sr.reagirl_download_still_running", nil,
        "Still downloading accessible UI library."))
    end
    return reaper.defer(ScreenReader.poll_reagirl_download)
  end

  local exit_text = ScreenReader.read_file(d.exit_path) or ""
  local exit_code = tonumber(tostring(exit_text):match("%-?%d+")) or -1
  if exit_code ~= 0 then
    return ScreenReader.fail_reagirl_download("curl exit " .. tostring(exit_code))
  end

  local ok, data_or_err = ScreenReader.verify_reagirl_file(d.out_path)
  if not ok then return ScreenReader.fail_reagirl_download(data_or_err) end
  if not (Code and Code.safe_write and Code.safe_write(d.dest_path, data_or_err)) then
    return ScreenReader.fail_reagirl_download("could not install downloaded file")
  end

  pcall(os.remove, d.out_path)
  pcall(os.remove, d.exit_path)
  S._screen_reader_reagirl_download = nil
  ScreenReader.announce(ScreenReader.t("a11y.sr.reagirl_download_ready",
    nil, "Accessible UI library installed. Opening Screen Reader Mode."))
  ScreenReader.start()
end

function ScreenReader.start_reagirl_download()
  local dest, out_path, exit_path = ScreenReader.reagirl_download_paths()
  if reaper.RecursiveCreateDirectory then
    pcall(reaper.RecursiveCreateDirectory, ScreenReader.reagirl_vendor_dir(), 0)
  end
  pcall(os.remove, out_path)
  pcall(os.remove, exit_path)
  local now = reaper.time_precise and reaper.time_precise() or os.time()
  S._screen_reader_reagirl_download = {
    dest_path = dest,
    out_path = out_path,
    exit_path = exit_path,
    url = reagirl_url,
    send_time = now,
    last_announce_time = now,
  }
  local ok = RA and RA.fire_get_to and RA.fire_get_to(
    reagirl_url, out_path, exit_path, reagirl_timeout,
    S._screen_reader_reagirl_download, "REAGIRL")
  if not ok then
    S._screen_reader_reagirl_download = nil
    return false, "download could not start"
  end
  return true
end

function ScreenReader.offer_reagirl_download()
  local ok, err = ScreenReader.start_reagirl_download()
  if not ok then return ScreenReader.fail_reagirl_download(err) end
  ScreenReader.announce(ScreenReader.t("a11y.sr.reagirl_downloading",
    nil, "Downloading accessible UI library."))
  reaper.defer(ScreenReader.poll_reagirl_download)
end

function ScreenReader.clean_label(text, limit)
  text = tostring(text or "")
  text = text:gsub("[%c\r\n\t]+", " ")
  text = text:gsub("%s%s+", " ")
  limit = tonumber(limit) or 0
  if limit > 0 and #text > limit then return text:sub(1, limit) .. "..." end
  return text
end

function ScreenReader.format_count(value)
  local n = math.floor(tonumber(value) or 0)
  local s = tostring(n)
  local out, count = "", 0
  for i = #s, 1, -1 do
    out = s:sub(i, i) .. out
    count = count + 1
    if count % 3 == 0 and i > 1 then out = "," .. out end
  end
  return out
end

function ScreenReader.run_status_label(status)
  status = tostring(status or "")
  local labels = {
    blocked = { "a11y.sr.run_status.blocked", "Code was blocked for safety" },
    blocked_action_context = {
      "a11y.sr.run_status.blocked_action_context",
      "Code needs manual review before running",
    },
    blocked_fragment = {
      "a11y.sr.run_status.blocked_fragment",
      "Code fragment needs manual review",
    },
    blocked_sandbox_api = {
      "a11y.sr.run_status.blocked_sandbox_api",
      "Code uses a blocked API",
    },
    errored = { "a11y.sr.run_status.errored", "Code run failed" },
    local_answer = { "a11y.sr.run_status.local_answer", "Answered locally" },
    manual_run = {
      "a11y.sr.run_status.manual_run",
      "Code is ready for manual review",
    },
    no_code = { "a11y.sr.run_status.no_code", "No runnable code found" },
    no_usable_answer = {
      "a11y.sr.run_status.no_usable_answer",
      "No usable answer was found",
    },
    pending = { "a11y.sr.run_status.pending", "Code is waiting to run" },
    provider_failed = {
      "a11y.sr.run_status.provider_failed",
      "Provider request failed",
    },
    ran_ok = { "a11y.sr.run_status.ran_ok", "Code ran successfully" },
    request_error = { "a11y.sr.run_status.request_error", "Request failed" },
    truncated = { "a11y.sr.run_status.truncated", "Response was truncated" },
  }
  local entry = labels[status]
  if entry then return ScreenReader.t(entry[1], nil, entry[2]) end
  return ScreenReader.clean_label(status:gsub("_", " "), 80)
end

function ScreenReader.run_status_sentence(status)
  return ScreenReader.t("a11y.sr.run_status", {
    status = ScreenReader.run_status_label(status),
  }, "Run status: " .. ScreenReader.run_status_label(status) .. ".")
end

function ScreenReader.humanize_response_text(text, payload)
  text = tostring(text or "")
  local status = payload and payload.run_status or nil
  if not status or status == "" then return text end
  local raw = "Run status: " .. tostring(status)
  local pos = text:find(raw, 1, true)
  if not pos then return text end
  return text:sub(1, pos - 1) .. ScreenReader.run_status_sentence(status)
    .. text:sub(pos + #raw)
end

function ScreenReader.response_metadata_paragraph(text)
  local lower = tostring(text or ""):lower()
  lower = lower:gsub("^%s+", ""):gsub("%s+$", "")
  return lower:match("^run%s+status%s*:") ~= nil
    or lower:match("^tokens%s*:") ~= nil
end

function ScreenReader.plain_response_text(text)
  text = tostring(text or "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local out = {}
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw
    line = line:gsub("^%s*#+%s*", "")
    line = line:gsub("^%s*[%-%*]%s+", "")
    line = line:gsub("^%s*%d+[%.)]%s+", "")
    line = line:gsub("%*%*(.-)%*%*", "%1")
    line = line:gsub("__(.-)__", "%1")
    line = line:gsub("`(.-)`", "%1")
    line = line:gsub("%s+([%.,;:%!%?])", "%1")
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

function ScreenReader.strip_markdown_code_blocks(text)
  text = tostring(text or "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local out = {}
  local in_block = false
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    if raw:match("^%s*```") then
      in_block = not in_block
    elseif not in_block then
      out[#out + 1] = raw
    end
  end
  return table.concat(out, "\n")
end

function ScreenReader.response_prose_text(payload)
  payload = payload or (AppController.latest_response_payload
    and AppController.latest_response_payload() or nil)
  local text = payload and payload.text or ""
  if AppController and AppController.strip_screen_reader_summary_tags then
    text = AppController.strip_screen_reader_summary_tags(text)
  end
  if payload and payload.has_code then
    text = ScreenReader.strip_markdown_code_blocks(text)
  end
  text = ScreenReader.plain_response_text(text)
  if payload then
    local trim = AppController.trim_text
      or function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
    local generated_notice = "Generated code is available separately."
    local keep = {}
    for paragraph in (tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        .. "\n\n"):gmatch("(.-)\n%s*\n") do
      paragraph = trim(paragraph)
      local generated_only = payload.has_code and payload.code
        and payload.code ~= "" and paragraph == generated_notice
      if paragraph ~= ""
          and not generated_only
          and not ScreenReader.response_metadata_paragraph(paragraph) then
        keep[#keep + 1] = paragraph
      end
    end
    text = table.concat(keep, "\n\n")
  end
  return text
end

function ScreenReader.generated_code_summary(payload)
  if not payload then return "" end
  local trim = AppController and AppController.trim_text
    or function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
  local code = tostring(payload.code or "")
  if payload.code_type == "jsfx" then
    local desc = trim(code:match("^%s*desc:%s*(.-)%s*[\r\n]") or "")
    if desc ~= "" then
      return ScreenReader.t("a11y.sr.jsfx_summary", { name = desc },
        "JSFX effect: " .. desc .. ".")
    end
  end
  for raw in (code:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n")
      :gmatch("([^\n]*)\n") do
    local comment = raw:match("^%s*%-%-%s*(.+)$")
    comment = trim(comment or "")
    if comment ~= "" and not ScreenReader.response_text_is_internal(comment) then
      return comment
    end
  end
  local summary = trim(payload.screen_reader_summary or "")
  if summary ~= "" and not ScreenReader.response_text_is_internal(summary) then
    return summary
  end
  return ""
end

function ScreenReader.significant_words(text)
  local stop = {
    a = true, an = true, ["and"] = true, are = true, as = true, at = true,
    be = true, ["for"] = true, from = true, has = true, have = true,
    ["in"] = true, into = true, is = true, it = true, new = true, of = true,
    on = true, ["or"] = true, set = true, sets = true, that = true,
    the = true, this = true, to = true, with = true,
  }
  local words = {}
  for word in tostring(text or ""):lower():gmatch("[%w]+") do
    if #word >= 2 and not stop[word] then words[word] = true end
  end
  return words
end

function ScreenReader.word_count(words)
  local count = 0
  for _ in pairs(words or {}) do count = count + 1 end
  return count
end

function ScreenReader.response_text_is_internal(text)
  local lower = tostring(text or ""):lower()
  lower = lower:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")
  lower = lower:gsub("^%s+", ""):gsub("%s+$", "")
  if lower == "" then return false end
  if lower:match("^helper:") or lower:find("plugin_ref", 1, true)
      or lower:find("binary search", 1, true) then
    return true
  end
  local starts_like_internal_note = lower:match("^i need%s")
    or lower:match("^i will%s")
    or lower:match("^i'll%s")
  if not starts_like_internal_note then return false end
  local markers = {
    "<context_needed", "api_ref", "cache breakpoint", "cache key",
    "cache marker", "cache refresh", "context bucket", "context request",
    "context tag", "context_needed", "docs:", "docs reference",
    "metadata scan", "midi reference", "plugin reference", "prompt_bundle",
    "reference bundle", "request metadata", "snapshot", "sticky context",
    "sticky_context", "system prompt", "validator",
  }
  for _, marker in ipairs(markers) do
    if lower:find(marker, 1, true) then return true end
  end
  return false
end

function ScreenReader.response_action_summary(text)
  local trim = AppController and AppController.trim_text
    or function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
  local verbs = {
    "add", "adds", "added", "apply", "applies", "applied",
    "configure", "configures", "configured", "create", "creates", "created",
    "delete", "deletes", "deleted", "insert", "inserts", "inserted",
    "move", "moves", "moved", "name", "names", "named",
    "remove", "removes", "removed", "rename", "renames", "renamed",
    "route", "routes", "routed", "set", "sets", "updated",
  }
  local function starts_with_action(paragraph)
    local first = tostring(paragraph or ""):lower():match("^%s*([%w_%-]+)")
    if not first then return false end
    for _, verb in ipairs(verbs) do
      if first == verb then return true end
    end
    return false
  end
  for paragraph in (tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
      .. "\n\n"):gmatch("(.-)\n%s*\n") do
    paragraph = trim(paragraph)
    if paragraph ~= ""
        and not ScreenReader.response_text_is_internal(paragraph)
        and starts_with_action(paragraph) then
      return ScreenReader.clean_label(paragraph:gsub("`", ""), 220)
    end
  end
  return ""
end

function ScreenReader.text_redundant_with_summary(text, summary)
  text = tostring(text or "")
  summary = tostring(summary or "")
  if text == "" or summary == "" or #text > 260 then return false end
  local a = ScreenReader.significant_words(text)
  local b = ScreenReader.significant_words(summary)
  local a_count = ScreenReader.word_count(a)
  local b_count = ScreenReader.word_count(b)
  if a_count < 4 or b_count < 4 then return false end
  local overlap = 0
  for word in pairs(a) do
    if b[word] then overlap = overlap + 1 end
  end
  return overlap / math.min(a_count, b_count) >= 0.58
end

function ScreenReader.response_display_prose(text, summary)
  local trim = AppController and AppController.trim_text
    or function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
  local keep = {}
  for paragraph in (tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
      .. "\n\n"):gmatch("(.-)\n%s*\n") do
    paragraph = trim(paragraph)
    if paragraph ~= ""
        and not ScreenReader.response_text_is_internal(paragraph)
        and not ScreenReader.text_redundant_with_summary(paragraph, summary) then
      keep[#keep + 1] = paragraph
    end
  end
  return table.concat(keep, "\n\n")
end

function ScreenReader.response_details_text(payload)
  if not (prefs and prefs.show_details == true and payload) then return "" end
  local msg = payload.request_message or payload.message or {}
  local fields = {}
  local function add(label, value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if value ~= "" then fields[#fields + 1] = label .. ": " .. value end
  end
  local ctx_label = tostring(payload.ctx_label or msg.ctx_label or "")
  if ctx_label ~= "" then
    ctx_label = ctx_label
      :gsub("snapshot", ScreenReader.t("details.value.session", nil, "Session"))
      :gsub("api_ref", "API")
    add(ScreenReader.t("details.label.context", nil, "Context"), ctx_label)
  end
  local model_label = tostring(payload.model_label or msg.model_label or "")
  if model_label ~= "" then
    add(ScreenReader.t("details.label.model", nil, "Model"),
      model_label:gsub(" %b()", ""))
  end
  if payload.tok_in or msg.tok_in then
    add(ScreenReader.t("details.label.tokens", nil, "Tokens"),
      ScreenReader.t("details.value.tokens_io", {
        input = ScreenReader.format_count(payload.tok_in or msg.tok_in),
        output = ScreenReader.format_count(payload.tok_out or msg.tok_out),
      }, ScreenReader.format_count(payload.tok_in or msg.tok_in)
        .. " in / " .. ScreenReader.format_count(payload.tok_out or msg.tok_out)
        .. " out"))
  end
  do
    local cr = tonumber(payload.tok_cache_read or msg.tok_cache_read) or 0
    local cc = tonumber(payload.tok_cache_create or msg.tok_cache_create) or 0
    if cr > 0 or cc > 0 then
      add(ScreenReader.t("details.label.cache", nil, "Cache"),
        ScreenReader.t("details.value.cache_io", {
          read = ScreenReader.format_count(cr),
          created = ScreenReader.format_count(cc),
        }, ScreenReader.format_count(cr) .. " read, "
          .. ScreenReader.format_count(cc) .. " created"))
    end
  end
  local response_time = tonumber(payload.response_time or msg.response_time)
  if response_time then
    add(ScreenReader.t("details.label.time", nil, "Time"),
      string.format("%.1fs", response_time))
  end
  local cost = tonumber(payload.cost or msg.cost)
  local free_tier = payload.free_tier == true or msg.free_tier == true
  if cost and (cost > 0 or free_tier) then
    local cost_text = MODELS and MODELS.format_cost
      and MODELS.format_cost(cost) or string.format("$%.4f", cost)
    if free_tier then
      add(ScreenReader.t("details.label.est_cost", nil, "Estimated cost"),
        ScreenReader.t("details.value.free_tier_cost", { cost = cost_text },
          "Free Tier (would have been ~" .. cost_text .. ")"))
    else
      add(ScreenReader.t("details.label.est_cost", nil, "Estimated cost"),
        "~" .. cost_text)
    end
  end
  local thinking = tostring(payload.thinking_label or msg.thinking_label or "")
  if thinking ~= "" then
    add(ScreenReader.t("details.label.thinking", nil, "Thinking"), thinking)
  end
  local fx_cache = tostring(payload.fx_cache_label or msg.fx_cache_label or "")
  if fx_cache ~= "" then
    add(ScreenReader.t("details.label.fx_cache", nil, "FX Cache"), fx_cache)
  end
  if payload.api_calls or msg.api_calls then
    add(ScreenReader.t("details.label.api_calls", nil, "API Calls"),
      tostring(payload.api_calls or msg.api_calls))
  end
  if #fields == 0 then return "" end
  return ScreenReader.reagirl_sentence(ScreenReader.t(
    "a11y.sr.response_details_prefix", nil, "Details: ")
    .. table.concat(fields, ". "))
end

function ScreenReader.payload_is_typed_action(payload)
  return payload
    and (payload.typed_action == true or payload.code_type == "typed_actions")
end

function ScreenReader.payload_is_jsfx(payload)
  return payload
    and payload.code_type == "jsfx"
    and not ScreenReader.payload_is_typed_action(payload)
end

function ScreenReader.payload_jsfx_message(payload)
  if ScreenReader.payload_is_jsfx(payload) then
    return payload.message
  end
  return nil
end

function ScreenReader.payload_jsfx_added(payload)
  local msg = ScreenReader.payload_jsfx_message(payload)
  return msg and msg.jsfx_added_to_tracks == true
end

function ScreenReader.payload_jsfx_status(payload)
  local msg = ScreenReader.payload_jsfx_message(payload)
  return tostring((msg and msg.jsfx_status) or "")
end

function ScreenReader.payload_can_undo(payload)
  if ScreenReader.payload_is_jsfx(payload) then
    return payload.undo_sent ~= true and ScreenReader.payload_jsfx_added(payload)
  end
  return payload and payload.can_undo == true
end

function ScreenReader.payload_auto_ran(payload)
  if not payload then return false end
  if ScreenReader.payload_is_typed_action(payload) then
    return payload.undo_sent ~= true
      and (payload.can_undo == true
        or payload.run_status == "ran_ok"
        or payload.auto_ran == true
        or payload.typed_action_has_results == true)
  end
  return payload.run_status == "ran_ok"
    and payload.undo_sent ~= true
    and (payload.has_code == true
      or payload.auto_ran == true
      or payload.can_undo == true)
end

function ScreenReader.response_ready_ran_text(payload, long_form)
  local auto_ran = payload and payload.auto_ran == true
  if ScreenReader.payload_is_jsfx(payload) then
    return long_form
      and ScreenReader.t("a11y.sr.response_state_ready_jsfx_added", nil,
        "Response ready. JSFX has been added to the selected tracks. Use Undo Run if you need to revert it, or Read or Save JSFX to review it.")
      or ScreenReader.t("a11y.sr.response_ready_body_jsfx_added", nil,
        "JSFX has been added to the selected tracks.")
  end
  if ScreenReader.payload_is_typed_action(payload) then
    if not auto_ran then
      return long_form
        and ScreenReader.t("a11y.sr.response_state_ready_action_ran_manual",
          nil,
          "Response ready. The structured edit ran successfully. Use Undo Edit if you need to revert it, or Undo and Request Lua to ask for a reusable script.")
        or ScreenReader.t("a11y.sr.response_ready_body_action_ran_manual",
          nil, "The structured edit ran successfully.")
    end
    return long_form
      and ScreenReader.t("a11y.sr.response_state_ready_action_ran", nil,
        "Response ready. Auto-run has already run the structured edit successfully. Use Review Edit Details to review it, or Undo and Request Lua to ask for a reusable script.")
      or ScreenReader.t("a11y.sr.response_ready_body_action_ran", nil,
        "Auto-run has already run the structured edit successfully.")
  end
  if not auto_ran then
    return long_form
      and ScreenReader.t("a11y.sr.response_state_ready_code_ran_manual",
        nil,
        "Response ready. Generated code ran successfully. Use Undo Run if you need to revert it, or Read or Save Code to review it.")
      or ScreenReader.t("a11y.sr.response_ready_body_code_ran_manual",
        nil, "Generated code ran successfully.")
  end
  return long_form
    and ScreenReader.t("a11y.sr.response_state_ready_code_ran", nil,
      "Response ready. Auto-run has already run the generated code successfully. Use Read or Save Code to review it.")
    or ScreenReader.t("a11y.sr.response_ready_body_code_ran", nil,
      "Auto-run has already run the generated code successfully.")
end

function ScreenReader.clean_announcement(text)
  text = tostring(text or "")
  if AppController and AppController.strip_screen_reader_summary_tags then
    text = AppController.strip_screen_reader_summary_tags(text)
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = text:gsub("%s+", " ")
  return (text:match("^%s*(.-)%s*$"))
end

function ScreenReader.response_ready_parts(payload)
  payload = payload or (AppController.latest_response_payload
    and AppController.latest_response_payload() or nil)
  local has_code = payload and payload.has_code == true
  local prose = ScreenReader.response_prose_text(payload)
  local full_has_prose = prose ~= ""
  local typed_action = ScreenReader.payload_is_typed_action(payload)
  local undo_sent = payload and payload.undo_sent == true
  local code_ran = has_code and ScreenReader.payload_auto_ran(payload)
  local action_summary = typed_action
    and ScreenReader.clean_label(payload.typed_action_summary or "", 520) or ""
  local sr_summary_raw = ""
  if has_code and not typed_action then
    local trim = AppController and AppController.trim_text
      or function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
    sr_summary_raw = ScreenReader.generated_code_summary(payload)
    if sr_summary_raw == ""
        or ScreenReader.response_text_is_internal(sr_summary_raw) then
      sr_summary_raw = trim(payload and payload.screen_reader_summary or "")
    end
    if sr_summary_raw == ""
        or ScreenReader.response_text_is_internal(sr_summary_raw) then
      sr_summary_raw = ScreenReader.response_action_summary(prose)
    end
    if sr_summary_raw == "" then
      sr_summary_raw = ScreenReader.generated_code_summary(payload)
    end
  end
  local sr_summary = ScreenReader.clean_label(sr_summary_raw, 220)
  local details_text = ScreenReader.response_details_text(payload)
  prose = ScreenReader.response_display_prose(prose, sr_summary_raw)
  if details_text ~= "" then
    prose = prose ~= "" and (prose .. "\n\n" .. details_text) or details_text
  end
  local has_prose = prose ~= ""
  local response_notes_below = has_prose and has_code
    and ScreenReader.t("a11y.sr.response_notes_after_actions_hint_v2", nil,
      "Available actions are listed first.") or ""
  local manual_run_blocked = ScreenReader.manual_lua_run_block_text(payload)
  local auto_run_blocked = manual_run_blocked ~= ""
    and "" or ScreenReader.auto_run_block_text(payload)
  local body_text
  if undo_sent then
    body_text = ScreenReader.payload_is_jsfx(payload)
      and ScreenReader.t("a11y.sr.response_ready_body_jsfx_undone", nil,
        "Undo has been sent for the JSFX add.")
      or typed_action and ScreenReader.t("a11y.sr.response_ready_body_action_undone", nil,
        "Undo has been sent for this structured edit.")
      or ScreenReader.t("a11y.sr.response_ready_body_code_undone", nil,
        "Undo has been sent for the generated code run.")
  elseif code_ran then
    body_text = ScreenReader.response_ready_ran_text(payload, false)
  elseif typed_action then
    body_text = ScreenReader.t("a11y.sr.response_ready_body_action", nil,
      "Review the edit details before running it, or request Lua if you want a script to save.")
  elseif ScreenReader.payload_is_jsfx(payload) then
    local jsfx_status = ScreenReader.payload_jsfx_status(payload)
    body_text = jsfx_status ~= "" and jsfx_status
      or ScreenReader.t("a11y.sr.response_ready_body_jsfx", nil,
        "The response includes generated JSFX. Read it first, then add it to selected tracks if it matches your request.")
  elseif manual_run_blocked ~= "" then
    body_text = manual_run_blocked
  elseif has_code then
    body_text = ScreenReader.t("a11y.sr.response_ready_body_code", nil,
      "The response includes generated code. Read it first, then run it only if it matches your request.")
  elseif not has_prose then
    body_text = ScreenReader.t("a11y.sr.response_ready_body", nil,
      "The response has arrived, but no readable response text was found.")
  else
    body_text = ""
  end
  return {
    payload = payload,
    has_code = has_code,
    prose = prose,
    full_has_prose = full_has_prose,
    has_prose = has_prose,
    typed_action = typed_action,
    undo_sent = undo_sent,
    code_ran = code_ran,
    action_summary = action_summary,
    sr_summary = sr_summary,
    sr_summary_raw = sr_summary_raw,
    details_text = details_text,
    response_notes_below = response_notes_below,
    auto_run_blocked = auto_run_blocked,
    manual_run_blocked = manual_run_blocked,
    body_text = body_text,
  }
end

function ScreenReader.response_ready_announcement_text(payload, fallback)
  local parts = ScreenReader.response_ready_parts(payload)
  local messages = {}
  if parts.has_code then
    local summary = parts.action_summary ~= "" and parts.action_summary
      or parts.sr_summary
    local status_text = parts.body_text
    if parts.code_ran then
      status_text = parts.typed_action
        and ScreenReader.t("a11y.sr.response_ready_body_action_ran_manual",
          nil, "The structured edit ran successfully.")
        or ScreenReader.t("a11y.sr.response_ready_body_code_ran_manual",
          nil, "Generated code ran successfully.")
    end
    if summary ~= "" then messages[#messages + 1] = summary end
    if status_text ~= "" then messages[#messages + 1] = status_text end
    if parts.auto_run_blocked ~= "" then
      messages[#messages + 1] = parts.auto_run_blocked
    end
    if parts.details_text ~= "" then
      messages[#messages + 1] = parts.details_text
    end
    if #messages == 0 and parts.prose ~= "" then
      messages[#messages + 1] = parts.prose
    end
  else
    if parts.prose ~= "" then
      messages[#messages + 1] = parts.prose
    elseif parts.body_text ~= "" then
      messages[#messages + 1] = parts.body_text
    end
  end
  if #messages == 0 and fallback and fallback ~= "" then
    messages[#messages + 1] = fallback
  end
  return ScreenReader.clean_announcement(table.concat(messages, " "))
end

function ScreenReader.queue_response_ready_announcement(payload, fallback)
  local text = ScreenReader.response_ready_announcement_text(payload, fallback)
  if text == "" then return end
  ScreenReader.set_status_after_rebuild(text, false)
  ScreenReader.announce_after_rebuild_settled(text)
end

function ScreenReader.payload_blocks_manual_lua_run(payload)
  if not payload then return false, "" end
  local status = tostring(payload.validation_status or "")
  local reason = tostring(payload.auto_run_block_reason or "")
  local block_kind = tostring(payload.validation_block_kind or "")
  if reason == "" and status == "blocked" then
    reason = block_kind ~= "" and block_kind or "validation_blocked"
  end
  if reason == "" then return false, "" end
  if reason == "auto_run_disabled"
      or reason == "backup_required"
      or reason == "backup_failed"
      or reason == "risky_code_confirmation"
      or reason == "non_runnable_lua_artifact"
      or reason == "manual_run_only_lua_artifact" then
    return false, ""
  end
  if Code and Code.auto_run_block_reason_blocks_manual_lua
      and Code.auto_run_block_reason_blocks_manual_lua(reason) then
    return true, reason
  end
  if status == "blocked" then
    local fallback = block_kind ~= "" and block_kind or "validation_blocked"
    return true, fallback
  end
  return false, reason
end

function ScreenReader.manual_lua_run_block_text(payload)
  local blocked, reason = ScreenReader.payload_blocks_manual_lua_run(payload)
  if not blocked then return "" end
  if reason == "sandbox_forbidden_global" then
    return ScreenReader.t("a11y.sr.run_code_sandbox_blocked", nil,
      "ReaAssist blocked this code from running because it uses a restricted Lua API. Ask ReaAssist to regenerate it instead.")
  end
  return ScreenReader.t("a11y.sr.run_code_validation_blocked", nil,
    "ReaAssist blocked this code from running because validation flagged it. Ask ReaAssist to regenerate it instead.")
end

function ScreenReader.auto_run_block_text(payload)
  local reason = payload and tostring(payload.auto_run_block_reason or "") or ""
  if reason == "" or reason == "auto_run_disabled" then return "" end
  if reason == "fx_param_scope_validator" then
    return ScreenReader.t("auto_run.blocked.fx_param_scope", nil,
      "Auto-run blocked: the model added plugin parameter changes even though the request only asked to add/load FX. Review the TrackFX_SetParam*/TakeFX_SetParam* lines before running manually.")
  end
  if reason == "fx_identifier_validator" then
    return ScreenReader.t("auto_run.blocked.fx_identifier", nil,
      "Auto-run blocked: the script did not use the exact preferred FX identifier. Review the TrackFX_AddByName plugin names before running manually.")
  end
  if reason == "proq4_bell_slope_validator" then
    return ScreenReader.t("auto_run.blocked.proq4_bell_slope", nil,
      "Auto-run blocked: Pro-Q 4 Bell boost/cut bands did not set Slope to 12 dB/oct. Review the Pro-Q 4 slope writes before running manually.")
  end
  if reason == "backup_required" then
    if ScreenReader.payload_is_typed_action(payload) then
      return ScreenReader.t("typed_actions.status.backup_required", nil,
        "Structured edit validated, but auto-run is blocked until the project is saved for safety backup.")
    end
    return ScreenReader.t("a11y.sr.run_code_backup_unsaved", nil,
      "Auto-backup is on, but the project has not been saved.")
  end
  if reason == "backup_failed" then
    if ScreenReader.payload_is_typed_action(payload) then
      return ScreenReader.t("typed_actions.status.backup_failed", nil,
        "Structured edit validated, but auto-run is blocked because ReaAssist could not create a safety backup.")
    end
    return ScreenReader.t("a11y.sr.auto_run_blocked_backup_failed", nil,
      "Auto-run was blocked because ReaAssist could not create a safety backup.")
  end
  if reason == "risky_code_confirmation" then
    return ScreenReader.t("a11y.sr.run_code_risky", nil,
      "This generated code needs confirmation before it runs.")
  end
  if reason == "sandbox_forbidden_global" then
    return ScreenReader.t("a11y.sr.auto_run_blocked_sandbox", nil,
      "Auto-run blocked: generated code uses a restricted Lua API. Review it before running manually.")
  end
  if reason == "non_runnable_lua_artifact" then
    return ScreenReader.t("a11y.sr.auto_run_blocked_non_runnable", nil,
      "Auto-run was blocked because the generated Lua was not runnable. Review or regenerate it before running manually.")
  end
  if reason == "manual_run_only_lua_artifact" then
    return ScreenReader.t("a11y.sr.auto_run_blocked_manual_only", nil,
      "Auto-run was blocked because this generated code requires manual review before running.")
  end
  return ScreenReader.t("auto_run.blocked.validator", nil,
    "Auto-run blocked: ReaAssist validation flagged this script. Review it before running manually.")
end

function ScreenReader.read_code_label(payload)
  local label
  if ScreenReader.payload_is_typed_action(payload) then
    label = ScreenReader.t("a11y.sr.read_action_plan", nil,
      "Review Edit Details")
  elseif ScreenReader.payload_is_jsfx(payload) then
    label = ScreenReader.t("a11y.sr.read_jsfx", nil, "Read or Save JSFX")
  else
    label = ScreenReader.t("a11y.sr.read_code", nil, "Read or Save Code")
  end
  return ScreenReader.shortcut_label(label, "F6")
end

function ScreenReader.read_code_meaning(payload)
  if ScreenReader.payload_is_typed_action(payload) then
    return ScreenReader.t("a11y.sr.read_action_plan.meaning", nil,
      "Opens the edit details preview with copy and save controls.")
  end
  if ScreenReader.payload_is_jsfx(payload) then
    return ScreenReader.t("a11y.sr.read_jsfx.meaning", nil,
      "Opens generated JSFX preview with copy, save, and add-to-selected-tracks controls.")
  end
  return ScreenReader.t("a11y.sr.read_code.meaning", nil,
    "Opens generated code preview with copy and save controls.")
end

function ScreenReader.undo_label(payload)
  local label
  if ScreenReader.payload_is_typed_action(payload) then
    label = ScreenReader.t("a11y.sr.undo_edit", nil, "Undo Edit")
  elseif ScreenReader.payload_is_jsfx(payload) then
    label = ScreenReader.t("a11y.sr.undo_jsfx", nil, "Undo JSFX Add")
  else
    label = ScreenReader.t("a11y.sr.undo_run", nil, "Undo Run")
  end
  return ScreenReader.shortcut_label(label, "F7")
end

function ScreenReader.undo_meaning(payload)
  if ScreenReader.payload_is_typed_action(payload) then
    return ScreenReader.t("a11y.sr.undo_edit.meaning", nil,
      "Sends REAPER Undo for the structured edit that just ran.")
  end
  if ScreenReader.payload_is_jsfx(payload) then
    return ScreenReader.t("a11y.sr.undo_jsfx.meaning", nil,
      "Sends REAPER Undo for adding the JSFX to selected tracks.")
  end
  return ScreenReader.t("a11y.sr.undo_run.meaning", nil,
    "Sends REAPER Undo for the generated code that just ran.")
end

function ScreenReader.wrap_text(text, width)
  width = tonumber(width) or 84
  local out, line = {}, ""
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local function push_line()
    out[#out + 1] = line
    line = ""
  end
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    if raw == "" then
      if line ~= "" then push_line() end
      out[#out + 1] = ""
    else
      for word in raw:gmatch("%S+") do
        while #word > width do
          local chunk = word:sub(1, width)
          word = word:sub(width + 1)
          if line ~= "" then push_line() end
          out[#out + 1] = chunk
        end
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          push_line()
          line = word
        end
      end
      if line ~= "" then push_line() end
    end
  end
  if #out > 0 and out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n")
end

function ScreenReader.measure_text_px(text)
  if gfx and gfx.measurestr then
    local w = gfx.measurestr(tostring(text or ""))
    return tonumber(w) or 0
  end
  return #tostring(text or "") * math.max(1, ScreenReader.text_size_font_px() * 0.55)
end

function ScreenReader.wrap_text_to_px(text, max_px, fallback_width)
  max_px = tonumber(max_px) or 0
  if max_px <= 0 then
    return ScreenReader.wrap_text(text, fallback_width or 84)
  end
  local out, line = {}, ""
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local function push_line()
    out[#out + 1] = line
    line = ""
  end
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    if raw == "" then
      if line ~= "" then push_line() end
      out[#out + 1] = ""
    else
      for word in raw:gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if line == "" or ScreenReader.measure_text_px(candidate) <= max_px then
          line = candidate
        else
          push_line()
          line = word
        end
      end
      if line ~= "" then push_line() end
    end
  end
  if #out > 0 and out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n")
end

function ScreenReader.status_text(prefix)
  local status = AppController.provider_model_status_text()
  if prefix and prefix ~= "" then status = tostring(prefix) .. " " .. status end
  if not AppController.active_provider_is_usable() then
    status = status .. " " .. ScreenReader.t(
      "a11y.sr.provider_not_configured_short",
      nil,
      "The selected provider needs setup before sending.")
  end
  return status
end

function ScreenReader.page_status_text()
  return ScreenReader.t("a11y.sr.page_status_ready", nil, "Ready.")
end

function ScreenReader.mode_summary_text()
  if prefs and prefs.auto_run then
    local backup = prefs.auto_backup and ScreenReader.t("a11y.sr.on", nil, "on")
      or ScreenReader.t("a11y.sr.off", nil, "off")
    return ScreenReader.t("a11y.sr.mode_auto_run", { backup = backup },
      "Mode: Auto-run generated actions. Auto-backup is " .. backup .. ".")
  end
  return ScreenReader.t("a11y.sr.mode_ask", nil,
    "Mode: Ask. ReaAssist will not run generated actions automatically.")
end

function ScreenReader.set_label(id, text)
  if not (id and reagirl) then return end
  text = tostring(text or "")
  if reagirl.Label_SetLabelText then
    pcall(reagirl.Label_SetLabelText, id, text)
  elseif reagirl.UI_Element_GetSetCaption then
    pcall(reagirl.UI_Element_GetSetCaption, id, true,
      ScreenReader.clean_label(text, 900))
  end
end

function ScreenReader.set_button_disabled(id, state)
  if id and reagirl and reagirl.Button_SetDisabled then
    pcall(reagirl.Button_SetDisabled, id, state == true)
  end
end

function ScreenReader.set_input_disabled(id, state)
  if id and reagirl and reagirl.Inputbox_SetDisabled then
    pcall(reagirl.Inputbox_SetDisabled, id, state == true)
  end
end

function ScreenReader.set_checkbox(id, state)
  if id and reagirl and reagirl.Checkbox_SetCheckState then
    pcall(reagirl.Checkbox_SetCheckState, id, state == true)
  end
end

function ScreenReader.set_dropdown_items(id, labels, selected)
  if id and reagirl and reagirl.DropDownMenu_SetMenuItems then
    if #labels == 0 then labels = { "None" }; selected = 1 end
    pcall(reagirl.DropDownMenu_SetMenuItems, id, labels, selected or 1)
  end
end

function ScreenReader.menu_from_provider_items()
  local labels, map, selected = {}, {}, 1
  for _, item in ipairs(AppController.provider_items({
    include_unconfigured = true,
  })) do
    local label = item.label
    if not item.configured then
      label = label .. " (" .. ScreenReader.t(
        "a11y.sr.needs_setup_suffix", nil, "needs setup") .. ")"
    end
    labels[#labels + 1] = label
    map[#labels] = item.idx
    if item.selected then selected = #labels end
  end
  if #labels == 0 then
    labels[1] = ScreenReader.t("a11y.sr.no_providers", nil,
      "No providers available")
  end
  return labels, map, selected
end

function ScreenReader.menu_from_model_items()
  local labels, map, selected = {}, {}, 1
  for _, item in ipairs(AppController.model_items({
    include_unavailable = true,
  })) do
    local label = item.label
    if item.paid_locked then
      label = label .. " (" .. ScreenReader.t(
        "a11y.sr.paid_tier_suffix", nil, "paid tier required") .. ")"
    elseif not item.available then
      label = label .. " (" .. ScreenReader.t(
        "a11y.sr.unavailable_suffix", nil, "unavailable") .. ")"
    end
    labels[#labels + 1] = label
    map[#labels] = item.available and item.idx or nil
    if item.selected then selected = #labels end
  end
  if #labels == 0 then
    labels[1] = ScreenReader.t("a11y.sr.no_models", nil,
      "No models available")
  end
  return labels, map, selected
end

function ScreenReader.menu_from_thinking_items()
  local labels, map, selected = {}, {}, 1
  for _, item in ipairs(AppController.thinking_items()) do
    local value = tostring(item.value or ""):lower()
    local label = value ~= "" and ScreenReader.t(
      "mode.thinking.level." .. value, nil, item.label) or item.label
    labels[#labels + 1] = label
    map[#labels] = item.idx
    if item.selected then selected = #labels end
  end
  if #labels == 0 then
    labels[1] = ScreenReader.t("a11y.sr.thinking_default", nil, "Default")
  end
  return labels, map, selected
end

function ScreenReader.current_prompt()
  return AppController.trim_text(S and S._screen_reader_prompt or "")
end

function ScreenReader.prompt_draft_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP .. "ScreenReader_Prompt_Draft.txt"
end

function ScreenReader.write_text_file(path, text)
  if not path then return false end
  local dir = path:match("^(.+[\\/])")
  if dir and reaper.RecursiveCreateDirectory then
    pcall(reaper.RecursiveCreateDirectory, dir, 0)
  end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(tostring(text or ""))
  f:close()
  return true
end

function ScreenReader.clipboard_text()
  if not reaper.CF_GetClipboard then return nil end
  local ok, text = pcall(reaper.CF_GetClipboard)
  if not ok then return nil end
  return tostring(text or "")
end

function ScreenReader.prompt_preview_text()
  local prompt = ScreenReader.current_prompt()
  if prompt == "" then
    return ScreenReader.t("a11y.sr.prompt_empty_preview", nil,
      "Prompt: no prompt entered. Choose Edit Prompt to enter a request.")
  end
  return ScreenReader.t("a11y.sr.prompt_preview", {
    prompt = ScreenReader.clean_label(prompt, 100),
  }, "Prompt: " .. ScreenReader.clean_label(prompt, 100))
end

function ScreenReader.prompt_body_text()
  local prompt = ScreenReader.current_prompt()
  if prompt == "" then
    return ScreenReader.t("a11y.sr.prompt_body_empty", nil,
      "No prompt entered.")
  end
  local compact = ScreenReader.clean_label(prompt, 140)
  if #compact <= 140 and not compact:match("%.%.%.$") then
    return compact
  end
  return ScreenReader.t("a11y.sr.prompt_body_long", {
    chars = tostring(#prompt),
  }, "Long prompt loaded (" .. tostring(#prompt) ..
    " characters). Use Copy Prompt or Save Prompt to review the full text.")
end

function ScreenReader.prompt_input_projection(text)
  return ScreenReader.clean_label(text, 1000)
end

function ScreenReader.should_preserve_prompt_input_projection(text)
  local current = tostring(S and S._screen_reader_prompt or "")
  if current == "" then return false end
  local projected = ScreenReader.prompt_input_projection(current)
  return current ~= projected and tostring(text or "") == projected
end

function ScreenReader.prompt_input_text()
  return ScreenReader.prompt_input_projection(
    S and S._screen_reader_prompt or "")
end

function ScreenReader.set_prompt_input(text)
  local ui = S and S.screen_reader_ui or nil
  local id = ui and ui.ids and ui.ids.prompt_input
  if id and reagirl and reagirl.Inputbox_SetText then
    local source = text
    if source == nil then source = S and S._screen_reader_prompt or "" end
    pcall(reagirl.Inputbox_SetText, id,
      ScreenReader.prompt_input_projection(source))
  end
end

function ScreenReader.update_prompt_from_input(text, should_announce,
    preserve_projection)
  local incoming = tostring(text or "")
  if preserve_projection ~= false
      and ScreenReader.should_preserve_prompt_input_projection(incoming) then
    ScreenReader.refresh_prompt_preview(true)
    ScreenReader.refresh_actions()
    return
  end
  S._screen_reader_prompt = incoming
  ScreenReader.refresh_prompt_preview(true)
  ScreenReader.refresh_actions()
  if should_announce then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.prompt_updated", nil,
      "Prompt updated. Press Send when ready."), true)
  end
end

function ScreenReader.add_prompt_input(ui, width, submit_on_enter)
  local meaning_key = submit_on_enter
    and "a11y.sr.prompt_input.meaning"
    or "a11y.sr.prompt_input_tools.meaning"
  local meaning_fallback = submit_on_enter
    and ("Type a short prompt here. Press Enter to open ReaGirl's "
      .. "accessible input dialog. In that dialog, OK sends the prompt "
      .. "from the main screen. Use Prompt & Chat for long or multiline "
      .. "prompts.")
    or ("Type or paste a prompt here. Press Enter to edit it in ReaGirl's "
      .. "accessible input dialog. In that dialog, OK updates the prompt "
      .. "on this screen. Use Send when ready.")
  ui.ids.prompt_input = reagirl.Inputbox_Add(nil, nil, width or 620,
    ScreenReader.t("a11y.sr.prompt_input", nil, "Prompt"),
    ScreenReader.caption_width_px(80),
    ScreenReader.t(meaning_key, nil, meaning_fallback),
    ScreenReader.prompt_input_text(),
    function(_, text)
      ScreenReader.update_prompt_from_input(text, not submit_on_enter)
      if submit_on_enter then ScreenReader.send_current_prompt() end
    end,
    function(_, text) ScreenReader.update_prompt_from_input(text, false) end,
    "prompt_input")
  if reagirl.Inputbox_SetEmptyText then
    pcall(reagirl.Inputbox_SetEmptyText, ui.ids.prompt_input,
      ScreenReader.t("a11y.sr.prompt_input_empty", nil,
        "Type a request for ReaAssist"))
  end
  return ui.ids.prompt_input
end

function ScreenReader.refresh_prompt_preview(skip_input)
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    if not skip_input then
      ScreenReader.set_prompt_input(S._screen_reader_prompt or "")
    end
    ScreenReader.set_label(ui.ids.prompt_preview,
      ScreenReader.prompt_preview_text())
    ScreenReader.set_label(ui.ids.prompt_editor_preview,
      ScreenReader.prompt_preview_text())
    ScreenReader.set_label(ui.ids.prompt_editor_body,
      ScreenReader.prompt_body_text())
  end
end

function ScreenReader.response_state_text(request_active, payload)
  if request_active then
    return ScreenReader.t("a11y.sr.response_state_waiting", nil,
      "Waiting for response. ReaAssist is still working.")
  end
  payload = payload or (AppController.latest_response_payload
    and AppController.latest_response_payload() or nil)
  if payload and payload.text and payload.text ~= "" then
    if payload.has_code then
      if ScreenReader.payload_is_jsfx(payload) then
        local jsfx_status = ScreenReader.payload_jsfx_status(payload)
        if jsfx_status ~= "" then
          return ScreenReader.t("a11y.sr.response_state_ready_jsfx_status", {
            status = jsfx_status,
          }, "Response ready. " .. jsfx_status)
        end
        return ScreenReader.t("a11y.sr.response_state_ready_jsfx", nil,
          "Response ready. Generated JSFX is available; use Read or Save JSFX, or Add JSFX to Selected Tracks after reviewing it.")
      end
      if ScreenReader.payload_auto_ran(payload) then
        return ScreenReader.response_ready_ran_text(payload, true)
      end
      return ScreenReader.t("a11y.sr.response_state_ready_code", nil,
        "Response ready. Generated code is available; use Read or Save Code, or Run Code after reviewing it.")
    end
    return ScreenReader.t("a11y.sr.response_state_ready", nil,
      "Response ready.")
  end
  return ScreenReader.t("a11y.sr.response_state_empty", nil,
    "No response yet. Send a request to get a response.")
end

function ScreenReader.edit_prompt()
  ScreenReader.open_view("prompt_edit")
end

function ScreenReader.starter_prompt_defs()
  return {
    "session_awareness",
    "editing",
    "track_project",
    "mixing_effects",
    "lua_scripting",
    "jsfx",
    "qa",
    "no_audio",
  }
end

function ScreenReader.use_starter_prompt(card_id)
  card_id = tostring(card_id or "")
  local title = ScreenReader.t("home.card." .. card_id .. ".title", nil,
    card_id:gsub("_", " "))
  local prompt = ScreenReader.t("home.card." .. card_id .. ".prompt", nil, "")
  if prompt == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.starter_prompt_missing",
      nil, "Starter prompt is not available."), true)
    return
  end
  S._screen_reader_prompt = prompt
  ScreenReader.refresh_prompt_preview()
  ScreenReader.refresh_actions()
  local msg = ScreenReader.t("a11y.sr.starter_prompt_loaded_named",
    { title = title }, "Starter prompt loaded: " .. title .. ".")
  if S and S._screen_reader_view == "example_prompts" then
    ScreenReader.set_status_after_rebuild(msg, true)
    ScreenReader.open_view("main")
    return
  end
  ScreenReader.set_status(msg, true)
end

function ScreenReader.set_prompt_text(text, status_key, fallback)
  S._screen_reader_prompt = tostring(text or "")
  ScreenReader.refresh_prompt_preview()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t(status_key or "a11y.sr.prompt_updated",
    nil, fallback or "Prompt updated. Press Send when ready."), true)
end

function ScreenReader.open_main_for_next_request()
  S._screen_reader_prompt = ""
  ScreenReader.refresh_prompt_preview()
  ScreenReader.focus_after_rebuild("prompt_input")
  ScreenReader.open_view("main")
end

function ScreenReader.open_prompt_for_next_request()
  S._screen_reader_prompt = ""
  ScreenReader.refresh_prompt_preview()
  ScreenReader.focus_after_rebuild("prompt_input")
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.new_prompt_ready", nil,
    "New prompt ready. Press Enter on Prompt to type, then use Send."), true)
  ScreenReader.open_view("prompt_edit")
end

function ScreenReader.new_prompt_dialog()
  if not (reaper and reaper.GetUserInputs) then return nil, "unavailable" end
  local ok, accepted, text = pcall(reaper.GetUserInputs,
    ScreenReader.t("a11y.sr.new_prompt_dialog_title", nil, "New Prompt"),
    1,
    ScreenReader.t("a11y.sr.new_prompt_dialog_caption", nil,
      "Prompt. OK sends") .. ",extrawidth=300",
    "")
  if not ok then return nil, accepted end
  if not accepted then return false, "" end
  return true, tostring(text or "")
end

function ScreenReader.paste_prompt(replace)
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  if AppController.trim_text(text) == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_empty", nil,
      "Clipboard is empty."), true)
    return
  end
  local prompt = replace and text or tostring(S._screen_reader_prompt or "")
  if not replace and prompt ~= "" then prompt = prompt .. "\n\n" .. text end
  ScreenReader.set_prompt_text(prompt, replace and "a11y.sr.prompt_pasted"
    or "a11y.sr.prompt_appended",
    replace and "Prompt pasted from clipboard."
      or "Clipboard text appended to prompt.")
end

function ScreenReader.open_prompt_draft()
  local path = ScreenReader.prompt_draft_path()
  local ok = ScreenReader.write_text_file(path, tostring(S._screen_reader_prompt or ""))
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.prompt_draft_opened", { path = path },
      "Prompt draft opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.prompt_draft_open_failed", { path = path },
      "Could not open prompt draft: " .. tostring(path)), true)
end

function ScreenReader.load_prompt_draft()
  local path = ScreenReader.prompt_draft_path()
  local text, err = ScreenReader.read_file(path)
  if not text then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.prompt_draft_read_failed",
      { error = tostring(err or "unknown error") },
      "Could not read prompt draft: " .. tostring(err or "unknown error")),
      true)
    return
  end
  ScreenReader.set_prompt_text(text, "a11y.sr.prompt_draft_loaded",
    "Prompt loaded from draft file.")
end

function ScreenReader.clear_prompt()
  ScreenReader.set_prompt_text("", "a11y.sr.prompt_cleared",
    "Prompt cleared.")
end

function ScreenReader.copy_prompt()
  local prompt = ScreenReader.current_prompt()
  if prompt == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_prompt_to_copy",
      nil, "There is no prompt to copy."), true)
    return
  end
  local ok = AppController.copy_text(prompt)
  ScreenReader.set_status(ok and ScreenReader.t("a11y.sr.prompt_copied",
    nil, "Prompt copied to clipboard.")
    or ScreenReader.t("a11y.sr.prompt_copy_failed", nil,
      "Could not copy the prompt."), true)
end

function ScreenReader.save_prompt()
  local prompt = ScreenReader.current_prompt()
  if prompt == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_prompt_to_save",
      nil, "There is no prompt to save."), true)
    return
  end
  local path = AppController.write_transcript(prompt,
    "ScreenReader_Prompt.txt")
  ScreenReader.set_status(path and ScreenReader.t("a11y.sr.prompt_saved", {
      path = path,
    }, "Prompt saved to " .. tostring(path) .. ".")
    or ScreenReader.t("a11y.sr.prompt_save_failed", nil,
      "Could not save the prompt."), true,
    path and ScreenReader.t("a11y.sr.prompt_saved_short", nil,
      "Prompt saved.") or nil)
end

function ScreenReader.refresh_attachment_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    local text = AppController.attachment_summary_text
      and AppController.attachment_summary_text()
      or ScreenReader.t("a11y.sr.attachments_none", nil,
        "No attachments queued.")
    ScreenReader.set_label(ui.ids.attachments_summary, text)
    ScreenReader.set_label(ui.ids.attachments_preview, text)
  end
end

function ScreenReader.add_attachment_from_clipboard_path()
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  local ok, err = AppController.add_attachment_path(text)
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.attachment_added", nil,
      "Attachment added.")
    or tostring(err or ScreenReader.t("a11y.sr.attachment_add_failed", nil,
      "Could not add attachment.")), true)
end

function ScreenReader.add_clipboard_image_attachment()
  local ok, err = AppController.add_clipboard_image_attachment()
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.attachment_added", nil,
      "Attachment added.")
    or tostring(err or ScreenReader.t("a11y.sr.attachment_add_failed", nil,
      "Could not add attachment.")), true)
end

function ScreenReader.add_screenshot_attachment()
  local ok, err = AppController.add_screenshot_attachment()
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.attachment_added", nil,
      "Attachment added.")
    or tostring(err or ScreenReader.t("a11y.sr.attachment_add_failed", nil,
      "Could not add attachment.")), true)
end

function ScreenReader.remove_last_attachment()
  local count = AppController.attachment_count and AppController.attachment_count()
    or 0
  local ok = count > 0 and AppController.remove_attachment(count)
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.attachment_removed", nil,
      "Last attachment removed.")
    or ScreenReader.t("a11y.sr.attachments_none", nil,
      "No attachments queued."), true)
end

function ScreenReader.clear_attachments()
  AppController.clear_attachments()
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.attachments_cleared", nil,
    "Attachments cleared."), true)
end

function ScreenReader.report_comment()
  return tostring(S and S._screen_reader_report_comment or "")
end

function ScreenReader.report_name()
  return tostring(S and S._screen_reader_report_name or "")
end

function ScreenReader.report_email()
  return tostring(S and S._screen_reader_report_email or "")
end

function ScreenReader.report_comment_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP
    .. "ScreenReader_Report_Description.txt"
end

function ScreenReader.report_contact_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP
    .. "ScreenReader_Report_Contact.txt"
end

function ScreenReader.invalidate_report_preview()
  if S then S._screen_reader_report_draft = nil end
end

function ScreenReader.report_summary_text()
  local comment = AppController.trim_text(ScreenReader.report_comment())
  local contact = ScreenReader.report_email()
  local contact_text = contact ~= ""
    and ScreenReader.t("a11y.sr.report_contact_saved", nil,
      "Contact email saved.")
    or ScreenReader.t("a11y.sr.report_contact_empty", nil,
      "No contact email saved.")
  local attachment = ScreenReader.t("a11y.sr.report_attachment_none", nil,
    "Diagnostic report only.")
  local log_has_content = false
  if prefs and prefs.debug_logging and Log and Log.path and Log.path ~= "" then
    local f = io.open(Log.path, "rb")
    if f then
      log_has_content = (f:seek("end") or 0) > 0
      f:close()
    end
  end
  if log_has_content then
    attachment = ScreenReader.t("a11y.sr.report_attachment_log", nil,
      "Advanced Log will be attached.")
  elseif S and S.display_messages and #S.display_messages > 0 then
    attachment = ScreenReader.t("a11y.sr.report_attachment_chat", {
      count = tostring(#S.display_messages),
    }, "Current chat will be attached.")
  end
  if comment == "" then
    return ScreenReader.t("a11y.sr.report_summary_empty", {
      contact = contact_text,
      attachment = attachment,
    }, "Report description is empty. " .. contact_text .. " " .. attachment)
  end
  return ScreenReader.t("a11y.sr.report_summary", {
    chars = tostring(#comment),
    contact = contact_text,
    attachment = attachment,
  }, "Report description has " .. tostring(#comment)
    .. " characters. " .. contact_text .. " " .. attachment)
end

function ScreenReader.refresh_report_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    ScreenReader.set_label(ui.ids.report_summary,
      ScreenReader.report_summary_text())
    ScreenReader.set_label(ui.ids.report_comment_preview,
      ScreenReader.t("a11y.sr.report_comment_preview", {
        text = ScreenReader.clean_label(ScreenReader.report_comment(), 220),
      }, "Description: "
        .. (ScreenReader.clean_label(ScreenReader.report_comment(), 220)
          ~= "" and ScreenReader.clean_label(ScreenReader.report_comment(), 220)
          or ScreenReader.t("a11y.sr.report_comment_empty", nil,
            "empty"))))
    ScreenReader.set_label(ui.ids.report_contact_preview,
      ScreenReader.t("a11y.sr.report_contact_preview", {
        name = ScreenReader.report_name() ~= "" and ScreenReader.report_name()
          or ScreenReader.t("a11y.sr.report_contact_no_name", nil, "no name"),
        email = ScreenReader.report_email() ~= "" and ScreenReader.report_email()
          or ScreenReader.t("a11y.sr.report_contact_no_email", nil, "no email"),
      }, "Contact: " .. (ScreenReader.report_name() ~= ""
          and ScreenReader.report_name() or "no name") .. ", "
        .. (ScreenReader.report_email() ~= "" and ScreenReader.report_email()
          or "no email")))
  end
end

function ScreenReader.set_report_comment(text, status_key, fallback)
  S._screen_reader_report_comment = tostring(text or "")
  ScreenReader.invalidate_report_preview()
  ScreenReader.refresh_report_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t(status_key, nil, fallback), true)
end

function ScreenReader.paste_report_comment(replace)
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  if AppController.trim_text(text) == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_empty", nil,
      "Clipboard is empty."), true)
    return
  end
  local comment = replace and text or ScreenReader.report_comment()
  if not replace and comment ~= "" then comment = comment .. "\n\n" .. text end
  ScreenReader.set_report_comment(comment,
    replace and "a11y.sr.report_comment_pasted"
      or "a11y.sr.report_comment_appended",
    replace and "Report description pasted from clipboard."
      or "Clipboard text appended to report description.")
end

function ScreenReader.open_report_comment_file()
  local path = ScreenReader.report_comment_path()
  local ok = ScreenReader.write_text_file(path, ScreenReader.report_comment())
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.report_comment_opened", { path = path },
      "Report description file opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.report_comment_open_failed", { path = path },
      "Could not open report description file: " .. tostring(path)), true)
end

function ScreenReader.load_report_comment_file()
  local path = ScreenReader.report_comment_path()
  local text, err = ScreenReader.read_file(path)
  if not text then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.report_comment_read_failed",
      { error = tostring(err or "unknown error") },
      "Could not read report description: " .. tostring(err or "unknown error")),
      true)
    return
  end
  ScreenReader.set_report_comment(text, "a11y.sr.report_comment_loaded",
    "Report description loaded from file.")
end

function ScreenReader.clear_report_comment()
  ScreenReader.set_report_comment("", "a11y.sr.report_comment_cleared",
    "Report description cleared.")
end

function ScreenReader.parse_report_contact(text)
  local name, email = "", ""
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    line = AppController.trim_text(line:gsub("^%s*[Nn]ame:%s*", "")
      :gsub("^%s*[Ee]mail:%s*", ""))
    if line ~= "" then
      if line:find("@", 1, true) and email == "" then email = line
      elseif name == "" then name = line end
    end
  end
  return name, email
end

function ScreenReader.set_report_contact(name, email, status_key, fallback)
  S._screen_reader_report_name = tostring(name or "")
  S._screen_reader_report_email = tostring(email or "")
  if CFG and reaper.SetExtState then
    reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_name",
      S._screen_reader_report_name, true)
    reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_email",
      S._screen_reader_report_email, true)
  end
  ScreenReader.invalidate_report_preview()
  ScreenReader.refresh_report_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t(status_key, nil, fallback), true)
end

function ScreenReader.paste_report_contact()
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  local name, email = ScreenReader.parse_report_contact(text)
  if name == "" and email == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.report_contact_empty_clipboard",
      nil, "Clipboard does not contain a name or email."), true)
    return
  end
  ScreenReader.set_report_contact(name, email,
    "a11y.sr.report_contact_pasted", "Report contact pasted.")
end

function ScreenReader.open_report_contact_file()
  local path = ScreenReader.report_contact_path()
  local text = "Name: " .. ScreenReader.report_name()
    .. "\nEmail: " .. ScreenReader.report_email() .. "\n"
  local ok = ScreenReader.write_text_file(path, text)
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.report_contact_opened", { path = path },
      "Report contact file opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.report_contact_open_failed", { path = path },
      "Could not open report contact file: " .. tostring(path)), true)
end

function ScreenReader.load_report_contact_file()
  local path = ScreenReader.report_contact_path()
  local text, err = ScreenReader.read_file(path)
  if not text then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.report_contact_read_failed",
      { error = tostring(err or "unknown error") },
      "Could not read report contact: " .. tostring(err or "unknown error")),
      true)
    return
  end
  local name, email = ScreenReader.parse_report_contact(text)
  ScreenReader.set_report_contact(name, email,
    "a11y.sr.report_contact_loaded", "Report contact loaded from file.")
end

function ScreenReader.clear_report_contact()
  ScreenReader.set_report_contact("", "", "a11y.sr.report_contact_cleared",
    "Report contact cleared.")
end

function ScreenReader.report_preview_text()
  if not (Diag and Diag.uploader_enabled and Diag.begin_bug_report_draft
      and Diag.preview_bug_report_text) then
    return nil, ScreenReader.t("a11y.sr.report_unavailable", nil,
      "Issue reporting is not available in this build.")
  end
  if not S._screen_reader_report_draft then
    S._screen_reader_report_draft = Diag.begin_bug_report_draft()
  end
  return Diag.preview_bug_report_text(S._screen_reader_report_draft,
    ScreenReader.report_comment(), ScreenReader.report_name(),
    ScreenReader.report_email())
end

function ScreenReader.copy_report_preview()
  local text, err = ScreenReader.report_preview_text()
  local ok = text and AppController.copy_text(text)
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.report_preview_copied", nil,
      "Report preview copied to clipboard.")
    or tostring(err or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response.")), true)
end

function ScreenReader.save_report_preview()
  local text, err = ScreenReader.report_preview_text()
  local path = text and AppController.write_transcript(text,
    "ScreenReader_Report_Preview.json") or nil
  ScreenReader.set_status(path
    and ScreenReader.t("a11y.sr.report_preview_saved", { path = path },
      "Report preview saved to " .. tostring(path) .. ".")
    or tostring(err or ScreenReader.t("a11y.sr.save_failed", nil,
      "Could not save the response.")), true,
    path and ScreenReader.t("a11y.sr.report_preview_saved_short", nil,
      "Report preview saved.") or nil)
end

function ScreenReader.send_report()
  if AppController.trim_text(ScreenReader.report_comment()) == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.report_comment_required",
      nil, "Enter a report description before sending."), true)
    return
  end
  if not (Diag and Diag.uploader_enabled and Diag.send_bug_report
      and Diag.begin_bug_report_draft) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.report_unavailable", nil,
      "Issue reporting is not available in this build."), true)
    return
  end
  local email = ScreenReader.report_email()
  if email ~= "" and Diag.is_valid_email and not Diag.is_valid_email(email) then
    ScreenReader.set_status(ScreenReader.t("bug_report.email_invalid", nil,
      "Doesn't look like an email address."), true)
    return
  end
  local draft = S._screen_reader_report_draft or Diag.begin_bug_report_draft()
  S._screen_reader_report_draft = draft
  S._screen_reader_report_sending = true
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t("bug_report.status.sending", nil,
    "Sending..."), true)
  local event_id = draft.event_id
  Diag.send_bug_report(draft, ScreenReader.report_comment(),
    ScreenReader.report_name(), email,
    function(ok, status, err)
      if not S._screen_reader_report_draft
          or S._screen_reader_report_draft.event_id ~= event_id then
        return
      end
      S._screen_reader_report_sending = false
      if ok then
        S._screen_reader_report_comment = ""
        S._screen_reader_report_draft = nil
        ScreenReader.set_status(ScreenReader.t("bug_report.toast.sent", nil,
          "Bug report sent. Thanks!"), true)
      else
        ScreenReader.set_status(ScreenReader.t("bug_report.status.send_failed",
          { error = tostring(err or ("status " .. tostring(status))) },
          "Send failed: " .. tostring(err or ("status " .. tostring(status)))),
          true)
      end
      ScreenReader.refresh_report_summary()
      ScreenReader.refresh_actions()
    end)
end

function ScreenReader.feedback_state()
  return S and S._screen_reader_feedback or nil
end

function ScreenReader.feedback_comment()
  local fb = ScreenReader.feedback_state()
  return tostring((fb and fb.comment) or "")
end

function ScreenReader.feedback_flags()
  local fb = ScreenReader.feedback_state()
  return (fb and fb.flags) or {}
end

function ScreenReader.feedback_sentiment_text()
  local flags = ScreenReader.feedback_flags()
  if flags.thumbs_up then
    return ScreenReader.t("feedback.helpful", nil, "Helpful")
  end
  if flags.thumbs_down then
    return ScreenReader.t("feedback.not_helpful", nil, "Not helpful")
  end
  return ScreenReader.t("a11y.sr.feedback_sentiment_none", nil,
    "No rating selected")
end

function ScreenReader.feedback_comment_preview_text()
  local comment = ScreenReader.feedback_comment()
  return ScreenReader.t("a11y.sr.feedback_comment_preview", {
    text = comment ~= "" and ScreenReader.clean_label(comment, 220)
      or ScreenReader.t("a11y.sr.feedback_comment_empty", nil, "empty"),
  }, "Comment: " .. (comment ~= "" and ScreenReader.clean_label(comment, 220)
    or ScreenReader.t("a11y.sr.feedback_comment_empty", nil, "empty")))
end

function ScreenReader.feedback_summary_text()
  local fb = ScreenReader.feedback_state()
  if not fb then
    return ScreenReader.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about.")
  end
  return ScreenReader.t("a11y.sr.feedback_summary", {
    sentiment = ScreenReader.feedback_sentiment_text(),
  }, "Feedback for the latest response. Selected rating: "
    .. ScreenReader.feedback_sentiment_text() .. ".")
end

function ScreenReader.refresh_feedback_summary()
  local ui = S and S.screen_reader_ui or nil
  if not (ui and ui.ids) then return end
  ScreenReader.set_label(ui.ids.feedback_summary,
    ScreenReader.feedback_summary_text())
  ScreenReader.set_label(ui.ids.feedback_comment_preview,
    ScreenReader.feedback_comment_preview_text())
end

function ScreenReader.open_feedback(sentiment, payload)
  if AppController.request_is_active and AppController.request_is_active() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.request_already_running",
      nil, "A request is already running."), true)
    return
  end
  local ok, data
  if AppController.begin_feedback_for_latest then
    ok, data = AppController.begin_feedback_for_latest(sentiment, payload)
  end
  if not ok or type(data) ~= "table" then
    ScreenReader.set_status(tostring(data or ScreenReader.t(
      "a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build.")), true)
    return
  end
  S._screen_reader_feedback = {
    draft = data.draft,
    flags = data.flags,
    comment = "",
    target_idx = data.target_idx,
    sending = false,
  }
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.feedback_opened", nil,
    "Feedback opened. Review the details, then send when ready."), true)
  ScreenReader.open_view("feedback")
end

function ScreenReader.set_feedback_sentiment(sentiment)
  local fb = ScreenReader.feedback_state()
  if not fb then return end
  sentiment = tostring(sentiment or "")
  fb.flags = fb.flags or {}
  fb.flags.thumbs_up = sentiment == "up"
  fb.flags.thumbs_down = sentiment == "down"
  ScreenReader.refresh_feedback_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.feedback_sentiment_changed",
    { sentiment = ScreenReader.feedback_sentiment_text() },
    "Feedback rating changed to " .. ScreenReader.feedback_sentiment_text()
      .. "."), true)
  if S and S._screen_reader_view == "feedback" then
    ScreenReader.focus_after_rebuild(sentiment == "down"
      and "feedback_not_helpful" or "feedback_helpful")
    ScreenReader.open_view("feedback")
  end
end

function ScreenReader.set_feedback_flag(flag, checked)
  local fb = ScreenReader.feedback_state()
  if not fb then return end
  fb.flags = fb.flags or {}
  fb.flags[tostring(flag or "")] = checked == true
  ScreenReader.set_status(ScreenReader.t("a11y.sr.feedback_reason_changed",
    nil, "Feedback reason updated."), true)
end

function ScreenReader.set_feedback_comment(text, status_key, fallback)
  local fb = ScreenReader.feedback_state()
  if not fb then return end
  fb.comment = tostring(text or "")
  ScreenReader.refresh_feedback_summary()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t(status_key, nil, fallback), true)
end

function ScreenReader.feedback_comment_dialog()
  if not (reaper and reaper.GetUserInputs) then return nil, "unavailable" end
  local fb = ScreenReader.feedback_state()
  if not fb then return end
  local ok, accepted, text = pcall(reaper.GetUserInputs,
    ScreenReader.t("a11y.sr.feedback_comment_dialog_title", nil,
      "Response Feedback"),
    1,
    ScreenReader.t("a11y.sr.feedback_comment_dialog_caption", nil,
      "Feedback comment") .. ",extrawidth=300",
    ScreenReader.feedback_comment())
  if not ok then return nil, accepted end
  if not accepted then return false, "" end
  return true, tostring(text or "")
end

function ScreenReader.edit_feedback_comment()
  local ok, text_or_err = ScreenReader.feedback_comment_dialog()
  if ok == true then
    ScreenReader.set_feedback_comment(text_or_err,
      "a11y.sr.feedback_comment_updated",
      "Feedback comment updated.")
  elseif ok == false then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.feedback_comment_cancelled", nil,
      "Feedback comment unchanged."), true)
  else
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.feedback_comment_dialog_unavailable", nil,
      "Feedback comment dialog is not available."), true)
  end
end

function ScreenReader.feedback_preview_text()
  local fb = ScreenReader.feedback_state()
  if not fb then
    return nil, ScreenReader.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about.")
  end
  return AppController.feedback_preview_text(fb.draft, fb.comment, fb.flags)
end

function ScreenReader.send_feedback()
  local fb = ScreenReader.feedback_state()
  if not fb then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about."), true)
    return
  end
  if fb.sending then
    ScreenReader.set_status(ScreenReader.t("feedback.status.sending", nil,
      "Sending..."), true)
    return
  end
  fb.sending = true
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ScreenReader.t("feedback.status.sending", nil,
    "Sending..."), true)
  local event_id = fb.draft and fb.draft.event_id
  local ok, err = AppController.send_feedback(fb.draft, fb.comment, fb.flags,
    function(done_ok, status, send_err)
      local cur = ScreenReader.feedback_state()
      if not cur or not cur.draft or cur.draft.event_id ~= event_id then
        return
      end
      cur.sending = false
      if done_ok then
        S._screen_reader_feedback = nil
        ScreenReader.set_status_after_rebuild(ScreenReader.t(
          "feedback.toast.sent", nil, "Feedback sent. Thanks!"), true)
        ScreenReader.open_view("response_ready")
      else
        ScreenReader.set_status(ScreenReader.t("feedback.status.send_failed",
          { error = tostring(send_err or ("status " .. tostring(status))) },
          "Send failed: "
            .. tostring(send_err or ("status " .. tostring(status)))), true)
        ScreenReader.refresh_actions()
      end
    end)
  if not ok then
    fb.sending = false
    ScreenReader.set_status(tostring(err or ScreenReader.t(
      "a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build.")), true)
    ScreenReader.refresh_actions()
  end
end

function ScreenReader.set_status(text, should_announce, display_text)
  local ui = S and S.screen_reader_ui or nil
  local display = ScreenReader.clean_label(display_text or text, 90)
  if ui and ui.ids then
    ScreenReader.set_label(ui.ids.status, display)
    ScreenReader.set_label(ui.ids.reader, display)
  end
  if should_announce then ScreenReader.announce(text) end
end

function ScreenReader.refresh_menus()
  local ui = S and S.screen_reader_ui or nil
  if not (ui and ui.ids) then return end
  local labels, map, selected = ScreenReader.menu_from_provider_items()
  ui.provider_map = map
  ScreenReader.set_dropdown_items(ui.ids.provider, labels, selected)
  labels, map, selected = ScreenReader.menu_from_model_items()
  ui.model_map = map
  ScreenReader.set_dropdown_items(ui.ids.model, labels, selected)
  labels, map, selected = ScreenReader.menu_from_thinking_items()
  ui.thinking_map = map
  ScreenReader.set_dropdown_items(ui.ids.thinking, labels, selected)
end

function ScreenReader.refresh_mode_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    ScreenReader.set_label(ui.ids.mode_summary, ScreenReader.mode_summary_text())
    ScreenReader.set_checkbox(ui.ids.auto_run, prefs and prefs.auto_run)
    ScreenReader.set_checkbox(ui.ids.auto_backup, prefs and prefs.auto_backup)
  end
end

function ScreenReader.set_status_after_rebuild(text, should_announce)
  if not S then return end
  S._screen_reader_after_rebuild_status = {
    text = tostring(text or ""),
    announce = should_announce == true,
  }
end

function ScreenReader.announce_after_rebuild(text)
  if not S then return end
  S._screen_reader_after_rebuild_announcement = tostring(text or "")
end

function ScreenReader.announce_after_rebuild_settled(text)
  if not S then return end
  S._screen_reader_after_gui_announcement = {
    text = tostring(text or ""),
    cycles = 2,
  }
end

function ScreenReader.default_focus_for_view(view)
  view = tostring(view or "main")
  local defaults = {
    main = "prompt_input",
    prompt_edit = "prompt_input",
    response_ready = {
      "undo_edit", "run_code", "read_code", "read_response",
      "copy_response", "new_prompt", "main",
    },
    reader = {
      "undo_run", "copy", "save", "run_code", "new_prompt",
      "response_ready", "main", "body_line_1",
    },
    thinking = "cancel_request",
    help = "help_manual",
    settings = "api_keys",
    api_keys = { "api_key_input", "api_key_provider", "continue_main" },
    update_prompt = "apply_update",
    visual_switch_confirm = "open_visual_now",
  }
  return defaults[view]
end

function ScreenReader.focus_after_rebuild(element_key)
  if not S then return end
  if type(element_key) == "table" then
    S._screen_reader_focus_after_rebuild = element_key
  else
    S._screen_reader_focus_after_rebuild = tostring(element_key or "")
  end
end

function ScreenReader.apply_focus_after_rebuild()
  if not S then return end
  local keys = S._screen_reader_focus_after_rebuild
  S._screen_reader_focus_after_rebuild = nil
  local ui = S.screen_reader_ui or nil
  if not (ui and ui.ids and reagirl and reagirl.UI_Element_SetFocused) then
    return
  end
  -- ReaGirl can leave this private sentinel nil before the first UI loop.
  -- Re-vet this fallback whenever the pinned ReaGirl version changes.
  if reagirl.Elements and reagirl.Elements.FocusedElement == nil then
    reagirl.Elements.FocusedElement = 0
  end
  if type(keys) ~= "table" then keys = { tostring(keys or "") } end
  for _, key in ipairs(keys) do
    key = tostring(key or "")
    local id = key ~= "" and ui.ids[key] or nil
    if id then
      pcall(reagirl.UI_Element_SetFocused, id)
      return
    end
  end
end

function ScreenReader.set_auto_run(checked)
  AppController.set_auto_run(checked == true)
  ScreenReader.refresh_mode_summary()
  ScreenReader.set_status(checked
    and ScreenReader.t("a11y.sr.auto_run_on", nil,
      "Auto-run is on. Generated actions can run automatically after validation.")
    or ScreenReader.t("a11y.sr.auto_run_off", nil,
      "Auto-run is off. Generated actions will wait for review."), true)
end

function ScreenReader.set_auto_backup(checked)
  AppController.set_auto_backup(checked == true)
  ScreenReader.refresh_mode_summary()
  ScreenReader.set_status(checked
    and ScreenReader.t("a11y.sr.auto_backup_on", nil, "Auto-backup is on.")
    or ScreenReader.t("a11y.sr.auto_backup_off", nil, "Auto-backup is off."),
    true)
end

function ScreenReader.refresh_actions(opts)
  local ui = S and S.screen_reader_ui or nil
  if not (ui and ui.ids) then return end
  opts = type(opts) == "table" and opts or nil
  local now = reaper and reaper.time_precise and reaper.time_precise() or nil
  if opts and opts.throttle then
    local interval = tonumber(opts.interval) or 0.35
    local next_at = tonumber(S._screen_reader_next_action_refresh_at) or 0
    if now and now < next_at then return false end
    if now then S._screen_reader_next_action_refresh_at = now + interval end
  elseif now then
    S._screen_reader_next_action_refresh_at = now + 0.35
  end
  local request_active = AppController.request_is_active()
  local provider_ready = AppController.active_provider_is_usable()
  local has_attachments = AppController.attachment_count
    and AppController.attachment_count() > 0
  local attachments_ready = AppController.attachments_ready
    and AppController.attachments_ready()
  local prompt_ready = ScreenReader.current_prompt() ~= "" or has_attachments
  local send_disabled = request_active or not provider_ready or not prompt_ready
    or not attachments_ready
  ScreenReader.set_button_disabled(ui.ids.send, send_disabled)
  ScreenReader.set_button_disabled(ui.ids.cancel_request, not request_active)
  if ui.ids.send_state then
    local text
    if request_active then
      text = ScreenReader.t("a11y.sr.send_state_waiting", nil,
        "A request is already running.")
    elseif has_attachments and not attachments_ready then
      text = ScreenReader.t("a11y.sr.send_state_attachments", nil,
        "Attachments are still encoding.")
    elseif not provider_ready then
      text = ScreenReader.t("a11y.sr.send_state_provider", nil,
        "Selected provider needs setup before sending.")
    elseif not prompt_ready then
      text = ScreenReader.t("a11y.sr.send_state_prompt", nil,
        "Enter a prompt first.")
    else
      text = ScreenReader.t("a11y.sr.send_state_ready", nil,
        "Ready. Press Enter on Prompt, then OK, to send.")
    end
    ScreenReader.set_label(ui.ids.send_state, text)
  end
  local payload = AppController.latest_response_payload()
  ScreenReader.set_label(ui.ids.response_state,
    ScreenReader.response_state_text(request_active, payload))
  local has_text = payload and ScreenReader.response_prose_text(payload) ~= ""
  local has_code = payload and payload.has_code == true
  ScreenReader.set_button_disabled(ui.ids.read_response, not has_text)
  ScreenReader.set_button_disabled(ui.ids.copy_response, not has_text)
  ScreenReader.set_button_disabled(ui.ids.read_code, not has_code)
  ScreenReader.set_button_disabled(ui.ids.request_lua,
    request_active
      or not ScreenReader.payload_is_typed_action(payload)
      or not ScreenReader.payload_can_undo(payload))
  ScreenReader.set_button_disabled(ui.ids.apply_plan,
    request_active
      or not ScreenReader.payload_is_typed_action(payload)
      or not has_code
      or ScreenReader.payload_can_undo(payload))
  local run_info = AppController.latest_code_run_info
    and AppController.latest_code_run_info() or nil
  local is_jsfx = ScreenReader.payload_is_jsfx(payload)
  ScreenReader.set_button_disabled(ui.ids.run_code,
    request_active or (is_jsfx and not has_code)
      or (not is_jsfx and not (run_info and run_info.can_run)))
  ScreenReader.set_button_disabled(ui.ids.copy_code, not has_code)
  ScreenReader.set_button_disabled(ui.ids.save_code, not has_code)
  local feedback_ready = AppController.feedback_available
    and AppController.feedback_available()
    and AppController.feedback_target_available
    and AppController.feedback_target_available(payload)
  ScreenReader.set_button_disabled(ui.ids.feedback_up,
    request_active or not feedback_ready)
  ScreenReader.set_button_disabled(ui.ids.feedback_down,
    request_active or not feedback_ready)
  local has_chat = AppController.conversation_has_content
    and AppController.conversation_has_content()
  ScreenReader.set_button_disabled(ui.ids.copy_chat, not has_chat)
  ScreenReader.set_button_disabled(ui.ids.save_chat, not has_chat)
  ScreenReader.set_button_disabled(ui.ids.clear_chat, request_active or not has_chat)
  ScreenReader.set_button_disabled(ui.ids.remove_last, not has_attachments)
  ScreenReader.set_button_disabled(ui.ids.clear_attachments, not has_attachments)
  if AppController.update_is_busy then
    local update_busy = AppController.update_is_busy()
    ScreenReader.set_button_disabled(ui.ids.check_updates, update_busy)
    ScreenReader.set_button_disabled(ui.ids.update_later, update_busy)
  end
  if AppController.update_can_apply then
    ScreenReader.set_button_disabled(ui.ids.apply_update,
      not AppController.update_can_apply())
  end
  local key_test_active = S and S._screen_reader_key_test_active == true
  local key_status = AppController.active_provider_key_status
    and AppController.active_provider_key_status() or nil
  local key_configured = key_status and key_status.configured == true
  local key_console = key_status and key_status.console_url
    and tostring(key_status.console_url) ~= ""
  ScreenReader.set_input_disabled(ui.ids.api_key_input, key_test_active)
  ScreenReader.set_button_disabled(ui.ids.test_key,
    key_test_active or request_active or not key_configured)
  ScreenReader.set_button_disabled(ui.ids.clear_key,
    key_test_active or not key_configured)
  ScreenReader.set_button_disabled(ui.ids.open_console, not key_console)
  ScreenReader.set_button_disabled(ui.ids.continue_main,
    key_test_active or request_active or not ScreenReader.has_usable_provider())
  local pref_scan_busy = pref_plugins and pref_plugins.scan
    and pref_plugins.scan.active == true
  ScreenReader.set_button_disabled(ui.ids.save_pref_plugins, pref_scan_busy)
  ScreenReader.set_button_disabled(ui.ids.save_scan_pref_plugins, pref_scan_busy)
  ScreenReader.set_button_disabled(ui.ids.rescan_pref_plugins, pref_scan_busy)
  ScreenReader.set_button_disabled(ui.ids.clear_all_pref_plugins, pref_scan_busy)
  local report_busy = S and S._screen_reader_report_sending == true
  local report_ready = AppController.trim_text(ScreenReader.report_comment()) ~= ""
  ScreenReader.set_button_disabled(ui.ids.send_report,
    report_busy or not report_ready)
  ScreenReader.set_button_disabled(ui.ids.copy_report_preview, report_busy)
  ScreenReader.set_button_disabled(ui.ids.save_report_preview, report_busy)
  ScreenReader.set_button_disabled(ui.ids.clear_report_comment,
    report_busy or not report_ready)
  ScreenReader.set_button_disabled(ui.ids.clear_report_contact, report_busy
    or (ScreenReader.report_name() == "" and ScreenReader.report_email() == ""))
  local feedback = S and S._screen_reader_feedback or nil
  local feedback_busy = feedback and feedback.sending == true
  ScreenReader.set_button_disabled(ui.ids.feedback_helpful, feedback_busy)
  ScreenReader.set_button_disabled(ui.ids.feedback_not_helpful, feedback_busy)
  ScreenReader.set_button_disabled(ui.ids.edit_feedback_comment,
    feedback_busy or not feedback)
  ScreenReader.set_button_disabled(ui.ids.send_feedback,
    feedback_busy or not feedback)
  ScreenReader.refresh_attachment_summary()
  ScreenReader.refresh_update_status()
  ScreenReader.refresh_report_summary()
  ScreenReader.refresh_feedback_summary()
  ScreenReader.track_pref_plugin_scan()
  ScreenReader.track_fx_cache_scan()
  return true
end

function ScreenReader.refresh_status(prefix, should_announce)
  ScreenReader.set_status(ScreenReader.status_text(prefix), should_announce)
  ScreenReader.refresh_actions()
end

function ScreenReader.select_provider(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local provider_idx = ui and ui.provider_map and ui.provider_map[menu_idx]
  local ok = provider_idx and AppController.select_provider_idx(provider_idx)
  if not ok then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.invalid_provider", nil,
      "That provider cannot be selected."), true)
    return
  end
  ScreenReader.refresh_menus()
  ScreenReader.refresh_status(ScreenReader.t("a11y.sr.provider_changed", nil,
    "Provider changed."), true)
end

function ScreenReader.select_model(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local model_idx = ui and ui.model_map and ui.model_map[menu_idx]
  local ok = model_idx and AppController.select_model_idx(model_idx)
  if not ok then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.invalid_model", nil,
      "That model cannot be selected."), true)
    ScreenReader.refresh_menus()
    return
  end
  ScreenReader.refresh_menus()
  ScreenReader.refresh_status(ScreenReader.t("a11y.sr.model_changed", nil,
    "Model changed."), true)
end

function ScreenReader.select_thinking(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local thinking_idx = ui and ui.thinking_map and ui.thinking_map[menu_idx]
  local ok = thinking_idx and AppController.select_thinking_idx(thinking_idx)
  if not ok then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.invalid_thinking", nil,
      "That thinking level cannot be selected."), true)
    ScreenReader.refresh_menus()
    return
  end
  ScreenReader.refresh_status(ScreenReader.t("a11y.sr.thinking_changed", nil,
    "Thinking level changed."), true)
end

function ScreenReader.send_current_prompt()
  if Log and Log.line then
    local p = AppController.active_provider and AppController.active_provider()
      or nil
    Log.line("A11Y", "screen reader send invoked; provider="
      .. tostring(p and p.id or "unknown")
      .. " usable=" .. tostring(AppController.active_provider_is_usable
        and AppController.active_provider_is_usable() or false)
      .. " prompt_bytes=" .. tostring(#ScreenReader.current_prompt()))
  end
  if AppController.request_is_active() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.request_already_running",
      nil, "A request is already running."), true)
    return
  end
  local prompt = ScreenReader.current_prompt()
  local has_attachments = AppController.attachment_count
    and AppController.attachment_count() > 0
  if prompt == "" and not has_attachments then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.empty_prompt", nil,
      "No prompt was entered."), true)
    return
  end
  local ok, err = AppController.send_prompt(prompt)
  if not ok then
    local msg
    if err == "provider_not_configured" then
      msg = ScreenReader.t("a11y.sr.provider_not_configured", nil,
        "The selected provider needs an API key before ReaAssist can send.")
    elseif err == "attachments_not_ready" then
      msg = ScreenReader.t("a11y.sr.send_state_attachments", nil,
        "Send unavailable: attachments are still encoding.")
    else
      msg = ScreenReader.t("a11y.sr.send_failed", {
        error = tostring(err or "unknown error"),
      }, "Could not send request: " .. tostring(err or "unknown error"))
    end
    ScreenReader.set_status(msg, true)
    return
  end
  S._screen_reader_request_active = true
  S._screen_reader_last_msg_idx = #S.display_messages
  if reaper and reaper.time_precise then
    local now = reaper.time_precise()
    S._screen_reader_request_started_at = now
    S._screen_reader_next_request_announcement_at = now + 20
  else
    S._screen_reader_request_started_at = nil
    S._screen_reader_next_request_announcement_at = nil
  end
  ScreenReader.refresh_actions()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.thinking_wait", nil,
    "Thinking. Please wait. Responses can take up to a minute."), true)
  ScreenReader.open_view("thinking")
end

function ScreenReader.cancel_request()
  local ok = AppController.cancel_request and AppController.cancel_request()
  S._screen_reader_request_active = false
  S._screen_reader_next_request_announcement_at = nil
  S._screen_reader_request_started_at = nil
  ScreenReader.refresh_actions()
  if S and S._screen_reader_view == "thinking" then
    ScreenReader.set_status_after_rebuild(ok
      and ScreenReader.t("a11y.sr.request_cancelled", nil,
        "Request cancelled.")
      or ScreenReader.t("a11y.sr.no_request_to_cancel", nil,
        "There is no active request to cancel."), true)
    ScreenReader.open_view("main")
    return
  end
  if ok then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.request_cancelled", nil,
      "Request cancelled."), true)
  else
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_request_to_cancel", nil,
      "There is no active request to cancel."), true)
  end
end

function ScreenReader.reader_payload(kind)
  kind = kind == "code" and "code" or "response"
  local payload = AppController.latest_response_payload()
  local text = ""
  local empty_key = "a11y.sr.no_response"
  local empty_fallback = "ReaAssist finished, but no readable response was found."
  local label = ScreenReader.t("a11y.sr.response_body", nil, "Response")
  local meaning = ScreenReader.t("a11y.sr.response_body.meaning", nil,
    "Full text of the latest ReaAssist response.")
  if kind == "code" then
    text = payload and payload.code or ""
    empty_key = "a11y.sr.no_code_to_copy"
    empty_fallback = "There is no generated code to copy."
    if ScreenReader.payload_is_typed_action(payload) then
      label = ScreenReader.t("a11y.sr.action_plan_body", nil,
        "Edit details")
      meaning = ScreenReader.t("a11y.sr.action_plan_body.meaning", nil,
        "Preview of the edit details from the latest ReaAssist response.")
    else
      label = ScreenReader.t("a11y.sr.code_body", nil,
        "Generated code preview")
      meaning = ScreenReader.t("a11y.sr.code_body.meaning", nil,
        "Preview of generated code from the latest ReaAssist response.")
    end
  else
    text = ScreenReader.response_prose_text(payload)
    local details_text = ScreenReader.response_details_text(payload)
    if details_text ~= "" then
      text = text ~= "" and (text .. "\n\n" .. details_text) or details_text
    end
    if payload and payload.has_code then
      label = ScreenReader.t("a11y.sr.response_notes_body", nil,
        "Response notes")
      meaning = ScreenReader.t("a11y.sr.response_notes_body.meaning", nil,
        "Non-code notes from the latest ReaAssist response.")
    end
    if text == "" and payload and payload.has_code then
      if ScreenReader.payload_is_typed_action(payload) then
        empty_key = "a11y.sr.response_no_prose_has_action_plan"
        empty_fallback =
          "This response contains edit details but no separate prose response. Use Review Edit Details to review them, Run Edit to apply them, or Request Lua to get a reusable script."
      else
        empty_key = "a11y.sr.response_no_prose_has_code"
        empty_fallback =
          "This response contains generated code but no separate prose response. Use Read or Save Code to review the generated code."
      end
    end
  end
  if text == "" then text = ScreenReader.t(empty_key, nil, empty_fallback) end
  return {
    kind = kind,
    payload = payload,
    text = text,
    label = label,
    meaning = meaning,
  }
end

function ScreenReader.preview_lines(text, is_code, width, max_lines,
    shortened_text)
  text = tostring(text or "")
  width = tonumber(width) or 96
  max_lines = tonumber(max_lines) or 14
  local all, truncated = {}, false
  local function add_candidate(line)
    all[#all + 1] = line ~= "" and line or " "
  end
  local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  for raw in (normalized .. "\n"):gmatch("([^\n]*)\n") do
    if is_code then
      local line = raw:gsub("\t", "  ")
      if line:match("^%s*$") then line = "" end
      if #line > width then
        line = line:sub(1, width) .. "..."
        truncated = true
      end
      if line ~= "" then
        add_candidate(line)
      end
    else
      local wrapped = ScreenReader.wrap_text(raw, width)
      for line in (wrapped .. "\n"):gmatch("([^\n]*)\n") do
        add_candidate(line)
      end
    end
  end
  if #all > max_lines then truncated = true end
  local out = {}
  for i = 1, math.min(#all, max_lines) do
    out[#out + 1] = all[i]
  end
  if #out == 0 then
    out[1] = ScreenReader.t("a11y.sr.reader_empty", nil,
      "There is nothing to read.")
  end
  if truncated then
    if shortened_text ~= false then
      out[#out + 1] = shortened_text or ScreenReader.t(
        "a11y.sr.reader_preview_shortened", nil,
        "Preview shortened. Use Copy for the full text.")
    end
  end
  return out
end

function ScreenReader.code_preview_info(text, width, max_lines)
  text = tostring(text or "")
  width = tonumber(width) or 100
  max_lines = tonumber(max_lines) or 10
  local total, has_long_line = 0, false
  local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  for raw in (normalized .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw:gsub("\t", "  ")
    if not line:match("^%s*$") then
      total = total + 1
      if #line > width then has_long_line = true end
    end
  end
  return {
    total = total,
    shown = math.min(total, max_lines),
    shortened = total > max_lines or has_long_line,
  }
end

function ScreenReader.open_reader(kind)
  kind = kind == "code" and "code" or "response"
  S._screen_reader_reader_kind = kind
  ScreenReader.open_view("reader")
end

function ScreenReader.copy_reader()
  local data = ScreenReader.reader_payload(S and S._screen_reader_reader_kind)
  local ok = data.text ~= "" and AppController.copy_text(data.text)
  local typed_action = data.kind == "code"
    and ScreenReader.payload_is_typed_action(data.payload)
  local is_jsfx = data.kind == "code"
    and ScreenReader.payload_is_jsfx(data.payload)
  local key = typed_action and "a11y.sr.action_plan_copied"
    or is_jsfx and "a11y.sr.jsfx_copied"
    or data.kind == "code" and "a11y.sr.code_copied"
    or "a11y.sr.response_copied"
  local fallback = typed_action and "Edit details copied to clipboard."
    or is_jsfx and "JSFX copied to clipboard."
    or data.kind == "code" and "Generated code copied to clipboard."
    or "Response copied to clipboard."
  ScreenReader.set_status(ok and ScreenReader.t(key, nil, fallback)
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.should_offer_add_to_actions(payload)
  return payload and payload.code_type == "lua"
    and not ScreenReader.payload_is_typed_action(payload)
end

function ScreenReader.offer_add_saved_script(path, payload)
  if S and S._screen_reader_last_code_save_status then return false end
  if not (path and ScreenReader.should_offer_add_to_actions(payload)) then
    return false
  end
  S._screen_reader_saved_script_path = path
  S._screen_reader_add_actions_return_view = S._screen_reader_view or "reader"
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.code_saved_add_actions", { path = path },
    "Generated code saved. Choose Add to Actions if you want this script in REAPER's Actions list."),
    true)
  ScreenReader.open_view("add_actions_confirm")
  return true
end

function ScreenReader.code_save_status_text(path)
  local status = S and S._screen_reader_last_code_save_status or nil
  if not (path and status and status.path == path) then return nil end

  local action_name = tostring(status.action_name or status.filename or path)
  if status.add_ok then
    return ScreenReader.t("a11y.sr.code_saved_actions", {
        path = path,
        name = action_name,
      }, "Generated code saved to " .. tostring(path)
        .. " and added to the REAPER Actions list as " .. action_name .. "."),
      ScreenReader.t("a11y.sr.code_saved_actions_short", {
        name = action_name,
      }, "Saved to Actions list as " .. action_name .. ".")
  end

  local error_text = tostring(status.add_msg or "")
  return ScreenReader.t("a11y.sr.code_saved_actions_failed", {
      path = path,
      name = action_name,
      error = error_text,
    }, "Generated code saved to " .. tostring(path)
      .. " as " .. action_name
      .. ", but ReaAssist could not add it to the REAPER Actions list."),
    ScreenReader.t("a11y.sr.code_saved_actions_failed_short", {
      name = action_name,
    }, "Saved as " .. action_name .. ", but not added to Actions.")
end

function ScreenReader.confirm_code_save_status(path)
  local status = S and S._screen_reader_last_code_save_status or nil
  if not (path and status and status.path == path) then return false end

  local action_name = tostring(status.action_name or status.filename or path)
  local title = ScreenReader.t("a11y.sr.code_saved_title", nil, "Code Saved")
  local message
  if status.add_ok then
    message = ScreenReader.t("a11y.sr.code_saved_actions_alert", {
      path = path,
      name = action_name,
    }, "Saved and added to REAPER Actions.\n\nAction: " .. action_name
      .. "\nFile: " .. tostring(path))
  else
    message = ScreenReader.t("a11y.sr.code_saved_actions_failed_alert", {
      path = path,
      name = action_name,
      error = tostring(status.add_msg or ""),
    }, "Saved, but could not add to REAPER Actions.\n\nAction: "
      .. action_name .. "\nFile: " .. tostring(path))
  end

  if reaper.ShowMessageBox then
    pcall(reaper.ShowMessageBox, message, title, 0)
  else
    ScreenReader.announce(message)
  end

  local status_text, display_text = ScreenReader.code_save_status_text(path)
  ScreenReader.set_status(status_text or message, false, display_text)
  return true
end

function ScreenReader.save_reader()
  local data = ScreenReader.reader_payload(S and S._screen_reader_reader_kind)
  local path
  if data.kind == "code" then
    local payload = data.payload or {}
    if ScreenReader.payload_is_jsfx(payload) then
      ScreenReader.save_latest_jsfx()
      return
    end
    path = AppController.write_code(payload.code or "", payload.code_type)
  else
    path = AppController.write_transcript(data.text)
  end
  local typed_action = data.kind == "code"
    and ScreenReader.payload_is_typed_action(data.payload)
  local ok_key = typed_action and "a11y.sr.action_plan_saved"
    or data.kind == "code" and "a11y.sr.code_saved"
    or "a11y.sr.response_saved"
  local ok_fallback = typed_action
    and ("Edit details saved to " .. tostring(path) .. ".")
    or data.kind == "code"
    and ("Generated code saved to " .. tostring(path) .. ".")
    or ("Response saved to " .. tostring(path) .. ".")
  local fail_key = typed_action and "a11y.sr.action_plan_save_failed"
    or data.kind == "code" and "a11y.sr.code_save_failed"
    or "a11y.sr.save_failed"
  local fail_fallback = typed_action
    and "Could not save the edit details."
    or data.kind == "code"
    and "Could not save the generated code."
    or "Could not save the response."
  local display_key = typed_action and "a11y.sr.action_plan_saved_short"
    or data.kind == "code" and "a11y.sr.code_saved_short"
    or "a11y.sr.response_saved_short"
  local display_fallback = typed_action and "Edit details saved."
    or data.kind == "code" and "Generated code saved."
    or "Response saved."
  if data.kind == "code" and ScreenReader.confirm_code_save_status(path) then
    return
  end
  if ScreenReader.offer_add_saved_script(path, data.payload) then return end
  ScreenReader.set_status(path and ScreenReader.t(ok_key, { path = path },
      ok_fallback)
    or ScreenReader.t(fail_key, nil, fail_fallback), true,
    path and ScreenReader.t(display_key, nil, display_fallback) or nil)
end

function ScreenReader.copy_chat()
  if not (AppController.conversation_has_content
      and AppController.conversation_has_content()) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_chat_to_copy", nil,
      "There is no chat to copy."), true)
    return
  end
  local text = AppController.chat_transcript_text()
  local ok = text ~= "" and AppController.copy_text(text)
  ScreenReader.set_status(ok and ScreenReader.t("footer.copy.toast", nil,
    "Chat copied to clipboard")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.save_chat()
  if not (AppController.conversation_has_content
      and AppController.conversation_has_content()) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_chat_to_save", nil,
      "There is no chat to save."), true)
    return
  end
  local text = AppController.chat_transcript_text()
  local path = text ~= "" and AppController.write_transcript(text,
    "ScreenReader_Chat_Log.txt") or nil
  ScreenReader.set_status(path and ScreenReader.t("a11y.sr.chat_saved", {
      path = path,
    }, "Chat log saved to " .. tostring(path) .. ".")
    or ScreenReader.t("a11y.sr.chat_save_failed", nil,
      "Could not save the chat log."), true,
    path and ScreenReader.t("a11y.sr.chat_saved_short", nil,
      "Chat log saved.") or nil)
end

function ScreenReader.show_response()
  local payload = AppController.latest_response_payload()
  local text = ScreenReader.response_prose_text(payload)
  if text == "" then
    if payload and payload.has_code and payload.code and payload.code ~= "" then
      ScreenReader.set_status_after_rebuild(ScreenReader.t(
        "a11y.sr.response_no_prose_open_code", nil,
        "This response contains generated code but no separate prose response. Opening generated code."), true)
      ScreenReader.open_reader("code")
      return
    end
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_response", nil,
      "ReaAssist finished, but no readable response was found."), true)
    return
  end
  ScreenReader.open_reader("response")
end

function ScreenReader.copy_response()
  local payload = AppController.latest_response_payload()
  local text = ScreenReader.response_prose_text(payload)
  local ok = text ~= "" and AppController.copy_text(text)
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.response_copied", nil,
      "Response copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.save_response()
  local payload = AppController.latest_response_payload()
  local text = ScreenReader.response_prose_text(payload)
  local path = text ~= "" and AppController.write_transcript(text) or nil
  ScreenReader.set_status(path
    and ScreenReader.t("a11y.sr.response_saved", { path = path },
      "Response saved to " .. tostring(path) .. ".")
    or ScreenReader.t("a11y.sr.save_failed", nil,
      "Could not save the response."), true,
    path and ScreenReader.t("a11y.sr.response_saved_short", nil,
      "Response saved.") or nil)
end

function ScreenReader.show_code()
  local payload = AppController.latest_response_payload()
  local code = payload and payload.code or ""
  if code == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_code_to_copy", nil,
      "There is no generated code to copy."), true)
    return
  end
  ScreenReader.open_reader("code")
end

function ScreenReader.copy_code()
  local payload = AppController.latest_response_payload()
  local code = payload and payload.code or ""
  local ok = code ~= "" and AppController.copy_text(code)
  ScreenReader.set_status(ok
    and (ScreenReader.payload_is_jsfx(payload)
      and ScreenReader.t("a11y.sr.jsfx_copied", nil,
        "JSFX copied to clipboard.")
      or ScreenReader.t("a11y.sr.code_copied", nil,
        "Generated code copied to clipboard."))
    or ScreenReader.t("a11y.sr.no_code_to_copy", nil,
      "There is no generated code to copy."), true)
end

function ScreenReader.save_code()
  local payload = AppController.latest_response_payload()
  local code = payload and payload.code or ""
  if ScreenReader.payload_is_jsfx(payload) then
    ScreenReader.save_latest_jsfx()
    return
  end
  local path = code ~= "" and AppController.write_code(code, payload.code_type)
    or nil
  if ScreenReader.confirm_code_save_status(path) then return end
  if ScreenReader.offer_add_saved_script(path, payload) then return end
  ScreenReader.set_status(path
    and ScreenReader.t("a11y.sr.code_saved", { path = path },
      "Generated code saved to " .. tostring(path) .. ".")
    or ScreenReader.t("a11y.sr.code_save_failed", nil,
      "Could not save the generated code."), true,
    path and ScreenReader.t("a11y.sr.code_saved_short", nil,
      "Generated code saved.") or nil)
end

function ScreenReader.jsfx_saved_path_valid(msg)
  local path = tostring(msg and msg.jsfx_saved_path or "")
  if path == "" then return false end
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  if msg then
    msg.jsfx_saved_path = nil
    msg.jsfx_saved_fx_name = nil
  end
  return false
end

function ScreenReader.jsfx_manual_validation_source(code)
  code = tostring(code or "")
  if not code:find("// --- ReaAssist output ceiling", 1, true) then
    return code
  end

  local out = {}
  local in_injected_block = false
  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("// --- ReaAssist output ceiling", 1, true) then
      in_injected_block = true
    elseif in_injected_block then
      if line:find("// ----------------------------------------------------------",
          1, true) then
        in_injected_block = false
      end
    else
      local cleaned = line:gsub("%s*gmem=ReaAssist_Ceiling", "")
      if cleaned:match("^%s*options:%s*$") then
        cleaned = nil
      elseif cleaned:find("Safety Output Ceiling (dBFS)", 1, true)
          and cleaned:match("^%s*slider%d+:") then
        cleaned = nil
      end
      if cleaned ~= nil then out[#out + 1] = cleaned end
    end
  end
  return table.concat(out, "\n")
end

function ScreenReader.jsfx_fatal_code_summary(findings)
  local codes, seen = {}, {}
  for _, f in ipairs(findings or {}) do
    if f.severity == "fatal" then
      local code = tostring(f.code or "jsfx")
      if not seen[code] then
        seen[code] = true
        codes[#codes + 1] = code
      end
    end
  end
  return (#codes > 0) and table.concat(codes, ", ") or "jsfx"
end

function ScreenReader.jsfx_finding_detail(findings)
  local fatal, warn = {}, {}
  for _, f in ipairs(findings or {}) do
    local line = f.line and ("line " .. tostring(f.line) .. ": ") or ""
    local text = "[" .. tostring(f.code or "jsfx") .. "] "
      .. line .. tostring(f.message or "")
    if f.severity == "fatal" then
      fatal[#fatal + 1] = text
    else
      warn[#warn + 1] = text
    end
  end
  local parts = {}
  if #fatal > 0 then parts[#parts + 1] = table.concat(fatal, "\n") end
  if #warn > 0 then
    parts[#parts + 1] = "Advisory:\n" .. table.concat(warn, "\n")
  end
  return table.concat(parts, "\n\n")
end

function ScreenReader.jsfx_ceiling_info_from_code(code)
  code = tostring(code or "")
  local slot = tonumber(code:match("_ra_slot%s*=%s*(%d+)%s*;"))
  if not slot then return nil end
  return {
    slot_base = slot,
    desc = code:match("^%s*desc:%s*(.-)%s*[\r\n]") or "",
  }
end

function ScreenReader.record_jsfx_ceiling_slot(msg, info, saved_path, code)
  if not (msg and saved_path and Code and Code.ceiling_record_slot) then
    return
  end
  info = info or msg.ceiling_inject_info
    or ScreenReader.jsfx_ceiling_info_from_code(code)
  if not (info and info.slot_base) then return end
  msg._ceiling_recorded_paths = msg._ceiling_recorded_paths or {}
  local key = tostring(saved_path) .. "#" .. tostring(info.slot_base)
  if msg._ceiling_recorded_paths[key] then return end
  Code.ceiling_record_slot(info, saved_path, info.desc)
  msg._ceiling_recorded_paths[key] = true
end

function ScreenReader.prepare_jsfx_for_save(payload, msg, allow_invalid)
  local code = tostring(payload and payload.code or "")
  if code == "" or not (Code and Code.auto_save_jsfx) then
    return nil, nil, ScreenReader.t("jsfx.save_failed", nil,
      "Failed to save JSFX.")
  end

  if not allow_invalid
     and Code.validate_jsfx and Code.jsfx_findings_have_gate then
    local validation_code = ScreenReader.jsfx_manual_validation_source(code)
    local findings = Code.validate_jsfx(validation_code,
      tostring(msg and msg.jsfx_user_text or ""))
    if findings and Code.jsfx_findings_have_gate(findings) then
      local codes = ScreenReader.jsfx_fatal_code_summary(findings)
      return nil, nil, ScreenReader.t("validator.jsfx_safety_blocked_no_retry", {
        codes = codes,
      }, "The generated JSFX failed ReaAssist's safety/syntax validator: "
        .. codes .. ". It was not saved."),
        ScreenReader.jsfx_finding_detail(findings)
    end
  end

  local inject_info = nil
  if Code.inject_output_ceiling then
    local injected, info_or_reason = Code.inject_output_ceiling(code)
    if injected then
      code = injected
      inject_info = info_or_reason
      if payload then payload.code = code end
      if msg then
        msg.code_block = code
        msg.jsfx_saved_path = nil
        msg.jsfx_saved_fx_name = nil
        msg.ceiling_injected = true
        msg.ceiling_inject_info = inject_info
      end
    end
  end
  return code, inject_info, nil
end

function ScreenReader.confirm_invalid_jsfx_save(detail, action)
  detail = tostring(detail or "")
  local intro = ScreenReader.t("modal.jsfx_save.intro", nil,
    "This JSFX failed ReaAssist's safety/syntax validator:")
  local outro = ScreenReader.t("modal.jsfx_save.outro", nil,
    "Saving or adding it can write unsafe effect code to disk or load it "
    .. "on selected tracks. ReaAssist will still apply the output ceiling "
    .. "first when possible.")
  local action_text = action == "add"
    and "Choose Yes to add it anyway, or No to cancel."
    or "Choose Yes to save it anyway, or No to cancel."
  local message = intro .. "\n\n" .. detail .. "\n\n" .. outro
    .. "\n\n" .. action_text
  local response = reaper.ShowMessageBox
    and reaper.ShowMessageBox(message, "Review Before Saving", 4) or 7
  return response == 6
end

function ScreenReader.save_jsfx_for_payload(payload, allow_invalid)
  local msg = ScreenReader.payload_jsfx_message(payload)
  if not msg then
    return nil, nil, false, ScreenReader.t("a11y.sr.no_code_to_copy", nil,
      "There is no generated code to copy.")
  end

  if ScreenReader.jsfx_saved_path_valid(msg) then
    local path = tostring(msg.jsfx_saved_path or "")
    local fx_name = tostring(msg.jsfx_saved_fx_name or "")
    if fx_name == "" then
      local filename = path:match("[^\\/]+$")
      if filename and filename ~= "" then
        fx_name = "ReaAssist/" .. filename
        msg.jsfx_saved_fx_name = fx_name
      end
    end
    if fx_name ~= "" then return path, fx_name, true end
  end

  local code, inject_info, prepare_err, validator_detail =
    ScreenReader.prepare_jsfx_for_save(payload, msg, allow_invalid)
  if not code then return nil, nil, false, prepare_err, validator_detail end

  local path, fx_name = Code.auto_save_jsfx(code)
  if path and fx_name then
    msg.jsfx_saved_path = path
    msg.jsfx_saved_fx_name = fx_name
    ScreenReader.record_jsfx_ceiling_slot(msg, inject_info, path, code)
    return path, fx_name, false
  end
  return nil, nil, false, ScreenReader.t("jsfx.save_failed", nil,
    "Failed to save JSFX.")
end

function ScreenReader.save_latest_jsfx()
  local payload = AppController.latest_response_payload()
  local path, _, already, err, detail =
    ScreenReader.save_jsfx_for_payload(payload)
  if not path and detail then
    if ScreenReader.confirm_invalid_jsfx_save(detail, "save") then
      path, _, already, err = ScreenReader.save_jsfx_for_payload(payload, true)
    else
      err = ScreenReader.t("a11y.sr.jsfx_save_cancelled", nil,
        "JSFX save cancelled.")
    end
  end
  if not path then
    ScreenReader.set_status(err or ScreenReader.t("jsfx.save_failed", nil,
      "Failed to save JSFX."), true)
    return false
  end

  local msg = ScreenReader.payload_jsfx_message(payload)
  local status = already
    and ScreenReader.t("jsfx.already_saved_to", { path = path },
      "Already saved to " .. path)
    or ScreenReader.t("jsfx.saved_to", { path = path },
      "Saved to " .. path)
  if msg then msg.jsfx_status = status end
  ScreenReader.set_status(status, true,
    ScreenReader.t("a11y.sr.jsfx_saved_short", nil, "JSFX saved."))
  return true
end

function ScreenReader.add_latest_jsfx_to_selected_tracks(next_view)
  local payload = AppController.latest_response_payload()
  local msg = ScreenReader.payload_jsfx_message(payload)
  if not msg or tostring(payload and payload.code or "") == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_code_to_run", nil,
      "There is no runnable generated code."), true)
    return false
  end

  local sel_count = reaper.CountSelectedTracks and reaper.CountSelectedTracks(0)
    or 0
  if sel_count <= 0 then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.add_jsfx_no_tracks", nil,
      "Select one or more tracks in REAPER first, then add the JSFX."), true)
    return false
  end

  local saved_path, fx_name, _, err, detail =
    ScreenReader.save_jsfx_for_payload(payload)
  if not (saved_path and fx_name) and detail then
    if ScreenReader.confirm_invalid_jsfx_save(detail, "add") then
      saved_path, fx_name, _, err =
        ScreenReader.save_jsfx_for_payload(payload, true)
    else
      err = ScreenReader.t("a11y.sr.jsfx_add_cancelled", nil,
        "JSFX add cancelled.")
    end
  end
  if not (saved_path and fx_name) then
    ScreenReader.set_status(err or ScreenReader.t("jsfx.save_failed", nil,
      "Failed to save JSFX."), true)
    return false
  end

  local tracks = {}
  for t = 0, sel_count - 1 do
    tracks[#tracks + 1] = reaper.GetSelectedTrack(0, t)
  end

  if reaper.Undo_BeginBlock then reaper.Undo_BeginBlock() end
  local added_n = 0
  for _, tr in ipairs(tracks) do
    local valid = tr
      and (not reaper.ValidatePtr2
        or reaper.ValidatePtr2(0, tr, "MediaTrack*"))
    if valid then
      local fx = reaper.TrackFX_AddByName(tr, fx_name, false, -1)
      if fx and fx >= 0 then added_n = added_n + 1 end
    end
  end
  if reaper.Undo_EndBlock then
    reaper.Undo_EndBlock("ReaAssist: Add JSFX to selected tracks", -1)
  end

  if added_n <= 0 then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.add_jsfx_failed", nil,
      "JSFX was saved, but REAPER did not add it to the selected tracks."),
      true)
    return false
  end

  local status = ScreenReader.t("jsfx.added_to", {
    count = added_n,
  }, "Added to " .. tostring(added_n) .. " track(s).")
  msg.jsfx_saved_path = saved_path
  msg.jsfx_saved_fx_name = fx_name
  msg.jsfx_added_to_tracks = true
  msg.jsfx_status = status
  msg.screen_reader_undo_clicked = nil
  msg.auto_ran = false
  ScreenReader.set_status_after_rebuild(status, true)
  ScreenReader.open_view(next_view or (S and S._screen_reader_view)
    or "response_ready")
  return true
end

function ScreenReader.undo_latest_typed_action(next_view)
  local ok, msg = AppController.undo_latest_typed_action
    and AppController.undo_latest_typed_action()
  ScreenReader.set_status(msg or (ok
    and ScreenReader.t("a11y.sr.undo_edit_done", nil, "Undo sent.")
    or ScreenReader.t("a11y.sr.undo_edit_unavailable", nil,
      "There is no structured edit to undo.")), true)
  ScreenReader.open_view(next_view or "response_ready")
end

function ScreenReader.request_lua_for_action_plan(next_view, opts)
  local ok, msg = AppController.request_lua_for_latest_typed_action
    and AppController.request_lua_for_latest_typed_action(opts or {})
  if not ok then
    ScreenReader.set_status(msg or ScreenReader.t(
      "a11y.sr.request_lua_unavailable", nil,
      "Could not request the Lua/ReaScript version."), true)
    return
  end
  S._screen_reader_request_active = true
  S._screen_reader_last_msg_idx = #S.display_messages
  if reaper and reaper.time_precise then
    local now = reaper.time_precise()
    S._screen_reader_request_started_at = now
    S._screen_reader_next_request_announcement_at = now + 20
  else
    S._screen_reader_request_started_at = nil
    S._screen_reader_next_request_announcement_at = nil
  end
  ScreenReader.refresh_actions()
  ScreenReader.set_status_after_rebuild(msg or ScreenReader.t(
    "a11y.sr.request_lua_sent", nil,
    "Requesting Lua/ReaScript version."), true)
  ScreenReader.open_view(next_view or "thinking")
end

function ScreenReader.undo_latest_generated_action(next_view)
  local payload = AppController.latest_response_payload()
  local msg = ScreenReader.payload_jsfx_message(payload)
  if msg and ScreenReader.payload_can_undo(payload) then
    reaper.Main_OnCommand(40029, 0)
    msg.jsfx_added_to_tracks = false
    msg.jsfx_status = nil
    msg.screen_reader_undo_clicked = true
    msg.auto_ran = false
    ScreenReader.set_status(ScreenReader.t("a11y.sr.jsfx_undo_done", nil,
      "Undo sent. JSFX add was reverted."), true)
    local target = next_view == "reader" and "response_ready"
      or next_view or "response_ready"
    ScreenReader.open_view(target)
    return
  end

  local ok, msg = AppController.undo_latest_generated_action
    and AppController.undo_latest_generated_action()
  ScreenReader.set_status(msg or (ok
    and ScreenReader.t("a11y.sr.undo_run_done", nil, "Undo sent.")
    or ScreenReader.t("a11y.sr.undo_run_unavailable", nil,
      "There is no completed action to undo.")), true)
  ScreenReader.open_view(next_view or "response_ready")
end

function ScreenReader.open_run_confirm(reason, message, opts)
  S._screen_reader_run_confirm = {
    reason = reason or "confirm",
    message = message or ScreenReader.t("a11y.sr.run_confirm_body", nil,
      "Review the generated code before running it."),
    opts = opts or {},
  }
  ScreenReader.open_view("run_confirm")
end

function ScreenReader.run_code(opts)
  local payload = AppController.latest_response_payload()
  if ScreenReader.payload_is_jsfx(payload) then
    local next_view = (S and S._screen_reader_view == "reader")
      and "reader" or "response_ready"
    ScreenReader.add_latest_jsfx_to_selected_tracks(next_view)
    return
  end

  local ok, reason, msg = AppController.run_latest_code(opts or {})
  if ok then
    ScreenReader.queue_response_ready_announcement(
      AppController.latest_response_payload(),
      msg or ScreenReader.t("a11y.sr.run_code_ok", nil,
        "Generated code ran."))
    ScreenReader.open_view("response_ready")
    return
  end
  if reason == "risky_confirmation_required" then
    return ScreenReader.open_run_confirm(reason, msg, { confirm_risky = true })
  end
  if reason == "backup_unsaved" then
    return ScreenReader.open_run_confirm(reason, msg, { skip_backup = true })
  end
  ScreenReader.set_status(msg or ScreenReader.t("a11y.sr.run_code_failed", nil,
    "Generated code failed. Check the response and debug log."), true)
  ScreenReader.refresh_actions()
end

function ScreenReader.apply_typed_action(opts)
  local ok, reason, msg
  if AppController.apply_latest_typed_action then
    ok, reason, msg = AppController.apply_latest_typed_action(opts or {})
  else
    ok, reason, msg = false, "unavailable", ScreenReader.t(
      "a11y.sr.apply_action_plan_unavailable", nil,
      "There is no validated edit to run.")
  end
  if ok then
    ScreenReader.queue_response_ready_announcement(
      AppController.latest_response_payload(),
      msg or ScreenReader.t("a11y.sr.apply_action_plan_done", nil,
        "Structured edit ran."))
    ScreenReader.open_view("response_ready")
    return
  end
  if reason == "backup_unsaved" then
    return ScreenReader.open_run_confirm(reason, msg, {
      apply_typed_action = true,
      skip_backup = true,
    })
  end
  ScreenReader.set_status(msg or ScreenReader.t(
    "a11y.sr.apply_action_plan_failed", nil,
    "Structured edit could not run."), true)
  ScreenReader.refresh_actions()
end

function ScreenReader.confirm_run_code()
  local confirm = S and S._screen_reader_run_confirm or {}
  if confirm.opts and confirm.opts.apply_typed_action then
    local opts = confirm.opts or {}
    opts.apply_typed_action = nil
    S._screen_reader_run_confirm = nil
    return ScreenReader.apply_typed_action(opts)
  end
  local ok, reason, msg = AppController.run_latest_code(confirm.opts or {})
  S._screen_reader_run_confirm = nil
  if ok then
    ScreenReader.queue_response_ready_announcement(
      AppController.latest_response_payload(),
      msg or ScreenReader.t("a11y.sr.run_code_ok", nil,
        "Generated code ran."))
    ScreenReader.open_view("response_ready")
  elseif reason == "backup_unsaved" then
    ScreenReader.open_run_confirm(reason, msg, { skip_backup = true })
  else
    ScreenReader.set_status_after_rebuild(msg or ScreenReader.t(
      "a11y.sr.run_code_failed", nil,
      "Generated code failed. Check the response and debug log."), true)
    ScreenReader.open_view("reader")
  end
end

function ScreenReader.cancel_run_code()
  S._screen_reader_run_confirm = nil
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.run_code_cancelled", nil, "Run cancelled."), true)
  ScreenReader.open_view("reader")
end

function ScreenReader.confirm_add_saved_script_to_actions()
  local path = S and S._screen_reader_saved_script_path or ""
  local ok, msg
  if AppController.add_script_to_actions then
    ok, msg = AppController.add_script_to_actions(path)
  end
  S._screen_reader_saved_script_path = nil
  local return_view = S._screen_reader_add_actions_return_view or "reader"
  S._screen_reader_add_actions_return_view = nil
  ScreenReader.set_status_after_rebuild(msg or (ok
    and ScreenReader.t("a11y.sr.add_actions_done", nil,
      "Script added to the REAPER Actions list.")
    or ScreenReader.t("a11y.sr.add_actions_failed", nil,
      "Could not add the script to the REAPER Actions list.")), true)
  ScreenReader.open_view(return_view)
end

function ScreenReader.skip_add_saved_script_to_actions()
  S._screen_reader_saved_script_path = nil
  local return_view = S._screen_reader_add_actions_return_view or "reader"
  S._screen_reader_add_actions_return_view = nil
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.add_actions_skipped", nil,
    "Saved script was not added to the Actions list."), true)
  ScreenReader.open_view(return_view)
end

function ScreenReader.open_clear_confirm()
  if AppController.request_is_active() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clear_blocked_active", nil,
      "Cancel or finish the active request before clearing the chat."), true)
    return
  end
  if AppController.conversation_has_content
      and not AppController.conversation_has_content() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.no_chat_to_clear", nil,
      "There is no conversation to clear."), true)
    return
  end
  ScreenReader.open_view("clear_confirm")
end

function ScreenReader.confirm_clear_chat()
  local ok = AppController.clear_conversation and AppController.clear_conversation()
  S._screen_reader_prompt = ""
  S._screen_reader_request_active = false
  ScreenReader.set_status_after_rebuild(ok
    and ScreenReader.t("a11y.sr.conversation_cleared", nil,
      "Conversation cleared.")
    or ScreenReader.t("a11y.sr.clear_failed", nil,
      "Could not clear the conversation."), true)
  ScreenReader.open_view("main")
end

function ScreenReader.cancel_clear_chat()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.clear_cancelled", nil, "Clear cancelled."), true)
  ScreenReader.open_view("main")
end

function ScreenReader.reset_window_size()
  local ok, err = AppController.reset_window_size()
  if ok then
    ScreenReader.store_reagirl_window_size("ReaAssist_Screen_Reader_Main",
      820, 380)
    ScreenReader.store_reagirl_window_size("ReaAssist_Screen_Reader_Mode",
      820, 500)
    ScreenReader.store_reagirl_window_size("ReaAssist_Screen_Reader_Examples",
      640, 430)
    ScreenReader.store_reagirl_window_size(
      "ReaAssist_Screen_Reader_Response_Ready", 760, 300)
    ScreenReader.store_reagirl_window_size("ReaAssist_Screen_Reader_Feedback",
      860, 500)
    ScreenReader.store_reagirl_window_size("ReaAssist_Screen_Reader_Thinking",
      520, 210)
    if reagirl and reagirl.Window_Open then
      local active = tostring(reagirl.Window_name or "")
      local w, h = 820, 500
      if active == "ReaAssist_Screen_Reader_Main" then
        w, h = 820, 380
      elseif active == "ReaAssist_Screen_Reader_Examples" then
        w, h = 640, 430
      elseif active == "ReaAssist_Screen_Reader_Response_Ready" then
        w, h = 760, 300
      elseif active == "ReaAssist_Screen_Reader_Feedback" then
        w, h = 860, 500
      elseif active == "ReaAssist_Screen_Reader_Thinking" then
        w, h = 520, 210
      end
      local target_w, target_h = ScreenReader.target_window_size(w, h)
      pcall(reagirl.Window_Open, "", target_w, target_h, 0, nil, nil)
      if gfx and gfx.dock then pcall(gfx.dock, 0) end
    end
  end
  ScreenReader.set_status(ok and ScreenReader.t(
    "a11y.sr.reset_window_done", nil,
    "Window sizes reset.")
    or tostring(err or ScreenReader.t("a11y.sr.reset_window_failed", nil,
      "Could not reset the window size.")), true)
end

function ScreenReader.open_factory_reset_confirm()
  if AppController.request_is_active() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.factory_reset_blocked_active",
      nil, "Cancel or finish the active request before factory reset."), true)
    return
  end
  ScreenReader.open_view("factory_reset_confirm")
end

function ScreenReader.confirm_factory_reset()
  local ok, err = AppController.factory_reset({
    keep_screen_reader = true,
    keep_open = true,
  })
  if not ok then
    ScreenReader.set_status_after_rebuild(tostring(err or ScreenReader.t(
      "a11y.sr.factory_reset_failed", nil,
      "Factory reset could not be completed.")), true)
    ScreenReader.open_view("settings")
    return
  end
  if S then S.script_open = true end
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.factory_reset_done", nil,
    "Factory reset complete. ReaAssist Screen Reader Mode is ready for first setup."),
    true)
  ScreenReader.focus_after_rebuild("terms_accept")
  ScreenReader.open_view("terms")
end

function ScreenReader.cancel_factory_reset()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.factory_reset_cancelled", nil, "Factory reset cancelled."), true)
  ScreenReader.open_view("settings")
end

function ScreenReader.response_preview_text(payload)
  payload = payload or AppController.latest_response_payload()
  local text = ScreenReader.response_prose_text(payload)
  local preview = text ~= "" and ScreenReader.clean_label(text, 420)
    or ScreenReader.t("a11y.sr.no_response", nil,
      "ReaAssist finished, but no readable response was found.")
  local notes = {}
  if payload and payload.has_code
      and not preview:find("Generated code", 1, true) then
    notes[#notes + 1] = ScreenReader.t("a11y.sr.code_available", {
      type = payload.code_label or ScreenReader.t("a11y.sr.generated_code",
        nil, "generated code"),
    }, "Generated code is available. Use the reader controls to review, copy, or save it.")
  end
  if payload and payload.run_status and payload.run_status ~= ""
      and not preview:find("Run status:", 1, true) then
    notes[#notes + 1] = ScreenReader.run_status_sentence(payload.run_status)
  end
  local manual_block_text = ScreenReader.manual_lua_run_block_text(payload)
  local block_text = manual_block_text ~= ""
    and manual_block_text or ScreenReader.auto_run_block_text(payload)
  if block_text ~= "" then notes[#notes + 1] = block_text end
  if #notes > 0 then preview = preview .. " " .. table.concat(notes, " ") end
  return preview
end

function ScreenReader.open_help()
  ScreenReader.open_view("help")
end

function ScreenReader.terms_required()
  return api_keys and api_keys.tos_is_accepted
    and not api_keys.tos_is_accepted()
end

function ScreenReader.terms_text()
  local fallback = api_keys and api_keys.tos_text or "Terms of Use"
  return tostring(ScreenReader.t("tos.body", {
    year = os.date and os.date("%Y") or "2026",
  }, fallback))
end

function ScreenReader.has_usable_provider()
  if Store and Store.has_usable_provider then
    return Store.has_usable_provider()
  end
  return AppController.active_provider_is_usable
    and AppController.active_provider_is_usable() or false
end

function ScreenReader.mark_first_launch_complete()
  if Store and Store.mark_first_launch_complete then
    Store.mark_first_launch_complete()
  end
end

function ScreenReader.api_keys_setup_active()
  return api_keys and api_keys.is_reentry == false
end

function ScreenReader.open_api_keys_setup()
  if api_keys then api_keys.is_reentry = false end
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "settings.hero.subtitle.first_run", nil,
    "Add at least one API key to get started."), true)
  ScreenReader.focus_after_rebuild({ "api_key_input", "api_key_provider" })
  ScreenReader.open_view("api_keys")
end

function ScreenReader.open_api_keys_settings()
  if api_keys then api_keys.is_reentry = true end
  ScreenReader.open_view("api_keys")
end

function ScreenReader.continue_from_api_keys()
  if not ScreenReader.has_usable_provider() then
    ScreenReader.set_status(ScreenReader.t("settings.hero.subtitle.first_run",
      nil, "Add at least one API key to get started."), true)
    return
  end
  if api_keys then api_keys.is_reentry = false end
  ScreenReader.mark_first_launch_complete()
  ScreenReader.announce_after_rebuild(ScreenReader.t("a11y.sr.opened", nil,
    "ReaAssist Screen Reader Mode opened. Press F2 for a new prompt, F1 for shortcuts, or Tab to move through controls."))
  ScreenReader.open_view("main")
end

function ScreenReader.accept_terms()
  if api_keys and api_keys.mark_tos_accepted then
    api_keys.mark_tos_accepted()
  end
  ScreenReader.announce(ScreenReader.t(
    "a11y.sr.tos_accepted", nil, "Terms accepted."))
  if ScreenReader.has_usable_provider() then
    ScreenReader.mark_first_launch_complete()
    ScreenReader.announce_after_rebuild(ScreenReader.t("a11y.sr.opened", nil,
      "ReaAssist Screen Reader Mode opened. Press F2 for a new prompt, F1 for shortcuts, or Tab to move through controls."))
    ScreenReader.open_view("main")
  else
    ScreenReader.open_api_keys_setup()
  end
end

function ScreenReader.decline_terms()
  ScreenReader.announce(ScreenReader.t("a11y.sr.tos_declined", nil,
    "Terms were not accepted. Closing ReaAssist Screen Reader Mode."))
  ScreenReader.finish()
end

function ScreenReader.copy_terms_text()
  local ok = AppController.copy_text(ScreenReader.terms_text())
  ScreenReader.set_status(ok and ScreenReader.t("a11y.sr.terms_copied",
    nil, "Terms copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Copy failed."), true)
end

function ScreenReader.open_manual()
  local ok = UI and UI.open_url and UI.open_url("https://reaassist.app/manual/")
  if not ok then ok = open_url("https://reaassist.app/manual/") end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.manual_opened", nil,
      "Opening the ReaAssist manual.")
    or ScreenReader.t("a11y.sr.manual_open_failed", nil,
      "Could not open the ReaAssist manual."), true)
end

function ScreenReader.help_text()
  local lines = {}
  local function add(text)
    text = tostring(text or "")
    if text ~= "" then lines[#lines + 1] = ScreenReader.wrap_text(text, 84) end
  end
  local function blank() lines[#lines + 1] = "" end
  local function heading(key, fallback)
    blank()
    add(ScreenReader.t(key, nil, fallback))
  end
  local function bullet(key, fallback)
    add("- " .. ScreenReader.t(key, nil, fallback))
  end

  add(ScreenReader.t("help.intro.what", nil,
    "ReaAssist helps with the technical side of REAPER sessions."))
  add(ScreenReader.t("a11y.sr.help_intro_start", nil,
    "Choose a provider and model, then type a prompt or press F2 for the fastest prompt dialog. Responses are read automatically when possible. If ReaAssist returns Lua or JSFX, review the summary first, then use Run Code for Lua, Add JSFX to Selected Tracks for JSFX, Read or Save, Copy Response, or Undo when those controls are available."))
  add(ScreenReader.t("help.intro.manual", nil,
    "For setup, providers, troubleshooting, privacy details, and advanced workflows, use Read Online Manual above."))

  heading("a11y.sr.shortcuts_title", "Keyboard Shortcuts")
  add(ScreenReader.t("a11y.sr.shortcuts_intro", nil,
    "These work while the Screen Reader Mode window has focus."))
  bullet("a11y.sr.shortcut_f1", "F1: Help and keyboard shortcuts.")
  bullet("a11y.sr.shortcut_f2", "F2: New prompt dialog.")
  bullet("a11y.sr.shortcut_f3", "F3: Settings.")
  bullet("a11y.sr.shortcut_f4", "F4: Close Screen Reader Mode.")
  bullet("a11y.sr.shortcut_f5", "F5: Send from prompt screens.")
  bullet("a11y.sr.shortcut_f6",
    "F6: Read or save generated Lua, JSFX, or edit details.")
  bullet("a11y.sr.shortcut_f7", "F7: Undo the last run or structured edit.")
  bullet("a11y.sr.shortcut_f8",
    "F8: Run generated Lua, add JSFX to selected tracks, run a validated edit, or confirm a safety prompt.")
  bullet("a11y.sr.shortcut_f9", "F9: Back to the previous screen.")
  heading("a11y.sr.screen_reader_tips_title", "Screen Reader Tips")
  bullet("a11y.sr.shortcut_reread_focus",
    "Shift Up Arrow: re-read the focused control.")
  bullet("a11y.sr.shortcut_read_window",
    "Shift T: read the current window context.")

  heading("help.ask.title", "Ask Clearly")
  bullet("help.ask.target", "Name the track, item, plugin, or project area you want changed.")
  bullet("help.ask.constraints", "Say what to avoid, preserve, or check before making changes.")
  bullet("help.ask.report", "If a result is wrong, describe what happened and what you expected.")

  heading("help.run.title", "Run Code Carefully")
  bullet("help.run.read", "Read generated Lua or JSFX before running it.")
  bullet("help.run.backup", "Save the project or make a backup before broad edits.")
  bullet("help.run.undo", "Use Undo in REAPER if a generated action does the wrong thing.")
  bullet("help.run.scanner", "ReaAssist blocks or asks before risky generated actions.")

  heading("help.privacy.title", "Privacy Basics")
  bullet("help.privacy.audio", "ReaAssist does not access, transmit, or create audio files.")
  bullet("help.privacy.provider", "Chat data goes only to the provider and model you choose.")
  bullet("help.privacy.request", "Session context may include track names, routing, markers, and settings.")
  bullet("help.privacy.manual_reports", "Manual reports are sent only after you preview and send them.")
  bullet("a11y.sr.help_privacy_diagnostics",
    "Automatic diagnostics can be managed from Settings.")

  heading("help.need.title", "Need Help?")
  bullet("help.need.symptom", "Include what you clicked, what happened, and what you expected.")
  bullet("help.need.error", "Include the error text if REAPER shows one.")
  bullet("help.need.close",
    "You can close Screen Reader Mode with F4, Control Q, Alt F4, double Escape, or Close.")
  bullet("help.need.screen_reader", "Mention your screen reader and whether OSARA is installed.")
  bullet("help.need.feedback", "Use Report Issue for bugs that need maintainer attention.")
  bullet("help.need.manual", "Use Read Online Manual for detailed setup and troubleshooting.")

  return table.concat(lines, "\n")
end

function ScreenReader.copy_help_text()
  local ok = AppController.copy_text(ScreenReader.help_text())
  ScreenReader.set_status(ok and ScreenReader.t("a11y.sr.help_copied", nil,
    "Help text copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.open_external_url(url, ok_key, ok_fallback)
  local ok = UI and UI.open_url and UI.open_url(url)
  if not ok then ok = open_url(url) end
  ScreenReader.set_status(ok and ScreenReader.t(ok_key, nil, ok_fallback)
    or ScreenReader.t("a11y.sr.open_url_failed", nil,
      "Could not open the link."), true)
end

function ScreenReader.open_donate()
  ScreenReader.open_external_url("https://www.paypal.com/paypalme/civil",
    "a11y.sr.donate_opened", "Opening donation page.")
end

function ScreenReader.credits_text()
  local lines = {}
  local function add(text)
    text = tostring(text or "")
    if text ~= "" then lines[#lines + 1] = ScreenReader.wrap_text(text, 84) end
  end
  local function blank() lines[#lines + 1] = "" end
  add(ScreenReader.t("credits.subtitle", nil,
    "Brought to you by Michael Briggs Mastering."))
  blank()
  add(ScreenReader.t("credits.about.bio", nil,
    "Michael Briggs is an audio engineer and producer based in Denton, Texas."))
  blank()
  add(ScreenReader.t("credits.about.reaassist", nil,
    "ReaAssist is a workflow assistant for the technical side of REAPER."))
  blank()
  add(ScreenReader.t("credits.section.dependencies", nil, "DEPENDENCIES"))
  add(ScreenReader.t("credits.dependency.sws", nil,
    "SWS/S&M Extension by Tim Payne, Jeffos, and contributors."))
  add(ScreenReader.t("credits.dependency.js_reascriptapi", nil,
    "js_ReaScriptAPI by Julian Sader."))
  add(ScreenReader.t("credits.dependency.osara", nil,
    "OSARA by James Teh and contributors."))
  add(ScreenReader.t("credits.dependency.reagirl", nil,
    "ReaGirl by Meo-Ada Mespotine."))
  blank()
  add("MichaelBriggs.audio")
  add("MichaelBriggsMastering.com")
  add("ReaAssist.app")
  add("michael@michaelbriggs.audio")
  add("help@reaassist.app")
  blank()
  add(ScreenReader.t("credits.donate.caption", nil,
    "Donations help keep this project moving forward."))
  return table.concat(lines, "\n")
end

function ScreenReader.copy_credits_text()
  local ok = AppController.copy_text(ScreenReader.credits_text())
  ScreenReader.set_status(ok and ScreenReader.t("a11y.sr.credits_copied",
    nil, "Credits copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.close_ui()
  if reagirl and reagirl.Gui_Close then pcall(reagirl.Gui_Close) end
  ScreenReader.finish()
end

function ScreenReader.shortcut_status(key, fallback)
  ScreenReader.set_status(ScreenReader.t(key, nil, fallback), true)
end

function ScreenReader.shortcut_new_prompt()
  if AppController.request_is_active and AppController.request_is_active() then
    ScreenReader.shortcut_status("a11y.sr.shortcut_waiting",
      "A request is already running. Wait for it to finish or use Cancel Request.")
    return
  end
  local ok, text = ScreenReader.new_prompt_dialog()
  if ok == true then
    ScreenReader.update_prompt_from_input(text, false, false)
    if ScreenReader.current_prompt() == "" then
      ScreenReader.focus_after_rebuild("prompt_input")
      ScreenReader.set_status_after_rebuild(ScreenReader.t(
        "a11y.sr.new_prompt_blank", nil,
        "No prompt entered. Press Enter on Prompt to type, then use Send."), true)
      ScreenReader.open_view("prompt_edit")
      return
    end
    ScreenReader.send_current_prompt()
    return
  end
  if ok == false then
    ScreenReader.shortcut_status("a11y.sr.new_prompt_cancelled",
      "New prompt cancelled.")
    return
  end
  ScreenReader.open_prompt_for_next_request()
end

function ScreenReader.shortcut_send_request()
  if AppController.request_is_active and AppController.request_is_active() then
    ScreenReader.shortcut_status("a11y.sr.request_already_running",
      "A request is already running.")
    return
  end

  local view = S and S._screen_reader_view or "main"
  local send_views = { main = true, prompt_edit = true, attachments = true }
  if send_views[view] then
    ScreenReader.send_current_prompt()
    return
  end

  ScreenReader.shortcut_status("a11y.sr.shortcut_send_unavailable",
    "F5 sends from prompt screens.")
end

function ScreenReader.shortcut_run_code()
  if AppController.request_is_active and AppController.request_is_active() then
    ScreenReader.shortcut_status("a11y.sr.request_already_running",
      "A request is already running.")
    return
  end

  local view = S and S._screen_reader_view or "main"
  if S and S._screen_reader_view == "run_confirm" then
    ScreenReader.confirm_run_code()
    return
  end

  local payload = AppController.latest_response_payload
    and AppController.latest_response_payload() or nil
  if ScreenReader.payload_is_typed_action(payload)
      and payload.has_code == true
      and not ScreenReader.payload_can_undo(payload) then
    ScreenReader.apply_typed_action()
    return
  end
  if ScreenReader.payload_is_jsfx(payload) and payload.has_code == true then
    local next_view = view == "reader" and "reader" or "response_ready"
    ScreenReader.add_latest_jsfx_to_selected_tracks(next_view)
    return
  end

  local run_info = AppController.latest_code_run_info
    and AppController.latest_code_run_info() or nil
  if run_info and run_info.can_run then
    ScreenReader.run_code()
    return
  end
  if run_info and run_info.message and run_info.message ~= ""
      and run_info.reason ~= "no_code"
      and run_info.reason ~= "not_lua" then
    ScreenReader.set_status(run_info.message, true)
    return
  end

  ScreenReader.shortcut_status("a11y.sr.shortcut_run_unavailable",
    "No runnable generated Lua, JSFX add action, or validated edit is available here.")
end

function ScreenReader.shortcut_read_or_save_code()
  local payload = AppController.latest_response_payload
    and AppController.latest_response_payload() or nil
  if payload and payload.has_code == true and payload.code
      and payload.code ~= "" then
    ScreenReader.show_code()
    return
  end
  ScreenReader.shortcut_status("a11y.sr.shortcut_no_code",
    "No generated code or edit details are available.")
end

function ScreenReader.shortcut_undo()
  local payload = AppController.latest_response_payload
    and AppController.latest_response_payload() or nil
  if ScreenReader.payload_can_undo(payload) then
    local next_view = (S and S._screen_reader_view == "reader")
      and "reader" or "response_ready"
    ScreenReader.undo_latest_generated_action(next_view)
    return
  end
  ScreenReader.shortcut_status("a11y.sr.shortcut_no_undo",
    "There is no completed action to undo.")
end

function ScreenReader.shortcut_back()
  if AppController.request_is_active and AppController.request_is_active() then
    ScreenReader.shortcut_status("a11y.sr.shortcut_waiting",
      "A request is already running. Wait for it to finish or use Cancel Request.")
    return
  end

  local view = S and S._screen_reader_view or "main"
  if view == "main" then
    ScreenReader.shortcut_status("a11y.sr.shortcut_back_unavailable",
      "Already on the main screen.")
  elseif view == "terms" then
    ScreenReader.shortcut_status("a11y.sr.shortcut_terms_required",
      "Accept or decline the terms before using Screen Reader Mode shortcuts.")
  elseif view == "api_keys" and ScreenReader.api_keys_setup_active() then
    ScreenReader.continue_from_api_keys()
  elseif view == "run_confirm" then
    ScreenReader.cancel_run_code()
  elseif view == "reader" then
    ScreenReader.open_view("response_ready")
  elseif view == "feedback" then
    ScreenReader.open_view("response_ready")
  elseif view == "response_ready" then
    ScreenReader.open_main_for_next_request()
  elseif view == "add_actions_confirm" then
    ScreenReader.skip_add_saved_script_to_actions()
  elseif view == "clear_confirm" then
    ScreenReader.cancel_clear_chat()
  elseif view == "pref_plugins_clear_confirm" then
    ScreenReader.cancel_clear_pref_plugins()
  elseif view == "fx_cache_clear_confirm"
      or view == "fx_cache_remove_confirm"
      or view == "fx_cache_rescan_all_confirm" then
    S._screen_reader_fx_cache_remove_ident = nil
    ScreenReader.open_view("fx_cache")
  elseif view == "api_keys"
      or view == "custom_providers"
      or view == "custom_instructions"
      or view == "pref_plugins"
      or view == "fx_cache"
      or view == "visual_switch_confirm"
      or view == "factory_reset_confirm" then
    if view == "factory_reset_confirm" then
      ScreenReader.cancel_factory_reset()
    elseif view == "visual_switch_confirm" then
      ScreenReader.cancel_visual_switch()
    else
      ScreenReader.open_view("settings")
    end
  else
    ScreenReader.open_view("main")
  end
end

function ScreenReader.handle_f_key_shortcut(key)
  local view = S and S._screen_reader_view or "main"
  if view == "terms" and key ~= 26164 then
    ScreenReader.shortcut_status("a11y.sr.shortcut_terms_required",
      "Accept or decline the terms before using Screen Reader Mode shortcuts.")
    return false
  end

  if key == 26161 then
    ScreenReader.open_help()
  elseif key == 26162 then
    ScreenReader.shortcut_new_prompt()
  elseif key == 26163 then
    ScreenReader.open_view("settings")
  elseif key == 26164 then
    ScreenReader.close_ui()
    return true
  elseif key == 26165 then
    ScreenReader.shortcut_send_request()
  elseif key == 26166 then
    ScreenReader.shortcut_read_or_save_code()
  elseif key == 26167 then
    ScreenReader.shortcut_undo()
  elseif key == 26168 then
    ScreenReader.shortcut_run_code()
  elseif key == 26169 then
    ScreenReader.shortcut_back()
  end
  return false
end

function ScreenReader.handle_reagirl_shortcuts()
  local keys = reagirl and reagirl.Key or nil
  if type(keys) ~= "table" then return false end
  local mouse_cap = tonumber(gfx and gfx.mouse_cap or 0) or 0
  if mouse_cap ~= 0 then return false end
  for i = 1, #keys do
    local key = tonumber(keys[i]) or 0
    if key == 26161 or key == 26162 or key == 26163
        or key == 26164 or key == 26165 or key == 26166
        or key == 26167 or key == 26168 or key == 26169 then
      return ScreenReader.handle_f_key_shortcut(key)
    end
  end
  return false
end

function ScreenReader.reagirl_close_key_action(key, mouse_cap)
  key = tonumber(key) or 0
  mouse_cap = tonumber(mouse_cap) or 0
  local ctrl = (mouse_cap & 4) == 4
  local shift = (mouse_cap & 8) == 8
  local alt = (mouse_cap & 16) == 16
  if ctrl and not shift and not alt and (key == 81 or key == 113) then
    return "ctrl_q"
  end
  if alt and not ctrl and not shift and key == 261 then
    return "alt_f4"
  end
  if key == 27 then return "esc" end
  return nil
end

function ScreenReader.handle_reagirl_close_keys()
  if not (S and reaper and reaper.time_precise) then return false end
  local keys = reagirl and reagirl.Key or nil
  if type(keys) ~= "table" then return false end
  local mouse_cap = gfx and gfx.mouse_cap or 0
  local now = reaper.time_precise()
  for i = 1, #keys do
    local key = tonumber(keys[i]) or 0
    local action = ScreenReader.reagirl_close_key_action(key, mouse_cap)
    if action == "ctrl_q" or action == "alt_f4" then
      ScreenReader.close_ui()
      return true
    end
    if action == "esc" then
      if S._screen_reader_last_esc_at
          and now - S._screen_reader_last_esc_at <= 1.25 then
        ScreenReader.close_ui()
        return true
      end
      S._screen_reader_last_esc_at = now
      ScreenReader.set_status(ScreenReader.t("a11y.sr.escape_again", nil,
        "Press Escape again to close Screen Reader Mode."), true)
      return false
    end
  end
  return false
end

function ScreenReader.request_elapsed_seconds()
  if not (S and reaper and reaper.time_precise) then return nil end
  local started = tonumber(S.request_start_time or 0)
  if not started or started <= 0 then
    started = tonumber(S._screen_reader_request_started_at or 0)
  end
  if not started or started <= 0 then return nil end
  return math.max(0, reaper.time_precise() - started)
end

function ScreenReader.announce_request_progress()
  if not (S and reaper and reaper.time_precise) then return end
  local now = reaper.time_precise()
  local next_at = tonumber(S._screen_reader_next_request_announcement_at or 0)
  if next_at <= 0 then
    local elapsed = ScreenReader.request_elapsed_seconds() or 0
    S._screen_reader_next_request_announcement_at =
      now + math.max(5, 20 - elapsed)
    return
  end
  if now < next_at then return end
  local elapsed = ScreenReader.request_elapsed_seconds()
  local seconds = math.max(20, math.floor(((elapsed or 0) + 5) / 10) * 10)
  ScreenReader.announce(ScreenReader.t("a11y.sr.request_still_working", {
    seconds = tostring(seconds),
  }, "Still working, " .. tostring(seconds) .. " seconds."))
  S._screen_reader_next_request_announcement_at = now + 20
end

function ScreenReader.handle_response_ready()
  S._screen_reader_request_active = false
  S._screen_reader_next_request_announcement_at = nil
  S._screen_reader_request_started_at = nil
  S._screen_reader_last_auto_copied_response = nil
  local payload = AppController.latest_response_payload()
  local text = payload and payload.text or ""
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    ScreenReader.set_label(ui.ids.response,
      ScreenReader.response_preview_text(payload))
  end
  if text ~= "" then AppController.write_transcript(text) end
  ScreenReader.refresh_actions()
  if text ~= "" then
    ScreenReader.queue_response_ready_announcement(payload, ScreenReader.t(
      "a11y.sr.response_ready", nil, "Response received."))
    ScreenReader.open_view("response_ready")
  else
    ScreenReader.set_status_after_rebuild(ScreenReader.t("a11y.sr.no_response", nil,
      "ReaAssist finished, but no readable response was found. Check the ReaAssist debug log or try again."), true)
    ScreenReader.open_main_for_next_request()
  end
end

function ScreenReader.save_config()
  if Store and Store.save_config then
    local err = Store.save_config()
    if err then
      ScreenReader.set_status(ScreenReader.t("a11y.sr.settings_save_failed", {
        error = err,
      }, "Settings could not be saved: " .. tostring(err)), true)
      return false
    end
  end
  return true
end

function ScreenReader.on_off(value)
  return value and ScreenReader.t("a11y.sr.on", nil, "on")
    or ScreenReader.t("a11y.sr.off", nil, "off")
end

function ScreenReader.concise_hints_enabled()
  return prefs and prefs.screen_reader_concise_hints == true
end

function ScreenReader.concise_description_for_element(el)
  if type(el) ~= "table" or el.IsDecorative == true then return nil end
  local typ = tostring(el.GUI_Element_Type or "")
  if typ == "Button" or typ == "ToolbarButton" or typ == "Burgermenu" then
    return ScreenReader.t("a11y.sr.concise_hint.button", nil,
      "Activates this command.")
  end
  if typ == "Checkbox" then
    return ScreenReader.t("a11y.sr.concise_hint.checkbox", nil,
      "Toggles this option.")
  end
  if typ == "ComboBox" then
    return ScreenReader.t("a11y.sr.concise_hint.menu", nil,
      "Choose an option.")
  end
  if typ == "Edit" then
    return ScreenReader.t("a11y.sr.concise_hint.edit", nil, "Enter text.")
  end
  if typ == "Slider" then
    return ScreenReader.t("a11y.sr.concise_hint.slider", nil,
      "Adjust value.")
  end
  if typ == "Tabs" then
    return ScreenReader.t("a11y.sr.concise_hint.tabs", nil,
      "Choose a tab.")
  end
  if typ == "ListView" then
    return ScreenReader.t("a11y.sr.concise_hint.list", nil,
      "Choose an item.")
  end
  if typ == "Textbox" then
    return ScreenReader.t("a11y.sr.concise_hint.textbox", nil,
      "Text area.")
  end
  return nil
end

function ScreenReader.apply_concise_hints()
  if not ScreenReader.concise_hints_enabled() then return end
  if not reagirl or type(reagirl.Elements) ~= "table" then return end
  for _, el in ipairs(reagirl.Elements) do
    local desc = ScreenReader.concise_description_for_element(el)
    if desc and desc ~= "" then el.Description = desc end
  end
end

function ScreenReader.set_pref_bool(key, value, status_key, fallback)
  if not prefs then return end
  prefs[key] = value == true
  if key == "debug_logging" and prefs.debug_logging and Log
      and Log.session_header then
    pcall(Log.session_header)
  end
  if ScreenReader.save_config() then
    ScreenReader.set_status(ScreenReader.t(status_key, {
      value = ScreenReader.on_off(prefs[key]),
    }, fallback), true)
  end
  ScreenReader.refresh_settings_summary()
end

function ScreenReader.set_concise_hints(value)
  if not prefs then return end
  prefs.screen_reader_concise_hints = value == true
  if ScreenReader.save_config() then
    ScreenReader.set_status_after_rebuild(ScreenReader.t(
      "a11y.sr.concise_hints_changed", {
        value = ScreenReader.on_off(prefs.screen_reader_concise_hints),
      }, "Concise focus hints are now {value}."), true)
    ScreenReader.focus_after_rebuild("concise_hints")
    ScreenReader.open_view("settings")
  end
end

function ScreenReader.prefer_screen_reader_enabled()
  return prefer_screen_reader_value() == "1"
end

function ScreenReader.set_prefer_screen_reader(value)
  set_prefer_screen_reader(value == true)
  ScreenReader.set_status_after_rebuild(value == true
    and ScreenReader.t("a11y.sr.prefer_sr_on", nil,
      "ReaAssist will open in Screen Reader Mode from now on.")
    or ScreenReader.t("a11y.sr.prefer_sr_off", nil,
      "ReaAssist will open its visual interface from now on. Screen Reader Mode is still available as its own action."),
    true)
  ScreenReader.focus_after_rebuild("prefer_screen_reader")
  ScreenReader.open_view("settings")
end

function ScreenReader.open_visual_switch_confirm()
  ScreenReader.open_view("visual_switch_confirm")
end

function ScreenReader.confirm_visual_switch()
  set_prefer_screen_reader(false)
  ScreenReader.announce(ScreenReader.t("a11y.sr.visual_switch_starting", nil,
    "Switching to the visual ReaAssist interface."))
  if Updater and Updater.fire_relauncher_now
      and Updater.fire_relauncher_now() then
    return
  end
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.visual_switch_manual", nil,
    "Screen Reader Mode default is off. Close this window and run ReaAssist to open the visual interface."),
    true)
  ScreenReader.open_view("settings")
end

function ScreenReader.cancel_visual_switch()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.visual_switch_cancelled", nil,
    "Visual interface switch cancelled."), true)
  ScreenReader.open_view("settings")
end

function ScreenReader.open_view(view)
  S._screen_reader_view = view or "main"
  if not S._screen_reader_focus_after_rebuild then
    ScreenReader.focus_after_rebuild(
      ScreenReader.default_focus_for_view(S._screen_reader_view))
  end
  S._screen_reader_rebuild = true
end

function ScreenReader.reset_scroll()
  if not reagirl then return end
  -- ReaGirl has public offset resetters, but not all hover/focus state has
  -- public reset APIs yet. Re-vet these private-field fallbacks whenever the
  -- pinned ReaGirl version or SHA changes.
  if reagirl.UI_Element_GetSetAllHorizontalOffset then
    pcall(reagirl.UI_Element_GetSetAllHorizontalOffset, true, 0)
  else
    reagirl.MoveItAllRight = 0
  end
  if reagirl.UI_Element_GetSetAllVerticalOffset then
    pcall(reagirl.UI_Element_GetSetAllVerticalOffset, true, 0)
  else
    reagirl.MoveItAllUp = 0
  end
  reagirl.MoveItAllRight_Delta = 0
  reagirl.MoveItAllUp_Delta = 0
  reagirl.UI_Element_NextLineY = 0
  reagirl.UI_Element_NextLineX = 10
  reagirl.NextLine_Overflow = 0
  reagirl.NextLine_triggered = nil
  reagirl.Next_Y = nil
  reagirl.Next_Y_offset = nil
  reagirl.TooltipWaitCounter = 0
  reagirl.UI_Elements_HoveredElement = -1
  if reagirl.Elements then
    reagirl.Elements.GlobalAccHoverMessageOld = ""
    reagirl.Elements["GlobalAccHoverMessage"] = ""
  end
  if reaper.TrackCtl_SetToolTip then
    pcall(reaper.TrackCtl_SetToolTip, "", 0, 0, false)
  end
  if reagirl.Gui_ForceRefresh then pcall(reagirl.Gui_ForceRefresh, 0) end
end

function ScreenReader.rebuild_ui()
  if reagirl and reagirl.Gui_Close then pcall(reagirl.Gui_Close) end
  ScreenReader.reset_scroll()
  local ok = ScreenReader.build_ui()
  if ok then ScreenReader.apply_concise_hints() end
  if ok then ScreenReader.apply_focus_after_rebuild() end
  S._screen_reader_reset_scroll_cycles = 3
  return ok
end

function ScreenReader.view_title()
  local view = S and S._screen_reader_view or "main"
  if view == "terms" then
    return ScreenReader.t("tos.title", nil, "Terms of Use")
  end
  if view == "settings" then
    return ScreenReader.t("a11y.sr.settings_title", nil,
      "ReaAssist Screen Reader Settings")
  end
  if view == "update_prompt" then
    local state = update and tostring(update.state or "idle") or "idle"
    if state == "repair_available" then
      return ScreenReader.t("a11y.sr.update_prompt.repair_title", nil,
        "ReaAssist Files Need Repair")
    end
    return ScreenReader.t("a11y.sr.update_prompt.update_title", nil,
      "ReaAssist Update Available")
  end
  if view == "api_keys" then
    return ScreenReader.t("a11y.sr.api_keys_title", nil,
      "ReaAssist API Keys")
  end
  if view == "custom_providers" then
    return ScreenReader.t("settings.custom.list.subtitle", nil,
      "Local & Custom Providers")
  end
  if view == "custom_instructions" then
    return ScreenReader.t("a11y.sr.custom_instructions_title", nil,
      "ReaAssist Custom Instructions")
  end
  if view == "pref_plugins" then
    return ScreenReader.t("a11y.sr.pref_plugins_title", nil,
      "ReaAssist Preferred Plugins")
  end
  if view == "fx_cache" then
    return ScreenReader.t("a11y.sr.fx_cache_title", nil,
      "ReaAssist FX Parameter Cache")
  end
  if view == "fx_cache_clear_confirm" then
    return ScreenReader.t("settings.fx_cache.confirm_clear.title", nil,
      "Confirm Clear Cache")
  end
  if view == "fx_cache_remove_confirm" then
    return ScreenReader.t("a11y.sr.fx_cache_remove_title", nil,
      "Remove Cached Plugin?")
  end
  if view == "fx_cache_rescan_all_confirm" then
    return ScreenReader.t("settings.fx_cache.confirm_rescan.title", nil,
      "Confirm Rescan All")
  end
  if view == "prompt_edit" then
    return ScreenReader.t("a11y.sr.prompt_editor_title", nil,
      "Prompt & Chat Tools")
  end
  if view == "example_prompts" then
    return ScreenReader.t("a11y.sr.example_prompts_title", nil,
      "Example Prompts")
  end
  if view == "response_ready" then
    return ScreenReader.t("a11y.sr.response_ready_title", nil,
      "Response")
  end
  if view == "thinking" then
    return ScreenReader.t("a11y.sr.thinking_title", nil,
      "Thinking")
  end
  if view == "attachments" then
    return ScreenReader.t("a11y.sr.attachments_title", nil,
      "ReaAssist Attachments")
  end
  if view == "report_issue" then
    return ScreenReader.t("a11y.sr.report_issue_title", nil,
      "Report Issue")
  end
  if view == "feedback" then
    return ScreenReader.t("a11y.sr.feedback_title", nil,
      "Response Feedback")
  end
  if view == "help" then
    return ScreenReader.t("help.title", nil, "Help")
  end
  if view == "credits" then
    return ScreenReader.t("footer.credits.label", nil, "Credits")
  end
  if view == "reader" then
    local kind = S and S._screen_reader_reader_kind or "response"
    if kind == "code" then
      return ScreenReader.t("a11y.sr.code_reader_title", nil,
        "ReaAssist Generated Code")
    end
    local payload = AppController.latest_response_payload
      and AppController.latest_response_payload() or nil
    if payload and payload.has_code then
      return ScreenReader.t("a11y.sr.response_notes_reader_title", nil,
        "Full Response Notes")
    end
    return ScreenReader.t("a11y.sr.response_reader_title", nil,
      "Full Response")
  end
  if view == "run_confirm" then
    return ScreenReader.t("a11y.sr.run_confirm_title", nil,
      "Run Generated Code?")
  end
  if view == "add_actions_confirm" then
    return ScreenReader.t("a11y.sr.add_actions_title", nil,
      "Add to Actions?")
  end
  if view == "clear_confirm" then
    return ScreenReader.t("a11y.sr.clear_confirm_title", nil, "Clear Chat?")
  end
  if view == "factory_reset_confirm" then
    return ScreenReader.t("settings.factory_reset.heading", nil,
      "Delete all ReaAssist data?")
  end
  if view == "visual_switch_confirm" then
    return ScreenReader.t("a11y.sr.visual_switch_title", nil,
      "Open Visual Interface?")
  end
  if view == "pref_plugins_clear_confirm" then
    return ScreenReader.t("a11y.sr.pref_plugins_clear_title", nil,
      "Clear Preferred Plugin Mappings?")
  end
  return ScreenReader.t("a11y.sr.title", nil, "ReaAssist Screen Reader Mode")
end

function ScreenReader.api_key_status_text()
  local status = AppController.active_provider_key_status()
  local label = status and status.label or ScreenReader.t(
    "a11y.controller.provider.unknown", nil, "unknown provider")
  if status and status.configured then
    return ScreenReader.t("a11y.sr.api_key_saved_status", {
      provider = label,
    }, label .. " API key is saved.")
  end
  return ScreenReader.t("a11y.sr.api_key_missing_status", {
    provider = label,
  }, label .. " API key is not saved.")
end

function ScreenReader.api_key_input_text()
  local ui = S and S.screen_reader_ui or nil
  local id = ui and ui.ids and ui.ids.api_key_input
  if id and reagirl and reagirl.Inputbox_GetText then
    local ok, text = pcall(reagirl.Inputbox_GetText, id)
    if ok then return tostring(text or "") end
  end
  return ""
end

function ScreenReader.refresh_api_key_status()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.api_key_status then
    ScreenReader.set_label(ui.ids.api_key_status,
      ScreenReader.api_key_status_text())
  end
end

function ScreenReader.api_key_message_box(message)
  if reaper and reaper.ShowMessageBox then
    reaper.ShowMessageBox(tostring(message or ""),
      ScreenReader.t("a11y.sr.api_keys_title", nil, "ReaAssist API Keys"), 0)
  end
end

function ScreenReader.api_key_test_result_text(passed, after_save)
  local test_text = passed
    and ScreenReader.t("a11y.sr.api_key_test_passed", nil,
      "API key test passed.")
    or ScreenReader.t("a11y.sr.api_key_test_failed", nil,
      "API key test failed. Check the key and try again.")
  if after_save then
    return ScreenReader.t("a11y.sr.api_key_saved", nil,
      "API key saved.") .. " " .. test_text
  end
  return test_text
end

function ScreenReader.save_api_key()
  local ok, err = AppController.save_active_provider_key(
    ScreenReader.api_key_input_text())
  if ok then
    local ui = S and S.screen_reader_ui or nil
    if ui and ui.ids and ui.ids.api_key_input
        and reagirl and reagirl.Inputbox_SetText then
      pcall(reagirl.Inputbox_SetText, ui.ids.api_key_input, "")
    end
    S._screen_reader_key_test_after_save = true
    ScreenReader.set_status(ScreenReader.t("a11y.sr.api_key_testing", nil,
      "Testing API key."), true)
  else
    local msg = err or ScreenReader.t("a11y.sr.api_key_save_failed",
      nil, "API key could not be saved.")
    ScreenReader.set_status(msg, false)
    ScreenReader.api_key_message_box(msg)
  end
  ScreenReader.refresh_menus()
  ScreenReader.refresh_api_key_status()
  ScreenReader.refresh_actions()
  if ok then ScreenReader.test_api_key({ after_save = true }) end
end

function ScreenReader.clear_api_key()
  if AppController.clear_active_provider_key() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.api_key_cleared", nil,
      "API key cleared."), true)
  end
  ScreenReader.refresh_api_key_status()
  ScreenReader.refresh_actions()
end

function ScreenReader.test_api_key(opts)
  opts = opts or {}
  local ok, err = AppController.test_active_provider_key()
  if not ok then
    local msg = err or ScreenReader.t("a11y.sr.api_key_test_failed",
      nil, "API key test could not start.")
    if opts.after_save then
      msg = ScreenReader.t("a11y.sr.api_key_saved", nil,
        "API key saved.") .. " " .. msg
    end
    S._screen_reader_key_test_after_save = nil
    ScreenReader.set_status(msg, false)
    ScreenReader.api_key_message_box(msg)
    return
  end
  S._screen_reader_key_test_active = true
  S._screen_reader_key_test_after_save =
    opts.after_save == true or S._screen_reader_key_test_after_save == true
  ScreenReader.set_status(ScreenReader.t("a11y.sr.api_key_testing", nil,
    "Testing API key."), true)
  ScreenReader.refresh_actions()
end

function ScreenReader.handle_key_test_ready()
  S._screen_reader_key_test_active = false
  local after_save = S._screen_reader_key_test_after_save == true
  S._screen_reader_key_test_after_save = nil
  local passed = AppController.active_provider_is_usable() and S.status ~= "error"
  local msg = ScreenReader.api_key_test_result_text(passed, after_save)
  ScreenReader.set_status(msg, false)
  ScreenReader.api_key_message_box(msg)
  ScreenReader.refresh_menus()
  ScreenReader.refresh_api_key_status()
  ScreenReader.refresh_actions()
end

function ScreenReader.open_provider_console()
  local status = AppController.active_provider_key_status()
  local url = status and status.console_url or nil
  if url and tostring(url) ~= "" then
    ScreenReader.open_external_url(url, "a11y.sr.api_key_console_opened",
      "Opening provider API key page.")
  else
    ScreenReader.set_status(ScreenReader.t("a11y.sr.api_key_console_missing",
      nil, "No API key page is available for this provider."), true)
  end
end

function ScreenReader.settings_summary_text()
  local parts = {}
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_snapshot", {
    value = ScreenReader.on_off(prefs and prefs.include_snapshot),
  }, "Snapshot " .. ScreenReader.on_off(prefs and prefs.include_snapshot) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_api_ref", {
    value = ScreenReader.on_off(prefs and prefs.include_api_ref),
  }, "API ref " .. ScreenReader.on_off(prefs and prefs.include_api_ref) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_details", {
    value = ScreenReader.on_off(prefs and prefs.show_details),
  }, "Details " .. ScreenReader.on_off(prefs and prefs.show_details) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_debug", {
    value = ScreenReader.on_off(prefs and prefs.debug_logging),
  }, "Log " .. ScreenReader.on_off(prefs and prefs.debug_logging) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_updates", {
    value = ScreenReader.on_off(prefs and prefs.update_check),
  }, "Update checks " .. ScreenReader.on_off(prefs and prefs.update_check) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_concise_hints", {
    value = ScreenReader.on_off(prefs and prefs.screen_reader_concise_hints),
  }, "Concise hints " .. ScreenReader.on_off(
      prefs and prefs.screen_reader_concise_hints) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_prefer_sr", {
    value = ScreenReader.on_off(ScreenReader.prefer_screen_reader_enabled()),
  }, "Screen Reader default " .. ScreenReader.on_off(
      ScreenReader.prefer_screen_reader_enabled()) .. ".")
  local language_label = ScreenReader.language_display_label(
    ScreenReader.current_language_code(), ScreenReader.current_language_code())
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_language", {
    value = language_label,
  }, "Language " .. tostring(language_label) .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_text_size", {
    value = ScreenReader.text_size_label(),
  }, "Accessible size " .. ScreenReader.text_size_label() .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_contrast", {
    value = ScreenReader.contrast_label(),
  }, "Contrast " .. ScreenReader.contrast_label() .. ".")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_timeout", {
    value = tostring(prefs and prefs.cloud_request_timeout or ""),
  }, "Timeout " .. tostring(prefs and prefs.cloud_request_timeout or "") .. "s.")
  parts[#parts + 1] = ScreenReader.t("a11y.sr.settings_summary_diag", {
    value = ScreenReader.diagnostics_tier_label(
      prefs and prefs.diag_auto_tier or "off"),
  }, "Diagnostics " .. ScreenReader.diagnostics_tier_label(
      prefs and prefs.diag_auto_tier or "off") .. ".")
  return table.concat(parts, " ")
end

function ScreenReader.settings_summary_wrap_px()
  local target_w = ScreenReader.target_window_size(820, 500)
  local window_w = tonumber(gfx and gfx.w) or target_w
  local width = math.min(target_w, window_w) - ScreenReader.scaled_ui_px(54)
  return math.max(ScreenReader.scaled_ui_px(280), width)
end

function ScreenReader.settings_summary_display_text()
  local fallback_chars = math.max(48,
    math.floor(88 / ScreenReader.text_size_factor()))
  return ScreenReader.wrap_text_to_px(ScreenReader.settings_summary_text(),
    ScreenReader.settings_summary_wrap_px(), fallback_chars)
end

function ScreenReader.refresh_settings_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.settings_summary then
    ScreenReader.set_label(ui.ids.settings_summary,
      ScreenReader.settings_summary_display_text())
  end
end

function ScreenReader.refresh_update_status()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.update_status
      and AppController.update_status_text then
    ScreenReader.set_label(ui.ids.update_status,
      AppController.update_status_text())
  end
end

function ScreenReader.check_updates()
  local ok, err = AppController.start_update_check()
  ScreenReader.refresh_update_status()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.update_check_started", nil,
      "Checking for updates.")
    or tostring(err or ScreenReader.t("a11y.sr.update_check_failed", nil,
      "Update check could not start.")), true)
end

function ScreenReader.apply_update()
  local ok, err = AppController.apply_update()
  ScreenReader.refresh_update_status()
  ScreenReader.refresh_actions()
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.update_apply_started", nil,
      "Applying update or repair.")
    or tostring(err or ScreenReader.t("a11y.sr.update_apply_failed", nil,
      "Update or repair could not start.")), true)
end

function ScreenReader.update_prompt_state()
  local state = update and tostring(update.state or "idle") or "idle"
  if state == "available" or state == "repair_available" then
    return state
  end
  return nil
end

function ScreenReader.update_prompt_body_text()
  local state = ScreenReader.update_prompt_state()
  if state == "repair_available" then
    local count = #(update.repair_missing or {})
      + #(update.repair_mismatched or {})
    return ScreenReader.t("a11y.sr.update_prompt.repair_body", {
      count = tostring(count),
    }, "ReaAssist found " .. tostring(count) ..
      " file(s) that need repair. Repair now to restore the required files.")
  end
  local remote = tostring(update and update.remote_version or "?")
  return ScreenReader.t("a11y.sr.update_prompt.update_body", {
    remote = remote,
    current = tostring(CFG and CFG.VERSION or "?"),
  }, "ReaAssist v" .. remote .. " is available. The update is quick and applies directly. No manual download is needed.")
end

function ScreenReader.maybe_show_update_prompt()
  if not (S and update) then return false end
  local state = ScreenReader.update_prompt_state()
  if not state then
    S._screen_reader_update_prompt_pending = nil
    return false
  end
  if update.popup_opened then
    S._screen_reader_update_prompt_pending = nil
    return false
  end
  if S._screen_reader_request_active or S._screen_reader_key_test_active then
    return false
  end
  local current = tostring(S._screen_reader_view or "main")
  if current ~= "update_prompt" then
    S._screen_reader_update_return_view = current
  end
  S._screen_reader_update_prompt_pending = nil
  update.popup_opened = true
  update.show_dialog = false
  ScreenReader.focus_after_rebuild("apply_update")
  ScreenReader.open_view("update_prompt")
  return true
end

function ScreenReader.queue_update_prompt()
  if not (S and update and ScreenReader.update_prompt_state()) then
    return false
  end
  if update.popup_opened then return false end
  S._screen_reader_update_prompt_pending = true
  return ScreenReader.maybe_show_update_prompt()
end

function ScreenReader.defer_update_prompt()
  if update then
    update.show_dialog = false
    update.popup_opened = true
  end
  if Store and Store.set_update_snooze then
    Store.set_update_snooze(os.time() + 7 * 24 * 3600)
  end
  local return_view = S and S._screen_reader_update_return_view or "main"
  if return_view == "update_prompt" or return_view == "" then
    return_view = "main"
  end
  if S then S._screen_reader_update_return_view = nil end
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.update_prompt.later_status", nil,
    "Update postponed for now."), true)
  ScreenReader.open_view(return_view)
end

function ScreenReader.maybe_start_auto_update_check()
  if not (S and Updater and Updater.check_start and update and CFG) then
    return
  end
  if update._session_check_fired then return end
  if not update._session_check_armed_at then
    if S._screen_reader_request_active then
      update._session_check_armed_at =
        reaper.time_precise and reaper.time_precise() or os.time()
    end
    return
  end
  local now = reaper.time_precise and reaper.time_precise() or os.time()
  local delay = tonumber(CFG.UPDATE_CHECK_DEFER) or 0.4
  if (now - update._session_check_armed_at) < delay then return end
  update._session_check_fired = true
  Updater.check_start()
end

function ScreenReader.track_update_status()
  if not (update and AppController.update_status_text) then return end
  local state = tostring(update.state or "idle")
  if S and S._screen_reader_update_prompt_pending then
    ScreenReader.maybe_show_update_prompt()
  end
  if S._screen_reader_last_update_state == state then return end
  S._screen_reader_last_update_state = state
  ScreenReader.refresh_update_status()
  if state == "available" or state == "repair_available" then
    ScreenReader.queue_update_prompt()
  elseif state == "done" or state == "failed" then
    ScreenReader.set_status(AppController.update_status_text(), true)
  end
end

function ScreenReader.language_menu()
  local labels, map, selected = {}, {}, 1
  local selected_code = prefs and prefs.language_code
  if not (CFG and CFG.is_valid_language_code
      and CFG.is_valid_language_code(selected_code)) then
    selected_code = CFG and CFG.current_language_code
      and CFG.current_language_code() or "en"
  end
  for i, label in ipairs((CFG and CFG.REPLY_LANGUAGE_LABELS) or {}) do
    local code = CFG and CFG.language_code_for_legacy_idx
      and CFG.language_code_for_legacy_idx(i)
    local has_catalog = code == "en" or (I18N and I18N.catalog_available
      and I18N.catalog_available(code))
    local pack_status = LangPacks and LangPacks.status_for_code
      and LangPacks.status_for_code(code)
    if has_catalog
        or pack_status == "download"
        or pack_status == "downloading"
        or pack_status == "failed" then
      local display_label = (LangPacks and LangPacks.label_for_code
        and LangPacks.label_for_code(code, label)) or tostring(label)
      display_label = ScreenReader.language_display_label(code, display_label)
      labels[#labels + 1] = display_label
      map[#labels] = i
      if code == selected_code then selected = #labels end
    end
  end
  if #labels == 0 then labels[1], map[1], selected = "English", 1, 1 end
  return labels, map, selected
end

function ScreenReader.refresh_language_menu()
  local ui = S and S.screen_reader_ui or nil
  if not (ui and ui.ids and ui.ids.language) then return end
  local labels, map, selected = ScreenReader.language_menu()
  ui.language_map = map
  ScreenReader.set_dropdown_items(ui.ids.language, labels, selected)
end

function ScreenReader.add_language_selector(ui)
  if not ui then return end
  local labels, map, selected = ScreenReader.language_menu()
  ui.language_map = map
  ui.ids.language_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.language_screen_reader_note", nil,
      "Be sure to set your screen reader software to this same language."),
    ScreenReader.t("a11y.sr.language_screen_reader_note.meaning", nil,
      "Reminder to match the screen reader voice or language with the selected ReaAssist language."),
    false, nil, "language_note")
  reagirl.NextLine()
  ui.ids.language = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(300),
    ScreenReader.t("settings.chat_language.label", nil, "Language"),
    ScreenReader.caption_width_px(100),
    ScreenReader.t("settings.chat_language.tooltip", nil,
      "Assistant replies and newly localized local reply surfaces use this language."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_language(menu_idx) end,
    "language")
end

function ScreenReader.language_changed_status_text(code)
  return ScreenReader.t("a11y.sr.language_changed", nil, "Language changed.")
end

function ScreenReader.commit_language(idx, code)
  if not (prefs and idx and code) then return end
  local return_view = (S and S._screen_reader_view == "terms") and "terms"
    or "settings"
  if not ScreenReader.language_supported_in_screen_reader(code) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.language_unavailable", nil,
      "That language is not available yet."), true)
    ScreenReader.refresh_language_menu()
    return
  end
  prefs.reply_language_idx = idx
  prefs.language_code = code
  if I18N and I18N.reload_language then pcall(I18N.reload_language, code) end
  if ScreenReader.save_config() then
    ScreenReader.set_status_after_rebuild(
      ScreenReader.language_changed_status_text(code), true)
    ScreenReader.focus_after_rebuild("language")
    ScreenReader.open_view(return_view)
  end
end

function ScreenReader.select_language(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local idx = ui and ui.language_map and ui.language_map[menu_idx]
  if not idx then return end
  local code = CFG and CFG.language_code_for_legacy_idx
    and CFG.language_code_for_legacy_idx(idx)
  if not code then return end
  if not ScreenReader.language_supported_in_screen_reader(code) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.language_unavailable", nil,
      "That language is not available yet."), true)
    ScreenReader.refresh_language_menu()
    ScreenReader.focus_after_rebuild("language")
    return
  end
  local has_catalog = code == "en" or (I18N and I18N.catalog_available
    and I18N.catalog_available(code))
  if has_catalog then return ScreenReader.commit_language(idx, code) end

  local pack_status = LangPacks and LangPacks.status_for_code
    and LangPacks.status_for_code(code)
  if pack_status == "downloading" then
    S._screen_reader_pending_language_code = code
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.language_download_waiting", nil,
      "Language pack is still downloading."), true)
    return
  end

  if LangPacks and LangPacks.start_language_download then
    local ok, reason = LangPacks.start_language_download(code, has_catalog)
    local started = ok or reason == "index_downloading"
      or (LangPacks.is_busy and LangPacks.is_busy())
    if started then
      S._screen_reader_pending_language_code = code
      ScreenReader.refresh_language_menu()
      ScreenReader.set_status(ScreenReader.t(
        "a11y.sr.language_download_started", nil,
        "Downloading language pack. ReaAssist will switch languages when it is ready."), true)
      return
    end
    ScreenReader.set_status(ScreenReader.t("a11y.sr.language_download_failed", {
      error = tostring(reason or ""),
    }, "Language pack download could not start: " .. tostring(reason or "")),
      true)
    ScreenReader.refresh_language_menu()
    return
  end
  ScreenReader.set_status(ScreenReader.t("a11y.sr.language_unavailable", nil,
    "That language is not available yet."), true)
end

function ScreenReader.track_language_download_status()
  if LangPacks and LangPacks.poll then pcall(LangPacks.poll) end
  local code = S and S._screen_reader_pending_language_code or nil
  if not code then return end
  if not ScreenReader.language_supported_in_screen_reader(code) then
    S._screen_reader_pending_language_code = nil
    ScreenReader.refresh_language_menu()
    ScreenReader.set_status(ScreenReader.t("a11y.sr.language_unavailable", nil,
      "That language is not available yet."), true)
    return
  end
  local has_catalog = code == "en" or (I18N and I18N.catalog_available
    and I18N.catalog_available(code))
  if has_catalog then
    S._screen_reader_pending_language_code = nil
    local idx = CFG and CFG.legacy_idx_for_language_code
      and CFG.legacy_idx_for_language_code(code)
    if idx then return ScreenReader.commit_language(idx, code) end
  end
  local pack_status = LangPacks and LangPacks.status_for_code
    and LangPacks.status_for_code(code)
  if pack_status == "failed" then
    S._screen_reader_pending_language_code = nil
    ScreenReader.refresh_language_menu()
    local d = LangPacks and LangPacks.download or nil
    ScreenReader.set_status(ScreenReader.t("a11y.sr.language_download_failed", {
      error = tostring(d and d.last_error or ""),
    }, "Language pack download failed."), true)
  end
end

function ScreenReader.contrast_label(value)
  value = tostring(value or (prefs and prefs.screen_reader_contrast) or "auto")
  if value == "dark" then
    return ScreenReader.t("a11y.sr.contrast_dark", nil, "Dark")
  elseif value == "light" then
    return ScreenReader.t("a11y.sr.contrast_light", nil, "Light")
  end
  return ScreenReader.t("a11y.sr.contrast_auto", nil, "Default")
end

function ScreenReader.contrast_menu()
  local labels = {
    ScreenReader.contrast_label("auto"),
    ScreenReader.contrast_label("dark"),
    ScreenReader.contrast_label("light"),
  }
  local map = { "auto", "dark", "light" }
  local selected = 1
  for i, value in ipairs(map) do
    if prefs and prefs.screen_reader_contrast == value then selected = i end
  end
  return labels, map, selected
end

function ScreenReader.select_contrast(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local value = ui and ui.contrast_map and ui.contrast_map[menu_idx]
  if not value then return end
  prefs.screen_reader_contrast = value
  if ScreenReader.save_config() then
    ScreenReader.set_status_after_rebuild(ScreenReader.t(
      "a11y.sr.contrast_changed", nil, "Contrast changed."), true)
    ScreenReader.focus_after_rebuild("contrast")
    ScreenReader.open_view("settings")
  end
end

function ScreenReader.text_size_menu()
  local labels, selected = {}, ScreenReader.text_size_idx()
  local source = CFG and CFG.SCREEN_READER_TEXT_SIZE_LABELS or {}
  for i = 1, #source do labels[i] = ScreenReader.text_size_label(i) end
  if #labels == 0 then
    labels = { "Default", "Large", "Extra Large", "Huge" }
  end
  if selected < 1 or selected > #labels then selected = 1 end
  return labels, selected
end

function ScreenReader.select_text_size(menu_idx)
  menu_idx = tonumber(menu_idx)
  local labels = ScreenReader.text_size_menu()
  if not (menu_idx and menu_idx >= 1 and menu_idx <= #labels) then return end
  prefs.screen_reader_text_size_idx = menu_idx
  if ScreenReader.save_config() then
    ScreenReader.set_status_after_rebuild(ScreenReader.t(
      "a11y.sr.text_size_changed", {
      value = labels[menu_idx],
    }, "Accessible size changed to " .. tostring(labels[menu_idx]) .. "."),
      true)
    ScreenReader.focus_after_rebuild("text_size")
    ScreenReader.open_view("settings")
  end
end

function ScreenReader.timeout_menu()
  local values = { 60, 120, 180, 300, 600, 1200, 1800 }
  local current = tonumber(prefs and prefs.cloud_request_timeout) or 180
  local current_in_presets = false
  for i, value in ipairs(values) do
    if value == current then current_in_presets = true end
  end
  if not current_in_presets then
    values[#values + 1] = current
    table.sort(values)
  end
  local labels, selected = {}, 1
  for i, value in ipairs(values) do
    labels[i] = ScreenReader.t("a11y.sr.seconds_value", {
      value = tostring(value),
    }, tostring(value) .. " seconds")
    if current == value then
      selected = i
    end
  end
  return labels, values, selected
end

function ScreenReader.select_timeout(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local value = ui and ui.timeout_map and ui.timeout_map[menu_idx]
  if not value then return end
  prefs.cloud_request_timeout = value
  if ScreenReader.save_config() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.timeout_changed", {
      value = tostring(value),
    }, "Cloud timeout changed to " .. tostring(value) .. " seconds."), true)
  end
  ScreenReader.refresh_settings_summary()
end

function ScreenReader.diagnostics_menu()
  local labels = {
    ScreenReader.t("settings.adv.diagnostics.basic", nil, "Basic"),
    ScreenReader.t("settings.adv.diagnostics.extended", nil, "Extended"),
    ScreenReader.t("a11y.sr.diagnostics_off", nil, "Off"),
  }
  local map = { "basic", "extended", "off" }
  local selected = 1
  local tier = (Diag and Diag.current_tier and Diag.current_tier())
    or (prefs and prefs.diag_auto_tier) or "off"
  for i, value in ipairs(map) do
    if tier == value then selected = i end
  end
  return labels, map, selected
end

function ScreenReader.diagnostics_tier_label(value)
  value = tostring(value or "off")
  if value == "basic" then
    return ScreenReader.t("settings.adv.diagnostics.basic", nil, "Basic")
  elseif value == "extended" then
    return ScreenReader.t("settings.adv.diagnostics.extended", nil, "Extended")
  end
  return ScreenReader.t("a11y.sr.diagnostics_off", nil, "Off")
end

function ScreenReader.select_diagnostics_tier(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local value = ui and ui.diagnostics_map and ui.diagnostics_map[menu_idx]
  if not value then return end
  if Diag and Diag.set_auto_tier then Diag.set_auto_tier(value)
  elseif prefs then prefs.diag_auto_tier = value end
  if ScreenReader.save_config() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.diagnostics_tier_changed", {
      value = ScreenReader.diagnostics_tier_label(value),
    }, "Automatic diagnostics changed to "
      .. ScreenReader.diagnostics_tier_label(value) .. "."), true)
  end
  ScreenReader.refresh_settings_summary()
end

function ScreenReader.custom_instructions_text()
  if Store and Store.custom_instructions_text then
    return Store.custom_instructions_text() or ""
  end
  return ""
end

function ScreenReader.custom_instructions_summary()
  local text = ScreenReader.custom_instructions_text()
  local enabled = prefs and prefs.custom_instructions_enabled
  return ScreenReader.t("a11y.sr.custom_instructions_summary", {
    enabled = ScreenReader.on_off(enabled),
    chars = tostring(#text),
  }, "Custom instructions " .. ScreenReader.on_off(enabled)
    .. ". " .. tostring(#text) .. " characters saved.")
end

function ScreenReader.set_custom_instructions_enabled(checked)
  local prev = prefs and prefs.custom_instructions_enabled
  if prefs then prefs.custom_instructions_enabled = checked == true end
  local err = Store and Store.save_custom_instructions_enabled
    and Store.save_custom_instructions_enabled(checked == true) or nil
  if err and prefs then prefs.custom_instructions_enabled = prev end
  ScreenReader.set_status(err and ScreenReader.t(
      "settings.custom_instructions.error.save_pref", nil,
      "Could not save Custom Instructions setting.")
    or ScreenReader.t("a11y.sr.custom_instructions_enabled_changed", {
      value = ScreenReader.on_off(prefs and prefs.custom_instructions_enabled),
    }, "Custom instructions are now "
      .. ScreenReader.on_off(prefs and prefs.custom_instructions_enabled) .. "."),
    true)
  ScreenReader.refresh_custom_instructions_summary()
end

function ScreenReader.refresh_custom_instructions_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.custom_instructions_summary then
    ScreenReader.set_label(ui.ids.custom_instructions_summary,
      ScreenReader.custom_instructions_summary())
  end
end

function ScreenReader.reload_custom_instructions_summary()
  ScreenReader.refresh_custom_instructions_summary()
  ScreenReader.set_status(ScreenReader.t(
    "a11y.sr.custom_instructions_reloaded", nil,
    "Custom instructions summary refreshed from disk."), true)
end

function ScreenReader.custom_instructions_example_text()
  return table.concat({
    ScreenReader.t("a11y.sr.custom_instructions_example.scope", nil,
      "Work only on selected tracks or items unless I say to edit the whole project."),
    ScreenReader.t("a11y.sr.custom_instructions_example.destructive", nil,
      "Ask before deleting tracks, items, takes, markers, regions, or FX."),
    ScreenReader.t("a11y.sr.custom_instructions_example.routing", nil,
      "Preserve existing routing, sends, receives, and folder structure unless I explicitly ask to change them."),
    ScreenReader.t("a11y.sr.custom_instructions_example.reversible", nil,
      "Prefer reversible REAPER actions and create clear undo points for session changes."),
  }, "\n")
end

function ScreenReader.open_custom_instructions_file()
  local path = RA and RA.CUSTOM_INSTRUCTIONS_PATH or nil
  if not path then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_instructions_path_missing", nil,
      "Custom instructions file path is not available."), true)
    return
  end
  if Store and Store.custom_instructions_write
      and not ScreenReader.file_exists(path) then
    Store.custom_instructions_write(ScreenReader.custom_instructions_text())
  end
  local ok = open_path(path)
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_instructions_opened", { path = path },
      "Opened custom instructions file: " .. tostring(path))
    or ScreenReader.t("a11y.sr.custom_instructions_open_failed", { path = path },
      "Could not open custom instructions file: " .. tostring(path)), true)
end

function ScreenReader.copy_custom_instructions()
  local text = ScreenReader.custom_instructions_text()
  local ok = text ~= "" and AppController.copy_text(text)
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_instructions_copied", nil,
      "Custom instructions copied to clipboard.")
    or ScreenReader.t("a11y.sr.custom_instructions_empty", nil,
      "No custom instructions are saved yet."), true)
end

function ScreenReader.copy_custom_instructions_example()
  local ok = AppController.copy_text(ScreenReader.custom_instructions_example_text())
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_instructions_example_copied", nil,
      "Custom instructions example copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil, "Copy failed."), true)
end

function ScreenReader.ensure_pref_plugins_rows()
  if S._screen_reader_pref_plugins_loaded and pref_plugins.rows
      and #pref_plugins.rows > 0 then
    S._screen_reader_pref_idx = math.min(
      math.max(tonumber(S._screen_reader_pref_idx) or 1, 1),
      math.max(#pref_plugins.rows, 1))
    return
  end
  pref_plugins.rows = {}
  for _, lbl in ipairs(PREF_PLUGIN_DEFAULTS or {}) do
    pref_plugins.rows[#pref_plugins.rows + 1] =
      { label = lbl, name = "", aliases = "" }
  end
  pref_plugins.rows[#pref_plugins.rows + 1] = { label = "", name = "", aliases = "" }
  pref_plugins.rows[#pref_plugins.rows + 1] = { label = "", name = "", aliases = "" }
  if CTX and CTX.load_pref_plugins then CTX.load_pref_plugins() end
  S._screen_reader_pref_plugins_loaded = true
  S._screen_reader_pref_idx = math.min(
    math.max(tonumber(S._screen_reader_pref_idx) or 1, 1),
    math.max(#pref_plugins.rows, 1))
end

function ScreenReader.pref_plugin_row(idx)
  ScreenReader.ensure_pref_plugins_rows()
  return pref_plugins.rows[tonumber(idx) or S._screen_reader_pref_idx or 1]
end

function ScreenReader.pref_plugin_key(label)
  if label_to_type_key then return label_to_type_key(label or "") end
  local key = tostring(label or ""):match("^%s*(.-)%s*$") or ""
  return key:lower():gsub("[%s%-]+", "_")
end

function ScreenReader.pref_plugin_type_menu()
  ScreenReader.ensure_pref_plugins_rows()
  local labels, map, selected = {}, {}, 1
  for i, row in ipairs(pref_plugins.rows) do
    local label = AppController.trim_text(row.label or "")
    if label ~= "" then
      labels[#labels + 1] = label
      map[#labels] = i
      if i == S._screen_reader_pref_idx then selected = #labels end
    end
  end
  if #labels == 0 then
    labels[1] = ScreenReader.t("a11y.sr.pref_plugins_no_types", nil,
      "No plugin types")
  end
  return labels, map, selected
end

function ScreenReader.pref_plugins_summary()
  ScreenReader.ensure_pref_plugins_rows()
  local saved, empty = {}, 0
  for _, row in ipairs(pref_plugins.rows) do
    local label = AppController.trim_text(row.label or "")
    local name = AppController.trim_text(row.name or "")
    if label ~= "" and name ~= "" then
      saved[#saved + 1] = label .. ": " .. name
    elseif label ~= "" then
      empty = empty + 1
    end
  end
  if #saved == 0 then
    return ScreenReader.t("a11y.sr.pref_plugins_summary_empty", {
      empty = tostring(empty),
    }, "No preferred plugins are saved. " .. tostring(empty)
      .. " plugin types are available.")
  end
  return ScreenReader.t("a11y.sr.pref_plugins_summary", {
    count = tostring(#saved),
  }, tostring(#saved) .. " preferred plugin(s) saved. "
    .. "Use Copy Mappings for the full list.")
end

function ScreenReader.pref_plugin_selected_summary()
  local row = ScreenReader.pref_plugin_row()
  local label = row and AppController.trim_text(row.label or "") or ""
  local name = row and AppController.trim_text(row.name or "") or ""
  local aliases = row and AppController.trim_text(row.aliases or "") or ""
  if label == "" then
    return ScreenReader.t("a11y.sr.pref_plugins_selected_empty", nil,
      "Selected row is empty.")
  end
  if name == "" then
    name = ScreenReader.t("a11y.sr.pref_plugins_no_plugin", nil,
      "no plugin selected")
  end
  if aliases == "" then
    aliases = ScreenReader.t("a11y.sr.pref_plugins_no_aliases", nil,
      "no aliases")
  end
  return ScreenReader.t("a11y.sr.pref_plugins_selected", {
    type = label,
    plugin = name,
    aliases = aliases,
  }, label .. ": " .. name .. ". Aliases: " .. aliases .. ".")
end

function ScreenReader.refresh_pref_plugins_summary()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids then
    ScreenReader.set_label(ui.ids.pref_plugins_summary,
      ScreenReader.pref_plugins_summary())
    ScreenReader.set_label(ui.ids.pref_plugins_selected,
      ScreenReader.pref_plugin_selected_summary())
    local labels, map, selected = ScreenReader.pref_plugin_type_menu()
    ui.pref_plugin_map = map
    ScreenReader.set_dropdown_items(ui.ids.pref_plugin_type, labels, selected)
  end
end

function ScreenReader.select_pref_plugin_type(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local idx = ui and ui.pref_plugin_map and ui.pref_plugin_map[menu_idx]
  if not idx then return end
  S._screen_reader_pref_idx = idx
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_type_changed",
    nil, "Preferred plugin type changed."), true)
end

function ScreenReader.set_selected_pref_plugin_name(text)
  local row = ScreenReader.pref_plugin_row()
  if not row then return end
  row.name = AppController.trim_text(text)
  pref_plugins.dirty = true
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_plugin_changed",
    nil, "Preferred plugin updated. Save when ready."), true)
end

function ScreenReader.paste_selected_pref_plugin_name()
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  if AppController.trim_text(text) == "" then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_empty", nil,
      "Clipboard is empty."), true)
    return
  end
  ScreenReader.set_selected_pref_plugin_name(text)
end

function ScreenReader.paste_selected_pref_plugin_aliases()
  local text = ScreenReader.clipboard_text()
  if text == nil then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.clipboard_unavailable",
      nil, "Clipboard access is not available."), true)
    return
  end
  local row = ScreenReader.pref_plugin_row()
  if not row then return end
  row.aliases = AppController.trim_text(text)
  pref_plugins.dirty = true
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_aliases_changed",
    nil, "Preferred plugin aliases updated. Save when ready."), true)
end

function ScreenReader.clear_selected_pref_plugin()
  local row = ScreenReader.pref_plugin_row()
  if not row then return end
  row.name = ""
  pref_plugins.dirty = true
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_plugin_cleared",
    nil, "Preferred plugin cleared for the selected type. Save when ready."),
    true)
end

function ScreenReader.pref_plugins_table_text()
  ScreenReader.ensure_pref_plugins_rows()
  local lines = {
    "# ReaAssist Screen Reader Preferred Plugins",
    "# Format: Type | aliases | plugin name",
  }
  for _, row in ipairs(pref_plugins.rows) do
    local label = AppController.trim_text(row.label or "")
    if label ~= "" then
      lines[#lines + 1] = label .. " | "
        .. AppController.trim_text(row.aliases or "") .. " | "
        .. AppController.trim_text(row.name or "")
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

function ScreenReader.pref_plugins_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP
    .. "ScreenReader_Preferred_Plugins.txt"
end

function ScreenReader.open_pref_plugins_file()
  local path = ScreenReader.pref_plugins_path()
  local ok = ScreenReader.write_text_file(path,
    ScreenReader.pref_plugins_table_text())
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.pref_plugins_file_opened", { path = path },
      "Preferred plugins file opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.pref_plugins_file_open_failed", { path = path },
      "Could not open preferred plugins file: " .. tostring(path)), true)
end

function ScreenReader.load_pref_plugins_file()
  local path = ScreenReader.pref_plugins_path()
  local text, err = ScreenReader.read_file(path)
  if not text then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_file_read_failed",
      { error = tostring(err or "unknown error") },
      "Could not read preferred plugins file: "
        .. tostring(err or "unknown error")), true)
    return
  end
  ScreenReader.ensure_pref_plugins_rows()
  local by_key = {}
  for _, row in ipairs(pref_plugins.rows) do
    local key = ScreenReader.pref_plugin_key(row.label or "")
    if key ~= "" then by_key[key] = row end
  end
  for line in text:gmatch("[^\r\n]+") do
    line = AppController.trim_text(line)
    if line ~= "" and not line:match("^#") then
      local label, aliases, name = line:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
      if label and AppController.trim_text(label) ~= "" then
        local key = ScreenReader.pref_plugin_key(label)
        local row = by_key[key]
        if not row then
          row = { label = AppController.trim_text(label), aliases = "", name = "" }
          pref_plugins.rows[#pref_plugins.rows + 1] = row
          by_key[key] = row
        end
        row.aliases = AppController.trim_text(aliases or "")
        row.name = AppController.trim_text(name or "")
      end
    end
  end
  pref_plugins.dirty = true
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_file_loaded",
    nil, "Preferred plugins loaded from file. Save when ready."), true)
end

function ScreenReader.copy_pref_plugins()
  local ok = AppController.copy_text(ScreenReader.pref_plugins_table_text())
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.pref_plugins_copied", nil,
      "Preferred plugins copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.save_pref_plugins(scan_after, force_scan)
  ScreenReader.ensure_pref_plugins_rows()
  if not (CTX and CTX.save_pref_plugins) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.pref_plugins_unavailable",
      nil, "Preferred plugin saving is not available in this build."), true)
    return
  end
  local err = CTX.save_pref_plugins()
  if err then
    ScreenReader.set_status(ScreenReader.t(
      "settings.pref_plugins.toast.save_failed",
      { error = tostring(err) }, "Save failed: " .. tostring(err)), true)
    return
  end
  pref_plugins.dirty = false
  if scan_after and CTX.pref_plugins_scan_start then
    pref_plugins.scan.status = ""
    CTX.pref_plugins_scan_start(force_scan == true)
    pref_plugins.pending_exit = false
    S._screen_reader_pref_scan_active = pref_plugins.scan.active == true
    ScreenReader.refresh_actions()
    ScreenReader.set_status(pref_plugins.scan.active
      and ScreenReader.t("settings.pref_plugins.status.scanning", nil,
        "Scanning parameters...")
      or ScreenReader.t("settings.pref_plugins.toast.saved", nil,
        "Preferences saved"), true)
    return
  end
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("settings.pref_plugins.toast.saved",
    nil, "Preferences saved"), true)
end

function ScreenReader.clear_pref_plugins()
  if FXCache and FXCache.clear_preferred_types then
    FXCache.clear_preferred_types()
  end
  if pref_plugins then
    pref_plugins.initialized = false
    pref_plugins.dirty = false
  end
  S._screen_reader_pref_plugins_loaded = false
  ScreenReader.ensure_pref_plugins_rows()
  ScreenReader.refresh_pref_plugins_summary()
  ScreenReader.set_status(ScreenReader.t("settings.pref_plugins.clear.toast",
    nil, "Preferred plugins cleared"), true)
end

function ScreenReader.open_pref_plugins_clear_confirm()
  ScreenReader.open_view("pref_plugins_clear_confirm")
end

function ScreenReader.confirm_clear_pref_plugins()
  ScreenReader.clear_pref_plugins()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "settings.pref_plugins.clear.toast", nil, "Preferred plugins cleared"),
    true)
  ScreenReader.open_view("pref_plugins")
end

function ScreenReader.cancel_clear_pref_plugins()
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.clear_cancelled", nil, "Clear cancelled."), true)
  ScreenReader.open_view("pref_plugins")
end

function ScreenReader.track_pref_plugin_scan()
  if not (pref_plugins and pref_plugins.scan) then return end
  local active = pref_plugins.scan.active == true
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.pref_plugins_scan_status then
    local status = pref_plugins.scan.status or ""
    if status == "" then
      status = active and ScreenReader.t(
          "settings.pref_plugins.status.scanning", nil,
          "Scanning parameters...")
        or ScreenReader.t("a11y.sr.pref_plugins_scan_idle", nil,
          "No scan is running.")
    end
    ScreenReader.set_label(ui.ids.pref_plugins_scan_status, status)
  end
  if S._screen_reader_pref_scan_active and not active then
    S._screen_reader_pref_scan_active = false
    pref_plugins.pending_exit = false
    ScreenReader.set_status((pref_plugins.scan.status ~= ""
        and pref_plugins.scan.status)
      or ScreenReader.t("a11y.sr.pref_plugins_scan_done", nil,
        "Preferred plugin scan finished."), true)
    ScreenReader.refresh_pref_plugins_summary()
    ScreenReader.refresh_actions()
  end
end

function ScreenReader.fx_cache_lists()
  local cache = FXCache and FXCache.load and FXCache.load() or {}
  local plugins = type(cache.plugins) == "table" and cache.plugins or {}
  local scanned, curated, seen_curated = {}, {}, {}
  for ident in pairs(plugins) do
    if Code and Code.is_curated_plugin and Code.is_curated_plugin(ident) then
      if not seen_curated[ident] then
        curated[#curated + 1] = ident
        seen_curated[ident] = true
      end
    else
      scanned[#scanned + 1] = ident
    end
  end
  local pref_types = FXCache and FXCache.get_preferred_types
    and FXCache.get_preferred_types() or {}
  for _, ident in pairs(pref_types or {}) do
    if ident and ident ~= "" and Code and Code.is_curated_plugin
        and Code.is_curated_plugin(ident) and not seen_curated[ident] then
      curated[#curated + 1] = ident
      seen_curated[ident] = true
    end
  end
  table.sort(scanned)
  table.sort(curated)
  return scanned, curated, cache
end

function ScreenReader.fx_cache_summary()
  local scanned, curated = ScreenReader.fx_cache_lists()
  if #scanned == 0 and #curated == 0 then
    return ScreenReader.t("a11y.sr.fx_cache_empty", nil,
      "No plugins are cached yet.")
  end
  return ScreenReader.t("a11y.sr.fx_cache_summary", {
    scanned = tostring(#scanned),
    curated = tostring(#curated),
  }, tostring(#scanned) .. " scanned plugin(s), " .. tostring(#curated)
    .. " built-in reference(s).")
end

function ScreenReader.fx_cache_menu()
  local scanned = ScreenReader.fx_cache_lists()
  local labels, map = {}, {}
  local selected = tonumber(S and S._screen_reader_fx_cache_idx) or 1
  for i, ident in ipairs(scanned) do
    labels[#labels + 1] = ScreenReader.clean_label(ident, 92)
    map[#labels] = i
  end
  if #labels == 0 then
    labels[1] = ScreenReader.t("a11y.sr.fx_cache_no_scanned", nil,
      "No scanned plugins")
    map[1] = nil
    selected = 1
  elseif selected < 1 or selected > #labels then
    selected = 1
  end
  return labels, map, selected
end

function ScreenReader.fx_cache_selected_ident()
  local scanned = ScreenReader.fx_cache_lists()
  local idx = tonumber(S and S._screen_reader_fx_cache_idx) or 1
  if idx < 1 or idx > #scanned then idx = 1 end
  S._screen_reader_fx_cache_idx = idx
  return scanned[idx]
end

function ScreenReader.fx_cache_selected_summary()
  local ident = ScreenReader.fx_cache_selected_ident()
  if not ident then
    return ScreenReader.t("a11y.sr.fx_cache_selected_empty", nil,
      "No scanned plugin is selected.")
  end
  local pdata = FXCache and FXCache.get_plugin and FXCache.get_plugin(ident)
    or nil
  local param_n = pdata and pdata.params and #pdata.params
    or tonumber(pdata and pdata.param_count) or 0
  if pdata and pdata.needs_deep_scan then
    return ScreenReader.t("a11y.sr.fx_cache_selected_needs_deep", {
      plugin = ident,
      count = tostring(param_n),
    }, ident .. ": " .. tostring(param_n)
      .. " parameters. Deep scan recommended.")
  end
  return ScreenReader.t("a11y.sr.fx_cache_selected", {
    plugin = ident,
    count = tostring(param_n),
  }, ident .. ": " .. tostring(param_n) .. " parameters cached.")
end

function ScreenReader.fx_cache_scan_status()
  if fx_cache_ui and fx_cache_ui.rescan_all and fx_cache_ui.rescan_all.active then
    local ra = fx_cache_ui.rescan_all
    return ScreenReader.t("a11y.sr.fx_cache_rescan_all_progress", {
      done = tostring(ra.index or 0),
      total = tostring(ra.total or 0),
    }, "Rescanning " .. tostring(ra.index or 0) .. " of "
      .. tostring(ra.total or 0) .. ".")
  end
  if deep_scan and deep_scan.active and deep_scan.origin == "fx_cache" then
    return ScreenReader.t("a11y.sr.fx_cache_deep_progress", {
      plugin = tostring(deep_scan.identifier or "plugin"),
      done = tostring(deep_scan.probes_done or 0),
      total = tostring(deep_scan.total_probes or 0),
    }, "Deep scanning " .. tostring(deep_scan.identifier or "plugin")
      .. ": " .. tostring(deep_scan.probes_done or 0) .. " of "
      .. tostring(deep_scan.total_probes or 0) .. ".")
  end
  if fx_cache_ui and fx_cache_ui.rescan and fx_cache_ui.rescan.status
      and fx_cache_ui.rescan.status ~= "" then
    return fx_cache_ui.rescan.status
  end
  return ScreenReader.t("a11y.sr.fx_cache_scan_idle", nil,
    "No FX cache scan is running.")
end

function ScreenReader.fx_cache_busy()
  return (fx_cache_ui and fx_cache_ui.rescan and fx_cache_ui.rescan.active)
    or (fx_cache_ui and fx_cache_ui.rescan_all
      and fx_cache_ui.rescan_all.active)
    or (deep_scan and deep_scan.active)
end

function ScreenReader.refresh_fx_cache_summary()
  local ui = S and S.screen_reader_ui or nil
  if not (ui and ui.ids) then return end
  ScreenReader.set_label(ui.ids.fx_cache_summary, ScreenReader.fx_cache_summary())
  ScreenReader.set_label(ui.ids.fx_cache_selected,
    ScreenReader.fx_cache_selected_summary())
  ScreenReader.set_label(ui.ids.fx_cache_scan_status,
    ScreenReader.fx_cache_scan_status())
  local labels, map, selected = ScreenReader.fx_cache_menu()
  ui.fx_cache_map = map
  ScreenReader.set_dropdown_items(ui.ids.fx_cache_plugin, labels, selected)
end

function ScreenReader.select_fx_cache_plugin(menu_idx)
  local ui = S and S.screen_reader_ui or nil
  local idx = ui and ui.fx_cache_map and ui.fx_cache_map[menu_idx]
  if not idx then return end
  S._screen_reader_fx_cache_idx = idx
  ScreenReader.refresh_fx_cache_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_selected_changed",
    nil, "Cached plugin selected."), true)
end

function ScreenReader.fx_cache_table_text()
  local scanned, curated, cache = ScreenReader.fx_cache_lists()
  local lines = {
    "# ReaAssist Screen Reader FX Parameter Cache",
    "# Scanned plugin parameter cache",
  }
  if #scanned == 0 then
    lines[#lines + 1] = "No scanned plugins."
  else
    for _, ident in ipairs(scanned) do
      local pdata = cache.plugins and cache.plugins[ident] or {}
      local param_n = pdata and pdata.params and #pdata.params
        or tonumber(pdata and pdata.param_count) or 0
      local deep = pdata and pdata.needs_deep_scan and "yes" or "no"
      lines[#lines + 1] = ident .. " | params: " .. tostring(param_n)
        .. " | deep recommended: " .. deep
    end
  end
  if #curated > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "# Built-in references from Plugin_Ref.md"
    for _, ident in ipairs(curated) do
      lines[#lines + 1] = ident .. " | built-in reference"
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

function ScreenReader.fx_cache_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP
    .. "ScreenReader_FX_Param_Cache.txt"
end

function ScreenReader.copy_fx_cache_list()
  local ok = AppController.copy_text(ScreenReader.fx_cache_table_text())
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.fx_cache_copied", nil,
      "FX parameter cache list copied to clipboard.")
    or ScreenReader.t("a11y.sr.copy_failed", nil,
      "Could not copy the response."), true)
end

function ScreenReader.open_fx_cache_file()
  local path = ScreenReader.fx_cache_path()
  local ok = ScreenReader.write_text_file(path, ScreenReader.fx_cache_table_text())
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.fx_cache_file_opened", { path = path },
      "FX parameter cache file opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.fx_cache_file_open_failed", { path = path },
      "Could not open FX parameter cache file: " .. tostring(path)), true)
end

function ScreenReader.rescan_selected_fx_cache(deep)
  if ScreenReader.fx_cache_busy() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_busy", nil,
      "Finish the current FX cache operation first."), true)
    return
  end
  local ident = ScreenReader.fx_cache_selected_ident()
  if not ident then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_none_selected",
      nil, "No cached plugin is selected."), true)
    return
  end
  if not (CTX and CTX.fx_cache_rescan_start) then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_unavailable",
      nil, "FX parameter cache controls are not available in this build."),
      true)
    return
  end
  fx_cache_ui.rescan.status = ""
  CTX.fx_cache_rescan_start(ident, deep == true)
  S._screen_reader_fx_cache_active = true
  ScreenReader.refresh_fx_cache_summary()
  ScreenReader.set_status(deep and ScreenReader.t(
      "a11y.sr.fx_cache_deep_started", { plugin = ident },
      "Deep scan started: " .. ident)
    or ScreenReader.t("a11y.sr.fx_cache_rescan_started", { plugin = ident },
      "Rescan started: " .. ident), true)
end

function ScreenReader.remove_selected_fx_cache()
  local ident = S and S._screen_reader_fx_cache_remove_ident or nil
  if ident == nil or ident == "" then ident = ScreenReader.fx_cache_selected_ident() end
  if not ident then return end
  local err = FXCache and FXCache.remove_plugin and FXCache.remove_plugin(ident)
  ScreenReader.set_status_after_rebuild(err
    and ScreenReader.t("a11y.sr.fx_cache_remove_failed", {
      error = tostring(err),
    }, "Could not remove cached plugin: " .. tostring(err))
    or ScreenReader.t("a11y.sr.fx_cache_removed", { plugin = ident },
      "Removed cached plugin: " .. ident), true)
  S._screen_reader_fx_cache_remove_ident = nil
  ScreenReader.open_view("fx_cache")
end

function ScreenReader.open_fx_cache_remove_confirm()
  local ident = ScreenReader.fx_cache_selected_ident()
  if not ident then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_none_selected",
      nil, "No cached plugin is selected."), true)
    return
  end
  S._screen_reader_fx_cache_remove_ident = ident
  ScreenReader.open_view("fx_cache_remove_confirm")
end

function ScreenReader.rescan_all_fx_cache()
  if ScreenReader.fx_cache_busy() then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_busy", nil,
      "Finish the current FX cache operation first."), true)
    return
  end
  local scanned = ScreenReader.fx_cache_lists()
  if #scanned == 0 then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_no_scanned",
      nil, "No scanned plugins"), true)
    return
  end
  if CTX and CTX.fx_cache_rescan_all_start then
    CTX.fx_cache_rescan_all_start(scanned)
    S._screen_reader_fx_cache_active = true
    ScreenReader.set_status_after_rebuild(ScreenReader.t(
      "a11y.sr.fx_cache_rescan_all_started", { count = tostring(#scanned) },
      "Rescan all started for " .. tostring(#scanned) .. " plugin(s)."),
      true)
  end
  ScreenReader.open_view("fx_cache")
end

function ScreenReader.cancel_fx_cache_scan()
  if fx_cache_ui and fx_cache_ui.rescan_all and fx_cache_ui.rescan_all.active
      and CTX and CTX.fx_cache_rescan_all_cancel then
    CTX.fx_cache_rescan_all_cancel()
  elseif deep_scan and deep_scan.active and CTX and CTX.cancel_deep_scan then
    CTX.cancel_deep_scan()
  else
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_scan_idle", nil,
      "No FX cache scan is running."), true)
    return
  end
  ScreenReader.refresh_fx_cache_summary()
  ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_cancelled", nil,
    "FX cache operation cancelled."), true)
end

function ScreenReader.clear_fx_cache()
  local err = FXCache and FXCache.clear_plugins and FXCache.clear_plugins()
  ScreenReader.set_status_after_rebuild(err
    and ScreenReader.t("a11y.sr.fx_cache_clear_failed", {
      error = tostring(err),
    }, "Could not clear FX parameter cache: " .. tostring(err))
    or ScreenReader.t("settings.fx_cache.action.clear_all", nil,
      "Clear All") .. ".",
    true)
  ScreenReader.open_view("fx_cache")
end

function ScreenReader.open_fx_cache_clear_confirm()
  ScreenReader.open_view("fx_cache_clear_confirm")
end

function ScreenReader.open_fx_cache_rescan_all_confirm()
  local scanned = ScreenReader.fx_cache_lists()
  if #scanned == 0 then
    ScreenReader.set_status(ScreenReader.t("a11y.sr.fx_cache_no_scanned",
      nil, "No scanned plugins"), true)
    return
  end
  ScreenReader.open_view("fx_cache_rescan_all_confirm")
end

function ScreenReader.track_fx_cache_scan()
  local ui = S and S.screen_reader_ui or nil
  if ui and ui.ids and ui.ids.fx_cache_scan_status then
    ScreenReader.set_label(ui.ids.fx_cache_scan_status,
      ScreenReader.fx_cache_scan_status())
  end
  if ui and ui.ids then
    local scanned = ScreenReader.fx_cache_lists()
    local has_selected = ScreenReader.fx_cache_selected_ident() ~= nil
    local busy = ScreenReader.fx_cache_busy()
    ScreenReader.set_button_disabled(ui.ids.rescan_selected,
      busy or not has_selected)
    ScreenReader.set_button_disabled(ui.ids.deep_selected,
      busy or not has_selected)
    ScreenReader.set_button_disabled(ui.ids.remove_selected,
      busy or not has_selected)
    ScreenReader.set_button_disabled(ui.ids.rescan_all, busy or #scanned == 0)
    ScreenReader.set_button_disabled(ui.ids.clear_all, busy or #scanned == 0)
    ScreenReader.set_button_disabled(ui.ids.cancel_scan, not busy)
  end
  local active = ScreenReader.fx_cache_busy()
  if S._screen_reader_fx_cache_active and not active then
    S._screen_reader_fx_cache_active = false
    ScreenReader.set_status(ScreenReader.fx_cache_scan_status(), true)
    ScreenReader.refresh_fx_cache_summary()
    ScreenReader.refresh_actions()
  end
end

function ScreenReader.custom_provider_records()
  if Custom and Custom.load_all then
    local ok, records = pcall(Custom.load_all)
    if ok and type(records) == "table" then return records end
  end
  return {}
end

function ScreenReader.custom_providers_summary()
  local records = ScreenReader.custom_provider_records()
  if #records == 0 then
    return ScreenReader.t("a11y.sr.custom_providers_empty", nil,
      "No local or custom providers are saved.")
  end
  local names = {}
  for i, rec in ipairs(records) do
    if i > 3 then break end
    local label = AppController.trim_text(rec.label or rec.id or "")
    local models = type(rec.models) == "table" and #rec.models or 0
    names[#names + 1] = label .. " (" .. tostring(models) .. " model"
      .. (models == 1 and "" or "s") .. ")"
  end
  local more = #records > #names and ScreenReader.t(
      "a11y.sr.custom_providers_more", { count = tostring(#records - #names) },
      ", plus " .. tostring(#records - #names) .. " more")
    or ""
  return ScreenReader.t("a11y.sr.custom_providers_summary", {
    count = tostring(#records),
    providers = table.concat(names, "; "),
    more = more,
  }, tostring(#records) .. " custom provider(s): "
    .. table.concat(names, "; ") .. more .. ".")
end

function ScreenReader.custom_providers_document(records)
  if Store and Store.providers_document then
    return Store.providers_document(records or ScreenReader.custom_provider_records())
  end
  return {
    schema_version = 1,
    records = records or ScreenReader.custom_provider_records(),
  }
end

function ScreenReader.custom_provider_template_record()
  local id = Custom and Custom.gen_id and Custom.gen_id()
    or ("custom_" .. tostring(os.time()))
  return {
    id = id,
    label = "Ollama Local",
    endpoint = "http://localhost:11434/v1/chat/completions",
    timeout_secs = 180,
    connect_timeout_secs = 10,
    allow_insecure = false,
    model_prefix = "",
    extra_headers = {},
    models = {
      {
        id = "qwen2.5-coder:14b",
        price_in = 0,
        price_cache_r = 0,
        price_out = 0,
        context_window = 32768,
        notes = "local",
      },
    },
  }
end

function ScreenReader.custom_provider_template_json()
  local id = Custom and Custom.gen_id and Custom.gen_id()
    or ("custom_" .. tostring(os.time()))
  return table.concat({
    "{",
    '  "schema_version": 1,',
    '  "records": [',
    "    {",
    '      "id": "' .. id .. '",',
    '      "label": "Ollama Local",',
    '      "endpoint": "http://localhost:11434/v1/chat/completions",',
    '      "timeout_secs": 180,',
    '      "connect_timeout_secs": 10,',
    '      "allow_insecure": false,',
    '      "model_prefix": "",',
    '      "extra_headers": [],',
    '      "models": [',
    "        {",
    '          "id": "qwen2.5-coder:14b",',
    '          "price_in": 0,',
    '          "price_cache_r": 0,',
    '          "price_out": 0,',
    '          "context_window": 32768,',
    '          "notes": "local"',
    "        }",
    "      ]",
    "    }",
    "  ]",
    "}",
    "",
  }, "\n")
end

function ScreenReader.custom_providers_json(use_template_when_empty)
  local records = ScreenReader.custom_provider_records()
  if use_template_when_empty and #records == 0 then
    return ScreenReader.custom_provider_template_json()
  end
  if #records == 0 then
    return "{\n  \"schema_version\": 1,\n  \"records\": []\n}\n"
  end
  local doc = ScreenReader.custom_providers_document(records)
  local ok, json, err = pcall(function()
    return JSON and JSON.encode and JSON.encode(doc, "  ")
  end)
  if not ok then json, err = nil, json end
  if not json then return nil, tostring(err or "JSON encode failed") end
  return json .. "\n"
end

function ScreenReader.custom_providers_path()
  return RA.DATA_DIR .. "Temp" .. RA.SEP
    .. "ScreenReader_Custom_Providers.json"
end

function ScreenReader.open_custom_providers_file()
  local path = ScreenReader.custom_providers_path()
  local text, err = ScreenReader.custom_providers_json(true)
  if not text then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_json_failed", { error = tostring(err) },
      "Could not build provider JSON: " .. tostring(err)), true)
    return
  end
  local ok = ScreenReader.write_text_file(path, text)
  if ok then ok = open_path(path) end
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_providers_file_opened",
      { path = path }, "Custom providers file opened: " .. tostring(path))
    or ScreenReader.t("a11y.sr.custom_providers_file_open_failed",
      { path = path }, "Could not open custom providers file: "
        .. tostring(path)), true)
end

function ScreenReader.copy_custom_providers_json()
  local text, err = ScreenReader.custom_providers_json(false)
  local ok = text and AppController.copy_text(text)
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_providers_copied", nil,
      "Custom providers JSON copied to clipboard.")
    or ScreenReader.t("a11y.sr.custom_providers_json_failed", {
      error = tostring(err or "copy failed"),
    }, "Could not build provider JSON: " .. tostring(err or "copy failed")),
    true)
end

function ScreenReader.copy_custom_provider_template()
  local text = ScreenReader.custom_provider_template_json()
  local err = nil
  local ok = text and AppController.copy_text(text .. "\n")
  ScreenReader.set_status(ok
    and ScreenReader.t("a11y.sr.custom_provider_template_copied", nil,
      "Custom provider template copied to clipboard.")
    or ScreenReader.t("a11y.sr.custom_providers_json_failed", {
      error = tostring(err or "copy failed"),
    }, "Could not build provider JSON: " .. tostring(err or "copy failed")),
    true)
end

function ScreenReader.load_custom_providers_file()
  local path = ScreenReader.custom_providers_path()
  local text, read_err = ScreenReader.read_file(path)
  if not text then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_file_read_failed",
      { error = tostring(read_err or "unknown error") },
      "Could not read custom providers file: "
        .. tostring(read_err or "unknown error")), true)
    return
  end
  local doc, decode_err = JSON.decode(text)
  if not doc or type(doc) ~= "table" or type(doc.records) ~= "table" then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_invalid_json",
      { error = tostring(decode_err or "records missing") },
      "Custom providers JSON is invalid: "
        .. tostring(decode_err or "records missing")), true)
    return
  end
  local records = {}
  for i, src in ipairs(doc.records) do
    local rec = Store and Store._provider_record_from_json
      and Store._provider_record_from_json(src, i) or nil
    if rec then records[#records + 1] = rec end
  end
  if #records == 0 and #doc.records > 0 then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_no_valid_records", nil,
      "No valid provider records were found in the file."), true)
    return
  end
  local err = Store and Store.save_providers and Store.save_providers(records)
  if err then
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_save_failed", { error = tostring(err) },
      "Could not save custom providers: " .. tostring(err)), true)
    return
  end
  if Custom and Custom.register_all then Custom.register_all() end
  if prefs and PROVIDERS and prefs.provider_idx > #PROVIDERS then
    prefs.provider_idx = 1
  end
  if MODELS and MODELS.refresh then MODELS.refresh() end
  if AppController and AppController.active_provider then
    local active = AppController.active_provider()
    S.api_key = active and S.api_key_map and S.api_key_map[active.id] or nil
  end
  ScreenReader.set_status_after_rebuild(ScreenReader.t(
    "a11y.sr.custom_providers_loaded",
    { count = tostring(#records) },
    "Loaded " .. tostring(#records) .. " custom provider(s)."), true)
  ScreenReader.open_view("custom_providers")
end

function ScreenReader.open_providers_json_source()
  if RA and RA.PROVIDERS_PATH and RA.PROVIDERS_PATH ~= ""
      and ScreenReader.file_exists(RA.PROVIDERS_PATH) then
    local ok = open_path(RA.PROVIDERS_PATH)
    ScreenReader.set_status(ok
      and ScreenReader.t("a11y.sr.custom_providers_source_opened",
        { path = RA.PROVIDERS_PATH },
        "Providers JSON opened: " .. tostring(RA.PROVIDERS_PATH))
      or ScreenReader.t("a11y.sr.custom_providers_file_open_failed",
        { path = RA.PROVIDERS_PATH },
        "Could not open custom providers file: "
          .. tostring(RA.PROVIDERS_PATH)), true)
  else
    ScreenReader.set_status(ScreenReader.t(
      "a11y.sr.custom_providers_source_missing", nil,
      "Providers.json does not exist yet. Use Open Edit File to create one."),
      true)
  end
end

function ScreenReader.build_terms_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.tos_title.meaning", nil,
      "Accessible Terms of Use screen for ReaAssist."),
    false, nil, "terms_title")

  reagirl.NextLine()
  ScreenReader.add_language_selector(ui)

  reagirl.NextLine()
  ui.ids.intro = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.tos_intro", nil,
      "Read the Terms of Use. Choose I Agree to continue, or Close to exit."),
    ScreenReader.t("a11y.sr.tos_intro.meaning", nil,
      "Instructions for accepting or declining the Terms of Use."),
    false, nil, "terms_intro")

  reagirl.NextLine()
  ui.ids.accept = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("tos.agree", nil, "I Agree"),
    ScreenReader.t("a11y.sr.tos_accept.meaning", nil,
      "Accepts the Terms of Use and opens ReaAssist Screen Reader Mode."),
    function() ScreenReader.accept_terms() end,
    "terms_accept")
  ui.ids.copy = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_terms", nil, "Copy Terms"),
    ScreenReader.t("a11y.sr.copy_terms.meaning", nil,
      "Copies the Terms of Use text to the clipboard."),
    function() ScreenReader.copy_terms_text() end,
    "copy_terms")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.tos_close.meaning", nil,
      "Closes ReaAssist without accepting the Terms of Use."),
    function() ScreenReader.decline_terms() end,
    "terms_close")

  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.tos_status", nil,
      "Terms are waiting for your choice."),
    ScreenReader.t("a11y.sr.tos_status.meaning", nil,
      "Current Terms screen status."),
    false, nil, "terms_status")

  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.wrap_text(ScreenReader.terms_text(), 86),
    ScreenReader.t("a11y.sr.tos_body.meaning", nil,
      "Terms of Use text."),
    false, nil, "terms_body")

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 640, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t("a11y.sr.tos_opened", nil,
      "Terms of Use opened. Choose I Agree to continue, or Close to exit."))
  end
  return ok == 1
end

function ScreenReader.build_settings_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.settings_title.meaning", nil,
      "Settings for ReaAssist Screen Reader Mode."),
    false, nil, "settings_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")
  reagirl.NextLine()
  ui.ids.settings_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.settings_summary_display_text(),
    ScreenReader.t("a11y.sr.settings_summary.meaning", nil,
      "Readable summary of the current settings."),
    false, nil, "settings_summary")
  reagirl.NextLine()
  ui.ids.update_status = reagirl.Label_Add(nil, nil,
    AppController.update_status_text and AppController.update_status_text()
      or ScreenReader.t("a11y.sr.update_status.idle", nil,
        "No update check is running."),
    ScreenReader.t("a11y.sr.update_status.meaning", nil,
      "Current update check, update, or repair status."),
    false, nil, "update_status")
  reagirl.NextLine()
  ui.ids.api_keys = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.api_keys", nil, "API Keys"),
    ScreenReader.t("a11y.sr.api_keys.meaning", nil,
      "Opens accessible API key setup and testing."),
    function() ScreenReader.open_api_keys_settings() end,
    "api_keys")
  ui.ids.custom_providers = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.api.custom_providers.label", nil,
      "Local & Custom Providers"),
    ScreenReader.t("a11y.sr.custom_providers.meaning", nil,
      "Opens accessible local and custom provider management."),
    function() ScreenReader.open_view("custom_providers") end,
    "custom_providers")
  ui.ids.custom_instructions = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.custom_instructions.label", nil,
      "Custom Instructions"),
    ScreenReader.t("a11y.sr.custom_instructions.meaning", nil,
      "Opens accessible controls for custom instructions."),
    function() ScreenReader.open_view("custom_instructions") end,
    "custom_instructions")
  reagirl.NextLine()
  ui.ids.pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.pref.preferred_plugins.label", nil,
      "Preferred Plugins"),
    ScreenReader.t("a11y.sr.pref_plugins.meaning", nil,
      "Opens accessible preferred plugin mappings."),
    function() ScreenReader.open_view("pref_plugins") end,
    "pref_plugins")
  ui.ids.fx_cache = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache", nil, "FX Cache"),
    ScreenReader.t("a11y.sr.fx_cache.meaning", nil,
      "Opens accessible FX parameter cache controls."),
    function() ScreenReader.open_view("fx_cache") end,
    "fx_cache")

  reagirl.NextLine()
  ui.ids.check_updates = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.check_updates", nil, "Check Updates"),
    ScreenReader.t("a11y.sr.check_updates.meaning", nil,
      "Checks for ReaAssist updates and install repairs."),
    function() ScreenReader.check_updates() end,
    "check_updates")
  ui.ids.apply_update = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.apply_update", nil, "Apply Update or Repair"),
    ScreenReader.t("a11y.sr.apply_update.meaning", nil,
      "Applies the available ReaAssist update or file repair."),
    function() ScreenReader.apply_update() end,
    "apply_update")

  reagirl.NextLine()
  ui.ids.reset_window = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.adv.reset_window.label", nil,
      "Reset Window Size"),
    ScreenReader.t("a11y.sr.reset_window.meaning", nil,
      "Reset window to default size and clear saved position."),
    function() ScreenReader.reset_window_size() end,
    "reset_window")
  ui.ids.factory_reset = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.adv.factory_reset.label", nil, "Factory Reset"),
    ScreenReader.t("a11y.sr.factory_reset.meaning", nil,
      "Clear all keys, preferences, and settings to start fresh."),
    function() ScreenReader.open_factory_reset_confirm() end,
    "factory_reset")

  reagirl.NextLine()
  ui.ids.include_snapshot = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.include_snapshot", nil,
      "Include session snapshot"),
    ScreenReader.t("a11y.sr.include_snapshot.meaning", nil,
      "Includes track, project, and relevant session context with requests."),
    prefs and prefs.include_snapshot == true,
    function(_, checked)
      ScreenReader.set_pref_bool("include_snapshot", checked,
        "a11y.sr.include_snapshot_changed",
        "Include session snapshot is now {value}.")
    end,
    "include_snapshot")
  ScreenReader.next_line_for_large_text()
  ui.ids.include_api_ref = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.include_api_ref", nil,
      "Include REAPER API reference"),
    ScreenReader.t("a11y.sr.include_api_ref.meaning", nil,
      "Includes additional REAPER API reference context with requests."),
    prefs and prefs.include_api_ref == true,
    function(_, checked)
      ScreenReader.set_pref_bool("include_api_ref", checked,
        "a11y.sr.include_api_ref_changed",
        "Include REAPER API reference is now {value}.")
    end,
    "include_api_ref")

  reagirl.NextLine()
  ui.ids.show_details = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.show_details", nil,
      "Show response details"),
    ScreenReader.t("a11y.sr.show_details.meaning", nil,
      "Shows model, token count, time, and cost details when available."),
    prefs and prefs.show_details == true,
    function(_, checked)
      ScreenReader.set_pref_bool("show_details", checked,
        "a11y.sr.show_details_changed",
        "Show response details is now {value}.")
    end,
    "show_details")
  ScreenReader.next_line_for_large_text()
  ui.ids.debug_logging = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.debug_logging", nil, "Enable advanced log"),
    ScreenReader.t("a11y.sr.debug_logging.meaning", nil,
      "Writes detailed request and diagnostic logs for troubleshooting."),
    prefs and prefs.debug_logging == true,
    function(_, checked)
      ScreenReader.set_pref_bool("debug_logging", checked,
        "a11y.sr.debug_logging_changed",
        "Advanced log is now {value}.")
    end,
    "debug_logging")
  ScreenReader.next_line_for_large_text()
  ui.ids.update_check = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("settings.pref.update_check.label", nil,
      "Check for updates on startup"),
    ScreenReader.t("a11y.sr.update_check.meaning", nil,
      "Automatically checks for ReaAssist updates when REAPER starts."),
    prefs and prefs.update_check == true,
    function(_, checked)
      ScreenReader.set_pref_bool("update_check", checked,
        "a11y.sr.update_check_changed",
        "Check for updates on startup is now {value}.")
    end,
    "update_check")

  reagirl.NextLine()
  ui.ids.concise_hints = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.concise_hints", nil, "Concise focus hints"),
    ScreenReader.t("a11y.sr.concise_hints.meaning", nil,
      "Shortens repeated focus descriptions in Screen Reader Mode."),
    prefs and prefs.screen_reader_concise_hints == true,
    function(_, checked) ScreenReader.set_concise_hints(checked) end,
    "concise_hints")

  reagirl.NextLine()
  ui.ids.prefer_screen_reader = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.prefer_screen_reader", nil,
      "Always open ReaAssist in Screen Reader Mode"),
    ScreenReader.t("a11y.sr.prefer_screen_reader.meaning", nil,
      "When enabled, launching the normal ReaAssist action hands off to this accessible interface."),
    ScreenReader.prefer_screen_reader_enabled(),
    function(_, checked) ScreenReader.set_prefer_screen_reader(checked) end,
    "prefer_screen_reader")
  ui.ids.open_visual = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.open_visual_now", nil,
      "Open Visual Interface Now"),
    ScreenReader.t("a11y.sr.open_visual_now.meaning", nil,
      "Turns off the Screen Reader Mode default and reopens ReaAssist in its visual interface."),
    function() ScreenReader.open_visual_switch_confirm() end,
    "open_visual_now")

  reagirl.NextLine()
  ScreenReader.add_language_selector(ui)

  local labels, selected = ScreenReader.text_size_menu()
  local map
  reagirl.NextLine()
  ui.ids.text_size = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(210),
    ScreenReader.t("a11y.sr.text_size", nil, "Accessible Size"),
    ScreenReader.caption_width_px(120),
    ScreenReader.t("a11y.sr.text_size.meaning", nil,
      "Changes text size and spacing in Screen Reader Mode."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_text_size(menu_idx) end,
    "text_size")

  labels, map, selected = ScreenReader.contrast_menu()
  ui.contrast_map = map
  ScreenReader.next_line_for_large_text()
  ui.ids.contrast = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(190),
    ScreenReader.t("a11y.sr.contrast", nil, "Contrast"),
    ScreenReader.caption_width_px(90),
    ScreenReader.t("a11y.sr.contrast.meaning", nil,
      "Chooses the visual contrast for Screen Reader Mode."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_contrast(menu_idx) end,
    "contrast")

  labels, map, selected = ScreenReader.timeout_menu()
  ui.timeout_map = map
  reagirl.NextLine()
  ui.ids.timeout = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(260),
    ScreenReader.t("a11y.sr.cloud_timeout", nil, "Cloud Timeout"),
    ScreenReader.caption_width_px(112),
    ScreenReader.t("a11y.sr.cloud_timeout.meaning", nil,
      "How long ReaAssist waits before timing out a cloud-provider request."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_timeout(menu_idx) end,
    "cloud_timeout")

  labels, map, selected = ScreenReader.diagnostics_menu()
  ui.diagnostics_map = map
  ScreenReader.next_line_for_large_text()
  ui.ids.diagnostics_tier = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(270),
    ScreenReader.t("settings.adv.diagnostics.label", nil,
      "Automatic diagnostics"),
    ScreenReader.caption_width_px(140),
    ScreenReader.t("settings.adv.diagnostics.tooltip", nil,
      "Basic anonymous diagnostics are enabled by default and can be turned off."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_diagnostics_tier(menu_idx) end,
    "diagnostics_tier")

  reagirl.NextLine()
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function()
      S._screen_reader_saved_script_path = nil
      S._screen_reader_add_actions_return_view = nil
      ScreenReader.close_ui()
    end,
    "close")


  return ScreenReader.open_reagirl_window("ReaAssist_Screen_Reader_Mode",
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    820, 560)
end

function ScreenReader.build_update_prompt_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local state = ScreenReader.update_prompt_state() or "available"
  local is_repair = state == "repair_available"
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.update_prompt.title.meaning", nil,
      "Accessible prompt for applying a ReaAssist update or repair."),
    false, nil, "update_prompt_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.update_prompt_body_text(),
    ScreenReader.t("a11y.sr.update_prompt.body.meaning", nil,
      "Explains why ReaAssist is asking to update or repair now."),
    false, nil, "update_prompt_body")
  reagirl.NextLine()
  ui.ids.update_status = reagirl.Label_Add(nil, nil,
    AppController.update_status_text and AppController.update_status_text()
      or ScreenReader.t("a11y.sr.update_status.idle", nil,
        "No update check is running."),
    ScreenReader.t("a11y.sr.update_status.meaning", nil,
      "Current update check, update, or repair status."),
    false, nil, "update_status")

  reagirl.NextLine()
  ui.ids.apply_update = reagirl.Button_Add(nil, nil, 10, 5,
    is_repair
      and ScreenReader.t("update.repair.now", nil, "Repair Now")
      or ScreenReader.t("update.action.update_now", nil, "Update Now"),
    ScreenReader.t("a11y.sr.update_prompt.apply.meaning", nil,
      "Applies the available ReaAssist update or file repair now."),
    function() ScreenReader.apply_update() end,
    "apply_update")

  if not is_repair then
    ui.ids.update_later = reagirl.Button_Add(nil, nil, 10, 5,
      ScreenReader.t("common.later", nil, "Later"),
      ScreenReader.t("a11y.sr.update_prompt.later.meaning", nil,
        "Postpones this update reminder."),
      function() ScreenReader.defer_update_prompt() end,
      "update_later")
    ui.ids.view_changelog = reagirl.Button_Add(nil, nil, 14, 5,
      ScreenReader.t("update.action.view_changelog", nil, "View Changelog"),
      ScreenReader.t("a11y.sr.update_prompt.changelog.meaning", nil,
        "Opens the ReaAssist changelog in your browser."),
      function()
        ScreenReader.open_external_url("https://reaassist.app/changelog/",
          "a11y.sr.changelog_opened",
          "Opening the ReaAssist changelog.")
      end,
      "view_changelog")
  end

  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    720, is_repair and 300 or 340, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(is_repair
      and ScreenReader.t("a11y.sr.update_prompt.repair_opened", nil,
        "ReaAssist files need repair. Choose Repair Now.")
      or ScreenReader.t("a11y.sr.update_prompt.update_opened", nil,
        "ReaAssist update available. Choose Update Now, Later, or View Changelog."))
  end
  return ok == 1
end

function ScreenReader.build_api_keys_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local setup = ScreenReader.api_keys_setup_active()
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.api_keys_title.meaning", nil,
      "API key setup for ReaAssist Screen Reader Mode."),
    false, nil, "api_keys_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  if setup then
    local intro_text = ScreenReader.t("settings.first_run.intro", nil,
      "Keys are obfuscated and stored locally on this machine and sent only to your chosen provider. Claude has shown the best all around results in testing. Gemini is the only provider to offer a free tier. You may also use a local or custom LLM to keep your data fully offline and private.")
    reagirl.NextLine()
    ui.ids.intro = reagirl.Label_Add(nil, nil,
      ScreenReader.wrap_text(intro_text, 88),
      intro_text,
      false, nil, "api_key_intro")
  end

  local labels, map, selected = ScreenReader.menu_from_provider_items()
  ui.provider_map = map
  reagirl.NextLine()
  ui.ids.provider = reagirl.DropDownMenu_Add(nil, nil, 250,
    ScreenReader.t("a11y.sr.provider", nil, "Provider"), 80,
    ScreenReader.t("a11y.sr.provider.meaning", nil,
      "Chooses which configured provider ReaAssist uses."),
    labels, selected,
    function(_, menu_idx)
      ScreenReader.select_provider(menu_idx)
      ScreenReader.refresh_api_key_status()
    end,
    "api_key_provider")

  reagirl.NextLine()
  ui.ids.api_key_status = reagirl.Label_Add(nil, nil,
    ScreenReader.api_key_status_text(),
    ScreenReader.t("a11y.sr.api_key_status.meaning", nil,
      "Tells whether the selected provider has a saved API key."),
    false, nil, "api_key_status")

  reagirl.NextLine()
  ui.ids.api_key_input = reagirl.Inputbox_Add(nil, nil, 430,
    ScreenReader.t("a11y.sr.api_key_input", nil, "New key"), 90,
    ScreenReader.t("a11y.sr.api_key_input.meaning", nil,
      "Paste a new API key for the selected provider. Press OK to save and test it."),
    "",
    function() ScreenReader.save_api_key() end,
    nil,
    "api_key_input")

  reagirl.NextLine()
  ui.ids.test_key = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.test_key", nil, "Test Key"),
    ScreenReader.t("a11y.sr.test_key.meaning", nil,
      "Sends a minimal provider request to test the saved API key."),
    function() ScreenReader.test_api_key() end,
    "test_key")
  ui.ids.clear_key = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.clear_key", nil, "Clear Key"),
    ScreenReader.t("a11y.sr.clear_key.meaning", nil,
      "Removes the saved API key for the selected provider."),
    function() ScreenReader.clear_api_key() end,
    "clear_key")
  ui.ids.open_console = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.open_key_page", nil, "Open Key Page"),
    ScreenReader.t("a11y.sr.open_key_page.meaning", nil,
      "Opens the selected provider's API key page in your browser."),
    function() ScreenReader.open_provider_console() end,
    "open_key_page")

  reagirl.NextLine()
  ui.ids.note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.api_key_note", nil,
      "Saved keys are stored in REAPER's persistent settings for this install."),
    ScreenReader.t("a11y.sr.api_key_note.meaning", nil,
      "Explains where API keys are stored."),
    false, nil, "api_key_note")

  reagirl.NextLine()
  if setup then
    ui.ids.continue_main = reagirl.Button_Add(nil, nil, 18, 5,
      ScreenReader.t("common.continue", nil, "Continue"),
      ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
        "Returns to the main ReaAssist screen."),
      function() ScreenReader.continue_from_api_keys() end,
      "continue_main")
  else
    ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
      ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
      ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
        "Returns to the settings screen."),
      function() ScreenReader.open_view("settings") end,
      "back_to_settings")
    ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
      ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
      ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
        "Returns to the main ReaAssist screen."),
      function() ScreenReader.open_view("main") end,
      "back_to_main")
  end
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    820, setup and 560 or 500, 0, nil, nil)
  return ok == 1
end

function ScreenReader.build_custom_providers_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.custom_providers_title.meaning", nil,
      "Accessible local and custom provider management."),
    false, nil, "custom_providers_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.summary = reagirl.Label_Add(nil, nil,
    ScreenReader.custom_providers_summary(),
    ScreenReader.t("a11y.sr.custom_providers_summary.meaning", nil,
      "Summary of saved local and custom providers."),
    false, nil, "custom_providers_summary")

  reagirl.NextLine()
  ui.ids.note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.custom_providers_note", nil,
      "Edit JSON, save it, then Load Edit File. Save provider keys from API Keys."),
    ScreenReader.t("a11y.sr.custom_providers_note.meaning", nil,
      "Explains the accessible custom providers workflow."),
    false, nil, "custom_providers_note")

  reagirl.NextLine()
  ui.ids.open_edit_file = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.custom_providers_open_file", nil,
      "Open Edit File"),
    ScreenReader.t("a11y.sr.custom_providers_open_file.meaning", nil,
      "Opens editable custom provider JSON in the system text editor."),
    function() ScreenReader.open_custom_providers_file() end,
    "custom_providers_open_file")
  ui.ids.load_edit_file = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.custom_providers_load_file", nil,
      "Load Edit File"),
    ScreenReader.t("a11y.sr.custom_providers_load_file.meaning", nil,
      "Validates and saves the custom providers JSON edit file."),
    function() ScreenReader.load_custom_providers_file() end,
    "custom_providers_load_file")
  ui.ids.copy_json = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.custom_providers_copy", nil,
      "Copy JSON"),
    ScreenReader.t("a11y.sr.custom_providers_copy.meaning", nil,
      "Copies the saved custom providers JSON to the clipboard."),
    function() ScreenReader.copy_custom_providers_json() end,
    "custom_providers_copy")
  ui.ids.copy_template = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.custom_provider_template", nil,
      "Copy Template"),
    ScreenReader.t("a11y.sr.custom_provider_template.meaning", nil,
      "Copies a starter custom provider JSON document to the clipboard."),
    function() ScreenReader.copy_custom_provider_template() end,
    "custom_provider_template")

  reagirl.NextLine()
  ui.ids.open_source = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.custom_providers_open_source", nil,
      "Open Providers.json"),
    ScreenReader.t("a11y.sr.custom_providers_open_source.meaning", nil,
      "Opens the saved Providers.json source file when it exists."),
    function() ScreenReader.open_providers_json_source() end,
    "custom_providers_open_source")
  ui.ids.api_keys = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.api_keys", nil, "API Keys"),
    ScreenReader.t("a11y.sr.custom_providers_api_keys.meaning", nil,
      "Opens API key setup. Select a loaded custom provider there to save its key."),
    function() ScreenReader.open_api_keys_settings() end,
    "custom_providers_api_keys")

  reagirl.NextLine()
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.open_view("settings") end,
    "back_to_settings")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    880, 460, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_custom_instructions_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.custom_instructions_title.meaning", nil,
      "Custom instructions settings for ReaAssist Screen Reader Mode."),
    false, nil, "custom_instructions_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.custom_instructions_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.custom_instructions_summary(),
    ScreenReader.t("a11y.sr.custom_instructions_summary.meaning", nil,
      "Shows whether custom instructions are enabled and how much text is saved."),
    false, nil, "custom_instructions_summary")

  reagirl.NextLine()
  ui.ids.custom_instructions_enabled = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("settings.custom_instructions.enable", nil,
      "Use custom instructions"),
    ScreenReader.t("a11y.sr.custom_instructions_enabled.meaning", nil,
      "Include these saved preferences with each request."),
    prefs and prefs.custom_instructions_enabled == true,
    function(_, checked)
      ScreenReader.set_custom_instructions_enabled(checked)
    end,
    "custom_instructions_enabled")

  reagirl.NextLine()
  ui.ids.open_custom_instructions = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.open_custom_instructions_file", nil,
      "Edit Instructions File"),
    ScreenReader.t("a11y.sr.open_custom_instructions_file.meaning", nil,
      "Opens the custom instructions Markdown file in the system text editor."),
    function() ScreenReader.open_custom_instructions_file() end,
    "open_custom_instructions_file")
  ui.ids.copy_custom_instructions = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_custom_instructions", nil,
      "Copy Instructions"),
    ScreenReader.t("a11y.sr.copy_custom_instructions.meaning", nil,
      "Copies the saved custom instructions text to the clipboard."),
    function() ScreenReader.copy_custom_instructions() end,
    "copy_custom_instructions")
  ui.ids.reload_custom_instructions = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.reload_custom_instructions", nil,
      "Refresh Summary"),
    ScreenReader.t("a11y.sr.reload_custom_instructions.meaning", nil,
      "Reloads the saved custom instructions file and updates this summary."),
    function() ScreenReader.reload_custom_instructions_summary() end,
    "reload_custom_instructions")
  ui.ids.copy_custom_instructions_example = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_custom_instructions_example", nil,
      "Copy Example"),
    ScreenReader.t("a11y.sr.copy_custom_instructions_example.meaning", nil,
      "Copies starter custom instructions examples to the clipboard."),
    function() ScreenReader.copy_custom_instructions_example() end,
    "copy_custom_instructions_example")

  reagirl.NextLine()
  ui.ids.note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.custom_instructions_note", nil,
      "The file uses Markdown. Save it in your text editor, then return to ReaAssist."),
    ScreenReader.t("a11y.sr.custom_instructions_note.meaning", nil,
      "Explains how custom instructions are edited."),
    false, nil, "custom_instructions_note")

  reagirl.NextLine()
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.open_view("settings") end,
    "back_to_settings")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    760, 420, 0, nil, nil)
  return ok == 1
end

function ScreenReader.build_pref_plugins_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.ensure_pref_plugins_rows()
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.pref_plugins_title.meaning", nil,
      "Accessible preferred plugin mappings for ReaAssist Screen Reader Mode."),
    false, nil, "pref_plugins_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.pref_plugins_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.pref_plugins_summary(),
    ScreenReader.t("a11y.sr.pref_plugins_summary.meaning", nil,
      "Summary of saved preferred plugin mappings."),
    false, nil, "pref_plugins_summary")

  local labels, map, selected = ScreenReader.pref_plugin_type_menu()
  ui.pref_plugin_map = map
  reagirl.NextLine()
  ui.ids.pref_plugin_type = reagirl.DropDownMenu_Add(nil, nil, 300,
    ScreenReader.t("a11y.sr.pref_plugin_type", nil, "Plugin Type"),
    80,
    ScreenReader.t("a11y.sr.pref_plugin_type.meaning", nil,
      "Chooses which preferred plugin type to edit."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_pref_plugin_type(menu_idx) end,
    "pref_plugin_type")

  reagirl.NextLine()
  ui.ids.pref_plugins_selected = reagirl.Label_Add(nil, nil,
    ScreenReader.pref_plugin_selected_summary(),
    ScreenReader.t("a11y.sr.pref_plugins_selected.meaning", nil,
      "Current plugin and aliases for the selected type."),
    false, nil, "pref_plugins_selected")

  reagirl.NextLine()
  ui.ids.pref_plugins_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.pref_plugins_note", nil,
      "Copy a plugin name from REAPER's FX Browser, then paste it for the selected type. Use the edit file for bulk changes or custom types."),
    ScreenReader.t("a11y.sr.pref_plugins_note.meaning", nil,
      "Explains the accessible preferred plugins workflow."),
    false, nil, "pref_plugins_note")

  reagirl.NextLine()
  ui.ids.paste_pref_plugin = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_paste_plugin", nil,
      "Paste Plugin"),
    ScreenReader.t("a11y.sr.pref_plugins_paste_plugin.meaning", nil,
      "Sets the selected type's plugin from clipboard text."),
    function() ScreenReader.paste_selected_pref_plugin_name() end,
    "paste_pref_plugin")
  ui.ids.paste_pref_aliases = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_paste_aliases", nil,
      "Paste Aliases"),
    ScreenReader.t("a11y.sr.pref_plugins_paste_aliases.meaning", nil,
      "Sets aliases for the selected type from clipboard text."),
    function() ScreenReader.paste_selected_pref_plugin_aliases() end,
    "paste_pref_aliases")
  ui.ids.clear_pref_plugin = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_clear_selected", nil,
      "Clear Selected"),
    ScreenReader.t("a11y.sr.pref_plugins_clear_selected.meaning", nil,
      "Clears the plugin name for the selected type."),
    function() ScreenReader.clear_selected_pref_plugin() end,
    "clear_pref_plugin")

  reagirl.NextLine()
  ui.ids.open_pref_plugins_file = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_open_file", nil,
      "Open Edit File"),
    ScreenReader.t("a11y.sr.pref_plugins_open_file.meaning", nil,
      "Opens the preferred plugins table in your system text editor."),
    function() ScreenReader.open_pref_plugins_file() end,
    "open_pref_plugins_file")
  ui.ids.load_pref_plugins_file = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_load_file", nil,
      "Load Edit File"),
    ScreenReader.t("a11y.sr.pref_plugins_load_file.meaning", nil,
      "Loads the preferred plugins table from the edit file."),
    function() ScreenReader.load_pref_plugins_file() end,
    "load_pref_plugins_file")
  ui.ids.copy_pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_copy", nil,
      "Copy Mappings"),
    ScreenReader.t("a11y.sr.pref_plugins_copy.meaning", nil,
      "Copies the preferred plugin mappings table to the clipboard."),
    function() ScreenReader.copy_pref_plugins() end,
    "copy_pref_plugins")

  reagirl.NextLine()
  ui.ids.save_pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_save", nil, "Save Mappings"),
    ScreenReader.t("a11y.sr.pref_plugins_save.meaning", nil,
      "Saves preferred plugin mappings."),
    function() ScreenReader.save_pref_plugins(false, false) end,
    "save_pref_plugins")
  ui.ids.save_scan_pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_save_scan", nil,
      "Save and Scan"),
    ScreenReader.t("a11y.sr.pref_plugins_save_scan.meaning", nil,
      "Saves mappings and scans new preferred plugins for parameter names."),
    function() ScreenReader.save_pref_plugins(true, false) end,
    "save_scan_pref_plugins")
  ui.ids.rescan_pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_rescan_all", nil,
      "Rescan All Plugins"),
    ScreenReader.t("a11y.sr.pref_plugins_rescan_all.meaning", nil,
      "Rescans all preferred plugins."),
    function() ScreenReader.save_pref_plugins(true, true) end,
    "rescan_pref_plugins")
  ui.ids.clear_all_pref_plugins = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_clear_all", nil,
      "Clear All Mappings"),
    ScreenReader.t("a11y.sr.pref_plugins_clear_all.meaning", nil,
      "Clears all preferred plugin mappings."),
    function() ScreenReader.open_pref_plugins_clear_confirm() end,
    "clear_all_pref_plugins")

  reagirl.NextLine()
  ui.ids.pref_plugins_scan_status = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.pref_plugins_scan_idle", nil,
      "No scan is running."),
    ScreenReader.t("a11y.sr.pref_plugins_scan_status.meaning", nil,
      "Status of preferred plugin parameter scans."),
    false, nil, "pref_plugins_scan_status")

  reagirl.NextLine()
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.open_view("settings") end,
    "back_to_settings")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 540, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_prompt_editor_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.prompt_editor_title.meaning", nil,
      "Accessible prompt and chat tools for ReaAssist Screen Reader Mode."),
    false, nil, "prompt_editor_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ScreenReader.add_prompt_input(ui, 620, false)

  reagirl.NextLine()
  ui.ids.prompt_editor_body = reagirl.Label_Add(nil, nil,
    ScreenReader.prompt_body_text(),
    ScreenReader.t("a11y.sr.prompt_editor_body.meaning", nil,
      "Readable prompt text that will be sent."),
    false, nil, "prompt_editor_body")

  reagirl.NextLine()
  ui.ids.prompt_editor_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.prompt_editor_note", nil,
      "Use the prompt box for quick prompts, or open the draft file in your text editor for longer prompts."),
    ScreenReader.t("a11y.sr.prompt_editor_note.meaning", nil,
      "Explains the accessible prompt editing options."),
    false, nil, "prompt_editor_note")

  reagirl.NextLine()
  ui.ids.paste_prompt = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.paste_prompt", nil, "Paste Prompt"),
    ScreenReader.t("a11y.sr.paste_prompt.meaning", nil,
      "Replaces the prompt with text from the clipboard."),
    function() ScreenReader.paste_prompt(true) end,
    "paste_prompt")
  ui.ids.append_prompt = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.append_prompt", nil, "Append Clipboard"),
    ScreenReader.t("a11y.sr.append_prompt.meaning", nil,
      "Adds clipboard text to the end of the current prompt."),
    function() ScreenReader.paste_prompt(false) end,
    "append_prompt")
  ui.ids.clear_prompt = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.clear_prompt", nil, "Clear Prompt"),
    ScreenReader.t("a11y.sr.clear_prompt.meaning", nil,
      "Clears the current prompt."),
    function() ScreenReader.clear_prompt() end,
    "clear_prompt")
  ui.ids.copy_prompt = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_prompt", nil, "Copy Prompt"),
    ScreenReader.t("a11y.sr.copy_prompt.meaning", nil,
      "Copies the current prompt to the clipboard."),
    function() ScreenReader.copy_prompt() end,
    "copy_prompt")
  ui.ids.save_prompt = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.save_prompt", nil, "Save Prompt"),
    ScreenReader.t("a11y.sr.save_prompt.meaning", nil,
      "Saves the current prompt to the ReaAssist temp folder."),
    function() ScreenReader.save_prompt() end,
    "save_prompt")

  reagirl.NextLine()
  ui.ids.open_prompt_draft = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.open_prompt_draft", nil,
      "Open Draft File"),
    ScreenReader.t("a11y.sr.open_prompt_draft.meaning", nil,
      "Opens a prompt draft text file in your system text editor."),
    function() ScreenReader.open_prompt_draft() end,
    "open_prompt_draft")
  ui.ids.load_prompt_draft = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.load_prompt_draft", nil,
      "Load Draft File"),
    ScreenReader.t("a11y.sr.load_prompt_draft.meaning", nil,
      "Loads the saved draft file as the current prompt."),
    function() ScreenReader.load_prompt_draft() end,
    "load_prompt_draft")

  reagirl.NextLine()
  ui.ids.send = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t_shortcut("common.send", "Send", "F5"),
    ScreenReader.t("a11y.sr.send.meaning", nil,
      "Sends the current request to ReaAssist."),
    function() ScreenReader.send_current_prompt() end,
    "send")

  reagirl.NextLine()
  ui.ids.copy_chat = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_chat", nil, "Copy Chat"),
    ScreenReader.t("a11y.sr.copy_chat.meaning", nil,
      "Copies the full chat transcript to the clipboard."),
    function() ScreenReader.copy_chat() end,
    "copy_chat")
  ui.ids.save_chat = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.save_chat", nil, "Save Chat"),
    ScreenReader.t("a11y.sr.save_chat.meaning", nil,
      "Saves the full chat transcript to the ReaAssist temp folder."),
    function() ScreenReader.save_chat() end,
    "save_chat")
  ui.ids.clear_chat = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.clear_chat", nil, "Clear Chat"),
    ScreenReader.t("a11y.sr.clear_chat.meaning", nil,
      "Clears the current ReaAssist conversation after confirmation."),
    function() ScreenReader.open_clear_confirm() end,
    "clear_chat")

  reagirl.NextLine()
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 640, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_example_prompts_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.example_prompts_title.meaning", nil,
      "Example prompts for ReaAssist Screen Reader Mode."),
    false, nil, "example_prompts_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.example_prompts_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.example_prompts_note", nil,
      "Choose an example to load it as the current prompt, then send from the main screen."),
    ScreenReader.t("a11y.sr.example_prompts_note.meaning", nil,
      "Explains how example prompts work."),
    false, nil, "example_prompts_note")

  reagirl.NextLine()
  ui.ids.starter_prompts = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.starter_prompts", nil,
      "Starter prompts"),
    ScreenReader.t("a11y.sr.starter_prompts.meaning", nil,
      "Suggested prompts matching the main ReaAssist welcome cards."),
    false, nil, "starter_prompts")
  for i, card_id in ipairs(ScreenReader.starter_prompt_defs()) do
    if i % 2 == 1 then reagirl.NextLine() end
    local starter_title = ScreenReader.t("home.card." .. card_id .. ".title",
      nil, card_id:gsub("_", " "))
    ui.ids["starter_" .. card_id] = reagirl.Button_Add(nil, nil, 10, 5,
      starter_title,
      ScreenReader.t("a11y.sr.starter_prompt.meaning", {
        title = starter_title,
      }, "Loads the " .. starter_title .. " starter prompt."),
      function() ScreenReader.use_starter_prompt(card_id) end,
      "starter_" .. card_id)
  end

  reagirl.NextLine()
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open(
    "ReaAssist_Screen_Reader_Examples",
    true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    640, 430, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.response_ready_window_height(opts)
  opts = opts or {}
  local lines = 1
  local function add_preview(text, width, max_lines)
    text = tostring(text or "")
    if text == "" then return end
    lines = lines + #ScreenReader.preview_lines(text, false, width, max_lines)
  end
  add_preview(opts.summary, 84, 2)
  add_preview(opts.response_notes_below, 84, 1)
  add_preview(opts.action_summary, 84, 4)
  add_preview(opts.auto_run_blocked, 84, 2)
  add_preview(opts.body_text, 84, 2)
  lines = lines + 3
  if opts.has_prose then
    lines = lines + 1
    add_preview(opts.prose, 84, opts.has_code and 2 or 6)
  end
  if opts.feedback then lines = lines + 2 end
  local height = 150 + (lines * 34)
  return math.min(600, math.max(300, height))
end

function ScreenReader.build_response_ready_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local parts = ScreenReader.response_ready_parts()
  local payload = parts.payload
  local has_code = parts.has_code
  local prose = parts.prose
  local full_has_prose = parts.full_has_prose
  local has_prose = parts.has_prose
  local typed_action = parts.typed_action
  local is_jsfx = ScreenReader.payload_is_jsfx(payload)
  local jsfx_added = ScreenReader.payload_jsfx_added(payload)
  local code_ran = parts.code_ran
  local run_info = nil
  if has_code and not typed_action and not is_jsfx and not code_ran then
    run_info = AppController.latest_code_run_info
      and AppController.latest_code_run_info() or nil
  end
  local action_summary = parts.action_summary
  local sr_summary = parts.sr_summary
  local response_notes_below = parts.response_notes_below
  local auto_run_blocked = parts.auto_run_blocked
  local body_text = parts.body_text
  local feedback_available = AppController.feedback_available
    and AppController.feedback_available()
    and AppController.feedback_target_available
    and AppController.feedback_target_available(payload)
  local function add_response_prose(id_prefix)
    if has_code then
      reagirl.NextLine()
      ui.ids[id_prefix .. "_title"] = reagirl.Label_Add(nil, nil,
        ScreenReader.t("a11y.sr.response_notes_body", nil,
          "Response notes"),
        ScreenReader.t("a11y.sr.response_notes_body.meaning", nil,
          "Non-code notes from the latest ReaAssist response."),
        false, nil, id_prefix .. "_title")
    end
    for i, line in ipairs(ScreenReader.preview_lines(prose, false, 84,
        has_code and 2 or 6,
        ScreenReader.t("a11y.sr.response_preview_shortened", nil,
          "Preview shortened. Use Read Full Response for the full text."))) do
      reagirl.NextLine()
      ui.ids[id_prefix .. "_" .. tostring(i)] =
        reagirl.Label_Add(nil, nil, line,
          ScreenReader.t("a11y.sr.response_preview_line.meaning", {
            number = tostring(i),
          }, "Response line " .. tostring(i) .. "."),
          false, nil, id_prefix .. "_" .. tostring(i))
    end
  end
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.response_ready_title.meaning", nil,
      "Latest ReaAssist response and available actions."),
    false, nil, "response_ready_title")

  if sr_summary ~= "" then
    for i, line in ipairs(ScreenReader.preview_lines(sr_summary, false,
        84, 2)) do
      reagirl.NextLine()
      ui.ids["screen_reader_summary_" .. tostring(i)] =
        reagirl.Label_Add(nil, nil, line,
          ScreenReader.t("a11y.sr.screen_reader_summary.meaning", nil,
            "Short summary of the latest response for screen-reader users."),
          false, nil, "screen_reader_summary_" .. tostring(i))
    end
  end

  if response_notes_below ~= "" then
    reagirl.NextLine()
    ui.ids.response_notes_below = reagirl.Label_Add(nil, nil,
      response_notes_below,
      ScreenReader.t("a11y.sr.response_notes_below.meaning", nil,
        "Tells the user where secondary response notes appear on the page."),
      false, nil, "response_notes_below")
  end

  if action_summary ~= "" then
    for i, line in ipairs(ScreenReader.preview_lines(action_summary, false,
        84, 4)) do
      reagirl.NextLine()
      ui.ids["typed_action_summary_" .. tostring(i)] =
        reagirl.Label_Add(nil, nil, line,
          ScreenReader.t("a11y.sr.typed_action_summary.meaning", nil,
            "Summary of the structured edit that ran."),
          false, nil, "typed_action_summary_" .. tostring(i))
    end
  end

  if auto_run_blocked ~= "" then
    for i, line in ipairs(ScreenReader.preview_lines(auto_run_blocked, false,
        84, 2)) do
      reagirl.NextLine()
      ui.ids["auto_run_blocked_" .. tostring(i)] =
        reagirl.Label_Add(nil, nil, line,
          ScreenReader.t("a11y.sr.auto_run_blocked.meaning", nil,
            "Explains why Auto-run did not run automatically."),
          false, nil, "auto_run_blocked_" .. tostring(i))
    end
  end

  if body_text ~= "" then
    reagirl.NextLine()
    ui.ids.response_ready_body = reagirl.Label_Add(nil, nil, body_text,
      ScreenReader.t("a11y.sr.response_ready_body.meaning", nil,
        "Explains the response choices."),
      false, nil, "response_ready_body")
  end

  if has_prose and not has_code then
    add_response_prose("response_note")
  end

  reagirl.NextLine()
  if has_code then
    if ScreenReader.payload_can_undo(payload) then
      ui.ids.undo_edit = reagirl.Button_Add(nil, nil, 14, 5,
        ScreenReader.undo_label(payload),
        ScreenReader.undo_meaning(payload),
        function() ScreenReader.undo_latest_generated_action() end,
        "undo_edit")
    end
    if typed_action and ScreenReader.payload_can_undo(payload) then
      ui.ids.request_lua = reagirl.Button_Add(nil, nil, 28, 5,
        ScreenReader.t("typed_actions.undo_lua", nil,
          "Undo and Request Lua"),
        ScreenReader.t("typed_actions.undo_lua.tooltip", nil,
          "Undo this structured edit, then ask for the Lua/ReaScript version. Auto-run still follows your current setting."),
        function() ScreenReader.request_lua_for_action_plan("thinking") end,
        "request_lua")
    end
    ui.ids.read_code = reagirl.Button_Add(nil, nil,
      typed_action and 30 or 22, 5,
      ScreenReader.read_code_label(payload),
      ScreenReader.read_code_meaning(payload),
      function() ScreenReader.show_code() end,
      "read_code")
    if typed_action and not ScreenReader.payload_can_undo(payload) then
      ui.ids.apply_plan = reagirl.Button_Add(nil, nil, 18, 5,
        ScreenReader.t_shortcut("a11y.sr.apply_action_plan",
          "Run Edit", "F8"),
        ScreenReader.t("a11y.sr.apply_action_plan.meaning", nil,
          "Runs the validated edit after ReaAssist checks it."),
        function() ScreenReader.apply_typed_action() end,
        "apply_plan")
      ui.ids.request_lua = reagirl.Button_Add(nil, nil, 18, 5,
        ScreenReader.t("typed_actions.request_lua", nil,
          "Request Lua"),
        ScreenReader.t("typed_actions.request_lua.tooltip", nil,
          "Ask for a normal Lua/ReaScript version you can review, run, or save. The structured edit will not run."),
        function()
          ScreenReader.request_lua_for_action_plan("thinking",
            { skip_undo = true })
        end,
        "request_lua")
    end
    if not code_ran and not typed_action and not jsfx_added
        and (is_jsfx or (run_info and run_info.can_run == true)) then
      ui.ids.run_code = reagirl.Button_Add(nil, nil,
        is_jsfx and 30 or 14, 5,
        is_jsfx
          and ScreenReader.t_shortcut("jsfx.add_selected",
            "Add JSFX to Selected Track(s)", "F8")
          or ScreenReader.t_shortcut("a11y.sr.run_code",
            "Run Code", "F8"),
        is_jsfx
          and ScreenReader.t("a11y.sr.add_jsfx.meaning", nil,
            "Saves the JSFX and adds it to all selected tracks.")
          or ScreenReader.t("a11y.sr.run_code.meaning", nil,
            "Runs the generated Lua code after ReaAssist checks it."),
        function()
          if is_jsfx then
            ScreenReader.add_latest_jsfx_to_selected_tracks("response_ready")
          else
            ScreenReader.run_code()
          end
        end,
        "run_code")
    end
  end
  if full_has_prose then
    ui.ids.read_response = reagirl.Button_Add(nil, nil, 22, 5,
      ScreenReader.t("a11y.sr.read_full_response", nil,
        "Read Full Response"),
      ScreenReader.t("a11y.sr.read_full_response.meaning", nil,
        "Opens a full response window and reads the full response."),
      function() ScreenReader.show_response() end,
      "read_response")
    ui.ids.copy_response = reagirl.Button_Add(nil, nil, 14, 5,
      ScreenReader.t("a11y.sr.copy_response", nil, "Copy Response"),
      ScreenReader.t("a11y.sr.copy_response.meaning", nil,
        "Copies the latest response to the clipboard."),
      function() ScreenReader.copy_response() end,
      "copy_response")
  end
  if feedback_available then
    reagirl.NextLine()
    ui.ids.feedback_prompt = reagirl.Label_Add(nil, nil,
      ScreenReader.t("feedback.was_helpful", nil, "Was this helpful?"),
      ScreenReader.t("a11y.sr.feedback_prompt.meaning", nil,
        "Feedback controls for the latest ReaAssist response."),
      false, nil, "feedback_prompt")
    reagirl.NextLine()
    ui.ids.feedback_up = reagirl.Button_Add(nil, nil, 12, 5,
      ScreenReader.t("feedback.helpful", nil, "Helpful"),
      ScreenReader.t("a11y.sr.feedback_helpful.meaning", nil,
        "Opens accessible feedback for this response with Helpful selected."),
      function() ScreenReader.open_feedback("up", payload) end,
      "feedback_up")
    ui.ids.feedback_down = reagirl.Button_Add(nil, nil, 14, 5,
      ScreenReader.t("feedback.not_helpful", nil, "Not helpful"),
      ScreenReader.t("a11y.sr.feedback_not_helpful.meaning", nil,
        "Opens accessible feedback for this response with Not helpful selected."),
      function() ScreenReader.open_feedback("down", payload) end,
      "feedback_down")
  end
  ui.ids.new_prompt = reagirl.Button_Add(nil, nil, 16, 5,
    ScreenReader.t_shortcut("a11y.sr.new_prompt", "New Prompt", "F2"),
    ScreenReader.t("a11y.sr.new_prompt.meaning", nil,
      "Opens a new prompt dialog. OK sends the prompt immediately."),
    function() ScreenReader.shortcut_new_prompt() end,
    "new_prompt")

  reagirl.NextLine()
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_main_for_next_request() end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  if has_prose and has_code then
    add_response_prose("response_note")
  end

  local ok = reagirl.Gui_Open(
    "ReaAssist_Screen_Reader_Response_Ready",
    false,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    760, ScreenReader.response_ready_window_height({
      summary = sr_summary,
      response_notes_below = response_notes_below,
      action_summary = action_summary,
      auto_run_blocked = auto_run_blocked,
      body_text = body_text,
      prose = prose,
      has_code = has_code,
      has_prose = has_prose,
      feedback = feedback_available,
    }), 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_feedback_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local fb = ScreenReader.feedback_state()
  local flags = ScreenReader.feedback_flags()
  local sending = fb and fb.sending == true
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.feedback_title.meaning", nil,
      "Accessible feedback for the latest ReaAssist response."),
    false, nil, "feedback_title")

  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.feedback_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.feedback_summary_text(),
    ScreenReader.t("a11y.sr.feedback_summary.meaning", nil,
      "Current feedback rating and target response."),
    false, nil, "feedback_summary")

  if fb then
    reagirl.NextLine()
    ui.ids.feedback_helpful = reagirl.Button_Add(nil, nil, 12, 5,
      ScreenReader.t("feedback.helpful", nil, "Helpful"),
      ScreenReader.t("a11y.sr.feedback_helpful_select.meaning", nil,
        "Marks this response as helpful."),
      function() ScreenReader.set_feedback_sentiment("up") end,
      "feedback_helpful")
    ui.ids.feedback_not_helpful = reagirl.Button_Add(nil, nil, 14, 5,
      ScreenReader.t("feedback.not_helpful", nil, "Not helpful"),
      ScreenReader.t("a11y.sr.feedback_not_helpful_select.meaning", nil,
        "Marks this response as not helpful."),
      function() ScreenReader.set_feedback_sentiment("down") end,
      "feedback_not_helpful")

    if flags.thumbs_down then
      reagirl.NextLine()
      ui.ids.feedback_what_wrong = reagirl.Label_Add(nil, nil,
        ScreenReader.t("feedback.modal.what_wrong", nil,
          "What went wrong?"),
        ScreenReader.t("a11y.sr.feedback_what_wrong.meaning", nil,
          "Optional reasons for a not helpful response."),
        false, nil, "feedback_what_wrong")

      reagirl.NextLine()
      ui.ids.feedback_wrong_result = reagirl.Checkbox_Add(nil, nil,
        ScreenReader.t("feedback.modal.tag.wrong_result", nil,
          "Wrong result"),
        ScreenReader.t("a11y.sr.feedback_wrong_result.meaning", nil,
          "Adds the wrong result reason to the feedback."),
        flags.wrong_result == true,
        function(_, checked)
          ScreenReader.set_feedback_flag("wrong_result", checked)
        end,
        "feedback_wrong_result")
      ui.ids.feedback_wrong_plugin = reagirl.Checkbox_Add(nil, nil,
        ScreenReader.t("feedback.modal.tag.wrong_plugin", nil,
          "Wrong plugin"),
        ScreenReader.t("a11y.sr.feedback_wrong_plugin.meaning", nil,
          "Adds the wrong plugin reason to the feedback."),
        flags.wrong_plugin == true,
        function(_, checked)
          ScreenReader.set_feedback_flag("wrong_plugin", checked)
        end,
        "feedback_wrong_plugin")

      reagirl.NextLine()
      ui.ids.feedback_didnt_follow = reagirl.Checkbox_Add(nil, nil,
        ScreenReader.t("feedback.modal.tag.didnt_follow", nil,
          "Didn't follow request"),
        ScreenReader.t("a11y.sr.feedback_didnt_follow.meaning", nil,
          "Adds the did not follow request reason to the feedback."),
        flags.didnt_follow_request == true,
        function(_, checked)
          ScreenReader.set_feedback_flag("didnt_follow_request", checked)
        end,
        "feedback_didnt_follow")
      ui.ids.feedback_too_slow = reagirl.Checkbox_Add(nil, nil,
        ScreenReader.t("feedback.modal.tag.too_slow", nil, "Too slow"),
        ScreenReader.t("a11y.sr.feedback_too_slow.meaning", nil,
          "Adds the too slow reason to the feedback."),
        flags.too_slow == true,
        function(_, checked)
          ScreenReader.set_feedback_flag("too_slow", checked)
        end,
        "feedback_too_slow")
    end

    reagirl.NextLine()
    ui.ids.feedback_comment_preview = reagirl.Label_Add(nil, nil,
      ScreenReader.feedback_comment_preview_text(),
      ScreenReader.t("a11y.sr.feedback_comment_preview.meaning", nil,
        "Preview of the optional feedback comment."),
      false, nil, "feedback_comment_preview")

    reagirl.NextLine()
    ui.ids.edit_feedback_comment = reagirl.Button_Add(nil, nil, 12, 5,
      ScreenReader.t("a11y.sr.feedback_edit_comment", nil,
        "Comment"),
      ScreenReader.t("a11y.sr.feedback_edit_comment.meaning", nil,
        "Opens a text entry popup for optional feedback details."),
      function() ScreenReader.edit_feedback_comment() end,
      "edit_feedback_comment")
    ui.ids.send_feedback = reagirl.Button_Add(nil, nil, 12, 5,
      ScreenReader.t("a11y.sr.feedback_send", nil, "Send Feedback"),
      ScreenReader.t("a11y.sr.feedback_send.meaning", nil,
        "Sends this feedback to the ReaAssist maintainer."),
      function() ScreenReader.send_feedback() end,
      "send_feedback")
  end

  reagirl.NextLine()
  ui.ids.response_ready = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.t_shortcut("common.back", "Back", "F9"),
    ScreenReader.t("a11y.sr.back_to_response_ready.meaning", nil,
      "Returns to the response screen with run, undo, and review controls."),
    function() ScreenReader.open_view("response_ready") end,
    "back_to_response_ready")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_main_for_next_request() end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Feedback", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, flags.thumbs_down and 500 or 420, 0, nil, nil)
  ScreenReader.refresh_actions()
  if ok == 1 and fb and not sending then
    ScreenReader.announce(ScreenReader.t("a11y.sr.feedback_opened", nil,
      "Feedback opened. Review the details, then send when ready."))
  end
  return ok == 1
end

function ScreenReader.build_thinking_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.thinking_title.meaning", nil,
      "Waiting screen while ReaAssist is generating a response."),
    false, nil, "thinking_title")

  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.thinking_wait", nil,
      "Thinking. Please wait."),
    ScreenReader.t("a11y.sr.thinking_wait.meaning", nil,
      "Tells the user that ReaAssist is waiting for the model response."),
    false, nil, "thinking_body")

  reagirl.NextLine()
  ui.ids.cancel_request = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.t("a11y.sr.cancel_request", nil, "Cancel Request"),
    ScreenReader.t("a11y.sr.cancel_request.meaning", nil,
      "Stops the current ReaAssist request when one is running."),
    function() ScreenReader.cancel_request() end,
    "cancel_request")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  local ok = reagirl.Gui_Open(
    "ReaAssist_Screen_Reader_Thinking",
    true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    520, 210, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_attachments_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.attachments_title.meaning", nil,
      "Accessible attachment controls for ReaAssist Screen Reader Mode."),
    false, nil, "attachments_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.attachments_preview = reagirl.Label_Add(nil, nil,
    AppController.attachment_summary_text and AppController.attachment_summary_text()
      or ScreenReader.t("a11y.sr.attachments_none", nil,
        "No attachments queued."),
    ScreenReader.t("a11y.sr.attachments_summary.meaning", nil,
      "Summary of the current attachment queue."),
    false, nil, "attachments_preview")

  reagirl.NextLine()
  ui.ids.attachments_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.attachments_note", nil,
      "Copy a file path in Explorer, then choose Add File Path. Attachments are sent with the next request only."),
    ScreenReader.t("a11y.sr.attachments_note.meaning", nil,
      "Explains how accessible attachments work."),
    false, nil, "attachments_note")

  reagirl.NextLine()
  ui.ids.add_path = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.add_attachment_path", nil,
      "Add File Path"),
    ScreenReader.t("a11y.sr.add_attachment_path.meaning", nil,
      "Adds the file path currently copied to the clipboard."),
    function() ScreenReader.add_attachment_from_clipboard_path() end,
    "add_attachment_path")
  ui.ids.add_clipboard_image = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.add_clipboard_image", nil,
      "Add Clipboard Image"),
    ScreenReader.t("a11y.sr.add_clipboard_image.meaning", nil,
      "Adds an image from the clipboard when one is available."),
    function() ScreenReader.add_clipboard_image_attachment() end,
    "add_clipboard_image")
  ui.ids.add_screenshot = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("attach.menu.screenshot", nil, "Screenshot"),
    ScreenReader.t("a11y.sr.add_screenshot.meaning", nil,
      "Takes a screenshot and attaches it to the next request."),
    function() ScreenReader.add_screenshot_attachment() end,
    "add_screenshot")

  reagirl.NextLine()
  ui.ids.remove_last = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.remove_last_attachment", nil,
      "Remove Last"),
    ScreenReader.t("a11y.sr.remove_last_attachment.meaning", nil,
      "Removes the most recently added attachment."),
    function() ScreenReader.remove_last_attachment() end,
    "remove_last_attachment")
  ui.ids.clear_attachments = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.clear_attachments", nil,
      "Clear Attachments"),
    ScreenReader.t("a11y.sr.clear_attachments.meaning", nil,
      "Removes all queued attachments."),
    function() ScreenReader.clear_attachments() end,
    "clear_attachments")

  reagirl.NextLine()
  ui.ids.send = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t_shortcut("common.send", "Send", "F5"),
    ScreenReader.t("a11y.sr.send.meaning", nil,
      "Sends the current request to ReaAssist."),
    function() ScreenReader.send_current_prompt() end,
    "send")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    820, 460, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_report_issue_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.report_issue_title.meaning", nil,
      "Accessible issue reporting for ReaAssist Screen Reader Mode."),
    false, nil, "report_issue_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.report_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.report_summary_text(),
    ScreenReader.t("a11y.sr.report_summary.meaning", nil,
      "Summarizes the report description, contact info, and diagnostic attachment."),
    false, nil, "report_summary")

  reagirl.NextLine()
  ui.ids.report_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.report_note", nil,
      "Paste a short description, or open the description file in your text editor. Copy Preview copies the exact redacted JSON that will be sent."),
    ScreenReader.t("a11y.sr.report_note.meaning", nil,
      "Explains how accessible issue reporting works."),
    false, nil, "report_note")

  reagirl.NextLine()
  ui.ids.report_comment_preview = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.report_comment_preview", {
      text = ScreenReader.clean_label(ScreenReader.report_comment(), 220),
    }, "Description: " .. (ScreenReader.report_comment() ~= ""
      and ScreenReader.clean_label(ScreenReader.report_comment(), 220)
      or ScreenReader.t("a11y.sr.report_comment_empty", nil, "empty"))),
    ScreenReader.t("a11y.sr.report_comment_preview.meaning", nil,
      "Preview of the issue description."),
    false, nil, "report_comment_preview")

  reagirl.NextLine()
  ui.ids.paste_report_comment = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_paste_description", nil,
      "Paste Description"),
    ScreenReader.t("a11y.sr.report_paste_description.meaning", nil,
      "Replaces the report description with text from the clipboard."),
    function() ScreenReader.paste_report_comment(true) end,
    "paste_report_comment")
  ui.ids.append_report_comment = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_append_description", nil,
      "Append Clipboard"),
    ScreenReader.t("a11y.sr.report_append_description.meaning", nil,
      "Adds clipboard text to the report description."),
    function() ScreenReader.paste_report_comment(false) end,
    "append_report_comment")
  ui.ids.clear_report_comment = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_clear_description", nil,
      "Clear Description"),
    ScreenReader.t("a11y.sr.report_clear_description.meaning", nil,
      "Clears the report description."),
    function() ScreenReader.clear_report_comment() end,
    "clear_report_comment")

  reagirl.NextLine()
  ui.ids.open_report_comment = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_open_description_file", nil,
      "Open Description File"),
    ScreenReader.t("a11y.sr.report_open_description_file.meaning", nil,
      "Opens the issue description file in your system text editor."),
    function() ScreenReader.open_report_comment_file() end,
    "open_report_comment")
  ui.ids.load_report_comment = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_load_description_file", nil,
      "Load Description File"),
    ScreenReader.t("a11y.sr.report_load_description_file.meaning", nil,
      "Loads the saved issue description file."),
    function() ScreenReader.load_report_comment_file() end,
    "load_report_comment")

  reagirl.NextLine()
  ui.ids.report_contact_preview = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.report_contact_preview", {
      name = ScreenReader.report_name() ~= "" and ScreenReader.report_name()
        or ScreenReader.t("a11y.sr.report_contact_no_name", nil, "no name"),
      email = ScreenReader.report_email() ~= "" and ScreenReader.report_email()
        or ScreenReader.t("a11y.sr.report_contact_no_email", nil, "no email"),
    }, "Contact: " .. (ScreenReader.report_name() ~= ""
        and ScreenReader.report_name() or "no name") .. ", "
      .. (ScreenReader.report_email() ~= "" and ScreenReader.report_email()
        or "no email")),
    ScreenReader.t("a11y.sr.report_contact_preview.meaning", nil,
      "Optional contact name and email for a reply."),
    false, nil, "report_contact_preview")

  reagirl.NextLine()
  ui.ids.paste_report_contact = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_paste_contact", nil,
      "Paste Contact"),
    ScreenReader.t("a11y.sr.report_paste_contact.meaning", nil,
      "Reads a contact name and email from the clipboard."),
    function() ScreenReader.paste_report_contact() end,
    "paste_report_contact")
  ui.ids.open_report_contact = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_open_contact_file", nil,
      "Open Contact File"),
    ScreenReader.t("a11y.sr.report_open_contact_file.meaning", nil,
      "Opens the optional contact file in your text editor."),
    function() ScreenReader.open_report_contact_file() end,
    "open_report_contact")
  ui.ids.load_report_contact = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_load_contact_file", nil,
      "Load Contact File"),
    ScreenReader.t("a11y.sr.report_load_contact_file.meaning", nil,
      "Loads optional contact details from the contact file."),
    function() ScreenReader.load_report_contact_file() end,
    "load_report_contact")
  ui.ids.clear_report_contact = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_clear_contact", nil,
      "Clear Contact"),
    ScreenReader.t("a11y.sr.report_clear_contact.meaning", nil,
      "Clears the optional contact name and email."),
    function() ScreenReader.clear_report_contact() end,
    "clear_report_contact")

  reagirl.NextLine()
  ui.ids.copy_report_preview = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_copy_preview", nil, "Copy Preview"),
    ScreenReader.t("a11y.sr.report_copy_preview.meaning", nil,
      "Copies the exact redacted report JSON to the clipboard."),
    function() ScreenReader.copy_report_preview() end,
    "copy_report_preview")
  ui.ids.save_report_preview = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_save_preview", nil,
      "Save Preview"),
    ScreenReader.t("a11y.sr.report_save_preview.meaning", nil,
      "Saves the exact redacted report JSON to the temp folder."),
    function() ScreenReader.save_report_preview() end,
    "save_report_preview")
  ui.ids.send_report = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("bug_report.send", nil, "Send Report"),
    ScreenReader.t("a11y.sr.report_send.meaning", nil,
      "Sends the issue report to the ReaAssist maintainer."),
    function() ScreenReader.send_report() end,
    "send_report")

  reagirl.NextLine()
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.settings = reagirl.Button_Add(nil, nil, 13, 5,
    ScreenReader.t_shortcut("a11y.sr.settings", "Settings", "F3"),
    ScreenReader.t("a11y.sr.settings.meaning", nil,
      "Opens accessible settings."),
    function() ScreenReader.open_view("settings") end,
    "settings")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 560, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_help_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.help_title.meaning", nil,
      "Accessible help and usage guidance for ReaAssist."),
    false, nil, "help_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.manual = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("help.nav.manual", nil, "Read Online Manual"),
    ScreenReader.t("a11y.sr.manual.meaning", nil,
      "Opens the online ReaAssist manual in your browser."),
    function() ScreenReader.open_manual() end,
    "help_manual")
  ui.ids.report = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("help.nav.feedback", nil, "Feedback & Report a Bug"),
    ScreenReader.t("a11y.sr.help_report.meaning", nil,
      "Opens the accessible report issue screen."),
    function() ScreenReader.open_view("report_issue") end,
    "help_report")
  ui.ids.copy = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_help", nil, "Copy Help"),
    ScreenReader.t("a11y.sr.copy_help.meaning", nil,
      "Copies the accessible help text to the clipboard."),
    function() ScreenReader.copy_help_text() end,
    "copy_help")
  ui.ids.credits = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("footer.credits.label", nil, "Credits"),
    ScreenReader.t("a11y.sr.credits.meaning", nil,
      "Opens accessible credits and support links."),
    function() ScreenReader.open_view("credits") end,
    "help_credits")
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local section_idx = 0
  local help_text = ScreenReader.help_text()
  for section in (help_text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n\n")
      :gmatch("(.-)\n%s*\n") do
    section = section:gsub("^%s+", ""):gsub("%s+$", "")
    if section ~= "" then
      section_idx = section_idx + 1
      reagirl.NextLine()
      ui.ids["help_body_" .. tostring(section_idx)] =
        reagirl.Label_Add(nil, nil, section,
          ScreenReader.t("a11y.sr.help_body_section.meaning", {
            number = tostring(section_idx),
          }, "Help section " .. tostring(section_idx) .. "."),
          false, nil, "help_body_" .. tostring(section_idx))
    end
  end

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    760, 560, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t("a11y.sr.help_opened", nil,
      "Help opened. Use Tab to move by section, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_credits_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.credits_title.meaning", nil,
      "Accessible credits and support links for ReaAssist."),
    false, nil, "credits_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.production = reagirl.Button_Add(nil, nil, 10, 5,
    "MichaelBriggs.audio",
    ScreenReader.t("a11y.sr.credits_production.meaning", nil,
      "Opens Michael Briggs audio production site."),
    function()
      ScreenReader.open_external_url(
        "https://michaelbriggs.audio/?mtm_campaign=reaassist",
        "a11y.sr.link_opened", "Opening link.")
    end,
    "credits_production")
  ui.ids.mastering = reagirl.Button_Add(nil, nil, 10, 5,
    "Mastering Site",
    ScreenReader.t("a11y.sr.credits_mastering.meaning", nil,
      "Opens Michael Briggs Mastering site."),
    function()
      ScreenReader.open_external_url(
        "https://michaelbriggsmastering.com/?mtm_campaign=reaassist",
        "a11y.sr.link_opened", "Opening link.")
    end,
    "credits_mastering")
  ui.ids.reaassist_site = reagirl.Button_Add(nil, nil, 10, 5,
    "ReaAssist.app",
    ScreenReader.t("a11y.sr.credits_reaassist.meaning", nil,
      "Opens the ReaAssist project site."),
    function()
      ScreenReader.open_external_url(
        "https://reaassist.app/?mtm_campaign=reaassist",
        "a11y.sr.link_opened", "Opening link.")
    end,
    "credits_reaassist")

  reagirl.NextLine()
  ui.ids.sample = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("credits.link.sample_label", nil,
      "Request a Free Mastering Sample"),
    ScreenReader.t("a11y.sr.credits_sample.meaning", nil,
      "Submit a free mastering sample request."),
    function()
      ScreenReader.open_external_url(
        "https://michaelbriggsmastering.com/free-sample/?mtm_campaign=reaassist",
        "a11y.sr.link_opened", "Opening link.")
    end,
    "credits_sample")
  ui.ids.email_direct = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.credits_email_direct", nil, "Email Michael"),
    ScreenReader.t("a11y.sr.credits_email_direct.meaning", nil,
      "Email Michael directly."),
    function()
      ScreenReader.open_external_url("mailto:michael@michaelbriggs.audio",
        "a11y.sr.email_opened", "Opening email link.")
    end,
    "credits_email_direct")
  ui.ids.email_support = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.credits_email_support", nil, "Email Support"),
    ScreenReader.t("a11y.sr.credits_email_support.meaning", nil,
      "Email the ReaAssist support address."),
    function()
      ScreenReader.open_external_url("mailto:help@reaassist.app",
        "a11y.sr.email_opened", "Opening email link.")
    end,
    "credits_email_support")

  reagirl.NextLine()
  ui.ids.donate = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("footer.donate.label", nil, "Donate"),
    ScreenReader.t("a11y.sr.donate.meaning", nil,
      "Opens the donation page for supporting ReaAssist."),
    function() ScreenReader.open_donate() end,
    "credits_donate")
  ui.ids.copy = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.copy_credits", nil, "Copy Credits"),
    ScreenReader.t("a11y.sr.copy_credits.meaning", nil,
      "Copies the credits text to the clipboard."),
    function() ScreenReader.copy_credits_text() end,
    "copy_credits")
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil, ScreenReader.credits_text(),
    ScreenReader.t("a11y.sr.credits_body.meaning", nil,
      "Credits and support information for ReaAssist."),
    false, nil, "credits_body")

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    760, 560, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t("a11y.sr.credits_opened", nil,
      "Credits opened. Use Tab for links, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_reader_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local data = ScreenReader.reader_payload(S and S._screen_reader_reader_kind)
  local is_code = data.kind == "code"
  local payload = AppController.latest_response_payload()
  if not is_code and payload and payload.has_code
      and ScreenReader.response_prose_text(payload) == "" then
    S._screen_reader_reader_kind = "code"
    data = ScreenReader.reader_payload("code")
    is_code = true
  end
  local code_ran = is_code and ScreenReader.payload_auto_ran(payload)
  local typed_action = is_code and ScreenReader.payload_is_typed_action(payload)
  local is_jsfx = is_code and ScreenReader.payload_is_jsfx(payload)
  local jsfx_added = is_code and ScreenReader.payload_jsfx_added(payload)
  local run_info = nil
  if is_code and not typed_action and not is_jsfx and not code_ran then
    run_info = AppController.latest_code_run_info
      and AppController.latest_code_run_info() or nil
  end
  local reader_button_w = typed_action and 16 or is_jsfx and 12
    or is_code and 10 or 14
  local status_text = ScreenReader.page_status_text()
  local jsfx_status = ScreenReader.payload_jsfx_status(payload)
  if jsfx_status ~= "" then
    status_text = jsfx_status
  elseif payload and ScreenReader.payload_auto_ran(payload) then
    status_text = ScreenReader.response_ready_ran_text(payload, false)
  elseif payload and payload.run_status and payload.run_status ~= "" then
    status_text = ScreenReader.run_status_sentence(payload.run_status)
  end
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.reader_title.meaning", nil,
      "Readable view of the latest ReaAssist output."),
    false, nil, "reader_title")

  if is_code then
    reagirl.NextLine()
    ui.ids.status = reagirl.Label_Add(nil, nil, status_text,
      ScreenReader.t("a11y.sr.status.meaning", nil,
        "Current page status or last action result."),
      false, nil, "status")
  end

  reagirl.NextLine()
  if is_code and ScreenReader.payload_can_undo(payload) then
    ui.ids.undo_run = reagirl.Button_Add(nil, nil, 14, 5,
      ScreenReader.undo_label(payload),
      ScreenReader.undo_meaning(payload),
      function() ScreenReader.undo_latest_generated_action("reader") end,
      "undo_run")
  end
  if typed_action and ScreenReader.payload_can_undo(payload) then
    ui.ids.request_lua = reagirl.Button_Add(nil, nil, 28, 5,
      ScreenReader.t("typed_actions.undo_lua", nil,
        "Undo and Request Lua"),
      ScreenReader.t("typed_actions.undo_lua.tooltip", nil,
        "Undo this structured edit, then ask for the Lua/ReaScript version. Auto-run still follows your current setting."),
      function() ScreenReader.request_lua_for_action_plan("thinking") end,
      "request_lua")
  end
  ui.ids.copy = reagirl.Button_Add(nil, nil, reader_button_w, 5,
    typed_action and ScreenReader.t("a11y.sr.copy_action_plan", nil,
      "Copy Edit Details")
      or is_jsfx and ScreenReader.t("a11y.sr.copy_jsfx", nil,
        "Copy JSFX")
      or is_code and ScreenReader.t("a11y.sr.copy_code", nil, "Copy Code")
      or ScreenReader.t("a11y.sr.copy_response", nil, "Copy Response"),
    typed_action and ScreenReader.t("a11y.sr.copy_action_plan.meaning", nil,
      "Copies the edit details to the clipboard.")
      or is_jsfx and ScreenReader.t("a11y.sr.copy_jsfx.meaning", nil,
        "Copies generated JSFX from the latest response.")
      or is_code and ScreenReader.t("a11y.sr.copy_code.meaning", nil,
      "Copies generated code from the latest response when code is available.")
      or ScreenReader.t("a11y.sr.copy_response.meaning", nil,
        "Copies the latest response to the clipboard."),
    function() ScreenReader.copy_reader() end,
    "copy_reader")
  if is_code then
    ui.ids.save = reagirl.Button_Add(nil, nil, reader_button_w, 5,
      typed_action and ScreenReader.t("a11y.sr.save_action_plan", nil,
        "Save Edit Details")
        or is_jsfx and ScreenReader.t("a11y.sr.save_jsfx", nil,
          "Save JSFX")
        or ScreenReader.t("a11y.sr.save_code", nil, "Save Code"),
      typed_action and ScreenReader.t("a11y.sr.save_action_plan.meaning", nil,
        "Saves the edit details to the ReaAssist temp folder.")
        or is_jsfx and ScreenReader.t("a11y.sr.save_jsfx.meaning", nil,
          "Saves generated JSFX to REAPER's Effects/ReaAssist folder.")
        or ScreenReader.t("a11y.sr.save_code.meaning", nil,
          "Saves generated Lua scripts to REAPER's Scripts folder, or JSFX code to REAPER's Effects folder."),
      function() ScreenReader.save_reader() end,
      "save_reader")
  end
  if typed_action and not ScreenReader.payload_can_undo(payload) then
    ui.ids.apply_plan = reagirl.Button_Add(nil, nil, 18, 5,
      ScreenReader.t_shortcut("a11y.sr.apply_action_plan",
        "Run Edit", "F8"),
      ScreenReader.t("a11y.sr.apply_action_plan.meaning", nil,
        "Runs the validated edit after ReaAssist checks it."),
      function() ScreenReader.apply_typed_action() end,
      "apply_plan")
  end
  if is_code and not code_ran and not typed_action and not jsfx_added
      and (is_jsfx or (run_info and run_info.can_run == true)) then
    ui.ids.run_code = reagirl.Button_Add(nil, nil,
      is_jsfx and 30 or 14, 5,
      is_jsfx
        and ScreenReader.t_shortcut("jsfx.add_selected",
          "Add JSFX to Selected Track(s)", "F8")
        or ScreenReader.t_shortcut("a11y.sr.run_code", "Run Code", "F8"),
      is_jsfx
        and ScreenReader.t("a11y.sr.add_jsfx.meaning", nil,
          "Saves the JSFX and adds it to all selected tracks.")
        or ScreenReader.t("a11y.sr.run_code.meaning", nil,
          "Runs the generated Lua code after ReaAssist checks it."),
      function()
        if is_jsfx then
          ScreenReader.add_latest_jsfx_to_selected_tracks("reader")
        else
          ScreenReader.run_code()
        end
      end,
      "run_code")
  end
  ui.ids.new_prompt = reagirl.Button_Add(nil, nil, 16, 5,
    ScreenReader.t_shortcut("a11y.sr.new_prompt", "New Prompt", "F2"),
    ScreenReader.t("a11y.sr.new_prompt.meaning", nil,
      "Opens a new prompt dialog. OK sends the prompt immediately."),
    function() ScreenReader.shortcut_new_prompt() end,
    "new_prompt")

  reagirl.NextLine()
  ui.ids.response_ready = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.t_shortcut("common.back", "Back", "F9"),
    ScreenReader.t("a11y.sr.back_to_response_ready.meaning", nil,
      "Returns to the response screen with run, undo, and review controls."),
    function() ScreenReader.open_view("response_ready") end,
    "back_to_response_ready")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_main_for_next_request() end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  local preview_width = is_code and 100 or 96
  local preview_limit = is_code and 10 or 10000
  local preview_notice
  if is_code then
    local info = ScreenReader.code_preview_info(data.text, preview_width,
      preview_limit)
    if info.shortened then
      preview_notice = ScreenReader.t("a11y.sr.code_preview_note", {
        shown = tostring(info.shown),
        total = tostring(info.total),
      }, "Code preview shortened. Showing first " .. tostring(info.shown)
        .. " of " .. tostring(info.total)
        .. " nonblank lines. Use Copy or Save for the full code.")
      reagirl.NextLine()
      ui.ids.preview_note = reagirl.Label_Add(nil, nil, preview_notice,
        ScreenReader.t("a11y.sr.code_preview_note.meaning", nil,
          "Explains how much generated code is visible in the preview."),
        false, nil, "reader_preview_note")
    end
  end
  local shortened = is_code and not preview_notice
    and ScreenReader.t("a11y.sr.reader_preview_shortened_code", nil,
      "Preview shortened. Use Copy or Save for the full text.")
    or not is_code and false
    or nil
  for i, line in ipairs(ScreenReader.preview_lines(data.text, is_code,
      preview_width, preview_limit, preview_notice and false or shortened)) do
    reagirl.NextLine()
    ui.ids["body_line_" .. tostring(i)] = reagirl.Label_Add(nil, nil,
      line,
      ScreenReader.t("a11y.sr.reader_preview_line.meaning", {
        number = tostring(i),
      }, "Preview line " .. tostring(i) .. "."),
      false, nil, "reader_body_line_" .. tostring(i))
  end


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 640, 0, nil, nil)
  if ok == 1 then
    if is_code then
      ScreenReader.announce(is_jsfx
        and ScreenReader.t("a11y.sr.jsfx_reader_opened", nil,
          "Generated JSFX view opened. Use F8 to add it to selected tracks, or F9 to go back.")
        or ScreenReader.t("a11y.sr.code_reader_opened", nil,
          "Generated code view opened. Use F8 to run code when available, or F9 to go back."))
    else
      local text = ScreenReader.clean_announcement(data.text)
      ScreenReader.announce(ScreenReader.t("a11y.sr.response_reader_opened",
        nil, "Full response opened. Reading response.") .. " " .. text)
    end
  end
  return ok == 1
end

function ScreenReader.build_run_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local confirm = S._screen_reader_run_confirm or {}
  local applying_plan = confirm.opts
    and confirm.opts.apply_typed_action == true
  local body = tostring(confirm.message or ScreenReader.t(
    "a11y.sr.run_confirm_body", nil,
    "Review the generated code before running it."))
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.run_confirm_title.meaning", nil,
      "Confirmation before running generated code."),
    false, nil, "run_confirm_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil, body,
    ScreenReader.t("a11y.sr.run_confirm_body.meaning", nil,
      "Explains why confirmation is needed before running generated code."),
    false, nil, "run_confirm_body")
  reagirl.NextLine()
  ui.ids.warning = reagirl.Label_Add(nil, nil,
    applying_plan
      and ScreenReader.t("a11y.sr.apply_confirm_review", nil,
        "Use Back to Edit Details to review first. Continue only if you trust the structured edit.")
      or ScreenReader.t("a11y.sr.run_confirm_review", nil,
        "Use Back to Code to review the code first. Continue only if you trust the generated action."),
    ScreenReader.t("a11y.sr.run_confirm_review.meaning", nil,
      "Safety reminder for generated-code execution."),
    false, nil, "run_confirm_review")

  reagirl.NextLine()
  local run_label = applying_plan and (confirm.reason == "backup_unsaved"
    and ScreenReader.t("a11y.sr.apply_without_backup", nil,
      "Run Edit Without Backup")
    or ScreenReader.t("a11y.sr.apply_action_plan", nil, "Run Edit"))
    or confirm.reason == "backup_unsaved"
    and ScreenReader.t("a11y.sr.run_without_backup", nil,
      "Run Without Backup")
    or ScreenReader.t("a11y.sr.run_anyway", nil, "Run Anyway")
  ui.ids.run_anyway = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.shortcut_label(run_label, "F8"),
    ScreenReader.t("a11y.sr.run_anyway.meaning", nil,
      "Runs the generated code after this confirmation."),
    function() ScreenReader.confirm_run_code() end,
    "run_anyway")
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    applying_plan
      and ScreenReader.back_label("a11y.sr.back_to_plan", "Back to Edit Details")
      or ScreenReader.back_label("a11y.sr.back_to_code", "Back to Code"),
    applying_plan
      and ScreenReader.t("a11y.sr.back_to_plan.meaning", nil,
        "Returns to the edit details without running the edit.")
      or ScreenReader.t("a11y.sr.back_to_code.meaning", nil,
        "Returns to the generated code view without running it."),
    function() ScreenReader.cancel_run_code() end,
    "back_to_code")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    720, 360, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(applying_plan
      and ScreenReader.t("a11y.sr.apply_confirm_opened", nil,
        "Apply confirmation opened. Press F8 to apply, or F9 to go back to the plan.")
      or ScreenReader.t("a11y.sr.run_confirm_opened", nil,
        "Run confirmation opened. Press F8 to run anyway, or F9 to go back to code."))
  end
  return ok == 1
end

function ScreenReader.build_add_actions_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local path = tostring(S and S._screen_reader_saved_script_path or "")
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.add_actions_title.meaning", nil,
      "Confirmation after saving a generated Lua script."),
    false, nil, "add_actions_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.add_actions_body", nil,
      "Generated Lua script saved. Add it to REAPER's Actions list so it can be run later?"),
    ScreenReader.t("a11y.sr.add_actions_body.meaning", nil,
      "Asks whether to register the saved Lua script in the REAPER Actions list."),
    false, nil, "add_actions_body")
  if path ~= "" then
    reagirl.NextLine()
    ui.ids.path = reagirl.Label_Add(nil, nil,
      ScreenReader.clean_label(ScreenReader.t("a11y.sr.add_actions_path", {
        path = path,
      }, "Saved file: " .. path), 220),
      ScreenReader.t("a11y.sr.add_actions_path.meaning", nil,
        "Path of the saved Lua script."),
      false, nil, "add_actions_path")
  end

  reagirl.NextLine()
  ui.ids.add = reagirl.Button_Add(nil, nil, 14, 5,
    ScreenReader.t("a11y.sr.add_actions", nil, "Add to Actions"),
    ScreenReader.t("a11y.sr.add_actions.meaning", nil,
      "Adds the saved Lua script to REAPER's Actions list."),
    function() ScreenReader.confirm_add_saved_script_to_actions() end,
    "add_actions")
  ui.ids.skip = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("common.skip", nil, "Skip"),
    ScreenReader.t("a11y.sr.skip_add_actions.meaning", nil,
      "Leaves the script saved without adding it to REAPER's Actions list."),
    function() ScreenReader.skip_add_saved_script_to_actions() end,
    "skip_add_actions")
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_code", "Back to Code"),
    ScreenReader.t("a11y.sr.back_to_saved_code.meaning", nil,
      "Returns to the generated code view without adding the saved script to Actions."),
    function() ScreenReader.skip_add_saved_script_to_actions() end,
    "back_to_code")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    700, 320, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t("a11y.sr.add_actions_opened", nil,
      "Add to Actions confirmation opened. Choose Add to Actions, Skip, or F9 to go back to code."))
  end
  return ok == 1
end

function ScreenReader.build_clear_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.clear_confirm_title.meaning", nil,
      "Confirmation before clearing the current conversation."),
    false, nil, "clear_confirm_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.clear_confirm_body", nil,
      "Clear the current conversation? This removes the visible chat and resets the running chat totals."),
    ScreenReader.t("a11y.sr.clear_confirm_body.meaning", nil,
      "Explains what clearing the current conversation does."),
    false, nil, "clear_confirm_body")

  reagirl.NextLine()
  ui.ids.clear = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.clear_chat", nil, "Clear Chat"),
    ScreenReader.t("a11y.sr.clear_chat.meaning", nil,
      "Clears the current ReaAssist conversation after confirmation."),
    function() ScreenReader.confirm_clear_chat() end,
    "clear_chat_confirm")
  ui.ids.back = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.back_label("a11y.sr.back_to_main", "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.cancel_clear_chat() end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    660, 300, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t("a11y.sr.clear_confirm_opened", nil,
      "Clear chat confirmation opened. Choose Clear Chat to confirm, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_factory_reset_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.factory_reset_title.meaning", nil,
      "Confirmation before deleting ReaAssist data."),
    false, nil, "factory_reset_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.factory_reset_body", nil,
      "Deletes ReaAssist data. This cannot be undone."),
    ScreenReader.t("a11y.sr.factory_reset_body.meaning", nil,
      "This deletes settings, API keys, custom providers, custom instructions, cached data, diagnostics, and saved window position. This cannot be undone."),
    false, nil, "factory_reset_body")

  reagirl.NextLine()
  ui.ids.reset = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("settings.adv.factory_reset.label", nil, "Factory Reset"),
    ScreenReader.t("a11y.sr.factory_reset_confirm.meaning", nil,
      "Deletes ReaAssist data after confirmation."),
    function() ScreenReader.confirm_factory_reset() end,
    "factory_reset_confirm")
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.cancel_factory_reset() end,
    "back_to_settings")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    720, 320, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t(
      "a11y.sr.factory_reset_confirm_opened", nil,
      "Factory reset confirmation opened. Choose Factory Reset only if you want to delete ReaAssist data, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_visual_switch_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.visual_switch_title.meaning", nil,
      "Confirmation before opening ReaAssist's visual interface."),
    false, nil, "visual_switch_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.visual_switch_body", nil,
      "This turns off the Screen Reader Mode default and reopens ReaAssist in the visual interface. Screen Reader Mode will remain available as its own REAPER action."),
    ScreenReader.t("a11y.sr.visual_switch_body.meaning", nil,
      "Explains that the normal ReaAssist action will open the visual interface after confirmation."),
    false, nil, "visual_switch_body")

  reagirl.NextLine()
  ui.ids.open_visual = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.open_visual_now", nil,
      "Open Visual Interface Now"),
    ScreenReader.t("a11y.sr.visual_switch_confirm.meaning", nil,
      "Turns off the Screen Reader Mode default and opens the visual ReaAssist interface."),
    function() ScreenReader.confirm_visual_switch() end,
    "open_visual_now")
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.cancel_visual_switch() end,
    "back_to_settings")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    740, 320, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t(
      "a11y.sr.visual_switch_confirm_opened", nil,
      "Visual interface confirmation opened. Choose Open Visual Interface Now, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_pref_plugins_clear_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.pref_plugins_clear_title.meaning", nil,
      "Confirmation before clearing preferred plugin mappings."),
    false, nil, "pref_plugins_clear_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("settings.pref_plugins.clear.body", nil,
      "This removes all preferred plugin mappings but keeps scanned parameter data."),
    ScreenReader.t("a11y.sr.pref_plugins_clear_body.meaning", nil,
      "Explains what clearing preferred plugins does."),
    false, nil, "pref_plugins_clear_body")

  reagirl.NextLine()
  ui.ids.clear = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.pref_plugins_clear_all", nil,
      "Clear All Mappings"),
    ScreenReader.t("a11y.sr.pref_plugins_clear_all.meaning", nil,
      "Clears all preferred plugin mappings."),
    function() ScreenReader.confirm_clear_pref_plugins() end,
    "clear_pref_plugins_confirm")
  ui.ids.back = reagirl.Button_Add(nil, nil, 30, 5,
    ScreenReader.back_label("a11y.sr.back_to_pref_plugins",
      "Back to Preferred Plugins"),
    ScreenReader.t("a11y.sr.back_to_pref_plugins.meaning", nil,
      "Returns to the preferred plugins screen."),
    function() ScreenReader.cancel_clear_pref_plugins() end,
    "back_to_pref_plugins")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    720, 300, 0, nil, nil)
  if ok == 1 then
    ScreenReader.announce(ScreenReader.t(
      "a11y.sr.pref_plugins_clear_opened", nil,
      "Clear preferred plugin mappings confirmation opened. Choose Clear All Mappings to confirm, or F9 to go back."))
  end
  return ok == 1
end

function ScreenReader.build_fx_cache_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.fx_cache_title.meaning", nil,
      "Accessible FX parameter cache controls for ReaAssist Screen Reader Mode."),
    false, nil, "fx_cache_title")
  reagirl.NextLine()
  ui.ids.status = reagirl.Label_Add(nil, nil, ScreenReader.page_status_text(),
    ScreenReader.t("a11y.sr.status.meaning", nil,
      "Current page status or last action result."),
    false, nil, "status")

  reagirl.NextLine()
  ui.ids.fx_cache_summary = reagirl.Label_Add(nil, nil,
    ScreenReader.fx_cache_summary(),
    ScreenReader.t("a11y.sr.fx_cache_summary.meaning", nil,
      "Summary of scanned plugin cache entries and built-in references."),
    false, nil, "fx_cache_summary")

  local labels, map, selected = ScreenReader.fx_cache_menu()
  ui.fx_cache_map = map
  reagirl.NextLine()
  ui.ids.fx_cache_plugin = reagirl.DropDownMenu_Add(nil, nil, 420,
    ScreenReader.t("a11y.sr.fx_cache_plugin", nil, "Cached Plugin"),
    122,
    ScreenReader.t("a11y.sr.fx_cache_plugin.meaning", nil,
      "Chooses the scanned plugin cache entry to manage."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_fx_cache_plugin(menu_idx) end,
    "fx_cache_plugin")

  reagirl.NextLine()
  ui.ids.fx_cache_selected = reagirl.Label_Add(nil, nil,
    ScreenReader.fx_cache_selected_summary(),
    ScreenReader.t("a11y.sr.fx_cache_selected.meaning", nil,
      "Parameter count and deep-scan status for the selected cached plugin."),
    false, nil, "fx_cache_selected")

  reagirl.NextLine()
  ui.ids.fx_cache_note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.fx_cache_note", nil,
      "Rescan after plugin updates. Use Deep Scan only when recommended."),
    ScreenReader.t("a11y.sr.fx_cache_note.meaning", nil,
      "Explains when to use FX parameter cache actions."),
    false, nil, "fx_cache_note")

  reagirl.NextLine()
  ui.ids.rescan_selected = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_rescan", nil, "Rescan Selected"),
    ScreenReader.t("a11y.sr.fx_cache_rescan.meaning", nil,
      "Quickly rescans the selected plugin's parameters."),
    function() ScreenReader.rescan_selected_fx_cache(false) end,
    "fx_cache_rescan")
  ui.ids.deep_selected = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_deep", nil, "Deep Scan"),
    ScreenReader.t("a11y.sr.fx_cache_deep.meaning", nil,
      "Runs a slower deep scan for plugins that need delayed parameter reads."),
    function() ScreenReader.rescan_selected_fx_cache(true) end,
    "fx_cache_deep")
  ui.ids.remove_selected = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_remove", nil, "Remove Selected"),
    ScreenReader.t("a11y.sr.fx_cache_remove.meaning", nil,
      "Removes the selected plugin from the parameter cache after confirmation."),
    function() ScreenReader.open_fx_cache_remove_confirm() end,
    "fx_cache_remove")

  reagirl.NextLine()
  ui.ids.copy_list = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_copy", nil, "Copy Cache List"),
    ScreenReader.t("a11y.sr.fx_cache_copy.meaning", nil,
      "Copies a readable list of cached plugins and built-in references."),
    function() ScreenReader.copy_fx_cache_list() end,
    "fx_cache_copy")
  ui.ids.open_file = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_open_file", nil, "Open Cache File"),
    ScreenReader.t("a11y.sr.fx_cache_open_file.meaning", nil,
      "Opens a readable cache summary in the system text editor."),
    function() ScreenReader.open_fx_cache_file() end,
    "fx_cache_open_file")
  ui.ids.rescan_all = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_rescan_all", nil,
      "Rescan All Plugins"),
    ScreenReader.t("a11y.sr.fx_cache_rescan_all.meaning", nil,
      "Starts a confirmed sequential rescan of every scanned plugin."),
    function() ScreenReader.open_fx_cache_rescan_all_confirm() end,
    "fx_cache_rescan_all")
  ui.ids.clear_all = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_clear_all", nil,
      "Clear Cache"),
    ScreenReader.t("a11y.sr.fx_cache_clear_all.meaning", nil,
      "Clears every scanned plugin cache entry after confirmation."),
    function() ScreenReader.open_fx_cache_clear_confirm() end,
    "fx_cache_clear_all")

  reagirl.NextLine()
  ui.ids.cancel_scan = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_cancel", nil, "Cancel Scan"),
    ScreenReader.t("a11y.sr.fx_cache_cancel.meaning", nil,
      "Cancels a batch rescan after the current plugin, or cancels a deep scan."),
    function() ScreenReader.cancel_fx_cache_scan() end,
    "fx_cache_cancel")
  ui.ids.fx_cache_scan_status = reagirl.Label_Add(nil, nil,
    ScreenReader.fx_cache_scan_status(),
    ScreenReader.t("a11y.sr.fx_cache_scan_status.meaning", nil,
      "Current FX parameter cache scan status."),
    false, nil, "fx_cache_scan_status")

  reagirl.NextLine()
  ui.ids.back = reagirl.Button_Add(nil, nil, 22, 5,
    ScreenReader.back_label("a11y.sr.back_to_settings", "Back to Settings"),
    ScreenReader.t("a11y.sr.back_to_settings.meaning", nil,
      "Returns to the settings screen."),
    function() ScreenReader.open_view("settings") end,
    "back_to_settings")
  ui.ids.main = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("a11y.sr.back_to_main", nil, "Back to Main"),
    ScreenReader.t("a11y.sr.back_to_main.meaning", nil,
      "Returns to the main ReaAssist screen."),
    function() ScreenReader.open_view("main") end,
    "back_to_main")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    860, 520, 0, nil, nil)
  ScreenReader.refresh_actions()
  return ok == 1
end

function ScreenReader.build_fx_cache_clear_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.fx_cache_clear_title.meaning", nil,
      "Confirmation before clearing scanned plugin parameter cache entries."),
    false, nil, "fx_cache_clear_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("settings.fx_cache.confirm_clear.body", nil,
      "Plugins will be re-scanned on next use."),
    ScreenReader.t("a11y.sr.fx_cache_clear_body.meaning", nil,
      "Explains what clearing the FX parameter cache does."),
    false, nil, "fx_cache_clear_body")

  reagirl.NextLine()
  ui.ids.clear_all = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_clear_all", nil, "Clear Cache"),
    ScreenReader.t("a11y.sr.fx_cache_clear_all.meaning", nil,
      "Clears every scanned plugin cache entry after confirmation."),
    function() ScreenReader.clear_fx_cache() end,
    "fx_cache_clear_all_confirm")
  ui.ids.cancel = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.cancel_back_label(),
    ScreenReader.t("a11y.sr.cancel.meaning", nil,
      "Cancels this action and returns to the previous screen."),
    function() ScreenReader.open_view("fx_cache") end,
    "cancel")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    680, 260, 0, nil, nil)
  return ok == 1
end

function ScreenReader.build_fx_cache_remove_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local ident = S and S._screen_reader_fx_cache_remove_ident or ""
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.fx_cache_remove_title.meaning", nil,
      "Confirmation before removing one plugin from the parameter cache."),
    false, nil, "fx_cache_remove_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.fx_cache_remove_body", {
      plugin = tostring(ident),
    }, "Remove cached parameter data for " .. tostring(ident) .. "?"),
    ScreenReader.t("a11y.sr.fx_cache_remove_body.meaning", nil,
      "Explains which cached plugin entry will be removed."),
    false, nil, "fx_cache_remove_body")

  reagirl.NextLine()
  ui.ids.remove = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_remove", nil, "Remove Selected"),
    ScreenReader.t("a11y.sr.fx_cache_remove.meaning", nil,
      "Removes the selected plugin from the parameter cache after confirmation."),
    function() ScreenReader.remove_selected_fx_cache() end,
    "fx_cache_remove_confirm")
  ui.ids.cancel = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.cancel_back_label(),
    ScreenReader.t("a11y.sr.cancel.meaning", nil,
      "Cancels this action and returns to the previous screen."),
    function()
      S._screen_reader_fx_cache_remove_ident = nil
      ScreenReader.open_view("fx_cache")
    end,
    "cancel")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    760, 280, 0, nil, nil)
  return ok == 1
end

function ScreenReader.build_fx_cache_rescan_all_confirm_ui()
  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  local scanned = ScreenReader.fx_cache_lists()
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18, ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.fx_cache_rescan_all_title.meaning", nil,
      "Confirmation before rescanning every scanned plugin cache entry."),
    false, nil, "fx_cache_rescan_all_title")
  reagirl.NextLine()
  ui.ids.body = reagirl.Label_Add(nil, nil,
    ScreenReader.t("settings.fx_cache.confirm_rescan.prompt", {
      count = tostring(#scanned),
    }, "Rescan all " .. tostring(#scanned) .. " cached plugins?"),
    ScreenReader.t("a11y.sr.fx_cache_rescan_all_body.meaning", nil,
      "Explains the batch rescan operation."),
    false, nil, "fx_cache_rescan_all_body")
  reagirl.NextLine()
  ui.ids.note = reagirl.Label_Add(nil, nil,
    ScreenReader.t("settings.fx_cache.confirm_rescan.body_cancel", nil,
      "You can cancel anytime during the batch."),
    ScreenReader.t("a11y.sr.fx_cache_rescan_all_note.meaning", nil,
      "Explains that batch rescans can be cancelled."),
    false, nil, "fx_cache_rescan_all_note")

  reagirl.NextLine()
  ui.ids.rescan_all = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.fx_cache_rescan_all", nil,
      "Rescan All Plugins"),
    ScreenReader.t("a11y.sr.fx_cache_rescan_all.meaning", nil,
      "Starts a confirmed sequential rescan of every scanned plugin."),
    function() ScreenReader.rescan_all_fx_cache() end,
    "fx_cache_rescan_all_confirm")
  ui.ids.cancel = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.cancel_back_label(),
    ScreenReader.t("a11y.sr.cancel.meaning", nil,
      "Cancels this action and returns to the previous screen."),
    function() ScreenReader.open_view("fx_cache") end,
    "cancel")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")


  local ok = reagirl.Gui_Open("ReaAssist_Screen_Reader_Mode", true,
    ScreenReader.view_title(),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    720, 300, 0, nil, nil)
  return ok == 1
end

function ScreenReader.build_ui()
  local view = S and S._screen_reader_view or "main"
  if view == "terms" then return ScreenReader.build_terms_ui() end
  if view == "settings" then return ScreenReader.build_settings_ui() end
  if view == "update_prompt" then
    return ScreenReader.build_update_prompt_ui()
  end
  if view == "api_keys" then return ScreenReader.build_api_keys_ui() end
  if view == "custom_providers" then
    return ScreenReader.build_custom_providers_ui()
  end
  if view == "custom_instructions" then
    return ScreenReader.build_custom_instructions_ui()
  end
  if view == "pref_plugins" then return ScreenReader.build_pref_plugins_ui() end
  if view == "fx_cache" then return ScreenReader.build_fx_cache_ui() end
  if view == "prompt_edit" then return ScreenReader.build_prompt_editor_ui() end
  if view == "example_prompts" then
    return ScreenReader.build_example_prompts_ui()
  end
  if view == "response_ready" then
    return ScreenReader.build_response_ready_ui()
  end
  if view == "thinking" then return ScreenReader.build_thinking_ui() end
  if view == "attachments" then return ScreenReader.build_attachments_ui() end
  if view == "report_issue" then return ScreenReader.build_report_issue_ui() end
  if view == "feedback" then return ScreenReader.build_feedback_ui() end
  if view == "help" then return ScreenReader.build_help_ui() end
  if view == "credits" then return ScreenReader.build_credits_ui() end
  if view == "reader" then return ScreenReader.build_reader_ui() end
  if view == "run_confirm" then return ScreenReader.build_run_confirm_ui() end
  if view == "add_actions_confirm" then
    return ScreenReader.build_add_actions_confirm_ui()
  end
  if view == "clear_confirm" then return ScreenReader.build_clear_confirm_ui() end
  if view == "factory_reset_confirm" then
    return ScreenReader.build_factory_reset_confirm_ui()
  end
  if view == "visual_switch_confirm" then
    return ScreenReader.build_visual_switch_confirm_ui()
  end
  if view == "pref_plugins_clear_confirm" then
    return ScreenReader.build_pref_plugins_clear_confirm_ui()
  end
  if view == "fx_cache_clear_confirm" then
    return ScreenReader.build_fx_cache_clear_confirm_ui()
  end
  if view == "fx_cache_remove_confirm" then
    return ScreenReader.build_fx_cache_remove_confirm_ui()
  end
  if view == "fx_cache_rescan_all_confirm" then
    return ScreenReader.build_fx_cache_rescan_all_confirm_ui()
  end

  S.screen_reader_ui = { ids = {} }
  local ui = S.screen_reader_ui
  ScreenReader.begin_reagirl_ui()

  ui.ids.title = reagirl.Label_Add(18, 18,
    ScreenReader.t("a11y.sr.title", nil, "ReaAssist Screen Reader Mode"),
    ScreenReader.t("a11y.sr.title.meaning", nil,
      "Title for the ReaAssist screen reader mode window."),
    false, nil, "title")

  reagirl.NextLine()
  ScreenReader.add_prompt_input(ui, 620, true)

  local attachment_count = AppController.attachment_count
    and AppController.attachment_count() or 0
  if attachment_count > 0 then
    reagirl.NextLine()
    ui.ids.attachments_summary = reagirl.Label_Add(nil, nil,
      AppController.attachment_summary_text and AppController.attachment_summary_text()
        or ScreenReader.t("a11y.sr.attachments_none", nil,
          "No attachments queued."),
      ScreenReader.t("a11y.sr.attachments_summary.meaning", nil,
        "Summary of the current attachment queue."),
      false, nil, "attachments_summary")
  end

  local labels, map, selected = ScreenReader.menu_from_provider_items()
  ui.provider_map = map
  reagirl.NextLine()
  ui.ids.provider = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(170),
    ScreenReader.t("a11y.sr.provider", nil, "Provider"),
    ScreenReader.caption_width_px(78),
    ScreenReader.t("a11y.sr.provider.meaning", nil,
      "Chooses which provider ReaAssist will use for the next request."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_provider(menu_idx) end,
    "provider")

  labels, map, selected = ScreenReader.menu_from_model_items()
  ui.model_map = map
  ScreenReader.next_line_for_large_text()
  ui.ids.model = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(215),
    ScreenReader.t("a11y.sr.model", nil, "Model"),
    ScreenReader.caption_width_px(58),
    ScreenReader.t("a11y.sr.model.meaning", nil,
      "Chooses which model ReaAssist will use for the next request."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_model(menu_idx) end,
    "model")

  labels, map, selected = ScreenReader.menu_from_thinking_items()
  ui.thinking_map = map
  ScreenReader.next_line_for_large_text()
  ui.ids.thinking = reagirl.DropDownMenu_Add(nil, nil,
    ScreenReader.control_width_px(165),
    ScreenReader.t("a11y.sr.thinking", nil, "Thinking"),
    ScreenReader.caption_width_px(82),
    ScreenReader.t("a11y.sr.thinking.meaning", nil,
      "Chooses the thinking level for the next request."),
    labels, selected,
    function(_, menu_idx) ScreenReader.select_thinking(menu_idx) end,
    "thinking")

  reagirl.NextLine()
  ui.ids.edit_prompt = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.t("a11y.sr.prompt_tools", nil, "Prompt & Chat"),
    ScreenReader.t("a11y.sr.prompt_tools.meaning", nil,
      "Opens clipboard, draft-file, and chat tools."),
    function() ScreenReader.edit_prompt() end,
    "prompt_tools")
  ui.ids.example_prompts = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.t("a11y.sr.example_prompts", nil, "Example Prompts"),
    ScreenReader.t("a11y.sr.example_prompts.meaning", nil,
      "Opens optional starter prompts on a separate screen."),
    function() ScreenReader.open_view("example_prompts") end,
    "example_prompts")
  ui.ids.attachments = reagirl.Button_Add(nil, nil, 12, 5,
    ScreenReader.t("a11y.sr.attachments", nil, "Attachments"),
    ScreenReader.t("a11y.sr.attachments.meaning", nil,
      "Opens accessible attachment controls."),
    function() ScreenReader.open_view("attachments") end,
    "attachments")

  reagirl.NextLine()
  ui.ids.auto_run = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.auto_run", nil, "Auto-run generated actions"),
    ScreenReader.t("a11y.sr.auto_run.meaning", nil,
      "When checked, validated generated actions can run automatically."),
    prefs and prefs.auto_run == true,
    function(_, checked) ScreenReader.set_auto_run(checked) end,
    "auto_run")
  ui.ids.auto_backup = reagirl.Checkbox_Add(nil, nil,
    ScreenReader.t("a11y.sr.auto_backup", nil, "Auto-backup session"),
    ScreenReader.t("a11y.sr.auto_backup.meaning", nil,
      "When checked, ReaAssist saves a project backup before Auto-run changes the session."),
    prefs and prefs.auto_backup == true,
    function(_, checked) ScreenReader.set_auto_backup(checked) end,
    "auto_backup")

  reagirl.NextLine()
  ui.ids.reader = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.reader_panel", nil,
      "Screen Reader: Use Tab and Shift Tab to move through controls. Press F1 for shortcuts."),
    ScreenReader.t("a11y.sr.reader_panel.meaning", nil,
      "Screen reader status and navigation hints."),
    false, nil, "screen_reader_panel")

  reagirl.NextLine()
  ui.ids.close_hint = reagirl.Label_Add(nil, nil,
    ScreenReader.t("a11y.sr.close_hint", nil,
      "Press F4, Control Q, Alt F4, Escape twice, or the Close button to close."),
    ScreenReader.t("a11y.sr.close_hint.meaning", nil,
      "Keyboard shortcuts for closing Screen Reader Mode."),
    false, nil, "close_hint")

  reagirl.NextLine()
  ui.ids.settings = reagirl.Button_Add(nil, nil, 13, 5,
    ScreenReader.t_shortcut("a11y.sr.settings", "Settings", "F3"),
    ScreenReader.t("a11y.sr.settings.meaning", nil,
      "Opens accessible settings."),
    function() ScreenReader.open_view("settings") end,
    "settings")
  ui.ids.help = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t_shortcut("footer.help.label", "Help", "F1"),
    ScreenReader.t("a11y.sr.help.meaning", nil,
      "Opens accessible help and usage guidance."),
    function() ScreenReader.open_help() end,
    "help")
  ui.ids.report_issue = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("a11y.sr.report_issue", nil, "Report Issue"),
    ScreenReader.t("a11y.sr.report_issue.meaning", nil,
      "Opens accessible issue reporting."),
    function() ScreenReader.open_view("report_issue") end,
    "report_issue")
  ui.ids.credits = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("footer.credits.label", nil, "Credits"),
    ScreenReader.t("a11y.sr.credits.meaning", nil,
      "Opens accessible credits and support links."),
    function() ScreenReader.open_view("credits") end,
    "credits")
  ui.ids.donate = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.t("footer.donate.label", nil, "Donate"),
    ScreenReader.t("a11y.sr.donate.meaning", nil,
      "Opens the donation page for supporting ReaAssist."),
    function() ScreenReader.open_donate() end,
    "donate")
  ui.ids.close = reagirl.Button_Add(nil, nil, 10, 5,
    ScreenReader.close_label(),
    ScreenReader.t("a11y.sr.close.meaning", nil,
      "Closes ReaAssist Screen Reader Mode."),
    function() ScreenReader.close_ui() end,
    "close")

  reagirl.NextLine()
  ui.ids.footer = reagirl.Button_Add(nil, nil, 18, 5,
    ScreenReader.t("footer.by", nil, "by") .. " Michael Briggs Mastering",
    ScreenReader.t("a11y.sr.footer.meaning", nil,
      "Opens Michael Briggs Mastering site."),
    function()
      ScreenReader.open_external_url(
        "https://michaelbriggsmastering.com/?mtm_campaign=reaassist",
        "a11y.sr.link_opened", "Opening link.")
    end,
    "footer_site")

  local ok = ScreenReader.open_reagirl_window(
    "ReaAssist_Screen_Reader_Main",
    ScreenReader.t("a11y.sr.title", nil, "ReaAssist Screen Reader Mode"),
    ScreenReader.t("a11y.sr.window.meaning", nil,
      "Accessible ReaAssist window for screen-reader users."),
    820, 380)
  ScreenReader.refresh_actions()
  return ok
end

function ScreenReader.heartbeat()
  if not (S and CFG and reaper.time_precise) then return end
  local now = reaper.time_precise()
  if not S._last_heartbeat or now - S._last_heartbeat >= 1.0 then
    S._last_heartbeat = now
    reaper.SetExtState(CFG.EXT_NS, "running",
      S.INSTANCE_ID .. "|" .. tostring(now), false)
    if RA and RA.write_temp_live_marker then RA.write_temp_live_marker(now) end
  end
end

function ScreenReader.loop()
  if not (S and S.script_open) then return ScreenReader.finish() end
  ScreenReader.heartbeat()
  if reagirl and reagirl.Gui_PreventCloseViaEscForOneCycle then
    pcall(reagirl.Gui_PreventCloseViaEscForOneCycle)
  end
  local open = true
  if reagirl and reagirl.Gui_IsOpen then open = reagirl.Gui_IsOpen() end
  if open == false then return ScreenReader.finish() end
  ScreenReader.maybe_start_auto_update_check()
  if S._screen_reader_request_active then
    local active = AppController.pump_request()
    ScreenReader.track_update_status()
    if active then
      ScreenReader.set_status(ScreenReader.t("a11y.sr.waiting", nil,
        "Waiting for response."), false)
      ScreenReader.announce_request_progress()
    else
      ScreenReader.handle_response_ready()
    end
  elseif S._screen_reader_key_test_active then
    local active = AppController.pump_background()
    ScreenReader.track_update_status()
    if active then
      ScreenReader.set_status(ScreenReader.t("a11y.sr.api_key_testing", nil,
        "Testing API key."), false)
    else
      ScreenReader.handle_key_test_ready()
    end
  elseif AppController and AppController.pump_background then
    AppController.pump_background()
    ScreenReader.track_update_status()
    ScreenReader.refresh_actions({ throttle = true })
  end
  ScreenReader.track_language_download_status()
  if reagirl and reagirl.Gui_Manage then pcall(reagirl.Gui_Manage) end
  if S._screen_reader_reset_scroll_cycles
      and S._screen_reader_reset_scroll_cycles > 0 then
    ScreenReader.reset_scroll()
    S._screen_reader_reset_scroll_cycles =
      S._screen_reader_reset_scroll_cycles - 1
  end
  if ScreenReader.handle_reagirl_shortcuts() then return end
  if ScreenReader.handle_reagirl_close_keys() then return end
  if S._screen_reader_rebuild then
    S._screen_reader_rebuild = nil
    if not ScreenReader.rebuild_ui() then return ScreenReader.finish() end
    local queued = S._screen_reader_after_rebuild_status
    if queued then
      S._screen_reader_after_rebuild_status = nil
      ScreenReader.set_status(queued.text, queued.announce)
    end
    local announcement = S._screen_reader_after_rebuild_announcement
    if announcement and announcement ~= "" then
      S._screen_reader_after_rebuild_announcement = nil
      ScreenReader.announce(announcement)
    end
  end
  local delayed = S._screen_reader_after_gui_announcement
  if delayed and delayed.text and delayed.text ~= "" then
    delayed.cycles = tonumber(delayed.cycles or 1) - 1
    if delayed.cycles <= 0 then
      S._screen_reader_after_gui_announcement = nil
      ScreenReader.announce(delayed.text)
    else
      S._screen_reader_after_gui_announcement = delayed
    end
  end
  if S.script_open and (not reagirl.Gui_IsOpen or reagirl.Gui_IsOpen()) then
    reaper.defer(ScreenReader.loop)
  else
    ScreenReader.finish()
  end
end

function ScreenReader.accept_terms_if_needed()
  return not ScreenReader.terms_required()
end

function ScreenReader.start()
  local title = ScreenReader.t("a11y.sr.title", nil,
    "ReaAssist Screen Reader Mode")
  if api_keys then api_keys.screen = nil end
  if CFG and reaper.GetExtState then
    S._screen_reader_report_name = reaper.GetExtState(CFG.EXT_NS,
      "bug_report_contact_name") or ""
    S._screen_reader_report_email = reaper.GetExtState(CFG.EXT_NS,
      "bug_report_contact_email") or ""
  end
  local ok, err = ScreenReader.load_reagirl()
  if not ok then
    err = tostring(err or "unknown error")
    if err == "missing_reagirl" or err == "sha_mismatch"
        or err == "size_mismatch" or err == "api_missing"
        or err == "sha_unavailable" or err:match("^read_failed") then
      return ScreenReader.offer_reagirl_download()
    end
    local msg = ScreenReader.t("a11y.sr.reagirl_missing", {
      error = err,
    }, "ReaAssist Screen Reader Mode could not load the accessible UI library. Error: " ..
      err)
    ScreenReader.report_startup_failure(msg, msg)
    return ScreenReader.finish()
  end
  if not ScreenReader.accept_terms_if_needed() then
    S._screen_reader_view = "terms"
    if not ScreenReader.build_ui() then
      local msg = ScreenReader.t("a11y.sr.window_failed", nil,
        "Could not open the accessible ReaAssist window.")
      ScreenReader.report_startup_failure(msg, msg)
      return ScreenReader.finish()
    end
    reaper.defer(ScreenReader.loop)
    return
  end
  if not ScreenReader.has_usable_provider() then
    if api_keys then api_keys.is_reentry = false end
    S._screen_reader_view = "api_keys"
    local setup_status = ScreenReader.t("settings.hero.subtitle.first_run",
      nil, "Add at least one API key to get started.")
    if not ScreenReader.build_ui() then
      local msg = ScreenReader.t("a11y.sr.window_failed", nil,
        "Could not open the accessible ReaAssist window.")
      ScreenReader.report_startup_failure(msg, msg)
      return ScreenReader.finish()
    end
    ScreenReader.set_status(setup_status, true)
    reaper.defer(ScreenReader.loop)
    return
  end
  ScreenReader.mark_first_launch_complete()
  if not ScreenReader.build_ui() then
    local msg = ScreenReader.t("a11y.sr.window_failed", nil,
      "Could not open the accessible ReaAssist window.")
    ScreenReader.report_startup_failure(msg, msg)
    return ScreenReader.finish()
  end
  ScreenReader.announce(ScreenReader.t("a11y.sr.opened", nil,
    "ReaAssist Screen Reader Mode opened. Press F2 for a new prompt, F1 for shortcuts, or Tab to move through controls."))
  reaper.defer(ScreenReader.loop)
end

REAASSIST_SCREEN_READER_ENTRY = function()
  ScreenReader.start()
end

if type(REAASSIST_SCREEN_READER_TEST_HOOK) == "table" then
  REAASSIST_SCREEN_READER_TEST_HOOK.reagirl_close_key_action =
    function(key, mouse_cap)
      return ScreenReader.reagirl_close_key_action(key, mouse_cap)
    end
  REAASSIST_SCREEN_READER_TEST_HOOK.build_view = function(view)
    if not (reagirl and reagirl.Gui_New) then
      local ok = ScreenReader.load_reagirl()
      if not ok then return false end
    end
    S._screen_reader_view = view or "main"
    S._screen_reader_rebuild = nil
    return ScreenReader.build_ui()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.language_menu = function()
    return ScreenReader.language_menu()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.select_language = function(menu_idx)
    return ScreenReader.select_language(menu_idx)
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.accept_terms = function()
    return ScreenReader.accept_terms()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.has_usable_provider = function()
    return ScreenReader.has_usable_provider()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.commit_language = function(idx, code)
    return ScreenReader.commit_language(idx, code)
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.translation_code = function()
    return ScreenReader.translation_code()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.t = function(key, values, fallback)
    return ScreenReader.t(key, values, fallback)
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.open_feedback = function(sentiment)
    return ScreenReader.open_feedback(sentiment)
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.set_feedback_sentiment =
    function(sentiment)
      return ScreenReader.set_feedback_sentiment(sentiment)
    end
  REAASSIST_SCREEN_READER_TEST_HOOK.rebuild_ui = function()
    return ScreenReader.rebuild_ui()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.reset_window_size = function()
    return ScreenReader.reset_window_size()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.handle_reagirl_shortcuts = function()
    return ScreenReader.handle_reagirl_shortcuts()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.heartbeat = function()
    return ScreenReader.heartbeat()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.cancel_request = function()
    return ScreenReader.cancel_request()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.shortcut_run_code = function()
    return ScreenReader.shortcut_run_code()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.apply_typed_action = function(opts)
    return ScreenReader.apply_typed_action(opts)
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.confirm_factory_reset = function()
    return ScreenReader.confirm_factory_reset()
  end
  REAASSIST_SCREEN_READER_TEST_HOOK.close = function()
    return ScreenReader.close_ui()
  end
end

AppController = AppController or {}

function AppController.t(key, values, fallback)
  return RA.t(key, values, fallback)
end

function AppController.trim_text(text)
  return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

function AppController.active_provider()
  return PROVIDERS and PROVIDERS.active and PROVIDERS.active() or nil
end

function AppController.active_model()
  if not MODELS then return nil end
  return MODELS[prefs.model_idx] or MODELS[1]
end

function AppController.active_thinking_level()
  local p = AppController.active_provider()
  if not (p and p.thinking_levels and prefs.thinking_idx) then return nil end
  return p.thinking_levels[prefs.thinking_idx]
end

function AppController.active_provider_is_usable()
  local p = AppController.active_provider()
  if not p then return false end
  if p.is_custom then return true end
  return S.api_key ~= nil and tostring(S.api_key) ~= ""
end

function AppController.active_provider_key_status()
  local p = AppController.active_provider()
  if not p then
    return {
      provider = nil,
      configured = false,
      label = AppController.t("a11y.controller.provider.unknown", nil,
        "unknown provider"),
      console_url = nil,
      console_label = nil,
    }
  end
  local configured = Store and Store.provider_has_usable_credentials
    and Store.provider_has_usable_credentials(p)
  if not configured then
    configured = p.is_custom
      or (S.api_key_map and S.api_key_map[p.id]
        and tostring(S.api_key_map[p.id]) ~= "")
  end
  return {
    provider = p,
    configured = configured,
    label = p.label or p.id or AppController.t(
      "a11y.controller.provider.unknown", nil, "unknown provider"),
    console_url = p.console_url,
    console_label = p.console_label,
  }
end

function AppController.save_active_provider_key(key)
  local p = AppController.active_provider()
  if not p then
    return false, AppController.t("a11y.sr.api_key_no_provider", nil,
      "No provider is selected.")
  end
  key = AppController.trim_text(key)
  if key == "" then
    return false, AppController.t("a11y.sr.api_key_empty", nil,
      "Enter an API key first.")
  end
  if key:match("%s") then
    return false, AppController.t("a11y.sr.api_key_has_spaces", nil,
      "API keys cannot contain spaces or line breaks.")
  end
  if #key < (p.key_min_len or 1) then
    return false, AppController.t("a11y.sr.api_key_too_short", {
      provider = p.label or p.id or "",
    }, "That " .. tostring(p.label or "provider") .. " key looks too short.")
  end
  if Key and Key.matches_excluded_prefix and Key.matches_excluded_prefix(key, p) then
    return false, AppController.t("a11y.sr.api_key_wrong_provider", {
      provider = p.label or p.id or "",
    }, "That key looks like it belongs to a different provider.")
  end
  if Key and Key.matches_known_prefix and not p.key_prefix_warning_only
      and not Key.matches_known_prefix(key, p) then
    return false, AppController.t("a11y.sr.api_key_unknown_prefix", {
      provider = p.label or p.id or "",
    }, "That key does not match the expected " .. tostring(p.label or "provider") .. " key format.")
  end
  S.api_key_map[p.id] = key
  S.api_key = key
  if Key and Key.save and p.key_extstate then Key.save(key, p.key_extstate) end
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.clear_active_provider_key()
  local p = AppController.active_provider()
  if not p then return false end
  if p.key_extstate and Key and Key.clear then Key.clear(p.key_extstate) end
  if S.api_key_map then S.api_key_map[p.id] = nil end
  S.api_key = nil
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.test_active_provider_key()
  local p = AppController.active_provider()
  if not p then
    return false, AppController.t("a11y.sr.api_key_no_provider", nil,
      "No provider is selected.")
  end
  if not AppController.active_provider_is_usable() then
    return false, AppController.t("a11y.sr.api_key_missing_for_test", nil,
      "Save an API key before testing it.")
  end
  if AppController.request_is_active() then
    return false, AppController.t("a11y.sr.request_already_running", nil,
      "A request is already running.")
  end
  Net.fire_key_test(p)
  return true
end

function AppController.has_any_usable_provider()
  if Store and Store.has_usable_provider then return Store.has_usable_provider() end
  if not PROVIDERS then return false end
  for _, p in ipairs(PROVIDERS) do
    if p and (p.is_custom
        or (S.api_key_map and S.api_key_map[p.id]
          and tostring(S.api_key_map[p.id]) ~= "")) then
      return true
    end
  end
  return false
end

function AppController.provider_items(opts)
  opts = opts or {}
  local out = {}
  if not PROVIDERS then return out end
  for i, p in ipairs(PROVIDERS) do
    local configured = Store and Store.provider_has_usable_credentials
      and Store.provider_has_usable_credentials(p)
    if not configured then
      configured = p.is_custom
        or (S.api_key_map and S.api_key_map[p.id]
          and tostring(S.api_key_map[p.id]) ~= "")
    end
    if configured or opts.include_unconfigured then
      local label = p.label or p.id or ("Provider " .. tostring(i))
      if p.id == "google" and S.gemini_paid_tier == false then
        label = label .. " (Free)"
      end
      out[#out + 1] = {
        idx = i,
        id = p.id,
        label = label,
        selected = prefs.provider_idx == i,
        configured = configured,
        custom = p.is_custom == true,
      }
    end
  end
  return out
end

function AppController.model_items(opts)
  opts = opts or {}
  local out = {}
  local p = AppController.active_provider()
  if not (p and p.models) then return out end
  for raw_idx, m in ipairs(p.models) do
    local model_idx = nil
    if p.is_custom then
      model_idx = raw_idx
    else
      for i, fm in ipairs(MODELS or {}) do
        if fm.id == m.id then model_idx = i; break end
      end
    end
    local paid_locked = (m.paid_only and p.id == "google"
      and S.gemini_paid_tier ~= true) or false
    if model_idx or opts.include_unavailable then
      out[#out + 1] = {
        idx = model_idx,
        raw_idx = raw_idx,
        id = m.id,
        label = m.label or m.id or ("Model " .. tostring(raw_idx)),
        selected = model_idx ~= nil and prefs.model_idx == model_idx,
        available = model_idx ~= nil and not paid_locked,
        paid_locked = paid_locked,
        notes = m.notes,
      }
    end
  end
  return out
end

function AppController.thinking_items()
  local out = {}
  local p = AppController.active_provider()
  local m = AppController.active_model()
  if not (p and p.thinking_levels) then return out end
  for i, level in ipairs(p.thinking_levels) do
    if not level.flash_only or (m and m.is_flash) then
      out[#out + 1] = {
        idx = i,
        label = level.label or tostring(level.value or i),
        selected = prefs.thinking_idx == i,
        value = level.value,
      }
    end
  end
  return out
end

function AppController.provider_model_status_text()
  local p = AppController.active_provider()
  local m = AppController.active_model()
  local tl = AppController.active_thinking_level()
  local provider = p and p.label or AppController.t(
    "a11y.controller.provider.unknown", nil, "unknown provider")
  local model = m and (m.label or m.id) or AppController.t(
    "a11y.controller.model.unknown", nil, "unknown model")
  if tl and tl.label then
    return AppController.t("a11y.controller.using_provider_model_thinking", {
      provider = provider,
      model = model,
      thinking = tl.label,
    }, "Using " .. provider .. ", " .. model .. ", thinking " .. tl.label .. ".")
  end
  return AppController.t("a11y.controller.using_provider_model", {
    provider = provider,
    model = model,
  }, "Using " .. provider .. ", " .. model .. ".")
end

function AppController._refresh_attachment_costs(model)
  if not model then return end
  for _, att in ipairs(S.attachments or {}) do
    att.cost = (att.tokens or 0) * (model.price_in or 0) / 1000000
  end
end

function AppController.select_provider_idx(idx)
  idx = tonumber(idx)
  if not (idx and PROVIDERS and PROVIDERS[idx]) then
    return false, "invalid_provider"
  end
  if prefs.provider_idx == idx then return true end
  local old_p = AppController.active_provider()
  if old_p and Store and Store.remember_model_idx then
    Store.remember_model_idx(old_p, MODELS, prefs.model_idx)
  end
  if old_p and old_p.thinking_levels and prefs.thinking_idx > 0 then
    PROVIDERS.save_thinking_idx(old_p, MODELS[prefs.model_idx] or MODELS[1],
      prefs.thinking_idx)
  end
  if old_p and old_p.id == "google" and Net then Net.gemini_cache_invalidate() end
  prefs.provider_idx = idx
  MODELS.refresh()
  local active = AppController.active_provider()
  S.api_key = active and S.api_key_map[active.id] or nil
  S.api_ref_message = nil
  if active and active.id == "google" and Net then Net.gemini_cache_invalidate() end
  AppController._refresh_attachment_costs(AppController.active_model())
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.select_model_idx(idx)
  idx = tonumber(idx)
  if not (idx and MODELS and MODELS[idx]) then return false, "invalid_model" end
  if prefs.model_idx == idx then return true end
  local p = AppController.active_provider()
  if p and p.thinking_levels and prefs.thinking_idx > 0 then
    PROVIDERS.save_thinking_idx(p, MODELS[prefs.model_idx] or MODELS[1],
      prefs.thinking_idx)
  end
  prefs.model_idx = idx
  if p and p.thinking_levels then
    prefs.thinking_idx = PROVIDERS.load_thinking_idx(p, MODELS[prefs.model_idx])
  end
  if p and p.id == "google" and Net then Net.gemini_cache_invalidate() end
  S.api_ref_message = nil
  AppController._refresh_attachment_costs(AppController.active_model())
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.select_thinking_idx(idx)
  idx = tonumber(idx)
  local p = AppController.active_provider()
  if not (idx and p and p.thinking_levels and p.thinking_levels[idx]) then
    return false, "invalid_thinking"
  end
  prefs.thinking_idx = idx
  PROVIDERS.save_thinking_idx(p, AppController.active_model(), idx)
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.set_auto_run(enabled)
  prefs.auto_run = enabled == true
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.set_auto_backup(enabled)
  prefs.auto_backup = enabled == true
  if Store and Store.save_config then Store.save_config() end
  return true
end

function AppController.attachment_count()
  return #(S.attachments or {})
end

function AppController.attachments_ready()
  return not (Attach and Attach.all_encoded) or Attach.all_encoded()
end

function AppController.attachment_items()
  local out = {}
  for i, att in ipairs(S.attachments or {}) do
    out[#out + 1] = {
      idx = i,
      name = att.name or ("Attachment " .. tostring(i)),
      kind = att.kind or "file",
      tokens = att.tokens,
      cost = att.cost,
      path = att.path,
      encoded = att.b64 ~= nil or att.kind == "text",
    }
  end
  return out
end

function AppController.attachment_summary_text()
  local items = AppController.attachment_items()
  if #items == 0 then
    return AppController.t("a11y.sr.attachments_none", nil,
      "No attachments queued.")
  end
  local names = {}
  for i, item in ipairs(items) do
    if i > 4 then
      names[#names + 1] = AppController.t("a11y.sr.attachments_more", {
        count = tostring(#items - 4),
      }, "plus " .. tostring(#items - 4) .. " more")
      break
    end
    local label = tostring(item.name or "")
    if item.kind and item.kind ~= "" then
      label = label .. " (" .. tostring(item.kind) .. ")"
    end
    names[#names + 1] = label
  end
  return AppController.t("a11y.sr.attachments_summary", {
    count = tostring(#items),
    names = table.concat(names, ", "),
  }, tostring(#items) .. " attachment(s): " .. table.concat(names, ", "))
end

function AppController.add_attachment_path(path)
  path = AppController.trim_text(path)
  if path == "" then
    return false, AppController.t("a11y.sr.attachment_path_empty", nil,
      "Copy a file path to the clipboard first.")
  end
  path = path:gsub("^%s*file:///", ""):gsub("^%s*file://", "")
  path = path:gsub('^"(.*)"$', "%1")
  local ok = Attach and Attach.file and Attach.file(path)
  return ok == true, ok and nil or (S.attach_error
    or AppController.t("a11y.sr.attachment_add_failed", nil,
      "Could not add attachment."))
end

function AppController.add_clipboard_image_attachment()
  local ok = Attach and Attach.clipboard and Attach.clipboard()
  return ok == true, ok and nil or (S.attach_error
    or AppController.t("a11y.sr.attachment_clipboard_failed", nil,
      "Could not add a clipboard image."))
end

function AppController.add_screenshot_attachment()
  local ok = Attach and Attach.screenshot and Attach.screenshot()
  return ok == true, ok and nil or (S.attach_error
    or AppController.t("a11y.sr.attachment_screenshot_failed", nil,
      "Could not take a screenshot."))
end

function AppController.remove_attachment(idx)
  idx = tonumber(idx)
  if not (idx and S.attachments and S.attachments[idx]) then return false end
  table.remove(S.attachments, idx)
  return true
end

function AppController.clear_attachments()
  S.attachments = {}
  return true
end

function AppController.send_prompt(prompt)
  prompt = AppController.trim_text(prompt)
  if prompt == "" and AppController.attachment_count() > 0 then
    prompt = AppController.t("prompt.default_attachment", nil,
      "Please analyze the attached file(s).")
  end
  if prompt == "" then return false, "empty_prompt" end
  if not AppController.attachments_ready() then
    return false, "attachments_not_ready"
  end
  if not AppController.active_provider_is_usable() then
    return false, "provider_not_configured"
  end
  local ok, err = pcall(Net.send_to_api, prompt)
  if not ok then
    Log.add_error("Accessible request failed: " .. tostring(err))
    return false, tostring(err)
  end
  return true
end

function AppController.cancel_request()
  if not (Net and Net.cancel_active_request) then return false, "not_active" end
  return Net.cancel_active_request("screen_reader_cancelled")
end

function AppController.request_is_active()
  return S.status == "waiting" or S.curl_pid ~= nil or S.retry_scheduled == true
end

function AppController.conversation_has_content()
  return (S.display_messages and #S.display_messages > 0)
    or (S.history and #S.history > 0)
    or S.pending_code ~= nil
end

function AppController.clear_conversation()
  if AppController.request_is_active() then
    AppController.cancel_request()
  end
  if Net and Net.clear_conversation then
    Net.clear_conversation()
    return true
  end
  return false
end

function AppController.pump_background()
  if RA and RA.pump_screen_reader_background then
    return RA.pump_screen_reader_background()
  end
  if AppController.request_is_active then
    return AppController.request_is_active()
  end
  return false
end

function AppController.update_status_text()
  local state = update and update.state or "idle"
  if state == "checking" or state == "verifying" then
    return AppController.t("a11y.sr.update_status.checking", nil,
      "Checking for updates.")
  end
  if state == "available" then
    return AppController.t("a11y.sr.update_status.available", {
      version = tostring(update.remote_version or "?"),
    }, "Update available: v" .. tostring(update.remote_version or "?") .. ".")
  end
  if state == "repair_available" then
    local count = #(update.repair_missing or {})
      + #(update.repair_mismatched or {})
    return AppController.t("a11y.sr.update_status.repair_available", {
      count = tostring(count),
    }, "Repair available: " .. tostring(count) .. " file(s) need repair.")
  end
  if state == "downloading" or state == "rename_retry" then
    local idx = update.download_idx or 0
    local total = #(update.download_queue or {})
    return AppController.t("a11y.sr.update_status.applying", {
      done = tostring(idx),
      total = tostring(total),
    }, "Applying update or repair: " .. tostring(idx)
      .. " of " .. tostring(total) .. ".")
  end
  if state == "done" then
    if update.action_was_repair then
      local count = #(update.applied_files or {})
      return AppController.t("a11y.sr.update_status.repaired", {
        count = tostring(count),
      }, "Repair complete. " .. tostring(count) .. " file(s) restored.")
    end
    return AppController.t("a11y.sr.update_status.updated", {
      version = tostring(update.remote_version or "?"),
    }, "Updated to v" .. tostring(update.remote_version or "?") .. ".")
  end
  if state == "failed" or (update and update.last_error) then
    return AppController.t("a11y.sr.update_status.failed", {
      step = tostring(update and update.last_step or "unknown"),
      error = tostring(update and update.last_error or "unknown error"),
    }, "Update failed at " .. tostring(update and update.last_step or "unknown")
      .. ": " .. tostring(update and update.last_error or "unknown error"))
  end
  if update and update._last_ok_at then
    return AppController.t("a11y.sr.update_status.up_to_date", {
      version = tostring(CFG.VERSION),
    }, "ReaAssist is up to date at v" .. tostring(CFG.VERSION) .. ".")
  end
  return AppController.t("a11y.sr.update_status.idle", nil,
    "No update check is running.")
end

function AppController.update_is_busy()
  return Updater and Updater.is_busy and Updater.is_busy() or false
end

function AppController.update_can_apply()
  return update and (update.state == "available"
    or update.state == "repair_available") or false
end

function AppController.reset_window_size()
  if S then S._reset_window_size = true end
  if Store and Store.clear_window_geometry then
    Store.clear_window_geometry()
  end
  return true
end

function AppController.delete_extstate_section(ns)
  if not ns or ns == "" then return 0 end
  local ini_path = reaper.GetResourcePath() .. "/reaper-extstate.ini"
  local f = io.open(ini_path, "r")
  if not f then return 0 end
  local keys = {}
  local in_section = false
  local line_no = 0
  for line in f:lines() do
    line_no = line_no + 1
    if line_no == 1 then line = line:gsub("^\xEF\xBB\xBF", "") end
    line = line:match("^%s*(.-)%s*$") or ""
    if line ~= "" and not line:match("^[;#]") then
      local sec = line:match("^%[(.-)%]$")
      if sec then
        in_section = (sec == ns)
      elseif in_section then
        local key = line:match("^([^=]+)")
        if key then
          key = key:match("^%s*(.-)%s*$") or ""
          key = key:gsub("\r$", "")
          if key ~= "" then keys[#keys + 1] = key end
        end
      end
    end
  end
  f:close()
  for _, k in ipairs(keys) do
    reaper.DeleteExtState(ns, k, true)
  end
  return #keys
end

function AppController.delete_extstate_key_all(ns, key)
  if not ns or ns == "" or not key or key == "" then return end
  reaper.DeleteExtState(ns, key, false)
  reaper.DeleteExtState(ns, key, true)
end

function AppController.clear_theme_backup_extstate()
  local ns = "ReaAssist"
  local manifest = reaper.GetExtState(ns, "ThemeBackup__KEYS")
  if manifest ~= "" then
    for key in manifest:gmatch("[^,]+") do
      key = key:match("^%s*(.-)%s*$") or ""
      if key ~= "" then
        AppController.delete_extstate_key_all(ns, "ThemeBackup_" .. key)
      end
    end
  end
  AppController.delete_extstate_key_all(ns, "ThemeBackup__KEYS")
  AppController.delete_extstate_section(ns)
end

function AppController.ensure_factory_reset_temp_dir(factory_reset_data_dir_cleared)
  if not (factory_reset_data_dir_cleared
      and RA.TEMP_DIR
      and RA.TEMP_DIR ~= ""
      and type(reaper.RecursiveCreateDirectory) == "function") then
    return
  end
  local temp_dir = tostring(RA.TEMP_DIR):gsub("[/\\]+$", "")
  if temp_dir ~= "" then pcall(reaper.RecursiveCreateDirectory, temp_dir, 0) end
end

function AppController.factory_reset_execute(opts)
  if RA and RA.factory_reset_execute then
    return RA.factory_reset_execute(opts)
  end
  if Render and Render._factory_reset_execute then
    return Render._factory_reset_execute(opts)
  end
  return false, AppController.t("a11y.sr.factory_reset_unavailable", nil,
    "Factory reset is not available in this build.")
end
function AppController.factory_reset(opts)
  opts = opts or {}
  if AppController.factory_reset_execute then
    local ok, err = AppController.factory_reset_execute(opts)
    if ok == false then return false, err end
    if S and opts.keep_open ~= true then S.script_open = false end
    return true
  end
  if Render and Render._factory_reset_execute then
    Render._factory_reset_execute(opts)
    if S and opts.keep_open ~= true then S.script_open = false end
    return true
  end
  return false, AppController.t("a11y.sr.factory_reset_unavailable", nil,
    "Factory reset is not available in this build.")
end

function AppController.start_update_check()
  if not (Updater and Updater.manual_check) then
    return false, AppController.t("a11y.sr.update_unavailable", nil,
      "Update checking is not available in this build.")
  end
  local ok = Updater.manual_check()
  if not ok then
    return false, AppController.update_status_text()
  end
  return true
end

function AppController.apply_update()
  if not AppController.update_can_apply() then
    return false, AppController.t("a11y.sr.update_nothing_to_apply", nil,
      "No update or repair is ready to apply.")
  end
  Updater.download_start()
  return true
end

function AppController.pump_request()
  return AppController.pump_background()
end

function AppController.last_assistant_message()
  for i = #S.display_messages, 1, -1 do
    local msg = S.display_messages[i]
    if msg and msg.role == "assistant" then return msg, i end
  end
  return nil, nil
end

function AppController.request_message_for_response(message_idx)
  message_idx = tonumber(message_idx) or 0
  for i = message_idx - 1, 1, -1 do
    local msg = S.display_messages[i]
    if msg and msg.role == "user" then return msg, i end
  end
  return nil, nil
end

function AppController.message_has_typed_actions(msg)
  return TypedActionController.message_has_typed_actions(msg)
end
function AppController.generated_code_text(msg)
  return TypedActionController.generated_code_text(msg)
end
function AppController.generated_code_type(msg)
  return TypedActionController.generated_code_type(msg)
end
function AppController.code_type_label(code_type)
  if code_type == "lua" then return "Lua" end
  if code_type == "jsfx" then return "JSFX" end
  if code_type == "typed_actions" then return "edit details" end
  return "generated code"
end

function AppController.typed_action_summary(msg)
  if not AppController.message_has_typed_actions(msg) then return "" end
  local plan_text = AppController.generated_code_text(msg)
  local summary = Code and Code.typed_actions_display_text
    and Code.typed_actions_display_text(plan_text,
      msg.typed_actions.action_results) or nil
  return tostring(summary or "")
end

function AppController.first_summary_sentence(text)
  text = AppController.trim_text(tostring(text or ""))
  if text == "" then return "" end
  text = text:gsub("[\r\n]+", " ")
  local first = text:match("^(.-%.)%s") or text:match("^(.-[%.%!%?])$")
    or text
  if #first > 180 then first = first:sub(1, 177) .. "..." end
  return AppController.trim_text(first)
end

function AppController.model_screen_reader_summary(msg)
  local content = tostring(msg and msg.content or "")
  local summary = AppController.extract_screen_reader_summary_tag(content)
  if not summary or summary == "" then return "" end
  summary = AppController.trim_text(summary:gsub("%s+", " "))
  if #summary > 180 then summary = summary:sub(1, 177) .. "..." end
  return summary
end

function AppController.extract_screen_reader_summary_tag(content)
  content = tostring(content or "")
  return content:match("<screen_reader_summary>%s*(.-)%s*</screen_reader_summary>")
    or content:match("<screen_er_summary>%s*(.-)%s*</screen_er_summary>")
    or ""
end

function AppController.strip_screen_reader_summary_tags(content)
  content = tostring(content or "")
  content = content:gsub("<screen_reader_summary>%s*.-%s*</screen_reader_summary>",
    "")
  content = content:gsub("<screen_er_summary>%s*.-%s*</screen_er_summary>",
    "")
  return AppController.trim_text(content)
end

function AppController.screen_reader_summary(msg)
  if AppController.message_has_typed_actions(msg) then
    return AppController.first_summary_sentence(
      AppController.typed_action_summary(msg))
  end
  return AppController.model_screen_reader_summary(msg)
end

function AppController.typed_action_has_results(msg)
  return TypedActionController.typed_action_has_results(msg)
end
function AppController.message_undo_sent(msg)
  return TypedActionController.message_undo_sent(msg)
end
function AppController.message_can_undo_generated_action(msg)
  return TypedActionController.message_can_undo_generated_action(msg)
end
function AppController.response_text(msg)
  local parts = {}
  local content = msg and tostring(msg.content or "") or ""
  local code = AppController.generated_code_text(msg)
  if code ~= "" then
    local start_pos, end_pos = content:find(code, 1, true)
    if start_pos then
      local before = content:sub(1, start_pos - 1)
      local after = content:sub(end_pos + 1)
      before = before:gsub("```[%w_%-]*%s*$", "")
      after = after:gsub("^%s*```", "")
      content = AppController.trim_text(before .. "\n\n" .. after)
    end
  end
  content = AppController.strip_screen_reader_summary_tags(content)
  if content ~= "" then parts[#parts + 1] = content end
  if code ~= "" then
    parts[#parts + 1] = "Generated code is available separately."
  end
  if msg and msg.run_status and msg.run_status ~= "" then
    parts[#parts + 1] = "Run status: " .. tostring(msg.run_status)
  end
  if msg and msg.tok_in then
    local cost = msg.cost and string.format("$%.4f", msg.cost) or "unknown"
    parts[#parts + 1] = string.format("Tokens: %s in, %s out. Cost: %s.",
      tostring(msg.tok_in or "?"), tostring(msg.tok_out or "?"), cost)
  end
  if #parts == 0 then
    return AppController.t("a11y.sr.no_response", nil,
      "ReaAssist finished, but no readable response was found. "
      .. "Check the ReaAssist debug log or try the visual interface.")
  end
  return table.concat(parts, "\n\n")
end

function AppController.latest_response_payload()
  local msg, idx = AppController.last_assistant_message()
  local request_msg, request_idx = AppController.request_message_for_response(idx)
  if not msg then
    return {
      message = nil,
      message_idx = nil,
      request_message = nil,
      request_message_idx = nil,
      text = "",
      code = "",
      code_type = nil,
      code_label = "generated code",
      has_code = false,
      run_status = nil,
      auto_ran = false,
      typed_action = false,
      typed_action_has_results = false,
      typed_action_summary = "",
      screen_reader_summary = "",
      undo_sent = false,
      can_undo = false,
      auto_run_block_reason = nil,
      validation_status = nil,
      validation_block_kind = nil,
      local_answer = false,
      provider_id = nil,
      model_label = nil,
      ctx_label = nil,
      thinking_label = nil,
    }
  end
  local code = AppController.generated_code_text(msg)
  local code_type = AppController.generated_code_type(msg)
  local typed_action = AppController.message_has_typed_actions(msg)
  return {
    message = msg,
    message_idx = idx,
    request_message = request_msg,
    request_message_idx = request_idx,
    text = AppController.response_text(msg),
    code = code,
    code_type = code_type,
    code_label = AppController.code_type_label(code_type),
    has_code = code ~= "",
    run_status = msg and msg.run_status or nil,
    auto_ran = msg and msg.auto_ran == true,
    typed_action = typed_action,
    typed_action_has_results = typed_action
      and AppController.typed_action_has_results(msg) or false,
    typed_action_summary = typed_action
      and AppController.typed_action_summary(msg) or "",
    screen_reader_summary = AppController.screen_reader_summary(msg),
    undo_sent = AppController.message_undo_sent(msg),
    can_undo = AppController.message_can_undo_generated_action(msg),
    auto_run_block_reason = msg and msg.auto_run_block_reason or nil,
    validation_status = msg and msg.validation_status or nil,
    validation_block_kind = msg and msg.validation_block_kind or nil,
    local_answer = msg and msg.local_answer == true,
    provider_id = (request_msg and request_msg.provider_id)
      or (msg and msg.provider_id) or nil,
    model_label = (request_msg and request_msg.model_label)
      or (msg and msg.model_label) or nil,
    ctx_label = request_msg and request_msg.ctx_label or nil,
    thinking_label = request_msg and request_msg.thinking_label or nil,
    tok_in = request_msg and request_msg.tok_in or nil,
    tok_out = request_msg and request_msg.tok_out or nil,
    tok_cache_read = request_msg and request_msg.tok_cache_read or nil,
    tok_cache_create = request_msg and request_msg.tok_cache_create or nil,
    cost = request_msg and request_msg.cost or nil,
    free_tier = request_msg and request_msg.free_tier == true or false,
    response_time = request_msg and request_msg.response_time or nil,
    fx_cache_label = request_msg and request_msg.fx_cache_label or nil,
    api_calls = request_msg and request_msg.api_calls or nil,
  }
end

function AppController.latest_code_run_info()
  local payload = AppController.latest_response_payload()
  local msg = payload and payload.message or nil
  local code = payload and payload.code or ""
  if not msg or code == "" then
    return {
      can_run = false,
      reason = "no_code",
      message = AppController.t("a11y.sr.no_code_to_run", nil,
        "There is no runnable generated code."),
    }
  end
  local code_type = payload and payload.code_type
  if code_type ~= "lua" then
    return {
      can_run = false,
      reason = "not_lua",
      message = AppController.t("a11y.sr.run_code_lua_only", nil,
        "Only Lua code can be run directly from Screen Reader Mode."),
    }
  end
  if ScreenReader and ScreenReader.payload_blocks_manual_lua_run
      and ScreenReader.payload_blocks_manual_lua_run(payload) then
    return {
      can_run = false,
      reason = "validation_blocked",
      message = ScreenReader.manual_lua_run_block_text(payload),
    }
  end
  local artifact = Code and Code.classify_lua_artifact
    and Code.classify_lua_artifact(code, { context_text = msg.content }) or nil
  if artifact and (not artifact.runnable or artifact.manual_run_only) then
    return {
      can_run = false,
      reason = artifact.manual_run_only and "manual_context" or "blocked",
      message = Code and Code.lua_artifact_block_message
        and Code.lua_artifact_block_message(artifact)
        or AppController.t("a11y.sr.run_code_blocked", nil,
          "This generated code cannot be run directly."),
    }
  end
  return {
    can_run = true,
    reason = nil,
    message = "",
    payload = payload,
    message_obj = msg,
    message_idx = payload.message_idx,
    code = code,
  }
end

function AppController.run_latest_code(opts)
  opts = opts or {}
  local info = AppController.latest_code_run_info()
  if not info.can_run then return false, info.reason, info.message end
  if Code and Code.scan_risky and not opts.confirm_risky then
    local risk = Code.scan_risky(info.code)
    if risk then
      return false, "risky_confirmation_required",
        AppController.t("a11y.sr.run_code_risky", nil,
          "This generated code needs confirmation before it runs.")
    end
  end
  if prefs and prefs.auto_backup and not opts.skip_backup
      and Code and Code.safety_backup then
    local _, berr = Code.safety_backup()
    if berr == "unsaved" then
      return false, "backup_unsaved",
        AppController.t("a11y.sr.run_code_backup_unsaved", nil,
          "Auto-backup is on, but the project has not been saved.")
    elseif berr and berr ~= "unchanged" then
      return false, "backup_failed",
        AppController.t("a11y.sr.run_code_backup_failed", {
          error = tostring(berr),
        }, "Safety backup failed: " .. tostring(berr))
    end
  end
  S.status = "running"
  local ok = Code and Code.run and Code.run(info.code)
  if Code and Code.apply_run_result_to_message then
    Code.apply_run_result_to_message(info.message_obj, ok, "lua",
      info.code, false)
  end
  if info.message_idx == #S.display_messages then S.pending_code = nil end
  S.status = ok and "idle" or "error"
  return ok == true, ok and nil or "run_failed",
    ok and AppController.t("a11y.sr.run_code_ok", nil,
      "Generated code ran.")
      or AppController.t("a11y.sr.run_code_failed", nil,
        "Generated code failed. Check the response and debug log.")
end

function AppController.apply_latest_typed_action(opts)
  opts = opts or {}
  local payload = AppController.latest_response_payload()
  local msg = payload and payload.message or nil
  if not AppController.message_has_typed_actions(msg) then
    return false, "no_plan", AppController.t(
      "a11y.sr.apply_action_plan_unavailable", nil,
      "There is no validated edit to run.")
  end
  if AppController.message_can_undo_generated_action(msg) then
    return false, "already_applied", AppController.t(
      "a11y.sr.apply_action_plan_already_applied", nil,
      "This structured edit has already been run.")
  end
  if prefs and prefs.auto_backup and not opts.skip_backup
      and Code and Code.safety_backup then
    local _, berr = Code.safety_backup()
    if berr == "unsaved" then
      return false, "backup_unsaved", AppController.t(
        "a11y.sr.apply_action_plan_backup_unsaved", nil,
        "Auto-backup is on, but the project has not been saved.")
    elseif berr and berr ~= "unchanged" then
      return false, "backup_failed", AppController.t(
        "a11y.sr.apply_action_plan_backup_failed",
        { error = tostring(berr) },
        "Safety backup failed: " .. tostring(berr))
    end
  end

  local plan_text = AppController.generated_code_text(msg)
  if plan_text == "" then
    return false, "no_plan", AppController.t(
      "a11y.sr.apply_action_plan_unavailable", nil,
      "There is no validated edit to run.")
  end

  local user_text = AppController.user_prompt_before_message(
    payload and payload.message_idx or nil) or ""
  local profile = Code and Code.typed_actions_model_profile
    and Code.typed_actions_model_profile(msg.provider_id, msg.model_id) or nil

  local function apply_result(done_ok, exec_result)
    local completed_result = exec_result
      and (exec_result.result or exec_result) or nil
    msg.auto_run_block_reason = nil
    msg.typed_actions = msg.typed_actions or { present = true }
    msg.typed_actions.deferred_pending = nil
    msg.typed_actions.executed = done_ok == true
    if completed_result and completed_result.action_results then
      msg.typed_actions.action_results = completed_result.action_results
    end
    if done_ok then
      msg.auto_ran = false
      msg.run_status = "ran_ok"
      msg.validation_status = "passed"
      msg.validation_block_kind = nil
      msg.typed_actions.error = nil
      msg.content = AppController.t("a11y.sr.apply_action_plan_done", nil,
        "Structured edit ran.")
      if type(Code.typed_actions_display_text) == "function" then
        msg.typed_action_summary = Code.typed_actions_display_text(plan_text,
          msg.typed_actions.action_results)
      end
      if type(Code.build_run_result) == "function" then
        msg.run_result = Code.build_run_result("typed_actions", plan_text,
          "ran_ok", "passed", {
            auto_ran = false,
            validation_block_kind = nil,
          })
      end
    else
      local err = exec_result and exec_result.code or "execution_failed"
      msg.auto_ran = false
      msg.run_status = "errored"
      msg.validation_status = "failed"
      msg.validation_block_kind = err
      msg.typed_actions.error = err
      msg.content = Code.typed_actions_user_failure_message(exec_result)
      if type(Code.build_run_result) == "function" then
        msg.run_result = Code.build_run_result("typed_actions", plan_text,
          "errored", "failed", {
            auto_ran = false,
            validation_block_kind = err,
            error_kind = "runtime_error",
            runtime_error = tostring(msg.content or err),
            error_debug = {
              failure_kind = "runtime_error",
              source = "typed_action_executor",
              typed_action_error = tostring(err),
            },
          })
      end
    end
  end

  local exec_ok, exec_result = Code.execute_typed_actions_from_text(plan_text, {
    allow_raw_json = true,
    user_text = user_text,
    profile = profile,
    on_done = function(done_ok, done_result)
      apply_result(done_ok == true, done_result)
      S.scroll_to_bottom = true
    end,
  })
  local exec_pending = exec_ok and exec_result
    and exec_result.deferred == true
    and exec_result.completed ~= true
  if exec_pending then
    msg.run_status = "pending"
    msg.validation_status = "pending"
    msg.typed_actions = msg.typed_actions or { present = true }
    msg.typed_actions.deferred = true
    msg.typed_actions.deferred_pending = true
    msg.content = AppController.t("a11y.sr.apply_action_plan_pending", nil,
      "Structured edit is running.")
    return true, nil, msg.content
  end

  apply_result(exec_ok == true, exec_result)
  if exec_ok then
    return true, nil, AppController.t("a11y.sr.apply_action_plan_done", nil,
      "Structured edit ran.")
  end
  return false, "execution_failed",
    Code.typed_actions_user_failure_message(exec_result)
end

function AppController.undo_latest_typed_action()
  local payload = AppController.latest_response_payload()
  local msg = payload and payload.message or nil
  if not AppController.message_has_typed_actions(msg) then
    return false, AppController.t("a11y.sr.undo_edit_unavailable", nil,
      "There is no structured edit to undo.")
  end
  if not AppController.message_can_undo_generated_action(msg) then
    return false, AppController.t("a11y.sr.undo_edit_unavailable", nil,
      "There is no structured edit to undo.")
  end
  reaper.Main_OnCommand(40029, 0)
  msg.screen_reader_undo_clicked = true
  msg.typed_action_undo_clicked = true
  msg.auto_ran = false
  return true, AppController.t("a11y.sr.undo_edit_done", nil,
    "Undo sent.")
end

function AppController.user_prompt_before_message(message_idx)
  return TypedActionController.user_prompt_before_message(message_idx)
end
function AppController.typed_action_lua_request_prompt(original_request)
  return TypedActionController.typed_action_lua_request_prompt(original_request)
end
function AppController.request_lua_for_typed_action_message(msg, message_idx, opts)
  return TypedActionController.request_lua_for_typed_action_message(
    msg, message_idx, opts)
end
function AppController.request_lua_for_latest_typed_action(opts)
  local payload = AppController.latest_response_payload()
  return TypedActionController.request_lua_for_typed_action_message(
    payload and payload.message or nil,
    payload and payload.message_idx or nil,
    opts)
end
function AppController.feedback_available()
  return Diag and Diag.uploader_enabled == true
    and type(Diag.begin_draft) == "function"
    and type(Diag.preview_payload_text) == "function"
    and type(Diag.send_draft) == "function"
end

function AppController.feedback_target_available(payload)
  payload = payload or AppController.latest_response_payload()
  if not (payload and payload.message and payload.message_idx) then
    return false
  end
  local msg = payload.message
  local has_text = msg.content and msg.content ~= ""
  local has_code = AppController.generated_code_text(msg) ~= ""
  return has_text or has_code
end

function AppController.feedback_flags(sentiment)
  sentiment = tostring(sentiment or "")
  return {
    thumbs_up            = sentiment == "up",
    thumbs_down          = sentiment == "down",
    wrong_result         = false,
    wrong_plugin         = false,
    didnt_follow_request = false,
    too_slow             = false,
  }
end

function AppController.begin_feedback_for_latest(sentiment, payload)
  if not AppController.feedback_available() then
    return false, AppController.t("a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build.")
  end
  payload = payload or AppController.latest_response_payload()
  if not AppController.feedback_target_available(payload) then
    return false, AppController.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about.")
  end
  local ok, draft = pcall(Diag.begin_draft, payload.message_idx)
  if not ok or type(draft) ~= "table" then
    return false, tostring(draft or AppController.t(
      "a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build."))
  end
  return true, {
    draft = draft,
    flags = AppController.feedback_flags(sentiment),
    target_idx = payload.message_idx,
  }
end

function AppController.feedback_preview_text(draft, comment, flags)
  if not AppController.feedback_available() then
    return nil, AppController.t("a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build.")
  end
  if type(draft) ~= "table" then
    return nil, AppController.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about.")
  end
  local ok, text = pcall(Diag.preview_payload_text, draft,
    tostring(comment or ""), flags or {})
  if not ok then return nil, tostring(text or "") end
  return text
end

function AppController.send_feedback(draft, comment, flags, on_done)
  if not AppController.feedback_available() then
    return false, AppController.t("a11y.sr.feedback_unavailable", nil,
      "Feedback is not available in this build.")
  end
  if type(draft) ~= "table" then
    return false, AppController.t("a11y.sr.feedback_no_response", nil,
      "There is no response to send feedback about.")
  end
  Diag.send_draft(draft, tostring(comment or ""), flags or {}, on_done)
  return true
end

function AppController.undo_latest_generated_action()
  local payload = AppController.latest_response_payload()
  local msg = payload and payload.message or nil
  if not AppController.message_can_undo_generated_action(msg) then
    return false, AppController.t("a11y.sr.undo_run_unavailable", nil,
      "There is no completed action to undo.")
  end
  reaper.Main_OnCommand(40029, 0)
  msg.screen_reader_undo_clicked = true
  if AppController.message_has_typed_actions(msg) then
    msg.typed_action_undo_clicked = true
  end
  msg.auto_ran = false
  return true, AppController.t("a11y.sr.undo_run_done", nil,
    "Undo sent.")
end

function AppController.conversation_items()
  local out = {}
  for i, msg in ipairs(S.display_messages or {}) do
    out[#out + 1] = {
      idx = i,
      role = msg.role,
      content = tostring(msg.content or ""),
      has_code = AppController.generated_code_text(msg) ~= "",
      run_status = msg.run_status,
      provider_id = msg.provider_id,
      model_label = msg.model_label,
      local_answer = msg.local_answer == true,
    }
  end
  return out
end

function AppController.chat_transcript_text()
  local parts = {}
  parts[#parts + 1] = CFG._PRODUCT .. " v" .. CFG.VERSION .. " - Chat Log"
  parts[#parts + 1] = string.rep("-", 50)
  parts[#parts + 1] = ""
  for _, msg in ipairs(S.display_messages or {}) do
    if msg.role == "user" then
      parts[#parts + 1] = "[USER]"
      parts[#parts + 1] = msg.content or ""
      if msg.attach_names and #msg.attach_names > 0 then
        for _, aname in ipairs(msg.attach_names) do
          parts[#parts + 1] = "  [Attachment: " .. tostring(aname) .. "]"
        end
      end
      if msg.model_label then
        parts[#parts + 1] = "  Model: "
          .. tostring(msg.model_label):gsub(" %b()", "")
      end
      if msg.thinking_label then
        parts[#parts + 1] = "  Thinking: " .. tostring(msg.thinking_label)
      end
      if msg.ctx_label then
        parts[#parts + 1] = "  Context: " .. tostring(msg.ctx_label)
      end
      if msg.tok_in then
        parts[#parts + 1] = string.format("  Tokens: %d in / %d out",
          msg.tok_in, msg.tok_out or 0)
        local cr = msg.tok_cache_read or 0
        local cc = msg.tok_cache_create or 0
        if cr > 0 or cc > 0 then
          parts[#parts + 1] = string.format("  Cache: %d read, %d created",
            cr, cc)
        end
        if msg.cost and MODELS and MODELS.format_cost then
          if msg.free_tier then
            parts[#parts + 1] =
              "  Estimated cost: Free Tier (would have been ~"
              .. MODELS.format_cost(msg.cost) .. ")"
          else
            parts[#parts + 1] = "  Estimated cost: "
              .. MODELS.format_cost(msg.cost)
          end
        end
      end
      if msg.response_time then
        parts[#parts + 1] = string.format("  Response time: %.1fs",
          msg.response_time)
      end
      if msg.fx_cache_label then
        parts[#parts + 1] = "  FX Cache: " .. tostring(msg.fx_cache_label)
      end
    else
      parts[#parts + 1] = "[ASSISTANT]"
      parts[#parts + 1] = msg.content or ""
      if msg.code_block then
        parts[#parts + 1] = "```" .. (msg.code_type or "lua")
        parts[#parts + 1] = msg.code_block
        parts[#parts + 1] = "```"
      end
    end
    parts[#parts + 1] = ""
  end
  if (S.session_tok_in or 0) > 0 and MODELS and MODELS.format_cost then
    parts[#parts + 1] = string.rep("-", 50)
    parts[#parts + 1] = string.format(
      "Session: %d in / %d out  |  Est. cost: %s",
      S.session_tok_in or 0, S.session_tok_out or 0,
      MODELS.format_cost(S.session_cost or 0))
  end
  return table.concat(parts, "\n")
end

function AppController.copy_text(text)
  text = tostring(text or "")
  if reaper.CF_SetClipboard then
    local ok = pcall(reaper.CF_SetClipboard, text)
    if ok then return true end
  end
  if ImGui and ImGui.ImGui_SetClipboardText and RA.ctx then
    local ok = pcall(ImGui.ImGui_SetClipboardText, RA.ctx, text)
    if ok then return true end
  end
  return false
end

function AppController.write_transcript(text, filename)
  filename = filename or "ScreenReader_Last_Response.txt"
  local path = RA.TEMP_DIR .. filename
  if Code.safe_write(path, tostring(text or "")) then return path end
  return nil
end

function AppController.write_code(code, code_type)
  code = tostring(code or "")
  if code == "" then return nil end
  if S then S._screen_reader_last_code_save_status = nil end
  if S and S.screen_reader_mode and code_type == "lua"
      and Code.auto_save_lua then
    local path, action_name, filename = Code.auto_save_lua(code)
    if not path then return nil end
    local add_ok, add_msg = AppController.add_script_to_actions(path)
    S._screen_reader_last_code_save_status = {
      path = path,
      action_name = action_name or filename or path,
      filename = filename or action_name or path,
      add_ok = add_ok == true,
      add_msg = add_msg,
    }
    return path
  elseif code_type == "lua" and Code.save_file then
    return Code.save_file(code, Code.derive_filename(code))
  elseif code_type == "jsfx" and Code.save_file_jsfx then
    return Code.save_file_jsfx(code, Code.derive_filename_jsfx(code))
  elseif code_type == "typed_actions" then
    return AppController.write_transcript(code, "ScreenReader_Last_Action_Plan.txt")
  end
  return AppController.write_transcript(code, "ScreenReader_Last_Code.txt")
end

function AppController.add_script_to_actions(path)
  path = tostring(path or "")
  if path == "" then
    return false, AppController.t("a11y.sr.add_actions_failed", nil,
      "Could not add the script to the REAPER Actions list.")
  end
  if not reaper.AddRemoveReaScript then
    return false, AppController.t("a11y.sr.add_actions_unavailable", nil,
      "REAPER's add-to-Actions function is not available.")
  end
  local ok, cmd = pcall(reaper.AddRemoveReaScript, true, 0, path, true)
  if not ok or cmd == 0 then
    return false, AppController.t("a11y.sr.add_actions_failed", nil,
      "Could not add the script to the REAPER Actions list.")
  end
  return true, AppController.t("a11y.sr.add_actions_done", nil,
    "Script added to the REAPER Actions list.")
end

function AppController.close_instance()
  S.script_open = false
  local section_id = S and S.section_id or nil
  local cmd_id = S and S.cmd_id or nil
  if section_id and cmd_id and section_id ~= -1 and cmd_id ~= -1 then
    reaper.SetToggleCommandState(section_id, cmd_id, 0)
    reaper.RefreshToolbar2(section_id, cmd_id)
  end
  local current = reaper.GetExtState(CFG.EXT_NS, "running")
  if current:match("^([^|]+)") == S.INSTANCE_ID then
    reaper.DeleteExtState(CFG.EXT_NS, "running", false)
  end
  reaper.DeleteExtState(CFG.EXT_NS, "request_close", false)
end

REAASSIST_SCREEN_READER_MODE = true

if not main_path then
  message_box(
    "Could not start ReaAssist Screen Reader Mode.\n\n" ..
    "ReaAssist.lua could not be found. This action should be installed beside " ..
    "ReaAssist.lua, or under Scripts" .. sep .. "mbriggs-reaper" .. sep ..
    "ReaAssist.\n\n" ..
    "Detected action path:\n" .. tostring(script_path or ""),
    0)
  return
end

local ok, err = pcall(dofile, main_path)
if not ok then
  message_box(
    "Could not start ReaAssist Screen Reader Mode.\n\n" .. tostring(err),
    0)
end
