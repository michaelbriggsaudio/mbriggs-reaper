-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- Maintained shared Lua kit. Each component has its own function scope.
-- Loading with the "kit" argument returns installer modules without initializing a client.
local EngineKit = {}

EngineKit.Contract = (function()
-- BEGIN ENGINE COMPONENT Contract
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- =============================================================================
-- Shared additive Engine contract admission
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
-- =============================================================================

local Contract = {}

function Contract.positive_integer(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value)
    and value >= minimum and value <= maximum
end

function Contract.strict_token_set(value)
  if type(value) ~= "table" then return nil end
  local out, count = {}, 0
  for index, token in ipairs(value) do
    if type(token) ~= "string" or token == ""
        or token:match("^[a-z0-9_]+$") == nil or out[token] then
      return nil
    end
    out[token] = true
    count = index
  end
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > count then
      return nil
    end
  end
  return out, count
end

function Contract.required_token_list(value, expected)
  local actual = Contract.strict_token_set(value)
  if not actual then return false end
  for _, token in ipairs(expected or {}) do
    if actual[token] ~= true then return false end
  end
  return true
end

function Contract.required_export_list(value, expected)
  if type(value) ~= "table" then return false end
  local actual, count = {}, 0
  for index, name in ipairs(value) do
    if type(name) ~= "string" or name:match("^MBH_[A-Za-z0-9_]+$") == nil
        or actual[name] then
      return false
    end
    actual[name] = true
    count = index
  end
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > count then
      return false
    end
  end
  for _, name in ipairs(expected or {}) do
    if actual[name] ~= true then return false end
  end
  return actual
end

-- Returns a validated view or nil, reason_code, optional_detail. Consumers add
-- their own presentation wording and any subsystem-specific optional checks.
function Contract.validate(value, raw, options)
  local opts = options or {}
  local positive_integer = Contract.positive_integer
  if type(value) ~= "table" or value.schema ~= 1 then
    return nil, "schema"
  end
  if type(value.engine_version) ~= "string" or value.engine_version == ""
      or value.engine_version ~= opts.bootstrap_version then
    return nil, "version"
  end
  -- The ABI is pinned exactly. Growth inside one ABI is additive and is what
  -- the schema below tolerates; a different ABI number is a different seam and
  -- the release package admits exactly one.
  if value.core_abi ~= opts.required_abi
      or value.core_abi ~= opts.bootstrap_abi then
    return nil, "ABI"
  end
  if value.build_channel ~= "production" then
    return nil, "build_channel"
  end
  if type(value.subsystems) ~= "table" then
    return nil, "subsystems"
  end

  local required_subsystems = opts.required_subsystems or {}
  for name, minimum in pairs(required_subsystems) do
    if not positive_integer(value.subsystems[name], minimum, 1000) then
      return nil, "subsystem", name
    end
  end

  local declared_exports = Contract.required_export_list(value.exports,
    opts.required_exports)
  if not declared_exports then return nil, "exports" end
  for _, name in ipairs(opts.forbidden_exports or {}) do
    if declared_exports[name] then
      return nil, "forbidden_export", name
    end
  end

  if not Contract.required_token_list(value.status_vocabulary,
      opts.required_status_vocabulary) then
    return nil, "status_vocabulary"
  end
  if not Contract.required_token_list(value.error_vocabulary,
      opts.required_error_vocabulary) then
    return nil, "error_vocabulary"
  end

  local protocols = Contract.strict_token_set(value.protocols)
  if not protocols then return nil, "protocols" end
  local profiles = {}
  local profile_revision = opts.profile_required_revision or 2
  if value.inference_profiles ~= nil then
    profiles = Contract.strict_token_set(value.inference_profiles)
    if not profiles then return nil, "inference_profiles" end
  elseif value.subsystems.inference >= profile_revision then
    return nil, "inference_profiles"
  end
  if value.subsystems.inference < profile_revision and next(profiles) ~= nil then
    return nil, "inference_profile_revision"
  end
  for profile_id, protocol in pairs(opts.profile_protocols or {}) do
    if profiles[profile_id] == true and protocols[protocol] ~= true then
      return nil, "inference_profile_protocol", profile_id
    end
  end

  local limits = value.limits
  if type(limits) ~= "table" then return nil, "limits" end
  if not positive_integer(limits.contract_bytes, #raw,
      opts.contract_buffer_bytes) then
    return nil, "limit", "contract_bytes"
  end
  if not positive_integer(limits.client_result_buffer_bytes, 1024,
      opts.max_result_buffer_bytes) then
    return nil, "limit", "client_result_buffer_bytes"
  end
  if not positive_integer(limits.inference_result_buffer_bytes, 1024,
      opts.max_result_buffer_bytes) then
    return nil, "limit", "inference_result_buffer_bytes"
  end
  if not positive_integer(limits.capability_bytes, 16, 64) then
    return nil, "limit", "capability_bytes"
  end
  if not positive_integer(limits.inference_event_bytes, 1,
      limits.inference_result_buffer_bytes) then
    return nil, "limit", "inference_event_bytes"
  end
  if not positive_integer(limits.request_body_bytes, 1024 * 1024,
      256 * 1024 * 1024) then
    return nil, "limit", "request_body_bytes"
  end

  if required_subsystems.input_media then
    if not positive_integer(limits.inference_image_count, 1, 1024)
        or not positive_integer(limits.inference_image_bytes, 1,
          limits.request_body_bytes)
        or not positive_integer(limits.inference_image_aggregate_bytes,
          limits.inference_image_bytes, limits.request_body_bytes)
        or not positive_integer(limits.input_media_bytes,
          limits.inference_image_bytes, limits.request_body_bytes)
        or not positive_integer(limits.input_media_per_client_count,
          limits.inference_image_count, 1024)
        or not positive_integer(limits.input_media_global_count,
          limits.input_media_per_client_count, 65536)
        or not positive_integer(limits.input_media_per_client_bytes,
          limits.inference_image_aggregate_bytes, limits.request_body_bytes)
        or not positive_integer(limits.input_media_global_bytes,
          limits.input_media_per_client_bytes, 1024 * 1024 * 1024) then
      return nil, "limit", "input_media"
    end
  end

  return {
    value = value,
    exports = declared_exports,
    protocols = protocols,
    profiles = profiles,
    limits = limits,
  }
end

return Contract
-- END ENGINE COMPONENT Contract
end)()

EngineKit.Installer = (function()
-- BEGIN ENGINE COMPONENT Installer
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- =============================================================================
-- Engine installer decision core
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
-- =============================================================================
--
-- This module decides what one Engine installer transaction may do next. It
-- performs no filesystem or REAPER calls. The runtime adapter must execute one
-- returned action, durably record its result, rebuild a fresh snapshot, and ask
-- again. Keeping decisions pure lets the test suite stop before and after every
-- write or rename and prove that a new process reaches the same safe answer.

local EngineInstaller = {}

EngineInstaller.SCHEMA = 1

EngineInstaller.PLATFORM_FILENAMES = {
  ["win-x64"] = "reaper_mbriggs_helper-x64.dll",
  ["win-arm64"] = "reaper_mbriggs_helper-arm64.dll",
  -- Two Mac slices, two names, exactly as Windows already is. Architecture is
  -- a target dimension and never a swap: a Mac that runs both REAPER builds
  -- ends up with both files, each build loads its own, and neither install
  -- touches the other's. Measured on m1 on 2026-09-08 with REAPER 7.78 in an
  -- isolated portable install: a foreign-architecture `reaper_*.dylib` in
  -- UserPlugins is skipped with a dlopen note on stderr and no dialog, the
  -- matching one loads, and both REAPER builds do this from one resource path.
  ["mac-arm64"] = "reaper_mbriggs_helper-arm64.dylib",
  ["mac-x64"] = "reaper_mbriggs_helper-x86_64.dylib",
  ["linux-x64"] = "reaper_mbriggs_helper-x86_64.so",
  ["linux-arm64"] = "reaper_mbriggs_helper-aarch64.so",
}

-- The target keys, in a written order rather than a `pairs` walk, so the set
-- is the same on every host and in every process. A target key names one
-- platform-and-architecture slice of the Engine. It is what the status record
-- is indexed by and what the journal records, so two slices installed on one
-- machine never overwrite each other's evidence.
EngineInstaller.TARGET_KEYS = {
  "win-x64", "win-arm64", "mac-arm64", "mac-x64",
  "linux-x64", "linux-arm64",
}

-- The payload directory a target's artifact travels in, named by the target.
-- One directory per target key, all six alike. It lives beside the target keys
-- rather than in the runtime because the host reads the artifact before the
-- runtime exists.
function EngineInstaller.bundle_directory(platform)
  for _, key in ipairs(EngineInstaller.TARGET_KEYS) do
    if key == platform then return key end
  end
  return nil
end

-- The machine an artifact's own header declares, per target. A digest proves
-- the bytes are the ones the descriptor named; it does not prove the
-- descriptor named the right file for this machine. A slice published under
-- the wrong target key, or a resource directory carrying another platform's
-- build under this platform's name, hashes correctly and cannot load, so the
-- header is read as well and the two must agree.
--
-- `win-arm64` carries ARM64EC, not classic ARM64. REAPER for Windows on ARM is
-- an ARM64EC process: it loads x64 and ARM64EC modules and refuses classic
-- ARM64 ones, measured on the Surface Pro X on 2026-09-07 and 2026-09-08. The
-- release tooling has required `arm64ec` for this slot since then, and this
-- table states the same rule where the installer reads it. `win-x64` stays
-- plain x64, so an ARM64EC image offered under that key is refused as well: a
-- plain x64 Windows cannot load one.
EngineInstaller.TARGET_MACHINES = {
  ["win-x64"] = "pe-x64",
  ["win-arm64"] = "pe-arm64ec",
  ["mac-arm64"] = "macho-arm64",
  ["mac-x64"] = "macho-x86_64",
  ["linux-x64"] = "elf-x86_64",
  ["linux-arm64"] = "elf-aarch64",
}

local function byte_u16le(bytes, offset)
  local low, high = bytes:byte(offset, offset + 1)
  if not high then return nil end
  return low + high * 256
end

local function byte_u32le(bytes, offset)
  local a, b, c, d = bytes:byte(offset, offset + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- The PE data directory that holds the load configuration, and the field
-- inside it that separates an ARM64EC image from a plain x64 one.
-- `IMAGE_LOAD_CONFIG_DIRECTORY64.CHPEMetadataPointer` is the ULONGLONG at
-- 0xC8, so the directory has to state at least 0xD0 bytes for the field to be
-- there at all.
local LOAD_CONFIG_DIRECTORY_INDEX = 10
local LOAD_CONFIG_CHPE_OFFSET = 0xC8
local LOAD_CONFIG_MINIMUM_BYTES = 0xD0
-- The largest load configuration this rule will fetch. The structure MSVC
-- writes is 0x140 bytes in all three real Engine DLLs, so this is eight times
-- the size anything real states; a directory claiming more is refused rather
-- than turned into a read of whatever length a crafted header asks for.
local LOAD_CONFIG_MAXIMUM_BYTES = 0x1000

-- THE ONE RULE THAT TURNS A DIRECTORY RVA INTO FILE BYTES. The range asked for
-- has to lie inside [VirtualAddress, VirtualAddress + SizeOfRawData) of exactly
-- one section that stores bytes at all, and the offset it maps to has to hold
-- the whole range, which the caller proves by getting back every byte it asked
-- for.
--
-- SizeOfRawData, not the larger of it and VirtualSize. A section's virtual size
-- may run past the bytes the file stores for it, which is what `.data` does in
-- all three real Engine DLLs, and an RVA inside that overhang has no bytes of
-- its own: mapping it by the larger of the two spans lands in the next
-- section's bytes or past the end of the file, so an image could name one
-- section and be answered from another. A section that stores no bytes hosts
-- nothing.
--
-- Exactly one section, because two sections whose stored ranges both hold the
-- range would leave the choice of bytes to the order of the table. Measured on
-- 2026-09-09 over the three real DLLs (7, 9 and 7 sections): no overlapping
-- pair, so refusing costs nothing.
--
-- The offsets passed in and the offset returned are zero-based, because a PE
-- states them that way; the `byte_u32le` calls add the one Lua wants.
local function pe_file_offset(bytes, section_table, section_count, rva, size)
  local found = nil
  for index = 0, section_count - 1 do
    local section = section_table + 40 * index
    local virtual_address = byte_u32le(bytes, section + 13)
    local raw_size = byte_u32le(bytes, section + 17)
    local raw_offset = byte_u32le(bytes, section + 21)
    if not virtual_address or not raw_size or not raw_offset then
      return nil
    end
    if raw_size > 0 and rva >= virtual_address
        and rva + size <= virtual_address + raw_size then
      if found then return nil end
      found = raw_offset + (rva - virtual_address)
    end
  end
  return found
end

-- Does this PE image carry CHPE metadata? `true` for an ARM64EC image,
-- `false` for a well-formed image that states no load configuration or states
-- one too short to hold the pointer, which a plain x64 image is entitled to,
-- and `nil` for an image whose headers contradict each other or name a
-- structure this reader could not get to.
--
-- The last answer is a refusal rather than a reading of x64. An ARM64EC image
-- whose load configuration cannot be reached would otherwise be admitted for
-- `win-x64`, which is the machine that cannot load it, so an unreadable
-- structure loses the file rather than the rule. Absent metadata is not
-- unreadable metadata, and the two answers are kept apart on purpose: an image
-- that says there is nothing to read is plain x64, an image that says there is
-- something to read and does not hold it is refused.
local function pe_hybrid_metadata(bytes, fetch, pe_offset)
  local coff = pe_offset + 4
  local sections = byte_u16le(bytes, coff + 3)
  local optional_size = byte_u16le(bytes, coff + 17)
  if not sections or not optional_size then return nil end
  local optional = coff + 20
  -- PE32+ only. A PE32 optional header puts its data directories eight bytes
  -- earlier, and no target here is 32-bit, so a 64-bit machine word over an
  -- optional header that is not PE32+ is a file this rule will not read rather
  -- than one it guesses at.
  if byte_u16le(bytes, optional + 1) ~= 0x20B then return nil end
  -- SizeOfOptionalHeader has to cover every field read below. A PE32+ optional
  -- header is 0xF0 bytes: 0x70 of standard and Windows-specific fields, then
  -- sixteen data directories of eight bytes each. `NumberOfRvaAndSizes` ends at
  -- 0x70 and data directory ten ends at 0xC8, so a header that declares less
  -- than 0xF0 either does not hold the count at all or holds a count of
  -- directories it does not carry, and reading it anyway answers plain x64 out
  -- of bytes that are the section table or the file behind it. That answer is
  -- the one that admits an ARM64EC image under `win-x64`.
  --
  -- 0xF0 is the minimum `Get-EnginePeLayout` in
  -- `release/EngineReleasePackageTools.psm1` has always required, and
  -- `Get-PayloadPeHybridMetadata` in `Publish-EngineToApp.ps1` requires it too.
  -- One number in three places, so an image cannot be readable under one of the
  -- three rules and refused under another. Measured on 2026-09-09: all three
  -- real Engine DLLs declare 0xF0 and sixteen directories, so requiring the
  -- whole header costs nothing.
  if optional_size < 0xF0 then return nil end
  -- The section table is what maps every RVA below, so a table that runs past
  -- the bytes in hand is a header this rule cannot read rather than one whose
  -- first entries happen to answer.
  local section_table = optional + optional_size
  if section_table + 40 * sections > #bytes then return nil end
  local directories = byte_u32le(bytes, optional + 109)
  if not directories then return nil end
  if directories <= LOAD_CONFIG_DIRECTORY_INDEX then return false end
  local entry = optional + 112 + LOAD_CONFIG_DIRECTORY_INDEX * 8
  -- An image that states more data directories than its optional header holds
  -- contradicts itself. Reading the entry anyway would read the section table
  -- as a data directory.
  if entry + 8 > section_table then return nil end
  local rva = byte_u32le(bytes, entry + 1)
  local size = byte_u32le(bytes, entry + 5)
  if not rva or not size then return nil end
  if rva == 0 then return false end
  -- A stated load configuration has to hold its own `Size` field, and has to
  -- be small enough to fetch, so a crafted header cannot turn this into a read
  -- of any length it likes.
  if size < 4 or size > LOAD_CONFIG_MAXIMUM_BYTES then return nil end
  local offset = pe_file_offset(bytes, section_table, sections, rva, size)
  if not offset then return nil end
  -- Every byte the directory claims, not only the ones the rule reads. A
  -- directory that advertises more than the file holds is refused here rather
  -- than answered from a short read that happens to cover the field.
  local config = fetch(offset, size)
  if type(config) ~= "string" or #config < size then return nil end
  -- The structure states its own length as well, and the two lengths have to
  -- agree. A structure longer than the directory that names it, or one that
  -- stops short of the pointer the directory says is there, is a contradiction
  -- rather than a plain x64 image.
  local declared = byte_u32le(config, 1)
  if not declared or declared > size then return nil end
  if size < LOAD_CONFIG_MINIMUM_BYTES then return false end
  if declared < LOAD_CONFIG_MINIMUM_BYTES then return nil end
  -- Read as eight bytes rather than as one number. The pointer is a 64-bit
  -- virtual address and only its being zero or not matters here, so nothing
  -- has to survive a conversion to a Lua number.
  for index = LOAD_CONFIG_CHPE_OFFSET + 1, LOAD_CONFIG_CHPE_OFFSET + 8 do
    if config:byte(index) ~= 0 then return true end
  end
  return false
end

-- Bytes already in hand are answered from `bytes`; anything past them goes to
-- the caller's reader. A caller holding a whole image in one string therefore
-- needs no reader, and a host holding a header prefix and an open file lends
-- the handle.
local function fetch_for(bytes, read_at)
  return function(offset, count)
    if offset >= 0 and offset + count <= #bytes then
      return bytes:sub(offset + 1, offset + count)
    end
    if type(read_at) ~= "function" then return nil end
    local ok, out = pcall(read_at, offset, count)
    if not ok or type(out) ~= "string" then return nil end
    return out
  end
end

-- Every offset here is one-based, because Lua strings are. A header this
-- function cannot read to the end of is `nil`, never a guess: an artifact
-- whose machine cannot be established is refused rather than admitted on the
-- strength of its digest alone.
--
-- `read_at(offset, count)` is optional and takes a zero-based file offset. It
-- exists for one field. The load configuration of a real Engine DLL sits about
-- 1.7 MB into the file, far past any header prefix a host would read, and the
-- whole Windows rule belongs here rather than half of it in the host, so the
-- host lends its open handle and this function does the walking.
function EngineInstaller.machine_of(bytes, read_at)
  if type(bytes) ~= "string" or #bytes < 64 then return nil end
  local first4 = bytes:sub(1, 4)

  if bytes:sub(1, 2) == "MZ" then
    local header = byte_u32le(bytes, 0x3D)
    if not header or header < 0 or header + 6 > #bytes then return nil end
    if bytes:sub(header + 1, header + 2) ~= "PE"
        or bytes:byte(header + 3) ~= 0
        or bytes:byte(header + 4) ~= 0 then
      return nil
    end
    local machine = byte_u16le(bytes, header + 5)
    if machine ~= 0xAA64 and machine ~= 0x8664 then return nil end
    -- ARM64EC and plain x64 are one machine word, because that is the point of
    -- the format: an ARM64EC process loads x64 and ARM64EC modules and refuses
    -- classic ARM64 ones, so the ARM code arrives under the AMD64 value. The
    -- CHPE pointer in the load configuration is the only thing that separates
    -- them, and `Publish-EngineToApp.ps1` and the release package gate read the
    -- same field the same way.
    --
    -- Classic ARM64 has a machine word of its own and needs no CHPE pointer
    -- read. It walks the same headers all the same, so one contradictory image
    -- is not readable under one machine word and refused under another. No
    -- target admits it any more; it is classified so a refusal can name it.
    local hybrid = pe_hybrid_metadata(bytes, fetch_for(bytes, read_at), header)
    if hybrid == nil then return nil end
    if machine == 0xAA64 then return "pe-arm64" end
    if hybrid then return "pe-arm64ec" end
    return "pe-x64"
  end

  -- A fat file is not a slice. Each Mac target takes a thin slice of its own,
  -- and admitting a fat file under one of their names would put an image for
  -- both architectures where one architecture's image belongs. REAPER loads
  -- every reaper_*.dylib it can, so a fat file beside a thin one is two
  -- loadable Engines for the same architecture: measured on m1 on 2026-09-08,
  -- where both ran their entry point in one process.
  if first4:byte(1) == 0xCA and first4:byte(2) == 0xFE
      and first4:byte(3) == 0xBA
      and (first4:byte(4) == 0xBE or first4:byte(4) == 0xBF) then
    return "macho-universal"
  end
  if byte_u32le(bytes, 1) == 0xFEEDFACF then
    local cpu = byte_u32le(bytes, 5)
    if cpu == 0x0100000C then return "macho-arm64" end
    if cpu == 0x01000007 then return "macho-x86_64" end
    return nil
  end

  if first4:byte(1) == 0x7F and first4:sub(2, 4) == "ELF" then
    local class, data = bytes:byte(5, 6)
    if class ~= 2 or data ~= 1 then return nil end
    local machine = byte_u16le(bytes, 0x13)
    if machine == 0x3E then return "elf-x86_64" end
    if machine == 0xB7 then return "elf-aarch64" end
    return nil
  end

  return nil
end

-- `read_at` travels through untouched, so a caller that can seek gives the
-- Windows rule everything it needs and a caller that cannot gets the same
-- refusal a short header gets.
function EngineInstaller.machine_matches(platform, bytes, read_at)
  local expected = EngineInstaller.TARGET_MACHINES[platform]
  if not expected then return false, "platform" end
  local actual = EngineInstaller.machine_of(bytes, read_at)
  if actual == nil then return false, "unreadable" end
  if actual ~= expected then return false, actual end
  return true
end

EngineInstaller.PHASES = {
  ["staged"] = true,
  ["sentinel-written"] = true,
  ["moving-previous"] = true,
  ["previous-moved"] = true,
  ["placing-target"] = true,
  ["target-placed"] = true,
  ["pending-restart"] = true,
  ["active"] = true,
  ["rollback-prepared"] = true,
  ["rejecting-target"] = true,
  ["target-rejected"] = true,
  ["restoring-previous"] = true,
  ["previous-restored"] = true,
  ["rolled-back-pending-restart"] = true,
  ["rolled-back"] = true,
}

-- The removal transition a withdrawal drives. REAPER loads the extension
-- before any Lua runs, so refusing calls does not stop a withdrawn digest from
-- initializing again; only taking the file out of the load path does. The
-- confirmation phase exists so the removal is never confused with a file that
-- was never there: the digest is proved present, written down, and only then
-- removed, and a live slot that holds other bytes by the time the removal runs
-- is another app's healthy install and is left alone.
EngineInstaller.WITHDRAWAL_PHASES = {
  ["withdrawal-pending"] = true,
  ["withdrawal-confirmed"] = true,
  ["withdrawal-removed"] = true,
  ["withdrawal-superseded"] = true,
  ["withdrawal-absent"] = true,
}

EngineInstaller.WITHDRAWAL_TERMINAL_PHASES = {
  ["withdrawal-removed"] = true,
  ["withdrawal-superseded"] = true,
  ["withdrawal-absent"] = true,
}

EngineInstaller.JOURNAL_KINDS = {
  ["install"] = true,
  ["withdrawal-removal"] = true,
}

local JOURNAL_FIELDS = {
  schema = true,
  transaction_id = true,
  phase = true,
  -- Which machine drives this journal. Absent means "install", which is what
  -- every journal written before the withdrawal transition existed is.
  kind = true,
  -- The target key this transaction is bound to. Absent means the platform,
  -- which is what every journal written before targets were named is. Recovery
  -- reads it through `journal_target`, never through `platform`, because two
  -- targets can share a platform's build and only the key says which slice a
  -- process is allowed to activate.
  target = true,
  platform = true,
  filename = true,
  target_version = true,
  target_sha256 = true,
  previous_kind = true,
  previous_version = true,
  previous_sha256 = true,
  failures = true,
  writer_instance = true,
  activation_session = true,
  rollback_session = true,
  -- The session that recorded the most recent probe failure. Additive inside
  -- schema 1: one REAPER session may contribute at most one failure, so a
  -- second instance that never loaded the target cannot spend both attempts.
  failure_session = true,
}

local SENTINEL_FIELDS = {
  schema = true,
  transaction_id = true,
  mode = true,
  expected_kind = true,
  version = true,
  sha256 = true,
}

local TARGET_FIELDS = {
  platform = true,
  filename = true,
  version = true,
  sha256 = true,
}

local SNAPSHOT_FIELDS = {
  lock = true,
  journal = true,
  sentinel = true,
  same_session = true,
  same_failure_session = true,
  quarantine = true,
  files = true,
  probe = true,
}

local FILE_FIELDS = {
  live = true,
  staged = true,
  backup = true,
  rejected = true,
}

local FILE_CLASSES = {
  absent = true,
  target = true,
  previous = true,
  other = true,
  unreadable = true,
}

local PROBE_RESULTS = {
  ["not-run"] = true,
  ["target-ok"] = true,
  ["previous-ok"] = true,
  ["absent-ok"] = true,
  -- The probing process never loaded the binary the lane is about, so it can
  -- report nothing about it. Distinct from "failed", which is evidence.
  ["not-loaded"] = true,
  -- No Engine is registered at all where the lane expected the target. Nothing
  -- can be concluded from it: a REAPER process that started before the
  -- placement reports exactly the same thing for a good install, and no source
  -- of process start times is available to Lua on all three platforms. It never
  -- counts toward a rollback.
  ["not-registered"] = true,
  ["failed"] = true,
  -- The probe could not run, or the snapshot it was handed was not usable.
  -- Neither observes the placed file, so neither counts toward a rollback.
  ["unavailable"] = true,
  ["malformed"] = true,
}

-- Every key the allowlist does not name, sorted and joined, rather than
-- whichever one `pairs` reached first. A table's iteration order is a property
-- of the process that built it, so reporting one key made the same defect
-- answer with a different field name on different runs, and a caller removing
-- the reported field learned the next one only by running again. The list is
-- capped because one of the tables validated here is a file this app did not
-- write.
local UNKNOWN_FIELD_LIMIT = 8

local function unknown_field(value, allowed)
  if type(value) ~= "table" then return nil end
  local names = {}
  for key in pairs(value) do
    if not allowed[key] then names[#names + 1] = tostring(key) end
  end
  if #names == 0 then return nil end
  table.sort(names)
  if #names <= UNKNOWN_FIELD_LIMIT then return table.concat(names, ",") end
  return table.concat(names, ",", 1, UNKNOWN_FIELD_LIMIT)
    .. ",+" .. tostring(#names - UNKNOWN_FIELD_LIMIT)
end

local function is_lower_sha256(value)
  return type(value) == "string"
    and #value == 64
    and value:match("^[0-9a-f]+$") ~= nil
end

local function parse_version(value)
  if type(value) ~= "string" then return nil end
  local a, b, c = value:match("^(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  local out = {}
  for index, part in ipairs({a, b, c}) do
    if #part > 1 and part:sub(1, 1) == "0" then return nil end
    local number = tonumber(part)
    if not number or number < 0 or number > 999999999
        or number ~= math.floor(number) then
      return nil
    end
    out[index] = number
  end
  return out
end

local function safe_id(value, prefix)
  if type(value) ~= "string" or #value < #prefix + 1 or #value > 160 then
    return false
  end
  if value:sub(1, #prefix) ~= prefix then return false end
  return value:match("^[A-Za-z0-9_%-]+$") ~= nil
end

local function refuse(reason, detail)
  return {kind = "refuse", reason = reason, detail = detail}
end

local function action(kind, next_phase)
  local out = {kind = kind}
  if next_phase then out.next_phase = next_phase end
  return out
end

local function prior_file_state_ok(journal, files)
  if journal.previous_kind == "absent" then
    return files.backup == "absent"
  end
  return files.backup == "previous"
end

function EngineInstaller.is_lower_sha256(value)
  return is_lower_sha256(value)
end

function EngineInstaller.parse_version(value)
  return parse_version(value)
end

function EngineInstaller.compare_versions(left, right)
  local a = parse_version(left)
  local b = parse_version(right)
  if not a or not b then return nil, "invalid-version" end
  for index = 1, 3 do
    if a[index] < b[index] then return -1 end
    if a[index] > b[index] then return 1 end
  end
  return 0
end

function EngineInstaller.validate_target(target)
  if type(target) ~= "table" then return false, "target-not-table" end
  local extra = unknown_field(target, TARGET_FIELDS)
  if extra then return false, "target-unknown-field:" .. extra end
  local expected = EngineInstaller.PLATFORM_FILENAMES[target.platform]
  if not expected then return false, "target-platform" end
  if target.filename ~= expected then return false, "target-filename" end
  if not parse_version(target.version) then return false, "target-version" end
  if not is_lower_sha256(target.sha256) then return false, "target-sha256" end
  return true
end

local TARGET_KEY_SET = {}
for _, key in ipairs(EngineInstaller.TARGET_KEYS) do TARGET_KEY_SET[key] = true end

-- The target key a journal is bound to. `platform` is the fallback because a
-- runtime carrying another slice's file operations leaves `target` absent: it
-- is not the process that will load that target, so it does not claim the key.
function EngineInstaller.journal_target(journal)
  if type(journal) ~= "table" then return nil end
  if journal.target ~= nil then return journal.target end
  return journal.platform
end

function EngineInstaller.journal_kind(journal)
  if type(journal) ~= "table" then return nil end
  if journal.kind == nil then return "install" end
  return journal.kind
end

function EngineInstaller.is_target_key(value)
  return TARGET_KEY_SET[value] == true
end

-- Why a recovery obligation could not be met, in the one vocabulary the
-- runtime writes into the record's `reason`, split into the answers that can
-- change and the three that cannot.
--
-- An obligation says one file is owed one Engine. It is kept until that Engine
-- is back, because deleting it is how a previous Engine sitting in a backup
-- artifact stops being anything's business. Three answers say it will never be
-- back, whatever anyone waits for:
--
--   backup-absent  -- there is no artifact at the name the record carries;
--   backup-sha256  -- the artifact is there and its bytes are not that Engine;
--   withdrawn      -- that Engine has been withdrawn, and the whole point of
--                     the withdrawal record is that it never re-enters a load
--                     path.
--
-- Everything else is a wait rather than a verdict, and must not qualify: a
-- file held open, a rename that lost a race, a readback still in flight, a
-- withdrawal record this app could not read (a later reading may well say the
-- digest is clear), and a live slot holding bytes that are not the recorded
-- Engine, which is a slot with something in it rather than an empty one.
--
-- This predicate is the core's rather than either caller's so the control that
-- offers the discharge and the body that performs it cannot disagree about
-- which obligations qualify.
EngineInstaller.UNMEETABLE_RECOVERY_REASONS = {
  ["backup-absent"] = true,
  ["backup-sha256"] = true,
  ["withdrawn"] = true,
}

function EngineInstaller.recovery_unmeetable(reason)
  if type(reason) ~= "string" then return false end
  return EngineInstaller.UNMEETABLE_RECOVERY_REASONS[reason] == true
end

function EngineInstaller.validate_journal(journal)
  if type(journal) ~= "table" then return false, "journal-not-table" end
  local extra = unknown_field(journal, JOURNAL_FIELDS)
  if extra then return false, "journal-unknown-field:" .. extra end
  if journal.schema ~= EngineInstaller.SCHEMA then
    return false, "journal-schema"
  end
  if not safe_id(journal.transaction_id, "txn_") then
    return false, "journal-transaction-id"
  end
  local kind = EngineInstaller.journal_kind(journal)
  if not EngineInstaller.JOURNAL_KINDS[kind] then
    return false, "journal-kind"
  end
  if journal.target ~= nil and not TARGET_KEY_SET[journal.target] then
    return false, "journal-target"
  end
  if journal.target ~= nil and journal.target ~= journal.platform then
    -- Today one platform is one target. The field is separate so recovery
    -- binds to the key rather than to the build, and so a later split of a
    -- platform into two slices does not have to reinterpret old journals.
    return false, "journal-target-platform"
  end
  if kind == "withdrawal-removal" then
    return EngineInstaller.validate_withdrawal_journal(journal)
  end
  if not EngineInstaller.PHASES[journal.phase] then
    return false, "journal-phase"
  end
  local expected = EngineInstaller.PLATFORM_FILENAMES[journal.platform]
  if not expected or journal.filename ~= expected then
    return false, "journal-platform-filename"
  end
  if not parse_version(journal.target_version) then
    return false, "journal-target-version"
  end
  if not is_lower_sha256(journal.target_sha256) then
    return false, "journal-target-sha256"
  end
  if journal.previous_kind == "engine" then
    if not parse_version(journal.previous_version) then
      return false, "journal-previous-version"
    end
    if not is_lower_sha256(journal.previous_sha256) then
      return false, "journal-previous-sha256"
    end
    if journal.previous_sha256 == journal.target_sha256 then
      return false, "journal-identical-target-previous"
    end
  elseif journal.previous_kind == "absent" then
    if journal.previous_version ~= nil or journal.previous_sha256 ~= nil then
      return false, "journal-absent-previous-metadata"
    end
  else
    return false, "journal-previous-kind"
  end
  if type(journal.failures) ~= "number"
      or journal.failures ~= math.floor(journal.failures)
      or journal.failures < 0 or journal.failures > 2 then
    return false, "journal-failures"
  end
  if not safe_id(journal.writer_instance, "inst_") then
    return false, "journal-writer-instance"
  end
  if journal.activation_session ~= nil
      and not safe_id(journal.activation_session, "session_") then
    return false, "journal-activation-session"
  end
  if journal.rollback_session ~= nil
      and not safe_id(journal.rollback_session, "session_") then
    return false, "journal-rollback-session"
  end
  if journal.failure_session ~= nil then
    if not safe_id(journal.failure_session, "session_") then
      return false, "journal-failure-session"
    end
    if journal.failures < 1 then return false, "journal-failure-session-count" end
  end
  local rollback_phase = journal.phase == "rollback-prepared"
    or journal.phase == "rejecting-target"
    or journal.phase == "target-rejected"
    or journal.phase == "restoring-previous"
    or journal.phase == "previous-restored"
    or journal.phase == "rolled-back-pending-restart"
    or journal.phase == "rolled-back"
  if rollback_phase and journal.failures ~= 2 then
    return false, "journal-rollback-failures"
  end
  if not rollback_phase and journal.failures == 2
      and journal.phase ~= "active" then
    return false, "journal-pre-rollback-failures"
  end
  if journal.phase ~= "staged" and journal.activation_session == nil then
    return false, "journal-activation-session-required"
  end
  if rollback_phase and journal.rollback_session == nil then
    return false, "journal-rollback-session-required"
  end
  if not rollback_phase and journal.rollback_session ~= nil then
    return false, "journal-early-rollback-session"
  end
  return true
end

-- A withdrawal removal is bound to one digest and to nothing else. It carries
-- no version, because a withdrawal names bytes rather than a release name and
-- the file in the load path may be one the status record never described; no
-- previous artifact, because it restores nothing; and no session or failure
-- count, because it certifies nothing and its retries are not activation
-- attempts. The two-failure rollback rule is the install machine's and is not
-- reused here.
function EngineInstaller.validate_withdrawal_journal(journal)
  if not EngineInstaller.WITHDRAWAL_PHASES[journal.phase] then
    return false, "withdrawal-phase"
  end
  local expected = EngineInstaller.PLATFORM_FILENAMES[journal.platform]
  if not expected or journal.filename ~= expected then
    return false, "withdrawal-platform-filename"
  end
  if not is_lower_sha256(journal.target_sha256) then
    return false, "withdrawal-sha256"
  end
  if journal.target_version ~= nil then
    return false, "withdrawal-version"
  end
  if journal.previous_kind ~= "absent" or journal.previous_version ~= nil
      or journal.previous_sha256 ~= nil then
    return false, "withdrawal-previous"
  end
  if journal.failures ~= 0 then return false, "withdrawal-failures" end
  if not safe_id(journal.writer_instance, "inst_") then
    return false, "withdrawal-writer-instance"
  end
  if journal.activation_session ~= nil or journal.rollback_session ~= nil
      or journal.failure_session ~= nil then
    return false, "withdrawal-session"
  end
  return true
end

-- The only decision the removal machine makes. The live slot is reclassified
-- at every step, so bytes that changed between two steps change the answer
-- rather than the outcome: one app's removal of X never removes a healthy Y
-- another app installed in between.
function EngineInstaller.next_withdrawal_action(snapshot)
  if type(snapshot) ~= "table" then return refuse("snapshot-invalid") end
  if snapshot.lock == "held" then return refuse("lock-held") end
  if snapshot.lock == "undecidable" then return refuse("lock-undecidable") end
  if snapshot.lock ~= "owned" then return refuse("lock-lost") end
  local journal = snapshot.journal
  local valid, why = EngineInstaller.validate_journal(journal)
  if not valid then return refuse("snapshot-invalid", why) end
  if EngineInstaller.journal_kind(journal) ~= "withdrawal-removal" then
    return refuse("withdrawal-kind", EngineInstaller.journal_kind(journal))
  end
  local live = snapshot.live
  if live ~= "withdrawn" and live ~= "other" and live ~= "absent"
      and live ~= "unreadable" then
    return refuse("snapshot-invalid", "withdrawal-live")
  end
  if EngineInstaller.WITHDRAWAL_TERMINAL_PHASES[journal.phase] then
    return action("complete-withdrawal")
  end
  -- A file this process cannot read proves nothing about its bytes, and a
  -- removal that is not proved is never performed. It is retried like any
  -- other step, which is also what a sharing violation gets.
  if live == "unreadable" then return refuse("withdrawal-live-unreadable") end
  if journal.phase == "withdrawal-pending" then
    if live == "withdrawn" then
      return action("set-phase", "withdrawal-confirmed")
    end
    if live == "absent" then return action("set-phase", "withdrawal-absent") end
    return action("set-phase", "withdrawal-superseded")
  end
  -- withdrawal-confirmed
  if live == "withdrawn" then return action("remove-withdrawn-live") end
  if live == "absent" then return action("set-phase", "withdrawal-removed") end
  return action("set-phase", "withdrawal-superseded")
end

function EngineInstaller.validate_sentinel(sentinel)
  if type(sentinel) ~= "table" then return false, "sentinel-not-table" end
  local extra = unknown_field(sentinel, SENTINEL_FIELDS)
  if extra then return false, "sentinel-unknown-field:" .. extra end
  if sentinel.schema ~= EngineInstaller.SCHEMA then
    return false, "sentinel-schema"
  end
  if not safe_id(sentinel.transaction_id, "txn_") then
    return false, "sentinel-transaction-id"
  end
  if sentinel.mode ~= "activation" and sentinel.mode ~= "rollback" then
    return false, "sentinel-mode"
  end
  if sentinel.expected_kind == "target" or sentinel.expected_kind == "previous" then
    if not parse_version(sentinel.version) then
      return false, "sentinel-version"
    end
    if not is_lower_sha256(sentinel.sha256) then
      return false, "sentinel-sha256"
    end
  elseif sentinel.expected_kind == "absent" then
    if sentinel.version ~= nil or sentinel.sha256 ~= nil then
      return false, "sentinel-absent-metadata"
    end
  else
    return false, "sentinel-expected-kind"
  end
  if sentinel.mode == "activation" and sentinel.expected_kind ~= "target" then
    return false, "sentinel-activation-kind"
  end
  if sentinel.mode == "rollback" and sentinel.expected_kind == "target" then
    return false, "sentinel-rollback-kind"
  end
  return true
end

function EngineInstaller.sentinel_for_activation(journal)
  local ok, why = EngineInstaller.validate_journal(journal)
  if not ok then return nil, why end
  if EngineInstaller.journal_kind(journal) ~= "install" then
    return nil, "journal-kind"
  end
  return {
    schema = EngineInstaller.SCHEMA,
    transaction_id = journal.transaction_id,
    mode = "activation",
    expected_kind = "target",
    version = journal.target_version,
    sha256 = journal.target_sha256,
  }
end

function EngineInstaller.sentinel_for_rollback(journal)
  local ok, why = EngineInstaller.validate_journal(journal)
  if not ok then return nil, why end
  if EngineInstaller.journal_kind(journal) ~= "install" then
    return nil, "journal-kind"
  end
  local out = {
    schema = EngineInstaller.SCHEMA,
    transaction_id = journal.transaction_id,
    mode = "rollback",
    expected_kind = journal.previous_kind == "engine" and "previous" or "absent",
  }
  if journal.previous_kind == "engine" then
    out.version = journal.previous_version
    out.sha256 = journal.previous_sha256
  end
  return out
end

function EngineInstaller.sentinel_relation(journal, sentinel)
  if sentinel == nil then return "absent" end
  local ok = EngineInstaller.validate_sentinel(sentinel)
  if not ok then return "invalid" end
  if sentinel.transaction_id ~= journal.transaction_id then return "other" end
  if sentinel.mode == "activation"
      and sentinel.expected_kind == "target"
      and sentinel.version == journal.target_version
      and sentinel.sha256 == journal.target_sha256 then
    return "activation"
  end
  if sentinel.mode == "rollback" then
    if journal.previous_kind == "absent"
        and sentinel.expected_kind == "absent" then
      return "rollback"
    end
    if journal.previous_kind == "engine"
        and sentinel.expected_kind == "previous"
        and sentinel.version == journal.previous_version
        and sentinel.sha256 == journal.previous_sha256 then
      return "rollback"
    end
  end
  return "other"
end

function EngineInstaller.artifact_names(journal)
  local ok, why = EngineInstaller.validate_journal(journal)
  if not ok then return nil, why end
  -- A withdrawal removal stages, backs up and rejects nothing, so it has no
  -- artifact names and no caller may invent any for it.
  if EngineInstaller.journal_kind(journal) ~= "install" then
    return nil, "journal-kind"
  end
  -- The journal carries and verifies the full digest. Filenames use a 64-bit
  -- prefix so the Windows resource path stays below the MAX_PATH ceiling.
  -- A prefix collision cannot replace anything: an existing artifact is read
  -- and compared against the full journal digest before any action proceeds.
  local target_tag = journal.target_version .. "."
    .. journal.target_sha256:sub(1, 16)
  local out = {
    live = journal.filename,
    staged = "Staged/" .. journal.filename .. "." .. target_tag .. ".staged",
    rejected = "Rejected/" .. journal.filename .. "." .. target_tag .. ".bad",
  }
  if journal.previous_kind == "engine" then
    local prior_tag = journal.previous_version .. "."
      .. journal.previous_sha256:sub(1, 16)
    out.backup = "Backup/" .. journal.filename .. "." .. prior_tag .. ".backup"
  end
  return out
end

function EngineInstaller.classify_file(observation, journal)
  if observation == nil or observation == "absent" then return "absent" end
  if observation == "unreadable" then return "unreadable" end
  local sha = type(observation) == "table" and observation.sha256 or observation
  if not is_lower_sha256(sha) then return "other" end
  if sha == journal.target_sha256 then return "target" end
  if journal.previous_kind == "engine" and sha == journal.previous_sha256 then
    return "previous"
  end
  return "other"
end

function EngineInstaller.decide_admission(input)
  if type(input) ~= "table" then return refuse("admission-invalid") end
  if input.lock == "held" then return refuse("lock-held") end
  if input.lock ~= "owned" then return refuse("lock-undecidable") end

  local target_ok, target_why = EngineInstaller.validate_target(input.target)
  if not target_ok then return refuse("target-invalid", target_why) end

  if input.journal_state == "invalid" or input.journal_state == "unreadable" then
    return refuse("journal-invalid")
  end
  if input.journal_state == "same" then return action("resume") end
  if input.journal_state == "other" then return refuse("transaction-conflict") end
  if input.journal_state ~= nil and input.journal_state ~= "absent" then
    return refuse("admission-invalid", "journal-state")
  end
  if input.quarantined == true then return refuse("target-quarantined") end

  if input.installed_state == "unreadable" then
    return refuse("active-undecidable")
  end
  if input.installed_state == nil or input.installed_state == "absent" then
    return action("stage")
  end
  if input.installed_state ~= "engine" or type(input.installed) ~= "table"
      or not parse_version(input.installed.version)
      or not is_lower_sha256(input.installed.sha256) then
    return refuse("active-undecidable")
  end

  local comparison = EngineInstaller.compare_versions(
    input.target.version, input.installed.version)
  if comparison > 0 then return action("stage") end
  if comparison < 0 then return refuse("downgrade") end
  if input.target.sha256 == input.installed.sha256 then
    return action("already-current")
  end
  -- Two builds can carry one version with different bytes, so the same-version
  -- replace runs the ordinary transaction: stage, restart, probe, roll back on
  -- failure. It is admitted only when the caller asked for it explicitly.
  if input.replace_equal_version == true then return action("stage") end
  return refuse("equal-version-conflict")
end

function EngineInstaller.validate_snapshot(snapshot)
  if type(snapshot) ~= "table" then return false, "snapshot-not-table" end
  local extra = unknown_field(snapshot, SNAPSHOT_FIELDS)
  if extra then return false, "snapshot-unknown-field:" .. extra end
  if snapshot.lock ~= "owned" and snapshot.lock ~= "held"
      and snapshot.lock ~= "undecidable" and snapshot.lock ~= "lost" then
    return false, "snapshot-lock"
  end
  local journal_ok, journal_why = EngineInstaller.validate_journal(snapshot.journal)
  if not journal_ok then return false, journal_why end
  if type(snapshot.same_session) ~= "boolean" then
    return false, "snapshot-same-session"
  end
  if type(snapshot.same_failure_session) ~= "boolean" then
    return false, "snapshot-same-failure-session"
  end
  if type(snapshot.quarantine) ~= "boolean" then
    return false, "snapshot-quarantine"
  end
  if type(snapshot.files) ~= "table" then return false, "snapshot-files" end
  local file_extra = unknown_field(snapshot.files, FILE_FIELDS)
  if file_extra then return false, "snapshot-file-field:" .. file_extra end
  for name in pairs(FILE_FIELDS) do
    if not FILE_CLASSES[snapshot.files[name]] then
      return false, "snapshot-file-class:" .. name
    end
  end
  if not PROBE_RESULTS[snapshot.probe] then return false, "snapshot-probe" end
  if snapshot.sentinel ~= nil then
    local sentinel_ok, sentinel_why = EngineInstaller.validate_sentinel(
      snapshot.sentinel)
    if not sentinel_ok then return false, sentinel_why end
  end
  return true
end

-- The user's decision to undo a transaction whose target is in the live slot
-- and has not registered. The installer never reaches this on its own: no
-- Engine registered is not evidence about the target, so nothing here counts
-- as a failure and the ordinary rollback machine takes over from the phase
-- this returns. A target that has already probed clean once is not offered,
-- which is why only "pending-restart" is admitted.
function EngineInstaller.decide_rejection(snapshot)
  local valid, why = EngineInstaller.validate_snapshot(snapshot)
  if not valid then return refuse("snapshot-invalid", why) end
  if snapshot.lock ~= "owned" then return refuse("lock-lost") end
  local journal, files = snapshot.journal, snapshot.files
  if journal.phase ~= "pending-restart" then
    return refuse("rejection-phase", journal.phase)
  end
  if EngineInstaller.sentinel_relation(journal, snapshot.sentinel)
      ~= "activation" then
    return refuse("sentinel-missing")
  end
  if files.live ~= "target" or files.staged ~= "absent"
      or files.rejected ~= "absent" or not prior_file_state_ok(journal, files) then
    return refuse("disk-state-conflict", "rejection")
  end
  return action("prepare-rollback", "rollback-prepared")
end

function EngineInstaller.next_action(snapshot)
  local valid, why = EngineInstaller.validate_snapshot(snapshot)
  if not valid then return refuse("snapshot-invalid", why) end
  if snapshot.lock == "held" then return refuse("lock-held") end
  if snapshot.lock == "undecidable" then return refuse("lock-undecidable") end
  if snapshot.lock ~= "owned" then return refuse("lock-lost") end

  local journal = snapshot.journal
  -- The install machine and the removal machine never share a rule. A journal
  -- of the other kind is refused here rather than interpreted, so no phase
  -- branch below has to ask which machine it is in.
  if EngineInstaller.journal_kind(journal) ~= "install" then
    return refuse("journal-kind", EngineInstaller.journal_kind(journal))
  end
  local files = snapshot.files
  local sentinel = EngineInstaller.sentinel_relation(journal, snapshot.sentinel)
  local phase = journal.phase

  if sentinel == "invalid" or sentinel == "other" then
    return refuse("sentinel-orphaned")
  end

  if phase == "staged" then
    if files.staged ~= "target" then return refuse("staged-invalid") end
    if files.rejected ~= "absent" then
      return refuse("disk-state-conflict", "rejected")
    end
    if files.live ~= "previous" and files.live ~= "absent" then
      return refuse("disk-state-conflict", "live")
    end
    if journal.previous_kind == "engine" and files.live ~= "previous" then
      return refuse("disk-state-conflict", "previous-live")
    end
    if journal.previous_kind == "absent" and files.live ~= "absent" then
      return refuse("disk-state-conflict", "fresh-live")
    end
    if files.backup ~= "absent" then
      return refuse("disk-state-conflict", "backup")
    end
    if sentinel == "absent" and not snapshot.same_session then
      return action("record-activation-session")
    end
    if sentinel == "absent" then return action("write-activation-sentinel") end
    if sentinel == "activation" then
      return action("set-phase", "sentinel-written")
    end
    return refuse("sentinel-orphaned")
  end

  if phase == "sentinel-written" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.rejected ~= "absent" then
      return refuse("disk-state-conflict", "rejected")
    end
    if files.live == "target" and files.staged == "absent"
        and prior_file_state_ok(journal, files) then
      return action("set-phase", "target-placed")
    end
    if journal.previous_kind == "absent" then
      if files.live ~= "absent" or files.backup ~= "absent" then
        return refuse("disk-state-conflict", "fresh-previous")
      end
      return action("set-phase", "previous-moved")
    end
    if files.live == "previous" and files.backup == "previous" then
      return refuse("duplicate-previous")
    end
    if files.live == "absent" and files.backup == "previous" then
      return action("set-phase", "previous-moved")
    end
    if files.live == "previous" and files.backup == "absent"
        and files.staged == "target" then
      if not snapshot.same_session then
        return action("record-activation-session")
      end
      return action("set-phase", "moving-previous")
    end
    return refuse("disk-state-conflict", "sentinel-written")
  end

  if phase == "moving-previous" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.rejected ~= "absent" then
      return refuse("disk-state-conflict", "rejected")
    end
    if files.live == "previous" and files.backup == "absent"
        and files.staged == "target" then
      if not snapshot.same_session then
        return action("record-activation-session")
      end
      return action("rename-previous-to-backup")
    end
    if files.live == "previous" and files.backup == "previous"
        and files.staged == "target" then
      if not snapshot.same_session then
        return action("record-activation-session")
      end
      return action("remove-duplicate-live-previous")
    end
    if files.live == "absent" and files.backup == "previous"
        and files.staged == "target" then
      return action("set-phase", "previous-moved")
    end
    return refuse("disk-state-conflict", "moving-previous")
  end

  if phase == "previous-moved" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.rejected ~= "absent" then
      return refuse("disk-state-conflict", "rejected")
    end
    if not prior_file_state_ok(journal, files) then
      return refuse("disk-state-conflict", "previous-backup")
    end
    if files.live == "target" and files.staged == "target" then
      return action("remove-duplicate-staged-target")
    end
    if files.live == "target" and files.staged == "absent" then
      return action("set-phase", "target-placed")
    end
    if not snapshot.same_session then
      return action("record-activation-session")
    end
    if files.live == "absent" and files.staged == "target" then
      return action("set-phase", "placing-target")
    end
    return refuse("disk-state-conflict", "previous-moved")
  end

  if phase == "placing-target" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.rejected ~= "absent" then
      return refuse("disk-state-conflict", "rejected")
    end
    if not prior_file_state_ok(journal, files) then
      return refuse("disk-state-conflict", "placing-backup")
    end
    if files.live == "absent" and files.staged == "target" then
      if not snapshot.same_session then
        return action("record-activation-session")
      end
      return action("rename-staged-to-live")
    end
    if files.live == "target" and files.staged == "target" then
      return action("remove-duplicate-staged-target")
    end
    if files.live == "target" and files.staged == "absent" then
      return action("set-phase", "target-placed")
    end
    return refuse("disk-state-conflict", "placing-target")
  end

  if phase == "target-placed" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.live ~= "target" or files.staged ~= "absent"
        or files.rejected ~= "absent"
        or not prior_file_state_ok(journal, files) then
      return refuse("disk-state-conflict", "target-placed")
    end
    return action("set-phase", "pending-restart")
  end

  if phase == "pending-restart" then
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.live ~= "target" or files.staged ~= "absent"
        or files.rejected ~= "absent"
        or not prior_file_state_ok(journal, files) then
      return refuse("disk-state-conflict", "pending-restart")
    end
    if snapshot.same_session then return action("wait-restart") end
    if snapshot.probe == "target-ok" then return action("set-phase", "active") end
    -- One REAPER session contributes at most one failure. Its verdict cannot
    -- change while it runs, so it waits for a restart instead of probing again.
    if snapshot.same_failure_session then return action("wait-restart") end
    if snapshot.probe == "not-run" then return action("run-activation-probe") end
    -- Only an artifact-attributed "failed" is evidence against the target.
    -- Every other answer, including a probe that could not run at all, says
    -- nothing about the placed file and waits for a session that can prove it.
    if snapshot.probe ~= "failed" then return action("wait-restart") end
    if journal.failures == 0 then return action("record-probe-failure") end
    if journal.failures == 1 then
      return action("prepare-rollback", "rollback-prepared")
    end
    return refuse("journal-invalid", "pending-failures")
  end

  if phase == "active" then
    if files.live ~= "target" or files.staged ~= "absent"
        or files.rejected ~= "absent"
        or not prior_file_state_ok(journal, files) then
      return refuse("disk-state-conflict", "active-files")
    end
    if sentinel == "absent" then return action("complete-active") end
    if sentinel ~= "activation" then return refuse("sentinel-orphaned") end
    if snapshot.probe == "target-ok" then return action("clear-sentinel") end
    if snapshot.same_failure_session then return action("wait-restart") end
    if snapshot.probe == "not-run" then return action("run-activation-probe") end
    -- Only an artifact-attributed "failed" is evidence against the target.
    -- Every other answer, including a probe that could not run at all, says
    -- nothing about the placed file and waits for a session that can prove it.
    if snapshot.probe ~= "failed" then return action("wait-restart") end
    if journal.failures == 0 then return action("record-probe-failure") end
    if journal.failures == 1 then
      return action("prepare-rollback", "rollback-prepared")
    end
    return refuse("journal-invalid", "active-failures")
  end

  if phase == "rollback-prepared" then
    if not snapshot.quarantine then return action("write-quarantine") end
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.live == "absent" and files.rejected == "target" then
      return action("set-phase", "target-rejected")
    end
    if not snapshot.same_session then return action("record-rollback-session") end
    if files.live == "target" and files.rejected == "absent" then
      return action("set-phase", "rejecting-target")
    end
    return refuse("disk-state-conflict", "rollback-prepared")
  end

  if phase == "rejecting-target" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if not snapshot.same_session and files.live == "target" then
      return action("record-rollback-session")
    end
    if files.live == "target" and files.rejected == "absent" then
      return action("rename-live-to-rejected")
    end
    if files.live == "target" and files.rejected == "target" then
      if not snapshot.same_session then
        return action("record-rollback-session")
      end
      return action("remove-duplicate-live-target")
    end
    if files.live == "absent" and files.rejected == "target" then
      return action("set-phase", "target-rejected")
    end
    return refuse("disk-state-conflict", "rejecting-target")
  end

  if phase == "target-rejected" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if files.live ~= "absent" or files.rejected ~= "target" then
      return refuse("disk-state-conflict", "target-rejected")
    end
    if journal.previous_kind == "absent" then
      if files.backup ~= "absent" then
        return refuse("disk-state-conflict", "fresh-backup")
      end
      return action("set-phase", "previous-restored")
    end
    if files.backup == "previous" then
      if not snapshot.same_session then return action("record-rollback-session") end
      return action("set-phase", "restoring-previous")
    end
    return refuse("rollback-unverified", "backup")
  end

  if phase == "restoring-previous" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    if sentinel ~= "activation" then return refuse("sentinel-missing") end
    if not snapshot.same_session and files.live == "absent" then
      return action("record-rollback-session")
    end
    if files.live == "absent" and files.backup == "previous"
        and files.rejected == "target" then
      return action("rename-backup-to-live")
    end
    if files.live == "previous" and files.backup == "previous"
        and files.rejected == "target" then
      return action("remove-duplicate-backup-previous")
    end
    if files.live == "previous" and files.backup == "absent"
        and files.rejected == "target" then
      return action("set-phase", "previous-restored")
    end
    return refuse("rollback-unverified", "restoring-previous")
  end

  if phase == "previous-restored" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    local previous_ok = journal.previous_kind == "absent"
      and files.live == "absent" and files.backup == "absent"
      or journal.previous_kind == "engine"
      and files.live == "previous" and files.backup == "absent"
    if not previous_ok or files.rejected ~= "target" then
      return refuse("rollback-unverified", "previous-restored")
    end
    if sentinel == "activation" then return action("write-rollback-sentinel") end
    if sentinel == "rollback" then
      return action("set-phase", "rolled-back-pending-restart")
    end
    return refuse("sentinel-missing")
  end

  if phase == "rolled-back-pending-restart" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    if sentinel ~= "rollback" then return refuse("sentinel-missing") end
    local disk_ok = journal.previous_kind == "engine"
      and files.live == "previous" and files.backup == "absent"
      or journal.previous_kind == "absent"
      and files.live == "absent" and files.backup == "absent"
    if not disk_ok or files.staged ~= "absent" or files.rejected ~= "target" then
      return refuse("rollback-unverified", "pending-files")
    end
    if snapshot.same_session then return action("wait-restart") end
    local expected_probe = journal.previous_kind == "engine"
      and "previous-ok" or "absent-ok"
    if snapshot.probe == "not-run" then return action("run-rollback-probe") end
    if snapshot.probe == expected_probe then
      return action("set-phase", "rolled-back")
    end
    -- Only an artifact-attributed "failed" is evidence against the target.
    -- Every other answer, including a probe that could not run at all, says
    -- nothing about the placed file and waits for a session that can prove it.
    if snapshot.probe ~= "failed" then return action("wait-restart") end
    return refuse("rollback-unverified", "probe")
  end

  if phase == "rolled-back" then
    if not snapshot.quarantine then return refuse("quarantine-missing") end
    local disk_ok = journal.previous_kind == "engine"
      and files.live == "previous" and files.backup == "absent"
      or journal.previous_kind == "absent"
      and files.live == "absent" and files.backup == "absent"
    if not disk_ok or files.staged ~= "absent" or files.rejected ~= "target" then
      return refuse("rollback-unverified", "final-files")
    end
    if sentinel == "absent" then return action("complete-rolled-back") end
    if sentinel ~= "rollback" then return refuse("sentinel-orphaned") end
    local expected_probe = journal.previous_kind == "engine"
      and "previous-ok" or "absent-ok"
    if snapshot.probe == "not-run" then return action("run-rollback-probe") end
    if snapshot.probe == expected_probe then return action("clear-sentinel") end
    -- Only an artifact-attributed "failed" is evidence against the target.
    -- Every other answer, including a probe that could not run at all, says
    -- nothing about the placed file and waits for a session that can prove it.
    if snapshot.probe ~= "failed" then return action("wait-restart") end
    return refuse("rollback-unverified", "final-probe")
  end

  return refuse("journal-invalid", "unhandled-phase")
end

-- =============================================================================
-- Shared-runtime policy
-- =============================================================================
--
-- One Engine on a machine, more than one app that uses it. Two words carry the
-- whole policy and must never share an outcome.
--
-- INVALID means the bytes are wrong: the artifact is missing, unreadable,
-- quarantined for that digest, or described by a record that does not describe
-- it. An invalid Engine is what an app repairs.
--
-- INCOMPATIBLE means the bytes are healthy and this app cannot use them: a
-- different `core_abi`, which is pinned exactly, or a subsystem version or an
-- export this app calls that the Engine does not have. An incompatible Engine
-- is refused for use and left exactly where it is. It is never replaced, never
-- rolled back and never quarantined, because nothing is wrong with it.
--
-- An app therefore repairs or upgrades only an invalid or older Engine. A
-- newer Engine it cannot use is another app's working runtime.

local IDENTITY_PLACED_STATES = {
  absent = true, unreadable = true, present = true,
}
local IDENTITY_RECORD_STATES = {
  absent = true, unreadable = true, invalid = true, valid = true,
}

-- What is installed for one target, and whether that is known at all.
--
-- Known needs the installer's own status entry and the bytes in the load path
-- to agree: the entry exists, is readable, validates, and its digest is the
-- digest of those bytes. The status entry is the authority, not the journal,
-- which exists only while a transaction is open, and not another app's bundled
-- descriptor, which describes that app's payload and proves nothing about the
-- binary on this machine.
--
-- Unknown is neither valid nor invalid. It authorizes no automatic replacement
-- and no use of the binary; the only way out is a repair the user confirms.
-- Confirmed absence is not unknown: an artifact path that is definitely empty
-- says exactly what is installed, which is nothing.
function EngineInstaller.decide_identity(input)
  if type(input) ~= "table" then return {state = "unknown", reason = "input"} end
  local placed = type(input.placed) == "table" and input.placed or {}
  local record = type(input.record) == "table" and input.record or {}
  if not IDENTITY_PLACED_STATES[placed.state] then
    return {state = "unknown", reason = "placed-state"}
  end
  if not IDENTITY_RECORD_STATES[record.state] then
    return {state = "unknown", reason = "record-state"}
  end
  if placed.state == "absent" then return {state = "absent"} end
  if placed.state == "unreadable" or not is_lower_sha256(placed.sha256) then
    return {state = "unknown", reason = "bytes-unreadable"}
  end
  if record.state ~= "valid" then
    return {state = "unknown", reason = "record-" .. record.state}
  end
  if not parse_version(record.version) or not is_lower_sha256(record.sha256) then
    return {state = "unknown", reason = "record-invalid"}
  end
  if record.sha256 ~= placed.sha256 then
    return {state = "unknown", reason = "record-mismatch"}
  end
  return {state = "known", version = record.version, sha256 = placed.sha256}
end

-- Healthy bytes an app cannot use. The ABI is the seam and is matched exactly;
-- subsystems grow additively inside one ABI, so a version at or above what the
-- app calls is compatible and a version below it is not; an export the app
-- calls and the Engine does not declare is the same answer by another route.
function EngineInstaller.decide_compatibility(input)
  if type(input) ~= "table" then
    return {state = "incompatible", reason = "input"}
  end
  if input.core_abi ~= input.required_abi then
    return {
      state = "incompatible",
      reason = "core-abi",
      detail = tostring(input.core_abi),
    }
  end
  local declared = type(input.subsystems) == "table" and input.subsystems or {}
  for name, minimum in pairs(input.required_subsystems or {}) do
    local value = declared[name]
    if type(value) ~= "number" or value ~= math.floor(value)
        or value < minimum then
      return {state = "incompatible", reason = "subsystem", detail = name}
    end
  end
  local exports = type(input.exports) == "table" and input.exports or {}
  for _, name in ipairs(input.required_exports or {}) do
    if exports[name] ~= true then
      return {state = "incompatible", reason = "export", detail = name}
    end
  end
  return {state = "compatible"}
end

local WITHDRAWN_STATES = {clear = true, withdrawn = true, unusable = true}

local function compatibility_detail(compatibility)
  if type(compatibility) ~= "table" or compatibility.reason == nil then
    return nil
  end
  if compatibility.detail == nil then return tostring(compatibility.reason) end
  return tostring(compatibility.reason) .. ":" .. tostring(compatibility.detail)
end

-- Whether this app may call the Engine this process has loaded.
--
-- Loaded, never placed. Replacing the file on disk does not change the image
-- this process is running, so every call stays gated on the loaded image,
-- identified by the `loaded_file_sha256` the contract reports, and a
-- replacement is certified only after the restart that loads it. An Engine
-- that does not say which file it came from cannot be attributed to anything
-- and is not used.
--
-- The withdrawal record is read first, before this check and before the
-- install check, so a digest withdrawn after this app last shipped stops being
-- called even though this app's own descriptor knows nothing about it.
function EngineInstaller.decide_use(input)
  if type(input) ~= "table" then return refuse("use-input") end
  if not WITHDRAWN_STATES[input.withdrawn] then
    return refuse("use-input", "withdrawn-state")
  end
  -- Not empty. A record this body cannot read may be hiding a withdrawal, so
  -- the Engine is not called until a user-confirmed repair rewrites it.
  if input.withdrawn == "unusable" then
    return refuse("withdrawal-record-unusable")
  end
  local loaded = type(input.loaded) == "table" and input.loaded or {}
  if loaded.state == "absent" then return refuse("engine-absent") end
  if loaded.state ~= "present" then
    return refuse("use-input", "loaded-state")
  end
  if not is_lower_sha256(loaded.sha256) then
    return refuse("loaded-identity-unknown")
  end
  if input.withdrawn == "withdrawn" then return refuse("withdrawn") end
  if input.quarantined == true then return refuse("quarantined") end
  local compatibility = type(input.compatibility) == "table"
    and input.compatibility or {state = "incompatible", reason = "unknown"}
  if compatibility.state ~= "compatible" then
    return refuse("incompatible", compatibility_detail(compatibility))
  end
  if input.minimum_version ~= nil then
    local comparison = EngineInstaller.compare_versions(
      tostring(loaded.version or ""), tostring(input.minimum_version))
    if comparison == nil then return refuse("loaded-version-unreadable") end
    if comparison < 0 then
      return refuse("below-minimum", tostring(loaded.version))
    end
  end
  return {kind = "use", reason = "compatible"}
end

local INSTALL_JOURNAL_STATES = {
  absent = true, same = true, other = true, invalid = true, unreadable = true,
}

-- Whether this app may put its own bundle into the load path for one target.
--
-- Four answers, and the three that are not "install" are different on purpose:
-- `none` leaves a working runtime alone, `repair-confirm` says only the user
-- can authorize a replacement, and `refuse` says this app may not act at all.
--
-- The three outcomes that must never share a rule:
--   confirmed absence  -> a fresh installation of this app's bundle, whatever
--                         its version, because nothing is being replaced;
--   unknown identity   -> no automatic action, only a repair the user confirms
--                         after being told what will be replaced;
--   known identity whose digest activation has quarantined -> the single
--                         exception to never downgrading.
-- A healthy newer Engine is never replaced by any of them.
function EngineInstaller.decide_install(input)
  if type(input) ~= "table" then return refuse("install-input") end
  if not WITHDRAWN_STATES[input.withdrawn] then
    return refuse("install-input", "withdrawn-state")
  end
  if input.withdrawn == "unusable" then
    return refuse("withdrawal-record-unusable")
  end
  if input.lock == "held" then return refuse("lock-held") end
  if input.lock ~= "owned" then return refuse("lock-undecidable") end
  local target_ok, target_why = EngineInstaller.validate_target(input.target)
  if not target_ok then return refuse("target-invalid", target_why) end

  local journal_state = input.journal_state or "absent"
  if not INSTALL_JOURNAL_STATES[journal_state] then
    return refuse("install-input", "journal-state")
  end
  if journal_state == "invalid" or journal_state == "unreadable" then
    return refuse("journal-invalid")
  end
  if journal_state == "same" then
    return {kind = "install", reason = "resume"}
  end
  -- Another app's transaction. Its recorded target and recovery state are its
  -- own; substituting this app's bundle into it would place bytes no journal
  -- describes.
  if journal_state == "other" then return refuse("transaction-conflict") end

  if input.withdrawn == "withdrawn" then return refuse("target-withdrawn") end
  if input.quarantined == true then return refuse("target-quarantined") end
  -- The withdrawn digest in the load path is the removal transition's work,
  -- not an installation's. Installing over it would race that removal.
  if input.installed_withdrawn == true then
    return {kind = "none", reason = "installed-withdrawn"}
  end

  local identity = type(input.identity) == "table" and input.identity or {}
  if identity.state == "absent" then
    return {kind = "install", reason = "absent"}
  end
  if identity.state ~= "known" then
    return {
      kind = "repair-confirm",
      reason = "identity-unknown",
      detail = identity.reason,
    }
  end
  if not parse_version(identity.version)
      or not is_lower_sha256(identity.sha256) then
    return {
      kind = "repair-confirm",
      reason = "identity-unknown",
      detail = "record-invalid",
    }
  end

  local comparison = EngineInstaller.compare_versions(
    input.target.version, identity.version)
  if comparison == nil then
    return {
      kind = "repair-confirm",
      reason = "identity-unknown",
      detail = "version-unreadable",
    }
  end
  if comparison > 0 then return {kind = "install", reason = "upgrade"} end
  if comparison == 0 then
    if input.target.sha256 == identity.sha256 then
      return {kind = "none", reason = "already-current"}
    end
    -- Activation proved these exact installed bytes bad. Same version, other
    -- digest: the bundle may take their place.
    if input.installed_quarantined == true then
      return {kind = "install", reason = "quarantine-exception"}
    end
    -- One version string, two binaries. Version equality alone authorizes
    -- nothing; the user is asked rather than the file silently overwritten.
    if input.replace_equal_version == true then
      return {kind = "install", reason = "equal-version-replace"}
    end
    return {kind = "repair-confirm", reason = "equal-version-conflict"}
  end
  -- The installed Engine is newer than this app's bundle.
  if input.installed_quarantined == true then
    return {kind = "install", reason = "quarantine-exception"}
  end
  if input.installed_compatibility == "incompatible" then
    -- Healthy bytes this app cannot call. Refused for use, left in place, and
    -- never downgraded into something this app happens to prefer.
    return {kind = "none", reason = "installed-incompatible"}
  end
  return {kind = "none", reason = "installed-newer"}
end

return EngineInstaller
-- END ENGINE COMPONENT Installer
end)()

EngineKit.InstallerPackage = (function()
-- BEGIN ENGINE COMPONENT InstallerPackage
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- =============================================================================
-- Engine release-package descriptor
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
-- =============================================================================
--
-- The release process writes one descriptor only after every artifact has
-- passed its platform architecture and integrity gate. This module validates
-- that local descriptor and returns the one target admitted for the current
-- platform.

local Package = {}

Package.SCHEMA = 3
Package.REQUIRED_CORE_ABI = 2
Package.REQUIRED_BUILD_CHANNEL = "production"
Package.REQUIRED_SUBSYSTEMS = {
  core = 1,
  client = 1,
  inference = 2,
  input_media = 1,
  openrouter_catalog = 1,
  stateless_helpers = 1,
}
Package.REQUIRED_INFERENCE_PROFILES = {
  "custom_openai_chat_v1",
  "custom_openai_responses_v1",
  "local_openai_chat_v1",
  "local_openai_responses_v1",
  "local_openai_chat_private_v1",
  "local_openai_responses_private_v1",
}
Package.PLATFORMS = {
  "win-x64", "win-arm64", "mac-arm64", "mac-x64",
  "linux-x64", "linux-arm64",
}
Package.SIGNATURE_POLICY = {
  ["win-x64"] = "signed-timestamped",
  ["win-arm64"] = "signed-timestamped",
  ["mac-arm64"] = "developer-id-notarized",
  ["mac-x64"] = "developer-id-notarized",
  ["linux-x64"] = "sha256",
  ["linux-arm64"] = "sha256",
}

local ROOT_FIELDS = {
  schema = true,
  version = true,
  core_abi = true,
  build_channel = true,
  subsystems = true,
  protocols = true,
  inference_profiles = true,
  artifacts = true,
  distribution = true,
  payload_layout = true,
  -- Optional and additive. It carries the withdrawal statement this release
  -- was signed with: the exact signed payload text, its signature, and the key
  -- that signed it. The payload is carried verbatim rather than rebuilt from
  -- the decoded list, because a signature covers bytes and re-encoding a table
  -- is not the same bytes. A descriptor without it withdraws nothing, which is
  -- what every descriptor written before this field existed says.
  withdrawal = true,
}

local WITHDRAWAL_FIELDS = {
  payload = true,
  signature = true,
  key_id = true,
}

local ARTIFACT_FIELDS = {
  filename = true,
  sha256 = true,
  signature = true,
}

-- Every key the allowlist does not name, sorted and joined, rather than
-- whichever one `pairs` reached first. A table's iteration order is a property
-- of the process that built it, so reporting one key made the same defect
-- answer with a different field name on different runs, and a caller removing
-- the reported field learned the next one only by running again. The list is
-- capped because one of the tables validated here is a file this app did not
-- write.
local UNKNOWN_FIELD_LIMIT = 8

local function unknown_field(value, allowed)
  if type(value) ~= "table" then return nil end
  local names = {}
  for key in pairs(value) do
    if not allowed[key] then names[#names + 1] = tostring(key) end
  end
  if #names == 0 then return nil end
  table.sort(names)
  if #names <= UNKNOWN_FIELD_LIMIT then return table.concat(names, ",") end
  return table.concat(names, ",", 1, UNKNOWN_FIELD_LIMIT)
    .. ",+" .. tostring(#names - UNKNOWN_FIELD_LIMIT)
end

-- The one place a target is built from a descriptor's artifact, so the target
-- this module hands to a caller and the target it validates each platform
-- against cannot be two different shapes. They were, and the four fields the
-- decision core admits were the ones checked here while the caller was given
-- nine, which the core refused on the first extra key it reached.
--
-- A target is an identity and nothing else: which slice, which file, which
-- version, which bytes. What the descriptor promises about the Engine inside
-- that file travels separately, through `Package.expected_contract`.
local function artifact_target(value, platform, artifact)
  return {
    platform = platform,
    filename = artifact.filename,
    version = value.version,
    sha256 = artifact.sha256,
  }
end

local function plain_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return false
    end
    count = count + 1
  end
  return count == #value
end

local function exact_subsystems(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for name, expected in pairs(Package.REQUIRED_SUBSYSTEMS) do
    if value[name] ~= expected then return false end
    count = count + 1
  end
  for name in pairs(value) do
    if Package.REQUIRED_SUBSYSTEMS[name] == nil then return false end
  end
  return count == 6
end

local function valid_protocols(value)
  if not plain_array(value) then return false end
  local seen = {}
  for _, protocol in ipairs(value) do
    if type(protocol) ~= "string" or protocol == ""
        or protocol:match("^[a-z0-9_]+$") == nil or seen[protocol] then
      return false
    end
    seen[protocol] = true
  end
  return true
end

local PROFILE_PROTOCOLS = {
  custom_openai_chat_v1 = "openai_chat_completions",
  custom_openai_responses_v1 = "openai_responses",
  local_openai_chat_v1 = "openai_chat_completions",
  local_openai_responses_v1 = "openai_responses",
  local_openai_chat_private_v1 = "openai_chat_completions",
  local_openai_responses_private_v1 = "openai_responses",
}

local function exact_inference_profiles(value, protocols)
  if not plain_array(value) or not plain_array(protocols)
      or #value ~= #Package.REQUIRED_INFERENCE_PROFILES then
    return false
  end
  local protocol_set = {}
  for _, protocol in ipairs(protocols) do protocol_set[protocol] = true end
  for index, expected in ipairs(Package.REQUIRED_INFERENCE_PROFILES) do
    if value[index] ~= expected
        or protocol_set[PROFILE_PROTOCOLS[expected]] ~= true then
      return false
    end
  end
  return true
end

-- P-08 / L-15. `distribution = "windows-x64-acceptance"` narrows a descriptor to
-- win-x64 and relaxes that artifact's signature policy to a bare SHA-256, which
-- is what an unsigned Windows acceptance build needs and what no ordinary
-- install may ever be given. The marker is therefore admitted only on an
-- install that carries the local acceptance token, an unmanifested file the
-- host looks for and the installer never creates; every other install reads a
-- marked descriptor as `package-distribution` and shows the same state as any
-- other invalid package. The Batch 3 line of
-- `Dev/Engine/ENGINE_AUDIT_1.0.2_2026-09-06.md` records the token's exact name
-- and location.
function Package.validate(value, core, options)
  if type(core) ~= "table" or type(core.validate_target) ~= "function"
      or type(core.parse_version) ~= "function" then
    return false, "core"
  end
  if type(value) ~= "table" then return false, "package-not-table" end
  local root_extra = unknown_field(value, ROOT_FIELDS)
  if root_extra then return false, "package-unknown-field:" .. root_extra end
  if value.schema ~= Package.SCHEMA then return false, "package-schema" end
  if value.payload_layout ~= nil
      and value.payload_layout ~= "native-bytes-txt-v1" then
    return false, "package-payload-layout"
  end
  if not core.parse_version(value.version) then return false, "package-version" end
  if value.core_abi ~= Package.REQUIRED_CORE_ABI then
    return false, "package-core-abi"
  end
  if value.build_channel ~= Package.REQUIRED_BUILD_CHANNEL then
    return false, "package-build-channel"
  end
  if not exact_subsystems(value.subsystems) then
    return false, "package-subsystems"
  end
  if not valid_protocols(value.protocols) then
    return false, "package-protocols"
  end
  if not exact_inference_profiles(value.inference_profiles,
      value.protocols) then
    return false, "package-inference-profiles"
  end
  if type(value.artifacts) ~= "table" then
    return false, "package-artifacts"
  end

  if value.withdrawal ~= nil then
    if type(value.withdrawal) ~= "table" then
      return false, "package-withdrawal"
    end
    local withdrawal_extra = unknown_field(value.withdrawal, WITHDRAWAL_FIELDS)
    if withdrawal_extra then
      return false, "package-withdrawal-field:" .. withdrawal_extra
    end
    if type(value.withdrawal.payload) ~= "string"
        or value.withdrawal.payload == ""
        or #value.withdrawal.payload > 64 * 1024 then
      return false, "package-withdrawal-payload"
    end
    if type(value.withdrawal.signature) ~= "string"
        or value.withdrawal.signature == ""
        or #value.withdrawal.signature > 4096
        or value.withdrawal.signature:match("^[A-Za-z0-9+/=_%-]+$") == nil then
      return false, "package-withdrawal-signature"
    end
    if type(value.withdrawal.key_id) ~= "string" or value.withdrawal.key_id == ""
        or #value.withdrawal.key_id > 128
        or value.withdrawal.key_id:match("^[A-Za-z0-9._%-]+$") == nil then
      return false, "package-withdrawal-key-id"
    end
  end

  local windows_acceptance = value.distribution == "windows-x64-acceptance"
    and type(options) == "table" and options.acceptance_allowed == true
  if value.distribution ~= nil and not windows_acceptance then
    return false, "package-distribution"
  end
  local platforms = windows_acceptance and {"win-x64"} or Package.PLATFORMS
  local platform_set = {}
  for _, platform in ipairs(platforms) do platform_set[platform] = true end
  local platform_extra = unknown_field(value.artifacts, platform_set)
  if platform_extra then
    return false, "package-unknown-platform:" .. platform_extra
  end

  for _, platform in ipairs(platforms) do
    local artifact = value.artifacts[platform]
    if type(artifact) ~= "table" then
      return false, "package-missing-platform:" .. platform
    end
    local artifact_extra = unknown_field(artifact, ARTIFACT_FIELDS)
    if artifact_extra then
      return false, "package-artifact-field:" .. platform .. ":" .. artifact_extra
    end
    local signature = windows_acceptance and "sha256" or Package.SIGNATURE_POLICY[platform]
    if artifact.signature ~= signature then
      return false, "package-signature-policy:" .. platform
    end
    local target = artifact_target(value, platform, artifact)
    local target_ok, target_why = core.validate_target(target)
    if not target_ok then
      return false, "package-target:" .. platform .. ":" .. tostring(target_why)
    end
  end

  -- Every target is its own artifact, and no two of them share a name or a
  -- digest. `validate_target` already pins each filename to its target, so a
  -- shared name can only reach here from a descriptor written by hand; a
  -- shared digest is what a build that copied one slice over another
  -- produces, and that is the defect this catches.
  if not windows_acceptance then
    local names, digests = {}, {}
    for _, platform in ipairs(platforms) do
      local artifact = value.artifacts[platform]
      if names[artifact.filename] then
        return false, "package-shared-filename:" .. platform
      end
      if digests[artifact.sha256] then
        return false, "package-shared-sha256:" .. platform
      end
      names[artifact.filename] = platform
      digests[artifact.sha256] = platform
    end
  end
  return true
end

-- The kit entries a descriptor's withdrawal statement produces, one per
-- digest the signed payload names. Nothing is authorized here: the caller
-- still verifies the signature and the kit still requires the payload to name
-- the digest an entry claims. This only unpacks.
function Package.withdrawal_entries(value, decode)
  if type(value) ~= "table" or type(value.withdrawal) ~= "table" then
    return {}
  end
  if type(decode) ~= "function" then return nil, "decode" end
  local ok, payload = pcall(decode, value.withdrawal.payload)
  if not ok or type(payload) ~= "table" then return nil, "payload" end
  if not plain_array(payload.withdrawn) then return nil, "payload-list" end
  local out = {}
  for _, digest in ipairs(payload.withdrawn) do
    if type(digest) ~= "string" or #digest ~= 64
        or digest:match("^[0-9a-f]+$") == nil then
      return nil, "payload-digest"
    end
    out[#out + 1] = {
      sha256 = digest,
      payload = value.withdrawal.payload,
      signature = value.withdrawal.signature,
      key_id = value.withdrawal.key_id,
    }
  end
  return out
end

function Package.target_for(value, platform, core, options)
  local valid, why = Package.validate(value, core, options)
  if not valid then return nil, why end
  local artifact = value.artifacts[platform]
  if not artifact then return nil, "package-platform-unsupported" end
  return artifact_target(value, platform, artifact)
end

-- The descriptor selects the bundle path without changing install identity.
-- Callers must validate the descriptor first. Unknown values have no suffix.
function Package.payload_suffix(value)
  if type(value) ~= "table" then return nil end
  if value.payload_layout == nil then return "" end
  if value.payload_layout == "native-bytes-txt-v1" then return ".txt" end
  return nil
end

-- What this descriptor promises about the Engine inside its artifacts, for the
-- caller that loads one and compares its contract against the package that
-- authorized the install. Five fields, every one of them pinned by
-- `Package.validate` before a target is ever returned.
--
-- It is deliberately not part of the target. The decision core admits the four
-- identity fields and refuses every other key, which is what makes a target a
-- thing the core has validated in full rather than a bag with unchecked
-- passengers; these five are checked here and nowhere in the core.
--
-- Nothing is validated in this function. It unpacks a descriptor the caller
-- has already put through `target_for`, exactly as `withdrawal_entries` does,
-- and a descriptor that did not validate promises nothing.
function Package.expected_contract(value)
  if type(value) ~= "table" then return nil end
  return {
    core_abi = value.core_abi,
    build_channel = value.build_channel,
    subsystems = value.subsystems,
    protocols = value.protocols,
    inference_profiles = value.inference_profiles,
  }
end

return Package
-- END ENGINE COMPONENT InstallerPackage
end)()

EngineKit.InstallerRuntime = (function()
-- BEGIN ENGINE COMPONENT InstallerRuntime
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- =============================================================================
-- Engine installer runtime
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
-- =============================================================================
--
-- This module adapts the pure EngineInstaller decision core to durable records
-- and filesystem operations. One call executes at most one decision action.
-- Every later call reloads and hashes the durable state before it asks the core
-- again, so a process restart does not depend on in-memory progress.

local Runtime = {}
Runtime.__index = Runtime

local QUARANTINE_FIELDS = {schema = true, entries = true}
local QUARANTINE_ENTRY_FIELDS = {
  version = true,
  sha256 = true,
  transaction_id = true,
  reason = true,
}

-- The status record is indexed by target key, one entry per slice, so a machine
-- that installs a second target cannot overwrite the first target's evidence.
-- The kit reads exactly the schema it writes: any other number is refused as
-- `status-schema` rather than interpreted, because a record this body cannot
-- read is not one it may act on.
local STATUS_SCHEMA = 1
local STATUS_FIELDS = {schema = true, targets = true}

local STATUS_ENTRY_FIELDS = {
  outcome = true,
  target_version = true,
  target_sha256 = true,
  transaction_id = true,
  active_kind = true,
  active_version = true,
  active_sha256 = true,
  -- The load-path name this entry describes. The entry says which file its
  -- digest was taken from rather than leaving it to be inferred.
  filename = true,
  -- A placed target whose activation no process has been able to certify yet.
  -- It holds the transaction verbatim, so the journal is free for another
  -- target's install while this one waits for a process that can load it.
  pending = true,
  -- What a withdrawal removal did to this target's load path.
  withdrawal = true,
}

local STATUS_WITHDRAWAL_FIELDS = {
  sha256 = true,
  state = true,
  transaction_id = true,
}

local STATUS_WITHDRAWAL_STATES = {
  -- The digest is still in the load path. The kit reports it present and
  -- unused, never "removed at next restart".
  pending = true,
  removed = true,
  -- Another app placed different bytes before the removal ran. Nothing was
  -- removed, and that other install is healthy.
  superseded = true,
  absent = true,
}

-- The durable record of which Engine digests have been withdrawn, shared by
-- every app on this machine and read before the install check and before the
-- use check. Each entry carries the signed payload it came from and that
-- payload's signature; a reader treats a digest as withdrawn only after an
-- authorized signature is verified over a payload that names it. A recorded
-- hash, or a signer's name, proves nothing on its own.
--
-- TRUST BOUNDARY, stated plainly. Append-only is a rule between cooperating
-- apps, not an enforcement. Any process running as this user can delete this
-- file, ignore it, or replace the Engine binary directly, and nothing here
-- prevents that or claims to. What the record buys is that an app which has
-- not shipped since a withdrawal still stops calling and installing the
-- withdrawn digest, because some other cooperating app wrote it down.
local WITHDRAWN_FIELDS = {schema = true, entries = true}
local WITHDRAWN_ENTRY_FIELDS = {
  sha256 = true,
  payload = true,
  signature = true,
  key_id = true,
}

Runtime.WITHDRAWN_PAYLOAD_BYTES = 64 * 1024
Runtime.WITHDRAWN_SIGNATURE_BYTES = 4096
Runtime.WITHDRAWN_MAX_ENTRIES = 256

-- The durable statement that an Engine was proven active, is not in the live
-- slot, and could not be put back. It outlives the journal that described the
-- interrupted transaction, so a later repair retries the restoration instead of
-- reporting an idle installer over an empty live slot.
local RECOVERY_FIELDS = {
  schema = true,
  filename = true,
  active_version = true,
  active_sha256 = true,
  transaction_id = true,
  reason = true,
}

-- The two phases whose sentinel describes the rollback rather than the
-- activation. Repair rebuilds the sentinel a valid journal's phase requires.
local SENTINEL_ROLLBACK_PHASES = {
  ["rolled-back-pending-restart"] = true,
  ["rolled-back"] = true,
}

-- The shared lock name, and the reclaim marker that names one instance's
-- intent to move an artifact away from it. The marker is a plain file on both
-- hosts, so one directory listing of files sees every one of them.
local LOCK_NAME = "install.lock"
local RECLAIM_PREFIX = LOCK_NAME .. ".reclaim."
local RECLAIM_PATTERN = "^" .. LOCK_NAME:gsub("%.", "%%.")
  .. "%.reclaim%.(inst_[A-Za-z0-9_%-]+)$"

local ROLLBACK_PHASES = {
  ["rollback-prepared"] = true,
  ["rejecting-target"] = true,
  ["target-rejected"] = true,
  ["restoring-previous"] = true,
  ["previous-restored"] = true,
  ["rolled-back-pending-restart"] = true,
  ["rolled-back"] = true,
}

local function slash(path)
  local out = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
  return out
end

local function join(left, right)
  return slash(left) .. "/" .. tostring(right or ""):gsub("^/+", "")
end

local function parent_dir(path)
  return tostring(path):match("^(.*)/[^/]+$")
end

local function safe_token(value)
  return tostring(value or ""):gsub("[^A-Za-z0-9_%-]", "_")
end

-- Refusal text reaches the recovery record, which is validated like every
-- other durable record, so it is reduced to one bounded lowercase token.
local function recovery_reason(value)
  local text = tostring(value or "unknown"):lower():gsub("[^a-z0-9]+", "-")
  text = text:gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 48)
  if text == "" then return "unknown" end
  return text
end

local function copy_table(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, item in pairs(value) do
    out[copy_table(key, seen)] = copy_table(item, seen)
  end
  return out
end

-- Every key the allowlist does not name, sorted and joined, rather than
-- whichever one `pairs` reached first. A table's iteration order is a property
-- of the process that built it, so reporting one key made the same defect
-- answer with a different field name on different runs, and a caller removing
-- the reported field learned the next one only by running again. The list is
-- capped because one of the tables validated here is a file this app did not
-- write.
local UNKNOWN_FIELD_LIMIT = 8

local function unknown_field(value, allowed)
  if type(value) ~= "table" then return nil end
  local names = {}
  for key in pairs(value) do
    if not allowed[key] then names[#names + 1] = tostring(key) end
  end
  if #names == 0 then return nil end
  table.sort(names)
  if #names <= UNKNOWN_FIELD_LIMIT then return table.concat(names, ",") end
  return table.concat(names, ",", 1, UNKNOWN_FIELD_LIMIT)
    .. ",+" .. tostring(#names - UNKNOWN_FIELD_LIMIT)
end

local function is_plain_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for _ in pairs(value) do count = count + 1 end
  return count == #value
end

local function is_lower_sha256(value)
  return type(value) == "string" and #value == 64
    and value:match("^[0-9a-f]+$") ~= nil
end

local function result(kind, detail)
  return {kind = kind, detail = detail}
end

function Runtime.new(options)
  assert(type(options) == "table", "Engine installer runtime options required")
  assert(type(options.core) == "table", "Engine installer core required")
  assert(type(options.json) == "table", "JSON adapter required")
  assert(type(options.hash_bytes) == "function", "hash_bytes adapter required")
  assert(type(options.mkdir) == "function", "mkdir adapter required")
  assert(type(options.instance_id) == "string", "instance id required")
  assert(type(options.session_id) == "string", "session id required")
  assert(options.instance_id:match("^inst_[A-Za-z0-9_%-]+$") ~= nil,
    "invalid instance id")
  assert(options.session_id:match("^session_[A-Za-z0-9_%-]+$") ~= nil,
    "invalid session id")

  local self = setmetatable({}, Runtime)
  self.core = options.core
  self.json = options.json
  self.hash_bytes = options.hash_bytes
  self.hash_file = options.hash_file
  self.mkdir = options.mkdir
  self.path_present = options.path_present
  self.instance_liveness = options.instance_liveness
  self.enumerate_files = options.enumerate_files
  self.loaded_version = options.loaded_version
  self.probe = options.probe
  self.log = options.log or function() end
  self.io = options.io or io
  self.os = options.os or os
  self.is_windows = options.is_windows == true
  -- The target key this process can load. It is what the status record is
  -- indexed by, what a resumed activation is matched against, and the reason a
  -- process of another architecture never certifies or condemns this one.
  self.target_key = nil
  if self.core.is_target_key ~= nil and self.core.is_target_key(options.target_key) then
    self.target_key = options.target_key
  end
  -- The signature primitive an app supplies for the withdrawal record. The kit
  -- owns the rule that a signature must cover the digest it authorizes; the
  -- app owns which keys are authorized and how a signature is checked.
  self.verify_signature = options.verify_signature
  -- The withdrawal statement this app's own bundle descriptor carries. It is
  -- merged into the shared record once per session, after the descriptor has
  -- been authenticated, and never enforced straight from the bundle: an app
  -- that has not shipped since a withdrawal carries an older descriptor, so
  -- the shared record is what every kit version reads.
  self.withdrawal_entries = is_plain_array(options.withdrawal_entries)
    and options.withdrawal_entries or nil
  self.instance_id = options.instance_id
  self.session_id = options.session_id
  self.resource_root = slash(options.resource_root)
  self.bundle_root = slash(options.bundle_root)
  assert(options.bundle_suffix == nil or options.bundle_suffix == ""
    or options.bundle_suffix == ".txt", "invalid bundle suffix")
  self.bundle_suffix = options.bundle_suffix or ""
  self.bundle_flat = options.bundle_flat == true
  self.bundle_target = type(options.bundle_target) == "table"
    and self.core.validate_target(options.bundle_target) and copy_table(options.bundle_target) or nil
  self.state_root = join(self.resource_root, "Data/mbriggs_helper")
  self.user_plugins = join(self.resource_root, "UserPlugins")
  self.paths = {
    journal = join(self.state_root, "install_journal.json"),
    sentinel = join(self.state_root, "first_load.json"),
    quarantine = join(self.state_root, "quarantine.json"),
    status = join(self.state_root, "status.json"),
    recovery = join(self.state_root, "recovery.json"),
    withdrawn = join(self.state_root, "withdrawn.json"),
    lock = join(self.state_root, LOCK_NAME),
    staged = join(self.state_root, "Staged"),
    backup = join(self.state_root, "Backup"),
    rejected = join(self.state_root, "Rejected"),
  }
  -- The live Engine filename for this host, when one is known. Repair uses it
  -- to see whether the live slot is empty; the journal carries its own copy for
  -- every transaction decision.
  self.live_filename = nil
  for _, name in pairs(self.core.PLATFORM_FILENAMES or {}) do
    if name == options.live_filename then self.live_filename = name end
  end
  -- A caller that named a live file but no target key gets the key derived,
  -- but only when the name belongs to exactly one target. Every host adapter
  -- passes the key it detected, so this answers for the callers that do not.
  if self.target_key == nil and self.live_filename ~= nil then
    local matches, count = nil, 0
    for key, name in pairs(self.core.PLATFORM_FILENAMES or {}) do
      if name == self.live_filename then
        matches = key
        count = count + 1
      end
    end
    if count == 1 then self.target_key = matches end
  end
  self.lock_identity = nil
  self.lock_revoked = false
  self.marker_held = false
  self.acquisition_sequence = 0
  self.reclaim_count = 0
  self.transaction_sequence = 0
  self.probe_cache = nil
  return self
end

function Runtime:_path_present(path)
  if type(self.path_present) == "function" then
    local ok, value = pcall(self.path_present, path)
    if ok then return value == true end
    return true
  end
  local file = self.io.open(path, "rb")
  if file then file:close(); return true end
  local renamed, _, code = self.os.rename(path, path)
  if renamed then return true end
  return tonumber(code) ~= 2
end

function Runtime:_read_bytes(path)
  local file = self.io.open(path, "rb")
  if not file then
    return nil, self:_path_present(path) and "unreadable" or "absent"
  end
  local ok, bytes = pcall(function() return file:read("*a") end)
  pcall(function() file:close() end)
  if not ok or type(bytes) ~= "string" then return nil, "unreadable" end
  return bytes, "present"
end

function Runtime:_write_bytes(path, bytes)
  local file = self.io.open(path, "wb")
  if not file then return false, "open:" .. tostring(path) end
  local wrote = pcall(function() assert(file:write(bytes)) end)
  local closed = pcall(function() assert(file:close()) end)
  if not wrote or not closed then return false, "write" end
  local check, state = self:_read_bytes(path)
  if state ~= "present" or check ~= bytes then return false, "readback" end
  return true
end

function Runtime:_decode(raw)
  local ok, value, err = pcall(self.json.decode, raw)
  if not ok then return nil, "decode-threw" end
  if value == nil then return nil, tostring(err or "decode-failed") end
  return value
end

function Runtime:_encode(value)
  local ok, raw, err = pcall(self.json.encode, value)
  if not ok or type(raw) ~= "string" then
    return nil, tostring(err or raw or "encode-failed")
  end
  return raw
end

function Runtime:_ensure_directories()
  for _, path in ipairs({
    self.state_root, self.user_plugins, self.paths.staged, self.paths.backup,
    self.paths.rejected,
  }) do
    local ok, value = pcall(self.mkdir, path)
    if not ok or value == false then return false, "mkdir:" .. path end
  end
  return true
end

-- The lock artifact for this host. Windows locks are one file, because Lua's
-- os.remove there removes files only: measured against .tools/lua/lua54.exe, it
-- answers errno 13 for a directory whether that directory is empty or not, so a
-- directory lock could never be destroyed. POSIX locks are a directory holding
-- an owner file, because a POSIX rename replaces an existing file silently and
-- so cannot be a create-if-absent. Both shapes run one protocol.
function Runtime:_lock_artifact()
  if self.is_windows then return self.paths.lock end
  return self.paths.lock .. ".d"
end

function Runtime:_lock_owner_path(artifact)
  if self.is_windows then return artifact end
  return artifact .. "/owner"
end

-- "blank" is a read that proves the artifact carries no identity. It is not the
-- same answer as "unreadable", which proves nothing about the owner, and the
-- two must stay apart: only a blank artifact may be reclaimed without a
-- liveness verdict.
function Runtime:_read_identity_file(path)
  local raw, state = self:_read_bytes(path)
  if state == "present" then
    raw = raw:match("^%s*(.-)%s*$")
    if raw ~= "" then return raw, "present" end
    return nil, "blank"
  end
  if state == "absent" then return nil, "absent" end
  return nil, "unreadable"
end

function Runtime:_read_lock_identity()
  local artifact = self:_lock_artifact()
  local identity, state = self:_read_identity_file(
    self:_lock_owner_path(artifact))
  if state == "absent" and not self.is_windows
      and self:_path_present(artifact) then
    return nil, "blank"
  end
  return identity, state
end

-- Destroy an artifact standing under a private name. Nothing under the shared
-- lock name is ever written into, emptied, or removed, so this runs only on a
-- claim this process built or on an artifact it has already renamed away.
function Runtime:_discard_artifact(path)
  if not self.is_windows then
    local owner = path .. "/owner"
    if not self.os.remove(owner) and self:_path_present(owner) then
      return false, "owner-remove"
    end
  end
  if not self.os.remove(path) and self:_path_present(path) then
    return false, "artifact-remove"
  end
  return true
end

-- A private artifact carrying this acquisition's identity, written and read
-- back before the rename that publishes it. The lock name therefore never
-- receives a partially written owner, which is what lets a blank artifact be
-- reclaimed without asking anyone's liveness.
function Runtime:_build_claim(claim, identity)
  self:_discard_artifact(claim)
  if not self.is_windows then
    local made, value = pcall(self.mkdir, claim)
    if not made or value == false then return false end
  end
  return self:_write_bytes(self:_lock_owner_path(claim), identity)
end

-- Acquisition is one rename of a fully formed private claim onto the shared
-- name, and that rename is the create-if-absent on both hosts. Windows refuses
-- an occupied destination outright (measured: errno 17 against a file, an empty
-- directory, and a non-empty directory). POSIX refuses a destination directory
-- that holds anything, and a lock directory always holds its owner file, so the
-- only destination POSIX would replace is an empty directory. No live owner can
-- leave one: the lock name is only ever created by this rename, and an artifact
-- is only ever emptied after it has been renamed away under a private name. An
-- empty lock directory can only be residue of the two-step removal the previous
-- protocol used, and replacing it displaces nobody.
function Runtime:_try_create_lock(identity)
  local artifact = self:_lock_artifact()
  local claim = artifact .. ".claim." .. safe_token(identity)
  if not self:_build_claim(claim, identity) then
    self:_discard_artifact(claim)
    return false
  end
  if not self.os.rename(claim, artifact) then
    self:_discard_artifact(claim)
    return false
  end
  return true
end

-- The liveness verdict for one instance id, or nil when nothing can be asked.
-- Only "dead" ever authorises touching what that instance left behind.
function Runtime:_liveness(instance)
  if type(instance) ~= "string"
      or type(self.instance_liveness) ~= "function" then
    return nil
  end
  local ok, verdict = pcall(self.instance_liveness, instance)
  if ok then return verdict end
  return nil
end

-- This instance's reclaim marker. It stands from before a reclamation reads the
-- standing identity until after that reclamation has renamed the artifact away.
-- One instance runs one reclamation at a time, so one name per instance is
-- enough, and only that instance ever writes or removes it.
function Runtime:_marker_path()
  return join(self.state_root, RECLAIM_PREFIX .. self.instance_id)
end

-- Can the shared name be created right now? "blocked" means a marker names an
-- instance no liveness proved dead, so a reclamation may be standing between
-- its read and its rename. "unlisted" means the listing could not be taken and
-- nothing can be proved from it.
--
-- A host with no enumeration seam answers "clear": nothing there can reclaim,
-- so no marker can exist, and every REAPER process sharing one resource path
-- runs one REAPER build and therefore one answer to this question.
function Runtime:_reclaim_markers()
  if type(self.enumerate_files) ~= "function" then return "clear" end
  local listed, names = pcall(self.enumerate_files, self.state_root)
  if not listed or type(names) ~= "table" then return "unlisted" end
  local verdict = "clear"
  for _, name in ipairs(names) do
    local owner = type(name) == "string" and name:match(RECLAIM_PATTERN) or nil
    if owner == self.instance_id then
      -- Ours. It names a reclamation only while this process is inside one,
      -- and this process runs one thing at a time, so anything else is the
      -- residue of a removal that was refused earlier.
      if not self.marker_held then
        self.os.remove(join(self.state_root, name))
      end
    elseif owner ~= nil then
      if self:_liveness(owner) == "dead" then
        -- A dead instance never returns, so removing its marker by its exact
        -- name cannot be mistaken for removing a live one's.
        self.os.remove(join(self.state_root, name))
      else
        verdict = "blocked"
      end
    end
  end
  return verdict
end

-- Move the artifact away under a private name and never return it. Rename is
-- atomic on all three platforms, so exactly one process moves any one artifact
-- and the loser finds no source. The move frees the shared name whatever
-- happens next, so no refusal here can wedge the installer.
--
-- The identity is read afterwards, from an artifact this acquisition holds
-- alone. An artifact that turns out not to be the one proved dead is left in
-- the graveyard rather than destroyed, and never returned to the shared name:
-- any protocol that puts a moved artifact back can be raced by a third process
-- taking the freed name first.
--
-- The graveyard name carries this instance id and nothing else, so this process
-- is the only one that can produce it and the leavings of an interrupted
-- reclamation are bounded at one artifact per instance.
function Runtime:_move_lock_artifact(expected)
  local standing, standing_state = self:_read_lock_identity()
  if standing ~= expected then return false, "changed" end
  if expected == nil and standing_state ~= "blank" then
    return false, "changed"
  end

  local artifact = self:_lock_artifact()
  local dead = artifact .. ".dead." .. self.instance_id
  self:_discard_artifact(dead)
  if self:_path_present(dead) then return false, "dead-present" end
  if not self.os.rename(artifact, dead) then return false, "rename" end

  local held, held_state = self:_read_identity_file(
    self:_lock_owner_path(dead))
  local ours = expected ~= nil and held == expected
    or expected == nil and (held_state == "blank" or held_state == "absent")
  if not ours then return true, "undecidable" end
  local discarded, why = self:_discard_artifact(dead)
  if not discarded then return true, why end
  return true, "disposed"
end

-- Every rename away from the shared name runs here, under this instance's
-- reclaim marker. The marker is written and read back before the standing
-- identity is read and removed after the rename, and no acquisition creates
-- the shared name while a marker of an instance nothing proved dead stands.
--
-- Proof. Between this read and this rename the artifact under the shared name
-- can change only by another reclaimer moving the same artifact away, because
-- no acquirer can create while this marker exists; this rename then finds no
-- source and does nothing. So a reclaimer never moves a live owner's lock, and
-- since an acquisition reports success only after a listing taken behind its
-- own claim shows no marker, no two processes can both pass verify_lock.
--
-- Returns whether this call freed the shared name, and a word for what became
-- of the artifact.
function Runtime:_take_lock_artifact(expected)
  local mine = self.lock_identity
  if type(mine) ~= "string" then return false, "identity" end
  local marker = self:_marker_path()
  if not self:_write_bytes(marker, mine) then
    self.os.remove(marker)
    return false, "marker"
  end
  self.marker_held = true
  self.reclaim_count = self.reclaim_count + 1
  local ran, freed, why = pcall(self._move_lock_artifact, self, expected)
  self.marker_held = false
  self.os.remove(marker)
  if not ran then return false, "transfer-error" end
  return freed, why
end

-- A claim of this identity stands under the shared name. It may be reported as
-- acquired only once a listing taken behind that claim shows no reclaim marker,
-- because a reclaimer whose standing read predates the claim removes its marker
-- only after its rename. The listing is read before the identity so a reclaimer
-- that finished between the two cannot be missed. The third return says the
-- claim stands, which a refusal must not abandon.
function Runtime:_settle(identity)
  if self:_reclaim_markers() ~= "clear" then
    return false, "lock-undecidable", true
  end
  if self:_read_lock_identity() == identity then return true end
  self.lock_revoked = true
  return false, "lock-undecidable"
end

-- One acquisition attempt, with this identity already standing in
-- `lock_identity` because the transfer and the claim both read it from there.
-- Three passes are the most a lawful sequence needs: a transient absence, one
-- reclamation, and the creation that follows it.
function Runtime:_acquire(identity)
  for _ = 1, 3 do
    if self:_reclaim_markers() ~= "clear" then
      return false, "lock-undecidable"
    end
    if self:_try_create_lock(identity) then return self:_settle(identity) end

    local current, state = self:_read_lock_identity()
    if current == identity then return self:_settle(identity) end
    if state == "unreadable" then return false, "lock-undecidable" end
    if current ~= nil then
      local verdict = self:_liveness(current:match("^(inst_[A-Za-z0-9_%-]+)#"))
      if verdict ~= "dead" then
        return false, verdict == "alive" and "lock-held" or "lock-undecidable"
      end
    end
    if state ~= "absent" then
      -- Never reclaim without the listing. The exclusion an acquirer honours
      -- is the only thing that keeps this rename off a live owner's lock.
      if type(self.enumerate_files) ~= "function" then
        return false, "lock-undecidable"
      end
      local freed, why = self:_take_lock_artifact(current)
      -- An artifact this transfer could not identify belonged to someone this
      -- pass never proved dead. The shared name is free, but taking it now
      -- would put this process exactly where that owner was, so the
      -- acquisition stops and the next tick competes for the free name.
      if why == "undecidable" or (not freed and why ~= "changed") then
        return false, "lock-undecidable"
      end
    end
  end
  return false, "lock-create-failed"
end

function Runtime:acquire_lock()
  if self.lock_identity and not self.lock_revoked then
    -- A claim published by an earlier call still has to clear the markers
    -- before it may be acted on, for the reason `_settle` states.
    if not self:verify_lock() then return false, "lock-lost" end
    if self:_reclaim_markers() ~= "clear" then
      return false, "lock-undecidable"
    end
    return true
  end
  local dirs_ok, dirs_why = self:_ensure_directories()
  if not dirs_ok then return false, dirs_why end
  self.acquisition_sequence = self.acquisition_sequence + 1
  self.lock_identity = self.instance_id .. "#"
    .. tostring(self.acquisition_sequence)
  self.lock_revoked = false
  local acquired, why, held = self:_acquire(self.lock_identity)
  if acquired then return true end
  -- A refusal that published no claim owns nothing, so it must leave no
  -- identity behind for the next call to mistake for a lock it held and lost.
  if not held then self.lock_identity = nil end
  return false, why
end

-- The identity under the shared name is the whole proof of ownership. It can
-- only be this acquisition's own or one a reclaimer moved away entirely, so a
-- match before every mutation is sufficient.
function Runtime:verify_lock()
  if self.lock_revoked or not self.lock_identity then return false end
  if self:_read_lock_identity() ~= self.lock_identity then
    self.lock_revoked = true
    self.lock_identity = nil
    return false
  end
  return true
end

-- A holder that cannot move its own artifact away keeps the acquisition. The
-- artifact still names this acquisition, and this process answers alive, so
-- abandoning it would leave a lock nothing anywhere could ever reclaim.
function Runtime:release_lock()
  if self.lock_identity and self:verify_lock() then
    local freed = self:_take_lock_artifact(self.lock_identity)
    if not freed then return end
  end
  self.lock_identity = nil
end

function Runtime:_with_lock(callback)
  local acquired, why = self:acquire_lock()
  if not acquired then return nil, why end
  local ok, first, second = pcall(callback)
  self:release_lock()
  if not ok then return nil, "runtime-error:" .. tostring(first) end
  return first, second
end

function Runtime:_rename_no_replace(source, destination)
  if not self:verify_lock() then return false, "lock-lost" end
  if self:_path_present(destination) then return false, "destination-present" end
  if self.is_windows then
    local ok, err = self.os.rename(source, destination)
    if not ok then return false, tostring(err or "rename") end
  else
    local quote = function(value)
      return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
    end
    local command = "ln " .. quote(source) .. " " .. quote(destination)
    local ok = self.os.execute(command)
    if ok == true or ok == 0 then
      if not self:_path_present(destination) then
        return false, "link-unverified"
      end
      local removed, err = self.os.remove(source)
      if not removed and self:_path_present(source) then
        return false, tostring(err or "source-remove")
      end
    else
      -- Portable installs can live on volumes such as exFAT that reject hard
      -- links. Recheck both lock ownership and destination absence before the
      -- ordinary rename fallback. The installer lock excludes every
      -- cooperating writer for this shared Engine transaction.
      if not self:verify_lock() then return false, "lock-lost" end
      if self:_path_present(destination) then
        return false, "destination-present"
      end
      local moved, err = self.os.rename(source, destination)
      if not moved then return false, tostring(err or "rename") end
    end
  end
  if self:_path_present(source) or not self:_path_present(destination) then
    return false, "rename-unverified"
  end
  return true
end

-- A record is written under `<name>.tmp`, verified there, and only then
-- renamed over its own name, so the primary never holds a partial write. The
-- two halves have their own names because one body needs the replacement to be
-- on disk before the record it replaces moves: `_stage_record` writes the
-- temporary and answers with the bytes it verified there, and
-- `_promote_record` renames those bytes into place and reads them back under
-- the primary name.
function Runtime:_stage_record(path, value)
  if not self:verify_lock() then return nil, "lock-lost" end
  local raw, encode_why = self:_encode(value)
  if not raw then return nil, encode_why end
  local temp = path .. ".tmp"
  self.os.remove(temp)
  local wrote, write_why = self:_write_bytes(temp, raw)
  if not wrote then return nil, write_why end
  return raw
end

function Runtime:_promote_record(path, raw)
  if not self:verify_lock() then return false, "lock-lost" end
  local temp = path .. ".tmp"

  if self.is_windows then
    if self:_path_present(path) then
      local removed = self.os.remove(path)
      if not removed and self:_path_present(path) then return false, "remove-primary" end
    end
    local moved, move_why = self:_rename_no_replace(temp, path)
    if not moved then return false, move_why end
  else
    local moved, err = self.os.rename(temp, path)
    if not moved then return false, tostring(err or "replace") end
  end

  local readback, state = self:_read_bytes(path)
  if state ~= "present" or readback ~= raw then return false, "record-readback" end
  return true
end

function Runtime:_write_record(path, value)
  local raw, stage_why = self:_stage_record(path, value)
  if not raw then return false, stage_why end
  return self:_promote_record(path, raw)
end

function Runtime:_read_record_file(path, validator)
  local raw, state = self:_read_bytes(path)
  if state ~= "present" then return nil, state end
  local value, decode_why = self:_decode(raw)
  if value == nil then return nil, "invalid", decode_why end
  local ok, why = validator(value)
  if not ok then return nil, "invalid", why end
  return value, "valid", nil, raw
end

-- Move a record out of the way under an evidence name, so what it said is
-- still readable after the body that could not use it moved on. The suffix
-- says why it was taken.
function Runtime:_preserve_as(path, suffix)
  local kept = path .. suffix
  self.os.remove(kept)
  if self:_path_present(kept) then return false, "preserve-present" end
  return self:_rename_no_replace(path, kept)
end

-- Records are written to `<name>.tmp`, read back, and only then swapped in, so
-- the primary name never holds a partial write. A primary this body cannot use
-- therefore came from outside the transaction protocol, and the completed
-- temporary beside it is the record the interrupted write had already verified.
-- Adopt it rather than refusing forever, keeping the unusable bytes for support.
function Runtime:_preserve_unusable(path)
  return self:_preserve_as(path, ".unusable")
end

function Runtime:_load_record(path, validator)
  local value, state, why = self:_read_record_file(path, validator)
  if state == "valid" then return value, "valid" end
  local orphan, orphan_state, orphan_why = self:_read_record_file(
    path .. ".tmp", validator)
  if orphan_state ~= "valid" then
    if state ~= "absent" then return nil, state, why end
    if orphan_state == "absent" then return nil, "absent" end
    return nil, orphan_state, orphan_why
  end
  if state ~= "absent" then
    local preserved, preserve_why = self:_preserve_unusable(path)
    if not preserved then
      return nil, state, "preserve:" .. tostring(preserve_why)
    end
  end
  local adopted, adopt_why = self:_rename_no_replace(path .. ".tmp", path)
  if not adopted then return nil, "invalid", "orphan-adopt:" .. tostring(adopt_why) end
  return orphan, "valid"
end

function Runtime:_validate_quarantine(value)
  if type(value) ~= "table" then return false, "quarantine-not-table" end
  local extra = unknown_field(value, QUARANTINE_FIELDS)
  if extra then return false, "quarantine-unknown-field:" .. extra end
  if value.schema ~= 1 then return false, "quarantine-schema" end
  if not is_plain_array(value.entries) then return false, "quarantine-entries" end
  local seen = {}
  for _, entry in ipairs(value.entries) do
    if type(entry) ~= "table" then return false, "quarantine-entry" end
    local entry_extra = unknown_field(entry, QUARANTINE_ENTRY_FIELDS)
    if entry_extra then return false, "quarantine-entry-field:" .. entry_extra end
    if not self.core.parse_version(entry.version) then
      return false, "quarantine-version"
    end
    if not is_lower_sha256(entry.sha256) then return false, "quarantine-sha256" end
    if type(entry.transaction_id) ~= "string"
        or not entry.transaction_id:match("^txn_[A-Za-z0-9_%-]+$") then
      return false, "quarantine-transaction"
    end
    if entry.reason ~= "self-test" then return false, "quarantine-reason" end
    if seen[entry.sha256] then return false, "quarantine-duplicate-sha256" end
    seen[entry.sha256] = true
  end
  return true
end

function Runtime:_load_quarantine()
  local validate = function(value) return self:_validate_quarantine(value) end
  local value, state, why = self:_load_record(self.paths.quarantine, validate)
  if state == "absent" then return {schema = 1, entries = {}}, "absent" end
  return value, state, why
end

-- Quarantine is keyed by the exact digest that failed its self-test. Two builds
-- can share a version string, so keying by version would refuse a good release
-- because a different binary with the same version failed once.
function Runtime:_target_quarantined(record, sha256)
  for _, entry in ipairs(record.entries or {}) do
    if entry.sha256 == sha256 then return true end
  end
  return false
end

function Runtime:_write_quarantine(journal)
  local record, state, why = self:_load_quarantine()
  if not record then return false, tostring(state) .. ":" .. tostring(why) end
  if self:_target_quarantined(record, journal.target_sha256) then return true end
  record.entries[#record.entries + 1] = {
    version = journal.target_version,
    sha256 = journal.target_sha256,
    transaction_id = journal.transaction_id,
    reason = "self-test",
  }
  return self:_write_record(self.paths.quarantine, record)
end

-- The completion record of the transaction before this one, and the only
-- durable statement of what is installed. The journal is not that statement:
-- it exists only while a transaction is open, so a machine between
-- transactions would have no record at all. Repair reads this to name the
-- backup artifact of an interrupted transaction whose journal is gone, and the
-- runtime policy reads it to decide whether the installed Engine's identity is
-- known.
-- An entry says three separable things: what the last transaction installed,
-- whether a placed target is still waiting for a process that can certify it,
-- and what a withdrawal removal did to this target's load path. Any of the
-- three may be absent, and an entry that says none of them is not an entry.
-- The `rebuilt` outcome is the exception to the first: no transaction wrote
-- it, and it says only that the bytes in the load path are the build this
-- app's descriptor names. The `unresolved` outcome says none of the three: a
-- repair could not carry this target's entry into the record it rebuilt, and
-- the entry states that loss rather than any outcome.
function Runtime:_validate_status_entry(entry)
  if type(entry) ~= "table" then return false, "status-entry" end
  local extra = unknown_field(entry, STATUS_ENTRY_FIELDS)
  if extra then return false, "status-entry-field:" .. extra end
  if entry.outcome == nil then
    if entry.target_version ~= nil or entry.target_sha256 ~= nil
        or entry.transaction_id ~= nil or entry.active_kind ~= nil
        or entry.active_version ~= nil or entry.active_sha256 ~= nil
        or entry.pending ~= nil then
      return false, "status-outcome"
    end
    if entry.withdrawal == nil then return false, "status-entry-empty" end
    if entry.filename ~= nil and type(entry.filename) ~= "string" then
      return false, "status-filename"
    end
    return self:_validate_status_withdrawal(entry.withdrawal)
  end
  if entry.outcome ~= "active" and entry.outcome ~= "rolled-back"
      and entry.outcome ~= "placed" and entry.outcome ~= "rebuilt"
      and entry.outcome ~= "unresolved" then
    return false, "status-outcome"
  end
  -- `unresolved` states a loss rather than an outcome. A repair took a record
  -- this kit could not read out of the way and could not carry this target's
  -- entry into the one it wrote, so the entry that replaces it names no build
  -- and no installed identity. Every decision then reads it exactly as it
  -- reads no entry at all: identity is unknown, nothing is authorized, and
  -- this target's own kit asks the user before anything is placed over its
  -- bytes. Its transaction id names the repair that dropped the entry.
  if entry.outcome == "unresolved" then
    if entry.active_kind ~= "absent" then return false, "status-unresolved" end
    if entry.target_version ~= nil or entry.target_sha256 ~= nil
        or entry.active_version ~= nil or entry.active_sha256 ~= nil
        or entry.filename ~= nil or entry.pending ~= nil
        or entry.withdrawal ~= nil then
      return false, "status-unresolved"
    end
    if type(entry.transaction_id) ~= "string"
        or not entry.transaction_id:match("^txn_[A-Za-z0-9_%-]+$") then
      return false, "status-transaction"
    end
    return true
  end
  if not self.core.parse_version(entry.target_version) then
    return false, "status-target-version"
  end
  if not is_lower_sha256(entry.target_sha256) then
    return false, "status-target-sha256"
  end
  if type(entry.transaction_id) ~= "string"
      or not entry.transaction_id:match("^txn_[A-Za-z0-9_%-]+$") then
    return false, "status-transaction"
  end
  if entry.active_kind == "engine" then
    if not self.core.parse_version(entry.active_version) then
      return false, "status-active-version"
    end
    if not is_lower_sha256(entry.active_sha256) then
      return false, "status-active-sha256"
    end
  elseif entry.active_kind ~= "absent" then
    return false, "status-active-kind"
  end
  if entry.filename ~= nil and type(entry.filename) ~= "string" then
    return false, "status-filename"
  end
  -- `rebuilt` is the one outcome no transaction wrote. A repair rebuilt this
  -- entry from the bytes in this target's load path and the digest this app's
  -- own descriptor names, so what it calls installed and what it calls placed
  -- are one digest, and nothing is waiting to be certified on it.
  if entry.outcome == "rebuilt" then
    if entry.active_kind ~= "engine"
        or entry.active_version ~= entry.target_version
        or entry.active_sha256 ~= entry.target_sha256 then
      return false, "status-rebuilt"
    end
  end
  if entry.pending ~= nil then
    local ok, why = self.core.validate_journal(entry.pending)
    if not ok then return false, "status-pending:" .. tostring(why) end
    if self.core.journal_kind(entry.pending) ~= "install" then
      return false, "status-pending-kind"
    end
    if entry.outcome ~= "placed" then return false, "status-pending-outcome" end
    if entry.pending.transaction_id ~= entry.transaction_id
        or entry.pending.target_sha256 ~= entry.target_sha256 then
      return false, "status-pending-transaction"
    end
  elseif entry.outcome == "placed" then
    return false, "status-placed-pending"
  end
  if entry.withdrawal ~= nil then
    return self:_validate_status_withdrawal(entry.withdrawal)
  end
  return true
end

function Runtime:_validate_status_withdrawal(value)
  if type(value) ~= "table" then return false, "status-withdrawal" end
  local extra = unknown_field(value, STATUS_WITHDRAWAL_FIELDS)
  if extra then return false, "status-withdrawal-field:" .. extra end
  if not is_lower_sha256(value.sha256) then
    return false, "status-withdrawal-sha256"
  end
  if not STATUS_WITHDRAWAL_STATES[value.state] then
    return false, "status-withdrawal-state"
  end
  if type(value.transaction_id) ~= "string"
      or not value.transaction_id:match("^txn_[A-Za-z0-9_%-]+$") then
    return false, "status-withdrawal-transaction"
  end
  return true
end

function Runtime:_validate_status(value)
  if type(value) ~= "table" then return false, "status-not-table" end
  local extra = unknown_field(value, STATUS_FIELDS)
  if extra then return false, "status-unknown-field:" .. extra end
  if value.schema ~= STATUS_SCHEMA then return false, "status-schema" end
  if type(value.targets) ~= "table" then return false, "status-targets" end
  for key, entry in pairs(value.targets) do
    if not self.core.is_target_key(key) then
      return false, "status-target-key:" .. tostring(key)
    end
    local ok, why = self:_validate_status_entry(entry)
    if not ok then return false, tostring(why) .. ":" .. tostring(key) end
  end
  return true
end

function Runtime:_load_status()
  return self:_load_record(self.paths.status,
    function(value) return self:_validate_status(value) end)
end

function Runtime:_status_targets(record)
  if type(record) ~= "table" then return {} end
  if record.schema ~= STATUS_SCHEMA then return {} end
  return record.targets or {}
end

function Runtime:_status_entry(record, target_key)
  local key = target_key or self.target_key
  if type(key) ~= "string" then return nil end
  return self:_status_targets(record)[key]
end

-- Read, replace exactly one target's entry, write. Every other target's entry
-- is carried through untouched, which is what stops a second slice's install
-- from erasing the first slice's evidence, on this machine and on a resource
-- directory shared between machines of different architecture.
function Runtime:_set_status_entry(target_key, entry)
  if type(target_key) ~= "string" then return false, "status-target-key" end
  local record, state, why = self:_load_status()
  if state ~= "valid" and state ~= "absent" then
    return false, "status-" .. tostring(state) .. ":" .. tostring(why)
  end
  local targets = copy_table(self:_status_targets(record))
  targets[target_key] = entry
  return self:_write_record(self.paths.status,
    {schema = STATUS_SCHEMA, targets = targets})
end

-- Structure only. A malformed record is refused rather than read past,
-- because an entry this body cannot parse may be the one that would have
-- withdrawn the digest now in the load path.
function Runtime:_validate_withdrawn(value)
  if type(value) ~= "table" then return false, "withdrawn-not-table" end
  local extra = unknown_field(value, WITHDRAWN_FIELDS)
  if extra then return false, "withdrawn-unknown-field:" .. extra end
  if value.schema ~= 1 then return false, "withdrawn-schema" end
  if not is_plain_array(value.entries) then return false, "withdrawn-entries" end
  if #value.entries > Runtime.WITHDRAWN_MAX_ENTRIES then
    return false, "withdrawn-entry-count"
  end
  for _, entry in ipairs(value.entries) do
    local ok, why = Runtime.validate_withdrawn_entry(entry)
    if not ok then return false, why end
  end
  return true
end

function Runtime.validate_withdrawn_entry(entry)
  if type(entry) ~= "table" then return false, "withdrawn-entry" end
  local extra = unknown_field(entry, WITHDRAWN_ENTRY_FIELDS)
  if extra then return false, "withdrawn-entry-field:" .. extra end
  if not is_lower_sha256(entry.sha256) then return false, "withdrawn-sha256" end
  if type(entry.payload) ~= "string" or entry.payload == ""
      or #entry.payload > Runtime.WITHDRAWN_PAYLOAD_BYTES then
    return false, "withdrawn-payload"
  end
  if type(entry.signature) ~= "string" or entry.signature == ""
      or #entry.signature > Runtime.WITHDRAWN_SIGNATURE_BYTES
      or entry.signature:match("^[A-Za-z0-9+/=_%-]+$") == nil then
    return false, "withdrawn-signature"
  end
  if type(entry.key_id) ~= "string" or entry.key_id == "" or #entry.key_id > 128
      or entry.key_id:match("^[A-Za-z0-9._%-]+$") == nil then
    return false, "withdrawn-key-id"
  end
  return true
end

-- One entry authorizes one digest, and only when an authorized signature is
-- verified over a payload that itself names that digest. The app supplies the
-- signature primitive and decides which keys are authorized; the kit refuses
-- to let a verified signature over some other payload stand in for this one.
--
-- THE PRIMITIVE ANSWERS THREE THINGS, NOT TWO.
-- `verify_signature(payload, signature, key_id)` returns:
--
--   "verified"     a key this app authorizes checked this signature over these
--                  payload bytes and it verified;
--   "rejected"     a key this app authorizes checked this signature and it did
--                  not verify;
--   "unknown-key"  this app cannot decide. It holds no key under `key_id`, its
--                  key store is unavailable, or it declines to answer. Any
--                  other value means the same thing.
--
-- `true` is read as "verified" as well, because that answer is unambiguous and
-- can only make this body treat a digest as withdrawn, which is the careful
-- direction. `false` is NOT read as "rejected". A boolean cannot tell a key
-- this app does not hold from a signature it checked and refused, and reading
-- it as a rejection is exactly how an app with the wrong key set comes to
-- ignore an authentic withdrawal and then discard it.
--
-- Returns `authorized`, a reason, and whether the answer is a PROOF. The third
-- value is the whole point: "this entry authorizes nothing" and "this body
-- could not tell" are different answers, and a body that treats the second as
-- the first admits a digest another app withdrew. An answer is a proof when
-- this body actually performed the check that produced it:
--
--   proved      the entry's structure is wrong; an authorized key checked the
--               signature and rejected it; or the signature verified and the
--               payload it covers does not name this digest;
--   not proved  no signature primitive is configured, the primitive raised,
--               the primitive could not decide, or the signature verified over
--               a payload this body cannot read. The entry may be an authentic
--               withdrawal of exactly these bytes, and nothing here can say it
--               is not.
function Runtime:_entry_authorizes(entry)
  local ok, why = Runtime.validate_withdrawn_entry(entry)
  if not ok then return false, why, true end
  if type(self.verify_signature) ~= "function" then
    return false, "no-verifier", false
  end
  local called, answer = pcall(self.verify_signature, entry.payload,
    entry.signature, entry.key_id)
  if not called then return false, "verifier-error", false end
  if answer ~= "verified" and answer ~= true then
    -- Only a key this app holds, having run the check, proves a rejection.
    if answer == "rejected" then return false, "signature", true end
    return false, "key-unavailable", false
  end
  local payload, decode_why = self:_decode(entry.payload)
  if type(payload) ~= "table" then
    return false, "payload:" .. tostring(decode_why), false
  end
  if not is_plain_array(payload.withdrawn) then
    return false, "payload-list", false
  end
  for _, digest in ipairs(payload.withdrawn) do
    if digest == entry.sha256 then return true, nil, true end
  end
  return false, "payload-omits-digest", true
end

-- The digests this machine treats as withdrawn, and whether the record could be
-- read at all. An absent record is empty, which is the trust boundary stated
-- above. A record that is present and malformed is not empty: it refuses use
-- and installation until a user-confirmed repair rewrites it.
--
-- Neither is a record holding an entry this body cannot check. An app with no
-- signature primitive, one whose primitive could not run, and one whose
-- primitive holds no key under the entry's `key_id`, have not found an empty
-- record: they have found a record they cannot read the meaning of, and it is
-- treated exactly like one that will not parse. That is what an app with no
-- verifier may do, stated plainly: while no withdrawal has ever been recorded
-- on this machine it installs and uses an Engine normally, and from the first
-- entry anyone writes it does neither until it ships a verifier or the user
-- repairs the record with an app that has one. The alternative is the defect
-- this rule exists to close, where the app that cannot check the record is the
-- one that goes on calling the digest another app withdrew.
function Runtime:_withdrawn_state()
  local value, state, why = self:_load_record(self.paths.withdrawn,
    function(record) return self:_validate_withdrawn(record) end)
  if state == "absent" then return {}, "clear", {} end
  if state ~= "valid" then
    return nil, "unusable", {}, tostring(state) .. ":" .. tostring(why)
  end
  local digests, dropped, unchecked = {}, {}, 0
  for index, entry in ipairs(value.entries) do
    local authorized, reason, proved = self:_entry_authorizes(entry)
    if authorized then
      digests[entry.sha256] = true
    else
      -- A forged entry is ignored, not fatal: it authorizes nothing, and the
      -- entries beside it that do verify still do. An entry this body could
      -- not check is neither, and it is counted separately.
      dropped[#dropped + 1] = {
        index = index,
        sha256 = entry.sha256,
        reason = tostring(reason),
        proved = proved == true,
      }
      if proved ~= true then unchecked = unchecked + 1 end
    end
  end
  if unchecked > 0 then
    return nil, "unusable", dropped,
      "unverifiable:" .. tostring(unchecked) .. ":" .. tostring(#value.entries)
  end
  return digests, "clear", dropped
end

-- Whether a name is a live Engine filename this kit knows. The set is the
-- kit's rather than this process's, because a record may be about a slice this
-- process does not load.
function Runtime:_is_live_filename(value)
  if type(value) ~= "string" then return false end
  for _, name in pairs(self.core.PLATFORM_FILENAMES or {}) do
    if name == value then return true end
  end
  return false
end

-- The recovery record names a file, not an architecture. A restoration is a
-- hash and a rename, and no part of it loads the binary, so a process of any
-- architecture has to be able to read an obligation a sibling slice's
-- transaction wrote down. Pinning the name to this process's own slice made a
-- sibling's obligation an unreadable record, which the next repair disposes of
-- while its previous Engine sits in the backup artifact.
function Runtime:_validate_recovery(value)
  if type(value) ~= "table" then return false, "recovery-not-table" end
  local extra = unknown_field(value, RECOVERY_FIELDS)
  if extra then return false, "recovery-unknown-field:" .. extra end
  if value.schema ~= 1 then return false, "recovery-schema" end
  if not self:_is_live_filename(value.filename) then
    return false, "recovery-filename"
  end
  if not self.core.parse_version(value.active_version) then
    return false, "recovery-active-version"
  end
  if not is_lower_sha256(value.active_sha256) then
    return false, "recovery-active-sha256"
  end
  if type(value.transaction_id) ~= "string"
      or not value.transaction_id:match("^txn_[A-Za-z0-9_%-]+$") then
    return false, "recovery-transaction"
  end
  if type(value.reason) ~= "string" or #value.reason > 48
      or value.reason:match("^[a-z0-9%-]+$") == nil then
    return false, "recovery-reason"
  end
  return true
end

function Runtime:_load_recovery()
  return self:_load_record(self.paths.recovery,
    function(value) return self:_validate_recovery(value) end)
end

function Runtime:_journal_validator(value)
  return self.core.validate_journal(value)
end

function Runtime:_sentinel_validator(value)
  return self.core.validate_sentinel(value)
end

function Runtime:_load_journal()
  return self:_load_record(self.paths.journal,
    function(value) return self:_journal_validator(value) end)
end

function Runtime:_load_sentinel()
  return self:_load_record(self.paths.sentinel,
    function(value) return self:_sentinel_validator(value) end)
end

function Runtime:_hash_path(path)
  if type(self.hash_file) == "function" then
    local ok, digest, state = pcall(self.hash_file, path)
    if ok and is_lower_sha256(digest) then return digest, "present" end
    if ok and state == "absent" then return nil, "absent" end
  end
  local bytes, state = self:_read_bytes(path)
  if state ~= "present" then return nil, state end
  local ok, digest = pcall(self.hash_bytes, bytes)
  if not ok or not is_lower_sha256(digest) then return nil, "unreadable" end
  return digest, "present"
end

function Runtime:_relative_paths(journal)
  local names, why = self.core.artifact_names(journal)
  if not names then return nil, why end
  return {
    live = join(self.user_plugins, names.live),
    staged = join(self.state_root, names.staged),
    backup = names.backup and join(self.state_root, names.backup) or nil,
    rejected = join(self.state_root, names.rejected),
  }
end

function Runtime:_classify_path(path, journal)
  if path == nil then return "absent" end
  local digest, state = self:_hash_path(path)
  if state == "absent" then return "absent" end
  if state ~= "present" then return "unreadable" end
  return self.core.classify_file(digest, journal)
end

function Runtime:_session_matches(journal)
  local expected = ROLLBACK_PHASES[journal.phase]
    and journal.rollback_session or journal.activation_session
  return expected ~= nil and expected == self.session_id
end

function Runtime:_probe_value(journal)
  local lane = ROLLBACK_PHASES[journal.phase] and "rollback" or "activation"
  local cache = self.probe_cache
  if cache and cache.transaction_id == journal.transaction_id
      and cache.lane == lane and cache.failures == journal.failures then
    return cache.value
  end
  return "not-run"
end

function Runtime:_snapshot(journal)
  local paths, paths_why = self:_relative_paths(journal)
  if not paths then return nil, paths_why end
  local sentinel, sentinel_state, sentinel_why = self:_load_sentinel()
  if sentinel_state ~= "valid" and sentinel_state ~= "absent" then
    return nil, "sentinel-" .. tostring(sentinel_state) .. ":" .. tostring(sentinel_why)
  end
  local quarantine, quarantine_state, quarantine_why = self:_load_quarantine()
  if not quarantine then
    return nil, "quarantine-" .. tostring(quarantine_state) .. ":"
      .. tostring(quarantine_why)
  end
  return {
    lock = self:verify_lock() and "owned" or "lost",
    journal = journal,
    sentinel = sentinel,
    same_session = self:_session_matches(journal),
    same_failure_session = journal.failure_session ~= nil
      and journal.failure_session == self.session_id,
    quarantine = self:_target_quarantined(quarantine, journal.target_sha256),
    files = {
      live = self:_classify_path(paths.live, journal),
      staged = self:_classify_path(paths.staged, journal),
      backup = self:_classify_path(paths.backup, journal),
      rejected = self:_classify_path(paths.rejected, journal),
    },
    probe = self:_probe_value(journal),
  }, nil, paths
end


function Runtime:_mint_transaction_id()
  self.transaction_sequence = self.transaction_sequence + 1
  return "txn_" .. safe_token(self.instance_id) .. "_"
    .. tostring(self.transaction_sequence)
end

function Runtime:_bundle_path(target)
  local directory = self.core.bundle_directory(target.platform)
  if not directory then return nil end
  if self.bundle_flat then return join(self.bundle_root, target.filename .. self.bundle_suffix) end
  return join(join(self.bundle_root, directory),
    target.filename .. self.bundle_suffix)
end

function Runtime:_loaded_version_value()
  if type(self.loaded_version) ~= "function" then return nil end
  local ok, value = pcall(self.loaded_version)
  if ok and type(value) == "string" and self.core.parse_version(value) then
    return value
  end
  return nil
end

function Runtime:_copy_bundle_to_staging(target, staged_path)
  local existing = self:_classify_path(staged_path, {
    target_sha256 = target.sha256,
    previous_kind = "absent",
  })
  if existing == "target" then return true end
  if existing ~= "absent" then return false, "staged-conflict" end

  local bundle = self:_bundle_path(target)
  if not bundle then return false, "bundle-platform" end
  local digest, digest_state = self:_hash_path(bundle)
  if digest_state ~= "present" then
    return false, "bundle-" .. tostring(digest_state)
  end
  if digest ~= target.sha256 then return false, "bundle-sha256" end
  local bytes, state = self:_read_bytes(bundle)
  if state ~= "present" then return false, "bundle-" .. tostring(state) end

  local copy_tag = safe_token(self.lock_identity):sub(-24)
  local temp = staged_path .. ".copy." .. copy_tag
  self.os.remove(temp)
  local wrote, write_why = self:_write_bytes(temp, bytes)
  if not wrote then return false, write_why end
  local temp_digest, temp_state = self:_hash_path(temp)
  if temp_state ~= "present" or temp_digest ~= target.sha256 then
    return false, "staged-temp-sha256"
  end
  local moved, move_why = self:_rename_no_replace(temp, staged_path)
  if not moved then return false, move_why end
  local final_digest, final_state = self:_hash_path(staged_path)
  if final_state ~= "present" or final_digest ~= target.sha256 then
    return false, "staged-readback-sha256"
  end
  return true
end

-- `confirmed` is the user's answer to a repair prompt. It is the only way an
-- unknown identity, or one version string carrying two different binaries,
-- becomes a replacement, and it never overrides a refusal: a withdrawn digest,
-- a quarantined bundle, another app's open transaction and a healthy newer
-- Engine are all still refused with it set.
-- Cache promotion shares the install lock. A verified download may replace a
-- stale cache only when no transaction can still be reading it. A crash after
-- removing a stale cache requires another download, never live-file recovery.
function Runtime:cache_bundle(target, source)
  return self:_with_lock(function()
    local valid, why = self.core.validate_target(target)
    if not valid then return result("refuse", "target-invalid:" .. tostring(why)) end
    local bundle = self:_bundle_path(target)
    if not bundle then return result("refuse", "bundle-platform") end
    local function verified(path)
      local digest, state = self:_hash_path(path)
      if state ~= "present" or digest ~= target.sha256 then return false end
      local file = self.io.open(path, "rb")
      if not file then return false end
      local ok, matched = pcall(function()
        local head = file:read(65536)
        return self.core.machine_matches(target.platform, head, function(offset, count)
          if file:seek("set", offset) ~= offset then return nil end
          return file:read(count)
        end)
      end)
      file:close()
      return ok and matched == true
    end
    if verified(bundle) then return result("ready", "cached") end
    if source == nil then return result("needed", "cache-missing-or-invalid") end
    -- Recovery names backups and the live slot, not the download cache. The
    -- user can install a verified target to discharge that obligation.
    for _, path in ipairs({self.paths.journal, self.paths.sentinel}) do
      if self:_path_present(path) or self:_path_present(path .. ".tmp") then
        return result("busy", "installation-pending")
      end
    end
    if type(source) ~= "string" or source == bundle or not verified(source) then
      return result("refuse", "download-invalid")
    end
    self.mkdir(parent_dir(bundle))
    if self:_path_present(bundle) then
      local removed, remove_why = self:_remove_verified(bundle)
      if not removed then return result("refuse", "cache-remove:" .. tostring(remove_why)) end
    end
    local moved, move_why = self:_rename_no_replace(source, bundle)
    if not moved then return result("refuse", "cache-place:" .. tostring(move_why)) end
    if not verified(bundle) then return result("refuse", "cache-readback") end
    return result("ready", "downloaded")
  end)
end

function Runtime:stage(target, options)
  local replace_equal_version = type(options) == "table"
    and options.replace_equal_version == true
  local confirmed = type(options) == "table" and options.confirmed == true
  return self:_with_lock(function()
    local target_ok, target_why = self.core.validate_target(target)
    if not target_ok then return result("refuse", "target-invalid:" .. target_why) end

    local journal, journal_state, journal_why = self:_load_journal()
    if journal_state ~= "valid" and journal_state ~= "absent" then
      return result("refuse", "journal-" .. tostring(journal_state)
        .. ":" .. tostring(journal_why))
    end
    local journal_relation = "absent"
    if journal then
      journal_relation = journal.platform == target.platform
        and journal.filename == target.filename
        and journal.target_version == target.version
        and journal.target_sha256 == target.sha256 and "same" or "other"
    end

    local quarantine, quarantine_state, quarantine_why = self:_load_quarantine()
    if not quarantine then
      return result("refuse", "quarantine-" .. tostring(quarantine_state)
        .. ":" .. tostring(quarantine_why))
    end

    -- The withdrawal record is read before the install check, as every kit
    -- version must, so a digest withdrawn after this app shipped is refused
    -- even though this app's own descriptor knows nothing about it.
    local digests, withdrawn_state, _, withdrawn_why = self:_withdrawn_state()
    if withdrawn_state ~= "clear" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(withdrawn_why))
    end

    local live_path = join(self.user_plugins, target.filename)
    local live_digest, live_state = self:_hash_path(live_path)
    local status, status_state = self:_load_status()
    local status_entry = status_state == "valid"
      and self:_status_entry(status, self.target_key or target.platform) or nil
    -- The installer's own status entry is the authority on what is installed,
    -- and the placed bytes have to agree with it. The version this process
    -- happens to have loaded is not that authority: it describes an image in
    -- memory, which a replacement on disk does not change.
    local record_state = "absent"
    if status_state == "valid" then
      record_state = type(status_entry) == "table" and status_entry.active_kind == "engine"
        and "valid" or "absent"
    elseif status_state ~= "absent" then
      record_state = status_state == "invalid" and "invalid" or "unreadable"
    end
    local identity = self.core.decide_identity({
      placed = {
        state = live_state == "present" and "present"
          or live_state == "absent" and "absent" or "unreadable",
        sha256 = live_digest,
      },
      record = {
        state = record_state,
        version = type(status_entry) == "table" and status_entry.active_version or nil,
        sha256 = type(status_entry) == "table" and status_entry.active_sha256 or nil,
      },
    })

    local policy = self.core.decide_install({
      lock = self:verify_lock() and "owned" or "lost",
      target = target,
      withdrawn = digests[target.sha256] and "withdrawn" or "clear",
      installed_withdrawn = live_state == "present"
        and digests[live_digest] == true or false,
      journal_state = journal_relation,
      identity = identity,
      quarantined = self:_target_quarantined(quarantine, target.sha256),
      installed_quarantined = live_state == "present"
        and self:_target_quarantined(quarantine, live_digest) or false,
      installed_compatibility = "unknown",
      replace_equal_version = replace_equal_version,
    })
    if policy.kind == "refuse" then
      return result("refuse", tostring(policy.reason)
        .. (policy.detail and (":" .. tostring(policy.detail)) or ""))
    end
    if policy.kind == "none" then
      -- Nothing is wrong and nothing is replaced. `already-current` keeps the
      -- name the controller has always shown for it.
      if policy.reason == "already-current" then
        return result("already-current", target.version)
      end
      return result("no-action", tostring(policy.reason))
    end
    if policy.kind == "repair-confirm" and not confirmed then
      return result("repair-required", tostring(policy.reason)
        .. (policy.detail and (":" .. tostring(policy.detail)) or ""))
    end

    local installed_state, installed = "absent", nil
    if identity.state == "known" then
      installed_state = "engine"
      installed = {version = identity.version, sha256 = identity.sha256}
    elseif identity.state ~= "absent" then
      -- A confirmed repair replaces bytes whose identity nobody can vouch for.
      -- The transaction records them by digest, which is what a rollback puts
      -- back. The version label is the bundle's, deliberately: the only version
      -- string on hand is the one from the record that disagrees with these
      -- bytes, and letting it decide a downgrade would let a wrong record
      -- refuse the repair it caused.
      if live_state == "present" and is_lower_sha256(live_digest) then
        installed_state = "engine"
        installed = {version = target.version, sha256 = live_digest}
        if installed.sha256 == target.sha256 then
          return result("refuse", "repair-identical-bytes")
        end
      else
        return result("refuse", "identity-unknown:" .. tostring(identity.reason))
      end
    end

    local decision = self.core.decide_admission({
      lock = self:verify_lock() and "owned" or "lost",
      target = target,
      journal_state = journal_relation,
      quarantined = self:_target_quarantined(quarantine, target.sha256),
      installed_state = installed_state,
      installed = installed,
      -- A confirmed repair is an explicit replacement, which is what the
      -- admission guard's equal-version rule asks for. It never turns a
      -- refusal above into a stage.
      replace_equal_version = replace_equal_version or confirmed,
    })
    if decision.kind == "refuse" then
      return result("refuse", tostring(decision.reason)
        .. (decision.detail and (":" .. tostring(decision.detail)) or ""))
    end
    if decision.kind ~= "stage" then return decision end

    local new_journal = {
      schema = self.core.SCHEMA,
      transaction_id = self:_mint_transaction_id(),
      phase = "staged",
      platform = target.platform,
      -- Only when this runtime is the one that loads this target. A runtime
      -- carrying file operations for another slice leaves the field absent
      -- rather than claiming a key it cannot load, and `journal_target` reads
      -- the platform for it.
      target = self.target_key == target.platform and self.target_key or nil,
      filename = target.filename,
      target_version = target.version,
      target_sha256 = target.sha256,
      previous_kind = installed_state == "engine" and "engine" or "absent",
      failures = 0,
      writer_instance = self.instance_id,
    }
    if installed_state == "engine" then
      new_journal.previous_version = installed.version
      new_journal.previous_sha256 = installed.sha256
    end
    local journal_ok, new_why = self.core.validate_journal(new_journal)
    if not journal_ok then return result("refuse", "journal-build:" .. new_why) end
    local paths = assert(self:_relative_paths(new_journal))
    local copied, copy_why = self:_copy_bundle_to_staging(target, paths.staged)
    if not copied then return result("refuse", copy_why) end
    local wrote, write_why = self:_write_record(self.paths.journal, new_journal)
    if not wrote then return result("refuse", "journal-write:" .. tostring(write_why)) end
    return result("staged", new_journal.transaction_id)
  end)
end

function Runtime:_write_journal(journal)
  local valid, why = self.core.validate_journal(journal)
  if not valid then return false, why end
  return self:_write_record(self.paths.journal, journal)
end

function Runtime:_remove_verified(path)
  if not self:verify_lock() then return false, "lock-lost" end
  local removed, err = self.os.remove(path)
  if not removed and self:_path_present(path) then return false, tostring(err or "remove") end
  return not self:_path_present(path), "remove-unverified"
end

-- What a target's entry already recorded about a withdrawal survives every
-- later transaction on that target. It is evidence about the load path, not
-- about the transaction that happens to be writing now.
function Runtime:_carried_withdrawal(target_key)
  local record, state = self:_load_status()
  if state ~= "valid" then return nil end
  local entry = self:_status_entry(record, target_key)
  if type(entry) ~= "table" then return nil end
  return copy_table(entry.withdrawal)
end

function Runtime:_write_status(journal, outcome)
  local entry = {
    outcome = outcome,
    target_version = journal.target_version,
    target_sha256 = journal.target_sha256,
    transaction_id = journal.transaction_id,
    filename = journal.filename,
  }
  if outcome == "rolled-back" then
    entry.active_kind = journal.previous_kind
    entry.active_version = journal.previous_version
    entry.active_sha256 = journal.previous_sha256
  else
    entry.active_kind = "engine"
    entry.active_version = journal.target_version
    entry.active_sha256 = journal.target_sha256
  end
  local target_key = self.core.journal_target(journal)
  entry.withdrawal = self:_carried_withdrawal(target_key)
  -- A completion carries no `pending`, so reaching one discharges the parked
  -- activation this target may have been sitting in.
  return self:_set_status_entry(target_key, entry)
end

-- Completed installs retain no old binaries. Recovery records take precedence
-- over cleanup, including parked activation for a different architecture.
-- Only names emitted by artifact_names are eligible, and their digest prefix
-- must match the file. Unknown files remain untouched.
function Runtime:_cleanup_completed_artifacts()
  if type(self.enumerate_files) ~= "function" or not self:verify_lock() then return end
  for _, path in ipairs({self.paths.journal, self.paths.sentinel, self.paths.recovery}) do
    if self:_path_present(path) or self:_path_present(path .. ".tmp") then return end
  end
  local status, state = self:_load_status()
  if state ~= "valid" then return end
  local fingerprint, fingerprint_state = self:_hash_path(self.paths.status)
  if fingerprint_state ~= "present" or self.cleanup_attempted == fingerprint then return end
  local eligible = {}
  for key, entry in pairs(status.targets) do
    if entry.pending or entry.outcome == "unresolved"
        or (entry.withdrawal and entry.withdrawal.state == "pending") then return end
    local filename = self.core.PLATFORM_FILENAMES[key]
    if filename == entry.filename and (entry.outcome == "active" or entry.outcome == "rolled-back") then
      local digest, live_state = self:_hash_path(join(self.user_plugins, filename))
      if (entry.active_kind == "engine" and live_state == "present" and digest == entry.active_sha256)
          or (entry.active_kind == "absent" and live_state == "absent") then
        eligible[filename] = true
      end
    end
  end
  -- At most one attempt per status per controller. A later launch retries an
  -- antivirus/file-lock refusal without spinning or blocking normal requests.
  self.cleanup_attempted = fingerprint
  local completed = self.bundle_target and status.targets[self.bundle_target.platform]
  if self.bundle_flat and self.bundle_target and eligible[self.bundle_target.filename]
      and completed and completed.filename == self.bundle_target.filename
      and completed.target_version == self.bundle_target.version
      and completed.target_sha256 == self.bundle_target.sha256 then
    local cache = self:_bundle_path(self.bundle_target)
    local digest, cache_state = self:_hash_path(cache)
    if cache_state == "present" and digest == self.bundle_target.sha256 then
      if not self:_remove_verified(cache) then return end
    end
  end
  for _, spec in ipairs({{self.paths.backup, "backup"}, {self.paths.staged, "staged"},
      {self.paths.rejected, "bad"}}) do
    local listed, names = pcall(self.enumerate_files, spec[1])
    if listed and type(names) == "table" then
      for _, name in ipairs(names) do
        if type(name) == "string" and not name:find("[/\\]") then
          for filename in pairs(eligible) do
            local prefix = filename .. "."
            if name:sub(1, #prefix) == prefix then
              local version, short_hash = name:sub(#prefix + 1):match(
                "^(%d+%.%d+%.%d+)%.([a-f0-9]+)%." .. spec[2] .. "$")
              if version and self.core.parse_version(version) and #short_hash == 16 then
                local path = join(spec[1], name)
                local digest, file_state = self:_hash_path(path)
                if file_state == "present" and digest:sub(1, 16) == short_hash then
                  if not self:_remove_verified(path) then return end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- A target whose file operations are done and whose activation waits for the
-- restart that loads it. The wait is durable and per target, in that target's
-- own status entry, outside the journal: `placed, activation pending`, holding
-- the transaction verbatim along with its backup reference and its evidence.
--
-- `close` says whether the journal goes with it. A process that can load this
-- target keeps the journal, because it is the one that will probe, certify or
-- roll back, and the rejection the user may be offered needs it. A process
-- that cannot load the target closes the transaction: it can never finish it,
-- and a journal it will never advance would block another target's install.
--
-- Order is one-directional at every crash point: the entry is durable before
-- the journal is removed, so a crash leaves the journal (which wins and parks
-- again) or the entry (which a later process resumes); the sentinel is cleared
-- last, because a sentinel with no journal is exactly what a resume rebuilds
-- from.
function Runtime:_park_activation(journal, close)
  local target_key = self.core.journal_target(journal)
  local entry = {
    outcome = "placed",
    target_version = journal.target_version,
    target_sha256 = journal.target_sha256,
    transaction_id = journal.transaction_id,
    filename = journal.filename,
    active_kind = "engine",
    active_version = journal.target_version,
    active_sha256 = journal.target_sha256,
    pending = copy_table(journal),
  }
  entry.withdrawal = self:_carried_withdrawal(target_key)
  local existing, existing_state = self:_load_status()
  local current = existing_state == "valid"
    and self:_status_entry(existing, target_key) or nil
  local unchanged = type(current) == "table" and current.outcome == "placed"
    and current.transaction_id == entry.transaction_id
    and current.target_sha256 == entry.target_sha256
    and type(current.pending) == "table"
    and current.pending.phase == journal.phase
    and current.pending.failures == journal.failures
  if not unchanged then
    local wrote, write_why = self:_set_status_entry(target_key, entry)
    if not wrote then
      return result("refuse", "park-status:" .. tostring(write_why))
    end
  end
  -- Recorded and nothing more. The caller reports the state through the
  -- ordinary action, so the detail a paused controller reads is unchanged.
  if close ~= true then return nil end
  local removed, remove_why = self:_remove_verified(self.paths.journal)
  if not removed then
    return result("refuse", "park-journal:" .. tostring(remove_why))
  end
  local cleared, clear_why = self:_clear_sentinel()
  if not cleared then return result("refuse", clear_why) end
  self.probe_cache = nil
  return result("restart-required", "activation-pending")
end

-- The other direction, run by a process that can load the target. The sentinel
-- is written before the journal so a crash between the two leaves the state a
-- resume already knows how to finish, rather than a journal whose sentinel is
-- missing.
function Runtime:_resume_activation(withdrawn_digests)
  if type(self.target_key) ~= "string" then return nil end
  local record, state = self:_load_status()
  if state ~= "valid" then return nil end
  local entry = self:_status_entry(record, self.target_key)
  if type(entry) ~= "table" or entry.outcome ~= "placed"
      or type(entry.pending) ~= "table" then
    return nil
  end
  -- The session that placed the target cannot certify it: its REAPER loaded
  -- whatever was there before. Resuming inside that session would only park
  -- again on the next step.
  if entry.pending.activation_session == self.session_id then return nil end
  -- A parked activation for a digest that has since been withdrawn is never
  -- certified. It stays parked, and the removal transition takes the file.
  if type(withdrawn_digests) == "table"
      and withdrawn_digests[entry.target_sha256] == true then
    return nil
  end
  local journal = copy_table(entry.pending)
  local valid, why = self.core.validate_journal(journal)
  if not valid then return result("refuse", "pending-journal:" .. tostring(why)) end
  local sentinel = self.core.sentinel_for_activation(journal)
  if type(sentinel) ~= "table" then
    return result("refuse", "pending-sentinel")
  end
  local wrote, write_why = self:_write_record(self.paths.sentinel, sentinel)
  if not wrote then
    return result("refuse", "pending-sentinel:" .. tostring(write_why))
  end
  local journal_written, journal_why = self:_write_journal(journal)
  if not journal_written then
    return result("refuse", "pending-journal:" .. tostring(journal_why))
  end
  self.probe_cache = nil
  return result("resumed", journal.transaction_id)
end

-- The removal transition for the digest in this host's load path, when the
-- record withdraws it and no transaction is open. Returns nil when there is
-- nothing to open, so a caller can fall through to its own next answer.
function Runtime:_open_withdrawal(digests)
  if type(self.live_filename) ~= "string"
      or type(self.target_key) ~= "string" then
    return nil
  end
  local digest, digest_state = self:_hash_path(
    join(self.user_plugins, self.live_filename))
  if digest_state ~= "present" or digests[digest] ~= true then return nil end
  local withdrawal, build_why = self:_withdrawal_journal(digest)
  if not withdrawal then
    return result("refuse", "withdrawal-open:" .. tostring(build_why))
  end
  local wrote, write_why = self:_write_journal(withdrawal)
  if not wrote then
    return result("refuse", "withdrawal-open:" .. tostring(write_why))
  end
  return result("withdrawal-opened", digest)
end

-- An install transaction whose target digest was withdrawn while it was open.
--
-- It is never advanced and never certified. What it leaves behind depends on
-- how far it had got, and the two ends are different on purpose:
--
--   the target is not in the load path yet -- the staged copy of the withdrawn
--     bytes and the transaction records go, and the load path is whatever the
--     transaction had left there. When that is nothing, because the previous
--     Engine had already been moved to the backup artifact, the obligation to
--     put it back is written down first, so the next run reports a recovery
--     rather than an idle installer over an empty load path;
--
--   the target is already in the load path -- the same records go, and the
--     removal transition opens on the digest that is actually there. Removing
--     a file from the load path is that machine's work and nothing else's, and
--     it is bound to the digest it proves present.
--
-- The obligation is written for whichever file this transaction emptied, not
-- only for the one this process loads. A process of another architecture reads
-- the same journal and removes the same records, and the previous Engine it
-- leaves in the backup artifact is owed to that slot whoever walks away from
-- it. The record names the file, so the process that can restore it is any
-- process, and the one that loads that slot no longer has to rebuild the
-- obligation from a status entry a repair would never reach.
--
-- Order is one-directional at every crash point: the recovery obligation is
-- durable before anything is removed, and the journal is removed last, so a
-- crash leaves a journal this same body abandons again rather than a tree no
-- record describes.
function Runtime:_abandon_withdrawn_transaction(journal, digests)
  local paths, paths_why = self:_relative_paths(journal)
  if not paths then
    return result("refuse", "withdrawn-abandon:" .. tostring(paths_why))
  end
  local live_digest, live_state = self:_hash_path(paths.live)
  if live_state ~= "present" and live_state ~= "absent" then
    return result("refuse", "withdrawn-abandon-live:" .. tostring(live_state))
  end

  -- The previous Engine is in the backup artifact and the load path is empty,
  -- which is the one state an abandonment must not simply walk away from.
  if live_state == "absent" and journal.previous_kind == "engine" then
    local pending = {
      schema = 1,
      filename = journal.filename,
      active_version = journal.previous_version,
      active_sha256 = journal.previous_sha256,
      transaction_id = journal.transaction_id,
      reason = "withdrawn-target",
    }
    local valid, valid_why = self:_validate_recovery(pending)
    if not valid then
      -- Nothing here can write down what the load path is owed, so the journal
      -- stays: it is the last record of what this transaction moved.
      return result("refuse",
        "withdrawn-abandon-recovery:" .. tostring(valid_why))
    end
    -- Both refusals below are named in the `recovery-` class on purpose. The
    -- host adapter offers its repair control for exactly that class of detail,
    -- and the repair is what resolves both of them: it discharges a standing
    -- obligation, or it takes an unreadable record out of the way. A refusal
    -- outside that class here would be a state with no control to leave it by.
    local held, held_state = self:_load_recovery()
    if held_state ~= "valid" and held_state ~= "absent" then
      -- A record nobody can read may already be an obligation. It is not
      -- overwritten here: the journal stays and the user's repair is what
      -- takes an unreadable record out of the way.
      return result("refuse", "recovery-" .. tostring(held_state))
    end
    if held_state == "valid" and held.filename ~= pending.filename then
      -- One file is already owed a binary and this record holds one
      -- obligation. Overwriting it would leave that file's previous Engine in
      -- the backup artifact with nothing on disk to say so, so the journal
      -- stays and the outstanding recovery is discharged first.
      return result("refuse", "recovery-held:" .. tostring(held.filename))
    end
    local wrote, write_why = self:_write_record(self.paths.recovery, pending)
    if not wrote then
      return result("refuse", "recovery-write:" .. tostring(write_why))
    end
  end

  local removed, remove_why = self:_remove_verified(paths.staged)
  if not removed then
    return result("refuse", "withdrawn-abandon-staged:" .. tostring(remove_why))
  end
  local cleared, clear_why = self:_clear_sentinel()
  if not cleared then return result("refuse", clear_why) end
  removed, remove_why = self:_remove_verified(self.paths.journal)
  if not removed then
    return result("refuse", "journal-remove:" .. tostring(remove_why))
  end
  removed, remove_why = self:_remove_verified(self.paths.journal .. ".tmp")
  if not removed then
    return result("refuse", "journal-temp-remove:" .. tostring(remove_why))
  end
  self.probe_cache = nil

  if live_state == "present" and digests[live_digest] == true then
    local opened = self:_open_withdrawal(digests)
    -- A process that does not load this target cannot open the removal. It has
    -- stopped driving the transaction, which is its part; the process that
    -- loads the target opens the removal at its own session start.
    if opened then return opened end
  end
  return result("withdrawn-abandoned", journal.target_sha256)
end

-- A target this process cannot load. It may still carry the journal's file
-- operations forward, because those come from the validated journal and are
-- the same on every architecture. It may not run the activation probe, may not
-- certify, and may not record an activation failure: it never loaded the
-- binary, so it has nothing to report about it.
function Runtime:_foreign_target(journal)
  if type(self.target_key) ~= "string" then return false end
  local target_key = self.core.journal_target(journal)
  if type(target_key) ~= "string" then return false end
  return target_key ~= self.target_key
end

-- The actions that put a digest into the load path or write down that one is
-- active, and which of the journal's two digests each of them is about. Every
-- other action moves records or evidence around and cannot make a withdrawn
-- build reachable.
local LOAD_PATH_ACTIONS = {
  ["rename-staged-to-live"] = "target",
  ["rename-backup-to-live"] = "previous",
  ["complete-active"] = "target",
}

function Runtime:_execute(decision, journal, paths, snapshot)
  if not self:verify_lock() then return result("refuse", "lock-lost") end
  local kind = decision.kind
  local changed = copy_table(journal)

  -- The last point before the file operation. `_execute` is reached from the
  -- step, from the user's rejection and from anything written later, so the
  -- invariant lives here rather than in one caller: no action of this
  -- transaction puts a withdrawn digest into the load path or certifies one.
  local guarded = LOAD_PATH_ACTIONS[kind]
    or (kind == "set-phase" and decision.next_phase == "active" and "target")
    or nil
  if guarded then
    local digests, withdrawn_state, _, withdrawn_why = self:_withdrawn_state()
    if withdrawn_state ~= "clear" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(withdrawn_why))
    end
    local sha256 = guarded == "previous" and journal.previous_sha256
      or journal.target_sha256
    if sha256 ~= nil and digests[sha256] == true then
      -- Restoring the previous Engine is refused for the reason the recovery
      -- path refuses it: the obligation is kept and reported, and the app's
      -- next update supplies a build that may be restored.
      return result("refuse", "withdrawn-" .. guarded)
    end
  end

  if kind == "record-activation-session" then
    changed.activation_session = self.session_id
    local ok, why = self:_write_journal(changed)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "write-activation-sentinel" then
    local sentinel = assert(self.core.sentinel_for_activation(journal))
    local ok, why = self:_write_record(self.paths.sentinel, sentinel)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "set-phase" then
    changed.phase = decision.next_phase
    local ok, why = self:_write_journal(changed)
    return ok and result("advanced", decision.next_phase) or result("refuse", why)
  elseif kind == "rename-previous-to-backup" then
    local ok, why = self:_rename_no_replace(paths.live, paths.backup)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "rename-staged-to-live" then
    local ok, why = self:_rename_no_replace(paths.staged, paths.live)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "remove-duplicate-live-previous" then
    local ok, why = self:_remove_verified(paths.live)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "remove-duplicate-staged-target" then
    local ok, why = self:_remove_verified(paths.staged)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "wait-restart" then
    -- A target in the live slot that has not registered stays there: nothing
    -- proves it will not load after a restart. The detail names that state,
    -- which is the only one the user-driven rejection is offered from.
    if type(snapshot) == "table" and snapshot.probe == "not-registered"
        and self.core.decide_rejection(snapshot).kind == "prepare-rollback" then
      return result("restart-required", "not-registered")
    end
    return result("restart-required", journal.phase)
  elseif kind == "run-activation-probe" or kind == "run-rollback-probe" then
    local lane = kind == "run-rollback-probe" and "rollback" or "activation"
    local value = "unavailable"
    if type(self.probe) == "function" then
      local ok, probed = pcall(self.probe, lane, copy_table(journal), copy_table(paths))
      if ok and type(probed) == "string" then value = probed end
    end
    self.probe_cache = {
      transaction_id = journal.transaction_id,
      lane = lane,
      failures = journal.failures,
      value = value,
    }
    return result("probed", value)
  elseif kind == "record-probe-failure" then
    changed.failures = changed.failures + 1
    changed.failure_session = self.session_id
    local ok, why = self:_write_journal(changed)
    if ok then self.probe_cache = nil end
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "prepare-rollback" then
    changed.failures = 2
    changed.phase = decision.next_phase
    changed.rollback_session = self.session_id
    local ok, why = self:_write_journal(changed)
    if ok then self.probe_cache = nil end
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "write-quarantine" then
    local ok, why = self:_write_quarantine(journal)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "record-rollback-session" then
    changed.rollback_session = self.session_id
    local ok, why = self:_write_journal(changed)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "rename-live-to-rejected" then
    local ok, why = self:_rename_no_replace(paths.live, paths.rejected)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "remove-duplicate-live-target" then
    local ok, why = self:_remove_verified(paths.live)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "rename-backup-to-live" then
    local ok, why = self:_rename_no_replace(paths.backup, paths.live)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "remove-duplicate-backup-previous" then
    local ok, why = self:_remove_verified(paths.backup)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "write-rollback-sentinel" then
    local sentinel = assert(self.core.sentinel_for_rollback(journal))
    local ok, why = self:_write_record(self.paths.sentinel, sentinel)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "clear-sentinel" then
    local ok, why = self:_remove_verified(self.paths.sentinel)
    return ok and result("advanced", kind) or result("refuse", why)
  elseif kind == "complete-active" or kind == "complete-rolled-back" then
    local outcome = kind == "complete-active" and "active" or "rolled-back"
    local temp_removed, temp_why = self:_remove_verified(self.paths.journal .. ".tmp")
    if not temp_removed then
      return result("refuse", "journal-temp-remove:" .. tostring(temp_why))
    end
    local wrote, write_why = self:_write_status(journal, outcome)
    if not wrote then return result("refuse", "status-write:" .. tostring(write_why)) end
    -- A completion that leaves a file in the live slot discharges a recorded
    -- recovery, which exists only to say that slot is empty and should not be.
    -- The record names one file: a completion in another slot has filled a
    -- different one and proves nothing about the obligation, so it leaves it
    -- standing rather than deleting the only statement that the other file is
    -- owed its Engine.
    if self:_path_present(paths.live) then
      local held, held_state = self:_load_recovery()
      local cleared, clear_why = true, nil
      if held_state == "valid" and held.filename == journal.filename then
        cleared, clear_why = self:_clear_recovery()
      elseif held_state ~= "valid" and held_state ~= "absent" then
        -- A record nobody can read cannot say which file it is about, and
        -- leaving it would refuse every later launch. Its bytes are kept under
        -- an evidence name, which is what the kit does with every record it
        -- takes out of the way without reading.
        cleared, clear_why = self:_dispose_record(self.paths.recovery)
      end
      if not cleared then
        return result("refuse", "recovery-clear:" .. tostring(clear_why))
      end
    end
    local removed, remove_why = self:_remove_verified(self.paths.journal)
    if not removed then return result("refuse", "journal-remove:" .. tostring(remove_why)) end
    self.probe_cache = nil
    self:_cleanup_completed_artifacts()
    return result(outcome, journal.target_version)
  end
  return result("refuse", "unhandled-action:" .. tostring(kind))
end

function Runtime:step()
  return self:_with_lock(function()
    -- The record is read before any transaction is advanced, not only when
    -- there is none. A withdrawal that arrives while a transaction is open has
    -- to stop it, and a body that reads the record only on the way past an
    -- absent journal would notice it after the transaction had certified.
    local digests, withdrawn_state, _, withdrawn_why = self:_withdrawn_state()
    if withdrawn_state ~= "clear" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(withdrawn_why))
    end
    local journal, state, why = self:_load_journal()
    if state == "absent" then
      -- The digest in the load path was withdrawn while this session ran, and
      -- no transaction is open to be stopped. The removal transition is what
      -- takes a file out of the load path, and it opens here as well as at the
      -- session start, so a withdrawal merged by another app mid-session is
      -- not left waiting for the next launch.
      local opened = self:_open_withdrawal(digests)
      if opened then return opened end
      -- A target parked in `placed, activation pending` is picked up by the
      -- first process that can load it, without needing the journal to have
      -- been held open for it.
      local resumed = self:_resume_activation(digests)
      if resumed then return resumed end
      local record, record_state = self:_load_recovery()
      if record_state == "valid" then
        return result("recovery-required", record.reason)
      end
      if record_state ~= "absent" then
        return result("refuse", "recovery-" .. tostring(record_state))
      end
      self:_cleanup_completed_artifacts()
      return result("idle", "no-transaction")
    end
    if not journal then
      return result("refuse", "journal-" .. tostring(state) .. ":" .. tostring(why))
    end
    if self.core.journal_kind(journal) == "withdrawal-removal" then
      return self:_withdrawal_step(journal)
    end
    -- An install transaction for a digest this record withdraws is never
    -- advanced and never certified, whatever phase it reached.
    if digests[journal.target_sha256] == true then
      return self:_abandon_withdrawn_transaction(journal, digests)
    end
    -- The file operations are finished and this process cannot load the
    -- target, so it can neither certify nor condemn it. Record the pending
    -- activation in that target's own entry and close the transaction, so a
    -- slice waiting for an architecture that may never launch does not hold
    -- the journal against another target's install.
    if journal.phase == "pending-restart" and self:_foreign_target(journal) then
      return self:_park_activation(journal, true)
    end
    local snapshot, snapshot_why, paths = self:_snapshot(journal)
    if not snapshot then return result("refuse", snapshot_why) end
    local decision = self.core.next_action(snapshot)
    if decision.kind == "refuse" then
      return result("refuse", decision.reason .. (decision.detail
        and (":" .. tostring(decision.detail)) or ""))
    end
    -- The file operations are done and the target is waiting for the restart
    -- that loads it. That wait is written into this target's own status entry
    -- before it is reported, so what is placed is known between transactions
    -- and not only while a journal happens to exist. The journal stays: this
    -- process can load the target, so it is the one that will probe, certify
    -- or roll back, and the rejection it may be offered needs it.
    if decision.kind == "wait-restart" and journal.phase == "pending-restart" then
      local refused = self:_park_activation(journal, false)
      if refused then return refused end
    end
    return self:_execute(decision, journal, paths, snapshot)
  end)
end

-- Which sentinel a valid journal's phase requires, or nil when what is on disk
-- is already one that phase accepts. "remove" disposes of a sentinel left by
-- another transaction while this one has moved no file yet.
function Runtime:_sentinel_repair_plan(phase, relation)
  if phase == "staged" then
    if relation == "absent" or relation == "activation" then return nil end
    return "remove"
  end
  if (phase == "active" or phase == "rolled-back") and relation == "absent" then
    return nil
  end
  if phase == "previous-restored" and relation == "rollback" then return nil end
  local wanted = SENTINEL_ROLLBACK_PHASES[phase] and "rollback" or "activation"
  if relation == wanted then return nil end
  return wanted
end

-- A valid journal describes the whole transaction, so a sentinel that belongs
-- to another one, or cannot be read, is rebuilt from it rather than left to
-- refuse every launch. The sentinel content is derived from the journal, so
-- this writes exactly what the interrupted step would have written.
function Runtime:_repair_sentinel(journal)
  local sentinel, state = self:_load_sentinel()
  local relation = "unusable"
  if state == "valid" then
    relation = self.core.sentinel_relation(journal, sentinel)
  elseif state == "absent" then
    relation = "absent"
  end
  local plan = self:_sentinel_repair_plan(journal.phase, relation)
  if not plan then return result("refuse", "journal-valid") end

  if relation == "unusable" and self:_path_present(self.paths.sentinel) then
    local preserved, preserve_why = self:_preserve_unusable(self.paths.sentinel)
    if not preserved then
      return result("refuse", "repair-sentinel-preserve:" .. tostring(preserve_why))
    end
  end
  local cleared, clear_why = self:_clear_sentinel()
  if not cleared then return result("refuse", clear_why) end
  self.probe_cache = nil
  if plan == "remove" then return result("repaired", "sentinel-removed") end

  local rebuilt = plan == "rollback"
    and self.core.sentinel_for_rollback(journal)
    or self.core.sentinel_for_activation(journal)
  if type(rebuilt) ~= "table" then
    return result("refuse", "repair-sentinel-build")
  end
  local wrote, write_why = self:_write_record(self.paths.sentinel, rebuilt)
  if not wrote then
    return result("refuse", "repair-sentinel-write:" .. tostring(write_why))
  end
  return result("repaired", "sentinel-" .. plan)
end

-- The user's remedy for a target that reached the live slot and has not
-- registered in this REAPER session. The installer never decides this itself,
-- because no Engine registered is not evidence about the target, so the
-- rollback is entered only from the state the presentation offers it in and
-- only while this session's own probe found nothing registered. Answering
-- "repaired" is what lets the paused controller drive the rollback it starts.
function Runtime:_reject_target(journal)
  local snapshot, _, paths = self:_snapshot(journal)
  if not snapshot or snapshot.probe ~= "not-registered" then return nil end
  local decision = self.core.decide_rejection(snapshot)
  if decision.kind ~= "prepare-rollback" then return nil end
  local outcome = self:_execute(decision, journal, paths, snapshot)
  if outcome.kind ~= "advanced" then return outcome end
  return result("repaired", decision.next_phase)
end

-- Both sentinel names, taken out of the way under one refusal vocabulary.
function Runtime:_clear_sentinel()
  local cleared, why = self:_remove_verified(self.paths.sentinel)
  if not cleared then return false, "repair-sentinel:" .. tostring(why) end
  cleared, why = self:_remove_verified(self.paths.sentinel .. ".tmp")
  if not cleared then return false, "repair-sentinel-temp:" .. tostring(why) end
  return true
end

-- The artifact one obligation would be met from. The name carries the file,
-- the version and the leading sixteen characters of the digest, so a record
-- names exactly one artifact and a hash decides whether it is the right one.
function Runtime:_recovery_backup(record)
  return join(self.state_root, "Backup/" .. record.filename .. "."
    .. record.active_version .. "." .. record.active_sha256:sub(1, 16)
    .. ".backup")
end

-- What stands between this obligation and the Engine it names, taken without
-- moving anything. Returns nil when a restoration would proceed, or when the
-- Engine is already in the load path and the record is met.
--
-- It is read-only on purpose. The restoration below uses it, and so does the
-- user's discharge, so the answer that authorizes discharging an obligation is
-- the same answer that decides whether a restoration runs. A separate rule for
-- the discharge could drift into discarding an obligation this body would
-- still have met.
function Runtime:_recovery_obstacle(record)
  local live = join(self.user_plugins, record.filename)
  if self:_path_present(live) then
    -- A file standing in the live slot discharges this record only once it is
    -- proved to be the Engine the record names. A restoration whose readback
    -- failed leaves bytes there that are not it, and the next repair would
    -- otherwise clear the record and report the previous Engine restored over
    -- an Engine nobody hashed.
    local digest, digest_state = self:_hash_path(live)
    if digest_state ~= "present" then
      return "live-" .. tostring(digest_state)
    end
    if digest ~= record.active_sha256 then return "live-sha256" end
    return nil
  end
  -- Restoring the Engine that was last proven active would put a withdrawn
  -- build back into the load path, which is the one thing the withdrawal
  -- record exists to stop. The obligation is kept and reported instead, and
  -- the app's next update is what supplies a build that may be restored.
  local digests, withdrawn_state = self:_withdrawn_state()
  if withdrawn_state ~= "clear" then return "withdrawal-record" end
  if digests[record.active_sha256] == true then return "withdrawn" end
  local digest, digest_state = self:_hash_path(self:_recovery_backup(record))
  if digest_state ~= "present" then
    return "backup-" .. tostring(digest_state)
  end
  if digest ~= record.active_sha256 then return "backup-sha256" end
  return nil
end

-- Interruption between the previous Engine moving to backup and the target
-- being placed leaves the live slot empty. Disposing of an unusable journal
-- there would report a repair and leave the user with no Engine, so repair puts
-- the previous Engine back from the backup artifact the record names, after
-- hashing it against the digest that record carries. A live slot that is
-- already occupied is hashed against the same digest before the record is
-- discharged, so only the recorded Engine ever ends this recovery.
--
-- The record names the file, and every step here is a hash and a rename, so
-- the process that discharges it is any process on this machine rather than
-- the one that loads that slice. That is what stops an obligation written by a
-- process of another architecture from waiting for a launch that may never
-- come.
function Runtime:_attempt_recovery(record)
  local obstacle = self:_recovery_obstacle(record)
  if obstacle then return false, obstacle end
  local live = join(self.user_plugins, record.filename)
  if self:_path_present(live) then return true end
  local moved, move_why = self:_rename_no_replace(
    self:_recovery_backup(record), live)
  if not moved then return false, recovery_reason(move_why) end
  local final, final_state = self:_hash_path(live)
  if final_state ~= "present" or final ~= record.active_sha256 then
    return false, "restore-readback"
  end
  return true
end

-- The completion record of the transaction before this one is the only durable
-- statement of which Engine was last proven active, so it is what a first
-- recovery record is built from. Returns nil when there is nothing to recover.
function Runtime:_recovery_from_status()
  if type(self.live_filename) ~= "string" then return nil end
  if self:_path_present(join(self.user_plugins, self.live_filename)) then
    return nil
  end
  local status, state = self:_load_status()
  if state ~= "valid" then return nil end
  -- Target-bound: this process restores its own target's Engine, never a
  -- sibling slice's, whose entry describes a file it does not load.
  local entry = self:_status_entry(status, self.target_key)
  if type(entry) ~= "table" or entry.active_kind ~= "engine" then return nil end
  -- A `placed` entry names bytes that were put in the load path and never
  -- certified, and the backup beside them is the Engine they displaced. That
  -- backup is the one a restoration can actually verify and use, so a target
  -- sitting in `placed, activation pending` recovers to what it replaced.
  if entry.outcome == "placed" and type(entry.pending) == "table" then
    if entry.pending.previous_kind ~= "engine" then return nil end
    return {
      schema = 1,
      filename = self.live_filename,
      active_version = entry.pending.previous_version,
      active_sha256 = entry.pending.previous_sha256,
      transaction_id = entry.transaction_id,
      reason = "pending",
    }
  end
  return {
    schema = 1,
    filename = self.live_filename,
    active_version = entry.active_version,
    active_sha256 = entry.active_sha256,
    transaction_id = entry.transaction_id,
    reason = "pending",
  }
end

-- Recovery that could not finish is written down before it is reported, so a
-- later repair retries it and every step keeps reporting it. It is cleared only
-- by a verified restoration or by a transaction that completes with a file in
-- the live slot.
function Runtime:_hold_recovery(record, why)
  record.reason = recovery_reason(why)
  local wrote, write_why = self:_write_record(self.paths.recovery, record)
  if not wrote then
    return result("refuse", "recovery-write:" .. tostring(write_why))
  end
  return result("recovery-required", record.reason)
end

function Runtime:_clear_recovery()
  local removed, why = self:_remove_verified(self.paths.recovery)
  if not removed then return false, why end
  return self:_remove_verified(self.paths.recovery .. ".tmp")
end

-- Keep an unusable record's bytes under an evidence name and take both of its
-- names out of the way.
function Runtime:_dispose_record(path)
  for _, name in ipairs({path, path .. ".tmp"}) do
    if self:_path_present(name) then
      local preserved, preserve_why = self:_preserve_unusable(name)
      if not preserved then
        return false, "preserve:" .. tostring(preserve_why)
      end
    end
    local removed, remove_why = self:_remove_verified(name)
    if not removed then return false, tostring(remove_why) end
  end
  return true
end

-- Move a record this body could not use into the kit's quarantine directory,
-- under a name carrying the record's own digest: two different bad records are
-- two files, and the same bad record twice is one file. It is a move, never a
-- copy and a delete. A rename is one operation, so there is no moment at which
-- the bytes are neither under the record's name nor under the quarantine name,
-- and `_rename_no_replace` proves the source is gone and the destination is
-- there before it answers.
--
-- A record that cannot be read has no digest to carry, so its name says
-- `unreadable` and a second one replaces the first. That is the only evidence
-- this route can lose, and it is evidence nothing on this machine can read.
function Runtime:_quarantine_record(path, name)
  if not self:_path_present(path) then return true end
  local digest, digest_state = self:_hash_path(path)
  local tag = digest_state == "present" and digest:sub(1, 16) or "unreadable"
  local kept = join(self.paths.rejected, name .. "." .. tag .. ".unusable")
  if self:_path_present(kept) then
    local held, held_state = self:_hash_path(kept)
    if digest_state == "present" and held_state == "present"
        and held == digest then
      -- These exact bytes are already quarantined, so the durable copy stands
      -- and removing the record's own name loses nothing.
      local removed, remove_why = self:_remove_verified(path)
      if not removed then return false, tostring(remove_why) end
      return true, kept
    end
    local removed, remove_why = self:_remove_verified(kept)
    if not removed then return false, "occupied:" .. tostring(remove_why) end
  end
  local moved, move_why = self:_rename_no_replace(path, kept)
  if not moved then return false, tostring(move_why) end
  return true, kept
end

-- What is in this target's load path, when this app can prove what it is.
--
-- The proof is this app's own bundle descriptor: a digest in the load path
-- that the descriptor names is that build, at the version the descriptor gives
-- it. That is the same authority an ordinary install writes into this record
-- when it completes, so the rebuild extends no trust the install path does not
-- already extend. Any other digest returns nothing, which leaves identity
-- unknown rather than guessed: unknown authorizes no replacement and asks the
-- user before anything is placed over those bytes.
function Runtime:_status_from_proof(target, carried)
  if type(self.target_key) ~= "string" or type(target) ~= "table" then
    return nil
  end
  local valid = self.core.validate_target(target)
  if not valid or target.platform ~= self.target_key then return nil end
  local digest, digest_state = self:_hash_path(
    join(self.user_plugins, target.filename))
  if digest_state ~= "present" or digest ~= target.sha256 then return nil end
  return {
    -- No transaction wrote this entry, and the outcome says so. A rebuild can
    -- know only which build is in the load path: nothing was probed, and no
    -- previous Engine was displaced. The transaction id names this repair, so
    -- the entry also says which run rebuilt it.
    outcome = "rebuilt",
    target_version = target.version,
    target_sha256 = digest,
    transaction_id = self:_mint_transaction_id(),
    filename = target.filename,
    active_kind = "engine",
    active_version = target.version,
    active_sha256 = digest,
    -- Evidence about the load path rather than about a transaction, so it
    -- survives a rebuild exactly as it survives a completion.
    withdrawal = copy_table(carried),
  }
end

-- The entry that names a target whose statement a rebuild dropped and could
-- not replace. It carries no build and no installed identity, so it authorizes
-- nothing and every decision reads it as no entry at all. What it adds over
-- silence is that the record says the entry was lost, and says which repair
-- lost it.
function Runtime:_unresolved_entry(transaction_id)
  return {
    outcome = "unresolved",
    transaction_id = transaction_id,
    active_kind = "absent",
  }
end

-- What a record this kit cannot read still says about the targets in it, kept
-- only where today's entry validator accepts an entry on its own.
--
-- The rebuild proves this target's entry from the bytes in its load path and
-- this app's descriptor. It has no such proof for any other target, and there
-- is one thing about another target that no proof could recover: a parked
-- activation, which holds the transaction that certifies or rolls it back and
-- the reference to the backup artifact a rollback puts back. Damage to one
-- target's entry is not a reason to take another target's rollback away from
-- it, and a backup left on disk with nothing naming it is how a previous
-- Engine stops being anything's business. Digest equality proves which bytes
-- are in a load path; it does not prove they activated or that no rollback is
-- owed.
--
-- This reads the bad record and trusts none of it. Every entry it keeps is run
-- through `_validate_status_entry`, the same body that admits an entry a
-- completion writes, and an entry that fails is dropped with the record. It
-- grants no authority a valid record does not already grant: anything able to
-- write these bytes could as easily have written a record that validates
-- whole.
--
-- The record's schema number is not consulted. A record a pre-release kit
-- wrote under another schema, whose entries validate under today's entry
-- validator, states exactly what today's entries state and is salvaged; one
-- whose entries do not validate is not. This adds no reader for a shape that
-- is not today's: it applies today's validator to today's entry shape and
-- keeps nothing else.
--
-- This target's own entry is answered on its own rather than carried with the
-- others, because there is exactly one thing in it the caller keeps and the
-- proof is a better statement than the record about everything else it says.
-- A key that names no target this kit knows is not an entry any kit reads and
-- goes with the record, which is also why the walk is over the written key
-- order rather than a `pairs` walk of whatever the file happens to hold.
--
-- Returns the other targets' entries to carry, the target keys the record
-- named, and this target's own entry where today's validator accepts it, or
-- nil when the bytes are not a record with a table of targets in them.
function Runtime:_salvage_status_targets(path)
  local raw, read_state = self:_read_bytes(path)
  if read_state ~= "present" then return nil end
  local value = self:_decode(raw)
  if type(value) ~= "table" or type(value.targets) ~= "table" then
    return nil
  end
  local kept, named, own = {}, {}, nil
  for _, key in ipairs(self.core.TARGET_KEYS) do
    local entry = value.targets[key]
    if entry ~= nil then
      named[#named + 1] = key
      local valid = self:_validate_status_entry(entry)
      if valid and key == self.target_key then
        own = copy_table(entry)
      elseif valid then
        kept[key] = copy_table(entry)
      end
    end
  end
  return kept, named, own
end

-- The status record is the only durable statement of what is installed, and
-- every body that records an outcome writes into it: a completion, a rollback,
-- a parked activation, a withdrawal removal. A record this kit cannot read
-- refuses all of them, so a machine whose record was torn by a power loss,
-- edited by hand, or written by something that is not this kit ends up with an
-- Engine that may load and a kit that can never record anything again.
--
-- This is the route out of that, and it is the user's rather than the session
-- start's. It destroys durable state and it writes down an installed identity;
-- neither is a thing an unattended launch may do to a record every app on this
-- machine shares.
--
-- IT TRUSTS NOTHING IN THE BAD RECORD. What it writes for this target is
-- proof, taken from the file in this target's load path and this app's own
-- descriptor. Entries are carried only where `_validate_status_entry` accepts
-- them on their own, because the one thing no proof here can recover is a
-- parked activation and the backup its rollback puts back. That holds for this
-- target's own parked activation too: a `placed` entry of this target's that
-- validates is carried rather than replaced, because the process that
-- certifies or rolls it back is this one and nothing else on this machine
-- names the backup it would put back. Every other claim the record makes about
-- this target is the claim that may be the damage, and the proof replaces it.
-- Files in the load path are untouched either way.
--
-- NAME WHAT COULD NOT BE KEPT. Every target the record named and this route
-- could neither carry nor prove gets an `unresolved` entry: identity unknown,
-- nothing authorized, and the record saying the entry was lost rather than
-- saying nothing. That slice's own kit then finds the marker, asks the user
-- before anything is placed over its bytes, and reaches a confirmed repair it
-- can finish. When the bytes are not a record at all, the keys that were in it
-- cannot be known, so every target key this kit knows is named except one this
-- route can prove.
--
-- ORDER. Five steps, and the replacement is on disk before the evidence moves.
-- The record is read while it is still under its own name. Any temporary
-- beside it is quarantined next, so a stale one is neither taken for the
-- replacement nor overwritten by it. The rebuilt record is then written and
-- read back under the temporary name. Only then does the bad record move to
-- the quarantine, by one rename, so nothing is removed before the copy that
-- replaces it is durable. The last step renames the temporary over the name
-- that move left free and reads it back.
--
-- A crash between the write and the move leaves the bad record beside a
-- complete temporary, which is a state `_load_record` already answers: it
-- keeps the primary's bytes under `.unusable` and adopts the temporary, so the
-- next session reads the rebuilt record and this route is not entered again. A
-- crash between the move and the rename leaves no primary and the same
-- complete temporary, which that same read adopts, with the bad bytes in the
-- quarantine under their own digest. Neither window loses the salvage or the
-- markers. Writing after the move was the earlier order, and a crash in that
-- window left the machine with no status record at all: the next repair
-- rebuilt from proof alone, and what this route had salvaged and named
-- survived only in the quarantined copy, which nothing reads.
--
-- Returns nil when there is nothing to do, so the rest of `repair` answers.
function Runtime:_repair_status(target)
  local record, state = self:_load_status()
  if state == "valid" or state == "absent" then
    -- A record that reads refuses no write, so nothing here is urgent. The
    -- entry is still rebuilt when it does not name the bytes in the load path
    -- and this app can prove what they are, because the confirmed repair those
    -- states lead to refuses identical bytes and would be a control the user
    -- cannot finish.
    local _, journal_state = self:_load_journal()
    -- An open transaction writes this record itself, from its own outcome,
    -- which is a better statement than one inferred from the load path.
    if journal_state ~= "absent" then return nil end
    local existing = self:_status_entry(record)
    -- A parked activation is a transaction with no journal. It is certified or
    -- rolled back by the process that can load it, never overwritten here.
    if type(existing) == "table" and existing.outcome == "placed" then
      return nil
    end
    local entry = self:_status_from_proof(target,
      type(existing) == "table" and existing.withdrawal or nil)
    if entry == nil then return nil end
    if type(existing) == "table" and existing.active_kind == "engine"
        and existing.active_sha256 == entry.active_sha256 then
      return nil
    end
    local wrote, write_why = self:_set_status_entry(self.target_key, entry)
    if not wrote then
      return result("refuse", "status-rebuild:" .. tostring(write_why))
    end
    return result("repaired", "status-rebuilt")
  end

  -- Read while the record is still under its own name.
  local kept, named, own = self:_salvage_status_targets(self.paths.status)
  if kept == nil and not self:_path_present(self.paths.status) then
    -- The temporary is the record only when the primary is not there at all.
    -- `_load_record` adopts a valid temporary, so one reached here failed the
    -- same validation the primary would have.
    kept, named, own = self:_salvage_status_targets(
      self.paths.status .. ".tmp")
  end
  if kept == nil then kept, named = {}, self.core.TARGET_KEYS end

  -- A completed temporary beside the primary is adopted by the next read, so
  -- it goes to the quarantine before the replacement is written under that
  -- name. Its bytes are evidence rather than something this route overwrites,
  -- and nothing left standing there can be taken for the record written below.
  local temp_moved, temp_why = self:_quarantine_record(
    self.paths.status .. ".tmp", "status.json.tmp")
  if not temp_moved then
    return result("refuse", "status-quarantine-temp:" .. tostring(temp_why))
  end

  -- A parked activation is certified or rolled back by the process that can
  -- load it, which for this entry is this one, and the entry is the only thing
  -- naming the backup that rollback puts back. The proof says nothing at all
  -- about that, so this target's own parked entry is carried exactly as a
  -- sibling's is.
  local carried = nil
  if type(own) == "table" and own.outcome == "placed" then carried = own end
  local entry = carried or self:_status_from_proof(target, nil)
  local targets = kept
  if entry ~= nil then targets[self.target_key] = entry end
  -- One transaction id across the markers, because one repair dropped them
  -- all. A key already carried or already proven is not a loss and is not
  -- named.
  local dropped = self:_mint_transaction_id()
  for _, key in ipairs(named) do
    if targets[key] == nil then
      targets[key] = self:_unresolved_entry(dropped)
    end
  end

  -- The replacement is written and read back under the temporary name before
  -- the record it replaces moves, so no crash in this route leaves this
  -- machine with no status record: what stands after every step from here is
  -- either the bad record beside a complete temporary or that temporary alone,
  -- and the next read adopts the temporary in both.
  local raw, stage_why = self:_stage_record(self.paths.status,
    {schema = STATUS_SCHEMA, targets = targets})
  if not raw then
    return result("refuse", "status-rebuild:" .. tostring(stage_why))
  end
  local moved, move_why = self:_quarantine_record(self.paths.status,
    "status.json")
  if not moved then
    return result("refuse", "status-quarantine:" .. tostring(move_why))
  end
  local wrote, write_why = self:_promote_record(self.paths.status, raw)
  if not wrote then
    return result("refuse", "status-rebuild:" .. tostring(write_why))
  end
  -- What the record says about this target now: the transaction it was parked
  -- in, carried; the proof, rebuilt; or nothing this route could prove.
  local detail = "status-quarantined"
  if carried ~= nil then
    detail = "status-carried"
  elseif entry ~= nil then
    detail = "status-rebuilt"
  end
  return result("repaired", detail)
end

-- Recovery for a durable record this body can no longer read. Lua cannot fsync,
-- and a primary damaged outside the transaction protocol, or carrying a field a
-- newer body wrote, would otherwise refuse every launch forever. Repair resumes
-- a recorded recovery first, then keeps both journal records under evidence
-- names, disposes of the journal and of the sentinel that journal orphans, and
-- restores the previous Engine if the interruption left the live slot empty. It
-- touches no staged copy, no rejected copy, and no backup other than the one it
-- verifies and restores.
--
-- `options.target` is this app's bundle target, and it is the only proof the
-- status rebuild below has of what is in the load path. A caller that passes
-- none can still take an unusable status record out of the way; it just cannot
-- say what is installed afterwards.
function Runtime:repair(options)
  local target = type(options) == "table" and options.target or nil
  return self:_with_lock(function()
    -- The status record is answered before any other repair work, because
    -- every body that records an outcome writes into it: the completion of the
    -- very transaction the rest of this control would repair, that
    -- transaction's rollback, and the activation a second target parks in.
    local rebuilt = self:_repair_status(target)
    if rebuilt then return rebuilt end
    local record, record_state = self:_load_recovery()
    local journal, state = self:_load_journal()

    -- A removal that could not take the file (a sharing violation is the
    -- ordinary case) is retried, not repaired: there is nothing damaged to
    -- repair, and the user's control is the retry.
    if state == "valid" and self.core.journal_kind(journal) == "withdrawal-removal" then
      return self:_withdrawal_step(journal)
    end

    -- An install transaction for a withdrawn digest is abandoned by the step,
    -- and by this control too. Without it the user's repair can reach the
    -- state after a discharge and still not finish: the abandonment is what
    -- writes down whatever slot that transaction emptied, and until it runs
    -- the journal refuses every install behind it. Only with no obligation
    -- standing, because an obligation is answered before any record work and
    -- the abandonment itself refuses to overwrite one.
    if state == "valid" and record_state == "absent" then
      local digests, withdrawn_state = self:_withdrawn_state()
      if withdrawn_state == "clear"
          and digests[journal.target_sha256] == true then
        return self:_abandon_withdrawn_transaction(journal, digests)
      end
    end

    -- A valid journal describes the whole transaction, including the artifact
    -- a restoration would use, so it wins over a recovery record for the same
    -- file and that record is removed. Nothing can then drive the same
    -- restoration twice.
    if state == "valid" then
      -- A record naming another file is answered before the journal rather
      -- than discarded with it: the journal says nothing about that slot, and
      -- deleting the only statement that a file is owed its Engine is how the
      -- backup artifact beside it stops being anything's business. Every step
      -- of that restoration is a hash and a rename on a file this transaction
      -- never touches, so it runs here and the journal is answered by the next
      -- call. This is also what keeps an abandonment that refused to overwrite
      -- the obligation from being a dead end: the user's repair clears its way.
      if record_state == "valid" and record.filename ~= journal.filename then
        local restored, restore_why = self:_attempt_recovery(record)
        if not restored then return self:_hold_recovery(record, restore_why) end
        local cleared, clear_why = self:_clear_recovery()
        if not cleared then
          return result("refuse", "recovery-clear:" .. tostring(clear_why))
        end
        return result("repaired", "previous-restored")
      end
      local took_record = false
      if record_state == "valid" then
        local gone, gone_why = self:_clear_recovery()
        if not gone then
          return result("refuse", "recovery-dispose:" .. tostring(gone_why))
        end
        took_record = true
      elseif record_state ~= "absent" then
        local gone, gone_why = self:_dispose_record(self.paths.recovery)
        if not gone then
          return result("refuse", "recovery-dispose:" .. tostring(gone_why))
        end
        took_record = true
      end
      local rejected = self:_reject_target(journal)
      if rejected then return rejected end
      local outcome = self:_repair_sentinel(journal)
      -- A recovery record was taken out of the way, so a journal and sentinel
      -- that already agree are not a refusal for this call.
      if took_record and outcome.kind == "refuse"
          and outcome.detail == "journal-valid" then
        return result("repaired", "recovery")
      end
      return outcome
    end

    if record_state == "valid" then
      local restored, restore_why = self:_attempt_recovery(record)
      if not restored then return self:_hold_recovery(record, restore_why) end
      local cleared, clear_why = self:_clear_recovery()
      if not cleared then
        return result("refuse", "recovery-clear:" .. tostring(clear_why))
      end
      return result("repaired", "previous-restored")
    end
    local disposed = nil
    if record_state ~= "absent" then
      local gone, gone_why = self:_dispose_record(self.paths.recovery)
      if not gone then
        return result("refuse", "recovery-dispose:" .. tostring(gone_why))
      end
      disposed = "recovery"
    end

    local had_sentinel = self:_path_present(self.paths.sentinel)
      or self:_path_present(self.paths.sentinel .. ".tmp")
    if state == "absent" and not had_sentinel and not disposed then
      return result("idle", "no-transaction")
    end

    -- The obligation is written before any record is removed. A crash between
    -- the two would otherwise leave an empty live slot with nothing on disk to
    -- say so, and the next repair would report an idle installer over it.
    local pending = self:_recovery_from_status()
    if pending then
      local wrote, write_why = self:_write_record(self.paths.recovery, pending)
      if not wrote then
        return result("refuse", "recovery-write:" .. tostring(write_why))
      end
    end

    if state ~= "absent" then
      local gone, gone_why = self:_dispose_record(self.paths.journal)
      if not gone then
        return result("refuse", "repair-journal:" .. tostring(gone_why))
      end
      disposed = "journal"
    end
    local cleared, clear_why = self:_clear_sentinel()
    if not cleared then return result("refuse", clear_why) end
    self.probe_cache = nil
    disposed = disposed or "sentinel"

    if pending then
      local restored, restore_why = self:_attempt_recovery(pending)
      if not restored then return self:_hold_recovery(pending, restore_why) end
      local recovered, recover_why = self:_clear_recovery()
      if not recovered then
        return result("refuse", "recovery-clear:" .. tostring(recover_why))
      end
      return result("repaired", "previous-restored")
    end
    return result("repaired", disposed)
  end)
end

-- The user's discharge of an obligation nothing can meet.
--
-- The record holds one obligation and it is kept until the Engine it names is
-- back, which is what stops a previous Engine in a backup artifact from
-- becoming nobody's business. Three answers say it never will be: no artifact
-- at the recorded name, an artifact whose bytes are not that Engine, or an
-- Engine that has since been withdrawn. Held forever, such a record blocks the
-- abandonment that would write down what another slot is owed, and every
-- install stays behind the journal that abandonment would remove. That is a
-- machine with no Engine in the load path and no control that puts one there,
-- which is the one outcome this kit may not reach.
--
-- So it is a decision. The installer never takes it: only a user who has been
-- told the Engine cannot come back.
--
-- It touches one record. No journal, no backup artifact, no staged or
-- rejected copy, and no other slot's evidence: a transaction interrupted
-- mid-move still has its journal afterwards, which is the whole statement of
-- what it moved and where. The discharged record's bytes are kept under an
-- evidence name rather than deleted, so what that slot was owed is still
-- readable after the fact.
--
-- Unmeetability is proved here, inside the lock, immediately before the record
-- is taken, by the same rule the restoration runs under. A caller cannot
-- assert it, and an obligation that would have been met is refused rather than
-- skipped.
function Runtime:discharge_recovery()
  return self:_with_lock(function()
    local record, record_state, record_why = self:_load_recovery()
    if record_state == "absent" then
      return result("refuse", "recovery-discharge-absent")
    end
    if record_state ~= "valid" then
      -- A record nobody can read has not been proved unmeetable, and it is not
      -- this control's to guess at. The repair is what takes it out of the way,
      -- and it is offered for this class of detail.
      return result("refuse", "recovery-" .. tostring(record_state)
        .. ":" .. tostring(record_why))
    end
    local obstacle = self:_recovery_obstacle(record)
    if obstacle == nil then
      -- The Engine is there to be restored. Discharging here would throw away
      -- a restoration the next repair performs, which is exactly what this
      -- escape must not be usable for.
      return result("refuse", "recovery-discharge-meetable")
    end
    if not self.core.recovery_unmeetable(obstacle) then
      return result("refuse", "recovery-discharge-retry:" .. tostring(obstacle))
    end
    -- The record is the only statement of what that slot was owed, so it is
    -- kept under an evidence name. The primary goes first: a crash between the
    -- two leaves a completed temporary the next read adopts, which reinstates
    -- the obligation rather than losing it, and this control runs again.
    local preserved, preserve_why = self:_preserve_as(
      self.paths.recovery, ".discharged")
    if not preserved and self:_path_present(self.paths.recovery) then
      return result("refuse",
        "recovery-discharge-preserve:" .. tostring(preserve_why))
    end
    local removed, remove_why = self:_remove_verified(
      self.paths.recovery .. ".tmp")
    if not removed then
      return result("refuse",
        "recovery-discharge-temp:" .. tostring(remove_why))
    end
    return result("recovery-discharged", obstacle)
  end)
end

-- Quarantine records a digest that failed its own self-test, so clearing it is
-- the user's decision and never the installer's. It is refused while any
-- transaction record exists, because the rollback phases require the entry.
--
-- One digest is cleared, the one the caller names, because the control that
-- offers this says it allows the version in front of the user. Any other
-- rejected digest keeps its entry. The record is removed only once its last
-- entry is gone.
function Runtime:clear_quarantine(sha256)
  if not is_lower_sha256(sha256) then
    return result("refuse", "quarantine-clear-sha256")
  end
  return self:_with_lock(function()
    local _, state = self:_load_journal()
    if state ~= "absent" then
      return result("refuse", "quarantine-clear-journal:" .. tostring(state))
    end
    local record, record_state, record_why = self:_load_quarantine()
    if not record then
      return result("refuse", "quarantine-clear-load:"
        .. tostring(record_state) .. ":" .. tostring(record_why))
    end
    local kept = {}
    local found = false
    for _, entry in ipairs(record.entries or {}) do
      if entry.sha256 == sha256 then found = true else kept[#kept + 1] = entry end
    end
    if not found then
      return result("refuse", "quarantine-clear-absent")
    end
    if #kept > 0 then
      record.entries = kept
      local written, write_why = self:_write_record(self.paths.quarantine, record)
      if not written then
        return result("refuse", "quarantine-write:" .. tostring(write_why))
      end
      return result("quarantine-cleared", sha256)
    end
    local removed, why = self:_remove_verified(self.paths.quarantine)
    if not removed then
      return result("refuse", "quarantine-remove:" .. tostring(why))
    end
    removed, why = self:_remove_verified(self.paths.quarantine .. ".tmp")
    if not removed then
      return result("refuse", "quarantine-temp-remove:" .. tostring(why))
    end
    return result("quarantine-cleared", sha256)
  end)
end

function Runtime:inspect()
  return self:_with_lock(function()
    local journal, state, why = self:_load_journal()
    if not journal then
      return {state = state, reason = why}
    end
    if self.core.journal_kind(journal) ~= "install" then
      return {
        state = journal.phase,
        transaction_id = journal.transaction_id,
        kind = self.core.journal_kind(journal),
        target_sha256 = journal.target_sha256,
      }
    end
    local snapshot, snapshot_why = self:_snapshot(journal)
    if not snapshot then return {state = "refuse", reason = snapshot_why} end
    return {
      state = journal.phase,
      transaction_id = journal.transaction_id,
      target_version = journal.target_version,
      failures = journal.failures,
      same_session = snapshot.same_session,
      quarantine = snapshot.quarantine,
      files = copy_table(snapshot.files),
      next = self.core.next_action(snapshot),
    }
  end)
end

-- =============================================================================
-- Withdrawal
-- =============================================================================

-- What one entry from a bundle descriptor looks like once it has been checked.
-- Merging is append-only between cooperating apps: nothing here removes an
-- entry another app wrote, and a digest already recorded by the same key and
-- signature is not recorded twice.
function Runtime:merge_withdrawn(entries)
  if not is_plain_array(entries) then
    return result("refuse", "withdrawn-merge-input")
  end
  return self:_with_lock(function()
    return self:_merge_withdrawn_locked(entries)
  end)
end

-- The merge body, already holding the lock. `session_start` uses it directly
-- so this app's own descriptor is merged inside the same acquisition that then
-- reads the record.
function Runtime:_merge_withdrawn_locked(entries)
  do
    local value, state, why = self:_load_record(self.paths.withdrawn,
      function(record) return self:_validate_withdrawn(record) end)
    if state ~= "valid" and state ~= "absent" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(state) .. ":" .. tostring(why))
    end
    local record = state == "valid" and copy_table(value)
      or {schema = 1, entries = {}}
    local seen = {}
    for _, entry in ipairs(record.entries) do
      seen[entry.sha256 .. "\0" .. entry.key_id .. "\0" .. entry.signature] = true
    end
    local added, rejected = 0, {}
    for index, incoming in ipairs(entries) do
      local authorized, reason = self:_entry_authorizes(incoming)
      if not authorized then
        rejected[#rejected + 1] = index .. ":" .. tostring(reason)
      else
        local key = incoming.sha256 .. "\0" .. incoming.key_id .. "\0"
          .. incoming.signature
        if not seen[key] then
          if #record.entries >= Runtime.WITHDRAWN_MAX_ENTRIES then
            return result("refuse", "withdrawn-full")
          end
          seen[key] = true
          record.entries[#record.entries + 1] = {
            sha256 = incoming.sha256,
            payload = incoming.payload,
            signature = incoming.signature,
            key_id = incoming.key_id,
          }
          added = added + 1
        end
      end
    end
    if added == 0 then
      return result("withdrawn-merged", "0:" .. tostring(#rejected))
    end
    local wrote, write_why = self:_write_record(self.paths.withdrawn, record)
    if not wrote then
      return result("refuse", "withdrawn-write:" .. tostring(write_why))
    end
    return result("withdrawn-merged", tostring(added) .. ":" .. tostring(#rejected))
  end
end

-- The user-confirmed repair for a record this body cannot read. It keeps the
-- unusable bytes under an evidence name, rewrites the record from the entries
-- that are not provably worthless, and reports what it dropped. A record that
-- will not decode at all drops everything, which the caller has to be told.
--
-- It drops only what it checked and found wanting. An entry this body could
-- not check is kept, and an entry signed under a key this app does not hold is
-- one of those: discarding it would let the app that cannot verify a
-- withdrawal be the one that deletes it for every app that can, and a repair
-- is offered to make a record readable, never to shorten it.
function Runtime:repair_withdrawn()
  return self:_with_lock(function()
    local raw, read_state = self:_read_bytes(self.paths.withdrawn)
    local kept, dropped = {}, 0
    if read_state == "present" then
      local decoded = self:_decode(raw)
      if type(decoded) == "table" and is_plain_array(decoded.entries) then
        for _, entry in ipairs(decoded.entries) do
          local authorized, _, proved = self:_entry_authorizes(entry)
          if authorized or proved ~= true then
            kept[#kept + 1] = {
              sha256 = entry.sha256,
              payload = entry.payload,
              signature = entry.signature,
              key_id = entry.key_id,
            }
          else
            dropped = dropped + 1
          end
        end
      elseif type(decoded) == "table" then
        dropped = -1
      else
        dropped = -1
      end
    end
    if read_state ~= "absent" then
      local preserved, preserve_why = self:_preserve_unusable(self.paths.withdrawn)
      if not preserved and self:_path_present(self.paths.withdrawn) then
        return result("refuse", "withdrawn-preserve:" .. tostring(preserve_why))
      end
    end
    -- A completed temporary beside the primary would be adopted by the next
    -- read and undo this repair. It goes with the record it belonged to.
    local temp_removed, temp_why = self:_remove_verified(
      self.paths.withdrawn .. ".tmp")
    if not temp_removed then
      return result("refuse", "withdrawn-temp-remove:" .. tostring(temp_why))
    end
    local wrote, write_why = self:_write_record(self.paths.withdrawn,
      {schema = 1, entries = kept})
    if not wrote then
      return result("refuse", "withdrawn-write:" .. tostring(write_why))
    end
    -- A negative count is the record that would not decode: every entry it may
    -- have held is gone and nobody can say how many there were.
    return result("withdrawn-repaired", tostring(#kept) .. ":"
      .. (dropped < 0 and "unknown" or tostring(dropped)))
  end)
end

-- The read every caller uses. Returns the digest set, the record state, and
-- the entries that did not verify, each saying whether that answer was proved.
-- An unusable record carries an empty set rather than none, because the state
-- is the answer there and a caller must not be able to index its way past it.
function Runtime:withdrawn()
  local value, lock_why = self:_with_lock(function()
    local digests, state, dropped, why = self:_withdrawn_state()
    return {
      kind = state == "clear" and "withdrawn-clear" or "withdrawn-unusable",
      detail = why,
      digests = digests or {},
      dropped = dropped,
    }
  end)
  if type(value) ~= "table" then
    -- The lock, not the record. Another app holding it for a moment says
    -- nothing about what the record contains, and calling that an unreadable
    -- record would refuse an Engine for the rest of the session over a moment
    -- of contention. It is a third answer, and the caller asks again.
    return {
      kind = "withdrawn-undecided",
      detail = tostring(lock_why),
      digests = {},
      dropped = {},
    }
  end
  return value
end

function Runtime:_withdrawal_journal(sha256)
  if type(self.target_key) ~= "string" then return nil, "no-target-key" end
  local filename = self.core.PLATFORM_FILENAMES[self.target_key]
  if filename == nil or filename ~= self.live_filename then
    return nil, "no-live-filename"
  end
  local journal = {
    schema = self.core.SCHEMA,
    kind = "withdrawal-removal",
    transaction_id = self:_mint_transaction_id(),
    phase = "withdrawal-pending",
    platform = self.target_key,
    target = self.target_key,
    filename = filename,
    target_sha256 = sha256,
    previous_kind = "absent",
    failures = 0,
    writer_instance = self.instance_id,
  }
  local ok, why = self.core.validate_journal(journal)
  if not ok then return nil, why end
  return journal
end

function Runtime:_withdrawal_snapshot(journal)
  local live = join(self.user_plugins, journal.filename)
  local digest, state = self:_hash_path(live)
  local class = "unreadable"
  if state == "absent" then
    class = "absent"
  elseif state == "present" then
    class = digest == journal.target_sha256 and "withdrawn" or "other"
  end
  return {
    lock = self:verify_lock() and "owned" or "lost",
    journal = journal,
    live = class,
  }, live
end

-- A removal takes a file out of the load path on the record's authority, so it
-- runs only while this app's own reading of the record still says that digest
-- is withdrawn. An entry this app cannot prove is not authority for this app to
-- delete anything.
--
-- What it does instead is drop the transaction, from the phases where nothing
-- has been done yet. Refusing would leave a journal no control can clear and
-- block every app's installs behind it; dropping it touches no file, and the
-- app whose keys do authorize the entry opens the removal again at its own
-- session start. A terminal phase is not dropped: it is writing down a removal
-- that already happened, and it deletes nothing.
--
-- The drop is reached only through a record that read clear, and a record
-- reads clear only when every entry in it produced a proof. So an app that
-- could not conclusively check an entry never drops anything: it refuses on
-- the line above, and the journal stays for an app that can check it. That is
-- the whole rule, and it is the reason the verifier has to separate a key this
-- app does not hold from a signature it checked and rejected.
--
-- Both callers arrive here, the step and the user's repair, so the rule is
-- here rather than in either of them.
function Runtime:_withdrawal_step(journal)
  if not self.core.WITHDRAWAL_TERMINAL_PHASES[journal.phase] then
    local digests, withdrawn_state, _, withdrawn_why = self:_withdrawn_state()
    if withdrawn_state ~= "clear" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(withdrawn_why))
    end
    if digests[journal.target_sha256] ~= true then
      local removed, remove_why = self:_remove_verified(self.paths.journal)
      if not removed then
        return result("refuse", "journal-remove:" .. tostring(remove_why))
      end
      removed, remove_why = self:_remove_verified(self.paths.journal .. ".tmp")
      if not removed then
        return result("refuse", "journal-temp-remove:" .. tostring(remove_why))
      end
      self.probe_cache = nil
      return result("withdrawal-abandoned", journal.target_sha256)
    end
  end
  local snapshot, live_path = self:_withdrawal_snapshot(journal)
  local decision = self.core.next_withdrawal_action(snapshot)
  if decision.kind == "refuse" then
    return result("refuse", tostring(decision.reason)
      .. (decision.detail and (":" .. tostring(decision.detail)) or ""))
  end
  if decision.kind == "set-phase" then
    local changed = copy_table(journal)
    changed.phase = decision.next_phase
    local ok, why = self:_write_journal(changed)
    return ok and result("advanced", decision.next_phase)
      or result("refuse", why)
  end
  if decision.kind == "remove-withdrawn-live" then
    -- Rehashed here, inside the lock, immediately before the removal. The
    -- classification above was taken in this same locked body; this second
    -- read is what makes the removal bound to the digest rather than to the
    -- name, so bytes that changed under a non-cooperating writer are not
    -- removed by mistake.
    local digest, state = self:_hash_path(live_path)
    if state ~= "present" then
      return result("refuse", "withdrawal-live-" .. tostring(state))
    end
    if digest ~= journal.target_sha256 then
      return result("refuse", "withdrawal-live-changed")
    end
    local removed, why = self:_remove_verified(live_path)
    if not removed then
      -- A sharing violation looks exactly like this. It is recorded and
      -- retried; it is not an activation failure and it spends nothing.
      return result("refuse", "withdrawal-remove:" .. tostring(why))
    end
    return result("advanced", "remove-withdrawn-live")
  end
  if decision.kind ~= "complete-withdrawal" then
    return result("refuse", "unhandled-action:" .. tostring(decision.kind))
  end

  local state = journal.phase == "withdrawal-removed" and "removed"
    or journal.phase == "withdrawal-superseded" and "superseded" or "absent"
  local target_key = self.core.journal_target(journal)
  local record, record_state, record_why = self:_load_status()
  if record_state ~= "valid" and record_state ~= "absent" then
    return result("refuse", "status-" .. tostring(record_state)
      .. ":" .. tostring(record_why))
  end
  local entry = copy_table(self:_status_entry(record, target_key)) or {}
  entry.filename = journal.filename
  entry.withdrawal = {
    sha256 = journal.target_sha256,
    state = state,
    transaction_id = journal.transaction_id,
  }
  -- The install evidence describes bytes that are no longer in the load path,
  -- so it is dropped. `superseded` is the exception: another app's healthy
  -- install is there now, and this entry's disagreement with it is exactly the
  -- unknown identity the policy wants the next repair to see.
  if state ~= "superseded" and entry.active_sha256 == journal.target_sha256 then
    entry.outcome = nil
    entry.target_version = nil
    entry.target_sha256 = nil
    entry.transaction_id = nil
    entry.active_kind = nil
    entry.active_version = nil
    entry.active_sha256 = nil
    entry.pending = nil
  end
  local wrote, write_why = self:_set_status_entry(target_key, entry)
  if not wrote then
    return result("refuse", "withdrawal-status:" .. tostring(write_why))
  end
  -- The activation this target may have been waiting for announced a digest
  -- that is gone. Its sentinel would refuse every later launch.
  if state ~= "superseded" then
    local cleared, clear_why = self:_clear_sentinel()
    if not cleared then return result("refuse", clear_why) end
  end
  local removed, remove_why = self:_remove_verified(self.paths.journal)
  if not removed then
    return result("refuse", "journal-remove:" .. tostring(remove_why))
  end
  removed, remove_why = self:_remove_verified(self.paths.journal .. ".tmp")
  if not removed then
    return result("refuse", "journal-temp-remove:" .. tostring(remove_why))
  end
  self.probe_cache = nil
  return result("withdrawal-" .. state, journal.target_sha256)
end

-- One call per REAPER session, before anything else asks the installer for
-- work. It reads the withdrawal record, opens the removal transition when the
-- digest in this host's load path is withdrawn, and otherwise resumes an
-- activation this target parked for a process that could load it. A restart is
-- the only event that changes either answer, and a session is a restart.
function Runtime:session_start()
  return self:_with_lock(function()
    if self.withdrawal_entries then
      local entries = self.withdrawal_entries
      self.withdrawal_entries = nil
      local merged = self:_merge_withdrawn_locked(entries)
      if merged.kind == "refuse" then return merged end
    end
    local digests, withdrawn_state, _, withdrawn_why = self:_withdrawn_state()
    if withdrawn_state ~= "clear" then
      return result("refuse", "withdrawal-record-unusable:"
        .. tostring(withdrawn_why))
    end
    local journal, journal_state = self:_load_journal()
    if journal_state == "valid" then
      return result("resume", self.core.journal_kind(journal))
    end
    if journal_state ~= "absent" then
      return result("refuse", "journal-" .. tostring(journal_state))
    end

    local opened = self:_open_withdrawal(digests)
    if opened then return opened end

    local resumed = self:_resume_activation(digests)
    if resumed then return resumed end
    self:_cleanup_completed_artifacts()
    return result("idle", "no-transaction")
  end)
end

-- The runtime policy for one bundle target, in one call, from the durable
-- records plus what this process has loaded. It answers three questions that
-- must never share a rule: what is installed and whether that is known, whether
-- this process may call the Engine it loaded, and whether this app may install
-- its bundle.
function Runtime:evaluate(target, loaded)
  return self:_with_lock(function()
    local digests, withdrawn_state, dropped, withdrawn_why = self:_withdrawn_state()
    local withdrawn = withdrawn_state == "clear" and "clear" or "unusable"
    digests = digests or {}
    local live_digest, live_state = nil, "absent"
    local filename = type(target) == "table" and target.filename or self.live_filename
    if type(filename) == "string" then
      live_digest, live_state = self:_hash_path(join(self.user_plugins, filename))
    end
    local status, status_state = self:_load_status()
    local entry = status_state == "valid"
      and self:_status_entry(status, self.target_key) or nil
    local record_state = "absent"
    if status_state == "valid" then
      record_state = type(entry) == "table" and entry.active_kind == "engine"
        and "valid" or "absent"
    elseif status_state ~= "absent" then
      record_state = status_state == "invalid" and "invalid" or "unreadable"
    end
    local identity = self.core.decide_identity({
      placed = {
        state = live_state == "present" and "present"
          or live_state == "absent" and "absent" or "unreadable",
        sha256 = live_digest,
      },
      record = {
        state = record_state,
        version = type(entry) == "table" and entry.active_version or nil,
        sha256 = type(entry) == "table" and entry.active_sha256 or nil,
      },
    })
    local quarantine = self:_load_quarantine() or {entries = {}}
    local loaded_view = type(loaded) == "table" and loaded or {state = "absent"}
    local use = self.core.decide_use({
      withdrawn = loaded_view.sha256 ~= nil and digests[loaded_view.sha256]
        and "withdrawn" or withdrawn,
      loaded = loaded_view,
      quarantined = loaded_view.sha256 ~= nil
        and self:_target_quarantined(quarantine, loaded_view.sha256) or false,
      compatibility = loaded_view.compatibility,
      minimum_version = loaded_view.minimum_version,
    })
    local install = nil
    if type(target) == "table" then
      local journal, journal_state = self:_load_journal()
      local relation = "absent"
      if journal_state == "valid" then
        relation = self.core.journal_kind(journal) == "install"
          and journal.platform == target.platform
          and journal.filename == target.filename
          and journal.target_version == target.version
          and journal.target_sha256 == target.sha256 and "same" or "other"
      elseif journal_state ~= "absent" then
        relation = journal_state == "invalid" and "invalid" or "unreadable"
      end
      install = self.core.decide_install({
        lock = self:verify_lock() and "owned" or "lost",
        target = target,
        withdrawn = digests[target.sha256] and "withdrawn" or withdrawn,
        installed_withdrawn = live_state == "present"
          and digests[live_digest] == true or false,
        journal_state = relation,
        identity = identity,
        quarantined = self:_target_quarantined(quarantine, target.sha256),
        installed_quarantined = live_state == "present"
          and self:_target_quarantined(quarantine, live_digest) or false,
        installed_compatibility = type(loaded_view.compatibility) == "table"
          and loaded_view.compatibility.state == "incompatible"
          and "incompatible" or "unknown",
        replace_equal_version = false,
      })
    end
    return {
      withdrawn = withdrawn,
      withdrawn_detail = withdrawn_why,
      withdrawn_dropped = dropped,
      identity = identity,
      placed_sha256 = live_digest,
      placed_state = live_state,
      use = use,
      install = install,
    }
  end)
end

return Runtime
-- END ENGINE COMPONENT InstallerRuntime
end)()

EngineKit.InstallerHost = (function()
-- BEGIN ENGINE COMPONENT InstallerHost
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- =============================================================================
-- Engine installer REAPER host adapter
-- Copyright (c) 2026 Michael Briggs. All rights reserved.
-- =============================================================================
--
-- This module supplies the REAPER-specific seams used by the durable installer
-- runtime. It does not choose or download an Engine build. Startup recovery is
-- armed only when a durable transaction already exists.

local Host = {}

local EngineContract = EngineKit.Contract
if type(EngineContract) ~= "table"
    or type(EngineContract.validate) ~= "function" then
  error("Engine contract validator unavailable")
end

-- Admitted 2026-09-07: the `win-arm64` artifact is now ARM64EC, which is the
-- only kind of ARM module an ARM64EC process loads, and it was qualified by
-- loading it inside REAPER itself. Host win-arm (Surface Pro X, SQ1, Windows
-- 11 26100), portable REAPER 7.79 win11_arm64ec_beta at C:\REAPER_Test launched
-- with -newinst. reaper_mbriggs_helper-arm64.dll registered 43 functions,
-- returned engine_version 1.0.2, core_abi 2, build_channel production through
-- MBH_GetContractV1, hashed itself back to the digest it was placed as, and
-- completed its unload sequence.
--
-- NO DIGEST IS NAMED HERE. A Windows link is not byte-reproducible even under
-- `/Brepro`, so the same source builds to a different digest in every lane run
-- and a digest written into this comment is wrong the next time anything is
-- built. What pins the shipped bytes is the qualification run named above and
-- the lane report the release package is cut from, whose receipts carry the
-- digests; `release/README.md` states that rule. The qualification itself is
-- written up under "The ReaAssist installer admits native Windows ARM hosts"
-- in the Engine repository's `README.md`, with the hardware sessions of
-- 2026-09-07 and 2026-09-08. Set this false to withdraw the platform from a
-- later release.
local WINDOWS_ARM64_ENGINE_RUNTIME_QUALIFIED = true

-- Admitted 2026-09-07: the packaged container artifact passed a native runtime
-- qualification under WSL2 Ubuntu 24.04 on that same arm64 host. Same audit
-- section. Set this false to withdraw the platform from a later release.
local LINUX_ARM64_ENGINE_RUNTIME_QUALIFIED = true

-- Admitted 2026-09-07: the Mac x86_64 slice passed a runtime qualification
-- under Rosetta 2 on the M1. Same audit section. `OSX64` is the
-- Intel REAPER build on any Mac, so this also admits Apple Silicon running
-- that build under Rosetta; the arm64 REAPER build reports `macOS-arm64` and
-- takes the arm64 slice. Set this false to withdraw the platform.
local MAC_X64_ENGINE_RUNTIME_QUALIFIED = true

-- One exact file image is enough to reuse the digest while the installer
-- copies a package artifact through its temporary and staged paths and through
-- the following journal-advancement ticks. Clear it as soon as the transaction
-- stops advancing so Engine bytes do not remain pinned for the REAPER session.
local MAX_HASH_CACHE_ENTRIES = 1
local HASH_CACHE_PROGRESS_STATES = {
  advanced = true,
  probed = true,
  resume = true,
  staged = true,
}

Host.MODULE_VERSION = 2
Host.EXT_NAMESPACE = "mbriggs_helper"
Host.SESSION_KEY = "engine_installer_session_id"
Host.SELF_TEST_TEXT = "abc"
Host.SELF_TEST_SHA256 =
  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

Host.REQUIRED_ABI = 2
Host.CONTRACT_BUFFER_BYTES = 32 * 1024
Host.MAX_RESULT_BUFFER_BYTES = 256 * 1024
Host.REQUIRED_SUBSYSTEMS = {
  core = 1,
  client = 1,
  inference = 1,
  stateless_helpers = 1,
}
Host.ACTIVATION_REQUIRED_SUBSYSTEMS = {
  core = 1,
  client = 1,
  inference = 2,
  input_media = 1,
  stateless_helpers = 1,
}
Host.ACTIVATION_REQUIRED_INFERENCE_PROFILES = {
  "custom_openai_chat_v1",
  "custom_openai_responses_v1",
  "local_openai_chat_v1",
  "local_openai_responses_v1",
  "local_openai_chat_private_v1",
  "local_openai_responses_private_v1",
}
Host.REQUIRED_STATUS_VOCABULARY = {
  "cancelled", "completed", "failed", "queued", "streaming",
}
Host.ACTIVATION_REQUIRED_STATUS_VOCABULARY = {
  "cancelled", "closed", "completed", "consumed", "failed", "loading",
  "queued", "ready", "streaming",
}
Host.REQUIRED_ERROR_VOCABULARY = {
  "capacity", "capability", "internal", "invalid_argument",
  "invalid_state", "not_supported", "protocol", "provider", "transport",
}

Host.REQUIRED_EXPORTS = {
  "MBH_GetVersion", "MBH_GetABI", "MBH_GetContractV1", "MBH_GetBuildInfo",
  "MBH_ClientOpenV1", "MBH_ClientCloseV1",
  "MBH_ClientGetOperationalStatsV1",
  "MBH_InferenceV1Start", "MBH_InferenceV1Status", "MBH_InferenceV1Read",
  "MBH_InferenceV1Cancel", "MBH_InferenceV1Close",
  "MBH_SHA256File", "MBH_SHA256String",
  "MBH_Dialog_BrowseForSaveFile", "MBH_Dialog_BrowseForOpenFiles",
  "MBH_Dialog_BrowseForFolder", "MBH_Window_GetFocus",
  "MBH_Window_SetFocus", "MBH_Window_IsWindow", "MBH_Window_GetRect",
  "MBH_Mouse_GetState", "MBH_File_Stat",
}
Host.ACTIVATION_REQUIRED_EXPORTS = {}
for index, name in ipairs(Host.REQUIRED_EXPORTS) do
  Host.ACTIVATION_REQUIRED_EXPORTS[index] = name
end
for _, name in ipairs({
  "MBH_InputMediaV1CreateFromFile", "MBH_InputMediaV1Status",
  "MBH_InputMediaV1Close", "MBH_InferenceV1StartWithInputMedia",
  "MBH_InferenceV1ConversationOpen",
  "MBH_InferenceV1StartWithConversation",
  "MBH_InferenceV1ConversationCommit",
  "MBH_InferenceV1ConversationClose",
}) do
  Host.ACTIVATION_REQUIRED_EXPORTS[
    #Host.ACTIVATION_REQUIRED_EXPORTS + 1] = name
end

Host.FORBIDDEN_PRODUCTION_EXPORTS = {
  "MBH_HttpStart", "MBH_HttpStatus", "MBH_HttpRead", "MBH_HttpCancel",
  "MBH_HttpClose", "MBH_ExecStart", "MBH_ExecStatus", "MBH_ExecRead",
  "MBH_ExecKill", "MBH_ExecClose",
}

-- Refusals a durable recovery action can still clear. Everything else is left
-- for a restart, because the installer must not offer a remedy it cannot take.
-- Every sentinel refusal is repairable: with a valid journal the sentinel is
-- rebuilt from it, and with no journal it is disposed of. A recovery record
-- this body cannot read is repairable for the same reason as a journal.
local REPAIRABLE_PREFIXES = {
  "journal-invalid", "journal-unreadable", "sentinel-", "recovery-",
}

-- The refusal every runtime body gives for a record it could not read, with or
-- without a reason after it.
local WITHDRAWAL_UNUSABLE_PREFIX = "withdrawal-record-unusable"

-- What a refusal looks like when the installer's own status record is the
-- thing that is wrong. Every body that records an outcome writes into that
-- record and each puts its own word in front of the refusal, so the marker is
-- looked for anywhere in the detail rather than at its front: `status-write:`
-- from a completion, `park-status:` from a parked activation,
-- `withdrawal-status:` from a removal.
local STATUS_UNUSABLE_MARKERS = {"status-invalid", "status-unreadable"}

-- The confirmed repair's refusal when the bytes it would replace are already
-- the ones this app would install. Nothing is wrong with the file: what is
-- wrong is the record that does not name it, and the repair below is the
-- control that writes one.
local IDENTICAL_BYTES = "repair-identical-bytes"

-- The identity refusals whose cause is the installer's own record rather than
-- the bytes in the load path. The repair answers them by rebuilding this
-- target's entry from the file in the load path and this app's descriptor.
local IDENTITY_RECORD_PREFIX = "identity-unknown:record-"

local function status_repairable(detail)
  if type(detail) ~= "string" then return false end
  if detail == IDENTICAL_BYTES then return true end
  for _, marker in ipairs(STATUS_UNUSABLE_MARKERS) do
    if detail:find(marker, 1, true) ~= nil then return true end
  end
  return false
end

-- The actions whose runtime body reads the withdrawal record before it does
-- anything else. Any action's refusal can name an unusable record; only these
-- prove, by succeeding, that the record was readable when they ran.
local WITHDRAWAL_READING_ACTIONS = {
  session_start = true,
  step = true,
  stage = true,
  merge_withdrawn = true,
  repair_withdrawn = true,
}

-- The compatibility question this app asks of a loaded Engine, in the shape
-- the decision core wants. The ABI is exact; the subsystems and exports are
-- the ones this app calls.
function Host.contract_compatibility(core, contract, exports)
  if type(core) ~= "table" or type(core.decide_compatibility) ~= "function" then
    return {state = "incompatible", reason = "core"}
  end
  local value = type(contract) == "table" and contract.value or nil
  if type(value) ~= "table" then
    return {state = "incompatible", reason = "contract"}
  end
  return core.decide_compatibility({
    core_abi = value.core_abi,
    required_abi = Host.REQUIRED_ABI,
    subsystems = value.subsystems,
    required_subsystems = Host.REQUIRED_SUBSYSTEMS,
    exports = type(exports) == "table" and exports
      or (type(contract.exports) == "table" and contract.exports or {}),
    required_exports = Host.REQUIRED_EXPORTS,
  })
end

local function repairable(detail)
  if type(detail) ~= "string" then return false end
  for _, prefix in ipairs(REPAIRABLE_PREFIXES) do
    if detail:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Whether a reported recovery is one no restoration will ever finish, which is
-- the only state the discharge control is offered from. The classification is
-- the decision core's, so this control and the runtime body that performs the
-- discharge cannot disagree about which obligations qualify; without a core to
-- ask, nothing is offered.
local function recovery_unmeetable(core, detail)
  if type(core) ~= "table"
      or type(core.recovery_unmeetable) ~= "function" then
    return false
  end
  local ok, value = pcall(core.recovery_unmeetable, detail)
  return ok and value == true
end

local function slash(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function join(left, right)
  return slash(left) .. "/" .. tostring(right or ""):gsub("^/+", "")
end

local function valid_session_id(value)
  return type(value) == "string"
    and value:match("^session_[A-Za-z0-9_%-]+$") ~= nil
end

local strict_token_set = EngineContract.strict_token_set

local INFERENCE_PROFILE_PROTOCOLS = {
  custom_openai_chat_v1 = "openai_chat_completions",
  custom_openai_responses_v1 = "openai_responses",
  local_openai_chat_v1 = "openai_chat_completions",
  local_openai_responses_v1 = "openai_responses",
  local_openai_chat_private_v1 = "openai_chat_completions",
  local_openai_responses_private_v1 = "openai_responses",
}

local positive_integer = EngineContract.positive_integer

local function api_exists(reaper_api, name)
  if type(reaper_api) ~= "table"
      or type(reaper_api.APIExists) ~= "function" then
    return false
  end
  local ok, value = pcall(reaper_api.APIExists, name)
  return ok and value == true and type(reaper_api[name]) == "function"
end

local function call_pair_string(fn)
  local ok, result_ok, value = pcall(fn)
  if not ok or result_ok ~= true or type(value) ~= "string" then return nil end
  return value
end

local function call_pair_string_with_buffer(fn, ...)
  local ok, result_ok, value = pcall(fn, ...)
  if not ok or result_ok ~= true or type(value) ~= "string" then return nil end
  return value
end

function Host.clear_hash_cache(cache)
  if type(cache) ~= "table" then return false end

  local contents = rawget(cache, "contents")
  if type(contents) == "table" then
    local key, entry = next(contents)
    while key ~= nil do
      if type(entry) == "table" then
        rawset(entry, "bytes", nil)
        rawset(entry, "digest", nil)
      end
      rawset(contents, key, nil)
      key, entry = next(contents)
    end
  end

  local paths = rawget(cache, "paths")
  if type(paths) == "table" then
    local key = next(paths)
    while key ~= nil do
      rawset(paths, key, nil)
      key = next(paths)
    end
  end

  rawset(cache, "contents", {})
  rawset(cache, "paths", {})
  return true
end

function Host.hash_file(io_api, hash_bytes, path, cache)
  if type(io_api) ~= "table" or type(io_api.open) ~= "function"
      or type(hash_bytes) ~= "function" or type(path) ~= "string"
      or path == "" then
    return nil, "invalid"
  end
  local ok_open, file = pcall(io_api.open, path, "rb")
  if not ok_open or not file then
    if type(cache) == "table" and type(cache.paths) == "table" then
      cache.paths[path] = nil
    end
    return nil, ok_open and "absent" or "unreadable"
  end
  local ok_read, bytes = pcall(function() return file:read("*a") end)
  pcall(function() file:close() end)
  if not ok_read or type(bytes) ~= "string" then
    if type(cache) == "table" and type(cache.paths) == "table" then
      cache.paths[path] = nil
    end
    return nil, "unreadable"
  end
  if type(cache) == "table" then
    if type(cache.paths) ~= "table" then cache.paths = {} end
    if type(cache.contents) ~= "table" then cache.contents = {} end
    local known = cache.paths[path]
    if type(known) == "table" and known.bytes == bytes
        and type(known.digest) == "string" then
      return known.digest, "present"
    end
    for _, candidate in ipairs(cache.contents) do
      if type(candidate) == "table" and candidate.bytes == bytes
          and type(candidate.digest) == "string" then
        cache.paths[path] = candidate
        return candidate.digest, "present"
      end
    end
  end
  local ok_hash, digest = pcall(hash_bytes, bytes)
  if not ok_hash or type(digest) ~= "string" or #digest ~= 64
      or digest:match("^[0-9a-f]+$") == nil then
    return nil, "unreadable"
  end
  if type(cache) == "table" then
    if #cache.contents >= MAX_HASH_CACHE_ENTRIES then
      local expired = table.remove(cache.contents, 1)
      for cached_path, entry in pairs(cache.paths) do
        if rawequal(entry, expired) then cache.paths[cached_path] = nil end
      end
    end
    local entry = {bytes = bytes, digest = digest}
    cache.paths[path] = entry
    cache.contents[#cache.contents + 1] = entry
  end
  return digest, "present"
end

function Host.hash_file_posix(io_api, path, is_macos)
  if type(io_api) ~= "table" or type(io_api.popen) ~= "function"
      or type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
    return nil, "fallback"
  end
  local executable = is_macos and "/usr/bin/shasum" or "/usr/bin/sha256sum"
  local arguments = is_macos and " -a 256 -- " or " -- "
  local quoted = "'" .. path:gsub("'", "'\"'\"'") .. "'"
  local command = executable .. arguments .. quoted .. " 2>/dev/null"
  local ok_open, pipe = pcall(io_api.popen, command, "r")
  if not ok_open or not pipe then return nil, "fallback" end
  local ok_read, output = pcall(function() return pipe:read("*a") end)
  local ok_close, closed = pcall(function() return pipe:close() end)
  if not ok_read or type(output) ~= "string" or not ok_close
      or closed == nil or closed == false then
    return nil, "fallback"
  end
  local digest = output:match("^([0-9A-Fa-f]+)%s")
  if type(digest) ~= "string" or #digest ~= 64 then return nil, "fallback" end
  digest = digest:lower()
  if digest:match("^[0-9a-f]+$") == nil then return nil, "fallback" end
  return digest, "present"
end

function Host.hash_file_engine(reaper_api, path)
  if type(path) ~= "string" or path == "" or path:find("\0", 1, true)
      or not api_exists(reaper_api, "MBH_SHA256File") then
    return nil, "fallback"
  end
  local ok, result_ok, digest = pcall(reaper_api.MBH_SHA256File, path)
  if not ok or result_ok ~= true or type(digest) ~= "string"
      or #digest ~= 64 then
    return nil, "fallback"
  end
  digest = digest:lower()
  if digest:match("^[0-9a-f]+$") == nil then return nil, "fallback" end
  return digest, "present"
end

function Host.detect_platform(reaper_api)
  if type(reaper_api) ~= "table"
      or type(reaper_api.GetOS) ~= "function"
      or type(reaper_api.GetAppVersion) ~= "function" then
    return nil
  end
  local ok_os, os_name = pcall(reaper_api.GetOS)
  local ok_app, app_version = pcall(reaper_api.GetAppVersion)
  if not ok_os or not ok_app then return nil end
  os_name = tostring(os_name or "")
  local arch = tostring(app_version or ""):match("/([^/]+)$") or ""
  arch = arch:lower()

  -- REAPER's Windows ARM build reports `Win-arm64` from GetOS, not `Win64`.
  -- Measured on the Surface Pro X on 2026-09-07 with the 7.79
  -- win11_arm64ec_beta build, which reports GetOS `Win-arm64` and app version
  -- `7.79/win11-arm64ec-beta`. Both names are recognized here: the OS name says
  -- this is Windows, and the pair below says which Windows artifact it takes.
  if os_name == "Win64" or os_name == "Win-arm64" then
    -- The OS name alone is enough to call the host ARM, so an app version this
    -- code cannot read cannot send a Windows ARM REAPER down the x64 path.
    -- `arm64ec` contains `arm64`, so one test covers the hybrid image REAPER
    -- actually is and the classic spelling. Both take the `win-arm64` key,
    -- because that key carries the ARM64EC artifact, and one flag gates them.
    if os_name == "Win-arm64"
        or arch:find("arm64", 1, true) or arch:find("aarch64", 1, true) then
      if not WINDOWS_ARM64_ENGINE_RUNTIME_QUALIFIED then return nil end
      return "win-arm64"
    end
    if arch:find("i386", 1, true) or arch:find("i686", 1, true)
        or (arch:find("x86", 1, true)
          and not arch:find("x86_64", 1, true)) then
      return nil
    end
    return "win-x64"
  end
  if os_name == "macOS-arm64" then return "mac-arm64" end
  if os_name == "OSX64" then
    if not MAC_X64_ENGINE_RUNTIME_QUALIFIED then return nil end
    return "mac-x64"
  end
  if os_name == "Other" then
    if arch:find("aarch64", 1, true) or arch:find("arm64", 1, true) then
      if not LINUX_ARM64_ENGINE_RUNTIME_QUALIFIED then return nil end
      return "linux-arm64"
    end
    if arch:find("armv", 1, true) or arch:find("i386", 1, true)
        or arch:find("i686", 1, true) then
      return nil
    end
    return "linux-x64"
  end
  return nil
end

function Host.session_id(reaper_api, instance_id, time_value, random_value)
  if type(reaper_api) ~= "table"
      or type(reaper_api.GetExtState) ~= "function"
      or type(reaper_api.SetExtState) ~= "function" then
    return nil, "extstate-unavailable"
  end
  local ok_read, existing = pcall(
    reaper_api.GetExtState, Host.EXT_NAMESPACE, Host.SESSION_KEY)
  if not ok_read then return nil, "extstate-read" end
  if valid_session_id(existing) then return existing end

  local seed = tostring(instance_id or "instance") .. "_"
    .. tostring(time_value or 0) .. "_" .. tostring(random_value or 0)
  seed = seed:gsub("[^A-Za-z0-9_%-]", "_")
  local chosen = "session_" .. seed
  if not valid_session_id(chosen) then return nil, "session-id-invalid" end
  local ok_write = pcall(reaper_api.SetExtState,
    Host.EXT_NAMESPACE, Host.SESSION_KEY, chosen, false)
  if not ok_write then return nil, "extstate-write" end
  local ok_verify, verified = pcall(
    reaper_api.GetExtState, Host.EXT_NAMESPACE, Host.SESSION_KEY)
  if not ok_verify or verified ~= chosen then return nil, "extstate-readback" end
  return chosen
end

-- P-08 / L-15. The local file that admits a Windows acceptance descriptor on
-- this install. It is never listed in any manifest, never written by the
-- installer, and its content is never read: an operator running an unsigned
-- acceptance build places it by hand beside the installer's other state, and
-- every install without it reads an acceptance descriptor as an invalid
-- package. `Dev/Engine/release/WINDOWS_ACCEPTANCE_SAFETY.md` states the rule.
Host.ACCEPTANCE_TOKEN_NAME = "acceptance-allowed"

-- The proof is an open that succeeded, not a presence probe: `path_present`
-- answers "present" for any path it could not classify, so a state root this
-- process cannot read would admit the marker. The file's content is not read.
-- Enough of an artifact to read its header. A PE file's COFF header sits
-- behind a pointer at offset 0x3C, and every Engine build this repository
-- produces puts it, its optional header and its whole section table inside the
-- first few hundred bytes; Mach-O and ELF declare theirs in the first twenty.
-- This is generous against all three.
--
-- IT IS NOT THE WHOLE READ FOR A PE. Separating an ARM64EC image from a plain
-- x64 one needs the CHPE pointer in the load configuration, which sits about
-- 1.7 MB into a real Engine DLL, so the classifier is handed a way to seek
-- rather than a longer prefix. The header prefix is what locates it: the
-- section table is here, and the core walks it.
Host.MACHINE_HEADER_BYTES = 65536

function Host.acceptance_allowed(io_api, resource_root)
  if type(io_api) ~= "table" or type(io_api.open) ~= "function"
      or type(resource_root) ~= "string" then
    return false
  end
  local ok, file = pcall(io_api.open, join(
    join(resource_root, "Data/mbriggs_helper"), Host.ACCEPTANCE_TOKEN_NAME),
    "rb")
  if not ok or not file then return false end
  pcall(function() file:close() end)
  return true
end

-- Returns the target, the package state, the reason it is not ready, and what
-- the descriptor promises about the Engine inside the artifact. The last of
-- these is the probe's business and never the target's: the decision core
-- refuses a target carrying any key it does not validate, so the promises
-- travel beside the target rather than inside it.
--
-- `expected_contract` is required of the package module rather than used when
-- present. Treating it as optional would let a host paired with an older
-- module drop the contract cross-check without saying so, and a check that
-- can disappear quietly is not a check.
function Host.load_package(io_api, json, path_present, descriptor_path,
                           platform, package_module, core, options)
  if type(io_api) ~= "table" or type(io_api.open) ~= "function"
      or type(json) ~= "table" or type(json.decode) ~= "function"
      or type(path_present) ~= "function" or type(descriptor_path) ~= "string"
      or type(package_module) ~= "table"
      or type(package_module.target_for) ~= "function"
      or type(package_module.expected_contract) ~= "function"
      or type(package_module.payload_suffix) ~= "function"
      or type(core) ~= "table"
      or type(core.bundle_directory) ~= "function"
      or type(core.machine_matches) ~= "function" then
    return nil, "invalid", "package-dependency"
  end
  if type(platform) ~= "string" or platform == "" then
    return nil, "unsupported", "package-platform"
  end

  local value
  if type(options) == "table" and (options.require_descriptor == true or options.descriptor ~= nil) then
    if type(options.descriptor) ~= "table" then return nil, "invalid", "package-metadata" end
    value = options.descriptor
  else
  local ok_open, file = pcall(io_api.open, descriptor_path, "rb")
  if not ok_open or not file then
    local ok_present, present = pcall(path_present, descriptor_path)
    if ok_present and present == false then return nil, "absent" end
    return nil, "invalid", "package-unreadable"
  end
  local ok_read, raw = pcall(function() return file:read("*a") end)
  pcall(function() file:close() end)
  if not ok_read or type(raw) ~= "string" or raw == "" then
    return nil, "invalid", "package-unreadable"
  end
  local ok_decode, decoded, decode_why = pcall(json.decode, raw)
  value = decoded
  if not ok_decode or value == nil then
    return nil, "invalid", "package-decode:" .. tostring(decode_why or value)
  end
  end
  local target, target_why = package_module.target_for(value, platform, core,
    options)
  if not target then return nil, "invalid", target_why end

  -- Host-only validation, the part a digest cannot do. The descriptor was
  -- validated in full above: every target's signature policy, filename and
  -- hash, exactly as a release validation does. Only local presence is
  -- relaxed, to the one target this host takes. That target's file, when it
  -- is here, has to be a file this machine could load, so its own header is
  -- read and compared with the target. Other targets' files are not opened:
  -- they are not required, they are not fetched, and they are never deleted
  -- for belonging to another machine.
  --
  -- An absent artifact is not a refusal here. It is an incomplete payload,
  -- which the installer reports when it goes to stage it, and which the
  -- updater answers by fetching the one file this host is missing.
  -- Required of the caller, never inferred. A host that supplied no artifact
  -- root would skip this check without saying so, and a check that can
  -- disappear quietly is not a check.
  local artifact_root = type(options) == "table" and options.artifact_root or nil
  if type(artifact_root) ~= "string" or artifact_root == "" then
    return nil, "invalid", "package-artifact-root"
  end
  local directory = core.bundle_directory(platform)
  if not directory then return nil, "invalid", "package-bundle-directory" end
  local bundle_suffix = package_module.payload_suffix(value)
  if bundle_suffix ~= "" and bundle_suffix ~= ".txt" then
    return nil, "invalid", "package-payload-layout"
  end
  local artifact_path = join(join(artifact_root, directory),
    target.filename .. bundle_suffix)
  if options.cache_only then artifact_path = join(artifact_root, target.filename .. bundle_suffix) end
  local ok_artifact, artifact_file = pcall(io_api.open, artifact_path, "rb")
  if ok_artifact and artifact_file then
    local ok_head, head = pcall(function()
      return artifact_file:read(Host.MACHINE_HEADER_BYTES)
    end)
    -- The handle stays open across the classification. A PE needs one more
    -- read, at an offset the core works out from the section table in the
    -- prefix, and lending the handle keeps the whole Windows rule in the core
    -- rather than half of it here. The core reads nothing else through this:
    -- it asks for one field, at one offset, and a read that does not answer
    -- with the bytes asked for refuses the artifact.
    local function read_at(offset, count)
      if artifact_file:seek("set", offset) ~= offset then return nil end
      return artifact_file:read(count)
    end
    -- Called through `pcall` so the handle is closed on every path. Before
    -- the classifier was given a reader, the close happened first and nothing
    -- it did could hold the file; now it runs with the handle open, and a
    -- raise here would leak it. A leaked handle on Windows is not a lost
    -- resource, it is a rename the installer cannot perform later.
    local machine_ok, machine_why
    if ok_head and type(head) == "string" then
      local ran, matched, why = pcall(core.machine_matches, platform, head,
        read_at)
      if ran then
        machine_ok, machine_why = matched, why
      else
        machine_ok, machine_why = false, "unreadable"
      end
    end
    pcall(function() artifact_file:close() end)
    if (not ok_head or type(head) ~= "string") and not options.cache_only then
      return nil, "invalid", "package-artifact-unreadable"
    end
    if not machine_ok and not options.cache_only then
      return nil, "invalid", "package-machine:" .. tostring(machine_why)
    end
  end

  return target, "ready", nil, package_module.expected_contract(value),
    bundle_suffix
end

local function decode_contract(json, raw, version, abi, expected_contract,
                               required_subsystems, required_exports,
                               required_status_vocabulary)
  if type(json) ~= "table" or type(json.decode) ~= "function"
      or type(raw) ~= "string" or raw == ""
      or #raw > Host.CONTRACT_BUFFER_BYTES then
    return nil, "contract-dependency"
  end
  local ok, value = pcall(json.decode, raw)
  if not ok then
    return nil, "contract-schema"
  end
  required_subsystems = required_subsystems or Host.REQUIRED_SUBSYSTEMS
  required_exports = required_exports or Host.REQUIRED_EXPORTS
  required_status_vocabulary = required_status_vocabulary
    or Host.REQUIRED_STATUS_VOCABULARY
  local validated, reason, detail = EngineContract.validate(value, raw, {
    required_abi = Host.REQUIRED_ABI,
    bootstrap_version = version,
    bootstrap_abi = abi,
    required_subsystems = required_subsystems,
    required_exports = required_exports,
    forbidden_exports = Host.FORBIDDEN_PRODUCTION_EXPORTS,
    required_status_vocabulary = required_status_vocabulary,
    required_error_vocabulary = Host.REQUIRED_ERROR_VOCABULARY,
    profile_protocols = INFERENCE_PROFILE_PROTOCOLS,
    profile_required_revision = 2,
    contract_buffer_bytes = Host.CONTRACT_BUFFER_BYTES,
    max_result_buffer_bytes = Host.MAX_RESULT_BUFFER_BYTES,
  })
  if not validated then
    local suffix = detail and ":" .. tostring(detail) or ""
    return nil, "contract-" .. tostring(reason):gsub("_", "-") .. suffix
  end
  local protocols = validated.protocols
  local inference_profiles = validated.profiles
  if type(expected_contract) == "table" then
    if expected_contract.core_abi ~= value.core_abi then
      return nil, "package-contract-ABI"
    end
    if expected_contract.build_channel ~= value.build_channel then
      return nil, "package-contract-build-channel"
    end
    if type(expected_contract.subsystems) ~= "table" then
      return nil, "package-contract-subsystems"
    end
    for name, required in pairs(expected_contract.subsystems) do
      if not positive_integer(required, 1, 1000)
          or not positive_integer(value.subsystems[name], required, 1000) then
        return nil, "package-contract-subsystem:" .. tostring(name)
      end
    end
    local package_protocols = strict_token_set(expected_contract.protocols)
    if not package_protocols then return nil, "package-contract-protocols" end
    for name in pairs(package_protocols) do
      if protocols[name] ~= true then
        return nil, "package-contract-protocol:" .. name
      end
    end
    local package_profiles = strict_token_set(
      expected_contract.inference_profiles)
    if not package_profiles then
      return nil, "package-contract-inference-profiles"
    end
    for name in pairs(package_profiles) do
      if inference_profiles[name] ~= true then
        return nil, "package-contract-inference-profile:" .. name
      end
      local bound_protocol = INFERENCE_PROFILE_PROTOCOLS[name]
      if bound_protocol and package_protocols[bound_protocol] ~= true then
        return nil, "package-contract-inference-profile-protocol:" .. name
      end
    end
  end
  return value
end

local function temporary_client_self_test(reaper_api, json, contract)
  local size = contract.limits.client_result_buffer_bytes
  local buffer = string.rep(" ", size)
  local opened_raw = call_pair_string_with_buffer(
    reaper_api.MBH_ClientOpenV1, buffer)
  if not opened_raw then return false, "client-open-call" end
  local ok_open, opened = pcall(json.decode, opened_raw)
  if not ok_open or type(opened) ~= "table" then
    return false, "client-open-decode"
  end
  local capability = opened.client_capability
  local close_raw = nil
  if type(capability) == "string" and capability ~= "" then
    close_raw = call_pair_string_with_buffer(reaper_api.MBH_ClientCloseV1,
      capability, buffer)
  end
  local expected_length = contract.limits.capability_bytes * 2
  if opened.ok ~= true or type(capability) ~= "string"
      or #capability ~= expected_length
      or capability:match("^[0-9a-f]+$") == nil then
    return false, "client-open-result"
  end
  if not close_raw then return false, "client-close-call" end
  local ok_close, closed = pcall(json.decode, close_raw)
  if not ok_close or type(closed) ~= "table" or closed.ok ~= true then
    return false, "client-close-result"
  end
  return true
end

-- The Engine hashes its own module file at load, before any script runs, and
-- reports that digest as the contract's `loaded_file_sha256`. It is the only
-- field that says which binary this process is actually running: a version
-- string cannot separate two builds that share one version, which is exactly
-- the same-version replace. Engines at 1.0.2 and earlier omit it, so a nil
-- answer is no evidence at all: the probe then neither certifies nor fails the
-- artifact the lane placed, and waits for a process that can say what it holds.
local function contract_file_digest(json, raw)
  if type(json) ~= "table" or type(json.decode) ~= "function"
      or type(raw) ~= "string" or raw == ""
      or #raw > Host.CONTRACT_BUFFER_BYTES then
    return nil
  end
  local ok, value = pcall(json.decode, raw)
  if not ok or type(value) ~= "table" then return nil end
  local digest = value.loaded_file_sha256
  if type(digest) ~= "string" or #digest ~= 64
      or digest:match("^[0-9a-f]+$") == nil then
    return nil
  end
  return digest
end

local function read_contract_raw(reaper_api)
  if type(reaper_api) ~= "table" then return nil end
  return call_pair_string_with_buffer(reaper_api.MBH_GetContractV1,
    string.rep(" ", Host.CONTRACT_BUFFER_BYTES))
end

function Host.probe_engine(reaper_api, lane, journal, paths, json,
                           expected_contract)
  if type(journal) ~= "table" then return "malformed", "journal" end
  if lane ~= "activation" and lane ~= "rollback" then
    return "malformed", "lane"
  end

  local expected_kind = lane == "activation" and "target"
    or journal.previous_kind == "engine" and "previous" or "absent"
  if expected_kind == "absent" then
    if type(reaper_api) ~= "table"
      or type(reaper_api.APIExists) ~= "function" then
      return "unavailable", "APIExists"
    end
    local ok, present = pcall(reaper_api.APIExists, "MBH_GetVersion")
    if not ok then return "unavailable", "APIExists-threw" end
    if present == false then return "absent-ok" end
    -- This lane undoes a fresh install, so it has no previous artifact and no
    -- digest read here can be one. A process that loaded the target before the
    -- removal reports a registered Engine for a rollback that completed, and
    -- the file classes already prove the removal, so nothing observed here is
    -- evidence of a failure and the lane waits for a restart instead.
    local digest = contract_file_digest(json, read_contract_raw(reaper_api))
    return "not-loaded",
      digest and ("file-sha256:" .. digest) or "engine-registered"
  end

  -- A process that never loaded the binary this lane is about can report
  -- nothing about it. Answering "failed" there rolls back and quarantines a
  -- good release whenever a second REAPER instance still holds the previous
  -- Engine, so that case gets its own result and waits for a restart instead.
  local has_version = api_exists(reaper_api, "MBH_GetVersion")
  local loaded_version = has_version
    and call_pair_string(reaper_api.MBH_GetVersion) or nil
  if loaded_version == nil then
    -- No Engine at all, or one whose version cannot be read. Neither says
    -- anything about the placed binary, in either lane: a REAPER process that
    -- started before the previous Engine was installed reports exactly this
    -- for a good update, just as one that predates a fresh placement does.
    local detail = has_version and "version-unreadable" or "no-engine-registered"
    if expected_kind == "target" and not has_version then
      return "not-registered", detail
    end
    return "not-loaded", detail
  end

  -- `loaded_file_sha256` is the only field that says which binary this process
  -- loaded. Every check below reports on that binary, so a failure may be
  -- attributed to this lane's artifact only while the digest proves the two are
  -- one file. A version string cannot prove it: two builds can carry one
  -- version, and a process older than both this transaction and the one before
  -- it reports a version that matches neither while having loaded neither. An
  -- absent field, a malformed one, and a different digest are therefore all
  -- "not-loaded", so no number of stale sessions can spend the failures a
  -- rollback needs. An Engine that does not report the field is never certified
  -- and never rolled back by this probe; the user's own repair still acts.
  local contract_raw = read_contract_raw(reaper_api)
  local loaded_digest = contract_file_digest(json, contract_raw)
  local expected_digest = expected_kind == "target"
    and journal.target_sha256 or journal.previous_sha256
  if loaded_digest == nil then
    return "not-loaded", "no-file-sha256:" .. loaded_version
  end
  if loaded_digest ~= expected_digest then
    return "not-loaded", "file-sha256:" .. loaded_digest
  end

  local required_exports = expected_kind == "target"
    and Host.ACTIVATION_REQUIRED_EXPORTS or Host.REQUIRED_EXPORTS
  local required_subsystems = expected_kind == "target"
    and Host.ACTIVATION_REQUIRED_SUBSYSTEMS or Host.REQUIRED_SUBSYSTEMS
  local required_status_vocabulary = expected_kind == "target"
    and Host.ACTIVATION_REQUIRED_STATUS_VOCABULARY
    or Host.REQUIRED_STATUS_VOCABULARY

  for _, name in ipairs(required_exports) do
    if not api_exists(reaper_api, name) then
      return "failed", "missing-export:" .. name
    end
  end
  for _, name in ipairs(Host.FORBIDDEN_PRODUCTION_EXPORTS) do
    if api_exists(reaper_api, name) then
      return "failed", "development-export:" .. name
    end
  end

  -- The digest above proved this process loaded the lane's own artifact, so a
  -- version that disagrees with the journal is a defect in that artifact.
  local version = loaded_version
  local expected_version = expected_kind == "target"
    and journal.target_version or journal.previous_version
  if version ~= expected_version then
    return "failed", "version:" .. tostring(version)
  end

  local ok_abi, abi = pcall(reaper_api.MBH_GetABI)
  if not ok_abi or abi ~= Host.REQUIRED_ABI then
    return "failed", "ABI:" .. tostring(abi)
  end

  local contract, contract_why = decode_contract(
    json, contract_raw, version, abi,
    expected_kind == "target" and expected_contract or nil,
    required_subsystems, required_exports, required_status_vocabulary)
  if not contract then
    return "failed", tostring(contract_why or "contract")
  end

  local build = call_pair_string(reaper_api.MBH_GetBuildInfo)
  if not build or not build:find('"tls":"', 1, true)
      or build:find('"tls":"none"', 1, true) then
    return "failed", "TLS-build-info"
  end

  local ok_hash, hash_ok, digest = pcall(
    reaper_api.MBH_SHA256String, Host.SELF_TEST_TEXT)
  if not ok_hash or hash_ok ~= true or digest ~= Host.SELF_TEST_SHA256 then
    return "failed", "SHA256String:" .. tostring(digest)
  end

  local client_ok, client_why = temporary_client_self_test(
    reaper_api, json, contract)
  if not client_ok then
    return "failed", "client-self-test:" .. tostring(client_why)
  end

  local ok_mouse, mouse = pcall(reaper_api.MBH_Mouse_GetState, 0)
  local ok_null, null_is_window = pcall(
    reaper_api.MBH_Window_IsWindow, nil)
  if not ok_mouse or mouse ~= 0 or not ok_null or null_is_window ~= false then
    return "failed", "Phase1.5-basic"
  end

  local live_path = type(paths) == "table" and paths.live or nil
  if type(live_path) ~= "string" or live_path == "" then
    return "malformed", "live-path"
  end
  local ok_stat, stat_result, stat_size, accessed, modified, changed = pcall(
    reaper_api.MBH_File_Stat, live_path)
  if not ok_stat or stat_result ~= 0 or type(stat_size) ~= "number"
      or stat_size <= 0 or type(accessed) ~= "string" or #accessed ~= 19
      or type(modified) ~= "string" or #modified ~= 19
      or type(changed) ~= "string" or #changed ~= 19 then
    return "failed", "File_Stat:" .. table.concat({
      tostring(stat_result), tostring(stat_size), tostring(accessed),
      tostring(modified), tostring(changed),
    }, ",")
  end

  return expected_kind == "target" and "target-ok" or "previous-ok"
end

-- The most entries a directory listing may hold before this host stops
-- claiming to have read all of it.
Host.MAX_DIRECTORY_ENTRIES = 4096

-- The names in one directory, or nil when this host cannot answer for the whole
-- of it. The refresh is part of the listing rather than a courtesy before it,
-- because EnumerateFiles caches a directory after the first walk and hands that
-- same listing back on every later index 0: a refresh that raised leaves the
-- cached names standing, and the walk would then answer with a listing of some
-- earlier moment. A refresh that raises, a walk that raises, and a walk that has
-- not ended inside the bound are all refused rather than answered: the installer
-- lock reads this to prove a name is absent, and a stale or partial listing
-- proves nothing.
function Host.enumerate_files(reaper_api, directory)
  if type(reaper_api) ~= "table"
      or type(reaper_api.EnumerateFiles) ~= "function"
      or type(directory) ~= "string" then
    return nil
  end
  local walked = directory:gsub("[\\/]+$", "")
  if not pcall(reaper_api.EnumerateFiles, walked, -1) then return nil end
  local out = {}
  for index = 0, Host.MAX_DIRECTORY_ENTRIES do
    local ok, name = pcall(reaper_api.EnumerateFiles, walked, index)
    if not ok then return nil end
    if type(name) ~= "string" then return out end
    out[#out + 1] = name
  end
  return nil
end

function Host.new(options)
  assert(type(options) == "table", "Engine installer host options required")
  assert(type(options.runtime_factory) == "function", "runtime factory required")
  assert(type(options.path_present) == "function", "path_present required")
  assert(type(options.resource_root) == "string", "resource root required")

  local self = {
    runtime_factory = options.runtime_factory,
    runtime_options = options.runtime_options,
    path_present = options.path_present,
    log = options.log or function() end,
    state_root = join(options.resource_root, "Data/mbriggs_helper"),
    runtime = nil,
    state = {kind = "idle", detail = "unchecked"},
    package_target = options.package_target,
    package_state = options.package_state or "absent",
    package_reason = options.package_reason,
    installed_hash = options.installed_hash,
    hash_cache = options.hash_cache,
    installed_hash_checked = false,
    installed_hash_value = nil,
    installed_hash_state = nil,
    paused = false,
    logged_state = nil,
    -- The session transition runs once: opening the removal transition and
    -- resuming a parked activation are both answers a restart changes, and a
    -- session is a restart.
    session_checked = false,
    -- What the record said when it was last read, and nothing more. The record
    -- is shared, so another app can merge a withdrawal into it at any moment of
    -- this session; every action that reads it updates this, `withdrawn()`
    -- reads it again on demand, and no reading here is kept for the session.
    withdrawn_state = "unchecked",
    withdrawn_detail = nil,
  }

  function self:_present(path)
    local ok, value = pcall(self.path_present, path)
    return not ok or value == true
  end

  function self:_clear_hash_cache()
    if self.hash_cache == nil then return true end
    return Host.clear_hash_cache(self.hash_cache)
  end

  function self:_clear_hash_cache_unless_progress()
    local kind = type(self.state) == "table" and self.state.kind or nil
    if HASH_CACHE_PROGRESS_STATES[kind] == true then return true end
    return self:_clear_hash_cache()
  end

  function self:_set_state(value)
    self.state = type(value) == "table" and value
      or {kind = "refuse", detail = "invalid-runtime-result"}
    local signature = tostring(self.state.kind) .. ":" .. tostring(self.state.detail)
    if signature ~= self.logged_state then
      self.logged_state = signature
      self.log("ENGINE-INSTALL", signature)
    end
    return self.state
  end

  function self:_runtime()
    if self.runtime then return self.runtime end
    local ok, value = pcall(self.runtime_factory, self.runtime_options)
    if not ok or type(value) ~= "table" or type(value.step) ~= "function" then
      return nil, ok and "runtime-invalid" or ("runtime-load:" .. tostring(value))
    end
    self.runtime = value
    return value
  end

  function self:_loaded_version()
    local options = self.runtime_options
    local loader = type(options) == "table" and options.loaded_version or nil
    if type(loader) ~= "function" then return nil end
    local ok, value = pcall(loader)
    if not ok or type(value) ~= "string" or value == "" then return nil end
    return value
  end

  function self:_installed_hash()
    if self.installed_hash_checked then
      return self.installed_hash_value, self.installed_hash_state
    end
    self.installed_hash_checked = true
    if type(self.installed_hash) ~= "function" then
      self.installed_hash_state = "unavailable"
      return nil, self.installed_hash_state
    end
    local ok, value, state = pcall(self.installed_hash)
    local cache_cleared = self:_clear_hash_cache()
    if not cache_cleared then
      self.installed_hash_state = "unreadable"
      return nil, self.installed_hash_state
    end
    if ok and type(value) == "string" and #value == 64
        and value:match("^[0-9a-f]+$") ~= nil then
      self.installed_hash_value = value
      self.installed_hash_state = "present"
    else
      self.installed_hash_state = ok and tostring(state or "unreadable")
        or "unreadable"
    end
    return self.installed_hash_value, self.installed_hash_state
  end

  -- A read-only view for both host interfaces. The durable runtime remains
  -- the authority for admission because it also checks the live binary hash,
  -- quarantine record, transaction journal, and installer lock. This view only
  -- decides whether a package-backed action should be shown and how the current
  -- durable state should be described.
  --
  -- The withdrawal state it shows is the last reading any action or `withdrawn`
  -- call took, never a session-long one. It takes no reading of its own: this
  -- runs on the paint path, and the record lives behind the installer lock.
  function self:presentation()
    local state = type(self.state) == "table" and self.state
      or {kind = "refuse", detail = "invalid-host-state"}
    local kind = tostring(state.kind or "refuse")
    local target_version = type(self.package_target) == "table"
      and self.package_target.version or nil
    local out = {
      visible = self.package_state == "ready" or kind ~= "idle",
      kind = kind,
      detail = state.detail,
      package_state = self.package_state,
      package_reason = self.package_reason,
      target_version = target_version,
      installed_version = self:_loaded_version(),
      action = "none",
      can_stage = false,
      can_replace = false,
      can_repair = false,
      can_clear_quarantine = false,
      can_discharge_recovery = false,
      withdrawn_state = self.withdrawn_state,
      withdrawn_detail = self.withdrawn_detail,
    }

    -- A record this body cannot read is not an empty one. Until a
    -- user-confirmed repair rewrites it, the Engine is neither used nor
    -- installed, and the only control offered is that repair.
    if self.withdrawn_state == "unusable" then
      out.action = "withdrawal-record-unusable"
      out.can_repair_withdrawn = true
      return out
    end

    if kind == "staged" or kind == "resume" or kind == "advanced"
        or kind == "resumed" then
      out.action = "installing"
      return out
    end
    -- The digest is out of the load path, but the image REAPER already loaded
    -- is still the one it loaded. This is the only state that may say
    -- "removed at next restart"; the pending one below says the opposite.
    if kind == "withdrawal-removed" then
      out.action = "withdrawn-removed"
      return out
    end
    if kind == "withdrawal-superseded" or kind == "withdrawal-absent" then
      out.action = "withdrawn-gone"
      return out
    end
    -- No automatic replacement, and the user has to be told what would be
    -- replaced before there can be one.
    if kind == "repair-required" then
      out.action = "confirm-repair"
      out.can_confirm_repair = self.package_state == "ready"
        and type(self.package_target) == "table"
      -- The identity is unknown because the installer's record does not name
      -- what is in the load path, which is the repair's work rather than the
      -- confirmation's. Offered beside it: the repair rewrites no binary, and
      -- when the file in the load path is the one this app would install, the
      -- confirmation cannot finish and the repair is the only way out.
      out.can_repair = type(state.detail) == "string"
        and state.detail:sub(1, #IDENTITY_RECORD_PREFIX)
          == IDENTITY_RECORD_PREFIX
      return out
    end
    -- The installed Engine is healthy and this app is not the one to change
    -- it: newer, incompatible with this app, or already what the bundle holds.
    if kind == "no-action" then
      out.action = "no-action"
      return out
    end
    if kind == "refuse" then
      out.action = kind
      out.can_repair = repairable(state.detail)
        or status_repairable(state.detail)
      out.can_clear_quarantine = state.detail == "target-quarantined"
      -- A removal that could not take the file. The digest is present and
      -- unused, which is the opposite of "removed at next restart", and the
      -- control retries the removal rather than repairing anything.
      if type(state.detail) == "string"
          and state.detail:sub(1, 18) == "withdrawal-remove:" then
        out.action = "withdrawn-present"
        out.can_repair = true
      end
      return out
    end
    -- The target reached the live slot and no Engine is registered in this
    -- REAPER session. Nothing proves it will not load after a restart, so the
    -- installer waits; undoing it is the user's decision and repair takes it.
    if kind == "restart-required" and state.detail == "not-registered" then
      out.action = "not-active"
      out.can_repair = true
      return out
    end
    if kind == "restart-required"
        or kind == "active" or kind == "rolled-back"
        or kind == "already-current" then
      out.action = kind
      return out
    end
    -- Recovery could not put an Engine back. Both remedies stay offered: run
    -- recovery again, or install the package build outright.
    if kind == "recovery-required" then
      out.action = kind
      out.can_repair = true
      out.can_stage = self.package_state == "ready"
        and type(self.package_target) == "table"
      -- An obligation nothing can meet reports the same state at every later
      -- launch, and while it stands no transaction may be abandoned and no
      -- bundle installed behind the journal that abandonment would remove. The
      -- third control ends it, and is offered only for that reading.
      out.can_discharge_recovery = recovery_unmeetable(
        type(self.runtime_options) == "table" and self.runtime_options.core
          or nil,
        state.detail)
      return out
    end
    if self.package_state ~= "ready"
        or type(self.package_target) ~= "table" then
      out.action = "unavailable"
      return out
    end

    if not out.installed_version then
      out.action = "install"
      out.can_stage = true
      return out
    end
    local core = type(self.runtime_options) == "table"
      and self.runtime_options.core or nil
    if type(core) ~= "table" or type(core.compare_versions) ~= "function" then
      out.action = "unavailable"
      return out
    end
    local comparison = core.compare_versions(
      tostring(target_version or ""), out.installed_version)
    if comparison == nil then
      out.action = "unavailable"
    elseif comparison > 0 then
      out.action = "update"
      out.can_stage = true
    elseif comparison < 0 then
      out.action = "newer"
    else
      local installed_hash, hash_state = self:_installed_hash()
      out.installed_sha256 = installed_hash
      out.installed_hash_state = hash_state
      if installed_hash == self.package_target.sha256 then
        out.action = "current"
      elseif hash_state == "present" then
        -- One version string, two different binaries. The package build can
        -- replace the installed one through the ordinary transaction, but only
        -- when the user asks for that explicitly.
        out.action = "conflict"
        out.can_replace = true
      else
        out.action = "unavailable"
      end
    end
    return out
  end

  -- Run once, before anything else asks the installer for work: it reads the
  -- withdrawal record, opens the removal transition when the digest in this
  -- host's load path has been withdrawn, and otherwise resumes an activation
  -- this target parked for a process that could load it.
  function self:session_start()
    if self.session_checked then return self.state end
    self.session_checked = true
    local state = self:_durable_action("session_start")
    if state.kind == "refuse" then self.paused = true end
    return state
  end

  function self:tick()
    if not self.session_checked then
      local started = self:session_start()
      if started.kind == "refuse" then return started end
    end
    if self.paused then
      self:_clear_hash_cache()
      return self.state
    end
    local journal = join(self.state_root, "install_journal.json")
    local sentinel = join(self.state_root, "first_load.json")
    local recovery = join(self.state_root, "recovery.json")
    -- A recovery record outlives the journal, so the durable runtime has to be
    -- asked even when no transaction record is left to describe it.
    local has_record = self:_present(journal) or self:_present(journal .. ".tmp")
      or self:_present(recovery) or self:_present(recovery .. ".tmp")
    if not has_record then
      if self:_present(sentinel) or self:_present(sentinel .. ".tmp") then
        self.paused = true
        self:_clear_hash_cache()
        return self:_set_state({kind = "refuse", detail = "sentinel-orphaned"})
      end
      self:_clear_hash_cache()
      self.state = {kind = "idle", detail = "no-transaction"}
      return self.state
    end

    self:_durable_action("step")
    if self.state.kind == "refuse" or self.state.kind == "restart-required"
        or self.state.kind == "active" or self.state.kind == "rolled-back"
        or self.state.kind == "recovery-required" then
      self.paused = true
    end
    return self.state
  end

  -- What one durable result says about the shared record, taken from every
  -- action rather than from the session start alone. A refusal that names an
  -- unusable record is evidence from whichever action produced it; a success
  -- says the record was readable only for the actions whose runtime body reads
  -- it before doing anything else.
  function self:_note_withdrawn(name, state)
    local detail = type(state) == "table" and tostring(state.detail or "") or ""
    if state.kind == "refuse"
        and detail:sub(1, #WITHDRAWAL_UNUSABLE_PREFIX)
          == WITHDRAWAL_UNUSABLE_PREFIX then
      self.withdrawn_state = "unusable"
      self.withdrawn_detail =
        detail:sub(#WITHDRAWAL_UNUSABLE_PREFIX + 1):gsub("^:", "")
      return
    end
    if state.kind ~= "refuse" and WITHDRAWAL_READING_ACTIONS[name] then
      self.withdrawn_state = "clear"
      self.withdrawn_detail = nil
    end
  end

  function self:_durable_action(name, ...)
    local runtime, runtime_why = self:_runtime()
    if not runtime or type(runtime[name]) ~= "function" then
      self.paused = true
      self:_clear_hash_cache()
      return self:_set_state({
        kind = "refuse",
        detail = runtime and ("runtime-" .. name .. "-missing") or runtime_why,
      })
    end
    local ok, value, why = pcall(runtime[name], runtime, ...)
    if not ok then
      value = {kind = "refuse", detail = "runtime-error:" .. tostring(value)}
    elseif value == nil then
      value = {kind = "refuse", detail = tostring(why or "runtime-empty")}
    end
    self:_set_state(value)
    self:_note_withdrawn(name, self.state)
    if not self:_clear_hash_cache_unless_progress() then
      self:_set_state({kind = "refuse", detail = "hash-cache-clear-failed"})
    end
    return self.state
  end

  -- Both recovery actions are user decisions, so a paused controller resumes
  -- only when the action succeeded and the durable state actually changed.
  -- The bundle target goes with the call: it is the only proof the status
  -- rebuild has of what is in the load path, and a descriptor this host
  -- refused proves nothing, so only a ready package is passed.
  function self:repair()
    local target = self.package_state == "ready"
      and type(self.package_target) == "table" and self.package_target or nil
    local state = self:_durable_action("repair", {target = target})
    self.paused = state.kind ~= "repaired" and state.kind ~= "idle"
    return state
  end

  -- The user's discharge of an obligation nothing can meet. It is a decision
  -- like the quarantine clear, so a paused controller resumes only when the
  -- durable state actually changed, and the next tick is then free to abandon
  -- the transaction the obligation was holding.
  function self:discharge_recovery()
    local state = self:_durable_action("discharge_recovery")
    self.paused = state.kind ~= "recovery-discharged"
    return state
  end

  -- The digest is the one this package would install, which is the version the
  -- control names. A package that is not ready has no digest to clear.
  function self:clear_quarantine()
    local sha256 = type(self.package_target) == "table"
      and self.package_target.sha256 or nil
    if type(sha256) ~= "string" then
      self.paused = true
      return self:_set_state({kind = "refuse", detail = "quarantine-no-target"})
    end
    local state = self:_durable_action("clear_quarantine", sha256)
    self.paused = state.kind ~= "quarantine-cleared"
    return state
  end

  function self:replace_package()
    return self:stage_package({replace_equal_version = true})
  end

  -- The user's answer to a repair prompt. It is the only way an unknown
  -- identity becomes a replacement, and the prompt that offers it has to say
  -- what will be replaced.
  function self:confirm_repair()
    return self:stage_package({confirmed = true})
  end

  function self:repair_withdrawn()
    local state = self:_durable_action("repair_withdrawn")
    if state.kind == "withdrawn-repaired" then
      -- What the repair left behind is read back rather than assumed. A repair
      -- run by an app that cannot verify the entries it kept rewrites the
      -- record without making it readable, and saying "clear" over that would
      -- hand the user a control that changes nothing.
      self:withdrawn()
      self.paused = self.withdrawn_state ~= "clear"
      -- The record is readable again, so the session start that refused on it
      -- runs once more. Without this, a removal the repaired record calls for
      -- would wait for the next REAPER launch.
      if not self.paused then self.session_checked = false end
    end
    return state
  end

  function self:merge_withdrawn(entries)
    return self:_durable_action("merge_withdrawn", entries)
  end

  -- The verified digest set, for the app to hand to whatever gates its calls.
  -- It reads the shared record every time it is asked, because another app can
  -- merge a withdrawal into that record at any moment of this session, and an
  -- answer kept from the session start would be the one thing standing between
  -- a withdrawal and the app that is still calling the digest it names.
  --
  -- It moves no transaction, but it does record what the record said, so the
  -- presentation never shows a reading older than the last one taken. An answer
  -- that is not a reading at all, because the installer lock was held
  -- elsewhere, records nothing and leaves the last reading standing: a moment
  -- of contention is not evidence about the record, and a caller that treated
  -- it as evidence would refuse an Engine for the rest of the session over it.
  function self:withdrawn()
    local runtime = self:_runtime()
    local value = nil
    if runtime and type(runtime.withdrawn) == "function" then
      local ok, read = pcall(runtime.withdrawn, runtime)
      if ok and type(read) == "table" then value = read end
    end
    if type(value) ~= "table" then
      -- No runtime at all, which is not transient and not a lock.
      value = {kind = "withdrawn-unusable", detail = "runtime",
        digests = {}, dropped = {}}
    end
    if value.kind == "withdrawn-clear" then
      self.withdrawn_state = "clear"
      self.withdrawn_detail = nil
    elseif value.kind == "withdrawn-unusable" then
      self.withdrawn_state = "unusable"
      self.withdrawn_detail = value.detail
    end
    return value
  end

  function self:cache_package(source)
    if self.package_state ~= "ready" or type(self.package_target) ~= "table" then
      return {kind="refuse", detail="package-unavailable"}
    end
    local runtime = self:_runtime()
    if not runtime or type(runtime.cache_bundle) ~= "function" then
      return {kind="refuse", detail="cache-runtime-unavailable"}
    end
    local value, why = runtime:cache_bundle(self.package_target, source)
    self:_clear_hash_cache()
    return value or {kind="busy", detail=tostring(why or "lock-unavailable")}
  end

  function self:stage_package(options)
    if self.package_state ~= "ready" or type(self.package_target) ~= "table" then
      self.paused = true
      self:_clear_hash_cache()
      return self:_set_state({
        kind = "refuse",
        detail = "package-" .. tostring(self.package_state)
          .. (self.package_reason and (":" .. tostring(self.package_reason)) or ""),
      })
    end
    local state = self:_durable_action("stage", self.package_target,
      type(options) == "table" and options or nil)
    self.paused = state.kind ~= "staged" and state.kind ~= "resume"
    return state
  end

  return self
end

-- `options` is additive and optional, so a caller written before the
-- withdrawal record existed still attaches. It carries `verify_signature`, the
-- primitive the app owns: which keys are authorized, and how a signature over
-- a payload is checked. Without it no entry ever verifies, which means no
-- digest is ever treated as withdrawn on the strength of a recorded hash or a
-- signer's name alone.
--
-- THE PRIMITIVE ANSWERS THREE THINGS, NOT TWO.
-- `verify_signature(payload, signature, key_id)` must return:
--
--   "verified"     a key this app authorizes checked this signature over these
--                  payload bytes and it verified;
--   "rejected"     a key this app authorizes checked this signature and it did
--                  not verify;
--   "unknown-key"  this app cannot decide. It holds no key under `key_id`, its
--                  key store is unavailable, or it declines to answer. Any
--                  other value means the same thing.
--
-- An app that answers "rejected" for a key it does not hold is stating a proof
-- it did not perform, and the kit acts on that: it ignores a withdrawal
-- another authority signed, and its repair discards the entry for every app
-- that could have read it. `true` is read as "verified"; `false` is read as
-- "cannot decide", because a boolean cannot say which of the two it meant.
-- Answering "unknown-key" is not a failure. It makes the record unreadable to
-- this app, which refuses installs and Engine calls until the app ships the
-- key or the user repairs the record with an app that has one.
function Host.attach(reaper_api, ra, json, hash_bytes, core, runtime_module,
                     package_module, log, options)
  if type(reaper_api) ~= "table" or type(ra) ~= "table"
      or type(json) ~= "table" or type(hash_bytes) ~= "function"
      or type(core) ~= "table" or type(runtime_module) ~= "table"
      or type(runtime_module.new) ~= "function"
      or type(package_module) ~= "table"
      or type(package_module.target_for) ~= "function"
      or type(package_module.expected_contract) ~= "function"
      or type(ra.instance_file_suffix) ~= "function"
      or type(ra.instance_liveness) ~= "function"
      or type(ra.path_present) ~= "function"
      or type(reaper_api.GetResourcePath) ~= "function"
      or type(reaper_api.RecursiveCreateDirectory) ~= "function" then
    return nil, "host-dependency-missing"
  end

  local instance_id = ra.instance_file_suffix()
  local now = type(reaper_api.time_precise) == "function"
    and reaper_api.time_precise() or 0
  local session_id, session_why = Host.session_id(
    reaper_api, instance_id, now, math.random(100000, 999999))
  if not session_id then return nil, session_why end
  local resource_root = slash(reaper_api.GetResourcePath())
  local compact = type(options) == "table" and options.require_descriptor == true
  local bundle_root = compact and join(resource_root, "Data/mbriggs_helper")
    or join(ra.RESOURCES_DIR, "Engine")
  local platform = Host.detect_platform(reaper_api)
  local byte_hash_cache = {}
  local function hash_file(path)
    local digest, state = Host.hash_file_engine(reaper_api, path)
    if digest then return digest, state end
    if ra.IS_WINDOWS ~= true then
      local digest, state = Host.hash_file_posix(io, path, ra.IS_MACOS == true)
      if digest then return digest, state end
    end
    return Host.hash_file(io, hash_bytes, path, byte_hash_cache)
  end
  local verify_signature = type(options) == "table"
    and type(options.verify_signature) == "function"
    and options.verify_signature or nil
  -- The fourth value is what the descriptor promises about the Engine inside
  -- the artifact, which the activation probe compares a loaded contract
  -- against. It is not the target and is never staged: a target carries the
  -- four identity fields the decision core validates and nothing else.
  local package_target, package_state, package_reason, package_contract,
    package_bundle_suffix =
    Host.load_package(
      io, json, ra.path_present, join(ra.RESOURCES_DIR, "Engine/index.json"),
      platform, package_module, core, {
        acceptance_allowed = Host.acceptance_allowed(io, resource_root),
        artifact_root = bundle_root,
        cache_only = type(options) == "table" and options.cache_only == true,
        require_descriptor = compact,
        descriptor = type(options) == "table" and options.descriptor or nil,
      })

  -- The descriptor's own withdrawal statement, unpacked but not trusted: the
  -- kit still requires an authorized signature over a payload that names each
  -- digest before it treats one as withdrawn. It is offered only when the
  -- descriptor validated, so a package this host refused withdraws nothing.
  local withdrawal_entries = nil
  if package_state == "ready" and verify_signature
      and type(package_module.withdrawal_entries) == "function" then
    local descriptor = type(options) == "table" and options.descriptor or nil
    if type(descriptor) == "table" then
      local ok, unpacked = pcall(package_module.withdrawal_entries, descriptor,
        json.decode)
      if ok and type(unpacked) == "table" and #unpacked > 0 then
        withdrawal_entries = unpacked
      end
    end
  end

  local runtime_options = {
    core = core,
    json = json,
    hash_bytes = hash_bytes,
    hash_file = hash_file,
    mkdir = function(path)
      return reaper_api.RecursiveCreateDirectory(path, 0)
    end,
    path_present = ra.path_present,
    instance_liveness = ra.instance_liveness,
    enumerate_files = function(directory)
      return Host.enumerate_files(reaper_api, directory)
    end,
    loaded_version = function()
      if not api_exists(reaper_api, "MBH_GetVersion") then return nil end
      return call_pair_string(reaper_api.MBH_GetVersion)
    end,
    probe = function(lane, journal, paths)
      return Host.probe_engine(reaper_api, lane, journal, paths, json,
        package_contract)
    end,
    log = log,
    is_windows = ra.IS_WINDOWS == true,
    instance_id = instance_id,
    session_id = session_id,
    resource_root = resource_root,
    bundle_root = bundle_root,
    bundle_suffix = package_bundle_suffix,
    bundle_flat = type(options) == "table" and options.cache_only == true,
    bundle_target = package_target,
    live_filename = platform and core.PLATFORM_FILENAMES[platform] or nil,
    -- The target key is the platform this host detected. It is what the status
    -- record is indexed by, and it is the reason a process of one architecture
    -- never certifies or condemns another's slice.
    target_key = platform,
    verify_signature = verify_signature,
    withdrawal_entries = withdrawal_entries,
  }

  return Host.new({
    runtime_factory = function(options) return runtime_module.new(options) end,
    runtime_options = runtime_options,
    path_present = ra.path_present,
    resource_root = resource_root,
    package_target = package_target,
    package_state = package_state,
    package_reason = package_reason,
    hash_cache = byte_hash_cache,
    installed_hash = function()
      if type(package_target) ~= "table" then return nil, "absent" end
      local live_path = join(join(resource_root, "UserPlugins"),
        package_target.filename)
      return hash_file(live_path)
    end,
    log = log,
  })
end

return Host
-- END ENGINE COMPONENT InstallerHost
end)()

if ... == "kit" then return EngineKit end

EngineKit.Client = (function()
-- BEGIN ENGINE COMPONENT Client
-- CFG.VERSION compatibility marker for the frozen ReaAssist v1.5 updater.
-- This module's runtime contract is defined by EngineContract.lua.
-- ============================================================================
-- Engine/lua/Engine.lua
-- ============================================================================
-- The application's side of the mbriggs helper engine seam.
--
-- What lives here and what deliberately does not
-- ----------------------------------------------
-- The production Engine owns provider wire protocols and canonical event
-- conversion. Lua owns product policy, request selection, validation, and
-- presentation. The raw HTTP transport and provider accumulators lower in this
-- file are frozen compatibility code for the unreleased ABI 1 development
-- artifact. No application path calls them: the one caller left in the
-- repository is the local live-provider smoke tool
-- `Dev/Engine/engine/tools/mbh_engine_live_provider_smoke.lua`, which drives
-- `Engine.stream_body`, `Engine.stream_endpoint`, `Engine.new_accumulator`,
-- `Engine.start`, `Engine.poll`, and `Engine.drain` against a live provider.
-- That tool is why the lane and its 512 KiB `Engine.READ_BUFFER` are still
-- here. Production admission forbids the `MBH_Http*` exports the lane uses, so
-- it cannot become a provider fallback inside the application.
--
-- This module has three current jobs:
--
--   1. **Detection and gating.** Validate the ABI 2 structured production
--      contract, required export subset, subsystem versions, and bounded limits.
--
--   2. **Ownership.** Open one capability-owned application client only after
--      contract admission, and close it on a circuit-breaker transition.
--
--   3. **Versioned inference seam.** Start, inspect, read, cancel, and close
--      owned inference resources. Provider-specific request construction stays
--      disabled until its protocol milestone enables native routing.
--
-- Safety model, unchanged
-- -----------------------
-- Streaming is display-only. Validation and execution operate exclusively on
-- the assembled post-stream envelope, never on partial text. A truncated
-- stream is a transport error, and a cancelled turn is discarded unvalidated
-- and unexecuted. Nothing in this file may be used to run generated code.
--
-- Status: shipped application sidecar for the Engine transport cutover.
-- ============================================================================

Engine = Engine or {}

local EngineContract = EngineKit.Contract
if type(EngineContract) ~= "table"
    or type(EngineContract.validate) ~= "function" then
  error("Engine contract validator unavailable")
end

Engine.MODULE_VERSION = 2

-- Error codes owned by the engine seam. Kept here as named values so the
-- application cutover never has to infer policy from numeric ranges.
Engine.ERROR = {
  REFUSED_TOO_MANY_REQUESTS = 1001,
  REFUSED_BAD_SPEC          = 1002,
  REFUSED_SHUTTING_DOWN     = 1003,
  REFUSED_BAD_BODY          = 1004,
  REFUSED_NUL_IN_PAYLOAD    = 1005,
  RESPONSE_TOO_LARGE        = 1010,
  SSE_EVENT_TOO_LARGE       = 1011,
  SSE_MALFORMED             = 1012,
  GLOBAL_BUDGET_EXHAUSTED   = 1013,
  GENERIC_TRANSPORT         = 1099,
}

-- The seam revision this module was written against. Growth inside one ABI is
-- additive and admitted; the ABI number itself is pinned exactly, because the
-- release package admits exactly one and a different number is a different seam.
Engine.REQUIRED_ABI = 2

Engine.REQUIRED_SUBSYSTEMS = {
  core = 1,
  client = 1,
  inference = 1,
  input_media = 1,
  stateless_helpers = 1,
}

Engine.REQUIRED_STATUS_VOCABULARY = {
  "cancelled", "closed", "completed", "consumed", "failed", "loading",
  "queued", "ready", "streaming",
}

Engine.REQUIRED_ERROR_VOCABULARY = {
  "capacity", "capability", "internal", "invalid_argument",
  "invalid_state", "not_supported", "protocol", "provider", "transport",
  "unsupported_acceptance_token", "unsupported_input_modality",
  "unsupported_output_modality",
}

Engine.SUPPORTED_PROTOCOLS = {
  anthropic_messages = true,
  deepseek_responses = true,
  openai_chat_completions = true,
  openai_responses = true,
  openrouter_chat_completions = true,
  openrouter_responses = true,
  google_generate_content = true,
  google_interactions = true,
}

Engine.SUPPORTED_PROFILES = {
  custom_openai_chat_v1 = "openai_chat_completions",
  custom_openai_responses_v1 = "openai_responses",
  local_openai_chat_v1 = "openai_chat_completions",
  local_openai_responses_v1 = "openai_responses",
  local_openai_chat_private_v1 = "openai_chat_completions",
  local_openai_responses_private_v1 = "openai_responses",
}

local PROFILE_PROVIDER = {
  custom_openai_chat_v1 = "custom",
  custom_openai_responses_v1 = "custom",
  local_openai_chat_v1 = "local_server",
  local_openai_responses_v1 = "local_server",
  local_openai_chat_private_v1 = "local_server",
  local_openai_responses_private_v1 = "local_server",
}

Engine.PROFILE_REQUIRED_INFERENCE_REVISION = 2

-- App releases admit native routing one protocol at a time. A newer additive
-- Engine contract cannot silently activate another known prototype.
Engine.NATIVE_ROUTING_PROTOCOLS = {
  anthropic_messages = true,
  deepseek_responses = true,
  google_generate_content = true,
  google_interactions = true,
  openai_responses = true,
  openrouter_chat_completions = true,
  openrouter_responses = true,
}

Engine.PROTOCOL_REQUIRED_EXPORTS = {
  google_interactions = {
    "MBH_InferenceV1ConversationOpen",
    "MBH_InferenceV1StartWithConversation",
    "MBH_InferenceV1ConversationCommit",
    "MBH_InferenceV1ConversationClose",
  },
}

Engine.CACHE_REQUIRED_EXPORTS = {
  "MBH_InferenceCacheV1Create",
  "MBH_InferenceCacheV1Reattach",
  "MBH_InferenceCacheV1Status",
  "MBH_InferenceCacheV1Renew",
  "MBH_InferenceCacheV1Delete",
  "MBH_InferenceCacheV1Close",
  "MBH_InferenceV1StartWithCache",
}

Engine.OPENROUTER_CATALOG_REQUIRED_EXPORTS = {
  "MBH_OpenRouterCatalogV1Start",
  "MBH_OpenRouterCatalogV1Status",
  "MBH_OpenRouterCatalogV1Read",
  "MBH_OpenRouterCatalogV1Cancel",
  "MBH_OpenRouterCatalogV1Close",
}

Engine.CONTRACT_BUFFER_BYTES = 32 * 1024
Engine.MAX_RESULT_BUFFER_BYTES = 256 * 1024
Engine.MAX_OPENROUTER_CATALOG_READ_BYTES = 512 * 1024
Engine.CONTRACT_BUFFER = string.rep(" ", Engine.CONTRACT_BUFFER_BYTES)

-- Read buffer for the caller-sized out-buffer convention.
--
-- Its length is the capacity the engine sees: REAPER supplies the size pointer
-- but sets its incoming value to zero, so the buffer's own length is the only
-- dependable statement of how much room there is. This was established by
-- instrumenting a real REAPER, and getting it wrong is silent: reads succeed,
-- consume their data, and return empty strings.
--
-- 512 KB matches the engine's per-call cap exactly. Smaller would throttle
-- reads for no reason; larger would be wasted.
Engine.READ_BUFFER = string.rep(" ", 512 * 1024)

-- Ceiling on a provider-supplied content-block or tool-call index.
--
-- These indices are chosen by the provider and used to key sparse maps, and
-- assembly has to walk a range because Lua's length operator is undefined on a
-- sparse table. That makes the highest index a loop bound, which makes it a
-- number the far end of a network connection gets to choose. An index of
-- 1000000000 would spin the main thread of a DAW for minutes.
--
-- Real responses use single-digit indices. Anything past this is refused and
-- counted as a fault rather than clamped, because a response that numbers its
-- blocks in the thousands is not a response this code understands.
Engine.MAX_BLOCK_INDEX = 1023

-- Every container belonging to a KNOWN event shape goes through one of these
-- before it is dereferenced.
--
-- The distinction that governs all of it: an unknown event type or field is
-- routine and tolerated, because providers add them and failing a turn over one
-- would be brittle. A known shape carrying the wrong type is a fault, because
-- indexing it raises a Lua error, and an error inside a defer callback takes
-- the whole stream handler down rather than failing one turn.
--
-- This was fixed piecemeal twice, one dereference at a time, and both times a
-- reviewer found more. Hence one helper applied everywhere rather than a
-- case-by-case judgement at each site.

-- A table check is not a kind check, and the difference is not cosmetic. Lua
-- has one table type where JSON has two, and the host decoder hands back both
-- as plain tables. An OBJECT arriving where an ARRAY belongs makes ipairs visit
-- nothing, so a stream that carried its whole answer in `choices` walks away
-- empty and the provider's finish signal still completes the turn: the exact
-- silently-short outcome every rule in this module exists to prevent. An ARRAY
-- arriving where an OBJECT belongs (tool input as `[]`) sails past a plain
-- table test and reaches the executor as arguments nothing can read.
--
-- An empty table is accepted by both, because `{}` and `[]` are the same value
-- once decoded and nothing here can tell them apart. Beyond that the shape is
-- decided by whether index 1 is occupied, which is what the host's own encoder
-- uses to make the same distinction in reverse.

-- The value if it is an array-shaped table, an empty table if it is absent, nil
-- if it is present and the wrong kind. Callers treat nil as a fault.
local function as_array(v)
  if v == nil then return {} end
  if type(v) ~= "table" then return nil end
  if next(v) == nil then return v end
  if v[1] == nil then return nil end
  return v
end

-- The same for an object-shaped table.
local function as_object(v)
  if v == nil then return {} end
  if type(v) ~= "table" then return nil end
  if next(v) == nil then return v end
  if v[1] ~= nil then return nil end
  return v
end

-- Validate a provider-supplied index. Returns the integer, or nil.
local function safe_index(v)
  local n = tonumber(v)
  if n == nil then return nil end
  if n ~= math.floor(n) then return nil end   -- fractional
  if n < 0 or n > Engine.MAX_BLOCK_INDEX then return nil end
  return n
end

-- ============================================================================
-- Detection
-- ============================================================================

local RELEASE_EXPORTS = {
  "MBH_GetVersion", "MBH_GetABI", "MBH_GetContractV1", "MBH_GetBuildInfo",
  "MBH_ClientOpenV1", "MBH_ClientCloseV1",
  "MBH_ClientGetOperationalStatsV1",
  "MBH_InferenceV1Start", "MBH_InferenceV1Status", "MBH_InferenceV1Read",
  "MBH_InferenceV1Cancel", "MBH_InferenceV1Close",
  "MBH_InputMediaV1CreateFromFile", "MBH_InputMediaV1Status",
  "MBH_InputMediaV1Close", "MBH_InferenceV1StartWithInputMedia",
  "MBH_SHA256File", "MBH_SHA256String",
  "MBH_Dialog_BrowseForSaveFile", "MBH_Dialog_BrowseForOpenFiles",
  "MBH_Dialog_BrowseForFolder", "MBH_Window_GetFocus",
  "MBH_Window_SetFocus", "MBH_Window_IsWindow", "MBH_Window_GetRect",
  "MBH_Mouse_GetState", "MBH_File_Stat",
}

local FORBIDDEN_PRODUCTION_EXPORTS = {
  "MBH_HttpStart", "MBH_HttpStatus", "MBH_HttpRead", "MBH_HttpCancel",
  "MBH_HttpClose", "MBH_ExecStart", "MBH_ExecStatus", "MBH_ExecRead",
  "MBH_ExecKill", "MBH_ExecClose",
}

local function json_decode_safe(value)
  if type(value) ~= "string" or value == ""
      or type(RA) ~= "table" or type(RA.JSON) ~= "table"
      or type(RA.JSON.decode) ~= "function" then
    return nil
  end
  local ok, decoded = pcall(RA.JSON.decode, value)
  if not ok or type(decoded) ~= "table" then return nil end
  -- A bare `null` or `[]` document decodes to a host-wide shared sentinel
  -- table. Callers write fields into decoded documents, so admitting one here
  -- would poison every later null for the whole session.
  if decoded == RA.JSON.NULL or decoded == RA.JSON.EMPTY_ARRAY then return nil end
  return decoded
end

local strict_token_set = EngineContract.strict_token_set
local validate_positive_integer = EngineContract.positive_integer

local function contract_reason(code, detail)
  local names = {
    schema = "contract schema",
    version = "contract version",
    ABI = "contract ABI",
    build_channel = "contract build channel",
    subsystems = "contract subsystems",
    exports = "contract export allowlist",
    status_vocabulary = "contract status vocabulary",
    error_vocabulary = "contract error vocabulary",
    protocols = "contract protocols",
    inference_profiles = "contract inference profiles",
    inference_profile_revision = "contract inference profile revision",
    limits = "contract limits",
  }
  if code == "subsystem" then return "contract subsystem: " .. tostring(detail) end
  if code == "forbidden_export" then
    return "contract forbidden export: " .. tostring(detail)
  end
  if code == "inference_profile_protocol" then
    return "contract inference profile protocol: " .. tostring(detail)
  end
  if code == "limit" then return "contract limit: " .. tostring(detail) end
  return names[code] or "contract validation"
end

local function validate_contract(contract, encoded, bootstrap_version,
                                 bootstrap_abi)
  local validated, reason, detail = EngineContract.validate(contract, encoded, {
    required_abi = Engine.REQUIRED_ABI,
    bootstrap_version = bootstrap_version,
    bootstrap_abi = bootstrap_abi,
    required_subsystems = Engine.REQUIRED_SUBSYSTEMS,
    required_exports = RELEASE_EXPORTS,
    forbidden_exports = FORBIDDEN_PRODUCTION_EXPORTS,
    required_status_vocabulary = Engine.REQUIRED_STATUS_VOCABULARY,
    required_error_vocabulary = Engine.REQUIRED_ERROR_VOCABULARY,
    profile_protocols = Engine.SUPPORTED_PROFILES,
    profile_required_revision = Engine.PROFILE_REQUIRED_INFERENCE_REVISION,
    contract_buffer_bytes = Engine.CONTRACT_BUFFER_BYTES,
    max_result_buffer_bytes = Engine.MAX_RESULT_BUFFER_BYTES,
  })
  if not validated then return nil, contract_reason(reason, detail) end
  local declared_exports = validated.exports
  local cache_version = contract.subsystems.inference_cache
  if cache_version ~= nil then
    if not validate_positive_integer(cache_version, 1, 1000) then
      return nil, "contract subsystem: inference_cache"
    end
    for _, name in ipairs(Engine.CACHE_REQUIRED_EXPORTS) do
      if declared_exports[name] ~= true then
        return nil, "contract cache export: " .. name
      end
    end
  end
  local catalog_version = contract.subsystems.openrouter_catalog
  if catalog_version ~= nil then
    if not validate_positive_integer(catalog_version, 1, 1000) then
      return nil, "contract subsystem: openrouter_catalog"
    end
    for _, name in ipairs(Engine.OPENROUTER_CATALOG_REQUIRED_EXPORTS) do
      if declared_exports[name] ~= true then
        return nil, "contract OpenRouter catalog export: " .. name
      end
    end
  end
  local protocols = validated.protocols
  local profiles = validated.profiles
  local limits = validated.limits
  if cache_version ~= nil then
    if not validate_positive_integer(limits.inference_caches, 1, 1024)
        or not validate_positive_integer(limits.inference_caches_per_client,
          1, limits.inference_caches) then
      return nil, "contract limit: inference caches"
    end
  end
  if catalog_version ~= nil then
    if not validate_positive_integer(limits.openrouter_catalogs, 1, 1024)
        or not validate_positive_integer(
          limits.openrouter_catalogs_per_client, 1,
          limits.openrouter_catalogs)
        or not validate_positive_integer(
          limits.openrouter_catalog_snapshot_bytes, 1, 16 * 1024 * 1024)
        or not validate_positive_integer(limits.read_chunk_bytes, 1,
          Engine.MAX_OPENROUTER_CATALOG_READ_BYTES) then
      return nil, "contract limit: OpenRouter catalog"
    end
  end
  return {
    value = contract,
    exports = declared_exports,
    protocols = protocols,
    profiles = profiles,
    limits = limits,
  }
end

-- Session-scoped state. Once the engine is marked unusable it stays that way
-- until REAPER restarts: a transport layer that comes and goes mid-session
-- would make every failure ambiguous.
Engine.state = {
  checked      = false,
  available    = false,
  routing_available = false,
  cache_available = false,
  openrouter_catalog_available = false,
  version      = nil,
  abi          = nil,
  contract     = nil,
  protocols    = nil,
  profiles     = nil,
  client_capability = nil,
  client_recovery_serial = 0,
  build        = nil,
  diagnostic_log_fallback = false,
  diagnostic_log_name = nil,
  reason       = nil,   -- why it is unavailable, for Diag
  pinned_to_curl = false,  -- circuit breaker tripped this session
  -- Why the Engine is not usable, in one word, because invalid and
  -- incompatible must never share an outcome.
  --   absent        no Engine is registered in this process
  --   invalid       the bytes are wrong: a handshake that will not parse, a
  --                 contract that does not describe them, a production build
  --                 carrying development exports
  --   incompatible  the bytes are healthy and this app cannot call them: a
  --                 different core_abi, or a subsystem version or export this
  --                 app needs and the Engine does not have
  --   withdrawn     the loaded image is a digest a cooperating app recorded as
  --                 withdrawn, or one this app cannot identify once the shared
  --                 withdrawal record has been read at all
  --   available     usable
  -- An app repairs or upgrades an invalid Engine. It does not touch an
  -- incompatible one: that is another app's working runtime.
  classification = "unchecked",
  incompatibility = nil,
  -- The digest of the file this process loaded, from the contract. It is the
  -- only thing that says which bytes are running here; the file on disk may
  -- already be a replacement, which this process will not be running until it
  -- restarts.
  loaded_file_sha256 = nil,
  -- The withdrawal record's state and digest set, as the installer host read
  -- and verified them. "unchecked" means no app handed them over, which is the
  -- pre-withdrawal behaviour.
  withdrawn_record = "unchecked",
  withdrawn_digests = nil,
}

-- The record itself, before the handshake has said anything about the bytes.
-- A record this body could not read may be hiding a withdrawal of exactly
-- these bytes, so it refuses every call until a user-confirmed repair rewrites
-- it. "unchecked" is the pre-withdrawal behaviour: no app handed a record
-- over, so nothing here withdraws anything.
local function withdrawal_record_refusal()
  if Engine.state.withdrawn_record == "unchecked" then return nil end
  if Engine.state.withdrawn_record ~= "clear" then
    return "the shared withdrawal record could not be read"
  end
  return nil
end

-- The whole admission rule, in one place, for every point that permits a call.
-- `loaded` is the digest of the image this process is running, as the contract
-- reported it.
--
-- It is deliberately the rule `EngineInstaller.decide_use` applies, because
-- two bodies answering the same question differently is how a withdrawn build
-- keeps being called: an identity the installer refuses to vouch for is not
-- one this module may report as available either.
local function withdrawal_refusal(loaded)
  local record = withdrawal_record_refusal()
  if record then return record end
  if Engine.state.withdrawn_record == "unchecked" then return nil end
  -- Withdrawal names bytes. An image that will not say which file it came from
  -- cannot be shown not to be a withdrawn one, so it is not called, and that
  -- does not wait for the set to have something in it: a digest set that
  -- happens to be empty right now is not a licence to call bytes nobody can
  -- attribute, and an admission that another app's next merge would reverse
  -- was never an admission. It is the rule `decide_use` applies in the same
  -- order, and the two bodies agreeing is the point.
  if type(loaded) ~= "string" then
    return "the loaded Engine does not report which file it came from"
  end
  local withdrawn = Engine.state.withdrawn_digests
  if type(withdrawn) == "table" and withdrawn[loaded] == true then
    return "this Engine build has been withdrawn"
  end
  return nil
end

-- STARTUP_ENGINE_API_PROBE_BEGIN
local function api_exists(name)
  if type(reaper) ~= "table" or type(reaper.APIExists) ~= "function" then
    return false
  end
  local ok, exists = pcall(reaper.APIExists, name)
  return ok and exists == true
end
-- STARTUP_ENGINE_API_PROBE_END

local function mark_unavailable(reason, classification, detail)
  Engine.state.checked   = true
  Engine.state.available = false
  Engine.state.classification = classification or "invalid"
  Engine.state.incompatibility = classification == "incompatible" and detail or nil
  Engine.state.routing_available = false
  Engine.state.cache_available = false
  Engine.state.openrouter_catalog_available = false
  Engine.state.diagnostic_log_fallback = false
  Engine.state.diagnostic_log_name = nil
  Engine.state.reason    = reason
  return false
end

-- The app hands over what the installer host read and verified: whether the
-- shared withdrawal record could be read at all, and the digests an authorized
-- signature actually covers. A record this body cannot read is not an empty
-- one, so "unusable" refuses every call.
--
-- A withdrawal that arrives after a successful detection revokes admission
-- here as well as at the next permit point, so nothing that reads
-- `Engine.state` directly (Diag, the installer presentation) can disagree with
-- what a call would be told. The revocation is one-directional: an Engine this
-- session has refused stays refused until REAPER restarts, which is the same
-- rule every other refusal in this module follows.
function Engine.set_withdrawn(record_state, digests)
  if record_state ~= "clear" and record_state ~= "unusable" then
    Engine.state.withdrawn_record = "unchecked"
    Engine.state.withdrawn_digests = nil
    return false
  end
  Engine.state.withdrawn_record = record_state
  Engine.state.withdrawn_digests = type(digests) == "table" and digests or {}
  if Engine.state.checked then
    local refused = withdrawal_refusal(Engine.state.loaded_file_sha256)
    if refused then mark_unavailable(refused, "withdrawn") end
  end
  return true
end

local function call_output(fn, ...)
  local ok, result_ok, value = pcall(fn, ...)
  if not ok or result_ok ~= true or type(value) ~= "string" then return nil end
  return value
end

local function close_operational_client()
  local capability = Engine.state.client_capability
  Engine.state.client_capability = nil
  if type(capability) ~= "string" or capability == ""
      or type(reaper) ~= "table"
      or type(reaper.MBH_ClientCloseV1) ~= "function" then
    return capability == nil
  end
  local limits = Engine.state.contract and Engine.state.contract.limits
  local size = limits and limits.client_result_buffer_bytes or 0
  if not validate_positive_integer(size, 1024,
      Engine.MAX_RESULT_BUFFER_BYTES) then
    return false
  end
  local document = call_output(reaper.MBH_ClientCloseV1, capability,
    string.rep(" ", size))
  local decoded = json_decode_safe(document)
  return decoded ~= nil and decoded.ok == true
end

local function open_operational_client()
  if type(Engine.state.client_capability) == "string" then return true end
  local limits = Engine.state.contract and Engine.state.contract.limits
  local size = limits and limits.client_result_buffer_bytes or 0
  if not validate_positive_integer(size, 1024,
      Engine.MAX_RESULT_BUFFER_BYTES) then
    Engine.state.reason = "invalid client result buffer limit"
    return false
  end
  local document = call_output(reaper.MBH_ClientOpenV1, string.rep(" ", size))
  local decoded = json_decode_safe(document)
  local capability = decoded and decoded.client_capability or nil
  local expected_length = limits.capability_bytes * 2
  if not decoded or decoded.ok ~= true or type(capability) ~= "string"
      or #capability ~= expected_length
      or capability:match("^[0-9a-f]+$") == nil then
    Engine.state.reason = "client self-test failed"
    return false
  end
  Engine.state.client_capability = capability
  return true
end

-- Returns true when the engine may be used. Safe to call repeatedly; the work
-- happens once.
function Engine.detect()
  if Engine.state.checked then
    -- Rechecked rather than remembered. The handshake happened once and
    -- cannot say anything about a withdrawal another app merged after it, so
    -- the cached answer is only ever returned once the current record has been
    -- asked about the digest this process loaded.
    local refused = withdrawal_refusal(Engine.state.loaded_file_sha256)
    if refused then return mark_unavailable(refused, "withdrawn") end
    return Engine.state.available
  end

  if type(reaper) ~= "table" or type(reaper.APIExists) ~= "function" then
    return mark_unavailable("no reaper API surface", "absent")
  end

  -- No Engine at all is absence, which is what an app installs over. A partial
  -- one that answers for some of the three is a defect in those bytes.
  if not api_exists("MBH_GetVersion") then
    return mark_unavailable("missing export: MBH_GetVersion", "absent")
  end
  for _, name in ipairs({"MBH_GetABI", "MBH_GetContractV1"}) do
    if not api_exists(name) then
      return mark_unavailable("missing export: " .. name, "invalid")
    end
  end
  local record_refused = withdrawal_record_refusal()
  if record_refused then return mark_unavailable(record_refused, "withdrawn") end

  local ok_v, version = reaper.MBH_GetVersion()
  if not ok_v or type(version) ~= "string" or version == "" then
    return mark_unavailable("version handshake failed", "invalid")
  end
  Engine.state.version = version

  local abi = reaper.MBH_GetABI()
  if type(abi) ~= "number" then
    return mark_unavailable("ABI handshake failed", "invalid")
  end
  Engine.state.abi = abi
  if abi ~= Engine.REQUIRED_ABI then
    -- Healthy bytes this app cannot call. The ABI is the seam and is pinned
    -- exactly; nothing here is repaired, replaced or quarantined.
    return mark_unavailable(string.format(
      "engine ABI %s does not match the required %d", tostring(abi),
      Engine.REQUIRED_ABI), "incompatible", "core-abi")
  end

  local encoded_contract = call_output(
    reaper.MBH_GetContractV1, Engine.CONTRACT_BUFFER)
  if not encoded_contract or #encoded_contract > Engine.CONTRACT_BUFFER_BYTES then
    return mark_unavailable("contract handshake failed", "invalid")
  end
  local decoded_contract = json_decode_safe(encoded_contract)
  local contract, contract_reason = validate_contract(
    decoded_contract, encoded_contract, version, abi)
  if not contract then
    -- A contract that describes an Engine this app cannot call is
    -- incompatible; one that will not describe the Engine at all is invalid.
    local incompatible = false
    for _, prefix in ipairs({
      "contract subsystem", "contract export allowlist",
      "contract cache export", "contract OpenRouter catalog export",
      "contract inference profile",
      -- A forbidden production export is not on this list. Its presence says
      -- the bytes are not the production build the contract claims, which is
      -- a defect in them, not a mismatch with what this app calls.
    }) do
      if contract_reason:sub(1, #prefix) == prefix then incompatible = true end
    end
    return mark_unavailable(contract_reason,
      incompatible and "incompatible" or "invalid", contract_reason)
  end

  local loaded_digest = type(decoded_contract) == "table"
    and decoded_contract.loaded_file_sha256 or nil
  if type(loaded_digest) ~= "string" or #loaded_digest ~= 64
      or loaded_digest:match("^[0-9a-f]+$") == nil then
    loaded_digest = nil
  end
  Engine.state.loaded_file_sha256 = loaded_digest
  local withdrawn_refused = withdrawal_refusal(loaded_digest)
  if withdrawn_refused then
    return mark_unavailable(withdrawn_refused, "withdrawn")
  end

  for _, name in ipairs(RELEASE_EXPORTS) do
    if not api_exists(name) then
      return mark_unavailable("missing export: " .. name, "incompatible",
        "export:" .. name)
    end
  end
  for _, name in ipairs(FORBIDDEN_PRODUCTION_EXPORTS) do
    if api_exists(name) then
      -- A production build does not carry these. Their presence says the bytes
      -- are not what the contract claims, which is a defect, not a mismatch.
      return mark_unavailable("development export present: " .. name, "invalid")
    end
  end

  local cache_available = contract.value.subsystems.inference_cache ~= nil
  if cache_available then
    for _, name in ipairs(Engine.CACHE_REQUIRED_EXPORTS) do
      if not api_exists(name) then
        return mark_unavailable("missing cache export: " .. name,
          "incompatible", "export:" .. name)
      end
    end
  end
  local catalog_available =
    contract.value.subsystems.openrouter_catalog ~= nil
  if catalog_available then
    for _, name in ipairs(Engine.OPENROUTER_CATALOG_REQUIRED_EXPORTS) do
      if not api_exists(name) then
        return mark_unavailable("missing OpenRouter catalog export: " .. name,
          "incompatible", "export:" .. name)
      end
    end
  end

  local build = call_output(reaper.MBH_GetBuildInfo)
  local build_value = json_decode_safe(build)
  if not build_value or type(build_value.tls) ~= "string"
      or build_value.tls == "" or build_value.tls == "none" then
    return mark_unavailable("TLS build handshake failed", "invalid")
  end
  local diagnostic_log_fallback =
    build_value.diagnostic_log_fallback == true
  local diagnostic_log_name = diagnostic_log_fallback
    and type(build_value.diagnostic_log_name) == "string"
    and #build_value.diagnostic_log_name >= 1
    and #build_value.diagnostic_log_name <= 128
    and build_value.diagnostic_log_name:match("^[%w_.%-]+$")
    and build_value.diagnostic_log_name or nil

  local routing_available = false
  for protocol in pairs(contract.protocols) do
    if Engine.SUPPORTED_PROTOCOLS[protocol] == true
        and Engine.NATIVE_ROUTING_PROTOCOLS[protocol] == true then
      routing_available = true
      break
    end
  end
  if not routing_available then
    for profile_id, protocol in pairs(Engine.SUPPORTED_PROFILES) do
      if contract.profiles[profile_id] == true
          and contract.protocols[protocol] == true then
        routing_available = true
        break
      end
    end
  end

  Engine.state.checked   = true
  Engine.state.available = true
  Engine.state.classification = "available"
  Engine.state.incompatibility = nil
  Engine.state.routing_available = routing_available
  Engine.state.cache_available = cache_available
  Engine.state.openrouter_catalog_available = catalog_available
  Engine.state.contract = contract
  Engine.state.protocols = contract.protocols
  Engine.state.profiles = contract.profiles
  Engine.state.build = build
  Engine.state.diagnostic_log_fallback = diagnostic_log_fallback
  Engine.state.diagnostic_log_name = diagnostic_log_name
  Engine.state.reason = not routing_available
    and "native inference routing is not enabled; curl selected" or nil
  return true
end

-- Reuse the admitted contract for app-side helper groups. This avoids a second
-- contract fetch and keeps every post-load capability decision on the same
-- validated Engine state.
function Engine.exports_available(names)
  if type(names) ~= "table" or not Engine.detect() then return false end
  local declared = Engine.state.contract and Engine.state.contract.exports
  if type(declared) ~= "table" then return false end
  local count = 0
  for index, name in ipairs(names) do
    if type(name) ~= "string" or declared[name] ~= true or not api_exists(name) then
      return false
    end
    count = index
  end
  for key in pairs(names) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > count then
      return false
    end
  end
  return count > 0
end

function Engine.cache_available()
  if type(S) == "table" and S.screen_reader_mode == true then
    return false, "screen_reader_mode"
  end
  if Engine.state.pinned_to_curl then return false, "engine pinned to curl" end
  if not Engine.detect() then
    return false, Engine.state.reason or "engine unavailable"
  end
  if Engine.state.cache_available ~= true then
    return false, "native explicit cache is not advertised"
  end
  if type(Engine.state.protocols) ~= "table"
      or Engine.state.protocols.google_generate_content ~= true then
    return false, "native Google GenerateContent is not advertised"
  end
  if not open_operational_client() then
    return false, Engine.state.reason or "engine client unavailable"
  end
  return true
end

function Engine.openrouter_catalog_available()
  if type(S) == "table" and S.screen_reader_mode == true then
    return false, "screen_reader_mode"
  end
  if Engine.state.pinned_to_curl then return false, "engine pinned to curl" end
  if not Engine.detect() then
    return false, Engine.state.reason or "engine unavailable"
  end
  if Engine.state.openrouter_catalog_available ~= true then
    return false, "native OpenRouter catalog is not advertised"
  end
  if not open_operational_client() then
    return false, Engine.state.reason or "engine client unavailable"
  end
  return true
end

-- True when a request may be routed through the engine right now. Separate
-- from detect() because the circuit breaker can pin a session to curl after a
-- successful handshake.
function Engine.usable()
  if Engine.state.pinned_to_curl then return false end
  if not Engine.detect() or not Engine.state.routing_available then return false end
  return open_operational_client()
end

-- Admission is exact per immutable dispatch. A healthy Engine that advertises
-- one protocol cannot authorize a request for another protocol. This check
-- does not open an operational client, so request construction can use it as a
-- cheap eligibility guard before hashing or serializing large inputs.
function Engine.protocol_available(protocol)
  if type(protocol) ~= "string" or protocol == ""
      or Engine.SUPPORTED_PROTOCOLS[protocol] ~= true then
    return false, "unsupported native protocol"
  end
  if Engine.NATIVE_ROUTING_PROTOCOLS[protocol] ~= true then
    return false, "native protocol is not enabled by this app release"
  end
  if Engine.state.pinned_to_curl then return false, "engine pinned to curl" end
  if not Engine.detect() then
    return false, Engine.state.reason or "engine unavailable"
  end
  if not Engine.state.routing_available then
    return false, Engine.state.reason or "native inference routing disabled"
  end
  if type(Engine.state.protocols) ~= "table"
      or Engine.state.protocols[protocol] ~= true then
    return false, "native protocol not advertised: " .. protocol
  end
  local required_exports = Engine.PROTOCOL_REQUIRED_EXPORTS[protocol]
  local declared_exports = Engine.state.contract and Engine.state.contract.exports
  for _, name in ipairs(required_exports or {}) do
    if type(declared_exports) ~= "table" or declared_exports[name] ~= true
        or not api_exists(name) then
      return false, "native protocol export unavailable: " .. name
    end
  end
  return true
end

-- True when a request may start now. This is the only protocol admission path
-- that opens the session-scoped operational client.
function Engine.protocol_usable(protocol)
  local available, reason = Engine.protocol_available(protocol)
  if not available then return false, reason end
  if not open_operational_client() then
    return false, Engine.state.reason or "engine client unavailable"
  end
  return true
end

-- Native Custom and Local dispatch requires the exact advertised profile and
-- its bound protocol. Protocol advertisement alone never grants endpoint or
-- authentication authority.
function Engine.profile_available(profile_id, protocol)
  local expected_protocol = type(profile_id) == "string"
    and Engine.SUPPORTED_PROFILES[profile_id] or nil
  if not expected_protocol or protocol ~= expected_protocol then
    return false, "unsupported native inference profile"
  end
  if Engine.state.pinned_to_curl then return false, "engine pinned to curl" end
  if not Engine.detect() then
    return false, Engine.state.reason or "engine unavailable"
  end
  if Engine.state.routing_available ~= true then
    return false, "native inference routing unavailable"
  end
  local subsystems = Engine.state.contract and
    Engine.state.contract.value.subsystems
  if type(subsystems) ~= "table"
      or not validate_positive_integer(subsystems.inference,
        Engine.PROFILE_REQUIRED_INFERENCE_REVISION, 1000) then
    return false, "native inference profiles require an Engine update"
  end
  if type(Engine.state.profiles) ~= "table"
      or Engine.state.profiles[profile_id] ~= true then
    return false, "native inference profile not advertised: " .. profile_id
  end
  if type(Engine.state.protocols) ~= "table"
      or Engine.state.protocols[expected_protocol] ~= true then
    return false, "native profile protocol not advertised: " .. expected_protocol
  end
  local required_exports = Engine.PROTOCOL_REQUIRED_EXPORTS[expected_protocol]
  local declared_exports = Engine.state.contract and Engine.state.contract.exports
  for _, name in ipairs(required_exports or {}) do
    if type(declared_exports) ~= "table" or declared_exports[name] ~= true
        or not api_exists(name) then
      return false, "native profile export unavailable: " .. name
    end
  end
  return true
end

function Engine.profile_usable(profile_id, protocol)
  local available, reason = Engine.profile_available(profile_id, protocol)
  if not available then return false, reason end
  if not open_operational_client() then
    return false, Engine.state.reason or "engine client unavailable"
  end
  return true
end

-- Trip the circuit breaker. Called when a request fails in a way that suggests
-- engine malfunction rather than network trouble. The session stays on curl
-- from here, and the reason is recorded for Diag.
function Engine.pin_to_curl(reason)
  close_operational_client()
  Engine.state.pinned_to_curl = true
  Engine.state.reason = tostring(reason or "unspecified")
end

function Engine.shutdown()
  return close_operational_client()
end

function Engine.inference_request_body_limit()
  local limits = Engine.state.contract and Engine.state.contract.limits
  local size = limits and limits.request_body_bytes or nil
  if not validate_positive_integer(size, 1024 * 1024,
      256 * 1024 * 1024) then
    return nil
  end
  return size
end

function Engine.inference_image_limits()
  local limits = Engine.state.contract and Engine.state.contract.limits
  if type(limits) ~= "table"
      or not validate_positive_integer(limits.inference_image_count, 1, 1024)
      or not validate_positive_integer(limits.inference_image_bytes, 1,
        limits.request_body_bytes)
      or not validate_positive_integer(limits.inference_image_aggregate_bytes,
        limits.inference_image_bytes, limits.request_body_bytes) then
    return nil
  end
  return {
    count = limits.inference_image_count,
    bytes = limits.inference_image_bytes,
    aggregate_bytes = limits.inference_image_aggregate_bytes,
  }
end

-- Compact description for diagnostic reports.
function Engine.describe()
  if not Engine.state.checked then Engine.detect() end
  return {
    present      = Engine.state.available,
    version      = Engine.state.version,
    abi          = Engine.state.abi,
    contract_schema = Engine.state.contract and Engine.state.contract.value.schema,
    build_channel = Engine.state.contract
      and Engine.state.contract.value.build_channel,
    subsystems = Engine.state.contract
      and Engine.state.contract.value.subsystems,
    protocols = Engine.state.contract
      and Engine.state.contract.value.protocols,
    inference_profiles = Engine.state.contract
      and Engine.state.contract.value.inference_profiles,
    routing_available = Engine.state.routing_available,
    cache_available = Engine.state.cache_available,
    openrouter_catalog_available =
      Engine.state.openrouter_catalog_available,
    client_open = type(Engine.state.client_capability) == "string",
    build        = Engine.state.build,
    diagnostic_log_fallback = Engine.state.diagnostic_log_fallback,
    diagnostic_log_name = Engine.state.diagnostic_log_name,
    pinned_to_curl = Engine.state.pinned_to_curl,
    reason       = Engine.state.reason,
  }
end

-- Monotonic, session-local marker for a client creation call that recovered
-- from a pre-dispatch capability refusal and then succeeded. Callers compare
-- before and after one operation. The capability itself is never exposed.
function Engine.client_recovery_serial()
  return Engine.state.client_recovery_serial
end

local OPERATIONAL_EXACT_FIELDS = {
  "client_opens", "statistics_reads", "resources_started",
  "resources_settled", "cancellations", "local_refusals",
  "capacity_refusals", "invalid_lifecycle", "resources_closed",
  "resources_reaped", "event_queue_high_water",
}
local OPERATIONAL_OBSERVER_FIELDS = {
  "origin", "other_client_activity_since_open", "other_active_clients_now",
  "other_active_client_high_water_since_open",
  "capability_denials_since_open",
}
local OPERATIONAL_BUCKETS = {
  ["0"] = true, ["1"] = true, ["2-3"] = true, ["4-7"] = true,
  ["8-15"] = true, ["16-31"] = true, ["32-63"] = true, ["64+"] = true,
}
local OPERATIONAL_RING_SUBSYSTEMS = {
  client = true, inference = true, inference_cache = true,
  input_media = true, openrouter_catalog = true,
}
local OPERATIONAL_RING_EVENTS = {
  open = true, resource_refusal = true, resource_start = true,
  resource_close = true, request_cancel = true, provider_event = true,
  request_terminal = true, conversation_commit = true,
  catalog_settled = true, catalog_cancelled = true, catalog_read = true,
}
local OPERATIONAL_RING_OUTCOMES = {
  ok = true, expired = true, completed = true, failed = true,
  cancelled = true, capacity = true, invalid_argument = true,
  invalid_state = true, internal = true, protocol = true, provider = true,
  transport = true, unknown = true,
}

local function exact_named_table(value, names)
  if type(value) ~= "table" then return false end
  local expected = {}
  for _, name in ipairs(names) do expected[name] = true end
  local count = 0
  for name in pairs(value) do
    if expected[name] ~= true then return false end
    count = count + 1
  end
  return count == #names
end

-- Returns requesting-client statistics only when the operational client already
-- exists. Diagnostics must never open a client solely to observe it.
function Engine.operational_stats()
  -- A diagnostic read is still a call into the loaded image, so it asks the
  -- same admission question every other call point asks.
  if not Engine.detect() then
    return nil, Engine.state.reason or "engine unavailable"
  end
  local capability = Engine.state.client_capability
  if type(capability) ~= "string" or capability == "" then
    return nil, "no_operational_client"
  end
  if type(reaper) ~= "table"
      or type(reaper.MBH_ClientGetOperationalStatsV1) ~= "function" then
    return nil, "operational_stats_unavailable"
  end
  local limits = Engine.state.contract and Engine.state.contract.limits
  local size = limits and limits.client_result_buffer_bytes or 0
  local counter_max = limits and limits.operational_counter_max or 0
  local ring_max = limits and limits.client_event_ring_entries or 0
  if not validate_positive_integer(size, 1024,
      Engine.MAX_RESULT_BUFFER_BYTES)
      or not validate_positive_integer(counter_max, 1, 65535)
      or not validate_positive_integer(ring_max, 1, 32) then
    return nil, "operational_stats_contract"
  end
  local document = call_output(reaper.MBH_ClientGetOperationalStatsV1,
    capability, string.rep(" ", size))
  local decoded = json_decode_safe(document)
  if not decoded or decoded.ok ~= true
      or not exact_named_table(decoded, {"ok", "exact", "observer", "ring"})
      or not exact_named_table(decoded.exact, OPERATIONAL_EXACT_FIELDS)
      or not exact_named_table(decoded.observer, OPERATIONAL_OBSERVER_FIELDS)
      or type(decoded.ring) ~= "table" or #decoded.ring > ring_max then
    return nil, "operational_stats_protocol"
  end
  local exact = {}
  for _, name in ipairs(OPERATIONAL_EXACT_FIELDS) do
    local value = decoded.exact[name]
    if type(value) ~= "number" or value ~= math.floor(value)
        or value < 0 or value > counter_max then
      return nil, "operational_stats_protocol"
    end
    exact[name] = value
  end
  if decoded.observer.origin ~= "Unknown" then
    return nil, "operational_stats_protocol"
  end
  local observer = {origin = "Unknown"}
  for _, name in ipairs(OPERATIONAL_OBSERVER_FIELDS) do
    if name ~= "origin" then
      local value = decoded.observer[name]
      if OPERATIONAL_BUCKETS[value] ~= true then
        return nil, "operational_stats_protocol"
      end
      observer[name] = value
    end
  end
  local ring = {}
  for index, item in ipairs(decoded.ring) do
    if not exact_named_table(item,
        {"sequence", "subsystem", "event", "outcome"})
        or type(item.sequence) ~= "number"
        or item.sequence ~= math.floor(item.sequence) or item.sequence < 1
        or item.sequence > 9007199254740991
        or OPERATIONAL_RING_SUBSYSTEMS[item.subsystem] ~= true
        or OPERATIONAL_RING_EVENTS[item.event] ~= true
        or OPERATIONAL_RING_OUTCOMES[item.outcome] ~= true then
      return nil, "operational_stats_protocol"
    end
    ring[index] = {
      sequence = item.sequence, subsystem = item.subsystem,
      event = item.event, outcome = item.outcome,
    }
  end
  for key in pairs(decoded.ring) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > #ring then
      return nil, "operational_stats_protocol"
    end
  end
  return {exact = exact, observer = observer, ring = ring}
end

-- ============================================================================
-- ABI 2 versioned inference seam
-- ============================================================================

local cached_inference_result_buffer
local cached_inference_result_buffer_size = 0

local function inference_result_buffer()
  local limits = Engine.state.contract and Engine.state.contract.limits
  local size = limits and limits.inference_result_buffer_bytes or 0
  if not validate_positive_integer(size, 1024,
      Engine.MAX_RESULT_BUFFER_BYTES) then
    return nil
  end
  if cached_inference_result_buffer_size ~= size then
    cached_inference_result_buffer = string.rep(" ", size)
    cached_inference_result_buffer_size = size
  end
  return cached_inference_result_buffer
end

local function inference_failure(message, request_sent)
  return {
    ok = false,
    state = "failed",
    error = tostring(message or "internal"),
    request_sent = request_sent ~= false,
  }
end

local function screen_reader_inference_refusal()
  if type(S) == "table" and S.screen_reader_mode == true then
    return inference_failure("screen_reader_mode", false)
  end
  return nil
end

-- Decode and classify the public document before Engine detection. Custom and
-- Local Server requests must carry the one profile that binds their provider
-- to their protocol. A profile on any other provider is refused here so an
-- unknown hosted provider cannot borrow Custom or Local Server authority.
local function classify_public_inference_spec(public_json)
  local public_spec = json_decode_safe(public_json)
  if not public_spec or (type(RA) == "table" and type(RA.JSON) == "table"
      and public_spec == RA.JSON.NULL) then
    return nil, nil, "invalid_argument"
  end
  if public_spec.provider == "custom"
      or public_spec.provider == "local_server" then
    local profile_id = public_spec.profile_id
    if type(profile_id) ~= "string" or profile_id == ""
        or PROFILE_PROVIDER[profile_id] ~= public_spec.provider
        or Engine.SUPPORTED_PROFILES[profile_id] ~= public_spec.protocol then
      return nil, nil, "unsupported native inference profile"
    end
    return public_spec, true
  end
  if public_spec.profile_id ~= nil then
    return nil, nil, "unsupported native inference profile"
  end
  return public_spec, false
end

local function operational_client_available()
  return type(Engine.state.client_capability) == "string"
    and Engine.state.client_capability ~= ""
end

local function inference_call(fn, arguments)
  -- Every operational call funnels through here, including the status, cancel
  -- and close calls that hold a capability from before. Admission is asked for
  -- again rather than inherited from the handshake that opened the client, so
  -- a withdrawal that arrives mid-session stops the next call rather than the
  -- next session.
  if not Engine.detect() then return nil end
  if type(arguments) ~= "table" or not operational_client_available()
      or arguments[1] ~= Engine.state.client_capability then
    return nil
  end
  local buffer = inference_result_buffer()
  if not buffer then return nil end
  arguments[#arguments + 1] = buffer
  local document = call_output(fn, table.unpack(arguments, 1, #arguments))
  arguments[#arguments] = nil
  return document
end

-- Client-only creation calls may recover once when the Engine has revoked the
-- cached client capability. A capability refusal occurs before the requested
-- operation is admitted, so this path cannot repeat a sent provider request.
-- Calls that depend on an existing resource capability must not use this
-- helper because client revocation also revokes those resources.
local function client_creation_call(fn, arguments)
  local document = inference_call(fn, arguments)
  local decoded = json_decode_safe(document)
  if type(decoded) ~= "table" or decoded.ok ~= false
      or decoded.error ~= "capability"
      or decoded.request_sent ~= nil and decoded.request_sent ~= false then
    return document
  end
  Engine.state.client_capability = nil
  if not open_operational_client() then return document end
  arguments[1] = Engine.state.client_capability
  local retry_document = inference_call(fn, arguments)
  local retry_decoded = json_decode_safe(retry_document)
  if type(retry_decoded) == "table" and retry_decoded.ok == true then
    Engine.state.client_recovery_serial =
      Engine.state.client_recovery_serial + 1
  end
  return retry_document
end

-- These methods are intentionally separate from the frozen ABI 1 raw transport
-- methods below. The provider milestone can migrate Net to this seam without
-- allowing an ABI 2 production Engine to enter the old raw HTTP path.
function Engine.inference_start(public_json, secret_json, input_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if type(public_json) ~= "string" or type(secret_json) ~= "string"
      or type(input_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  local public_spec, uses_profile, classification_error =
    classify_public_inference_spec(public_json)
  if not public_spec then
    return nil, inference_failure(classification_error, false)
  end
  local usable, reason
  if uses_profile then
    usable, reason = Engine.profile_usable(
      public_spec.profile_id, public_spec.protocol)
  else
    usable, reason = Engine.protocol_usable(public_spec.protocol)
  end
  if not usable then return nil, inference_failure(reason, false) end
  local document = client_creation_call(reaper.MBH_InferenceV1Start, {
    Engine.state.client_capability, public_json, secret_json, input_json,
  })
  if not document then return nil, inference_failure("internal", true) end
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("protocol", true) end
  if decoded.ok ~= true then
    decoded.request_sent = decoded.request_sent ~= false
    return nil, decoded
  end
  local capability = decoded.request_capability
  local request_id = decoded.request_id
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil
      or type(request_id) ~= "string" or request_id == "" then
    return nil, inference_failure("protocol", true)
  end
  return {
    request_capability = capability,
    request_id = request_id,
    closed = false,
  }
end

local encode_json
local valid_inference_handle

local function valid_conversation_revision(value)
  return type(value) == "string" and #value == 64
    and value:match("^[0-9a-f]+$") ~= nil
end

local function valid_conversation_handle(handle)
  return type(handle) == "table" and handle.closed ~= true
    and type(handle.conversation_capability) == "string"
    and handle.conversation_capability ~= ""
    and type(handle.generation) == "number"
    and handle.generation >= 0
    and handle.generation == math.floor(handle.generation)
    and valid_conversation_revision(handle.context_revision)
    and valid_conversation_revision(handle.history_revision)
end

function Engine.inference_conversation_open(binding)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  local usable, reason = Engine.protocol_usable("google_interactions")
  if not usable then return nil, inference_failure(reason, false) end
  if type(binding) ~= "table"
      or not valid_conversation_revision(binding.context_revision)
      or not valid_conversation_revision(binding.history_revision) then
    return nil, inference_failure("invalid_argument", false)
  end
  local binding_json = encode_json(binding)
  if not binding_json then return nil, inference_failure("internal", false) end
  local document = client_creation_call(
    reaper.MBH_InferenceV1ConversationOpen, {
    Engine.state.client_capability, binding_json,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", false) end
  if decoded.ok ~= true then return nil, decoded end
  local capability = decoded.conversation_capability
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  local valid_capability = type(capability) == "string"
    and #capability == capability_bytes * 2
    and capability:match("^[0-9a-f]+$") ~= nil
  if not valid_capability or decoded.generation ~= 0
      or decoded.context_revision ~= binding.context_revision
      or decoded.history_revision ~= binding.history_revision then
    if valid_capability then
      pcall(inference_call, reaper.MBH_InferenceV1ConversationClose, {
        Engine.state.client_capability, capability,
      })
    end
    return nil, inference_failure("protocol", false)
  end
  return {
    conversation_capability = capability,
    generation = 0,
    context_revision = binding.context_revision,
    history_revision = binding.history_revision,
    provider = binding.provider,
    protocol = binding.protocol,
    api_version = binding.api_version,
    model = binding.model,
    closed = false,
  }
end

function Engine.inference_start_with_conversation(
    conversation, public_json, secret_json, input_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not valid_conversation_handle(conversation)
      or type(public_json) ~= "string" or type(secret_json) ~= "string"
      or type(input_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  local public_spec, uses_profile, classification_error =
    classify_public_inference_spec(public_json)
  if not public_spec then
    return nil, inference_failure(classification_error, false)
  end
  if uses_profile then
    local available, reason = Engine.profile_available(
      public_spec.profile_id, public_spec.protocol)
    if not available then return nil, inference_failure(reason, false) end
    return nil, inference_failure("unsupported native protocol", false)
  end
  if public_spec.protocol ~= conversation.protocol
      or conversation.protocol ~= "google_interactions" then
    return nil, inference_failure("unsupported native protocol", false)
  end
  local usable, reason = Engine.protocol_usable(public_spec.protocol)
  if not usable then return nil, inference_failure(reason, false) end
  local continuity_json = encode_json({
    generation = conversation.generation,
    context_revision = conversation.context_revision,
    history_revision = conversation.history_revision,
  })
  if not continuity_json then
    return nil, inference_failure("internal", false)
  end
  local document = inference_call(
    reaper.MBH_InferenceV1StartWithConversation, {
      Engine.state.client_capability, conversation.conversation_capability,
      continuity_json, public_json, secret_json, input_json,
    })
  if not document then return nil, inference_failure("internal", true) end
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("protocol", true) end
  if decoded.ok ~= true then
    decoded.request_sent = decoded.request_sent ~= false
    return nil, decoded
  end
  local capability = decoded.request_capability
  local request_id = decoded.request_id
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  local valid_capability = type(capability) == "string"
    and #capability == capability_bytes * 2
    and capability:match("^[0-9a-f]+$") ~= nil
  if not valid_capability
      or type(request_id) ~= "string" or request_id == ""
      or decoded.protocol ~= conversation.protocol
      or decoded.conversation_generation ~= conversation.generation then
    if valid_capability then
      pcall(inference_call, reaper.MBH_InferenceV1Close, {
        Engine.state.client_capability, capability,
      })
    end
    return nil, inference_failure("protocol", true)
  end
  return {
    request_capability = capability,
    request_id = request_id,
    closed = false,
    conversation = conversation,
  }
end

function Engine.inference_conversation_commit(
    conversation, request_handle, next_history_revision)
  local refusal = screen_reader_inference_refusal()
  if refusal then return false, refusal end
  if not valid_conversation_handle(conversation)
      or not valid_inference_handle(request_handle)
      or request_handle.conversation ~= conversation
      or not valid_conversation_revision(next_history_revision) then
    return false, inference_failure("invalid_argument", true)
  end
  local commit_json = encode_json({
    next_history_revision = next_history_revision,
  })
  if not commit_json then return false, inference_failure("internal", true) end
  local document = inference_call(reaper.MBH_InferenceV1ConversationCommit, {
    Engine.state.client_capability, conversation.conversation_capability,
    request_handle.request_capability, commit_json,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", true) end
  if decoded.ok ~= true then return false, decoded end
  if decoded.generation ~= conversation.generation + 1
      or decoded.history_revision ~= next_history_revision then
    return false, inference_failure("protocol", true)
  end
  conversation.generation = decoded.generation
  conversation.history_revision = decoded.history_revision
  return true, decoded
end

function Engine.inference_conversation_close(conversation)
  local refusal = screen_reader_inference_refusal()
  if refusal then return false, refusal end
  if type(conversation) ~= "table" then
    return false, inference_failure("invalid_state", false)
  end
  if conversation.closed == true then return true, {ok = true} end
  if type(conversation.conversation_capability) ~= "string"
      or conversation.conversation_capability == "" then
    conversation.closed = true
    return false, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InferenceV1ConversationClose, {
    Engine.state.client_capability, conversation.conversation_capability,
  })
  conversation.closed = true
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", false) end
  return decoded.ok == true, decoded
end

local function valid_input_media_handle(handle)
  return type(handle) == "table" and handle.closed ~= true
    and handle.consumed ~= true
    and type(handle.media_capability) == "string"
    and handle.media_capability ~= ""
end

encode_json = function(value)
  if type(RA) ~= "table" or type(RA.JSON) ~= "table"
      or type(RA.JSON.encode) ~= "function" then
    return nil
  end
  local ok, encoded = pcall(RA.JSON.encode, value)
  if ok and type(encoded) == "string" and encoded ~= "" then
    return encoded
  end
  return nil
end

local function valid_cache_revision(value)
  return type(value) == "string" and #value == 64
    and value:match("^[0-9a-f]+$") ~= nil
end

local function valid_cache_binding(binding)
  local adapter_revision = type(binding) == "table"
    and binding.adapter_contract_revision or nil
  local valid_adapter_revision = type(adapter_revision) == "number"
      and adapter_revision > 0 and adapter_revision == math.floor(adapter_revision)
    or type(adapter_revision) == "string" and #adapter_revision >= 1
      and #adapter_revision <= 64
      and adapter_revision:match("^[%w_.%-]+$") ~= nil
  return type(binding) == "table"
    and binding.provider == "google"
    and binding.protocol == "google_generate_content"
    and binding.api_version == "v1beta"
    and type(binding.model) == "string" and #binding.model >= 1
    and #binding.model <= 128
    and binding.model:match("^[%w_.%-]+$") ~= nil
    and valid_adapter_revision
    and valid_cache_revision(binding.source_revision)
    and valid_cache_revision(binding.context_revision)
end

local function copy_cache_binding(binding)
  if not valid_cache_binding(binding) then return nil end
  return {
    provider = binding.provider,
    protocol = binding.protocol,
    api_version = binding.api_version,
    model = binding.model,
    adapter_contract_revision = binding.adapter_contract_revision,
    source_revision = binding.source_revision,
    context_revision = binding.context_revision,
  }
end

local function valid_cache_handle(handle)
  return type(handle) == "table" and handle.closed ~= true
    and type(handle.cache_capability) == "string"
    and handle.cache_capability ~= ""
    and valid_cache_binding(handle.binding)
end

local CACHE_STATES = {
  creating = true, reattaching = true, ready = true, renewing = true,
  deleting = true, invalidated = true, deleted = true, failed = true,
  closed = true,
}

local CACHE_OPERATIONS = {
  none = true, create = true, reattach = true, renew = true, delete = true,
}

local CACHE_TRANSMISSIONS = {
  not_sent = true, unknown = true, sent = true,
}

local CACHE_RECOVERY_REASONS = {
  transmission_not_proven = true,
  transmission_sent = true,
  provider_cache_state_created = true,
  explicit_cache_state_used = true,
}

local CACHE_ERRORS = {
  capacity = true, capability = true, internal = true,
  invalid_argument = true, invalid_state = true, not_supported = true,
  protocol = true, provider = true, transport = true,
  unsupported_acceptance_token = true,
  unsupported_input_modality = true,
  unsupported_output_modality = true,
}

local function copy_cache_status_recovery(value)
  if type(value) ~= "table" or type(value.blocked) ~= "boolean"
      or type(value.reasons) ~= "table" then
    return nil
  end
  local copy = {blocked = value.blocked, reasons = {}}
  for _, reason in ipairs(value.reasons) do
    if type(reason) == "string" and CACHE_RECOVERY_REASONS[reason] then
      copy.reasons[#copy.reasons + 1] = reason
    end
  end
  return copy
end

local function copy_cache_failure(decoded, default_request_sent)
  if type(decoded) ~= "table" or decoded.ok ~= false then
    return inference_failure("protocol", default_request_sent)
  end
  local transmission = CACHE_TRANSMISSIONS[decoded.transmission]
    and decoded.transmission or nil
  local request_sent
  if type(decoded.request_sent) == "boolean" then
    request_sent = decoded.request_sent
  else
    request_sent = default_request_sent ~= false
  end
  if transmission == nil then
    transmission = request_sent and "unknown" or "not_sent"
  elseif (transmission == "not_sent") ~= (request_sent == false) then
    transmission = "unknown"
    request_sent = true
  end
  local failure = {
    ok = false,
    state = "failed",
    error = type(decoded.error) == "string" and CACHE_ERRORS[decoded.error]
      and decoded.error or "unknown",
    transmission = transmission,
    request_sent = request_sent,
  }
  if type(decoded.cleanup_ttl_fallback) == "boolean" then
    failure.cleanup_ttl_fallback = decoded.cleanup_ttl_fallback
  end
  local recovery = copy_cache_status_recovery(decoded.recovery)
  if recovery then failure.recovery = recovery end
  return failure
end

local function decode_cache_status(document, handle)
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", false) end
  if decoded.ok ~= true then return nil, copy_cache_failure(decoded, true) end
  if CACHE_STATES[decoded.state] ~= true
      or type(decoded.ready) ~= "boolean"
      or type(decoded.reattachment_available) ~= "boolean" then
    return nil, inference_failure("protocol", false)
  end
  if decoded.reattachment_available == true then
    local capability_bytes = Engine.state.contract.limits.capability_bytes
    if type(decoded.reattachment_token) ~= "string"
        or #decoded.reattachment_token ~= capability_bytes * 2
        or decoded.reattachment_token:match("^[0-9a-f]+$") == nil then
      return nil, inference_failure("protocol", false)
    end
    handle.reattachment_token = decoded.reattachment_token
  else
    handle.reattachment_token = nil
  end
  handle.state = decoded.state
  handle.ready = decoded.ready
  local expires_at = type(decoded.expires_at_unix_seconds) == "number"
    and decoded.expires_at_unix_seconds or nil
  handle.expires_at_unix_seconds = expires_at or 0

  -- Keep the Lua boundary structurally private. Only documented, bounded
  -- status fields cross into the application, even if a newer Engine adds an
  -- internal field to its native document. In particular, a provider cache
  -- name can never escape through an additive status field.
  local status = {
    ok = true,
    state = decoded.state,
    ready = decoded.ready,
    reattachment_available = decoded.reattachment_available,
  }
  if CACHE_OPERATIONS[decoded.operation] then
    status.operation = decoded.operation
  end
  if expires_at and expires_at >= 0 and expires_at == math.floor(expires_at) then
    status.expires_at_unix_seconds = expires_at
  end
  local remaining = type(decoded.remaining_seconds) == "number"
    and decoded.remaining_seconds or nil
  if remaining and remaining >= 0 and remaining == math.floor(remaining) then
    status.remaining_seconds = remaining
  end
  if type(decoded.error) == "string" then
    status.error = CACHE_ERRORS[decoded.error] and decoded.error or "unknown"
  end
  if type(decoded.cleanup_ttl_fallback) == "boolean" then
    status.cleanup_ttl_fallback = decoded.cleanup_ttl_fallback
  end
  if CACHE_TRANSMISSIONS[decoded.transmission] then
    status.transmission = decoded.transmission
  end
  if type(decoded.request_sent) == "boolean" then
    status.request_sent = decoded.request_sent
  end
  local recovery = copy_cache_status_recovery(decoded.recovery)
  if recovery then status.recovery = recovery end
  return status
end

local function cache_start_result(document, binding)
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", false) end
  if decoded.ok ~= true then return nil, copy_cache_failure(decoded, true) end
  local capability = decoded.cache_capability
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil
      or (decoded.state ~= "creating" and decoded.state ~= "reattaching") then
    return nil, inference_failure("protocol", true)
  end
  local owned_binding = copy_cache_binding(binding)
  if not owned_binding then return nil, inference_failure("protocol", true) end
  return {
    cache_capability = capability,
    binding = owned_binding,
    state = decoded.state,
    ready = false,
    closed = false,
  }
end

function Engine.inference_cache_create(binding, secret_json, source)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  local available, reason = Engine.cache_available()
  if not available then return nil, inference_failure(reason, false) end
  if not valid_cache_binding(binding) or type(secret_json) ~= "string"
      or type(source) ~= "table" then
    return nil, inference_failure("invalid_argument", false)
  end
  local binding_json = encode_json(binding)
  local source_json = encode_json(source)
  if not binding_json or not source_json then
    return nil, inference_failure("internal", false)
  end
  local document = client_creation_call(reaper.MBH_InferenceCacheV1Create, {
    Engine.state.client_capability, binding_json, secret_json, source_json,
  })
  return cache_start_result(document, binding)
end

function Engine.inference_cache_reattach(token, binding, secret_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  local available, reason = Engine.cache_available()
  if not available then return nil, inference_failure(reason, false) end
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(token) ~= "string" or #token ~= capability_bytes * 2
      or token:match("^[0-9a-f]+$") == nil
      or not valid_cache_binding(binding) or type(secret_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  local binding_json = encode_json(binding)
  if not binding_json then return nil, inference_failure("internal", false) end
  local document = client_creation_call(reaper.MBH_InferenceCacheV1Reattach, {
    Engine.state.client_capability, token, binding_json, secret_json,
  })
  return cache_start_result(document, binding)
end

function Engine.inference_cache_status(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not valid_cache_handle(handle) then
    return nil, inference_failure("invalid_state", false)
  end
  if not operational_client_available() then
    return nil, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InferenceCacheV1Status, {
    Engine.state.client_capability, handle.cache_capability,
  })
  return decode_cache_status(document, handle)
end

function Engine.inference_cache_renew(handle, secret_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not valid_cache_handle(handle) or type(secret_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  if not operational_client_available() then
    return nil, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InferenceCacheV1Renew, {
    Engine.state.client_capability, handle.cache_capability, secret_json,
  })
  return decode_cache_status(document, handle)
end

function Engine.inference_cache_delete(handle, secret_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not valid_cache_handle(handle) or type(secret_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  if not operational_client_available() then
    return nil, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InferenceCacheV1Delete, {
    Engine.state.client_capability, handle.cache_capability, secret_json,
  })
  return decode_cache_status(document, handle)
end

function Engine.inference_cache_close(handle)
  if type(handle) ~= "table" then
    return false, inference_failure("invalid_state", false)
  end
  if handle.closed == true then return true, {ok = true, state = "closed"} end
  if type(handle.cache_capability) ~= "string"
      or handle.cache_capability == "" then
    handle.closed = true
    handle.ready = false
    handle.reattachment_token = nil
    return false, inference_failure("invalid_state", false)
  end
  if not operational_client_available() then
    handle.closed = true
    handle.ready = false
    handle.reattachment_token = nil
    return false, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InferenceCacheV1Close, {
    Engine.state.client_capability, handle.cache_capability,
  })
  handle.closed = true
  handle.ready = false
  handle.reattachment_token = nil
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", false) end
  if decoded.ok ~= true then
    return false, copy_cache_failure(decoded, false)
  end
  local status = {ok = true, state = "closed"}
  if type(decoded.cleanup_ttl_fallback) == "boolean" then
    status.cleanup_ttl_fallback = decoded.cleanup_ttl_fallback
  end
  if CACHE_TRANSMISSIONS[decoded.transmission] then
    status.transmission = decoded.transmission
  end
  if type(decoded.request_sent) == "boolean" then
    status.request_sent = decoded.request_sent
  end
  local recovery = copy_cache_status_recovery(decoded.recovery)
  if recovery then status.recovery = recovery end
  return decoded.state == "closed", status
end

function Engine.inference_start_with_cache(cache, secret_json, input_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  local usable, reason = Engine.protocol_usable("google_generate_content")
  if not usable then return nil, inference_failure(reason, false) end
  if not valid_cache_handle(cache) or cache.ready ~= true
      or type(secret_json) ~= "string" or type(input_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  local binding_json = encode_json(cache.binding)
  if not binding_json then return nil, inference_failure("internal", false) end
  local document = inference_call(reaper.MBH_InferenceV1StartWithCache, {
    Engine.state.client_capability, cache.cache_capability, binding_json,
    secret_json, input_json,
  })
  if not document then return nil, inference_failure("internal", true) end
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("protocol", true) end
  if decoded.ok ~= true then
    return nil, copy_cache_failure(decoded, true)
  end
  local capability = decoded.request_capability
  local request_id = decoded.request_id
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil
      or type(request_id) ~= "string" or request_id == "" then
    return nil, inference_failure("protocol", true)
  end
  return {
    request_capability = capability,
    request_id = request_id,
    closed = false,
    explicit_cache = cache,
  }
end

function Engine.input_media_create(path, media_type)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not Engine.usable() then
    return nil, inference_failure(
      Engine.state.reason or "engine unavailable", false)
  end
  if type(path) ~= "string" or path == ""
      or type(media_type) ~= "string" or media_type == "" then
    return nil, inference_failure("invalid_argument", false)
  end
  local source_json = encode_json({
    revision = 1,
    kind = "image",
    path = path,
    media_type = media_type,
  })
  if not source_json then
    return nil, inference_failure("internal", false)
  end
  local document = client_creation_call(
    reaper.MBH_InputMediaV1CreateFromFile, {
    Engine.state.client_capability, source_json,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", false) end
  if decoded.ok ~= true then return nil, decoded end
  local capability = decoded.media_capability
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil then
    return nil, inference_failure("protocol", false)
  end
  return {
    media_capability = capability,
    state = "loading",
    closed = false,
    consumed = false,
  }
end

function Engine.input_media_status(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if type(handle) ~= "table" or handle.closed == true
      or type(handle.media_capability) ~= "string"
      or handle.media_capability == "" then
    return nil, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InputMediaV1Status, {
    Engine.state.client_capability, handle.media_capability,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", false) end
  if decoded.ok == true and type(decoded.state) == "string" then
    handle.state = decoded.state
    if decoded.state == "consumed" then handle.consumed = true end
  end
  if decoded.ok == true then return decoded, nil end
  return nil, decoded
end

function Engine.input_media_close(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return false, refusal end
  if type(handle) ~= "table" then
    return false, inference_failure("invalid_state", false)
  end
  if handle.closed == true then return true, {ok = true} end
  if type(handle.media_capability) ~= "string"
      or handle.media_capability == "" then
    handle.closed = true
    return false, inference_failure("invalid_state", false)
  end
  local document = inference_call(reaper.MBH_InputMediaV1Close, {
    Engine.state.client_capability, handle.media_capability,
  })
  handle.closed = true
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", false) end
  return decoded.ok == true, decoded
end

function Engine.inference_start_with_input_media(
    media_handles, public_json, secret_json, input_json)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if type(media_handles) ~= "table" or #media_handles == 0
      or type(public_json) ~= "string" or type(secret_json) ~= "string"
      or type(input_json) ~= "string" then
    return nil, inference_failure("invalid_argument", false)
  end
  local public_spec, uses_profile, classification_error =
    classify_public_inference_spec(public_json)
  if not public_spec then
    return nil, inference_failure(classification_error, false)
  end
  if uses_profile then
    local available, reason = Engine.profile_available(
      public_spec.profile_id, public_spec.protocol)
    if not available then return nil, inference_failure(reason, false) end
    return nil, inference_failure("unsupported_input_modality", false)
  end
  local usable, reason = Engine.protocol_usable(public_spec.protocol)
  if not usable then return nil, inference_failure(reason, false) end
  local capabilities, seen = {}, {}
  for index, handle in ipairs(media_handles) do
    if not valid_input_media_handle(handle)
        or seen[handle.media_capability] then
      return nil, inference_failure("invalid_argument", false)
    end
    capabilities[index] = handle.media_capability
    seen[handle.media_capability] = true
  end
  for key in pairs(media_handles) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > #capabilities then
      return nil, inference_failure("invalid_argument", false)
    end
  end
  local capabilities_json = encode_json(capabilities)
  if not capabilities_json then
    return nil, inference_failure("internal", false)
  end
  local document = inference_call(
    reaper.MBH_InferenceV1StartWithInputMedia, {
      Engine.state.client_capability, capabilities_json, public_json,
      secret_json, input_json,
    })
  local decoded = json_decode_safe(document)
  if not decoded then
    for _, handle in ipairs(media_handles) do handle.consumed = true end
    return nil, inference_failure("protocol", true)
  end
  if decoded.ok ~= true then
    decoded.request_sent = decoded.request_sent ~= false
    return nil, decoded
  end
  for _, handle in ipairs(media_handles) do
    handle.consumed = true
    handle.state = "consumed"
  end
  local capability = decoded.request_capability
  local request_id = decoded.request_id
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil
      or type(request_id) ~= "string" or request_id == "" then
    return nil, inference_failure("protocol", true)
  end
  return {
    request_capability = capability,
    request_id = request_id,
    closed = false,
    input_media_consumed = true,
  }
end

valid_inference_handle = function(handle)
  return type(handle) == "table" and handle.closed ~= true
    and type(handle.request_capability) == "string"
    and handle.request_capability ~= ""
end

function Engine.inference_status(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return refusal end
  if not valid_inference_handle(handle) then
    return inference_failure("invalid_state", true)
  end
  local document = inference_call(reaper.MBH_InferenceV1Status, {
    Engine.state.client_capability, handle.request_capability,
  })
  if type(document) ~= "string" then
    return nil, inference_failure("internal", true)
  end
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", true) end
  return decoded
end

function Engine.inference_read(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return nil, refusal end
  if not valid_inference_handle(handle) then
    return nil, inference_failure("invalid_state", true)
  end
  local document = inference_call(reaper.MBH_InferenceV1Read, {
    Engine.state.client_capability, handle.request_capability,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return nil, inference_failure("internal", true) end
  if decoded.ok ~= true then return nil, decoded end
  if type(RA) == "table" and type(RA.JSON) == "table"
      and decoded.event == RA.JSON.NULL then
    return nil
  end
  if decoded.event == nil then return nil end
  if type(decoded.event) ~= "table" then
    return nil, inference_failure("protocol", true)
  end
  return decoded.event
end

function Engine.inference_cancel(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return false, refusal end
  if not valid_inference_handle(handle) then
    return false, inference_failure("invalid_state", true)
  end
  local document = inference_call(reaper.MBH_InferenceV1Cancel, {
    Engine.state.client_capability, handle.request_capability,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", true) end
  return decoded.ok == true, decoded
end

function Engine.inference_close(handle)
  local refusal = screen_reader_inference_refusal()
  if refusal then return false, refusal end
  if type(handle) ~= "table" then
    return false, inference_failure("invalid_state", true)
  end
  if handle.closed == true then return true, {ok = true} end
  if type(handle.request_capability) ~= "string"
      or handle.request_capability == "" then
    handle.closed = true
    return false, inference_failure("invalid_state", true)
  end
  local document = inference_call(reaper.MBH_InferenceV1Close, {
    Engine.state.client_capability, handle.request_capability,
  })
  handle.closed = true
  local decoded = json_decode_safe(document)
  if not decoded then return false, inference_failure("internal", true) end
  return decoded.ok == true, decoded
end

-- ============================================================================
-- OpenRouter model and endpoint catalog
-- ============================================================================

local OPENROUTER_CATALOG = {
  states = {
    queued = true, streaming = true, completed = true, consumed = true,
    failed = true, cancelled = true, closed = true,
  },
  errors = {
    capacity = true, capability = true, internal = true,
    invalid_argument = true, invalid_state = true, not_supported = true,
    protocol = true, provider = true, transport = true,
  },
  pricing_keys = {
    "prompt", "completion", "request", "image", "web_search",
    "internal_reasoning", "input_cache_read", "input_cache_write",
  },
}

function OPENROUTER_CATALOG.failure(error)
  return {
    ok = false,
    state = "failed",
    error = OPENROUTER_CATALOG.errors[error] and error or "internal",
  }
end

function OPENROUTER_CATALOG.path(value, minimum_segments, maximum_segments,
                                  maximum_bytes)
  if type(value) ~= "string" or value == "" or #value > maximum_bytes
      or value:sub(1, 1) == "/" or value:sub(-1) == "/"
      or value:match("^[A-Za-z0-9_.:/%-]+$") == nil then
    return false
  end
  local count = 0
  for segment in value:gmatch("[^/]+") do
    if segment == "." or segment == ".."
        or segment:match("^[A-Za-z0-9_.:%-]+$") == nil then
      return false
    end
    count = count + 1
  end
  return count >= minimum_segments and count <= maximum_segments
    and not value:find("//", 1, true)
end

function OPENROUTER_CATALOG.identifier(value)
  return type(value) == "string" and value ~= "" and #value <= 64
    and value:match("^[A-Za-z0-9_.:+%-]+$") ~= nil
end

function OPENROUTER_CATALOG.safe_token(value, maximum_bytes)
  return type(value) == "string" and value ~= ""
    and #value <= maximum_bytes
    and value:match("^[A-Za-z0-9_.:+%-]+$") ~= nil
end

function OPENROUTER_CATALOG.preset_slug(value)
  return type(value) == "string" and value ~= "" and #value <= 128
    and value:match("^[A-Za-z0-9._~%-]+$") ~= nil
end

function OPENROUTER_CATALOG.preset_status(value)
  return type(value) == "string" and #value >= 1 and #value <= 32
    and value:match("^[A-Za-z0-9_%-]+$") ~= nil
end

function OPENROUTER_CATALOG.exact_keys(value, allowed)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do
    if allowed[key] ~= true then return false end
  end
  return true
end

function OPENROUTER_CATALOG.display_text(value)
  if type(value) ~= "string" or value == "" or #value > 256
      or value:find("[%z\1-\31\127]") then
    return false
  end
  return type(utf8) ~= "table" or type(utf8.len) ~= "function"
    or utf8.len(value) ~= nil
end

function OPENROUTER_CATALOG.decimal(value)
  return type(value) == "string" and #value <= 64
    and (value:match("^%d+$") ~= nil
      or value:match("^%d+%.%d+$") ~= nil)
end

function OPENROUTER_CATALOG.integer(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value)
    and value >= minimum and value <= maximum
end

function OPENROUTER_CATALOG.string_array(value)
  if type(value) ~= "table" or #value > 64 then return nil end
  local output, seen = {}, {}
  for index, item in ipairs(value) do
    if not OPENROUTER_CATALOG.identifier(item) or seen[item] then return nil end
    output[index] = item
    seen[item] = true
  end
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > #output then
      return nil
    end
  end
  return output
end

function OPENROUTER_CATALOG.architecture(value)
  if type(value) ~= "table" then return nil end
  local input = OPENROUTER_CATALOG.string_array(value.input_modalities)
  local output = OPENROUTER_CATALOG.string_array(value.output_modalities)
  if not input or not output then return nil end
  return {input_modalities = input, output_modalities = output}
end

function OPENROUTER_CATALOG.pricing(value)
  if type(value) ~= "table" then return nil end
  local output = {}
  for _, key in ipairs(OPENROUTER_CATALOG.pricing_keys) do
    if value[key] ~= nil then
      if not OPENROUTER_CATALOG.decimal(value[key]) then return nil end
      output[key] = value[key]
    end
  end
  return output
end

function OPENROUTER_CATALOG.metric(value, maximum)
  return type(value) == "number" and value >= 0 and value <= maximum
end

function OPENROUTER_CATALOG.percentiles(value)
  if value == nil then return nil, true end
  if type(value) ~= "table" then return nil, false end
  local output = {}
  for _, key in ipairs({"p50", "p75", "p90", "p99"}) do
    if value[key] ~= nil then
      if not OPENROUTER_CATALOG.metric(value[key], 1000000000000) then
        return nil, false
      end
      output[key] = value[key]
    end
  end
  return output, true
end

function OPENROUTER_CATALOG.endpoint(value, model_id, seen)
  if type(value) ~= "table"
      or not OPENROUTER_CATALOG.path(value.tag, 1, 3, 128)
      or seen[value.tag] then
    return nil
  end
  local pricing = OPENROUTER_CATALOG.pricing(value.pricing)
  local parameters = OPENROUTER_CATALOG.string_array(
    value.supported_parameters)
  if not pricing or not parameters then return nil end
  local output = {
    tag = value.tag,
    pricing = pricing,
    supported_parameters = parameters,
  }
  seen[value.tag] = true
  for _, key in ipairs({"provider_name", "name"}) do
    if value[key] ~= nil then
      if not OPENROUTER_CATALOG.display_text(value[key]) then return nil end
      output[key] = value[key]
    end
  end
  if value.quantization ~= nil then
    if not OPENROUTER_CATALOG.identifier(value.quantization) then return nil end
    output.quantization = value.quantization
  end
  for key, bounds in pairs({
    context_length = {1, 100000000},
    max_prompt_tokens = {0, 100000000},
    max_completion_tokens = {0, 100000000},
    status = {-100, 100},
  }) do
    if value[key] ~= nil then
      if not OPENROUTER_CATALOG.integer(
          value[key], bounds[1], bounds[2]) then return nil end
      output[key] = value[key]
    end
  end
  for _, key in ipairs({
    "uptime_last_5m", "uptime_last_30m", "uptime_last_1d",
  }) do
    if value[key] ~= nil then
      if not OPENROUTER_CATALOG.metric(value[key], 100) then return nil end
      output[key] = value[key]
    end
  end
  for _, key in ipairs({"latency_last_30m", "throughput_last_30m"}) do
    local metric, valid = OPENROUTER_CATALOG.percentiles(value[key])
    if not valid then return nil end
    if metric then output[key] = metric end
  end
  if value.supports_implicit_caching ~= nil then
    if type(value.supports_implicit_caching) ~= "boolean" then return nil end
    output.supports_implicit_caching = value.supports_implicit_caching
  end
  return output
end

function OPENROUTER_CATALOG.snapshot(value, handle)
  if type(value) ~= "table" or value.kind ~= handle.kind then return nil end
  if value.kind == "presets" then
    if not OPENROUTER_CATALOG.exact_keys(value, {
        kind = true, total_count = true, presets = true,
      }) or not OPENROUTER_CATALOG.integer(
        value.total_count, 0, 1000000)
        or type(value.presets) ~= "table" or #value.presets > 100
        or value.total_count < #value.presets then
      return nil
    end
    local output, seen = {
      kind = "presets", total_count = value.total_count, presets = {},
    }, {}
    for index, preset in ipairs(value.presets) do
      if not OPENROUTER_CATALOG.exact_keys(preset, {
          slug = true, name = true, status = true, updated_at = true,
          designated_version_id = true,
        }) or not OPENROUTER_CATALOG.preset_slug(preset.slug)
          or seen[preset.slug]
          or not OPENROUTER_CATALOG.display_text(preset.name)
          or not OPENROUTER_CATALOG.display_text(preset.updated_at)
          or #preset.updated_at > 64
          or not OPENROUTER_CATALOG.preset_status(preset.status)
          or (preset.designated_version_id ~= nil
            and not OPENROUTER_CATALOG.safe_token(
              preset.designated_version_id, 128)) then
        return nil
      end
      output.presets[index] = {
        slug = preset.slug, name = preset.name, status = preset.status,
        updated_at = preset.updated_at,
        designated_version_id = preset.designated_version_id,
      }
      seen[preset.slug] = true
    end
    for key in pairs(value.presets) do
      if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
          or key > #output.presets then
        return nil
      end
    end
    return output
  end
  if value.kind == "preset" then
    if value.preset_slug ~= handle.preset_slug
        or not OPENROUTER_CATALOG.exact_keys(value, {
          kind = true, preset_slug = true, name = true, status = true,
          updated_at = true, designated_version_id = true,
          has_designated_version = true, version = true, model = true,
          models = true, provider_config_present = true,
          tools_present = true, modalities = true,
        }) or not OPENROUTER_CATALOG.preset_slug(value.preset_slug)
        or not OPENROUTER_CATALOG.display_text(value.name)
        or not OPENROUTER_CATALOG.display_text(value.updated_at)
        or #value.updated_at > 64
        or not OPENROUTER_CATALOG.preset_status(value.status)
        or type(value.has_designated_version) ~= "boolean"
        or (value.designated_version_id ~= nil
          and not OPENROUTER_CATALOG.safe_token(
            value.designated_version_id, 128)) then
      return nil
    end
    local output = {
      kind = "preset", preset_slug = value.preset_slug, name = value.name,
      status = value.status, updated_at = value.updated_at,
      designated_version_id = value.designated_version_id,
      has_designated_version = value.has_designated_version,
    }
    if value.has_designated_version == false then
      if value.version ~= nil or value.model ~= nil or value.models ~= nil
          or value.provider_config_present ~= nil
          or value.tools_present ~= nil or value.modalities ~= nil then
        return nil
      end
      return output
    end
    if not OPENROUTER_CATALOG.integer(value.version, 1, 1000000000)
        or type(value.provider_config_present) ~= "boolean"
        or type(value.tools_present) ~= "boolean" then
      return nil
    end
    output.version = value.version
    output.provider_config_present = value.provider_config_present
    output.tools_present = value.tools_present
    if value.model ~= nil then
      if not OPENROUTER_CATALOG.path(value.model, 2, 2, 128) then return nil end
      output.model = value.model
    end
    if value.models ~= nil then
      if type(value.models) ~= "table" or #value.models == 0
          or #value.models > 64 then return nil end
      output.models, seen = {}, {}
      for index, model in ipairs(value.models) do
        if not OPENROUTER_CATALOG.path(model, 2, 2, 128)
            or seen[model] then return nil end
        output.models[index], seen[model] = model, true
      end
      for key in pairs(value.models) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
            or key > #output.models then return nil end
      end
    end
    if value.modalities ~= nil then
      output.modalities = OPENROUTER_CATALOG.string_array(value.modalities)
      if not output.modalities then return nil end
    end
    return output
  end
  if type(value) ~= "table" or value.kind ~= handle.kind
      or value.model_id ~= handle.model_id then
    return nil
  end
  local architecture = OPENROUTER_CATALOG.architecture(value.architecture)
  if not architecture then return nil end
  local output = {
    kind = value.kind,
    model_id = value.model_id,
    architecture = architecture,
  }
  if value.name ~= nil then
    if not OPENROUTER_CATALOG.display_text(value.name) then return nil end
    output.name = value.name
  end
  if value.kind == "model" then
    local parameters = OPENROUTER_CATALOG.string_array(
      value.supported_parameters)
    local pricing = OPENROUTER_CATALOG.pricing(value.pricing)
    if not OPENROUTER_CATALOG.path(value.canonical_slug, 2, 2, 128)
        or not OPENROUTER_CATALOG.integer(
          value.context_length, 1, 100000000)
        or not parameters or not pricing then
      return nil
    end
    output.canonical_slug = value.canonical_slug
    output.context_length = value.context_length
    output.supported_parameters = parameters
    output.pricing = pricing
    return output
  end
  if value.kind ~= "endpoints" or type(value.endpoints) ~= "table"
      or #value.endpoints > 512 then
    return nil
  end
  local endpoints, seen = {}, {}
  for index, endpoint in ipairs(value.endpoints) do
    endpoints[index] = OPENROUTER_CATALOG.endpoint(
      endpoint, handle.model_id, seen)
    if not endpoints[index] then return nil end
  end
  for key in pairs(value.endpoints) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
        or key > #endpoints then
      return nil
    end
  end
  output.endpoints = endpoints
  return output
end

function OPENROUTER_CATALOG.valid_handle(handle)
  local limits = Engine.state.contract and Engine.state.contract.limits
  local capability_bytes = limits and limits.capability_bytes or 0
  return type(handle) == "table" and handle.closed ~= true
    and handle.consumed ~= true
    and type(handle.catalog_capability) == "string"
    and #handle.catalog_capability == capability_bytes * 2
    and handle.catalog_capability:match("^[0-9a-f]+$") ~= nil
    and ((handle.kind == "model" or handle.kind == "endpoints")
      and OPENROUTER_CATALOG.path(handle.model_id, 2, 2, 128)
      or handle.kind == "presets" and handle.model_id == nil
      or handle.kind == "preset"
        and OPENROUTER_CATALOG.preset_slug(handle.preset_slug))
end

function OPENROUTER_CATALOG.status(document, handle)
  local decoded = json_decode_safe(document)
  if not decoded then return nil, OPENROUTER_CATALOG.failure("protocol") end
  if decoded.ok ~= true then
    return nil, OPENROUTER_CATALOG.failure(decoded.error)
  end
  if OPENROUTER_CATALOG.states[decoded.state] ~= true then
    return nil, OPENROUTER_CATALOG.failure("protocol")
  end
  local status = {ok = true, state = decoded.state}
  if decoded.error ~= nil then
    if not OPENROUTER_CATALOG.errors[decoded.error] then
      return nil, OPENROUTER_CATALOG.failure("protocol")
    end
    status.error = decoded.error
  end
  if (decoded.state == "failed") ~= (status.error ~= nil) then
    return nil, OPENROUTER_CATALOG.failure("protocol")
  end
  if decoded.snapshot_bytes ~= nil then
    local maximum = Engine.state.contract.limits
      .openrouter_catalog_snapshot_bytes
    if decoded.state ~= "completed"
        or not OPENROUTER_CATALOG.integer(
          decoded.snapshot_bytes, 1, maximum) then
      return nil, OPENROUTER_CATALOG.failure("protocol")
    end
    status.snapshot_bytes = decoded.snapshot_bytes
  elseif decoded.state == "completed" then
    return nil, OPENROUTER_CATALOG.failure("protocol")
  end
  handle.state = decoded.state
  if decoded.state == "consumed" then handle.consumed = true end
  return status
end

function Engine.openrouter_catalog_start(kind, model_id, secret_json)
  local available, reason = Engine.openrouter_catalog_available()
  if not available then
    return nil, OPENROUTER_CATALOG.failure(reason)
  end
  local query, preset_slug
  if kind == "model" or kind == "endpoints" then
    if not OPENROUTER_CATALOG.path(model_id, 2, 2, 128) then
      return nil, OPENROUTER_CATALOG.failure("invalid_argument")
    end
    query = {kind = kind, model_id = model_id}
  elseif kind == "presets" then
    if model_id ~= nil then
      return nil, OPENROUTER_CATALOG.failure("invalid_argument")
    end
    query = {kind = kind}
  elseif kind == "preset" then
    if not OPENROUTER_CATALOG.preset_slug(model_id) then
      return nil, OPENROUTER_CATALOG.failure("invalid_argument")
    end
    preset_slug = model_id
    query = {kind = kind, preset_slug = preset_slug}
  else
    return nil, OPENROUTER_CATALOG.failure("invalid_argument")
  end
  if type(secret_json) ~= "string" then
    return nil, OPENROUTER_CATALOG.failure("invalid_argument")
  end
  local query_json = encode_json(query)
  if not query_json then
    return nil, OPENROUTER_CATALOG.failure("internal")
  end
  local document = client_creation_call(
    reaper.MBH_OpenRouterCatalogV1Start, {
    Engine.state.client_capability, query_json, secret_json,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return nil, OPENROUTER_CATALOG.failure("protocol") end
  if decoded.ok ~= true then
    return nil, OPENROUTER_CATALOG.failure(decoded.error)
  end
  local capability = decoded.catalog_capability
  local capability_bytes = Engine.state.contract.limits.capability_bytes
  if type(capability) ~= "string" or #capability ~= capability_bytes * 2
      or capability:match("^[0-9a-f]+$") == nil
      or decoded.state ~= "queued" then
    return nil, OPENROUTER_CATALOG.failure("protocol")
  end
  return {
    catalog_capability = capability,
    kind = kind,
    model_id = (kind == "model" or kind == "endpoints") and model_id or nil,
    preset_slug = preset_slug,
    state = "queued",
    consumed = false,
    closed = false,
  }
end

function Engine.openrouter_catalog_status(handle)
  if not OPENROUTER_CATALOG.valid_handle(handle) then
    return nil, OPENROUTER_CATALOG.failure("invalid_state")
  end
  local document = inference_call(reaper.MBH_OpenRouterCatalogV1Status, {
    Engine.state.client_capability, handle.catalog_capability,
  })
  return OPENROUTER_CATALOG.status(document, handle)
end

function Engine.openrouter_catalog_read(handle)
  if not OPENROUTER_CATALOG.valid_handle(handle)
      or handle.state ~= "completed" then
    return nil, OPENROUTER_CATALOG.failure("invalid_state")
  end
  if not operational_client_available() then
    return nil, OPENROUTER_CATALOG.failure("invalid_state")
  end
  local limits = Engine.state.contract.limits
  local read_bytes = limits.read_chunk_bytes
  local snapshot_bytes = limits.openrouter_catalog_snapshot_bytes
  if not validate_positive_integer(read_bytes, 1,
      Engine.MAX_OPENROUTER_CATALOG_READ_BYTES)
      or not validate_positive_integer(snapshot_bytes, 1,
        16 * 1024 * 1024) then
    return nil, OPENROUTER_CATALOG.failure("protocol")
  end
  local buffer = string.rep(" ", read_bytes)
  local pieces, total = {}, 0
  local maximum_reads = math.ceil(snapshot_bytes / read_bytes) + 1
  for index = 1, maximum_reads do
    local called, ok, chunk = pcall(
      reaper.MBH_OpenRouterCatalogV1Read,
      Engine.state.client_capability, handle.catalog_capability, buffer)
    if not called or ok ~= true or type(chunk) ~= "string"
        or #chunk > read_bytes then
      return nil, OPENROUTER_CATALOG.failure("capability")
    end
    total = total + #chunk
    if total > snapshot_bytes then
      return nil, OPENROUTER_CATALOG.failure("capacity")
    end
    pieces[index] = chunk
    local status, failure = Engine.openrouter_catalog_status(handle)
    if not status then return nil, failure end
    if status.state == "consumed" then
      local decoded = json_decode_safe(table.concat(pieces))
      local snapshot = OPENROUTER_CATALOG.snapshot(decoded, handle)
      if not snapshot then
        return nil, OPENROUTER_CATALOG.failure("protocol")
      end
      handle.consumed = true
      return snapshot
    end
    if status.state ~= "completed" or #chunk == 0 then
      return nil, OPENROUTER_CATALOG.failure("protocol")
    end
  end
  return nil, OPENROUTER_CATALOG.failure("capacity")
end

function Engine.openrouter_catalog_cancel(handle)
  if not OPENROUTER_CATALOG.valid_handle(handle) then
    return false, OPENROUTER_CATALOG.failure("invalid_state")
  end
  local document = inference_call(reaper.MBH_OpenRouterCatalogV1Cancel, {
    Engine.state.client_capability, handle.catalog_capability,
  })
  local decoded = json_decode_safe(document)
  if not decoded then return false, OPENROUTER_CATALOG.failure("protocol") end
  if decoded.ok ~= true then
    return false, OPENROUTER_CATALOG.failure(decoded.error)
  end
  handle.state = "cancelled"
  return true, {ok = true, state = "cancelled"}
end

function Engine.openrouter_catalog_close(handle)
  if type(handle) ~= "table" then
    return false, OPENROUTER_CATALOG.failure("invalid_state")
  end
  if handle.closed == true then return true, {ok = true, state = "closed"} end
  if type(handle.catalog_capability) ~= "string"
      or handle.catalog_capability == "" then
    handle.closed = true
    return false, OPENROUTER_CATALOG.failure("invalid_state")
  end
  local document = inference_call(reaper.MBH_OpenRouterCatalogV1Close, {
    Engine.state.client_capability, handle.catalog_capability,
  })
  handle.closed = true
  handle.state = "closed"
  local decoded = json_decode_safe(document)
  if not decoded then return false, OPENROUTER_CATALOG.failure("protocol") end
  if decoded.ok ~= true then
    return false, OPENROUTER_CATALOG.failure(decoded.error)
  end
  return true, {ok = true, state = "closed"}
end

-- ============================================================================
-- ABI 2 canonical event consumer
-- ============================================================================

-- Provider payloads stop at the native boundary. This accumulator accepts only
-- the Engine's provider-neutral event contract and does not reconstruct a
-- provider response envelope. Provisional text can be displayed while events
-- arrive, but only finalize() can authorize the settled response pipeline.
local CanonicalAccumulator = {}
CanonicalAccumulator.__index = CanonicalAccumulator

local CANONICAL_TERMINALS = {
  response_completed = "completed",
  response_failed = "failed",
  response_cancelled = "cancelled",
}

local CANONICAL_USAGE_FIELDS = {
  "input_tokens", "output_tokens", "total_tokens", "cached_input_tokens",
  "cache_write_input_tokens", "cache_write_5m_input_tokens",
  "cache_write_1h_input_tokens", "reasoning_tokens", "tool_use_tokens",
}

local CANONICAL_USAGE_FIELD_SET = {}
for _, name in ipairs(CANONICAL_USAGE_FIELDS) do
  CANONICAL_USAGE_FIELD_SET[name] = true
end

local CANONICAL_USAGE_RELATIONSHIP_FIELDS = {
  "cached_input_to_input", "cache_write_input_to_input",
  "reasoning_to_output", "tool_use_to_input",
}

local CANONICAL_USAGE_SOURCES = {
  not_reported = true,
  provider_reported = true,
  engine_derived = true,
}

local CANONICAL_USAGE_RELATIONSHIPS = {
  included_in_input = true,
  additional_to_input = true,
  included_in_output = true,
  additional_to_output = true,
  unknown = true,
}

local CANONICAL_USAGE_QUALITIES = {
  complete_normalized_usage = true,
  conservative_no_cache_discount = true,
  unknown = true,
}

local CANONICAL_RESPONSE_CACHE_STATUSES = {
  not_reported = true,
  hit = true,
  miss = true,
  invalid = true,
}

local CANONICAL_RESPONSE_CACHE_CONSISTENCIES = {
  confirmed = true,
  contradictory = true,
  unknown = true,
}

local function is_integer_between(value, minimum, maximum)
  return type(value) == "number" and value == math.floor(value)
    and value >= minimum and value <= maximum
end

local function nonempty_bounded_string(value, maximum)
  return type(value) == "string" and value ~= "" and #value <= maximum
end

local function exact_nonnegative_decimal(value)
  if type(value) ~= "string" or value == "" or #value > 128 then return false end
  local index, length = 1, #value
  local first = value:sub(index, index)
  if first == "0" then
    index = index + 1
    local next_byte = value:sub(index, index)
    if next_byte:match("%d") then return false end
  elseif first:match("[1-9]") then
    repeat
      index = index + 1
    until index > length or not value:sub(index, index):match("%d")
  else
    return false
  end
  if value:sub(index, index) == "." then
    index = index + 1
    local fraction_start = index
    while index <= length and value:sub(index, index):match("%d") do
      index = index + 1
    end
    if index == fraction_start then return false end
  end
  local exponent = value:sub(index, index)
  if exponent == "e" or exponent == "E" then
    index = index + 1
    local sign = value:sub(index, index)
    if sign == "+" or sign == "-" then index = index + 1 end
    local exponent_start = index
    while index <= length and value:sub(index, index):match("%d") do
      index = index + 1
    end
    if index == exponent_start then return false end
  end
  return index > length
end

local function exact_actual_cost_decimal(value)
  if not exact_nonnegative_decimal(value) then return false end
  local mantissa, exponent_text = value:match("^([^eE]+)[eE]([+-]?%d+)$")
  if not mantissa then
    mantissa, exponent_text = value, "0"
  end
  local exponent_negative = exponent_text:sub(1, 1) == "-"
  local exponent_digits = exponent_text:gsub("^[+-]", ""):gsub("^0+", "")
  if exponent_digits == "" then exponent_digits = "0" end
  if #exponent_digits > 4 then return false end
  local exponent = tonumber(exponent_digits)
  if not exponent or exponent > 1000 then return false end
  if exponent_negative then exponent = -exponent end

  local integer, fraction = mantissa:match("^(%d+)%.(%d+)$")
  if not integer then integer, fraction = mantissa, "" end
  local digits = (integer .. fraction):gsub("^0+", "")
  if digits == "" then return true end
  local decimal_shift = exponent - #fraction
  local integer_digits = #digits + decimal_shift
  if integer_digits > 10 then return false end
  if integer_digits < 10 then return true end
  local exact_integer = decimal_shift >= 0
      and (digits .. string.rep("0", decimal_shift))
    or digits:sub(1, 10)
  if exact_integer > "1000000000" then return false end
  if exact_integer == "1000000000" and decimal_shift < 0
      and digits:sub(11):find("[1-9]") then
    return false
  end
  return true
end

local function canonical_object(value)
  return as_object(value)
end

local function canonical_array(value)
  return as_array(value)
end

local function actual_cost_decimal_is_zero(value)
  if not exact_actual_cost_decimal(value) then return false end
  local mantissa = value:match("^([^eE]+)") or value
  return mantissa:find("[1-9]") == nil
end

local function valid_actual_cost(value, response_cache)
  if value == nil then return true end
  value = canonical_object(value)
  if value == nil then return false end
  for name in pairs(value) do
    if name ~= "decimal" and name ~= "currency" and name ~= "source" then
      return false
    end
  end
  if not exact_actual_cost_decimal(value.decimal)
      or value.currency ~= "USD" then return false end
  if value.source == "provider_reported" then return true end
  response_cache = canonical_object(response_cache)
  return value.source == "provider_cache_header_derived"
    and actual_cost_decimal_is_zero(value.decimal)
    and response_cache ~= nil and response_cache.status == "hit"
    and response_cache.consistency == "confirmed"
end

local function valid_response_cache(value)
  if value == nil then return true end
  value = canonical_object(value)
  if value == nil then return false end
  for name in pairs(value) do
    if name ~= "status" and name ~= "consistency" then return false end
  end
  return nonempty_bounded_string(value.status, 128)
    and nonempty_bounded_string(value.consistency, 128)
end

local function valid_usage_snapshot(usage)
  usage = canonical_object(usage)
  if usage == nil then return false end
  for _, name in ipairs(CANONICAL_USAGE_FIELDS) do
    if not is_integer_between(usage[name], 0, 1000000000000) then
      return false
    end
  end

  local sources = canonical_object(usage.category_sources)
  if sources == nil then return false end
  for _, name in ipairs(CANONICAL_USAGE_FIELDS) do
    if not nonempty_bounded_string(sources[name], 128) then return false end
  end

  local relationships = canonical_object(usage.relationships)
  if relationships == nil then return false end
  for _, name in ipairs(CANONICAL_USAGE_RELATIONSHIP_FIELDS) do
    if not nonempty_bounded_string(relationships[name], 128) then
      return false
    end
  end

  return nonempty_bounded_string(usage.accounting_quality, 128)
    and type(usage.accounting_disagreement) == "boolean"
    and type(usage.unknown_fields_present) == "boolean"
    and (usage.actual_cost_evidence == nil
      or usage.actual_cost_evidence == "not_reported"
      or usage.actual_cost_evidence == "valid"
      or usage.actual_cost_evidence == "invalid")
    and (usage.actual_cost_evidence == nil
      or (usage.actual_cost_evidence == "valid"
        and usage.actual_cost ~= nil)
      or ((usage.actual_cost_evidence == "not_reported"
          or usage.actual_cost_evidence == "invalid")
        and usage.actual_cost == nil))
    and valid_actual_cost(usage.actual_cost, usage.response_cache)
    and valid_response_cache(usage.response_cache)
end

local function usage_schema_extensions_present(usage)
  local top_level_known = {
    category_sources = true,
    relationships = true,
    accounting_quality = true,
    accounting_disagreement = true,
    unknown_fields_present = true,
    lua_schema_extensions_present = true,
    actual_cost = true,
    actual_cost_evidence = true,
    response_cache = true,
  }
  for name in pairs(CANONICAL_USAGE_FIELD_SET) do top_level_known[name] = true end
  for name in pairs(usage) do
    if top_level_known[name] ~= true then return true end
  end
  for name in pairs(usage.category_sources) do
    if CANONICAL_USAGE_FIELD_SET[name] ~= true then return true end
  end
  local relationship_known = {}
  for _, name in ipairs(CANONICAL_USAGE_RELATIONSHIP_FIELDS) do
    relationship_known[name] = true
  end
  for name in pairs(usage.relationships) do
    if relationship_known[name] ~= true then return true end
  end
  for _, name in ipairs(CANONICAL_USAGE_FIELDS) do
    if CANONICAL_USAGE_SOURCES[usage.category_sources[name]] ~= true then
      return true
    end
  end
  for _, name in ipairs(CANONICAL_USAGE_RELATIONSHIP_FIELDS) do
    if CANONICAL_USAGE_RELATIONSHIPS[usage.relationships[name]] ~= true then
      return true
    end
  end
  local response_cache = usage.response_cache ~= nil
    and canonical_object(usage.response_cache) or nil
  if response_cache ~= nil then
    if CANONICAL_RESPONSE_CACHE_STATUSES[response_cache.status] ~= true
        or CANONICAL_RESPONSE_CACHE_CONSISTENCIES[
          response_cache.consistency] ~= true then
      return true
    end
  end
  if CANONICAL_USAGE_QUALITIES[usage.accounting_quality] ~= true then
    return true
  end
  return false
end

local function copy_usage_snapshot(usage)
  local copy = {}
  for _, name in ipairs(CANONICAL_USAGE_FIELDS) do copy[name] = usage[name] end
  copy.category_sources = {}
  for _, name in ipairs(CANONICAL_USAGE_FIELDS) do
    local source = usage.category_sources[name]
    copy.category_sources[name] = CANONICAL_USAGE_SOURCES[source] == true
      and source or "not_reported"
  end
  copy.relationships = {}
  for _, name in ipairs(CANONICAL_USAGE_RELATIONSHIP_FIELDS) do
    local relationship = usage.relationships[name]
    copy.relationships[name] =
      CANONICAL_USAGE_RELATIONSHIPS[relationship] == true
        and relationship or "unknown"
  end
  copy.accounting_quality =
    CANONICAL_USAGE_QUALITIES[usage.accounting_quality] == true
      and usage.accounting_quality or "unknown"
  copy.accounting_disagreement = usage.accounting_disagreement
  copy.unknown_fields_present = usage.unknown_fields_present
  copy.actual_cost_evidence = usage.actual_cost_evidence
  if usage.actual_cost ~= nil then
    copy.actual_cost = {
      decimal = usage.actual_cost.decimal,
      currency = usage.actual_cost.currency,
      source = usage.actual_cost.source,
    }
  end
  if usage.response_cache ~= nil then
    copy.response_cache = {
      status = CANONICAL_RESPONSE_CACHE_STATUSES[
          usage.response_cache.status] == true
        and usage.response_cache.status or "unknown",
      consistency = CANONICAL_RESPONSE_CACHE_CONSISTENCIES[
          usage.response_cache.consistency] == true
        and usage.response_cache.consistency or "unknown",
    }
  end
  copy.lua_schema_extensions_present =
    usage.lua_schema_extensions_present == true
      or usage_schema_extensions_present(usage)
  return copy
end

local function valid_recovery(value)
  value = canonical_object(value)
  if value == nil or type(value.blocked) ~= "boolean" then return false end
  local reasons = canonical_array(value.reasons)
  if reasons == nil or #reasons > 8 then return false end
  for _, reason in ipairs(reasons) do
    if not nonempty_bounded_string(reason, 128) then return false end
  end
  return value.blocked == (#reasons > 0)
end

local function json_null(value)
  return type(RA) == "table" and type(RA.JSON) == "table"
    and value == RA.JSON.NULL
end

local function valid_discarded(value)
  value = canonical_object(value)
  if value == nil
      or not is_integer_between(value.events, 0, 1000000000)
      or not is_integer_between(value.text_bytes, 0, 8 * 1024 * 1024) then
    return false
  end
  if value.events == 0 then
    return (value.first_sequence == nil or json_null(value.first_sequence))
      and (value.last_sequence == nil or json_null(value.last_sequence))
  end
  return is_integer_between(value.first_sequence, 1, 1000000000)
    and is_integer_between(value.last_sequence, value.first_sequence,
      1000000000)
    and value.events == value.last_sequence - value.first_sequence + 1
end

local function exact_failed_terminal_gap(event, expected_sequence)
  if event.kind ~= "response_failed"
      or not is_integer_between(event.sequence, expected_sequence + 1,
        1000000000) then
    return false
  end
  local discarded = canonical_object(event.discarded)
  return valid_discarded(discarded)
    and discarded.events == event.sequence - expected_sequence
    and discarded.first_sequence == expected_sequence
    and discarded.last_sequence == event.sequence - 1
end

local function valid_provider_error_message(value)
  if not nonempty_bounded_string(value, 1024) then return false end
  for index = 1, #value do
    local byte = value:byte(index)
    if byte == 0 or (byte < 32 and byte ~= 9 and byte ~= 10
        and byte ~= 13) then
      return false
    end
  end
  local ok_utf8, length = pcall(utf8.len, value)
  return ok_utf8 and length ~= nil
end

local function valid_terminal_common(event)
  local transmission = event.transmission
  if transmission ~= "not_sent" and transmission ~= "unknown"
      and transmission ~= "sent" then
    return false
  end
  if type(event.request_sent) ~= "boolean"
      or event.request_sent ~= (transmission ~= "not_sent") then
    return false
  end
  if event.provider_error_message ~= nil
      and (event.kind ~= "response_failed" or transmission ~= "sent"
        or (event.category ~= "provider" and event.category ~= "transport")
        or not valid_provider_error_message(event.provider_error_message)) then
    return false
  end
  if event.diagnostic ~= nil
      and (event.kind ~= "response_failed"
        or not nonempty_bounded_string(event.diagnostic, 128)
        or event.diagnostic:match("^[%w_%-]+$") == nil) then
    return false
  end
  if event.provider_model ~= nil
      and (event.kind ~= "response_completed"
        or not nonempty_bounded_string(event.provider_model, 256)) then
    return false
  end
  return valid_recovery(event.recovery) and valid_discarded(event.discarded)
end

local function copy_terminal_event(event)
  local copy = {
    kind = event.kind,
    request_id = event.request_id,
    sequence = event.sequence,
    category = event.category,
    finish_status = event.finish_status,
    finish_reason = event.finish_reason,
    provider_model = event.provider_model,
    transmission = event.transmission,
    request_sent = event.request_sent,
    recovery = {blocked = event.recovery.blocked, reasons = {}},
    discarded = {
      events = event.discarded.events,
      first_sequence = event.discarded.first_sequence,
      last_sequence = event.discarded.last_sequence,
      text_bytes = event.discarded.text_bytes,
    },
  }
  for index, reason in ipairs(event.recovery.reasons) do
    copy.recovery.reasons[index] = reason
  end
  if event.provider_error_message ~= nil then
    copy.provider_error_message = event.provider_error_message
  end
  if event.diagnostic ~= nil then copy.diagnostic = event.diagnostic end
  if event.kind == "response_completed" then
    copy.settlement = {}
    for _, name in ipairs({
        "text_bytes", "text_sha256", "reasoning_bytes", "reasoning_sha256",
        "reasoning_summary_bytes", "reasoning_summary_sha256",
        "refusal_bytes", "refusal_sha256", "completed_items",
        "abandoned_items", "event_count", "final_sequence",
      }) do
      copy.settlement[name] = event.settlement[name]
    end
  end
  return copy
end

local function engine_sha256_string(value)
  if type(reaper) ~= "table" or type(reaper.MBH_SHA256String) ~= "function" then
    return nil
  end
  local ok_call, ok_hash, digest = pcall(reaper.MBH_SHA256String, value)
  if not ok_call or ok_hash ~= true or type(digest) ~= "string"
      or #digest ~= 64 or digest:match("^[0-9a-f]+$") == nil then
    return nil
  end
  return digest
end

function Engine.sha256_string(value)
  if type(value) ~= "string" or value:find("\0", 1, true) then return nil end
  return engine_sha256_string(value)
end

function Engine.new_canonical_accumulator(request_id)
  if not nonempty_bounded_string(request_id, 512) then return nil end
  return setmetatable({
    request_id = request_id,
    next_sequence = 1,
    event_count = 0,
    started = false,
    text_parts = {},
    reasoning_parts = {},
    reasoning_summary_parts = {},
    refusal_parts = {},
    latest_usage = nil,
    latest_routing_provenance = nil,
    open_items = {},
    completed_items = {},
    abandoned_items = {},
    terminal = nil,
    fault = nil,
    finalized = false,
  }, CanonicalAccumulator)
end

function CanonicalAccumulator:_fail(reason)
  if self.fault == nil then self.fault = tostring(reason or "protocol") end
  return false, self.fault
end

function CanonicalAccumulator:_accept(event)
  self.event_count = self.event_count + 1
  self.next_sequence = event.sequence + 1
  return true, event.kind
end

function CanonicalAccumulator:consume(event)
  if self.fault ~= nil then return false, self.fault end
  if self.finalized then return self:_fail("event_after_finalize") end
  if self.terminal ~= nil then return self:_fail("event_after_terminal") end
  if type(event) ~= "table" then return self:_fail("event_not_object") end
  if event.request_id ~= self.request_id then
    return self:_fail("request_id_mismatch")
  end
  local sequence_is_next = event.sequence == self.next_sequence
  local explained_terminal_gap = exact_failed_terminal_gap(
    event, self.next_sequence)
  if not is_integer_between(event.sequence, 1, 1000000000)
      or (not sequence_is_next and not explained_terminal_gap) then
    return self:_fail("sequence_mismatch")
  end
  if not nonempty_bounded_string(event.kind, 128) then
    return self:_fail("invalid_event_kind")
  end

  local kind = event.kind
  if kind == "response_started" then
    if self.started then return self:_fail("duplicate_response_started") end
    self.started = true
    return self:_accept(event)
  end

  if kind == "text_delta" or kind == "reasoning_delta"
      or kind == "reasoning_summary_delta" or kind == "refusal_delta" then
    if not self.started or type(event.text) ~= "string" then
      return self:_fail("malformed_" .. kind)
    end
    local target = kind == "text_delta" and self.text_parts
      or kind == "reasoning_delta" and self.reasoning_parts
      or kind == "reasoning_summary_delta" and self.reasoning_summary_parts
      or self.refusal_parts
    target[#target + 1] = event.text
    return self:_accept(event)
  end

  if kind == "item_started" then
    if not self.started
        or not nonempty_bounded_string(event.item_kind, 128)
        or not nonempty_bounded_string(event.item_id, 512)
        or self.open_items[event.item_id] ~= nil
        or self.completed_items[event.item_id] ~= nil
        or self.abandoned_items[event.item_id] ~= nil then
      return self:_fail("malformed_item_started")
    end
    self.open_items[event.item_id] = {kind = event.item_kind}
    return self:_accept(event)
  end

  if kind == "item_completed" or kind == "item_abandoned" then
    local open = type(event.item_id) == "string"
      and self.open_items[event.item_id] or nil
    if not self.started or open == nil or event.item_kind ~= open.kind then
      return self:_fail("malformed_" .. kind)
    end
    if kind == "item_completed" then
      if type(event.provider_id) ~= "string" or type(event.name) ~= "string"
          or type(event.arguments) ~= "string" then
        return self:_fail("malformed_item_completed")
      end
      self.completed_items[event.item_id] = {
        kind = event.item_kind,
        provider_id = event.provider_id,
        name = event.name,
        arguments = event.arguments,
      }
    else
      self.abandoned_items[event.item_id] = {kind = event.item_kind}
    end
    self.open_items[event.item_id] = nil
    return self:_accept(event)
  end

  if kind == "usage_updated" then
    if not self.started or not valid_usage_snapshot(event.usage) then
      return self:_fail("malformed_usage_updated")
    end
    -- Usage events are cumulative snapshots. Replacing this value is required
    -- for exact-once billing in the later settled-turn bridge.
    self.latest_usage = copy_usage_snapshot(event.usage)
    return self:_accept(event)
  end

  if kind == "routing_provenance_updated" then
    local provenance = canonical_object(event.provenance)
    if not self.started or provenance == nil
        or self.latest_routing_provenance ~= nil then
      return self:_fail("malformed_routing_provenance_updated")
    end
    for name in pairs(provenance) do
      if name ~= "selected_provider" and name ~= "selected_endpoint"
          and name ~= "attempt" and name ~= "fallback_occurred"
          and name ~= "endpoint_was_configured" then
        return self:_fail("malformed_routing_provenance_updated")
      end
    end
    if not nonempty_bounded_string(provenance.selected_provider, 256)
        or type(provenance.selected_endpoint) ~= "string"
        or #provenance.selected_endpoint > 256
        or not is_integer_between(provenance.attempt, 1, 1024)
        or type(provenance.fallback_occurred) ~= "boolean"
        or type(provenance.endpoint_was_configured) ~= "boolean"
        or provenance.fallback_occurred ~= (provenance.attempt > 1)
        or provenance.endpoint_was_configured
          ~= (provenance.selected_endpoint ~= "") then
      return self:_fail("malformed_routing_provenance_updated")
    end
    self.latest_routing_provenance = {
      selected_provider = provenance.selected_provider,
      selected_endpoint = provenance.selected_endpoint,
      attempt = provenance.attempt,
      fallback_occurred = provenance.fallback_occurred,
      endpoint_was_configured = provenance.endpoint_was_configured,
    }
    return self:_accept(event)
  end

  local terminal_state = CANONICAL_TERMINALS[kind]
  if terminal_state ~= nil then
    if not valid_terminal_common(event)
        or (event.discarded.events > 0 and not explained_terminal_gap)
        or (kind ~= "response_completed"
          and not nonempty_bounded_string(event.category, 128)) then
      return self:_fail("malformed_" .. kind)
    end
    if kind == "response_completed" then
      local settlement = canonical_object(event.settlement)
      if not self.started or event.finish_status ~= "completed"
          or not nonempty_bounded_string(event.finish_reason, 128)
          or settlement == nil then
        return self:_fail("malformed_response_completed")
      end
    end
    self.terminal = copy_terminal_event(event)
    return self:_accept(event)
  end

  -- Additive metadata events keep the stream forward-compatible. They count
  -- toward sequence and settlement evidence and therefore block replay.
  return self:_accept(event)
end

function CanonicalAccumulator:visible_text()
  return table.concat(self.text_parts)
end

function CanonicalAccumulator:readable_reasoning()
  return table.concat(self.reasoning_parts)
end

function CanonicalAccumulator:reasoning_summary()
  return table.concat(self.reasoning_summary_parts)
end

function CanonicalAccumulator:refusal_text()
  return table.concat(self.refusal_parts)
end

local function table_count(value)
  local count = 0
  for _ in pairs(value or {}) do count = count + 1 end
  return count
end

local function settlement_text_matches(settlement, prefix, value)
  local bytes = settlement[prefix .. "_bytes"]
  local digest = settlement[prefix .. "_sha256"]
  return is_integer_between(bytes, 0, 8 * 1024 * 1024)
    and bytes == #value
    and type(digest) == "string"
    and digest == engine_sha256_string(value)
end

local function copy_item_map(items)
  local copy = {}
  for item_id, item in pairs(items or {}) do
    copy[item_id] = {
      kind = item.kind,
      provider_id = item.provider_id,
      name = item.name,
      arguments = item.arguments,
    }
  end
  return copy
end

local function terminal_failure_evidence(terminal)
  local copy = copy_terminal_event(terminal)
  return {
    request_id = copy.request_id,
    kind = copy.kind,
    category = copy.category,
    transmission = copy.transmission,
    request_sent = copy.request_sent,
    recovery = copy.recovery,
    discarded = copy.discarded,
    diagnostic = copy.diagnostic,
    provider_error_message = copy.provider_error_message,
  }
end

function CanonicalAccumulator:finalize(status)
  if self.finalized then return nil, "already_finalized" end
  if type(status) ~= "table" or status.ok ~= true then
    return nil, "status_unavailable"
  end
  self.finalized = true
  if self.fault ~= nil then return nil, self.fault end
  if type(self.terminal) ~= "table" then return nil, "missing_terminal_event" end
  if status.request_id ~= self.request_id or status.terminal ~= true
      or status.terminal_event_lost == true
      or not is_integer_between(status.events_pending, 0, 1000000000)
      or status.events_pending ~= 0 then
    return nil, "terminal_status_mismatch"
  end

  local expected_state = CANONICAL_TERMINALS[self.terminal.kind]
  if status.state ~= expected_state then return nil, "terminal_state_mismatch" end
  if expected_state ~= "completed" then
    return nil, expected_state, terminal_failure_evidence(self.terminal)
  end

  local settlement = canonical_object(self.terminal.settlement)
  if settlement == nil or self.terminal.discarded.events ~= 0
      or not is_integer_between(settlement.final_sequence, 1, 1000000000)
      or settlement.final_sequence ~= self.terminal.sequence
      or not is_integer_between(settlement.event_count, 1, 1000000000)
      or settlement.event_count ~= self.event_count
      or not is_integer_between(settlement.completed_items, 0, 1000000000)
      or settlement.completed_items ~= table_count(self.completed_items)
      or not is_integer_between(settlement.abandoned_items, 0, 1000000000)
      or settlement.abandoned_items ~= table_count(self.abandoned_items)
      or next(self.open_items) ~= nil then
    return nil, "settlement_evidence_mismatch"
  end

  local text = self:visible_text()
  local reasoning = self:readable_reasoning()
  local summary = self:reasoning_summary()
  local refusal = self:refusal_text()
  if not settlement_text_matches(settlement, "text", text)
      or not settlement_text_matches(settlement, "reasoning", reasoning)
      or not settlement_text_matches(settlement, "reasoning_summary", summary)
      or not settlement_text_matches(settlement, "refusal", refusal) then
    return nil, "settlement_text_mismatch"
  end

  local terminal_copy = copy_terminal_event(self.terminal)
  return {
    request_id = self.request_id,
    text = text,
    provider_reasoning = reasoning,
    provider_reasoning_summary = summary,
    refusal_text = refusal,
    finish_status = self.terminal.finish_status,
    finish_reason = self.terminal.finish_reason,
    provider_model = terminal_copy.provider_model,
    usage = self.latest_usage and copy_usage_snapshot(self.latest_usage) or nil,
    routing_provenance = self.latest_routing_provenance and {
      selected_provider = self.latest_routing_provenance.selected_provider,
      selected_endpoint = self.latest_routing_provenance.selected_endpoint,
      attempt = self.latest_routing_provenance.attempt,
      fallback_occurred =
        self.latest_routing_provenance.fallback_occurred,
      endpoint_was_configured =
        self.latest_routing_provenance.endpoint_was_configured,
    } or nil,
    completed_items = copy_item_map(self.completed_items),
    abandoned_items = copy_item_map(self.abandoned_items),
    transmission = terminal_copy.transmission,
    request_sent = terminal_copy.request_sent,
    recovery = terminal_copy.recovery,
    settlement = terminal_copy.settlement,
  }
end

-- ============================================================================
-- Frozen ABI 1 raw transport compatibility code
-- ============================================================================

-- Decode a status document. Kept tolerant: an unreadable status is not a crash,
-- it is an unknown state, and the no-replay rule already says unknown counts as
-- sent.
local function decode_status(doc)
  if type(doc) ~= "string" or doc == "" then
    return { state = "unknown", request_sent = true, error_code = 1099,
             error_msg = "unreadable status" }
  end
  if type(RA) == "table" and type(RA.JSON) == "table"
     and type(RA.JSON.decode) == "function" then
    local ok, v = pcall(RA.JSON.decode, doc)
    -- A bare `null` or `[]` document decodes to a shared host sentinel, which
    -- is not a status. Fall through to the unreadable answer below.
    if ok and type(v) == "table"
        and v ~= RA.JSON.NULL and v ~= RA.JSON.EMPTY_ARRAY then
      return v
    end
  end
  return { state = "unknown", request_sent = true, error_code = 1099,
           error_msg = "status did not decode" }
end

-- Dormant raw-HTTP compatibility lane. Host provider traffic does not
-- call this family. Production Engine admission forbids MBH_Http* exports, so
-- these helpers cannot become an accidental provider fallback. The local
-- live-provider smoke tool still drives them, which is why they are here.
--
-- Start a request.
--
-- opts:
--   url                     (required)
--   method                  default "POST"
--   headers                 array of "Name: value" strings
--   body                    string, sent verbatim
--   sse                     true to have the engine decode event framing
--   connect_timeout_s       default 10
--   total_timeout_s         default 600
--   allow_insecure          custom providers only, mirrors curl's --insecure
--   ssl_revoke_best_effort  Windows only, mirrors --ssl-revoke-best-effort
--   tee_file                raw wire response is copied here
--   max_response_bytes
--
-- Returns a handle table, or nil plus a failure table. Every failure from this
-- function happened before any byte was transmitted, so every one of them is
-- safe to retry on the curl lane.
function Engine.start(opts)
  if not Engine.usable() then
    return nil, { engine_refused = true, request_sent = false,
                  error_code = 0, error_msg = "engine unavailable" }
  end
  if type(opts) ~= "table" or type(opts.url) ~= "string" or opts.url == "" then
    return nil, { engine_refused = true, request_sent = false,
                  error_code = 1002, error_msg = "no url" }
  end

  local spec = {
    url               = opts.url,
    method            = opts.method or "POST",
    headers           = opts.headers or {},
    connect_timeout_s = opts.connect_timeout_s or 10,
    total_timeout_s   = opts.total_timeout_s or 600,
    sse               = opts.sse and true or false,
    consumer          = "reaassist",
  }
  if opts.allow_insecure then spec.allow_insecure = true end
  if opts.ssl_revoke_best_effort then spec.ssl_revoke_best_effort = true end
  if opts.tee_file then spec.tee_file = opts.tee_file end
  if opts.max_response_bytes then spec.max_response_bytes = opts.max_response_bytes end

  if type(RA) ~= "table" or type(RA.JSON) ~= "table"
     or type(RA.JSON.encode) ~= "function" then
    return nil, { engine_refused = true, request_sent = false,
                  error_code = 0, error_msg = "RA.JSON unavailable" }
  end

  local spec_json = RA.JSON.encode(spec)
  local req_id = reaper.MBH_HttpStart(spec_json, opts.body or "")
  if type(req_id) ~= "number" or req_id <= 0 then
    -- The reason for a refusal is read back through handle 0.
    local _, doc = reaper.MBH_HttpStatus(0)
    local st = decode_status(doc)
    return nil, {
      engine_refused = true,
      request_sent   = st.request_sent == true,
      error_code     = st.error_code or 1002,
      error_msg      = st.error_msg or "engine refused the request",
    }
  end

  return {
    id       = req_id,
    sse      = spec.sse,
    started  = true,
    closed   = false,
  }
end

-- Current status as a table.
function Engine.poll(handle)
  if type(handle) ~= "table" or handle.closed then
    return { state = "unknown", request_sent = true, error_code = 1099,
             error_msg = "handle closed" }
  end
  local _, doc = reaper.MBH_HttpStatus(handle.id)
  return decode_status(doc)
end

-- Read one unit of data: one decoded event in SSE mode, or a chunk of bytes in
-- raw mode. Returns nil when nothing is available.
--
-- In SSE mode an empty payload is a real event, so callers must drive this from
-- the status document's events_pending rather than from emptiness. Engine.drain
-- below does that correctly and is what callers should normally use.
function Engine.read(handle)
  if type(handle) ~= "table" or handle.closed then return nil end
  local ok, chunk = reaper.MBH_HttpRead(handle.id, Engine.READ_BUFFER)
  if not ok and (chunk == nil or chunk == "") then return nil end
  return chunk or ""
end

-- Drain everything currently available.
--
-- Returns an array. In SSE mode it contains whole event payloads, read strictly
-- while events_pending is nonzero, which is the only way to distinguish a
-- delivered empty event from nothing pending. In raw mode it contains byte
-- chunks.
function Engine.drain(handle, status)
  local out = {}
  if type(handle) ~= "table" or handle.closed then return out end

  if handle.sse then
    -- events_pending is read once per batch rather than once per event. The
    -- count only grows between polls (the network thread adds, this thread
    -- removes), so consuming exactly the number that was known and then
    -- re-polling is both correct and conservative. Polling after every single
    -- event would put a JSON decode of the status document on the hot path for
    -- every token the model produces.
    local st = status or Engine.poll(handle)
    local pending = tonumber(st.events_pending) or 0
    local guard = 0
    while pending > 0 do
      local ok, ev = reaper.MBH_HttpRead(handle.id, Engine.READ_BUFFER)
      -- An empty payload is a legitimate event, and the engine reports success
      -- for it, so emptiness alone never ends the drain. Only a failed read
      -- does, which at this point means the engine and the count disagree.
      if not ok and (ev == nil or ev == "") then break end
      out[#out + 1] = ev or ""
      pending = pending - 1

      -- Bounded per call. A defer tick has a budget, and an engine that somehow
      -- reported a count it could not satisfy must not be able to spin here.
      -- Whatever is left is simply read on the next tick.
      guard = guard + 1
      if guard >= 512 then break end

      if pending == 0 then
        st = Engine.poll(handle)
        pending = tonumber(st.events_pending) or 0
      end
    end
  else
    while true do
      local ok, chunk = reaper.MBH_HttpRead(handle.id, Engine.READ_BUFFER)
      if not ok or chunk == nil or chunk == "" then break end
      out[#out + 1] = chunk
    end
  end
  return out
end

function Engine.cancel(handle)
  if type(handle) ~= "table" or handle.closed then return false end
  return reaper.MBH_HttpCancel(handle.id) and true or false
end

function Engine.close(handle)
  if type(handle) ~= "table" or handle.closed then return end
  handle.closed = true
  reaper.MBH_HttpClose(handle.id)
end

-- Whether a failed request may be retried automatically on the curl lane.
--
-- The boundary is request transmission, not first response byte: a provider can
-- receive, process, and bill a request that never sends a byte back. So only an
-- explicit false permits a replay, and a missing or unreadable value counts as
-- sent. Unknown never auto-replays.
function Engine.may_fall_back(status_or_failure)
  if type(status_or_failure) ~= "table" then return false end
  return status_or_failure.request_sent == false
end

-- Decide what the application may do after an engine request fails.
--
-- Returns a table with:
--   fallback_allowed  true only when transmission is explicitly false and no
--                     response payload has reached Lua
--   pin_to_curl       true when the status suggests an engine or seam defect
--   request_sent      conservative transmission result; unknown is true
--   contradiction     true when payload arrived while request_sent says false
--
-- This is deliberately pure so the no-replay guard can be tested without
-- REAPER. The application owns the effects: closing the handle, recording the
-- diagnostic event, launching curl when permitted, or surfacing the failure.
function Engine.failure_policy(status_or_failure, had_payload)
  local status = type(status_or_failure) == "table"
    and status_or_failure or {}
  local reported_not_sent = status.request_sent == false
  local contradiction = had_payload == true and reported_not_sent
  local request_sent = not reported_not_sent
  if contradiction then request_sent = true end
  local code = tonumber(status.error_code) or 0
  local curl_code = tonumber(status.curl_code) or 0
  local state = tostring(status.state or (code > 0 and "error" or "unknown"))

  local engine_fault = state == "unknown"
    or code == Engine.ERROR.REFUSED_BAD_SPEC
    or code == Engine.ERROR.REFUSED_SHUTTING_DOWN
    or code == Engine.ERROR.REFUSED_BAD_BODY
    or code == Engine.ERROR.REFUSED_NUL_IN_PAYLOAD
    or code == Engine.ERROR.RESPONSE_TOO_LARGE
    or code == Engine.ERROR.SSE_EVENT_TOO_LARGE
    or code == Engine.ERROR.SSE_MALFORMED
    or code == Engine.ERROR.GLOBAL_BUDGET_EXHAUSTED
    or (code == Engine.ERROR.GENERIC_TRANSPORT and curl_code == 0)

  if contradiction then engine_fault = true end

  return {
    fallback_allowed = not request_sent and had_payload ~= true,
    pin_to_curl = engine_fault,
    request_sent = request_sent,
    contradiction = contradiction,
  }
end

-- ============================================================================
-- Streaming adapters
-- ============================================================================
-- Everything below is provider knowledge. The engine has none of it.
--
-- `shape` is one of "anthropic", "openai", "gemini". Custom providers advertise
-- their shape through their configured API style and fall back to non-streaming
-- when it is unknown, which is always a supported mode.

Engine.shapes = {}

-- ----------------------------------------------------------------------------
-- Request shaping
-- ----------------------------------------------------------------------------

-- Turn a non-streaming request body table into a streaming one. Returns the
-- same table, mutated, so callers can chain.
function Engine.stream_body(shape, body, opts)
  if type(body) ~= "table" then return body end
  if shape == "anthropic" then
    body.stream = true
  elseif shape == "openai" then
    body.stream = true
    -- OpenAI-compatible providers may send usage in a final empty-choice
    -- event. Request it explicitly so existing cost and token accounting sees
    -- the same fields it receives from the settled response lane.
    if not opts or opts.include_usage ~= false then
      body.stream_options = type(body.stream_options) == "table"
        and body.stream_options or {}
      body.stream_options.include_usage = true
    end
  end
  -- Gemini signals streaming through the endpoint, not the body.
  return body
end

-- Turn a non-streaming endpoint into a streaming one.
--
-- Only Gemini needs this: it swaps `:generateContent` for
-- `:streamGenerateContent?alt=sse`. Without `alt=sse` the response is a JSON
-- array delivered in pieces, which is a different parsing problem entirely.
function Engine.stream_endpoint(shape, endpoint)
  if shape ~= "gemini" or type(endpoint) ~= "string" then return endpoint end
  if endpoint:find("streamGenerateContent", 1, true) then return endpoint end
  local swapped = endpoint:gsub(":generateContent", ":streamGenerateContent")
  if swapped:find("?", 1, true) then
    return swapped .. "&alt=sse"
  end
  return swapped .. "?alt=sse"
end

-- True when this shape can stream at all.
function Engine.shape_supports_streaming(shape)
  return shape == "anthropic" or shape == "openai" or shape == "gemini"
end

-- ----------------------------------------------------------------------------
-- The accumulator
-- ----------------------------------------------------------------------------
-- Consumes decoded SSE payloads and assembles a response document shaped
-- exactly like the non-streaming one for the same provider.
--
-- This is the piece that keeps streaming from rippling through the rest of the
-- application. Downstream, nothing knows a stream happened.

local Accumulator = {}
Accumulator.__index = Accumulator

local function json_decode(s)
  if type(RA) ~= "table" or type(RA.JSON) ~= "table"
     or type(RA.JSON.decode) ~= "function" then
    return nil
  end
  local ok, v = pcall(RA.JSON.decode, s)
  if ok then return v end
  return nil
end

-- JSON null, and why it gets its own machinery.
--
-- The host decoder does not turn null into Lua nil. It returns a shared
-- sentinel TABLE, deliberately, so that {"key":null} does not vanish on decode
-- the way `obj[key] = nil` would. Correct for the host, and quietly lethal
-- here: every `type(x) == "table"` guard below accepts the sentinel, and every
-- "present but the wrong type" rule FIRES on it. Providers send null constantly.
-- A real OpenAI stream carries "finish_reason":null on every interim chunk, plus
-- "usage":null and "logprobs":null; Anthropic's message_start carries
-- "stop_reason":null and null usage fields. Left alone, the string-only finish
-- rule would count each of those as a lost piece of the answer and refuse every
-- valid stream in production as incomplete.
--
-- So null is normalised to absent, once, at the single point where events
-- enter, rather than tested for at each of the forty-odd guards below. After
-- the walk every existing `~= nil` presence check is already correct, and
-- absent is routine everywhere it should be.
--
-- Two details the code cannot show:
--
--   Sentinels at positive integer keys are LEFT IN PLACE. Removing them would
--   punch a hole in an array and ipairs would stop at it, turning "one null
--   element" into "the rest of the answer is missing". As elements they behave
--   as empty objects, which every per-element guard already tolerates.
--
--   EMPTY_ARRAY, the host's other sentinel, is not handled because the decoder
--   never produces one. It exists so the encoder can write [] for a table that
--   would otherwise render as {}, and it only ever travels outward.
--
-- The sentinel is resolved lazily rather than captured at load, because the
-- host attaches RA.JSON after its own decoder is fully built and this module
-- makes no assumption about which of the two loads first. A host whose decoder
-- returns Lua nil for null leaves it unresolved and the walk is a no-op, which
-- is exactly right for that host.
local JSON_NULL = nil

-- Mirrors the engine's own kJsonMaxDepth. A document deeper than this is not
-- one any provider sends, and the cap keeps a hostile payload from recursing
-- without bound.
local JSON_STRIP_MAX_DEPTH = 32

local function strip_json_nulls(t, depth)
  if depth > JSON_STRIP_MAX_DEPTH then return t end
  local drop = nil
  for k, v in pairs(t) do
    if v == JSON_NULL then
      -- Positive integer keys are array positions; see above.
      if not (type(k) == "number" and k > 0 and k == math.floor(k)) then
        drop = drop or {}
        drop[#drop + 1] = k
      end
    elseif type(v) == "table" then
      strip_json_nulls(v, depth + 1)
    end
  end
  if drop then
    for i = 1, #drop do t[drop[i]] = nil end
  end
  return t
end

function Engine.new_accumulator(shape)
  return setmetatable({
    shape       = shape,
    blocks      = {},     -- anthropic: content blocks by index
    text        = {},     -- openai / gemini: text pieces in order
    tool_calls  = {},     -- openai: by index
    envelope    = nil,    -- anthropic: the message object from message_start
    finish      = nil,
    usage       = nil,
    saw_done    = false,
    error       = nil,
    delta_count = 0,
    -- Events that arrived but could not be used: a payload that was not valid
    -- JSON, an index outside the representable range, tool-input fragments that
    -- did not reassemble. Any of these means part of the answer is missing, so
    -- the turn must not be accepted as complete even if the provider later
    -- signals a normal finish.
    dropped_events = 0,
    -- Highest index actually seen, so assembly walks exactly what arrived.
    -- Both of these are sparse maps keyed by a provider-chosen index, and Lua's
    -- length operator is undefined on a sparse table, so a scanned range is
    -- needed. Scanning a fixed range instead would be a silent truncation
    -- ceiling: a turn with more blocks than the guess would lose its tail with
    -- no error anywhere.
    max_block_index = -1,
    max_tool_index  = -1,
  }, Accumulator)
end

-- Feed one decoded SSE payload.
--
-- Returns delta_text, done, err:
--   delta_text  new visible text produced by this event, or nil
--   done        true once the provider has signalled the end of the turn
--   err         a provider-reported error, if the stream carried one
--
-- A payload that does not parse is ignored rather than fatal. Providers emit
-- keep-alives and event types that postdate this code, and failing a turn
-- because of an unrecognised event would be brittle in exactly the way a
-- transport layer must not be.
function Accumulator:consume(payload)
  if type(payload) ~= "string" then return nil, false, nil end

  -- OpenAI's end-of-stream sentinel is not JSON.
  if self.shape == "openai" and payload == "[DONE]" then
    self.saw_done = true
    return nil, true, nil
  end
  if payload == "" then return nil, false, nil end

  local ev = json_decode(payload)
  if type(ev) ~= "table" then
    -- A nonempty payload that will not decode is a piece of the answer that has
    -- gone missing. Ignoring it quietly was the original behavior and it was
    -- wrong: a damaged delta would vanish, the provider's finish event would
    -- still arrive, and the turn would be accepted as a complete answer that
    -- was quietly short. Counted here so the turn fails instead.
    self.dropped_events = self.dropped_events + 1
    return nil, false, nil
  end

  if JSON_NULL == nil and type(RA) == "table" and type(RA.JSON) == "table" then
    JSON_NULL = RA.JSON.NULL
  end
  if JSON_NULL ~= nil then
    if ev == JSON_NULL then
      -- The whole payload was the literal `null`. Absent is routine, and the
      -- sentinel is shared host-wide, so it must never be handed to an adapter
      -- that could write into it.
      return nil, false, nil
    end
    strip_json_nulls(ev, 1)
  end

  if self.shape == "anthropic" then
    return self:_consume_anthropic(ev)
  elseif self.shape == "openai" then
    return self:_consume_openai(ev)
  elseif self.shape == "gemini" then
    return self:_consume_gemini(ev)
  end
  return nil, false, nil
end

-- --- Anthropic --------------------------------------------------------------
-- Content is modelled as blocks by index, exactly as the non-streaming
-- response presents them, so a turn containing thinking and text (or a tool
-- use) reassembles into the same structure rather than a flattened string.
function Accumulator:_consume_anthropic(ev)
  local t = ev.type

  if t == "error" then
    local e = as_object(ev.error)
    self.error = (e and type(e.message) == "string" and e.message)
                 or "provider stream error"
    self.error_event = ev
    return nil, true, self.error
  end

  if t == "message_start" then
    local msg = as_object(ev.message)
    if msg == nil then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    self.envelope = msg
    self.envelope.content = {}
    local usage = as_object(self.envelope.usage)
    if self.envelope.usage ~= nil and usage == nil then
      -- Usage present but malformed. Counted, and cleared from the envelope so
      -- the assembled document does not carry the garbage value onward.
      self.dropped_events = self.dropped_events + 1
      self.envelope.usage = nil
    elseif usage ~= nil and next(usage) ~= nil then
      self.usage = usage
    end
    return nil, false, nil
  end

  if t == "content_block_start" then
    local idx = safe_index(ev.index)
    if idx == nil then
      -- An index this code cannot represent means the response is not one it
      -- understands. Counted as a fault so the turn is not accepted as
      -- complete, rather than dropped silently.
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    local block = as_object(ev.content_block)
    if block == nil then
      -- A recognised event type carrying the wrong shape. This has to be
      -- checked rather than assumed: passing a string to pairs() raises a Lua
      -- error, which inside a defer callback takes the whole stream handler
      -- down. An array in the same slot is the quiet version of the same
      -- mistake. Valid JSON is not the same as a valid event.
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    -- Copy so later mutation cannot alias the event table.
    local copy = {}
    for k, v in pairs(block) do copy[k] = v end
    -- The appendable fields must be strings before the block is admitted. A
    -- block that starts with, say, a table in `text` is not merely odd: the
    -- first text_delta then concatenates onto it and raises, which inside a
    -- defer callback takes the whole stream handler down. The sweep that
    -- closed the single-event crash class missed this because it takes two
    -- events to reach. Malformed here means the block is refused and counted.
    if (copy.text ~= nil and type(copy.text) ~= "string")
        or (copy.thinking ~= nil and type(copy.thinking) ~= "string")
        or (copy.signature ~= nil and type(copy.signature) ~= "string") then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    -- `type` is required, and it is the one field here that absence does not
    -- excuse. Everywhere else a missing field is routine, because a provider
    -- that omits something simply did not have it to send. This one routes: it
    -- is what visible_text matches on, so a block carrying answer text under no
    -- type at all, or under a number, is skipped at assembly while the turn
    -- finishes normally and counts nothing. Present text going nowhere is the
    -- silently short answer this whole module exists to refuse, and real
    -- streams always type the block they are opening, so absent and wrong-typed
    -- are the same fault. That also means an event with no content_block, or an
    -- empty one, is refused: the event exists only to open a typed block.
    --
    -- The rest carry the ordinary rule. `id` and `name` reach the tool-call
    -- path as strings and `input` as a table, so a wrong-typed one would ride
    -- into the assembled document for a later reader to stumble over.
    if type(copy.type) ~= "string"
        or (copy.id ~= nil and type(copy.id) ~= "string")
        or (copy.name ~= nil and type(copy.name) ~= "string")
        or (copy.input ~= nil and as_object(copy.input) == nil) then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    copy.text     = copy.text or (copy.type == "text" and "" or nil)
    copy.thinking = copy.thinking or (copy.type == "thinking" and "" or nil)
    self.blocks[idx] = copy
    if idx > self.max_block_index then self.max_block_index = idx end
    return nil, false, nil
  end

  if t == "content_block_delta" then
    local idx = safe_index(ev.index)
    if idx == nil then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    -- The outer container of a recognised event type has to be validated
    -- before it is dereferenced. `ev.delta` holding a number would make the
    -- `d.type` read below raise "attempt to index a number value", and a Lua
    -- error inside a defer callback takes the whole stream handler down.
    -- Tolerating unknown event TYPES is safe; assuming the shape of a known one
    -- is not.
    local d = as_object(ev.delta)
    if d == nil then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end

    local block = self.blocks[idx]
    if not block then
      -- A delta before its start is malformed, but inventing a text block is a
      -- better outcome than dropping the user's answer on the floor.
      block = { type = "text", text = "" }
      self.blocks[idx] = block
      if idx > self.max_block_index then self.max_block_index = idx end
    end
    self.delta_count = self.delta_count + 1

    -- A recognised delta type whose payload is the wrong shape is a fault, not
    -- something to skip over. The distinction that matters: an UNRECOGNISED
    -- type is routine and tolerated, because providers add them; a recognised
    -- one carrying a non-string where its text belongs means a piece of the
    -- answer went missing, and letting it pass silently would produce a turn
    -- that finishes normally and is quietly short.
    local dt = d.type
    local function malformed()
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end

    if dt == "text_delta" then
      if type(d.text) ~= "string" then return malformed() end
      block.text = (block.text or "") .. d.text
      return d.text, false, nil

    elseif dt == "thinking_delta" then
      if type(d.thinking) ~= "string" then return malformed() end
      block.thinking = (block.thinking or "") .. d.thinking
      -- Thinking is not visible answer text. It can drive the working
      -- indicator; whether it is displayed at all is a product decision this
      -- module does not make.
      return nil, false, nil

    elseif dt == "signature_delta" then
      if type(d.signature) ~= "string" then return malformed() end
      block.signature = (block.signature or "") .. d.signature
      return nil, false, nil

    elseif dt == "input_json_delta" then
      if type(d.partial_json) ~= "string" then return malformed() end
      block.__partial_json = (block.__partial_json or "") .. d.partial_json
      return nil, false, nil
    end

    -- An unrecognised delta type. Tolerated on purpose.
    return nil, false, nil
  end

  if t == "content_block_stop" then
    local idx = safe_index(ev.index)
    if idx == nil then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    local block = self.blocks[idx]
    if block and block.__partial_json then
      -- Tool input arrives as a stream of JSON fragments and is only valid once
      -- the block closes.
      local parsed = json_decode(block.__partial_json)
      -- This is the one decode that does not go through consume, so the null
      -- normalisation has to be repeated on what it produces. Fragments that
      -- reassemble into the bare literal `null` are arguments that are not
      -- there, which is the refusal below rather than a stored sentinel.
      if type(parsed) == "table" and parsed ~= JSON_NULL then
        strip_json_nulls(parsed, 1)
      end
      if parsed == nil or parsed == JSON_NULL or as_object(parsed) == nil then
        -- The fragments did not reassemble into valid JSON. Leaving the block
        -- in place with no input would present a tool call that looks complete
        -- and carries no arguments, which is worse than failing the turn.
        --
        -- A scalar counts here for the same reason it would at block start:
        -- tool input is an object, and fragments that decode to 42 are the same
        -- kind of loss as fragments that decode to nothing. Testing only for
        -- nil let that scalar in through the back door, past the rule the start
        -- event applies to `input`, and an array walks the same path.
        self.dropped_events = self.dropped_events + 1
      else
        block.input = parsed
      end
      block.__partial_json = nil
    end
    return nil, false, nil
  end

  if t == "message_delta" then
    local d = as_object(ev.delta)
    local u = as_object(ev.usage)
    if d == nil or u == nil then
      self.dropped_events = self.dropped_events + 1
      return nil, false, nil
    end
    -- Same rule as every finish signal: only a string may be stored, because
    -- incomplete_reason treats any stored value as "the provider finished".
    if d.stop_reason ~= nil then
      if type(d.stop_reason) == "string" then self.finish = d.stop_reason
      else self.dropped_events = self.dropped_events + 1 end
    end
    if next(u) ~= nil then
      self.usage = self.usage or {}
      for k, v in pairs(u) do self.usage[k] = v end
    end
    return nil, false, nil
  end

  if t == "message_stop" then
    return nil, true, nil
  end

  -- ping and anything newer than this code: ignored on purpose.
  return nil, false, nil
end

-- --- OpenAI-compatible ------------------------------------------------------
function Accumulator:_consume_openai(ev)
  if ev.error ~= nil then
    local e = as_object(ev.error)
    self.error = (e and type(e.message) == "string" and e.message)
                 or "provider stream error"
    self.error_event = ev
    return nil, true, self.error
  end

  -- Built once, from the first chunk that carries it; later chunks repeat these
  -- fields and the envelope is left alone. Each one is admitted only with the
  -- type the assembled document promises, because assemble() returns this table
  -- as the response a non-streaming request would have produced and its readers
  -- treat `id` and `model` as strings. A present field of the wrong type is
  -- counted and left out rather than stored and handed onward as garbage.
  if self.envelope == nil then
    local env_id, env_created, env_model = ev.id, ev.created, ev.model
    if env_id ~= nil and type(env_id) ~= "string" then
      self.dropped_events = self.dropped_events + 1
      env_id = nil
    end
    if env_created ~= nil and type(env_created) ~= "number" then
      self.dropped_events = self.dropped_events + 1
      env_created = nil
    end
    if env_model ~= nil and type(env_model) ~= "string" then
      self.dropped_events = self.dropped_events + 1
      env_model = nil
    end
    self.envelope = {
      id      = env_id,
      object  = "chat.completion",
      created = env_created,
      model   = env_model,
    }
  end
  -- Usage arrives in a trailing chunk when the request asked for it.
  if ev.usage ~= nil then
    local u = as_object(ev.usage)
    if u == nil then self.dropped_events = self.dropped_events + 1
    else self.usage = u end
  end

  if ev.choices == nil then return nil, false, nil end
  local choices = as_array(ev.choices)
  if choices == nil then
    -- Present but not an array: an event that carried answer content this
    -- code cannot reach. Absent is routine (usage-only trailing chunks);
    -- malformed is a fault and must be counted, or a stream that lost its
    -- content would still read as complete. An OBJECT here is the worst of
    -- the shapes, because it does not raise and it does not look wrong: the
    -- loop below simply visits nothing and the turn finishes empty.
    self.dropped_events = self.dropped_events + 1
    return nil, false, nil
  end

  local visible = nil
  for _, ch in ipairs(choices) do
    -- The choice itself, before anything is read out of it. A choices array
    -- holding a bare number would make the `ch.delta` read raise.
    local choice = as_object(ch)
    if choice == nil then
      self.dropped_events = self.dropped_events + 1
      goto next_choice
    end

    local d = as_object(choice.delta)
    if d == nil then
      -- The delta slot filled with something that is not an object.
      self.dropped_events = self.dropped_events + 1
      d = {}
    end
    if d.content ~= nil and type(d.content) ~= "string" then
      -- Present but the wrong type: a piece of the answer that cannot be used.
      self.dropped_events = self.dropped_events + 1
    elseif type(d.content) == "string" and d.content ~= "" then
      self.text[#self.text + 1] = d.content
      self.delta_count = self.delta_count + 1
      visible = (visible or "") .. d.content
    end
    -- Reasoning-style deltas from providers that expose them. Accumulated for
    -- the envelope but never treated as answer text.
    if d.reasoning_content ~= nil and type(d.reasoning_content) ~= "string" then
      self.dropped_events = self.dropped_events + 1
    elseif type(d.reasoning_content) == "string" and d.reasoning_content ~= "" then
      self.reasoning = (self.reasoning or "") .. d.reasoning_content
    end
    if d.tool_calls ~= nil then
      local calls = as_array(d.tool_calls)
      if calls == nil then
        -- Present but not an array. The round that added per-site checks
        -- counted malformed entries INSIDE the array but let a malformed array
        -- itself pass silently, so a stream that lost its tool calls still
        -- looked complete. Absent is routine; wrong-kinded is always counted.
        self.dropped_events = self.dropped_events + 1
        calls = {}
      end
      for _, entry in ipairs(calls) do
        local tc = as_object(entry)
        if tc == nil then
          -- A tool_calls array holding a bare value. Reading tc.index would
          -- raise.
          self.dropped_events = self.dropped_events + 1
          goto next_tool
        end
        local idx = safe_index(tc.index)
        if idx == nil then
          -- An index this code cannot represent. Counted rather than clamped:
          -- folding it onto some other slot would merge two tool calls into
          -- one, which is a worse outcome than failing the turn.
          self.dropped_events = self.dropped_events + 1
        else
          local slot = self.tool_calls[idx]
          if not slot then
            slot = { type = "function",
                     ["function"] = { name = "", arguments = "" } }
            self.tool_calls[idx] = slot
            if idx > self.max_tool_index then self.max_tool_index = idx end
          end
          -- Identity fields go into the slot only as strings. A wrong-typed id
          -- or type is counted, because a tool call carrying garbage identity
          -- is not one the executor can act on, and storing it as-is would
          -- present exactly that.
          if tc.id ~= nil then
            if type(tc.id) == "string" then slot.id = tc.id
            else self.dropped_events = self.dropped_events + 1 end
          end
          if tc.type ~= nil then
            if type(tc.type) == "string" then slot.type = tc.type
            else self.dropped_events = self.dropped_events + 1 end
          end
          local fn = nil
          if tc["function"] ~= nil then fn = as_object(tc["function"]) end
          if tc["function"] ~= nil and fn == nil then
            -- The function container itself malformed: its name or arguments
            -- are unreachable, which is lost answer data, not noise.
            self.dropped_events = self.dropped_events + 1
          elseif fn ~= nil then
            if fn.name ~= nil and type(fn.name) ~= "string" then
              self.dropped_events = self.dropped_events + 1
            elseif type(fn.name) == "string" then
              slot["function"].name = slot["function"].name .. fn.name
            end
            if fn.arguments ~= nil and type(fn.arguments) ~= "string" then
              self.dropped_events = self.dropped_events + 1
            elseif type(fn.arguments) == "string" then
              slot["function"].arguments = slot["function"].arguments .. fn.arguments
            end
          end
        end
        ::next_tool::
      end
    end
    -- The finish signal is what incomplete_reason keys on, so a wrong-typed
    -- value must not be stored: garbage in `finish` would make a truncated
    -- stream read as finished, which defeats the entire truncation check.
    if choice.finish_reason ~= nil then
      if type(choice.finish_reason) == "string" then self.finish = choice.finish_reason
      else self.dropped_events = self.dropped_events + 1 end
    end

    -- Lua permits a label as the final statement of a block even with locals
    -- declared above it, which is what makes this the idiomatic "continue".
    ::next_choice::
  end

  return visible, false, nil
end

-- --- Gemini -----------------------------------------------------------------
function Accumulator:_consume_gemini(ev)
  if ev.error ~= nil then
    local e = as_object(ev.error)
    self.error = (e and type(e.message) == "string" and e.message)
                 or "provider stream error"
    self.error_event = ev
    return nil, true, self.error
  end
  if ev.usageMetadata ~= nil then
    local u = as_object(ev.usageMetadata)
    if u == nil then self.dropped_events = self.dropped_events + 1
    else self.usage = u end
  end
  if ev.modelVersion ~= nil then
    if type(ev.modelVersion) == "string" then self.model_version = ev.modelVersion
    else self.dropped_events = self.dropped_events + 1 end
  end

  if ev.candidates == nil then return nil, false, nil end
  local cands = as_array(ev.candidates)
  if cands == nil then
    self.dropped_events = self.dropped_events + 1
    return nil, false, nil
  end

  local visible = nil
  for _, entry in ipairs(cands) do
    local c = as_object(entry)
    if c == nil then
      -- A candidates array holding a bare value; reading c.content would raise.
      self.dropped_events = self.dropped_events + 1
      goto next_candidate
    end

    local content = as_object(c.content)
    local parts = nil
    if content ~= nil and content.parts ~= nil then
      parts = as_array(content.parts)
    end
    if content == nil then
      self.dropped_events = self.dropped_events + 1
    elseif content.parts ~= nil and parts == nil then
      -- The parts container itself malformed. Everything the candidate said is
      -- unreachable behind it, so this must be counted: skipping it silently
      -- while still recording the finishReason below produced a stream that
      -- lost its entire answer and read as complete.
      self.dropped_events = self.dropped_events + 1
    elseif parts ~= nil then
      for _, raw_part in ipairs(parts) do
        local part = as_object(raw_part)
        if part == nil then
          -- A parts array holding a bare value.
          self.dropped_events = self.dropped_events + 1
        elseif part.thought == true then
          -- Summary faults are display-only faults. Ignore a malformed summary
          -- value so a separate valid answer can still complete the turn.
          if type(part.text) == "string" and part.text ~= "" then
            self.reasoning = (self.reasoning or "") .. part.text
          end
        elseif part.thought ~= nil and type(part.thought) ~= "boolean" then
          -- An ambiguous marker is treated as private and ignored. Guessing it
          -- is answer text could expose provider reasoning.
        elseif part.text ~= nil and type(part.text) ~= "string" then
          -- Present but the wrong type on an answer part is lost answer data.
          self.dropped_events = self.dropped_events + 1
        elseif type(part.text) == "string" and part.text ~= "" then
            self.text[#self.text + 1] = part.text
            self.delta_count = self.delta_count + 1
            visible = (visible or "") .. part.text
        end
      end
      if content.role ~= nil then
        if type(content.role) == "string" then self.role = content.role
        else self.dropped_events = self.dropped_events + 1 end
      end
    end
    -- Finish signals are string-only everywhere; see the OpenAI adapter for
    -- why storing anything else defeats the truncation check.
    if c.finishReason ~= nil then
      if type(c.finishReason) == "string" then self.finish = c.finishReason
      else self.dropped_events = self.dropped_events + 1 end
    end

    ::next_candidate::
  end

  -- Gemini has no separate end-of-stream sentinel. A string finishReason in
  -- the final candidate is its provider completion signal.
  return visible, self.finish ~= nil, nil
end

-- ----------------------------------------------------------------------------
-- Assembly
-- ----------------------------------------------------------------------------

-- The visible answer text accumulated so far. Used for the in-flight bubble
-- and nothing else: validation and execution see only the assembled envelope.
function Accumulator:visible_text()
  if self.shape == "anthropic" then
    -- Text blocks in index order. Gaps are skipped rather than treated as the
    -- end, because a turn can legitimately open a thinking block at index 0 and
    -- a text block at index 1, and stopping at the first non-text block would
    -- silently drop the answer.
    local parts = {}
    for idx = 0, self.max_block_index do
      local b = self.blocks[idx]
      if b and b.type == "text" and type(b.text) == "string" then
        parts[#parts + 1] = b.text
      end
    end
    return table.concat(parts)
  end
  return table.concat(self.text)
end

-- Build the response document a non-streaming request would have produced.
--
-- Returned as a Lua table. The caller encodes it and writes it wherever the
-- legacy response artifact goes, so Log.response and the diagnostics slicing
-- keep working unchanged.
function Accumulator:assemble()
  if type(self.error_event) == "table" then
    return self.error_event
  end
  if self.shape == "anthropic" then
    local msg = self.envelope or { type = "message", role = "assistant" }
    local content = {}
    for idx = 0, self.max_block_index do
      local b = self.blocks[idx]
      if b then
        b.__partial_json = nil
        content[#content + 1] = b
      end
    end
    msg.content = content
    if self.finish then msg.stop_reason = self.finish end
    if self.usage then msg.usage = self.usage end
    return msg

  elseif self.shape == "openai" then
    local message = { role = "assistant", content = table.concat(self.text) }
    if self.reasoning then message.reasoning_content = self.reasoning end
    local calls = {}
    for i = 0, self.max_tool_index do
      if self.tool_calls[i] then calls[#calls + 1] = self.tool_calls[i] end
    end
    if #calls > 0 then message.tool_calls = calls end

    local env = self.envelope or {}
    env.object  = "chat.completion"
    env.choices = { {
      index         = 0,
      message       = message,
      finish_reason = self.finish,
    } }
    if self.usage then env.usage = self.usage end
    return env

  elseif self.shape == "gemini" then
    local parts = {}
    if self.reasoning and self.reasoning ~= "" then
      parts[#parts + 1] = { thought = true, text = self.reasoning }
    end
    local answer = table.concat(self.text)
    if answer ~= "" then parts[#parts + 1] = { text = answer } end
    local cand = {
      content = { parts = parts, role = self.role or "model" },
      index   = 0,
    }
    if self.finish then cand.finishReason = self.finish end
    local env = { candidates = { cand } }
    if self.usage then env.usageMetadata = self.usage end
    if self.model_version then env.modelVersion = self.model_version end
    return env
  end

  return {}
end

-- Why this turn must not be accepted as a complete answer, or nil if it may be.
--
-- Two distinct faults, one remedy. A stream that ended without a finish signal
-- was cut off. A stream that finished normally but lost pieces along the way
-- (a payload that would not decode, an index outside the representable range,
-- tool-input fragments that did not reassemble) is quietly short.
--
-- The second is the more dangerous of the two, because everything about it
-- looks healthy: the provider said it finished, the text is well-formed, and
-- nothing raised an error. It just isn't all there. Both map to the existing
-- closed-early transport error, because a short answer presented as a whole one
-- is something the user would act on.
--
-- Returns "truncated", "dropped_events", or nil.
function Accumulator:incomplete_reason()
  -- A provider that reported its own error has already produced a user-visible
  -- failure through a different path; it is not additionally "incomplete".
  if self.error then return nil end
  if (self.dropped_events or 0) > 0 then return "dropped_events" end
  if self.finish == nil and not self.saw_done then return "truncated" end
  return nil
end

-- True when the turn must not be accepted, for either reason.
--
-- Callers should use this rather than testing the reason, so that a fault class
-- added later is handled without every call site needing to learn about it.
function Accumulator:was_truncated()
  return self:incomplete_reason() ~= nil
end

-- How many events arrived and could not be used. Diagnostic only; the decision
-- to reject belongs to was_truncated.
function Accumulator:dropped_count()
  return self.dropped_events or 0
end

return Engine
-- END ENGINE COMPONENT Client
end)()

EngineKit.Client.Kit = EngineKit
return EngineKit.Client
