-- Resources/CodeRuntime.lua
-- Eager-loaded by ReaAssist.lua through RA.load_code_runtime(). Defines the
-- generated-code runtime on Code.*: typed-action parsing/execution, Lua safety
-- validators, latest-code tracking, run-result metadata, and JSFX validation.
-- Marker: CFG.VERSION (consumed by ReaAssist.lua's updater integrity check for
-- sidecar files that do not otherwise need the runtime version constant).
--
-- Boundary contract:
--   - Startup work should be definition-only; validation/execution work happens
--     when the user sends, retries, inspects, or runs generated code.
--   - Function bodies may resolve main-file helpers at call time through the
--     loader environment, so keep cross-file dependencies explicit in
--     RA.load_code_runtime().
--   - Validators favor high-confidence gates over broad linting; comments below
--     call out intentional false-positive/false-negative tradeoffs.

function Code._lua_trim_expr(v)
  return tostring(v or ""):match("^%s*(.-)%s*$") or ""
end

function Code._lua_line_for_pos(src, pos)
  local line = 1
  for _ in tostring(src or ""):sub(1, pos or 1):gmatch("\n") do
    line = line + 1
  end
  return line
end

function Code._lua_call_inner(src, open_pos)
  src = tostring(src or "")
  open_pos = tonumber(open_pos)
  if not open_pos then return nil, nil end

  local depth = 1
  local i = open_pos + 1
  local in_str = nil
  while i <= #src do
    local c = src:sub(i, i)
    if in_str then
      if c == "\\" then
        i = i + 1
      elseif c == in_str then
        in_str = nil
      end
    else
      if c == '"' or c == "'" then
        in_str = c
      elseif c == "(" or c == "[" or c == "{" then
        depth = depth + 1
      elseif c == ")" or c == "]" or c == "}" then
        depth = depth - 1
        if depth == 0 then
          return src:sub(open_pos + 1, i - 1), i
        end
      end
    end
    i = i + 1
  end
  return nil, nil
end

function Code._split_lua_args(src)
  if src == nil then return nil end
  src = tostring(src or "")

  local args, field = {}, {}
  local depth = 0
  local in_str = nil
  local i = 1
  while i <= #src do
    local c = src:sub(i, i)
    if in_str then
      field[#field + 1] = c
      if c == "\\" then
        i = i + 1
        if i <= #src then field[#field + 1] = src:sub(i, i) end
      elseif c == in_str then
        in_str = nil
      end
    else
      if c == '"' or c == "'" then
        in_str = c
        field[#field + 1] = c
      elseif c == "(" or c == "[" or c == "{" then
        depth = depth + 1
        field[#field + 1] = c
      elseif c == ")" or c == "]" or c == "}" then
        depth = depth - 1
        field[#field + 1] = c
      elseif c == "," and depth == 0 then
        args[#args + 1] = Code._lua_trim_expr(table.concat(field))
        field = {}
      else
        field[#field + 1] = c
      end
    end
    i = i + 1
  end
  args[#args + 1] = Code._lua_trim_expr(table.concat(field))
  return args
end

function Code._parse_lua_call_args(src, open_pos)
  local inner, close_pos = Code._lua_call_inner(src, open_pos)
  if inner == nil then return nil, nil end
  return Code._split_lua_args(inner), close_pos
end

-- =============================================================================
-- Code.extract_typed_actions / Code.validate_typed_actions_plan
-- =============================================================================
-- Phase-1/2 typed action support: parse and validate provider-neutral action
-- JSON, plus a fail-closed local executor for exact-fit structured track edits.
-- The normal Lua path remains first-class for every request outside this
-- deliberately narrow stock track/FX/folder/send graph lane.
do
-- The typed-action lane is intentionally small: track creation/resolution,
-- stock FX, stock-FX parameters, folders, sends, and pan LFO automation. Anything
-- outside this whitelist should stay on the generated-Lua path.
local _TYPED_ACTION_STOCK_FX = {
  ReaEQ = true,
  ReaComp = true,
  ReaDelay = true,
  ReaVerbate = true,
  ReaGate = true,
  ReaLimit = true,
}

local _TYPED_ACTION_OP_KEYS = {
  "track.create",
  "track.ensure",
  "track.resolve",
  "track.set",
  "track.pan_lfo",
  "track.folder",
  "fx.add_stock",
  "fx.set_param",
  "send.create",
}

-- Fast membership map used by schema validation and repair.
local _TYPED_ACTION_OP_ALLOWED = {}
for _, op in ipairs(_TYPED_ACTION_OP_KEYS) do
  _TYPED_ACTION_OP_ALLOWED[op] = true
end

-- Supported stock-FX parameter names by action schema. Types here describe the
-- JSON contract, not the eventual normalized REAPER parameter values.
local _TYPED_ACTION_PARAM_TYPES = {
  ReaEQ = {
    band = "number",
    frequency_hz = "number",
    gain_db = "number",
  },
  ReaComp = {
    threshold_db = "number",
    attack_ms = "number",
    release_ms = "number",
    wet_db = "number",
    dry_db = "number",
    rms_ms = "number",
  },
  ReaDelay = {
    free_time_ms = "number",
    musical_length = "number",
    feedback_pct = "number",
    feedback_db = "number",
    wet_db = "number",
    dry_db = "number",
  },
  ReaVerbate = {
    wet_db = "number",
    dry_db = "number",
    room_size = "number",
    dampening = "number",
  },
  ReaGate = {
    threshold_db = "number",
    hysteresis_db = "number",
    attack_ms = "number",
    hold_ms = "number",
    release_ms = "number",
  },
  ReaLimit = {
    threshold_db = "number",
    ceiling_db = "number",
  },
}

-- Normalized ReaEQ parameter lookup points. The executor interpolates these
-- sparse calibration tables instead of pretending ReaEQ uses linear Hz/dB
-- scaling across its sliders.
local _TYPED_ACTION_REAEQ_FREQ_POINTS = {
  { 20, 0.0078 }, { 50, 0.0625 }, { 80, 0.1094 },
  { 100, 0.1406 }, { 150, 0.1953 }, { 200, 0.2344 },
  { 250, 0.2656 }, { 300, 0.2891 }, { 400, 0.3320 },
  { 500, 0.3672 }, { 600, 0.3945 }, { 700, 0.4199 },
  { 800, 0.4414 }, { 900, 0.4590 }, { 1000, 0.4766 },
  { 1200, 0.5059 }, { 1500, 0.5410 }, { 2000, 0.5884 },
  { 2500, 0.6250 }, { 3000, 0.6553 }, { 3500, 0.6802 },
  { 4000, 0.7026 }, { 5000, 0.7393 }, { 6000, 0.7695 },
  { 7000, 0.7952 }, { 8000, 0.8173 }, { 10000, 0.8542 },
  { 12000, 0.8846 }, { 14000, 0.9103 }, { 16000, 0.9325 },
  { 18000, 0.9521 }, { 20000, 0.9696 }, { 24000, 1.0000 },
}

local _TYPED_ACTION_REAEQ_GAIN_POINTS = {
  { -12, 0.1250 }, { -10, 0.1582 }, { -8, 0.1992 },
  { -6, 0.2500 }, { -5, 0.2813 }, { -4, 0.3164 },
  { -3, 0.3555 }, { -2, 0.3984 }, { -1, 0.4453 },
  { 0, 0.5000 }, { 1, 0.5195 }, { 2, 0.5430 },
  { 3, 0.5684 }, { 4, 0.5977 }, { 5, 0.6289 },
  { 6, 0.6641 }, { 7, 0.7070 }, { 8, 0.7500 },
  { 9, 0.8047 }, { 10, 0.8594 }, { 11, 0.9219 },
  { 12, 0.9961 },
}

-- Small JSON-shape helpers shared by parser, validator, and repair code.
local function _typed_action_error(code, path, message)
  return { code = code, path = path or "$", message = message }
end

local function _typed_action_trim(s)
  return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function _typed_action_is_nonempty_string(v)
  return type(v) == "string" and v:match("%S") ~= nil
end

local function _typed_action_is_array(t)
  if type(t) ~= "table" or t == JSON.NULL then return false end
  local n = #t
  if n == 0 then return false end
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  return count == n
end

local function _typed_action_is_object(t)
  if type(t) ~= "table" or t == JSON.NULL then return false end
  if #t > 0 then return false end
  return true
end

local function _typed_action_add_error(errors, code, path, message)
  errors[#errors+1] = _typed_action_error(code, path, message)
end

local function _typed_action_check_fields(errors, obj, path, allowed)
  for k in pairs(obj) do
    if type(k) ~= "string" or not allowed[k] then
      _typed_action_add_error(errors, "unknown_field",
        path .. "." .. tostring(k), "Unsupported typed-action field")
    end
  end
end

local function _typed_action_first_error_code(errors)
  local first = type(errors) == "table" and errors[1] or nil
  return first and first.code or nil
end

local function _typed_action_signature_value(v)
  if v == JSON.NULL then return "null" end
  local tv = type(v)
  if tv ~= "table" then return tv .. ":" .. tostring(v) end
  if _typed_action_is_array(v) then
    local parts = {}
    for i = 1, #v do
      parts[#parts+1] = _typed_action_signature_value(v[i])
    end
    return "array:[" .. table.concat(parts, ",") .. "]"
  end
  local keys, parts = {}, {}
  for k in pairs(v) do keys[#keys+1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    parts[#parts+1] = tostring(k) .. "=" .. _typed_action_signature_value(v[k])
  end
  return "object:{" .. table.concat(parts, ",") .. "}"
end

-- Some smaller models occasionally loop exact duplicate JSON actions. Exact
-- repeats cannot express an intentional second object because ids must be
-- unique, so collapse them before validation while preserving non-identical
-- duplicate-id failures.
function Code.normalize_typed_actions_plan(plan)
  if not _typed_action_is_object(plan)
     or not _typed_action_is_array(plan.actions) then
    return plan, 0
  end

  local seen, out, dropped = {}, {}, 0
  for _, action in ipairs(plan.actions) do
    local sig = _typed_action_signature_value(action)
    if seen[sig] then
      dropped = dropped + 1
    else
      seen[sig] = true
      out[#out+1] = action
    end
  end

  if dropped > 0 then plan.actions = out end
  return plan, dropped
end

-- Prompt-intent readers used by typed-action repair, schema shaping, and
-- semantic validation. These are deliberately string-pattern based so they can
-- run before any model call and without depending on the context sidecar.
function Code._typed_action_selected_indexes_from_user_text(user_text)
  local text = tostring(user_text or ""):lower()
  text = text
    :gsub("do not use selected_index", "")
    :gsub("do not use selected index", "")
    :gsub("don't use selected_index", "")
    :gsub("don't use selected index", "")
    :gsub("without selected_index", "")
    :gsub("without selected index", "")
    :gsub("not selected_index", "")
    :gsub("not selected index", "")
  local indexes, seen = {}, {}
  local function add(raw)
    local n = tonumber(raw)
    if not n or n % 1 ~= 0 or n < 1 then return end
    if seen[n] then return end
    seen[n] = true
    indexes[#indexes + 1] = n
  end

  for raw in text:gmatch("selected[_%-%s]+index%s*[:=]?%s*(%d+)") do
    add(raw)
  end
  for _, suffix in ipairs({ "st", "nd", "rd", "th" }) do
    for raw in text:gmatch("%f[%d](%d+)%s*" .. suffix .. "%s+selected%s+track") do
      add(raw)
    end
  end
  for raw in text:gmatch("selected%s+track%s+(%d+)") do
    add(raw)
  end

  local ordinals = {
    first = 1, second = 2, third = 3, fourth = 4, fifth = 5,
    sixth = 6, seventh = 7, eighth = 8, ninth = 9, tenth = 10,
  }
  for word, n in pairs(ordinals) do
    if text:find("%f[%a]" .. word .. "%s+selected%s+track", 1) then
      add(n)
    elseif text:find("%f[%a]" .. word .. "%s+selected%f[%A]", 1) then
      add(n)
    end
  end

  table.sort(indexes)
  local required = #indexes > 0
    or text:find("selected_index", 1, true) ~= nil
    or text:find("selected index", 1, true) ~= nil
  return indexes, required
end

function Code._typed_action_absolute_track_indexes_from_user_text(user_text)
  local text = Code._typed_action_user_request_text(user_text):lower()
  text = text
    :gsub("selected%s+track%s+#?%s*%d+", "")
    :gsub("selected[_%-%s]+index%s*[:=]?%s*%d+", "")
  local indexes, seen = {}, {}
  for raw in text:gmatch("%f[%a]track%s+#?%s*(%d+)%f[%D]") do
    local n = tonumber(raw)
    if n and n % 1 == 0 and n >= 1 and n <= 4096 and not seen[n] then
      seen[n] = true
      indexes[#indexes + 1] = n
    end
  end
  table.sort(indexes)
  return indexes
end

function Code._typed_action_forbids_positional_track_selector(user_text)
  local text = tostring(user_text or ""):lower()
  return text:find("do not use selected_index", 1, true) ~= nil
    or text:find("do not use selected index", 1, true) ~= nil
    or text:find("don't use selected_index", 1, true) ~= nil
    or text:find("don't use selected index", 1, true) ~= nil
    or text:find("without selected_index", 1, true) ~= nil
    or text:find("without selected index", 1, true) ~= nil
    or text:find("do not use absolute track index", 1, true) ~= nil
    or text:find("do not use absolute track indexes", 1, true) ~= nil
    or text:find("don't use absolute track index", 1, true) ~= nil
    or text:find("don't use absolute track indexes", 1, true) ~= nil
    or text:find("without absolute track index", 1, true) ~= nil
    or text:find("without absolute track indexes", 1, true) ~= nil
end

function Code._typed_action_forbids_absolute_track_index(user_text)
  local text = tostring(user_text or ""):lower()
  return text:find("do not use absolute track index", 1, true) ~= nil
    or text:find("do not use absolute track indexes", 1, true) ~= nil
    or text:find("don't use absolute track index", 1, true) ~= nil
    or text:find("don't use absolute track indexes", 1, true) ~= nil
    or text:find("without absolute track index", 1, true) ~= nil
    or text:find("without absolute track indexes", 1, true) ~= nil
    or text:match("do not use[^%.\n;]*absolute track indexes?") ~= nil
    or text:match("don't use[^%.\n;]*absolute track indexes?") ~= nil
    or text:match("without[^%.\n;]*absolute track indexes?") ~= nil
end

function Code._typed_action_user_request_text(user_text)
  local text = tostring(user_text or "")
  local marker, last = "USER REQUEST:", nil
  local pos = 1
  while true do
    local s, e = text:find(marker, pos, true)
    if not s then break end
    last = e + 1
    pos = e + 1
  end
  if last then text = text:sub(last) end

  local cut_at
  for _, stop in ipairs({
    "\n\nTYPED ACTION CONTRACT",
    "\nTYPED ACTION CONTRACT",
    "\n\nSESSION CONTEXT",
    "\nSESSION CONTEXT",
  }) do
    local s = text:find(stop, 1, true)
    if s and (not cut_at or s < cut_at) then cut_at = s end
  end
  if cut_at then text = text:sub(1, cut_at - 1) end
  return text:gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
end

function Code._localized_action_intent_text(user_text)
  local text = Code._typed_action_user_request_text(user_text):lower()
  for _, pair in ipairs({
    { "á", "a" }, { "à", "a" }, { "â", "a" }, { "ã", "a" },
    { "é", "e" }, { "ê", "e" }, { "í", "i" }, { "ó", "o" },
    { "ô", "o" }, { "õ", "o" }, { "ú", "u" }, { "ü", "u" },
    { "ç", "c" }, { "ñ", "n" },
    { "Á", "a" }, { "À", "a" }, { "Â", "a" }, { "Ã", "a" },
    { "É", "e" }, { "Ê", "e" }, { "Í", "i" }, { "Ó", "o" },
    { "Ô", "o" }, { "Õ", "o" }, { "Ú", "u" }, { "Ü", "u" },
    { "Ç", "c" }, { "Ñ", "n" },
  }) do
    text = text:gsub(pair[1], pair[2])
  end
  text = text
    :gsub("%f[%w]plug%-ins%f[%W]", "plugins")
    :gsub("%f[%w]plug%-in%f[%W]", "plugin")
  for _, pair in ipairs({
    { "faixas", "tracks" }, { "faixa", "track" },
    { "pistas", "tracks" }, { "pista", "track" },
    { "selecionadas", "selected" }, { "selecionados", "selected" },
    { "selecionada", "selected" }, { "selecionado", "selected" },
    { "seleccionadas", "selected" }, { "seleccionados", "selected" },
    { "seleccionada", "selected" }, { "seleccionado", "selected" },
    { "panoramica", "pan" },
    { "adicione", "add" }, { "adicionar", "add" },
    { "anade", "add" }, { "anadir", "add" },
    { "agrega", "add" }, { "agregar", "add" },
    { "insira", "insert" }, { "inserir", "insert" },
    { "inserta", "insert" }, { "insertar", "insert" },
    { "coloque", "put" }, { "colocar", "put" },
    { "pon", "put" }, { "poner", "put" },
    { "aplica", "apply" }, { "aplicar", "apply" },
    { "ajuste", "adjust" }, { "ajustar", "adjust" },
    { "ajusta", "adjust" },
    { "defina", "set" }, { "definir", "set" },
    { "establece", "set" }, { "establecer", "set" },
    { "configure", "configure" }, { "configurar", "configure" },
    { "configura", "configure" },
    { "altere", "change" }, { "alterar", "change" },
    { "cambia", "change" }, { "cambiar", "change" },
    { "crie", "create" }, { "criar", "create" },
    { "crea", "create" }, { "crear", "create" },
    { "explique", "explain" }, { "explicar", "explain" },
    { "explica", "explain" },
    { "mova", "move" }, { "mover", "move" },
    { "mueve", "move" },
    { "silencie", "mute" }, { "silenciar", "mute" },
    { "silencia", "mute" },
    { "roteie", "route" }, { "rotear", "route" },
    { "enruta", "route" }, { "enrutar", "route" },
    { "roteamento", "routing" },
    { "enrutamiento", "routing" },
    { "envios", "sends" }, { "envio", "send" },
    { "envie", "send" }, { "enviar", "send" },
    { "envia", "send" },
    { "efeitos", "effects" }, { "efeito", "effect" },
    { "efectos", "effects" }, { "efecto", "effect" },
    { "cadenas", "chains" }, { "cadena", "chain" },
    { "existentes", "existing" }, { "existente", "existing" },
    { "utiliza", "use" }, { "utilizar", "use" },
    { "usa", "use" }, { "usar", "use" },
    { "modifica", "modify" }, { "modificar", "modify" },
    { "parametros", "parameters" }, { "parametro", "parameter" },
    { "estilos", "styles" }, { "estilo", "style" },
    { "umbrales", "thresholds" }, { "umbral", "threshold" },
    { "ataques", "attacks" }, { "ataque", "attack" },
    { "ganancias", "gains" }, { "ganancia", "gain" },
    { "frecuencias", "frequencies" }, { "frecuencia", "frequency" },
    { "mezclas", "mixes" }, { "mezcla", "mix" },
    { "velocidades", "speeds" }, { "velocidad", "speed" },
    { "reajustes", "retunes" }, { "reajuste", "retune" },
    { "suave", "gentle" }, { "suavemente", "gently" },
    { "compressores", "compressors" }, { "compressor", "compressor" },
    { "compresores", "compressors" }, { "compresor", "compressor" },
    { "reverberacao", "reverb" },
    { "reverberacion", "reverb" },
  }) do
    text = text:gsub("%f[%w]" .. pair[1] .. "%f[%W]", pair[2])
  end
  return text:gsub("%s+", " ")
end

function Code.prompt_is_question_or_readonly(user_text)
  local lt = Code._localized_action_intent_text(user_text)
  local trimmed_lt = lt:gsub("^%s+", "")
    :gsub("^¿+", "")
    :gsub("^¡+", "")
    :gsub("^%s+", "")
  if trimmed_lt == "" then return false end
  local fx_presence_question =
       trimmed_lt:find("^does%s+.+%s+have%s+") ~= nil
    or trimmed_lt:find("^do%s+.+%s+have%s+") ~= nil
    or trimmed_lt:find("^does%s+.+%s+use%s+") ~= nil
    or trimmed_lt:find("^do%s+.+%s+use%s+") ~= nil
  local prefaced_question = false
  for _, prefix in ipairs({ "in", "for", "with", "on", "about", "regarding" }) do
    if trimmed_lt:find("^" .. prefix .. "%s+.-,%s*how%s+")
        or trimmed_lt:find("^" .. prefix .. "%s+.-,%s*what%s+")
        or trimmed_lt:find("^" .. prefix .. "%s+.-,%s*why%s+")
        or trimmed_lt:find("^" .. prefix .. "%s+.-,%s*where%s+")
        or trimmed_lt:find("^" .. prefix .. "%s+.-,%s*when%s+")
        or trimmed_lt:find("^" .. prefix .. "%s+.-,%s*explain%s+") then
      prefaced_question = true
      break
    end
  end
  local explicitly_prose_only =
       trimmed_lt:find("answer only in prose", 1, true) ~= nil
    or trimmed_lt:find("answer in prose only", 1, true) ~= nil
    or trimmed_lt:find("do not include code", 1, true) ~= nil
    or trimmed_lt:find("don't include code", 1, true) ~= nil
    or trimmed_lt:find("without code", 1, true) ~= nil
  return
       trimmed_lt:find("^how%s+") ~= nil
    or trimmed_lt:find("^what%s+") ~= nil
    or trimmed_lt:find("^why%s+") ~= nil
    or trimmed_lt:find("^where%s+") ~= nil
    or trimmed_lt:find("^when%s+") ~= nil
    or trimmed_lt:find("^should%s+i%s+") ~= nil
    or trimmed_lt:find("^should%s+we%s+") ~= nil
    or trimmed_lt:find("^do%s+i%s+need%s+to%s+") ~= nil
    or trimmed_lt:find("^do%s+we%s+need%s+to%s+") ~= nil
    or trimmed_lt:find("^would%s+it%s+be%s+better%s+to%s+") ~= nil
    or trimmed_lt:find("^would%s+it%s+help%s+to%s+") ~= nil
    or trimmed_lt:find("^is%s+") ~= nil
    or trimmed_lt:find("^are%s+") ~= nil
    or trimmed_lt:find("^explain%s+") ~= nil
    or trimmed_lt:find("^tell%s+me%s+") ~= nil
    or trimmed_lt:find("^show%s+me%s+how%s+") ~= nil
    or trimmed_lt:find("^list%s+") ~= nil
    or trimmed_lt:find("^show%s+") ~= nil
    or trimmed_lt:find("^inspect%s+") ~= nil
    or trimmed_lt:find("^analyze%s+") ~= nil
    or trimmed_lt:find("^review%s+") ~= nil
    or trimmed_lt:find("^diagnose%s+") ~= nil
    or trimmed_lt:find("^summarize%s+") ~= nil
    or trimmed_lt:find("^como%s+") ~= nil
    or trimmed_lt:find("^o%s+que%s+") ~= nil
    or trimmed_lt:find("^qual%s+") ~= nil
    or trimmed_lt:find("^quais%s+") ~= nil
    or trimmed_lt:find("^por%s+que%s+") ~= nil
    or trimmed_lt:find("^devo%s+") ~= nil
    or trimmed_lt:find("^que%s+") ~= nil
    or trimmed_lt:find("^cual%s+") ~= nil
    or trimmed_lt:find("^cuales%s+") ~= nil
    or trimmed_lt:find("^debo%s+") ~= nil
    or trimmed_lt:find("^puedo%s+") ~= nil
    or prefaced_question
    or explicitly_prose_only
    or fx_presence_question
end

function Code.prompt_is_answer_only_followup(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if lt == "" then return false end
  local reasoning_behind = lt:find("reasoning%s+behind") ~= nil
  local reasoning_readonly_prefix =
       lt:find("^explain%s+") ~= nil
    or lt:find("^why%s+") ~= nil
    or lt:find("^what%s+") ~= nil
    or lt:find("^can%s+you%s+explain%s+") ~= nil
    or lt:find("^could%s+you%s+explain%s+") ~= nil
    or lt:find("^please%s+explain%s+") ~= nil
  return
       lt:find("^explain%s+your%s+") ~= nil
    or lt:find("^explain%s+why%s+you%s+") ~= nil
    or lt:find("^explain%s+the%s+reasoning%s+behind%s+") ~= nil
    or lt:find("^why%s+did%s+you%s+") ~= nil
    or lt:find("^why%s+did%s+that%s+") ~= nil
    or lt:find("^what%s+was%s+your%s+reasoning") ~= nil
    or lt:find("^what%s+made%s+you%s+") ~= nil
    or lt:find("^walk%s+me%s+through%s+your%s+") ~= nil
    or lt:find("^walk%s+me%s+through%s+that") ~= nil
    or lt:find("^walk%s+me%s+through%s+this") ~= nil
    or lt:find("^walk%s+me%s+through%s+it") ~= nil
    or lt:find("^talk%s+me%s+through%s+your%s+") ~= nil
    or lt:find("^talk%s+me%s+through%s+that") ~= nil
    or lt:find("^talk%s+me%s+through%s+this") ~= nil
    or lt:find("^talk%s+me%s+through%s+it") ~= nil
    or lt:find("^how%s+come%s+you%s+") ~= nil
    or lt:find("^tell%s+me%s+why%s+you%s+") ~= nil
    or (reasoning_behind and reasoning_readonly_prefix
        and (lt:find("%f[%w]your%f[%W]") ~= nil
          or lt:find("%f[%w]you%f[%W]") ~= nil))
end

function Code.prompt_requests_reusable_action_script(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if lt == "" or Code.prompt_is_question_or_readonly(user_text) then
    return false
  end

  local action_list = lt:find("action list", 1, true) ~= nil
    or lt:find("actions list", 1, true) ~= nil
    or lt:find("action%-list") ~= nil
  local shortcut_trigger = lt:find("keyboard shortcut", 1, true) ~= nil
    or lt:find("shortcut key", 1, true) ~= nil
    or lt:find("create shortcut", 1, true) ~= nil
    or lt:find("make shortcut", 1, true) ~= nil
    or lt:find("add shortcut", 1, true) ~= nil
    or lt:find("assign shortcut", 1, true) ~= nil
    or lt:find("bind shortcut", 1, true) ~= nil
    or lt:find("shortcut for", 1, true) ~= nil
    or lt:find("shortcut to", 1, true) ~= nil
    or lt:find("shortcut in", 1, true) ~= nil
  local action_list_trigger = action_list and (
       lt:find("%f[%w]script%f[%W]") ~= nil
    or lt:find("%f[%w]reascript%f[%W]") ~= nil
    or shortcut_trigger
    or lt:find("%f[%w]hotkey%f[%W]") ~= nil
    or lt:find("add to action", 1, true) ~= nil
    or lt:find("add to the action", 1, true) ~= nil
    or lt:find("create an action", 1, true) ~= nil
    or lt:find("install", 1, true) ~= nil
    or lt:find("register", 1, true) ~= nil)
  local trigger_noun = action_list_trigger or shortcut_trigger
    or lt:find("%f[%w]hotkey%f[%W]") ~= nil
    or lt:find("toolbar button", 1, true) ~= nil
    or lt:find("key press", 1, true) ~= nil
    or lt:find("keypress", 1, true) ~= nil
    or lt:find("keystroke", 1, true) ~= nil
  local install_verb = lt:find("%f[%w]assign%f[%W]") ~= nil
    or lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]bind%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]install%f[%W]") ~= nil
    or lt:find("%f[%w]make%f[%W]") ~= nil
    or lt:find("%f[%w]register%f[%W]") ~= nil
    or lt:find("%f[%w]save%f[%W]") ~= nil
    or lt:find("%f[%w]set up%f[%W]") ~= nil
    or lt:find("%f[%w]setup%f[%W]") ~= nil
  local later_trigger = lt:find("when pressing", 1, true) ~= nil
    or lt:find("when i press", 1, true) ~= nil
    or lt:find("when the key is pressed", 1, true) ~= nil
    or lt:find("when that key is pressed", 1, true) ~= nil
    or lt:find("using a shortcut", 1, true) ~= nil
    or lt:find("with a shortcut", 1, true) ~= nil
    or lt:find("via a shortcut", 1, true) ~= nil
    or lt:find("run it later", 1, true) ~= nil
    or lt:find("run later", 1, true) ~= nil
  local press_trigger = lt:find("%f[%w]press%f[%W]") ~= nil
    or lt:find("%f[%w]pressing%f[%W]") ~= nil
    or lt:find("%f[%w]pressed%f[%W]") ~= nil
  return trigger_noun and (install_verb or later_trigger)
    or (later_trigger and (install_verb or press_trigger))
end

function Code.prompt_requests_save_actions_help(user_text, candidate)
  if type(candidate) ~= "table"
      or type(candidate.code) ~= "string" or candidate.code == ""
      or candidate.code_type ~= "lua" then
    return false
  end
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if lt == ""
      or not Code.latest_code_prompt_refers_to_candidate(user_text) then
    return false
  end
  local procedural_question = lt:find("^how%s+") ~= nil
    or lt:find("^where%s+") ~= nil
    or lt:find("^show%s+me%s+how%s+") ~= nil
    or lt:find("^tell%s+me%s+how%s+") ~= nil
    or lt:find("^can%s+you%s+show%s+me%s+how%s+") ~= nil
    or lt:find("^could%s+you%s+show%s+me%s+how%s+") ~= nil
  if not procedural_question then return false end
  return lt:find("%f[%w]save%f[%W]") ~= nil
    or lt:find("%f[%w]install%f[%W]") ~= nil
    or lt:find("add to actions", 1, true) ~= nil
    or lt:find("actions list", 1, true) ~= nil
    or lt:find("action list", 1, true) ~= nil
    or lt:find("%f[%w]shortcut%f[%W]") ~= nil
    or lt:find("%f[%w]hotkey%f[%W]") ~= nil
end

function Code.prompt_is_ideation_advice_followup(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if lt == "" then return false end

  local has_concrete_action =
       lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]apply%f[%W]") ~= nil
    or lt:find("%f[%w]configure%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]execute%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]load%f[%W]") ~= nil
    or lt:find("%f[%w]proceed%f[%W]") ~= nil
    or lt:find("%f[%w]put%f[%W]") ~= nil
    or lt:find("%f[%w]route%f[%W]") ~= nil
    or lt:find("%f[%w]routing%f[%W]") ~= nil
    or lt:find("%f[%w]run%f[%W]") ~= nil
    or lt:find("%f[%w]send%f[%W]") ~= nil
    or lt:find("%f[%w]arm%f[%W]") ~= nil
    or lt:find("%f[%w]automate%f[%W]") ~= nil
    or lt:find("%f[%w]bounce%f[%W]") ~= nil
    or lt:find("%f[%w]bus%f[%W]") ~= nil
    or lt:find("%f[%w]compress%f[%W]") ~= nil
    or lt:find("%f[%w]copy%f[%W]") ~= nil
    or lt:find("%f[%w]deess%f[%W]") ~= nil
    or lt:find("%f[%w]de%-ess%f[%W]") ~= nil
    or lt:find("%f[%w]delete%f[%W]") ~= nil
    or lt:find("%f[%w]duplicate%f[%W]") ~= nil
    or lt:find("%f[%w]eq%f[%W]") ~= nil
    or lt:find("%f[%w]fade%f[%W]") ~= nil
    or lt:find("%f[%w]freeze%f[%W]") ~= nil
    or lt:find("%f[%w]gate%f[%W]") ~= nil
    or lt:find("%f[%w]group%f[%W]") ~= nil
    or lt:find("%f[%w]limit%f[%W]") ~= nil
    or lt:find("%f[%w]mute%f[%W]") ~= nil
    or lt:find("%f[%w]normalize%f[%W]") ~= nil
    or lt:find("%f[%w]pan%f[%W]") ~= nil
    or lt:find("%f[%w]parallel%f[%W]") ~= nil
    or lt:find("%f[%w]quantize%f[%W]") ~= nil
    or lt:find("%f[%w]remove%f[%W]") ~= nil
    or lt:find("%f[%w]rename%f[%W]") ~= nil
    or lt:find("%f[%w]replace%f[%W]") ~= nil
    or lt:find("%f[%w]render%f[%W]") ~= nil
    or lt:find("%f[%w]reverse%f[%W]") ~= nil
    or lt:find("%f[%w]move%f[%W]") ~= nil
    or lt:find("%f[%w]select%f[%W]") ~= nil
    or lt:find("%f[%w]sidechain%f[%W]") ~= nil
    or lt:find("%f[%w]side%-chain%f[%W]") ~= nil
    or lt:find("%f[%w]solo%f[%W]") ~= nil
    or lt:find("%f[%w]split%f[%W]") ~= nil
    or lt:find("%f[%w]swap%f[%W]") ~= nil
    or lt:find("%f[%w]trim%f[%W]") ~= nil
    or lt:find("%f[%w]ungroup%f[%W]") ~= nil
    or lt:find("set%s+up") ~= nil
    or lt:find("%f[%w]setup%f[%W]") ~= nil
    or lt:find("%f[%w]do%s+it%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+a%s+track%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+the%s+track%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+the%s+selected%s+track%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+selected%s+track%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+tracks%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+a%s+bus%f[%W]") ~= nil
    or lt:find("%f[%w]make%s+a%s+folder%f[%W]") ~= nil
    or lt:find("^is%s+it%s+ok%s+to%s+use%s+.+%s+on%s+") ~= nil
    or lt:find("^is%s+it%s+okay%s+to%s+use%s+.+%s+on%s+") ~= nil
    or lt:find("^should%s+i%s+use%s+.+%s+on%s+") ~= nil
    or lt:find("^should%s+we%s+use%s+.+%s+on%s+") ~= nil
  if has_concrete_action then return false end

  local asks_for_library_tags =
       ((lt:find("sound%s+library") ~= nil
         or lt:find("sample%s+library") ~= nil)
        and (lt:find("%f[%w]tag%f[%W]") ~= nil
          or lt:find("%f[%w]tags%f[%W]") ~= nil
          or lt:find("%f[%w]search%f[%W]") ~= nil
          or lt:find("%f[%w]find%f[%W]") ~= nil
          or lt:find("look%s+for") ~= nil))
    or lt:find("tags%s+should%s+we%s+use") ~= nil
    or lt:find("which%s+tags%s+should%s+we%s+use") ~= nil

  return asks_for_library_tags
    or lt:find("%f[%w]ideation%f[%W]") ~= nil
    or lt:find("plan%s+before%s+doing") ~= nil
    or lt:find("before%s+doing%s+anything") ~= nil
    or lt:find("^is%s+it%s+ok%s+to%s+") ~= nil
    or lt:find("^is%s+it%s+okay%s+to%s+") ~= nil
    or lt:find("^would%s+it%s+be%s+ok%s+to%s+") ~= nil
    or lt:find("^would%s+it%s+be%s+okay%s+to%s+") ~= nil
    or lt:find("^does%s+it%s+make%s+sense%s+to%s+") ~= nil
    or lt:find("^should%s+i%s+") ~= nil
    or lt:find("^should%s+we%s+") ~= nil
    or lt:find("^what%s+if%s+") ~= nil
    or lt:find("^i%s+was%s+thinking%s+") ~= nil
end

function Code.history_has_prior_assistant(history)
  if type(history) ~= "table" then return false end
  for i = #history, 1, -1 do
    local item = history[i]
    if type(item) == "table"
       and item.role == "assistant"
       and tostring(item.content or ""):match("%S") then
      return true
    end
  end
  return false
end

function Code._typed_action_user_requests_master_send_state(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("%s+", " ")
  if lt == "" then return false end
  return Code._typed_action_user_requests_master_send_off(user_text) == true
    or lt:find("master send", 1, true) ~= nil
    or lt:find("master sends", 1, true) ~= nil
    or lt:find("main send", 1, true) ~= nil
    or lt:find("main sends", 1, true) ~= nil
    or lt:find("master/parent", 1, true) ~= nil
    or lt:find("master parent", 1, true) ~= nil
    or lt:find("parent send", 1, true) ~= nil
    or lt:find("parent sends", 1, true) ~= nil
    or lt:find("master output", 1, true) ~= nil
    or lt:find("master_send", 1, true) ~= nil
    or lt:find("going only to the master", 1, true) ~= nil
    or lt:find("only goes to master", 1, true) ~= nil
    or lt:find("only to the master", 1, true) ~= nil
end

function Code._typed_action_user_requests_master_send_off(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("[’']", "")
    :gsub("%s+", " ")
  if lt == "" then return false end
  for _, phrase in ipairs({
    "turn off master send",
    "turn off the master send",
    "disable master send",
    "disable the master send",
    "master_send false",
    "master send false",
    "no master send",
    "without master send",
    "does not go to the master",
    "doesnt go to the master",
    "do not go to the master",
    "dont go to the master",
    "not go to the master",
    "does not feed the master",
    "doesnt feed the master",
    "do not feed the master",
    "dont feed the master",
    "not feed the master",
    "does not route to the master",
    "doesnt route to the master",
    "not routed to the master",
    "not routing to the master",
    "out of the master",
    "away from the master",
    "separate from the main mix",
    "away from the main mix",
  }) do
    if lt:find(phrase, 1, true) then return true end
  end
  if lt:find("do not send[^%.\n;:]-to the master")
      or lt:find("dont send[^%.\n;:]-to the master")
      or lt:find("without sending[^%.\n;:]-to the master") then
    return true
  end
  return false
end

function Code._typed_action_user_requests_record_ready_state(user_text)
  local lt = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("[’']", "")
    :gsub("%s+", " ")
  if lt == "" then return false end
  for _, phrase in ipairs({
    "ready for recording",
    "ready to record",
    "record ready",
    "record-ready",
    "record armed",
    "record-armed",
    "record arm",
    "arm for recording",
    "armed for recording",
  }) do
    if lt:find(phrase, 1, true) then return true end
  end
  return lt:find("%f[%w]arm%f[%W]%s+[^%.\n;:]-record") ~= nil
end

function Code._typed_action_user_requests_track_deletion(user_text)
  local text = Code._typed_action_user_request_text(user_text)
    :lower()
    :gsub("[’']", "")
    :gsub("%s+", " ")
  if text == "" then return false end
  for _, phrase in ipairs({
    "do not create, delete, rename, mute, solo, pan, or change any other tracks",
    "do not create, delete, rename, mute, solo, pan, or change any other track",
    "do not create, delete, rename, mute, pan, or change any other tracks",
    "do not create, delete, rename, mute, pan, or change any other track",
    "do not create, delete, rename, solo, or change any other tracks",
    "do not create, delete, rename, solo, or change any other track",
    "do not create, delete, or rename any other tracks",
    "do not create, delete, or rename any other track",
    "do not create, delete or rename any other tracks",
    "do not create, delete or rename any other track",
    "do not create, delete, or rename any tracks",
    "do not create, delete, or rename any track",
    "do not create, delete or rename any tracks",
    "do not create, delete or rename any track",
    "do not delete any tracks",
    "do not delete any track",
    "don't delete any tracks",
    "don't delete any track",
    "do not remove any tracks",
    "do not remove any track",
    "don't remove any tracks",
    "don't remove any track",
    "without deleting tracks",
    "without deleting any tracks",
    "without removing tracks",
    "without removing any tracks",
  }) do
    text = text:gsub(phrase, "")
  end
  local object_words = {
    "track", "tracks", "selected", "current", "existing", "empty",
  }
  local function has_track_object(fragment)
    for _, word in ipairs(object_words) do
      if fragment:find("%f[%w]" .. word .. "%f[%W]") then return true end
    end
    return false
  end
  for clause in text:gmatch("[^%.\n;:]+") do
    if has_track_object(clause)
        and (clause:find("%f[%w]delete%f[%W]")
          or clause:find("%f[%w]remove%f[%W]")
          or clause:find("%f[%w]clear%f[%W]")
          or clause:find("%f[%w]wipe%f[%W]")) then
      return true
    end
    if clause:find("%f[%w]start%s+from%s+scratch%f[%W]")
        or clause:find("%f[%w]clear%s+the%s+project%f[%W]")
        or clause:find("%f[%w]empty%s+the%s+project%f[%W]") then
      return true
    end
  end
  return false
end

function Code._typed_action_track_property_intent_text(user_text)
  local text = Code._localized_action_intent_text(user_text)
  text = text
    :gsub("post%-fader", "")
    :gsub("post fader", "")
    :gsub("pre%-fader", "")
    :gsub("pre fader", "")
  for _, phrase in ipairs({
    "do not create, delete, rename, mute, solo, pan, or change any other tracks",
    "do not create, delete, rename, mute, solo, pan, or change any other track",
    "do not create, delete, rename, mute, pan, or change any other tracks",
    "do not create, delete, rename, mute, pan, or change any other track",
    "do not create, delete, rename, solo, or change any other tracks",
    "do not create, delete, rename, solo, or change any other track",
    "do not rename, mute, solo, pan, or change any other tracks",
    "do not rename, mute, solo, pan, or change any other track",
    "do not rename, mute, pan, or change any other tracks",
    "do not rename, mute, pan, or change any other track",
    "do not create, delete, rename, mute, solo, pan",
    "do not create, delete, rename, mute, pan",
    "do not create, delete, rename, solo",
    "do not rename, mute, solo, pan",
    "do not rename, mute, pan",
    "do not rename any tracks",
    "do not rename any track",
    "don't rename any tracks",
    "don't rename any track",
    "without renaming",
    "rename any tracks",
    "rename any track",
    "no rename",
    "not rename",
    "do not rename",
    "don't rename",
    "do not mute any tracks",
    "do not mute any track",
    "don't mute any tracks",
    "don't mute any track",
    "without muting",
    "mute any tracks",
    "mute any track",
    "no mute",
    "not mute",
    "do not mute",
    "don't mute",
    "do not solo any tracks",
    "do not solo any track",
    "don't solo any tracks",
    "don't solo any track",
    "without soloing",
    "solo any tracks",
    "solo any track",
    "no solo",
    "not solo",
    "do not solo",
    "don't solo",
    "do not pan any tracks",
    "do not pan any track",
    "don't pan any tracks",
    "don't pan any track",
    "without panning",
    "pan any tracks",
    "pan any track",
    "no pan",
    "not pan",
    "do not pan",
    "don't pan",
  }) do
    text = text:gsub(phrase, "")
  end
  return text
end

function Code._typed_action_static_pan_value(user_text)
  local text = Code._typed_action_track_property_intent_text(user_text):lower()
  local first_value, value_count, conflicting = nil, 0, false

  local function add_value(raw, direction)
    local value = tonumber(raw)
    if not value then return end
    value = math.abs(value) * direction
    if value == 0 then value = 0 end
    value_count = value_count + 1
    if first_value == nil then
      first_value = value
    elseif math.abs(first_value - value) > 0.000000001 then
      conflicting = true
    end
  end

  for raw in text:gmatch("([%+%-]?%d+%.?%d*)%s*percent%s+right") do
    add_value(raw, 1)
  end
  for raw in text:gmatch("([%+%-]?%d+%.?%d*)%s*%%%s*right") do
    add_value(raw, 1)
  end
  for raw in text:gmatch("([%+%-]?%d+%.?%d*)%s*percent%s+left") do
    add_value(raw, -1)
  end
  for raw in text:gmatch("([%+%-]?%d+%.?%d*)%s*%%%s*left") do
    add_value(raw, -1)
  end

  if conflicting then return nil, true, value_count end
  return first_value, false, value_count
end

function Code._typed_action_user_requests_aggregate_track_property_target(user_text)
  local text = Code._typed_action_track_property_intent_text(user_text)
    :gsub("[^%w]+", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if text == "" then return false end
  local words = " " .. text .. " "
  local property_terms = {
    "volume", "vol", "fader", "level", "pan", "panned", "mute", "muted", "unmute",
    "solo", "soloed", "unsolo", "master send", "main send",
    "master parent", "parent send", "master output", "rename",
    "renamed", "call", "called",
  }
  local has_property = false
  for _, term in ipairs(property_terms) do
    if words:find(" " .. term .. " ", 1, true) then
      has_property = true
      break
    end
  end
  if not has_property then return false end
  for _, phrase in ipairs({
    "all tracks",
    "all my tracks",
    "all the tracks",
    "all of the tracks",
    "all existing tracks",
    "all project tracks",
    "all audio tracks",
    "all midi tracks",
    "all selected tracks",
    "every track",
    "every existing track",
    "every project track",
    "every audio track",
    "every midi track",
    "every selected track",
    "each track",
    "each existing track",
    "each project track",
    "each audio track",
    "each midi track",
    "each selected track",
  }) do
    if words:find(" " .. phrase .. " ", 1, true) then return true end
  end
  return false
end

function Code._typed_action_strip_quoted_literals(user_text)
  local value = tostring(user_text or "")

  local function word_at(pos)
    if pos < 1 or pos > #value then return false end
    return value:sub(pos, pos):match("[%w]") ~= nil
  end

  local function strip_pairs(open_quote, close_quote, boundary_open, boundary_close)
    local out, emit_pos, search_pos = {}, 1, 1
    while true do
      local open_pos = value:find(open_quote, search_pos, true)
      if not open_pos then break end
      if boundary_open and word_at(open_pos - 1) then
        search_pos = open_pos + #open_quote
      else
        local line_break = value:find("[\r\n]", open_pos + #open_quote)
        local close_pos = value:find(
          close_quote, open_pos + #open_quote, true)
        if close_pos and line_break and close_pos > line_break then
          close_pos = nil
        end
        while close_pos
            and boundary_close
            and word_at(close_pos + #close_quote) do
          close_pos = value:find(
            close_quote, close_pos + #close_quote, true)
          if close_pos and line_break and close_pos > line_break then
            close_pos = nil
          end
        end
        if close_pos then
          out[#out + 1] = value:sub(emit_pos, open_pos - 1)
          out[#out + 1] = " "
          emit_pos = close_pos + #close_quote
          search_pos = emit_pos
        else
          search_pos = open_pos + #open_quote
        end
      end
    end
    out[#out + 1] = value:sub(emit_pos)
    value = table.concat(out)
  end

  strip_pairs('"', '"', false, false)
  strip_pairs("'", "'", true, true)
  strip_pairs("“", "”", false, false)
  strip_pairs("‘", "’", false, true)
  return value
end

function Code._typed_action_user_requests_predicate_track_property_target(user_text)
  local raw_text = Code._typed_action_user_request_text(user_text):lower()
  local predicate_text = Code._typed_action_strip_quoted_literals(raw_text)
  local text = predicate_text
    :gsub("[^%w]+", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if text == "" then return false end
  local words = " " .. text .. " "
  local has_track_target = words:find(" track ", 1, true) ~= nil
    or words:find(" tracks ", 1, true) ~= nil
    or words:find(" selected ", 1, true) ~= nil
  if not has_track_target then return false end

  local has_property = false
  for _, term in ipairs({
    "volume", "vol", "fader", "level", "pan", "panned", "mute", "muted",
    "unmute", "solo", "soloed", "unsolo", "master send", "main send",
    "master parent", "parent send", "master output", "rename", "renamed",
    "call", "called",
  }) do
    if words:find(" " .. term .. " ", 1, true) then
      has_property = true
      break
    end
  end
  if not has_property then
    has_property = Code._typed_action_user_requests_track_level_change(user_text)
  end
  if not has_property
      and predicate_text:find("[%+%-]?%d+%.?%d*%s*[dD][bB]") then
    has_property = true
  end
  if not has_property then return false end

  for _, phrase in ipairs({
    "if a selected track", "if any selected track", "if the selected track",
    "if selected tracks", "if a track", "if any track", "if the track",
    "if tracks", "when a selected track", "when any selected track",
    "when the selected track", "when selected tracks", "when a track",
    "when any track", "when the track", "when tracks",
    "track ends in", "track ends with", "track ending in", "track ending with",
    "tracks end in", "tracks end with", "tracks ending in", "tracks ending with",
    "track starts in", "track starts with", "track starting in", "track starting with",
    "tracks start in", "tracks start with", "tracks starting in", "tracks starting with",
    "track contains", "track containing", "tracks contain", "tracks containing",
    "track whose name", "tracks whose name", "track name ends", "track name starts",
    "track name contains", "tracks matching", "track matching",
    "tracks that end", "track that ends", "tracks that start", "track that starts",
  }) do
    if words:find(" " .. phrase .. " ", 1, true) then return true end
  end
  return false
end

function Code._typed_action_user_requests_track_level_change(user_text)
  local text = Code._typed_action_track_property_intent_text(user_text)
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
  if text == "" then return false end

  local function has_word(fragment, word)
    return fragment:find("%f[%w]" .. word .. "%f[%W]") ~= nil
  end

  local function has_track_target(fragment)
    return has_word(fragment, "track")
      or has_word(fragment, "tracks")
      or has_word(fragment, "bus")
      or has_word(fragment, "buses")
      or has_word(fragment, "aux")
      or has_word(fragment, "selected")
  end

  local function has_db_value(fragment)
    return fragment:find("[%+%-]?%d+%.?%d*%s*[dD][bB]") ~= nil
  end

  local function has_explicit_track_level_word(fragment)
    return has_word(fragment, "volume")
      or has_word(fragment, "fader")
      or has_word(fragment, "level")
  end

  local function has_fx_db_target(fragment)
    if fragment:find("%f[%d]%d+%.?%d*%s*[kK]?[hH][zZ]%f[%W]") then
      return true
    end
    for _, word in ipairs({
      "threshold", "ceiling", "ratio", "attack", "release", "hold",
      "knee", "band", "filter", "frequency", "freq", "wet", "dry",
      "mix", "feedback", "drive", "input", "output",
    }) do
      if has_word(fragment, word) then return true end
    end
    if fragment:find("%f[%w]make%W*up%f[%W]") then return true end
    if has_word(fragment, "gain") then
      return has_word(fragment, "eq")
        or has_word(fragment, "band")
        or has_word(fragment, "filter")
        or has_word(fragment, "plugin")
        or has_word(fragment, "fx")
    end
    return false
  end

  for clause in text:gmatch("[^%.\n;:,]+") do
    if has_track_target(clause) and has_db_value(clause) then
      if has_explicit_track_level_word(clause) then
        return true
      end
      if not has_fx_db_target(clause) then
        for _, word in ipairs({
          "pull", "pulled", "lower", "lowered", "drop", "dropped",
          "reduce", "reduced", "trim", "trimmed", "bring", "brought",
          "take", "took",
        }) do
          if has_word(clause, word) then return true end
        end
      end
    end
  end

  return false
end

function Code._typed_action_send_intent_text(user_text)
  local text = Code._typed_action_user_request_text(user_text):lower()
  text = text
    :gsub("master/parent send", "")
    :gsub("master send", "")
    :gsub("main send", "")
    :gsub("master parent send", "")
    :gsub("parent send", "")
  for _, pattern in ipairs({
    "do not add[^%.\n;:]-sends?[^%.\n;:]*",
    "don't add[^%.\n;:]-sends?[^%.\n;:]*",
    "do not create[^%.\n;:]-sends?[^%.\n;:]*",
    "don't create[^%.\n;:]-sends?[^%.\n;:]*",
    "without[^%.\n;:]-sends?[^%.\n;:]*",
    "no%s+other%s+sends?[^%.\n;:]*",
    "no%s+sends?[^%.\n;:]*",
  }) do
    text = text:gsub(pattern, "")
  end
  return text
end

function Code.typed_action_user_requests_hardware_output(user_text)
  local lt = Code._typed_action_user_request_text(user_text):lower()
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
  if lt == "" then return false end

  if lt:find("hardware output", 1, true)
      or lt:find("hardware outputs", 1, true)
      or lt:find("hardware out", 1, true)
      or lt:find("physical output", 1, true)
      or lt:find("physical outputs", 1, true) then
    return true
  end

  for _, pat in ipairs({
    "%f[%w]output%s*%d",
    "%f[%w]outputs%s*%d",
    "%f[%w]out%s*%d",
    "%f[%w]outs%s*%d",
    "%f[%w]uscita%s*%d",
    "%f[%w]uscite%s*%d",
    "%d%s*/%s*%d%s+output%f[%W]",
    "%d%s*/%s*%d%s+outputs%f[%W]",
    "%d%s*/%s*%d%s+out%f[%W]",
    "%d%s*/%s*%d%s+outs%f[%W]",
    "%d%s*/%s*%d%s+uscita%f[%W]",
    "%d%s*/%s*%d%s+uscite%f[%W]",
  }) do
    if lt:find(pat) then return true end
  end

  return false
end

function Code.typed_action_user_requests_track_creation(user_text)
  local u = Code._typed_action_user_request_text(user_text):lower()
  local mentions_existing_targets =
    u:find("existing track", 1, true) ~= nil
    or u:find("existing tracks", 1, true) ~= nil
    or u:find("resolve the existing", 1, true) ~= nil
  local creation_text = u
  for _, pattern in ipairs({
    "do not create[^%.\n;]*tracks?",
    "don't create[^%.\n;]*tracks?",
    "do not add[^%.\n;]*tracks?",
    "don't add[^%.\n;]*tracks?",
    "do not make[^%.\n;]*tracks?",
    "don't make[^%.\n;]*tracks?",
  }) do
    creation_text = creation_text:gsub(pattern, "")
  end
  local explicit_creation =
    u:find("blank project", 1, true) ~= nil
    or u:find("blank-project", 1, true) ~= nil
    or u:find("blank reaper project", 1, true) ~= nil
    or creation_text:match("%f[%w]create%s+[%w%-]+%s+tracks?") ~= nil
    or creation_text:match("%f[%w]create%s+[%w%-]+%s+new%s+tracks?") ~= nil
    or creation_text:match("%f[%w]create%s+a%s+new%s+track") ~= nil
    or creation_text:match("%f[%w]create%s+tracks?%s+#?%d+") ~= nil
    or creation_text:match("%f[%w]create[^%.\n;]-tracks%f[%W]") ~= nil
    or creation_text:match("%f[%w]add%s+[%w%-]+%s+tracks?") ~= nil
    or creation_text:match("%f[%w]add%s+[%w%-]+%s+new%s+tracks?") ~= nil
    or creation_text:match("%f[%w]make%s+[%w%-]+%s+tracks?") ~= nil
    or creation_text:match("%f[%w]make%s+[%w%-]+%s+new%s+tracks?") ~= nil
    or creation_text:match("%f[%w]make[^%.\n;]-tracks%f[%W]") ~= nil
    or creation_text:match("%f[%w]insert%s+[%w%-]+%s+tracks?") ~= nil
    or creation_text:match("%f[%w]insert%s+[%w%-]+%s+new%s+tracks?") ~= nil
    or creation_text:match("create exactly%s+[%w%-]+%s+tracks?") ~= nil
    or creation_text:match("create exactly%s+[%w%-]+%s+new%s+tracks?") ~= nil
    or creation_text:find("create one track", 1, true) ~= nil
    or creation_text:find("create two tracks", 1, true) ~= nil
    or creation_text:find("create three tracks", 1, true) ~= nil
    or creation_text:find("create four tracks", 1, true) ~= nil
    or creation_text:find("create five tracks", 1, true) ~= nil
    or creation_text:find("create six tracks", 1, true) ~= nil
    or creation_text:match("%f[%w]create[^%.\n;]-bus%s+named%f[%W]") ~= nil
    or creation_text:match("%f[%w]create[^%.\n;]-buses%s+named%f[%W]") ~= nil
    or creation_text:match("%f[%w]create[^%.\n;]-return%s+named%f[%W]") ~= nil
    or creation_text:match("%f[%w]create[^%.\n;]-returns%s+named%f[%W]") ~= nil
    or creation_text:match("%f[%w]create%s+one%s+[%w%-]+%s+bus%f[%W]") ~= nil
    or creation_text:match("%f[%w]create%s+one%s+[%w%-]+%s+return%f[%W]") ~= nil
    or creation_text:match("%f[%w]append[^%.\n;]-bus%f[%W]") ~= nil
    or creation_text:match("%f[%w]append[^%.\n;]-buses%f[%W]") ~= nil
    or creation_text:match("%f[%w]append[^%.\n;]-return%f[%W]") ~= nil
    or creation_text:match("%f[%w]append[^%.\n;]-returns%f[%W]") ~= nil
    or creation_text:match("%f[%w]set%s+up[^%.\n;]-stack%f[%W]") ~= nil
    or creation_text:match("%f[%w]setup[^%.\n;]-stack%f[%W]") ~= nil
    or creation_text:match("%f[%w]build[^%.\n;]-routing%s+plan%f[%W]") ~= nil
    or creation_text:match("%f[%w]build[^%.\n;]-routing%s+setup%f[%W]") ~= nil
    or creation_text:find("routing template", 1, true) ~= nil
  return explicit_creation == true
    or (mentions_existing_targets and explicit_creation == true)
end

function Code.typed_action_user_requests_track_ensure(user_text)
  local u = Code._typed_action_user_request_text(user_text):lower()
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
  if u == "" then return false end
  return u:find("%f[%w]ensure%f[%W]") ~= nil
    or u:find("if missing", 1, true) ~= nil
    or u:find("if it is missing", 1, true) ~= nil
    or u:find("if it's missing", 1, true) ~= nil
    or u:find("%f[%w]reuse%f[%W]") ~= nil
    or u:find("%f[%w]re%-use%f[%W]") ~= nil
end

function Code.typed_action_user_forbids_track_creation(user_text)
  if Code.typed_action_user_requests_track_creation(user_text)
      and not Code.typed_action_user_requests_selected_target(user_text) then
    return false
  end
  local u = Code._typed_action_user_request_text(user_text):lower()
  for _, pattern in ipairs({
    "do not create[^%.\n;]*tracks?",
    "don't create[^%.\n;]*tracks?",
    "do not add[^%.\n;]*tracks?",
    "don't add[^%.\n;]*tracks?",
    "do not make[^%.\n;]*tracks?",
    "don't make[^%.\n;]*tracks?",
    "do not create[^%.\n;]*replacement%s+tracks?",
    "don't create[^%.\n;]*replacement%s+tracks?",
    "no%s+new%s+tracks?",
    "no%s+replacement%s+tracks?",
  }) do
    if u:match(pattern) then return true end
  end
  return false
end

function Code.typed_action_user_requests_selected_target(user_text)
  local clean_text = Code._typed_action_user_request_text(user_text)
  local u = clean_text:lower()
  local _, selected_index_required =
    Code._typed_action_selected_indexes_from_user_text(clean_text)
  return selected_index_required
    or u:find("selected track", 1, true) ~= nil
    or u:find("selected tracks", 1, true) ~= nil
    or u:find("currently selected", 1, true) ~= nil
end

-- True only when the current request itself uses selected/current-track
-- language for an action. This deliberately excludes read-only questions and
-- loose combinations such as "current volume" plus a later "track" word.
function Code.prompt_requests_request_time_track_target(user_text)
  local clean_text = Code._typed_action_user_request_text(user_text)
  if clean_text == "" or Code.prompt_is_question_or_readonly(clean_text) then
    return false
  end
  local u = clean_text:lower():gsub("[%c]+", " "):gsub("%s+", " ")
  return Code.typed_action_user_requests_selected_target(clean_text)
    or u:find("track selected", 1, true) ~= nil
    or u:find("tracks selected", 1, true) ~= nil
    or u:find("track i selected", 1, true) ~= nil
    or u:find("tracks i selected", 1, true) ~= nil
    or u:find("track i have selected", 1, true) ~= nil
    or u:find("tracks i have selected", 1, true) ~= nil
    or u:find("track that is selected", 1, true) ~= nil
    or u:find("tracks that are selected", 1, true) ~= nil
    or u:find("current track", 1, true) ~= nil
end

function Code.typed_action_user_mentions_existing_or_source_track(user_text)
  local u = Code._typed_action_user_request_text(user_text):lower()
    :gsub("[%c]+", " ")
    :gsub("%s+", " ")
  if u == "" then return false end
  return u:find("existing", 1, true) ~= nil
    or u:find("source track", 1, true) ~= nil
    or u:find("source tracks", 1, true) ~= nil
    or u:find("selected track", 1, true) ~= nil
    or u:find("selected tracks", 1, true) ~= nil
    or u:find("currently selected", 1, true) ~= nil
    or u:find("already a track", 1, true) ~= nil
    or u:find("already tracks", 1, true) ~= nil
    or u:find("already have a track", 1, true) ~= nil
    or u:find("already has a track", 1, true) ~= nil
end

function Code.typed_action_user_requests_folder(user_text)
  local u = Code._typed_action_user_request_text(user_text):lower()
  for _, phrase in ipairs({
    "do not create folders",
    "do not create a folder",
    "do not make folders",
    "do not make a folder",
    "don't create folders",
    "don't create a folder",
    "don't make folders",
    "don't make a folder",
    "without folders",
    "without a folder",
    "no folders",
    "no folder",
    "not folders",
    "not a folder",
  }) do
    u = u:gsub(phrase, "")
  end
  local has_folder =
    u:find("folder", 1, true) ~= nil
    or u:find("folders", 1, true) ~= nil
  if not has_folder then return false end
  return u:find("track", 1, true) ~= nil
    or u:find("tracks", 1, true) ~= nil
    or u:find("parent", 1, true) ~= nil
    or u:find("contain", 1, true) ~= nil
    or u:find("containing", 1, true) ~= nil
    or u:find("create", 1, true) ~= nil
    or u:find("make", 1, true) ~= nil
    or u:find("set up", 1, true) ~= nil
    or u:find("setup", 1, true) ~= nil
    or u:find("build", 1, true) ~= nil
end

-- Repair pass for predictable malformed typed-action JSON. Repairs are limited
-- to shape-preserving or intent-preserving changes; ambiguous/unsafe plans stay
-- invalid and flow into the retry/escalation path instead.
function Code.repair_typed_actions_plan(plan, opts)
  opts = type(opts) == "table" and opts or {}
  if not _typed_action_is_object(plan)
     or not _typed_action_is_array(plan.actions) then
    return plan, false
  end

  local repaired = false
  do
    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      if type(action) == "table"
         and action.op == "fx.set_param"
         and (_typed_action_is_object(action.params)
              and next(action.params) == nil) then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 and #out > 0 then
      plan.actions = out
      repaired = true
    end
  end

  do
    local add_stock_ids_by_fx, param_actions_by_fx = {}, {}
    for _, action in ipairs(plan.actions) do
      if action.op == "fx.add_stock"
         and _typed_action_is_nonempty_string(action.id)
         and _TYPED_ACTION_STOCK_FX[action.fx] then
        local list = add_stock_ids_by_fx[action.fx]
        if not list then
          list = {}
          add_stock_ids_by_fx[action.fx] = list
        end
        list[#list + 1] = action.id
      elseif action.op == "fx.set_param"
         and _typed_action_is_nonempty_string(action.fx)
         and _TYPED_ACTION_STOCK_FX[action.fx] then
        local list = param_actions_by_fx[action.fx]
        if not list then
          list = {}
          param_actions_by_fx[action.fx] = list
        end
        list[#list + 1] = action
      end
    end

    for fx_name, param_actions in pairs(param_actions_by_fx) do
      local fx_ids = add_stock_ids_by_fx[fx_name]
      if fx_ids and #fx_ids == #param_actions then
        for i, action in ipairs(param_actions) do
          action.fx = fx_ids[i]
          repaired = true
        end
      end
    end
  end

  local user_text = tostring(opts.user_text or "")
  if user_text == "" then return plan, repaired end

  local user_text_lower = user_text:lower()
  do
    local absolute_indexes =
      Code._typed_action_absolute_track_indexes_from_user_text(user_text)
    local sole_resolve = nil
    local resolve_count = 0
    for _, action in ipairs(plan.actions) do
      if type(action) == "table" and action.op == "track.resolve" then
        resolve_count = resolve_count + 1
        sole_resolve = action
      end
    end
    if #absolute_indexes == 1
       and resolve_count == 1
       and not Code.typed_action_user_requests_selected_target(user_text)
       and not Code.typed_action_user_requests_track_creation(user_text)
       and not Code._typed_action_forbids_absolute_track_index(user_text) then
      local target_index = absolute_indexes[1]
      if sole_resolve.index ~= target_index
         or sole_resolve.name ~= nil
         or sole_resolve.selected ~= nil
         or sole_resolve.selected_index ~= nil then
        sole_resolve.index = target_index
        sole_resolve.name = nil
        sole_resolve.selected = nil
        sole_resolve.selected_index = nil
        repaired = true
      end
    end
  end
  if Code.typed_action_user_requests_selected_target(user_text) then
    local selected_indexes, selected_index_required =
      Code._typed_action_selected_indexes_from_user_text(user_text)
    for _, action in ipairs(plan.actions) do
      if type(action) == "table" and action.op == "track.resolve" then
        if type(action.selected_index) == "number" then
          if action.name ~= nil or action.index ~= nil
             or action.selected ~= nil then
            action.name = nil
            action.index = nil
            action.selected = nil
            repaired = true
          end
        elseif action.selected == true then
          if selected_index_required and #selected_indexes == 1 then
            action.selected = nil
            action.name = nil
            action.index = nil
            action.selected_index = selected_indexes[1]
            repaired = true
          elseif action.name ~= nil or action.index ~= nil then
            action.selected = nil
            action.selected_index = nil
            repaired = true
          elseif action.selected_index ~= nil then
            action.selected_index = nil
            repaired = true
          end
        end
      end
    end
  end
  local repair_user_words = " "
    .. user_text_lower:gsub("[^%w]+", " ")
    .. " "
  local direct_new_track_request =
    Code.typed_action_user_requests_track_creation(user_text)
    and not Code.typed_action_user_requests_selected_target(user_text)
    and user_text_lower:find("ensure", 1, true) == nil
    and user_text_lower:find("if missing", 1, true) == nil
    and user_text_lower:find("if it is missing", 1, true) == nil
    and user_text_lower:find("if they are missing", 1, true) == nil
  local direct_new_track_request_has_names =
    user_text_lower:find(" named ", 1, true) ~= nil
    or user_text_lower:find(" called ", 1, true) ~= nil
    or user_text_lower:find('"', 1, true) ~= nil
    or user_text_lower:find("'", 1, true) ~= nil
    or user_text_lower:match("track%s+%d+") ~= nil
  local direct_new_track_request_wants_names =
    user_text_lower:find("name them", 1, true) ~= nil
    or user_text_lower:find("name the tracks", 1, true) ~= nil
    or user_text_lower:find("label them", 1, true) ~= nil
    or user_text_lower:find("label the tracks", 1, true) ~= nil
  if direct_new_track_request then
    local create_ordinal = 0
    local reply_lang = (I18N and I18N.prompt_language_name and I18N.prompt_language_name())
      or (CFG and CFG.prompt_language_name_for_idx
        and CFG.prompt_language_name_for_idx(prefs.reply_language_idx or 1))
      or (CFG and CFG.REPLY_LANGUAGE_CODES
        and CFG.REPLY_LANGUAGE_CODES[prefs.reply_language_idx or 1])
      or "English"
    for _, action in ipairs(plan.actions) do
      if type(action) == "table"
         and (action.op == "track.create" or action.op == "track.ensure") then
        create_ordinal = create_ordinal + 1
        if action.op == "track.ensure" then
          action.op = "track.create"
          repaired = true
        end
        if not direct_new_track_request_has_names then
          local generic_n = type(action.name) == "string"
            and action.name:match("^Track%s+(%d+)$") or nil
          if direct_new_track_request_wants_names then
            if generic_n or action.name == nil then
              action.name = Code.typed_actions_localized_track_label(
                reply_lang, generic_n or create_ordinal)
              repaired = true
            end
          elseif generic_n then
            action.name = nil
            repaired = true
          elseif reply_lang ~= "English" and type(action.name) == "string"
              and action.name:match("^Track%s+%d+$") then
            action.name = Code.typed_actions_localized_track_label(
              reply_lang, action.name:match("%d+"))
            repaired = true
          end
        end
      end
    end
  end
  local repair_mentions_stock_fx_name = false
  local repair_literal_track_names = {}
  for fx_name in pairs(_TYPED_ACTION_STOCK_FX) do
    local fx_lower = tostring(fx_name):lower()
    if user_text_lower:find(fx_lower, 1, true) then
      repair_mentions_stock_fx_name = true
    end
    if repair_user_words:find(" track named " .. fx_lower .. " ", 1, true)
       or repair_user_words:find(" track called " .. fx_lower .. " ", 1, true) then
      repair_literal_track_names[fx_lower] = true
    end
  end
  local repair_has_stock_fx_action_word =
    repair_user_words:find(" add ", 1, true) ~= nil
    or repair_user_words:find(" insert ", 1, true) ~= nil
    or repair_user_words:find(" load ", 1, true) ~= nil
    or repair_user_words:find(" put ", 1, true) ~= nil
    or repair_user_words:find(" apply ", 1, true) ~= nil
    or repair_user_words:find(" use ", 1, true) ~= nil
    or repair_user_words:find(" using ", 1, true) ~= nil
    or repair_user_words:find(" with ", 1, true) ~= nil
  local repair_requests_stock_fx = repair_mentions_stock_fx_name
    and repair_has_stock_fx_action_word
  repair_requests_stock_fx = repair_requests_stock_fx
    or user_text_lower:find("stock fx", 1, true) ~= nil
    or user_text_lower:find("stock effect", 1, true) ~= nil
    or user_text_lower:find("stock plugin", 1, true) ~= nil
  local function repair_normalized_name(s)
    return tostring(s or ""):lower()
      :gsub("^%s+", "")
      :gsub("%s+$", "")
      :gsub("%s+", " ")
  end
  local function repair_user_mentions_name(name)
    local n = repair_normalized_name(name):gsub("[^%w]+", " ")
    n = n:gsub("%s+", " ")
    return n ~= "" and repair_user_words:find(" " .. n .. " ", 1, true) ~= nil
  end
  local function repair_name_key(s)
    return tostring(s or ""):lower():gsub("[^%w]+", "")
  end
  local function repair_requested_named_track_map(text)
    text = tostring(text or "")
    local found = {}
    local function add_fragment(fragment)
      fragment = tostring(fragment or "")
      fragment = fragment:gsub("%f[%a][Aa]nd%f[%A]", ",")
      fragment = fragment:gsub("%f[%a][Tt]hen%f[%A]", ",")
      for part in fragment:gmatch("[^,]+") do
        local name = tostring(part or "")
          :gsub("^%s+", "")
          :gsub("%s+$", "")
          :gsub("^then%s+", "")
          :gsub("^and%s+", "")
          :gsub("^create%s+", "")
          :gsub("^make%s+", "")
          :gsub("^set%s+up%s+", "")
          :gsub("^build%s+", "")
          :gsub("^exactly%s+[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^tracks?%s+named%s+", "")
          :gsub("^named%s+", "")
          :gsub("^the%s+", "")
          :gsub("^a%s+", "")
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        local key = repair_name_key(name)
        if key ~= "" then found[key] = name end
      end
    end
    local explicit_fragment =
      text:match("[Tt]racks?%s+named%s+([^%.\n]+)")
      or text:match("[Tt]racks?%s+called%s+([^%.\n]+)")
    if explicit_fragment then add_fragment(explicit_fragment) end
    local colon_fragment = text:match(":%s*([^%.\n]+)")
    if colon_fragment then add_fragment(colon_fragment) end
    return next(found) and found or nil
  end
  local function repair_requested_folder_parent_name(text)
    text = tostring(text or "")
    local name =
      text:match("[Cc]reate%s+a%s+([%w%s%-%_']-)%s+folder%s+with")
      or text:match("[Cc]reate%s+an%s+([%w%s%-%_']-)%s+folder%s+with")
      or text:match("[Mm]ake%s+a%s+([%w%s%-%_']-)%s+folder%s+with")
      or text:match("[Ss]et%s+up%s+a%s+([%w%s%-%_']-)%s+folder%s+with")
      or text:match("[Bb]uild%s+a%s+([%w%s%-%_']-)%s+folder%s+with")
    name = tostring(name or "")
      :gsub("^new%s+", "")
      :gsub("^%s+", "")
      :gsub("%s+$", "")
    if name == "" or name:lower() == "folder" or #name > 64 then return nil end
    return name
  end
  local function repair_requested_created_track_name_set(text)
    text = tostring(text or "")
    local found = {}
    local function add_name(name)
      name = tostring(name or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("^a%s+", "")
        :gsub("^an%s+", "")
        :gsub("^new%s+", "")
      name = name:gsub("%s+with%s+.*$", "")
        :gsub("%s+and%s+send%s+.*$", "")
        :gsub("%s+$", "")
      if name ~= "" and #name <= 64 then
        found[repair_normalized_name(name)] = name
      end
    end
    for name in text:gmatch("[Cc]reate%s+one%s+([%w%s%-%_']-)%s+with%s+") do
      add_name(name)
    end
    for name in text:gmatch("[Cc]reate%s+one%s+([%w%s%-%_']-)[,%.\n]") do
      add_name(name)
    end
    for name in text:gmatch("[Cc]reate%s+a%s+([%w%s%-%_']-)%s+with%s+") do
      add_name(name)
    end
    for name in text:gmatch("[Cc]reate%s+an%s+([%w%s%-%_']-)%s+with%s+") do
      add_name(name)
    end
    return next(found) and found or nil
  end
  local function repair_selected_existing_track_name_set(text)
    text = tostring(text or "")
    local found = {}
    local function add_fragment(fragment)
      fragment = tostring(fragment or "")
      fragment = fragment:gsub("%f[%a][Aa]nd%f[%A]", ",")
      for part in fragment:gmatch("[^,]+") do
        local name = tostring(part or "")
          :gsub("^%s+", "")
          :gsub("%s+$", "")
          :gsub("^only%s+", "")
          :gsub("^the%s+", "")
          :gsub("^selected%s+tracks?%s+", "")
          :gsub("^are%s+", "")
          :gsub("^is%s+", "")
          :gsub("%s+only$", "")
          :gsub("%s+$", "")
        if name ~= "" and #name <= 64 then
          found[repair_normalized_name(name)] = name
        end
      end
    end
    for fragment in text:gmatch("[Ss]elected%s+tracks%s+are%s+([^%.\n]+)") do
      add_fragment(fragment)
    end
    for fragment in text:gmatch("[Ss]elected%s+track%s+is%s+([^%.\n]+)") do
      add_fragment(fragment)
    end
    return next(found) and found or nil
  end
  local function repair_user_mentions_existing_name(name)
    local n = repair_normalized_name(name):gsub("[^%w]+", " ")
      :gsub("%s+", " ")
    if n == "" then return false end
    return repair_user_words:find(" already a track named " .. n .. " ", 1, true) ~= nil
      or repair_user_words:find(" already track named " .. n .. " ", 1, true) ~= nil
      or repair_user_words:find(" existing track named " .. n .. " ", 1, true) ~= nil
      or repair_user_words:find(" existing " .. n .. " ", 1, true) ~= nil
      or repair_user_words:find(" selected track is " .. n .. " ", 1, true) ~= nil
      or repair_user_words:find(" selected tracks are " .. n .. " ", 1, true) ~= nil
  end
  local function repair_slug_id(name)
    local id = repair_normalized_name(name):gsub("[^%w]+", "_")
      :gsub("^_+", ""):gsub("_+$", "")
    if id == "" then id = "track" end
    if id:match("^%d") then id = "track_" .. id end
    return id
  end
  for _, action in ipairs(plan.actions) do
    if type(action) == "table"
       and (action.op == "track.ensure" or action.op == "track.create")
       and action.index ~= nil
       and _typed_action_is_nonempty_string(action.name)
       and repair_user_mentions_existing_name(action.name) then
      action.op = "track.resolve"
      action.position = nil
      action.select = nil
      repaired = true
    end
  end
  local function repair_requested_exact_track_order(text)
    text = tostring(text or "")
    local function parse_order_fragment(fragment)
      fragment = tostring(fragment or "")
      fragment = fragment:gsub("^%s*.-:%s*", "")
      fragment = fragment:gsub("%f[%a][Tt]hen%f[%A]", ",")
      fragment = fragment:gsub("%f[%a][Aa]nd%f[%A]", ",")
      local out = {}
      for part in fragment:gmatch("[^,]+") do
        local name = tostring(part or "")
          :gsub("^%s+", "")
          :gsub("%s+$", "")
          :gsub("^then%s+", "")
          :gsub("^and%s+", "")
          :gsub("^create%s+", "")
          :gsub("^make%s+", "")
          :gsub("^set%s+up%s+", "")
          :gsub("^build%s+", "")
          :gsub("^exactly%s+[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^tracks?%s+named%s+", "")
          :gsub("^named%s+", "")
          :gsub("^the%s+", "")
          :gsub("^a%s+", "")
        name = repair_normalized_name(name)
        if name ~= "" then out[#out + 1] = name end
      end
      return #out >= 2 and out or nil
    end
    local explicit_fragment =
      text:match("[Tt]rack%s+order%s+must%s+be%s+([^%.\n]+)")
      or text:match("[Oo]rder%s+must%s+be%s+([^%.\n]+)")
    if explicit_fragment then return parse_order_fragment(explicit_fragment) end
    local lt = text:lower()
    local marker = lt:find(" in that exact order", 1, true)
      or lt:find(" in exact order", 1, true)
      or lt:find(" in that order", 1, true)
    if not marker then return nil end
    local before = text:sub(1, marker - 1)
    local cut = 0
    for i = 1, #before do
      local ch = before:sub(i, i)
      if ch == "." or ch == "\n" then cut = i end
    end
    if cut > 0 then before = before:sub(cut + 1) end
    before = before:gsub("^.*[Cc]reate%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Cc]reate%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Mm]ake%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Ss]et%s+up%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*%f[%a]with%s+", "")
    return parse_order_fragment(before)
  end
  local function repair_user_mentions_db_value(db)
    local want = tonumber(db)
    if not want then return false end
    for raw in user_text:gmatch("([%+%-]?%d+%.?%d*)%s*[dD][bB]") do
      local got = tonumber(raw)
      if got and math.abs(got - want) <= 0.25 then return true end
    end
    return false
  end
  local function repair_user_mentions_db_magnitude(db)
    local want = math.abs(tonumber(db) or 0)
    if want == 0 then return false end
    for raw in user_text:gmatch("([%+%-]?%d+%.?%d*)%s*[dD][bB]") do
      local got = tonumber(raw)
      if got and math.abs(math.abs(got) - want) <= 0.25 then return true end
    end
    return false
  end
  local function repair_user_mentions_gain_direction(db)
    local want = tonumber(db)
    if not want or not repair_user_mentions_db_magnitude(want) then
      return false
    end
    if want < 0 then
      return user_text_lower:find("pull", 1, true) ~= nil
        or user_text_lower:find("down", 1, true) ~= nil
        or user_text_lower:find("reduce", 1, true) ~= nil
        or user_text_lower:find("lower", 1, true) ~= nil
        or user_text_lower:find("dip", 1, true) ~= nil
        or user_text_lower:find("attenuate", 1, true) ~= nil
        or user_text_lower:find("cut", 1, true) ~= nil
    elseif want > 0 then
      return user_text_lower:find("boost", 1, true) ~= nil
        or user_text_lower:find("raise", 1, true) ~= nil
        or user_text_lower:find("lift", 1, true) ~= nil
        or user_text_lower:find("push", 1, true) ~= nil
        or user_text_lower:find("up", 1, true) ~= nil
    end
    return false
  end
  local function repair_user_mentions_param(param, value, params)
    param = tostring(param or "")
    if param == "band" then
      return (params.frequency_hz ~= nil
          and repair_user_mentions_param("frequency_hz", params.frequency_hz, params))
        or (params.gain_db ~= nil
          and repair_user_mentions_param("gain_db", params.gain_db, params))
    elseif param == "frequency_hz" then
      return user_text_lower:find("frequency", 1, true) ~= nil
        or user_text_lower:find("freq", 1, true) ~= nil
        or user_text_lower:find(" hz", 1, true) ~= nil
        or user_text_lower:find("khz", 1, true) ~= nil
    elseif param == "gain_db" then
      return user_text_lower:find("gain", 1, true) ~= nil
        or user_text_lower:find("boost", 1, true) ~= nil
        or user_text_lower:find("cut", 1, true) ~= nil
        or repair_user_mentions_gain_direction(value)
        or (user_text_lower:find("band", 1, true) ~= nil
          and repair_user_mentions_db_value(value))
    elseif param == "threshold_db" then
      return user_text_lower:find("threshold", 1, true) ~= nil
    elseif param == "ratio" then
      return user_text_lower:find("ratio", 1, true) ~= nil
    elseif param == "attack_ms" then
      return user_text_lower:find("attack", 1, true) ~= nil
    elseif param == "release_ms" then
      return user_text_lower:find("release", 1, true) ~= nil
    elseif param == "wet_db" then
      return user_text_lower:find("wet", 1, true) ~= nil
    elseif param == "dry_db" then
      return user_text_lower:find("dry", 1, true) ~= nil
    elseif param == "rms_ms" then
      return user_text_lower:find("rms", 1, true) ~= nil
    elseif param == "free_time_ms" then
      return user_text_lower:find("free time", 1, true) ~= nil
        or user_text_lower:find("free-time", 1, true) ~= nil
        or user_text_lower:find("length (time)", 1, true) ~= nil
    elseif param == "musical_length" then
      return user_text_lower:find("musical", 1, true) ~= nil
        or user_text_lower:find("tempo", 1, true) ~= nil
        or user_text_lower:find("quarter", 1, true) ~= nil
        or user_text_lower:find("half note", 1, true) ~= nil
        or user_text_lower:find("whole note", 1, true) ~= nil
    elseif param == "feedback_pct" or param == "feedback_db" then
      return user_text_lower:find("feedback", 1, true) ~= nil
    elseif param == "room_size" then
      return user_text_lower:find("room size", 1, true) ~= nil
        or user_text_lower:find("room", 1, true) ~= nil
    elseif param == "dampening" then
      return user_text_lower:find("dampening", 1, true) ~= nil
        or user_text_lower:find("damping", 1, true) ~= nil
    elseif param == "hysteresis_db" then
      return user_text_lower:find("hysteresis", 1, true) ~= nil
    elseif param == "hold_ms" then
      return user_text_lower:find("hold", 1, true) ~= nil
    elseif param == "ceiling_db" then
      return user_text_lower:find("ceiling", 1, true) ~= nil
    end
    return false
  end
  local repair_exact_track_order, repair_exact_track_names
  do
    local order = repair_requested_exact_track_order(user_text)
    if order then
      repair_exact_track_order = order
      repair_exact_track_names = {}
      for _, name in ipairs(order) do repair_exact_track_names[name] = true end
    end
  end

  local repair_requested_track_names = repair_requested_named_track_map(user_text)
  if repair_requested_track_names then
    for _, action in ipairs(plan.actions) do
      if type(action) == "table"
         and (action.op == "track.create" or action.op == "track.ensure")
         and _typed_action_is_nonempty_string(action.id)
         and (not _typed_action_is_nonempty_string(action.name)
           or tostring(action.name):lower():gsub("%s+", "") == "null") then
        local requested_name =
          repair_requested_track_names[repair_name_key(action.id)]
        if requested_name then
          action.name = requested_name
          repaired = true
        end
      end
    end
  end
  do
    local selected_existing_names = repair_selected_existing_track_name_set(user_text)
    if selected_existing_names then
      for _, action in ipairs(plan.actions) do
        if type(action) == "table"
           and (action.op == "track.create" or action.op == "track.ensure")
           and _typed_action_is_nonempty_string(action.name)
           and selected_existing_names[repair_normalized_name(action.name)] then
          action.op = "track.resolve"
          action.position = nil
          action.select = nil
          action.selected = nil
          action.selected_index = nil
          repaired = true
        end
      end
    end
  end

  do
    local folder_parent_name = repair_requested_folder_parent_name(user_text)
    if folder_parent_name then
      local parent_ids = {}
      for _, action in ipairs(plan.actions) do
        if type(action) == "table" and action.op == "track.folder"
           and _typed_action_is_nonempty_string(action.parent) then
          parent_ids[action.parent] = true
        end
      end
      for _, action in ipairs(plan.actions) do
        if type(action) == "table"
           and parent_ids[action.id]
           and (action.op == "track.create" or action.op == "track.ensure")
           and not _typed_action_is_nonempty_string(action.name) then
          action.name = folder_parent_name
          repaired = true
        end
      end
    end
  end

  do
    local known_fx_ids, known_fx_type_by_id = {}, {}
    for _, action in ipairs(plan.actions) do
      if type(action) == "table"
         and action.op == "fx.add_stock"
         and _typed_action_is_nonempty_string(action.id) then
        known_fx_ids[action.id] = true
        known_fx_type_by_id[action.id] = tostring(action.fx or "")
      end
    end
    local function user_requested_eq_shelf_or_filter()
      return user_text_lower:find("shelf", 1, true) ~= nil
        or user_text_lower:find("low pass", 1, true) ~= nil
        or user_text_lower:find("high pass", 1, true) ~= nil
        or user_text_lower:find("low%-pass") ~= nil
        or user_text_lower:find("high%-pass") ~= nil
        or user_text_lower:find("filter", 1, true) ~= nil
        or user_text_lower:find("%f[%w]hp%f[%W]") ~= nil
        or user_text_lower:find("%f[%w]lp%f[%W]") ~= nil
    end
    local out, dropped, stripped = {}, 0, 0
    for _, action in ipairs(plan.actions) do
      local drop = false
      if type(action) == "table"
         and action.op == "fx.set_param"
         and known_fx_ids[action.fx]
         and type(action.params) == "table" then
        if known_fx_type_by_id[action.fx] == "ReaEQ"
            and tonumber(action.params.band) == 1
            and action.params.frequency_hz ~= nil
            and action.params.gain_db ~= nil
            and repair_user_mentions_gain_direction(action.params.gain_db)
            and not user_requested_eq_shelf_or_filter() then
          action.params.band = 2
          repaired = true
        end
        local has_param, has_requested_param = false, false
        for param, value in pairs(action.params) do
          if value ~= nil then
            has_param = true
            if repair_user_mentions_param(param, value, action.params) then
              has_requested_param = true
            else
              action.params[param] = nil
              stripped = stripped + 1
            end
          end
        end
        drop = has_param and not has_requested_param
      end
      if drop then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 and #out > 0 then
      plan.actions = out
      repaired = true
    elseif stripped > 0 then
      repaired = true
    end
  end

  if not Code.typed_action_user_requests_folder(user_text) then
    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      if type(action) == "table" and action.op == "track.folder" then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 then
      plan.actions = out
      repaired = true
    end
  end

  local function repair_reference_state(actions)
    local refs, non_resolve = {}, false
    local function add_ref(ref)
      if _typed_action_is_nonempty_string(ref) then refs[ref] = true end
    end
    for _, action in ipairs(actions) do
      if type(action) ~= "table" then return nil, nil end
      if action.op == "track.set" then
        add_ref(action.track)
        non_resolve = true
      elseif action.op == "track.folder" then
        add_ref(action.parent)
        non_resolve = true
        if type(action.children) == "table" then
          for _, child in ipairs(action.children) do
            add_ref(child)
          end
        end
      elseif action.op == "fx.add_stock" then
        add_ref(action.track)
        non_resolve = true
      elseif action.op == "send.create" then
        add_ref(action["from"])
        add_ref(action.to)
        non_resolve = true
      elseif action.op and action.op ~= "track.resolve" then
        non_resolve = true
      end
    end
    return refs, non_resolve
  end

  do
    local track_ids, track_name_to_id = {}, {}
    for _, action in ipairs(plan.actions) do
      if type(action) == "table"
         and (action.op == "track.create" or action.op == "track.ensure"
           or action.op == "track.resolve")
         and _typed_action_is_nonempty_string(action.id) then
        track_ids[action.id] = true
        if _typed_action_is_nonempty_string(action.name) then
          local key = repair_normalized_name(action.name)
          if key ~= "" and not track_name_to_id[key] then
            track_name_to_id[key] = action.id
          end
        end
      end
    end

    local inserted_resolves, inserted_resolve_names = {}, {}
    local function unique_track_id(base)
      local id = repair_slug_id(base)
      local candidate, n = id, 2
      while track_ids[candidate] do
        candidate = id .. "_" .. tostring(n)
        n = n + 1
      end
      track_ids[candidate] = true
      return candidate
    end
    local function repair_ref(action, key)
      local ref = action[key]
      if not _typed_action_is_nonempty_string(ref) or track_ids[ref] then
        return false
      end
      local name_key = repair_normalized_name(ref)
      local existing_id = track_name_to_id[name_key]
      if existing_id then
        action[key] = existing_id
        return true
      end
      if name_key ~= "" and ref:find("%s") and repair_user_mentions_name(ref) then
        local id = inserted_resolves[name_key]
        if not id then
          id = unique_track_id(ref)
          inserted_resolves[name_key] = id
          inserted_resolve_names[name_key] = ref
          track_name_to_id[name_key] = id
        end
        action[key] = id
        return true
      end
      return false
    end

    for _, action in ipairs(plan.actions) do
      if type(action) == "table" and action.op == "send.create" then
        if repair_ref(action, "from") then repaired = true end
        if repair_ref(action, "to") then repaired = true end
      end
    end
    if next(inserted_resolves) then
      local insert_at = 1
      while insert_at <= #plan.actions do
        local op = type(plan.actions[insert_at]) == "table"
          and plan.actions[insert_at].op or nil
        if op ~= "track.create" and op ~= "track.ensure"
           and op ~= "track.resolve" then
          break
        end
        insert_at = insert_at + 1
      end
      local prefix = {}
      for name_key, id in pairs(inserted_resolves) do
        prefix[#prefix + 1] = {
          op = "track.resolve",
          id = id,
          name = inserted_resolve_names[name_key],
        }
      end
      table.sort(prefix, function(a, b) return tostring(a.id) < tostring(b.id) end)
      for i = #prefix, 1, -1 do
        table.insert(plan.actions, insert_at, prefix[i])
      end
      repaired = true
    end
  end

  local referenced_tracks, has_non_resolve =
    repair_reference_state(plan.actions)
  if not referenced_tracks then return plan, false end
  if has_non_resolve then
    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      local unnamed_unreferenced_track =
        (action.op == "track.create" or action.op == "track.ensure")
        and _typed_action_is_nonempty_string(action.id)
        and not referenced_tracks[action.id]
        and not _typed_action_is_nonempty_string(action.name)
      if unnamed_unreferenced_track then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 and #out > 0 then
      plan.actions = out
      repaired = true
      referenced_tracks, has_non_resolve =
        repair_reference_state(plan.actions)
      if not referenced_tracks then return plan, false end
    end
  end
  if has_non_resolve then
    local existing_target_only =
      not Code.typed_action_user_requests_track_creation(user_text)
      and (user_text_lower:find("existing track", 1, true) ~= nil
        or user_text_lower:find("existing tracks", 1, true) ~= nil
        or user_text_lower:find("resolve the existing", 1, true) ~= nil
        or user_text_lower:find("do not create", 1, true) ~= nil
        or user_text_lower:find("don't create", 1, true) ~= nil)
    if existing_target_only then
      local out, dropped = {}, 0
      for _, action in ipairs(plan.actions) do
        local name = tostring(action.name or "")
        local id_key = tostring(action.id or ""):lower():gsub("[^%w]+", "")
        local name_key = name:lower():gsub("[^%w]+", "")
        local junk_ensure = (action.op == "track.create" or action.op == "track.ensure")
          and _typed_action_is_nonempty_string(action.id)
          and not referenced_tracks[action.id]
          and (not _typed_action_is_nonempty_string(action.name)
            or name:find("%w") == nil
            or name:lower():gsub("%s+", "") == ":null"
            or name:lower():gsub("%s+", "") == "null"
            or id_key:find("send", 1, true) ~= nil
            or name_key:find("send", 1, true) ~= nil)
        if junk_ensure then
          dropped = dropped + 1
        else
          out[#out + 1] = action
        end
      end
      if dropped > 0 and #out > 0 then
        plan.actions = out
        repaired = true
        referenced_tracks, has_non_resolve =
          repair_reference_state(plan.actions)
        if not referenced_tracks then return plan, false end
      end
    end
  end
  if has_non_resolve then
    if repair_exact_track_order
       and Code.typed_action_user_requests_track_creation(user_text)
       and not Code.typed_action_user_requests_folder(user_text) then
      local ensure_slots, ensure_by_name = {}, {}
      local bad_order_repair = false
      for i, action in ipairs(plan.actions) do
        if type(action) ~= "table" then
          bad_order_repair = true
          break
        elseif action.op == "track.create" or action.op == "track.ensure" then
          if not _typed_action_is_nonempty_string(action.id)
             or not _typed_action_is_nonempty_string(action.name) then
            bad_order_repair = true
            break
          end
          local name_key = repair_normalized_name(action.name)
          if ensure_by_name[name_key] then
            bad_order_repair = true
            break
          end
          ensure_by_name[name_key] = action
          ensure_slots[#ensure_slots + 1] = i
        elseif action.op == "track.folder" then
          bad_order_repair = true
          break
        end
      end
      if not bad_order_repair
         and #ensure_slots == #repair_exact_track_order then
        local ordered = {}
        for _, name in ipairs(repair_exact_track_order) do
          local action = ensure_by_name[name]
          if not action then
            bad_order_repair = true
            break
          end
          ordered[#ordered + 1] = action
        end
        if not bad_order_repair then
          local changed = false
          for i, slot in ipairs(ensure_slots) do
            if plan.actions[slot] ~= ordered[i] then changed = true end
            plan.actions[slot] = ordered[i]
          end
          if changed then repaired = true end
        end
      end
    end

    if repair_exact_track_names then
      local out, dropped = {}, 0
      for _, action in ipairs(plan.actions) do
        local extra_track = (action.op == "track.create" or action.op == "track.ensure")
          and _typed_action_is_nonempty_string(action.id)
          and not referenced_tracks[action.id]
          and not repair_exact_track_names[repair_normalized_name(action.name)]
        if extra_track then
          dropped = dropped + 1
        else
          out[#out + 1] = action
        end
      end
      if dropped > 0 then
        plan.actions = out
        repaired = true
      end
    end

    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      if action.op == "track.resolve"
         and _typed_action_is_nonempty_string(action.id)
         and not referenced_tracks[action.id] then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 then
      plan.actions = out
      repaired = true
    end
  end

  if has_non_resolve then
    local requested_created_names = repair_requested_created_track_name_set(user_text)
    if requested_created_names and Code.typed_action_user_requests_selected_target(user_text) then
      local kept_name, out, dropped = {}, {}, 0
      for _, action in ipairs(plan.actions) do
        local drop = false
        if (action.op == "track.create" or action.op == "track.ensure")
           and _typed_action_is_nonempty_string(action.id)
           and _typed_action_is_nonempty_string(action.name) then
          local name_key = repair_normalized_name(action.name)
          if requested_created_names[name_key] then
            if referenced_tracks[action.id] and not kept_name[name_key] then
              kept_name[name_key] = action.id
              if action.op ~= "track.create" then
                action.op = "track.create"
                repaired = true
              end
            elseif not referenced_tracks[action.id] or kept_name[name_key] then
              drop = true
            end
          end
        end
        if drop then
          dropped = dropped + 1
        else
          out[#out + 1] = action
        end
      end
      if dropped > 0 and #out > 0 then
        plan.actions = out
        repaired = true
        referenced_tracks, has_non_resolve = repair_reference_state(plan.actions)
        if not referenced_tracks then return plan, false end
      end
    end

    local referenced_ensure_name = {}
    local stock_fx_action_ids = {}
    for _, action in ipairs(plan.actions) do
      if (action.op == "track.create" or action.op == "track.ensure")
         and _typed_action_is_nonempty_string(action.id)
         and _typed_action_is_nonempty_string(action.name)
         and referenced_tracks[action.id] then
        referenced_ensure_name[action.name] = true
      elseif action.op == "fx.add_stock"
         and _typed_action_is_nonempty_string(action.id)
         and _TYPED_ACTION_STOCK_FX[action.fx] then
        stock_fx_action_ids[action.id] = true
      end
    end
    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      local helper_fx_id = (action.op == "track.create" or action.op == "track.ensure")
        and _typed_action_is_nonempty_string(action.id)
        and stock_fx_action_ids[action.id]
      local helper_name_stock_fx = (action.op == "track.create" or action.op == "track.ensure")
        and repair_requests_stock_fx
        and _typed_action_is_nonempty_string(action.name)
        and not repair_literal_track_names[tostring(action.name):lower()]
        and _TYPED_ACTION_STOCK_FX[tostring(action.name)] == true
      local helper_id = (action.op == "track.create" or action.op == "track.ensure")
        and _typed_action_is_nonempty_string(action.id)
        and (action.id:match("_[Ee][Qq]$")
          or action.id:match("_[Cc][Oo][Mm][Pp]$")
          or action.id:match("_[Rr][Ee][Vv][Ee][Rr][Bb]$")
          or action.id:match("_[Dd][Ee][Ll][Aa][Yy]$")
          or action.id:match("_[Gg][Aa][Tt][Ee]$")
          or action.id:match("_[Ll][Ii][Mm][Ii][Tt]$")
          or action.id:match("_[Rr][Ee][Aa][Ee][Qq]$")
          or action.id:match("_[Rr][Ee][Aa][Cc][Oo][Mm][Pp]$")
          or action.id:match("_[Rr][Ee][Aa][Vv][Ee][Rr][Bb][Aa][Tt][Ee]$")
          or action.id:match("_[Rr][Ee][Aa][Dd][Ee][Ll][Aa][Yy]$")
          or action.id:match("_[Rr][Ee][Aa][Gg][Aa][Tt][Ee]$")
          or action.id:match("_[Rr][Ee][Aa][Ll][Ii][Mm][Ii][Tt]$")
          or (repair_requests_stock_fx and action.id:match("_[Ff][Xx]$"))
          or (helper_name_stock_fx and action.id:match("_[Ff][Xx]$")))
      local helper_name_ok = _typed_action_is_nonempty_string(action.name)
        and tostring(action.name):find("%w") ~= nil
      local helper_id_unmentioned = helper_id
        and repair_requests_stock_fx
        and not repair_user_mentions_name(action.name)
      if (helper_id or helper_name_stock_fx or helper_fx_id)
         and not referenced_tracks[action.id]
         and (helper_name_stock_fx
          or helper_fx_id
          or helper_id_unmentioned
          or not helper_name_ok
          or referenced_ensure_name[action.name]) then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 then
      plan.actions = out
      repaired = true
    end
  end

  if has_non_resolve and Code.typed_action_user_requests_track_creation(user_text) then
    local ensured_name_by_id = {}
    for _, action in ipairs(plan.actions) do
      if (action.op == "track.create" or action.op == "track.ensure")
         and _typed_action_is_nonempty_string(action.id) then
        ensured_name_by_id[action.id] = repair_normalized_name(action.name)
      end
    end
    local out, dropped = {}, 0
    for _, action in ipairs(plan.actions) do
      local ensured_name = action.op == "track.resolve"
        and _typed_action_is_nonempty_string(action.id)
        and ensured_name_by_id[action.id]
      local resolve_name = repair_normalized_name(action.name)
      local redundant_resolve = ensured_name
        and action.selected ~= true
        and action.selected_index == nil
        and action.index == nil
        and (resolve_name == "" or resolve_name == ensured_name)
      if redundant_resolve then
        dropped = dropped + 1
      else
        out[#out + 1] = action
      end
    end
    if dropped > 0 then
      plan.actions = out
      repaired = true
    end
  end

  local u = user_text:lower()
  local preserve_mixed_existing_resolves =
    Code.typed_action_user_requests_track_creation(user_text)
    and (Code.typed_action_user_mentions_existing_or_source_track(user_text)
      or Code.typed_action_user_requests_selected_target(user_text))
  if Code.typed_action_user_requests_track_creation(user_text) then
    for _, action in ipairs(plan.actions) do
      if action.op == "track.resolve"
         and _typed_action_is_nonempty_string(action.name)
         and not preserve_mixed_existing_resolves
         and action.selected ~= true
         and action.selected_index == nil
         and action.index == nil then
        action.op = direct_new_track_request and "track.create" or "track.ensure"
        action.position = action.position or "end"
        action.selected = nil
        action.selected_index = nil
        action.index = nil
        repaired = true
      end
    end
  end

  local u_words = tostring(user_text or ""):lower()
    :gsub("[^%w]+", " ")
    :gsub("%s+", " ")
  local fx_order
  if u_words:find("reaeq first and reacomp second", 1, true)
     or u_words:find("reaeq followed by reacomp", 1, true)
     or (u_words:find("reaeq first", 1, true)
       and u_words:find("reacomp second", 1, true)) then
    fx_order = { ReaEQ = 1, ReaComp = 2 }
  elseif u_words:find("reacomp first and reaeq second", 1, true)
      or u_words:find("reacomp followed by reaeq", 1, true)
      or (u_words:find("reacomp first", 1, true)
        and u_words:find("reaeq second", 1, true)) then
    fx_order = { ReaComp = 1, ReaEQ = 2 }
  end
  if fx_order then
    local track_order, seen_track, fx_actions = {}, {}, {}
    local prefix, suffix = {}, {}
    for i, action in ipairs(plan.actions) do
      if action.op == "track.create" or action.op == "track.ensure"
         or action.op == "track.resolve" then
        if _typed_action_is_nonempty_string(action.id)
           and not seen_track[action.id] then
          seen_track[action.id] = #track_order + 1
          track_order[#track_order + 1] = action.id
        end
        prefix[#prefix + 1] = action
      elseif action.op == "track.set" or action.op == "track.folder" then
        prefix[#prefix + 1] = action
      elseif action.op == "fx.add_stock" then
        fx_actions[#fx_actions + 1] = { action = action, index = i }
      else
        suffix[#suffix + 1] = action
      end
    end
    if #fx_actions > 1 then
      table.sort(fx_actions, function(a, b)
        local aa, bb = a.action, b.action
        local at = seen_track[aa.track] or math.huge
        local bt = seen_track[bb.track] or math.huge
        if at ~= bt then return at < bt end
        local af = fx_order[aa.fx] or 1000
        local bf = fx_order[bb.fx] or 1000
        if af ~= bf then return af < bf end
        return a.index < b.index
      end)
      local out = {}
      for _, action in ipairs(prefix) do out[#out + 1] = action end
      for _, item in ipairs(fx_actions) do out[#out + 1] = item.action end
      for _, action in ipairs(suffix) do out[#out + 1] = action end
      plan.actions = out
      repaired = true
    end
  end

  local selected_indexes, selected_index_required =
    Code._typed_action_selected_indexes_from_user_text(user_text)
  local positional_selector_forbidden =
    Code._typed_action_forbids_positional_track_selector(user_text)
  local function selected_send_index_order()
    if not selected_index_required then return nil, nil end
    local words = " " .. Code._typed_action_user_request_text(user_text):lower()
      :gsub("[^%w]+", " ")
      :gsub("%s+", " ") .. " "
    local ordinals = {
      { "first", 1 },
      { "second", 2 },
      { "third", 3 },
      { "fourth", 4 },
      { "fifth", 5 },
      { "sixth", 6 },
    }
    local function has_order(from_word, from_idx, to_word, to_idx)
      return words:find(" from the " .. from_word
          .. " selected track to the " .. to_word .. " selected track ",
          1, true) ~= nil
        or words:find(" from " .. from_word
          .. " selected track to " .. to_word .. " selected track ",
          1, true) ~= nil
        or words:find(" " .. from_word
          .. " selected track to the " .. to_word .. " selected track ",
          1, true) ~= nil
        or words:find(" " .. from_word
          .. " selected to " .. to_word .. " selected ", 1, true) ~= nil
        or words:find(" from selected index " .. tostring(from_idx)
          .. " to selected index " .. tostring(to_idx) .. " ", 1, true) ~= nil
    end
    for _, from in ipairs(ordinals) do
      for _, to in ipairs(ordinals) do
        if from[2] ~= to[2] and has_order(from[1], from[2], to[1], to[2]) then
          return from[2], to[2]
        end
      end
    end
    return nil, nil
  end
  local track_property_text =
    Code._typed_action_track_property_intent_text(user_text)
  local requests_track_properties =
    (track_property_text:find("volume", 1, true) ~= nil
      or track_property_text:find("fader", 1, true) ~= nil
      or track_property_text:find("pan", 1, true) ~= nil
      or track_property_text:find("panned", 1, true) ~= nil
      or track_property_text:find("mute", 1, true) ~= nil
      or track_property_text:find("muted", 1, true) ~= nil
      or track_property_text:find("unmute", 1, true) ~= nil
      or track_property_text:find("solo", 1, true) ~= nil
      or track_property_text:find("soloed", 1, true) ~= nil
      or track_property_text:find("unsolo", 1, true) ~= nil
      or track_property_text:find("master send", 1, true) ~= nil
      or track_property_text:find("main send", 1, true) ~= nil
      or track_property_text:find("master/parent", 1, true) ~= nil
      or track_property_text:find("master parent", 1, true) ~= nil
      or track_property_text:find("parent send", 1, true) ~= nil
      or track_property_text:find("master output", 1, true) ~= nil
      or Code._typed_action_user_requests_track_level_change(user_text))
    and (track_property_text:find("track", 1, true) ~= nil
      or track_property_text:find("bus", 1, true) ~= nil
      or track_property_text:find("aux", 1, true) ~= nil)
  local requests_track_rename =
    (track_property_text:find("rename", 1, true) ~= nil
      or track_property_text:find("renamed", 1, true) ~= nil
      or track_property_text:find("call ", 1, true) ~= nil
      or track_property_text:find("called", 1, true) ~= nil)
    and (track_property_text:find("track", 1, true) ~= nil
      or track_property_text:find("bus", 1, true) ~= nil
      or track_property_text:find("aux", 1, true) ~= nil)

  if requests_track_properties
     and not Code.typed_action_user_requests_track_creation(user_text)
     and selected_index_required
     and #selected_indexes == 1 then
    local placeholder_only, placeholder_count = true, 0
    for _, action in ipairs(plan.actions) do
      if type(action) ~= "table" or action.op ~= "track.ensure" then
        placeholder_only = false
        break
      end
      local name = tostring(action.name or "")
      if _typed_action_is_nonempty_string(action.name)
         and name:find("%w") ~= nil then
        placeholder_only = false
        break
      end
      placeholder_count = placeholder_count + 1
    end
    if placeholder_only and placeholder_count > 0 then
      plan.actions = {
        {
          op = "track.resolve",
          id = "target",
          selected_index = selected_indexes[1],
        },
      }
      repaired = true
    end
  end

  do
    local send_text = Code._typed_action_send_intent_text(user_text)
    local requests_selected_send =
      selected_index_required
      and not Code.typed_action_user_requests_track_creation(user_text)
      and (send_text:find("send", 1, true) ~= nil
        or send_text:find("route", 1, true) ~= nil
        or send_text:find("routing", 1, true) ~= nil)
    if requests_selected_send then
      local from_index, to_index = selected_send_index_order()
      if from_index and to_index then
        local send_action, send_count, repairable = nil, 0, true
        for _, action in ipairs(plan.actions) do
          if type(action) ~= "table" then
            repairable = false
            break
          elseif action.op == "send.create" then
            send_count = send_count + 1
            send_action = send_action or action
          elseif action.op ~= "track.resolve" then
            repairable = false
            break
          end
        end
        if repairable and send_count == 1 and send_action then
          plan.actions = {
            {
              op = "track.resolve",
              id = "selected_send_from",
              selected_index = from_index,
            },
            {
              op = "track.resolve",
              id = "selected_send_to",
              selected_index = to_index,
            },
            {
              op = "send.create",
              id = send_action.id,
              ["from"] = "selected_send_from",
              to = "selected_send_to",
              volume_db = send_action.volume_db,
              pan = send_action.pan,
              mode = send_action.mode,
              muted = send_action.muted,
            },
          }
          return plan, true
        end
      end
    end
  end

  if not requests_track_properties and not requests_track_rename then
    return plan, repaired
  end

  if requests_track_rename then
    local exact_id, exact_names, exact_seen, exact_repairable =
      nil, {}, {}, true
    for _, action in ipairs(plan.actions) do
      if type(action) ~= "table"
         or action.op ~= "track.resolve"
         or not _typed_action_is_nonempty_string(action.id)
         or not _typed_action_is_nonempty_string(action.name)
         or action.selected == true
         or action.selected_index ~= nil
         or action.index ~= nil then
        exact_repairable = false
        break
      end
      exact_id = exact_id or action.id
      if action.id ~= exact_id then
        exact_repairable = false
        break
      end
      if not exact_seen[action.name] then
        exact_seen[action.name] = true
        exact_names[#exact_names + 1] = action.name
      end
    end
    if exact_repairable and #exact_names == 2 then
      local first_pos = track_property_text:find(exact_names[1]:lower(), 1, true)
      local second_pos = track_property_text:find(exact_names[2]:lower(), 1, true)
      if first_pos and second_pos and first_pos < second_pos then
        plan.actions = {
          {
            op = "track.resolve",
            id = exact_id,
            name = exact_names[1],
          },
          {
            op = "track.set",
            track = exact_id,
            name = exact_names[2],
          },
        }
        return plan, true
      end
    end

    local rename_target, rename_selector_key, resolved_name = nil, nil, nil
    local rename_repairable = true
    for _, action in ipairs(plan.actions) do
      if type(action) ~= "table"
         or action.op ~= "track.resolve"
         or not _typed_action_is_nonempty_string(action.id) then
        rename_repairable = false
        break
      end
      local has_positional_selector =
        type(action.index) == "number"
        or type(action.selected_index) == "number"
        or action.selected == true
      local has_name_selector = _typed_action_is_nonempty_string(action.name)
      if has_positional_selector then
        if positional_selector_forbidden then
          rename_repairable = false
          break
        end
        if has_name_selector then
          rename_repairable = false
          break
        end
        local selector_key
        if type(action.selected_index) == "number" then
          selector_key = "selected_index:" .. tostring(action.selected_index)
        elseif type(action.index) == "number" then
          selector_key = "index:" .. tostring(action.index)
        else
          selector_key = "selected:true"
        end
        if rename_selector_key and rename_selector_key ~= selector_key then
          rename_repairable = false
          break
        end
        rename_selector_key = selector_key
        rename_target = rename_target or action
      elseif has_name_selector then
        if resolved_name and resolved_name ~= action.name then
          rename_repairable = false
          break
        end
        resolved_name = action.name
      else
        rename_repairable = false
        break
      end
    end
    if rename_repairable and rename_target and resolved_name then
      if selected_index_required then
        local target_selected_index = tonumber(rename_target.selected_index)
        if not target_selected_index then return plan, repaired end
        if #selected_indexes == 1
           and target_selected_index ~= selected_indexes[1] then
          return plan, repaired
        end
      end

      local resolved = {
        op = "track.resolve",
        id = rename_target.id,
      }
      if type(rename_target.index) == "number" then
        resolved.index = rename_target.index
      end
      if type(rename_target.selected_index) == "number" then
        resolved.selected_index = rename_target.selected_index
      end
      if rename_target.selected == true then
        resolved.selected = true
      end
      plan.actions = {
        resolved,
        {
          op = "track.set",
          track = rename_target.id,
          name = resolved_name,
        },
      }
      return plan, true
    end
  end

  local allow_noisy_resolve_only_track_set =
    requests_track_properties
    and not requests_track_rename
    and not Code.typed_action_user_requests_track_creation(user_text)
  local function resolve_matches_requested_selected_index(action)
    if not selected_index_required then return false end
    local n = tonumber(action and action.selected_index)
    if not n then return false end
    if #selected_indexes == 0 then return true end
    for _, want in ipairs(selected_indexes) do
      if n == want then return true end
    end
    return false
  end

  local target_id, target_action, rename_target_action, rename_name, has_mutation =
    nil, nil, nil, nil, false
  local target_action_priority = 0
  local selector_priority_by_key = {}
  local function resolve_selector_key(action)
    local name = _typed_action_trim(action and action.name)
      :lower():gsub("%s+", " ")
    if name ~= "" then return "name:" .. name end
    if type(action and action.selected_index) == "number" then
      return "selected_index:" .. tostring(action.selected_index)
    end
    if type(action and action.index) == "number" then
      return "index:" .. tostring(action.index)
    end
    if action and action.selected == true then return "selected:true" end
    return nil
  end
  for _, action in ipairs(plan.actions) do
    if type(action) ~= "table" then return plan, false end
    if action.op == "track.resolve" then
      if not _typed_action_is_nonempty_string(action.id) then
        return plan, false
      end
      target_id = target_id or action.id
      if action.id ~= target_id and not allow_noisy_resolve_only_track_set then
        return plan, false
      end
      local has_positional_selector =
        type(action.index) == "number"
        or type(action.selected_index) == "number"
        or action.selected == true
      if has_positional_selector and not rename_target_action then
        rename_target_action = action
      end
      local selector_priority = 0
      if resolve_matches_requested_selected_index(action) then
        selector_priority = 3
      elseif not selected_index_required
          and _typed_action_is_nonempty_string(action.name)
          and repair_user_mentions_name(action.name) then
        selector_priority = 2
      elseif _typed_action_is_nonempty_string(action.name)
          or type(action.index) == "number"
          or type(action.selected_index) == "number"
          or action.selected == true then
        selector_priority = 1
      end
      local selector_key = resolve_selector_key(action)
      if selector_key
         and selector_priority > (selector_priority_by_key[selector_key] or 0) then
        selector_priority_by_key[selector_key] = selector_priority
      end
      if selector_priority > target_action_priority then
        target_action = action
        target_action_priority = selector_priority
      end
      if requests_track_rename
         and _typed_action_is_nonempty_string(action.name)
         and not has_positional_selector then
        if rename_name and action.name ~= rename_name then
          return plan, repaired
        end
        rename_name = action.name
      end
    else
      has_mutation = true
    end
  end
  if has_mutation or not target_action then return plan, repaired end
  if allow_noisy_resolve_only_track_set then
    local preferred_selector_count = 0
    for _, priority in pairs(selector_priority_by_key) do
      if priority == target_action_priority then
        preferred_selector_count = preferred_selector_count + 1
      end
    end
    if preferred_selector_count ~= 1 then return plan, repaired end
    target_id = target_action.id
  end

  if requests_track_rename and rename_target_action and rename_name then
    if positional_selector_forbidden then return plan, repaired end
    if selected_index_required then
      local target_selected_index = tonumber(rename_target_action.selected_index)
      if not target_selected_index then return plan, repaired end
      if #selected_indexes == 1
         and target_selected_index ~= selected_indexes[1] then
        return plan, repaired
      end
    end

    local resolved = {
      op = "track.resolve",
      id = target_id,
    }
    if type(rename_target_action.index) == "number" then
      resolved.index = rename_target_action.index
    end
    if type(rename_target_action.selected_index) == "number" then
      resolved.selected_index = rename_target_action.selected_index
    end
    if rename_target_action.selected == true then
      resolved.selected = true
    end
    plan.actions = {
      resolved,
      {
        op = "track.set",
        track = target_id,
        name = rename_name,
      },
    }
    return plan, true
  end

  if not requests_track_properties then return plan, repaired end

  if positional_selector_forbidden then
    local uses_positional_selector =
      type(target_action.index) == "number"
      or type(target_action.selected_index) == "number"
      or target_action.selected == true
    if uses_positional_selector then return plan, repaired end
  end

  if selected_index_required then
    local target_selected_index = tonumber(target_action.selected_index)
    if not target_selected_index then return plan, repaired end
    if #selected_indexes == 1
       and target_selected_index ~= selected_indexes[1] then
      return plan, repaired
    end
  end

  local volume_db, volume_db_count = nil, 0
  for raw in user_text:gmatch("([%+%-]?%d+%.?%d*)%s*[dD][bB]") do
    volume_db_count = volume_db_count + 1
    volume_db = tonumber(raw)
  end
  if volume_db_count ~= 1 then volume_db = nil end

  local pan_pct, pan_conflict = Code._typed_action_static_pan_value(user_text)
  if pan_conflict then return plan, repaired end

  local mute = nil
  if track_property_text:find("unmute", 1, true) ~= nil then
    mute = false
  elseif track_property_text:find("mute", 1, true) ~= nil
      or track_property_text:find("muted", 1, true) ~= nil then
    mute = true
  end

  local solo = nil
  if track_property_text:find("unsolo", 1, true) ~= nil then
    solo = false
  elseif track_property_text:find("solo", 1, true) ~= nil
      or track_property_text:find("soloed", 1, true) ~= nil then
    solo = true
  end

  local master_send = nil
  if track_property_text:find("turn off master send", 1, true) ~= nil
      or track_property_text:find("turn off main send", 1, true) ~= nil
      or track_property_text:find("turn off master/parent", 1, true) ~= nil
      or track_property_text:find("disable master send", 1, true) ~= nil
      or track_property_text:find("disable main send", 1, true) ~= nil
      or track_property_text:find("disable master/parent", 1, true) ~= nil
      or track_property_text:find("master_send false", 1, true) ~= nil
      or track_property_text:find("master send false", 1, true) ~= nil
      or track_property_text:find("no master send", 1, true) ~= nil then
    master_send = false
  elseif track_property_text:find("turn on master send", 1, true) ~= nil
      or track_property_text:find("turn on main send", 1, true) ~= nil
      or track_property_text:find("turn on master/parent", 1, true) ~= nil
      or track_property_text:find("enable master send", 1, true) ~= nil
      or track_property_text:find("enable main send", 1, true) ~= nil
      or track_property_text:find("enable master/parent", 1, true) ~= nil
      or track_property_text:find("master_send true", 1, true) ~= nil
      or track_property_text:find("master send true", 1, true) ~= nil then
    master_send = true
  end

  if volume_db == nil and pan_pct == nil and mute == nil
      and solo == nil and master_send == nil then
    return plan, repaired
  end

  local resolved = {
    op = "track.resolve",
    id = target_id,
  }
  if _typed_action_is_nonempty_string(target_action.name) then
    resolved.name = target_action.name
  end
  if type(target_action.index) == "number" then
    resolved.index = target_action.index
  end
  if type(target_action.selected_index) == "number" then
    resolved.selected_index = target_action.selected_index
  end
  if target_action.selected == true then
    resolved.selected = true
  end
  plan.actions = {
    resolved,
    {
      op = "track.set",
      track = target_id,
      volume_db = volume_db,
      pan_pct = pan_pct,
      mute = mute,
      solo = solo,
      master_send = master_send,
    },
  }
  return plan, true
end

function Code._typed_action_folder_depth_plan(plan)
  local errors = {}
  local track_order, track_order_index = {}, {}
  local folder_specs = {}

  for i, action in ipairs((plan and plan.actions) or {}) do
    if type(action) == "table" then
      if (action.op == "track.create" or action.op == "track.ensure")
         and _typed_action_is_nonempty_string(action.id)
         and not track_order_index[action.id] then
        track_order[#track_order + 1] = action.id
        track_order_index[action.id] = #track_order
      elseif action.op == "track.folder" then
        folder_specs[#folder_specs + 1] = {
          parent = action.parent,
          children = action.children,
          path = "$.actions[" .. tostring(i) .. "]",
        }
      end
    end
  end

  local children_by_parent, parent_by_child = {}, {}
  local parent_order = {}

  for _, spec in ipairs(folder_specs) do
    local parent = spec.parent
    local children = spec.children
    if _typed_action_is_nonempty_string(parent)
       and track_order_index[parent]
       and _typed_action_is_array(children) then
      if children_by_parent[parent] then
        _typed_action_add_error(errors, "duplicate_folder_parent",
          spec.path .. ".parent",
          "A typed-action folder parent can be declared only once")
      else
        children_by_parent[parent] = {}
        parent_order[#parent_order + 1] = parent
      end

      local seen_children = {}
      for cidx, child in ipairs(children) do
        local cpath = spec.path .. ".children[" .. tostring(cidx) .. "]"
        if _typed_action_is_nonempty_string(child)
           and track_order_index[child] then
          if child == parent then
            _typed_action_add_error(errors, "folder_self_child", cpath,
              "A folder parent cannot also be its child")
          elseif seen_children[child] then
            _typed_action_add_error(errors, "duplicate_folder_child", cpath,
              "Duplicate folder child: " .. tostring(child))
          elseif parent_by_child[child] and parent_by_child[child] ~= parent then
            _typed_action_add_error(errors, "overlapping_folder", cpath,
              "A typed-action folder child can have only one direct parent")
          else
            seen_children[child] = true
            parent_by_child[child] = parent
            if children_by_parent[parent] then
              children_by_parent[parent][#children_by_parent[parent] + 1] = child
            end
          end
        end
      end
    end
  end

  local visiting, visited = {}, {}
  local function visit(id, path)
    if visiting[id] then
      _typed_action_add_error(errors, "folder_cycle", path or "$.actions",
        "Nested typed-action folders cannot form a cycle")
      return
    end
    if visited[id] then return end
    visiting[id] = true
    for _, child in ipairs(children_by_parent[id] or {}) do
      visit(child, path)
    end
    visiting[id] = nil
    visited[id] = true
  end
  for _, parent in ipairs(parent_order) do visit(parent) end

  local function append_subtree(id, out)
    out[#out + 1] = id
    for _, child in ipairs(children_by_parent[id] or {}) do
      append_subtree(child, out)
    end
  end

  if #errors == 0 then
    for _, parent in ipairs(parent_order) do
      local expected = {}
      append_subtree(parent, expected)
      local pidx = track_order_index[parent]
      for offset, id in ipairs(expected) do
        if track_order[pidx + offset - 1] ~= id then
          _typed_action_add_error(errors, "folder_order_mismatch",
            "$.actions",
            "track.folder requires each parent to be followed immediately by "
              .. "its full nested child subtree in track creation order")
          break
        end
      end
    end
  end

  if #errors > 0 then return nil, errors end

  local depths, touched, touched_set = {}, {}, {}
  local function mark(id)
    if not touched_set[id] then
      touched_set[id] = true
      touched[#touched + 1] = id
    end
  end
  local function mark_subtree(id)
    mark(id)
    for _, child in ipairs(children_by_parent[id] or {}) do
      mark_subtree(child)
    end
  end
  local function last_descendant(id)
    local children = children_by_parent[id]
    if children and #children > 0 then
      return last_descendant(children[#children])
    end
    return id
  end

  for _, parent in ipairs(parent_order) do
    depths[parent] = (depths[parent] or 0) + 1
    local last = last_descendant(parent)
    depths[last] = (depths[last] or 0) - 1
    mark_subtree(parent)
  end

  table.sort(touched, function(a, b)
    return (track_order_index[a] or 0) < (track_order_index[b] or 0)
  end)

  return { depths = depths, order = touched }, nil
end

local function _typed_action_db_to_amp(db)
  return 10 ^ ((tonumber(db) or 0) / 20)
end

local function _typed_action_clamp01(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function _typed_action_ms_to_norm(ms, full_scale_ms)
  return _typed_action_clamp01((tonumber(ms) or 0) / (tonumber(full_scale_ms) or 1000))
end

local function _typed_action_percent_to_norm(v)
  v = tonumber(v) or 0
  if v > 1 then v = v / 100 end
  return _typed_action_clamp01(v)
end

local function _typed_action_interp(points, x)
  x = tonumber(x)
  if not x or x < points[1][1] or x > points[#points][1] then return nil end
  for i = 1, #points do
    if x == points[i][1] then return points[i][2] end
  end
  for i = 1, #points - 1 do
    local ax, ay = points[i][1], points[i][2]
    local bx, by = points[i + 1][1], points[i + 1][2]
    if x >= ax and x <= bx then
      local t = (x - ax) / (bx - ax)
      return ay + (by - ay) * t
    end
  end
  return nil
end

local function _typed_action_param_setters(fx_name, params, path)
  local setters, errors = {}, {}
  local function add_error(code, p, msg)
    errors[#errors+1] = _typed_action_error(code, p or path, msg)
  end
  local function add(method, index, value)
    setters[#setters+1] = { method = method, index = index, value = value }
  end
  local function unsupported(param, why)
    add_error("unsupported_param", path .. ".params." .. tostring(param),
      why or ("Typed-action executor does not support " .. tostring(fx_name)
        .. "." .. tostring(param)))
  end

  if type(params) ~= "table" then
    add_error("invalid_type", path .. ".params", "params must be an object")
    return nil, errors
  end

  for param, value in pairs(params) do
    local norm_idx = type(param) == "string"
      and param:match("^normalized_(%d+)$") or nil
    if norm_idx then
      add("normalized", tonumber(norm_idx), value)

    elseif fx_name == "ReaEQ" then
      if param == "band" then
        -- Selector for the other ReaEQ params in this action.
      elseif param == "frequency_hz" then
        local band = tonumber(params.band or 1)
        if not band or band % 1 ~= 0 or band < 1 or band > 4 then
          add_error("out_of_range", path .. ".params.band",
            "ReaEQ typed actions support bands 1-4")
        else
          local norm = _typed_action_interp(_TYPED_ACTION_REAEQ_FREQ_POINTS, value)
          if not norm then
            add_error("out_of_range", path .. ".params.frequency_hz",
              "ReaEQ frequency_hz must be between 20 and 24000")
          else
            add("normalized", (band - 1) * 3, norm)
          end
        end
      elseif param == "gain_db" then
        local band = tonumber(params.band or 1)
        if not band or band % 1 ~= 0 or band < 1 or band > 4 then
          add_error("out_of_range", path .. ".params.band",
            "ReaEQ typed actions support bands 1-4")
        else
          local norm = _typed_action_interp(_TYPED_ACTION_REAEQ_GAIN_POINTS, value)
          if not norm then
            add_error("out_of_range", path .. ".params.gain_db",
              "ReaEQ gain_db must be between -12 and +12")
          else
            add("normalized", (band - 1) * 3 + 1, norm)
          end
        end
      else
        unsupported(param, param == "type"
          and "ReaEQ band type is UI-only and is not scriptable"
          or nil)
      end

    elseif fx_name == "ReaComp" then
      if param == "threshold_db" then
        add("raw", 0, _typed_action_db_to_amp(value))
      elseif param == "attack_ms" then
        add("normalized", 2, _typed_action_ms_to_norm(value, 500))
      elseif param == "release_ms" then
        add("normalized", 3, _typed_action_ms_to_norm(value, 5000))
      elseif param == "dry_db" then
        add("raw", 10, _typed_action_db_to_amp(value))
      elseif param == "wet_db" then
        add("raw", 11, _typed_action_db_to_amp(value))
      elseif param == "rms_ms" then
        add("raw", 13, (tonumber(value) or 0) / 1000)
      else
        unsupported(param)
      end

    elseif fx_name == "ReaDelay" then
      if param == "wet_db" then
        add("raw", 0, _typed_action_db_to_amp(value))
      elseif param == "dry_db" then
        add("raw", 1, _typed_action_db_to_amp(value))
      elseif param == "free_time_ms" then
        local ms = tonumber(value)
        if not ms or ms < 0 or ms > 1000 then
          add_error("out_of_range", path .. ".params.free_time_ms",
            "ReaDelay free_time_ms must be between 0 and 1000")
        else
          add("raw", 3, ms / 1000)
        end
      elseif param == "musical_length" then
        local whole_notes = tonumber(value)
        if not whole_notes or whole_notes < 0 or whole_notes > 256 then
          add_error("out_of_range", path .. ".params.musical_length",
            "ReaDelay musical_length must be between 0 and 256 whole notes")
        else
          add("raw", 4, whole_notes / 256)
        end
      elseif param == "feedback_pct" then
        add("raw", 5, _typed_action_clamp01((tonumber(value) or 0) / 100))
      elseif param == "feedback_db" then
        add("raw", 5, _typed_action_db_to_amp(value))
      else
        unsupported(param)
      end

    elseif fx_name == "ReaVerbate" then
      if param == "wet_db" then
        add("raw", 0, _typed_action_db_to_amp(value))
      elseif param == "dry_db" then
        add("raw", 1, _typed_action_db_to_amp(value))
      elseif param == "room_size" then
        add("normalized", 2, _typed_action_percent_to_norm(value))
      elseif param == "dampening" then
        add("normalized", 3, _typed_action_percent_to_norm(value))
      else
        unsupported(param)
      end

    elseif fx_name == "ReaGate" then
      if param == "threshold_db" then
        add("raw", 0, _typed_action_db_to_amp(value))
      elseif param == "attack_ms" then
        add("normalized", 1, _typed_action_ms_to_norm(value, 500))
      elseif param == "release_ms" then
        add("normalized", 2, _typed_action_ms_to_norm(value, 5000))
      elseif param == "hold_ms" then
        add("normalized", 4, _typed_action_ms_to_norm(value))
      elseif param == "hysteresis_db" then
        add("raw", 12, _typed_action_db_to_amp(value))
      else
        unsupported(param)
      end

    elseif fx_name == "ReaLimit" then
      if param == "threshold_db" then
        add("normalized", 0, _typed_action_clamp01(((tonumber(value) or 0) + 60) / 72))
      elseif param == "ceiling_db" then
        add("normalized", 1, _typed_action_clamp01(((tonumber(value) or 0) + 24) / 24))
      else
        unsupported(param)
      end

    else
      unsupported("*", "Typed-action executor has no parameter map for "
        .. tostring(fx_name))
    end
  end

  if #errors > 0 then return nil, errors end
  if #setters == 0 then
    add_error("unsupported_param", path .. ".params",
      "fx.set_param contains no executable parameter writes")
    return nil, errors
  end
  return setters, nil
end

local function _typed_action_blank_op_counts()
  local counts = {}
  for _, op in ipairs(_TYPED_ACTION_OP_KEYS) do counts[op] = 0 end
  return counts
end

local function _typed_action_count_ops(plan)
  local counts = _typed_action_blank_op_counts()
  local actions = type(plan) == "table" and plan.actions or nil
  if type(actions) ~= "table" then return counts end
  for _, action in ipairs(actions) do
    local op = type(action) == "table" and action.op or nil
    if _TYPED_ACTION_OP_ALLOWED[op] then
      counts[op] = counts[op] + 1
    end
  end
  return counts
end

local function _typed_action_strip_json_nulls(value)
  if value == JSON.NULL then return nil end
  if type(value) ~= "table" then return value end
  for k, v in pairs(value) do
    if v == JSON.NULL then
      value[k] = nil
    else
      value[k] = _typed_action_strip_json_nulls(v)
    end
  end
  return value
end

local function _typed_action_single_json_object(raw)
  local s = _typed_action_trim(raw)
  if s == "" then
    return false, "Typed action block is empty"
  end
  if s:sub(1, 1) ~= "{" then
    return false, "Typed action JSON must be a top-level object"
  end

  local depth, in_string, escaped = 0, false, false
  for i = 1, #s do
    local ch = s:sub(i, i)
    if in_string then
      if escaped then
        escaped = false
      elseif ch == "\\" then
        escaped = true
      elseif ch == "\"" then
        in_string = false
      end
    else
      if ch == "\"" then
        in_string = true
      elseif ch == "{" or ch == "[" then
        depth = depth + 1
      elseif ch == "}" or ch == "]" then
        depth = depth - 1
        if depth < 0 then
          return false, "Typed action JSON has an unmatched closing bracket"
        end
        if depth == 0 and i ~= #s then
          return false, "Typed action JSON has trailing content after the object"
        end
      end
    end
  end
  if in_string then
    return false, "Typed action JSON has an unterminated string"
  end
  if depth ~= 0 then
    return false, "Typed action JSON has unbalanced brackets"
  end
  return true, nil
end

-- Public typed-action parser/validator entry points. Extraction prefers the
-- canonical ```reaassist-actions fence, then accepts a few common malformed
-- wrappers from small models when the payload is still one clean JSON object.
function Code.extract_typed_actions(text)
  if type(text) ~= "string" or text == "" then return nil, nil end
  local blocks = {}
  for block in text:gmatch("```reaassist%-actions%s*\n(.-)\n%s*```") do
    blocks[#blocks+1] = block
  end
  if #blocks == 0 then
    for block in text:gmatch("```%s*\n(.-)\n%s*```") do
      local payload = block:match("^%s*reaassist%-actions%s*\n(.*)$")
      if payload then blocks[#blocks+1] = payload end
    end
  end
  if #blocks == 0 then
    for block in text:gmatch("<reaassist%-actions>%s*(.-)%s*</reaassist%-actions>") do
      blocks[#blocks+1] = block
    end
  end
  if #blocks == 0 then
    local marker_start, marker_end =
      text:find("reaassist%-actions%s*[\r\n]+")
    if marker_start then
      local rest = text:sub(marker_end + 1)
      local object_start = rest:find("{", 1, true)
      if object_start then
        local depth, in_string, escaped = 0, false, false
        for i = object_start, #rest do
          local ch = rest:sub(i, i)
          if in_string then
            if escaped then
              escaped = false
            elseif ch == "\\" then
              escaped = true
            elseif ch == "\"" then
              in_string = false
            end
          else
            if ch == "\"" then
              in_string = true
            elseif ch == "{" or ch == "[" then
              depth = depth + 1
            elseif ch == "}" or ch == "]" then
              depth = depth - 1
              if depth == 0 then
                blocks[#blocks+1] = rest:sub(object_start, i)
                break
              end
            end
          end
        end
      end
    end
  end
  if #blocks == 0 then return nil, nil end
  if #blocks > 1 then
    local first = tostring(blocks[1] or ""):match("^%s*(.-)%s*$") or ""
    local all_same = true
    for i = 2, #blocks do
      local b = tostring(blocks[i] or ""):match("^%s*(.-)%s*$") or ""
      if b ~= first then
        all_same = false
        break
      end
    end
    if all_same then
      blocks = { first }
    else
      return nil, {
        _typed_action_error("multiple_action_blocks", "$",
          "Use exactly one reaassist-actions block")
      }
    end
  end
  return blocks[1], nil
end

function Code.parse_typed_actions_block(raw)
  local ok_shape, shape_err = _typed_action_single_json_object(raw)
  if not ok_shape then
    return nil, {
      _typed_action_error("invalid_json_shape", "$", shape_err)
    }
  end

  local plan, err = JSON.decode(_typed_action_trim(raw))
  if not plan then
    return nil, {
      _typed_action_error("invalid_json", "$",
        "Typed action block is not valid JSON: " .. tostring(err))
    }
  end
  if _typed_action_is_object(plan)
     and _typed_action_is_object(plan["reaassist-actions"]) then
    local wrapper_keys = 0
    for _ in pairs(plan) do wrapper_keys = wrapper_keys + 1 end
    if wrapper_keys == 1 then plan = plan["reaassist-actions"] end
  end
  plan = _typed_action_strip_json_nulls(plan)
  Code.normalize_typed_actions_plan(plan)
  return plan, nil
end

function Code.validate_typed_actions_plan(plan)
  local errors = {}
  if not _typed_action_is_object(plan) then
    _typed_action_add_error(errors, "invalid_top_level", "$",
      "Typed action plan must be a JSON object")
    return false, errors
  end

  _typed_action_check_fields(errors, plan, "$", {
    version = true,
    actions = true,
  })

  if plan.version ~= 1 then
    _typed_action_add_error(errors, "invalid_version", "$.version",
      "Typed action plan version must be 1")
  end

  if not _typed_action_is_array(plan.actions) then
    _typed_action_add_error(errors, "invalid_actions", "$.actions",
      "Typed action plan actions must be a non-empty array")
    return false, errors
  end

  local action_ids, track_ids, track_id_kind = {}, {}, {}
  local fx_ids, send_ids, fx_type_by_id = {}, {}, {}
  local resolve_count, has_non_resolve_action = 0, false

  local function require_string(action, field, path)
    if not _typed_action_is_nonempty_string(action[field]) then
      _typed_action_add_error(errors, "invalid_type", path .. "." .. field,
        field .. " must be a non-empty string")
      return nil
    end
    return action[field]
  end

  local function require_number(action, field, path)
    if type(action[field]) ~= "number" then
      _typed_action_add_error(errors, "invalid_type", path .. "." .. field,
        field .. " must be a number")
      return nil
    end
    return action[field]
  end

  local function require_ref(refs, value, path, kind)
    if not _typed_action_is_nonempty_string(value) then
      _typed_action_add_error(errors, "invalid_type", path,
        kind .. " reference must be a non-empty string")
      return false
    end
    if not refs[value] then
      _typed_action_add_error(errors, "unknown_ref", path,
        "Unknown " .. kind .. " reference: " .. value)
      return false
    end
    return true
  end

  local function require_created_track_ref(value, path)
    if not require_ref(track_ids, value, path, "track") then return false end
    if track_id_kind[value] ~= "create" and track_id_kind[value] ~= "ensure" then
      _typed_action_add_error(errors, "unsupported_existing_folder_target", path,
        "track.folder currently supports only track ids created by track.create or track.ensure")
      return false
    end
    return true
  end

  local function validate_track_name(name, path)
    if not name then return end
    if not tostring(name):find("%w") then
      _typed_action_add_error(errors, "invalid_track_name", path,
        "track name must contain at least one letter or number")
    end
  end

  local function register_id(set, id, path, kind, id_kind)
    if not id then return end
    if set[id] then
      _typed_action_add_error(errors, "duplicate_id", path,
        "Duplicate " .. kind .. " id: " .. id)
      return
    end
    if action_ids[id] then
      _typed_action_add_error(errors, "duplicate_id", path,
        "Duplicate typed-action id: " .. id
          .. " was already used for " .. tostring(action_ids[id]))
      return
    end
    action_ids[id] = kind
    set[id] = true
    if kind == "track" then track_id_kind[id] = id_kind or "ensure" end
  end

  for i, action in ipairs(plan.actions) do
    local path = "$.actions[" .. tostring(i) .. "]"
    if not _typed_action_is_object(action) then
      _typed_action_add_error(errors, "invalid_action", path,
        "Each action must be a JSON object")
    else
      local op = require_string(action, "op", path)
      if op == "track.resolve" then
        resolve_count = resolve_count + 1
      elseif _TYPED_ACTION_OP_ALLOWED[op] then
        has_non_resolve_action = true
      end
      if op == "track.create" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          id = true,
          name = true,
          select = true,
          position = true,
        })
        local id = require_string(action, "id", path)
        if action.name ~= nil then
          require_string(action, "name", path)
          validate_track_name(action.name, path .. ".name")
        end
        if action.select ~= nil and type(action.select) ~= "boolean" then
          _typed_action_add_error(errors, "invalid_type", path .. ".select",
            "select must be a boolean")
        end
        if action.position ~= nil then
          if type(action.position) ~= "string" then
            _typed_action_add_error(errors, "invalid_type", path .. ".position",
              "position must be a string")
          elseif action.position ~= "end" then
            local dir, ref = action.position:match("^(after):(.-)$")
            if not dir then dir, ref = action.position:match("^(before):(.-)$") end
            if not dir or not track_ids[ref] then
              _typed_action_add_error(errors, "unknown_ref", path .. ".position",
                "position must be end, after:<existing-track-id>, or before:<existing-track-id>")
            end
          end
        end
        register_id(track_ids, id, path .. ".id", "track", "create")

      elseif op == "track.ensure" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          id = true,
          name = true,
          select = true,
          position = true,
        })
        local id = require_string(action, "id", path)
        local name = require_string(action, "name", path)
        validate_track_name(name, path .. ".name")
        if action.select ~= nil and type(action.select) ~= "boolean" then
          _typed_action_add_error(errors, "invalid_type", path .. ".select",
            "select must be a boolean")
        end
        if action.position ~= nil then
          if type(action.position) ~= "string" then
            _typed_action_add_error(errors, "invalid_type", path .. ".position",
              "position must be a string")
          elseif action.position ~= "end" then
            local dir, ref = action.position:match("^(after):(.-)$")
            if not dir then dir, ref = action.position:match("^(before):(.-)$") end
            if not dir or not track_ids[ref] then
              _typed_action_add_error(errors, "unknown_ref", path .. ".position",
                "position must be end, after:<existing-track-id>, or before:<existing-track-id>")
            end
          end
        end
        register_id(track_ids, id, path .. ".id", "track", "ensure")

      elseif op == "track.resolve" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          id = true,
          name = true,
          selected = true,
          selected_index = true,
          index = true,
        })
        local id = require_string(action, "id", path)
        local has_name = false
        local has_selected = false
        local has_selected_index = false
        local has_index = false
        if action.name ~= nil then
          has_name = true
          require_string(action, "name", path)
        end
        if action.selected ~= nil then
          has_selected = true
          if action.selected ~= true then
            _typed_action_add_error(errors, "invalid_type",
              path .. ".selected", "selected must be true when provided")
          end
        end
        if action.selected_index ~= nil then
          has_selected_index = true
          if type(action.selected_index) ~= "number"
             or action.selected_index % 1 ~= 0
             or action.selected_index < 1 then
            _typed_action_add_error(errors, "out_of_range",
              path .. ".selected_index",
              "selected_index must be a positive 1-based selected-track number")
          end
        end
        if action.index ~= nil then
          has_index = true
          if type(action.index) ~= "number"
             or action.index % 1 ~= 0
             or action.index < 1 then
            _typed_action_add_error(errors, "out_of_range", path .. ".index",
              "index must be a positive 1-based track number")
          end
        end
        if has_selected and (has_name or has_index or has_selected_index) then
          _typed_action_add_error(errors, "invalid_target_selector", path,
            "track.resolve selected:true cannot be combined with other selectors")
        elseif has_selected_index and (has_name or has_index) then
          _typed_action_add_error(errors, "invalid_target_selector", path,
            "track.resolve selected_index cannot be combined with name or index")
        elseif not has_selected and not has_selected_index
            and not (has_name or has_index) then
          _typed_action_add_error(errors, "invalid_target_selector", path,
            "track.resolve must include name, index, name+index, "
              .. "selected:true, or selected_index")
        end
        register_id(track_ids, id, path .. ".id", "track", "resolve")

      elseif op == "track.set" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          track = true,
          volume_db = true,
          pan_pct = true,
          name = true,
          mute = true,
          solo = true,
          master_send = true,
        })
        require_ref(track_ids, action.track, path .. ".track", "track")
        local has_property = false
        if action.name ~= nil then
          has_property = true
          require_string(action, "name", path)
        end
        if action.volume_db ~= nil then
          has_property = true
          local volume_db = require_number(action, "volume_db", path)
          if volume_db and (volume_db < -150 or volume_db > 24) then
            _typed_action_add_error(errors, "out_of_range", path .. ".volume_db",
              "volume_db must be between -150 and +24")
          end
        end
        if action.pan_pct ~= nil then
          has_property = true
          local pan_pct = require_number(action, "pan_pct", path)
          if pan_pct and (pan_pct < -100 or pan_pct > 100) then
            _typed_action_add_error(errors, "out_of_range", path .. ".pan_pct",
              "pan_pct must be between -100 and 100")
          end
        end
        if action.mute ~= nil then
          has_property = true
          if type(action.mute) ~= "boolean" then
            _typed_action_add_error(errors, "invalid_type", path .. ".mute",
              "mute must be a boolean")
          end
        end
        if action.solo ~= nil then
          has_property = true
          if type(action.solo) ~= "boolean" then
            _typed_action_add_error(errors, "invalid_type", path .. ".solo",
              "solo must be a boolean")
          end
        end
        if action.master_send ~= nil then
          has_property = true
          if type(action.master_send) ~= "boolean" then
            _typed_action_add_error(errors, "invalid_type",
              path .. ".master_send", "master_send must be a boolean")
          end
        end
        if not has_property then
          _typed_action_add_error(errors, "missing_track_property", path,
            "track.set must include name, volume_db, pan_pct, mute, solo, or master_send")
        end

      elseif op == "track.pan_lfo" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          track = true,
          start = true,
          bars = true,
          cycles_per_bar = true,
          depth_pct = true,
          resolution = true,
          clear_existing = true,
        })
        require_ref(track_ids, action.track, path .. ".track", "track")
        if action.start ~= nil then
          if type(action.start) ~= "string" then
            _typed_action_add_error(errors, "invalid_type", path .. ".start",
              "start must be cursor, project_start, or null")
          else
            local st = action.start:lower():gsub("%s+", "_"):gsub("%-", "_")
            if st ~= "cursor" and st ~= "project_start" then
              _typed_action_add_error(errors, "unsupported_start", path .. ".start",
                "start must be cursor or project_start")
            end
          end
        end
        local bars = require_number(action, "bars", path)
        if bars and (bars <= 0 or bars > 256) then
          _typed_action_add_error(errors, "out_of_range", path .. ".bars",
            "bars must be greater than 0 and no more than 256")
        end
        local cycles_per_bar = require_number(action, "cycles_per_bar", path)
        if cycles_per_bar and (cycles_per_bar <= 0 or cycles_per_bar > 32) then
          _typed_action_add_error(errors, "out_of_range",
            path .. ".cycles_per_bar",
            "cycles_per_bar must be greater than 0 and no more than 32")
        end
        if bars and cycles_per_bar and bars * cycles_per_bar > 2048 then
          _typed_action_add_error(errors, "out_of_range",
            path .. ".cycles_per_bar",
            "track.pan_lfo supports no more than 2048 total cycles")
        end
        if action.depth_pct ~= nil then
          local depth_pct = require_number(action, "depth_pct", path)
          if depth_pct and (depth_pct <= 0 or depth_pct > 100) then
            _typed_action_add_error(errors, "out_of_range",
              path .. ".depth_pct",
              "depth_pct must be greater than 0 and no more than 100")
          end
        end
        if action.resolution ~= nil then
          if type(action.resolution) ~= "string" then
            _typed_action_add_error(errors, "invalid_type", path .. ".resolution",
              "resolution must be eighth, 16th, 32nd, 64th, or null")
          else
            local res = action.resolution:lower():gsub("%s+", ""):gsub("%-", "")
            if res ~= "eighth" and res ~= "8th" and res ~= "16th"
                and res ~= "32nd" and res ~= "64th" then
              _typed_action_add_error(errors, "unsupported_resolution",
                path .. ".resolution",
                "resolution must be eighth, 16th, 32nd, or 64th")
            end
          end
        end
        if action.clear_existing ~= nil
           and type(action.clear_existing) ~= "boolean" then
          _typed_action_add_error(errors, "invalid_type",
            path .. ".clear_existing",
            "clear_existing must be a boolean")
        end

      elseif op == "track.folder" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          parent = true,
          children = true,
        })
        require_created_track_ref(action.parent, path .. ".parent")

        if not _typed_action_is_array(action.children) then
          _typed_action_add_error(errors, "invalid_type", path .. ".children",
            "children must be a non-empty array of track ids")
        else
          local seen_children = {}
          for cidx, child in ipairs(action.children) do
            local cpath = path .. ".children[" .. tostring(cidx) .. "]"
            require_created_track_ref(child, cpath)
            if child == action.parent then
              _typed_action_add_error(errors, "folder_self_child", cpath,
                "A folder parent cannot also be its child")
            end
            if _typed_action_is_nonempty_string(child) and seen_children[child] then
              _typed_action_add_error(errors, "duplicate_folder_child", cpath,
                "Duplicate folder child: " .. tostring(child))
            end
            if _typed_action_is_nonempty_string(child) then
              seen_children[child] = true
            end
          end
        end

      elseif op == "fx.add_stock" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          track = true,
          id = true,
          fx = true,
        })
        require_ref(track_ids, action.track, path .. ".track", "track")
        local id = require_string(action, "id", path)
        local fx = require_string(action, "fx", path)
        if fx and not _TYPED_ACTION_STOCK_FX[fx] then
          _typed_action_add_error(errors, "unsupported_stock_fx", path .. ".fx",
            "Unsupported or non-stock FX for typed actions: " .. fx)
        end
        register_id(fx_ids, id, path .. ".id", "fx")
        if id and fx and _TYPED_ACTION_STOCK_FX[fx] then
          fx_type_by_id[id] = fx
        end

      elseif op == "fx.set_param" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          fx = true,
          params = true,
        })
        local fx = require_string(action, "fx", path)
        require_ref(fx_ids, fx, path .. ".fx", "fx")
        if not _typed_action_is_object(action.params) or next(action.params) == nil then
          _typed_action_add_error(errors, "invalid_type", path .. ".params",
            "params must be a non-empty object")
        else
          local fx_name = fx and fx_type_by_id[fx]
          local allowed_params = fx_name and _TYPED_ACTION_PARAM_TYPES[fx_name] or nil
          for param, value in pairs(action.params) do
            local ppath = path .. ".params." .. tostring(param)
            if type(param) ~= "string" then
              _typed_action_add_error(errors, "unknown_param", ppath,
                "Parameter name must be a string")
            elseif param:match("^normalized_") then
              if type(value) ~= "number" then
                _typed_action_add_error(errors, "invalid_type", ppath,
                  "Normalized parameter values must be numeric")
              elseif value < 0 or value > 1 then
                _typed_action_add_error(errors, "out_of_range", ppath,
                  "Normalized parameter values must be between 0 and 1")
              end
            elseif not allowed_params or not allowed_params[param] then
              _typed_action_add_error(errors, "unknown_param", ppath,
                "Unknown parameter for " .. tostring(fx_name or "FX") .. ": " .. param)
            elseif type(value) ~= allowed_params[param] then
              _typed_action_add_error(errors, "invalid_type", ppath,
                param .. " must be a " .. allowed_params[param])
            end
          end
        end

      elseif op == "send.create" then
        _typed_action_check_fields(errors, action, path, {
          op = true,
          id = true,
          ["from"] = true,
          ["to"] = true,
          volume_db = true,
          pan = true,
          mode = true,
          muted = true,
        })
        local id = nil
        if action.id ~= nil then
          id = require_string(action, "id", path)
        end
        require_ref(track_ids, action["from"], path .. ".from", "track")
        require_ref(track_ids, action["to"], path .. ".to", "track")
        if action.volume_db ~= nil then require_number(action, "volume_db", path) end
        if action.pan ~= nil then
          local pan = require_number(action, "pan", path)
          if pan and (pan < -1 or pan > 1) then
            _typed_action_add_error(errors, "out_of_range", path .. ".pan",
              "pan must be between -1 and 1")
          end
        end
        if action.mode ~= nil
           and type(action.mode) ~= "string"
           and type(action.mode) ~= "number" then
          _typed_action_add_error(errors, "invalid_type", path .. ".mode",
            "mode must be a string or number")
        end
        if action.muted ~= nil and type(action.muted) ~= "boolean" then
          _typed_action_add_error(errors, "invalid_type", path .. ".muted",
            "muted must be a boolean")
        end
        register_id(send_ids, id, path .. ".id", "send")

      elseif op then
        _typed_action_add_error(errors, "unknown_op", path .. ".op",
          "Unsupported typed action op: " .. tostring(op))
      end
    end
  end

  if resolve_count > 0 and not has_non_resolve_action then
    _typed_action_add_error(errors, "missing_mutation_action", "$.actions",
      "track.resolve only binds target ids; add track.set, fx.add_stock, "
        .. "track.pan_lfo, send.create, or another supported mutation action")
  end

  if #errors == 0 then
    local _, folder_errors = Code._typed_action_folder_depth_plan(plan)
    for _, err in ipairs(folder_errors or {}) do errors[#errors + 1] = err end
  end

  return #errors == 0, errors
end

function Code.find_typed_actions_wrong_fence(text)
  if type(text) ~= "string" or text == "" then return nil end
  local raw_text = _typed_action_trim(text)
  local raw_plan = Code.parse_typed_actions_block(raw_text)
  if raw_plan then
    local raw_valid = Code.validate_typed_actions_plan(raw_plan)
    if raw_valid then
      return {
        label = "(unfenced)",
        raw = raw_text,
        op_counts = _typed_action_count_ops(raw_plan),
      }
    end
  end

  for label, block in text:gmatch("```([^\n]*)\n(.-)\n%s*```") do
    local lowered = string.lower(label or "")
    local trimmed = lowered:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "json" or trimmed == ""
       or (trimmed ~= "reaassist-actions"
           and trimmed:find("reaassist%-actions") ~= nil) then
      local plan = Code.parse_typed_actions_block(block)
      if plan then
        local valid = Code.validate_typed_actions_plan(plan)
        if valid then
          return {
            label = trimmed ~= "" and label or "(unlabeled)",
            raw = block,
            op_counts = _typed_action_count_ops(plan),
          }
        end
      end
    end
  end
  return nil
end

function Code.typed_actions_dev_gate_enabled()
  if type(reaper) ~= "table" or type(reaper.file_exists) ~= "function" then
    return false
  end
  if type(reaper.GetExePath) ~= "function" then
    return false
  end
  local exe_path = tostring(reaper.GetExePath() or ""):lower():gsub("/", "\\")
  exe_path = exe_path:gsub("\\+$", "")
  if exe_path ~= "c:\\reaper - test"
     and not exe_path:find("c:\\reaper - test\\", 1, true) then
    return false
  end
  if type(RA) ~= "table" or type(RA.script_path) ~= "string" then
    return false
  end
  local sep = RA.SEP or package.config:sub(1, 1)
  local cache = Code._typed_actions_dev_gate_cache
  if type(cache) ~= "table" then
    cache = {}
    Code._typed_actions_dev_gate_cache = cache
  end
  local cache_key = exe_path .. "\n" .. tostring(RA.script_path) .. "\n"
    .. tostring(sep)
  if cache[cache_key] ~= nil then return cache[cache_key] == true end
  local function file_exists_normalized(path)
    local exists_raw = reaper.file_exists(path)
    if exists_raw == true or exists_raw == 1 then return true end
    for _ = 1, 32 do
      local normalized, n = path:gsub("[^\\/]+[\\/]%.%.[\\/]", "")
      path = normalized
      if n == 0 then break end
    end
    exists_raw = reaper.file_exists(path)
    if exists_raw == true or exists_raw == 1 then return true end
    local f = io.open(path, "rb")
    if f then
      f:close()
      return true
    end
    return false
  end
  local candidates = {
    RA.script_path .. "Dev" .. sep .. "typed_actions_enabled",
    RA.script_path .. ".." .. sep .. "typed_actions_enabled",
    RA.script_path .. ".." .. sep .. ".." .. sep .. "typed_actions_enabled",
  }
  for _, path in ipairs(candidates) do
    if file_exists_normalized(path) then
      cache[cache_key] = true
      return true
    end
  end
  cache[cache_key] = false
  return false
end

function Code.typed_actions_public_force_off()
  return type(reaper) == "table"
    and type(reaper.GetExtState) == "function"
    and type(CFG) == "table"
    and reaper.GetExtState(CFG.EXT_NS, "typed_actions_force_off") == "1"
end

function Code.typed_actions_executor_enabled()
  if Code.typed_actions_dev_gate_enabled() then return true end
  if Code.typed_actions_public_force_off() then return false end
  return true
end

function Code.typed_actions_executor_disabled_message()
  if Code.typed_actions_public_force_off() then
    local fallback = "Structured track edits are temporarily disabled."
    return (RA and RA.t and RA.t("typed_actions.error.executor_disabled", nil,
      fallback)) or fallback
  end
  local fallback = "Structured track edits are unavailable in this install."
  return (RA and RA.t and RA.t("typed_actions.error.executor_unavailable",
    nil, fallback)) or fallback
end

-- OpenAI receives these operation shapes through its strict response schema.
-- Keep the examples for fenced-output providers, but do not resend that schema
-- in the OpenAI prompt body.
local _TYPED_ACTION_CONTRACT_OPERATION_SHAPES = [[
- Do not emit `<context_needed>` when this contract fits; include the complete track, FX, parameter, folder, and send plan in this one response.
- Supported ops only:
  - {"op":"track.create","id":"new_track","name":"New Track","position":"end","select":true}
  - {"op":"track.ensure","id":"lead","name":"Lead Vocal","position":"end","select":true}
  - {"op":"track.resolve","id":"lead","name":"Lead Vocal","selected":null,"selected_index":null,"index":null}
  - {"op":"track.set","track":"lead","name":null,"volume_db":-6,"pan_pct":null,"mute":false,"solo":null,"master_send":null}
  - {"op":"track.pan_lfo","track":"lead","start":"cursor","bars":8,"cycles_per_bar":1,"depth_pct":100,"resolution":"32nd","clear_existing":true}
  - {"op":"track.folder","parent":"drums","children":["kick","snare"]}
  - {"op":"fx.add_stock","track":"lead","id":"lead_eq","fx":"ReaEQ"}
  - {"op":"fx.set_param","fx":"lead_eq","params":{"band":2,"frequency_hz":300,"gain_db":-3}}
  - {"op":"fx.add_stock","track":"lead","id":"delay_fx","fx":"ReaDelay"}
  - {"op":"fx.set_param","fx":"delay_fx","params":{"free_time_ms":0,"musical_length":0.25,"feedback_db":-12,"wet_db":-12}}
  - {"op":"send.create","from":"lead","to":"bus","volume_db":-12,"pan":0,"mode":"post_fader","muted":false}
- Supported stock FX: ReaEQ, ReaComp, ReaDelay, ReaVerbate, ReaGate, ReaLimit.
]]

local _TYPED_ACTION_CONTRACT_COMMON_BODY = [[
- Use `track.resolve` for existing tracks only. It supports exactly one selector:
  exact unique `name`, `selected`:true for exactly one selected track, 1-based
  `selected_index` for the Nth selected track when multiple tracks are selected,
  1-based `index`, or `name`+`index` as a checked lookup. If the target is
  ambiguous or missing, do not use typed actions.
- A `name`+`index` lookup is one checked target identity. Both fields must
  match at execution time. A name mismatch fails the complete plan before any
  mutation; never substitute live selection or the track now at that index.
- If the user says "first selected track", "second selected track", or similar,
  use `selected_index`:N. Do not use `selected`:true for ordinal selected-track
  requests.
- `track.resolve` only binds a target id; it does not change the track. Follow it
  with `track.set`, `track.pan_lfo`, `fx.add_stock`, or `send.create` for the requested change.
- When the user says a named track is selected, existing, or already present,
  resolve that track with `track.resolve`; do not recreate it with `track.create`.
- Use `track.create` when the user asks to create, add, make, or insert new tracks. It always inserts new tracks. If the user names the new track, put that exact display name in `name`; use `"name":null` only for truly generic unnamed tracks.
- Treat named setup/build requests for stacks, routing plans, buses, returns, and folders as new track creation unless the user says existing/ensure/if missing.
- If a request mixes an existing selected source with a new return/bus, use `track.resolve` for the selected source and `track.create` for the new return/bus.
- Use `track.ensure` only when the user means ensure/reuse-if-present/if-missing, or when a named setup/routing track should be reused if it already exists.
- FX ids are created only by `fx.add_stock`. Never use `track.resolve` for ids
  like `lead_eq`, `lead_comp`, `verb_fx`, or send ids.
- Add only the stock FX the user named for each target track; do not infer extra EQ/compressor chain members.
- `track.set` supports `name`, `volume_db`, `pan_pct` (-100 left to 100 right), `mute`, `solo`, and `master_send`. At least one value must be non-null.
- Use `track.set` only when the user explicitly requests track rename/name, volume, fader, pan, mute, unmute, solo, unsolo, or master/parent send state.
- In `track.set`, use JSON null for every supported property the user did not request. Do not fill unused booleans with false.
- Use `track.pan_lfo` only for requested track-pan/autopan/sine/LFO envelope motion over bars. It writes the track Pan envelope, not send pan, JSFX, or audio-rate modulation.
- In `track.pan_lfo`, `start` is `cursor` or `project_start`; `bars` and `cycles_per_bar` must be explicit numbers; `depth_pct` defaults to 100 if null; `resolution` is eighth, 16th, 32nd, or 64th.
- `track.pan_lfo.clear_existing` defaults to true; pass false only when the user explicitly wants to layer onto existing pan automation.
- Do not set `master_send`:true or `master_send`:false unless the user explicitly requests master/parent send state.
- Use `track.folder` only when the user explicitly requests a folder. Children are immediate child tracks only. For nested folders, emit one `track.folder` action per folder parent and create tracks in depth-first order so every parent is followed immediately by its full child subtree.
- Emit actions in dependency order: all `track.create`, `track.ensure`, and `track.resolve` before `track.folder`, FX after tracks, params after FX, and sends after tracks.
- The examples above show JSON shape only. Do not copy placeholder ids/names like `lead` or `Lead Vocal` unless the user requested them.
- Every `id` must be unique across track, FX, and send actions.
]]

local _TYPED_ACTION_CONTRACT_SUPPORTED_PARAMS = [[
- Supported params:
  - ReaEQ: band, frequency_hz, gain_db
  - ReaComp: threshold_db, attack_ms, release_ms, wet_db, dry_db, rms_ms
  - ReaDelay: free_time_ms, musical_length, feedback_pct, feedback_db, wet_db, dry_db
  - ReaVerbate: wet_db, dry_db, room_size, dampening
  - ReaGate: threshold_db, hysteresis_db, attack_ms, hold_ms, release_ms
  - ReaLimit: threshold_db, ceiling_db
- ReaDelay `musical_length` uses displayed whole-note units: 0.25 is a quarter note, 0.5 is a half note, and 1 is a whole note. Do not convert it to a normalized value.
- ReaDelay `free_time_ms` uses milliseconds. Set it to 0 when the requested tempo-synced delay should have no additional free-time length.
]]

local _TYPED_ACTION_CONTRACT_REFERENCE_BODY = [[
- References must point to ids created by earlier `track.create`, `track.ensure`,
  `track.resolve`, `fx.add_stock`, or `send.create` actions. Do not embed Lua in JSON fields.
- For `track`, `from`, and `to`, reference the earlier action id, never the
  display name. If the source/destination is an existing named track, add a
  `track.resolve` action first and use that id.
- If the request needs MIDI, JSFX authoring, third-party plugins, items/takes, envelopes other than `track.pan_lfo`, markers, regions, colors, presets, unsupported FX, or unsupported params, ignore this contract and write normal Lua instead.
]]

local _TYPED_ACTION_PROMPT_CONTRACT = [[
TYPED ACTION CONTRACT (use only when the request is an exact fit):
- If this contract fits the user request, output exactly one fenced block whose label is `reaassist-actions`.
- Do not output Lua, ReaScript, JSFX, prose, apologies, raw JSON, `json`, `json reaassist-actions`, or any other code fence when using this contract.
- The block must contain one JSON object: {"version":1,"actions":[...]}.
]] .. _TYPED_ACTION_CONTRACT_OPERATION_SHAPES
  .. _TYPED_ACTION_CONTRACT_COMMON_BODY
  .. _TYPED_ACTION_CONTRACT_SUPPORTED_PARAMS
  .. _TYPED_ACTION_CONTRACT_REFERENCE_BODY

local _TYPED_ACTION_RESPONSE_FORMAT_FULL_PROMPT_CONTRACT = [[
TYPED ACTION CONTRACT (use only when the request is an exact fit):
- If this contract fits the user request, output the action plan as the raw JSON object required by the API response schema.
- Do not output Lua, ReaScript, JSFX, prose, apologies, markdown, code fences, or a `reaassist-actions` wrapper when using this contract.
- The JSON object must be {"version":1,"actions":[...]}.
]] .. _TYPED_ACTION_CONTRACT_OPERATION_SHAPES
  .. _TYPED_ACTION_CONTRACT_COMMON_BODY
  .. _TYPED_ACTION_CONTRACT_REFERENCE_BODY

local _TYPED_ACTION_RESPONSE_FORMAT_COMPACT_PROMPT_CONTRACT = [[
TYPED ACTION CONTRACT (use only when the request is an exact fit):
- If this contract fits the user request, output the action plan as the raw JSON object required by the API response schema.
- Do not output Lua, ReaScript, JSFX, prose, apologies, markdown, code fences, or a `reaassist-actions` wrapper when using this contract.
- The JSON object must be {"version":1,"actions":[...]}.
- Do not emit `<context_needed>` when this contract fits; include the complete track, FX, parameter, folder, and send plan in this one response.
]] .. _TYPED_ACTION_CONTRACT_COMMON_BODY
  .. _TYPED_ACTION_CONTRACT_REFERENCE_BODY

local _TYPED_ACTION_ROUTING_SEMANTIC_HELP = [[

MODEL-SCOPED ROUTING CHECKLIST:
- Complete graph requests must include every requested family:
  tracks/resolves, `fx.add_stock`, `fx.set_param`, and `send.create`.
- Plugin/FX names are never tracks. Use `fx.add_stock`; do not create helper
  tracks named like Kick EQ, Snare Comp, or Vocal Reverb unless requested.
- For bus routing, use `volume_db`:0 unless the user gives another bus level.
  Wet effect sends use only their requested negative dB values.
- Keep exact graphs exact: no inferred sends, return-to-bus edges, extra bus FX,
  duplicate same-track stock FX, or cross-group FX spreading.
- Put source-chain FX on source tracks, return FX on return tracks, and bus FX
  on bus tracks only when requested.
- Preserve requested track order, exact names, and exact track counts. Generic
  "N tracks" uses `name`:null unless the user asks to label them.
- Folder requests use depth-first track order and immediate-child folder lists.
- Routing order: tracks/resolves, track properties/pan LFO, folders,
  `fx.add_stock`, `fx.set_param`, then `send.create`.
- For each requested parameter, target the same-track `fx.add_stock.id`; never
  use the track id, plugin name, blank string, or example placeholder.
- Resolve a track once, then reuse that id for requested mutations. Do not
  create helper ids like `lead_set`, and never stop with only resolves.
- Re-emit the complete plan; do not omit sends, FX, or parameter actions.
]]

local _TYPED_ACTION_MINIMAL_PLAN_HELP = [[

MODEL-SCOPED MINIMAL ACTION CHECKLIST:
- Emit the shortest complete action list that satisfies the request.
- Do not repeat actions, ids, track/FX pairs, or send edges.
- Add each requested stock FX exactly once per named target track unless the
  user explicitly asks for multiple copies.
- If the user says exactly N new tracks, emit exactly N `track.create` actions;
  plugin names and FX ids are not tracks.
- For blank-project or create-track requests, use `track.create` for each requested new track. Do not use `track.resolve` for tracks that do not exist yet.
- For selected-track source requests that also create a named return/bus, resolve the selected source with `track.resolve` and create the return/bus with `track.create`.
- For requested track rename/name, volume, pan, mute, unmute, solo, unsolo, or master/parent send state, emit one `track.set` action for the already-created track id.
- In `track.set`, set only requested properties; unused properties must be null.
- For requested track-pan/autopan/sine/LFO envelope motion over bars, emit one `track.pan_lfo` action for the already-created or resolved track id.
- If the target is an existing track, emit one valid `track.resolve` first, then
  the requested mutation using that same id; resolve-only plans do nothing.
- For requested FX, create real `fx.add_stock` actions. Ids like `lead_eq`,
  `lead_comp`, or `verb_fx` belong there, not in `track.resolve`.
- If the user did not request track rename/name, volume, pan, mute, unmute, solo, unsolo, or master/parent send state, do not emit `track.set`.
- Emit exactly the requested folders, parameter settings, and routes once each,
  after their referenced tracks/FX exist.
]]

local _TYPED_ACTION_LUNA_TARGETING_HELP = [[

LUNA TARGETING CHECKLIST:
- When a request applies to multiple currently selected tracks, never use
  `track.resolve` with `selected:true`. Resolve each target by exact name when
  known, or use a distinct 1-based `selected_index` for each selected track.
- Existing selected tracks must not also receive `track.create` or
  `track.ensure`. Resolve each target once, then reuse that id for `track.set`,
  `fx.add_stock`, `fx.set_param`, and `send.create`.
- FX/plugin names are never tracks or track ids.
]]

local _TYPED_ACTION_STRICT_FENCE_HELP = [[

MODEL-SCOPED ACTION FORMAT CHECKLIST:
- When this typed-action contract is present, it overrides normal context-bucket requests for supported stock track, stock FX, parameter, and send actions.
- Do not emit `<context_needed>` for requests that fit the typed-action contract; use the stock FX names and values already present in the user request.
- Emit exactly one `reaassist-actions` fenced JSON block.
- Do not omit the fence, change the fence label, emit raw JSON, emit Lua, or add prose outside the fence.
- The JSON object must contain only top-level fields `version` and `actions`.
- Do not include `pinned`, metadata, comments, explanations, or any other top-level field.
- For `track.create` and `track.ensure`, use `"position":"end"` or `null`; do not use numeric positions.
- For `fx.set_param`, `fx` must be the earlier `fx.add_stock.id`, not the track id, plugin name, blank string, or example placeholder.
- Re-emit the complete action plan in that single block.
]]

local _TYPED_ACTION_PROFILE_ROUTING_HELP = {
  key = "routing_semantic_help",
  extra_prompt = _TYPED_ACTION_ROUTING_SEMANTIC_HELP,
  semantic_retry = true,
  semantic_retry_from_scratch = true,
  schema_fast_escalate = true,
  semantic_fast_escalate = true,
  fallback = {
    provider_id = "openai",
    model_id = "gpt-5.6-terra",
    thinking_value = "low",
    reason = "typed_action_semantic_retry_failed",
  },
}

local _TYPED_ACTION_PROFILE_MINIMAL_PLAN_HELP = {
  key = "minimal_plan_help",
  extra_prompt = _TYPED_ACTION_MINIMAL_PLAN_HELP,
  semantic_retry = true,
  fallback = {
    provider_id = "openai",
    model_id = "gpt-5.6-terra",
    thinking_value = "none",
    reason = "typed_action_semantic_retry_failed",
  },
}

local _TYPED_ACTION_PROFILE_LUNA_ROUTING_HELP = {
  key = "luna_routing_semantic_help",
  extra_prompt = _TYPED_ACTION_ROUTING_SEMANTIC_HELP
    .. _TYPED_ACTION_MINIMAL_PLAN_HELP
    .. _TYPED_ACTION_LUNA_TARGETING_HELP,
  semantic_retry = true,
  semantic_retry_from_scratch = false,
  semantic_max_retries = 1,
  response_format_omit_operation_shapes = true,
  fallback = {
    provider_id = "openai",
    model_id = "gpt-5.6-terra",
    thinking_value = "none",
    reason = "typed_action_semantic_retry_failed",
  },
}

local _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP = {
  key = "strict_fence_help",
  extra_prompt = _TYPED_ACTION_STRICT_FENCE_HELP,
  semantic_retry = true,
}

local _TYPED_ACTION_PROFILE_BASELINE_SEMANTIC = {
  key = "baseline_destructive_semantic",
  semantic_retry = true,
  destructive_mismatch_only = true,
}

local _TYPED_ACTION_PROFILE_COMPACT_RESPONSE_SCHEMA = {
  key = "compact_response_schema",
  response_format_omit_operation_shapes = true,
  semantic_retry = true,
  destructive_mismatch_only = true,
}

local _TYPED_ACTION_BASELINE_DESTRUCTIVE_CODES = {
  ambiguous_selected_track = true,
  ambiguous_property_value = true,
  bus_send_not_unity = true,
  duplicate_track_fx = true,
  extra_inferred_return_bus_send = true,
  forbidden_selected_index = true,
  forbidden_track_index = true,
  fx_as_track = true,
  incomplete_multi_target_plan = true,
  missing_selected_index = true,
  resolve_after_planned_track = true,
  return_fx_mismatch = true,
  track_order_mismatch = true,
  unrequested_master_send_action = true,
  unrequested_param_action = true,
  unexpected_folder_actions = true,
  unexpected_pan_lfo_action = true,
  unexpected_track_create_existing_target = true,
  unexpected_track_ensure_actions = true,
  unexpected_track_fx = true,
  unexpected_track_resolve_target = true,
  unexpected_track_set_actions = true,
  unsupported_record_arm_typed_action = true,
}

local function _typed_action_filter_semantic_errors_for_profile(errors, profile)
  if type(profile) ~= "table" or profile.destructive_mismatch_only ~= true
      or type(errors) ~= "table" or #errors == 0 then
    return errors
  end
  local filtered = {}
  for _, err in ipairs(errors) do
    if _TYPED_ACTION_BASELINE_DESTRUCTIVE_CODES[
        tostring(err and err.code or "")] then
      filtered[#filtered + 1] = err
    end
  end
  return filtered
end

local _TYPED_ACTION_PROFILES_BY_KEY = {
  routing_semantic_help = _TYPED_ACTION_PROFILE_ROUTING_HELP,
  routing_semantic_retry_help = {
    key = "routing_semantic_retry_help",
    extra_prompt = _TYPED_ACTION_ROUTING_SEMANTIC_HELP,
    semantic_retry = true,
    semantic_retry_from_scratch = true,
    fallback = {
      provider_id = "openai",
      model_id = "gpt-5.6-terra",
      thinking_value = "low",
      reason = "typed_action_semantic_retry_failed",
    },
  },
  luna_routing_semantic_help = _TYPED_ACTION_PROFILE_LUNA_ROUTING_HELP,
  minimal_plan_help = _TYPED_ACTION_PROFILE_MINIMAL_PLAN_HELP,
  strict_fence_help = _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP,
  compact_response_schema = _TYPED_ACTION_PROFILE_COMPACT_RESPONSE_SCHEMA,
}

local _TYPED_ACTION_MODEL_PROFILES = {
  openai = {
    ["gpt-5.6-luna"] = _TYPED_ACTION_PROFILE_LUNA_ROUTING_HELP,
    ["gpt-5.6-terra"] = _TYPED_ACTION_PROFILE_COMPACT_RESPONSE_SCHEMA,
    ["gpt-5.6-sol"] = _TYPED_ACTION_PROFILE_COMPACT_RESPONSE_SCHEMA,
    ["gpt-5.4-mini"] = {
      key = "mini_routing_semantic_help",
      extra_prompt = _TYPED_ACTION_ROUTING_SEMANTIC_HELP,
      semantic_retry = true,
      schema_fast_escalate = true,
      semantic_fast_escalate = true,
      fallback = {
        provider_id = "openai",
        model_id = "gpt-5.6-terra",
        thinking_value = "none",
        reason = "typed_action_semantic_retry_failed",
      },
    },
  },
  deepseek = {
    ["deepseek-v4-flash"] = _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP,
  },
  anthropic = {
    ["claude-haiku-4-5"] = _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP,
  },
  google = {
    ["gemini-3.5-flash"] = _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP,
    ["gemini-3.1-flash-lite"] = _TYPED_ACTION_PROFILE_STRICT_FENCE_HELP,
  },
}
_TYPED_ACTION_PROFILES_BY_KEY.mini_routing_semantic_help =
  _TYPED_ACTION_MODEL_PROFILES.openai["gpt-5.4-mini"]
assert(_TYPED_ACTION_PROFILES_BY_KEY.mini_routing_semantic_help,
  "missing typed-action mini routing profile")

-- Model-specific typed-action prompt profiles. These add stricter fence/schema
-- guidance or automatic escalation for models that tend to omit helper actions,
-- use prose fences, or need a stronger semantic retry.
function Code.typed_actions_model_profile(provider_id, model_id)
  local by_provider = _TYPED_ACTION_MODEL_PROFILES[tostring(provider_id or "")]
  if not by_provider then return nil end
  return by_provider[tostring(model_id or "")]
end

function Code.typed_actions_model_profile_by_key(key)
  return _TYPED_ACTION_PROFILES_BY_KEY[tostring(key or "")]
end

local function _typed_action_contract_for_profile(contract, profile)
  if not contract or contract == "" then return contract end
  if type(profile) ~= "table" then return contract end
  local extra = profile.extra_prompt
  if type(extra) ~= "string" or extra == "" then return contract end
  return contract .. extra
end

function Code.typed_action_request_specific_help(user_text)
  local rules = {}
  local absolute_indexes =
    Code._typed_action_absolute_track_indexes_from_user_text(user_text)
  if #absolute_indexes == 1
     and not Code.typed_action_user_requests_selected_target(user_text)
     and not Code.typed_action_user_requests_track_creation(user_text)
     and not Code._typed_action_forbids_absolute_track_index(user_text) then
    local n = tostring(absolute_indexes[1])
    rules[#rules + 1] = "- The user targeted existing Track " .. n
      .. " by absolute 1-based track number. Emit exactly "
      .. "`{\"op\":\"track.resolve\",\"id\":\"target_track\",\"index\":"
      .. n .. "}` for that target before mutations. Do not add `name`, "
      .. "`selected`, or `selected_index` to that action. Do not emit "
      .. "`track.create` or `track.ensure` for this target. Reuse "
      .. "`target_track` in each mutation that targets it."
  end
  if Code.typed_action_user_forbids_track_creation(user_text) then
    rules[#rules + 1] = "- The user explicitly forbids creating tracks. Do "
      .. "not emit `track.create` or `track.ensure`. Resolve existing target "
      .. "tracks with `track.resolve`, then apply the requested `track.set`, "
      .. "`track.pan_lfo`, `fx.add_stock`, or `send.create` action."
  end
  if #rules == 0 then return "" end
  return "\n\nREQUEST-SPECIFIC TYPED ACTION RULE:\n"
    .. table.concat(rules, "\n") .. "\n"
end

local _TYPED_ACTION_SCHEMA_PARAM_KEYS = {
  "band",
  "frequency_hz",
  "gain_db",
  "threshold_db",
  "ceiling_db",
  "attack_ms",
  "release_ms",
  "wet_db",
  "dry_db",
  "rms_ms",
  "free_time_ms",
  "musical_length",
  "feedback_pct",
  "feedback_db",
  "room_size",
  "dampening",
  "hysteresis_db",
  "hold_ms",
}

local function _typed_action_json_type(...)
  local out = {}
  for i = 1, select("#", ...) do out[#out+1] = select(i, ...) end
  return { type = out }
end

local function _typed_action_string_enum(value)
  return { type = "string", enum = { value } }
end

local function _typed_action_required_from_properties(properties)
  local required = {}
  for key in pairs(properties or {}) do required[#required+1] = key end
  table.sort(required)
  return required
end

local function _typed_action_schema_object(properties, required)
  return {
    type = "object",
    properties = properties,
    required = required or _typed_action_required_from_properties(properties),
    additionalProperties = false,
  }
end

local function _typed_action_schema_action(properties, required)
  return _typed_action_schema_object(properties, required)
end

local function _typed_action_schema_params_object()
  local props = {}
  for _, name in ipairs(_TYPED_ACTION_SCHEMA_PARAM_KEYS) do
    props[name] = _typed_action_json_type("number", "null")
  end
  return _typed_action_schema_object(props, _TYPED_ACTION_SCHEMA_PARAM_KEYS)
end

-- OpenAI response_format schema builder for typed actions. The schema narrows
-- track selectors and helper-action availability based on the current prompt so
-- constrained decoding cannot pick obviously disallowed structures.
function Code.typed_actions_openai_response_format_field(user_text)
  user_text = tostring(user_text
    or (type(S) == "table" and S.pending_orig_prompt) or "")
  local selected_indexes, selected_index_required =
    Code._typed_action_selected_indexes_from_user_text(user_text)
  local selected_target_requested =
    Code.typed_action_user_requests_selected_target(user_text)
  local requests_track_creation =
    Code.typed_action_user_requests_track_creation(user_text)
  local requests_track_ensure =
    Code.typed_action_user_requests_track_ensure(user_text)
  local mixed_existing_track_request =
    requests_track_creation
    and Code.typed_action_user_mentions_existing_or_source_track(user_text)
  local include_track_resolve = true
  local include_track_ensure = true
  local include_absolute_index_resolve =
    not Code._typed_action_forbids_absolute_track_index(user_text)
  if requests_track_creation
     and not selected_target_requested
     and not mixed_existing_track_request then
    include_track_resolve = false
  elseif Code.typed_action_user_forbids_track_creation(user_text) then
    include_track_ensure = false
  end
  local selected_index_schema = { type = "number" }
  if #selected_indexes > 0 then
    selected_index_schema = { type = "number", enum = selected_indexes }
  end
  local include_track_create = requests_track_creation
  if include_track_create then
    if not selected_target_requested
       and not mixed_existing_track_request then
      include_track_resolve = false
    end
  end
  if Code.typed_action_user_forbids_track_creation(user_text) then
    include_track_create = false
  end

  local action_variants = {}
  local function add_action(schema)
    action_variants[#action_variants + 1] = schema
  end

  if include_track_create then
    add_action(_typed_action_schema_action({
      op = _typed_action_string_enum("track.create"),
      id = { type = "string" },
      name = _typed_action_json_type("string", "null"),
      position = _typed_action_json_type("string", "null"),
      select = _typed_action_json_type("boolean", "null"),
    }))
  end

  if include_track_ensure
      and (not include_track_create or requests_track_ensure) then
    add_action(_typed_action_schema_action({
      op = _typed_action_string_enum("track.ensure"),
      id = { type = "string" },
      name = { type = "string" },
      position = _typed_action_json_type("string", "null"),
      select = _typed_action_json_type("boolean", "null"),
    }))
  end

  -- For blank-project/create-track requests, the model has no existing target
  -- to resolve. Do not offer track.resolve in the structured-output schema:
  -- weak models were legally choosing that branch as a fake FX/send placeholder
  -- and then failing semantic validation before any safe mutation could run.
  if include_track_resolve then
    add_action(_typed_action_schema_action({
      op = _typed_action_string_enum("track.resolve"),
      id = { type = "string" },
      name = { type = "string" },
      selected = _typed_action_json_type("null"),
      selected_index = _typed_action_json_type("null"),
      index = _typed_action_json_type("null"),
    }))
    if not selected_index_required then
      add_action(_typed_action_schema_action({
        op = _typed_action_string_enum("track.resolve"),
        id = { type = "string" },
        name = _typed_action_json_type("null"),
        selected = { type = "boolean", enum = { true } },
        selected_index = _typed_action_json_type("null"),
        index = _typed_action_json_type("null"),
      }))
    end
    add_action(_typed_action_schema_action({
      op = _typed_action_string_enum("track.resolve"),
      id = { type = "string" },
      name = _typed_action_json_type("null"),
      selected = _typed_action_json_type("null"),
      selected_index = selected_index_schema,
      index = _typed_action_json_type("null"),
    }))
    if include_absolute_index_resolve then
      add_action(_typed_action_schema_action({
        op = _typed_action_string_enum("track.resolve"),
        id = { type = "string" },
        name = _typed_action_json_type("null"),
        selected = _typed_action_json_type("null"),
        selected_index = _typed_action_json_type("null"),
        index = { type = "number" },
      }))
      add_action(_typed_action_schema_action({
        op = _typed_action_string_enum("track.resolve"),
        id = { type = "string" },
        name = { type = "string" },
        selected = _typed_action_json_type("null"),
        selected_index = _typed_action_json_type("null"),
        index = { type = "number" },
      }))
    end
  end

  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("track.set"),
    track = { type = "string" },
    name = _typed_action_json_type("string", "null"),
    volume_db = _typed_action_json_type("number", "null"),
    pan_pct = _typed_action_json_type("number", "null"),
    mute = _typed_action_json_type("boolean", "null"),
    solo = _typed_action_json_type("boolean", "null"),
    master_send = _typed_action_json_type("boolean", "null"),
  }))
  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("track.pan_lfo"),
    track = { type = "string" },
    start = _typed_action_json_type("string", "null"),
    bars = _typed_action_json_type("number", "null"),
    cycles_per_bar = _typed_action_json_type("number", "null"),
    depth_pct = _typed_action_json_type("number", "null"),
    resolution = _typed_action_json_type("string", "null"),
    clear_existing = _typed_action_json_type("boolean", "null"),
  }))
  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("track.folder"),
    parent = { type = "string" },
    children = {
      type = "array",
      items = { type = "string" },
    },
  }))
  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("fx.add_stock"),
    track = { type = "string" },
    id = { type = "string" },
    fx = {
      type = "string",
      enum = { "ReaEQ", "ReaComp", "ReaDelay", "ReaVerbate", "ReaGate", "ReaLimit" },
    },
  }))
  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("fx.set_param"),
    fx = { type = "string" },
    params = _typed_action_schema_params_object(),
  }))
  add_action(_typed_action_schema_action({
    op = _typed_action_string_enum("send.create"),
    id = _typed_action_json_type("string", "null"),
    ["from"] = { type = "string" },
    to = { type = "string" },
    volume_db = _typed_action_json_type("number", "null"),
    pan = _typed_action_json_type("number", "null"),
    mode = _typed_action_json_type("string", "number", "null"),
    muted = _typed_action_json_type("boolean", "null"),
  }))

  local action_schema = { anyOf = action_variants }
  local schema = _typed_action_schema_object({
    version = { type = "integer", enum = { 1 } },
    actions = {
      type = "array",
      items = action_schema,
      maxItems = 64,
    },
  }, { "version", "actions" })
  local encoded = JSON.encode({
    type = "json_schema",
    json_schema = {
      name = "reaassist_actions_v1",
      strict = true,
      schema = schema,
    },
  })
  if not encoded then return "" end
  return ',"response_format":' .. encoded
end

local function _typed_action_text_has_any(lt, terms)
  for _, term in ipairs(terms) do
    if lt:find(term, 1, true) then return true end
  end
  return false
end

local function _typed_action_text_has_any_word(lt, terms)
  for _, term in ipairs(terms) do
    if lt:find("%f[%w]" .. term .. "%f[%W]") then return true end
  end
  return false
end

function Code.selected_track_rename_numbered_range(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return nil end
  if lt:find("%f[%w]rename%f[%W]") == nil then return nil end
  if not (lt:find("selected tracks", 1, true)
      or lt:find("selected track", 1, true)) then
    return nil
  end
  if _typed_action_text_has_any(lt, {
      "item", "items", "take", "takes", "midi", "marker", "markers",
      "region", "regions", "fx", "plugin", "plugins", "route", "routing",
      "send", "sends",
    }) then
    return nil
  end
  if not (lt:find("sequential", 1, true)
      or lt:find("sequence", 1, true)
      or lt:find("numbered", 1, true)
      or lt:find("number", 1, true)
      or lt:find("index", 1, true)) then
    return nil
  end
  local start_raw, end_raw =
    lt:match("%f[%w]from%f[%W]%s*(%d+)%s+to%s+(%d+)")
  if not start_raw then return nil end
  local start_index, end_index = tonumber(start_raw), tonumber(end_raw)
  if not start_index or not end_index then return nil end
  if start_index % 1 ~= 0 or end_index % 1 ~= 0 then return nil end
  local expected_count = math.abs(end_index - start_index) + 1
  if expected_count < 1 or expected_count > 256 then return nil end
  return {
    start_index = start_index,
    end_index = end_index,
    expected_count = expected_count,
  }
end

function Code.prompt_requests_pan_lfo_automation(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  local has_track_pan =
    not (lt:find("send pan", 1, true)
      or lt:find("pan the send", 1, true)
      or lt:find("pan send", 1, true))
    and (lt:find("%f[%w]pan%f[%W]") ~= nil
      or lt:find("%f[%w]panner%f[%W]") ~= nil
      or lt:find("%f[%w]autopan%f[%W]") ~= nil
      or lt:find("auto%-pan") ~= nil
      or lt:find("percent left", 1, true) ~= nil
      or lt:find("percent right", 1, true) ~= nil)
  local has_lfo =
    lt:find("%f[%w]lfo%f[%W]") ~= nil
    or lt:find("%f[%w]autopan%f[%W]") ~= nil
    or lt:find("auto%-pan") ~= nil
    or lt:find("%f[%w]sine%f[%W]") ~= nil
    or lt:find("%f[%w]sinewave%f[%W]") ~= nil
    or lt:find("%f[%w]oscillat") ~= nil
  if not has_lfo then return false end
  if has_track_pan then
    for n in lt:gmatch("%f[%w](%d+%.?%d*)%s*hz%f[%W]") do
      local hz = tonumber(n)
      if hz and hz >= 15
          and not lt:find("%f[%w]jsfx%f[%W]")
          and not lt:find("%f[%w]plugin%f[%W]") then
        return false
      end
    end
  elseif lt:find("%f[%w]sine%s*wave%s+per%s+bar%f[%W]") == nil
      and lt:find("%f[%w]sinewave%s+per%s+bar%f[%W]") == nil then
    return false
  end
  if lt:find("%f[%w]jsfx%f[%W]")
      or lt:find("%f[%w]plugin%f[%W]")
      or lt:find("%f[%w]audio rate%f[%W]")
      or lt:find("audio%-rate") then
    return false
  end
  return lt:find("%f[%w]bar%f[%W]") ~= nil
    or lt:find("%f[%w]bars%f[%W]") ~= nil
    or lt:find("%f[%w]measure%f[%W]") ~= nil
    or lt:find("%f[%w]measures%f[%W]") ~= nil
end

function Code.typed_actions_prompt_contract(user_text, opts)
  opts = type(opts) == "table" and opts or {}
  if not opts.force_enabled and not Code.typed_actions_executor_enabled() then
    return nil, "executor_disabled"
  end
  if type(user_text) ~= "string" or user_text == "" then
    return nil, "empty_prompt"
  end

  local lt = Code._localized_action_intent_text(user_text)
  local words = " " .. lt:gsub("[^%w]+", " "):gsub("%s+", " ") .. " "
  local function has_word_phrase(term)
    return words:find(" " .. term .. " ", 1, true) ~= nil
  end
  if CTX
      and type(CTX.explicit_validated_plugin_profile_names) == "function" then
    for _, profile_name in ipairs(
        CTX.explicit_validated_plugin_profile_names(user_text)) do
      if not _TYPED_ACTION_STOCK_FX[profile_name] then
        return nil, "validated_plugin_profile_requires_lua"
      end
    end
  end
  local predicate_track_property_request =
    Code._typed_action_user_requests_predicate_track_property_target(user_text)
  local first_word = lt:match("^%s*([%a]+)")
  local question_prefixes = {
    what = true, why = true, how = true, should = true, would = true,
    could = true, can = true, is = true, are = true, ["do"] = true,
    does = true, did = true, will = true, where = true, who = true,
  }
  local when_second_word = first_word == "when"
    and lt:match("^%s*when%s+([%a]+)") or nil
  local when_question_prefixes = {
    is = true, are = true, ["do"] = true, does = true, did = true,
    will = true, would = true, should = true, can = true, could = true,
  }
  local explicit_question_prefix = question_prefixes[first_word] == true
    or when_question_prefixes[when_second_word] == true
  if predicate_track_property_request
      and lt:find("?", 1, true) == nil
      and not explicit_question_prefix then
    return nil, "unsupported_multi_track_property_target"
  end
  local question_or_readonly = Code.prompt_is_question_or_readonly(user_text)
  if question_or_readonly then
    return nil, "question_or_readonly"
  end

  if Code.prompt_requests_reusable_action_script(user_text) then
    return nil, "deferred_reusable_action"
  end

  local explicit_lua_request =
       lt:find("reaper lua", 1, true) ~= nil
    or lt:find("lua script", 1, true) ~= nil
    or lt:find("lua code", 1, true) ~= nil
    or lt:find("reascript", 1, true) ~= nil
    or lt:find("return only lua", 1, true) ~= nil
    or lt:find("return only the lua", 1, true) ~= nil
    or (has_word_phrase("write") and has_word_phrase("script")
      and (has_word_phrase("reaper") or has_word_phrase("lua")))
    or (has_word_phrase("generate") and has_word_phrase("script")
      and (has_word_phrase("reaper") or has_word_phrase("lua")))
  if explicit_lua_request then
    return nil, "explicit_lua_request"
  end

  if CTX and type(CTX.prompt_indicates_timecode_generator) == "function"
      and CTX.prompt_indicates_timecode_generator(user_text) then
    return nil, "unsupported_timecode_generator"
  end

  if type(Code.typed_action_user_requests_hardware_output) == "function"
      and Code.typed_action_user_requests_hardware_output(user_text) then
    return nil, "unsupported_hardware_output"
  end

  if Code._typed_action_user_requests_record_ready_state(user_text)
      or has_word_phrase("arm")
      or has_word_phrase("armed")
      or has_word_phrase("record arm")
      or has_word_phrase("record armed")
      or has_word_phrase("recording") then
    return nil, "unsupported_record_arm"
  end

  if Code._typed_action_user_requests_track_deletion(user_text) then
    return nil, "unsupported_track_delete"
  end

  local has_pan_lfo =
    type(Code.prompt_requests_pan_lfo_automation) == "function"
    and Code.prompt_requests_pan_lfo_automation(user_text)
  local has_readelay_tempo_sync = lt:find("readelay", 1, true) ~= nil
    and _typed_action_text_has_any(lt, {
      "tempo sync", "tempo-sync", "tempo synced", "tempo-synced",
    })

  local blocked_terms = {
    "midi", "jsfx", "eel2", "reajs", "theme", "marker", "region",
    "item", "take",
    "render", "export", "install", "download", "color", "colors",
    "colour", "colours", "third-party", "third party",
    "vst3", "fabfilter", "pro-q", "pro q", "waves", "uad", "kontakt",
    "serum", "vital", "omnisphere", "ozone", "soothe",
  }
  if not has_pan_lfo then
    blocked_terms[#blocked_terms + 1] = "envelope"
    blocked_terms[#blocked_terms + 1] = "automation"
    if not has_readelay_tempo_sync then
      blocked_terms[#blocked_terms + 1] = "tempo"
    end
    blocked_terms[#blocked_terms + 1] = "time signature"
  end
  if _typed_action_text_has_any(lt, blocked_terms) then
    return nil, "unsupported_scope"
  end

  local has_stock_fx = _typed_action_text_has_any(lt, {
    "reaeq", "reacomp", "readelay", "reaverbate", "reagate", "realimit",
  })
  if has_stock_fx then
    -- The typed-action lane is an exact command executor, not a substitute for
    -- plugin knowledge. Qualitative requests need the unified plugin profile
    -- and generated-Lua path so the model can choose musically appropriate
    -- settings and can reach parameters outside the deliberately small schema.
    local qualitative_stock_fx_terms = {
      "gentle", "gently", "natural", "transparent", "controlled",
      "more even", "even out", "squashed", "punchy", "punchier",
      "punch", "dense", "aggressive", "subtle", "warm", "warmer",
      "bright", "brighter", "dark", "darker", "muddy", "mud",
      "boxy", "boxiness", "harsh", "harshness", "rumble",
      "clean up", "tasteful", "musical", "smooth", "smoother",
      "open up", "airy", "air", "sheen", "glue", "polish",
      "restrained", "sits behind", "sit behind", "crowd", "clutter",
      "sound good", "sound better", "feel better",
    }
    if _typed_action_text_has_any(lt, qualitative_stock_fx_terms) then
      return nil, "qualitative_stock_fx_requires_profile"
    end

    -- Route named parameter requests that the typed-action schema cannot
    -- express through the same profile/Lua path. This prevents a partial plan
    -- from silently satisfying only the easy controls.
    local unsupported_stock_fx_parameter = false
    if lt:find("reacomp", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "ratio", "knee", "makeup", "make up", "auto release",
        "pre comp", "pre-comp", "lookahead", "sidechain", "detector",
        "lowpass", "low pass", "highpass", "high pass", "bypass",
        "delta", "legacy", "filter preview",
      })
    end
    if not unsupported_stock_fx_parameter
        and lt:find("reaeq", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "q value", "bandwidth", "slope", "shape", "filter type",
        "band type", "high pass", "highpass", "low pass", "lowpass",
        "shelf", "notch", "bypass", "enabled",
      })
    end
    if not unsupported_stock_fx_parameter
        and lt:find("readelay", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "stereo width", "low pass", "lowpass",
        "high pass", "highpass", "bypass",
      })
      local tap_mentioned = lt:find("%f[%w]tap%f[%W]") ~= nil
      local supported_tap_mentioned = false
      for tap_number in lt:gmatch("%f[%w]tap%s*(%d+)") do
        if tonumber(tap_number) == 1 then
          supported_tap_mentioned = true
        else
          unsupported_stock_fx_parameter = true
        end
      end
      if tap_mentioned and not supported_tap_mentioned then
        unsupported_stock_fx_parameter = true
      end
    end
    if not unsupported_stock_fx_parameter
        and lt:find("reaverbate", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "pre delay", "pre-delay", "stereo width", "initial delay",
        "low pass", "lowpass", "high pass", "highpass", "bypass",
      })
    end
    if not unsupported_stock_fx_parameter
        and lt:find("reagate", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "pre open", "pre-open", "lookahead", "sidechain", "detector",
        "low pass", "lowpass", "high pass", "highpass", "bypass",
      })
    end
    if not unsupported_stock_fx_parameter
        and lt:find("realimit", 1, true) then
      unsupported_stock_fx_parameter = _typed_action_text_has_any(lt, {
        "release", "lookahead", "true peak", "true-peak", "link",
        "stereo", "bypass",
      })
    end
    if unsupported_stock_fx_parameter then
      return nil, "unsupported_stock_fx_parameter_requires_profile"
    end

    -- The v1 typed-action contract can add stock FX, but it cannot bind and
    -- edit an instance already in the chain. Keep explicit existing-instance
    -- requests in the profile-aware Lua lane so they cannot add a duplicate.
    local existing_stock_fx_instance = false
    for _, fx_name in ipairs({
      "reaeq", "reacomp", "readelay", "reaverbate", "reagate", "realimit",
    }) do
      if lt:find("existing " .. fx_name, 1, true)
          or lt:find(fx_name .. " already", 1, true)
          or lt:find("already loaded " .. fx_name, 1, true)
          or lt:find("already inserted " .. fx_name, 1, true) then
        existing_stock_fx_instance = true
        break
      end
    end
    if existing_stock_fx_instance then
      return nil, "existing_stock_fx_requires_profile"
    end
  end
  if not has_stock_fx then
    local generic_fx_lt = lt
    for _, phrase in ipairs({
      "do not add any effects",
      "do not add effects",
      "do not add any effect",
      "do not add effect",
      "do not add any fx",
      "do not add fx",
      "add no effects",
      "add no effect",
      "add no fx",
      "no effects",
      "no effect",
      "no fx",
    }) do
      generic_fx_lt = generic_fx_lt:gsub(phrase, "")
    end
    local generic_fx_words = " "
      .. generic_fx_lt:gsub("[^%w]+", " "):gsub("%s+", " ") .. " "
    local function has_generic_fx_word_phrase(term)
      return generic_fx_words:find(" " .. term .. " ", 1, true) ~= nil
    end
    local generic_fx_terms = {
      "chain", "fx", "effect", "effects", "plugin", "plugins",
      "compressor", "eq", "equalizer", "reverb", "delay", "gate",
      "limiter", "deesser", "saturation", "saturator", "chorus",
      "phaser", "pitch correction", "pitch shift", "vocal chain",
      "rock vocal", "suitable", "suitable for", "processing",
      "processor", "rack", "strip", "channel strip", "mix ready",
      "mixready", "sound good", "sound better", "amp", "amp sim",
      "distortion", "drive", "auto tune", "autotune",
    }
    for _, term in ipairs(generic_fx_terms) do
      if has_generic_fx_word_phrase(term) then
        return nil, "generic_fx_chain"
      end
    end
  end
  local has_routing = _typed_action_text_has_any_word(lt, {
    "route", "routing", "send", "sends", "bus", "buss", "aux",
  })
  local has_track_setup =
    _typed_action_text_has_any(lt, { "create", "add", "make", "set up", "setup", "build" })
    and _typed_action_text_has_any_word(lt, { "track", "tracks", "bus", "aux" })
  local track_property_lt =
    Code._typed_action_track_property_intent_text(user_text)
  local has_track_property =
    _typed_action_text_has_any_word(track_property_lt, {
      "track", "tracks", "bus", "aux", "selected", "current", "existing",
    })
    and _typed_action_text_has_any(track_property_lt, {
      "volume", "vol ", "fader", "level", "pan", "panned", "mute", "muted", "unmute",
      "solo", "soloed", "unsolo",
      "master send", "main send", "master/parent", "master parent",
      "parent send", "master output", "rename", "renamed", "call ", "called",
    })
  if has_track_property
      and (Code._typed_action_user_requests_aggregate_track_property_target(
        user_text)
        or Code._typed_action_user_requests_predicate_track_property_target(
          user_text)) then
    return nil, "unsupported_multi_track_property_target"
  end
  local has_folder = Code.typed_action_user_requests_folder(user_text)

  if not (has_stock_fx or has_routing or has_track_setup
      or has_track_property or has_folder) then
    if not has_pan_lfo then
      return nil, "no_typed_action_intent"
    end
  end

  if opts.response_format then
    local response_contract =
      _TYPED_ACTION_RESPONSE_FORMAT_FULL_PROMPT_CONTRACT
    if type(opts.profile) == "table"
       and opts.profile.response_format_omit_operation_shapes == true then
      response_contract = _TYPED_ACTION_RESPONSE_FORMAT_COMPACT_PROMPT_CONTRACT
    end
    local contract = _typed_action_contract_for_profile(
      response_contract, opts.profile)
    return contract .. Code.typed_action_request_specific_help(user_text),
      "eligible"
  end
  local contract = _typed_action_contract_for_profile(
    _TYPED_ACTION_PROMPT_CONTRACT, opts.profile)
  return contract .. Code.typed_action_request_specific_help(user_text),
    "eligible"
end

-- Convert assistant text into a repaired plan, then run request-aware semantic
-- validation. This catches plans that are syntactically valid but do not satisfy
-- the user's requested edit.
function Code.typed_actions_plan_from_text(text, opts)
  opts = type(opts) == "table" and opts or {}
  if opts.allow_raw_json then
    local raw_json = _typed_action_trim(text)
    if raw_json:sub(1, 1) == "{" then
      local plan, errors = Code.parse_typed_actions_block(raw_json)
      if plan then Code.repair_typed_actions_plan(plan, opts) end
      return plan, errors
    end
  end
  local raw, extract_errors = Code.extract_typed_actions(text)
  if not raw then return nil, extract_errors end
  local plan, errors = Code.parse_typed_actions_block(raw)
  if plan then Code.repair_typed_actions_plan(plan, opts) end
  return plan, errors
end

function Code.validate_typed_actions_semantics(plan, opts)
  opts = type(opts) == "table" and opts or {}
  local profile = opts.profile
  if type(profile) == "string" then
    profile = Code.typed_actions_model_profile_by_key(profile)
  end
  if type(profile) ~= "table"
     and tostring(opts.user_text or "") ~= "" then
    profile = _TYPED_ACTION_PROFILE_BASELINE_SEMANTIC
  end
  if type(profile) ~= "table" or profile.semantic_retry ~= true then
    return true, nil
  end

  local tracks, track_order, fx_seen_by_track, fx_by_track, op_counts, errors =
    {}, {}, {}, {}, {}, {}
  local fx_type_by_id = {}
  local folder_children_by_parent = {}
  local send_seen_by_names = {}
  local static_pan_targets = {}
  local planned_track_id_by_name = {}
  local function lower(s) return tostring(s or ""):lower() end
  local function trim(s) return Code._lua_trim_expr(s) end
  local function normalized_name(s)
    return lower(trim(s)):gsub("%s+", " ")
  end
  local function name_has(name, needle)
    return lower(name):find(tostring(needle or ""), 1, true) ~= nil
  end
  local function is_bus_name(name)
    local n = lower(name)
    return n:find("bus", 1, true) ~= nil or n:find("buss", 1, true) ~= nil
  end
  local function is_return_name(name)
    local n = lower(name)
    return n:find("verb", 1, true) ~= nil
      or n:find("reverb", 1, true) ~= nil
      or n:find("delay", 1, true) ~= nil
      or n:find("return", 1, true) ~= nil
      or n:find("aux", 1, true) ~= nil
  end
  local function is_aux_like_name(name)
    local n = lower(name)
    return is_return_name(name)
      or n:find("crush", 1, true) ~= nil
      or n:find("parallel", 1, true) ~= nil
  end
  local function word_text(s)
    return normalized_name(tostring(s or ""):gsub("[^%w]+", " "))
  end
  local function send_route_key(src_name, dst_name)
    local src = word_text(src_name)
    local dst = word_text(dst_name)
    if src == "" or dst == "" then return nil end
    return src .. "->" .. dst
  end
  local u = lower(opts.user_text)
  local u_words = word_text(opts.user_text)
  local exact_send_graph_requested =
    u:find("keep the graph exact", 1, true) ~= nil
    or u:find("do not add any other", 1, true) ~= nil
    or u:find("do not add extra", 1, true) ~= nil
    or u:find("no other sends", 1, true) ~= nil
  local function explicit_send_requested(src_name, dst_name)
    local src = word_text(src_name)
    local dst = word_text(dst_name)
    if src == "" or dst == "" then return false end
    local phrases = {
      src .. " to " .. dst,
      src .. " into " .. dst,
      src .. " feed " .. dst,
      src .. " feeds " .. dst,
      src .. " feeding " .. dst,
      "route " .. src .. " to " .. dst,
      "route " .. src .. " into " .. dst,
      "send " .. src .. " to " .. dst,
      "send " .. src .. " into " .. dst,
    }
    for _, phrase in ipairs(phrases) do
      if u_words:find(phrase, 1, true) then return true end
    end
    return false
  end
  local function user_mentions_db_value(db)
    local want = tonumber(db)
    if not want then return false end
    for raw in tostring(opts.user_text or ""):gmatch("([%+%-]?%d+%.?%d*)%s*[dD][bB]") do
      local got = tonumber(raw)
      if got and math.abs(got - want) <= 0.25 then return true end
    end
    return false
  end
  local function user_mentions_db_magnitude(db)
    local want = math.abs(tonumber(db) or 0)
    if want == 0 then return false end
    for raw in tostring(opts.user_text or ""):gmatch("([%+%-]?%d+%.?%d*)%s*[dD][bB]") do
      local got = tonumber(raw)
      if got and math.abs(math.abs(got) - want) <= 0.25 then return true end
    end
    return false
  end
  local track_level_change_requested =
    Code._typed_action_user_requests_track_level_change(opts.user_text)
  local function user_mentions_gain_direction(db)
    local want = tonumber(db)
    if not want or not user_mentions_db_magnitude(want) then return false end
    if track_level_change_requested
        and not (u:find("band", 1, true) ~= nil
          or u:find("eq", 1, true) ~= nil
          or u:find("filter", 1, true) ~= nil
          or u:find("frequency", 1, true) ~= nil
          or u:find("freq", 1, true) ~= nil
          or u:find("gain", 1, true) ~= nil) then
      return false
    end
    if want < 0 then
      return u:find("pull", 1, true) ~= nil
        or u:find("down", 1, true) ~= nil
        or u:find("reduce", 1, true) ~= nil
        or u:find("lower", 1, true) ~= nil
        or u:find("dip", 1, true) ~= nil
        or u:find("attenuate", 1, true) ~= nil
        or u:find("cut", 1, true) ~= nil
    elseif want > 0 then
      return u:find("boost", 1, true) ~= nil
        or u:find("raise", 1, true) ~= nil
        or u:find("lift", 1, true) ~= nil
        or u:find("push", 1, true) ~= nil
        or u:find("up", 1, true) ~= nil
    end
    return false
  end
  local required_selected_indexes, selected_index_required =
    Code._typed_action_selected_indexes_from_user_text(opts.user_text)
  local positional_selector_forbidden =
    Code._typed_action_forbids_positional_track_selector(opts.user_text)
  local seen_selected_indexes, any_selected_index_resolve = {}, false
  local allow_duplicate_fx =
    u:find("duplicate", 1, true) ~= nil
    or u:find("another", 1, true) ~= nil
    or u:find("two ", 1, true) ~= nil
    or u:find("multiple", 1, true) ~= nil
  local function user_mentions_name(name)
    local n = word_text(name)
    return n ~= "" and u_words:find(n, 1, true) ~= nil
  end
  local function requested_supported_stock_fx()
    for fx_name in pairs(_TYPED_ACTION_STOCK_FX) do
      if u:find(lower(fx_name), 1, true) ~= nil then return true end
    end
    return u:find("stock fx", 1, true) ~= nil
      or u:find("stock effect", 1, true) ~= nil
      or u:find("stock plugin", 1, true) ~= nil
  end
  local requests_stock_fx = requested_supported_stock_fx()
  local requests_params =
    requests_stock_fx
    and (u:find("threshold", 1, true) ~= nil
      or u:find("frequency", 1, true) ~= nil
      or u:find(" hz", 1, true) ~= nil
      or u:find("khz", 1, true) ~= nil
      or u:find("band", 1, true) ~= nil
      or u:find("gain", 1, true) ~= nil
      or (not track_level_change_requested
        and (u:find("pull", 1, true) ~= nil
          or u:find("push", 1, true) ~= nil
          or u:find("lower", 1, true) ~= nil
          or u:find("raise", 1, true) ~= nil
          or u:find("dip", 1, true) ~= nil))
      or u:find("ratio", 1, true) ~= nil
      or u:find("attack", 1, true) ~= nil
      or u:find("release", 1, true) ~= nil
      or u:find("feedback", 1, true) ~= nil
      or u:find("wet", 1, true) ~= nil
      or u:find("dry", 1, true) ~= nil
      or u:find("ceiling", 1, true) ~= nil)
  local function user_mentions_param(param, value, params)
    param = tostring(param or "")
    if param == "band" then
      return (params.frequency_hz ~= nil
          and user_mentions_param("frequency_hz", params.frequency_hz, params))
        or (params.gain_db ~= nil
          and user_mentions_param("gain_db", params.gain_db, params))
    elseif param == "frequency_hz" then
      return u:find("frequency", 1, true) ~= nil
        or u:find("freq", 1, true) ~= nil
        or u:find(" hz", 1, true) ~= nil
        or u:find("khz", 1, true) ~= nil
    elseif param == "gain_db" then
      return u:find("gain", 1, true) ~= nil
        or u:find("boost", 1, true) ~= nil
        or u:find("cut", 1, true) ~= nil
        or user_mentions_gain_direction(value)
        or (u:find("band", 1, true) ~= nil
          and user_mentions_db_value(value))
    elseif param == "threshold_db" then
      return u:find("threshold", 1, true) ~= nil
    elseif param == "ratio" then
      return u:find("ratio", 1, true) ~= nil
    elseif param == "attack_ms" then
      return u:find("attack", 1, true) ~= nil
    elseif param == "release_ms" then
      return u:find("release", 1, true) ~= nil
    elseif param == "wet_db" then
      return u:find("wet", 1, true) ~= nil
    elseif param == "dry_db" then
      return u:find("dry", 1, true) ~= nil
    elseif param == "rms_ms" then
      return u:find("rms", 1, true) ~= nil
    elseif param == "free_time_ms" then
      return u:find("free time", 1, true) ~= nil
        or u:find("free-time", 1, true) ~= nil
        or u:find("length (time)", 1, true) ~= nil
    elseif param == "musical_length" then
      return u:find("musical", 1, true) ~= nil
        or u:find("tempo", 1, true) ~= nil
        or u:find("quarter", 1, true) ~= nil
        or u:find("half note", 1, true) ~= nil
        or u:find("whole note", 1, true) ~= nil
    elseif param == "feedback_pct" or param == "feedback_db" then
      return u:find("feedback", 1, true) ~= nil
    elseif param == "room_size" then
      return u:find("room size", 1, true) ~= nil
        or u:find("room", 1, true) ~= nil
    elseif param == "dampening" then
      return u:find("dampening", 1, true) ~= nil
        or u:find("damping", 1, true) ~= nil
    elseif param == "hysteresis_db" then
      return u:find("hysteresis", 1, true) ~= nil
    elseif param == "hold_ms" then
      return u:find("hold", 1, true) ~= nil
    elseif param == "ceiling_db" then
      return u:find("ceiling", 1, true) ~= nil
    end
    return false
  end
  local send_intent_text =
    Code._typed_action_send_intent_text(opts.user_text)
  local send_intent_words = " " .. word_text(send_intent_text) .. " "
  local requests_sends =
    (send_intent_words:find(" send ", 1, true) ~= nil
      or send_intent_words:find(" sends ", 1, true) ~= nil
      or send_intent_words:find(" route ", 1, true) ~= nil
      or send_intent_words:find(" routes ", 1, true) ~= nil
      or send_intent_words:find(" routed ", 1, true) ~= nil
      or send_intent_words:find(" routing ", 1, true) ~= nil
      or send_intent_words:find(" feed ", 1, true) ~= nil
      or send_intent_words:find(" feeds ", 1, true) ~= nil
      or send_intent_words:find(" feeding ", 1, true) ~= nil)
  local function explicit_send_required(src_name, dst_name)
    local src = word_text(src_name)
    local dst = word_text(dst_name)
    if src == "" or dst == "" then return false end
    for _, phrase in ipairs({
      "do not send " .. src .. " to " .. dst,
      "do not send " .. src .. " into " .. dst,
      "don t send " .. src .. " to " .. dst,
      "don t send " .. src .. " into " .. dst,
      "without sending " .. src .. " to " .. dst,
      "without sending " .. src .. " into " .. dst,
    }) do
      if u_words:find(phrase, 1, true) then return false end
    end
    for _, phrase in ipairs({
      "send " .. src .. " to " .. dst,
      "send " .. src .. " into " .. dst,
      "route " .. src .. " to " .. dst,
      "route " .. src .. " into " .. dst,
      "feed " .. src .. " to " .. dst,
      "feed " .. src .. " into " .. dst,
      src .. " to " .. dst,
      src .. " into " .. dst,
    }) do
      if send_intent_words:find(phrase, 1, true) then return true end
    end
    return false
  end
  local track_property_text =
    Code._typed_action_track_property_intent_text(opts.user_text)
  local requests_master_send_state =
    Code._typed_action_user_requests_master_send_state(opts.user_text)
  local requests_master_send_off =
    Code._typed_action_user_requests_master_send_off(opts.user_text)
  local requests_record_ready_state =
    Code._typed_action_user_requests_record_ready_state(opts.user_text)
  local requests_track_properties =
    (track_property_text:find("volume", 1, true) ~= nil
      or track_property_text:find("fader", 1, true) ~= nil
      or track_property_text:find("pan", 1, true) ~= nil
      or track_property_text:find("panned", 1, true) ~= nil
      or track_property_text:find("mute", 1, true) ~= nil
      or track_property_text:find("muted", 1, true) ~= nil
      or track_property_text:find("unmute", 1, true) ~= nil
      or track_property_text:find("solo", 1, true) ~= nil
      or track_property_text:find("soloed", 1, true) ~= nil
      or track_property_text:find("unsolo", 1, true) ~= nil
      or requests_master_send_state
      or track_property_text:find("rename", 1, true) ~= nil
      or track_property_text:find("renamed", 1, true) ~= nil
      or track_property_text:find("call ", 1, true) ~= nil
      or track_property_text:find("called", 1, true) ~= nil
      or track_level_change_requested)
    and (track_property_text:find("track", 1, true) ~= nil
      or track_property_text:find("bus", 1, true) ~= nil
      or track_property_text:find("aux", 1, true) ~= nil)
  local predicate_track_property_request =
    Code._typed_action_user_requests_predicate_track_property_target(
      opts.user_text)
  local _, conflicting_static_pan =
    Code._typed_action_static_pan_value(opts.user_text)
  local requests_track_creation =
    Code.typed_action_user_requests_track_creation(opts.user_text)
  local user_text_lower = lower(opts.user_text)
  local existing_target_only =
    not requests_track_creation
    and (user_text_lower:find("existing track", 1, true) ~= nil
      or user_text_lower:find("existing tracks", 1, true) ~= nil
      or user_text_lower:find("resolve the existing", 1, true) ~= nil
      or user_text_lower:find("do not create", 1, true) ~= nil
      or user_text_lower:find("don't create", 1, true) ~= nil)
  local selected_target_requested =
    Code.typed_action_user_requests_selected_target(opts.user_text)
  local mixed_existing_track_request =
    requests_track_creation
    and Code.typed_action_user_mentions_existing_or_source_track(opts.user_text)
  local requests_folders =
    Code.typed_action_user_requests_folder(opts.user_text)
  local requests_pan_lfo =
    type(Code.prompt_requests_pan_lfo_automation) == "function"
    and Code.prompt_requests_pan_lfo_automation(opts.user_text)
  local master_send_off_seen = false
  local function is_fx_like_track_name(name)
    local n = " " .. word_text(name) .. " "
    return n:find(" eq ", 1, true) ~= nil
      or n:find(" comp ", 1, true) ~= nil
      or n:find(" compressor ", 1, true) ~= nil
      or n:find(" reverb ", 1, true) ~= nil
      or n:find(" delay ", 1, true) ~= nil
      or n:find(" gate ", 1, true) ~= nil
      or n:find(" limiter ", 1, true) ~= nil
  end
  local function requested_exact_track_order(text)
    text = tostring(text or "")
    local lt = lower(text)
    local stock_fx_order_name = {}
    for fx_name in pairs(_TYPED_ACTION_STOCK_FX) do
      stock_fx_order_name[normalized_name(fx_name)] = true
    end
    local function is_stock_fx_order(order)
      if type(order) ~= "table" or #order < 2 then return false end
      for _, name in ipairs(order) do
        if not stock_fx_order_name[normalized_name(name)] then return false end
      end
      return true
    end
    local function parse_order_fragment(fragment)
      fragment = tostring(fragment or "")
      fragment = fragment:gsub("^%s*.-:%s*", "")
      fragment = fragment:gsub("%f[%a][Tt]hen%f[%A]", ",")
      fragment = fragment:gsub("%f[%a][Aa]nd%f[%A]", ",")
      local out = {}
      for part in fragment:gmatch("[^,]+") do
        local name = trim(part)
          :gsub("^then%s+", "")
          :gsub("^and%s+", "")
          :gsub("^create%s+", "")
          :gsub("^make%s+", "")
          :gsub("^set%s+up%s+", "")
          :gsub("^build%s+", "")
          :gsub("^exactly%s+[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^[%w]+%s+tracks?%s+named%s+", "")
          :gsub("^tracks?%s+named%s+", "")
          :gsub("^named%s+", "")
          :gsub("^the%s+", "")
          :gsub("^a%s+", "")
        name = trim(name)
        if name ~= "" then out[#out + 1] = normalized_name(name) end
      end
      return #out >= 2 and out or nil
    end
    local explicit_fragment =
      text:match("[Tt]rack%s+order%s+must%s+be%s+([^%.\n]+)")
      or text:match("[Oo]rder%s+must%s+be%s+([^%.\n]+)")
    if explicit_fragment then
      local explicit_order = parse_order_fragment(explicit_fragment)
      if explicit_order and not is_stock_fx_order(explicit_order) then
        return explicit_order
      end
    end
    local marker = lt:find(" in that exact order", 1, true)
      or lt:find(" in exact order", 1, true)
      or lt:find(" in that order", 1, true)
    if not marker then return nil end
    local before = text:sub(1, marker - 1)
    local cut = 0
    for i = 1, #before do
      local ch = before:sub(i, i)
      if ch == "." or ch == "\n" then cut = i end
    end
    if cut > 0 then before = before:sub(cut + 1) end
    before = before:gsub("^.*[Cc]reate%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Cc]reate%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Mm]ake%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*[Ss]et%s+up%s+exactly%s+[%w%-]+%s+tracks?%s+named%s+", "")
    before = before:gsub("^.*%f[%a]with%s+", "")
    local order = parse_order_fragment(before)
    if order and is_stock_fx_order(order) then return nil end
    return order
  end

  local function requested_folder_memberships(text)
    text = tostring(text or "")
    local wanted = {}
    local by_parent = {}
    local function add_membership(parent, children)
      parent = normalized_name(parent)
      if parent == "" or type(children) ~= "table" then return end
      local item = by_parent[parent]
      if not item then
        item = { parent = parent, children = {}, seen = {} }
        by_parent[parent] = item
        wanted[#wanted + 1] = item
      end
      for _, child in ipairs(children) do
        child = normalized_name(child)
        if child ~= "" and child ~= parent and not item.seen[child] then
          item.children[#item.children + 1] = child
          item.seen[child] = true
        end
      end
    end
    local function mentioned_names(fragment)
      local f_words = " " .. word_text(fragment) .. " "
      local out, seen = {}, {}
      for _, name in ipairs(track_order) do
        local key = word_text(name)
        if key ~= "" and f_words:find(" " .. key .. " ", 1, true)
            and not seen[key] then
          out[#out + 1] = normalized_name(name)
          seen[key] = true
        end
      end
      return out
    end
    local function pattern_escape(value)
      return tostring(value or ""):gsub("([^%w])", "%%%1")
    end
    for sentence in text:gmatch("[^%.\n]+") do
      local sentence_l = lower(sentence)
      for _, name in ipairs(track_order) do
        local parent = normalized_name(name)
        if parent ~= "" then
          local pat = pattern_escape(parent) .. "%s+folder%s+with%s+"
          local _s, e = sentence_l:find(pat)
          if e then
            local fragment = sentence:sub(e + 1)
            fragment = fragment:gsub("%f[%a][Ii]nside%s+it.*$", "")
            fragment = fragment:gsub("%f[%a][Aa]s%s+normal%s+.-$", "")
            local children = mentioned_names(fragment)
            add_membership(parent, children)
          end
        end
      end
      local start_pos, end_pos = lower(sentence):find("folder%s+containing")
      if start_pos then
        local parents = mentioned_names(sentence:sub(1, start_pos - 1))
        local children = mentioned_names(sentence:sub(end_pos + 1))
        local parent = parents[#parents]
        if parent and #children > 0 then
          add_membership(parent, children)
        end
      end
    end
    local nested_children_by_parent = {}
    for _, item in ipairs(wanted) do
      nested_children_by_parent[item.parent] = nested_children_by_parent[item.parent] or {}
      for _, child in ipairs(item.children) do
        nested_children_by_parent[item.parent][child] = true
      end
    end
    for _, item in ipairs(wanted) do
      local immediate_set = {}
      for _, child in ipairs(item.children) do immediate_set[child] = true end
      local filtered = {}
      for _, child in ipairs(item.children) do
        local nested_descendant = false
        for nested_parent in pairs(immediate_set) do
          if nested_parent ~= item.parent
              and nested_children_by_parent[nested_parent]
              and nested_children_by_parent[nested_parent][child] then
            nested_descendant = true
            break
          end
        end
        if not nested_descendant then filtered[#filtered + 1] = child end
      end
      item.children = filtered
      item.seen = nil
    end
    return wanted
  end

  for i, action in ipairs((type(plan) == "table" and plan.actions) or {}) do
    local path = "$.actions[" .. tostring(i) .. "]"
    local op = tostring(action.op or "")
    op_counts[op] = (op_counts[op] or 0) + 1
    if (action.op == "track.create" or action.op == "track.ensure")
       and action.id then
      tracks[action.id] = action.name or action.id
      track_order[#track_order + 1] = action.name or action.id
      local planned_name = normalized_name(action.name)
      if planned_name ~= "" then
        planned_track_id_by_name[planned_name] = action.id
      end
      if (requests_track_creation or action.op == "track.create")
         and not _typed_action_is_nonempty_string(action.name)
         and user_mentions_name(action.id) then
        errors[#errors + 1] = _typed_action_error(
          "missing_requested_track_name", path .. ".name",
          "The user named this new track; put the requested display name "
            .. "directly in track.create.name instead of name:null")
      end
      if requests_stock_fx
         and is_fx_like_track_name(action.name)
         and not user_mentions_name(action.name) then
        errors[#errors + 1] = _typed_action_error(
          "fx_as_track", path .. ".name",
          tostring(action.name) .. " looks like an effect track, but the user "
            .. "asked for stock FX; use fx.add_stock on the intended track")
      end
    elseif action.op == "track.resolve" and action.id then
      local resolve_name = normalized_name(action.name)
      local planned_id = resolve_name ~= ""
        and planned_track_id_by_name[resolve_name] or nil
      if planned_id and planned_id ~= action.id then
        errors[#errors + 1] = _typed_action_error(
          "resolve_after_planned_track", path,
          "track.resolve is only for tracks that existed before this plan. "
            .. "Use the planned track id " .. tostring(planned_id)
            .. " instead of resolving " .. tostring(action.name)
            .. " under a second id")
      end
      local selected_track_count = tonumber(opts.selected_track_count)
      if action.selected == true and selected_track_count
          and selected_track_count ~= 1 then
        errors[#errors + 1] = _typed_action_error(
          "ambiguous_selected_track", path .. ".selected",
          "selected:true requires exactly one selected track, but the project "
            .. "currently has " .. tostring(selected_track_count)
            .. "; resolve each target by exact name or distinct selected_index")
      end
      if positional_selector_forbidden
         and type(action.selected_index) == "number" then
        errors[#errors + 1] = _typed_action_error(
          "forbidden_selected_index", path .. ".selected_index",
          "User explicitly said not to use selected_index; use the requested "
            .. "non-positional selector instead")
      end
      if positional_selector_forbidden
         and type(action.index) == "number" then
        errors[#errors + 1] = _typed_action_error(
          "forbidden_track_index", path .. ".index",
          "User explicitly said not to use absolute track indexes; use the "
            .. "requested non-positional selector instead")
      end
      if requests_track_creation
         and not selected_target_requested
         and not mixed_existing_track_request
         and (action.selected == true
           or type(action.selected_index) == "number"
           or type(action.index) == "number") then
        errors[#errors + 1] = _typed_action_error(
          "unexpected_track_resolve_target", path,
          "User requested creating tracks in a blank/project template; do not "
            .. "target selected or indexed existing tracks")
      end
      if requests_stock_fx
         and is_fx_like_track_name(action.id)
         and not _typed_action_is_nonempty_string(action.name) then
        errors[#errors + 1] = _typed_action_error(
          "track_resolve_used_for_fx", path,
          "Do not create FX ids with track.resolve. Use fx.add_stock with this "
            .. "id on the intended track, then use fx.set_param if needed")
      end
      if _typed_action_is_nonempty_string(action.name) then
        tracks[action.id] = action.name
      elseif type(action.index) == "number" then
        tracks[action.id] = "track " .. tostring(action.index)
      elseif type(action.selected_index) == "number" then
        any_selected_index_resolve = true
        seen_selected_indexes[action.selected_index] = true
        tracks[action.id] = "selected track " .. tostring(action.selected_index)
      elseif action.selected == true then
        tracks[action.id] = "selected track"
      else
        tracks[action.id] = action.id
      end
    elseif action.op == "track.set" then
      if action.pan_pct ~= nil and action.track ~= nil then
        static_pan_targets[tostring(action.track)] = true
      end
      if action.master_send ~= nil and not requests_master_send_state then
        local track_name = tracks[action.track] or action.track
        errors[#errors + 1] = _typed_action_error(
          "unrequested_master_send_action", path .. ".master_send",
          "User did not explicitly request master/parent send state for "
            .. tostring(track_name)
            .. "; leave master_send null and use send.create for routing")
      end
      if action.master_send == false then
        master_send_off_seen = true
      end
    elseif action.op == "track.pan_lfo" then
      if not requests_pan_lfo then
        errors[#errors + 1] = _typed_action_error(
          "unexpected_pan_lfo_action", path,
          "User did not request track pan LFO/automation; do not emit "
            .. "track.pan_lfo actions")
      end
    elseif action.op == "fx.add_stock" then
      local track_id = action.track
      local track_name = tracks[track_id] or track_id
      local fx = tostring(action.fx or "")
      if _typed_action_is_nonempty_string(action.id) then
        fx_type_by_id[action.id] = fx
      end
      local track_key = tostring(track_id or "")
      fx_seen_by_track[track_key] = fx_seen_by_track[track_key] or {}
      fx_by_track[track_key] = fx_by_track[track_key] or {}
      fx_by_track[track_key][fx] = true
      if fx_seen_by_track[track_key][fx] and not allow_duplicate_fx then
        errors[#errors + 1] = _typed_action_error(
          "duplicate_track_fx", path .. ".fx",
          "Duplicate " .. fx .. " on " .. tostring(track_name)
            .. "; add each requested source-chain FX once per track")
      end
      fx_seen_by_track[track_key][fx] = true

      if name_has(track_name, "verb") and fx ~= "ReaVerbate" then
        errors[#errors + 1] = _typed_action_error(
          "return_fx_mismatch", path .. ".fx",
          tostring(track_name) .. " is a reverb return; use ReaVerbate only "
            .. "unless the user asks for more")
      elseif name_has(track_name, "delay") and fx ~= "ReaDelay" then
        errors[#errors + 1] = _typed_action_error(
          "return_fx_mismatch", path .. ".fx",
          tostring(track_name) .. " is a delay return; use ReaDelay only "
            .. "unless the user asks for more")
      end
    elseif action.op == "send.create" then
      local src_name = tracks[action["from"]] or action["from"]
      local dst_name = tracks[action.to] or action.to
      local volume_db = tonumber(action.volume_db)
      local route_key = send_route_key(src_name, dst_name)
      if route_key then send_seen_by_names[route_key] = true end
      if exact_send_graph_requested
         and is_aux_like_name(src_name)
         and is_bus_name(dst_name)
         and not explicit_send_requested(src_name, dst_name) then
        errors[#errors + 1] = _typed_action_error(
          "extra_inferred_return_bus_send", path,
          tostring(src_name) .. " -> " .. tostring(dst_name)
            .. " was not explicitly requested; exact routing graphs must not "
            .. "invent return/parallel-track sends")
      end
      if is_bus_name(dst_name)
         and not is_return_name(src_name)
         and volume_db ~= nil
         and math.abs(volume_db) > 0.7
         and not user_mentions_db_value(volume_db) then
        errors[#errors + 1] = _typed_action_error(
          "bus_send_not_unity", path .. ".volume_db",
          tostring(src_name) .. " -> " .. tostring(dst_name)
            .. " is bus routing and should use volume_db 0 unless the user "
            .. "asks for a different bus level")
      end
    elseif action.op == "fx.set_param" and type(action.params) == "table" then
      for param, value in pairs(action.params) do
        if value ~= nil and not user_mentions_param(param, value, action.params) then
          errors[#errors + 1] = _typed_action_error(
            "unrequested_param_action", path .. ".params." .. tostring(param),
            "User did not request " .. tostring(fx_type_by_id[action.fx] or "FX")
              .. "." .. tostring(param) .. "; do not emit extra parameter writes")
        end
      end
    elseif action.op == "track.folder" then
      local children = {}
      if type(action.children) == "table" then
        for _, child in ipairs(action.children) do
          children[#children + 1] = child
        end
      end
      folder_children_by_parent[action.parent] = children
    end
  end

  if selected_index_required then
    if #required_selected_indexes == 0 then
      if not any_selected_index_resolve then
        errors[#errors + 1] = _typed_action_error(
          "missing_selected_index", "$.actions",
          "User explicitly requested selected_index targeting; use "
            .. "track.resolve with selected_index and do not substitute name, "
            .. "index, or selected:true")
      end
    else
      for _, selected_index in ipairs(required_selected_indexes) do
        if not seen_selected_indexes[selected_index] then
          errors[#errors + 1] = _typed_action_error(
            "missing_selected_index", "$.actions",
            "User requested selected track " .. tostring(selected_index)
              .. "; use track.resolve with selected_index="
              .. tostring(selected_index)
              .. " and do not substitute name, index, or selected:true")
        end
      end
    end
  end

  local track_creation_count = (op_counts["track.create"] or 0)
    + (op_counts["track.ensure"] or 0)
  if requests_track_creation and track_creation_count == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_track_create_actions", "$.actions",
      "User requested creating tracks or a blank-project template; use "
        .. "track.create for the requested new tracks, not track.resolve")
  end
  if existing_target_only and track_creation_count > 0 then
    errors[#errors + 1] = _typed_action_error(
      "unexpected_track_create_existing_target", "$.actions",
      "User requested existing-track targets; use track.resolve for those "
        .. "tracks and do not create replacement tracks")
  end
  if requests_stock_fx and (op_counts["fx.add_stock"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_fx_actions", "$.actions",
      "User requested supported stock FX; the typed-action plan must include "
        .. "fx.add_stock actions, not only track creation actions")
  end
  if requests_params and (op_counts["fx.set_param"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_param_actions", "$.actions",
      "User requested FX parameter settings; the typed-action plan must include "
        .. "fx.set_param actions")
  end
  if requests_sends and (op_counts["send.create"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_send_actions", "$.actions",
      "User requested routing/sends; the typed-action plan must include "
        .. "send.create actions")
  end
  if requests_sends then
    local checked_routes = {}
    for src_id, src_name in pairs(tracks) do
      for dst_id, dst_name in pairs(tracks) do
        if src_id ~= dst_id and explicit_send_required(src_name, dst_name) then
          local route_key = send_route_key(src_name, dst_name)
          if route_key and not checked_routes[route_key] then
            checked_routes[route_key] = true
            if not send_seen_by_names[route_key] then
              errors[#errors + 1] = _typed_action_error(
                "missing_send_actions", "$.actions",
                "User explicitly requested a send from "
                  .. tostring(src_name) .. " to " .. tostring(dst_name)
                  .. "; include one send.create action with from="
                  .. tostring(src_id) .. " and to=" .. tostring(dst_id))
            end
          end
        end
      end
    end
  end
  if predicate_track_property_request then
    errors[#errors + 1] = _typed_action_error(
      "incomplete_multi_target_plan", "$.actions",
      "Conditional or predicate-based track property requests cannot be "
        .. "represented safely as a fixed typed-action plan; use Lua instead")
  end
  local static_pan_target_count = 0
  for _ in pairs(static_pan_targets) do
    static_pan_target_count = static_pan_target_count + 1
  end
  if requests_track_properties
      and conflicting_static_pan
      and not requests_pan_lfo
      and static_pan_target_count <= 1 then
    errors[#errors + 1] = _typed_action_error(
      "ambiguous_property_value", "$.actions",
      "User requested conflicting static pan directions or values; do not "
        .. "choose one value or execute a partial typed-action plan")
  end
  if requests_pan_lfo and (op_counts["track.pan_lfo"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_pan_lfo_action", "$.actions",
      "User requested track pan LFO/automation over bars; the typed-action "
        .. "plan must include track.pan_lfo actions")
  end
  local function pan_lfo_request_still_needs_track_set()
    if not requests_track_properties then return false end
    if not requests_pan_lfo then return true end
    local t = track_property_text
    local non_lfo_property =
      t:find("volume", 1, true) ~= nil
      or t:find("fader", 1, true) ~= nil
      or t:find("mute", 1, true) ~= nil
      or t:find("muted", 1, true) ~= nil
      or t:find("unmute", 1, true) ~= nil
      or t:find("solo", 1, true) ~= nil
      or t:find("soloed", 1, true) ~= nil
      or t:find("unsolo", 1, true) ~= nil
      or requests_master_send_state
      or t:find("rename", 1, true) ~= nil
      or t:find("renamed", 1, true) ~= nil
      or t:find("call ", 1, true) ~= nil
      or t:find("called", 1, true) ~= nil
    if non_lfo_property then return true end
    return t:find("set%s+[^%.\n]*pan%s+to") ~= nil
      or t:find("pan%s+to%s*[%+%-]?%d") ~= nil
      or t:find("pan%s*[%+%-]%d") ~= nil
      or t:find("panned%s+[^%.\n]*to") ~= nil
  end
  if pan_lfo_request_still_needs_track_set()
      and (op_counts["track.set"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_track_set_actions", "$.actions",
      "User requested track rename/name, volume, pan, mute, unmute, solo, unsolo, or "
        .. "master/parent send state; the typed-action plan must include "
        .. "track.set actions")
  end
  if requests_master_send_off and not master_send_off_seen then
    errors[#errors + 1] = _typed_action_error(
      "missing_master_send_off_action", "$.actions",
      "User requested a track/bus not feed the master; include a track.set "
        .. "action with master_send=false on the requested track id")
  end
  if requests_record_ready_state then
    errors[#errors + 1] = _typed_action_error(
      "unsupported_record_arm_typed_action", "$.actions",
      "User requested a track ready for recording/record arm, but the "
        .. "typed-action schema cannot arm tracks yet; use Lua instead of "
        .. "executing an incomplete typed-action plan")
  end
  if requests_folders and (op_counts["track.folder"] or 0) == 0 then
    errors[#errors + 1] = _typed_action_error(
      "missing_folder_actions", "$.actions",
      "User requested a track folder; the typed-action plan must include "
        .. "track.folder actions")
  end
  if not requests_folders and (op_counts["track.folder"] or 0) > 0 then
    errors[#errors + 1] = _typed_action_error(
      "unexpected_folder_actions", "$.actions",
      "User did not request a track folder; do not emit track.folder actions")
  end
  if not requests_track_properties and (op_counts["track.set"] or 0) > 0 then
    errors[#errors + 1] = _typed_action_error(
      "unexpected_track_set_actions", "$.actions",
      "User did not request track rename/name, volume, pan, mute, unmute, solo, unsolo, or "
        .. "master/parent send state; do not emit track.set actions")
  end
  if not requests_pan_lfo and (op_counts["track.pan_lfo"] or 0) > 0 then
    errors[#errors + 1] = _typed_action_error(
      "unexpected_pan_lfo_action", "$.actions",
      "User did not request track pan LFO/automation; do not emit "
        .. "track.pan_lfo actions")
  end

  local requested_order = requested_exact_track_order(opts.user_text)
  if requested_order then
    if exact_send_graph_requested and #track_order > #requested_order then
      errors[#errors + 1] = _typed_action_error(
        "unexpected_track_ensure_actions", "$.actions",
        "User requested an exact track order with "
          .. tostring(#requested_order)
          .. " tracks, but the plan creates "
          .. tostring(#track_order)
          .. "; do not create extra tracks for FX, folders, or helper ids")
    end
    for i, want in ipairs(requested_order) do
      local got = normalized_name(track_order[i])
      if got ~= want then
        errors[#errors + 1] = _typed_action_error(
          "track_order_mismatch", "$.actions",
          "User requested exact track order; expected track "
            .. tostring(i) .. " to be " .. tostring(want)
            .. ", got " .. tostring(track_order[i] or "missing"))
        break
      end
    end
  end

  if requests_folders then
    local child_names_by_parent = {}
    for parent_id, child_ids in pairs(folder_children_by_parent) do
      local parent_name = normalized_name(tracks[parent_id] or parent_id)
      child_names_by_parent[parent_name] = child_names_by_parent[parent_name] or {}
      for _, child_id in ipairs(child_ids) do
        child_names_by_parent[parent_name][normalized_name(tracks[child_id] or child_id)] = true
      end
    end
    for _, want in ipairs(requested_folder_memberships(opts.user_text)) do
      local got = child_names_by_parent[want.parent] or {}
      for _, child_name in ipairs(want.children) do
        if not got[child_name] then
          errors[#errors + 1] = _typed_action_error(
            "missing_folder_child", "$.actions",
            "User requested " .. tostring(want.parent)
              .. " to contain " .. tostring(child_name)
              .. "; include that id in the parent track.folder children list")
        end
      end
    end
  end

  local repeated_source_chain_requested =
    (u_words:find("reaeq first and reacomp second", 1, true) ~= nil)
    or (u_words:find("reaeq first", 1, true) ~= nil
      and u_words:find("reacomp second", 1, true) ~= nil)
    or (u_words:find("reacomp first and reaeq second", 1, true) ~= nil)
    or (u_words:find("reacomp first", 1, true) ~= nil
      and u_words:find("reaeq second", 1, true) ~= nil)
    or (u_words:find("reaeq followed by reacomp", 1, true) ~= nil)
    or (u_words:find("reacomp followed by reaeq", 1, true) ~= nil)
    or (u_words:find("reaeq then reacomp", 1, true) ~= nil)
    or (u_words:find("reacomp then reaeq", 1, true) ~= nil)
    or (u_words:find("reaeq and reacomp to", 1, true) ~= nil)
    or (u_words:find("reaeq and reacomp on", 1, true) ~= nil)
    or (u_words:find("reacomp and reaeq to", 1, true) ~= nil)
    or (u_words:find("reacomp and reaeq on", 1, true) ~= nil)
  if repeated_source_chain_requested then
    for track_id, name in pairs(tracks) do
      if not is_bus_name(name)
         and not is_return_name(name)
         and not is_aux_like_name(name) then
        local fx = fx_by_track[tostring(track_id)] or {}
        if fx.ReaComp and not fx.ReaEQ then
          errors[#errors + 1] = _typed_action_error(
            "incomplete_source_fx_chain", "$.actions",
            tostring(name) .. " has ReaComp but is missing ReaEQ; source "
              .. "tracks in this repeated chain need both requested FX")
        end
      end
    end
  end

  if exact_send_graph_requested and requests_stock_fx then
    local requested_fx_by_track = {}
    for sentence in tostring(opts.user_text or ""):gmatch("[^%.%!%?]+") do
      local sw = word_text(sentence)
      if sw ~= "" then
        local sentence_fx = {}
        for fx_name in pairs(_TYPED_ACTION_STOCK_FX) do
          if sw:find(word_text(fx_name), 1, true) then
            sentence_fx[fx_name] = true
          end
        end
        if next(sentence_fx) then
          local broad =
            sw:find("all tracks", 1, true) ~= nil
            or sw:find("every track", 1, true) ~= nil
            or sw:find("each track", 1, true) ~= nil
          for track_id, name in pairs(tracks) do
            if broad or sw:find(word_text(name), 1, true) then
              requested_fx_by_track[track_id] =
                requested_fx_by_track[track_id] or {}
              for fx_name in pairs(sentence_fx) do
                requested_fx_by_track[track_id][fx_name] = true
              end
            end
          end
        end
      end
    end
    for track_id, fx_set in pairs(fx_by_track) do
      local requested = requested_fx_by_track[track_id]
      if requested then
        local track_name = tracks[track_id] or track_id
        for fx_name in pairs(fx_set) do
          if not requested[fx_name] then
            errors[#errors + 1] = _typed_action_error(
              "unexpected_track_fx", "$.actions",
              tostring(track_name) .. " has " .. tostring(fx_name)
                .. ", but the user did not request that stock FX for this "
                .. "track; keep exact graph FX assignments separate")
          end
        end
      end
    end
  end

  errors = _typed_action_filter_semantic_errors_for_profile(errors, profile)
  return #errors == 0, (#errors > 0 and errors or nil)
end

function Code.format_typed_action_semantic_errors(errors, limit)
  if type(errors) ~= "table" or #errors == 0 then return "semantic_mismatch" end
  limit = tonumber(limit) or 3
  local parts = {}
  for i = 1, math.min(#errors, limit) do
    local e = errors[i]
    parts[#parts + 1] = tostring(e.code or "semantic_mismatch")
      .. " at " .. tostring(e.path or "$")
      .. ": " .. tostring(e.message or "")
  end
  if #errors > limit then
    parts[#parts + 1] = tostring(#errors - limit) .. " more"
  end
  return table.concat(parts, "; ")
end

function Code.typed_action_semantic_detail_missing_action_family(detail)
  detail = tostring(detail or "")
  return detail:find("missing_fx_actions", 1, true) ~= nil
    or detail:find("missing_param_actions", 1, true) ~= nil
    or detail:find("missing_send_actions", 1, true) ~= nil
end

function Code.typed_action_semantic_detail_allows_lua_fallback(detail, user_text)
  detail = tostring(detail or "")
  if Code.typed_action_semantic_detail_missing_action_family(detail) then
    return true
  end
  if not detail:find("unexpected_track_set_actions", 1, true) then
    return false
  end
  if not Code.prompt_likely_needs_lua_action(user_text) then return false end
  local text = Code._typed_action_track_property_intent_text(user_text)
  local words = " " .. text:gsub("[^%w]+", " "):gsub("%s+", " ") .. " "
  local has_target =
    words:find(" track ", 1, true) ~= nil
    or words:find(" tracks ", 1, true) ~= nil
    or words:find(" bus ", 1, true) ~= nil
    or words:find(" selected ", 1, true) ~= nil
  local has_property = false
  for _, term in ipairs({
    "volume", "vol", "fader", "level", "pan", "mute", "muted",
    "unmute", "solo", "soloed", "unsolo", "rename", "renamed",
  }) do
    if words:find(" " .. term .. " ", 1, true) then
      has_property = true
      break
    end
  end
  return has_target and has_property
end

function Code.typed_action_semantic_retry_from_scratch(profile, detail)
  detail = tostring(detail or "")
  if type(profile) == "table"
     and profile.semantic_retry_from_scratch == false then
    return false
  end
  if type(profile) == "table"
     and profile.semantic_retry_from_scratch == true then
    return true
  end
  if detail:find("unexpected_track_create_existing_target", 1, true)
     or detail:find("unexpected_track_ensure_existing_target", 1, true) then
    return true
  end
  if Code.typed_action_semantic_detail_missing_action_family(detail)
     and type(S) == "table"
     and (S.typed_action_escalation_used == true
       or (tonumber(S.typed_action_escalation_count or 0) or 0) > 0) then
    return true
  end
  return false
end

function Code._typed_action_schema_retry_detail(text, opts)
  opts = type(opts) == "table" and opts or {}
  local plan, plan_errors = Code.typed_actions_plan_from_text(text, {
    allow_raw_json = opts.allow_raw_json == true,
  })
  local detail = nil
  if plan then
    local valid, validate_errors = Code.validate_typed_actions_plan(plan)
    if not valid then
      detail = Code.format_typed_action_semantic_errors(validate_errors, 4)
    end
  else
    detail = Code.format_typed_action_semantic_errors(plan_errors, 4)
  end

  local u = tostring(opts.user_text or ""):lower()
  local track_property_text = u
    :gsub("post%-fader", "")
    :gsub("post fader", "")
    :gsub("pre%-fader", "")
    :gsub("pre fader", "")
    :gsub("do not rename", "")
    :gsub("don't rename", "")
    :gsub("without renaming", "")
    :gsub("rename any tracks", "")
    :gsub("rename any track", "")
    :gsub("no rename", "")
    :gsub("not rename", "")
  local requests_track_properties =
    (track_property_text:find("volume", 1, true) ~= nil
      or track_property_text:find("fader", 1, true) ~= nil
      or track_property_text:find("pan", 1, true) ~= nil
      or track_property_text:find("panned", 1, true) ~= nil
      or track_property_text:find("mute", 1, true) ~= nil
      or track_property_text:find("muted", 1, true) ~= nil
      or track_property_text:find("unmute", 1, true) ~= nil
      or track_property_text:find("solo", 1, true) ~= nil
      or track_property_text:find("soloed", 1, true) ~= nil
      or track_property_text:find("unsolo", 1, true) ~= nil
      or track_property_text:find("master send", 1, true) ~= nil
      or track_property_text:find("main send", 1, true) ~= nil
      or track_property_text:find("master/parent", 1, true) ~= nil
      or track_property_text:find("master parent", 1, true) ~= nil
      or track_property_text:find("parent send", 1, true) ~= nil
      or track_property_text:find("master output", 1, true) ~= nil
      or track_property_text:find("rename", 1, true) ~= nil
      or track_property_text:find("renamed", 1, true) ~= nil
      or track_property_text:find("call ", 1, true) ~= nil
      or track_property_text:find("called", 1, true) ~= nil
      or Code._typed_action_user_requests_track_level_change(user_text))
  if plan and requests_track_properties then
    local counts = _typed_action_count_ops(plan)
    if (counts["track.resolve"] or 0) > 0
       and (counts["track.set"] or 0) == 0 then
      local hint = "User requested track property changes; keep one valid "
        .. "track.resolve for the target, then add one track.set using that "
        .. "same id"
      detail = detail and detail ~= "" and (detail .. "; " .. hint) or hint
    end
  end
  return detail and detail ~= "" and detail or "invalid_plan"
end

local function _typed_action_executor_validate(plan)
  local valid, errors = Code.validate_typed_actions_plan(plan)
  if not valid then return false, errors end

  local fx_type_by_id, exec_errors = {}, {}
  for i, action in ipairs(plan.actions or {}) do
    local path = "$.actions[" .. tostring(i) .. "]"
    if action.op == "fx.add_stock" and action.id and action.fx then
      fx_type_by_id[action.id] = action.fx
    elseif action.op == "fx.set_param" then
      local fx_name = fx_type_by_id[action.fx]
      local setters, perr = _typed_action_param_setters(
        fx_name, action.params, path)
      if not setters then
        for _, e in ipairs(perr or {}) do exec_errors[#exec_errors+1] = e end
      end
    elseif action.op == "send.create" and action.mode ~= nil
       and type(action.mode) == "string" then
      local m = tostring(action.mode):lower():gsub("%s+", "_"):gsub("%-", "_")
      local ok_mode = m == "post_fader"
        or m == "post_fader_post_pan"
        or m == "pre_fx"
        or m == "pre_fader"
        or m == "post_fx"
      if not ok_mode then
        exec_errors[#exec_errors+1] = _typed_action_error(
          "unsupported_send_mode", path .. ".mode",
          "Unsupported send mode: " .. tostring(action.mode))
      end
    end
  end
  return #exec_errors == 0, exec_errors
end

local function _typed_action_find_existing_track(api, name)
  local found = {}
  local n = api.CountTracks(0)
  for i = 0, n - 1 do
    local tr = api.GetTrack(0, i)
    local _, tname = api.GetTrackName(tr, "")
    if tname == name then found[#found+1] = tr end
  end
  return found
end

function Code._typed_action_resolve_existing_track(api, action)
  if action.selected_index ~= nil then
    if type(api.CountSelectedTracks) ~= "function"
       or type(api.GetSelectedTrack) ~= "function" then
      return nil, "selected_track_unavailable",
        "REAPER selected-track APIs are unavailable"
    end
    local idx = tonumber(action.selected_index)
    local count = api.CountSelectedTracks(0)
    if not idx or idx % 1 ~= 0 or idx < 1 or idx > count then
      return nil, "missing_selected_track",
        "No selected track at 1-based selected index "
          .. tostring(action.selected_index) .. "; found "
          .. tostring(count or 0)
    end
    local tr = api.GetSelectedTrack(0, idx - 1)
    if not tr then
      return nil, "missing_selected_track",
        "Could not resolve selected track index "
          .. tostring(action.selected_index)
    end
    return tr
  end

  if action.selected == true then
    if type(api.CountSelectedTracks) ~= "function"
       or type(api.GetSelectedTrack) ~= "function" then
      return nil, "selected_track_unavailable",
        "REAPER selected-track APIs are unavailable"
    end
    local count = api.CountSelectedTracks(0)
    if count ~= 1 then
      return nil, "ambiguous_selected_track",
        "track.resolve selected requires exactly one selected track; found "
          .. tostring(count or 0)
    end
    local tr = api.GetSelectedTrack(0, 0)
    if not tr then
      return nil, "missing_selected_track",
        "Could not resolve the selected track"
    end
    return tr
  end

  if action.index ~= nil then
    local idx = tonumber(action.index)
    local count = api.CountTracks(0)
    if not idx or idx % 1 ~= 0 or idx < 1 or idx > count then
      return nil, "missing_track",
        "No existing track at 1-based index " .. tostring(action.index)
    end
    local tr = api.GetTrack(0, idx - 1)
    if not tr then
      return nil, "missing_track",
        "Could not resolve track index " .. tostring(action.index)
    end
    if action.name ~= nil then
      local _, tname = api.GetTrackName(tr, "")
      if tname ~= action.name then
        return nil, "track_name_mismatch",
          "Track index " .. tostring(action.index) .. " is named "
            .. tostring(tname) .. ", not " .. tostring(action.name)
      end
    end
    return tr
  end

  if action.name ~= nil then
    local found = _typed_action_find_existing_track(api, action.name)
    if #found == 0 then
      return nil, "missing_track",
        "No existing track is named " .. tostring(action.name)
    end
    if #found > 1 then
      return nil, "ambiguous_track",
        "Multiple existing tracks are named " .. tostring(action.name)
    end
    return found[1]
  end

  return nil, "invalid_target_selector",
    "track.resolve needs name, selected, selected_index, or index"
end

local function _typed_action_track_insert_index(api, action, tracks)
  local count = api.CountTracks(0)
  local pos = action.position
  if not pos or pos == "" or pos == "end" then return count end
  local dir, ref = pos:match("^(after):(.-)$")
  if not dir then dir, ref = pos:match("^(before):(.-)$") end
  local ref_tr = ref and tracks[ref] or nil
  if not ref_tr then return nil, "Unknown position reference: " .. tostring(pos) end
  local ref_num = api.GetMediaTrackInfo_Value(ref_tr, "IP_TRACKNUMBER")
  if not ref_num or ref_num < 1 then
    return nil, "Could not resolve position reference: " .. tostring(pos)
  end
  if dir == "before" then return math.max(0, ref_num - 1) end
  return math.min(count, ref_num)
end

local function _typed_action_send_mode(mode)
  if mode == nil then return nil, nil end
  if type(mode) == "number" then return mode, nil end
  local m = tostring(mode):lower():gsub("%s+", "_"):gsub("%-", "_")
  local map = {
    post_fader = 0,
    post_fader_post_pan = 0,
    pre_fx = 1,
    pre_fader = 3,
    post_fx = 3,
  }
  if map[m] == nil then return nil, "Unsupported send mode: " .. tostring(mode) end
  return map[m], nil
end

function Code._typed_action_pan_lfo_resolution_steps(resolution)
  local r = tostring(resolution or "32nd"):lower()
    :gsub("%s+", "")
    :gsub("%-", "")
  if r == "" or r == "null" then r = "32nd" end
  if r == "eighth" or r == "8th" then return 8 end
  if r == "16th" then return 16 end
  if r == "64th" then return 64 end
  return 32
end

function Code._typed_action_pan_lfo_start(api, start)
  local st = tostring(start or "cursor"):lower():gsub("%s+", "_"):gsub("%-", "_")
  if st == "project_start" then return 0 end
  if type(api.GetCursorPosition) == "function" then
    local ok, pos = pcall(api.GetCursorPosition)
    if ok and tonumber(pos) then return tonumber(pos) end
  end
  return 0
end

function Code._typed_action_project_bpm_bpi(api, t)
  local bpm, bpi = 120, 4
  if type(api.GetProjectTimeSignature2) == "function" then
    local ok, got_bpm, got_bpi = pcall(api.GetProjectTimeSignature2, 0)
    if ok and tonumber(got_bpm) and tonumber(got_bpm) > 0 then
      bpm = tonumber(got_bpm)
    end
    if ok and tonumber(got_bpi) and tonumber(got_bpi) > 0 then
      bpi = tonumber(got_bpi)
    end
  elseif type(api.Master_GetTempo) == "function" then
    local ok, got_bpm = pcall(api.Master_GetTempo)
    if ok and tonumber(got_bpm) and tonumber(got_bpm) > 0 then
      bpm = tonumber(got_bpm)
    end
  end
  if type(api.TimeMap_GetDividedBpmAtTime) == "function" then
    local ok, got_bpm = pcall(api.TimeMap_GetDividedBpmAtTime, t or 0)
    if ok and tonumber(got_bpm) and tonumber(got_bpm) > 0 then
      bpm = tonumber(got_bpm)
    end
  end
  return bpm, bpi
end

function Code._typed_action_pan_lfo_finish(api, start, bars)
  bars = tonumber(bars)
  if not bars or bars <= 0 then return nil end
  if type(api.TimeMap2_timeToBeats) == "function"
      and type(api.TimeMap2_beatsToTime) == "function" then
    local ok1, beat, measure = pcall(api.TimeMap2_timeToBeats, 0, start)
    if ok1 and tonumber(beat) and tonumber(measure) then
      local target_beat = tonumber(beat)
      local target_measure = tonumber(measure)
      if bars % 1 == 0 then
        target_measure = target_measure + bars
      else
        local _, bpi = Code._typed_action_project_bpm_bpi(api, start)
        target_beat = target_beat + bars * bpi
      end
      local ok2, finish = pcall(api.TimeMap2_beatsToTime, 0,
        target_beat, target_measure)
      if ok2 and tonumber(finish) and tonumber(finish) > start then
        return tonumber(finish)
      end
    end
  end
  local bpm, bpi = Code._typed_action_project_bpm_bpi(api, start)
  return start + (60 / bpm) * bpi * bars
end

function Code._typed_action_track_pan_envelope(api, tr)
  local env = nil
  if type(api.GetTrackEnvelopeByName) == "function" then
    for _, name in ipairs({
      "Pan",
      "Pan (Left)",
      "Pan (L)",
      "Pan L",
      "Left Pan",
      "Pan (Right)",
      "Pan (R)",
      "Pan R",
      "Right Pan",
    }) do
      local ok, got = pcall(api.GetTrackEnvelopeByName, tr, name)
      if ok and got then return got end
    end
  end
  if type(api.GetTrackEnvelopeByChunkName) == "function" then
    for _, chunk_name in ipairs({ "<PANENV", "<PANENV2" }) do
      local ok, got = pcall(api.GetTrackEnvelopeByChunkName, tr, chunk_name)
      if ok and got then return got end
    end
  end
  return env
end

function Code._typed_action_apply_track_pan_lfo(api, tr, action)
  if type(api.InsertEnvelopePoint) ~= "function"
      or type(api.Envelope_SortPoints) ~= "function" then
    return false, "envelope_api_unavailable",
      "REAPER envelope point APIs are unavailable"
  end
  local env = Code._typed_action_track_pan_envelope(api, tr)
  if not env then
    return false, "pan_envelope_unavailable",
      "Could not access the target track Pan envelope"
  end
  local start = Code._typed_action_pan_lfo_start(api, action.start)
  local finish = Code._typed_action_pan_lfo_finish(api, start, action.bars)
  if not finish or finish <= start then
    return false, "invalid_pan_lfo_span",
      "Could not compute a positive pan LFO time span"
  end
  local steps_per_bar =
    Code._typed_action_pan_lfo_resolution_steps(action.resolution)
  local steps = math.max(2,
    math.ceil((tonumber(action.bars) or 0) * steps_per_bar))
  if steps > 8192 then
    return false, "pan_lfo_too_dense",
      "track.pan_lfo would write too many envelope points"
  end
  local depth = tonumber(action.depth_pct)
  if not depth then depth = 100 end
  depth = math.max(0.001, math.min(100, depth)) / 100
  local cycles = (tonumber(action.cycles_per_bar) or 1)
    * (tonumber(action.bars) or 1)
  local mode = 0
  if type(api.GetEnvelopeScalingMode) == "function" then
    local ok, got = pcall(api.GetEnvelopeScalingMode, env)
    if ok and tonumber(got) then mode = tonumber(got) end
  end
  if action.clear_existing ~= false then
    if type(api.DeleteEnvelopePointRange) ~= "function" then
      return false, "envelope_clear_unavailable",
        "REAPER envelope delete API is unavailable"
    end
    api.DeleteEnvelopePointRange(env, start, finish)
  end
  for i = 0, steps do
    local frac = i / steps
    local t = start + (finish - start) * frac
    local pan = math.sin(frac * cycles * 2 * math.pi) * depth
    local value = pan
    if type(api.ScaleToEnvelopeMode) == "function" then
      value = api.ScaleToEnvelopeMode(mode, pan)
    end
    api.InsertEnvelopePoint(env, t, value, 0, 0, false, true)
  end
  api.Envelope_SortPoints(env)
  return true, nil, nil, steps + 1
end

function Code._typed_action_error_result(code, path, message, result)
  return false, {
    code = code or "execution_error",
    path = path or "$",
    message = message or "Structured edit failed",
    result = result,
  }
end

function Code.typed_actions_user_failure_message(exec_result)
  local code = exec_result and exec_result.code or "execution_failed"
  local detail = exec_result and exec_result.message or nil
  local result = exec_result and exec_result.result or nil
  local changed = type(result) == "table"
    and type(result.action_results) == "table"
    and #result.action_results > 0
  if code == "executor_disabled" then
    return Code.typed_actions_executor_disabled_message()
  end
  local function add_detail(msg)
    if detail and detail ~= "" then
      local fallback = "Details: " .. tostring(detail)
      msg = msg .. " " .. ((RA and RA.t and RA.t(
        "typed_actions.error.details", { detail = tostring(detail) },
        fallback)) or fallback)
    end
    return msg
  end
  if code == "invalid_json" or code == "missing_action_block"
     or code == "invalid_plan" or code == "semantic_mismatch" then
    local msg = (RA and RA.t and RA.t(
      "typed_actions.error.blocked_before_change", nil,
      "I blocked this structured edit before it changed the project because the plan did not match the request safely. No changes were made."))
      or "I blocked this structured edit before it changed the project because the plan did not match the request safely. No changes were made."
    return add_detail(msg)
  end
  if changed then
    local msg = (RA and RA.t and RA.t(
      "typed_actions.error.partial_failed", nil,
      "Structured edit failed after making part of the change. ReaAssist stopped immediately; use REAPER Undo if the project is not in the state you want."))
      or "Structured edit failed after making part of the change. ReaAssist stopped immediately; use REAPER Undo if the project is not in the state you want."
    return add_detail(msg)
  end
  local msg = (RA and RA.t and RA.t(
    "typed_actions.error.failed_before_change", nil,
    "Structured edit failed before it changed the project. No changes were made."))
    or "Structured edit failed before it changed the project. No changes were made."
  return add_detail(msg)
end

-- Fail-closed local executor for accepted typed-action plans. It opens one undo
-- block, applies actions in dependency order, and stops immediately on the first
-- validation or REAPER API failure.
function Code.execute_typed_actions_plan(plan, opts)
  opts = opts or {}
  local api = opts.reaper or reaper
  local result = {
    executed = false,
    completed = false,
    deferred = false,
    op_counts = _typed_action_count_ops(plan),
    action_results = {},
  }

  if not opts.allow_dev_executor and not Code.typed_actions_executor_enabled() then
    return Code._typed_action_error_result("executor_disabled", "$",
      Code.typed_actions_executor_disabled_message(), result)
  end

  if type(api) ~= "table" then
    return Code._typed_action_error_result("executor_unavailable", "$",
      "REAPER API table is unavailable", result)
  end

  local valid, validation_errors = _typed_action_executor_validate(plan)
  if not valid then
    result.validation_errors = validation_errors
    return Code._typed_action_error_result("invalid_plan", "$",
      "Typed action plan failed executor validation", result)
  end
  local folder_depth_plan, folder_depth_errors =
    Code._typed_action_folder_depth_plan(plan)
  if folder_depth_errors and #folder_depth_errors > 0 then
    result.validation_errors = folder_depth_errors
    return Code._typed_action_error_result("invalid_plan", "$",
      "Typed action folder plan failed executor validation", result)
  end

  local tracks, fx_by_id, param_actions = {}, {}, {}
  local undo_open, refresh_open = false, false

  local function close_block(label, flags)
    if refresh_open then
      pcall(api.PreventUIRefresh, -1)
      refresh_open = false
    end
    if type(api.TrackList_AdjustWindows) == "function" then
      pcall(api.TrackList_AdjustWindows, false)
    end
    if type(api.UpdateArrange) == "function" then pcall(api.UpdateArrange) end
    if undo_open then
      pcall(api.Undo_EndBlock, label or "ReaAssist: typed actions", flags or -1)
      undo_open = false
    end
  end

  local function fail(code, path, message)
    close_block("ReaAssist: typed actions failed", -1)
    local fallback = "Structured edit failed: " .. tostring(message)
    local msg = (RA and RA.t and RA.t("typed_actions.error.failed",
      { message = tostring(message) }, fallback)) or fallback
    if type(Log) == "table" and type(Log.add_error) == "function" then
      Log.add_error(msg)
    end
    if type(api.ShowMessageBox) == "function" then
      pcall(api.ShowMessageBox, msg, "ReaAssist", 0)
    end
    return Code._typed_action_error_result(code, path, message, result)
  end

  local function complete(ok, done_result)
    result.completed = true
    result.executed = ok == true
    if type(opts.on_done) == "function" then
      local cb_ok, cb_err = pcall(opts.on_done, ok == true,
        done_result or { result = result })
      if not cb_ok and type(Log) == "table"
         and type(Log.add_error) == "function" then
        local fallback = "Structured edit completion callback failed: "
          .. tostring(cb_err)
        Log.add_error((RA and RA.t and RA.t(
          "typed_actions.error.callback_failed",
          { error = tostring(cb_err) }, fallback)) or fallback)
      end
    end
  end

  local pre_resolved_tracks = {}
  for i, action in ipairs(plan.actions or {}) do
    if action.op == "track.resolve" then
      local path = "$.actions[" .. tostring(i) .. "]"
      local tr, code, err =
        Code._typed_action_resolve_existing_track(api, action)
      if not tr then
        return fail(code or "track_resolve_failed", path,
          err or ("Could not resolve track " .. tostring(action.id)))
      end
      pre_resolved_tracks[action.id] = tr
    end
  end

  api.Undo_BeginBlock()
  undo_open = true
  api.PreventUIRefresh(1)
  refresh_open = true

  for i, action in ipairs(plan.actions or {}) do
    local path = "$.actions[" .. tostring(i) .. "]"
    local op = action.op
    if op == "track.create" or op == "track.ensure" then
      local existing = op == "track.ensure"
        and _typed_action_find_existing_track(api, action.name) or {}
      local tr
      local created = false
      if #existing > 1 then
        return fail("ambiguous_track", path .. ".name",
          "Multiple existing tracks are named " .. tostring(action.name))
      elseif #existing == 1 then
        tr = existing[1]
      else
        local idx, pos_err = _typed_action_track_insert_index(api, action, tracks)
        if not idx then return fail("unknown_ref", path .. ".position", pos_err) end
        api.InsertTrackAtIndex(idx, true)
        tr = api.GetTrack(0, idx)
        if not tr then
          return fail("track_create_failed", path,
            "Could not create track " .. tostring(action.name))
        end
        created = true
      end
      if _typed_action_is_nonempty_string(action.name) then
        api.GetSetMediaTrackInfo_String(tr, "P_NAME", action.name, true)
      end
      if action.select == true then
        api.SetTrackSelected(tr, true)
      end
      tracks[action.id] = tr
      local result_name = action.name
      if (not _typed_action_is_nonempty_string(result_name))
         and type(api.GetTrackName) == "function" then
        local name_ok, display_name = api.GetTrackName(tr, "")
        if name_ok and _typed_action_is_nonempty_string(display_name) then
          result_name = display_name
        end
      end
      result.action_results[#result.action_results+1] = {
        op = op, id = action.id, name = result_name, created = created,
        selected = action.select == true or nil, status = "ok"
      }

    elseif op == "track.resolve" then
      local tr = pre_resolved_tracks[action.id]
      tracks[action.id] = tr
      result.action_results[#result.action_results+1] = {
        op = op, id = action.id, name = action.name, index = action.index,
        selected = action.selected == true or nil,
        selected_index = action.selected_index, status = "ok"
      }

    elseif op == "track.set" then
      local tr = tracks[action.track]
      if not tr then
        return fail("unknown_ref", path .. ".track",
          "Unknown track id " .. tostring(action.track))
      end
      if action.name ~= nil then
        api.GetSetMediaTrackInfo_String(tr, "P_NAME", action.name, true)
      end
      if action.volume_db ~= nil then
        api.SetMediaTrackInfo_Value(tr, "D_VOL",
          _typed_action_db_to_amp(action.volume_db))
      end
      if action.pan_pct ~= nil then
        api.SetMediaTrackInfo_Value(tr, "D_PAN", action.pan_pct / 100)
      end
      if action.mute ~= nil then
        api.SetMediaTrackInfo_Value(tr, "B_MUTE", action.mute and 1 or 0)
      end
      if action.solo ~= nil then
        api.SetMediaTrackInfo_Value(tr, "I_SOLO", action.solo and 1 or 0)
      end
      if action.master_send ~= nil then
        api.SetMediaTrackInfo_Value(tr, "B_MAINSEND",
          action.master_send and 1 or 0)
      end
      result.action_results[#result.action_results+1] = {
        op = op, id = action.track, name = action.name,
        volume_db = action.volume_db, pan_pct = action.pan_pct,
        mute = action.mute, solo = action.solo,
        master_send = action.master_send, status = "ok"
      }

    elseif op == "track.pan_lfo" then
      local tr = tracks[action.track]
      if not tr then
        return fail("unknown_ref", path .. ".track",
          "Unknown track id " .. tostring(action.track))
      end
      local ok, code, msg, points =
        Code._typed_action_apply_track_pan_lfo(api, tr, action)
      if not ok then
        return fail(code or "pan_lfo_failed", path, msg)
      end
      result.action_results[#result.action_results+1] = {
        op = op, id = action.track, start = action.start, bars = action.bars,
        cycles_per_bar = action.cycles_per_bar,
        depth_pct = action.depth_pct, resolution = action.resolution,
        clear_existing = action.clear_existing, status = "ok", points = points
      }

    elseif op == "track.folder" then
      result.action_results[#result.action_results+1] = {
        op = op, id = action.parent, children = action.children, status = "ok"
      }

    elseif op == "fx.add_stock" then
      local tr = tracks[action.track]
      if not tr then
        return fail("unknown_ref", path .. ".track",
          "Unknown track id " .. tostring(action.track))
      end
      local existed = false
      if type(api.TrackFX_GetByName) == "function" then
        local before_fx = api.TrackFX_GetByName(tr, action.fx, false)
        existed = type(before_fx) == "number" and before_fx >= 0
      end
      local fx = api.TrackFX_AddByName(tr, action.fx, false, -1)
      if not fx or fx < 0 then
        return fail("fx_add_failed", path .. ".fx",
          "Could not add " .. tostring(action.fx))
      end
      fx_by_id[action.id] = { track = tr, fx = fx, fx_name = action.fx }
      result.action_results[#result.action_results+1] = {
        op = op, id = action.id, track = action.track, fx = action.fx,
        existed = existed, status = "ok"
      }

    elseif op == "fx.set_param" then
      param_actions[#param_actions+1] = { action = action, path = path }

    elseif op == "send.create" then
      local src, dst = tracks[action["from"]], tracks[action.to]
      if not src then
        return fail("unknown_ref", path .. ".from",
          "Unknown source track id " .. tostring(action["from"]))
      end
      if not dst then
        return fail("unknown_ref", path .. ".to",
          "Unknown destination track id " .. tostring(action.to))
      end
      local sidx = api.CreateTrackSend(src, dst)
      if not sidx or sidx < 0 then
        return fail("send_create_failed", path,
          "Could not create send " .. tostring(action.id))
      end
      if action.volume_db ~= nil then
        api.SetTrackSendInfo_Value(src, 0, sidx, "D_VOL",
          _typed_action_db_to_amp(action.volume_db))
      end
      if action.pan ~= nil then
        api.SetTrackSendInfo_Value(src, 0, sidx, "D_PAN", action.pan)
      end
      if action.muted ~= nil then
        api.SetTrackSendInfo_Value(src, 0, sidx, "B_MUTE",
          action.muted and 1 or 0)
      end
      if action.mode ~= nil then
        local mode, mode_err = _typed_action_send_mode(action.mode)
        if mode == nil then return fail("unsupported_send_mode", path .. ".mode", mode_err) end
        api.SetTrackSendInfo_Value(src, 0, sidx, "I_SENDMODE", mode)
      end
      result.action_results[#result.action_results+1] = {
        op = op, id = action.id, from = action["from"], to = action.to,
        volume_db = action.volume_db, pan = action.pan, mode = action.mode,
        muted = action.muted, status = "ok"
      }
    end
  end

  for _, track_id in ipairs((folder_depth_plan and folder_depth_plan.order) or {}) do
    local tr = tracks[track_id]
    if not tr then
      return fail("unknown_ref", "$.actions",
        "Unknown folder track id " .. tostring(track_id))
    end
    api.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH",
      folder_depth_plan.depths[track_id] or 0)
  end

  local function apply_params_and_close()
    local ok, err = xpcall(function()
      for _, item in ipairs(param_actions) do
        local action, path = item.action, item.path
        local fx_ref = fx_by_id[action.fx]
        if not fx_ref then error(path .. ": unknown FX id " .. tostring(action.fx)) end
        local setters = assert(_typed_action_param_setters(
          fx_ref.fx_name, action.params, path))
        for _, setter in ipairs(setters) do
          if setter.method == "raw" then
            api.TrackFX_SetParam(fx_ref.track, fx_ref.fx, setter.index, setter.value)
          else
            api.TrackFX_SetParamNormalized(fx_ref.track, fx_ref.fx,
              setter.index, setter.value)
          end
        end
        result.action_results[#result.action_results+1] = {
          op = action.op, id = action.fx, params = action.params, status = "ok"
        }
      end
    end, debug and debug.traceback or tostring)
    if not ok then
      close_block("ReaAssist: typed actions failed", -1)
      local fallback = "Structured edit parameter write failed: " .. tostring(err)
      local msg = (RA and RA.t and RA.t(
        "typed_actions.error.param_write_failed",
        { error = tostring(err) }, fallback)) or fallback
      if type(Log) == "table" and type(Log.add_error) == "function" then
        Log.add_error(msg)
      end
      if type(api.ShowMessageBox) == "function" then
        pcall(api.ShowMessageBox, msg, "ReaAssist", 0)
      end
      local _, err_result = Code._typed_action_error_result(
        "param_write_failed", "$.actions", tostring(err), result)
      complete(false, err_result)
      return false, err_result
    end
    close_block("ReaAssist: typed actions", -1)
    complete(true, { result = result })
    return true
  end

  if #param_actions > 0 then
    -- Supported stock FX expose their typed-action parameters immediately
    -- after TrackFX_AddByName. Keep insertion and parameter writes in the same
    -- REAPER cycle so Undo_BeginBlock/Undo_EndBlock owns one complete edit.
    -- An undo block that crosses reaper.defer cycles does not reliably group
    -- the native FX-parameter undo entries.
    local applied, apply_err = apply_params_and_close()
    if not applied then return false, apply_err end
  else
    close_block("ReaAssist: typed actions", -1)
    complete(true, { result = result })
  end

  return true, result
end

function Code.execute_typed_actions_from_text(text, opts)
  opts = type(opts) == "table" and opts or {}
  local plan, errors = Code.typed_actions_plan_from_text(text, opts)
  if not plan then
    local code = _typed_action_first_error_code(errors)
    local result_code = (code == "invalid_json" or code == "invalid_json_shape")
      and "invalid_json" or "missing_action_block"
    return Code._typed_action_error_result(result_code, "$",
      code or "No reaassist-actions block found", nil)
  end
  local api = opts.api or (type(reaper) == "table" and reaper or nil)
  local selected_track_count = nil
  if type(api) == "table" and type(api.CountSelectedTracks) == "function" then
    selected_track_count = api.CountSelectedTracks(0)
  end
  local semantic_ok, semantic_errors = Code.validate_typed_actions_semantics(
    plan, {
      profile = opts.profile,
      user_text = opts.user_text or "",
      selected_track_count = selected_track_count,
    })
  if not semantic_ok then
    return Code._typed_action_error_result("semantic_mismatch", "$.actions",
      Code.format_typed_action_semantic_errors(semantic_errors, 4), nil)
  end
  return Code.execute_typed_actions_plan(plan, opts)
end

-- Lightweight inspection path used before deciding whether to retry/escalate or
-- execute. It returns parsed plan metrics and validation details without
-- mutating the project.
function Code.inspect_typed_actions(text, opts)
  opts = type(opts) == "table" and opts or {}
  local metrics = {
    present = false,
    valid = false,
    executed = false,
    fallback_to_lua = false,
    raw_json = false,
    retry_count = 0,
    error = nil,
    op_counts = _typed_action_blank_op_counts(),
  }

  if opts.allow_raw_json then
    local raw_json = _typed_action_trim(text)
    if raw_json:sub(1, 1) == "{" then
      metrics.present = true
      metrics.raw_json = true
      local plan, parse_errors = Code.parse_typed_actions_block(raw_json)
      if not plan then
        metrics.error = _typed_action_first_error_code(parse_errors) or "invalid_json"
        return metrics
      end
      Code.repair_typed_actions_plan(plan, opts)
      metrics.op_counts = _typed_action_count_ops(plan)
      local valid, validate_errors = Code.validate_typed_actions_plan(plan)
      if not valid then
        metrics.error = _typed_action_first_error_code(validate_errors) or "invalid_plan"
        return metrics
      end
      metrics.valid = true
      return metrics
    end
  end

  local raw, extract_errors = Code.extract_typed_actions(text)
  if not raw then
    if extract_errors and #extract_errors > 0 then
      metrics.present = true
      metrics.error = _typed_action_first_error_code(extract_errors)
    end
    return metrics
  end

  metrics.present = true
  local plan, parse_errors = Code.parse_typed_actions_block(raw)
  if not plan then
    metrics.error = _typed_action_first_error_code(parse_errors) or "invalid_json"
    return metrics
  end

  Code.repair_typed_actions_plan(plan, opts)
  metrics.op_counts = _typed_action_count_ops(plan)
  local valid, validate_errors = Code.validate_typed_actions_plan(plan)
  if not valid then
    metrics.error = _typed_action_first_error_code(validate_errors) or "invalid_plan"
    return metrics
  end

  metrics.valid = true
  return metrics
end
end -- close typed action validator scope

-- =============================================================================
-- Code safety: risky-call scanner + execution gate
-- =============================================================================
-- Code.find_unknown_reaper_calls(lua_code) -> list of bad names, or nil
-- =============================================================================
-- Pre-flight validator that catches model-emitted reaper.X calls where X
-- isn't a real function on this user's machine. Complements the docs-gate
-- (which auto-fetches docs when the model wrote reaper.* without docs in
-- context); this fires AFTER the docs-gate, on the case where docs IS
-- pinned but the model still hallucinated a function name.
--
-- Source of truth is the live `reaper` table (introspected once per session
-- via _valid_reaper_fns), not the curated docs file -- the curated docs is
-- a small subset (~150 functions) of REAPER's full ~3000-function API plus
-- whatever extensions the user has installed (SWS, JS_ReaScriptAPI, BR_,
-- CF_, etc.). Validating against docs would flag tons of legitimate calls.
-- Validating against the live table flags exactly the calls that would
-- fail at runtime on this machine.
--
-- Common failure mode caught: weaker models (Gemini Flash 3.5, Kimi k2.6,
-- smaller Claude variants) sometimes emit plausible-sounding but
-- non-existent names like "GetProjectMarkerByIndex" (real function is
-- "EnumProjectMarkers") even when docs is pinned. The runtime sandbox
-- catches these as "attempt to call a nil value" but the user sees a
-- crash instead of a corrected reply.
local _valid_reaper_fns_cache = nil
local function _valid_reaper_fns()
  if _valid_reaper_fns_cache then return _valid_reaper_fns_cache end
  local t, count = {}, 0
  for k, v in pairs(reaper) do
    if type(v) == "function" then
      t[k] = true
      count = count + 1
    end
  end
  _valid_reaper_fns_cache = t
  -- One-shot proof-of-life log: confirms the validator was loaded and
  -- shows how many functions REAPER + installed extensions exposed on
  -- this user's machine. Only fires once per session (subsequent calls
  -- hit the cache and return immediately above).
  if type(Log) == "table" and type(Log.line) == "function" then
    Log.line("API-VALIDATOR",
      "cache built: " .. count .. " reaper.* functions available")
  end
  return t
end

local function _blank_non_newlines(s)
  return tostring(s or ""):gsub("[^\r\n]", " ")
end

local function _lua_code_only_preserving_offsets(lua_code)
  local src = tostring(lua_code or "")
  if type(Code.tokenize_lua) ~= "function" then
    -- Best-effort fallback for sliced test environments; production loads the
    -- shared tokenizer before validators run, so strings/block comments are
    -- blanked by the token path below.
    return src:gsub("%-%-[^\n]*", _blank_non_newlines)
  end
  local out = {}
  for _, t in ipairs(Code.tokenize_lua(src) or {}) do
    if t.type == "str" or t.type == "com" then
      out[#out + 1] = _blank_non_newlines(t.text)
    else
      out[#out + 1] = t.text
    end
  end
  return table.concat(out)
end

-- ReaEQ mapping scans need to see a real plugin-name string argument while
-- ignoring comments and code-looking text inside arbitrary strings. Preserve
-- byte/newline offsets, reduce quoted ReaEQ names to one canonical literal,
-- reduce other quoted strings to an empty literal, and blank long strings.
function Code._lua_reeq_scan_source(lua_code)
  local src = tostring(lua_code or "")
  if type(Code.tokenize_lua) ~= "function" then
    return _lua_code_only_preserving_offsets(src)
  end
  local out, has_reeq_literal = {}, false
  for _, token in ipairs(Code.tokenize_lua(src) or {}) do
    if token.type == "com" then
      out[#out + 1] = _blank_non_newlines(token.text)
    elseif token.type == "str" then
      local raw = tostring(token.text or "")
      local value = raw
      local chunk = load("return " .. raw, "=(ReaEQ scan literal)", "t", {})
      if chunk then
        local ok, parsed = pcall(chunk)
        if ok and type(parsed) == "string" then value = parsed end
      end
      local normalized = tostring(value):lower():gsub("[^%a%d]", "")
      local marker = normalized:find("reaeq", 1, true) and '"ReaEQ"' or nil
      local blank = _blank_non_newlines(raw)
      if marker then
        has_reeq_literal = true
        -- Preserve every newline and byte offset. Long strings can begin with
        -- a newline, so place the marker in the first sufficiently long
        -- non-newline run instead of overwriting the token prefix.
        local marker_pos = blank:find(
          "[^\r\n][^\r\n][^\r\n][^\r\n][^\r\n][^\r\n][^\r\n]")
        if marker_pos then
          out[#out + 1] = blank:sub(1, marker_pos - 1) .. marker
            .. blank:sub(marker_pos + #marker)
        else
          -- A long string can split every run (for example, [[\nReaEQ\n]]).
          -- Spread a bare canonical marker across five existing non-newline
          -- bytes; literal_reeq_name normalizes the intervening whitespace.
          local marker_chars, marker_idx, pieces = "ReaEQ", 1, {}
          for i = 1, #blank do
            local ch = blank:sub(i, i)
            if marker_idx <= #marker_chars and ch ~= "\r" and ch ~= "\n" then
              pieces[#pieces + 1] = marker_chars:sub(marker_idx, marker_idx)
              marker_idx = marker_idx + 1
            else
              pieces[#pieces + 1] = ch
            end
          end
          out[#out + 1] = table.concat(pieces)
        end
      else
        out[#out + 1] = blank
      end
    else
      out[#out + 1] = token.text
    end
  end
  return table.concat(out), has_reeq_literal
end

function Code.find_unknown_reaper_calls(lua_code)
  if not lua_code or lua_code == "" then return nil, 0 end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local valid = _valid_reaper_fns()
  local seen, unknown = {}, {}
  local total = 0
  for name in stripped:gmatch("reaper%.([%w_]+)") do
    total = total + 1
    if not valid[name] and not seen[name] then
      seen[name] = true
      unknown[#unknown+1] = name
    end
  end
  if #unknown == 0 then return nil, total end
  table.sort(unknown)
  return unknown, total
end

function Code.find_unavailable_lua_library_calls(lua_code)
  if not lua_code or lua_code == "" then return nil, 0 end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local blocked = {
    math = {
      mod = "Lua 5.4 has no math.mod; use the % operator or math.fmod for floating-point remainder semantics.",
      pow = "Lua 5.4 has no math.pow; use the exponent operator instead, e.g. 10 ^ (db / 20).",
    },
    string = {
      gfind = "Lua 5.4 has no string.gfind; use string.gmatch instead.",
    },
    table = {
      getn = "Lua 5.4 has no table.getn; use the length operator (#t) instead.",
    },
  }
  local blocked_global = {
    unpack = "Lua 5.4 has no global unpack; use table.unpack instead.",
  }
  local findings, seen = {}, {}
  local total = 0

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function name_assigned_before(name, pos)
    local prefix = stripped:sub(1, math.max(0, (pos or 1) - 1))
    local n = tostring(name or "")
    if n == "" then return false end
    local escaped = n:gsub("(%W)", "%%%1")
    if prefix:find("%f[%w_]local%s+function%s+" .. escaped .. "%f[^%w_]", 1) then
      return true
    end
    if prefix:find("%f[%w_]function%s+" .. escaped .. "%s*%(", 1) then
      return true
    end
    if prefix:find("%f[%w_]" .. escaped .. "%s*=", 1) then
      return true
    end
    local pos2 = 1
    while true do
      local s, e, names = prefix:find("%f[%w_]local%s+([%a_][%w_%s,]*)=", pos2)
      if not s then break end
      for declared in tostring(names or ""):gmatch("[%a_][%w_]*") do
        if declared == n then return true end
      end
      pos2 = e + 1
    end
    return false
  end

  local function add_finding(call, pos, msg)
    total = total + 1
    if not seen[call] then
      seen[call] = true
      findings[#findings + 1] = {
        call = call,
        line = line_for_pos(pos),
        message = msg,
      }
    end
  end

  local pos = 1
  while true do
    local s, e, lib, name =
      stripped:find("([%a_][%w_]*)%s*%.%s*([%a_][%w_]*)%s*%(", pos)
    if not s then break end
    local msg = blocked[tostring(lib or "")] and blocked[tostring(lib or "")][tostring(name or "")]
    if msg then
      add_finding(tostring(lib) .. "." .. tostring(name), s, msg)
    end
    pos = e + 1
  end

  pos = 1
  while true do
    local s, e, name = stripped:find("%f[%a_]([%a_][%w_]*)%s*%(", pos)
    if not s then break end
    local before = s > 1 and stripped:sub(s - 1, s - 1) or ""
    local prefix = stripped:sub(math.max(1, s - 24), s - 1)
    local msg = blocked_global[tostring(name or "")]
    if msg
       and before ~= "."
       and before ~= ":"
       and not prefix:match("%f[%w_]function%s+$")
       and not name_assigned_before(name, s) then
      add_finding(tostring(name), s, msg)
    end
    pos = e + 1
  end

  if #findings == 0 then return nil, total end
  table.sort(findings, function(a, b)
    return tostring(a.call) < tostring(b.call)
  end)
  return findings, total
end

-- Detect a high-confidence undefined table target before auto-run. Indexing a
-- nil global on the left side of an assignment compiles successfully but then
-- crashes at runtime, often after the script has already made partial project
-- changes. This deliberately checks only the append shape observed in model
-- output: `lhs[#declared_list + 1] = value`. It flags an undeclared `lhs` when
-- the length expression names a different, already-declared list. Broader Lua
-- undefined-global analysis would need a real AST and risks false positives.
function Code.find_likely_undefined_table_targets(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local findings, seen = {}, {}

  local function declared_before(name, pos)
    local prefix = stripped:sub(1, math.max(0, (pos or 1) - 1))
    local n = tostring(name or "")
    if n == "" then return false end
    local escaped = n:gsub("(%W)", "%%%1")
    -- Recognize a bare target anywhere in a single-line multi-assignment
    -- without mistaking dotted targets or constructor fields for that target.
    -- The tokenizer path below still covers local declarations, loop bindings,
    -- function parameters, and multi-line forms.
    for statement in (prefix .. "\n"):gmatch("([^\r\n;]*)[\r\n;]") do
      local lhs = statement:match("^%s*(.-)%s*=%s*[^=]")
      if lhs and not lhs:find("[=<>~]") then
        lhs = lhs:gsub("^%s*local%s+", "")
        for target in lhs:gmatch("[^,]+") do
          local bare = target:match("^%s*([%a_][%w_]*)%s*$")
          if bare == n then return true end
        end
      end
    end
    if type(Code.tokenize_lua) == "function" then
      local significant = {}
      for _, token in ipairs(Code.tokenize_lua(prefix) or {}) do
        if token.type ~= "ws" and token.type ~= "com"
            and token.type ~= "str" then
          significant[#significant + 1] = token
        end
      end
      local function is_name_token(token)
        return token and (token.type == "id" or token.type == "api")
      end
      for i, token in ipairs(significant) do
        if token.type == "kw" and token.text == "local" then
          local j = i + 1
          if significant[j] and significant[j].text == "function" then
            j = j + 1
          end
          while is_name_token(significant[j]) do
            if significant[j].text == n then return true end
            if not significant[j + 1]
                or significant[j + 1].text ~= "," then
              break
            end
            j = j + 2
          end
        elseif token.type == "kw" and token.text == "for" then
          local j = i + 1
          while is_name_token(significant[j]) do
            if significant[j].text == n then return true end
            if not significant[j + 1]
                or significant[j + 1].text ~= "," then
              break
            end
            j = j + 2
          end
        elseif is_name_token(token) then
          -- Recognize a bounded bare multi-assignment declaration such as
          -- `results, errors = {}, {}` without treating constructor fields or
          -- dotted/colon targets as declarations. Indexed mixed targets such
          -- as `t[i], errors = ...` intentionally remain outside this narrow
          -- check because accepting `]` would reopen constructor false hits.
          local lhs_start = i
          while lhs_start >= 3
              and significant[lhs_start - 1].text == ","
              and is_name_token(significant[lhs_start - 2]) do
            lhs_start = lhs_start - 2
          end
          local j = lhs_start
          local declares_name = false
          while is_name_token(significant[j]) do
            if significant[j].text == n then declares_name = true end
            if significant[j + 1]
               and significant[j + 1].text == ","
               and is_name_token(significant[j + 2]) then
              j = j + 2
            else
              break
            end
          end
          local previous = significant[lhs_start - 1]
          local previous_text = previous and previous.text or ""
          if declares_name
              and significant[j + 1]
              and significant[j + 1].text == "="
              and (not significant[j + 2]
                or significant[j + 2].text ~= "=")
              and previous_text ~= "." and previous_text ~= ":"
              and previous_text ~= "{" and previous_text ~= ","
              and previous_text ~= "=" then
            return true
          end
        end
      end
    elseif prefix:find(
        "%f[%w_]local%s+" .. escaped .. "%f[^%w_]", 1)
       or prefix:find("%f[%w_]" .. escaped .. "%s*=%s*[^=]", 1)
       or prefix:find("%f[%w_]for%s+" .. escaped .. "%f[^%w_]", 1) then
      return true
    end
    for params in prefix:gmatch("function[^%(]*%(([^%)]*)%)") do
      for param in tostring(params):gmatch("[%a_][%w_]*") do
        if param == n then return true end
      end
    end
    return false
  end

  local pos = 1
  while true do
    local s, e, target, counted = stripped:find(
      "%f[%w_]([%a_][%w_]*)%s*%[%s*#%s*([%a_][%w_]*)[^%]]*%]%s*=", pos)
    if not s then break end
    if target ~= counted
       and not declared_before(target, s)
       and declared_before(counted, s)
       and not seen[target] then
      seen[target] = true
      findings[#findings + 1] = {
        global = target,
        likely_target = counted,
        line = Code._lua_line_for_pos(stripped, s),
        expression = target .. "[#" .. counted .. " ...]",
        message = "`" .. target .. "` is not declared before this table write. "
          .. "The append length uses the declared table `" .. counted
          .. "`; use the intended declared table consistently.",
      }
    end
    pos = e + 1
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.global) < tostring(b.global)
  end)
  return findings
end

function Code.find_mistyped_reaper_globals(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local valid = _valid_reaper_fns()
  local seen, findings = {}, {}

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function prefix_assigned_before(name, pos)
    local prefix = stripped:sub(1, (pos or 1) - 1)
    local n = tostring(name or "")
    if n == "" then return false end
    local escaped = n:gsub("(%W)", "%%%1")
    if prefix:find("%f[%w_]local%s+function%s+" .. escaped .. "%f[^%w_]", 1) then
      return true
    end
    if prefix:find("%f[%w_]" .. escaped .. "%s*=%s*[^=]", 1) then
      return true
    end
    local pos2 = 1
    while true do
      local s, e, names = prefix:find("%f[%w_]local%s+([%a_][%w_%s,]*)=", pos2)
      if not s then break end
      for declared in tostring(names or ""):gmatch("[%a_][%w_]*") do
        if declared == n then return true end
      end
      pos2 = e + 1
    end
    return false
  end

  local pos = 1
  while true do
    local s, e, prefix, name =
      stripped:find("([%a_][%w_]*)%s*%.%s*([%a_][%w_]*)%s*%(", pos)
    if not s then break end
    local pfx = tostring(prefix or "")
    local lower = pfx:lower()
    if lower ~= "reaper"
       and (lower:match("^rea") or lower == "reel")
       and #lower >= 4
       and #lower <= 8
       and not prefix_assigned_before(pfx, s)
       and valid[name] then
      local key = lower .. ":" .. tostring(name)
      if not seen[key] then
        seen[key] = true
        findings[#findings + 1] = {
          global = pfx,
          name = name,
          line = line_for_pos(s),
        }
      end
    end
    pos = e + 1
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    if a.global ~= b.global then return a.global < b.global end
    return a.name < b.name
  end)
  return findings
end

-- =============================================================================
-- Code.find_unverified_main_oncommand_ids
-- =============================================================================
-- Main_OnCommand(command_id, 0) is a sharp edge: any integer is syntactically
-- valid, so the API validator cannot tell whether the model picked the right
-- REAPER action. We only allow literal numeric IDs from the small documented
-- common-action list, or IDs the user explicitly typed in the request. Other
-- native actions should be implemented with direct API calls where possible,
-- or the model should ask the user to confirm the exact Action List ID.

function Code.find_unverified_main_oncommand_ids(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  -- Keep in sync with API_Ref.md "COMMON ACTION IDS" (the list served to the
  -- model). IDs verified against REAPER 7.77 kbd_getTextFromCmd; glue action
  -- labels were rechecked on 2026-07-21:
  -- 40032 = Item grouping: Group items (40434 is "move edit cursor to play
  -- cursor" and was removed -- a model emitting 40434 almost certainly means
  -- grouping and SHOULD be flagged); 40362 = glue items while ignoring the
  -- time selection; 42432 = glue items within the time selection; 40289 =
  -- clear selection of all items;
  -- 40625/40626 = time selection set
  -- start/end; 40635 = REMOVE time selection; 40769 = unselect all
  -- tracks/items/envelope points.
  local common = {
    [1007] = true, [1008] = true, [1013] = true, [1016] = true,
    [40044] = true, [40073] = true,

    [40029] = true, [40030] = true, [40026] = true, [40012] = true,
    [40061] = true, [40289] = true, [40362] = true, [42432] = true,
    [40548] = true,
    [40057] = true, [40058] = true, [40698] = true, [40032] = true,
    [40033] = true, [40123] = true, [40719] = true,

    [40001] = true, [40005] = true, [40006] = true,
    [40062] = true, [40297] = true,
    [40296] = true,

    [40020] = true, [40625] = true, [40626] = true, [40635] = true,
    [40364] = true, [40367] = true, [42364] = true, [40769] = true,
    [40860] = true,
  }
  local function user_text_mentions_action_id(id)
    local text = tostring(user_text or "")
    id = tostring(id or "")
    if id == "" then return false end
    local pos = 1
    while true do
      local s, e = text:find(id, pos, true)
      if not s then return false end
      local before = s > 1 and text:sub(s - 1, s - 1) or ""
      local after = e < #text and text:sub(e + 1, e + 1) or ""
      if not before:match("%d") and not after:match("%d") then
        return true
      end
      pos = e + 1
    end
  end
  local seen, bad = {}, {}
  local line_no = 0
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  for clean_line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    for _, fn in ipairs({ "Main_OnCommand", "Main_OnCommandEx" }) do
      local pattern = "reaper%." .. fn .. "%s*%(%s*([+-]?%d+)"
      for id_text in clean_line:gmatch(pattern) do
        local id = tonumber(id_text)
        if id and not common[id]
           and not user_text_mentions_action_id(id) then
          local key = fn .. ":" .. tostring(id)
          if not seen[key] then
            seen[key] = true
            bad[#bad + 1] = { fn = fn, id = id, line = line_no }
          end
        end
      end
    end
  end
  if #bad == 0 then return nil end
  table.sort(bad, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    return a.fn < b.fn
  end)
  return bad
end

-- =============================================================================
-- Code.find_bad_tempo_marker_alignment_scripts
-- =============================================================================
-- For "move this bar/beat line to the transient/edit cursor" tempo-map prompts,
-- adding a marker at the bar's current TimeMap2_beatsToTime position with
-- measurepos/beatpos left at -1 is a parse-valid no-op shape. The intended
-- operation is a real tempo-map edit, such as changing the preceding tempo span
-- so the requested measure/beat lands at the target time.
function Code.find_bad_tempo_marker_alignment_scripts(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  local has_anchor_target =
       prompt:find("%f[%w]transient%f[%W]") ~= nil
    or prompt:find("edit cursor", 1, true) ~= nil
    or prompt:find("%f[%w]cursor%f[%W]") ~= nil
    or prompt:find("%f[%w]tab%f[%W]") ~= nil
  local has_bar_target =
       prompt:find("%f[%w]bar%f[%W]") ~= nil
    or prompt:find("%f[%w]bars%f[%W]") ~= nil
    or prompt:find("%f[%w]measure%f[%W]") ~= nil
    or prompt:find("%f[%w]measures%f[%W]") ~= nil
    or prompt:find("beat 1", 1, true) ~= nil
    or prompt:find("beat one", 1, true) ~= nil
    or prompt:find("%f[%w]downbeat%f[%W]") ~= nil
  local has_move_intent =
       prompt:find("%f[%w]move%f[%W]") ~= nil
    or prompt:find("%f[%w]align%f[%W]") ~= nil
    or prompt:find("%f[%w]sync%f[%W]") ~= nil
    or prompt:find("%f[%w]snap%f[%W]") ~= nil
    or prompt:find("%f[%w]lock%f[%W]") ~= nil
    or prompt:find("onto", 1, true) ~= nil
  if not (has_anchor_target and has_bar_target and has_move_intent) then
    return nil
  end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.SetTempoTimeSigMarker", 1, false)
     or not stripped:find("reaper%.TimeMap2_beatsToTime", 1, false) then
    return nil
  end

  local function trim(s)
    return Code._lua_trim_expr(s)
  end
  local function normalized_token(s)
    local t = trim(s):gsub("%s+", "")
    local paren = t:match("^%(([%w_]+)%)$")
    return paren or t
  end
  local function is_negative_one(s)
    return trim(s):gsub("[%s%(%)]+", "") == "-1"
  end

  local beat_time_vars = {}
  local line_no = 0
  for raw_line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    for name in raw_line:gmatch(
        "([%w_]+)%s*=%s*reaper%.TimeMap2_beatsToTime%s*%(") do
      beat_time_vars[name] = line_no
    end
  end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function call_args(open_pos)
    return Code._lua_call_inner(stripped, open_pos)
  end
  local function split_args(arg_text)
    return Code._split_lua_args(arg_text)
  end

  local findings, search_pos = {}, 1
  while true do
    local s, e = stripped:find("reaper%.SetTempoTimeSigMarker%s*%(",
      search_pos)
    if not s then break end
    local open_pos = stripped:find("%(", s)
    local arg_text, close_pos = nil, nil
    if open_pos then arg_text, close_pos = call_args(open_pos) end
    if arg_text then
      local args = split_args(arg_text)
      local time_arg = args[3] or ""
      local time_token = normalized_token(time_arg)
      local old_bar_line = beat_time_vars[time_token]
      local uses_old_bar_time = old_bar_line ~= nil
        or time_arg:find("reaper%.TimeMap2_beatsToTime", 1, false) ~= nil
      if #args >= 5
         and uses_old_bar_time
         and is_negative_one(args[2])
         and is_negative_one(args[4])
         and is_negative_one(args[5]) then
        findings[#findings + 1] = {
          line = line_for_pos(s),
          source_line = old_bar_line,
        }
      end
    end
    search_pos = (close_pos or e) + 1
  end

  return #findings > 0 and findings or nil
end

function Code.find_loop_bar_beat_without_timemap(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if prompt == "" then return nil end

  local has_loop_intent =
       prompt:find("%f[%w]loop%f[%W]") ~= nil
    or prompt:find("loop range", 1, true) ~= nil
    or prompt:find("loop points", 1, true) ~= nil
    or prompt:find("time selection", 1, true) ~= nil
  local has_bar_beat =
       prompt:find("%f[%w]bar%f[%W]") ~= nil
    or prompt:find("%f[%w]bars%f[%W]") ~= nil
    or prompt:find("%f[%w]measure%f[%W]") ~= nil
    or prompt:find("%f[%w]measures%f[%W]") ~= nil
    or prompt:find("%f[%w]beat%f[%W]") ~= nil
    or prompt:find("%f[%w]beats%f[%W]") ~= nil
    or prompt:find("%f[%w]downbeat%f[%W]") ~= nil
  local function phrase(...)
    local parts = { ... }
    local pattern = ""
    for i = 1, #parts do
      if i > 1 then pattern = pattern .. "%W+" end
      pattern = pattern .. "%f[%w]" .. parts[i] .. "%f[%W]"
    end
    return prompt:find(pattern) ~= nil
  end
  local function action_loop_phrase(action)
    return phrase(action, "loop") or phrase(action, "the", "loop")
      or phrase(action, "loop", "points")
      or phrase(action, "the", "loop", "points")
  end
  local function action_time_selection_phrase(action)
    return phrase(action, "time", "selection")
      or phrase(action, "the", "time", "selection")
  end
  local clear_only =
       action_loop_phrase("clear")
    or action_loop_phrase("remove")
    or action_loop_phrase("disable")
    or action_loop_phrase("stop")
    or phrase("turn", "loop", "off")
    or phrase("turn", "the", "loop", "off")
    or phrase("turn", "off", "loop")
    or phrase("turn", "off", "the", "loop")
    or action_time_selection_phrase("clear")
    or action_time_selection_phrase("remove")
  if not (has_loop_intent and has_bar_beat) or clear_only then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.GetSet_LoopTimeRange", 1, false) then
    return nil
  end
  if stripped:find("reaper%.TimeMap2_", 1, false) then return nil end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function call_args(open_pos)
    return Code._lua_call_inner(stripped, open_pos)
  end
  local function split_args(arg_text)
    return Code._split_lua_args(arg_text)
  end

  local has_measure_info =
    stripped:find("reaper%.TimeMap_GetMeasureInfo%s*%(") ~= nil
  local qn_time_vars = {}
  local assignment_scan = stripped
    :gsub("=%s*\n%s*(reaper%.TimeMap_QNToTime)", "= %1")
  if has_measure_info then
    for raw_line in assignment_scan:gmatch("[^\r\n]+") do
      local vars, expr =
        raw_line:match("^%s*local%s+([%a_][%w_,%s]*)%s*=%s*(.-)%s*$")
      if not vars then
        vars, expr = raw_line:match("^%s*([%a_][%w_,%s]*)%s*=%s*(.-)%s*$")
      end
      if vars and expr
         and (expr:find("reaper%.TimeMap_QNToTime%s*%(")
          or expr:find("reaper%.TimeMap_QNToTime_abs%s*%(")) then
        local lhs_vars, rhs_exprs = split_args(vars), split_args(expr)
        for i, lhs in ipairs(lhs_vars) do
          local var = lhs:match("^%s*([%a_][%w_]*)%s*$")
          local rhs = rhs_exprs[i] or ""
          if var
             and (rhs:find("reaper%.TimeMap_QNToTime%s*%(")
              or rhs:find("reaper%.TimeMap_QNToTime_abs%s*%(")) then
            qn_time_vars[var] = true
          end
        end
      end
    end
  end
  local function uses_qn_time(arg)
    if not has_measure_info then return false end
    if arg:find("reaper%.TimeMap_QNToTime%s*%(")
       or arg:find("reaper%.TimeMap_QNToTime_abs%s*%(") then
      return true
    end
    for var in pairs(qn_time_vars) do
      if arg:find("%f[%w_]" .. var .. "%f[^%w_]") then return true end
    end
    return false
  end
  local function loop_call_uses_qn_time(api, arg_text)
    local args = split_args(arg_text or "")
    local start_idx = api == "GetSet_LoopTimeRange2" and 4 or 3
    local start_arg, end_arg = args[start_idx] or "", args[start_idx + 1] or ""
    return uses_qn_time(start_arg) and uses_qn_time(end_arg)
  end

  local findings = {}
  local search_pos = 1
  while true do
    local s, e, api = stripped:find("reaper%.(GetSet_LoopTimeRange2?)%s*%(",
      search_pos)
    if not s then break end
    local open_pos = stripped:find("%(", s)
    local arg_text, close_pos = nil, nil
    if open_pos then arg_text, close_pos = call_args(open_pos) end
    if not (arg_text and loop_call_uses_qn_time(api, arg_text)) then
      findings[#findings + 1] = { line = line_for_pos(s), api = api }
    end
    search_pos = (close_pos or e) + 1
  end

  return #findings > 0 and findings or nil
end

function Code.find_missing_project_tempo_set(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if prompt == "" then return nil end
  if prompt:find("do not change tempo", 1, true)
     or prompt:find("don't change tempo", 1, true)
     or prompt:find("without changing tempo", 1, true) then
    return nil
  end
  local bpm = prompt:match("%f[%w]set%s+tempo%s+to%s+(%d+%.?%d*)%s*bpm")
    or prompt:match("%f[%w]set%s+the%s+tempo%s+to%s+(%d+%.?%d*)%s*bpm")
    or prompt:match("%f[%w]change%s+tempo%s+to%s+(%d+%.?%d*)%s*bpm")
    or prompt:match("%f[%w]tempo%s+to%s+(%d+%.?%d*)%s*bpm")
  local explicit_tempo_request = bpm ~= nil
  bpm = bpm or prompt:match("%f[%w]at%s+(%d+%.?%d*)%s*bpm%f[%W]")
  bpm = bpm or prompt:match("%f[%d](%d+%.?%d*)%s*bpm%f[%W]")
  if not bpm then return nil end
  local existing_tempo_context =
       prompt:find("%f[%w]project%s+is%s+at%s+%d+%.?%d*%s*bpm%f[%W]") ~= nil
    or prompt:find("%f[%w]project's%s+at%s+%d+%.?%d*%s*bpm%f[%W]") ~= nil
    or prompt:find("%f[%w]session%s+is%s+at%s+%d+%.?%d*%s*bpm%f[%W]") ~= nil
    or prompt:find("%f[%w]song%s+is%s+at%s+%d+%.?%d*%s*bpm%f[%W]") ~= nil
    or prompt:find("%f[%w]tempo%s+is%s+%d+%.?%d*%s*bpm%f[%W]") ~= nil
  local beat_content_request =
       explicit_tempo_request
    or prompt:find("%f[%w]midi%f[%W]") ~= nil
    or prompt:find("%f[%w]groove%f[%W]") ~= nil
    or prompt:find("%f[%w]drum%s+pattern%f[%W]") ~= nil
    or prompt:find("%f[%w]beat%f[%W]") ~= nil
    or prompt:find("%f[%w]bar%f[%W]") ~= nil
    or prompt:find("%f[%w]bars%f[%W]") ~= nil
    or prompt:find("%f[%w]marker%f[%W]") ~= nil
    or prompt:find("%f[%w]region%f[%W]") ~= nil
    or prompt:find("%f[%w]song%s+map%f[%W]") ~= nil
  if not beat_content_request then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.SetCurrentBPM%s*%(")
     or stripped:find("reaper%.SetTempoTimeSigMarker%s*%(") then
    return nil
  end
  if not explicit_tempo_request
     and existing_tempo_context
     and (stripped:find("reaper%.Master_GetTempo%s*%(")
       or stripped:find("reaper%.GetProjectTimeSignature2%s*%(")) then
    return nil
  end
  return { bpm = bpm }
end

function Code.find_missing_point_markers_for_region_marker_pairs(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local text = tostring(user_text or "")
  local lower_text = text:lower()
  local marker_s, marker_e = lower_text:find("%f[%w]markers%f[%W]")
  if not marker_s then
    marker_s, marker_e = lower_text:find("%f[%w]marker%f[%W]")
  end
  if not marker_s then return nil end

  local cutoff = #text + 1
  for _, pat in ipairs({
    "%f[%w]regions%f[%W]",
    "%f[%w]region%f[%W]",
    "%f[%w]tracks%f[%W]",
    "%f[%w]track%f[%W]",
    "%f[%w]do%s+not%f[%W]",
    "%f[%w]don't%f[%W]",
  }) do
    local s = lower_text:find(pat, marker_e + 1)
    if s and s < cutoff then cutoff = s end
  end

  local function trim(s)
    return Code._lua_trim_expr(s)
  end
  local requested, seen = {}, {}
  local segment = text:sub(marker_e + 1, cutoff - 1)
  for name in segment:gmatch("([%a][%w%s%-%_']-)%s+at%s+[%d%.]+%s*%a*") do
    name = trim(name)
      :gsub("^and%s+", "")
      :gsub("^a%s+", "")
      :gsub("^the%s+", "")
      :gsub("^marker%s+", "")
      :gsub("^markers%s+", "")
    name = trim(name)
    if name ~= ""
       and #name <= 64
       and not name:lower():find("region", 1, true)
       and not seen[name:lower()] then
      seen[name:lower()] = true
      requested[#requested + 1] = name
    end
  end
  if #requested == 0 then return nil end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local function escaped_literal(s)
    return (tostring(s or ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
  end
  local function has_named_api_call(api_name, is_region, name)
    local bool = is_region and "true" or "false"
    local q = "[\"']" .. escaped_literal(name) .. "[\"']"
    return stripped:find("reaper%." .. api_name
      .. "%s*%([^%)]-,%s*" .. bool .. "%s*,[^%)]-" .. q)
  end
  local function has_named_call(is_region, name)
    return has_named_api_call("AddRegionOrMarker", is_region, name)
      or has_named_api_call("AddProjectMarker2", is_region, name)
      or has_named_api_call("AddProjectMarker", is_region, name)
  end

  local findings = {}
  local has_modern_region_api =
       type(reaper) == "table"
   and type(reaper.AddRegionOrMarker) == "function"
  for _, name in ipairs(requested) do
    local has_modern_true = has_named_api_call("AddRegionOrMarker", true, name)
    local has_modern_false = has_named_api_call("AddRegionOrMarker", false, name)
    if has_modern_region_api
        and has_modern_true
        and not has_modern_false then
      findings[#findings + 1] = { name = name }
    elseif has_named_call(true, name) and not has_named_call(false, name) then
      findings[#findings + 1] = { name = name }
    end
  end
  return #findings > 0 and findings or nil
end

function Code.find_explicit_second_marker_region_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local text = tostring(user_text or "")
  local lower = text:lower()
  if not (lower:find(" seconds", 1, true)
      and (lower:find("marker", 1, true) or lower:find("region", 1, true))) then
    return nil
  end

  local function trim(s)
    return Code._lua_trim_expr(s)
  end
  local function clean_name(name)
    name = trim(name)
      :gsub("^and%s+", "")
      :gsub("^add%s+", "")
      :gsub("^a%s+", "")
      :gsub("^an%s+", "")
      :gsub("^the%s+", "")
    return trim(name)
  end
  local function name_key(name)
    return tostring(name or ""):lower():gsub("[^%w]+", "")
  end
  local expectations = {}
  local function add_expectation(kind, name, start_s, end_s)
    name = clean_name(name)
    if name == "" or #name > 64 then return end
    local key = kind .. ":" .. name_key(name)
    expectations[key] = {
      kind = kind,
      name = name,
      start = tonumber(start_s),
      finish = end_s and tonumber(end_s) or nil,
    }
  end

  for name, start_s, end_s in text:gmatch(
      "%f[%a]a%s+([%a][%w%s%-%_']-)%s+region%s+from%s+([%d%.]+)%s+to%s+([%d%.]+)%s+seconds") do
    add_expectation("region", name, start_s, end_s)
  end
  for name, start_s, end_s in text:gmatch(
      "[Rr]egion%s+named%s+([%a][%w%s%-%_']-)%s+from%s+([%d%.]+)%s+to%s+([%d%.]+)%s+seconds") do
    add_expectation("region", name, start_s, end_s)
  end
  for name, start_s in text:gmatch(
      "%f[%a]a%s+([%a][%w%s%-%_']-)%s+marker%s+at%s+([%d%.]+)%s+seconds") do
    add_expectation("marker", name, start_s, nil)
  end
  for name, start_s in text:gmatch(
      "[Mm]arker%s+named%s+([%a][%w%s%-%_']-)%s+at%s+([%d%.]+)%s+seconds") do
    add_expectation("marker", name, start_s, nil)
  end
  if not next(expectations) then return nil end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local findings = {}
  local function close_enough(a, b)
    a, b = tonumber(a), tonumber(b)
    return a and b and math.abs(a - b) <= 0.05
  end
  local function scan_api(api)
    for args in stripped:gmatch("reaper%." .. api .. "%s*%(([^%)]-)%)") do
      for _, spec in ipairs({
        { kind = "region", bool = "true" },
        { kind = "marker", bool = "false" },
      }) do
        local pos_s, end_s, name = args:match("^%s*[^,]+,%s*"
          .. spec.bool
          .. "%s*,%s*([%-]?%d+%.?%d*)%s*,%s*([%-]?%d+%.?%d*)%s*,%s*[\"'](.-)[\"']")
        local exp = name and expectations[spec.kind .. ":" .. name_key(name)]
        if exp and not close_enough(pos_s, exp.start) then
          findings[#findings + 1] = {
            kind = spec.kind,
            name = exp.name,
            expected_start = exp.start,
            actual_start = tonumber(pos_s),
          }
        elseif exp and spec.kind == "region"
            and not close_enough(end_s, exp.finish) then
          findings[#findings + 1] = {
            kind = spec.kind,
            name = exp.name,
            expected_start = exp.start,
            expected_end = exp.finish,
            actual_start = tonumber(pos_s),
            actual_end = tonumber(end_s),
          }
        end
      end
    end
  end
  scan_api("AddRegionOrMarker")
  scan_api("AddProjectMarker2")
  return #findings > 0 and findings or nil
end

-- =============================================================================
-- Code.find_audio_accessor_transient_marker_scripts
-- =============================================================================
-- A simple Lua peak/energy detector is much worse than REAPER's Dynamic Split
-- for "every hit" drum/transient stretch-marker work: it tends to mark decays
-- and bleed as hits. For that intent, block scripts that combine audio-accessor
-- scanning with direct stretch-marker insertion unless the user explicitly
-- asked for a custom/approximate threshold detector.
local function _validator_first_match_line(text, patterns)
  local best
  for _, pattern in ipairs(patterns or {}) do
    local pos = tostring(text or ""):find(pattern)
    if pos and (not best or pos < best) then best = pos end
  end
  if not best then return 1 end
  local line = 1
  for _ in tostring(text or ""):sub(1, best):gmatch("\n") do line = line + 1 end
  return line
end

function Code.find_audio_accessor_transient_marker_scripts(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  local prompt_names_drum_source =
       prompt:find("%f[%w]drum%f[%W]")
    or prompt:find("%f[%w]drums%f[%W]")
    or prompt:find("%f[%w]kick%f[%W]")
    or prompt:find("%f[%w]snare%f[%W]")
    or prompt:find("guide track", 1, true)
  local prompt_names_drum_edit =
       prompt:find("%f[%w]quantiz")
    or prompt:find("%f[%w]edit")
    or prompt:find("%f[%w]tighten")
    or prompt:find("%f[%w]sync")
    or prompt:find("%f[%w]transient")
    or prompt:find("%f[%w]hit%f[%W]")
    or prompt:find("%f[%w]hits%f[%W]")
    or prompt:find("stretch marker", 1, true)
  local drum_edit_intent =
       CTX
   and CTX.prompt_indicates_drum_edit
   and CTX.prompt_indicates_drum_edit(prompt)
    or (prompt_names_drum_source and prompt_names_drum_edit)
  local wants_markers =
       prompt:find("stretch marker", 1, true)
    or prompt:find("stretch%-marker")
    or drum_edit_intent
  if not wants_markers then return nil end
  local wants_hits =
       prompt:find("%f[%w]hit%f[%W]")
    or prompt:find("%f[%w]hits%f[%W]")
    or prompt:find("%f[%w]transient%f[%W]")
    or prompt:find("%f[%w]transients%f[%W]")
    or prompt:find("%f[%w]drum%f[%W]")
    or prompt:find("%f[%w]drums%f[%W]")
    or prompt:find("%f[%w]kick%f[%W]")
    or prompt:find("%f[%w]snare%f[%W]")
    or drum_edit_intent
  if not wants_hits then return nil end
  local explicitly_custom =
       prompt:find("%f[%w]custom%f[%W]")
    or prompt:find("%f[%w]approximate%f[%W]")
    or prompt:find("%f[%w]approximation%f[%W]")
    or prompt:find("%f[%w]threshold%f[%W]")
    or prompt:find("%f[%w]energy%f[%W]")
  if explicitly_custom then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.GetAudioAccessorSamples", 1, false) then
    return nil
  end
  if not stripped:find("reaper%.SetTakeStretchMarker", 1, false) then
    return nil
  end
  local findings = {}
  local line_no = 0
  for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local line = raw_line:gsub("%-%-[^\n]*", "")
    if line:find("reaper%.GetAudioAccessorSamples", 1, false)
       or line:find("reaper%.SetTakeStretchMarker", 1, false) then
      findings[#findings + 1] = { line = line_no }
    end
  end
  return #findings > 0 and findings or { {
    line = _validator_first_match_line(stripped, {
      "reaper%.GetAudioAccessorSamples",
      "reaper%.SetTakeStretchMarker",
    }),
  } }
end

-- =============================================================================
-- Code.find_nil_unsafe_audio_accessor_sample_checks
-- =============================================================================
-- reaper.GetAudioAccessorSamples can fail to read and return nil. Catch the
-- high-confidence crash shape where generated Lua saves that return value and
-- immediately compares it with <, <=, >, or >= before proving it is non-nil.
function Code.find_nil_unsafe_audio_accessor_sample_checks(lua_code)
  if not lua_code or lua_code == "" then return nil end
  if not lua_code:find("reaper%.GetAudioAccessorSamples", 1, false) then
    return nil
  end

  local function strip_comment(line)
    return tostring(line or ""):gsub("%-%-[^\n]*", "")
  end

  local function ident(name)
    return "%f[%w_]" .. tostring(name) .. "%f[^%w_]"
  end

  local function first_match_pos(line, patterns)
    local best
    for _, pattern in ipairs(patterns) do
      local pos = line:find(pattern)
      if pos and (not best or pos < best) then best = pos end
    end
    return best
  end

  local function capture_return_var(line)
    if not line:find("reaper%.GetAudioAccessorSamples", 1, false) then
      return nil
    end
    local before = line:match("^(.-)reaper%.GetAudioAccessorSamples%s*%(")
    if not before then return nil end
    local lhs = before:match("^%s*local%s+(.+)%s*=%s*$")
      or before:match("^%s*(.-)%s*=%s*$")
    if not lhs or lhs == "" then return nil end
    local name = lhs:match("^%s*([_%a][_%w]*)")
    if name == "if" or name == "return" then return nil end
    return name
  end

  local function nil_guard_pos(line, name)
    local id = ident(name)
    return first_match_pos(line, {
      "not%s+" .. id,
      id .. "%s*==%s*nil",
      "nil%s*==%s*" .. id,
      id .. "%s*~=%s*nil",
      "nil%s*~=%s*" .. id,
      id .. "%s*==%s*1",
      "1%s*==%s*" .. id,
      id .. "%s*~=%s*1",
      "1%s*~=%s*" .. id,
      "type%s*%(%s*" .. id .. "%s*%)%s*==%s*[\"']number[\"']",
      id .. "%s+and%s+" .. id,
    })
  end

  local function relation_pos(line, name)
    local id = ident(name)
    return first_match_pos(line, {
      id .. "%s*[<>]=?",
      "[<>]=?%s*" .. id,
    })
  end

  local function reassigns_name(line, name)
    local id = ident(name)
    return line:find("^%s*local%s+" .. id .. "%s*=")
      or (line:find("^%s*" .. id .. "%s*=")
          and not line:find("^%s*" .. id .. "%s*=="))
  end

  local lines = {}
  for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = strip_comment(raw_line)
  end

  local findings = {}
  for i, line in ipairs(lines) do
    local name = capture_return_var(line)
    if name then
      local guarded = false
      local scanned = 0
      for j = i, math.min(#lines, i + 8) do
        local candidate = lines[j]
        if candidate:match("%S") then
          scanned = scanned + 1
          if j > i and reassigns_name(candidate, name) then break end
          local compare_at = relation_pos(candidate, name)
          local guard_at = nil_guard_pos(candidate, name)
          if guard_at and (not compare_at or guard_at < compare_at) then
            guarded = true
          end
          if compare_at then
            if not guarded then
              findings[#findings + 1] = {
                line = j,
                variable = name,
                source_line = i,
              }
            end
            break
          end
          if scanned >= 5 then break end
        end
      end
    end
  end

  return #findings > 0 and findings or nil
end

-- =============================================================================
-- Code.find_audio_sync_item_start_alignment_scripts
-- =============================================================================
-- Same-song/take sync requests usually mean "match the audio/transient", not
-- "make the item starts or take source offsets equal". Catch high-confidence
-- cases where generated Lua silently treats audio-content sync as a plain
-- start/offset move.
function Code.find_audio_sync_item_start_alignment_scripts(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  local alignment_intent =
       prompt:find("%f[%w]sync")
    or prompt:find("%f[%w]synchron")
    or prompt:find("in sync", 1, true)
    or prompt:find("%f[%w]align")
    or prompt:find("line up", 1, true)
    or prompt:find("%f[%w]match")
  if not alignment_intent then return nil end

  local content_anchor =
       prompt:find("same song", 1, true)
    or prompt:find("same performance", 1, true)
    or prompt:find("same recording", 1, true)
    or prompt:find("matching audio", 1, true)
    or prompt:find("match the audio", 1, true)
    or prompt:find("audio content", 1, true)
    or prompt:find("%f[%w]waveform")
    or prompt:find("%f[%w]transient")
    or prompt:find("take on top", 1, true)
    or prompt:find("on top of", 1, true)
    or prompt:find("selected takes", 1, true)
    or prompt:find("two takes", 1, true)
    or prompt:find("phase align", 1, true)
    or prompt:find("phase%-align")
  if not content_anchor then return nil end

  local explicit_start_or_grid =
       prompt:find("align starts", 1, true)
    or prompt:find("align the starts", 1, true)
    or prompt:find("align item starts", 1, true)
    or prompt:find("align the item starts", 1, true)
    or prompt:find("match starts", 1, true)
    or prompt:find("match the starts", 1, true)
    or prompt:find("same start", 1, true)
    or prompt:find("start at", 1, true)
    or prompt:find("start time", 1, true)
    or prompt:find("start offset", 1, true)
    or prompt:find("take start offset", 1, true)
    or prompt:find("source offset", 1, true)
    or prompt:find("d_startoffs", 1, true)
    or prompt:find("slip edit", 1, true)
    or prompt:find("slip%-edit")
    or prompt:find("slip editing", 1, true)
    or prompt:find("item start", 1, true)
    or prompt:find("item starts", 1, true)
    or prompt:find("move whole item", 1, true)
    or prompt:find("move whole media item", 1, true)
    or prompt:find("move item starts", 1, true)
    or prompt:find("snap to grid", 1, true)
    or prompt:find("sync to grid", 1, true)
    or prompt:find("to the grid", 1, true)
    or prompt:find("align to grid", 1, true)
    or prompt:find("tempo grid", 1, true)
    or prompt:find("project tempo", 1, true)
    or prompt:find("at the cursor", 1, true)
    or prompt:find("edit cursor", 1, true)
    or prompt:find("cursor position", 1, true)
    or prompt:find("bar ", 1, true)
    or prompt:find("beat ", 1, true)
    or prompt:find("set position", 1, true)
    or prompt:find("exact time", 1, true)
  if explicit_start_or_grid then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local writes_plain_start_or_offset =
       stripped:find("reaper%.SetMediaItemPosition", 1, false)
    or (stripped:find("reaper%.SetMediaItemInfo_Value", 1, false)
        and stripped:find("[\"']D_POSITION[\"']"))
    or (stripped:find("reaper%.SetMediaItemTakeInfo_Value", 1, false)
        and stripped:find("[\"']D_STARTOFFS[\"']"))
  if not writes_plain_start_or_offset then return nil end

  local has_real_anchor_workflow =
       stripped:find("reaper%.CreateTakeAudioAccessor", 1, false)
    or stripped:find("reaper%.GetAudioAccessorSamples", 1, false)
    or stripped:find("reaper%.SetTakeStretchMarker", 1, false)
    or stripped:find("reaper%.GetTakeStretchMarker", 1, false)
    or stripped:find("[\"']D_SNAPOFFSET[\"']")
  if has_real_anchor_workflow then return nil end

  local findings = {}
  local line_no = 0
  for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local line = raw_line:gsub("%-%-[^\n]*", "")
    if line:find("reaper%.SetMediaItemPosition", 1, false)
       or (line:find("reaper%.SetMediaItemInfo_Value", 1, false)
           and line:find("[\"']D_POSITION[\"']"))
       or (line:find("reaper%.SetMediaItemTakeInfo_Value", 1, false)
           and line:find("[\"']D_STARTOFFS[\"']")) then
      findings[#findings + 1] = { line = line_no }
    end
  end
  return #findings > 0 and findings or { {
    line = _validator_first_match_line(stripped, {
      "reaper%.SetMediaItemPosition",
      "reaper%.SetMediaItemInfo_Value",
      "reaper%.SetMediaItemTakeInfo_Value",
    }),
  } }
end

-- True when the request asks ReaAssist to align performances by their actual
-- audio/content rather than by an already-supplied timeline coordinate. A
-- project snapshot cannot provide listening evidence, so the request should be
-- answered with the honest anchor workflow instead of a context round-trip.
function Code.prompt_requests_audio_content_sync(user_text)
  local prompt = tostring(user_text or ""):lower()
  local alignment_intent =
       prompt:find("%f[%w]sync") ~= nil
    or prompt:find("%f[%w]synchron") ~= nil
    or prompt:find("%f[%w]align") ~= nil
    or prompt:find("line up", 1, true) ~= nil
  if not alignment_intent then return false end
  return prompt:find("same song", 1, true) ~= nil
    or prompt:find("same performance", 1, true) ~= nil
    or prompt:find("same recording", 1, true) ~= nil
    or prompt:find("by listening", 1, true) ~= nil
    or prompt:find("match the audio", 1, true) ~= nil
    or prompt:find("matching audio", 1, true) ~= nil
    or prompt:find("%f[%w]waveform") ~= nil
    or prompt:find("%f[%w]transient") ~= nil
end

-- =============================================================================
-- Code.find_drum_whole_item_quantize_scripts
-- =============================================================================
-- Drum quantize should move hit timing inside the drum items (normally shared
-- stretch markers from explicit guide tracks), not treat media-item starts as
-- drum hits. A whole-item D_POSITION script can pass validation, report "moved"
-- counts, and still do nothing audible if the item starts are already on-grid.
function Code.find_drum_whole_item_quantize_scripts(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  local has_drum =
       prompt:find("%f[%w]drum%f[%W]")
    or prompt:find("%f[%w]drums%f[%W]")
  if not has_drum then return nil end
  local timing_intent =
       prompt:find("%f[%w]quantiz")
    or prompt:find("%f[%w]tighten")
    or prompt:find("%f[%w]transient")
    or prompt:find("%f[%w]snap%f[%W]")
    or prompt:find("stretch marker", 1, true)
    or prompt:find("guide track", 1, true)
    or prompt:find("edit drums", 1, true)
    or prompt:find("editing drums", 1, true)
  if not timing_intent then return nil end
  local explicitly_whole_item =
       prompt:find("move whole item", 1, true)
    or prompt:find("move whole media item", 1, true)
    or prompt:find("move the items", 1, true)
    or prompt:find("move item starts", 1, true)
  if explicitly_whole_item then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.SetMediaItemInfo_Value", 1, false)
     or not stripped:find("[\"']D_POSITION[\"']") then
    return nil
  end
  if stripped:find("reaper%.SetTakeStretchMarker", 1, false) then
    return nil
  end

  local findings = {}
  local line_no = 0
  for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local line = raw_line:gsub("%-%-[^\n]*", "")
    if line:find("reaper%.SetMediaItemInfo_Value", 1, false)
       and line:find("[\"']D_POSITION[\"']") then
      findings[#findings + 1] = { line = line_no }
    end
  end
  return #findings > 0 and findings or { {
    line = _validator_first_match_line(stripped, {
      "reaper%.SetMediaItemInfo_Value",
    }),
  } }
end

-- Drum stretch-marker quantize must normalize every affected item to the same
-- marker set. If a script adds/moves stretch markers without deleting/replacing
-- the range first, guide tracks can keep Dynamic Split-only markers while the
-- rest of the kit gets a different map.
function Code.find_unsynced_drum_stretch_marker_scripts(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  local has_drum =
       prompt:find("%f[%w]drum%f[%W]")
    or prompt:find("%f[%w]drums%f[%W]")
  if not has_drum then return nil end
  local timing_intent =
       prompt:find("%f[%w]quantiz")
    or prompt:find("%f[%w]tighten")
    or prompt:find("%f[%w]transient")
    or prompt:find("%f[%w]snap%f[%W]")
    or prompt:find("stretch marker", 1, true)
    or prompt:find("guide track", 1, true)
    or prompt:find("edit drums", 1, true)
    or prompt:find("editing drums", 1, true)
  if not timing_intent then return nil end
  local explicit_existing =
       prompt:find("existing stretch marker", 1, true)
    or prompt:find("existing markers", 1, true)
    or prompt:find("already has stretch marker", 1, true)
    or prompt:find("already have stretch marker", 1, true)
  if explicit_existing then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.SetTakeStretchMarker", 1, false) then
    return nil
  end
  if stripped:find("reaper%.DeleteTakeStretchMarkers", 1, false) then
    return nil
  end
  if stripped:find("reaper%.GetTakeStretchMarker", 1, false)
     and not stripped:find("reaper%.SetTakeStretchMarker%s*%([^,\n]+,%s*%-1%s*,") then
    return nil
  end

  local findings = {}
  local line_no = 0
  for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local line = raw_line:gsub("%-%-[^\n]*", "")
    if line:find("reaper%.SetTakeStretchMarker", 1, false) then
      findings[#findings + 1] = { line = line_no }
    end
  end
  return #findings > 0 and findings or { {
    line = _validator_first_match_line(stripped, {
      "reaper%.SetTakeStretchMarker",
    }),
  } }
end

-- =============================================================================
-- Code.find_reaper_arity_mismatches
-- =============================================================================
-- Conservative fixed-arity check for high-confidence param-write calls. The
-- API validator above only checks that NAMES exist; a bug like
-- `reaper.TrackFX_SetParamNormalized(tr, fx, best_v)` (3 args, missing pidx)
-- passes the name check but crashes at runtime inside reaper.defer with
-- "bad argument #3 ... (number has no integer representation)" because
-- best_v (a float) lands in the integer pidx slot. Caught in a Gemini
-- session where the model pasted set_param_display but corrupted the
-- final setter call.
--
-- Scope is intentionally narrow -- only fixed-arity functions where every
-- documented signature has the same arg count, and where the args are
-- always positional (no optional trailing varargs that would produce false
-- positives). Adding a name here is opting it into the strict check; do
-- not add unless every real call site uses the same fixed count.
local _REAPER_FIXED_ARITY = {
  SetCurrentBPM                  = 3,
  AddProjectMarker               = 6,
  AddProjectMarker2              = 7,
  GetSetProjectInfo              = 4,
  GetSetMediaTrackInfo_String    = 4,
  TrackFX_SetParamNormalized      = 4,
  TakeFX_SetParamNormalized       = 4,
  TrackFX_SetParam                = 4,
  TakeFX_SetParam                 = 4,
  TrackFX_GetParamNormalized      = 3,
  TakeFX_GetParamNormalized       = 3,
  TrackFX_GetFormattedParamValue  = 4,
  TakeFX_GetFormattedParamValue   = 4,
  GetTrackSendInfo_Value          = 4,
  SetTrackSendInfo_Value          = 5,
  GetSet_LoopTimeRange            = 5,
  GetSet_LoopTimeRange2           = 6,
  TrackList_AdjustWindows         = 1,
}

function Code.find_reaper_arity_mismatches(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local seen, mismatches = {}, {}
  local function is_modern_marker_guarded_legacy_fallback(call_pos)
    if type(reaper) ~= "table"
       or type(reaper.AddRegionOrMarker) ~= "function" then
      return false
    end
    local guard_s, guard_e
    local pos = 1
    while true do
      local s, e = stripped:find(
        "if%s+reaper%.AddRegionOrMarker%s+then", pos)
      if not s or s > call_pos then break end
      guard_s, guard_e = s, e
      pos = e + 1
    end
    if not guard_s then return false end
    local segment = stripped:sub(guard_e + 1, call_pos - 1)
    local else_pos = segment:find("%f[%w]else%f[%W]")
    if not else_pos then return false end
    local end_pos = segment:find("%f[%w]end%f[%W]")
    return not (end_pos and end_pos < else_pos)
  end
  local pos = 1
  while true do
    local call_start, me, name = stripped:find("reaper%.([%w_]+)%s*%(", pos)
    if not me then break end
    local expected = _REAPER_FIXED_ARITY[name]
    if expected then
      -- Walk forward from me (the open paren) tracking bracket depth +
      -- string state. Comma at depth==1 separates top-level args.
      -- (), {}, [] all increment/decrement depth so a nested table
      -- literal `{1, 2, 3}` doesn't add false top-level commas.
      local depth, args = 1, 0
      local i = me + 1
      local in_str = nil  -- nil, '"', or "'"
      local saw_content = false
      while i <= #stripped do
        local c = stripped:sub(i, i)
        if in_str then
          if c == "\\" then
            i = i + 2  -- skip escape sequence
          else
            if c == in_str then in_str = nil end
            i = i + 1
          end
        else
          if c == '"' or c == "'" then
            in_str = c; saw_content = true
          elseif c == "(" or c == "[" or c == "{" then
            depth = depth + 1; saw_content = true
          elseif c == ")" or c == "]" or c == "}" then
            depth = depth - 1
            if depth == 0 then break end
          elseif c == "," and depth == 1 then
            args = args + 1
          elseif not c:match("%s") then
            saw_content = true
          end
          i = i + 1
        end
      end
      if depth == 0 then
        local got = saw_content and (args + 1) or 0
        local skip_guarded_legacy_marker =
          name == "AddProjectMarker"
          and got == 7
          and is_modern_marker_guarded_legacy_fallback(call_start)
        if got ~= expected and not skip_guarded_legacy_marker then
          local key = name .. ":" .. got
          if not seen[key] then
            seen[key] = true
            mismatches[#mismatches+1] =
              { name = name, expected = expected, got = got }
          end
        end
      end
    end
    pos = me + 1
  end
  if #mismatches == 0 then return nil end
  table.sort(mismatches, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.got < b.got
  end)
  return mismatches
end

function Code.find_addprojectmarker2_isrgn_misuse(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local findings = {}
  local pos = 1
  while true do
    local _ms, me = stripped:find("reaper%.AddProjectMarker2%s*%(", pos)
    if not me then break end
    local depth, args, field = 1, {}, {}
    local i = me + 1
    local in_str = nil
    while i <= #stripped do
      local c = stripped:sub(i, i)
      if in_str then
        field[#field + 1] = c
        if c == "\\" then
          i = i + 1
          if i <= #stripped then field[#field + 1] = stripped:sub(i, i) end
        elseif c == in_str then
          in_str = nil
        end
      else
        if c == '"' or c == "'" then
          in_str = c
          field[#field + 1] = c
        elseif c == "(" or c == "[" or c == "{" then
          depth = depth + 1
          field[#field + 1] = c
        elseif c == ")" or c == "]" or c == "}" then
          depth = depth - 1
          if depth == 0 then
            args[#args + 1] =
              table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
            break
          end
          field[#field + 1] = c
        elseif c == "," and depth == 1 then
          args[#args + 1] =
            table.concat(field):gsub("^%s+", ""):gsub("%s+$", "")
          field = {}
        else
          field[#field + 1] = c
        end
      end
      i = i + 1
    end
    local isrgn = args[2]
    local isrgn_ok = isrgn == "true" or isrgn == "false"
    if isrgn and not isrgn_ok then
      local normalized = isrgn:lower():gsub("^%s+", ""):gsub("%s+$", "")
      normalized = normalized:gsub("%s+", "")
      if normalized:match("^[%a_][%w_]*$") then
        isrgn_ok =
          normalized == "is_region"
          or normalized == "isregion"
          or normalized == "is_rgn"
          or normalized == "isrgn"
          or normalized == "is_region_flag"
      end
    end
    if isrgn and not isrgn_ok then
      local line = 1
      for _ in stripped:sub(1, me):gmatch("\n") do line = line + 1 end
      findings[#findings + 1] = {
        line = line,
        name = "AddProjectMarker2",
        expected = "boolean 2nd argument (false for marker, true for region)",
        got = isrgn,
      }
    end
    pos = me + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_media_item_p_name_misuse(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", function(s) return s:gsub("[^\n]", "") end)
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.GetSetMediaItemInfo_String%s*%(") then
    return nil
  end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local findings = {}
  local pos = 1
  while true do
    local s, e = stripped:find("reaper%.GetSetMediaItemInfo_String%s*%(", pos)
    if not s then break end
    local args = parse_args(e)
    local parm = args and args[2] or nil
    if parm and (parm == [["P_NAME"]] or parm == [['P_NAME']]) then
      findings[#findings + 1] = { line = line_for_pos(s), parm = parm }
    end
    pos = e + 1
  end
  if #findings == 0 then return nil end
  return findings
end

-- =============================================================================
-- Code.find_untracked_createtracksend_results
-- =============================================================================
-- CreateTrackSend returns the new send index. When a script creates multiple
-- sends from the same source track and then sets send properties using literal
-- indices (0/1/2), it can silently set the wrong send if REAPER orders sends
-- differently than the model assumed. Keep this intentionally narrow: only
-- flag standalone CreateTrackSend calls whose return value is ignored, paired
-- with later SetTrackSendInfo_Value calls on the same source track that use
-- hard-coded numeric send indices. Also flag repeated CreateTrackSend calls
-- for the same source/destination pair; models sometimes emit a discarded
-- CreateTrackSend(...) call immediately before the real assigned one, which
-- leaves the user with duplicate sends to the same return.
function Code.find_untracked_createtracksend_results(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function normalize_arg(v)
    return tostring(v or ""):gsub("%s+", "")
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local violations, seen = {}, {}
  local ignored_by_source = {}
  local assigned_sendidx = {}
  local creates_by_pair = {}
  local function is_generic_send_helper_pair(src, dst)
    local s = normalize_arg(src):lower()
    local d = normalize_arg(dst):lower()
    local generic_src = s == "src" or s == "source"
      or s == "source_track" or s == "srctrack"
    local generic_dst = d == "dst" or d == "dest"
      or d == "destination" or d == "dest_track"
      or d == "dsttrack" or d == "destination_track"
    return generic_src and generic_dst
  end
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.CreateTrackSend%s*%(", pos)
    if not s then break end
    local line_start = stripped:sub(1, s):match(".*()\n")
    line_start = line_start and (line_start + 1) or 1
    local prefix = stripped:sub(line_start, s - 1)
    local args = parse_args(open_pos)
    local lhs = prefix:match("^%s*local%s+(.+)%s*=%s*$")
      or prefix:match("^%s*(.-)%s*=%s*$")
    if args and args[1] and args[1] ~= "" and args[2] and args[2] ~= "" then
      local src = normalize_arg(args[1])
      local dst = normalize_arg(args[2])
      if not is_generic_send_helper_pair(args[1], args[2]) then
        local pair = src .. "=>" .. dst
        creates_by_pair[pair] = creates_by_pair[pair] or {
          source = args[1],
          dest = args[2],
          first_line = line_for_pos(s),
          count = 0,
        }
        creates_by_pair[pair].count = creates_by_pair[pair].count + 1
        if creates_by_pair[pair].count == 2 then
          local key = "duplicate:" .. pair
          if not seen[key] then
            seen[key] = true
            violations[#violations + 1] = {
              kind = "duplicate",
              source = args[1],
              dest = args[2],
              create_line = creates_by_pair[pair].first_line,
              set_line = line_for_pos(s),
            }
          end
        end
      end
    end
    if lhs and lhs:find(",", 1, true) then
      local key = "multi_assign:" .. tostring(line_for_pos(s))
      if not seen[key] then
        seen[key] = true
        violations[#violations + 1] = {
          kind = "multi_assign",
          source = args and args[1] or "",
          sendidx = lhs,
          create_line = line_for_pos(s),
          set_line = line_for_pos(s),
        }
      end
    elseif prefix:match("^%s*$") then
      if args and args[1] and args[1] ~= "" then
        local src = normalize_arg(args[1])
        ignored_by_source[src] = ignored_by_source[src] or {}
        ignored_by_source[src][#ignored_by_source[src] + 1] = {
          pos = s,
          line = line_for_pos(s),
        }
      end
    elseif lhs then
      local var = lhs:match("^%s*([%a_][%w_]*)%s*$")
      if var and args and args[1] and args[1] ~= "" then
        assigned_sendidx[var] = {
          source = args[1],
          create_line = line_for_pos(s),
        }
      end
    end
    pos = open_pos + 1
  end

  for var, create in pairs(assigned_sendidx) do
    local esc = var:gsub("([^%w_])", "%%%1")
    local bad_s, bad_e = stripped:find("%f[%w_]if%s+[^\n]-" .. esc
      .. "%s*~=%s*0%f[^%w_]")
    if not bad_s then
      bad_s, bad_e = stripped:find("%f[%w_]if%s+[^\n]-" .. esc
        .. "%s*>%s*0%f[^%w_]")
    end
    if bad_s and create.create_line and line_for_pos(bad_s) >= create.create_line then
      local key = "zero_check:" .. tostring(var) .. ":" .. tostring(line_for_pos(bad_s))
      if not seen[key] then
        seen[key] = true
        violations[#violations + 1] = {
          kind = "zero_check",
          source = create.source,
          sendidx = var,
          create_line = create.create_line,
          set_line = line_for_pos(bad_s),
        }
      end
    end
  end

  pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.SetTrackSendInfo_Value%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    if args and args[1] and args[3] then
      local src = normalize_arg(args[1])
      local creates = ignored_by_source[src]
      local sendidx = tostring(args[3]):match("^%s*(.-)%s*$") or ""
      if creates and sendidx:match("^%d+$") then
        local risky = tonumber(sendidx) ~= 0 or #creates > 1
        local follows_create = false
        local create_line = nil
        for _, c in ipairs(creates) do
          if c.pos < s then
            follows_create = true
            create_line = create_line or c.line
          end
        end
        if risky and follows_create then
          local key = src .. ":" .. sendidx
          if not seen[key] then
            seen[key] = true
            violations[#violations + 1] = {
              source = args[1],
              sendidx = sendidx,
              create_line = create_line,
              set_line = line_for_pos(s),
            }
          end
        end
      end
    end
    pos = open_pos + 1
  end

  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.set_line ~= b.set_line then return a.set_line < b.set_line end
    return tostring(a.source) < tostring(b.source)
  end)
  return violations
end

function Code.find_hardware_send_category_misuse(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end

  local function normalize_arg(v)
    return trim(v):gsub("%s+", "")
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local hardware_send_vars = {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.CreateTrackSend%s*%(", pos)
    if not s then break end
    local line_start = stripped:sub(1, s):match(".*()\n")
    line_start = line_start and (line_start + 1) or 1
    local prefix = stripped:sub(line_start, s - 1)
    local args = parse_args(open_pos)
    local lhs = prefix:match("^%s*local%s+(.+)%s*=%s*$")
      or prefix:match("^%s*(.-)%s*=%s*$")
    if args and args[1] and normalize_arg(args[2]):lower() == "nil" then
      local var = lhs and lhs:match("^%s*([%a_][%w_]*)%s*$")
      if var then
        hardware_send_vars[var] = {
          source = normalize_arg(args[1]),
          raw_source = args[1],
          create_line = line_for_pos(s),
        }
      end
    end
    pos = open_pos + 1
  end

  local findings, seen = {}, {}
  pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.SetTrackSendInfo_Value%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    local category = args and normalize_arg(args[2]) or ""
    local sendidx = args and normalize_arg(args[3]) or ""
    local hw = hardware_send_vars[sendidx]
    if category == "0" and hw then
      local key = sendidx
      if not seen[key] then
        seen[key] = true
        findings[#findings + 1] = {
          kind = "hardware_category",
          source = hw.raw_source,
          sendidx = sendidx,
          create_line = hw.create_line,
          set_line = line_for_pos(s),
        }
      end
    end
    pos = open_pos + 1
  end

  if #findings == 0 then return nil end
  return findings
end

function Code.find_timecode_generator_workflow_misuse(lua_code, user_prompt)
  if not lua_code or lua_code == "" then return nil end
  if not (CTX and type(CTX.prompt_indicates_timecode_generator) == "function"
      and CTX.prompt_indicates_timecode_generator(user_prompt)) then
    return nil
  end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end

  local function normalize_arg(v)
    return trim(v):gsub("%s+", "")
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function action_lookup_words(condition)
    condition = tostring(condition or ""):lower()
    return {
      generator = condition:find("generator", 1, true) ~= nil,
      timecode = condition:find("timecode", 1, true) ~= nil
        or condition:find("time code", 1, true) ~= nil,
      smpte = condition:find("smpte", 1, true) ~= nil,
      ltc = condition:find("%f[%w]ltc%f[%W]") ~= nil,
      mtc = condition:find("%f[%w]mtc%f[%W]") ~= nil,
      has_or = condition:find("%f[%w]or%f[%W]") ~= nil,
    }
  end

  local function has_broad_action_lookup_condition()
    local pos = 1
    while true do
      local s, e, cond = stripped:find("%f[%w]if%s+(.-)%s+then%f[%W]", pos)
      if not s then break end
      local words = action_lookup_words(cond)
      if words.generator then
        if words.timecode and not (words.smpte or words.ltc or words.mtc) then
          return true
        end
        if words.smpte and not (words.timecode or words.ltc or words.mtc) then
          return true
        end
        if words.ltc and not (words.timecode or words.smpte or words.mtc) then
          return true
        end
        if words.mtc and not (words.timecode or words.smpte or words.ltc) then
          return true
        end
      end
      pos = e + 1
    end

    local compact = stripped:lower():gsub("%s+", "")
    for _, pair in ipairs({
      { "timecode", "generator" },
      { "generator", "timecode" },
      { "smpte", "generator" },
      { "generator", "smpte" },
      { "ltc", "generator" },
      { "generator", "ltc" },
      { "mtc", "generator" },
      { "generator", "mtc" },
    }) do
      local a, b = pair[1], pair[2]
      if compact:find('{"' .. a .. '","' .. b .. '"', 1, true)
          or compact:find("{'" .. a .. "','" .. b .. "'", 1, true) then
        return true
      end
    end

    return false
  end

  local function overconstrained_action_lookup()
    if not stripped:find("reaper%.kbd_enumerateActions%s*%(") then
      return nil
    end

    local has_broad_lookup = has_broad_action_lookup_condition()
    local first_strict = nil
    local pos = 1
    while true do
      local s, e, cond = stripped:find("%f[%w]if%s+(.-)%s+then%f[%W]", pos)
      if not s then break end
      local words = action_lookup_words(cond)
      local requires_specific_family =
        (words.smpte or words.ltc or words.mtc) and words.timecode
      if words.generator and requires_specific_family and not words.has_or then
        first_strict = first_strict or s
      end
      pos = e + 1
    end

    if first_strict and not has_broad_lookup then
      return {
        kind = "overconstrained_action_lookup",
        line = line_for_pos(first_strict),
      }
    end
    return nil
  end

  local function has_generated_item_track_detection(after_pos)
    local tail = stripped:sub(after_pos or 1)
    if tail:find("reaper%.GetMediaItemTrack%s*%(")
        or tail:find("reaper%.GetMediaItem_Track%s*%(") then
      return true
    end
    return false
  end

  local function has_generated_item_move(after_pos)
    local tail = stripped:sub(after_pos or 1)
    return tail:find("reaper%.MoveMediaItemToTrack%s*%(") ~= nil
  end

  local findings = {}
  local lookup_bad = overconstrained_action_lookup()
  if lookup_bad then findings[#findings + 1] = lookup_bad end
  local first_action = nil
  local action_pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.Main_OnCommand%s*%(", action_pos)
    if not s then break end
    local args = parse_args(open_pos)
    if normalize_arg(args and args[1]) ~= "40297" then
      first_action = s
      break
    end
    action_pos = open_pos + 1
  end
  local first_hw_send = nil
  local send_pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.CreateTrackSend%s*%(", send_pos)
    if not s then break end
    local args = parse_args(open_pos)
    if normalize_arg(args and args[2]):lower() == "nil" then
      first_hw_send = s
      break
    end
    send_pos = open_pos + 1
  end
  if first_action
      and stripped:find("reaper%.InsertTrackAtIndex%s*%(")
      and type(Code.lua_satisfies_exclusive_track_selection) == "function"
      and not Code.lua_satisfies_exclusive_track_selection(lua_code) then
    findings[#findings + 1] = {
      kind = "missing_exclusive_selection",
      line = line_for_pos(first_action),
    }
  end
  if first_action and first_hw_send and first_hw_send < first_action then
    findings[#findings + 1] = {
      kind = "route_before_action",
      line = line_for_pos(first_hw_send),
    }
  end
  local first_insert = first_action
    and stripped:find("reaper%.InsertTrackAtIndex%s*%(") or nil
  local precreated_track = first_insert and first_insert < first_action
  if precreated_track then
    findings[#findings + 1] = {
      kind = "precreated_track_before_timecode_action",
      line = line_for_pos(first_insert),
    }
  end
  if first_action and first_hw_send and first_hw_send > first_action then
    local detects_item_track = has_generated_item_track_detection(first_action)
    local moves_item = has_generated_item_move(first_action)
    if precreated_track then
      if not (detects_item_track or moves_item) then
        findings[#findings + 1] = {
          kind = "missing_generated_item_track_detection",
          line = line_for_pos(first_hw_send),
        }
      elseif not moves_item then
        findings[#findings + 1] = {
          kind = "precreated_track_without_item_move",
          line = line_for_pos(first_hw_send),
        }
      end
    elseif not detects_item_track then
      findings[#findings + 1] = {
        kind = "missing_generated_item_track_detection",
        line = line_for_pos(first_hw_send),
      }
    end
  end

  local category_bad = Code.find_hardware_send_category_misuse(lua_code)
  if category_bad then
    for _, finding in ipairs(category_bad) do
      findings[#findings + 1] = finding
    end
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    local la = a.line or a.set_line or a.create_line or 0
    local lb = b.line or b.set_line or b.create_line or 0
    if la ~= lb then return la < lb end
    return tostring(a.kind) < tostring(b.kind)
  end)
  return findings
end

function Code.find_ruler_lane_timebase_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("RULER_LANE_TIMEBASE", 1, true) then return nil end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end

  local function normalize_arg(v)
    return trim(v):gsub("%s+", "")
  end

  local function unquote(v)
    v = trim(v)
    local q = v:sub(1, 1)
    if (q == '"' or q == "'") and v:sub(-1) == q then
      return v:sub(2, -2)
    end
    return nil
  end

  local function literal_number(v)
    v = normalize_arg(v)
    if v:match("^%-?%d+%.?%d*$") then return tonumber(v) end
    return nil
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function prompt_is_timeline_ruler_display()
    local text = tostring(user_text or ""):lower():gsub("%s+", " ")
    if text == "" then return false end
    if text:find("ruler lane", 1, true)
       or text:find("marker lane", 1, true)
       or text:find("region lane", 1, true) then
      return false
    end
    local has_ruler = text:find("%f[%w]ruler%f[%W]") ~= nil
    if not has_ruler then return false end
    return text:find("%f[%w]main%f[%W]") ~= nil
        or text:find("%f[%w]primary%f[%W]") ~= nil
        or text:find("%f[%w]secondary%f[%W]") ~= nil
        or text:find("time unit", 1, true) ~= nil
        or text:find("timebase", 1, true) ~= nil
        or text:find("time base", 1, true) ~= nil
        or text:find("timecode", 1, true) ~= nil
        or text:find("h:m:s:f", 1, true) ~= nil
        or text:find("measures:beats", 1, true) ~= nil
        or text:find("measures.beats", 1, true) ~= nil
  end

  local function has_verified_ruler_display_action()
    return stripped:find("reaper%.Main_OnCommand%s*%(%s*40367%s*,", 1, false)
        or stripped:find("reaper%.Main_OnCommand%s*%(%s*42364%s*,", 1, false)
        or (stripped:find("reaper%.kbd_enumerateActions%s*%(", 1, false)
          and stripped:lower():find("time unit for ruler", 1, true))
  end

  local calls, findings = {}, {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.GetSetProjectInfo%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    local key = args and unquote(args[2]) or nil
    if key and key:match("^RULER_LANE_TIMEBASE:%d+$")
       and normalize_arg(args[4]):lower() == "true" then
      local call = {
        key = key,
        line = line_for_pos(s),
        value = args[3],
      }
      calls[#calls + 1] = call
      -- Non-literal values are intentionally allowed unless the user prompt is
      -- asking for main/secondary timeline ruler display rather than lane data.
      local n = literal_number(args[3])
      if n and (n < -1 or n > 2 or n % 1 ~= 0) then
        findings[#findings + 1] = {
          kind = "invalid_value",
          key = key,
          value = args[3],
          line = call.line,
        }
      end
    end
    pos = open_pos + 1
  end

  if #calls > 0 and #findings == 0
     and prompt_is_timeline_ruler_display()
     and not has_verified_ruler_display_action() then
    local call = calls[1]
    findings[#findings + 1] = {
      kind = "display_domain",
      key = call.key,
      value = call.value,
      line = call.line,
    }
  end

  return #findings > 0 and findings or nil
end

-- =============================================================================
-- Code.find_master_send_remove_misuse
-- =============================================================================
-- Master/parent send is not a normal send slot. Removing category 1 sends removes
-- hardware outputs; the master/parent send lives on B_MAINSEND.
function Code.prompt_requests_master_send_change(user_text)
  if Code._typed_action_user_requests_master_send_state
     and Code._typed_action_user_requests_master_send_state(user_text) then
    return true
  end
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  return lt:find("master send", 1, true) ~= nil
    or lt:find("master sends", 1, true) ~= nil
    or lt:find("main send", 1, true) ~= nil
    or lt:find("main sends", 1, true) ~= nil
    or lt:find("master/parent", 1, true) ~= nil
    or lt:find("master parent", 1, true) ~= nil
    or lt:find("parent send", 1, true) ~= nil
    or lt:find("parent sends", 1, true) ~= nil
    or lt:find("master output", 1, true) ~= nil
    or lt:find("master_send", 1, true) ~= nil
    or lt:find("going only to the master", 1, true) ~= nil
    or lt:find("only goes to master", 1, true) ~= nil
    or lt:find("only to the master", 1, true) ~= nil
end

function Code.find_master_send_remove_misuse(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local one_vars = {}
  for name in stripped:gmatch("%f[%w_]local%s+([%a_][%w_]*)%s*=%s*1%f[^%w_]") do
    local ln = name:lower()
    if ln:find("master", 1, true)
        or ln:find("send", 1, true)
        or ln:find("cat", 1, true)
        or ln:find("category", 1, true) then
      one_vars[name] = true
    end
  end

  local violations, seen = {}, {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.RemoveTrackSend%s*%(", pos)
    if not s then break end
    local depth, i = 1, open_pos + 1
    local field, args, in_str = {}, {}, nil
    while i <= #stripped do
      local c = stripped:sub(i, i)
      if in_str then
        field[#field + 1] = c
        if c == "\\" then
          i = i + 1
          if i <= #stripped then field[#field + 1] = stripped:sub(i, i) end
        elseif c == in_str then
          in_str = nil
        end
      else
        if c == '"' or c == "'" then
          in_str = c
          field[#field + 1] = c
        elseif c == "(" or c == "[" or c == "{" then
          depth = depth + 1
          field[#field + 1] = c
        elseif c == ")" or c == "]" or c == "}" then
          depth = depth - 1
          if depth == 0 then
            args[#args + 1] = table.concat(field):match("^%s*(.-)%s*$") or ""
            break
          end
          field[#field + 1] = c
        elseif c == "," and depth == 1 then
          args[#args + 1] = table.concat(field):match("^%s*(.-)%s*$") or ""
          field = {}
        else
          field[#field + 1] = c
        end
      end
      i = i + 1
    end
    local category = args[2] and args[2]:match("^%s*(.-)%s*$") or ""
    if category == "1" or one_vars[category] then
      local key = tostring(line_for_pos(s)) .. ":" .. category
      if not seen[key] then
        seen[key] = true
        violations[#violations + 1] = {
          line = line_for_pos(s),
          category = category,
        }
      end
    end
    pos = open_pos + 1
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.prompt_requests_track_pan(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if lt:find("send pan", 1, true)
      or lt:find("pan the send", 1, true)
      or lt:find("pan send", 1, true) then
    return false
  end
  return lt:find("%f[%w]pan%f[%W]") ~= nil
    or lt:find("%f[%w]panner%f[%W]") ~= nil
    or lt:find("%f[%w]autopan%f[%W]") ~= nil
    or lt:find("auto%-pan") ~= nil
    or lt:find("percent left", 1, true) ~= nil
    or lt:find("percent right", 1, true) ~= nil
end

function Code.prompt_needs_pan_lfo_rate_clarification(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if not Code.prompt_requests_track_pan(lt) then return false end
  local has_lfo =
    lt:find("%f[%w]lfo%f[%W]") ~= nil
    or lt:find("%f[%w]autopan%f[%W]") ~= nil
    or lt:find("auto%-pan") ~= nil
    or lt:find("%f[%w]sine%f[%W]") ~= nil
    or lt:find("%f[%w]oscillat") ~= nil
  if not has_lfo then return false end
  if not (lt:find("%d+%s*bar%f[%W]")
      or lt:find("%d+%s*bars%f[%W]")) then
    return false
  end
  local hz = nil
  for n in lt:gmatch("%f[%w](%d+%.?%d*)%s*hz%f[%W]") do
    hz = tonumber(n)
    break
  end
  if not hz or hz < 15 then return false end
  if lt:find("%f[%w]jsfx%f[%W]")
      or lt:find("%f[%w]plugin%f[%W]") then
    return false
  end
  return true, hz
end

function Code.prompt_needs_reaverb_control_clarification(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if not lt:find("%f[%w]reaverb%f[%W]") then return false end
  local has_unsupported_control =
    lt:find("%f[%w]plate%f[%W]") ~= nil
    or lt:find("%f[%w]decay%f[%W]") ~= nil
    or lt:find("decay time", 1, true) ~= nil
  if not has_unsupported_control then return false end
  return lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]apply%f[%W]") ~= nil
    or lt:find("%f[%w]configure%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]make%f[%W]") ~= nil
    or lt:find("%f[%w]set%f[%W]") ~= nil
    or lt:find("%f[%w]use%f[%W]") ~= nil
end

function Code.find_track_pan_sent_as_send_pan(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_track_pan(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']D_PAN[\"']") then
    return nil
  end
  local violations = {}
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local pos = 1
  while true do
    local s = stripped:find("reaper%.SetTrackSendInfo_Value%s*%([^%)]-[\"']D_PAN[\"']", pos)
    if not s then break end
    violations[#violations + 1] = { line = line_for_pos(s) }
    pos = s + 1
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.find_track_pan_bare_handle_table_key_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_track_pan(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']D_PAN[\"']") then
    return nil
  end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local violations = {}
  local pos = 1
  while true do
    local s, e, table_name, body = stripped:find(
      "local%s+([%a_][%w_]*)%s*=%s*{%s*(.-)%s*}", pos)
    if not s then break end
    if body:find("%[%s*[%a_][%w_]*%s*%]%s*=")
        and stripped:find(
          "reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']D_PAN[\"'][^%)]-"
          .. table_name .. "%s*%[") then
      local bare_keys = {}
      local bpos = 1
      while true do
        local bs, be, key = body:find("([%a_][%w_]*)%s*=", bpos)
        if not bs then break end
        local prev = body:sub(1, bs - 1):match("(%S)%s*$")
        if prev ~= "[" then
          bare_keys[#bare_keys + 1] = key
        end
        bpos = be + 1
      end
      if #bare_keys > 0 then
        violations[#violations + 1] = {
          line = line_for_pos(s),
          table_name = table_name,
          bare_keys = bare_keys,
        }
      end
    end
    pos = e + 1
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.prompt_requests_exclusive_track_selection(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if lt:find("select only", 1, true) then return true end
  if lt:find("only select", 1, true) then return true end
  if lt:find("%f[%w]make%s+only%s+the%s+.-%s+selected%f[%W]") then return true end
  if lt:find("%f[%w]leave%s+only%s+the%s+.-%s+selected%f[%W]") then return true end
  if lt:find("%f[%w]keep%s+only%s+the%s+.-%s+selected%f[%W]") then return true end
  return false
end

function Code.lua_satisfies_exclusive_track_selection(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.SetOnlyTrackSelected%s*%(") then return true end
  if not stripped:find("reaper%.SetTrackSelected%s*%(") then return false end
  local has_select = stripped:find(
    "reaper%.SetTrackSelected%s*%(.-,%s*true%s*%)") ~= nil
  local has_unselect = stripped:find(
    "reaper%.SetTrackSelected%s*%(.-,%s*false%s*%)") ~= nil
  local has_unselect_command = stripped:find(
    "reaper%.Main_OnCommand%s*%(%s*40297%s*,") ~= nil
  return has_select and (has_unselect or has_unselect_command)
end

function Code.prompt_requests_bus_or_return_send_routing(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  local routing_text = lt
  for _, phrase in ipairs({
    "master/parent send",
    "master parent send",
    "master send",
    "parent send",
    "main send",
  }) do
    routing_text = routing_text:gsub(phrase, "")
  end
  for _, pat in ipairs({
    "%f[%w]do%s+not%s+[^%.%!%?;]*routing[^%.%!%?;]*",
    "%f[%w]don't%s+[^%.%!%?;]*routing[^%.%!%?;]*",
    "%f[%w]dont%s+[^%.%!%?;]*routing[^%.%!%?;]*",
    "%f[%w]without%s+[^%.%!%?;]*routing[^%.%!%?;]*",
    "%f[%w]no%s+routing%s+changes?%f[%W]",
    "%f[%w]do%s+not%s+[^%.%!%?;]*route[^%.%!%?;]*",
    "%f[%w]don't%s+[^%.%!%?;]*route[^%.%!%?;]*",
    "%f[%w]dont%s+[^%.%!%?;]*route[^%.%!%?;]*",
    "%f[%w]without%s+[^%.%!%?;]*route[^%.%!%?;]*",
  }) do
    routing_text = routing_text:gsub(pat, "")
  end
  local mentions_bus_or_return =
    lt:find("%f[%w]bus%f[%W]") ~= nil
    or lt:find("%f[%w]buses%f[%W]") ~= nil
    or lt:find("%f[%w]return%f[%W]") ~= nil
    or lt:find("%f[%w]returns%f[%W]") ~= nil
  if not mentions_bus_or_return then return false end
  local routing_phrases = {
    "send ",
    " sends ",
    "sent to",
    "route ",
    " routed ",
    "routing",
    "going into",
    "go into",
    "goes into",
    "into a ",
    "into the ",
    "shared ",
  }
  for _, phrase in ipairs(routing_phrases) do
    if routing_text:find(phrase, 1, true) then return true end
  end
  return false
end

function Code.lua_satisfies_bus_or_return_send_routing(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  return stripped:find("reaper%.CreateTrackSend%s*%(") ~= nil
end

function Code.extract_sidechain_ducking_send_request(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  local has_sidechain_word =
       lt:find("%f[%w]duck%f[%W]") ~= nil
    or lt:find("%f[%w]ducks%f[%W]") ~= nil
    or lt:find("%f[%w]ducking%f[%W]") ~= nil
    or lt:find("%f[%w]sidechain%f[%W]") ~= nil
    or lt:find("%f[%w]side%-chain%f[%W]") ~= nil
  if not has_sidechain_word then return nil end

  local function clause_has_sidechain_word(clause)
    clause = tostring(clause or "")
    return clause:find("%f[%w]ducks%f[%W]") ~= nil
      or clause:find("%f[%w]ducking%f[%W]") ~= nil
      or clause:find("%f[%w]sidechain%f[%W]") ~= nil
      or clause:find("%f[%w]side%-chain%f[%W]") ~= nil
  end

  local function clean_endpoint(s)
    s = tostring(s or ""):lower()
    s = s:gsub("%s+for%s+side%-?chain.*$", "")
    s = s:gsub("%s+for%s+duck.*$", "")
    s = s:gsub("%s+feeding%s+.*$", "")
    s = s:gsub("%s+on%s+channels.*$", "")
    s = s:gsub("%s+at%s+[%-+]?%d+%.?%d*%s*d?b.*$", "")
    s = s:gsub("^%s*the%s+", "")
    s = s:gsub("^%s*a%s+", "")
    s = s:gsub("^%s*an%s+", "")
    s = s:gsub("%s+track%s*$", "")
    s = s:gsub("%s+tracks%s*$", "")
    s = s:gsub("[%.;,].*$", "")
    return s:match("^%s*(.-)%s*$")
  end

  local function split_sources(s)
    local parts, seen = {}, {}
    s = tostring(s or ""):gsub("%s+and%s+", ",")
    for part in s:gmatch("[^,]+") do
      part = clean_endpoint(part)
      if part ~= "" and not seen[part] then
        seen[part] = true
        parts[#parts + 1] = part
      end
    end
    return parts
  end

  local src, dst
  for clause in lt:gmatch("[^%.;,]+") do
    if clause_has_sidechain_word(clause) then
      src, dst = clause:match("%f[%w]send%s+from%s+(.-)%s+to%s+(.+)$")
      if not src then
        src, dst = clause:match("%f[%w]route%s+(.-)%s+to%s+(.+)$")
      end
      if src and dst then break end
    end
  end
  src, dst = clean_endpoint(src), clean_endpoint(dst)
  if src ~= "" and dst ~= "" and src ~= dst then
    local sources = split_sources(src)
    if #sources == 0 then sources = { src } end
    return { source = src, sources = sources, dest = dst }
  end
  return nil
end

function Code.prompt_requests_sidechain_ducking(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if Code.extract_sidechain_ducking_send_request(user_text) then return true end
  local has_kick = lt:find("%f[%w]kick%f[%W]") ~= nil
  local has_bass = lt:find("%f[%w]bass%f[%W]") ~= nil
  if not (has_kick and has_bass) then return false end
  return lt:find("%f[%w]duck%f[%W]") ~= nil
    or lt:find("%f[%w]ducks%f[%W]") ~= nil
    or lt:find("%f[%w]ducking%f[%W]") ~= nil
    or lt:find("%f[%w]sidechain%f[%W]") ~= nil
    or lt:find("%f[%w]side%-chain%f[%W]") ~= nil
end

function Code.lua_satisfies_sidechain_ducking_send(lua_code, user_text)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local lowered = stripped:lower()
  local explicit = Code.extract_sidechain_ducking_send_request
    and Code.extract_sidechain_ducking_send_request(user_text) or nil
  local explicit_sources = nil
  if explicit then
    explicit_sources = type(explicit.sources) == "table"
      and explicit.sources or { explicit.source }
  end
  local aliases = explicit and { dest = {} } or { kick = {}, bass = {} }
  if explicit then
    for i = 1, #explicit_sources do
      aliases["source" .. tostring(i)] = {}
    end
  end
  local function compact(s)
    return tostring(s or ""):lower():gsub("[^%w]", "")
  end
  local function add_alias(role, value)
    value = tostring(value or ""):lower():match("^%s*(.-)%s*$")
    if value ~= "" then aliases[role][value] = true end
    local cv = compact(value)
    if cv ~= "" then aliases[role][cv] = true end
  end
  local function add_endpoint_variants(role, value)
    value = tostring(value or ""):lower()
    local acronym = ""
    for word in value:gmatch("%w+") do
      if #word >= 3 then add_alias(role, word) end
      acronym = acronym .. word:sub(1, 1)
    end
    if #acronym >= 2 then add_alias(role, acronym) end
    if value:find("voiceover", 1, true) then
      add_alias(role, "voice")
      add_alias(role, "vo")
    end
  end
  if explicit then
    add_alias("dest", explicit.dest)
    add_endpoint_variants("dest", explicit.dest)
    for i, source in ipairs(explicit_sources) do
      local role = "source" .. tostring(i)
      add_alias(role, source)
      add_endpoint_variants(role, source)
    end
  end
  local function short_alias_matches(text_value, alias)
    local norm = "_" .. tostring(text_value or "")
      :lower():gsub("[^%w]+", "_") .. "_"
    return norm:find("_" .. alias .. "_", 1, true) ~= nil
  end
  local function role_for_text(text_value)
    local cv = compact(text_value)
    if explicit then
      for i = 1, #explicit_sources do
        local role = "source" .. tostring(i)
        for alias in pairs(aliases[role]) do
          local ca = compact(alias)
          if ca ~= "" and ((#ca <= 2 and short_alias_matches(text_value, ca))
              or (#ca > 2 and cv:find(ca, 1, true))) then
            return role
          end
        end
      end
      for alias in pairs(aliases.dest) do
        local ca = compact(alias)
        if ca ~= "" and ((#ca <= 2 and short_alias_matches(text_value, ca))
            or (#ca > 2 and cv:find(ca, 1, true))) then
          return "dest"
        end
      end
      return nil
    end
    if text_value:find("kick", 1, true) then return "kick" end
    if text_value:find("bass", 1, true) then return "bass" end
    return nil
  end
  for name in lowered:gmatch("[%a_][%w_]*") do
    local role = role_for_text(name)
    if role then add_alias(role, name) end
  end
  for lhs, quoted in lowered:gmatch(
      "([%a_][%w_]*)%s*=%s*.-[\"']([^\"']+)[\"']") do
    local role = role_for_text(quoted)
    if role then add_alias(role, lhs) end
  end
  for var, quoted in lowered:gmatch(
      "getsetmediatrackinfo_string%s*%(%s*([%a_][%w_]*)%s*,%s*[\"']p_name[\"']%s*,%s*[\"']([^\"']+)[\"']") do
    local role = role_for_text(quoted)
    if role then add_alias(role, var) end
  end
  local named_tables = {}
  for table_var, body in lowered:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*%{(.-)%}") do
    local entries = {}
    for quoted in tostring(body or ""):gmatch("[\"']([^\"']+)[\"']") do
      entries[#entries + 1] = quoted
    end
    if #entries > 0 then named_tables[table_var] = entries end
  end
  for source_table, entries in pairs(named_tables) do
    local indexed_pattern = "([%a_][%w_]*)%s*%[%s*i%s*%]%s*="
    if lowered:find("ipairs%s*%(%s*" .. source_table .. "%s*%)")
        or lowered:find("for%s+[%a_][%w_]*%s*=%s*1%s*,%s*#%s*"
          .. source_table) then
      for target_table in lowered:gmatch(indexed_pattern) do
        for idx, quoted in ipairs(entries) do
          local role = role_for_text(quoted)
          if role then
            add_alias(role, target_table .. "[" .. tostring(idx) .. "]")
          end
        end
      end
    end
  end
  for names_var, entries in pairs(named_tables) do
    local direct_pat =
      "getsetmediatrackinfo_string%s*%(%s*([%a_][%w_]*)%[%s*([%a_][%w_]*)%s*%]%s*,%s*[\"']p_name[\"']%s*,%s*"
      .. names_var .. "%[%s*([%a_][%w_]*)%s*%]"
    for track_table, track_idx_var, name_idx_var in lowered:gmatch(direct_pat) do
      if track_idx_var == name_idx_var then
        for idx, quoted in ipairs(entries) do
          local role = role_for_text(quoted)
          if role then
            add_alias(role, track_table .. "[" .. tostring(idx) .. "]")
          end
        end
      end
    end
    local offset_pat =
      "getsetmediatrackinfo_string%s*%(%s*([%a_][%w_]*)%[%s*([%a_][%w_]*)%s*%]%s*,%s*[\"']p_name[\"']%s*,%s*"
      .. names_var .. "%[%s*([%a_][%w_]*)%s*%+%s*1%s*%]"
    for track_table, track_idx_var, name_idx_var in lowered:gmatch(offset_pat) do
      if track_idx_var == name_idx_var then
        for idx, quoted in ipairs(entries) do
          local role = role_for_text(quoted)
          if role then
            add_alias(role, track_table .. "[" .. tostring(idx - 1) .. "]")
          end
        end
      end
    end
  end
  local function expr_matches_role(expr, role)
    expr = tostring(expr or ""):lower()
    if not explicit and expr:find(role, 1, true) then return true end
    local cexpr = compact(expr)
    for alias in pairs(aliases[role]) do
      if #alias <= 1 then
        for token in expr:gmatch("[%a_][%w_]*") do
          if token == alias then return true end
        end
      elseif #alias <= 2 then
        if short_alias_matches(expr, alias) then return true end
      elseif expr:find(alias, 1, true)
          or (cexpr ~= "" and cexpr:find(compact(alias), 1, true)) then
        return true
      end
    end
    return false
  end
  for _ = 1, 3 do
    for lhs, rhs in lowered:gmatch(
        "local%s+([%a_][%w_]*)%s*=%s*([^\n]+)") do
      if explicit then
        for i = 1, #explicit_sources do
          local role = "source" .. tostring(i)
          if expr_matches_role(rhs, role) then add_alias(role, lhs) end
        end
        if expr_matches_role(rhs, "dest") then add_alias("dest", lhs) end
      else
        if expr_matches_role(rhs, "kick") then add_alias("kick", lhs) end
        if expr_matches_role(rhs, "bass") then add_alias("bass", lhs) end
      end
    end
  end
  local send_count = 0
  local exact_send = false
  local explicit_matches = {}
  local function note_send(src, dst)
    send_count = send_count + 1
    if explicit then
      for i = 1, #explicit_sources do
        local role = "source" .. tostring(i)
        if expr_matches_role(src, role) and expr_matches_role(dst, "dest") then
          explicit_matches[role] = true
        end
      end
    elseif expr_matches_role(src, "kick") and expr_matches_role(dst, "bass") then
      exact_send = true
    end
  end
  for src, dst in lowered:gmatch(
      "reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
    note_send(src, dst)
  end
  local send_helpers = {}
  local function local_function_body(start_pos)
    local depth = 1
    local pos = start_pos
    while true do
      local s, e, word = lowered:find("([%a_][%w_]*)", pos)
      if not s then return lowered:sub(start_pos) end
      if word == "function" or word == "do" or word == "then" then
        depth = depth + 1
      elseif word == "end" then
        depth = depth - 1
        if depth == 0 then return lowered:sub(start_pos, s - 1) end
      end
      pos = e + 1
    end
  end
  local helper_pos = 1
  while true do
    local s, e, fname = lowered:find(
      "local%s+function%s+([%a_][%w_]*)%s*%b()%s*", helper_pos)
    if not s then break end
    local body = local_function_body(e + 1)
    if body:find("reaper%.createtracksend%s*%(") then
      send_helpers[fname] = true
    end
    helper_pos = e + 1
  end
  for fname, args in lowered:gmatch("([%a_][%w_]*)%s*%(([^%)]*)%)") do
    if send_helpers[fname] then
      local src, dst = tostring(args or ""):match("^%s*([^,]+)%s*,%s*([^,]+)")
      if src and dst then note_send(src, dst) end
    end
  end
  if explicit then
    for i = 1, #explicit_sources do
      if not explicit_matches["source" .. tostring(i)] then return false end
    end
    return #explicit_sources > 0
  end
  return exact_send
end

function Code.prompt_requests_podcast_bus_all_sources(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  return lt:find("%f[%w]host%f[%W]") ~= nil
    and lt:find("%f[%w]guest%f[%W]") ~= nil
    and lt:find("%f[%w]music%f[%W]") ~= nil
    and lt:find("%f[%w]bus%f[%W]") ~= nil
end

function Code.lua_satisfies_podcast_bus_all_sources(lua_code, user_text)
  if not lua_code or lua_code == "" then return false end
  local prompt = tostring(user_text or ""):lower():gsub("%s+", " ")
  local wants_multi_bus =
       prompt:find("dialog bus", 1, true) ~= nil
    or prompt:find("music bus", 1, true) ~= nil
    or prompt:find("fx bus", 1, true) ~= nil
    or prompt:find("print mix", 1, true) ~= nil
  local wants_sfx =
       prompt:find("%f[%w]sfx%f[%W]") ~= nil
    or prompt:find("fx bus", 1, true) ~= nil
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local lowered = stripped:lower()
  local roles = { "host", "guest", "music" }
  if wants_sfx then roles[#roles + 1] = "sfx" end
  local aliases = {
    host = {}, guest = {}, music = {}, sfx = {},
    bus = {}, dialog_bus = {}, music_bus = {}, fx_bus = {}, print_mix = {},
  }
  local function add_alias(role, value)
    value = tostring(value or ""):lower():match("^%s*(.-)%s*$")
    if value ~= "" then aliases[role][value] = true end
    local compact = value:gsub("[^%w]", "")
    if compact ~= "" then aliases[role][compact] = true end
  end
  local function add_named_aliases(value, role_hint)
    value = tostring(value or ""):lower()
    if role_hint then add_alias(role_hint, value) end
    if value:find("dialog", 1, true) and value:find("bus", 1, true) then
      add_alias("dialog_bus", value)
      add_alias("bus", value)
    end
    if value:find("music", 1, true) and value:find("bus", 1, true) then
      add_alias("music_bus", value)
      add_alias("bus", value)
    end
    if value:find("fx", 1, true) and value:find("bus", 1, true) then
      add_alias("fx_bus", value)
      add_alias("bus", value)
    end
    if value:find("print", 1, true) then
      add_alias("print_mix", value)
      add_alias("bus", value)
    end
    if value:find("bus", 1, true) then add_alias("bus", value) end
  end
  add_alias("dialog_bus", "dialog bus")
  add_alias("music_bus", "music bus")
  add_alias("fx_bus", "fx bus")
  add_alias("print_mix", "print mix")
  add_alias("bus", "bus")
  for name in lowered:gmatch("[%a_][%w_]*") do
    for _, role in ipairs(roles) do
      if name:find(role, 1, true) then add_alias(role, name) end
    end
    add_named_aliases(name)
  end
  for lhs, quoted in lowered:gmatch(
      "([%a_][%w_]*)%s*=%s*.-[\"']([^\"']+)[\"']") do
    for _, role in ipairs(roles) do
      if quoted:find(role, 1, true) then add_alias(role, lhs) end
    end
    add_named_aliases(quoted)
    add_named_aliases(lhs)
  end
  local function expr_matches_role(expr, role)
    expr = tostring(expr or ""):lower()
    if expr:find(role, 1, true) then return true end
    local compact_expr = expr:gsub("[^%w]", "")
    for alias in pairs(aliases[role]) do
      if #alias <= 1 then
        for token in expr:gmatch("[%a_][%w_]*") do
          if token == alias then return true end
        end
      elseif expr:find(alias, 1, true)
          or (compact_expr ~= "" and compact_expr:find(
            tostring(alias):gsub("[^%w]", ""), 1, true)) then
        return true
      end
    end
    return false
  end
  local routed, dest_by_role = {}, {}
  for _, role in ipairs(roles) do
    routed[role] = false
    dest_by_role[role] = {}
  end
  for src, dst in lowered:gmatch(
      "reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
    for _, role in ipairs(roles) do
      if expr_matches_role(src, role) then
        routed[role] = true
        dest_by_role[role][#dest_by_role[role] + 1] =
          tostring(dst or ""):lower():match("^%s*(.-)%s*$")
      end
    end
  end
  if wants_multi_bus then
    local required = {
      host = "dialog_bus",
      guest = "dialog_bus",
      music = "music_bus",
      sfx = "fx_bus",
    }
    local has_config_table_send =
      (lowered:find("config.bus", 1, true) ~= nil
        or lowered:find("config.dest", 1, true) ~= nil)
      and lowered:find(
        "reaper%.createtracksend%s*%(%s*src_track%s*,%s*dst_track%s*%)") ~= nil
    has_config_table_send = has_config_table_send
      or ((lowered:find("target_bus", 1, true) ~= nil
          or lowered:find("config.bus", 1, true) ~= nil
          or lowered:find("config.dest", 1, true) ~= nil)
        and (lowered:find(
          "reaper%.createtracksend%s*%(%s*src%s*,%s*dst%s*%)") ~= nil
          or lowered:find(
            "reaper%.createtracksend%s*%(%s*src_track%s*,%s*dst_track%s*%)") ~= nil))
    local route_helper_names = { "route_track", "route", "add_send", "send" }
    local function has_route_helper_definition()
      for _, helper in ipairs(route_helper_names) do
        if lowered:find("function%s+" .. helper .. "%s*%(") ~= nil then
          return true
        end
      end
      return false
    end
    local has_route_helper_send =
      has_route_helper_definition()
      and (lowered:find(
        "reaper%.createtracksend%s*%(%s*src%s*,%s*dst%s*%)") ~= nil
        or lowered:find(
          "reaper%.createtracksend%s*%(%s*src%s*,%s*dest%s*%)") ~= nil)
    local has_pair_table_send =
      ((lowered:find("tracks%s*%[%s*pair%s*%[%s*1%s*%]%s*%]") ~= nil
        and lowered:find("tracks%s*%[%s*pair%s*%[%s*2%s*%]%s*%]") ~= nil)
        or (lowered:find("pair%s*%[%s*1%s*%]") ~= nil
          and lowered:find("pair%s*%[%s*2%s*%]") ~= nil))
      and lowered:find(
        "reaper%.createtracksend%s*%(%s*src%s*,%s*dst%s*%)") ~= nil
    local has_routing_map_send =
      lowered:find("for%s+src_name%s*,%s*dst_name%s+in%s+pairs%s*%(") ~= nil
      and lowered:find("tracks%s*%[%s*src_name%s*%]") ~= nil
      and lowered:find("tracks%s*%[%s*dst_name%s*%]") ~= nil
      and lowered:find(
        "reaper%.createtracksend%s*%(%s*src%s*,%s*dst%s*%)") ~= nil
    local function config_table_has_pair(src_role, dest_role)
      for body in lowered:gmatch("{([^{}]*)}") do
        if expr_matches_role(body, src_role)
            and expr_matches_role(body, dest_role) then
          return true
        end
      end
      return false
    end
    local function route_helper_has_pair(src_role, dest_role)
      for _, helper in ipairs(route_helper_names) do
        for src_name, dst_name in lowered:gmatch(
            helper .. "%s*%(%s*[\"']([^\"']+)[\"']%s*,%s*[\"']([^\"']+)[\"']%s*%)") do
          if expr_matches_role(src_name, src_role)
              and expr_matches_role(dst_name, dest_role) then
            return true
          end
        end
        for src_name, dst_name in lowered:gmatch(
            helper .. "%s*%(%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*%)") do
          if expr_matches_role(src_name, src_role)
              and expr_matches_role(dst_name, dest_role) then
            return true
          end
        end
      end
      return false
    end
    local function routing_map_has_pair(src_role, dest_role)
      for src_name, dst_name in lowered:gmatch(
          "%[%s*[\"']([^\"']+)[\"']%s*%]%s*=%s*[\"']([^\"']+)[\"']") do
        if expr_matches_role(src_name, src_role)
            and expr_matches_role(dst_name, dest_role) then
          return true
        end
      end
      return false
    end
    for _, role in ipairs(roles) do
      local dest_role = required[role]
      local ok = false
      for _, dst in ipairs(dest_by_role[role] or {}) do
        if dest_role and expr_matches_role(dst, dest_role) then ok = true end
      end
      if not ok and has_config_table_send and dest_role then
        ok = config_table_has_pair(role, dest_role)
      end
      if not ok and has_pair_table_send and dest_role then
        ok = config_table_has_pair(role, dest_role)
      end
      if not ok and has_routing_map_send and dest_role then
        ok = routing_map_has_pair(role, dest_role)
      end
      if not ok and has_route_helper_send and dest_role then
        ok = route_helper_has_pair(role, dest_role)
      end
      if not ok then return false end
    end
    return true
  end
  local all_direct = true
  for _, role in ipairs(roles) do
    if not routed[role] then all_direct = false end
  end
  if all_direct then
    local first_dest, same_dest, has_bus_dest = nil, true, false
    for _, role in ipairs(roles) do
      local dst = (dest_by_role[role] and dest_by_role[role][1]) or ""
      if expr_matches_role(dst, "bus") then has_bus_dest = true end
      if first_dest == nil then
        first_dest = dst
      elseif dst ~= first_dest then
        same_dest = false
      end
    end
    if has_bus_dest
        or (same_dest
          and not expr_matches_role(first_dest, "host")
          and not expr_matches_role(first_dest, "guest")
          and not expr_matches_role(first_dest, "music")) then
      return true
    end
  end
  local source_table_has_all = false
  for body in lowered:gmatch("{([^{}]*)}") do
    local has_all = true
    for _, role in ipairs(roles) do
      if not expr_matches_role(body, role) then has_all = false end
    end
    if has_all then
      source_table_has_all = true
      break
    end
  end
  if source_table_has_all then
    for _, dst in lowered:gmatch(
        "reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
      if expr_matches_role(dst, "bus") then return true end
    end
  end
  return false
end

function Code.prompt_requests_midi_input_device_filter(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  local function has_word(word)
    return lt:find("%f[%w]" .. word .. "%f[%W]") ~= nil
  end
  local mentions_midi_input =
       has_word("midi")
    or has_word("controller")
    or has_word("controllers")
  if not mentions_midi_input then return false end
  local mentions_device =
       has_word("device")
    or has_word("devices")
    or has_word("input")
    or has_word("inputs")
    or has_word("controller")
    or has_word("controllers")
  if not mentions_device then return false end

  local filter_phrases = {
    "all midi devices except",
    "all midi device except",
    "all midi inputs except",
    "all midi input except",
    "every midi device except",
    "every midi devices except",
    "every midi input except",
    "every midi inputs except",
    "all midi controllers except",
    "every midi controller except",
    "all controllers except",
    "every controller except",
    "all inputs except",
    "every input except",
    "all midi devices but",
    "all midi inputs but",
    "all inputs but",
    "controlled by all midi devices except",
    "controlled by all midi inputs except",
  }
  for _, phrase in ipairs(filter_phrases) do
    if lt:find(phrase, 1, true) then return true end
  end

  local has_all_or_every =
       has_word("all")
    or has_word("every")
  if has_all_or_every and (has_word("except")
      or has_word("excluding")
      or lt:find("but not", 1, true) ~= nil) then
    return true
  end
  local only_routing_phrases = {
    "only listen to",
    "only listens to",
    "listen only to",
    "only receive from",
    "only receives from",
    "receive only from",
    "only accept from",
    "only accepts from",
    "accept only from",
    "only use",
    "only uses",
    "use only",
    "only controlled by",
    "controlled only by",
  }
  for _, phrase in ipairs(only_routing_phrases) do
    if lt:find(phrase, 1, true) then return true end
  end
  local has_physical_device_target =
       has_word("device")
    or has_word("devices")
    or has_word("controller")
    or has_word("controllers")
  if has_physical_device_target
      and not has_word("channel")
      and (has_word("ignore") or has_word("block") or has_word("exclude")) then
    return true
  end
  return false
end

function Code.lua_has_midi_input_or_routing_mutation(lua_code)
  local stripped = tostring(lua_code or "")
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  return stripped:find("reaper%.SetMediaTrackInfo_Value%s*%(") ~= nil
    or stripped:find("reaper%.CreateTrackSend%s*%(") ~= nil
    or stripped:find("reaper%.SetTrackSendInfo_Value%s*%(") ~= nil
    or stripped:find("reaper%.InsertTrackAtIndex%s*%(") ~= nil
    or stripped:find("reaper%.GetSetTrackState%s*%(") ~= nil
    or stripped:find("reaper%.GetSetTrackStateChunk%s*%(") ~= nil
end

function Code.find_midi_input_device_filter_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local lower = stripped:lower()
  local findings = {}
  local function add(kind, detail)
    findings[#findings + 1] = { kind = kind, detail = detail }
  end
  if stripped:find(
      "reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']B_RECARM[\"']") then
    add("invalid_record_arm_property",
      "B_RECARM is not a valid track property; use I_RECARM")
  end
  if not Code.prompt_requests_midi_input_device_filter(user_text) then
    if #findings == 0 then return nil end
    return findings
  end
  local numeric_assignments = {}
  for line in stripped:gmatch("[^\n]+") do
    local var, value = line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*(-?%d+%.?%d*)%s*$")
    if not var then
      var, value = line:match("^%s*([%a_][%w_]*)%s*=%s*(-?%d+%.?%d*)%s*$")
    end
    if var and value then numeric_assignments[var] = tonumber(value) end
  end
  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end
  local function literal_channel_value(expr)
    local compact = tostring(expr or ""):gsub("%s+", "")
    if not compact:find("4096", 1, true)
        or not compact:find("%*32") then
      return nil
    end
    local literal = compact:match("%+(-?%d+%.?%d*)$")
    if literal then return tonumber(literal) end
    local var = compact:match("%+([%a_][%w_]*)$")
    return var and numeric_assignments[var] or nil
  end

  if stripped:find("P_MIDI_MAP", 1, true) then
    add("unsupported_midi_map",
      "P_MIDI_MAP is not a supported track MIDI input-device filter")
  end
  if stripped:find("%f[%d]4096%.?0*%s*%+%s*256%.?0*%f[%D]")
      or stripped:find("%f[%d]256%.?0*%f[%D]%s*%+%s*4096%.?0*%f[%D]")
      or stripped:find("%f[%d]4352%.?0*%f[%D]") then
    add("fake_all_except_map",
      "4096 + 256 is not an all-MIDI-except-device encoding")
  end
  if stripped:find("[\"']I_RECINPUT[\"']%s*,%s*4096%.?0*%s*%)") then
    add("all_midi_for_filtered_request",
      "I_RECINPUT=4096 selects all MIDI inputs, not a filtered device set")
  end
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.SetMediaTrackInfo_Value%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    if args and args[2] and args[3]
        and args[2]:match("^[\"']I_RECINPUT[\"']$") then
      local channel = literal_channel_value(args[3])
      if channel and (channel < 0 or channel > 16 or channel % 1 ~= 0) then
        add("midi_channel_out_of_range",
          "I_RECINPUT channel component must be an integer from 0 to 16")
      end
    end
    pos = open_pos + 1
  end
  if stripped:find("reaper%.GetMIDIInputName%s*%(")
      and (lower:find("console", 1, true)
        or lower:find("print%s*%(") ~= nil)
      and not Code.lua_has_midi_input_or_routing_mutation(stripped) then
    add("inspection_only",
      "script only lists MIDI inputs instead of applying the requested filter")
  end

  if #findings == 0 then return nil end
  return findings
end

function Code.prompt_has_midi_generation_verb(text)
  local lt = tostring(text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  return lt:find("%f[%w]make%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]new%f[%W]") ~= nil
    or lt:find("%f[%w]idea%f[%W]") ~= nil
    or lt:find("%f[%w]pattern%f[%W]") ~= nil
    or lt:find("%f[%w]generate%f[%W]") ~= nil
    or lt:find("%f[%w]write%f[%W]") ~= nil
    or lt:find("%f[%w]compose%f[%W]") ~= nil
    or lt:find("%f[%w]program%f[%W]") ~= nil
end

function Code.prompt_requests_new_midi_content(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if lt:find("%f[%w]midi%f[%W]") then
    return Code.prompt_has_midi_generation_verb(lt)
  end
  return Code.prompt_implies_midi_generation(lt)
end

function Code.prompt_implies_midi_generation(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" or lt:find("%f[%w]midi%f[%W]") then return false end
  if not Code.prompt_has_midi_generation_verb(lt) then return false end
  return lt:find("%f[%w]chord") ~= nil
    or lt:find("%f[%w]triad") ~= nil
    or lt:find("%f[%w]arpegg") ~= nil
    or lt:find("%f[%w]progression") ~= nil
    or lt:find("%f[%w]melod") ~= nil
    or lt:find("%f[%w]harmony%f[%W]") ~= nil
    or lt:find("%f[%w]bassline%f[%W]") ~= nil
    or lt:find("%f[%w]bass%s+line%f[%W]") ~= nil
    or lt:find("%f[%w]drum%s+pattern%f[%W]") ~= nil
    or lt:find("%f[%w]beat%f[%W]") ~= nil
    or lt:find("%f[%w]notes%f[%W]") ~= nil
    or lt:find("%f[%w]pitches%f[%W]") ~= nil
    or lt:find("%f[%w]pitch%s+%d") ~= nil
end

function Code.find_literal_midi_insertnote_ppq_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_new_midi_content(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end
  if stripped:find("reaper%.MIDI_GetPPQPosFromProjTime%s*%(")
     or stripped:find("reaper%.MIDI_GetPPQPosFromProjQN%s*%(") then
    return nil
  end

  local findings = {}
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local pos = 1
  while true do
    local s, e, args = stripped:find("reaper%.MIDI_InsertNote%s*%(([^%)]*)%)", pos)
    if not s then break end
    local parts = {}
    for part in tostring(args or ""):gmatch("[^,]+") do
      parts[#parts + 1] = part:gsub("^%s+", ""):gsub("%s+$", "")
    end
    local start_ppq = tonumber(parts[4])
    local end_ppq = tonumber(parts[5])
    if start_ppq and end_ppq and end_ppq > start_ppq and end_ppq <= 32 then
      findings[#findings + 1] = {
        line = line_for_pos(s),
        start_ppq = start_ppq,
        end_ppq = end_ppq,
      }
    end
    pos = e + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_midi_insertnote_project_time_variable_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_new_midi_content(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end
  if stripped:find("reaper%.MIDI_GetPPQPosFromProjTime%s*%(")
     or stripped:find("reaper%.MIDI_GetPPQPosFromProjQN%s*%(") then
    return nil
  end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local assignments = {}
  for line in stripped:gmatch("[^\r\n]+") do
    local var, expr =
      line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not var then
      var, expr = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if var and expr and not expr:find("^%s*function%f[%W]") then
      assignments[var] = Code._lua_trim_expr(expr)
    end
  end

  local function has_ppq_hint(expr)
    local le = tostring(expr or ""):lower()
    return le:find("ppq", 1, true) ~= nil
      or le:find("tick", 1, true) ~= nil
      or le:find("midi_getppq", 1, true) ~= nil
      or le:find("%f[%w]qn%f[%W]") ~= nil
  end
  local function has_project_time_hint(expr)
    local le = tostring(expr or ""):lower()
    return le:find("time", 1, true) ~= nil
      or le:find("sec", 1, true) ~= nil
      or le:find("proj", 1, true) ~= nil
      or le:find("beat", 1, true) ~= nil
      or le:find("quarter", 1, true) ~= nil
      or le:find("eighth", 1, true) ~= nil
      or le:find("%f[%w]bar%f[%W]") ~= nil
      or le:find("measure", 1, true) ~= nil
  end
  local function suspicious_project_time_expr(expr, seen)
    expr = Code._lua_trim_expr(expr)
    if expr == "" or has_ppq_hint(expr) then return false end
    local n = tonumber(expr)
    if n then return n >= 0 and n <= 32 end
    if has_project_time_hint(expr) then return true end
    seen = seen or {}
    for name in expr:gmatch("%f[%a_][%a_][%w_]*%f[^%w_]") do
      if not seen[name] and assignments[name] then
        seen[name] = true
        if suspicious_project_time_expr(assignments[name], seen) then
          return true
        end
      end
    end
    return false
  end

  local findings = {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.MIDI_InsertNote%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    if args and args[4] and args[5]
        and (suspicious_project_time_expr(args[4])
          or suspicious_project_time_expr(args[5])) then
      findings[#findings + 1] = {
        line = line_for_pos(s),
        start_arg = args[4],
        end_arg = args[5],
      }
    end
    pos = open_pos + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_midi_insertnote_table_pitch_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not (Code.prompt_requests_new_midi_content(user_text)
      or Code.prompt_implies_midi_generation(user_text)) then
    return nil
  end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local nested_tables = {}
  local pos = 1
  while true do
    local s, e, name =
      stripped:find("local%s+([%w_]+)%s*=%s*{%s*{%s*{", pos)
    if not s then break end
    nested_tables[name] = line_for_pos(s)
    pos = e + 1
  end
  if not next(nested_tables) then return nil end

  local loop_vars = {}
  for table_name in pairs(nested_tables) do
    local loop_pat = "for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+"
      .. "ipairs%s*%(%s*" .. table_name .. "%s*%)"
    for loop_var in stripped:gmatch(loop_pat) do
      loop_vars[loop_var] = table_name
    end
  end
  if not next(loop_vars) then return nil end

  local pitch_vars = {}
  for loop_var, table_name in pairs(loop_vars) do
    local assign_pat = "local%s+([%w_]+)%s*=%s*"
      .. loop_var .. "%s*%[[^%]]+%]"
    for pitch_var in stripped:gmatch(assign_pat) do
      pitch_vars[pitch_var] = {
        table_name = table_name,
        loop_var = loop_var,
      }
    end
    local inner_loop_pat = "for%s+[%w_]+%s*,%s*([%w_]+)%s+in%s+"
      .. "ipairs%s*%(%s*" .. loop_var .. "%s*%)"
    for pitch_var in stripped:gmatch(inner_loop_pat) do
      pitch_vars[pitch_var] = {
        table_name = table_name,
        loop_var = loop_var,
      }
    end
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local findings = {}
  pos = 1
  while true do
    local s, e = stripped:find("reaper%.MIDI_InsertNote%s*%(", pos)
    if not s then break end
    local args = parse_args(e)
    local pitch_arg = args and args[7] or nil
    if pitch_arg then
      local assigned = pitch_vars[pitch_arg]
      if assigned then
        findings[#findings + 1] = {
          line = line_for_pos(s),
          table_name = assigned.table_name,
          table_line = nested_tables[assigned.table_name],
          loop_var = assigned.loop_var,
          pitch_arg = pitch_arg,
        }
      end
      for loop_var, table_name in pairs(loop_vars) do
        local pat = "^" .. loop_var .. "%s*%[[^%]]+%]$"
        if pitch_arg:match(pat) then
          findings[#findings + 1] = {
            line = line_for_pos(s),
            table_name = table_name,
            table_line = nested_tables[table_name],
            loop_var = loop_var,
            pitch_arg = pitch_arg,
          }
          break
        end
      end
    end
    pos = e + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_kick_midi_wrong_pitch_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  if prompt == "" then return nil end
  if not prompt:find("%f[%w]kick%f[%W]") then return nil end
  if prompt:find("%f[%w]snare%f[%W]")
      or prompt:find("%f[%w]hat%f[%W]")
      or prompt:find("%f[%w]hihat%f[%W]")
      or prompt:find("%f[%w]hi%-hat%f[%W]")
      or prompt:find("%f[%w]tom%f[%W]")
      or prompt:find("%f[%w]cymbal%f[%W]") then
    return nil
  end
  local explicit_named_note = prompt:find("%f[%w]c%d%f[%W]") ~= nil
  local explicit_c2_kick =
    explicit_named_note
    and prompt:find("%f[%w]c2%f[%W]") ~= nil
    and (prompt:find("%f[%w]kick%s+notes?%f[%W]")
      or prompt:find("%f[%w]kick%s+midi%f[%W]")
      or prompt:find("%f[%w]kick%s+pattern%f[%W]")
      or prompt:find("%f[%w]kick%s+trigger%f[%W]"))
  if prompt:find("%f[%w]pitch%s+%d")
      or prompt:find("%f[%w]note%s+%d")
      or prompt:find("%f[%w]pitches%f[%W]")
      or (explicit_named_note and not explicit_c2_kick) then
    return nil
  end
  if not (prompt:find("%f[%w]midi%f[%W]")
      or prompt:find("%f[%w]pattern%f[%W]")
      or prompt:find("%f[%w]notes?%f[%W]")) then
    return nil
  end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local assignments = {}
  for line in stripped:gmatch("[^\r\n]+") do
    local var, expr =
      line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not var then
      var, expr = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if var and expr and not expr:find("^%s*function%f[%W]") then
      assignments[var] = trim(expr)
    end
  end

  local function eval_num(expr, seen)
    expr = trim(expr)
    local n = tonumber(expr)
    if n then return n end
    local compact = expr:gsub("%s+", "")
    local a, op, b = compact:match("^(%d+)([%+%-])(%d+)$")
    if a and op and b then
      a, b = tonumber(a), tonumber(b)
      return op == "+" and (a + b) or (a - b)
    end
    a, b = compact:match("^(%d+)%*(%d+)$")
    if a and b then return tonumber(a) * tonumber(b) end
    if assignments[expr] and not (seen and seen[expr]) then
      seen = seen or {}
      seen[expr] = true
      return eval_num(assignments[expr], seen)
    end
    return nil
  end
  local function is_valid_kick_pitch(pitch)
    return pitch == 35 or pitch == 36
  end

  local findings = {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.MIDI_InsertNote%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    local pitch = args and eval_num(args[7])
    if pitch and not is_valid_kick_pitch(pitch) then
      findings[#findings + 1] = {
        line = line_for_pos(s),
        pitch = pitch,
        pitch_arg = args[7],
      }
    end
    pos = open_pos + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_midi_named_note_octave_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower()
  if prompt == "" then return nil end
  local compact_prompt = prompt:gsub("%s+", "")
  local wants_c4_triad =
    compact_prompt:find("c4/e4/g4", 1, true) ~= nil
    or (prompt:find("%f[%w]c4%f[%W]")
      and prompt:find("%f[%w]e4%f[%W]")
      and prompt:find("%f[%w]g4%f[%W]"))
    or (prompt:find("%f[%w]c4%f[%W]")
      and prompt:find("%f[%w]major%s+triad%f[%W]"))
    or (prompt:find("%f[%w]60%f[%W]")
      and prompt:find("%f[%w]64%f[%W]")
      and prompt:find("%f[%w]67%f[%W]"))
  if not wants_c4_triad then return nil end
  if not (Code.prompt_requests_new_midi_content(user_text)
      or Code.prompt_implies_midi_generation(user_text)) then
    return nil
  end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local wrong, right, findings = {}, {}, {}
  local expected_wrong = { [48] = "C4", [52] = "E4", [55] = "G4" }
  local expected_right = { [60] = true, [64] = true, [67] = true }
  local pos = 1
  while true do
    local s, e, pitch = stripped:find("%f[%w_]pitch%f[^%w_]%s*=%s*(%d+)", pos)
    if not s then break end
    pitch = tonumber(pitch)
    if expected_wrong[pitch] then
      wrong[pitch] = true
      findings[#findings + 1] = {
        line = line_for_pos(s),
        pitch = pitch,
        expected = expected_wrong[pitch],
      }
    elseif expected_right[pitch] then
      right[pitch] = true
    end
    pos = e + 1
  end

  if not (wrong[48] and wrong[52] and wrong[55]) then return nil end
  if right[60] and right[64] and right[67] then return nil end
  return findings
end

function Code.find_midi_seconds_as_qn_offset_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_new_midi_content(user_text) then return nil end
  local prompt_l = tostring(user_text or ""):lower():gsub("%s+", " ")
  local timing_request =
       prompt_l:find("next eighth", 1, true) ~= nil
    or prompt_l:find("every eighth", 1, true) ~= nil
    or prompt_l:find("eighth notes", 1, true) ~= nil
    or prompt_l:find("eighth-note", 1, true) ~= nil
    or prompt_l:find("8th note", 1, true) ~= nil
    or prompt_l:find(" bpm", 1, true) ~= nil
    or prompt_l:find("%f[%w]%d+%s*bpm%f[%W]") ~= nil
  if not timing_request then return nil end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(")
     or not stripped:find("reaper%.MIDI_GetPPQPosFromProjQN%s*%(")
     or not stripped:find("reaper%.TimeMap2_timeToQN%s*%(") then
    return nil
  end

  local lines, assigns = {}, {}
  local seconds_vars, qn_offset_vars = {}, {}
  local line_no = 0
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    lines[line_no] = line
    local var, rhs = line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not var then
      var, rhs = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if var and rhs then
      assigns[#assigns + 1] = { line = line_no, var = var, rhs = rhs }
      local compact_rhs = rhs:gsub("%s+", "")
      local lname = var:lower()
      if compact_rhs:find("^60/[%a_][%w_]*$")
          or compact_rhs:find("^60/%d+%.?%d*$") then
        if lname:find("qn", 1, true)
            or lname:find("quarter", 1, true)
            or lname:find("beat", 1, true)
            or compact_rhs:find("bpm", 1, true)
            or compact_rhs:find("tempo", 1, true) then
          seconds_vars[var] = line_no
        end
      end
    end
  end
  if not next(seconds_vars) then return nil end

  local changed = true
  while changed do
    changed = false
    for _, assign in ipairs(assigns) do
      local compact_rhs = assign.rhs:gsub("%s+", "")
      local lname = assign.var:lower()
      for svar in pairs(seconds_vars) do
        if compact_rhs == svar .. "/2"
            or compact_rhs:find(svar .. "/2", 1, true) then
          if not seconds_vars[assign.var] then
            seconds_vars[assign.var] = assign.line
            changed = true
          end
        end
      end
      for svar in pairs(seconds_vars) do
        if compact_rhs:find(svar, 1, true)
            and (compact_rhs:find("%*", 1, false)
              or compact_rhs:find("%+", 1, false)
              or compact_rhs:find("%-", 1, false)) then
          if lname:find("qn", 1, true)
              or lname:find("start", 1, true)
              or lname:find("pos", 1, true)
              or lname:find("offset", 1, true) then
            if not qn_offset_vars[assign.var] then
              qn_offset_vars[assign.var] = assign.line
              changed = true
            end
          end
        end
      end
      for qvar in pairs(qn_offset_vars) do
        if compact_rhs:find(qvar, 1, true) then
          if lname:find("qn", 1, true)
              or lname:find("start", 1, true)
              or lname:find("pos", 1, true)
              or lname:find("offset", 1, true)
              or lname:find("ppq", 1, true) then
            if not qn_offset_vars[assign.var] then
              qn_offset_vars[assign.var] = assign.line
              changed = true
            end
          end
        end
      end
    end
  end
  if not next(qn_offset_vars) then return nil end

  local findings = {}
  for i, line in ipairs(lines) do
    if line:find("reaper%.MIDI_GetPPQPosFromProjQN%s*%(") then
      for qvar in pairs(qn_offset_vars) do
        if line:find(qvar, 1, true) then
          findings[#findings + 1] = {
            line = i,
            variable = qvar,
          }
          break
        end
      end
    end
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_midi_eighth_spacing_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not (Code.prompt_requests_new_midi_content(user_text)
      or Code.prompt_implies_midi_generation(user_text)) then
    return nil
  end
  local prompt_l = tostring(user_text or ""):lower():gsub("%s+", " ")
  local wants_eighth_spacing =
       prompt_l:find("next eighth", 1, true) ~= nil
    or prompt_l:find("every eighth", 1, true) ~= nil
    or prompt_l:find("eighth notes", 1, true) ~= nil
    or prompt_l:find("eighth-note", 1, true) ~= nil
    or prompt_l:find("eighths", 1, true) ~= nil
    or prompt_l:find("off-eighth", 1, true) ~= nil
    or prompt_l:find("spaced as eighth", 1, true) ~= nil
    or prompt_l:find("8th note", 1, true) ~= nil
    or prompt_l:find("8th-note", 1, true) ~= nil
  if not wants_eighth_spacing then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.MIDI_InsertNote%s*%(") then return nil end

  if stripped:find("reaper%.MIDI_GetPPQPosFromProjTime%s*%(") then
    local bpm = tonumber(prompt_l:match("(%d+%.?%d*)%s*bpm"))
    if not bpm then
      bpm = tonumber(stripped:match("SetCurrentBPM%s*%(%s*[^,]+,%s*(%d+%.?%d*)"))
        or tonumber(stripped:match("local%s+bpm%s*=%s*(%d+%.?%d*)"))
    end
    if bpm and bpm > 0 then
      local expected_eighth_seconds = 30 / bpm
      local findings = {}
      for var, body in stripped:gmatch("local%s+([%a_][%w_]*)%s*=%s*{%s*([^{}]-)%s*}") do
        local lname = var:lower()
        if lname:find("start", 1, true)
           or lname:find("time", 1, true)
           or lname:find("pos", 1, true) then
          local nums = {}
          for raw in body:gmatch("%f[%d%-]%-?%d+%.?%d*") do
            nums[#nums + 1] = tonumber(raw)
          end
          if #nums >= 2 then
            local step = nums[2] - nums[1]
            if math.abs(step - 0.5) <= 0.001
               and math.abs(step - expected_eighth_seconds) > 0.04 then
              findings[#findings + 1] = {
                variable = var,
                step_seconds = step,
                expected_seconds = expected_eighth_seconds,
                bpm = bpm,
              }
            end
          end
        end
      end
      if #findings > 0 then return findings end
    end
  end

  local function has_name_segment(name, segment)
    return name == segment
      or name:find("^" .. segment .. "_") ~= nil
      or name:find("_" .. segment .. "_", 1, true) ~= nil
      or name:find("_" .. segment .. "$") ~= nil
  end

  local quarter_vars, eighth_vars, loop_vars = {}, {}, {}
  for var in stripped:gmatch("([%a_][%w_]*)%s*=") do
    local lname = var:lower()
    if lname:find("ppq", 1, true) then
      if lname:find("qn", 1, true)
          or lname:find("quarter", 1, true)
          or lname == "ppq_per_beat"
          or lname == "beat_ppq" then
        quarter_vars[var] = true
      end
      if has_name_segment(lname, "en")
          or lname:find("eighth", 1, true)
          or lname:find("eight", 1, true) then
        eighth_vars[var] = true
      end
    end
  end
  if not next(quarter_vars) or not next(eighth_vars) then return nil end

  for idx in stripped:gmatch("for%s+([%a_][%w_]*)%s*=%s*[^,%s]+%s*,") do
    loop_vars[idx] = true
  end
  for idx in stripped:gmatch("for%s+([%a_][%w_]*)%s*,%s*[%a_][%w_]*%s+in%s+ipairs%s*%(") do
    loop_vars[idx] = true
  end
  if not next(loop_vars) then return nil end

  local function count_plain(haystack, needle)
    local count, pos = 0, 1
    while true do
      local s, e = haystack:find(needle, pos, true)
      if not s then break end
      count = count + 1
      pos = e + 1
    end
    return count
  end
  local eighth_var_used = false
  for evar in pairs(eighth_vars) do
    if count_plain(stripped, evar) >= 2 then
      eighth_var_used = true
      break
    end
  end
  if not eighth_var_used then return nil end

  local function has_halved_quarter_step(line, idx, qvar)
    local product1 = idx .. "%s*%*%s*" .. qvar
    local product2 = qvar .. "%s*%*%s*" .. idx
    return line:find(product1 .. "%s*%*%s*0%.5%f[^%d%.]")
      or line:find(product1 .. "%s*%*%s*%.5%f[^%d%.]")
      or line:find(product1 .. "%s*[%)]*%s*/%s*2%f[^%d%.]")
      or line:find(product2 .. "%s*%*%s*0%.5%f[^%d%.]")
      or line:find(product2 .. "%s*%*%s*%.5%f[^%d%.]")
      or line:find(product2 .. "%s*[%)]*%s*/%s*2%f[^%d%.]")
  end

  local findings, line_no = {}, 0
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local line_l = line:lower()
    local looks_like_note_start =
      line_l:find("pos", 1, true)
      or line_l:find("start", 1, true)
      or line:find("reaper%.MIDI_InsertNote%s*%(")
    if looks_like_note_start then
      for idx in pairs(loop_vars) do
        for qvar in pairs(quarter_vars) do
          if line:find(idx .. "%s*%*%s*" .. qvar)
              or line:find(qvar .. "%s*%*%s*" .. idx) then
            if not has_halved_quarter_step(line, idx, qvar) then
              findings[#findings + 1] = {
                line = line_no,
                loop_var = idx,
                quarter_var = qvar,
              }
            end
          end
        end
      end
    end
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_create_new_midi_item_bad_track_arg(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_new_midi_content(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local findings = {}
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local pos = 1
  while true do
    local s, e, arg1 = stripped:find(
      "reaper%.CreateNewMIDIItemInProj%s*%(%s*([^,%)]*)", pos)
    if not s then break end
    arg1 = tostring(arg1 or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg1 == "0" or arg1 == "nil" or arg1 == "false" or arg1 == "true" then
      findings[#findings + 1] = { line = line_for_pos(s), arg = arg1 }
    end
    pos = e + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_takeismidi_media_item_arg(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  if not Code.prompt_requests_new_midi_content(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local media_item_vars = {}
  local function remember_item_var(var)
    var = tostring(var or ""):match("^%s*([%a_][%w_]*)%s*$")
    if var then media_item_vars[var] = true end
  end
  for var in stripped:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*reaper%.CreateNewMIDIItemInProj%s*%(") do
    remember_item_var(var)
  end
  for var in stripped:gmatch(
      "\n%s*([%a_][%w_]*)%s*=%s*reaper%.CreateNewMIDIItemInProj%s*%(") do
    remember_item_var(var)
  end
  for var, callee in stripped:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*%(") do
    if tostring(callee or ""):lower():find("midiitem", 1, true) then
      remember_item_var(var)
    end
  end
  local findings = {}
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local pos = 1
  while true do
    local s, e, arg = stripped:find(
      "reaper%.TakeIsMIDI%s*%(%s*([%a_][%w_]*)%s*%)", pos)
    if not s then break end
    local lower_arg = tostring(arg or ""):lower()
    local looks_like_item =
      media_item_vars[arg]
      or (lower_arg:find("item", 1, true)
        and not lower_arg:find("take", 1, true))
    if looks_like_item then
      findings[#findings + 1] = {
        line = line_for_pos(s),
        arg = arg,
      }
    end
    pos = e + 1
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.bare_lua_retry_candidate(text)
  local bare_lua = tostring(text or ""):match("^%s*(.-)%s*$") or ""
  if bare_lua == "" then return nil end
  local inline_code = false
  local inline_lua = bare_lua:match("^`%s*(.-)%s*`$")
  if inline_lua and not inline_lua:find("`", 1, true) then
    bare_lua = inline_lua:match("^%s*(.-)%s*$") or ""
    inline_code = true
  end
  local looks_like_lua = bare_lua ~= ""
    and bare_lua:find("reaper%.")
    and (bare_lua:find("reaper%.Undo_")
      or bare_lua:find("reaper%.AddProjectMarker")
      or bare_lua:find("reaper%.InsertTrackAtIndex")
      or bare_lua:find("local%s+function")
      or bare_lua:find("function%s+main")
      or (inline_code
        and bare_lua:find("^%s*reaper%.[%w_]+%s*%(")))
  if not looks_like_lua then return nil end
  local chunk = load(bare_lua, "bare_lua_preflight", "t", {})
  if not chunk then return nil end
  return bare_lua
end

-- =============================================================================
-- Code.prompt_requests_track_creation / Code.lua_creates_tracks
-- =============================================================================
-- Guard against syntactically valid but inert scripts where the user asked to
-- create tracks and the model merely renames existing track handles.
function Code.prompt_requests_track_creation(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  lt = lt:gsub("%s+", " ")
  if lt:find("%f[%w]selected%s+track%f[%W]")
      or lt:find("%f[%w]selected%s+tracks%f[%W]")
      or lt:find("%f[%w]existing%s+track%f[%W]")
      or lt:find("%f[%w]existing%s+tracks%f[%W]")
      or lt:find("%f[%w]current%s+track%f[%W]")
      or lt:find("%f[%w]current%s+tracks%f[%W]") then
    return false
  end
  local function bounded_make_track(article)
    local pat = "%f[%w]make%s+" .. article .. "%s+([%w%- ]-)track%f[%W]"
    for words in lt:gmatch(pat) do
      local count, blocked = 0, false
      for word in tostring(words or ""):gmatch("[%w%-]+") do
        count = count + 1
        if word == "on" or word == "to" or word == "from"
            or word == "for" or word == "with" or word == "into"
            or word == "onto" or word == "using" or word == "sound"
            or word == "sounds" then
          blocked = true
        end
      end
      if count <= 4 and not blocked then return true end
    end
    return false
  end
  local patterns = {
    "%f[%w]create%s+exactly%s+.-%f[%w]track%f[%W]",
    "%f[%w]create%s+exactly%s+.-%f[%w]tracks%f[%W]",
    "%f[%w]creates%s+exactly%s+.-%f[%w]track%f[%W]",
    "%f[%w]creates%s+exactly%s+.-%f[%w]tracks%f[%W]",
    "%f[%w]create%s+one%s+track%f[%W]",
    "%f[%w]creates%s+one%s+track%f[%W]",
    "%f[%w]create%s+a%s+track%f[%W]",
    "%f[%w]creates%s+a%s+track%f[%W]",
    "%f[%w]create%s+track%s+named%f[%W]",
    "%f[%w]creates%s+track%s+named%f[%W]",
    "%f[%w]create%s+tracks%s+named%f[%W]",
    "%f[%w]creates%s+tracks%s+named%f[%W]",
    "%f[%w]insert%s+a%s+track%f[%W]",
    "%f[%w]insert%s+tracks%s+named%f[%W]",
    "%f[%w]add%s+a%s+track%f[%W]",
    "%f[%w]add%s+tracks%s+named%f[%W]",
    "%f[%w]make%s+.-%f[%w]folder%f[%W]",
    "%f[%w]make%s+.-%f[%w]tracks%f[%W]%s+with",
    "%f[%w]build%s+.-%f[%w]folder%f[%W]",
    "%f[%w]build%s+.-%f[%w]tracks%f[%W]",
    "%f[%w]build%s+.-%f[%w]session%s+outline%f[%W]",
    "%f[%w]create%s+.-%f[%w]folder%f[%W]",
    "%f[%w]set%s+up%s+a%s+.-%f[%w]track%f[%W]",
    "%f[%w]set%s+up%s+.-%f[%w]tracks%f[%W]",
    "%f[%w]set%s+up%s+.-%f[%w]folder%f[%W]",
  }
  for _, pat in ipairs(patterns) do
    if lt:find(pat) then return true end
  end
  if bounded_make_track("a")
      or bounded_make_track("an")
      or bounded_make_track("one") then
    return true
  end
  return false
end

function Code.lua_creates_tracks(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.InsertTrackAtIndex%s*%(") then return true end
  if stripped:find("reaper%.Main_OnCommand%s*%(%s*40001%s*,") then return true end
  return false
end

function Code.prompt_requests_track_duplication(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  lt = lt:gsub("[\226\128\153']", ""):gsub("%s+", " ")

  local verbs = {
    "duplicate", "duplicates", "duplicated", "duplicating",
    "clone", "clones", "cloned", "cloning",
    "copy", "copies", "copied", "copying",
  }
  local objects = {
    "track", "tracks", "bus", "buses", "folder", "folders",
    "return", "returns",
  }
  local non_track_targets = {
    item = true, items = true, take = true, takes = true,
    media = true, fx = true, effect = true, effects = true,
    plugin = true, plugins = true, setting = true, settings = true,
    parameter = true, parameters = true, send = true, sends = true,
    routing = true, automation = true, envelope = true, envelopes = true,
    color = true, colour = true, colors = true, colours = true,
  }
  local function has_non_track_target(text)
    for word in tostring(text or ""):gmatch("%f[%w]([%w_]+)%f[%W]") do
      if non_track_targets[word] then return true end
    end
    return false
  end
  local function word_count(text)
    local count = 0
    for _ in tostring(text or ""):gmatch("%f[%w][%w_]+%f[%W]") do
      count = count + 1
    end
    return count
  end
  local boundary_after_track = {
    ["and"] = true, ["as"] = true, ["become"] = true, ["becomes"] = true,
    ["called"] = true, ["for"] = true, ["include"] = true,
    ["includes"] = true, ["including"] = true, ["into"] = true,
    ["named"] = true, ["plus"] = true, ["rename"] = true,
    ["renamed"] = true, ["that"] = true, ["then"] = true, ["to"] = true,
    ["which"] = true, ["with"] = true, ["within"] = true,
  }
  local function has_near_non_track_target_after_object(text)
    local count = 0
    for word in tostring(text or ""):gmatch("%f[%w]([%w_]+)%f[%W]") do
      if boundary_after_track[word] then return false end
      if non_track_targets[word] then return true end
      count = count + 1
      if count >= 4 then return false end
    end
    return false
  end

  local double_track_patterns = {
    "%f[%w]double%s+the%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+this%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+that%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+my%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+the%s+selected%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+the%s+current%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+the%s+existing%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+selected%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+current%s+([%w_]+)%f[%W]",
    "%f[%w]double%s+existing%s+([%w_]+)%f[%W]",
    "%f[%w]doubled%s+the%s+selected%s+([%w_]+)%f[%W]",
    "%f[%w]doubling%s+the%s+selected%s+([%w_]+)%f[%W]",
    "%f[%w]doubled%s+the%s+([%w_]+)%f[%W]",
    "%f[%w]doubling%s+the%s+([%w_]+)%f[%W]",
  }
  for _, pat in ipairs(double_track_patterns) do
    local target = lt:match(pat)
    if target then
      for _, object in ipairs(objects) do
        if target == object then return true end
      end
    end
  end

  for _, verb in ipairs(verbs) do
    local pos = 1
    while true do
      local s, e = lt:find("%f[%w]" .. verb .. "%f[%W]", pos)
      if not s then break end
      local phrase = lt:sub(e + 1, math.min(#lt, e + 100))
      phrase = phrase:match("^%s*([^%.;\n]*)") or phrase
      for _, object in ipairs(objects) do
        local os, oe = phrase:find("%f[%w]" .. object .. "%f[%W]")
        if os then
          local before = phrase:sub(1, os - 1)
          local after = phrase:sub(oe + 1)
          if word_count(before) <= 5
              and not has_non_track_target(before)
              and not has_near_non_track_target_after_object(after) then
            return true
          end
        end
      end
      pos = e + 1
    end
  end
  return false
end

function Code.lua_duplicates_tracks(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.Main_OnCommand%s*%(%s*40062%s*,")
      or stripped:find("reaper%.Main_OnCommandEx%s*%(%s*40062%s*,") then
    return true
  end
  if stripped:find("reaper%.GetTrackStateChunk%s*%(")
      and stripped:find("reaper%.SetTrackStateChunk%s*%(") then
    return true
  end
  return false
end

function Code.find_inert_track_duplication(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not Code.prompt_requests_track_duplication(user_text) then return nil end
  if Code.lua_duplicates_tracks(lua_code) then return nil end

  local findings = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    if code_line:find("reaper%.InsertTrackAtIndex%s*%(")
        or code_line:find("reaper%.Main_OnCommand%s*%(%s*40001%s*,") then
      findings[#findings + 1] = {
        line = line_no,
        source = line:match("^%s*(.-)%s*$"),
        reason = "inert_track_duplication",
      }
    end
  end
  if #findings == 0 then
    findings[#findings + 1] = {
      line = 1,
      source = "",
      reason = "missing_track_duplication",
    }
  end
  return findings
end

-- True media-item duplication must preserve full item/take state, and a
-- state-chunk clone must not reuse the source item/take GUIDs. This detector
-- intentionally accepts the documented callback pattern only: a single
-- precomputed replacement GUID would assign the same identity to every take.
function Code.prompt_requests_item_duplication(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  lt = lt:gsub("[\226\128\153']", ""):gsub("%s+", " ")
  local verbs = {
    "copy", "copies", "copied", "copying",
    "duplicate", "duplicates", "duplicated", "duplicating",
    "clone", "clones", "cloned", "cloning",
    "repeat", "repeats", "repeated", "repeating",
  }
  local objects = { "item", "items", "clip", "clips", "take", "takes" }
  for _, verb in ipairs(verbs) do
    local pos = 1
    while true do
      local s, e = lt:find("%f[%w]" .. verb .. "%f[%W]", pos)
      if not s then break end
      local near = lt:sub(math.max(1, s - 80), math.min(#lt, e + 80))
      for _, object in ipairs(objects) do
        if near:find("%f[%w]" .. object .. "%f[%W]") then return true end
      end
      pos = e + 1
    end
  end
  return false
end

function Code.find_unsafe_item_duplication(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not Code.prompt_requests_item_duplication(user_text) then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local gets_chunk = stripped:find("reaper%.GetItemStateChunk%s*%(") ~= nil
  local sets_chunk = stripped:find("reaper%.SetItemStateChunk%s*%(") ~= nil
  if gets_chunk or sets_chunk then
    local has_full_guid_pattern = stripped:find("I%?GUID", 1, false) ~= nil
    local has_callback = stripped:find("gsub%s*%(") ~= nil
      and stripped:find("function%s*%(") ~= nil
    local has_fresh_guid = stripped:find(
      'reaper%.genGuid%s*%(%s*""%s*%)') ~= nil
      or stripped:find("reaper%.genGuid%s*%(%s*''%s*%)") ~= nil
    if not (gets_chunk and sets_chunk and has_full_guid_pattern
        and has_callback and has_fresh_guid) then
      return {
        {
          line = 1,
          source = "",
          reason = "unsafe_item_chunk_guid_clone",
        },
      }
    end
  end
  if not (gets_chunk and sets_chunk)
      and stripped:find("reaper%.AddMediaItemToTrack%s*%(") then
    return {
      {
        line = 1,
        source = "",
        reason = "incomplete_active_take_item_clone",
      },
    }
  end
  local lt = tostring(user_text or ""):lower()
  local wants_crossfade = lt:find("crossfade", 1, true) ~= nil
    or lt:find("cross fade", 1, true) ~= nil
    or lt:find("overlap", 1, true) ~= nil
  if wants_crossfade then
    -- Conservative requirement: a real repeat-boundary crossfade needs an
    -- explicit literal reaper.SetMediaItemInfo_Value(..., "D_FADEINLEN", ...)
    -- write on the appended block. A chunk-based clone that merely carries or
    -- mutates FADEIN lines inside the item state chunk is deliberately NOT
    -- accepted here: copying (or rewriting) a source item's fade does not
    -- prove the FIRST appended item's boundary fade is correct, because that
    -- fade belongs to the source item, not the new seam between the original
    -- tail and the repeat head. Requiring the literal D_FADEINLEN write costs
    -- at most one wasted retry on a chunk-fade script but never green-lights an
    -- unproven boundary fade. (No narrow chunk-fade exemption is attempted: it
    -- cannot be made provably nonzero-and-boundary-correct conservatively.)
    local has_fadein_write = stripped:find(
      "reaper%.SetMediaItemInfo_Value%s*%([^\n]-[\"']D_FADEINLEN[\"']") ~= nil
    if not has_fadein_write then
      return {
        {
          line = 1,
          source = "",
          reason = "missing_repeat_boundary_crossfade",
        },
      }
    end
  end
  return nil
end

function Code.prompt_forbids_new_track_creation(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  lt = lt:gsub("[\226\128\153']", ""):gsub("%s+", " ")
  if Code.prompt_requests_track_creation(user_text) then return false end
  local objects = { "track", "tracks", "bus", "buses", "return", "returns" }
  for _, obj in ipairs(objects) do
    if lt:find("%f[%w]no%s+new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]dont%s+create%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]dont%s+add%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]do%s+not%s+create%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]do%s+not%s+add%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]never%s+create%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
    if lt:find("%f[%w]never%s+add%s+.-%f[%w]new%s+" .. obj .. "%f[%W]") then return true end
  end
  return false
end

function Code.find_forbidden_track_creation(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not Code.prompt_forbids_new_track_creation(user_text) then return nil end
  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    if code_line:find("reaper%.InsertTrackAtIndex%s*%(")
        or code_line:find("reaper%.Main_OnCommand%s*%(%s*40001%s*,") then
      violations[#violations + 1] = {
        line = line_no,
        source = line:match("^%s*(.-)%s*$"),
        reason = "forbidden_new_track_creation",
      }
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.prompt_forbids_fx_addition(user_text)
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  lt = lt:gsub("[\226\128\153']", ""):gsub("%s+", " ")
  local fx_nouns = {
    "effect", "effects", "fx", "plugin", "plugins",
    "eq", "compressor", "delay", "reverb", "gate", "limiter",
  }
  local function _has_fx_noun(text)
    for _, noun in ipairs(fx_nouns) do
      if text:find("%f[%w]" .. noun .. "%f[%W]") then return true end
    end
    return false
  end
  local function _add_verb_is_negated(clause, verb_start)
    local before = clause:sub(1, verb_start - 1):gsub("%s+", " ")
    return before:find("%f[%w]do%s+not%s*$") ~= nil
        or before:find("%f[%w]do%s+not%s+ever%s*$") ~= nil
        or before:find("%f[%w]dont%s*$") ~= nil
        or before:find("%f[%w]dont%s+ever%s*$") ~= nil
        or before:find("%f[%w]never%s*$") ~= nil
        or before:find("%f[%w]not%s+to%s*$") ~= nil
  end
  local function _conditional_missing_fx_add_spans()
    local spans, pos = {}, 1
    while true do
      local match_start, match_end, clause =
        lt:find("%f[%w]if%s+([^%.;\n]+)", pos)
      if not match_start then break end
      local missing_fx = false
      for _, noun in ipairs(fx_nouns) do
        if clause:find("%f[%w]no%s+[^,]*%f[%w]" .. noun .. "%f[%W]")
           or (clause:find("%f[%w]" .. noun .. "%f[%W]")
               and (clause:find("%f[%w]missing%f[%W]")
                    or clause:find("%f[%w]not%s+there%f[%W]")
                    or clause:find("%f[%w]doesnt%s+have%f[%W]")
                    or clause:find("%f[%w]dont%s+have%f[%W]"))) then
          missing_fx = true
          break
        end
      end
      if missing_fx then
        for _, verb in ipairs({ "add", "insert", "load", "put" }) do
          local s, e = clause:find("%f[%w]" .. verb .. "%f[%W]")
          if s and not _add_verb_is_negated(clause, s) then
            local after = clause:sub(e + 1)
            if after:find("^%s+one%f[%W]")
               or after:find("^%s+it%f[%W]")
               or _has_fx_noun(after) then
              spans[#spans + 1] = { s = match_start, e = match_end }
              break
            end
          end
        end
      end
      pos = match_end + 1
    end
    return spans
  end
  local hard_lt = lt
  local conditional_add_spans = _conditional_missing_fx_add_spans()
  if #conditional_add_spans > 0 then
    local parts, last = {}, 1
    for _, span in ipairs(conditional_add_spans) do
      parts[#parts + 1] = hard_lt:sub(last, span.s - 1)
      parts[#parts + 1] = string.rep(" ", span.e - span.s + 1)
      last = span.e + 1
    end
    parts[#parts + 1] = hard_lt:sub(last)
    hard_lt = table.concat(parts)
  end
  local objects = { "effect", "effects", "fx", "plugin", "plugins" }
  -- "No other/extra/additional FX" limits additions to the FX already named;
  -- it is not a blanket prohibition on those requested FX. Mask only that
  -- partial constraint here. The relevance validator separately rejects an
  -- unrequested extra plugin, while any independent blanket no-FX clause
  -- remains visible to the checks below.
  local function _mask_partial_fx_constraint(pattern)
    hard_lt = hard_lt:gsub(pattern, function(match)
      return string.rep(" ", #match)
    end)
  end
  for _, obj in ipairs(objects) do
    for _, lead in ipairs({
      "no", "add%s+no", "do%s+not%s+add", "dont%s+add",
      "never%s+add", "without%s+adding",
    }) do
      for _, qualifier in ipairs({
        "other", "any%s+other", "extra", "any%s+extra",
        "additional", "any%s+additional", "another",
      }) do
        _mask_partial_fx_constraint(
          "%f[%w]" .. lead .. "%s+" .. qualifier .. "%s+"
            .. obj .. "%f[%W]")
      end
    end
  end
  for _, obj in ipairs(objects) do
    if hard_lt:find("%f[%w]no%s+new%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
    if hard_lt:find("%f[%w]no%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
    if hard_lt:find("%f[%w]do%s+not%s+add%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
    if hard_lt:find("%f[%w]dont%s+add%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
    if hard_lt:find("%f[%w]never%s+add%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
    if hard_lt:find("%f[%w]without%s+adding%s+[^%.;\n]*" .. obj .. "%f[%W]") then return true end
  end
  return false
end

function Code.find_forbidden_fx_addition(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not Code.prompt_forbids_fx_addition(user_text) then return nil end
  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    if code_line:find("reaper%.TrackFX_AddByName%s*%(")
        or code_line:find("reaper%.TakeFX_AddByName%s*%(") then
      violations[#violations + 1] = {
        line = line_no,
        source = line:match("^%s*(.-)%s*$"),
        reason = "forbidden_fx_addition",
      }
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.find_unrequested_instrument_fx_addition(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local lt = tostring(user_text or ""):lower():gsub("[\226\128\153']", ""):gsub("%s+", " ")
  if lt == "" then return nil end
  local names_instrument_track =
       lt:find("%f[%w]synth%f[%W]") ~= nil
    or lt:find("%f[%w]synths%f[%W]") ~= nil
    or lt:find("%f[%w]piano%f[%W]") ~= nil
    or lt:find("%f[%w]bass%f[%W]") ~= nil
    or lt:find("%f[%w]pad%f[%W]") ~= nil
    or lt:find("%f[%w]lead%f[%W]") ~= nil
    or lt:find("%f[%w]keys%f[%W]") ~= nil
  if not names_instrument_track then return nil end

  local explicit_instrument =
       lt:find("%f[%w]load%s+.-%f[%w]instrument%f[%W]") ~= nil
    or lt:find("%f[%w]add%s+.-%f[%w]instrument%f[%W]") ~= nil
    or lt:find("%f[%w]virtual%s+instrument%f[%W]") ~= nil
    or lt:find("%f[%w]vsti%f[%W]") ~= nil
    or lt:find("%f[%w]vst3i%f[%W]") ~= nil
    or lt:find("%f[%w]synth%s+plugin%f[%W]") ~= nil
    or lt:find("%f[%w]sampler%f[%W]") ~= nil
    or lt:find("%f[%w]sound%s+source%f[%W]") ~= nil
    or lt:find("reasynth", 1, true) ~= nil
    or lt:find("rea synth", 1, true) ~= nil
    or lt:find("twin 3", 1, true) ~= nil
    or lt:find("serum", 1, true) ~= nil
    or lt:find("kontakt", 1, true) ~= nil
  if explicit_instrument then return nil end

  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    if code_line:find("reaper%.TrackFX_AddByName%s*%(")
        or code_line:find("reaper%.TakeFX_AddByName%s*%(") then
      local lower = code_line:lower()
      if lower:find("vst3i:", 1, true)
          or lower:find("vsti:", 1, true)
          or lower:find("reasynth", 1, true)
          or lower:find("twin 3", 1, true)
          or lower:find("serum", 1, true)
          or lower:find("kontakt", 1, true) then
        violations[#violations + 1] = {
          line = line_no,
          source = line:match("^%s*(.-)%s*$"),
          reason = "unrequested_instrument_fx_addition",
        }
      end
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.prompt_requests_inferred_created_track_name(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  local has_part =
       lt:find("%f[%w]drum%f[%W]") ~= nil
    or lt:find("%f[%w]drums%f[%W]") ~= nil
    or lt:find("%f[%w]kick%f[%W]") ~= nil
    or lt:find("%f[%w]snare%f[%W]") ~= nil
    or lt:find("%f[%w]bass%f[%W]") ~= nil
    or lt:find("%f[%w]piano%f[%W]") ~= nil
    or lt:find("%f[%w]keys%f[%W]") ~= nil
    or lt:find("%f[%w]vocal%f[%W]") ~= nil
    or lt:find("%f[%w]guitar%f[%W]") ~= nil
  if not has_part then return false end
  if Code.prompt_requests_track_creation(user_text) then return true end
  local has_midi =
       lt:find("%f[%w]midi%f[%W]") ~= nil
    or lt:find("%f[%w]notes%f[%W]") ~= nil
  local has_idea =
       lt:find("%f[%w]idea%f[%W]") ~= nil
    or lt:find("%f[%w]pattern%f[%W]") ~= nil
    or lt:find("%f[%w]part%f[%W]") ~= nil
    or lt:find("%f[%w]clip%f[%W]") ~= nil
    or lt:find("%f[%w]item%f[%W]") ~= nil
  return has_midi and has_idea
end

function Code.prompt_likely_needs_lua_action(user_text)
  local lt = Code._localized_action_intent_text(user_text)
  if lt == "" then return false end
  if Code.prompt_is_question_or_readonly
      and Code.prompt_is_question_or_readonly(user_text) then
    return false
  end
  if lt:find("reaper lua script", 1, true)
      or lt:find("reaper lua", 1, true)
      or lt:find("reascript", 1, true)
      or (lt:find("lua script", 1, true)
        and lt:find("reaper", 1, true)) then
    return true
  end
  if Code.prompt_requests_track_creation(user_text)
      or Code.prompt_requests_inferred_created_track_name(user_text)
      or (Code.prompt_requests_bus_or_return_send_routing
        and Code.prompt_requests_bus_or_return_send_routing(user_text))
      or (Code.prompt_requests_sidechain_ducking
        and Code.prompt_requests_sidechain_ducking(user_text))
      or (Code.prompt_requests_exclusive_track_selection
        and Code.prompt_requests_exclusive_track_selection(user_text))
      or (Code.prompt_requests_region_creation
        and Code.prompt_requests_region_creation(user_text)) then
    return true
  end
  local track_property_text =
    Code._typed_action_track_property_intent_text(user_text)
  local track_property_words = " "
    .. track_property_text:gsub("[^%w]+", " "):gsub("%s+", " ")
    .. " "
  local has_track_property_action = false
  for _, word in ipairs({
    "volume", "vol", "fader", "level", "pan", "panned", "mute", "muted",
    "unmute", "solo", "soloed", "unsolo", "master send", "main send",
    "master parent", "parent send", "master output", "rename", "renamed",
    "call", "called",
  }) do
    if track_property_words:find(" " .. word .. " ", 1, true) then
      has_track_property_action = true
      break
    end
  end
  if has_track_property_action then
    for _, word in ipairs({ "track", "tracks", "bus", "aux", "selected" }) do
      if track_property_words:find(" " .. word .. " ", 1, true) then
        return true
      end
    end
  end
  local action_words = {
    "add", "adjust", "arm", "change", "clean up", "close", "configure", "create",
    "insert", "make", "modify", "move", "mute", "name", "pan", "put",
    "route", "select", "set", "set up", "solo", "tweak", "use",
  }
  local object_words = {
    "track", "tracks", "fx", "plugin", "eq", "compressor", "reverb",
    "delay", "bus", "send", "marker", "region", "midi", "item",
    "project", "session", "tab",
    "folder", "folders", "reaeq", "reacomp", "readelay", "reaverbate",
    "reagate", "realimit",
  }
  local has_action = false
  for _, word in ipairs(action_words) do
    if lt:find("%f[%w]" .. word .. "%f[%W]") then
      has_action = true
      break
    end
  end
  if not has_action then return false end
  for _, word in ipairs(object_words) do
    if lt:find("%f[%w]" .. word .. "%f[%W]") then return true end
  end
  return false
end

function Code.no_code_reply_is_clarification(reply_text)
  local text = tostring(reply_text or "")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or #text > 400 then return false end
  if not text:find("%?%s*$") then return false end

  local lt = text:lower():gsub("%s+", " ")
  local markers = {
    "what color", "which color", "what colour", "which colour",
    "one color", "different colors", "one colour", "different colours",
    "which track", "what track", "which tracks", "what tracks",
    "which region", "what region", "which regions", "what regions",
    "which marker", "what marker", "which item", "what item",
    "which take", "what take", "which plugin", "what plugin",
    "which fx", "what fx", "which parameter", "what parameter",
    "which value", "what value", "what name", "which name",
  }
  for _, marker in ipairs(markers) do
    if lt:find(marker, 1, true) then return true end
  end

  if lt:find(" or ", 1, true) == nil then return false end
  local asks_for_choice =
       lt:find("do you want", 1, true) ~= nil
    or lt:find("should i", 1, true) ~= nil
    or lt:find("should the", 1, true) ~= nil
    or lt:find("should each", 1, true) ~= nil
    or lt:find("would you like", 1, true) ~= nil
    or lt:find("which ", 1, true) ~= nil
    or lt:find("what ", 1, true) ~= nil
  if not asks_for_choice then return false end

  local subjects = {
    "color", "colour", "track", "region", "marker", "item", "take",
    "plugin", "fx", "parameter", "value", "name", "tempo", "folder",
    "bus", "send",
  }
  for _, subject in ipairs(subjects) do
    if lt:find(subject, 1, true) then return true end
  end
  return false
end

function Code.prompt_requests_region_creation(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if lt:find("%f[%w]region%f[%W]") == nil
      and lt:find("%f[%w]regions%f[%W]") == nil then
    return false
  end
  return lt:find("%f[%w]make%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]from%f[%W]") ~= nil
end

function Code.prompt_requests_point_marker_creation(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return false end
  if lt:find("%f[%w]marker%f[%W]") == nil
      and lt:find("%f[%w]markers%f[%W]") == nil then
    return false
  end
  if lt:find("%f[%w]region%f[%W]") ~= nil
      or lt:find("%f[%w]regions%f[%W]") ~= nil then
    return false
  end
  return lt:find("%f[%w]make%f[%W]") ~= nil
    or lt:find("%f[%w]create%f[%W]") ~= nil
    or lt:find("%f[%w]add%f[%W]") ~= nil
    or lt:find("%f[%w]insert%f[%W]") ~= nil
    or lt:find("%f[%w]place%f[%W]") ~= nil
end

function Code.lua_creates_region_for_point_marker(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.AddProjectMarker2?%s*%([^,]+,%s*true%s*,") then
    return true
  end
  if stripped:find("reaper%.AddRegionOrMarker%s*%([^,]+,%s*true%s*,") then
    return true
  end
  return false
end

function Code.lua_creates_requested_region(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if stripped:find("reaper%.AddProjectMarker2?%s*%([^,]+,%s*true%s*,") then
    return true
  end
  if stripped:find("reaper%.AddRegionOrMarker%s*%([^,]+,%s*true%s*,") then
    return true
  end
  return false
end

function Code.lua_names_created_track(lua_code)
  if not lua_code or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  return stripped:find(
    "reaper%.GetSetMediaTrackInfo_String%s*%([^%)]-[\"']P_NAME[\"'][^%)]-,%s*true%s*%)")
    ~= nil
end

function Code._numeric_track_target_from_user_text(user_text)
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt == "" then return nil end
  local targets = {}
  local function add_target(n)
    n = tonumber(n)
    if n and n >= 1 and n <= 999 then targets[n] = true end
  end
  local patterns = {
    "%f[%w]on%s+track%s*#?%s*(%d+)%f[%W]",
    "%f[%w]to%s+track%s*#?%s*(%d+)%f[%W]",
    "%f[%w]for%s+track%s*#?%s*(%d+)%f[%W]",
    "%f[%w]from%s+track%s*#?%s*(%d+)%f[%W]",
    "%f[%w]onto%s+track%s*#?%s*(%d+)%f[%W]",
    "%f[%w]on%s+track%s+number%s*#?%s*(%d+)%f[%W]",
    "%f[%w]to%s+track%s+number%s*#?%s*(%d+)%f[%W]",
    "%f[%w]for%s+track%s+number%s*#?%s*(%d+)%f[%W]",
  }
  for _, pat in ipairs(patterns) do
    for n in lt:gmatch(pat) do add_target(n) end
  end
  local only
  for n in pairs(targets) do
    if only and only ~= n then return nil end
    only = n
  end
  return only
end

function Code._text_mentions_literal(text, literal)
  local needle = tostring(literal or ""):lower()
    :gsub("^%s+", "")
    :gsub("%s+$", "")
    :gsub("%s+", " ")
  if needle == "" then return false end
  local hay = tostring(text or ""):lower():gsub("%s+", " ")
  return hay:find(needle, 1, true) ~= nil
end

function Code.find_numeric_track_target_name_guard_mismatches(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local display_idx = Code._numeric_track_target_from_user_text(user_text)
  if not display_idx then return nil end
  local expected_api_idx = display_idx - 1
  local track_vars, name_vars = {}, {}
  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    local tr_var, api_idx = code_line:match(
      "^%s*local%s+([%a_][%w_]*)%s*=%s*reaper%.GetTrack%s*%(%s*0%s*,%s*(%d+)%s*%)")
    if not tr_var then
      tr_var, api_idx = code_line:match(
        "^%s*([%a_][%w_]*)%s*=%s*reaper%.GetTrack%s*%(%s*0%s*,%s*(%d+)%s*%)")
    end
    if tr_var and tonumber(api_idx) == expected_api_idx then
      track_vars[tr_var] = { api_idx = tonumber(api_idx), line = line_no }
    end

    local _ret_var, name_var, from_tr = code_line:match(
      "^%s*local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*reaper%.GetTrackName%s*%(%s*([%a_][%w_]*)")
    if not name_var then
      local lhs1, lhs2, arg_tr = code_line:match(
        "^%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*reaper%.GetTrackName%s*%(%s*([%a_][%w_]*)")
      if lhs1 then
        name_var, from_tr = lhs2, arg_tr
      end
    end
    if name_var and from_tr and track_vars[from_tr] then
      name_vars[name_var] = from_tr
    end

    local check_var, literal =
      code_line:match("^%s*if%s+([%a_][%w_]*)%s*~=%s*\"([^\"]*)\"%s*then")
    if not check_var then
      check_var, literal =
        code_line:match("^%s*if%s+([%a_][%w_]*)%s*~=%s*'([^']*)'%s*then")
    end
    if not check_var then
      literal, check_var =
        code_line:match("^%s*if%s+\"([^\"]*)\"%s*~=%s*([%a_][%w_]*)%s*then")
    end
    if not check_var then
      literal, check_var =
        code_line:match("^%s*if%s+'([^']*)'%s*~=%s*([%a_][%w_]*)%s*then")
    end
    local source_tr = check_var and name_vars[check_var]
    if source_tr and track_vars[source_tr]
        and not Code._text_mentions_literal(user_text, literal) then
      violations[#violations + 1] = {
        line = line_no,
        track_line = track_vars[source_tr].line,
        display_idx = display_idx,
        api_idx = expected_api_idx,
        guard_name = literal,
        source = line:match("^%s*(.-)%s*$"),
      }
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.find_literal_gettrack_index_mismatches(lua_code, snapshot)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if type(snapshot) ~= "string" or snapshot == "" then return nil end
  local tracks = {}
  local track_count
  track_count = tonumber(snapshot:match("Tracks%s*%(%s*N%s*=%s*(%d+)%s*%)"))
  local in_track_rows = false
  for line in snapshot:gmatch("[^\r\n]+") do
    if line:match("^%s*Tracks%s*%(") then
      in_track_rows = true
    elseif in_track_rows then
      local idx, name = line:match("^%s*(%d+)|([^|]*)|")
      idx = tonumber(idx)
      if not idx or name == nil then
        in_track_rows = false
      else
        tracks[#tracks + 1] = {
          display_idx = idx,
          api_idx = idx - 1,
          name = name,
          name_l = tostring(name):lower(),
        }
      end
    end
  end
  if #tracks == 0 and not track_count then return nil end
  local live_track_count = track_count or #tracks

  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local line_l = line:lower()
    local code_line = line:gsub("%-%-.*$", "")
    local inserted_idx =
      tonumber(code_line:match("reaper%.InsertTrackAtIndex%s*%(%s*(%d+)%s*,"))
    if inserted_idx and inserted_idx <= live_track_count then
      live_track_count = live_track_count + 1
    end
    for idx_text in code_line:gmatch("reaper%.GetTrack%s*%(%s*0%s*,%s*(%d+)%s*%)") do
      local api_idx = tonumber(idx_text)
      local expected
      local reason
      if live_track_count and api_idx and api_idx >= live_track_count then
        expected = live_track_count > 0 and (live_track_count - 1) or 0
        reason = "out_of_range"
      end
      for _, tr in ipairs(tracks) do
        local mentions_track_number =
          line_l:find("%f[%w]track%s*" .. tostring(tr.display_idx) .. "%f[%W]") ~= nil
        local mentions_name = tr.name_l ~= "" and line_l:find(tr.name_l, 1, true) ~= nil
        if (mentions_track_number or mentions_name)
            and api_idx and api_idx ~= tr.api_idx then
          expected = tr.api_idx
          reason = mentions_name and "name_comment_mismatch"
            or "track_number_comment_mismatch"
          break
        end
      end
      if expected then
        violations[#violations + 1] = {
          line = line_no,
          api_idx = api_idx,
          expected_api_idx = expected,
          reason = reason,
          source = line:match("^%s*(.-)%s*$"),
        }
      end
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.find_track_creation_index_misuse(lua_code, user_text, snapshot)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not Code.prompt_requests_track_creation(user_text) then return nil end
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if lt:find("%f[%w]before%f[%W]")
      or lt:find("%f[%w]after%f[%W]")
      or lt:find("at position", 1, true)
      or lt:find("at track", 1, true)
      or lt:find("insert position", 1, true) then
    return nil
  end
  local track_count = nil
  if type(snapshot) == "string" then
    track_count = tonumber(snapshot:match("Tracks%s*%(%s*N%s*=%s*(%d+)%s*%)"))
  end
  if not track_count then track_count = 0 end

  local table_lengths = {}
  for var, body in lua_code:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*{%s*(.-)%s*}") do
    local count = 0
    for _ in body:gmatch("[\"'][^\"']+[\"']") do
      count = count + 1
    end
    if count > 0 then table_lengths[var] = count end
  end
  do
    local collect_var, depth, count
    for line in lua_code:gmatch("[^\r\n]+") do
      local code_line = line:gsub("%-%-.*$", "")
      if collect_var then
        if code_line:match("^%s*{") then
          count = count + 1
        elseif code_line:match("^%s*[\"'][^\"']+[\"']") then
          count = count + 1
        end
        for _ in code_line:gmatch("{") do depth = depth + 1 end
        for _ in code_line:gmatch("}") do depth = depth - 1 end
        if depth <= 0 then
          if count > 0 then table_lengths[collect_var] = count end
          collect_var, depth, count = nil, nil, nil
        end
      else
        local var, rest = code_line:match(
          "^%s*local%s+([%a_][%w_]*)%s*=%s*{%s*(.*)$")
        if var and not rest:find("}", 1, true) then
          collect_var, depth, count = var, 1, 0
        end
      end
    end
  end

  local violations = {}
  local line_no = 0
  local active_loop = nil
  local active_ensure_count = nil
  local ensure_counted = false
  local counttracks_vars = {}
  local counttracks_append_vars = {}
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local ensure_count = line:match(
      "^%s*while%s+reaper%.CountTracks%s*%(%s*0%s*%)%s*<%s*(%d+)%s*do%s*$")
    if ensure_count then
      active_ensure_count = tonumber(ensure_count)
      ensure_counted = false
    end
    local loop_var, loop_first, loop_last = line:match(
      "^%s*for%s+([%a_][%w_]*)%s*=%s*(%d+)%s*,%s*(%d+)%s*do%s*$")
    if not loop_var then
      local len_var
      loop_var, loop_first, len_var = line:match(
        "^%s*for%s+([%a_][%w_]*)%s*=%s*(%d+)%s*,%s*#([%a_][%w_]*)%s*do%s*$")
      loop_last = len_var and table_lengths[len_var] or nil
    end
    if not loop_var then
      local ignored, len_var
      loop_var, ignored, len_var = line:match(
        "^%s*for%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%s*%(%s*([%a_][%w_]*)%s*%)%s*do%s*$")
      loop_first = loop_var and 1 or nil
      loop_last = len_var and table_lengths[len_var] or nil
    end
    if loop_var then
      active_loop = {
        var = loop_var,
        first = tonumber(loop_first),
        last = tonumber(loop_last),
        counted_insert = false,
      }
    end
    local insert_idx =
      tonumber(line:match("reaper%.InsertTrackAtIndex%s*%(%s*(%d+)%s*,"))
    local handled_insert = false
    if insert_idx then
      track_count = track_count + 1
      handled_insert = true
    else
      local insert_var = line:match(
        "reaper%.InsertTrackAtIndex%s*%(%s*([%a_][%w_]*)%s*,")
      local known_count = insert_var and counttracks_vars[insert_var]
      if known_count then
        track_count = math.max(track_count, known_count + 1)
        counttracks_append_vars[insert_var] = true
        handled_insert = true
      end
    end
    if not handled_insert
        and active_loop and not active_loop.counted_insert
        and active_loop.first and active_loop.last
        and line:find("reaper%.InsertTrackAtIndex%s*%(%s*reaper%.CountTracks%s*%(%s*0%s*%)%s*,") then
      track_count = track_count + math.abs(active_loop.last - active_loop.first) + 1
      active_loop.counted_insert = true
    elseif not handled_insert
        and active_loop and not active_loop.counted_insert
        and active_loop.first and active_loop.last
        and (line:find("reaper%.InsertTrackAtIndex%s*%(%s*"
          .. active_loop.var .. "%s*,")
          or line:find("reaper%.InsertTrackAtIndex%s*%(%s*"
            .. active_loop.var .. "%s*[%+%-]%s*%d+%s*,")) then
      track_count = track_count + math.abs(active_loop.last - active_loop.first) + 1
      active_loop.counted_insert = true
    elseif not handled_insert
        and active_ensure_count and not ensure_counted
        and line:find("reaper%.InsertTrackAtIndex%s*%(%s*reaper%.CountTracks%s*%(%s*0%s*%)%s*,") then
      if active_ensure_count > track_count then
        track_count = active_ensure_count
      end
      ensure_counted = true
    elseif not handled_insert
        and line:find("reaper%.InsertTrackAtIndex%s*%(%s*reaper%.CountTracks%s*%(%s*0%s*%)%s*,") then
      track_count = track_count + 1
    end
    local count_var = line:match(
      "^%s*local%s+([%a_][%w_]*)%s*=%s*reaper%.CountTracks%s*%(%s*0%s*%)")
    if not count_var then
      count_var = line:match(
        "^%s*([%a_][%w_]*)%s*=%s*reaper%.CountTracks%s*%(%s*0%s*%)")
    end
    if count_var then
      counttracks_vars[count_var] = track_count
    end
    for idx_text in line:gmatch("reaper%.GetTrack%s*%(%s*0%s*,%s*(%d+)%s*%)") do
      local api_idx = tonumber(idx_text)
      if api_idx and api_idx >= track_count then
        violations[#violations + 1] = {
          line = line_no,
          api_idx = api_idx,
          expected_api_idx = track_count > 0 and (track_count - 1) or 0,
          reason = "created_track_out_of_range",
          source = line:match("^%s*(.-)%s*$"),
        }
      end
    end
    for var in line:gmatch(
        "reaper%.GetTrack%s*%(%s*0%s*,%s*([%a_][%w_]*)%s*%)") do
      local known_count = counttracks_vars[var]
      if known_count and known_count > 0
          and not counttracks_append_vars[var] then
        violations[#violations + 1] = {
          line = line_no,
          api_idx = var,
          expected_api_idx = var .. " - 1",
          reason = "counttracks_out_of_range",
          source = line:match("^%s*(.-)%s*$"),
        }
      end
    end
    if active_loop and line:match("^%s*end%s*$") then
      active_loop = nil
    end
    if active_ensure_count and line:match("^%s*end%s*$") then
      active_ensure_count = nil
      ensure_counted = false
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.repair_repeated_zero_track_insertion_order(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then
    return lua_code, false, nil
  end
  if not Code.prompt_requests_track_creation(user_text) then
    return lua_code, false, nil
  end
  if not lua_code:find("reaper%.InsertTrackAtIndex%s*%(%s*0%s*,") then
    return lua_code, false, nil
  end

  local newline = lua_code:find("\r\n", 1, true) and "\r\n" or "\n"
  local lines = {}
  lua_code:gsub("([^\r\n]*)\r?\n?", function(line)
    if line ~= "" or #lines == 0 or lua_code:sub(-1) == "\n" then
      lines[#lines + 1] = line
    end
  end)
  if #lines > 0 and lines[#lines] == "" and lua_code:sub(-1) ~= "\n" then
    lines[#lines] = nil
  end

  local tables = {}
  for i, line in ipairs(lines) do
    local var, body =
      line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*{%s*(.-)%s*}%s*$")
    if var and body then
      local values = {}
      for name in body:gmatch("[\"']([^\"']+)[\"']") do
        values[#values + 1] = name
      end
      if #values > 0 then
        tables[var] = { line = i, values = values }
      end
    end
  end

  local function quoted_list(values)
    local out = {}
    for _, value in ipairs(values) do
      out[#out + 1] = string.format("%q", value)
    end
    return "{ " .. table.concat(out, ", ") .. " }"
  end

  for start_idx, line in ipairs(lines) do
    local indent, loop_var, first_text, last_text =
      line:match("^(%s*)for%s+([%a_][%w_]*)%s*=%s*(%d+)%s*,%s*(%d+)%s*do%s*$")
    local first = tonumber(first_text)
    local last = tonumber(last_text)
    if loop_var and first == 1 and last then
      local end_idx
      for i = start_idx + 1, #lines do
        if lines[i]:match("^%s*end%s*$") then
          end_idx = i
          break
        end
      end
      if end_idx then
        local block = table.concat(lines, "\n", start_idx, end_idx)
        if block:find("reaper%.InsertTrackAtIndex%s*%(%s*0%s*,")
            and block:find("reaper%.GetTrack%s*%(%s*0%s*,%s*0%s*%)") then
          for table_var, info in pairs(tables) do
            local expression_pat =
              table_var .. "%s*%[%s*(%d+)%s*%-%s*" .. loop_var .. "%s*%]"
            local base_text = block:match(expression_pat)
            local base = tonumber(base_text)
            if base == last + 1 and #info.values == last then
              local tracks_var, track_var
              for i = start_idx + 1, end_idx - 1 do
                local lhs, rhs = lines[i]:match(
                  "^%s*([%a_][%w_]*)%s*%[%s*" .. loop_var
                    .. "%s*%]%s*=%s*([%a_][%w_]*)%s*$")
                if lhs and rhs then
                  tracks_var, track_var = lhs, rhs
                  break
                end
              end
              if tracks_var and track_var then
                local function patt(s)
                  return tostring(s or "")
                    :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                end
                local function expected_loop_line(body_line)
                  local trimmed = tostring(body_line or ""):match("^%s*(.-)%s*$") or ""
                  if trimmed == "" or trimmed:match("^%-%-") then return true end
                  if body_line:find("reaper%.InsertTrackAtIndex%s*%(%s*0%s*,") then
                    return true
                  end
                  if body_line:match("^%s*local%s+" .. patt(track_var)
                      .. "%s*=%s*reaper%.GetTrack%s*%(%s*0%s*,%s*0%s*%)%s*$") then
                    return true
                  end
                  if body_line:match("^%s*reaper%.GetSetMediaTrackInfo_String%s*%(%s*"
                      .. patt(track_var)
                      .. "%s*,%s*[\"']P_NAME[\"']%s*,%s*"
                      .. patt(table_var)
                      .. "%s*%[%s*"
                      .. patt(base_text)
                      .. "%s*%-%s*"
                      .. patt(loop_var)
                      .. "%s*%]%s*,%s*true%s*%)%s*$") then
                    return true
                  end
                  if body_line:match("^%s*" .. patt(tracks_var)
                      .. "%s*%[%s*" .. patt(loop_var)
                      .. "%s*%]%s*=%s*" .. patt(track_var) .. "%s*$") then
                    return true
                  end
                  return false
                end
                local unsupported_loop_body = false
                for i = start_idx + 1, end_idx - 1 do
                  if not expected_loop_line(lines[i]) then
                    unsupported_loop_body = true
                    break
                  end
                end
                if unsupported_loop_body then
                  return lua_code, false, {
                    line = start_idx,
                    table_var = table_var,
                    loop_var = loop_var,
                    reason = "unsupported_loop_body",
                  }
                end
                local forward = {}
                for i = 1, #info.values do
                  forward[i] = info.values[#info.values - i + 1]
                end
                lines[info.line] = "local " .. table_var .. " = "
                  .. quoted_list(forward)
                local replacement = {
                  indent .. "for " .. loop_var .. " = 1, " .. tostring(last) .. " do",
                  indent .. "  local idx = reaper.CountTracks(0)",
                  indent .. "  reaper.InsertTrackAtIndex(idx, true)",
                  indent .. "  local " .. track_var .. " = reaper.GetTrack(0, idx)",
                  indent .. "  reaper.GetSetMediaTrackInfo_String(" .. track_var
                    .. ', "P_NAME", ' .. table_var .. "[" .. loop_var .. "], true)",
                  indent .. "  " .. tracks_var .. "[" .. loop_var .. "] = " .. track_var,
                  indent .. "end",
                }
                local repaired = {}
                for i = 1, start_idx - 1 do
                  repaired[#repaired + 1] = lines[i]
                end
                for _, replacement_line in ipairs(replacement) do
                  repaired[#repaired + 1] = replacement_line
                end
                for i = end_idx + 1, #lines do
                  repaired[#repaired + 1] = lines[i]
                end
                return table.concat(repaired, newline), true, {
                  line = start_idx,
                  table_var = table_var,
                  loop_var = loop_var,
                }
              end
            end
          end
        end
      end
    end
  end

  return lua_code, false, nil
end

function Code.find_folder_child_boundary_misuse(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  if not lua_code:find("I_FOLDERDEPTH", 1, true) then return nil end
  local lt = tostring(user_text or ""):lower():gsub("%s+", " ")

  local function norm(s)
    s = tostring(s or ""):lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^.-:%s*", "")
    s = s:gsub("^please%s+", "")
    s = s:gsub("^make%s+", ""):gsub("^create%s+", "")
    s = s:gsub("^add%s+", ""):gsub("^set%s+up%s+", "")
    s = s:gsub("^a%s+", ""):gsub("^an%s+", "")
    s = s:gsub("^the%s+", ""):gsub("^your%s+", "")
    s = s:gsub("^named%s+", ""):gsub("^called%s+", "")
    s = s:gsub("^sub%-?tracks?%s+", ""):gsub("^tracks?%s+", "")
    s = s:gsub("%s+tracks?$", ""):gsub("%s+folder$", "")
    return s:gsub("%s+", " ")
  end

  local function clean_display(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s:gsub("%s+", " ")
  end

  local children, child_set = {}, {}
  local child_display = {}
  local function add_child(child, display)
    local normalized = norm(child)
    if normalized ~= "" then
      children[#children + 1] = normalized
      child_set[normalized] = true
      child_display[normalized] = clean_display(display or child)
    end
  end

  local function add_children_from_text(text)
    text = tostring(text or "")
    local quoted = false
    for child in text:gmatch("[\"']([^\"']+)[\"']") do
      add_child(child, child)
      quoted = true
    end
    if quoted then return end
    text = text:gsub("[%.%?].*$", "")
    text = text:gsub("%s+inside%s+it.*$", "")
    text = text:gsub(",%s*then%s+.*$", "")
    text = text:gsub("%s+then%s+.*$", "")
    text = text:gsub(",%s*and%s+", ","):gsub("%s+and%s+", ",")
    for part in text:gmatch("[^,]+") do
      add_child(part, part)
    end
  end

  local exact_child_only_prompt = false
  local parent_text, child_text = lt:match(
    "([%w%s%-%_']+%s+folder)%s+should%s+contain%s+([^%.%?]+)%s+only")
  if parent_text and child_text then
    exact_child_only_prompt = true
  end
  if not child_text or not parent_text then
    child_text, parent_text =
      lt:match("make%s+(.+)%s+children%s+of%s+([^%.]+)")
  end
  if not child_text or not parent_text then
    parent_text, child_text = lt:match(
      "folder%s+named%s+([^%.%?]+)%s+with%s+(.+)%s+inside")
  end
  if not child_text or not parent_text then
    parent_text, child_text = lt:match(
      "folder%s+called%s+([^%.%?]+)%s+with%s+(.+)%s+inside")
  end
  if not child_text or not parent_text then
    parent_text, child_text = lt:match(
      "(.+)%s+folder%s+with%s+(.+)%s+inside")
  end
  local nested_folder_prompt =
    lt:find("%f[%w]nested%f[%W]") ~= nil
    or lt:find("folder%s+containing%s+.-folder%s+with") ~= nil
    or lt:find("folder%s+should%s+contain%s+.-folder", 1) ~= nil
    or (select(2, lt:gsub("folder%s+should%s+contain", ""))
      and select(2, lt:gsub("folder%s+should%s+contain", "")) > 1)
  if not child_text or not parent_text then
    parent_text, child_text = lt:match(
      "inside%s+(.+)%s+folder%s+named%s+([^%.%?]+)")
  end
  if not child_text or not parent_text then
    parent_text, child_text = lt:match(
      "inside%s+(.+)%s+named%s+([^%.%?]+)")
  end
  if child_text then add_children_from_text(child_text) end
  if nested_folder_prompt and not exact_child_only_prompt then return nil end
  local parent_from_user_text = parent_text ~= nil and parent_text ~= ""

  local ref_to_name = {}
  local ref_to_display = {}
  local name_to_ref = {}
  local name_to_display = {}
  local string_vars = {}
  local string_var_display = {}
  local function remember_ref_name(ref, display_name)
    if not ref or not display_name then return end
    local normalized_name = norm(display_name)
    if normalized_name == "" then return end
    ref_to_name[ref] = normalized_name
    ref_to_display[ref] = clean_display(display_name)
    name_to_ref[normalized_name] = ref
    name_to_display[normalized_name] = clean_display(display_name)
  end
  for var, value in lua_code:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*[\"']([^\"']+)[\"']") do
    string_vars[var] = norm(value)
    string_var_display[var] = clean_display(value)
  end

  local table_vars = {}
  local table_var_displays = {}
  for var, body in lua_code:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*{%s*(.-)%s*}") do
    local names = {}
    local displays = {}
    for name in body:gmatch("[\"']([^\"']+)[\"']") do
      names[#names + 1] = norm(name)
      displays[#displays + 1] = clean_display(name)
    end
    if #names > 0 then
      table_vars[var] = names
      table_var_displays[var] = displays
    end
  end

  local parent_text_display = parent_text
  if not parent_text then
    local parent_var = nil
    if string_vars.folder_name then
      parent_var = "folder_name"
    elseif string_vars.parent_name then
      parent_var = "parent_name"
    end
    if not parent_var then
      for var in pairs(string_vars) do
        local lv = tostring(var or ""):lower()
        if lv:match("^folder") or lv:match("^parent") then
          parent_var = var
          break
        end
      end
    end
    if not parent_var then
      for var in pairs(string_vars) do
        local lv = tostring(var or ""):lower()
        if lv:find("folder", 1, true) or lv:find("parent", 1, true) then
          parent_var = var
          break
        end
      end
    end
    if parent_var then
      parent_text = string_vars[parent_var]
      parent_text_display = string_var_display[parent_var]
    end
  end

  for ref, name in lua_code:gmatch(
      "reaper%.GetSetMediaTrackInfo_String%s*%(%s*([%w_%.%[%]]+)%s*,%s*[\"']P_NAME[\"']%s*,%s*[\"']([^\"']+)[\"']") do
    remember_ref_name(ref, name)
  end

  for names_var, indexed_names in pairs(table_vars) do
    if #indexed_names > 0 then
      local active_loop = nil
      for line in lua_code:gmatch("[^\r\n]+") do
        local loop_var, first, last = line:match(
          "^%s*for%s+([%a_][%w_]*)%s*=%s*(%d+)%s*,%s*(%d+)%s*do%s*$")
        if loop_var then
          active_loop = {
            var = loop_var,
            first = tonumber(first),
            last = tonumber(last),
          }
        end
        if active_loop and active_loop.first and active_loop.last then
          local track_table, track_idx_var, name_idx_var = line:match(
            "reaper%.GetSetMediaTrackInfo_String%s*%(%s*([%a_][%w_]*)%[%s*([%a_][%w_]*)%s*%]%s*,%s*[\"']P_NAME[\"']%s*,%s*"
              .. names_var .. "%[%s*([%a_][%w_]*)%s*%+%s*1%s*%]")
          if track_table
              and track_idx_var == active_loop.var
              and name_idx_var == active_loop.var then
            local step = active_loop.first <= active_loop.last and 1 or -1
            local i = active_loop.first
            while true do
              local name = indexed_names[i - active_loop.first + 1]
              if name then
                local ref = track_table .. "[" .. tostring(i) .. "]"
                ref_to_name[ref] = name
                ref_to_display[ref] =
                  table_var_displays[names_var][i - active_loop.first + 1]
                  or name
                name_to_ref[name] = ref
                name_to_display[name] = ref_to_display[ref]
              end
              if i == active_loop.last then break end
              i = i + step
            end
          end
        end
        if active_loop and line:match("^%s*end%s*$") then
          active_loop = nil
        end
      end
    end
  end

  local loop_child_groups = {}
  local active_ipairs = nil
  for line in lua_code:gmatch("[^\r\n]+") do
    local _, value_var, names_var = line:match(
      "^%s*for%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%s*%(%s*([%a_][%w_]*)%s*%)%s*do%s*$")
    if value_var and names_var and table_vars[names_var] then
      active_ipairs = {
        value_var = value_var,
        names = table_vars[names_var],
        displays = table_var_displays[names_var] or table_vars[names_var],
      }
    end
    if active_ipairs then
      local ref, value = line:match(
        "reaper%.GetSetMediaTrackInfo_String%s*%(%s*([%a_][%w_]*)%s*,%s*[\"']P_NAME[\"']%s*,%s*([%a_][%w_]*)")
      if ref and value == active_ipairs.value_var then
        loop_child_groups[#loop_child_groups + 1] = {
          ref = ref,
          names = active_ipairs.names,
          displays = active_ipairs.displays,
        }
        for i, child in ipairs(active_ipairs.names) do
          add_child(child, active_ipairs.displays[i])
        end
      end
    end
    if active_ipairs and line:match("^%s*end%s*$") then
      active_ipairs = nil
    end
  end

  if #children == 0 then return nil end
  local last_child = children[#children]
  local has_quoted_depth_ref =
    lua_code:find("I_FOLDERDEPTH", 1, true)
    and lua_code:find("%[%s*[\"'][^\"']+[\"']%s*%]") ~= nil
  if not next(ref_to_name)
      and #loop_child_groups == 0
      and not has_quoted_depth_ref then
    return nil
  end

  local negative_by_name = {}
  local positive_by_ref = {}
  local zero_by_ref = {}
  local final_depth_by_ref = {}
  local any_negative_depth = false
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local ref, depth = line:match(
      "reaper%.SetMediaTrackInfo_Value%s*%(%s*(.-)%s*,%s*[\"']I_FOLDERDEPTH[\"']%s*,%s*(-?%d+)")
    depth = tonumber(depth)
    if ref and not ref_to_name[ref] then
      local quoted_key = ref:match("%[%s*[\"']([^\"']+)[\"']%s*%]")
      if quoted_key then remember_ref_name(ref, quoted_key) end
    end
    if ref and depth then
      final_depth_by_ref[ref] = {
        line = line_no,
        depth = depth,
        ref = ref,
      }
    end
  end
  for ref, info in pairs(final_depth_by_ref) do
    local depth = info.depth
    if depth < 0 then
      any_negative_depth = true
      local name = ref_to_name[ref]
      if name then
        negative_by_name[name] = {
          line = info.line,
          depth = depth,
          ref = ref,
          display = ref_to_display[ref] or name,
        }
      end
    elseif depth > 0 then
      positive_by_ref[ref] = { line = info.line, depth = depth, ref = ref }
    elseif depth == 0 then
      zero_by_ref[ref] = { line = info.line, depth = depth, ref = ref }
    end
  end
  local last_child_close = negative_by_name[last_child]
  local violations = {}

  local function name_from_tables(name)
    for var, names in pairs(table_vars) do
      for i, candidate in ipairs(names) do
        if candidate == name then
          local displays = table_var_displays[var]
          return displays and displays[i] or candidate
        end
      end
    end
    return nil
  end

  local function created_name_display(name)
    return name_to_display[name] or name_from_tables(name)
  end

  local parent_name = norm(parent_text)
  local parent_is_created = parent_name ~= ""
    and created_name_display(parent_name) ~= nil
  local first_open = nil
  for _, info in pairs(positive_by_ref) do
    if not first_open or (info.line or 0) < (first_open.line or 0) then
      first_open = info
    end
  end
  if parent_name ~= "" and not parent_is_created and first_open then
    local matched_children = 0
    local first_child_display = nil
    for _, child in ipairs(children) do
      local display = created_name_display(child)
      if display then
        matched_children = matched_children + 1
        first_child_display = first_child_display or display
      end
    end
    if parent_from_user_text and matched_children >= math.min(#children, 2) then
      violations[#violations + 1] = {
        line = first_open.line,
        name = ref_to_name[first_open.ref] or first_open.ref,
        name_display = ref_to_display[first_open.ref]
          or first_child_display
          or first_open.ref,
        ref = first_open.ref,
        expected_name = parent_name,
        expected_name_display = parent_name,
        expected_ref = nil,
        parent = parent_name,
        parent_display = parent_name,
        reason = "missing_parent_folder_track",
      }
    end
  end

  for name, info in pairs(negative_by_name) do
    if not child_set[name]
        and not (nested_folder_prompt
          and exact_child_only_prompt
          and last_child_close) then
      violations[#violations + 1] = {
        line = info.line,
        name = name,
        name_display = info.display,
        ref = info.ref,
        expected_name = last_child,
        expected_name_display = name_to_display[last_child]
          or child_display[last_child],
        expected_ref = name_to_ref[last_child],
        parent = norm(parent_text),
        parent_display = clean_display(parent_text_display or parent_text),
        reason = "outside_track_closes_folder",
      }
    end
  end
  if #violations == 0 and not last_child_close then
    local parent_open = nil
    for ref, info in pairs(positive_by_ref) do
      local name = ref_to_name[ref]
      if parent_text and name == norm(parent_text) then
        parent_open = info
        break
      end
      if not parent_open
          and (name or tostring(ref):lower():find("parent", 1, true)
            or tostring(ref):lower():find("folder", 1, true)) then
        parent_open = info
      end
    end
    local expected_ref = name_to_ref[last_child]
    if parent_open and expected_ref and zero_by_ref[expected_ref] then
      violations[#violations + 1] = {
        line = zero_by_ref[expected_ref].line,
        name = ref_to_name[parent_open.ref] or norm(parent_text)
          or parent_open.ref,
        name_display = ref_to_display[parent_open.ref]
          or clean_display(parent_text_display or parent_text)
          or parent_open.ref,
        ref = parent_open.ref,
        expected_name = last_child,
        expected_name_display = name_to_display[last_child]
          or child_display[last_child],
        expected_ref = expected_ref,
        parent = norm(parent_text),
        parent_display = clean_display(parent_text_display or parent_text),
        reason = "last_child_not_closed",
      }
    elseif parent_open and parent_text and not any_negative_depth then
      for _, group in ipairs(loop_child_groups) do
        if zero_by_ref[group.ref] and #group.names > 0 then
          violations[#violations + 1] = {
            line = zero_by_ref[group.ref].line,
            name = ref_to_name[parent_open.ref] or norm(parent_text)
              or parent_open.ref,
            name_display = ref_to_display[parent_open.ref]
              or clean_display(parent_text_display or parent_text)
              or parent_open.ref,
            ref = parent_open.ref,
            expected_name = group.names[#group.names],
            expected_name_display =
              (group.displays and group.displays[#group.names])
              or child_display[group.names[#group.names]],
            expected_ref = nil,
            parent = norm(parent_text),
            parent_display = clean_display(parent_text_display or parent_text),
            reason = "last_child_not_closed",
          }
          break
        end
      end
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.repair_folder_child_boundary_misuse(lua_code, user_text)
  local findings = Code.find_folder_child_boundary_misuse(lua_code, user_text)
  if not findings or #findings == 0 then return lua_code, false, nil end
  local f = findings[1]
  if f.reason ~= "outside_track_closes_folder" then
    return lua_code, false, findings
  end
  if not f.ref or not f.expected_ref then return lua_code, false, findings end
  local function patt(s)
    return tostring(s or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  end
  local call_pat = "reaper%.SetMediaTrackInfo_Value%s*%(%s*"
    .. patt(f.ref)
    .. "%s*,%s*[\"']I_FOLDERDEPTH[\"']%s*,%s*-?%d+%s*%)"
  local replacement = "reaper.SetMediaTrackInfo_Value("
    .. tostring(f.expected_ref) .. ", \"I_FOLDERDEPTH\", -1)\n"
    .. "reaper.SetMediaTrackInfo_Value("
    .. tostring(f.ref) .. ", \"I_FOLDERDEPTH\", 0)"
  local repaired, n = lua_code:gsub(call_pat, function()
    return replacement
  end, 1)
  if n == 0 then return lua_code, false, findings end
  return repaired, true, findings
end

-- =============================================================================
-- Code.find_nil_prone_settrackselected_args
-- =============================================================================
-- SetTrackSelected requires a real boolean. Lower-tier models sometimes pass an
-- and/or expression that can evaluate to nil, which crashes at runtime.
function Code.find_boolean_setmediatrackinfo_value_args(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local violations = {}
  local line_no = 0
  for line in lua_code:gmatch("[^\r\n]+") do
    line_no = line_no + 1
    local code_line = line:gsub("%-%-.*$", "")
    local parm, bool = code_line:match(
      "reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']([%w_]+)[\"']%s*,%s*(true)%s*%)")
    if not parm then
      parm, bool = code_line:match(
        "reaper%.SetMediaTrackInfo_Value%s*%([^%)]-[\"']([%w_]+)[\"']%s*,%s*(false)%s*%)")
    end
    if parm and bool then
      violations[#violations + 1] = {
        line = line_no,
        parm = parm,
        bool = bool,
        source = line:match("^%s*(.-)%s*$"),
      }
    end
  end
  if #violations == 0 then return nil end
  return violations
end

function Code.find_nil_prone_settrackselected_args(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")

  local function trim(v)
    return Code._lua_trim_expr(v)
  end

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local assignments = {}
  for line in stripped:gmatch("[^\r\n]+") do
    local var, expr = line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not var then
      var, expr = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if var and expr and expr:sub(1, 1) ~= "=" then
      assignments[var] = trim(expr)
    end
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function may_return_nil_boolean(expr)
    expr = trim(expr)
    if expr == "" or expr == "true" or expr == "false" then return false end
    if expr:find("%f[%w_]and%s+true%s+or%s+false%f[^%w_]")
       or expr:find("%f[%w_]and%s+false%s+or%s+true%f[^%w_]")
       or expr:find("%f[%w_]or%s+false%s*$")
       or expr:find("%f[%w_]or%s+true%s*$") then
      return false
    end
    return expr:find("%f[%w_]and%f[^%w_]") ~= nil
  end

  local findings = {}
  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.SetTrackSelected%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    local arg = args and args[2] or nil
    local expr = nil
    if arg and may_return_nil_boolean(arg) then
      expr = arg
    else
      local var = arg and arg:match("^([%a_][%w_]*)$") or nil
      if var and assignments[var] and may_return_nil_boolean(assignments[var]) then
        expr = assignments[var]
      end
    end
    if expr then
      findings[#findings + 1] = {
        line = line_for_pos(s),
        arg = arg,
        expr = expr,
      }
    end
    pos = open_pos + 1
  end

  if #findings == 0 then return nil end
  return findings
end

-- =============================================================================
-- Code.find_stock_fx_substitutions
-- =============================================================================
-- If the user explicitly names a stock Cockos plugin, do not let the generated
-- script silently substitute a third-party or JSFX alternative from the same
-- plugin family. This is intentionally narrow and only checks Track/Take
-- FX_AddByName string literals: explicit exact plugin requests are user intent,
-- not preference-hint suggestions.
--
-- Keep family-intent vocabulary in one matcher. The stock-substitution and
-- action-relevance validators previously maintained separate lists with
-- different matching rules, so ordinary intent such as "bleed", "glue", or
-- "hall" could authorize a plugin in one validator and be rejected by the
-- other. Patterns here intentionally preserve the broader prefix/frontier
-- matching already used by the stock-FX validator.
Code.PLUGIN_FAMILY_INTENT_PATTERNS = {
  eq = {
    "%f[%w]eq%f[%W]", "equaliz", "equalis", "%f[%w]filter%f[%W]",
    "%f[%w]muddy%f[%W]", "%f[%w]harsh%f[%W]", "%f[%w]bright%f[%W]",
    "%f[%w]dark%f[%W]", "%f[%w]tone%f[%W]", "%f[%w]tonal%f[%W]",
  },
  compressor = {
    "compress", "%f[%w]dynamics%f[%W]", "%f[%w]threshold%f[%W]",
    "%f[%w]ratio%f[%W]", "%f[%w]glue%f[%W]", "%f[%w]leveler%f[%W]",
  },
  delay = {
    "%f[%w]delay%f[%W]", "%f[%w]echo%f[%W]", "%f[%w]slap%f[%W]",
    "%f[%w]slapback%f[%W]",
  },
  reverb = {
    "%f[%w]reverb%f[%W]", "%f[%w]verb%f[%W]", "%f[%w]room%f[%W]",
    "%f[%w]hall%f[%W]", "%f[%w]plate%f[%W]",
  },
  gate = {
    "%f[%w]gate%f[%W]", "%f[%w]gating%f[%W]",
    "%f[%w]expander%f[%W]", "%f[%w]bleed%f[%W]",
  },
  limiter = {
    "%f[%w]limit%f[%W]", "%f[%w]limiter%f[%W]",
    "%f[%w]limiting%f[%W]", "%f[%w]ceiling%f[%W]",
    "%f[%w]loudness%f[%W]",
  },
  instrument = {
    "%f[%w]instrument%f[%W]", "%f[%w]vsti%f[%W]",
    "%f[%w]synth%f[%W]", "%f[%w]sampler%f[%W]",
    "%f[%w]kontakt%f[%W]",
  },
}

function Code.prompt_expresses_plugin_family_intent(user_prompt, family)
  local prompt = tostring(user_prompt or ""):lower()
  local patterns = Code.PLUGIN_FAMILY_INTENT_PATTERNS[
    tostring(family or ""):lower()]
  if prompt == "" or not patterns then return false end
  for _, pattern in ipairs(patterns) do
    if prompt:find(pattern) then return true end
  end
  return false
end

function Code.find_stock_fx_substitutions(lua_code, user_prompt)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_prompt or ""):lower()
  if prompt == "" then return nil end

  local specs = {
    {
      requested = "ReaEQ",
      prompt_token = "reaeq",
      family = "eq",
      substitutes = {
        { pattern = "pro%-q", label = "FabFilter Pro-Q" },
        { pattern = "reeq",  label = "ReEQ" },
      },
    },
    {
      requested = "ReaComp",
      prompt_token = "reacomp",
      family = "compressor",
      substitutes = {
        { pattern = "pro%-c", label = "FabFilter Pro-C" },
      },
    },
    {
      requested = "ReaDelay",
      prompt_token = "readelay",
      family = "delay",
      substitutes = {
        { pattern = "timeless", label = "FabFilter Timeless" },
      },
    },
    {
      requested = "ReaVerbate",
      prompt_token = "reaverbate",
      family = "reverb",
      substitutes = {
        { pattern = "pro%-r", label = "FabFilter Pro-R" },
      },
    },
    {
      requested = "ReaGate",
      prompt_token = "reagate",
      family = "gate",
      substitutes = {
        { pattern = "pro%-g", label = "FabFilter Pro-G" },
      },
    },
    {
      requested = "ReaLimit",
      prompt_token = "realimit",
      family = "limiter",
      substitutes = {
        { pattern = "pro%-l", label = "FabFilter Pro-L" },
      },
    },
  }

  local requested, requested_order = {}, {}
  for _, spec in ipairs(specs) do
    if prompt:find(spec.prompt_token, 1, true) then
      requested[spec.requested] = true
      requested_order[#requested_order + 1] = spec.requested
    end
  end
  if next(requested) == nil then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function string_literal_value(v)
    v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
    local q = v:sub(1, 1)
    if q ~= '"' and q ~= "'" then return nil end
    local out = {}
    local i = 2
    while i <= #v do
      local c = v:sub(i, i)
      if c == "\\" then
        i = i + 1
        if i <= #v then out[#out + 1] = v:sub(i, i) end
      elseif c == q then
        return table.concat(out)
      else
        out[#out + 1] = c
      end
      i = i + 1
    end
    return nil
  end

  -- Best effort only: catch simple `local id = "Plugin"` aliases so explicit
  -- stock-plugin substitutions cannot hide behind a one-hop variable.
  local string_vars = {}
  for name, expr in stripped:gmatch("local%s+([%a_][%w_]*)%s*=%s*([\"'][^\n]-[\"'])") do
    local value = string_literal_value(expr)
    if value and value ~= "" then string_vars[name] = value end
  end

  local calls = {}
  for _, fn in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
    local pos = 1
    while true do
      local s, open_pos = stripped:find("reaper%." .. fn .. "%s*%(", pos)
      if not s then break end
      local args = parse_args(open_pos)
      local plugin = args and string_literal_value(args[2])
      if (not plugin or plugin == "") and args then
        local var_name = tostring(args[2] or ""):match("^%s*([%a_][%w_]*)%s*$")
        if var_name then plugin = string_vars[var_name] end
      end
      if plugin and plugin ~= "" then
        calls[#calls + 1] = {
          fn = fn,
          plugin = plugin,
          plugin_lower = plugin:lower(),
          line = line_for_pos(s),
        }
      end
      pos = open_pos + 1
    end
  end
  if #calls == 0 then return nil end

  local violations, seen = {}, {}
  local function prompt_allows_generic_stock(spec)
    if prompt:find(spec.prompt_token, 1, true) then return true end
    return Code.prompt_expresses_plugin_family_intent(prompt, spec.family)
  end

  local requested_anchor = requested_order[1] or "requested stock FX"
  for _, spec in ipairs(specs) do
    if requested[spec.requested] then
      for _, call in ipairs(calls) do
        for _, sub in ipairs(spec.substitutes) do
          if call.plugin_lower:find(sub.pattern)
             and not prompt:find(sub.pattern) then
            local key = spec.requested .. ":" .. call.plugin_lower .. ":"
              .. tostring(call.line)
            if not seen[key] then
              seen[key] = true
              violations[#violations + 1] = {
                requested = spec.requested,
                substitute = call.plugin,
                substitute_label = sub.label,
                fn = call.fn,
                line = call.line,
              }
            end
          end
        end
      end
    end
  end

  for _, call in ipairs(calls) do
    for _, spec in ipairs(specs) do
      if call.plugin_lower:find(spec.prompt_token, 1, true)
          and not requested[spec.requested]
          and not prompt_allows_generic_stock(spec) then
        local key = "unrequested:" .. spec.requested .. ":"
          .. call.plugin_lower .. ":" .. tostring(call.line)
        if not seen[key] then
          seen[key] = true
          violations[#violations + 1] = {
            requested = requested_anchor,
            substitute = call.plugin,
            substitute_label = "unrequested " .. spec.requested,
            fn = call.fn,
            line = call.line,
          }
        end
      end
    end
  end

  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    if a.requested ~= b.requested then return a.requested < b.requested end
    return tostring(a.substitute) < tostring(b.substitute)
  end)
  return violations
end

-- =============================================================================
-- Code.find_timecode_generator_fx_misuse
-- =============================================================================
-- SMPTE/LTC/MTC generation is a native REAPER action/item workflow, not a
-- plugin family. Catch scripts that try to satisfy generator requests by
-- loading timecode-looking FX names, while leaving legitimate reader/meter
-- prompts alone.
function Code.find_timecode_generator_fx_misuse(lua_code, user_prompt)
  if not lua_code or lua_code == "" then return nil end
  if not (CTX and CTX.prompt_indicates_timecode_generator
      and CTX.prompt_indicates_timecode_generator(user_prompt)) then
    return nil
  end
  local stripped = lua_code:gsub("%-%-%[%[.-%]%]", "")
  stripped = stripped:gsub("%-%-[^\n]*", "")

  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function string_literal_value(v)
    v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
    local q = v:sub(1, 1)
    if q ~= '"' and q ~= "'" then return nil end
    local out = {}
    local i = 2
    while i <= #v do
      local c = v:sub(i, i)
      if c == "\\" then
        i = i + 1
        if i <= #v then out[#out + 1] = v:sub(i, i) end
      elseif c == q then
        return table.concat(out)
      else
        out[#out + 1] = c
      end
      i = i + 1
    end
    return nil
  end

  local string_vars = {}
  for name, expr in stripped:gmatch("local%s+([%a_][%w_]*)%s*=%s*([\"'][^\n]-[\"'])") do
    local value = string_literal_value(expr)
    if value and value ~= "" then string_vars[name] = value end
  end

  local function plugin_looks_like_timecode_fx(plugin)
    local p = tostring(plugin or ""):lower()
    if p:find("%f[%w]smpte%f[%W]") then return true end
    if p:find("%f[%w]ltc%f[%W]") then return true end
    if p:find("%f[%w]mtc%f[%W]") then return true end
    if p:find("timecode", 1, true) then return true end
    if p:find("time code", 1, true) then return true end
    if p:find("ltc%-generator") then return true end
    if p:find("reader/generator", 1, true) then return true end
    return false
  end

  local findings, seen = {}, {}
  for _, fn in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
    local pos = 1
    while true do
      local s, open_pos = stripped:find("reaper%." .. fn .. "%s*%(", pos)
      if not s then break end
      local args = parse_args(open_pos)
      local plugin = args and string_literal_value(args[2])
      if (not plugin or plugin == "") and args then
        local var_name = tostring(args[2] or ""):match("^%s*([%a_][%w_]*)%s*$")
        if var_name then plugin = string_vars[var_name] end
      end
      if plugin and plugin_looks_like_timecode_fx(plugin) then
        local line = line_for_pos(s)
        local key = fn .. ":" .. plugin:lower() .. ":" .. tostring(line)
        if not seen[key] then
          seen[key] = true
          findings[#findings + 1] = {
            line = line,
            fn = fn,
            plugin = plugin,
            reason = "timecode_generator_as_fx",
          }
        end
      end
      pos = open_pos + 1
    end
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    if a.fn ~= b.fn then return a.fn < b.fn end
    return tostring(a.plugin) < tostring(b.plugin)
  end)
  return findings
end

-- =============================================================================
-- Code.find_preferred_fx_identifier_drift
-- =============================================================================
-- Preferred-plugin context gives the model exact AddByName identifiers such as
-- "VST3: Pro-G". After hidden repair retries, weaker models sometimes strip the
-- prefix/vendor and fall back to bare names like "Pro-G", which can fail on
-- installs where REAPER requires the exact identifier. Catch those before
-- auto-run and ask for a focused identifier-only repair.
function Code.find_preferred_fx_identifier_drift(lua_code)
  if not lua_code or lua_code == "" then return nil end
  if not FXCache or not FXCache.get_preferred_types then return nil end

  local prefs_map = FXCache.get_preferred_types() or {}
  local preferred = {}
  local function strip_prefix(s)
    return tostring(s or ""):gsub("^[A-Za-z][A-Za-z0-9]*:%s*", "")
  end
  local function strip_vendor(s)
    return tostring(s or ""):gsub("%s+%b()", "")
  end
  local function has_prefix(s)
    return tostring(s or ""):find("^[A-Za-z][A-Za-z0-9]*:%s*") ~= nil
  end
  local function identifier_loose_match(a, b)
    a = tostring(a or ""):lower()
    b = tostring(b or ""):lower()
    if a == "" or b == "" then return false end
    if a == b then return true end
    if #a < 4 or #b < 4 then return false end
    local pa = "%f[%w_]" .. a:gsub("(%W)", "%%%1") .. "%f[^%w_]"
    local pb = "%f[%w_]" .. b:gsub("(%W)", "%%%1") .. "%f[^%w_]"
    return b:find(pa) ~= nil or a:find(pb) ~= nil
  end
  for type_key, ident in pairs(prefs_map) do
    ident = tostring(ident or "")
    if ident ~= "" and FXCache.canonicalize_identifier then
      ident = FXCache.canonicalize_identifier(type_key, ident)
    end
    if ident ~= "" and has_prefix(ident) then
      local bare = strip_vendor(strip_prefix(ident)):lower()
      if bare ~= "" then
        preferred[#preferred + 1] = {
          type_key = tostring(type_key or ""),
          exact = ident,
          bare = bare,
        }
      end
    end
  end
  if #preferred == 0 then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end

  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end

  local function string_literal_value(v)
    v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
    local q = v:sub(1, 1)
    if q ~= '"' and q ~= "'" then return nil end
    local out = {}
    local i = 2
    while i <= #v do
      local c = v:sub(i, i)
      if c == "\\" then
        i = i + 1
        if i <= #v then out[#out + 1] = v:sub(i, i) end
      elseif c == q then
        return table.concat(out)
      else
        out[#out + 1] = c
      end
      i = i + 1
    end
    return nil
  end

  local violations, seen = {}, {}
  for _, fn in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
    local pos = 1
    while true do
      local s, open_pos = stripped:find("reaper%." .. fn .. "%s*%(", pos)
      if not s then break end
      local args = parse_args(open_pos)
      local plugin = args and string_literal_value(args[2])
      if plugin and plugin ~= "" and not has_prefix(plugin) then
        local normalized = strip_vendor(plugin):lower()
        for _, pref in ipairs(preferred) do
          if identifier_loose_match(normalized, pref.bare) then
            local key = fn .. ":" .. normalized .. ":" .. pref.exact .. ":"
              .. tostring(line_for_pos(s))
            if not seen[key] then
              seen[key] = true
              violations[#violations + 1] = {
                fn = fn,
                plugin = plugin,
                exact = pref.exact,
                type_key = pref.type_key,
                line = line_for_pos(s),
              }
            end
          end
        end
      end
      pos = open_pos + 1
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.plugin) < tostring(b.plugin)
  end)
  return violations
end

-- =============================================================================
-- Code.find_installed_fx_identifier_drift
-- =============================================================================
-- Memoized derived installed-FX index (built once per installed-FX snapshot,
-- reused across every generated-code candidate in the same response). Building
-- installed_entries pcalls FXCache.canonicalize_identifier once per installed
-- plugin, so a multi-thousand-plugin install must not pay that pass on each
-- candidate. populate_installed_fx rebuilds its source tables wholesale on
-- repopulation, so table identity is a correct invalidation signal: a fresh
-- CTX._installed_fx_entries (or the fallback list when raw entries are absent)
-- misses the memo and rebuilds; the same table hits it.
local _installed_fx_index_memo_key = nil
local _installed_fx_index_memo = nil
--
-- Models sometimes preserve the requested plugin words but invent punctuation
-- inside an otherwise prefix-shaped AddByName identifier, for example:
--
--   local fx_ident = "JS: Tukan/Tape_Recorder_S_2"
--   reaper.TrackFX_AddByName(track, fx_ident, false, -1)
--
-- That is relevant to the user's request, but it is not an installed REAPER
-- identifier. Before Auto-Run, resolve only a unique punctuation-insensitive
-- match from EnumInstalledFX and ask the model to copy that exact identifier.
-- Zero or multiple matches are left alone rather than guessed. A first-pass
-- punctuation-sensitive comparison (with trailing vendor metadata removed)
-- preserves already-loadable forms such as `VST3: Pro-Q 4` when the installed
-- display entry is `VST3: Pro-Q 4 (FabFilter)`.
function Code.find_installed_fx_identifier_drift(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  if not stripped:find("FX_AddByName", 1, true) then return nil end
  if not CTX or not CTX.populate_installed_fx then return nil end
  local ok_installed, installed = pcall(CTX.populate_installed_fx)
  if not ok_installed or type(installed) ~= "table" or #installed == 0 then
    return nil
  end

  local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$") or ""
  end
  local function strip_vendor(s)
    return trim(tostring(s or ""):gsub("%s*%b()%s*$", ""))
  end
  local function parts(identifier)
    local prefix, rest = trim(identifier):match(
      "^([A-Za-z][A-Za-z0-9]*):%s*(.+)$")
    if not prefix or not rest then return nil end
    local raw_base = trim(rest):lower():gsub("%s+", " ")
    local base = strip_vendor(rest):lower():gsub("%s+", " ")
    local compact = base:gsub("[^%w]", "")
    return {
      prefix = prefix:lower(),
      raw_base = raw_base,
      raw_compact = raw_base:gsub("[^%w]", ""),
      base = base,
      compact = compact,
    }
  end

  -- Memo key: the raw-entries table identity when present, otherwise the
  -- installed list identity. Both are rebuilt wholesale on repopulation, so a
  -- new identity is a correct miss.
  local raw_entries = CTX._installed_fx_entries
  local memo_key = (type(raw_entries) == "table" and #raw_entries > 0)
    and raw_entries or installed

  local installed_entries
  if _installed_fx_index_memo_key == memo_key and _installed_fx_index_memo then
    installed_entries = _installed_fx_index_memo
  else
    installed_entries = {}
    if type(raw_entries) ~= "table" or #raw_entries == 0 then
      raw_entries = {}
      for _, identifier in ipairs(installed) do
        raw_entries[#raw_entries + 1] = { name = identifier }
      end
    end
    for _, row in ipairs(raw_entries) do
      local identifier = type(row) == "table" and row.name or row
      local p = parts(identifier)
      if p and #p.compact >= 4 then
        local exact = tostring(identifier)
        if FXCache and FXCache.canonicalize_identifier then
          local ok_canonical, canonical = pcall(
            FXCache.canonicalize_identifier, nil, exact)
          if ok_canonical and type(canonical) == "string"
             and canonical ~= "" then exact = canonical end
        end
        installed_entries[#installed_entries + 1] = {
          prefix = p.prefix,
          base = p.base,
          compact = p.compact,
          exact = exact,
          match_kind = "display",
        }
        -- EnumInstalledFX's JS display name is loadable but does not include
        -- the relative Effects/ path. Its raw ident does. Keep that ident
        -- verbatim: parentheses and punctuation are literal JSFX path content,
        -- not vendor metadata. Binary-format idents are filesystem paths and
        -- intentionally remain outside this AddByName repair path.
        local raw_ident = type(row) == "table"
          and tostring(row.ident or "") or ""
        local ident_compact = raw_ident:lower():gsub("[^%w]", "")
        if p.prefix == "js" and raw_ident:match("%S")
           and #ident_compact >= 4 then
          installed_entries[#installed_entries + 1] = {
            prefix = p.prefix,
            compact = ident_compact,
            exact = "JS: " .. raw_ident,
            match_kind = "js_ident",
          }
        end
      end
    end
    _installed_fx_index_memo_key = memo_key
    _installed_fx_index_memo = installed_entries
  end
  if #installed_entries == 0 then return nil end

  local function string_literal_value(v)
    v = trim(v)
    local q = v:sub(1, 1)
    if q ~= '"' and q ~= "'" then return nil end
    local out = {}
    local i = 2
    while i <= #v do
      local c = v:sub(i, i)
      if c == "\\" then
        i = i + 1
        if i <= #v then out[#out + 1] = v:sub(i, i) end
      elseif c == q then
        return table.concat(out)
      else
        out[#out + 1] = c
      end
      i = i + 1
    end
    return nil
  end

  -- One-hop literal aliases cover the common generated-code shape without
  -- treating unrelated message/documentation strings as plugin identifiers.
  local string_vars = {}
  for name, expr in stripped:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*([\"'][^\n]-[\"'])") do
    local value = string_literal_value(expr)
    if value and value ~= "" then string_vars[name] = value end
  end

  local findings, seen = {}, {}
  for _, fn in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
    local pos = 1
    while true do
      local s, open_pos = stripped:find("reaper%." .. fn .. "%s*%(", pos)
      if not s then break end
      local args = Code._parse_lua_call_args(stripped, open_pos)
      local plugin = args and string_literal_value(args[2])
      if (not plugin or plugin == "") and args then
        local var_name = trim(args[2]):match("^([%a_][%w_]*)$")
        if var_name then plugin = string_vars[var_name] end
      end
      local candidate = plugin and parts(plugin) or nil
      if candidate and #candidate.compact >= 4 then
        local already_loadable = false
        local candidate_exact = trim(plugin):lower()
        for _, entry in ipairs(installed_entries) do
          if entry.prefix == candidate.prefix then
            if entry.match_kind == "display"
               and entry.base == candidate.base then
              already_loadable = true
              break
            elseif entry.match_kind == "js_ident"
               and trim(entry.exact):lower() == candidate_exact then
              already_loadable = true
              break
            end
          end
        end
        if not already_loadable then
          local matches = {}
          for _, entry in ipairs(installed_entries) do
            local candidate_compact = entry.match_kind == "js_ident"
              and candidate.raw_compact or candidate.compact
            if entry.prefix == candidate.prefix
               and entry.compact == candidate_compact then
              matches[entry.exact:lower()] = entry.exact
            end
          end
          local exact, match_count = nil, 0
          for _, installed_exact in pairs(matches) do
            exact = installed_exact
            match_count = match_count + 1
          end
          if match_count == 1
             and trim(exact):lower() ~= candidate_exact then
            local line = Code._lua_line_for_pos(stripped, s)
            local key = fn .. ":" .. tostring(plugin):lower() .. ":"
              .. tostring(exact):lower() .. ":" .. tostring(line)
            if not seen[key] then
              seen[key] = true
              findings[#findings + 1] = {
                fn = fn,
                plugin = plugin,
                exact = exact,
                line = line,
                source = "installed_fx",
              }
            end
          end
        end
      end
      pos = open_pos + 1
    end
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    if a.fn ~= b.fn then return a.fn < b.fn end
    return tostring(a.plugin) < tostring(b.plugin)
  end)
  return findings
end

-- =============================================================================
-- Code.find_unchecked_addbyname_results
-- =============================================================================
-- Static check for unchecked TrackFX_AddByName / TakeFX_AddByName results.
-- A common silent-failure pattern from less-careful models:
--
--   local fx = reaper.TrackFX_AddByName(tr, "VST3i: Twin 3", false, -1)
--   -- ... never checks fx < 0; downstream code assumes fx is valid
--
-- or the silent-skip variant:
--
--   local fx_comp = reaper.TrackFX_AddByName(tr, ..., false, -1)
--   if fx_comp >= 0 then
--     ... configure ...
--   end                            -- no else, no error, no return
--
-- Both forms claim the script "ran OK" while in reality a required plugin
-- failed to load and the user gets no diagnostic. The script is dependent
-- on the AddByName succeeding; if it doesn't, that's a broken chain the
-- user should be told about.
-- Also flags `local ok, fx = TrackFX_AddByName(...)`: AddByName returns
-- exactly one integer FX index, not an ok/value pair.
--
-- Detection: for each `NAME = reaper.(Track|Take)FX_AddByName(...)`, check
-- that NAME appears in a failure-direction comparison somewhere in the
-- script. Acceptable patterns: `NAME < 0`, `NAME == -1`, `NAME <= -1`.
-- A success-direction guard is only accepted when its else branch reports or
-- aborts the failure (`error(...)`, `return`, ShowMessageBox, error table).
-- Bare unassigned AddByName calls are also flagged because the script cannot
-- observe or report load failure.
-- GetByName is covered by a separate dependent-use validator below because
-- returning -1 is a legitimate "not present" signal in upsert patterns.
--
-- Returns a sorted list of `{name, line}` entries (line is approximate),
-- or nil if every AddByName result is properly checked.
function Code.find_unchecked_addbyname_results(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local violations, seen = {}, {}
  local lines = {}
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local function _line_for_pos(pos)
    local line = 1
    for _ in stripped:sub(1, pos):gmatch("\n") do line = line + 1 end
    return line
  end
  local function _assignment_info(call_start)
    local line_start = stripped:sub(1, call_start):match(".*()\n")
    line_start = line_start and (line_start + 1) or 1
    local prefix = stripped:sub(line_start, call_start - 1)
    local lhs = prefix:match("^%s*local%s+(.+)%s*=%s*$")
      or prefix:match("^%s*(.-)%s*=%s*$")
    if not lhs then return nil, false, nil end
    local name = lhs:match("([%a_][%w_]*)%s*$")
    return name, lhs:find(",", 1, true) ~= nil, lhs
  end
  local function _var_pat(name)
    return "%f[%w_]" .. tostring(name or "") .. "%f[^%w_]"
  end
  local function _line_has_success_guard(line, name)
    local v = _var_pat(name)
    return line:find("^%s*if%s+")
      and line:find("%f[%w_]then%f[^%w_]")
      and (
        line:find(v .. "%s*>=%s*0")
        or line:find(v .. "%s*>%s*%-%s*1")
        or line:find("0%s*<=%s*" .. v)
        or line:find("%-%s*1%s*<%s*" .. v)
      )
  end
  local function _chunk_reports_failure(chunk)
    return chunk:find("error%s*%(")
        or chunk:find("%f[%w_]return%f[^%w_]")
        or chunk:find("ShowMessageBox", 1, true)
        or chunk:find("errors%s*%[")
        or chunk:find("failed%s*%[")
        or chunk:find("failures%s*%[")
        or chunk:find("missing%s*%[")
  end
  local function _next_assignment_line(assign_line, name)
    for i = assign_line + 1, #lines do
      local line = lines[i] or ""
      local eq = line:find("=", 1, true)
      local prev = eq and line:sub(eq - 1, eq - 1) or ""
      local after = eq and line:sub(eq + 1, eq + 1) or ""
      local assignment = eq and not prev:find("[<>~=]") and after ~= "="
      local prefix = assignment and line:sub(1, eq - 1) or ""
      local lhs = prefix:match("^%s*local%s+(.+)%s*$")
        or prefix:match("^%s*(.-)%s*$")
      local assigned = lhs and lhs:match("([%a_][%w_]*)%s*$") or nil
      if assigned == name then return i end
    end
    return #lines + 1
  end
  local function _success_guard_has_failure_else(assign_line, name, last_line)
    local stop = math.min(#lines, last_line or #lines, assign_line + 40)
    for i = assign_line, stop do
      if _line_has_success_guard(lines[i] or "", name) then
        local depth, else_line, end_line = 0, nil, nil
        for j = i, stop do
          local l = lines[j] or ""
          if l:find("%f[%w_]if%f[^%w_]") and l:find("%f[%w_]then%f[^%w_]") then
            depth = depth + 1
          end
          if depth == 1 and l:match("^%s*else%f[^%w_]") then
            else_line = j
          end
          if l:match("^%s*end%s*[%)%,;]*%s*$") then
            depth = depth - 1
            if depth == 0 then
              end_line = j
              break
            end
          end
        end
        if else_line then
          local chunk = table.concat(lines, "\n", else_line, end_line or math.min(#lines, else_line + 12))
          if _chunk_reports_failure(chunk) then return true end
        end
      end
    end
    return false
  end
  local function _scan(fn)
    local pos = 1
    while true do
      local s, e = stripped:find("reaper%." .. fn .. "%s*%(", pos)
      if not s then break end
      local name, multi_assign, lhs = _assignment_info(s)
      if multi_assign then
        violations[#violations+1] = {
          name = name or "(multiple assignment)",
          line = _line_for_pos(s),
          multi_assign = true,
          lhs = lhs,
        }
      elseif not name then
        violations[#violations+1] = {
          name = "(unassigned result)",
          line = _line_for_pos(s),
          unassigned = true,
        }
      else
        -- Limit each result check to that assignment's lifetime. Reusing the
        -- same variable for a later AddByName call must not inherit an earlier
        -- failure check.
        local line = _line_for_pos(s)
        local next_line = _next_assignment_line(line, name)
        local last_line = math.max(line, next_line - 1)
        local hay = table.concat(lines, "\n", line, last_line) .. "\n"
        local nid = "[^%w_]"
        local end_  = "[^%w_%.]"  -- excludes "." so "< 0.5" doesn't match "< 0"
        local checked =
             hay:find(nid .. name .. "%s*<%s*0"   .. end_)   -- NAME < 0
          or hay:find(nid .. name .. "%s*==%s*%-%s*1" .. end_)  -- NAME == -1
          or hay:find(nid .. name .. "%s*<=%s*%-%s*1" .. end_)  -- NAME <= -1
          or hay:find(nid .. name .. "%s*<%s*%-%s*1"  .. end_)  -- NAME < -1
        if not checked
           and not _success_guard_has_failure_else(line, name, last_line) then
          violations[#violations+1] = { name = name, line = line }
        end
      end
      pos = e + 1
    end
  end
  _scan("TrackFX_AddByName")
  _scan("TakeFX_AddByName")
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.name < b.name
  end)
  return violations
end

function Code.find_trackfx_addbyname_recfx_misuse(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local prompt = tostring(user_text or ""):lower():gsub("[\226\128\153']", "'")
  if prompt:find("%f[%w]input%s+fx%f[%W]")
      or prompt:find("%f[%w]record%s+fx%f[%W]")
      or prompt:find("%f[%w]rec%s+fx%f[%W]")
      or prompt:find("%f[%w]monitor%s+fx%f[%W]")
      or prompt:find("%f[%w]input%s+effect")
      or prompt:find("%f[%w]record%s+effect") then
    return nil
  end

  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.TrackFX_AddByName%s*%(") then return nil end

  local function trim(v)
    return Code._lua_trim_expr(v)
  end
  local function line_for_pos(pos)
    return Code._lua_line_for_pos(stripped, pos)
  end
  local function parse_args(open_pos)
    return Code._parse_lua_call_args(stripped, open_pos)
  end
  local function split_params(src)
    local out = {}
    for part in tostring(src or ""):gmatch("[^,]+") do
      local name = trim(part):match("^([%a_][%w_]*)$")
      if name then out[#out + 1] = name end
    end
    return out
  end
  local function truthy_literal(expr)
    local compact = trim(expr):gsub("%s+", ""):lower()
    return compact == "true"
  end
  local function expr_references_param_as_recfx(expr, param)
    local e = trim(expr)
    if e == param then return true end
    local escaped = param:gsub("([^%w_])", "%%%1")
    return e:find("%f[%w_]" .. escaped .. "%f[^%w_]%s*==%s*true") ~= nil
      or e:find("true%s*==%s*%f[%w_]" .. escaped .. "%f[^%w_]") ~= nil
  end

  local findings, seen = {}, {}
  local function add(kind, pos, detail)
    local key = kind .. ":" .. tostring(pos) .. ":" .. tostring(detail or "")
    if seen[key] then return end
    seen[key] = true
    findings[#findings + 1] = {
      kind = kind,
      line = line_for_pos(pos),
      detail = detail,
    }
  end

  local helper_params = {}
  local search_pos = 1
  while true do
    local s, e, fname, params =
      stripped:find("local%s+function%s+([%a_][%w_]*)%s*%(([^%)]*)%)", search_pos)
    if not s then break end
    local body_end = stripped:find("\n%s*end%f[%W]", e + 1) or #stripped
    local body = stripped:sub(e + 1, body_end)
    local params_list = split_params(params)
    local body_base = e
    local body_pos = 1
    while true do
      local _, call_open = body:find("reaper%.TrackFX_AddByName%s*%(", body_pos)
      if not call_open then break end
      local args = parse_args(body_base + call_open)
      local recfx_expr = args and args[3] or nil
      if recfx_expr then
        for idx, param in ipairs(params_list) do
          if expr_references_param_as_recfx(recfx_expr, param) then
            helper_params[fname] = helper_params[fname] or {}
            helper_params[fname][idx] = param
          end
        end
      end
      body_pos = call_open + 1
    end
    search_pos = e + 1
  end

  local pos = 1
  while true do
    local s, open_pos = stripped:find("reaper%.TrackFX_AddByName%s*%(", pos)
    if not s then break end
    local args = parse_args(open_pos)
    if args and args[3] and truthy_literal(args[3]) then
      add("direct_true", s, args[3])
    end
    pos = open_pos + 1
  end

  for fname, param_map in pairs(helper_params) do
    local call_pos = 1
    while true do
      local s, open_pos = stripped:find("%f[%w_]" .. fname .. "%s*%(", call_pos)
      if not s then break end
      local before = stripped:sub(math.max(1, s - 20), s - 1)
      if not before:find("function%s+$") then
        local args = parse_args(open_pos)
        if args then
          for idx, param in pairs(param_map) do
            if args[idx] and truthy_literal(args[idx]) then
              add("helper_true", s, fname .. "." .. param)
            end
          end
        end
      end
      call_pos = open_pos + 1
    end
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.kind) < tostring(b.kind)
  end)
  return findings
end

-- =============================================================================
-- Code.find_proq4_bell_slope_violations
-- =============================================================================
-- Pro-Q 4's GUI-created Bell bands default to 12 dB/oct slope. Generated
-- scripts that create/configure a fresh Bell boost/cut through raw parameter
-- writes can leave the slope at the host/plugin state instead, observed as
-- 48 dB/oct on DeepSeek output. Catch the high-confidence literal-index case:
-- Pro-Q 4 is being added, a Bell band has Gain + Shape writes, but that same
-- band does not set Slope via the fingerprint-validated current Pro-Q 4
-- direct-normalized 12 dB/oct value. The display-helper form remains accepted
-- for generic/live-discovery scripts, but the validated profile should prefer
-- the compact direct mapping so weaker models do not need to paste a long
-- probe helper.
function Code.profile_resolver_spec_bindings(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local bindings = {}
  local search_pos = 1
  while true do
    local call_start, call_open = stripped:find(
      "%f[%w_]reaassist_resolve_profile_params%s*%(", search_pos)
    if not call_start then break end
    local before = stripped:sub(1, call_start - 1)
    local line_start = (before:match(".*()\n") or 0) + 1
    local assignment = stripped:sub(line_start, call_start - 1)
    local mapped_var, error_var = assignment:match(
      "^%s*local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*$")
    if not mapped_var then
      mapped_var, error_var = assignment:match(
        "^%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*$")
    end
    if not mapped_var then
      mapped_var = assignment:match(
        "^%s*local%s+([%a_][%w_]*)%s*=%s*$")
        or assignment:match("^%s*([%a_][%w_]*)%s*=%s*$")
    end

    local args, call_close = Code._parse_lua_call_args(stripped, call_open)
    local binding = {
      mapped_var = mapped_var,
      error_var = error_var,
      call_start = call_start,
      call_close = call_close,
      track_expr = args and Code._lua_trim_expr(args[1]) or nil,
      fx_expr = args and Code._lua_trim_expr(args[2]) or nil,
      specs = {},
    }
    local specs_src = args and args[3] or nil
    if mapped_var and specs_src then
      local depth, entry_start = 0, nil
      for i = 1, #specs_src do
        local char = specs_src:sub(i, i)
        if char == "{" then
          depth = depth + 1
          if depth == 2 then entry_start = i end
        elseif char == "}" then
          if depth == 2 and entry_start then
            local entry = specs_src:sub(entry_start, i)
            binding.specs[#binding.specs + 1] = {
              index = tonumber(entry:match(
                "%f[%w_]index%s*=%s*([%+%-]?%d+)")),
            }
            entry_start = nil
          end
          depth = depth - 1
        end
      end
    end
    bindings[#bindings + 1] = binding
    search_pos = (call_close or call_open) + 1
  end
  if #bindings == 0 then return nil end
  return bindings
end

function Code.find_proq4_bell_slope_violations(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local lower = stripped:lower()
  if not (lower:find("trackfx_addbyname", 1, true)
          and lower:find("pro%-q%s*4")) then
    return nil
  end

  local lines = {}
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end

  local function split_args(src)
    return Code._split_lua_args(src)
  end

  local function call_args(line, name)
    local s, e = line:find(name .. "%s*%(")
    if not s then return nil end
    local rest = line:sub(e + 1)
    local close = rest:match("^(.*)%)%s*$")
    if not close then close = rest:match("^(.*)%)") end
    return split_args(close or rest)
  end

  local function literal_number(expr)
    expr = tostring(expr or ""):match("^%s*(.-)%s*$") or ""
    return tonumber(expr)
  end

  local function trim_expr(expr)
    return tostring(expr or ""):match("^%s*(.-)%s*$") or ""
  end

  local function base_for_idx(idx, offset)
    idx = tonumber(idx)
    if not idx then return nil end
    local base = idx - offset
    if base < 0 or (base % 23) ~= 0 then return nil end
    return base
  end

  local function band_for_base(base)
    return math.floor(base / 23) + 1
  end

  local function is_slope_norm_12(value)
    value = tonumber(value)
    return value and math.abs(value - 0.2) <= 0.0005
  end

  local bands = {}
  local function ensure_band(base)
    bands[base] = bands[base] or {
      base = base,
      band = band_for_base(base),
      slope_idx = base + 6,
    }
    return bands[base]
  end

  local proq_fx_exprs = {}
  for _, line in ipairs(lines) do
    local args = call_args(line, "reaper%.TrackFX_AddByName")
    if args and args[2]
       and tostring(args[2]):lower():find("pro%-q%s*4") then
      local lhs = line:match(
        "^%s*local%s+([%a_][%w_]*)%s*=%s*reaper%.TrackFX_AddByName%s*%(")
        or line:match(
          "^%s*([%a_][%w_]*)%s*=%s*reaper%.TrackFX_AddByName%s*%(")
      if lhs then proq_fx_exprs[lhs] = true end
    end
  end

  if not next(proq_fx_exprs) then return nil end

  local function is_proq_fx_expr(expr)
    return proq_fx_exprs[trim_expr(expr)] == true
  end

  local resolved_indices = {}
  for _, binding in ipairs(
      Code.profile_resolver_spec_bindings(lua_code) or {}) do
    if binding.mapped_var and is_proq_fx_expr(binding.fx_expr) then
      for ordinal, spec in ipairs(binding.specs or {}) do
        if spec.index ~= nil then
          resolved_indices[
            binding.mapped_var .. "[" .. tostring(ordinal) .. "]"
          ] = spec.index
        end
      end
    end
  end

  local function parameter_index(expr)
    local literal = literal_number(expr)
    if literal ~= nil then return literal end
    return resolved_indices[trim_expr(expr):gsub("%s+", "")]
  end

  for line_no, line in ipairs(lines) do
    for _, name in ipairs({
      "reaper%.TrackFX_SetParamNormalized",
      "reaper%.TrackFX_SetParam",
    }) do
      local args = call_args(line, name)
      if args and is_proq_fx_expr(args[2]) then
        local idx = parameter_index(args[3])
        local val = literal_number(args[4])
        local shape_base = base_for_idx(idx, 5)
        if shape_base and val and math.abs(val) < 0.000001 then
          local b = ensure_band(shape_base)
          b.shape_bell = true
          b.shape_line = b.shape_line or line_no
        end
        local gain_base = base_for_idx(idx, 3)
        if gain_base and args[4] and tostring(args[4]):match("%S") then
          local b = ensure_band(gain_base)
          b.gain = true
          b.gain_line = b.gain_line or line_no
        end
        local slope_base = base_for_idx(idx, 6)
        if slope_base then
          local b = ensure_band(slope_base)
          b.slope_direct = true
          b.slope_direct_line = b.slope_direct_line or line_no
          if name:find("SetParamNormalized", 1, true)
             and is_slope_norm_12(val) then
            b.slope_direct_12 = true
          end
        end
      end
    end

    local args = call_args(line, "set_param_display")
    if args and is_proq_fx_expr(args[2]) then
      local idx = parameter_index(args[3])
      local target = literal_number(args[4])
      local slope_base = base_for_idx(idx, 6)
      if slope_base then
        local b = ensure_band(slope_base)
        if target and math.abs(target - 12) < 0.000001 then
          b.slope_display_12 = true
          b.slope_display_line = b.slope_display_line or line_no
        else
          b.slope_other_display = true
          b.slope_other_line = b.slope_other_line or line_no
        end
      end
    end
  end

  local violations = {}
  for _, b in pairs(bands) do
    if b.shape_bell and b.gain
       and not b.slope_display_12
       and not b.slope_direct_12 then
      violations[#violations + 1] = {
        band = b.band,
        line = b.shape_line or b.gain_line or b.slope_direct_line or 1,
        slope_idx = b.slope_idx,
        direct_norm = b.slope_direct == true,
        wrong_display = b.slope_other_display == true,
      }
    end
  end

  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.band) < tostring(b.band)
  end)
  return violations
end

-- =============================================================================
-- Code.find_reeq_gain_mapping_violations
-- =============================================================================
-- ReaEQ band-gain parameters do not share the generic raw or normalized
-- mappings that models often invent. When only live fx_params context is
-- available, the safe contract is to work in displayed dB through the
-- canonical set_param_display helper. Keep this scanner intentionally narrow:
-- literal or simple-literal-aliased ReaEQ lookups, literal/simple-literal
-- band-gain indices, and direct TrackFX writes or helper calls whose target
-- can be classified confidently.

function Code.prompt_requests_relative_db_adjustment(user_text)
  local text = tostring(user_text or ""):lower():gsub("%s+", " ")
  if text == "" then return false end
  local by_db = text:find(
    "%f[%a]by%f[%A]%s*[+-]?%s*%d*%.?%d+%s*d%s*b%f[%A]")
    or text:find(
      "%f[%a]by%f[%A]%s*[+-]?%s*%d*%.?%d+%s*decibel%f[%A]")
    or text:find(
      "%f[%a]by%f[%A]%s*[+-]?%s*%d*%.?%d+%s*decibels%f[%A]")
  if not by_db then return false end
  for _, pattern in ipairs({
    "lower", "lowered", "reduce", "reduced", "decrease", "decreased",
    "drop", "dropped", "cut", "raise", "raised", "increase", "increased",
    "boost", "boosted", "bump", "bumped", "nudge", "nudged",
    "lift", "lifted", "turn%s+down", "turn%s+up",
  }) do
    if text:find("%f[%a]" .. pattern .. "%f[%A]") then return true end
  end
  return false
end

function Code.reeq_live_gain_gate_active(sticky_context, opts)
  if type(sticky_context) ~= "table" then return false end
  opts = type(opts) == "table" and opts or {}
  local live_values = false
  local reference_pinned = false

  local function mentions_reeq(payload, require_scope)
    for part in tostring(payload or ""):gmatch("[^/]+") do
      local name = part
      if require_scope then
        if not name:match("@%s*%d+%s*$") then goto continue_part end
        name = name:gsub("@%s*%d+%s*$", "")
      end
      local normalized = name:lower():gsub("[^%a%d]", "")
      if normalized:find("reaeq", 1, true) then return true end
      ::continue_part::
    end
    return false
  end

  for key in pairs(sticky_context) do
    local lower = tostring(key or ""):lower()
    local fx_payload = lower:match("^fx:(.+)$")
    if fx_payload and mentions_reeq(fx_payload, false) then
      -- The mapping risk comes from using live ReaEQ values for a generated
      -- write, not from whether the read was scoped to one track. Keep
      -- unscoped read-only inspection available; the downstream scanner only
      -- reports an actual unsafe gain write.
      live_values = true
    end
    local ref_payload = lower:match("^plugin_ref:(.+)$")
    if ref_payload and mentions_reeq(ref_payload, false) then
      -- A reference pulled only because the model requested more context must
      -- not become a conversation-long escape hatch from the live-value gate.
      -- Deliberately pre-pinned/copy-pinned references retain their existing
      -- behavior, and callers without provenance remain backward-compatible.
      local source = type(opts.sticky_pin_source) == "table"
        and opts.sticky_pin_source[key] or nil
      if source ~= "context_needed" then reference_pinned = true end
    end
  end
  return live_values and (opts.ignore_reference == true or not reference_pinned)
end

function Code.find_reeq_gain_mapping_violations(lua_code, opts)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  opts = type(opts) == "table" and opts or {}
  local relative_request = opts.relative_request
  if relative_request == nil then
    relative_request = Code.prompt_requests_relative_db_adjustment(opts.user_text)
  end
  local absolute_db_targets = {}
  do
    local prompt = tostring(opts.user_text or ""):lower()
    local function collect(pattern)
      for value in prompt:gmatch(pattern) do
        value = tonumber(value)
        if value ~= nil then
          absolute_db_targets[#absolute_db_targets + 1] = value
        end
      end
    end
    collect("%f[%a]to%f[%A]%s*([+-]?%d*%.?%d+)%s*d%s*b%f[%A]")
    collect("%f[%a]to%f[%A]%s*([+-]?%d*%.?%d+)%s*decibels?%f[%A]")
  end

  -- Preserve newlines and byte positions for finding line numbers while
  -- removing every Lua comment form and code-looking string content. Real
  -- quoted ReaEQ names remain as canonical string literals for FX lookup.
  local stripped, has_reeq_literal = Code._lua_reeq_scan_source(lua_code)
  if not has_reeq_literal then return nil end

  local assignment_counts = {}
  local numeric_assignment = {}
  local string_assignment = {}
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    local name, rhs = line:match(
      "^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not name then
      name, rhs = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if name then
      rhs = Code._lua_trim_expr(tostring(rhs or ""):gsub(";%s*$", ""))
      assignment_counts[name] = (assignment_counts[name] or 0) + 1
      local number = tonumber(rhs)
      if number ~= nil then numeric_assignment[name] = number end
      local quote = rhs:sub(1, 1)
      if (quote == '"' or quote == "'") and rhs:sub(-1) == quote then
        string_assignment[name] = rhs
      end
    end
  end
  local literal_vars = {}
  for name, number in pairs(numeric_assignment) do
    if assignment_counts[name] == 1 then literal_vars[name] = number end
  end
  local literal_string_vars = {}
  for name, value in pairs(string_assignment) do
    if assignment_counts[name] == 1 then literal_string_vars[name] = value end
  end

  local function literal_number(expr)
    expr = Code._lua_trim_expr(expr)
    return tonumber(expr) or literal_vars[expr]
  end

  local gain_indices = { [1] = true, [4] = true, [7] = true,
    [10] = true, [13] = true }
  local function gain_index(expr)
    local value = literal_number(expr)
    if not value or value % 1 ~= 0 or not gain_indices[value] then return nil end
    return value
  end

  local function literal_reeq_name(expr)
    expr = Code._lua_trim_expr(expr)
    expr = literal_string_vars[expr] or expr
    local quote = expr:sub(1, 1)
    if (quote == '"' or quote == "'") and expr:sub(-1) == quote then
      local normalized = expr:sub(2, -2):lower():gsub("[^%a%d]", "")
      return normalized:find("reaeq", 1, true) ~= nil
    end
    -- Newline-split long strings use the scanner's whitespace-separated bare
    -- sentinel. Require the exact normalized sentinel so ordinary variables
    -- and expressions cannot be mistaken for an FX-name literal.
    if expr:match("^[%a_][%w_]*$") then return false end
    return expr:lower():gsub("[^%a%d]", "") == "reaeq"
  end

  local reeq_fx_vars = {}
  local function scan_fx_lookup(api_name)
    local pos = 1
    local pattern = "reaper%." .. api_name .. "%s*%("
    while true do
      local call_start, open_pos = stripped:find(pattern, pos)
      if not call_start then break end
      local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
      if args and literal_reeq_name(args[2]) then
        local before = stripped:sub(math.max(1, call_start - 240), call_start - 1)
        local lhs = before:match("local%s+([%a_][%w_]*)%s*=%s*$")
          or before:match("([%a_][%w_]*)%s*=%s*$")
        if lhs then reeq_fx_vars[lhs] = true end
      end
      pos = (close_pos or open_pos) + 1
    end
  end
  scan_fx_lookup("TrackFX_GetByName")
  scan_fx_lookup("TrackFX_AddByName")
  if not next(reeq_fx_vars) then return nil end

  local function resolved_triplet(args)
    if not args then return nil, nil, nil end
    local track_expr = Code._lua_trim_expr(args[1])
    local fx_expr = Code._lua_trim_expr(args[2])
    if not reeq_fx_vars[fx_expr] then return nil, nil, nil end
    return track_expr, fx_expr, gain_index(args[3])
  end

  local function access_key(track_expr, fx_expr, idx)
    return track_expr .. "\0" .. fx_expr .. "\0" .. tostring(idx)
  end

  local formatted_reads = {}
  do
    local pos = 1
    while true do
      local call_start, open_pos = stripped:find(
        "reaper%.TrackFX_GetFormattedParamValue%s*%(", pos)
      if not call_start then break end
      local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
      local track_expr, fx_expr, idx = resolved_triplet(args)
      if track_expr and fx_expr and idx then
        formatted_reads[access_key(track_expr, fx_expr, idx)] = true
      end
      pos = (close_pos or open_pos) + 1
    end
  end

  local findings = {}
  local function add(kind, pos, fx_expr, idx, detail)
    findings[#findings + 1] = {
      kind = kind,
      line = Code._lua_line_for_pos(stripped, pos),
      fx = fx_expr,
      param_index = idx,
      detail = detail,
    }
  end

  local function scan_direct(api_name, kind)
    local pos = 1
    local pattern = "reaper%." .. api_name .. "%s*%("
    while true do
      local call_start, open_pos = stripped:find(pattern, pos)
      if not call_start then break end
      local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
      local _, fx_expr, idx = resolved_triplet(args)
      if fx_expr and idx then
        add(kind, call_start, fx_expr, idx,
          "ReaEQ gain index " .. idx .. " uses reaper." .. api_name
            .. " instead of set_param_display")
      end
      pos = (close_pos or open_pos) + 1
    end
  end
  scan_direct("TrackFX_SetParamNormalized", "direct_normalized_gain_write")
  scan_direct("TrackFX_SetParam", "direct_raw_gain_write")

  local pos = 1
  while true do
    local call_start, open_pos = stripped:find(
      "%f[%w_]set_param_display%s*%(", pos)
    if not call_start then break end
    local before = stripped:sub(math.max(1, call_start - 32), call_start - 1)
    local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
    if not before:match("function%s+$") then
      local track_expr, fx_expr, idx = resolved_triplet(args)
      if relative_request and fx_expr and idx then
        local target = Code._lua_trim_expr(args[4])
        local target_number = literal_number(target)
        local explicit_absolute = false
        if target_number ~= nil then
          for _, value in ipairs(absolute_db_targets) do
            if math.abs(target_number - value) <= 0.000001 then
              explicit_absolute = true
              break
            end
          end
        end
        if target_number ~= nil and not explicit_absolute then
          add("relative_literal_target", call_start, fx_expr, idx,
            "relative ReaEQ gain edit uses an absolute literal display target")
        end
        if not explicit_absolute
           and not formatted_reads[access_key(track_expr, fx_expr, idx)] then
          add("relative_missing_formatted_read", call_start, fx_expr, idx,
            "relative ReaEQ gain edit does not read the current displayed value for the same track/FX/index")
        end
      end
    end
    pos = (close_pos or open_pos) + 1
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.kind) < tostring(b.kind)
  end)
  return findings
end

-- =============================================================================
-- Code.find_proq4_literal_mapping_mismatches
-- =============================================================================
-- Models often keep a helpful human target in a table-row comment but copy the
-- normalized value from the adjacent reference row (for example 100 Hz's
-- value beside a `120 Hz` comment). The script compiles and runs, yet lands on
-- the wrong audible value. For Pro-Q 4 only, verify literal normalized
-- `freq*`, `gain*`, and `q*` named fields against a same-line human comment.
-- Human-unit fields such as `freq_hz` and `gain_db`, nonliteral expressions,
-- and uncommented values are intentionally outside this high-confidence gate.
function Code.find_proq4_literal_mapping_mismatches(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local lower = lua_code:gsub("%-%-[^\n]*", ""):lower()
  if not lower:find("pro%-q%s*4") then return nil end

  local findings = {}
  local function add(kind, line_no, actual, target, expected, tolerance)
    -- Accept a value deliberately rounded to two decimal places. The maximum
    -- nearest-hundredth error is 0.005; a small epsilon avoids binary-float
    -- edge noise without concealing adjacent reference-row mistakes. Direct
    -- setter literals with an explicit human target use a much tighter
    -- tolerance so a value such as 0.444 cannot masquerade as exact 350 Hz
    -- (it displays about 349.82 Hz); those should use the documented formula.
    if math.abs(actual - expected) <= (tolerance or 0.0051) then return end
    findings[#findings + 1] = {
      kind = kind,
      line = line_no,
      actual = actual,
      target = target,
      expected = expected,
    }
  end

  local line_no = 0
  for line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local code_part, comment = line:match("^(.-)%-%-(.*)$")
    if code_part and comment then
      local field, value = code_part:match(
        "%f[%w_]([Ff][Rr][Ee][Qq][%w_]*)%s*=%s*([%d%.]+)")
      value = tonumber(value)
      if field and value and value >= 0 and value <= 1
         and not field:lower():find("hz", 1, true) then
        local khz = tonumber(comment:match("([%d%.]+)%s*[kK]%s*[hH][zZ]"))
        local hz = khz and (khz * 1000)
          or tonumber(comment:match("([%d%.]+)%s*[hH][zZ]"))
        if hz and hz >= 10 and hz <= 30000 then
          add("frequency", line_no, value, hz,
            math.log(hz / 10) / math.log(3000))
        end
      end

      field, value = code_part:match(
        "%f[%w_]([Gg][Aa][Ii][Nn][%w_]*)%s*=%s*([%d%.]+)")
      value = tonumber(value)
      if field and value and value >= 0 and value <= 1
         and not field:lower():find("db", 1, true) then
        local db = tonumber(comment:match("([+-]?[%d%.]+)%s*[dD][bB]"))
        if db and db >= -30 and db <= 30 then
          add("gain", line_no, value, db, (db + 30) / 60)
        end
      end

      field, value = code_part:match(
        "%f[%w_]([Qq][%w_]*)%s*=%s*([%d%.]+)")
      value = tonumber(value)
      if field and value and value >= 0 and value <= 1
         and not field:lower():find("display", 1, true) then
        -- Remove the product name before looking for an explicit Q target;
        -- otherwise the "Q 4" in "Pro-Q 4" becomes a fabricated target.
        local q_comment = comment
          :gsub("[Pp][Rr][Oo][%s%-]*[Qq]%s*4", "")
        local q = tonumber(q_comment:match("[Qq]%s*=?%s*([%d%.]+)"))
        if q and q >= 0.025 and q <= 40 then
          add("q", line_no, value, q,
            math.log(q / 0.025) / math.log(1600))
        end
      end

      local direct = code_part:match(
        "reaper%.TrackFX_SetParamNormalized%s*%([^,]+,[^,]+,[^,]+,%s*([%d%.]+)%s*%)")
        or code_part:match(
          "[%a_][%w_]*%s*%(%s*mapped%s*%[%s*%d+%s*%]%s*,%s*"
            .. "([%d%.]+)%s*%)")
      direct = tonumber(direct)
      if direct and direct >= 0 and direct <= 1 then
        local khz = tonumber(comment:match("([%d%.]+)%s*[kK]%s*[hH][zZ]"))
        local hz = khz and (khz * 1000)
          or tonumber(comment:match("([%d%.]+)%s*[hH][zZ]"))
        if hz and hz >= 10 and hz <= 30000 then
          add("frequency", line_no, direct, hz,
            math.log(hz / 10) / math.log(3000), 0.000001)
        elseif not comment:lower():find("db%s*/%s*oct") then
          local db = tonumber(comment:match("([+-]?[%d%.]+)%s*[dD][bB]"))
          if db and db >= -30 and db <= 30 then
            add("gain", line_no, direct, db, (db + 30) / 60, 0.000001)
          else
            local q_comment = comment
              :gsub("[Pp][Rr][Oo][%s%-]*[Qq]%s*4", "")
            local q = tonumber(
              q_comment:match("[Qq]%s*=?%s*([%d%.]+)"))
            if q and q >= 0.025 and q <= 40 then
              add("q", line_no, direct, q,
                math.log(q / 0.025) / math.log(1600), 0.000001)
            end
          end
        end
      end
    end
  end

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.kind) < tostring(b.kind)
  end)
  return findings
end

-- Deterministically repair only the highest-confidence form caught above:
-- a direct Pro-Q 4 SetParamNormalized call whose literal fourth argument is
-- paired with an explicit human target in the same-line comment. Replace the
-- guessed literal with the exact documented expression, then let the normal
-- validator re-check the whole script. Named table fields are left to the
-- retry/block path because their eventual parameter destination is not
-- provable from one line.
function Code.repair_proq4_literal_mapping_mismatches(lua_code)
  local findings = Code.find_proq4_literal_mapping_mismatches(lua_code)
  if not findings or #findings == 0 then
    return lua_code, false, nil
  end

  local by_line = {}
  for _, finding in ipairs(findings) do
    local n = tonumber(finding.line)
    if n then by_line[n] = finding end
  end

  local newline = lua_code:find("\r\n", 1, true) and "\r\n" or "\n"
  local lines = {}
  for line in (lua_code:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end

  local repaired = {}
  for line_no, finding in pairs(by_line) do
    local line = lines[line_no]
    local expression
    if finding.kind == "frequency" then
      expression = ("math.log(%s / 10) / math.log(3000)")
        :format(tostring(finding.target))
    elseif finding.kind == "gain" then
      expression = ("(%s + 30) / 60"):format(tostring(finding.target))
    elseif finding.kind == "q" then
      expression = ("math.log(%s / 0.025) / math.log(1600)")
        :format(tostring(finding.target))
    end

    if line and expression then
      local prefix, literal, suffix = line:match(
        "^(.-reaper%.TrackFX_SetParamNormalized%s*%("
          .. "[^,]+,[^,]+,[^,]+,%s*)([%d%.]+)(%s*%).*)$")
      if not prefix then
        prefix, literal, suffix = line:match(
          "^(.-[%a_][%w_]*%s*%(%s*mapped%s*%[%s*%d+%s*%]%s*,%s*)"
            .. "([%d%.]+)(%s*%).*)$")
      end
      if prefix and literal and suffix
         and math.abs((tonumber(literal) or -1)
           - (tonumber(finding.actual) or -2)) <= 0.000000000001 then
        lines[line_no] = prefix .. expression .. suffix
        repaired[#repaired + 1] = finding
      end
    end
  end

  if #repaired == 0 then return lua_code, false, findings end
  table.sort(repaired, function(a, b) return a.line < b.line end)
  return table.concat(lines, newline), true, repaired
end

-- Code.prompt_targets_existing_fx
-- True only when the prompt structurally targets an FX instance that is
-- already present. This keeps musical-result wording such as "use the existing
-- Saturation effect to add warmth" out of insertion and add-only validators:
-- the word "add" describes the sonic result there, not a new plugin.
function Code.prompt_targets_existing_fx(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  local existing =
    lo:find("%f[%w]existing%f[%W]") ~= nil
    or lo:find("%f[%w]already%s+inserted%f[%W]") ~= nil
    or lo:find("%f[%w]already%s+loaded%f[%W]") ~= nil
    or lo:find("%f[%w]already%s+on%f[%W]") ~= nil
    or lo:find("%f[%w]already%s+there%f[%W]") ~= nil
    or lo:find("%f[%w]already%s+present%f[%W]") ~= nil
    or lo:find("%f[%w]currently%s+on%f[%W]") ~= nil
  if not existing then return false end
  return lo:find("%f[%w]use%f[%W]") ~= nil
    or lo:find("%f[%w]give%f[%W]") ~= nil
    or lo:find("%f[%w]refine%f[%W]") ~= nil
    or lo:find("%f[%w]make%f[%W]") ~= nil
    or lo:find("%f[%w]modify%f[%W]") ~= nil
    or lo:find("%f[%w]configure%f[%W]") ~= nil
    or lo:find("%f[%w]adjust%f[%W]") ~= nil
    or lo:find("%f[%w]tweak%f[%W]") ~= nil
    or lo:find("%f[%w]change%f[%W]") ~= nil
    or lo:find("%f[%w]edit%f[%W]") ~= nil
    or lo:find("%f[%w]set%f[%W]") ~= nil
    or lo:find("%f[%w]dial%f[%W]") ~= nil
    or lo:find("%f[%w]shape%f[%W]") ~= nil
    or lo:find("%f[%w]clean%s+up%f[%W]") ~= nil
end

-- =============================================================================
-- Code.find_dependent_getbyname_silent_skips
-- =============================================================================
-- Static check for TrackFX_GetByName / TakeFX_GetByName results that drive
-- required parameter work but only have a success-direction guard:
--
--   local fx = reaper.TrackFX_GetByName(tr, "Pro-Q 4", false)
--   if fx >= 0 then
--     set_param_display(tr, fx, ...)
--   end                            -- no else, no error, no return
--
-- GetByName is allowed to return -1 in upsert code, so this intentionally
-- does NOT require every GetByName call to fail immediately. It only flags
-- the dependent-use case when there is no real failure path (`fx < 0` with
-- return/message/error, or the canonical GetByName -> AddByName
-- fallback followed by that final failure path).
--
-- Returns a sorted list of `{name, line}` entries, or nil if every dependent
-- GetByName result has an explicit failure path.
function Code.find_dependent_getbyname_silent_skips(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local lines = {}
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines+1] = line
  end

  local function _var_pat(name)
    return "%f[%w_]" .. tostring(name or "") .. "%f[^%w_]"
  end

  local function _is_failure_cmp(line, name)
    local v = _var_pat(name)
    return line:find(v .. "%s*<%s*0")
        or line:find(v .. "%s*==%s*%-%s*1")
        or line:find(v .. "%s*<=%s*%-%s*1")
        or line:find(v .. "%s*<%s*%-%s*1")
  end

  local function _failure_path_reports(assign_line, name)
    for i = assign_line, #lines do
      if _is_failure_cmp(lines[i], name) then
        local stop = math.min(#lines, i + 16)
        local chunk = table.concat(lines, "\n", i, stop)
        if chunk:find("error%s*%(")
           or chunk:find("%f[%w_]return%f[^%w_]")
           or chunk:find("ShowMessageBox", 1, true)
           or chunk:find("errors%s*%[")
           or chunk:find("failed%s*%[")
           or chunk:find("failures%s*%[")
           or chunk:find("missing%s*%[") then
          return true
        end
      end
    end
    return false
  end

  local param_api = {
    "TrackFX_SetParam", "TrackFX_SetParamNormalized",
    "TrackFX_GetParam", "TrackFX_GetParamNormalized",
    "TrackFX_GetParamName", "TrackFX_GetFormattedParamValue",
    "TrackFX_GetNumParams",
    "TakeFX_SetParam", "TakeFX_SetParamNormalized",
    "TakeFX_GetParam", "TakeFX_GetParamNormalized",
    "TakeFX_GetParamName", "TakeFX_GetFormattedParamValue",
    "TakeFX_GetNumParams",
  }

  local param_helpers = {
    find_param = true,
    set_param_display = true,
    set_param_enum = true,
    set_param_enum_paced = true,
  }

  local function _mark_param_helper(name, body)
    if not name or param_helpers[name] then return end
    for _, api in ipairs(param_api) do
      if body:find(api, 1, true) then
        param_helpers[name] = true
        return
      end
    end
  end

  do
    local pos = 1
    while true do
      local s, e, name = stripped:find("local%s+function%s+([%a_][%w_]*)%s*%(", pos)
      if not s then break end
      local next_s = stripped:find("\n%s*local%s+function%s+", e + 1)
        or stripped:find("\n%s*function%s+", e + 1)
        or (#stripped + 1)
      _mark_param_helper(name, stripped:sub(e + 1, next_s - 1))
      pos = e + 1
    end
    pos = 1
    while true do
      local s, e, name = stripped:find("\n%s*function%s+([%a_][%w_]*)%s*%(", pos)
      if not s then break end
      local next_s = stripped:find("\n%s*local%s+function%s+", e + 1)
        or stripped:find("\n%s*function%s+", e + 1)
        or (#stripped + 1)
      _mark_param_helper(name, stripped:sub(e + 1, next_s - 1))
      pos = e + 1
    end
  end

  local function _has_dependent_param_use(text, name)
    local v = _var_pat(name)
    local in_named_function = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      local starts_named_function =
        line:match("^%s*local%s+function%s+[%a_][%w_]*%s*%(")
        or line:match("^%s*function%s+[%a_][%w_]*%s*%(")
      if starts_named_function then
        in_named_function = in_named_function + 1
      end
      if in_named_function == 0 then
        for _, api in ipairs(param_api) do
          if line:find(api, 1, true) and line:find(v) then
            return true
          end
        end
        for helper in pairs(param_helpers) do
          if line:find("%f[%w_]" .. helper .. "%s*%([^%)]*" .. v) then
            return true
          end
        end
      end
      if in_named_function > 0 and line:match("^%s*end%s*$") then
        in_named_function = in_named_function - 1
      end
    end
    return false
  end

  local function _get_assignment(line)
    local name = line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*reaper%.TrackFX_GetByName%s*%(")
      or line:match("^%s*([%a_][%w_]*)%s*=%s*reaper%.TrackFX_GetByName%s*%(")
      or line:match("^%s*local%s+([%a_][%w_]*)%s*=%s*reaper%.TakeFX_GetByName%s*%(")
      or line:match("^%s*([%a_][%w_]*)%s*=%s*reaper%.TakeFX_GetByName%s*%(")
    return name
  end

  local violations, seen = {}, {}
  for i, line in ipairs(lines) do
    local name = _get_assignment(line)
    if name and not seen[name .. ":" .. tostring(i)] then
      seen[name .. ":" .. tostring(i)] = true
      local after = table.concat(lines, "\n", i + 1)
      if _has_dependent_param_use(after, name)
         and not _failure_path_reports(i, name) then
        violations[#violations+1] = { name = name, line = i }
      end
    end
  end

  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.name < b.name
  end)
  return violations
end

-- An explicit existing-effect edit must fail clearly when the named instance is
-- absent. Adding a replacement can conceal a bad target and create a duplicate
-- in another location. Flag only GetByName/AddByName pairs for the same
-- normalized identifier so a mixed request may still add a different effect.
-- A validated profile receipt may also prove that a definite-article request
-- such as "make the chorus..." targets the existing live instance even though
-- the prompt does not literally say "existing".
function Code.find_existing_fx_add_fallback_violations(
    user_text, lua_code, profile_receipts)
  if type(lua_code) ~= "string" or lua_code == "" then
    return nil
  end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local string_consts = {}
  for name, value in stripped:gmatch(
      "local%s+([%w_]+)%s*=%s*\"([^\"]+)\"") do
    string_consts[name] = value
  end
  for name, value in stripped:gmatch(
      "local%s+([%w_]+)%s*=%s*'([^']+)'") do
    string_consts[name] = value
  end
  local function resolve_arg(value)
    if value and value:match("^[%w_]+$") and string_consts[value] then
      return string_consts[value]
    end
    return value
  end
  local function norm(value)
    local n = tostring(value or ""):lower()
    n = n:match("^[a-z][a-z0-9]*:%s*(.+)$") or n
    n = n:gsub("%s*%b()%s*$", "")
    return n:gsub("[^%w]+", "")
  end
  local existing_profile_keys = {}
  for _, receipt in ipairs(type(profile_receipts) == "table"
      and profile_receipts or {}) do
    if type(receipt) == "table" and receipt.existing_request == true then
      local key = norm(receipt.identifier)
      if key ~= "" then existing_profile_keys[key] = true end
    end
  end
  if not Code.prompt_targets_existing_fx(user_text)
     and next(existing_profile_keys) == nil then
    return nil
  end
  local gets, adds = {}, {}
  local function call_arg(text, api)
    return text:match(api .. "%s*%([^,]+,%s*\"([^\"]+)\"")
      or text:match(api .. "%s*%([^,]+,%s*'([^']+)'")
      or resolve_arg(text:match(
        api .. "%s*%([^,]+,%s*([%w_]+)%s*,"))
  end
  local function collect_calls(api, callback)
    local position = 1
    while true do
      local first, last = stripped:find(api .. "%s*%(", position)
      if not first then return end
      local chunk = stripped:sub(first, math.min(#stripped, first + 1000))
      local id = call_arg(chunk, api)
      if id then
        local _, newline_count = stripped:sub(1, first):gsub("\n", "\n")
        callback(id, newline_count + 1)
      end
      position = math.max(last + 1, first + #api)
    end
  end
  for _, api in ipairs({ "TrackFX_GetByName", "TakeFX_GetByName" }) do
    collect_calls(api, function(id, line)
      local key = norm(id)
      if key ~= "" then
        gets[key] = gets[key] or { id = id, line = line }
      end
    end)
  end
  for _, api in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
    collect_calls(api, function(id, line)
      local key = norm(id)
      if key ~= "" then
        adds[#adds + 1] = { id = id, key = key, line = line }
      end
    end)
  end
  local violations = {}
  for _, add in ipairs(adds) do
    if gets[add.key] or existing_profile_keys[add.key] then
      violations[#violations + 1] = {
        id = add.id,
        line = add.line,
        lookup_line = gets[add.key] and gets[add.key].line or nil,
        existing_profile = existing_profile_keys[add.key] == true,
      }
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return tostring(a.id) < tostring(b.id)
  end)
  return violations
end

-- =============================================================================
-- Code.find_add_requested_getonly_fx_violations
-- =============================================================================
-- When the user explicitly says to add/put/load/apply/use a named FX, a
-- GetByName-only script with a "not found" return does not satisfy the
-- request. "Use <plugin> to..." also needs an add-if-missing fallback: it
-- safely reuses an existing instance while still fulfilling the request on a
-- track where that plugin is absent. This catches that narrow intent while
-- leaving ordinary modify-existing GetByName scripts alone.
function Code.find_add_requested_getonly_fx_violations(user_text, lua_code)
  if not lua_code or lua_code == "" then return nil end
  if Code.prompt_targets_existing_fx(user_text) then return nil end
  local prompt = tostring(user_text or ""):lower():gsub("%s+", " ")
  if prompt == "" then return nil end

  local known = {
    { key = "reaeq", labels = { "reaeq", "rea eq" } },
    { key = "reacomp", labels = { "reacomp", "rea comp" } },
    { key = "reaxcomp", labels = { "reaxcomp", "rea xcomp", "rea x-comp" } },
    { key = "reagate", labels = { "reagate", "rea gate" } },
    { key = "readelay", labels = { "readelay", "rea delay" } },
    { key = "realimit", labels = { "realimit", "rea limit" } },
    { key = "reapitch", labels = { "reapitch", "rea pitch" } },
    { key = "reatune", labels = { "reatune", "rea tune" } },
    { key = "reasynth", labels = { "reasynth", "rea synth" } },
    { key = "reaverbate", labels = { "reaverbate", "rea verbate" } },
    { key = "proq4", labels = { "pro-q 4", "pro q 4", "pro-q", "pro q" } },
    { key = "proc3", labels = { "pro-c 3", "pro c 3", "pro-c", "pro c" } },
    { key = "prog", labels = { "pro-g", "pro g" } },
    { key = "prol2", labels = { "pro-l 2", "pro l 2", "pro-l", "pro l" } },
    { key = "promb", labels = { "pro-mb", "pro mb" } },
    { key = "prods", labels = { "pro-ds", "pro ds" } },
    { key = "pror2", labels = { "pro-r 2", "pro r 2", "pro-r", "pro r" } },
    { key = "saturn2", labels = { "saturn 2" } },
    { key = "timeless3", labels = { "timeless 3" } },
  }
  local verbs = { "add", "put", "insert", "load", "place", "apply", "use" }
  local requested = {}
  for _, fx in ipairs(known) do
    for _, label in ipairs(fx.labels) do
      for _, verb in ipairs(verbs) do
        if prompt:find(verb .. " " .. label, 1, true)
           or prompt:find(verb .. " a " .. label, 1, true)
           or prompt:find(verb .. " an " .. label, 1, true)
           or prompt:find(verb .. " the " .. label, 1, true) then
          requested[fx.key] = label
        end
      end
    end
  end
  if not next(requested) then return nil end

  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local string_consts = {}
  for ident, val in stripped:gmatch("local%s+([%w_]+)%s*=%s*\"([^\"]+)\"") do
    string_consts[ident] = val
  end
  for ident, val in stripped:gmatch("local%s+([%w_]+)%s*=%s*'([^']+)'") do
    string_consts[ident] = val
  end

  local function norm(id)
    local n = tostring(id or ""):lower()
    n = n:match("^[a-z][a-z0-9]*:%s*(.+)$") or n
    n = n:gsub("%s*%b()%s*$", "")
    return n:gsub("[^%w]+", "")
  end
  local function requested_key_for(n)
    if n == "" then return false end
    for key in pairs(requested) do
      if n == key or n:find(key, 1, true)
         or key:find(n, 1, true) == 1 then
        return key
      end
    end
    return nil
  end
  local function resolve_arg(cap)
    if cap and cap:match("^[%w_]+$") and string_consts[cap] then
      return string_consts[cap]
    end
    return cap
  end

  local add_keys, get_entries = {}, {}
  local lines = {}
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  for i, line in ipairs(lines) do
    for _, api in ipairs({ "TrackFX_AddByName", "TakeFX_AddByName" }) do
      local cap = line:match(api .. "%s*%([^,]+,%s*\"([^\"]+)\"")
        or line:match(api .. "%s*%([^,]+,%s*'([^']+)'")
        or resolve_arg(line:match(api .. "%s*%([^,]+,%s*([%w_]+)%s*,"))
      if cap then
        local add_key = requested_key_for(norm(cap))
        if add_key then add_keys[add_key] = true end
      end
    end
    for _, api in ipairs({ "TrackFX_GetByName", "TakeFX_GetByName" }) do
      local cap = line:match(api .. "%s*%([^,]+,%s*\"([^\"]+)\"")
        or line:match(api .. "%s*%([^,]+,%s*'([^']+)'")
        or resolve_arg(line:match(api .. "%s*%([^,]+,%s*([%w_]+)%s*,"))
      if cap then
        local get_key = requested_key_for(norm(cap))
        if get_key then
          get_entries[#get_entries + 1] = {
            id = cap,
            key = norm(cap),
            requested_key = get_key,
            line = i,
          }
        end
      end
    end
  end

  local violations = {}
  for _, e in ipairs(get_entries) do
    if not add_keys[e.requested_key] then
      violations[#violations + 1] = e
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.id < b.id
  end)
  return violations
end

-- =============================================================================
-- Code.find_chain_upsert_violations
-- =============================================================================
-- Strict-pairing check for chain-build follow-up turns: every plugin name
-- referenced via TrackFX_GetByName MUST also appear in a TrackFX_AddByName
-- call (and vice-versa). Catches two opposite anti-patterns observed
-- across providers when fx_chains is pinned and the user said "build a
-- vocal chain" / "set up a chain":
--
--   GET-ONLY (ChatGPT pattern): GetByName for all required plugins,
--   then if any returns < 0, ShowMessageBox "missing one or more chain
--   plugins" and return. Misses the "add the missing ones" half of the
--   upsert -- the script bails when the chain is incomplete instead of
--   completing it.
--
--   ADD-ONLY (Claude pattern): AddByName for every plugin without
--   checking whether the plugin is already on the track. Silently
--   duplicates plugins that an earlier turn already placed.
--
-- The canonical pattern requires BOTH calls for the same plugin:
--   local fx = reaper.TrackFX_GetByName(tr, "Pro-Q 4", false)
--   if fx < 0 then
--     fx = reaper.TrackFX_AddByName(tr, "VST3: Pro-Q 4", false, -1)
--   end
--   if fx < 0 then -- report failure end
--
-- Caller is responsible for gating: only run when the prompt is a chain-
-- build (CHAIN_PHRASE_HINTS matched) AND fx_chains was preempted/pinned
-- this turn. In other contexts both patterns can be legitimate
-- (modifying an existing instance, adding a new plugin to a fresh track,
-- etc.) and this validator would false-positive.
--
-- Returns a list of `{kind, bare, id}` entries (kind is "get_only" or
-- "add_only", bare is the lowercased name without format prefix or
-- vendor suffix, id is the original string from the call) or nil if
-- every plugin name appears in both call types.
function Code.find_chain_upsert_violations(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-[^\n]*", "")
  local function _bare(id)
    if not id then return nil end
    local n = id:match("^[A-Za-z][A-Za-z0-9]*:%s*(.+)$") or id
    n = n:gsub("%s*%(.-%)%s*$", "")
    return n:lower()
  end
  -- Resolve simple `local NAME = "literal"` constants so AddByName /
  -- GetByName calls that pass a variable instead of a literal still
  -- match. Observed in a Gemini session that hoisted the identifier
  -- into local id_eq = "VST3: Pro-Q 4"; reaper.TrackFX_AddByName(tr,
  -- id_eq, ...) and slipped past the literal-only scan. Only resolves
  -- single-line `local X = "..."` -- not concatenations, function
  -- calls, table indexing, or reassignment.
  local string_consts = {}
  for ident, val in stripped:gmatch("local%s+([%w_]+)%s*=%s*\"([^\"]+)\"") do
    string_consts[ident] = val
  end
  for ident, val in stripped:gmatch("local%s+([%w_]+)%s*=%s*'([^']+)'") do
    string_consts[ident] = val
  end
  local function _resolve_arg(captured)
    -- captured may be a quoted string content (already resolved by the
    -- gmatch pattern that captured between quotes) or a bare identifier
    -- (when the pattern matched the variable form). Caller passes both
    -- shapes through this helper -- if it looks like an identifier and
    -- we have a constant for it, return the constant; otherwise return
    -- the captured value as-is.
    if not captured then return nil end
    if captured:match("^[%w_]+$") and string_consts[captured] then
      return string_consts[captured]
    end
    return captured
  end
  local get_names, add_names = {}, {}
  -- Match: TrackFX_GetByName(track_arg, "name"|'name'|IDENT, ...)
  for cap in stripped:gmatch("TrackFX_GetByName%s*%([^,]+,%s*\"([^\"]+)\"") do
    local b = _bare(cap); if b then get_names[b] = cap end
  end
  for cap in stripped:gmatch("TrackFX_GetByName%s*%([^,]+,%s*'([^']+)'") do
    local b = _bare(cap); if b then get_names[b] = cap end
  end
  for cap in stripped:gmatch("TrackFX_GetByName%s*%([^,]+,%s*([%w_]+)%s*,") do
    local resolved = _resolve_arg(cap)
    if resolved and resolved ~= cap then  -- only count if we resolved a const
      local b = _bare(resolved); if b then get_names[b] = resolved end
    end
  end
  for cap in stripped:gmatch("TrackFX_AddByName%s*%([^,]+,%s*\"([^\"]+)\"") do
    local b = _bare(cap); if b then add_names[b] = cap end
  end
  for cap in stripped:gmatch("TrackFX_AddByName%s*%([^,]+,%s*'([^']+)'") do
    local b = _bare(cap); if b then add_names[b] = cap end
  end
  for cap in stripped:gmatch("TrackFX_AddByName%s*%([^,]+,%s*([%w_]+)%s*,") do
    local resolved = _resolve_arg(cap)
    if resolved and resolved ~= cap then
      local b = _bare(resolved); if b then add_names[b] = resolved end
    end
  end
  local violations = {}
  for bare, id in pairs(get_names) do
    if not add_names[bare] then
      violations[#violations+1] = { kind = "get_only", bare = bare, id = id }
    end
  end
  for bare, id in pairs(add_names) do
    if not get_names[bare] then
      violations[#violations+1] = { kind = "add_only", bare = bare, id = id }
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b)
    if a.bare ~= b.bare then return a.bare < b.bare end
    return a.kind < b.kind
  end)
  return violations
end

-- =============================================================================
-- Code.find_helper_integrity_violations
-- =============================================================================
-- Narrow check for known-corrupted bundled helper bodies. The plugin_helpers
-- bundle's source is the canonical form; helpers are meant to be pasted
-- verbatim. Models occasionally rewrite or simplify the body in ways that
-- break safety -- the observed case from a ChatGPT 5.4 Mini session was the
-- range-guard on set_param_display:
--
--   GOOD: vmin and vmax and vmin < vmax and (target < vmin or target > vmax)
--   BAD:  vmin and vmax and target < vmin or target > vmax
--
-- Lua's and/or precedence makes the bad form parse as
-- `(vmin and vmax and target < vmin) or (target > vmax)`, so the second
-- disjunct evaluates `target > vmax` even when vmax is nil, producing
-- "attempt to compare nil with number" inside reaper.defer (after Code.run
-- has already logged "Script completed OK").
--
-- Detection keeps the canonical public/safety contract while tolerating
-- harmless formatting, statement separators, and internal-variable names.
-- Algorithm checks are scoped to the called helper's own function span so
-- unrelated code cannot lend a corrupted helper the fragments it is missing.
--
-- Returns a list of `{name, missing}` entries (missing is the canonical
-- fragment the helper body lacks), or nil if every defined helper looks
-- intact.
function Code.find_helper_integrity_violations(lua_code)
  if not lua_code or lua_code == "" then return nil end
  -- Treat descriptive variants such as `set_param_display_inverted` as the
  -- same safety-critical helper family. The observed recovery script renamed
  -- the helper and thereby skipped the old exact-name validator entirely.
  lua_code = tostring(lua_code):gsub(
    "%f[%w_]set_param_display[_%w]*%f[^%w_]", "set_param_display")
  -- Inlined to avoid a file-scope local slot (we're at the 200-local
  -- limit). Trivial reconstruction cost; this validator runs at most
  -- once per turn.
  local required_fragments = {
    set_param_display = {
      -- The helper is a tested source artifact, not a loose recipe. Keep its
      -- safety-critical parsing, unit conversion and range guards. The public
      -- signature and
      -- search/refinement structure are checked separately below so harmless
      -- declaration forms, internal-variable renames, and statement formatting
      -- do not turn a safe helper into a false positive.
      "local text = tostring(s or \"\"):gsub(\",\", \"\")",
      -- Nil-safe parse helper. The bare `s:gsub(...)` form crashes when
      -- TrackFX_GetFormattedParamValue returns nil (some VST3 plugins
      -- return that during the binary-search probe phase). The `(s or "")`
      -- guard turns a nil into a no-op match.
      "tostring(s or \"\"):gsub",
      -- Display units can change across one parameter's range. Comparing
      -- 10.00 ms to 2.500 sec as raw 10 and 2.5 reverses the range and rejects
      -- valid targets. Require base-unit conversion for time and frequency.
      "return value * 1000, \"frequency\", 1000",
      "return value, \"frequency\", 1",
      "return value, \"time\", 1",
      "return value * 1000, \"time\", 1000",
      -- Unit-bearing targets are authoritative. Legacy numeric targets on a
      -- mixed-unit range are accepted only when one interpretation is in
      -- range; ambiguous cases fail closed.
      "local target_value, target_family = parse(target_input)",
      "\"numeric target has ambiguous units; pass a unit-bearing string\"",
    },
  }
  -- Strip ALL whitespace and optional statement separators from haystack and
  -- required fragments before matching. A semicolon and a line break are
  -- equivalent between Lua statements; treating them differently rejected
  -- safe pretty-printed copies of the canonical helper.
  local function _normws(s) return (s:gsub("[%s;]+", "")) end

  -- Normalize executable Lua tokens while preserving string VALUES as opaque
  -- length-prefixed hex markers. A quoted or long-string decoy therefore
  -- cannot lend the surrounding helper executable syntax, while semantically
  -- equivalent single/double-quoted literals compare the same. Comments,
  -- whitespace, and optional statement separators are ignored.
  local function _token_norm(s)
    if type(Code.tokenize_lua) ~= "function" then
      return _normws(_lua_code_only_preserving_offsets(s))
    end
    local out = {}
    for _, token in ipairs(Code.tokenize_lua(tostring(s or "")) or {}) do
      if token.type == "str" then
        local value = token.text
        local chunk = load("return " .. tostring(token.text or ""),
          "=(helper string literal)", "t", {})
        if chunk then
          local ok, parsed = pcall(chunk)
          if ok and type(parsed) == "string" then value = parsed end
        end
        local hex = tostring(value or ""):gsub(".", function(ch)
          return string.format("%02x", string.byte(ch))
        end)
        out[#out + 1] = "<str:" .. tostring(#tostring(value or ""))
          .. ":" .. hex .. ">"
      elseif token.type ~= "com" and token.type ~= "ws"
          and token.text ~= ";" then
        out[#out + 1] = token.text
      end
    end
    return table.concat(out)
  end

  -- Walk a code-only span from just after a function/loop header to its
  -- matching end/until. Strings and comments have already been replaced with
  -- same-length spaces by _lua_code_only_preserving_offsets, so byte offsets
  -- map back to the original script and keyword-looking text cannot interfere.
  local function _matching_block_end(src, start_i, initial_depth)
    local depth = initial_depth or 1
    local pos = start_i
    while pos <= #src and depth > 0 do
      local s, e, word = src:find("([_%a][_%w]*)", pos)
      if not s then break end
      if word == "function" or word == "if" or word == "repeat"
         or word == "do" then
        depth = depth + 1
      elseif word == "end" or word == "until" then
        depth = depth - 1
        if depth == 0 then return e end
      end
      pos = e + 1
    end
    return nil
  end

  local code_only = _lua_code_only_preserving_offsets(lua_code)
  local violations = {}
  for name, fragments in pairs(required_fragments) do
    -- Only check helpers that are BOTH defined AND called. A pasted-
    -- but-uncalled helper is dead code -- its corruption never executes,
    -- so forcing a retry is wasted cost. Mirrors the dead-code exemption
    -- the defer-validator already has. Call-site detection: NAME(
    -- preceded by a non-identifier, non-`.` byte (so `obj.NAME(` doesn't
    -- count and we don't false-positive on field access).
    local defined, header_end
    local family_definition_count = 0
    for _ in code_only:gmatch(
        "function%s+" .. name .. "%s*%b()") do
      family_definition_count = family_definition_count + 1
    end
    for _ in (" " .. code_only):gmatch(
        "[^%w_%.]" .. name .. "%s*=%s*function%s*%b()") do
      family_definition_count = family_definition_count + 1
    end
    local definition_patterns = {
      "local%s+function%s+" .. name .. "%s*%b()",
      "function%s+" .. name .. "%s*%b()",
      "local%s+" .. name .. "%s*=%s*function%s*%b()",
      "%f[%w_]" .. name .. "%f[^%w_]%s*=%s*function%s*%b()",
    }
    for _, pattern in ipairs(definition_patterns) do
      local candidate, candidate_end = code_only:find(pattern)
      if candidate and (not defined or candidate < defined) then
        defined, header_end = candidate, candidate_end
      end
    end
    if defined and header_end then
      local function_end = _matching_block_end(code_only, header_end + 1, 1)
      local call_tail = function_end and code_only:sub(function_end + 1) or ""
      local called = (" " .. call_tail):find(
        "[^%w_%.]" .. name .. "%s*%(") ~= nil
      if called and function_end then
        local helper_source = lua_code:sub(defined, function_end)
        local helper_code = code_only:sub(defined, function_end)
        local token_hay = _token_norm(helper_source)
        local helper_hay = _normws(helper_code)
        local violations_before = #violations
        local header_args = code_only:sub(defined, header_end)
          :match("(%b())%s*$")
        if family_definition_count > 1 then
          violations[#violations+1] = {
            name = name,
            missing = "exactly one set_param_display family definition",
          }
        elseif name == "set_param_display"
           and _normws(header_args or "") ~= "(tr,fx,pidx,target)" then
          violations[#violations+1] = {
            name = name,
            missing = "local function set_param_display(tr, fx, pidx, target)",
          }
        end
        for _, frag in ipairs(fragments) do
          if #violations > violations_before then break end
          if not token_hay:find(_token_norm(frag), 1, true) then
            violations[#violations+1] = { name = name, missing = frag }
            break  -- one violation per helper is enough to trigger retry
          end
        end
        if name == "set_param_display" and #violations == violations_before then
          -- Prove the 30-step search inside its own loop: initialize [0,1],
          -- write the midpoint, read/parse the same parameter, and narrow the
          -- same bounds. A loop header with an empty/gutted body must not pass.
          local _, _, binary_iter, binary_body_start = helper_code:find(
            "for%s+([%a_][%w_]*)%s*=%s*1%s*,%s*30%s+do()")
          local binary_end = binary_body_start and _matching_block_end(
            helper_code, binary_body_start, 1)
          local binary_body = binary_end
            and helper_code:sub(binary_body_start, binary_end) or ""
          local binary_hay = _normws(binary_body)
          local mid, low, high = binary_hay:match(
            "local([%a_][%w_]*)=%(([%a_][%w_]*)%+"
              .. "([%a_][%w_]*)%)/2")
          local bounds_initialized = false
          local endpoint_low, endpoint_high
          if low and high then
            local low_init, high_init = helper_hay:match(
              "local" .. low .. "," .. high .. "="
                .. "([%+%-]?[%d%.]+[eE]?[%+%-]?%d*),"
                .. "([%+%-]?[%d%.]+[eE]?[%+%-]?%d*)")
            bounds_initialized =
              tonumber(low_init) == 0 and tonumber(high_init) == 1
            if not bounds_initialized then
              endpoint_low, endpoint_high = helper_hay:match(
                "local" .. low .. "," .. high
                  .. "=([%a_][%w_]*),([%a_][%w_]*)local")
              if endpoint_low and endpoint_high then
                local endpoint_low_init, endpoint_high_init =
                  helper_hay:match(
                    "local" .. endpoint_low .. "," .. endpoint_high .. "="
                      .. "([%+%-]?[%d%.]+[eE]?[%+%-]?%d*),"
                      .. "([%+%-]?[%d%.]+[eE]?[%+%-]?%d*)")
                bounds_initialized = tonumber(endpoint_low_init) == 0
                  and tonumber(endpoint_high_init) == 1
              end
            end
          end
          local display = mid and binary_hay:match(
            "local[%a_][%w_]*,([%a_][%w_]*)="
              .. "reaper%.TrackFX_GetFormattedParamValue%"
              .. "(tr,fx,pidx,")
          local current = display and binary_hay:match(
            "local([%a_][%w_]*)=parse%(" .. display .. "%)")
          local original = helper_hay:match(
            "local([%a_][%w_]*)="
              .. "reaper%.TrackFX_GetParamNormalized%(tr,fx,pidx%)")
          local orientation = helper_hay:match(
            "local([%a_][%w_]*)=[%a_][%w_]*>[%a_][%w_]*")
          local low_value, high_value
          if low and high then
            low_value, high_value = helper_hay:match(
              "local" .. low .. "," .. high
                .. "=[%+%-]?[%d%.]+[eE]?[%+%-]?%d*,"
                .. "[%+%-]?[%d%.]+[eE]?[%+%-]?%d*"
                .. "local([%a_][%w_]*),"
                .. "([%a_][%w_]*)=")
            if not low_value then
              local assigned_endpoint_low, assigned_endpoint_high,
                assigned_low_value, assigned_high_value =
                helper_hay:match(
                  "local" .. low .. "," .. high
                    .. "=[%+%-]?[%d%.]+[eE]?[%+%-]?%d*,"
                    .. "[%+%-]?[%d%.]+[eE]?[%+%-]?%d*"
                    .. low .. "," .. high .. "="
                    .. "([%a_][%w_]*),([%a_][%w_]*)"
                    .. "local([%a_][%w_]*),([%a_][%w_]*)=")
              if assigned_endpoint_low and assigned_endpoint_high then
                endpoint_low, endpoint_high =
                  assigned_endpoint_low, assigned_endpoint_high
                low_value, high_value =
                  assigned_low_value, assigned_high_value
              end
            end
            if not low_value and endpoint_low and endpoint_high then
              low_value, high_value = helper_hay:match(
                "local" .. low .. "," .. high .. "="
                  .. endpoint_low .. "," .. endpoint_high
                  .. "local([%a_][%w_]*),([%a_][%w_]*)=")
            end
          end
          local binary_probe = mid and binary_hay:find(
            "reaper.TrackFX_SetParamNormalized(tr,fx,pidx," .. mid .. ")",
            1, true)
          local parse_guard_start = current and select(3, binary_body:find(
            "if%s+not%s+" .. current .. "%s+then()"))
          local parse_guard_end = parse_guard_start
            and _matching_block_end(binary_body, parse_guard_start, 1)
          local parse_guard_hay = parse_guard_end
            and _normws(binary_body:sub(parse_guard_start, parse_guard_end))
            or ""
          local restore_and_fail = original
            and ("reaper.TrackFX_SetParamNormalized(tr,fx,pidx,"
              .. original .. ")returnfalse")
          local parse_guard = parse_guard_start and restore_and_fail
            and parse_guard_hay:find(restore_and_fail, 1, true)
          local descending_guard_start = current and low_value and high_value
            and select(3, binary_body:find(
              "if%s+" .. current .. "%s*>%s*" .. low_value
                .. "%s+or%s+" .. current .. "%s*<%s*" .. high_value
                .. "%s+then()"))
          local descending_guard_end = descending_guard_start
            and _matching_block_end(binary_body, descending_guard_start, 1)
          local descending_guard_hay = descending_guard_end
            and _normws(binary_body:sub(
              descending_guard_start, descending_guard_end))
            or ""
          local ascending_guard_start = current and low_value and high_value
            and select(3, binary_body:find(
              "if%s+" .. current .. "%s*<%s*" .. low_value
                .. "%s+or%s+" .. current .. "%s*>%s*" .. high_value
                .. "%s+then()"))
          local ascending_guard_end = ascending_guard_start
            and _matching_block_end(binary_body, ascending_guard_start, 1)
          local ascending_guard_hay = ascending_guard_end
            and _normws(binary_body:sub(
              ascending_guard_start, ascending_guard_end))
            or ""
          local monotonic_guards = restore_and_fail
            and descending_guard_start and ascending_guard_start
            and descending_guard_hay:find(restore_and_fail, 1, true)
            and ascending_guard_hay:find(restore_and_fail, 1, true)
          local descending_narrow = current and low and high and mid
            and low_value and high_value
            and (binary_hay:find(
              "if" .. current .. ">targetthen"
                .. low .. "," .. low_value .. "=" .. mid .. "," .. current
                .. "else" .. high .. "," .. high_value .. "="
                .. mid .. "," .. current .. "end",
              1, true)
              or binary_hay:find(
                "if" .. current .. ">targetthen"
                  .. low .. "=" .. mid .. low_value .. "=" .. current
                  .. "else" .. high .. "=" .. mid
                  .. high_value .. "=" .. current .. "end",
                1, true))
          local ascending_narrow = current and low and high and mid
            and low_value and high_value
            and (binary_hay:find(
              "if" .. current .. "<targetthen"
                .. low .. "," .. low_value .. "=" .. mid .. "," .. current
                .. "else" .. high .. "," .. high_value .. "="
                .. mid .. "," .. current .. "end",
              1, true)
              or binary_hay:find(
                "if" .. current .. "<targetthen"
                  .. low .. "=" .. mid .. low_value .. "=" .. current
                  .. "else" .. high .. "=" .. mid
                  .. high_value .. "=" .. current .. "end",
                1, true))
          local narrowing = orientation
            and binary_hay:find("if" .. orientation .. "then", 1, true)
            and descending_narrow and ascending_narrow
          local binary_ok = binary_iter and bounds_initialized
            and low and high and mid and display
            and current and binary_probe and parse_guard
            and monotonic_guards and narrowing

          -- Scope refinement checks to the -5..+5 loop. Allow its base and
          -- best-value initializer to be either a local name (`conv`) or an
          -- inline expression (`(lo + hi) / 2`), while keeping the candidate,
          -- closest-difference update, and final write linked by captured names.
          local _, _, nudge_iter, nudge_body_start = helper_code:find(
            "for%s+([%a_][%w_]*)%s*=%s*%-5%s*,%s*5%s+do()")
          local nudge_end = nudge_body_start and _matching_block_end(
            helper_code, nudge_body_start, 1)
          local nudge_body = nudge_end
            and helper_code:sub(nudge_body_start, nudge_end) or ""
          local nudge_hay = _normws(nudge_body)
          local candidate = nudge_iter and nudge_body:match(
            "local%s+([%a_][%w_]*)%s*=%s*[^\r\n;,]+%+%s*"
              .. "%(*%s*" .. nudge_iter
              .. "%s*%*%s*0%.0001%s*%)*")
          local best_value, best_diff = helper_code:match(
            "local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*"
              .. "[^\r\n;,]+%s*,%s*math%.huge")
          local best_display = best_value and best_diff
            and helper_hay:match(
              "local" .. best_value .. "," .. best_diff
                .. "=[%a_][%w_]*,math%.hugelocal([%a_][%w_]*)=")
          local refine_display = candidate and nudge_hay:match(
            "local[%a_][%w_]*,([%a_][%w_]*)="
              .. "reaper%.TrackFX_GetFormattedParamValue%"
              .. "(tr,fx,pidx,")
          local refined = refine_display and nudge_hay:match(
            "local([%a_][%w_]*)=parse%(" .. refine_display .. "%)")
          local candidate_diff = refined and nudge_hay:match(
            "local([%a_][%w_]*)=math%.abs%(" .. refined .. "%-target%)")
          local candidate_probe = candidate and nudge_hay:find(
            "reaper.TrackFX_SetParamNormalized(tr,fx,pidx," .. candidate .. ")",
            1, true)
          local candidate_bounds = candidate and nudge_hay:find(
            "if" .. candidate .. ">=0%.?0*and" .. candidate
              .. "<=1%.?0*then",
            1)
          if candidate and not candidate_bounds
              and endpoint_low and endpoint_high then
            candidate_bounds = nudge_hay:find(
              "if" .. candidate .. ">=" .. endpoint_low
                .. "and" .. candidate .. "<=" .. endpoint_high .. "then",
              1, true)
          end
          local closest_update = candidate and best_value and best_diff
            and candidate_diff
            and nudge_hay:find(
              "if" .. candidate_diff .. "<" .. best_diff .. "then",
              1, true)
            and ((nudge_hay:find(
                best_diff .. "=" .. candidate_diff, 1, true)
              and nudge_hay:find(
                best_value .. "=" .. candidate, 1, true))
              or (best_display and refine_display
                and nudge_hay:find(
                  best_diff .. "," .. best_value .. "," .. best_display
                    .. "=" .. candidate_diff .. "," .. candidate .. ","
                    .. refine_display,
                  1, true)))
          local final_best_write = best_value and helper_hay:find(
            "reaper.TrackFX_SetParamNormalized(tr,fx,pidx,"
              .. best_value .. ")",
            1, true)
          local final_display = best_value and helper_hay:match(
            "reaper%.TrackFX_SetParamNormalized%(tr,fx,pidx,"
              .. best_value .. "%)local[%a_][%w_]*,([%a_][%w_]*)="
              .. "reaper%.TrackFX_GetFormattedParamValue%(tr,fx,pidx,")
          local final_value = final_display and helper_hay:match(
            "local([%a_][%w_]*)=parse%(" .. final_display .. "%)")
          local exact_tolerance = final_value and helper_hay:match(
            "local([%a_][%w_]*)=0%.0+1")
          if final_value and not exact_tolerance then
            exact_tolerance = helper_hay:match(
              "local([%a_][%w_]*)=1[eE]%-0?9")
          end
          local final_diff = final_value and helper_hay:match(
            "local([%a_][%w_]*)=math%.abs%("
              .. final_value .. "%-target%)")
          local below = helper_code:match(
            "local%s+([%a_][%w_]*)%s*=%s*nil%s*"
              .. "if%s+[%a_][%w_]*%s*<=%s*target%s+then")
          local above = helper_code:match(
            "local%s+([%a_][%w_]*)%s*=%s*nil%s*"
              .. "if%s+[%a_][%w_]*%s*>=%s*target%s+then")
          if not below or not above then
            local paired_below, paired_above = helper_code:match(
              "local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*"
                .. "=%s*nil%s*,%s*nil")
            below = below or paired_below
            above = above or paired_above
          end
          local range_low, range_high = helper_hay:match(
            "local([%a_][%w_]*),([%a_][%w_]*)="
              .. "math%.min%([%a_][%w_]*,[%a_][%w_]*%),"
              .. "math%.max%([%a_][%w_]*,[%a_][%w_]*%)")
          local local_step = below and above and helper_hay:match(
            "local([%a_][%w_]*)=" .. below .. "and" .. above
              .. "and" .. above .. ">" .. below
              .. "and%(" .. above .. "%-" .. below .. "%)ornil")
          local max_local_step = exact_tolerance and range_low and range_high
            and helper_hay:match(
              "local([%a_][%w_]*)=math%.max%("
                .. exact_tolerance .. ",%(" .. range_high .. "%-"
                .. range_low .. "%)%*0%.1%)")
          if exact_tolerance and range_low and range_high
             and not max_local_step then
            max_local_step = helper_hay:match(
              "local([%a_][%w_]*)=math%.max%("
                .. exact_tolerance .. ",%(" .. range_high .. "%-"
                .. range_low .. "%)/10%)")
          end
          local final_branch_start
          if final_diff and exact_tolerance then
            final_branch_start = select(3, helper_code:find(
              "if%s+" .. final_diff .. "%s*>%s*" .. exact_tolerance
                .. "%s+then()"))
          end
          local final_branch_end = final_branch_start
            and _matching_block_end(helper_code, final_branch_start, 1)
          local final_branch_hay = final_branch_end
            and _normws(helper_code:sub(final_branch_start, final_branch_end))
            or ""
          local final_unreadable_guard = final_value and original
            and helper_hay:find("ifnot" .. final_value .. "then"
              .. "reaper.TrackFX_SetParamNormalized(tr,fx,pidx,"
              .. original .. ")returnfalse", 1, true)
          local final_failure = local_step and max_local_step and final_diff
            and exact_tolerance and original
            and (final_branch_hay:find(
              "ifnot" .. local_step .. "or" .. local_step .. ">"
                .. max_local_step .. "or" .. final_diff .. ">"
                .. local_step .. "/2+" .. exact_tolerance .. "then",
              1, true)
              or final_branch_hay:find(
                "ifnot" .. local_step .. "or" .. local_step .. ">"
                  .. max_local_step .. "or" .. final_diff .. ">"
                  .. local_step .. "%*0%.5%+" .. exact_tolerance .. "then",
                1))
            and final_branch_hay:find(
              "reaper.TrackFX_SetParamNormalized(tr,fx,pidx,"
                .. original .. ")returnfalse",
              1, true)
          local function assigned_once(var)
            if not var then return false end
            local count = 0
            for _ in helper_code:gmatch(
                "[^%w_]" .. var .. "%s*=%s*[^=]") do
              count = count + 1
            end
            return count == 1
          end
          local final_verified = final_value and exact_tolerance and final_diff
            and final_branch_start and final_failure
            and assigned_once(original)
            and assigned_once(exact_tolerance)
            and assigned_once(final_diff)
            and assigned_once(local_step)
            and assigned_once(max_local_step)
            and helper_hay:find("returntrue", 1, true)
          local missing
          if not binary_iter then
            missing = "30-iteration normalized binary search"
          elseif not binary_ok then
            missing = "direction-aware 30-iteration normalized binary search body"
          elseif not nudge_iter or not candidate or not candidate_probe
              or not candidate_bounds or not refine_display or not refined then
            missing = "-5 through +5 normalized refinement loop"
          elseif not best_value or not best_diff or not candidate_diff
              or not closest_update then
            missing = "closest formatted-value candidate update"
          elseif not final_best_write then
            missing = "final normalized write of the closest candidate"
          elseif not final_value or not final_unreadable_guard then
            missing = "formatted-value postcondition readback"
          elseif not final_verified then
            missing = "bounded nearest-value verification and failure restore"
          end
          if missing then
            violations[#violations+1] = { name = name, missing = missing }
          end
        end
      end
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations, function(a, b) return a.name < b.name end)
  return violations
end

-- For a hallucinated reaper.X name, return up to N real function names that
-- look similar (share a substring of >=4 chars, case-insensitive). Sorted
-- so the suggestions are stable across calls. Used by the API-validator
-- retry hint to give the model concrete candidates instead of just "you
-- got it wrong, try again."
function Code.suggest_reaper_alternatives(bad_name, max_results)
  max_results = max_results or 8
  local bad_lo = bad_name:lower()
  local needle = bad_lo:sub(1, math.min(8, #bad_lo))
  local valid = _valid_reaper_fns()
  local matches = {}
  for real in pairs(valid) do
    local real_lo = real:lower()
    -- Two-way prefix match: bad starts with real's prefix, or real starts
    -- with bad's prefix. Catches "GetProjectMarkerByIndex" -> "GetProjectMarker"
    -- (real shorter) and "GetTrack" -> "GetTrackInfo_Value" (real longer).
    if real_lo:find(needle, 1, true)
       or bad_lo:find(real_lo:sub(1, math.min(8, #real_lo)), 1, true) then
      matches[#matches+1] = real
    end
  end
  table.sort(matches)
  while #matches > max_results do matches[#matches] = nil end
  return matches
end

-- =============================================================================
-- Code.find_param_calls_outside_defer
-- =============================================================================
-- Behavioral validator for the MANDATORY DEFER RULE in
-- prompt_bundle:plugin. Generated scripts that call TrackFX/TakeFX
-- param Get/Set helpers OUTSIDE a `reaper.defer(function() ... end)`
-- block can silently fail on some VST3 plugins -- the script appears
-- to succeed (even logs "Script completed OK") but the parameters
-- never actually change. The existing API validator only checks that
-- function NAMES exist, not WHERE they're called, so this check fills
-- the gap.
--
-- Returns a sorted, deduplicated list of violating function names, or
-- nil if every param call is inside a defer scope (or the script has
-- no param calls at all).
--
-- Algorithm:
--   1. Replace line comments with same-length spaces so byte offsets
--      stay aligned with the original source while comments and strings
--      don't pollute pattern matches. This uses the same tokenizer-backed
--      sanitizer as the other Lua validators when available.
--   2. Walk the cleaned text. For each `reaper.defer(function()`
--      opening, find the matching `end)` by tracking Lua block depth
--      (function/if/repeat increment; for/while + do also increment;
--      end and until decrement). Record each defer body as a [start,
--      end] byte range.
--   3. Scan for every `reaper.<NAME>` call. If NAME is in the
--      param-touching set AND the byte position is not inside any
--      recorded defer range, flag it.
--
-- Named callbacks are valid too: `local function apply() ... end` followed by
-- `reaper.defer(apply)` executes the callback body in the deferred phase. The
-- scanner therefore recognizes a lexically earlier named callback, while a
-- direct `apply()` call remains a violation.
local _DEFER_OPEN_PAT = "reaper%.defer%s*%(%s*function%s*%(%s*%)"
local _PARAM_CALL_NAMES = {
  TrackFX_GetParam              = true,
  TrackFX_GetParamNormalized    = true,
  TrackFX_SetParam              = true,
  TrackFX_SetParamNormalized    = true,
  TrackFX_GetParamName          = true,
  TrackFX_GetNumParams          = true,
  TrackFX_GetFormattedParamValue= true,
  TakeFX_GetParam               = true,
  TakeFX_GetParamNormalized     = true,
  TakeFX_SetParam               = true,
  TakeFX_SetParamNormalized     = true,
  TakeFX_GetParamName           = true,
  TakeFX_GetNumParams           = true,
  TakeFX_GetFormattedParamValue = true,
}

local function _strip_line_comments_preserving_offsets(code)
  -- Replace comments/strings with same-length spaces so positions discovered
  -- in the cleaned text map 1:1 to the original source.
  return _lua_code_only_preserving_offsets(code)
end

-- Walk forward from `start_i` tracking Lua block depth (function/if/for/
-- while/repeat/do as opens, end/until as closes). Returns the byte index
-- one past the matching close, or nil if no matching close was found.
-- Shared by both the defer-region scan and the local-function-body scan.
local function _walk_to_matching_end(stripped, start_i, initial_depth)
  local depth = initial_depth
  local saw_loop_header = false
  local i = start_i
  while i <= #stripped and depth > 0 do
    local prev = i > 1 and stripped:sub(i-1, i-1) or ""
    local is_word_start = not prev:match("[%w_]")
    if is_word_start then
      local word = stripped:sub(i):match("^([%w_]+)")
      if word == "function" or word == "if" or word == "repeat" then
        depth = depth + 1
        saw_loop_header = false
        i = i + #word
      elseif word == "for" or word == "while" then
        saw_loop_header = true
        i = i + #word
      elseif word == "do" then
        depth = depth + 1
        saw_loop_header = false
        i = i + #word
      elseif word == "end" or word == "until" then
        depth = depth - 1
        saw_loop_header = false
        i = i + #word
      elseif word then
        i = i + #word
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  if depth == 0 then return i end
  return nil
end

local function _find_defer_regions(stripped)
  local regions = {}
  local pos = 1
  while true do
    local s, e = stripped:find(_DEFER_OPEN_PAT, pos)
    if not s then break end
    local body_start = e + 1
    local body_end_plus1 = _walk_to_matching_end(stripped, body_start, 1)
    if body_end_plus1 then
      regions[#regions+1] = { body_start, body_end_plus1 - 1 }
      pos = body_end_plus1
    else
      pos = e + 1
    end
  end
  return regions
end

-- Returns list of { name, body_start, body_end } for each simple
-- `function NAME(...) ... end` or `local function NAME(...) ... end`
-- definition in the script. Used by the defer validator
-- to recognize that helper-function bodies whose NAME is called inside a
-- defer block are transitively "deferred" -- the helper's reaper.* calls
-- only execute when the helper is invoked, and that invocation happens
-- inside defer.
local function _find_local_function_regions(stripped)
  local fns = {}
  local pos = 1
  while true do
    local s, e, name = stripped:find("%f[%w_]function%s+([%w_]+)%s*%(", pos)
    if not s then break end
    -- Skip past the parameter list to find the body start.
    local i = e
    while i <= #stripped and stripped:sub(i, i) ~= ")" do i = i + 1 end
    if i > #stripped then break end
    local params = {}
    for param in stripped:sub(e + 1, i - 1):gmatch("[%a_][%w_]*") do
      params[param] = true
    end
    i = i + 1  -- past `)`
    local body_start = i
    local body_end_plus1 = _walk_to_matching_end(stripped, body_start, 1)
    if body_end_plus1 then
      fns[#fns+1] = {
        name = name,
        def_start = s,
        body_start = body_start,
        body_end = body_end_plus1 - 1,
        params = params,
      }
      -- Advance INTO the body, not past its end. The model commonly wraps
      -- the whole script in `local function main() ... end main()` and
      -- defines helpers (set_param_display, find_param, etc.) as nested
      -- local functions inside main. Skipping past main's end would
      -- therefore miss every helper, leaving the defer validator unable
      -- to recognize their bodies as transitively in-defer when called
      -- from within reaper.defer().
      pos = body_start
    else
      pos = e + 1
    end
  end
  return fns
end

-- Normalize executable Lua tokens for exact bundled-helper comparisons.
-- Comments, whitespace, and optional statement separators are ignored. String
-- token spelling remains significant because helper error text and formatted
-- target parsing are part of the safety contract.
function Code.normalized_lua_tokens(lua_code)
  lua_code = tostring(lua_code or "")
  if type(Code.tokenize_lua) ~= "function" then
    return _lua_code_only_preserving_offsets(lua_code):gsub("[%s;]+", "")
  end
  local out = {}
  for _, token in ipairs(Code.tokenize_lua(lua_code) or {}) do
    if token.type ~= "com" and token.type ~= "ws"
       and token.text ~= ";" then
      out[#out + 1] = tostring(token.type or "") .. ":"
        .. tostring(token.text or "")
    end
  end
  return table.concat(out, "\31")
end

-- Return every exact-name parameter-helper function region in a source string.
-- The prompt bundle contains a short presentation example before the full
-- set_param_display definition, so callers select the longest canonical region.
function Code.parameter_helper_regions(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return {} end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local wanted = {
    set_param_display = true,
    set_param_enum = true,
    set_param_enum_paced = true,
  }
  local regions = {}
  for _, fn in ipairs(_find_local_function_regions(stripped)) do
    if wanted[fn.name] then
      local source = lua_code:sub(fn.def_start, fn.body_end)
      regions[fn.name] = regions[fn.name] or {}
      regions[fn.name][#regions[fn.name] + 1] = {
        name = fn.name,
        def_start = fn.def_start,
        body_start = fn.body_start,
        body_end = fn.body_end,
        source = source,
        normalized = Code.normalized_lua_tokens(source),
      }
    end
  end
  return regions
end

function Code.parameter_helper_region_is_line_isolated(lua_code, region)
  if type(lua_code) ~= "string" or type(region) ~= "table" then return false end
  local def_start = tonumber(region.def_start)
  local body_end = tonumber(region.body_end)
  if not def_start or not body_end then return false end
  local before = lua_code:sub(1, math.max(0, def_start - 1))
    :match("([^\r\n]*)$") or ""
  local after = lua_code:sub(body_end + 1):match("^([^\r\n]*)") or ""
  local prefix_isolated = before:match("^%s*$") ~= nil
    or before:match("^%s*local%s+$") ~= nil
  return prefix_isolated and after:match("^%s*$") ~= nil
end

function Code.canonical_parameter_helper_tokens()
  local content = nil
  if type(CTX) == "table" and type(CTX.prompt_bundle) == "function" then
    content = select(1, CTX.prompt_bundle("plugin_helpers"))
  end
  if (type(content) ~= "string" or content == "")
     and type(S) == "table" and type(S.prompt_bundle_cache) == "table" then
    content = S.prompt_bundle_cache.plugin_helpers
  end
  if type(content) ~= "string" or content == "" then return {} end

  local canonical = {}
  for name, candidates in pairs(Code.parameter_helper_regions(content)) do
    local longest = nil
    for _, candidate in ipairs(candidates) do
      if not longest or #candidate.normalized > #longest.normalized then
        longest = candidate
      end
    end
    if longest then canonical[name] = longest.normalized end
  end
  return canonical
end

-- Classify every generated TrackFX/TakeFX parameter setter source line.
-- Runtime enforcement uses this map at the sandbox setter boundary. The static
-- response and manual-run gates use the findings list to reject direct generic
-- writes before generated code starts.
function Code.parameter_write_authorization_map(lua_code, profile_receipts)
  if type(lua_code) ~= "string" or lua_code == "" then return {}, nil end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local canonical = Code.canonical_parameter_helper_tokens()
  local helper_regions = Code.parameter_helper_regions(lua_code)
  local helper_bad = {}
  for _, finding in ipairs(
      Code.find_helper_integrity_violations(lua_code) or {}) do
    helper_bad[tostring(finding.name or "")] = true
  end

  local verified_helpers = {}
  for name, candidates in pairs(helper_regions) do
    if #candidates == 1 and canonical[name]
       and candidates[1].normalized == canonical[name]
       and Code.parameter_helper_region_is_line_isolated(
         lua_code, candidates[1])
       and not helper_bad[name] then
      verified_helpers[#verified_helpers + 1] = candidates[1]
    end
  end

  local profile_active =
    (profile_receipts == true)
    or (type(profile_receipts) == "table" and #profile_receipts > 0)
  local profile_safe = false
  local resolver_vars = {}
  if profile_active
     and type(Code.find_unguarded_profile_param_writes) == "function" then
    profile_safe =
      Code.find_unguarded_profile_param_writes(lua_code) == nil
    if profile_safe then
      for _, binding in ipairs(
          Code.profile_resolver_spec_bindings(lua_code) or {}) do
        if binding.mapped_var then
          resolver_vars[binding.mapped_var] = true
        end
      end
    end
  end

  local all_functions = _find_local_function_regions(stripped)
  local authorization = {}
  local findings = {}
  local finding_lines = {}
  local setter_names = {
    "TrackFX_SetParamNormalized",
    "TrackFX_SetParam",
    "TakeFX_SetParamNormalized",
    "TakeFX_SetParam",
  }

  for _, api_name in ipairs(setter_names) do
    local search_pos = 1
    while true do
      local call_start, call_open = stripped:find(
        "reaper%." .. api_name .. "%s*%(", search_pos)
      if not call_start then break end
      local args, call_close =
        Code._parse_lua_call_args(stripped, call_open)
      local line = Code._lua_line_for_pos(stripped, call_start)
      local helper_name = nil
      for _, region in ipairs(verified_helpers) do
        if call_start >= region.body_start
           and call_start <= region.body_end then
          helper_name = region.name
          break
        end
      end

      local classification = nil
      if helper_name then
        classification = {
          kind = "canonical_helper",
          helper = helper_name,
        }
      elseif profile_safe and api_name:find("^TrackFX_") then
        local index_expr = args and Code._lua_trim_expr(args[3]) or ""
        index_expr = index_expr:gsub("%s+", "")
        local mapped_var = index_expr:match(
          "^([%a_][%w_]*)%[%d+%]$")
        if mapped_var and resolver_vars[mapped_var] then
          classification = { kind = "profile_resolver" }
        else
          for _, fn in ipairs(all_functions) do
            if call_start >= fn.body_start and call_start <= fn.body_end then
              classification = {
                kind = "profile_wrapper",
                helper = fn.name,
              }
              break
            end
          end
        end
      end

      if classification then
        authorization[line] = classification
      else
        finding_lines[line] = true
        findings[#findings + 1] = {
          api = api_name,
          line = line,
          kind = "generic_raw",
        }
      end
      search_pos = (call_close or call_open) + 1
    end
  end

  for line in pairs(finding_lines) do authorization[line] = nil end
  if #findings == 0 then return authorization, nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.api < b.api
  end)
  return authorization, findings
end

function Code.find_param_calls_outside_defer(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = _strip_line_comments_preserving_offsets(lua_code)
  local regions  = _find_defer_regions(stripped)

  -- Expand regions to include local-function bodies whose name is called
  -- inside any current "in-defer" region. The conventional script shape
  -- defines helpers (set_param_display, find_param, custom nil-safe
  -- wrappers like setp) at the script top OR inside main()'s body BEFORE
  -- the reaper.defer block, then CALLS them from inside defer. The
  -- reaper.* calls inside the helper's source body don't execute when
  -- the helper is defined; they only execute when the helper is invoked
  -- (which is inside defer). Without this expansion, the validator
  -- false-positive-flags every helper-internal SetParamNormalized call
  -- and blocks auto-run on perfectly-correct scripts. Iterative pass
  -- handles transitivity (helper A calls helper B, A is called from
  -- defer -> B is also "in defer").
  local fns = _find_local_function_regions(stripped)
  local function _local_call_positions(fn_name)
    local positions = {}
    local ps = 1
    while true do
      local cs, ce = stripped:find(fn_name .. "%s*%(", ps)
      if not cs then break end
      local prev = cs > 1 and stripped:sub(cs - 1, cs - 1) or ""
      if not prev:match("[%w_%.:]") then
        positions[#positions + 1] = cs
      end
      ps = ce + 1
    end
    return positions
  end

  local function _local_token_positions(fn_name)
    local positions = {}
    local ps = 1
    while true do
      local cs, ce = stripped:find(fn_name, ps, true)
      if not cs then break end
      local prev = cs > 1 and stripped:sub(cs - 1, cs - 1) or ""
      local next_ch = ce < #stripped and stripped:sub(ce + 1, ce + 1) or ""
      if not prev:match("[%w_%.:]") and not next_ch:match("[%w_]") then
        positions[#positions + 1] = cs
      end
      ps = ce + 1
    end
    return positions
  end

  local function _name_called_in_regions(fn_name, regs)
    for _, cs in ipairs(_local_call_positions(fn_name)) do
      for _, r in ipairs(regs) do
        if cs >= r[1] and cs <= r[2] then return true end
      end
    end
    return false
  end

  local function _name_passed_directly_to_defer(fn)
    local ps = 1
    while true do
      local cs, ce, callback = stripped:find(
        "reaper%.defer%s*%(%s*([%a_][%w_]*)%s*%)", ps)
      if not cs then break end
      if callback == fn.name and fn.def_start < cs then return true end
      ps = ce + 1
    end
    return false
  end

  local known_in_defer = {}
  for _, fn in ipairs(fns) do
    if _name_passed_directly_to_defer(fn) then
      regions[#regions+1] = { fn.body_start, fn.body_end }
      known_in_defer[fn] = true
    end
  end
  local added = true
  while added do
    added = false
    for _, fn in ipairs(fns) do
      if not known_in_defer[fn]
         and _name_called_in_regions(fn.name, regions) then
        regions[#regions+1] = { fn.body_start, fn.body_end }
        known_in_defer[fn] = true
        added = true
      end
    end
  end

  -- Dead-code exemption: a local function whose name has no call sites
  -- OUTSIDE its own def header + body is unreachable -- its reaper.* calls
  -- never execute, so don't flag them. This catches the common case of
  -- the model pasting a helper (e.g. set_param_display) "just in case"
  -- without actually invoking it. Limited to one-level reachability:
  -- helpers called only by other dead helpers are still flagged. Acceptable
  -- because that pattern is rare and erring on the side of flagging keeps
  -- the validator's primary purpose intact (catch real defer violations
  -- like `local function apply() ... end; apply()` outside defer).
  for _, fn in ipairs(fns) do
    if not known_in_defer[fn] then
      local has_external = false
      for _, cs in ipairs(_local_call_positions(fn.name)) do
        if cs < fn.def_start or cs > fn.body_end then
          has_external = true
          break
        end
      end
      if not has_external then
        -- `pcall(main)`, `xpcall(main, ...)`, or assigning/passing a local
        -- function as a callback still makes that function reachable even
        -- though it is not written as `main(...)`. Treat any out-of-body
        -- token reference as reachable so wrapper mains don't mask nested
        -- helper-param calls from the defer validator.
        for _, cs in ipairs(_local_token_positions(fn.name)) do
          if cs < fn.def_start or cs > fn.body_end then
            has_external = true
            break
          end
        end
      end
      if not has_external then
        regions[#regions+1] = { fn.body_start, fn.body_end }
      end
    end
  end

  local violations = {}
  local seen = {}
  local s = 1
  while true do
    local hs, he, name = stripped:find("reaper%.([%w_]+)", s)
    if not hs then break end
    if _PARAM_CALL_NAMES[name] then
      local in_defer = false
      for _, r in ipairs(regions) do
        if hs >= r[1] and hs <= r[2] then in_defer = true; break end
      end
      if not in_defer and not seen[name] then
        seen[name] = true
        violations[#violations+1] = name
      end
    end
    s = he + 1
  end
  if #violations == 0 then return nil end
  table.sort(violations)
  return violations
end

-- =============================================================================
-- Code.find_helper_calls_without_definition
-- =============================================================================
-- Behavioral validator for helper calls that will compile as global lookups.
-- The main target is the prompt_bundle:plugin_helpers contract: helpers
-- (find_param, set_param_display, set_param_enum, set_param_enum_paced) are
-- LOCAL FUNCTIONS, not REAPER built-ins. The model can write calls from memory
-- without including the function source, producing a runtime `attempt to call
-- a nil value` crash. Lower-tier models also invent ad-hoc helpers such as
-- set_vol_for_send and forget to define them. Catch both shapes before auto-run.
--
-- Returns a sorted, deduplicated list of helper names that are CALLED but
-- not DEFINED in the same script, or nil if every called helper has a
-- matching `local function NAME(` definition.
local _HELPER_NAMES = {
  find_param           = true,
  set_param_display    = true,
  set_param_enum       = true,
  set_param_enum_paced = true,
}

local _HELPER_CALL_ALLOWED_GLOBALS = {
  assert = true, collectgarbage = true, error = true, getmetatable = true,
  ipairs = true, next = true, pairs = true, pcall = true, print = true,
  reaassist_resolve_profile_params = true,
  rawequal = true, rawget = true, rawlen = true, rawset = true,
  select = true, setmetatable = true, tonumber = true, tostring = true,
  type = true, xpcall = true,
}

function Code.find_helper_calls_without_definition(lua_code)
  if not lua_code or lua_code == "" then return nil end
  -- Blank strings/comments preserving offsets so positions remain consistent
  -- with the rest of the validator pass.
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  -- For each helper name, find the earliest definition position and the
  -- earliest call position. Two failure modes both produce the same
  -- runtime crash ("attempt to call a nil value"); both treated as
  -- violations so the retry hint covers them uniformly:
  --
  --   1. NO definition anywhere -- model called the helper without
  --      including its source.
  --   2. Definition exists but is LEXICALLY AFTER the first call site.
  --      Common when the model writes main() first and helper functions
  --      below: when Lua compiles main()'s body, the helper's `local`
  --      slot doesn't exist yet at that source position, so the call
  --      compiles as a global (_ENV) lookup and crashes at runtime
  --      inside the deferred callback. Confirmed reproducible against
  --      Lua 5.4 with the exact pattern observed in a debug log.
  --
  -- Definition forms accepted:
  --   `local function NAME(`        -- standard form the bundle uses
  --   `function NAME(`              -- bare (no local; less safe but valid)
  --   `local NAME = function`       -- assignment form
  --   `NAME = function` (mid-line)  -- bare assignment (creates global)
  --
  -- The definition-before-call check uses START position of the def
  -- match. For a `local function NAME(` site, that's the 'l' of "local",
  -- which is always BEFORE the call-pattern's match (the space inside
  -- "function NAME(" that satisfies [^%w_%.]). So def-site false-call-
  -- matches don't trigger out-of-order -- they compare def_pos < their
  -- own call_pos.
  local violations, seen = {}, {}
  local names_to_check = {}
  local function_regions = _find_local_function_regions(stripped)
  for name in pairs(_HELPER_NAMES) do names_to_check[name] = true end

  local function remember_candidate(name)
    name = tostring(name or "")
    if name == "" or _HELPER_CALL_ALLOWED_GLOBALS[name] then return end
    if name:find("^reaper$") or name:find("^gfx$") then return end
    local lname = name:lower()
    if name ~= lname then return end
    if name:find("_", 1, true) then
      names_to_check[name] = true
    end
  end

  for name in stripped:gmatch("[^%w_%.]([%a_][%w_]*)%s*%(") do
    remember_candidate(name)
  end
  local leading = stripped:match("^%s*([%a_][%w_]*)%s*%(")
  remember_candidate(leading)

  for name in pairs(names_to_check) do
    local def_pos = nil
    local function _take_min(pat)
      local sp = stripped:find(pat)
      if sp and (not def_pos or sp < def_pos) then def_pos = sp end
    end
    _take_min("local%s+function%s+" .. name .. "%s*%(")
    _take_min("[^%w_]function%s+" .. name .. "%s*%(")
    _take_min("^function%s+" .. name .. "%s*%(")
    _take_min("local%s+" .. name .. "%s*=%s*function")
    _take_min("[^%w_]" .. name .. "%s*=%s*function")
    local function call_is_function_parameter(call_pos)
      for _, region in ipairs(function_regions) do
        if call_pos >= region.body_start and call_pos <= region.body_end
           and region.params and region.params[name] then
          return true
        end
      end
      return false
    end
    -- Check every call site so a valid callback invocation inside its
    -- declaring function cannot hide a same-named global call elsewhere.
    local call_positions = {}
    local scan_pos = 1
    while true do
      local call_start, call_end = stripped:find(
        "[^%w_%.]" .. name .. "%s*%(", scan_pos)
      if not call_start then break end
      call_positions[#call_positions + 1] = call_start
      scan_pos = call_end + 1
    end
    if stripped:find("^" .. name .. "%s*%(") then
      call_positions[#call_positions + 1] = 1
    end
    for _, call_pos in ipairs(call_positions) do
      if not seen[name] and not call_is_function_parameter(call_pos)
         and (not def_pos or def_pos > call_pos) then
        seen[name] = true
        violations[#violations+1] = name
      end
    end
  end
  if #violations == 0 then return nil end
  table.sort(violations)
  return violations
end

-- =============================================================================
-- Code.prompt_has_param_write_intent
-- =============================================================================
-- Returns true if the user's prompt looks like a request to WRITE plugin
-- parameter values (vs. a pure-read query like "what is X set to?").
-- Used by the dispatcher to gate the plugin_helpers co-pin on fx_params
-- and preferred_plugins paths -- pure reads don't need helpers; writes do.
--
-- Two-signal detection: a write verb AND a value-shape pattern. Either
-- signal alone is too weak (a mention of "set" without a value, or a
-- value pattern without a write verb, are both weak signals). Conjunction
-- catches the high-signal cases without spamming co-pin on weak prompts.
local _WRITE_VERBS = {
  "set", "change", "configure", "adjust", "make", "turn",
  "add", "insert", "load", "put",
  "boost", "cut", "raise", "lower", "lift", "drop", "tune",
  "tweak", "dial", "increase", "decrease", "shift", "move",
  "bump", "nudge", "trim", "apply",
  "boosts", "cuts", "raises", "lowers", "lifts", "drops",
  "tweaks", "dials", "increases", "decreases", "bumps", "nudges",
  "trims", "applies",
}
-- Value-shape patterns: number followed by a unit, or a colon-separated
-- ratio. Lua patterns; %d is digit, %s is whitespace.
local _VALUE_PATTERNS = {
  "%d+%s*[dD][bB]",         -- 6 dB, 6dB, 6 DB
  "%d+%s*[hH][zZ]",         -- 100 Hz, 100hz
  "%d+%s*[kK][hH][zZ]",     -- 5 kHz
  "%d+%s*[kK]%f[%W]",        -- 5k, 4 k
  "%d+%s*ms",               -- 50 ms
  "%d+%s*sec",              -- 2 sec
  "%d+%s*%%",               -- 65%
  "%d+%s*[cC][eE][nN][tT]", -- 50 cents, 50 cent
  "%d+%s*[sS][eE][mM][iI]", -- 12 semitones
  "%d+:%d+",                -- 4:1, 10:1
  "%d+%.%d+",               -- 0.75, 1.5 (bare decimal -- looks intentional)
  "[Qq]%s*=%s*%d",          -- Q=2, Q = 1.5
  "[Qq]%s+of%s+%d",         -- Q of 2
}

function Code.prompt_has_open_ended_param_write_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = text:lower()
  local has_eq =
       lo:find("%f[%w]eq%f[%W]") ~= nil
    or lo:find("%f[%w]equaliz") ~= nil
    or lo:find("%f[%w]filter%f[%W]") ~= nil
  if not has_eq then return false end

  local open_ended =
       lo:find("%f[%w]generic%f[%W]") ~= nil
    or lo:find("%f[%w]general%f[%W]") ~= nil
    or lo:find("%f[%w]recommended%f[%W]") ~= nil
    or lo:find("%f[%w]tasteful%f[%W]") ~= nil
    or lo:find("%f[%w]good%f[%W]") ~= nil
    or lo:find("%f[%w]starter%f[%W]") ~= nil
    or lo:find("%f[%w]appropriate%f[%W]") ~= nil
    or lo:find("type%-appropriate", 1, false) ~= nil
    or lo:find("type%s+appropriate") ~= nil
    or lo:find("respective%s+to%s+the%s+type") ~= nil
  local settings_word =
       lo:find("%f[%w]settings?%f[%W]") ~= nil
    or lo:find("%f[%w]treatment%f[%W]") ~= nil
    or lo:find("%f[%w]recipe%f[%W]") ~= nil
  local apply_word = lo:find("%f[%w]apply%f[%W]") ~= nil

  local source_type =
       lo:find("%f[%w]vox%f[%W]") ~= nil
    or lo:find("%f[%w]vocal") ~= nil
    or lo:find("%f[%w]guitar") ~= nil
    or lo:find("%f[%w]kick") ~= nil
    or lo:find("%f[%w]snare") ~= nil
    or lo:find("%f[%w]bass%f[%W]") ~= nil
    or lo:find("%f[%w]drum") ~= nil
  if open_ended and settings_word then return true end
  if apply_word and settings_word and source_type then return true end
  if source_type and open_ended then return true end

  return false
end

-- A plugin add can also carry a non-numeric musical configuration, for
-- example `add AutoTune FX set to Bb minor`. Keep this narrower than the
-- generic named-value detector: require explicit plugin/effect context, a
-- configuration relation, and an adjacent musical key + scale pair. That
-- prevents prose such as "fix a minor issue" from disabling the add-only
-- path while ensuring a requested key/scale write is never stripped.
function Code.prompt_has_plugin_musical_config_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  local has_plugin =
       lo:find("%f[%w]fx%f[%W]") ~= nil
    or lo:find("%f[%w]plugin%f[%W]") ~= nil
    or lo:find("%f[%w]effect%f[%W]") ~= nil
    or lo:find("autotune", 1, true) ~= nil
    or lo:find("auto%s*tune") ~= nil
    or lo:find("pitch%s+correction") ~= nil
  if not has_plugin then return false end

  local has_config_relation =
       lo:find("%f[%w]set%f[%W]") ~= nil
    or lo:find("%f[%w]configure%f[%W]") ~= nil
    or lo:find("%f[%w]configured%f[%W]") ~= nil
    or lo:find("%f[%w]change%f[%W]") ~= nil
    or lo:find("%f[%w]adjust%f[%W]") ~= nil
    or lo:find("%f[%w]tune%f[%W]") ~= nil
    or lo:find("%f[%w]key%s+of%f[%W]") ~= nil
  if not has_config_relation then return false end

  local words = {}
  for word in lo:gmatch("[%a#]+") do words[#words + 1] = word end
  local note_tokens = {
    a=true, ["a#"]=true, ab=true,
    b=true, ["b#"]=true, bb=true,
    c=true, ["c#"]=true, cb=true,
    d=true, ["d#"]=true, db=true,
    e=true, ["e#"]=true, eb=true,
    f=true, ["f#"]=true, fb=true,
    g=true, ["g#"]=true, gb=true,
  }
  for i, word in ipairs(words) do
    if word == "major" or word == "minor" or word == "chromatic" then
      for j = math.max(1, i - 3), i - 1 do
        if note_tokens[words[j]]
           or (j < i - 1
             and words[j]:match("^[a-g]$")
             and (words[j + 1] == "sharp" or words[j + 1] == "flat")) then
          return true
        end
      end
    end
  end
  return false
end

-- A named musical key/scale request (for example "set Auto-Tune to D minor")
-- cannot safely derive the scale from a raw normalized literal unless the
-- entire selector mapping is independently verified. Long selectors are often
-- sampled/partial, and the exact observed failure mapped a guessed 1.0 to
-- HARMONIC instead of MINOR. Require an executable enum-matching helper call
-- whenever such a request also emits direct FX parameter writes.
function Code.find_musical_enum_guess_violations(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == ""
     or not Code.prompt_has_plugin_musical_config_intent(user_text) then
    return nil
  end
  local stripped = _lua_code_only_preserving_offsets(lua_code)

  local function has_helper_call(name)
    local pos = 1
    while true do
      local first, last = stripped:find(
        "%f[%w_]" .. name .. "%s*%(", pos)
      if not first then return false end
      local before = stripped:sub(math.max(1, first - 32), first - 1)
      if not before:match("function%s+$") then return true end
      pos = last + 1
    end
  end

  if has_helper_call("set_param_enum")
     or has_helper_call("set_param_enum_paced") then
    return nil
  end

  local findings = {}
  for _, api_name in ipairs({
    "TrackFX_SetParamNormalized", "TrackFX_SetParam",
    "TakeFX_SetParamNormalized", "TakeFX_SetParam",
  }) do
    local pos = 1
    while true do
      local first, last = stripped:find(
        "reaper%." .. api_name .. "%s*%(", pos)
      if not first then break end
      findings[#findings + 1] = {
        api = api_name,
        line = Code._lua_line_for_pos(stripped, first),
      }
      pos = last + 1
    end
  end
  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.api < b.api
  end)
  return findings
end

-- Bare integers are intentionally excluded from the broad numeric write
-- detector because track numbers, years, tempos, and counts are common. This
-- signal is for an already-established plugin workflow only (the caller owns
-- that state gate), and therefore requires an explicit plugin-parameter noun.
function Code.prompt_has_plugin_param_bare_integer_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  local has_write =
       lo:find("%f[%w]set%f[%W]") ~= nil
    or lo:find("%f[%w]change%f[%W]") ~= nil
    or lo:find("%f[%w]adjust%f[%W]") ~= nil
    or lo:find("%f[%w]make%f[%W]") ~= nil
    or lo:find("%f[%w]turn%f[%W]") ~= nil
    or lo:find("%f[%w]dial%f[%W]") ~= nil
    or lo:find("%f[%w]put%f[%W]") ~= nil
  if not has_write or not lo:find("%f[%d]%d+%f[%D]") then return false end

  if lo:find("%f[%w]retun") and lo:find("%f[%w]speed%f[%W]") then
    return true
  end
  if lo:find("pitch%s+correction%s+speed") then return true end
  local plugin_params = {
    attack=true, release=true, threshold=true, ratio=true, knee=true,
    feedback=true, drive=true, mix=true, cutoff=true, resonance=true,
    lookahead=true, hold=true, decay=true, oversampling=true,
  }
  for word in lo:gmatch("[%a]+") do
    if plugin_params[word] then return true end
  end
  return false
end

function Code.prompt_has_param_write_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  if Code.prompt_has_open_ended_param_write_intent(lo) then return true end
  if Code.prompt_has_plugin_musical_config_intent(lo) then return true end
  -- Verb scan with word-boundary frontier so "settle" doesn't match "set".
  local has_verb = false
  for _, v in ipairs(_WRITE_VERBS) do
    if lo:find("%f[%w]" .. v .. "%f[%W]") then has_verb = true; break end
  end
  if not has_verb then return false end
  -- Value-shape scan.
  for _, pat in ipairs(_VALUE_PATTERNS) do
    if lo:find(pat) then return true end
  end
  return false
end

-- Detect named/enum/qualitative plugin-parameter targets that the numeric
-- write-intent predicate above intentionally does not classify. This stays
-- separate from prompt_has_param_write_intent because that broader predicate
-- controls helper pre-pinning; this narrower signal only prevents an add-only
-- response from hiding a requested plugin-parameter write.
function Code.prompt_requests_named_param_value(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  local words = {}
  for word in lo:gmatch("[%a%d]+") do words[#words+1] = word end
  if #words == 0 then return false end

  local effect_words = {
    plugin=true, fx=true, effect=true, compressor=true, compression=true,
    eq=true, equalizer=true, filter=true, delay=true, reverb=true, gate=true,
    limiter=true, deesser=true, saturator=true, saturation=true,
    reaeq=true, reacomp=true, readelay=true, reaverbate=true, reagate=true,
    realimit=true, fabfilter=true,
  }
  local has_effect =
       lo:find("pro%-q") ~= nil or lo:find("pro%s+q") ~= nil
    or lo:find("pro%-c") ~= nil or lo:find("pro%s+c") ~= nil
    or lo:find("pro%-l") ~= nil or lo:find("pro%s+l") ~= nil
    or lo:find("pro%-r") ~= nil or lo:find("pro%s+r") ~= nil
    or lo:find("pro%-g") ~= nil or lo:find("pro%s+g") ~= nil
    or lo:find("pro%-mb") ~= nil or lo:find("pro%s+mb") ~= nil
    or lo:find("%f[%w]saturn%f[%W]") ~= nil
    or lo:find("%f[%w]timeless%f[%W]") ~= nil
    or lo:find("%f[%w]volcano%f[%W]") ~= nil
    or lo:find("%f[%w]twin%f[%W]") ~= nil
  for _, word in ipairs(words) do
    if effect_words[word] then has_effect = true; break end
  end
  if not has_effect then return false end

  local write_words = {
    set=true, change=true, switch=true, turn=true, configure=true, adjust=true,
    choose=true, select=true, make=true, use=true, apply=true, clean=true,
  }
  local param_words = {
    style=true, shape=true, type=true, mode=true, curve=true, slope=true,
    band=true, ratio=true, threshold=true, attack=true, release=true,
    knee=true, gain=true, frequency=true, freq=true, q=true, mix=true,
    drive=true, character=true, algorithm=true, detector=true, range=true,
    lookahead=true, hold=true, decay=true, feedback=true, width=true,
    oversampling=true, quality=true, phase=true, order=true, wet=true,
    dry=true, bypass=true, cutoff=true, resonance=true,
  }
  local named_modes = {
    opto=true, vocal=true, clean=true, classic=true, modern=true,
    transparent=true, mastering=true, pumping=true, punch=true,
  }
  local tone_words = {
    punchy=true, warm=true, warmer=true, dark=true, darker=true,
    bright=true, brighter=true, aggressive=true, gentle=true,
    gently=true, natural=true, controlled=true, even=true, squashed=true,
    transparent=true, smooth=true, smoother=true, airy=true, crisp=true,
    tight=true, softer=true, soft=true, subtle=true, tasteful=true,
    muddy=true, mud=true, boxy=true, boxiness=true, harsh=true,
    harshness=true, rumble=true, thin=true, open=true,
  }
  local pronoun_subjects = { it=true, its=true }
  local property_words = {
    color=true, colour=true, name=true, icon=true, height=true,
  }

  local function has_word_in_range(set, first, last)
    first = math.max(1, first)
    last = math.min(#words, last)
    for i = first, last do
      if set[words[i]] then return true end
    end
    return false
  end

  -- Named target tied to an explicit plugin-parameter noun, for example
  -- "set only its Style to Vocal" or "set band 1 shape to Low Cut".
  for i, word in ipairs(words) do
    if param_words[word] and has_word_in_range(write_words, i - 6, i + 1) then
      local has_relation = false
      for j = i + 1, math.min(#words, i + 5) do
        if words[j] == "to" or words[j] == "as" then
          has_relation = true
          break
        end
      end
      if has_relation
         or has_word_in_range(named_modes, i + 1, i + 5)
         or has_word_in_range(tone_words, i + 1, i + 5) then
        return true
      end
    end
  end

  -- Pronoun-only named mode, for example "switch it to Opto" after naming
  -- the plugin elsewhere in the request.
  for i, word in ipairs(words) do
    if write_words[word] then
      local relation
      for j = i + 1, math.min(#words, i + 4) do
        if words[j] == "to" or words[j] == "as" then relation = j; break end
      end
      if relation then
        if has_word_in_range(named_modes, relation + 1, relation + 3) then
          return true
        end
        local a, b = words[relation + 1], words[relation + 2]
        if (a == "low" or a == "high")
           and (b == "cut" or b == "shelf" or b == "pass") then
          return true
        end
      end
    end
  end

  -- Qualitative plugin treatment where no literal parameter name is given.
  -- Require a nearby effect/pronoun subject so track-color adjectives do not
  -- turn an otherwise add-only request into a parameter-write request.
  for i, word in ipairs(words) do
    if tone_words[word] and has_word_in_range(write_words, i - 6, i - 1) then
      local write_idx
      for j = i - 1, math.max(1, i - 6), -1 do
        if write_words[words[j]] then write_idx = j; break end
      end
      local property_target = write_idx
        and has_word_in_range(property_words, write_idx + 1, i + 4)
      if not property_target
         and (has_word_in_range(effect_words, i - 5, i - 1)
           or has_word_in_range(pronoun_subjects, i - 5, i - 1)
           or has_effect) then
        return true
      end
    end
  end
  if lo:find("%f[%w]roll%s+off%f[%W]")
     or lo:find("%f[%w]tame%s+the%s+[%w]+") then
    return true
  end
  return false
end

function Code.prompt_has_chain_or_recipe_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = Code._localized_action_intent_text(text)
  local has_delay =
    lo:find("%f[%w]delay%f[%W]") ~= nil
    or lo:find("%f[%w]echo%f[%W]") ~= nil
  local delay_recipe =
    has_delay
    and (
      lo:find("%f[%w]slap%f[%W]") ~= nil
      or lo:find("%f[%w]slapback%f[%W]") ~= nil
      or lo:find("%f[%w]ping%s*pong%f[%W]") ~= nil
    )
  return lo:find("%f[%w]chain%f[%W]") ~= nil
    or lo:find("%f[%w]recipe%f[%W]") ~= nil
    or lo:find("%f[%w]preset%f[%W]") ~= nil
    or lo:find("%f[%w]tone%f[%W]") ~= nil
    or lo:find("%f[%w]sound%s+like%f[%W]") ~= nil
    or lo:find("%f[%w]vibe%f[%W]") ~= nil
    or delay_recipe
end

function Code.prompt_has_midi_workflow_intent(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = text:lower()
  local has_explicit_midi =
       lo == "midi"
    or lo:match("^midi[^%a]") ~= nil
    or lo:match("[^%a]midi$") ~= nil
    or lo:match("[^%a]midi[^%a]") ~= nil
  if has_explicit_midi then return true end
  if Code.prompt_implies_midi_generation
     and Code.prompt_implies_midi_generation(lo) then
    return true
  end
  local has_note_word =
       lo:find("%f[%w]note") ~= nil
    or lo:find("%f[%w]nota") ~= nil
    or lo:find("%f[%w]noten") ~= nil
    or lo:find("%f[%w]notlar") ~= nil
    or lo:find("%f[%w]pitch%s+%d") ~= nil
    or lo:find("%f[%w]pitches%f[%W]") ~= nil
    or lo:find("%f[%w]triad") ~= nil
    or lo:find("%f[%w]chord") ~= nil
  if not has_note_word then return false end
  return lo:find("%f[%w]melod") ~= nil
    or lo:find("%f[%w]bass%f[%W]") ~= nil
    or lo:find("%f[%w]basso") ~= nil
    or lo:find("%f[%w]basse") ~= nil
    or lo:find("%f[%w]bajo") ~= nil
    or lo:find("%f[%w]baixo") ~= nil
    or lo:find("%f[%w]bas%f[%W]") ~= nil
    or lo:find("%f[%w]harmony%f[%W]") ~= nil
    or lo:find("%f[%w]harmon") ~= nil
    or lo:find("%f[%w]countermelody%f[%W]") ~= nil
    or lo:find("%f[%w]part") ~= nil
end

function Code.lua_uses_only_midi_ref_covered_calls(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return false end
  local allowed = {
    CountTracks = true,
    GetTrack = true,
    GetTrackName = true,
    GetCursorPosition = true,
    CSurf_TrackToID = true,
    InsertTrackAtIndex = true,
    GetSetMediaTrackInfo_String = true,
    GetMediaTrackInfo_Value = true,
    SetMediaTrackInfo_Value = true,
    SetOnlyTrackSelected = true,
    SetTrackSelected = true,
    CountTrackMediaItems = true,
    GetTrackMediaItem = true,
    GetActiveTake = true,
    GetMediaItemTake = true,
    GetMediaItemTake_Item = true,
    GetMediaItemInfo_Value = true,
    SetMediaItemInfo_Value = true,
    SetMediaItemSelected = true,
    GetSetMediaItemTakeInfo_String = true,
    CreateNewMIDIItemInProj = true,
    TakeIsMIDI = true,
    MIDI_CountEvts = true,
    MIDI_GetNote = true,
    MIDI_GetCC = true,
    MIDI_InsertNote = true,
    MIDI_InsertCC = true,
    MIDI_SetNote = true,
    MIDI_SetCC = true,
    MIDI_DeleteNote = true,
    MIDI_DeleteCC = true,
    MIDI_SelectAll = true,
    MIDI_DisableSort = true,
    MIDI_Sort = true,
    MIDI_GetGrid = true,
    MIDI_GetPPQPos_StartOfMeasure = true,
    MIDI_GetPPQPos_EndOfMeasure = true,
    MIDI_GetPPQPosFromProjTime = true,
    MIDI_GetProjTimeFromPPQPos = true,
    MIDI_GetProjQNFromPPQPos = true,
    MIDI_GetPPQPosFromProjQN = true,
    TimeMap2_timeToQN = true,
    TimeMap2_QNToTime = true,
    TimeMap2_timeToBeats = true,
    TimeMap2_beatsToTime = true,
    MIDIEditor_GetActive = true,
    MIDIEditor_GetTake = true,
    SetCurrentBPM = true,
    MarkTrackItemsDirty = true,
    UpdateItemInProject = true,
    Undo_BeginBlock = true,
    Undo_EndBlock = true,
    PreventUIRefresh = true,
    UpdateArrange = true,
    ShowMessageBox = true,
  }
  local saw_call = false
  for name in lua_code:gmatch("reaper%.([%w_]+)") do
    saw_call = true
    if not allowed[name] then return false end
  end
  return saw_call
end

function Code.prompt_is_fx_add_only(text)
  if type(text) ~= "string" or text == "" then return false end
  if Code.prompt_has_param_write_intent(text)
     or Code.prompt_requests_named_param_value(text)
     or Code.prompt_has_chain_or_recipe_intent(text)
     or Code.prompt_targets_existing_fx(text) then
    return false
  end
  local lo = text:lower()
  if lo:find("%f[%w]sidechain%f[%W]")
     or lo:find("%f[%w]ducking%f[%W]")
     or lo:find("%f[%w]duck%f[%W]") then
    return false
  end
  -- Negative guardrails such as "do not touch other tracks or add other
  -- effects" are not an add request. Remove only the negative clause before
  -- looking for an insertion verb; keep the original text for FX detection.
  local positive_add_text = lo
  positive_add_text = positive_add_text
    :gsub("do%s+not%s+[^%.%!%?%;]-add%s+[^%.%!%?%;]*", "")
    :gsub("don['’]t%s+[^%.%!%?%;]-add%s+[^%.%!%?%;]*", "")
    :gsub("never%s+[^%.%!%?%;]-add%s+[^%.%!%?%;]*", "")
    :gsub("without%s+[^%.%!%?%;]-adding%s+[^%.%!%?%;]*", "")
  local add_verb =
    positive_add_text:find("%f[%w]add%f[%W]") ~= nil
    or positive_add_text:find("%f[%w]insert%f[%W]") ~= nil
    or positive_add_text:find("%f[%w]load%f[%W]") ~= nil
    or positive_add_text:find("%f[%w]give%f[%W]") ~= nil
    or positive_add_text:find("%f[%w]put%f[%W]") ~= nil
  if not add_verb then return false end
  return lo:find("%f[%w]fx%f[%W]") ~= nil
    or lo:find("%f[%w]plugin%f[%W]") ~= nil
    or lo:find("%f[%w]effect%f[%W]") ~= nil
    or lo:find("reaeq", 1, true) ~= nil
    or lo:find("reacomp", 1, true) ~= nil
    or lo:find("readelay", 1, true) ~= nil
    or lo:find("reaverbate", 1, true) ~= nil
    or lo:find("reagate", 1, true) ~= nil
    or lo:find("realimit", 1, true) ~= nil
    or lo:find("%f[%w]compressor%f[%W]") ~= nil
    or lo:find("%f[%w]eq%f[%W]") ~= nil
    or lo:find("%f[%w]delay%f[%W]") ~= nil
    or lo:find("%f[%w]reverb%f[%W]") ~= nil
    or lo:find("%f[%w]gate%f[%W]") ~= nil
    or lo:find("%f[%w]limiter%f[%W]") ~= nil
end

-- Conservative routing gate for the compact plugin workflow bundle. This is
-- intentionally narrower than prompt_is_fx_add_only: that older predicate also
-- supports response cleanup, while compact context is allowed only for plain
-- track-FX additions. Any chain location or filter-shape ambiguity stays full.
function Code.prompt_can_use_plugin_add_only_bundle(text)
  if not Code.prompt_is_fx_add_only(text) then return false end
  local lo = text:lower()
  if lo:find("%f[%w]take%s*fx%f[%W]")
     or lo:find("%f[%w]item%s*fx%f[%W]")
     or lo:find("takefx", 1, true)
     or lo:find("%f[%w]input%s*fx%f[%W]")
     or lo:find("%f[%w]monitor%s*fx%f[%W]")
     or lo:find("%f[%w]monitoring%s*fx%f[%W]")
     or lo:find("%f[%w]record%s*fx%f[%W]")
     or lo:find("%f[%w]recording%s*fx%f[%W]")
     or lo:find("%f[%w]input%s*chain%f[%W]")
     or lo:find("%f[%w]monitor%s*chain%f[%W]")
     or lo:find("%f[%w]record%s*chain%f[%W]") then
    return false
  end
  if lo:find("%f[%w]take%f[%W]")
     and (lo:find("%f[%w]item%f[%W]")
       or lo:find("%f[%w]media%s+item%f[%W]")) then
    return false
  end
  if lo:find("%f[%w]a%s+plugin%f[%W]")
     or lo:find("%f[%w]an%s+effect%f[%W]")
     or lo:find("%f[%w]some%s+plugin%f[%W]")
     or lo:find("%f[%w]any%s+plugin%f[%W]") then
    return false
  end
  if Code.prompt_targets_existing_fx(text)
     or lo:find("%f[%w]high%s+shelf%f[%W]")
     or lo:find("%f[%w]low%s+shelf%f[%W]")
     or lo:find("%f[%w]high%s+pass%f[%W]")
     or lo:find("%f[%w]low%s+pass%f[%W]")
     or lo:find("%f[%w]high%s+cut%f[%W]")
     or lo:find("%f[%w]low%s+cut%f[%W]")
     or lo:find("%f[%w]bell%s+band%f[%W]")
     or lo:find("%f[%w]filter%s+band%f[%W]") then
    return false
  end
  return true
end

function Code.lua_has_fx_param_writes(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return false end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  return stripped:find("reaper%.TrackFX_SetParam%s*%(") ~= nil
    or stripped:find("reaper%.TrackFX_SetParamNormalized%s*%(") ~= nil
    or stripped:find("reaper%.TakeFX_SetParam%s*%(") ~= nil
    or stripped:find("reaper%.TakeFX_SetParamNormalized%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_display%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_enum%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_enum_paced%s*%(") ~= nil
end

function Code.strip_inapplicable_fx_param_tip(response_text, lua_code, user_text)
  response_text = tostring(response_text or "")
  if response_text == ""
     or not Code.prompt_is_fx_add_only(user_text or "")
     or Code.lua_has_fx_param_writes(lua_code or "") then
    return response_text, false
  end
  local lower = response_text:lower()
  local first = lower:find(
    "tip:%s*plugin parameters set via script may not be perfectly precise%.?")
  if not first then return response_text, false end
  local _, last = lower:find(
    "verify the values in the plugin ui after running%.?", first)
  if not last then return response_text, false end

  local before = response_text:sub(1, first - 1):gsub("[ \t\r\n]+$", "")
  local after = response_text:sub(last + 1):gsub("^[ \t\r\n]+", "")
  local cleaned = before
  if before ~= "" and after ~= "" then cleaned = cleaned .. "\n\n" end
  cleaned = (cleaned .. after):gsub("[ \t\r\n]+$", "")
  return cleaned, true
end

function Code.prompt_requests_full_param_readout(text)
  if type(text) ~= "string" or text == "" then return false end
  local lo = text:lower()
  return lo:find("%f[%w]all%f[%W]") ~= nil
    or lo:find("%f[%w]full%f[%W]") ~= nil
    or lo:find("%f[%w]every%f[%W]") ~= nil
    or lo:find("%f[%w]complete%f[%W]") ~= nil
    or lo:find("%f[%w]raw%f[%W]") ~= nil
  end

function Code.filter_broad_fx_param_readout(user_text, response_text)
  if type(response_text) ~= "string" or response_text == "" then
    return response_text, 0
  end
  if response_text:find("```", 1, true) then return response_text, 0 end
  if not (CTX and CTX.prompt_has_fx_param_read_intent
      and CTX.prompt_has_fx_param_read_intent(user_text)) then
    return response_text, 0
  end
  if Code.prompt_requests_full_param_readout(user_text) then
    return response_text, 0
  end

  local prompt = tostring(user_text or ""):lower()
  local function clean_name(name)
    return tostring(name or "")
      :gsub("[`*_]", "")
      :gsub("^%s*(.-)%s*$", "%1")
      :lower()
  end
  local function clean_display(display)
    return tostring(display or "")
      :gsub("[`*_]", "")
      :gsub("^%s*(.-)%s*$", "%1")
      :lower()
  end
  local function prompt_mentions_name(name)
    local n = clean_name(name):gsub("[^%w]+", " "):gsub("^%s*(.-)%s*$", "%1")
    if n == "" then return false end
    return prompt:find(n, 1, true) ~= nil
  end
  local function defaultish_display(name, display)
    local n, d = clean_name(name), clean_display(display)
    if d == "" then return true end
    if n:find("pan", 1, true) then
      return d == "0" or d == "0.0" or d == "0.00" or d == "0.000"
        or d == "center" or d == "centre" or d == "c"
    end
    if n:find("level", 1, true) or n:find("trim", 1, true) then
      return d == "0 db" or d == "0.0 db" or d == "0.00 db"
        or d == "+0 db" or d == "+0.0 db" or d == "+0.00 db"
        or d == "-inf db" or d == "-inf" or d == "-infinity db"
    end
    if n:find("mix", 1, true) then
      return d == "0" or d == "0.0" or d == "0.00" or d == "0.000"
    end
    if n:find("bypass", 1, true) then
      return d:find("not bypass", 1, true) ~= nil
        or d == "off" or d == "disabled"
    end
    if n == "midi state" then return d == "enabled" end
    if n == "oversampling" or n == "expert mode"
       or n == "audition side chain" then
      return d == "off" or d == "disabled"
    end
    if n == "channel mode" then
      return d == "left/right" or d == "stereo"
    end
    if n == "side chain input signal" then
      return d == "normal input" or d == "normal"
    end
    if n == "interface" or n == "ex style" then return true end
    return false
  end
  local function should_drop(name, display)
    if prompt_mentions_name(name) then return false end
    local n = clean_name(name)
    local secondary =
         n:find("side chain level", 1, true)
      or n:find("side chain mix", 1, true)
      or n == "side chain input signal"
      or n == "wet level" or n == "wet pan"
      or n == "dry level" or n == "dry pan"
      or n == "input level" or n == "input pan"
      or n == "output level" or n == "output pan"
      or n == "midi state"
      or n == "oversampling"
      or n == "expert mode"
      or n == "audition side chain"
      or n == "channel mode"
      or n == "interface"
      or n == "ex style"
      or n:find("bypass", 1, true)
    return secondary and defaultish_display(n, display)
  end

  local out, removed = {}, 0
  for line in (response_text .. "\n"):gmatch("(.-)\n") do
    local name, display = line:match("^%s*[-*]%s+([^:]+):%s*(.-)%s*$")
    if name and should_drop(name, display) then
      removed = removed + 1
    else
      out[#out+1] = line
    end
  end
  if removed == 0 then return response_text, 0 end
  return table.concat(out, "\n"):gsub("%s+$", ""), removed
end

function Code.find_unrequested_track_deletion(lua_code, user_text)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  if not (stripped:find("reaper%.DeleteTrack%s*%(")
      or stripped:find("reaper%.Main_OnCommand%s*%(%s*40005%s*,")
      or stripped:find("reaper%.Main_OnCommandEx%s*%(%s*40005%s*,")) then
    return nil
  end

  local prompt = tostring(user_text or ""):lower():gsub("%s+", " ")
  local forbids_deletion =
    prompt:find("do not delete", 1, true) ~= nil
    or prompt:find("don't delete", 1, true) ~= nil
    or prompt:find("without deleting", 1, true) ~= nil
    or prompt:find("do not remove", 1, true) ~= nil
    or prompt:find("don't remove", 1, true) ~= nil
  local function verb_targets_track(verb)
    local verb_pat = "%f[%w_]" .. verb .. "%f[^%w_]"
    local function has_word(text, word)
      return text:find("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
    end
    local function has_any_word(text, words)
      for _, word in ipairs(words) do
        if has_word(text, word) then return true end
      end
      return false
    end
    local function first_word_pos(text, words)
      local best = nil
      for _, word in ipairs(words) do
        local pos = text:find("%f[%w_]" .. word .. "%f[^%w_]")
        if pos and (not best or pos < best) then best = pos end
      end
      return best
    end
    local track_create_verbs = { "create", "add", "insert", "make", "build" }
    local non_track_context_words = {
      "send", "sends", "fx", "plugin", "plugins", "effect", "effects",
      "item", "items", "take", "takes", "marker", "markers", "region",
      "regions", "envelope", "envelopes", "reverb", "delay",
    }
    local non_track_target_words = {
      "send", "sends", "fx", "plugin", "plugins", "effect", "effects",
      "item", "items", "take", "takes", "marker", "markers", "region",
      "regions", "envelope", "envelopes",
    }
    local carry_stop_words = {
      "keep", "preserve", "leave", "create", "add", "insert", "make",
      "build", "rename", "route", "move", "copy", "set",
    }
    local function direct_track_target(part, verb_end, mentions_track)
      if not mentions_track then return false end
      local after_verb = part:sub(verb_end + 1)
      local track_pos = first_word_pos(after_verb, { "track", "tracks" })
      if not track_pos then return false end
      local other_pos = first_word_pos(after_verb, non_track_target_words)
      if other_pos and other_pos < track_pos then
        local between = after_verb:sub(other_pos, track_pos)
        if not between:find("%f[%w_]and%f[^%w_]") then return false end
      end
      if after_verb:find("%f[%w_]tracks?%s+fx%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+effects?%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+items?%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+takes?%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+markers?%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+regions?%f[^%w_]")
          or after_verb:find("%f[%w_]tracks?%s+envelopes?%f[^%w_]") then
        return false
      end
      return true
    end
    local function track_is_primary_object(part)
      local track_pos = first_word_pos(part, { "track", "tracks" })
      if not track_pos then return false end
      local other_pos = first_word_pos(part, non_track_target_words)
      return not other_pos or track_pos < other_pos
    end
    local created_track_subject = nil
    for clause in (prompt .. "."):gmatch("([^%.;,]+)[%.;,]") do
      clause = clause:gsub("%f[%w_]but%f[^%w_]", "and")
      local carried_target_verb = false
      for part in (clause .. " and "):gmatch("(.-)%s+and%s+") do
        local mentions_track = part:find("%f[%w_]tracks?%f[^%w_]") ~= nil
        local verb_start, verb_end = part:find(verb_pat)
        local direct_target = verb_start
          and direct_track_target(part, verb_end, mentions_track)
        local carried_target = false
        if not verb_start and carried_target_verb and mentions_track
            and not has_any_word(part, carry_stop_words) then
          carried_target =
            direct_track_target(verb .. " " .. part, #verb, mentions_track)
        end
        if verb_start
            and (direct_target
              or (created_track_subject
                and (has_any_word(part, { "them", "those", "these" })
                  or (created_track_subject == "singular"
                    and has_word(part, "it")))
                and not has_any_word(part, non_track_context_words)))
            or carried_target then
          return true
        end
        carried_target_verb = verb_start and not direct_target
          and has_any_word(part, non_track_context_words) or false
        if mentions_track
            and track_is_primary_object(part)
            and has_any_word(part, track_create_verbs) then
          created_track_subject =
            has_word(part, "track") and not has_word(part, "tracks")
              and "singular" or "plural"
        elseif has_any_word(part, non_track_context_words) then
          created_track_subject = nil
        end
      end
    end
    return false
  end
  local requested_track_deletion =
    verb_targets_track("delete")
    or verb_targets_track("remove")
    or verb_targets_track("clear")
    or verb_targets_track("wipe")
    or prompt:find("clear the project", 1, true) ~= nil
    or prompt:find("empty the project", 1, true) ~= nil
    or prompt:find("start from scratch", 1, true) ~= nil
    or prompt:find("replace existing tracks", 1, true) ~= nil
    or prompt:find("rebuild the project", 1, true) ~= nil
  if requested_track_deletion and not forbids_deletion then return nil end

  local findings, line_no = {}, 0
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    if line:find("reaper%.DeleteTrack%s*%(")
       or line:find("reaper%.Main_OnCommand%s*%(%s*40005%s*,")
       or line:find("reaper%.Main_OnCommandEx%s*%(%s*40005%s*,") then
      findings[#findings + 1] = { line = line_no }
    end
  end
  return #findings > 0 and findings or nil
end

-- =============================================================================
-- Code.find_action_request_relevance_violations
-- =============================================================================
-- Defense-in-depth relevance gate for generated Lua. Existing validators are
-- deliberately precise about individual API mistakes; this layer compares the
-- action's broad effect with the actual request and captured session instead:
--   * literal FX additions need explicit FX/effect-family intent;
--   * literal track targets must appear in the prompt or request-time snapshot;
--   * high-impact native actions need matching user intent;
--   * dynamically resolved actions that are not grounded in an explicit,
--     by-name Action List request require relevance review.
--
-- It is intentionally conservative: uncertain dynamic actions are review-only,
-- not declared wrong, and all findings block Auto-run rather than making the
-- script un-runnable. That keeps the safety boundary strong without preventing
-- a user from reviewing and deliberately running a valid advanced workflow.

function Code.prompt_requests_item_deletion(user_text)
  local prompt = tostring(user_text or ""):lower():gsub("'", "")
    :gsub("%s+", " ")
  if prompt == "" then return false end
  if prompt:find("do not delete", 1, true)
      or prompt:find("dont delete", 1, true)
      or prompt:find("without deleting", 1, true)
      or prompt:find("do not remove", 1, true)
      or prompt:find("dont remove", 1, true) then
    return false
  end
  for _, verb in ipairs({ "delete", "remove", "clear", "wipe" }) do
    for clause in (prompt .. "."):gmatch("([^%.;,]+)[%.;,]") do
      local _, verb_end = clause:find("%f[%w_]" .. verb .. "%f[^%w_]")
      if verb_end then
        local tail = clause:sub(verb_end + 1)
        local item_pos = tail:find("%f[%w_]items?%f[^%w_]")
          or tail:find("%f[%w_]clips?%f[^%w_]")
          or tail:find("media%s+items?")
        local other_pos = tail:find("%f[%w_]tracks?%f[^%w_]")
          or tail:find("%f[%w_]fx%f[^%w_]")
          or tail:find("%f[%w_]plugins?%f[^%w_]")
          or tail:find("%f[%w_]effects?%f[^%w_]")
        if item_pos and (not other_pos or item_pos < other_pos) then
          return true
        end
      end
    end
  end
  return false
end

function Code.find_action_request_relevance_violations(
    lua_code, user_text, snapshot, authorized_plugin_profiles)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local prompt = tostring(user_text or "")
  local prompt_lower = prompt:lower():gsub("\226\128\153", "'")
    :gsub("%s+", " ")
  local prompt_words = " " .. prompt_lower:gsub("[^%w]+", " ") .. " "
  local findings, seen = {}, {}

  local function add(kind, line, detail, review_only)
    local key = tostring(kind) .. ":" .. tostring(line or 0) .. ":"
      .. tostring(detail or "")
    if seen[key] then return end
    seen[key] = true
    findings[#findings + 1] = {
      kind = kind,
      line = line,
      detail = detail,
      review_only = review_only == true,
    }
  end

  local function mentions_number(id)
    local id_text, pos = tostring(id), 1
    while true do
      local s, e = prompt:find(id_text, pos, true)
      if not s then return false end
      local before = s > 1 and prompt:sub(s - 1, s - 1) or ""
      local after = e < #prompt and prompt:sub(e + 1, e + 1) or ""
      if not before:match("%d") and not after:match("%d") then return true end
      pos = e + 1
    end
  end

  local function has_word(word)
    return prompt_words:find(" " .. word .. " ", 1, true) ~= nil
  end
  local function has_any(words)
    for _, word in ipairs(words) do
      if has_word(word) then return true end
    end
    return false
  end
  local function phrase(text)
    return prompt_lower:find(text, 1, true) ~= nil
  end
  local requests_time_selection_glue =
    has_any({ "glue", "glued", "gluing" })
    and (phrase("within time selection")
      or phrase("within the time selection")
      or phrase("within existing time selection")
      or phrase("within the existing time selection")
      or phrase("within current time selection")
      or phrase("within the current time selection")
      or phrase("inside time selection")
      or phrase("inside the time selection")
      or phrase("inside existing time selection")
      or phrase("inside the existing time selection")
      or phrase("inside current time selection")
      or phrase("inside the current time selection")
      or phrase("in time selection")
      or phrase("in the time selection")
      or phrase("in existing time selection")
      or phrase("in the existing time selection")
      or phrase("in current time selection")
      or phrase("in the current time selection")
      or phrase("within selection")
      or phrase("within the selection")
      or phrase("within time range")
      or phrase("within the time range")
      or phrase("within selected time")
      or phrase("time-selection"))
  local function requests_time_selection_change()
    local verbs = { "set", "create", "make", "define", "change", "adjust" }
    local suffixes = {
      "%s+the%s+time%s+selection",
      "%s+a%s+time%s+selection",
      "%s+time%s+selection",
      "%s+the%s+current%s+time%s+selection",
      "%s+current%s+time%s+selection",
      "%s+the%s+existing%s+time%s+selection",
      "%s+existing%s+time%s+selection",
    }
    for _, verb in ipairs(verbs) do
      for _, suffix in ipairs(suffixes) do
        local pattern = "%f[%w]" .. verb .. "%f[%W]" .. suffix
        local search_from = 1
        while true do
          local start_pos, end_pos = prompt_lower:find(pattern, search_from)
          if not start_pos then break end
          local before = prompt_lower:sub(math.max(1, start_pos - 48),
            start_pos - 1)
          -- Keep commas inside the lookback so coordinated negation such as
          -- "Do not add, move, or change the time selection" fails closed.
          local clause = before:match("([^%.%;!%?]*)$") or before
          local negated =
            clause:find("%f[%w]do%s+not%f[%W]") ~= nil
            or clause:find("%f[%w]don't%f[%W]") ~= nil
            or clause:find("%f[%w]dont%f[%W]") ~= nil
            or clause:find("%f[%w]never%f[%W]") ~= nil
            or clause:find("%f[%w]without%f[%W]") ~= nil
            or clause:find("%f[%w]avoid%f[%W]") ~= nil
          if not negated then return true end
          search_from = end_pos + 1
        end
      end
    end
    return false
  end
  local request_sets_time_selection = requests_time_selection_change()

  local function high_impact_allowed(id)
    if mentions_number(id) then return true end
    if id == 1013 then
      if has_word("arm") or has_word("armed") or has_word("arming") then
        return phrase("start recording") or phrase("begin recording")
          or has_any({ "capture", "take" })
      end
      return has_any({ "record", "recording", "capture" })
    elseif id == 40026 then
      return has_any({ "save", "saving" })
        and has_any({ "project", "session", "rpp" })
    elseif id == 40029 then
      return has_any({ "undo", "revert" }) or phrase("go back")
    elseif id == 40030 then
      return has_any({ "redo", "reapply" })
    elseif id == 40005 then
      return Code.find_unrequested_track_deletion(
        "reaper.Main_OnCommand(40005, 0)", prompt) == nil
    elseif id == 40006 then
      return Code.prompt_requests_item_deletion(prompt)
    elseif id == 40364 then
      return has_any({ "metronome", "click" })
        and has_any({ "toggle", "enable", "disable", "turn", "on", "off" })
    elseif id == 40860 then
      return has_any({ "close", "closing" })
        and has_any({ "project", "session", "tab" })
    elseif id == 1007 or id == 40044 then
      return has_any({ "play", "playback", "transport" })
    elseif id == 1008 or id == 40073 then
      return has_any({ "pause", "playback", "transport" })
    elseif id == 1016 then
      return has_any({ "stop", "playback", "transport", "recording" })
    end
    return true
  end

  local high_impact = {
    [1013] = "start recording",
    [40026] = "save the project",
    [40029] = "undo",
    [40030] = "redo",
    [40005] = "delete tracks",
    [40006] = "delete selected items",
    [40364] = "toggle the metronome",
    [40860] = "close the current project tab",
    [1007] = "start playback",
    [1008] = "pause playback",
    [1016] = "stop transport",
    [40044] = "toggle play/stop",
    [40073] = "toggle play/pause",
  }

  local unrequested_track_delete =
    Code.find_unrequested_track_deletion(lua_code, prompt)
  for _, finding in ipairs(unrequested_track_delete or {}) do
    add("high_impact_action", finding.line,
      "DeleteTrack (delete tracks)", false)
  end

  local code_only = _lua_code_only_preserving_offsets(lua_code)
  local function named_action_lookup_is_grounded(variable)
    -- Keep this exception deliberately narrow. A dynamic command is relevant
    -- only when the user explicitly asked to find a native action by name,
    -- the script enumerates the Action List, and the value passed to
    -- Main_OnCommand comes from a lookup whose literal arguments contain the
    -- requested action name. Code.scan_risky still requires confirmation for
    -- every dynamic command before execution; this only prevents a correct
    -- response from being mislabeled as unrelated to the request.
    local explicit_name_lookup = prompt_lower:find("by name", 1, true) ~= nil
      or (prompt_lower:find("enumerat", 1, true) ~= nil
        and prompt_lower:find("action name", 1, true) ~= nil)
    if not explicit_name_lookup
        or not prompt_lower:find("action", 1, true)
        or not code_only:find("reaper%.kbd_enumerateActions%s*%(") then
      return false
    end

    local requested_name = prompt_lower:match(
      "native%s+([%w][%w%s%-]-)%s+action")
    if not requested_name or requested_name == "" then
      requested_name = prompt_lower:match(
        "with%s+broad%s+([%w%s/%-]-)%s+fallback%s+terms")
    end
    if not requested_name or requested_name == "" then return false end

    local ignored = {
      a = true, an = true, the = true, native = true, reaper = true,
      item = true, items = true, selected = true,
    }
    local requested_words = {}
    for word in requested_name:gmatch("[%w]+") do
      if #word >= 3 and not ignored[word] then
        requested_words[#requested_words + 1] = word
      end
    end
    -- A one-word name is too weak to justify bypassing the relevance review.
    if #requested_words < 2 then return false end

    local function literal_text_matches_requested(literal_text)
      local joined = " " .. table.concat(literal_text, " ")
        :lower():gsub("[^%w]+", " ") .. " "
      if #literal_text == 0 then return false end
      for _, word in ipairs(requested_words) do
        if not joined:find(" " .. word .. " ", 1, true) then
          return false
        end
      end
      return true
    end

    -- A model may express fallback action-name searches as one nested list or
    -- as several assignments to the same command variable. Aggregate literal
    -- terms across every call to the same locally-defined lookup helper before
    -- deciding whether the requested name is covered. This still rejects a
    -- dynamic command when any requested fallback word is absent overall.
    local helper_literals = {}
    local escaped_lookup_variable = variable:gsub("(%W)", "%%%1")
    for line in (lua_code .. "\n"):gmatch("([^\r\n]*)\r?\n") do
      local assignment_pattern = "%f[%w_]" .. escaped_lookup_variable
        .. "%f[^%w_]%s*[,_%w%s]-=%s*([%a_][%w_]*)%s*(%b())"
      for helper, args in line:gmatch(assignment_pattern) do
        local literal_text = helper_literals[helper]
        if not literal_text then
          literal_text = {}
          helper_literals[helper] = literal_text
        end
        for value in args:gmatch('"(.-)"') do
          literal_text[#literal_text + 1] = value:lower()
        end
        for value in args:gmatch("'(.-)'") do
          literal_text[#literal_text + 1] = value:lower()
        end
        -- Also recognize the table-driven fallback form:
        --   local candidates = { { "timecode" }, { "smpte" }, ... }
        --   for _, terms in ipairs(candidates) do
        --     cmd = find_action(terms)
        --   end
        -- The loop variable must be the helper's sole argument and must come
        -- directly from ipairs over a literal local table.
        local argument_variable = args:match(
          "^%(%s*([%a_][%w_]*)%s*%)$")
        if argument_variable then
          local escaped_argument = argument_variable:gsub("(%W)", "%%%1")
          local iterator_pattern = "for%s+[%a_][%w_]*%s*,%s*"
            .. escaped_argument .. "%s+in%s+ipairs%s*%(%s*"
            .. "([%a_][%w_]*)%s*%)"
          for table_variable in code_only:gmatch(iterator_pattern) do
            local escaped_table = table_variable:gsub("(%W)", "%%%1")
            -- Locate the declaration in comment/string-blanked code, then
            -- read the balanced table from the raw source at the same byte
            -- offset so its literal search terms remain available.
            local declaration_start = code_only:find(
              "local%s+" .. escaped_table .. "%s*=%s*{")
            local brace_start = declaration_start
              and code_only:find("{", declaration_start, true) or nil
            local table_body = brace_start
              and lua_code:sub(brace_start):match("^(%b{})") or nil
            if table_body then
              for value in table_body:gmatch('"(.-)"') do
                literal_text[#literal_text + 1] = value:lower()
              end
              for value in table_body:gmatch("'(.-)'") do
                literal_text[#literal_text + 1] = value:lower()
              end
            end
          end
        end
      end
    end
    for helper, literal_text in pairs(helper_literals) do
      local escaped = helper:gsub("(%W)", "%%%1")
      if literal_text_matches_requested(literal_text)
          and code_only:find("function%s+" .. escaped .. "%s*%(") then
        return true
      end
    end

    -- Also accept the compact inline form produced by smaller models:
    -- enumerate `(cmd, action_name)`, compare action_name to the requested
    -- literal (or a literal-backed target variable), copy cmd into the
    -- variable later passed to Main_OnCommand.
    local enum_cmd_vars, enum_name_vars = {}, {}
    for cmd_var, name_var in code_only:gmatch(
        "local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*"
          .. "reaper%.kbd_enumerateActions%s*%(") do
      enum_cmd_vars[cmd_var] = true
      enum_name_vars[name_var] = true
    end
    local escaped_variable = variable:gsub("(%W)", "%%%1")
    local assigned_from_enum = false
    for cmd_var in pairs(enum_cmd_vars) do
      local escaped_cmd = cmd_var:gsub("(%W)", "%%%1")
      if code_only:find("%f[%w_]" .. escaped_variable
          .. "%f[^%w_]%s*=%s*" .. escaped_cmd .. "%f[^%w_]") then
        assigned_from_enum = true
        break
      end
    end
    if not assigned_from_enum then return false end

    local target_literals = {}
    local literal_vars = {}
    for line in (lua_code .. "\n"):gmatch("([^\r\n]*)\r?\n") do
      local lhs, quote, value = line:match(
        "^%s*local%s+([%a_][%w_]*)%s*=%s*([\"'])(.-)%2%s*$")
      if lhs and quote then literal_vars[lhs] = value end
    end
    for name_var in pairs(enum_name_vars) do
      local escaped_name = name_var:gsub("(%W)", "%%%1")
      for line in (lua_code .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local rhs = line:match(escaped_name .. "%s*==%s*(.+)")
          or line:match("(.+)%s*==%s*" .. escaped_name .. "%f[^%w_]")
        if rhs then
          local direct = rhs:match('^%s*"(.-)"')
            or rhs:match("^%s*'(.-)'")
          if direct then
            target_literals[#target_literals + 1] = direct
          else
            local target_var = rhs:match("^%s*([%a_][%w_]*)")
            if target_var and literal_vars[target_var] then
              target_literals[#target_literals + 1] = literal_vars[target_var]
            end
          end
        end
      end
    end
    return literal_text_matches_requested(target_literals)
  end
  if requests_time_selection_glue and not request_sets_time_selection
      and (code_only:find(
          "reaper%.GetSet_LoopTimeRange2%s*%(%s*[^,]-,%s*true%s*,")
        or code_only:find("reaper%.GetSet_LoopTimeRange%s*%(%s*true%s*,")) then
    add("time_selection_glue_changes_range", nil,
      "use the existing time selection only; do not create, expand, or replace it. "
        .. "If it is empty, explain that no time selection is active and return "
        .. "without starting an undo block or changing the project",
      false)
  end
  local line_no = 0
  for line in (code_only .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    for _, fn in ipairs({ "Main_OnCommand", "Main_OnCommandEx" }) do
      for id_text in line:gmatch(
          "reaper%." .. fn .. "%s*%(%s*([+-]?%d+)") do
        local id = tonumber(id_text)
        if id == 40362 and requests_time_selection_glue then
          add("time_selection_glue_action", line_no,
            "40362 ignores the time selection; use verified action 42432, "
              .. "do not create or expand a missing time selection, require at least "
              .. "two overlapping target items, and restore unrelated item selections",
            false)
        end
        if requests_time_selection_glue
            and (id == 40020 or id == 40625 or id == 40626 or id == 40635)
            and not (request_sets_time_selection
              and (id == 40625 or id == 40626)) then
          add("time_selection_glue_changes_range", line_no,
            tostring(id) .. " changes or clears the existing time selection; "
              .. "use the captured range unchanged for action 42432",
            false)
        end
        if id and high_impact[id] and not high_impact_allowed(id) then
          add("high_impact_action", line_no,
            tostring(id) .. " (" .. high_impact[id] .. ")", false)
        end
      end
      local variable = line:match(
        "reaper%." .. fn .. "%s*%(%s*([%a_][%w_]*)")
      if variable and not named_action_lookup_is_grounded(variable) then
        add("dynamic_action", line_no,
          fn .. "(" .. variable .. ")", true)
      end
    end
  end

  local function normalize_name(value)
    return tostring(value or ""):lower()
      :gsub("^%s+", ""):gsub("%s+$", "")
      :gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  end
  local normalized_prompt = " " .. normalize_name(prompt) .. " "
  local session_names = {}
  for name in tostring(snapshot or ""):gmatch("\n%d+|([^|\n]*)|%d+|%-?%d+") do
    local normalized = normalize_name(name)
    if normalized ~= "" then session_names[normalized] = true end
  end
  for name in tostring(snapshot or ""):gmatch('name "(.-)"[,%.]') do
    local normalized = normalize_name(name)
    if normalized ~= "" then session_names[normalized] = true end
  end
  local function target_is_grounded(name)
    local normalized = normalize_name(name)
    if normalized == "" then return true end
    if session_names[normalized] then return true end
    return normalized_prompt:find(" " .. normalized .. " ", 1, true) ~= nil
  end
  -- Names the script only WRITES as a new track's name are not lookup targets,
  -- so they must not require prompt/snapshot grounding when the script also
  -- creates a track. Collect names that flow into a P_NAME set: string literals
  -- passed directly, and simple variables assigned a string literal that are
  -- then passed as the value. Names used to FIND existing tracks (compared to
  -- GetTrackName, or handed to find/get/resolve/target functions) are collected
  -- elsewhere and stay checked. Scanned on raw lua_code because code_only blanks
  -- the "P_NAME" key and the name literals themselves.
  local creates_tracks =
    code_only:find("reaper%.InsertTrackAtIndex%s*%(") ~= nil
    or code_only:find("reaper%.Main_OnCommand%s*%(%s*40001%s*,") ~= nil
    or code_only:find("reaper%.Main_OnCommandEx%s*%(%s*40001%s*,") ~= nil
    or code_only:find("reaper%.Main_OnCommand%s*%(%s*40702%s*,") ~= nil
    or code_only:find("reaper%.Main_OnCommandEx%s*%(%s*40702%s*,") ~= nil
  local inserted_index_pos = {}
  local function normalized_expr(raw)
    return tostring(raw or ""):gsub("%s+", "")
  end
  for pos, raw_idx in code_only:gmatch(
      "()reaper%.InsertTrackAtIndex%s*%(%s*([^,%)]+)") do
    local idx = normalized_expr(raw_idx)
    if idx ~= "" then
      inserted_index_pos[idx] = math.min(inserted_index_pos[idx] or pos, pos)
    end
  end
  local insert_selected_pos = code_only:find(
    "reaper%.Main_OnCommand%s*%(%s*40001%s*,")
    or code_only:find("reaper%.Main_OnCommandEx%s*%(%s*40001%s*,")
    or code_only:find("reaper%.Main_OnCommand%s*%(%s*40702%s*,")
    or code_only:find("reaper%.Main_OnCommandEx%s*%(%s*40702%s*,")
  local created_track_vars = {}
  for pos, var, raw_idx in code_only:gmatch(
      "()local%s+([%a_][%w_]*)%s*=%s*reaper%.GetTrack%s*%(%s*[^,]+,%s*([^%)]+)%)") do
    local insert_pos = inserted_index_pos[normalized_expr(raw_idx)]
    if insert_pos and insert_pos < pos then created_track_vars[var] = pos end
  end
  if insert_selected_pos then
    local function selection_was_redirected(from_pos, to_pos)
      local window = code_only:sub(from_pos + 1, to_pos - 1)
      local raw_window = lua_code:sub(from_pos + 1, to_pos - 1)
      local function target_is_existing(raw_target, mutation_pos)
        local target = tostring(raw_target or ""):match(
          "^%s*([%a_][%w_]*)%s*$")
        local created_pos = target and created_track_vars[target]
        return not created_pos or created_pos >= mutation_pos
      end
      local function targets_existing_track(pattern)
        for rel_pos, raw_target in window:gmatch(pattern) do
          local mutation_pos = from_pos + rel_pos
          if target_is_existing(raw_target, mutation_pos) then return true end
        end
        return false
      end
      local function i_selected_targets_existing()
        for rel_pos, raw_target in raw_window:gmatch(
            "()reaper%.SetMediaTrackInfo_Value%s*%(%s*([^,]+),%s*[\"']I_SELECTED[\"']") do
          -- String contents are blanked in code_only, but offsets are preserved.
          -- Requiring the live call prefix there prevents commented examples from
          -- influencing the selection-flow inference.
          if window:sub(rel_pos):find(
              "^reaper%.SetMediaTrackInfo_Value%s*%(")
              and target_is_existing(raw_target, from_pos + rel_pos) then
            return true
          end
        end
        return false
      end
      return targets_existing_track(
          "()reaper%.SetOnlyTrackSelected%s*%(%s*([^%)]+)")
        or targets_existing_track(
          "()reaper%.SetTrackSelected%s*%(%s*([^,%)]*)")
        or i_selected_targets_existing()
    end
    for pos, var in code_only:gmatch(
        "()local%s+([%a_][%w_]*)%s*=%s*reaper%.GetSelectedTrack%s*%(") do
      if insert_selected_pos < pos
          and not selection_was_redirected(insert_selected_pos, pos) then
        created_track_vars[var] = pos
      end
    end
  end

  local pname_write_names = {}
  local function record_pname_value(raw_val)
    raw_val = tostring(raw_val or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local literal = raw_val:match('^"(.-)"$') or raw_val:match("^'(.-)'$")
    if literal then
      local n = normalize_name(literal)
      if n ~= "" then pname_write_names[n] = true end
      return
    end
    if raw_val:match("^[%a_][%w_]*$") then
      local escaped = raw_val:gsub("(%W)", "%%%1")
      for lit in lua_code:gmatch("%f[%w_]" .. escaped .. "%s*=%s*\"(.-)\"") do
        local n = normalize_name(lit)
        if n ~= "" then pname_write_names[n] = true end
      end
      for lit in lua_code:gmatch("%f[%w_]" .. escaped .. "%s*=%s*'(.-)'") do
        local n = normalize_name(lit)
        if n ~= "" then pname_write_names[n] = true end
      end
    end
  end
  for target, raw_val in lua_code:gmatch(
      'GetSetMediaTrackInfo_String%s*%(%s*([%a_][%w_]*)%s*,%s*"P_NAME"%s*,%s*([^,]+)%s*,%s*true') do
    if created_track_vars[target] then record_pname_value(raw_val) end
  end
  for target, raw_val in lua_code:gmatch(
      "GetSetMediaTrackInfo_String%s*%(%s*([%a_][%w_]*)%s*,%s*'P_NAME'%s*,%s*([^,]+)%s*,%s*true") do
    if created_track_vars[target] then record_pname_value(raw_val) end
  end
  local function add_target(name, line, may_be_created_output)
    if may_be_created_output and creates_tracks
        and pname_write_names[normalize_name(name)] then
      return
    end
    if not target_is_grounded(name) then
      add("literal_track_target", line, tostring(name), false)
    end
  end
  local function line_for_pos(pos)
    local _, n = lua_code:sub(1, math.max(1, pos or 1)):gsub("\n", "\n")
    return n + 1
  end

  for pos, _, body in lua_code:gmatch(
      "()([%w_]*track[%w_]*names?[%w_]*)%s*=%s*{(.-)}") do
    for name in body:gmatch('"(.-)"') do
      add_target(name, line_for_pos(pos), true)
    end
    for name in body:gmatch("'(.-)'") do
      add_target(name, line_for_pos(pos), true)
    end
  end
  for pos, _, name in lua_code:gmatch(
      '()([%w_]*track[%w_]*name[%w_]*)%s*=%s*"(.-)"') do
    add_target(name, line_for_pos(pos), true)
  end
  for pos, _, name in lua_code:gmatch(
      "()([%w_]*track[%w_]*name[%w_]*)%s*=%s*'(.-)'") do
    add_target(name, line_for_pos(pos), true)
  end
  for pos, fn, name in lua_code:gmatch(
      '()([%w_]*[Tt]rack[%w_]*)%s*%(%s*"(.-)"') do
    local lower_fn = fn:lower()
    if lower_fn:find("find", 1, true) or lower_fn:find("get", 1, true)
        or lower_fn:find("resolve", 1, true)
        or lower_fn:find("target", 1, true) then
      add_target(name, line_for_pos(pos), false)
    end
  end
  for pos, fn, name in lua_code:gmatch(
      "()([%w_]*[Tt]rack[%w_]*)%s*%(%s*'(.-)'") do
    local lower_fn = fn:lower()
    if lower_fn:find("find", 1, true) or lower_fn:find("get", 1, true)
        or lower_fn:find("resolve", 1, true)
        or lower_fn:find("target", 1, true) then
      add_target(name, line_for_pos(pos), false)
    end
  end

  local broad_fx_intent = has_any({
    "fx", "plugin", "plugins", "effect", "effects", "chain", "processing",
    "process", "sound", "tone", "jsfx", "instrument", "vsti", "sampler",
  })
  -- A fingerprint-validated profile is concrete grounding for its exact
  -- identifier. This matters for registry paths whose vendor/folder prefix is
  -- not normally spoken by the user: "Add Saturation" legitimately generates
  -- `JS: LOSER/Saturation`, while an unrelated `VST3: Nectar 4 Saturation`
  -- must remain blocked. Product-key comparison also tolerates a host-added
  -- vendor suffix on ordinary VST3 identifiers.
  local authorized_profile_identifiers = {}
  local authorized_profile_products = {}
  local function profile_product_key(raw_name)
    local product = tostring(raw_name or "")
      :gsub("%b()", " ")
      :gsub("^[%w]+:%s*", "")
      :gsub("(%l)(%u)", "%1 %2")
    return normalize_name(product)
  end
  for _, receipt in ipairs(authorized_plugin_profiles or {}) do
    if type(receipt) == "table"
       and receipt.validation_state == "validated"
       and receipt.injected == true then
      local identifier = normalize_name(receipt.identifier)
      if identifier ~= "" then
        authorized_profile_identifiers[identifier] = true
        local product = profile_product_key(receipt.identifier)
        if product ~= "" then authorized_profile_products[product] = true end
      end
      local display = profile_product_key(receipt.display_name)
      if display ~= "" then authorized_profile_products[display] = true end
    end
  end
  local explicit_plugins = {
    { prompt = "reaeq", generated = "reaeq" },
    { prompt = "reacomp", generated = "reacomp" },
    { prompt = "reagate", generated = "reagate" },
    { prompt = "realimit", generated = "realimit" },
    { prompt = "readelay", generated = "readelay" },
    { prompt = "reaverbate", generated = "reaverbate" },
    { prompt = "pro q", generated = "pro q" },
    { prompt = "pro c", generated = "pro c" },
    { prompt = "pro g", generated = "pro g" },
    { prompt = "pro l", generated = "pro l" },
    { prompt = "pro r", generated = "pro r" },
    { prompt = "twin 3", generated = "twin 3" },
    { prompt = "serum", generated = "serum" },
    { prompt = "kontakt", generated = "kontakt" },
  }
  local requested_explicit = {}
  for _, spec in ipairs(explicit_plugins) do
    if normalized_prompt:find(" " .. spec.prompt .. " ", 1, true) then
      requested_explicit[#requested_explicit + 1] = spec.generated
    end
  end
  local function plugin_family(name)
    local normalized = normalize_name(name)
    if normalized:find("reaeq", 1, true) or normalized:find("reeq", 1, true)
        or normalized:find("pro q", 1, true)
        or normalized:find(" eq ", 1, true) or normalized:match("^eq ") then
      return "eq"
    elseif normalized:find("reacomp", 1, true)
        or normalized:find("pro c", 1, true)
        or normalized:find("compress", 1, true) then
      return "compressor"
    elseif normalized:find("reagate", 1, true)
        or normalized:find("pro g", 1, true) then
      return "gate"
    elseif normalized:find("realimit", 1, true)
        or normalized:find("pro l", 1, true)
        or normalized:find("limit", 1, true) then
      return "limiter"
    elseif normalized:find("reaverb", 1, true)
        or normalized:find("pro r", 1, true)
        or normalized:find("reverb", 1, true) then
      return "reverb"
    elseif normalized:find("readelay", 1, true)
        or normalized:find("timeless", 1, true)
        or normalized:find("delay", 1, true)
        or normalized:find("echo", 1, true) then
      return "delay"
    elseif normalized:find("vsti", 1, true)
        or normalized:find("synth", 1, true)
        or normalized:find("serum", 1, true)
        or normalized:find("kontakt", 1, true)
        or normalized:find("twin 3", 1, true) then
      return "instrument"
    end
    return nil
  end
  -- Space-insensitive grounding: registered plugin names often join words the
  -- user spells separately ("ValhallaSupermassive" vs "valhalla supermassive").
  -- Match the normalized PRODUCT name, not any individual long word: vendor
  -- tokens such as "FabFilter" or "Valhalla" are shared by sibling plugins and
  -- must not authorize a different product. Strip parenthesized vendor metadata
  -- and format tokens, and split CamelCase before comparing the full product.
  local format_tokens = {
    vst = true, vst3 = true, vst3i = true, vsti = true,
    clap = true, au = true, js = true, x64 = true,
  }
  local prompt_no_space = normalized_prompt:gsub(" ", "")
  local function product_name_grounded(raw_name)
    local product = tostring(raw_name or "")
      :gsub("%b()", " ")
      :gsub("(%l)(%u)", "%1 %2")
    product = normalize_name(product)
    local words = {}
    for word in product:gmatch("[%w]+") do
      if not format_tokens[word] then words[#words + 1] = word end
    end
    product = table.concat(words, " ")
    if product == "" then return false end
    if normalized_prompt:find(" " .. product .. " ", 1, true) then return true end
    local joined = product:gsub(" ", "")
    if #joined >= 6 and prompt_no_space:find(joined, 1, true) ~= nil then
      return true
    end

    -- User-entered product names commonly contain one ordinary typo. Permit a
    -- single edit only inside one long alphabetic product token while every
    -- other token stays exact. Letter/digit boundaries are split first so a
    -- version discriminator such as S2 can never consume the permitted edit
    -- ("S3" must stay blocked even when the rest of the product matches).
    local function split_letter_digit_tokens(text)
      local out = {}
      for word in tostring(text or ""):gmatch("[%w]+") do
        word = word:gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
        for part in word:gmatch("[%w]+") do out[#out + 1] = part end
      end
      return out
    end
    local function is_single_edit(a, b)
      if a == b then return false end
      local na, nb = #a, #b
      if math.abs(na - nb) > 1 then return false end
      if na == nb then
        local mismatches = 0
        for i = 1, na do
          if a:sub(i, i) ~= b:sub(i, i) then
            mismatches = mismatches + 1
            if mismatches > 1 then return false end
          end
        end
        return mismatches == 1
      end
      if na > nb then a, b, na, nb = b, a, nb, na end
      local i, j, skipped = 1, 1, false
      while i <= na and j <= nb do
        if a:sub(i, i) == b:sub(j, j) then
          i, j = i + 1, j + 1
        elseif skipped then
          return false
        else
          skipped, j = true, j + 1
        end
      end
      return true
    end
    local product_tokens = split_letter_digit_tokens(product)
    local prompt_tokens = split_letter_digit_tokens(normalized_prompt)
    if #product_tokens < 2 or #prompt_tokens < #product_tokens then return false end
    for start = 1, #prompt_tokens - #product_tokens + 1 do
      local fuzzy_count, exact_count, matches = 0, 0, true
      for i, wanted in ipairs(product_tokens) do
        local offered = prompt_tokens[start + i - 1]
        if offered == wanted then
          exact_count = exact_count + 1
        elseif fuzzy_count == 0
            and wanted:match("^%a+$") and offered:match("^%a+$")
            and #wanted >= 7 and #offered >= 6
            and is_single_edit(wanted, offered) then
          fuzzy_count = 1
        else
          matches = false
          break
        end
      end
      if matches and fuzzy_count == 1 and exact_count >= 1 then return true end
    end
    return false
  end
  local function plugin_is_grounded(name)
    local normalized = normalize_name(name)
    if authorized_profile_identifiers[normalized]
       or authorized_profile_products[profile_product_key(name)] then
      return true
    end
    if normalized ~= ""
        and normalized_prompt:find(" " .. normalized .. " ", 1, true) then
      return true
    end
    if product_name_grounded(name) then return true end
    if #requested_explicit > 0 then
      for _, wanted in ipairs(requested_explicit) do
        if normalized:find(wanted, 1, true) then return true end
      end
      -- Explicit-list miss: the prompt named specific plugins and this is not
      -- one of them. Ground it only if it belongs to a plugin family the prompt
      -- independently asked for (so "add pro q 4 and a compressor" grounds a
      -- substituted ReaComp via the compressor family). Do not fall through to
      -- broad_fx_intent here: a prompt naming ReaEQ that also says "another
      -- effect" must not ground a substituted Pro-Q.
      local family = plugin_family(name)
      if family and Code.prompt_expresses_plugin_family_intent(
          prompt_lower, family) then return true end
      return false
    end
    local family = plugin_family(name)
    if family and Code.prompt_expresses_plugin_family_intent(
        prompt_lower, family) then return true end
    return broad_fx_intent
  end
  -- code_only blanks comment and string bodies while preserving line offsets, so
  -- a line still carrying the call prefix there is live code, not a commented-out
  -- or in-string example. The plugin-name literal is blanked in code_only, so
  -- read the name from the aligned raw line (same split, same line indices).
  local function scan_fx_call(fn)
    local live_by_line, co_index = {}, 0
    for co_line in (code_only .. "\n"):gmatch("([^\n]*)\n") do
      co_index = co_index + 1
      if co_line:find("reaper%." .. fn .. "%s*%(") then
        live_by_line[co_index] = true
      end
    end
    local line_index = 0
    for raw_line in (lua_code .. "\n"):gmatch("([^\n]*)\n") do
      line_index = line_index + 1
      if live_by_line[line_index] then
        local name = raw_line:match(
          "reaper%." .. fn .. "%s*%([^,]+,%s*\"(.-)\"")
          or raw_line:match(
            "reaper%." .. fn .. "%s*%([^,]+,%s*'(.-)'")
        if name and not plugin_is_grounded(name) then
          add("unrequested_plugin", line_index, name, false)
        end
      end
    end
  end
  scan_fx_call("TrackFX_AddByName")
  scan_fx_call("TakeFX_AddByName")

  if #findings == 0 then return nil end
  table.sort(findings, function(a, b)
    if (a.line or 0) ~= (b.line or 0) then
      return (a.line or 0) < (b.line or 0)
    end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return tostring(a.detail or "") < tostring(b.detail or "")
  end)
  return findings
end

-- =============================================================================
-- Code.scan_risky(code) -> warning_string or nil
-- Scans a Lua code string for calls that could have side effects beyond the
-- REAPER project (file deletion, arbitrary shell commands, loading external
-- code, etc.). Returns a human-readable warning string listing what was found,
-- or nil if no risky patterns were detected.
--
-- This scanner GATES code execution: when it returns a non-nil warning, the
-- UI blocks the Run button behind a confirmation modal ("Review Before
-- Running") that the user must explicitly accept. Auto-run is also blocked.
-- This is a hard gate, not an advisory label.
--
-- Patterns are intentionally broad (matching "os.remove" anywhere in the
-- string, including inside comments or strings) to minimize false negatives.
-- A few false positives are acceptable for a safety feature.
-- RISKY_PATTERNS is hoisted out of Code.scan_risky into this do-block so it
-- isn't reallocated on every call. scan_risky runs from the render hot path
-- (once per visible Lua code block per frame), so the table allocation +
-- field assignments were measurable on long conversations.
--
-- Each entry is a list of patterns that all flag the same risk label.
-- Patterns cover both dot-notation (os.remove) and string-indexed access
-- (os["remove"], os['remove'], _G.os.remove) so the model cannot bypass the
-- warning by simply switching syntax. Catches the obvious bypass attempts;
-- determined obfuscation (loadstring with hex-encoded strings, etc.) is
-- still possible but at that point the model is actively trying to evade
-- the user's safety check, which is well outside our threat model -- the
-- user is opting in to running generated code in the first place.
do
  -- Hoisted into the do-block so the render loop does not allocate this table
  -- every frame for every visible Lua artifact.
  local RISKY_PATTERNS = {
    { label = "os.remove (deletes files)", patterns = {
      "os%.remove",
      'os%s*%[%s*["\']remove["\']%s*%]',
      "_G%.os%.remove",
      '_G%s*%[%s*["\']os["\']%s*%]',
    }},
    { label = "os.rename (moves/renames files)", patterns = {
      "os%.rename",
      'os%s*%[%s*["\']rename["\']%s*%]',
    }},
    { label = "os.execute (runs shell commands)", patterns = {
      "os%.execute",
      'os%s*%[%s*["\']execute["\']%s*%]',
      "_G%.os%.execute",
    }},
    { label = "io.popen (runs shell commands)", patterns = {
      "io%.popen",
      'io%s*%[%s*["\']popen["\']%s*%]',
    }},
    { label = "io.open in write/append mode", patterns = {
      -- Anchor the mode arg to the second positional ([^,]+ prevents the
      -- lazy match from walking across the path arg into a later string
      -- like print("welcome") that happens to start with "w" or "a"). The
      -- old lazy pattern flagged read-mode opens whenever any later quoted
      -- string in the snippet started with w or a (false-positive risky
      -- popup on perfectly safe read scripts).
      'io%.open%s*%([^,]+,%s*["\']w',
      'io%.open%s*%([^,]+,%s*["\']a',
      'io%s*%[%s*["\']open["\']%s*%]',
    }},
    { label = "shell/process launch via REAPER or SWS", patterns = {
      -- REAPER's built-in process launcher and the SWS / js_ReaScriptAPI
      -- shell helpers. Generated code can shell out via these APIs without
      -- touching os.execute or io.popen, so they need explicit coverage in
      -- the scanner -- otherwise a malicious or careless plugin call could
      -- run arbitrary commands while the auto-run gate stays silent.
      "reaper%.ExecProcess",
      "reaper%.CF_ShellExecute",
      "reaper%.BR_Win32_ShellExecute",
      'reaper%s*%[%s*["\']ExecProcess["\']%s*%]',
      'reaper%s*%[%s*["\']CF_ShellExecute["\']%s*%]',
      'reaper%s*%[%s*["\']BR_Win32_ShellExecute["\']%s*%]',
    }},
    { label = "destructive project/file API (review before running)", patterns = {
      "reaper%.Main_SaveProject%s*%(",
      "reaper%.Main_SaveProjectEx%s*%(",
      "reaper%.Main_openProject%s*%(",
      'reaper%s*%[%s*["\']Main_SaveProject["\']%s*%]%s*%(',
      'reaper%s*%[%s*["\']Main_SaveProjectEx["\']%s*%]%s*%(',
      'reaper%s*%[%s*["\']Main_openProject["\']%s*%]%s*%(',
    }},
    { label = "global REAPER config mutation (review before running)", patterns = {
      "reaper%.SNM_Set%a+ConfigVar%s*%(",
      'reaper%s*%[%s*["\']SNM_Set%a+ConfigVar["\']%s*%]%s*%(',
    }},
    { label = "high-impact REAPER action (confirm before running)", patterns = {
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*1013%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40026%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40029%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40030%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40005%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40006%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40364%s*,",
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*40860%s*,",
    }},
    { label = "dynamically resolved REAPER action (confirm exact action)", patterns = {
      "reaper%.Main_OnCommand[%w_]*%s*%(%s*[%a_][%w_]*%s*,",
    }},
    { label = "extension-state write (review namespace before running)", match = function(code, searchable)
      code = tostring(code or "")
      searchable = tostring(searchable or code)
      local function literal_arg_after(open_end)
        local i = open_end + 1
        while code:sub(i, i):match("%s") do i = i + 1 end
        local quote = code:sub(i, i)
        if quote ~= '"' and quote ~= "'" then return nil, false end
        local j = i + 1
        while j <= #code do
          local ch = code:sub(j, j)
          if ch == "\\" then
            j = j + 2
          elseif ch == quote then
            return code:sub(i + 1, j - 1), true
          else
            j = j + 1
          end
        end
        return nil, false
      end
      local function scan_call_pattern(pattern)
        local pos = 1
        while true do
          local _s, e = searchable:find(pattern, pos)
          if not e then return false end
          local ns, is_literal = literal_arg_after(e)
          if not (is_literal and ns == "ReaAssist") then return true end
          pos = e + 1
        end
      end
      return scan_call_pattern("reaper%.SetExtState%s*%(")
        or scan_call_pattern('reaper%s*%[%s*["\']SetExtState["\']%s*%]%s*%(')
    end},
    { label = "require (loads external modules)", patterns = {
      "%f[%w_]require%s*%(",
      "%f[%w_]require%s*['\"]",
    }},
    { label = "dofile (executes external files)", patterns = {
      "dofile%s*%(",
      "dofile%s*['\"]",
    }},
    { label = "loadfile (loads external files)", patterns = {
      "loadfile%s*%(",
      "loadfile%s*['\"]",
    }},
    { label = "loadstring/load (executes runtime strings)", patterns = {
      "loadstring%s*%(",
      "%f[%w_]load%s*%(",  -- bare load() but not e.g. fileloader(
    }},
    { label = "debug library access", patterns = {
      "%f[%w_]debug%s*%.",
      "%f[%w_]debug%s*%[",
    }},
  }
  local lua_blank_comments_and_strings
  local RISKY_SCAN_CACHE = {}
  local RISKY_SCAN_CACHE_ORDER = {}
  local RISKY_SCAN_CACHE_MAX_ENTRIES = 32
  local RISKY_SCAN_CACHE_MAX_CODE_BYTES = 65536

  local function risky_cache_store(code, result)
    if #code > RISKY_SCAN_CACHE_MAX_CODE_BYTES then return end
    RISKY_SCAN_CACHE[code] = result or false
    RISKY_SCAN_CACHE_ORDER[#RISKY_SCAN_CACHE_ORDER + 1] = code
    while #RISKY_SCAN_CACHE_ORDER > RISKY_SCAN_CACHE_MAX_ENTRIES do
      local old = table.remove(RISKY_SCAN_CACHE_ORDER, 1)
      RISKY_SCAN_CACHE[old] = nil
    end
  end

  function Code.scan_risky(code)
    if type(code) ~= "string" or code == "" then return nil end
    local cached = RISKY_SCAN_CACHE[code]
    if cached ~= nil then return cached or nil end
    local searchable = lua_blank_comments_and_strings(code)
    local found = {}
    for _, entry in ipairs(RISKY_PATTERNS) do
      if entry.match then
        if entry.match(code, searchable) then
          found[#found+1] = entry.label
        end
      else
        for _, pat in ipairs(entry.patterns) do
          if searchable:find(pat) then
            found[#found+1] = entry.label
            break  -- one match per label is enough
          end
        end
      end
    end
    local result = nil
    if #found > 0 then
      result = "Warning: " .. table.concat(found, ", ")
    end
    risky_cache_store(code, result)
    return result
  end

  function Code.prompt_requests_jsfx_track_companion(user_text)
    local s = tostring(user_text or ""):lower()
    if s == "" then return false end
    if not (s:find("jsfx", 1, true)
        or s:find("reajs", 1, true)
        or s:find("eel2", 1, true)) then
      return false
    end
    local track_word = "%f[%w]tracks?%f[%W]"
    if not s:find(track_word) then return false end
    if s:find("add%s+.-jsfx%s+.-" .. track_word)
        or s:find("put%s+.-jsfx%s+.-" .. track_word)
        or s:find("place%s+.-jsfx%s+.-" .. track_word)
        or s:find("insert%s+.-jsfx%s+.-" .. track_word)
        or s:find("load%s+.-jsfx%s+.-" .. track_word)
        or s:find("apply%s+.-jsfx%s+.-" .. track_word)
        or s:find("create%s+.-" .. track_word .. "%s+.-jsfx")
        or s:find("create%s+.-jsfx%s+.-" .. track_word) then
      return true
    end
    return false
  end

  function Code.find_jsfx_format_issue(response_text, extracted_jsfx)
    local text = tostring(response_text or "")
    local code = tostring(extracted_jsfx or "")
    if text == "" then return nil end
    local function has_section(src, name)
      return ("\n" .. tostring(src or "")):find(
        "\n[ \t]*@" .. name .. "%f[%W]") ~= nil
    end
    local function has_section_header_line(src, name)
      local normalized = tostring(src or ""):gsub("\r\n", "\n")
      for raw_line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw_line:match("^%s*(.-)%s*$") or ""
        if line == "@" .. name
            or line:find("^@" .. name .. "%s*//") then
          return true
        end
      end
      return false
    end
    local function clean_label(label)
      local value = tostring(label or ""):lower()
        :match("^%s*(.-)%s*$")
      return value ~= "" and value or "(unlabelled)"
    end

    if code ~= "" and not has_section(code, "sample") then
      -- A valid MIDI-only JSFX can intentionally use @block without @sample.
      -- Retry only when the response proves a real @sample section was
      -- stranded outside the prematurely closed fence.
      local outside = text:gsub(
        "```[^\r\n]*[ \t\r]*\n.-[ \t\r\n]*```", "")
      if has_section_header_line(outside, "sample") then
        return {
          kind = "early_closed_fence",
          label = "jsfx",
          raw = text,
        }
      end
    end
    if code ~= "" then return nil end

    for label, body in text:gmatch(
        "```([^\r\n]*)[ \t\r]*\n(.-)[ \t\r\n]*```") do
      local normalized = clean_label(label)
      if normalized ~= "jsfx" and normalized ~= "eel"
          and tostring(body):find("^%s*desc%s*:") then
        return {
          kind = "wrong_fence_label",
          label = normalized,
          raw = body,
        }
      end
    end

    -- Also catch an unclosed wrong/unlabelled fence whose JSFX body starts
    -- with desc:. Correct labelled closed fences were already extracted.
    local label, body = text:match(
      "```([^\r\n]*)[ \t\r]*\n%s*(desc%s*:.*)$")
    if body then
      return {
        kind = "unclosed_fence",
        label = clean_label(label),
        raw = body,
      }
    end
    return nil
  end

  function Code.rewrite_lua_companion_jsfx_refs(lua_code, jsfx_code, fx_name)
    local code = tostring(lua_code or "")
    local replacement = tostring(fx_name or "")
    if code == "" or replacement == "" then return lua_code, false end
    local changed = false
    local function esc_pat(s)
      return tostring(s or ""):gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    end
    local function rep()
      return replacement
    end
    local refs = {}
    if Code.derive_filename_jsfx then
      local derived = Code.derive_filename_jsfx(jsfx_code or "")
      if derived and derived ~= "" then
        refs[#refs + 1] = "ReaAssist/" .. derived
        local shorter = derived:gsub("^ReaAssist%s+", "")
        if shorter ~= derived and shorter ~= "" then
          refs[#refs + 1] = "ReaAssist/" .. shorter
        end
      end
    end
    for _, ref in ipairs(refs) do
      local n
      code, n = code:gsub(esc_pat(ref), rep)
      if n and n > 0 then changed = true end
      local without_ext = ref:gsub("%.jsfx$", "")
      if (not n or n == 0) and without_ext ~= ref then
        code, n = code:gsub(esc_pat(without_ext), rep)
        if n and n > 0 then changed = true end
      end
    end
    local out = {}
    local normalized = code:gsub("\r\n", "\n"):gsub("\r", "\n")
    local had_trailing_newline = normalized:sub(-1) == "\n"
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
      local patched = line
      if patched:find(".jsfx", 1, true) then
        local n
        patched, n = patched:gsub(
          "(%f[%w_]fx_file%f[^%w_]%s*=%s*)\"[^\"]+%.jsfx\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fx_file%f[^%w_]%s*=%s*)'[^']+%.jsfx'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfx_file%f[^%w_]%s*=%s*)\"[^\"]+%.jsfx\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfx_file%f[^%w_]%s*=%s*)'[^']+%.jsfx'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fxfile%f[^%w_]%s*=%s*)\"[^\"]+%.jsfx\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fxfile%f[^%w_]%s*=%s*)'[^']+%.jsfx'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfxfile%f[^%w_]%s*=%s*)\"[^\"]+%.jsfx\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfxfile%f[^%w_]%s*=%s*)'[^']+%.jsfx'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
      end
      if patched:find("ReaAssist/", 1, true) then
        local n
        patched, n = patched:gsub(
          "(%f[%w_]fx_path%f[^%w_]%s*=%s*)\"ReaAssist/[^\"\n]+\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fx_path%f[^%w_]%s*=%s*)'ReaAssist/[^'\n]+'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfx_path%f[^%w_]%s*=%s*)\"ReaAssist/[^\"\n]+\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfx_path%f[^%w_]%s*=%s*)'ReaAssist/[^'\n]+'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fxpath%f[^%w_]%s*=%s*)\"ReaAssist/[^\"\n]+\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]fxpath%f[^%w_]%s*=%s*)'ReaAssist/[^'\n]+'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfxpath%f[^%w_]%s*=%s*)\"ReaAssist/[^\"\n]+\"",
          function(prefix)
            return prefix .. "\"" .. replacement .. "\""
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub(
          "(%f[%w_]jsfxpath%f[^%w_]%s*=%s*)'ReaAssist/[^'\n]+'",
          function(prefix)
            return prefix .. "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
      end
      if patched:find("ReaAssist/", 1, true)
          and patched:find(".jsfx", 1, true) then
        local n
        patched, n = patched:gsub('"ReaAssist/"%s*%.%.%s*"[^"]+%.jsfx"',
          function()
            return '"' .. replacement .. '"'
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub("'ReaAssist/'%s*%.%.%s*'[^']+%.jsfx'",
          function()
            return "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
      end
      if patched:find("TrackFX_AddByName", 1, true)
          and patched:find("ReaAssist/", 1, true)
          and patched:find("..", 1, true) then
        local n
        patched, n = patched:gsub('"ReaAssist/"%s*%.%.%s*[%w_]+',
          function()
            return '"' .. replacement .. '"'
          end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub("'ReaAssist/'%s*%.%.%s*[%w_]+",
          function()
            return "'" .. replacement .. "'"
          end)
        if n and n > 0 then changed = true end
      end
      if patched:find("TrackFX_AddByName", 1, true) then
        local n
        patched, n = patched:gsub('"ReaAssist/[^"]+%.jsfx"', function()
          return '"' .. replacement .. '"'
        end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub("'ReaAssist/[^']+%.jsfx'", function()
          return "'" .. replacement .. "'"
        end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub('"ReaAssist/[^"]+"', function()
          return '"' .. replacement .. '"'
        end)
        if n and n > 0 then changed = true end
        patched, n = patched:gsub("'ReaAssist/[^']+'", function()
          return "'" .. replacement .. "'"
        end)
        if n and n > 0 then changed = true end
      end
      out[#out + 1] = patched
    end
    if #out > 0 and out[#out] == "" and not had_trailing_newline then
      out[#out] = nil
    end
    local joined = table.concat(out, "\n")
    if joined:find("%f[%w_]fxFile%f[^%w_]")
        and joined:find("%f[%w_]jsfxFile%f[^%w_]")
        and not joined:find("local%s+jsfxFile%s*=") then
      local n
      joined, n = joined:gsub("%f[%w_]jsfxFile%f[^%w_]", "fxFile")
      if n and n > 0 then changed = true end
    end
    if joined:find("%f[%w_]fx_fullname%f[^%w_]")
        and joined:find("%f[%w_]jsfx_fullname%f[^%w_]")
        and not joined:find("local%s+jsfx_fullname%s*=") then
      local n
      joined, n = joined:gsub("%f[%w_]jsfx_fullname%f[^%w_]",
        "fx_fullname")
      if n and n > 0 then changed = true end
    end
    return joined, changed
  end

  function lua_blank_comments_and_strings(src)
    src = tostring(src or "")
    local n = #src
    if n == 0 then return "" end

    local out, i = {}, 1
    local function blank(s)
      return (s:gsub("[^\n]", " "))
    end
    local function long_bracket(pos)
      if src:sub(pos, pos) ~= "[" then return nil end
      local j = pos + 1
      while src:sub(j, j) == "=" do j = j + 1 end
      if src:sub(j, j) ~= "[" then return nil end
      return j + 1, src:sub(pos + 1, j - 1)
    end
    local function append_blank(a, b)
      out[#out + 1] = blank(src:sub(a, b))
    end

    while i <= n do
      local c = src:sub(i, i)
      local next_c = src:sub(i + 1, i + 1)
      if c == "-" and next_c == "-" then
        local lb_start, lb_eq = long_bracket(i + 2)
        if lb_start then
          local close = "]" .. lb_eq .. "]"
          local close_pos = src:find(close, lb_start, true)
          local end_pos = close_pos and (close_pos + #close - 1) or n
          append_blank(i, end_pos)
          i = end_pos + 1
        else
          local eol = src:find("\n", i, true)
          if eol then
            append_blank(i, eol - 1)
            out[#out + 1] = "\n"
            i = eol + 1
          else
            append_blank(i, n)
            i = n + 1
          end
        end
      elseif c == '"' or c == "'" then
        local quote, j = c, i + 1
        local end_pos = n
        while j <= n do
          local ch = src:sub(j, j)
          if ch == "\\" then
            j = j + 2
          elseif ch == quote then
            end_pos = j
            break
          elseif ch == "\n" then
            end_pos = j - 1
            break
          else
            j = j + 1
          end
        end
        append_blank(i, end_pos)
        i = end_pos + 1
      elseif c == "[" then
        local lb_start, lb_eq = long_bracket(i)
        if lb_start then
          local close = "]" .. lb_eq .. "]"
          local close_pos = src:find(close, lb_start, true)
          local end_pos = close_pos and (close_pos + #close - 1) or n
          append_blank(i, end_pos)
          i = end_pos + 1
        else
          out[#out + 1] = c
          i = i + 1
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end

    return table.concat(out)
  end

  local FORBIDDEN_SANDBOX_GLOBALS = {
    { label = "os.*", patterns = {
      "%f[%w_]os%s*%.",
      'os%s*%[%s*["\']',
      "_G%.os%s*%.",
      '_G%s*%[%s*["\']os["\']%s*%]',
    }},
    { label = "io.*", patterns = {
      "%f[%w_]io%s*%.",
      'io%s*%[%s*["\']',
      "_G%.io%s*%.",
      '_G%s*%[%s*["\']io["\']%s*%]',
    }},
    { label = "debug.*", patterns = {
      "%f[%w_]debug%s*%.",
      'debug%s*%[%s*["\']',
      "_G%.debug%s*%.",
      '_G%s*%[%s*["\']debug["\']%s*%]',
    }},
    { label = "package.*", patterns = {
      "%f[%w_]package%s*%.",
      'package%s*%[%s*["\']',
      "_G%.package%s*%.",
      '_G%s*%[%s*["\']package["\']%s*%]',
    }},
    { label = "require", patterns = {
      "%f[%w_]require%s*%(",
      "%f[%w_]require%s*['\"]",
    }},
    { label = "dofile", patterns = {
      "%f[%w_]dofile%s*%(",
      "%f[%w_]dofile%s*['\"]",
    }},
    { label = "loadfile", patterns = {
      "%f[%w_]loadfile%s*%(",
      "%f[%w_]loadfile%s*['\"]",
    }},
    { label = "loadstring/load", patterns = {
      "%f[%w_]loadstring%s*%(",
      "%f[%w_]load%s*%(",
    }},
  }

  function Code.scan_forbidden_sandbox_globals(code)
    if type(code) ~= "string" or code == "" then return nil end
    code = lua_blank_comments_and_strings(code)
    local found = {}
    for _, entry in ipairs(FORBIDDEN_SANDBOX_GLOBALS) do
      for _, pat in ipairs(entry.patterns) do
        if code:find(pat) then
          found[#found + 1] = entry.label
          break
        end
      end
    end
    if #found == 0 then return nil end
    return table.concat(found, ", ")
  end
end

-- =============================================================================
-- Lua artifact classification and latest-code memory
-- =============================================================================
-- Distinguishes complete runnable scripts from snippets, diffs, toolbar/action
-- scripts, or syntax errors before Run/Auto-run. Also keeps one latest working
-- Lua candidate so follow-up prompts like "make that brighter" can include the
-- right code context without the user pasting it again.

function Code._lua_artifact_trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Code._lua_artifact_line_count(s)
  s = tostring(s or "")
  if s == "" then return 0 end
  local n = 1
  for _ in s:gmatch("\n") do n = n + 1 end
  return n
end

function Code._lua_artifact_strip_comments(s)
  return tostring(s or "")
    :gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
end

function Code._lua_artifact_context_says_fragment(text)
  local lt = tostring(text or ""):lower()
  if lt == "" then return false end
  if lt:find("complete script", 1, true)
     or lt:find("full script", 1, true)
     or lt:find("entire script", 1, true)
     or lt:find("runnable script", 1, true) then
    return false
  end
  return lt:find("snippet", 1, true) ~= nil
    or lt:find("fragment", 1, true) ~= nil
    or lt:find("patch", 1, true) ~= nil
    or lt:find("diff", 1, true) ~= nil
    or lt:find("replace this", 1, true) ~= nil
    or lt:find("replace the line", 1, true) ~= nil
    or lt:find("change this line", 1, true) ~= nil
    or lt:find("one-line", 1, true) ~= nil
    or lt:find("one line", 1, true) ~= nil
    or lt:find("single line", 1, true) ~= nil
    or lt:find("only showed", 1, true) ~= nil
    or lt:find("just reduce", 1, true) ~= nil
end

function Code._lua_has_quoted_word(text, word)
  text = tostring(text or "")
  word = tostring(word or "")
  return text:find('"' .. word .. '"', 1, true) ~= nil
    or text:find("'" .. word .. "'", 1, true) ~= nil
end

function Code.lua_action_context_run_block_reason(code)
  local stripped = Code._lua_artifact_strip_comments(code)
  local has_action_context =
    stripped:find("reaper%.get_action_context%s*%(") ~= nil
  local has_toolbar_state =
    stripped:find("reaper%.SetToggleCommandState%s*%(") ~= nil
    or stripped:find("reaper%.RefreshToolbar2%s*%(") ~= nil
  if has_action_context and has_toolbar_state then
    return "toolbar/action-context scripts must be launched by their "
      .. "installed REAPER action, not from inside ReaAssist"
  end
  return nil
end

function Code.find_toolbar_toggle_action_issues(code)
  local stripped = Code._lua_artifact_strip_comments(code)
  local issues = {}
  local has_action_context =
    stripped:find("reaper%.get_action_context%s*%(") ~= nil
  local has_toolbar_state =
    stripped:find("reaper%.SetToggleCommandState%s*%(") ~= nil
    or stripped:find("reaper%.RefreshToolbar2%s*%(") ~= nil
  local has_defer = stripped:find("reaper%.defer%s*%(") ~= nil
  local has_extstate_lock =
    (stripped:find("reaper%.GetExtState%s*%(") ~= nil
      or stripped:find("reaper%.SetExtState%s*%(") ~= nil)
    and (Code._lua_has_quoted_word(stripped, "running")
      or Code._lua_has_quoted_word(stripped, "request_close"))
  if has_action_context and has_toolbar_state and has_defer
     and has_extstate_lock then
    issues[#issues + 1] = {
      code = "persistent_toolbar_reentry",
      message = "same action mixes a persistent toolbar watcher, ExtState "
        .. "single-instance lock, and click-to-toggle behavior",
    }
  end
  local writes_freemode =
    stripped:find("reaper%.SetMediaTrackInfo_Value%s*%(") ~= nil
    and Code._lua_has_quoted_word(stripped, "I_FREEMODE")
  if writes_freemode
     and not stripped:find("reaper%.UpdateTimeline%s*%(") then
    issues[#issues + 1] = {
      code = "freemode_without_timeline",
      message = "script writes I_FREEMODE but does not call "
        .. "reaper.UpdateTimeline() after changing lane mode",
    }
  end
  if #issues == 0 then return nil end
  return issues
end

function Code.classify_lua_artifact(code, opts)
  opts = opts or {}
  local raw = tostring(code or "")
  local trimmed = Code._lua_artifact_trim(raw)
  local info = {
    kind = "complete_script",
    parse_ok = true,
    runnable = true,
    reason = nil,
    line_count = Code._lua_artifact_line_count(trimmed),
    byte_count = #raw,
  }
  if trimmed == "" then
    info.kind = "empty"
    info.runnable = false
    info.reason = "empty Lua block"
    return info
  end

  local _chunk, parse_err = load(trimmed, "lua_artifact_preflight", "t", {})
  if not _chunk then
    info.kind = "syntax_error"
    info.parse_ok = false
    info.runnable = false
    info.parse_err = parse_err
    info.reason = "Lua syntax check failed"
    return info
  end

  local stripped = Code._lua_artifact_strip_comments(trimmed)
  local lower = stripped:lower()
  local first_line = stripped:match("^%s*([^\r\n]+)") or stripped
  local short = info.line_count <= 4 and #trimmed <= 360
  local has_reaper_or_gfx = stripped:find("reaper%.") ~= nil
    or stripped:find("gfx%.") ~= nil
  local has_complete_shape = lower:find("undo_beginblock", 1, true) ~= nil
    or lower:find("undo_endblock", 1, true) ~= nil
    or stripped:find("local%s+function%s+[%w_]+") ~= nil
    or stripped:find("function%s+[%w_]+%s*%(") ~= nil
    or stripped:find("reaper%.defer%s*%(") ~= nil
  local starts_control =
       first_line:match("^%s*if%s") ~= nil
    or first_line:match("^%s*if%s*%(") ~= nil
    or first_line:match("^%s*for%s") ~= nil
    or first_line:match("^%s*while%s") ~= nil
    or first_line:match("^%s*repeat%s*$") ~= nil
    or first_line:match("^%s*elseif%s") ~= nil
    or first_line:match("^%s*else%s*$") ~= nil
    or first_line:match("^%s*return%s") ~= nil
    or first_line:match("^%s*break%s*$") ~= nil

  if trimmed:find("^%s*@@")
     or trimmed:find("^%s*%-%-%-")
     or trimmed:find("^%s*%+%+%+") then
    info.kind = "patch"
    info.runnable = false
    info.reason = "diff or patch text"
    return info
  end

  if short and starts_control and not has_reaper_or_gfx
     and not has_complete_shape then
    info.kind = "fragment"
    info.runnable = false
    info.reason = "short control-flow snippet without REAPER actions"
    return info
  end

  if info.line_count <= 8
     and Code._lua_artifact_context_says_fragment(opts.context_text)
     and not has_complete_shape then
    info.kind = "fragment"
    info.runnable = false
    info.reason = "surrounding text presents this as a snippet or patch"
    return info
  end

  local action_context_reason = Code.lua_action_context_run_block_reason(stripped)
  if action_context_reason then
    info.kind = "action_context_script"
    info.manual_run_only = true
    info.manual_run_reason = action_context_reason
  end

  return info
end

function Code.lua_artifact_block_message(info)
  info = info or {}
  local kind = info.kind or "fragment"
  local reason = info.reason or "it does not look self-contained"
  if info.manual_run_only then
    return "This Lua block is a toolbar/action-context script. "
      .. "ReaAssist did not run it because `reaper.get_action_context()` "
      .. "and toolbar toggle state must come from the installed REAPER "
      .. "action, not ReaAssist's own action context. Save/install it as "
      .. "a REAPER action and launch it from that toolbar button."
  end
  if kind == "syntax_error" then
    return "This Lua block failed syntax validation and was not run: "
      .. tostring(info.parse_err or reason)
  end
  return "This Lua block looks like a " .. kind
    .. ", not a complete runnable script (" .. tostring(reason) .. "). "
    .. "ReaAssist did not run it. Ask for the complete script or edit "
    .. "the block until it is self-contained before running."
end

function Code.record_latest_code_candidate(code, source, opts)
  opts = opts or {}
  if type(code) ~= "string" or code == "" then return nil end
  local artifact = opts.artifact
    or Code.classify_lua_artifact(code, { context_text = opts.context_text })
  if not artifact or not artifact.parse_ok or not artifact.runnable then
    return nil
  end
  local prev = S.latest_code_candidate
  local keep_working = prev and prev.code == code and prev.working == true
  S.latest_code_candidate = {
    code = code,
    source = source or "unknown",
    code_type = "lua",
    artifact_kind = artifact.kind,
    runnable = true,
    working = keep_working or opts.working == true,
    working_note = keep_working and prev.working_note or opts.working_note,
    captured_at = os.time and os.time() or nil,
  }
  return S.latest_code_candidate
end

-- Detect high-confidence internal orchestration vocabulary before a model
-- response can enter chat history or execute. A user may explicitly ask about
-- these identifiers, so each marker is exempt when it already appears in the
-- user's own prompt.
function Code.find_internal_output_leaks(response_text, user_text)
  local response = tostring(response_text or ""):lower()
  if response == "" then return nil end
  local user = tostring(user_text or ""):lower()
  local markers = {
    "pinned references",
    "pinned context",
    "profile guidance",
    "reference guidance",
    "referral guidance",
    "plugin_ref:",
    "prompt_bundle:",
    "preferred_plugins:",
    "pref:",
    "fx_inspect:",
    "fx_params:",
    "resolve:",
    "sticky_context",
    "sticky context",
    "internal context note",
    "internal note to the model",
    "persistent validated-profile safety requirement",
    "persistent existing-effect safety requirement",
    "do not mention this",
    "context_needed",
  }
  local findings = {}
  for _, marker in ipairs(markers) do
    if response:find(marker, 1, true)
       and not user:find(marker, 1, true) then
      findings[#findings + 1] = {
        kind = "internal_output_leak",
        detail = marker,
        review_only = false,
      }
    end
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.extract_user_lua_candidate(user_text)
  local text = tostring(user_text or "")
  local parts = {}
  for block in text:gmatch("```lua%s*\n(.-)\n%s*```") do
    parts[#parts+1] = block
  end
  if #parts == 0 then
    for block in text:gmatch("```reascript%s*\n(.-)\n%s*```") do
      parts[#parts+1] = block
    end
  end
  if #parts > 0 then
    local code = table.concat(parts, "\n\n")
    return code, Code.classify_lua_artifact(code, { context_text = text })
  end

  local trimmed = Code._lua_artifact_trim(text)
  if trimmed == "" then return nil end
  if not (trimmed:find("reaper%.") or trimmed:find("gfx%.")
          or trimmed:find("local%s+function")
          or trimmed:find("function%s+[%w_]+%s*%(")) then
    return nil
  end
  local artifact = Code.classify_lua_artifact(trimmed, { context_text = text })
  if artifact.parse_ok then return trimmed, artifact end
  return nil
end

function Code.maybe_update_latest_from_user(user_text)
  local code, artifact = Code.extract_user_lua_candidate(user_text)
  if code and artifact then
    return Code.record_latest_code_candidate(code, "user", {
      artifact = artifact,
      context_text = user_text,
    })
  end
  return nil
end

function Code.maybe_mark_latest_candidate_working(user_text)
  local cand = S.latest_code_candidate
  if not cand then return false end
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  if lt:find("doesn't work", 1, true)
     or lt:find("doesnt work", 1, true)
     or lt:find("does not work", 1, true)
     or lt:find("not working", 1, true)
     or lt:find("won't work", 1, true)
     or lt:find("wont work", 1, true)
     or lt:find("runtime error", 1, true)
     or (Code._latest_code_text_has_error_word
       and Code._latest_code_text_has_error_word(lt)) then
    return false
  end
  local mentions_code = Code._latest_code_text_has_code_word
    and Code._latest_code_text_has_code_word(lt)
  local positive = lt:find("%f[%w]works%f[%W]") ~= nil
    or lt:find("%f[%w]worked%f[%W]") ~= nil
    or lt:find("that's it", 1, true) ~= nil
    or lt:find("that is it", 1, true) ~= nil
    or (mentions_code and (
      lt:find("%f[%w]good%f[%W]") ~= nil
      or lt:find("%f[%w]perfect%f[%W]") ~= nil
      or lt:find("looks good", 1, true) ~= nil))
  if not positive then return false end
  cand.working = true
  cand.working_note = user_text
  cand.working_at = os.time and os.time() or nil
  return true
end

Code.LATEST_CODE_CONTEXT_MAX_BYTES = Code.LATEST_CODE_CONTEXT_MAX_BYTES or 12000

function Code._latest_code_text_has_code_word(lt)
  lt = tostring(lt or ""):lower()
  return lt:find("%f[%w]script%f[%W]") ~= nil
    or lt:find("%f[%w]code%f[%W]") ~= nil
    or lt:find("%f[%w]lua%f[%W]") ~= nil
    or lt:find("%f[%w]reascript%f[%W]") ~= nil
end

function Code._latest_code_text_has_error_word(lt)
  lt = tostring(lt or ""):lower()
  return lt:find("doesn't work", 1, true) ~= nil
    or lt:find("doesnt work", 1, true) ~= nil
    or lt:find("does not work", 1, true) ~= nil
    or lt:find("not working", 1, true) ~= nil
    or lt:find("won't work", 1, true) ~= nil
    or lt:find("wont work", 1, true) ~= nil
    or lt:find("%f[%w]failed%f[%W]") ~= nil
    or lt:find("%f[%w]fails%f[%W]") ~= nil
    or lt:find("%f[%w]error%f[%W]") ~= nil
    or lt:find("%f[%w]errors%f[%W]") ~= nil
    or lt:find("%f[%w]crash%f[%W]") ~= nil
    or lt:find("%f[%w]crashes%f[%W]") ~= nil
    or lt:find("%f[%w]incorrect%f[%W]") ~= nil
    or lt:find("%f[%w]wrong%f[%W]") ~= nil
    or lt:find("not right", 1, true) ~= nil
    or lt:find("not what i wanted", 1, true) ~= nil
    or lt:find("not what i asked", 1, true) ~= nil
end

function Code.latest_code_prompt_refers_to_candidate(user_text, opts)
  opts = opts or {}
  local lt = tostring(user_text or ""):lower()
  if lt == "" then return false end
  local has_code_word = Code._latest_code_text_has_code_word(lt)
  local explicit =
       lt:find("latest script", 1, true) ~= nil
    or lt:find("latest code", 1, true) ~= nil
    or lt:find("last script", 1, true) ~= nil
    or lt:find("last code", 1, true) ~= nil
    or lt:find("previous script", 1, true) ~= nil
    or lt:find("previous code", 1, true) ~= nil
    or lt:find("current script", 1, true) ~= nil
    or lt:find("current code", 1, true) ~= nil
    or lt:find("working script", 1, true) ~= nil
    or lt:find("working code", 1, true) ~= nil
    or lt:find("same script", 1, true) ~= nil
    or lt:find("same code", 1, true) ~= nil
    or lt:find("this script", 1, true) ~= nil
    or lt:find("this code", 1, true) ~= nil
    or lt:find("that script", 1, true) ~= nil
    or lt:find("that code", 1, true) ~= nil
    or lt:find("complete latest", 1, true) ~= nil
    or lt:find("full latest", 1, true) ~= nil
    or lt:find("script above", 1, true) ~= nil
    or lt:find("code above", 1, true) ~= nil
    or lt:find("above script", 1, true) ~= nil
    or lt:find("above code", 1, true) ~= nil
    or lt:find("script you wrote", 1, true) ~= nil
    or lt:find("code you wrote", 1, true) ~= nil
    or lt:find("script you generated", 1, true) ~= nil
    or lt:find("code you generated", 1, true) ~= nil
  if explicit then return true end

  local edit_pronoun =
       lt:find("fix it", 1, true) ~= nil
    or lt:find("fix that", 1, true) ~= nil
    or lt:find("fix this", 1, true) ~= nil
    or lt:find("change it", 1, true) ~= nil
    or lt:find("change that", 1, true) ~= nil
    or lt:find("change this", 1, true) ~= nil
    or lt:find("update it", 1, true) ~= nil
    or lt:find("update that", 1, true) ~= nil
    or lt:find("update this", 1, true) ~= nil
    or lt:find("modify it", 1, true) ~= nil
    or lt:find("modify that", 1, true) ~= nil
    or lt:find("modify this", 1, true) ~= nil
    or lt:find("rewrite it", 1, true) ~= nil
    or lt:find("rewrite that", 1, true) ~= nil
    or lt:find("rewrite this", 1, true) ~= nil
    or lt:find("add to it", 1, true) ~= nil
    or lt:find("add to that", 1, true) ~= nil
    or lt:find("add to this", 1, true) ~= nil
  if not edit_pronoun then return false end
  if has_code_word then return true end
  if opts.had_last_run_error == true then return true end
  return Code._latest_code_text_has_error_word(lt)
end

function Code.latest_code_followup_note(user_text, opts)
  local cand = S.latest_code_candidate
  if not cand or type(cand.code) ~= "string" or cand.code == "" then
    return nil
  end
  if not Code.latest_code_prompt_refers_to_candidate(user_text, opts) then
    return nil
  end
  local code = cand.code
  local truncated = false
  local max_bytes = tonumber(Code.LATEST_CODE_CONTEXT_MAX_BYTES) or 12000
  if max_bytes < 1000 then max_bytes = 1000 end
  if #code > max_bytes then
    code = code:sub(1, max_bytes)
      .. "\n-- [latest code candidate truncated for context] "
      .. "Ask the user for the full script before making exact edits "
      .. "outside the visible portion."
    truncated = true
  end
  return "(INTERNAL CODE CONTEXT -- DO NOT MENTION THIS: The user appears "
    .. "to be referring to the latest runnable Lua script candidate. Use "
    .. "this as the current code base unless the user explicitly provides "
    .. "a newer script. source=" .. tostring(cand.source)
    .. ", working_base=" .. tostring(cand.working == true)
    .. ", truncated=" .. tostring(truncated) .. ".)\n```lua\n"
    .. code .. "\n```"
end

-- =============================================================================
-- Code.run
-- =============================================================================
-- Compiles and executes a Lua string inside REAPER. Shows a message box on
-- compile or runtime error. Returns true on success, false on error.
--
-- Wraps execution in a plugin-level undo block as a safety net. The assistant
-- is instructed to include Undo_BeginBlock/EndBlock in its code, but if it
-- forgets, this outer wrapper ensures the user still gets undo protection.
-- Nested undo blocks are harmless in REAPER (inner ones are simply absorbed).
-- The surrounding UI code decides whether risky-code confirmation, safety backup,
-- auto-run, or manual Run brought us here; this function is the final executor.

-- =============================================================================
-- Code.safety_backup
-- =============================================================================
-- Copies the current project file to a timestamped .rpp-bak file in the same
-- directory. Returns true on success, or false plus an error key on failure:
--   "unsaved"    - project has never been saved (no file on disk)
--   "read_error" - could not open the source file
--   "write_error"- could not write the backup file
--
-- Every caller must use Code.safety_backup_can_proceed() below rather than
-- maintaining its own error allowlist. A missing error means the backup was
-- created; "unchanged" means the existing diff-aware backup is still current.
-- Every named or future/unknown error is fail-closed.
function Code.safety_backup_can_proceed(err)
  return err == nil or err == "unchanged"
end

function Code.safety_backup()
  local BACKUP_MAX = 10  -- maximum safety backups to keep per project
  local _, proj_path = reaper.EnumProjects(-1)
  if not proj_path or proj_path == "" then
    return false, "unsaved"
  end

  -- Extract directory and project name (without .rpp extension). Match the
  -- extension case-insensitively so projects saved as .RPP / .Rpp / etc. are
  -- not treated as unsaved.
  local dir  = proj_path:match("(.+)[/\\]")
  local name = proj_path:match("([^/\\]+)%.[rR][pP][pP]$")
  if not dir or not name then
    return false, "unsaved"
  end

  -- Diff-aware: skip if the project state hasn't changed since our last backup.
  -- GetProjectStateChangeCount increments on every change (fader moves, edits,
  -- FX adds, etc.) regardless of whether the user has saved.
  local cur_state = reaper.GetProjectStateChangeCount(0)
  if S.last_backup_path and S.last_backup_state == cur_state then
    return false, "unchanged"
  end

  -- A wall-clock second alone can collide when two changed states are backed
  -- up quickly, after a script reload, or from separate portable REAPER
  -- instances touching the same project. Add millisecond, project-state,
  -- per-process sequence, and instance components, then retain an existence
  -- loop as a final defense. This avoids overwriting an earlier safety point
  -- without depending on non-portable exclusive-create file modes.
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local precise = reaper.time_precise and reaper.time_precise() or os.clock()
  local millis = math.floor((precise % 1) * 1000)
  S.safety_backup_sequence = (tonumber(S.safety_backup_sequence) or 0) + 1
  local instance = tostring(S.INSTANCE_ID or "main")
    :gsub("[^%w]", ""):sub(-6)
  if instance == "" then instance = "main" end
  local suffix = string.format("%03d-%06d-%03d-%s",
    millis, cur_state % 1000000, S.safety_backup_sequence % 1000, instance)
  local backup_base = dir .. RA.SEP .. name .. "-SafetyBackup-"
    .. timestamp .. "-" .. suffix
  local backup_path = backup_base .. ".rpp-bak"
  local collision = 0
  while reaper.file_exists(backup_path) and collision < 999 do
    collision = collision + 1
    backup_path = backup_base .. "-" .. tostring(collision) .. ".rpp-bak"
  end
  if reaper.file_exists(backup_path) then
    Log.line("BACKUP", "Could not allocate a collision-free safety backup name")
    return false, "write_error"
  end

  -- Save current project state (including unsaved changes) directly to the
  -- backup path without touching the main .rpp. Options=0 means no template
  -- flags and no project-path reassignment.
  reaper.Main_SaveProjectEx(0, backup_path, 0)

  -- Main_SaveProjectEx returns nothing, so verify the backup landed on disk
  -- before claiming success. Without this, a permission error or full-disk
  -- failure would silently let generated code run while the UI insists a
  -- safety backup exists.
  if not reaper.file_exists(backup_path) then
    return false, "write_error"
  end
  local probe = io.open(backup_path, "rb")
  if not probe then return false, "write_error" end
  local first = probe:read(1)
  probe:close()
  if not first then return false, "write_error" end

  -- Track last backup state for diff-aware skipping.
  S.last_backup_path  = backup_path
  S.last_backup_state = cur_state

  -- Enforce backup cap: collect all SafetyBackup files, delete oldest if over limit.
  -- Escape Lua magic characters in the project name so names like "Mix-v1.2"
  -- don't break the pattern and bypass the cap (causing infinite disk bloat).
  local safe_name = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
  local legacy_pattern = "^" .. safe_name
    .. "%-SafetyBackup%-%d+%-%d+%.rpp%-bak$"
  local unique_pattern = "^" .. safe_name
    .. "%-SafetyBackup%-%d+%-%d+%-%d+%-%d+%-%d+%-%w+%-?%d*%.rpp%-bak$"
  local backups = {}
  local idx = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, idx)
    if not fn then break end
    if fn:match(legacy_pattern) or fn:match(unique_pattern) then
      backups[#backups + 1] = fn
    end
    idx = idx + 1
  end
  if #backups > BACKUP_MAX then
    table.sort(backups)  -- alphabetical = chronological (timestamp format)
    for k = 1, #backups - BACKUP_MAX do
      local victim = dir .. RA.SEP .. backups[k]
      local ok_rm, err_rm = os.remove(victim)
      if not ok_rm then
        Log.line("BACKUP", "Failed to prune old safety backup "
          .. backups[k] .. ": " .. tostring(err_rm))
      end
    end
  end

  return true
end

-- Redirects print() to reaper.ShowConsoleMsg so output from assistant-generated
-- code is visible in REAPER's console window rather than going to stdout
-- (which REAPER hides).
--
-- Sandboxed environment: generated code only sees a curated whitelist of Lua
-- builtins plus the reaper/gfx APIs. Dangerous modules (os, io, debug,
-- package) and meta-level primitives (load, loadfile, dofile, require,
-- rawset, rawget, getmetatable, setmetatable, _G) are excluded. This is a
-- defence-in-depth layer on top of the risky-code scanner and the system
-- prompt rules -- any one of the three may stop a bad generation, but all
-- three together make accidental damage extremely unlikely.
--
-- The sandbox is a flat table (no __index fallback to _G) so generated code
-- cannot reach anything not explicitly listed. Writes go into the sandbox
-- table itself and do not leak to script globals.

-- Build only immutable scalar/function bindings once at load time. Mutable
-- library tables and host API proxies are rebuilt per run so generated code
-- cannot corrupt the next sandbox or reach denied host capabilities through
-- aliases / computed keys.

-- Shallow-copy a table's fields into a new table. Used to isolate sandbox
-- copies of `string`, `math`, and `table` from the host environment so that
-- generated code cannot corrupt the host's standard libraries by mutating
-- shared references (e.g. `string.format = function() return "pwned" end`).
local function sandbox_lib_copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local CODE_SANDBOX_DENIED_REAPER_APIS = {
  -- Shell / process launch.
  ExecProcess = true,
  CF_ShellExecute = true,
  BR_Win32_ShellExecute = true,

  -- Lifecycle escape. Generated code may use the guarded one-shot defer shim
  -- below, but it must not register callbacks that run during a later script
  -- shutdown or start a persistent loop outside this run's undo/result scope.
  atexit = true,
  runloop = true,

  -- Project/file replacement. ReaAssist creates its own pre-run safety backup;
  -- generated scripts should not save/open projects or silently touch disk.
  Main_SaveProject = true,
  Main_SaveProjectEx = true,
  Main_openProject = true,
  RecursiveCreateDirectory = true,

  -- File browser helpers belong to ReaAssist's explicit Save/Export flows, not
  -- arbitrary generated code.
  JS_Dialog_BrowseForOpenFiles = true,
  JS_Dialog_BrowseForSaveFile = true,
  JS_Dialog_BrowseForFolder = true,
  ReaAssist_Native_JS_Dialog_BrowseForSaveFile = true,
}

local function sandbox_reaper_denied_reason(key)
  if type(key) ~= "string" then return nil end
  if CODE_SANDBOX_DENIED_REAPER_APIS[key] then return key end
  if key:match("^BR_Win32_") then return key end
  if key:match("^ReaPack_") then return key end
  return nil
end

local function sandbox_api_proxy(api, overrides, label)
  overrides = overrides or {}
  label = label or "api"
  return setmetatable(overrides, {
    __index = function(_, key)
      if label == "reaper" then
        local denied = sandbox_reaper_denied_reason(key)
        if denied then
          error("reaper." .. denied
            .. " is not available in ReaAssist's generated-code sandbox", 2)
        end
      end
      return api and api[key] or nil
    end,
    __newindex = function(_, key)
      error(tostring(label) .. "." .. tostring(key)
        .. " cannot be modified in ReaAssist's generated-code sandbox", 2)
    end,
    __pairs = function(t)
      return next, t, nil
    end,
  })
end

local CODE_SANDBOX_BASE = {
  -- Lua core builtins (safe subset)
  assert     = assert,
  error      = error,
  ipairs     = ipairs,
  next       = next,
  pairs      = pairs,
  pcall      = pcall,
  select     = select,
  tonumber   = tonumber,
  tostring   = tostring,
  type       = type,
  unpack     = table.unpack or unpack,
  xpcall     = xpcall,
}

-- =============================================================================
-- Run-result and diagnostic metadata helpers
-- =============================================================================
-- These functions summarize generated artifacts and observable project changes
-- for chat display, diagnostics, and feedback payloads. They avoid storing raw
-- secrets and use REAPER's project state-change count as the cheapest mutation
-- evidence available after a run.

Code.AUTO_RUN_MANUAL_LUA_BLOCK_REASONS = {
  action_context_validator = true,
  arity_validator = true,
  audio_accessor_samples_nil_validator = true,
  audio_sync_validator = true,
  chain_upsert_validator = true,
  defer_validator = true,
  docs_gate = true,
  drum_marker_sync_validator = true,
  drum_quantize_validator = true,
  fx_add_getonly_validator = true,
  fx_check_validator = true,
  fx_identifier_validator = true,
  fx_param_scope_validator = true,
  get_by_name_validator = true,
  helper_integrity_validator = true,
  helper_validator = true,
  jsfx_format_validator = true,
  jsfx_validator = true,
  jsfx_wrong_artifact_validator = true,
  loop_time_map_validator = true,
  marker_pair_validator = true,
  media_item_label_validator = true,
  midi_input_validator = true,
  record_arm_property_validator = true,
  project_tempo_validator = true,
  proq4_bell_slope_validator = true,
  proq4_mapping_validator = true,
  proq4_parameter_contract_validator = true,
  plugin_profile_guard_validator = true,
  musical_enum_validator = true,
  fx_param_provenance_validator = true,
  reeq_gain_mapping_validator = true,
  ruler_timebase_validator = true,
  sandbox_forbidden_global = true,
  send_index_validator = true,
  stock_fx_validator = true,
  tempo_marker_validator = true,
  timecode_fx_validator = true,
  timecode_workflow_validator = true,
  toolbar_validator = true,
  trackfx_recfx_validator = true,
  transient_validator = true,
  validation_blocked = true,
  validator_gate = true,
}

Code.AUTO_RUN_MANUAL_LUA_REVIEW_REASONS = {
  action_relevance_review = true,
  auto_run_disabled = true,
  backup_failed = true,
  backup_required = true,
  manual_run_only_lua_artifact = true,
  non_runnable_lua_artifact = true,
  risky_code_confirmation = true,
}

function Code.auto_run_block_reason_blocks_manual_lua(reason)
  return Code.AUTO_RUN_MANUAL_LUA_BLOCK_REASONS[tostring(reason or "")] == true
end

function Code.auto_run_block_reason_allows_manual_lua(reason)
  return Code.AUTO_RUN_MANUAL_LUA_REVIEW_REASONS[tostring(reason or "")] == true
end

function Code.project_pointer_exists(project)
  if not project
      or type(reaper) ~= "table"
      or type(reaper.EnumProjects) ~= "function" then
    return false
  end
  local index = 0
  while true do
    local candidate = reaper.EnumProjects(index)
    if not candidate then return false end
    if candidate == project then return true end
    index = index + 1
  end
end

function Code.project_change_count()
  if type(reaper) ~= "table"
     or type(reaper.GetProjectStateChangeCount) ~= "function" then
    return nil
  end
  local proj = (type(S) == "table" and S.pending_project) or 0
  local ok, count = pcall(reaper.GetProjectStateChangeCount, proj)
  if not ok then return nil end
  return tonumber(count)
end

function Code.parameter_change_evidence(writes)
  if type(writes) ~= "table" then return nil end
  local out = {
    status = "unknown",
    target_count = 0,
    write_count = 0,
    changed_target_count = 0,
    unchanged_target_count = 0,
    returned_to_initial_count = 0,
    unknown_target_count = 0,
    profile_guarded_target_count = 0,
  }
  local guarded_products = {}
  for _, entry in pairs(writes) do
    if type(entry) == "table" then
      out.target_count = out.target_count + 1
      out.write_count = out.write_count + (tonumber(entry.write_count) or 0)
      local initial, final =
        tonumber(entry.initial_normalized), tonumber(entry.final_normalized)
      if initial == nil or final == nil then
        out.unknown_target_count = out.unknown_target_count + 1
      elseif math.abs(final - initial) > 0.0000001 then
        out.changed_target_count = out.changed_target_count + 1
      elseif entry.changed_during == true then
        out.returned_to_initial_count = out.returned_to_initial_count + 1
      else
        out.unchanged_target_count = out.unchanged_target_count + 1
      end
      if entry.plugin_profile_guard == "validated" then
        out.profile_guarded_target_count =
          out.profile_guarded_target_count + 1
        if entry.plugin_product_key then
          guarded_products[tostring(entry.plugin_product_key)] = true
        end
      end
    end
  end
  if out.target_count == 0 then return nil end
  if out.changed_target_count > 0 then
    -- A target that was already at the requested value is a successful
    -- no-op, not a partial failure. Reserve partially_changed for evidence
    -- that really is unresolved or returned to its starting value.
    if out.returned_to_initial_count > 0
       or out.unknown_target_count > 0 then
      out.status = "partially_changed"
    else
      out.status = "changed"
    end
  elseif out.returned_to_initial_count > 0
      and out.unchanged_target_count == 0
      and out.unknown_target_count == 0 then
    out.status = "returned_to_initial"
  elseif out.unchanged_target_count > 0
      or out.returned_to_initial_count > 0 then
    out.status = "unchanged"
  end
  local product_keys = {}
  for key in pairs(guarded_products) do product_keys[#product_keys + 1] = key end
  table.sort(product_keys)
  if #product_keys > 0 then out.profile_product_keys = product_keys end
  return out
end

-- Return the exact validated profile record for a live track FX target.
--
-- A profile receipt authorizes behavior guidance only for the fingerprint that
-- was validated before generation. Re-checking that same fingerprint at the
-- write boundary closes the race where the plug-in binary or instance layout
-- changes between prompt preparation and execution. A target that does not
-- correspond to any injected profile is deliberately reported as
-- `not_profile_target`; generic live-discovery writes remain available in
-- mixed-product scripts.
function Code.plugin_profile_code_key(code)
  if type(RA) == "table" and type(RA.sha256_hex) == "function" then
    return RA.sha256_hex(tostring(code or ""))
  end
  return tostring(code or "")
end

-- Passive, test-resource-only execution correlation for the visible GUI
-- campaign. This records what the shipping request/validator/runtime path
-- already did; it cannot inject a prompt, trigger Send, or write a parameter.
function Code.plugin_test_runtime_event(stage, extra)
  local ok, err = pcall(function()
    if not (reaper and reaper.GetResourcePath and reaper.GetExtState
        and RA and RA.JSON and type(RA.JSON.encode) == "function"
        and type(RA.TEMP_DIR) == "string") then
      return
    end
    if tostring(reaper.GetResourcePath() or ""):lower()
        ~= "c:\\reaper - test" then
      return
    end
    local nonce = tostring(reaper.GetExtState(
      CFG.EXT_NS, "plugin_test_case_nonce") or "")
    if nonce == "" then return end
    local event = {
      schema_version = 1,
      nonce = nonce,
      stage = tostring(stage or ""),
      event_time = reaper.time_precise and reaper.time_precise() or 0,
      profile_mode = type(S) == "table"
        and tostring(S.plugin_profile_mode or "auto") or "auto",
      profiles_used = type(S) == "table"
        and S.plugin_profiles_used or {},
      profile_preparation = type(S) == "table"
        and S.plugin_profile_preparation_trace or nil,
    }
    if type(extra) == "table" then
      for key, value in pairs(extra) do event[key] = value end
    end
    local encoded = RA.JSON.encode(event)
    if type(encoded) ~= "string" or encoded == "" then return end
    local path = RA.TEMP_DIR .. "plugin_test_runtime_events.jsonl"
    local handle, open_err = io.open(path, "ab")
    if not handle then error(open_err or "runtime event log open failed") end
    handle:write(encoded, "\n")
    handle:close()
  end)
  if not ok and type(Log) == "table" and type(Log.line) == "function" then
    Log.line("PLUGIN_TEST", "runtime event logging failed: " .. tostring(err))
  end
end

function Code.register_plugin_profile_code(code, receipts)
  if type(S) ~= "table" or type(code) ~= "string"
     or type(receipts) ~= "table" or #receipts == 0 then
    return false
  end
  S.plugin_profile_code_authorizations =
    S.plugin_profile_code_authorizations or {}
  S.plugin_profile_code_authorization_order =
    S.plugin_profile_code_authorization_order or {}
  local key = Code.plugin_profile_code_key(code)
  local copied = {}
  for _, receipt in ipairs(receipts) do
    if type(receipt) == "table"
       and receipt.validation_state == "validated"
       and receipt.injected == true then
      local item = {}
      for field, value in pairs(receipt) do item[field] = value end
      copied[#copied + 1] = item
    end
  end
  if #copied == 0 then return false end
  if S.plugin_profile_code_authorizations[key] == nil then
    local order = S.plugin_profile_code_authorization_order
    order[#order + 1] = key
    while #order > 32 do
      local expired = table.remove(order, 1)
      S.plugin_profile_code_authorizations[expired] = nil
    end
  end
  S.plugin_profile_code_authorizations[key] = copied
  Code.plugin_test_runtime_event("code_registered", {
    code_sha256 = key,
    profile_authorization_count = #copied,
  })
  return true
end

function Code.plugin_profile_receipts_for_code(code)
  if type(S) ~= "table" then return nil end
  local saved = type(S.plugin_profile_code_authorizations) == "table"
    and S.plugin_profile_code_authorizations[
      Code.plugin_profile_code_key(code)] or nil
  if type(saved) == "table" and #saved > 0 then return saved end
  local current = S.plugin_profiles_used
  if type(current) == "table" and #current > 0 then return current end
  return nil
end

function Code.plugin_profile_code_mentions_receipt(code, receipts)
  if type(code) ~= "string" or code == ""
     or type(receipts) ~= "table" then
    return false
  end
  local lower = code:lower()
  for _, receipt in ipairs(receipts) do
    if type(receipt) == "table" then
      for _, value in ipairs({
          receipt.identifier, receipt.display_name, receipt.product_key }) do
        local needle = tostring(value or ""):lower()
          :match("^%s*(.-)%s*$") or ""
        if #needle >= 4 and lower:find(needle, 1, true) then
          return true
        end
      end
    end
  end
  return false
end

function Code.plugin_profile_target_validation(track, fx, receipts,
    target_project)
  receipts = receipts
    or (type(S) == "table" and S.plugin_profiles_used or nil)
  if type(receipts) ~= "table" or #receipts == 0 then
    return nil, "profiles_inactive"
  end
  if type(CTX) ~= "table"
     or type(CTX.plugin_profile_key) ~= "function"
     or type(CTX.plugin_profile_inventory) ~= "function"
     or type(CTX.plugin_profile_match) ~= "function" then
    return nil, "profile_runtime_unavailable"
  end
  if track == nil or fx == nil or tonumber(fx) == nil
     or tonumber(fx) < 0 then
    return nil, "invalid_fx_target"
  end
  if type(reaper.ValidatePtr2) == "function"
     and not reaper.ValidatePtr2(target_project or 0, track, "MediaTrack*") then
    return nil, "invalid_track"
  end

  local ok_name, _, loaded_name =
    pcall(reaper.TrackFX_GetFXName, track, fx, "")
  if not ok_name then return nil, "fx_name_unavailable" end
  loaded_name = tostring(loaded_name or "")
  local normalize = type(CTX.plugin_profile_normalize) == "function"
    and CTX.plugin_profile_normalize
    or function(value)
      return (tostring(value or ""):lower():match("^%s*(.-)%s*$") or "")
        :gsub("%s+", " ")
    end
  local loaded_key = normalize(loaded_name)
  local function canonical_plugin_name(value)
    local key = normalize(value)
    key = key:gsub("^vst3i?%s*:%s*", "")
      :gsub("^vsti?%s*:%s*", "")
      :gsub("^clapi?%s*:%s*", "")
      :gsub("^js%s*:%s*", "")
      :gsub("^au%s*:%s*", "")
      :gsub("%s*%([^()]-%)%s*$", "")
    return key:match("^%s*(.-)%s*$") or ""
  end
  local loaded_canonical = canonical_plugin_name(loaded_name)
  local function name_matches_loaded(value)
    local key = normalize(value)
    if key == "" then return false end
    if key == loaded_key then return true end
    local canonical = canonical_plugin_name(value)
    return canonical ~= "" and canonical == loaded_canonical
  end
  local function receipt_name_matches(receipt, meta)
    if name_matches_loaded(receipt and receipt.identifier)
       or name_matches_loaded(receipt and receipt.display_name) then
      return true
    end
    if type(meta) ~= "table" then return false end
    if name_matches_loaded(meta.display_name) then return true end
    local identifiers = type(meta.identifiers) == "table"
      and meta.identifiers or {}
    for _, field in ipairs({ "add_by_name", "aliases", "curated" }) do
      for _, value in ipairs(
          type(identifiers[field]) == "table" and identifiers[field] or {}) do
        if name_matches_loaded(value) then return true end
      end
    end
    -- JSFX registry paths can differ from the title REAPER reports for the
    -- loaded instance. Accept the declared loaded name only from the exact
    -- fingerprint row that produced this validated receipt. The later live
    -- inventory check still has to reproduce that fingerprint before a write.
    local receipt_identifier = normalize(receipt and receipt.identifier)
    local receipt_fingerprint = tostring(receipt and receipt.fingerprint or "")
    for _, fingerprint in ipairs(
        type(meta.fingerprints) == "table" and meta.fingerprints or {}) do
      if type(fingerprint) == "table"
         and receipt_identifier ~= ""
         and normalize(fingerprint.identifier) == receipt_identifier
         and receipt_fingerprint ~= ""
         and tostring(fingerprint.observed_fingerprint_sha256 or "")
           == receipt_fingerprint
         and name_matches_loaded(fingerprint.loaded_name) then
        return true
      end
    end
    return false
  end
  local name_candidates = {}
  local candidate_signatures = {}
  local matched_profile_name = false
  local name_match_reason = "profile_receipt_not_current"

  for _, receipt in ipairs(receipts) do
    if type(receipt) == "table"
       and receipt.validation_state == "validated"
       and receipt.injected == true
       and receipt.product_key then
      local profile_key = CTX.plugin_profile_key(receipt.product_key)
      local meta = type(CTX._plugin_profile_metadata) == "table"
        and profile_key and CTX._plugin_profile_metadata[profile_key] or nil
      if receipt_name_matches(receipt, meta) then
        matched_profile_name = true
        local receipt_pack_revision = tostring(receipt.pack_revision or "")
        local current_pack_revision = tostring(CTX._plugin_pack_revision or "")
        local receipt_section_revision = tostring(receipt.section_revision or "")
        local current_section_revision = tostring(
          type(CTX._plugin_profile_section_revisions) == "table"
            and profile_key
            and CTX._plugin_profile_section_revisions[profile_key] or "")
        local receipt_identifier = tostring(receipt.identifier or "")
        local receipt_fingerprint = tostring(receipt.fingerprint or "")
        if type(meta) ~= "table" then
          name_match_reason = "profile_metadata_unavailable"
        elseif receipt_pack_revision == "" or current_pack_revision == ""
            or receipt_section_revision == ""
            or current_section_revision == "" then
          name_match_reason = "profile_pack_identity_unavailable"
        elseif receipt_pack_revision ~= current_pack_revision then
          name_match_reason = "profile_pack_changed"
        elseif receipt_section_revision ~= current_section_revision then
          name_match_reason = "profile_section_changed"
        elseif receipt_identifier == "" then
          name_match_reason = "profile_receipt_identifier_unavailable"
        elseif receipt_fingerprint == "" then
          name_match_reason = "profile_receipt_fingerprint_unavailable"
        else
          local signature = table.concat({
            tostring(profile_key),
            receipt_pack_revision,
            receipt_section_revision,
            receipt_identifier,
            receipt_fingerprint,
          }, "\31")
          if not candidate_signatures[signature] then
            candidate_signatures[signature] = true
            name_candidates[#name_candidates + 1] = {
              receipt = receipt,
              profile_key = profile_key,
              metadata = meta,
            }
          end
        end
      end
    end
  end

  if #name_candidates == 0 then
    return nil, matched_profile_name and name_match_reason
      or "not_profile_target"
  end

  local matched = {}
  local last_reason = "profile_fingerprint_mismatch"
  for _, candidate in ipairs(name_candidates) do
    local inventory, inventory_err =
      CTX.plugin_profile_inventory(
        track, fx, candidate.receipt.identifier)
    if inventory then
      local fingerprint, match_err =
        CTX.plugin_profile_match(candidate.profile_key, inventory)
      local live_hash = tostring(
        inventory.observed_fingerprint_sha256 or "")
      local receipt_hash = tostring(candidate.receipt.fingerprint or "")
      if fingerprint
         and live_hash ~= ""
         and live_hash == receipt_hash then
        matched[#matched + 1] = {
          receipt = candidate.receipt,
          profile_key = candidate.profile_key,
          metadata = candidate.metadata,
          inventory = inventory,
          fingerprint = fingerprint,
          loaded_name = loaded_name,
        }
      else
        last_reason = match_err
          or (live_hash ~= receipt_hash and "receipt_fingerprint_changed")
          or "profile_fingerprint_mismatch"
      end
    else
      last_reason = inventory_err or "inventory_failed"
    end
  end

  if #matched == 1 then return matched[1] end
  if #matched > 1 then return nil, "profile_target_ambiguous" end
  return nil, last_reason
end

-- Static first gate for a profile-backed response. The runtime resolver below
-- is the authority, but catching a missing resolver here gives the model one
-- invisible repair attempt instead of letting an unsafe script reach Run.
function Code.find_unguarded_profile_param_writes(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  local has_write =
    stripped:find("reaper%.TrackFX_SetParam%s*%(") ~= nil
    or stripped:find("reaper%.TrackFX_SetParamNormalized%s*%(") ~= nil
    or stripped:find("%f[%w_]set_param_display%s*%(") ~= nil
    or stripped:find("%f[%w_]set_param_enum%s*%(") ~= nil
    or stripped:find("%f[%w_]set_param_enum_paced%s*%(") ~= nil
  if not has_write then return nil end
  if stripped:find(
      "%f[%w_]local%s+function%s+reaassist_resolve_profile_params%s*%(")
     or stripped:find(
       "%f[%w_]function%s+reaassist_resolve_profile_params%s*%(")
     or stripped:find(
       "%f[%w_]local%s+reaassist_resolve_profile_params%s*=")
     or stripped:find(
       "%f[%w_]reaassist_resolve_profile_params%s*=") then
    return { "shadowed_profile_parameter_resolver" }
  end
  if not stripped:find(
      "%f[%w_]reaassist_resolve_profile_params%s*%(") then
    return { "missing_profile_parameter_resolver" }
  end

  local findings = {}
  local resolver_variables = {}
  local resolver_order = {}
  local resolver_search = 1
  while true do
    local call_start, call_open = stripped:find(
      "%f[%w_]reaassist_resolve_profile_params%s*%(", resolver_search)
    if not call_start then break end
    local before = stripped:sub(1, call_start - 1)
    local line_start = (before:match(".*()\n") or 0) + 1
    local assignment = stripped:sub(line_start, call_start - 1)
    local variable, error_variable = assignment:match(
      "^%s*local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*$")
    if not variable then
      variable, error_variable = assignment:match(
        "^%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*$")
    end
    if not variable then
      variable = assignment:match(
        "^%s*local%s+([%a_][%w_]*)%s*=%s*$")
        or assignment:match("^%s*([%a_][%w_]*)%s*=%s*$")
    end
    local call_args, call_close = Code._parse_lua_call_args(stripped, call_open)
    if call_args then
      local function declared_targets(pattern)
        local names = {}
        for name in before:gmatch(pattern) do names[name] = true end
        return names
      end
      local function bare_identifier(expr)
        return tostring(expr or ""):match(
          "^%s*([%a_][%w_]*)%s*$")
      end
      local track_arg = bare_identifier(call_args[1])
      local declared_tracks = declared_targets(
        "%f[%w_]local%s+([%a_][%w_]*)%s*=%s*reaper%.GetTrack%s*%(")
      for name in before:gmatch(
          "%f[%w_]local%s+([%a_][%w_]*)%s*=%s*reaper%.GetSelectedTrack%s*%(") do
        declared_tracks[name] = true
      end
      for name in before:gmatch(
          "%f[%w_]local%s+([%a_][%w_]*)%s*=%s*reaper%.GetMasterTrack%s*%(") do
        declared_tracks[name] = true
      end
      local has_declared_track = next(declared_tracks) ~= nil
      if track_arg and has_declared_track and not declared_tracks[track_arg] then
        findings[#findings + 1] =
          "profile_track_argument_mismatches_declared_track_" .. track_arg
      end

      local fx_arg = bare_identifier(call_args[2])
      local declared_fx = declared_targets(
        "%f[%w_]local%s+([%a_][%w_]*)%s*=%s*reaper%.TrackFX_GetByName%s*%(")
      for name in before:gmatch(
          "%f[%w_]local%s+([%a_][%w_]*)%s*=%s*reaper%.TrackFX_AddByName%s*%(") do
        declared_fx[name] = true
      end
      local has_declared_fx = next(declared_fx) ~= nil
      if fx_arg and has_declared_fx and not declared_fx[fx_arg] then
        findings[#findings + 1] =
          "profile_fx_argument_mismatches_declared_fx_" .. fx_arg
      end
    end
    local specs_open = nil
    local paren_depth = 1
    local cursor = call_open + 1
    while cursor <= #stripped and paren_depth > 0 do
      local char = stripped:sub(cursor, cursor)
      if char == "(" then
        paren_depth = paren_depth + 1
      elseif char == ")" then
        paren_depth = paren_depth - 1
      elseif char == "{" and paren_depth == 1 then
        specs_open = cursor
        break
      end
      cursor = cursor + 1
    end
    if not specs_open and call_args then
      local specs_variable = tostring(call_args[3] or ""):match(
        "^%s*([%a_][%w_]*)%s*$")
      if specs_variable then
        local declaration_pattern =
          "%f[%w_]local%s+" .. specs_variable .. "%s*=%s*{"
        local declaration_search = 1
        while true do
          local declaration_start, declaration_open = stripped:find(
            declaration_pattern, declaration_search)
          if not declaration_start or declaration_open >= line_start then break end
          local declaration_depth = 0
          local declaration_close = nil
          local declaration_cursor = declaration_open
          while declaration_cursor < line_start do
            local declaration_char = stripped:sub(
              declaration_cursor, declaration_cursor)
            if declaration_char == "{" then
              declaration_depth = declaration_depth + 1
            elseif declaration_char == "}" then
              declaration_depth = declaration_depth - 1
              if declaration_depth == 0 then
                declaration_close = declaration_cursor
                break
              end
            end
            declaration_cursor = declaration_cursor + 1
          end
          if declaration_close
             and stripped:sub(
               declaration_close + 1, line_start - 1):match("^%s*$") then
            specs_open = declaration_open
          end
          declaration_search = declaration_open + 1
        end
      end
    end
    if not variable then
      findings[#findings + 1] =
        "profile_mapping_result_not_assigned_at_line_"
          .. tostring(select(2,
            stripped:sub(1, call_start):gsub("\n", "\n")) + 1)
    elseif resolver_variables[variable] then
      findings[#findings + 1] =
        "profile_mapping_variable_reused_" .. variable
    elseif not specs_open then
      findings[#findings + 1] =
        "profile_mapping_specs_unavailable_" .. variable
    else
      local brace_depth = 0
      local spec_count = 0
      local specs_close = nil
      cursor = specs_open
      while cursor <= #stripped do
        local char = stripped:sub(cursor, cursor)
        if char == "{" then
          brace_depth = brace_depth + 1
          if brace_depth == 2 then spec_count = spec_count + 1 end
        elseif char == "}" then
          brace_depth = brace_depth - 1
          if brace_depth == 0 then
            specs_close = cursor
            break
          end
        end
        cursor = cursor + 1
      end
      if not specs_close or spec_count == 0 then
        findings[#findings + 1] =
          "profile_mapping_specs_unavailable_" .. variable
      else
        resolver_variables[variable] = {
          spec_count = spec_count,
          error_variable = error_variable,
          call_close = call_close,
        }
        resolver_order[#resolver_order + 1] = variable
      end
    end
    resolver_search = call_open + 1
  end
  for _, variable in ipairs(resolver_order) do
    local resolver_info = resolver_variables[variable]
    local spec_count = resolver_info.spec_count
    local referenced = {}
    for ordinal in stripped:gmatch(
        "%f[%w_]" .. variable .. "%s*%[%s*(%d+)%s*%]") do
      local numeric = tonumber(ordinal)
      if numeric then
        referenced[numeric] = true
        if numeric < 1 or numeric > spec_count then
          findings[#findings + 1] =
            "profile_mapping_ordinal_out_of_range_" .. variable .. "_"
              .. tostring(numeric) .. "_of_" .. tostring(spec_count)
        end
      end
    end
    for ordinal = 1, spec_count do
      if not referenced[ordinal] then
        findings[#findings + 1] =
          "profile_mapping_ordinal_unused_" .. variable .. "_"
            .. tostring(ordinal) .. "_of_" .. tostring(spec_count)
      end
    end
    if not resolver_info.error_variable then
      findings[#findings + 1] =
        "profile_mapping_error_result_missing_" .. variable
    else
      local after_call = (resolver_info.call_close or 0) + 1
      local first_use = stripped:find(
        "%f[%w_]" .. variable .. "%s*%[", after_call)
      local guard_region = stripped:sub(
        after_call, first_use and (first_use - 1) or #stripped)
      local correct_guard =
        "if%s+not%s+" .. variable
          .. "%s+then%s+error%s*%(%s*" .. resolver_info.error_variable
          .. "%s*%)%s*end"
      local return_guard_body = guard_region:match(
        "if%s+not%s+" .. variable
          .. "%s+then%s*(.-)%s*%f[%w_]end%f[%W]")
      local simple_return_guard =
        return_guard_body
        and return_guard_body:find("%f[%w_]return%f[%W]")
        and not return_guard_body:find("%f[%w_]else%f[%W]")
        and not return_guard_body:find("%f[%w_]elseif%f[%W]")
        and not return_guard_body:find("%f[%w_]if%f[%W]")
        and not return_guard_body:find("%f[%w_]for%f[%W]")
        and not return_guard_body:find("%f[%w_]while%f[%W]")
        and not return_guard_body:find("%f[%w_]repeat%f[%W]")
        and not return_guard_body:find("%f[%w_]function%f[%W]")
      if not guard_region:find(correct_guard) and not simple_return_guard then
        findings[#findings + 1] =
          "profile_mapping_guard_missing_" .. variable .. "_"
            .. resolver_info.error_variable
      end
    end
  end

  local line_no = 0
  for line in (stripped .. "\n"):gmatch("([^\n]*)\n") do
    line_no = line_no + 1
    local third = line:match(
      "reaper%.TrackFX_SetParamNormalized%s*%([^,]+,[^,]+,%s*([^,%)]*)")
      or line:match(
        "reaper%.TrackFX_SetParam%s*%([^,]+,[^,]+,%s*([^,%)]*)")
      or line:match(
        "%f[%w_]set_param_display%s*%([^,]+,[^,]+,%s*([^,%)]*)")
      or line:match(
        "%f[%w_]set_param_enum%s*%([^,]+,[^,]+,%s*([^,%)]*)")
      or line:match(
        "%f[%w_]set_param_enum_paced%s*%([^,]+,[^,]+,%s*([^,%)]*)")
    if third and third:match("^%s*[%+%-]?%d+%s*$") then
      findings[#findings + 1] =
        "literal_parameter_index_at_line_" .. tostring(line_no)
    elseif third then
      for _, variable in ipairs(resolver_order) do
        if third:find(
            "%f[%w_]" .. variable .. "%s*%[")
           and not third:match(
             "^%s*" .. variable .. "%s*%[%s*%d+%s*%]%s*$") then
          findings[#findings + 1] =
            "profile_mapping_index_expression_at_line_" .. tostring(line_no)
          break
        end
      end
    end
  end
  if #findings == 0 then return nil end
  return findings
end

function Code.find_unproven_generic_param_writes(lua_code, profile_receipts)
  local _, findings =
    Code.parameter_write_authorization_map(lua_code, profile_receipts)
  return findings
end

function Code.build_run_result(code_type, code, run_status, validation_status,
                               opts)
  opts = opts or {}
  local before = tonumber(opts.change_count_before)
  local after  = tonumber(opts.change_count_after)
  local result = {
    code_type = code_type or "lua",
    byte_count = type(code) == "string" and #code or tonumber(code) or 0,
    run_status = run_status or "unknown",
    validation_status = validation_status or "not_applicable",
    observable_change_status = "unknown",
  }
  if opts.auto_ran ~= nil then result.auto_ran = opts.auto_ran == true end
  if opts.deferred ~= nil then result.deferred = opts.deferred == true end
  if opts.deferred_pending ~= nil then
    result.deferred_pending = opts.deferred_pending == true
  end
  if opts.generated_refresh_recovered ~= nil then
    result.generated_refresh_recovered =
      opts.generated_refresh_recovered == true
  end
  if tonumber(opts.generated_refresh_recovery_count) then
    result.generated_refresh_recovery_count =
      tonumber(opts.generated_refresh_recovery_count)
  end
  if opts.auto_run_block_reason then
    result.auto_run_block_reason = tostring(opts.auto_run_block_reason)
  end
  if opts.validation_block_kind then
    result.validation_block_kind = tostring(opts.validation_block_kind)
  end
  if opts.error_kind then result.error_kind = tostring(opts.error_kind) end
  if opts.error_debug ~= nil then result.error_debug = opts.error_debug end
  if type(opts.parameter_change_evidence) == "table" then
    result.parameter_change_evidence = opts.parameter_change_evidence
    result.parameter_change_status =
      tostring(opts.parameter_change_evidence.status or "unknown")
  end
  if opts.runtime_error then
    result.runtime_error = Log.scrub_url_secrets(tostring(opts.runtime_error))
  end
  if before ~= nil and after ~= nil then
    result.change_evidence = {
      project_state_change_count_before = before,
      project_state_change_count_after = after,
    }
    if after ~= before then
      result.observable_change_status = "changed"
      result.project_state_change_delta = after - before
    else
      result.observable_change_status = "unchanged"
      result.project_state_change_delta = 0
    end
  end
  return result
end

function Code.generated_code_descriptor(code, code_type, opts)
  if type(code) ~= "string" or code == "" then return nil end
  opts = opts or {}
  local desc = {
    code_type = code_type or "lua",
    byte_count = #code,
    content_field = opts.content_field or "code_block",
    content_hash_scope = "raw",
  }
  if type(Diag) == "table" and type(Diag.content_hash) == "function" then
    desc.content_hash = Diag.content_hash(code)
  end
  if code_type == "typed_actions" then
    desc.artifact_name = "typed_action_plan.json"
  elseif code_type == "jsfx" then
    desc.artifact_name = "generated_code.jsfx"
  else
    desc.artifact_name = "generated_code.lua"
  end
  return desc
end

function Code.typed_actions_artifact_text(text, allow_raw_json)
  if type(text) ~= "string" or text == "" then return nil end
  local trimmed = text:match("^%s*(.-)%s*$") or ""
  if allow_raw_json and trimmed:sub(1, 1) == "{" then return trimmed end
  if type(Code.extract_typed_actions) == "function" then
    local raw = Code.extract_typed_actions(text)
    if type(raw) == "string" and raw ~= "" then return raw end
  end
  return nil
end

function Code.typed_actions_action_count(metrics, plan_text)
  local count = 0
  local counts = type(metrics) == "table" and metrics.op_counts or nil
  if type(counts) == "table" then
    for _, n in pairs(counts) do
      count = count + (tonumber(n) or 0)
    end
  end
  if count == 0 and type(plan_text) == "string" and plan_text ~= ""
     and type(Code.typed_actions_plan_from_text) == "function" then
    local plan = Code.typed_actions_plan_from_text(plan_text,
      { allow_raw_json = true })
    if type(plan) == "table" and type(plan.actions) == "table" then
      count = #plan.actions
    end
  end
  return count
end

function Code.typed_actions_op_counts_text(counts)
  if type(counts) ~= "table" then return "" end
  local order = {
    "track.create", "track.ensure", "track.resolve", "track.set", "track.pan_lfo",
    "track.folder", "fx.add_stock", "fx.set_param", "send.create",
  }
  local parts = {}
  for _, op in ipairs(order) do
    local n = tonumber(counts[op]) or 0
    if n > 0 then parts[#parts + 1] = op .. " x" .. tostring(n) end
  end
  return table.concat(parts, ", ")
end

function Code.typed_actions_kind_label(metrics)
  local counts = type(metrics) == "table" and metrics.op_counts or nil
  local function label(key, fallback)
    if I18N and I18N.t then
      local text = I18N.t(key)
      if type(text) == "string" and text ~= "" and text ~= key then
        return text
      end
    end
    return fallback
  end
  if type(counts) ~= "table" then
    return label("typed_actions.kind.project_edit", "Project edit")
  end
  local function n(op) return tonumber(counts[op]) or 0 end
  if n("track.pan_lfo") > 0 then
    return label("typed_actions.kind.pan_automation", "Pan automation")
  end
  if n("send.create") > 0 then
    return label("typed_actions.kind.routing", "Routing")
  end
  if n("track.folder") > 0 then
    return label("typed_actions.kind.folder_setup", "Folder setup")
  end
  if n("fx.add_stock") > 0 or n("fx.set_param") > 0 then
    return label("typed_actions.kind.fx_setup", "FX setup")
  end
  if n("track.set") > 0 then
    return label("typed_actions.kind.track_update", "Track update")
  end
  if n("track.create") > 0 or n("track.ensure") > 0 then
    return label("typed_actions.kind.track_setup", "Track setup")
  end
  return label("typed_actions.kind.project_edit", "Project edit")
end

local TYPED_ACTIONS_RECEIPT_PACK
local TYPED_ACTIONS_RECEIPT_EN

function Code._typed_actions_receipt_pack()
  if TYPED_ACTIONS_RECEIPT_PACK then
    return TYPED_ACTIONS_RECEIPT_PACK, TYPED_ACTIONS_RECEIPT_EN
  end
  local en = {
    created_tracks = "Created {n} new tracks.",
    reused_tracks = "Reused {n} existing tracks.",
    no_tracks_created = "No tracks were created.",
    checked_tracks = "Checked {n} tracks.",
    created_missing_reused =
      "Created missing tracks and reused matching existing tracks.",
    setup_tracks = "Set up {n} tracks ({parts}).",
    part_created = "created {n} new tracks",
    part_reused = "reused {n} existing tracks",
    part_checked = "checked {n} tracks",
    names = "Names: {value}",
    created = "Created: {value}",
    already_existed = "Already existed: {value}",
    created_or_found = "Created or found: {value}",
    target = "Target: {value}",
    applied = "Applied structured edit.",
  }
  local pack = {
    English = en,
    Spanish = {
      created_tracks = "Pistas nuevas creadas: {n}.",
      reused_tracks = "Pistas existentes reutilizadas: {n}.",
      no_tracks_created = "No se crearon pistas.",
      checked_tracks = "Pistas comprobadas: {n}.",
      created_missing_reused =
        "Se crearon las pistas faltantes y se reutilizaron las existentes.",
      setup_tracks = "Pistas configuradas: {n} ({parts}).",
      part_created = "creadas: {n}",
      part_reused = "reutilizadas: {n}",
      part_checked = "comprobadas: {n}",
      names = "Nombres: {value}",
      created = "Creadas: {value}",
      already_existed = "Ya existían: {value}",
      created_or_found = "Creadas o encontradas: {value}",
      target = "Destino: {value}",
      applied = "Edición estructurada aplicada.",
    },
    French = {
      created_tracks = "Nouvelles pistes créées : {n}.",
      reused_tracks = "Pistes existantes réutilisées : {n}.",
      no_tracks_created = "Aucune piste n'a été créée.",
      checked_tracks = "Pistes vérifiées : {n}.",
      created_missing_reused =
        "Les pistes manquantes ont été créées et les pistes existantes correspondantes réutilisées.",
      setup_tracks = "Pistes configurées : {n} ({parts}).",
      part_created = "créées : {n}",
      part_reused = "réutilisées : {n}",
      part_checked = "vérifiées : {n}",
      names = "Noms : {value}",
      created = "Créées : {value}",
      already_existed = "Existaient déjà : {value}",
      created_or_found = "Créées ou trouvées : {value}",
      target = "Cible : {value}",
      applied = "Modification structurée appliquée.",
    },
    German = {
      created_tracks = "Neue Spuren erstellt: {n}.",
      reused_tracks = "Vorhandene Spuren wiederverwendet: {n}.",
      no_tracks_created = "Es wurden keine Spuren erstellt.",
      checked_tracks = "Spuren geprüft: {n}.",
      created_missing_reused =
        "Fehlende Spuren wurden erstellt und passende vorhandene Spuren wiederverwendet.",
      setup_tracks = "Spuren eingerichtet: {n} ({parts}).",
      part_created = "erstellt: {n}",
      part_reused = "wiederverwendet: {n}",
      part_checked = "geprüft: {n}",
      names = "Namen: {value}",
      created = "Erstellt: {value}",
      already_existed = "Bereits vorhanden: {value}",
      created_or_found = "Erstellt oder gefunden: {value}",
      target = "Ziel: {value}",
      applied = "Strukturierte Bearbeitung angewendet.",
    },
    Italian = {
      created_tracks = "Nuove tracce create: {n}.",
      reused_tracks = "Tracce esistenti riutilizzate: {n}.",
      no_tracks_created = "Non sono state create tracce.",
      checked_tracks = "Tracce controllate: {n}.",
      created_missing_reused =
        "Sono state create le tracce mancanti e riutilizzate quelle esistenti corrispondenti.",
      setup_tracks = "Tracce configurate: {n} ({parts}).",
      part_created = "create: {n}",
      part_reused = "riutilizzate: {n}",
      part_checked = "controllate: {n}",
      names = "Nomi: {value}",
      created = "Create: {value}",
      already_existed = "Già esistenti: {value}",
      created_or_found = "Create o trovate: {value}",
      target = "Destinazione: {value}",
      applied = "Modifica strutturata applicata.",
    },
    Portuguese = {
      created_tracks = "Novas faixas criadas: {n}.",
      reused_tracks = "Faixas existentes reutilizadas: {n}.",
      no_tracks_created = "Nenhuma faixa foi criada.",
      checked_tracks = "Faixas verificadas: {n}.",
      created_missing_reused =
        "As faixas ausentes foram criadas e as existentes correspondentes foram reutilizadas.",
      setup_tracks = "Faixas configuradas: {n} ({parts}).",
      part_created = "criadas: {n}",
      part_reused = "reutilizadas: {n}",
      part_checked = "verificadas: {n}",
      names = "Nomes: {value}",
      created = "Criadas: {value}",
      already_existed = "Já existiam: {value}",
      created_or_found = "Criadas ou encontradas: {value}",
      target = "Destino: {value}",
      applied = "Edição estruturada aplicada.",
    },
    Dutch = {
      created_tracks = "Nieuwe tracks aangemaakt: {n}.",
      reused_tracks = "Bestaande tracks hergebruikt: {n}.",
      no_tracks_created = "Er zijn geen tracks aangemaakt.",
      checked_tracks = "Tracks gecontroleerd: {n}.",
      created_missing_reused =
        "Ontbrekende tracks zijn aangemaakt en overeenkomende bestaande tracks zijn hergebruikt.",
      setup_tracks = "Tracks ingesteld: {n} ({parts}).",
      part_created = "aangemaakt: {n}",
      part_reused = "hergebruikt: {n}",
      part_checked = "gecontroleerd: {n}",
      names = "Namen: {value}",
      created = "Aangemaakt: {value}",
      already_existed = "Bestonden al: {value}",
      created_or_found = "Aangemaakt of gevonden: {value}",
      target = "Doel: {value}",
      applied = "Gestructureerde bewerking toegepast.",
    },
    Polish = {
      created_tracks = "Utworzono nowe ścieżki: {n}.",
      reused_tracks = "Użyto istniejących ścieżek: {n}.",
      no_tracks_created = "Nie utworzono nowych ścieżek.",
      checked_tracks = "Sprawdzono ścieżki: {n}.",
      created_missing_reused =
        "Utworzono brakujące ścieżki i użyto pasujących istniejących ścieżek.",
      setup_tracks = "Skonfigurowano ścieżki: {n} ({parts}).",
      part_created = "utworzono: {n}",
      part_reused = "użyto istniejących: {n}",
      part_checked = "sprawdzono: {n}",
      names = "Nazwy: {value}",
      created = "Utworzono: {value}",
      already_existed = "Już istniały: {value}",
      created_or_found = "Utworzono lub znaleziono: {value}",
      target = "Cel: {value}",
      applied = "Zastosowano edycję strukturalną.",
    },
    Swedish = {
      created_tracks = "Nya spår skapade: {n}.",
      reused_tracks = "Befintliga spår återanvända: {n}.",
      no_tracks_created = "Inga spår skapades.",
      checked_tracks = "Spår kontrollerade: {n}.",
      created_missing_reused =
        "Saknade spår skapades och matchande befintliga spår återanvändes.",
      setup_tracks = "Spår inställda: {n} ({parts}).",
      part_created = "skapade: {n}",
      part_reused = "återanvända: {n}",
      part_checked = "kontrollerade: {n}",
      names = "Namn: {value}",
      created = "Skapade: {value}",
      already_existed = "Fanns redan: {value}",
      created_or_found = "Skapade eller hittade: {value}",
      target = "Mål: {value}",
      applied = "Strukturerad redigering tillämpad.",
    },
    Czech = {
      created_tracks = "Vytvořeny nové stopy: {n}.",
      reused_tracks = "Použity existující stopy: {n}.",
      no_tracks_created = "Nebyly vytvořeny žádné stopy.",
      checked_tracks = "Zkontrolované stopy: {n}.",
      created_missing_reused =
        "Chybějící stopy byly vytvořeny a odpovídající existující stopy použity.",
      setup_tracks = "Nastavené stopy: {n} ({parts}).",
      part_created = "vytvořeno: {n}",
      part_reused = "použito: {n}",
      part_checked = "zkontrolováno: {n}",
      names = "Názvy: {value}",
      created = "Vytvořeno: {value}",
      already_existed = "Již existovaly: {value}",
      created_or_found = "Vytvořeno nebo nalezeno: {value}",
      target = "Cíl: {value}",
      applied = "Strukturovaná úprava použita.",
    },
    Romanian = {
      created_tracks = "Piste noi create: {n}.",
      reused_tracks = "Piste existente reutilizate: {n}.",
      no_tracks_created = "Nu au fost create piste.",
      checked_tracks = "Piste verificate: {n}.",
      created_missing_reused =
        "Pistele lipsă au fost create, iar pistele existente potrivite au fost reutilizate.",
      setup_tracks = "Piste configurate: {n} ({parts}).",
      part_created = "create: {n}",
      part_reused = "reutilizate: {n}",
      part_checked = "verificate: {n}",
      names = "Nume: {value}",
      created = "Create: {value}",
      already_existed = "Existau deja: {value}",
      created_or_found = "Create sau găsite: {value}",
      target = "Țintă: {value}",
      applied = "Editare structurată aplicată.",
    },
    Turkish = {
      created_tracks = "Yeni kanallar oluşturuldu: {n}.",
      reused_tracks = "Mevcut kanallar yeniden kullanıldı: {n}.",
      no_tracks_created = "Kanal oluşturulmadı.",
      checked_tracks = "Kanallar kontrol edildi: {n}.",
      created_missing_reused =
        "Eksik kanallar oluşturuldu ve eşleşen mevcut kanallar yeniden kullanıldı.",
      setup_tracks = "Kanallar ayarlandı: {n} ({parts}).",
      part_created = "oluşturuldu: {n}",
      part_reused = "yeniden kullanıldı: {n}",
      part_checked = "kontrol edildi: {n}",
      names = "Adlar: {value}",
      created = "Oluşturuldu: {value}",
      already_existed = "Zaten vardı: {value}",
      created_or_found = "Oluşturuldu veya bulundu: {value}",
      target = "Hedef: {value}",
      applied = "Yapılandırılmış düzenleme uygulandı.",
    },
    ["Simplified Chinese"] = {
      created_tracks = "已创建新轨道：{n}。",
      reused_tracks = "已复用现有轨道：{n}。",
      no_tracks_created = "未创建轨道。",
      checked_tracks = "已检查轨道：{n}。",
      created_missing_reused = "已创建缺少的轨道并复用匹配的现有轨道。",
      setup_tracks = "已设置轨道：{n}（{parts}）。",
      part_created = "已创建：{n}",
      part_reused = "已复用：{n}",
      part_checked = "已检查：{n}",
      names = "名称：{value}",
      created = "已创建：{value}",
      already_existed = "已存在：{value}",
      created_or_found = "已创建或找到：{value}",
      target = "目标：{value}",
      applied = "已应用结构化编辑。",
    },
    ["Traditional Chinese"] = {
      created_tracks = "已建立新軌道：{n}。",
      reused_tracks = "已重用現有軌道：{n}。",
      no_tracks_created = "未建立軌道。",
      checked_tracks = "已檢查軌道：{n}。",
      created_missing_reused = "已建立缺少的軌道並重用相符的現有軌道。",
      setup_tracks = "已設定軌道：{n}（{parts}）。",
      part_created = "已建立：{n}",
      part_reused = "已重用：{n}",
      part_checked = "已檢查：{n}",
      names = "名稱：{value}",
      created = "已建立：{value}",
      already_existed = "已存在：{value}",
      created_or_found = "已建立或找到：{value}",
      target = "目標：{value}",
      applied = "已套用結構化編輯。",
    },
    Japanese = {
      created_tracks = "新しいトラックを作成しました: {n}。",
      reused_tracks = "既存のトラックを再利用しました: {n}。",
      no_tracks_created = "トラックは作成されませんでした。",
      checked_tracks = "トラックを確認しました: {n}。",
      created_missing_reused =
        "不足しているトラックを作成し、一致する既存トラックを再利用しました。",
      setup_tracks = "トラックを設定しました: {n}（{parts}）。",
      part_created = "作成: {n}",
      part_reused = "再利用: {n}",
      part_checked = "確認: {n}",
      names = "名前: {value}",
      created = "作成: {value}",
      already_existed = "既存: {value}",
      created_or_found = "作成または検出: {value}",
      target = "対象: {value}",
      applied = "構造化編集を適用しました。",
    },
    Korean = {
      created_tracks = "새 트랙을 생성했습니다: {n}.",
      reused_tracks = "기존 트랙을 재사용했습니다: {n}.",
      no_tracks_created = "트랙을 생성하지 않았습니다.",
      checked_tracks = "트랙을 확인했습니다: {n}.",
      created_missing_reused =
        "없는 트랙을 생성하고 일치하는 기존 트랙을 재사용했습니다.",
      setup_tracks = "트랙을 설정했습니다: {n}({parts}).",
      part_created = "생성: {n}",
      part_reused = "재사용: {n}",
      part_checked = "확인: {n}",
      names = "이름: {value}",
      created = "생성: {value}",
      already_existed = "이미 있음: {value}",
      created_or_found = "생성 또는 찾음: {value}",
      target = "대상: {value}",
      applied = "구조화 편집을 적용했습니다.",
    },
    Vietnamese = {
      created_tracks = "Đã tạo track mới: {n}.",
      reused_tracks = "Đã dùng lại track hiện có: {n}.",
      no_tracks_created = "Không tạo track mới.",
      checked_tracks = "Đã kiểm tra track: {n}.",
      created_missing_reused =
        "Đã tạo các track còn thiếu và dùng lại các track hiện có phù hợp.",
      setup_tracks = "Đã thiết lập track: {n} ({parts}).",
      part_created = "đã tạo: {n}",
      part_reused = "đã dùng lại: {n}",
      part_checked = "đã kiểm tra: {n}",
      names = "Tên: {value}",
      created = "Đã tạo: {value}",
      already_existed = "Đã tồn tại: {value}",
      created_or_found = "Đã tạo hoặc tìm thấy: {value}",
      target = "Đích: {value}",
      applied = "Đã áp dụng chỉnh sửa có cấu trúc.",
    },
    Indonesian = {
      created_tracks = "Track baru dibuat: {n}.",
      reused_tracks = "Track yang sudah ada digunakan kembali: {n}.",
      no_tracks_created = "Tidak ada track yang dibuat.",
      checked_tracks = "Track diperiksa: {n}.",
      created_missing_reused =
        "Track yang belum ada dibuat dan track yang sudah ada yang cocok digunakan kembali.",
      setup_tracks = "Track disiapkan: {n} ({parts}).",
      part_created = "dibuat: {n}",
      part_reused = "digunakan kembali: {n}",
      part_checked = "diperiksa: {n}",
      names = "Nama: {value}",
      created = "Dibuat: {value}",
      already_existed = "Sudah ada: {value}",
      created_or_found = "Dibuat atau ditemukan: {value}",
      target = "Target: {value}",
      applied = "Edit terstruktur diterapkan.",
    },
    Russian = {
      created_tracks = "Создано новых треков: {n}.",
      reused_tracks = "Использовано существующих треков: {n}.",
      no_tracks_created = "Новые треки не создавались.",
      checked_tracks = "Проверено треков: {n}.",
      created_missing_reused =
        "Недостающие треки созданы, совпадающие существующие треки использованы.",
      setup_tracks = "Настроено треков: {n} ({parts}).",
      part_created = "создано: {n}",
      part_reused = "использовано существующих: {n}",
      part_checked = "проверено: {n}",
      names = "Имена: {value}",
      created = "Созданы: {value}",
      already_existed = "Уже существовали: {value}",
      created_or_found = "Созданы или найдены: {value}",
      target = "Цель: {value}",
      applied = "Структурное изменение применено.",
    },
    Ukrainian = {
      created_tracks = "Створено нових треків: {n}.",
      reused_tracks = "Використано наявних треків: {n}.",
      no_tracks_created = "Нові треки не створювалися.",
      checked_tracks = "Перевірено треків: {n}.",
      created_missing_reused =
        "Відсутні треки створено, відповідні наявні треки використано.",
      setup_tracks = "Налаштовано треків: {n} ({parts}).",
      part_created = "створено: {n}",
      part_reused = "використано наявних: {n}",
      part_checked = "перевірено: {n}",
      names = "Назви: {value}",
      created = "Створено: {value}",
      already_existed = "Уже існували: {value}",
      created_or_found = "Створено або знайдено: {value}",
      target = "Ціль: {value}",
      applied = "Структурну зміну застосовано.",
    },
  }
  pack["Chinese (Simplified)"] = pack["Simplified Chinese"]
  pack["Chinese (Traditional)"] = pack["Traditional Chinese"]
  TYPED_ACTIONS_RECEIPT_PACK = pack
  TYPED_ACTIONS_RECEIPT_EN = en
  return pack, en
end

function Code.typed_actions_receipt_language()
  local lang = (I18N and I18N.prompt_language_name and I18N.prompt_language_name())
    or (CFG.prompt_language_name_for_idx
      and CFG.prompt_language_name_for_idx(prefs.reply_language_idx or 1))
    or (CFG.REPLY_LANGUAGE_CODES and CFG.REPLY_LANGUAGE_CODES[prefs.reply_language_idx or 1])
    or "English"
  local pack, en = Code._typed_actions_receipt_pack()
  local strings = pack[lang] or en
  return function(key, values)
    local template = strings[key] or en[key] or key
    if type(values) == "table" then
      template = template:gsub("{([%w_]+)}", function(name)
        local value = values[name]
        return value ~= nil and tostring(value) or ""
      end)
    end
    return template
  end, lang
end

function Code.typed_actions_localized_track_label(lang, n)
  n = tostring(n or "?")
  local labels = {
    English = "Track {n}",
    Spanish = "Pista {n}",
    French = "Piste {n}",
    German = "Spur {n}",
    Italian = "Traccia {n}",
    Portuguese = "Faixa {n}",
    Dutch = "Track {n}",
    Polish = "Ścieżka {n}",
    Swedish = "Spår {n}",
    Czech = "Stopa {n}",
    Romanian = "Pista {n}",
    Turkish = "Kanal {n}",
    Russian = "Трек {n}",
    Ukrainian = "Трек {n}",
    ["Simplified Chinese"] = "轨道 {n}",
    ["Traditional Chinese"] = "軌道 {n}",
    Japanese = "トラック {n}",
    Korean = "트랙 {n}",
    Vietnamese = "Track {n}",
    Indonesian = "Track {n}",
  }
  labels["Chinese (Simplified)"] = labels["Simplified Chinese"]
  labels["Chinese (Traditional)"] = labels["Traditional Chinese"]
  local template = labels[lang] or labels.English
  return template:gsub("{n}", n)
end

function Code.typed_actions_localized_selected_track_label(lang)
  local labels = {
    English = "selected track",
    Spanish = "pista seleccionada",
    French = "piste sélectionnée",
    German = "ausgewählte Spur",
    Italian = "traccia selezionata",
    Portuguese = "faixa selecionada",
    Dutch = "geselecteerde track",
    Polish = "wybrana ścieżka",
    Swedish = "valt spår",
    Czech = "vybraná stopa",
    Romanian = "pista selectată",
    Turkish = "seçili kanal",
    Russian = "выбранный трек",
    Ukrainian = "вибраний трек",
    ["Simplified Chinese"] = "所选轨道",
    ["Traditional Chinese"] = "所選軌道",
    Japanese = "選択したトラック",
    Korean = "선택한 트랙",
    Vietnamese = "track đã chọn",
    Indonesian = "track terpilih",
  }
  labels["Chinese (Simplified)"] = labels["Simplified Chinese"]
  labels["Chinese (Traditional)"] = labels["Traditional Chinese"]
  return labels[lang] or labels.English
end

function Code.typed_actions_display_text(plan_text, action_results)
  if type(plan_text) ~= "string" or plan_text == ""
     or type(Code.typed_actions_plan_from_text) ~= "function" then
    return nil
  end
  local plan = Code.typed_actions_plan_from_text(plan_text,
    { allow_raw_json = true })
  if type(plan) ~= "table" or type(plan.actions) ~= "table" then
    return nil
  end
  local tr, receipt_lang = Code.typed_actions_receipt_language()
  -- Avoid mixed-language receipts until every detailed phrase has native copy.
  local detail_language_is_english = receipt_lang == "English"

  local results = {}
  for _, r in ipairs(type(action_results) == "table" and action_results or {}) do
    if type(r) == "table" then
      local id = r.id or r.track or r.fx or r.parent
      if r.op and id then
        results[tostring(r.op) .. "|" .. tostring(id)] = r
      end
    end
  end

  local function default_track_number(name)
    if type(name) ~= "string" then return nil end
    return name:match("^Track%s+(%d+)$") or name:match("^track%s+(%d+)$")
  end

  local function display_track_name(name, action)
    local n = default_track_number(name)
    if n and type(action) == "table"
       and (action.op == "track.create" or action.op == "track.ensure") then
      return Code.typed_actions_localized_track_label(receipt_lang, n)
    end
    return name
  end

  local track_names, fx_names, fx_tracks = {}, {}, {}
  for _, action in ipairs(plan.actions) do
    if type(action) == "table" then
      if (action.op == "track.create" or action.op == "track.ensure"
          or action.op == "track.resolve")
         and action.id then
        local r = results[tostring(action.op) .. "|" .. tostring(action.id)]
        local display_name = action.name or (r and r.name)
        display_name = display_track_name(display_name, action)
        track_names[action.id] = display_name
          or (action.selected == true
            and Code.typed_actions_localized_selected_track_label(receipt_lang))
          or (action.selected_index and Code.typed_actions_localized_track_label(
            receipt_lang, action.selected_index))
          or (action.index and Code.typed_actions_localized_track_label(
            receipt_lang, action.index))
          or tostring(action.id)
      elseif action.op == "fx.add_stock" and action.id then
        fx_names[action.id] = action.fx or tostring(action.id)
        fx_tracks[action.id] = action.track
      end
    end
  end

  local function track_label(id)
    return track_names[id] or tostring(id or "?")
  end

  local function join(list, sep)
    return table.concat(list, sep or ", ")
  end

  local function fmt_num(n, suffix)
    if n == nil then return nil end
    local s
    if type(n) == "number" and math.floor(n) == n then
      s = tostring(math.floor(n))
    else
      s = tostring(n)
    end
    return suffix and (s .. suffix) or s
  end

  local function plural(n, singular, plural_form)
    return tostring(n) .. " " .. (n == 1 and singular
      or (plural_form or (singular .. "s")))
  end

  local function append_if(value, list)
    if value and value ~= "" then list[#list + 1] = value end
  end

  local function param_label(k, v)
    local labels = {
      band = "band",
      frequency_hz = "frequency",
      gain_db = "gain",
      threshold_db = "threshold",
      ceiling_db = "ceiling",
      feedback_pct = "feedback",
      feedback_db = "feedback",
      wet_db = "wet",
      dry_db = "dry",
      attack_ms = "attack",
      release_ms = "release",
      hold_ms = "hold",
      rms_ms = "RMS",
      hysteresis_db = "hysteresis",
      room_size = "room size",
      dampening = "dampening",
    }
    local suffix = k:match("_hz$") and " Hz"
      or k:match("_db$") and " dB"
      or k:match("_ms$") and " ms"
      or k:match("_pct$") and "%"
      or nil
    return (labels[k] or tostring(k)) .. " " .. fmt_num(v, suffix)
  end

  local created_tracks, existing_tracks, ensured_tracks = {}, {}, {}
  for _, action in ipairs(plan.actions) do
    if type(action) == "table"
       and (action.op == "track.create" or action.op == "track.ensure") then
      local r = results[tostring(action.op) .. "|" .. tostring(action.id)]
      local name = display_track_name((r and r.name) or action.name, action)
        or tostring(action.id)
      if action.op == "track.create" or (r and r.created == true) then
        created_tracks[#created_tracks + 1] = name
      elseif r and r.created == false then
        existing_tracks[#existing_tracks + 1] = name
      else
        ensured_tracks[#ensured_tracks + 1] = name
      end
    end
  end

  local detail_lines = {}
  local track_action_total =
    #created_tracks + #existing_tracks + #ensured_tracks
  local headline = nil
  if track_action_total > 0 then
    if #created_tracks == track_action_total then
      headline = tr("created_tracks", { n = #created_tracks })
      detail_lines[#detail_lines + 1] =
        tr("names", { value = join(created_tracks) })
    elseif #existing_tracks == track_action_total then
      headline = tr("reused_tracks", { n = #existing_tracks })
      detail_lines[#detail_lines + 1] = tr("no_tracks_created")
      detail_lines[#detail_lines + 1] =
        tr("names", { value = join(existing_tracks) })
    elseif #ensured_tracks == track_action_total then
      headline = tr("checked_tracks", { n = #ensured_tracks })
      detail_lines[#detail_lines + 1] = tr("created_missing_reused")
      detail_lines[#detail_lines + 1] =
        tr("names", { value = join(ensured_tracks) })
    else
      local parts = {}
      if #created_tracks > 0 then
        parts[#parts + 1] = tr("part_created", { n = #created_tracks })
      end
      if #existing_tracks > 0 then
        parts[#parts + 1] = tr("part_reused", { n = #existing_tracks })
      end
      if #ensured_tracks > 0 then
        parts[#parts + 1] = tr("part_checked", { n = #ensured_tracks })
      end
      headline = tr("setup_tracks", {
        n = track_action_total,
        parts = join(parts),
      })
      if #created_tracks > 0 then
        detail_lines[#detail_lines + 1] =
          tr("created", { value = join(created_tracks) })
      end
      if #existing_tracks > 0 then
        detail_lines[#detail_lines + 1] =
          tr("already_existed", { value = join(existing_tracks) })
      end
      if #ensured_tracks > 0 then
        detail_lines[#detail_lines + 1] =
          tr("created_or_found", { value = join(ensured_tracks) })
      end
    end
  end

  for _, action in ipairs(plan.actions) do
    if type(action) == "table"
       and action.op ~= "track.create"
       and action.op ~= "track.ensure" then
      if action.op == "track.resolve" then
        detail_lines[#detail_lines + 1] =
          tr("target", { value = track_label(action.id) })

      elseif action.op == "track.set" then
        if detail_language_is_english then
          local props = {}
          append_if(action.name ~= nil and ("renamed to " .. tostring(action.name)) or nil, props)
          append_if(action.volume_db ~= nil and ("volume " .. fmt_num(action.volume_db, " dB")) or nil, props)
          append_if(action.pan_pct ~= nil and ("pan " .. fmt_num(action.pan_pct, "%")) or nil, props)
          append_if(action.mute ~= nil and (action.mute and "muted" or "unmuted") or nil, props)
          append_if(action.solo ~= nil and (action.solo and "soloed" or "unsoloed") or nil, props)
          if action.master_send ~= nil then
            props[#props + 1] = action.master_send and "master send on" or "master send off"
          end
          headline = headline or ("Updated " .. track_label(action.track) .. ".")
          detail_lines[#detail_lines + 1] = "Changed settings: "
            .. join(props)
        else
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", { value = track_label(action.track) })
        end

      elseif action.op == "track.pan_lfo" then
        if detail_language_is_english then
          local parts = {
            fmt_num(action.bars, " bars"),
            fmt_num(action.cycles_per_bar, " cycles/bar"),
            fmt_num(action.depth_pct or 100, "% depth"),
            tostring(action.resolution or "32nd") .. " resolution",
          }
          headline = headline or ("Wrote pan automation on " .. track_label(action.track) .. ".")
          detail_lines[#detail_lines + 1] = "Pan LFO: " .. join(parts)
        else
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", { value = track_label(action.track) })
        end

      elseif action.op == "track.folder" then
        local children = {}
        for _, child in ipairs(type(action.children) == "table" and action.children or {}) do
          children[#children + 1] = track_label(child)
        end
        if detail_language_is_english then
          headline = headline or ("Created folder " .. track_label(action.parent) .. ".")
          detail_lines[#detail_lines + 1] = "Folder children: " .. join(children)
        else
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", { value = track_label(action.parent) })
          if #children > 0 then
            detail_lines[#detail_lines + 1] =
              tr("names", { value = join(children) })
          end
        end

      elseif action.op == "fx.add_stock" then
        local r = results["fx.add_stock|" .. tostring(action.id)]
        if detail_language_is_english then
          local verb = (r and r.existed == true) and "Used existing" or "Added"
          headline = headline or (verb .. " stock FX.")
          detail_lines[#detail_lines + 1] = verb .. " " .. tostring(action.fx)
            .. " on " .. track_label(action.track)
        else
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", {
              value = track_label(action.track) .. ": " .. tostring(action.fx),
            })
        end

      elseif action.op == "fx.set_param" then
        local fx_name = fx_names[action.fx] or tostring(action.fx)
        local track_id = fx_tracks[action.fx]
        if detail_language_is_english then
          local params = {}
          for k, v in pairs(type(action.params) == "table" and action.params or {}) do
            params[#params + 1] = param_label(k, v)
          end
          table.sort(params)
          local suffix = track_id and (" on " .. track_label(track_id)) or ""
          headline = headline or ("Set " .. fx_name .. ".")
          detail_lines[#detail_lines + 1] = "Set " .. fx_name .. suffix
            .. ": " .. join(params)
        else
          local target = track_id and (track_label(track_id) .. ": " .. fx_name)
            or fx_name
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", { value = target })
        end

      elseif action.op == "send.create" then
        if detail_language_is_english then
          local props = {}
          if action.volume_db ~= nil then props[#props + 1] = fmt_num(action.volume_db, " dB") end
          if action.pan ~= nil then props[#props + 1] = "pan " .. tostring(action.pan) end
          if action.mode ~= nil then props[#props + 1] = tostring(action.mode) end
          if action.muted ~= nil then props[#props + 1] = action.muted and "muted" or "unmuted" end
          local tail = #props > 0 and (" (" .. join(props) .. ")") or ""
          headline = headline or "Created routing."
          detail_lines[#detail_lines + 1] = "Send: " .. track_label(action["from"])
            .. " -> " .. track_label(action.to) .. tail
        else
          headline = headline or tr("applied")
          detail_lines[#detail_lines + 1] =
            tr("target", {
              value = track_label(action["from"]) .. " -> "
                .. track_label(action.to),
            })
        end
      end
    end
  end

  headline = headline or tr("applied")
  if #detail_lines == 0 then return headline end
  return headline .. "\n" .. join(detail_lines, "\n")
end

function Code.apply_run_result_to_message(msg, ok, code_type, code, auto_ran,
    completed_result)
  if type(msg) ~= "table" then return end
  local rr = {}
  if type(completed_result) == "table" then
    for k, v in pairs(completed_result) do rr[k] = v end
  elseif type(S) == "table" and type(S.last_run_result) == "table" then
    for k, v in pairs(S.last_run_result) do rr[k] = v end
  else
    -- Defensive fallback for future callers; current UI paths call Code.run first.
    rr = Code.build_run_result(code_type or "lua", code,
      ok and "ran_ok" or "errored", ok and "passed" or "failed", {
        auto_ran = auto_ran == true,
        error_kind = ok and nil or "runtime_error",
        runtime_error = (type(S) == "table" and S.last_run_error) or nil,
      })
  end
  rr.auto_ran = auto_ran == true
  rr.code_type = code_type or rr.code_type or "lua"
  msg.run_result = rr
  msg.run_status = rr.run_status
  msg.validation_status = rr.validation_status
  msg.observable_change_status = rr.observable_change_status
  msg.change_evidence = rr.change_evidence
  msg.parameter_change_status = rr.parameter_change_status
  msg.parameter_change_evidence = rr.parameter_change_evidence
  msg.runtime_error = rr.runtime_error
  if rr.error_kind then msg.error_kind = rr.error_kind end
  if rr.error_debug and not msg.error_debug then msg.error_debug = rr.error_debug end
  msg.code_block_present = (type(code or msg.code_block) == "string"
    and (code or msg.code_block) ~= "")
  msg.generated_code = msg.generated_code
    or Code.generated_code_descriptor(code or msg.code_block, code_type)
  if type(msg.validation_trace) == "table"
     and type(msg.run_result) == "table"
     and msg.run_result.validation_trace == nil then
    msg.run_result.validation_trace = msg.validation_trace
  end
end

function Code.bind_pending_deferred_run(message_idx, history_idx, auto_ran,
    probe_turn)
  if type(S) ~= "table" or type(S.lua_defer_run) ~= "table"
     or type(S.lua_defer_run.bind) ~= "function" then
    return false
  end
  S.lua_defer_run.bind(message_idx, history_idx, auto_ran, probe_turn)
  return true
end

local CODE_RUN_INSTRUCTION_BUDGET = 25000000
local CODE_RUN_HOOK_COUNT = 10000
local CODE_RUN_BUDGET_TOKEN = "__reaassist_lua_instruction_budget_exceeded__"

local function short_error_excerpt(err_str, max_lines)
  local lines, n = {}, 0
  for line in tostring(err_str or ""):gmatch("[^\n]+") do
    n = n + 1
    if n > (max_lines or 6) then lines[#lines+1] = "  ..."; break end
    lines[#lines+1] = line
  end
  return table.concat(lines, "\n")
end

local function lua_runtime_error_strings(run_err, instruction_timeout)
  local err_str = instruction_timeout
    and ("Generated Lua stopped after exceeding ReaAssist's instruction "
      .. "budget. The script may contain an infinite loop or runaway "
      .. "iteration.")
    or tostring(run_err)
  local short = short_error_excerpt(err_str, 6)
  local fallback = instruction_timeout
    and ("Generated Lua was stopped because it exceeded ReaAssist's "
      .. "instruction budget. It may contain an infinite loop or runaway "
      .. "iteration.\n\n" .. short)
    or ("Runtime error in generated code:\n\n" .. short)
  local key = instruction_timeout
    and "code.runtime_instruction_budget_error" or "code.runtime_error"
  local msg = (RA and RA.t and RA.t(key, { error = short }, fallback))
    or fallback
  return err_str, short, msg
end

local function run_lua_chunk_with_instruction_guard(fn)
  local traceback = debug and debug.traceback or tostring
  if not (debug and debug.sethook and coroutine and coroutine.create
      and coroutine.resume) then
    local ok, err = xpcall(fn, traceback)
    return ok, err, false, nil
  end

  local count = 0
  local function hook()
    count = count + CODE_RUN_HOOK_COUNT
    if count >= CODE_RUN_INSTRUCTION_BUDGET then
      error(CODE_RUN_BUDGET_TOKEN, 0)
    end
  end

  local co = coroutine.create(function()
    return xpcall(fn, traceback)
  end)
  debug.sethook(co, hook, "", CODE_RUN_HOOK_COUNT)
  local resume_ok, ok, err = coroutine.resume(co)
  debug.sethook(co)
  if not resume_ok then
    return false, ok, tostring(ok):find(CODE_RUN_BUDGET_TOKEN, 1, true) ~= nil,
      count
  end
  local timed_out = tostring(err or ""):find(CODE_RUN_BUDGET_TOKEN, 1, true) ~= nil
  return ok, err, timed_out, count
end

function Code.run(code)
  -- A one-shot generated defer keeps ReaAssist's real undo block open until
  -- the callback completes on the next REAPER cycle. Do not let a second run
  -- nest inside that short window or both logical actions could collapse into
  -- one undo entry. In normal UI use this window is shorter than one frame.
  if type(S) == "table" and type(S.lua_defer_run) == "table"
     and (tonumber(S.lua_defer_run.pending) or 0) > 0 then
    local msg = "ReaAssist is still finishing the previous action. "
      .. "Wait a moment, then run this script again."
    Log.line("SCRIPT", "Blocked overlapping run while deferred action pending")
    Log.add_error(msg, nil, nil, nil, {
      error_kind = "runtime_busy",
      error_debug = {
        failure_kind = "runtime_busy",
        source = "generated_lua_defer_overlap_guard",
      },
    })
    return false
  end
  -- A bound deferred callback owns its message through its closure and no
  -- longer needs to monopolize the global slot. Detach it before a later
  -- manual run so its eventual completion cannot overwrite the newer run's
  -- global result; apply_completed_result still finalizes the original row.
  if type(S) == "table" and type(S.lua_defer_run) == "table"
     and S.lua_defer_run.message_idx then
    S.lua_defer_run = nil
  end
  local artifact = Code.classify_lua_artifact(code)
  if not artifact.runnable or artifact.manual_run_only then
    local msg = Code.lua_artifact_block_message(artifact)
    local block_kind = artifact.manual_run_only
      and "action_context_script" or "non-runnable Lua artifact"
    local block_reason = artifact.manual_run_reason or artifact.reason
      or artifact.kind
    local block_debug = {
      failure_kind = "validator_blocked",
      source = "lua_artifact_classifier",
      validation_block_kind = tostring(block_reason or block_kind),
      artifact_kind = tostring(artifact.kind or ""),
      manual_run_only = artifact.manual_run_only == true,
      generated_code_bytes = type(code) == "string" and #code or 0,
    }
    Log.line("SCRIPT", "Blocked " .. block_kind .. ": "
      .. tostring(artifact.kind) .. " / " .. tostring(block_reason))
    Log.add_error(msg, nil, nil, nil,
      { error_kind = "validator_blocked", error_debug = block_debug })
    S.last_run_error = "blocked lua artifact: "
      .. tostring(artifact.kind) .. " / " .. tostring(block_reason)
    S.last_run_result = Code.build_run_result("lua", code,
      artifact.manual_run_only and "blocked_action_context"
        or "blocked_fragment",
      "blocked", {
        validation_block_kind = block_reason,
        error_kind = "validator_blocked",
        error_debug = block_debug,
        runtime_error = S.last_run_error,
      })
    return false
  end

  local forbidden = type(Code.scan_forbidden_sandbox_globals) == "function"
    and Code.scan_forbidden_sandbox_globals(code) or nil
  if forbidden then
    local block_debug = {
      failure_kind = "validator_blocked",
      source = "sandbox_forbidden_global_validator",
      validation_block_kind = "sandbox_forbidden_global",
      forbidden_globals = forbidden,
      generated_code_bytes = type(code) == "string" and #code or 0,
    }
    local msg = "I blocked this script because it references Lua APIs that "
      .. "are unavailable in ReaAssist's execution sandbox: "
      .. tostring(forbidden)
      .. ". Ask ReaAssist to regenerate it without those APIs."
    Log.line("SCRIPT", "Blocked sandbox-forbidden globals: "
      .. tostring(forbidden))
    Log.add_error(msg, nil, nil, nil,
      { error_kind = "validator_blocked", error_debug = block_debug })
    S.last_run_error = "blocked sandbox-forbidden globals: "
      .. tostring(forbidden)
    S.last_run_result = Code.build_run_result("lua", code,
      "blocked_sandbox_api", "blocked", {
        validation_block_kind = "sandbox_forbidden_global",
        error_kind = "validator_blocked",
        error_debug = block_debug,
        runtime_error = S.last_run_error,
      })
    return false
  end

  -- Per-call sandbox: shallow copy the static base and add the print redirect.
  -- Built BEFORE load() so we can pass the env directly via the 4th argument,
  -- which is cleaner and stricter than retrofitting _ENV via debug.setupvalue.
  local code_env = {}
  for k, v in pairs(CODE_SANDBOX_BASE) do code_env[k] = v end
  code_env.math = sandbox_lib_copy(math)
  code_env.string = sandbox_lib_copy(string)
  code_env.table = sandbox_lib_copy(table)
  code_env.gfx = sandbox_api_proxy(gfx, nil, "gfx")
  code_env.print = function(...)
    -- Use select("#", ...) + select(i, ...) rather than {...}/#args: a table
    -- built with `{...}` has an undefined length when the varargs contain nil
    -- (e.g. print(1, nil, 3)), which silently drops trailing arguments.
    local n = select("#", ...)
    local buf = {}
    for i = 1, n do
      local v = tostring((select(i, ...)))
      if i > 1 then reaper.ShowConsoleMsg("\t"); buf[#buf+1] = "\t" end
      reaper.ShowConsoleMsg(v)
      buf[#buf+1] = v
    end
    reaper.ShowConsoleMsg("\n")
    Log.line("SCRIPT", "print: " .. table.concat(buf))
  end

  -- Undo capture state. Generated Begin/End calls are always intercepted so
  -- a throw cannot leave REAPER's undo stack unbalanced. Most scripts use one
  -- real outer block. Fingerprint-authorized, track-FX-only profile edits use
  -- an isolated staging project instead: configure a copied/new FX there,
  -- then apply the verified final parameter values to an existing instance or
  -- copy a newly added instance into the user's project inside one synchronous
  -- Undo block. Existing FX keep their GUID and non-parameter state. The user
  -- project is untouched until that commit, and a failed preparation can be
  -- discarded without rewinding user state.
  local inner_undo_label = nil
  local inner_undo_flags = -1
  local change_count_before = Code.project_change_count()
  local profile_receipts = Code.plugin_profile_receipts_for_code(code)
  local param_write_authorization, param_write_findings =
    Code.parameter_write_authorization_map(code, profile_receipts)
  local function profile_track_fx_staging_eligible()
    if type(profile_receipts) ~= "table" or #profile_receipts == 0 then
      return false, "no_profile_receipt"
    end
    if not code:find("TrackFX_SetParam", 1, true)
       or code:find("TakeFX_", 1, true) then
      return false, "not_track_parameter_only"
    end
    if type(reaper.EnumProjects) ~= "function"
       or type(reaper.Main_OnCommand) ~= "function"
       or type(reaper.SelectProjectInstance) ~= "function"
       or type(reaper.InsertTrackInProject) ~= "function"
       or type(reaper.GetSetProjectInfo) ~= "function"
       or type(reaper.PreventUIRefresh) ~= "function"
       or type(reaper.GetTrack) ~= "function"
       or type(reaper.CountTracks) ~= "function"
       or type(reaper.GetMasterTrack) ~= "function"
       or type(reaper.GetTrackGUID) ~= "function"
       or type(reaper.TrackFX_GetCount) ~= "function"
       or type(reaper.TrackFX_GetFXGUID) ~= "function"
       or type(reaper.TrackFX_GetFXName) ~= "function"
       or type(reaper.TrackFX_CopyToTrack) ~= "function"
       or type(reaper.TrackFX_Delete) ~= "function"
       or type(reaper.Undo_DoUndo2) ~= "function"
       or type(reaper.Undo_BeginBlock2) ~= "function"
       or type(reaper.Undo_EndBlock2) ~= "function" then
      return false, "required_api_unavailable"
    end

    local allowed = {
      defer = true,
      GetTrack = true,
      GetSelectedTrack = true,
      GetMasterTrack = true,
      CountTracks = true,
      GetTrackName = true,
      GetTrackGUID = true,
      GetProjectStateChangeCount = true,
      EnumProjects = true,
      ValidatePtr = true,
      ValidatePtr2 = true,
      TrackFX_AddByName = true,
      TrackFX_GetByName = true,
      TrackFX_GetCount = true,
      TrackFX_GetFXName = true,
      TrackFX_GetNumParams = true,
      TrackFX_GetParam = true,
      TrackFX_GetParamEx = true,
      TrackFX_GetParamName = true,
      TrackFX_GetParamNormalized = true,
      TrackFX_GetFormattedParamValue = true,
      TrackFX_GetNamedConfigParm = true,
      TrackFX_SetParam = true,
      TrackFX_SetParamNormalized = true,
      TrackFX_Show = true,
      ShowMessageBox = true,
      ShowConsoleMsg = true,
      PreventUIRefresh = true,
      UpdateArrange = true,
      TrackList_AdjustWindows = true,
      Undo_BeginBlock = true,
      Undo_BeginBlock2 = true,
      Undo_EndBlock = true,
      Undo_EndBlock2 = true,
    }
    for api in code:gmatch("reaper%.([%a_][%w_]*)%s*%(") do
      if not allowed[api] then
        return false, "non_track_fx_api:" .. tostring(api)
      end
    end
    return true
  end
  local profile_fx_staging_enabled, profile_fx_staging_reason =
    profile_track_fx_staging_eligible()
  if type(profile_receipts) == "table" and #profile_receipts > 0
     and type(Code.find_unguarded_profile_param_writes) == "function" then
    local guard_findings = Code.find_unguarded_profile_param_writes(code)
    local preflight_unsafe = false
    for _, finding in ipairs(guard_findings or {}) do
      if finding == "shadowed_profile_parameter_resolver"
         or tostring(finding):match("^profile_mapping_")
         or (finding == "missing_profile_parameter_resolver"
           and Code.plugin_profile_code_mentions_receipt(
             code, profile_receipts)) then
        preflight_unsafe = true
        break
      end
    end
    if preflight_unsafe then
      local guard_error = "ReaAssist profile parameter guard refused the "
        .. "script because its mapped parameter references were not safe."
      S.last_run_error = guard_error
      S.last_run_result = Code.build_run_result("lua", code,
        "blocked_profile_guard", "blocked", {
          validation_block_kind = "plugin_profile_guard_validator",
          error_kind = "validator_blocked",
          error_debug = {
            failure_kind = "validator_blocked",
            source = "plugin_profile_runtime_preflight",
            findings = guard_findings,
          },
          runtime_error = guard_error,
        })
      Log.add_error("ReaAssist did not run this script because its plug-in "
        .. "parameter mapping could not be verified. Ask ReaAssist to "
        .. "regenerate the track FX script, or adjust the value manually.")
      Code.plugin_test_runtime_event("run_error", {
        code_sha256 = Code.plugin_profile_code_key(code),
        run_result = S.last_run_result,
      })
      return false
    end
  end
  if type(param_write_findings) == "table"
     and #param_write_findings > 0 then
    local guard_error = "ReaAssist parameter provenance validation refused "
      .. "the script because it contains a direct plug-in parameter write "
      .. "without a validated profile mapping or canonical parameter helper."
    S.last_run_error = guard_error
    S.last_run_result = Code.build_run_result("lua", code,
      "blocked_parameter_provenance", "blocked", {
        validation_block_kind = "fx_param_provenance_validator",
        error_kind = "validator_blocked",
        error_debug = {
          failure_kind = "validator_blocked",
          source = "fx_param_provenance_runtime_preflight",
          findings = param_write_findings,
        },
        runtime_error = guard_error,
      })
    Log.add_error("ReaAssist did not run this script because it contains a "
      .. "plug-in parameter change that could not be verified. For "
      .. "take/item FX, adjust the value manually. For track FX, ask "
      .. "ReaAssist to regenerate the script.")
    Code.plugin_test_runtime_event("run_error", {
      code_sha256 = Code.plugin_profile_code_key(code),
      run_result = S.last_run_result,
    })
    return false
  end
  Code.plugin_test_runtime_event("run_started", {
    code_sha256 = Code.plugin_profile_code_key(code),
    profile_authorization_count =
      type(profile_receipts) == "table" and #profile_receipts or 0,
  })
  local defer_state = {
    code = code,
    pending = 0,
    failed = false,
    in_callback = false,
    undo_open = false,
    undo_closed = false,
    undo_project = nil,
    undo_project_api = false,
    profile_fx_staging_enabled = profile_fx_staging_enabled == true,
    profile_fx_staging_reason = profile_fx_staging_reason,
    profile_fx_stage_project = nil,
    profile_fx_stage_track = nil,
    profile_fx_stage_entries = {},
    profile_fx_stage_proxy_map = {},
    profile_fx_stage_real_map = {},
    profile_fx_stage_write_sequence = {},
    profile_fx_stage_next_proxy = 1000000000,
    profile_fx_stage_committed = false,
    profile_fx_stage_focus = nil,
    change_count_before = change_count_before,
    parameter_writes = {},
    profile_resolutions = {},
    profile_target_checks = {},
    param_write_authorization = param_write_authorization or {},
    generated_refresh_balance = 0,
    generated_refresh_recovery_count = 0,
  }

  if type(reaper.EnumProjects) == "function" then
    defer_state.undo_project = reaper.EnumProjects(-1, "")
  end

  local function close_run_undo()
    if defer_state.undo_open and not defer_state.undo_closed then
      if defer_state.undo_project_api
         and type(reaper.Undo_EndBlock2) == "function" then
        if Code.project_pointer_exists(defer_state.undo_project) then
          reaper.Undo_EndBlock2(defer_state.undo_project,
            inner_undo_label or "ReaAssist", inner_undo_flags or -1)
        else
          Log.line("SCRIPT",
            "Skipped Undo_EndBlock2 because the run project no longer exists")
        end
      else
        reaper.Undo_EndBlock(inner_undo_label or "ReaAssist",
          inner_undo_flags or -1)
      end
      defer_state.undo_closed = true
      defer_state.undo_open = false
    end
  end

  local function recover_generated_refresh()
    local held = math.max(0,
      math.floor(tonumber(defer_state.generated_refresh_balance) or 0))
    if held <= 0 then return 0 end
    for _ = 1, held do pcall(reaper.PreventUIRefresh, -1) end
    defer_state.generated_refresh_balance = 0
    defer_state.generated_refresh_recovery_count =
      (tonumber(defer_state.generated_refresh_recovery_count) or 0) + held
    Log.line("SCRIPT", "Recovered " .. tostring(held)
      .. " generated PreventUIRefresh hold(s)")
    return held
  end

  local function profile_stage_pair_key(track, fx)
    return tostring(track) .. "\31" .. tostring(fx)
  end

  local function profile_project_exists(project)
    return Code.project_pointer_exists(project)
  end

  local function restore_profile_stage_focus()
    if defer_state.profile_fx_stage_focus
       and type(reaper.JS_Window_SetFocus) == "function"
       and (type(reaper.JS_Window_IsWindow) ~= "function"
         or reaper.JS_Window_IsWindow(
           defer_state.profile_fx_stage_focus)) then
      pcall(reaper.JS_Window_SetFocus, defer_state.profile_fx_stage_focus)
    end
  end

  local function resolve_profile_target_track(entry)
    local project = defer_state.undo_project
    local track = entry and entry.target_track
    if track and type(reaper.ValidatePtr2) == "function"
       and reaper.ValidatePtr2(project, track, "MediaTrack*")
       and reaper.GetTrackGUID(track) == entry.target_guid then
      return track
    end
    local master = type(reaper.GetMasterTrack) == "function"
      and reaper.GetMasterTrack(project) or nil
    if master and reaper.GetTrackGUID(master) == entry.target_guid then
      entry.target_track = master
      return master
    end
    for i = 0, reaper.CountTracks(project) - 1 do
      local candidate = reaper.GetTrack(project, i)
      if candidate and reaper.GetTrackGUID(candidate) == entry.target_guid then
        entry.target_track = candidate
        return candidate
      end
    end
    return nil
  end

  local function cleanup_profile_fx_stage()
    local stage_project = defer_state.profile_fx_stage_project
    if not stage_project then return true end
    local refresh_held = false
    local stage_closed = false
    local ok, cleanup_err = pcall(function()
      reaper.PreventUIRefresh(1)
      refresh_held = true
      if profile_project_exists(stage_project) then
        reaper.SelectProjectInstance(stage_project)
        reaper.GetSetProjectInfo(stage_project, "DIRTY", 0, true)
        if reaper.GetSetProjectInfo(
            stage_project, "DIRTY", 0, false) ~= 0 then
          error("temporary staging project remained dirty")
        end
        reaper.Main_OnCommand(40860, 0)
        if profile_project_exists(stage_project) then
          error("temporary staging project did not close")
        end
        stage_closed = true
      else
        stage_closed = true
      end
    end)
    if defer_state.undo_project
       and profile_project_exists(defer_state.undo_project) then
      pcall(reaper.SelectProjectInstance, defer_state.undo_project)
    end
    if refresh_held then reaper.PreventUIRefresh(-1) end
    restore_profile_stage_focus()
    if stage_closed then
      defer_state.profile_fx_stage_project = nil
      defer_state.profile_fx_stage_track = nil
    end
    return ok and stage_closed, cleanup_err
  end

  local function ensure_profile_fx_stage()
    if defer_state.profile_fx_stage_track then return true end
    if not defer_state.profile_fx_staging_enabled then
      return false, defer_state.profile_fx_staging_reason
    end
    defer_state.profile_fx_stage_focus =
      type(reaper.JS_Window_GetFocus) == "function"
      and reaper.JS_Window_GetFocus() or nil
    local refresh_held = false
    local ok, stage_err = pcall(function()
      reaper.PreventUIRefresh(1)
      refresh_held = true
      reaper.Main_OnCommand(40859, 0)
      local stage_project = reaper.EnumProjects(-1, "")
      if not stage_project or stage_project == defer_state.undo_project then
        error("temporary project tab did not open")
      end
      defer_state.profile_fx_stage_project = stage_project
      reaper.InsertTrackInProject(stage_project, 0, 0)
      local stage_track = reaper.GetTrack(stage_project, 0)
      if not stage_track then error("temporary track was not created") end
      defer_state.profile_fx_stage_track = stage_track
      reaper.SelectProjectInstance(defer_state.undo_project)
      if reaper.EnumProjects(-1, "") ~= defer_state.undo_project then
        error("original project tab was not restored")
      end
    end)
    if refresh_held then reaper.PreventUIRefresh(-1) end
    restore_profile_stage_focus()
    if not ok then
      cleanup_profile_fx_stage()
      return false, tostring(stage_err)
    end
    return true
  end

  local function register_profile_stage_entry(target_track, target_real_fx,
      target_fx_guid, stage_fx, mode, loaded_name, requested_name)
    local guid = reaper.GetTrackGUID(target_track)
    if type(guid) ~= "string" or guid == "" then
      return nil, "target_track_guid_unavailable"
    end
    local proxy = defer_state.profile_fx_stage_next_proxy
    defer_state.profile_fx_stage_next_proxy = proxy + 1
    local entry = {
      target_track = target_track,
      target_guid = guid,
      target_real_fx = target_real_fx,
      target_fx_guid = target_fx_guid,
      stage_fx = stage_fx,
      proxy_fx = proxy,
      mode = mode,
      loaded_name = loaded_name,
      requested_name = requested_name,
    }
    defer_state.profile_fx_stage_entries[
      #defer_state.profile_fx_stage_entries + 1] = entry
    defer_state.profile_fx_stage_proxy_map[
      profile_stage_pair_key(target_track, proxy)] = entry
    if target_real_fx ~= nil then
      defer_state.profile_fx_stage_real_map[
        profile_stage_pair_key(target_track, target_real_fx)] = entry
    end
    return entry
  end

  local function stage_existing_profile_fx(target_track, target_fx,
      requested_name)
    local real_key = profile_stage_pair_key(target_track, target_fx)
    local existing = defer_state.profile_fx_stage_real_map[real_key]
    if existing then return existing end
    local ok, stage_err = ensure_profile_fx_stage()
    if not ok then return nil, stage_err end
    local name_ok, loaded_name =
      reaper.TrackFX_GetFXName(target_track, target_fx, "")
    if not name_ok then return nil, "target_fx_unavailable" end
    local target_fx_guid = reaper.TrackFX_GetFXGUID(target_track, target_fx)
    if type(target_fx_guid) ~= "string" or target_fx_guid == "" then
      return nil, "target_fx_guid_unavailable"
    end
    local stage_fx = reaper.TrackFX_GetCount(
      defer_state.profile_fx_stage_track)
    reaper.TrackFX_CopyToTrack(target_track, target_fx,
      defer_state.profile_fx_stage_track, stage_fx, false)
    if reaper.TrackFX_GetCount(defer_state.profile_fx_stage_track)
       ~= stage_fx + 1 then
      return nil, "target_fx_copy_to_stage_failed"
    end
    local entry, entry_err = register_profile_stage_entry(
      target_track, target_fx, target_fx_guid, stage_fx, "replace", loaded_name,
      requested_name)
    return entry, entry_err
  end

  local function stage_new_profile_fx(target_track, add_name)
    local ok, stage_err = ensure_profile_fx_stage()
    if not ok then return nil, stage_err end
    local stage_track = defer_state.profile_fx_stage_track
    local before_count = reaper.TrackFX_GetCount(stage_track)
    local stage_fx = reaper.TrackFX_AddByName(
      stage_track, add_name, false, -1)
    if not stage_fx or stage_fx < 0
       or reaper.TrackFX_GetCount(stage_track) ~= before_count + 1 then
      return nil, "plugin_add_to_stage_failed"
    end
    local _, loaded_name = reaper.TrackFX_GetFXName(stage_track, stage_fx, "")
    local entry, entry_err = register_profile_stage_entry(
      target_track, nil, nil, stage_fx, "append",
      loaded_name or tostring(add_name), tostring(add_name))
    return entry, entry_err
  end

  local function profile_fx_name_key(value)
    local key = tostring(value or ""):lower()
      :gsub("^%s+", ""):gsub("%s+$", "")
      :gsub("^[%w%d]+:%s*", "")
      :gsub("%s*%([^()]+%)%s*$", "")
      :gsub("[^%w]+", "")
    return key
  end

  local function find_profile_stage_by_name(target_track, name)
    local requested = profile_fx_name_key(name)
    if requested == "" then return nil end
    for _, entry in ipairs(defer_state.profile_fx_stage_entries) do
      if entry.target_track == target_track then
        local requested_key = profile_fx_name_key(entry.requested_name)
        local loaded_key = profile_fx_name_key(entry.loaded_name)
        if requested == requested_key or requested == loaded_key
           or (loaded_key ~= "" and (loaded_key:find(requested, 1, true)
             or requested:find(loaded_key, 1, true))) then
          return entry
        end
      end
    end
    return nil
  end

  local function profile_stage_entry(target_track, fx, stage_if_missing)
    if not defer_state.profile_fx_staging_enabled then return nil end
    local key = profile_stage_pair_key(target_track, fx)
    local entry = defer_state.profile_fx_stage_proxy_map[key]
      or defer_state.profile_fx_stage_real_map[key]
    if entry or not stage_if_missing then return entry end
    return stage_existing_profile_fx(target_track, fx)
  end

  local function profile_stage_target(target_track, fx, stage_if_missing)
    local entry, stage_err =
      profile_stage_entry(target_track, fx, stage_if_missing)
    if not entry then return nil, nil, stage_err end
    return defer_state.profile_fx_stage_track, entry.stage_fx, nil, entry
  end

  local function show_committed_profile_fx()
    for _, entry in ipairs(defer_state.profile_fx_stage_entries) do
      if entry.show_flag ~= nil then
        local target_track = resolve_profile_target_track(entry)
        if target_track then
          pcall(reaper.TrackFX_Show, target_track, entry.committed_fx,
            entry.show_flag)
        end
      end
    end
  end

  local function profile_formatted_parameter_value(track, fx, pidx)
    if type(reaper.TrackFX_GetFormattedParamValue) ~= "function" then
      return nil
    end
    local ok, first, second = pcall(
      reaper.TrackFX_GetFormattedParamValue, track, fx, pidx, "")
    if not ok then return nil end
    if type(second) == "string" then return second end
    if type(first) == "string" then return first end
    return nil
  end

  -- A generated edit may deliberately set a value that is already present.
  -- The staged copy then proves the request is satisfied, but copying that
  -- identical FX back would still change its GUID, dirty the project, and add
  -- a misleading Undo entry. Suppress that commit only when every staged entry
  -- is an existing FX and every witnessed parameter has a known unchanged final
  -- value. This lane permits no other FX-state mutators, so discarding the
  -- staging project preserves the complete user-project state.
  local function profile_stage_is_verified_noop()
    local evidence = Code.parameter_change_evidence(
      defer_state.parameter_writes)
    if not evidence or (tonumber(evidence.target_count) or 0) < 1
       or (tonumber(evidence.changed_target_count) or 0) ~= 0
       or (tonumber(evidence.unknown_target_count) or 0) ~= 0
       or #defer_state.profile_fx_stage_entries < 1 then
      return false
    end
    for _, entry in ipairs(defer_state.profile_fx_stage_entries) do
      if entry.mode ~= "replace" then return false end
      local target_track = resolve_profile_target_track(entry)
      local target_fx = tonumber(entry.target_real_fx)
      local count = target_track and reaper.TrackFX_GetCount(target_track) or 0
      if not target_track or not target_fx or target_fx < 0
         or target_fx >= count then
        return nil, "replacement_target_missing"
      end
      local current_guid = reaper.TrackFX_GetFXGUID(target_track, target_fx)
      if type(current_guid) ~= "string"
         or current_guid ~= entry.target_fx_guid then
        return nil, "replacement_target_identity_changed"
      end
      entry.committed_fx = target_fx
    end
    return true
  end

  local function commit_profile_fx_stage()
    if defer_state.profile_fx_stage_committed then return true end
    if not defer_state.profile_fx_stage_project then return true end
    local no_op, no_op_err = profile_stage_is_verified_noop()
    if no_op == nil then
      cleanup_profile_fx_stage()
      return false, tostring(no_op_err or "profile_fx_noop_check_failed")
    end
    if no_op then
      local cleanup_ok, cleanup_err = cleanup_profile_fx_stage()
      if not cleanup_ok then
        return false, "stage_cleanup_failed:" .. tostring(cleanup_err)
      end
      defer_state.profile_fx_stage_committed = true
      show_committed_profile_fx()
      Log.line("SCRIPT",
        "Discarded verified no-op profile staging without changing the user project")
      return true
    end
    local project = defer_state.undo_project
    local block_open = false
    local block_started = false
    local refresh_held = false
    local committed = false
    local ok, commit_err = pcall(function()
      reaper.PreventUIRefresh(1)
      refresh_held = true
      reaper.SelectProjectInstance(project)
      reaper.Undo_BeginBlock2(project)
      block_open = true
      block_started = true
      for _, entry in ipairs(defer_state.profile_fx_stage_entries) do
        local target_track = resolve_profile_target_track(entry)
        if not target_track then error("target_track_not_found") end
        local before_count = reaper.TrackFX_GetCount(target_track)
        local dest_fx
        if entry.mode == "replace" then
          dest_fx = tonumber(entry.target_real_fx)
          if not dest_fx or dest_fx < 0 or dest_fx >= before_count then
            error("replacement_target_missing")
          end
          local current_guid =
            reaper.TrackFX_GetFXGUID(target_track, dest_fx)
          if type(current_guid) ~= "string"
             or current_guid ~= entry.target_fx_guid then
            error("replacement_target_identity_changed")
          end
          entry.committed_fx = dest_fx
        else
          dest_fx = before_count
        end
        if entry.mode ~= "replace" then
          reaper.TrackFX_CopyToTrack(defer_state.profile_fx_stage_track,
            entry.stage_fx, target_track, dest_fx, false)
          if reaper.TrackFX_GetCount(target_track) ~= before_count + 1 then
            error("profile_fx_commit_copy_failed")
          end
          entry.committed_fx = dest_fx
        end
      end
      for _, staged_write in ipairs(
          defer_state.profile_fx_stage_write_sequence) do
        local entry = staged_write.stage_entry
        if entry and entry.mode == "replace" then
          if staged_write.final_normalized == nil then
            error("replacement_parameter_final_value_unavailable")
          end
          local target_track = resolve_profile_target_track(entry)
          if not target_track then error("target_track_not_found") end
          reaper.TrackFX_SetParamNormalized(
            target_track, entry.committed_fx,
            staged_write.parameter_index, staged_write.final_normalized)
        end
      end
      reaper.Undo_EndBlock2(project,
        inner_undo_label or "ReaAssist", 2)
      block_open = false
      committed = true
    end)
    if refresh_held then reaper.PreventUIRefresh(-1) end
    if block_open then
      pcall(reaper.Undo_EndBlock2, project,
        inner_undo_label or "ReaAssist", 2)
    end
    if not ok or not committed then
      if block_started then
        pcall(reaper.Undo_DoUndo2, project)
      end
      cleanup_profile_fx_stage()
      return false, tostring(commit_err or "profile_fx_commit_failed")
    end

    for _, witness in pairs(defer_state.parameter_writes) do
      local entry = witness.stage_entry
      if entry and witness.final_normalized ~= nil then
        local target_track = resolve_profile_target_track(entry)
        local actual = target_track and reaper.TrackFX_GetParamNormalized(
          target_track, entry.committed_fx, witness.parameter_index) or nil
        local normalized_match = actual ~= nil
          and math.abs(actual - witness.final_normalized) <= 0.0000001
        local actual_formatted = nil
        local formatted_match = false
        if not normalized_match
           and type(witness.final_formatted) == "string" then
          actual_formatted = target_track
            and profile_formatted_parameter_value(
              target_track, entry.committed_fx, witness.parameter_index)
            or nil
          formatted_match = actual_formatted == witness.final_formatted
        end
        if not normalized_match and not formatted_match then
          Log.line("SCRIPT", string.format(
            "Profile commit verification mismatch product=%s parameter=%s "
              .. "index=%s expected_norm=%s actual_norm=%s "
              .. "expected_display=%s actual_display=%s",
            tostring(witness.plugin_product_key or ""),
            tostring(witness.parameter_name or ""),
            tostring(witness.parameter_index),
            tostring(witness.final_normalized), tostring(actual),
            tostring(witness.final_formatted),
            tostring(actual_formatted)))
          pcall(reaper.Undo_DoUndo2, project)
          cleanup_profile_fx_stage()
          return false, "committed_parameter_verification_failed"
        end
      end
    end
    defer_state.profile_fx_stage_committed = true
    local cleanup_ok, cleanup_err = cleanup_profile_fx_stage()
    if not cleanup_ok then
      pcall(reaper.Undo_DoUndo2, project)
      return false, "stage_cleanup_failed:" .. tostring(cleanup_err)
    end
    show_committed_profile_fx()
    Log.line("SCRIPT",
      "Committed deferred profile FX edit from isolated staging while preserving existing FX identity")
    return true
  end

  local function profile_target_key(kind, target_ref, fx)
    return tostring(kind) .. "\31" .. tostring(target_ref)
      .. "\31" .. tostring(fx)
  end

  local function profile_guard_error(reason)
    return "ReaAssist profile parameter guard refused the write: "
      .. tostring(reason or "unknown_profile_guard_failure")
  end

  local function profile_parameter_label_key(value)
    local text = tostring(value or ""):lower()
      :gsub("^%s+", ""):gsub("%s+$", "")
    local key = text:gsub("[^%w]+", " ")
      :gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return key ~= "" and key or text
  end

  local function validate_profile_write_target(kind, target_ref, fx, pidx,
      caller_line)
    if kind == "track" then
      local target_key = profile_target_key(kind, target_ref, fx)
      local target = defer_state.profile_target_checks[target_key]
      if target ~= false then
        if not target then
          local validated, reason =
            Code.plugin_profile_target_validation(
              target_ref, fx, profile_receipts)
          if not validated then
            if reason == "profiles_inactive"
               or reason == "not_profile_target" then
              defer_state.profile_target_checks[target_key] = false
              target = false
            else
              error(profile_guard_error(reason), 3)
            end
          else
            target = validated
            defer_state.profile_target_checks[target_key] = target
          end
        end

        if target then
          local resolution = defer_state.profile_resolutions[target_key]
          local index = tonumber(pidx)
          if not resolution or index == nil or index % 1 ~= 0
             or not resolution.indices[index] then
            error(profile_guard_error(
              "unresolved mapped parameter index " .. tostring(pidx)
                .. " for " .. tostring(target.loaded_name)), 3)
          end
          return true
        end
      end
    end

    local authorization = defer_state.param_write_authorization[
      tonumber(caller_line)]
    if authorization and authorization.kind == "canonical_helper" then
      return true
    end
    error("ReaAssist parameter provenance guard refused the "
      .. tostring(kind) .. " FX write at generated line "
      .. tostring(caller_line or "unknown")
      .. ": use a validated plug-in profile mapping or an exact bundled "
      .. "parameter helper.", 3)
  end

  -- ReaAssist-provided generated-code helper. Unlike the generic probing
  -- helpers, this function is part of the per-run sandbox and does not need
  -- to be pasted into generated Lua. It validates every requested mapping in
  -- one pass and returns no indices unless the whole compound target set is
  -- safe. Generated code must call it before any mapped write.
  code_env.reaassist_resolve_profile_params = function(track, fx, specs)
    if type(specs) ~= "table" or #specs == 0 then
      return nil, profile_guard_error("empty parameter specification")
    end
    local validation_track, validation_fx = track, fx
    local stage_entry = nil
    if defer_state.profile_fx_staging_enabled then
      local stage_err
      validation_track, validation_fx, stage_err, stage_entry =
        profile_stage_target(track, fx, true)
      if not validation_track then
        return nil, profile_guard_error(
          stage_err or "plugin_staging_unavailable")
      end
    end
    local validated, reason =
      Code.plugin_profile_target_validation(
        validation_track, validation_fx, profile_receipts,
        stage_entry and defer_state.profile_fx_stage_project or nil)
    if not validated then
      return nil, profile_guard_error(reason)
    end
    local inventory = validated.inventory
    local params = type(inventory) == "table" and inventory.params or nil
    if type(params) ~= "table" then
      return nil, profile_guard_error("inventory unavailable")
    end

    local resolved = {}
    local resolved_by_index = {}
    for position, spec in ipairs(specs) do
      if type(spec) ~= "table" then
        return nil, profile_guard_error(
          "invalid parameter specification at position " .. position)
      end
      local expected_index = tonumber(spec.index)
      local expected_name = tostring(spec.name or "")
      local expected_section = spec.section ~= nil
        and tostring(spec.section) or nil
      local expected_name_key = profile_parameter_label_key(expected_name)
      local expected_section_key = expected_section ~= nil
        and profile_parameter_label_key(expected_section) or nil
      if expected_index == nil or expected_index % 1 ~= 0
         or expected_index < 0 or expected_name == "" then
        return nil, profile_guard_error(
          "invalid parameter specification at position " .. position)
      end

      local name_matches = {}
      for _, live in ipairs(params) do
        if profile_parameter_label_key(live.name) == expected_name_key
           and (expected_section == nil
             or profile_parameter_label_key(live.section)
               == expected_section_key) then
          name_matches[#name_matches + 1] = live
        end
      end
      if expected_section == nil and #name_matches > 1 then
        return nil, profile_guard_error(
          "parameter name is ambiguous without a section: " .. expected_name)
      end

      local live = params[expected_index + 1]
      local direct_ok = live
        and profile_parameter_label_key(live.name) == expected_name_key
        and (expected_section == nil
          or (live.section_available == true
            and profile_parameter_label_key(live.section)
              == expected_section_key))
      if direct_ok and expected_section ~= nil
         and live.section_available ~= true then
        direct_ok = false
      end
      if not direct_ok then
        if #name_matches ~= 1 then
          return nil, profile_guard_error(
            "expected index/name/section did not match uniquely: "
              .. tostring(expected_index) .. " / " .. expected_name
              .. (expected_section ~= nil
                and (" / " .. expected_section) or ""))
        end
        live = name_matches[1]
      end
      resolved[position] = live.index
      resolved_by_index[live.index] = {
        expected_name = expected_name,
        expected_section = expected_section,
      }
    end

    local target_key = profile_target_key("track", track, fx)
    defer_state.profile_target_checks[target_key] = validated
    defer_state.profile_resolutions[target_key] = {
      indices = resolved_by_index,
      product_key = validated.receipt
        and validated.receipt.product_key or nil,
      fingerprint = inventory.observed_fingerprint_sha256,
      stage_entry = stage_entry,
    }
    return resolved
  end

  defer_state.record_parameter_write = function(kind, target_ref, fx, pidx,
      getter, setter, value, caller_line, value_is_normalized)
    validate_profile_write_target(
      kind, target_ref, fx, pidx, caller_line)
    local write_target, write_fx = target_ref, fx
    local stage_entry = nil
    if kind == "track" and defer_state.profile_fx_staging_enabled then
      local stage_err
      write_target, write_fx, stage_err, stage_entry =
        profile_stage_target(target_ref, fx, true)
      if not write_target then
        error("ReaAssist could not stage the target plug-in before the "
          .. "parameter write: " .. tostring(stage_err), 3)
      end
    end
    local key = tostring(kind) .. "\31" .. tostring(target_ref)
      .. "\31" .. tostring(fx) .. "\31" .. tostring(pidx)
    local entry = defer_state.parameter_writes[key]
    if not entry then
      entry = {
        write_count = 0,
        changed_during = false,
        stage_entry = stage_entry,
        parameter_index = tonumber(pidx),
      }
      if kind == "track" then
        local target_key = profile_target_key(kind, target_ref, fx)
        local target = defer_state.profile_target_checks[target_key]
        local resolution = defer_state.profile_resolutions[target_key]
        local resolved = resolution and resolution.indices[tonumber(pidx)]
        if target and resolved then
          entry.plugin_profile_guard = "validated"
          entry.plugin_product_key = resolution.product_key
          entry.plugin_fingerprint = resolution.fingerprint
          entry.plugin_loaded_name = target.loaded_name
          entry.parameter_name = resolved.expected_name
          entry.parameter_section = resolved.expected_section
        end
      end
      defer_state.parameter_writes[key] = entry
      if type(getter) == "function" then
        local before_ok, before =
          pcall(getter, write_target, write_fx, pidx)
        if before_ok then entry.initial_normalized = tonumber(before) end
      end
    end
    local packed = table.pack(setter(write_target, write_fx, pidx, value))
    entry.write_count = entry.write_count + 1
    local write_final_normalized = nil
    if type(getter) == "function" then
      local after_ok, after =
        pcall(getter, write_target, write_fx, pidx)
      if after_ok then
        entry.final_normalized = tonumber(after)
        write_final_normalized = entry.final_normalized
        entry.final_formatted = profile_formatted_parameter_value(
          write_target, write_fx, pidx)
        if entry.initial_normalized ~= nil
           and entry.final_normalized ~= nil
           and math.abs(entry.final_normalized - entry.initial_normalized)
             > 0.0000001 then
          entry.changed_during = true
        end
      end
    end
    if stage_entry then
      -- Replaying a staged readback can quantize the value a second time in
      -- some plug-ins. A normalized setter must therefore replay the original
      -- requested value. Verification below still compares the real result
      -- with the staging result and rolls back any genuine mismatch.
      local commit_normalized = value_is_normalized
        and tonumber(value) or write_final_normalized
      defer_state.profile_fx_stage_write_sequence[
        #defer_state.profile_fx_stage_write_sequence + 1] = {
          stage_entry = stage_entry,
          parameter_index = tonumber(pidx),
          final_normalized = commit_normalized,
        }
    end
    return table.unpack(packed, 1, packed.n)
  end

  defer_state.apply_completed_result = function()
    local rr = defer_state.completed_result
    if type(rr) ~= "table" then return end
    local msg = defer_state.message_idx
      and type(S.display_messages) == "table"
      and S.display_messages[defer_state.message_idx] or nil
    if msg and not defer_state.message_finalized then
      msg.run_status = rr.run_status
      msg.validation_status = rr.validation_status
      msg.auto_ran = (rr.run_status == "ran_ok" and defer_state.auto_ran == true)
      Code.apply_run_result_to_message(msg, rr.run_status == "ran_ok",
        "lua", code, msg.auto_ran, rr)
      defer_state.message_finalized = true
    end

    local hist = defer_state.history_idx
      and type(S.history) == "table" and S.history[defer_state.history_idx]
      or nil
    if hist and not defer_state.history_finalized then
      hist.run_status = rr.run_status
      hist.code_bytes = type(code) == "string" and #code or nil
      hist.code_type = "lua"
      defer_state.history_finalized = true
    end

    if type(Probe) == "table" and defer_state.probe_turn
       and not defer_state.probe_finalized then
      if type(Probe.mark_phase_end) == "function" then
        Probe.mark_phase_end(defer_state.probe_turn, "execution")
      end
      if type(Probe.end_turn) == "function" then
        Probe.end_turn(defer_state.probe_turn,
          rr.run_status == "errored" and "error" or "ok")
      end
      if type(S) == "table" and S.probe_turn == defer_state.probe_turn then
        S.probe_turn = nil
      end
      defer_state.probe_finalized = true
    end

    if type(S) == "table" and S.lua_defer_run == defer_state
       and defer_state.message_idx then
      S.lua_defer_run = nil
    end
  end

  defer_state.bind = function(message_idx, history_idx, auto_ran, probe_turn)
    defer_state.message_idx = message_idx
    defer_state.history_idx = history_idx
    defer_state.auto_ran = auto_ran == true
    defer_state.probe_turn = probe_turn
    defer_state.apply_completed_result()
  end

  local function record_runtime_error(run_err, instruction_timeout,
      instruction_count, source)
    recover_generated_refresh()
    local err_str, short, user_msg =
      lua_runtime_error_strings(run_err, instruction_timeout)
    local change_count_after = Code.project_change_count()
    local err_debug = {
      failure_kind = instruction_timeout
        and "lua_instruction_budget_exceeded" or "runtime_error",
      source = source or "generated_lua_runtime",
      runtime_error = Log.scrub_url_secrets(err_str),
      stack_excerpt = Log.scrub_url_secrets(short),
      instruction_budget = instruction_timeout
        and CODE_RUN_INSTRUCTION_BUDGET or nil,
      instruction_count = instruction_count,
      generated_code_bytes = type(code) == "string" and #code or 0,
      project_state_change_count_before = change_count_before,
      project_state_change_count_after = change_count_after,
      generated_refresh_recovered =
        (defer_state.generated_refresh_recovery_count or 0) > 0,
      generated_refresh_recovery_count =
        defer_state.generated_refresh_recovery_count or 0,
    }
    Log.line("SCRIPT", "Runtime error: " .. err_str:gsub("\n", " \\n "))
    Diag.add_error(err_str, nil, code)
    Log.add_error(user_msg, nil, nil, nil,
      { error_kind = "runtime_error", error_debug = err_debug })
    S.last_run_error = "runtime error: " .. Log.scrub_url_secrets(short)
    local error_result = Code.build_run_result("lua", code,
      "errored", "failed", {
        change_count_before = change_count_before,
        change_count_after = change_count_after,
        parameter_change_evidence =
          Code.parameter_change_evidence(defer_state.parameter_writes),
        error_kind = "runtime_error",
        error_debug = err_debug,
        runtime_error = S.last_run_error,
        generated_refresh_recovered =
          (defer_state.generated_refresh_recovery_count or 0) > 0,
        generated_refresh_recovery_count =
          defer_state.generated_refresh_recovery_count or 0,
      })
    defer_state.error_result = error_result
    if type(S) == "table"
       and (S.lua_defer_run == nil or S.lua_defer_run == defer_state) then
      S.last_run_result = error_result
    end
    Code.plugin_test_runtime_event("run_error", {
      code_sha256 = Code.plugin_profile_code_key(code),
      run_result = error_result,
    })
  end

  local function finish_deferred_lua_run()
    if defer_state.pending > 0 then return end
    recover_generated_refresh()
    close_run_undo()
    if not defer_state.failed then
      local call_ok, commit_ok, commit_err =
        pcall(commit_profile_fx_stage)
      if not call_ok or not commit_ok then
        defer_state.failed = true
        cleanup_profile_fx_stage()
        record_runtime_error(
          "ReaAssist could not commit this plug-in edit from isolated "
            .. "staging in one verified Undo entry: "
            .. tostring(call_ok and commit_err or commit_ok),
          false, nil, "plugin_profile_staging_commit")
      end
    else
      cleanup_profile_fx_stage()
    end
    local parameter_evidence =
      Code.parameter_change_evidence(defer_state.parameter_writes)
    local completed_result
    if not defer_state.failed then
      local change_count_after = Code.project_change_count()
      completed_result = Code.build_run_result("lua", code,
        "ran_ok", "passed", {
          change_count_before = change_count_before,
          change_count_after = change_count_after,
          parameter_change_evidence = parameter_evidence,
          deferred = true,
          deferred_pending = false,
          generated_refresh_recovered =
            (defer_state.generated_refresh_recovery_count or 0) > 0,
          generated_refresh_recovery_count =
            defer_state.generated_refresh_recovery_count or 0,
        })
    elseif type(defer_state.error_result) == "table" then
      completed_result = defer_state.error_result
      completed_result.deferred = true
      completed_result.deferred_pending = false
      completed_result.parameter_change_evidence =
        completed_result.parameter_change_evidence or parameter_evidence
      completed_result.parameter_change_status =
        completed_result.parameter_change_status
        or (parameter_evidence and parameter_evidence.status)
    end
    if type(completed_result) == "table" then
      defer_state.completed_result = completed_result
      if type(S) == "table" and S.lua_defer_run == defer_state then
        S.last_run_result = completed_result
      end
      defer_state.apply_completed_result()
      Code.plugin_test_runtime_event("run_completed", {
        code_sha256 = Code.plugin_profile_code_key(code),
        run_result = completed_result,
      })
    end
  end

  -- Wrap `reaper` so user-facing calls (dialogs, console output) are logged
  -- when debug logging is enabled. Every other allowed reaper.* call falls
  -- through to the real API via __index; denied APIs are blocked even when the
  -- code aliases `reaper` or builds a function name dynamically.
  local function route_staged_track_fx(api, tr, fx, ...)
    if not defer_state.profile_fx_staging_enabled then
      return api(tr, fx, ...)
    end
    local staged_track, staged_fx, stage_err =
      profile_stage_target(tr, fx, true)
    if not staged_track then
      error("ReaAssist could not route the plug-in operation through "
        .. "isolated staging: " .. tostring(stage_err), 3)
    end
    return api(staged_track, staged_fx, ...)
  end

  local reaper_shim = sandbox_api_proxy(reaper, {
    defer = function(fn)
      if type(fn) ~= "function" or type(reaper.defer) ~= "function" then
        return reaper.defer(fn)
      end
      if defer_state.in_callback then
        error("generated Lua cannot schedule reaper.defer from inside a "
          .. "deferred callback; use exactly one reaper.defer callback for "
          .. "one-shot edits", 2)
      end
      defer_state.pending = defer_state.pending + 1
      local wrapped = function()
        if defer_state.failed then
          defer_state.pending = math.max(0, defer_state.pending - 1)
          finish_deferred_lua_run()
          return
        end
        defer_state.in_callback = true
        local ok, run_err, instruction_timeout, instruction_count =
          run_lua_chunk_with_instruction_guard(fn)
        defer_state.in_callback = false
        if not ok then
          defer_state.failed = true
        end
        defer_state.pending = math.max(0, defer_state.pending - 1)
        if defer_state.pending == 0 then close_run_undo() end
        if not ok then
          record_runtime_error(run_err, instruction_timeout, instruction_count,
            "generated_lua_defer_callback")
        end
        finish_deferred_lua_run()
      end
      local schedule_ok, schedule_result = pcall(reaper.defer, wrapped)
      if not schedule_ok then
        defer_state.pending = math.max(0, defer_state.pending - 1)
        error(schedule_result, 2)
      end
      return schedule_result
    end,
    ShowMessageBox = function(msg, title, btn_type)
      Log.line("SCRIPT", "ShowMessageBox [" .. tostring(title) .. "]: "
        .. tostring(msg):gsub("\n", " \\n "))
      return reaper.ShowMessageBox(msg, title, btn_type)
    end,
    ShowConsoleMsg = function(msg)
      Log.line("SCRIPT", "ShowConsoleMsg: " .. tostring(msg):gsub("\n$", ""):gsub("\n", " \\n "))
      return reaper.ShowConsoleMsg(msg)
    end,
    PreventUIRefresh = function(adjust)
      local delta = tonumber(adjust) or 0
      local packed = table.pack(reaper.PreventUIRefresh(adjust))
      defer_state.generated_refresh_balance = math.max(0,
        (tonumber(defer_state.generated_refresh_balance) or 0) + delta)
      return table.unpack(packed, 1, packed.n)
    end,
    TrackFX_SetParamNormalized = function(tr, fx, pidx, value)
      local caller = debug.getinfo(2, "l")
      return defer_state.record_parameter_write("track", tr, fx, pidx,
        reaper.TrackFX_GetParamNormalized,
        reaper.TrackFX_SetParamNormalized, value,
        caller and caller.currentline or nil, true)
    end,
    TrackFX_AddByName = function(tr, name, rec_fx, instantiate)
      if not defer_state.profile_fx_staging_enabled then
        return reaper.TrackFX_AddByName(tr, name, rec_fx, instantiate)
      end
      if rec_fx then
        error("isolated profile staging supports normal track FX only", 2)
      end
      local staged = find_profile_stage_by_name(tr, name)
      local mode = tonumber(instantiate)
      if staged and mode ~= nil and mode >= 0 then
        return staged.proxy_fx
      end
      local existing = reaper.TrackFX_AddByName(tr, name, false, 0)
      if existing and existing >= 0 and mode ~= nil and mode >= 0 then
        local entry, stage_err =
          stage_existing_profile_fx(tr, existing, name)
        if not entry then
          error("ReaAssist could not stage the existing plug-in: "
            .. tostring(stage_err), 2)
        end
        return entry.proxy_fx
      end
      if mode == 0 then return -1 end
      if mode == nil then
        error("TrackFX_AddByName instantiate mode is required", 2)
      end
      if mode < 0 and mode ~= -1 then
        error("isolated profile staging does not support positional "
          .. "TrackFX_AddByName insertion", 2)
      end
      local entry, stage_err = stage_new_profile_fx(tr, name)
      if not entry then
        error("ReaAssist could not add the plug-in in isolated staging: "
          .. tostring(stage_err), 2)
      end
      return entry.proxy_fx
    end,
    TrackFX_GetByName = function(tr, name, instantiate)
      if not defer_state.profile_fx_staging_enabled then
        return reaper.TrackFX_GetByName(tr, name, instantiate)
      end
      local staged = find_profile_stage_by_name(tr, name)
      if staged then return staged.proxy_fx end
      local existing = reaper.TrackFX_GetByName(tr, name, false)
      if existing and existing >= 0 then
        local entry, stage_err =
          stage_existing_profile_fx(tr, existing, name)
        if not entry then
          error("ReaAssist could not stage the existing plug-in: "
            .. tostring(stage_err), 2)
        end
        return entry.proxy_fx
      end
      if not instantiate then return -1 end
      local entry, stage_err = stage_new_profile_fx(tr, name)
      if not entry then
        error("ReaAssist could not add the plug-in in isolated staging: "
          .. tostring(stage_err), 2)
      end
      return entry.proxy_fx
    end,
    TrackFX_GetCount = function(tr)
      local count = reaper.TrackFX_GetCount(tr)
      if not defer_state.profile_fx_staging_enabled then return count end
      for _, entry in ipairs(defer_state.profile_fx_stage_entries) do
        if entry.target_track == tr and entry.mode == "append" then
          count = count + 1
        end
      end
      return count
    end,
    TrackFX_GetParamNormalized = function(tr, fx, pidx)
      return route_staged_track_fx(
        reaper.TrackFX_GetParamNormalized, tr, fx, pidx)
    end,
    TrackFX_GetParam = function(tr, fx, pidx)
      return route_staged_track_fx(reaper.TrackFX_GetParam, tr, fx, pidx)
    end,
    TrackFX_GetParamEx = function(tr, fx, pidx)
      return route_staged_track_fx(reaper.TrackFX_GetParamEx, tr, fx, pidx)
    end,
    TrackFX_GetFormattedParamValue = function(tr, fx, pidx, value)
      return route_staged_track_fx(
        reaper.TrackFX_GetFormattedParamValue, tr, fx, pidx, value)
    end,
    TrackFX_GetParamName = function(tr, fx, pidx, name)
      return route_staged_track_fx(
        reaper.TrackFX_GetParamName, tr, fx, pidx, name)
    end,
    TrackFX_GetNumParams = function(tr, fx)
      return route_staged_track_fx(reaper.TrackFX_GetNumParams, tr, fx)
    end,
    TrackFX_GetFXName = function(tr, fx, name)
      return route_staged_track_fx(reaper.TrackFX_GetFXName, tr, fx, name)
    end,
    TrackFX_GetNamedConfigParm = function(tr, fx, parmname)
      return route_staged_track_fx(
        reaper.TrackFX_GetNamedConfigParm, tr, fx, parmname)
    end,
    TrackFX_Show = function(tr, fx, show_flag)
      if not defer_state.profile_fx_staging_enabled then
        return reaper.TrackFX_Show(tr, fx, show_flag)
      end
      local entry, stage_err = profile_stage_entry(tr, fx, true)
      if not entry then
        error("ReaAssist could not defer the plug-in window request: "
          .. tostring(stage_err), 2)
      end
      entry.show_flag = show_flag
    end,
    TrackFX_SetParam = function(tr, fx, pidx, value)
      local caller = debug.getinfo(2, "l")
      return defer_state.record_parameter_write("track", tr, fx, pidx,
        reaper.TrackFX_GetParamNormalized, reaper.TrackFX_SetParam, value,
        caller and caller.currentline or nil)
    end,
    TakeFX_SetParamNormalized = function(take, fx, pidx, value)
      local caller = debug.getinfo(2, "l")
      return defer_state.record_parameter_write("take", take, fx, pidx,
        reaper.TakeFX_GetParamNormalized,
        reaper.TakeFX_SetParamNormalized, value,
        caller and caller.currentline or nil, true)
    end,
    TakeFX_SetParam = function(take, fx, pidx, value)
      local caller = debug.getinfo(2, "l")
      return defer_state.record_parameter_write("take", take, fx, pidx,
        reaper.TakeFX_GetParamNormalized, reaper.TakeFX_SetParam, value,
        caller and caller.currentline or nil)
    end,
    Main_OnCommand = function(command_id, flag)
      if tonumber(command_id) == 40860 then close_run_undo() end
      return reaper.Main_OnCommand(command_id, flag)
    end,
    Main_OnCommandEx = function(command_id, flag, project)
      if tonumber(command_id) == 40860 then close_run_undo() end
      return reaper.Main_OnCommandEx(command_id, flag, project)
    end,
    -- Undo shim: no-op on REAPER's side, capture the label on End so the
    -- outer wrapper can apply it. Return 0 from EndBlock to match REAPER's
    -- real signature (it returns 0 when there was nothing to undo, non-zero
    -- otherwise); generated code rarely checks this, and returning 0 is the
    -- safe default given we didn't actually open a real block here.
    Undo_BeginBlock  = function() end,
    Undo_BeginBlock2 = function(_proj) end,
    Undo_EndBlock = function(label, flags)
      if label and label ~= "" then
        inner_undo_label = label
        inner_undo_flags = flags or -1
      end
      return 0
    end,
    Undo_EndBlock2 = function(_proj, label, flags)
      if label and label ~= "" then
        inner_undo_label = label
        inner_undo_flags = flags or -1
      end
      return 0
    end,
  }, "reaper")
  code_env.reaper = reaper_shim

  if Log.enabled() then
    Log.line("SCRIPT", "Running generated code (" .. #code .. " bytes)")
  end

  -- "t" enforces text-only chunks (no bytecode), and the 4th arg sets _ENV
  -- directly at compile time without needing debug.setupvalue.
  S.last_run_result = nil
  local fn, compile_err = load(code, "ReaAssist", "t", code_env)
  if not fn then
    defer_state.failed = true
    local err_str = tostring(compile_err)
    local err_short = short_error_excerpt(err_str, 6)
    local change_count_after = Code.project_change_count()
    local err_debug = {
      failure_kind = "lua_compile_error",
      source = "generated_lua_compile",
      compile_error = Log.scrub_url_secrets(err_str),
      generated_code_bytes = type(code) == "string" and #code or 0,
      project_state_change_count_before = change_count_before,
      project_state_change_count_after = change_count_after,
    }
    Log.line("SCRIPT", "Compile error: " .. err_str)
    Diag.add_error(err_str, nil, code)
    -- Surface the failure as a chat-visible message instead of (only) a modal
    -- popup: the popup interrupts flow and hides the error the moment the
    -- user clicks OK, so they have nothing to reference when they type a
    -- follow-up. Inline lets them read the trace, copy parts, and keep going.
    local fallback = "Lua compile error in generated code:\n\n" .. err_str
    Log.add_error((RA and RA.t and RA.t("code.compile_error",
      { error = err_str }, fallback)) or fallback,
      nil, nil, nil, { error_kind = "runtime_error", error_debug = err_debug })
    -- Stash so the next user prompt's send_to_api can include the error as
    -- model context -- when the user types "fix that" they expect the model
    -- to know what broke. Cleared after the next send.
    S.last_run_error = "compile error: " .. Log.scrub_url_secrets(err_short)
    S.last_run_result = Code.build_run_result("lua", code,
      "errored", "failed", {
        change_count_before = change_count_before,
        change_count_after = change_count_after,
      error_kind = "runtime_error",
      error_debug = err_debug,
      parameter_change_evidence =
        Code.parameter_change_evidence(defer_state.parameter_writes),
      runtime_error = S.last_run_error,
      })
    Code.plugin_test_runtime_event("run_completed", {
      code_sha256 = Code.plugin_profile_code_key(code),
      run_result = S.last_run_result,
    })
    return false
  end

  -- Plugin-level undo wrapper. Generated Undo calls are intercepted above.
  -- General scripts receive one real outer block. Profile-authorized,
  -- track-FX-only scripts do not touch the user project here; their completed
  -- staged state is committed later in one short synchronous block. Existing
  -- FX receive only verified parameter values so their GUIDs remain stable;
  -- newly added FX are copied into place.
  if not defer_state.profile_fx_staging_enabled then
    if defer_state.undo_project
       and type(reaper.Undo_BeginBlock2) == "function"
       and type(reaper.Undo_EndBlock2) == "function" then
      reaper.Undo_BeginBlock2(defer_state.undo_project)
      defer_state.undo_project_api = true
    else
      reaper.Undo_BeginBlock()
    end
    defer_state.undo_open = true
  end
  local ok, run_err, instruction_timeout, instruction_count =
    run_lua_chunk_with_instruction_guard(fn)
  if not ok then
    defer_state.failed = true
    close_run_undo()
    cleanup_profile_fx_stage()
    record_runtime_error(run_err, instruction_timeout, instruction_count,
      "generated_lua_runtime")
    return false
  end
  Log.line("SCRIPT", "Script completed OK")
  if defer_state.pending == 0 then recover_generated_refresh() end
  reaper.UpdateArrange()
  if defer_state.pending > 0 then
    S.lua_defer_run = defer_state
    S.last_run_result = Code.build_run_result("lua", code,
      "pending", "pending", {
        deferred = true,
        deferred_pending = true,
      })
    Code.plugin_test_runtime_event("run_pending", {
      code_sha256 = Code.plugin_profile_code_key(code),
      run_result = S.last_run_result,
    })
    return true, "pending"
  end
  close_run_undo()
  local commit_call_ok, commit_ok, commit_err =
    pcall(commit_profile_fx_stage)
  if not commit_call_ok or not commit_ok then
    defer_state.failed = true
    cleanup_profile_fx_stage()
    record_runtime_error(
      "ReaAssist could not commit this plug-in edit from isolated staging "
        .. "in one verified Undo entry: "
        .. tostring(commit_call_ok and commit_err or commit_ok),
      false, nil, "plugin_profile_staging_commit")
    return false
  end
  local change_count_after = Code.project_change_count()
  S.last_run_result = Code.build_run_result("lua", code,
    "ran_ok", "passed", {
      change_count_before = change_count_before,
      change_count_after = change_count_after,
      parameter_change_evidence =
        Code.parameter_change_evidence(defer_state.parameter_writes),
      generated_refresh_recovered =
        (defer_state.generated_refresh_recovery_count or 0) > 0,
      generated_refresh_recovery_count =
        defer_state.generated_refresh_recovery_count or 0,
    })
  Code.plugin_test_runtime_event("run_completed", {
    code_sha256 = Code.plugin_profile_code_key(code),
    run_result = S.last_run_result,
  })
  return true
end

-- =============================================================================

-- Code.jsfx_pitch_intent / Code.jsfx_pitch_preflight_note
-- =============================================================================
-- Classify request-time JSFX pitch intent once so the preflight note and
-- Context.lua family-bundle routing cannot drift apart.
function Code.jsfx_pitch_intent(user_text)
  local lower = tostring(user_text or ""):lower():gsub("’", "'")
  local function requests_term(term, allow_suffix)
    return Code.prompt_requests_jsfx_term(user_text, term, allow_suffix)
  end
  local function requests_pattern(pattern)
    local pos = 1
    while true do
      local first, last = lower:find(pattern, pos)
      if not first then return false end
      if Code.prompt_requests_jsfx_term(
          user_text, lower:sub(first, last), false) then
        return true
      end
      pos = math.max(last + 1, pos + 1)
    end
  end
  local shimmer = requests_term("shimmer", false)
  local function verb_match_is_negated(first)
    local prefix = lower:sub(1, math.max(0, first - 1))
    local segment_start =
      prefix:match(".*[%.!%?;,\n]()%s*") or 1
    local segment = prefix:sub(segment_start)
      :gsub("%f[%a]not%s+only%f[%A]", "also")
      :gsub("%f[%a]not%s+just%f[%A]", "also")
      :gsub("n't%s+only%f[%A]", "also")
      :gsub("n't%s+just%f[%A]", "also")
    local negated = segment:find("%f[%a]not%f[%A]") ~= nil
      or segment:find("%f[%a]never%f[%A]") ~= nil
      or segment:find("n't", 1, true) ~= nil
    return negated, segment_start
  end
  local function verb_targets_pitch(stem)
    local head = "%f[%a]" .. stem .. "%a*%s+"
    for _, pattern in ipairs({
      head .. "pitch%f[%A]",
      head .. "[%a']+%s+pitch%f[%A]",
      head .. "[%a']+%s+[%a']+%s+pitch%f[%A]",
    }) do
      local pos = 1
      while true do
        local first, last = lower:find(pattern, pos)
        if not first then break end
        local negated, segment_start = verb_match_is_negated(first)
        if not negated and Code.prompt_requests_jsfx_term(
            lower:sub(segment_start, last),
            lower:sub(first, last), false) then
          return true
        end
        pos = math.max(last + 1, pos + 1)
      end
    end
    return false
  end
  local action_pitch = false
  for _, stem in ipairs({
    "shift", "drop", "move", "alter", "adjust", "raise", "lower", "change",
  }) do
    if verb_targets_pitch(stem) then
      action_pitch = true
      break
    end
  end
  local semitone_amount = requests_term("semitone", true)
  local named_shift =
       requests_term("pitch shift", true)
    or requests_term("pitch-shift", true)
    or requests_term("pitchshift", true)
  local transpose = requests_term("transpos", true)
  local harmonize = requests_term("harmoniz", true)
  local detune = requests_term("detun", true)
  local granular_term = requests_term("grain", false)
    or requests_term("granular", true)
  local pitched_grains = granular_term
    and requests_term("pitch grain", true)
  local octave_up =
       requests_term("octave up", false)
    or requests_term("octave-up", false)
    or requests_pattern("%f[%a]up%s+an%s+octave%f[%A]")
    or requests_pattern("%f[%a]up%s+one%s+octave%f[%A]")
  local octave_down =
       requests_term("octave down", false)
    or requests_term("octave-down", false)
    or requests_pattern("%f[%a]down%s+an%s+octave%f[%A]")
    or requests_pattern("%f[%a]down%s+one%s+octave%f[%A]")
    or requests_pattern("%f[%a]an%s+octave%s+lower%f[%A]")
    or requests_pattern("%f[%a]one%s+octave%s+lower%f[%A]")
    or requests_pattern("%f[%a]drop%a*%s+an%s+octave%f[%A]")
    or requests_pattern("%f[%a]drop%a*%s+one%s+octave%f[%A]")
    or requests_pattern(
      "%f[%a]drop%a*%s+[%a']+%s+an%s+octave%f[%A]")
    or requests_pattern(
      "%f[%a]drop%a*%s+[%a']+%s+one%s+octave%f[%A]")
  local pitch_up_direction =
       requests_pattern("%f[%a]pitch%s+up%f[%A]")
    or requests_pattern("%f[%a]pitch%s+it%s+up%f[%A]")
    or requests_pattern(
      "%f[%a]pitch%s+the%s+[%a%-]+%s+up%f[%A]")
  local pitch_down_direction =
       requests_pattern("%f[%a]pitch%s+down%f[%A]")
    or requests_pattern("%f[%a]pitch%s+it%s+down%f[%A]")
    or requests_pattern(
      "%f[%a]pitch%s+the%s+[%a%-]+%s+down%f[%A]")
  local pitch_direction = pitch_up_direction or pitch_down_direction
  local octave_shifter = requests_term("octave shifter", true)
  local pitch_analysis =
       lower:find("pitch detector", 1, true) ~= nil
    or lower:find("%f[%a]tuner%f[%A]") ~= nil
    or lower:find("%f[%a]tuning%s+display%f[%A]") ~= nil
  local explicit_effect = shimmer or named_shift or transpose or harmonize
    or detune or granular_term or octave_shifter
    or octave_up or octave_down or pitch_direction or action_pitch
  local pitch_shift = explicit_effect or semitone_amount
  if not pitch_shift or (pitch_analysis and not explicit_effect) then
    return nil
  end

  local granular_pitch = shimmer or named_shift or transpose or harmonize
    or pitched_grains
    or octave_shifter
    or octave_up or pitch_direction or action_pitch or semitone_amount
  local down_direction = octave_down
    or pitch_down_direction
    or lower:find("%f[%a]drop%a*%f[%A]") ~= nil
    or lower:find("%f[%a]lower%a*%f[%A]") ~= nil
  local divider_topology =
       lower:find("%f[%a]divider%f[%A]") ~= nil
    or lower:find("sub octave", 1, true) ~= nil
    or lower:find("sub-octave", 1, true) ~= nil
    or (not octave_up and not pitch_up_direction and down_direction and (
         lower:find("%f[%a]rectif") ~= nil
         or lower:find("%f[%a]fuzz%f[%A]") ~= nil))
  if divider_topology then granular_pitch = false end
  local pitch_bundle = granular_term or granular_pitch or shimmer
    or (octave_down and not divider_topology)

  return {
    pitch_shift = true,
    granular = granular_pitch,
    granular_term = granular_term,
    shimmer = shimmer,
    pitch_bundle = pitch_bundle,
  }
end

-- Build the request-time safety note for JSFX pitch shifting without choosing
-- a topology the user did not ask for. The pinned jsfx_pitch bundle owns the
-- complete DSP recipes; this note only reinforces the failure shapes that have
-- repeatedly survived into first responses.
function Code.jsfx_pitch_preflight_note(user_text)
  local lower = tostring(user_text or ""):lower()
  local intent = Code.jsfx_pitch_intent(user_text)
  if not intent then return nil end
  local shimmer = intent.shimmer
  -- Bare detune and octave-up/down wording should still receive the universal
  -- indexed-buffer/ring safety below, but it does not by itself prove that the
  -- requested topology is a two-grain pitch shifter. Chorus/ensemble detune
  -- and divider/sub-octave effects are common counterexamples.
  local granular_pitch = intent.granular

  local function requests_pattern(pattern)
    local pos = 1
    while true do
      local first, last = lower:find(pattern, pos)
      if not first then return false end
      if Code.prompt_requests_jsfx_term(
          user_text, lower:sub(first, last), false) then
        return true
      end
      pos = math.max(last + 1, pos + 1)
    end
  end
  local explicit_minimal = shimmer and (
    Code.prompt_requests_jsfx_term(user_text, "one path", false)
    or Code.prompt_requests_jsfx_term(user_text, "one-path", false)
    or Code.prompt_requests_jsfx_term(user_text, "single path", false)
    or Code.prompt_requests_jsfx_term(user_text, "single-path", false)
    or Code.prompt_requests_jsfx_term(
      user_text, "one feedback path", false)
    or Code.prompt_requests_jsfx_term(
      user_text, "single feedback path", false)
    or Code.prompt_requests_jsfx_term(user_text, "one comb", false)
    or Code.prompt_requests_jsfx_term(user_text, "single comb", false)
    or requests_pattern("%f[%a]minimal%s+shimmer%f[%A]")
    or requests_pattern(
      "%f[%a]minimal%s+[%a%-]+%s+shimmer%f[%A]")
    or requests_pattern("%f[%a]shimmer%s+minimal%f[%A]"))
  local requests_full_tank =
    Code.prompt_requests_jsfx_term(user_text, "full tank", false)
  local requests_full_reverb =
    Code.prompt_requests_jsfx_term(user_text, "full reverb", false)
  local full_topology = shimmer and (
    Code.prompt_requests_jsfx_term(user_text, "parallel comb", true)
    or Code.prompt_requests_jsfx_term(user_text, "comb bank", true)
    or Code.prompt_requests_jsfx_term(user_text, "allpass", true)
    or Code.prompt_requests_jsfx_term(user_text, "diffusion", true)
    or requests_full_tank
    or requests_full_reverb
    or Code.prompt_requests_jsfx_term(user_text, "four comb", true)
    or Code.prompt_requests_jsfx_term(user_text, "4 comb", true)
    or Code.prompt_requests_jsfx_term(user_text, "cathedral", false))
  explicit_minimal = explicit_minimal and not full_topology

  local note = "Assign every indexed buffer base in @init. Audit every "
    .. "exact name[index] before replying: the identical name must be assigned "
    .. "a numeric base in @init; do not allocate apL1 and then index buf_apL1. "
    .. "Use separate delay/comb and pitch heads whenever those rings have "
    .. "different lengths or masks. Never index a pitch/grain buffer with an "
    .. "unmasked head from another ring. "
  if granular_pitch then
    note = note .. "INLINE the complete left and right two-grain paths; do not "
      .. "define a pitch/grain helper or pass persistent heads/offsets as "
      .. "helper parameters. For each channel, compute grain reads from that "
      .. "channel's live write head PLUS analysis offset. Copy this exact "
      .. "relationship for both channels: `analysis_step = pitch_ratio - 1;` "
      .. "then `read_index = (write_head + floor(analysis_offset)) & mask;`. "
      .. "DO NOT use a minus sign; an absolute buffer[floor(phase)] read or a "
      .. "minus-offset read is invalid. "
  end
  if shimmer then
    note = note .. "For shimmer, write the damped/DC-blocked comb read into "
      .. "the pitch buffer, never dry spl0/spl1, and consume pitch_outL/R in "
      .. "the feedback written back to the pitched comb; do not compute and "
      .. "abandon the pitched signal. "
    if explicit_minimal then
      note = note .. "The user explicitly requested a minimal one-path "
        .. "shimmer, so use one feedback delay/comb plus one pitch buffer per "
        .. "channel and do not add parallel comb banks or allpass stages. "
    else
      note = note .. "Preserve every requested shimmer topology and count. "
        .. "Do not collapse a requested comb bank, parallel paths, diffusion "
        .. "network, or allpass stages into a single comb. "
    end
  elseif intent.granular_term and not granular_pitch then
    note = note .. "This is a granular buffer request, not a pitch-shift "
      .. "request. It is not automatically a shimmer feedback reverb. Do not "
      .. "invent pitch transposition, a feedback comb, reverb tank, or allpass "
      .. "diffusion unless the user requested it. "
  elseif intent.pitch_bundle then
    note = note .. "This is a pitch-shift request, not automatically a "
      .. "shimmer feedback reverb. Do not invent a feedback comb, reverb tank, "
      .. "or allpass diffusion unless the user requested it. "
  end
  return note
end

-- =============================================================================

-- Code.validate_jsfx
-- =============================================================================
-- Static analysis for generated JSFX before auto-save / auto-run. Returns a
-- list of findings; each: { severity, code, line, message }. Severity is
-- "fatal" (would gate auto-run + qualify for one retry) or "warn" (advisory).
-- Calibrated against C:\REAPER\Effects (264 standalone stock + community JSFX)
-- to keep per-rule false-positive rates at or below ~3.5%. The audit harness
-- lives in Dev/Tests/corpus_audit.lua (gitignored); regression tests live
-- alongside it in Dev/Tests/test_*.lua.
--
-- Rules:
--  fatal  missing_desc          first non-comment content not `desc:`
--  fatal  reaper_api            `reaper` reference (JSFX has no ReaScript API)
--  fatal  generated_gmem        user JSFX declares/uses gmem, which blocks
--                               ReaAssist's injected safety ceiling namespace
--  fatal  output_ceiling_slider user JSFX declares a duplicate safety/output
--                               ceiling/limit slider instead of leaving the
--                               host-injected safety ceiling separate
--  fatal  banned_braces         `{` or `}` outside header lines / strings / comments
--  fatal  banned_else           bare `else` keyword (no else in EEL2)
--  fatal  banned_end_statement  Lua-style standalone `end;` terminator
--  fatal  banned_math_prefix    `math.X` (EEL2 uses bare `sin`, `cos`, ...)
--  fatal  banned_for_loop       C-style `for(...)` (use `loop()` or `while()`)
--  fatal  invalid_section_marker malformed/plural/misspelled JSFX section markers
--  fatal  feedback_unclamped    feedback-named slider can exceed 0.85 with no
--                               `0.85` clamp visible (Prompts.md mandate)
--  fatal  memory_no_init        `id[...]` or `mem[id+...]` indexed but `id`
--                               is never assigned a base value (skipped when
--                               file uses `import`)
--  fatal  buffer_overlap        two declared buffers (`X = base; X_len = len;`
--                               where X is used as a memory base) have spans
--                               that intersect -- two filters writing to the
--                               same memory addresses
--  fatal  parallel_comb_doubled in @sample, 2+ buffer writes share the same
--                               additive feedback RHS (`bufN[wN] = input +
--                               <term>*<id>`). Identical content written to
--                               parallel buffers makes their summed reads
--                               loop-gain N*fb; runs away even with fb<=0.85
--  fatal  pitch_missing_write_head_offset an explicitly requested
--                               analysis/write-head pitch topology reads by
--                               an absolute phase instead of relating every
--                               analysis offset to the live write head
--  fatal  shimmer_pitch_from_dry a shimmer writes dry spl0/spl1 directly
--                               into its pitch-analysis buffer instead of the
--                               damped feedback-tank read
--  fatal  pitch_output_unused   a named pitched result is computed but never
--                               consumed by the final feedback signal
--  fatal  pitch_write_wrong_ring a pitch/grain buffer is written with a head
--                               that advances using a comb/delay ring mask
--  fatal  hard_clip_unrequested `min(max(audio, -T), T)` with T<=1.5 on a
--                               sample-touching expr, when user_text doesn't
--                               request clip/limit/distort
--  fatal  arg_count_mismatch    `id(...)` call to a built-in EEL2/JSFX
--                               function with fixed arity uses the wrong
--                               number of arguments (e.g. `memset(0, len)`
--                               instead of `memset(0, 0, len)`). Catches
--                               REAPER's `'%s' needs N prms` compile error
--                               class. Conservative arity table -- only
--                               functions with unambiguous fixed signatures.
--  warn   unknown_function      `id(...)` call where id is neither in the
--                               EEL2/JSFX whitelist nor user-defined; logged
--                               but not gated
do

-- Token helpers below operate on Code.tokenize_jsfx output from ReaAssist.lua.
-- They keep line numbers stable so findings can point at the generated JSFX
-- source the user sees in chat.
local function add(findings, sev, code, line, message)
  findings[#findings + 1] = { severity = sev, code = code, line = line, message = message }
end

local function next_significant(tokens, from)
  for i = from, #tokens do
    local t = tokens[i]
    if t.type ~= "ws" and t.type ~= "com" then return i, t end
  end
end

local function skip_ws(tokens, i)
  while tokens[i] and (tokens[i].type == "ws" or tokens[i].type == "com") do
    i = i + 1
  end
  return tokens[i] and i or nil
end

local function read_signed_num(tokens, i)
  i = skip_ws(tokens, i); if not i then return nil end
  local sign = 1
  if tokens[i].type == "other" and tokens[i].text == "-" then
    sign = -1
    i = skip_ws(tokens, i + 1); if not i then return nil end
  end
  if tokens[i].type ~= "num" then return nil end
  return sign * tonumber(tokens[i].text), i + 1
end

local function match_seq(tokens, start, pat)
  local i = start
  for _, p in ipairs(pat) do
    while tokens[i] and (tokens[i].type == "ws" or tokens[i].type == "com") do
      i = i + 1
    end
    local t = tokens[i]
    if not t then return false end
    if p.type and t.type ~= p.type then return false end
    if p.text and t.text ~= p.text then return false end
    i = i + 1
  end
  return true
end

local function find_seq_lines(tokens, pat)
  -- Only start matches at significant tokens. match_seq's leading-ws skip
  -- means starting from a ws/com token would otherwise produce a duplicate
  -- hit at the preceding line.
  local lines = {}
  for i = 1, #tokens do
    local t = tokens[i]
    if t.type ~= "ws" and t.type ~= "com" and match_seq(tokens, i, pat) then
      lines[#lines + 1] = t.line
    end
  end
  return lines
end

-- `sliderN:default<min,max,step>Name` (range optional).
local function parse_sliders(src)
  local out = {}
  local cur = 0
  for line_text in src:gmatch("([^\n]*)\n?") do
    cur = cur + 1
    local idx, def, rest = line_text:match("^%s*slider(%d+):([^<\n]*)(.*)$")
    if idx then
      local mn, mx, step, name
      local range, after = rest:match("^<([^>]*)>(.*)$")
      if range then
        mn, mx, step = range:match("^([^,]*),([^,]*),([^,]*)$")
        if not mn then mn, mx = range:match("^([^,]*),([^,]*)$") end
        name = after
      else
        name = rest
      end
      local raw_default = (def or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local var_name, default_value =
        raw_default:match("^([_%a][_%w]*)%s*=%s*(.+)$")
      out[#out + 1] = {
        index = tonumber(idx),
        default = raw_default,
        default_value = default_value
          and default_value:gsub("^%s+", ""):gsub("%s+$", "") or nil,
        var = var_name,
        min  = tonumber(((mn   or ""):gsub("%s", ""))),
        max  = tonumber(((mx   or ""):gsub("%s", ""))),
        step = tonumber(((step or ""):gsub("%s", ""))),
        name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""),
        line = cur,
      }
    end
  end
  return out
end

-- Header lines (slider, desc, tags, ...) are NOT EEL2 code: `{enum}` and
-- `[TAG]` text inside descriptions are legal there and must be skipped.
local function build_header_lines(src)
  local set = {}
  local n = 0
  for line_text in src:gmatch("([^\n]*)\n?") do
    n = n + 1
    if line_text:match("^%s*slider%d")
       or line_text:match("^%s*desc:")
       or line_text:match("^%s*filename:")
       or line_text:match("^%s*tags:")
       or line_text:match("^%s*author:")
       or line_text:match("^%s*in_pin:")
       or line_text:match("^%s*out_pin:")
       or line_text:match("^%s*options:")
       or line_text:match("^%s*import%s") then
      set[n] = true
    end
  end
  return set
end

local function check_desc(tokens, findings)
  local _, t = next_significant(tokens, 1)
  if not t then
    add(findings, "fatal", "missing_desc", 1, "Empty source; no `desc:` line found.")
    return
  end
  if not (t.type == "id" and t.text == "desc") then
    add(findings, "fatal", "missing_desc", t.line,
        "First non-comment content must be `desc:` line.")
  end
end

local function check_reaper_api(tokens, findings)
  for _, t in ipairs(tokens) do
    if t.type == "id" and t.text == "reaper" then
      add(findings, "fatal", "reaper_api", t.line,
          "JSFX has no access to the `reaper` object or ReaScript APIs; use JSFX host variables such as `tempo` and `srate`.")
    end
  end
end

local function check_generated_safety_conflicts(src, tokens, sliders, findings)
  local line_no = 0
  for line in tostring(src or ""):gmatch("([^\n]*)\n?") do
    line_no = line_no + 1
    if line:match("^%s*options:[^\r\n]*gmem%s*=") then
      add(findings, "fatal", "generated_gmem", line_no,
          "Do not declare `options:gmem=` in generated JSFX; ReaAssist injects its own gmem namespace for the safety output ceiling.")
    end
  end
  for i, t in ipairs(tokens or {}) do
    if t.type == "id" and t.text == "gmem" then
      local _, next_t = next_significant(tokens, i + 1)
      if next_t and next_t.type == "other" and next_t.text == "[" then
        add(findings, "fatal", "generated_gmem", t.line,
            "Do not read or write `gmem[]` in generated JSFX; it conflicts with ReaAssist's injected safety output ceiling state.")
      end
    end
  end
  for _, slider in ipairs(sliders or {}) do
    local lname = tostring(slider.name or ""):lower()
    if lname:find("output ceiling", 1, true)
       or lname:find("output limit", 1, true)
       or lname:find("output cap", 1, true)
       or lname:find("safety ceiling", 1, true)
       or (lname:find("safety", 1, true)
           and lname:find("output", 1, true)) then
      add(findings, "fatal", "output_ceiling_slider", slider.line,
          "Do not declare a safety/output ceiling or limiter slider in generated JSFX; keep the creative DSP separate and let ReaAssist inject the safety output ceiling.")
    end
  end
end

-- `end`, `then`, `return` are NOT reserved in EEL2 and stock JSFX uses them
-- as identifiers (e.g. `end = 18 * (2*$pi/16)`); banning them false-positives
-- on legit code. Only `else` is rare-enough as an identifier to keep.
local BANNED_BARE = {
  ["else"] = "EEL2 has no `else` keyword. Use ternary `cond ? a : b`.",
}

local function check_banned_syntax(tokens, header_lines, findings)
  for i, t in ipairs(tokens) do
    if t.type == "other" and (t.text == "{" or t.text == "}") then
      if not header_lines[t.line] then
        add(findings, "fatal", "banned_braces", t.line,
            "EEL2 has no `{}` blocks. Group statements with `(...)`.")
      end
    elseif (t.type == "id" or t.type == "kw") and BANNED_BARE[t.text] then
      add(findings, "fatal", "banned_" .. t.text, t.line, BANNED_BARE[t.text])
    elseif t.type == "id" and t.text == "end" then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == ";" then
        add(findings, "fatal", "banned_end_statement", t.line,
            "EEL2 does not use Lua-style `end;` terminators. Function and section bodies use `( ... );`.")
      end
    end
  end
  for _, line in ipairs(find_seq_lines(tokens, {
    { type = "id", text = "math" }, { type = "other", text = "." },
  })) do
    add(findings, "fatal", "banned_math_prefix", line,
        "EEL2 uses bare math functions (sin, cos, sqrt, ...). No `math.` prefix.")
  end
  for _, line in ipairs(find_seq_lines(tokens, {
    { type = "id", text = "for" }, { type = "other", text = "(" },
  })) do
    add(findings, "fatal", "banned_for_loop", line,
        "EEL2 has no C-style `for(...)`. Use `loop(N, ...)` or `while(cond) (...)`.")
  end
end

local INVALID_SECTION_MARKERS = {
  ["@samples"] = "JSFX section marker is `@sample` (singular), not `@samples`.",
  ["@sliders"] = "JSFX section marker is `@slider` (singular), not `@sliders`.",
  ["@blocks"] = "JSFX section marker is `@block` (singular), not `@blocks`.",
  ["@serialise"] = "JSFX section marker is `@serialize`, not `@serialise`.",
  ["@graphics"] = "JSFX graphics section marker is `@gfx`, not `@graphics`.",
}

local function check_section_markers(src, tokens, findings)
  local line_no = 0
  for line in tostring(src or ""):gmatch("([^\n]*)\n?") do
    line_no = line_no + 1
    local doubled = line:match("^%s*(@@+[%w_]+)")
    if doubled then
      add(findings, "fatal", "invalid_section_marker", line_no,
        "JSFX section markers use exactly one `@` (for example `@sample`), not `"
          .. doubled .. "`.")
    end
  end
  for _, t in ipairs(tokens) do
    if t.type == "kw" and INVALID_SECTION_MARKERS[t.text] then
      add(findings, "fatal", "invalid_section_marker", t.line,
        INVALID_SECTION_MARKERS[t.text])
    end
  end
end

-- Map slider max into a worst-case feedback coefficient under common
-- conventions: raw 0..1, raw coefficients up to 3, percent 0..100.
-- Anything else is treated as risky.
local function slider_max_coef(s)
  if not s.max then return nil end
  local mx = s.max
  if mx <= 3.001 then return mx end
  if mx <= 100.001 then return mx / 100 end
  return 1.5
end

local FEEDBACK_NAMES = { "feedback", "regen", "regeneration" }
local function name_is_feedback(name)
  local low = name:lower()
  if low:match("%f[%w]fb%f[^%w]") then return true end
  for _, p in ipairs(FEEDBACK_NAMES) do
    if low:find(p, 1, true) then return true end
  end
  return false
end

local function feedback_clamp_num_at(tokens, i)
  local t = tokens[i]
  if not t then return nil end
  if t.type == "num" then return tonumber(t.text) end
  if t.type == "other" and t.text == "." then
    local n = tokens[i + 1]
    if n and n.type == "num" then
      return tonumber("0." .. tostring(n.text))
    end
  end
  return nil
end

local function feedback_clamp_literal(v)
  return v and v >= 0.84 and v <= 0.85
end

local function token_is_feedback_id(t, feedback_ids)
  return t and t.type == "id" and feedback_ids[t.text] == true
end

local function feedback_call_span(tokens, open_i)
  local depth = 0
  for j = open_i, #tokens do
    local t = tokens[j]
    if t.type == "other" and t.text == "(" then
      depth = depth + 1
    elseif t.type == "other" and t.text == ")" then
      depth = depth - 1
      if depth == 0 then return j end
    end
  end
end

local function span_has_feedback_and_limit(tokens, a, b, feedback_ids, limit_ids)
  local has_feedback, has_limit = false, false
  for j = a, b do
    local t = tokens[j]
    if token_is_feedback_id(t, feedback_ids) then has_feedback = true end
    if feedback_clamp_literal(feedback_clamp_num_at(tokens, j)) then
      has_limit = true
    end
    if t and t.type == "id" and limit_ids and limit_ids[t.text] then
      has_limit = true
    end
    if has_feedback and has_limit then return true end
  end
  return false
end

local function feedback_clamp_limit_ids(tokens)
  local ids = {}
  for i, t in ipairs(tokens or {}) do
    if t.type == "id" then
      local eq_i = skip_ws(tokens, i + 1)
      if eq_i and tokens[eq_i].type == "other" and tokens[eq_i].text == "=" then
        local val_i = skip_ws(tokens, eq_i + 1)
        if val_i and feedback_clamp_literal(
            feedback_clamp_num_at(tokens, val_i)) then
          ids[t.text] = true
        end
      end
    end
  end
  return ids
end

local function add_slider_feedback_ids(feedback_ids, s)
  if s.index then feedback_ids["slider" .. tostring(s.index)] = true end
  if s.var and tostring(s.var):match("^[_%a][_%w]*$") then
    feedback_ids[tostring(s.var)] = true
  end
  local name = tostring(s.name or "")
  if name:match("^[_%a][_%w]*$") then feedback_ids[name] = true end
end

local function add_named_feedback_ids(feedback_ids, tokens)
  for _, t in ipairs(tokens or {}) do
    if t.type == "id" and name_is_feedback(t.text) then
      feedback_ids[t.text] = true
    end
  end
end

local function feedback_assignment_rhs_end(tokens, val_i)
  if not val_i or not tokens[val_i] then return nil end
  local line = tokens[val_i].line
  local depth = 0
  local j = val_i
  while j <= #tokens do
    local t = tokens[j]
    if t.line ~= line and depth == 0 then return j - 1 end
    if t.type == "other" then
      if t.text == "(" or t.text == "[" then
        depth = depth + 1
      elseif t.text == ")" or t.text == "]" then
        depth = math.max(0, depth - 1)
      elseif t.text == ";" and depth == 0 then
        return j - 1
      end
    end
    j = j + 1
  end
  return #tokens
end

local function span_has_feedback_id(tokens, a, b, feedback_ids)
  for j = a or 1, b or 0 do
    if token_is_feedback_id(tokens[j], feedback_ids) then return true end
  end
  return false
end

local FEEDBACK_ALIAS_BLOCKED_IDS = {
  mem = true, gmem = true,
  spl0 = true, spl1 = true, spl2 = true, spl3 = true,
  spl4 = true, spl5 = true, spl6 = true, spl7 = true,
  this = true,
}

local function feedback_alias_lhs_allowed(id_text)
  local id = tostring(id_text or "")
  if id == "" then return false end
  if FEEDBACK_ALIAS_BLOCKED_IDS[id] then return false end
  if id:match("^slider%d+$") then return false end
  return true
end

local function rhs_is_direct_feedback_copy(tokens, a, b, feedback_ids)
  local saw_feedback = false
  for j = a or 1, b or 0 do
    local t = tokens[j]
    if t and t.type ~= "ws" and t.type ~= "com" and t.type ~= "str" then
      if token_is_feedback_id(t, feedback_ids) then
        if saw_feedback then return false end
        saw_feedback = true
      elseif t.type == "other" and (t.text == "(" or t.text == ")") then
        -- harmless grouping around a direct alias copy
      else
        return false
      end
    end
  end
  return saw_feedback
end

local function feedback_ids_for_slider(tokens, s)
  local feedback_ids = {}
  add_slider_feedback_ids(feedback_ids, s)

  local changed = true
  while changed do
    changed = false
    for i, t in ipairs(tokens or {}) do
      if t.type == "id" and not feedback_ids[t.text]
         and feedback_alias_lhs_allowed(t.text) then
        local eq_i = skip_ws(tokens, i + 1)
        if eq_i and tokens[eq_i].type == "other"
           and tokens[eq_i].text == "=" then
          local val_i = skip_ws(tokens, eq_i + 1)
          local rhs_end = feedback_assignment_rhs_end(tokens, val_i)
          if rhs_end and span_has_feedback_id(tokens, val_i, rhs_end,
              feedback_ids)
             and (name_is_feedback(t.text)
                  or rhs_is_direct_feedback_copy(tokens, val_i, rhs_end,
                    feedback_ids)) then
            feedback_ids[t.text] = true
            changed = true
          end
        end
      end
    end
  end

  return feedback_ids
end

local function has_feedback_clamp_for_ids(tokens, feedback_ids, limit_ids)

  for i, t in ipairs(tokens or {}) do
    if t.type == "id"
       and (t.text == "min" or t.text == "max" or t.text == "clamp") then
      local open_i = skip_ws(tokens, i + 1)
      if open_i and tokens[open_i].type == "other"
         and tokens[open_i].text == "(" then
        local close_i = feedback_call_span(tokens, open_i)
        if close_i and span_has_feedback_and_limit(tokens, open_i, close_i,
            feedback_ids, limit_ids) then
          return true
        end
      end
    end
  end

  local line_state = {}
  for i, t in ipairs(tokens or {}) do
    if t.type ~= "ws" and t.type ~= "com" and t.type ~= "str" then
      local rec = line_state[t.line]
      if not rec then
        rec = { feedback = false, limit = false, ternary_q = false,
          ternary_colon = false, assign = false }
        line_state[t.line] = rec
      end
      if token_is_feedback_id(t, feedback_ids) then rec.feedback = true end
      if feedback_clamp_literal(feedback_clamp_num_at(tokens, i)) then
        rec.limit = true
      end
      if t.type == "id" and limit_ids[t.text] then rec.limit = true end
      if t.type == "other" and t.text == "?" then rec.ternary_q = true end
      if t.type == "other" and t.text == ":" then rec.ternary_colon = true end
      if t.type == "other" and t.text == "=" then rec.assign = true end
    end
  end
  for _, rec in pairs(line_state) do
    if rec.feedback and rec.limit and rec.ternary_q
       and (rec.ternary_colon or rec.assign) then
      return true
    end
  end
  return false
end

local function feedback_clamp_coverage(tokens, risky)
  local covered = {}
  local limit_ids = feedback_clamp_limit_ids(tokens)

  if #risky == 1 then
    local feedback_ids = feedback_ids_for_slider(tokens, risky[1])
    add_named_feedback_ids(feedback_ids, tokens)
    if has_feedback_clamp_for_ids(tokens, feedback_ids, limit_ids) then
      covered[1] = true
    end
    return covered
  end

  for i, s in ipairs(risky) do
    local feedback_ids = feedback_ids_for_slider(tokens, s)
    if has_feedback_clamp_for_ids(tokens, feedback_ids, limit_ids) then
      covered[i] = true
    end
  end
  return covered
end

local function check_feedback_clamp(tokens, sliders, findings)
  local risky = {}
  for _, s in ipairs(sliders) do
    if name_is_feedback(s.name)
       or name_is_feedback(tostring(s.var or ""))
       or name_is_feedback(tostring(s.default or "")) then
      local coef = slider_max_coef(s)
      if coef and coef > 0.85 then risky[#risky + 1] = s end
    end
  end
  if #risky == 0 then return end
  local covered = feedback_clamp_coverage(tokens, risky)
  for i, s in ipairs(risky) do
    if covered[i] then goto continue end
    add(findings, "fatal", "feedback_unclamped", s.line,
        ("Feedback-style slider `%s` reaches >0.85 effective coefficient with no `0.85` clamp visible. Per ReaAssist's JSFX safety rule, hard-clamp the feedback coefficient to <= 0.85.")
          :format(s.name))
    ::continue::
  end
end

local MEM_BUILTINS = { mem = 1, gmem = 1, spl0 = 1, spl1 = 1, spl2 = 1,
  spl3 = 1, spl4 = 1, spl5 = 1, spl6 = 1, spl7 = 1, this = 1 }

-- Has any token-level base assignment to id (`id =`, `id += ...`, etc.)?
-- An assignment to a slot (`id[expr] =`) does NOT count.
local function id_has_base_assignment(tokens, id_text)
  for i = 1, #tokens do
    local t = tokens[i]
    if t.type == "id" and t.text == id_text then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" then
        local jt = tokens[j].text
        if jt == "+" or jt == "-" or jt == "*" or jt == "/" then
          j = skip_ws(tokens, j + 1)
        end
        if j and tokens[j].type == "other" and tokens[j].text == "=" then
          local k = tokens[j + 1]
          if not (k and k.type == "other" and k.text == "=") then
            return true
          end
        end
      end
    end
  end
  return false
end

local function prev_significant_index(tokens, i)
  i = i - 1
  while i >= 1 and (tokens[i].type == "ws" or tokens[i].type == "com") do
    i = i - 1
  end
  return i >= 1 and i or nil
end

local function matching_paren_index(tokens, open_i)
  if not (tokens[open_i] and tokens[open_i].type == "other"
      and tokens[open_i].text == "(") then
    return nil
  end
  local depth = 0
  for i = open_i, #tokens do
    local t = tokens[i]
    if t.type == "other" and t.text == "(" then
      depth = depth + 1
    elseif t.type == "other" and t.text == ")" then
      depth = depth - 1
      if depth == 0 then return i end
    end
  end
  return nil
end

local function split_call_args(tokens, open_i, close_i)
  local out = {}
  local start_i = skip_ws(tokens, open_i + 1)
  if not start_i or start_i >= close_i then return out end
  local depth = 0
  local arg_start = start_i
  for i = start_i, close_i - 1 do
    local t = tokens[i]
    if t.type == "other" then
      if t.text == "(" or t.text == "[" then
        depth = depth + 1
      elseif t.text == ")" or t.text == "]" then
        depth = math.max(0, depth - 1)
      elseif t.text == "," and depth == 0 then
        out[#out + 1] = { first = arg_start, last = i - 1 }
        arg_start = skip_ws(tokens, i + 1) or (i + 1)
      end
    end
  end
  out[#out + 1] = { first = arg_start, last = close_i - 1 }
  return out
end

local function single_id_arg(tokens, arg)
  if not (arg and arg.first) then return nil end
  local first_i = skip_ws(tokens, arg.first)
  if not first_i or first_i > (arg.last or 0) then return nil end
  local t = tokens[first_i]
  if not (t and t.type == "id") then return nil end
  local next_i = skip_ws(tokens, first_i + 1)
  if next_i and next_i <= arg.last then return nil end
  return t.text
end

local function function_param_memory_bases(tokens, header_lines)
  local funcs = {}
  for i, t in ipairs(tokens or {}) do
    if t.type == "kw" and t.text == "function" then
      local name_i, name_t = next_significant(tokens, i + 1)
      if name_t and name_t.type == "id" then
        local params_open = skip_ws(tokens, name_i + 1)
        if params_open and tokens[params_open].type == "other"
           and tokens[params_open].text == "(" then
          local params_close = matching_paren_index(tokens, params_open)
          local body_open = params_close and skip_ws(tokens, params_close + 1)
          local body_close = body_open and matching_paren_index(tokens, body_open)
          if body_close then
            funcs[#funcs + 1] = {
              name = name_t.text,
              params = split_call_args(tokens, params_open, params_close),
              body_open = body_open,
              body_close = body_close,
            }
          end
        end
      end
    end
  end

  local safe = {}
  for _, fn in ipairs(funcs) do
    local indexed_params = {}
    local param_pos = {}
    for idx, arg in ipairs(fn.params) do
      local id = single_id_arg(tokens, arg)
      if id then param_pos[id] = idx end
    end
    for i = fn.body_open + 1, fn.body_close - 1 do
      local t = tokens[i]
      if t and t.type == "id" and param_pos[t.text] then
        local j = skip_ws(tokens, i + 1)
        if j and tokens[j].type == "other" and tokens[j].text == "[" then
          indexed_params[t.text] = param_pos[t.text]
        end
      end
    end
    if next(indexed_params) then
      local calls, all_safe = 0, true
      for i, t in ipairs(tokens or {}) do
        if t.type == "id" and t.text == fn.name
           and not header_lines[t.line] then
          local p = prev_significant_index(tokens, i)
          local is_definition = p and tokens[p].type == "kw"
            and tokens[p].text == "function"
          if not is_definition then
            local open_i = skip_ws(tokens, i + 1)
            if open_i and tokens[open_i].type == "other"
               and tokens[open_i].text == "(" then
              local close_i = matching_paren_index(tokens, open_i)
              if close_i then
                calls = calls + 1
                local args = split_call_args(tokens, open_i, close_i)
                for _, param_idx in pairs(indexed_params) do
                  local arg_id = single_id_arg(tokens, args[param_idx])
                  if not arg_id or (not MEM_BUILTINS[arg_id]
                      and not id_has_base_assignment(tokens, arg_id)) then
                    all_safe = false
                    break
                  end
                end
              end
            end
          end
        end
        if not all_safe then break end
      end
      if calls > 0 and all_safe then
        for id in pairs(indexed_params) do
          safe[#safe + 1] = {
            id = id,
            body_open = fn.body_open,
            body_close = fn.body_close,
          }
        end
      end
    end
  end
  return safe
end

local function function_param_base_is_safe(safe_param_bases, id_text, token_i)
  for _, rec in ipairs(safe_param_bases or {}) do
    if rec.id == id_text
       and token_i > rec.body_open
       and token_i < rec.body_close then
      return true
    end
  end
  return false
end

local function check_memory_init(tokens, header_lines, has_imports, findings)
  if has_imports then return end
  local seen = {}
  local safe_param_bases = function_param_memory_bases(tokens, header_lines)

  local function maybe_fire(id_text, line, token_i)
    if MEM_BUILTINS[id_text] then return end
    if id_text:match("^slider%d+$") then return end
    if function_param_base_is_safe(safe_param_bases, id_text, token_i) then
      return
    end
    if seen[id_text] then return end
    seen[id_text] = true
    if not id_has_base_assignment(tokens, id_text) then
      add(findings, "fatal", "memory_no_init", line,
          ("Indexed access on `%s[...]` but `%s` is never assigned a base value (no `%s = ...` anywhere). Initialize the buffer base in @init.")
            :format(id_text, id_text, id_text))
    end
  end

  for i = 1, #tokens - 1 do
    local a = tokens[i]
    if a.type == "id" and not header_lines[a.line] then
      if a.text == "mem" or a.text == "gmem" then
        -- Pattern: `mem [ id` -- the id is the buffer base.
        local j = skip_ws(tokens, i + 1)
        if j and tokens[j].type == "other" and tokens[j].text == "[" then
          local k = skip_ws(tokens, j + 1)
          if k and tokens[k].type == "id" and not header_lines[tokens[k].line] then
            maybe_fire(tokens[k].text, tokens[k].line, k)
          end
        end
      else
        -- Pattern: `id [ ...` -- direct array indexing.
        local _, b = next_significant(tokens, i + 1)
        if b and b.type == "other" and b.text == "["
           and not header_lines[b.line] then
          maybe_fire(a.text, a.line, i)
        end
      end
    end
  end
end

-- buffer_overlap: detect pairs of declared buffer regions whose memory
-- spans overlap. A buffer is recognized when an id has BOTH a literal-int
-- base assignment AND a matching `<id>_len` (or `_length` / `_size`)
-- literal assignment, AND is used somewhere as a memory base (`id[...]` or
-- `mem[id + ...]`). Each overlapping pair fires its own fatal finding so
-- the model can fix the layout holistically on retry.
local LENGTH_SUFFIXES = { "_len", "_length", "_size" }

local function check_buffer_overlap(tokens, findings)
  -- Step 1: collect current `id = <integer literal>` assignments. If the
  -- same id is later assigned from an expression, drop the earlier literal
  -- evidence; the static checker cannot safely prove that final base.
  local assigns = {}
  for i = 1, #tokens do
    local t = tokens[i]
    if t.type == "id" then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == "=" then
        local nxt = tokens[j + 1]
        if not (nxt and nxt.type == "other" and nxt.text == "=") then
          local v = read_signed_num(tokens, j + 1)
          if v and v == math.floor(v) and v >= 0 then
            assigns[t.text] = { value = v, line = t.line }
          else
            assigns[t.text] = nil
          end
        end
      end
    end
  end

  -- Step 2: pair bases with length companions.
  local candidates = {}
  for id, info in pairs(assigns) do
    local is_len = false
    for _, suf in ipairs(LENGTH_SUFFIXES) do
      if id:sub(-#suf) == suf then is_len = true; break end
    end
    if not is_len then
      for _, suf in ipairs(LENGTH_SUFFIXES) do
        local len_info = assigns[id .. suf]
        if len_info and len_info.value > 0 then
          candidates[#candidates + 1] = {
            id = id, base = info.value,
            length = len_info.value, line = info.line,
          }
          break
        end
      end
    end
  end

  -- Step 3: confirm each candidate is actually used as a memory base.
  local used_as_base = {}
  for i = 1, #tokens - 1 do
    local t = tokens[i]
    if t.type == "id" then
      if t.text == "mem" or t.text == "gmem" then
        local j = skip_ws(tokens, i + 1)
        if j and tokens[j].type == "other" and tokens[j].text == "[" then
          local k = skip_ws(tokens, j + 1)
          if k and tokens[k].type == "id" then
            used_as_base[tokens[k].text] = true
          end
        end
      else
        local j = skip_ws(tokens, i + 1)
        if j and tokens[j].type == "other" and tokens[j].text == "[" then
          used_as_base[t.text] = true
        end
      end
    end
  end

  local buffers = {}
  for _, c in ipairs(candidates) do
    if used_as_base[c.id] then buffers[#buffers + 1] = c end
  end

  -- Step 4: pairwise overlap check. Each overlap fires a separate finding.
  for i = 1, #buffers do
    for j = i + 1, #buffers do
      local b1, b2 = buffers[i], buffers[j]
      local lo1, hi1 = b1.base, b1.base + b1.length - 1
      local lo2, hi2 = b2.base, b2.base + b2.length - 1
      if lo1 <= hi2 and lo2 <= hi1 then
        local first, second = b1, b2
        if first.base > second.base then first, second = second, first end
        local overlap = math.min(hi1, hi2) - math.max(lo1, lo2) + 1
        add(findings, "fatal", "buffer_overlap",
            math.max(b1.line, b2.line),
            ("Buffer `%s` (base=%d, len=%d -> owns %d..%d) overlaps buffer `%s` (base=%d, len=%d -> owns %d..%d) by %d samples. Each filter must own a non-overlapping memory region.")
              :format(
                first.id, first.base, first.length,
                first.base, first.base + first.length - 1,
                second.id, second.base, second.length,
                second.base, second.base + second.length - 1,
                overlap))
      end
    end
  end
end

local function find_hard_clip_clamps(tokens)
  local out = {}
  for i = 1, #tokens do
    local t = tokens[i]
    if t.type == "id" and t.text == "min" then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == "(" then
        local k = skip_ws(tokens, j + 1)
        if k and tokens[k].type == "id" and tokens[k].text == "max" then
          local m = skip_ws(tokens, k + 1)
          if m and tokens[m].type == "other" and tokens[m].text == "(" then
            local depth = 1
            local expr_start, expr_end = m + 1, nil
            local q = m + 1
            while tokens[q] do
              local x = tokens[q]
              if x.type == "other" then
                if x.text == "(" then depth = depth + 1
                elseif x.text == ")" then depth = depth - 1; if depth == 0 then break end
                elseif x.text == "," and depth == 1 then expr_end = q - 1; break end
              end
              q = q + 1
            end
            if expr_end then
              local lo, lo_after = read_signed_num(tokens, q + 1)
              if lo then
                local close_max = skip_ws(tokens, lo_after)
                if close_max and tokens[close_max].type == "other"
                   and tokens[close_max].text == ")" then
                  local comma2 = skip_ws(tokens, close_max + 1)
                  if comma2 and tokens[comma2].type == "other"
                     and tokens[comma2].text == "," then
                    local hi, _ = read_signed_num(tokens, comma2 + 1)
                    if hi then
                      local pieces = {}
                      for r = expr_start, expr_end do
                        if tokens[r].type ~= "ws" and tokens[r].type ~= "com" then
                          pieces[#pieces + 1] = tokens[r].text
                        end
                      end
                      out[#out + 1] = {
                        line = t.line,
                        threshold = math.max(math.abs(lo), math.abs(hi)),
                        expr_text = table.concat(pieces, " "),
                      }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return out
end

local function expr_touches_audio(expr_text)
  return expr_text:match("%f[%w]spl%d+%f[^%w]") ~= nil
end

local CLIP_INTENT = { "clip", "limit", "limiter", "brick", "wall", "fuzz",
  "crush", "distort", "saturate", "drive", "hard" }

local function user_requested_clip(user_text)
  if not user_text or user_text == "" then return false end
  local low = user_text:lower()
  for _, w in ipairs(CLIP_INTENT) do
    if low:find(w, 1, true) then return true end
  end
  return false
end

local function check_hard_clip(tokens, user_text, findings)
  if user_requested_clip(user_text) then return end
  for _, c in ipairs(find_hard_clip_clamps(tokens)) do
    if c.threshold <= 1.5 and expr_touches_audio(c.expr_text) then
      add(findings, "fatal", "hard_clip_unrequested", c.line,
          ("Hard-clip pattern min(max(audio, -%g), %g) on a sample-touching expression without explicit user request for clip/limit/distort. Use soft saturation `x/(1+abs(x))` instead (tanh is NOT a JSFX built-in -- define it inline if needed).")
            :format(math.abs(c.threshold), c.threshold))
      return
    end
  end
end

-- parallel_comb_doubled: in @sample, multiple buffer writes share the same
-- feedback-style RHS expression. Pattern signature: 2+ writes of the form
-- `bufN[idx] = <RHS> ;` where the RHS is textually identical AND contains
-- both a `+` operator (additive feedback structure: `input + feedback_term`)
-- and a `<term> * <id>` subsequence (the feedback-coefficient multiplication).
--
-- Why this catches the runaway-feedback pattern: a Schroeder-style comb bank
-- requires each comb's write to feed back from its OWN read (cN[wN] =
-- input + fN * fb). When the model instead computes one shared feedback
-- signal and writes it into N parallel combs, all N buffers hold identical
-- content; their summed reads form a feedback path with loop gain N*fb,
-- well above unity even when fb=0.85. From any seed the signal grows
-- exponentially until the soft-saturator (if any) clamps -- the user hears
-- silence -> ramp -> pinned at full scale, often loud enough to damage
-- speakers/ears.
--
-- The `+` AND `*<id>` requirement filters out benign shared-write patterns
-- (`bufL[wL] = mono; bufR[wR] = mono;`) and pure gain applications
-- (`bufL[wL] = spl0 * gain;`). Calibrated against C:\REAPER\Effects: zero
-- false positives on stock JSFX; fires only on ReaAssist-generated reverbs
-- that produced the exact runaway-feedback bug.
local function check_parallel_comb_doubled(tokens, header_lines, has_imports, findings)
  if has_imports then return end

  -- Find @sample section bounds. JSFX_KEYWORDS doesn't mark @sections as kw,
  -- so the production tokenizer assigns them type "kw" with text "@sample"
  -- (see Code.tokenize_jsfx; @-prefixed sections get the kw type explicitly).
  local sample_start, sample_end
  for i = 1, #tokens do
    local t = tokens[i]
    if t.type == "kw" and t.text:sub(1, 1) == "@" then
      if t.text == "@sample" and not sample_start then
        sample_start = i + 1
      elseif sample_start and t.text ~= "@sample" then
        sample_end = i - 1
        break
      end
    end
  end
  if not sample_start then return end
  if not sample_end then sample_end = #tokens end

  -- Inner helper: walk RHS [rhs_start, rhs_end_excl) and return
  --   pieces            -- joined text, used as fingerprint
  --   has_plus          -- top-level `+` operator seen
  --   has_mult_by_id    -- explicit `<term> * <id>` in this RHS
  --   ref_ids           -- set of bare ids referenced in this RHS
  local function scan_rhs(rhs_start, rhs_end_excl)
    local pieces, has_plus, has_mult_by_id, ref_ids = {}, false, false, {}
    local prev_was_star, depth3 = false, 0
    for r = rhs_start, rhs_end_excl - 1 do
      local tr = tokens[r]
      if tr.type ~= "ws" and tr.type ~= "com" then
        pieces[#pieces + 1] = tr.text
        if tr.type == "other" then
          if tr.text == "(" or tr.text == "[" then depth3 = depth3 + 1
          elseif tr.text == ")" or tr.text == "]" then depth3 = depth3 - 1 end
          if tr.text == "+" and depth3 == 0 then has_plus = true end
        end
        if prev_was_star and tr.type == "id" then has_mult_by_id = true end
        if tr.type == "id" then ref_ids[tr.text] = true end
        prev_was_star = (tr.type == "other" and tr.text == "*")
      end
    end
    return table.concat(pieces, " "), has_plus, has_mult_by_id, ref_ids
  end

  -- Pass 1: collect feedback-flavored temp identifiers. The model can evade
  -- a "RHS contains <term> * <id>" check by hoisting the multiplication into
  -- a temp earlier in @sample (Opus retry pattern: `combfb_L = fbL *
  -- fb_smooth; buf_cL0[wL0] = inL + combfb_L; buf_cL1[wL1] = inL + combfb_L;
  -- ...`). We track `id = <expr containing <id>*<id>> ;` assignments and
  -- treat any later RHS that references one of those temps as if it had a
  -- direct `* <id>`.
  local feedback_temps = {}
  local assignment_events = {}
  do
    local i2 = sample_start
    while i2 <= sample_end do
      local t = tokens[i2]
      if t.type == "id" and not header_lines[t.line] then
        local j = skip_ws(tokens, i2 + 1)
        -- Look for `id = ...;` (NOT `id [ ... ] = ...;` which is a buffer
        -- write handled in pass 2, NOT `==` which is comparison).
        if j and tokens[j].type == "other" and tokens[j].text == "="
           and not (tokens[j+1] and tokens[j+1].type == "other"
                     and tokens[j+1].text == "=") then
          assignment_events[#assignment_events + 1] = {
            id = t.text,
            pos = i2,
          }
          local rhs_start = j + 1
          local depth_p1, m = 0, rhs_start
          while m <= sample_end do
            local tm = tokens[m]
            if tm.type == "other" then
              if tm.text == "(" or tm.text == "[" then depth_p1 = depth_p1 + 1
              elseif tm.text == ")" or tm.text == "]" then depth_p1 = depth_p1 - 1
              elseif tm.text == ";" and depth_p1 == 0 then break end
            end
            m = m + 1
          end
          if m <= sample_end then
            local _, _, has_mult = scan_rhs(rhs_start, m)
            if has_mult then feedback_temps[t.text] = true end
            i2 = m
          end
        end
      end
      i2 = i2 + 1
    end
  end

  -- Pass 2: walk @sample, collect buffer-write signatures.
  local writes = {}
  local i = sample_start
  while i <= sample_end do
    local t = tokens[i]
    if t.type == "id" and not header_lines[t.line] then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == "[" then
        local idx_start = j + 1
        local depth = 1
        local k = j + 1
        while k <= sample_end and depth > 0 do
          local tk = tokens[k]
          if tk.type == "other" then
            if tk.text == "[" then depth = depth + 1
            elseif tk.text == "]" then depth = depth - 1 end
          end
          k = k + 1
        end
        if depth == 0 then
          -- Capture the index expression text so two writes to the SAME
          -- buffer at different offsets count as distinct LHS slots
          -- (Gemini's flat-buffer-with-tap-offsets evasion).
          local idx_pieces = {}
          for r = idx_start, k - 2 do
            local tr = tokens[r]
            if tr.type ~= "ws" and tr.type ~= "com" then
              idx_pieces[#idx_pieces + 1] = tr.text
            end
          end
          local lhs_idx = table.concat(idx_pieces, " ")
          local eq = skip_ws(tokens, k)
          if eq and tokens[eq].type == "other" and tokens[eq].text == "=" then
            local nxt = tokens[eq + 1]
            if not (nxt and nxt.type == "other" and nxt.text == "=") then
              local rhs_start = eq + 1
              local depth2 = 0
              local m = rhs_start
              while m <= sample_end do
                local tm = tokens[m]
                if tm.type == "other" then
                  if tm.text == "(" or tm.text == "[" then depth2 = depth2 + 1
                  elseif tm.text == ")" or tm.text == "]" then depth2 = depth2 - 1
                  elseif tm.text == ";" and depth2 == 0 then break end
                end
                m = m + 1
              end
              if m <= sample_end then
                local fp, has_plus, has_mult_by_id, ref_ids =
                  scan_rhs(rhs_start, m)
                local has_mult_via_temp = false
                for id_name in pairs(ref_ids) do
                  if feedback_temps[id_name] then
                    has_mult_via_temp = true
                    break
                  end
                end
                writes[#writes + 1] = {
                  lhs_buf            = t.text,
                  lhs_idx            = lhs_idx,
                  fingerprint        = fp,
                  pos                = i,
                  line               = t.line,
                  has_plus           = has_plus,
                  has_mult_by_id     = has_mult_by_id,
                  has_mult_via_temp  = has_mult_via_temp,
                  ref_ids            = ref_ids,
                }
                i = m
              end
            end
          end
        end
      end
    end
    i = i + 1
  end

  local function rhs_ref_reassigned_between(ref_ids, a_pos, b_pos)
    if not ref_ids or not a_pos or not b_pos then return false end
    for _, ev in ipairs(assignment_events) do
      if ev.pos > a_pos and ev.pos < b_pos and ref_ids[ev.id] then
        return true
      end
    end
    return false
  end

  -- Group qualifying writes by RHS fingerprint; fire when 2+ distinct
  -- (buffer, index) write slots share the same feedback expression. The
  -- (buffer, index) tuple catches both topologies that produce identical
  -- content in N parallel taps:
  --   - N distinct buffers, same RHS  (classic Schroeder error)
  --   - 1 buffer, N distinct offsets, same RHS  (flat-buffer/tap-offset
  --     workaround; same loop-gain explosion since each region gets the
  --     same input-plus-shared-feedback every sample)
  local groups = {}
  for _, w in ipairs(writes) do
    if w.has_plus and (w.has_mult_by_id or w.has_mult_via_temp) then
      local list = groups[w.fingerprint]
      if not list then list = {}; groups[w.fingerprint] = list end
      local g = list[#list]
      if not g
         or rhs_ref_reassigned_between(w.ref_ids, g.last.pos, w.pos) then
        g = { members = {} }
        list[#list + 1] = g
      end
      g.members[#g.members + 1] = w
      g.last = w
    end
  end
  local reported = {}
  for fp, list in pairs(groups) do
    for _, g in ipairs(list) do
      local distinct = {}
      local distinct_bufs = {}
      for _, mem in ipairs(g.members) do
        distinct[mem.lhs_buf .. "[" .. mem.lhs_idx .. "]"] = true
        distinct_bufs[mem.lhs_buf] = true
      end
      local slots = {}
      for n in pairs(distinct) do slots[#slots + 1] = n end
      local bufs = {}
      for n in pairs(distinct_bufs) do bufs[#bufs + 1] = n end
      if #slots >= 2 and not reported[fp] then
        reported[fp] = true
        table.sort(slots)
        table.sort(bufs)
        local first = g.members[1]
        -- Tailor the message body to which evasion path was hit so the retry
        -- hint sent back to the model is specific (different buffers vs same
        -- buffer at different offsets).
        local target_phrase
        if #bufs >= 2 then
          target_phrase = ("%d different buffers (%s)")
            :format(#bufs, table.concat(bufs, ", "))
        else
          target_phrase = ("the same buffer `%s` at %d different offsets")
            :format(bufs[1], #slots)
        end
        add(findings, "fatal", "parallel_comb_doubled", first.line,
            ("Same feedback expression `%s` written to %s inside @sample. Each parallel comb must take its feedback from its OWN read (`cN[wN] = input + fN * fb`); writing one shared feedback signal to N parallel slots makes all N hold identical content, and the summed read path then has loop gain N*fb (well above unity for any N>=2 with fb=0.85), producing exponential runaway feedback that can damage speakers.")
              :format(fp, target_phrase))
      end
    end
  end
end

-- unknown_function: flag function calls whose name is neither in the EEL2/
-- JSFX built-in whitelist nor user-defined in this file. Severity is `warn`
-- (advisory only -- not gated for retry) since the whitelist may need
-- expansion as new EEL2 functions are added by Cockos.
local KNOWN_FUNCTIONS = {
  -- Math
  ["sin"]=1, ["cos"]=1, ["tan"]=1, ["asin"]=1, ["acos"]=1,
  ["atan"]=1, ["atan2"]=1, ["sinh"]=1, ["cosh"]=1,
  -- NOTE: `tanh` is NOT a JSFX/EEL2 built-in. REAPER's compiler reports
  -- `'tanh' undefined`. Stock JSFX (Tukan, cookdsp) defines tanh as a
  -- user function. Do NOT add tanh here unless Cockos adds it natively.
  ["sqrt"]=1, ["sqr"]=1, ["pow"]=1, ["exp"]=1,
  ["log"]=1, ["log10"]=1, ["log2"]=1,
  ["abs"]=1, ["floor"]=1, ["ceil"]=1, ["min"]=1, ["max"]=1,
  ["sign"]=1, ["mod"]=1, ["invsqrt"]=1, ["rand"]=1, ["sleep"]=1,
  -- Bit (functional form)
  ["xor"]=1, ["shl"]=1, ["shr"]=1, ["bitor"]=1, ["bitand"]=1,
  -- Memory
  ["memcpy"]=1, ["memset"]=1, ["__memtop"]=1, ["freembuf"]=1,
  ["mem_set_values"]=1, ["mem_get_values"]=1, ["mem_insert_shuffle"]=1,
  -- Stack
  ["stack_push"]=1, ["stack_pop"]=1, ["stack_peek"]=1, ["stack_exch"]=1,
  -- String
  ["strlen"]=1, ["strcpy"]=1, ["strcmp"]=1, ["stricmp"]=1,
  ["strncmp"]=1, ["strnicmp"]=1, ["strncpy"]=1, ["strcat"]=1, ["strncat"]=1,
  ["strcpy_from"]=1, ["strcpy_substr"]=1, ["strcpy_fromslider"]=1,
  ["str_getchar"]=1, ["str_setchar"]=1, ["str_setlen"]=1,
  ["str_insert"]=1, ["str_delete_sub"]=1,
  ["match"]=1, ["matchi"]=1, ["sprintf"]=1, ["printf"]=1,
  ["atof"]=1, ["atoi"]=1,
  -- File
  ["file_open"]=1, ["file_close"]=1, ["file_avail"]=1, ["file_var"]=1,
  ["file_mem"]=1, ["file_riff"]=1, ["file_string"]=1, ["file_text"]=1,
  ["file_rewind"]=1,
  -- FFT / MDCT
  ["fft"]=1, ["ifft"]=1, ["fft_real"]=1, ["ifft_real"]=1,
  ["fft_permute"]=1, ["fft_ipermute"]=1, ["convolve_c"]=1,
  ["mdct"]=1, ["imdct"]=1, ["mdct_real"]=1, ["imdct_real"]=1,
  -- MIDI
  ["midisend"]=1, ["midirecv"]=1, ["midisend_buf"]=1, ["midirecv_buf"]=1,
  ["midisyx"]=1, ["midisend_str"]=1, ["midirecv_str"]=1,
  -- JSFX-specific
  ["slider"]=1, ["slider_automate"]=1, ["slider_next_chg"]=1,
  ["sliderchange"]=1, ["slider_show"]=1, ["spl"]=1,
  ["get_pin_mapping"]=1, ["set_pin_mapping"]=1,
  ["get_pinmapper_flags"]=1, ["set_pinmapper_flags"]=1,
  ["get_host_numchan"]=1, ["set_host_numchan"]=1,
  ["export_buffer_to_project"]=1,
  -- Atomics (newer EEL2)
  ["atomic_set"]=1, ["atomic_add"]=1, ["atomic_exch"]=1,
  ["atomic_or"]=1, ["atomic_and"]=1, ["atomic_xor"]=1,
  ["atomic_setifequal"]=1, ["atomic_get"]=1,
  -- GFX
  ["gfx_setpixel"]=1, ["gfx_getpixel"]=1, ["gfx_set"]=1, ["gfx_setcursor"]=1,
  ["gfx_setfont"]=1, ["gfx_getfont"]=1,
  ["gfx_line"]=1, ["gfx_lineto"]=1, ["gfx_rect"]=1, ["gfx_rectto"]=1,
  ["gfx_circle"]=1, ["gfx_arc"]=1, ["gfx_triangle"]=1,
  ["gfx_roundrect"]=1, ["gfx_gradrect"]=1, ["gfx_muladdrect"]=1,
  ["gfx_deltablit"]=1, ["gfx_blit"]=1, ["gfx_blitext"]=1,
  ["gfx_blit_ext"]=1, ["gfx_blit2"]=1, ["gfx_blitext2"]=1,
  ["gfx_loadimg"]=1, ["gfx_setimgdim"]=1, ["gfx_getimgdim"]=1,
  ["gfx_imgresize"]=1,
  ["gfx_drawchar"]=1, ["gfx_drawnumber"]=1, ["gfx_drawstr"]=1,
  ["gfx_measurestr"]=1, ["gfx_printf"]=1, ["gfx_setdest"]=1, ["gfx_clear"]=1,
  ["gfx_showmenu"]=1, ["gfx_getchar"]=1, ["gfx_getdropfile"]=1,
  ["gfx_blurto"]=1, ["gfx_getsyscol"]=1,
  -- EEL2 control flow / structural (callable-form: `loop(N, ...)`)
  ["loop"]=1, ["while"]=1, ["function"]=1, ["if"]=1,
  ["local"]=1, ["global"]=1, ["globals"]=1, ["instance"]=1, ["this"]=1,
  -- Time / misc
  ["time_precise"]=1, ["time"]=1,
  ["__denormal_likely_zero"]=1,
}

-- Built-in EEL2/JSFX functions with a strictly-fixed argument count. An
-- arity mismatch is a compile-time error in REAPER ("'memset' needs 3 prms").
-- Conservative list -- only functions where the signature is unambiguous in
-- the EEL2 / JSFX docs. Variadic builtins (mem_set_values, gfx_*, midisend
-- with optional ext bytes, etc.), default-arg builtins (rand which is 0-or-1
-- arg), and anything I'm not 100% sure about are intentionally absent --
-- false-fire on a legitimate call costs more than missing one or two
-- additional bug classes.
local FIXED_ARITY = {
  -- Memory ops: most-frequently-misused class (LLMs often forget the
  -- `value` arg on memset, the `count` arg on memcpy).
  memset = 3,    -- memset(dest, value, count)
  memcpy = 3,    -- memcpy(dest, src,   count)
  -- Math two-arg
  pow   = 2,     -- pow(base, exp)
  atan2 = 2,     -- atan2(y, x)
  -- Slider control
  sliderchange = 1,  -- sliderchange(slider_idx)
  -- Memory single-arg
  freembuf = 1,  -- freembuf(start_idx)
  -- Misc
  sleep = 1,     -- sleep(ms)
}

-- Returns the arg count of a function call starting at the `(` token at
-- index `paren_open`. Counts top-level commas; returns the close-paren
-- index too (or nil if unbalanced).
local function count_call_args(tokens, paren_open, sample_end)
  local depth, arg_count, has_content = 1, 0, false
  local k = paren_open + 1
  local end_idx = sample_end or #tokens
  while k <= end_idx and depth > 0 do
    local tk = tokens[k]
    if tk.type == "other" then
      if tk.text == "(" or tk.text == "[" then depth = depth + 1
      elseif tk.text == ")" or tk.text == "]" then depth = depth - 1
      elseif tk.text == "," and depth == 1 then arg_count = arg_count + 1 end
    end
    if depth >= 1 and tk.type ~= "ws" and tk.type ~= "com" then
      has_content = true
    end
    if depth == 0 then return arg_count + (has_content and 1 or 0), k end
    k = k + 1
  end
  return nil, nil  -- unbalanced
end

local function check_arg_count(tokens, has_imports, findings)
  if has_imports then return end

  -- Build set of user-defined function names so we don't false-fire on
  -- a JSFX that defined its own `function memset(...)` etc. (rare, but
  -- legal -- the user-defined function shadows the builtin).
  local user_defined = {}
  for i = 1, #tokens - 1 do
    local t = tokens[i]
    if (t.type == "id" or t.type == "kw") and t.text == "function" then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "id" then
        user_defined[tokens[j].text] = true
      end
    end
  end

  for i = 1, #tokens do
    local t = tokens[i]
    if t.type == "id" and FIXED_ARITY[t.text] and not user_defined[t.text] then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == "(" then
        -- Skip method-call form (preceded by `.`): `obj.memset(...)` is
        -- a different function on a struct, not the global builtin.
        local p = i - 1
        while p >= 1 and (tokens[p].type == "ws" or tokens[p].type == "com") do
          p = p - 1
        end
        local is_method = p >= 1 and tokens[p].type == "other"
                       and tokens[p].text == "."
        if not is_method then
          local got = count_call_args(tokens, j)
          local expected = FIXED_ARITY[t.text]
          if got and got ~= expected then
            add(findings, "fatal", "arg_count_mismatch", t.line,
              ("`%s(...)` requires %d argument(s); call site has %d. EEL2 will reject this with a `'%s' needs %d prms` compile error."):format(
                t.text, expected, got, t.text, expected))
          end
        end
      end
    end
  end
end

local function check_unknown_function(tokens, header_lines, has_imports, findings)
  if has_imports then return end

  -- Step 1: collect user-defined function names from `function NAME(...)`.
  local user_defined = {}
  for i = 1, #tokens - 1 do
    local t = tokens[i]
    if (t.type == "id" or t.type == "kw") and t.text == "function" then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "id" then
        user_defined[tokens[j].text] = true
      end
    end
  end

  -- Step 2: scan for `id ( ` patterns. Skip header lines (slider display
  -- names look like calls -- `Mix (%)`), method calls (preceded by `.`),
  -- slider variables, and `@`-prefixed section markers (those are kw-typed
  -- by the tokenizer and `skip_ws` after them will cross the newline and
  -- land on the first `(` of the section body, falsely flagging
  -- `@sample(...)` / `@block(...)` etc. as unknown function calls).
  local seen = {}
  for i = 1, #tokens do
    local t = tokens[i]
    if (t.type == "id" or t.type == "kw") and not seen[t.text]
       and not KNOWN_FUNCTIONS[t.text] and not user_defined[t.text]
       and not t.text:match("^slider%d+$")
       and not t.text:match("^@")
       and not header_lines[t.line] then
      local j = skip_ws(tokens, i + 1)
      if j and tokens[j].type == "other" and tokens[j].text == "(" then
        local p = i - 1
        while p >= 1 and (tokens[p].type == "ws" or tokens[p].type == "com") do
          p = p - 1
        end
        local is_method = p >= 1 and tokens[p].type == "other"
                       and tokens[p].text == "."
        if not is_method then
          seen[t.text] = true
          add(findings, "warn", "unknown_function", t.line,
              ("Function `%s(...)` is not a documented EEL2/JSFX built-in and is not defined in this file. Verify it exists in your REAPER version, or define the function explicitly with `function %s(...) ( ... );`.")
                :format(t.text, t.text))
        end
      end
    end
  end
end

function Code.prompt_requests_jsfx_term(user_text, term, allow_suffix)
  local raw_text = tostring(user_text or "")
  local wanted = tostring(term or ""):lower()
  if raw_text == "" or wanted == "" then return false end
  local request_words = {
    "need", "want", "add", "use", "include", "insert", "put", "create",
    "build", "apply", "introduce", "keep", "make", "let", "allow", "set",
  }
  -- Only verbs that unambiguously introduce a later term in this scope.
  -- Modifier/directive verbs such as `make`, `keep`, and `set` stay excluded.
  local term_introduction_words = {
    "add", "use", "include", "insert", "put", "create", "build", "apply",
    "introduce",
  }

  local cache = Code._jsfx_term_request_cache
  local text
  if type(cache) == "table" and cache.user_text == raw_text
      and type(cache.text) == "string"
      and type(cache.results) == "table" then
    text = cache.text
  else
    text = raw_text:lower()
      :gsub("’", "'")
      :gsub("%f[%a]%a+n't%s+only%f[%A]", "also")
      :gsub("%f[%a]%a+n't%s+just%f[%A]", "also")
      :gsub("%f[%a]dont%s+only%f[%A]", "also")
      :gsub("%f[%a]dont%s+just%f[%A]", "also")
      :gsub("%f[%a]not%s+only%f[%A]", "also")
      :gsub("%f[%a]not%s+just%f[%A]", "also")
      :gsub("%f[%a]under%s+no%s+circumstances%f[%A]%s*,?%s*", "never ")
      :gsub("%f[%a]in%s+no%s+circumstances%f[%A]%s*,?%s*", "never ")
      :gsub("%f[%a]no%-frills%f[%A]", "simple")
      :gsub("%f[%a]no%s+frills%f[%A]", "simple")
      :gsub("%f[%a]no%-nonsense%f[%A]", "simple")
      :gsub("%f[%a]no%s+nonsense%f[%A]", "simple")
      :gsub("%f[%a]no%-fuss%f[%A]", "simple")
      :gsub("%f[%a]no%s+fuss%f[%A]", "simple")

    -- Contrast words and comma-led imperative restarts end an exclusion span.
    -- This keeps "do not add a limiter, add a comb instead" positive for comb
    -- while preserving lists such as "no reverb, feedback, or comb".
    for _, boundary in ipairs({ "but", "however", "yet", "except" }) do
      text = text:gsub("%f[%a]" .. boundary .. "%f[%A]", ";")
    end
    for _, restart in ipairs(request_words) do
      text = text:gsub(",%s*" .. restart .. "%f[%A]", "; " .. restart)
    end
    for _, restart in ipairs({ "just", "only" }) do
      text = text:gsub(",%s*" .. restart .. "%f[%A]", "; " .. restart)
    end
    cache = {
      user_text = raw_text,
      text = text,
      results = {},
    }
    Code._jsfx_term_request_cache = cache
  end
  if text == "" then return false end
  local result_key = wanted .. "\0" .. tostring(not not allow_suffix)
  if cache.results[result_key] ~= nil then
    return cache.results[result_key]
  end

  local escaped = wanted:gsub("(%W)", "%%%1")
  local occurrence = "%f[%w]" .. escaped
    .. (allow_suffix and "" or "%f[%W]")
  local function segment_start(pos)
    local prefix = text:sub(1, math.max(0, pos - 1))
    return prefix:match(".*[%.!%?;\n]()") or 1
  end
  local function segment_end(pos)
    return (text:find("[%.!%?;\n]", pos) or (#text + 1)) - 1
  end
  local function has_word(src, word)
    return src:find("%f[%a]" .. word .. "%f[%A]") ~= nil
  end
  local function has_threshold_language(src)
    if src:find("%d") or src:find("%%", 1, true) then return true end
    for _, word in ipairs({
      "above", "below", "over", "under", "higher", "lower", "greater",
      "less", "more", "than", "exceed", "exceeds", "exceeding", "half",
      "percent", "maximum", "minimum", "max", "min", "enough",
    }) do
      if has_word(src, word) then return true end
    end
    return false
  end
  local negation_patterns = {
    "%f[%a]do%s+not%f[%A]",
    "%f[%a]don't%f[%A]",
    "%f[%a]dont%f[%A]",
    "%f[%a]should%s+not%f[%A]",
    "%f[%a]shouldn't%f[%A]",
    "%f[%a]shouldnt%f[%A]",
    "%f[%a]must%s+not%f[%A]",
    "%f[%a]mustn't%f[%A]",
    "%f[%a]mustnt%f[%A]",
    "%f[%a]does%s+not%f[%A]",
    "%f[%a]doesn't%f[%A]",
    "%f[%a]doesnt%f[%A]",
    "%f[%a]did%s+not%f[%A]",
    "%f[%a]didn't%f[%A]",
    "%f[%a]didnt%f[%A]",
    "%f[%a]will%s+not%f[%A]",
    "%f[%a]won't%f[%A]",
    "%f[%a]wont%f[%A]",
    "%f[%a]can%s+not%f[%A]",
    "%f[%a]can't%f[%A]",
    "%f[%a]cannot%f[%A]",
    "%f[%a]cant%f[%A]",
    "%f[%a]could%s+not%f[%A]",
    "%f[%a]couldn't%f[%A]",
    "%f[%a]couldnt%f[%A]",
    "%f[%a]would%s+not%f[%A]",
    "%f[%a]wouldn't%f[%A]",
    "%f[%a]wouldnt%f[%A]",
    "%f[%a]never%f[%A]",
  }
  local function latest_negation_end(src)
    local latest
    for _, pattern in ipairs(negation_patterns) do
      local pos = 1
      while true do
        local _, e = src:find(pattern, pos)
        if not e then break end
        if not latest or e > latest then latest = e end
        pos = e + 1
      end
    end
    local pos = 1
    while true do
      local _, e = src:find("%f[%a]not%f[%A]", pos)
      if not e then break end
      if not latest or e > latest then latest = e end
      pos = e + 1
    end
    return latest
  end
  local function count_words(src)
    local count = 0
    for _ in src:gmatch("%f[%a]%a+%f[%A]") do
      count = count + 1
    end
    return count
  end
  local function nearby_negation(src, max_words)
    local negation_end = latest_negation_end(src)
    return negation_end ~= nil
      and count_words(src:sub(negation_end + 1)) <= max_words
  end
  local function split_exclusion_action(prefix, tail)
    if not tail:find("^%s+out%f[%A]")
        and not tail:find("^%s+%a+%s+out%f[%A]") then
      return false, false
    end
    local closest_start, closest_end
    for _, pattern in ipairs({
      "%f[%a]keep%a*%f[%A]",
      "%f[%a]leav%a*%f[%A]",
      "%f[%a]tak%a*%f[%A]",
    }) do
      local pos = 1
      while true do
        local s, e = prefix:find(pattern, pos)
        if not s then break end
        if not closest_end or e > closest_end then
          closest_start, closest_end = s, e
        end
        pos = math.max(e + 1, pos + 1)
      end
    end
    if not closest_end
        or count_words(prefix:sub(closest_end + 1)) > 3 then
      return false, false
    end
    return true, nearby_negation(prefix:sub(1, closest_start - 1), 2)
  end
  local function post_term_exclusion(prefix, tail)
    local split, negated = split_exclusion_action(prefix, tail)
    if split then return not negated end

    if tail:find("^%s*%-free%f[%A]") then
      return not nearby_negation(prefix, 4)
    end
    if prefix:find("%f[%a]free%s+of%s*$") then
      return not nearby_negation(prefix, 4)
    end

    local candidates = { tail }
    local after_suffix = tail:match("^%s+%a+(.+)$")
    if after_suffix then candidates[#candidates + 1] = after_suffix end
    for _, candidate in ipairs(candidates) do
      for _, copula in ipairs({
        "is", "are", "was", "were",
      }) do
        for _, descriptor in ipairs({
          "needed", "necessary", "wanted", "required",
        }) do
          if candidate:find("^%s*" .. copula .. "%s+not%s+"
              .. descriptor .. "%f[%A]") then
            return true
          end
        end
        if candidate:find("^%s*" .. copula
            .. "%s+unnecessary%f[%A]") then
          return true
        end
      end
      for _, copula in ipairs({
        "isn't", "isnt", "aren't", "arent",
        "wasn't", "wasnt", "weren't", "werent",
      }) do
        for _, descriptor in ipairs({
          "needed", "necessary", "wanted", "required",
        }) do
          if candidate:find("^%s*" .. copula .. "%s+"
              .. descriptor .. "%f[%A]") then
            return true
          end
        end
      end
    end
    return false
  end
  local function has_preservation_action(src)
    local closest_end
    for _, pattern in ipairs({
      "%f[%a]remov%a*%f[%A]",
      "%f[%a]los%a*%f[%A]",
      "%f[%a]drop%a*%f[%A]",
      "%f[%a]touch%a*%f[%A]",
      "%f[%a]delet%a*%f[%A]",
      "%f[%a]kill%a*%f[%A]",
      "%f[%a]cut%a*%f[%A]",
      "%f[%a]strip%a*%f[%A]",
      "%f[%a]omit%a*%f[%A]",
      "%f[%a]exclud%a*%f[%A]",
      "%f[%a]skip%a*%f[%A]",
      "%f[%a]avoid%a*%f[%A]",
      "%f[%a]chang%a*%f[%A]",
      "%f[%a]alter%a*%f[%A]",
      "%f[%a]reduc%a*%f[%A]",
      "%f[%a]lower%a*%f[%A]",
      "%f[%a]mut%a*%f[%A]",
      "%f[%a]disabl%a*%f[%A]",
      "%f[%a]bypass%a*%f[%A]",
      "%f[%a]keep%a*%s+out%f[%A]",
      "%f[%a]leav%a*%s+out%f[%A]",
      "%f[%a]tak%a*%s+out%f[%A]",
      "%f[%a]stop%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stops%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stopped%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stopping%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]get%s+rid%s+of%f[%A]",
      "%f[%a]got%s+rid%s+of%f[%A]",
      "%f[%a]getting%s+rid%s+of%f[%A]",
      "%f[%a]ditch%a*%f[%A]",
    }) do
      local pos = 1
      while true do
        local s, e = src:find(pattern, pos)
        if not s then break end
        if not closest_end or e > closest_end then closest_end = e end
        pos = math.max(e + 1, pos + 1)
      end
    end
    if not closest_end then return false end
    local trailing = src:sub(closest_end + 1)
    for _, word in ipairs(term_introduction_words) do
      if has_word(trailing, word) then return false end
    end
    return true
  end
  local function has_no_need(src)
    return src:find("%f[%a]no%s+need%f[%A]") ~= nil
      or src:find("%f[%a]no%s+%a+%s+need%f[%A]") ~= nil
  end
  local function has_request_after_connector(src)
    for _, connector in ipairs({ "and", "then", "so", "plus" }) do
      local pos = 1
      while true do
        local _, e = src:find(
          "%f[%a]" .. connector .. "%f[%A]", pos)
        if not e then break end
        local trailing = src:sub(e + 1)
        for _, word in ipairs(request_words) do
          for _, lead in ipairs({ "", "please%s+", "i%s+", "we%s+",
              "you%s+" }) do
            if trailing:find(
                "^%s*" .. lead .. word .. "%f[%A]") then return true end
          end
        end
        pos = e + 1
      end
    end
    return false
  end
  local function tail_starts_comparative(tail)
    for _, word in ipairs({
      "above", "below", "over", "under", "higher", "lower", "greater",
      "less", "more", "exceed", "exceeds", "exceeding",
    }) do
      local _, comparator_end = tail:find("^%s*" .. word .. "%f[%A]")
      if comparator_end then
        return has_threshold_language(tail:sub(comparator_end + 1))
      end
    end
    return false
  end
  local function clause_has_negation(prefix, tail)
    if tail_starts_comparative(tail) then return false end
    local closest_end
    for _, pattern in ipairs(negation_patterns) do
      local pos = 1
      while true do
        local s, e = prefix:find(pattern, pos)
        if not s then break end
        if not closest_end or e > closest_end then closest_end = e end
        pos = math.max(e + 1, pos + 1)
      end
    end
    if not closest_end then return false end
    local after = prefix:sub(closest_end + 1)
    local split = split_exclusion_action(prefix, tail)
    -- Negating an exclusion keeps the named term positive:
    -- "do not keep the comb out" and "do not make it comb-free".
    if split or tail:find("^%s*%-free%f[%A]")
        or prefix:find("%f[%a]free%s+of%s*$") then
      return false
    end
    -- A negated removal/preservation action keeps the named term positive:
    -- "do not remove the shimmer" means preserve shimmer, not exclude it.
    if has_preservation_action(after) then return false end
    -- "Do not make the delay too long" constrains a requested term; the
    -- trailing `too` alone must not defeat a direct form such as "no reverb
    -- too."
    if tail:find("^%s*too%s+%a") then return false end
    -- "Do not use more than 60% feedback" still requests feedback; only
    -- its allowed amount is constrained.
    return not has_threshold_language(after)
  end
  local function direct_negation(prefix, tail)
    -- A comparative threshold describes a requested term; it is not an
    -- exclusion ("without feedback exceeding 0.6", "no feedback above 0.6").
    if tail_starts_comparative(tail) then return false end

    local closest_start, closest_end
    for _, pattern in ipairs({
      "%f[%a]no%f[%A]",
      "%f[%a]not%s+an?%f[%A]",
      "%f[%a]not%s+the%f[%A]",
      "%f[%a]is%s+not%f[%A]",
      "%f[%a]are%s+not%f[%A]",
      "%f[%a]was%s+not%f[%A]",
      "%f[%a]were%s+not%f[%A]",
      "%f[%a]isn't%f[%A]",
      "%f[%a]aren't%f[%A]",
      "%f[%a]wasn't%f[%A]",
      "%f[%a]weren't%f[%A]",
      "%f[%a]hasn't%f[%A]",
      "%f[%a]haven't%f[%A]",
      "%f[%a]hadn't%f[%A]",
      "%f[%a]isnt%f[%A]",
      "%f[%a]arent%f[%A]",
      "%f[%a]wasnt%f[%A]",
      "%f[%a]werent%f[%A]",
      "%f[%a]hasnt%f[%A]",
      "%f[%a]havent%f[%A]",
      "%f[%a]hadnt%f[%A]",
      "%f[%a]without%f[%A]",
      "%f[%a]avoid%a*%f[%A]",
      "%f[%a]omit%a*%f[%A]",
      "%f[%a]exclud%a*%f[%A]",
      "%f[%a]skip%a*%f[%A]",
      "%f[%a]keep%a*%s+out%f[%A]",
      "%f[%a]leav%a*%s+out%f[%A]",
      "%f[%a]tak%a*%s+out%f[%A]",
      "%f[%a]stop%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stops%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stopped%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]stopping%f[%A]%s+us[ei]%a*%f[%A]",
      "%f[%a]get%s+rid%s+of%f[%A]",
      "%f[%a]got%s+rid%s+of%f[%A]",
      "%f[%a]getting%s+rid%s+of%f[%A]",
      "%f[%a]ditch%a*%f[%A]",
      "%f[%a]lose%f[%A]",
      "%f[%a]loses%f[%A]",
      "%f[%a]losing%f[%A]",
      "%f[%a]lost%f[%A]",
      "%f[%a]sans%f[%A]",
      "%f[%a]zero%f[%A]",
      "%f[%a]minus%f[%A]",
      "%f[%a]instead%s+of%f[%A]",
      "%f[%a]rather%s+than%f[%A]",
    }) do
      local pos = 1
      while true do
        local s, e = prefix:find(pattern, pos)
        if not s then break end
        if not closest_start or s > closest_start then
          closest_start, closest_end = s, e
        end
        pos = e + 1
      end
    end
    if not closest_end then return false end
    local before = prefix:sub(1, closest_start - 1)
    for _, pattern in ipairs(negation_patterns) do
      if before:find(pattern .. "%s*$") then return false end
    end
    if before:find("%f[%a]not%f[%A]%s*$")
        or before:find("%f[%a]without%f[%A]%s*$")
        or before:find("%f[%a]avoid%a*%f[%A]%s*$")
        or before:find("%f[%a]no%f[%A]%s*$") then
      return false
    end
    local between = prefix:sub(closest_end + 1)
    local marker = prefix:sub(closest_start, closest_end)
    if marker == "no" and between:find("^%s*more%s*$") then
      return true
    end
    if marker == "zero" and between:find("%a") then
      return false
    end
    local contrastive_marker = marker:find("not", 1, true) ~= nil
      or marker:find("n't", 1, true) ~= nil
    for _, contraction in ipairs({
      "isnt", "arent", "wasnt", "werent", "hasnt", "havent", "hadnt",
    }) do
      if marker == contraction then
        contrastive_marker = true
        break
      end
    end
    if contrastive_marker and between:find(",", 1, true) then
      local continuation = between:match("[^,]*$") or ""
      local introduces_term = false
      for _, word in ipairs({
        "with", "using", "plus", "via", "featuring", "including", "adding",
        "creating",
      }) do
        if has_word(continuation, word) then
          introduces_term = true
          break
        end
      end
      if not introduces_term then
        for _, word in ipairs(request_words) do
          if has_word(continuation, word) then
            introduces_term = true
            break
          end
        end
      end
      if introduces_term then
        for _, word in ipairs(request_words) do
          if has_word(before, word) then
            return false
          end
        end
      end
    end
    if has_threshold_language(between) then return false end
    if has_preservation_action(between) then return false end
    if has_no_need(prefix) then
      return not has_request_after_connector(between)
    end
    for _, word in ipairs(request_words) do
      if has_word(between, word) then return false end
    end
    return true
  end

  local pos = 1
  while true do
    local s, e = text:find(occurrence, pos)
    if not s then break end
    local first = segment_start(s)
    local last = segment_end(e + 1)
    local prefix = text:sub(first, s - 1)
    local tail = text:sub(e + 1, last)
    if not clause_has_negation(prefix, tail)
       and not direct_negation(prefix, tail)
       and not post_term_exclusion(prefix, tail) then
      cache.results[result_key] = true
      return true
    end
    pos = math.max(e + 1, pos + 1)
  end
  cache.results[result_key] = false
  return false
end

local function check_named_jsfx_terms(src, user_text, findings)
  local prompt = tostring(user_text or "")
  if prompt == "" then return end
  local body = tostring(src or ""):lower()
  local function has_named_term(term)
    -- Accept standalone comments (`allpass`) and identifier stems
    -- (`allpassL1`, `buffer_l0`) while avoiding matches inside longer
    -- unrelated words (`inside` should not satisfy `side`).
    return body:find("%f[%w]" .. term) ~= nil
  end
  local fatal_terms = {
    "allpass", "buffer", "grain", "freeze", "jitter", "comb",
  }
  local warn_terms = {
    "feedback", "width", "mid", "side",
  }
  local function check_term(term, severity)
    if Code.prompt_requests_jsfx_term(prompt, term, false)
        and not has_named_term(term) then
      add(findings, severity, "missing_named_dsp_term", 1,
        "The user explicitly requested `" .. term
        .. "` but the JSFX omitted that literal concept name. Keep requested DSP concepts visible as identifier stems or short comments.")
    end
  end
  for _, term in ipairs(fatal_terms) do check_term(term, "fatal") end
  for _, term in ipairs(warn_terms) do check_term(term, "warn") end
end

local function check_pitch_write_head_offset(src, user_text, findings)
  local prompt = tostring(user_text or ""):lower()
  local names_contract = prompt:find("analysis/write%-head")
    or prompt:find("analysis/write head", 1, true)
    or (prompt:find("analysis", 1, true)
      and prompt:find("write", 1, true)
      and prompt:find("head", 1, true)
      and (prompt:find("pitch", 1, true)
        or prompt:find("shimmer", 1, true)))
  if not names_contract then return end

  local code = ""
  for raw_line in (tostring(src or "") .. "\n"):gmatch("([^\n]*)\n") do
    code = code .. raw_line:gsub("//.*$", ""):lower() .. "\n"
  end
  local has_relation = false
  for line in code:gmatch("[^\n]+") do
    local write_id, offset_id = line:match(
      "([%a_][%w_]*)%s*%+%s*floor%s*%(%s*([%a_][%w_]*)")
    if write_id and offset_id then
      local writeish = write_id:find("head", 1, true)
        or write_id:find("w", 1, true)
        or write_id:match("_h[%w_]*$")
      local offsetish = offset_id:find("offset", 1, true)
        or offset_id:find("off", 1, true)
        or offset_id:match("^ao")
      if writeish and offsetish then
        has_relation = true
        break
      end
    end
  end
  if not has_relation then
    add(findings, "fatal", "pitch_missing_write_head_offset", 1,
      "The request explicitly requires an analysis/write-head offset, but no grain read index adds the live write head to its analysis offset. With `analysis_step = pitch_ratio - 1`, compute each channel's read index as write head PLUS analysis offset; do not use a minus or absolute-phase-only read.")
  end
end

local function check_shimmer_pitch_topology(src, user_text, findings)
  local prompt = tostring(user_text or ""):lower()
  if not prompt:find("shimmer", 1, true) then return end

  local code = ""
  for raw_line in (tostring(src or "") .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw_line:gsub("//.*$", ""):lower()
    code = code .. line .. "\n"
    local buffer, dry = line:match(
      "^%s*([%a_][%w_]*)%s*%[[^%]]+%]%s*=%s*(spl[01])%s*;")
    if buffer and (buffer:find("pit", 1, true)
        or buffer:find("grain", 1, true)) then
      add(findings, "fatal", "shimmer_pitch_from_dry", 1,
        "The shimmer pitch buffer is written directly from `" .. dry
        .. "`. Feed it from the damped/DC-blocked pitched-comb read so the pitch shifter is inside the feedback loop, not from the dry input.")
      break
    end
  end

  local assigned = {}
  for name in code:gmatch("([%a_][%w_]*)%s*=") do
    if name:find("pitch_out", 1, true) or name:find("pitched", 1, true) then
      assigned[name] = true
    end
  end
  for name in pairs(assigned) do
    local count = 0
    for token in code:gmatch("[%a_][%w_]*") do
      if token == name then count = count + 1 end
    end
    if count < 2 then
      add(findings, "fatal", "pitch_output_unused", 1,
        "`" .. name .. "` is computed but never consumed. Use the pitched result in the feedback expression written back to the pitched comb.")
    end
  end

  for buffer, head in code:gmatch(
      "([%a_][%w_]*)%s*%[%s*([%a_][%w_]*)%s*%]%s*=") do
    if buffer:find("pit", 1, true) or buffer:find("grain", 1, true) then
      local shared_feedback_head = false
      for other_buffer, other_head in code:gmatch(
          "([%a_][%w_]*)%s*%[%s*([%a_][%w_]*)%s*%]%s*=") do
        if other_head == head and other_buffer ~= buffer
            and (other_buffer:find("comb", 1, true)
              or other_buffer:find("delay", 1, true)) then
          shared_feedback_head = true
          break
        end
      end
      local update_mask = code:match(
        "%f[%w_]" .. head .. "%f[^%w_]%s*=%s*[^\n]-&%s*([%a_][%w_]*)")
      if shared_feedback_head or (update_mask
          and (update_mask:find("comb", 1, true)
            or update_mask:find("delay", 1, true))) then
        add(findings, "fatal", "pitch_write_wrong_ring", 1,
          "The pitch/grain buffer `" .. buffer .. "` is indexed by `" .. head
          .. "`, but that raw head is also used by the feedback-delay ring or "
          .. "advances with its mask. Use a separate pitch head advanced with "
          .. "the grain/pitch mask, or explicitly mask the pitch-buffer index "
          .. "with its own ring mask.")
        break
      end
    end
  end
end

function Code.validate_jsfx(src, user_text)
  if not src or src == "" then return {} end
  local findings = {}
  local tokens = Code.tokenize_jsfx(src)
  local sliders = parse_sliders(src)
  local header_lines = build_header_lines(src)
  local has_imports = src:match("\n%s*import%s+%S") ~= nil
                   or src:match("^%s*import%s+%S") ~= nil
  check_desc(tokens, findings)
  check_reaper_api(tokens, findings)
  check_generated_safety_conflicts(src, tokens, sliders, findings)
  check_banned_syntax(tokens, header_lines, findings)
  check_section_markers(src, tokens, findings)
  check_feedback_clamp(tokens, sliders, findings)
  check_memory_init(tokens, header_lines, has_imports, findings)
  check_buffer_overlap(tokens, findings)
  check_parallel_comb_doubled(tokens, header_lines, has_imports, findings)
  check_hard_clip(tokens, user_text or "", findings)
  check_arg_count(tokens, has_imports, findings)
  check_unknown_function(tokens, header_lines, has_imports, findings)
  check_pitch_write_head_offset(src, user_text or "", findings)
  check_shimmer_pitch_topology(src, user_text or "", findings)
  check_named_jsfx_terms(src, user_text or "", findings)
  return findings
end

-- True if any finding has fatal severity (would gate auto-run).
function Code.jsfx_findings_have_gate(findings)
  if not findings then return false end
  for _, f in ipairs(findings) do
    if f.severity == "fatal" then return true end
  end
  return false
end

end  -- close JSFX validator scope
