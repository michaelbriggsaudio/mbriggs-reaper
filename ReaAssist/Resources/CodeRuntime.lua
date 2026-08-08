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
-- Small structured lane for pure track, folder, and routing work.
do
local OPS = {
  ["track.create"] = true,
  ["track.ensure"] = true,
  ["track.resolve"] = true,
  ["track.set"] = true,
  ["track.folder"] = true,
  ["send.create"] = true,
}
local OP_ORDER = {
  "track.create", "track.ensure", "track.resolve",
  "track.set", "track.folder", "send.create",
}
local FIELDS = {
  ["track.create"] = {op=true,id=true,name=true,position=true,select=true},
  ["track.ensure"] = {op=true,id=true,name=true,position=true,select=true},
  ["track.resolve"] = {
    op=true,id=true,name=true,selected=true,selected_index=true,index=true,
  },
  ["track.set"] = {
    op=true,track=true,name=true,volume_db=true,pan_pct=true,
    mute=true,solo=true,master_send=true,
  },
  ["track.folder"] = {op=true,parent=true,children=true},
  ["send.create"] = {
    op=true,id=true,["from"]=true,to=true,volume_db=true,
    pan=true,mode=true,muted=true,
  },
}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
  end
  return count == #value
end

local function err(code, path, message)
  return {
    code = tostring(code or "invalid_plan"),
    path = tostring(path or "$"),
    message = tostring(message or "Invalid structured edit."),
  }
end

