-- @description ReaClock - Custom Studio Clock for REAPER
-- @version 1.0.0
-- @author Michael Briggs
-- @provides
--   [nomain] Resources/ChivoMono-Regular.ttf
--   [nomain] Resources/Roboto-Regular.ttf
--   [nomain] Resources/Roboto-Bold.ttf
--   [nomain] Resources/lucide.ttf
--   [nomain] Resources/CHANGELOG.md
--   [nomain] README.md
--   [nomain] Resources/LICENSE.txt
--   [nomain] Resources/ReaClock_Meter.jsfx
-- @about
--   A scalable landscape studio clock and session display for REAPER.
--
--   Features:
--     - Project, current-region, or time-selection position
--     - Time, frame, sample, or arbitrary-meter bars/beats formats
--     - Current region plus upcoming region/marker awareness
--     - Zero to twenty card rows with one to six cards per row
--     - Per-card Auto or one-to-six-unit widths within each row
--     - Optional per-card auto-scroll for long region, marker, and custom text
--     - Built-in and user-created Clock Faces with instant switching
--     - Signed remaining time, transport, tempo, meter, and progress
--     - Adaptive Visual Click and live Action Buttons with persistent toggle state
--     - Loudness, peak, RMS, level, history, waveform, spectrum, spectrogram,
--       vectorscope, and phase-correlation cards
--     - Independent card pop-outs and per-visualization fullscreen viewing
--     - Optional perimeter click, docking, and full-monitor Presentation mode
--     - Persistent signed calibration offset in milliseconds or samples
--     - JSON-backed font, color, layout, and geometry customization
--     - Automatic proportional fitting or optional independent width and height
--
--   Requires ReaImGui 0.10 or newer.

local R = reaper

-- -----------------------------------------------------------------------------
-- Dependency and singleton setup
-- -----------------------------------------------------------------------------

local TITLE = "ReaClock"
local EXT = "ReaClock_v1"
local GRID_LINES_COMMAND = 40145 -- Options: Toggle grid lines
local METRONOME_COMMAND = 40364 -- Options: Toggle metronome
local Runtime = {
  reaimgui_version = "Unknown",
  scroll_traverse_seconds = 12,
  scroll_pause_seconds = 2.75,
  tooltip = {
    request = nil,
    key = nil,
    title = nil,
    detail = nil,
    hover_started = 0,
    fade_started = nil,
    fade_from = 0,
    alpha = 0,
    delay = 0.42,
    fade_in = 0.10,
    fade_out = 0.08,
    wrap_width = 274,
  },
}
local Metering

do
  local required = {
    { "ImGui_CreateContext", R.ImGui_CreateContext },
    { "ImGui_CreateFontFromFile", R.ImGui_CreateFontFromFile },
    { "ImGui_PushFont", R.ImGui_PushFont },
    { "ImGui_CreateFunctionFromEEL", R.ImGui_CreateFunctionFromEEL },
    { "ImGui_Function_SetValue", R.ImGui_Function_SetValue },
    { "ImGui_SetNextWindowSizeConstraints", R.ImGui_SetNextWindowSizeConstraints },
    { "ImGui_GetItemRectMin", R.ImGui_GetItemRectMin },
    { "ImGui_GetItemRectMax", R.ImGui_GetItemRectMax },
    { "ImGui_BeginTooltip", R.ImGui_BeginTooltip },
    { "ImGui_EndTooltip", R.ImGui_EndTooltip },
    { "ImGui_IsWindowFocused", R.ImGui_IsWindowFocused },
    { "ImGui_CreateImage", R.ImGui_CreateImage },
    { "ImGui_Image_GetSize", R.ImGui_Image_GetSize },
    { "ImGui_DrawList_AddImageRounded", R.ImGui_DrawList_AddImageRounded },
    { "ImGui_ValidatePtr", R.ImGui_ValidatePtr },
    { "ImGui_Attach", R.ImGui_Attach },
    { "ImGui_Detach", R.ImGui_Detach },
    { "ImGui_IsMouseDoubleClicked", R.ImGui_IsMouseDoubleClicked },
    { "ImGui_IsMouseClicked", R.ImGui_IsMouseClicked },
    { "ImGui_IsMouseDown", R.ImGui_IsMouseDown },
    { "ImGui_GetMousePos", R.ImGui_GetMousePos },
    { "ImGui_GetMouseDragDelta", R.ImGui_GetMouseDragDelta },
    { "ImGui_MouseButton_Left", R.ImGui_MouseButton_Left },
    { "ImGui_MouseButton_Right", R.ImGui_MouseButton_Right },
    { "ImGui_IsAnyItemHovered", R.ImGui_IsAnyItemHovered },
    { "ImGui_IsWindowHovered", R.ImGui_IsWindowHovered },
  }
  local missing, version_ok, detected_version = {}, false, "Unknown"
  for _, api in ipairs(required) do
    if type(api[2]) ~= "function" then missing[#missing + 1] = api[1] end
  end
  if type(R.ImGui_GetVersion) == "function" then
    local result = table.pack(pcall(R.ImGui_GetVersion))
    local text = tostring(result[4] or "")
    local major, minor = text:match("^(%d+)%.(%d+)")
    Runtime.reaimgui_version = text ~= "" and text or "Unknown"
    detected_version = Runtime.reaimgui_version
    version_ok = result[1] and major ~= nil
      and (tonumber(major) > 0 or tonumber(minor) >= 10)
  end
  if not version_ok or #missing > 0 then
    local reason
    if type(R.ImGui_GetVersion) ~= "function" then
      reason = "ReaImGui was not found in this REAPER installation."
    elseif detected_version ~= "Unknown" and not version_ok then
      reason = "ReaImGui " .. detected_version .. " is installed, but ReaClock needs version 0.10 or newer."
    elseif #missing > 0 then
      reason = "This ReaImGui installation is missing functions ReaClock needs:\n"
        .. table.concat(missing, ", ")
    else
      reason = "ReaClock could not verify the installed ReaImGui version."
    end
    R.ShowMessageBox(
      reason
        .. "\n\nTo fix this:\n"
        .. "1. Open Extensions > ReaPack > Browse packages.\n"
        .. "2. Search for ReaImGui, then install or update it.\n"
        .. "3. Restart REAPER and run ReaClock again.\n\n"
        .. "If ReaImGui is not listed, synchronize your ReaPack repositories first.",
      TITLE .. " - ReaImGui Required", 0)
    return
  end
end

local _, _, section_id, command_id = R.get_action_context()
do
  local source = debug.getinfo(1, "S").source
  local path = source:sub(1, 1) == "@" and source:sub(2) or ""
  Runtime.script_path = path
  Runtime.script_dir = path:match("^(.*[\\/])") or ""
  Runtime.path_separator = package.config:sub(1, 1)
  Runtime.platform = R.GetOS and R.GetOS() or ""
  Runtime.is_windows = Runtime.path_separator == "\\"
  Runtime.is_macos = Runtime.platform:match("OSX") ~= nil
    or Runtime.platform:match("macOS") ~= nil
end

local function join_path(base, leaf)
  if base == "" then return leaf end
  local ending = base:sub(-1)
  if ending == "/" or ending == "\\" then return base .. leaf end
  return base .. Runtime.path_separator .. leaf
end

Runtime.resources_dir = join_path(Runtime.script_dir, "Resources")

-- Lua has no native JSON support, so ReaClock carries this small codec inline.
-- Keeping it here makes the installed package self-contained while retaining a
-- human-readable settings file and strict validation of malformed data.
local Json = { null = {}, array_metatable = {} }

function Json.array(value)
  return setmetatable(value or {}, Json.array_metatable)
end

do
  local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
  }

  local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
      return escapes[char] or string.format('\\u%04X', char:byte())
    end) .. '"'
  end

  local function array_length(value)
    local marked, count, highest = getmetatable(value) == Json.array_metatable, 0, 0
    for key in pairs(value) do
      if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
        if marked then error('JSON array keys must be positive integers') end
        return nil
      end
      count, highest = count + 1, math.max(highest, key)
    end
    if count ~= highest then
      if marked then error('cannot encode a sparse JSON array') end
      return nil
    end
    if count == 0 and not marked then return nil end
    return highest
  end

  local function encode_value(value, stack, indent, depth)
    local kind = type(value)
    if value == Json.null or kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then
      if value ~= value or value == math.huge or value == -math.huge then
        error('cannot encode a non-finite JSON number')
      end
      return string.format('%.17g', value)
    end
    if kind == 'string' then return quote(value) end
    if kind ~= 'table' then error('cannot encode JSON value of type ' .. kind) end
    if stack[value] then error('cannot encode a circular JSON table') end
    stack[value] = true

    local parts, length = {}, array_length(value)
    if length then
      for index = 1, length do
        parts[index] = encode_value(value[index], stack, indent, depth + 1)
      end
      stack[value] = nil
      if not indent or #parts == 0 then return '[' .. table.concat(parts, ',') .. ']' end
      local child_pad, pad = indent:rep(depth + 1), indent:rep(depth)
      return '[\n' .. child_pad .. table.concat(parts, ',\n' .. child_pad)
        .. '\n' .. pad .. ']'
    end

    local keys = {}
    for key in pairs(value) do
      if type(key) ~= 'string' then error('JSON object keys must be strings') end
      keys[#keys + 1] = key
    end
    table.sort(keys)
    for index, key in ipairs(keys) do
      parts[index] = quote(key) .. (indent and ': ' or ':')
        .. encode_value(value[key], stack, indent, depth + 1)
    end
    stack[value] = nil
    if not indent or #parts == 0 then return '{' .. table.concat(parts, ',') .. '}' end
    local child_pad, pad = indent:rep(depth + 1), indent:rep(depth)
    return '{\n' .. child_pad .. table.concat(parts, ',\n' .. child_pad)
      .. '\n' .. pad .. '}'
  end

  function Json.encode(value)
    return encode_value(value, {}, nil, 0)
  end

  function Json.encode_pretty(value)
    return encode_value(value, {}, '  ', 0)
  end

  local function utf8_char(codepoint)
    if codepoint <= 0x7F then return string.char(codepoint) end
    if codepoint <= 0x7FF then
      return string.char(0xC0 | (codepoint >> 6), 0x80 | (codepoint & 0x3F))
    end
    if codepoint <= 0xFFFF then
      return string.char(0xE0 | (codepoint >> 12),
        0x80 | ((codepoint >> 6) & 0x3F), 0x80 | (codepoint & 0x3F))
    end
    if codepoint <= 0x10FFFF then
      return string.char(0xF0 | (codepoint >> 18),
        0x80 | ((codepoint >> 12) & 0x3F),
        0x80 | ((codepoint >> 6) & 0x3F), 0x80 | (codepoint & 0x3F))
    end
    error('invalid Unicode codepoint in JSON string')
  end

  function Json.decode(text)
    if type(text) ~= 'string' then error('JSON input must be a string') end
    local position, length = 1, #text

    local function fail(message)
      error(string.format('%s at byte %d', message, position), 0)
    end

    local function skip_space()
      local _, last = text:find('^[ \t\r\n]*', position)
      position = (last or position - 1) + 1
    end

    local parse_value

    local function parse_string()
      position = position + 1
      local output = {}
      while position <= length do
        local byte = text:byte(position)
        if byte == 34 then
          position = position + 1
          return table.concat(output)
        end
        if byte < 32 then fail('unescaped control character in JSON string') end
        if byte ~= 92 then
          local start = position
          repeat
            position = position + 1
            byte = text:byte(position)
          until position > length or byte == 34 or byte == 92 or byte < 32
          output[#output + 1] = text:sub(start, position - 1)
        else
          position = position + 1
          local escape = text:sub(position, position)
          local mapped = ({ ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
            b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' })[escape]
          if mapped then
            output[#output + 1], position = mapped, position + 1
          elseif escape == 'u' then
            local hex = text:sub(position + 1, position + 4)
            local codepoint = #hex == 4 and tonumber(hex, 16) or nil
            if not codepoint then fail('invalid Unicode escape') end
            position = position + 5
            if codepoint >= 0xD800 and codepoint <= 0xDBFF then
              if text:sub(position, position + 1) ~= '\\u' then
                fail('missing low surrogate')
              end
              local low = tonumber(text:sub(position + 2, position + 5), 16)
              if not low or low < 0xDC00 or low > 0xDFFF then fail('invalid low surrogate') end
              codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00)
              position = position + 6
            elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
              fail('unexpected low surrogate')
            end
            output[#output + 1] = utf8_char(codepoint)
          else
            fail('invalid JSON escape')
          end
        end
      end
      fail('unterminated JSON string')
    end

    local function parse_number()
      local tail = text:sub(position)
      local token = tail:match('^%-?%d+%.?%d*[eE][%+%-]?%d+')
        or tail:match('^%-?%d+%.%d+') or tail:match('^%-?%d+')
      local value = token and tonumber(token) or nil
      if not value then fail('invalid JSON number') end
      position = position + #token
      return value
    end

    local function parse_array()
      position = position + 1
      skip_space()
      local value = Json.array()
      if text:sub(position, position) == ']' then position = position + 1 return value end
      while true do
        value[#value + 1] = parse_value()
        skip_space()
        local delimiter = text:sub(position, position)
        position = position + 1
        if delimiter == ']' then return value end
        if delimiter ~= ',' then fail('expected comma or closing bracket') end
        skip_space()
      end
    end

    local function parse_object()
      position = position + 1
      skip_space()
      local value = {}
      if text:sub(position, position) == '}' then position = position + 1 return value end
      while true do
        if text:sub(position, position) ~= '"' then fail('expected JSON object key') end
        local key = parse_string()
        skip_space()
        if text:sub(position, position) ~= ':' then fail('expected colon after JSON object key') end
        position = position + 1
        skip_space()
        value[key] = parse_value()
        skip_space()
        local delimiter = text:sub(position, position)
        position = position + 1
        if delimiter == '}' then return value end
        if delimiter ~= ',' then fail('expected comma or closing brace') end
        skip_space()
      end
    end

    function parse_value()
      skip_space()
      local char = text:sub(position, position)
      if char == '"' then return parse_string() end
      if char == '{' then return parse_object() end
      if char == '[' then return parse_array() end
      if char == '-' or char:match('%d') then return parse_number() end
      if text:sub(position, position + 3) == 'true' then position = position + 4 return true end
      if text:sub(position, position + 4) == 'false' then position = position + 5 return false end
      if text:sub(position, position + 3) == 'null' then position = position + 4 return Json.null end
      fail('unexpected JSON value')
    end

    local value = parse_value()
    skip_space()
    if position <= length then fail('unexpected trailing JSON data') end
    return value
  end
end

-- User settings live in REAPER's writable Data directory rather than beside
-- the ReaPack-managed script. The singleton token remains the only production
-- ExtState value; a private override is available to the portable test harness.
local Store = {
  schema_version = 2,
  dirty = false,
  save_after = 0,
  test_override = R.GetExtState(EXT, "__test_override") == "1",
  json = Json,
}

Store.dir = join_path(join_path(R.GetResourcePath(), "Data"), "ReaClock")
Store.path = join_path(Store.dir, "settings.json")
Store.backup_path = join_path(Store.dir, "settings.json.bak")

function Store.default_root()
  return {
    schema_version = Store.schema_version,
    settings = {},
    faces = { active = "default", user_next = 1, user_ids = "", names = {}, layouts = {} },
    detached_cards = Json.array(),
    detached_next = 1,
  }
end

Store.root = Store.default_root()

function Store.read(path)
  local file = io.open(path, "rb")
  if not file then return nil, "not found" end
  local text = file:read("*a")
  file:close()
  local ok, decoded = pcall(Store.json.decode, text)
  if not ok or type(decoded) ~= "table" then
    return nil, ok and "root is not an object" or tostring(decoded)
  end
  if type(decoded.settings) ~= "table" or type(decoded.faces) ~= "table" then
    return nil, "required settings or faces object is missing"
  end
  return decoded
end

function Store.normalize(root)
  -- A missing version predates the current schema and must still receive any
  -- conservative migrations. Fresh roots already carry Store.schema_version.
  root.schema_version = tonumber(root.schema_version) or 1
  root.settings = type(root.settings) == "table" and root.settings or {}
  root.faces = type(root.faces) == "table" and root.faces or {}
  root.faces.active = type(root.faces.active) == "string" and root.faces.active or "default"
  root.faces.user_next = tonumber(root.faces.user_next) or 1
  root.faces.user_ids = type(root.faces.user_ids) == "string" and root.faces.user_ids or ""
  root.faces.names = type(root.faces.names) == "table" and root.faces.names or {}
  root.faces.layouts = type(root.faces.layouts) == "table" and root.faces.layouts or {}
  root.detached_cards = Json.array(type(root.detached_cards) == "table" and root.detached_cards or {})
  root.detached_next = math.max(1, math.floor(tonumber(root.detached_next) or 1))
  return root
end

function Store.set_warning(text, label)
  Store.warning = text
  Store.warning_label = label or "SETTINGS NOTICE"
  Store.warning_started_at = R.time_precise()
  Store.warning_acknowledged = false
end

function Store.load()
  -- Deterministic harness scenarios use temporary ExtState values and must
  -- never read or write the portable install's real JSON preferences.
  if Store.test_override then return end
  local root, load_error = Store.read(Store.path)
  if root then
    Store.root = Store.normalize(root)
    Store.invalid_primary = false
    return
  end

  local backup = Store.read(Store.backup_path)
  if backup then
    Store.root = Store.normalize(backup)
    Store.invalid_primary = load_error ~= "not found"
    Store.set_warning(
      "ReaClock recovered settings from settings.json.bak because settings.json was invalid.",
      "SETTINGS RECOVERED")
    Store.dirty, Store.save_after = true, R.time_precise() + 0.5
    return
  end

  Store.invalid_primary = load_error ~= "not found"
  if load_error ~= "not found" then
    Store.set_warning(
      "ReaClock could not read settings.json and started with safe defaults. The invalid file will be preserved as settings.json.corrupt on the next save.",
      "SETTINGS RESET")
  else
    -- A first run (or an intentionally deleted settings file) is not an
    -- error. Once the runtime defaults have been assembled, write them out
    -- immediately so the on-disk state always matches what the user sees.
    Store.create_defaults = true
  end
end

function Store.mark_dirty()
  if Store.test_override then return end
  Store.dirty, Store.save_after = true, R.time_precise() + 0.35
end

function Store.flush(force)
  if Store.test_override or Store.suppress_flush or not Store.dirty then return true end
  if not force and R.time_precise() < Store.save_after then return true end
  if R.RecursiveCreateDirectory then R.RecursiveCreateDirectory(Store.dir, 0) end

  Store.root.schema_version = Store.schema_version
  local encoder = Store.json.encode_pretty or Store.json.encode
  local ok, encoded = pcall(encoder, Store.root)
  if not ok then Store.error = "Could not encode settings: " .. tostring(encoded) return false end
  local temporary = Store.path .. ".tmp"
  local file, open_error = io.open(temporary, "wb")
  if not file then Store.error = "Could not write settings: " .. tostring(open_error) return false end
  file:write(encoded, "\n")
  file:flush()
  file:close()

  local current = io.open(Store.path, "rb")
  if current then current:close() end
  if current and Store.invalid_primary then
    local corrupt_path = Store.path .. ".corrupt"
    os.remove(corrupt_path)
    local preserved, preserve_error = os.rename(Store.path, corrupt_path)
    if not preserved then
      os.remove(temporary)
      Store.error = "Could not preserve invalid settings: " .. tostring(preserve_error)
      return false
    end
    current = nil
  elseif current then
    os.remove(Store.backup_path)
    local backed_up, backup_error = os.rename(Store.path, Store.backup_path)
    if not backed_up then
      os.remove(temporary)
      Store.error = "Could not back up settings: " .. tostring(backup_error)
      return false
    end
  end
  local replaced, replace_error = os.rename(temporary, Store.path)
  if not replaced then
    os.rename(Store.backup_path, Store.path)
    os.remove(temporary)
    Store.error = "Could not replace settings: " .. tostring(replace_error)
    return false
  end
  Store.dirty, Store.error, Store.invalid_primary = false, nil, false
  return true
end

-- Factory Reset owns the complete Data/ReaClock container. Clearing it
-- recursively makes the reset future-proof: newly added preferences or
-- auxiliary settings files cannot survive simply because a reset list was not
-- updated. User-selected assets live outside this directory and are untouched.
function Store.clear_all()
  if type(R.EnumerateFiles) ~= "function"
      or type(R.EnumerateSubdirectories) ~= "function" then
    return false, "This REAPER build cannot enumerate the ReaClock settings folder."
  end
  local normalized = Store.dir:gsub("\\", "/"):gsub("/+$", ""):lower()
  if not normalized:match("/data/reaclock$") then
    return false, "Safety check refused an unexpected settings path: " .. Store.dir
  end

  local function entries(path, enumerate)
    local result, index = {}, 0
    while true do
      local name = enumerate(path, index)
      if not name or name == "" then break end
      result[#result + 1], index = name, index + 1
    end
    return result
  end

  local function remove_empty_directory(path)
    local removed, remove_error, remove_code = os.remove(path)
    if removed then return true end
    -- os.rename(path, path) is a side-effect-free existence check for files
    -- and directories. A stale enumeration entry is already a success.
    if not os.rename(path, path) then return true end
    if Runtime.is_windows and type(R.ExecProcess) == "function" then
      -- Lua's Windows CRT cannot remove directories with os.remove. `rd`
      -- receives an already-verified, empty, ReaClock-owned path; no recursive
      -- switch is used, so it cannot delete unexpected contents.
      if path:find('"', 1, true) then
        return false, "Could not safely quote the settings directory " .. path
      end
      local command_path = path:gsub("%%", "%%%%")
      local result = R.ExecProcess('cmd.exe /D /C rd "' .. command_path .. '"', 2000)
      local exit_code = tonumber(tostring(result or ""):match("^([%-]?%d+)"))
      if exit_code == 0 or not os.rename(path, path) then return true end
      return false, "Could not remove " .. path .. ": " .. tostring(result)
    end
    if remove_code == 2 then return true end
    return false, "Could not remove " .. path .. ": " .. tostring(remove_error)
  end

  local function clear_directory(path)
    for _, name in ipairs(entries(path, R.EnumerateFiles)) do
      local target = join_path(path, name)
      local removed, remove_error, remove_code = os.remove(target)
      if not removed and remove_code ~= 2 then
        return false, "Could not remove " .. target .. ": " .. tostring(remove_error)
      end
    end
    for _, name in ipairs(entries(path, R.EnumerateSubdirectories)) do
      local child = join_path(path, name)
      local cleared, clear_error = clear_directory(child)
      if not cleared then return false, clear_error end
      local removed, remove_error = remove_empty_directory(child)
      if not removed then return false, remove_error end
    end
    return true
  end

  -- Suppress every old-instance save path before deleting anything. The new
  -- instance recreates the directory and one canonical settings.json.
  Store.suppress_flush = true
  local cleared, clear_error = clear_directory(Store.dir)
  if not cleared then
    Store.suppress_flush = false
    return false, clear_error
  end
  local removed_root, root_error = remove_empty_directory(Store.dir)
  if not removed_root then
    Store.suppress_flush = false
    return false, root_error
  end
  Store.root = Store.default_root()
  Store.dirty, Store.error, Store.invalid_primary = false, nil, false
  return true
end

Store.load()

local existing_instance = R.GetExtState(EXT, "running")
if existing_instance ~= "" and existing_instance ~= "0" then
  R.SetExtState(EXT, "running", "0", false)
  return
end

-- A unique token prevents an older deferred callback from adopting a newer
-- instance's running state during a very fast stop/restart cycle.
local instance_token = string.format("%.17g:%s", R.time_precise(), tostring({}))
R.SetExtState(EXT, "running", instance_token, false)

if section_id and command_id and command_id > 0 then
  R.SetToggleCommandState(section_id, command_id, 1)
  R.RefreshToolbar2(section_id, command_id)
end

local cleaned_up = false
local function cleanup()
  if cleaned_up then return end
  cleaned_up = true
  Store.flush(true)
  local owns_instance = R.GetExtState(EXT, "running") == instance_token
  if owns_instance then
    R.SetExtState(EXT, "running", "0", false)
  end
  if owns_instance and section_id and command_id and command_id > 0 then
    R.SetToggleCommandState(section_id, command_id, 0)
    R.RefreshToolbar2(section_id, command_id)
  end
  if Metering and Metering.Visual and Metering.Visual.release_all then
    pcall(Metering.Visual.release_all, false)
  end
end

R.atexit(cleanup)

-- -----------------------------------------------------------------------------
-- Persistent settings
-- -----------------------------------------------------------------------------

local function ext_string(key, fallback)
  if Store.test_override then
    local override = R.GetExtState(EXT, key)
    if override ~= "" then return override end
  end
  local value = Store.root.settings[key]
  if value == nil then return fallback end
  return tostring(value)
end

local function ext_number(key, fallback)
  return tonumber(ext_string(key, "")) or fallback
end

local function ext_bool(key, fallback)
  local value = ext_string(key, "")
  if value == "" then return fallback end
  return value == "1"
end

local THEME_PRESETS = {
  dark = {
    label = "Dark",
    description = "Low-glare charcoal with steel blue and restrained plum accents.",
    background = 0x141518FF,
    text = 0xECEEF0FF,
    highlight = 0x6C9BBDFF,
    card = 0x1D2024FF,
    border = 0x2C3239FF,
    label_color = 0xA9B0B8FF,
    secondary_accent = 0x806C92FF,
    control = 0x4F718DFF,
    progress_track = 0x24292FFF,
    card_accents = { 0x91AFC5FF, 0xAAB3BCFF, 0xAF92B8FF },
  },
  light = {
    label = "Light",
    description = "Clean paper-white surfaces with slate blue and muted mauve details.",
    background = 0xE1E4E8FF,
    text = 0x171B20FF,
    highlight = 0x41688AFF,
    card = 0xF2F4F6FF,
    border = 0xB6BEC5FF,
    label_color = 0x4E5C67FF,
    secondary_accent = 0x8D6F85FF,
    control = 0x658199FF,
    progress_track = 0xCDD3D8FF,
    card_accents = { 0x2F5F7EFF, 0x6A5370FF, 0x486351FF },
  },
  sunny = {
    label = "Sunny",
    description = "Warm cream and honeyed cards with amber, olive, and earth accents.",
    background = 0xF5EAD1FF,
    text = 0x2A2117FF,
    highlight = 0xAD5A19FF,
    card = 0xEDDDBAFF,
    border = 0xCFAC74FF,
    label_color = 0x6C5536FF,
    secondary_accent = 0x757D43FF,
    control = 0xAE6F3CFF,
    progress_track = 0xE3D0A8FF,
    card_accents = { 0x8A4015FF, 0x4F612DFF, 0x6D4B35FF },
  },
  cool = {
    label = "Cool",
    description = "Deep blue-gray with calm cyan, cornflower, and mint accents.",
    background = 0x121E28FF,
    text = 0xE9F2F5FF,
    highlight = 0x61B4CCFF,
    card = 0x1A2C38FF,
    border = 0x2A4A5CFF,
    label_color = 0xA8C3CEFF,
    secondary_accent = 0x6B87D8FF,
    control = 0x427487FF,
    progress_track = 0x213743FF,
    card_accents = { 0x6CC5D9FF, 0x8BB7E8FF, 0x71C7A1FF },
  },
  rainbow = {
    label = "Rainbow",
    description = "Dark violet surfaces with a polished rotating spectrum of card accents.",
    background = 0x171520FF,
    text = 0xF2EEF7FF,
    highlight = 0xC279E6FF,
    card = 0x231F2FFF,
    border = 0x463A52FF,
    label_color = 0xB9ACC6FF,
    secondary_accent = 0x6BC6D9FF,
    control = 0x7F5899FF,
    progress_track = 0x2C2739FF,
    card_accents = {
      0x70BDE9FF, 0x68CDA0FF, 0xE8C75EFF, 0xEE9475FF, 0xCB8DE8FF,
    },
  },
  forest = {
    label = "Forest",
    description = "Deep botanical greens with sage, teal, and muted gold accents.",
    background = 0x131E17FF,
    text = 0xEDF3EEFF,
    highlight = 0x7CB983FF,
    card = 0x1C2C23FF,
    border = 0x2E4D39FF,
    label_color = 0xA8C3ADFF,
    secondary_accent = 0xC19A5BFF,
    control = 0x497752FF,
    progress_track = 0x25392CFF,
    card_accents = { 0x83BE88FF, 0xDBC07AFF, 0x6CB6A1FF },
  },
  midnight = {
    label = "Midnight",
    description = "Inky navy with luminous cobalt, violet, and turquoise accents.",
    background = 0x0D1523FF,
    text = 0xEEF3FBFF,
    highlight = 0x6899F0FF,
    card = 0x142136FF,
    border = 0x294060FF,
    label_color = 0xA9B9D2FF,
    secondary_accent = 0x8B72E8FF,
    control = 0x4064A8FF,
    progress_track = 0x1C2B45FF,
    card_accents = { 0x70A1F4FF, 0x8C84EDFF, 0x65C9C0FF },
  },
  rose = {
    label = "Rose",
    description = "Soft blush surfaces with berry, plum, and terracotta accents.",
    background = 0xF2E4E7FF,
    text = 0x35252AFF,
    highlight = 0x9F5269FF,
    card = 0xE8D1D7FF,
    border = 0xCFA8B4FF,
    label_color = 0x73545EFF,
    secondary_accent = 0xA1644AFF,
    control = 0xAC6B7DFF,
    progress_track = 0xDEC2C9FF,
    card_accents = { 0x8F4056FF, 0x70445FFF, 0x884A35FF },
  },
  pitch_black = {
    label = "Pitch Black",
    description = "True black with quiet monochrome surfaces for late-night sessions.",
    background = 0x000000FF,
    text = 0x8F8F8FFF,
    highlight = 0x636363FF,
    card = 0x080808FF,
    border = 0x1F1F1FFF,
    label_color = 0x7C7C7CFF,
    secondary_accent = 0x686868FF,
    control = 0x404040FF,
    progress_track = 0x141414FF,
    card_accents = { 0x848484FF, 0x808080FF, 0x7C7C7CFF },
  },
}
local STYLE_PRESET_ORDER = {
  "dark", "light", "sunny", "cool", "rainbow", "forest", "midnight", "rose",
  "pitch_black",
}

-- Schema 2 refines the built-in palette anchors. Migrate only an exact match
-- for a schema-1 preset: users who changed even one anchor keep their saved
-- colors, including hand-edited files that still carry a built-in mode ID.
Store.theme_preset_anchors_v1 = {
  dark = { 0x18191CFF, 0xECEEF0FF, 0x5B86A6FF },
  light = { 0xD7DBDFFF, 0x171B20FF, 0x4F7694FF },
  sunny = { 0xF1E3C4FF, 0x2A2117FF, 0xB86120FF },
  cool = { 0x16232DFF, 0xE9F2F5FF, 0x57A9C2FF },
  rainbow = { 0x1C1A26FF, 0xF2EEF7FF, 0xC279E6FF },
  forest = { 0x18231DFF, 0xEDF3EEFF, 0x71AD78FF },
  midnight = { 0x101827FF, 0xEEF3FBFF, 0x5F8FE8FF },
  rose = { 0xF2E4E7FF, 0x35252AFF, 0xB45D76FF },
  pitch_black = { 0x000000FF, 0x888888FF, 0x5C5C5CFF },
}

function Store.stored_color_equals(value, expected)
  if type(value) == "number" then return math.floor(value) == expected end
  local hex = tostring(value or ""):match("^#?(%x%x%x%x%x%x%x%x)$")
  return hex ~= nil and tonumber(hex, 16) == expected
end

function Store.migrate_theme_preset_anchors()
  local version = tonumber(Store.root.schema_version) or 1
  if version >= 2 then return end
  local stored = Store.root.settings
  local mode = type(stored.theme_mode) == "string" and stored.theme_mode or "midnight"
  local previous, current = Store.theme_preset_anchors_v1[mode], THEME_PRESETS[mode]
  if previous and current
      and Store.stored_color_equals(stored.theme_background, previous[1])
      and Store.stored_color_equals(stored.theme_text, previous[2])
      and Store.stored_color_equals(stored.theme_highlight, previous[3]) then
    stored.theme_background = string.format("%08X", current.background)
    stored.theme_text = string.format("%08X", current.text)
    stored.theme_highlight = string.format("%08X", current.highlight)
  end
  Store.root.schema_version = 2
  Store.mark_dirty()
end

Store.migrate_theme_preset_anchors()

local DEFAULT_APPEARANCE = {
  regular_font = "Roboto",
  mono_font = "Chivo Mono",
  regular_weight = "regular",
  mono_weight = "regular",
  regular_size = 1.0,
  mono_size = 1.0,
  background = THEME_PRESETS.midnight.background,
  text = THEME_PRESETS.midnight.text,
  highlight = THEME_PRESETS.midnight.highlight,
  background_gradient_strength = 1.00,
  card_background_opacity = 0.50,
  background_image_path = "",
  background_image_opacity = 0.12,
  card_alignment = "left",
  recording_background_enabled = true,
  recording_background = 0x2A181CFF,
}

local MAX_CARD_ROWS = 20
local CARDS_PER_ROW = 6
local TOTAL_CARD_SLOTS = MAX_CARD_ROWS * CARDS_PER_ROW
local ROW_SIZE_OPTIONS = {
  small = { label = "Small", height = 52, label_size = 9, value_size = 30 },
  medium = { label = "Medium", height = 64, label_size = 10, value_size = 38 },
  large = { label = "Large", height = 78, label_size = 10.5, value_size = 48 },
  huge = { label = "Huge", height = 104, label_size = 11, value_size = 64 },
  visualizer = { label = "Visualizer", height = 156, label_size = 11, value_size = 70 },
}
local ROW_SIZE_ORDER = { "small", "medium", "large", "huge", "visualizer" }

local function normalize_card_span(value)
  if value == "auto" or value == nil then return "auto" end
  local numeric = tonumber(value)
  if not numeric then return "auto" end
  numeric = math.floor(numeric + 0.5)
  if numeric < 1 or numeric > CARDS_PER_ROW then return "auto" end
  return tostring(numeric)
end

-- Reuse Runtime to avoid adding another long-lived main-chunk local. Each
-- size owns its reserved band as well as the Chivo Mono optical lift.
Runtime.clock_sizes = {
  small = { label = "Small", height = 118, font_size = 115, text_offset = -10 },
  medium = { label = "Medium", height = 158, font_size = 160, text_offset = -16 },
  large = { label = "Large", height = 200, font_size = 205, text_offset = -23 },
  huge = { label = "Huge", height = 242, font_size = 250, text_offset = -28 },
  order = { "small", "medium", "large", "huge" },
}
Runtime.card_scroll_states = {}

-- Every grid slot shares one concise content model; row and column controls
-- provide flexibility without allowing arbitrary, fragile freeform placement.
local CARD_TYPE_OPTIONS = {
  { id = "none", label = "None" },
  { id = "length", label = "Length", group = "time_transport" },
  { id = "remaining", label = "Remaining", group = "time_transport" },
  { id = "position", label = "Current Position", group = "time_transport" },
  { id = "tempo", label = "Tempo", group = "time_transport" },
  { id = "time_signature", label = "Time Signature", group = "time_transport" },
  { id = "visual_click", label = "Visual Click", group = "time_transport" },
  { id = "transport", label = "Transport Status", group = "time_transport" },
  { id = "current_region", label = "Current Region", group = "regions_markers" },
  { id = "next_region", label = "Next Region", group = "regions_markers" },
  { id = "next_region_countdown", label = "Next Region Countdown",
    group = "regions_markers" },
  { id = "next_marker", label = "Next Marker", group = "regions_markers" },
  { id = "next_marker_countdown", label = "Next Marker Countdown",
    group = "regions_markers" },
  { id = "project", label = "Project Name", group = "project_local" },
  { id = "project_title", label = "Project Title", group = "project_local" },
  { id = "time12", label = "System Time - 12-hour", group = "project_local" },
  { id = "time24", label = "System Time - 24-hour", group = "project_local" },
  { id = "date", label = "System Date", group = "project_local" },
  { id = "sample_rate", label = "Sample Rate", group = "audio", section = "format",
    technical = true },
  { id = "buffer_size", label = "Buffer Size", group = "audio", section = "format",
    technical = true },
  { id = "bit_depth", label = "Bit Depth", group = "audio", section = "format",
    technical = true },
  { id = "audio_mode", label = "Audio Driver / Mode", group = "audio", section = "format",
    technical = true },
  { id = "input_latency", label = "Input Latency", group = "audio", section = "latency",
    technical = true },
  { id = "output_latency", label = "Output Latency", group = "audio", section = "latency",
    technical = true },
  { id = "roundtrip_latency", label = "Roundtrip Latency", group = "audio",
    section = "latency", technical = true },
  { id = "input_device", label = "Input Device", group = "audio", section = "devices",
    technical = true },
  { id = "output_device", label = "Output Device", group = "audio", section = "devices",
    technical = true },
  { id = "audio_inputs", label = "Audio Input Channels", group = "audio",
    section = "devices", technical = true },
  { id = "audio_outputs", label = "Audio Output Channels", group = "audio",
    section = "devices", technical = true },
  { id = "midi_inputs", label = "MIDI Inputs", group = "audio", section = "devices",
    technical = true },
  { id = "midi_outputs", label = "MIDI Outputs", group = "audio", section = "devices",
    technical = true },
  { id = "audio_xrun", label = "Last Audio Underrun", group = "audio", section = "health",
    technical = true },
  { id = "media_xrun", label = "Last Media Underrun", group = "audio", section = "health",
    technical = true },
  { id = "track_count", label = "Track Count", group = "project_stats", technical = true },
  { id = "item_count", label = "Media Item Count", group = "project_stats", technical = true },
  { id = "selected_tracks", label = "Selected Track Count", group = "project_stats",
    technical = true },
  { id = "selected_items", label = "Selected Item Count", group = "project_stats",
    technical = true },
  { id = "marker_count", label = "Marker Count", group = "project_stats", technical = true },
  { id = "region_count", label = "Region Count", group = "project_stats", technical = true },
  { id = "project_tabs", label = "Open Project Tabs", group = "project_stats",
    technical = true },
  { id = "project_status", label = "Project Save Status", group = "project_stats",
    technical = true },
  { id = "record_disk_free", label = "Recording Disk Free", group = "project_stats",
    technical = true },
  { id = "meter", label = "Metering", group = "metering" },
  { id = "action", label = "Action Button" },
  { id = "custom", label = "Custom Template" },
}

local CARD_TYPE_DESCRIPTIONS = {
  none = "Keeps this configured slot empty until you choose another content type.",
  length = "Shows the total duration of the active project, region, or time selection.",
  remaining = "Shows signed time remaining in the active scope, including overtime after its end.",
  position = "Shows the current position measured from the start of the active scope.",
  tempo = "Shows the project tempo at the current play or edit position.",
  time_signature = "Shows the time signature at the current play or edit position.",
  visual_click = "Shows the current beat and a phase-accurate visual pulse during playback.",
  current_region = "Shows the name of the region currently under the playhead or edit cursor.",
  next_region = "Shows the next project region after the playhead or edit cursor.",
  next_region_countdown = "Counts down to the next project region and shows signed overtime.",
  next_marker = "Shows the next project marker after the playhead or edit cursor.",
  next_marker_countdown = "Counts down to the next project marker and shows signed overtime.",
  transport = "Shows whether REAPER is stopped, paused, playing, or recording.",
  project = "Shows the active REAPER project tab name.",
  project_title = "Shows the title stored in the active REAPER project's metadata.",
  time12 = "Shows the computer's local time using a 12-hour clock.",
  time24 = "Shows the computer's local time using a 24-hour clock.",
  date = "Shows the computer's current local date.",
  sample_rate = "Shows the active project or audio-device sample rate.",
  buffer_size = "Shows the audio device's current block or buffer size.",
  bit_depth = "Shows the active recording or project media bit depth when REAPER reports it.",
  input_latency = "Shows the latency REAPER reports for the active audio input path.",
  output_latency = "Shows the latency REAPER reports for the active audio output path.",
  roundtrip_latency = "Shows the combined reported input and output latency.",
  audio_mode = "Shows the active audio driver or device mode.",
  input_device = "Shows the active audio input device.",
  output_device = "Shows the active audio output device.",
  audio_inputs = "Shows the number of audio input channels currently available to REAPER.",
  audio_outputs = "Shows the number of audio output channels currently available to REAPER.",
  midi_inputs = "Shows the MIDI input devices currently available to REAPER.",
  midi_outputs = "Shows the MIDI output devices currently available to REAPER.",
  audio_xrun = "Shows the most recently reported audio underrun count.",
  media_xrun = "Shows the most recently reported media underrun count.",
  track_count = "Shows the total number of tracks in the active project.",
  item_count = "Shows the total number of media items in the active project.",
  selected_tracks = "Shows how many tracks are currently selected.",
  selected_items = "Shows how many media items are currently selected.",
  marker_count = "Shows the total number of project markers.",
  region_count = "Shows the total number of project regions.",
  project_tabs = "Shows how many REAPER project tabs are currently open.",
  project_status = "Shows whether the active project has unsaved changes.",
  record_disk_free = "Shows the free space available at the active recording path.",
  meter = "Shows a numeric loudness reading or a live audio visualization from a ReaClock meter.",
  action = "Runs one installed Main-section REAPER action or script from a deliberate button click.",
  custom = "Combines your own label, text, and live ReaClock tokens in one card.",
}

local CARD_GROUPS = {
  { id = "time_transport", label = "Time & Transport" },
  { id = "regions_markers", label = "Regions & Markers" },
  { id = "project_local", label = "Project & Local Time" },
  { id = "metering", label = "Metering" },
  { id = "visualizations", label = "Visualizations" },
  { id = "audio", label = "Audio System", sections = {
    { id = "format", label = "Session Format" },
    { id = "latency", label = "Latency" },
    { id = "devices", label = "Devices & I/O" },
    { id = "health", label = "Health" },
  } },
  { id = "project_stats", label = "Project Statistics" },
}
local METER_FACE_IDS = { metering = true, visualizations = true }

local CARD_TYPE_BY_ID, TECHNICAL_TOKEN_IDS = {}, {}
for _, option in ipairs(CARD_TYPE_OPTIONS) do
  CARD_TYPE_BY_ID[option.id] = option
  if option.technical then
    TECHNICAL_TOKEN_IDS[#TECHNICAL_TOKEN_IDS + 1] = option.id
  end
end

-- The insert-token picker is built from the same card catalog used by the
-- clock, so newly added technical values become discoverable automatically.
local TEMPLATE_TOKEN_GROUPS = {
  { label = "Time & Transport", tokens = {
    { id = "position", label = "Current position" },
    { id = "length", label = "Scope length" },
    { id = "remaining", label = "Signed remaining time" },
    { id = "tempo", label = "Tempo" },
    { id = "timesig", label = "Time signature" },
    { id = "transport", label = "Transport status" },
    { id = "scope", label = "Active scope" },
    { id = "units", label = "Active units" },
  } },
  { label = "Regions & Markers", tokens = {
    { id = "region", label = "Current region" },
    { id = "next_region", label = "Next region name" },
    { id = "next_region_countdown", label = "Next region countdown" },
    { id = "next_marker", label = "Next marker name" },
    { id = "next_marker_countdown", label = "Next marker countdown" },
  } },
  { label = "Project & Local Time", tokens = {
    { id = "project", label = "Project name" },
    { id = "project_title", label = "Project title" },
    { id = "author", label = "Project author" },
    { id = "time12", label = "12-hour local time" },
    { id = "time24", label = "24-hour local time" },
    { id = "date", label = "Local date" },
  } },
}
for _, group in ipairs(CARD_GROUPS) do
  local token_group = { label = group.label, tokens = {}, sections = {} }
  if group.sections then
    for _, section in ipairs(group.sections) do
      token_group.sections[#token_group.sections + 1] = {
        id = section.id, label = section.label, tokens = {},
      }
    end
  end
  for _, option in ipairs(CARD_TYPE_OPTIONS) do
    if option.group == group.id and option.technical then
      local target = token_group.tokens
      if option.section then
        for _, section in ipairs(token_group.sections) do
          if section.id == option.section then target = section.tokens break end
        end
      end
      target[#target + 1] = { id = option.id, label = option.label }
    end
  end
  local count = #token_group.tokens
  for _, section in ipairs(token_group.sections) do count = count + #section.tokens end
  if count > 0 then TEMPLATE_TOKEN_GROUPS[#TEMPLATE_TOKEN_GROUPS + 1] = token_group end
end

local CARD_DEFAULTS = {}
local METER_CARD_FIELDS = {
  { key = "meter_display", kind = "enum", default = "numeric",
    values = { numeric = true, levels = true, history = true, waveform = true,
      spectrum = true, spectrogram = true, vectorscope = true, correlation = true } },
  { key = "meter_metric", kind = "enum", default = "lufs_i",
    values = { sample_peak = true, sample_peak_max = true, true_peak = true,
      true_peak_max = true, rms_m = true, rms_m_max = true, rms_i = true,
      rms_i_max = true, lufs_m = true, lufs_m_max = true, lufs_s = true,
      lufs_s_max = true, lufs_i = true, lufs_i_max = true, lra = true,
      lra_max = true } },
  { key = "meter_source_kind", kind = "enum", default = "",
    values = { [""] = true, monitoring = true, master = true, track = true } },
  { key = "meter_track_guid", kind = "string", default = "" },
  { key = "meter_fx_guid", kind = "string", default = "" },
  { key = "meter_source_ordinal", kind = "number", default = 1, min = 1, max = 64,
    integer = true },
  { key = "meter_last_source_name", kind = "string", default = "" },
  { key = "meter_visual_quality", kind = "enum", default = "auto",
    values = { auto = true, low = true, standard = true, high = true, maximum = true } },
  { key = "meter_channel_mode", kind = "enum", default = "auto",
    values = { auto = true, mono = true, pair = true, all = true } },
  { key = "meter_channel_a", kind = "number", default = 1, min = 1, max = 64,
    integer = true },
  { key = "meter_channel_b", kind = "number", default = 2, min = 1, max = 64,
    integer = true },
  { key = "meter_level_floor", kind = "number", default = -60, min = -90, max = -36 },
  { key = "meter_level_peak_max", kind = "boolean", default = true },
  { key = "meter_level_true_peak_marker", kind = "boolean", default = false },
  { key = "meter_history_traces", kind = "string", default = "m,s,i" },
  { key = "meter_history_seconds", kind = "number", default = 60, min = 30,
    max = 7200, integer = true },
  { key = "meter_history_min", kind = "number", default = -36, min = -120, max = 12 },
  { key = "meter_history_max", kind = "number", default = -6, min = -120, max = 24 },
  { key = "meter_history_target", kind = "number", default = -14, min = -120, max = 24 },
  { key = "meter_waveform_timebase", kind = "number", default = 50, min = 10,
    max = 250, integer = true },
  { key = "meter_waveform_layout", kind = "enum", default = "overlay",
    values = { overlay = true, stacked = true } },
  { key = "meter_spectrum_fft_size", kind = "number", default = 4096, min = 1024,
    max = 8192, integer = true },
  { key = "meter_spectrum_floor", kind = "number", default = -90, min = -120, max = -60 },
  { key = "meter_spectrum_smoothing", kind = "number", default = 0.6, min = 0, max = 0.95 },
  { key = "meter_spectrum_peak_hold", kind = "boolean", default = true },
  { key = "meter_spectrogram_seconds", kind = "number", default = 10, min = 5,
    max = 30, integer = true },
  { key = "meter_spectrogram_bins", kind = "number", default = 1024, min = 64,
    max = 1024, integer = true },
  { key = "meter_spectrogram_palette", kind = "enum", default = "ocean",
    values = { theme = true, ocean = true, ember = true, violet = true } },
  { key = "meter_spectrogram_scale", kind = "enum", default = "mel",
    values = { mel = true, log = true, linear = true } },
  { key = "meter_spectrogram_mode", kind = "enum", default = "sharper",
    values = { sharper = true, sharp = true, classic = true } },
  { key = "meter_spectrogram_tilt", kind = "number", default = 4.5, min = -12,
    max = 12 },
  { key = "meter_scope_mode", kind = "enum", default = "lr",
    values = { lr = true, ms = true } },
  { key = "meter_scope_persistence", kind = "number", default = 0.35, min = 0, max = 2 },
  { key = "meter_correlation_seconds", kind = "number", default = 10, min = 3,
    max = 60, integer = true },
}
Runtime.action_card_fields = {
  { key = "action_command", default = "" },
  { key = "action_name", default = "" },
  { key = "action_text", default = "" },
}

local function meter_field_default(field)
  return field.default
end

local function normalize_meter_field(field, value)
  if field.kind == "boolean" then return value == true end
  if field.kind == "number" then
    value = tonumber(value)
    if value == nil then value = field.default end
    value = math.max(field.min or -math.huge, math.min(field.max or math.huge, value))
    if field.integer then value = math.floor(value + 0.5) end
    return value
  end
  value = type(value) == "string" and value or tostring(value or "")
  if field.kind == "enum" and not field.values[value] then return field.default end
  return value
end

local function add_meter_field_defaults(card)
  for _, field in ipairs(METER_CARD_FIELDS) do
    if card[field.key] == nil then card[field.key] = meter_field_default(field) end
  end
  return card
end

function Runtime.normalize_action_field(value, fallback)
  if value == nil then value = fallback or "" end
  return tostring(value)
end

function Runtime.add_card_field_defaults(card)
  add_meter_field_defaults(card)
  for _, field in ipairs(Runtime.action_card_fields) do
    if card[field.key] == nil then card[field.key] = field.default end
  end
  return card
end

for index = 1, TOTAL_CARD_SLOTS do
  CARD_DEFAULTS[index] = Runtime.add_card_field_defaults({
    type = "none", label = "CUSTOM", template = "", font = "auto", scroll = false,
    align = "default", span = "auto",
  })
end
-- Default is deliberately readable at a distance: a large current-region row,
-- four session values, then two wide upcoming-region cards.
CARD_DEFAULTS[1] = { type = "current_region", label = "CUSTOM", template = "{region}", font = "auto" }
CARD_DEFAULTS[7] = { type = "length", label = "CUSTOM", template = "{length}", font = "auto" }
CARD_DEFAULTS[8] = { type = "remaining", label = "CUSTOM", template = "{remaining}", font = "auto" }
CARD_DEFAULTS[9] = { type = "tempo", label = "CUSTOM", template = "{tempo}", font = "auto" }
CARD_DEFAULTS[10] = { type = "time_signature", label = "CUSTOM", template = "{timesig}", font = "auto" }
CARD_DEFAULTS[13] = {
  type = "next_region", label = "CUSTOM", template = "{next_region}",
  font = "auto", span = "4",
}
CARD_DEFAULTS[14] = {
  type = "next_region_countdown", label = "CUSTOM",
  template = "{next_region_countdown}", font = "auto",
}
for _, defaults in ipairs(CARD_DEFAULTS) do
  defaults.show_title = defaults.show_title ~= false
  Runtime.add_card_field_defaults(defaults)
end

local settings
do
local function ext_color(key, fallback)
  local value = ext_string(key, "")
  local hex = value:match("^#?(%x%x%x%x%x%x%x%x)$")
  if not hex then return fallback end
  return tonumber(hex, 16) or fallback
end

settings = {
  scope = ext_string("scope", "project"),
  units = ext_string("units", "time"),
  time_format = ext_string("time_format", "minsec"),
  hide_tempo_without_grid = ext_bool("hide_tempo_without_grid", true),
  show_main_clock = ext_bool("show_main_clock", true),
  main_clock_size = ext_string("main_clock_size", "huge"),
  show_progress = ext_bool("show_progress", true),
  active_face = Store.root.faces.active,
  face_user_ids = Store.root.faces.user_ids,
  face_user_next = Store.root.faces.user_next,
  meter_face_source_kind = ext_string("meter_face_source_kind", ""),
  meter_face_track_guid = ext_string("meter_face_track_guid", ""),
  meter_face_fx_guid = ext_string("meter_face_fx_guid", ""),
  meter_face_source_ordinal = ext_number("meter_face_source_ordinal", 1),
  meter_face_last_source_name = ext_string("meter_face_last_source_name", ""),
  card_rows = ext_number("card_rows", 3),
  card_row_counts = {},
  card_row_sizes = {},
  cue_warning_seconds = ext_number("cue_warning_seconds", 10),
  gap_mode = ext_string("gap_mode", "blank"),
  visual_click = ext_bool("visual_click", false),
  click_activation = ext_string("click_activation", "playing"),
  click_decay_ms = ext_number("click_decay_ms", 130),
  click_intensity = ext_number("click_intensity", 0.75),
  always_on_top = ext_bool("always_on_top", false),
  keyboard_shortcuts_enabled = ext_bool("keyboard_shortcuts_enabled", true),
  fit_window_to_content = ext_bool("fit_window_to_content", true),
  dock_id = ext_number("dock_id", 0),
  presentation_vertical_position = ext_number("presentation_vertical_position", 0.5),
  offset_unit = ext_string("offset_unit", "ms"),
  offset_value = ext_number("offset_value", 0),
  regular_font = ext_string("regular_font", DEFAULT_APPEARANCE.regular_font),
  mono_font = ext_string("mono_font", DEFAULT_APPEARANCE.mono_font),
  regular_weight = ext_string("regular_weight", DEFAULT_APPEARANCE.regular_weight),
  mono_weight = ext_string("mono_weight", DEFAULT_APPEARANCE.mono_weight),
  regular_size = ext_number("regular_size", DEFAULT_APPEARANCE.regular_size),
  mono_size = ext_number("mono_size", DEFAULT_APPEARANCE.mono_size),
  theme_mode = ext_string("theme_mode", "midnight"),
  theme_background = ext_color("theme_background", DEFAULT_APPEARANCE.background),
  theme_text = ext_color("theme_text", DEFAULT_APPEARANCE.text),
  theme_highlight = ext_color("theme_highlight", DEFAULT_APPEARANCE.highlight),
  background_gradient_strength = ext_number(
    "background_gradient_strength", DEFAULT_APPEARANCE.background_gradient_strength),
  card_background_opacity = ext_number(
    "card_background_opacity", DEFAULT_APPEARANCE.card_background_opacity),
  background_image_path = ext_string(
    "background_image_path", DEFAULT_APPEARANCE.background_image_path),
  background_image_opacity = ext_number(
    "background_image_opacity", DEFAULT_APPEARANCE.background_image_opacity),
  card_alignment = ext_string("card_alignment", DEFAULT_APPEARANCE.card_alignment),
  fade_controls = ext_bool("fade_controls", true),
  recording_background_enabled = ext_bool(
    "recording_background_enabled", DEFAULT_APPEARANCE.recording_background_enabled),
  recording_background = ext_color(
    "recording_background", DEFAULT_APPEARANCE.recording_background),
  cards = {},
  detached_cards = {},
  detached_by_index = {},
  detached_next = Store.root.detached_next,
}

for row = 1, MAX_CARD_ROWS do
  local fallback_counts = { 1, 4, 2, 1 }
  settings.card_row_counts[row] = ext_number(
    "card_row" .. row .. "_count", fallback_counts[row] or 1)
  local fallback_sizes = { "large", "medium", "medium", "medium" }
  settings.card_row_sizes[row] = ext_string(
    "card_row" .. row .. "_size", fallback_sizes[row] or "medium")
end

local function read_card(prefix, defaults)
  local card = {
    type = ext_string(prefix .. "_type", defaults.type),
    label = ext_string(prefix .. "_label", defaults.label),
    template = ext_string(prefix .. "_template", defaults.template),
    font = ext_string(prefix .. "_font", defaults.font),
    scroll = ext_bool(prefix .. "_scroll", defaults.scroll == true),
    show_title = ext_bool(prefix .. "_show_title", defaults.show_title ~= false),
    align = ext_string(prefix .. "_align", defaults.align or "default"),
    span = normalize_card_span(ext_string(prefix .. "_span", defaults.span or "auto")),
  }
  for _, field in ipairs(METER_CARD_FIELDS) do
    local fallback = defaults[field.key]
    local value
    if field.kind == "boolean" then
      value = ext_bool(prefix .. "_" .. field.key, fallback == true)
    elseif field.kind == "number" then
      value = ext_number(prefix .. "_" .. field.key, fallback)
    else
      value = ext_string(prefix .. "_" .. field.key, fallback)
    end
    card[field.key] = normalize_meter_field(field, value)
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    card[field.key] = Runtime.normalize_action_field(
      ext_string(prefix .. "_" .. field.key, defaults[field.key]), field.default)
  end
  return card
end

for index, defaults in ipairs(CARD_DEFAULTS) do
  settings.cards[index] = read_card("card_" .. index, defaults)
end
end

if settings.scope ~= "project" and settings.scope ~= "region" and settings.scope ~= "selection" then
  settings.scope = "project"
end
if settings.units ~= "time" and settings.units ~= "beats" then settings.units = "time" end
if not Runtime.clock_sizes[settings.main_clock_size] then settings.main_clock_size = "huge" end
local valid_time_formats = {
  minsec = true, hms = true, timecode = true, frames = true, seconds = true, samples = true,
}
if not valid_time_formats[settings.time_format] then settings.time_format = "minsec" end
if settings.gap_mode ~= "blank" and settings.gap_mode ~= "next"
    and settings.gap_mode ~= "overtime" then settings.gap_mode = "blank" end
if settings.click_activation ~= "playing" and settings.click_activation ~= "grid"
    and settings.click_activation ~= "metronome" then settings.click_activation = "playing" end
settings.cue_warning_seconds = math.max(0, math.min(300, settings.cue_warning_seconds))
settings.click_decay_ms = math.max(60, math.min(300, settings.click_decay_ms))
settings.click_intensity = math.max(0.25, math.min(1.0, settings.click_intensity))
settings.dock_id = math.max(-16, math.min(0, math.floor(settings.dock_id)))
settings.presentation_vertical_position = math.max(0, math.min(1,
  settings.presentation_vertical_position or 0.5))
settings.card_rows = math.max(0, math.min(MAX_CARD_ROWS, math.floor(settings.card_rows + 0.5)))
if settings.meter_face_source_kind ~= "monitoring"
    and settings.meter_face_source_kind ~= "master"
    and settings.meter_face_source_kind ~= "track" then
  settings.meter_face_source_kind = ""
end
settings.meter_face_source_ordinal = math.max(1,
  math.min(64, math.floor((tonumber(settings.meter_face_source_ordinal) or 1) + 0.5)))
for row = 1, MAX_CARD_ROWS do
  settings.card_row_counts[row] = math.max(1, math.min(CARDS_PER_ROW,
    math.floor((tonumber(settings.card_row_counts[row]) or 1) + 0.5)))
  if not ROW_SIZE_OPTIONS[settings.card_row_sizes[row]] then
    settings.card_row_sizes[row] = row == 1 and "large" or "medium"
  end
end
if not THEME_PRESETS[settings.theme_mode]
    and settings.theme_mode ~= "custom" then settings.theme_mode = "midnight" end
if settings.offset_unit ~= "ms" and settings.offset_unit ~= "samples" then settings.offset_unit = "ms" end
if settings.regular_font == "" then settings.regular_font = DEFAULT_APPEARANCE.regular_font end
if settings.mono_font == "" then settings.mono_font = DEFAULT_APPEARANCE.mono_font end
if settings.regular_weight ~= "regular" and settings.regular_weight ~= "bold" then
  settings.regular_weight = DEFAULT_APPEARANCE.regular_weight
end
if settings.mono_weight ~= "regular" and settings.mono_weight ~= "bold" then
  settings.mono_weight = DEFAULT_APPEARANCE.mono_weight
end
settings.regular_size = math.max(0.6, math.min(1.6, settings.regular_size))
settings.mono_size = math.max(0.5, math.min(2.0, settings.mono_size))
settings.background_gradient_strength = math.max(0, math.min(1,
  settings.background_gradient_strength or DEFAULT_APPEARANCE.background_gradient_strength))
settings.card_background_opacity = math.max(0, math.min(1,
  settings.card_background_opacity or DEFAULT_APPEARANCE.card_background_opacity))
settings.background_image_opacity = math.max(0,
  math.min(0.5, settings.background_image_opacity or DEFAULT_APPEARANCE.background_image_opacity))
if settings.card_alignment ~= "left" and settings.card_alignment ~= "center"
    and settings.card_alignment ~= "right" then
  settings.card_alignment = DEFAULT_APPEARANCE.card_alignment
end
for index, card in ipairs(settings.cards) do
  local defaults = CARD_DEFAULTS[index]
  if not CARD_TYPE_BY_ID[card.type] then card.type = defaults.type end
  if card.label == "" then card.label = defaults.label end
  if card.font ~= "auto" and card.font ~= "regular" and card.font ~= "mono" then
    card.font = defaults.font
  end
  if card.align ~= "default" and card.align ~= "left"
      and card.align ~= "center" and card.align ~= "right" then
    card.align = defaults.align or "default"
  end
  card.show_title = card.show_title ~= false
  card.span = normalize_card_span(card.span)
  for _, field in ipairs(METER_CARD_FIELDS) do
    card[field.key] = normalize_meter_field(field, card[field.key])
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    card[field.key] = Runtime.normalize_action_field(card[field.key], field.default)
  end
end

function Runtime.normalize_detached_card(raw, fallback_type)
  raw = type(raw) == "table" and raw or {}
  local card_type = CARD_TYPE_BY_ID[raw.type] and raw.type
    or (CARD_TYPE_BY_ID[fallback_type] and fallback_type or "position")
  local card = {
    type = card_type,
    label = type(raw.label) == "string" and raw.label ~= "" and raw.label or "CUSTOM",
    template = type(raw.template) == "string" and raw.template or "",
    font = (raw.font == "regular" or raw.font == "mono") and raw.font or "auto",
    scroll = raw.scroll == true,
    show_title = raw.show_title ~= false,
    align = (raw.align == "left" or raw.align == "center" or raw.align == "right")
      and raw.align or "default",
    span = normalize_card_span(raw.span or "auto"),
  }
  for _, field in ipairs(METER_CARD_FIELDS) do
    card[field.key] = normalize_meter_field(field,
      raw[field.key] == nil and field.default or raw[field.key])
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    card[field.key] = Runtime.normalize_action_field(raw[field.key], field.default)
  end
  return card
end

function Runtime.load_detached_cards()
  local normalized, seen, highest = Json.array(), {}, 0
  for _, raw in ipairs(Store.root.detached_cards or {}) do
    if #normalized >= 32 then break end
    local id = math.floor(tonumber(raw and raw.id) or 0)
    if id < 1 or seen[id] then
      id = math.max(1, settings.detached_next or 1)
      while seen[id] do id = id + 1 end
    end
    seen[id], highest = true, math.max(highest, id)
    local card = Runtime.normalize_detached_card(raw.card, "position")
    local defaults = Runtime.normalize_detached_card(raw.defaults or raw.card, card.type)
    local entry = {
      id = id,
      open = raw.open ~= false,
      x = tonumber(raw.x), y = tonumber(raw.y),
      w = math.max(240, math.min(2160, tonumber(raw.w) or 560)),
      h = math.max(110, math.min(2160, tonumber(raw.h) or 220)),
      card = card,
      defaults = defaults,
    }
    normalized[#normalized + 1] = entry
    settings.detached_by_index[-id] = entry
    settings.cards[-id] = card
  end
  settings.detached_cards = normalized
  settings.detached_next = math.max(highest + 1, tonumber(settings.detached_next) or 1)
  Store.root.detached_cards = normalized
  Store.root.detached_next = settings.detached_next
  Runtime.detached = { applied = {}, render_focus_prior = false, pending = nil }
end

Runtime.load_detached_cards()

function Runtime.each_active_card(callback)
  for row = 1, settings.card_rows do
    for column = 1, settings.card_row_counts[row] do
      local index = (row - 1) * CARDS_PER_ROW + column
      callback(index, settings.cards[index])
    end
  end
  for _, entry in ipairs(settings.detached_cards) do
    if entry.open then callback(-entry.id, entry.card) end
  end
end
for row = 1, MAX_CARD_ROWS do
  local used, count = 0, settings.card_row_counts[row]
  for column = 1, count do
    local index = (row - 1) * CARDS_PER_ROW + column
    local card = settings.cards[index]
    local remaining_cards = count - column
    local maximum = math.max(1, CARDS_PER_ROW - used - remaining_cards)
    local fixed = tonumber(card.span)
    if fixed then card.span = tostring(math.min(fixed, maximum)) end
    used = used + (tonumber(card.span) or 1)
  end
end

local function save_string(key, value)
  Store.root.settings[key] = tostring(value)
  -- Persist only inside the disposable portable-test override so the native
  -- harness can inspect live changes through reaper-extstate.ini. The runner
  -- snapshots and restores every touched key around the matrix.
  if Store.test_override then R.SetExtState(EXT, key, tostring(value), true) end
  Store.mark_dirty()
end

local function save_bool(key, value)
  save_string(key, value and "1" or "0")
end

local function save_color(key, value)
  save_string(key, string.format("%08X", value & 0xFFFFFFFF))
end

local function save_all_settings()
  save_string("scope", settings.scope)
  save_string("units", settings.units)
  save_string("time_format", settings.time_format)
  save_bool("hide_tempo_without_grid", settings.hide_tempo_without_grid)
  save_bool("show_main_clock", settings.show_main_clock)
  save_string("main_clock_size", settings.main_clock_size)
  save_bool("show_progress", settings.show_progress)
  save_string("meter_face_source_kind", settings.meter_face_source_kind)
  save_string("meter_face_track_guid", settings.meter_face_track_guid)
  save_string("meter_face_fx_guid", settings.meter_face_fx_guid)
  save_string("meter_face_source_ordinal", settings.meter_face_source_ordinal)
  save_string("meter_face_last_source_name", settings.meter_face_last_source_name)
  save_string("card_rows", settings.card_rows)
  for row = 1, MAX_CARD_ROWS do
    save_string("card_row" .. row .. "_count", settings.card_row_counts[row])
    save_string("card_row" .. row .. "_size", settings.card_row_sizes[row])
  end
  save_string("cue_warning_seconds", string.format("%.3f", settings.cue_warning_seconds))
  save_string("gap_mode", settings.gap_mode)
  save_bool("visual_click", settings.visual_click)
  save_string("click_activation", settings.click_activation)
  save_string("click_decay_ms", string.format("%.3f", settings.click_decay_ms))
  save_string("click_intensity", string.format("%.4f", settings.click_intensity))
  save_bool("always_on_top", settings.always_on_top)
  save_bool("keyboard_shortcuts_enabled", settings.keyboard_shortcuts_enabled)
  save_bool("fit_window_to_content", settings.fit_window_to_content)
  save_string("dock_id", settings.dock_id)
  save_string("presentation_vertical_position",
    string.format("%.4f", settings.presentation_vertical_position))
  save_string("offset_unit", settings.offset_unit)
  save_string("offset_value", string.format("%.12f", settings.offset_value))
  save_string("regular_font", settings.regular_font)
  save_string("mono_font", settings.mono_font)
  save_string("regular_weight", settings.regular_weight)
  save_string("mono_weight", settings.mono_weight)
  save_string("regular_size", string.format("%.4f", settings.regular_size))
  save_string("mono_size", string.format("%.4f", settings.mono_size))
  save_string("theme_mode", settings.theme_mode)
  save_color("theme_background", settings.theme_background)
  save_color("theme_text", settings.theme_text)
  save_color("theme_highlight", settings.theme_highlight)
  save_string("background_gradient_strength",
    string.format("%.4f", settings.background_gradient_strength))
  save_string("card_background_opacity",
    string.format("%.4f", settings.card_background_opacity))
  save_string("background_image_path", settings.background_image_path)
  save_string("background_image_opacity", string.format("%.4f", settings.background_image_opacity))
  save_string("card_alignment", settings.card_alignment)
  save_bool("fade_controls", settings.fade_controls)
  save_bool("recording_background_enabled", settings.recording_background_enabled)
  save_color("recording_background", settings.recording_background)
  for index, card in ipairs(settings.cards) do
    save_string("card_" .. index .. "_type", card.type)
    save_string("card_" .. index .. "_label", card.label)
    save_string("card_" .. index .. "_template", card.template)
    save_string("card_" .. index .. "_font", card.font)
    save_bool("card_" .. index .. "_scroll", card.scroll)
    save_bool("card_" .. index .. "_show_title", card.show_title ~= false)
    save_string("card_" .. index .. "_align", card.align or "default")
    save_string("card_" .. index .. "_span", card.span or "auto")
    for _, field in ipairs(METER_CARD_FIELDS) do
      local key, value = "card_" .. index .. "_" .. field.key, card[field.key]
      if field.kind == "boolean" then save_bool(key, value) else save_string(key, value) end
    end
    for _, field in ipairs(Runtime.action_card_fields) do
      save_string("card_" .. index .. "_" .. field.key, card[field.key])
    end
  end
end

-- -----------------------------------------------------------------------------
-- ReaImGui resources
-- -----------------------------------------------------------------------------

local ctx = R.ImGui_CreateContext(TITLE, R.ImGui_ConfigFlags_DockingEnable())

-- Images are loaded only after the user chooses one. The cache is attached to
-- the current ReaImGui context, replaced when the path changes, and never
-- re-decoded during the frame loop.
local background_image_cache = {
  path = nil,
  image = nil,
  width = 0,
  height = 0,
  error = nil,
  attempted = false,
  drawn = false,
}
local background_image_status = ""

local function background_image_filename(path)
  if not path or path == "" then return "No image selected" end
  return path:match("([^\\/]+)$") or path
end

local function is_supported_background_image(path)
  local extension = tostring(path or ""):match("%.([^%.\\/]+)$")
  extension = extension and extension:lower() or ""
  return extension == "png" or extension == "jpg" or extension == "jpeg"
end

local function invalidate_background_image()
  if background_image_cache.image then
    local ok, valid = pcall(R.ImGui_ValidatePtr,
      background_image_cache.image, "ImGui_Image*")
    if ok and valid then pcall(R.ImGui_Detach, ctx, background_image_cache.image) end
  end
  background_image_cache.path = nil
  background_image_cache.image = nil
  background_image_cache.width = 0
  background_image_cache.height = 0
  background_image_cache.error = nil
  background_image_cache.attempted = false
  background_image_cache.drawn = false
end

local function get_background_image()
  local path = settings.background_image_path or ""
  if path == "" then return nil end
  if background_image_cache.path ~= path then
    invalidate_background_image()
    background_image_cache.path = path
  end

  if background_image_cache.image then
    local ok, valid = pcall(R.ImGui_ValidatePtr,
      background_image_cache.image, "ImGui_Image*")
    if ok and valid then
      return background_image_cache.image,
        background_image_cache.width, background_image_cache.height
    end
    background_image_cache.image = nil
    background_image_cache.attempted = false
  end
  if background_image_cache.attempted then return nil end
  background_image_cache.attempted = true

  if not is_supported_background_image(path) then
    background_image_cache.error = "Only PNG and JPEG images are supported."
    return nil
  end
  if not R.file_exists(path) then
    background_image_cache.error = "The selected image could not be found."
    return nil
  end

  local created, image_or_error = pcall(R.ImGui_CreateImage, path)
  if not created or not image_or_error then
    background_image_cache.error = "ReaImGui could not load this image: "
      .. tostring(image_or_error or "unknown image error")
    return nil
  end
  local size_ok, width, height = pcall(R.ImGui_Image_GetSize, image_or_error)
  if not size_ok or not width or not height or width <= 0 or height <= 0 then
    background_image_cache.error = "The selected image has invalid dimensions."
    return nil
  end

  R.ImGui_Attach(ctx, image_or_error)
  background_image_cache.image = image_or_error
  background_image_cache.width = width
  background_image_cache.height = height
  background_image_cache.error = nil
  return image_or_error, width, height
end

local font_asset_dir = Runtime.resources_dir
local font_scan_roots = { font_asset_dir }
local font_scan_root_keys = {
  [Runtime.is_windows and font_asset_dir:lower() or font_asset_dir] = true,
}

local function add_font_scan_root(path)
  if not path or path == "" then return end
  local key = Runtime.is_windows and path:lower() or path
  if font_scan_root_keys[key] then return end
  font_scan_root_keys[key] = true
  font_scan_roots[#font_scan_roots + 1] = path
end

local font_file_candidates = {
  ["Roboto"] = {
    regular = { join_path(font_asset_dir, "Roboto-Regular.ttf") },
    bold = { join_path(font_asset_dir, "Roboto-Bold.ttf") },
  },
  ["Chivo Mono"] = {
    regular = { join_path(font_asset_dir, "ChivoMono-Regular.ttf") },
  },
  ["JetBrains Mono"] = { regular = {}, bold = {} },
}

local function add_font_candidate(family, style, path)
  if not path or path == "" then return end
  font_file_candidates[family] = font_file_candidates[family] or {}
  font_file_candidates[family][style] = font_file_candidates[family][style] or {}
  table.insert(font_file_candidates[family][style], path)
end

local home_dir = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

if Runtime.is_windows then
  local local_app_data = os.getenv("LOCALAPPDATA") or ""
  local user_font_dir = local_app_data ~= ""
    and join_path(join_path(local_app_data, "Microsoft"), join_path("Windows", "Fonts")) or ""
  local windows_font_dir = join_path(os.getenv("WINDIR") or "C:\\Windows", "Fonts")

  add_font_scan_root(user_font_dir)
  add_font_scan_root(windows_font_dir)

  if user_font_dir ~= "" then
    add_font_candidate("Roboto", "regular", join_path(user_font_dir, "Roboto-VariableFont_wdth,wght.ttf"))
    add_font_candidate("Roboto", "regular", join_path(user_font_dir, "Roboto-Regular.ttf"))
    add_font_candidate("Roboto", "bold", join_path(user_font_dir, "Roboto-Bold.ttf"))
    add_font_candidate("Chivo Mono", "regular", join_path(user_font_dir, "ChivoMono-Regular.ttf"))
    add_font_candidate("JetBrains Mono", "regular", join_path(user_font_dir, "JetBrainsMono-VariableFont_wght.ttf"))
    add_font_candidate("JetBrains Mono", "regular", join_path(user_font_dir, "JetBrainsMono-Regular.ttf"))
    add_font_candidate("JetBrains Mono", "bold", join_path(user_font_dir, "JetBrainsMono-Bold.ttf"))
  end

  font_file_candidates["Segoe UI"] = {
    regular = { join_path(windows_font_dir, "segoeui.ttf") },
    bold = { join_path(windows_font_dir, "segoeuib.ttf") },
  }
  font_file_candidates["Arial"] = {
    regular = { join_path(windows_font_dir, "arial.ttf") },
    bold = { join_path(windows_font_dir, "arialbd.ttf") },
  }
  font_file_candidates["Tahoma"] = {
    regular = { join_path(windows_font_dir, "tahoma.ttf") },
    bold = { join_path(windows_font_dir, "tahomabd.ttf") },
  }
  font_file_candidates["Consolas"] = {
    regular = { join_path(windows_font_dir, "consola.ttf") },
    bold = { join_path(windows_font_dir, "consolab.ttf") },
  }
  font_file_candidates["Courier New"] = {
    regular = { join_path(windows_font_dir, "cour.ttf") },
    bold = { join_path(windows_font_dir, "courbd.ttf") },
  }
elseif Runtime.is_macos then
  local user_font_dir = home_dir ~= "" and join_path(join_path(home_dir, "Library"), "Fonts") or ""
  add_font_scan_root(user_font_dir)
  add_font_scan_root("/Library/Fonts")
  add_font_scan_root("/System/Library/Fonts")
  if user_font_dir ~= "" then
    for _, name in ipairs({ "Roboto-Regular.ttf", "Roboto[wdth,wght].ttf" }) do
      add_font_candidate("Roboto", "regular", join_path(user_font_dir, name))
    end
    add_font_candidate("Roboto", "bold", join_path(user_font_dir, "Roboto-Bold.ttf"))
    add_font_candidate("Chivo Mono", "regular", join_path(user_font_dir, "ChivoMono-Regular.ttf"))
    add_font_candidate("JetBrains Mono", "regular", join_path(user_font_dir, "JetBrainsMono-Regular.ttf"))
    add_font_candidate("JetBrains Mono", "bold", join_path(user_font_dir, "JetBrainsMono-Bold.ttf"))
  end
  font_file_candidates["Helvetica Neue"] = {
    regular = { "/System/Library/Fonts/HelveticaNeue.ttc" },
  }
  font_file_candidates["Menlo"] = {
    regular = { "/System/Library/Fonts/Menlo.ttc" },
  }
  font_file_candidates["Monaco"] = {
    regular = { "/System/Library/Fonts/Monaco.ttf" },
  }
else
  local local_font_dir = home_dir ~= "" and join_path(join_path(join_path(home_dir, ".local"), "share"), "fonts") or ""
  local legacy_font_dir = home_dir ~= "" and join_path(home_dir, ".fonts") or ""
  add_font_scan_root(local_font_dir)
  add_font_scan_root(legacy_font_dir)
  add_font_scan_root("/usr/local/share/fonts")
  add_font_scan_root("/usr/share/fonts")
  for _, dir in ipairs({ local_font_dir, legacy_font_dir, "/usr/share/fonts/truetype/roboto" }) do
    if dir ~= "" then
      add_font_candidate("Roboto", "regular", join_path(dir, "Roboto-Regular.ttf"))
      add_font_candidate("Roboto", "bold", join_path(dir, "Roboto-Bold.ttf"))
      add_font_candidate("JetBrains Mono", "regular", join_path(dir, "JetBrainsMono-Regular.ttf"))
      add_font_candidate("JetBrains Mono", "bold", join_path(dir, "JetBrainsMono-Bold.ttf"))
    end
  end
  font_file_candidates["DejaVu Sans"] = {
    regular = { "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" },
    bold = { "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" },
  }
  font_file_candidates["DejaVu Sans Mono"] = {
    regular = { "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf" },
    bold = { "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf" },
  }
  font_file_candidates["Liberation Sans"] = {
    regular = { "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf" },
    bold = { "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" },
  }
  font_file_candidates["Liberation Mono"] = {
    regular = { "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf" },
    bold = { "/usr/share/fonts/truetype/liberation2/LiberationMono-Bold.ttf" },
  }
end

local function create_font(paths, family, bold, native_weight)
  local flags = 0
  if bold and not native_weight and R.ImGui_FontFlags_Bold then
    flags = R.ImGui_FontFlags_Bold()
  end
  if type(paths) == "string" then paths = { paths } end
  for _, path in ipairs(paths or {}) do
    if R.ImGui_CreateFontFromFile and path ~= "" and R.file_exists(path) then
      local ok, font = pcall(R.ImGui_CreateFontFromFile, path, 0, flags)
      if ok and font then return font end
    end
  end
  flags = 0
  if bold and R.ImGui_FontFlags_Bold then flags = R.ImGui_FontFlags_Bold() end
  local ok, font = pcall(R.ImGui_CreateFont, family ~= "" and family or "sans-serif", flags)
  if ok and font then return font end
  return R.ImGui_CreateFont("sans-serif", flags)
end

local function looks_like_font_file(value)
  return value:lower():match("%.tt[fc]$") or value:lower():match("%.otf$")
end

local function source_font_candidates(source, bold)
  if R.file_exists(source) then return { source }, false end
  local preset = font_file_candidates[source]
  if not preset then return {}, false end
  if bold and preset.bold and #preset.bold > 0 then return preset.bold, true end
  return preset.regular or {}, false
end

local function create_font_from_source(source, bold, fallback)
  if looks_like_font_file(source) and not R.file_exists(source) then source = fallback end
  local candidates, native_weight = source_font_candidates(source, bold)
  return create_font(candidates, source, bold, native_weight)
end

local icon_font_path = join_path(font_asset_dir, "lucide.ttf")
local font_regular, font_bold, font_mono, font_icon
local font_reload_pending = false
local font_status = ""
local icon_font_status = ""

local function load_icon_font()
  if not R.file_exists(icon_font_path) then
    icon_font_status = "The bundled icon font is missing. ReaClock is using text and drawn control fallbacks."
    return false
  end
  local ok, font = pcall(R.ImGui_CreateFontFromFile, icon_font_path, 0, 0)
  if not ok or not font then
    icon_font_status = "The bundled icon font could not be loaded. ReaClock is using text and drawn control fallbacks."
    return false
  end
  R.ImGui_Attach(ctx, font)
  font_icon = font
  return true
end

-- Lucide Static 1.24.0 glyphs from the bundled, ReaClock-specific subset.
-- Private Use Area codepoints are pinned to the exact distributed font so
-- user font choices and platform fonts can never change the icon mapping.
local function icon_utf8(codepoint)
  return string.char(
    0xE0 | (codepoint >> 12),
    0x80 | ((codepoint >> 6) & 0x3F),
    0x80 | (codepoint & 0x3F))
end

local ICON = {
  CHECK = icon_utf8(0xE06C),
  CIRCLE_PLUS = icon_utf8(0xE081),
  CIRCLE_HELP = icon_utf8(0xE082),
  GRIP_VERTICAL = icon_utf8(0xE0EB),
  MAXIMIZE = icon_utf8(0xE112),
  MINIMIZE = icon_utf8(0xE11A),
  MONITOR = icon_utf8(0xE11D),
  PLUS = icon_utf8(0xE13D),
  ROTATE_CCW = icon_utf8(0xE148),
  SETTINGS = icon_utf8(0xE154),
  TRASH = icon_utf8(0xE18E),
  PENCIL = icon_utf8(0xE1F9),
  GRIP = icon_utf8(0xE3B1),
  AUDIO_LINES = icon_utf8(0xE55A),
}

local function reload_fonts()
  font_reload_pending = false
  local ok, err = pcall(function()
    local old_fonts = { font_regular, font_bold, font_mono }
    local regular = create_font_from_source(
      settings.regular_font, settings.regular_weight == "bold",
      DEFAULT_APPEARANCE.regular_font)
    local bold = create_font_from_source(
      settings.regular_font, true, DEFAULT_APPEARANCE.regular_font)
    local mono = create_font_from_source(
      settings.mono_font, settings.mono_weight == "bold",
      DEFAULT_APPEARANCE.mono_font)
    R.ImGui_Attach(ctx, regular)
    R.ImGui_Attach(ctx, bold)
    R.ImGui_Attach(ctx, mono)
    font_regular, font_bold, font_mono = regular, bold, mono
    if R.ImGui_Detach then
      local detached = {}
      for _, old_font in ipairs(old_fonts) do
        if old_font and not detached[old_font] then
          detached[old_font] = true
          pcall(R.ImGui_Detach, ctx, old_font)
        end
      end
    end
  end)
  if not ok then
    font_status = "Font could not be loaded: " .. tostring(err)
    return false
  end
  return true
end

load_icon_font()
reload_fonts()

local function color_channels(color)
  return (color >> 24) & 0xFF, (color >> 16) & 0xFF,
    (color >> 8) & 0xFF, color & 0xFF
end

local function rgba_to_argb(color)
  return ((color >> 8) & 0x00FFFFFF) | ((color << 24) & 0xFF000000)
end

local function argb_to_rgba(color)
  return ((color << 8) & 0xFFFFFF00) | ((color >> 24) & 0xFF)
end

local function pack_color(r, g, b, a)
  return ((math.floor(r + 0.5) & 0xFF) << 24)
    | ((math.floor(g + 0.5) & 0xFF) << 16)
    | ((math.floor(b + 0.5) & 0xFF) << 8)
    | (math.floor(a + 0.5) & 0xFF)
end

local function mix_color(from, to, amount)
  local fr, fg, fb, fa = color_channels(from)
  local tr, tg, tb, ta = color_channels(to)
  return pack_color(fr + (tr - fr) * amount, fg + (tg - fg) * amount,
    fb + (tb - fb) * amount, fa + (ta - fa) * amount)
end

local function with_alpha(color, alpha)
  local r, g, b = color_channels(color)
  return pack_color(r, g, b, math.max(0, math.min(255, alpha or 255)))
end

local function srgb_component(value)
  value = value / 255
  if value <= 0.04045 then return value / 12.92 end
  return ((value + 0.055) / 1.055) ^ 2.4
end

local function color_luminance(color)
  local r, g, b = color_channels(color)
  return 0.2126 * srgb_component(r) + 0.7152 * srgb_component(g)
    + 0.0722 * srgb_component(b)
end

local function contrast_ratio(a, b)
  local la, lb = color_luminance(a), color_luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function contrast_layer(base, amount)
  local target = color_luminance(base) > 0.45 and 0x000000FF or 0xFFFFFFFF
  return mix_color(base, target, amount)
end

local function desaturate_color(color, amount)
  local r, g, b = color_channels(color)
  local gray = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return mix_color(color, pack_color(gray, gray, gray, 255), amount)
end

local function readable_on(color)
  local dark, light = 0x0D0D0FFF, 0xF5F6F7FF
  if contrast_ratio(dark, color) >= contrast_ratio(light, color) then return dark end
  return light
end

local C = {}

function C.lift_color(color, red, green, blue)
  local r, g, b, a = color_channels(color)
  return pack_color(math.min(255, r + red), math.min(255, g + green),
    math.min(255, b + blue), a)
end

function C.minimum_contrast(color, backgrounds)
  local result = math.huge
  for _, background in ipairs(backgrounds) do
    result = math.min(result, contrast_ratio(color, background))
  end
  return result
end

function C.ensure_text_contrast(color, backgrounds, minimum)
  minimum = minimum or 4.5
  if C.minimum_contrast(color, backgrounds) >= minimum then return color end
  local dark, light = 0x0D0D0FFF, 0xF5F6F7FF
  local target = C.minimum_contrast(dark, backgrounds)
      >= C.minimum_contrast(light, backgrounds) and dark or light
  local low, high = 0, 1
  for _ = 1, 14 do
    local middle = (low + high) * 0.5
    if C.minimum_contrast(mix_color(color, target, middle), backgrounds) >= minimum then
      high = middle
    else
      low = middle
    end
  end
  return mix_color(color, target, high)
end

function C.ensure_contrast_against(color, against, minimum)
  if contrast_ratio(color, against) >= minimum then return color end
  local target = color_luminance(against) > 0.45 and 0x000000FF or 0xFFFFFFFF
  local low, high = 0, 1
  for _ = 1, 14 do
    local middle = (low + high) * 0.5
    if contrast_ratio(mix_color(color, target, middle), against) >= minimum then
      high = middle
    else
      low = middle
    end
  end
  return mix_color(color, target, high)
end

local palette_rebuild_pending = false
local function rebuild_palette()
  local function build(surface, text, highlight, use_default_toggle, style)
    style = style or {}
    local light_surface = color_luminance(surface) > 0.45
    local derived_tile = contrast_layer(surface, light_surface and 0.07 or 0.04)
    local derived_border = contrast_layer(surface, 0.10)
    local tint = style.secondary_accent or 0xFFFFFFFF
    local tile = style.card or derived_tile
    local palette = {
      surface = surface,
      gradient_tint = tint,
      gradient_top_amount = style.secondary_accent and 0.055 or 0.045,
      outer = style.border and mix_color(surface, style.border, 0.55)
        or contrast_layer(surface, 0.08),
      tile = tile,
      tile_top = mix_color(tile, tint, style.secondary_accent and 0.04 or 0.03),
      tile_bottom = mix_color(tile, 0x000000FF, 0.045),
      border = style.border or derived_border,
      progress_track = style.progress_track or contrast_layer(surface, 0.075),
      ink = text,
      accent = highlight,
      accent_secondary = style.secondary_accent or mix_color(highlight, text, 0.32),
    }
    local settings_body = contrast_layer(surface, 0.025)
    local settings_card = light_surface and C.lift_color(surface, 5, 8, 8)
      or contrast_layer(surface, 0.052)
    local settings_control = light_surface and C.lift_color(tile, 2, 4, 5)
      or contrast_layer(tile, 0.035)
    local settings_text_surfaces = { settings_body, settings_card, settings_control }
    palette.accent_text = C.ensure_text_contrast(palette.accent,
      settings_text_surfaces, 4.75)
    palette.accent_secondary_text = C.ensure_text_contrast(palette.accent_secondary,
      settings_text_surfaces, 4.75)
    palette.secondary = mix_color(surface, palette.ink, 0.84)
    palette.muted = style.label_color or mix_color(surface, palette.ink, 0.62)
    palette.accent_hover = contrast_layer(palette.accent, 0.15)
    palette.accent_active = mix_color(palette.accent, surface, 0.24)
    if style.control then
      palette.toggle_selected = style.control
    elseif use_default_toggle then
      palette.toggle_selected = 0x668093FF
    else
      palette.toggle_selected = desaturate_color(palette.accent, 0.38)
    end
    palette.toggle_text = readable_on(palette.toggle_selected)
    local toggle_target = palette.toggle_text == 0x0D0D0FFF
      and 0xFFFFFFFF or 0x000000FF
    palette.toggle_selected_hover = C.ensure_contrast_against(
      mix_color(palette.toggle_selected, toggle_target, 0.12), palette.toggle_text, 4.5)
    palette.toggle_selected_active = C.ensure_contrast_against(
      mix_color(palette.toggle_selected, surface, style.control and 0.10 or 0.08),
      palette.toggle_text, 4.5)
    palette.inactive_hover = contrast_layer(surface, 0.10)
    palette.inactive_active = contrast_layer(surface, 0.14)
    palette.danger = color_luminance(surface) > 0.45 and 0xA52D36FF or 0xE07070FF
    palette.recording = color_luminance(surface) > 0.45 and 0xB32832FF or 0xEF626CFF
    return palette
  end

  local preset = THEME_PRESETS[settings.theme_mode]
  local normal = build(settings.theme_background, settings.theme_text,
    settings.theme_highlight,
    settings.theme_mode == "dark" and settings.theme_highlight == THEME_PRESETS.dark.highlight,
    preset)
  normal.card_accents = preset and preset.card_accents or nil
  for key, value in pairs(normal) do C[key] = value end
  if not normal.card_accents then C.card_accents = nil end

  local recording_text = settings.theme_text
  if contrast_ratio(recording_text, settings.recording_background) < 4.5 then
    recording_text = readable_on(settings.recording_background)
  end
  C.recording_palette = build(settings.recording_background, recording_text,
    settings.theme_highlight, false)
end

rebuild_palette()

-- Width remains the stable design unit while height follows the chosen clock
-- and row structure. This preserves proportions without leaving dead space.
local BASE_W = 918
local MIN_WINDOW_W, MIN_WINDOW_H = 360, 70
local edit_mode = false
local function face_layout_metrics()
  -- Chivo Mono's line box contains more empty space above the visible glyphs.
  -- Lift only the rendered clock inside its reserved band so the optical gap
  -- below the controls matches the gap above the progress rail.
  local clock_size = Runtime.clock_sizes[settings.main_clock_size]
    or Runtime.clock_sizes.huge
  local fit = 1
  local reference = Runtime.main_fit_reference
  if settings.show_main_clock and font_mono and reference and reference ~= "" then
    local nominal_size = clock_size.font_size * settings.mono_size
    R.ImGui_PushFont(ctx, font_mono, nominal_size)
    local reference_width = R.ImGui_CalcTextSize(ctx, reference)
    R.ImGui_PopFont(ctx)
    if reference_width > 800 then fit = math.max(0.1, 800 / reference_width) end
  end
  local clock_height = math.max(64, clock_size.height * fit)
  local clock_y = edit_mode and 67 or 14
  local layout = {
    clock_y = clock_y,
    clock_text_y = clock_y + clock_size.text_offset * fit,
    clock_h = clock_height,
    clock_font_size = clock_size.font_size,
    progress_h = 7, rows = {},
  }
  local active_rows = {}
  for row = 1, settings.card_rows do
    if edit_mode or not Runtime.row_visible or Runtime.row_visible[row] ~= false then
      active_rows[#active_rows + 1] = row
    end
  end
  local cursor
  if settings.show_main_clock then
    cursor = layout.clock_y + layout.clock_h
  else
    cursor = edit_mode and 57 or 0
  end
  if settings.show_progress then
    layout.progress_y = cursor + (settings.show_main_clock and 12 or 17)
    cursor = layout.progress_y + layout.progress_h
    if #active_rows > 0 then cursor = cursor + 12 end
  elseif #active_rows > 0 then
    cursor = cursor + (settings.show_main_clock and 13 or 17)
  end
  for active_index, row in ipairs(active_rows) do
    local style = ROW_SIZE_OPTIONS[settings.card_row_sizes[row]]
      or ROW_SIZE_OPTIONS.medium
    layout.rows[row] = { y = cursor, height = style.height, style = style }
    cursor = cursor + style.height
    if active_index < #active_rows then cursor = cursor + 8 end
  end
  if edit_mode then
    layout.edit_actions_y = cursor + 14
    layout.utility_y = layout.edit_actions_y
  else
    -- Keep the borderless utility row compact, with matching space above and
    -- below its click targets.
    layout.utility_y = cursor + 6
  end
  cursor = layout.utility_y + 27
  local bottom_inset = edit_mode and 18 or 6
  layout.base_h = math.max(78, cursor + bottom_inset)
  return layout
end
local function current_base_height() return face_layout_metrics().base_h end
local function current_aspect_ratio() return BASE_W / current_base_height() end
local settings_open = false
local settings_tab_request
local detail_editor = {
  open = false,
  kind = nil,
  id = nil,
  focus_requested = false,
  topmost_reassert = 0,
}
local face_dialog = { request = nil, action = nil, input = "", close_request = false }
-- Layout editing is deliberately session-only: opening the clock always starts
-- in its uncluttered performance view, while card order/content remain saved.
local edit_selected_row = 1
local edit_selected_card = 1
local layout_resize_pending = false
local function request_layout_resize() layout_resize_pending = true end
local presentation_mode = false
local presentation_request
local presentation_drag = { active = false, origin_y = nil, target_y = nil }
local main_dock_id = 0
local first_frame = true
local window_chrome_h = 21
local CHROME_MEASURE_EPSILON = 2
local WINDOW_MONITOR_MARGIN = 24
local saved_window = {
  x = ext_number("window_x", nil),
  y = ext_number("window_y", nil),
  w = ext_number("window_w", nil),
  h = ext_number("window_h", nil),
}

local function finite_number(value)
  return type(value) == "number" and value == value
    and value > -math.huge and value < math.huge
end

local function native_pixel(value)
  value = tonumber(value) or 0
  return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function window_work_area(x, y, w, h)
  if not R.my_getViewport then return nil end
  local native_x, native_y = native_pixel(x), native_pixel(y)
  local native_right, native_bottom = native_pixel(x + w), native_pixel(y + h)
  local left, top, right, bottom = R.my_getViewport(
    0, 0, 0, 0, native_x, native_y, native_right, native_bottom, true)
  if not finite_number(left) or not finite_number(top)
      or not finite_number(right) or not finite_number(bottom)
      or right <= left or bottom <= top then
    return nil
  end
  return { left = left, top = top, right = right, bottom = bottom }
end

local function cap_window_rect(x, y, w, h, fit_content)
  local bounds = window_work_area(x, y, w, h)
  if not bounds then return x, y, w, h, false end
  local margin = math.min(WINDOW_MONITOR_MARGIN,
    math.max(0, (bounds.right - bounds.left - MIN_WINDOW_W) * 0.5),
    math.max(0, (bounds.bottom - bounds.top - MIN_WINDOW_H) * 0.5))
  local left, top, right, bottom = bounds.left, bounds.top, bounds.right, bounds.bottom
  local maximum_w = math.max(1, right - left - margin * 2)
  local maximum_h = math.max(1, bottom - top - margin * 2)
  local original_x, original_y, original_w, original_h = x, y, w, h

  w = math.max(math.min(MIN_WINDOW_W, maximum_w), math.min(w, maximum_w))
  if fit_content then
    local aspect = current_aspect_ratio()
    local fitted_h = w / aspect + window_chrome_h
    if fitted_h > maximum_h then
      local fitted_w = math.max(1, (maximum_h - window_chrome_h) * aspect)
      w = math.max(math.min(MIN_WINDOW_W, maximum_w), math.min(w, fitted_w, maximum_w))
      fitted_h = w / aspect + window_chrome_h
    end
    h = math.max(math.min(MIN_WINDOW_H, maximum_h), math.min(fitted_h, maximum_h))
  else
    h = math.max(math.min(MIN_WINDOW_H, maximum_h), math.min(h, maximum_h))
  end

  local max_x = math.max(left, right - w)
  local max_y = math.max(top, bottom - h)
  x, y = math.min(math.max(x, left), max_x), math.min(math.max(y, top), max_y)
  local changed = math.abs(x - original_x) > 0.5 or math.abs(y - original_y) > 0.5
    or math.abs(w - original_w) > 0.5 or math.abs(h - original_h) > 0.5
  return x, y, w, h, changed
end

local has_saved_window = finite_number(saved_window.x) and finite_number(saved_window.y)
  and finite_number(saved_window.w) and finite_number(saved_window.h)
  and saved_window.w >= MIN_WINDOW_W and saved_window.h >= MIN_WINDOW_H
if has_saved_window then
  -- In automatic mode, width is the durable user choice and height belongs to
  -- the active face. Freeform mode restores both dimensions exactly. Either
  -- way, fit stale geometry to the monitor selected by the saved rectangle.
  local original_x, original_y = saved_window.x, saved_window.y
  local original_w, original_h = saved_window.w, saved_window.h
  if settings.fit_window_to_content then
    saved_window.h = saved_window.w / current_aspect_ratio() + window_chrome_h
  end
  local x, y, w, h, changed = cap_window_rect(saved_window.x, saved_window.y,
    saved_window.w, saved_window.h, settings.fit_window_to_content)
  saved_window.x, saved_window.y, saved_window.w, saved_window.h = x, y, w, h
  changed = changed or math.abs(x - original_x) > 0.5 or math.abs(y - original_y) > 0.5
    or math.abs(w - original_w) > 0.5 or math.abs(h - original_h) > 0.5
  if changed then
    save_string("window_x", native_pixel(x))
    save_string("window_y", native_pixel(y))
    save_string("window_w", native_pixel(w))
    save_string("window_h", native_pixel(h))
  end
end
local last_seen_geometry
local last_saved_geometry
local geometry_changed_at = R.time_precise()
local restore_request_w = saved_window.w
local restore_request_h = saved_window.h
local restore_size_pending = false
local restore_size_applied = false
local restore_size_applied_at = -math.huge
local restore_attempts = 0
local window_restore_complete = not has_saved_window

local aspect_constraint = R.ImGui_CreateFunctionFromEEL([[
  DesiredSize.y = floor(DesiredSize.x / aspect_ratio + chrome_h + 0.5);
]])
R.ImGui_Attach(ctx, aspect_constraint)
R.ImGui_Function_SetValue(aspect_constraint, "aspect_ratio", current_aspect_ratio())

local function round_pixel(value)
  value = tonumber(value) or 0
  if value >= 0 then return math.floor(value + 0.5) end
  return math.ceil(value - 0.5)
end

local function geometry_key(x, y, w, h)
  return table.concat({
    round_pixel(x), round_pixel(y), round_pixel(w), round_pixel(h)
  }, ":")
end

if has_saved_window then
  last_saved_geometry = geometry_key(
    saved_window.x, saved_window.y, saved_window.w, saved_window.h)
end

local function persist_window_geometry()
  if not window_restore_complete then return end
  local x, y = R.ImGui_GetWindowPos(ctx)
  local w, h = R.ImGui_GetWindowSize(ctx)
  -- Some desktop window managers use a large negative coordinate while a
  -- native window is minimized. Never persist that sentinel or bad geometry.
  if not finite_number(x) or not finite_number(y)
      or not finite_number(w) or not finite_number(h)
      or x <= -30000 or y <= -30000 or w < 1 or h < 1 then
    return
  end
  local key = geometry_key(x, y, w, h)
  local now = R.time_precise()

  if key ~= last_seen_geometry then
    last_seen_geometry = key
    geometry_changed_at = now
    return
  end
  if key == last_saved_geometry or now - geometry_changed_at < 0.25 then return end

  save_string("window_x", round_pixel(x))
  save_string("window_y", round_pixel(y))
  save_string("window_w", round_pixel(w))
  save_string("window_h", round_pixel(h))
  last_saved_geometry = key
end

-- -----------------------------------------------------------------------------
-- Timing, region, and formatting helpers
-- -----------------------------------------------------------------------------

-- Keep the timing engine's implementation details out of the main chunk's
-- long-lived local scope. Only the snapshot and its two public entry points
-- need to remain visible to the renderer.
local snapshot, recompute_snapshot, offset_seconds, active_sample_rate, transport_position
Metering = {}
local Content
do
local regions = {}
local markers = {}
local last_project_change = -1
local cached_project = nil
local last_region_refresh = -math.huge

local function refresh_regions_if_needed(force)
  local project = R.EnumProjects and R.EnumProjects(-1) or 0
  local project_changed = project ~= cached_project
  local change = R.GetProjectStateChangeCount(project) or 0
  if not project_changed and change == last_project_change then return end
  local now = R.time_precise()
  -- A recording or continuously updating control surface can churn REAPER's
  -- project-state counter. Region edits remain responsive while large setlists
  -- are protected from a full enumerate/sort at graphics-frame rate.
  if not force and not project_changed and now - last_region_refresh < 0.25 then return end
  cached_project = project
  last_project_change = change
  last_region_refresh = now

  regions = {}
  markers = {}
  local _, marker_count, region_count = R.CountProjectMarkers(project)
  local total = (marker_count or 0) + (region_count or 0)

  for enum_index = 0, total - 1 do
    local ok, is_region, start_pos, end_pos, name, display_index, color =
      R.EnumProjectMarkers3(project, enum_index)
    if ok then
      local item = {
        enum_index = enum_index,
        start_pos = start_pos or 0,
        end_pos = end_pos or 0,
        name = name or "",
        display_index = display_index or 0,
        color = color or 0,
      }
      if is_region then
        item.kind = "region"
        regions[#regions + 1] = item
      else
        item.kind = "marker"
        markers[#markers + 1] = item
      end
    end
  end

  table.sort(regions, function(a, b)
    if a.start_pos == b.start_pos then return a.end_pos < b.end_pos end
    return a.start_pos < b.start_pos
  end)
  table.sort(markers, function(a, b) return a.start_pos < b.start_pos end)
end

local function current_region_at(pos)
  -- Deterministic overlap handling: prefer the most recently started region,
  -- then the shortest containing region. This makes nested cue regions useful.
  local best
  for _, region in ipairs(regions) do
    if region.start_pos <= pos + 0.0000001 and region.end_pos > pos + 0.0000001 then
      if not best or region.start_pos > best.start_pos
          or (region.start_pos == best.start_pos and region.end_pos < best.end_pos) then
        best = region
      end
    elseif region.start_pos > pos then
      break
    end
  end
  return best
end

local function previous_region_before(pos)
  local best
  for _, region in ipairs(regions) do
    if region.end_pos <= pos + 0.0000001
        and (not best or region.end_pos > best.end_pos) then best = region end
  end
  return best
end

local function next_named_item(items, pos)
  for _, item in ipairs(items) do
    if item.start_pos > pos + 0.0000001 then return item end
  end
  return nil
end

active_sample_rate = function()
  local ok, value = R.GetAudioDeviceInfo("SRATE")
  local rate = ok and tonumber(value) or nil
  if rate and rate > 0 then return rate, "audio device" end

  local use_project_rate = R.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  local project_rate = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if use_project_rate == 1 and project_rate and project_rate > 0 then
    return project_rate, "project"
  end
  if project_rate and project_rate > 0 then return project_rate, "project fallback" end
  return 48000, "48 kHz fallback"
end

offset_seconds = function()
  if settings.offset_unit == "samples" then
    local sample_rate = active_sample_rate()
    return settings.offset_value / sample_rate
  end
  return settings.offset_value / 1000
end

transport_position = function()
  local state = R.GetPlayStateEx and R.GetPlayStateEx(0) or R.GetPlayState()
  local transport_active = (state & 1) ~= 0 or (state & 2) ~= 0 or (state & 4) ~= 0
  if transport_active then
    if R.GetPlayPositionEx then return R.GetPlayPositionEx(0), state end
    return R.GetPlayPosition(), state
  end
  if R.GetCursorPositionEx then return R.GetCursorPositionEx(0), state end
  return R.GetCursorPosition(), state
end

local function format_clock_seconds(seconds)
  seconds = math.max(0, math.floor((seconds or 0) + 0.0000001))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function format_remaining_seconds(seconds)
  seconds = math.max(0, math.ceil((seconds or 0) - 0.0000001))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function rounded_seconds(seconds, round_up)
  seconds = math.max(0, tonumber(seconds) or 0)
  if round_up then return math.ceil(seconds - 0.0000001) end
  return math.floor(seconds + 0.0000001)
end

local function format_hms(seconds, round_up)
  seconds = rounded_seconds(seconds, round_up)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor(seconds / 60) % 60
  return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
end

local function project_frame_rate()
  if R.TimeMap_curFrameRate then
    -- Extra parentheses collapse REAPER's (rate, drop-frame) returns so the
    -- boolean is not accidentally passed to tonumber as its optional base.
    local rate = tonumber((R.TimeMap_curFrameRate(0)))
    if rate and rate > 0 then return rate end
  end
  return 30
end

local function project_time_offset()
  if R.GetProjectTimeOffset then return tonumber(R.GetProjectTimeOffset(0, false)) or 0 end
  return 0
end

local function format_time_value(seconds, round_up)
  seconds = math.max(0, tonumber(seconds) or 0)
  if settings.time_format == "hms" then return format_hms(seconds, round_up) end
  if settings.time_format == "timecode" then
    -- Cancel the project start-time offset: ReaClock scopes are elapsed spans
    -- and intentionally begin at zero even when the ruler has a start offset.
    -- Remaining/countdown values round up to the next complete frame, matching
    -- the no-early-zero contract used by every other display format.
    if round_up then
      local frame_rate = project_frame_rate()
      seconds = math.ceil(seconds * frame_rate - 0.0000001) / frame_rate
    end
    return R.format_timestr_pos(seconds - project_time_offset(), "", 5)
  end
  if settings.time_format == "frames" then
    local frames = seconds * project_frame_rate()
    frames = round_up and math.ceil(frames - 0.0000001) or math.floor(frames + 0.0000001)
    return tostring(math.max(0, frames))
  end
  if settings.time_format == "seconds" then
    return tostring(rounded_seconds(seconds, round_up))
  end
  if settings.time_format == "samples" then
    local rate = active_sample_rate()
    local samples = seconds * rate
    samples = round_up and math.ceil(samples - 0.0000001) or math.floor(samples + 0.0000001)
    return tostring(math.max(0, samples))
  end
  if round_up then return format_remaining_seconds(seconds) end
  return format_clock_seconds(seconds)
end

local function parse_bars_beats(value)
  if type(value) ~= "string" then return nil end
  -- REAPER normally returns measures.beats.hundredths here (for example
  -- "0.3.00"). The fractional field lets Remaining round upward so it does
  -- not show 0:0 while part of the final beat is still left.
  local bars, beats, fraction = value:match("^%s*(-?%d+)[%.,:](%d+)[%.,:](%d+)")
  if not bars then bars, beats = value:match("^%s*(-?%d+)[%.,:](%d+)") end
  return tonumber(bars), tonumber(beats), tonumber(fraction) or 0
end

local function format_project_bars_beats(pos)
  local beat_in_measure, measure = R.TimeMap2_timeToBeats(0, math.max(0, pos))
  measure = math.max(0, math.floor(tonumber(measure) or 0))
  beat_in_measure = math.max(0, tonumber(beat_in_measure) or 0)
  return string.format("%d:%d", measure + 1, math.floor(beat_in_measure + 0.0000001) + 1)
end

local function format_duration_bars_beats(start_pos, end_pos, as_position, round_up)
  start_pos = tonumber(start_pos) or 0
  end_pos = math.max(start_pos, tonumber(end_pos) or start_pos)
  local length = end_pos - start_pos
  local raw = R.format_timestr_len(length, "", start_pos, 2)
  local bars, beats, fraction = parse_bars_beats(raw)
  if not bars then return "0:0" end

  bars = math.max(0, math.floor(bars))
  beats = math.max(0, math.floor(beats))
  if round_up and length > 0.0000001
      and (fraction > 0 or (bars == 0 and beats == 0)) then
    beats = beats + 1
    local probe_pos = math.max(0, end_pos - math.min(0.0000001, length * 0.5))
    local beats_per_measure = select(1, R.TimeMap_GetTimeSigAtTime(0, probe_pos))
    beats_per_measure = math.max(1, math.floor(tonumber(beats_per_measure) or 4))
    if beats >= beats_per_measure then
      bars = bars + math.floor(beats / beats_per_measure)
      beats = beats % beats_per_measure
    end
  end
  if as_position then
    bars = bars + 1
    beats = beats + 1
  end
  return string.format("%d:%d", bars, beats)
end

local meter_fit_cache = { key = nil, max_numerator = 4 }

local function integer_digit_count(value)
  value = math.max(0, math.floor(tonumber(value) or 0))
  return #tostring(value)
end

local function max_numerator_in_span(start_pos, end_pos)
  start_pos = math.max(0, tonumber(start_pos) or 0)
  end_pos = math.max(start_pos, tonumber(end_pos) or start_pos)
  local project = R.EnumProjects and R.EnumProjects(-1) or 0
  local change = R.GetProjectStateChangeCount(project) or 0
  local key = table.concat({
    tostring(project), tostring(change),
    string.format("%.9f", start_pos), string.format("%.9f", end_pos)
  }, ":")
  if meter_fit_cache.key == key then return meter_fit_cache.max_numerator end

  local start_numerator = select(1, R.TimeMap_GetTimeSigAtTime(project, start_pos))
  local max_numerator = math.max(1, math.floor(tonumber(start_numerator) or 4))
  if R.CountTempoTimeSigMarkers and R.GetTempoTimeSigMarker then
    local count = R.CountTempoTimeSigMarkers(project) or 0
    for index = 0, count - 1 do
      local ok, marker_pos, _, _, _, numerator =
        R.GetTempoTimeSigMarker(project, index)
      if ok and marker_pos >= start_pos - 0.0000001
          and marker_pos <= end_pos + 0.0000001
          and tonumber(numerator) and numerator > 0 then
        max_numerator = math.max(max_numerator, math.floor(numerator))
      end
    end
  end

  meter_fit_cache.key = key
  meter_fit_cache.max_numerator = max_numerator
  return max_numerator
end

local function bars_beats_fit_reference(current_text, end_text, max_numerator)
  local bar_digits, beat_digits = 1, integer_digit_count(max_numerator)
  for _, value in ipairs({ current_text, end_text }) do
    local bars, beats = tostring(value or ""):match("^(%d+):(%d+)$")
    if bars then
      bar_digits = math.max(bar_digits, #bars)
      beat_digits = math.max(beat_digits, #beats)
    end
  end
  return string.rep("8", bar_digits) .. ":" .. string.rep("8", beat_digits)
end

local function format_region_label(region)
  if not region then return "" end
  if region.name and region.name ~= "" then return region.name end
  local kind = region.kind == "marker" and "Marker" or "Region"
  return kind .. " " .. tostring(region.display_index or 0)
end

-- -----------------------------------------------------------------------------
-- Metering bridge, source discovery, and numeric cache
-- -----------------------------------------------------------------------------

Metering.fx_ident = "ReaClock/ReaClock_Meter.jsfx"
Metering.fx_name = "JS:ReaClock/ReaClock_Meter.jsfx"
Metering.gmem_name = "ReaClock_Meter_v1"
Metering.rec_offset = 0x1000000
Metering.api_version = 1
Metering.companion_build = 10
Metering.companion_checksum = "422FFE58"
Metering.command = { magic = 52601, api = 1, slot_base = 16, slot_count = 16384,
  slot_stride = 8, counter_mod = 65536 }
-- UI theme records are separate from the command and visual bridges. They are
-- keyed by the meter's collision-resistant command slot + owner token, so
-- matching the standalone JSFX to ReaClock never dirties a project or leaks a
-- project-tab binding into another meter instance.
Metering.theme = { magic = 52621, base = 7340032, stride = 16, prime = 16777213 }
Metering.param = {
  reset_on_transport = 0, force_mono = 1, true_peak_user = 2,
  sample_peak = 3, sample_peak_max = 4, true_peak = 5, true_peak_max = 6,
  rms_m = 7, rms_m_max = 8, rms_i = 9, rms_i_max = 10,
  lufs_m = 11, lufs_m_max = 12, lufs_s = 13, lufs_s_max = 14,
  lufs_i = 15, lufs_i_max = 16, lra = 17, lra_max = 18,
  reset_ack = 19, valid_mask = 20, heartbeat = 21, channels = 22,
  api = 23, slot = 24, token = 25, correlation = 26, arm_ack = 27, epoch = 28,
  channel_limit = 29, build = 30,
}
Metering.metrics = {
  sample_peak = { label = "PEAK", unit = "dBFS", valid = 1 },
  sample_peak_max = { label = "PEAK MAX", unit = "dBFS", valid = 1, reset = true },
  true_peak = { label = "TRUE PEAK", unit = "dBTP", valid = 2, true_peak = true },
  true_peak_max = { label = "TRUE PEAK MAX", unit = "dBTP", valid = 2,
    true_peak = true, reset = true },
  rms_m = { label = "RMS-M", unit = "dBFS", valid = 4 },
  rms_m_max = { label = "RMS-M MAX", unit = "dBFS", valid = 4, reset = true },
  rms_i = { label = "RMS-I", unit = "dBFS", valid = 8, reset = true },
  rms_i_max = { label = "RMS-I MAX", unit = "dBFS", valid = 8, reset = true },
  lufs_m = { label = "LUFS-M", unit = "LUFS", valid = 16 },
  lufs_m_max = { label = "LUFS-M MAX", unit = "LUFS", valid = 16, reset = true },
  lufs_s = { label = "LUFS-S", unit = "LUFS", valid = 32 },
  lufs_s_max = { label = "LUFS-S MAX", unit = "LUFS", valid = 32, reset = true },
  lufs_i = { label = "LUFS-I", unit = "LUFS", valid = 64, reset = true },
  lufs_i_max = { label = "LUFS-I MAX", unit = "LUFS", valid = 64, reset = true },
  lra = { label = "LRA", unit = "LU", valid = 128, reset = true },
  lra_max = { label = "LRA MAX", unit = "LU", valid = 128, reset = true },
}

Metering.numeric_menus = {
  { label = "LUFS", items = {
    { "Momentary", "lufs_m" }, { "Momentary Maximum", "lufs_m_max" },
    { "Short-Term", "lufs_s" }, { "Short-Term Maximum", "lufs_s_max" },
    { "Integrated", "lufs_i" }, { "Integrated Maximum", "lufs_i_max" },
  } },
  { label = "RMS", items = {
    { "Momentary", "rms_m" }, { "Momentary Maximum", "rms_m_max" },
    { "Integrated", "rms_i" }, { "Integrated Maximum", "rms_i_max" },
  } },
  { label = "Peak", items = {
    { "Sample Peak", "sample_peak" }, { "Sample Peak Maximum", "sample_peak_max" },
    { "True Peak", "true_peak" }, { "True Peak Maximum", "true_peak_max" },
  } },
  { label = "Loudness Range", items = {
    { "Current", "lra" }, { "Maximum", "lra_max" },
  } },
}

Metering.visual_menus = {
  { "Level Meters", "levels" },
  { "Loudness History", "history" },
  { "Waveform", "waveform" },
  { "Spectrum Analyzer", "spectrum" },
  { "Spectrogram", "spectrogram" },
  { "Vectorscope", "vectorscope" },
  { "Phase Correlation", "correlation" },
}

do
  local meter_tokens = {}
  for _, group in ipairs(Metering.numeric_menus) do
    for _, item in ipairs(group.items) do
      meter_tokens[#meter_tokens + 1] = {
        id = item[2], label = group.label .. " · " .. item[1],
      }
    end
  end
  TEMPLATE_TOKEN_GROUPS[#TEMPLATE_TOKEN_GROUPS + 1] = {
    label = "Metering", tokens = meter_tokens,
  }
end

function Metering.template_metric_ids(template)
  local ids = {}
  template = tostring(template or "")
  for _, group in ipairs(Metering.numeric_menus) do
    for _, item in ipairs(group.items) do
      if template:find("{" .. item[2] .. "}", 1, true) then
        ids[#ids + 1] = item[2]
      end
    end
  end
  return ids
end

function Metering.template_uses_metrics(template)
  return #Metering.template_metric_ids(template) > 0
end

Runtime.metering = {
  active_project = nil,
  active_project_token = nil,
  project_tokens = setmetatable({}, { __mode = "k" }),
  next_project_token = 1,
  sources = {}, source_by_key = {},
  last_scan = -math.huge, last_project_change = -1, last_poll = -math.huge,
  active_playing = false, background_playing = false,
  playing_project_count = 0, output_project = nil, gmem_attached = false,
  transport_running = false, transport_generation = 0,
  operation_status = nil, operation_error = nil,
  companion_checked = false, last_companion_check = -math.huge,
  companion_installed = nil, companion_repair_copy = nil,
  companion_reload = nil, companion_reload_attempted = {},
  companion_reload_fingerprint = nil, companion_reload_force = true,
  last_companion_reload_scan = -math.huge,
  last_companion_reload_full_scan = -math.huge,
  last_theme_sync = -math.huge, theme_key = nil,
  setup_request = nil, setup_card = nil, setup_bind_face = false,
  setup_close_request = false,
  setup_status = nil, setup_error = nil,
}

function Metering.read_file(path)
  local file, open_error = io.open(path, "rb")
  if not file then return nil, tostring(open_error or "could not open file") end
  local content = file:read("*a")
  local closed, close_error = file:close()
  if content == nil then return nil, "could not read file" end
  if closed == nil then return nil, tostring(close_error or "could not close file") end
  return content
end

function Metering.source_markers(content)
  if type(content) ~= "string" or not content:find("// ReaClock managed meter", 1, true) then
    return nil, "missing ReaClock managed-meter marker"
  end
  local api = tonumber(content:match("ReaClock%-Meter%-API:%s*(%d+)"))
  local build = tonumber(content:match("ReaClock%-Meter%-Build:%s*(%d+)"))
  local checksum = content:match("ReaClock%-Meter%-Checksum:%s*(%x+)")
  if not api or not build or not checksum then
    return nil, "missing API, build, or checksum marker"
  end
  checksum = checksum:upper()
  local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  normalized = "\n" .. normalized
  local payload, removed = normalized:gsub(
    "\n[^\n]*ReaClock%-Meter%-Checksum:%s*%x+[^\n]*", "", 1)
  if removed ~= 1 then return nil, "could not isolate checksum marker" end
  payload = payload:sub(2)
  local hash = 2166136261
  for index = 1, #payload do
    hash = ((hash ~ payload:byte(index)) * 16777619) & 0xFFFFFFFF
  end
  local computed = string.format("%08X", hash)
  return {
    api = api, build = build, checksum = checksum,
    computed_checksum = computed, checksum_valid = checksum == computed,
  }
end

function Metering.companion_paths()
  local effects = join_path(R.GetResourcePath(), "Effects")
  local directory = join_path(effects, "ReaClock")
  local bundled = join_path(Runtime.resources_dir, "ReaClock_Meter.jsfx")
  if Store.test_override then
    local test_path = R.GetExtState(EXT, "__meter_test_bundled_path")
    if test_path ~= "" then bundled = test_path end
  end
  return {
    bundled = bundled,
    directory = directory,
    destination = join_path(directory, "ReaClock_Meter.jsfx"),
  }
end

function Metering.file_exists(path)
  if R.file_exists then return R.file_exists(path) == true end
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

function Metering.inspect_companion(path, keep_content)
  local result = { path = path, code = "missing", ready = false }
  if not Metering.file_exists(path) then
    result.detail = "The file is missing."
    return result
  end
  local content, read_error = Metering.read_file(path)
  if not content then
    result.code, result.detail = "unreadable", "The file could not be read: "
      .. tostring(read_error or "unknown error")
    return result
  end
  if keep_content then result.content = content end
  local markers, marker_error = Metering.source_markers(content)
  result.markers = markers
  if not markers then
    result.code, result.detail = "damaged", "The file is not a valid ReaClock Meter: "
      .. tostring(marker_error or "required markers are missing")
    return result
  end
  if not markers.checksum_valid then
    result.code, result.detail = "damaged", string.format(
      "The file checksum is %s, but its contents calculate as %s.",
      markers.checksum, markers.computed_checksum)
    return result
  end
  if markers.api == Metering.api_version
      and markers.build == Metering.companion_build
      and markers.checksum == Metering.companion_checksum then
    result.code, result.ready = "ready", true
    result.detail = string.format("API %d · Build %d · Checksum %s",
      markers.api, markers.build, markers.checksum)
    return result
  end
  local newer = markers.api > Metering.api_version
    or markers.api == Metering.api_version and markers.build > Metering.companion_build
  result.code = newer and "newer" or "outdated"
  result.detail = string.format(
    "Installed API %d / Build %d does not match required API %d / Build %d.",
    markers.api, markers.build, Metering.api_version, Metering.companion_build)
  return result
end

function Metering.same_path(left, right)
  local function normalize(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
    local operating_system = R.GetOS and tostring(R.GetOS()) or ""
    if operating_system:find("Win", 1, true) or operating_system:find("OSX", 1, true)
        or operating_system:find("macOS", 1, true) then path = path:lower() end
    return path
  end
  return normalize(left) == normalize(right)
end

function Metering.write_file_checked(path, content)
  local file, open_error = io.open(path, "wb")
  if not file then return false, tostring(open_error or "could not create file") end
  local written, write_error = file:write(content)
  if not written then file:close() return false, tostring(write_error or "write failed") end
  local flushed, flush_error = file:flush()
  local closed, close_error = file:close()
  if flushed == nil then return false, tostring(flush_error or "flush failed") end
  if closed == nil then return false, tostring(close_error or "close failed") end
  local verify, verify_error = Metering.read_file(path)
  if verify ~= content then return false, verify_error or "written file did not verify" end
  return true
end

function Metering.unique_sidecar_path(destination, role)
  local token = (instance_token .. ":" .. tostring(os.time()) .. ":"
    .. string.format("%.17g", R.time_precise())):gsub("[^%w]", "")
  for attempt = 0, 99 do
    local candidate = destination .. "." .. role .. "-" .. token
      .. (attempt == 0 and "" or "-" .. attempt)
    if not Metering.file_exists(candidate) then return candidate end
  end
  return nil
end

function Metering.add_companion_reload_chain(instances, seen, project, track, rec_chain, monitoring)
  local count = rec_chain and R.TrackFX_GetRecCount(track) or R.TrackFX_GetCount(track)
  for index = 0, count - 1 do
    local fx = (rec_chain and Metering.rec_offset or 0) + index
    if Metering.fx_identity(track, fx) then
      local fx_guid = tostring(R.TrackFX_GetFXGUID(track, fx) or "")
      local identity_key = fx_guid ~= "" and fx_guid or tostring(track) .. ":" .. tostring(fx)
      if seen[identity_key] then goto continue end
      seen[identity_key] = true
      local bridge = Metering.bridge_metadata(track, fx)
      instances[#instances + 1] = {
        project = project, track = track, rec_chain = rec_chain, monitoring = monitoring == true,
        chain_index = index, fx_index = fx,
        fx_guid = fx_guid,
        was_open = R.TrackFX_GetOpen and R.TrackFX_GetOpen(track, fx) == true,
        was_offline = R.TrackFX_GetOffline(track, fx) == true,
        was_enabled = R.TrackFX_GetEnabled(track, fx) == true,
        loaded_build = bridge.has_build and math.floor((bridge.build or 0) + 0.5) or 0,
      }
    end
    ::continue::
  end
end

function Metering.loaded_companion_instances()
  local instances, seen, project_index = {}, {}, 0
  if Store.test_override then
    local count = tonumber(R.GetExtState(EXT, "__meter_test_reload_full_scans")) or 0
    R.SetExtState(EXT, "__meter_test_reload_full_scans", tostring(count + 1), false)
  end
  local active_project = R.EnumProjects and R.EnumProjects(-1) or nil
  local active_master = active_project and R.GetMasterTrack(active_project) or nil
  if active_master then
    -- Monitoring FX are global. Enumerate that chain once through the active project.
    Metering.add_companion_reload_chain(
      instances, seen, active_project, active_master, true, true)
  end
  while true do
    local project = R.EnumProjects(project_index)
    if not project then break end
    local master = R.GetMasterTrack(project)
    if master then
      Metering.add_companion_reload_chain(instances, seen, project, master, false, false)
    end
    for track_index = 0, (R.CountTracks(project) or 0) - 1 do
      local track = R.GetTrack(project, track_index)
      if track then
        Metering.add_companion_reload_chain(instances, seen, project, track, false, false)
        Metering.add_companion_reload_chain(instances, seen, project, track, true, false)
      end
    end
    project_index = project_index + 1
  end
  return instances
end

function Metering.resolve_companion_reload_instance(instance)
  if not instance then return nil end
  if instance.monitoring then
    local project = R.EnumProjects and R.EnumProjects(-1) or nil
    local track = project and R.GetMasterTrack(project) or nil
    if not Metering.track_valid(project, track) then return nil end
    instance.project, instance.track = project, track
  elseif not Metering.track_valid(instance.project, instance.track) then
    return nil
  end
  local count = instance.rec_chain and R.TrackFX_GetRecCount(instance.track)
    or R.TrackFX_GetCount(instance.track)
  local offset = instance.rec_chain and Metering.rec_offset or 0
  for index = 0, count - 1 do
    local fx = offset + index
    local guid = tostring(R.TrackFX_GetFXGUID(instance.track, fx) or "")
    if instance.fx_guid ~= "" and guid == instance.fx_guid
        or instance.fx_guid == "" and index == instance.chain_index then return fx end
  end
  return nil
end

function Metering.set_fx_offline(track, fx, offline)
  if Store.test_override and offline == false then
    local remaining = tonumber(R.GetExtState(EXT, "__meter_test_restore_failures")) or 0
    if remaining > 0 then
      R.SetExtState(EXT, "__meter_test_restore_failures", tostring(remaining - 1), false)
      error("Injected companion restore failure")
    end
  end
  return R.TrackFX_SetOffline(track, fx, offline)
end

function Metering.queue_companion_reload(base_status)
  local state = Runtime.metering
  if state.companion_reload or not R.TrackFX_SetOffline
      or not R.TrackFX_GetOffline or not R.TrackFX_GetNumParams then return 0, 0 end
  local queued, failed = {}, 0
  for _, instance in ipairs(Metering.loaded_companion_instances()) do
    local reload_key = (instance.fx_guid ~= "" and instance.fx_guid
      or tostring(instance.track) .. ":" .. tostring(instance.fx_index))
      .. ":" .. tostring(Metering.companion_build)
    if not instance.was_offline and instance.loaded_build ~= Metering.companion_build
        and not state.companion_reload_attempted[reload_key] then
      -- Mark this before toggling: project reloads advance the project state count.
      state.companion_reload_attempted[reload_key] = true
      instance.reload_key = reload_key
      local okay = pcall(Metering.set_fx_offline, instance.track, instance.fx_index, true)
      if okay then queued[#queued + 1] = instance else failed = failed + 1 end
    end
  end
  if #queued > 0 then
    local now = R.time_precise()
    state.companion_reload = {
      phase = "wait_offline", items = queued, initial_failed = failed,
      ready_at = now + 0.05, deadline = now + 0.75,
      base_status = base_status,
    }
  end
  return #queued, failed
end

function Metering.update_companion_reload(now)
  local state, pending = Runtime.metering, Runtime.metering.companion_reload
  if not pending or now < (pending.ready_at or 0) then return end

  if pending.phase == "wait_offline" then
    local all_offline = true
    for _, instance in ipairs(pending.items) do
      local fx = Metering.resolve_companion_reload_instance(instance)
      instance.resolved_fx = fx
      if fx and not R.TrackFX_GetOffline(instance.track, fx) then all_offline = false end
    end
    if not all_offline and now < pending.deadline then return end
    for _, instance in ipairs(pending.items) do
      local fx = instance.resolved_fx or Metering.resolve_companion_reload_instance(instance)
      if fx then
        local okay = pcall(Metering.set_fx_offline, instance.track, fx, false)
        if okay then
          instance.restore_requested = true
        else
          instance.restore_retry_at = now + 0.05
        end
      else
        instance.restore_retry_at = now + 0.05
      end
    end
    pending.phase, pending.ready_at, pending.deadline = "verify", now + 0.15, now + 1.5
    return
  end

  local waiting = false
  for _, instance in ipairs(pending.items) do
    if not instance.verified and not instance.failed then
      local fx = Metering.resolve_companion_reload_instance(instance)
      local offline = fx and R.TrackFX_GetOffline(instance.track, fx) == true
      if offline and now >= (instance.restore_retry_at or 0) then
        local okay = pcall(Metering.set_fx_offline, instance.track, fx, false)
        if okay then instance.restore_requested = true end
        instance.restore_retry_at = now + 0.05
        offline = R.TrackFX_GetOffline(instance.track, fx) == true
      end
      local bridge = fx and Metering.bridge_metadata(instance.track, fx) or nil
      local loaded_build = bridge and bridge.has_build
        and math.floor((bridge.build or 0) + 0.5) or 0
      if fx and not offline
          and loaded_build == Metering.companion_build then
        if R.TrackFX_GetEnabled and R.TrackFX_SetEnabled
            and R.TrackFX_GetEnabled(instance.track, fx) ~= instance.was_enabled then
          pcall(R.TrackFX_SetEnabled, instance.track, fx, instance.was_enabled)
        end
        local enabled_preserved = not R.TrackFX_GetEnabled
          or R.TrackFX_GetEnabled(instance.track, fx) == instance.was_enabled
        if R.TrackFX_GetOpen and R.TrackFX_SetOpen
            and R.TrackFX_GetOpen(instance.track, fx) ~= instance.was_open then
          pcall(R.TrackFX_SetOpen, instance.track, fx, instance.was_open)
        end
        local open_preserved = not R.TrackFX_GetOpen
          or R.TrackFX_GetOpen(instance.track, fx) == instance.was_open
        instance.verified = enabled_preserved and open_preserved
        if not instance.verified and now < pending.deadline then waiting = true end
      elseif now < pending.deadline then
        waiting = true
      else
        instance.stranded = fx and offline or false
        instance.failed = true
      end
    end
  end
  if waiting then return end

  local reloaded, failed, stranded, project_reloaded = 0, pending.initial_failed or 0, 0, {}
  for _, instance in ipairs(pending.items) do
    if instance.verified then
      reloaded = reloaded + 1
      if not instance.monitoring then project_reloaded[tostring(instance.project)] = true end
    else
      failed = failed + 1
      if instance.stranded then stranded = stranded + 1 end
    end
  end
  local base = tostring(pending.base_status or "The ReaClock Meter file is current.")
  if reloaded > 0 then
    base = base .. string.format(" Reloaded %d online meter instance%s.",
      reloaded, reloaded == 1 and "" or "s")
  end
  local project_count = 0
  for _ in pairs(project_reloaded) do project_count = project_count + 1 end
  if project_count > 0 then
    base = base .. string.format(
      " REAPER may mark %d affected open project%s modified; ReaClock did not save %s.",
      project_count, project_count == 1 and "" or "s",
      project_count == 1 and "it" or "them")
  end
  if failed - stranded > 0 then
    base = base .. string.format(" %d loaded meter instance%s could not be reloaded; restart REAPER to finish the update.",
      failed - stranded, failed - stranded == 1 and "" or "s")
  end
  if stranded > 0 then
    base = base .. string.format(" %d meter instance%s remained offline; re-enable %s manually in the FX chain.",
      stranded, stranded == 1 and "" or "s", stranded == 1 and "it" or "them")
  end
  state.operation_status, state.operation_error = base, nil
  state.companion_reload = nil
  state.companion_reload_force = true
  state.last_scan, state.last_poll = -math.huge, -math.huge
  Metering.scan_sources(true)
end

function Metering.companion_reload_change_fingerprint()
  local parts = {}
  local active_project = R.EnumProjects and R.EnumProjects(-1) or nil
  parts[#parts + 1] = "active=" .. tostring(active_project)
  local project_index = 0
  while true do
    local project = R.EnumProjects(project_index)
    if not project then break end
    parts[#parts + 1] = table.concat({ "project", tostring(project),
      tostring(R.GetProjectStateChangeCount(project) or 0) }, ":")
    project_index = project_index + 1
  end

  local master = active_project and R.GetMasterTrack(active_project) or nil
  if master then
    local count = R.TrackFX_GetRecCount(master) or 0
    parts[#parts + 1] = "monitoring_count=" .. tostring(count)
    for index = 0, count - 1 do
      local fx = Metering.rec_offset + index
      if Metering.fx_identity(master, fx) then
        local bridge = Metering.bridge_metadata(master, fx)
        parts[#parts + 1] = table.concat({ "monitoring", index,
          tostring(R.TrackFX_GetFXGUID(master, fx) or ""),
          R.TrackFX_GetOffline(master, fx) and 1 or 0,
          bridge.has_build and math.floor((bridge.build or 0) + 0.5) or 0 }, ":")
      end
    end
  end
  return table.concat(parts, "|")
end

function Metering.check_loaded_companion_reloads(now)
  local state = Runtime.metering
  if Store.test_override and R.GetExtState(EXT, "__meter_test_pause_reload_scan") == "1" then return end
  if state.companion_reload or now - state.last_companion_reload_scan < 1 then return end
  state.last_companion_reload_scan = now
  local installed = state.companion_installed
  if not installed or not installed.ready then return end
  local fingerprint = Metering.companion_reload_change_fingerprint()
  local changed = fingerprint ~= state.companion_reload_fingerprint
  state.companion_reload_fingerprint = fingerprint
  local fallback_due = now - state.last_companion_reload_full_scan >= 30
  if not state.companion_reload_force and not changed and not fallback_due then return end
  state.companion_reload_force = false
  state.last_companion_reload_full_scan = now
  local base_status = "Verified the installed ReaClock Meter."
  local queued, failed = Metering.queue_companion_reload(base_status)
  if queued > 0 then
    state.operation_status = base_status .. string.format(
      " Reloading %d outdated meter instance%s.", queued, queued == 1 and "" or "s")
  elseif failed > 0 then
    state.operation_status = base_status .. string.format(
      " %d outdated meter instance%s could not be queued for reload; restart REAPER to finish the update.",
      failed, failed == 1 and "" or "s")
  end
end

function Metering.repair_companion(source)
  local state = Runtime.metering
  local paths = Metering.companion_paths()
  if Metering.same_path(paths.bundled, paths.destination) then
    return false, "The packaged repair copy and Effects destination resolve to the same file."
  end
  if not source or not source.content then
    source = Metering.inspect_companion(paths.bundled, true)
  end
  if not source.ready then
    return false, "Automatic repair is unavailable because the packaged repair copy is missing, damaged, or does not match this ReaClock version. Reinstall or update ReaClock in ReaPack."
  end
  if not R.RecursiveCreateDirectory then
    return false, "This REAPER version cannot create the meter's Effects folder."
  end
  R.RecursiveCreateDirectory(paths.directory, 0)
  local temporary = Metering.unique_sidecar_path(paths.destination, "repair")
  if not temporary then return false, "Could not reserve a temporary meter repair path." end
  local wrote, write_error = Metering.write_file_checked(temporary, source.content)
  if not wrote then
    os.remove(temporary)
    return false, "Could not stage the meter repair: " .. tostring(write_error)
  end
  local staged = Metering.inspect_companion(temporary)
  if not staged.ready then
    os.remove(temporary)
    return false, "The staged meter repair did not pass its version and integrity checks."
  end

  local had_destination = Metering.file_exists(paths.destination)
  local backup = had_destination and Metering.unique_sidecar_path(paths.destination, "rollback") or nil
  if had_destination and not backup then
    os.remove(temporary)
    return false, "Could not reserve a rollback path for the installed meter."
  end
  if had_destination then
    local preserved, preserve_error = os.rename(paths.destination, backup)
    if not preserved then
      os.remove(temporary)
      return false, "Could not preserve the installed meter before repair: "
        .. tostring(preserve_error)
    end
  end
  local installed, install_error = os.rename(temporary, paths.destination)
  if not installed then
    local restored, restore_error = true, nil
    if had_destination then restored, restore_error = os.rename(backup, paths.destination) end
    os.remove(temporary)
    return false, "Could not install the repaired meter: " .. tostring(install_error)
      .. (restored and "" or " The previous file could not be restored: "
        .. tostring(restore_error))
  end
  local verified = Metering.inspect_companion(paths.destination)
  if not verified.ready then
    os.remove(paths.destination)
    local restored, restore_error = true, nil
    if had_destination then restored, restore_error = os.rename(backup, paths.destination) end
    return false, "The repaired meter failed final verification."
      .. (restored and "" or " The previous file could not be restored: "
        .. tostring(restore_error))
  end
  local cleanup_warning
  if had_destination then
    local removed, remove_error = os.remove(backup)
    if not removed then
      cleanup_warning = "Its temporary rollback copy could not be removed: "
        .. tostring(remove_error)
    end
  end
  local base_status = string.format(
    "Repaired and verified ReaClock Meter API %d / Build %d from its packaged fallback.",
    Metering.api_version, Metering.companion_build)
  if cleanup_warning then base_status = base_status .. " " .. cleanup_warning end
  state.companion_reload_force = true
  local queued, failed = Metering.queue_companion_reload(base_status)
  if queued > 0 then
    state.operation_status = base_status .. string.format(" Reloading %d loaded meter instance%s.",
      queued, queued == 1 and "" or "s")
  elseif failed > 0 then
    state.operation_status = base_status .. string.format(
      " %d loaded meter instance%s could not be queued for reload; restart REAPER to finish the update.",
      failed, failed == 1 and "" or "s")
  else
    state.operation_status = base_status
  end
  state.operation_error = nil
  state.companion_installed = Metering.inspect_companion(paths.destination)
  state.companion_repair_copy = Metering.inspect_companion(paths.bundled)
  return true, state.operation_status
end

function Metering.ensure_companion()
  local state, paths = Runtime.metering, Metering.companion_paths()
  state.companion_checked = true
  state.last_companion_check = R.time_precise()
  local installed = Metering.inspect_companion(paths.destination)
  local repair_copy = Metering.inspect_companion(paths.bundled)
  state.companion_installed, state.companion_repair_copy = installed, repair_copy
  if installed.ready then
    state.operation_error = nil
    return true, paths.destination
  end
  if installed.code == "newer" then
    state.operation_error = installed.detail
      .. " Update ReaClock in ReaPack so the Lua script matches this newer meter."
    return false, state.operation_error
  end
  if not repair_copy.ready then
    state.operation_status, state.operation_error = nil,
      "The ReaClock Meter could not be repaired automatically. Automatic repair is unavailable because the packaged repair copy is missing, damaged, or does not match this ReaClock version. Reinstall or update ReaClock in ReaPack."
    return false, state.operation_error
  end
  local source = Metering.inspect_companion(paths.bundled, true)
  local repaired, detail = Metering.repair_companion(source)
  if repaired then return true, detail end
  state.operation_status, state.operation_error = nil,
    "The ReaClock Meter could not be repaired automatically. " .. tostring(detail)
  return false, state.operation_error
end

function Metering.verify_companion()
  return Metering.ensure_companion()
end

function Metering.project_valid(project)
  if not project then return false end
  if not R.ValidatePtr then return true end
  local ok, valid = pcall(R.ValidatePtr, project, "ReaProject*")
  return ok and valid == true
end

function Metering.track_valid(project, track)
  if not Metering.project_valid(project) or not track then return false end
  if not R.ValidatePtr2 then return true end
  local ok, valid = pcall(R.ValidatePtr2, project, track, "MediaTrack*")
  return ok and valid == true
end

function Metering.project_token(project)
  local state = Runtime.metering
  local token = state.project_tokens[project]
  if not token then
    token = state.next_project_token
    state.next_project_token = state.next_project_token + 1
    state.project_tokens[project] = token
  end
  return token
end

function Metering.fx_identity(track, fx)
  local ident_ok, ident = R.TrackFX_GetNamedConfigParm(track, fx, "fx_ident")
  local type_ok, fx_type = R.TrackFX_GetNamedConfigParm(track, fx, "fx_type")
  return ident_ok and type_ok and ident == Metering.fx_ident and fx_type == "JS",
    tostring(ident or ""), tostring(fx_type or "")
end

function Metering.bridge_metadata(track, fx)
  local parameter_count = R.TrackFX_GetNumParams(track, fx) or 0
  local function named(index, expected)
    if parameter_count <= index then return 0, false end
    local okay, name = R.TrackFX_GetParamName(track, fx, index, "")
    if not okay or name ~= expected then return 0, false end
    return tonumber((R.TrackFX_GetParam(track, fx, index))) or 0, true
  end
  local api, has_api = named(Metering.param.api, "Bridge API version (output)")
  local _, has_epoch = named(Metering.param.epoch, "Measurement epoch (output)")
  local build, has_build = named(Metering.param.build, "Bridge build (output)")
  local bridge_compatible = has_api and has_epoch
    and math.floor(api + 0.5) == Metering.api_version
  local current_build = bridge_compatible and has_build
    and math.floor(build + 0.5) == Metering.companion_build
  return {
    parameter_count = parameter_count,
    api = api, build = build,
    has_api = has_api, has_epoch = has_epoch, has_build = has_build,
    bridge_compatible = bridge_compatible == true,
    current_build = current_build == true,
  }
end

function Metering.track_name(track, number)
  local _, name = R.GetTrackName(track, "")
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or (number == 0 and "Master" or "Track " .. number)
end

function Metering.add_chain_sources(list, old_by_key, project, project_token,
    track, kind, rec_chain, track_number, track_guid)
  local count = rec_chain and R.TrackFX_GetRecCount(track) or R.TrackFX_GetCount(track)
  local matches = {}
  for index = 0, count - 1 do
    local fx = (rec_chain and Metering.rec_offset or 0) + index
    local exact = Metering.fx_identity(track, fx)
    if exact then
      local guid = tostring(R.TrackFX_GetFXGUID(track, fx) or "")
      local bridge = Metering.bridge_metadata(track, fx)
      matches[#matches + 1] = {
        kind = kind, project = project, project_session_token = project_token,
        track = track, track_guid = track_guid, fx_guid = guid,
        fx_index = fx, chain_index = index, rec_chain = rec_chain,
        track_number = track_number, track_name = Metering.track_name(track, track_number),
        api_version = bridge.api, build_version = bridge.build,
        has_api_param = bridge.has_api, has_epoch_param = bridge.has_epoch,
        has_build_param = bridge.has_build,
        bridge_compatible = bridge.bridge_compatible,
        current_build = bridge.current_build,
        update_pending = bridge.bridge_compatible and not bridge.current_build,
        -- Kept as a usability alias for existing binding, command, and visual call sites.
        compatible = bridge.bridge_compatible,
        enabled = R.TrackFX_GetEnabled(track, fx), offline = R.TrackFX_GetOffline(track, fx),
      }
    end
  end
  for ordinal, source in ipairs(matches) do
    source.ordinal = ordinal
    source.monitoring_ordinal = kind == "monitoring" and ordinal or nil
    if kind == "monitoring" then
      source.key = "monitoring:" .. ordinal
      source.short_name = "OUTPUT"
      source.display_name = "Monitoring FX - Entire Output"
    elseif kind == "master" then
      source.key = table.concat({ "master", project_token, track_guid, source.fx_guid }, ":")
      source.short_name = "MASTER"
      source.display_name = "Master Track FX"
    else
      source.key = table.concat({ "track", project_token, track_guid, source.fx_guid }, ":")
      source.short_name = source.track_name:upper()
      source.display_name = string.format("%d - %s", track_number, source.track_name)
    end
    if #matches > 1 then
      source.short_name = source.short_name .. " METER " .. ordinal
      source.display_name = source.display_name .. " - Meter " .. ordinal
    end
    source.runtime = old_by_key[source.key] and old_by_key[source.key].runtime or {
      values = {}, valid_mask = 0, last_heartbeat_at = R.time_precise(),
    }
    list[#list + 1] = source
  end
end

function Metering.scan_sources(force)
  local state, now = Runtime.metering, R.time_precise()
  local project = R.EnumProjects and R.EnumProjects(-1) or 0
  if not Metering.project_valid(project) then
    state.sources, state.source_by_key = {}, {}
    return false
  end
  local change = R.GetProjectStateChangeCount(project) or 0
  if not force and project == state.active_project
      and change == state.last_project_change and now - state.last_scan < 1 then return true end

  if project ~= state.active_project then
    state.active_project = project
    state.active_project_token = Metering.project_token(project)
    state.sources, state.source_by_key = {}, {}
    state.last_project_change = -1
  end
  local old_by_key = state.source_by_key
  local sources, by_key = {}, {}
  local project_token = state.active_project_token
  local master = R.GetMasterTrack(project)
  if Metering.track_valid(project, master) then
    local master_guid = tostring(R.GetTrackGUID(master) or "MASTER")
    Metering.add_chain_sources(sources, old_by_key, project, project_token,
      master, "monitoring", true, 0, master_guid)
    Metering.add_chain_sources(sources, old_by_key, project, project_token,
      master, "master", false, 0, master_guid)
  end
  for index = 0, (R.CountTracks(project) or 0) - 1 do
    local track = R.GetTrack(project, index)
    if Metering.track_valid(project, track) then
      Metering.add_chain_sources(sources, old_by_key, project, project_token,
        track, "track", false, index + 1, tostring(R.GetTrackGUID(track) or ""))
    end
  end
  table.sort(sources, function(a, b)
    local order = { monitoring = 1, master = 2, track = 3 }
    if order[a.kind] ~= order[b.kind] then return order[a.kind] < order[b.kind] end
    if a.track_number ~= b.track_number then return a.track_number < b.track_number end
    return (a.ordinal or 1) < (b.ordinal or 1)
  end)
  for _, source in ipairs(sources) do by_key[source.key] = source end
  state.sources, state.source_by_key = sources, by_key
  state.last_scan, state.last_project_change = now, change
  return true
end

function Metering.inactive_track_matches(track_guid)
  if not track_guid or track_guid == "" then return 0 end
  local state, matches, index = Runtime.metering, 0, 0
  while true do
    local project = R.EnumProjects(index)
    if not project then break end
    if project ~= state.active_project and Metering.project_valid(project) then
      local master = R.GetMasterTrack(project)
      if Metering.track_valid(project, master)
          and tostring(R.GetTrackGUID(master) or "") == track_guid then matches = matches + 1 end
      for track_index = 0, (R.CountTracks(project) or 0) - 1 do
        local track = R.GetTrack(project, track_index)
        if Metering.track_valid(project, track)
            and tostring(R.GetTrackGUID(track) or "") == track_guid then matches = matches + 1 end
      end
    end
    index = index + 1
  end
  return matches
end

function Metering.resolve_binding(config)
  local state = Runtime.metering
  if config.meter_source_kind == "" then return nil, "SETUP REQUIRED" end
  if config.meter_source_kind == "monitoring" then
    local ordinal = math.max(1, math.floor(tonumber(config.meter_source_ordinal) or 1))
    for _, source in ipairs(state.sources) do
      if source.kind == "monitoring" and source.ordinal == ordinal then
        if source.compatible then return source, nil end
        return source, "METER UPDATE REQUIRED"
      end
    end
    return nil, "SOURCE MISSING"
  end
  local active_track_exists = false
  for _, source in ipairs(state.sources) do
    if source.track_guid == config.meter_track_guid then
      active_track_exists = true
      if source.kind == config.meter_source_kind and source.fx_guid == config.meter_fx_guid then
        if source.compatible then return source, nil end
        return source, "METER UPDATE REQUIRED"
      end
    end
  end
  if not active_track_exists then
    local inactive = Metering.inactive_track_matches(config.meter_track_guid)
    if inactive == 1 then return nil, "SOURCE IN ANOTHER PROJECT" end
    if inactive > 1 then return nil, "SOURCE PROJECT AMBIGUOUS" end
  end
  return nil, "SOURCE MISSING"
end

function Metering.assign_card_source(config, source)
  if not config or not source then return false end
  config.meter_source_kind = source.kind
  config.meter_track_guid = source.kind == "monitoring" and "" or source.track_guid
  config.meter_fx_guid = source.kind == "monitoring" and "" or source.fx_guid
  config.meter_source_ordinal = source.ordinal or 1
  config.meter_last_source_name = source.display_name
  return true
end

function Metering.remember_face_source(source)
  if not source then return end
  settings.meter_face_source_kind = source.kind
  settings.meter_face_track_guid = source.kind == "monitoring" and "" or source.track_guid
  settings.meter_face_fx_guid = source.kind == "monitoring" and "" or source.fx_guid
  settings.meter_face_source_ordinal = source.ordinal or 1
  settings.meter_face_last_source_name = source.display_name
  save_string("meter_face_source_kind", settings.meter_face_source_kind)
  save_string("meter_face_track_guid", settings.meter_face_track_guid)
  save_string("meter_face_fx_guid", settings.meter_face_fx_guid)
  save_string("meter_face_source_ordinal", settings.meter_face_source_ordinal)
  save_string("meter_face_last_source_name", settings.meter_face_last_source_name)
end

function Metering.bind_card(index, source)
  local config = settings.cards[index]
  if not Metering.assign_card_source(config, source) then return false end
  local preserve_face = Runtime.metering.setup_bind_face == true
    and METER_FACE_IDS[settings.active_face] == true
  Content.save_card(index, preserve_face)
  if preserve_face then Metering.remember_face_source(source) end
  Metering.scan_sources(true)
  if recompute_snapshot then recompute_snapshot(true) end
  return true
end

function Metering.bind_active_meter_face(source)
  if not source or not METER_FACE_IDS[settings.active_face] then return 0 end
  local count = 0
  for row = 1, settings.card_rows do
    for column = 1, settings.card_row_counts[row] do
      local index = (row - 1) * CARDS_PER_ROW + column
      local config = settings.cards[index]
      if config and config.type == "meter" then
        Metering.assign_card_source(config, source)
        Content.save_card(index, true)
        count = count + 1
      end
    end
  end
  Metering.remember_face_source(source)
  Metering.scan_sources(true)
  if recompute_snapshot then recompute_snapshot(true) end
  return count
end

function Metering.request_source_setup(card_index, bind_face)
  card_index = math.floor(tonumber(card_index) or 0)
  local config = settings.cards[card_index]
  if not config or config.type ~= "meter" then return false end
  local state = Runtime.metering
  state.setup_request = card_index
  state.setup_bind_face = card_index > 0 and (bind_face == true
    or bind_face == nil and METER_FACE_IDS[settings.active_face] == true)
  state.setup_status, state.setup_error = nil, nil
  return true
end

function Metering.find_source_for_track(track, kind)
  for _, source in ipairs(Runtime.metering.sources) do
    if source.track == track and source.kind == kind and source.compatible then return source end
  end
end

function Metering.insert_on_track(card_index, track, kind)
  local state, project = Runtime.metering, Runtime.metering.active_project
  if not Metering.track_valid(project, track) then return false, "The selected track is no longer available." end
  local ready, verify_detail = Metering.verify_companion()
  if not ready then return false, verify_detail end
  Metering.scan_sources(true)
  local existing = Metering.find_source_for_track(track, kind)
  if existing then Metering.bind_card(card_index, existing) return true, "Reused " .. existing.display_name .. "." end

  local undo = kind ~= "monitoring" and R.Undo_BeginBlock2 and R.Undo_EndBlock2
  if undo then R.Undo_BeginBlock2(project) end
  local added = R.TrackFX_AddByName(track, Metering.fx_name, kind == "monitoring", -1)
  if added < 0 then
    if undo then R.Undo_EndBlock2(project, "Add ReaClock meter", -1) end
    state.operation_error = "REAPER could not instantiate " .. Metering.fx_name
      .. ". Reinstall or update ReaClock in ReaPack, then try again."
    return false, state.operation_error
  end
  if undo then R.Undo_EndBlock2(project, "Add ReaClock meter", -1) end

  Metering.scan_sources(true)
  local source = Metering.find_source_for_track(track, kind)
  if not source then
    state.operation_error = "The meter was added, but its bridge identity could not be verified."
    return false, state.operation_error
  end
  Metering.bind_card(card_index, source)
  local destination = source.kind == "track" and source.track_name or source.display_name
  return true, "Added and verified on " .. destination .. "."
end

function Metering.insert_monitoring(card_index)
  local project = Runtime.metering.active_project
  local master = project and R.GetMasterTrack(project)
  if not Metering.track_valid(project, master) then return false, "The Monitoring FX chain is unavailable." end
  local existing = Metering.find_source_for_track(master, "monitoring")
  if existing then Metering.bind_card(card_index, existing) return true, "Reused the existing output meter." end
  local before = R.TrackFX_GetRecCount(master)
  local okay, detail = Metering.insert_on_track(card_index, master, "monitoring")
  if not okay then return false, detail end

  -- The output meter must observe the unprocessed hardware-monitoring path.
  -- Move only the newly verified compatible instance ahead of room correction
  -- or headphone processing; do not disturb the relative order of other FX.
  Metering.scan_sources(true)
  local source = Metering.find_source_for_track(master, "monitoring")
  if source and source.chain_index ~= 0 and R.TrackFX_GetRecCount(master) > before then
    R.TrackFX_CopyToTrack(master, source.fx_index, master, Metering.rec_offset, true)
    Metering.scan_sources(true)
    source = Metering.find_source_for_track(master, "monitoring")
    if not source or source.chain_index ~= 0 then
      return false, "The output meter was added but could not be moved before the existing Monitoring FX."
    end
    Metering.bind_card(card_index, source)
  end
  return true, detail
end

function Metering.selected_destination()
  local project = Runtime.metering.active_project
  if not Metering.project_valid(project) then return nil, nil, "No active project is available." end
  local master = R.GetMasterTrack(project)
  local master_selected = Metering.track_valid(project, master)
    and (R.GetMediaTrackInfo_Value(master, "I_SELECTED") or 0) > 0.5
  local count = R.CountSelectedTracks(project) or 0
  if master_selected and count == 0 then return master, "master", nil end
  if count ~= 1 or master_selected then
    return nil, nil, count == 0 and "Select one track to add a meter."
      or "Leave exactly one track selected to add one meter."
  end
  return R.GetSelectedTrack(project, 0), "track", nil
end

function Metering.config_references_source(config, source)
  if type(config) ~= "table" or config.type ~= "meter" or not source then return false end
  if source.kind == "monitoring" then
    return config.meter_source_kind == "monitoring"
      and math.floor(tonumber(config.meter_source_ordinal) or 1) == (source.ordinal or 1)
  end
  return config.meter_source_kind == source.kind
    and config.meter_track_guid == source.track_guid
    and config.meter_fx_guid == source.fx_guid
end

function Metering.source_referenced(source)
  for _, config in ipairs(settings.cards or {}) do
    if Metering.config_references_source(config, source) then return true end
  end
  for _, entry in ipairs(settings.detached_cards or {}) do
    if Metering.config_references_source(entry.card, source) then return true end
  end
  for _, face in pairs(Store.root.faces.layouts or {}) do
    for _, config in ipairs(type(face) == "table" and face.cards or {}) do
      if Metering.config_references_source(config, source) then return true end
    end
  end
  return false
end

function Metering.unused_ordinary_sources()
  Metering.scan_sources(true)
  local unused = {}
  for _, source in ipairs(Runtime.metering.sources or {}) do
    if source.kind ~= "monitoring" and not Metering.source_referenced(source) then
      unused[#unused + 1] = source
    end
  end
  table.sort(unused, function(a, b)
    if a.track == b.track then return a.fx_index > b.fx_index end
    if a.track_number ~= b.track_number then return a.track_number > b.track_number end
    return a.fx_index > b.fx_index
  end)
  return unused
end

function Metering.cleanup_unused_ordinary_sources()
  local project = Runtime.metering.active_project
  if not Metering.project_valid(project) then return false, "No active project is available." end
  local unused = Metering.unused_ordinary_sources()
  if #unused == 0 then return true, "No unused track meters were found.", 0 end
  local undo = R.Undo_BeginBlock2 and R.Undo_EndBlock2
  if undo then R.Undo_BeginBlock2(project) end
  local removed = 0
  for _, source in ipairs(unused) do
    if Metering.track_valid(project, source.track)
        and source.project == project and Metering.fx_identity(source.track, source.fx_index) then
      local deleted = R.TrackFX_Delete(source.track, source.fx_index)
      if deleted ~= false then removed = removed + 1 end
    end
  end
  if undo then R.Undo_EndBlock2(project, "Remove unused ReaClock meters", -1) end
  Metering.scan_sources(true)
  if recompute_snapshot then recompute_snapshot(true) end
  if removed ~= #unused then
    return false, string.format("Removed %d of %d unused track meters; another change moved an FX before cleanup finished.",
      removed, #unused), removed
  end
  return true, string.format("Removed %d unused track meter%s. Monitoring FX meters were left in place.",
    removed, removed == 1 and "" or "s"), removed
end

function Metering.run_test_command()
  if not Store.test_override then return end
  local command = R.GetExtState(EXT, "__meter_test_command")
  local state = Runtime.metering
  if command == "" or command == state.last_test_command then return end
  state.last_test_command = command
  R.SetExtState(EXT, "__meter_test_status", "running", false)

  local function export(key, value)
    value = tostring(value == nil and "" or value):gsub("[\r\n]", " ")
    R.SetExtState(EXT, "__meter_test_" .. key, value, false)
  end
  local function perform_insert(monitoring)
    local first_ok, first_detail, second_ok, second_detail
    if monitoring then
      first_ok, first_detail = Metering.insert_monitoring(1)
      second_ok, second_detail = Metering.insert_monitoring(1)
    else
      local track, kind, destination_error = Metering.selected_destination()
      if not track then return false, destination_error or "No destination", false, "not attempted" end
      first_ok, first_detail = Metering.insert_on_track(1, track, kind)
      second_ok, second_detail = Metering.insert_on_track(1, track, kind)
    end
    return first_ok, first_detail, second_ok, second_detail
  end

  local okay, failure = pcall(function()
    local first_ok, first_detail, second_ok, second_detail
    if command:match("^inspect_meter_sources") then
      Metering.scan_sources(true)
      for _, source in ipairs(state.sources or {}) do
        Metering.poll_source(source, { source = source, metrics = {} }, R.time_precise())
      end
      first_ok, first_detail = true, "Meter source states exported."
    elseif command == "verify_companion" then
      first_ok, first_detail = Metering.verify_companion()
    elseif command == "insert_selected_twice" then
      first_ok, first_detail, second_ok, second_detail = perform_insert(false)
    elseif command == "insert_monitoring_twice" then
      first_ok, first_detail, second_ok, second_detail = perform_insert(true)
    elseif command == "cleanup_unused" then
      first_ok, first_detail, second_detail = Metering.cleanup_unused_ordinary_sources()
    elseif command == "select_meter_card" then
      Content.set_card_type(1, "meter", false)
      first_ok = settings.cards[1] and settings.cards[1].type == "meter"
        and (state.setup_request == 1 or state.setup_card == 1)
      first_detail = first_ok and "Metering selection requested its source chooser."
        or "Metering selection did not request its source chooser."
    elseif command == "open_meter_card_editor" then
      Content.open_detail_editor("card", 1)
      first_ok = detail_editor.open == true and detail_editor.kind == "card"
        and tonumber(detail_editor.id) == 1
      first_detail = first_ok and "Meter card editor opened."
        or "Meter card editor did not open."
    elseif command == "create_popout_from_first" then
      local detached_index = Content.create_detached(settings.cards[1], false)
      local entry = detached_index and Content.detached_entry(detached_index)
      first_ok = detached_index ~= nil and entry ~= nil and entry.open == true
      first_detail = first_ok and "Independent pop-out card created."
        or "Independent pop-out card was not created."
      export("detached_index", detached_index)
      export("detached_count", #(settings.detached_cards or {}))
      export("detached_open", entry and entry.open == true)
      export("detached_type", entry and entry.card and entry.card.type or "")
      export("face_card_type", settings.cards[1] and settings.cards[1].type or "")
    elseif command == "move_first_to_popout" then
      local before_count = #(settings.detached_cards or {})
      first_ok = Content.move_card_to_detached_now(1) == true
      local entry = settings.detached_cards[#settings.detached_cards]
      first_detail = first_ok and "Face card moved to an independent pop-out."
        or "Face card was not moved to a pop-out."
      export("detached_count_before", before_count)
      export("detached_count", #(settings.detached_cards or {}))
      export("detached_index", entry and -entry.id or "")
      export("detached_type", entry and entry.card and entry.card.type or "")
      export("face_card_count", settings.card_row_counts[1] or 0)
      export("face_card_type", settings.cards[1] and settings.cards[1].type or "")
    elseif command == "protect_popout_meter_cleanup" then
      local moved = Content.move_card_to_detached_now(1) == true
      local entry = settings.detached_cards[#settings.detached_cards]
      local cleanup_ok, cleanup_detail, removed = Metering.cleanup_unused_ordinary_sources()
      local resolved = entry and Metering.resolve_binding(entry.card)
      first_ok = moved and cleanup_ok and resolved ~= nil
      first_detail = first_ok and "Pop-out-only meter remained protected from cleanup."
        or cleanup_detail
      second_ok, second_detail = cleanup_ok, removed
      export("detached_count", #(settings.detached_cards or {}))
      export("detached_source_resolved", resolved ~= nil)
      export("face_card_count", settings.card_row_counts[1] or 0)
      export("face_card_type", settings.cards[1] and settings.cards[1].type or "")
    elseif command == "move_and_return_first_popout" then
      local original_type = settings.cards[1] and settings.cards[1].type or ""
      local moved = Content.move_card_to_detached_now(1) == true
      local entry = settings.detached_cards[#settings.detached_cards]
      local detached_index = entry and -entry.id
      local returned = moved and detached_index
        and Content.return_detached_now(detached_index) == true
      first_ok = moved and returned
      first_detail = first_ok and "Card moved to a pop-out and returned to the face."
        or "Move/return round trip failed."
      export("roundtrip_original_type", original_type)
      export("roundtrip_returned_type", settings.cards[1] and settings.cards[1].type or "")
      export("detached_count", #(settings.detached_cards or {}))
      export("face_card_count", settings.card_row_counts[1] or 0)
    elseif command == "popout_limit_error" then
      while #settings.detached_cards < 32 do
        local detached_index = Content.create_detached(Content.new_card("length"), false)
        local entry = detached_index and Content.detached_entry(detached_index)
        if not entry then break end
        entry.open = false
      end
      local before_count = #settings.detached_cards
      local moved = Content.move_card_to_detached_now(1)
      first_ok = moved == false and before_count == 32
        and Runtime.detached.error == "ReaClock supports up to 32 independent pop-out cards."
      first_detail = first_ok and "Pop-out limit failure produced visible feedback."
        or "Pop-out limit failure did not preserve the face card and report its reason."
      export("detached_count", #settings.detached_cards)
      export("detached_error", Runtime.detached.error)
      export("face_card_type", settings.cards[1] and settings.cards[1].type or "")
    elseif command == "popout_return_error" then
      local detached_index = Content.create_detached(settings.cards[1], false)
      local entry = detached_index and Content.detached_entry(detached_index)
      if entry then entry.open = false end
      settings.card_rows = MAX_CARD_ROWS
      for row = 1, MAX_CARD_ROWS do
        settings.card_row_counts[row] = CARDS_PER_ROW
        for column = 1, CARDS_PER_ROW do
          settings.cards[(row - 1) * CARDS_PER_ROW + column] = Content.new_card("length")
        end
      end
      local returned = detached_index and Content.return_detached_now(detached_index)
      first_ok = returned == false and Runtime.detached.error
        == "Add room to the face before returning this pop-out card."
      first_detail = first_ok and "Full-face return failure produced visible feedback."
        or "Full-face return failure did not preserve the pop-out and report its reason."
      export("detached_count", #settings.detached_cards)
      export("detached_error", Runtime.detached.error)
      export("detached_open", entry and entry.open == true)
    elseif command == "fullscreen_first" then
      local config = settings.cards[1]
      first_ok = config and config.type == "meter"
        and config.meter_display ~= "numeric"
      if first_ok then
        Runtime.card_fullscreen = { index = 1, opened_at = R.time_precise() }
      end
      first_detail = first_ok and "Visualization entered fullscreen."
        or "Visualization did not enter fullscreen."
      export("fullscreen_index", Runtime.card_fullscreen and Runtime.card_fullscreen.index or "")
    else
      error("Unknown meter test command: " .. command)
    end
    Metering.scan_sources(true)
    local paths = Metering.companion_paths()
    export("first_ok", first_ok == true)
    export("first_detail", first_detail)
    export("second_ok", second_ok == nil and "" or second_ok == true)
    export("second_detail", second_detail)
    export("source_count", #(state.sources or {}))
    export("card_source_kind", settings.cards[1] and settings.cards[1].meter_source_kind or "")
    export("card_source_ordinal", settings.cards[1] and settings.cards[1].meter_source_ordinal or "")
    export("card_track_guid", settings.cards[1] and settings.cards[1].meter_track_guid or "")
    export("card_fx_guid", settings.cards[1] and settings.cards[1].meter_fx_guid or "")
    export("card_type", settings.cards[1] and settings.cards[1].type or "")
    export("setup_request", state.setup_request)
    export("setup_card", state.setup_card)
    export("companion_present", Metering.file_exists(paths.destination))
    local current_count, pending_count, incompatible_count, update_required_count = 0, 0, 0, 0
    for _, source in ipairs(state.sources or {}) do
      if source.current_build then current_count = current_count + 1 end
      if source.update_pending then pending_count = pending_count + 1 end
      if not source.bridge_compatible then incompatible_count = incompatible_count + 1 end
      if source.runtime and source.runtime.status == "METER UPDATE REQUIRED" then
        update_required_count = update_required_count + 1
      end
    end
    export("source_current_count", current_count)
    export("source_pending_count", pending_count)
    export("source_incompatible_count", incompatible_count)
    export("source_update_required_count", update_required_count)
    export("operation_status", state.operation_status or "")
  end)
  export("error", okay and "" or failure)
  R.SetExtState(EXT, "__meter_test_status", okay and "done" or "error", false)
end

function Metering.command_base(source)
  local runtime = source and source.runtime
  local slot = runtime and tonumber(runtime.slot)
  if not slot or slot < 0 or slot >= Metering.command.slot_count then return nil end
  return Metering.command.slot_base + math.floor(slot) * Metering.command.slot_stride
end

function Metering.command_valid(source)
  local base = Metering.command_base(source)
  local token = source and source.runtime and tonumber(source.runtime.token)
  if not base or not token or not Runtime.metering.gmem_attached then return false end
  return R.gmem_read(0) == Metering.command.magic
    and R.gmem_read(1) == Metering.command.api
    and R.gmem_read(base) == token
end

function Metering.theme_channels(color)
  color = math.floor(tonumber(color) or 0)
  return ((color >> 24) & 0xFF) / 255,
    ((color >> 16) & 0xFF) / 255,
    ((color >> 8) & 0xFF) / 255
end

function Metering.theme_state()
  local background = math.floor(tonumber(settings.theme_background) or 0)
  local text = math.floor(tonumber(settings.theme_text) or 0)
  local accent = math.floor(tonumber(settings.theme_highlight) or 0)
  local key = string.format("%08X:%08X:%08X", background, text, accent)
  local signature = ((background >> 8) * 3 + (text >> 8) * 5 + (accent >> 8) * 7)
    % Metering.theme.prime
  local br, bg, bb = Metering.theme_channels(background)
  local tr, tg, tb = Metering.theme_channels(text)
  local ar, ag, ab = Metering.theme_channels(accent)
  return key, signature, { br, bg, bb, tr, tg, tb, ar, ag, ab }
end

function Metering.sync_themes(now)
  local state = Runtime.metering
  if not state.gmem_attached then return end
  now = now or R.time_precise()
  local key, signature, channels = Metering.theme_state()
  local changed = key ~= state.theme_key
  if not changed and now - (state.last_theme_sync or -math.huge) < 1 then return end

  for _, source in ipairs(state.sources or {}) do
    local runtime = source.runtime
    runtime.slot = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
      Metering.param.slot) or -1)
    runtime.token = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
      Metering.param.token) or 0)
    if source.compatible and Metering.command_valid(source) then
      local base = Metering.theme.base + math.floor(runtime.slot) * Metering.theme.stride
      local current = R.gmem_read(base) == Metering.theme.magic
        and R.gmem_read(base + 1) == runtime.token
        and R.gmem_read(base + 2) == signature
      if changed or not current then
        -- Invalidate first so @gfx never adopts a half-written palette.
        R.gmem_write(base, 0)
        R.gmem_write(base + 1, runtime.token)
        R.gmem_write(base + 2, signature)
        for index, value in ipairs(channels) do R.gmem_write(base + 2 + index, value) end
        R.gmem_write(base, Metering.theme.magic)
      end
    end
  end
  state.theme_key, state.last_theme_sync = key, now
end

function Metering.next_counter(value)
  return (math.floor(tonumber(value) or 0) + 1) % Metering.command.counter_mod
end

function Metering.request_reset(source, reason)
  if not source or not Metering.command_valid(source) then return false, "Meter command is unavailable." end
  local runtime, base = source.runtime, Metering.command_base(source)
  if runtime.pending_reset ~= nil then return false, "A meter reset is already pending." end
  local request = Metering.next_counter(runtime.last_reset_request_written
    or R.gmem_read(base + 2))
  R.gmem_write(base + 2, request)
  if R.gmem_read(base + 2) ~= request or R.gmem_read(base) ~= runtime.token then
    return false, "The meter changed identity before the reset could be sent."
  end
  runtime.last_reset_request_written = request
  runtime.pending_reset = request
  runtime.pending_reset_since = R.time_precise()
  runtime.pending_reset_epoch = runtime.epoch
  runtime.pending_reset_reason = reason or "manual"
  if Store.test_override then
    local test_root = os.getenv("CIVIL_CLOCK_TEST_ROOT") or ""
    if test_root ~= "" then
      local file = io.open(test_root .. "\\meter-reset-requests.txt", "ab")
      if file then
        file:write(string.format("reason=%s request=%d epoch=%s\n",
          tostring(runtime.pending_reset_reason), request, tostring(runtime.epoch or "")))
        file:close()
      end
    end
  end
  return true, request
end

function Metering.project_playback_summary()
  local state = Runtime.metering
  if not R.GetPlayStateEx or not R.EnumProjects then
    local playing = ((R.GetPlayState() or 0) & (1 | 4)) ~= 0
    return playing, false, playing and 1 or 0,
      playing and state.active_project or nil
  end
  local active_playing, background_playing = false, false
  local running_count, sole_project, index = 0, nil, 0
  while true do
    local project = R.EnumProjects(index)
    if not project then break end
    if Metering.project_valid(project) then
      local play_state = R.GetPlayStateEx(project) or 0
      if (play_state & (1 | 4)) ~= 0 then
        running_count, sole_project = running_count + 1, project
        if project == state.active_project then active_playing = true
        else background_playing = true end
      end
    end
    index = index + 1
  end
  return active_playing, background_playing, running_count,
    running_count == 1 and sole_project or nil
end

function Metering.monitoring_outside_active_project(source)
  local state = Runtime.metering
  return source and source.kind == "monitoring"
    and state.output_project ~= state.active_project
end

function Metering.compact_history(history, key, head_key)
  local head = history[head_key] or 1
  local values = history[key]
  if head > 256 and head > #values * 0.25 then
    local compacted = {}
    for index = head, #values do compacted[#compacted + 1] = values[index] end
    history[key], history[head_key] = compacted, 1
  end
end

function Metering.append_numeric_history(runtime, need, now)
  if runtime.status or runtime.epoch == nil then return end
  if need.history then
    local history = runtime.loudness_history
    if not history or history.epoch ~= runtime.epoch then
      history = { epoch = runtime.epoch, recent = {}, archive = {},
        recent_head = 1, archive_head = 1, last_archive_second = nil }
      runtime.loudness_history = history
    end
    local values = runtime.values or {}
    local point = { time = now, m = values.lufs_m, s = values.lufs_s, i = values.lufs_i }
    history.recent[#history.recent + 1] = point
    local second = math.floor(now)
    if history.last_archive_second ~= second then
      history.archive[#history.archive + 1] = point
      history.last_archive_second = second
    end
    while history.recent[history.recent_head]
        and now - history.recent[history.recent_head].time > 180 do
      history.recent_head = history.recent_head + 1
    end
    while history.archive[history.archive_head]
        and now - history.archive[history.archive_head].time > 7200 do
      history.archive_head = history.archive_head + 1
    end
    Metering.compact_history(history, "recent", "recent_head")
    Metering.compact_history(history, "archive", "archive_head")
  end
  if need.correlation and runtime.values and runtime.values.correlation then
    local history = runtime.correlation_history
    if not history or history.epoch ~= runtime.epoch then
      history = { epoch = runtime.epoch, values = {}, head = 1 }
      runtime.correlation_history = history
    end
    history.values[#history.values + 1] = {
      time = now, value = math.max(-1, math.min(1, runtime.values.correlation)),
    }
    while history.values[history.head]
        and now - history.values[history.head].time > 60 do history.head = history.head + 1 end
    if history.head > 256 and history.head > #history.values * 0.25 then
      local compacted = {}
      for index = history.head, #history.values do compacted[#compacted + 1] = history.values[index] end
      history.values, history.head = compacted, 1
    end
  end
end

function Metering.poll_source(source, need, now)
  if source.project ~= Runtime.metering.active_project
      or not Metering.track_valid(source.project, source.track) then
    source.runtime.status = "SOURCE MISSING"
    Runtime.metering.last_scan = -math.huge
    return
  end
  local current_guid = tostring(R.TrackFX_GetFXGUID(source.track, source.fx_index) or "")
  local exact = Metering.fx_identity(source.track, source.fx_index)
  if not exact or source.kind ~= "monitoring" and current_guid ~= source.fx_guid then
    source.runtime.status = "SOURCE MOVED OR MISSING"
    Runtime.metering.last_scan = -math.huge
    return
  end
  local runtime, param = source.runtime, Metering.param
  source.enabled = R.TrackFX_GetEnabled(source.track, source.fx_index)
  source.offline = R.TrackFX_GetOffline(source.track, source.fx_index)
  runtime.status = source.offline and "METER OFFLINE"
    or (not source.enabled and "METER BYPASSED" or nil)
  runtime.api = source.has_api_param
    and R.TrackFX_GetParam(source.track, source.fx_index, param.api) or 0
  runtime.build = source.has_build_param
    and R.TrackFX_GetParam(source.track, source.fx_index, param.build) or 0
  source.api_version, source.build_version = runtime.api, runtime.build
  source.bridge_compatible = source.has_api_param and source.has_epoch_param
    and math.floor((tonumber(runtime.api) or 0) + 0.5) == Metering.api_version
  source.current_build = source.bridge_compatible and source.has_build_param
    and math.floor((tonumber(runtime.build) or 0) + 0.5) == Metering.companion_build
  source.update_pending = source.bridge_compatible and not source.current_build
  source.compatible = source.bridge_compatible
  if not source.bridge_compatible then
    runtime.status = "METER UPDATE REQUIRED"
  end
  runtime.reset_ack = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
    param.reset_ack) or 0) % Metering.command.counter_mod
  runtime.valid_mask = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
    param.valid_mask) or 0)
  runtime.heartbeat = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
    param.heartbeat) or 0)
  runtime.channels = math.max(0, math.floor(R.TrackFX_GetParam(source.track,
    source.fx_index, param.channels) or 0))
  runtime.slot = math.floor(R.TrackFX_GetParam(source.track, source.fx_index, param.slot) or -1)
  runtime.token = math.floor(R.TrackFX_GetParam(source.track, source.fx_index, param.token) or 0)
  runtime.arm_ack = math.floor(R.TrackFX_GetParam(source.track, source.fx_index,
    param.arm_ack) or 0) % Metering.command.counter_mod
  local epoch = math.floor(R.TrackFX_GetParam(source.track, source.fx_index, param.epoch) or 0)
    % Metering.command.counter_mod
  if runtime.epoch ~= nil and runtime.epoch ~= epoch then
    runtime.history_epoch_changed = true
    runtime.values = runtime.values or {}
  end
  runtime.epoch = epoch
  if runtime.heartbeat ~= runtime.last_heartbeat then
    runtime.last_heartbeat, runtime.last_heartbeat_at = runtime.heartbeat, now
  end
  local expected = source.kind == "monitoring"
    and (not R.Audio_IsRunning or R.Audio_IsRunning() ~= 0)
    or ((R.GetPlayStateEx and R.GetPlayStateEx(source.project) or R.GetPlayState()) & (1 | 4)) ~= 0
  if expected and now - (runtime.last_heartbeat_at or now) > 2.5
      and not runtime.status then runtime.status = "METER NOT RESPONDING" end

  runtime.values = runtime.values or {}
  for metric in pairs(need.metrics or {}) do
    local index = param[metric]
    if index then runtime.values[metric] = R.TrackFX_GetParam(source.track, source.fx_index, index) end
  end
  if need.history then
    for _, metric in ipairs({ "lufs_m", "lufs_s", "lufs_i" }) do
      runtime.values[metric] = R.TrackFX_GetParam(source.track, source.fx_index, param[metric])
    end
  end
  if need.correlation then
    runtime.values.correlation = R.TrackFX_GetParam(source.track, source.fx_index, param.correlation)
  end
  if need.true_peak then
    runtime.values.true_peak = R.TrackFX_GetParam(source.track, source.fx_index, param.true_peak)
    runtime.values.true_peak_max = R.TrackFX_GetParam(source.track, source.fx_index,
      param.true_peak_max)
  end

  if runtime.pending_reset ~= nil and runtime.reset_ack == runtime.pending_reset
      and runtime.epoch ~= runtime.pending_reset_epoch then
    runtime.pending_reset = nil
    runtime.reset_completed_at = now
    runtime.reset_completed_reason = runtime.pending_reset_reason
    runtime.pending_reset_reason = nil
  end

  if source.kind == "monitoring" then
    local state = Runtime.metering
    if state.playing_project_count > 1 then
      runtime.contaminated = true
      runtime.cleanup_request = nil
      runtime.cleanup_baseline_epoch = nil
      if state.active_playing then runtime.status = "MULTIPLE PROJECTS PLAYING" end
    elseif Metering.monitoring_outside_active_project(source) then
      -- Monitoring FX are global, but ReaClock remains scoped to the selected
      -- project tab. Keep the other tab's output hidden until its project is
      -- selected, including after that project's transport stops.
    elseif runtime.contaminated then
      if runtime.pending_reset ~= nil then
        runtime.status = "RESTARTING OUTPUT METER"
      elseif runtime.cleanup_request == nil then
        runtime.cleanup_baseline_epoch = runtime.epoch
        local sent, request = Metering.request_reset(source, "multiple_project_playback_ended")
        if sent then runtime.cleanup_request = request end
        runtime.status = sent and "RESTARTING OUTPUT METER" or "WAITING FOR PRIOR METER RESET"
      elseif runtime.reset_ack == runtime.cleanup_request
          and runtime.epoch ~= runtime.cleanup_baseline_epoch then
        runtime.contaminated = false
        runtime.cleanup_request, runtime.cleanup_baseline_epoch = nil, nil
        runtime.restarted_until = now + 2
        runtime.status = nil
      else
        runtime.status = "RESTARTING OUTPUT METER"
      end
    end
  end

  if runtime.pending_reset ~= nil and not runtime.status then runtime.status = "RESET PENDING" end
  Metering.append_numeric_history(runtime, need, now)
end

function Metering.collect_needs()
  local needs = {}
  Runtime.each_active_card(function(_, config)
      local custom_metrics = config.type == "custom"
        and Metering.template_metric_ids(config.template) or {}
      if config.type == "meter" or #custom_metrics > 0 then
        local source = Metering.resolve_binding(config)
        if source then
          local need = needs[source.key]
          if not need then need = { source = source, metrics = {} }; needs[source.key] = need end
          if #custom_metrics > 0 then
            for _, metric_id in ipairs(custom_metrics) do need.metrics[metric_id] = true end
          elseif config.meter_display == "numeric" then
            need.metrics[config.meter_metric] = true
          elseif config.meter_display == "history" then
            need.history = true
          elseif config.meter_display == "correlation" then
            need.correlation = true
          else
            need.visual = true
          end
          local metric = Metering.metrics[config.meter_metric]
          if metric and metric.true_peak or config.meter_level_true_peak_marker then
            need.true_peak = true
          end
        end
      end
  end)
  return needs
end

function Metering.refresh_true_peak_lease(source, demanded, now)
  local runtime = source.runtime
  if not Metering.command_valid(source) then return end
  local base = Metering.command_base(source)
  if demanded then
    if not runtime.true_peak_lease_on or now - (runtime.true_peak_lease_at or -math.huge) >= 0.8 then
      local sequence = Metering.next_counter(R.gmem_read(base + 3))
      R.gmem_write(base + 4, 1)
      R.gmem_write(base + 3, sequence)
      runtime.true_peak_lease_on, runtime.true_peak_lease_at = true, now
    end
  elseif runtime.true_peak_lease_on then
    local sequence = Metering.next_counter(R.gmem_read(base + 3))
    R.gmem_write(base + 4, 0)
    R.gmem_write(base + 3, sequence)
    runtime.true_peak_lease_on, runtime.true_peak_lease_at = false, now
  end
end

function Metering.arm_stopped_sources(needs)
  local state = Runtime.metering
  local running = state.active_playing
  if state.transport_running and not running then
    state.transport_generation = Metering.next_counter(state.transport_generation)
  end
  state.transport_running = running
  if running then return end
  for _, need in pairs(needs) do
    local source, runtime = need.source, need.source.runtime
    if not (source.kind == "monitoring" and state.background_playing)
        and runtime.last_arm_generation ~= state.transport_generation
        and Metering.command_valid(source) then
      local enabled = R.TrackFX_GetParam(source.track, source.fx_index,
        Metering.param.reset_on_transport)
      if enabled and enabled >= 0.5 then
        local base = Metering.command_base(source)
        R.gmem_write(base + 7, state.transport_generation)
      end
      runtime.last_arm_generation = state.transport_generation
    end
  end
end

function Metering.update(now)
  local state = Runtime.metering
  now = now or R.time_precise()
  if not state.companion_checked then
    if Store.test_override
        and R.GetExtState(EXT, "__meter_test_skip_companion_ensure") == "1" then
      state.companion_checked = true
      state.companion_installed = { ready = true, code = "ready", detail = "Test override" }
    else
      Metering.ensure_companion()
    end
  end
  Metering.update_companion_reload(now)
  local active = R.EnumProjects and R.EnumProjects(-1) or 0
  if active ~= state.active_project then
    if Metering.Visual and Metering.Visual.release_all then
      Metering.Visual.release_all(true)
    end
    state.active_project = active
    state.active_project_token = Metering.project_token(active)
    state.sources, state.source_by_key = {}, {}
    state.last_scan, state.last_poll, state.last_theme_sync, state.last_project_change =
      -math.huge, -math.huge, -math.huge, -1
  end
  if not state.gmem_attached and R.gmem_attach then
    -- ReaScript's gmem_attach is a command-style API and commonly returns nil
    -- even when attachment succeeds. Treat a non-throwing call as success;
    -- an explicit false remains a failure for forward-compatible bindings.
    local okay, attached = pcall(R.gmem_attach, Metering.gmem_name)
    state.gmem_attached = okay and attached ~= false
  end
  Metering.scan_sources(false)
  Metering.check_loaded_companion_reloads(now)
  Metering.run_test_command()
  local active_playing, background_playing, playing_project_count, sole_project =
    Metering.project_playback_summary()
  local output_project = state.output_project
  if playing_project_count == 1 then
    output_project = sole_project
  elseif playing_project_count > 1
      or output_project and not Metering.project_valid(output_project) then
    output_project = nil
  end
  if active_playing ~= state.active_playing
      or background_playing ~= state.background_playing
      or playing_project_count ~= state.playing_project_count
      or output_project ~= state.output_project then
    state.active_playing, state.background_playing = active_playing, background_playing
    state.playing_project_count, state.output_project = playing_project_count, output_project
    if state.visual then state.visual.compile_dirty = true end
  end
  local needs = Metering.collect_needs()
  if now - state.last_poll >= 0.1 then
    for _, need in pairs(needs) do Metering.poll_source(need.source, need, now) end
    for _, source in ipairs(state.sources) do
      Metering.refresh_true_peak_lease(source,
        needs[source.key] and needs[source.key].true_peak == true, now)
    end
    Metering.arm_stopped_sources(needs)
    state.last_poll = now
  end
  Metering.sync_themes(now)
  state.needs = needs
  if Metering.Visual and Metering.Visual.update then Metering.Visual.update(now) end
end

function Metering.format_value(metric, value)
  local definition = Metering.metrics[metric]
  if not definition or type(value) ~= "number" or value ~= value then return "" end
  if definition.unit ~= "LU" and value <= -149 then return "" end
  return string.format("%.1f %s", value, definition.unit)
end

function Metering.card_content(config, card_index)
  local source, binding_status = Metering.resolve_binding(config)
  local definition = Metering.metrics[config.meter_metric] or Metering.metrics.lufs_i
  local fallback_source = config.meter_last_source_name ~= "" and config.meter_last_source_name:upper()
    or "METER"
  local resettable = config.meter_display == "numeric" and definition.reset == true
    or config.meter_display == "history"
    or config.meter_display == "levels" and config.meter_level_peak_max == true
  local content = {
    visible = true, label = fallback_source .. " - " .. definition.label,
    value = binding_status or "SETUP REQUIRED", font = "mono", fit_mode = "shrink",
    fit_reference = "-888.8 dBFS", meter = true, meter_display = config.meter_display,
    resettable = resettable,
  }
  if not source then
    content.value = binding_status == "SETUP REQUIRED" and "CHOOSE A SOURCE"
      or binding_status or "SOURCE MISSING"
    content.resettable = false
    content.setup_required = binding_status ~= "SOURCE IN ANOTHER PROJECT"
    content.setup_status = binding_status
    return content
  end
  content.label = source.short_name .. " - " .. (config.meter_display == "numeric"
    and definition.label or config.meter_display:upper())
  content.meter_source, content.meter_source_key = source, source.key
  local runtime = source.runtime
  if binding_status or runtime.status then
    content.value = binding_status or (runtime.pending_reset ~= nil and "" or runtime.status)
    content.resettable = false
    content.setup_required = binding_status ~= nil
    content.setup_status = binding_status
    return content
  end
  if Metering.monitoring_outside_active_project(source) then
    content.value = ""
    content.resettable = false
    content.keep_visible = true
    return content
  end
  if runtime.reset_completed_at
      and R.time_precise() - runtime.reset_completed_at < 1 then
    content.value = ""
    return content
  end
  if runtime.restarted_until and R.time_precise() < runtime.restarted_until then
    content.value = "MEASUREMENT RESTARTED"
    return content
  end
  if config.meter_display ~= "numeric" then
    local stream = card_index and Runtime.metering.visual.card_streams[card_index] or nil
    if stream and stream.error then
      content.value, content.resettable = stream.error, false
      return content
    end
    if config.meter_display ~= "history" and config.meter_display ~= "correlation"
        and (not stream or not stream.frame) then
      content.value = "VISUALIZER STARTING"
      return content
    end
    content.value = " "
    content.visualization = {
      display = config.meter_display, source = source, stream = stream,
      config = config, card_index = card_index,
    }
    return content
  end
  if (runtime.valid_mask & definition.valid) == 0 then
    content.value = ""
    return content
  end
  content.value = Metering.format_value(config.meter_metric,
    runtime.values and runtime.values[config.meter_metric])
  return content
end

Metering.Visual = {
  header = 131088, magic = 52611, api = 4,
  source_base = 262144, source_stride = 48,
  lane_base = 1048576, lane_count = 64, lane_stride = 73728,
  lane_header = 64, bank_size = 3072,
  spectrum_history_offset = 6208, spectrum_history_capacity = 256,
  spectrum_history_entry_size = 260,
  prime_a = 16777213, prime_b = 16777199,
  demand = { levels = 1, waveform = 2, spectrum = 4, vectorscope = 8,
    correlation = 16 },
  mode = { auto = 0, mono = 1, pair = 2, all = 3 },
  quality = { auto = 0, low = 1, standard = 2, high = 3, maximum = 4 },
  timebase = { [10] = 0, [25] = 1, [50] = 2, [100] = 3, [250] = 4 },
  fft = { [1024] = 0, [2048] = 1, [4096] = 2, [8192] = 3 },
  profile_limit = 4,
}

do
  local seed = math.floor((R.time_precise() * 1000000 + (command_id or 0) * 7919) % 16777213)
  Runtime.metering.visual = {
    controller = 1 + seed,
    token_state = (seed * 48271 + 17) % 16777213,
    generation = 0, lease_sequence = 0,
    streams = {}, card_streams = {}, card_data = {}, source_signatures = {},
    source_leases = {}, lane_generations = {}, header_written = false,
    profiles = {}, profile_budget = {}, compile_dirty = true, last_compile = -math.huge,
  }
end

function Metering.Visual.finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

function Metering.Visual.exact_integer(value)
  return Metering.Visual.finite(value) and value == math.floor(value)
end

function Metering.Visual.mod(value, prime)
  return value - math.floor(value / prime) * prime
end

function Metering.Visual.quantize(value)
  return value >= 0 and math.floor(value * 1000 + 0.5)
    or -math.floor(-value * 1000 + 0.5)
end

function Metering.Visual.hash(a, b, value, index)
  local q = Metering.Visual.quantize(value)
  return Metering.Visual.mod(a + q, Metering.Visual.prime_a),
    Metering.Visual.mod(b + (index + 1) * q, Metering.Visual.prime_b)
end

function Metering.Visual.next_token()
  local visual = Runtime.metering.visual
  visual.token_state = (visual.token_state * 48271 + 1) % 16777213
  return visual.token_state + 1
end

function Metering.Visual.next_generation()
  local visual = Runtime.metering.visual
  visual.generation = (visual.generation + 1) % 65536
  if visual.generation == 0 then visual.generation = 1 end
  return visual.generation
end

function Metering.Visual.source_record(source)
  local slot = source and source.runtime and source.runtime.slot
  if not slot then return nil end
  return Metering.Visual.source_base + math.floor(slot) * Metering.Visual.source_stride
end

function Metering.Visual.lane_address(lane)
  return Metering.Visual.lane_base + lane * Metering.Visual.lane_stride
end

function Metering.Visual.bank_address(lane, bank)
  return Metering.Visual.lane_address(lane) + Metering.Visual.lane_header
    + bank * Metering.Visual.bank_size
end

function Metering.Visual.write_header()
  if not Runtime.metering.gmem_attached then return false end
  local visual, now = Runtime.metering.visual, R.time_precise()
  if visual.header_written and now - (visual.header_written_at or -math.huge) < 1 then
    return true
  end
  local v = Metering.Visual
  R.gmem_write(v.header, v.magic)
  R.gmem_write(v.header + 1, v.api)
  R.gmem_write(v.header + 2, v.source_base)
  R.gmem_write(v.header + 3, v.source_stride)
  R.gmem_write(v.header + 4, v.lane_base)
  R.gmem_write(v.header + 5, v.lane_count)
  R.gmem_write(v.header + 6, v.lane_stride)
  R.gmem_write(v.header + 7, v.bank_size)
  visual.header_written, visual.header_written_at = true, now
  return true
end

function Metering.Visual.revoke_lane(stream)
  if not stream or stream.lane == nil or not Runtime.metering.gmem_attached then return end
  local base = Metering.Visual.lane_address(stream.lane)
  R.gmem_write(base + 6, 0)
  R.gmem_write(base + 8, 0)
  R.gmem_write(base + 2, 0)
  R.gmem_write(base + 5, Metering.Visual.next_generation())
end

function Metering.Visual.detach_spectrogram(ring)
  if not ring or not R.ImGui_Detach then return end
  for _, key in ipairs({ "image", "tail_image" }) do
    if ring[key] then pcall(R.ImGui_Detach, ctx, ring[key]) end
    ring[key] = nil
  end
end

function Metering.Visual.release_all(project_switch)
  local visual = Runtime.metering.visual
  if not visual then return end
  for _, stream in pairs(visual.streams) do Metering.Visual.revoke_lane(stream) end
  if not project_switch then
    for key in pairs(visual.source_signatures) do
      local source = Runtime.metering.source_by_key[key]
      local record = source and Metering.Visual.source_record(source)
      if record and Metering.command_valid(source) then
        R.gmem_write(record + 2, 0)
        R.gmem_write(record + 3, 0)
        R.gmem_write(record, 0)
        R.gmem_write(record + 6, 0)
      end
    end
  end
  for _, cache in pairs(visual.card_data or {}) do
    Metering.Visual.detach_spectrogram(cache.spectrogram)
  end
  visual.streams, visual.card_streams = {}, {}
  visual.card_data = {}
  visual.source_signatures, visual.source_leases, visual.profiles = {}, {}, {}
  visual.profile_budget = {}
  visual.compile_dirty = true
end

function Metering.Visual.profile_for(config, display)
  local v = Metering.Visual
  local demand = v.demand[display]
  if display == "levels" then demand = v.demand.levels end
  if display == "spectrogram" then demand = v.demand.spectrum end
  local mode_name = config.meter_channel_mode
  if display == "levels" then mode_name = "all" end
  if display == "vectorscope" or display == "correlation" then
    if mode_name ~= "pair" then mode_name = "auto" end
  end
  local mode = v.mode[mode_name] or v.mode.auto
  local channel_a = (mode == v.mode.auto or mode == v.mode.all) and -1
    or math.max(0, math.min(63, math.floor(config.meter_channel_a or 1) - 1))
  local channel_b = mode ~= v.mode.pair and -1
    or math.max(0, math.min(63, math.floor(config.meter_channel_b or 2) - 1))
  local timebase = v.timebase[math.floor(config.meter_waveform_timebase or 50)] or 2
  local fft = v.fft[math.floor(config.meter_spectrum_fft_size or 4096)] or 2
  local quality = v.quality[config.meter_visual_quality] or 0
  return {
    demand = demand, mode = mode, channel_a = channel_a, channel_b = channel_b,
    timebase = timebase, fft = fft, quality = quality,
  }
end

function Metering.Visual.profile_key(source, profile)
  local v = Metering.Visual
  local timebase = (profile.demand & v.demand.waveform) ~= 0 and profile.timebase or -1
  local fft = (profile.demand & v.demand.spectrum) ~= 0 and profile.fft or -1
  return table.concat({ source.key, profile.mode, profile.channel_a, profile.channel_b,
    timebase, fft, profile.quality }, "|")
end

function Metering.Visual.profiles_compatible(existing, candidate)
  local v = Metering.Visual
  if existing.mode ~= candidate.mode or existing.channel_a ~= candidate.channel_a
      or existing.channel_b ~= candidate.channel_b or existing.quality ~= candidate.quality then
    return false
  end
  local existing_wave = (existing.demand & v.demand.waveform) ~= 0
  local candidate_wave = (candidate.demand & v.demand.waveform) ~= 0
  if existing_wave and candidate_wave and existing.timebase ~= candidate.timebase then return false end
  local existing_spectrum = (existing.demand & v.demand.spectrum) ~= 0
  local candidate_spectrum = (candidate.demand & v.demand.spectrum) ~= 0
  if existing_spectrum and candidate_spectrum and existing.fft ~= candidate.fft then return false end
  return true
end

function Metering.Visual.merge_profile(existing, candidate)
  local v = Metering.Visual
  if (existing.demand & v.demand.waveform) == 0
      and (candidate.demand & v.demand.waveform) ~= 0 then
    existing.timebase = candidate.timebase
  end
  if (existing.demand & v.demand.spectrum) == 0
      and (candidate.demand & v.demand.spectrum) ~= 0 then
    existing.fft = candidate.fft
  end
  existing.demand = existing.demand | candidate.demand
end

function Metering.Visual.allocate_lane(used)
  for lane = 0, Metering.Visual.lane_count - 1 do
    if not used[lane] then return lane end
  end
end

function Metering.Visual.assign_lane(stream, used)
  if stream.lane ~= nil and (not used[stream.lane] or used[stream.lane] == stream) then
    used[stream.lane] = stream
    return true
  end
  local lane = Metering.Visual.allocate_lane(used)
  if lane == nil then return false end
  stream.lane, stream.token = lane, Metering.Visual.next_token()
  stream.generation = Metering.Visual.next_generation()
  stream.sequence, stream.frame, stream.invalid_count = 0, nil, 0
  used[lane] = stream
  local base, visual = Metering.Visual.lane_address(lane), Runtime.metering.visual
  R.gmem_write(base + 6, 0)
  R.gmem_write(base + 8, 0)
  R.gmem_write(base, Metering.Visual.magic)
  R.gmem_write(base + 1, Metering.Visual.api)
  R.gmem_write(base + 2, stream.token)
  R.gmem_write(base + 3, stream.source.runtime.token)
  R.gmem_write(base + 4, visual.controller)
  R.gmem_write(base + 5, stream.generation)
  R.gmem_write(base + 7, 0)
  R.gmem_write(base + 9, 0)
  R.gmem_write(base + 10, 0)
  R.gmem_write(base + 11, 0)
  R.gmem_write(base + 12, 0)
  R.gmem_write(base + 13, -1)
  R.gmem_write(base + 14, 0)
  return true
end

function Metering.Visual.compile()
  local visual = Runtime.metering.visual
  local requested, card_streams = {}, {}
  Runtime.each_active_card(function(index, config)
      if config.type == "meter" and config.meter_display ~= "numeric"
          and config.meter_display ~= "history" then
        local source = Metering.resolve_binding(config)
        if source and source.compatible and not source.runtime.status
            and not Metering.monitoring_outside_active_project(source) then
          local default_correlation = config.meter_display == "correlation"
            and config.meter_channel_mode ~= "pair"
          if not default_correlation then
            local profile = Metering.Visual.profile_for(config, config.meter_display)
            local entry
            for _, candidate in ipairs(requested) do
              if candidate.source.key == source.key
                  and Metering.Visual.profiles_compatible(candidate.profile, profile) then
                entry = candidate
                break
              end
            end
            if entry then
              Metering.Visual.merge_profile(entry.profile, profile)
            else
              entry = { source = source, profile = profile, cards = {}, order = index }
              requested[#requested + 1] = entry
            end
            entry.cards[#entry.cards + 1] = index
          end
        end
      end
  end)

  local per_source = {}
  for _, request in ipairs(requested) do
    local key = Metering.Visual.profile_key(request.source, request.profile)
    local list = per_source[request.source.key]
    if not list then list = {}; per_source[request.source.key] = list end
    list[#list + 1] = { key = key, request = request }
  end
  for _, list in pairs(per_source) do
    table.sort(list, function(a, b)
      if a.request.order == b.request.order then return a.key < b.key end
      return a.request.order < b.request.order
    end)
  end

  local profile_budget = {}
  for source_key, list in pairs(per_source) do
    profile_budget[source_key] = {
      requested = #list,
      used = math.min(#list, Metering.Visual.profile_limit),
      limit = Metering.Visual.profile_limit,
    }
  end

  -- Retire obsolete profiles before a replacement is allowed to claim their
  -- lanes. Previously a quality change could allocate the old lane to the new
  -- stream and then revoke that same lane while cleaning up the old stream,
  -- leaving the replacement permanently stuck on VISUAL DATA UNSTABLE.
  local accepted, used = {}, {}
  for _, list in pairs(per_source) do
    for position, item in ipairs(list) do
      if position <= Metering.Visual.profile_limit then accepted[item.key] = true end
    end
  end
  for key, stream in pairs(visual.streams) do
    if not accepted[key] then
      Metering.Visual.revoke_lane(stream)
      stream.lane = nil
    elseif stream.lane ~= nil then
      used[stream.lane] = stream
    end
  end

  local kept = {}
  for source_key, list in pairs(per_source) do
    for position, item in ipairs(list) do
      if position <= Metering.Visual.profile_limit then
        local stream = visual.streams[item.key] or {
          key = item.key, source = item.request.source, profile = item.request.profile,
          created_at = R.time_precise(), histories = {},
        }
        stream.source, stream.profile = item.request.source, item.request.profile
        stream.profile_budget = profile_budget[source_key]
        if Metering.Visual.assign_lane(stream, used) then
          kept[item.key] = stream
          for _, card_index in ipairs(item.request.cards) do card_streams[card_index] = stream end
        else
          for _, card_index in ipairs(item.request.cards) do
            card_streams[card_index] = {
              error = "VISUAL STREAMS FULL",
              error_code = "global_stream_limit",
              error_detail = "All 64 ReaClock visual stream lanes are currently in use.",
            }
          end
        end
      else
        for _, card_index in ipairs(item.request.cards) do
          card_streams[card_index] = {
            error = string.format("%d OF %d VISUAL VIEWS", profile_budget[source_key].used,
              profile_budget[source_key].limit),
            error_code = "source_profile_limit",
            error_detail = "This meter source already uses four distinct live visual views. Match this card's channel view, waveform time span, FFT size, or visual quality to an existing card so they can share a view.",
            profile_budget = profile_budget[source_key],
          }
        end
      end
    end
  end
  for key, stream in pairs(visual.streams) do
    if not kept[key] and stream.lane ~= nil then Metering.Visual.revoke_lane(stream) end
  end
  visual.streams, visual.card_streams = kept, card_streams
  visual.profile_budget = profile_budget
  local profiles = {}
  for _, stream in pairs(kept) do
    local list = profiles[stream.source.key]
    if not list then list = {}; profiles[stream.source.key] = list end
    list[#list + 1] = stream
  end
  visual.profiles = profiles
  return per_source
end

function Metering.Visual.source_checksum(record, count)
  local a, b = 0, 0
  for _, offset in ipairs({ 0, 1, 6 }) do
    a, b = Metering.Visual.hash(a, b, R.gmem_read(record + offset), offset)
  end
  for index = 0, count * 10 - 1 do
    local offset = 8 + index
    a, b = Metering.Visual.hash(a, b, R.gmem_read(record + offset), offset)
  end
  return a, b
end

function Metering.Visual.commit_source(source, streams, now)
  if not Metering.command_valid(source) or #streams < 1
      or #streams > Metering.Visual.profile_limit then return false end
  local visual, record = Runtime.metering.visual, Metering.Visual.source_record(source)
  if not record then return false end
  table.sort(streams, function(a, b) return a.key < b.key end)
  local signature_parts = { source.runtime.slot, source.runtime.token }
  for _, stream in ipairs(streams) do
    local p = stream.profile
    signature_parts[#signature_parts + 1] = table.concat({ stream.lane, stream.token,
      p.demand, p.mode, p.channel_a, p.channel_b, p.timebase, p.fft, p.quality,
      stream.generation }, ",")
  end
  local signature = table.concat(signature_parts, ";")
  if visual.source_signatures[source.key] ~= signature then
    local generation = Metering.Visual.next_generation()
    R.gmem_write(record + 2, 0)
    R.gmem_write(record + 3, 0)
    R.gmem_write(record, source.runtime.token)
    R.gmem_write(record + 1, visual.controller)
    R.gmem_write(record + 6, #streams)
    visual.lease_sequence = Metering.next_counter(visual.lease_sequence)
    R.gmem_write(record + 7, visual.lease_sequence)
    for profile_index, stream in ipairs(streams) do
      local p = stream.profile
      local descriptor = { stream.lane, stream.token, p.demand, p.mode,
        p.channel_a, p.channel_b, p.timebase, p.fft, p.quality, stream.generation }
      for index, value in ipairs(descriptor) do
        R.gmem_write(record + 8 + (profile_index - 1) * 10 + index - 1, value)
      end
    end
    local a, b = Metering.Visual.source_checksum(record, #streams)
    R.gmem_write(record + 4, a)
    R.gmem_write(record + 5, b)
    R.gmem_write(record + 3, generation)
    R.gmem_write(record + 2, generation)
    visual.source_signatures[source.key] = signature
    visual.source_leases[source.key] = now
  elseif now - (visual.source_leases[source.key] or -math.huge) >= 0.2 then
    visual.lease_sequence = Metering.next_counter(visual.lease_sequence)
    R.gmem_write(record + 7, visual.lease_sequence)
    visual.source_leases[source.key] = now
  end
  return true
end

function Metering.Visual.sequence_distance(newer, older)
  return (math.floor(newer) - math.floor(older)) % Metering.command.counter_mod
end

function Metering.Visual.read_spectrum_history(stream)
  local v = Metering.Visual
  local base = v.lane_address(stream.lane)
  local latest_sequence = R.gmem_read(base + 12)
  local write_index = R.gmem_read(base + 13)
  local valid_count = R.gmem_read(base + 14)
  if not v.exact_integer(latest_sequence) or latest_sequence <= 0 then return {} end
  if not v.exact_integer(write_index) or write_index < 0
      or write_index >= v.spectrum_history_capacity
      or not v.exact_integer(valid_count) or valid_count < 1
      or valid_count > v.spectrum_history_capacity then
    return nil, "spectrum_history_header"
  end

  local previous = math.floor(stream.spectrum_history_sequence or 0)
  local distance = previous > 0 and v.sequence_distance(latest_sequence, previous)
    or valid_count
  if distance == 0 then return {} end
  local read_count = math.min(distance, valid_count, v.spectrum_history_capacity)
  local columns = {}
  for back = read_count - 1, 0, -1 do
    local slot = (write_index - back) % v.spectrum_history_capacity
    local entry = base + v.spectrum_history_offset
      + slot * v.spectrum_history_entry_size
    local begin_sequence = R.gmem_read(entry)
    local count = R.gmem_read(entry + 1)
    local fft_size = R.gmem_read(entry + 2)
    if not v.exact_integer(begin_sequence) or begin_sequence <= 0
        or not v.exact_integer(count) or count < 1 or count > 1024
        or not v.exact_integer(fft_size) or fft_size < 1024 or fft_size > 8192 then
      return nil, "spectrum_history_entry"
    end
    local values = {}
    local packed_count = math.floor((count + 3) / 4)
    for packed_index = 0, packed_count - 1 do
      local packed = R.gmem_read(entry + 3 + packed_index)
      if not v.exact_integer(packed) or packed < 0
          or packed > 281474976710655 then
        return nil, "spectrum_history_packed"
      end
      for component = 0, 3 do
        local index = packed_index * 4 + component
        if index < count then
          local quantized = packed % 4096
          values[index + 1] = -150 + quantized * 0.04
        end
        packed = math.floor(packed / 4096)
      end
    end
    if R.gmem_read(entry) ~= begin_sequence
        or R.gmem_read(entry + v.spectrum_history_entry_size - 1)
          ~= begin_sequence then
      return nil, "spectrum_history_stamp"
    end
    columns[#columns + 1] = {
      sequence = begin_sequence,
      fft_size = fft_size,
      values = values,
    }
  end
  stream.spectrum_history_sequence = latest_sequence
  if distance > read_count then
    stream.spectrum_history_dropped = (stream.spectrum_history_dropped or 0)
      + distance - read_count
  end
  return columns
end

function Metering.Visual.read_frame(stream)
  local v, visual = Metering.Visual, Runtime.metering.visual
  local base = v.lane_address(stream.lane)
  local published_sequence = R.gmem_read(base + 6)
  if v.exact_integer(published_sequence) and published_sequence > 0
      and published_sequence == stream.sequence then return true, "unchanged" end
  local lane = {}
  for offset = 0, 11 do lane[offset] = R.gmem_read(base + offset) end
  if lane[0] ~= v.magic or lane[1] ~= v.api then return false, "lane_api" end
  if lane[2] ~= stream.token or lane[3] ~= stream.source.runtime.token
      or lane[4] ~= visual.controller or lane[5] ~= stream.generation then
    return false, "lane_identity"
  end
  local sequence, active_bank, ready = lane[6], lane[7], math.floor(lane[8] or 0)
  if not v.exact_integer(sequence) or sequence <= 0 then return false, "starting" end
  if sequence == stream.sequence then return true, "unchanged" end
  if active_bank ~= 0 and active_bank ~= 1 then return false, "lane_bank" end
  if (ready & stream.profile.demand) ~= stream.profile.demand then return false, "starting" end

  local bank = v.bank_address(stream.lane, active_bank)
  local begin_sequence, end_sequence = R.gmem_read(bank), R.gmem_read(bank + 1)
  if begin_sequence ~= sequence or end_sequence ~= sequence then return false, "bank_stamp" end
  local checksum_a, checksum_b = R.gmem_read(bank + 2), R.gmem_read(bank + 3)
  local metadata = {}
  local a, b = 0, 0
  for index = 4, 35 do
    local value = R.gmem_read(bank + index)
    if not v.finite(value) then return false, "metadata_nonfinite" end
    metadata[index] = value
    a, b = v.hash(a, b, value, index)
  end
  local channels = math.floor(metadata[6])
  local wave_count = math.floor(metadata[15])
  local spectrum_count = math.floor(metadata[18])
  local scope_count = math.floor(metadata[22])
  if metadata[4] ~= ready or metadata[5] <= 0 or channels < 1 or channels > 64
      or wave_count < 0 or wave_count > 256
      or spectrum_count < 0 or spectrum_count > 1024
      or scope_count < 0 or scope_count > 256
      or metadata[25] < -1 or metadata[25] > 1 then return false, "counts_or_range" end
  if metadata[28] ~= stream.profile.mode
      or metadata[31] ~= stream.generation or metadata[32] ~= stream.token
      or metadata[33] ~= stream.source.runtime.token
      or metadata[34] ~= visual.controller or metadata[35] ~= v.api then
    return false, "bank_identity"
  end

  local frame = {
    sequence = sequence, ready = ready, sample_rate = metadata[5], channels = channels,
    epoch = math.floor(metadata[7]) % 65536, sample_counter = metadata[8],
    effective_quality = metadata[9], force_mono = metadata[10] ~= 0,
    level_sequence = metadata[11], wave_sequence = metadata[13],
    spectrum_sequence = metadata[16], fft_size = metadata[19],
    scope_sequence = metadata[20], correlation_sequence = metadata[23],
    correlation = metadata[25], status = metadata[26], dropped = metadata[27],
    mode = metadata[28], channel_a = metadata[29], channel_b = metadata[30],
    peak = {}, rms = {}, peak_max = {}, wave = {}, spectrum = {},
    spectrum_history = {}, scope = {},
  }
  if (ready & v.demand.levels) ~= 0 then
    for channel = 0, channels - 1 do
      for _, section in ipairs({ { 40, frame.peak }, { 104, frame.rms },
          { 168, frame.peak_max } }) do
        local offset, value = section[1] + channel, R.gmem_read(bank + section[1] + channel)
        if not v.finite(value) then return false, "levels_nonfinite" end
        section[2][channel + 1] = value
        a, b = v.hash(a, b, value, offset)
      end
    end
  end
  if (ready & v.demand.waveform) ~= 0 then
    for index = 0, wave_count * 4 - 1 do
      local offset, value = 256 + index, R.gmem_read(bank + 256 + index)
      if not v.finite(value) then return false, "wave_nonfinite" end
      frame.wave[index + 1] = value
      a, b = v.hash(a, b, value, offset)
    end
  end
  if (ready & v.demand.spectrum) ~= 0 then
    for index = 0, spectrum_count - 1 do
      local offset, value = 1280 + index, R.gmem_read(bank + 1280 + index)
      if not v.finite(value) then return false, "spectrum_nonfinite" end
      frame.spectrum[index + 1] = value
      a, b = v.hash(a, b, value, offset)
    end
  end
  if (ready & v.demand.vectorscope) ~= 0 then
    for index = 0, scope_count * 2 - 1 do
      local offset, value = 2304 + index, R.gmem_read(bank + 2304 + index)
      if not v.finite(value) then return false, "scope_nonfinite" end
      frame.scope[index + 1] = value
      a, b = v.hash(a, b, value, offset)
    end
  end
  if a ~= checksum_a or b ~= checksum_b then return false, "checksum" end
  if R.gmem_read(bank) ~= begin_sequence or R.gmem_read(bank + 1) ~= end_sequence
      or R.gmem_read(bank + 2) ~= checksum_a or R.gmem_read(bank + 3) ~= checksum_b then
    return false, "bank_changed"
  end
  for offset = 0, 11 do
    if R.gmem_read(base + offset) ~= lane[offset] then return false, "lane_changed" end
  end
  if (ready & v.demand.spectrum) ~= 0 then
    if stream.frame and stream.frame.epoch ~= frame.epoch then
      stream.spectrum_history_sequence = 0
    end
    local history, history_error = Metering.Visual.read_spectrum_history(stream)
    if history then
      frame.spectrum_history = history
    else
      frame.spectrum_history_error = history_error
    end
  end
  return true, frame
end

function Metering.Visual.resample_spectrum(values, count)
  local result, source_count = {}, #values
  if source_count == 0 then return result end
  for index = 1, count do
    local position = count > 1 and (index - 1) * (source_count - 1) / (count - 1) or 0
    local lower = math.floor(position) + 1
    local upper = math.min(source_count, lower + 1)
    local amount = position - math.floor(position)
    result[index] = values[lower] * (1 - amount) + values[upper] * amount
  end
  return result
end

function Metering.Visual.spectrogram_render_settings(config)
  local scale = config.meter_spectrogram_scale or "mel"
  local mode = config.meter_spectrogram_mode or "sharper"
  local tilt = tonumber(config.meter_spectrogram_tilt) or 4.5
  if mode == "classic" then return scale, tilt, 0, 0.95 end
  if mode == "sharp" then return scale, tilt, 0.35, 0.4 end
  return scale, tilt, 0.7, 0.18
end

function Metering.Visual.resample_spectrogram(values, count, config, frame, workspace)
  workspace = workspace or {}
  local source_count = #values
  if source_count == 0 then return {} end
  local scale, tilt, sharpening = Metering.Visual.spectrogram_render_settings(config)
  local nyquist = math.max(40, (tonumber(frame and frame.sample_rate) or 48000) * 0.5)
  local minimum = math.min(20, nyquist * 0.5)
  local log_span = math.log(nyquist / minimum)
  local signature = table.concat({ source_count, count, scale, tilt, nyquist }, ":")
  local mapping = workspace.mapping
  if not mapping or mapping.signature ~= signature then
    mapping = { signature = signature, lower = {}, upper = {}, blend = {}, offset = {} }
    local mel_min = 2595 * math.log(1 + minimum / 700) / math.log(10)
    local mel_max = 2595 * math.log(1 + nyquist / 700) / math.log(10)
    for index = 1, count do
      local amount = count > 1 and (index - 1) / (count - 1) or 0
      local frequency
      if scale == "mel" then
        local mel = mel_min + (mel_max - mel_min) * amount
        frequency = 700 * (10 ^ (mel / 2595) - 1)
      elseif scale == "linear" then
        frequency = minimum + (nyquist - minimum) * amount
      else
        frequency = minimum * math.exp(log_span * amount)
      end
      local source_position = math.log(math.max(minimum, frequency) / minimum)
        / math.max(1e-9, log_span) * math.max(0, source_count - 1)
      local lower = math.floor(source_position) + 1
      mapping.lower[index] = lower
      mapping.upper[index] = math.min(source_count, lower + 1)
      mapping.blend[index] = source_position - math.floor(source_position)
      mapping.offset[index] = tilt
        * math.log(math.max(1, frequency) / 1000) / math.log(2)
    end
    workspace.mapping = mapping
  end
  local result = workspace.result or {}
  workspace.result = result
  for index = 1, count do
    local blend = mapping.blend[index]
    result[index] = values[mapping.lower[index]] * (1 - blend)
      + values[mapping.upper[index]] * blend + mapping.offset[index]
  end
  if sharpening > 0 and count > 2 then
    local sharpened = workspace.sharpened or {}
    local prefix = workspace.prefix or {}
    workspace.sharpened, workspace.prefix = sharpened, prefix
    local radius = math.max(2, math.floor(count / 128 + 0.5))
    prefix[0] = 0
    for index = 1, count do prefix[index] = prefix[index - 1] + result[index] end
    for index = 1, count do
      local first, last = math.max(1, index - radius), math.min(count, index + radius)
      local local_average = (prefix[last] - prefix[first - 1]) / (last - first + 1)
      sharpened[index] = math.min(6,
        result[index] + (result[index] - local_average) * sharpening)
    end
    return sharpened
  end
  return result
end

function Metering.Visual.spectrum_rate(frame)
  local quality = math.floor(tonumber(frame and frame.effective_quality) or 3)
  if quality <= 1 then return 10 end
  if quality == 2 then return 20 end
  if quality >= 4 then return 240 end
  return 30
end

function Metering.Visual.spectrogram_bins(config, frame)
  local requested = math.max(64, math.min(1024,
    math.floor(config.meter_spectrogram_bins or 1024)))
  local quality = math.floor(tonumber(frame and frame.effective_quality) or 3)
  local quality_cap = quality <= 1 and 96 or quality == 2 and 128
    or quality >= 4 and 1024 or 512
  return math.min(requested, quality_cap)
end

function Metering.Visual.spectrogram_color(value, floor, palette)
  local raw = math.max(0, math.min(1, (value - floor) / math.max(1, -floor)))
  -- Keep the floor genuinely black and reserve cyan/white for resolved energy.
  -- This matches the supplied MiniMeters reference more closely than lifting
  -- low-level bins into a uniform teal haze.
  local amount = raw <= 0.045 and 0 or ((raw - 0.045) / 0.955) ^ 1.18
  local low, lower, middle, high, hottest =
    mix_color(0x030407FF, C.outer, 0.08),
    mix_color(0x0B1117FF, C.accent, 0.28), C.accent, C.secondary, 0xF5F8F4FF
  if palette == "ocean" then
    low, lower, middle, high, hottest = 0x02070CFF, 0x062A38FF, 0x087B84FF,
      0x36D4C2FF, 0xEEF5C5FF
  elseif palette == "ember" then
    low, lower, middle, high, hottest = 0x080507FF, 0x351017FF, 0x8D3027FF,
      0xF08B39FF, 0xFFF1B8FF
  elseif palette == "violet" then
    low, lower, middle, high, hottest = 0x070612FF, 0x22164AFF, 0x633993FF,
      0xD16DD4FF, 0xF9E7FFFF
  end
  if amount < 0.18 then return mix_color(low, lower, amount / 0.18) end
  if amount < 0.45 then return mix_color(lower, middle, (amount - 0.18) / 0.27) end
  if amount < 0.74 then return mix_color(middle, high, (amount - 0.45) / 0.29) end
  return mix_color(high, hottest, (amount - 0.74) / 0.26)
end

function Metering.Visual.update_spectrogram_image(ring, config, column)
  local pixel_api = type(R.ImGui_CreateImageFromSize) == "function"
    and type(R.ImGui_Image_SetPixels_Array) == "function" and type(R.new_array) == "function"
  ring.pixel_api = pixel_api
  if not pixel_api then return end
  local width = math.max(32, math.min(4096,
    math.floor(tonumber(ring.capacity) or 150)))
  local height = math.max(64, math.min(2048,
    math.floor(tonumber(ring.pixel_height) or ring.bins or #column or 128)))
  if ring.image and (ring.image_width ~= width or ring.image_height ~= height) then
    Metering.Visual.detach_spectrogram(ring)
    ring.pixel_column = nil
  end
  if not ring.image then
    ring.image = R.ImGui_CreateImageFromSize(width, height)
    ring.tail_image = R.ImGui_CreateImageFromSize(1, height)
    R.ImGui_Attach(ctx, ring.image)
    R.ImGui_Attach(ctx, ring.tail_image)
    local blank_tail = R.new_array(height)
    local floor = math.max(-120, math.min(-60, config.meter_spectrum_floor or -90))
    local blank_color = Metering.Visual.spectrogram_color(
      floor, floor, config.meter_spectrogram_palette)
    ring.blank_color = blank_color
    for index = 1, height do blank_tail[index] = blank_color end
    R.ImGui_Image_SetPixels_Array(ring.tail_image, 0, 0, 1, height,
      blank_tail, 0, 1)
    ring.image_head, ring.image_width, ring.image_height, ring.columns_written =
      0, width, height, 0
  end
  ring.pixel_column = ring.pixel_column or R.new_array(height)
  local floor = math.max(-120, math.min(-60, config.meter_spectrum_floor or -90))
  for y = 0, height - 1 do
    local position = (height - 1 - y) * math.max(0, #column - 1) / (height - 1)
    local lower, amount = math.floor(position) + 1, position - math.floor(position)
    local upper = math.min(#column, lower + 1)
    local value = (column[lower] or floor) * (1 - amount) + (column[upper] or floor) * amount
    ring.pixel_column[y + 1] = Metering.Visual.spectrogram_color(
      value, floor, config.meter_spectrogram_palette)
  end
  R.ImGui_Image_SetPixels_Array(ring.image, ring.image_head, 0, 1, height,
    ring.pixel_column, 0, 1)
  R.ImGui_Image_SetPixels_Array(ring.tail_image, 0, 0, 1, height,
    ring.pixel_column, 0, 1)
  ring.image_head = (ring.image_head + 1) % width
  ring.columns_written = math.min(width, (ring.columns_written or 0) + 1)
end

function Metering.Visual.prepare_card_data(card_index, stream, now)
  local visual, config, frame = Runtime.metering.visual,
    settings.cards[card_index], stream.frame
  if not config or not frame then return end
  local cache = visual.card_data[card_index]
  local signature = table.concat({
    tostring(config.meter_display), tostring(config.meter_channel_mode),
    tostring(config.meter_channel_a), tostring(config.meter_channel_b),
    tostring(config.meter_waveform_timebase), tostring(config.meter_waveform_layout),
    tostring(config.meter_spectrum_fft_size), tostring(config.meter_spectrum_floor),
    tostring(config.meter_spectrum_smoothing), tostring(config.meter_spectrum_peak_hold),
    tostring(config.meter_spectrogram_seconds), tostring(config.meter_spectrogram_bins),
    tostring(config.meter_spectrogram_palette), tostring(config.meter_spectrogram_scale),
    tostring(config.meter_spectrogram_mode), tostring(config.meter_spectrogram_tilt),
    tostring(config.meter_scope_mode),
    tostring(config.meter_scope_persistence), tostring(config.meter_correlation_seconds),
    tostring(C.outer), tostring(C.accent), tostring(C.secondary), tostring(C.ink),
    tostring(C.danger), tostring(C.accent_secondary),
  }, ":")
  local identity = stream.key .. ":" .. stream.generation .. ":" .. frame.epoch
    .. ":" .. signature
  if not cache or cache.identity ~= identity then
    if cache then Metering.Visual.detach_spectrogram(cache.spectrogram) end
    cache = { identity = identity, spectrogram = {},
      scope_frames = {}, correlation = { values = {}, head = 1 } }
    visual.card_data[card_index] = cache
  end
  if cache.last_sequence == frame.sequence then return end
  cache.last_sequence, cache.frame = frame.sequence, frame
  local display = config.meter_display
  if display == "waveform" and cache.last_wave_sequence ~= frame.wave_sequence then
    cache.wave_target = cache.wave_target or {}
    for index, value in ipairs(frame.wave) do
      cache.wave_target[index] = value
    end
    for index = #frame.wave + 1, #cache.wave_target do cache.wave_target[index] = nil end
    if not cache.wave_display then
      cache.wave_display = {}
      for index, value in ipairs(cache.wave_target) do cache.wave_display[index] = value end
    end
    cache.last_wave_sequence = frame.wave_sequence
  elseif display == "spectrum" and cache.last_spectrum_sequence ~= frame.spectrum_sequence then
    cache.spectrum_smoothing = math.max(0,
      math.min(0.95, config.meter_spectrum_smoothing or 0.6))
    cache.spectrum_target = cache.spectrum_target or {}
    cache.spectrum_peak = cache.spectrum_peak or {}
    for index, value in ipairs(frame.spectrum) do
      cache.spectrum_target[index] = value
    end
    for index = #frame.spectrum + 1, #cache.spectrum_target do
      cache.spectrum_target[index] = nil
    end
    if not cache.spectrum then
      cache.spectrum = {}
      for index, value in ipairs(cache.spectrum_target) do
        cache.spectrum[index], cache.spectrum_peak[index] = value, value
      end
    end
    cache.last_spectrum_sequence = frame.spectrum_sequence
  elseif display == "spectrogram"
      and cache.last_spectrum_sequence ~= frame.spectrum_sequence then
    local bins = Metering.Visual.spectrogram_bins(config, frame)
    local ring = cache.spectrogram
    ring.history_warmup_until = ring.history_warmup_until or now + 1
    local _, _, _, rendering_smoothing = Metering.Visual.spectrogram_render_settings(config)
    local smoothing = math.max(0, math.min(rendering_smoothing or 0.95,
      config.meter_spectrum_smoothing or 0.6))
    local column_rate = Metering.Visual.spectrum_rate(frame)
    ring.bins = bins
    ring.pixel_multiplier = 1
    ring.pixel_height = bins
    ring.column_rate = column_rate
    ring.column_interval = 1 / column_rate
    ring.capacity = math.min(4096, math.max(32,
      math.floor((config.meter_spectrogram_seconds or 10) * column_rate
        + 0.5)))

    local source_columns = {}
    for _, history_column in ipairs(frame.spectrum_history or {}) do
      source_columns[#source_columns + 1] = history_column.values
    end
    if #source_columns == 0 then source_columns[1] = frame.spectrum end
    cache.spectrogram_column = cache.spectrogram_column or {}
    ring.resample_workspace = ring.resample_workspace or {}
    for _, source_column in ipairs(source_columns) do
      local column = Metering.Visual.resample_spectrogram(
        source_column, bins, config, frame, ring.resample_workspace)
      for index, value in ipairs(column) do
        local previous = cache.spectrogram_column[index]
        cache.spectrogram_column[index] = previous and previous * smoothing
          + value * (1 - smoothing) or value
      end
      for index = #column + 1, #cache.spectrogram_column do
        cache.spectrogram_column[index] = nil
      end
      Metering.Visual.update_spectrogram_image(
        ring, config, cache.spectrogram_column)
    end
    ring.source_columns = (ring.source_columns or 0) + #source_columns
    ring.history_batch = #source_columns
    ring.max_history_batch = math.max(ring.max_history_batch or 0, #source_columns)
    ring.history_dropped = stream.spectrum_history_dropped or 0
    if now <= ring.history_warmup_until then
      ring.history_warmup_dropped = ring.history_dropped
    else
      ring.history_warmup_dropped = ring.history_warmup_dropped
        or ring.history_dropped
      ring.history_steady_dropped = math.max(0,
        ring.history_dropped - ring.history_warmup_dropped)
    end
    ring.last_at, cache.last_spectrum_sequence = now, frame.spectrum_sequence
  elseif display == "vectorscope" and cache.last_scope_sequence ~= frame.scope_sequence then
    cache.scope_frames[#cache.scope_frames + 1] = { time = now, values = frame.scope }
    local left_energy, right_energy, mid_energy, side_energy = 0, 0, 0, 0
    for index = 1, #frame.scope - 1, 2 do
      local left, right = frame.scope[index] or 0, frame.scope[index + 1] or 0
      local mid, side = (left + right) * 0.5, (left - right) * 0.5
      left_energy, right_energy = left_energy + left * left, right_energy + right * right
      mid_energy, side_energy = mid_energy + mid * mid, side_energy + side * side
    end
    cache.scope_stats = {
      balance_db = 10 * math.log((left_energy + 1e-12) / (right_energy + 1e-12))
        / math.log(10),
      side_percent = 100 * side_energy / math.max(1e-12, mid_energy + side_energy),
    }
    local persistence = math.max(0, math.min(2, config.meter_scope_persistence or 0.35))
    while cache.scope_frames[1] and now - cache.scope_frames[1].time > persistence do
      table.remove(cache.scope_frames, 1)
    end
    while #cache.scope_frames > 16 do table.remove(cache.scope_frames, 1) end
    cache.last_scope_sequence = frame.scope_sequence
  elseif display == "correlation"
      and cache.last_correlation_sequence ~= frame.correlation_sequence then
    local history = cache.correlation
    history.values[#history.values + 1] = { time = now, value = frame.correlation }
    local span = math.max(3, math.min(60, config.meter_correlation_seconds or 10))
    while history.values[history.head]
        and now - history.values[history.head].time > span do history.head = history.head + 1 end
    cache.last_correlation_sequence = frame.correlation_sequence
  end
end

function Metering.Visual.animate_card_data(cache, now)
  if not cache then return end
  local elapsed = math.max(0, math.min(0.1, now - (cache.animated_at or now)))
  cache.animated_at = now
  if elapsed <= 0 then return end

  if cache.wave_target and cache.wave_display then
    local retention = math.exp(-elapsed * 18)
    for index, target in ipairs(cache.wave_target) do
      local current = cache.wave_display[index] or target
      cache.wave_display[index] = current * retention + target * (1 - retention)
    end
  end

  if cache.spectrum_target and cache.spectrum then
    local smoothing = cache.spectrum_smoothing or 0.6
    local retention = smoothing ^ math.max(0.05, elapsed * 30)
    cache.spectrum_peak = cache.spectrum_peak or {}
    for index, target in ipairs(cache.spectrum_target) do
      local current = cache.spectrum[index] or target
      cache.spectrum[index] = current * retention + target * (1 - retention)
      local peak = cache.spectrum_peak[index] or target
      cache.spectrum_peak[index] = math.max(target, peak - elapsed * 12)
    end
  end
end

function Metering.Visual.update(now)
  if not Runtime.metering.gmem_attached then return end
  Metering.Visual.write_header()
  local visual = Runtime.metering.visual
  if visual.compile_dirty or now - visual.last_compile >= 0.1 then
    Metering.Visual.compile()
    visual.compile_dirty, visual.last_compile = false, now
  end
  local profiles = visual.profiles or {}
  for source_key, streams in pairs(profiles) do
    Metering.Visual.commit_source(streams[1].source, streams, now)
  end
  for source_key in pairs(visual.source_signatures) do
    if not profiles[source_key] then
      local source = Runtime.metering.source_by_key[source_key]
      local record = source and Metering.Visual.source_record(source)
      if record and Metering.command_valid(source) then
        R.gmem_write(record + 2, 0)
        R.gmem_write(record + 3, 0)
        R.gmem_write(record, 0)
        R.gmem_write(record + 6, 0)
      end
      visual.source_signatures[source_key], visual.source_leases[source_key] = nil, nil
    end
  end
  for _, stream in pairs(visual.streams) do
    local okay, result = Metering.Visual.read_frame(stream)
    -- Maximum analysis can publish a new atomic bank while Lua is copying the
    -- prior one. Retry that benign collision once in the same UI frame rather
    -- than surfacing a transient lane_changed diagnostic to the user.
    if not okay and result == "lane_changed" then
      okay, result = Metering.Visual.read_frame(stream)
    end
    if okay then
      stream.invalid_count, stream.error, stream.last_read_error = 0, nil, nil
      if result ~= "unchanged" then
        if stream.frame and stream.frame.epoch ~= result.epoch then stream.histories = {} end
        stream.frame, stream.sequence, stream.updated_at = result, result.sequence, now
      end
    elseif not okay and result ~= "starting" then
      stream.invalid_count = (stream.invalid_count or 0) + 1
      stream.last_read_error = result
      if stream.invalid_count >= 3 then stream.error = "VISUAL DATA UNSTABLE" end
    end
  end
  local active_cards = {}
  for card_index, stream in pairs(visual.card_streams) do
    active_cards[card_index] = true
    if not stream.error and stream.frame then
      Metering.Visual.prepare_card_data(card_index, stream, now)
      Metering.Visual.animate_card_data(visual.card_data[card_index], now)
    end
  end
  for card_index in pairs(visual.card_data) do
    if not active_cards[card_index] then
      local cache = visual.card_data[card_index]
      Metering.Visual.detach_spectrogram(cache.spectrogram)
      visual.card_data[card_index] = nil
    end
  end
end

function Metering.Visual.process_test_quality_request()
  if not Store.test_override then return end
  local request = R.GetExtState(EXT, "__meter_visual_quality_request")
  local visual = Runtime.metering.visual
  if request == "" or request == visual.test_quality_request then return end
  visual.test_quality_request = request
  local card_index, quality = request:match("^(%d+):([%a_]+):")
  card_index = tonumber(card_index)
  local config = card_index and settings.cards[card_index]
  local quality_values = {
    auto = true, low = true, standard = true, high = true, maximum = true,
  }
  if config and config.type == "meter" and quality_values[quality] then
    config.meter_visual_quality = quality
    Content.save_card(card_index)
    R.SetExtState(EXT, "__meter_visual_quality_ack", request, false)
  else
    R.SetExtState(EXT, "__meter_visual_quality_ack", "invalid:" .. request, false)
  end
end

snapshot = {
  blank = false,
  gap_display = nil,
  main = "0:00",
  main_fit_reference = "0:00",
  length = "0:00",
  remaining = "0:00",
  remaining_label = "REMAINING",
  current_region = "",
  next_region = "",
  next_region_countdown = "",
  next_region_fit_reference = "",
  next_region_warning = false,
  next_marker = "",
  next_marker_countdown = "",
  next_marker_fit_reference = "",
  next_marker_warning = false,
  progress = 0,
  tempo = "120",
  time_signature = "4/4",
  grid_visible = true,
  tempo_visible = true,
  transport_label = "STOPPED",
  transport_kind = "stopped",
  raw_position = 0,
  position = 0,
  tempo_value = 120,
  cards = {},
  technical = {
    updated = -math.huge, project_change = -1, values = {},
    device_updated = -math.huge, midi_inputs = 0, midi_outputs = 0,
  },
}

function snapshot.refresh_technical()
  local now = R.time_precise()
  local project = R.EnumProjects(-1) or 0
  local project_change = R.GetProjectStateChangeCount(project) or 0
  local function audio_value(attribute)
    local ok, value = R.GetAudioDeviceInfo(attribute)
    return ok and tostring(value or "") ~= "" and tostring(value) or "Unavailable"
  end
  local function put(id, label, value, font, fit_reference)
    snapshot.technical.values[id] = {
      label = label, value = tostring(value), font = font or "mono",
      fit_mode = font == "regular" and "ellipsis" or "shrink",
      fit_reference = fit_reference,
    }
  end
  if now - snapshot.technical.updated < 1 then return end

  local function latency(samples, sample_rate)
    samples = math.max(0, math.floor(tonumber(samples) or 0))
    return string.format("%d smp · %.1f ms", samples, samples * 1000 / sample_rate)
  end
  local function xrun_age(timestamp, current)
    timestamp, current = tonumber(timestamp) or 0, tonumber(current) or 0
    if timestamp <= 0 then return "None this session" end
    local seconds = math.max(0, (current - timestamp) / 1000)
    if seconds < 1 then return "Just now" end
    if seconds < 60 then return string.format("%.0f s ago", seconds) end
    if seconds < 3600 then return string.format("%.0f min ago", seconds / 60) end
    return string.format("%.1f hr ago", seconds / 3600)
  end
  local function count_named_devices(maximum, getter)
    local count = 0
    for index = 0, math.max(0, tonumber(maximum) or 0) - 1 do
      if getter(index, "") then count = count + 1 end
    end
    return count
  end

  local sample_rate = select(1, active_sample_rate())
  local rate_text = sample_rate >= 1000
    and string.format(sample_rate % 1000 == 0 and "%.0f kHz" or "%.1f kHz",
      sample_rate / 1000) or string.format("%.0f Hz", sample_rate)
  local input_latency, output_latency = 0, 0
  if R.GetInputOutputLatency then input_latency, output_latency = R.GetInputOutputLatency() end
  input_latency, output_latency = tonumber(input_latency) or 0, tonumber(output_latency) or 0
  local buffer = audio_value("BSIZE")
  if tonumber(buffer) then buffer = tostring(math.floor(tonumber(buffer))) .. " samples" end
  local bit_depth = audio_value("BPS")
  if tonumber(bit_depth) then bit_depth = tostring(math.floor(tonumber(bit_depth))) .. "-bit" end
  local _, marker_count, region_count = R.CountProjectMarkers(project)
  local project_tabs, tab_index = 0, 0
  while R.EnumProjects(tab_index) do project_tabs, tab_index = project_tabs + 1, tab_index + 1 end
  local audio_xrun, media_xrun, xrun_now = R.GetUnderrunTime()
  if now - snapshot.technical.device_updated >= 10 then
    snapshot.technical.midi_inputs =
      count_named_devices(R.GetNumMIDIInputs(), R.GetMIDIInputName)
    snapshot.technical.midi_outputs =
      count_named_devices(R.GetNumMIDIOutputs(), R.GetMIDIOutputName)
    snapshot.technical.device_updated = now
  end
  local free_mb = R.GetFreeDiskSpaceForRecordPath
    and tonumber(R.GetFreeDiskSpaceForRecordPath(project, 0)) or nil
  local free_text = "Unavailable"
  if free_mb and free_mb >= 0 then
    free_text = free_mb >= 1048576 and string.format("%.2f TB", free_mb / 1048576)
      or (free_mb >= 1024 and string.format("%.1f GB", free_mb / 1024)
        or string.format("%.0f MB", free_mb))
  end

  put("sample_rate", "SAMPLE RATE", rate_text, "mono", "888.8 kHz")
  put("buffer_size", "BUFFER SIZE", buffer, "mono", "88888 samples")
  put("bit_depth", "BIT DEPTH", bit_depth, "mono", "888-bit")
  put("input_latency", "INPUT LATENCY", latency(input_latency, sample_rate), "mono")
  put("output_latency", "OUTPUT LATENCY", latency(output_latency, sample_rate), "mono")
  put("roundtrip_latency", "TOTAL LATENCY",
    latency(input_latency + output_latency, sample_rate), "mono")
  put("audio_mode", "AUDIO DRIVER", audio_value("MODE"), "regular")
  put("input_device", "INPUT DEVICE", audio_value("IDENT_IN"), "regular")
  put("output_device", "OUTPUT DEVICE", audio_value("IDENT_OUT"), "regular")
  put("audio_inputs", "AUDIO INPUTS", R.GetNumAudioInputs(), "mono", "888")
  put("audio_outputs", "AUDIO OUTPUTS", R.GetNumAudioOutputs(), "mono", "888")
  put("midi_inputs", "MIDI INPUTS", snapshot.technical.midi_inputs, "mono", "888")
  put("midi_outputs", "MIDI OUTPUTS", snapshot.technical.midi_outputs, "mono", "888")
  put("audio_xrun", "LAST AUDIO XRUN", xrun_age(audio_xrun, xrun_now), "regular")
  put("media_xrun", "LAST MEDIA XRUN", xrun_age(media_xrun, xrun_now), "regular")
  put("track_count", "TRACKS", R.CountTracks(project), "mono", "88888")
  put("item_count", "MEDIA ITEMS", R.CountMediaItems(project), "mono", "88888")
  put("selected_tracks", "SELECTED TRACKS", R.CountSelectedTracks(project), "mono", "88888")
  put("selected_items", "SELECTED ITEMS", R.CountSelectedMediaItems(project), "mono", "88888")
  put("marker_count", "MARKERS", marker_count or 0, "mono", "88888")
  put("region_count", "REGIONS", region_count or 0, "mono", "88888")
  put("project_tabs", "PROJECT TABS", project_tabs, "mono", "888")
  put("project_status", "PROJECT STATUS",
    R.IsProjectDirty(project) == 1 and "Unsaved changes" or "Saved", "regular")
  put("record_disk_free", "DISK FREE", free_text, "mono", "888.88 TB")
  snapshot.technical.updated, snapshot.technical.project_change = now, project_change
end

local system_clock_cache = { second = -1, time12 = "", time24 = "", date = "" }

local function system_clock_values()
  local second = os.time()
  if second ~= system_clock_cache.second then
    system_clock_cache.second = second
    system_clock_cache.time12 = os.date("%I:%M:%S %p", second):gsub("^0", "")
    system_clock_cache.time24 = os.date("%H:%M:%S", second)
    system_clock_cache.date = os.date("%b %d, %Y", second)
  end
  return system_clock_cache.time12, system_clock_cache.time24, system_clock_cache.date
end

local function current_project_name()
  local _, project_path = R.EnumProjects(-1, "")
  local name = tostring(project_path or ""):match("([^\\/]+)$") or ""
  name = name:gsub("%.[Rr][Pp][Pp]$", "")
  return name ~= "" and name or "Untitled"
end

local function current_project_metadata(key)
  if not R.GetSetProjectInfo_String then return "" end
  local okay, value = R.GetSetProjectInfo_String(0, key, "", false)
  return okay and tostring(value or "") or ""
end

local function expand_card_template(template, values)
  return (tostring(template or ""):gsub("{([%w_]+)}", function(token)
    local value = values[token]
    return value ~= nil and tostring(value) or ("{" .. token .. "}")
  end))
end

local function refresh_display_snapshots()
  Metering.update(R.time_precise())
  local needs_system_clock, needs_project_name, needs_project_title = false, false, false
  local needs_project_author, needs_technical = false, false
  local configs = {}
  Runtime.each_active_card(function(_, config) configs[#configs + 1] = config end)
  for _, config in ipairs(configs) do
    if config.type == "time12" or config.type == "time24" or config.type == "date" then
      needs_system_clock = true
    elseif config.type == "project" then
      needs_project_name = true
    elseif config.type == "project_title" then
      needs_project_title = true
    elseif CARD_TYPE_BY_ID[config.type] and CARD_TYPE_BY_ID[config.type].technical then
      needs_technical = true
    elseif config.type == "custom" then
      local template = config.template or ""
      needs_system_clock = needs_system_clock or template:find("{time12}", 1, true) ~= nil
        or template:find("{time24}", 1, true) ~= nil
        or template:find("{date}", 1, true) ~= nil
      needs_project_name = needs_project_name or template:find("{project}", 1, true) ~= nil
      needs_project_title = needs_project_title
        or template:find("{project_title}", 1, true) ~= nil
      needs_project_author = needs_project_author or template:find("{author}", 1, true) ~= nil
      if not needs_technical then
        for _, token in ipairs(TECHNICAL_TOKEN_IDS) do
          if template:find("{" .. token .. "}", 1, true) then
            needs_technical = true
            break
          end
        end
      end
    end
  end

  local time12, time24, date = "", "", ""
  if needs_system_clock then time12, time24, date = system_clock_values() end
  local project_name = needs_project_name and current_project_name() or ""
  local project_title = needs_project_title and current_project_metadata("PROJECT_TITLE") or ""
  local project_author = needs_project_author and current_project_metadata("PROJECT_AUTHOR") or ""
  if needs_technical then snapshot.refresh_technical() end
  local scope_labels = { project = "Project", region = "Region", selection = "Selection" }
  local values = {
    position = snapshot.main,
    length = snapshot.length,
    remaining = snapshot.remaining,
    region = snapshot.current_region,
    next_region = snapshot.next_region,
    next_region_countdown = snapshot.next_region_countdown,
    next_marker = snapshot.next_marker,
    next_marker_countdown = snapshot.next_marker_countdown,
    tempo = snapshot.tempo,
    timesig = snapshot.time_signature,
    transport = snapshot.transport_label,
    project = project_name,
    project_title = project_title,
    author = project_author,
    time12 = time12,
    time24 = time24,
    date = date,
    scope = scope_labels[settings.scope] or settings.scope,
    units = settings.units == "beats" and "Beats" or "Time",
  }
  if needs_technical then
    for id, technical in pairs(snapshot.technical.values) do values[id] = technical.value end
  end

  local function resolve_content(config, card_index)
    local content = {
      visible = config.type ~= "none"
        and (config.type ~= "tempo" and config.type ~= "time_signature" or snapshot.tempo_visible),
      label = "",
      value = "",
      font = "mono",
      fit_mode = "shrink",
      fit_reference = nil,
      visual_click = false,
    }
    local content_type = config.type
    if content_type == "length" then
      content.label, content.value, content.fit_reference = "LENGTH", snapshot.length, snapshot.length
    elseif content_type == "remaining" then
      content.label, content.value = snapshot.remaining_label, snapshot.remaining
      content.fit_reference = "-" .. snapshot.length
    elseif content_type == "position" then
      content.label, content.value = "POSITION", snapshot.main
      content.fit_reference = snapshot.main_fit_reference
    elseif content_type == "tempo" then
      content.label, content.value, content.fit_reference = "TEMPO", snapshot.tempo, "888.8"
    elseif content_type == "time_signature" then
      content.label, content.value, content.fit_reference =
        "TIME SIGNATURE", snapshot.time_signature, "88/88"
    elseif content_type == "visual_click" then
      content.label, content.value, content.fit_reference = "VISUAL CLICK", "1", "88"
      content.visual_click = true
    elseif content_type == "current_region" then
      content.label, content.value, content.font, content.fit_mode =
        "CURRENT REGION", snapshot.current_region, "regular", "ellipsis"
    elseif content_type == "next_region" then
      content.label, content.value, content.font, content.fit_mode =
        "NEXT REGION", snapshot.next_region, "regular", "ellipsis"
    elseif content_type == "next_region_countdown" then
      content.label, content.value = "REGION IN", snapshot.next_region_countdown
      content.fit_reference = snapshot.next_region_fit_reference
    elseif content_type == "next_marker" then
      content.label, content.value, content.font, content.fit_mode =
        "NEXT MARKER", snapshot.next_marker, "regular", "ellipsis"
    elseif content_type == "next_marker_countdown" then
      content.label, content.value = "MARKER IN", snapshot.next_marker_countdown
      content.fit_reference = snapshot.next_marker_fit_reference
    elseif content_type == "transport" then
      content.label, content.value, content.font, content.fit_mode =
        "TRANSPORT", snapshot.transport_label, "regular", "shrink"
    elseif content_type == "project" then
      content.label, content.value, content.font, content.fit_mode =
        "PROJECT", values.project, "regular", "ellipsis"
    elseif content_type == "project_title" then
      content.label, content.value, content.font, content.fit_mode =
        "PROJECT TITLE", values.project_title, "regular", "ellipsis"
    elseif content_type == "time12" then
      content.label, content.value, content.fit_reference = "LOCAL TIME", time12, "88:88:88 PM"
    elseif content_type == "time24" then
      content.label, content.value, content.fit_reference = "LOCAL TIME", time24, "88:88:88"
    elseif content_type == "date" then
      content.label, content.value, content.font, content.fit_mode = "DATE", date, "regular", "shrink"
      content.fit_reference = "Sep 88, 8888"
    elseif content_type == "meter" then
      content = Metering.card_content(config, card_index)
    elseif content_type == "action" then
      local action, action_error = Content.actions.resolve(config.action_command)
      local action_toggle_state
      if action then action_toggle_state = Content.actions.toggle_state(action.command) end
      content.label = "ACTION"
      content.value = config.action_text ~= "" and config.action_text
        or action and action.name
        or config.action_name ~= "" and config.action_name
        or "CHOOSE AN ACTION"
      content.font, content.fit_mode = "regular", "shrink"
      content.action_button = true
      content.action_available = action ~= nil
      content.action_command = action and action.command or nil
      content.action_toggle = action_toggle_state ~= nil
      content.action_toggled = action_toggle_state == true
      content.action_error = action_error
    elseif CARD_TYPE_BY_ID[content_type] and CARD_TYPE_BY_ID[content_type].technical then
      local technical = snapshot.technical.values[content_type]
      if technical then
        content.label, content.value, content.font = technical.label, technical.value, technical.font
        content.fit_mode, content.fit_reference = technical.fit_mode, technical.fit_reference
      else
        content.visible = false
      end
    elseif content_type == "custom" then
      content.label = config.label
      local meter_metric_ids = Metering.template_metric_ids(config.template)
      local custom_values = setmetatable({}, { __index = values })
      if #meter_metric_ids > 0 then
        local source, binding_status = Metering.resolve_binding(config)
        if not source then
          content.value = binding_status == "SETUP REQUIRED" and "CHOOSE A METER SOURCE"
            or binding_status or "METER SOURCE MISSING"
          content.setup_required = binding_status ~= "SOURCE IN ANOTHER PROJECT"
          content.setup_status = binding_status
        else
          local runtime = source.runtime
          if binding_status or runtime.status then
            content.value = binding_status or runtime.status
            content.setup_required = binding_status ~= nil
            content.setup_status = binding_status
          elseif Metering.monitoring_outside_active_project(source) then
            for _, metric_id in ipairs(meter_metric_ids) do custom_values[metric_id] = "" end
            content.value = expand_card_template(config.template, custom_values)
            content.keep_visible = true
          else
            for _, metric_id in ipairs(meter_metric_ids) do
              custom_values[metric_id] = Metering.format_value(metric_id,
                runtime.values and runtime.values[metric_id])
            end
            content.value = expand_card_template(config.template, custom_values)
          end
          content.meter_source, content.meter_source_key = source, source.key
        end
      else
        content.value = expand_card_template(config.template, custom_values)
      end
      content.font = config.font == "auto" and "regular" or config.font
      content.fit_mode = content.font == "mono" and "shrink" or "ellipsis"
    else
      content.visible = false
    end
    if config.font == "regular" or config.font == "mono" then
      content.font = config.font
      content.fit_mode = content.font == "mono" and "shrink" or "ellipsis"
    end
    if config.scroll and content.fit_mode == "ellipsis" then
      content.fit_mode = "scroll"
    end
    return content
  end

  Runtime.resolve_card_content = resolve_content
  for index, config in ipairs(settings.cards) do
    snapshot.cards[index] = resolve_content(config, index)
  end
  for _, entry in ipairs(settings.detached_cards) do
    local index = -entry.id
    snapshot.cards[index] = entry.open and resolve_content(entry.card, index) or nil
  end
  Runtime.row_visible = Runtime.row_visible or {}
  -- Hold the configured footprint until transport fully stops. A pause in a
  -- region gap must be just as stable as live playback or recording.
  local transport_active = snapshot.transport_kind ~= "stopped"
  for row = 1, MAX_CARD_ROWS do
    local visible = false
    if row <= settings.card_rows then
      for column = 1, settings.card_row_counts[row] do
        local card = snapshot.cards[(row - 1) * CARDS_PER_ROW + column]
        -- Reserve every enabled card row while transport runs or pauses, even
        -- when a live value is temporarily empty (for example, between regions).
        if card and card.visible
            and (transport_active or card.value ~= "" or card.keep_visible) then
          visible = true
          break
        end
      end
    end
    Runtime.row_visible[row] = visible
  end
end

local last_data_update = -math.huge

recompute_snapshot = function(force)
  local now = R.time_precise()
  local raw_pos, state = transport_position()
  local running = (state & 1) ~= 0 or (state & 4) ~= 0
  -- Text and project metadata do not need to be rebuilt at graphics-frame
  -- rate. The click rim uses a separate fresh-position path while active.
  local maximum_visual = false
  if running then
    Runtime.each_active_card(function(_, config)
      if config.type == "meter" and config.meter_display ~= "numeric"
          and config.meter_visual_quality == "maximum" then
        maximum_visual = true
      end
    end)
  end
  local interval = running and (maximum_visual and (1 / 60) or (1 / 30)) or (1 / 15)
  if not force and now - last_data_update < interval then return end
  last_data_update = now

  refresh_regions_if_needed(force)

  local pos = math.max(0, raw_pos + offset_seconds())
  local ts_num, ts_denom, tempo = R.TimeMap_GetTimeSigAtTime(0, pos)
  local current = current_region_at(pos)
  local next_region = next_named_item(regions, pos)
  local next_marker = next_named_item(markers, pos)
  local project_length = math.max(0, R.GetProjectLength(0) or 0)
  snapshot.raw_position, snapshot.position = raw_pos, pos
  snapshot.gap_display = nil
  snapshot.remaining_label = "REMAINING"
  snapshot.next_region_warning = false
  snapshot.next_marker_warning = false

  if (state & 4) ~= 0 then
    snapshot.transport_label, snapshot.transport_kind = "RECORDING", "recording"
  elseif (state & 2) ~= 0 then
    snapshot.transport_label, snapshot.transport_kind = "PAUSED", "paused"
  elseif (state & 1) ~= 0 then
    snapshot.transport_label, snapshot.transport_kind = "PLAYING", "playing"
  else
    snapshot.transport_label, snapshot.transport_kind = "STOPPED", "stopped"
  end

  local span_start, span_end
  local previous = settings.scope == "region" and previous_region_before(pos) or nil
  if settings.scope == "region" then
    if not current then
      if settings.gap_mode == "overtime" and previous then
        snapshot.blank = false
        snapshot.gap_display = "overtime"
        current = previous
        span_start, span_end = previous.start_pos, previous.end_pos
      else
        snapshot.blank = true
        snapshot.gap_display = settings.gap_mode == "next" and "next" or nil
      end
    else
      snapshot.blank = false
      span_start, span_end = current.start_pos, current.end_pos
    end
  elseif settings.scope == "selection" then
    local selection_start, selection_end = R.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if not selection_start or not selection_end or selection_end <= selection_start + 0.0000001
        or pos < selection_start or pos >= selection_end then
      snapshot.blank = true
    else
      snapshot.blank = false
      span_start, span_end = selection_start, selection_end
    end
  else
    snapshot.blank = false
    span_start, span_end = 0, project_length
  end

  if not snapshot.blank then
    local overtime = snapshot.gap_display == "overtime"
    local elapsed = overtime and math.max(0, pos - span_end) or math.max(0, pos - span_start)
    local length = math.max(0, span_end - span_start)
    local remaining = overtime and elapsed or math.max(0, span_end - pos)

    if settings.units == "beats" then
      if overtime then
        snapshot.main = "+" .. format_duration_bars_beats(span_end, pos, false)
      elseif settings.scope ~= "project" then
        snapshot.main = format_duration_bars_beats(span_start, pos, true)
      else
        snapshot.main = format_project_bars_beats(pos)
      end
      snapshot.length = format_duration_bars_beats(span_start, span_end, false)
      snapshot.remaining = overtime
        and ("+" .. format_duration_bars_beats(span_end, pos, false))
        or ("-" .. format_duration_bars_beats(pos, span_end, false, true))
      local end_position
      if settings.scope ~= "project" then
        end_position = format_duration_bars_beats(span_start, span_end, true)
      else
        end_position = format_project_bars_beats(project_length)
      end
      snapshot.main_fit_reference = bars_beats_fit_reference(
        snapshot.main, end_position, max_numerator_in_span(span_start, math.max(span_end, pos)))
    else
      snapshot.main = (overtime and "+" or "") .. format_time_value(elapsed, false)
      snapshot.length = format_time_value(length, false)
      snapshot.remaining = (overtime and "+" or "-") .. format_time_value(remaining, true)
      local reference_seconds = settings.scope == "project" and project_length or length
      if overtime then
        local gap_capacity = next_region and math.max(0, next_region.start_pos - span_end)
          or math.max(0, project_length - span_end)
        reference_seconds = math.max(reference_seconds, gap_capacity)
      end
      snapshot.main_fit_reference = (overtime and "+" or "")
        .. format_time_value(reference_seconds, false)
    end

    if overtime then snapshot.remaining_label = "OVERTIME" end
    snapshot.current_region = format_region_label(current)
    snapshot.progress = overtime and 1
      or (length > 0 and math.max(0, math.min(1, elapsed / length)) or 0)
  else
    snapshot.main = ""
    snapshot.main_fit_reference = ""
    snapshot.length = ""
    snapshot.remaining = ""
    snapshot.current_region = ""
    snapshot.progress = 0
  end

  local function update_upcoming(prefix, item)
    snapshot[prefix] = format_region_label(item)
    snapshot[prefix .. "_countdown"] = ""
    snapshot[prefix .. "_fit_reference"] = ""
    if not item then return end
    local cue_delta = math.max(0, item.start_pos - pos)
    local cue_reference_start = span_start or (previous and previous.end_pos) or 0
    cue_reference_start = math.min(cue_reference_start, pos, item.start_pos)
    if settings.units == "beats" then
      snapshot[prefix .. "_countdown"] = "-" .. format_duration_bars_beats(
        pos, item.start_pos, false, true)
      local full_countdown = "-" .. format_duration_bars_beats(
        cue_reference_start, item.start_pos, false, true)
      snapshot[prefix .. "_fit_reference"] = bars_beats_fit_reference(
        snapshot[prefix .. "_countdown"], full_countdown,
        max_numerator_in_span(cue_reference_start, item.start_pos))
    else
      snapshot[prefix .. "_countdown"] = "-" .. format_time_value(cue_delta, true)
      snapshot[prefix .. "_fit_reference"] = "-" .. format_time_value(
        math.max(0, item.start_pos - cue_reference_start), true)
    end
    snapshot[prefix .. "_warning"] =
      cue_delta <= settings.cue_warning_seconds + 0.0000001
  end
  update_upcoming("next_region", next_region)
  update_upcoming("next_marker", next_marker)

  snapshot.time_signature = string.format("%d/%d", ts_num or 4, ts_denom or 4)
  tempo = tonumber(tempo) or 120
  snapshot.tempo_value = tempo
  if math.abs(tempo - math.floor(tempo + 0.5)) < 0.005 then
    snapshot.tempo = tostring(math.floor(tempo + 0.5))
  else
    snapshot.tempo = string.format("%.1f", tempo)
  end

  snapshot.grid_visible = R.GetToggleCommandState(GRID_LINES_COMMAND) == 1
  snapshot.tempo_visible = not settings.hide_tempo_without_grid or snapshot.grid_visible
  Runtime.main_fit_reference = snapshot.main_fit_reference
  refresh_display_snapshots()
  -- Snapshot strings can change every second while recording even when their
  -- rendered width class does not. Refit only when the resulting layout height
  -- truly changes, avoiding needless forced geometry writes during a take.
  -- The bootstrap snapshot runs before the first deferred ImGui frame. Delay
  -- font-backed height measurement until loop() marks that frame available.
  if Runtime.defer_started then
    local snapshot_layout_height = current_base_height()
    if Runtime.snapshot_layout_height
        and math.abs(Runtime.snapshot_layout_height - snapshot_layout_height) > 0.5 then
      request_layout_resize()
    end
    Runtime.snapshot_layout_height = snapshot_layout_height
  end

  -- The disposable portable harness can request one exact render-model export.
  -- Normal users never enter this branch, and tests pay only one ExtState write
  -- burst per scenario rather than distorting the defer-loop CPU measurements.
  if Store.test_override then
    local request = R.GetExtState(EXT, "__snapshot_request")
    if request ~= "" and request ~= snapshot.test_export_token then
      snapshot.test_export_token = request
      local function export_value(key, value)
        value = tostring(value == nil and "" or value):gsub("[\r\n]", " ")
        R.SetExtState(EXT, "__snapshot_" .. key, value, false)
      end
      local values = {
        blank = snapshot.blank, gap_display = snapshot.gap_display or "",
        main = snapshot.main, main_fit_reference = snapshot.main_fit_reference,
        length = snapshot.length, remaining = snapshot.remaining,
        remaining_label = snapshot.remaining_label,
        current_region = snapshot.current_region,
        next_region = snapshot.next_region,
        next_region_countdown = snapshot.next_region_countdown,
        next_region_fit_reference = snapshot.next_region_fit_reference,
        next_region_warning = snapshot.next_region_warning,
        next_marker = snapshot.next_marker,
        next_marker_countdown = snapshot.next_marker_countdown,
        next_marker_fit_reference = snapshot.next_marker_fit_reference,
        next_marker_warning = snapshot.next_marker_warning,
        progress = snapshot.progress,
        tempo = snapshot.tempo, time_signature = snapshot.time_signature,
        grid_visible = snapshot.grid_visible, tempo_visible = snapshot.tempo_visible,
        transport_label = snapshot.transport_label,
        transport_kind = snapshot.transport_kind,
        raw_position = snapshot.raw_position, position = snapshot.position,
        scroll_overflow = Runtime.last_scroll_metrics and Runtime.last_scroll_metrics.overflow or "",
        scroll_speed = Runtime.last_scroll_metrics and Runtime.last_scroll_metrics.speed or "",
        scroll_travel_seconds = Runtime.last_scroll_metrics and Runtime.last_scroll_metrics.travel or "",
        scroll_pause_seconds = Runtime.last_scroll_metrics and Runtime.last_scroll_metrics.pause or "",
        meter_source_count = #(Runtime.metering.sources or {}),
        meter_gmem_attached = Runtime.metering.gmem_attached == true,
      }
      local first_card_config = settings.cards[1] or {}
      values.meter_spectrogram_config_fft_size =
        first_card_config.meter_spectrum_fft_size or ""
      values.meter_spectrogram_config_scale =
        first_card_config.meter_spectrogram_scale or ""
      values.meter_spectrogram_config_mode =
        first_card_config.meter_spectrogram_mode or ""
      values.meter_spectrogram_config_tilt =
        first_card_config.meter_spectrogram_tilt or ""
      local first_meter_source = Runtime.metering.sources and Runtime.metering.sources[1]
      if first_meter_source then
        values.meter_source_api = first_meter_source.api_version
        values.meter_source_compatible = first_meter_source.compatible == true
        values.meter_source_current = first_meter_source.current_build == true
        values.meter_source_update_pending = first_meter_source.update_pending == true
        values.meter_runtime_api = first_meter_source.runtime and first_meter_source.runtime.api or ""
        values.meter_runtime_status = first_meter_source.runtime and first_meter_source.runtime.status or ""
        local budget = Runtime.metering.visual.profile_budget
          and Runtime.metering.visual.profile_budget[first_meter_source.key]
        values.meter_profile_requested = budget and budget.requested or 0
        values.meter_profile_used = budget and budget.used or 0
        values.meter_profile_limit = budget and budget.limit or Metering.Visual.profile_limit
      end
      local stream_count = 0
      for _ in pairs(Runtime.metering.visual.streams or {}) do stream_count = stream_count + 1 end
      for _, meter_stream in pairs(Runtime.metering.visual.streams or {}) do
        values.meter_stream_sequence = meter_stream.sequence or ""
        values.meter_stream_invalid_count = meter_stream.invalid_count or 0
        values.meter_stream_last_error = meter_stream.last_read_error or ""
        values.meter_stream_error = meter_stream.error or ""
        values.meter_stream_channels = meter_stream.frame and meter_stream.frame.channels or ""
        values.meter_stream_effective_quality = meter_stream.frame
          and meter_stream.frame.effective_quality or ""
        break
      end
      values.meter_stream_count = stream_count
      for _, meter_cache in pairs(Runtime.metering.visual.card_data or {}) do
        local ring = meter_cache.spectrogram
        if ring and ring.image then
          values.meter_spectrogram_column_rate = ring.column_rate or ""
          values.meter_spectrogram_image_width = ring.image_width or ""
          values.meter_spectrogram_image_height = ring.image_height or ""
          values.meter_spectrogram_bins = ring.bins or ""
          values.meter_spectrogram_columns_written = ring.columns_written or 0
          values.meter_spectrogram_tail_ready = ring.tail_image ~= nil
          values.meter_spectrogram_fractional_frames = ring.test_fractional_frames or 0
          values.meter_spectrogram_history_batch = ring.history_batch or 0
          values.meter_spectrogram_max_history_batch = ring.max_history_batch or 0
          values.meter_spectrogram_source_columns = ring.source_columns or 0
          values.meter_spectrogram_history_dropped = ring.history_dropped or 0
          values.meter_spectrogram_history_warmup_dropped =
            ring.history_warmup_dropped or 0
          values.meter_spectrogram_history_steady_dropped =
            ring.history_steady_dropped or 0
          break
        end
      end
      for key, value in pairs(values) do export_value(key, value) end
      for row = 1, MAX_CARD_ROWS do
        export_value("row_" .. row .. "_visible", Runtime.row_visible[row] == true)
      end
      for index = 1, TOTAL_CARD_SLOTS do
        local card = snapshot.cards[index] or {}
        export_value("card_" .. index .. "_visible", card.visible == true)
        export_value("card_" .. index .. "_label", card.label or "")
        export_value("card_" .. index .. "_value", card.value or "")
        export_value("card_" .. index .. "_font", card.font or "")
        export_value("card_" .. index .. "_fit_mode", card.fit_mode or "")
        export_value("card_" .. index .. "_fit_reference", card.fit_reference or "")
        export_value("card_" .. index .. "_keep_visible", card.keep_visible == true)
        export_value("card_" .. index .. "_action_button", card.action_button == true)
        export_value("card_" .. index .. "_action_available", card.action_available == true)
        export_value("card_" .. index .. "_action_toggle", card.action_toggle == true)
        export_value("card_" .. index .. "_action_toggled", card.action_toggled == true)
      end
      R.SetExtState(EXT, "__snapshot_response", request, false)
    end
  end
end
end

-- -----------------------------------------------------------------------------
-- Drawing helpers
-- -----------------------------------------------------------------------------

local function utf8_prefix(text, count)
  if count <= 0 then return "" end
  if utf8 and utf8.offset then
    local text_len = utf8.len(text)
    if text_len and count >= text_len then return text end
    local next_index = utf8.offset(text, count + 1)
    if next_index then return text:sub(1, next_index - 1) end
  end
  return text:sub(1, count)
end

local function utf8_count(text)
  if utf8 and utf8.len then return utf8.len(text) or #text end
  return #text
end

local function truncate_current_font(text, max_width)
  local width = R.ImGui_CalcTextSize(ctx, text)
  if width <= max_width then return text end

  local suffix = "…"
  local low, high = 0, utf8_count(text)
  while low < high do
    local mid = math.floor((low + high + 1) / 2)
    local candidate = utf8_prefix(text, mid) .. suffix
    local candidate_width = R.ImGui_CalcTextSize(ctx, candidate)
    if candidate_width <= max_width then low = mid else high = mid - 1 end
  end
  return utf8_prefix(text, low) .. suffix
end

local function draw_text_box(draw_list, font, text, x, y, w, h, font_size, color,
    align_x, fit_mode, fit_reference, scroll_key)
  if not text or text == "" then return end
  align_x = align_x or 0
  local size = math.max(6, font_size)

  R.ImGui_PushFont(ctx, font, size)
  local render_text = text
  local text_w, text_h = R.ImGui_CalcTextSize(ctx, render_text)
  local scroll_offset, scroll_overflow
  local fit_w = text_w
  if fit_reference and fit_reference ~= "" then
    local reference_w = R.ImGui_CalcTextSize(ctx, fit_reference)
    fit_w = math.max(fit_w, reference_w)
  end

  if fit_mode == "shrink" and fit_w > w and fit_w > 0 then
    R.ImGui_PopFont(ctx)
    size = math.max(6, size * (w / fit_w))
    R.ImGui_PushFont(ctx, font, size)
    text_w, text_h = R.ImGui_CalcTextSize(ctx, render_text)
  elseif fit_mode == "ellipsis" and text_w > w then
    render_text = truncate_current_font(render_text, w)
    text_w, text_h = R.ImGui_CalcTextSize(ctx, render_text)
  elseif fit_mode == "scroll" and text_w > w then
    local key = tostring(scroll_key or render_text)
    local state = Runtime.card_scroll_states[key]
    local now = R.time_precise()
    if not state or state.text ~= render_text or math.abs(state.width - w) > 0.5 then
      state = { text = render_text, width = w, started_at = now }
      Runtime.card_scroll_states[key] = state
    end
    local overflow = text_w - w
    scroll_overflow = overflow
    local pause = Runtime.scroll_pause_seconds
    -- Bound the one-way traversal instead of capping speed: short overflow
    -- still glides slowly, while a very long region name remains readable
    -- without making the user wait a minute to see its other end.
    local speed = math.max(28, overflow / Runtime.scroll_traverse_seconds)
    local travel = overflow / speed
    if Store.test_override then
      Runtime.last_scroll_metrics = {
        overflow = overflow, speed = speed, travel = travel, pause = pause,
      }
    end
    local phase = (now - state.started_at) % (pause * 2 + travel * 2)
    if phase <= pause then
      scroll_offset = 0
    elseif phase <= pause + travel then
      scroll_offset = (phase - pause) * speed
    elseif phase <= pause * 2 + travel then
      scroll_offset = overflow
    else
      scroll_offset = overflow - (phase - pause * 2 - travel) * speed
    end
  elseif fit_mode == "scroll" and scroll_key then
    Runtime.card_scroll_states[tostring(scroll_key)] = nil
  end

  local tx = x + math.max(0, w - text_w) * align_x - (scroll_offset or 0)
  local ty = y + math.max(0, h - text_h) * 0.5
  if scroll_offset then
    R.ImGui_DrawList_PushClipRect(draw_list, x, y, x + w, y + h, false)
  end
  R.ImGui_DrawList_AddText(draw_list, tx, ty, color, render_text)
  if scroll_offset then R.ImGui_DrawList_PopClipRect(draw_list) end
  if scroll_offset and scroll_overflow then
    -- A short surface-colored edge fade avoids chopped half-glyphs while the
    -- marquee crosses either clip boundary. It disappears at the readable end.
    local fade = math.min(14, math.max(6, size * 0.22))
    local clear = with_alpha(C.tile, 0)
    if scroll_offset > 0.5 then
      R.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + fade, y + h,
        C.tile, clear, clear, C.tile)
    end
    if scroll_offset < scroll_overflow - 0.5 then
      R.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x + w - fade, y, x + w, y + h,
        clear, C.tile, C.tile, clear)
    end
  end
  R.ImGui_PopFont(ctx)
end

local function draw_icon_centered(draw_list, glyph, x, y, w, h, size, color, y_nudge)
  if not font_icon or not glyph or glyph == "" then return false end
  size = math.max(6, size)
  R.ImGui_PushFont(ctx, font_icon, size)
  local text_w, text_h = R.ImGui_CalcTextSize(ctx, glyph)
  R.ImGui_DrawList_AddText(draw_list,
    x + math.max(0, w - text_w) * 0.5,
    y + math.max(0, h - text_h) * 0.5 + (y_nudge or 0),
    color, glyph)
  R.ImGui_PopFont(ctx)
  return true
end

local function draw_segment_button(label, id, x, y, w, h, selected, scale, alpha,
    left_align)
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  local button = selected and C.toggle_selected or C.tile
  local hovered = selected and C.toggle_selected_hover or C.inactive_hover
  local active = selected and C.toggle_selected_active or C.inactive_active
  local text_color = selected and C.toggle_text or C.ink
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  R.ImGui_PushFont(ctx, font_bold, math.max(5, 10.5 * scale))
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5 * scale)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), math.max(1, scale))
  if left_align then
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ButtonTextAlign(), 0.12, 0.5)
  end
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),
    with_alpha(button, math.floor((button & 0xFF) * alpha)))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), hovered)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(),
    with_alpha(text_color, math.floor((text_color & 0xFF) * alpha)))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(),
    with_alpha(selected and C.accent or C.border, math.floor(255 * alpha)))
  local clicked = R.ImGui_Button(ctx, label .. "##" .. id, w, h)
  local item_hovered = R.ImGui_IsItemHovered(ctx)
  R.ImGui_PopStyleColor(ctx, 5)
  R.ImGui_PopStyleVar(ctx, left_align and 3 or 2)
  R.ImGui_PopFont(ctx)
  return clicked, item_hovered
end

local function draw_icon_button(draw_list, glyph, id, x, y, w, h, selected,
    enabled, scale, alpha, icon_size, y_nudge, quiet_idle)
  enabled = enabled ~= false
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  local transparent_idle = quiet_idle and not selected
  local button = selected and C.toggle_selected or C.tile
  local hover_fill = selected and C.toggle_selected_hover or C.inactive_hover
  local active_fill = selected and C.toggle_selected_active or C.inactive_active
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5 * scale)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(),
    transparent_idle and 0 or math.max(1, scale))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),
    with_alpha(button, transparent_idle and 0
      or math.floor((button & 0xFF) * alpha)))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), hover_fill)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), active_fill)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(),
    with_alpha(selected and C.accent or C.border, math.floor(255 * alpha)))
  local clicked = R.ImGui_Button(ctx, "##" .. id, w, h)
  local hovered = R.ImGui_IsItemHovered(ctx)
  R.ImGui_PopStyleColor(ctx, 4)
  R.ImGui_PopStyleVar(ctx, 2)

  local icon_color = enabled and (selected and C.toggle_text
      or hovered and C.accent_secondary or C.secondary)
    or C.muted
  icon_color = with_alpha(icon_color,
    math.floor((icon_color & 0xFF) * alpha * (enabled and 1 or 0.65)))
  draw_icon_centered(draw_list, glyph, x, y, w, h,
    icon_size or math.max(6, 15 * scale), icon_color, y_nudge)
  return clicked and enabled, hovered
end

local function draw_styled_tooltip(title, detail)
  if not title or title == "" then return end
  detail = detail or ""
  Runtime.tooltip.request = {
    key = title .. "\0" .. detail,
    title = title,
    detail = detail,
  }
end

Runtime.draw_active_tooltip = function()
  local tooltip, now = Runtime.tooltip, R.time_precise()
  local request = tooltip.request
  if request then
    if tooltip.key ~= request.key then
      tooltip.key = request.key
      tooltip.title, tooltip.detail = request.title, request.detail
      tooltip.hover_started = now
      tooltip.alpha = 0
    end
    tooltip.fade_started = nil
    local elapsed = now - tooltip.hover_started - tooltip.delay
    tooltip.alpha = elapsed > 0 and math.min(1, elapsed / tooltip.fade_in) or 0
  elseif tooltip.key then
    if not tooltip.fade_started then
      tooltip.fade_started, tooltip.fade_from = now, tooltip.alpha
    end
    local elapsed = now - tooltip.fade_started
    tooltip.alpha = tooltip.fade_from * math.max(0, 1 - elapsed / tooltip.fade_out)
    if tooltip.alpha <= 0 then
      tooltip.key, tooltip.title, tooltip.detail = nil, nil, nil
      tooltip.fade_started, tooltip.fade_from = nil, 0
      return
    end
  else
    return
  end
  if tooltip.alpha <= 0 then return end

  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_PopupBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), C.border)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.ink)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_Alpha(), tooltip.alpha)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 13, 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 6)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 8, 5)
  if R.ImGui_BeginTooltip(ctx) then
    R.ImGui_PushTextWrapPos(ctx, tooltip.wrap_width)
    R.ImGui_PushFont(ctx, font_bold, 12.5)
    R.ImGui_Text(ctx, tooltip.title)
    R.ImGui_PopFont(ctx)
    if tooltip.detail ~= "" then
      R.ImGui_PushFont(ctx, font_regular, 12.5)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
      R.ImGui_Text(ctx, tooltip.detail)
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)
    end
    R.ImGui_PopTextWrapPos(ctx)
    R.ImGui_EndTooltip(ctx)
  end
  R.ImGui_PopStyleVar(ctx, 5)
  R.ImGui_PopStyleColor(ctx, 3)
end

local function item_tooltip(title, detail)
  if R.ImGui_IsItemHovered and R.ImGui_IsItemHovered(ctx) then
    draw_styled_tooltip(title, detail)
  end
end

Content = {}
Content.actions = {}

-- Shared surface tokens for Settings and every authored popup. Keeping these
-- layers together prevents context menus, content choosers, and editor token
-- pickers from drifting away from the compact card-based Settings language.
function Content.settings_surface_palette()
  local light = color_luminance(C.surface) > 0.45
  local surface_r, surface_g, surface_b = color_channels(C.surface)
  local near_black = surface_r + surface_g + surface_b < 48
  return {
    body = contrast_layer(C.surface, 0.025),
    card = light and C.lift_color(C.surface, 5, 8, 8)
      or contrast_layer(C.surface, 0.052),
    selected = light and C.lift_color(C.surface, 9, 16, 15)
      or near_black and mix_color(C.surface, C.ink, 0.30)
      or contrast_layer(C.surface, 0.10),
    selected_border = near_black and with_alpha(C.accent, 220)
      or with_alpha(C.border, 75),
    control = light and C.lift_color(C.tile, 2, 4, 5)
      or contrast_layer(C.tile, 0.035),
    segment = mix_color(C.surface, C.ink, 0.08),
    label = light and (C.card_accents and C.card_accents[1]
        or mix_color(C.accent, C.ink, 0.28))
      or mix_color(C.accent, C.ink, 0.20),
    subtle_border = light and with_alpha(C.ink, 26)
      or with_alpha(C.border, 125),
  }
end

local function shortcut_hint(key)
  return settings.keyboard_shortcuts_enabled
    and (" Shortcut: " .. key .. ".")
    or (" Enable keyboard shortcuts in Settings to use " .. key .. ".")
end

Content.controls = {
  alpha = 1,
  utility_alpha = 1,
  last_hover = R.time_precise(),
  last_frame = R.time_precise(),
  popup_was_open = false,
}
Content.context_click_claimed = false
Content.card_click = {
  pending = nil,
  primary_delay = 0.34,
}
Content.actions.catalog = nil
Content.actions.catalog_by_command = nil
Content.actions.section = nil
Content.actions.searches = {}
Content.actions.feedback = {}

function Content.actions.main_section()
  if not Content.actions.section and R.SectionFromUniqueID then
    Content.actions.section = R.SectionFromUniqueID(0)
  end
  return Content.actions.section
end

local function trim_action_identifier(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function Content.actions.resolve(identifier)
  identifier = trim_action_identifier(identifier)
  if identifier == "" then return nil, "Choose a Main-section action." end
  local command
  if identifier:match("^%d+$") then
    command = tonumber(identifier)
  elseif R.NamedCommandLookup then
    command = R.NamedCommandLookup(identifier)
  end
  if not command or command <= 0 then return nil, "Action ID was not found." end
  local section = Content.actions.main_section()
  local name = section and R.kbd_getTextFromCmd
    and tostring(R.kbd_getTextFromCmd(command, section) or "") or ""
  if name == "" then return nil, "Action is not available in REAPER's Main section." end
  return { command = command, name = name, identifier = identifier }
end

-- REAPER reports -1 for commands that do not expose a persistent toggle
-- state. Preserve that distinction so momentary actions keep ordinary button
-- styling while real toggles can mirror changes made from any REAPER surface.
function Content.actions.toggle_state(command)
  command = tonumber(command)
  if not command or command <= 0 or not R.GetToggleCommandStateEx then return nil end
  local state = tonumber(R.GetToggleCommandStateEx(0, command))
  if not state or state < 0 then return nil end
  return state > 0
end

function Content.actions.ensure_catalog(force)
  if Content.actions.catalog and not force then return Content.actions.catalog end
  local section = Content.actions.main_section()
  local catalog, by_command = {}, {}
  if section and R.kbd_enumerateActions then
    for index = 0, 100000 do
      local command, name = R.kbd_enumerateActions(section, index)
      if not command or command == 0 then break end
      name = tostring(name or "")
      if name == "" and R.kbd_getTextFromCmd then
        name = tostring(R.kbd_getTextFromCmd(command, section) or "")
      end
      if name ~= "" then
        local named = R.ReverseNamedCommandLookup
          and tostring(R.ReverseNamedCommandLookup(command) or "") or ""
        local identifier = named ~= "" and named or tostring(command)
        local item = {
          command = command,
          identifier = identifier,
          name = name,
          search = (name .. " " .. identifier .. " " .. tostring(command)):lower(),
        }
        catalog[#catalog + 1] = item
        by_command[command] = item
      end
    end
  end
  table.sort(catalog, function(a, b)
    local left, right = a.name:lower(), b.name:lower()
    return left == right and a.identifier < b.identifier or left < right
  end)
  Content.actions.catalog, Content.actions.catalog_by_command = catalog, by_command
  return catalog
end

function Content.actions.search(query, limit)
  local words = {}
  for word in trim_action_identifier(query):lower():gmatch("%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then return {}, 0 end
  local results, total = {}, 0
  for _, item in ipairs(Content.actions.ensure_catalog(false)) do
    local matches = true
    for _, word in ipairs(words) do
      if not item.search:find(word, 1, true) then matches = false break end
    end
    if matches then
      total = total + 1
      if #results < (limit or 60) then results[#results + 1] = item end
    end
  end
  return results, total
end

function Content.actions.bind(config, prefix, identifier, name)
  identifier = trim_action_identifier(identifier)
  local resolved = Content.actions.resolve(identifier)
  config.action_command = identifier
  config.action_name = resolved and resolved.name or tostring(name or "")
  local detached_id = tostring(prefix):match("^detached_(%d+)$")
  if detached_id then
    Content.save_card(-tonumber(detached_id))
  else
    save_string(prefix .. "_action_command", config.action_command)
    save_string(prefix .. "_action_name", config.action_name)
    if Content.save_active_face then Content.save_active_face() end
  end
  recompute_snapshot(true)
  return resolved
end

function Content.actions.execute_card(card_index)
  local config = settings.cards[card_index]
  local resolved, error_message = config and Content.actions.resolve(config.action_command)
  if not resolved then
    Content.actions.feedback[card_index] = {
      error = error_message or "Action is unavailable.", at = R.time_precise(),
    }
    return false
  end
  local toggle_before = Content.actions.toggle_state(resolved.command)
  R.Main_OnCommand(resolved.command, 0)
  local toggle_after = Content.actions.toggle_state(resolved.command)
  if Store.test_override then
    local test_root = os.getenv("CIVIL_CLOCK_TEST_ROOT") or ""
    local file = test_root ~= "" and io.open(test_root .. "\\action-button-events.txt", "ab")
    if file then
      file:write(string.format("command=%d identifier=%s name=%s\n",
        resolved.command, resolved.identifier, resolved.name))
      file:close()
    end
    local toggle_file = test_root ~= ""
      and io.open(test_root .. "\\action-button-toggle-state.txt", "ab")
    if toggle_file then
      local function state_text(state)
        return state == nil and "unsupported" or state and "on" or "off"
      end
      toggle_file:write(string.format("command=%d before=%s after=%s\n",
        resolved.command, state_text(toggle_before), state_text(toggle_after)))
      toggle_file:close()
    end
  end
  Content.actions.feedback[card_index] = { command = resolved.command, at = R.time_precise() }
  return true
end
Content.common_type_ids = {
  "length", "remaining", "position", "current_region", "next_region", "transport",
}

function Content.handle_main_shortcuts()
  if not settings.keyboard_shortcuts_enabled
      or not R.ImGui_IsWindowFocused(ctx)
      or settings_open or detail_editor.open or face_dialog.action
      or Content.controls.popup_was_open
      or R.ImGui_IsPopupOpen(ctx, "", R.ImGui_PopupFlags_AnyPopup())
      or (R.ImGui_IsAnyItemActive and R.ImGui_IsAnyItemActive(ctx)) then
    return
  end
  if R.ImGui_GetKeyMods and R.ImGui_GetKeyMods(ctx) ~= 0 then return end

  local function pressed(key_factory)
    return type(key_factory) == "function"
      and R.ImGui_IsKeyPressed(ctx, key_factory(), false)
  end
  local used = false
  if pressed(R.ImGui_Key_E) then
    edit_mode = not edit_mode
    if edit_mode then
      edit_selected_row = math.max(1, math.min(settings.card_rows, 1))
      edit_selected_card = settings.card_rows > 0
        and ((edit_selected_row - 1) * CARDS_PER_ROW + 1) or 1
    end
    request_layout_resize()
    used = true
  end

  local scope
  if pressed(R.ImGui_Key_P) then scope = "project"
  elseif pressed(R.ImGui_Key_R) then scope = "region"
  elseif pressed(R.ImGui_Key_S) then scope = "selection" end
  if scope and settings.scope ~= scope then
    settings.scope = scope
    save_string("scope", scope)
    recompute_snapshot(true)
    used = true
  end

  local units
  if pressed(R.ImGui_Key_T) then units = "time"
  elseif pressed(R.ImGui_Key_B) then units = "beats" end
  if units and settings.units ~= units then
    settings.units = units
    save_string("units", units)
    recompute_snapshot(true)
    used = true
  end
  if used then Content.controls.last_hover = R.time_precise() end
end

function Content.update_control_fade()
  local controls, now = Content.controls, R.time_precise()
  if not settings.fade_controls then
    controls.alpha, controls.utility_alpha = 1, 1
    controls.last_hover, controls.last_frame = now, now
    return 1, 1
  end
  local hovered = R.ImGui_IsWindowHovered and R.ImGui_IsWindowHovered(ctx)
  local focused = R.ImGui_IsWindowFocused and R.ImGui_IsWindowFocused(ctx)
  local recovery_badge_active = Store.warning and not Store.warning_acknowledged
    and now - (Store.warning_started_at or 0) < 8
  local force_visible = hovered or edit_mode or settings_open or detail_editor.open
    or snapshot.transport_kind == "recording" or controls.popup_was_open
    or recovery_badge_active
  if force_visible then controls.last_hover = now end
  local target = (force_visible or now - controls.last_hover < 1.15) and 1 or 0.58
  local elapsed = math.max(0, math.min(0.1, now - controls.last_frame))
  local speed = target > controls.alpha and 12 or 5
  controls.alpha = controls.alpha + (target - controls.alpha) * math.min(1, elapsed * speed)
  -- Fullscreen, Edit, and Settings are the only persistent controls in the
  -- performance view. Let them recede farther when the clock is neither the
  -- active window nor under the pointer, while retaining the standard idle
  -- treatment as soon as the user returns to ReaClock.
  local utility_target = (hovered or focused) and target or 0.34
  local utility_speed = utility_target > controls.utility_alpha and 12 or 5
  controls.utility_alpha = controls.utility_alpha
    + (utility_target - controls.utility_alpha) * math.min(1, elapsed * utility_speed)
  controls.last_frame = now
  return controls.alpha, controls.utility_alpha
end

function Content.open_detail_editor(kind, id)
  detail_editor.kind, detail_editor.id, detail_editor.open = kind, id, true
  detail_editor.focus_requested = true
  -- Toggle the native TopMost hint across two frames as well as keeping it
  -- persistent. This reasserts ordering if Windows or another application
  -- explicitly demoted an already-open ReaImGui viewport.
  detail_editor.topmost_reassert = 2
end

function Content.execute_card_primary_action(action)
  if not action then return end
  if action.kind == "setup" then
    local config = settings.cards[action.card_index]
    if config and config.type == "custom" then
      -- Custom Templates configure their shared meter source inside Card
      -- Details. Route the face affordance there instead of sending a custom
      -- card through the Metering-only source chooser, which rejects it.
      Content.open_detail_editor("card", action.card_index)
    else
      Metering.request_source_setup(action.card_index)
    end
  elseif action.kind == "reset" and action.source then
    local okay, detail = Metering.request_reset(action.source, "card_click")
    Runtime.metering.operation_error = not okay and detail or nil
  elseif action.kind == "reaper_action" and action.card_index then
    Content.actions.execute_card(action.card_index)
  end
end

function Content.process_pending_card_action()
  local pending = Content.card_click.pending
  if not pending or R.time_precise() < pending.due then return end
  Content.card_click.pending = nil
  Content.execute_card_primary_action(pending)
end

function Content.queue_card_primary_action(action)
  if Content.card_click.pending then
    Content.execute_card_primary_action(Content.card_click.pending)
  end
  action.due = R.time_precise() + Content.card_click.primary_delay
  Content.card_click.pending = action
end

function Content.open_card_detail_from_double_click(card_index)
  local pending = Content.card_click.pending
  if pending and pending.card_index == card_index then Content.card_click.pending = nil end
  Content.open_detail_editor("card", card_index)
end

function Content.draw_presentation_button(draw_list, scale, x, y, w, h, alpha)
  local selected, enabled = presentation_mode, main_dock_id == 0
  alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
  local clicked, hovered
  if font_icon then
    clicked, hovered = draw_icon_button(draw_list,
      selected and ICON.MINIMIZE or ICON.MAXIMIZE,
      "presentation_toggle", x, y, w, h, selected, enabled, scale, alpha,
      math.max(6, 15 * scale), scale, true)
  else
    local button = selected and C.toggle_selected or C.tile
    R.ImGui_SetCursorScreenPos(ctx, x, y)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5 * scale)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(),
      math.max(1, scale))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),
      with_alpha(button, math.floor((button & 0xFF) * alpha)))
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(),
      selected and C.toggle_selected_hover or C.inactive_hover)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(),
      selected and C.toggle_selected_active or C.inactive_active)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(),
      with_alpha(selected and C.accent or C.border, math.floor(255 * alpha)))
    clicked = R.ImGui_Button(ctx, "##presentation_toggle", w, h)
    hovered = R.ImGui_IsItemHovered(ctx)
    R.ImGui_PopStyleColor(ctx, 4)
    R.ImGui_PopStyleVar(ctx, 2)

    local color = enabled and (selected and C.toggle_text or C.secondary) or C.muted
    color = with_alpha(color, math.floor((color & 0xFF) * alpha))
    local cx, cy, half, arm = x + w * 0.5, y + h * 0.5, 6 * scale, 4 * scale
    local thickness = math.max(1, 1.35 * scale)
    R.ImGui_DrawList_AddLine(draw_list, cx - half, cy - half,
      cx - half + arm, cy - half, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx - half, cy - half,
      cx - half, cy - half + arm, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx + half, cy - half,
      cx + half - arm, cy - half, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx + half, cy - half,
      cx + half, cy - half + arm, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx - half, cy + half,
      cx - half + arm, cy + half, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx - half, cy + half,
      cx - half, cy + half - arm, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx + half, cy + half,
      cx + half - arm, cy + half, color, thickness)
    R.ImGui_DrawList_AddLine(draw_list, cx + half, cy + half,
      cx + half, cy + half - arm, color, thickness)
    clicked = clicked and enabled
  end
  if hovered then
    draw_styled_tooltip(selected and "Exit fullscreen" or "Fullscreen presentation",
      enabled and (selected
        and "Drag anywhere outside the utility buttons to move the face vertically. Click here to return to the previous floating window."
        or "Fill the current monitor with a borderless canvas while keeping the complete face undistorted.")
        or "Undock ReaClock before entering fullscreen presentation.")
  end
  return clicked, hovered
end

function Content.update_presentation_drag(scale, controls_hovered, face_y)
  if not presentation_mode or edit_mode then
    presentation_drag.active = false
    presentation_drag.origin_y = nil
    return
  end

  local button = R.ImGui_MouseButton_Left()
  if not presentation_drag.active
      and not controls_hovered
      and R.ImGui_IsWindowHovered(ctx)
      and R.ImGui_IsMouseClicked(ctx, button) then
    presentation_drag.active = true
    presentation_drag.origin_y = face_y
  end

  if presentation_drag.active and R.ImGui_IsMouseDown(ctx, button) then
    local _, drag_y = R.ImGui_GetMouseDragDelta(ctx, nil, nil, button, 0.0)
    if math.abs(drag_y) >= math.max(2, 2 * scale) then
      presentation_drag.target_y = presentation_drag.origin_y + drag_y
    end
  elseif presentation_drag.active then
    presentation_drag.active = false
    presentation_drag.origin_y = nil
  end
end

function Content.clone_card(card)
  local clone = {
    type = card.type,
    label = card.label,
    template = card.template,
    font = card.font,
    scroll = card.scroll == true,
    show_title = card.show_title ~= false,
    align = card.align or "default",
    span = normalize_card_span(card.span),
  }
  for _, field in ipairs(METER_CARD_FIELDS) do
    clone[field.key] = normalize_meter_field(field, card[field.key])
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    clone[field.key] = Runtime.normalize_action_field(card[field.key], field.default)
  end
  return clone
end

function Content.save_card(index, preserve_builtin_face)
  local card = settings.cards[index]
  if not card then return end
  if index < 0 then
    Store.root.detached_cards = settings.detached_cards
    Store.root.detached_next = settings.detached_next
    Store.mark_dirty()
    if Runtime.metering and Runtime.metering.visual then
      Runtime.metering.visual.compile_dirty = true
    end
    return
  end
  save_string("card_" .. index .. "_type", card.type)
  save_string("card_" .. index .. "_label", card.label)
  save_string("card_" .. index .. "_template", card.template)
  save_string("card_" .. index .. "_font", card.font)
  save_bool("card_" .. index .. "_scroll", card.scroll)
  save_bool("card_" .. index .. "_show_title", card.show_title ~= false)
  save_string("card_" .. index .. "_align", card.align or "default")
  save_string("card_" .. index .. "_span", card.span or "auto")
  for _, field in ipairs(METER_CARD_FIELDS) do
    local key, value = "card_" .. index .. "_" .. field.key, card[field.key]
    if field.kind == "boolean" then save_bool(key, value) else save_string(key, value) end
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    save_string("card_" .. index .. "_" .. field.key, card[field.key])
  end
  if Runtime.metering and Runtime.metering.visual then
    Runtime.metering.visual.compile_dirty = true
  end
  if Content.save_active_face and not (preserve_builtin_face
      and METER_FACE_IDS[settings.active_face]) then Content.save_active_face() end
end

function Content.new_card(card_type)
  local templates = {
    length = "{length}", remaining = "{remaining}", position = "{position}",
    tempo = "{tempo}", time_signature = "{timesig}", current_region = "{region}",
    visual_click = "",
    next_region = "{next_region}", next_region_countdown = "{next_region_countdown}",
    next_marker = "{next_marker}", next_marker_countdown = "{next_marker_countdown}",
    transport = "{transport}", project = "{project}", time12 = "{time12}",
    time24 = "{time24}", date = "{date}",
  }
  local card = Runtime.add_card_field_defaults({
    type = CARD_TYPE_BY_ID[card_type] and card_type or "none",
    label = "CUSTOM",
    template = templates[card_type] or "",
    font = "auto",
    scroll = false,
    show_title = card_type ~= "action",
    align = card_type == "action" and "center" or "default",
    span = card_type == "meter" and "6" or "auto",
  })
  return card
end

local row_card_index, card_row_column

function Content.detached_entry(index)
  return settings.detached_by_index[index]
end

function Content.detached_label(entry)
  if not entry or not entry.card then return "Pop-Out Card" end
  local option = CARD_TYPE_BY_ID[entry.card.type]
  if entry.card.type == "custom" and entry.card.label ~= "" then return entry.card.label end
  if entry.card.type == "action" and entry.card.action_text ~= "" then
    return entry.card.action_text
  end
  if entry.card.type == "meter" then
    if entry.card.meter_display == "numeric" then
      local metric = Metering.metrics[entry.card.meter_metric]
      return metric and metric.label or "Metering"
    end
    for _, display in ipairs(Metering.visual_menus) do
      if display[2] == entry.card.meter_display then return display[1] end
    end
  end
  return option and option.label or "Pop-Out Card"
end

function Content.create_detached(card, open_editor)
  if #settings.detached_cards >= 32 then
    Content.set_detached_error("ReaClock supports up to 32 independent pop-out cards.")
    return nil
  end
  Runtime.detached.error = nil
  local id = math.max(1, math.floor(tonumber(settings.detached_next) or 1))
  while settings.detached_by_index[-id] do id = id + 1 end
  local owner = Runtime.settings_owner_geometry or { x = 120, y = 120, w = 918, h = 600 }
  local config = Content.clone_card(card or Content.new_card("position"))
  config.span = "auto"
  local entry = {
    id = id, open = true,
    x = owner.x + 52 + (#settings.detached_cards % 5) * 24,
    y = owner.y + 52 + (#settings.detached_cards % 5) * 24,
    w = config.type == "meter" and config.meter_display ~= "numeric" and 720 or 560,
    h = config.type == "meter" and config.meter_display ~= "numeric" and 360 or 220,
    card = config,
    defaults = Content.clone_card(config),
  }
  settings.detached_cards[#settings.detached_cards + 1] = entry
  settings.detached_by_index[-id], settings.cards[-id] = entry, entry.card
  settings.detached_next, Store.root.detached_next = id + 1, id + 1
  Store.root.detached_cards = settings.detached_cards
  Store.mark_dirty()
  Runtime.detached.applied[id] = nil
  if Runtime.metering and Runtime.metering.visual then
    Runtime.metering.visual.compile_dirty = true
  end
  recompute_snapshot(true)
  if open_editor then Content.open_detail_editor("card", -id) end
  return -id
end

function Content.remove_detached_now(index)
  local entry = settings.detached_by_index[index]
  if not entry then return false end
  if detail_editor.open and tonumber(detail_editor.id) == index then detail_editor.open = false end
  if Runtime.card_fullscreen and Runtime.card_fullscreen.index == index then
    Runtime.card_fullscreen = nil
  end
  for position, candidate in ipairs(settings.detached_cards) do
    if candidate == entry then table.remove(settings.detached_cards, position) break end
  end
  settings.detached_by_index[index], settings.cards[index], snapshot.cards[index] = nil, nil, nil
  Runtime.detached.applied[entry.id] = nil
  Store.root.detached_cards = settings.detached_cards
  Store.mark_dirty()
  if Runtime.metering and Runtime.metering.visual then
    Runtime.metering.visual.compile_dirty = true
  end
  recompute_snapshot(true)
  return true
end

function Content.return_detached_now(index)
  local entry = settings.detached_by_index[index]
  if not entry then return false end
  local target_row, target_index
  for row = 1, settings.card_rows do
    for column = 1, settings.card_row_counts[row] or 0 do
      local candidate = row_card_index(row, column)
      if settings.cards[candidate] and settings.cards[candidate].type == "none" then
        target_row, target_index = row, candidate
        break
      end
    end
    if target_index then break end
  end
  if not target_index then
    for row = 1, settings.card_rows do
      if Content.row_can_add_card(row) then target_row = row break end
    end
  end
  if not target_index and target_row then
    local count = settings.card_row_counts[target_row]
    target_index = row_card_index(target_row, count + 1)
    settings.card_row_counts[target_row] = count + 1
    save_string("card_row" .. target_row .. "_count", count + 1)
  elseif not target_index and settings.card_rows < MAX_CARD_ROWS then
    if not Content.insert_row_at(settings.card_rows + 1) then return false end
    target_row = settings.card_rows
    target_index = row_card_index(target_row, 1)
  elseif not target_index then
    Content.set_detached_error("Add room to the face before returning this pop-out card.")
    return false
  end
  settings.cards[target_index] = Content.clone_card(entry.card)
  settings.cards[target_index].span = "auto"
  Content.save_card(target_index)
  edit_selected_row, edit_selected_card = target_row, target_index
  Content.remove_detached_now(index)
  Runtime.detached.error = nil
  request_layout_resize()
  recompute_snapshot(true)
  return true
end

function Content.move_card_to_detached_now(index)
  if not index or index < 1 or not settings.cards[index] then return false end
  local row, column = card_row_column(index)
  local detached_index = Content.create_detached(settings.cards[index], false)
  if not detached_index then return false end
  if Runtime.card_fullscreen and Runtime.card_fullscreen.index == index then
    Runtime.card_fullscreen = nil
  end
  Content.remove_card(row, column)
  return true
end

function Content.queue_detached_action(kind, index)
  Runtime.detached.pending = { kind = kind, index = tonumber(index) }
end

function Content.set_detached_error(message)
  Runtime.detached.error = tostring(message or "")
  Runtime.detached.error_started_at = R.time_precise()
end

function Content.process_detached_request()
  local request = Runtime.detached and Runtime.detached.pending
  if not request then return end
  Runtime.detached.pending = nil
  if request.kind == "new" then
    Content.create_detached(Content.new_card("position"), true)
  elseif request.kind == "move" then
    Content.move_card_to_detached_now(request.index)
  elseif request.kind == "return" then
    Content.return_detached_now(request.index)
  elseif request.kind == "remove" then
    Content.remove_detached_now(request.index)
  elseif request.kind == "close" then
    local entry = Content.detached_entry(request.index)
    if entry then entry.open = false Content.save_card(request.index) end
  elseif request.kind == "open" then
    local entry = Content.detached_entry(request.index)
    if entry then
      entry.open = true
      Runtime.detached.applied[entry.id] = nil
      Content.save_card(request.index)
    end
  end
  recompute_snapshot(true)
end

function Content.draw_detached_management_menu(id_prefix)
  if not R.ImGui_BeginMenu(ctx, "Pop-Out Cards") then return end
  if R.ImGui_MenuItem(ctx, "New Pop-Out Card…##" .. id_prefix .. "_new",
      nil, false, #settings.detached_cards < 32) then
    Content.queue_detached_action("new")
  end
  if #settings.detached_cards > 0 then R.ImGui_Separator(ctx) end
  for _, entry in ipairs(settings.detached_cards) do
    local index = -entry.id
    local label = Content.detached_label(entry)
    if R.ImGui_MenuItem(ctx,
        label .. "##" .. id_prefix .. "_card_" .. entry.id,
        nil, entry.open, true) then
      if entry.open then
        entry.focus_requested = true
      else
        Content.queue_detached_action("open", index)
      end
    end
  end
  R.ImGui_EndMenu(ctx)
end

function Content.swap_cards(source_index, target_index)
  if source_index == target_index or not settings.cards[source_index]
      or not settings.cards[target_index] then return end
  settings.cards[source_index], settings.cards[target_index] =
    settings.cards[target_index], settings.cards[source_index]
  Content.save_card(source_index)
  Content.save_card(target_index)
  recompute_snapshot(true)
end

row_card_index = function(row, column)
  return (row - 1) * CARDS_PER_ROW + column
end

card_row_column = function(index)
  local row = math.floor((index - 1) / CARDS_PER_ROW) + 1
  return row, (index - 1) % CARDS_PER_ROW + 1
end

function Content.row_required_units(row, excluded_index)
  local total = 0
  for column = 1, settings.card_row_counts[row] or 0 do
    local index = row_card_index(row, column)
    if index ~= excluded_index then
      total = total + (tonumber(settings.cards[index].span) or 1)
    end
  end
  return total
end

function Content.max_card_span(index)
  local row, column = card_row_column(index)
  if row < 1 or row > settings.card_rows
      or column > (settings.card_row_counts[row] or 0) then return 1 end
  return math.max(1, CARDS_PER_ROW - Content.row_required_units(row, index))
end

function Content.row_can_add_card(row)
  local count = settings.card_row_counts[row] or 0
  return count < CARDS_PER_ROW
    and Content.row_required_units(row) + 1 <= CARDS_PER_ROW
end

function Content.set_card_span(index, span)
  local card = settings.cards[index]
  if not card then return false end
  span = normalize_card_span(span)
  local fixed = tonumber(span)
  if fixed and fixed > Content.max_card_span(index) then return false end
  if card.span == span then return true end
  card.span = span
  Content.save_card(index)
  recompute_snapshot(true)
  return true
end

function Content.card_span_label(card, compact)
  local fixed = tonumber(card and card.span)
  if not fixed then return compact and "AUTO" or "Auto (share remaining)" end
  return compact and (fixed .. "/6") or (fixed .. " of 6")
end

function Content.ensure_edit_card_selection(row)
  row = math.max(1, math.min(settings.card_rows, row or edit_selected_row or 1))
  local selected_row, selected_column = card_row_column(edit_selected_card or 1)
  if selected_row ~= row or selected_column > settings.card_row_counts[row] then
    edit_selected_card = row_card_index(row, 1)
  end
  edit_selected_row = row
  return edit_selected_card
end

function Content.set_card_rows(rows)
  rows = math.max(0, math.min(MAX_CARD_ROWS, math.floor((tonumber(rows) or 0) + 0.5)))
  if rows == settings.card_rows then return end
  local previous_rows = settings.card_rows
  settings.card_rows = rows
  for row = previous_rows + 1, rows do
    local has_content = false
    for column = 1, settings.card_row_counts[row] do
      if settings.cards[row_card_index(row, column)].type ~= "none" then
        has_content = true
        break
      end
    end
    if not has_content then
      local index = row_card_index(row, 1)
      settings.card_row_counts[row] = 1
      settings.cards[index] = Content.new_card("position")
      save_string("card_row" .. row .. "_count", 1)
      Content.save_card(index)
    end
  end
  if rows > 0 then edit_selected_row = math.max(1, math.min(rows, edit_selected_row or 1)) end
  if rows > 0 then Content.ensure_edit_card_selection(edit_selected_row) end
  save_string("card_rows", rows)
  if Content.save_active_face then Content.save_active_face() end
  request_layout_resize()
  recompute_snapshot(true)
end

function Content.set_main_clock_size(size_id)
  if not Runtime.clock_sizes[size_id] or size_id == "order"
      or settings.main_clock_size == size_id then return end
  settings.main_clock_size = size_id
  save_string("main_clock_size", size_id)
  if Content.save_active_face then Content.save_active_face() end
  request_layout_resize()
  recompute_snapshot(true)
end

function Content.set_row_count(row, count)
  if row < 1 or row > settings.card_rows then return end
  count = math.max(1, math.min(CARDS_PER_ROW, math.floor((tonumber(count) or 1) + 0.5)))
  local previous = settings.card_row_counts[row]
  if previous == count then return end
  if count > previous then
    if Content.row_required_units(row) + (count - previous) > CARDS_PER_ROW then return end
    -- A reduced row keeps each hidden card's content so it can be restored,
    -- but an old fixed width may no longer fit beside widths edited while the
    -- card was hidden. Reactivated cards return to Auto and share the remaining
    -- six-unit grid without discarding their content.
    for column = previous + 1, count do
      local index = row_card_index(row, column)
      local card = settings.cards[index]
      if card.span ~= "auto" then
        card.span = "auto"
        save_string("card_" .. index .. "_span", card.span)
      end
    end
  end
  settings.card_row_counts[row] = count
  save_string("card_row" .. row .. "_count", count)
  Content.ensure_edit_card_selection(row)
  if Content.save_active_face then Content.save_active_face() end
  recompute_snapshot(true)
end

function Content.set_row_size(row, size_id)
  if row < 1 or row > settings.card_rows or not ROW_SIZE_OPTIONS[size_id] then return end
  if settings.card_row_sizes[row] == size_id then return end
  settings.card_row_sizes[row] = size_id
  save_string("card_row" .. row .. "_size", size_id)
  if Content.save_active_face then Content.save_active_face() end
  request_layout_resize()
end

function Content.move_row(source_row, target_row)
  source_row, target_row = tonumber(source_row), tonumber(target_row)
  if not source_row or not target_row or source_row == target_row
      or source_row < 1 or source_row > settings.card_rows
      or target_row < 1 or target_row > settings.card_rows then return end

  local rows = {}
  for row = 1, settings.card_rows do
    local data = {
      count = settings.card_row_counts[row],
      size = settings.card_row_sizes[row],
      cards = {},
    }
    for column = 1, CARDS_PER_ROW do
      data.cards[column] = Content.clone_card(settings.cards[row_card_index(row, column)])
    end
    rows[row] = data
  end
  local moving = table.remove(rows, source_row)
  table.insert(rows, target_row, moving)

  for row, data in ipairs(rows) do
    settings.card_row_counts[row], settings.card_row_sizes[row] = data.count, data.size
    save_string("card_row" .. row .. "_count", data.count)
    save_string("card_row" .. row .. "_size", data.size)
    for column = 1, CARDS_PER_ROW do
      local index = row_card_index(row, column)
      settings.cards[index] = Content.clone_card(data.cards[column])
      Content.save_card(index)
    end
  end
  edit_selected_row = target_row
  edit_selected_card = row_card_index(target_row, 1)
  if Content.save_active_face then Content.save_active_face() end
  request_layout_resize()
  recompute_snapshot(true)
end

function Content.remove_row(row)
  if row < 1 or row > settings.card_rows then return end
  for target_row = row, settings.card_rows - 1 do
    settings.card_row_counts[target_row] = settings.card_row_counts[target_row + 1]
    settings.card_row_sizes[target_row] = settings.card_row_sizes[target_row + 1]
    for column = 1, CARDS_PER_ROW do
      local target = row_card_index(target_row, column)
      local source = row_card_index(target_row + 1, column)
      settings.cards[target] = Content.clone_card(settings.cards[source])
      Content.save_card(target)
    end
  end
  local final_row = settings.card_rows
  settings.card_row_counts[final_row] = 1
  settings.card_row_sizes[final_row] = "medium"
  for column = 1, CARDS_PER_ROW do
    local index = row_card_index(final_row, column)
    settings.cards[index] = Content.new_card("none")
    Content.save_card(index)
  end
  save_string("card_row" .. final_row .. "_count", 1)
  save_string("card_row" .. final_row .. "_size", "medium")
  Content.set_card_rows(settings.card_rows - 1)
end

function Content.insert_row_at(target_row)
  if settings.card_rows >= MAX_CARD_ROWS then return false end
  Content.set_card_rows(settings.card_rows + 1)
  local new_row = settings.card_rows
  target_row = math.max(1, math.min(new_row, tonumber(target_row) or new_row))

  -- Shift existing rows downward from the bottom so insertion never revives
  -- dormant content from a previously hidden row or overwrites the row below.
  for row = new_row, target_row + 1, -1 do
    local source_row = row - 1
    settings.card_row_counts[row] = settings.card_row_counts[source_row]
    settings.card_row_sizes[row] = settings.card_row_sizes[source_row]
    save_string("card_row" .. row .. "_count", settings.card_row_counts[row])
    save_string("card_row" .. row .. "_size", settings.card_row_sizes[row])
    for column = 1, CARDS_PER_ROW do
      local target_index = row_card_index(row, column)
      local source_index = row_card_index(source_row, column)
      settings.cards[target_index] = Content.clone_card(settings.cards[source_index])
      Content.save_card(target_index)
    end
  end

  settings.card_row_counts[target_row] = 1
  settings.card_row_sizes[target_row] = "medium"
  save_string("card_row" .. target_row .. "_count", 1)
  save_string("card_row" .. target_row .. "_size", "medium")
  for column = 1, CARDS_PER_ROW do
    local index = row_card_index(target_row, column)
    settings.cards[index] = Content.new_card(column == 1 and "position" or "none")
    Content.save_card(index)
  end
  edit_selected_row = target_row
  edit_selected_card = row_card_index(target_row, 1)
  if Content.save_active_face then Content.save_active_face() end
  request_layout_resize()
  recompute_snapshot(true)
  return true
end

function Content.remove_card(row, column)
  local count = settings.card_row_counts[row]
  local first_index = row_card_index(row, 1)
  if column < 1 or column > count then return end
  if count == 1 then Content.remove_row(row) return end
  for position = column, count - 1 do
    settings.cards[first_index + position - 1] =
      Content.clone_card(settings.cards[first_index + position])
    Content.save_card(first_index + position - 1)
  end
  settings.cards[first_index + count - 1] = Content.new_card("none")
  Content.save_card(first_index + count - 1)
  Content.set_row_count(row, count - 1)
  edit_selected_card = row_card_index(row, math.min(column, count - 1))
end

function Content.apply_meter_preset(config, preset)
  if not config or type(preset) ~= "table" then return end
  if METER_CARD_FIELDS[1].values[preset.meter_display] then
    config.meter_display = preset.meter_display
  end
  if preset.meter_metric and METER_CARD_FIELDS[2].values[preset.meter_metric] then
    config.meter_metric = preset.meter_metric
  end
end

function Content.add_card(row, card_type, open_editor, meter_preset)
  local count = settings.card_row_counts[row]
  if not count or not Content.row_can_add_card(row) or not CARD_TYPE_BY_ID[card_type]
      or card_type == "none" then return end
  local index = row_card_index(row, count + 1)
  settings.cards[index] = Content.new_card(card_type)
  if card_type == "meter" then Content.apply_meter_preset(settings.cards[index], meter_preset) end
  settings.card_row_counts[row] = count + 1
  save_string("card_row" .. row .. "_count", settings.card_row_counts[row])
  Content.save_card(index)
  edit_selected_row, edit_selected_card = row, index
  recompute_snapshot(true)
  if card_type == "meter" then
    Metering.request_source_setup(index)
  elseif open_editor then
    Content.open_detail_editor("card", index)
  end
end

function Content.set_card_type(index, card_type, open_editor, meter_preset)
  local card = settings.cards[index]
  if not card or not CARD_TYPE_BY_ID[card_type] then return end
  local prior_type = card.type
  card.type = card_type
  if card_type == "meter" then Content.apply_meter_preset(card, meter_preset) end
  if card_type == "action" and prior_type ~= "action" then
    card.show_title = false
    card.align = "center"
  end
  Content.save_card(index)
  if Content.save_active_face then Content.save_active_face() end
  recompute_snapshot(true)
  if card_type == "meter" and not open_editor
      and (prior_type ~= "meter" or not Metering.resolve_binding(card)) then
    Metering.request_source_setup(index)
  elseif open_editor then
    Content.open_detail_editor("card", index)
  end
end

function Metering.draw_numeric_card_type_menu(id_prefix, selected_type, current_config, select_content)
  local function choose_numeric(label, metric)
    local selected = selected_type == "meter" and current_config
      and current_config.meter_display == "numeric"
      and current_config.meter_metric == metric
    if R.ImGui_MenuItem(ctx, label .. "##" .. id_prefix .. "meter_numeric_" .. metric,
        nil, selected == true, true) then
      select_content("meter", false, { meter_display = "numeric", meter_metric = metric })
    end
  end

  for _, group in ipairs(Metering.numeric_menus) do
    if R.ImGui_BeginMenu(ctx, group.label) then
      for _, option in ipairs(group.items) do choose_numeric(option[1], option[2]) end
      R.ImGui_EndMenu(ctx)
    end
  end
end

function Metering.draw_visual_card_type_menu(id_prefix, selected_type, current_config, select_content)
  for _, option in ipairs(Metering.visual_menus) do
    local display = option[2]
    local selected = selected_type == "meter" and current_config
      and current_config.meter_display == display
    if R.ImGui_MenuItem(ctx, option[1] .. "##" .. id_prefix .. "meter_visual_" .. display,
        nil, selected == true, true) then
      select_content("meter", false, { meter_display = display })
    end
  end
end

function Content.draw_type_menu_items(id_prefix, selected_type, include_none,
    allow_visual_click, select_content, current_config)
  local function draw_option(option)
    if (include_none or option.id ~= "none")
        and (allow_visual_click or option.id ~= "visual_click") then
      local selected = selected_type == option.id
      if R.ImGui_MenuItem(ctx, option.label .. "##" .. id_prefix .. option.id,
          nil, selected, true) then
        select_content(option.id, option.id == "custom" or option.id == "action")
      end
    end
  end

  if include_none then
    draw_option(CARD_TYPE_BY_ID.none)
    R.ImGui_Separator(ctx)
  end
  for _, option_id in ipairs(Content.common_type_ids) do
    draw_option(CARD_TYPE_BY_ID[option_id])
  end
  R.ImGui_Separator(ctx)
  for _, group in ipairs(CARD_GROUPS) do
    if R.ImGui_BeginMenu(ctx, group.label) then
      if group.id == "metering" then
        Metering.draw_numeric_card_type_menu(
          id_prefix, selected_type, current_config, select_content)
      elseif group.id == "visualizations" then
        Metering.draw_visual_card_type_menu(
          id_prefix, selected_type, current_config, select_content)
      elseif group.sections then
        for _, section in ipairs(group.sections) do
          if R.ImGui_BeginMenu(ctx, section.label) then
            for _, option in ipairs(CARD_TYPE_OPTIONS) do
              if option.group == group.id and option.section == section.id then
                draw_option(option)
              end
            end
            R.ImGui_EndMenu(ctx)
          end
        end
      else
        for _, option in ipairs(CARD_TYPE_OPTIONS) do
          if option.group == group.id then draw_option(option) end
        end
      end
      R.ImGui_EndMenu(ctx)
    end
  end
  R.ImGui_Separator(ctx)
  draw_option(CARD_TYPE_BY_ID.action)
  draw_option(CARD_TYPE_BY_ID.custom)
end

local function push_popup_style()
  local palette = Content.settings_surface_palette()
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_PopupBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.ink)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Header(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_HeaderHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_HeaderActive(), C.toggle_selected)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), palette.subtle_border)
  Content.push_focus_color()
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 10, 8)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 7, 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), 8, 4)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5)
end

local function pop_popup_style()
  R.ImGui_PopStyleVar(ctx, 6)
  local focus_colors = (type(R.ImGui_Col_NavCursor) == "function"
    or type(R.ImGui_Col_NavHighlight) == "function") and 1 or 0
  R.ImGui_PopStyleColor(ctx, 6 + focus_colors)
end

-- Keep authored popups inside the current monitor work area. The content
-- chooser is also structurally bounded: every root and leaf submenu has a
-- short, deliberate list, so platform menu scrolling is only a safety net.
function Content.constrain_next_popup_height()
  local max_height
  if type(R.ImGui_GetWindowViewport) == "function"
      and type(R.ImGui_Viewport_GetWorkSize) == "function" then
    local viewport = R.ImGui_GetWindowViewport(ctx)
    if viewport then
      local _, work_height = R.ImGui_Viewport_GetWorkSize(viewport)
      if finite_number(work_height) then max_height = work_height - 16 end
    end
  end
  if not max_height then
    local owner_x, owner_y = R.ImGui_GetWindowPos(ctx)
    local owner_w, owner_h = R.ImGui_GetWindowSize(ctx)
    local bounds = window_work_area(owner_x, owner_y, owner_w, owner_h)
    if bounds then max_height = bounds.bottom - bounds.top - 16 end
  end
  if max_height and max_height >= 140 then
    R.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, 100000, max_height)
  end
end

function Content.push_focus_color()
  local api = type(R.ImGui_Col_NavCursor) == "function" and R.ImGui_Col_NavCursor
    or type(R.ImGui_Col_NavHighlight) == "function" and R.ImGui_Col_NavHighlight
  if type(api) ~= "function" then return 0 end
  R.ImGui_PushStyleColor(ctx, api(), C.accent)
  return 1
end

function Content.draw_popup_heading(text)
  R.ImGui_PushFont(ctx, font_bold, 10)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), Content.settings_surface_palette().label)
  R.ImGui_Text(ctx, text)
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
end

local function card_alignment_options()
  local options = {}
  for _, alignment_id in ipairs({ "left", "center", "right" }) do
    local label = alignment_id:gsub("^%l", string.upper)
    if alignment_id == settings.card_alignment then
      options[#options + 1] = { id = "default", effective = alignment_id,
        label = label .. " (Default)" }
    else
      options[#options + 1] = { id = alignment_id, effective = alignment_id, label = label }
    end
  end
  return options
end

function Content.draw_card_span_menu_items(card_index, id_prefix)
  local card = settings.cards[card_index]
  if not card then return end
  local current, maximum = card.span or "auto", Content.max_card_span(card_index)
  if R.ImGui_MenuItem(ctx, "Auto - share remaining##" .. id_prefix .. "auto",
      nil, current == "auto", true) then Content.set_card_span(card_index, "auto") end
  R.ImGui_Separator(ctx)
  for units = 1, CARDS_PER_ROW do
    local id, enabled = tostring(units), units <= maximum
    if R.ImGui_MenuItem(ctx, units .. " of 6##" .. id_prefix .. id,
        nil, current == id, enabled) and enabled then
      Content.set_card_span(card_index, id)
    end
    if not enabled then
      item_tooltip("Width unavailable",
        "The other cards in this row need at least one unit each. Reduce another fixed width first.")
    end
  end
end

function Content.draw_row_size_menu_items(row, id_prefix)
  if not row or row < 1 or row > settings.card_rows then return end
  local current_size = settings.card_row_sizes[row]
  for _, option_id in ipairs(ROW_SIZE_ORDER) do
    if R.ImGui_MenuItem(ctx, ROW_SIZE_OPTIONS[option_id].label .. "##"
        .. id_prefix .. option_id, nil, current_size == option_id, true) then
      Content.set_row_size(row, option_id)
    end
  end
end

function Content.draw_context_popup(scale, popup_id, heading, config,
    select_content, allow_visual_click, card_index, scrollable)
  local menu_id = popup_id
  push_popup_style()
  Content.constrain_next_popup_height()
  if R.ImGui_BeginPopup(ctx, popup_id) then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading(heading)
    R.ImGui_Separator(ctx)
    local detached = card_index and card_index < 0
    local row = card_index and card_index > 0
      and math.floor((card_index - 1) / CARDS_PER_ROW) + 1 or nil
    if R.ImGui_BeginMenu(ctx, "Change Content") then
      Content.draw_type_menu_items("content_" .. menu_id, config.type, true,
        allow_visual_click ~= false, select_content, config)
      R.ImGui_EndMenu(ctx)
    end
    if card_index and R.ImGui_MenuItem(ctx,
        "Show card title##content_title_" .. menu_id,
        nil, config.show_title ~= false, true) then
      config.show_title = config.show_title == false
      Content.save_card(card_index)
      recompute_snapshot(true)
    end
    if scrollable and R.ImGui_MenuItem(ctx,
        "Auto-scroll long text##content_scroll_" .. menu_id,
        nil, config.scroll == true, true) then
      config.scroll = not config.scroll
      Content.save_card(card_index)
      recompute_snapshot(true)
    end
    if R.ImGui_BeginMenu(ctx, "Alignment") then
      local current = config.align or "default"
      for _, option in ipairs(card_alignment_options()) do
        local selected = current == option.id
          or option.id == "default" and current == option.effective
        if R.ImGui_MenuItem(ctx, option.label .. "##content_align_" .. menu_id .. option.id,
            nil, selected, true) then
          config.align = option.id
          if card_index then Content.save_card(card_index) end
        end
      end
      R.ImGui_EndMenu(ctx)
    end
    if card_index and row then
      local row_size = ROW_SIZE_OPTIONS[settings.card_row_sizes[row]] or ROW_SIZE_OPTIONS.medium
      if R.ImGui_BeginMenu(ctx, "Row Height · " .. row_size.label) then
        Content.draw_row_size_menu_items(row, "content_row_size_" .. menu_id)
        R.ImGui_EndMenu(ctx)
      end
      if R.ImGui_BeginMenu(ctx,
          "Card Width · " .. Content.card_span_label(config, true)) then
        Content.draw_card_span_menu_items(card_index, "content_span_" .. menu_id)
        R.ImGui_EndMenu(ctx)
      end
      if R.ImGui_BeginMenu(ctx, "Row") then
        if R.ImGui_MenuItem(ctx, "Add New Row Above##content_add_row_above_" .. menu_id,
            nil, false, settings.card_rows < MAX_CARD_ROWS) then
          Content.insert_row_at(row)
        end
        if R.ImGui_MenuItem(ctx, "Add New Row Below##content_add_row_below_" .. menu_id,
            nil, false, settings.card_rows < MAX_CARD_ROWS) then
          Content.insert_row_at(row + 1)
        end
        R.ImGui_Separator(ctx)
        if R.ImGui_MenuItem(ctx, "Remove Row##content_remove_row_" .. menu_id,
            nil, false, settings.card_rows > 0) then
          Content.remove_row(row)
        end
        R.ImGui_EndMenu(ctx)
      end
    end
    if card_index and config.type == "meter" then
      if R.ImGui_BeginMenu(ctx, "Meter Actions") then
        local meter_card = snapshot.cards[card_index]
        local source = Metering.resolve_binding(config)
        local runtime = source and source.runtime
        if R.ImGui_MenuItem(ctx, source
            and "Change Meter Source…##content_source_setup_" .. menu_id
            or "Choose Meter Source…##content_source_setup_" .. menu_id) then
          Metering.request_source_setup(card_index)
        end
        R.ImGui_Separator(ctx)
        local reset_enabled = meter_card and meter_card.resettable == true
          and source and source.compatible and Metering.command_valid(source)
          and runtime.pending_reset == nil
        if not reset_enabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
        if R.ImGui_MenuItem(ctx, runtime and runtime.pending_reset ~= nil
            and "Reset Pending…##content_reset_" .. menu_id
            or "Reset Meter##content_reset_" .. menu_id) and reset_enabled then
          local okay, detail = Metering.request_reset(source, "context_menu")
          Runtime.metering.operation_error = not okay and detail or nil
        end
        if not reset_enabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
        item_tooltip("Reset this meter",
          "Restarts integrated loudness, RMS, LRA, all maxima, and histories for every card using this source.")
        R.ImGui_EndMenu(ctx)
      end
    end
    R.ImGui_Separator(ctx)
    local resolved = card_index and snapshot.cards[card_index]
    if resolved and resolved.visualization
        and R.ImGui_MenuItem(ctx, "Fullscreen Visualization##content_fullscreen_" .. menu_id) then
      Content.toggle_card_fullscreen(card_index)
    end
    if card_index and R.ImGui_BeginMenu(ctx, "Pop-Out") then
      if detached then
        if R.ImGui_MenuItem(ctx, "Return to Face##content_return_" .. menu_id) then
          Content.queue_detached_action("return", card_index)
        end
        if R.ImGui_MenuItem(ctx, "Close Pop-Out##content_close_" .. menu_id) then
          Content.queue_detached_action("close", card_index)
        end
        if R.ImGui_MenuItem(ctx, "Remove Pop-Out…##content_remove_popout_" .. menu_id) then
          Content.queue_detached_action("remove", card_index)
        end
        R.ImGui_Separator(ctx)
      else
        local can_detach = #settings.detached_cards < 32
        if R.ImGui_MenuItem(ctx, "Move to Pop-Out##content_detach_" .. menu_id,
            nil, false, can_detach) then
          Content.queue_detached_action("move", card_index)
        end
        if not can_detach then
          item_tooltip("Pop-out limit reached",
            "ReaClock supports up to 32 independent pop-out cards.")
        end
      end
      if R.ImGui_MenuItem(ctx, "New Pop-Out Card…##content_new_popout_" .. menu_id,
          nil, false, #settings.detached_cards < 32) then
        Content.queue_detached_action("new")
      end
      R.ImGui_EndMenu(ctx)
    end
    R.ImGui_Separator(ctx)
    if R.ImGui_MenuItem(ctx, "Customize details…##content_settings_" .. menu_id) then
      select_content(config.type, true)
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.open_context_popup_for_item(popup_id)
  local right_button = R.ImGui_MouseButton_Right and R.ImGui_MouseButton_Right() or 1
  if R.ImGui_IsItemClicked and R.ImGui_IsItemClicked(ctx, right_button) then
    Content.context_click_claimed = true
    R.ImGui_OpenPopup(ctx, popup_id)
  end
end

function Content.mouse_screen_position()
  if type(R.GetMousePosition) == "function" then
    local mouse_x, mouse_y = R.GetMousePosition()
    if finite_number(mouse_x) and finite_number(mouse_y) then return mouse_x, mouse_y end
  end
  return R.ImGui_GetMousePos(ctx)
end

function Content.draw_context_menu(draw_list, scale, x, y, w, h, menu_id,
    heading, tooltip_detail, config, select_content, allow_visual_click, card_index, scrollable,
    interaction_exclusion)
  local popup_id = "content_menu_" .. menu_id
  local hovered, left_clicked, double_clicked = false, false, false
  local function draw_hit_region(suffix, region_x, region_y, region_w, region_h)
    if region_w <= 0 or region_h <= 0 then return end
    R.ImGui_SetCursorScreenPos(ctx, region_x, region_y)
    R.ImGui_InvisibleButton(ctx, "##content_hit_" .. menu_id .. suffix,
      region_w, region_h)
    local region_hovered = R.ImGui_IsItemHovered and R.ImGui_IsItemHovered(ctx)
    hovered = hovered or region_hovered
    left_clicked = left_clicked or (card_index and region_hovered
      and R.ImGui_IsMouseClicked(ctx, R.ImGui_MouseButton_Left(), false))
    double_clicked = double_clicked or (card_index and region_hovered
      and R.ImGui_IsMouseDoubleClicked(ctx, R.ImGui_MouseButton_Left()))
    Content.open_context_popup_for_item(popup_id)
  end

  if interaction_exclusion then
    local ex_x = math.max(x, math.min(x + w, interaction_exclusion.x))
    local ex_y = math.max(y, math.min(y + h, interaction_exclusion.y))
    local ex_right = math.max(ex_x, math.min(x + w,
      interaction_exclusion.x + interaction_exclusion.w))
    local ex_bottom = math.max(ex_y, math.min(y + h,
      interaction_exclusion.y + interaction_exclusion.h))
    draw_hit_region("_left", x, y, ex_x - x, h)
    draw_hit_region("_right", ex_right, y, x + w - ex_right, h)
    draw_hit_region("_above", ex_x, y, ex_right - ex_x, ex_y - y)
    draw_hit_region("_below", ex_x, ex_bottom, ex_right - ex_x, y + h - ex_bottom)
  else
    draw_hit_region("", x, y, w, h)
  end

  local mouse_x, mouse_y = Content.mouse_screen_position()
  local exclusion_hovered = interaction_exclusion
    and mouse_x >= interaction_exclusion.x
    and mouse_x <= interaction_exclusion.x + interaction_exclusion.w
    and mouse_y >= interaction_exclusion.y
    and mouse_y <= interaction_exclusion.y + interaction_exclusion.h
  local card_hovered = hovered or exclusion_hovered == true
  if card_hovered and not Runtime.card_fullscreen_rendering then
    R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h,
      with_alpha(C.accent, 125), 8 * scale, 0, math.max(1, scale))
  end
  if hovered and not Runtime.card_fullscreen_rendering then
    local reset_hint = card_index and snapshot.cards[card_index]
      and snapshot.cards[card_index].resettable and not presentation_mode
    local setup_hint = card_index and snapshot.cards[card_index]
      and snapshot.cards[card_index].setup_required and not presentation_mode
    local action_hint = card_index and snapshot.cards[card_index]
      and snapshot.cards[card_index].action_button
    draw_styled_tooltip(action_hint
      and "Click the button to run · Double-click to customize · Right-click for options"
      or setup_hint
      and (config.type == "custom"
        and "Click to configure its meter source in Card Details · Double-click to customize · Right-click for options"
        or "Click to choose a meter source · Double-click to customize · Right-click for options")
      or reset_hint and "Click to reset · Double-click to customize · Right-click for options"
      or card_index and "Double-click to customize · Right-click for options"
      or "Right-click for options", tooltip_detail)
  end
  Content.draw_context_popup(scale, popup_id, heading, config,
    select_content, allow_visual_click, card_index, scrollable)
  return hovered, left_clicked, double_clicked, card_hovered
end

function Content.card_tooltip_detail(card_index, include_move_hint)
  local config = settings.cards[card_index]
  local option = CARD_TYPE_BY_ID[config.type]
  if card_index < 0 then
    local detail = (option and option.label or "Unknown content") .. ": "
      .. (CARD_TYPE_DESCRIPTIONS[config.type]
        or "Shows the currently configured card content.")
      .. " This is an independent pop-out card; resize or position its window directly."
    if include_move_hint then detail = detail .. " Use Return to Face to place it back in the layout." end
    return detail
  end
  local row = math.floor((card_index - 1) / CARDS_PER_ROW) + 1
  local row_size = ROW_SIZE_OPTIONS[settings.card_row_sizes[row]] or ROW_SIZE_OPTIONS.medium
  local detail = (option and option.label or "Unknown content") .. ": "
    .. (CARD_TYPE_DESCRIPTIONS[config.type] or "Shows the currently configured card content.")
    .. " Width: " .. Content.card_span_label(config, false) .. "."
    .. " Row size: " .. row_size.label .. "."
  if include_move_hint then detail = detail .. " Drag the lower-right grip to move it." end
  local card = snapshot.cards[card_index]
  if card and card.resettable then
    detail = detail .. " A single left click resets this meter and every card using the same source."
  elseif card and card.setup_required then
    detail = detail .. (config.type == "custom"
      and " Click the card to configure its meter source in Card Details."
      or " Click the card to choose what ReaClock should meter.")
  elseif card and card.action_button then
    detail = detail .. (card.action_available
      and (" Click the inset button once to run it. Double-clicking opens Card Details without running it."
        .. (card.action_toggle
          and (card.action_toggled and " This toggle is currently on."
            or " This toggle is currently off.") or ""))
      or " Choose a valid Main-section action in Card Details before using it.")
  end
  return detail
end

function Content.draw_meter_reset_icon(draw_list, scale, x, y, w, hovered)
  local color = with_alpha(hovered and C.accent_secondary or C.muted,
    hovered and 235 or 185)
  if draw_icon_centered(draw_list, ICON.ROTATE_CCW,
      x + w - 23 * scale, y + 6 * scale, 16 * scale, 16 * scale,
      math.max(6, 14 * scale), color, scale) then
    return
  end
  local cx, cy, radius = x + w - 15 * scale, y + 14 * scale, 6 * scale
  local thickness = math.max(1.2, 1.35 * scale)
  local function arc(first, last)
    local prior_x, prior_y
    for step = 0, 5 do
      local angle = first + (last - first) * step / 5
      local px, py = cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
      if prior_x then
        R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py, color, thickness)
      end
      prior_x, prior_y = px, py
    end
    return prior_x, prior_y, last
  end
  local ax, ay, angle = arc(-2.75, 0.15)
  local arrow = 3.1 * scale
  R.ImGui_DrawList_AddLine(draw_list, ax, ay,
    ax - math.cos(angle - 0.75) * arrow, ay - math.sin(angle - 0.75) * arrow,
    color, thickness)
  R.ImGui_DrawList_AddLine(draw_list, ax, ay,
    ax - math.cos(angle + 0.75) * arrow, ay - math.sin(angle + 0.75) * arrow,
    color, thickness)
  ax, ay, angle = arc(0.4, 3.3)
  R.ImGui_DrawList_AddLine(draw_list, ax, ay,
    ax - math.cos(angle - 0.75) * arrow, ay - math.sin(angle - 0.75) * arrow,
    color, thickness)
  R.ImGui_DrawList_AddLine(draw_list, ax, ay,
    ax - math.cos(angle + 0.75) * arrow, ay - math.sin(angle + 0.75) * arrow,
    color, thickness)
end

function Content.draw_meter_setup_icon(draw_list, scale, x, y, w, hovered)
  local color = with_alpha(hovered and C.accent_secondary or C.muted,
    hovered and 235 or 185)
  if draw_icon_centered(draw_list, ICON.CIRCLE_PLUS,
      x + w - 23 * scale, y + 6 * scale, 16 * scale, 16 * scale,
      math.max(6, 14 * scale), color, scale) then
    return
  end
  local cx, cy, radius = x + w - 15 * scale, y + 14 * scale, 6 * scale
  local thickness = math.max(1.2, 1.35 * scale)
  R.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, color, 16, thickness)
  R.ImGui_DrawList_AddLine(draw_list, cx - 3 * scale, cy, cx + 3 * scale, cy,
    color, thickness)
  R.ImGui_DrawList_AddLine(draw_list, cx, cy - 3 * scale, cx, cy + 3 * scale,
    color, thickness)
end

function Content.action_button_rect(config, scale, x, y, w, h)
  local show_title = config.show_title ~= false
  local top = show_title and 23 or 8
  return x + 10 * scale, y + top * scale,
    w - 20 * scale, h - (top + 8) * scale
end

function Content.card_focus_prior(card_index)
  if card_index and card_index < 0 then
    return Runtime.detached and Runtime.detached.render_focus_prior == true
  end
  return Runtime.metering.main_focused_prior == true
end

function Content.toggle_card_fullscreen(card_index)
  local active = Runtime.card_fullscreen
  if active and active.index == card_index then
    Runtime.card_fullscreen = nil
  elseif settings.cards[card_index] and snapshot.cards[card_index]
      and snapshot.cards[card_index].visualization then
    Runtime.card_fullscreen = { index = card_index, opened_at = R.time_precise() }
  end
end

function Content.visualization_fullscreen_bounds(scale, x, y, w, has_secondary_control)
  local size = math.max(18, math.min(28, 22 * scale))
  local right_inset = (has_secondary_control and 30 or 7) * scale
  return {
    x = x + w - size - right_inset,
    y = y + 5 * scale,
    w = size,
    h = size,
    secondary_left = has_secondary_control and x + w - 23 * scale or nil,
  }
end

function Content.export_test_visualization_fullscreen_bounds(card_index, bounds)
  if not Store.test_override or Runtime.card_fullscreen_rendering then return end
  local root = os.getenv("CIVIL_CLOCK_TEST_ROOT") or ""
  if root == "" then return end
  local slot = card_index < 0 and "popout" or "face"
  local gap = bounds.secondary_left and bounds.secondary_left - bounds.x - bounds.w or -1
  local value = string.format(
    "index=%d\nx=%.3f\ny=%.3f\nw=%.3f\nh=%.3f\nsecondary_left=%.3f\ngap=%.3f\n",
    card_index, bounds.x, bounds.y, bounds.w, bounds.h,
    bounds.secondary_left or -1, gap)
  Content.test_visualization_fullscreen_bounds =
    Content.test_visualization_fullscreen_bounds or {}
  if Content.test_visualization_fullscreen_bounds[slot] == value then return end
  local file = io.open(root .. "\\visualization-fullscreen-" .. slot .. ".txt", "wb")
  if file then
    file:write(value)
    file:close()
    Content.test_visualization_fullscreen_bounds[slot] = value
  end
end

function Content.draw_visualization_fullscreen_glyph(draw_list, bounds, active, color)
  local cx, cy = bounds.x + bounds.w * 0.5, bounds.y + bounds.h * 0.5
  local unit = math.max(0.8, math.min(1.35, bounds.w / 22))
  local outer, arm = 5.5 * unit, 3.6 * unit
  local thickness = math.max(1.1, 1.35 * unit)
  local function line(x1, y1, x2, y2)
    R.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, color, thickness)
  end
  if active then
    local inner = 1.4 * unit
    line(cx - inner, cy - inner, cx - inner - arm, cy - inner)
    line(cx - inner, cy - inner, cx - inner, cy - inner - arm)
    line(cx + inner, cy - inner, cx + inner + arm, cy - inner)
    line(cx + inner, cy - inner, cx + inner, cy - inner - arm)
    line(cx - inner, cy + inner, cx - inner - arm, cy + inner)
    line(cx - inner, cy + inner, cx - inner, cy + inner + arm)
    line(cx + inner, cy + inner, cx + inner + arm, cy + inner)
    line(cx + inner, cy + inner, cx + inner, cy + inner + arm)
  else
    line(cx - outer, cy - outer, cx - outer + arm, cy - outer)
    line(cx - outer, cy - outer, cx - outer, cy - outer + arm)
    line(cx + outer, cy - outer, cx + outer - arm, cy - outer)
    line(cx + outer, cy - outer, cx + outer, cy - outer + arm)
    line(cx - outer, cy + outer, cx - outer + arm, cy + outer)
    line(cx - outer, cy + outer, cx - outer, cy + outer - arm)
    line(cx + outer, cy + outer, cx + outer - arm, cy + outer)
    line(cx + outer, cy + outer, cx + outer, cy + outer - arm)
  end
end

function Content.draw_visualization_fullscreen_button(draw_list, scale, card_index,
    card_hovered, bounds)
  Content.visualization_fullscreen_fade = Content.visualization_fullscreen_fade or {}
  local now = R.time_precise()
  local mouse_x, mouse_y = Content.mouse_screen_position()
  local button_hovered = mouse_x >= bounds.x and mouse_x <= bounds.x + bounds.w
    and mouse_y >= bounds.y and mouse_y <= bounds.y + bounds.h
  -- The fullscreen hit area is intentionally excluded from the card's context
  -- hit regions. Count it directly as card hover so approaching the hidden
  -- control from outside the card always starts the reveal animation.
  card_hovered = card_hovered or button_hovered
  local fade = Content.visualization_fullscreen_fade[card_index]
  if not fade then
    fade = {
      alpha = 0,
      updated_at = now,
      hover_started = card_hovered and now or nil,
      last_hovered_at = card_hovered and now or nil,
    }
    Content.visualization_fullscreen_fade[card_index] = fade
  end
  if card_hovered then
    fade.hover_started = fade.hover_started or now
    fade.last_hovered_at = now
  elseif not fade.last_hovered_at or now - fade.last_hovered_at > 0.07 then
    fade.hover_started = nil
  end
  local hover_latched = card_hovered or fade.last_hovered_at
    and now - fade.last_hovered_at <= 0.07
  local hover_ready = hover_latched and fade.hover_started
    and now - fade.hover_started >= 0.09
  local target = hover_ready and 1 or 0
  local elapsed = math.max(0, math.min(0.1, now - fade.updated_at))
  local speed = target > fade.alpha and 16 or 10
  fade.alpha = fade.alpha + (target - fade.alpha) * math.min(1, elapsed * speed)
  if target == 0 and fade.alpha < 0.01 then fade.alpha = 0 end
  fade.updated_at = now
  if fade.alpha <= 0 and not card_hovered then return end

  local active = Runtime.card_fullscreen and Runtime.card_fullscreen.index == card_index
  local hovered = button_hovered
  if hovered or active then
    local fill = active and C.toggle_selected or C.inactive_hover
    local fill_alpha = math.floor((fill & 0xFF) * fade.alpha * (active and 0.78 or 0.62))
    R.ImGui_DrawList_AddRectFilled(draw_list,
      bounds.x, bounds.y, bounds.x + bounds.w, bounds.y + bounds.h,
      with_alpha(fill, fill_alpha), 5 * math.max(0.75, scale))
  end
  local icon = active and C.toggle_text or hovered and C.accent_secondary or C.secondary
  icon = with_alpha(icon, math.floor((icon & 0xFF) * fade.alpha * 0.92))
  Content.draw_visualization_fullscreen_glyph(draw_list, bounds, active, icon)

  R.ImGui_SetCursorScreenPos(ctx, bounds.x, bounds.y)
  local clicked = R.ImGui_InvisibleButton(ctx,
    "##card_fullscreen_" .. tostring(card_index), bounds.w, bounds.h)
  clicked = clicked or hovered
    and R.ImGui_IsMouseClicked(ctx, R.ImGui_MouseButton_Left(), false)
  if clicked then Content.toggle_card_fullscreen(card_index) end
  if hovered then
    draw_styled_tooltip(active and "Exit fullscreen" or "Fullscreen visualization",
      "Temporarily fills the current monitor with this live visualization. The card remains one configuration, not a duplicate.")
  end
end

function Content.draw_action_button_surface(draw_list, scale, x, y, w, h,
    card_index, card, config, row_style)
  local bx, by, bw, bh = Content.action_button_rect(config, scale, x, y, w, h)
  local mouse_x, mouse_y = R.ImGui_GetMousePos(ctx)
  local hovered = mouse_x >= bx and mouse_x <= bx + bw
    and mouse_y >= by and mouse_y <= by + bh
  if presentation_mode and hovered then Content.presentation_action_hovered = true end
  local available = card.action_available == true
  local feedback = Content.actions.feedback[card_index]
  local recently_fired = feedback and not feedback.error
    and R.time_precise() - (feedback.at or 0) < 0.28
  local palette = Content.settings_surface_palette()
  local toggle_state
  if available then toggle_state = Content.actions.toggle_state(card.action_command) end
  local toggled_on = toggle_state == true
  local fill
  if not available then
    fill = with_alpha(C.muted, 24)
  elseif toggled_on then
    fill = recently_fired and C.toggle_selected_active
      or hovered and C.toggle_selected_hover or C.toggle_selected
  elseif toggle_state ~= nil then
    fill = recently_fired and C.inactive_active
      or hovered and C.inactive_hover or palette.control
  else
    fill = recently_fired and C.toggle_selected_active
      or hovered and C.inactive_hover or palette.control
  end
  local border = toggled_on and with_alpha(C.accent, hovered and 245 or 210)
    or available and with_alpha(C.accent, hovered and 215 or 145)
    or with_alpha(C.muted, 90)
  R.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, fill, 6 * scale)
  R.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh,
    border, 6 * scale, 0, math.max(1, scale))

  if config.show_title ~= false then
    draw_text_box(draw_list, font_bold, card.label, x + 14 * scale, y + 5 * scale,
      w - 28 * scale, 16 * scale, row_style.label_size * scale * settings.regular_size,
      C.muted, 0.5, "ellipsis")
  end
  local alignment_id = config.align == "default" and settings.card_alignment
    or (config.align or "center")
  local alignment = alignment_id == "left" and 0
    or alignment_id == "right" and 1 or 0.5
  local font_size = math.min(row_style.value_size * 0.62,
    math.max(10, (bh / scale - 8) * 0.58)) * scale * settings.regular_size
  draw_text_box(draw_list, font_bold, card.value, bx + 10 * scale, by + 3 * scale,
    bw - 20 * scale, bh - 6 * scale, font_size,
    toggled_on and C.toggle_text or available and C.secondary or C.muted,
    alignment, "shrink", card.value)
end

function Content.draw_card_menu(draw_list, scale, x, y, w, h, card_index,
    interaction_exclusion)
  local detached = card_index < 0 and Content.detached_entry(card_index) or nil
  local row = not detached and math.floor((card_index - 1) / CARDS_PER_ROW) + 1 or nil
  local column = not detached and (card_index - 1) % CARDS_PER_ROW + 1 or nil
  local card = snapshot.cards[card_index]
  local config = settings.cards[card_index]
  local hovered, left_clicked, double_clicked, card_hovered = Content.draw_context_menu(
    draw_list, scale, x, y, w, h,
    "card_" .. card_index,
    detached and "POP-OUT CARD" or ("ROW " .. row .. " · CARD " .. column),
    Content.card_tooltip_detail(card_index), config,
    function(content_type, open_editor, meter_preset)
      Content.set_card_type(card_index, content_type, open_editor, meter_preset)
    end, true, card_index, card.fit_mode == "ellipsis" or card.fit_mode == "scroll",
    interaction_exclusion)
  if double_clicked and not Runtime.card_fullscreen_rendering then
    Content.open_card_detail_from_double_click(card_index)
  end
  local primary_activated = left_clicked and not double_clicked
  if card.action_button then
    if primary_activated and card.action_available then
      local button = R.ImGui_MouseButton_Left()
      local drag_x, drag_y = R.ImGui_GetMouseDragDelta(ctx, nil, nil, button, 0.0)
      local moved = math.sqrt((tonumber(drag_x) or 0) ^ 2 + (tonumber(drag_y) or 0) ^ 2)
      local bx, by, bw, bh = Content.action_button_rect(config, scale, x, y, w, h)
      local mouse_x, mouse_y = R.ImGui_GetMousePos(ctx)
      local clicked_button = mouse_x >= bx and mouse_x <= bx + bw
        and mouse_y >= by and mouse_y <= by + bh
      if Content.card_focus_prior(card_index) and clicked_button
          and moved <= math.max(4, 4 * scale) then
        Content.queue_card_primary_action({
          kind = "reaper_action", card_index = card_index,
        })
      end
    end
  elseif card.setup_required and not presentation_mode then
    Content.draw_meter_setup_icon(draw_list, scale, x, y, w, hovered)
    if primary_activated then
      local button = R.ImGui_MouseButton_Left()
      local drag_x, drag_y = R.ImGui_GetMouseDragDelta(ctx, nil, nil, button, 0.0)
      local moved = math.sqrt((tonumber(drag_x) or 0) ^ 2 + (tonumber(drag_y) or 0) ^ 2)
      if moved <= math.max(4, 4 * scale) then
        Content.queue_card_primary_action({ kind = "setup", card_index = card_index })
      end
    end
  elseif card.resettable and not presentation_mode then
    Content.draw_meter_reset_icon(draw_list, scale, x, y, w, hovered)
    if primary_activated then
      local button = R.ImGui_MouseButton_Left()
      local drag_x, drag_y = R.ImGui_GetMouseDragDelta(ctx, nil, nil, button, 0.0)
      local moved = math.sqrt((tonumber(drag_x) or 0) ^ 2 + (tonumber(drag_y) or 0) ^ 2)
      if Store.test_override then
        local test_root = os.getenv("CIVIL_CLOCK_TEST_ROOT") or ""
        local file = test_root ~= "" and io.open(test_root .. "\\meter-reset-click-events.txt", "ab")
        if file then
          file:write(string.format(
            "activated focus_prior=%s moved=%.3f source=%s command_valid=%s\n",
            tostring(Content.card_focus_prior(card_index)), moved,
            tostring(card.meter_source ~= nil),
            tostring(card.meter_source and Metering.command_valid(card.meter_source) or false)))
          file:close()
        end
      end
      if Content.card_focus_prior(card_index)
          and moved <= math.max(4, 4 * scale) and card.meter_source then
        Content.queue_card_primary_action({
          kind = "reset", card_index = card_index, source = card.meter_source,
        })
      end
    end
  end
  return card_hovered
end

local CLOCK_FORMAT_OPTIONS = {
  { id = "minsec", label = "Minutes : Seconds" },
  { id = "hms", label = "Hours : Minutes : Seconds" },
  { id = "timecode", label = "SMPTE Timecode" },
  { id = "frames", label = "Absolute Frames" },
  { id = "seconds", label = "Seconds" },
  { id = "samples", label = "Samples" },
  { id = "beats", label = "Beats", separator_before = true },
}

local function select_clock_format(format_id)
  if format_id == "beats" then
    settings.units = "beats"
    save_string("units", settings.units)
  elseif valid_time_formats[format_id] then
    settings.units, settings.time_format = "time", format_id
    save_string("units", settings.units)
    save_string("time_format", settings.time_format)
  end
  recompute_snapshot(true)
end

local function draw_clock_context_menu(scale, x, y, w, h)
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  R.ImGui_InvisibleButton(ctx, "##clock_format_hit", w, h)
  local selected_format = settings.units == "beats" and "Beats"
    or ((function()
      for _, option in ipairs(CLOCK_FORMAT_OPTIONS) do
        if option.id == settings.time_format then return option.label end
      end
      return "Time"
    end)())
  item_tooltip("Right-click for options",
    "Main clock: " .. selected_format .. ". Change its format, size, or related settings.")

  Content.open_context_popup_for_item("clock_format_menu")
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "clock_format_menu") then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("CLOCK FORMAT")
    R.ImGui_Separator(ctx)
    for _, option in ipairs(CLOCK_FORMAT_OPTIONS) do
      if option.separator_before then R.ImGui_Separator(ctx) end
      local selected = option.id == "beats" and settings.units == "beats"
        or settings.units == "time" and settings.time_format == option.id
      if R.ImGui_MenuItem(ctx, option.label .. "##clock_format_" .. option.id,
          nil, selected, true) then
        select_clock_format(option.id)
      end
    end
    R.ImGui_Separator(ctx)
    Content.draw_popup_heading("CLOCK SIZE")
    for _, size_id in ipairs(Runtime.clock_sizes.order) do
      local size = Runtime.clock_sizes[size_id]
      if R.ImGui_MenuItem(ctx, size.label .. "##clock_size_" .. size_id,
          nil, settings.main_clock_size == size_id, true) then
        Content.set_main_clock_size(size_id)
      end
    end
    R.ImGui_Separator(ctx)
    Content.draw_detached_management_menu("clock_popouts")
    R.ImGui_Separator(ctx)
    if R.ImGui_MenuItem(ctx, "Open Clock Settings…##clock_settings") then
      settings_open = true
      settings_tab_request = "clock"
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

local function row_value_base_size(style, visible_count)
  local density = visible_count <= 1 and 1
    or (visible_count <= 2 and 0.9 or (visible_count <= 4 and 0.72 or 0.58))
  return style.value_size * density
end

Metering.Draw = {}

function Metering.Draw.plot_rect(x, y, w, h, scale, show_title)
  local inset = math.max(5, 8 * scale)
  local top = show_title == false and 7 * scale or 25 * scale
  local bottom = 6 * scale
  return x + inset, y + top, math.max(1, w - inset * 2),
    math.max(1, h - top - bottom)
end

function Metering.Draw.grid(draw_list, x, y, w, h, horizontal, vertical, scale)
  local color = with_alpha(C.border, 78)
  for index = 1, horizontal - 1 do
    local py = y + h * index / horizontal
    R.ImGui_DrawList_AddLine(draw_list, x, py, x + w, py, color, math.max(1, 0.65 * scale))
  end
  for index = 1, vertical - 1 do
    local px = x + w * index / vertical
    R.ImGui_DrawList_AddLine(draw_list, px, y, px, y + h, color, math.max(1, 0.65 * scale))
  end
end

function Metering.Draw.levels(draw_list, scale, x, y, w, h, descriptor)
  local frame, config = descriptor.stream.frame, descriptor.config
  local channels = math.max(1, math.min(frame.channels, #frame.peak))
  local floor = math.max(-90, math.min(-36, config.meter_level_floor or -60))
  local rows = channels <= 8 and 1 or 2
  local columns = math.ceil(channels / rows)
  local hottest, hottest_value = 1, -math.huge
  for index, value in ipairs(frame.peak) do
    if value > hottest_value then hottest, hottest_value = index, value end
  end
  local rms_color = with_alpha(mix_color(C.accent, C.secondary, 0.35), 155)
  local peak_color = C.secondary
  local max_color = mix_color(C.accent_secondary, C.ink, 0.35)
  local track_color = with_alpha(C.outer, 178)
  local function normalized(value)
    return math.max(0, math.min(1, ((tonumber(value) or floor) - floor) / -floor))
  end
  local function draw_legend(legend_x, legend_y)
    draw_text_box(draw_list, font_bold, "RMS", legend_x, legend_y,
      25 * scale, 10 * scale, 7 * scale, rms_color, 0, "shrink")
    draw_text_box(draw_list, font_bold, "PEAK", legend_x + 30 * scale, legend_y,
      31 * scale, 10 * scale, 7 * scale, peak_color, 0, "shrink")
    if config.meter_level_peak_max ~= false then
      draw_text_box(draw_list, font_bold, "MAX", legend_x + 66 * scale, legend_y,
        26 * scale, 10 * scale, 7 * scale, max_color, 0, "shrink")
    end
  end
  if channels <= 2 and w >= h * 2.6 then
    local label_w = math.max(18 * scale, math.min(30 * scale, w * 0.07))
    local bar_x, bar_wide = x + label_w, math.max(4, w - label_w)
    local legend_h = h > 92 * scale and w > 420 * scale and 11 * scale or 0
    local scale_h = h > 42 * scale and math.min(11 * scale, h * 0.18) or 0
    local meter_y, meter_h = y + legend_h, math.max(8, h - legend_h - scale_h)
    local channel_h = meter_h / channels
    local function horizontal_position(value)
      return bar_x + bar_wide * normalized(value)
    end
    if legend_h > 0 then draw_legend(bar_x, y) end
    for _, tick in ipairs({ -48, -24, -12, -6, 0 }) do
      if tick >= floor then
        local tx = horizontal_position(tick)
        if scale_h > 0 then
          local tw = (tick <= -12 and 23 or 19) * scale
          local tx_label = math.max(bar_x, math.min(bar_x + bar_wide - tw, tx - tw * 0.5))
          draw_text_box(draw_list, font_bold, tostring(tick), tx_label,
            y + h - scale_h, tw, scale_h, 7 * scale, C.muted, 0.5, "shrink")
        end
      end
    end
    if scale_h > 0 and label_w >= 22 * scale then
      draw_text_box(draw_list, font_bold, "dB", x, y + h - scale_h,
        label_w - 3 * scale, scale_h, 7 * scale, C.muted, 0.5, "shrink")
    end
    for channel = 1, channels do
      local by = meter_y + (channel - 1) * channel_h + 2 * scale
      local bh = math.max(8, channel_h - 4 * scale)
      local radius = math.min(4 * scale, bh * 0.3)
      R.ImGui_DrawList_AddRectFilled(draw_list, bar_x, by, bar_x + bar_wide, by + bh,
        track_color, radius)
      local rms_x, peak_x, max_x = horizontal_position(frame.rms[channel]),
        horizontal_position(frame.peak[channel]), horizontal_position(frame.peak_max[channel])
      R.ImGui_DrawList_AddRectFilled(draw_list, bar_x, by, rms_x, by + bh,
        rms_color, radius)
      R.ImGui_DrawList_AddLine(draw_list, peak_x, by, peak_x, by + bh,
        peak_color, math.max(1.2, 1.8 * scale))
      if config.meter_level_peak_max ~= false then
        R.ImGui_DrawList_AddCircleFilled(draw_list, max_x, by + bh * 0.5,
          math.max(1.5, math.min(2.5 * scale, bh * 0.18)), max_color)
      end
      if frame.peak[channel] >= 0 then
        R.ImGui_DrawList_AddRect(draw_list, bar_x, by, bar_x + bar_wide, by + bh,
          C.danger, radius, 0, math.max(1, 1.2 * scale))
      end
      local label = channels == 1 and "M" or (channel == 1 and "L" or "R")
      draw_text_box(draw_list, font_bold, label, x, by, label_w - 4 * scale, bh,
        math.max(8, math.min(11 * scale, bh * 0.58)),
        channel == hottest and C.secondary or C.muted, 0.5, "shrink")
    end
    for _, tick in ipairs({ -48, -24, -12, -6, 0 }) do
      if tick >= floor then
        local tx = horizontal_position(tick)
        R.ImGui_DrawList_AddLine(draw_list, tx, meter_y, tx, meter_y + meter_h,
          with_alpha(C.border, tick == 0 and 165 or 88), math.max(1, 0.6 * scale))
      end
    end
    if config.meter_level_true_peak_marker and descriptor.source.runtime.values then
      local value = descriptor.source.runtime.values.true_peak
      if type(value) == "number" and value > -149 then
        local marker_x = horizontal_position(value)
        R.ImGui_DrawList_AddLine(draw_list, marker_x, meter_y, marker_x, meter_y + meter_h,
          with_alpha(C.danger, 220), math.max(1, scale))
        if w > 340 * scale then
          draw_text_box(draw_list, font_bold, string.format("TP %.1f", value),
            x + w - 58 * scale, legend_h > 0 and y or meter_y,
            56 * scale, 11 * scale, 8 * scale,
            C.danger, 1, "shrink")
        end
      end
    end
    return
  end

  local legend_h = h > 105 * scale and w > 400 * scale and 11 * scale or 0
  local meter_y, meter_h = y + legend_h, math.max(8, h - legend_h)
  local scale_w = w > 200 * scale and math.min(28 * scale, w * 0.09) or 0
  local bars_x, bars_wide = x + scale_w, math.max(4, w - scale_w)
  local row_h = meter_h / rows
  local gap = math.max(1, math.min(5 * scale, bars_wide / math.max(8, columns * 4)))
  local bar_w = math.max(2, (bars_wide - gap * (columns - 1)) / columns)
  if legend_h > 0 then draw_legend(bars_x, y) end

  local vertical_ticks = rows == 1 and { -48, -24, -12, 0 } or { -24, -12, 0 }
  for row = 0, rows - 1 do
    local by = meter_y + row * row_h + 2 * scale
    local label_h = channels <= 16 and math.min(13 * scale, row_h * 0.2) or 0
    local bh = math.max(4, row_h - label_h - 4 * scale)
    for _, tick in ipairs(vertical_ticks) do
      if tick >= floor then
        local ty = by + bh * (1 - normalized(tick))
        if scale_w > 0 then
          local th = math.min(9 * scale, bh * 0.18)
          local label_y = math.max(by, math.min(by + bh - th, ty - th * 0.5))
          draw_text_box(draw_list, font_bold, tostring(tick), x, label_y,
            scale_w - 4 * scale, th, 7 * scale, C.muted, 1, "shrink")
        end
      end
    end
  end
  for row = 0, rows - 1 do
    local by = meter_y + row * row_h + 2 * scale
    local label_h = channels <= 16 and math.min(13 * scale, row_h * 0.2) or 0
    local bh = math.max(4, row_h - label_h - 4 * scale)
    for _, tick in ipairs(vertical_ticks) do
      if tick >= floor then
        local ty = by + bh * (1 - normalized(tick))
        R.ImGui_DrawList_AddLine(draw_list, bars_x, ty, x + w, ty,
          with_alpha(C.border, tick == 0 and 165 or 88), math.max(1, 0.6 * scale))
      end
    end
  end
  for channel = 1, channels do
    local row, column = math.floor((channel - 1) / columns), (channel - 1) % columns
    local bx = bars_x + column * (bar_w + gap)
    local by = meter_y + row * row_h + 2 * scale
    local label_h = channels <= 16 and math.min(13 * scale, row_h * 0.2) or 0
    local bh = math.max(4, row_h - label_h - 4 * scale)
    local rms_y = by + bh * (1 - normalized(frame.rms[channel]))
    local peak_y = by + bh * (1 - normalized(frame.peak[channel]))
    local max_y = by + bh * (1 - normalized(frame.peak_max[channel]))
    R.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bar_w, by + bh,
      track_color, math.min(3 * scale, bar_w * 0.28))
    R.ImGui_DrawList_AddRectFilled(draw_list, bx, rms_y, bx + bar_w, by + bh,
      rms_color, math.min(3 * scale, bar_w * 0.28))
    local line = math.max(1, math.min(2.2 * scale, bar_w * 0.22))
    R.ImGui_DrawList_AddLine(draw_list, bx, peak_y, bx + bar_w, peak_y, peak_color, line)
    if config.meter_level_peak_max ~= false then
      R.ImGui_DrawList_AddCircleFilled(draw_list, bx + bar_w * 0.5, max_y,
        math.max(1, math.min(2.2 * scale, bar_w * 0.18)), max_color)
    end
    if frame.peak[channel] >= 0 then
      R.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bar_w, by + math.max(2, 4 * scale),
        C.danger, 1 * scale, 0, math.max(1, scale))
    end
    if channel == hottest and channels > 8 then
      R.ImGui_DrawList_AddRect(draw_list, bx - 1, by - 1, bx + bar_w + 1, by + bh + 1,
        with_alpha(C.accent, 190), 3 * scale, 0, math.max(1, scale))
    end
    if label_h > 0 then
      local label = channels == 1 and "MONO" or (channels == 2 and (channel == 1 and "L" or "R")
        or (bar_w >= 32 * scale and "CH " .. tostring(channel) or tostring(channel)))
      draw_text_box(draw_list, font_bold, label, bx, by + bh + 1 * scale,
        bar_w, label_h, math.max(7, math.min(10 * scale, bar_w * 0.55)),
        channel == hottest and C.secondary or C.muted, 0.5, "shrink")
    end
  end
  if config.meter_level_true_peak_marker and descriptor.source.runtime.values then
    local value = descriptor.source.runtime.values.true_peak
    if type(value) == "number" and value > -149 then
      for row = 0, rows - 1 do
        local by = meter_y + row * row_h + 2 * scale
        local label_h = channels <= 16 and math.min(13 * scale, row_h * 0.2) or 0
        local bh = math.max(4, row_h - label_h - 4 * scale)
        local marker_y = by + bh * (1 - normalized(value))
        R.ImGui_DrawList_AddLine(draw_list, bars_x, marker_y, x + w, marker_y,
          with_alpha(C.danger, 205), math.max(1, scale))
        if row == 0 and w > 260 * scale then
          draw_text_box(draw_list, font_bold, string.format("TP %.1f", value),
            x + w - 60 * scale, math.max(by, marker_y - 11 * scale),
            58 * scale, 11 * scale, 8 * scale, C.danger, 1, "shrink")
        end
      end
    end
  end
end

function Metering.Draw.history(draw_list, scale, x, y, w, h, descriptor)
  local config, runtime = descriptor.config, descriptor.source.runtime
  local history = runtime.loudness_history
  if not history then return end
  local seconds = math.max(30, math.min(7200, config.meter_history_seconds or 60))
  local values, head = seconds > 180 and history.archive or history.recent,
    seconds > 180 and history.archive_head or history.recent_head
  local now, minimum, maximum = R.time_precise(), config.meter_history_min or -36,
    config.meter_history_max or -6
  if maximum <= minimum then maximum = minimum + 1 end
  Metering.Draw.grid(draw_list, x, y, w, h, h > 70 * scale and 4 or 2,
    w > 320 * scale and 6 or 3, scale)
  local target = tonumber(config.meter_history_target)
  if target and target >= minimum and target <= maximum then
    local ty = y + h * (1 - (target - minimum) / (maximum - minimum))
    R.ImGui_DrawList_AddLine(draw_list, x, ty, x + w, ty,
      with_alpha(C.muted, 135), math.max(1, scale))
  end
  local traces = "," .. tostring(config.meter_history_traces or "m,s,i") .. ","
  local definitions = {
    { "m", "m", C.accent, 1, false },
    { "s", "s", C.secondary, 1.35, false },
    { "i", "i", C.accent_secondary, 1.6, true },
  }
  local available = math.max(0, #values - head + 1)
  local oldest_age = 0
  for index = head, #values do
    local point = values[index]
    if point and type(point.time) == "number" and now - point.time <= seconds then
      oldest_age = math.max(0, now - point.time)
      break
    end
  end
  local stride = math.max(1, math.ceil(available / math.max(32, math.floor(w / scale))))
  for _, trace in ipairs(definitions) do
    if traces:find("," .. trace[1] .. ",", 1, true) then
      local prior_x, prior_y, segment = nil, nil, 0
      for index = head, #values, stride do
        local point, value = values[index], values[index][trace[2]]
        if point and type(value) == "number" and now - point.time <= seconds then
          local px = x + w * math.max(0, math.min(1, 1 - (now - point.time) / seconds))
          local py = y + h * (1 - math.max(0, math.min(1,
            (value - minimum) / (maximum - minimum))))
          if prior_x and (not trace[5] or segment % 3 ~= 1) then
            R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py,
              trace[3], math.max(1, trace[4] * scale))
          end
          prior_x, prior_y, segment = px, py, segment + 1
        end
      end
    end
  end
  if w > 360 * scale and h > 70 * scale then
    draw_text_box(draw_list, font_bold, "M  S  I", x + 5 * scale, y + 3 * scale,
      62 * scale, 13 * scale, 8 * scale, C.muted, 0, "shrink")
  end
  local coverage = math.max(0, math.min(1, oldest_age / seconds))
  local empty_w = w * (1 - coverage)
  if coverage < 0.92 and empty_w > 108 * scale and h > 46 * scale then
    local elapsed = math.floor(oldest_age + 0.5)
    local label = elapsed > 0 and string.format("COLLECTING %d / %d SEC", elapsed, seconds)
      or "COLLECTING HISTORY"
    draw_text_box(draw_list, font_bold, label, x + 5 * scale, y + h - 14 * scale,
      math.min(150 * scale, empty_w - 10 * scale), 11 * scale,
      7 * scale, with_alpha(C.muted, 185), 0, "shrink")
  end
end

function Metering.Draw.waveform(draw_list, scale, x, y, w, h, descriptor, cache)
  local frame, config = descriptor.stream.frame, descriptor.config
  local values = cache and cache.wave_display or frame.wave
  local count = math.floor(#values / 4)
  if count < 1 then return end
  local maximum = 0
  for _, value in ipairs(values) do maximum = math.max(maximum, math.abs(value)) end
  local range = math.max(0.125, math.min(1, maximum * 1.12))
  local stacked = config.meter_waveform_layout == "stacked"
    and frame.channel_a ~= frame.channel_b and frame.mode ~= Metering.Visual.mode.all
  local center_a, amplitude = stacked and (y + h * 0.25) or (y + h * 0.5),
    stacked and h * 0.22 or h * 0.46
  local center_b = y + h * 0.75
  R.ImGui_DrawList_AddLine(draw_list, x, center_a, x + w, center_a,
    with_alpha(C.border, 120), math.max(1, 0.7 * scale))
  if stacked then
    R.ImGui_DrawList_AddLine(draw_list, x, center_b, x + w, center_b,
      with_alpha(C.border, 120), math.max(1, 0.7 * scale))
  end
  local color_a, color_b = C.secondary, with_alpha(C.accent_secondary, stacked and 235 or 175)
  local stride = math.max(1, math.ceil(count / math.max(32, math.floor(w))))
  for index = 1, count, stride do
    local px = x + w * (index - 1) / math.max(1, count - 1)
    local base = (index - 1) * 4
    local amin, amax = values[base + 1] / range, values[base + 2] / range
    local bmin, bmax = values[base + 3] / range, values[base + 4] / range
    R.ImGui_DrawList_AddLine(draw_list, px, center_a - amax * amplitude,
      px, center_a - amin * amplitude, color_a, math.max(1, scale))
    if frame.channel_a ~= frame.channel_b and frame.mode ~= Metering.Visual.mode.all then
      local center = stacked and center_b or center_a
      R.ImGui_DrawList_AddLine(draw_list, px, center - bmax * amplitude,
        px, center - bmin * amplitude, color_b, math.max(1, scale))
    end
  end
end

function Metering.Draw.spectrum(draw_list, scale, x, y, w, h, descriptor, cache)
  local config, frame = descriptor.config, descriptor.stream.frame
  local values = cache and cache.spectrum or frame.spectrum
  if not values or #values < 2 then return end
  local floor = math.max(-120, math.min(-60, config.meter_spectrum_floor or -90))
  Metering.Draw.grid(draw_list, x, y, w, h, h > 70 * scale and 3 or 2,
    w > 320 * scale and 6 or 3, scale)
  local prior_x, prior_y = x, y + h
  local stride = math.max(1, math.ceil(#values / math.max(48, math.floor(w))))
  for index = 1, #values, stride do
    local px = x + w * (index - 1) / math.max(1, #values - 1)
    local value = math.max(floor, math.min(0, values[index]))
    local py = y + h * (1 - (value - floor) / -floor)
    R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py,
      C.secondary, math.max(1, 1.4 * scale))
    R.ImGui_DrawList_AddLine(draw_list, px, py, px, y + h,
      with_alpha(C.accent, 24), math.max(1, scale))
    prior_x, prior_y = px, py
  end
  if config.meter_spectrum_peak_hold and cache and cache.spectrum_peak then
    prior_x, prior_y = nil, nil
    for index = 1, #cache.spectrum_peak, stride do
      local px = x + w * (index - 1) / math.max(1, #cache.spectrum_peak - 1)
      local value = math.max(floor, math.min(0, cache.spectrum_peak[index]))
      local py = y + h * (1 - (value - floor) / -floor)
      if prior_x then R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py,
        with_alpha(C.ink, 105), math.max(1, 0.8 * scale)) end
      prior_x, prior_y = px, py
    end
  end
  if w > 390 * scale and h > 72 * scale then
    for _, marker in ipairs({ { 20, "20" }, { 100, "100" }, { 1000, "1k" },
        { 10000, "10k" } }) do
      if marker[1] < frame.sample_rate * 0.5 then
        local px = x + w * math.log(marker[1] / 20) / math.log((frame.sample_rate * 0.5) / 20)
        local label_w = 24 * scale
        local label_x = math.max(x, math.min(x + w - label_w, px - label_w * 0.5))
        draw_text_box(draw_list, font_bold, marker[2], label_x, y + h - 13 * scale,
          label_w, 12 * scale, 7 * scale, C.muted, 0.5, "shrink")
      end
    end
  end
end

function Metering.Draw.spectrogram(draw_list, scale, x, y, w, h, descriptor, cache)
  local ring = cache and cache.spectrogram
  if not ring or not ring.image or not ring.pixel_api then
    draw_text_box(draw_list, font_bold, "SPECTROGRAM REQUIRES NEWER REAIMGUI",
      x + 8 * scale, y, w - 16 * scale, h, 12 * scale, C.muted, 0.5, "shrink")
    return
  end
  local image_width = math.max(1, ring.image_width or 256)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h,
    ring.blank_color or C.outer, 3 * scale)
  local split = (ring.image_head or 0) / image_width
  local interval = math.max(1 / 60, tonumber(ring.column_interval) or 1 / 15)
  local phase = math.max(0, math.min(1,
    (R.time_precise() - (ring.last_at or R.time_precise())) / interval))
  if Store.test_override and phase > 0.05 and phase < 0.95 then
    ring.test_fractional_frames = (ring.test_fractional_frames or 0) + 1
  end
  local shift = phase * w * math.max(1, ring.pixel_multiplier or 1) / image_width
  local first_width = w * (1 - split)
  if first_width > 0 then
    R.ImGui_DrawList_AddImage(draw_list, ring.image,
      x - shift, y, x + first_width - shift, y + h,
      split, 0, 1, 1, 0xFFFFFFFF)
  end
  if split > 0 then
    R.ImGui_DrawList_AddImage(draw_list, ring.image,
      x + first_width - shift, y, x + w - shift, y + h,
      0, 0, split, 1, 0xFFFFFFFF)
  end
  if shift > 0 and ring.tail_image then
    R.ImGui_DrawList_AddImage(draw_list, ring.tail_image,
      x + w - shift, y, x + w, y + h, 0, 0, 1, 1, 0xFFFFFFFF)
  end
  R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, with_alpha(C.border, 120), 3 * scale)
end

function Metering.Draw.vectorscope(draw_list, scale, x, y, w, h, descriptor, cache)
  local cx, cy, radius = x + w * 0.5, y + h * 0.5, math.max(3, math.min(w, h) * 0.46)
  local guide = with_alpha(C.border, 125)
  R.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, guide, 48, math.max(1, scale))
  R.ImGui_DrawList_AddLine(draw_list, cx - radius, cy, cx + radius, cy, guide, math.max(1, scale))
  R.ImGui_DrawList_AddLine(draw_list, cx, cy - radius, cx, cy + radius, guide, math.max(1, scale))
  R.ImGui_DrawList_AddLine(draw_list, cx - radius * 0.7, cy - radius * 0.7,
    cx + radius * 0.7, cy + radius * 0.7, with_alpha(guide, 80), math.max(1, 0.7 * scale))
  R.ImGui_DrawList_AddLine(draw_list, cx - radius * 0.7, cy + radius * 0.7,
    cx + radius * 0.7, cy - radius * 0.7, with_alpha(guide, 80), math.max(1, 0.7 * scale))
  local frames = cache and cache.scope_frames or {}
  local first = math.max(1, #frames - 5)
  for frame_index = first, #frames do
    local values = frames[frame_index].values
    local age = #frames - frame_index
    local color = with_alpha(C.secondary, math.max(42, 220 - age * 35))
    local stride = age > 0 and 4 or 2
    local prior_x, prior_y = nil, nil
    for index = 1, #values - 1, stride * 2 do
      local left, right = values[index], values[index + 1]
      local mid, side = (left + right) * 0.5, (left - right) * 0.5
      local vx, vy = descriptor.config.meter_scope_mode == "ms" and mid or side,
        descriptor.config.meter_scope_mode == "ms" and side or mid
      local px, py = cx + vx * radius, cy - vy * radius
      if prior_x then R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py,
        color, math.max(1, 0.8 * scale)) end
      prior_x, prior_y = px, py
    end
  end
  if w > 270 * scale and h > 80 * scale then
    draw_text_box(draw_list, font_bold,
      descriptor.config.meter_scope_mode == "ms" and "MID / SIDE" or "LEFT / RIGHT",
      x + 4 * scale, y + 3 * scale, 74 * scale, 12 * scale,
      8 * scale, C.muted, 0, "shrink")
  end
  if w > 460 * scale and h > 92 * scale then
    local correlation = tonumber(descriptor.stream.frame.correlation)
      or tonumber(descriptor.source.runtime.values
        and descriptor.source.runtime.values.correlation) or 0
    correlation = math.max(-1, math.min(1, correlation))
    local stats = cache and cache.scope_stats or {}
    local balance = math.max(-99.9, math.min(99.9, tonumber(stats.balance_db) or 0))
    local balance_text = math.abs(balance) < 0.1 and "CENTERED"
      or string.format("%s +%.1f dB", balance > 0 and "L" or "R", math.abs(balance))
    local side = math.max(0, math.min(100, tonumber(stats.side_percent) or 0))
    local zone_w = math.max(86 * scale, (w - radius * 2 - 72 * scale) * 0.5)
    local value_y = y + h * 0.38
    draw_text_box(draw_list, font_bold, "CORRELATION", x + 10 * scale,
      value_y - 16 * scale, zone_w, 11 * scale, 7 * scale, C.muted, 0, "shrink")
    draw_text_box(draw_list, font_mono, string.format("%+.2f", correlation),
      x + 10 * scale, value_y, zone_w, 24 * scale, 19 * scale,
      correlation >= 0 and C.secondary or C.danger, 0, "shrink")
    local right_x = x + w - zone_w - 10 * scale
    draw_text_box(draw_list, font_bold, "BALANCE", right_x,
      value_y - 16 * scale, zone_w, 11 * scale, 7 * scale, C.muted, 1, "shrink")
    draw_text_box(draw_list, font_mono, balance_text, right_x,
      value_y, zone_w, 20 * scale, 13 * scale, C.ink, 1, "shrink")
    draw_text_box(draw_list, font_bold, string.format("SIDE ENERGY %.0f%%", side),
      right_x, value_y + 22 * scale, zone_w, 11 * scale,
      7 * scale, C.muted, 1, "shrink")
  end
end

function Metering.Draw.correlation(draw_list, scale, x, y, w, h, descriptor, cache)
  local runtime, stream = descriptor.source.runtime, descriptor.stream
  local value = stream and stream.frame and stream.frame.correlation
    or runtime.values and runtime.values.correlation or 0
  value = math.max(-1, math.min(1, tonumber(value) or 0))
  local bar_h = math.min(18 * scale, h * 0.25)
  local bar_y = y + h * 0.16
  local center = x + w * 0.5
  R.ImGui_DrawList_AddRectFilled(draw_list, x, bar_y, x + w, bar_y + bar_h,
    with_alpha(C.outer, 180), bar_h * 0.5)
  R.ImGui_DrawList_AddLine(draw_list, center, bar_y - 3 * scale,
    center, bar_y + bar_h + 3 * scale, C.muted, math.max(1, scale))
  local edge = center + value * w * 0.5
  R.ImGui_DrawList_AddRectFilled(draw_list, math.min(center, edge), bar_y,
    math.max(center, edge), bar_y + bar_h,
    value >= 0 and with_alpha(C.secondary, 205) or with_alpha(C.danger, 205), bar_h * 0.5)
  draw_text_box(draw_list, font_mono, string.format("%+.2f", value),
    x, bar_y + bar_h + 2 * scale, w, math.min(28 * scale, h * 0.34),
    math.min(24 * scale, h * 0.28), value >= 0 and C.secondary or C.danger, 0.5, "shrink")
  local history = cache and cache.correlation or runtime.correlation_history
  local values = history and (history.values or history.values) or {}
  local head = history and (history.head or 1) or 1
  local history_y, history_h = y + h * 0.68, h * 0.28
  if history_h > 10 * scale and #values >= head then
    R.ImGui_DrawList_AddLine(draw_list, x, history_y + history_h * 0.5,
      x + w, history_y + history_h * 0.5, with_alpha(C.border, 110), math.max(1, 0.7 * scale))
    local now, seconds = R.time_precise(), descriptor.config.meter_correlation_seconds or 10
    local prior_x, prior_y = nil, nil
    for index = head, #values do
      local point = values[index]
      if now - point.time <= seconds then
        local px = x + w * math.max(0, 1 - (now - point.time) / seconds)
        local py = history_y + history_h * (1 - (point.value + 1) * 0.5)
        if prior_x then R.ImGui_DrawList_AddLine(draw_list, prior_x, prior_y, px, py,
          C.accent_secondary, math.max(1, scale)) end
        prior_x, prior_y = px, py
      end
    end
  end
  if w > 320 * scale then
    draw_text_box(draw_list, font_bold, "OUT OF PHASE", x, y, 80 * scale, 12 * scale,
      7 * scale, C.muted, 0, "shrink")
    draw_text_box(draw_list, font_bold, "IN PHASE", x + w - 60 * scale, y,
      60 * scale, 12 * scale, 7 * scale, C.muted, 1, "shrink")
  end
end

function Metering.Draw.card(draw_list, scale, x, y, w, h, descriptor)
  local px, py, pw, ph = Metering.Draw.plot_rect(x, y, w, h, scale,
    descriptor.config.show_title ~= false and not Runtime.card_fullscreen_rendering)
  local cache = descriptor.card_index
    and Runtime.metering.visual.card_data[descriptor.card_index] or nil
  R.ImGui_DrawList_PushClipRect(draw_list, px, py, px + pw, py + ph, true)
  if descriptor.display == "levels" then
    Metering.Draw.levels(draw_list, scale, px, py, pw, ph, descriptor)
  elseif descriptor.display == "history" then
    Metering.Draw.history(draw_list, scale, px, py, pw, ph, descriptor)
  elseif descriptor.display == "waveform" then
    Metering.Draw.waveform(draw_list, scale, px, py, pw, ph, descriptor, cache)
  elseif descriptor.display == "spectrum" then
    Metering.Draw.spectrum(draw_list, scale, px, py, pw, ph, descriptor, cache)
  elseif descriptor.display == "spectrogram" then
    Metering.Draw.spectrogram(draw_list, scale, px, py, pw, ph, descriptor, cache)
  elseif descriptor.display == "vectorscope" then
    Metering.Draw.vectorscope(draw_list, scale, px, py, pw, ph, descriptor, cache)
  elseif descriptor.display == "correlation" then
    Metering.Draw.correlation(draw_list, scale, px, py, pw, ph, descriptor, cache)
  end
  R.ImGui_DrawList_PopClipRect(draw_list)
end

function Content.draw_grid_card(draw_list, scale, ox, oy, x_offset, y_offset,
    width, height, visible_count, card_index, card, editing, row_value_scale, row_style)
  local x, y = ox + x_offset * scale, oy + y_offset * scale
  local w, h = width * scale, height * scale
  local config = settings.cards[card_index]
  local label, value = card.label, card.value
  if editing and (not card.visible or value == "") then
    local option = CARD_TYPE_BY_ID[config.type]
    label = option and option.label:upper() or "EMPTY"
    value = config.type == "none" and "EMPTY SLOT" or "HIDDEN"
  end
  local card_opacity = math.max(0, math.min(1,
    settings.card_background_opacity or DEFAULT_APPEARANCE.card_background_opacity))
  if card_opacity > 0 then
    local tile_color = with_alpha(C.tile, math.floor(card_opacity * 255 + 0.5))
    R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h,
      tile_color, 8 * scale)
    local gradient_strength = settings.background_gradient_strength or 0
    if gradient_strength > 0 then
      local gradient_inset = math.max(1, 3 * scale)
      local gradient_scale = gradient_strength / 0.50
      R.ImGui_DrawList_AddRectFilledMultiColor(draw_list,
        x + gradient_inset, y + gradient_inset,
        x + w - gradient_inset, y + h - gradient_inset,
        with_alpha(C.tile_top,
          math.min(180, math.floor(44 * gradient_scale * card_opacity + 0.5))),
        with_alpha(C.tile_top,
          math.min(180, math.floor(44 * gradient_scale * card_opacity + 0.5))),
        with_alpha(C.tile_bottom,
          math.min(110, math.floor(24 * gradient_scale * card_opacity + 0.5))),
        with_alpha(C.tile_bottom,
          math.min(110, math.floor(24 * gradient_scale * card_opacity + 0.5))))
    end
  end
  if editing then
    R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h,
      with_alpha(C.accent, 70), 8 * scale, 0, math.max(1, scale))
  end
  if card.visual_click and not editing then
    Content.draw_visual_click_card(draw_list, scale, x, y, w, h)
    Content.draw_card_menu(draw_list, scale, x, y, w, h, card_index)
    return
  end
  row_style = row_style or ROW_SIZE_OPTIONS.medium
  local show_title = config.show_title ~= false and not Runtime.card_fullscreen_rendering
  local alignment_id = config.align or "default"
  if alignment_id == "default" then alignment_id = settings.card_alignment end
  local alignment = alignment_id == "center" and 0.5
    or (alignment_id == "right" and 1 or 0)
  if card.action_button and not editing then
    Content.draw_action_button_surface(draw_list, scale, x, y, w, h,
      card_index, card, config, row_style)
    Content.draw_card_menu(draw_list, scale, x, y, w, h, card_index)
    return
  end
  local label_color = C.muted
  if C.card_accents and #C.card_accents > 0 then
    label_color = C.card_accents[((card_index - 1) % #C.card_accents) + 1]
  end
  local visualization_has_secondary_control = card.visualization
    and (card.resettable or card.setup_required) and not presentation_mode
  local text_right_inset = editing and 52
    or card.visualization and (visualization_has_secondary_control and 70 or 46)
    or card.resettable and not presentation_mode and 46 or 28
  local text_width = w - text_right_inset * scale
  if editing then
    R.ImGui_DrawList_PushClipRect(draw_list, x + 8 * scale, y + 3 * scale,
      x + w - 36 * scale, y + h - 11 * scale, true)
  end
  if show_title then
    draw_text_box(draw_list, font_bold, label, x + 14 * scale, y + 5 * scale,
      text_width, 18 * scale, row_style.label_size * scale * settings.regular_size,
      label_color, alignment, "ellipsis")
  end
  if card.visualization then
    Metering.Draw.card(draw_list, scale, x, y, w, h, card.visualization)
    if editing then R.ImGui_DrawList_PopClipRect(draw_list) end
    if not editing then
      local fullscreen_bounds = Content.visualization_fullscreen_bounds(
        scale, x, y, w, visualization_has_secondary_control)
      Content.export_test_visualization_fullscreen_bounds(card_index, fullscreen_bounds)
      local card_hovered = Content.draw_card_menu(draw_list, scale, x, y, w, h,
        card_index, fullscreen_bounds)
      Content.draw_visualization_fullscreen_button(draw_list, scale, card_index,
        card_hovered, fullscreen_bounds)
    end
    return
  end
  local value_font = card.font == "mono" and font_mono or font_regular
  local base_size = row_value_base_size(row_style, visible_count)
  local value_size = base_size * scale * (card.font == "mono"
    and settings.mono_size or settings.regular_size)
  if card.font == "mono" then
    value_size = value_size * (row_value_scale or 1)
  end
  local value_y = show_title and 21 or 5
  local value_bottom = editing and 13 or 5
  draw_text_box(draw_list, value_font, value, x + 14 * scale, y + value_y * scale,
    text_width, (height - value_y - value_bottom) * scale, value_size,
    ((config.type == "next_region_countdown" and snapshot.next_region_warning)
        or (config.type == "next_marker_countdown" and snapshot.next_marker_warning))
      and C.accent or C.secondary, alignment,
    card.fit_mode, card.fit_reference, "card_" .. card_index)
  if editing then R.ImGui_DrawList_PopClipRect(draw_list) end
  if not editing then Content.draw_card_menu(draw_list, scale, x, y, w, h, card_index) end
end

function Content.draw_detached_windows()
  for _, entry in ipairs(settings.detached_cards) do
    if entry.open then
      local index = -entry.id
      if not Runtime.detached.applied[entry.id] then
        if entry.x and entry.y then
          R.ImGui_SetNextWindowPos(ctx, entry.x, entry.y, R.ImGui_Cond_Always())
        end
        R.ImGui_SetNextWindowSize(ctx, entry.w, entry.h, R.ImGui_Cond_Always())
        Runtime.detached.applied[entry.id] = true
      end
      R.ImGui_SetNextWindowSizeConstraints(ctx, 240, 110, 2160, 2160)
      if entry.focus_requested and type(R.ImGui_SetNextWindowFocus) == "function" then
        R.ImGui_SetNextWindowFocus(ctx)
        entry.focus_requested = nil
      end

      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), C.outer)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), C.border)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGrip(), with_alpha(C.accent, 55))
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGripHovered(), C.accent)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGripActive(), C.accent_active)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBg(), C.surface)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBgActive(), C.surface)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBgCollapsed(), C.surface)
      R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 7, 7)
      R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)

      local flags = R.ImGui_WindowFlags_NoCollapse()
        | R.ImGui_WindowFlags_NoDocking()
        | R.ImGui_WindowFlags_NoSavedSettings()
        | R.ImGui_WindowFlags_NoScrollbar()
        | R.ImGui_WindowFlags_NoScrollWithMouse()
      if settings.always_on_top and type(R.ImGui_WindowFlags_TopMost) == "function" then
        flags = flags | R.ImGui_WindowFlags_TopMost()
      end
      local visible, open = R.ImGui_Begin(ctx,
        Content.detached_label(entry) .. "###ReaClockDetached" .. entry.id,
        entry.open, flags)
      if visible then
        local focused = R.ImGui_IsWindowFocused(ctx)
        local ox, oy = R.ImGui_GetCursorScreenPos(ctx)
        local available_w, available_h = R.ImGui_GetContentRegionAvail(ctx)
        local resolved = snapshot.cards[index]
        if resolved then
          local scale = math.max(0.65, math.min(3.2,
            math.min(available_w / 560, available_h / 200)))
          local row_style = resolved.visualization
            and ROW_SIZE_OPTIONS.visualizer or ROW_SIZE_OPTIONS.large
          Runtime.detached.render_focus_prior = entry.focus_prior == true
          Content.draw_grid_card(R.ImGui_GetWindowDrawList(ctx), scale,
            ox, oy, 0, 0, available_w / scale, available_h / scale,
            1, index, resolved, false, 1, row_style)
          Runtime.detached.render_focus_prior = false
        end
        entry.focus_prior = focused
        local x, y = R.ImGui_GetWindowPos(ctx)
        local w, h = R.ImGui_GetWindowSize(ctx)
        if not entry.x or math.abs(entry.x - x) > 0.5
            or not entry.y or math.abs(entry.y - y) > 0.5
            or math.abs(entry.w - w) > 0.5 or math.abs(entry.h - h) > 0.5 then
          entry.x, entry.y, entry.w, entry.h = x, y, w, h
          Store.mark_dirty()
        end
      end
      R.ImGui_End(ctx)
      if entry.open and not open then
        entry.open = false
        Content.save_card(index)
        if Runtime.card_fullscreen and Runtime.card_fullscreen.index == index then
          Runtime.card_fullscreen = nil
        end
      end
      R.ImGui_PopStyleVar(ctx, 2)
      R.ImGui_PopStyleColor(ctx, 8)
    end
  end
end

function Content.draw_detached_error()
  local detached = Runtime.detached
  if not detached or not detached.error or detached.error == "" then return end
  local now = R.time_precise()
  local elapsed = now - (detached.error_started_at or now)
  local duration, fade = 5, 0.35
  if elapsed >= duration then
    detached.error, detached.error_started_at = nil, nil
    if Store.test_override then
      R.SetExtState(EXT, "__detached_error_visible", "", false)
    end
    return
  end
  if Store.test_override then
    R.SetExtState(EXT, "__detached_error_visible", detached.error, false)
  end

  local owner = main_geometry or Runtime.settings_owner_geometry
    or { x = 100, y = 100, w = 918, h = 600 }
  local width = math.min(520, math.max(300, (owner.w or 520) - 32))
  local x = (owner.x or 100) + ((owner.w or width) - width) * 0.5
  local y = (owner.y or 100) + 16
  local alpha = math.min(1, elapsed / 0.12)
  if elapsed > duration - fade then
    alpha = alpha * math.max(0, (duration - elapsed) / fade)
  end

  R.ImGui_SetNextWindowPos(ctx, x, y, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSizeConstraints(ctx, width, 0, width, 120)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), with_alpha(C.danger, 220))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.ink)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_Alpha(), alpha)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 14, 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 8)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 6, 3)
  local flags = R.ImGui_WindowFlags_NoDecoration()
    | R.ImGui_WindowFlags_NoMove() | R.ImGui_WindowFlags_NoResize()
    | R.ImGui_WindowFlags_NoDocking() | R.ImGui_WindowFlags_NoSavedSettings()
  if type(R.ImGui_WindowFlags_AlwaysAutoResize) == "function" then
    flags = flags | R.ImGui_WindowFlags_AlwaysAutoResize()
  end
  if type(R.ImGui_WindowFlags_NoFocusOnAppearing) == "function" then
    flags = flags | R.ImGui_WindowFlags_NoFocusOnAppearing()
  end
  if type(R.ImGui_WindowFlags_NoInputs) == "function" then
    flags = flags | R.ImGui_WindowFlags_NoInputs()
  end
  if type(R.ImGui_WindowFlags_TopMost) == "function" then
    flags = flags | R.ImGui_WindowFlags_TopMost()
  end
  local visible = R.ImGui_Begin(ctx, "Pop-Out Notice###ReaClockDetachedError", true, flags)
  if visible then
    R.ImGui_PushFont(ctx, font_bold, 11)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.danger)
    R.ImGui_Text(ctx, "POP-OUT NOT COMPLETED")
    R.ImGui_PopStyleColor(ctx)
    R.ImGui_PopFont(ctx)
    R.ImGui_PushFont(ctx, font_regular, 12.5)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.secondary)
    R.ImGui_PushTextWrapPos(ctx, width - 14)
    R.ImGui_TextWrapped(ctx, detached.error)
    R.ImGui_PopTextWrapPos(ctx)
    R.ImGui_PopStyleColor(ctx)
    R.ImGui_PopFont(ctx)
  end
  R.ImGui_End(ctx)
  R.ImGui_PopStyleVar(ctx, 5)
  R.ImGui_PopStyleColor(ctx, 3)
end

function Content.mono_row_scale(scale, visible_count, active, row_style)
  local base_size = row_value_base_size(row_style or ROW_SIZE_OPTIONS.medium, visible_count)
  local font_size = math.max(6, base_size * scale * settings.mono_size)
  local factor, count = 1, 0
  R.ImGui_PushFont(ctx, font_mono, font_size)
  for _, entry in ipairs(active) do
    local card = entry.content
    if card.font == "mono" and not card.visual_click then
      local available = math.max(1, ((entry.render_width or 1) - 28) * scale)
      local text = card.fit_reference or card.value
      local text_width = R.ImGui_CalcTextSize(ctx, tostring(text or ""))
      if text_width > available then factor = math.min(factor, available / text_width) end
      count = count + 1
    end
  end
  R.ImGui_PopFont(ctx)
  if count < 2 then return 1 end
  return factor
end

function Content.draw_edit_card_controls(draw_list, scale, x, y, w, h,
    row, column, card_index)
  -- Keep the right edge free for explicit remove and drag-grip targets while
  -- the rest of the tile remains a generous selection/context/drop surface.
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  local selected = R.ImGui_InvisibleButton(
    ctx, "##edit_card_" .. card_index, w - 28 * scale, h)
  if selected then edit_selected_row, edit_selected_card = row, card_index end
  local hovered = R.ImGui_IsItemHovered(ctx)
  local is_selected = edit_selected_card == card_index
  if hovered and R.ImGui_IsMouseDoubleClicked(ctx, R.ImGui_MouseButton_Left()) then
    edit_selected_row, edit_selected_card = row, card_index
    Content.open_card_detail_from_double_click(card_index)
  end
  if hovered or is_selected then
    R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h,
      with_alpha(C.accent, hovered and 185 or 105), 8 * scale, 0,
      math.max(1, (hovered and 2 or 1.25) * scale))
  end
  if hovered then
    draw_styled_tooltip("Double-click to customize · Right-click for options",
      Content.card_tooltip_detail(card_index, true))
  end
  local popup_id = "content_menu_card_" .. card_index
  local right_button = R.ImGui_MouseButton_Right and R.ImGui_MouseButton_Right() or 1
  if R.ImGui_IsItemClicked and R.ImGui_IsItemClicked(ctx, right_button) then
    edit_selected_row, edit_selected_card = row, card_index
  end
  Content.open_context_popup_for_item(popup_id)
  if R.ImGui_BeginDragDropSource(ctx) then
    R.ImGui_SetDragDropPayload(ctx, "REACLOCK_CARD", tostring(card_index))
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 14 * math.min(scale, 1.25)))
    R.ImGui_Text(ctx, "Move " .. (CARD_TYPE_BY_ID[settings.cards[card_index].type].label or "card"))
    R.ImGui_PopFont(ctx)
    R.ImGui_EndDragDropSource(ctx)
  end
  if R.ImGui_BeginDragDropTarget(ctx) then
    local accepted, payload = R.ImGui_AcceptDragDropPayload(ctx, "REACLOCK_CARD")
    if accepted then Content.swap_cards(tonumber(payload), card_index) end
    R.ImGui_EndDragDropTarget(ctx)
  end
  local config, resolved = settings.cards[card_index], snapshot.cards[card_index]
  Content.draw_context_popup(scale, popup_id, "ROW " .. row .. " · CARD " .. column,
    config, function(content_type, open_editor, meter_preset)
      Content.set_card_type(card_index, content_type, open_editor, meter_preset)
    end, true, card_index, resolved.fit_mode == "ellipsis" or resolved.fit_mode == "scroll")

  local removable = true
  local cx, cy, radius = x + w - 13 * scale, y + 13 * scale, 9 * scale
  R.ImGui_SetCursorScreenPos(ctx, cx - radius, cy - radius)
  if R.ImGui_InvisibleButton(ctx, "##remove_card_" .. card_index, radius * 2, radius * 2)
      and removable then
    Content.remove_card(row, column)
  end
  local remove_hovered = R.ImGui_IsItemHovered(ctx)
  local remove_color = removable and (remove_hovered and C.inactive_hover or C.inactive_active)
    or with_alpha(C.inactive_active, 95)
  R.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, remove_color)
  if not draw_icon_centered(draw_list, ICON.TRASH,
      cx - radius, cy - radius, radius * 2, radius * 2,
      math.max(6, 11.5 * scale), removable and C.ink or C.muted, 0.5 * scale) then
    R.ImGui_DrawList_AddLine(draw_list, cx - 4 * scale, cy, cx + 4 * scale, cy,
      removable and C.ink or C.muted, math.max(1, 1.5 * scale))
  end
  if remove_hovered then
    draw_styled_tooltip(settings.card_row_counts[row] == 1 and "Remove card and row" or "Remove card",
      settings.card_row_counts[row] == 1
        and "This is the row's final card, so the whole row will also be removed."
        or "Remove this card and close the remaining cards together.")
  end

  local grip_button_size = 22 * scale
  local grip_button_x, grip_button_y = x + w - 25 * scale, y + h - 33 * scale
  R.ImGui_SetCursorScreenPos(ctx, grip_button_x, grip_button_y)
  local grip_selected = R.ImGui_InvisibleButton(
    ctx, "##move_card_grip_" .. card_index, grip_button_size, grip_button_size)
  if grip_selected then edit_selected_row, edit_selected_card = row, card_index end
  local grip_hovered = R.ImGui_IsItemHovered(ctx)
  if grip_hovered then
    R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h,
      with_alpha(C.accent, 185), 8 * scale, 0, math.max(1, 2 * scale))
    draw_styled_tooltip("Right-click for options",
      Content.card_tooltip_detail(card_index, true))
  end
  if R.ImGui_IsItemClicked and R.ImGui_IsItemClicked(ctx, right_button) then
    edit_selected_row, edit_selected_card = row, card_index
  end
  Content.open_context_popup_for_item(popup_id)
  if R.ImGui_BeginDragDropSource(ctx) then
    R.ImGui_SetDragDropPayload(ctx, "REACLOCK_CARD", tostring(card_index))
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 14 * math.min(scale, 1.25)))
    R.ImGui_Text(ctx, "Move " .. (CARD_TYPE_BY_ID[settings.cards[card_index].type].label or "card"))
    R.ImGui_PopFont(ctx)
    R.ImGui_EndDragDropSource(ctx)
  end
  if R.ImGui_BeginDragDropTarget(ctx) then
    local accepted, payload = R.ImGui_AcceptDragDropPayload(ctx, "REACLOCK_CARD")
    if accepted then Content.swap_cards(tonumber(payload), card_index) end
    R.ImGui_EndDragDropTarget(ctx)
  end

  local grip_color = (hovered or grip_hovered) and C.secondary or C.muted
  local fixed_span = tonumber(config.span)
  if fixed_span then
    local span_label = Content.card_span_label(config, true)
    local badge_w, badge_h = 34 * scale, 15 * scale
    local badge_x, badge_y = x + w - 67 * scale, y + h - 25 * scale
    R.ImGui_DrawList_AddRectFilled(draw_list, badge_x, badge_y,
      badge_x + badge_w, badge_y + badge_h, with_alpha(C.surface, 180), 4 * scale)
    draw_text_box(draw_list, font_bold, span_label, badge_x, badge_y,
      badge_w, badge_h, 8 * scale * settings.regular_size, C.muted, 0.5, "shrink")
  end
  if not draw_icon_centered(draw_list, ICON.GRIP_VERTICAL,
      grip_button_x, grip_button_y, grip_button_size, grip_button_size,
      math.max(6, 16 * scale), grip_color, scale) then
    local grip_x, grip_y = x + w - 15 * scale, y + h - 23 * scale
    for grip_row = 0, 2 do
      for grip_column = 0, 1 do
        R.ImGui_DrawList_AddCircleFilled(draw_list,
          grip_x + grip_column * 5 * scale, grip_y + grip_row * 5 * scale,
          math.max(1, 1.25 * scale), grip_color)
      end
    end
  end
end

function Content.draw_add_card(draw_list, scale, ox, oy, row, x_offset, y_offset,
    width, height, enabled, disabled_detail)
  local x, y = ox + x_offset * scale, oy + y_offset * scale
  local w, h = width * scale, height * scale
  local popup_id = "add_card_row_" .. row
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = R.ImGui_InvisibleButton(ctx, "##add_card_" .. row, w, h)
  local hovered = R.ImGui_IsItemHovered(ctx)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h,
    enabled and (hovered and C.inactive_hover or C.tile)
      or with_alpha(C.tile, 115), 8 * scale)
  R.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h,
    with_alpha(enabled and C.accent or C.border,
      enabled and (hovered and 190 or 105) or 80),
    8 * scale, 0, math.max(1, scale))
  local cx, cy = x + w * 0.5, y + h * 0.5
  if not draw_icon_centered(draw_list, ICON.PLUS, x, y, w, h,
      math.max(6, 19 * scale), enabled and C.secondary or C.muted, scale) then
    R.ImGui_DrawList_AddLine(draw_list, cx - 7 * scale, cy, cx + 7 * scale, cy,
      enabled and C.secondary or C.muted, math.max(1, 2 * scale))
    R.ImGui_DrawList_AddLine(draw_list, cx, cy - 7 * scale, cx, cy + 7 * scale,
      enabled and C.secondary or C.muted, math.max(1, 2 * scale))
  end
  if hovered then
    draw_styled_tooltip(enabled and "Add a card" or "Cannot add another card",
      enabled and ("Choose new content to append to Row " .. row .. ".")
        or disabled_detail)
  end
  if clicked and enabled then R.ImGui_OpenPopup(ctx, popup_id) end

  push_popup_style()
  Content.constrain_next_popup_height()
  if R.ImGui_BeginPopup(ctx, popup_id) then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("ADD TO ROW " .. row)
    R.ImGui_Separator(ctx)
    Content.draw_type_menu_items("add_row_" .. row, nil, false, true,
      function(content_type, open_editor, meter_preset)
        Content.add_card(row, content_type, open_editor, meter_preset)
      end)
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.draw_row_drag_handle(draw_list, scale, ox, oy, row, y_offset, height)
  local x, y = ox + 27 * scale, oy + y_offset * scale
  local w, h = 22 * scale, height * scale
  local is_selected = edit_selected_row == row
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  local selected = R.ImGui_InvisibleButton(ctx, "##move_row_" .. row, w, h)
  if selected then
    edit_selected_row, edit_selected_card = row, row_card_index(row, 1)
  end
  local hovered = R.ImGui_IsItemHovered(ctx)
  if hovered or is_selected then
    R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h,
      hovered and C.inactive_hover or with_alpha(C.toggle_selected, 105), 5 * scale)
  end
  if hovered then
    draw_styled_tooltip("Drag or right-click Row " .. row,
      "Drag to reorder the whole row. Right-click to change the size of every card in it.")
  end
  local popup_id = "##edit_row_options_" .. row
  Content.open_context_popup_for_item(popup_id)
  if R.ImGui_BeginDragDropSource(ctx) then
    R.ImGui_SetDragDropPayload(ctx, "REACLOCK_ROW", tostring(row))
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 14 * math.min(scale, 1.25)))
    R.ImGui_Text(ctx, "Move Row " .. row)
    R.ImGui_PopFont(ctx)
    R.ImGui_EndDragDropSource(ctx)
  end
  if R.ImGui_BeginDragDropTarget(ctx) then
    local accepted, payload = R.ImGui_AcceptDragDropPayload(ctx, "REACLOCK_ROW")
    if accepted then Content.move_row(tonumber(payload), row) end
    R.ImGui_EndDragDropTarget(ctx)
  end

  local color = hovered and C.secondary or (is_selected and C.accent_secondary or C.muted)
  if not draw_icon_centered(draw_list, ICON.GRIP, x, y, w, h,
      math.max(6, 18 * scale), color, scale) then
    local center_x, center_y = x + w * 0.5, y + h * 0.5
    for grip_row = -1, 1 do
      for grip_column = -1, 1 do
        R.ImGui_DrawList_AddCircleFilled(draw_list,
          center_x + grip_column * 5 * scale, center_y + grip_row * 5 * scale,
          math.max(1, 1.35 * scale), color)
      end
    end
  end

  push_popup_style()
  if R.ImGui_BeginPopup(ctx, popup_id) then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("ROW " .. row .. " SIZE")
    R.ImGui_Separator(ctx)
    Content.draw_row_size_menu_items(row, "row_handle_size_" .. row .. "_")
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.draw_card_grid(draw_list, scale, ox, oy, layout)
  Content.process_pending_card_action()
  local reserve_empty_cards = snapshot.transport_kind ~= "stopped"
  for row = 1, settings.card_rows do
    -- A card action can change the row model while this frame still owns the
    -- previous layout. Stop here and let the next frame draw the new geometry.
    if layout_resize_pending then return end
    local configured_count = settings.card_row_counts[row]
    local active = {}
    for column = 1, configured_count do
      local card_index = row_card_index(row, column)
      local card = snapshot.cards[card_index]
      if edit_mode or card.visible
          and (card.value ~= "" or reserve_empty_cards or card.keep_visible) then
        active[#active + 1] = { index = card_index, content = card, column = column }
      end
    end
    local visible_count = #active
    local row_layout = layout.rows[row]
    if visible_count > 0 and row_layout then
      local gap = 8
      local show_add = edit_mode
      local add_width = show_add and 48 or 0
      local usable_width = 800 - (show_add and add_width + gap or 0)
      local available_card_width = usable_width - gap * (visible_count - 1)
      local fixed_units, auto_count = 0, 0
      for _, entry in ipairs(active) do
        local fixed = tonumber(settings.cards[entry.index].span)
        if fixed then fixed_units = fixed_units + fixed else auto_count = auto_count + 1 end
      end
      local auto_units = auto_count > 0
        and math.max(1, (CARDS_PER_ROW - fixed_units) / auto_count) or 0
      local unit_width = available_card_width / CARDS_PER_ROW
      for _, entry in ipairs(active) do
        entry.render_units = tonumber(settings.cards[entry.index].span) or auto_units
        entry.render_width = unit_width * entry.render_units
      end
      local y, row_height, row_style = row_layout.y, row_layout.height, row_layout.style
      if edit_mode then
        Content.draw_row_drag_handle(draw_list, scale, ox, oy, row, y, row_height)
        if layout_resize_pending then return end
      end
      local row_value_scale = edit_mode and 1
        or Content.mono_row_scale(scale, visible_count, active, row_style)
      local x = 58
      for _, entry in ipairs(active) do
        local width = entry.render_width
        Content.draw_grid_card(draw_list, scale, ox, oy, x, y,
          width, row_height, visible_count, entry.index, entry.content, edit_mode,
          row_value_scale, row_style)
        if edit_mode then
          Content.draw_edit_card_controls(draw_list, scale,
            ox + x * scale, oy + y * scale, width * scale, row_height * scale,
            row, entry.column, entry.index)
        end
        x = x + width + gap
      end
      if show_add then
        local add_enabled = Content.row_can_add_card(row)
        local disabled_detail = configured_count >= CARDS_PER_ROW
          and "This row already contains the six-card maximum."
          or "All six width units are assigned. Reduce a fixed card width or switch one to Auto first."
        Content.draw_add_card(draw_list, scale, ox, oy, row,
          58 + usable_width + gap, y, add_width, row_height,
          add_enabled, disabled_detail)
      end
    end
  end
end

local function draw_settings_recovery_badge(draw_list, scale, ox, oy, utility_y)
  if not Store.warning or Store.warning_acknowledged
      or R.time_precise() - (Store.warning_started_at or 0) >= 8 then return false, false end
  local label = (Store.warning_label or "SETTINGS NOTICE"):gsub("^SETTINGS%s+", "")
  local x, y, w, h = ox + 554 * scale, oy + utility_y * scale, 118 * scale, 27 * scale
  local clicked, hovered = draw_segment_button(label, "settings_recovery", x, y, w, h,
    false, scale, 1)
  if clicked then settings_open = true end
  item_tooltip(Store.warning_label or "Settings notice", Store.warning .. " Click to open Settings.")
  R.ImGui_DrawList_AddCircleFilled(draw_list, x + 10 * scale, y + h * 0.5,
    3 * scale, C.accent)
  return true, hovered
end

function Content.add_row_with_card(content_type, open_editor, meter_preset)
  if settings.card_rows >= MAX_CARD_ROWS or not CARD_TYPE_BY_ID[content_type]
      or content_type == "none" then return end
  local row = settings.card_rows + 1
  settings.card_row_counts[row] = 1
  settings.card_row_sizes[row] = row == 1 and "large" or "medium"
  local index = row_card_index(row, 1)
  settings.cards[index] = Content.new_card(content_type)
  if content_type == "meter" then Content.apply_meter_preset(settings.cards[index], meter_preset) end
  save_string("card_row" .. row .. "_count", 1)
  save_string("card_row" .. row .. "_size", settings.card_row_sizes[row])
  Content.save_card(index)
  Content.set_card_rows(row)
  edit_selected_row, edit_selected_card = row, index
  if content_type == "meter" then Metering.request_source_setup(index) end
end

function Content.draw_edit_row_actions(scale, ox, oy, layout)
  if not layout.edit_actions_y then return end
  local can_add, can_remove = settings.card_rows < MAX_CARD_ROWS, settings.card_rows > 0
  local y = oy + layout.edit_actions_y * scale
  local selected_row = settings.card_rows > 0
    and math.max(1, math.min(settings.card_rows, edit_selected_row)) or nil
  local selected_card = selected_row and Content.ensure_edit_card_selection(selected_row) or nil
  local size_id = selected_row and settings.card_row_sizes[selected_row] or nil
  local size_label = size_id and ROW_SIZE_OPTIONS[size_id].label:upper() or "NO ROW"
  local row_size_alpha = selected_row and 1 or 0.42
  if draw_segment_button(selected_row
      and ("ROW " .. selected_row .. " SIZE · " .. size_label) or "NO ROW SELECTED",
      "edit_selected_row_size", ox + 58 * scale, y,
      150 * scale, 27 * scale, false, scale, row_size_alpha) and selected_row then
    R.ImGui_OpenPopup(ctx, "##edit_selected_row_size_menu")
  end
  item_tooltip(selected_row and ("Resize Row " .. selected_row) or "No row selected",
    selected_row
      and "Choose Small, Medium, Large, or Huge. The size applies to every card in this row."
      or "Add a row before choosing its size.")

  R.ImGui_SetNextWindowPos(ctx, ox + 58 * scale, y - 8 * scale,
    R.ImGui_Cond_Appearing(), 0, 1)
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "##edit_selected_row_size_menu") then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("ROW " .. tostring(selected_row or 1) .. " SIZE")
    R.ImGui_Separator(ctx)
    if selected_row then
      Content.draw_row_size_menu_items(selected_row, "edit_selected_row_size_")
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()

  local selected_config = selected_card and settings.cards[selected_card] or nil
  local selected_column
  if selected_card then selected_column = (selected_card - 1) % CARDS_PER_ROW + 1 end
  local width_label = selected_config and Content.card_span_label(selected_config, true) or "--"
  if draw_segment_button(selected_card
      and ("CARD " .. selected_column .. " WIDTH · " .. width_label) or "NO CARD SELECTED",
      "edit_selected_card_width", ox + 216 * scale, y,
      162 * scale, 27 * scale, false, scale, selected_card and 1 or 0.42)
      and selected_card then
    R.ImGui_OpenPopup(ctx, "##edit_selected_card_width_menu")
  end
  item_tooltip(selected_card and ("Resize Card " .. selected_column) or "No card selected",
    selected_card
      and "Choose Auto or reserve one to six units in this row. Auto shares all remaining width."
      or "Select a card before choosing its width.")

  R.ImGui_SetNextWindowPos(ctx, ox + 216 * scale, y - 8 * scale,
    R.ImGui_Cond_Appearing(), 0, 1)
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "##edit_selected_card_width_menu") then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("ROW " .. tostring(selected_row or 1)
      .. " · CARD " .. tostring(selected_column or 1) .. " WIDTH")
    R.ImGui_Separator(ctx)
    if selected_card then
      Content.draw_card_span_menu_items(selected_card, "edit_selected_card_span_")
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()

  local x = ox + 387 * scale
  if draw_segment_button("+ ROW", "edit_add_row", x, y,
      68 * scale, 27 * scale, false, scale, can_add and 1 or 0.42) and can_add then
    R.ImGui_OpenPopup(ctx, "##edit_add_row_menu")
  end
  item_tooltip(can_add and "Add a row" or "Maximum rows reached",
    can_add and "Choose the first card for a new row at the bottom of this Clock Face."
      or "A Clock Face can contain up to four information rows.")

  x = x + 76 * scale
  if draw_segment_button("- ROW", "edit_remove_row", x, y,
      68 * scale, 27 * scale, false, scale, can_remove and 1 or 0.42) and can_remove then
    Content.remove_row(settings.card_rows)
  end
  item_tooltip(can_remove and "Remove bottom row" or "No row to remove",
    can_remove and "Remove the final row. Drag another row to the bottom first if needed."
      or "Add a row before using the remove-row control.")

  R.ImGui_SetNextWindowPos(ctx, ox + 387 * scale, y - 8 * scale,
    R.ImGui_Cond_Appearing(), 0, 1)
  push_popup_style()
  Content.constrain_next_popup_height()
  if R.ImGui_BeginPopup(ctx, "##edit_add_row_menu") then
    Content.draw_popup_heading("NEW ROW CONTENT")
    R.ImGui_Separator(ctx)
    Content.draw_type_menu_items("bottom_add_row_", nil, false, true,
      function(content_type, open_editor, meter_preset)
        Content.add_row_with_card(content_type, open_editor, meter_preset)
      end)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

Content.click = { pulse = 0, downbeat = false, beat = 1, numerator = 4, phase = 0 }

function Content.click_needed()
  if settings.visual_click then return true end
  for row = 1, settings.card_rows do
    local count = settings.card_row_counts[row]
    for column = 1, count do
      if settings.cards[row_card_index(row, column)].type == "visual_click" then return true end
    end
  end
  return false
end

function Content.update_click_state()
  local click = Content.click
  if not Content.click_needed() then
    click.pulse, click.downbeat = 0, false
    return
  end
  local raw_pos, state = transport_position()
  local active = (state & 1) ~= 0 or (state & 4) ~= 0
  local pos = math.max(0, raw_pos + offset_seconds())
  local beat_in_measure, measure = R.TimeMap2_timeToBeats(0, pos)
  beat_in_measure = math.max(0, tonumber(beat_in_measure) or 0)
  measure = math.max(0, math.floor(tonumber(measure) or 0))
  local whole_beat = math.floor(beat_in_measure + 0.0000001)
  local phase = math.max(0, math.min(0.999999, beat_in_measure - whole_beat))
  local numerator, denominator, tempo = R.TimeMap_GetTimeSigAtTime(0, pos)
  numerator = math.max(1, math.floor(tonumber(numerator) or 4))
  denominator = math.max(1, math.floor(tonumber(denominator) or 4))
  tempo = math.max(1, tonumber(tempo) or 120)
  click.beat = math.max(1, math.min(numerator, whole_beat + 1))
  click.numerator, click.phase = numerator, phase
  click.downbeat, click.active = whole_beat == 0, active

  local permitted = active
    and (settings.click_activation ~= "grid"
      or R.GetToggleCommandState(GRID_LINES_COMMAND) == 1)
    and (settings.click_activation ~= "metronome"
      or R.GetToggleCommandState(METRONOME_COMMAND) == 1)
  if not permitted then click.pulse = 0 return end

  -- Derive elapsed time from REAPER's actual tempo map when possible. The
  -- denominator-aware fallback keeps unusual meters aligned as well.
  local elapsed_ms
  if R.TimeMap2_beatsToTime then
    local ok, beat_time = pcall(R.TimeMap2_beatsToTime, 0, whole_beat, measure)
    if ok and tonumber(beat_time) then elapsed_ms = math.max(0, (pos - beat_time) * 1000) end
  end
  elapsed_ms = elapsed_ms or (phase * 60000 / tempo * 4 / denominator)
  click.pulse = math.max(0, math.min(1, 1 - elapsed_ms / settings.click_decay_ms))
end

function Content.draw_visual_click_card(draw_list, scale, x, y, w, h)
  local click, base_width = Content.click, w / scale
  if click.pulse > 0 then
    local alpha = math.floor((click.downbeat and 62 or 40)
      * click.pulse * settings.click_intensity)
    R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h,
      with_alpha(C.accent, alpha), 8 * scale)
  end
  local alignment = settings.card_alignment == "center" and 0.5 or 0
  draw_text_box(draw_list, font_bold, "VISUAL CLICK", x + 14 * scale, y + 5 * scale,
    w - 28 * scale, 17 * scale, 10 * scale * settings.regular_size,
    C.muted, alignment, "ellipsis")

  local number_width = base_width < 230 and base_width - 28
    or (base_width < 430 and 80 or 108)
  local number_color = click.pulse > 0
    and mix_color(C.ink, C.accent, click.downbeat and 0.42 or 0.22) or C.secondary
  draw_text_box(draw_list, font_mono, tostring(click.beat), x + 14 * scale,
    y + 20 * scale, number_width * scale, h - 24 * scale,
    (h / scale > 70 and 48 or 38) * scale * settings.mono_size,
    number_color, base_width < 230 and 0.5 or 0, "shrink", tostring(click.numerator))
  if base_width < 230 then return end

  local rail_x = x + (number_width + 30) * scale
  local rail_w = w - (number_width + 46) * scale
  local rail_y, rail_h = y + h * 0.66, math.max(5 * scale, h * 0.12)
  draw_text_box(draw_list, font_bold,
    string.format("BAR POSITION · %d / %d", click.beat, click.numerator),
    rail_x, y + 12 * scale, rail_w, 18 * scale,
    9.5 * scale * settings.regular_size, C.muted, 0, "shrink")

  local max_segments = base_width >= 560 and 24 or 14
  if click.numerator <= max_segments then
    local gap = math.max(2 * scale, 3 * scale)
    local segment_w = (rail_w - gap * (click.numerator - 1)) / click.numerator
    for beat = 1, click.numerator do
      local left = rail_x + (beat - 1) * (segment_w + gap)
      local color = C.progress_track
      if beat < click.beat then color = with_alpha(C.accent, 70) end
      if beat == click.beat then
        color = with_alpha(C.accent, 165 + math.floor(90 * click.pulse))
      end
      R.ImGui_DrawList_AddRectFilled(draw_list, left, rail_y,
        left + segment_w, rail_y + rail_h, color, rail_h * 0.45)
    end
  else
    R.ImGui_DrawList_AddRectFilled(draw_list, rail_x, rail_y,
      rail_x + rail_w, rail_y + rail_h, C.progress_track, rail_h * 0.5)
    local progress = math.max(0, math.min(1,
      (click.beat - 1 + click.phase) / click.numerator))
    R.ImGui_DrawList_AddRectFilled(draw_list, rail_x, rail_y,
      rail_x + rail_w * progress, rail_y + rail_h,
      with_alpha(C.accent, 135), rail_h * 0.5)
    local marker_x = rail_x + rail_w * progress
    R.ImGui_DrawList_AddCircleFilled(draw_list, marker_x, rail_y + rail_h * 0.5,
      rail_h * (0.65 + 0.18 * click.pulse), C.accent)
  end
end

local function draw_visual_click(draw_list, scale, ox, oy, face_w, face_h)
  if not settings.visual_click then return end
  local pulse, downbeat = Content.click.pulse, Content.click.downbeat
  if pulse <= 0 then return end
  local alpha = math.floor((38 + 185 * pulse) * settings.click_intensity)
  local thickness = (downbeat and 9 or 5) * scale
  R.ImGui_DrawList_AddRect(draw_list, ox + thickness * 0.5, oy + thickness * 0.5,
    ox + face_w - thickness * 0.5, oy + face_h - thickness * 0.5,
    with_alpha(C.accent, alpha), 8 * scale, 0, thickness)
end

local function draw_background_image(draw_list, scale, ox, oy, face_w, face_h)
  background_image_cache.drawn = false
  local opacity = math.max(0, math.min(0.5,
    settings.background_image_opacity or DEFAULT_APPEARANCE.background_image_opacity))
  if opacity <= 0 or settings.background_image_path == "" then return end
  local image, image_width, image_height = get_background_image()
  if not image then return end

  -- Cover the clock face without distortion, cropping evenly from the longer
  -- image dimension just like a well-behaved CSS background-size: cover.
  local target_aspect = face_w / face_h
  local image_aspect = image_width / image_height
  local u_min, v_min, u_max, v_max = 0, 0, 1, 1
  if image_aspect > target_aspect then
    local visible_width = target_aspect / image_aspect
    u_min, u_max = (1 - visible_width) * 0.5, (1 + visible_width) * 0.5
  elseif image_aspect < target_aspect then
    local visible_height = image_aspect / target_aspect
    v_min, v_max = (1 - visible_height) * 0.5, (1 + visible_height) * 0.5
  end

  local inset = 0
  R.ImGui_DrawList_AddImageRounded(draw_list, image,
    ox + inset, oy + inset, ox + face_w - inset, oy + face_h - inset,
    u_min, v_min, u_max, v_max,
    with_alpha(0xFFFFFFFF, math.floor(opacity * 255 + 0.5)), 0, 0)
  background_image_cache.drawn = true

  -- Preserve the dedicated recording color as a recognizable tint even over
  -- a colorful user image.
  if settings.recording_background_enabled
      and snapshot.transport_kind == "recording" then
    R.ImGui_DrawList_AddRectFilled(draw_list,
      ox + inset, oy + inset, ox + face_w - inset, oy + face_h - inset,
      with_alpha(C.surface, 88), 0)
  end
end

local function draw_face(origin_x, origin_y, avail_w, avail_h)
  -- The face always uses the largest complete centered rectangle that fits.
  -- Automatic floating sizes normally match it exactly; this containment also
  -- protects very tall layouts when a monitor cap or freeform size leaves extra
  -- space in one dimension.
  Content.presentation_action_hovered = false
  local layout = face_layout_metrics()
  local base_h = layout.base_h
  local scale = math.min(avail_w / BASE_W, avail_h / base_h)
  scale = math.max(0.05, scale)
  local face_w, face_h = BASE_W * scale, base_h * scale
  local ox = origin_x + (avail_w - face_w) * 0.5
  local vertical_room = math.max(0, avail_h - face_h)
  local vertical_position = presentation_mode
    and math.max(0, math.min(1, settings.presentation_vertical_position or 0.5))
    or 0.5
  local oy = origin_y + vertical_room * vertical_position
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local normal_palette = C
  if settings.recording_background_enabled and snapshot.transport_kind == "recording" then
    C = normal_palette.recording_palette
  end

  -- Presentation keeps the clock face at its complete design aspect ratio, but
  -- its styled background should fill the monitor behind that centered face.
  -- Floating windows retain their existing face-bounded background treatment.
  local background_x, background_y = ox, oy
  local background_w, background_h = face_w, face_h
  if presentation_mode then
    background_x, background_y = origin_x, origin_y
    background_w, background_h = avail_w, avail_h
  end

  R.ImGui_DrawList_AddRectFilled(draw_list, origin_x, origin_y,
    origin_x + avail_w, origin_y + avail_h, C.outer)
  R.ImGui_DrawList_AddRectFilled(draw_list, background_x, background_y,
    background_x + background_w, background_y + background_h, C.surface)
  local gradient_inset = 0
  local gradient_strength = settings.background_gradient_strength or 0
  if gradient_strength > 0 then
    local gradient_scale = gradient_strength / 0.50
    local surface_top = mix_color(C.surface, C.gradient_tint,
      math.min(0.35, C.gradient_top_amount * gradient_scale))
    local surface_bottom = mix_color(C.surface, 0x000000FF,
      math.min(0.28, 0.032 * gradient_scale))
    R.ImGui_DrawList_AddRectFilledMultiColor(draw_list,
      background_x + gradient_inset, background_y + gradient_inset,
      background_x + background_w - gradient_inset,
      background_y + background_h - gradient_inset,
      surface_top, surface_top, surface_bottom, surface_bottom)
  end
  draw_background_image(draw_list, scale, background_x, background_y,
    background_w, background_h)
  Content.update_click_state()
  draw_visual_click(draw_list, scale, ox, oy, face_w, face_h)

  local edit_button_y = oy + 30 * scale
  local utility_y = oy + layout.utility_y * scale
  local button_h = 27 * scale
  local control_alpha, utility_alpha = Content.update_control_fade()
  if edit_mode then
    draw_text_box(draw_list, font_bold, "SCOPE", ox + 58 * scale, oy + 12 * scale,
      191 * scale, 13 * scale, 10 * scale * settings.regular_size,
      C.muted, 0, "ellipsis")
    draw_text_box(draw_list, font_bold, "BASE", ox + 274 * scale, oy + 12 * scale,
      107 * scale, 13 * scale, 10 * scale * settings.regular_size,
      C.muted, 0, "ellipsis")
    if draw_segment_button("PROJECT", "project", ox + 58 * scale, edit_button_y,
        66 * scale, button_h, settings.scope == "project", scale, control_alpha) then
      settings.scope = "project"
      save_string("scope", settings.scope)
      recompute_snapshot(true)
    end
    item_tooltip("Project scope", "Measure from the project start." .. shortcut_hint("P"))
    if draw_segment_button("REGION", "region", ox + 127 * scale, edit_button_y,
        61 * scale, button_h, settings.scope == "region", scale, control_alpha) then
      settings.scope = "region"
      save_string("scope", settings.scope)
      recompute_snapshot(true)
    end
    item_tooltip("Region scope", "Measure from the current region start." .. shortcut_hint("R"))
    if draw_segment_button("SELECT", "selection", ox + 191 * scale, edit_button_y,
        58 * scale, button_h, settings.scope == "selection", scale, control_alpha) then
      settings.scope = "selection"
      save_string("scope", settings.scope)
      recompute_snapshot(true)
    end
    item_tooltip("Time-selection scope", "Measure from REAPER's active time selection." .. shortcut_hint("S"))
    if draw_segment_button("TIME", "time", ox + 274 * scale, edit_button_y,
        49 * scale, button_h, settings.units == "time", scale, control_alpha) then
      settings.units = "time"
      save_string("units", settings.units)
      recompute_snapshot(true)
    end
    item_tooltip("Time display", "Use minutes, timecode, frames, seconds, or samples." .. shortcut_hint("T"))
    if draw_segment_button("BEATS", "beats", ox + 326 * scale, edit_button_y,
        55 * scale, button_h, settings.units == "beats", scale, control_alpha) then
      settings.units = "beats"
      save_string("units", settings.units)
      recompute_snapshot(true)
    end
    item_tooltip("Bars and beats", "Follow the project tempo map and time signature." .. shortcut_hint("B"))
    Content.draw_face_button(scale, ox + 407 * scale, edit_button_y,
      92 * scale, button_h, control_alpha)
    Content.draw_style_button(scale, ox + 505 * scale, edit_button_y,
      92 * scale, button_h, control_alpha)
  end
  local utility_controls_hovered = false
  local icon_utility_bar = font_icon ~= nil
  local presentation_x = ox + (icon_utility_bar and 746 or 684) * scale
  local edit_x = ox + (icon_utility_bar and 786 or 724) * scale
  local settings_x = ox + (icon_utility_bar and 826 or 790) * scale
  local presentation_clicked, presentation_hovered = Content.draw_presentation_button(
    draw_list, scale, presentation_x, utility_y, 32 * scale, button_h, utility_alpha)
  utility_controls_hovered = presentation_hovered
  if presentation_clicked then
    presentation_request = presentation_mode and "exit" or "enter"
  end
  local edit_clicked, edit_hovered
  if icon_utility_bar then
    edit_clicked, edit_hovered = draw_icon_button(draw_list,
      edit_mode and ICON.CHECK or ICON.PENCIL,
      "edit_cards", edit_x, utility_y, 32 * scale, button_h,
      edit_mode, true, scale, utility_alpha,
      math.max(6, (edit_mode and 15 or 14) * scale), scale, true)
  else
    edit_clicked, edit_hovered = draw_segment_button(
      edit_mode and "DONE" or "EDIT", "edit_cards", edit_x, utility_y,
      54 * scale, button_h, edit_mode, scale, utility_alpha)
  end
  utility_controls_hovered = utility_controls_hovered or edit_hovered
  if edit_clicked then
    edit_mode = not edit_mode
    if edit_mode then
      edit_selected_row = math.max(1, math.min(settings.card_rows, 1))
      edit_selected_card = settings.card_rows > 0 and row_card_index(edit_selected_row, 1) or 1
    end
    request_layout_resize()
  end
  item_tooltip(edit_mode and "Finish editing" or "Edit this Clock Face",
    (edit_mode and "Return to the clean performance view."
      or "Change scope, units, face, rows, cards, order, and style.") .. shortcut_hint("E"))
  local settings_clicked, settings_hovered
  if icon_utility_bar then
    settings_clicked, settings_hovered = draw_icon_button(draw_list,
      ICON.SETTINGS, "settings", settings_x, utility_y, 32 * scale, button_h,
      settings_open, true, scale, utility_alpha, math.max(6, 15 * scale), 0,
      true)
  else
    settings_clicked, settings_hovered = draw_segment_button(
      "SETTINGS", "settings", settings_x, utility_y,
      68 * scale, button_h, false, scale, utility_alpha)
  end
  utility_controls_hovered = utility_controls_hovered or settings_hovered
  if settings_clicked then
    settings_open = not settings_open
  end
  item_tooltip(settings_open and "Close Settings" or "Open Settings",
    settings_open and "Return focus to the clock face."
      or "Configure clock behavior, layout, visual click, appearance, and calibration.")
  if Store.warning and not Store.warning_acknowledged
      and R.time_precise() - (Store.warning_started_at or 0) >= 8 then
    R.ImGui_DrawList_AddCircleFilled(draw_list, ox + 854 * scale, utility_y + 4 * scale,
      3.5 * scale, C.accent)
  end

  local _, recovery_hovered = draw_settings_recovery_badge(
    draw_list, scale, ox, oy, layout.utility_y)
  utility_controls_hovered = utility_controls_hovered or recovery_hovered
  Content.update_presentation_drag(scale,
    utility_controls_hovered or Content.presentation_action_hovered, oy)

  -- Face, Edit, scope, and unit controls can all alter the required
  -- geometry. Keep the stable background/controls from this frame, then draw
  -- the body once face_layout_metrics() reflects the new model next frame.
  if layout_resize_pending then
    C = normal_palette
    return
  end

  if snapshot.blank and not edit_mode then
    if snapshot.gap_display == "next" and snapshot.next_region_countdown ~= "" then
      local gap_top = settings.show_main_clock and 88 or 68
      local countdown_h = math.max(50, base_h - gap_top - 90)
      draw_text_box(draw_list, font_bold, "NEXT REGION",
        ox + 58 * scale, oy + gap_top * scale, 800 * scale, 30 * scale,
        13 * scale * settings.regular_size, C.muted, 0, "ellipsis")
      draw_text_box(draw_list, font_mono, snapshot.next_region_countdown,
        ox + 58 * scale, oy + (gap_top + 27) * scale, 800 * scale, countdown_h * scale,
        170 * scale * settings.mono_size,
        snapshot.next_region_warning and C.accent or C.ink, 0.5, "shrink",
        snapshot.next_region_fit_reference)
      if snapshot.next_region ~= "" then
        draw_text_box(draw_list, font_regular, snapshot.next_region,
          ox + 58 * scale, oy + (base_h - 70) * scale, 800 * scale, 48 * scale,
          42 * scale * settings.regular_size, C.secondary, 0, "ellipsis")
      end
    end
    C = normal_palette
    return
  end

  if settings.show_main_clock then
    draw_text_box(draw_list, font_mono, snapshot.main,
      ox + 58 * scale, oy + layout.clock_text_y * scale,
      800 * scale, layout.clock_h * scale,
      layout.clock_font_size * scale * settings.mono_size,
      C.ink, 0.5, "shrink", snapshot.main_fit_reference)
    draw_clock_context_menu(scale, ox + 58 * scale, oy + layout.clock_y * scale,
      800 * scale, layout.clock_h * scale)
    if layout_resize_pending then
      C = normal_palette
      return
    end
  end

  if settings.show_progress then
    local px, py = ox + 58 * scale, oy + layout.progress_y * scale
    local pw, ph = 800 * scale, layout.progress_h * scale
    R.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + pw, py + ph, C.progress_track, ph * 0.5)
    R.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + pw * snapshot.progress, py + ph, C.accent, ph * 0.5)
  end

  Content.draw_card_grid(draw_list, scale, ox, oy, layout)
  if edit_mode and not layout_resize_pending then
    Content.draw_edit_row_actions(scale, ox, oy, layout)
  end

  C = normal_palette
end

-- -----------------------------------------------------------------------------
-- Settings window
-- -----------------------------------------------------------------------------

local function settings_checkbox(label, key, value, on_change)
  -- Keep the native Checkbox item for keyboard navigation and accessibility,
  -- then paint the compact ReaClock treatment over its transparent geometry.
  local custom_value = value ~= nil
  value = custom_value and value or settings[key]
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), 0x00000000)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgHovered(), 0x00000000)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), 0x00000000)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_CheckMark(), 0x00000000)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), 0x00000000)
  local changed, next_value = R.ImGui_Checkbox(ctx,
    label .. "##compact_" .. (custom_value and key or "settings_" .. key), value == true)
  R.ImGui_PopStyleColor(ctx, 5)

  local min_x, min_y = R.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = R.ImGui_GetItemRectMax(ctx)
  local box_size = 16
  local box_y = min_y + math.max(0, (max_y - min_y - box_size) * 0.5)
  local hovered = R.ImGui_IsItemHovered(ctx)
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local checked = next_value == true
  local fill = checked and (hovered and C.accent_hover or C.accent)
    or hovered and with_alpha(C.inactive_hover, 220) or 0x00000000
  local border = checked and C.accent or with_alpha(C.secondary, 125)
  R.ImGui_DrawList_AddRectFilled(draw_list, min_x, box_y,
    min_x + box_size, box_y + box_size, fill, 4)
  R.ImGui_DrawList_AddRect(draw_list, min_x, box_y,
    min_x + box_size, box_y + box_size, border, 4, 0, checked and 0 or 1.25)
  if checked then
    -- The mockup uses a quiet light tick on every accent. All built-in accent
    -- colors preserve enough separation at this compact 16px size.
    local check_color = 0xFBF4F6FF
    R.ImGui_DrawList_AddLine(draw_list, min_x + 4, box_y + 8,
      min_x + 7, box_y + 11, check_color, 1.8)
    R.ImGui_DrawList_AddLine(draw_list, min_x + 7, box_y + 11,
      min_x + 12.5, box_y + 4.8, check_color, 1.8)
  end
  R.ImGui_PushFont(ctx, font_regular, 12)
  R.ImGui_DrawList_AddText(draw_list, min_x + box_size + 9,
    min_y + math.max(0, (max_y - min_y - 12) * 0.5 - 1), C.ink, label)
  R.ImGui_PopFont(ctx)

  if changed then
    if custom_value then
      on_change(next_value)
    else
      settings[key] = next_value
      save_bool(key, next_value)
      recompute_snapshot(true)
    end
  end
  return changed, next_value
end

local function convert_offset_unit(new_unit)
  if settings.offset_unit == new_unit then return end
  local seconds = offset_seconds()
  settings.offset_unit = new_unit
  if new_unit == "samples" then
    local sample_rate = active_sample_rate()
    settings.offset_value = round_pixel(seconds * sample_rate)
  else
    settings.offset_value = seconds * 1000
  end
  save_string("offset_unit", settings.offset_unit)
  save_string("offset_value", settings.offset_value)
  recompute_snapshot(true)
end

local font_inputs = {
  regular_font = settings.regular_font,
  mono_font = settings.mono_font,
}
local font_search = { regular_font = "", mono_font = "" }
local installed_font_options
local font_scan_summary = "Installed font folders have not been scanned."

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function path_key(path)
  return Runtime.is_windows and tostring(path):lower() or tostring(path)
end

local function font_file_label(path)
  local name = tostring(path):match("([^\\/]+)$") or tostring(path)
  name = name:gsub("%.[Tt][Tt][FfCc]$", ""):gsub("%.[Oo][Tt][Ff]$", "")
  name = name:gsub("[_%-]+", " "):gsub("%s+", " ")
  return trim(name)
end

local function font_source_label(source)
  if looks_like_font_file(source) then return font_file_label(source) end
  return source
end

local function scan_installed_fonts(force)
  if installed_font_options and not force then return installed_font_options end

  local pinned, discovered, seen = {}, {}, {}
  local face_count, truncated = 0, false
  local max_face_files = 12000

  local function add_option(target, label, source, group)
    if not source or source == "" then return end
    local key = path_key(source)
    if seen[key] then return end
    seen[key] = true
    target[#target + 1] = { label = label, source = source, group = group }
  end

  add_option(pinned, "Roboto (bundled default)", "Roboto", "ReaClock")
  add_option(pinned, "Chivo Mono (bundled default)", "Chivo Mono", "ReaClock")
  add_option(pinned, "System sans-serif", "sans-serif", "Generic")
  add_option(pinned, "System monospace", "monospace", "Generic")

  local family_names = {}
  for family in pairs(font_file_candidates) do family_names[#family_names + 1] = family end
  table.sort(family_names, function(a, b) return a:lower() < b:lower() end)
  for _, family in ipairs(family_names) do
    add_option(discovered, family, family, "Known family")
  end

  local visited = {}
  local function scan_directory(dir, depth)
    if truncated or depth > 12 or not dir or dir == "" then return end
    local dir_key = path_key(dir)
    if visited[dir_key] then return end
    visited[dir_key] = true

    local index = 0
    while not truncated do
      local ok, name = pcall(R.EnumerateFiles, dir, index)
      if not ok or not name then break end
      if name:lower():match("%.tt[fc]$") or name:lower():match("%.otf$") then
        local path = join_path(dir, name)
        if path_key(path) ~= path_key(icon_font_path) then
          face_count = face_count + 1
          add_option(discovered, font_file_label(path), path, "Installed face")
          if face_count >= max_face_files then truncated = true end
        end
      end
      index = index + 1
    end

    index = 0
    while not truncated do
      local ok, name = pcall(R.EnumerateSubdirectories, dir, index)
      if not ok or not name then break end
      scan_directory(join_path(dir, name), depth + 1)
      index = index + 1
    end
  end

  for _, root in ipairs(font_scan_roots) do scan_directory(root, 0) end
  table.sort(discovered, function(a, b)
    local left, right = a.label:lower(), b.label:lower()
    if left == right then return path_key(a.source) < path_key(b.source) end
    return left < right
  end)

  installed_font_options = {}
  for _, option in ipairs(pinned) do installed_font_options[#installed_font_options + 1] = option end
  for _, option in ipairs(discovered) do installed_font_options[#installed_font_options + 1] = option end
  font_scan_summary = string.format("%d installed font face%s found%s.", face_count,
    face_count == 1 and "" or "s", truncated and " (12,000-file safety limit reached)" or "")
  return installed_font_options
end

local UI = {}

UI.settings_layout = {
  width = 860,
  header_height = 43,
  nav_height = 43,
  body_padding = 14,
  column_gap = 12,
  card_gap = 12,
}
UI.settings_page = "clock"
UI.settings_font_advanced = { regular_font = false, mono_font = false }
UI.settings_appearance_reset_armed = false

function UI.settings_palette()
  return Content.settings_surface_palette()
end

function UI.settings_note(text, color, wrap_width)
  R.ImGui_PushFont(ctx, font_regular, 10.5)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), color or C.muted)
  local width = wrap_width or UI.settings_inner_width
  if width and width > 0 then
    local x = R.ImGui_GetCursorScreenPos(ctx)
    local window_x = R.ImGui_GetWindowPos(ctx)
    R.ImGui_PushTextWrapPos(ctx, x - window_x + width)
    R.ImGui_Text(ctx, text)
    R.ImGui_PopTextWrapPos(ctx)
  else
    R.ImGui_TextWrapped(ctx, text)
  end
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
end

local METER_SOURCE_POPUP = "Meter Setup###ReaClockMeterSource"

function Metering.draw_source_choice(id, options)
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local width = math.max(320, options.width or UI.settings_inner_width
    or select(1, R.ImGui_GetContentRegionAvail(ctx)))
  local height = 76
  local clicked = R.ImGui_InvisibleButton(ctx, "##meter_source_choice_" .. id, width, height)
  local hovered = R.ImGui_IsItemHovered(ctx) and not options.disabled
  local active = R.ImGui_IsItemActive and R.ImGui_IsItemActive(ctx)
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local emphasized = options.primary or options.current
  local fill = options.disabled and with_alpha(C.tile, 105)
    or active and C.inactive_active
    or hovered and C.inactive_hover
    or emphasized and mix_color(C.tile, C.accent, 0.10)
    or C.tile
  local border = options.disabled and with_alpha(C.border, 90)
    or hovered and C.accent
    or emphasized and mix_color(C.border, C.accent, 0.52)
    or C.border
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, fill, 8)
  R.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, border, 8, 0,
    hovered and 2 or 1)

  local icon_x, icon_y = x + 28, y + height * 0.5
  local icon_color = options.disabled and C.muted or emphasized and C.accent or C.secondary
  R.ImGui_DrawList_AddCircleFilled(draw_list, icon_x, icon_y, 16,
    with_alpha(icon_color, options.disabled and 18 or 34))
  R.ImGui_DrawList_AddCircle(draw_list, icon_x, icon_y, 16,
    with_alpha(icon_color, options.disabled and 80 or 190), 24, 1.25)
  local source_icon = options.kind == "monitoring" and ICON.MONITOR or ICON.AUDIO_LINES
  if not draw_icon_centered(draw_list, source_icon,
      icon_x - 16, icon_y - 16, 32, 32, 19, icon_color, 1) then
    if options.kind == "monitoring" then
      for line = -1, 1 do
        local half = line == 0 and 7 or 5
        R.ImGui_DrawList_AddLine(draw_list, icon_x - half, icon_y + line * 5,
          icon_x + half, icon_y + line * 5, icon_color, line == 0 and 2 or 1.5)
      end
    else
      R.ImGui_DrawList_AddLine(draw_list, icon_x - 7, icon_y - 6, icon_x - 7,
        icon_y + 6, icon_color, 2)
      R.ImGui_DrawList_AddLine(draw_list, icon_x, icon_y - 3, icon_x,
        icon_y + 6, icon_color, 2)
      R.ImGui_DrawList_AddLine(draw_list, icon_x + 7, icon_y - 8, icon_x + 7,
        icon_y + 6, icon_color, 2)
    end
  end

  local badge_width = 0
  if options.badge and options.badge ~= "" then
    R.ImGui_PushFont(ctx, font_regular, 10)
    local text_width, text_height = R.ImGui_CalcTextSize(ctx, options.badge)
    badge_width = text_width + 14
    local badge_x, badge_y = x + width - badge_width - 14, y + 14
    local badge_fill = options.disabled and with_alpha(C.muted, 20)
      or with_alpha(options.current and C.accent_secondary or C.accent, 34)
    local badge_ink = options.disabled and C.muted
      or options.current and C.accent_secondary or C.accent
    R.ImGui_DrawList_AddRectFilled(draw_list, badge_x, badge_y,
      badge_x + badge_width, badge_y + text_height + 6, badge_fill, 5)
    R.ImGui_DrawList_AddText(draw_list, badge_x + 7, badge_y + 3, badge_ink, options.badge)
    R.ImGui_PopFont(ctx)
  end

  local text_x = x + 56
  local text_right = x + width - 14 - (badge_width > 0 and badge_width + 10 or 0)
  R.ImGui_PushFont(ctx, font_bold, 15)
  local title = truncate_current_font(options.title, math.max(60, text_right - text_x))
  R.ImGui_DrawList_AddText(draw_list, text_x, y + 14,
    options.disabled and C.muted or C.ink, title)
  R.ImGui_PopFont(ctx)
  R.ImGui_PushFont(ctx, font_regular, 12)
  local detail = truncate_current_font(options.detail, math.max(80, x + width - 16 - text_x))
  R.ImGui_DrawList_AddText(draw_list, text_x, y + 43,
    options.disabled and with_alpha(C.muted, 180) or C.secondary, detail)
  R.ImGui_PopFont(ctx)

  return clicked and not options.disabled and not options.current
end

function Metering.other_setup_sources(config)
  if not config then return {} end
  local source = Metering.resolve_binding(config)
  local project = Runtime.metering.active_project
  local master = project and R.GetMasterTrack(project)
  local monitoring_source = master and Metering.find_source_for_track(master, "monitoring")
  local destination, kind = Metering.selected_destination()
  local destination_source = destination and Metering.find_source_for_track(destination, kind)
  local results = {}
  for _, candidate in ipairs(Runtime.metering.sources or {}) do
    if candidate.compatible
        and (not source or candidate.key ~= source.key)
        and (not monitoring_source or candidate.key ~= monitoring_source.key)
        and (not destination_source or candidate.key ~= destination_source.key) then
      results[#results + 1] = candidate
    end
  end
  return results
end

function Metering.draw_source_setup_dialog()
  local state = Runtime.metering
  if state.setup_request then
    state.setup_card = state.setup_request
    state.setup_request = nil
    state.setup_close_request = false
    state.setup_status, state.setup_error = nil, nil
    Metering.scan_sources(true)
    R.ImGui_OpenPopup(ctx, METER_SOURCE_POPUP)
  end
  local card_index = state.setup_card
  if not card_index then return end

  local config = settings.cards[card_index]
  if not config or config.type ~= "meter" then state.setup_close_request = true end
  Metering.scan_sources(false)
  local other_sources = config and Metering.other_setup_sources(config) or {}
  local owner_x, owner_y = R.ImGui_GetWindowPos(ctx)
  local owner_w, owner_h = R.ImGui_GetWindowSize(ctx)
  -- Fourteen-pixel body insets plus a separately anchored footer need a little
  -- more vertical room when an existing source selector is present. At 360px
  -- the final safety note, divider, and button row overlap one another.
  local setup_width = 580
  local setup_height = #other_sources > 0 and 404 or 348
  if state.setup_error then setup_height = setup_height + 20 end
  local setup_x = owner_x + owner_w * 0.5 - setup_width * 0.5
  local setup_y = owner_y + owner_h * 0.5 - setup_height * 0.5
  local setup_bounds = window_work_area(owner_x, owner_y, owner_w, owner_h)
  if setup_bounds then
    local inset = 8
    local min_x, min_y = setup_bounds.left + inset, setup_bounds.top + inset
    local max_x = math.max(min_x, setup_bounds.right - setup_width - inset)
    local max_y = math.max(min_y, setup_bounds.bottom - setup_height - inset)
    setup_x = math.max(min_x, math.min(max_x, setup_x))
    setup_y = math.max(min_y, math.min(max_y, setup_y))
  end
  R.ImGui_SetNextWindowPos(ctx, setup_x, setup_y, R.ImGui_Cond_Appearing())
  R.ImGui_SetNextWindowSize(ctx, setup_width, setup_height, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSizeConstraints(ctx,
    setup_width, setup_height, setup_width, setup_height)
  local palette = UI.settings_palette()
  push_popup_style()
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 7, 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), 8, 4)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), palette.subtle_border)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), C.inactive_active)

  local visible, dialog_open
  if R.ImGui_BeginPopupModal then
    visible, dialog_open = R.ImGui_BeginPopupModal(ctx, METER_SOURCE_POPUP, true,
      R.ImGui_WindowFlags_NoTitleBar() | R.ImGui_WindowFlags_NoResize())
  else
    visible = R.ImGui_BeginPopup(ctx, METER_SOURCE_POPUP)
    dialog_open = visible or R.ImGui_IsPopupOpen(ctx, METER_SOURCE_POPUP)
  end
  local should_close = state.setup_close_request or dialog_open == false

  local function close_dialog()
    state.setup_request, state.setup_card = nil, nil
    state.setup_bind_face = false
    state.setup_close_request = false
    if R.ImGui_CloseCurrentPopup then R.ImGui_CloseCurrentPopup(ctx) end
  end

  local function apply_result(okay, detail)
    detail = tostring(detail or (okay and "Meter source ready." or "Meter setup failed."))
    if okay and state.setup_bind_face then
      local face_source = Metering.resolve_binding(config)
      local card_count = face_source and Metering.bind_active_meter_face(face_source) or 0
      if card_count > 1 then
        detail = string.format("All %d cards in this face now use %s.",
          card_count, face_source.display_name)
      end
    end
    state.setup_status, state.setup_error = okay and detail or nil, not okay and detail or nil
    state.operation_status, state.operation_error = okay and detail or nil, not okay and detail or nil
    if okay then
      recompute_snapshot(true)
      close_dialog()
    end
  end

  if visible then
    if should_close then
      close_dialog()
    else
      UI.settings_info_index = 0
      local origin_x, origin_y = R.ImGui_GetCursorScreenPos(ctx)
      local window_width, window_height = R.ImGui_GetWindowSize(ctx)
      local draw_list = R.ImGui_GetWindowDrawList(ctx)
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, origin_y + 14)
      R.ImGui_PushFont(ctx, font_bold, 13)
      R.ImGui_Text(ctx, "Set up audio metering")
      R.ImGui_PopFont(ctx)
      R.ImGui_PushFont(ctx, font_bold, 9.5)
      local context_width = R.ImGui_CalcTextSize(ctx, "METER SETUP")
      R.ImGui_SetCursorScreenPos(ctx,
        origin_x + window_width - context_width - 46, origin_y + 16)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), palette.label)
      R.ImGui_Text(ctx, "METER SETUP")
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)
      local close_x, close_y, close_size = origin_x + window_width - 29, origin_y + 12, 16
      R.ImGui_SetCursorScreenPos(ctx, close_x, close_y)
      if R.ImGui_InvisibleButton(ctx, "##close_meter_setup", close_size, close_size) then
        close_dialog()
      end
      local close_color = R.ImGui_IsItemHovered(ctx) and C.ink or C.muted
      R.ImGui_DrawList_AddLine(draw_list, close_x + 4, close_y + 4,
        close_x + 12, close_y + 12, close_color, 1.1)
      R.ImGui_DrawList_AddLine(draw_list, close_x + 12, close_y + 4,
        close_x + 4, close_y + 12, close_color, 1.1)

      local header_height = 45
      local body_y, body_height = origin_y + header_height, window_height - header_height
      R.ImGui_DrawList_AddRectFilled(draw_list, origin_x, body_y,
        origin_x + window_width, body_y + body_height, palette.body, 10,
        type(R.ImGui_DrawFlags_RoundCornersBottom) == "function"
          and R.ImGui_DrawFlags_RoundCornersBottom() or 0)
      R.ImGui_DrawList_AddLine(draw_list, origin_x, body_y,
        origin_x + window_width, body_y, palette.subtle_border, 1)
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_y + 14)
      local prior_inner = UI.settings_inner_width
      UI.settings_inner_width = window_width - 28

      local source = Metering.resolve_binding(config)
      local project = state.active_project
      local master = project and R.GetMasterTrack(project)
      local monitoring_source = master and Metering.find_source_for_track(master, "monitoring")
      local monitoring_current = source and monitoring_source
        and source.key == monitoring_source.key

      UI.settings_note(state.setup_bind_face
        and "Choose once for this face. ReaClock will connect every meter and visualization card to the same source."
        or "Choose where ReaClock should listen. It verifies and repairs its companion automatically, then adds or reuses the meter.")
      R.ImGui_Dummy(ctx, 0, 4)
      local body_cursor_y = select(2, R.ImGui_GetCursorScreenPos(ctx))
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_cursor_y)

      if Metering.draw_source_choice("monitoring", {
          kind = "monitoring", title = "Entire mix",
          detail = "Monitoring FX · stays ready across projects and REAPER restarts",
          badge = monitoring_current and "CURRENT" or "RECOMMENDED",
          primary = true, current = monitoring_current,
        }) then
        local okay, detail = Metering.insert_monitoring(card_index)
        apply_result(okay, detail)
      end
      body_cursor_y = select(2, R.ImGui_GetCursorScreenPos(ctx))
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_cursor_y)
      local destination, kind, destination_error = Metering.selected_destination()
      local destination_number = destination and math.floor(
        R.GetMediaTrackInfo_Value(destination, "IP_TRACKNUMBER") or 0) or 0
      local destination_name = destination and (kind == "master" and "Master Track"
        or string.format("%d - %s", destination_number,
          Metering.track_name(destination, destination_number)))
      local destination_source = destination and Metering.find_source_for_track(destination, kind)
      local destination_current = source and destination_source
        and source.key == destination_source.key
      local destination_title = destination and (kind == "master" and "Selected master track"
        or "Selected track · " .. destination_number) or "Selected track"
      local destination_detail = destination and (destination_name
        .. " · post-FX, pre-fader in the active project")
        or destination_error or "Select one track in REAPER"
      if Metering.draw_source_choice("selected_track", {
          kind = "track", title = destination_title,
          detail = destination_detail,
          badge = destination_current and "CURRENT" or not destination and "NO TRACK SELECTED" or nil,
          disabled = not destination, current = destination_current,
        }) then
        local okay, detail = Metering.insert_on_track(card_index, destination, kind)
        apply_result(okay, detail)
      end

      if #other_sources > 0 then
        R.ImGui_Spacing(ctx)
        body_cursor_y = select(2, R.ImGui_GetCursorScreenPos(ctx))
        R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_cursor_y)
        R.ImGui_TextDisabled(ctx, "OTHER DETECTED METERS")
        body_cursor_y = select(2, R.ImGui_GetCursorScreenPos(ctx))
        R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_cursor_y)
        R.ImGui_SetNextItemWidth(ctx, UI.settings_inner_width)
        if R.ImGui_BeginCombo(ctx, "##meter_source_setup_existing",
            "Choose an existing meter…") then
          for _, candidate in ipairs(other_sources) do
            if R.ImGui_Selectable(ctx,
                candidate.display_name .. "##setup_source_" .. candidate.key, false) then
              apply_result(Metering.bind_card(card_index, candidate),
                "Using " .. candidate.display_name .. ".")
            end
          end
          R.ImGui_EndCombo(ctx)
        end
      end

      if state.setup_error then
        UI.settings_note(state.setup_error, C.danger)
      end
      body_cursor_y = select(2, R.ImGui_GetCursorScreenPos(ctx))
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_cursor_y)
      UI.settings_note("Audio passes through unchanged. You can switch sources from the card at any time.")
      local footer_y = body_y + body_height - 43
      R.ImGui_DrawList_AddLine(draw_list, origin_x + 14, footer_y - 7,
        origin_x + window_width - 14, footer_y - 7, palette.subtle_border, 1)
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, footer_y)
      if UI.settings_outline_button("SET UP LATER", "meter_setup_later", 110, 27) then
        close_dialog()
      end
      R.ImGui_SameLine(ctx, 0, 10)
      R.ImGui_AlignTextToFramePadding(ctx)
      UI.settings_note("The card stays ready to finish later.")
      UI.settings_inner_width = prior_inner
      R.ImGui_SetCursorScreenPos(ctx, origin_x, body_y + body_height)
      R.ImGui_Dummy(ctx, window_width, 0)
    end
    if R.ImGui_EndPopup then R.ImGui_EndPopup(ctx) end
  end
  if should_close then
    state.setup_request, state.setup_card = nil, nil
    state.setup_bind_face = false
    state.setup_close_request = false
  end
  R.ImGui_PopStyleColor(ctx, 7)
  R.ImGui_PopStyleVar(ctx, 6)
  pop_popup_style()
end

local function settings_heading(text)
  R.ImGui_PushFont(ctx, font_bold, 10)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), UI.settings_palette().label)
  R.ImGui_Text(ctx, text)
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
end

function UI.settings_label(text)
  R.ImGui_PushFont(ctx, font_regular, 12)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.secondary)
  R.ImGui_Text(ctx, text)
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
end

function UI.settings_info(title, detail)
  UI.settings_info_index = (UI.settings_info_index or 0) + 1
  local size = 14
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_InvisibleButton(ctx, "##settings_info_" .. UI.settings_info_index, size, size)
  local hovered = R.ImGui_IsItemHovered(ctx)
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local color = hovered and C.secondary or with_alpha(C.secondary, 145)
  if not draw_icon_centered(draw_list, ICON.CIRCLE_HELP,
      x, y, size, size, 13, color, 2) then
    local center_y = y + size * 0.5 + 2
    R.ImGui_DrawList_AddCircle(draw_list, x + size * 0.5, center_y,
      size * 0.43, color, 18, 1)
    R.ImGui_PushFont(ctx, font_bold, 9)
    local text_w, text_h = R.ImGui_CalcTextSize(ctx, "?")
    R.ImGui_DrawList_AddText(draw_list, x + (size - text_w) * 0.5,
      center_y - text_h * 0.5, color, "?")
    R.ImGui_PopFont(ctx)
  end
  item_tooltip(title, detail)
end

function UI.settings_section(title, description, tooltip_title)
  settings_heading(title:upper())
  if description and description ~= "" then
    R.ImGui_SameLine(ctx, 0, 6)
    UI.settings_info(tooltip_title or title, description)
  end
  R.ImGui_Dummy(ctx, 0, 4)
end

function UI.settings_gap(amount)
  -- settings_card's terminal zero-height item has already advanced by the
  -- current 5px ItemSpacing. Move only the remainder so a requested 12px gap
  -- is visually 12px rather than 5 + 12 + 5 = 22px.
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_SetCursorScreenPos(ctx, x,
    y + math.max(0, (amount or UI.settings_layout.card_gap) - 5))
end

function UI.draw_dashed_rect(draw_list, x1, y1, x2, y2, color, radius)
  local dash, gap = 6, 4
  local x = x1 + radius
  while x < x2 - radius do
    R.ImGui_DrawList_AddLine(draw_list, x, y1, math.min(x + dash, x2 - radius), y1, color, 1)
    R.ImGui_DrawList_AddLine(draw_list, x, y2, math.min(x + dash, x2 - radius), y2, color, 1)
    x = x + dash + gap
  end
  local y = y1 + radius
  while y < y2 - radius do
    R.ImGui_DrawList_AddLine(draw_list, x1, y, x1, math.min(y + dash, y2 - radius), color, 1)
    R.ImGui_DrawList_AddLine(draw_list, x2, y, x2, math.min(y + dash, y2 - radius), color, 1)
    y = y + dash + gap
  end
  R.ImGui_DrawList_AddLine(draw_list, x1, y1 + radius, x1 + radius, y1, color, 1)
  R.ImGui_DrawList_AddLine(draw_list, x2 - radius, y1, x2, y1 + radius, color, 1)
  R.ImGui_DrawList_AddLine(draw_list, x1, y2 - radius, x1 + radius, y2, color, 1)
  R.ImGui_DrawList_AddLine(draw_list, x2 - radius, y2, x2, y2 - radius, color, 1)
end

function UI.settings_card(id, height, draw, options)
  options = options or {}
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_column_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local palette = UI.settings_palette()
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local fill = options.transparent and 0x00000000 or (options.fill or palette.card)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, fill, 8)
  if options.dashed then
    UI.draw_dashed_rect(draw_list, x, y, x + width, y + height,
      with_alpha(options.border or palette.label, 115), 8)
  else
    R.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height,
      options.border or palette.subtle_border, 8, 0, 1)
  end

  local prior_inner = UI.settings_inner_width
  UI.settings_inner_width = width - 28
  R.ImGui_SetCursorScreenPos(ctx, x + 14, y + (options.compact and 10 or 12))
  R.ImGui_BeginGroup(ctx)
  draw(UI.settings_inner_width, height - (options.compact and 20 or 24))
  R.ImGui_EndGroup(ctx)
  UI.settings_inner_width = prior_inner
  R.ImGui_SetCursorScreenPos(ctx, x, y + height)
  R.ImGui_Dummy(ctx, width, 0)
end

function UI.settings_columns(id, left_draw, right_draw)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  -- The cursor already includes the left body inset. ImGui's remaining width
  -- still reaches the far window edge, so reserve the matching right inset
  -- explicitly before splitting into the two 410px mockup columns.
  local available = math.max(320,
    select(1, R.ImGui_GetContentRegionAvail(ctx)) - UI.settings_layout.body_padding)
  local gap = UI.settings_layout.column_gap
  local width = (available - gap) * 0.5

  local function draw_column(x, callback)
    R.ImGui_SetCursorScreenPos(ctx, x, start_y)
    R.ImGui_BeginGroup(ctx)
    local prior_width = UI.settings_column_width
    UI.settings_column_width = width
    callback(width)
    UI.settings_column_width = prior_width
    R.ImGui_Dummy(ctx, width, 0)
    R.ImGui_EndGroup(ctx)
    local _, bottom = R.ImGui_GetCursorScreenPos(ctx)
    return bottom
  end

  local left_bottom = draw_column(start_x, left_draw)
  local right_bottom = draw_column(start_x + width + gap, right_draw)
  local bottom = math.max(left_bottom, right_bottom)
  R.ImGui_SetCursorScreenPos(ctx, start_x, bottom)
  R.ImGui_Dummy(ctx, available, 0)
end

function UI.settings_row(label, label_width, draw_control, tooltip_title, tooltip_detail)
  label_width = label_width or 130
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_AlignTextToFramePadding(ctx)
  UI.settings_label(label)
  if tooltip_detail then
    R.ImGui_SameLine(ctx, 0, 5)
    UI.settings_info(tooltip_title or label, tooltip_detail)
  end
  R.ImGui_SetCursorScreenPos(ctx, start_x + label_width, start_y)
  draw_control(math.max(30, (UI.settings_inner_width or UI.settings_column_width or 260)
    - label_width))
end

function UI.settings_combo(label, key, options, width)
  local current_label = settings[key]
  for _, option in ipairs(options) do
    if option[1] == settings[key] then current_label = option[2] break end
  end
  UI.settings_row(label, 130, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, width or control_width)
    if R.ImGui_BeginCombo(ctx, "##" .. key, current_label) then
      for _, option in ipairs(options) do
        local selected = settings[key] == option[1]
        if R.ImGui_Selectable(ctx, option[2] .. "##" .. key .. option[1], selected) then
          settings[key] = option[1]
          save_string(key, option[1])
          recompute_snapshot(true)
        end
        if selected and R.ImGui_SetItemDefaultFocus then R.ImGui_SetItemDefaultFocus(ctx) end
      end
      R.ImGui_EndCombo(ctx)
    end
  end)
end

function UI.settings_outline_button(label, id, width, height, accent)
  local palette = UI.settings_palette()
  local border = accent and palette.label or with_alpha(C.secondary, 105)
  local text_color = accent and palette.label or C.secondary
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), 0x00000000)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), text_color)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), border)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), 1)
  R.ImGui_PushFont(ctx, font_bold, 10)
  local clicked = R.ImGui_Button(ctx, label .. "##" .. id, width or 120, height or 27)
  R.ImGui_PopFont(ctx)
  R.ImGui_PopStyleVar(ctx)
  R.ImGui_PopStyleColor(ctx, 5)
  return clicked
end

function UI.settings_text_link(label, id)
  R.ImGui_PushFont(ctx, font_regular, 10.5)
  local width, height = R.ImGui_CalcTextSize(ctx, label)
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local clicked = R.ImGui_InvisibleButton(ctx, "##settings_link_" .. id, width, height + 2)
  local hovered = R.ImGui_IsItemHovered(ctx)
  local color = hovered and C.accent_hover or UI.settings_palette().label
  R.ImGui_DrawList_AddText(R.ImGui_GetWindowDrawList(ctx), x, y, color, label)
  R.ImGui_DrawList_AddLine(R.ImGui_GetWindowDrawList(ctx), x, y + height,
    x + width, y + height, with_alpha(color, hovered and 210 or 130), 1)
  R.ImGui_PopFont(ctx)
  return clicked
end

function UI.settings_slider_row(label, id, value, minimum, maximum, display,
    on_change, label_width, tooltip_title, tooltip_detail)
  local changed_out, hovered_out = false, false
  UI.settings_row(label, label_width or 130, function(control_width)
    local value_width, gap = 46, 8
    R.ImGui_SetNextItemWidth(ctx, math.max(40, control_width - value_width - gap))
    local changed, next_value = R.ImGui_SliderDouble(ctx, "##" .. id,
      value, minimum, maximum, "")
    changed_out = changed
    hovered_out = R.ImGui_IsItemHovered(ctx)
    if changed then on_change(next_value) end
    R.ImGui_SameLine(ctx, 0, gap)
    R.ImGui_PushFont(ctx, font_mono, 10.5)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.secondary)
    R.ImGui_Text(ctx, display(changed and next_value or value))
    R.ImGui_PopStyleColor(ctx)
    R.ImGui_PopFont(ctx)
  end, tooltip_title, tooltip_detail)
  return changed_out, hovered_out
end

function UI.settings_status_row(label, detail, color, tooltip)
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_inner_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  R.ImGui_DrawList_AddCircleFilled(draw_list, x + 3.5, y + 9, 3.5, color)
  R.ImGui_PushFont(ctx, font_regular, 12)
  R.ImGui_DrawList_AddText(draw_list, x + 14, y + 1, C.ink, label)
  R.ImGui_PopFont(ctx)
  R.ImGui_PushFont(ctx, font_mono, 10)
  local detail_width = R.ImGui_CalcTextSize(ctx, detail)
  local available = math.max(40, width - 130)
  local shown = truncate_current_font(detail, available)
  local shown_width = R.ImGui_CalcTextSize(ctx, shown)
  R.ImGui_DrawList_AddText(draw_list, x + width - shown_width, y + 2, C.muted, shown)
  R.ImGui_PopFont(ctx)
  R.ImGui_InvisibleButton(ctx, "##settings_status_" .. tostring(label)
    .. tostring(UI.settings_info_index or 0), width, 19)
  if tooltip then item_tooltip(label, tooltip) end
end

function UI.settings_path_row(label, path)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_inner_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  R.ImGui_PushFont(ctx, font_bold, 10)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
  R.ImGui_Text(ctx, label:upper())
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
  R.ImGui_SetCursorScreenPos(ctx, start_x + 60, start_y)
  R.ImGui_PushFont(ctx, font_mono, 10)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
  local window_x = R.ImGui_GetWindowPos(ctx)
  R.ImGui_PushTextWrapPos(ctx, start_x - window_x + width)
  R.ImGui_Text(ctx, path)
  R.ImGui_PopTextWrapPos(ctx)
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
  item_tooltip(label .. " path", path)
end

function UI.settings_divider()
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_inner_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  R.ImGui_DrawList_AddLine(R.ImGui_GetWindowDrawList(ctx), x, y + 1,
    x + width, y + 1, UI.settings_palette().subtle_border, 1)
  R.ImGui_Dummy(ctx, width, 7)
end

function UI.settings_action_row(text_value, button_label, button_id, button_width,
    accent, on_click)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_inner_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local text_width = math.max(80, width - button_width - 14)
  UI.settings_note(text_value, nil, text_width)
  local _, text_bottom = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_SetCursorScreenPos(ctx, start_x + width - button_width, start_y)
  local clicked = UI.settings_outline_button(button_label, button_id,
    button_width, 27, accent)
  if clicked and on_click then on_click() end
  local _, button_bottom = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_SetCursorScreenPos(ctx, start_x, math.max(text_bottom, button_bottom))
  R.ImGui_Dummy(ctx, width, 0)
  return clicked
end

function UI.settings_confirm_action_row(text_value, confirm_label, confirm_id,
    confirm_width, cancel_label, cancel_id, cancel_width, on_confirm, on_cancel)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_inner_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local gap = 6
  local actions_width = confirm_width + gap + cancel_width
  UI.settings_note(text_value, C.danger,
    math.max(80, width - actions_width - 14))
  local _, text_bottom = R.ImGui_GetCursorScreenPos(ctx)
  -- Balance the actions against multiline warnings instead of pinning them to
  -- the first line. ImGui advances the cursor by the 5px item spacing after
  -- Text(), so exclude that spacing when finding the rendered text midpoint.
  local text_height = math.max(0, text_bottom - start_y - 5)
  local button_y = start_y + math.max(0, (text_height - 27) * 0.5)
  R.ImGui_SetCursorScreenPos(ctx, start_x + width - actions_width, button_y)
  if UI.settings_outline_button(confirm_label, confirm_id,
      confirm_width, 27, true) and on_confirm then
    on_confirm()
  end
  R.ImGui_SameLine(ctx, 0, gap)
  if UI.settings_outline_button(cancel_label, cancel_id,
      cancel_width, 27) and on_cancel then
    on_cancel()
  end
  local _, button_bottom = R.ImGui_GetCursorScreenPos(ctx)
  R.ImGui_SetCursorScreenPos(ctx, start_x, math.max(text_bottom, button_bottom))
  R.ImGui_Dummy(ctx, width, 0)
end

function UI.settings_segmented(id, options, selected, on_select, button_width, height)
  button_width = button_width or 72
  height = height or 27
  local padding, gap = 3, 2
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local total_width = padding * 2 + (#options - 1) * gap
  for _, option in ipairs(options) do
    total_width = total_width + (option[3] or button_width)
  end
  local total_height = height + padding * 2
  local palette = UI.settings_palette()
  R.ImGui_DrawList_AddRectFilled(R.ImGui_GetWindowDrawList(ctx), x, y,
    x + total_width, y + total_height, palette.segment, 7)
  R.ImGui_SetCursorScreenPos(ctx, x + padding, y + padding)
  for index, option in ipairs(options) do
    local value, label = option[1], option[2]
    local option_width = option[3] or button_width
    local enabled = option[4] ~= false
    local active = selected == value
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), active and palette.selected or 0x00000000)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(),
      active and palette.selected or C.inactive_hover)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), active and C.ink or C.muted)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(),
      active and palette.selected_border or 0x00000000)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), active and 1 or 0)
    R.ImGui_PushFont(ctx, active and font_bold or font_regular, 10.5)
    if not enabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
    if R.ImGui_Button(ctx, label .. "##segmented_" .. id .. "_" .. value,
        option_width, height) and enabled then on_select(value) end
    if not enabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
    if option[5] then item_tooltip(option[5], option[6] or "") end
    R.ImGui_PopFont(ctx)
    R.ImGui_PopStyleVar(ctx)
    R.ImGui_PopStyleColor(ctx, 5)
    if index < #options then R.ImGui_SameLine(ctx, 0, gap) end
  end
  R.ImGui_SetCursorScreenPos(ctx, x, y + total_height)
  R.ImGui_Dummy(ctx, total_width, 0)
  return total_width, total_height
end

function UI.settings_alignment_control(id, selected, default_alignment, on_select)
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local button_width, height, padding, gap = 48, 27, 3, 2
  local total_width = button_width * 3 + gap * 2 + padding * 2
  local total_height = height + padding * 2
  local palette = UI.settings_palette()
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y,
    x + total_width, y + total_height, palette.segment, 7)

  for index, alignment in ipairs({ "left", "center", "right" }) do
    local button_x = x + padding + (index - 1) * (button_width + gap)
    local button_y = y + padding
    R.ImGui_SetCursorScreenPos(ctx, button_x, button_y)
    local active = selected == alignment
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(),
      active and palette.selected or 0x00000000)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(),
      active and palette.selected or C.inactive_hover)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(),
      active and palette.selected_border or 0x00000000)
    R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameBorderSize(), active and 1 or 0)
    if R.ImGui_Button(ctx, "##alignment_" .. id .. "_" .. alignment,
        button_width, height) then on_select(alignment) end
    R.ImGui_PopStyleVar(ctx)
    R.ImGui_PopStyleColor(ctx, 4)

    local line_color = active and C.ink or C.muted
    local line_widths = { 18, 12, 16 }
    for line_index, line_width in ipairs(line_widths) do
      local line_x = button_x + 10
      if alignment == "center" then
        line_x = button_x + (button_width - line_width) * 0.5
      elseif alignment == "right" then
        line_x = button_x + button_width - 10 - line_width
      end
      local line_y = button_y + 8 + (line_index - 1) * 5
      R.ImGui_DrawList_AddLine(draw_list, line_x, line_y,
        line_x + line_width, line_y, line_color, 1.5)
    end
    local label = alignment:gsub("^%l", string.upper)
    if alignment == default_alignment then label = label .. " (Default)" end
    item_tooltip(label, "Align this card's value " .. alignment .. ".")
  end

  R.ImGui_SetCursorScreenPos(ctx, x, y + total_height)
  R.ImGui_Dummy(ctx, total_width, 0)
  return total_width, total_height
end

function Content.card_index_from_prefix(prefix)
  local main = tostring(prefix):match("^card_(%d+)$")
  if main then return tonumber(main) end
  local detached = tostring(prefix):match("^detached_(%d+)$")
  return detached and -tonumber(detached) or nil
end

function Content.save_field(config, prefix, field, value)
  if not config then return end
  config[field] = value
  if Runtime.metering and Runtime.metering.visual then
    Runtime.metering.visual.compile_dirty = true
  end
  local detached_id = tostring(prefix):match("^detached_(%d+)$")
  if detached_id then
    Content.save_card(-tonumber(detached_id))
  else
    save_string(prefix .. "_" .. field, value)
    if Content.save_active_face then Content.save_active_face() end
  end
  recompute_snapshot(true)
end

function Content.reset_config(config, prefix, defaults)
  local detached_id = tostring(prefix):match("^detached_(%d+)$")
  local function persist_string(key, value)
    if not detached_id then save_string(key, value) end
  end
  local function persist_bool(key, value)
    if not detached_id then save_bool(key, value) end
  end
  config.type, config.label = defaults.type, defaults.label
  config.template, config.font = defaults.template, defaults.font
  config.scroll = defaults.scroll == true
  config.show_title = defaults.show_title ~= false
  config.align = defaults.align or "default"
  config.span = normalize_card_span(defaults.span)
  for _, field in ipairs({ "type", "label", "template", "font", "align", "span" }) do
    persist_string(prefix .. "_" .. field, config[field])
  end
  persist_bool(prefix .. "_scroll", config.scroll)
  persist_bool(prefix .. "_show_title", config.show_title)
  for _, field in ipairs(METER_CARD_FIELDS) do
    local value = normalize_meter_field(field, defaults[field.key])
    config[field.key] = value
    if field.kind == "boolean" then
      persist_bool(prefix .. "_" .. field.key, value)
    else
      persist_string(prefix .. "_" .. field.key, value)
    end
  end
  for _, field in ipairs(Runtime.action_card_fields) do
    local value = Runtime.normalize_action_field(defaults[field.key], field.default)
    config[field.key] = value
    persist_string(prefix .. "_" .. field.key, value)
  end
  if detached_id then
    Content.save_card(-tonumber(detached_id))
  elseif Content.save_active_face then
    Content.save_active_face()
  end
end

function Content.reset_cards()
  settings.card_rows = 3
  save_string("card_rows", settings.card_rows)
  local default_counts = { 1, 4, 2, 1 }
  local default_sizes = { "large", "medium", "medium", "medium" }
  for row = 1, MAX_CARD_ROWS do
    settings.card_row_counts[row] = default_counts[row]
    settings.card_row_sizes[row] = default_sizes[row]
    save_string("card_row" .. row .. "_count", default_counts[row])
    save_string("card_row" .. row .. "_size", default_sizes[row])
  end
  for index, defaults in ipairs(CARD_DEFAULTS) do
    Content.reset_config(settings.cards[index], "card_" .. index, defaults)
  end
  edit_selected_row, edit_selected_card = 1, 1
  request_layout_resize()
  recompute_snapshot(true)
end

function Content.draw_template_token_picker(config, prefix)
  local popup_id = "template_tokens_" .. prefix
  UI.settings_action_row(
    "Add a live clock, region, marker, audio, or project value.",
    "INSERT TOKEN…", "insert_token_" .. prefix, 116, true,
    function() R.ImGui_OpenPopup(ctx, popup_id) end)

  push_popup_style()
  Content.constrain_next_popup_height()
  if R.ImGui_BeginPopup(ctx, popup_id) then
    R.ImGui_PushFont(ctx, font_regular, 12)
    Content.draw_popup_heading("INSERT TOKEN")
    R.ImGui_Separator(ctx)
    local function draw_tokens(tokens)
      for _, token in ipairs(tokens) do
        local menu_label = string.format("{%s}   %s##%s_%s",
          token.id, token.label, prefix, token.id)
        if R.ImGui_MenuItem(ctx, menu_label) then
          local template = tostring(config.template or "")
          local separator = template ~= "" and not template:match("%s$") and " " or ""
          Content.save_field(config, prefix, "template",
            template .. separator .. "{" .. token.id .. "}")
        end
      end
    end
    for _, group in ipairs(TEMPLATE_TOKEN_GROUPS) do
      if R.ImGui_BeginMenu(ctx, group.label) then
        draw_tokens(group.tokens)
        for _, section in ipairs(group.sections or {}) do
          if R.ImGui_BeginMenu(ctx, section.label) then
            draw_tokens(section.tokens)
            R.ImGui_EndMenu(ctx)
          end
        end
        R.ImGui_EndMenu(ctx)
      end
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.draw_editor_summary(config, prefix)
  local card_index = Content.card_index_from_prefix(prefix)
  local resolved = card_index and snapshot.cards[card_index]
  local type_label = CARD_TYPE_BY_ID[config.type]
    and CARD_TYPE_BY_ID[config.type].label or config.type
  local preview_label = resolved and resolved.label or config.label or ""
  local preview_value = resolved and resolved.value or ""
  local preview = preview_label
  if preview_value:find("%S") then
    preview = preview ~= "" and (preview .. "  ·  " .. preview_value) or preview_value
  end
  if preview == "" then preview = "No value at the current project position" end
  local preview_alignment_id = config.align or "default"
  if preview_alignment_id == "default" then
    preview_alignment_id = settings.card_alignment
  end
  local preview_alignment = preview_alignment_id == "center" and 0.5
    or (preview_alignment_id == "right" and 1 or 0)

  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local available_width = select(1, R.ImGui_GetContentRegionAvail(ctx))
  local window_x = select(1, R.ImGui_GetWindowPos(ctx))
  local window_width = select(1, R.ImGui_GetWindowSize(ctx))
  local visible_width = math.max(260, window_x + window_width - x - 20)
  local width = math.max(260, UI.settings_column_width
    or math.min(available_width, visible_width))
  local height = 76
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  R.ImGui_InvisibleButton(ctx, "##editor_summary_" .. prefix, width, height)
  local hovered = R.ImGui_IsItemHovered(ctx)
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  local palette = UI.settings_palette()
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height,
    hovered and C.inactive_hover or palette.card, 8)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + 4, y + height,
    C.accent, 8)
  R.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height,
    palette.subtle_border, 8)
  draw_text_box(draw_list, font_bold, type_label:upper(), x + 16, y + 9,
    width * 0.55, 16, 11, C.muted, 0, "ellipsis")
  draw_text_box(draw_list, font_bold, "PREVIEW", x + width - 92, y + 9,
    76, 16, 10, C.accent_secondary_text, 1, "ellipsis")
  draw_text_box(draw_list, font_regular, preview, x + 16, y + 31,
    width - 32, 32, 20, C.ink, preview_alignment, "ellipsis")
  if hovered then
    draw_styled_tooltip("Live card preview",
      "Shows the label and value ReaClock currently resolves from this card.")
  end
end

local function draw_editor_section(title, detail)
  R.ImGui_Spacing(ctx)
  R.ImGui_PushFont(ctx, font_bold, 12)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.accent_secondary_text)
  R.ImGui_Text(ctx, title:upper())
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)
  if detail and detail ~= "" then
    R.ImGui_SameLine(ctx)
    R.ImGui_TextDisabled(ctx, detail)
  end
end

function Content.editor_scrollable(config, prefix)
  local card_index = Content.card_index_from_prefix(prefix)
  local resolved = card_index and snapshot.cards[card_index]
  return resolved and (resolved.fit_mode == "ellipsis" or resolved.fit_mode == "scroll")
end

function Content.draw_editor_combo_row(config, prefix, field, label, options,
    tooltip_title, tooltip_detail)
  local current_label = tostring(config[field] or "")
  for _, option in ipairs(options) do
    if option[1] == config[field] then current_label = option[2] break end
  end
  UI.settings_row(label, 94, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, control_width)
    if R.ImGui_BeginCombo(ctx, "##dialog_" .. prefix .. "_" .. field, current_label) then
      for _, option in ipairs(options) do
        local selected = config[field] == option[1]
        if R.ImGui_Selectable(ctx, option[2] .. "##dialog_" .. prefix .. "_"
            .. field .. "_" .. tostring(option[1]), selected) then
          Content.save_field(config, prefix, field, option[1])
        end
        if selected and R.ImGui_SetItemDefaultFocus then R.ImGui_SetItemDefaultFocus(ctx) end
      end
      R.ImGui_EndCombo(ctx)
    end
    item_tooltip(tooltip_title or label, tooltip_detail or "")
  end)
end

function Content.type_picker_entries()
  local entries = {}
  local function add(group, label, content_type, meter_preset, search_detail)
    entries[#entries + 1] = {
      group = group,
      label = label,
      content_type = content_type,
      meter_preset = meter_preset,
      search = table.concat({ group or "", label or "", content_type or "",
        search_detail or "" }, " "):lower(),
    }
  end

  add("General", "None", "none", nil, CARD_TYPE_DESCRIPTIONS.none)
  for _, group in ipairs(CARD_GROUPS) do
    if group.id == "metering" then
      for _, meter_group in ipairs(Metering.numeric_menus) do
        for _, item in ipairs(meter_group.items) do
          add(group.label, meter_group.label .. " · " .. item[1], "meter",
            { meter_display = "numeric", meter_metric = item[2] }, item[2])
        end
      end
    elseif group.id == "visualizations" then
      for _, item in ipairs(Metering.visual_menus) do
        add(group.label, item[1], "meter", { meter_display = item[2] }, item[2])
      end
    else
      for _, candidate in ipairs(CARD_TYPE_OPTIONS) do
        if candidate.group == group.id then
          local section_label = ""
          for _, section in ipairs(group.sections or {}) do
            if section.id == candidate.section then section_label = section.label break end
          end
          add(group.label, candidate.label, candidate.id, nil,
            section_label .. " " .. (CARD_TYPE_DESCRIPTIONS[candidate.id] or ""))
        end
      end
    end
  end
  add("Actions", CARD_TYPE_BY_ID.action.label, "action", nil,
    CARD_TYPE_DESCRIPTIONS.action)
  add("Custom", CARD_TYPE_BY_ID.custom.label, "custom", nil,
    CARD_TYPE_DESCRIPTIONS.custom)
  return entries
end

function Content.type_picker_entry_selected(entry, config)
  if entry.content_type ~= config.type then return false end
  if entry.content_type ~= "meter" then return true end
  local preset = entry.meter_preset or {}
  if preset.meter_display ~= config.meter_display then return false end
  return preset.meter_display ~= "numeric"
    or preset.meter_metric == config.meter_metric
end

function Content.type_picker_label(config, entries)
  for _, entry in ipairs(entries) do
    if Content.type_picker_entry_selected(entry, config) then return entry.label end
  end
  local option = CARD_TYPE_BY_ID[config.type]
  return option and option.label or tostring(config.type or "None")
end

function Content.draw_editor_content_card(config, prefix, card_index)
  local entries = Content.type_picker_entries()
  local type_label = Content.type_picker_label(config, entries)
  Runtime.content_type_searches = Runtime.content_type_searches or {}
  local search = Runtime.content_type_searches[prefix]
  if not search then
    search = { text = "" }
    Runtime.content_type_searches[prefix] = search
  end

  UI.settings_card("dialog_content", 82, function()
    UI.settings_section("Content", "What this card displays")
    UI.settings_row("Type", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      if R.ImGui_BeginCombo(ctx, "##dialog_" .. prefix .. "_type", type_label) then
        if R.ImGui_IsWindowAppearing and R.ImGui_IsWindowAppearing(ctx) then
          search.text = ""
          if R.ImGui_SetKeyboardFocusHere then R.ImGui_SetKeyboardFocusHere(ctx) end
        end
        R.ImGui_SetNextItemWidth(ctx, -1)
        local changed, search_text = R.ImGui_InputTextWithHint(ctx,
          "##dialog_" .. prefix .. "_type_search",
          "Search all content types…", search.text)
        if changed then search.text = search_text end
        R.ImGui_Separator(ctx)
        local query = search.text:lower():match("^%s*(.-)%s*$") or ""
        local any, prior_group = false, nil
        for _, entry in ipairs(entries) do
          local matches = query == "" or entry.search:find(query, 1, true) ~= nil
          if matches then
            any = true
            if prior_group ~= entry.group then
              if prior_group then R.ImGui_Separator(ctx) end
              R.ImGui_PushFont(ctx, font_bold, 10)
              R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(),
                Content.settings_surface_palette().label)
              R.ImGui_Text(ctx, entry.group:upper())
              R.ImGui_PopStyleColor(ctx)
              R.ImGui_PopFont(ctx)
              prior_group = entry.group
            end
            local selected = Content.type_picker_entry_selected(entry, config)
            local item_id = entry.content_type
              .. (entry.meter_preset and ("_" .. entry.meter_preset.meter_display
                .. "_" .. tostring(entry.meter_preset.meter_metric or "")) or "")
            if R.ImGui_Selectable(ctx, entry.label .. "##dialog_" .. prefix
                .. "_type_result_" .. item_id, selected) then
              search.text = ""
              Content.set_card_type(card_index, entry.content_type, true,
                entry.meter_preset)
            end
            if selected and query == "" and R.ImGui_SetItemDefaultFocus then
              R.ImGui_SetItemDefaultFocus(ctx)
            end
          end
        end
        if not any then
          R.ImGui_TextDisabled(ctx, "No content types match “" .. search.text .. "”.")
        end
        R.ImGui_EndCombo(ctx)
      end
      item_tooltip("Card content", CARD_TYPE_DESCRIPTIONS[config.type]
        or "Choose the live value this card displays.")
    end)
  end)
end

function Content.draw_editor_action_card(config, prefix)
  local resolved, resolve_error = Content.actions.resolve(config.action_command)
  local toggle_state
  if resolved then toggle_state = Content.actions.toggle_state(resolved.command) end
  Content.actions.searches[prefix] = Content.actions.searches[prefix] or { text = "" }
  local search = Content.actions.searches[prefix]

  UI.settings_card("dialog_action_button", 176, function()
    UI.settings_section("Action Button",
      "Run an installed REAPER Main-section action or script")
    UI.settings_row("Action ID", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, value = R.ImGui_InputTextWithHint(ctx,
        "##dialog_" .. prefix .. "_action_command", "40044 or _RS…",
        config.action_command)
      if changed then Content.actions.bind(config, prefix, value, "") end
      item_tooltip("Action ID",
        "Paste a numeric command ID or named command ID from REAPER's Main Action List.")
    end)

    UI.settings_row("Find action", 94, function(control_width)
      local preview = resolved and resolved.name or "Search installed actions…"
      R.ImGui_SetNextItemWidth(ctx, control_width)
      Content.constrain_next_popup_height()
      if R.ImGui_BeginCombo(ctx, "##dialog_" .. prefix .. "_action_search", preview) then
        if R.ImGui_IsWindowAppearing and R.ImGui_IsWindowAppearing(ctx) then
          search.text = ""
          if R.ImGui_SetKeyboardFocusHere then R.ImGui_SetKeyboardFocusHere(ctx) end
        end
        R.ImGui_SetNextItemWidth(ctx, -1)
        local changed, search_text = R.ImGui_InputTextWithHint(ctx,
          "##dialog_" .. prefix .. "_action_search_text",
          "Search actions and scripts…", search.text)
        if changed then search.text = search_text end
        R.ImGui_Separator(ctx)
        local results, total = Content.actions.search(search.text, 80)
        if search.text:match("%S") then
          for _, item in ipairs(results) do
            local selected = resolved and resolved.command == item.command
            local label = item.name .. "   [" .. item.identifier .. "]##dialog_"
              .. prefix .. "_action_result_" .. tostring(item.command)
            if R.ImGui_Selectable(ctx, label, selected) then
              Content.actions.bind(config, prefix, item.identifier, item.name)
              search.text = ""
            end
            if selected and R.ImGui_SetItemDefaultFocus then
              R.ImGui_SetItemDefaultFocus(ctx)
            end
          end
          if total == 0 then
            R.ImGui_TextDisabled(ctx, "No installed Main-section actions match this search.")
          elseif total > #results then
            R.ImGui_TextDisabled(ctx,
              string.format("Showing %d of %d matches. Keep typing to narrow the list.",
                #results, total))
          end
        else
          R.ImGui_TextDisabled(ctx, "Type part of an action or script name.")
        end
        R.ImGui_Separator(ctx)
        if R.ImGui_MenuItem(ctx, "Refresh installed actions##dialog_" .. prefix
            .. "_action_refresh") then
          Content.actions.ensure_catalog(true)
        end
        R.ImGui_EndCombo(ctx)
      end
      item_tooltip("Find action",
        "Searches every native action, custom action, extension action, and script installed in REAPER's Main section.")
    end)

    UI.settings_row("Button text", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, value = R.ImGui_InputTextWithHint(ctx,
        "##dialog_" .. prefix .. "_action_text",
        resolved and resolved.name or "Use the action name", config.action_text)
      if changed then Content.save_field(config, prefix, "action_text", value) end
      item_tooltip("Button text",
        "Leave this blank to show REAPER's current action name automatically.")
    end)

    if toggle_state ~= nil then
      UI.settings_note((toggle_state and "On · " or "Off · ") .. resolved.name,
        toggle_state and C.accent_secondary_text or C.muted)
    elseif resolved then
      UI.settings_note("Ready · " .. resolved.name, C.accent_secondary_text)
    else
      UI.settings_note(resolve_error or "Choose an action before using this button.", C.muted)
    end
  end)
end

function Content.draw_editor_row_height_row(card_index, prefix)
  local row = math.floor((card_index - 1) / CARDS_PER_ROW) + 1
  local current = settings.card_row_sizes[row]
  UI.settings_row("Height", 94, function(control_width)
    local compact = control_width < 300
    local options = compact and {
      { "small", "S", 34, true, "Small" },
      { "medium", "M", 34, true, "Medium" },
      { "large", "L", 34, true, "Large" },
      { "huge", "XL", 36, true, "Huge" },
      { "visualizer", "Viz", 42, true, "Visualizer" },
    } or {
      { "small", "Small", 46 },
      { "medium", "Medium", 60 },
      { "large", "Large", 48 },
      { "huge", "Huge", 46 },
      { "visualizer", "Visualizer", 72 },
    }
    UI.settings_segmented("dialog_" .. prefix .. "_row_height", options,
      current, function(option_id) Content.set_row_size(row, option_id) end)
  end)
end

function Content.draw_editor_span_row(config, prefix, card_index)
  UI.settings_row("Width", 94, function(control_width)
    local maximum = Content.max_card_span(card_index)
    local auto_width = control_width < 300 and 42 or 48
    local number_width = math.max(24,
      math.min(36, math.floor((control_width - auto_width - 18) / CARDS_PER_ROW)))
    local options = { { "auto", "Auto", auto_width, true,
      "Auto width", "Shares the row space left after fixed-width cards." } }
    for units = 1, CARDS_PER_ROW do
      options[#options + 1] = {
        tostring(units), tostring(units), number_width, units <= maximum,
        units .. " of 6", "Reserve " .. units .. " of the row's six width units.",
      }
    end
    UI.settings_segmented("dialog_" .. prefix .. "_span", options,
      config.span or "auto", function(value) Content.set_card_span(card_index, value) end)
  end)
end

function Content.draw_editor_text_card(config, prefix)
  UI.settings_card("dialog_text", 161, function()
    UI.settings_section("Text", "Label, template, and live token values")
    UI.settings_row("Label", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, value = R.ImGui_InputTextWithHint(ctx,
        "##dialog_" .. prefix .. "_label", "CUSTOM", config.label)
      if changed then Content.save_field(config, prefix, "label", value) end
      item_tooltip("Card label", "Short text shown above the card's resolved value.")
    end)
    UI.settings_row("Template", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, value = R.ImGui_InputTextWithHint(ctx,
        "##dialog_" .. prefix .. "_template", "{region} · {remaining}", config.template)
      if changed then Content.save_field(config, prefix, "template", value) end
      item_tooltip("Value template",
        "Combine plain text with live values such as {region}, {remaining}, or {tempo}.")
    end)
    R.ImGui_Dummy(ctx, 0, 1)
    Content.draw_template_token_picker(config, prefix)
    UI.settings_note("Unknown token names stay visible on the card, so typos remain easy to find.")
  end)
end

function Content.draw_editor_display_card(config, prefix, card_index)
  local scrollable = Content.editor_scrollable(config, prefix)
  UI.settings_card("dialog_display", scrollable and 243 or 216, function()
    UI.settings_section("Display", "How the value is rendered")
    Content.draw_editor_combo_row(config, prefix, "font", "Value font", {
      { "auto", "Auto for content" }, { "regular", "Regular text" },
      { "mono", "Numeric / mono" },
    }, "Value font", "Let ReaClock choose automatically, or force regular text or numeric mono.")
    if card_index and card_index > 0 then
      Content.draw_editor_row_height_row(card_index, prefix)
      Content.draw_editor_span_row(config, prefix, card_index)
    else
      UI.settings_row("Window", 94, function()
        R.ImGui_TextDisabled(ctx, "Resize the pop-out window directly")
      end)
    end

    local alignment = config.align or "default"
    local effective_alignment = alignment == "default" and settings.card_alignment or alignment
    UI.settings_row("Alignment", 94, function()
      UI.settings_alignment_control("dialog_" .. prefix, effective_alignment,
        settings.card_alignment, function(value)
          Content.save_field(config, prefix, "align",
            value == settings.card_alignment and "default" or value)
        end)
    end)

    settings_checkbox("Show card title", prefix .. "_show_title", config.show_title ~= false,
      function(value)
        Content.save_field(config, prefix, "show_title", value)
      end)

    if scrollable then
      settings_checkbox("Auto-scroll long text", prefix .. "_scroll", config.scroll == true,
        function(value)
          Content.save_field(config, prefix, "scroll", value)
        end)
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Auto-scroll long text",
        "Moves only overflowing regular text; numeric and mono values remain stable.")
    end
  end)
end

function Content.draw_editor_reset_card(config, prefix, defaults)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  local width = UI.settings_column_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  if not detail_editor.reset_armed then
    local button_width = 104
    R.ImGui_SetCursorScreenPos(ctx, start_x + width - button_width, start_y)
    if UI.settings_outline_button(
        "RESET CARD…", "dialog_reset_card", button_width, 27, true) then
      detail_editor.reset_armed = true
    end
  else
    local confirm_width, cancel_width, gap = 112, 64, 6
    R.ImGui_SetCursorScreenPos(ctx,
      start_x + width - confirm_width - cancel_width - gap, start_y)
    if UI.settings_outline_button(
        "CONFIRM RESET", "dialog_confirm_reset", confirm_width, 27, true) then
      Content.reset_config(config, prefix, defaults)
      recompute_snapshot(true)
      detail_editor.reset_armed = false
    end
    R.ImGui_SameLine(ctx, 0, gap)
    if UI.settings_outline_button("CANCEL", "dialog_cancel_reset", cancel_width, 27) then
      detail_editor.reset_armed = false
    end
  end
  R.ImGui_SetCursorScreenPos(ctx, start_x, start_y + 27)
  R.ImGui_Dummy(ctx, width, 0)
end

function Metering.draw_compact_channel_rows(config, prefix, pair_only)
  local options = pair_only
    and { { "auto", "Auto pair" }, { "pair", "Exact channel pair" } }
    or { { "auto", "Auto" }, { "mono", "One channel" },
      { "pair", "Channel pair" }, { "all", "All channels" } }
  Content.draw_editor_combo_row(config, prefix, "meter_channel_mode",
    "Channels", options, "Channel view",
    "Choose automatic routing, one channel, a pair, or every channel exposed by the source.")
  if config.meter_channel_mode == "mono" or config.meter_channel_mode == "pair" then
    UI.settings_row("First", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, channel = R.ImGui_InputInt(ctx,
        "##dialog_" .. prefix .. "_meter_channel_a", config.meter_channel_a, 1, 2)
      if changed then
        Content.save_field(config, prefix, "meter_channel_a",
          math.max(1, math.min(64, channel)))
      end
    end)
  end
  if config.meter_channel_mode == "pair" then
    UI.settings_row("Second", 94, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local changed, channel = R.ImGui_InputInt(ctx,
        "##dialog_" .. prefix .. "_meter_channel_b", config.meter_channel_b, 1, 2)
      if changed then
        Content.save_field(config, prefix, "meter_channel_b",
          math.max(1, math.min(64, channel)))
      end
    end)
  end
end

function Metering.draw_compact_slider_row(config, prefix, field, label,
    minimum, maximum, format, tooltip)
  UI.settings_row(label, 94, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, control_width)
    local changed, value = R.ImGui_SliderDouble(ctx,
      "##dialog_" .. prefix .. "_" .. field, config[field], minimum, maximum, format)
    if changed then Content.save_field(config, prefix, field, value) end
    if tooltip then item_tooltip(label, tooltip) end
  end)
end

function Metering.draw_compact_metric_row(config, prefix)
  local groups = {
    { "CURRENT / SESSION", {
      { "lufs_i", "Integrated Loudness (LUFS-I)" },
      { "lufs_s", "Short-term Loudness (LUFS-S)" },
      { "lufs_m", "Momentary Loudness (LUFS-M)" },
      { "lra", "Loudness Range (LRA)" },
      { "rms_m", "Momentary RMS (RMS-M)" },
      { "rms_i", "Integrated RMS (RMS-I)" },
      { "sample_peak", "Sample Peak" }, { "true_peak", "True Peak" },
    } },
    { "MAXIMUM SINCE RESET", {
      { "lufs_i_max", "Integrated Loudness Maximum" },
      { "lufs_s_max", "Short-term Loudness Maximum" },
      { "lufs_m_max", "Momentary Loudness Maximum" },
      { "lra_max", "Loudness Range Maximum" },
      { "rms_m_max", "Momentary RMS Maximum" },
      { "rms_i_max", "Integrated RMS Maximum" },
      { "sample_peak_max", "Sample Peak Maximum" },
      { "true_peak_max", "True Peak Maximum" },
    } },
  }
  local definition = Metering.metrics[config.meter_metric] or Metering.metrics.lufs_i
  UI.settings_row("Reading", 94, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, control_width)
    if R.ImGui_BeginCombo(ctx, "##dialog_" .. prefix .. "_meter_metric", definition.label) then
      for _, group in ipairs(groups) do
        R.ImGui_TextDisabled(ctx, group[1])
        for _, option in ipairs(group[2]) do
          local selected = config.meter_metric == option[1]
          if R.ImGui_Selectable(ctx,
              option[2] .. "##dialog_" .. prefix .. "_metric_" .. option[1], selected) then
            Content.save_field(config, prefix, "meter_metric", option[1])
          end
        end
        R.ImGui_Separator(ctx)
      end
      R.ImGui_EndCombo(ctx)
    end
    item_tooltip("Numeric reading",
      "Current and maximum readings cover the active meter reset epoch.")
  end)
end

function Metering.compact_display_height(config)
  local display = config.meter_display
  local heights = {
    numeric = 104, levels = 220, history = 150, waveform = 210,
    spectrum = 258, spectrogram = 425, vectorscope = 210, correlation = 184,
  }
  local height = heights[display] or 220
  if display ~= "numeric" and (config.meter_channel_mode == "mono"
      or config.meter_channel_mode == "pair") then height = height + 27 end
  if display ~= "numeric" and config.meter_channel_mode == "pair" then height = height + 27 end
  return height
end

function Metering.draw_compact_profile_note(config, card_index)
  local source = Metering.resolve_binding(config)
  local uses_profile = config.meter_display ~= "numeric"
    and config.meter_display ~= "history"
    and not (config.meter_display == "correlation" and config.meter_channel_mode ~= "pair")
  if not source or not uses_profile then return end
  local visual = Runtime.metering.visual
  local budget = visual.profile_budget and visual.profile_budget[source.key]
  local used = budget and budget.used or 0
  local limit = budget and budget.limit or Metering.Visual.profile_limit
  local requested = budget and budget.requested or used
  UI.settings_note(string.format("Visual views: %d of %d in use%s.", used, limit,
    requested > limit and string.format("; %d requested", requested) or ""),
    requested > limit and C.danger or C.accent_secondary_text)
  local card_stream = visual.card_streams and visual.card_streams[card_index]
  if card_stream and card_stream.error_code == "source_profile_limit" then
    UI.settings_note(card_stream.error_detail, C.danger)
  end
end

function Metering.draw_compact_display_card(config, prefix, card_index)
  UI.settings_card("dialog_meter_display", Metering.compact_display_height(config), function()
    UI.settings_section("Meter view",
      "Measurement, channels, and only the controls that materially change this view")
    Content.draw_editor_combo_row(config, prefix, "meter_display", "Card view", {
      { "numeric", "Numeric reading" }, { "levels", "Level meters" },
      { "history", "Loudness history" }, { "waveform", "Waveform" },
      { "spectrum", "Spectrum analyzer" }, { "spectrogram", "Spectrogram" },
      { "vectorscope", "Vectorscope" }, { "correlation", "Phase correlation" },
    }, "Card display", "Choose a precise reading or one shared live visual stream.")

    local display = config.meter_display
    if display == "numeric" then
      Metering.draw_compact_metric_row(config, prefix)
    elseif display == "levels" then
      Metering.draw_compact_channel_rows(config, prefix, false)
      Content.draw_editor_combo_row(config, prefix, "meter_level_floor", "Meter floor", {
        { -36, "-36 dBFS" }, { -48, "-48 dBFS" }, { -60, "-60 dBFS" },
        { -72, "-72 dBFS" }, { -90, "-90 dBFS" },
      })
      settings_checkbox("Show per-channel maxima", prefix .. "_level_peak_max",
        config.meter_level_peak_max, function(value)
          Content.save_field(config, prefix, "meter_level_peak_max", value)
        end)
      settings_checkbox("Show aggregate True Peak", prefix .. "_level_true_peak",
        config.meter_level_true_peak_marker, function(value)
          Content.save_field(config, prefix, "meter_level_true_peak_marker", value)
        end)
    elseif display == "history" then
      Content.draw_editor_combo_row(config, prefix, "meter_history_seconds", "History", {
        { 30, "30 seconds" }, { 60, "1 minute" }, { 180, "3 minutes" },
        { 7200, "Current reset epoch" },
      })
      R.ImGui_AlignTextToFramePadding(ctx)
      UI.settings_label("Traces")
      R.ImGui_SameLine(ctx, 0, 16)
      local traces = "," .. tostring(config.meter_history_traces or "") .. ","
      for index, trace in ipairs({ { "m", "M" }, { "s", "S" }, { "i", "I" } }) do
        local enabled = traces:find("," .. trace[1] .. ",", 1, true) ~= nil
        settings_checkbox(trace[2], prefix .. "_trace_" .. trace[1], enabled, function(value)
          local selected = {}
          for _, candidate in ipairs({ "m", "s", "i" }) do
            local on = candidate == trace[1] and value
              or candidate ~= trace[1] and traces:find("," .. candidate .. ",", 1, true) ~= nil
            if on then selected[#selected + 1] = candidate end
          end
          if #selected == 0 then selected[1] = trace[1] end
          Content.save_field(config, prefix, "meter_history_traces", table.concat(selected, ","))
        end)
        if index < 3 then R.ImGui_SameLine(ctx, 0, 10) end
      end
    elseif display == "waveform" then
      Metering.draw_compact_channel_rows(config, prefix, false)
      Content.draw_editor_combo_row(config, prefix, "meter_waveform_timebase", "Time span", {
        { 10, "10 ms" }, { 25, "25 ms" }, { 50, "50 ms" },
        { 100, "100 ms" }, { 250, "250 ms" },
      })
      Content.draw_editor_combo_row(config, prefix, "meter_waveform_layout", "Pair layout", {
        { "overlay", "Overlay" }, { "stacked", "Stacked" },
      })
    elseif display == "spectrum" or display == "spectrogram" then
      Metering.draw_compact_channel_rows(config, prefix, false)
      Content.draw_editor_combo_row(config, prefix, "meter_spectrum_fft_size", "FFT size", {
        { 1024, "1024 - responsive" }, { 2048, "2048 - balanced" },
        { 4096, "4096 - detailed" }, { 8192, "8192 - maximum" },
      })
      Content.draw_editor_combo_row(config, prefix, "meter_spectrum_floor", "Floor", {
        { -60, "-60 dB" }, { -90, "-90 dB" }, { -120, "-120 dB" },
      })
      Metering.draw_compact_slider_row(config, prefix, "meter_spectrum_smoothing",
        "Smoothing", 0, 0.95, "%.2f", "Higher values blend recent frames into calmer motion.")
      if display == "spectrogram" then
        Content.draw_editor_combo_row(config, prefix, "meter_spectrogram_seconds", "Visible time", {
          { 5, "5 seconds" }, { 10, "10 seconds" },
          { 20, "20 seconds" }, { 30, "30 seconds" },
        })
        Content.draw_editor_combo_row(config, prefix, "meter_spectrogram_bins", "Detail", {
          { 64, "64 bins - efficient" }, { 128, "128 bins - balanced" },
          { 256, "256 bins - detailed" }, { 512, "512 bins - high" },
          { 1024, "1024 bins - maximum" },
        })
        Content.draw_editor_combo_row(config, prefix, "meter_spectrogram_palette", "Palette", {
          { "theme", "Theme" }, { "ocean", "Ocean" },
          { "ember", "Ember" }, { "violet", "Violet" },
        })
        Content.draw_editor_combo_row(config, prefix, "meter_spectrogram_scale", "Frequency scale", {
          { "mel", "Mel" }, { "log", "Log" }, { "linear", "Linear" },
        }, "Frequency scale", "Choose the frequency spacing independently of FFT size, definition, and tilt.")
        Content.draw_editor_combo_row(config, prefix, "meter_spectrogram_mode", "Mode", {
          { "sharper", "Sharper" }, { "sharp", "Sharp" }, { "classic", "Classic" },
        }, "Spectrogram mode", "Sharper emphasizes local spectral detail; Classic is the smoothest presentation.")
        Metering.draw_compact_slider_row(config, prefix, "meter_spectrogram_tilt",
          "Tilt", -12, 12, "%+.2f dB",
          "Tilts the displayed spectrum around 1 kHz. The fresh default is +4.50 dB.")
      else
        settings_checkbox("Peak hold", prefix .. "_spectrum_peak_hold",
          config.meter_spectrum_peak_hold, function(value)
            Content.save_field(config, prefix, "meter_spectrum_peak_hold", value)
          end)
      end
    elseif display == "vectorscope" then
      Metering.draw_compact_channel_rows(config, prefix, true)
      Content.draw_editor_combo_row(config, prefix, "meter_scope_mode", "Orientation", {
        { "lr", "Left / Right" }, { "ms", "Mid / Side" },
      })
      Metering.draw_compact_slider_row(config, prefix, "meter_scope_persistence",
        "Persistence", 0, 2, "%.2f s", "Keeps a short, bounded trail in ReaClock.")
    elseif display == "correlation" then
      Metering.draw_compact_channel_rows(config, prefix, true)
      Content.draw_editor_combo_row(config, prefix, "meter_correlation_seconds", "History", {
        { 3, "3 seconds" }, { 5, "5 seconds" }, { 10, "10 seconds" },
        { 30, "30 seconds" }, { 60, "60 seconds" },
      })
    end

    if display ~= "numeric" and display ~= "history" then
      Content.draw_editor_combo_row(config, prefix, "meter_visual_quality", "Quality", {
        { "auto", "Auto - recommended" }, { "low", "Low" },
        { "standard", "Standard" }, { "high", "High" },
        { "maximum", "Maximum - CPU intensive" },
      }, "Visual quality", config.meter_visual_quality == "maximum"
        and "Maximum uses the selected FFT size, up to 1024 spectrum bins, and up to 240 real overlapping FFT columns per second. It can use substantially more CPU—especially at 8192, where it may consume much of one CPU core—so use it when visual detail matters most."
        or "Balances analysis detail and CPU use for this shared view. Maximum is an opt-in high-density analyzer with up to 1024 spectrum bins and 240 real FFT columns per second; the 8192 setting can use much of one CPU core on some systems.")
    end
    Metering.draw_compact_profile_note(config, card_index)
  end)
end

function Metering.draw_compact_source_card(config, prefix, card_index)
  Metering.scan_sources(false)
  local source, status = Metering.resolve_binding(config)
  UI.settings_card("dialog_meter_source", 145, function()
    UI.settings_section("Source",
      "One transparent meter instance shared by every card bound to it")
    local ready = source and source.compatible
    UI.settings_status_row(ready and "Source ready" or "Setup required",
      source and source.display_name or (status or "Choose a source"),
      ready and C.accent_secondary or C.accent,
      source and source.display_name or status)

    UI.settings_row("Meter", 72, function(control_width)
      R.ImGui_SetNextItemWidth(ctx, control_width)
      local preview = source and source.display_name
        or (config.meter_last_source_name ~= "" and config.meter_last_source_name
          or "Choose a source…")
      if R.ImGui_BeginCombo(ctx, "##dialog_" .. prefix .. "_meter_source", preview) then
        local any = false
        for _, candidate in ipairs(Runtime.metering.sources) do
          if candidate.compatible then
            any = true
            local selected = source and source.key == candidate.key
            if R.ImGui_Selectable(ctx,
                candidate.display_name .. "##dialog_" .. prefix .. "_source_" .. candidate.key,
                selected) then Metering.bind_card(card_index, candidate) end
          end
        end
        if not any then R.ImGui_TextDisabled(ctx, "No compatible meters found") end
        R.ImGui_EndCombo(ctx)
      end
    end)

    local project = Runtime.metering.active_project
    local master = project and R.GetMasterTrack(project)
    local monitoring_source = master and Metering.find_source_for_track(master, "monitoring")
    local monitoring_current = source and monitoring_source and source.key == monitoring_source.key
    local destination, kind = Metering.selected_destination()
    local destination_source = destination and Metering.find_source_for_track(destination, kind)
    local destination_current = source and destination_source and source.key == destination_source.key
    local button_width = (UI.settings_inner_width - 6) * 0.5
    if monitoring_current and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
    if UI.settings_outline_button(monitoring_current and "MONITORING · CURRENT"
        or monitoring_source and "USE MONITORING FX" or "ADD MONITORING FX",
        "dialog_meter_monitoring", button_width, 27, true) and not monitoring_current then
      local okay, detail = Metering.insert_monitoring(card_index)
      Runtime.metering.operation_status = okay and detail or nil
      Runtime.metering.operation_error = not okay and detail or nil
    end
    if monitoring_current and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
    R.ImGui_SameLine(ctx, 0, 6)
    local destination_disabled = not destination or destination_current
    if destination_disabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
    if UI.settings_outline_button(destination_current and "TRACK · CURRENT"
        or destination_source and "USE SELECTED TRACK" or "ADD TO SELECTED TRACK",
        "dialog_meter_destination", button_width, 27) and not destination_disabled then
      local okay, detail = Metering.insert_on_track(card_index, destination, kind)
      Runtime.metering.operation_status = okay and detail or nil
      Runtime.metering.operation_error = not okay and detail or nil
    end
    if destination_disabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end

    if Runtime.metering.operation_status then
      UI.settings_note(Runtime.metering.operation_status, C.accent_secondary_text)
    elseif Runtime.metering.operation_error then
      UI.settings_note(Runtime.metering.operation_error, C.danger)
    end
  end)
end

function Metering.draw_compact_controls_card(config)
  local source = Metering.resolve_binding(config)
  local available = source and source.compatible
  UI.settings_card("dialog_meter_controls", 101, function()
    UI.settings_section("Meter controls", "These affect every card using this source")
    if not available and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
    UI.settings_action_row("Restart every integrated, maximum, and history reading.",
      "RESET METER", "dialog_reset_meter", 104, false, function()
        if source then
          local okay, detail = Metering.request_reset(source, "editor")
          Runtime.metering.operation_error = not okay and detail or nil
        end
      end)
    local reset_on_transport = source and (R.TrackFX_GetParam(source.track,
      source.fx_index, Metering.param.reset_on_transport) or 0) >= 0.5 or not source
    settings_checkbox("Reset when transport starts", "dialog_meter_transport_reset",
      reset_on_transport, function(value)
        if not source then return end
        local wrote = R.TrackFX_SetParam(source.track, source.fx_index,
          Metering.param.reset_on_transport, value and 1 or 0)
        local verified = (R.TrackFX_GetParam(source.track, source.fx_index,
          Metering.param.reset_on_transport) or 0) >= 0.5
        if wrote ~= false and verified == value then
          Runtime.metering.operation_status = value
            and "Fresh measurement enabled when transport starts."
            or "Transport-start reset disabled."
          Runtime.metering.operation_error = nil
        else
          Runtime.metering.operation_error = "REAPER could not update transport reset."
        end
      end)
    if not available and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
  end)
end

function Metering.compact_maintenance_height()
  if Runtime.metering.cleanup_armed then return 112 end
  if Runtime.metering.cleanup_status or Runtime.metering.cleanup_error then return 102 end
  return 78
end

function Metering.draw_compact_maintenance_card()
  UI.settings_card("dialog_meter_maintenance", Metering.compact_maintenance_height(), function()
    UI.settings_section("Project cleanup", "Unused track and master meters in the active project")
    if Runtime.metering.cleanup_status then
      UI.settings_note(Runtime.metering.cleanup_status, C.accent_secondary_text)
    elseif Runtime.metering.cleanup_error then
      UI.settings_note(Runtime.metering.cleanup_error, C.danger)
    end
    if not Runtime.metering.cleanup_armed then
      UI.settings_action_row("Monitoring FX is never removed here.",
        "REVIEW UNUSED…", "dialog_review_unused", 124, false, function()
          local candidates = Metering.unused_ordinary_sources()
          if #candidates == 0 then
            Runtime.metering.cleanup_status = "No unused track meters were found."
            Runtime.metering.cleanup_error = nil
          else
            Runtime.metering.cleanup_armed = #candidates
            Runtime.metering.cleanup_status, Runtime.metering.cleanup_error = nil, nil
          end
        end)
    else
      local count = Runtime.metering.cleanup_armed
      UI.settings_note(string.format("Remove %d unused meter%s?", count,
        count == 1 and "" or "s"), C.danger)
      if UI.settings_outline_button("REMOVE", "dialog_remove_unused", 88, 27, true) then
        local okay, detail = Metering.cleanup_unused_ordinary_sources()
        Runtime.metering.cleanup_status = okay and detail or nil
        Runtime.metering.cleanup_error = not okay and detail or nil
        Runtime.metering.cleanup_armed = nil
      end
      R.ImGui_SameLine(ctx, 0, 6)
      if UI.settings_outline_button("CANCEL", "dialog_cancel_unused", 64, 27) then
        Runtime.metering.cleanup_armed = nil
      end
    end
  end)
end

function Content.draw_compact_meter_editor(config, prefix, defaults)
  local card_index = Content.card_index_from_prefix(prefix)
  local start_x, start_y = R.ImGui_GetCursorScreenPos(ctx)
  local available = UI.settings_column_width or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local gap, column_width = 12, (available - 12) * 0.5

  local function draw_column(x, callback)
    R.ImGui_SetCursorScreenPos(ctx, x, start_y)
    R.ImGui_BeginGroup(ctx)
    local prior_width = UI.settings_column_width
    UI.settings_column_width = column_width
    callback()
    UI.settings_column_width = prior_width
    R.ImGui_Dummy(ctx, column_width, 0)
    R.ImGui_EndGroup(ctx)
    return select(2, R.ImGui_GetCursorScreenPos(ctx))
  end

  local left_bottom = draw_column(start_x, function()
    Metering.draw_compact_source_card(config, prefix, card_index)
    UI.settings_gap()
    Content.draw_editor_display_card(config, prefix, card_index)
  end)
  local right_bottom = draw_column(start_x + column_width + gap, function()
    Metering.draw_compact_display_card(config, prefix, card_index)
    UI.settings_gap()
    Metering.draw_compact_controls_card(config)
    UI.settings_gap()
    Metering.draw_compact_maintenance_card()
  end)

  local bottom = math.max(left_bottom, right_bottom)
  R.ImGui_SetCursorScreenPos(ctx, start_x, bottom)
  R.ImGui_Dummy(ctx, available, 0)
  UI.settings_gap()
  Content.draw_editor_reset_card(config, prefix, defaults)
end

function Content.meter_editor_height(config, prefix)
  local display_height = Metering.compact_display_height(config)
  local maintenance_height = Metering.compact_maintenance_height()
  local display_card_height = Content.editor_scrollable(config, prefix) and 243 or 216
  local left_height = 145 + 12 + display_card_height
  local right_height = display_height + 12 + 101 + 12 + maintenance_height
  -- Header, body insets, Preview, Content, inter-section gaps, Reset, and a
  -- comfortable bottom inset account for 318 px around the taller column.
  -- A fully expanded Spectrogram adds independent scale, definition, and tilt
  -- rows. Prefer fitting the complete two-column workspace plus Reset Card on
  -- ordinary 1080p displays; the work-area cap still supplies scrolling on
  -- genuinely shorter screens.
  return math.max(700, math.min(1020, 318 + math.max(left_height, right_height)))
end

function Content.draw_detail_editor_window()
  if not detail_editor.open then
    if Runtime.detail_editor_window_was_open then
      detail_editor.reset_armed = false
      Runtime.metering.cleanup_armed = nil
    end
    Runtime.detail_editor_window_was_open = false
    return
  end
  local newly_opened = not Runtime.detail_editor_window_was_open
  Runtime.detail_editor_window_was_open = true

  local config, prefix, title, defaults, show_custom_label
  if detail_editor.kind == "card" then
    local index = tonumber(detail_editor.id)
    local detached = index and index < 0 and Content.detached_entry(index) or nil
    config = index and settings.cards[index]
    defaults = detached and detached.defaults or index and CARD_DEFAULTS[index]
    if config then
      if detached then
        prefix = "detached_" .. detached.id
        title = "Customize Pop-Out Card"
      else
        local row = math.floor((index - 1) / CARDS_PER_ROW) + 1
        local column = (index - 1) % CARDS_PER_ROW + 1
        prefix = "card_" .. index
        title = string.format("Customize Row %d · Card %d", row, column)
      end
      show_custom_label = true
    end
  end
  if not config or not defaults then detail_editor.open = false return end

  local is_meter = config.type == "meter"
  local is_action = config.type == "action"
  local editor_width = is_meter and 720 or 620
  local editor_height = is_meter and Content.meter_editor_height(config, prefix)
    or (Content.editor_scrollable(config, prefix) and 560 or 532)
  if config.type == "custom" then
    editor_height = Content.editor_scrollable(config, prefix) and 748 or 720
    if Metering.template_uses_metrics(config.template) then
      -- The shared meter-source workspace adds a complete setup card. Give it
      -- real room on ordinary desktop monitors; the work-area cap below still
      -- supplies scrolling on genuinely short displays.
      editor_height = math.min(920, editor_height + 172)
    end
  elseif is_action then
    editor_height = 730
  end
  local detail_index = Content.card_index_from_prefix(prefix)
  local detached_owner = detail_index and detail_index < 0
    and Content.detached_entry(detail_index) or nil
  local owner = detached_owner and {
    x = detached_owner.x, y = detached_owner.y,
    w = detached_owner.w, h = detached_owner.h,
  } or Runtime.settings_owner_geometry
  local bounds = owner and window_work_area(owner.x, owner.y, owner.w, owner.h)
  if bounds then
    editor_height = math.max(420, math.min(editor_height, bounds.bottom - bounds.top - 16))
  end
  R.ImGui_SetNextWindowSize(ctx, editor_width, editor_height, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSizeConstraints(ctx,
    editor_width, editor_height, editor_width, editor_height)
  if newly_opened and owner then
    local target_x = owner.x + owner.w * 0.5 - editor_width * 0.5
    local target_y = owner.y + owner.h * 0.5 - editor_height * 0.5
    if bounds then
      local inset = 8
      local min_x, min_y = bounds.left + inset, bounds.top + inset
      local max_x = math.max(min_x, bounds.right - editor_width - inset)
      local max_y = math.max(min_y, bounds.bottom - editor_height - inset)
      target_x = math.max(min_x, math.min(max_x, target_x))
      target_y = math.max(min_y, math.min(max_y, target_y))
    end
    R.ImGui_SetNextWindowPos(ctx, target_x, target_y, R.ImGui_Cond_Appearing())
  end
  if detail_editor.focus_requested and type(R.ImGui_SetNextWindowFocus) == "function" then
    R.ImGui_SetNextWindowFocus(ctx)
  end
  detail_editor.focus_requested = false
  local suppress_topmost = (detail_editor.topmost_reassert or 0) > 1
  if (detail_editor.topmost_reassert or 0) > 0 then
    detail_editor.topmost_reassert = detail_editor.topmost_reassert - 1
  end

  local palette = UI.settings_palette()
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.ink)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_CheckMark(), readable_on(C.accent))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), palette.subtle_border)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_PopupBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Header(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_HeaderHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_HeaderActive(), C.toggle_selected)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Separator(), palette.subtle_border)
  local detail_focus_colors = Content.push_focus_color()
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 7, 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), 8, 4)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushFont(ctx, font_regular, 12)

  local detail_flags = R.ImGui_WindowFlags_NoCollapse()
    | R.ImGui_WindowFlags_NoDocking()
    | R.ImGui_WindowFlags_NoTitleBar()
    | R.ImGui_WindowFlags_NoResize()
    | R.ImGui_WindowFlags_NoScrollbar()
    | R.ImGui_WindowFlags_NoScrollWithMouse()
  -- Card Details is a modeless tool window, but it must never disappear behind
  -- the clock that opened it. Keep the auxiliary viewport above ordinary
  -- windows for its entire lifetime; the main clock yields its own TopMost
  -- role while an auxiliary window is open.
  if not suppress_topmost and type(R.ImGui_WindowFlags_TopMost) == "function" then
    detail_flags = detail_flags | R.ImGui_WindowFlags_TopMost()
  end
  local visible
  visible, detail_editor.open = R.ImGui_Begin(ctx,
    title .. "###ReaClockDetailEditor", detail_editor.open, detail_flags)
  if visible then
    UI.settings_info_index = 0
    local origin_x, origin_y = R.ImGui_GetCursorScreenPos(ctx)
    local window_width, window_height = R.ImGui_GetWindowSize(ctx)
    local draw_list = R.ImGui_GetWindowDrawList(ctx)
    Runtime.detail_editor_window_geometry = {
      x = select(1, R.ImGui_GetWindowPos(ctx)),
      y = select(2, R.ImGui_GetWindowPos(ctx)),
      w = window_width, h = window_height,
    }

    R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, origin_y + 14)
    R.ImGui_PushFont(ctx, font_bold, 13)
    R.ImGui_Text(ctx, title)
    R.ImGui_PopFont(ctx)

    local context_label = is_meter and "METERING"
      or is_action and "ACTION BUTTON"
      or config.type == "custom" and "CUSTOM TEMPLATE" or "CARD DETAILS"
    R.ImGui_PushFont(ctx, font_bold, 9.5)
    local context_width = R.ImGui_CalcTextSize(ctx, context_label)
    R.ImGui_SetCursorScreenPos(ctx,
      origin_x + window_width - context_width - 46, origin_y + 16)
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), palette.label)
    R.ImGui_Text(ctx, context_label)
    R.ImGui_PopStyleColor(ctx)
    R.ImGui_PopFont(ctx)

    local close_x, close_y, close_size = origin_x + window_width - 29, origin_y + 12, 16
    R.ImGui_SetCursorScreenPos(ctx, close_x, close_y)
    if R.ImGui_InvisibleButton(ctx, "##close_detail_editor", close_size, close_size) then
      detail_editor.open = false
    end
    local close_color = R.ImGui_IsItemHovered(ctx) and C.ink or C.muted
    R.ImGui_DrawList_AddLine(draw_list, close_x + 4, close_y + 4,
      close_x + 12, close_y + 12, close_color, 1.1)
    R.ImGui_DrawList_AddLine(draw_list, close_x + 12, close_y + 4,
      close_x + 4, close_y + 12, close_color, 1.1)

    local header_height = 45
    local body_y, body_height = origin_y + header_height, window_height - header_height
    local body_rounding, body_rounding_flags = 0, 0
    if type(R.ImGui_DrawFlags_RoundCornersBottom) == "function" then
      body_rounding = 10
      body_rounding_flags = R.ImGui_DrawFlags_RoundCornersBottom()
    end
    R.ImGui_DrawList_AddRectFilled(draw_list, origin_x, body_y,
      origin_x + window_width, body_y + body_height, palette.body,
      body_rounding, body_rounding_flags)
    R.ImGui_DrawList_AddLine(draw_list, origin_x, body_y,
      origin_x + window_width, body_y, palette.subtle_border, 1)

    local body_padding = 14
    local content_width = window_width - body_padding * 2
    R.ImGui_SetCursorScreenPos(ctx, origin_x + body_padding, body_y + body_padding)
    local prior_column_width = UI.settings_column_width
    UI.settings_column_width = content_width

    if R.ImGui_BeginChild(ctx, "##detail_editor_scroll", content_width,
        body_height - body_padding * 2, 0) then
      UI.settings_column_width = math.max(320,
        select(1, R.ImGui_GetContentRegionAvail(ctx)) - 8)
      Content.draw_editor_summary(config, prefix)
      UI.settings_gap()
      Content.draw_editor_content_card(config, prefix,
        Content.card_index_from_prefix(prefix))
      UI.settings_gap()
      if is_meter then
        Content.draw_compact_meter_editor(config, prefix, defaults)
      else
        if config.type == "custom" then
          Content.draw_editor_text_card(config, prefix)
          UI.settings_gap()
          if Metering.template_uses_metrics(config.template) then
            Metering.draw_compact_source_card(config, prefix,
              Content.card_index_from_prefix(prefix))
            UI.settings_gap()
          end
        elseif is_action then
          Content.draw_editor_action_card(config, prefix)
          UI.settings_gap()
        end
        Content.draw_editor_display_card(config, prefix,
          Content.card_index_from_prefix(prefix))
        UI.settings_gap()
        Content.draw_editor_reset_card(config, prefix, defaults)
      end
      R.ImGui_Dummy(ctx, 0, 8)
    end
    R.ImGui_EndChild(ctx)
    UI.settings_column_width = prior_column_width

    R.ImGui_SetCursorScreenPos(ctx, origin_x, body_y + body_height)
    R.ImGui_Dummy(ctx, window_width, 0)
  end
  R.ImGui_End(ctx)
  R.ImGui_PopFont(ctx)
  R.ImGui_PopStyleVar(ctx, 6)
  R.ImGui_PopStyleColor(ctx, 15 + detail_focus_colors)
end

-- Clock Faces store only information architecture. Appearance, calibration,
-- docking, and window geometry remain global so switching faces is immediate
-- and never changes the user's monitoring setup unexpectedly.
function Content.capture_face()
  local face = {
    show_main_clock = settings.show_main_clock,
    main_clock_size = settings.main_clock_size,
    show_progress = settings.show_progress,
    card_rows = settings.card_rows,
    row_counts = {}, row_sizes = {}, cards = {},
  }
  for row = 1, MAX_CARD_ROWS do
    face.row_counts[row] = settings.card_row_counts[row]
    face.row_sizes[row] = settings.card_row_sizes[row]
  end
  for index, card in ipairs(settings.cards) do
    face.cards[index] = Content.clone_card(card)
  end
  return face
end

function Content.default_face(face_id)
  local face = {
    show_main_clock = true, main_clock_size = "huge",
    show_progress = true,
    card_rows = 3,
    row_counts = { 1, 4, 2, 1 },
    row_sizes = { "large", "medium", "medium", "medium" },
    cards = {},
  }
  for index = 1, TOTAL_CARD_SLOTS do face.cards[index] = Content.new_card("none") end

  local function meter_card(display, metric, span)
    local card = Content.new_card("meter")
    card.meter_display, card.meter_metric = display, metric or "lufs_i"
    card.span = span or "auto"
    card.meter_source_kind = settings.meter_face_source_kind
    card.meter_track_guid = settings.meter_face_track_guid
    card.meter_fx_guid = settings.meter_face_fx_guid
    card.meter_source_ordinal = settings.meter_face_source_ordinal
    card.meter_last_source_name = settings.meter_face_last_source_name
    return card
  end

  if face_id == "minimal" then
    face.show_progress = false
    face.card_rows = 0
  elseif face_id == "visual_click" then
    face.show_main_clock, face.show_progress = false, false
    face.card_rows, face.row_counts[1], face.row_sizes[1] = 1, 1, "huge"
    face.cards[1] = Content.new_card("visual_click")
  elseif face_id == "metering" then
    face.show_main_clock, face.show_progress = false, false
    face.card_rows = 3
    face.row_counts = { 2, 3, 2, 1 }
    face.row_sizes = { "huge", "medium", "visualizer", "medium" }
    face.cards[1] = meter_card("numeric", "lufs_i", "4")
    face.cards[2] = meter_card("numeric", "lufs_i_max", "2")
    face.cards[7] = meter_card("numeric", "lufs_s", "2")
    face.cards[8] = meter_card("numeric", "true_peak_max", "2")
    face.cards[9] = meter_card("numeric", "lra", "2")
    face.cards[13] = meter_card("history", "lufs_i", "4")
    face.cards[14] = meter_card("levels", "lufs_i", "2")
  elseif face_id == "visualizations" then
    face.show_main_clock, face.show_progress = false, false
    face.card_rows = 4
    face.row_counts = { 2, 2, 2, 2 }
    face.row_sizes = { "visualizer", "visualizer", "visualizer", "medium" }
    face.cards[1] = meter_card("spectrum", "lufs_i", "4")
    face.cards[2] = meter_card("levels", "lufs_i", "2")
    face.cards[7] = meter_card("waveform", "lufs_i", "4")
    face.cards[8] = meter_card("vectorscope", "lufs_i", "2")
    face.cards[13] = meter_card("spectrogram", "lufs_i", "4")
    face.cards[14] = meter_card("history", "lufs_i", "2")
    face.cards[19] = meter_card("numeric", "lufs_i", "3")
    face.cards[20] = meter_card("numeric", "lufs_s", "3")
  else
    for index, defaults in ipairs(CARD_DEFAULTS) do
      face.cards[index] = Content.clone_card(defaults)
    end
  end
  -- Initialize every dormant row so adding any row up to the current maximum
  -- always starts from a predictable one-card Medium configuration.
  for row = 1, MAX_CARD_ROWS do
    face.row_counts[row] = face.row_counts[row] or 1
    face.row_sizes[row] = face.row_sizes[row] or "medium"
  end
  return face
end

function Content.normalize_face(face, fallback_id)
  if type(face) ~= "table" then return nil end
  local fallback = Content.default_face(fallback_id)
  local normalized = {
    show_main_clock = type(face.show_main_clock) == "boolean"
      and face.show_main_clock or fallback.show_main_clock,
    main_clock_size = Runtime.clock_sizes[face.main_clock_size]
      and face.main_clock_size or fallback.main_clock_size,
    show_progress = type(face.show_progress) == "boolean"
      and face.show_progress or fallback.show_progress,
    card_rows = 0,
    row_counts = {}, row_sizes = {}, cards = {},
  }
  local function normalize_config(config, default)
    config = type(config) == "table" and config or default
    local content_type = CARD_TYPE_BY_ID[config.type] and config.type or default.type
    local font = (config.font == "regular" or config.font == "mono")
      and config.font or "auto"
    local align = (config.align == "left" or config.align == "center"
      or config.align == "right") and config.align or "default"
    local span = normalize_card_span(config.span)
    local normalized_config = {
      type = content_type,
      label = type(config.label) == "string" and config.label or default.label,
      template = type(config.template) == "string" and config.template or default.template,
      font = font,
      scroll = config.scroll == true,
      show_title = config.show_title ~= false,
      align = align,
      span = span,
    }
    for _, field in ipairs(METER_CARD_FIELDS) do
      normalized_config[field.key] = normalize_meter_field(field,
        config[field.key] == nil and default[field.key] or config[field.key])
    end
    for _, field in ipairs(Runtime.action_card_fields) do
      normalized_config[field.key] = Runtime.normalize_action_field(
        config[field.key] == nil and default[field.key] or config[field.key], field.default)
    end
    return normalized_config
  end
  local cards = type(face.cards) == "table" and face.cards or {}
  local row_counts = type(face.row_counts) == "table" and face.row_counts or fallback.row_counts
  local row_sizes = type(face.row_sizes) == "table" and face.row_sizes or fallback.row_sizes
  normalized.card_rows = math.max(0, math.min(MAX_CARD_ROWS,
    math.floor((tonumber(face.card_rows) or fallback.card_rows) + 0.5)))
  for row = 1, MAX_CARD_ROWS do
    normalized.row_counts[row] = math.max(1, math.min(CARDS_PER_ROW,
      math.floor((tonumber(row_counts[row]) or fallback.row_counts[row]) + 0.5)))
    local size_id = row_sizes[row]
    normalized.row_sizes[row] = ROW_SIZE_OPTIONS[size_id] and size_id or fallback.row_sizes[row]
  end
  for index = 1, TOTAL_CARD_SLOTS do
    normalized.cards[index] = normalize_config(cards[index], fallback.cards[index])
  end
  for row = 1, MAX_CARD_ROWS do
    local used, count = 0, normalized.row_counts[row]
    for column = 1, count do
      local index = (row - 1) * CARDS_PER_ROW + column
      local card = normalized.cards[index]
      local remaining_cards = count - column
      local maximum = math.max(1, CARDS_PER_ROW - used - remaining_cards)
      local fixed = tonumber(card.span)
      if fixed then card.span = tostring(math.min(fixed, maximum)) end
      used = used + (tonumber(card.span) or 1)
    end
  end
  return normalized
end

function Content.builtin_face_ids()
  return { "default", "minimal", "metering", "visualizations", "visual_click" }
end

function Content.user_face_ids()
  local ids = {}
  for id in tostring(settings.face_user_ids or ""):gmatch("[^,]+") do
    if id:match("^u%d+$") then ids[#ids + 1] = id end
  end
  return ids
end

function Content.face_name(face_id)
  local names = {
    default = "Default", minimal = "Minimal", visual_click = "Visual Click",
    metering = "Metering", visualizations = "Visualizations",
    custom = "Custom",
  }
  if names[face_id] then return names[face_id] end
  return Store.root.faces.names[face_id] or "Untitled Face"
end

function Content.is_builtin_face(face_id)
  for _, id in ipairs(Content.builtin_face_ids()) do
    if id == face_id then return true end
  end
  return false
end

function Content.face_exists(face_id)
  if face_id == "custom" or Content.is_builtin_face(face_id) then return true end
  for _, id in ipairs(Content.user_face_ids()) do
    if id == face_id then return true end
  end
  return false
end

function Content.load_face(face_id)
  -- Built-in faces are immutable presets. Never let a previously saved layout
  -- shadow their canonical definitions.
  if Content.is_builtin_face(face_id) then return Content.default_face(face_id) end
  local decoded = Content.normalize_face(Store.root.faces.layouts[face_id], face_id)
  if decoded then return decoded end
  if face_id == "custom" then return Content.capture_face() end
  return nil
end

function Content.save_face(face_id, face)
  Store.root.faces.layouts[face_id] = Content.normalize_face(face, face_id)
  Store.mark_dirty()
end

function Content.save_active_face()
  -- Editing an immutable built-in creates a Custom face immediately. Named
  -- user faces remain editable in place.
  if Content.is_builtin_face(settings.active_face)
      or not Content.face_exists(settings.active_face) then
    settings.active_face, Store.root.faces.active = "custom", "custom"
  end
  Content.save_face(settings.active_face, Content.capture_face())
end

function Content.apply_face(face_id, face)
  if not face then return end
  settings.active_face = face_id
  Store.root.faces.active = face_id
  settings.show_main_clock = face.show_main_clock
  settings.main_clock_size = face.main_clock_size
  settings.show_progress = face.show_progress
  settings.card_rows = face.card_rows
  for row = 1, MAX_CARD_ROWS do
    settings.card_row_counts[row] = face.row_counts[row]
    settings.card_row_sizes[row] = face.row_sizes[row]
  end
  for index = 1, TOTAL_CARD_SLOTS do
    settings.cards[index] = Content.clone_card(face.cards[index])
  end
  save_all_settings()
  if not Content.is_builtin_face(face_id) then
    Content.save_face(face_id, Content.capture_face())
  end
  Store.mark_dirty()
  -- Face switching now lives inside Edit mode, so keep the editing surface
  -- open while the selected layout changes underneath it.
  detail_editor.open = false
  edit_selected_row = math.max(1, math.min(settings.card_rows, 1))
  edit_selected_card = settings.card_rows > 0 and row_card_index(edit_selected_row, 1) or 1
  request_layout_resize()
  recompute_snapshot(true)
  if METER_FACE_IDS[face_id] then
    Metering.scan_sources(true)
    local first_meter, ready_source
    for row = 1, settings.card_rows do
      for column = 1, settings.card_row_counts[row] do
        local index = (row - 1) * CARDS_PER_ROW + column
        local card = settings.cards[index]
        if card and card.type == "meter" then
          first_meter = first_meter or index
          ready_source = ready_source or Metering.resolve_binding(card)
        end
      end
    end
    if first_meter and not ready_source then Metering.request_source_setup(first_meter, true) end
  end
end

function Content.select_face(face_id)
  if face_id == settings.active_face or not Content.face_exists(face_id) then return end
  if not Content.is_builtin_face(settings.active_face) then Content.save_active_face() end
  Content.apply_face(face_id, Content.load_face(face_id))
end

function Content.create_face(name)
  local next_id = math.max(1, math.floor(tonumber(settings.face_user_next) or 1))
  local face_id = "u" .. next_id
  while Content.face_exists(face_id) do
    next_id, face_id = next_id + 1, "u" .. (next_id + 1)
  end
  local ids = Content.user_face_ids()
  ids[#ids + 1] = face_id
  settings.face_user_ids = table.concat(ids, ",")
  settings.face_user_next = next_id + 1
  Store.root.faces.user_ids = settings.face_user_ids
  Store.root.faces.user_next = settings.face_user_next
  Store.root.faces.names[face_id] = name
  Content.save_face(face_id, Content.capture_face())
  settings.active_face = face_id
  Store.root.faces.active = face_id
  Store.mark_dirty()
end

function Content.rename_face(face_id, name)
  if not face_id:match("^u%d+$") or not Content.face_exists(face_id) then return end
  Store.root.faces.names[face_id] = name
  Store.mark_dirty()
end

function Content.delete_face(face_id)
  if not face_id:match("^u%d+$") or not Content.face_exists(face_id) then return end
  if settings.active_face == face_id then Content.select_face("default") end
  local kept = {}
  for _, id in ipairs(Content.user_face_ids()) do
    if id ~= face_id then kept[#kept + 1] = id end
  end
  settings.face_user_ids = table.concat(kept, ",")
  Store.root.faces.user_ids = settings.face_user_ids
  Store.root.faces.names[face_id], Store.root.faces.layouts[face_id] = nil, nil
  Store.mark_dirty()
end

function Content.reset_active_face()
  if not Content.is_builtin_face(settings.active_face) then return end
  Content.apply_face(settings.active_face, Content.default_face(settings.active_face))
end

function Content.ensure_faces()
  if not Content.face_exists(settings.active_face) then
    settings.active_face = "default"
    Store.root.faces.active = settings.active_face
    Store.mark_dirty()
  end
  if not Content.is_builtin_face(settings.active_face)
      and type(Store.root.faces.layouts[settings.active_face]) ~= "table" then
    Content.save_active_face()
  end
end

function Content.request_face_dialog(action)
  face_dialog.request = action
  if action == "save_as" then
    local base = Content.face_name(settings.active_face)
    face_dialog.input = settings.active_face == "custom" and "My Clock Face"
      or (base .. " Copy")
  elseif action == "rename" then
    face_dialog.input = Content.face_name(settings.active_face)
  end
end

function Content.draw_face_selector(include_actions)
  for _, face_id in ipairs(Content.builtin_face_ids()) do
    if R.ImGui_MenuItem(ctx, Content.face_name(face_id) .. "##face_switch_" .. face_id,
        nil, settings.active_face == face_id, true) then Content.select_face(face_id) end
  end
  R.ImGui_Separator(ctx)
  if R.ImGui_MenuItem(ctx, "Custom##face_switch_custom", nil,
      settings.active_face == "custom", true) then Content.select_face("custom") end
  for _, face_id in ipairs(Content.user_face_ids()) do
    if R.ImGui_MenuItem(ctx, Content.face_name(face_id) .. "##face_switch_" .. face_id,
        nil, settings.active_face == face_id, true) then Content.select_face(face_id) end
  end
  if include_actions then
    R.ImGui_Separator(ctx)
    if R.ImGui_MenuItem(ctx, "Save Current Face As…##save_face_as") then
      Content.request_face_dialog("save_as")
    end
    if settings.active_face:match("^u%d+$") then
      if R.ImGui_MenuItem(ctx, "Rename Current Face…##rename_face") then
        Content.request_face_dialog("rename")
      end
      if R.ImGui_MenuItem(ctx, "Delete Current Face…##delete_face") then
        Content.request_face_dialog("delete")
      end
    elseif Content.is_builtin_face(settings.active_face) then
      if R.ImGui_MenuItem(ctx, "Reset " .. Content.face_name(settings.active_face)
          .. "##reset_face") then Content.reset_active_face() end
    end
  end
end

function Content.draw_face_button(scale, x, y, w, h, alpha)
  local full_name = Content.face_name(settings.active_face)
  local clicked = draw_segment_button(
    "FACE", "face_selector", x, y, w, h, false, scale, alpha, true)
  local arrow_x, arrow_y = x + w - 11 * scale, y + h * 0.5
  local arrow_color = with_alpha(C.secondary,
    math.floor((C.secondary & 0xFF) * math.max(0, math.min(1, alpha or 1))))
  R.ImGui_DrawList_AddTriangleFilled(R.ImGui_GetWindowDrawList(ctx),
    arrow_x - 3 * scale, arrow_y - 2 * scale,
    arrow_x + 3 * scale, arrow_y - 2 * scale,
    arrow_x, arrow_y + 2 * scale, arrow_color)
  if clicked then
    R.ImGui_OpenPopup(ctx, "##ReaClockFaceButtonMenu")
  end
  item_tooltip("Choose a Clock Face", "Currently selected: " .. full_name .. ".")
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "##ReaClockFaceButtonMenu") then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("CLOCK FACE")
    R.ImGui_Separator(ctx)
    Content.draw_face_selector(true)
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.draw_face_switch_menu()
  local right_button = R.ImGui_MouseButton_Right()
  local popup_open = R.ImGui_IsPopupOpen(ctx, "", R.ImGui_PopupFlags_AnyPopup())
  local unused_background_clicked = not popup_open
    and not Content.context_click_claimed
    and R.ImGui_IsWindowHovered(ctx)
    and not R.ImGui_IsAnyItemHovered(ctx)
    and R.ImGui_IsMouseClicked(ctx, right_button, false)
  if unused_background_clicked then
    R.ImGui_OpenPopup(ctx, "##ReaClockFaceSwitch")
  end
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "##ReaClockFaceSwitch") then
    R.ImGui_PushFont(ctx, font_regular, 13)
    Content.draw_popup_heading("CLOCK FACE")
    R.ImGui_Separator(ctx)
    Content.draw_face_selector(true)
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

function Content.draw_face_dialog()
  if face_dialog.request then
    face_dialog.action = face_dialog.request
    face_dialog.request = nil
    face_dialog.close_request = false
    R.ImGui_OpenPopup(ctx, "Clock Face Action###ReaClockFaceAction")
  end
  if not face_dialog.action and not face_dialog.close_request then return end

  local delete_action = face_dialog.action == "delete"
  local dialog_width, dialog_height = 460, delete_action and 180 or 215
  local owner_x, owner_y = R.ImGui_GetWindowPos(ctx)
  local owner_w, owner_h = R.ImGui_GetWindowSize(ctx)
  local dialog_x = owner_x + owner_w * 0.5 - dialog_width * 0.5
  local dialog_y = owner_y + owner_h * 0.5 - dialog_height * 0.5
  local bounds = window_work_area(owner_x, owner_y, owner_w, owner_h)
  if bounds then
    local inset = 8
    local min_x, min_y = bounds.left + inset, bounds.top + inset
    local max_x = math.max(min_x, bounds.right - dialog_width - inset)
    local max_y = math.max(min_y, bounds.bottom - dialog_height - inset)
    dialog_x = math.max(min_x, math.min(max_x, dialog_x))
    dialog_y = math.max(min_y, math.min(max_y, dialog_y))
  end
  R.ImGui_SetNextWindowPos(ctx, dialog_x, dialog_y, R.ImGui_Cond_Appearing())
  R.ImGui_SetNextWindowSize(ctx, dialog_width, dialog_height, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSizeConstraints(ctx,
    dialog_width, dialog_height, dialog_width, dialog_height)

  local palette = UI.settings_palette()
  push_popup_style()
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 7, 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), 8, 4)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), palette.subtle_border)

  local visible, dialog_open
  local flags = R.ImGui_WindowFlags_NoTitleBar() | R.ImGui_WindowFlags_NoResize()
  if R.ImGui_BeginPopupModal then
    visible, dialog_open = R.ImGui_BeginPopupModal(ctx,
      "Clock Face Action###ReaClockFaceAction", true, flags)
  else
    visible = R.ImGui_BeginPopup(ctx, "Clock Face Action###ReaClockFaceAction")
    dialog_open = visible or R.ImGui_IsPopupOpen(ctx,
      "Clock Face Action###ReaClockFaceAction")
  end
  local should_close = face_dialog.close_request or dialog_open == false

  local function close_dialog()
    face_dialog.action = nil
    if R.ImGui_CloseCurrentPopup then R.ImGui_CloseCurrentPopup(ctx) end
  end

  if visible then
    if should_close then
      close_dialog()
    else
      UI.settings_info_index = 0
      local origin_x, origin_y = R.ImGui_GetCursorScreenPos(ctx)
      local window_width, window_height = R.ImGui_GetWindowSize(ctx)
      local draw_list = R.ImGui_GetWindowDrawList(ctx)
      local heading = delete_action and "Delete Clock Face"
        or face_dialog.action == "rename" and "Rename Clock Face"
        or "Save Current Face"

      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, origin_y + 14)
      R.ImGui_PushFont(ctx, font_bold, 13)
      R.ImGui_Text(ctx, heading)
      R.ImGui_PopFont(ctx)
      R.ImGui_PushFont(ctx, font_bold, 9.5)
      local context_width = R.ImGui_CalcTextSize(ctx, "CLOCK · FACE")
      R.ImGui_SetCursorScreenPos(ctx,
        origin_x + window_width - context_width - 46, origin_y + 16)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), palette.label)
      R.ImGui_Text(ctx, "CLOCK · FACE")
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)

      local close_x, close_y, close_size = origin_x + window_width - 29, origin_y + 12, 16
      R.ImGui_SetCursorScreenPos(ctx, close_x, close_y)
      if R.ImGui_InvisibleButton(ctx, "##close_face_dialog", close_size, close_size) then
        close_dialog()
      end
      local close_color = R.ImGui_IsItemHovered(ctx) and C.ink or C.muted
      R.ImGui_DrawList_AddLine(draw_list, close_x + 4, close_y + 4,
        close_x + 12, close_y + 12, close_color, 1.1)
      R.ImGui_DrawList_AddLine(draw_list, close_x + 12, close_y + 4,
        close_x + 4, close_y + 12, close_color, 1.1)

      local header_height = 45
      local body_y, body_height = origin_y + header_height, window_height - header_height
      local rounding, rounding_flags = 0, 0
      if type(R.ImGui_DrawFlags_RoundCornersBottom) == "function" then
        rounding, rounding_flags = 10, R.ImGui_DrawFlags_RoundCornersBottom()
      end
      R.ImGui_DrawList_AddRectFilled(draw_list, origin_x, body_y,
        origin_x + window_width, body_y + body_height, palette.body,
        rounding, rounding_flags)
      R.ImGui_DrawList_AddLine(draw_list, origin_x, body_y,
        origin_x + window_width, body_y, palette.subtle_border, 1)

      R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, body_y + 14)
      local prior_width = UI.settings_column_width
      UI.settings_column_width = window_width - 28
      UI.settings_card("face_action", body_height - 28, function()
        if delete_action then
          UI.settings_section("Delete face",
            "The Default face becomes active; this cannot be undone")
          UI.settings_note("Delete “" .. Content.face_name(settings.active_face) .. "”?",
            C.danger)
          R.ImGui_Dummy(ctx, 0, 7)
          R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), C.danger)
          R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(),
            contrast_layer(C.danger, 0.12))
          R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(),
            mix_color(C.danger, C.surface, 0.16))
          R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), readable_on(C.danger))
          if R.ImGui_Button(ctx, "DELETE FACE", 104, 27) then
            Content.delete_face(settings.active_face)
            Content.select_face("default")
            close_dialog()
          end
          R.ImGui_PopStyleColor(ctx, 4)
        else
          UI.settings_section(face_dialog.action == "rename" and "Name" or "New face",
            "Choose a short, recognizable Clock Face name")
          UI.settings_row("Name", 72, function(control_width)
            R.ImGui_SetNextItemWidth(ctx, control_width)
            if R.ImGui_IsWindowAppearing and R.ImGui_IsWindowAppearing(ctx)
                and R.ImGui_SetKeyboardFocusHere then R.ImGui_SetKeyboardFocusHere(ctx) end
            local changed, value = R.ImGui_InputTextWithHint(ctx,
              "##main_face_name", "Clock face name", face_dialog.input or "")
            if changed then face_dialog.input = value end
          end)
          UI.settings_note("Faces store the clock and card layout; global style and calibration stay unchanged.")
          R.ImGui_Dummy(ctx, 0, 5)
          local trimmed = tostring(face_dialog.input or ""):match("^%s*(.-)%s*$")
          if trimmed == "" and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
          if UI.settings_outline_button(face_dialog.action == "rename" and "RENAME"
              or "SAVE FACE", "face_dialog_primary", 96, 27, true)
              and trimmed ~= "" then
            if face_dialog.action == "rename" then
              Content.rename_face(settings.active_face, trimmed)
            else
              Content.create_face(trimmed)
            end
            close_dialog()
          end
          if trimmed == "" and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
        end
        R.ImGui_SameLine(ctx, 0, 6)
        if UI.settings_outline_button("CANCEL", "face_dialog_cancel", 68, 27) then
          close_dialog()
        end
      end, delete_action and { dashed = true, transparent = true } or nil)
      UI.settings_column_width = prior_width

      R.ImGui_SetCursorScreenPos(ctx, origin_x, body_y + body_height)
      R.ImGui_Dummy(ctx, window_width, 0)
    end
    if R.ImGui_EndPopup then R.ImGui_EndPopup(ctx) end
  end
  if should_close then
    face_dialog.request, face_dialog.action, face_dialog.close_request = nil, nil, false
  end
  R.ImGui_PopStyleColor(ctx, 7)
  R.ImGui_PopStyleVar(ctx, 6)
  pop_popup_style()
end

Content.ensure_faces()

if Store.create_defaults then
  Store.root.faces.active = settings.active_face
  save_all_settings()
  Store.create_defaults = nil
  if not Store.flush(true) then
    Store.set_warning(
      "ReaClock started with safe defaults but could not create settings.json. "
        .. tostring(Store.error or "Check that REAPER's Data folder is writable."),
      "SETTINGS NOT SAVED")
  end
end

local apply_theme_preset

function UI.style_chip(mode, width)
  local preset = THEME_PRESETS[mode]
  local selected = settings.theme_mode == mode
  local x, y = R.ImGui_GetCursorScreenPos(ctx)
  local height = 30
  local clicked = R.ImGui_InvisibleButton(ctx, "##style_chip_" .. mode, width, height)
  local hovered = R.ImGui_IsItemHovered(ctx)
  local palette = UI.settings_palette()
  local fill = selected and palette.selected or hovered and C.inactive_hover or palette.control
  local border = selected and C.accent or with_alpha(C.border, 70)
  local draw_list = R.ImGui_GetWindowDrawList(ctx)
  R.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, fill, 6)
  R.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height,
    border, 6, 0, selected and 1.5 or 1)
  local colors = { preset.background, preset.card or preset.background, preset.highlight }
  for index, color in ipairs(colors) do
    local cx = x + 14 + (index - 1) * 11
    R.ImGui_DrawList_AddCircleFilled(draw_list, cx, y + height * 0.5, 4.5, color)
    R.ImGui_DrawList_AddCircle(draw_list, cx, y + height * 0.5, 4.5,
      with_alpha(readable_on(color), 95), 14, 0.8)
  end
  R.ImGui_PushFont(ctx, font_bold, 10)
  local text_color = selected and UI.settings_palette().label or C.ink
  R.ImGui_DrawList_AddText(draw_list, x + 43, y + 9, text_color,
    preset.label:upper())
  R.ImGui_PopFont(ctx)
  item_tooltip("Use " .. preset.label, preset.description)
  if clicked then apply_theme_preset(mode) end
  return clicked
end

apply_theme_preset = function(mode)
  local preset = THEME_PRESETS[mode]
  if not preset then return end
  settings.theme_mode = mode
  settings.theme_background = preset.background
  settings.theme_text = preset.text
  settings.theme_highlight = preset.highlight
  -- The Edit-mode style menu is drawn while C may temporarily reference the
  -- recording palette. Rebuild on the next frame, after draw_face restores C
  -- to the normal palette, so a live style change cannot mutate the wrong
  -- table.
  palette_rebuild_pending = true
  save_string("theme_mode", mode)
  save_color("theme_background", settings.theme_background)
  save_color("theme_text", settings.theme_text)
  save_color("theme_highlight", settings.theme_highlight)
end

function Content.draw_style_button(scale, x, y, w, h, alpha)
  local preset = THEME_PRESETS[settings.theme_mode]
  local current_label = preset and preset.label or "Custom"
  local clicked = draw_segment_button(
    "STYLE", "style_selector", x, y, w, h, false, scale, alpha, true)
  local arrow_x, arrow_y = x + w - 11 * scale, y + h * 0.5
  local arrow_color = with_alpha(C.secondary,
    math.floor((C.secondary & 0xFF) * math.max(0, math.min(1, alpha or 1))))
  R.ImGui_DrawList_AddTriangleFilled(R.ImGui_GetWindowDrawList(ctx),
    arrow_x - 3 * scale, arrow_y - 2 * scale,
    arrow_x + 3 * scale, arrow_y - 2 * scale,
    arrow_x, arrow_y + 2 * scale, arrow_color)
  if clicked then R.ImGui_OpenPopup(ctx, "##ReaClockStyleButtonMenu") end
  item_tooltip("Choose a style", preset and preset.description
    or "Currently using your custom colors and fonts.")

  local function draw_style_swatches(option)
    local min_x, min_y = R.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = R.ImGui_GetItemRectMax(ctx)
    local size = math.max(7, 9 * math.min(scale, 1.25))
    local gap = math.max(3, 4 * math.min(scale, 1.25))
    local colors = {
      option.background, option.card or option.background, option.highlight,
    }
    local start_x = max_x - 24 * math.min(scale, 1.25)
      - (#colors * size + (#colors - 1) * gap)
    local swatch_y = min_y + math.max(1, (max_y - min_y - size) * 0.5)
    local draw_list = R.ImGui_GetWindowDrawList(ctx)
    for index, color in ipairs(colors) do
      local swatch_x = start_x + (index - 1) * (size + gap)
      R.ImGui_DrawList_AddRectFilled(draw_list, swatch_x, swatch_y,
        swatch_x + size, swatch_y + size, color, 2)
      R.ImGui_DrawList_AddRect(draw_list, swatch_x, swatch_y,
        swatch_x + size, swatch_y + size, with_alpha(readable_on(color), 105), 2)
    end
  end

  R.ImGui_SetNextWindowSizeConstraints(ctx,
    math.max(250, 250 * math.min(scale, 1.15)), 0, 380, 1000)
  push_popup_style()
  if R.ImGui_BeginPopup(ctx, "##ReaClockStyleButtonMenu") then
    R.ImGui_PushFont(ctx, font_regular, math.max(12, 13 * math.min(scale, 1.25)))
    Content.draw_popup_heading("CLOCK STYLE")
    R.ImGui_Separator(ctx)
    for _, mode in ipairs(STYLE_PRESET_ORDER) do
      local option = THEME_PRESETS[mode]
      if R.ImGui_MenuItem(ctx, option.label .. "##style_switch_" .. mode,
          nil, settings.theme_mode == mode, true) then
        apply_theme_preset(mode)
      end
      draw_style_swatches(option)
      if R.ImGui_IsItemHovered(ctx) then
        draw_styled_tooltip("Use " .. option.label, option.description)
      end
    end
    R.ImGui_Separator(ctx)
    if R.ImGui_MenuItem(ctx, "Custom…##style_switch_custom", nil,
        settings.theme_mode == "custom", true) then
      settings.theme_mode = "custom"
      save_string("theme_mode", settings.theme_mode)
      settings_open = true
      settings_tab_request = "appearance"
    end
    draw_style_swatches({
      background = settings.theme_background,
      card = C.tile,
      highlight = settings.theme_highlight,
    })
    if R.ImGui_IsItemHovered(ctx) then
      draw_styled_tooltip("Create a custom style",
        "Open Style settings and adjust the palette and fonts yourself.")
    end
    R.ImGui_PopFont(ctx)
    R.ImGui_EndPopup(ctx)
  end
  pop_popup_style()
end

local function apply_font_source(key, value)
  value = trim(value)
  if value == "" then
    font_status = "Enter a font family name or a .ttf, .otf, or .ttc file."
    return
  end
  if looks_like_font_file(value) and not R.file_exists(value) then
    font_status = "Font file not found: " .. value
    return
  end
  settings[key] = value
  font_inputs[key] = value
  save_string(key, value)
  font_reload_pending = true
  if key == "mono_font" then request_layout_resize() end
  font_status = "Font change applied."
end

function UI.draw_font_selector(label, key, description)
  local role = key == "regular_font" and "regular" or "mono"
  local weight_key, size_key = role .. "_weight", role .. "_size"
  local selected_weight = settings[weight_key] == "bold" and "Bold" or "Regular"

  R.ImGui_PushFont(ctx, font_bold, 11)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.secondary)
  R.ImGui_Text(ctx, label)
  R.ImGui_PopStyleColor(ctx)
  R.ImGui_PopFont(ctx)

  local available_width = UI.settings_inner_width or UI.settings_column_width
    or select(1, R.ImGui_GetContentRegionAvail(ctx))
  local gap = 6
  local weight_width = math.floor(available_width * 0.34)
  local family_width = available_width - weight_width - gap
  R.ImGui_SetNextItemWidth(ctx, family_width)
  local combo_flags = type(R.ImGui_ComboFlags_HeightLarge) == "function"
    and R.ImGui_ComboFlags_HeightLarge() or 0
  if R.ImGui_BeginCombo(ctx, "##font_picker_" .. key,
      font_source_label(settings[key]), combo_flags) then
    local options = scan_installed_fonts(false)
    local popup_width = select(1, R.ImGui_GetContentRegionAvail(ctx))
    local rescan_width = 64
    R.ImGui_SetNextItemWidth(ctx, math.max(110, popup_width - rescan_width - gap))
    local changed, search = R.ImGui_InputTextWithHint(ctx, "##font_search_" .. key,
      "Search installed fonts...", font_search[key])
    if changed then font_search[key] = search end
    R.ImGui_SameLine(ctx, 0, gap)
    if R.ImGui_Button(ctx, "RESCAN##" .. key, rescan_width, 0) then
      options = scan_installed_fonts(true)
    end
    UI.settings_note(font_scan_summary)

    local query = trim(font_search[key]):lower()
    local matches = 0
    for index, option in ipairs(options) do
      local haystack = (option.label .. " " .. option.source):lower()
      if query == "" or haystack:find(query, 1, true) then
        matches = matches + 1
        local selected = settings[key] == option.source
        if R.ImGui_Selectable(ctx, option.label .. "##font_" .. key .. index, selected) then
          apply_font_source(key, option.source)
        end
        item_tooltip(option.label, option.source)
        if selected and R.ImGui_SetItemDefaultFocus then R.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    if matches == 0 then UI.settings_note("No font faces match this search.") end
    R.ImGui_EndCombo(ctx)
  end

  R.ImGui_SameLine(ctx, 0, gap)
  R.ImGui_SetNextItemWidth(ctx, weight_width)
  if R.ImGui_BeginCombo(ctx, "##weight_" .. key, selected_weight) then
    for _, option in ipairs({ "regular", "bold" }) do
      local selected = settings[weight_key] == option
      local title = option == "bold" and "Bold" or "Regular"
      if R.ImGui_Selectable(ctx, title .. "##compact_" .. key, selected) then
        settings[weight_key] = option
        save_string(weight_key, option)
        font_reload_pending = true
        if role == "mono" then request_layout_resize() end
        font_status = title .. " weight applied."
      end
      if selected and R.ImGui_SetItemDefaultFocus then R.ImGui_SetItemDefaultFocus(ctx) end
    end
    R.ImGui_EndCombo(ctx)
  end

  local min_size, max_size = role == "regular" and 60 or 50, role == "regular" and 160 or 200
  UI.settings_slider_row("Size", "face_size_" .. key, settings[size_key] * 100,
    min_size, max_size, function(value) return string.format("%.0f%%", value) end,
    function(value)
      settings[size_key] = value / 100
      save_string(size_key, string.format("%.4f", settings[size_key]))
      if role == "mono" then request_layout_resize() end
    end, 60)

  if UI.settings_text_link("Advanced family or file path…", "font_advanced_" .. key) then
    UI.settings_font_advanced[key] = not UI.settings_font_advanced[key]
  end
  if UI.settings_font_advanced[key] then
    UI.settings_note("For unusual installations, enter an installed family name or an absolute .ttf, .otf, or .ttc path.")
    local apply_width = 86
    available_width = UI.settings_inner_width
      or select(1, R.ImGui_GetContentRegionAvail(ctx))
    R.ImGui_SetNextItemWidth(ctx, math.max(140, available_width - apply_width - 10))
    local changed, value = R.ImGui_InputText(ctx, "##custom_" .. key, font_inputs[key])
    if changed then font_inputs[key] = value end
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx, "APPLY##" .. key, apply_width, 0) then
      apply_font_source(key, font_inputs[key])
    end
  end
end

function UI.draw_theme_color(label, key, description)
  local flags = 0
  if R.ImGui_ColorEditFlags_NoAlpha then flags = flags | R.ImGui_ColorEditFlags_NoAlpha() end
  if R.ImGui_ColorEditFlags_DisplayHex then flags = flags | R.ImGui_ColorEditFlags_DisplayHex() end
  if R.ImGui_ColorEditFlags_NoLabel then flags = flags | R.ImGui_ColorEditFlags_NoLabel() end
  UI.settings_row(label, 90, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, control_width)
    local changed, value = R.ImGui_ColorEdit4(
      ctx, "##" .. key, rgba_to_argb(settings[key]), flags)
    if changed then
      settings[key] = argb_to_rgba(value)
      save_color(key, settings[key])
      if key ~= "recording_background" then
        settings.theme_mode = "custom"
        save_string("theme_mode", settings.theme_mode)
      end
      rebuild_palette()
    end
  end)
end

local function reset_appearance()
  settings.regular_font = DEFAULT_APPEARANCE.regular_font
  settings.mono_font = DEFAULT_APPEARANCE.mono_font
  settings.regular_weight = DEFAULT_APPEARANCE.regular_weight
  settings.mono_weight = DEFAULT_APPEARANCE.mono_weight
  settings.regular_size = DEFAULT_APPEARANCE.regular_size
  settings.mono_size = DEFAULT_APPEARANCE.mono_size
  settings.theme_mode = "midnight"
  settings.theme_background = DEFAULT_APPEARANCE.background
  settings.theme_text = DEFAULT_APPEARANCE.text
  settings.theme_highlight = DEFAULT_APPEARANCE.highlight
  settings.background_gradient_strength = DEFAULT_APPEARANCE.background_gradient_strength
  settings.card_background_opacity = DEFAULT_APPEARANCE.card_background_opacity
  settings.background_image_path = DEFAULT_APPEARANCE.background_image_path
  settings.background_image_opacity = DEFAULT_APPEARANCE.background_image_opacity
  settings.card_alignment = DEFAULT_APPEARANCE.card_alignment
  settings.fade_controls = true
  settings.recording_background_enabled = DEFAULT_APPEARANCE.recording_background_enabled
  settings.recording_background = DEFAULT_APPEARANCE.recording_background
  font_inputs.regular_font = settings.regular_font
  font_inputs.mono_font = settings.mono_font
  font_reload_pending = true
  invalidate_background_image()
  background_image_status = ""
  font_status = "Appearance reset to ReaClock defaults."
  request_layout_resize()
  rebuild_palette()
  save_all_settings()
end

local dock_request = settings.dock_id ~= 0 and settings.dock_id or nil
local factory_reset_armed = false
local factory_restart_requested = false
local factory_reset_error

local function factory_reset_all()
  if Store.test_override then
    factory_reset_error = "Factory Reset requires the normal JSON settings path."
    return false
  end
  local cleared, clear_error = Store.clear_all()
  if not cleared then
    factory_reset_error = clear_error or "The settings folder could not be cleared."
    return false
  end
  factory_reset_error = nil
  settings_open, detail_editor.open = false, false
  face_dialog.request, face_dialog.action, face_dialog.close_request = nil, nil, false
  factory_restart_requested = true
  return true
end

function UI.draw_style_settings()
  local regular_extra = UI.settings_font_advanced.regular_font and 58 or 0
  local mono_extra = UI.settings_font_advanced.mono_font and 58 or 0
  local fonts_height = 240 + regular_extra + mono_extra

  UI.settings_columns("style_columns", function(width)
    UI.settings_card("palette", 150, function(inner_width)
      UI.settings_section("Palette",
        "Choose a complete built-in palette, or adjust the colors and fonts to create a custom style.")
      local gap = 6
      local chip_width = (inner_width - gap * 2) / 3
      for index, mode in ipairs(STYLE_PRESET_ORDER) do
        if index > 1 and (index - 1) % 3 ~= 0 then R.ImGui_SameLine(ctx, 0, gap) end
        UI.style_chip(mode, chip_width)
      end
    end)
    UI.settings_gap()

    UI.settings_card("surfaces", 104, function()
      UI.settings_section("Surfaces")
      local _, gradient_hovered = UI.settings_slider_row("Gradient",
        "background_gradient_strength", settings.background_gradient_strength * 100,
        0, 100, function(value) return string.format("%.0f%%", value) end,
        function(value)
          settings.background_gradient_strength = math.max(0, math.min(1, value / 100))
          save_string("background_gradient_strength",
            string.format("%.4f", settings.background_gradient_strength))
        end, 130, "Background gradient",
        "Shapes both the main background and card surfaces. Double-click to restore the 100% default.")
      if gradient_hovered and R.ImGui_IsMouseDoubleClicked(ctx, R.ImGui_MouseButton_Left()) then
        settings.background_gradient_strength = DEFAULT_APPEARANCE.background_gradient_strength
        save_string("background_gradient_strength",
          string.format("%.4f", settings.background_gradient_strength))
      end
      local _, opacity_hovered = UI.settings_slider_row("Card opacity",
        "card_background_opacity", settings.card_background_opacity * 100,
        0, 100, function(value) return string.format("%.0f%%", value) end,
        function(value)
          settings.card_background_opacity = math.max(0, math.min(1, value / 100))
          save_string("card_background_opacity",
            string.format("%.4f", settings.card_background_opacity))
        end, 130, "Card opacity",
        "50% preserves card structure while letting a background image show through. Double-click to restore the default.")
      if opacity_hovered and R.ImGui_IsMouseDoubleClicked(ctx, R.ImGui_MouseButton_Left()) then
        settings.card_background_opacity = DEFAULT_APPEARANCE.card_background_opacity
        save_string("card_background_opacity",
          string.format("%.4f", settings.card_background_opacity))
      end
    end)
    UI.settings_gap()

    UI.settings_card("background_image", 107, function(inner_width)
      UI.settings_section("Background image",
        string.format("Local PNG or JPEG. ReaClock stores only its path and center-crops it to cover the clock face. Default Face crop: %d × %d px. Opacity is capped at 50%% to preserve legibility.",
          BASE_W, math.floor(current_base_height() + 0.5)))
      if UI.settings_outline_button("CHOOSE IMAGE…", "background_image", 116, 27) then
        local selected, path = R.GetUserFileNameForRead(
          settings.background_image_path or "", "Choose a ReaClock background image", "png,jpg,jpeg")
        if selected and path and path ~= "" then
          if is_supported_background_image(path) then
            settings.background_image_path = path
            invalidate_background_image()
            background_image_status = "Selected " .. background_image_filename(path) .. "."
            save_string("background_image_path", path)
          else
            background_image_status = "Choose a PNG, JPG, or JPEG image."
          end
        end
      end
      item_tooltip("Choose a background image",
        "The file stays on your computer and is not copied into ReaClock.")
      R.ImGui_SameLine(ctx, 0, 8)
      R.ImGui_PushFont(ctx, font_regular, 11)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
      local image_label = settings.background_image_path ~= ""
        and background_image_filename(settings.background_image_path) or "No image selected"
      R.ImGui_Text(ctx, truncate_current_font(image_label, inner_width - 132))
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)
      if settings.background_image_path ~= "" then
        item_tooltip("Selected image", settings.background_image_path)
      end

      local disabled = settings.background_image_path == ""
      if disabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
      local _, image_hovered = UI.settings_slider_row("Image opacity",
        "background_image_opacity", settings.background_image_opacity * 100,
        0, 50, function(value) return string.format("%.0f%%", value) end,
        function(value)
          settings.background_image_opacity = math.max(0, math.min(0.5, value / 100))
          save_string("background_image_opacity",
            string.format("%.4f", settings.background_image_opacity))
        end, 130)
      if disabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
      if not disabled and image_hovered
          and R.ImGui_IsMouseDoubleClicked(ctx, R.ImGui_MouseButton_Left()) then
        settings.background_image_opacity = DEFAULT_APPEARANCE.background_image_opacity
        save_string("background_image_opacity",
          string.format("%.4f", settings.background_image_opacity))
      end
    end)
    UI.settings_gap()

    UI.settings_card("style_interface", 106, function()
      UI.settings_section("Interface")
      settings_checkbox("Fade interface controls when idle", "fade_controls")
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Fade interface controls when idle",
        "Keeps the performance view quiet. Fullscreen, Edit, and Settings recede farther when ReaClock is unfocused, then restore when the clock is focused or hovered.")
      UI.settings_combo("Card alignment", "card_alignment", {
        { "left", "Left" }, { "center", "Center" }, { "right", "Right" },
      })
    end)
  end, function(width)
    UI.settings_card("custom_colors", 188, function()
      UI.settings_section("Custom colors",
        "Built-in styles use hand-tuned cards, borders, labels, controls, and accent sets. Custom styles derive those supporting colors from these anchors.")
      UI.draw_theme_color("Background", "theme_background",
        "Clock face and Settings surface.")
      UI.draw_theme_color("Text", "theme_text",
        "Clock, names, labels, and supporting text.")
      UI.draw_theme_color("Highlight", "theme_highlight",
        "Progress, selected controls, and active accents.")
      settings_checkbox("Different background while recording", "recording_background_enabled")
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Recording background",
        "A muted dark red by default. ReaClock automatically preserves readable text contrast.")
      local recording_disabled = not settings.recording_background_enabled
      if recording_disabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
      UI.draw_theme_color("Recording", "recording_background",
        "The alternate clock background used while recording.")
      if recording_disabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
    end)
    UI.settings_gap()

    UI.settings_card("fonts", fonts_height, function()
      UI.settings_section("Fonts",
        "Installed font folders are scanned only when a chooser is opened; results stay in memory until Rescan or restart. Installed faces can be selected directly.")
      UI.draw_font_selector("Regular text", "regular_font",
        "Names, labels, buttons, and Settings.")
      UI.draw_font_selector("Numeric display", "mono_font",
        "Main clock and numeric cards.")
      if icon_font_status ~= "" then UI.settings_note(icon_font_status, C.danger) end
      if font_status ~= "" and (font_status:match("not found") or font_status:match("could not")) then
        UI.settings_note(font_status, C.danger)
      end
    end)
    UI.settings_gap()

    UI.settings_card("reset_appearance", 53, function()
      if not UI.settings_appearance_reset_armed then
        UI.settings_action_row(
          "Restores the built-in style, surfaces, colors, and fonts to their defaults.",
          "RESET APPEARANCE…", "reset_appearance", 144, true,
          function() UI.settings_appearance_reset_armed = true end)
      else
        UI.settings_confirm_action_row("Restore the complete default appearance?",
          "CONFIRM RESET", "confirm_appearance", 124,
          "CANCEL", "cancel_appearance", 72,
          function()
            reset_appearance()
            UI.settings_appearance_reset_armed = false
          end,
          function() UI.settings_appearance_reset_armed = false end)
      end
    end, { dashed = true, transparent = true, compact = true })
  end)
end

function UI.draw_compact_docking_control()
  local label = settings.dock_id == 0 and "Floating" or ("REAPER Docker " .. -settings.dock_id)
  UI.settings_row("Location", 130, function(control_width)
    R.ImGui_SetNextItemWidth(ctx, control_width)
    if R.ImGui_BeginCombo(ctx, "##compact_dock_id", label) then
      if R.ImGui_Selectable(ctx, "Floating##compact_dock_float", settings.dock_id == 0) then
        settings.dock_id, dock_request = 0, 0
        save_string("dock_id", 0)
      end
      for index = 1, 16 do
        local value = -index
        if R.ImGui_Selectable(ctx, "REAPER Docker " .. index .. "##compact_dock_" .. index,
            settings.dock_id == value) then
          settings.dock_id, dock_request = value, value
          save_string("dock_id", value)
        end
      end
      R.ImGui_EndCombo(ctx)
    end
  end)
end

function UI.draw_clock_page()
  UI.settings_columns("clock_page", function()
    UI.settings_card("clock_behavior", 65, function()
      UI.settings_section("Clock behavior")
      settings_checkbox("Hide Tempo & Time Signature cards when grid is off",
        "hide_tempo_without_grid")
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Grid-aware cards",
        "Only direct Tempo and Time Signature cards are affected; custom templates remain visible.")
    end)
    UI.settings_gap()

    UI.settings_card("outside_regions", 108, function()
      UI.settings_section("Outside regions",
        "Region mode stays blank outside regions unless you choose Next cue or Overtime. Right-click an upcoming card to choose Regions, Markers, or Both.")
      UI.settings_combo("Display", "gap_mode", {
        { "blank", "Blank (default)" },
        { "next", "Show next cue countdown" },
        { "overtime", "Show previous-region overtime" },
      })
      UI.settings_row("Warning threshold", 130, function(control_width)
        R.ImGui_SetNextItemWidth(ctx, control_width)
        local changed, warning = R.ImGui_InputDouble(ctx, "##cue_warning_compact",
          settings.cue_warning_seconds, 1, 5, "%.1f s")
        if changed then
          settings.cue_warning_seconds = math.max(0, math.min(300, warning))
          save_string("cue_warning_seconds", string.format("%.3f", settings.cue_warning_seconds))
          recompute_snapshot(true)
        end
      end)
    end)
    UI.settings_gap()

    UI.settings_card("calibration", 128, function(inner_width)
      UI.settings_section("Calibration",
        "Positive values advance the displayed clock; negative values delay it. The offset also moves region transitions and the visual click.")
      UI.settings_row("Offset", 130, function()
        UI.settings_segmented("offset_unit", {
          { "ms", "MS", 38 }, { "samples", "SAMPLES", 70 },
        }, settings.offset_unit, convert_offset_unit, 54, 21)
      end)

      local reset_width = 58
      R.ImGui_SetNextItemWidth(ctx, math.max(160, inner_width - reset_width - 8))
      if settings.offset_unit == "samples" then
        local current = round_pixel(settings.offset_value)
        local changed, value = R.ImGui_InputInt(ctx, "##offset_samples_compact", current, 1, 64)
        if changed then
          settings.offset_value = value
          save_string("offset_value", value)
          recompute_snapshot(true)
        end
      else
        local changed, value = R.ImGui_InputDouble(ctx, "##offset_milliseconds_compact",
          settings.offset_value, 0.1, 10, "%.3f ms")
        if changed then
          settings.offset_value = value
          save_string("offset_value", string.format("%.12f", value))
          recompute_snapshot(true)
        end
      end
      R.ImGui_SameLine(ctx, 0, 6)
      if UI.settings_outline_button("RESET", "offset_reset", reset_width, 25) then
        settings.offset_value = 0
        save_string("offset_value", "0")
        recompute_snapshot(true)
      end

      local sample_rate, sample_rate_source = active_sample_rate()
      R.ImGui_PushFont(ctx, font_mono, 10)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
      R.ImGui_Text(ctx, string.format("%.0f Hz · effective %+.6f s",
        sample_rate, offset_seconds()))
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)
    end)
  end, function()
    UI.settings_card("visual_click", 185, function()
      UI.settings_section("Visual click")
      settings_checkbox("Perimeter click pulse", "visual_click")
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Perimeter click pulse",
        "The entire edge pulses without covering the clock; downbeats are brighter and thicker. Intensity affects both the card flash and the perimeter pulse.")
      local disabled = not settings.visual_click
      if disabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
      UI.settings_combo("Activation", "click_activation", {
        { "playing", "Whenever transport plays" },
        { "grid", "Playing + grid lines on" },
        { "metronome", "Playing + metronome on" },
      })
      UI.settings_slider_row("Pulse decay", "click_decay_compact",
        settings.click_decay_ms, 60, 300,
        function(value) return string.format("%.0f ms", value) end,
        function(value)
          settings.click_decay_ms = value
          save_string("click_decay_ms", string.format("%.3f", value))
        end, 130)
      UI.settings_slider_row("Flash intensity", "click_intensity_compact",
        settings.click_intensity * 100, 25, 100,
        function(value) return string.format("%.0f%%", value) end,
        function(value)
          settings.click_intensity = value / 100
          save_string("click_intensity", string.format("%.4f", settings.click_intensity))
        end, 130)
      if disabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
      UI.settings_note("Follows the calibration offset, so rim and beat display stay aligned.")
    end)
    UI.settings_gap()

    UI.settings_card("metering_link", 49, function()
      UI.settings_action_row(
        "Meter companion status, detected sources, and project cleanup.",
        "ADVANCED…", "open_metering", 94, false,
        function() UI.settings_page = "metering" end)
    end, { compact = true })
    UI.settings_gap()

    local reset_height = factory_reset_armed and 53 or 67
    if factory_reset_error then reset_height = reset_height + 18 end
    UI.settings_card("factory_reset", reset_height, function()
      if factory_reset_error then UI.settings_note(factory_reset_error, C.danger) end
      if not factory_reset_armed then
        UI.settings_action_row(
          "Deletes all preferences and saved UI state, then reopens like a fresh install. Meter FX remain in REAPER.",
          "FACTORY RESET…", "factory_reset", 120, true,
          function() factory_reset_armed = true end)
      else
        UI.settings_confirm_action_row(
          "This clears every preference and saved UI state.",
          "CONFIRM RESET", "confirm_factory_reset", 126,
          "CANCEL", "cancel_factory_reset", 72,
          function()
            if factory_reset_all() then factory_reset_armed = false end
          end,
          function() factory_reset_armed = false end)
      end
    end, { dashed = true, transparent = true, compact = true })
  end)
end

function UI.draw_face_page()
  UI.settings_columns("face_page", function()
    UI.settings_card("main_clock", 121, function()
      UI.settings_section("Main clock")
      if settings_checkbox("Show main clock", "show_main_clock") then
        Content.save_active_face()
        request_layout_resize()
      end
      UI.settings_row("Size", 130, function(control_width)
        local current = Runtime.clock_sizes[settings.main_clock_size]
          or Runtime.clock_sizes.huge
        R.ImGui_SetNextItemWidth(ctx, control_width)
        if R.ImGui_BeginCombo(ctx, "##main_clock_size_compact", current.label) then
          for _, size_id in ipairs(Runtime.clock_sizes.order) do
            local option = Runtime.clock_sizes[size_id]
            if R.ImGui_Selectable(ctx, option.label .. "##main_clock_compact_" .. size_id,
                settings.main_clock_size == size_id) then
              Content.set_main_clock_size(size_id)
            end
          end
          R.ImGui_EndCombo(ctx)
        end
      end)
      if settings_checkbox("Show progress bar", "show_progress") then
        Content.save_active_face()
        request_layout_resize()
      end
    end)
    UI.settings_gap()

    UI.settings_card("window", 150, function()
      UI.settings_section("Window",
        "Floating windows stay inside the monitor work area; oversized windows are reduced automatically. Automatic fit preserves width and adjusts height as rows change. Use the fullscreen button for Presentation mode.")
      UI.draw_compact_docking_control()
      settings_checkbox("Keep clock always on top", "always_on_top")
      if settings_checkbox("Automatically fit height to content", "fit_window_to_content") then
        request_layout_resize()
      end
      settings_checkbox("Enable keyboard shortcuts", "keyboard_shortcuts_enabled")
      R.ImGui_SameLine(ctx, 0, 7)
      UI.settings_info("Keyboard shortcuts",
        "Shortcuts are suspended while Settings, an editor, a dialog, or a popup is active, so typing never changes the clock unexpectedly.")
    end)
  end, function()
    UI.settings_card("layout", 283, function(inner_width)
      UI.settings_section("Layout",
        "Switch or save Clock Faces from the Face menu on the clock. Use Edit on the clock to change content, order, row size, card width, or card count directly.")
      UI.settings_row("Rows", 70, function()
        R.ImGui_SetNextItemWidth(ctx, 110)
        if R.ImGui_BeginCombo(ctx, "##layout_rows_compact", tostring(settings.card_rows)) then
          for rows = 0, MAX_CARD_ROWS do
            if R.ImGui_Selectable(ctx, tostring(rows) .. "##layout_rows_compact_" .. rows,
                rows == settings.card_rows) then Content.set_card_rows(rows) end
          end
          R.ImGui_EndCombo(ctx)
        end
      end)

      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ChildBg(), 0x00000000)
      R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
      local child_visible = R.ImGui_BeginChild(ctx, "##layout_rows_scroll", 0, 118, 0)
      if child_visible then
        if settings.card_rows == 0 then
          UI.settings_note("No card rows are visible.")
        end
        for row = 1, settings.card_rows do
          local row_x, row_y = R.ImGui_GetCursorScreenPos(ctx)
          R.ImGui_PushFont(ctx, font_mono, 10)
          R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
          R.ImGui_AlignTextToFramePadding(ctx)
          R.ImGui_Text(ctx, "ROW " .. row)
          R.ImGui_PopStyleColor(ctx)
          R.ImGui_PopFont(ctx)

          local label_width, gap = 62, 8
          local combo_width = (inner_width - label_width - gap) * 0.5
          R.ImGui_SetCursorScreenPos(ctx, row_x + label_width, row_y)
          local count = settings.card_row_counts[row]
          R.ImGui_SetNextItemWidth(ctx, combo_width)
          if R.ImGui_BeginCombo(ctx, "##layout_count_compact_" .. row,
              count .. (count == 1 and " card" or " cards")) then
            for option_count = 1, CARDS_PER_ROW do
              local enabled = option_count <= count
                or Content.row_required_units(row) + (option_count - count) <= CARDS_PER_ROW
              if not enabled and R.ImGui_BeginDisabled then R.ImGui_BeginDisabled(ctx) end
              if R.ImGui_Selectable(ctx, tostring(option_count) .. "##layout_count_compact_"
                  .. row .. "_" .. option_count, option_count == count) and enabled then
                Content.set_row_count(row, option_count)
              end
              if not enabled and R.ImGui_EndDisabled then R.ImGui_EndDisabled(ctx) end
            end
            R.ImGui_EndCombo(ctx)
          end
          R.ImGui_SameLine(ctx, 0, gap)
          local size_id = settings.card_row_sizes[row]
          R.ImGui_SetNextItemWidth(ctx, combo_width)
          if R.ImGui_BeginCombo(ctx, "##layout_size_compact_" .. row,
              ROW_SIZE_OPTIONS[size_id].label) then
            for _, option_id in ipairs(ROW_SIZE_ORDER) do
              if R.ImGui_Selectable(ctx, ROW_SIZE_OPTIONS[option_id].label
                  .. "##layout_size_compact_" .. row .. "_" .. option_id,
                  option_id == size_id) then Content.set_row_size(row, option_id) end
            end
            R.ImGui_EndCombo(ctx)
          end
        end
      end
      R.ImGui_EndChild(ctx)
      R.ImGui_PopStyleVar(ctx)
      R.ImGui_PopStyleColor(ctx)

      local button_x, button_y = R.ImGui_GetCursorScreenPos(ctx)
      R.ImGui_SetCursorScreenPos(ctx, button_x + inner_width - 103, button_y)
      if UI.settings_outline_button("RESET LAYOUT", "reset_layout", 103, 27) then
        Content.reset_cards()
      end
    end)
  end)
end

function UI.draw_metering_page()
  local paths = Metering.companion_paths()
  local state, now = Runtime.metering, R.time_precise()
  if now - (state.last_companion_check or -math.huge) >= 2 then Metering.ensure_companion() end
  local installed = state.companion_installed or Metering.inspect_companion(paths.destination)
  local repair_copy = state.companion_repair_copy or Metering.inspect_companion(paths.bundled)
  Metering.scan_sources(false)
  local compatible, update_pending, update_required, monitoring = 0, 0, 0, 0
  for _, source in ipairs(Runtime.metering.sources or {}) do
    if source.bridge_compatible then
      compatible = compatible + 1
      if not source.current_build then update_pending = update_pending + 1 end
    else
      update_required = update_required + 1
    end
    if source.kind == "monitoring" then monitoring = monitoring + 1 end
  end

  local function companion_detail(result)
    if result.markers then
      return string.format("API %d · BUILD %d · %s",
        result.markers.api, result.markers.build, result.markers.checksum)
    end
    return result.detail or "Unavailable"
  end

  local operation = Runtime.metering.operation_status or Runtime.metering.operation_error
  local companion_height = operation and 176 or 154
  local cleanup_height = Runtime.metering.cleanup_armed and 104
    or (Runtime.metering.cleanup_status or Runtime.metering.cleanup_error) and 112 or 90

  UI.settings_columns("metering_page", function()
    UI.settings_card("meter_companion", companion_height, function()
      UI.settings_section("Meter companion",
        "ReaClock checks the exact API, build, and content checksum at startup and before adding a source. Missing, older, or damaged copies are repaired automatically; a newer copy is never downgraded. ReaPack installs and updates the packaged source.")
      UI.settings_status_row(installed.ready and "Installed copy verified" or "Installed copy not ready",
        companion_detail(installed), installed.ready and C.accent or C.danger, installed.detail)
      UI.settings_status_row(repair_copy.ready and "Repair copy verified" or "Repair copy not ready",
        companion_detail(repair_copy), repair_copy.ready and C.accent or C.danger, repair_copy.detail)
      UI.settings_divider()
      UI.settings_path_row("Effects", paths.destination)
      UI.settings_path_row("Repair", paths.bundled)
      if operation then
        UI.settings_note(operation,
          Runtime.metering.operation_error and C.danger or C.accent_secondary_text)
      end
    end)
    UI.settings_gap()

    UI.settings_card("package_management", 88, function()
      UI.settings_section("Package management",
        "ReaPack owns the packaged repair copy under Resources; package updates replace it automatically and uninstall removes it. The active Effects copy is separate.")
      UI.settings_note("ReaPack owns the repair copy; the active Effects copy stays available to existing project and Monitoring FX chains even after uninstall.")
    end)
  end, function()
    UI.settings_card("detected_sources", 84, function()
      UI.settings_section("Detected sources",
        "Add or select Monitoring FX, track, and master sources from a Metering card editor. This page remains available even when no Metering cards exist.")
      local summary = string.format("%d usable source%s · active project + Monitoring FX",
        compatible, compatible == 1 and "" or "s")
      if update_required > 0 then summary = summary .. string.format(" · %d update required", update_required) end
      if update_pending > 0 then summary = summary .. string.format(" · %d update pending", update_pending) end
      UI.settings_status_row(summary, "", update_required > 0 and C.danger or C.accent)
      UI.settings_note(string.format("%d persistent Monitoring FX meter%s included.",
        monitoring, monitoring == 1 and "" or "s"))
    end)
    UI.settings_gap()

    UI.settings_card("project_cleanup", cleanup_height, function()
      UI.settings_section("Project cleanup",
        "Reviews only the active project. Compatible track and master meters referenced by any saved Clock Face are preserved; Monitoring FX is never removed here. The action is undoable.")
      if Runtime.metering.cleanup_status then
        UI.settings_note(Runtime.metering.cleanup_status, C.accent_secondary_text)
      elseif Runtime.metering.cleanup_error then
        UI.settings_note(Runtime.metering.cleanup_error, C.danger)
      end
      if not Runtime.metering.cleanup_armed then
        UI.settings_action_row(
          "Removes only unreferenced track/master meters in the active project.",
          "REVIEW UNUSED METERS…", "review_unused_meters", 170, false,
          function()
            local candidates = Metering.unused_ordinary_sources()
            if #candidates == 0 then
              Runtime.metering.cleanup_status = "No unused track meters were found in the active project."
              Runtime.metering.cleanup_error = nil
            else
              Runtime.metering.cleanup_armed = #candidates
              Runtime.metering.cleanup_status, Runtime.metering.cleanup_error = nil, nil
            end
          end)
      else
        local count = Runtime.metering.cleanup_armed
        UI.settings_confirm_action_row(
          string.format("Remove %d unused track meter%s? Monitoring FX will remain installed.",
            count, count == 1 and "" or "s"),
          "REMOVE UNUSED METERS", "remove_unused_meters", 170,
          "CANCEL", "cancel_unused_meters", 72,
          function()
            local okay, detail = Metering.cleanup_unused_ordinary_sources()
            Runtime.metering.cleanup_status = okay and detail or nil
            Runtime.metering.cleanup_error = not okay and detail or nil
            Runtime.metering.cleanup_armed = nil
          end,
          function() Runtime.metering.cleanup_armed = nil end)
      end
    end)
  end)
end

-- Compact card-based Settings surface from Dev/Design/Settings Redesign.dc.html.
function UI.draw_settings_window()
  if not settings_open then
    if Runtime.settings_window_was_open then
      factory_reset_armed = false
      UI.settings_appearance_reset_armed = false
      Runtime.metering.cleanup_armed = nil
    end
    Runtime.settings_window_was_open = false
    return
  end
  local settings_newly_opened = not Runtime.settings_window_was_open
  Runtime.settings_window_was_open = true

  if settings_tab_request then
    local requested = settings_tab_request
    UI.settings_page = requested == "appearance" and "style"
      or requested == "metering" and "metering"
      or requested == "face" and "face" or "clock"
    settings_tab_request = nil
  end
  UI.settings_info_index = 0

  -- Resolve status before calculating the Metering page height so an operation
  -- message cannot make the card grow one frame after the window does.
  if UI.settings_page == "metering" then
    local metering_state, now = Runtime.metering, R.time_precise()
    if now - (metering_state.last_companion_check or -math.huge) >= 2 then
      Metering.ensure_companion()
    end
    Metering.scan_sources(false)
  end

  local function page_inner_height()
    if UI.settings_page == "clock" then
      local reset_height = factory_reset_armed and 53 or 67
      if factory_reset_error then reset_height = reset_height + 18 end
      return math.max(325, 185 + 12 + 49 + 12 + reset_height) + 5
    elseif UI.settings_page == "face" then
      return 287
    elseif UI.settings_page == "style" then
      local font_height = 240
        + (UI.settings_font_advanced.regular_font and 58 or 0)
        + (UI.settings_font_advanced.mono_font and 58 or 0)
      local reset_height = 53
      return math.max(503, 188 + 12 + font_height + 12 + reset_height) + 6
    end
    local companion_height = (Runtime.metering.operation_status
      or Runtime.metering.operation_error) and 176 or 154
    local cleanup_height = Runtime.metering.cleanup_armed and 104
      or (Runtime.metering.cleanup_status or Runtime.metering.cleanup_error) and 112 or 90
    return math.max(companion_height + 12 + 88, 84 + 12 + cleanup_height) + 1
  end

  local warning_extra = (Store.warning and 24 or 0) + (Store.error and 24 or 0)
  local inner_height = page_inner_height()
  local body_height = UI.settings_layout.body_padding * 2 + warning_extra + inner_height
  local nav_height = UI.settings_page == "metering" and 40
    or UI.settings_layout.nav_height
  local total_height = UI.settings_layout.header_height
    + nav_height + body_height
  R.ImGui_SetNextWindowSize(ctx, UI.settings_layout.width, total_height, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSizeConstraints(ctx,
    UI.settings_layout.width, total_height, UI.settings_layout.width, total_height)
  local owner = Runtime.settings_owner_geometry
  local previous_geometry = Runtime.settings_window_geometry
  local previous_height = Runtime.settings_window_height
  local height_changed = previous_height
    and math.abs(previous_height - total_height) > 0.5
  if settings_newly_opened and owner then
    R.ImGui_SetNextWindowPos(ctx, owner.x + owner.w * 0.5,
      owner.y + owner.h * 0.5, R.ImGui_Cond_Appearing(), 0.5, 0.5)
  elseif height_changed and previous_geometry then
    local target_x = previous_geometry.x + previous_geometry.w * 0.5
      - UI.settings_layout.width * 0.5
    local target_y = previous_geometry.y + previous_geometry.h * 0.5
      - total_height * 0.5
    local bounds = window_work_area(previous_geometry.x, previous_geometry.y,
      previous_geometry.w, previous_geometry.h)
    if bounds then
      local inset = 8
      local min_x, min_y = bounds.left + inset, bounds.top + inset
      local max_x = math.max(min_x, bounds.right - UI.settings_layout.width - inset)
      local max_y = math.max(min_y, bounds.bottom - total_height - inset)
      target_x = math.max(min_x, math.min(max_x, target_x))
      target_y = math.max(min_y, math.min(max_y, target_y))
    end
    R.ImGui_SetNextWindowPos(ctx, target_x, target_y, R.ImGui_Cond_Always())
  end
  Runtime.settings_window_height = total_height

  local palette = UI.settings_palette()
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), C.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.ink)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBg(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_FrameBgActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_CheckMark(), readable_on(C.accent))
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Button(), palette.control)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonHovered(), C.inactive_hover)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ButtonActive(), C.inactive_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), palette.subtle_border)
  local optional_colors = 0
  local function push_optional_color(api, color)
    if type(api) ~= "function" then return end
    R.ImGui_PushStyleColor(ctx, api(), color)
    optional_colors = optional_colors + 1
  end
  push_optional_color(R.ImGui_Col_Header, C.inactive_active)
  push_optional_color(R.ImGui_Col_HeaderHovered, C.inactive_hover)
  push_optional_color(R.ImGui_Col_HeaderActive, C.toggle_selected)
  push_optional_color(R.ImGui_Col_PopupBg, C.surface)
  push_optional_color(R.ImGui_Col_ChildBg, 0x00000000)
  push_optional_color(R.ImGui_Col_SliderGrab, C.accent)
  push_optional_color(R.ImGui_Col_SliderGrabActive, C.accent_hover)
  push_optional_color(R.ImGui_Col_Separator, palette.subtle_border)
  push_optional_color(type(R.ImGui_Col_NavCursor) == "function"
    and R.ImGui_Col_NavCursor or R.ImGui_Col_NavHighlight, C.accent)

  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing(), 7, 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FrameRounding(), 5)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), 8, 4)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowRounding(), 10)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 1)
  R.ImGui_PushFont(ctx, font_regular, 12)

  local flags = R.ImGui_WindowFlags_NoCollapse()
    | R.ImGui_WindowFlags_NoDocking()
    | R.ImGui_WindowFlags_NoTitleBar()
    | R.ImGui_WindowFlags_NoResize()
    | R.ImGui_WindowFlags_NoScrollbar()
    | R.ImGui_WindowFlags_NoScrollWithMouse()
  -- Settings is an auxiliary tool window. Keep it above the clock for its
  -- lifetime instead of allowing a click on the clock to hide it.
  if type(R.ImGui_WindowFlags_TopMost) == "function" then
    flags = flags | R.ImGui_WindowFlags_TopMost()
  end
  local visible
  visible, settings_open = R.ImGui_Begin(ctx,
    "ReaClock Settings###ReaClockSettings", settings_open, flags)

  if visible then
    if Store.warning then Store.warning_acknowledged = true end
    local settings_x, settings_y = R.ImGui_GetWindowPos(ctx)
    local settings_w, settings_h = R.ImGui_GetWindowSize(ctx)
    Runtime.settings_window_geometry = {
      x = settings_x, y = settings_y, w = settings_w, h = settings_h,
    }
    local origin_x, origin_y = R.ImGui_GetCursorScreenPos(ctx)
    local window_width = select(1, R.ImGui_GetContentRegionAvail(ctx))
    local draw_list = R.ImGui_GetWindowDrawList(ctx)

    R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, origin_y + 13)
    R.ImGui_PushFont(ctx, font_bold, 13)
    R.ImGui_Text(ctx, "ReaClock Settings")
    R.ImGui_PopFont(ctx)

    local function draw_header_line(offset_y, prefix, link, suffix, url, tooltip_title)
      R.ImGui_PushFont(ctx, font_regular, 10)
      local prefix_w = R.ImGui_CalcTextSize(ctx, prefix)
      local link_w = R.ImGui_CalcTextSize(ctx, link)
      local suffix_w = R.ImGui_CalcTextSize(ctx, suffix)
      local total = prefix_w + link_w + suffix_w
      local right = origin_x + window_width - 42
      R.ImGui_SetCursorScreenPos(ctx, right - total, origin_y + offset_y)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
      R.ImGui_Text(ctx, prefix)
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_SameLine(ctx, 0, 0)
      if R.ImGui_Col_TextLink then
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TextLink(), palette.label)
      end
      R.ImGui_TextLinkOpenURL(ctx, link, url)
      if R.ImGui_Col_TextLink then R.ImGui_PopStyleColor(ctx) end
      item_tooltip(tooltip_title, "Open " .. url .. " in your browser.")
      if suffix ~= "" then
        R.ImGui_SameLine(ctx, 0, 0)
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), C.muted)
        R.ImGui_Text(ctx, suffix)
        R.ImGui_PopStyleColor(ctx)
      end
      R.ImGui_PopFont(ctx)
    end
    draw_header_line(11, "PROVIDED FREE BY ", "MICHAEL BRIGGS MASTERING", "",
      "https://michaelbriggsmastering.com", "Michael Briggs Mastering")
    draw_header_line(26, "TRY ", "REAASSIST", " TO CONTROL YOUR SESSIONS",
      "https://reaassist.app", "Explore ReaAssist")

    local close_x, close_y, close_size = origin_x + window_width - 29, origin_y + 12, 16
    R.ImGui_SetCursorScreenPos(ctx, close_x, close_y)
    if R.ImGui_InvisibleButton(ctx, "##close_settings", close_size, close_size) then
      settings_open = false
    end
    local close_color = R.ImGui_IsItemHovered(ctx) and C.ink or C.muted
    R.ImGui_DrawList_AddLine(draw_list, close_x + 4, close_y + 4,
      close_x + 12, close_y + 12, close_color, 1.1)
    R.ImGui_DrawList_AddLine(draw_list, close_x + 12, close_y + 4,
      close_x + 4, close_y + 12, close_color, 1.1)

    local nav_y = origin_y + UI.settings_layout.header_height
    R.ImGui_SetCursorScreenPos(ctx, origin_x + 14, nav_y + 5)
    if UI.settings_page == "metering" then
      UI.settings_segmented("settings_back", { { "back", "‹  BACK" } }, "back",
        function() UI.settings_page = "clock" end, 76, 25)
      R.ImGui_SetCursorScreenPos(ctx, origin_x + 104, nav_y + 13)
      R.ImGui_PushFont(ctx, font_bold, 11)
      R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), palette.label)
      R.ImGui_Text(ctx, "ADVANCED · METERING")
      R.ImGui_PopStyleColor(ctx)
      R.ImGui_PopFont(ctx)
    else
      UI.settings_segmented("settings_pages", {
        { "clock", "CLOCK" }, { "face", "FACE" }, { "style", "STYLE" },
      }, UI.settings_page, function(page) UI.settings_page = page end, 68, 25)
    end

    local body_y = origin_y + UI.settings_layout.header_height
      + nav_height
    local body_rounding, body_rounding_flags = 0, 0
    if type(R.ImGui_DrawFlags_RoundCornersBottom) == "function" then
      body_rounding = 10
      body_rounding_flags = R.ImGui_DrawFlags_RoundCornersBottom()
    end
    R.ImGui_DrawList_AddRectFilled(draw_list, origin_x, body_y,
      origin_x + window_width, body_y + body_height, palette.body,
      body_rounding, body_rounding_flags)
    R.ImGui_DrawList_AddLine(draw_list, origin_x, body_y,
      origin_x + window_width, body_y, palette.subtle_border, 1)
    local content_offset_y = UI.settings_page == "metering" and 0 or 3
    R.ImGui_SetCursorScreenPos(ctx, origin_x + UI.settings_layout.body_padding,
      body_y + UI.settings_layout.body_padding + content_offset_y)

    if Store.warning then
      UI.settings_note(Store.warning, C.accent_text)
      R.ImGui_Dummy(ctx, 0, 4)
    end
    if Store.error then
      UI.settings_note(Store.error, C.danger)
      R.ImGui_Dummy(ctx, 0, 4)
    end

    if UI.settings_page == "clock" then
      UI.draw_clock_page()
    elseif UI.settings_page == "face" then
      UI.draw_face_page()
    elseif UI.settings_page == "style" then
      UI.draw_style_settings()
    else
      UI.draw_metering_page()
    end

    R.ImGui_SetCursorScreenPos(ctx, origin_x, body_y + body_height)
    R.ImGui_Dummy(ctx, window_width, 0)
  end

  R.ImGui_End(ctx)
  R.ImGui_PopFont(ctx)
  R.ImGui_PopStyleVar(ctx, 6)
  R.ImGui_PopStyleColor(ctx, 10 + optional_colors)
end

-- -----------------------------------------------------------------------------
-- Main loop
-- -----------------------------------------------------------------------------

local base_main_flags = R.ImGui_WindowFlags_NoCollapse()
  | R.ImGui_WindowFlags_NoScrollbar()
  | R.ImGui_WindowFlags_NoScrollWithMouse()
  -- ReaClock owns its geometry in settings.json. Do not let a stale ImGui ini
  -- viewport override the saved position or collapse the restored size.
  | R.ImGui_WindowFlags_NoSavedSettings()
local main_geometry
local presentation_restore
local presentation_bounds
local forced_window_geometry

local function find_presentation_bounds(x, y, w, h)
  if not R.my_getViewport then
    return { left = x, top = y, right = x + w, bottom = y + h }
  end
  local native_x, native_y = native_pixel(x), native_pixel(y)
  local native_right, native_bottom = native_pixel(x + w), native_pixel(y + h)
  local left, top, right, bottom = R.my_getViewport(
    0, 0, 0, 0, native_x, native_y, native_right, native_bottom, false)
  if not finite_number(left) or not finite_number(top)
      or not finite_number(right) or not finite_number(bottom)
      or right <= left or bottom <= top then
    return { left = x, top = y, right = x + w, bottom = y + h }
  end
  return { left = left, top = top, right = right, bottom = bottom }
end

function Content.draw_card_fullscreen_window()
  local state = Runtime.card_fullscreen
  if not state then return end
  local config, resolved = settings.cards[state.index], snapshot.cards[state.index]
  if not config or not resolved or not resolved.visualization then
    Runtime.card_fullscreen = nil
    return
  end
  local source = state.index < 0 and Content.detached_entry(state.index) or main_geometry
  source = source or Runtime.settings_owner_geometry
    or { x = 100, y = 100, w = 918, h = 600 }
  local bounds = find_presentation_bounds(
    source.x or 100, source.y or 100, source.w or 918, source.h or 600)
  local x, y = bounds.left, bounds.top
  local w, h = bounds.right - bounds.left, bounds.bottom - bounds.top
  R.ImGui_SetNextWindowPos(ctx, x, y, R.ImGui_Cond_Always())
  R.ImGui_SetNextWindowSize(ctx, w, h, R.ImGui_Cond_Always())
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), C.outer)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 0)
  local flags = R.ImGui_WindowFlags_NoDecoration()
    | R.ImGui_WindowFlags_NoMove() | R.ImGui_WindowFlags_NoResize()
    | R.ImGui_WindowFlags_NoDocking() | R.ImGui_WindowFlags_NoSavedSettings()
    | R.ImGui_WindowFlags_NoScrollbar() | R.ImGui_WindowFlags_NoScrollWithMouse()
  if type(R.ImGui_WindowFlags_TopMost) == "function" then
    flags = flags | R.ImGui_WindowFlags_TopMost()
  end
  local visible = R.ImGui_Begin(ctx,
    "Fullscreen Visualization###ReaClockCardFullscreen", true, flags)
  if visible then
    local ox, oy = R.ImGui_GetCursorScreenPos(ctx)
    local available_w, available_h = R.ImGui_GetContentRegionAvail(ctx)
    local scale = math.max(0.75, math.min(6,
      math.min(available_w / 900, available_h / 500)))
    Runtime.card_fullscreen_rendering = true
    Content.draw_grid_card(R.ImGui_GetWindowDrawList(ctx), scale,
      ox, oy, 0, 0, available_w / scale, available_h / scale,
      1, state.index, resolved, false, 1, ROW_SIZE_OPTIONS.visualizer)
    Runtime.card_fullscreen_rendering = false
    if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape()) then
      Runtime.card_fullscreen = nil
    end
  end
  R.ImGui_End(ctx)
  R.ImGui_PopStyleVar(ctx, 2)
  R.ImGui_PopStyleColor(ctx)
end

local function presentation_window_rect(bounds)
  return bounds.left, bounds.top,
    bounds.right - bounds.left, bounds.bottom - bounds.top
end

local function fit_presentation_face_rect(bounds, vertical_position)
  local viewport_w = bounds.right - bounds.left
  local viewport_h = bounds.bottom - bounds.top
  local aspect = current_aspect_ratio()
  -- The native Presentation window fills the monitor. This rectangle tracks
  -- the largest complete face within that canvas so dragging can adjust only
  -- the face's relative vertical position without exposing the desktop.
  local target_w, target_h = viewport_w, viewport_w / aspect
  if target_h > viewport_h then
    target_h = viewport_h
    target_w = target_h * aspect
  end
  local vertical_room = math.max(0, viewport_h - target_h)
  vertical_position = math.max(0, math.min(1, vertical_position or 0.5))
  return bounds.left + (viewport_w - target_w) * 0.5,
    bounds.top + vertical_room * vertical_position, target_w, target_h
end

local function process_presentation_request()
  if presentation_request == "enter" and not presentation_mode then
    local geometry = main_geometry or {
      x = saved_window.x or 100, y = saved_window.y or 100,
      w = saved_window.w or 918, h = saved_window.h or 600,
    }
    edit_mode = false
    presentation_restore = { x = geometry.x, y = geometry.y, w = geometry.w, h = geometry.h }
    presentation_bounds = find_presentation_bounds(
      geometry.x, geometry.y, geometry.w, geometry.h)
    local x, y, w, h = presentation_window_rect(presentation_bounds)
    forced_window_geometry = { x = x, y = y, w = w, h = h }
    presentation_mode = true
    settings_open = false
    detail_editor.open = false
  elseif presentation_request == "exit" and presentation_mode then
    presentation_mode = false
    forced_window_geometry = presentation_restore
    presentation_bounds = nil
    presentation_drag.active = false
    presentation_drag.origin_y = nil
    presentation_drag.target_y = nil
  end
  presentation_request = nil
end

local function current_main_flags()
  local flags = base_main_flags
  local auxiliary_window_open = settings_open or detail_editor.open
  if (settings.always_on_top and not auxiliary_window_open) or presentation_mode then
    flags = flags | R.ImGui_WindowFlags_TopMost()
  end
  if presentation_mode then
    flags = flags | R.ImGui_WindowFlags_NoDecoration()
      | R.ImGui_WindowFlags_NoMove() | R.ImGui_WindowFlags_NoResize()
  end
  return flags
end

local function loop()
  -- A context can become invalid when an older deferred instance is winding
  -- down after the action is toggled or the script is reloaded. Validate it
  -- before every frame so no ReaImGui API ever receives a stale pointer.
  if R.GetExtState(EXT, "running") ~= instance_token then
    cleanup()
    return
  end
  if R.ImGui_ValidatePtr and not R.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    cleanup()
    return
  end
  Runtime.tooltip.request = nil

  if font_reload_pending then reload_fonts() end
  if palette_rebuild_pending then
    rebuild_palette()
    palette_rebuild_pending = false
  end

  process_presentation_request()
  Content.process_detached_request()
  Metering.Visual.process_test_quality_request()

  if dock_request ~= nil then
    R.ImGui_SetNextWindowDockID(ctx, dock_request, R.ImGui_Cond_Always())
    dock_request = nil
  end

  Runtime.defer_started = true
  recompute_snapshot(first_frame)

  local aspect = current_aspect_ratio()
  R.ImGui_Function_SetValue(aspect_constraint, "aspect_ratio", aspect)
  if first_frame and has_saved_window and settings.dock_id == 0
      and settings.fit_window_to_content then
    -- The fit reference becomes available during the first snapshot. Refit
    -- the saved height before ImGui applies it so a long clock format cannot
    -- preserve the old tall height by expanding the window width instead.
    local x, y, w, h = cap_window_rect(saved_window.x, saved_window.y,
      saved_window.w, saved_window.w / aspect + window_chrome_h, true)
    saved_window.x, saved_window.y, saved_window.w, saved_window.h = x, y, w, h
    save_string("window_x", round_pixel(x))
    save_string("window_y", round_pixel(y))
    save_string("window_w", round_pixel(w))
    save_string("window_h", round_pixel(h))
    restore_request_w, restore_request_h = w, h
  end
  if layout_resize_pending then
    if presentation_mode and main_geometry then
      presentation_bounds = presentation_bounds or find_presentation_bounds(
        main_geometry.x, main_geometry.y, main_geometry.w, main_geometry.h)
      local x, y, w, h = presentation_window_rect(presentation_bounds)
      forced_window_geometry = { x = x, y = y, w = w, h = h }
    elseif settings.fit_window_to_content and main_geometry
        and settings.dock_id == 0 and main_dock_id == 0 then
      local target_w = main_geometry.w
      local target_h = target_w / aspect + window_chrome_h
      local target_x, target_y
      target_x, target_y, target_w, target_h = cap_window_rect(
        main_geometry.x, main_geometry.y, target_w, target_h, true)
      forced_window_geometry = {
        x = target_x, y = target_y, w = target_w, h = target_h,
      }
    end
    layout_resize_pending = false
  end

  if presentation_mode and presentation_bounds and presentation_drag.target_y then
    local _, _, _, h = fit_presentation_face_rect(presentation_bounds, 0)
    local min_y = presentation_bounds.top
    local max_y = math.max(min_y, presentation_bounds.bottom - h)
    local y = math.max(min_y, math.min(max_y, presentation_drag.target_y))
    local vertical_room = max_y - min_y
    local position = vertical_room > 0 and (y - min_y) / vertical_room or 0.5
    if math.abs(position - settings.presentation_vertical_position) > 0.0005 then
      settings.presentation_vertical_position = position
      save_string("presentation_vertical_position", string.format("%.4f", position))
    end
    presentation_drag.target_y = nil
  end

  if forced_window_geometry then
    R.ImGui_SetNextWindowPos(ctx, forced_window_geometry.x, forced_window_geometry.y,
      R.ImGui_Cond_Always())
    R.ImGui_SetNextWindowSize(ctx, forced_window_geometry.w, forced_window_geometry.h,
      R.ImGui_Cond_Always())
    forced_window_geometry = nil
  elseif first_frame then
    if settings.dock_id ~= 0 then
      window_restore_complete = true
    elseif has_saved_window then
      R.ImGui_SetNextWindowPos(ctx, saved_window.x, saved_window.y, R.ImGui_Cond_Always())
      R.ImGui_SetNextWindowSize(ctx, restore_request_w, restore_request_h,
        R.ImGui_Cond_Always())
      restore_size_applied = true
      restore_size_applied_at = R.time_precise()
    else
      R.ImGui_SetNextWindowSize(ctx, 918, current_base_height() + window_chrome_h,
        R.ImGui_Cond_FirstUseEver())
    end
    first_frame = false
  elseif restore_size_pending then
    R.ImGui_SetNextWindowSize(ctx, restore_request_w, restore_request_h,
      R.ImGui_Cond_Always())
    restore_size_pending = false
    restore_size_applied = true
    restore_size_applied_at = R.time_precise()
  end
  -- ReaImGui viewports can settle for several frames after appearing on a
  -- mixed-DPI monitor. Hold the requested dimensions during that brief handoff
  -- so the aspect constraint cannot adopt its minimum as the new live size.
  if restore_size_applied and R.time_precise() - restore_size_applied_at < 0.75 then
    R.ImGui_SetNextWindowSize(ctx, restore_request_w, restore_request_h,
      R.ImGui_Cond_Always())
  end
  if not presentation_mode and settings.dock_id == 0 and main_dock_id == 0 then
    local reference = main_geometry or (has_saved_window and saved_window)
      or { x = 100, y = 100, w = 918, h = current_base_height() + window_chrome_h }
    local bounds = window_work_area(reference.x, reference.y, reference.w, reference.h)
    local maximum_w, maximum_h = 2160, 2160
    if bounds then
      maximum_w = math.max(MIN_WINDOW_W,
        bounds.right - bounds.left - WINDOW_MONITOR_MARGIN * 2)
      maximum_h = math.max(MIN_WINDOW_H,
        bounds.bottom - bounds.top - WINDOW_MONITOR_MARGIN * 2)
    end
    if settings.fit_window_to_content then
      R.ImGui_Function_SetValue(aspect_constraint, "chrome_h", window_chrome_h)
      local min_h = MIN_WINDOW_W / aspect + window_chrome_h
      local aspect_max_w = math.min(maximum_w,
        math.max(1, (maximum_h - window_chrome_h) * aspect))
      if min_h <= maximum_h and aspect_max_w >= MIN_WINDOW_W then
        R.ImGui_SetNextWindowSizeConstraints(ctx,
          MIN_WINDOW_W, math.max(MIN_WINDOW_H, min_h),
          aspect_max_w, maximum_h, aspect_constraint)
      else
        -- Extremely tall layouts cannot honor both the normal minimum width
        -- and the monitor height. Keep a usable window and contain the whole
        -- face inside it rather than clipping bottom rows.
        R.ImGui_SetNextWindowSizeConstraints(ctx,
          MIN_WINDOW_W, MIN_WINDOW_H, maximum_w, maximum_h)
      end
    else
      R.ImGui_SetNextWindowSizeConstraints(ctx,
        MIN_WINDOW_W, MIN_WINDOW_H, maximum_w, maximum_h)
    end
  end

  local main_palette = settings.recording_background_enabled
    and snapshot.transport_kind == "recording" and C.recording_palette or C
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_WindowBg(), main_palette.outer)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Border(), main_palette.border)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGrip(), 0xA1A6B033)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGripHovered(), main_palette.accent)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_ResizeGripActive(), main_palette.accent_active)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), main_palette.ink)
  -- These affect ImGui-rendered decorations (including docked contexts). Some
  -- desktop environments own the native floating title bar and may ignore them.
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBg(), main_palette.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBgActive(), main_palette.surface)
  R.ImGui_PushStyleColor(ctx, R.ImGui_Col_TitleBgCollapsed(), main_palette.surface)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowPadding(), 0, 0)
  R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_WindowBorderSize(), 0)

  local visible, open = R.ImGui_Begin(ctx, TITLE .. "###ReaClockMain", true, current_main_flags())
  if visible then
    local main_focused_now = R.ImGui_IsWindowFocused(ctx)
    main_dock_id = R.ImGui_GetWindowDockID(ctx)
    if main_dock_id < 0 and settings.dock_id ~= main_dock_id then
      settings.dock_id = main_dock_id
      save_string("dock_id", main_dock_id)
    elseif main_dock_id == 0 and settings.dock_id ~= 0 then
      settings.dock_id = 0
      save_string("dock_id", 0)
    end
    local origin_x, origin_y = R.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = R.ImGui_GetContentRegionAvail(ctx)
    if not presentation_mode and main_dock_id == 0 then
      -- Native title-bar height differs across Windows, macOS, Linux, themes,
      -- and DPI scales. Measure it from the live viewport, then refit once if
      -- the startup estimate was different so the content ratio stays exact.
      local measured_chrome = math.max(0, R.ImGui_GetWindowHeight(ctx) - avail_h)
      if math.abs(measured_chrome - window_chrome_h) > CHROME_MEASURE_EPSILON then
        window_chrome_h = measured_chrome
        request_layout_resize()
      end
    end
    if restore_size_applied and R.time_precise() - restore_size_applied_at >= 0.75 then
      restore_size_applied = false
      restore_attempts = restore_attempts + 1
      local actual_w, actual_h = R.ImGui_GetWindowSize(ctx)
      local width_error = math.abs(actual_w - saved_window.w)
      local height_error = math.abs(actual_h - saved_window.h)
      if (width_error <= 2 and height_error <= 2) or restore_attempts >= 4 then
        window_restore_complete = true
      else
        -- SetNextWindowSize inputs can be scaled by REAPER's UI scale even
        -- when the viewport DPI reports 1. Calibrate against the actual
        -- content height, then correct on the next frame. This converges in
        -- one or two frames and prevents size growth on every reopen.
        if settings.fit_window_to_content then
          local target_content_h = math.max(1, saved_window.h - window_chrome_h)
          local actual_content_h = math.max(1, actual_h - window_chrome_h)
          local correction = target_content_h / actual_content_h
          restore_request_w = math.max(1, restore_request_w * correction)
          restore_request_h = math.max(1, restore_request_h * correction)
        else
          restore_request_w = math.max(1,
            restore_request_w * saved_window.w / math.max(1, actual_w))
          restore_request_h = math.max(1,
            restore_request_h * saved_window.h / math.max(1, actual_h))
        end
        restore_size_pending = true
      end
    end
    Content.handle_main_shortcuts()
    draw_face(origin_x, origin_y, avail_w, avail_h)
    if edit_mode and not presentation_mode then Content.draw_face_switch_menu() end
    Content.draw_face_dialog()
    Metering.draw_source_setup_dialog()
    local gx, gy = R.ImGui_GetWindowPos(ctx)
    local gw, gh = R.ImGui_GetWindowSize(ctx)
    Runtime.settings_owner_geometry = Runtime.settings_owner_geometry or {}
    Runtime.settings_owner_geometry.x, Runtime.settings_owner_geometry.y = gx, gy
    Runtime.settings_owner_geometry.w, Runtime.settings_owner_geometry.h = gw, gh
    local monitor_cap_pending = false
    if main_dock_id == 0 and not presentation_mode then
      local fitted_x, fitted_y, fitted_w, fitted_h, changed = cap_window_rect(
        gx, gy, gw, gh, settings.fit_window_to_content)
      if changed then
        forced_window_geometry = {
          x = fitted_x, y = fitted_y, w = fitted_w, h = fitted_h,
        }
        monitor_cap_pending = true
      end
      main_geometry = {
        x = changed and fitted_x or gx, y = changed and fitted_y or gy,
        w = changed and fitted_w or gw, h = changed and fitted_h or gh,
      }
    elseif main_dock_id == 0 then
      main_geometry = { x = gx, y = gy, w = gw, h = gh }
    end
    if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape()) then
      if Runtime.card_fullscreen then
        Runtime.card_fullscreen = nil
      elseif face_dialog.action then
        -- The popup itself owns CloseCurrentPopup, so defer closure until its
        -- next BeginPopupModal scope instead of leaving stale modal state.
        face_dialog.request, face_dialog.close_request = nil, true
      elseif Content.controls.popup_was_open then
        -- ImGui owns Escape for the popup that was open at frame start.
      elseif presentation_mode then
        presentation_request = "exit"
      elseif settings_open then
        settings_open = false
      elseif detail_editor.open then
        detail_editor.open = false
      elseif edit_mode then
        edit_mode = false
        request_layout_resize()
      else
        -- Esc is a script-local close command in both floating and docked
        -- layouts. This avoids Alt+F4 accidentally closing REAPER when the
        -- clock lives in a docker.
        open = false
      end
    end
    if not presentation_mode and main_dock_id == 0 and not monitor_cap_pending then
      persist_window_geometry()
    end
    Runtime.metering.main_focused_prior = main_focused_now
  else
    Runtime.metering.main_focused_prior = false
  end
  R.ImGui_End(ctx)

  R.ImGui_PopStyleVar(ctx, 2)
  R.ImGui_PopStyleColor(ctx, 9)

  UI.draw_settings_window()
  Content.draw_detached_windows()
  Content.draw_card_fullscreen_window()
  Content.draw_detail_editor_window()
  Content.draw_detached_error()
  Runtime.draw_active_tooltip()
  if factory_restart_requested then
    factory_restart_requested = false
    -- Invoking the same deferred REAPER action while it is active stops it
    -- without starting a replacement. Fully retire this instance, then load
    -- the exact currently running source again so startup follows the genuine
    -- first-install path without depending on action-toggle timing.
    local relaunch_path = Runtime.script_path
    cleanup()
    local relaunched, relaunch_error = false, "The current script path is unavailable."
    if type(relaunch_path) == "string" and relaunch_path ~= "" then
      relaunched, relaunch_error = pcall(dofile, relaunch_path)
    end
    if not relaunched then
      R.ShowMessageBox(
        "Factory Reset is complete, but ReaClock could not reopen automatically.\n\n"
          .. tostring(relaunch_error) .. "\n\nRun ReaClock again to open the fresh configuration.",
        TITLE, 0)
    end
    return
  end
  -- Preserve popup ownership for the next frame. ImGui may process Escape and
  -- close a popup before this script's next live IsPopupOpen query; retaining
  -- the prior rendered frame is what prevents that key from bubbling upward.
  Content.controls.popup_was_open = R.ImGui_IsPopupOpen(ctx, "",
    R.ImGui_PopupFlags_AnyPopup())
  Store.flush(false)

  if open then
    R.defer(loop)
  else
    cleanup()
  end
end

recompute_snapshot(true)
R.defer(loop)