local function add_error(errors, code, path, message)
  errors[#errors + 1] = err(code, path, message)
end

local function first_error(errors)
  return type(errors) == "table" and errors[1]
    and tostring(errors[1].code or "invalid_plan") or nil
end

local function count_ops(plan)
  local counts = {}
  for _, op in ipairs(OP_ORDER) do counts[op] = 0 end
  for _, action in ipairs(type(plan) == "table" and plan.actions or {}) do
    if counts[action.op] ~= nil then counts[action.op] = counts[action.op] + 1 end
  end
  return counts
end

local function fenced_blocks(text)
  local fence = string.char(96, 96, 96)
  return tostring(text or ""):gmatch(
    fence .. "([^\n]*)\n(.-)\n%s*" .. fence)
end

local function has_plugin_signal(user_text)
  local lower = tostring(user_text or ""):lower()
  if type(CTX) == "table"
      and type(CTX.prompt_has_named_plugin_pack_signal) == "function"
      and CTX.prompt_has_named_plugin_pack_signal(user_text) then
    return true
  end
  -- "Reverb Bus" is ordinarily a track name, so routing work that mentions one
  -- keeps its structured path. A return is different: an effect return is the
  -- track the effect lives on, so "set up a reverb return" is a creation
  -- request where the plug-in is the deliverable. Drop the effect word for a
  -- return only when a determiner marks it as one that already exists.
  lower = lower
    :gsub("%f[%w]reverb%s+bus%f[%W]", "bus")
    :gsub("%f[%w]delay%s+bus%f[%W]", "bus")
  for _, det in ipairs({ "my", "the", "our", "that", "existing" }) do
    lower = lower
      :gsub("%f[%w]" .. det .. "%s+reverb%s+return%f[%W]", det .. " return")
      :gsub("%f[%w]" .. det .. "%s+delay%s+return%f[%W]", det .. " return")
  end
  if type(CTX) == "table"
      and type(CTX.prompt_has_plugin_pack_signal) == "function"
      and CTX.prompt_has_plugin_pack_signal(lower) then
    return true
  end
  local words = " " .. lower
    :gsub("[^%w]+", " "):gsub("%s+", " ") .. " "
  for _, term in ipairs({
      "plugin", "plugins", "plug in", "plug ins", "fx", "effect", "effects",
      "processor", "processors", "processing", "chain", "channel strip",
      "wet", "eq", "equalizer", "compressor", "limiter",
      "compression", "compressing", "equalization", "limiting", "gating",
      "de essing", "deessing",
      "gate", "reverb", "delay", "deesser", "saturation", "distortion",
      "chorus", "phaser", "pitch correction", "amp sim", "vst", "vst3",
      "clap", "au", "aax", "parameter", "parameters", "preset", "presets",
    }) do
    if words:find(" " .. term .. " ", 1, true) then return true end
  end
  return false
end

local function exact_nonplugin_scope(user_text)
  local text = tostring(user_text or "")
  local lower = text:lower()
  if lower == "" or has_plugin_signal(text) then return false end
  if type(Code.prompt_is_question_or_readonly) == "function"
      and Code.prompt_is_question_or_readonly(text) then return false end
  if type(Code.prompt_requests_reusable_action_script) == "function"
      and Code.prompt_requests_reusable_action_script(text) then return false end
  if lower:find("reaper lua", 1, true)
      or lower:find("lua script", 1, true)
      or lower:find("reascript", 1, true) then return false end
  local words = " " .. lower:gsub("[^%w]+", " "):gsub("%s+", " ") .. " "
  for _, term in ipairs({
      " item ", " items ", " take ", " takes ", " media ", " midi ",
      " marker ", " markers ", " region ", " regions ", " envelope ",
      " automation ", " render ", " export ", " record ", " recording ",
      " play ", " playback ", " transport ", " tempo ", " theme ", " color ",
      " colour ", " toolbar ", " project tab ", " open project ",
      " close project ",
    }) do
    if words:find(term, 1, true) then return false end
  end
  local action, target = false, false
  for _, term in ipairs({
      " create ", " add ", " make ", " insert ", " ensure ", " rename ",
      " set ", " mute ", " unmute ", " solo ", " unsolo ", " route ",
      " send ", " folder ",
    }) do
    if words:find(term, 1, true) then action = true break end
  end
  for _, term in ipairs({
      " track ", " tracks ", " bus ", " buses ", " folder ", " send ",
      " routing ",
    }) do
    if words:find(term, 1, true) then target = true break end
  end
  return action and target
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
    { "vozes", "vocals" }, { "voz", "vocal" },
    { "vocais", "vocals" },
    { "sincronizacao", "timing" }, { "sincronizar", "align" },
    { "alinhamento", "timing" }, { "alinhar", "align" },
    { "afinacao", "pitch correction" }, { "afinar", "pitch correction" },
    { "entonacao", "pitch correction" },
    { "niveis", "levels" }, { "nivel", "level" },
    { "ganhos", "gains" }, { "ganho", "gain" },
    { "integrada", "integrated" }, { "integrado", "integrated" },
    { "pico", "peak" }, { "picos", "peaks" },
    { "corrija", "adjust" }, { "corrigir", "adjust" },
    { "reduza", "lower" }, { "reduzir", "lower" },
    { "diminua", "lower" }, { "diminuir", "lower" },
    { "aumente", "raise" }, { "aumentar", "raise" },
    { "ideal", "ideal" }, { "adequado", "ideal" },
    { "adecuado", "ideal" },
  }) do
    text = text:gsub("%f[%w]" .. pair[1] .. "%f[%W]", pair[2])
  end
  -- Localized follow-ups commonly use conjugations that an exact word table
  -- cannot enumerate safely. Keep this stem pass limited to action and effect
  -- words, then require the normal action/object predicates downstream.
  for _, pair in ipairs({
    { "configur[%a]*", "configure" },
    { "ajust[%a]*", "adjust" },
    { "modific[%a]*", "modify" },
    { "cambi[%a]*", "change" },
    { "aplic[%a]*", "apply" },
    { "agreg[%a]*", "add" },
    { "anad[%a]*", "add" },
    { "insert[%a]*", "insert" },
    { "complement[%a]*", "plugin" },
    { "efect[%a]*", "effect" },
    { "ecualiz[%a]*", "eq" },
    { "compres[%a]*", "compressor" },
    { "reverber[%a]*", "reverb" },
    { "limit[%a]*", "limiter" },
    { "sincroni[%a]*", "align" },
    { "alinh[%a]*", "align" },
    { "afin[%a]*", "pitch correction" },
    { "entonaci[%a]*", "pitch correction" },
    { "entonac[%a]*", "pitch correction" },
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

function Code.typed_actions_public_force_off()
  return type(reaper) == "table"
    and type(reaper.GetExtState) == "function"
    and type(CFG) == "table"
    and reaper.GetExtState(CFG.EXT_NS, "typed_actions_force_off") == "1"
end

function Code.typed_actions_executor_enabled()
  return not Code.typed_actions_public_force_off()
end

function Code.typed_actions_executor_disabled_message()
  return "Structured track edits are temporarily unavailable."
end

function Code._typed_action_selected_indexes_from_user_text()
  return {}, false
end

function Code.typed_action_user_requests_folder(user_text)
  return tostring(user_text or ""):lower()
    :find("%f[%w]folder%f[%W]") ~= nil
end

local CONTRACT = [[
STRUCTURED TRACK EDIT CONTRACT:
The complete request contains only track, folder, or routing work.
Return one fenced reaassist-actions block containing
{"version":1,"actions":[...]}.
Supported operations are track.create, track.ensure, track.resolve, track.set,
track.folder, and send.create. Use track.create for new tracks, track.ensure
only for reuse-if-present wording, and track.resolve for existing targets.
References must use ids from earlier track actions. Use dependency order.
Use `op` for every operation. Every track.create, track.ensure, and
track.resolve declares an `id` that later actions reference.
track.set names its target with `track`, not `id`, and changes only name,
volume_db, pan_pct, mute, solo, or master_send.
Folder nesting uses track.folder with `parent` and `children`. There is no
folder field on track.set.
A send uses `from` and `to`, with optional `volume_db`, for example
{"op":"send.create","from":"vocal","to":"reverb","volume_db":-6}.
Worked example for an existing track that becomes a folder:
{"version":1,"actions":[
{"op":"track.resolve","id":"drums","name":"Drum Bus"},
{"op":"track.create","id":"kick","name":"Kick"},
{"op":"track.create","id":"snare","name":"Snare"},
{"op":"track.folder","parent":"drums","children":["kick","snare"]}]}
Do not output Lua, prose, plug-in work, parameter work, or another code fence.
]]

function Code.typed_actions_prompt_contract(user_text, opts)
  opts = type(opts) == "table" and opts or {}
  if not opts.force_enabled and not Code.typed_actions_executor_enabled() then
    return nil, "executor_disabled"
  end
  if not exact_nonplugin_scope(user_text) then
    return nil, has_plugin_signal(user_text)
      and "plugin_work_requires_lua" or "uncertain_or_unsupported_scope"
  end
  return CONTRACT, "eligible"
end

function Code.typed_actions_openai_response_format_field()
  return ""
end

function Code.extract_typed_actions(text)
  local blocks = {}
  for label, body in fenced_blocks(text) do
    if trim(label):lower() == "reaassist-actions" then
      blocks[#blocks + 1] = body
    end
  end
  if #blocks == 1 then return blocks[1] end
  if #blocks > 1 then
    return nil, {err("multiple_action_blocks", "$",
      "Only one structured edit block is allowed.")}
  end
  return nil, {}
end

function Code.parse_typed_actions_block(raw)
  local source = trim(raw)
  if source:sub(1, 1) ~= "{" or source:sub(-1) ~= "}" then
    return nil, {err("invalid_json_shape", "$",
      "The structured edit must be one JSON object.")}
  end
  local plan, decode_error = JSON.decode(source)
  if type(plan) ~= "table" then
    return nil, {err("invalid_json", "$",
      tostring(decode_error or "Invalid JSON."))}
  end
  if type(plan["reaassist-actions"]) == "table" then
    plan = plan["reaassist-actions"]
  end
  return plan
end

function Code.validate_typed_actions_plan(plan)
  local errors, ids = {}, {}
  if type(plan) ~= "table" then
    return false, {err("invalid_top_level", "$", "Plan must be an object.")}
  end
  if tonumber(plan.version) ~= 1 then
    add_error(errors, "invalid_version", "$.version", "Version must be 1.")
  end
  if not array(plan.actions) or #plan.actions < 1 then
    add_error(errors, "invalid_actions", "$.actions",
      "Actions must be a non-empty array.")
    return false, errors
  end
  for index, action in ipairs(plan.actions) do
    local path = "$.actions[" .. tostring(index) .. "]"
    local op = type(action) == "table" and tostring(action.op or "") or ""
    if not OPS[op] then
      add_error(errors, "unsupported_op", path .. ".op",
        "Unsupported track-lane operation.")
    else
      for key in pairs(action) do
        if not FIELDS[op][key] then
          add_error(errors, "unknown_field", path .. "." .. tostring(key),
            "Unsupported field for " .. op .. ".")
        end
      end
      if op == "track.create" or op == "track.ensure"
          or op == "track.resolve" then
        if not nonempty(action.id) then
          add_error(errors, "missing_id", path .. ".id", "Track id is required.")
        elseif ids[action.id] then
          add_error(errors, "duplicate_id", path .. ".id", "Ids must be unique.")
        else
          ids[action.id] = true
        end
        if op == "track.ensure" and not nonempty(action.name) then
          add_error(errors, "missing_name", path .. ".name",
            "track.ensure needs an exact name.")
        elseif op == "track.resolve" then
          local selectors = (nonempty(action.name) and 1 or 0)
            + (action.selected == true and 1 or 0)
            + (tonumber(action.selected_index) and 1 or 0)
            + (tonumber(action.index) and 1 or 0)
          if selectors ~= 1 then
            add_error(errors, "invalid_selector", path,
              "track.resolve needs exactly one selector.")
          end
        end
      elseif op == "track.set" then
        if not ids[action.track] then
          add_error(errors, "unknown_track_ref", path .. ".track",
            "track.set must reference an earlier track action.")
        end
        if action.name == nil and action.volume_db == nil
            and action.pan_pct == nil and action.mute == nil
            and action.solo == nil and action.master_send == nil then
          add_error(errors, "empty_track_set", path,
            "track.set needs at least one property.")
        end
      elseif op == "track.folder" then
        if not ids[action.parent] then
          add_error(errors, "unknown_track_ref", path .. ".parent",
            "Folder parent must reference an earlier track action.")
        end
        if not array(action.children) or #action.children < 1 then
          add_error(errors, "invalid_children", path .. ".children",
            "Folder children must be a non-empty array.")
        else
          for child_index, child in ipairs(action.children) do
            if not ids[child] then
              add_error(errors, "unknown_track_ref",
                path .. ".children[" .. tostring(child_index) .. "]",
                "Folder child must reference an earlier track action.")
            end
          end
        end
      elseif op == "send.create"
          and (not ids[action["from"]] or not ids[action.to]) then
        add_error(errors, "unknown_track_ref", path,
          "Send endpoints must reference earlier track actions.")
      end
    end
  end
  return #errors == 0, errors
end

function Code.repair_typed_actions_plan(plan)
  if type(plan) ~= "table" or type(plan.actions) ~= "table" then return plan end
  for _, action in ipairs(plan.actions) do
    if type(action) == "table" then
      if action.op == nil and type(action.action) == "string" then
        action.op = action.action
      end
      action.action = nil
      if action.op == "send.create" then
        if action["from"] == nil and type(action.source) == "string" then
          action["from"] = action.source
        end
        if action.to == nil and type(action.destination) == "string" then
          action.to = action.destination
        end
        action.source = nil
        action.destination = nil
      end
    end
  end
  return plan
end

function Code.typed_actions_plan_from_text(text, opts)
  opts = type(opts) == "table" and opts or {}
  local raw, errors
  if opts.allow_raw_json and trim(text):sub(1, 1) == "{" then
    raw = trim(text)
  else
    raw, errors = Code.extract_typed_actions(text)
  end
  if not raw then return nil, errors end
  local plan, parse_errors = Code.parse_typed_actions_block(raw)
  if not plan then return nil, parse_errors end
  plan = Code.repair_typed_actions_plan(plan)
  local valid, validation_errors = Code.validate_typed_actions_plan(plan)
  if not valid then return nil, validation_errors end
  return plan
end

function Code.validate_typed_actions_semantics(plan, opts)
  opts = type(opts) == "table" and opts or {}
  if has_plugin_signal(opts.user_text) then
    return false, {err("plugin_work_requires_lua", "$",
      "Plug-in work must use ordinary Lua as one complete request.")}
  end
  return Code.validate_typed_actions_plan(plan)
end

function Code.format_typed_action_semantic_errors(errors, limit)
  local parts = {}
  for index, item in ipairs(type(errors) == "table" and errors or {}) do
    if index > (tonumber(limit) or 4) then break end
    parts[#parts + 1] = tostring(item.path or "$") .. ": "
      .. tostring(item.message or item.code or "invalid plan")
  end
  return table.concat(parts, "; ")
end

function Code.typed_action_semantic_detail_missing_action_family()
  return false
end

function Code.typed_action_semantic_detail_allows_lua_fallback()
  return true
end

function Code.typed_action_semantic_retry_from_scratch()
  return true
end

function Code._typed_action_schema_retry_detail(text, opts)
  local _, errors = Code.typed_actions_plan_from_text(text, opts)
  return Code.format_typed_action_semantic_errors(errors, 4)
end

function Code.find_typed_actions_wrong_fence(text)
  for label, body in fenced_blocks(text) do
    local clean = trim(label):lower()
    if clean == "json" or clean == "" then
      local plan = Code.parse_typed_actions_block(body)
      if plan and Code.validate_typed_actions_plan(plan) then
        return {label=clean ~= "" and clean or "(unlabelled)", raw=body}
      end
    end
  end
  return nil
end

local PROFILE = {key="track_only", semantic_max_retries=1}
function Code.typed_actions_model_profile() return PROFILE end
function Code.typed_actions_model_profile_by_key() return PROFILE end

function Code.typed_actions_artifact_text(text, allow_raw_json)
  if allow_raw_json and trim(text):sub(1, 1) == "{" then return trim(text) end
  local raw = Code.extract_typed_actions(text)
  return raw or ""
end

function Code.inspect_typed_actions(text, opts)
  opts = type(opts) == "table" and opts or {}
  local metrics = {
    present=false, valid=false, executed=false, fallback_to_lua=false,
    raw_json=false, retry_count=0, error=nil, op_counts=count_ops(nil),
  }
  local artifact = Code.typed_actions_artifact_text(text, opts.allow_raw_json)
  if type(artifact) ~= "string" or artifact == "" then return metrics end
  metrics.present = true
  metrics.raw_json = opts.allow_raw_json == true and trim(text):sub(1,1) == "{"
  local plan, errors = Code.typed_actions_plan_from_text(text, opts)
  if not plan then
    metrics.error = first_error(errors) or "invalid_plan"
    return metrics
  end
  metrics.valid, metrics.op_counts = true, count_ops(plan)
  return metrics
end

function Code.typed_actions_action_count(metrics, plan_text)
  local total, counts = 0, type(metrics) == "table" and metrics.op_counts or nil
  if type(counts) == "table" then
    for _, count in pairs(counts) do total = total + (tonumber(count) or 0) end
    return total
  end
  local plan = Code.typed_actions_plan_from_text(plan_text or "",
    {allow_raw_json=true})
  return plan and #plan.actions or 0
end

function Code.typed_actions_op_counts_text(counts)
  local parts = {}
  for _, op in ipairs(OP_ORDER) do
    local count = type(counts) == "table" and tonumber(counts[op]) or 0
    if count and count > 0 then
      parts[#parts + 1] = op .. "=" .. tostring(count)
    end
  end
  return table.concat(parts, ", ")
end

function Code.typed_actions_kind_label()
  return "Track and routing edit"
end

function Code.typed_actions_display_text(plan_text, action_results)
  local plan = Code.typed_actions_plan_from_text(plan_text or "",
    {allow_raw_json=true})
  if not plan then return "Structured track edit" end
  local labels = {}
  for _, action in ipairs(plan.actions) do labels[#labels + 1] = action.op end
  return table.concat(labels, ", ")
    .. (type(action_results) == "table" and #action_results > 0
      and " completed" or "")
end

function Code.typed_actions_user_failure_message(exec_result)
  local result = type(exec_result) == "table" and exec_result or {}
  local detail = tostring(result.message or result.code
    or "The edit did not complete.")
  if type(result.action_results) == "table" and #result.action_results > 0 then
    return "The track or routing edit stopped after making part of the change. "
      .. "Use REAPER Undo, then retry the request. Details: " .. detail
  end
  return "The track or routing edit was not applied. Check the named or selected "
    .. "track, then retry the request. Details: " .. detail
end

local function find_named_track(name)
  local matches = {}
  for index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, index)
    local _, track_name = reaper.GetTrackName(track, "")
    if tostring(track_name or "") == tostring(name or "") then
      matches[#matches + 1] = track
    end
  end
  if #matches == 1 then return matches[1] end
  return nil, #matches > 1 and "ambiguous_track" or "missing_track"
end

local function resolve_track(action)
  if nonempty(action.name) then return find_named_track(action.name) end
  if action.selected == true then
    if reaper.CountSelectedTracks(0) ~= 1 then
      return nil, "selected_track_count"
    end
    return reaper.GetSelectedTrack(0, 0)
  end
  if tonumber(action.selected_index) then
    local index = math.floor(tonumber(action.selected_index))
    if index < 1 or index > reaper.CountSelectedTracks(0) then
      return nil, "selected_track_missing"
    end
    return reaper.GetSelectedTrack(0, index - 1)
  end
  if tonumber(action.index) then
    local index = math.floor(tonumber(action.index))
    if index < 1 or index > reaper.CountTracks(0) then
      return nil, "track_index_missing"
    end
    return reaper.GetTrack(0, index - 1)
  end
  return nil, "invalid_selector"
end

local function db_to_amp(db)
  return 10 ^ ((tonumber(db) or 0) / 20)
end

local function send_mode(value)
  if value == nil or value == "post_fader" then return 0 end
  if value == "pre_fx" then return 1 end
  if value == "pre_fader" or value == "post_fx" then return 3 end
  return tonumber(value) or 0
end

function Code.execute_typed_actions_from_text(text, opts)
  opts = type(opts) == "table" and opts or {}
  local plan, errors = Code.typed_actions_plan_from_text(text, opts)
  if not plan then
    return false, {
      code=first_error(errors) or "invalid_plan",
      message=Code.format_typed_action_semantic_errors(errors, 4),
      action_results={},
    }
  end
  local semantic_ok, semantic_errors =
    Code.validate_typed_actions_semantics(plan, opts)
  if not semantic_ok then
    return false, {
      code=first_error(semantic_errors) or "semantic_mismatch",
      message=Code.format_typed_action_semantic_errors(semantic_errors, 4),
      action_results={},
    }
  end

  local tracks = {}
  for _, action in ipairs(plan.actions) do
    if action.op == "track.resolve" then
      local track, reason = resolve_track(action)
      if not track then
        return false, {code=reason, message="Could not resolve the requested track.",
          action_results={}}
      end
      tracks[action.id] = track
    elseif action.op == "track.ensure" then
      local track, reason = find_named_track(action.name)
      if reason == "ambiguous_track" then
        return false, {code=reason,
          message="More than one track has the requested name.",
          action_results={}}
      end
      if track then tracks[action.id] = track end
    end
  end

  local results, undo_open, refresh_open = {}, false, false
  local function close_undo(label)
    if not undo_open then return end
    if type(reaper.Undo_EndBlock2) == "function" then
      reaper.Undo_EndBlock2(0, label, -1)
    else
      reaper.Undo_EndBlock(label, -1)
    end
    undo_open = false
  end
  local function result(action, status)
    results[#results + 1] = {
      op=action.op, id=action.id, status=status or "completed",
    }
  end

  if type(reaper.Undo_BeginBlock2) == "function" then
    reaper.Undo_BeginBlock2(0)
  else
    reaper.Undo_BeginBlock()
  end
  undo_open = true
  reaper.PreventUIRefresh(1)
  refresh_open = true

  local ok, run_error = xpcall(function()
    for _, action in ipairs(plan.actions) do
      if action.op == "track.create" or action.op == "track.ensure" then
        local track, created = tracks[action.id], false
        if not track then
          local index = reaper.CountTracks(0)
          reaper.InsertTrackAtIndex(index, true)
          track, created = reaper.GetTrack(0, index), true
          if not track then error("Could not create the requested track.") end
          tracks[action.id] = track
        end
        if nonempty(action.name) then
          reaper.GetSetMediaTrackInfo_String(track, "P_NAME", action.name, true)
        end
        if action.select == true then reaper.SetTrackSelected(track, true) end
        result(action, created and "created" or "reused")
      elseif action.op == "track.resolve" then
        result(action, "resolved")
      elseif action.op == "track.set" then
        local track = tracks[action.track]
        if not track then error("A track reference became unavailable.") end
        if action.name ~= nil then
          reaper.GetSetMediaTrackInfo_String(track, "P_NAME",
            tostring(action.name), true)
        end
        if action.volume_db ~= nil then
          reaper.SetMediaTrackInfo_Value(track, "D_VOL", db_to_amp(action.volume_db))
        end
        if action.pan_pct ~= nil then
          local pan = math.max(-100, math.min(100, tonumber(action.pan_pct) or 0))
          reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan / 100)
        end
        if action.mute ~= nil then
          reaper.SetMediaTrackInfo_Value(track, "B_MUTE", action.mute and 1 or 0)
        end
        if action.solo ~= nil then
          reaper.SetMediaTrackInfo_Value(track, "I_SOLO", action.solo and 1 or 0)
        end
        if action.master_send ~= nil then
          reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND",
            action.master_send and 1 or 0)
        end
        result(action)
      elseif action.op == "track.folder" then
        local parent = tracks[action.parent]
        local last_child = tracks[action.children[#action.children]]
        if not parent or not last_child then
          error("A folder track reference became unavailable.")
        end
        reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH",
          reaper.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") + 1)
        reaper.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH",
          reaper.GetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH") - 1)
        result(action)
      elseif action.op == "send.create" then
        local source, destination = tracks[action["from"]], tracks[action.to]
        if not source or not destination then
          error("A send track reference became unavailable.")
        end
        local index = reaper.CreateTrackSend(source, destination)
        if not index or index < 0 then error("REAPER could not create the send.") end
        if action.volume_db ~= nil then
          reaper.SetTrackSendInfo_Value(source, 0, index, "D_VOL",
            db_to_amp(action.volume_db))
        end
        if action.pan ~= nil then
          reaper.SetTrackSendInfo_Value(source, 0, index, "D_PAN",
            math.max(-1, math.min(1, tonumber(action.pan) or 0)))
        end
        if action.mode ~= nil then
          reaper.SetTrackSendInfo_Value(source, 0, index, "I_SENDMODE",
            send_mode(action.mode))
        end
        if action.muted ~= nil then
          reaper.SetTrackSendInfo_Value(source, 0, index, "B_MUTE",
            action.muted and 1 or 0)
        end
        result(action)
      end
    end
  end, debug and debug.traceback or tostring)

  if refresh_open then reaper.PreventUIRefresh(-1) end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  close_undo(ok and "ReaAssist: Track and routing edit"
    or "ReaAssist: Track and routing edit stopped")
  if not ok then
    return false, {code="execution_failed", message=tostring(run_error),
      action_results=results, completed=true}
  end
  return true, {code="ok", message="Track and routing edit completed.",
    action_results=results, completed=true}
end
end -- close small structured track-edit scope


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
-- Common failure mode caught: some lower-cost models emit plausible-sounding
-- but non-existent names like "GetProjectMarkerByIndex" (real function is
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

-- Flag only high-confidence state-chunk rewrites that consume the remainder of
-- an envelope VIS record and replace it with a one-field record. REAPER on
-- Windows currently normalizes `VIS 1` back to `VIS 1 1 1`, but the state
-- chunk contract is not documented as accepting that shorthand on every host.
-- Preserve the remaining fields instead of relying on host normalization.
function Code.find_destructive_envelope_vis_rewrites(lua_code)
  if not lua_code or lua_code == "" then return nil end
  local stripped = lua_code
    :gsub("%-%-%[%[.-%]%]", function(s) return s:gsub("[^\n]", "") end)
    :gsub("%-%-[^\n]*", "")
  if not stripped:find("reaper%.SetEnvelopeStateChunk%s*%(")
     or not stripped:find("reaper%.GetEnvelopeStateChunk%s*%(") then
    return nil
  end

  local findings = {}
  local pos = 1
  while true do
    local start_pos, open_pos = stripped:find("[:%.]gsub%s*%(", pos)
    if not start_pos then break end
    local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
    local pattern_arg = args and tostring(args[1] or "") or ""
    local replacement_arg = args and tostring(args[2] or "") or ""
    local vis_pos = pattern_arg:find("VIS", 1, true)
    local quote = replacement_arg:sub(1, 1)
    local literal_replacement = (quote == '"' or quote == "'")
      and replacement_arg:sub(-1) == quote
    local replacement_body = literal_replacement
      and replacement_arg:sub(2, -2) or ""
    if vis_pos and literal_replacement
       and replacement_body:find("VIS%s+[01]") then
      local pattern_tail = pattern_arg:sub(vis_pos + 3)
      local _, numeric_fields = pattern_tail:gsub("%%d[%*+]?", "")
      local consumes_record_tail = pattern_tail:find("%.%*", 1) ~= nil
        or pattern_tail:find("%.%-", 1) ~= nil
        or pattern_tail:find("%[%^[^%]]+%][%*+]", 1) ~= nil
        or numeric_fields >= 2
      local tail_has_capture = false
      local scan_pos = 1
      while scan_pos <= #pattern_tail do
        local char = pattern_tail:sub(scan_pos, scan_pos)
        if char == "%" then
          scan_pos = scan_pos + 2
        elseif char == "(" then
          tail_has_capture = true
          break
        else
          scan_pos = scan_pos + 1
        end
      end
      local preserves_suffix = tail_has_capture
        and replacement_body:find("%%[1-9]", 1) ~= nil
      if consumes_record_tail and not preserves_suffix then
        findings[#findings + 1] = {
          kind = "envelope_vis_line_collapse",
          line = Code._lua_line_for_pos(stripped, start_pos),
          detail = "Envelope VIS rewrite consumes the remaining record fields without preserving them.",
        }
      end
    end
    pos = (close_pos or open_pos) + 1
  end
  return #findings > 0 and findings or nil
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

function Code.find_unsafe_literal_name_word_removal(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local raw_request = tostring(user_text or ""):lower()
  local literal = raw_request:match(
    "%f[%w]remove%s+the%s+word%s+[\"']?([%a]+)")
    or raw_request:match("%f[%w]delete%s+the%s+word%s+[\"']?([%a]+)")
    or raw_request:match("%f[%w]strip%s+the%s+word%s+[\"']?([%a]+)")
  if not literal then
    local request = Code._localized_action_intent_text(user_text)
    literal = request:match(
      "%f[%w]remove%s+the%s+word%s+[\"']?([%a]+)")
      or request:match("%f[%w]delete%s+the%s+word%s+[\"']?([%a]+)")
      or request:match("%f[%w]strip%s+the%s+word%s+[\"']?([%a]+)")
  end
  if not literal or literal == "" then return nil end

  local source = lua_code
  literal = literal:lower()
  local removal_pos = nil
  local unsafe_removal_pos = nil
  local saw_literal_removal = false
  local has_boundaries = true
  local cleans_spaces = false
  local cleans_underscores = false
  local cleans_hyphens = false
  local has_left_trim = false
  local has_right_trim = false
  local scan_pos = 1
  while true do
    local call_pos, open_pos = source:find(":gsub%s*%(", scan_pos)
    if not call_pos then break end
    local args, close_pos = Code._parse_lua_call_args(source, open_pos)
    local pattern = args and args[1]
      and args[1]:match("^%s*[\"'](.-)[\"']%s*$") or nil
    local replacement = args and args[2]
      and args[2]:match("^%s*[\"'](.-)[\"']%s*$") or nil
    if pattern and replacement ~= nil then
      local bounded_word = pattern:match(
        "^%%f%[%%w%]([%a]+)%%f%[%%W%]$")
      if replacement == "" and (pattern:lower() == literal
          or (bounded_word and bounded_word:lower() == literal)) then
        saw_literal_removal = true
        removal_pos = removal_pos or call_pos
        if pattern:lower() == literal then
          has_boundaries = false
          unsafe_removal_pos = unsafe_removal_pos or call_pos
        end
      end

      if replacement == "%1" and pattern == "^%s*(.-)%s*$" then
        has_left_trim = true
        has_right_trim = true
      elseif replacement == "" or replacement == " " then
        local repeated = pattern:find("+", 1, true) ~= nil
        local char_class = pattern:find("[", 1, true) ~= nil
          and pattern:find("]", 1, true) ~= nil
        if repeated and pattern:find("%s", 1, true) then
          cleans_spaces = true
        end
        if pattern == "_" or pattern == "_+"
            or (repeated and char_class
              and pattern:find("_", 1, true)) then
          cleans_underscores = true
        end
        if pattern == "-" or pattern == "%-"
            or pattern == "-+" or pattern == "%-+"
            or (repeated and char_class
              and (pattern:find("%-", 1, true)
                or pattern:find("-", 1, true))) then
          cleans_hyphens = true
        end
        if pattern == "^%s+" then has_left_trim = true end
        if pattern == "%s+$" then has_right_trim = true end
        local left_class = pattern:match("^%^(%b[])%+$")
        local right_class = pattern:match("^(%b[])%+%$$")
        if left_class and left_class:find("%s", 1, true) then
          has_left_trim = true
        end
        if right_class and right_class:find("%s", 1, true) then
          has_right_trim = true
        end
      end
    end
    scan_pos = (close_pos or open_pos) + 1
  end
  scan_pos = 1
  while true do
    local call_pos, open_pos = source:find(":match%s*%(", scan_pos)
    if not call_pos then break end
    local args, close_pos = Code._parse_lua_call_args(source, open_pos)
    local pattern = args and args[1]
      and args[1]:match("^%s*[\"'](.-)[\"']%s*$") or nil
    if pattern == "^%s*(.-)%s*$" then
      has_left_trim = true
      has_right_trim = true
    end
    scan_pos = (close_pos or open_pos) + 1
  end
  if not saw_literal_removal then return nil end

  local has_delimiter_cleanup = cleans_spaces and cleans_underscores
    and cleans_hyphens and has_left_trim and has_right_trim
  local lower = source:lower()
  local function trim_guard_expr(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
  end
  local function strip_guard_parens(value)
    local expr = trim_guard_expr(value)
    while expr:sub(1, 1) == "(" and expr:sub(-1) == ")" do
      local depth, quote, wraps = 0, nil, true
      local i = 1
      while i <= #expr do
        local c = expr:sub(i, i)
        if quote then
          if c == "\\" then
            i = i + 1
          elseif c == quote then
            quote = nil
          end
        elseif c == "\"" or c == "'" then
          quote = c
        elseif c == "(" then
          depth = depth + 1
        elseif c == ")" then
          depth = depth - 1
          if depth == 0 and i < #expr then
            wraps = false
            break
          end
        end
        i = i + 1
      end
      if not wraps or depth ~= 0 then break end
      expr = trim_guard_expr(expr:sub(2, -2))
    end
    return expr
  end
  local function split_guard_boolean(value, operator)
    local parts, depth, quote = {}, 0, nil
    local start_pos, i, found = 1, 1, false
    while i <= #value do
      local c = value:sub(i, i)
      if quote then
        if c == "\\" then
          i = i + 1
        elseif c == quote then
          quote = nil
        end
      elseif c == "\"" or c == "'" then
        quote = c
      elseif c == "(" then
        depth = depth + 1
      elseif c == ")" then
        depth = math.max(0, depth - 1)
      elseif depth == 0 and value:sub(i, i + #operator - 1) == operator then
        local before = value:sub(i - 1, i - 1)
        local after = value:sub(i + #operator, i + #operator)
        if (before == "" or not before:match("[%w_]"))
            and (after == "" or not after:match("[%w_]")) then
          parts[#parts + 1] = trim_guard_expr(value:sub(start_pos, i - 1))
          start_pos = i + #operator
          i = start_pos - 1
          found = true
        end
      end
      i = i + 1
    end
    if not found then return nil end
    parts[#parts + 1] = trim_guard_expr(value:sub(start_pos))
    return parts
  end
  local function guaranteed_nonempty_variables(value)
    local expr = strip_guard_parens(value)
    local alternatives = split_guard_boolean(expr, "or")
    if alternatives then
      local common = guaranteed_nonempty_variables(alternatives[1])
      for i = 2, #alternatives do
        local branch = guaranteed_nonempty_variables(alternatives[i])
        for name in pairs(common) do
          if not branch[name] then common[name] = nil end
        end
      end
      return common
    end
    local requirements = split_guard_boolean(expr, "and")
    if requirements then
      local combined = {}
      for _, requirement in ipairs(requirements) do
        for name in pairs(guaranteed_nonempty_variables(requirement)) do
          combined[name] = true
        end
      end
      return combined
    end
    local name = expr:match('^([%a_][%w_]*)%s*~=%s*""$')
      or expr:match("^([%a_][%w_]*)%s*~=%s*''$")
      or expr:match("^#%s*([%a_][%w_]*)%s*>%s*0$")
    return name and { [name] = true } or {}
  end
  local has_empty_guard = false
  for condition in lower:gmatch("if%s+([^\r\n]-)%s+then") do
    if next(guaranteed_nonempty_variables(condition)) then
      has_empty_guard = true
      break
    end
  end
  if not has_empty_guard then
    local empty_scan_pos = 1
    while true do
      local _, empty_if_end, empty_var = lower:find(
        "if%s+([%a_][%w_]*)%s*==%s*[\"']%s*[\"']%s+then",
        empty_scan_pos)
      if not empty_if_end then break end
      local branch_end = lower:find("%f[%w]end%f[%W]", empty_if_end + 1)
        or (#lower + 1)
      local branch = lower:sub(empty_if_end + 1, branch_end - 1)
      if branch:find("%f[%w]return%f[%W]")
          or branch:find(
            "%f[%w]" .. empty_var .. "%f[%W]%s*=%s*[%a_][%w_]*") then
        has_empty_guard = true
        break
      end
      local goto_label = branch:match("%f[%w]goto%s+([%a_][%w_]*)")
      if goto_label then
        local p_name_pos = lower:find("[\"']p_name[\"']", branch_end + 1)
        local label_pos = lower:find(
          "::%s*" .. goto_label .. "%s*::", branch_end + 1)
        if p_name_pos and label_pos and label_pos > p_name_pos then
          has_empty_guard = true
          break
        end
      end
      empty_scan_pos = empty_if_end + 1
    end
  end
  if not has_empty_guard then
    local function parse_conditional_fallback(rhs)
      local patterns = {
        '^%(%s*([%a_][%w_]*)%s*~=%s*""%s+and%s+'
          .. '([%a_][%w_]*)%s*%)%s+or%s+(.+)$',
        "^%(%s*([%a_][%w_]*)%s*~=%s*''%s+and%s+"
          .. "([%a_][%w_]*)%s*%)%s+or%s+(.+)$",
        '^([%a_][%w_]*)%s*~=%s*""%s+and%s+'
          .. '([%a_][%w_]*)%s+or%s+(.+)$',
        "^([%a_][%w_]*)%s*~=%s*''%s+and%s+"
          .. "([%a_][%w_]*)%s+or%s+(.+)$",
      }
      for _, pattern in ipairs(patterns) do
        local tested, kept, fallback = rhs:match(pattern)
        if tested then return tested, kept, trim_guard_expr(fallback) end
      end
      return nil
    end
    local function fallback_is_nonempty(value, guarded_name)
      local identifier = value:match("^([%a_][%w_]*)$")
      if identifier then return identifier ~= guarded_name end
      local literal = value:match('^"(.*)"$') or value:match("^'(.*)'$")
      return literal ~= nil and literal:find("%S") ~= nil
    end
    for line in lower:gmatch("[^\r\n]+") do
      local assigned, rhs = line:match(
        "^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
      local tested, kept, fallback
      if rhs then
        tested, kept, fallback = parse_conditional_fallback(rhs)
      end
      if assigned and assigned == tested and tested == kept
          and fallback_is_nonempty(fallback, tested) then
        has_empty_guard = true
        break
      end
    end
  end
  if has_boundaries and has_delimiter_cleanup and has_empty_guard then
    return nil
  end
  return {{
    kind = "unsafe_literal_name_word_removal",
    line = Code._lua_line_for_pos(source,
      unsafe_removal_pos or removal_pos),
    missing_boundaries = not has_boundaries,
    missing_delimiter_cleanup = not has_delimiter_cleanup,
    missing_empty_guard = not has_empty_guard,
  }}
end

function Code.prompt_requests_midi_receive_change(user_text)
  local lt = Code._localized_action_intent_text(user_text)
  if not lt:find("%f[%w]midi%f[%W]") then return false end
  return lt:find("%f[%w]receive%f[%W]") ~= nil
    or lt:find("%f[%w]receives%f[%W]") ~= nil
    or lt:find("midi input", 1, true) ~= nil
    or lt:find("input routing", 1, true) ~= nil
end

function Code.find_midi_receive_identity_misuse(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == ""
      or not Code.prompt_requests_midi_receive_change(user_text) then
    return nil
  end
  local source = lua_code
  local findings = {}
  local function trimmed(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
  end
  local block_tokens = {}
  local masked_parts = {}
  local token_pos = 1
  if type(Code.tokenize_lua) == "function" then
    for _, token in ipairs(Code.tokenize_lua(source) or {}) do
      local text = token.text or ""
      if token.type == "str" or token.type == "com" then
        masked_parts[#masked_parts + 1] = text:gsub("[^\r\n]", " ")
      else
        masked_parts[#masked_parts + 1] = text
      end
      if token.type ~= "ws" and token.type ~= "str"
          and token.type ~= "com" then
        block_tokens[#block_tokens + 1] = {
          text = text,
          pos = token_pos,
        }
      end
      token_pos = token_pos + #text
    end
  else
    masked_parts[1] = source
    for word_pos, word in source:gmatch("()([%a_][%w_]*)") do
      block_tokens[#block_tokens + 1] = { text = word, pos = word_pos }
    end
  end
  local masked = table.concat(masked_parts)
  local function matching_loop_end(body_start)
    local depth = 1
    for _, token in ipairs(block_tokens) do
      if token.pos >= body_start then
        local word = token.text
        if word == "do" or word == "function" or word == "if"
            or word == "repeat" then
          depth = depth + 1
        elseif word == "end" or word == "until" then
          depth = depth - 1
          if depth == 0 then return token.pos end
        end
      end
    end
    return #source + 1
  end
  local direct_loops = {}
  local collected_loops = {}
  if type(Code.tokenize_lua) == "function" then
    for token_index, token in ipairs(block_tokens) do
      if token.text == "for" then
        local index_token = block_tokens[token_index + 1]
        local equals_token = block_tokens[token_index + 2]
        if index_token and index_token.text:match("^[%a_][%w_]*$")
            and equals_token and equals_token.text == "=" then
          local do_token = nil
          for scan_index = token_index + 3, #block_tokens do
            local candidate = block_tokens[scan_index]
            if candidate.text == "for" or candidate.text == "end" then break end
            if candidate.text == "do" then
              do_token = candidate
              break
            end
          end
          if do_token then
            local header_tail = masked:sub(
              equals_token.pos + 1, do_token.pos - 1)
            if header_tail:match(
                "%-%s*1%s*,%s*0%s*,%s*%-1%s*$") then
              local body_start = do_token.pos + #do_token.text
              direct_loops[#direct_loops + 1] = {
                index = index_token.text,
                body_start = body_start,
                body_end = matching_loop_end(body_start),
              }
            end
          end
        end
      end
    end
  else
    -- Production loads the tokenizer. Keep this reduced-capability fallback
    -- conservative by recognizing a descending header only when its start
    -- bound ends on the same line as the equals sign.
    local loop_scan_pos = 1
    while true do
      local loop_pos, header_end, index_name, body_start = masked:find(
        "for%s+([%a_][%w_]*)%s*=%s*[^\r\n]-%-%s*1%s*,%s*0%s*,%s*%-1%s+do()",
        loop_scan_pos)
      if not loop_pos then break end
      direct_loops[#direct_loops + 1] = {
        index = index_name,
        body_start = body_start,
        body_end = matching_loop_end(body_start),
      }
      loop_scan_pos = header_end + 1
    end
  end
  local loop_scan_pos = 1
  while true do
    local loop_pos, _, index_name, list_name, body_start = masked:find(
      "for%s+([%a_][%w_]*)%s*=%s*#([%a_][%w_]*)%s*,%s*1%s*,%s*%-1%s+do()",
      loop_scan_pos)
    if not loop_pos then break end
    collected_loops[#collected_loops + 1] = {
      index = index_name,
      list = list_name,
      body_start = body_start,
      body_end = matching_loop_end(body_start),
    }
    loop_scan_pos = body_start
  end
  local function removal_has_descending_iteration(call_pos, index_expr)
    local compact_index = index_expr:gsub("%s+", "")
    for _, loop in ipairs(direct_loops) do
      if call_pos >= loop.body_start and call_pos < loop.body_end
          and compact_index == loop.index then
        return true
      end
    end
    for _, loop in ipairs(collected_loops) do
      if call_pos >= loop.body_start and call_pos < loop.body_end then
        local direct_index = loop.list .. "[" .. loop.index .. "]"
        if compact_index == direct_index then return true end
        local prefix = source:sub(loop.body_start, call_pos - 1)
        local escaped_list = loop.list:gsub("(%W)", "%%%1")
        local escaped_index = loop.index:gsub("(%W)", "%%%1")
        for hoisted in prefix:gmatch(
            "local%s+([%a_][%w_]*)%s*<%s*const%s*>%s*=%s*"
              .. escaped_list .. "%s*%[%s*" .. escaped_index .. "%s*%]") do
          if compact_index == hoisted then return true end
        end
        for hoisted in prefix:gmatch(
            "local%s+([%a_][%w_]*)%s*=%s*" .. escaped_list
              .. "%s*%[%s*" .. escaped_index .. "%s*%]") do
          if compact_index == hoisted then return true end
        end
      end
    end
    return false
  end
  local has_source_identity = source:find("[\"']P_SRCTRACK[\"']") ~= nil
  local has_audio_identity = source:find("[\"']I_SRCCHAN[\"']") ~= nil
    and source:find("==%s*%-1") ~= nil
  local has_midi_identity = source:find("[\"']I_MIDIFLAGS[\"']") ~= nil
    and (source:find("&%s*31") ~= nil
      or source:find("%%%s*32") ~= nil)
  local remove_scan_pos = 1
  while true do
    local remove_pos, remove_open_pos = source:find(
      "reaper%.RemoveTrackSend%s*%(", remove_scan_pos)
    if not remove_pos then break end
    local args, close_pos = Code._parse_lua_call_args(source, remove_open_pos)
    local has_receive_category = trimmed(args and args[2]) == "-1"
    local has_descending_receive_loop = args and args[3]
      and removal_has_descending_iteration(remove_pos, trimmed(args[3])) or false
    if not (has_receive_category and has_descending_receive_loop
        and has_source_identity and has_audio_identity and has_midi_identity) then
      findings[#findings + 1] = {
        kind = "unsafe_midi_receive_identity",
        line = Code._lua_line_for_pos(source, remove_pos),
        missing_receive_category = not has_receive_category,
        missing_descending_iteration = not has_descending_receive_loop,
        missing_source_identity = not has_source_identity,
        missing_audio_identity = not has_audio_identity,
        missing_midi_identity = not has_midi_identity,
      }
    end
    remove_scan_pos = (close_pos or remove_open_pos) + 1
  end

  local function assignments_before(call_pos)
    local assignments = {}
    local prefix = source:sub(1, math.max(0, call_pos - 1)) .. "\n"
    for raw_line in prefix:gmatch("([^\n]*)\n") do
      local line = raw_line:gsub("\r$", ""):gsub("%s+%-%-.*$", "")
      local name, rhs = line:match(
        "^%s*local%s+([%a_][%w_]*)%s*<%s*const%s*>%s*=%s*(.-)%s*$")
      if not name then
        name, rhs = line:match(
          "^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
      end
      if not name then
        name, rhs = line:match(
          "^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
      end
      if name and rhs and rhs ~= "" then assignments[name] = rhs end
    end
    return assignments
  end
  local function resolve_bare_assignment(value_expr, assignments)
    local current = trimmed(value_expr)
    local visited = {}
    for _ = 1, 4 do
      local name = current:match("^([%a_][%w_]*)$")
      if not name then return current, false end
      if visited[name] then return current, true end
      visited[name] = true
      local rhs = assignments[name]
      if not rhs then return current, true end
      current = trimmed(rhs)
    end
    return current, current:match("^[%a_][%w_]*$") ~= nil
  end
  local function expression_has_integer_flags(value_expr, assignments)
    if value_expr:find("math%.floor%s*%(") then return true end
    for name in value_expr:gmatch("[%a_][%w_]*") do
      local resolved = resolve_bare_assignment(name, assignments)
      if resolved:find("math%.floor%s*%(") then return true end
    end
    return false
  end

  local flags_scan_pos = 1
  while true do
    local flags_pos, flags_open_pos = source:find(
      "reaper%.SetTrackSendInfo_Value%s*%(", flags_scan_pos)
    if not flags_pos then break end
    local args, close_pos = Code._parse_lua_call_args(source, flags_open_pos)
    local parm = args and args[4]
      and args[4]:match("^%s*[\"'](.-)[\"']%s*$") or nil
    if parm == "I_MIDIFLAGS" then
      local assignments = assignments_before(flags_pos)
      local value_expr, unresolved = resolve_bare_assignment(
        args and args[5] or "", assignments)
      local has_integer_flags = expression_has_integer_flags(
        value_expr, assignments)
      local disables_source = value_expr:find("|%s*31%f[^%d]") ~= nil
      local channel_literal = value_expr:match("|%s*(%d+)%f[^%d]")
      local or_pos = value_expr:find("|", 1, true)
      local low_value_expr = or_pos and value_expr:sub(or_pos + 1) or ""
      local has_masked_low_value = low_value_expr:find("&%s*31") ~= nil
      local masked_channel_write =
        value_expr:find("&%s*~%s*31") ~= nil
        and ((channel_literal and tonumber(channel_literal) <= 16)
          or has_masked_low_value)
      local safe_write = has_integer_flags
        and (disables_source or masked_channel_write)
      local direct_literal = value_expr:match("^[%+%-]?%d+$") ~= nil
      local provably_unsafe = direct_literal
        or (channel_literal ~= nil and not safe_write)
      if not safe_write and provably_unsafe and not unresolved then
        findings[#findings + 1] = {
          kind = "overwrites_packed_midi_flags",
          line = Code._lua_line_for_pos(source, flags_pos),
        }
      end
    end
    flags_scan_pos = (close_pos or flags_open_pos) + 1
  end
  return #findings > 0 and findings or nil
end

function Code.find_effect_initialization_advisories(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local source = lua_code
  local add_pos = source:find("reaper%.TrackFX_AddByName%s*%(")
  if not add_pos or not source:find("reaper%.TrackFX_SetParam") then return nil end
  if Code.find_param_calls_outside_defer(lua_code) then return nil end

  local stock = {
    reaeq = true, reacomp = true, readelay = true, reaverbate = true,
    reagate = true, realimit = true, reapitch = true, reatune = true,
    reaxcomp = true, reacontrolmidi = true,
  }
  local saw_unknown = false
  local pos = 1
  while true do
    local first, open_pos = source:find("reaper%.TrackFX_AddByName%s*%(", pos)
    if not first then break end
    local args, close_pos = Code._parse_lua_call_args(source, open_pos)
    local name = args and args[2] and args[2]:match("^%s*[\"'](.-)[\"']%s*$")
    local bare_name = name and name:lower():gsub("^.-:%s*", "") or ""
    bare_name = bare_name:gsub("%s*%b()%s*$", "")
    local key = bare_name:gsub("[^%a%d]", "")
    if key == "" or not stock[key] then saw_unknown = true; break end
    pos = (close_pos or open_pos) + 1
  end
  if not saw_unknown then return nil end
  return {{
    kind = "unknown_effect_same_cycle_param_write",
    line = Code._lua_line_for_pos(source, add_pos),
    review_only = true,
  }}
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

function Code.prompt_needs_loudness_bundle_clarification(user_text)
  local lt = Code._localized_action_intent_text(user_text)
  if lt == "" then return false end
  if not (Code.prompt_likely_needs_lua_action
      and Code.prompt_likely_needs_lua_action(user_text)) then
    return false
  end
  local has_lufs = lt:find("%f[%w]lufs%f[%W]") ~= nil
    or (lt:find("%f[%w]integrated%f[%W]") ~= nil
      and lt:find("%f[%w]loudness%f[%W]") ~= nil)
  local has_peak_unit = lt:find("%f[%w]dbfs%f[%W]") ~= nil
    or (lt:find("%f[%w]peak%f[%W]") ~= nil
      and lt:find("%f[%w]db%f[%W]") ~= nil)
  if not has_lufs or not has_peak_unit then return false end

  local numeric_count = 0
  for _ in lt:gmatch("[%+%-]?%d+[%.,]?%d*") do
    numeric_count = numeric_count + 1
  end
  local has_measurement_source =
       lt:find("%f[%w]measure%f[%W]") ~= nil
    or lt:find("%f[%w]measured%f[%W]") ~= nil
    or lt:find("%f[%w]analyze%f[%W]") ~= nil
    or lt:find("%f[%w]render%f[%W]") ~= nil
    or lt:find("%f[%w]rendered%f[%W]") ~= nil
  if has_measurement_source and numeric_count >= 2 then return false end
  return true, {
    kind = numeric_count < 2 and "mixed_units" or "measurement_required",
    numeric_count = numeric_count,
  }
end

function Code.prompt_needs_vocal_edit_clarification(user_text)
  local lt = Code._localized_action_intent_text(user_text)
  if lt == "" then return false end
  if not (Code.prompt_likely_needs_lua_action
      and Code.prompt_likely_needs_lua_action(user_text)) then
    return false
  end
  local has_vocal = lt:find("%f[%w]vocal%f[%W]") ~= nil
    or lt:find("%f[%w]vocals%f[%W]") ~= nil
  local has_pitch = lt:find("pitch%s+correction") ~= nil
    or lt:find("%f[%w]pitch%f[%W]") ~= nil
    or lt:find("%f[%w]tune%f[%W]") ~= nil
    or lt:find("%f[%w]tuning%f[%W]") ~= nil
  local has_level_goal = lt:find("%f[%w]level%f[%W]") ~= nil
    or lt:find("%f[%w]levels%f[%W]") ~= nil
    or lt:find("%f[%w]gain%f[%W]") ~= nil
    or lt:find("%f[%w]ideal%f[%W]") ~= nil
  if not (has_vocal and has_pitch and has_level_goal) then return false end

  local has_target = lt:find("%f[%w]selected%f[%W]") ~= nil
    or lt:find("%f[%w]track%f[%W]") ~= nil
    or lt:find("%f[%w]tracks%f[%W]") ~= nil
    or lt:find("[\"'][^\"']+[\"']") ~= nil
  local has_method = lt:find("%f[%w]plugin%f[%W]") ~= nil
    or lt:find("%f[%w]effect%f[%W]") ~= nil
    or lt:find("%f[%w]stretch%f[%W]") ~= nil
    or lt:find("%f[%w]manual%f[%W]") ~= nil
    or lt:find("%f[%w]reatune%f[%W]") ~= nil
    or lt:find("%f[%w]autotune%f[%W]") ~= nil
  local has_value = lt:find("[%+%-]?%d+[%.,]?%d*%s*[dD][bB]") ~= nil
    or lt:find("[%+%-]?%d+[%.,]?%d*%s*%%") ~= nil
  if has_target and has_method and has_value then return false end
  return true, {
    missing_target = not has_target,
    missing_method = not has_method,
    missing_value = not has_value,
  }
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
    "%f[%w]do%s+not%s+create%s+sends?%f[%W]",
    "%f[%w]don't%s+create%s+sends?%f[%W]",
    "%f[%w]dont%s+create%s+sends?%f[%W]",
    "%f[%w]no%s+sends?%f[%W]",
    "%f[%w]without%s+sends?%f[%W]",
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

function Code.lua_satisfies_sidechain_ducking_send(
    lua_code, user_text, require_functional_channels)
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
    -- A single explicit route is often resolved through generic variables
    -- populated by a name-matching loop. The requested endpoint names remain
    -- visible in that loop, but the final CreateTrackSend call only contains
    -- source_track/destination_track. Accept those conventional role names
    -- for one-source requests while keeping multi-source routes strict.
    if #explicit_sources == 1 then
      for _, name in ipairs({ "source", "source_track", "src", "src_track" }) do
        add_alias("source1", name)
      end
      for _, name in ipairs({
          "destination", "destination_track", "dest", "dest_track" }) do
        add_alias("dest", name)
      end
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
  for indexed, quoted in lowered:gmatch(
      "getsetmediatrackinfo_string%s*%(%s*([%a_][%w_]*%s*%[%s*%d+%s*%])%s*,%s*[\"']p_name[\"']%s*,%s*[\"']([^\"']+)[\"']") do
    local role = role_for_text(quoted)
    if role then add_alias(role, indexed) end
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
    local loop_name_pat =
      "getsetmediatrackinfo_string%s*%(%s*([%a_][%w_]*)%s*,%s*[\"']p_name[\"']%s*,%s*"
      .. names_var .. "%[%s*([%a_][%w_]*)%s*%+%s*1%s*%]"
    for track_var, index_var in lowered:gmatch(loop_name_pat) do
      local store_pat = "([%a_][%w_]*)%s*%[%s*" .. index_var
        .. "%s*%+%s*1%s*%]%s*=%s*" .. track_var
      for track_table in lowered:gmatch(store_pat) do
        for idx, quoted in ipairs(entries) do
          local role = role_for_text(quoted)
          if role then
            add_alias(role, track_table .. "[" .. tostring(idx) .. "]")
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
    for lhs, rhs in lowered:gmatch(
        "([%a_][%w_]*%s*%[%s*%d+%s*%])%s*=%s*([%a_][%w_]*)") do
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
  local matched_sends = {}
  local function note_send(src, dst, send_var)
    send_count = send_count + 1
    if explicit then
      for i = 1, #explicit_sources do
        local role = "source" .. tostring(i)
        if expr_matches_role(src, role) and expr_matches_role(dst, "dest") then
          explicit_matches[role] = true
          if send_var then
            matched_sends[#matched_sends + 1] = {
              role = role,
              source = src,
              dest = dst,
              send_var = send_var,
            }
          end
        end
      end
    elseif expr_matches_role(src, "kick") and expr_matches_role(dst, "bass") then
      exact_send = true
      if send_var then
        matched_sends[#matched_sends + 1] = {
          role = "kick",
          source = src,
          dest = dst,
          send_var = send_var,
        }
      end
    end
  end
  for send_var, src, dst in lowered:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
    note_send(src, dst, send_var)
  end
  for send_var, src, dst in lowered:gmatch(
      "[%s;]([%a_][%w_]*)%s*=%s*reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
    note_send(src, dst, send_var)
  end
  for src, dst in lowered:gmatch(
      "reaper%.createtracksend%s*%(%s*([^,%)]-)%s*,%s*([^%)]+)%)") do
    note_send(src, dst)
  end
  local send_helpers = {}
  local local_helpers = {}
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
    local s, e, fname, params = lowered:find(
      "local%s+function%s+([%a_][%w_]*)%s*(%b())%s*", helper_pos)
    if not s then break end
    local body = local_function_body(e + 1)
    local_helpers[fname] = {
      body = body,
      first_param = tostring(params or ""):match(
        "^%(%s*([%a_][%w_]*)"),
    }
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
  local routes_ok = exact_send
  if explicit then
    for i = 1, #explicit_sources do
      if not explicit_matches["source" .. tostring(i)] then return false end
    end
    routes_ok = #explicit_sources > 0
  end
  if not routes_ok or not require_functional_channels then return routes_ok end

  local simple_numbers = {}
  for name, value in lowered:gmatch(
      "local%s+([%a_][%w_]*)%s*=%s*([%+%-]?%d*%.?%d+)%f[^%d%.]") do
    simple_numbers[name] = tonumber(value)
  end
  local function numeric_value(expr)
    expr = tostring(expr or ""):match("^%s*(.-)%s*$")
    return tonumber(expr) or simple_numbers[expr]
  end
  local function quoted_key(expr)
    return tostring(expr or ""):match("^%s*[\"']([^\"']+)[\"']%s*$")
  end
  local function compact_expr(expr)
    return tostring(expr or ""):lower():gsub("%s+", "")
  end
  local function split_call_args(call)
    call = tostring(call or "")
    if call:sub(1, 1) == "(" and call:sub(-1) == ")" then
      call = call:sub(2, -2)
    end
    local args, start_pos = {}, 1
    local paren, brace, bracket = 0, 0, 0
    local quote, escaped = nil, false
    for i = 1, #call do
      local char = call:sub(i, i)
      if quote then
        if escaped then
          escaped = false
        elseif char == "\\" then
          escaped = true
        elseif char == quote then
          quote = nil
        end
      elseif char == "\"" or char == "'" then
        quote = char
      elseif char == "(" then
        paren = paren + 1
      elseif char == ")" then
        paren = paren - 1
      elseif char == "{" then
        brace = brace + 1
      elseif char == "}" then
        brace = brace - 1
      elseif char == "[" then
        bracket = bracket + 1
      elseif char == "]" then
        bracket = bracket - 1
      elseif char == "," and paren == 0 and brace == 0 and bracket == 0 then
        args[#args + 1] = call:sub(start_pos, i - 1)
        start_pos = i + 1
      end
    end
    args[#args + 1] = call:sub(start_pos)
    return args
  end

  local destination_role = explicit and "dest" or "bass"
  local destination_channels_ok = false
  for call in lowered:gmatch(
      "reaper%.setmediatrackinfo_value%s*(%b())") do
    local args = split_call_args(call)
    if expr_matches_role(args[1], destination_role)
        and quoted_key(args[2]) == "i_nchan"
        and (numeric_value(args[3]) or 0) >= 4 then
      destination_channels_ok = true
      break
    end
  end
  if not destination_channels_ok then
    local channel_helpers = {}
    for fname, helper in pairs(local_helpers) do
      if helper.first_param then
        for call in helper.body:gmatch(
            "reaper%.setmediatrackinfo_value%s*(%b())") do
          local args = split_call_args(call)
          if compact_expr(args[1]) == compact_expr(helper.first_param)
              and quoted_key(args[2]) == "i_nchan"
              and (numeric_value(args[3]) or 0) >= 4 then
            channel_helpers[fname] = true
            break
          end
        end
      end
    end
    for fname, args_text in lowered:gmatch(
        "([%a_][%w_]*)%s*%(([^%)]*)%)") do
      if channel_helpers[fname] then
        local args = split_call_args("(" .. args_text .. ")")
        if expr_matches_role(args[1], destination_role) then
          destination_channels_ok = true
          break
        end
      end
    end
  end
  if not destination_channels_ok then return false end

  local functional_roles = {}
  for call in lowered:gmatch(
      "reaper%.settracksendinfo_value%s*(%b())") do
    local args = split_call_args(call)
    if quoted_key(args[4]) == "i_dstchan"
        and numeric_value(args[2]) == 0
        and numeric_value(args[5]) == 2 then
      for _, matched in ipairs(matched_sends) do
        if compact_expr(args[3]) == compact_expr(matched.send_var)
            and expr_matches_role(args[1], matched.role) then
          functional_roles[matched.role] = true
        end
      end
    end
  end
  if explicit then
    for i = 1, #explicit_sources do
      if not functional_roles["source" .. tostring(i)] then return false end
    end
    return true
  end
  return functional_roles.kick == true
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

function Code.find_midi_record_mode_output_misuse(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local stripped
  if type(Code.tokenize_lua) == "function" then
    local parts = {}
    for _, token in ipairs(Code.tokenize_lua(lua_code) or {}) do
      parts[#parts + 1] = token.type == "com"
        and _blank_non_newlines(token.text) or token.text
    end
    stripped = table.concat(parts)
  else
    stripped = lua_code:gsub("%-%-[^\n]*", _blank_non_newlines)
  end
  local assignments = {}
  for line in stripped:gmatch("[^\r\n]+") do
    local name, expr = line:match(
      "^%s*local%s+([%a_][%w_]*)%s*=%s*(.-)%s*$")
    if not name then
      name, expr = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
    end
    if name and expr and expr:sub(1, 1) ~= "=" then
      assignments[name] = Code._lua_trim_expr(expr)
    end
  end

  local function resolve_number(expr)
    local seen = {}
    local value = Code._lua_trim_expr(expr)
    for _ = 1, 5 do
      while value:match("^%b()$") do value = value:sub(2, -2) end
      local number = tonumber(value)
      if number ~= nil then return number end
      local name = value:match("^([%a_][%w_]*)$")
      if not name or seen[name] or assignments[name] == nil then return nil end
      seen[name] = true
      value = Code._lua_trim_expr(assignments[name])
    end
    return nil
  end

  local calls = {}
  local pos = 1
  while true do
    local first, open_pos = stripped:find(
      "reaper%.SetMediaTrackInfo_Value%s*%(", pos)
    if not first then break end
    local args, close_pos = Code._parse_lua_call_args(stripped, open_pos)
    if args and args[1] and args[2] and args[3] then
      calls[#calls + 1] = {
        first = first,
        line = Code._lua_line_for_pos(stripped, first),
        target = Code._lua_trim_expr(args[1]):gsub("%s+", ""),
        parm = Code._lua_trim_expr(args[2]):match("^[\"']([%w_]+)[\"']$"),
        value_expr = Code._lua_trim_expr(args[3]),
      }
    end
    pos = (close_pos or open_pos) + 1
  end

  local midi_input_targets = {}
  for _, call in ipairs(calls) do
    if call.parm == "I_RECINPUT" then
      local value = resolve_number(call.value_expr)
      local compact = call.value_expr:gsub("%s+", "")
      if (value and value >= 4096)
          or compact:find("4096", 1, true)
          or compact:find("GetMIDIInputName", 1, true) then
        midi_input_targets[call.target] = true
      end
    end
  end

  local raw_lines = {}
  for line in (lua_code .. "\n"):gmatch("(.-)\r?\n") do
    raw_lines[#raw_lines + 1] = line
  end
  local function adjacent_comment_supports_midi(line_no)
    for index = math.max(1, line_no - 1), line_no do
      local comment = tostring(raw_lines[index] or ""):match("%-%-(.*)$")
      local lower = comment and comment:lower() or ""
      if lower:find("midi", 1, true)
          and (lower:find("overdub", 1, true)
            or lower:find("replace", 1, true)
            or lower:find("record", 1, true)) then
        return true
      end
    end
    return false
  end

  local request_has_midi = Code.prompt_has_midi_workflow_intent(user_text or "")
  local request_lower = tostring(user_text or ""):lower()
  local function terms_match_gap(line, first, second, plain, gap_ok)
    local first_from = 1
    while true do
      local first_start, first_end = line:find(first, first_from, plain)
      if not first_start then break end
      local second_from = 1
      while true do
        local second_start, second_end = line:find(second, second_from, plain)
        if not second_start then break end
        local gap, gap_text = 0, ""
        if first_end < second_start then
          gap = second_start - first_end - 1
          gap_text = line:sub(first_end + 1, second_start - 1)
        elseif second_end < first_start then
          gap = first_start - second_end - 1
          gap_text = line:sub(second_end + 1, first_start - 1)
        end
        if gap <= 24 and (not gap_ok
            or gap_ok(gap_text or "", first_end < second_start)) then
          return true
        end
        second_from = math.max(second_end + 1, second_start + 1)
      end
      first_from = math.max(first_end + 1, first_start + 1)
    end
    return false
  end
  local function terms_are_near(line, first, second, plain)
    return terms_match_gap(line, first, second, plain, nil)
  end
  local english_direct_gap_words = {
    a = true, an = true, the = true,
    this = true, that = true, these = true, those = true,
    its = true, my = true, your = true, our = true, their = true,
    his = true, her = true, s = true,
    stereo = true, mono = true, main = true, master = true,
    track = true, tracks = true, audio = true, midi = true,
    hardware = true, software = true, virtual = true,
    instrument = true, synth = true, synthesizer = true,
    processed = true, wet = true, dry = true, direct = true,
    summed = true, multichannel = true, channel = true,
    left = true, right = true, selected = true, current = true,
    full = true, final = true, internal = true, external = true,
    pre = true, post = true, fader = true, fx = true, bus = true,
  }
  local english_reverse_gap_words = {
    to = true, ["for"] = true, be = true, being = true,
    should = true, is = true, was = true,
  }
  local function english_gap_is_direct_object(gap, record_before_output)
    if gap:find("[,;:%.%!%?&/]") then return false end
    local allowed = record_before_output
      and english_direct_gap_words or english_reverse_gap_words
    local count = 0
    for word in gap:gmatch("[a-z]+") do
      count = count + 1
      if not allowed[word] or count > 6 then return false end
    end
    return true
  end
  local function latin_gap_has_no_clause_connector(gap)
    if gap:find("[,;:%.%!%?&/]") then return false end
    for word in gap:gmatch("[a-z]+") do
      if word == "and" or word == "then" or word == "also"
          or word == "send" or word == "route" or word == "y"
          or word == "luego" or word == "e" or word == "então"
          or word == "et" or word == "puis" or word == "und"
          or word == "dann" then
        return false
      end
    end
    return true
  end
  local function output_precedes_record_with_particles(gap, record_before_output,
      particles)
    if record_before_output then return false end
    local rest = gap:gsub("%s+", "")
    for _, particle in ipairs(particles) do
      while true do
        local start_pos, end_pos = rest:find(particle, 1, true)
        if not start_pos then break end
        rest = rest:sub(1, start_pos - 1) .. rest:sub(end_pos + 1)
      end
    end
    return rest == ""
  end
  local function line_explicitly_records_output(line)
    if terms_match_gap(line, "%f[%a]record%a*%f[^%a]",
        "%f[%a]output%a*%f[^%a]", false,
        english_gap_is_direct_object) then
      return true
    end
    local localized_pairs = {
      { "graba", "salida" },
      { "grava", "saída" },
      { "grava", "saÍda" },
      { "grava", "saida" },
      { "enregistr", "sortie" },
      { "aufnehm", "ausgang" },
      { "aufnahme", "ausgang" },
    }
    for _, pair in ipairs(localized_pairs) do
      if terms_match_gap(line, pair[1], pair[2], true,
          latin_gap_has_no_clause_connector) then
        return true
      end
    end
    if terms_match_gap(line, "録音", "出力", true,
        function(gap, record_before_output)
          return output_precedes_record_with_particles(gap,
            record_before_output, { "を", "の" })
        end) then
      return true
    end
    if terms_match_gap(line, "녹음", "출력", true,
        function(gap, record_before_output)
          return output_precedes_record_with_particles(gap,
            record_before_output, { "을", "를", "의" })
        end) then
      return true
    end
    -- Chinese word order varies across short requests. Keep this as a bounded
    -- proximity check until native-language fixtures define a safer grammar.
    if terms_are_near(line, "录音", "输出", true)
        or terms_are_near(line, "錄音", "輸出", true) then
      return true
    end
    return false
  end
  local explicitly_records_output = false
  for line in (request_lower .. "\n"):gmatch("(.-)\r?\n") do
    if line_explicitly_records_output(line) then
      explicitly_records_output = true
      break
    end
  end
  local explicitly_requests_midi_mode =
    request_lower:find("%f[%w]overdub%f[%W]")
      or request_lower:find(
        "%f[%w]replace%f[%W]%s+%f[%w]mode%f[%W]")
      or request_lower:find(
        "%f[%w]replace%f[%W]%s+%f[%w]record%a*%f[^%a]")
  if not explicitly_requests_midi_mode then
    for _, term in ipairs({
      "sobregrab", "sobregrav", "superposition",
      "オーバーダブ", "重ね録り", "置き換え録音",
      "叠录", "疊錄", "오버더빙", "대체 녹음",
    }) do
      if request_lower:find(term, 1, true) then
        explicitly_requests_midi_mode = true
        break
      end
    end
  end
  if not explicitly_requests_midi_mode then
    for line in (request_lower .. "\n"):gmatch("(.-)\r?\n") do
      if terms_are_near(line, "%f[%w]midi%f[%W]",
          "%f[%w]replace%f[%W]", false)
          or terms_are_near(line, "record mode",
            "%f[%w]replace%f[%W]", false) then
        explicitly_requests_midi_mode = true
        break
      end
    end
  end
  local output_modes = {
    [1] = "stereo output",
    [3] = "stereo output with latency compensation",
    [4] = "MIDI output",
    [5] = "mono output",
    [6] = "mono output with latency compensation",
  }
  local findings = {}
  for _, call in ipairs(calls) do
    if call.parm == "I_RECMODE" then
      local value = resolve_number(call.value_expr)
      local label = value and output_modes[value] or nil
      local comment_support = adjacent_comment_supports_midi(call.line)
      local target_support = midi_input_targets[call.target] == true
      if label
          and not (explicitly_records_output and not explicitly_requests_midi_mode)
          and (request_has_midi or target_support or comment_support) then
        findings[#findings + 1] = {
          kind = "midi_record_mode_output_value",
          line = call.line,
          mode = value,
          mode_label = label,
          target = call.target,
          request_midi = request_has_midi,
          target_midi_input = target_support,
          adjacent_comment = comment_support,
          source = tostring(raw_lines[call.line] or ""):match("^%s*(.-)%s*$"),
        }
      end
    end
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
    "%f[%w]create%s+a%s+new%s+track%f[%W]",
    "%f[%w]creates%s+a%s+new%s+track%f[%W]",
    "%f[%w]create%s+new%s+track%f[%W]",
    "%f[%w]creates%s+new%s+track%f[%W]",
    "%f[%w]create%s+a%s+track%f[%W]",
    "%f[%w]creates%s+a%s+track%f[%W]",
    "%f[%w]create%s+track%s+named%f[%W]",
    "%f[%w]creates%s+track%s+named%f[%W]",
    "%f[%w]create%s+tracks%s+named%f[%W]",
    "%f[%w]creates%s+tracks%s+named%f[%W]",
    "%f[%w]insert%s+a%s+track%f[%W]",
    "%f[%w]insert%s+a%s+new%s+track%f[%W]",
    "%f[%w]insert%s+tracks%s+named%f[%W]",
    "%f[%w]add%s+a%s+track%f[%W]",
    "%f[%w]add%s+a%s+new%s+track%f[%W]",
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

-- Shared vocabulary for the two narrow validators that still need to
-- distinguish a requested effect family from an unrelated plug-in choice.
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
  multiband_compressor = {
    "multiband", "multi%-band",
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
    "%f[%w]loudness%f[%W]", "maximiz",
  },
  deesser = {
    "de%-esser", "de%s+esser", "%f[%w]deesser%f[%W]",
  },
  saturation = {
    "saturat", "%f[%w]exciter%f[%W]", "%f[%w]distort",
    "%f[%w]drive%f[%W]",
  },
  chorus = {
    "%f[%w]chorus%f[%W]",
  },
  phaser = {
    "%f[%w]phaser%f[%W]",
  },
  pitch_shift = {
    "pitch%s+shift",
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

Code.MANUAL_ONLY_PLUGIN_POLICIES = {
  melodyne = {
    key = "melodyne",
    display_name = "Melodyne",
    vendor = "Celemony",
  },
}

-- Some plug-ins cannot be automated safely through ordinary TrackFX or TakeFX
-- calls even when their host-exposed parameters appear simple. Match these
-- products independently of the installed format so VST3 and Audio Unit names
-- receive the same policy.
function Code.manual_only_plugin_policy(value)
  local text = tostring(value or ""):lower()
  if text:find("%f[%w]melodyne%f[%W]") then
    return Code.MANUAL_ONLY_PLUGIN_POLICIES.melodyne
  end
  return nil
end

-- Treat a protected product mention as targeted unless it is a narrow,
-- declarative project-state observation. This keeps the safety policy closed
-- for new action wording while allowing an unrelated edit in another clause.
function Code.prompt_targets_manual_only_plugin(user_text)
  local text = tostring(user_text or ""):lower():gsub("%s+", " ")
  if not Code.manual_only_plugin_policy(text) then return nil end
  text = text:gsub("%s+and%s+", "\n")
    :gsub("%s+then%s+", "\n")
    :gsub("%s+but%s+", "\n")
  local clauses = {}
  for clause in text:gmatch("[^,;%.%!%?\n]+") do
    clauses[#clauses+1] = clause
  end
  for index, clause in ipairs(clauses) do
    local policy = Code.manual_only_plugin_policy(clause)
    if policy then
      local state = clause:match("^%s*melodyne%s+is%s+([%w%-]+)")
      local observation = clause:find("^%s*i%s+have%s+.-%f[%w]melodyne%f[%W]")
        or clause:find("^%s*there%s+is%s+.-%f[%w]melodyne%f[%W]")
        or state == "open" or state == "on"
        or state == "inserted" or state == "loaded"
      if not observation then return policy end
      local other_effect_target = false
      for later = index + 1, #clauses do
        local next_clause = tostring(clauses[later] or "")
        if next_clause:find("%f[%w]it%f[%W]")
            or next_clause:find("%f[%w]that%f[%W]")
            or next_clause:find("%f[%w]this%f[%W]")
            or next_clause:find("%f[%w]the%s+plug%-in%f[%W]")
            or next_clause:find("%f[%w]pitch%f[%W]")
            or next_clause:find("%f[%w]tun")
            or next_clause:find("%f[%w]formant%f[%W]")
            or next_clause:find("%f[%w]note%f[%W]")
            or next_clause:find("%f[%w]phrase%f[%W]") then
          return policy
        end
        for family in pairs(Code.PLUGIN_FAMILY_INTENT_PATTERNS or {}) do
          if Code.prompt_expresses_plugin_family_intent(next_clause, family) then
            other_effect_target = true
            break
          end
        end
        if not other_effect_target
            and type(CTX) == "table"
            and type(CTX.explicit_plugin_profile_matches) == "function" then
          for _, matched in pairs(
              CTX.explicit_plugin_profile_matches(next_clause) or {}) do
            if matched then
              other_effect_target = true
              break
            end
          end
        end
      end
      if not other_effect_target then return policy end
    end
  end
  return nil
end

function Code.manual_only_plugin_guidance(policy)
  policy = policy or Code.MANUAL_ONLY_PLUGIN_POLICIES.melodyne
  return "MELODYNE MANUAL-ONLY POLICY (VST3 AND AUDIO UNIT):\n"
    .. "ReaAssist may inspect current host-visible values and open an existing "
    .. "Melodyne window. It must not add, delete, move, copy, bypass, take "
    .. "offline, select presets for, or write parameters to Melodyne through "
    .. "ReaScript. Use this short response order:\n"
    .. "1. Start with: I did not make any project changes.\n"
    .. "2. State that Melodyne is manual-only in ReaAssist for both VST3 and "
    .. "Audio Unit (AU).\n"
    .. "3. If Melodyne is missing, say: Insert the installed VST3 or Audio Unit "
    .. "(AU) version manually as the first Track FX through REAPER's ARA "
    .. "workflow.\n"
    .. "4. Tell the user to open the Melodyne editor and perform the requested "
    .. "edit there. Name a control only when its identity is verified in the "
    .. "available context.\n"
    .. "Do not claim that only one plug-in format supports ARA. Never substitute "
    .. "ReaPitch, ReaTune, or another effect."
end

function Code.find_manual_only_plugin_operations(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local stripped = lua_code:gsub("%-%-%[%[.-%]%]", "")
    :gsub("%-%-[^\n]*", "")
  local prompt_policy = Code.prompt_targets_manual_only_plugin(user_text)
  local code_policy = Code.manual_only_plugin_policy(stripped)
  local policy = prompt_policy or code_policy
  if not policy then return nil end

  local findings = {}
  local function add(api, pos, reason)
    findings[#findings + 1] = {
      api = api,
      line = Code._lua_line_for_pos and Code._lua_line_for_pos(stripped, pos)
        or 1,
      reason = reason,
      policy_key = policy.key,
    }
  end
  local pos = 1
  while true do
    local first, last, family, operation = stripped:find(
      "reaper%.([%a]+FX)_([%a_][%w_]*)%s*%(", pos)
    if not first then break end
    local api = family .. "_" .. operation
    local disallowed = (family == "TrackFX" or family == "TakeFX")
      and (operation == "AddByName"
      or operation == "Delete"
      or operation == "CopyToTrack"
      or operation == "CopyToTake"
      or operation == "NavigatePresets"
      or (operation:find("^Set") ~= nil and operation ~= "SetOpen"))
    if disallowed then add(api, first, "manual_only_plugin_mutation") end
    pos = math.max(last + 1, first + 1)
  end

  if prompt_policy and Code.lua_has_fx_param_writes
      and Code.lua_has_fx_param_writes(stripped) and #findings == 0 then
    add("parameter_helper", 1, "manual_only_plugin_parameter_write")
  end
  if #findings == 0 then return nil end
  return findings
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
        _mask_partial_fx_constraint(
          "%f[%w]" .. lead .. "%s+" .. qualifier
            .. "%s+[^%.;\n]-[,/]%s*" .. obj .. "%f[%W]")
        _mask_partial_fx_constraint(
          "%f[%w]" .. lead .. "%s+" .. qualifier
            .. "%s+[^%.;\n]-%s+or%s+" .. obj .. "%f[%W]")
        _mask_partial_fx_constraint(
          "%f[%w]" .. lead .. "%s+" .. qualifier
            .. "%s+[^%.;\n]-%s+and%s+" .. obj .. "%f[%W]")
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
  if type(Code.manual_only_plugin_policy) == "function"
      and Code.prompt_targets_manual_only_plugin(user_text) then
    return false
  end
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
    "align", "apply", "lower", "raise",
  }
  local object_words = {
    "track", "tracks", "fx", "plugin", "effect", "eq", "compressor", "reverb",
    "delay", "limiter", "vocal", "vocals", "pitch correction", "timing",
    "level", "levels", "loudness", "lufs", "bus", "send", "marker", "region", "midi", "item",
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
        index_aliases = {},
      }
    end
    if active_loop then
      local alias, source = line:match(
        "^%s*local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*[%+%-]%s*%d+")
      if not alias then
        alias, source = line:match(
          "^%s*local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*$")
      end
      if alias and source == active_loop.var then
        active_loop.index_aliases[alias] = true
      end
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
      if insert_var and active_loop and not active_loop.counted_insert
          and active_loop.first and active_loop.last
          and (known_count ~= nil
            or active_loop.index_aliases[insert_var]) then
        track_count = track_count
          + math.abs(active_loop.last - active_loop.first) + 1
        active_loop.counted_insert = true
        if known_count ~= nil then counttracks_append_vars[insert_var] = true end
        handled_insert = true
      elseif known_count then
        track_count = math.max(track_count, known_count + 1)
        counttracks_append_vars[insert_var] = true
        handled_insert = true
      end
    end
    if not handled_insert then
      local table_var, op, offset = line:match(
        "reaper%.InsertTrackAtIndex%s*%(%s*#([%a_][%w_]*)%s*([%+%-])%s*(%d+)%s*,")
      local table_len = table_var and table_lengths[table_var]
      if table_len and op and offset then
        track_count = track_count + 1
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
    for table_var, op, offset in line:gmatch(
        "reaper%.GetTrack%s*%(%s*0%s*,%s*#([%a_][%w_]*)%s*([%+%-])%s*(%d+)%s*%)") do
      local table_len = table_lengths[table_var]
      local delta = tonumber(offset)
      local api_idx = table_len and delta
        and (op == "+" and (table_len + delta) or (table_len - delta))
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

function Code.lua_has_fx_param_value_writes(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return false end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  return stripped:find("reaper%.TrackFX_SetParam%s*%(") ~= nil
    or stripped:find("reaper%.TrackFX_SetParamNormalized%s*%(") ~= nil
    or stripped:find("reaper%.TakeFX_SetParam%s*%(") ~= nil
    or stripped:find("reaper%.TakeFX_SetParamNormalized%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_display%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_enum%s*%(") ~= nil
    or stripped:find("%f[%w]set_param_enum_paced%s*%(") ~= nil
end

function Code.lua_has_fx_named_config_value_write(lua_code)
  if type(lua_code) ~= "string" or lua_code == "" then return false end
  local code_only = _lua_code_only_preserving_offsets(lua_code)
  for _, api_name in ipairs({
    "TrackFX_SetNamedConfigParm", "TakeFX_SetNamedConfigParm",
  }) do
    local search_pos = 1
    while true do
      local _, open_pos = code_only:find(
        "reaper%." .. api_name .. "%s*%(", search_pos)
      if not open_pos then break end
      local inner, close_pos = Code._lua_call_inner(lua_code, open_pos)
      if inner and (inner:find('\"param%.%d+%.value\"')
          or inner:find("'param%.%d+%.value'")) then
        return true
      end
      search_pos = (close_pos or open_pos) + 1
    end
  end
  return false
end

function Code.lua_has_fx_param_writes(lua_code)
  if Code.lua_has_fx_param_value_writes(lua_code)
      or Code.lua_has_fx_named_config_value_write(lua_code) then
    return true
  end
  if type(lua_code) ~= "string" or lua_code == "" then return false end
  local stripped = _lua_code_only_preserving_offsets(lua_code)
  return stripped:find("reaper%.TrackFX_SetPreset%s*%(") ~= nil
    or stripped:find("reaper%.TakeFX_SetPreset%s*%(") ~= nil
end

function Code.find_omitted_fx_param_write(lua_code, user_text)
  if type(lua_code) ~= "string" or lua_code == "" then return nil end
  local code_only = _lua_code_only_preserving_offsets(lua_code)
  local add_pos = code_only:find("reaper%.TrackFX_AddByName%s*%(")
    or code_only:find("reaper%.TakeFX_AddByName%s*%(")
  if not add_pos or Code.lua_has_fx_param_value_writes(lua_code)
      or Code.lua_has_fx_named_config_value_write(lua_code) then
    return nil
  end

  -- Quoted text is commonly a track name. Ignore unit-like names such as
  -- "Vocal +6 dB" when deciding whether the prompt requested a value write.
  local prompt = Code._typed_action_user_request_text(user_text)
    :gsub('"[^"\r\n]*"', " ")
  local localized = Code._localized_action_intent_text(prompt):lower()

  local function has_live_literal_property(api_name, property_name)
    local search_pos = 1
    while true do
      local _, open_pos = code_only:find(
        "reaper%." .. api_name .. "%s*%(", search_pos)
      if not open_pos then return false end
      local inner, close_pos = Code._lua_call_inner(lua_code, open_pos)
      if inner and (inner:find('"' .. property_name .. '"', 1, true)
          or inner:find("'" .. property_name .. "'", 1, true)) then
        return true
      end
      search_pos = (close_pos or open_pos) + 1
    end
  end

  -- Blank implemented host-property clauses, then evaluate the joined
  -- remainder. This keeps the effect name available to qualify a later
  -- request such as "set its Rate to 2 Hz" without joining distant words.
  local split = localized
    :gsub("[,;.!?\r\n]+", "\n")
    :gsub("%s+and%s+", "\n")
    :gsub("%s+y%s+", "\n")
    :gsub("%s+e%s+", "\n")
  local filtered_clauses = {}
  local inherited_scope = nil
  local has_preset_write = code_only:find("reaper%.TrackFX_SetPreset%s*%(")
    or code_only:find("reaper%.TakeFX_SetPreset%s*%(")
  for clause in (split .. "\n"):gmatch("(.-)\n") do
    local has_track_scope = clause:find("%f[%w]track%f[%W]") ~= nil
      or clause:find("%f[%w]master%f[%W]") ~= nil
      or clause:find("%f[%w]fader%f[%W]") ~= nil
    local has_item_scope = clause:find("%f[%w]item%f[%W]") ~= nil
      or clause:find("%f[%w]take%f[%W]") ~= nil
    local has_send_scope = clause:find("%f[%w]send%f[%W]") ~= nil
    if has_send_scope then
      inherited_scope = "send"
    elseif has_item_scope then
      inherited_scope = "item"
    elseif has_track_scope then
      inherited_scope = "track"
    end
    local has_volume_word = clause:find("%f[%w]volume%f[%W]") ~= nil
    local has_level_word = clause:find("%f[%w]level%f[%W]") ~= nil
    local has_gain_word = clause:find("%f[%w]gain%f[%W]") ~= nil
    local has_fader_word = clause:find("%f[%w]fader%f[%W]") ~= nil
    local local_level_word = has_volume_word or has_level_word
      or has_gain_word or has_fader_word
    local inherited_level_word = has_volume_word or has_fader_word
    local implemented_host_write =
      ((has_track_scope and local_level_word
          or inherited_scope == "track" and inherited_level_word)
        and has_live_literal_property("SetMediaTrackInfo_Value", "D_VOL"))
      or ((has_item_scope and local_level_word
          or inherited_scope == "item" and inherited_level_word)
        and has_live_literal_property("SetMediaItemInfo_Value", "D_VOL"))
      or ((has_send_scope and local_level_word
          or inherited_scope == "send"
            and (inherited_level_word or has_level_word))
        and has_live_literal_property("SetTrackSendInfo_Value", "D_VOL"))
      or ((has_track_scope or inherited_scope == "track")
        and clause:find("%f[%w]pan%f[%W]")
        and has_live_literal_property("SetMediaTrackInfo_Value", "D_PAN"))
      or (has_track_scope and clause:find("%f[%w]width%f[%W]")
        and has_live_literal_property("SetMediaTrackInfo_Value", "D_WIDTH"))
      or (has_preset_write
        and (clause:find("%f[%w]preset%f[%W]")
          or clause:find("%f[%w]program%f[%W]")))
    filtered_clauses[#filtered_clauses + 1] = implemented_host_write
      and string.rep(" ", #clause) or clause
  end
  local fx_prompt = table.concat(filtered_clauses, " ")

  if not Code.prompt_has_param_write_intent(fx_prompt)
     and not Code.prompt_requests_named_param_value(fx_prompt) then
    return nil
  end

  return {
    line = Code._lua_line_for_pos(code_only, add_pos),
    detail = "FX was inserted without writing every requested value",
  }
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

  local omitted_fx_param = Code.find_omitted_fx_param_write(lua_code, prompt)
  if omitted_fx_param then
    add("missing_requested_fx_param_write", omitted_fx_param.line,
      omitted_fx_param.detail, false)
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
      -- Third shape: a loop variable bound over a table of name literals, as
      -- in `for _, name in ipairs(track_names) do`. Without this the names a
      -- script gives the tracks it just created look like lookup targets.
      for tbl in lua_code:gmatch("%f[%w_]for%s+[%w_%s,]-%f[%w_]" .. escaped
          .. "%s+in%s+[%w_%.]-pairs%s*%(%s*([%a_][%w_]*)%s*%)") do
        local escaped_tbl = tbl:gsub("(%W)", "%%%1")
        for body in lua_code:gmatch(
            "%f[%w_]" .. escaped_tbl .. "%s*=%s*{(.-)}") do
          for lit in body:gmatch('"(.-)"') do
            local n = normalize_name(lit)
            if n ~= "" then pname_write_names[n] = true end
          end
          for lit in body:gmatch("'(.-)'") do
            local n = normalize_name(lit)
            if n ~= "" then pname_write_names[n] = true end
          end
        end
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
       and (receipt.validation_state == "validated"
         or receipt.validation_state == "approved_stock_pending")
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

-- Captures print() from Assistant-generated code in Debug.log without opening
-- REAPER's ReaScript console. Direct actions already report completion in the
-- ReaAssist conversation, so a console window is unwanted UI.
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

local function sandbox_api_proxy(api, overrides, label, dynamic_override)
  overrides = overrides or {}
  label = label or "api"
  local dynamic_cache = {}
  return setmetatable(overrides, {
    __index = function(_, key)
      if label == "reaper" then
        local denied = sandbox_reaper_denied_reason(key)
        if denied then
          error("reaper." .. denied
            .. " is not available in ReaAssist's generated-code sandbox", 2)
        end
      end
      if dynamic_cache[key] ~= nil then return dynamic_cache[key] end
      local value = api and api[key] or nil
      if dynamic_override then
        local wrapped = dynamic_override(key, value)
        if wrapped ~= nil then
          dynamic_cache[key] = wrapped
          return wrapped
        end
      end
      return value
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
  docs_gate = true,
  drum_marker_sync_validator = true,
  drum_quantize_validator = true,
  fx_check_validator = true,
  helper_validator = true,
  jsfx_format_validator = true,
  jsfx_validator = true,
  jsfx_wrong_artifact_validator = true,
  loop_time_map_validator = true,
  marker_pair_validator = true,
  manual_only_plugin_validator = true,
  media_item_label_validator = true,
  midi_input_validator = true,
  record_arm_property_validator = true,
  project_tempo_validator = true,
  ruler_timebase_validator = true,
  sandbox_forbidden_global = true,
  send_index_validator = true,
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
  midi_record_mode_review = true,
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
    requested_value_match_count = 0,
    requested_value_mismatch_count = 0,
    requested_value_confirmed_mismatch_count = 0,
    requested_value_quantized_match_count = 0,
    requested_value_unknown_count = 0,
    setter_rejected_target_count = 0,
    profile_guarded_target_count = 0,
  }
  local guarded_products = {}
  local function value_tolerance(entry)
    if entry.value_domain == "raw" then
      local min_value = tonumber(entry.min_value)
      local max_value = tonumber(entry.max_value)
      local range = min_value and max_value and math.abs(max_value - min_value)
        or 0
      return math.max(0.0000001, range * 0.000001)
    end
    return 0.000001
  end
  local function preset_name(value)
    if type(value) ~= "string" then return nil end
    local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return normalized ~= "" and normalized or nil
  end
  for _, entry in pairs(writes) do
    if type(entry) == "table" then
      out.target_count = out.target_count + 1
      out.write_count = out.write_count + (tonumber(entry.write_count) or 0)
      local target_changed = false
      if entry.value_domain == "preset" then
        local initial_preset = preset_name(entry.initial_preset)
        local final_preset = preset_name(entry.final_preset)
        if final_preset == nil then
          out.unknown_target_count = out.unknown_target_count + 1
        elseif initial_preset ~= final_preset then
          target_changed = true
          out.changed_target_count = out.changed_target_count + 1
        elseif entry.changed_during == true then
          out.returned_to_initial_count = out.returned_to_initial_count + 1
        else
          out.unchanged_target_count = out.unchanged_target_count + 1
        end
        local requested_preset = preset_name(entry.requested_preset)
        if requested_preset and final_preset then
          if requested_preset == final_preset then
            out.requested_value_match_count =
              out.requested_value_match_count + 1
          else
            out.requested_value_mismatch_count =
              out.requested_value_mismatch_count + 1
            out.requested_value_confirmed_mismatch_count =
              out.requested_value_confirmed_mismatch_count + 1
          end
        elseif entry.requested_preset_captured == true then
          out.requested_value_unknown_count =
            out.requested_value_unknown_count + 1
        end
      else
        local initial = tonumber(entry.initial_value)
          or tonumber(entry.initial_normalized)
        local final = tonumber(entry.final_value)
          or tonumber(entry.final_normalized)
        local tolerance = value_tolerance(entry)
        if initial == nil or final == nil then
          out.unknown_target_count = out.unknown_target_count + 1
        elseif math.abs(final - initial) > tolerance then
          target_changed = true
          out.changed_target_count = out.changed_target_count + 1
        elseif entry.changed_during == true then
          out.returned_to_initial_count = out.returned_to_initial_count + 1
        else
          out.unchanged_target_count = out.unchanged_target_count + 1
        end
        local requested = tonumber(entry.requested_value)
        if requested ~= nil and final ~= nil then
          local numeric_match = math.abs(final - requested) <= tolerance
          if numeric_match or entry.requested_display_match == true then
            out.requested_value_match_count =
              out.requested_value_match_count + 1
            if not numeric_match and entry.requested_display_match == true then
              out.requested_value_quantized_match_count =
                out.requested_value_quantized_match_count + 1
            end
          else
            out.requested_value_mismatch_count =
              out.requested_value_mismatch_count + 1
            if entry.requested_display_match == false
                or entry.setter_result == false or not target_changed then
              out.requested_value_confirmed_mismatch_count =
                out.requested_value_confirmed_mismatch_count + 1
            end
          end
        elseif entry.requested_value_captured == true then
          out.requested_value_unknown_count =
            out.requested_value_unknown_count + 1
        end
      end
      if entry.setter_result == false then
        out.setter_rejected_target_count =
          out.setter_rejected_target_count + 1
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
  if out.requested_value_confirmed_mismatch_count > 0
      or out.requested_value_unknown_count > 0 then
    if out.returned_to_initial_count == out.target_count
        and out.unknown_target_count == 0 then
      out.status = "returned_to_initial"
    else
      out.status = "partially_changed"
    end
  elseif out.changed_target_count > 0 then
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

-- Stable diagnostic key for generated source.
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


function Code.build_run_result(code_type, code, run_status, validation_status,
                               opts)
  opts = opts or {}
  local before = tonumber(opts.change_count_before)
  local after  = tonumber(opts.change_count_after)
  local attributed_delta = tonumber(opts.attributed_change_delta)
  local interval_overlapped = opts.change_interval_contaminated == true
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
  if type(opts.fx_insert_failure_evidence) == "table" then
    result.fx_insert_failure_evidence = opts.fx_insert_failure_evidence
  end
  if type(opts.protected_call_failure_evidence) == "table" then
    result.protected_call_failure_evidence = {
      failure_count = math.max(0,
        math.floor(tonumber(opts.protected_call_failure_evidence.failure_count)
          or 0)),
      pcall_count = math.max(0,
        math.floor(tonumber(opts.protected_call_failure_evidence.pcall_count)
          or 0)),
      xpcall_count = math.max(0,
        math.floor(tonumber(opts.protected_call_failure_evidence.xpcall_count)
          or 0)),
    }
  end
  if type(opts.plugin_profile_equivalence) == "table" then
    result.plugin_profile_equivalence = opts.plugin_profile_equivalence
  end
  if opts.runtime_error then
    result.runtime_error = Log.scrub_url_secrets(tostring(opts.runtime_error))
  end
  if before ~= nil and after ~= nil then
    result.change_evidence = {
      project_state_change_count_before = before,
      project_state_change_count_after = after,
      attribution = interval_overlapped
        and "interval_overlapped" or "direct",
    }
    if interval_overlapped then
      result.raw_project_state_change_delta = after - before
      if attributed_delta ~= nil then
        result.project_state_change_delta = attributed_delta
        result.observable_change_status = attributed_delta ~= 0
          and "changed" or "unchanged"
      end
    elseif after ~= before then
      result.observable_change_status = "changed"
      result.project_state_change_delta = after - before
    else
      result.observable_change_status = "unchanged"
      result.project_state_change_delta = 0
    end
    local insert_evidence = result.fx_insert_failure_evidence
    if not interval_overlapped and type(insert_evidence) == "table"
        and insert_evidence.other_project_change_detected ~= nil then
      result.raw_project_state_change_delta = after - before
      if insert_evidence.other_project_change_detected == true then
        result.observable_change_status = "changed"
      else
        result.observable_change_status = "unchanged"
        result.project_state_change_delta = 0
      end
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
    "track.create", "track.ensure", "track.resolve", "track.set",
    "track.folder", "send.create",
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
  if n("send.create") > 0 then
    return label("typed_actions.kind.routing", "Routing")
  end
  if n("track.folder") > 0 then
    return label("typed_actions.kind.folder_setup", "Folder setup")
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
  local plan = Code.typed_actions_plan_from_text(plan_text or "",
    { allow_raw_json = true })
  if not plan then return "Structured track edit" end
  local labels = {}
  for _, action in ipairs(plan.actions) do
    labels[#labels + 1] = tostring(action.op)
  end
  local suffix = type(action_results) == "table" and #action_results > 0
    and " completed" or ""
  return table.concat(labels, ", ") .. suffix
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
  msg.fx_insert_failure_evidence = rr.fx_insert_failure_evidence
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
  -- A bound deferred callback owns its message through its closure and no
  -- longer needs to monopolize the global slot. Detach it before a later
  -- manual run so its eventual completion cannot overwrite the newer run's
  -- global result; apply_completed_result still finalizes the original row.
  if type(S) == "table" and type(S.lua_defer_run) == "table"
     and S.lua_defer_run.bound then
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
      if i > 1 then buf[#buf+1] = "\t" end
      buf[#buf+1] = v
    end
    Log.line("SCRIPT", "print: " .. table.concat(buf))
  end

  -- Undo capture state. The outer wrapper (below) is the ONLY real Begin/End
  -- pair against REAPER's undo stack; the shim intercepts the generated
  -- code's own Begin/End calls so a throw between them cannot unbalance the
  -- stack. We still capture the descriptive label the code passed to
  -- Undo_EndBlock and forward it to the outer End, so REAPER's undo history
  -- reads "ReaAssist: Create 10 tracks" rather than a generic "ReaAssist".
  -- Later captures overwrite earlier ones; generated code that issues
  -- multiple Begin/End pairs collapses into one outer entry with the last
  -- non-empty label (typical generations are one logical operation).
  local inner_undo_label = nil
  local inner_undo_flags = -1
  local change_count_before = Code.project_change_count()
  local code_uses_fx_insertion = code:find("TrackFX_AddByName", 1, true)
    or code:find("TakeFX_AddByName", 1, true)
  local function project_shape_snapshot()
    local shape = {}
    local function safe_count(fn, ...)
      if type(fn) ~= "function" then return nil end
      local ok, value = pcall(fn, ...)
      if ok then return tonumber(value) end
      return nil
    end
    shape.track_count = safe_count(reaper.CountTracks, 0)
    shape.item_count = safe_count(reaper.CountMediaItems, 0)
    shape.marker_count = safe_count(reaper.CountProjectMarkers, 0)
    shape.tempo_marker_count = safe_count(
      reaper.CountTempoTimeSigMarkers, 0)
    if code_uses_fx_insertion and shape.track_count
        and type(reaper.GetTrack) == "function"
        and type(reaper.GetTrackName) == "function" then
      local identities = {}
      for index = 0, shape.track_count - 1 do
        local track = reaper.GetTrack(0, index)
        local ok, valid, name = pcall(reaper.GetTrackName, track, "")
        identities[#identities + 1] = tostring(track) .. "\31"
          .. (ok and valid and tostring(name or "") or "")
          .. "\31" .. tostring(type(reaper.TrackFX_GetCount) == "function"
            and reaper.TrackFX_GetCount(track) or "")
          .. "\31" .. tostring(type(reaper.TrackFX_GetRecCount) == "function"
            and reaper.TrackFX_GetRecCount(track) or "")
      end
      shape.track_identity = table.concat(identities, "\30")
    end
    return shape
  end
  local project_shape_before = project_shape_snapshot()
  local defer_state = {
    code = code,
    pending = 0,
    failed = false,
    in_callback = false,
    bound = false,
    message_ref = nil,
    protected_call_failures = {
      failure_count = 0,
      pcall_count = 0,
      xpcall_count = 0,
    },
    change_count_before = change_count_before,
    parameter_writes = {},
    fx_insert_failures = {},
    fx_insert_failure_order = {},
    successful_fx_insert_count = 0,
    generated_refresh_balance = 0,
    generated_refresh_recovery_count = 0,
    attributed_change_delta = 0,
    last_segment_change_delta = nil,
    change_interval_contaminated = false,
  }
  local function record_change_segment(segment_before, segment_after)
    segment_before = tonumber(segment_before)
    segment_after = tonumber(segment_after)
    if segment_before == nil or segment_after == nil then
      defer_state.last_segment_change_delta = nil
      defer_state.attributed_change_delta = nil
      return
    end
    local delta = segment_after - segment_before
    defer_state.last_segment_change_delta = delta
    if defer_state.attributed_change_delta ~= nil then
      defer_state.attributed_change_delta =
        defer_state.attributed_change_delta + delta
    end
  end
  local function record_protected_call_result(kind, ok)
    if ok ~= false then return end
    local counts = defer_state.protected_call_failures
    counts.failure_count = counts.failure_count + 1
    if kind == "xpcall" then
      counts.xpcall_count = counts.xpcall_count + 1
    else
      counts.pcall_count = counts.pcall_count + 1
    end
  end
  local function protected_call_failure_evidence()
    local counts = defer_state.protected_call_failures
    if counts.failure_count < 1 then return nil end
    return {
      failure_count = counts.failure_count,
      pcall_count = counts.pcall_count,
      xpcall_count = counts.xpcall_count,
    }
  end
  code_env.pcall = function(fn, ...)
    local result = table.pack(pcall(fn, ...))
    record_protected_call_result("pcall", result[1])
    return table.unpack(result, 1, result.n)
  end
  code_env.xpcall = function(fn, msgh, ...)
    local result = table.pack(xpcall(fn, msgh, ...))
    record_protected_call_result("xpcall", result[1])
    return table.unpack(result, 1, result.n)
  end
  local function recover_generated_refresh()
    local held = math.max(0,
      math.floor(tonumber(defer_state.generated_refresh_balance) or 0))
    for _ = 1, held do pcall(reaper.PreventUIRefresh, -1) end
    defer_state.generated_refresh_balance = 0
    defer_state.generated_refresh_recovery_count =
      defer_state.generated_refresh_recovery_count + held
    if held > 0 then
      Log.line("SCRIPT", "Recovered " .. tostring(held)
        .. " unmatched PreventUIRefresh call(s)")
    end
    return held
  end
  defer_state.record_parameter_write = function(kind, target_ref, fx, pidx,
      getter, setter, value, value_domain, formatter, formatted_getter)
    local key = tostring(kind) .. "\31" .. tostring(target_ref)
      .. "\31" .. tostring(fx) .. "\31" .. tostring(pidx)
      .. "\31" .. tostring(value_domain or "normalized")
    local entry = defer_state.parameter_writes[key]
    if not entry then
      entry = {
        write_count = 0,
        changed_during = false,
        value_domain = value_domain or "normalized",
      }
      defer_state.parameter_writes[key] = entry
      if type(getter) == "function" then
        local before = table.pack(pcall(getter, target_ref, fx, pidx))
        if before[1] then
          entry.initial_value = tonumber(before[2])
          if entry.value_domain == "raw" then
            entry.min_value = tonumber(before[3])
            entry.max_value = tonumber(before[4])
          end
          if entry.value_domain == "normalized" then
            entry.initial_normalized = entry.initial_value
          end
        end
      end
    end
    entry.requested_value_captured = true
    entry.requested_value = tonumber(value)
    -- Raw-to-normalized mappings can be nonlinear. Formatted comparison is
    -- reliable only when the generated setter itself used normalized values.
    local requested_normalized = entry.value_domain == "normalized"
      and entry.requested_value or nil
    local function formatted_text(packed)
      if not packed[1] then return nil end
      local value_text = type(packed[3]) == "string" and packed[3]
        or (type(packed[2]) == "string" and packed[2] or nil)
      if packed[2] == false or not value_text then return nil end
      value_text = value_text:lower():gsub("^%s+", ""):gsub("%s+$", "")
      return value_text ~= "" and value_text or nil
    end
    if type(formatter) == "function" and requested_normalized ~= nil then
      entry.requested_display = formatted_text(table.pack(
        pcall(formatter, target_ref, fx, pidx, requested_normalized)))
    else
      entry.requested_display = nil
    end
    local packed = table.pack(setter(target_ref, fx, pidx, value))
    entry.write_count = entry.write_count + 1
    if type(packed[1]) == "boolean" then entry.setter_result = packed[1] end
    if type(getter) == "function" then
      local after = table.pack(pcall(getter, target_ref, fx, pidx))
      if after[1] then
        entry.final_value = tonumber(after[2])
        if entry.value_domain == "raw" then
          entry.min_value = tonumber(after[3]) or entry.min_value
          entry.max_value = tonumber(after[4]) or entry.max_value
        end
        if entry.value_domain == "normalized" then
          entry.final_normalized = entry.final_value
        end
        if type(formatted_getter) == "function" then
          entry.final_display = formatted_text(table.pack(
            pcall(formatted_getter, target_ref, fx, pidx, "")))
          if entry.requested_display and entry.final_display then
            entry.requested_display_match =
              entry.requested_display == entry.final_display
          else
            entry.requested_display_match = nil
          end
        end
        local change_tolerance = entry.value_domain == "raw"
          and math.max(0.0000001,
            math.abs((entry.max_value or 0) - (entry.min_value or 0))
              * 0.000001)
          or 0.000001
        if entry.initial_value ~= nil
           and entry.final_value ~= nil
           and math.abs(entry.final_value - entry.initial_value)
              > change_tolerance then
          entry.changed_during = true
        end
      end
    end
    return table.unpack(packed, 1, packed.n)
  end

  defer_state.record_preset_write = function(kind, target_ref, fx, preset_name,
      getter, setter)
    local key = tostring(kind) .. "\31" .. tostring(target_ref)
      .. "\31" .. tostring(fx) .. "\31preset"
    local entry = defer_state.parameter_writes[key]
    if not entry then
      entry = {
        write_count = 0,
        changed_during = false,
        value_domain = "preset",
      }
      defer_state.parameter_writes[key] = entry
      if type(getter) == "function" then
        local before = table.pack(pcall(getter, target_ref, fx, ""))
        if before[1] and before[2] ~= false and type(before[3]) == "string" then
          entry.initial_preset = before[3]
        end
      end
    end
    entry.requested_preset_captured = true
    entry.requested_preset = tostring(preset_name or "")
    local packed = table.pack(setter(target_ref, fx, preset_name))
    entry.write_count = entry.write_count + 1
    if type(packed[1]) == "boolean" then entry.setter_result = packed[1] end
    if type(getter) == "function" then
      local after = table.pack(pcall(getter, target_ref, fx, ""))
      if after[1] and after[2] ~= false and type(after[3]) == "string" then
        entry.final_preset = after[3]
        if entry.initial_preset ~= nil
            and entry.final_preset ~= entry.initial_preset then
          entry.changed_during = true
        end
      end
    end
    return table.unpack(packed, 1, packed.n)
  end

  local fx_host_prefixes = {
    au = true, aui = true, auv3 = true, auv3i = true,
    clap = true, clapi = true, dx = true, dxi = true,
    js = true, lv2 = true, lv2i = true,
    vst = true, vsti = true, vst3 = true, vst3i = true,
  }
  local function normalized_fx_insert_name(name)
    local text = tostring(name or ""):match("^%s*(.-)%s*$") or ""
    local lower = text:lower()
    local prefix = lower:match("^([%w]+)%s*:%s*")
    if prefix and fx_host_prefixes[prefix] then
      lower = lower:gsub("^[%w]+%s*:%s*", "", 1)
    end
    return lower:match("^%s*(.-)%s*$") or lower, text
  end
  defer_state.record_fx_insert_result = function(kind, target_ref, name,
      instantiate, result)
    if (tonumber(instantiate) or 0) == 0 then return end
    local normalized, display_name = normalized_fx_insert_name(name)
    if normalized == "" then normalized = display_name:lower() end
    local key = tostring(kind) .. "\31" .. tostring(target_ref)
      .. "\31" .. normalized
    local entry = defer_state.fx_insert_failures[key]
    if tonumber(result) and tonumber(result) >= 0 then
      defer_state.successful_fx_insert_count =
        defer_state.successful_fx_insert_count + 1
      if entry then entry.active = false end
      return
    end
    if not (tonumber(result) and tonumber(result) < 0) then return end
    if not entry then
      entry = {
        active = true,
        display_name = display_name ~= "" and display_name or tostring(name),
        normalized_name = normalized,
      }
      defer_state.fx_insert_failures[key] = entry
      defer_state.fx_insert_failure_order[
        #defer_state.fx_insert_failure_order + 1] = key
    else
      entry.active = true
    end
  end
  defer_state.fx_insert_failure_evidence = function()
    local failed_names, seen_names = {}, {}
    local failed_target_count = 0
    for _, key in ipairs(defer_state.fx_insert_failure_order) do
      local entry = defer_state.fx_insert_failures[key]
      if entry and entry.active then
        failed_target_count = failed_target_count + 1
        if not seen_names[entry.normalized_name] then
          seen_names[entry.normalized_name] = true
          failed_names[#failed_names + 1] = entry.display_name
        end
      end
    end
    if failed_target_count == 0 then return nil end
    local shape_after = project_shape_snapshot()
    local shape_changed = false
    for key, before_value in pairs(project_shape_before) do
      if before_value ~= nil and shape_after[key] ~= nil
          and shape_after[key] ~= before_value then
        shape_changed = true
        break
      end
    end
    local parameter_evidence =
      Code.parameter_change_evidence(defer_state.parameter_writes)
    local parameter_changed = parameter_evidence
      and (parameter_evidence.status == "changed"
        or parameter_evidence.status == "partially_changed") or false
    return {
      failure_count = failed_target_count,
      failed_target_count = failed_target_count,
      failed_name_count = #failed_names,
      failed_names = failed_names,
      other_project_change_detected =
        (not defer_state.change_interval_contaminated and shape_changed)
        or parameter_changed
        or defer_state.successful_fx_insert_count > 0,
    }
  end

  defer_state.apply_completed_result = function()
    local rr = defer_state.completed_result
    if type(rr) ~= "table" then return end
    local msg = defer_state.message_ref
    if type(msg) ~= "table" then
      msg = defer_state.message_idx
        and type(S.display_messages) == "table"
        and S.display_messages[defer_state.message_idx] or nil
    end
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
       and defer_state.bound then
      S.lua_defer_run = nil
    end
  end

  defer_state.bind = function(message_idx, history_idx, auto_ran, probe_turn)
    defer_state.message_idx = message_idx
    defer_state.message_ref = type(S.display_messages) == "table"
      and S.display_messages[message_idx] or nil
    defer_state.bound = true
    defer_state.history_idx = history_idx
    defer_state.auto_ran = auto_ran == true
    defer_state.probe_turn = probe_turn
    defer_state.apply_completed_result()
  end

  local function record_runtime_error(run_err, instruction_timeout,
      instruction_count, source, failure_kind)
    local err_str, short, user_msg =
      lua_runtime_error_strings(run_err, instruction_timeout)
    local change_count_after = Code.project_change_count()
    local error_fx_insert_evidence =
      defer_state.fx_insert_failure_evidence()
    local detached = defer_state.bound
      and (type(S) ~= "table" or S.lua_defer_run ~= defer_state)
    local project_changed = error_fx_insert_evidence
      and error_fx_insert_evidence.other_project_change_detected == true
      or (not error_fx_insert_evidence
        and change_count_after ~= change_count_before)
    local callback_delta = tonumber(defer_state.last_segment_change_delta)
    if detached and callback_delta == nil then
      user_msg = user_msg
        .. "\n\nReaAssist could not measure whether this action changed the "
        .. "project. Check the project before using Undo, then ask ReaAssist "
        .. "to fix and retry it."
    elseif detached and callback_delta ~= 0 then
      user_msg = user_msg
        .. "\n\nThis older action changed the project before it failed, and "
        .. "a newer action has run since. Use Undo now if you do not want to "
        .. "keep the older action's partial work, then ask ReaAssist to fix "
        .. "and retry it."
    elseif detached then
      user_msg = user_msg
        .. "\n\nThis older action failed without changing the project, and "
        .. "a newer action has run since. Do not use Undo. Ask ReaAssist to "
        .. "fix and retry that action."
    elseif project_changed then
      user_msg = user_msg
        .. "\n\nThe project changed before the error, so the result may be "
        .. "partial. Use Undo if you do not want to keep it, then ask "
        .. "ReaAssist to fix and retry the last action."
    else
      user_msg = user_msg
        .. "\n\nNo project change was detected. Ask ReaAssist to fix and "
        .. "retry the last action."
    end
    local err_debug = {
      failure_kind = failure_kind or (instruction_timeout
        and "lua_instruction_budget_exceeded" or "runtime_error"),
      source = source or "generated_lua_runtime",
      runtime_error = Log.scrub_url_secrets(err_str),
      stack_excerpt = Log.scrub_url_secrets(short),
      instruction_budget = instruction_timeout
        and CODE_RUN_INSTRUCTION_BUDGET or nil,
      instruction_count = instruction_count,
      generated_code_bytes = type(code) == "string" and #code or 0,
      project_state_change_count_before = change_count_before,
      project_state_change_count_after = change_count_after,
      protected_call_failure_evidence =
        failure_kind == "protected_call_failure"
          and protected_call_failure_evidence() or nil,
    }
    Log.line("SCRIPT", "Runtime error: " .. err_str:gsub("\n", " \\n "))
    Diag.add_error(err_str, nil, code)
    Log.add_error(user_msg, nil, nil, nil,
      { error_kind = "runtime_error", error_debug = err_debug })
    local runtime_error = "runtime error: " .. Log.scrub_url_secrets(short)
    local owns_global_result = type(S) == "table"
      and ((S.lua_defer_run == nil and not defer_state.bound)
        or S.lua_defer_run == defer_state)
    if owns_global_result then S.last_run_error = runtime_error end
    local error_result = Code.build_run_result("lua", code,
      "errored", "failed", {
        change_count_before = change_count_before,
        change_count_after = change_count_after,
        attributed_change_delta = defer_state.attributed_change_delta,
        change_interval_contaminated =
          defer_state.change_interval_contaminated,
        parameter_change_evidence =
          Code.parameter_change_evidence(defer_state.parameter_writes),
        fx_insert_failure_evidence = error_fx_insert_evidence,
        generated_refresh_recovered =
          defer_state.generated_refresh_recovery_count > 0,
        generated_refresh_recovery_count =
          defer_state.generated_refresh_recovery_count,
        error_kind = "runtime_error",
        error_debug = err_debug,
        protected_call_failure_evidence =
          failure_kind == "protected_call_failure"
            and protected_call_failure_evidence() or nil,
        runtime_error = runtime_error,
      })
    defer_state.error_result = error_result
    if owns_global_result then S.last_run_result = error_result end
  end

  local function finish_deferred_lua_run()
    if defer_state.pending > 0 then return end
    local parameter_evidence =
      Code.parameter_change_evidence(defer_state.parameter_writes)
    local fx_insert_failure_evidence =
      defer_state.fx_insert_failure_evidence()
    local completed_result
    if not defer_state.failed then
      local change_count_after = Code.project_change_count()
      completed_result = Code.build_run_result("lua", code,
        "ran_ok", "passed", {
          change_count_before = change_count_before,
          change_count_after = change_count_after,
          attributed_change_delta = defer_state.attributed_change_delta,
          change_interval_contaminated =
            defer_state.change_interval_contaminated,
          parameter_change_evidence = parameter_evidence,
          fx_insert_failure_evidence = fx_insert_failure_evidence,
          deferred = true,
          deferred_pending = false,
          generated_refresh_recovered =
            defer_state.generated_refresh_recovery_count > 0,
          generated_refresh_recovery_count =
            defer_state.generated_refresh_recovery_count,
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
      completed_result.fx_insert_failure_evidence =
        completed_result.fx_insert_failure_evidence
        or fx_insert_failure_evidence
    end
    if type(completed_result) == "table" then
      defer_state.completed_result = completed_result
      if type(S) == "table" and S.lua_defer_run == defer_state then
        S.last_run_result = completed_result
      end
      defer_state.apply_completed_result()
    end
  end

  -- Wrap `reaper` so user-facing calls (dialogs, console output) are logged
  -- when debug logging is enabled. Every other allowed reaper.* call falls
  -- through to the real API via __index; denied APIs are blocked even when the
  -- code aliases `reaper` or builds a function name dynamically.
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
        if defer_state.bound
            and (type(S) ~= "table" or S.lua_defer_run ~= defer_state) then
          defer_state.change_interval_contaminated = true
        end
        if defer_state.failed then
          defer_state.pending = math.max(0, defer_state.pending - 1)
          if type(S) == "table"
              and (S.lua_defer_run == defer_state
                or defer_state.bound) then
            finish_deferred_lua_run()
          end
          return
        end
        local callback_undo_label = inner_undo_label
        local callback_undo_flags = inner_undo_flags
        inner_undo_label = nil
        inner_undo_flags = -1
        reaper.Undo_BeginBlock()
        local callback_change_count_before = Code.project_change_count()
        defer_state.in_callback = true
        local protected_failures_before =
          defer_state.protected_call_failures.failure_count
        local ok, run_err, instruction_timeout, instruction_count =
          run_lua_chunk_with_instruction_guard(fn)
        defer_state.in_callback = false
        recover_generated_refresh()
        local undo_label = inner_undo_label or callback_undo_label
          or "ReaAssist"
        local undo_flags = inner_undo_label and inner_undo_flags
          or callback_undo_flags or -1
        reaper.Undo_EndBlock(undo_label, undo_flags)
        local callback_change_count_after = Code.project_change_count()
        record_change_segment(callback_change_count_before,
          callback_change_count_after)
        if not ok then
          defer_state.failed = true
          record_runtime_error(run_err, instruction_timeout, instruction_count,
            "generated_lua_defer_callback")
        elseif defer_state.protected_call_failures.failure_count
            > protected_failures_before then
          defer_state.failed = true
          record_runtime_error(
            "Generated Lua caught a failed pcall or xpcall without stopping.",
            false, nil, "generated_lua_defer_callback",
            "protected_call_failure")
        end
        defer_state.pending = math.max(0, defer_state.pending - 1)
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
      Log.line("SCRIPT", "ShowConsoleMsg suppressed: "
        .. tostring(msg):gsub("\n$", ""):gsub("\n", " \\n "))
      return nil
    end,
    ClearConsole = function()
      Log.line("SCRIPT", "ClearConsole suppressed")
      return nil
    end,
    PreventUIRefresh = function(direction)
      local value = tonumber(direction) or 0
      if value > 0 then
        defer_state.generated_refresh_balance =
          defer_state.generated_refresh_balance + value
        return reaper.PreventUIRefresh(direction)
      end
      if value < 0 then
        if defer_state.generated_refresh_balance <= 0 then return 0 end
        defer_state.generated_refresh_balance = math.max(0,
          defer_state.generated_refresh_balance + value)
        return reaper.PreventUIRefresh(direction)
      end
      return reaper.PreventUIRefresh(direction)
    end,
    TrackFX_AddByName = function(tr, name, rec_fx, instantiate)
      local packed = table.pack(
        reaper.TrackFX_AddByName(tr, name, rec_fx, instantiate))
      defer_state.record_fx_insert_result(
        "track:" .. tostring(rec_fx == true), tr, name, instantiate,
        packed[1])
      return table.unpack(packed, 1, packed.n)
    end,
    TakeFX_AddByName = function(take, name, instantiate)
      local packed = table.pack(
        reaper.TakeFX_AddByName(take, name, instantiate))
      defer_state.record_fx_insert_result(
        "take", take, name, instantiate, packed[1])
      return table.unpack(packed, 1, packed.n)
    end,
    TrackFX_SetParamNormalized = function(tr, fx, pidx, value)
      return defer_state.record_parameter_write("track", tr, fx, pidx,
        reaper.TrackFX_GetParamNormalized,
        reaper.TrackFX_SetParamNormalized, value, "normalized",
        reaper.TrackFX_FormatParamValueNormalized,
        reaper.TrackFX_GetFormattedParamValue)
    end,
    TrackFX_SetParam = function(tr, fx, pidx, value)
      return defer_state.record_parameter_write("track", tr, fx, pidx,
        reaper.TrackFX_GetParam, reaper.TrackFX_SetParam, value, "raw",
        reaper.TrackFX_FormatParamValueNormalized,
        reaper.TrackFX_GetFormattedParamValue)
    end,
    TakeFX_SetParamNormalized = function(take, fx, pidx, value)
      return defer_state.record_parameter_write("take", take, fx, pidx,
        reaper.TakeFX_GetParamNormalized,
        reaper.TakeFX_SetParamNormalized, value, "normalized",
        reaper.TakeFX_FormatParamValueNormalized,
        reaper.TakeFX_GetFormattedParamValue)
    end,
    TakeFX_SetParam = function(take, fx, pidx, value)
      return defer_state.record_parameter_write("take", take, fx, pidx,
        reaper.TakeFX_GetParam, reaper.TakeFX_SetParam, value, "raw",
        reaper.TakeFX_FormatParamValueNormalized,
        reaper.TakeFX_GetFormattedParamValue)
    end,
    TrackFX_SetPreset = function(tr, fx, preset_name)
      return defer_state.record_preset_write("track", tr, fx, preset_name,
        reaper.TrackFX_GetPreset, reaper.TrackFX_SetPreset)
    end,
    TakeFX_SetPreset = function(take, fx, preset_name)
      return defer_state.record_preset_write("take", take, fx, preset_name,
        reaper.TakeFX_GetPreset, reaper.TakeFX_SetPreset)
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
      .. "\n\nThe script did not run, so no project change was made. Ask "
      .. "ReaAssist to fix and retry the last action."
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
      fx_insert_failure_evidence =
        defer_state.fx_insert_failure_evidence(),
      runtime_error = S.last_run_error,
      })
    return false
  end

  -- Plugin-level undo wrapper. The generated code's own Undo_Begin/EndBlock
  -- calls are intercepted by reaper_shim above (no-op + label capture), so
  -- this pair is the ONLY real interaction with REAPER's undo stack and a
  -- throw anywhere inside fn() cannot leave the stack unbalanced. The label
  -- the inner code passed to Undo_EndBlock ("ReaAssist: Create 10 tracks"
  -- etc.) is surfaced in REAPER's undo history via inner_undo_label.
  reaper.Undo_BeginBlock()
  local ok, run_err, instruction_timeout, instruction_count =
    run_lua_chunk_with_instruction_guard(fn)
  local protected_failed =
    defer_state.protected_call_failures.failure_count > 0
  if defer_state.pending == 0 or not ok or protected_failed then
    recover_generated_refresh()
  end
  reaper.Undo_EndBlock(inner_undo_label or "ReaAssist", inner_undo_flags)
  local change_count_after = Code.project_change_count()
  record_change_segment(change_count_before, change_count_after)
  if not ok then
    defer_state.failed = true
    record_runtime_error(run_err, instruction_timeout, instruction_count,
      "generated_lua_runtime")
    return false
  end
  if protected_failed then
    defer_state.failed = true
    record_runtime_error(
      "Generated Lua caught a failed pcall or xpcall without stopping.",
      false, nil, "generated_lua_runtime", "protected_call_failure")
    reaper.UpdateArrange()
    return false
  end
  Log.line("SCRIPT", "Script completed OK")
  reaper.UpdateArrange()
  if defer_state.pending > 0 then
    S.lua_defer_run = defer_state
    S.last_run_result = Code.build_run_result("lua", code,
      "pending", "pending", {
        deferred = true,
        deferred_pending = true,
        generated_refresh_recovered =
          defer_state.generated_refresh_recovery_count > 0,
        generated_refresh_recovery_count =
          defer_state.generated_refresh_recovery_count,
        fx_insert_failure_evidence =
          defer_state.fx_insert_failure_evidence(),
      })
    return true, "pending"
  end
  S.last_run_result = Code.build_run_result("lua", code,
    "ran_ok", "passed", {
      change_count_before = change_count_before,
      change_count_after = change_count_after,
      parameter_change_evidence =
        Code.parameter_change_evidence(defer_state.parameter_writes),
      fx_insert_failure_evidence =
        defer_state.fx_insert_failure_evidence(),
      generated_refresh_recovered =
        defer_state.generated_refresh_recovery_count > 0,
      generated_refresh_recovery_count =
        defer_state.generated_refresh_recovery_count,
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
