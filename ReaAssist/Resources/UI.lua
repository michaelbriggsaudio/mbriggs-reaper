-- =============================================================================
-- UI.lua -- UI subsystem (Render namespace)
-- =============================================================================
-- This file is dofile()'d from ReaAssist.lua during startup. It populates
-- the global `Render` table (declared in ReaAssist.lua as `Render = {}`)
-- with every screen rendering function:
--
--   Render.tos_screen, Render.help_screen, Render.bug_report_screen,
--   Render.credits_screen, Render._factory_reset_execute,
--   Render._factory_reset_popup, Render._key_test_results_popup,
--   Render._key_validation_error_popup, Render.first_run_screen,
--   Render.settings_screen, Render._shared_key_screen_impl,
--   Render.custom_providers_screen, Render.custom_llm_screen,
--   Render.preferred_plugins_screen, Render.fx_cache_screen
--
-- Splitting the UI off gives ReaAssist.lua headroom on Lua 5.4's 200-local
-- limit per chunk. Both halves share state through plain globals and the
-- RA table. Cross-file reads in the UI file target:
--   RA.*       : ctx, SC, SEP, RESOURCES_DIR, bold_font, code_font,
--                IS_WINDOWS, IS_MACOS, FX_CACHE_PATH, sel_cb
--   namespaces : CFG, S, prefs, Log, Net, MODELS, PROVIDERS, api_keys,
--                Custom, TK, COL, UI, Theme, FONT, ICON, Attach, Code,
--                CTX, update, pref_plugins, fx_cache_ui, FXCache,
--                deep_scan, Key, Diag, PALETTES, Attribution
--   helpers    : apply_palette, resolve_theme, label_to_type_key,
--                pref_plugins_best_match, pref_plugins_rank_matches
--   constants  : PREF_PLUGIN_DEFAULTS, CUSTOM_DEFAULT_CTX,
--                CUSTOM_DEFAULT_TIMEOUT, CUSTOM_MIN_TIMEOUT,
--                CUSTOM_MAX_TIMEOUT, CUSTOM_MIN_CTX,
--                CUSTOM_DEFAULT_TEST_TIMEOUT, CUSTOM_CONN_TEST_ID
--
-- Performance aliases below mirror the ones in ReaAssist.lua. Each Lua
-- chunk has its own upvalue table, so file-scope aliases cannot cross
-- the dofile boundary and must be redeclared here.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Direct-run guard
-- ---------------------------------------------------------------------------
-- UI.lua is a fragment of ReaAssist that depends on globals (RA, CFG, S,
-- prefs, Render, etc.) set up by ReaAssist.lua. Running it on its own from
-- REAPER's action list or a Lua CLI yields cryptic "attempt to index a nil
-- value" errors. Detect that case via the RA sentinel and bail with a
-- friendly message instead.
if type(RA) ~= "table" then
  local msg = "Resources/UI.lua is part of ReaAssist and cannot be run "
           .. "directly.\n\nPlease run ReaAssist.lua in the parent folder "
           .. "instead."
  if type(reaper) == "table" and reaper.MB then
    reaper.MB(msg, "ReaAssist", 0)
  else
    print(msg)
  end
  return
end

-- ---------------------------------------------------------------------------
-- Performance aliases (ImGui hot-path + stdlib functions used by screens)
-- ---------------------------------------------------------------------------
local ImGui        = reaper

-- Standard library
local str_format   = string.format
local str_find     = string.find
local str_sub      = string.sub
local str_match    = string.match

-- Forward declaration for the file-private markdown-table parser. Its
-- sole caller (UI.selectable_text) runs before the definition point
-- down below, so declare-now / define-later keeps the parser off the
-- public UI.* namespace.
local parse_md_table

-- Pure helpers hoisted to file scope so the per-message render loop
-- does not re-create them every frame. fmt_num prints integers with
-- thousands separators (details card); _shift_col adjusts a u32 color
-- channel with clamping (code-block gradient bands).
local function fmt_num(n)
  local s = tostring(math.floor(n))
  local out, count = "", 0
  for k = #s, 1, -1 do
    out = s:sub(k, k) .. out
    count = count + 1
    if count % 3 == 0 and k > 1 then out = "," .. out end
  end
  return out
end
local function _shift_col(col, d)
  local r = math.max(0, math.min(255, ((col >> 24) & 0xFF) + d))
  local g = math.max(0, math.min(255, ((col >> 16) & 0xFF) + d))
  local b = math.max(0, math.min(255, ((col >> 8)  & 0xFF) + d))
  return (r << 24) | (g << 16) | (b << 8) | (col & 0xFF)
end
local tbl_concat   = table.concat
local tbl_remove   = table.remove
local math_floor   = math.floor
local math_min     = math.min
local math_max     = math.max
local math_abs     = math.abs
local time_precise = reaper.time_precise

-- Wordmark letters hoisted out of the per-frame draw loop in
-- UI.hero_band_v5 / UI.hero_band_settings_v5. The literal `{"A","s","s",
-- "i","s","t"}` was being allocated every frame on the home / settings
-- screens.
local _ASSIST_LETTERS = { "A", "s", "s", "i", "s", "t" }

-- Details-card lookup tables hoisted to file scope. Previously these
-- three table literals (10 + 9 + 9 entries) were re-allocated every
-- frame inside the per-message render loop, once per visible bubble
-- with show_details on. With several visible bubbles, that's ~30 small
-- table allocs per frame for entirely invariant data.
local _DETAILS_GROUP_OF = {
  ["Model"]      = "decision",
  ["Context"]    = "context",
  ["FX Cache"]   = "context",
  ["Tokens"]     = "usage",
  ["Cache"]      = "usage",
  ["API Calls"]  = "usage",
  ["Time"]       = "cost",   -- grouped with Est. Cost so the "bill" sits together
  ["Thinking"]   = "reasoning",
  ["Est. Cost"]  = "cost",
  ["Est. Total"] = "cost",
}
local _DETAILS_ROW_ORDER = {
  "Model", "Complexity",
  "Context", "FX Cache",
  "Tokens", "Cache", "API Calls", "Time",
  "Thinking",
  "Est. Cost", "Est. Total",
}
local _DETAILS_FIELD_TOOLTIPS = {
  ["Context"]    = "Which source material was bundled with your prompt. 'Session' = live state of your REAPER session (tracks, items, FX, markers, etc.). 'API' = the REAPER/ReaScript API reference. 'fx:<plugin>' = per-plugin parameter reference. 'plugin_ref:<plugin>' = general plugin documentation.",
  ["Model"]      = "Which model produced this response.",
  ["Est. Cost"]  = "Estimated cost for this exchange based on the provider's per-token pricing. May differ slightly from what the provider actually bills.",
  ["Est. Total"] = "Running total of estimated cost across every turn in this chat up to and including this one. Hidden on turn 1 since it would just match Est. Cost.",
  ["Tokens"]     = "Input tokens / output tokens used in this exchange. Input covers your prompt plus the bundled context; output is the model's reply.",
  ["Time"]       = "How long the model took to return its response.",
  ["Cache"]      = "Tokens read from the prompt cache / tokens newly written to the cache this turn. Cache reads are billed at a fraction of the normal input-token rate.",
  ["API Calls"]  = "How many round-trips to the model this turn took. 1 means a single clean request. >1 means a silent retry fired (docs auto-fetch, beta-header fallback, cache-expiration refresh, intra-turn context fetch); the Tokens / Cache / Time / Cost values reflect only the LAST request, so when this is >1 the visible numbers undercount the true work for the turn.",
  ["Complexity"] = "Auto-computed complexity score of your prompt (0-10). Higher = a more involved request. The parenthesised label shows which tier Auto mode picked for this turn: Fast (simple prompts), Balanced (mid-range), or Smart (complex work).",
  ["Thinking"]   = "Reasoning effort level used for this response (only relevant for models that support extended thinking).",
  ["FX Cache"]   = "Filter applied to the FX cache this turn (limits which plugins contribute to the Context bundle).",
}

-- ImGui hot-path aliases -- shorter names for the calls used hundreds of
-- times across draw code. Saves file size and avoids repeated table lookups
-- in tight UI loops. Names match upstream with the ImGui_ prefix stripped
-- so the call sites stay self-documenting (PushStyleColor(ctx, ...)).
local PushStyleColor = reaper.ImGui_PushStyleColor
local PopStyleColor  = reaper.ImGui_PopStyleColor
local PushStyleVar   = reaper.ImGui_PushStyleVar
local PushFont       = reaper.ImGui_PushFont
local PopFont        = reaper.ImGui_PopFont
local Text           = reaper.ImGui_Text
local SameLine       = reaper.ImGui_SameLine
local CalcTextSize   = reaper.ImGui_CalcTextSize
local GetCursorPosX  = reaper.ImGui_GetCursorPosX
local SetCursorPosX  = reaper.ImGui_SetCursorPosX
local Dummy          = reaper.ImGui_Dummy

local R = reaper  -- reaper.* call sites in this file (e.g. session_strip_v5)

-- ---------------------------------------------------------------------------
-- CAPABILITY_SECTIONS (welcome-grid capability tiles)
-- ---------------------------------------------------------------------------
-- Static data for the empty-chat welcome grid. Hoisted to file scope so
-- the render loop does not rebuild the nested card table every frame.
-- Shape: { {name=..., cards={ {title, body, prompt}, ... }}, ... }.
local CAPABILITY_SECTIONS = {
  {
    name = "SESSION & AUTOMATION",
    cards = {
      {"Session Awareness",
       "Read your session state to give advice or write custom scripts.",
       "What information do you have about my current REAPER session right now? Give me a brief summary of what you can see (tracks, items, markers, FX, etc.) and explain how you can use this information to help me. Keep your response concise with a few bullet points."},
      {"Editing",
       "Item edits, splits, crossfades, time selections, markers, regions, and more.",
       "What kinds of editing tasks can you help me with in REAPER? Give me a concise overview with specific examples of item editing, splitting, crossfades, time selections, markers, regions, and other editing operations you can perform. Use brief bullet points."},
      {"Track & Project Mgmt",
       "Create tracks, manage folders, configure I/O, and organize your session.",
       "What can you help me with for track and project management in REAPER? Give me a concise overview of the types of tasks you can perform - creating tracks, setting colors, managing folders, routing, I/O configuration, project settings, and session organization. Use brief bullet points."},
      {"Mixing & Effects",
       "Add and configure plugins, adjust levels, set up sends, and build FX chains.",
       "What can you help me with for mixing and effects in REAPER? Give me a concise overview of how you can add and configure plugins, adjust levels, set up sends and routing, and build FX chains. Include a few specific examples of what I could ask you to do. Keep it brief."},
    },
  },
  {
    name = "CUSTOM CODE",
    cards = {
      {"Lua Scripting",
       "Write custom scripts to automate tasks, batch-process tracks, and more.",
       "What kinds of Lua scripts can you write for REAPER? Give me a concise list of practical examples organized by category (batch processing, track management, item manipulation, workflow automation, etc.). Keep it brief with short bullet points."},
      {"JSFX Effect Scripting",
       "Build custom effect plugins on the fly and add them to your tracks.",
       "What kinds of JSFX effects can you create for me? Give me a concise overview of the types of custom audio plugins you can build (EQ, dynamics, delay, utilities, etc.) and explain briefly how the process works - from generating the code to adding it to my tracks. Keep it short."},
    },
  },
  {
    name = "ANSWERS & BOUNDARIES",
    cards = {
      {"General REAPER Q&A",
       "Ask about shortcuts, features, best practices, and workflow tips.",
       "What kinds of REAPER questions can you help me with? Give me a brief overview of the topics you can assist with - shortcuts, features, best practices, workflow tips, recording advice, and production techniques. Include a few example questions I could ask. Keep it concise."},
      {"No Generative Audio",
       "Cannot generate or process audio, music, or other creative content.",
       "Explain briefly what you cannot do: you cannot generate, produce, or process audio, music, or any creative content. Then explain what you can still help with in this area - for example, setting up virtual instruments and samplers, configuring MIDI routing, advising on microphone selection and recording techniques, recommending signal chains, and other production guidance. Keep it concise with bullet points."},
    },
  },
}

-- ---------------------------------------------------------------------------
-- UI rendering helpers
-- ---------------------------------------------------------------------------
-- Pure-UI helpers: ImGui draw code, style-stack push/pop pairs, and
-- composite widgets (hero band, session strip, footer rail, v5 rows,
-- card container). Called from both the Render.* screens in this file
-- and from Render.main_window's chat body.


-- Render the floating toast. Anchor rect (x, y, w, h) is the screen-space
-- bounds of whatever the toast should sit at the bottom of -- in practice,
-- the main ReaAssist window. Called from the main render loop so the toast
-- persists across page navigation while it's still alive.
function UI.render_float_toast(anchor_x, anchor_y, anchor_w, anchor_h)
  local tip = S.float_toast
  if not tip then return end
  local now = reaper.time_precise()
  local alpha
  if now < tip.fade_in_end_at then
    alpha = (now - tip.start_at) / tip.fade_in_s
  elseif tip.sticky then
    alpha = 1.0  -- sticky: hold at full alpha until replaced or cleared
  elseif now < tip.hold_end_at then
    alpha = 1.0
  elseif now < tip.fade_out_end_at then
    alpha = 1 - (now - tip.hold_end_at) / tip.fade_out_s
  else
    S.float_toast = nil
    return
  end
  if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end

  -- Scale the alpha byte of a u32 colour so the bubble fades uniformly.
  local function _scale_alpha(col, a)
    return (col & 0xFFFFFF00) | math_floor((col & 0xFF) * a + 0.5)
  end

  local bottom_margin = RA.SC(36)
  local target_x = anchor_x + anchor_w * 0.5
  local target_y = anchor_y + anchor_h - bottom_margin

  ImGui.ImGui_SetNextWindowPos(RA.ctx, target_x, target_y,
    ImGui.ImGui_Cond_Always(), 0.5, 1.0)
  ImGui.ImGui_SetNextWindowBgAlpha(RA.ctx, alpha)

  local flags = ImGui.ImGui_WindowFlags_NoDecoration()
              | ImGui.ImGui_WindowFlags_NoInputs()
              | ImGui.ImGui_WindowFlags_NoMove()
              | ImGui.ImGui_WindowFlags_AlwaysAutoResize()
              | ImGui.ImGui_WindowFlags_NoSavedSettings()
              | ImGui.ImGui_WindowFlags_NoFocusOnAppearing()
              | ImGui.ImGui_WindowFlags_NoNav()

  PushStyleColor(RA.ctx, ImGui.ImGui_Col_WindowBg(),
    _scale_alpha(TK.card, 1.0))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),
    _scale_alpha(TK.border, alpha))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(14), RA.SC(9))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowRounding(), RA.SC(10))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowBorderSize(), 1)
  if ImGui.ImGui_Begin(RA.ctx, "##reaassist_float_toast", nil, flags) then
    local accent_col = (tip.kind == "err") and TK.red or TK.green
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), _scale_alpha(accent_col, alpha))
    Text(RA.ctx, tip.text)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end
  ImGui.ImGui_End(RA.ctx)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopStyleColor(RA.ctx, 2)
end


-- Draw a unified highlight border around the whole window when a file
-- is being dragged over any drop target. Called once per frame at the end.
function UI.draw_drop_overlay()
  if not S.drop_active then return end
  local draw = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local wx, wy = ImGui.ImGui_GetWindowPos(RA.ctx)
  local ww, wh = ImGui.ImGui_GetWindowSize(RA.ctx)
  -- Filled tint over the whole window.
  ImGui.ImGui_DrawList_AddRectFilled(draw, wx, wy, wx + ww, wy + wh, 0xFFFF0018)
  -- Yellow border.
  ImGui.ImGui_DrawList_AddRect(draw, wx + 1, wy + 1, wx + ww - 1, wy + wh - 1, 0xFFFF00AA, 0, 0, 2)
  S.drop_active = false
end

-- =============================================================================
-- Styled tooltip: shows a tooltip with dark theme colors when the previous
-- item is hovered. Call immediately after the widget.
-- V5 tooltip: 300ms hover delay, 300ms fade-in on first show, 300ms fade-out
-- when hover leaves. Keeps a single active-tip entry in S._tip so both timers
-- survive across frames. Call `UI.tooltip_v5(text)` immediately after the
-- widget whose hover should trigger it, then call `UI.tooltip_render_v5()`
-- once per frame AFTER every possible tooltip_v5 call -- typically near the
-- end of the main loop so the tooltip paints above all other windows.
UI.TIP_DELAY_S  = 0.3
UI.TIP_FADE_S   = 0.3
function UI.tooltip_v5(text)
  -- AllowWhenDisabled so disabled items (e.g. paid-only models for free-tier
  -- users) still fire their tooltip -- they're often the most important
  -- items to explain, since users want to know WHY they can't click them.
  if ImGui.ImGui_IsItemHovered(RA.ctx,
       ImGui.ImGui_HoveredFlags_AllowWhenDisabled()) then
    local now = time_precise()
    -- If we're hovering a NEW item (different text) OR the previous entry was
    -- already fading out, start fresh -- this prevents a mid-fade tooltip
    -- from being "revived" with its old alpha and a stale anchor.
    if not S._tip or S._tip.text ~= text or S._tip.fade_start then
      local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
      S._tip = {
        text        = text,
        hover_start = now,
        fade_start  = nil,
        anchor_x    = mx + RA.SC(14),
        anchor_y    = my + RA.SC(18),
      }
    else
      -- Track cursor while still hovering so the tooltip follows the mouse.
      local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
      S._tip.anchor_x = mx + RA.SC(14)
      S._tip.anchor_y = my + RA.SC(18)
    end
    S._tip_hovered_this_frame = true
  end
end

function UI.tooltip_render_v5()
  local tip = S._tip
  if not tip then
    S._tip_hovered_this_frame = false
    return
  end
  local now = time_precise()
  local alpha
  if S._tip_hovered_this_frame then
    -- Hover continues: alpha = fade-in curve past the delay window.
    local t = now - tip.hover_start
    if t < UI.TIP_DELAY_S then
      alpha = 0
    else
      alpha = math_min(1.0, (t - UI.TIP_DELAY_S) / UI.TIP_FADE_S)
    end
  else
    -- Not hovered this frame: start (or continue) fade-out.
    tip.fade_start = tip.fade_start or now
    local t = now - tip.fade_start
    alpha = 1.0 - t / UI.TIP_FADE_S
    if alpha <= 0 then
      S._tip = nil
      S._tip_hovered_this_frame = false
      return
    end
  end
  if alpha > 0 then
    ImGui.ImGui_SetNextWindowPos(RA.ctx, tip.anchor_x, tip.anchor_y)
    ImGui.ImGui_SetNextWindowBgAlpha(RA.ctx, alpha)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_Alpha(),              alpha)
    -- Match global tooltip styling (UI.tooltip above): SC(11)/SC(9)
    -- inner padding, SC(5) rounded corners, 1px border.
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),      RA.SC(11), RA.SC(9))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowRounding(),     RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowBorderSize(),   1)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_WindowBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),   TK.border_str)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),     TK.text)
    local flags = ImGui.ImGui_WindowFlags_NoDecoration()
                | ImGui.ImGui_WindowFlags_NoInputs()
                | ImGui.ImGui_WindowFlags_NoMove()
                | ImGui.ImGui_WindowFlags_AlwaysAutoResize()
                | ImGui.ImGui_WindowFlags_NoSavedSettings()
                | ImGui.ImGui_WindowFlags_NoFocusOnAppearing()
                | ImGui.ImGui_WindowFlags_NoNav()
    local visible = ImGui.ImGui_Begin(RA.ctx, "##v5_tooltip", nil, flags)
    if visible then
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      -- Global max width: wrap at SC(500); AlwaysAutoResize then
      -- shrinks the window to the wrapped content width.
      ImGui.ImGui_PushTextWrapPos(RA.ctx, RA.SC(500))
      Text(RA.ctx, tip.text)
      ImGui.ImGui_PopTextWrapPos(RA.ctx)
      PopFont(RA.ctx)
    end
    ImGui.ImGui_End(RA.ctx)
    PopStyleColor(RA.ctx, 3)
    ImGui.ImGui_PopStyleVar(RA.ctx, 4)
  end
  S._tip_hovered_this_frame = false
end

function UI.tooltip(text)
  local hover_flags = ImGui.ImGui_HoveredFlags_DelayNormal()
                    | ImGui.ImGui_HoveredFlags_NoSharedDelay()
  if ImGui.ImGui_IsItemHovered(RA.ctx, hover_flags) then
    -- V5 palette tokens so this standard tooltip matches
    -- UI.tooltip_v5 exactly -- same bg/text/border on every screen
    -- regardless of which tooltip variant fires. Legacy COL.*
    -- values rendered a different tone (blue-ish gray) that read
    -- inconsistent vs the v5 tooltip's TK.card white/dark-navy.
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),    TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border_str)
    -- V5 global tooltip styling: SC(11)/SC(9) inner padding, SC(5)
    -- rounded corners, 1px border, Inter Regular SC(12) font. Push
    -- BOTH WindowRounding and PopupRounding because BeginTooltip's
    -- rounding comes from the Window* variant, not Popup*, in most
    -- ImGui builds; pushing both covers the binding regardless.
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),    RA.SC(11), RA.SC(9))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(),    RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupBorderSize(),  1)
    ImGui.ImGui_BeginTooltip(RA.ctx)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    -- Max tooltip width: wrap long descriptions at SC(500) so the
    -- tooltip window auto-sizes to at most that width instead of
    -- ballooning horizontally to the full message.
    ImGui.ImGui_PushTextWrapPos(RA.ctx, RA.SC(500))
    Text(RA.ctx, text)
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    PopFont(RA.ctx)
    ImGui.ImGui_EndTooltip(RA.ctx)
    ImGui.ImGui_PopStyleVar(RA.ctx, 5)
    PopStyleColor(RA.ctx, 3)
  end
end

-- Draw a subtle focus ring around the last widget if it is active (focused).
-- Uses the draw list to overlay a 1px accent-tinted rectangle so it works
-- regardless of ImGui's built-in border styling.
function UI.focus_ring()
  if ImGui.ImGui_IsItemActive(RA.ctx) then
    local x1, y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
    local x2, y2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
    local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
    ImGui.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, COL.ASSIST, 0, 0, 1.5)
  end
end

-- =============================================================================
-- Right-click context menu for text input fields
-- =============================================================================
-- ImGui's InputText widgets do not ship with a Copy/Paste/Cut popup on
-- right-click. macOS users in particular expect this on every text
-- field (and, over RDP, Cmd+V can be flaky depending on the remote
-- desktop client). Without it there is no obvious way to paste an
-- API key on a fresh install.
--
-- Pattern: call UI.input_with_menu IMMEDIATELY after any
-- ImGui_InputText / ImGui_InputTextWithHint / ImGui_InputTextMultiline
-- call, passing the (changed, new_value) tuple it returned. The helper
-- attaches a right-click popup to that just-rendered item and returns
-- a possibly-augmented tuple: if the user picks Paste, it returns
-- (true, clipboard_text); if Cut, (true, ""); otherwise unchanged.
--
-- Paste replaces the entire field rather than inserting at the cursor.
-- Cursor-aware paste would require an InputText edit-callback to
-- splice the clipboard into the live buffer, which is a much larger
-- change. The native Cmd+V / Ctrl+V paths still work for cursor-aware
-- paste; the right-click menu is the no-keyboard fallback for cases
-- (API keys, custom URLs, names) where the user pastes into an empty
-- or about-to-be-replaced field anyway.
function UI.input_with_menu(ctx, changed, new_value)
  -- Per-frame counter assigns each call site a unique popup ID. Without
  -- this, every InputText shares the same popup ID; when BeginPopup is
  -- called with that shared ID, it returns true for ALL call sites
  -- once the popup is open, and the menu renders one stacked copy per
  -- input on screen (visible on dense pages like Preferred Plugins
  -- where 16 rows x 3 fields = 48 stacked Copy/Paste/Cut popups).
  -- Counter resets at the top of Render.main_window each frame, so the
  -- per-call IDs are stable across frames as long as the iteration
  -- order of input rendering is stable (which it always is in our UI).
  UI._txt_menu_count = (UI._txt_menu_count or 0) + 1
  local popup_id = "##ra_text_ctx_menu_" .. UI._txt_menu_count

  -- IsMouseClicked(ctx, 1) -> right mouse button.
  if ImGui.ImGui_IsItemHovered(ctx)
      and ImGui.ImGui_IsMouseClicked(ctx, 1) then
    ImGui.ImGui_OpenPopup(ctx, popup_id)
  end
  if ImGui.ImGui_BeginPopup(ctx, popup_id) then
    if ImGui.ImGui_MenuItem(ctx, "Copy") then
      ImGui.ImGui_SetClipboardText(ctx, new_value or "")
    end
    if ImGui.ImGui_MenuItem(ctx, "Paste") then
      new_value = ImGui.ImGui_GetClipboardText(ctx) or ""
      changed   = true
    end
    if ImGui.ImGui_MenuItem(ctx, "Cut") then
      ImGui.ImGui_SetClipboardText(ctx, new_value or "")
      new_value = ""
      changed   = true
    end
    ImGui.ImGui_EndPopup(ctx)
  end
  return changed, new_value
end

-- =============================================================================
-- Shared settings-screen UI helpers
-- =============================================================================
-- The five settings-family screens (api_key, advanced, custom_llm,
-- preferred_plugins, fx_cache) all share the same visual language: 5 px
-- FramePadding, 4 px FrameRounding/GrabRounding/PopupRounding, secondary-
-- button palette, 1 px border, centered 20 px page title with an ice-blue
-- accent underline, and -- where applicable -- uppercase letter-spaced
-- section headers with a fading divider. Centralising these below means
-- edits to the visual language propagate to every screen at once.

-- Push the standard settings-screen style stack. Pair with pop_settings_styles.
function UI.push_settings_styles()
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        COL.BTN)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), COL.BTN_HOV)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  COL.BTN_ACT)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        COL.BORDER)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    5, 5)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_GrabRounding(),    RA.SC(4))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(),   RA.SC(4))
end

function UI.pop_settings_styles()
  ImGui.ImGui_PopStyleVar(RA.ctx, 5)    -- FrameBorderSize, FramePadding, FrameRounding, GrabRounding, PopupRounding
  PopStyleColor(RA.ctx, 4)  -- Button, ButtonHovered, ButtonActive, Border
end

-- V5 modal dialog chrome.
--
-- One helper drives every BeginPopupModal in the script: factory reset,
-- clear-cache, key-error, unsaved-settings, advisory, risky-code, etc.
--
-- Visual language (matches Settings / card palette):
--   * PopupBg: blend between TK.card and TK.bg (~35% toward bg). Pure
--     TK.card is blinding white in light mode; a subtle tint softens
--     the modal while keeping it clearly lifted above the page. The
--     blend is theme-aware via UI.lerp_u32.
--   * Title bar = same blended tone (flush). The default ImGui title
--     strip (lighter band above the body) creates visual noise for
--     dialogs that are already small; blending the title bar into the
--     body lets the title read as a centered heading instead of a
--     chrome element. WindowTitleAlign = (0.5, 0.5) centers the title.
--   * Border = TK.border_str (muted grey), not accent -- the modal is
--     a surface, not an action.
--   * Default Button palette is the V5 "secondary" look (card_hover
--     fill, border frame). Primary / destructive buttons opt in via
--     UI.push_modal_primary_btn / UI.push_modal_danger_btn so call
--     sites only push one helper instead of 4 raw style colors.
--   * WindowPadding / FramePadding / rounding tuned to match the
--     Settings pinned bar and the capability-card chrome.
-- Pair with pop_modal_style.
function UI.push_modal_style()
  -- Softened modal surface: TK.card blended 35% toward TK.bg so the
  -- dialog reads as an elevated surface without the pure-white harshness
  -- of TK.card in light mode. Theme-aware via the lerp.
  local modal_bg = UI.lerp_u32(TK.card, TK.bg, 0.35)
  -- PopupBg is used by BeginPopupModal; WindowBg is used by standalone
  -- ImGui.ImGui_Begin dialogs (Update Available, File integrity). We push
  -- both so the same helper works for either container type.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(),          modal_bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_WindowBg(),         modal_bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),             TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TextDisabled(),     TK.text_muted)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),           TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TitleBg(),          modal_bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TitleBgActive(),    modal_bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TitleBgCollapsed(), modal_bg)
  -- Secondary button palette (V5 default): card_hover fill with a
  -- gentle accent tint on hover / active. Keeps Cancel / Skip / Back
  -- buttons reading as neutral surfaces, reserving saturated fills
  -- for primary / danger actions.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),           TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(),  1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),    RA.SC(18), RA.SC(16))
  -- FramePadding tuned to match the V5 Settings pinned bar (compact
  -- vertical, not chunky). SC(12, 5) gives ~24px tall buttons at 100%
  -- DPI, leaving room for title bar + body + button row in popups as
  -- short as SC(130) without clipping.
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),     RA.SC(12), RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),    RA.SC(5))
  -- BeginPopupModal honours WindowRounding; push PopupRounding too as
  -- cheap insurance in case a future ImGui version flips the rule.
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowRounding(),   RA.SC(7))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(),    RA.SC(7))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowTitleAlign(), 0.5, 0.5)
end

function UI.pop_modal_style()
  ImGui.ImGui_PopStyleVar(RA.ctx, 7)   -- FrameBorderSize, WindowPadding, FramePadding, FrameRounding, WindowRounding, PopupRounding, WindowTitleAlign
  PopStyleColor(RA.ctx, 11)            -- PopupBg, WindowBg, Text, TextDisabled, Border, TitleBg, TitleBgActive, TitleBgCollapsed, Button, ButtonHovered, ButtonActive
end

-- Primary modal button (Save / Confirm / Add / OK / Run): accent fill
-- with white text. Four colour pushes paired with pop_modal_primary_btn.
-- Replaces the 4-push-4-pop SEND_BTN boilerplate at every modal call site.
function UI.push_modal_primary_btn()
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(TK.accent, 0x000000FF, 0.15))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
end
function UI.pop_modal_primary_btn() PopStyleColor(RA.ctx, 4) end

-- Destructive modal button (Run Anyway / Clear Cache / Factory Reset /
-- Confirm Clear / Confirm UI Scale down). Softened red: TK.red blended
-- ~25% toward TK.text_muted so the fill reads as serious-but-not-
-- shouting. Still clearly destructive via the red tone; desaturation
-- keeps the saturated TK.red reserved for page-level error states
-- where the extra intensity carries real warning weight.
function UI.push_modal_danger_btn()
  local danger_fill = UI.lerp_u32(TK.red, TK.text_muted, 0.25)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        danger_fill)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(danger_fill, 0xFFFFFFFF, 0.12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(danger_fill, 0x000000FF, 0.15))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          0xFFFFFFFF)
end
function UI.pop_modal_danger_btn() PopStyleColor(RA.ctx, 4) end

-- Card-style popup (provider/model/thinking chip menus): dark card bg,
-- tighter padding, mono font, lifted TextDisabled for readable descriptors.
-- Pair with pop_card_popup_style.
function UI.push_card_popup_style()
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(8),  RA.SC(8))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(10), RA.SC(6))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),   RA.SC(8),  RA.SC(4))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(),      TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),       TK.border_str)
  -- Col_TextDisabled lifted halfway toward text so MenuItem "shortcut" slot
  -- descriptors/$ indicators stay readable on both card bg and accent hover.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TextDisabled(),
    UI.lerp_u32(TK.text_muted, TK.text, 0.5))
  PushFont(RA.ctx, FONT.mono_med, RA.SC(10))  -- matches callers' local MONO_SIZE/ATT_MONO_SIZE
end

function UI.pop_card_popup_style()
  PopFont(RA.ctx)
  PopStyleColor(RA.ctx, 3)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
end

-- Renders the ReaAssist brand logo: "Rea" (normal) + "Assist" (bold),
-- centered, 24 px, ice blue. Matches the TOS screen header exactly so
-- onboarding screens share a consistent brand mark. `inner_w` is the
-- content column width used for horizontal centering.
-- Blend two 0xRRGGBBAA colors linearly by t in [0,1]. Shared helper used
-- by the wordmark gradient band renderer (and reusable elsewhere).
function UI.lerp_u32(a, b, t)
  local ar, ag, ab_, aa = (a >> 24) & 0xFF, (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
  local br, bg, bb_, ba = (b >> 24) & 0xFF, (b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF
  local it = 1 - t
  return ((math_floor(ar*it+br*t) & 0xFF) << 24)
       | ((math_floor(ag*it+bg*t) & 0xFF) << 16)
       | ((math_floor(ab_*it+bb_*t) & 0xFF) << 8)
       |  (math_floor(aa*it+ba*t) & 0xFF)
end

-- V5 home <-> chat transition scalar. phase=0 = home state (tall hero +
-- tagline + capability grid); phase=1 = chat state (compact hero + scrolling
-- message list). The main loop sets `target` each frame from #display_messages
-- and calls tick() to advance `phase` using ImGui's delta time. Renderers
-- read UI.transition.phase (linear) or pass it through UI.transition.ease()
-- for a smoothstep curve. duration_in / duration_out allow asymmetric timing
-- per direction; currently both are 0.35s.
UI.transition = { phase = 0, target = 0, duration_in = 0.35, duration_out = 0.35 }
function UI.transition.tick()
  local t  = UI.transition
  local dt = ImGui.ImGui_GetDeltaTime(RA.ctx) or 0
  if dt > 0.1 then dt = 0.1 end  -- clamp hitches from window drags / pauses
  local dur = (t.target > t.phase) and t.duration_in or t.duration_out
  local step = dt / math_max(dur, 0.016)
  if t.target > t.phase then
    t.phase = math_min(t.target, t.phase + step)
  elseif t.target < t.phase then
    t.phase = math_max(t.target, t.phase - step)
  end
end
-- Smoothstep (3t^2 - 2t^3): symmetric S-curve -- slow at both ends, fastest
-- in the middle. Places the visual midpoint (e.g. crossfade handoff) at the
-- actual time midpoint, so a 350ms transition reads as ~175ms of perceived
-- motion on each side instead of front-loading everything like cubic-out.
function UI.transition.ease(t)
  return t * t * (3 - 2 * t)
end

-- Draws the wordmark with a horizontal ASSIST -> ASSIST_DK gradient so the
-- "R" reads brightest and the trailing "t" slightly darker. Implemented
-- via N vertical clip-rect bands, each pass redrawing all four glyphs in
-- the band's interpolated color. Returns (screen_x, screen_y, width, size)
-- of the wordmark so callers can run visibility checks (mini-logo fade).
function UI.logo(inner_w, title_size)
  local TITLE_SIZE = title_size or RA.SC(24)
  local kern = -2
  PushFont(RA.ctx, nil, TITLE_SIZE)
  local r_w = CalcTextSize(RA.ctx, "R")
  local e_w = CalcTextSize(RA.ctx, "e")
  local a_w = CalcTextSize(RA.ctx, "a")
  PopFont(RA.ctx)
  local rea_w = r_w + kern + e_w + kern + a_w
  PushFont(RA.ctx, RA.bold_font, TITLE_SIZE)
  local assist_tw = CalcTextSize(RA.ctx, "Assist")
  PopFont(RA.ctx)
  local title_tw = rea_w + assist_tw
  local base_x   = GetCursorPosX(RA.ctx)
  local start_x  = base_x + math_max(math_floor((inner_w - title_tw) * 0.5), 0)
  local cur_y    = ImGui.ImGui_GetCursorPosY(RA.ctx)
  ImGui.ImGui_SetCursorPos(RA.ctx, start_x, cur_y)
  local logo_sx0, logo_sy0 = ImGui.ImGui_GetCursorScreenPos(RA.ctx)

  local logo_bright = COL.ASSIST
  local logo_dark   = UI.lerp_u32(0x000000FF, COL.ASSIST, 0.78)

  local function draw_all(col)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col)
    PushFont(RA.ctx, nil, TITLE_SIZE)
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x, cur_y)
    Text(RA.ctx, "R")
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x + r_w + kern, cur_y)
    Text(RA.ctx, "e")
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x + r_w + kern + e_w + kern, cur_y)
    Text(RA.ctx, "a")
    PopFont(RA.ctx)
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x + rea_w, cur_y)
    PushFont(RA.ctx, RA.bold_font, TITLE_SIZE)
    Text(RA.ctx, "Assist")
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
  end

  local N_BANDS = 7
  local clip_y1 = logo_sy0 - RA.SC(4)
  local clip_y2 = logo_sy0 + TITLE_SIZE * 1.30 + RA.SC(20)
  for b = 0, N_BANDS - 1 do
    local bx1 = logo_sx0 + title_tw *  b      / N_BANDS
    local bx2 = (b == N_BANDS - 1)
      and (logo_sx0 + title_tw + RA.SC(4))
      or  (logo_sx0 + title_tw * (b + 1) / N_BANDS)
    local bt  = (b + 0.5) / N_BANDS
    ImGui.ImGui_PushClipRect(RA.ctx, bx1, clip_y1, bx2, clip_y2, false)
    draw_all(UI.lerp_u32(logo_bright, logo_dark, bt))
    ImGui.ImGui_PopClipRect(RA.ctx)
  end

  return logo_sx0, logo_sy0, title_tw, TITLE_SIZE
end

-- V5 Bold Premium hero band. Renders across the full inner window width.
-- Layout: gradient bg (accent_soft -> bg), wordmark "Rea" (Inter Light) +
-- "Assist" (Inter Bold) left-aligned, status chip right-aligned, two-line
-- tagline below (in home state). Accepts a `phase` scalar in [0..1] where
-- 0 = home and 1 = chat; all continuous properties (wordmark size, padding,
-- hero height, tagline alpha, "+ new chat" alpha) interpolate across that
-- range so the home<->chat transition animates smoothly instead of snapping.
-- Returns the total pixel height consumed so the caller can advance the
-- layout cursor.
function UI.hero_band_v5(phase)
  phase = phase or 0
  if phase < 0 then phase = 0 elseif phase > 1 then phase = 1 end
  -- Eased phase drives visual lerps; `eased` thresholds (e.g. "+ new chat"
  -- click-enable at 0.85) replace a discrete compact flag so the transition
  -- stays continuous.
  local eased = UI.transition.ease(phase)

  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local start_x_local = GetCursorPosX(RA.ctx)
  local start_y_local = ImGui.ImGui_GetCursorPosY(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  -- Hero gradient bleeds edge-to-edge on the window (past WindowPadding);
  -- compute the full window rect for the fill while keeping text layout
  -- relative to the content cursor.
  local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
  local win_w        = ImGui.ImGui_GetWindowSize(RA.ctx)
  local full_x1      = win_x
  local full_x2      = win_x + win_w

  -- ReaImGui re-rasterizes via FreeType per PushFont call at the requested
  -- size. Glyph bitmaps still snap to integer pixels, which is why downstream
  -- positions (KERN, letter widths) are smoothed so the wordmark doesn't
  -- pop by a pixel as the rasterizer crosses integer size boundaries.
  local f_wm_l = FONT.inter_light
  local f_wm_b = FONT.inter_bold
  local WM_SIZE_H, WM_SIZE_C = RA.SC(38), RA.SC(24)
  local WM_SIZE   = WM_SIZE_H + (WM_SIZE_C - WM_SIZE_H) * eased
  local TAG_SIZE  = RA.SC(20)
  local CHIP_SIZE = RA.SC(10)

  local PAD_TOP_H, PAD_TOP_C = RA.SC(12), RA.SC(6)
  local PAD_BOT_H, PAD_BOT_C = RA.SC(18), RA.SC(12)
  local PAD_TOP   = PAD_TOP_H + (PAD_TOP_C - PAD_TOP_H) * eased
  local PAD_BOT   = PAD_BOT_H + (PAD_BOT_C - PAD_BOT_H) * eased
  local PAD_X     = RA.SC(24)

  local TAG_LINE_H = math_floor(TAG_SIZE * 1.15 + 0.5)

  -- Single continuous hero-height formula: the tagline block (title + sub-
  -- tagline + gap) collapses proportionally with `eased`, so the hero's
  -- bottom edge slides up smoothly instead of snapping. Tagline render is
  -- gated separately below by its own alpha/skip.
  local TAG_BLOCK_H = RA.SC(8) + TAG_LINE_H * 2
  local hero_h = PAD_TOP + WM_SIZE + TAG_BLOCK_H * (1 - eased) + PAD_BOT

  -- Gradient background + bottom border. The rect extends from the window
  -- edges (bleeding past WindowPadding) so the hero reaches the top and
  -- sides of the content area with no visible TK.bg strip around it.
  ImGui.ImGui_DrawList_AddRectFilledMultiColor(dl,
    full_x1, win_y, full_x2, sy + hero_h,
    TK.accent_soft, TK.accent_soft, TK.bg, TK.bg)
  ImGui.ImGui_DrawList_AddLine(dl,
    full_x1, sy + hero_h - 1, full_x2, sy + hero_h - 1,
    TK.border, 1)

  -- Wordmark (left). "Rea" in Inter Light + "Assist" in Inter Bold, drawn
  -- letter-by-letter for per-glyph gradient and negative kerning (-2..-1 px)
  -- to approximate the spec's tight -1.2 tracking.
  --
  -- KERN lerps between endpoint values (-2 at 38px, -1 at 24px) rather than
  -- being recomputed from WM_SIZE per frame; floor-of-fractional WM_SIZE
  -- would otherwise pop by 1 px mid-animation. Letter widths are measured
  -- once at the reference home size and scaled by wm_scale -- continuous
  -- positions regardless of how CalcTextSize rounds its results.
  local KERN_H = -math_max(1, math_floor(WM_SIZE_H * 0.07))  -- -2 at 38
  local KERN_C = -math_max(1, math_floor(WM_SIZE_C * 0.07))  -- -1 at 24
  local KERN   = KERN_H + (KERN_C - KERN_H) * eased
  local wm_scale = WM_SIZE / WM_SIZE_H
  -- Cache letter widths at the constant WM_SIZE_H. Without this, every
  -- home-screen frame did 2 PushFont/PopFont pairs + 10 CalcTextSize calls
  -- (3 letters at Inter Light, 6 at Inter Bold, plus "Assist" full-string)
  -- to measure invariant data. Cache key is WM_SIZE_H itself so a UI
  -- scale change naturally invalidates (RA.SC produces a different size).
  UI._wm_metrics_h = UI._wm_metrics_h or {}
  local _wm_h = UI._wm_metrics_h[WM_SIZE_H]
  if not _wm_h then
    _wm_h = { letter_w = {} }
    PushFont(RA.ctx, f_wm_l, WM_SIZE_H)
    _wm_h.r_w = CalcTextSize(RA.ctx, "R")
    _wm_h.e_w = CalcTextSize(RA.ctx, "e")
    _wm_h.a_w = CalcTextSize(RA.ctx, "a")
    PopFont(RA.ctx)
    PushFont(RA.ctx, f_wm_b, WM_SIZE_H)
    _wm_h.assist_w = CalcTextSize(RA.ctx, "Assist")
    for i, ltr in ipairs(_ASSIST_LETTERS) do
      _wm_h.letter_w[i] = CalcTextSize(RA.ctx, ltr)
    end
    PopFont(RA.ctx)
    UI._wm_metrics_h[WM_SIZE_H] = _wm_h
  end
  local r_w = _wm_h.r_w * wm_scale
  local e_w = _wm_h.e_w * wm_scale
  local a_w = _wm_h.a_w * wm_scale
  local assist_letters = _ASSIST_LETTERS
  -- Inline `_wm_h.letter_w[i] * wm_scale` at the only consumer
  -- (the draw_letter loop below) so we don't allocate a fresh
  -- assist_widths table every frame.
  local letter_widths = _wm_h.letter_w
  local assist_w = _wm_h.assist_w * wm_scale
  local rea_w = r_w + KERN + e_w + KERN + a_w

  -- Subtle horizontal gradient across the wordmark: leftmost letter sits at
  -- ~25% toward white (noticeably lighter), rightmost letter is pure accent.
  -- Computed per-letter so both "Rea" (Inter Light) and "Assist" (Inter Bold)
  -- share the same ramp rather than splitting on the weight boundary.
  local wm_x = start_x_local + PAD_X
  local GRAD_MAX  = 0.40           -- max blend toward the dark endpoint (leftmost)
  local GRAD_DARK = 0x18264FFF     -- deep navy; mixes with accent toward the left
  local total_w = rea_w + assist_w
  local function letter_color(x_rel_center)
    local t = (1 - x_rel_center / total_w) * GRAD_MAX
    return UI.lerp_u32(TK.accent, GRAD_DARK, t)
  end
  local function draw_letter(font, ltr, x, glyph_w)
    PushFont(RA.ctx, font, WM_SIZE)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
      letter_color((x - wm_x) + glyph_w * 0.5))
    ImGui.ImGui_SetCursorPos(RA.ctx, x, start_y_local + PAD_TOP)
    Text(RA.ctx, ltr)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end

  -- "Rea" (Inter Light) with per-letter kerning so the trio reads tight.
  draw_letter(f_wm_l, "R", wm_x,                             r_w)
  draw_letter(f_wm_l, "e", wm_x + r_w + KERN,                e_w)
  draw_letter(f_wm_l, "a", wm_x + r_w + KERN + e_w + KERN,   a_w)
  -- "Assist" (Inter Bold) drawn letter-by-letter so the gradient ramp stays
  -- continuous across the Inter-Light -> Inter-Bold boundary.
  do
    local ax = wm_x + rea_w
    for i, ltr in ipairs(assist_letters) do
      local glyph_w = letter_widths[i] * (wm_scale or 1)
      draw_letter(f_wm_b, ltr, ax, glyph_w)
      ax = ax + glyph_w
    end
  end

  -- Clickable wordmark: acts like "return to home" -- clears the current
  -- conversation (with no confirmation, since the user just clicked the
  -- brand mark expecting a fresh start). Hover flips to hand cursor.
  -- Defer the actual conversation-clear to the main loop via
  -- S._logo_click_pending so the click site stays UI-only -- the
  -- consumer (Loop) handles cancel-curl + history wipe + status reset
  -- in a single well-tested place.
  do
    local wm_sx1 = sx + PAD_X
    local wm_sy1 = sy + PAD_TOP
    local wm_sx2 = wm_sx1 + rea_w + assist_w
    local wm_sy2 = wm_sy1 + WM_SIZE
    local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
    if mx >= wm_sx1 and mx <= wm_sx2 and my >= wm_sy1 and my <= wm_sy2 then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
        S._logo_click_pending = true
      end
    end
  end

  -- ---- Status chip (+ "+ new chat" when hero is compact) ------------------
  -- V5 state-aware indicator: label + coloured dot reflect S.status / API-key
  -- presence so the chip actually means something. Pulses subtly while a
  -- request is in flight. When the hero is in compact mode (chat state),
  -- a "+ new chat" link appears to the right of the status.
  local active_p = PROVIDERS.active()
  local needs_key = active_p and not active_p.is_custom
  local has_key   = S.api_key ~= nil
  local cur_status = S.status or "idle"

  local st_label, st_color, st_tooltip, st_pulse, st_is_settings
  if needs_key and not has_key then
    st_label, st_color = "SET API KEY", TK.amber
    st_tooltip = "No API key configured. Click to open Settings."
    st_is_settings = true
  elseif cur_status == "waiting" then
    st_label, st_color = "THINKING", TK.accent
    st_tooltip = "Waiting on a response from the model. This can take a few seconds."
    st_pulse = true
  elseif cur_status == "running" then
    st_label, st_color = "RUNNING", TK.accent
    st_tooltip = "Executing the returned code in REAPER."
    st_pulse = true
  elseif cur_status == "error" then
    st_label, st_color = "ERROR", 0xFF5555FF         -- red
    st_tooltip = "The last request failed. Try again or check your connection."
  else
    st_label, st_color = "READY", TK.green
    st_tooltip = "Connected and ready. Type a prompt or pick a card to begin."
  end

  -- Subtle pulse for active states -- modulate dot alpha on a ~1.4s sine cycle.
  local dot_alpha = 1.0
  if st_pulse then
    local tphase = (time_precise() % 1.4) / 1.4
    dot_alpha = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(tphase * 2 * math.pi))
  end

  local DOT_R   = RA.SC(3)
  local DOT_GAP = RA.SC(8)
  PushFont(RA.ctx, FONT.mono_reg, CHIP_SIZE)
  local st_tw = CalcTextSize(RA.ctx, st_label)
  PopFont(RA.ctx)
  local st_chip_w = DOT_R * 2 + DOT_GAP + st_tw

  -- "+ new chat" chip -- rounded outlined button with a Lucide PLUS glyph
  -- (accent colour) + "new chat" label (faint). Backgrounds are transparent;
  -- only the outer border reads so the chip sits quietly on the hero
  -- gradient. Width grows continuously from 0 to full along `eased` so the
  -- status chip slides leftward in lockstep with the chip opening up.
  local NC_LABEL_TEXT = "new chat"
  local NC_GAP        = RA.SC(14)
  local NC_CHIP_PAD_X = RA.SC(9)   -- inner padding on each end of the chip
  local NC_ICON_GAP   = RA.SC(6)   -- gap between icon and text
  local NC_ICON_SIZE  = RA.SC(12)  -- Lucide glyph size (slightly larger than text for optical weight)
  local NC_CHIP_H     = RA.SC(22)  -- matches ROW_H on the bottom pill
  local NC_CHIP_ROUND = RA.SC(5)   -- matches ROUND_PILL
  PushFont(RA.ctx, FONT.lucide, NC_ICON_SIZE)
  local nc_icon_tw = CalcTextSize(RA.ctx, ICON.PLUS)
  PopFont(RA.ctx)
  PushFont(RA.ctx, FONT.mono_med, CHIP_SIZE)
  local nc_text_tw = CalcTextSize(RA.ctx, NC_LABEL_TEXT)
  PopFont(RA.ctx)
  local nc_chip_w = NC_CHIP_PAD_X * 2 + nc_icon_tw + NC_ICON_GAP + nc_text_tw
  local nc_slot_w = (NC_GAP + nc_chip_w) * eased
  -- Renamed from `total_w` to avoid shadowing the wordmark-width
  -- `total_w` declared above (closed over by letter_color); the chip
  -- group's width is a different quantity entirely.
  local group_w   = st_chip_w + nc_slot_w

  -- Right-align the whole group, centered vertically on the wordmark.
  -- The +SC(2) nudge pushes the status label's optical centre down so
  -- it sits more naturally on the wordmark's cap line.
  --
  -- GROUP_RIGHT_PAD combines the main window's WindowPadding.x (= the
  -- same pad the cards use at their outer edge) PLUS the capability
  -- grid's CONT_PAD_X (SC(14)). That lands the READY chip's right
  -- edge flush with the capability cards' right edge below, matching
  -- the same "right-align to content column" rule the Settings
  -- breadcrumb follows.
  local hero_pad_x      = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local GROUP_RIGHT_PAD = hero_pad_x + RA.SC(14)
  local chip_y_local = start_y_local + PAD_TOP
                     + math_floor((WM_SIZE - CHIP_SIZE) * 0.5) + RA.SC(2)
  local group_x_local = start_x_local + avail_w - GROUP_RIGHT_PAD - group_w
  local chip_sx = sx + (group_x_local - start_x_local)
  local chip_sy = sy + (chip_y_local - start_y_local)

  -- Dot + glow rings (alpha-modulated for the pulse).
  local base_rgb  = st_color & 0xFFFFFF00
  local core_a    = math_max(math_floor(0xFF  * dot_alpha), 0x80)
  local ring_hi_a = math_floor(0x40 * dot_alpha)
  local ring_lo_a = math_floor(0x20 * dot_alpha)
  local dot_cx = chip_sx + DOT_R
  local dot_cy = chip_sy + math_floor(CHIP_SIZE * 0.5)
  ImGui.ImGui_DrawList_AddCircleFilled(dl, dot_cx, dot_cy, RA.SC(6),   base_rgb | ring_lo_a, 0)
  ImGui.ImGui_DrawList_AddCircleFilled(dl, dot_cx, dot_cy, RA.SC(4.5), base_rgb | ring_hi_a, 0)
  ImGui.ImGui_DrawList_AddCircleFilled(dl, dot_cx, dot_cy, DOT_R,   base_rgb | core_a,    0)

  -- Status label.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), st_color)
  PushFont(RA.ctx, FONT.mono_reg, CHIP_SIZE)
  ImGui.ImGui_SetCursorPos(RA.ctx, group_x_local + DOT_R * 2 + DOT_GAP, chip_y_local)
  Text(RA.ctx, st_label)
  PopFont(RA.ctx)
  PopStyleColor(RA.ctx)

  -- Hover + click on status chip (only actionable when the chip is the
  -- "SET API KEY" state; otherwise tooltip-only).
  do
    local st_btn_h = RA.SC(16)
    local st_btn_y = chip_y_local + math_floor((CHIP_SIZE - st_btn_h) * 0.5)
    ImGui.ImGui_SetCursorPos(RA.ctx, group_x_local, st_btn_y)
    local st_clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##hero_status",
      st_chip_w, st_btn_h)
    if ImGui.ImGui_IsItemHovered(RA.ctx) and st_is_settings then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
    end
    UI.tooltip_v5(st_tooltip)
    if st_clicked and st_is_settings then
      api_keys.screen          = "settings"
      api_keys.is_reentry      = true
      api_keys.key_bufs        = {}
      api_keys.key_errors      = {}
      api_keys.key_error       = nil
      api_keys.key_focused     = false
      api_keys.key_validating  = false
      -- Stash current Preferences values so Cancel / "unsaved" discard
      -- can revert them. Save persists + clears these; discard restores
      -- + clears. Keys get their own buffer flow above; everything
      -- below (both main + merged-Advanced prefs) lives here.
      api_keys.saved_ui_scale_idx         = prefs.ui_scale_idx
      api_keys.saved_theme                = prefs.theme
      api_keys.saved_update_check         = prefs.update_check
      api_keys.saved_auto_backup          = prefs.auto_backup
      api_keys.saved_chat_font_idx        = prefs.chat_font_idx
      api_keys.saved_include_snapshot     = prefs.include_snapshot
      api_keys.saved_include_api_ref      = prefs.include_api_ref
      api_keys.saved_cloud_request_timeout = prefs.cloud_request_timeout
      -- Section-open state (per Settings session; not persisted across
      -- script reloads). API KEYS + PREFERENCES default open, ADVANCED
      -- defaults closed so the destructive actions stay tucked away.
      api_keys.section_open = {
        api  = true,
        pref = true,
        adv  = false,
      }
      api_keys.key_validating_idx = nil
      api_keys.custom_edit = nil
    end
  end

  -- "+ new chat" chip. Transparent fill, outlined border, Lucide PLUS icon
  -- in the accent colour + "new chat" label in faint text. Each colour's
  -- alpha byte is scaled manually because DrawList bypasses StyleVar_Alpha,
  -- so the whole chip fades uniformly with `eased`. Hit-testing is gated
  -- to the nearly-settled chat state (eased > 0.85) so the InvisibleButton
  -- doesn't eat capability-grid clicks during the fade-in below it.
  if eased > 0.02 then
    local function _fade(col)
      return (col & 0xFFFFFF00) | math_floor((col & 0xFF) * eased)
    end
    local nc_sx1 = chip_sx + st_chip_w + NC_GAP
    local nc_sx2 = nc_sx1 + nc_chip_w
    -- The chip sits SC(1) below the status-chip centerline so its border
    -- aligns visually with the session-strip card below (which renders a
    -- full pixel lower than the raw vertical-center math would put it).
    local nc_cy  = chip_sy + math_floor(CHIP_SIZE * 0.5) + RA.SC(1)
    local nc_sy1 = nc_cy - math_floor(NC_CHIP_H * 0.5)
    local nc_sy2 = nc_sy1 + NC_CHIP_H

    local nc_hovered, nc_clicked = false, false
    if eased > 0.85 then
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, nc_sx1, nc_sy1)
      nc_clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##hero_new_chat",
        nc_chip_w, NC_CHIP_H)
      nc_hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
      if nc_hovered then
        ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      end
      UI.tooltip_v5("Clear the current conversation and start fresh.")
    end

    -- Fill: dedicated per-theme tokens for rest + hover. Light-mode rest
    -- uses white with alpha so it blends with the hero gradient beneath;
    -- hover is a solid darker tone. Dark-mode rest lifts slightly above
    -- accent_soft; hover lifts further.
    ImGui.ImGui_DrawList_AddRectFilled(dl, nc_sx1, nc_sy1, nc_sx2, nc_sy2,
      _fade(nc_hovered and TK.nc_chip_hover or TK.nc_chip_bg), NC_CHIP_ROUND)
    -- Border on top of the fill. Stronger border on hover for extra
    -- affordance against the shifted background colour.
    ImGui.ImGui_DrawList_AddRect(dl, nc_sx1, nc_sy1, nc_sx2, nc_sy2,
      _fade(nc_hovered and TK.border_str or TK.border), NC_CHIP_ROUND, 0, 1)

    -- Icon + label layout: [pad][icon][gap][text][pad].
    -- Colours are both theme-aware via palette tokens -- TK.accent and
    -- TK.text_muted naturally darken on light mode and lighten on dark mode
    -- relative to the prior accent_ui / text_faint choices.
    local nc_icon_x = nc_sx1 + NC_CHIP_PAD_X
    local nc_text_x = nc_icon_x + nc_icon_tw + NC_ICON_GAP
    -- Icon centered vertically on the chip; the +SC(1) nudge compensates for
    -- Lucide glyphs' typical top-heavy bounding box.
    local nc_icon_y = nc_cy - math_floor(NC_ICON_SIZE * 0.5) + RA.SC(1)
    -- Label nudged up SC(2) from its optical center so it sits tight against
    -- the icon's baseline instead of drifting below it.
    local nc_text_y = nc_cy - math_floor(CHIP_SIZE * 0.5) - RA.SC(2)
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.lucide, NC_ICON_SIZE,
      nc_icon_x, nc_icon_y, _fade(TK.accent), ICON.PLUS)
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.mono_med, CHIP_SIZE,
      nc_text_x, nc_text_y, _fade(TK.text_muted), NC_LABEL_TEXT)

    if nc_clicked then
      -- Same pending flag the clickable wordmark uses -- main loop consumes
      -- it next frame and cancels any in-flight request first.
      S._logo_click_pending = true
    end
  end

  if eased < 0.98 then
    -- Tagline: "Ask anything." (bold, primary) + "Automate everything."
    -- (light, muted) -- two-line contrast via weight AND color, matching the
    -- V5 screenshot. StyleVar_Alpha fades both lines out as the hero
    -- collapses into its compact form, in lockstep with hero_h shrinking.
    local tag_alpha = 1 - eased
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_Alpha(), tag_alpha)
    local tag_y = start_y_local + PAD_TOP + WM_SIZE + RA.SC(8)
    PushFont(RA.ctx, FONT.inter_bold, TAG_SIZE)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local + PAD_X, tag_y)
    Text(RA.ctx, "Ask anything.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    -- "Automate everything." renders 2px smaller than "Ask anything." so the
    -- bold primary line reads as the heading and the light secondary line
    -- sits visually one step below it.
    local TAG_SIZE_SUB = TAG_SIZE - RA.SC(2)
    PushFont(RA.ctx, FONT.inter_light, TAG_SIZE_SUB)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    -- Align baselines by pushing the smaller line down slightly so it sits on
    -- the same cap-line continuation as the bold line above.
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local + PAD_X,
      tag_y + TAG_LINE_H + math_floor((RA.SC(2)) * 0.5))
    Text(RA.ctx, "Automate everything.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    ImGui.ImGui_PopStyleVar(RA.ctx)
    -- Subtitle deliberately omitted in V5: the tagline above already carries
    -- the positioning line, and dropping the third row keeps the hero more
    -- compact so the capability grid has more breathing room.
  end

  -- Advance layout cursor past the hero band.
  ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local, start_y_local + hero_h)
  return hero_h
end

-- V5 compact hero for secondary pages (Settings, Advanced, Preferred
-- Plugins, etc). Fixed-size wordmark (no animation), a mono breadcrumb
-- on the right (e.g. "SETTINGS \xc2\xb7 v0.9.7"), and an optional
-- semibold subtitle below. Bleed the gradient to the window edges like
-- the main hero. Clickable wordmark behaves as "return home".
-- Returns the total pixel height consumed.
function UI.hero_band_settings_v5(subtitle, right_text)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local start_x_local = GetCursorPosX(RA.ctx)
  local start_y_local = ImGui.ImGui_GetCursorPosY(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
  local win_w        = ImGui.ImGui_GetWindowSize(RA.ctx)

  local WM_SIZE   = RA.SC(22)    -- wordmark size (compact, per V5 spec)
  local SUB_SIZE  = RA.SC(16)    -- subtitle size
  local RIGHT_SZ  = RA.SC(12)    -- right-side breadcrumb mono size (+2 vs spec for weight)
  local PAD_TOP   = RA.SC(16)
  local PAD_BOT   = RA.SC(22)    -- includes +10 breathing room above the divider
  local PAD_X     = RA.SC(22)
  local WM_SUB_GAP = RA.SC(6)    -- gap between wordmark and subtitle

  local hero_h
  if subtitle and subtitle ~= "" then
    hero_h = PAD_TOP + WM_SIZE + WM_SUB_GAP + SUB_SIZE + PAD_BOT
  else
    hero_h = PAD_TOP + WM_SIZE + PAD_BOT
  end

  -- Gradient bg + bottom border, edge-to-edge past WindowPadding.
  ImGui.ImGui_DrawList_AddRectFilledMultiColor(dl,
    win_x, win_y, win_x + win_w, sy + hero_h,
    TK.accent_soft, TK.accent_soft, TK.bg, TK.bg)
  ImGui.ImGui_DrawList_AddLine(dl,
    win_x, sy + hero_h - 1, win_x + win_w, sy + hero_h - 1,
    TK.border, 1)

  -- Wordmark ("Rea" Inter Light + "Assist" Inter Bold) with per-letter
  -- horizontal gradient (leftmost letter ~40% toward deep navy; rightmost
  -- is pure accent). Simplified from UI.hero_band_v5 -- static size, no
  -- kerning animation.
  local f_wm_l = FONT.inter_light
  local f_wm_b = FONT.inter_bold
  local KERN   = -math_max(1, math_floor(WM_SIZE * 0.07))
  -- Settings-hero metric cache, mirror of the home-screen hero cache
  -- above. Cache key is WM_SIZE so a UI scale change invalidates.
  UI._wm_metrics_s = UI._wm_metrics_s or {}
  local _wm_s = UI._wm_metrics_s[WM_SIZE]
  if not _wm_s then
    _wm_s = { letter_w = {} }
    PushFont(RA.ctx, f_wm_l, WM_SIZE)
    _wm_s.r_w = CalcTextSize(RA.ctx, "R")
    _wm_s.e_w = CalcTextSize(RA.ctx, "e")
    _wm_s.a_w = CalcTextSize(RA.ctx, "a")
    PopFont(RA.ctx)
    PushFont(RA.ctx, f_wm_b, WM_SIZE)
    _wm_s.assist_w = CalcTextSize(RA.ctx, "Assist")
    for i, ltr in ipairs(_ASSIST_LETTERS) do
      _wm_s.letter_w[i] = CalcTextSize(RA.ctx, ltr)
    end
    PopFont(RA.ctx)
    UI._wm_metrics_s[WM_SIZE] = _wm_s
  end
  local r_w = _wm_s.r_w
  local e_w = _wm_s.e_w
  local a_w = _wm_s.a_w
  local assist_letters = _ASSIST_LETTERS
  local letter_widths  = _wm_s.letter_w
  local assist_w = _wm_s.assist_w
  local rea_w   = r_w + KERN + e_w + KERN + a_w
  local wm_x    = start_x_local + PAD_X
  local total_w = rea_w + assist_w
  local GRAD_MAX  = 0.40
  local GRAD_DARK = 0x18264FFF
  local function letter_color(x_rel_center)
    local t = (1 - x_rel_center / total_w) * GRAD_MAX
    return UI.lerp_u32(TK.accent, GRAD_DARK, t)
  end
  local function draw_letter(font, ltr, x, glyph_w)
    PushFont(RA.ctx, font, WM_SIZE)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
      letter_color((x - wm_x) + glyph_w * 0.5))
    ImGui.ImGui_SetCursorPos(RA.ctx, x, start_y_local + PAD_TOP)
    Text(RA.ctx, ltr)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end
  draw_letter(f_wm_l, "R", wm_x,                           r_w)
  draw_letter(f_wm_l, "e", wm_x + r_w + KERN,              e_w)
  draw_letter(f_wm_l, "a", wm_x + r_w + KERN + e_w + KERN, a_w)
  do
    local ax = wm_x + rea_w
    for i, ltr in ipairs(assist_letters) do
      local glyph_w = letter_widths[i] * (wm_scale or 1)
      draw_letter(f_wm_b, ltr, ax, glyph_w)
      ax = ax + glyph_w
    end
  end

  -- Clickable wordmark (return home). Hover flips to hand cursor;
  -- consumed by the main loop via S._logo_click_pending.
  do
    local wm_sx1 = sx + PAD_X
    local wm_sy1 = sy + PAD_TOP
    local wm_sx2 = wm_sx1 + rea_w + assist_w
    local wm_sy2 = wm_sy1 + WM_SIZE
    local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
    if mx >= wm_sx1 and mx <= wm_sx2 and my >= wm_sy1 and my <= wm_sy2 then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
        S._logo_click_pending = true
      end
    end
  end

  -- Right breadcrumb: mono, tight letter-spacing, right-aligned to the
  -- same edge the body content column below will use (so the SETTINGS
  -- text lines up with the API KEYS / PREFERENCES section labels and
  -- the key cards under them).
  if right_text and right_text ~= "" then
    -- Body content column right-edge: matches the symmetric SC(22)
    -- horizontal inset used by _shared_key_screen_impl and the rest of
    -- the settings-family screens. Subtract (BODY_PAD_X - pad_x) from
    -- the full-avail right edge so the breadcrumb sits at the same
    -- window-local x the body's right card edge will.
    local hero_pad_x = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
    local BODY_PAD_X = RA.SC(22)
    local right_edge_local = start_x_local + avail_w - (BODY_PAD_X - hero_pad_x)

    -- Tight mono kern: -1px per gap at SC(11); scales with font size.
    -- Draw each UTF-8 char individually because ImGui has no letter-
    -- spacing style var; CalcTextSize per char gives us advance widths.
    local TIGHT_KERN = -math_max(1, math_floor(RIGHT_SZ * 0.08))
    PushFont(RA.ctx, FONT.mono_reg, RIGHT_SZ)
    local chars, total_rt_w = {}, 0
    for _, cp in utf8.codes(right_text) do
      local ch = utf8.char(cp)
      local cw = CalcTextSize(RA.ctx, ch)
      chars[#chars+1] = { c = ch, w = cw }
      total_rt_w = total_rt_w + cw
    end
    PopFont(RA.ctx)
    if #chars > 1 then
      total_rt_w = total_rt_w + TIGHT_KERN * (#chars - 1)
    end
    -- Horizontal: right edge matches the cards' right column edge
    -- exactly (win_x + win_w - BODY_PAD_X). Mono glyphs have a slight
    -- right-side bearing that can read as "just inside" the column,
    -- but overshooting on purpose made it worse -- flush alignment
    -- looks best.
    -- Vertical: baseline with the subtitle row below the wordmark
    -- (sub_y uses the same formula below). Reads as complementary
    -- "meta" info at the same altitude as the page subtitle.
    local rt_x_screen = sx + (right_edge_local - start_x_local) - total_rt_w
    local rt_y_screen = sy + PAD_TOP + WM_SIZE + WM_SUB_GAP
                     + math_floor((SUB_SIZE - RIGHT_SZ) * 0.5)
    local cur_sx = rt_x_screen
    for _, ch in ipairs(chars) do
      ImGui.ImGui_DrawList_AddTextEx(dl, FONT.mono_reg, RIGHT_SZ,
        cur_sx, rt_y_screen, TK.text_faint, ch.c)
      cur_sx = cur_sx + ch.w + TIGHT_KERN
    end
  end

  -- Subtitle below wordmark (Inter SemiBold at SUB_SIZE, TK.text).
  if subtitle and subtitle ~= "" then
    local sub_y = start_y_local + PAD_TOP + WM_SIZE + WM_SUB_GAP
    PushFont(RA.ctx, FONT.inter_semi, SUB_SIZE)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local + PAD_X, sub_y)
    Text(RA.ctx, subtitle)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end

  -- Advance layout cursor past the hero band.
  ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local, start_y_local + hero_h)
  return hero_h
end

-- V5 session context strip -- small card pinned below the hero band that
-- reflects the currently-active REAPER project: project name, track/item/FX
-- counts, and the live play-cursor time. Read-only; purely informational.
-- Cached session counts. Invalidated on a change in REAPER's project
-- state counter (GetProjectStateChangeCount - O(1) read, increments on
-- every undoable op) or after a 5s fallback for non-undoable changes
-- like project swaps. Play-cursor time still reads per frame.
local _session_cache = {
  t = 0, state = -1, name = "", tracks = 0, items = 0, fx = 0
}
local function _format_time(sec)
  sec = math_max(0, sec)
  local h = math_floor(sec / 3600)
  local m = math_floor((sec % 3600) / 60)
  local s = math_floor(sec % 60)
  return str_format("%02d:%02d:%02d", h, m, s)
end
function UI.session_strip_v5()
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local start_x_local = GetCursorPosX(RA.ctx)
  local start_y_local = ImGui.ImGui_GetCursorPosY(RA.ctx)

  local CARD_PAD_V    = RA.SC(10)        -- card inner vertical padding
  local CARD_PAD_H    = RA.SC(12)        -- card inner horizontal padding
  local CARD_ROUND    = RA.SC(8)
  local CONT_PAD_TOP  = RA.SC(14)
  local CONT_PAD_BOT  = RA.SC(10)
  local CONT_PAD_X    = RA.SC(14)        -- bar spans closer to window edges
  local ROW_FONT_SIZE = RA.SC(12)        -- body rows
  local MONO_SIZE     = RA.SC(10)
  local ITEM_GAP      = RA.SC(8)

  local card_h = CARD_PAD_V * 2 + math_max(ROW_FONT_SIZE, MONO_SIZE)
  local strip_h = CONT_PAD_TOP + card_h + CONT_PAD_BOT

  -- Project name falls back to "unsaved" when EnumProjects returns an
  -- empty path. Rebuild only when the state counter changes or after
  -- the 5s fallback; steady-state frames are just a counter compare.
  local now = time_precise()
  local cur_state = reaper.GetProjectStateChangeCount
                    and reaper.GetProjectStateChangeCount(0) or -1
  -- Throttle state-dirty rebuilds to once per 100ms. During heavy edits
  -- (drag-resize, large multi-select moves) GetProjectStateChangeCount
  -- ticks per micro-edit, so the strip would otherwise re-walk every
  -- track + count items + count FX every frame -- the bulk of the
  -- strip's per-frame cost on 100+ track sessions. The strip is
  -- informational, not interactive, so 100ms staleness is invisible.
  -- The 5s fallback still covers non-undoable changes (like project
  -- swaps) that don't bump the state counter.
  local age = now - _session_cache.t
  if (cur_state ~= _session_cache.state and age > 0.1) or age > 5 then
    local proj_path = select(2, reaper.EnumProjects(-1)) or ""
    local proj_name = proj_path:match("[^\\/]+$")
    if not proj_name or proj_name == "" then proj_name = "unsaved" end
    -- Cap to 33 chars (including the ".rpp" tail) so the session strip
    -- doesn't blow past the card width on long project names. Truncate to
    -- 30 chars + "..." so the total stays at exactly 33. Use utf8.len /
    -- utf8.offset so a CJK / Cyrillic / accented project name isn't cut
    -- mid-codepoint (which would feed ImGui invalid UTF-8 and render as
    -- a replacement glyph).
    if utf8.len(proj_name) and utf8.len(proj_name) > 33 then
      local cut = utf8.offset(proj_name, 31)
      if cut then proj_name = proj_name:sub(1, cut - 1) .. "..." end
    end
    local nt = R.CountTracks(0)
    local items, fxs = 0, 0
    for i = 0, nt - 1 do
      local tr = R.GetTrack(0, i)
      -- Guard: GetTrack can return nil if another deferred script removed
      -- a track between CountTracks and this iteration. Without the
      -- guard, passing nil to CountTrackMediaItems / TrackFX_GetCount
      -- userdata-errors and aborts the render frame.
      if tr then
        items = items + R.CountTrackMediaItems(tr)
        fxs   = fxs   + R.TrackFX_GetCount(tr)
      end
    end
    _session_cache.t      = now
    _session_cache.state  = cur_state
    _session_cache.name   = proj_name
    _session_cache.tracks = nt
    _session_cache.items  = items
    _session_cache.fx     = fxs
  end

  local card_x_local = start_x_local + CONT_PAD_X
  local card_y_local = start_y_local + CONT_PAD_TOP
  local card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx) - CONT_PAD_X * 2
  -- Derive screen coords for the card rect (draw list uses screen space).
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local cs_x1 = sx + CONT_PAD_X
  local cs_y1 = sy + CONT_PAD_TOP
  local cs_x2 = cs_x1 + card_w
  local cs_y2 = cs_y1 + card_h

  -- Transparent card -- keep the rounded border outline for the "contained
  -- band" feel, but skip the fill so the main window bg shows through. The
  -- tile grid below still uses TK.card, so the strip no longer competes
  -- with the tiles for visual weight while still reading as a framed unit.
  ImGui.ImGui_DrawList_AddRect(dl, cs_x1, cs_y1, cs_x2, cs_y2,
    TK.border, CARD_ROUND, 0, 1)

  -- Row content -- draw left-to-right, tracking cumulative cursor x. The row
  -- is nudged up a couple pixels so the Inter cap-height sits on the visual
  -- centre of the card (Inter's descender-heavy line box otherwise reads low).
  local row_y = card_y_local + CARD_PAD_V - RA.SC(2)
  local x     = card_x_local + CARD_PAD_H

  local function draw_seg(font, size, col, text)
    PushFont(RA.ctx, font, size)
    local tw = CalcTextSize(RA.ctx, text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col)
    -- Align all segments to the same visual baseline by offsetting smaller
    -- fonts down so their bottoms line up with the body-row text.
    local y_adj = math_floor((ROW_FONT_SIZE - size) * 0.5)
    ImGui.ImGui_SetCursorPos(RA.ctx, x, row_y + y_adj)
    Text(RA.ctx, text)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    x = x + tw + ITEM_GAP
  end
  -- Draw a mid-dot separator as a small filled circle (source is ASCII-only,
  -- so the "." glyph is faked via the draw list). Centered vertically on the
  -- body-text cap height.
  local function draw_dot()
    local cx = sx + (x - start_x_local)
    local cy = sy + (row_y - start_y_local) + math_floor(ROW_FONT_SIZE * 0.5)
    -- TK.text_muted (not text_faint) so the separators still read on the
    -- transparent-card strip against the main window bg.
    ImGui.ImGui_DrawList_AddCircleFilled(dl, cx, cy, math_max(RA.SC(1.3), 1), TK.text_muted, 0)
    x = x + RA.SC(4) + ITEM_GAP
  end

  -- V5 technical-readout look -- everything in JetBrains Mono at the
  -- same MONO_SIZE as CURRENT / STOP / time. Uniform size means the data
  -- segments share CURRENT's tighter letter-spacing feel rather than
  -- reading as larger-and-looser next to it.
  -- File icon (Lucide) replaces the old "CURRENT" label so the project name
  -- becomes the loudest element in the row. Same muted accent as the old
  -- label kept the visual anchor on the left; using text_faint here would
  -- lose the "this is context" signal entirely.
  do
    local icon_size = RA.SC(14)                    -- +3px over the previous SC(11)
    PushFont(RA.ctx, FONT.lucide, icon_size)
    local iw = CalcTextSize(RA.ctx, ICON.FILE)
    PopFont(RA.ctx)
    local ix = sx + (x - start_x_local)
    -- Center the icon vertically on the mono cap-height, then nudge 2px
    -- down to sit closer to the text baseline.
    local iy = sy + (row_y - start_y_local)
             + math_floor((MONO_SIZE - icon_size) * 0.5) + RA.SC(2)
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.lucide, icon_size,
      ix, iy, TK.text_faint, ICON.FILE)
    x = x + iw + ITEM_GAP
  end
  draw_seg(FONT.mono_reg, MONO_SIZE,  TK.text,       _session_cache.name)
  draw_dot()
  draw_seg(FONT.mono_reg, MONO_SIZE,  TK.text_muted,
           tostring(_session_cache.tracks) .. " tracks")
  draw_dot()
  draw_seg(FONT.mono_reg, MONO_SIZE,  TK.text_muted,
           tostring(_session_cache.items) .. " items")
  draw_dot()
  draw_seg(FONT.mono_reg, MONO_SIZE,  TK.text_muted,
           tostring(_session_cache.fx) .. " fx")

  -- Transport state + play-cursor time (both mono, right-aligned). The time
  -- reads fresh each frame so it animates smoothly during playback; the state
  -- label reflects reaper.GetPlayState (bit 0 = play, bit 1 = paused,
  -- bit 2 = record). State colour: green when playing, red when recording,
  -- amber when paused, muted grey when stopped.
  local st = reaper.GetPlayState() or 0
  local st_label, st_col
  if (st & 4) ~= 0 then
    st_label, st_col = "REC",   0xFF5555FF
  elseif (st & 2) ~= 0 then
    st_label, st_col = "PAUSE", TK.amber
  elseif (st & 1) ~= 0 then
    st_label, st_col = "PLAY",  TK.green
  else
    st_label, st_col = "STOP",  TK.text_faint
  end
  -- Playhead: show the live play-cursor during playback, otherwise show the
  -- edit cursor so the readout tracks where the user has clicked/moved the
  -- playhead even when transport is stopped. Both calls are O(1) reads.
  local playhead = ((st & 1) ~= 0) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local time_str = _format_time(playhead)

  PushFont(RA.ctx, FONT.mono_reg, MONO_SIZE)
  local t_tw  = CalcTextSize(RA.ctx, time_str)
  local st_tw = CalcTextSize(RA.ctx, st_label)
  PopFont(RA.ctx)
  local GAP_ST_T = RA.SC(10)
  local right_x  = card_x_local + card_w - CARD_PAD_H
  local t_x      = right_x - t_tw
  local st_x     = t_x - GAP_ST_T - st_tw
  local mono_y   = row_y + math_floor((ROW_FONT_SIZE - MONO_SIZE) * 0.5)

  PushFont(RA.ctx, FONT.mono_reg, MONO_SIZE)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), st_col)
  ImGui.ImGui_SetCursorPos(RA.ctx, st_x, mono_y)
  Text(RA.ctx, st_label)
  PopStyleColor(RA.ctx)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
  ImGui.ImGui_SetCursorPos(RA.ctx, t_x, mono_y)
  Text(RA.ctx, time_str)
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)

  -- Advance layout cursor past the strip.
  ImGui.ImGui_SetCursorPos(RA.ctx, start_x_local, start_y_local + strip_h)
  return strip_h
end

-- V5 Mode + model controls row.
-- Segmented Ask|Auto-Run pill + provider chip + model chip + optional
-- thinking chip + inline details toggle. Chip visuals are custom-drawn;
-- popups use ImGui's native menu flow so keyboard dismiss and click-
-- outside-to-close come for free.
function UI.mode_model_row_v5()
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local start_pos_x = ImGui.ImGui_GetCursorPosX(RA.ctx)
  local start_pos_y = ImGui.ImGui_GetCursorPosY(RA.ctx)

  local PAD_X      = RA.SC(14)
  local ROW_GAP    = RA.SC(8)
  local ROW_H      = RA.SC(22)
  local SEG_PAD_X  = RA.SC(9)
  local INNER_PAD  = RA.SC(2)
  local CHIP_PAD_X = RA.SC(9)
  local CHEV_GAP   = RA.SC(4)
  local MONO_SIZE  = RA.SC(10)
  local CHEV_SIZE  = RA.SC(10)
  local ROUND_PILL = RA.SC(5)
  local ROUND_SEG  = RA.SC(3)

  local req_live = (S.status == "waiting")

  local cursor_x = sx + PAD_X
  -- Lift the chip row 7px above its layout slot. The Dummy at the bottom
  -- of this function still reserves ROW_H of vertical space, so downstream
  -- elements (combo-hint line, footer rail) keep their normal layout
  -- positions; only the chip row + Ask/AutoRun pill + inline toggles
  -- visually rise into the slot above.
  local CHIP_ROW_LIFT = RA.SC(5)
  local y1, y2 = sy - CHIP_ROW_LIFT, sy - CHIP_ROW_LIFT + ROW_H

  PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
  local _, th = CalcTextSize(RA.ctx, "M")
  PopFont(RA.ctx)
  local t_y = y1 + math_floor((ROW_H - th) * 0.5)

  -- Place an InvisibleButton at (x1, y1) with size (w, h). Returns true if the
  -- button was clicked this frame. Also sets the hand cursor on hover. Each
  -- button's unique id is required for ImGui's hover/click tracking.
  local function btn_at(id, x1, w, h)
    ImGui.ImGui_SetCursorScreenPos(RA.ctx, x1, y1)
    local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, id, w, h)
    if ImGui.ImGui_IsItemHovered(RA.ctx) then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
    end
    return clicked
  end

  -- ---- Chip drawer (used for provider / model / thinking) -----------------
  -- Draws a chip (label + chevron) and places an InvisibleButton over it so
  -- hover/click/tooltips route through normal ImGui item flow. Returns the
  -- chip's left edge (for popup anchoring) and whether it was clicked.
  local function draw_chip(label, btn_id, enabled, tooltip_text)
    PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
    local lw = CalcTextSize(RA.ctx, label)
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.lucide, CHEV_SIZE)
    local cw = CalcTextSize(RA.ctx, ICON.CHEVRON_DOWN)
    PopFont(RA.ctx)
    local w = CHIP_PAD_X * 2 + lw + CHEV_GAP + cw
    local cx1, cx2 = cursor_x, cursor_x + w

    ImGui.ImGui_BeginDisabled(RA.ctx, not enabled)
    local clicked = btn_at(btn_id, cx1, w, ROW_H)
    local hovered = enabled and ImGui.ImGui_IsItemHovered(RA.ctx)
    UI.tooltip_v5(tooltip_text)
    ImGui.ImGui_EndDisabled(RA.ctx)

    ImGui.ImGui_DrawList_AddRectFilled(dl, cx1, y1, cx2, y2,
      hovered and TK.card_hover or TK.card, ROUND_PILL)
    ImGui.ImGui_DrawList_AddRect(dl, cx1, y1, cx2, y2, TK.border, ROUND_PILL)
    PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
    ImGui.ImGui_DrawList_AddText(dl, cx1 + CHIP_PAD_X, t_y,
      enabled and TK.text or TK.text_faint, label)
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.lucide, CHEV_SIZE)
    local ch_y = y1 + math_floor((ROW_H - CHEV_SIZE) * 0.5)
    ImGui.ImGui_DrawList_AddText(dl,
      cx1 + CHIP_PAD_X + lw + CHEV_GAP, ch_y,
      TK.text_muted, ICON.CHEVRON_DOWN)
    PopFont(RA.ctx)
    cursor_x = cx2 + ROW_GAP
    return cx1, clicked
  end

  -- ---- Provider chip ------------------------------------------------------
  -- Hidden built-ins (experimental, gated by an ExtState unlock at startup;
  -- see the unlock block after Custom.register_all in ReaAssist.lua) keep
  -- their slot in PROVIDERS for id-based lookup but stay out of every UI
  -- surface, including this dropdown.
  local prov_filtered = {}
  for i, p in ipairs(PROVIDERS) do
    if not p.hidden and (p.is_custom or S.api_key_map[p.id]) then
      -- Label Gemini as "Gemini (Free)" in the dropdown when the free-tier
      -- detector has confirmed the key is on the free plan. The chip uses a
      -- separate suffix (same condition, capitalized to match UPPER casing).
      local label = p.label
      if p.id == "google" and S.gemini_paid_tier == false then
        label = label .. " (Free)"
      end
      prov_filtered[#prov_filtered+1] = { idx = i, label = label, id = p.id }
    end
  end
  local p_active = PROVIDERS.active()

  -- Hard cap on the mono text rendered inside each chip. The row holds
  -- provider + model + thinking chips plus the Ask/Auto-Run pill and the
  -- "backup / details" text; letting a user-typed label grow unbounded
  -- (long custom-provider names, verbose model ids) pushes everything to
  -- the right off-screen. Ellipsis (U+2026) truncation hints at the cutoff
  -- without breaking mono alignment. Full label is still visible in the
  -- chip's tooltip and in the dropdown menu items below.
  local CHIP_MAX_PROV  = 14
  local CHIP_MAX_MODEL = 22
  local function _chip_truncate(s, max_chars)
    if not s then return "" end
    if #s <= max_chars then return s end
    return s:sub(1, max_chars - 1) .. "\xe2\x80\xa6"
  end

  -- The Free-tier suffix only appears in the provider dropdown (see label
  -- composition above); the chip stays a bare provider name for brevity.
  local prov_chip = _chip_truncate(p_active.label:upper(), CHIP_MAX_PROV)
  local can_prov = (#prov_filtered > 1) and not req_live
  local prov_cx1, prov_clicked = draw_chip(prov_chip, "##mm_prov_btn", can_prov,
    "Provider - " .. p_active.label .. ". Choose which service ReaAssist talks to.")
  if prov_clicked then ImGui.ImGui_OpenPopup(RA.ctx, "##mm_prov_popup") end

  ImGui.ImGui_SetNextWindowPos(RA.ctx, prov_cx1, y2 + RA.SC(2))
  UI.push_card_popup_style()
  if ImGui.ImGui_BeginPopup(RA.ctx, "##mm_prov_popup") then
    -- Muted header label so the dropdown reads "this is the Provider menu"
    -- at a glance. TextDisabled inherits Col_TextDisabled = TK.text_muted
    -- from the global style push at line 575, so it tracks the active
    -- theme without an extra Push/Pop pair here.
    ImGui.ImGui_TextDisabled(RA.ctx, "Provider:")
    ImGui.ImGui_Separator(RA.ctx)
    for _, fp in ipairs(prov_filtered) do
      if ImGui.ImGui_MenuItem(RA.ctx, fp.label, nil, fp.idx == prefs.provider_idx)
         and fp.idx ~= prefs.provider_idx then
        local old_p = PROVIDERS.active()
        reaper.SetExtState(CFG.EXT_NS, "model_idx_" .. old_p.id,
          tostring(prefs.model_idx), true)
        -- Save thinking_idx under the OLD (provider, model) pair so the
        -- per-model state survives the switch. The helper writes the
        -- new "thinking_idx_<provider>_<model>" slot.
        if old_p.thinking_levels and prefs.thinking_idx > 0 then
          local old_m = MODELS[prefs.model_idx] or MODELS[1]
          PROVIDERS.save_thinking_idx(old_p, old_m, prefs.thinking_idx)
        end
        if old_p.id == "google" then Net.gemini_cache_invalidate() end
        prefs.provider_idx = fp.idx
        reaper.SetExtState(CFG.EXT_NS, "provider_idx",
          tostring(prefs.provider_idx), true)
        MODELS.refresh()
        S.api_key = S.api_key_map[PROVIDERS.active().id]
        S.api_ref_message = nil
        local nm = MODELS[prefs.model_idx]
        if nm then
          for _, att in ipairs(S.attachments) do
            att.cost = att.tokens * nm.price_in / 1000000
          end
        end
      end
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_card_popup_style()

  -- ---- Model chip ----------------------------------------------------------
  local prov_id = p_active.id
  local model_label
  do
    local m = MODELS[prefs.model_idx]
    -- Prefer the short chip_label from the model definition (e.g. "HAIKU",
    -- "NANO", "FLASH LITE") so the row stays compact. Custom providers
    -- don't ship chip_labels and their m.label now includes the Dropdown
    -- Notes tag ("kimi-k2.6 . fast") for the menu. The chip itself shows
    -- only the raw id (without notes) to keep the row tight; the dropdown
    -- stays the place where notes differentiate same-id rows.
    if m then
      if p_active.is_custom then
        model_label = (m.id or "?"):upper()
      else
        model_label = m.chip_label or m.label:upper()
      end
    else
      model_label = "?"
    end
    model_label = _chip_truncate(model_label, CHIP_MAX_MODEL)
  end
  -- Tooltip carries the full (un-truncated, notes-included) label so the
  -- user can confirm which row is active even when the chip is ellipsized.
  local mdl_tooltip = "Model - pick which model handles this provider's requests."
  do
    local m = MODELS[prefs.model_idx]
    if m and m.label and m.label ~= "" then
      mdl_tooltip = "Model - " .. m.label .. ". "
                 .. "Pick which model handles this provider's requests."
    end
  end
  local mdl_cx1, mdl_clicked = draw_chip(model_label, "##mm_mdl_btn", not req_live,
    mdl_tooltip)
  if mdl_clicked then ImGui.ImGui_OpenPopup(RA.ctx, "##mm_mdl_popup") end

  ImGui.ImGui_SetNextWindowPos(RA.ctx, mdl_cx1, y2 + RA.SC(2))
  UI.push_card_popup_style()
  -- Descriptor by position in the current provider's model list. ImGui's
  -- MenuItem "shortcut" slot right-aligns and dims the text -- reusing it
  -- for descriptors gives us a clean two-column look without extra widgets.
  local function model_descriptor(i, total)
    if total <= 1 then return nil end
    if total == 2 then
      return i == 1 and "fast" or "balanced"
    end
    if i == 1 then return "fast" end
    if i == total then return "smart" end
    return "balanced"
  end
  if ImGui.ImGui_BeginPopup(RA.ctx, "##mm_mdl_popup") then
    -- Header label, matching the Provider / Thinking dropdowns.
    ImGui.ImGui_TextDisabled(RA.ctx, "Model:")
    ImGui.ImGui_Separator(RA.ctx)
    -- Iterate the provider's FULL model list (raw, unfiltered) -- we want
    -- paid-only models to appear disabled rather than hidden, so free-tier
    -- users learn they exist. MODELS (the filtered list) is still used to
    -- resolve a raw index to a "usable" index for prefs.model_idx.
    local raw_models = p_active.models
    local total_models = #raw_models
    -- Free Gemini has no per-token cost, so the $ column becomes noise.
    -- But paid-only entries still get a "paid" tag in that slot.
    local show_price = not (prov_id == "google" and S.gemini_paid_tier == false)

    -- Pre-compute each row's right-column string and the widest descriptor
    -- + right-column so fixed-width mono alignment stays tight. Custom
    -- providers skip the tier descriptors ("fast" / "balanced" / "smart")
    -- and the $-count ranking entirely: user-defined model lists don't
    -- imply a performance/cost ordering, and the Dropdown Notes field on
    -- each model row is the user's own labeling channel. Keeping the
    -- built-in ranking on custom providers mislabels equal-tier models
    -- (e.g. kimi-k2.6 thinking vs non-thinking) as "fast" and "smart".
    local row_descr, row_right = {}, {}
    local max_descr, max_right = 0, 0
    local is_custom = p_active.is_custom or false
    for i, raw_m in ipairs(raw_models) do
      -- Coerce the three-way AND to a strict boolean. Without `or false`,
      -- Lua's short-circuit leaves `locked` as `nil` when raw_m.paid_only
      -- is nil, and ReaImGui's BeginDisabled treats nil differently from
      -- false on some builds -- silently greying every row.
      -- Use `~= true` (not `== false`) so the lock is also engaged when
      -- the tier is `nil` (untested, or just-cleared by a fresh tier
      -- test that hasn't resolved yet). This matches the model-list
      -- filter at ReaAssist.lua's MODELS.refresh, which strips paid_only
      -- entries unless tier is strictly `true`. Without this match,
      -- raw_models still renders Pro for any non-`false` tier but the
      -- click handler can't find it in the filtered MODELS list, so
      -- the row looks selectable yet silently swallows clicks.
      local locked = (raw_m.paid_only and prov_id == "google"
                      and S.gemini_paid_tier ~= true) or false
      local d = ""
      if not is_custom then
        d = model_descriptor(i, total_models) or ""
      end
      local r
      if locked then
        r = "paid only"
      elseif show_price and not is_custom then
        r = string.rep("$", i)
      else
        r = ""
      end
      row_descr[i] = d
      row_right[i] = r
      if #d > max_descr then max_descr = #d end
      if #r > max_right then max_right = #r end
    end

    for i, raw_m in ipairs(raw_models) do
      -- Coerce the three-way AND to a strict boolean. Without `or false`,
      -- Lua's short-circuit leaves `locked` as `nil` when raw_m.paid_only
      -- is nil, and ReaImGui's BeginDisabled treats nil differently from
      -- false on some builds -- silently greying every row.
      -- Use `~= true` (not `== false`) so the lock is also engaged when
      -- the tier is `nil` (untested, or just-cleared by a fresh tier
      -- test that hasn't resolved yet). This matches the model-list
      -- filter at ReaAssist.lua's MODELS.refresh, which strips paid_only
      -- entries unless tier is strictly `true`. Without this match,
      -- raw_models still renders Pro for any non-`false` tier but the
      -- click handler can't find it in the filtered MODELS list, so
      -- the row looks selectable yet silently swallows clicks.
      local locked = (raw_m.paid_only and prov_id == "google"
                      and S.gemini_paid_tier ~= true) or false
      -- Map this raw model to its position in the filtered MODELS list. For
      -- built-in providers, match by id: the Google free-tier filter may
      -- drop paid-only rows so raw/usable indices diverge. For custom
      -- providers, MODELS mirrors raw_models 1-to-1 (no filtering), and a
      -- user-defined list can legitimately repeat the same model id across
      -- rows that differ only in notes / extra_body (e.g. "kimi-k2.6 .
      -- fast" vs "kimi-k2.6 . thinking"); an id-based lookup would collapse
      -- them to the same index. Use position-based matching instead.
      local usable_idx
      if is_custom then
        usable_idx = i
      else
        for j, m in ipairs(MODELS) do
          if m.id == raw_m.id then usable_idx = j; break end
        end
      end
      -- Checkmark: the selected-state indicator next to the active row.
      -- Position-based comparison works for both branches -- built-in:
      -- usable_idx is the filtered MODELS index and prefs.model_idx tracks
      -- the same; custom: usable_idx = i and the saved model_idx is the
      -- raw row position too. Two custom rows that share an id but differ
      -- in notes get checkmarked independently because the index disambiguates.
      local sel = usable_idx ~= nil and (prefs.model_idx == usable_idx)

      local descr_col = row_descr[i] .. string.rep(" ", max_descr - #row_descr[i])
      local right_col = string.rep(" ", max_right - #row_right[i]) .. row_right[i]
      local shortcut
      if max_right > 0 then
        shortcut = descr_col .. "  " .. right_col
      else
        shortcut = row_descr[i]    -- no right column; plain descriptor
      end

      -- Asterisk badge marks the provider's recommended model (per
      -- p_active.default_model_idx). Non-recommended rows get a 2-space
      -- prefix so model names line up vertically against "* ". The
      -- right-side checkmark (sel) still indicates the user's current
      -- selection -- the two cues read independently, so a
      -- recommended-and-selected row appears as "* Sonnet 4.6 CHK".
      -- Asterisk (vs. a Unicode star glyph) keeps us inside the basic
      -- Latin range that the menu font's glyph map actually loads.
      -- Custom providers carry a default_model_idx (typically 1) for
      -- bootstrap, but their model lists are user-defined so generic
      -- "recommended" guidance can't be reliable -- nil out rec_idx
      -- on custom providers so no row gets the badge, matching the
      -- same convention UI.COMBO_HINTS uses to skip custom providers.
      local rec_idx   = (not is_custom) and p_active.default_model_idx or nil
      local label_pfx = (i == rec_idx) and "* " or "  "
      ImGui.ImGui_BeginDisabled(RA.ctx, locked)
      local m_clicked = ImGui.ImGui_MenuItem(RA.ctx, label_pfx .. raw_m.label, shortcut, sel)
      ImGui.ImGui_EndDisabled(RA.ctx)
      if locked then
        UI.tooltip_v5("Requires Google's paid API tier. Upgrade at aistudio.google.com/apikey.")
      else
        local tip = UI.MODEL_TIPS[raw_m.id]
        if tip then UI.tooltip_v5(tip) end
      end
      if m_clicked and usable_idx then
        -- Save current thinking_idx under the OLD model so per-model
        -- state survives the switch (e.g. Sonnet=Medium, Haiku=Low,
        -- Opus=None all preserved independently). Capture old_m BEFORE
        -- mutating prefs.model_idx; otherwise we'd save under the new
        -- model's id and lose the old model's setting.
        local old_m = MODELS[prefs.model_idx] or MODELS[1]
        if p_active.thinking_levels and prefs.thinking_idx > 0 then
          PROVIDERS.save_thinking_idx(p_active, old_m, prefs.thinking_idx)
        end
        prefs.model_idx = usable_idx
        reaper.SetExtState(CFG.EXT_NS, "model_idx_" .. prov_id,
          tostring(prefs.model_idx), true)
        -- Load thinking_idx for the NEW model. Helper cascades through
        -- per-model key -> model default -> provider default -> 1, so
        -- first switches to a model with a model-level default (e.g.
        -- Haiku 4.5 = Medium) auto-apply that default while explicit
        -- prior choices on that model still win.
        if p_active.thinking_levels then
          local new_m = MODELS[prefs.model_idx] or MODELS[1]
          prefs.thinking_idx = PROVIDERS.load_thinking_idx(p_active, new_m)
        end
        if prov_id == "google" then Net.gemini_cache_invalidate() end
        S.api_ref_message = nil
        for _, att in ipairs(S.attachments) do
          att.cost = att.tokens * raw_m.price_in / 1000000
        end
      end
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_card_popup_style()

  -- ---- Thinking chip (only when provider has thinking levels) ------------
  if p_active.thinking_levels then
    local active_model = p_active.models[prefs.model_idx] or p_active.models[1]
    local vis = {}
    for i, tl in ipairs(p_active.thinking_levels) do
      if not tl.flash_only or (active_model and active_model.is_flash) then
        vis[#vis+1] = { idx = i, label = tl.label }
      end
    end
    local cur = p_active.thinking_levels[prefs.thinking_idx]
    local tl_label = (cur and cur.label or "THINK"):upper()
    local tl_cx1, tl_clicked = draw_chip(tl_label, "##mm_tl_btn", not req_live,
      "Thinking depth: higher tiers think longer (smarter, slower, more expensive).")
    if tl_clicked then ImGui.ImGui_OpenPopup(RA.ctx, "##mm_tl_popup") end
    ImGui.ImGui_SetNextWindowPos(RA.ctx, tl_cx1, y2 + RA.SC(2))
    UI.push_card_popup_style()
    if ImGui.ImGui_BeginPopup(RA.ctx, "##mm_tl_popup") then
      -- Header label, matching the Provider / Model dropdowns.
      ImGui.ImGui_TextDisabled(RA.ctx, "Thinking:")
      ImGui.ImGui_Separator(RA.ctx)
      -- Same asterisk convention as the model dropdown: marks the
      -- recommended thinking level for the active model. Cascade is the
      -- same one PROVIDERS.load_thinking_idx uses for first-touch
      -- defaults -- model.default_thinking_idx -> provider.
      -- default_thinking_idx -> nil. Nil means no badge (custom
      -- providers that haven't configured a default).
      local rec_t_idx = (active_model and active_model.default_thinking_idx)
                         or p_active.default_thinking_idx
      for _, v in ipairs(vis) do
        local t_pfx = (v.idx == rec_t_idx) and "* " or "  "
        if ImGui.ImGui_MenuItem(RA.ctx, t_pfx .. v.label, nil, v.idx == prefs.thinking_idx) then
          prefs.thinking_idx = v.idx
          -- Save under the per-model slot via the helper. Falls back to
          -- the legacy per-provider key only when no model id is available.
          local active_m = MODELS[prefs.model_idx] or MODELS[1]
          PROVIDERS.save_thinking_idx(p_active, active_m, prefs.thinking_idx)
        end
        -- Hover tooltip: show the (provider, model, this-thinking) explainer
        -- line so the user can preview each row's tradeoff before clicking.
        -- Same lookup the muted line below the chip row uses; here it
        -- previews each option, while the muted line summarizes the
        -- current pick. Custom providers without COMBO_HINTS entries
        -- return nil and skip the tooltip.
        local tl_obj = p_active.thinking_levels[v.idx]
        local hint   = UI.combo_hint(p_active, active_model, tl_obj)
        if hint then UI.tooltip_v5(hint) end
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    -- Use the helper instead of duplicating the pop sequence inline. If
    -- push_card_popup_style ever changes its push counts (e.g. adds a
    -- fourth color or a font-weight push) a manual three-pop block here
    -- would silently leave the style stack imbalanced.
    UI.pop_card_popup_style()
  end

  -- ---- Ask | Auto-Run segmented pill --------------------------------------
  -- Placed AFTER the provider/model/thinking chips so the row reads in a
  -- logical order: pick what AI to use first, then pick how it behaves.
  PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
  local ask_tw  = CalcTextSize(RA.ctx, "ASK")
  local auto_tw = CalcTextSize(RA.ctx, "AUTO-RUN")
  PopFont(RA.ctx)
  local s1w = ask_tw  + SEG_PAD_X * 2
  local s2w = auto_tw + SEG_PAD_X * 2
  local pill_w = s1w + s2w + INNER_PAD * 2
  local px1, px2 = cursor_x, cursor_x + pill_w

  ImGui.ImGui_DrawList_AddRectFilled(dl, px1, y1, px2, y2, TK.card, ROUND_PILL)
  ImGui.ImGui_DrawList_AddRect      (dl, px1, y1, px2, y2, TK.border, ROUND_PILL)

  local s1x1 = px1 + INNER_PAD
  local s1x2 = s1x1 + s1w
  local s2x1 = s1x2
  local s2x2 = px2 - INNER_PAD
  local act_y1, act_y2 = y1 + INNER_PAD, y2 - INNER_PAD

  local auto_on = prefs.auto_run
  local ax1 = auto_on and s2x1 or s1x1
  local ax2 = auto_on and s2x2 or s1x2
  -- Active segment fill:
  --   ASK       -> TK.accent_ui (the default "interactive accent"
  --                voice shared with toggles, card dots, send button).
  --   AUTO-RUN  -> TK.autorun_fill (soft pink in light mode, a darker
  --                muted rose in dark mode -- theme-aware via the
  --                palette tokens). Distinct from the error-red so it
  --                reads as a gentle "risky mode active" cue rather
  --                than "something is wrong".
  local active_fill = auto_on and TK.autorun_fill or TK.accent_ui
  ImGui.ImGui_DrawList_AddRectFilled(dl, ax1, act_y1, ax2, act_y2, active_fill, ROUND_SEG)

  -- Active-segment label color. Both ASK-on-accent and AUTO-RUN-on-pink
  -- use TK.accent_text (white) -- good contrast against both fills.
  PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
  ImGui.ImGui_DrawList_AddText(dl, s1x1 + SEG_PAD_X, t_y,
    auto_on and TK.text_muted or TK.accent_text, "ASK")
  ImGui.ImGui_DrawList_AddText(dl, s2x1 + SEG_PAD_X, t_y,
    auto_on and TK.accent_text or TK.text_muted, "AUTO-RUN")
  PopFont(RA.ctx)

  ImGui.ImGui_BeginDisabled(RA.ctx, req_live)
  local ask_clicked = btn_at("##mm_ask_seg", s1x1, s1w, ROW_H - INNER_PAD * 2)
  UI.tooltip_v5("Ask mode: replies only; returned code waits for you to click Run.")
  if ask_clicked and auto_on then
    prefs.auto_run = false
    reaper.SetExtState(CFG.EXT_NS, "auto_run", "0", true)
  end
  local auto_clicked = btn_at("##mm_autorun_seg", s2x1, s2w, ROW_H - INNER_PAD * 2)
  UI.tooltip_v5("Auto-Run: returned code runs automatically after the reply arrives.")
  if auto_clicked and not auto_on then
    prefs.auto_run = true
    reaper.SetExtState(CFG.EXT_NS, "auto_run", "1", true)
  end
  ImGui.ImGui_EndDisabled(RA.ctx)
  cursor_x = px2 + ROW_GAP

  -- ---- Inline label-toggle helper (used for details / backup) -------------
  -- Renders "<label>: <state>" at `x1` in mono font. The label prefix stays
  -- textMuted; the state suffix is accent-coloured when `on` is true, else
  -- textMuted. Returns the clicked state and the total width drawn.
  local function inline_toggle(id, label, on, tooltip_text, x1)
    PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
    local prefix = label .. ": "
    local suffix = on and "on" or "off"
    local pfx_w  = CalcTextSize(RA.ctx, prefix)
    local sfx_w  = CalcTextSize(RA.ctx, suffix)
    PopFont(RA.ctx)
    local w = pfx_w + sfx_w
    local clicked = btn_at(id, x1, w, ROW_H)
    UI.tooltip_v5(tooltip_text)
    PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
    ImGui.ImGui_DrawList_AddText(dl, x1,         t_y, TK.text_muted, prefix)
    ImGui.ImGui_DrawList_AddText(dl, x1 + pfx_w, t_y,
      on and TK.accent_ui or TK.text_muted, suffix)
    PopFont(RA.ctx)
    return clicked, w
  end

  -- ---- backup: on|off -----------------------------------------------------
  local bak_clicked, bak_w = inline_toggle(
    "##mm_backup_btn", "backup", prefs.auto_backup,
    "Backup: save a timestamped .rpp-bak before Auto-Run executes returned code.",
    cursor_x)
  if bak_clicked then
    prefs.auto_backup = not prefs.auto_backup
    reaper.SetExtState(CFG.EXT_NS, "auto_backup",
      prefs.auto_backup and "1" or "0", true)
  end
  cursor_x = cursor_x + bak_w

  -- Mid-dot separator between the two inline toggles -- same pattern as the
  -- session strip. Uses a small filled circle so we stay ASCII-only in source.
  local SEP_GAP = RA.SC(10)
  local dot_cx  = cursor_x + SEP_GAP
  local dot_cy  = y1 + ROW_H * 0.5
  ImGui.ImGui_DrawList_AddCircleFilled(dl, dot_cx, dot_cy, RA.SC(1.5), TK.text_faint, 8)
  cursor_x = cursor_x + SEP_GAP * 2

  -- ---- details: on|off ----------------------------------------------------
  local det_clicked = inline_toggle(
    "##mm_details_btn", "details", prefs.show_details,
    "Details: show model, token count, and cost under each message.",
    cursor_x)
  if det_clicked then
    prefs.show_details = not prefs.show_details
    reaper.SetExtState(CFG.EXT_NS, "show_details",
      prefs.show_details and "1" or "0", true)
  end

  -- Advance the layout cursor past the row. InvisibleButton calls moved the
  -- cursor around via SetCursorScreenPos, so restore to a clean position.
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, sx, sy)
  ImGui.ImGui_Dummy(RA.ctx, 1, ROW_H)

  -- Combo hint below the chip row: a single muted line describing the
  -- current (provider, model, thinking) pick in the format
  -- "Best for | Cost | Speed | Note" -- e.g.
  -- "Simple and complex | Mid-cost | Very fast | Recommended OpenAI default"
  -- or "Avoid long prompts | Higher cost | Very slow (hits timeouts) |
  -- Use None or Opus None". Lookup table lives in UI.COMBO_HINTS (source
  -- of truth: Dev/Model_Info.md). Custom providers and uncovered combos
  -- return nil and the line just doesn't render. Rendered in the
  -- whitespace between the chip row and the footer rail, left-aligned
  -- with the page content edge (sx + PAD_X -- same origin the CLAUDE chip
  -- uses), nudged up 1px. Same font + muted color the prior tier-warning
  -- toast used; no fade since the line is keyed off the active selection
  -- rather than a transient event.
  do
    local active_m  = MODELS[prefs.model_idx] or MODELS[1]
    local active_tl = p_active.thinking_levels
                      and p_active.thinking_levels[prefs.thinking_idx]
                      or nil
    local hint = UI.combo_hint(p_active, active_m, active_tl)
    if hint then
      -- Selection-change-triggered fade: hold for HOLD_S then fade over
      -- FADE_S. The signature (provider|model|thinking) is rebuilt every
      -- frame; whenever it changes, the visibility deadline pushes
      -- forward so the user gets a fresh read after each pick. Window
      -- close/reopen resets S.combo_hint_sig (S.* lives in script state)
      -- so a freshly-opened ReaAssist also flashes the line on first
      -- render.
      local HOLD_S = 10.0
      local FADE_S = 0.5
      local sig = (p_active and p_active.id or "") .. "|"
                .. (active_m and active_m.id or "") .. "|"
                .. (active_tl and active_tl.value or "")
      if sig ~= S.combo_hint_sig then
        -- First render after script launch: S.combo_hint_sig is nil. Just
        -- prime the signature so the line stays hidden on launch -- only
        -- a real user pick (provider/model/thinking change) should make
        -- it appear and fade.
        if S.combo_hint_sig ~= nil then
          S.combo_hint_until = time_precise() + HOLD_S + FADE_S
        end
        S.combo_hint_sig = sig
      end
      local now   = time_precise()
      local end_t = S.combo_hint_until or 0
      local alpha = 1.0
      if now >= end_t then
        alpha = 0
      elseif now > end_t - FADE_S then
        alpha = (end_t - now) / FADE_S
      end
      if alpha > 0 then
        local base   = TK.text_muted
        local fade_c = (base & 0xFFFFFF00)
                       | math_floor((base & 0xFF) * alpha + 0.5)
        PushFont(RA.ctx, nil, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), fade_c)
        local _, cy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        ImGui.ImGui_SetCursorScreenPos(RA.ctx, sx + PAD_X + RA.SC(2), cy - RA.SC(3))
        Text(RA.ctx, hint)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
      end
    end
  end

  -- tooltip_render_v5() lives at the end of UI.footer_rail_v5 -- it's the
  -- last V5 element rendered so we only call it once per frame.
end

-- V5 Footer rail -- spans the full window width beneath the mode+model row.
-- Left: "by Michael Briggs Mastering" + version
-- Right: heart Donate, Credits, [Copy when chat has messages], Help, settings icon
-- Drawn entirely with draw list + InvisibleButton overlays for click/hover so
-- we get a recessed bg + 1px top border without fighting ImGui button style.
function UI.footer_rail_v5()
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)

  -- PAD_X chosen so `sx + PAD_X` (the "by Michael" left edge) lands at
  -- SC(22) from the window edge -- matches the Settings body's
  -- BODY_PAD_X, so the footer text column lines up with the content
  -- column above it.
  local PAD_X   = RA.SC(11)
  local ROW_H   = RA.SC(32)
  local GAP     = RA.SC(14)   -- gap between right-side items
  local TXT_SZ  = RA.SC(11)
  local MONO_SZ = RA.SC(10)   -- mono 9.5 rounded to 10
  local ICON_SZ = RA.SC(14)

  -- Capture the caller's cursor so we can restore it before returning.
  -- The rail repositions the cursor to the window-bottom row via
  -- SetCursorScreenPos to draw its hit-tested links; without restoring,
  -- ImGui's CursorMaxPos tracker gets clobbered and the scroll region
  -- shrinks. Every caller would otherwise need the same save/restore
  -- dance, so doing it here keeps call sites to a single line.
  local _saved_cx, _saved_cy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)

  -- Pin to the window's bottom edge regardless of the caller's cursor,
  -- so the rail lands in the same place on every screen and the text
  -- stays vertically centered inside the ROW_H strip.
  local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
  local win_w, win_h = ImGui.ImGui_GetWindowSize(RA.ctx)
  local sy = win_y + win_h - ROW_H
  local sx = win_x + PAD_X
  local avail_w = win_w - PAD_X * 2
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, sx, sy)

  -- Background + top border. Extend to the window's true edges (past
  -- WindowPadding) so the footer reads as a proper bottom strip.
  local bg_x1 = win_x
  local bg_x2 = win_x + win_w
  local bg_y2 = win_y + win_h
  ImGui.ImGui_DrawList_AddRectFilled(dl, bg_x1, sy, bg_x2, bg_y2, TK.footer_bg)
  ImGui.ImGui_DrawList_AddLine(dl, bg_x1, sy, bg_x2, sy, TK.border, 1)

  local y_mid = sy + ROW_H * 0.5

  -- Footer text metrics are entirely invariant per UI scale. Without this
  -- cache, every screen's footer rail re-pushed two fonts and called
  -- CalcTextSize four times per frame for "M", "by ", "Michael Briggs
  -- Mastering", and the version string -- pure waste at 60 fps. Cache
  -- key bundles the three font sizes since a UI scale change drops new
  -- values into all of them simultaneously.
  UI._footer_metrics = UI._footer_metrics or {}
  local _fm_key = TXT_SZ .. ":" .. MONO_SZ .. ":v" .. CFG.VERSION
  local _fm = UI._footer_metrics[_fm_key]
  if not _fm then
    _fm = {}
    PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
    _, _fm.th_inter = CalcTextSize(RA.ctx, "M")
    _fm.by_w   = CalcTextSize(RA.ctx, "by ")
    _fm.name_w = CalcTextSize(RA.ctx, "Michael Briggs Mastering")
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.mono_reg, MONO_SZ)
    _, _fm.th_mono = CalcTextSize(RA.ctx, "M")
    _fm.ver_w  = CalcTextSize(RA.ctx, "v" .. CFG.VERSION)
    PopFont(RA.ctx)
    UI._footer_metrics[_fm_key] = _fm
  end
  local th_inter = _fm.th_inter
  local th_mono  = _fm.th_mono
  local y_inter = math_floor(y_mid - th_inter * 0.5)
  local y_mono  = math_floor(y_mid - th_mono  * 0.5)
  local y_icon  = math_floor(y_mid - ICON_SZ  * 0.5)

  -- ---- LEFT SIDE: "by Michael Briggs Mastering" + version -----------------
  local by_w   = _fm.by_w
  local name_w = _fm.name_w
  local left_x = sx + PAD_X

  PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
  ImGui.ImGui_DrawList_AddText(dl, left_x, y_inter, TK.text_faint, "by ")
  PopFont(RA.ctx)

  -- Clickable author link: InvisibleButton sized to the name bounding box
  -- so hover + click route through ImGui. Color lightens on hover to signal
  -- the link affordance.
  local name_x = left_x + by_w
  local name_btn_h = RA.SC(18)
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, name_x, math_floor(y_mid - name_btn_h * 0.5))
  local name_clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##fr_author_link", name_w, name_btn_h)
  local name_hov = ImGui.ImGui_IsItemHovered(RA.ctx)
  if name_hov then ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand()) end
  UI.tooltip_v5("Request a free sample master")
  if name_clicked then UI.open_url("https://michaelbriggsmastering.com/?mtm_campaign=reaassist") end
  local name_col = name_hov and TK.text or TK.text_muted
  PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
  ImGui.ImGui_DrawList_AddText(dl, name_x, y_inter, name_col, "Michael Briggs Mastering")
  PopFont(RA.ctx)
  -- Subtle underline beneath the name -- slightly brighter on hover for the
  -- same visual "hot" feedback the link color change gives.
  local uy = y_inter + th_inter + RA.SC(1)
  ImGui.ImGui_DrawList_AddLine(dl,
    name_x,          uy,
    name_x + name_w, uy,
    name_hov and TK.text_muted or TK.text_faint, 1)

  -- Version number after a small gap. Doubles as a hidden "check for
  -- updates" link: visually identical to a plain text label so the
  -- page stays clean, but hovering reveals the hand cursor + tooltip,
  -- and clicking fires Updater.manual_check. The tooltip swaps to a
  -- "last checked N ago" string after the first successful check in
  -- the session so the user sees explicit up-to-date status. Busy
  -- states (another check already in flight) route through the usual
  -- force_reinstall / manual_check guards so a second click is a
  -- harmless no-op.
  local ver_str = "v" .. CFG.VERSION
  local ver_w = _fm.ver_w
  local ver_x = left_x + by_w + name_w + RA.SC(12)
  local ver_btn_h = RA.SC(18)
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, ver_x,
    math_floor(y_mid - ver_btn_h * 0.5))
  local ver_busy = Updater.is_busy()
  local ver_disabled = ver_busy or CFG.UPDATE_BASE_URL == ""
  ImGui.ImGui_BeginDisabled(RA.ctx, ver_disabled)
  local ver_clicked = ImGui.ImGui_InvisibleButton(RA.ctx,
    "##fr_version_check", ver_w, ver_btn_h)
  local ver_hov = (not ver_disabled) and ImGui.ImGui_IsItemHovered(RA.ctx)
  if ver_hov then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
  end
  -- Tooltip text: if we have a recorded successful check, show a
  -- human-friendly "ago" string; otherwise default to the prompt.
  -- Computed once when hover begins and frozen for the lifetime of
  -- the hover. Recomputing every frame would tick "Ns ago" forward
  -- each second, and tooltip_v5 treats text changes as a new tooltip
  -- (restarting the fade-in), which reads as a flicker every second.
  local ver_tip
  if ver_busy then
    S._fr_ver_tip = nil
    ver_tip = "Update check in progress..."
  elseif CFG.UPDATE_BASE_URL == "" then
    S._fr_ver_tip = nil
    ver_tip = "Update checks not available in this build"
  elseif ver_hov then
    if not S._fr_ver_tip then
      if update._last_ok_at then
        local dt = os.time() - update._last_ok_at
        local ago
        if     dt < 5     then ago = "just now"
        elseif dt < 60    then ago = dt .. "s ago"
        elseif dt < 3600  then ago = math.floor(dt / 60)   .. "m ago"
        elseif dt < 86400 then ago = math.floor(dt / 3600) .. "h ago"
        else                   ago = math.floor(dt / 86400) .. "d ago"
        end
        S._fr_ver_tip = "Up to date (checked " .. ago .. ")\nClick to check again"
      else
        S._fr_ver_tip = "Click to check for updates"
      end
    end
    ver_tip = S._fr_ver_tip
  else
    S._fr_ver_tip = nil
    ver_tip = "Click to check for updates"
  end
  UI.tooltip_v5(ver_tip)
  ImGui.ImGui_EndDisabled(RA.ctx)
  if ver_clicked and not ver_disabled then
    Updater.manual_check()
  end
  -- Color picks up a subtle brightening on hover to reinforce the
  -- click affordance discovered via the cursor / tooltip.
  local ver_col = ver_hov and TK.text_muted or TK.text_faint
  PushFont(RA.ctx, FONT.mono_reg, MONO_SZ)
  ImGui.ImGui_DrawList_AddText(dl, ver_x, y_mono, ver_col, ver_str)
  PopFont(RA.ctx)

  -- ---- RIGHT SIDE: drawn right-to-left --------------------------------------
  local req_live = (S.status == "waiting")
  local right_edge = sx + avail_w - PAD_X
  local cursor_x = right_edge

  -- Text-link drawer. Renders an Inter 11px text at cursor_x (right-aligned
  -- against cursor_x), registers an InvisibleButton for click/hover, fires
  -- on_click when pressed. Returns nothing; advances cursor_x leftward.
  local function text_link(id, text, tip, on_click, enabled)
    enabled = enabled ~= false
    -- Cache per-link text width keyed on (TXT_SZ, text). Each frame
    -- previously pushed Inter Reg + measured the (constant) link label
    -- ("Help", "Copy", "Credits", "Donate"...) just to advance cursor_x.
    local _tk = "f" .. TXT_SZ .. ":" .. text
    local tw = _fm[_tk]
    if not tw then
      PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
      tw = CalcTextSize(RA.ctx, text)
      PopFont(RA.ctx)
      _fm[_tk] = tw
    end
    local y_h = RA.SC(22)
    local x1  = cursor_x - tw
    ImGui.ImGui_SetCursorScreenPos(RA.ctx, x1, math_floor(y_mid - y_h * 0.5))
    ImGui.ImGui_BeginDisabled(RA.ctx, not enabled)
    local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, id, tw, y_h)
    local hov = enabled and ImGui.ImGui_IsItemHovered(RA.ctx)
    if hov then ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand()) end
    UI.tooltip_v5(tip)
    ImGui.ImGui_EndDisabled(RA.ctx)
    local col = enabled and (hov and TK.text or TK.text_muted) or TK.text_faint
    PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
    ImGui.ImGui_DrawList_AddText(dl, x1, y_inter, col, text)
    PopFont(RA.ctx)
    if clicked then on_click() end
    cursor_x = x1 - GAP
  end

  -- Settings gear (rightmost). Icon-only, larger tap zone, accent-tinted when
  -- no API keys are configured so the user notices.
  do
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    local iw = CalcTextSize(RA.ctx, ICON.SETTINGS)
    PopFont(RA.ctx)
    local y_h = RA.SC(24)
    local tap_pad = RA.SC(4)
    local x1 = cursor_x - iw
    ImGui.ImGui_SetCursorScreenPos(RA.ctx,
      x1 - tap_pad, math_floor(y_mid - y_h * 0.5))
    ImGui.ImGui_BeginDisabled(RA.ctx, req_live)
    local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##fr_settings",
      iw + tap_pad * 2, y_h)
    local hov = not req_live and ImGui.ImGui_IsItemHovered(RA.ctx)
    if hov then ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand()) end
    UI.tooltip_v5("Settings: API keys, preferences, and display options.")
    ImGui.ImGui_EndDisabled(RA.ctx)
    -- Accent tint when no key is configured for any provider (draws eye).
    -- Suppressed while the user is already on an api_keys flow screen --
    -- they don't need the nudge when the keys UI is on-screen. Hidden
    -- experimental providers do not count: they cannot be configured from
    -- the visible Settings UI, so a stranded key on one of them must not
    -- suppress the accent for users who have no other key set.
    local keys_set = 0
    for _, pk in ipairs(PROVIDERS) do
      if not pk.hidden and (pk.is_custom or S.api_key_map[pk.id]) then
        keys_set = keys_set + 1
      end
    end
    local col
    if keys_set == 0 and not api_keys.screen then
      col = TK.accent
    else
      col = hov and TK.text or TK.text_muted
    end
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    ImGui.ImGui_DrawList_AddText(dl, x1, y_icon, col, ICON.SETTINGS)
    PopFont(RA.ctx)
    if clicked then
      if api_keys.screen == "settings" then
        -- Toggle off: fire the same "cancel" signal the screen's own
        -- Cancel button uses, so unsaved changes still prompt the
        -- confirm popup. The Settings render path consumes this flag
        -- at the top of its frame and clears it.
        S._settings_request_cancel = true
      else
        -- Toggle on: remember where we came from so the next click
        -- can restore it. Covers nav from chat ("") + from a help /
        -- credits / bug-report modal (captures those flags too).
        S._settings_return_to = {
          screen        = api_keys.screen,
          show_help     = S.show_help,
          show_bug      = S.show_bug_report,
          show_credits  = S.show_credits,
        }
        -- Close any currently-open modal screen so Settings dispatches.
        S.show_help        = false
        S.show_bug_report  = false
        S.show_credits     = false

        api_keys.screen          = "settings"
        api_keys.is_reentry      = true
        api_keys.key_bufs        = {}
        api_keys.key_errors      = {}
        api_keys.key_error       = nil
        api_keys.key_focused     = false
        api_keys.key_validating  = false
        -- Stash current Preferences values so Cancel / "unsaved" discard
        -- can revert them. Save persists + clears these; discard restores
        -- + clears. Keys get their own buffer flow above; everything
        -- below (both main + merged-Advanced prefs) lives here.
        api_keys.saved_ui_scale_idx         = prefs.ui_scale_idx
        api_keys.saved_theme                = prefs.theme
        api_keys.saved_update_check         = prefs.update_check
        api_keys.saved_auto_backup          = prefs.auto_backup
        api_keys.saved_chat_font_idx        = prefs.chat_font_idx
        api_keys.saved_include_snapshot     = prefs.include_snapshot
        api_keys.saved_include_api_ref      = prefs.include_api_ref
        api_keys.saved_cloud_request_timeout = prefs.cloud_request_timeout
        -- Section-open state (per Settings session; not persisted across
        -- script reloads). API KEYS + PREFERENCES default open, ADVANCED
        -- defaults closed so the destructive actions stay tucked away.
        api_keys.section_open = {
          api  = true,
          pref = true,
          adv  = false,
        }
        api_keys.key_validating_idx = nil
        api_keys.custom_edit = nil
      end
    end
    cursor_x = x1 - GAP
  end

  -- Theme toggle (immediately left of the gear). Icon shows the OTHER theme
  -- as the "destination" of a click -- sun means "click to go light",
  -- moon means "click to go dark". Auto mode resolves to its effective
  -- theme for icon display; clicking from Auto locks into the opposite
  -- specific theme. Users who want Auto back go through Settings.
  do
    local effective = resolve_theme(prefs.theme)
    local glyph = (effective == "dark") and ICON.SUN or ICON.MOON
    local next_theme = (effective == "dark") and "light" or "dark"
    local tt_text = (effective == "dark")
      and "Switch to light mode" or "Switch to dark mode"

    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    local iw = CalcTextSize(RA.ctx, glyph)
    PopFont(RA.ctx)
    local y_h = RA.SC(24)
    local tap_pad = RA.SC(4)
    local x1 = cursor_x - iw
    ImGui.ImGui_SetCursorScreenPos(RA.ctx,
      x1 - tap_pad, math_floor(y_mid - y_h * 0.5))
    local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##fr_theme",
      iw + tap_pad * 2, y_h)
    local hov = ImGui.ImGui_IsItemHovered(RA.ctx)
    if hov then ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand()) end
    UI.tooltip_v5(tt_text)
    local col = hov and TK.text or TK.text_muted
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    ImGui.ImGui_DrawList_AddText(dl, x1, y_icon, col, glyph)
    PopFont(RA.ctx)
    if clicked then
      prefs.theme = next_theme
      reaper.SetExtState(CFG.EXT_NS, "theme", prefs.theme, true)
      apply_palette(PALETTES[resolve_theme(prefs.theme)])
    end
    cursor_x = x1 - GAP
  end

  -- Help
  text_link("##fr_help", "Help",
    "View help and usage guide.",
    function()
      if S.show_help then
        -- Toggle off: restore the screen/modal context we captured
        -- when the link opened Help. Falls through to chat if nothing
        -- was captured (e.g. Help was opened via some other path).
        local ret = S._footer_help_ret
        S._footer_help_ret = nil
        S.show_help        = false
        api_keys.screen    = ret and ret.screen      or nil
        S.show_bug_report  = ret and ret.show_bug    or false
        S.show_credits     = ret and ret.show_credits or false
      else
        -- Toggle on: remember the current nav context so the next
        -- click restores it. The dispatcher only renders show_help
        -- when api_keys.screen is nil, so we clear that here.
        S._footer_help_ret = {
          screen       = api_keys.screen,
          show_bug     = S.show_bug_report,
          show_credits = S.show_credits,
        }
        api_keys.screen    = nil
        S.show_help        = true
        S.show_bug_report  = false
        S.show_credits     = false
      end
    end)

  -- Copy (only on the chat screen, and only when chat has messages).
  -- On every other screen (Settings / Advanced / Help / Credits /
  -- Bug Report etc.) the Copy link is hidden entirely -- it's not
  -- contextually meaningful when the chat isn't visible.
  local _on_chat_screen = (api_keys.screen == nil)
    and not S.show_help and not S.show_bug_report and not S.show_credits
  if _on_chat_screen and #S.display_messages > 0 then
    text_link("##fr_copy", "Copy",
      "Copy full chat history to clipboard.",
      function()
        local parts = {}
        parts[#parts+1] = CFG._PRODUCT .. " v" .. CFG.VERSION .. " - Chat Log"
        parts[#parts+1] = string.rep("-", 50)
        parts[#parts+1] = ""
        for _, msg in ipairs(S.display_messages) do
          if msg.role == "user" then
            parts[#parts+1] = "[USER]"
            parts[#parts+1] = msg.content or ""
            if msg.attach_names and #msg.attach_names > 0 then
              for _, aname in ipairs(msg.attach_names) do
                parts[#parts+1] = "  [Attachment: " .. aname .. "]"
              end
            end
            if msg.model_label then
              parts[#parts+1] = "  Model: " .. msg.model_label:gsub(" %b()", "")
            end
            if msg.thinking_label then
              parts[#parts+1] = "  Thinking: " .. msg.thinking_label
            end
            if msg.ctx_label then
              parts[#parts+1] = "  Context: " .. msg.ctx_label
            end
            if msg.tok_in then
              parts[#parts+1] = str_format("  Tokens: %d in / %d out",
                msg.tok_in, msg.tok_out or 0)
              local cr = msg.tok_cache_read or 0
              local cc = msg.tok_cache_create or 0
              if cr > 0 or cc > 0 then
                parts[#parts+1] = str_format("  Cache: %d read, %d created", cr, cc)
              end
              if msg.cost then
                if msg.free_tier then
                  parts[#parts+1] = "  Estimated cost: Free Tier (would have been ~"
                    .. MODELS.format_cost(msg.cost) .. ")"
                else
                  parts[#parts+1] = "  Estimated cost: " .. MODELS.format_cost(msg.cost)
                end
              end
            end
            if msg.response_time then
              parts[#parts+1] = str_format("  Response time: %.1fs", msg.response_time)
            end
            if msg.fx_cache_label then
              parts[#parts+1] = "  FX Cache: " .. msg.fx_cache_label
            end
          else
            parts[#parts+1] = "[ASSISTANT]"
            parts[#parts+1] = msg.content or ""
            if msg.code_block then
              parts[#parts+1] = "```" .. (msg.code_type or "lua")
              parts[#parts+1] = msg.code_block
              parts[#parts+1] = "```"
            end
          end
          parts[#parts+1] = ""
        end
        if S.session_tok_in > 0 then
          parts[#parts+1] = string.rep("-", 50)
          parts[#parts+1] = str_format("Session: %d in / %d out  |  Est. cost: %s",
            S.session_tok_in, S.session_tok_out, MODELS.format_cost(S.session_cost))
        end
        ImGui.ImGui_SetClipboardText(RA.ctx, tbl_concat(parts, "\n"))
        UI.show_float_toast("Chat copied to clipboard", "ok")
      end)
  end

  -- Credits (toggles like Help above -- full state capture/restore).
  text_link("##fr_credits", "Credits",
    "View credits.",
    function()
      if S.show_credits then
        local ret = S._footer_credits_ret
        S._footer_credits_ret = nil
        S.show_credits     = false
        api_keys.screen    = ret and ret.screen    or nil
        S.show_help        = ret and ret.show_help or false
        S.show_bug_report  = ret and ret.show_bug  or false
      else
        S._footer_credits_ret = {
          screen    = api_keys.screen,
          show_help = S.show_help,
          show_bug  = S.show_bug_report,
        }
        api_keys.screen    = nil
        S.show_help        = false
        S.show_bug_report  = false
        S.show_credits     = true
      end
    end)

  -- Donate (heart icon + label)
  do
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    local hw = CalcTextSize(RA.ctx, ICON.HEART)
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
    local lw = CalcTextSize(RA.ctx, "Donate")
    PopFont(RA.ctx)
    local inner_gap = RA.SC(5)
    local total_w = hw + inner_gap + lw
    local y_h = RA.SC(22)
    local x1  = cursor_x - total_w
    ImGui.ImGui_SetCursorScreenPos(RA.ctx, x1, math_floor(y_mid - y_h * 0.5))
    local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, "##fr_donate", total_w, y_h)
    local hov = ImGui.ImGui_IsItemHovered(RA.ctx)
    if hov then ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand()) end
    UI.tooltip_v5("Support ReaAssist development.")
    local col = hov and TK.text or TK.text_muted
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    ImGui.ImGui_DrawList_AddText(dl, x1, y_icon, col, ICON.HEART)
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.inter_reg, TXT_SZ)
    ImGui.ImGui_DrawList_AddText(dl, x1 + hw + inner_gap, y_inter, col, "Donate")
    PopFont(RA.ctx)
    if clicked then UI.open_url("https://www.paypal.com/paypalme/civil") end
    cursor_x = x1 - GAP
  end

  -- Single-frame tooltip render -- fed by tooltip_v5 calls in BOTH the
  -- mode/model row above and the footer links just drawn.
  UI.tooltip_render_v5()

  -- Restore the caller's cursor so the rail call is transparent to the
  -- surrounding layout. Without this, ImGui's CursorMaxPos climbs to
  -- the rail's SetCursorScreenPos(sx, sy) coordinates and the window
  -- reserves virtual height past the real content -- scroll region
  -- grows by ROW_H and the last content row becomes unreachable.
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, _saved_cx, _saved_cy)
end

-- Centered 20 px page title + short ice-blue accent underline beneath it.
-- `inner_w` is the content column width used for horizontal centering.
function UI.page_title(text, inner_w)
  PushFont(RA.ctx, nil, RA.SC(20))
  local tw = CalcTextSize(RA.ctx, text)
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - tw) * 0.5), 0))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)
  Text(RA.ctx, text)
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, 4)
  local accent_w, accent_h = RA.SC(42), RA.SC(2)
  local asx, asy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local ax       = asx + math_max(math_floor((inner_w - accent_w) * 0.5), 0)
  local adl      = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  ImGui.ImGui_DrawList_AddRectFilled(adl,
    ax, asy, ax + accent_w, asy + accent_h, COL.ASSIST, RA.SC(1))
  Dummy(RA.ctx, 1, accent_h)
end

-- V5 section label: short accent bar + mono label in TK.text_faint with
-- widened letter-spacing (+1px per gap). Used on Settings-family screens
-- to delineate groups of controls.
--
-- Two modes (first positional arg after `txt`):
--   1. Non-collapsible (is_open == nil): static label, no hit region.
--      Returns nothing. Reserves vertical space + breathing room.
--   2. Collapsible (is_open == boolean): the accent bar doubles as a
--      +/- glyph (horizontal bar = minus/open, horizontal+vertical =
--      plus/closed). Whole header row becomes a click target that
--      toggles the state. Hand cursor on hover. Returns the POST-click
--      open state so callers can do `open = v5_section_label("X", open)`.
--
-- Optional `right_text` (3rd arg): small Inter SC(10) note right-aligned
-- on the same line as the label. Used for section-level reassurances
-- (e.g. "Keys are obfuscated...") that would otherwise take their own
-- vertical row. Not clickable even when the section is collapsible.
--
-- Optional `size_scale` (4th arg): multiplies the label text, accent
-- bar, and gap sizes. Defaults to 1.0 (original SC(10) mono). Used
-- by the Help page so every section label responds to the in-page
-- text-size controls alongside the body.
--
-- Optional `color_override` (5th arg): 0xRRGGBBAA to use for the
-- label text regardless of hover state. Defaults to nil, which
-- keeps the original TK.text_faint (rest) / TK.text_muted (hover)
-- pair. Help uses this to run its section labels at TK.text_muted
-- (more readable when the labels are bumped up in size to serve as
-- proper chapter markers rather than thin UI group labels).
function UI.v5_section_label(txt, is_open, right_text, size_scale, color_override)
  local scale = size_scale or 1.0
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  local LABEL_SZ = RA.SC(math_floor(11 * scale + 0.5))
  local BAR_W    = RA.SC(math_floor(14 * scale + 0.5))
  local BAR_H    = RA.SC(2)
  local GAP      = RA.SC(8)
  local WIDE_KERN = math_max(1, math_floor(LABEL_SZ * 0.12))   -- +1 at default SC(11)

  local collapsible = (is_open ~= nil)

  -- Measure the label text up front so the whole row width can be
  -- computed for the click-target + the layout reservation below.
  PushFont(RA.ctx, FONT.mono_reg, LABEL_SZ)
  local chars, total_w = {}, 0
  for _, cp in utf8.codes(txt) do
    local ch = utf8.char(cp)
    local cw = CalcTextSize(RA.ctx, ch)
    chars[#chars+1] = { c = ch, w = cw }
    total_w = total_w + cw
  end
  PopFont(RA.ctx)
  if #chars > 1 then total_w = total_w + WIDE_KERN * (#chars - 1) end

  -- Hit region: the entire row width when collapsible, so users can
  -- click anywhere (not just the tiny 14px accent bar) to toggle.
  local new_open = is_open
  local hovered = false
  if collapsible then
    ImGui.ImGui_InvisibleButton(RA.ctx, "##v5_sec_" .. txt,
      avail_w, LABEL_SZ + RA.SC(2))
    hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
    if hovered then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      UI.tooltip(is_open and "Click to collapse this section"
                            or "Click to expand this section")
    end
    if ImGui.ImGui_IsItemClicked(RA.ctx) then
      new_open = not is_open
    end
  end

  -- Accent bar on the left, vertically centered on the label's cap line.
  -- Muted accent so the glyph reads as a quiet group marker.
  local bar_y   = sy + math_floor((LABEL_SZ - BAR_H) * 0.5) + RA.SC(1)
  local bar_col = UI.lerp_u32(TK.accent, TK.bg, 0.35)
  ImGui.ImGui_DrawList_AddRectFilled(dl,
    sx, bar_y, sx + BAR_W, bar_y + BAR_H,
    bar_col, RA.SC(1))
  -- Collapsible + closed => draw a vertical accent stroke through the
  -- bar's center, turning the minus into a plus.
  if collapsible and not is_open then
    local vbar_x_c = sx + math_floor(BAR_W * 0.5)
    local vbar_y1  = bar_y - math_floor(BAR_W * 0.5) + math_floor(BAR_H * 0.5)
    local vbar_y2  = vbar_y1 + BAR_W
    ImGui.ImGui_DrawList_AddRectFilled(dl,
      vbar_x_c - math_floor(BAR_H * 0.5), vbar_y1,
      vbar_x_c - math_floor(BAR_H * 0.5) + BAR_H, vbar_y2,
      bar_col, RA.SC(1))
  end

  -- Widened mono label (drawn char-by-char because ImGui has no
  -- letter-spacing style var). Hover lifts the label color slightly
  -- so the click affordance reads.
  local label_col = color_override
    or (hovered and TK.text_muted or TK.text_faint)
  local text_sx = sx + BAR_W + GAP
  local cur_sx  = text_sx
  for _, ch in ipairs(chars) do
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.mono_reg, LABEL_SZ,
      cur_sx, sy, label_col, ch.c)
    cur_sx = cur_sx + ch.w + WIDE_KERN
  end

  -- Optional right-aligned note (e.g. "Keys are obfuscated...").
  -- Drawn in Inter SC(10) / TK.text_faint so it reads as a quiet
  -- footnote next to the section heading, not a second heading. Uses
  -- Inter instead of mono because long disclaimers are impractical
  -- in fixed-width glyphs on a single line.
  if right_text and right_text ~= "" then
    local RIGHT_SZ = RA.SC(10)
    PushFont(RA.ctx, FONT.inter_reg, RIGHT_SZ)
    local rt_w = CalcTextSize(RA.ctx, right_text)
    PopFont(RA.ctx)
    local right_edge_x = sx + avail_w
    local rt_x = right_edge_x - rt_w
    -- Center the right-note vertically on the mono label's cap line.
    local rt_y = sy + math_floor((LABEL_SZ - RIGHT_SZ) * 0.5) + RA.SC(1)
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, RIGHT_SZ,
      rt_x, rt_y, TK.text_faint, right_text)
  end

  -- Reserve layout space for the row + breathing room underneath.
  -- (Non-collapsible path; collapsible already reserved space via
  -- InvisibleButton above, so just add the breathing-room Dummy.)
  if not collapsible then
    Dummy(RA.ctx, BAR_W + GAP + total_w, LABEL_SZ)
  end
  Dummy(RA.ctx, 1, RA.SC(6))

  if collapsible then return new_open end
end

-- Frame-captured flag: true if ANY popup was open at the start of this
-- frame (captured in loop() right after ImGui_Begin). Used by
-- UI.back_pressed() to ignore Esc when a popup is claiming it. Capturing
-- at frame start rather than at back_pressed call time avoids the race
-- where a popup handles its own Esc + calls CloseCurrentPopup, making
-- live ImGui_IsPopupOpen return false by the time the screen's back
-- handler runs.
UI._popup_was_open = false

-- Returns true if the user just triggered a "go back one screen" action
-- this frame -- Escape key OR mouse back button (MB4, index 3). ImGui
-- exposes up to 5 mouse buttons (0=Left, 1=Right, 2=Middle, 3=Back,
-- 4=Forward); 3/4 have no named enum, but the integer indices are
-- guaranteed stable per the ReaImGui docs.
--
-- Centralised so every page's back handler stays in sync -- adding a
-- new input (e.g. a back keybind) is a single edit here.
--
-- Suppressed when a modal popup was open at the start of this frame
-- (UI._popup_was_open). The popup's own Esc handling owns the key that
-- frame; letting the screen's back handler also fire would, for example,
-- close the Factory Reset confirm AND bubble Esc to Settings' cancel
-- flow, triggering the unsaved-changes prompt.
--
-- Only used on pages where Esc already meant "go back" (Help, Credits,
-- Bug Report, Settings cancel, Preferred Plugins, FX Cache, Custom
-- LLM). NOT used for popup dismissal, inline widget Esc (autocomplete
-- dropdown close), main-chat quit-confirm, or TOS exit -- those stay
-- Esc-only so MB4 doesn't accidentally wire itself into modal or
-- intra-widget logic.
function UI.back_pressed()
  if UI._popup_was_open then return false end
  return ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape())
      or ImGui.ImGui_IsMouseClicked(RA.ctx, 3)
end

-- True on the platform-conventional "save" key chord: Ctrl+S on Windows /
-- Linux, Cmd+S on macOS (Mod_Super maps to Cmd there). Used by page-level
-- Save buttons (Settings, Custom LLM, Preferred Plugins, Bug Report,
-- Pinned, User System Prompt) to fire alongside an explicit click. Same
-- modal guard as back_pressed -- a confirm popup over a save page must
-- not let Ctrl+S leak through to the underlying Save action.
function UI.is_save_shortcut()
  if UI._popup_was_open then return false end
  local key_s = ImGui.ImGui_Key_S()
  return ImGui.ImGui_IsKeyChordPressed(RA.ctx, ImGui.ImGui_Mod_Ctrl()  | key_s)
      or ImGui.ImGui_IsKeyChordPressed(RA.ctx, ImGui.ImGui_Mod_Super() | key_s)
end

-- "Pressable" feedback for the preceding ImGui_Button. Adds a 2 px inset
-- top shadow when the button is held, giving a subtle tactile "sink"
-- beyond ImGui's built-in ButtonActive color swap. Leak past rounded
-- corners is <= 2 px and not noticeable at typical FrameRounding.
function UI.pressable()
  if ImGui.ImGui_IsItemActive(RA.ctx) then
    local x1, y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
    local x2, _  = ImGui.ImGui_GetItemRectMax(RA.ctx)
    local dl     = ImGui.ImGui_GetWindowDrawList(RA.ctx)
    ImGui.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y1 + RA.SC(2), 0x00000055)
  end
end

-- V5 toggle: card-bg row with label left + 26x15 pill switch (white
-- knob) on the right. Whole row acts as the click target so the
-- toggle fires even on label hits, not just the switch glyph.
-- `width` (optional): forces the row to a specific pixel width.
-- Omit to span the full available content region. Pass an explicit
-- width when the caller wants the toggle's right edge to line up
-- with sibling widgets whose widths differ from GetContentRegionAvail
-- (e.g. BeginChild-bounded provider cards on Settings).
-- Returns (changed, new_on). `id` must include the ImGui ## suffix.
function UI.v5_toggle(id, label, on, tooltip, width)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local avail_w = width or ImGui.ImGui_GetContentRegionAvail(RA.ctx)

  local ROW_H     = RA.SC(30)
  local PAD_X     = RA.SC(12)
  local ROUND     = RA.SC(6)
  local LABEL_SZ  = RA.SC(12)
  local SW_W      = RA.SC(26)
  local SW_H      = RA.SC(15)
  local KNOB_R    = RA.SC(5)        -- 11px knob / 2
  local KNOB_PAD  = RA.SC(2)

  ImGui.ImGui_InvisibleButton(RA.ctx, id, avail_w, ROW_H)
  local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
  local clicked = ImGui.ImGui_IsItemClicked(RA.ctx)
  if hovered then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
  end
  if tooltip then UI.tooltip(tooltip) end

  local new_on = on
  if clicked then new_on = not on end

  -- Card bg + 1px border. Hover lifts the bg tone a touch.
  local bg_col = hovered and TK.card_hover or TK.card
  ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + avail_w, sy + ROW_H, bg_col, ROUND)
  ImGui.ImGui_DrawList_AddRect(dl, sx, sy, sx + avail_w, sy + ROW_H, TK.border, ROUND, 0, 1)

  -- Label, vertically centered on the label's cap line.
  PushFont(RA.ctx, FONT.inter_reg, LABEL_SZ)
  local _, lh = CalcTextSize(RA.ctx, "M")
  PopFont(RA.ctx)
  local label_y = sy + math_floor((ROW_H - lh) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, LABEL_SZ,
    sx + PAD_X, label_y, TK.text, label)

  -- Toggle pill + white knob on the right.
  local sw_x = sx + avail_w - PAD_X - SW_W
  local sw_y = sy + math_floor((ROW_H - SW_H) * 0.5)
  local sw_bg = new_on and TK.accent or TK.toggle_off_bg
  ImGui.ImGui_DrawList_AddRectFilled(dl,
    sw_x, sw_y, sw_x + SW_W, sw_y + SW_H, sw_bg, SW_H * 0.5)
  local knob_cx = new_on
    and (sw_x + SW_W - KNOB_PAD - KNOB_R)
    or  (sw_x + KNOB_PAD + KNOB_R)
  local knob_cy = sw_y + SW_H * 0.5
  ImGui.ImGui_DrawList_AddCircleFilled(dl, knob_cx, knob_cy, KNOB_R, 0xFFFFFFFF, 16)

  return (new_on ~= on), new_on
end

-- V5 nav row / nav button: card-bg clickable surface with a centered
-- label + right-pointing chevron content block. The label and the
-- chevron are treated as ONE centered content unit, so a short label
-- in a wider row reads as "balanced" rather than floating-to-the-left
-- with a chevron way off on the right.
--
-- Chrome matches V5 secondary buttons (SC(24) height, SC(5) rounding,
-- SC(11) label) so nav widgets can sit on the same row as action
-- buttons (e.g. "Test API Keys" + "Local & Custom Providers") without
-- height mismatch.
--
-- `width` (optional): forces the row to a specific pixel width. Omit
-- to span the full available content region.
-- `accent` (optional): when truthy, subtly tints the bg, border, and
-- chevron toward the theme accent so the row advertises that its
-- destination has active content. Tints stay light enough that the row
-- still reads as a settings card, not a primary CTA.
-- Returns `clicked` (bool).
function UI.v5_nav_row(id, label, tooltip, width, accent)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local w       = width or ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  local ROW_H    = RA.SC(30)
  local PAD_X    = RA.SC(12)
  local ROUND    = RA.SC(6)
  local LABEL_SZ = RA.SC(12)
  local GAP      = RA.SC(8)       -- gap between label and chevron
  local CV_SIZE  = RA.SC(4)       -- chevron radius from tip back to each endpoint

  ImGui.ImGui_InvisibleButton(RA.ctx, id, w, ROW_H)
  local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
  local clicked = ImGui.ImGui_IsItemClicked(RA.ctx)
  if hovered then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
  end
  if tooltip then UI.tooltip(tooltip) end

  local rest_bg, hover_bg, border_col, chev_col
  if accent then
    -- Light mode renders the accent at high contrast against a near-white
    -- card, so the same lerp factors that read as "subtle" in dark mode
    -- come across loud. Dial back bg/border tints on light; keep the
    -- chevron at full accent in both modes since it's a tiny stroke and
    -- carries the main "active content" signal.
    local light = (resolve_theme(prefs.theme) == "light")
    local bg_t     = light and 0.32 or 0.50
    local border_t = light and 0.30 or 0.45
    rest_bg    = UI.lerp_u32(TK.card,       TK.accent_soft, bg_t)
    hover_bg   = UI.lerp_u32(TK.card_hover, TK.accent_soft, bg_t)
    border_col = UI.lerp_u32(TK.border,     TK.accent,      border_t)
    chev_col   = TK.accent
  else
    rest_bg    = TK.card
    hover_bg   = TK.card_hover
    border_col = TK.border
    chev_col   = TK.text_muted
  end

  local bg_col = hovered and hover_bg or rest_bg
  ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + w, sy + ROW_H, bg_col, ROUND)
  ImGui.ImGui_DrawList_AddRect(dl, sx, sy, sx + w, sy + ROW_H, border_col, ROUND, 0, 1)

  -- Measure label to size the centered content block.
  PushFont(RA.ctx, FONT.inter_reg, LABEL_SZ)
  local label_tw, label_th = CalcTextSize(RA.ctx, label)
  PopFont(RA.ctx)

  -- Content block = [label | gap | chevron]. Width measured from the
  -- label's left edge to the chevron's tip (rightmost point of the `>`).
  local content_w     = label_tw + GAP + CV_SIZE
  local content_start = sx + math_max(math_floor((w - content_w) * 0.5), PAD_X)

  -- Label (vertically centered on the row).
  local label_y = sy + math_floor((ROW_H - label_th) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, LABEL_SZ,
    content_start, label_y, TK.text, label)

  -- Chevron: tip sits at content_start + label_tw + GAP + CV_SIZE so
  -- the glyph is flush-right against the end of the content block.
  UI._stroke_chevron_right(dl,
    content_start + label_tw + GAP + CV_SIZE,
    sy + ROW_H * 0.5,
    CV_SIZE, RA.SC(1.5), chev_col)

  return clicked
end

-- V5 action row: card-bg pill with a Lucide icon + label, no chevron.
-- Distinct from v5_nav_row (which implies navigation via its right-edge
-- chevron) because this button performs a one-shot action instead of
-- opening another screen. Hover sweeps the icon and label to TK.accent
-- for a unified active state like the rest of the V5 card-style buttons.
function UI.v5_action_row(id, icon, label, tooltip, width)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local w = width or ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  local ROW_H    = RA.SC(30)
  local PAD_X    = RA.SC(12)
  local ROUND    = RA.SC(6)
  local LABEL_SZ = RA.SC(12)
  local ICON_SZ  = RA.SC(14)
  local GAP      = RA.SC(8)

  ImGui.ImGui_InvisibleButton(RA.ctx, id, w, ROW_H)
  local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
  local clicked = ImGui.ImGui_IsItemClicked(RA.ctx)
  if hovered then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
    if tooltip then UI.tooltip(tooltip) end
  end

  local bg_col = hovered and TK.card_hover or TK.card
  ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + w, sy + ROW_H, bg_col, ROUND)
  ImGui.ImGui_DrawList_AddRect(dl, sx, sy, sx + w, sy + ROW_H, TK.border, ROUND, 0, 1)

  -- Measure label and icon so the combined content block can be centered.
  PushFont(RA.ctx, FONT.inter_reg, LABEL_SZ)
  local label_tw, label_th = CalcTextSize(RA.ctx, label)
  PopFont(RA.ctx)
  PushFont(RA.ctx, FONT.lucide, ICON_SZ)
  local icon_tw = CalcTextSize(RA.ctx, icon)
  PopFont(RA.ctx)

  local content_w     = icon_tw + GAP + label_tw
  local content_start = sx + math_max(math_floor((w - content_w) * 0.5), PAD_X)

  local icon_col = hovered and TK.accent or TK.text_muted
  local text_col = hovered and TK.accent or TK.text

  -- Icon: centered on the math midline (Lucide glyphs are already
  -- vertically balanced inside their bounding box).
  local icon_y = sy + math_floor((ROW_H - ICON_SZ) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.lucide, ICON_SZ,
    content_start, icon_y, icon_col, icon)

  -- Label: 1 px lift to balance Inter's baseline next to the icon.
  local label_y = sy + math_floor((ROW_H - label_th) * 0.5) - RA.SC(1)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, LABEL_SZ,
    content_start + icon_tw + GAP, label_y, text_col, label)

  return clicked
end

-- UI._stroke_chevron_right
-- ------------------------
-- Shared helper for every right-pointing chevron in the app (v5_nav_row,
-- button_chevron, ...). Uses DrawList_PathLineTo + PathStroke so the two
-- diagonals meet with a smooth mitered join rather than two separate
-- AddLine calls (which leaves a visible notch at the apex).
--
-- cx, cy are the CHEVRON TIP position (rightmost point of the `>` shape).
-- The two diagonals extend back (up-left and down-left) by `size`.
local function _stroke_chevron_right(dl, cx, cy, size, thickness, col)
  ImGui.ImGui_DrawList_PathLineTo(dl, cx - size, cy - size)
  ImGui.ImGui_DrawList_PathLineTo(dl, cx,        cy)
  ImGui.ImGui_DrawList_PathLineTo(dl, cx - size, cy + size)
  ImGui.ImGui_DrawList_PathStroke(dl, col, 0, thickness)
end
UI._stroke_chevron_right = _stroke_chevron_right


-- V5 link row: same card-bg pill chrome as UI.v5_nav_row, laid out as
-- a clickable "open external target" row. Three display modes driven
-- by the `label` argument:
--   label nil / ""  -> value left-aligned (just the URL/target)
--   label provided  -> muted descriptor on the left, value on the right
-- The icon at the far right is a Lucide glyph (ICON.LINK for websites,
-- ICON.MAIL for emails, ICON.PHONE for numbers) -- matches the rest of
-- the V5 Lucide iconography weight-wise.
--
-- Whole row is the click target; clicking fires UI.open_url(url), which
-- is safe for http(s) / mailto / tel schemes.
function UI.v5_link_row(id, label, value, url, icon, tooltip, width)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local w = width or ImGui.ImGui_GetContentRegionAvail(RA.ctx)
  local ROW_H    = RA.SC(30)
  local PAD_X    = RA.SC(12)
  local ROUND    = RA.SC(6)
  local LABEL_SZ = RA.SC(11)   -- muted descriptor
  local VALUE_SZ = RA.SC(12)   -- primary / link target
  local ICON_SZ  = RA.SC(14)   -- Lucide glyph; tuned to sit optically
                            -- balanced with the Inter SemiBold value
  local has_label = (label and label ~= "")

  ImGui.ImGui_InvisibleButton(RA.ctx, id, w, ROW_H)
  local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
  local clicked = ImGui.ImGui_IsItemClicked(RA.ctx)
  if hovered then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
    if tooltip then UI.tooltip(tooltip) end
  end

  local bg_col = hovered and TK.card_hover or TK.card
  ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + w, sy + ROW_H, bg_col, ROUND)
  ImGui.ImGui_DrawList_AddRect(dl, sx, sy, sx + w, sy + ROW_H, TK.border, ROUND, 0, 1)

  -- Left-leading icon (file-browser style: icon then name). Sits at
  -- PAD_X from the left edge; the value starts one ICON_GAP beyond
  -- the icon's right edge. When a descriptor label is present, the
  -- label slides between the icon and a right-aligned value.
  --
  -- Value rests in TK.text (not accent) -- the card pill chrome +
  -- icon + hover bg swap already over-signal clickability; bolding
  -- or colouring the text accent piled on top of that made the page
  -- shouty. Whole row sweeps to accent on hover (value + icon + bg
  -- together) for a strong unified active state.
  -- Optical vertical nudges vs the mathematical row midline. Text and
  -- icon sit at different sweet spots because Inter and Lucide have
  -- different baseline/ascent ratios -- text lifted 1 px balances the
  -- whitespace above vs below the glyphs at SC(12) Inter Regular, and
  -- icon at the exact math-midline reads right next to the lifted
  -- text (Lucide's bounding box is already vertically balanced).
  local ICON_Y_NUDGE = 0
  local TEXT_Y_NUDGE = RA.SC(1)
  local ICON_GAP = RA.SC(8)
  local icon_col = hovered and TK.accent or TK.text_muted
  local content_x = sx + PAD_X
  if icon then
    PushFont(RA.ctx, FONT.lucide, ICON_SZ)
    local iw = CalcTextSize(RA.ctx, icon)
    PopFont(RA.ctx)
    local icon_y = sy + math_floor((ROW_H - ICON_SZ) * 0.5) - ICON_Y_NUDGE
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.lucide, ICON_SZ,
      content_x, icon_y, icon_col, icon)
    content_x = content_x + iw + ICON_GAP
  end

  PushFont(RA.ctx, FONT.inter_reg, VALUE_SZ)
  local value_w = CalcTextSize(RA.ctx, value)
  PopFont(RA.ctx)
  local value_y = sy + math_floor((ROW_H - VALUE_SZ) * 0.5) - TEXT_Y_NUDGE
  local value_x
  if has_label then
    -- Descriptor label right after the icon, value right-aligned
    -- against the row's right padding.
    local label_y = sy + math_floor((ROW_H - LABEL_SZ) * 0.5) - TEXT_Y_NUDGE
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, LABEL_SZ,
      content_x, label_y, TK.text_muted, label)
    value_x = sx + w - PAD_X - value_w
  else
    value_x = content_x
  end
  local value_col = hovered and TK.accent or TK.text
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, VALUE_SZ,
    value_x, value_y, value_col, value)

  if clicked and url then UI.open_url(url) end
  return clicked
end

-- V5 select row: card-bg row with label left + custom-drawn chip-pill
-- on the right that matches the home-screen provider/model chips.
-- Chip has a mono-uppercase label + Lucide chevron; clicking opens a
-- card-styled popup (via UI.push_card_popup_style) listing items.
-- `items_str` is null-separated ("One\0Two\0Three\0"); `cur_idx` is
-- 0-based (matches ImGui_Combo return for easy drop-in). Returns
-- (changed, new_idx).
function UI.v5_select_row(id, label, items_str, cur_idx, tooltip, col_w)
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  local sx, sy  = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  local cur_x   = GetCursorPosX(RA.ctx)
  local cur_y   = ImGui.ImGui_GetCursorPosY(RA.ctx)

  local ROW_H      = RA.SC(30)
  local PAD_X      = RA.SC(12)
  local ROUND      = RA.SC(6)
  local LABEL_SZ   = RA.SC(12)
  local MONO_SIZE  = RA.SC(10)
  local CHEV_SIZE  = RA.SC(10)
  local CHIP_H     = RA.SC(20)
  local CHIP_PAD_X = RA.SC(9)
  local CHEV_GAP   = RA.SC(4)
  local ROUND_PILL = RA.SC(5)

  -- Card bg + border (the outer row).
  ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + col_w, sy + ROW_H, TK.card, ROUND)
  ImGui.ImGui_DrawList_AddRect(dl, sx, sy, sx + col_w, sy + ROW_H, TK.border, ROUND, 0, 1)

  -- Label on the left, vertically centered on its cap line.
  PushFont(RA.ctx, FONT.inter_reg, LABEL_SZ)
  local _, lh = CalcTextSize(RA.ctx, "M")
  PopFont(RA.ctx)
  local label_y = sy + math_floor((ROW_H - lh) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, LABEL_SZ,
    sx + PAD_X, label_y, TK.text, label)

  -- Extract current value text for the chip label; uppercase to match
  -- the home-screen provider/model chips (CLAUDE / AUTO / ASK style).
  -- The popup below still renders menu items in their original case.
  local cur_value, idx = "", 0
  for v in items_str:gmatch("[^%z]+") do
    if idx == cur_idx then cur_value = v; break end
    idx = idx + 1
  end
  local chip_label = cur_value:upper()

  -- Measure the chip: mono_med label + Lucide chevron + inner padding.
  PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
  local lw = CalcTextSize(RA.ctx, chip_label)
  PopFont(RA.ctx)
  PushFont(RA.ctx, FONT.lucide, CHEV_SIZE)
  local cw = CalcTextSize(RA.ctx, ICON.CHEVRON_DOWN)
  PopFont(RA.ctx)
  local chip_w  = CHIP_PAD_X * 2 + lw + CHEV_GAP + cw
  local chip_sx = sx + col_w - PAD_X - chip_w
  local chip_sy = sy + math_floor((ROW_H - CHIP_H) * 0.5)
  local chip_x2 = chip_sx + chip_w
  local chip_y2 = chip_sy + CHIP_H

  -- Tooltip-only hit region over the label area (left of the chip).
  -- Lets users hover anywhere on the row to discover what the setting
  -- does without swallowing chip clicks. No click handler, no cursor
  -- swap -- just a passive hover target that feeds the tooltip.
  if tooltip then
    local lbl_btn_w = chip_sx - sx - RA.SC(4)
    if lbl_btn_w > 0 then
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, sx, sy)
      ImGui.ImGui_InvisibleButton(RA.ctx, id .. "_lbl_hov", lbl_btn_w, ROW_H)
      UI.tooltip(tooltip)
    end
  end

  -- Invisible button over the chip -- routes hover/click/tooltip through
  -- standard ImGui item flow while the chip visuals are hand-drawn below.
  ImGui.ImGui_SetCursorScreenPos(RA.ctx, chip_sx, chip_sy)
  local clicked = ImGui.ImGui_InvisibleButton(RA.ctx, id, chip_w, CHIP_H)
  local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
  if hovered then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
  end
  if tooltip then UI.tooltip(tooltip) end

  -- Chip fill + border, matching the home mode/model chip exactly.
  ImGui.ImGui_DrawList_AddRectFilled(dl, chip_sx, chip_sy, chip_x2, chip_y2,
    hovered and TK.card_hover or TK.card, ROUND_PILL)
  ImGui.ImGui_DrawList_AddRect(dl, chip_sx, chip_sy, chip_x2, chip_y2,
    TK.border, ROUND_PILL, 0, 1)
  -- Mono-med label (uppercase). Use the actual measured text height
  -- (not MONO_SIZE) so the label sits on the chip's true optical
  -- center -- matches the home provider/model chip math.
  PushFont(RA.ctx, FONT.mono_med, MONO_SIZE)
  local _, mono_th = CalcTextSize(RA.ctx, "M")
  PopFont(RA.ctx)
  local t_y = chip_sy + math_floor((CHIP_H - mono_th) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.mono_med, MONO_SIZE,
    chip_sx + CHIP_PAD_X, t_y, TK.text, chip_label)
  -- Lucide chevron, centered vertically in the chip.
  local ch_y = chip_sy + math_floor((CHIP_H - CHEV_SIZE) * 0.5)
  ImGui.ImGui_DrawList_AddTextEx(dl, FONT.lucide, CHEV_SIZE,
    chip_sx + CHIP_PAD_X + lw + CHEV_GAP, ch_y,
    TK.text_muted, ICON.CHEVRON_DOWN)

  -- Open the popup on chip click; position it just below the chip.
  local popup_id = id .. "_popup"
  if clicked then ImGui.ImGui_OpenPopup(RA.ctx, popup_id) end
  ImGui.ImGui_SetNextWindowPos(RA.ctx, chip_sx, chip_y2 + RA.SC(2))
  UI.push_card_popup_style()
  local changed, new_idx = false, cur_idx
  if ImGui.ImGui_BeginPopup(RA.ctx, popup_id) then
    local i = 0
    for v in items_str:gmatch("[^%z]+") do
      if ImGui.ImGui_MenuItem(RA.ctx, v, nil, i == cur_idx) and i ~= cur_idx then
        new_idx = i
        changed = true
      end
      i = i + 1
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_card_popup_style()

  -- Restore cursor and reserve layout space for the row.
  ImGui.ImGui_SetCursorPos(RA.ctx, cur_x, cur_y)
  Dummy(RA.ctx, col_w, ROW_H)

  return changed, new_idx
end

-- =============================================================================
-- Utility: UI.selectable_text
-- =============================================================================
-- Renders chat content as a mix of selectable text blocks and ImGui tables.
-- Markdown table blocks (lines starting with |) are detected, parsed, and
-- rendered as real ImGui tables with auto-sized columns and monospace font.
-- All other text is word-wrapped and rendered as InputTextMultiline widgets
-- with transparent backgrounds so they blend into the chat pane.
-- Right-click context menus provide Copy Selection / Copy All / Copy Table.
--
-- IMPORTANT: Keep individual text blocks under ~5 KB. Passing a very large
-- buffer to ImGui_InputTextMultiline causes a C stack overflow in ReaImGui.
-- `chars_per_line_override`: when passed, skips the avail_w / avg_char_w
-- derivation and forces the wrap to a specific char count. Used by the user
-- bubble so its measurement-phase wrap config matches the render-phase wrap
-- config exactly (otherwise the bubble is sized for the measurement wrap
-- but the rendered wrap is tighter, leaving a visible right-side gap).
function UI.selectable_text(text, widget_id, avail_w, color, chars_per_line_override)
  -- Trim trailing whitespace, but keep raw text intact for heading detection.
  -- Headings need to be detected BEFORE strip_markdown so we can render them
  -- with a larger font; strip_markdown is applied per-segment below for the
  -- text segments that aren't headings or tables.
  local raw = (text or ""):match("^(.-)%s*$") or ""
  if #raw == 0 then raw = " " end

  local line_h = ImGui.ImGui_GetTextLineHeight(RA.ctx) + 2
  -- avg_char_w scales with the current font size (ratio 0.48 calibrated so
  -- that 14 px produces the original 6.75 value). Using a fixed 6.75 was
  -- wrong after the V5 chat font dropped to 12 px -- it over-estimated
  -- character width, wrapped too few chars per line, and left a visible
  -- right-side gap inside user bubbles.
  local avg_char_w     = ImGui.ImGui_GetFontSize(RA.ctx) * 0.48
  local chars_per_line = chars_per_line_override
    or math_floor(math_max(avail_w / avg_char_w, 20))

  -- Segment/full-text cache keyed by widget_id. The parse result (segments +
  -- full_text for Copy All) is purely a function of `raw`, so it only needs
  -- to be rebuilt when the underlying message content changes (streaming
  -- updates, edits). On cache hits we skip line-splitting, heading/table
  -- detection, and the per-segment strip_markdown passes -- a meaningful
  -- win at 60 fps once the chat history grows past a handful of messages.
  -- Cache grows at most to MAX_DISPLAY_MSGS; stale entries for pruned
  -- messages are reused by new messages that land on the same widget_id.
  UI._seg_cache = UI._seg_cache or {}
  local cached = UI._seg_cache[widget_id]
  local segments, full_text
  if cached and cached.raw == raw then
    segments  = cached.segments
    full_text = cached.full_text
  else
    -- Split raw text into lines, then group into segments: text / heading / table.
    local all_lines = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do all_lines[#all_lines+1] = line end

    -- Heading detector: 1-3 leading '#' followed by a space. Returns the level
    -- (1, 2, or 3) and the heading text, or nil if not a heading. Lines inside
    -- ``` fences would not reach here -- code blocks are handled outside
    -- selectable_text by the chat renderer.
    local function parse_heading(line)
      local hashes, rest = line:match("^(#+)%s+(.+)$")
      if not hashes then return nil end
      local lvl = #hashes
      if lvl < 1 or lvl > 3 then return nil end
      return lvl, rest
    end

    -- Hard cap per text segment. ReaImGui's InputTextMultiline crashes with a
    -- C stack overflow on very large buffers (observed around ~5 KB). Split
    -- long stripped blocks at line boundaries so each chunk stays well under
    -- the danger zone. The rare pathological case of a single line larger
    -- than the cap (e.g. a huge code-fenced JSON blob) falls back to a hard
    -- character-count split -- visible boundary, but no crash.
    local SEG_MAX_BYTES = 4096
    local function split_segment_text(t)
      if #t <= SEG_MAX_BYTES then return { t } end
      local chunks, cur, cur_len = {}, {}, 0
      for line in (t .. "\n"):gmatch("(.-)\n") do
        local line_len = #line + 1  -- +1 for the separating newline
        if line_len > SEG_MAX_BYTES then
          if cur_len > 0 then
            chunks[#chunks+1] = table.concat(cur, "\n")
            cur, cur_len = {}, 0
          end
          local pos = 1
          while pos <= #line do
            chunks[#chunks+1] = line:sub(pos, pos + SEG_MAX_BYTES - 1)
            pos = pos + SEG_MAX_BYTES
          end
        else
          if cur_len > 0 and cur_len + line_len > SEG_MAX_BYTES then
            chunks[#chunks+1] = table.concat(cur, "\n")
            cur, cur_len = {}, 0
          end
          cur[#cur+1] = line
          cur_len = cur_len + line_len
        end
      end
      if #cur > 0 then chunks[#chunks+1] = table.concat(cur, "\n") end
      return chunks
    end

    segments = {}  -- types: "text" | "table" | "heading"
    local li = 1
    while li <= #all_lines do
      local line = all_lines[li]
      if line:match("^%s*|") then
        local rows, next_i = parse_md_table(all_lines, li)
        if #rows > 0 then
          segments[#segments+1] = { type = "table", rows = rows }
        end
        li = next_i
      else
        local hl, htext = parse_heading(line)
        if hl then
          -- Heading line: stripped of markers and stored as its own segment.
          -- strip_markdown still runs over the inner text so **bold** etc. are
          -- cleaned up.
          segments[#segments+1] = {
            type  = "heading",
            level = hl,
            text  = UI.strip_markdown(htext),
          }
          li = li + 1
        else
          -- Collect contiguous non-table, non-heading lines into a text block.
          local text_lines = {}
          while li <= #all_lines do
            local cur = all_lines[li]
            if cur:match("^%s*|") then break end
            if parse_heading(cur) then break end
            text_lines[#text_lines+1] = cur
            li = li + 1
          end
          local block = table.concat(text_lines, "\n")
          if #block > 0 then
            local stripped = UI.strip_markdown(block)
            for _, chunk in ipairs(split_segment_text(stripped)) do
              segments[#segments+1] = { type = "text", text = chunk }
            end
          end
        end
      end
    end

    -- Build full plain text for "Copy All".
    local full_parts = {}
    for _, seg in ipairs(segments) do
      if seg.type == "text" then
        full_parts[#full_parts+1] = seg.text
      elseif seg.type == "heading" then
        full_parts[#full_parts+1] = seg.text
      else
        for _, cells in ipairs(seg.rows) do
          full_parts[#full_parts+1] = table.concat(cells, "\t")
        end
      end
    end
    full_text = table.concat(full_parts, "\n")

    UI._seg_cache[widget_id] = {
      raw       = raw,
      segments  = segments,
      full_text = full_text,
    }
  end

  -- Style shared across all segments.
  if color then PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), color) end

  for si, seg in ipairs(segments) do
    if seg.type == "heading" then
      -- Heading: render with a larger font via PushFont. Selectability is
      -- sacrificed (ImGui_Text is not part of an input widget) so the user
      -- can still grab the heading from the right-click "Copy All" or by
      -- selecting from the surrounding text segments.
      local size = (seg.level == 1) and RA.SC(22)
                or (seg.level == 2) and RA.SC(18)
                or RA.SC(16)
      ImGui.ImGui_Spacing(RA.ctx)
      PushFont(RA.ctx, nil, size)
      if color then PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), color) end
      ImGui.ImGui_TextWrapped(RA.ctx, seg.text)
      if color then PopStyleColor(RA.ctx) end
      PopFont(RA.ctx)

    elseif seg.type == "text" then
      -- Render text segment as selectable InputTextMultiline.
      local wrapped, lc = UI.get_wrap_cached(seg.text, chars_per_line)
      local seg_h = lc * line_h + 2
      local seg_id = widget_id .. "_s" .. si

      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),          0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),   0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),    0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(),  color or COL.CHAT_TEXT)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), 0, 0)
      -- ScrollbarSize = 0 so InputTextMultiline doesn't reserve right-side
      -- space for a scrollbar. Chat text is always sized to fit its content
      -- (widget height derived from line count), so a scrollbar is never
      -- needed.
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize(), 0)
      -- InputTextMultiline internally spins up a child window, and child
      -- windows apply WindowPadding (default ~8/8). That padding sits
      -- INSIDE the passed widget width, so the text ends up shifted right +
      -- wrapped early, creating a visible asymmetric right gap. Zeroing
      -- WindowPadding here makes the inner child flush with the widget
      -- rect so text starts at x = 0 and wraps at x = avail_w.
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), 0, 0)
      ImGui.ImGui_InputTextMultiline(RA.ctx, seg_id, wrapped, #wrapped + 1,
        avail_w, seg_h, ImGui.ImGui_InputTextFlags_CallbackAlways(), RA.sel_cb)
      -- Right-click menu.
      local sel_s = ImGui.ImGui_Function_GetValue(RA.sel_cb, "sel_start")
      local sel_e = ImGui.ImGui_Function_GetValue(RA.sel_cb, "sel_end")

      -- Unwrap helper: maps a selection range from the wrapped string back to
      -- the original (pre-wrap) text so that copied text doesn't contain the
      -- artificial line breaks inserted by word wrapping.
      local function unwrap_selection(a, b)
        local sel_wrapped = str_sub(wrapped, a + 1, b)
        -- Build a map of newline positions that exist in the original text.
        local orig_nls = {}
        for p in seg.text:gmatch("()\n") do orig_nls[p] = true end
        -- Walk both strings in sync to identify which wrapped newlines
        -- are original (keep) vs wrap-inserted (replace with space).
        local result = {}
        local wi = a + 1  -- position in wrapped string
        local oi = 1      -- position in original string
        -- Advance oi to match the start of the selection in wrapped.
        -- Both strings have the same characters except \n vs space at
        -- wrap points, so step through together.
        local sync_wi = 1
        while sync_wi < wi and oi <= #seg.text do
          local wc = str_sub(wrapped, sync_wi, sync_wi)
          local oc = str_sub(seg.text, oi, oi)
          if wc == oc then
            sync_wi = sync_wi + 1
            oi = oi + 1
          elseif wc == "\n" and oc == " " then
            -- wrap-inserted newline corresponds to original space
            sync_wi = sync_wi + 1
            oi = oi + 1
          elseif wc == "\n" then
            -- wrap-inserted newline with no corresponding space (word break)
            sync_wi = sync_wi + 1
          else
            sync_wi = sync_wi + 1
            oi = oi + 1
          end
        end
        -- Now extract the selection, replacing wrap newlines with spaces.
        for ci = 1, #sel_wrapped do
          local wc = str_sub(sel_wrapped, ci, ci)
          local oc = oi <= #seg.text and str_sub(seg.text, oi, oi) or ""
          if wc == "\n" and oc ~= "\n" then
            result[#result+1] = oc == " " and " " or " "
            if oc == " " then oi = oi + 1 end
          else
            result[#result+1] = wc
            oi = oi + 1
          end
        end
        return tbl_concat(result)
      end

      -- Intercept Ctrl+C / Cmd+C: overwrite clipboard with unwrapped text.
      if ImGui.ImGui_IsItemActive(RA.ctx) and sel_s ~= sel_e then
        local ctrl = ImGui.ImGui_Mod_Ctrl()
        if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_C())
          and (ImGui.ImGui_GetKeyMods(RA.ctx) & ctrl) == ctrl then
          local a, b = math_min(sel_s, sel_e), math_max(sel_s, sel_e)
          ImGui.ImGui_SetClipboardText(RA.ctx, unwrap_selection(a, b))
        end
      end

      -- Popup styling matches the V5 provider / model dropdowns (TK.card
      -- fill, strong border, mono-med font, SC padding) so all context
      -- menus read as one family. Pushed AFTER the InputTextMultiline
      -- render so we override the earlier FramePadding(0,0) +
      -- WindowPadding(0,0) + ScrollbarSize(0) stack for the popup window
      -- specifically. Pop in reverse before the outer pops run.
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(8),  RA.SC(8))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(10), RA.SC(6))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),   RA.SC(8),  RA.SC(4))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(), RA.SC(4))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(), TK.card)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border_str)
      PushFont(RA.ctx, FONT.mono_med, RA.SC(10))
      if ImGui.ImGui_BeginPopupContextItem(RA.ctx, seg_id .. "_ctx") then
        if sel_s ~= sel_e then
          if ImGui.ImGui_MenuItem(RA.ctx, "Copy Selection") then
            local a, b = math_min(sel_s, sel_e), math_max(sel_s, sel_e)
            ImGui.ImGui_SetClipboardText(RA.ctx, unwrap_selection(a, b))
          end
        end
        if ImGui.ImGui_MenuItem(RA.ctx, "Copy All") then
          ImGui.ImGui_SetClipboardText(RA.ctx, full_text)
        end
        ImGui.ImGui_EndPopup(RA.ctx)
      end
      PopFont(RA.ctx)
      PopStyleColor(RA.ctx, 2)  -- PopupBg, Border
      ImGui.ImGui_PopStyleVar(RA.ctx, 4)  -- WindowPadding, FramePadding, ItemSpacing, PopupRounding
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)  -- FramePadding, ScrollbarSize, WindowPadding
      PopStyleColor(RA.ctx, 4)  -- FrameBg x3, InputTextCursor

    else
      -- Render table segment as a real ImGui table.
      local num_cols = 0
      for _, cells in ipairs(seg.rows) do
        if #cells > num_cols then num_cols = #cells end
      end
      if num_cols > 0 then
        local tbl_id = widget_id .. "_t" .. si
        local tbl_flags = ImGui.ImGui_TableFlags_SizingFixedFit()
                        | ImGui.ImGui_TableFlags_BordersInnerV()
                        | ImGui.ImGui_TableFlags_PadOuterX()
        PushFont(RA.ctx, RA.code_font, RA.SC(12))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_CellPadding(), 5, 2)
        -- Pre-calculate max pixel width per column from cell content.
        local col_px = {}
        for c = 1, num_cols do col_px[c] = 0 end
        for _, cells in ipairs(seg.rows) do
          for c = 1, num_cols do
            local w = CalcTextSize(RA.ctx, cells[c] or "")
            if w > col_px[c] then col_px[c] = w end
          end
        end
        -- Fit all columns within avail_w: keep small columns at natural width,
        -- shrink only the oversized ones to fill remaining space.
        local pad_total = num_cols * 12  -- cell padding + borders
        local budget = avail_w - pad_total
        local total_w = 0
        for c = 1, num_cols do total_w = total_w + col_px[c] end
        if total_w > budget and budget > 0 then
          local fair = budget / num_cols
          -- First pass: lock columns that fit within fair share.
          local locked = 0
          local unlocked_w = 0
          local is_locked = {}
          for c = 1, num_cols do
            if col_px[c] <= fair then
              is_locked[c] = true
              locked = locked + col_px[c]
            else
              unlocked_w = unlocked_w + col_px[c]
            end
          end
          -- Second pass: distribute remaining budget among oversized columns.
          local remain = budget - locked
          for c = 1, num_cols do
            if not is_locked[c] then
              if unlocked_w > 0 then
                col_px[c] = math_max(40, math_floor(remain * col_px[c] / unlocked_w))
              else
                col_px[c] = math_max(40, math_floor(remain / num_cols))
              end
            end
          end
        end
        if ImGui.ImGui_BeginTable(RA.ctx, tbl_id, num_cols, tbl_flags, avail_w) then
          -- Set up columns with explicit widths.
          for c = 1, num_cols do
            ImGui.ImGui_TableSetupColumn(RA.ctx, "##c" .. c,
              ImGui.ImGui_TableColumnFlags_WidthFixed(), col_px[c])
          end
          -- First row as header if more than 1 row.
          local start_row = 1
          if #seg.rows > 1 then
            ImGui.ImGui_TableNextRow(RA.ctx)
            for c = 1, num_cols do
              ImGui.ImGui_TableSetColumnIndex(RA.ctx, c - 1)
              local val = seg.rows[1][c] or ""
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.DETAIL)
              ImGui.ImGui_TextWrapped(RA.ctx, val)
              PopStyleColor(RA.ctx)
            end
            start_row = 2
          end
          -- Data rows.
          for r = start_row, #seg.rows do
            ImGui.ImGui_TableNextRow(RA.ctx)
            for c = 1, num_cols do
              ImGui.ImGui_TableSetColumnIndex(RA.ctx, c - 1)
              ImGui.ImGui_TextWrapped(RA.ctx, seg.rows[r][c] or "")
            end
          end
          ImGui.ImGui_EndTable(RA.ctx)
        end
        ImGui.ImGui_PopStyleVar(RA.ctx)
        PopFont(RA.ctx)
        -- Right-click on table area to copy. Same V5 popup styling as the
        -- text segment popup above so all context menus match visually.
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(8),  RA.SC(8))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(10), RA.SC(6))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),   RA.SC(8),  RA.SC(4))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(), RA.SC(4))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(), TK.card)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border_str)
        PushFont(RA.ctx, FONT.mono_med, RA.SC(10))
        if ImGui.ImGui_BeginPopupContextItem(RA.ctx, tbl_id .. "_ctx") then
          if ImGui.ImGui_MenuItem(RA.ctx, "Copy Table") then
            local tbl_parts = {}
            for _, cells in ipairs(seg.rows) do
              tbl_parts[#tbl_parts+1] = table.concat(cells, "\t")
            end
            ImGui.ImGui_SetClipboardText(RA.ctx, table.concat(tbl_parts, "\n"))
          end
          if ImGui.ImGui_MenuItem(RA.ctx, "Copy All") then
            ImGui.ImGui_SetClipboardText(RA.ctx, full_text)
          end
          ImGui.ImGui_EndPopup(RA.ctx)
        end
        PopFont(RA.ctx)
        PopStyleColor(RA.ctx, 2)  -- PopupBg, Border
        ImGui.ImGui_PopStyleVar(RA.ctx, 4)  -- WindowPadding, FramePadding, ItemSpacing, PopupRounding
      end
    end
  end

  if color then PopStyleColor(RA.ctx) end
end

-- ---------------------------------------------------------------------------
-- Screen render functions
-- ---------------------------------------------------------------------------

-- =============================================================================
-- First-run screens: Render.tos_screen / Render.api_key_screen
-- =============================================================================
-- Settings screens (API Keys, Preferred Plugins) use centered Indent columns
-- with the main window scrollbar, matching the Help screen pattern.
-- UI.text_multiline() / TextWrapped wrap to the indented content region width.

-- -----------------------------------------------------------------------------
-- Render.tos_screen
-- -----------------------------------------------------------------------------
-- Full-window Terms of Use / disclaimer screen. Shown first on every launch
-- where the stored api_keys.tos_version does not match the current one. The user must
-- click "I Agree" to continue, or Escape to close the script.

-- Parse api_keys.tos_text into structured blocks for V5 rendering.
-- First line of each paragraph (split on blank lines) determines classification:
--   ALL CAPS heading    -> { type="section", heading, body }
--   starts "Copyright"  -> { type="copyright", text }
--   starts "By clicking" -> { type="confirm",   text }
--   otherwise           -> { type="body",      text }
local function parse_tos_blocks(raw)
  local blocks = {}
  local paras  = {}
  local buf    = {}
  -- Split into paragraphs on blank lines. Appending trailing \n ensures
  -- the final paragraph gets flushed by the gmatch loop.
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      if #buf > 0 then
        paras[#paras+1] = table.concat(buf, "\n")
        buf = {}
      end
    else
      buf[#buf+1] = line
    end
  end
  if #buf > 0 then paras[#paras+1] = table.concat(buf, "\n") end
  for _, para in ipairs(paras) do
    local first_nl   = para:find("\n", 1, true)
    local first_line = first_nl and para:sub(1, first_nl-1) or para
    local rest       = first_nl and para:sub(first_nl+1) or ""
    -- Heading detection: the paragraph's first line is all uppercase letters,
    -- spaces, and ampersands (matching the 3 authored headings) and no more
    -- than 40 chars. Guards against mistaking a regular sentence that
    -- happens to begin with an uppercase word as a heading.
    if first_line:match("^[A-Z][A-Z%s&]*$") and #first_line <= 40 then
      blocks[#blocks+1] = {
        type = "section", heading = first_line, body = rest,
      }
    elseif first_line:match("^Copyright") then
      blocks[#blocks+1] = { type = "copyright", text = para }
    elseif first_line:match("^By clicking") then
      blocks[#blocks+1] = { type = "confirm", text = para }
    else
      blocks[#blocks+1] = { type = "body", text = para }
    end
  end
  return blocks
end

function Render.tos_screen()
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w     = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w

  -- Target visible margin of 30 px on each side (measured from the window
  -- edge). pad_x covers part of it; indent makes up the rest so the
  -- cursor lands at 30 px from the window left. inner_w is the resulting
  -- content column width between the two margins.
  local SIDE_MARGIN = RA.SC(30)
  local indent   = math_max(SIDE_MARGIN - pad_x, 0)
  local inner_w  = math_max(stable_w - 2 * indent, RA.SC(200))
  ImGui.ImGui_Indent(RA.ctx, indent)

  Dummy(RA.ctx, 1, RA.SC(10))

  -- Wordmark + "Terms of Use" title with accent underline. Kept as the
  -- centered-logo approach rather than the hero band used on the settings
  -- family, because TOS is a pre-onboarding ceremonial moment and reads
  -- better with a formal document-style header. Logo rendered at 2x the
  -- default size so it anchors this splash-like screen.
  UI.logo(inner_w, RA.SC(44))
  Dummy(RA.ctx, 1, RA.SC(4))
  UI.page_title("Terms of Use", inner_w)
  Dummy(RA.ctx, 1, RA.SC(16))

  -- Parse TOS text into structured blocks on first render. Cached on
  -- api_keys so subsequent renders skip the split.
  if not api_keys._tos_blocks then
    api_keys._tos_blocks = parse_tos_blocks(api_keys.tos_text)
  end

  -- Wrap-X helper: returns the X coordinate at which TextWrapPos should
  -- wrap. Subtracts `indent` so the right margin matches the left
  -- (SIDE_MARGIN), instead of stopping at the global WindowPadding edge.
  -- The default ImGui content-region right edge sits at pad_x from the
  -- window edge; we want it at SIDE_MARGIN, which means rolling back by
  -- (SIDE_MARGIN - pad_x) = indent.
  local function _wrap_x()
    return GetCursorPosX(RA.ctx)
      + ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      - indent
  end

  -- Shared accept-flow: fired by the I Agree button and by the Enter-key
  -- shortcut below. Marks the current TOS version as accepted and routes
  -- to the right next-screen (main chat if a key is already stored,
  -- first-run flow otherwise).
  local function _accept_tos()
    api_keys.mark_tos_accepted()
    if S.api_key then
      api_keys.screen = nil
      S.refocus_prompt = true
    else
      api_keys.screen = "first_run"
    end
  end

  -- Flat layout: render the TOS sections directly on the page (no inner
  -- scrollable child). The TOS is short and won't grow -- v1.1's auto-
  -- diagnostics opt-in lives in its own dedicated dialog, not here -- so
  -- the previous container-with-scrollbar machinery was overkill. The
  -- main window's own scrollbar handles overflow on small screens.
  --
  -- Right-click -> Copy TOS was scoped to the inner child and dropped
  -- with the flatten. Users wanting a copy of the terms can read the
  -- source (Resources/UI.lua references the canonical text in
  -- api_keys.tos_text in ReaAssist.lua); a Copy button can be added back
  -- here later if a real user asks for it.

  -- Render each block. Sections get a v5_section_label + wrapped body
  -- paragraph. Copyright is a quiet muted footnote at the end.
  -- "confirm" blocks are rendered below the section list, right above
  -- the I Agree button. Section labels render at the default SC(10)
  -- mono to match the rest of the V5 section-label sites.
  for bi, blk in ipairs(api_keys._tos_blocks) do
    if blk.type == "section" then
      if bi > 1 then Dummy(RA.ctx, 1, RA.SC(10)) end
      UI.v5_section_label(blk.heading)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
      ImGui.ImGui_PushTextWrapPos(RA.ctx, _wrap_x())
      Text(RA.ctx, blk.body)
      ImGui.ImGui_PopTextWrapPos(RA.ctx)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    elseif blk.type == "copyright" then
      Dummy(RA.ctx, 1, RA.SC(20))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
      ImGui.ImGui_PushTextWrapPos(RA.ctx, _wrap_x())
      Text(RA.ctx, blk.text)
      ImGui.ImGui_PopTextWrapPos(RA.ctx)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    end
  end

  Dummy(RA.ctx, 1, RA.SC(28))

  -- Confirmation line: the authored "By clicking..." paragraph rendered
  -- as a muted caption right above the I Agree button. Acts as the final
  -- "this is what you're about to do" beat. Centered horizontally so it
  -- visually anchors to the centered I Agree button below. If the window
  -- is narrow enough that the line wraps, we fall back to a wrapped
  -- left-aligned render (centering wrapped multi-line per-line text
  -- would require manual line-by-line layout for marginal gain).
  for _, blk in ipairs(api_keys._tos_blocks) do
    if blk.type == "confirm" then
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      local tw = CalcTextSize(RA.ctx, blk.text)
      if tw <= inner_w then
        SetCursorPosX(RA.ctx,
          GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - tw) * 0.5), 0))
        Text(RA.ctx, blk.text)
      else
        ImGui.ImGui_PushTextWrapPos(RA.ctx, _wrap_x())
        Text(RA.ctx, blk.text)
        ImGui.ImGui_PopTextWrapPos(RA.ctx)
      end
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
      break
    end
  end

  Dummy(RA.ctx, 1, RA.SC(10))

  -- I Agree button: V5 primary accent (blue fill, white text). Centered.
  local BTN_W = RA.SC(200)
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - BTN_W) * 0.5), 0))
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(7))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(TK.accent, 0x000000FF, 0.15))
  if ImGui.ImGui_Button(RA.ctx, "I Agree##tos_agree", BTN_W, 0) then
    _accept_tos()
  end
  UI.pressable()
  PopStyleColor(RA.ctx, 4)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  Dummy(RA.ctx, 1, RA.SC(10))

  -- Keyboard shortcuts (both gated on UI._popup_was_open so key presses
  -- inside a popup don't also fire these handlers).
  --   Enter        -> same as clicking I Agree
  --   Esc          -> quit the script
  if not UI._popup_was_open then
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
      _accept_tos()
    elseif ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      S.script_open = false
    end
  end

  ImGui.ImGui_Unindent(RA.ctx, indent)
end

-- -----------------------------------------------------------------------------
-- Render.help_screen
-- -----------------------------------------------------------------------------
-- Full-window help overlay with styled section headers, clickable table of
-- contents, and smooth-scroll navigation.
-- Parses Help.md into structured sections on first load.
-- HELP_SECTIONS stays local: it's a one-time markdown parse cache that
-- never needs to cross chunks or survive a session reset.
-- help_section_ys stays local: rebuilt during each help-screen render
-- and not meaningful outside that code path.
-- S.help_scroll_to / _top / _frames are transient UI state (smooth-scroll
-- progress, TOC target, auto-expiry frame counter). They live on S like
-- every other "user clicked something, persist for a few frames" state.
local HELP_SECTIONS  -- cached parsed sections: { {title, body_lines}, ... }
local help_section_ys  -- maps section index -> cursor Y during render
local help_search_buf = ""  -- Help-screen search input buffer; was previously
                            -- written without `local` (global leak across
                            -- the dofile chunk boundary into _G).

local function load_help_sections()
  if HELP_SECTIONS then return HELP_SECTIONS end
  local path = RA.RESOURCES_DIR .. "Help.md"
  local f = io.open(path, "r")
  if not f then
    HELP_SECTIONS = {{ title = "Error", lines = {"Help file not found.", "Expected: " .. path} }}
    return HELP_SECTIONS
  end
  local raw = f:read("*a"); f:close()
  local sections = {}
  local cur_section
  for line in raw:gmatch("[^\n]+") do
    if line:match("^# ") and not line:match("^## ") then
      -- Skip top-level title.
    elseif line:match("^## ") then
      local heading = line:gsub("^##%s*", "")
      cur_section = { title = heading, lines = {} }
      sections[#sections+1] = cur_section
    elseif cur_section then
      -- Strip **bold** markers for plain rendering.
      line = line:gsub("%*%*(.-)%*%*", "%1")
      cur_section.lines[#cur_section.lines+1] = line
    end
  end
  HELP_SECTIONS = sections
  return HELP_SECTIONS
end

function Render.help_screen()
  local win_w  = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x  = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w   = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local indent   = math_floor((stable_w - inner_w) * 0.5)

  -- Close handler: checks the S.help_return_to cookie so Help knows where
  -- to go back. Callers set the cookie before opening Help (e.g. Settings
  -- or Custom LLM set it to their own screen id); on close, we route
  -- there and clear the cookie. With no cookie, the user lands in the
  -- main chat (default for the main-screen Help button).
  local function close_help()
    S.show_help      = false
    help_search_buf  = ""
    -- Priority: footer-toggle breadcrumb (captured on footer Help
    -- click, knows full show_credits / show_bug / screen context) >
    -- legacy help_return_to cookie (pre-footer, screen-only cookie
    -- set by Settings / Custom-LLM when they open Help) > fallback
    -- (main chat).
    local ret = S._footer_help_ret
    if ret then
      S._footer_help_ret = nil
      api_keys.screen   = ret.screen       or nil
      S.show_credits    = ret.show_credits or false
      S.show_bug_report = ret.show_bug     or false
      if not (api_keys.screen or S.show_credits or S.show_bug_report) then
        S.refocus_prompt = true
      end
    elseif S.help_return_to then
      api_keys.screen   = S.help_return_to
      S.help_return_to  = nil
    else
      S.refocus_prompt = true
    end
  end

  UI.push_settings_styles()

  -- V5 hero band. Esc / Close button / footer / logo click cover nav.
  UI.hero_band_settings_v5(
    "Guide, shortcuts, and usage tips.",
    "HELP \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: see Render.credits_screen for the full pattern.
  -- Child ends at the top of the footer rail so scrollbar stops there
  -- (not behind the footer) and content can't draw into the footer
  -- strip.
  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##help_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, indent)
  Dummy(RA.ctx, 1, RA.SC(14))

  -- Top-of-page nav row pair: [Read Online Manual] [Feedback & Report a
  -- Bug]. Same card pill chrome as the Settings Preferred Plugins button
  -- (UI.v5_nav_row); both buttons are equal-width and centered as a
  -- group. The manual button opens the online manual via UI.open_url;
  -- the feedback button drills into the in-app bug report screen.
  do
    local NAV_ROW_W = RA.SC(230)
    local NAV_GAP   = RA.SC(8)
    local TOTAL_W   = NAV_ROW_W * 2 + NAV_GAP
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - TOTAL_W) * 0.5), 0))
    if UI.v5_nav_row("##help_manual_btn", "Read Online Manual",
        "Open the online manual at reaassist.app/manual", NAV_ROW_W) then
      UI.open_url("https://reaassist.app/manual")
    end
    SameLine(RA.ctx, 0, NAV_GAP)
    if UI.v5_nav_row("##help_bug_btn", "Feedback & Report a Bug",
        "Open the feedback / bug report form", NAV_ROW_W) then
      S.show_bug_report = true
      S.show_help = false
    end
  end
  Dummy(RA.ctx, 1, RA.SC(14))

  -- Load sections.
  local sections = load_help_sections()
  if not help_section_ys then help_section_ys = {} end

  -- ---- Search + Table of Contents ----
  local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
  help_search_buf = help_search_buf or ""

  -- Search row: [ input ][ Clear ]  [-][+]
  -- The Clear group + size group share the same V5 secondary button
  -- palette (card fill / border / TK.text) and the same frame
  -- rounding + padding push; an extra gap separates them so the
  -- two groups read as distinct controls.
  local CLEAR_BTN_W = RA.SC(60)
  local SIZE_BTN_W  = RA.SC(28)
  local BTN_GAP     = RA.SC(6)
  local GROUP_GAP   = RA.SC(12)
  local sz_group_w  = SIZE_BTN_W * 2 + BTN_GAP
  local input_w     = inner_w - CLEAR_BTN_W - sz_group_w - BTN_GAP - GROUP_GAP
  -- Input fill lifted from TK.input_bg -> TK.card. Reads a touch
  -- brighter in dark mode (card > input_bg, which was the deepest
  -- recessed well). On light mode it goes pure white against the
  -- page's off-white bg -- also reads brighter.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(), TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),  TK.card)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(6))
  ImGui.ImGui_SetNextItemWidth(RA.ctx, input_w)
  local _, sub_buf = ImGui.ImGui_InputTextWithHint(
    RA.ctx, "##help_search", "Search Help...", help_search_buf)
  help_search_buf = sub_buf
  UI.focus_ring()
  _, help_search_buf = UI.input_with_menu(RA.ctx, false, help_search_buf)
  PopStyleColor(RA.ctx, 3)

  local do_clear = false
  -- Toned-down secondary palette for Clear / - / + : transparent fill
  -- at rest (disappears into the page bg) + muted text + keeps the
  -- 1px border for affordance. Hover lifts to TK.card so the button
  -- materialises under the cursor. Previously they rendered at full
  -- TK.card + TK.text which read too "primary" for helper controls.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)

  SameLine(RA.ctx, 0, BTN_GAP)
  if ImGui.ImGui_Button(RA.ctx, "Clear##help_clear_btn", CLEAR_BTN_W, 0) then
    do_clear = true
  end

  -- Text-size controls. Scope: help content only (section body
  -- paragraphs + bullets). Doesn't affect chat, settings, or chrome.
  -- Range 0.8 -> 1.5 in 0.1 steps; persisted to ExtState.
  SameLine(RA.ctx, 0, GROUP_GAP)
  ImGui.ImGui_BeginDisabled(RA.ctx, prefs.help_font_scale <= 0.8 + 1e-6)
  if ImGui.ImGui_Button(RA.ctx, "\xe2\x88\x92##help_text_dec",
      SIZE_BTN_W, 0) then
    prefs.help_font_scale = math.max(0.8,
      (prefs.help_font_scale or 1.0) - 0.1)
    reaper.SetExtState(CFG.EXT_NS, "help_font_scale",
      tostring(prefs.help_font_scale), true)
  end
  ImGui.ImGui_EndDisabled(RA.ctx)
  if ImGui.ImGui_IsItemHovered(RA.ctx,
      ImGui.ImGui_HoveredFlags_AllowWhenDisabled()) then
    UI.tooltip(string.format("Decrease text size  (%d%%)",
      math_floor(prefs.help_font_scale * 100 + 0.5)))
  end

  SameLine(RA.ctx, 0, BTN_GAP)
  ImGui.ImGui_BeginDisabled(RA.ctx, prefs.help_font_scale >= 1.5 - 1e-6)
  if ImGui.ImGui_Button(RA.ctx, "+##help_text_inc",
      SIZE_BTN_W, 0) then
    prefs.help_font_scale = math.min(1.5,
      (prefs.help_font_scale or 1.0) + 0.1)
    reaper.SetExtState(CFG.EXT_NS, "help_font_scale",
      tostring(prefs.help_font_scale), true)
  end
  ImGui.ImGui_EndDisabled(RA.ctx)
  if ImGui.ImGui_IsItemHovered(RA.ctx,
      ImGui.ImGui_HoveredFlags_AllowWhenDisabled()) then
    UI.tooltip(string.format("Increase text size  (%d%%)",
      math_floor(prefs.help_font_scale * 100 + 0.5)))
  end

  ImGui.ImGui_PopStyleVar(RA.ctx)            -- FrameBorderSize
  PopStyleColor(RA.ctx, 5)                   -- Button + Hovered + Active + Text + Border
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)         -- FrameRounding + FramePadding (shared with input)
  Dummy(RA.ctx, 1, RA.SC(12))

  -- Help text-scale driver. Section labels (CONTENTS + per-section),
  -- the TOC font, and the body font all multiply their sizes by this
  -- so the page scales as a unit under the - / + buttons above.
  local _help_scale = prefs.help_font_scale or 1.0

  -- Help section labels run ~2 px larger than the default v5_section_label
  -- (scale * 1.2) and at TK.text_muted instead of TK.text_faint. They're
  -- serving as chapter markers on a long-form content page, not thin UI
  -- group labels on a form, so they get more presence -- brighter on
  -- dark mode, darker on light mode, both courtesy of TK.text_muted.
  local HELP_LBL_SCALE = _help_scale * 1.2
  local HELP_LBL_COL   = TK.text_muted

  UI.v5_section_label("CONTENTS", nil, nil, HELP_LBL_SCALE, HELP_LBL_COL)

  -- Build filtered index list based on search query. Memoized on
  -- (sections identity, query) so steady-state typing doesn't re-scan
  -- the entire help body every frame -- previously this called
  -- :lower() + :find on every body line of every section per frame
  -- while the help screen was open.
  local q = help_search_buf:lower()
  local _hf = UI._help_filter_cache
  local filtered
  if _hf and _hf.sections == sections and _hf.q == q then
    filtered = _hf.filtered
  else
    filtered = {}
    for si, sec in ipairs(sections) do
      local hit = (q == "")
      if not hit and sec.title:lower():find(q, 1, true) then hit = true end
      if not hit then
        for _, ln in ipairs(sec.lines) do
          if ln:lower():find(q, 1, true) then hit = true; break end
        end
      end
      if hit then filtered[#filtered + 1] = si end
    end
    UI._help_filter_cache = { sections = sections, q = q, filtered = filtered }
  end

  if do_clear then
    help_search_buf = ""
  end

  -- Match counter (dim) when searching.
  if help_search_buf ~= "" then
    PushFont(RA.ctx, nil, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    local count_text = (#filtered == 0) and "No matches"
                                         or string.format("%d matches", #filtered)
    local ctw = CalcTextSize(RA.ctx, count_text)
    local cur_x = GetCursorPosX(RA.ctx)
    SetCursorPosX(RA.ctx, cur_x + inner_w - ctw - RA.SC(2))
    Text(RA.ctx, count_text)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, 4)
  end

  if #filtered == 0 then
    PushFont(RA.ctx, nil, RA.SC(12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx, "No sections match \"" .. help_search_buf .. "\"")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  else
    PushFont(RA.ctx, nil, RA.SC(math_floor(12 * _help_scale + 0.5)))
    local base_x = GetCursorPosX(RA.ctx)
    local top_y  = ImGui.ImGui_GetCursorPosY(RA.ctx)
    local col_w  = math_floor(inner_w * 0.5)
    local half   = math.ceil(#filtered / 2)
    local max_y  = top_y
    for col = 0, 1 do
      local lo = col * half + 1
      local hi = math_min((col + 1) * half, #filtered)
      ImGui.ImGui_SetCursorPosY(RA.ctx, top_y)
      for i = lo, hi do
        local si  = filtered[i]
        local sec = sections[si]
        SetCursorPosX(RA.ctx, base_x + col * col_w)
        local toc_label = sec.title
        local toc_w = CalcTextSize(RA.ctx, toc_label)
        local toc_sx, toc_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        ImGui.ImGui_InvisibleButton(RA.ctx, "##toc_" .. si, toc_w, ImGui.ImGui_GetTextLineHeight(RA.ctx))
        local toc_hov = ImGui.ImGui_IsItemHovered(RA.ctx)
        if toc_hov then
          ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
        end
        if ImGui.ImGui_IsItemClicked(RA.ctx) then
          S.help_scroll_to = si
          S.help_scroll_frames = nil
        end
        -- Rest: TK.text_muted (quiet at rest); hover: TK.accent with
        -- underline. Inverts the old "accent at rest / brighter on
        -- hover" so the TOC reads as a calm list the user's eye scans,
        -- with hover as the interactive affordance.
        local toc_col = toc_hov and TK.accent or TK.text_muted
        ImGui.ImGui_DrawList_AddText(dl, toc_sx, toc_sy, toc_col, toc_label)
        if toc_hov then
          local ul_y = toc_sy + ImGui.ImGui_GetTextLineHeight(RA.ctx) - 1
          ImGui.ImGui_DrawList_AddLine(dl, toc_sx, ul_y, toc_sx + toc_w, ul_y, toc_col, 1)
        end
      end
      local cur_y = ImGui.ImGui_GetCursorPosY(RA.ctx)
      if cur_y > max_y then max_y = cur_y end
    end
    ImGui.ImGui_SetCursorPosY(RA.ctx, max_y)
    PopFont(RA.ctx)
  end

  Dummy(RA.ctx, 1, 14)
  -- Separator line below TOC (inset). Muted TK.border so it reads as a
  -- hairline section separator, not a divider beam.
  local sep2_x, sep2_y = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  ImGui.ImGui_DrawList_AddLine(dl, sep2_x + RA.SC(40), sep2_y, sep2_x + inner_w - RA.SC(40), sep2_y, TK.border, 1)
  Dummy(RA.ctx, 1, 14)

  -- ---- Sections ----
  for _, si in ipairs(filtered) do
    local sec = sections[si]
    -- Record section Y for scroll targeting.
    help_section_ys[si] = ImGui.ImGui_GetCursorPosY(RA.ctx)

    -- Group the whole section so right-click anywhere in it opens the
    -- "Copy" context menu via BeginPopupContextItem on the group.
    ImGui.ImGui_BeginGroup(RA.ctx)

    -- Section heading: UI.v5_section_label (mono + short accent
    -- bar + uppercase) -- unifies the visual rhythm with CONTENTS
    -- above. Uses the Help-specific scale + color (bigger + more
    -- readable than the default thin UI labels on Settings).
    UI.v5_section_label(sec.title:upper(), nil, nil,
      HELP_LBL_SCALE, HELP_LBL_COL)

    -- Body text. Font size is scaled by prefs.help_font_scale (0.8 ->
    -- 1.5, driven by the - / + buttons on the search row). Scoped
    -- here so the scale affects section body paragraphs + bullets
    -- without bleeding into the page chrome.
    local _help_body_sz = RA.SC(math_floor(12 * prefs.help_font_scale + 0.5))
    PushFont(RA.ctx, nil, _help_body_sz)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)

    -- Manual word-wrap renderer that also paints a highlight rect behind
    -- every match of `query` in each wrapped sub-line. Used when searching.
    local qlower_body = (q ~= "") and q or nil
    local qlen_body   = qlower_body and #qlower_body or 0
    -- Search-match highlight: accent fill at ~38% alpha (0x60). Less
    -- glaring than the previous 0x80 wash against the scaled-up body
    -- text -- still clearly a hit marker, not a paint stripe.
    local HL_COL      = (TK.accent & 0xFFFFFF00) | 0x60
    local function draw_hl_wrapped(text, wrap_w)
      local th = ImGui.ImGui_GetTextLineHeight(RA.ctx)
      local function flush_line(buf)
        local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        if qlower_body then
          local lower = buf:lower()
          local p = 1
          while true do
            local s = lower:find(qlower_body, p, true)
            if not s then break end
            local pre_w = CalcTextSize(RA.ctx, buf:sub(1, s - 1))
            local m_w  = CalcTextSize(RA.ctx, buf:sub(s, s + qlen_body - 1))
            ImGui.ImGui_DrawList_AddRectFilled(dl,
              sx + pre_w - RA.SC(1), sy,
              sx + pre_w + m_w + RA.SC(1), sy + th,
              HL_COL, RA.SC(2))
            p = s + qlen_body
          end
        end
        Text(RA.ctx, buf)
      end
      -- Track a running line width incrementally instead of remeasuring
      -- the full `cur .. " " .. word` candidate every iteration. The old
      -- loop was O(words^2) (each CalcTextSize walks the whole growing
      -- candidate), which produced a noticeable hitch when typing into
      -- the search field on long help paragraphs. Now the per-iteration
      -- work is one CalcTextSize on the new word + one add.
      local space_w = CalcTextSize(RA.ctx, " ")
      local cur, cur_w = "", 0
      for word in text:gmatch("%S+") do
        local word_w = CalcTextSize(RA.ctx, word)
        local cand_w = (cur == "") and word_w or (cur_w + space_w + word_w)
        if cand_w <= wrap_w then
          cur   = (cur == "") and word or (cur .. " " .. word)
          cur_w = cand_w
        else
          if cur ~= "" then flush_line(cur) end
          cur, cur_w = word, word_w
        end
      end
      if cur ~= "" then flush_line(cur) end
    end

    local body_wrap_x_off = inner_w
    -- Index-based walk (vs. ipairs) so the table branch can advance
    -- across multiple consumed rows in one step. Adds ### sub-heading
    -- and pipe-table support that the chat renderer (UI.selectable_text)
    -- already had; without these, "### Foo" rendered as literal raw
    -- text and "| col | col |" rows showed as pipe-separated lines.
    local idx = 1
    while idx <= #sec.lines do
      local raw  = sec.lines[idx]
      local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if line == "" then
        Dummy(RA.ctx, 1, 4)
        idx = idx + 1
      elseif line:match("^|") then
        -- Markdown table: gather contiguous |...| rows starting here,
        -- then render via ImGui_BeginTable. Same column-fitting logic
        -- the chat renderer's table branch uses (search "Render table
        -- segment" in this file). No per-table right-click "Copy"
        -- menu -- the section-level "Copy" via BeginPopupContextItem
        -- on the outer group already covers it.
        local rows, next_idx = parse_md_table(sec.lines, idx)
        if #rows > 0 then
          local num_cols = 0
          for _, cells in ipairs(rows) do
            if #cells > num_cols then num_cols = #cells end
          end
          if num_cols > 0 then
            local tbl_id    = "##help_tbl_" .. si .. "_" .. idx
            local tbl_flags = ImGui.ImGui_TableFlags_SizingFixedFit()
                            | ImGui.ImGui_TableFlags_BordersInnerV()
                            | ImGui.ImGui_TableFlags_PadOuterX()
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_CellPadding(), 5, 2)
            local col_px = {}
            for c = 1, num_cols do col_px[c] = 0 end
            for _, cells in ipairs(rows) do
              for c = 1, num_cols do
                local w = CalcTextSize(RA.ctx, cells[c] or "")
                if w > col_px[c] then col_px[c] = w end
              end
            end
            local pad_total = num_cols * 12
            local budget    = body_wrap_x_off - pad_total
            local total_w   = 0
            for c = 1, num_cols do total_w = total_w + col_px[c] end
            if total_w > budget and budget > 0 then
              local fair = budget / num_cols
              local locked, unlocked_w = 0, 0
              local is_locked = {}
              for c = 1, num_cols do
                if col_px[c] <= fair then
                  is_locked[c] = true
                  locked = locked + col_px[c]
                else
                  unlocked_w = unlocked_w + col_px[c]
                end
              end
              local remain = budget - locked
              for c = 1, num_cols do
                if not is_locked[c] then
                  if unlocked_w > 0 then
                    col_px[c] = math_max(40, math_floor(remain * col_px[c] / unlocked_w))
                  else
                    col_px[c] = math_max(40, math_floor(remain / num_cols))
                  end
                end
              end
            end
            if ImGui.ImGui_BeginTable(RA.ctx, tbl_id, num_cols, tbl_flags, body_wrap_x_off) then
              for c = 1, num_cols do
                ImGui.ImGui_TableSetupColumn(RA.ctx, "##c" .. c,
                  ImGui.ImGui_TableColumnFlags_WidthFixed(), col_px[c])
              end
              local start_row = 1
              if #rows > 1 then
                ImGui.ImGui_TableNextRow(RA.ctx)
                for c = 1, num_cols do
                  ImGui.ImGui_TableSetColumnIndex(RA.ctx, c - 1)
                  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
                  ImGui.ImGui_TextWrapped(RA.ctx, rows[1][c] or "")
                  PopStyleColor(RA.ctx)
                end
                start_row = 2
              end
              for r = start_row, #rows do
                ImGui.ImGui_TableNextRow(RA.ctx)
                for c = 1, num_cols do
                  ImGui.ImGui_TableSetColumnIndex(RA.ctx, c - 1)
                  ImGui.ImGui_TextWrapped(RA.ctx, rows[r][c] or "")
                end
              end
              ImGui.ImGui_EndTable(RA.ctx)
            end
            ImGui.ImGui_PopStyleVar(RA.ctx)
            Dummy(RA.ctx, 1, 4)
          end
        end
        idx = next_idx
      elseif line:match("^### ") then
        -- H3 sub-heading: bold at body size + 2 SC pixels, with a
        -- small pre/post spacer. ## H2 sections still cap at the
        -- orange section label via UI.v5_section_label above; ###
        -- gives a lighter visual divider inside a section.
        local htext = line:sub(5):gsub("^%s+", "")
        Dummy(RA.ctx, 1, 4)
        PushFont(RA.ctx, RA.bold_font, _help_body_sz + RA.SC(2))
        Text(RA.ctx, htext)
        PopFont(RA.ctx)
        Dummy(RA.ctx, 1, 2)
        idx = idx + 1
      elseif line:sub(1, 2) == "- " then
        local content = line:sub(3)
        -- Bullet dot, muted. Pulled back from TK.accent to TK.text_muted
        -- so the bullet + bold lead-in combo doesn't read as a wall of
        -- blue -- the emphasis on the lead-in carries the hierarchy.
        local bx, by = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        local th     = ImGui.ImGui_GetTextLineHeight(RA.ctx)
        ImGui.ImGui_DrawList_AddCircleFilled(dl, bx + RA.SC(5), by + th * 0.55, RA.SC(2), TK.text_muted)
        local indent_px = RA.SC(14)
        ImGui.ImGui_Indent(RA.ctx, indent_px)
        local wrap_w = body_wrap_x_off - indent_px
        local colon = line:find(":", 3, true)
        if qlower_body then
          -- Searching: no bold split -- render uniform content with highlights.
          draw_hl_wrapped(content, wrap_w)
        elseif colon and (colon - 2) <= 32 then
          -- Bold "Label:" lead-in + wrapped rest (ImGui wrap).
          local lead = line:sub(3, colon)
          local rest = line:sub(colon + 1):gsub("^%s+", "")
          local wrap_x = GetCursorPosX(RA.ctx) + wrap_w
          ImGui.ImGui_PushTextWrapPos(RA.ctx, wrap_x)
          -- "Label:" lead-in: plain TK.text in bold (no accent colour).
          -- Bold weight alone carries the emphasis -- adding the accent
          -- tint on every lead-in made the page read shouty.
          PushFont(RA.ctx, RA.bold_font, _help_body_sz)
          Text(RA.ctx, lead)
          PopFont(RA.ctx)
          SameLine(RA.ctx, 0, RA.SC(4))
          Text(RA.ctx, rest)
          ImGui.ImGui_PopTextWrapPos(RA.ctx)
        else
          local wrap_x = GetCursorPosX(RA.ctx) + wrap_w
          ImGui.ImGui_PushTextWrapPos(RA.ctx, wrap_x)
          Text(RA.ctx, content)
          ImGui.ImGui_PopTextWrapPos(RA.ctx)
        end
        ImGui.ImGui_Unindent(RA.ctx, indent_px)
        Dummy(RA.ctx, 1, 2)
        idx = idx + 1
      else
        if qlower_body then
          draw_hl_wrapped(line, body_wrap_x_off)
        else
          ImGui.ImGui_PushTextWrapPos(RA.ctx, GetCursorPosX(RA.ctx) + body_wrap_x_off)
          Text(RA.ctx, line)
          ImGui.ImGui_PopTextWrapPos(RA.ctx)
        end
        idx = idx + 1
      end
    end
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)

    ImGui.ImGui_EndGroup(RA.ctx)
    if ImGui.ImGui_BeginPopupContextItem(RA.ctx, "##sec_ctx_" .. si) then
      if ImGui.ImGui_Selectable(RA.ctx, "Copy") then
        local text = sec.title .. "\n\n" .. tbl_concat(sec.lines, "\n")
        ImGui.ImGui_SetClipboardText(RA.ctx, text)
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end

    Dummy(RA.ctx, 1, 18)
  end

  -- ---- Smooth scroll to section ----
  -- Tick the expire counter unconditionally on the outer guard, so a
  -- target section that gets filtered out by the search field (its Y
  -- entry vanishes from help_section_ys) can still age out instead of
  -- lingering until the user clears the search and inadvertently
  -- triggers a delayed jump.
  if S.help_scroll_to then
    if not S.help_scroll_frames then S.help_scroll_frames = 0 end
    S.help_scroll_frames = S.help_scroll_frames + 1
    -- Auto-expire after 30 frames to avoid fighting user scroll.
    if S.help_scroll_frames > 30 then
      S.help_scroll_to = nil
      S.help_scroll_frames = nil
    elseif help_section_ys[S.help_scroll_to] then
      local target_y = help_section_ys[S.help_scroll_to] - 30
      local cur_scroll = ImGui.ImGui_GetScrollY(RA.ctx)
      local diff = target_y - cur_scroll
      if math_abs(diff) < 2 then
        ImGui.ImGui_SetScrollY(RA.ctx, target_y)
        S.help_scroll_to = nil
        S.help_scroll_frames = nil
      else
        ImGui.ImGui_SetScrollY(RA.ctx, math_floor(cur_scroll + diff * 0.15))
      end
    end
  end

  -- Smooth scroll to top.
  if S.help_scroll_top then
    local cur_scroll = ImGui.ImGui_GetScrollY(RA.ctx)
    if cur_scroll < 1 then
      ImGui.ImGui_SetScrollY(RA.ctx, 0)
      S.help_scroll_top = false
    else
      ImGui.ImGui_SetScrollY(RA.ctx, math_floor(cur_scroll * 0.8))
    end
  end

  -- No inline Close button -- Esc, MB4, footer Help-toggle, and logo
  -- click all cover navigation away (matches Credits pattern).
  Dummy(RA.ctx, 1, RA.SC(18))

  -- Back-to-top arrow: bottom-right, visible when scrolled down.
  -- win_x/win_y/win_h2 here refer to the BeginChild we're currently
  -- rendering into -- its bottom already stops at the footer rail's
  -- top edge, so positioning the arrow relative to the child bottom
  -- places it just above the rail without any extra subtraction.
  local scroll_y = ImGui.ImGui_GetScrollY(RA.ctx)
  if scroll_y > RA.SC(100) then
    local arrow_sz = RA.SC(20)
    local arrow_inset_h = RA.SC(20)
    local arrow_inset_v = RA.SC(12)
    local tri_inset = RA.SC(2)
    local tri_side  = RA.SC(3)
    local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    local win_w2, win_h2 = ImGui.ImGui_GetWindowSize(RA.ctx)
    local ax = win_x + win_w2 - arrow_sz - arrow_inset_h
    local ay = win_y + win_h2 - arrow_sz - arrow_inset_v
    -- Manual hit-test.
    local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
    local arrow_hov = mx >= ax and mx <= ax + arrow_sz
                  and my >= ay and my <= ay + arrow_sz
    if arrow_hov then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
        S.help_scroll_top = true
        S.help_scroll_to  = nil
      end
    end
    -- Muted at rest, accent on hover -- matches the v5_link_row icon
    -- colour language on Credits (quiet at rest, sweep to accent).
    local arrow_col = arrow_hov and TK.accent or TK.accent_ui
    -- Draw upward arrow triangle.
    local cx = ax + arrow_sz * 0.5
    ImGui.ImGui_DrawList_AddTriangleFilled(dl,
      cx, ay + tri_inset,
      ax + tri_side, ay + arrow_sz - tri_inset,
      ax + arrow_sz - tri_side, ay + arrow_sz - tri_inset,
      arrow_col)
  end

  if UI.back_pressed() then
    close_help()
  end

  ImGui.ImGui_Unindent(RA.ctx, indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding
  UI.pop_settings_styles()

  -- V5 footer rail: paints on the outer window's drawlist (we're
  -- outside the BeginChild now) so it sits on top of the bottom
  -- strip. Content inside the child is clipped at the child's
  -- bottom edge, so nothing bleeds through the rail.
  UI.footer_rail_v5()
end

-- -----------------------------------------------------------------------------
-- Render.bug_report_screen
-- -----------------------------------------------------------------------------
-- Top-level Feedback / Report an Issue page (linked from Help). Hosts a form
-- that POSTs to https://d.reaassist.app via Diag.send_bug_report. Replaces the
-- previous email-out-of-band flow (mailto / Gmail compose) -- the in-app form
-- bundles the comment, optional contact name + email, the diagnostic report,
-- and either the entire Advanced Log (when enabled) or the current chat
-- session (fallback) into one redacted JSON payload.
--
-- Form state (S.bug_report_form_*) persists across page navigation within a
-- session; name + email also persist across sessions via ExtState so the user
-- types contact info once. Comment is cleared on successful send.
function Render.bug_report_screen()
  local win_w  = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x  = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w   = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(480), stable_w)
  local indent   = math_floor((stable_w - inner_w) * 0.5)

  -- Lazy-load contact fields from ExtState once per session so the user only
  -- types name + email once. nil sentinel ensures we hit ExtState on first
  -- access but don't re-read on subsequent renders. Empty strings indicate
  -- "loaded but user never set it"; further blank visits don't re-query.
  if S.bug_report_form_name == nil then
    S.bug_report_form_name =
      reaper.GetExtState(CFG.EXT_NS, "bug_report_contact_name") or ""
  end
  if S.bug_report_form_email == nil then
    S.bug_report_form_email =
      reaper.GetExtState(CFG.EXT_NS, "bug_report_contact_email") or ""
  end
  S.bug_report_form_comment = S.bug_report_form_comment or ""
  S.bug_report_send_state   = S.bug_report_send_state   or "idle"

  -- V5 hero band -- matches Settings. Branded "FEEDBACK" to line up
  -- with the Help-page "Feedback & Report a Bug" entry row.
  UI.hero_band_settings_v5(
    "Send feedback or report an issue.",
    "FEEDBACK \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: see Render.credits_screen for the full pattern.
  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##bugrpt_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, indent)
  Dummy(RA.ctx, 1, RA.SC(10))

  -- Help-style section labels (bigger scale + TK.text_muted). Both
  -- Bug Report + Help are documentation-style pages and share the
  -- same chapter-heading rhythm so their structure feels unified.
  local SEC_LBL_SCALE = 1.2
  local SEC_LBL_COL   = TK.text_muted

  -- Body-paragraph helper: left-aligned wrapped text in TK.text, size
  -- SC(12). Used for the short intros under each section label.
  local function _para(text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    PushFont(RA.ctx, nil, RA.SC(12))
    ImGui.ImGui_PushTextWrapPos(RA.ctx, GetCursorPosX(RA.ctx) + inner_w)
    Text(RA.ctx, text)
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
  end

  -- Small centered toast helper (auto-fading feedback under button rows).
  local function _toast(text, col)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col)
    PushFont(RA.ctx, nil, RA.SC(11))
    local tw = CalcTextSize(RA.ctx, text)
    local off = math_max(math_floor((inner_w - tw) * 0.5), 0)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + off)
    Text(RA.ctx, text)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
  end

  -- Recessed-input chrome with a 1 px border so empty fields stand out from
  -- the page background. TK.input_bg fill + TK.border outline + Inter SC(13).
  -- Pair push/pop around any single-line ImGui_InputText or InputTextMultiline
  -- call inside this form.
  local function _push_input_style()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),         TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),  TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),   TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),            TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(), TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),          TK.border)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(13))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(8), RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
  end
  local function _pop_input_style()
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx, 6)
  end

  local sending = S.bug_report_send_state == "sending"
  local locked  = sending  -- inputs frozen while a send is in flight

  -- Compatibility shim for ImGui_BeginDisabled (added in later ReaImGui
  -- versions). When unavailable we just skip the visual disable; the
  -- `if not locked then` guards on the mutation paths below prevent
  -- state changes regardless of the visual.
  local _has_disabled = type(ImGui.ImGui_BeginDisabled) == "function"
  local function _begin_dis(b) if _has_disabled then ImGui.ImGui_BeginDisabled(RA.ctx, b) end end
  local function _end_dis()    if _has_disabled then ImGui.ImGui_EndDisabled(RA.ctx) end end

  -- Decide what attachment will accompany the report. Same rule as
  -- Diag.begin_bug_report_draft: log if available, else chat, else none.
  -- Read on every render so the summary updates immediately when the user
  -- toggles "Enable Advanced Log" below or sends a new chat message.
  local _log_size, _log_present = nil, false
  if prefs.debug_logging and Log and Log.path and Log.path ~= "" then
    local f = io.open(Log.path, "rb")
    if f then
      local sz = f:seek("end") or 0
      f:close()
      if sz > 0 then _log_size, _log_present = sz, true end
    end
  end
  local _chat_count = 0
  if type(S.display_messages) == "table" then _chat_count = #S.display_messages end
  local _attachment_kind
  if _log_present then       _attachment_kind = "log"
  elseif _chat_count > 0 then _attachment_kind = "chat"
  else                        _attachment_kind = "none" end

  -- Page-level intro. Calls out the privacy posture in one sentence so
  -- users have context before filling out the form -- the deeper
  -- "Details & privacy" expander below has the full disclosure.
  _para("Sends your description plus the diagnostic report and either the "
     .. "Advanced Log or the current chat session to the ReaAssist "
     .. "maintainer. API keys, bearer tokens, and home paths are "
     .. "automatically redacted before sending.")
  Dummy(RA.ctx, 1, RA.SC(14))

  -- ---- DESCRIBE THE ISSUE -------------------------------------------
  UI.v5_section_label("DESCRIBE THE ISSUE", nil, nil,
    SEC_LBL_SCALE, SEC_LBL_COL)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- Capture screen pos BEFORE the input so we can overlay a placeholder
  -- when the field is empty (same pattern as feedback_modal's comment box).
  local _cmt_x, _cmt_y = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
  _begin_dis(locked)
  _push_input_style()
  local _, new_comment = ImGui.ImGui_InputTextMultiline(RA.ctx,
    "##bugrpt_comment", S.bug_report_form_comment,
    inner_w, RA.SC(110), 0, nil)
  _pop_input_style()
  _end_dis()
  if not locked then S.bug_report_form_comment = new_comment end
  if (S.bug_report_form_comment or "") == "" then
    local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
    ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, RA.SC(13),
      _cmt_x + RA.SC(10), _cmt_y + RA.SC(8), TK.text_faint,
      "What happened? What did you expect? What actually happened?")
  end
  Dummy(RA.ctx, 1, RA.SC(14))

  -- ---- OPTIONAL CONTACT ---------------------------------------------
  UI.v5_section_label("OPTIONAL CONTACT", nil, nil,
    SEC_LBL_SCALE, SEC_LBL_COL)
  _para("Only if you'd like a reply. These fields are sent as-is and "
     .. "are not redacted.")
  Dummy(RA.ctx, 1, RA.SC(8))

  -- Two-column row so Name + Email line up side-by-side at SC(480) inner_w
  -- (~SC(228) per cell + SC(24) gap).
  local FIELD_GAP = RA.SC(24)
  local FIELD_W   = math_floor((inner_w - FIELD_GAP) / 2)

  -- Name + Email labels side-by-side, each aligned to the start of its
  -- corresponding input below. Anchored to the row's starting X so the
  -- positioning is independent of label-text width.
  local _label_row_x = ImGui.ImGui_GetCursorPosX(RA.ctx)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx, "Name")
  ImGui.ImGui_SameLine(RA.ctx)
  ImGui.ImGui_SetCursorPosX(RA.ctx, _label_row_x + FIELD_W + FIELD_GAP)
  Text(RA.ctx, "Email")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(4))

  _begin_dis(locked)
  _push_input_style()
  ImGui.ImGui_SetNextItemWidth(RA.ctx, FIELD_W)
  local _, new_name = ImGui.ImGui_InputText(RA.ctx,
    "##bugrpt_name", S.bug_report_form_name or "")
  -- Persist on blur (IsItemDeactivatedAfterEdit fires the frame after the
  -- field loses focus following an edit). Means tab-out / click-out saves
  -- contact info even if the user doesn't end up pressing Send.
  local _name_blurred = ImGui.ImGui_IsItemDeactivatedAfterEdit
    and ImGui.ImGui_IsItemDeactivatedAfterEdit(RA.ctx) or false
  ImGui.ImGui_SameLine(RA.ctx, 0, FIELD_GAP)
  ImGui.ImGui_SetNextItemWidth(RA.ctx, FIELD_W)
  local _, new_email = ImGui.ImGui_InputText(RA.ctx,
    "##bugrpt_email", S.bug_report_form_email or "")
  local _email_blurred = ImGui.ImGui_IsItemDeactivatedAfterEdit
    and ImGui.ImGui_IsItemDeactivatedAfterEdit(RA.ctx) or false
  _pop_input_style()
  _end_dis()
  if not locked then
    -- Editing the email field dismisses any prior "bad email" error so the
    -- user isn't yelled at while mid-keystroke. The error only re-fires when
    -- they hit Send again.
    if new_email ~= S.bug_report_form_email then
      S.bug_report_email_show_error = false
    end
    S.bug_report_form_name  = new_name
    S.bug_report_form_email = new_email
    if _name_blurred then
      reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_name",
        S.bug_report_form_name or "", true)
    end
    if _email_blurred then
      reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_email",
        S.bug_report_form_email or "", true)
    end
  end

  -- Inline email error: shown only when the user has actually clicked Send
  -- with a malformed address (S.bug_report_email_show_error). Editing the
  -- field clears the flag (above), so the message auto-dismisses as soon as
  -- they start fixing it.
  local _email_invalid = false
  if S.bug_report_email_show_error and Diag and Diag.is_valid_email then
    local em = S.bug_report_form_email or ""
    _email_invalid = (em ~= "" and not Diag.is_valid_email(em))
  end
  if _email_invalid then
    Dummy(RA.ctx, 1, RA.SC(4))
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + FIELD_W + FIELD_GAP)
    Text(RA.ctx, "Doesn't look like an email address.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end
  Dummy(RA.ctx, 1, RA.SC(14))

  -- ---- WHAT WILL BE SENT --------------------------------------------
  UI.v5_section_label("WHAT WILL BE SENT", nil, nil,
    SEC_LBL_SCALE, SEC_LBL_COL)
  Dummy(RA.ctx, 1, RA.SC(4))

  do
    local function _bullet(text, col)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col or TK.text_muted)
      ImGui.ImGui_PushTextWrapPos(RA.ctx, GetCursorPosX(RA.ctx) + inner_w)
      Text(RA.ctx, "\xe2\x80\xa2  " .. text)
      ImGui.ImGui_PopTextWrapPos(RA.ctx)
      PopFont(RA.ctx)
      PopStyleColor(RA.ctx)
    end

    _bullet("Diagnostic report (app/REAPER/OS, recent errors, metrics)")
    if _attachment_kind == "log" then
      local size_str
      if _log_size >= 1024 * 1024 then
        size_str = string.format("%.1f MB", _log_size / (1024 * 1024))
      else
        size_str = string.format("%.0f KB", math.max(1, _log_size / 1024))
      end
      _bullet("Advanced Log enabled \xe2\x80\x94 your complete log ("
        .. size_str .. ") will be attached")
    elseif _attachment_kind == "chat" then
      _bullet("Advanced Log not enabled \xe2\x80\x94 the current chat ("
        .. _chat_count .. " message" .. (_chat_count == 1 and "" or "s")
        .. ") will be attached instead")
      _bullet("For richer reports, enable the Advanced Log below, "
        .. "reproduce the issue, and try again.", TK.text_faint)
    else
      _bullet("No log or chat available \xe2\x80\x94 only the diagnostic "
        .. "report will be sent. Enable the Advanced Log below or start "
        .. "a chat to reproduce the issue first.", TK.text_faint)
    end
    if (S.bug_report_form_name or "") ~= ""
       or (S.bug_report_form_email or "") ~= "" then
      _bullet("Your name / email (sent as-is, not redacted)")
    end
  end

  Dummy(RA.ctx, 1, RA.SC(14))

  -- ---- STATUS / SEND ROW --------------------------------------------
  if sending then
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    Text(RA.ctx, "Sending\xe2\x80\xa6")
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
    if S.bug_report_send_truncation_note then
      _para("Note: " .. S.bug_report_send_truncation_note)
    end
    Dummy(RA.ctx, 1, RA.SC(4))
  elseif S.bug_report_send_state == "error" then
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    UI.text_multiline("Send failed: " ..
      (S.bug_report_send_error or "unknown error"))
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(4))
  end

  -- Send button (centered, primary modal style). Disabled when comment is
  -- empty, when email is invalid, or while a send is in flight. Label flips
  -- to "Try Again" when the previous attempt failed (matches the feedback
  -- modal's retry pattern).
  do
    local btn_w   = RA.SC(140)
    local btn_off = math_max(math_floor((inner_w - btn_w) * 0.5), 0)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + btn_off)

    local comment_empty = (S.bug_report_form_comment or ""):find("%S") == nil
    -- can_send only blocks on the structural prerequisites (not in flight,
    -- comment present). Email validity is checked at click time so the user
    -- gets a clear error rather than a silently-disabled button.
    local can_send = (not locked) and (not comment_empty)
    local label = (S.bug_report_send_state == "error") and "Try Again" or "Send"

    UI.push_modal_primary_btn()
    _begin_dis(not can_send)
    local clicked = ImGui.ImGui_Button(RA.ctx, label .. "##bugrpt_send",
      btn_w, RA.SC(28))
    _end_dis()
    UI.pop_modal_primary_btn()

    if clicked and can_send then
      -- Validate email at submit time. If it's filled in but malformed,
      -- surface the inline error and skip the actual send -- the user can
      -- fix it and click Send again.
      local em = S.bug_report_form_email or ""
      if em ~= "" and Diag and Diag.is_valid_email
         and not Diag.is_valid_email(em) then
        S.bug_report_email_show_error = true
      else
      S.bug_report_email_show_error = false
      -- Persist contact info to ExtState so the next visit pre-fills.
      reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_name",
        S.bug_report_form_name or "", true)
      reaper.SetExtState(CFG.EXT_NS, "bug_report_contact_email",
        S.bug_report_form_email or "", true)

      -- Privacy contract: if the user has the Preview Report expander
      -- open, send EXACTLY the bytes they're looking at. Reusing the
      -- cached preview draft byte-for-byte (event_id and drafted_at
      -- included -- they were stamped when the preview draft was built)
      -- means the redacted log snapshot the user reviewed is the
      -- redacted log snapshot they upload, not a fresh re-read at click
      -- time which could have grown new events or shifted redaction
      -- since they OK'd it. If the preview is closed (cached draft is
      -- nil), the user hasn't reviewed anything yet, so we build a
      -- fresh snapshot for the send -- event_id and drafted_at in that
      -- branch reflect the click moment.
      local draft = S.bug_report_preview_draft or Diag.begin_bug_report_draft()
      S.bug_report_draft_inflight = draft
      S.bug_report_send_state     = "sending"
      S.bug_report_send_error     = nil
      S.bug_report_send_truncation_note = nil
      local send_event_id = draft.event_id
      Diag.send_bug_report(draft,
        S.bug_report_form_comment or "",
        S.bug_report_form_name    or "",
        S.bug_report_form_email   or "",
        function(ok, status, err)
          -- Guard: only mutate state if the in-flight draft is still ours
          -- (defends against the user navigating away mid-send and the
          -- screen state being torn down or replaced).
          if not S.bug_report_draft_inflight
             or S.bug_report_draft_inflight.event_id ~= send_event_id then
            return
          end
          if ok then
            S.bug_report_send_state    = "idle"
            S.bug_report_form_comment  = ""
            S.bug_report_draft_inflight = nil
            S.bug_report_send_truncation_note = nil
            S.bug_report_preview_open  = false
            if UI.show_float_toast then
              UI.show_float_toast("Bug report sent. Thanks!", "ok")
            end
          else
            S.bug_report_send_state = "error"
            S.bug_report_send_error = err or
              ("status " .. tostring(status))
            S.bug_report_draft_inflight = nil
          end
        end)
      end  -- else (email valid, proceed with send)
    end
  end

  Dummy(RA.ctx, 1, RA.SC(16))

  -- ---- COLLAPSIBLES: Preview report + Details & privacy --------------
  -- Preview shows the EXACT redacted JSON bytes that will be POSTed.
  -- We rebuild the draft on each open of the expander (not every frame)
  -- so log-file IO stays bounded. Right-clicking the preview body copies
  -- the full payload to the clipboard for offline inspection.
  S.bug_report_preview_open = S.bug_report_preview_open or false
  local _was_preview_open = S.bug_report_preview_open
  S.bug_report_preview_open = UI.v5_section_label(
    "Preview report",
    S.bug_report_preview_open, nil, 1.0, TK.text_muted)
  if S.bug_report_preview_open then
    -- Refresh the cached draft on every transition closed -> open so the
    -- preview reflects current log state, but reuse the snapshot while the
    -- expander stays open (avoids re-reading multi-MB logs each frame).
    if not _was_preview_open or not S.bug_report_preview_draft then
      S.bug_report_preview_draft = Diag.begin_bug_report_draft()
    end
    local draft = S.bug_report_preview_draft
    local preview = Diag.preview_bug_report_text(draft,
      S.bug_report_form_comment or "",
      S.bug_report_form_name    or "",
      S.bug_report_form_email   or "")

    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.code_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),    TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
      UI.lerp_u32(TK.border_str, TK.text, 0.30))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
      UI.lerp_u32(TK.border_str, TK.text, 0.55))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(10), RA.SC(8))
    if ImGui.ImGui_BeginChild(RA.ctx, "##bugrpt_preview_child",
        inner_w, RA.SC(220), ImGui.ImGui_ChildFlags_Borders()) then
      if ImGui.ImGui_BeginPopupContextWindow(RA.ctx, "##bugrpt_preview_ctx") then
        if ImGui.ImGui_MenuItem(RA.ctx, "Copy") then
          ImGui.ImGui_SetClipboardText(RA.ctx, preview)
        end
        ImGui.ImGui_EndPopup(RA.ctx)
      end
      PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
      local rp = 1
      while rp <= #preview do
        local nl = str_find(preview, "\n", rp, true)
        local line = nl and str_sub(preview, rp, nl - 1) or str_sub(preview, rp)
        if line == "" then
          Dummy(RA.ctx, 1, 4)
        else
          ImGui.ImGui_TextWrapped(RA.ctx, line)
        end
        if not nl then break end
        rp = nl + 1
      end
      PopFont(RA.ctx)
      ImGui.ImGui_EndChild(RA.ctx)
    end
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 7)
    Dummy(RA.ctx, 1, RA.SC(6))
  else
    -- Drop the cached draft once the preview collapses so the next open
    -- triggers a fresh log read (and so we don't pin a multi-MB string in
    -- S indefinitely).
    S.bug_report_preview_draft = nil
  end

  -- Details & privacy. Mirrors the feedback_modal's privacy panel layout
  -- (2x2 mini-cards) but adapted to the bug-report context: the chat card
  -- is replaced with one describing the log, and a fourth panel calls out
  -- the contact-fields exception.
  S.bug_report_privacy_open = S.bug_report_privacy_open or false
  S.bug_report_privacy_open = UI.v5_section_label(
    "Details & privacy",
    S.bug_report_privacy_open, nil, 1.0, TK.text_muted)
  if S.bug_report_privacy_open then
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),
      RA.SC(10), RA.SC(2))

    local _avail_w  = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    local _grid_gap = RA.SC(8)
    local _panel_w  = math_floor((_avail_w - _grid_gap) / 2)
    local _item_wrap = _panel_w - RA.SC(20)
    local _pad_y    = RA.SC(8)
    local _spacing_y = RA.SC(2)

    local function _panel_h(header, items)
      PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
      local _, hh = ImGui.ImGui_CalcTextSize(RA.ctx, header)
      PopFont(RA.ctx)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      local items_h = 0
      for _, item in ipairs(items) do
        local _, ih = ImGui.ImGui_CalcTextSize(RA.ctx,
          "\xe2\x80\xa2 " .. item, nil, nil, false, _item_wrap)
        items_h = items_h + ih + _spacing_y
      end
      PopFont(RA.ctx)
      if #items > 0 then items_h = items_h - _spacing_y end
      return hh + RA.SC(4) + items_h + _pad_y * 2 + RA.SC(8)
    end

    local function _panel(id, header, items, h)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(),
        UI.lerp_u32(TK.card, TK.bg, 0.35))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(), TK.border)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(5))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),
        RA.SC(10), _pad_y)
      if ImGui.ImGui_BeginChild(RA.ctx, id, _panel_w, h,
          ImGui.ImGui_ChildFlags_Borders(),
          ImGui.ImGui_WindowFlags_NoScrollbar()) then
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
        Text(RA.ctx, header)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        Dummy(RA.ctx, 1, RA.SC(4))
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        ImGui.ImGui_PushTextWrapPos(RA.ctx,
          GetCursorPosX(RA.ctx) + _item_wrap)
        for _, item in ipairs(items) do
          Text(RA.ctx, "\xe2\x80\xa2 " .. item)
        end
        ImGui.ImGui_PopTextWrapPos(RA.ctx)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        ImGui.ImGui_EndChild(RA.ctx)
      end
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopStyleColor(RA.ctx, 2)
    end

    -- Row 1: Included | Redacted
    local r1a_h, r1a_i = "What's included", {
      "Diagnostic report (app/REAPER/OS, errors, metrics)",
      "Advanced Log or current chat (whichever is available)",
      "Comment, name, and email you typed (if provided)",
      "Active provider and model id",
    }
    local r1b_h, r1b_i = "Auto-redacted", {
      "API keys (yours, and any pasted into chat)",
      "Authorization headers and Bearer tokens",
      "Home-directory paths",
      "?key= / ?token= URL params",
      "Custom-provider endpoint URLs",
    }
    local r1_h = math_max(_panel_h(r1a_h, r1a_i), _panel_h(r1b_h, r1b_i))
    _panel("##bugrpt_priv_inc", r1a_h, r1a_i, r1_h)
    ImGui.ImGui_SameLine(RA.ctx, 0, _grid_gap)
    _panel("##bugrpt_priv_red", r1b_h, r1b_i, r1_h)

    -- Row 2: Where it goes | Note
    local r2a_h, r2a_i = "Where it goes", {
      "Sent to the ReaAssist maintainer",
      "Used only to debug ReaAssist issues",
      "No third parties",
    }
    local r2b_h, r2b_i = "Not redacted", {
      "Project, track, plugin, or file names you typed",
      "Anything else you pasted into the chat",
      "Your contact name and email (so a reply works)",
    }
    local r2_h = math_max(_panel_h(r2a_h, r2a_i), _panel_h(r2b_h, r2b_i))
    _panel("##bugrpt_priv_where", r2a_h, r2a_i, r2_h)
    ImGui.ImGui_SameLine(RA.ctx, 0, _grid_gap)
    _panel("##bugrpt_priv_note",  r2b_h, r2b_i, r2_h)

    ImGui.ImGui_PopStyleVar(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(6))
  end

  Dummy(RA.ctx, 1, RA.SC(20))

  -- ---- DEBUG LOG ----------------------------------------------------
  UI.v5_section_label("DEBUG LOG", nil, nil, SEC_LBL_SCALE, SEC_LBL_COL)

  _para("Captures full API traffic and FX scan events. When enabled, the "
     .. "complete log is attached to your bug report automatically. "
     .. "Reproduce the issue first, then send the form above.")

  Dummy(RA.ctx, 1, RA.SC(10))

  -- V5 toggle row for Enable Advanced Log.
  do
    local changed_dl, new_dl = UI.v5_toggle("##bugrpt_dbg_toggle",
      "Enable Advanced Log",
      prefs.debug_logging,
      "Log all API requests/responses (including hidden auto-follow-ups) "
        .. "and FX scan events to a file you can attach to a bug report.\n"
        .. "File: " .. Log.path,
      inner_w)
    if changed_dl then
      prefs.debug_logging = new_dl
      reaper.SetExtState(CFG.EXT_NS, "debug_logging",
        prefs.debug_logging and "1" or "0", true)
      if prefs.debug_logging then Log.session_header() end
    end
  end

  Dummy(RA.ctx, 1, RA.SC(10))

  -- Open / Save / Clear row. Same "Test API Keys" secondary style as
  -- the Diagnostic-Report buttons above (TK.card fill + TK.border +
  -- TK.text, Inter Regular SC(11), 12x6 padding, 5 radius). Fixed
  -- SC(76) width gives the three buttons a uniform pill rhythm.
  -- Centered under the Enable Advanced Log toggle.
  do
    local LOG_W, LOG_GAP = RA.SC(76), RA.SC(8)
    local LOG_ROW_W = LOG_W * 3 + LOG_GAP * 2
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - LOG_ROW_W) * 0.5), 0))

    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(12), RA.SC(6))

    if ImGui.ImGui_Button(RA.ctx, "Open##bugrpt_dbg_open", LOG_W, 0) then
      if reaper.CF_LocateInExplorer then
        reaper.CF_LocateInExplorer(Log.path)
      else
        local folder = Log.path:match("^(.*)[/\\][^/\\]+$") or Log.path
        if RA.IS_WINDOWS then
          os.execute('start "" "' .. folder .. '"')
        else
          os.execute('open "' .. folder .. '" 2>/dev/null || xdg-open "' .. folder .. '" 2>/dev/null')
        end
      end
    end
    UI.tooltip("Reveal the debug log file in your file browser")

    SameLine(RA.ctx, 0, LOG_GAP)
    if ImGui.ImGui_Button(RA.ctx, "Save##bugrpt_dbg_save", LOG_W, 0) then
      local f = io.open(Log.path, "r")
      if not f then
        S.bug_report_log_msg = "Log file not found at: " .. Log.path
        S.bug_report_log_msg_err = true
        S.bug_report_log_msg_time = reaper.time_precise()
      else
        local content = f:read("*a") or ""
        f:close()
        local default_name = str_format("Debug_%s.log",
          os.date("%Y-%m-%d_%H%M%S"))
        local default_dir = reaper.GetResourcePath() or ""
        local saved_path
        if reaper.JS_Dialog_BrowseForSaveFile then
          local ret, path = reaper.JS_Dialog_BrowseForSaveFile(
            "Save ReaAssist Debug Log",
            default_dir, default_name,
            "Log files (.log)\0*.log\0Text files (.txt)\0*.txt\0All files\0*.*\0")
          if ret == 1 and path and path ~= "" then
            if not path:match("%.log$") and not path:match("%.txt$") then
              path = path .. ".log"
            end
            saved_path = path
          end
        else
          saved_path = default_dir .. RA.SEP .. default_name
        end
        if saved_path then
          local wf, werr = io.open(saved_path, "w")
          if wf then
            wf:write(content)
            wf:close()
            S.bug_report_log_msg = "Saved: " .. saved_path
            S.bug_report_log_msg_err = false
          else
            S.bug_report_log_msg = "Save failed: " .. tostring(werr)
            S.bug_report_log_msg_err = true
          end
          S.bug_report_log_msg_time = reaper.time_precise()
        end
      end
    end
    UI.tooltip("Save a copy of the log to a location of your choice")

    SameLine(RA.ctx, 0, LOG_GAP)
    if ImGui.ImGui_Button(RA.ctx, "Clear##bugrpt_dbg_clear", LOG_W, 0) then
      Log.clear()
      S.bug_report_log_msg = "Log cleared."
      S.bug_report_log_msg_err = false
      S.bug_report_log_msg_time = reaper.time_precise()
    end
    UI.tooltip("Wipe the debug log file (useful before reproducing an issue cleanly)")

    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 5)
    PopFont(RA.ctx)
  end

  -- Toast for log actions; auto-fades after 6s.
  if S.bug_report_log_msg then
    Dummy(RA.ctx, 1, RA.SC(6))
    local elapsed = reaper.time_precise() - (S.bug_report_log_msg_time or 0)
    if elapsed < 6 then
      _toast(S.bug_report_log_msg,
        S.bug_report_log_msg_err and TK.amber or TK.green)
    else
      S.bug_report_log_msg = nil
    end
  end

  Dummy(RA.ctx, 1, RA.SC(18))

  -- No bottom "Back to Help" button -- Esc / MB4 / footer Help-toggle /
  -- logo click all cover navigation away (matches Credits + Help).
  if UI.back_pressed() then
    S.show_bug_report = false
    S.show_help = true
  end

  ImGui.ImGui_Unindent(RA.ctx, indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding

  -- V5 footer rail: outside the child, pins to outer window bottom.
  UI.footer_rail_v5()
end

-- -----------------------------------------------------------------------------
-- Render.credits_screen
-- -----------------------------------------------------------------------------
function Render.credits_screen()
  local win_w  = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x  = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w   = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local indent   = math_floor((stable_w - inner_w) * 0.5)

  local function close_credits()
    S.show_credits = false
    -- Priority mirror of close_help: footer-toggle breadcrumb first
    -- (captures full screen/modal context when footer Credits was
    -- clicked), legacy credits_return_to cookie next (pre-footer
    -- Settings / Help path), then fallback to main chat.
    local ret = S._footer_credits_ret
    if ret then
      S._footer_credits_ret = nil
      api_keys.screen   = ret.screen    or nil
      S.show_help       = ret.show_help or false
      S.show_bug_report = ret.show_bug  or false
      if not (api_keys.screen or S.show_help or S.show_bug_report) then
        S.refocus_prompt = true
      end
    elseif S.credits_return_to == "help" then
      S.show_help = true
      S.credits_return_to = nil
    else
      S.refocus_prompt = true
    end
  end

  UI.push_settings_styles()

  -- V5 hero band -- matches the Settings page exactly: wordmark +
  -- subtitle + right-side mono breadcrumb. Replaces the old
  -- UI.page_title + floating X close button; navigation is now via
  -- Esc, the Close/Back button in the body, footer links, or clicking
  -- the wordmark to return home.
  UI.hero_band_settings_v5(
    "Brought to you by Michael Briggs Mastering.",
    "CREDITS \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: same pattern as Render.settings_screen. The page
  -- is wrapped in a BeginChild whose height stops at the top of the
  -- footer rail. The child's scrollbar runs from the top of the page
  -- to the footer's top edge (not behind it), and any overflow scrolls
  -- INSIDE the child -- content physically can't draw past the child's
  -- bottom, so the footer's bg stays pristine with no ghost of content
  -- showing through. WindowPadding=0 + ChildBorderSize=0 so the
  -- scrollbar sits flush with the window's right edge.
  local FOOTER_RAIL_H = RA.SC(32)   -- matches UI.footer_rail_v5's ROW_H
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##credits_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, indent)
  Dummy(RA.ctx, 1, RA.SC(10))

  -- Credits body. ABOUT + SUPPORT are prose containers (TK.card); LINKS
  -- + CONTACT are tables of labelled link rows via UI.v5_link_row --
  -- same pill chrome as the Preferred Plugins button on Settings, but
  -- with an external-link diagonal arrow instead of the `>` chevron.

  -- Shared chrome helper for prose cards (ABOUT, SUPPORT).
  local function _begin_card(id)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),  RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),  RA.SC(12), RA.SC(8))
    return ImGui.ImGui_BeginChild(RA.ctx, "##credits_" .. id, inner_w, 0,
      ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders())
  end
  local function _pop_card_chrome()
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 2)
  end


  -- ---- ABOUT ---------------------------------------------------------
  UI.v5_section_label("ABOUT")
  if _begin_card("about") then
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    PushFont(RA.ctx, nil, RA.SC(13))
    ImGui.ImGui_PushTextWrapPos(RA.ctx, 0)
    Text(RA.ctx,
      "Michael Briggs is an award-winning audio engineer and producer "
      .. "based in Denton, Texas, available for production, mixing, "
      .. "recording, and mastering. He has worked with over 400 artists "
      .. "on more than 3,000 songs across just about every genre. "
      .. "Voted Best Producer and Best Audio Engineer in North Texas.")
    PopStyleColor(RA.ctx)   -- release TK.text before pushing the muted tone

    -- Short blurb about what ReaAssist is + isn't. Rendered in
    -- TK.text_muted so it reads as a secondary disclaimer under the
    -- primary bio above, not a peer paragraph. The two together
    -- answer "who built this and why."
    Dummy(RA.ctx, 1, RA.SC(8))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx,
      "ReaAssist was designed to give you modern tools that aid the "
      .. "technical side of your productions and improve your workflow. "
      .. "This is purely a workflow assistant and is not designed or "
      .. "intended to be used for any type of generative creative content.")
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx)
    ImGui.ImGui_EndChild(RA.ctx)
  end
  _pop_card_chrome()
  Dummy(RA.ctx, 1, RA.SC(5))

  -- 2-column grid: every link row is (inner_w - gap) / 2 wide, laid
  -- out side-by-side via SameLine. Reads as a composed mini-directory
  -- instead of a tall list of stretched pills. Icon on each row
  -- (link for sites, mail for emails) carries the type distinction --
  -- no descriptor labels needed since the value itself is self-
  -- evident from its glyph + content.
  local GRID_GAP = RA.SC(8)
  local ROW_W    = math_floor((inner_w - GRID_GAP) / 2)
  local ROW_GAP  = RA.SC(5)   -- vertical gap between grid rows

  -- ---- LINKS ---------------------------------------------------------
  -- 2x2 grid: two production/mastering sites on row A, ReaAssist.app +
  -- free-sample CTA on row B. Free-sample is now a real web page
  -- (/free-sample/), so it uses the link glyph like the others --
  -- reads as a peer, not a special-cased mailto.
  UI.v5_section_label("LINKS")
  UI.v5_link_row("##credits_link_site", nil,
    "MichaelBriggs.audio", "https://michaelbriggs.audio/?mtm_campaign=reaassist", ICON.LINK,
    "Production / mixing / recording site", ROW_W)
  SameLine(RA.ctx, 0, GRID_GAP)
  UI.v5_link_row("##credits_link_mastering", nil,
    "MichaelBriggsMastering.com", "https://michaelbriggsmastering.com/?mtm_campaign=reaassist",
    ICON.LINK, "Mastering site", ROW_W)

  Dummy(RA.ctx, 1, ROW_GAP)

  UI.v5_link_row("##credits_link_reaassist", nil,
    "ReaAssist.app", "https://reaassist.app/?mtm_campaign=reaassist", ICON.LINK,
    "Project site for ReaAssist", ROW_W)
  SameLine(RA.ctx, 0, GRID_GAP)
  UI.v5_link_row("##credits_link_sample", nil,
    "Request a Free Mastering Sample",
    "https://michaelbriggsmastering.com/free-sample/?mtm_campaign=reaassist", ICON.LINK,
    "Submit a free mastering sample request", ROW_W)

  Dummy(RA.ctx, 1, RA.SC(9))

  -- ---- CONTACT -------------------------------------------------------
  -- Single grid row with the two contact emails side-by-side. Mail
  -- glyph + address is enough to convey meaning -- the "Direct /
  -- Support" distinction reads from the addresses themselves (named
  -- inbox vs. help@) so explicit descriptor labels would be noise.
  UI.v5_section_label("CONTACT")
  UI.v5_link_row("##credits_ct_direct", nil,
    "michael@michaelbriggs.audio", "mailto:michael@michaelbriggs.audio",
    ICON.MAIL, "Email Michael directly", ROW_W)
  SameLine(RA.ctx, 0, GRID_GAP)
  UI.v5_link_row("##credits_ct_support", nil,
    "help@reaassist.app", "mailto:help@reaassist.app", ICON.MAIL,
    "Email the ReaAssist support address", ROW_W)

  Dummy(RA.ctx, 1, RA.SC(9))

  -- ---- SUPPORT REAASSIST ---------------------------------------------
  -- Flat (no container card). Button-first, then the muted explanatory
  -- line below it -- the CTA leads, the caption supports. Sitting
  -- directly on the page background keeps the section light.
  UI.v5_section_label("SUPPORT REAASSIST")

  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  UI.push_modal_primary_btn()
  if ImGui.ImGui_Button(RA.ctx, "Donate##credits_donate", RA.SC(92), RA.SC(26)) then
    UI.open_url("https://www.paypal.com/paypalme/civil")
  end
  if ImGui.ImGui_IsItemHovered(RA.ctx) then
    ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
  end
  UI.pop_modal_primary_btn()
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)

  Dummy(RA.ctx, 1, RA.SC(4))

  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
  PushFont(RA.ctx, nil, RA.SC(12))
  ImGui.ImGui_PushTextWrapPos(RA.ctx, 0)
  Text(RA.ctx, "Donations help keep this project moving forward.")
  ImGui.ImGui_PopTextWrapPos(RA.ctx)
  PopFont(RA.ctx)
  PopStyleColor(RA.ctx)

  if UI.back_pressed() then close_credits() end

  ImGui.ImGui_Unindent(RA.ctx, indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding
  UI.pop_settings_styles()

  -- V5 footer rail: rendered on the OUTER window drawlist after the
  -- child closes, so it paints on top of the window edge below the
  -- child's scroll region. Content that scrolls past the child's
  -- bottom is clipped by the child itself -- the footer reads as a
  -- clean opaque strip with nothing bleeding through.
  UI.footer_rail_v5()
end

-- -----------------------------------------------------------------------------
-- Render.api_key_screen
-- -----------------------------------------------------------------------------
-- Full-window API key entry screen with three sections (one per provider).
-- Render._factory_reset_popup
-- Renders the Factory Reset confirmation modal. Sets
-- Render._factory_reset_pending = true when the user confirms, so the
-- parent screen can execute the reset logic (which touches screen-local
-- state like api_keys.screen and is_reentry).
-- Callable from any screen that opens "##factory_reset_confirm"; the
-- modal is rendered in the current context, matching the screen's
-- center-of-window positioning.

-- Render._factory_reset_execute
-- Shared implementation of the Factory Reset flow. Called from the
-- Settings page's ADVANCED section when the user confirms the popup.
-- Wipes every ExtState key in CFG.EXT_NS by parsing
-- reaper-extstate.ini directly -- no hand-maintained key list to fall
-- out of sync with SetExtState call sites -- then restores in-memory
-- defaults and navigates back to the TOS screen.
function Render._factory_reset_execute()
  -- Restore any modified theme colors before wiping state, so the user
  -- doesn't get stuck with a modified REAPER theme and no way to revert.
  pcall(Theme.restore_backups)
  -- Unregister every custom provider from the in-memory PROVIDERS table.
  pcall(Custom.unregister_all)
  -- Gemini explicit cache: clear in-memory state, persisted ExtState
  -- keys (gemini_cache_name/model/expires), and fire server-side DELETE.
  pcall(Net.gemini_cache_invalidate)

  -- Delete every persisted ExtState key under our section by
  -- enumerating the reaper-extstate.ini file directly. Robust to legacy
  -- keys and new additions; nothing to hand-maintain.
  do
    local ini_path = reaper.GetResourcePath() .. "/reaper-extstate.ini"
    local f = io.open(ini_path, "r")
    if f then
      local keys = {}
      local in_section = false
      local line_no = 0
      for line in f:lines() do
        line_no = line_no + 1
        -- Strip a UTF-8 BOM if present on the first line. Some text
        -- editors add it, and without this strip the first section
        -- header (`[reaassist]`) wouldn't match and the entire reset
        -- would silently no-op on the live keys.
        if line_no == 1 then line = line:gsub("^\xEF\xBB\xBF", "") end
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and not line:match("^[;#]") then
          local sec = line:match("^%[(.-)%]$")
          if sec then
            in_section = (sec == CFG.EXT_NS)
          elseif in_section then
            local key = line:match("^([^=]+)")
            if key then
              -- f:lines() strips '\n' but not '\r'. On a CRLF-newline
              -- ini file the captured key would end with a literal '\r'
              -- and DeleteExtState would not match the live key name.
              key = key:match("^%s*(.-)%s*$") or ""
              key = key:gsub("\r$", "")
              if key ~= "" then keys[#keys + 1] = key end
            end
          end
        end
      end
      f:close()
      for _, k in ipairs(keys) do
        reaper.DeleteExtState(CFG.EXT_NS, k, true)
      end
    end
  end
  -- Transient session locks (persist=false -- never hit the .ini file
  -- so the enumeration above misses them).
  reaper.DeleteExtState(CFG.EXT_NS, "running",       false)
  reaper.DeleteExtState(CFG.EXT_NS, "request_close", false)

  -- Suppress in-session re-writes that would otherwise repopulate the
  -- .ini file within seconds. Cleared by the relauncher fire below;
  -- if the relauncher fails we leave them set and surface a toast so
  -- the user knows to close-and-reopen manually.
  S._suppress_geometry_save  = true  -- stops the periodic win_x/y/w/h save
  S._suppress_os_theme_cache = true  -- stops detect_os_theme from re-caching
  -- Reset every in-memory pref to its documented default. Without this,
  -- any pref the running script later writes via SetExtState (provider
  -- switch, debug-logging toggle, etc.) would re-persist its OLD
  -- in-memory value into the just-cleared .ini, leaving the user with
  -- a non-default config that "factory reset" was supposed to wipe.
  -- Schema mirror of the prefs table at ReaAssist.lua:~2331.
  prefs.auto_run              = false
  prefs.auto_backup           = true
  prefs.show_details          = false
  prefs.debug_logging         = true   -- default ON during early-release window; mirror of ReaAssist.lua prefs load site
  prefs.include_api_ref       = false
  prefs.include_snapshot      = true
  prefs.update_check          = true
  prefs.test_force_cold_cache = false
  prefs.cloud_request_timeout = CFG.CLOUD_TIMEOUT_DEFAULT
  prefs.provider_idx          = 1   -- 1=Claude
  prefs.model_idx             = 2   -- MODELS.refresh sets the real value when a provider becomes active
  prefs.thinking_idx          = 0   -- 0 = no thinking; MODELS.refresh sets per-provider
  prefs.ui_scale_idx          = 3   -- 100%
  prefs.theme                 = "auto"
  prefs.chat_font_idx         = 2   -- Medium
  prefs.help_font_scale       = 1.0
  apply_palette(PALETTES[resolve_theme("auto")])
  S._reset_window_size = true
  Net.clear_conversation()
  S.api_key  = nil
  S.api_key_map = {}
  S.gemini_paid_tier = nil
  api_keys.custom_edit = nil
  os.remove(RA.FX_CACHE_PATH)
  FXCache.invalidate()
  api_keys.screen     = "tos"
  api_keys.is_reentry = false
  S.refocus_prompt = true
  -- Auto-relaunch so the user gets a true fresh-install state. The
  -- _suppress_* flags above are necessary mid-reset to keep the still-
  -- running script from immediately re-saving stale geometry / theme
  -- cache; a script restart is the cleanest way to clear them without
  -- leaving the session in a half-functional state where window resize
  -- is permanently suppressed. If the relauncher can't register, fall
  -- back to a clear toast so the user knows to close-and-reopen by hand.
  if not Updater.fire_relauncher_now() then
    UI.show_float_toast(
      "Reset complete. Close and reopen ReaAssist to finish.", "ok", true)
  end
end

function Render._factory_reset_popup(ctx)
  local fr_w, fr_h = RA.SC(340), RA.SC(150)
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(ctx,
      update._main_x + (update._main_w - fr_w) * 0.5,
      update._main_y + (update._main_h - fr_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(ctx, fr_w, fr_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(ctx, "Factory Reset##factory_reset_confirm", true,
      ImGui.ImGui_WindowFlags_NoResize()) then
    local fr_cw = ImGui.ImGui_GetContentRegionAvail(ctx)
    ImGui.ImGui_Spacing(ctx)
    local fr_txt = "Reset all settings and restart as new?"
    local fr_tw  = CalcTextSize(ctx, fr_txt)
    SetCursorPosX(ctx, GetCursorPosX(ctx)
      + math_floor((fr_cw - fr_tw) * 0.5))
    Text(ctx, fr_txt)
    ImGui.ImGui_Spacing(ctx)
    ImGui.ImGui_Spacing(ctx)

    local fr_do_reset = false
    local fr_yes_w, fr_no_w, fr_gap = RA.SC(88), RA.SC(72), RA.SC(16)
    local fr_row = fr_yes_w + fr_gap + fr_no_w
    SetCursorPosX(ctx, GetCursorPosX(ctx)
      + math_floor((fr_cw - fr_row) * 0.5))
    -- Factory reset is destructive -- use the V5 danger-button palette
    -- (red fill, white text) so the commit button reads as "this will
    -- wipe your data," not "safe primary action."
    UI.push_modal_danger_btn()
    if ImGui.ImGui_Button(ctx, "Confirm", fr_yes_w, 0) then fr_do_reset = true end
    UI.pop_modal_danger_btn()
    SameLine(ctx, 0, fr_gap)
    if ImGui.ImGui_Button(ctx, "Cancel", fr_no_w, 0) then
      ImGui.ImGui_CloseCurrentPopup(ctx)
    end
    if ImGui.ImGui_IsKeyPressed(ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(ctx, ImGui.ImGui_Key_KeypadEnter()) then
      fr_do_reset = true
    end
    if ImGui.ImGui_IsKeyPressed(ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(ctx)
    end
    if fr_do_reset then
      Render._factory_reset_pending = true
      ImGui.ImGui_CloseCurrentPopup(ctx)
    end
    ImGui.ImGui_EndPopup(ctx)
  end
  UI.pop_modal_style()
end

-- Render._key_test_results_popup
-- Shared "API Key Test Results" popup. Rendered by both the first-run and
-- Settings screens so the popup comes up wherever the user fired the
-- Test API Keys button from. Closes on OK / Enter / Esc. The popup never
-- navigates away -- the calling screen stays put so the user can keep
-- editing afterward.
function Render._key_test_results_popup()
  if api_keys.show_test_results then
    api_keys.show_test_results = false
    ImGui.ImGui_OpenPopup(RA.ctx, "API Key Test Results##popup")
  end
  local all_ok = true
  for _, r in pairs(api_keys.test_results) do
    if not r.ok then all_ok = false; break end
  end
  local res_w, res_h = RA.SC(380), all_ok and RA.SC(140) or RA.SC(220)
  local result_count = 0
  for _ in pairs(api_keys.test_results) do result_count = result_count + 1 end
  if result_count > 3 then res_h = res_h + (result_count - 3) * RA.SC(22) end
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - res_w) * 0.5,
      update._main_y + (update._main_h - res_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, res_w, res_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "API Key Test Results##popup", true,
      ImGui.ImGui_WindowFlags_NoResize()) then
    local cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    if all_ok then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.green)
      local ok_txt = "All API Keys Tested and Working"
      local ok_tw  = CalcTextSize(RA.ctx, ok_txt)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx) + math_floor((cw - ok_tw) * 0.5))
      Text(RA.ctx, ok_txt)
      PopStyleColor(RA.ctx)
    else
      Text(RA.ctx, "Test Results:")
      ImGui.ImGui_Spacing(RA.ctx)
      for _, pk in ipairs(PROVIDERS) do
        local r = (not pk.hidden) and api_keys.test_results[pk.id] or nil
        if r then
          if r.ok then
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.green)
            Text(RA.ctx, "  " .. r.label .. ": OK")
            PopStyleColor(RA.ctx)
          else
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
            Text(RA.ctx, "  " .. r.label .. ": FAILED")
            PopStyleColor(RA.ctx)
            if r.error then
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
              -- Error text can carry \n from upstream curl/HTTP errors;
              -- text_multiline avoids TextWrapped's window-state corruption.
              UI.text_multiline("    " .. r.error)
              PopStyleColor(RA.ctx)
            end
          end
        end
      end
    end
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    local ok_btn_w = RA.SC(88)
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((cw - ok_btn_w) * 0.5))
    UI.push_modal_primary_btn()
    local dismiss = ImGui.ImGui_Button(RA.ctx, "OK", ok_btn_w, 0)
    UI.pop_modal_primary_btn()
    if dismiss
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_modal_style()
end

-- =============================================================================
-- Render.feedback_modal
-- =============================================================================
-- Manual feedback dialog. Opened by clicking "What went right, what went
-- wrong?" below an assistant message. The link itself sends nothing; this
-- modal is the consent moment. The preview is ALWAYS visible (not behind
-- a collapsing header) and is the EXACT bytes that Send would post --
-- preview_payload_text and send_draft both render the same draft + comment
-- + flags through Diag.assemble_payload.
local function _close_feedback_modal()
  S.feedback_modal_open       = false
  S._feedback_modal_opened    = false
  S.feedback_modal_draft      = nil
  S.feedback_modal_target_idx = nil
  S.feedback_modal_comment    = nil
  S.feedback_modal_flags      = nil
  S.feedback_modal_state      = nil
  S.feedback_modal_error      = nil
  -- Reset the collapsible-section open state so each modal open starts
  -- with both Preview feedback and the privacy panel closed (treat the
  -- modal as a one-shot consent dialog rather than a persistent
  -- workspace).
  S.feedback_modal_preview_open = nil
  S.feedback_modal_privacy_open = nil
end

-- Compatibility helpers: ImGui_BeginDisabled was added in a later ReaImGui
-- and isn't used elsewhere in this file. If absent, the visual disabled
-- state is skipped -- the manual `if not (sending or success) then` guards
-- below prevent state mutation regardless of the visual.
local _fb_has_disabled = type(ImGui.ImGui_BeginDisabled) == "function"
local function _fb_begin_disabled(b)
  if _fb_has_disabled then ImGui.ImGui_BeginDisabled(RA.ctx, b) end
end
local function _fb_end_disabled()
  if _fb_has_disabled then ImGui.ImGui_EndDisabled(RA.ctx) end
end

function Render.feedback_modal()
  if not S.feedback_modal_open then
    S._feedback_modal_opened = false
    return
  end

  local draft = S.feedback_modal_draft
  if not draft then
    _close_feedback_modal()
    return
  end

  if not S._feedback_modal_opened then
    S._feedback_modal_opened = true
    ImGui.ImGui_OpenPopup(RA.ctx, "Send Feedback##fb_modal")
  end

  -- Clamp height to fit inside main window with a margin. Width and
  -- height both tightened post-redesign: the modal is mostly thumbs +
  -- comment + collapsibles and reads cleaner at this size.
  local mw     = RA.SC(490)
  local main_h = update._main_h or RA.SC(760)
  local mh     = math.min(RA.SC(620), math.max(RA.SC(320), main_h - RA.SC(140)))

  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - mw) * 0.5,
      update._main_y + (main_h - mh) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, mw, mh, ImGui.ImGui_Cond_Appearing())

  UI.push_modal_style()
  -- Scrollbar palette pushed BEFORE BeginPopupModal so the popup window's
  -- own scrollbar (visible when content overflows mh) inherits the
  -- TK.border_str palette too. Pushing inside the popup body only affects
  -- nested BeginChild scrollbars, not the popup's own. Popped after
  -- pop_modal_style on both branches.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "Send Feedback##fb_modal", true,
      ImGui.ImGui_WindowFlags_NoResize()) then

    -- Very faint vertical gradient over the modal body. The home / Settings
    -- hero uses TK.accent_soft -> TK.bg full-strength; for the modal we
    -- want a barely-perceptible tint, so the top color is lerped 80%
    -- toward TK.bg before the gradient draws. Drawn onto the window draw
    -- list FIRST so subsequent ImGui content renders on top of it.
    do
      local _dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      local _wx, _wy = ImGui.ImGui_GetWindowPos(RA.ctx)
      local _ww, _wh = ImGui.ImGui_GetWindowSize(RA.ctx)
      local _top = UI.lerp_u32(TK.accent_soft, TK.bg, 0.80)
      ImGui.ImGui_DrawList_AddRectFilledMultiColor(_dl,
        _wx, _wy, _wx + _ww, _wy + _wh,
        _top, _top, TK.bg, TK.bg)
    end

    -- Push input frame colors so the comment box and (when expanded) the
    -- preview read as recessed text wells against the modal_bg, instead of
    -- the global theme FrameBg which clashes (washed-out blue on the light
    -- theme). TK.input_bg is the canonical "field" tone used by the
    -- Settings API-key input cards.
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),        TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(), TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),  TK.input_bg)

    local cw      = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    local sending = S.feedback_modal_state == "sending"
    local success = S.feedback_modal_state == "success"
    local locked  = sending or success
    local f       = S.feedback_modal_flags

    -- In-body title heading. The popup title-bar text is small and easy
    -- to miss; an explicit heading anchors the top of the modal. Sized a
    -- step below the bug-report hero (SC(22) wordmark + SC(16) subtitle)
    -- so the modal feels like a focused surface rather than a peer page.
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(17))
    Text(RA.ctx, "Send Feedback")
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx, "Help improve ReaAssist")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(10))

    -- Intro
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    UI.text_multiline(
      "Sends the current chat session plus your tags and comment below "
      .. "to help improve ReaAssist. API keys, bearer tokens, and home "
      .. "paths are automatically redacted before sending. Project, "
      .. "track, or plugin names you typed may still appear in the chat "
      .. "content; review the preview to verify. Audio is never sent."
    )
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(4))

    -- Cross-link to the full bug-report flow. Three Text calls chained via
    -- SameLine(0, 0) so the "Bug Reports" segment is the only clickable
    -- region (accent color + hand cursor on hover). Clicking closes the
    -- modal and pops the user onto the Bug Report page, which has space
    -- for an Advanced Log attachment plus name/email contact fields. Sized
    -- at SC(11) Inter Regular so the line reads as a peer of the intro
    -- paragraph above.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx, "See the ")
    PopStyleColor(RA.ctx)
    SameLine(RA.ctx, 0, 0)

    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.accent)
    Text(RA.ctx, "Bug Reports")
    local _br_link_clicked = ImGui.ImGui_IsItemClicked(RA.ctx)
    if ImGui.ImGui_IsItemHovered(RA.ctx) then
      ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
    end
    PopStyleColor(RA.ctx)
    SameLine(RA.ctx, 0, 0)

    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx, " screen to send an advanced report with the full log.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)

    if _br_link_clicked and not locked then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      _close_feedback_modal()
      S.show_bug_report = true
    end

    Dummy(RA.ctx, 1, RA.SC(8))

    -- ──── TAGS section (Option A: thumbs sentiment + conditional chips).
    --
    -- Layout:
    --   thumbs-up / thumbs-down sentiment buttons (mutually exclusive)
    --   when thumbs_down: "What went wrong?" + multi-select chip row
    --
    -- Why this shape: matches the dominant pattern in other AI assistants
    -- (ChatGPT, Claude.ai, Gemini), reduces vertical clutter for the
    -- common 👍 case (one-click), and surfaces the secondary "what went
    -- wrong" tags only when they're relevant -- exactly the analysis
    -- signal we care about.
    UI.v5_section_label("HOW DID IT GO?")
    Dummy(RA.ctx, 1, RA.SC(6))

    -- Local helpers (modal-private; not promoted to UI.* since they're
    -- one-off styling for this dialog).
    --
    -- Hover affordance: ImGui_Button only colours the background on
    -- hover, not the border or text. To get a "subtle accent on hover"
    -- like the rest of the V5 surface (where icons + borders shift
    -- toward TK.accent), we render the button with a low-alpha
    -- accent-tinted hover bg AND overlay an accent rect-stroke after
    -- the button when hovered. Selected state stays full accent fill,
    -- so the overlay is a no-op there.
    local function _fb_overlay_hover_border(rounding)
      local x1, y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local x2, y2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
      local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      ImGui.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2,
        TK.accent, rounding, 0, 1)
    end

    local function _fb_thumb_btn(id, icon, selected, btn_w, btn_h, tooltip)
      local fill_col = selected and TK.accent or 0x00000000
      local bord_col = selected and TK.accent or TK.border
      local text_col = selected and TK.accent_text or TK.text_muted
      -- Unselected hover: accent at ~20% alpha tints the bg toward
      -- accent without overpowering. Selected hover stays full accent.
      local hov_col  = selected and TK.accent or
                       ((TK.accent & 0xFFFFFF00) | 0x33)
      local act_col  = selected and TK.accent or
                       ((TK.accent & 0xFFFFFF00) | 0x55)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        fill_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), hov_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  act_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        bord_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          text_col)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(6))
      PushFont(RA.ctx, FONT.lucide, RA.SC(18))
      local clicked = ImGui.ImGui_Button(RA.ctx, icon .. "##" .. id,
        btn_w, btn_h)
      PopFont(RA.ctx)
      ImGui.ImGui_PopStyleVar(RA.ctx, 2)
      PopStyleColor(RA.ctx, 5)
      local hovered = ImGui.ImGui_IsItemHovered(RA.ctx)
      if hovered then
        if not selected then _fb_overlay_hover_border(RA.SC(6)) end
        if tooltip then UI.tooltip(tooltip) end
      end
      return clicked
    end

    local function _fb_chip(id, label, selected)
      local fill_col = selected and TK.accent or 0x00000000
      local bord_col = selected and TK.accent or TK.border
      local text_col = selected and TK.accent_text or TK.text_muted
      local hov_col  = selected and TK.accent or
                       ((TK.accent & 0xFFFFFF00) | 0x33)
      local act_col  = selected and TK.accent or
                       ((TK.accent & 0xFFFFFF00) | 0x55)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        fill_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), hov_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  act_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        bord_col)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          text_col)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(12))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),
        RA.SC(12), RA.SC(5))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      local clicked = ImGui.ImGui_Button(RA.ctx, label .. "##" .. id)
      PopFont(RA.ctx)
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopStyleColor(RA.ctx, 5)
      if not selected and ImGui.ImGui_IsItemHovered(RA.ctx) then
        _fb_overlay_hover_border(RA.SC(12))
      end
      return clicked
    end

    -- Thumbs sentiment row: two equal-width buttons side by side.
    _fb_begin_disabled(locked)
    local THUMB_W = math.floor((cw - RA.SC(8)) * 0.5)
    local THUMB_H = RA.SC(40)
    if _fb_thumb_btn("fb_thumb_up", ICON.THUMBS_UP, f.thumbs_up,
        THUMB_W, THUMB_H, "Helpful") and not locked then
      if f.thumbs_up then
        f.thumbs_up = false
      else
        f.thumbs_up   = true
        f.thumbs_down = false
        -- Clear any previously-set secondary tags so they don't ride
        -- along on a sentiment that no longer applies.
        f.wrong_result, f.too_slow, f.wrong_plugin, f.didnt_follow_request
          = false, false, false, false
      end
    end
    SameLine(RA.ctx, 0, RA.SC(8))
    if _fb_thumb_btn("fb_thumb_down", ICON.THUMBS_DOWN, f.thumbs_down,
        THUMB_W, THUMB_H, "Not helpful") and not locked then
      if f.thumbs_down then
        f.thumbs_down = false
        -- Collapse the follow-up chip row by clearing its selections too,
        -- so re-opening 👎 starts on a clean slate (and the payload
        -- doesn't keep stale flags from a previous 👎/un-👎 cycle).
        f.wrong_result, f.too_slow, f.wrong_plugin, f.didnt_follow_request
          = false, false, false, false
      else
        f.thumbs_down = true
        f.thumbs_up   = false
      end
    end
    _fb_end_disabled()

    -- Conditional follow-up: revealed only when thumbs_down. The chips
    -- wrap to a second row when needed via SameLine + width-aware breaks
    -- (ImGui doesn't auto-wrap buttons, so we measure each label and
    -- start a new line when the cumulative width would overflow cw).
    if f.thumbs_down then
      Dummy(RA.ctx, 1, RA.SC(10))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, "What went wrong?")
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
      Dummy(RA.ctx, 1, RA.SC(6))

      _fb_begin_disabled(locked)
      local chips = {
        { "fb_tag_wrong",   "Wrong result",            "wrong_result" },
        { "fb_tag_plugin",  "Wrong plugin",            "wrong_plugin" },
        { "fb_tag_didnt",   "Didn't follow request",   "didnt_follow_request" },
        { "fb_tag_slow",    "Too slow",                "too_slow" },
      }
      -- Track horizontal cursor to break to next row before overflow.
      -- ImGui_Button width auto-fits content + FramePadding; CalcTextSize
      -- gives us the inner text width, so the rendered button width is
      -- text_w + 2 * padding_x (12px each side) + FrameBorderSize (~1).
      local CHIP_PAD_X = RA.SC(12)
      local CHIP_GAP   = RA.SC(6)
      local row_w = 0
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      for i, c in ipairs(chips) do
        local id, label, key = c[1], c[2], c[3]
        local tw = CalcTextSize(RA.ctx, label)
        local btn_w = tw + CHIP_PAD_X * 2 + 2
        local need_w = (i == 1) and btn_w or (CHIP_GAP + btn_w)
        if i > 1 and (row_w + need_w) > cw then
          -- Wrap: start a fresh row.
          row_w = 0
        elseif i > 1 then
          SameLine(RA.ctx, 0, CHIP_GAP)
        end
        PopFont(RA.ctx)   -- chip pushes its own font; restore measurement font afterward
        if _fb_chip(id, label, f[key]) and not locked then
          f[key] = not f[key]
        end
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
        row_w = row_w + need_w
      end
      PopFont(RA.ctx)
      _fb_end_disabled()
    end

    -- ──── COMMENTS section (free-text). Below the sentiment row so the
    -- quick-classify path is on top and the comment box is the optional
    -- elaboration step.
    Dummy(RA.ctx, 1, RA.SC(12))
    UI.v5_section_label("COMMENTS")
    Dummy(RA.ctx, 1, RA.SC(4))
    -- Capture screen pos BEFORE the input so we can overlay a placeholder
    -- text when the field is empty. ImGui's InputTextWithHint helper is
    -- single-line only; for multi-line we draw the hint manually onto the
    -- window draw list at the input's top-left + the InputText frame
    -- padding.
    local _fb_comment_x, _fb_comment_y = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
    _fb_begin_disabled(locked)
    -- Push input font + explicit text colors. The caret in particular
    -- needs Col_InputTextCursor (a separate ImGui slot) -- pushing only
    -- Col_Text leaves the caret using the global default which renders
    -- white on the light theme's pale input_bg. Same fix used by the
    -- chat selection InputTextMultiline at line ~3528.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(14))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),            TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(), TK.text)
    -- Snapshot the buffer BEFORE InputTextMultiline so the Enter-to-Send
    -- handler can restore it (stripped of trailing \n) when Enter fires
    -- from inside the comment box. Without this restore, the \n that
    -- ImGui already inserted on the same frame would leak into
    -- user_comment. Mirrors the chat prompt pattern at line ~14875.
    local _fb_prev_comment = S.feedback_modal_comment or ""
    local _rv, new_comment = ImGui.ImGui_InputTextMultiline(RA.ctx,
      "##fb_comment", S.feedback_modal_comment or "",
      cw, RA.SC(78), 0, nil)
    -- Capture focus state so the Enter-to-Send handler below can
    -- distinguish "Enter pressed while typing" (need to strip the \n
    -- ImGui just inserted) from "Enter pressed elsewhere in the modal"
    -- (no buffer mutation needed).
    local _fb_comment_active = ImGui.ImGui_IsItemActive(RA.ctx)
    PopStyleColor(RA.ctx, 2)
    PopFont(RA.ctx)
    if not locked then S.feedback_modal_comment = new_comment end
    _fb_end_disabled()
    if (S.feedback_modal_comment or "") == "" then
      -- Placeholder adapts to the current sentiment: a generic prompt
      -- when neither thumb is selected, then a tailored question after
      -- the user picks a thumb. Switching back to neutral (deselecting)
      -- restores the generic prompt.
      local _fb_placeholder
      if f.thumbs_up then
        _fb_placeholder = "What went right? How did this help you?"
      elseif f.thumbs_down then
        _fb_placeholder = "What went wrong? How could this chat have gone better?"
      else
        _fb_placeholder = "What went right, what went wrong?"
      end
      local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      ImGui.ImGui_DrawList_AddTextEx(dl, FONT.inter_reg, RA.SC(13),
        _fb_comment_x + RA.SC(12), _fb_comment_y + RA.SC(10),
        TK.text_faint, _fb_placeholder)
    end

    -- ──── Preview Report -- collapsible sub-section. Modeled on the
    -- Help > Report a Bug page's "Preview Report" expander (same
    -- v5_section_label + bordered child + mono font pattern). Closed by
    -- default. When expanded, shows the EXACT JSON bytes that Send would
    -- post (preview_payload_text and send_draft both render the same
    -- draft + comment + flags through Diag.assemble_payload). Walked
    -- line-by-line with TextWrapped so the box shape and styling match
    -- the bug-report preview rather than ImGui's default text-input look.
    Dummy(RA.ctx, 1, RA.SC(14))
    S.feedback_modal_preview_open = S.feedback_modal_preview_open or false
    S.feedback_modal_preview_open = UI.v5_section_label(
      "Preview feedback",
      S.feedback_modal_preview_open, nil, 1.0, TK.text_muted)
    if S.feedback_modal_preview_open then
      local preview = Diag.preview_payload_text(draft,
        S.feedback_modal_comment or "", f)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.code_bg)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),    TK.text)
      -- Scrollbar palette pushed locally too (belt + suspenders alongside
      -- the modal-level push) so the preview child's own scrollbar reads
      -- light in light mode regardless of how scope inheritance shakes
      -- out across nested popup -> child -> child windows.
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
        UI.lerp_u32(TK.border_str, TK.text, 0.30))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
        UI.lerp_u32(TK.border_str, TK.text, 0.55))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(5))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(10), RA.SC(8))
      if ImGui.ImGui_BeginChild(RA.ctx, "##fb_preview_child",
          cw, RA.SC(220), ImGui.ImGui_ChildFlags_Borders()) then
        -- Right-click anywhere in the preview body -> Copy full payload
        -- text to clipboard. Lets users grab the exact JSON they're
        -- about to send for offline inspection without having to
        -- triple-click + select-all + Ctrl-C through a non-selectable
        -- TextWrapped widget.
        if ImGui.ImGui_BeginPopupContextWindow(RA.ctx, "##fb_preview_ctx") then
          if ImGui.ImGui_MenuItem(RA.ctx, "Copy") then
            ImGui.ImGui_SetClipboardText(RA.ctx, preview)
          end
          ImGui.ImGui_EndPopup(RA.ctx)
        end
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        local rp = 1
        while rp <= #preview do
          local nl = str_find(preview, "\n", rp, true)
          local line = nl and str_sub(preview, rp, nl - 1) or str_sub(preview, rp)
          if line == "" then
            Dummy(RA.ctx, 1, 4)
          else
            ImGui.ImGui_TextWrapped(RA.ctx, line)
          end
          if not nl then break end
          rp = nl + 1
        end
        PopFont(RA.ctx)
        ImGui.ImGui_EndChild(RA.ctx)
      end
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopStyleColor(RA.ctx, 7)   -- ChildBg, Border, Text + Scrollbar x4
      Dummy(RA.ctx, 1, RA.SC(6))
    end

    -- ──── What's in the Report (privacy) -- collapsible sub-section.
    -- Modeled on the bug-report page's privacy expander but adapted to
    -- the feedback flow (which sends chat content + comment + tags +
    -- diag report, redacted before send). Closed by default.
    S.feedback_modal_privacy_open = S.feedback_modal_privacy_open or false
    S.feedback_modal_privacy_open = UI.v5_section_label(
      "Details & privacy",
      S.feedback_modal_privacy_open, nil, 1.0, TK.text_muted)
    if S.feedback_modal_privacy_open then
      -- 2x2 grid of compact bordered mini-panels. Each panel has a bold
      -- short header (1-2 words) + 2-4 bullets. Heights are normalised
      -- per row -- both panels in a row render at max(content_a, content_b)
      -- so the grid reads as uniform tiles instead of ragged auto-sized
      -- cards.
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),
        RA.SC(10), RA.SC(2))

      local _avail_w  = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      local _grid_gap = RA.SC(8)
      local _panel_w  = math.floor((_avail_w - _grid_gap) / 2)

      -- Approximate the rendered height of one panel's content. Uses the
      -- exact fonts the renderer uses + the same wrap width so the
      -- result tracks reality. Includes WindowPadding (top + bottom) +
      -- the SC(4) Dummy between header and items + ItemSpacing.y between
      -- bullets, then trims one trailing ItemSpacing since the last
      -- bullet doesn't add a gap below.
      local _item_wrap = _panel_w - RA.SC(20)
      local _pad_y    = RA.SC(8)
      local _spacing_y = RA.SC(2)
      local function _panel_h(header, items)
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        local _, hh = ImGui.ImGui_CalcTextSize(RA.ctx, header)
        PopFont(RA.ctx)
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
        local items_h = 0
        for _, item in ipairs(items) do
          -- ReaImGui CalcTextSize signature: (ctx, text, off_x?, off_y?,
          -- hide_text_after_double_hash, wrap_width). Positions 3-4 are
          -- nil so the call measures from the text origin, not an offset.
          local _, ih = ImGui.ImGui_CalcTextSize(RA.ctx,
            "\xe2\x80\xa2 " .. item, nil, nil, false, _item_wrap)
          items_h = items_h + ih + _spacing_y
        end
        PopFont(RA.ctx)
        if #items > 0 then items_h = items_h - _spacing_y end
        -- Header line + Dummy(SC(4)) + items + WindowPadding top + bot.
        -- + SC(8) safety margin: CalcTextSize's wrapped height tends to
        -- run ~1-2 px shy of the actual rendered height per wrapped line
        -- (ItemSpacing.y on the underlying TextWrapped is not perfectly
        -- captured), so without a buffer the child can overflow by a
        -- pixel or two and trigger ImGui's auto-scrollbar.
        return hh + RA.SC(4) + items_h + _pad_y * 2 + RA.SC(8)
      end

      local function _fb_priv_panel(id, header, items, h)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(),
          UI.lerp_u32(TK.card, TK.bg, 0.35))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(), TK.border)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(5))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),
          RA.SC(10), _pad_y)
        if ImGui.ImGui_BeginChild(RA.ctx, id, _panel_w, h,
            ImGui.ImGui_ChildFlags_Borders(),
            ImGui.ImGui_WindowFlags_NoScrollbar()) then
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
          Text(RA.ctx, header)
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)
          Dummy(RA.ctx, 1, RA.SC(4))
          PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
          ImGui.ImGui_PushTextWrapPos(RA.ctx,
            GetCursorPosX(RA.ctx) + _item_wrap)
          for _, item in ipairs(items) do
            Text(RA.ctx, "\xe2\x80\xa2 " .. item)   -- "• " (UTF-8 bullet)
          end
          ImGui.ImGui_PopTextWrapPos(RA.ctx)
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)
          ImGui.ImGui_EndChild(RA.ctx)
        end
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)
        PopStyleColor(RA.ctx, 2)
      end

      -- Row 1: What's included | Privacy
      local _r1_a_header, _r1_a_items = "What's included", {
        "Chat shown above",
        "Your comment and tags",
        "App, REAPER, OS, provider/model",
        "Diagnostic summary",
      }
      local _r1_b_header, _r1_b_items = "Privacy", {
        "API keys and bearer tokens redacted",
        "Home/install paths redacted",
        "Audio files and .RPP projects not sent",
        "No account/contact info",
      }
      local _r1_h = math.max(
        _panel_h(_r1_a_header, _r1_a_items),
        _panel_h(_r1_b_header, _r1_b_items))
      _fb_priv_panel("##fb_priv_included", _r1_a_header, _r1_a_items, _r1_h)
      ImGui.ImGui_SameLine(RA.ctx, 0, _grid_gap)
      _fb_priv_panel("##fb_priv_privacy",  _r1_b_header, _r1_b_items, _r1_h)

      -- Row 2: Where it goes | Note
      local _r2_a_header, _r2_a_items = "Where it goes", {
        "Sent to ReaAssist maintainer",
        "Used only to improve ReaAssist",
        "No third parties",
      }
      local _r2_b_header, _r2_b_items = "Note", {
        "Chat may include project, track, plugin, or names you typed.",
      }
      local _r2_h = math.max(
        _panel_h(_r2_a_header, _r2_a_items),
        _panel_h(_r2_b_header, _r2_b_items))
      _fb_priv_panel("##fb_priv_where", _r2_a_header, _r2_a_items, _r2_h)
      ImGui.ImGui_SameLine(RA.ctx, 0, _grid_gap)
      _fb_priv_panel("##fb_priv_note",  _r2_b_header, _r2_b_items, _r2_h)

      ImGui.ImGui_PopStyleVar(RA.ctx)   -- ItemSpacing
    end

    -- Status / error line (no success branch -- on ok the modal closes
    -- immediately and a toast fires on the main screen instead).
    if sending then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, "Sending...")
      PopStyleColor(RA.ctx)
    elseif S.feedback_modal_state == "error" then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
      UI.text_multiline("Send failed: " ..
        (S.feedback_modal_error or "unknown error"))
      PopStyleColor(RA.ctx)
    end

    -- Buttons (centered horizontally within the modal content width).
    -- 5 px margin above (was 20 px) -- tightened so the button row stays
    -- inside the modal viewport without a scrollbar at default height.
    Dummy(RA.ctx, 1, RA.SC(5))
    local btn_w   = RA.SC(100)
    local btn_gap = RA.SC(8)
    local btns_total_w = btn_w * 2 + btn_gap
    local _btn_cur_x = ImGui.ImGui_GetCursorPosX(RA.ctx)
    ImGui.ImGui_SetCursorPosX(RA.ctx,
      _btn_cur_x + math_max(0, math_floor((cw - btns_total_w) * 0.5)))

    -- Cancel: disabled while sending. The POST cannot be cancelled, so
    -- allowing Cancel mid-flight would just orphan the in-flight callback
    -- (which would later mutate cleared state). Same applies to Escape.
    _fb_begin_disabled(sending)
    local cancel_clicked = ImGui.ImGui_Button(RA.ctx, "Cancel", btn_w, 0)
    _fb_end_disabled()

    ImGui.ImGui_SameLine(RA.ctx, 0, btn_gap)

    UI.push_modal_primary_btn()
    _fb_begin_disabled(locked)
    local primary_label = (S.feedback_modal_state == "error") and "Try Again" or "Send"
    local send_clicked = ImGui.ImGui_Button(RA.ctx, primary_label, btn_w, 0)
    _fb_end_disabled()
    UI.pop_modal_primary_btn()

    -- Cancel + Escape (only when not sending)
    if not sending and (cancel_clicked or
       ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape())) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      _close_feedback_modal()
    end

    -- Enter-to-submit: fires from anywhere in the modal as long as Shift
    -- is not held. Shift+Enter inside the comment box still inserts a
    -- newline (standard chat-app convention; matches the main chat
    -- prompt's Enter handling at line ~14875). When Enter fires from
    -- inside the comment box, we restore the pre-edit buffer (stripped
    -- of any trailing \n) so the newline ImGui already inserted on this
    -- frame doesn't leak into user_comment. Both Enter and Keypad-Enter
    -- count.
    local _fb_shift_held = (ImGui.ImGui_GetKeyMods(RA.ctx)
      & ImGui.ImGui_Mod_Shift()) == ImGui.ImGui_Mod_Shift()
    local _fb_enter_pressed =
      ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
    local _fb_enter_to_send = _fb_enter_pressed and not _fb_shift_held
    if _fb_enter_to_send and _fb_comment_active and not locked then
      S.feedback_modal_comment = _fb_prev_comment:gsub("\n$", "")
    end

    -- Send / Try Again. Capture event_id BEFORE send_draft so the callback
    -- can verify the same draft is still active (defends against the
    -- title-bar X close mid-send race).
    if (send_clicked or _fb_enter_to_send) and not locked then
      S.feedback_modal_state = "sending"
      S.feedback_modal_error = nil
      local send_event_id = draft.event_id
      Diag.send_draft(draft,
        S.feedback_modal_comment or "",
        S.feedback_modal_flags,
        function(ok, status, err)
          -- Guard: only mutate UI state if the same draft is still active.
          -- Prevents orphan callbacks (after title-bar X close, or after
          -- the user opened a fresh modal for a different message) from
          -- writing into cleared or re-initialised modal state.
          if not S.feedback_modal_draft
             or S.feedback_modal_draft.event_id ~= send_event_id then
            return
          end
          if ok then
            S.feedback_modal_state = "success"
          else
            S.feedback_modal_state = "error"
            S.feedback_modal_error = err or
              ("status " .. tostring(status))
          end
        end)
    end

    -- Close-on-success: drop the modal as soon as the callback flips
    -- state to "success" and surface a brief toast on the main window
    -- instead. No inline success banner, no 1.5 s linger.
    if success then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      if UI.show_float_toast then
        UI.show_float_toast("Feedback sent. Thanks!", "ok")
      end
      _close_feedback_modal()
    end

    -- Pop the 3 FrameBg colors pushed at the top of this branch.
    PopStyleColor(RA.ctx, 3)

    ImGui.ImGui_EndPopup(RA.ctx)
  else
    -- BeginPopupModal returned false. If we already opened the popup once,
    -- the user closed it via the title-bar X. Tear down state.
    if S._feedback_modal_opened then
      _close_feedback_modal()
    end
  end
  UI.pop_modal_style()
  PopStyleColor(RA.ctx, 4)   -- outer scrollbar palette
end

-- Render._key_validation_error_popup
-- Shared "Key Validation Failed" popup. Shows the provider name, error
-- detail, fix hint, and a clickable console link when the Save-fired
-- test call fails. User stays on the current screen to fix the key.
function Render._key_validation_error_popup()
  if api_keys.show_key_error_popup then
    api_keys.show_key_error_popup = false
    ImGui.ImGui_OpenPopup(RA.ctx, "Key Validation Failed##popup")
  end
  -- Base height fits the typical 3-line detail + 2-line "How to fix"
  -- + OK button. Add SC(24) when a console-link row is also rendered.
  -- Was SC(200) before; the OK button clipped at the bottom on the
  -- typical ChatGPT failure-text length.
  local kerr_w, kerr_h = RA.SC(400), RA.SC(240)
  if api_keys.key_error_url then kerr_h = kerr_h + RA.SC(24) end
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - kerr_w) * 0.5,
      update._main_y + (update._main_h - kerr_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, kerr_w, kerr_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "Key Validation Failed##popup", true,
      ImGui.ImGui_WindowFlags_NoResize()) then
    local cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
    local prov_txt = (api_keys.key_error_provider or "API Key") .. ": Validation Failed"
    local ptw = CalcTextSize(RA.ctx, prov_txt)
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((cw - ptw) * 0.5))
    Text(RA.ctx, prov_txt)
    PopStyleColor(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    if api_keys.key_error_detail then
      -- key_error_detail can contain "\n\nServer said: ..." from custom-LLM
      -- validation; route through text_multiline to avoid TextWrapped's
      -- window-state corruption on embedded newlines.
      UI.text_multiline(api_keys.key_error_detail)
      ImGui.ImGui_Spacing(RA.ctx)
    end
    if api_keys.key_error_hint then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      UI.text_multiline("How to fix: " .. api_keys.key_error_hint)
      PopStyleColor(RA.ctx)
    end
    if api_keys.key_error_url then
      ImGui.ImGui_Spacing(RA.ctx)
      local link_label = api_keys.key_error_url_label or api_keys.key_error_url
      local link_w     = CalcTextSize(RA.ctx, link_label)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx) + math_floor((cw - link_w) * 0.5))
      local link_sx, link_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), 0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          COL.LINK)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), 0, 0)
      if ImGui.ImGui_Button(RA.ctx, link_label .. "##kerr_link", link_w, 0) then
        UI.open_url(api_keys.key_error_url)
      end
      ImGui.ImGui_PopStyleVar(RA.ctx, 2)
      PopStyleColor(RA.ctx, 4)
      if ImGui.ImGui_IsItemHovered(RA.ctx) then
        ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
        local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        local ul_y = link_sy + ImGui.ImGui_GetTextLineHeight(RA.ctx) - 1
        ImGui.ImGui_DrawList_AddLine(dl, link_sx, ul_y, link_sx + link_w, ul_y, COL.LINK, 1)
      end
    end
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    local ok_btn_w = RA.SC(88)
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((cw - ok_btn_w) * 0.5))
    UI.push_modal_primary_btn()
    local dismiss = ImGui.ImGui_Button(RA.ctx, "OK", ok_btn_w, 0)
    UI.pop_modal_primary_btn()
    if dismiss
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_modal_style()
end

-- =============================================================================
-- Render._ceiling_alert_popup
-- =============================================================================
-- Modal that surfaces when ReaAssist's safety output ceiling tripped on one
-- or more JSFX. State comes from the host poll loop in ReaAssist.lua
-- (Loop.handle_ceiling_poll); the diagnose action goes through
-- Code.ceiling_diagnose_one.
--
-- No "Reset Mute" button: the JSFX-side mute auto-clears on transport
-- stopped->playing transitions, so a manual reset would be redundant.
-- The popup is purely informational + diagnostic: tell the user what
-- happened, where, and offer to send the JSFX to the model for analysis.
--
-- Open trigger: S._ceiling_alert_pending = true (set by the poll on a
-- new mute-flag transition). Stays open until the user clicks Dismiss
-- or the muted list goes empty (e.g. user hit Play and the JSFX-side
-- auto-clear wiped state).
function Render._ceiling_alert_popup()
  if S._ceiling_alert_pending and not S._ceiling_alert_open then
    S._ceiling_alert_pending = false
    S._ceiling_alert_open    = true
    ImGui.ImGui_OpenPopup(RA.ctx, "Output Ceiling Engaged##ceiling_alert")
  end

  if not S._ceiling_alert_open then return end

  -- Ordered list (sort by slot for stable render). Stays open until the
  -- user explicitly dismisses, so they see a record of what tripped this
  -- session even after JSFX-side auto-clear releases the mute.
  local muted = S._ceiling_muted_fx or {}
  local entries = {}
  for _, e in pairs(muted) do entries[#entries + 1] = e end
  table.sort(entries, function(a, b) return a.slot < b.slot end)

  -- ---------- Layout constants (V5 -- matches Settings provider cards) ----------
  -- Each entry is rendered as a card mirroring the API-key cards in
  -- Render._shared_key_screen_impl: TK.card bg, TK.border 1px, SC(6)
  -- corner radius, SC(12 x 10) inner padding. The card auto-sizes to
  -- its contents (ChildFlags_AutoResizeY).
  local CARD_GAP = RA.SC(6)        -- vertical gap between cards

  -- Both the popup AND the inner list region have FIXED dimensions, so
  -- the Dismiss row never shifts and the list area is the only thing
  -- that can scroll. LIST_H was tuned to fit three single-location
  -- cards comfortably (each card is ~SC(70) tall once WindowPadding,
  -- ItemSpacing, and the FramePadding'd Diagnose button are factored
  -- in) -- see the math in the inline comment below. Anything above
  -- three cards triggers the inner scrollbar; one or two cards stack
  -- at the top of the region with empty space underneath, which is
  -- the price for the "Dismiss never moves" UX the user asked for.
  --
  -- Card height empirics:
  --   border (2) + WindowPadding y top (10) + title row (~22 button)
  --   + ItemSpacing.y (4) + Dummy(2) + ItemSpacing.y (4)
  --   + 1 location row (~15) + WindowPadding y bottom (10) = ~69
  -- Three cards: 3 * 69 + 2 * (CARD_GAP + ItemSpacing.y * 2) = ~235.
  -- LIST_H rounded up so multi-location cards still fit three at a
  -- time more often than not (a 2-location card adds ~SC(18)).
  local LIST_H  = RA.SC(245)
  local pop_w   = RA.SC(500)
  local pop_h   = RA.SC(490)
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - pop_w) * 0.5,
      update._main_y + (update._main_h - pop_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, pop_w, pop_h, ImGui.ImGui_Cond_Appearing())

  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx,
        "Output Ceiling Engaged##ceiling_alert", true,
        ImGui.ImGui_WindowFlags_NoScrollbar()
          | ImGui.ImGui_WindowFlags_NoScrollWithMouse()) then

    local body_avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    local body_start_x = GetCursorPosX(RA.ctx)

    -- ===== Headline (Inter Bold SC(15), red) =====
    PushFont(RA.ctx, FONT.inter_bold, RA.SC(15))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.red)
    Text(RA.ctx, "Safety ceiling tripped")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(4))

    -- ===== Body explanation (Inter Reg SC(12), muted, wrapped) =====
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    ImGui.ImGui_PushTextWrapPos(RA.ctx,
      body_start_x + body_avail_w - RA.SC(4))
    Text(RA.ctx,
      "These effects exceeded the safety ceiling for >50 ms and self-muted "
      .. "to prevent runaway feedback. Mute clears on transport restart; if "
      .. "it re-trips, click Diagnose to attach the JSFX file and ask the "
      .. "model to analyze it.")
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(12))

    -- ===== Section label "MUTED EFFECTS" with count on the right =====
    -- Mirrors Settings-screen v5 section labels (API KEYS, PREFERENCES).
    local count_label = (#entries == 1) and "1 effect"
                                          or (#entries .. " effects")
    UI.v5_section_label("MUTED EFFECTS", nil, count_label)

    -- ===== Cards list (fixed-size, scrollable when content overflows) =====
    -- Fixed LIST_H -- popup chrome + this child + footer = pop_h, all
    -- precomputed, so the Dismiss row sits at the same Y on every
    -- frame regardless of how many cards are present. The inner
    -- BeginChild auto-shows its scrollbar when the stacked cards
    -- exceed LIST_H (in practice, when there are 4 or more entries
    -- with single-location cards). Padding 0 + transparent bg keeps
    -- the cards reading as the only surface in this region. Muted
    -- scrollbar matches the V5 settings palette.
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), 0, 0)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(),            0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),        0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),      TK.border_str)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
      UI.lerp_u32(TK.border_str, TK.text, 0.30))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
      UI.lerp_u32(TK.border_str, TK.text, 0.55))
    if ImGui.ImGui_BeginChild(RA.ctx, "##ceiling_entries",
          body_avail_w, LIST_H, 0) then
      local card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

      for idx, e in ipairs(entries) do
        if idx > 1 then Dummy(RA.ctx, 1, CARD_GAP) end

        -- Card: TK.card bg, 1px TK.border, SC(6) rounding, SC(12 x 10)
        -- inner padding -- identical to the settings provider cards.
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),  RA.SC(6))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),
          RA.SC(12), RA.SC(10))
        if ImGui.ImGui_BeginChild(RA.ctx, "##ceil_card_" .. e.slot,
              card_w, 0,
              ImGui.ImGui_ChildFlags_AutoResizeY()
                | ImGui.ImGui_ChildFlags_Borders()) then

          -- Capture row metrics BEFORE any items so the right-aligned
          -- Diagnose button anchors to the card's inner-right edge
          -- regardless of label length. (Same pattern as the console
          -- URL link in the API-key cards.)
          local row_start_x = GetCursorPosX(RA.ctx)
          local row_avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

          -- Pre-measure the Diagnose button so its right-anchor X is
          -- known before we draw the title.
          local btn_label = "Diagnose with Model"
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
          local btn_text_w = CalcTextSize(RA.ctx, btn_label)
          PopFont(RA.ctx)
          local btn_w = btn_text_w + RA.SC(20)

          -- Status dot: red, halo'd. Drawn via InvisibleButton so it
          -- reserves layout space and emits hover events for the
          -- tooltip. Mirrors the green/grey provider-card dot.
          do
            local dot_r   = RA.SC(4)
            local dot_dia = dot_r * 2
            local font_h  = ImGui.ImGui_GetTextLineHeight(RA.ctx)
            ImGui.ImGui_InvisibleButton(RA.ctx,
              "##ceil_dot_" .. e.slot, dot_dia + 2, font_h)
            local bx1, by1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
            local dl       = ImGui.ImGui_GetWindowDrawList(RA.ctx)
            local dot_cy   = by1 + font_h * 0.5 - RA.SC(1)
            local halo_col = (TK.red & 0xFFFFFF00) | 0x40
            ImGui.ImGui_DrawList_AddCircleFilled(dl,
              bx1 + dot_r + 1, dot_cy, dot_r * 2, halo_col, 20)
            ImGui.ImGui_DrawList_AddCircleFilled(dl,
              bx1 + dot_r + 1, dot_cy, dot_r, TK.red, 16)
            UI.tooltip("Muted: output ceiling tripped")
            SameLine(RA.ctx, 0, RA.SC(6))
          end

          -- Effect name -- card title (Inter SemiBold SC(12), TK.text)
          local label = (e.desc and e.desc ~= "") and e.desc
            or (e.file and e.file:match("[^/\\]+$") or "(unknown)")
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
          Text(RA.ctx, label)
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)

          -- Diagnose button, right-aligned to the card's inner-right
          -- edge. Compact FramePadding + Inter SemiBold SC(11) so the
          -- button height matches the title row visually.
          SameLine(RA.ctx)
          SetCursorPosX(RA.ctx, row_start_x + row_avail_w - btn_w)
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),
            RA.SC(10), RA.SC(4))
          UI.push_modal_primary_btn()
          if ImGui.ImGui_Button(RA.ctx,
                btn_label .. "##ceiling_diag_" .. e.slot,
                btn_w, 0) then
            Code.ceiling_diagnose_one(e.slot)
          end
          UI.pop_modal_primary_btn()
          ImGui.ImGui_PopStyleVar(RA.ctx, 1)
          PopFont(RA.ctx)

          -- Per-location rows: Inter Reg SC(11), TK.text_muted,
          -- indented under the title. Quiet enough to not compete
          -- with the title, but readable.
          Dummy(RA.ctx, 1, RA.SC(2))
          local locs = e.locations or {}
          PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
          if #locs == 0 then
            local fname = e.file and e.file:match("[^/\\]+$") or "?"
            Text(RA.ctx, "  " .. fname)
          else
            for _, loc in ipairs(locs) do
              local idx_str = (loc.track_idx == "M") and "Master"
                or ("Track " .. tostring(loc.track_idx))
              local tname = loc.track_name and loc.track_name ~= ""
                              and (' "' .. loc.track_name .. '"') or ""
              Text(RA.ctx, ("  %s%s   \xc2\xb7   FX %d"):format(
                idx_str, tname, loc.fx_idx or 0))
            end
          end
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)

          ImGui.ImGui_EndChild(RA.ctx)
        end
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)
        PopStyleColor(RA.ctx, 2)
      end
      ImGui.ImGui_EndChild(RA.ctx)
    end
    PopStyleColor(RA.ctx, 5)            -- ChildBg + 4 Scrollbar*
    ImGui.ImGui_PopStyleVar(RA.ctx, 1)  -- WindowPadding for the scroll child

    -- Tight gap above the footer -- the dynamic list_h above already
    -- consumed the slack, so this is just the visual breathing room
    -- between the bottom card and the Dismiss row.
    Dummy(RA.ctx, 1, RA.SC(6))

    -- ===== Footer: checkbox left, Dismiss button right =====
    do
      local footer_avail = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      local b_w = RA.SC(110)
      local cb_x = GetCursorPosX(RA.ctx)
      local cb_y = ImGui.ImGui_GetCursorPosY(RA.ctx)

      -- Checkbox -- frame palette tuned to the modal surface.
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),        TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_CheckMark(),      TK.accent)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      local cur = S._ceiling_alert_dismissed and true or false
      local changed, val = ImGui.ImGui_Checkbox(RA.ctx,
        "Don't show again this session", cur)
      PopFont(RA.ctx)
      PopStyleColor(RA.ctx, 4)
      if changed then S._ceiling_alert_dismissed = val end

      -- Dismiss button on the same row, right-aligned.
      SameLine(RA.ctx)
      SetCursorPosX(RA.ctx, cb_x + footer_avail - b_w)
      ImGui.ImGui_SetCursorPosY(RA.ctx, cb_y)
      UI.push_modal_primary_btn()
      local dismiss = ImGui.ImGui_Button(RA.ctx,
        "Dismiss##ceiling_alert", b_w, 0)
      UI.pop_modal_primary_btn()

      if dismiss
         or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        S._ceiling_alert_open = false
        S._ceiling_muted_fx   = {}
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
    end

    ImGui.ImGui_EndPopup(RA.ctx)
  else
    -- Popup closed externally (X button, click outside, etc.).
    -- Treat the same as Dismiss -- clear so a new trip can re-open.
    S._ceiling_alert_open = false
    S._ceiling_muted_fx   = {}
  end
  UI.pop_modal_style()
end

-- Render.first_run_screen / Render.settings_screen
-- Two public entry points for the API-keys screen. first_run_screen is
-- what the user sees after accepting TOS (no prior config); settings_screen
-- is what they see when they open Settings from the main chat. They share
-- the bulk of their rendering via Render._shared_key_screen_impl -- only
-- the screen-specific chrome differs (logo + Save & Continue + Help on
-- first-run; X + title + Preferences + Save + Cancel on Settings). That
-- shared impl is driven by the `is_first_run` flag so feature divergence
-- can live in either the wrapper (for per-screen chrome) or the impl (for
-- shared behaviour) as appropriate.
function Render.first_run_screen()
  api_keys.is_reentry = false
  Render._shared_key_screen_impl()
end

function Render.settings_screen()
  api_keys.is_reentry = true
  Render._shared_key_screen_impl()
end

-- Shared cleanup invoked from every "leave Settings" branch in
-- Render._shared_key_screen_impl: the unsaved-changes popup's Save and
-- Discard buttons, and the no-popup cancel branch when there were no
-- unsaved changes. Previously each branch carried a verbatim copy of
-- this 14-line block, with predictable drift risk -- the synthesis
-- review caught two minor inconsistencies between them.
local function _exit_settings_screen()
  -- Clear staged Preference snapshots so a re-entry into Settings starts
  -- fresh.
  api_keys.saved_ui_scale_idx          = nil
  api_keys.saved_theme                 = nil
  api_keys.saved_update_check          = nil
  api_keys.saved_auto_backup           = nil
  api_keys.saved_chat_font_idx         = nil
  api_keys.saved_include_snapshot      = nil
  api_keys.saved_include_api_ref       = nil
  api_keys.saved_cloud_request_timeout = nil
  api_keys.section_open = nil
  -- Restore previous-screen context (if the footer gear opened Settings
  -- from Help / Bug Report / Credits, this drops the user back where
  -- they were).
  local ret = S._settings_return_to
  S._settings_return_to = nil
  api_keys.screen       = ret and ret.screen or nil
  S.show_help           = ret and ret.show_help     or false
  S.show_bug_report     = ret and ret.show_bug      or false
  S.show_credits        = ret and ret.show_credits  or false
  api_keys.is_reentry   = false
  api_keys.key_bufs     = {}
  api_keys.key_errors   = {}
  api_keys.key_error    = nil
  api_keys.key_focused  = false
  api_keys.custom_edit  = nil
  local _act = PROVIDERS.active()
  S.api_key = _act and S.api_key_map[_act.id] or nil
end

-- Used for both first-run onboarding and re-entry via the Settings button.
-- Each provider shows its current key status, an input field for new/replacement
-- keys, and a Remove button for existing keys. Format validation is done locally;
-- a test API call validates the first newly entered key before accepting it.
function Render._shared_key_screen_impl()
  local is_reentry = api_keys.is_reentry

  -- Initialize per-provider buffers on first render. Custom providers are
  -- handled by the dedicated custom section below; their slot stays empty
  -- (sparse table). Detect needs-init by scanning for any expected non-
  -- custom slot that is still nil, rather than testing `#key_bufs == 0`:
  -- sparse holes make `#` undefined-behavior (it can return any boundary),
  -- and if PROVIDERS is ever reordered with a custom in the middle the
  -- mid-render `#` could land on a small number, the init re-runs, and
  -- the user's typed buffer is wiped. Several reset sites elsewhere set
  -- `key_bufs = {}` -- the next-render scan re-detects all-nil and
  -- re-initialises without those sites needing to know about the change.
  local needs_init = false
  for i, prov in ipairs(PROVIDERS) do
    if not prov.is_custom and not prov.hidden
       and api_keys.key_bufs[i] == nil then
      needs_init = true; break
    end
  end
  if needs_init then
    for i, prov in ipairs(PROVIDERS) do
      if not prov.is_custom and not prov.hidden then
        api_keys.key_bufs[i]   = api_keys.key_bufs[i]   or ""
        api_keys.key_errors[i] = api_keys.key_errors[i] or nil
      end
    end
  end

  -- Tab / Shift+Tab navigation between provider key inputs. Each card is
  -- its own BeginChild, so ImGui's built-in Tab focus scopes to the card
  -- and cycles between the console link + input inside. We override:
  -- captured here, applied just before the target widget is drawn.
  -- Values: a provider index i (focus that card's input) or "save"
  -- (focus the pinned Save / Save & Continue button).
  local pending_focus = api_keys._pending_focus
  api_keys._pending_focus = nil

  -- Lazy-init section_open in case we arrived here via the first-run
  -- path (which doesn't run the Settings-open entry-point blocks that
  -- normally set this up). First-run only uses api = true; the other
  -- two sections don't render for first-run anyway.
  if not api_keys.section_open then
    api_keys.section_open = {
      api  = true,
      pref = is_reentry,
      adv  = false,
    }
  end

  -- Centered column via Indent (no child window) so the main window scrollbar
  -- handles overflow -- same pattern as Render.help_screen.
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  -- V5: symmetric SC(22) horizontal inset from the window edge on both
  -- sides, matching the JSX reference's "padding: 14px 22px 8px" body
  -- rule. api_indent adds just enough to the ambient WindowPadding.x to
  -- reach the SC(22) target, so the cards read as a single column inset
  -- equally from left and right.
  local BODY_PAD_X = RA.SC(22)
  local inner_w    = win_w - BODY_PAD_X * 2
  local api_indent = BODY_PAD_X - pad_x
  if api_indent < 0 then api_indent = 0 end

  -- Shared settings-screen style stack (FramePadding, rounding, button
  -- palette, border). Pushed here so the X close button below inherits the
  -- same rounding and padding as the rest of the screen. Paired pop lives
  -- at the very bottom of this function.
  UI.push_settings_styles()

  -- V5 hero band: compact wordmark + "SETTINGS \xc2\xb7 vX.Y.Z" mono
  -- breadcrumb on the right + subtitle below. Exit is handled by the
  -- Cancel button in the pinned footer bar below.
  local hero_subtitle = is_reentry
    and "Configure API keys & preferences."
    or  "Add at least one API key to get started."
  -- Distinct breadcrumb on first-run so the page's context reads at a
  -- glance (same SETTINGS surface, but this is the initial setup pass).
  local hero_breadcrumb = (is_reentry and "SETTINGS" or "FIRST-RUN SETTINGS")
    .. " \xc2\xb7 v" .. CFG.VERSION
  UI.hero_band_settings_v5(hero_subtitle, hero_breadcrumb)

  -- Small gap between the hero and the API KEYS section below.
  Dummy(RA.ctx, 1, RA.SC(6))

  -- Scrollable body container. Spans the full main-window content
  -- region (pad_x to win_w - pad_x) so the scrollbar hugs the window's
  -- right edge instead of sitting inset inside the body. The content
  -- column (inner_w wide) is positioned via an Indent INSIDE the
  -- child -- not outside -- so the child itself extends past the
  -- column to host the scrollbar.
  --
  -- Zero WindowPadding + zero ChildBorderSize so cursor math inside
  -- stays aligned with the main window's coordinate system.
  --
  -- Muted scrollbar colors to match the V5 palette in both themes
  -- (default ImGui scrollbar reads too dark in light mode and too
  -- flat in dark mode).
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local BODY_PINNED_RESERVE = RA.SC(52) + RA.SC(32)   -- BAR_H + FOOTER_RAIL_H
  local _body_h = math_max(_body_avail_h - BODY_PINNED_RESERVE, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##settings_body", _body_avail_w, _body_h, 0)
  -- Indent *inside* the child so the content column sits BODY_PAD_X
  -- from the window's left edge; the child's remaining right-side
  -- slack is where the scrollbar renders.
  ImGui.ImGui_Indent(RA.ctx, api_indent)

  -- Disable all inputs while a validation request is in flight.
  ImGui.ImGui_BeginDisabled(RA.ctx, api_keys.key_validating)

  -- First-run intro block: one consolidated paragraph above the API
  -- KEYS section label. Leads with the trust reassurance (most
  -- important at the moment the user is about to paste a secret),
  -- then a soft nudge toward Claude (best all-around results) or
  -- Gemini (only provider with a free tier), closing with the local
  -- / custom option for offline privacy.
  if not is_reentry then
    local fr_intro_wrap = GetCursorPosX(RA.ctx) + inner_w - RA.SC(8)
    ImGui.ImGui_PushTextWrapPos(RA.ctx, fr_intro_wrap)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    Text(RA.ctx,
      "Keys are obfuscated and stored locally on this machine and sent "
      .. "only to your chosen provider. Claude has shown the best all "
      .. "around results in testing. Gemini is the only provider to "
      .. "offer a free tier. You may also use a local or custom LLM to "
      .. "keep your data fully offline and private.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(10))
  end

  -- API KEYS section -- collapsible on re-entry (user can hide the
  -- card column to focus on Preferences). First-run keeps it always
  -- open since the user's whole job here is to enter a key.
  if is_reentry then
    api_keys.section_open.api = UI.v5_section_label("API KEYS",
      api_keys.section_open.api)
  else
    UI.v5_section_label("API KEYS")
  end

  if (is_reentry and api_keys.section_open.api) or not is_reentry then

  -- Render one section per provider.
  -- Push CHAT_TEXT for text + cursor so both are visible in all themes.
  -- Use a distinct FrameBgActive tint so focused fields are visually obvious.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),             COL.CHAT_TEXT)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(),  COL.CHAT_TEXT)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),          COL.FRAME_BG)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),   COL.FRAME_BG)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),    COL.CODE_BG)

  -- Card styling shared by every provider block: slightly-darker background
  -- + 1px border + rounded corners, so the three blocks read as distinct
  -- grouped cards rather than a running list of fields.
  --
  -- Inter-card spacing is a PRE-card Dummy (fires on every card except
  -- the first) so after the loop, cursor sits tight against the last
  -- card's bottom edge -- the caller controls post-loop spacing
  -- precisely without double-counting a trailing inter-card gap.
  local any_card_drawn = false
  for i, prov in ipairs(PROVIDERS) do
    -- Custom providers are managed on the dedicated "Local & Custom
    -- Providers" page (entered via the nav row further down). Skip them
    -- here to avoid rendering the cloud-provider single-input layout
    -- against a row that has its own multi-row schema. Hidden experimental
    -- providers (gated by an ExtState unlock at startup) are also skipped:
    -- they are not surfaced anywhere in the UI until unlocked.
    if not prov.is_custom and not prov.hidden then
      if any_card_drawn then
        Dummy(RA.ctx, 1, RA.SC(5))
      end
      any_card_drawn = true

      local cur_key = S.api_key_map[prov.id]

      -- Match the V5 option-row palette (toggles / select rows / nav
      -- row below) so the API cards read as the same surface tone.
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),  RA.SC(6))
      -- V5: SC(12) x SC(8) inner padding (bumped +2 each axis for more air).
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),  RA.SC(12), RA.SC(8))
      local card_tl_x, card_tl_y = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
      -- V5 cards are flat: no drop shadow, no hover accent border. The
      -- 1px TK.border + the card's slightly-lifted TK.card background
      -- carry the separation on their own.
      if ImGui.ImGui_BeginChild(RA.ctx, "##prov_card_" .. i, inner_w, 0,
          ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then

      -- V5: nudge the first (name) row 1px lower so the label sits
      -- optically centered against the dot + CONNECTED pill on its row.
      Dummy(RA.ctx, 1, RA.SC(1))

      -- Capture the card row's starting X + available width BEFORE any items
      -- are placed, so the console link can be right-aligned to the card's
      -- inner edge regardless of label length or UI scale.
      local row_start_x = GetCursorPosX(RA.ctx)
      local row_avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

      -- Status dot: green when a key is stored, muted gray when empty.
      -- Rendered via an InvisibleButton so its rect is a proper ImGui item
      -- (reserves layout space and emits hover events for the tooltip).
      do
        local dot_r   = RA.SC(4)
        local dot_dia = dot_r * 2
        local font_h  = ImGui.ImGui_GetTextLineHeight(RA.ctx)
        ImGui.ImGui_InvisibleButton(RA.ctx, "##dot_" .. i, dot_dia + 2, font_h)
        local bx1, by1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
        local dl        = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        -- Soft halo behind the active dot so it reads as "alive" rather
        -- than just colored. Drawn first so the solid dot sits on top.
        -- The -SC(1) nudge on y lifts the dot one pixel so it sits
        -- optically centered on the provider name's cap line (the
        -- label baseline naturally reads slightly low otherwise).
        local dot_cy = by1 + font_h * 0.5 - RA.SC(1)
        if cur_key then
          local halo_col = (COL.SUCCESS & 0xFFFFFF00) | 0x40
          ImGui.ImGui_DrawList_AddCircleFilled(dl,
            bx1 + dot_r + 1, dot_cy, dot_r * 2, halo_col, 20)
        end
        local dot_color = cur_key and COL.SUCCESS or COL.DETAIL
        ImGui.ImGui_DrawList_AddCircleFilled(dl,
          bx1 + dot_r + 1, dot_cy, dot_r, dot_color, 16)
        UI.tooltip(cur_key and "Active" or "Inactive")
        SameLine(RA.ctx, 0, RA.SC(6))
      end

      -- Provider label (left side of the row). V5: Inter Regular SC(12),
      -- TK.text. Just the bare provider name; the section header above
      -- the cards ("API KEYS"), the green dot, the CONNECTED pill, the
      -- masked "Current: sk-..." preview, and the per-card tooltip
      -- already carry the "this is an API key" context, so the title
      -- doesn't need the extra weight that the section header carries.
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
      Text(RA.ctx, prov.label)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)

      -- Status pill: mono 9, inline right after the label. Shows
      -- CONNECTED (green) when a key is stored and idle, TESTING
      -- (amber) when this card's key is currently being validated.
      -- Hidden when no key is stored.
      local is_testing = api_keys.key_validating
        and api_keys.key_validating_idx == i
      if cur_key then
        SameLine(RA.ctx, 0, RA.SC(8))
        local PILL_SZ    = RA.SC(9)
        local PILL_PAD_X = RA.SC(6)
        local PILL_PAD_Y = RA.SC(3)
        local PILL_ROUND = RA.SC(3)
        local pill_label  = is_testing and "TESTING"    or "CONNECTED"
        local pill_fg     = is_testing and TK.amber   or TK.green
        local pill_bg_src = is_testing and TK.amber   or TK.green
        -- Pill metrics are invariant per UI scale (PILL_SZ + label font
        -- size both derive from RA.SC). Cache the two CalcTextSize +
        -- four PushFont/PopFont per provider card per frame: with three
        -- cloud-key cards visible at any time on the API Keys screen,
        -- this was 12 push/pop and 6 measurements per frame for two
        -- possible label strings.
        UI._pill_metrics = UI._pill_metrics or {}
        local _pm_key = PILL_SZ .. ":" .. RA.SC(12)
        local _pm = UI._pill_metrics[_pm_key]
        if not _pm then
          _pm = {}
          PushFont(RA.ctx, FONT.mono_reg, PILL_SZ)
          _pm.connected_w = CalcTextSize(RA.ctx, "CONNECTED")
          _pm.testing_w   = CalcTextSize(RA.ctx, "TESTING")
          PopFont(RA.ctx)
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
          _, _pm.label_lh = CalcTextSize(RA.ctx, "M")
          PopFont(RA.ctx)
          UI._pill_metrics[_pm_key] = _pm
        end
        local pw = is_testing and _pm.testing_w or _pm.connected_w
        local label_lh = _pm.label_lh
        local pill_w  = pw + PILL_PAD_X * 2
        local pill_h  = PILL_SZ + PILL_PAD_Y * 2
        local psx, psy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        local pill_sy = psy + math_floor((label_lh - pill_h) * 0.5)
        -- Reserve layout space so the URL link's right-align math stays
        -- consistent whether or not the pill is visible.
        Dummy(RA.ctx, pill_w, label_lh)
        local dl_pill = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        -- ~16% alpha bg tint, color matched to the text.
        local pill_bg = (pill_bg_src & 0xFFFFFF00) | 0x28
        ImGui.ImGui_DrawList_AddRectFilled(dl_pill,
          psx, pill_sy, psx + pill_w, pill_sy + pill_h,
          pill_bg, PILL_ROUND)
        -- Text nudged up 1px: mono_reg's baseline sits visually low
        -- in the pill's cap band; the nudge re-centers optically.
        ImGui.ImGui_DrawList_AddTextEx(dl_pill, FONT.mono_reg, PILL_SZ,
          psx + PILL_PAD_X, pill_sy + PILL_PAD_Y - RA.SC(1),
          pill_fg, pill_label)
      end

      -- Console sign-up link (right side of the row). V5: mono SC(10) in
      -- TK.accent with a 1px underline, right-aligned to the card's
      -- inner right edge so long labels can't crowd it. A transparent
      -- SmallButton handles the hit region + keyboard focus + click.
      local LINK_SZ = RA.SC(10)
      -- Cache the console-label width on prov itself, keyed on font size.
      -- prov.console_label is invariant per provider; PROVIDERS rebuilds
      -- via Custom.register_all naturally invalidate by replacing the
      -- table reference.
      if prov._console_lw_key ~= LINK_SZ then
        PushFont(RA.ctx, FONT.mono_reg, LINK_SZ)
        prov._console_lw     = CalcTextSize(RA.ctx, prov.console_label)
        prov._console_lw_key = LINK_SZ
        PopFont(RA.ctx)
      end
      local link_w = prov._console_lw
      SameLine(RA.ctx)
      SetCursorPosX(RA.ctx, row_start_x + row_avail_w - link_w)
      PushFont(RA.ctx, FONT.mono_reg, LINK_SZ)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), 0, 0)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), 0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  0x00000000)
      if ImGui.ImGui_SmallButton(RA.ctx, prov.console_label .. "##frl" .. i) then
        UI.open_url(prov.console_url)
      end
      if ImGui.ImGui_IsItemHovered(RA.ctx) then
        ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      end
      UI.tooltip("Sign up or manage your " .. prov.label
        .. " API keys on the provider's console")
      do
        local bx1, _   = ImGui.ImGui_GetItemRectMin(RA.ctx)
        local bx2, by2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
        local dl       = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        ImGui.ImGui_DrawList_AddLine(dl, bx1, by2 - 1, bx2, by2 - 1, TK.accent, 1.0)
      end
      PopStyleColor(RA.ctx, 4)
      ImGui.ImGui_PopStyleVar(RA.ctx, 2)
      PopFont(RA.ctx)

      -- Current key status + Remove button. V5: "Current: sk-..." in mono
      -- SC(10) TK.text_muted, Remove button right-aligned with a thin
      -- transparent-bg pill style (1px border, small 9.5 label).
      if cur_key then
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        Text(RA.ctx, "Current: " .. Key.mask(cur_key, prov.id))
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Two-step Remove: first click arms the button (label swaps
        -- to "Confirm?", color shifts to destructive red), a second
        -- click within RM_ARM_WINDOW seconds commits the removal.
        -- If no second click lands in that window, the button
        -- reverts to "Remove". Prevents accidental loss of an API
        -- key from a mis-click.
        local RM_ARM_WINDOW = 3.0
        api_keys._rm_arm = api_keys._rm_arm or {}
        local arm_t = api_keys._rm_arm[i]
        local now_t = reaper.time_precise()
        local armed = arm_t and (now_t - arm_t) < RM_ARM_WINDOW
        -- Auto-expire the arm state if it timed out.
        if arm_t and not armed then
          api_keys._rm_arm[i] = nil
        end

        local rm_label = armed and "Confirm?" or "Remove"
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        local rm_tw = CalcTextSize(RA.ctx, rm_label)
        PopFont(RA.ctx)
        local rm_pad_x = RA.SC(7)
        local rm_btn_w = rm_tw + rm_pad_x * 2
        SameLine(RA.ctx)
        SetCursorPosX(RA.ctx, row_start_x + row_avail_w - rm_btn_w)
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), rm_pad_x, RA.SC(1))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(3))
        -- Armed state uses the same muted terracotta as Factory
        -- Reset for visual family; the tinted fill makes the
        -- "armed" state clearly different from the idle state.
        local RM_RED = 0xBF7777FF
        local rm_text_col   = armed and RM_RED or TK.text_muted
        local rm_border_col = armed and RM_RED or TK.border
        local rm_bg_col     = armed
          and ((RM_RED & 0xFFFFFF00) | 0x20)    -- ~12% alpha red fill
          or  0x00000000
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          rm_text_col)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        rm_border_col)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        rm_bg_col)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), rm_bg_col)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  rm_bg_col)
        if ImGui.ImGui_Button(RA.ctx, rm_label .. "##rm" .. i) then
          if armed then
            -- Commit removal.
            api_keys._rm_arm[i] = nil
            S.api_key_map[prov.id] = nil
            Key.clear(prov.key_extstate)
            if prov.id == "google" then
              S.gemini_paid_tier = nil
              reaper.DeleteExtState(CFG.EXT_NS, "gemini_paid_tier", true)
            end
            if prov.id == PROVIDERS.active().id then
              S.api_key = nil
            end
          else
            -- Arm: wait for a confirm click within the window.
            api_keys._rm_arm[i] = now_t
          end
        end
        if ImGui.ImGui_IsItemHovered(RA.ctx) then
          ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
          UI.tooltip(armed
            and "Click again to remove this key. Auto-cancels in 3s."
            or  "Remove this API key. Requires a second click to confirm.")
        end
        PopStyleColor(RA.ctx, 5)  -- Text, Border, Button, ButtonHovered, ButtonActive
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)  -- FramePadding, FrameBorderSize, FrameRounding
        PopFont(RA.ctx)
      end

      -- Password input field -- V5: shown ONLY when no key is stored for
      -- this provider. To change a key the user must click Remove first,
      -- which clears cur_key and re-reveals the input on the next frame.
      -- The placeholder "Paste API key..." lives inside the empty field.
      if not cur_key then
        local card_avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        -- V5 input bg: recessed tone relative to the card so the
        -- field reads as a text well. TK.input_bg is a notch darker
        -- than TK.card (dark) / subtle gray vs white card (light).
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),        TK.input_bg)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(), TK.input_bg)
        ImGui.ImGui_SetNextItemWidth(RA.ctx, card_avail_w)
        if pending_focus == i then
          ImGui.ImGui_SetKeyboardFocusHere(RA.ctx)
        elseif not api_keys.key_focused and i == 1 and not is_reentry then
          ImGui.ImGui_SetKeyboardFocusHere(RA.ctx)
          api_keys.key_focused = true
        end
        -- Mono font for both the hint and typed content (typed text
        -- renders as bullets under the Password flag, but the hint
        -- reads as a mono "Paste API key..." placeholder when empty).
        -- V5: SC(10) (-1 from SC(11)); FramePadding.x bumped +3 so the
        -- hint sits 3px in from the input's left edge for breathing room.
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), RA.SC(8), RA.SC(5))
        local _, new_buf = ImGui.ImGui_InputTextWithHint(RA.ctx,
          "##frkey_" .. i, "Paste API key...",
          api_keys.key_bufs[i],
          ImGui.ImGui_InputTextFlags_Password())
        -- input_active query MUST come before input_with_menu: the popup's
        -- BeginPopup/MenuItem calls become the "last item" if the popup is
        -- open, which would corrupt IsItemActive's reading of the input.
        local input_active = ImGui.ImGui_IsItemActive(RA.ctx)
        _, new_buf = UI.input_with_menu(RA.ctx, false, new_buf)
        ImGui.ImGui_PopStyleVar(RA.ctx)
        PopFont(RA.ctx)
        PopStyleColor(RA.ctx, 2)  -- FrameBg, FrameBgHovered
        UI.focus_ring()
        api_keys.key_bufs[i] = new_buf
        UI.tooltip("Paste your " .. prov.label .. " API key here")

        -- Tab / Shift+Tab: jump to the next/previous provider card whose
        -- key input is still showing (no stored key yet). Forward tab past
        -- the last empty card routes to the pinned Save button so the user
        -- can commit with a keyboard-only flow.
        if input_active
              and ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Tab()) then
          local shift_down =
               ImGui.ImGui_IsKeyDown(RA.ctx, ImGui.ImGui_Key_LeftShift())
            or ImGui.ImGui_IsKeyDown(RA.ctx, ImGui.ImGui_Key_RightShift())
          local target
          if shift_down then
            for j = i - 1, 1, -1 do
              local pj = PROVIDERS[j]
              if pj and not pj.is_custom and not pj.hidden
                 and not S.api_key_map[pj.id] then
                target = j
                break
              end
            end
          else
            for j = i + 1, #PROVIDERS do
              local pj = PROVIDERS[j]
              if pj and not pj.is_custom and not pj.hidden
                 and not S.api_key_map[pj.id] then
                target = j
                break
              end
            end
            if not target then target = "save" end
          end
          if target then
            api_keys._pending_focus = target
          end
        end

        -- Per-field validation error (only meaningful when the input is
        -- visible -- errors against a now-connected key are stale).
        -- Rendered 2 px smaller than the ambient body font so the
        -- single-line error reads as secondary detail rather than
        -- competing with the input field's chrome.
        if api_keys.key_errors[i] then
          local _err_sz = math_max(ImGui.ImGui_GetFontSize(RA.ctx) - 2, 8)
          PushFont(RA.ctx, FONT.inter_reg, _err_sz)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.ERROR)
          Text(RA.ctx, api_keys.key_errors[i])
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)
        end
      end

        ImGui.ImGui_EndChild(RA.ctx)
      end
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)   -- ChildBorderSize, ChildRounding, WindowPadding
      PopStyleColor(RA.ctx, 2) -- ChildBg, Border
      -- Per-card tooltip: explains what the card is and surfaces the
      -- security reassurance (obfuscation + install-path lock) without
      -- taking a dedicated row. IsItemHovered after EndChild reports
      -- hover on the child window itself.
      UI.tooltip(prov.label .. " API key. Stored locally on this "
        .. "machine, obfuscated, and locked to this install path for "
        .. "security.")
      -- (No trailing inter-card Dummy here -- the pre-card Dummy at
      -- the top of the loop handles inter-card spacing, and the
      -- post-loop Dummy below sizes the card -> buttons gap exactly.)
    end
  end

  PopStyleColor(RA.ctx, 5)  -- Text, InputTextCursor, FrameBg x3

  -- Provider actions: Test API Keys + Configure Local / Custom LLM.
  -- SC(7) gives a ~15px visual gap from the last card's bottom to the
  -- button row top (gap = 2 * ItemSpacing + SC(7) = 8 + 7 = 15).
  Dummy(RA.ctx, 1, RA.SC(7))
  do
    -- V5 secondary button style: card bg, 1px border, SC(12) label, 12/8
    -- padding, 6 radius. Tuned to yield SC(30) button height so paired
    -- action buttons (Test API Keys) sit flush with adjacent v5_nav_row
    -- and v5_toggle / v5_select_row widgets on the same page.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(12), RA.SC(8))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)

    local test_label = "Test API Keys"
    -- Rendered via UI.v5_nav_row (centered label + chevron block) so it
    -- signals "opens a different page" with the same glyph + chrome as
    -- the Preferred Plugins nav row, while still pairing on one line
    -- with the Test API Keys action button next to it.
    local cllm_label = "Local & Custom Providers"
    local custom_count = 0
    for _, pk in ipairs(PROVIDERS) do
      if pk.is_custom then custom_count = custom_count + 1 end
    end
    if custom_count > 0 then
      cllm_label = cllm_label .. " (" .. custom_count .. ")"
    end
    local test_btn_w = CalcTextSize(RA.ctx, test_label) + RA.SC(24)
    -- v5_nav_row needs: label_w + gap(SC(8)) + chevron(SC(4)) + 2*pad(SC(24))
    local cllm_btn_w = CalcTextSize(RA.ctx, cllm_label) + RA.SC(36)
    local pair_gap   = RA.SC(8)
    local pair_w     = test_btn_w + pair_gap + cllm_btn_w
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - pair_w) * 0.5), 0))

    -- Test API Keys: verifies all stored keys sequentially, then shows the
    -- results popup. Enabled if any provider has either a stored key OR a
    -- non-empty buffered (just-pasted, not yet saved) key. Disabled only
    -- while a test is already running. Hidden providers cannot reach this
    -- UI to enter a key, so they are excluded from the trigger condition.
    local has_keys = false
    for i, pk in ipairs(PROVIDERS) do
      if not pk.hidden then
        if S.api_key_map[pk.id] then has_keys = true; break end
        local buf = not pk.is_custom and api_keys.key_bufs[i]
        if buf and buf:match("%S") then has_keys = true; break end
      end
    end
    ImGui.ImGui_BeginDisabled(RA.ctx, not has_keys or api_keys.key_validating)
    if ImGui.ImGui_Button(RA.ctx, test_label .. "##key_recheck") then
      -- Promote any buffered (freshly-pasted) keys into S.api_key_map so the
      -- test queue below picks them up. Mirrors what Save does -- the key
      -- is only moved in-memory here; persistence to ExtState happens in
      -- the test-success callback, same as for a Save-then-test flow. Any
      -- buffered key that fails format validation records an inline error
      -- and is NOT promoted.
      for i, prov in ipairs(PROVIDERS) do
        if not prov.is_custom and not prov.hidden then
          local buf = (api_keys.key_bufs[i] or ""):match("^%s*(.-)%s*$") or ""
          if buf ~= "" then
            local valid, reason = Key.validate_format(buf, prov)
            if valid then
              S.api_key_map[prov.id] = buf
            else
              api_keys.key_errors[i] = reason
            end
          end
        end
      end

      -- Build a queue of all providers that have a stored key.
      api_keys.test_queue   = {}
      api_keys.test_results = {}
      -- Two passes (hardcoded providers first, custom providers last)
      -- so the cloud keys test before any local-LLM endpoint reachability
      -- check. Custom-provider tests can be slow (network or local
      -- server roundtrip), and surfacing the cloud results promptly
      -- matters more than queue brevity. The order also matches what
      -- the user usually configures first (cloud keys -> custom).
      for i, pk in ipairs(PROVIDERS) do
        if not pk.is_custom and not pk.hidden and S.api_key_map[pk.id] then
          api_keys.test_queue[#api_keys.test_queue + 1] = { idx = i, prov = pk }
        end
      end
      for i, pk in ipairs(PROVIDERS) do
        if pk.is_custom and S.api_key_map[pk.id] then
          api_keys.test_queue[#api_keys.test_queue + 1] = { idx = i, prov = pk }
        end
      end
      if #api_keys.test_queue > 0 then
        api_keys.key_error = nil
        api_keys.key_validating = true
        local first = api_keys.test_queue[1]
        api_keys.key_validating_idx = first.idx
        -- Snapshot the active provider before flipping for the test.
        -- Net.fire_key_test reads S.api_key + prefs.provider_idx, so each
        -- queued provider must temporarily own those slots; the queue-
        -- exhaust branch in advance_key_test_queue restores from this
        -- snapshot. Without it, "Test API Keys" silently switches the
        -- active provider to whichever was last in the queue.
        api_keys._test_orig_provider_idx = prefs.provider_idx
        S.api_key = S.api_key_map[first.prov.id]
        prefs.provider_idx = first.idx
        MODELS.refresh()
        Net.fire_key_test(first.prov)
      end
    end
    UI.pressable()
    ImGui.ImGui_EndDisabled(RA.ctx)
    UI.tooltip("Verify all API keys (stored or newly pasted) and recheck Gemini account status")

    SameLine(RA.ctx, 0, pair_gap)
    if UI.v5_nav_row("##open_cllm_settings", cllm_label,
        "Manage any number of OpenAI-compatible providers: local "
        .. "servers (Ollama, LM Studio, llama.cpp, vLLM) and online "
        .. "gateways (OpenRouter, Groq, DeepSeek, Together AI, etc.)",
        cllm_btn_w, custom_count > 0) then
      -- Remember which screen opened Custom Providers so its Save / Back
      -- can route correctly: first-run back-out drops the user directly
      -- into chat; Settings back-out returns to the Settings page.
      api_keys._cllm_source = api_keys.is_reentry and "settings" or "first_run"
      api_keys.screen       = "custom_providers"
      api_keys.custom_edit  = nil  -- list view, no edit in progress
    end

    -- Close the V5 secondary-button style stack pushed at the start of
    -- this do-block.
    PopStyleColor(RA.ctx, 5)               -- Text, Border, Button, ButtonHovered, ButtonActive
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)     -- FrameBorderSize, FrameRounding, FramePadding
    PopFont(RA.ctx)
  end
  end -- API KEYS collapsible section
  ImGui.ImGui_EndDisabled(RA.ctx)  -- pair for BeginDisabled(key_validating) above;
                                 -- unconditional so it fires whether or not the
                                 -- API KEYS section is expanded

  -- Small breathing gap between API KEYS and the PREFERENCES label.
  -- Tuned so the inter-section spacing (API KEYS -> PREFERENCES) matches
  -- the PREFERENCES -> ADVANCED spacing below when both sections are
  -- collapsed -- 5px tighter than before for visual symmetry.
  Dummy(RA.ctx, 1, 1)

  if is_reentry then
  Dummy(RA.ctx, 1, RA.SC(10))

  -- PREFERENCES section -- collapsible, default open.
  api_keys.section_open.pref = UI.v5_section_label("PREFERENCES",
    api_keys.section_open.pref)
  if api_keys.section_open.pref then

  -- Toggle: Check for updates on startup. Stages the change on `prefs`
  -- only -- Save persists, Cancel reverts from api_keys.saved_update_check.
  do
    local changed, new_on = UI.v5_toggle("##pref_update_check",
      "Check for updates on startup",
      prefs.update_check,
      "Automatically check for new ReaAssist versions when the script starts",
      inner_w)
    if changed then prefs.update_check = new_on end
  end
  Dummy(RA.ctx, 1, RA.SC(6))

  -- Toggle: Auto-backup session before auto-runs. Stages on `prefs` only.
  do
    local changed, new_on = UI.v5_toggle("##pref_auto_backup",
      "Auto-backup session before auto-runs",
      prefs.auto_backup,
      "Save a timestamped .rpp-bak before Auto-Run executes returned code",
      inner_w)
    if changed then prefs.auto_backup = new_on end
  end
  Dummy(RA.ctx, 1, RA.SC(6))

  -- 3-column select grid: Theme / UI Scale / Chat Font (mockup order).
  -- Column widths split the content region evenly with SC(6) inter-col
  -- gap; cursor is manually advanced so the rows line up.
  do
    local GRID_GAP = RA.SC(6)
    local col_w    = math_floor((inner_w - GRID_GAP * 2) / 3)
    local row_sx   = GetCursorPosX(RA.ctx)
    local row_sy   = ImGui.ImGui_GetCursorPosY(RA.ctx)

    -- --- Theme ---
    local theme_names = { "auto", "dark", "light" }
    local theme_idx = 0
    for i, n in ipairs(theme_names) do
      if prefs.theme == n then theme_idx = i - 1; break end
    end
    ImGui.ImGui_SetCursorPos(RA.ctx, row_sx, row_sy)
    local th_changed, th_new = UI.v5_select_row("##pref_theme",
      "Theme", "Auto\0Dark\0Light\0", theme_idx,
      "Color theme: Auto follows your OS dark/light mode setting", col_w)
    if th_changed then
      prefs.theme = theme_names[th_new + 1]
      apply_palette(PALETTES[resolve_theme(prefs.theme)])  -- live preview
    end

    -- --- UI Scale ---
    ImGui.ImGui_SetCursorPos(RA.ctx, row_sx + col_w + GRID_GAP, row_sy)
    local scale_combo_str = table.concat(CFG.UI_SCALE_LABELS, "\0") .. "\0"
    local sc_changed, sc_new = UI.v5_select_row("##pref_ui_scale",
      "UI Scale", scale_combo_str, prefs.ui_scale_idx - 1,
      "Scale the entire interface (clamped to your monitor size)", col_w)
    if sc_changed and (sc_new + 1) ~= prefs.ui_scale_idx then
      S._scale_prev_idx = prefs.ui_scale_idx  -- save for revert
      S._scale_confirm_deadline = reaper.time_precise() + 10
      prefs.ui_scale_idx = sc_new + 1  -- live preview
      S._open_scale_confirm = true
    end

    -- --- Chat Font ---
    ImGui.ImGui_SetCursorPos(RA.ctx, row_sx + (col_w + GRID_GAP) * 2, row_sy)
    local cf_combo_str = table.concat(CFG.CHAT_FONT_LABELS, "\0") .. "\0"
    local cf_changed, cf_new = UI.v5_select_row("##pref_chat_font",
      "Chat Font", cf_combo_str, prefs.chat_font_idx - 1,
      "Font size for chat messages only (does not affect the rest of the UI)", col_w)
    if cf_changed then
      -- Stage on `prefs` only; Save persists, Cancel reverts.
      prefs.chat_font_idx = cf_new + 1
    end
  end
  Dummy(RA.ctx, 1, RA.SC(6))

  -- Preferred Plugins + Check for Updates row. Preferred Plugins
  -- sized to content (left-aligned under Theme). Check for Updates
  -- right-aligned so it sits under the Chat Font column of the grid
  -- above. Both rendered at the same y-baseline so they read as one
  -- paired row of Settings actions.
  do
    local row_x = GetCursorPosX(RA.ctx)
    local row_y = ImGui.ImGui_GetCursorPosY(RA.ctx)

    -- Preferred Plugins nav: sized to content (not the 1/3-column grid
    -- width the Theme/UI Scale/Chat Font row uses) so it reads as a
    -- compact nav button consistent with "Local & Custom Providers"
    -- and "FX Param Cache". Same width formula:
    --   label_w + gap(SC(8)) + chevron(SC(4)) + 2*pad(SC(24))
    local pp_label  = "Preferred Plugins"
    local pp_btn_w  = CalcTextSize(RA.ctx, pp_label) + RA.SC(36)
    local pp_tip    = "Set default plugins for each type (EQ, compressor, reverb, etc.)"
    if S.status ~= "waiting" then
      if UI.v5_nav_row("##pref_pref_plugins", pp_label, pp_tip, pp_btn_w) then
        api_keys.screen = "preferred_plugins"
        pref_plugins.initialized = false
      end
    else
      ImGui.ImGui_BeginDisabled(RA.ctx, true)
      UI.v5_nav_row("##pref_pref_plugins", pp_label, pp_tip, pp_btn_w)
      ImGui.ImGui_EndDisabled(RA.ctx)
    end

    -- Check for Updates action: icon + label card pill, right-aligned.
    -- Width formula matches pp_btn_w (label + SC(36)) with extra space
    -- for the Lucide icon and icon-label gap.
    local cu_label = "Check for Updates"
    local cu_tip   = "Check now for a newer ReaAssist release or missing files"
    local cu_btn_w = CalcTextSize(RA.ctx, cu_label) + RA.SC(56)
    ImGui.ImGui_SetCursorPos(RA.ctx, row_x + inner_w - cu_btn_w, row_y)
    local busy = Updater.is_busy()
    if busy or CFG.UPDATE_BASE_URL == "" then
      ImGui.ImGui_BeginDisabled(RA.ctx, true)
      UI.v5_action_row("##pref_check_updates", ICON.REDO_2, cu_label,
        cu_tip, cu_btn_w)
      ImGui.ImGui_EndDisabled(RA.ctx)
    else
      if UI.v5_action_row("##pref_check_updates", ICON.REDO_2, cu_label,
          cu_tip, cu_btn_w) then
        Updater.manual_check()
      end
    end
  end

  end -- PREFERENCES collapsible section

  -- ADVANCED section -- collapsible, closed by default. Houses the
  -- power-user prefs (snapshot/api_ref/timeout) and the maintenance
  -- actions (FX Cache / Reset Warnings / Reset Window / Factory Reset).
  -- Factory Reset is the destructive one.
  Dummy(RA.ctx, 1, RA.SC(14))
  api_keys.section_open.adv = UI.v5_section_label("ADVANCED",
    api_keys.section_open.adv)
  if api_keys.section_open.adv then
    -- Toggle: Send session snapshot.
    do
      local changed, new_on = UI.v5_toggle("##adv_include_snapshot",
        "Send session snapshot with each message",
        prefs.include_snapshot,
        "Attach a live snapshot of your project (tracks, FX, tempo, "
          .. "markers, etc.) with every message",
        inner_w)
      if changed then prefs.include_snapshot = new_on end
    end
    Dummy(RA.ctx, 1, RA.SC(6))

    -- Toggle: always pin the REAPER API reference. Off by default: the model
    -- requests <context_needed>docs</context_needed> only when it's about to
    -- write reaper.* code, saving ~10K tokens per turn on non-code requests.
    -- Turn ON if you do mostly code-generation and want zero round-trips.
    -- Toggling invalidates the Gemini prompt cache because ref is a cache key.
    do
      local changed, new_on = UI.v5_toggle("##adv_include_api_ref",
        "Always include REAPER API reference",
        prefs.include_api_ref,
        "Pin the REAPER Lua API reference to every request instead of letting "
          .. "the model fetch it on-demand. On = zero round-trips but ~10K "
          .. "extra tokens every turn. Off = saves tokens on non-code turns; "
          .. "the model fetches docs when it needs them.",
        inner_w)
      if changed then
        prefs.include_api_ref = new_on
        if not new_on then Net.gemini_cache_invalidate() end
      end
    end
    Dummy(RA.ctx, 1, RA.SC(6))

    -- Cloud Timeout select row. (Was paired with a Max Tokens dropdown in
    -- a 2-column grid; the Max Tokens knob was removed once each model's
    -- output ceiling became metadata -- Anthropic gets the model's published
    -- max sent in the request, OpenAI/Gemini omit the field so the server
    -- applies its own per-model default. The dropdown was a footgun: a
    -- fixed cap could be entirely consumed by reasoning tokens and produce
    -- empty visible output (observed on GPT-5.x with reasoning_effort set).)
    -- Timeout uses preset values; custom stored values survive by being
    -- inserted in-order into the preset list.
    do
      local col2_w    = inner_w
      local row_sx2   = GetCursorPosX(RA.ctx)
      local row_sy2   = ImGui.ImGui_GetCursorPosY(RA.ctx)

      -- Cloud-timeout combo: cached on cur_to's identity so the table
      -- assembly + sort + concat only re-fire when the saved timeout
      -- changes. The list is one of two shapes: pure presets, or
      -- presets + sorted-in custom value.
      local TO_PRESETS = { 60, 120, 180, 300, 600, 1200, 1800 }
      local cur_to = prefs.cloud_request_timeout or 180
      if UI._to_combo_cur ~= cur_to then
        local to_labels, to_values = {}, {}
        local cur_in_presets = false
        for _, v in ipairs(TO_PRESETS) do
          if v == cur_to then cur_in_presets = true end
          to_labels[#to_labels+1] = tostring(v) .. "s"
          to_values[#to_values+1] = v
        end
        if not cur_in_presets then
          to_values[#to_values+1] = cur_to
          table.sort(to_values)
          to_labels = {}
          for _, v in ipairs(to_values) do
            to_labels[#to_labels+1] = tostring(v) .. "s"
          end
        end
        local to_cur_idx = 0
        for i, v in ipairs(to_values) do
          if v == cur_to then to_cur_idx = i - 1; break end
        end
        UI._to_combo_cur     = cur_to
        UI._to_combo_str     = table.concat(to_labels, "\0") .. "\0"
        UI._to_combo_values  = to_values
        UI._to_combo_cur_idx = to_cur_idx
      end
      local to_combo_str = UI._to_combo_str
      local to_values    = UI._to_combo_values
      local to_cur_idx   = UI._to_combo_cur_idx
      ImGui.ImGui_SetCursorPos(RA.ctx, row_sx2, row_sy2)
      local to_changed, to_new_idx = UI.v5_select_row("##adv_cloud_timeout",
        "Cloud Timeout", to_combo_str, to_cur_idx,
        "How long to wait for a Claude/ChatGPT/Gemini response before "
          .. "timing out. Default 180s. Reasoning models on large prompts "
          .. "may need 300+", col2_w)
      if to_changed then
        prefs.cloud_request_timeout = to_values[to_new_idx + 1]
      end
    end

    -- Three maintenance actions on a single row, centered as a group:
    -- FX Param Cache / Reset Window Size / Factory Reset. Factory Reset
    -- keeps the muted-terracotta tint so it reads distinctly at the right
    -- edge of the row.
    Dummy(RA.ctx, 1, RA.SC(10))
    local adv_gap = RA.SC(8)
    -- Muted terracotta for Factory Reset: distinct from the neutral
    -- button row but not alarming. The confirm popup catches accidental
    -- clicks so the visual warning can stay subtle.
    local FR_RED  = 0xBF7777FF

    -- Shared frame metrics for both neutral and destructive buttons.
    -- Tuned to yield SC(30) button height so FX Param Cache (v5_nav_row),
    -- Reset Window Size, and Factory Reset all sit flush with the
    -- v5_toggle / v5_select_row rows above in PREFERENCES.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(12), RA.SC(8))

    -- Pre-measure so the whole row can be centered at once.
    -- v5_nav_row width = label_w + gap(SC(8)) + chevron(SC(4)) + 2*pad(SC(24)).
    -- Matches the sizing on "Local & Custom Providers" in API KEYS.
    local b_fx_w  = CalcTextSize(RA.ctx, "FX Param Cache") + RA.SC(36)
    local b_rws_w = CalcTextSize(RA.ctx, "Reset Window Size") + RA.SC(24)
    local b_fr_w  = CalcTextSize(RA.ctx, "Factory Reset")     + RA.SC(24)
    local row_w   = b_fx_w + adv_gap + b_rws_w + adv_gap + b_fr_w
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - row_w) * 0.5), 0))

    -- Neutral buttons (FX Param Cache + two resets).
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)

    -- Rendered via UI.v5_nav_row (centered label + chevron block) to
    -- signal "opens a different page". Same chrome as "Local & Custom
    -- Providers" above.
    if UI.v5_nav_row("##adv_fx_cache", "FX Param Cache",
        "View, rescan, or remove cached plugin parameter data. "
        .. "Curated plugins (those with a Plugin_Ref.md section) are "
        .. "also listed here as read-only entries for reference.",
        b_fx_w) then
      api_keys.screen = "fx_cache"
    end
    SameLine(RA.ctx, 0, adv_gap)

    if ImGui.ImGui_Button(RA.ctx, "Reset Window Size##adv_reset_win") then
      S._reset_window_size = true
      reaper.DeleteExtState(CFG.EXT_NS, "win_x", true)
      reaper.DeleteExtState(CFG.EXT_NS, "win_y", true)
      reaper.DeleteExtState(CFG.EXT_NS, "win_w", true)
      reaper.DeleteExtState(CFG.EXT_NS, "win_h", true)
    end
    UI.tooltip("Reset window to default size and clear saved position")
    SameLine(RA.ctx, 0, adv_gap)

    -- Pop the neutral color stack and push the destructive-red one for
    -- Factory Reset. Frame vars (border/rounding/padding) stay shared.
    PopStyleColor(RA.ctx, 5)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          FR_RED)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        FR_RED)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
    if ImGui.ImGui_Button(RA.ctx, "Factory Reset##adv_factory_reset") then
      ImGui.ImGui_OpenPopup(RA.ctx, "Factory Reset##factory_reset_confirm")
    end
    UI.tooltip("Clear all keys, preferences, and settings to start fresh")
    PopStyleColor(RA.ctx, 5)

    ImGui.ImGui_PopStyleVar(RA.ctx, 3)  -- FrameBorderSize, FrameRounding, FramePadding
    PopFont(RA.ctx)
  end -- ADVANCED collapsible section

  -- Factory Reset confirmation popup (stays rendered whether the
  -- ADVANCED section is open or not -- the OpenPopup call above is the
  -- only path that opens it, so leaving this always-called is fine).
  Render._factory_reset_popup(RA.ctx)
  do
    local fr_do_reset = Render._factory_reset_pending
    Render._factory_reset_pending = false
    if fr_do_reset then
      Render._factory_reset_execute()
    end
  end
  end -- is_reentry: options section

  -- ##unsaved_settings popup's BeginPopupModal is hoisted OUT of the
  -- BeginChild scope (below EndChild). ImGui popup IDs are scoped
  -- per-window; OpenPopup("##unsaved_settings") fires from the
  -- Cancel handler after EndChild (main-window context), so
  -- BeginPopupModal must live there too.

  Dummy(RA.ctx, 1, 8)

  -- Validation indicator lives inside each provider card (CONNECTED
  -- pill swaps to TESTING while that key is being tested).

  Dummy(RA.ctx, 1, 6)

  -- Close the scrollable body container. Unindent must happen INSIDE
  -- the child (paired with the Indent right after BeginChild) -
  -- otherwise the indent state leaks to subsequent frames.
  ImGui.ImGui_Unindent(RA.ctx, api_indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)  -- ScrollbarBg, ScrollbarGrab, -Hovered, -Active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)  -- ChildBorderSize, WindowPadding

  -- Frame-local flag: set by the unsaved_settings popup's Esc handler
  -- so the outer Esc handler below knows the key was already consumed
  -- Unsaved UI Scale confirmation popup (styled to match Factory Reset
  -- dialog). Lives in the main-window scope (after EndChild) so its
  -- BeginPopupModal ID matches the OpenPopup call in the Cancel
  -- handler below -- both must share the same scope for the modal
  -- to actually open.
  do
    local us_w, us_h = RA.SC(360), RA.SC(120)
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - us_w) * 0.5,
        update._main_y + (update._main_h - us_h) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, us_w, us_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Unsaved Changes##unsaved_settings", true,
        ImGui.ImGui_WindowFlags_NoResize()) then
      local us_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      local us_txt = "You have unsaved changes. Save before leaving?"
      local us_tw  = CalcTextSize(RA.ctx, us_txt)
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((us_cw - us_tw) * 0.5))
      Text(RA.ctx, us_txt)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)

      local us_save_w, us_disc_w, us_back_w, us_gap = RA.SC(72), RA.SC(72), RA.SC(56), RA.SC(12)
      local us_row = us_save_w + us_gap + us_disc_w + us_gap + us_back_w
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((us_cw - us_row) * 0.5))
      UI.push_modal_primary_btn()
      if ImGui.ImGui_Button(RA.ctx, "Save##us_save", us_save_w, 0) then
        -- Persist every staged Preference. Mirrors the main Save handler
        -- below so this "Save on exit" path writes the same ExtState keys.
        reaper.SetExtState(CFG.EXT_NS, "ui_scale_idx",
          tostring(prefs.ui_scale_idx), true)
        reaper.SetExtState(CFG.EXT_NS, "theme", prefs.theme, true)
        reaper.SetExtState(CFG.EXT_NS, "update_check",
          prefs.update_check and "1" or "0", true)
        reaper.SetExtState(CFG.EXT_NS, "auto_backup",
          prefs.auto_backup and "1" or "0", true)
        reaper.SetExtState(CFG.EXT_NS, "chat_font_idx",
          tostring(prefs.chat_font_idx), true)
        reaper.SetExtState(CFG.EXT_NS, "include_snapshot",
          prefs.include_snapshot and "1" or "0", true)
        reaper.SetExtState(CFG.EXT_NS, "include_api_ref",
          prefs.include_api_ref and "1" or "0", true)
        reaper.SetExtState(CFG.EXT_NS, "cloud_request_timeout",
          tostring(prefs.cloud_request_timeout), true)
        _exit_settings_screen()
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      UI.pop_modal_primary_btn()
      SameLine(RA.ctx, 0, us_gap)
      -- Discard is destructive (wipes staged edits) -- red palette.
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "Discard##us_disc", us_disc_w, 0) then
        -- Revert every staged Preference to its value at screen open.
        if api_keys.saved_ui_scale_idx then
          prefs.ui_scale_idx = api_keys.saved_ui_scale_idx
        end
        if api_keys.saved_theme then
          prefs.theme = api_keys.saved_theme
          apply_palette(PALETTES[resolve_theme(prefs.theme)])
        end
        if api_keys.saved_update_check ~= nil then
          prefs.update_check = api_keys.saved_update_check
        end
        if api_keys.saved_auto_backup ~= nil then
          prefs.auto_backup = api_keys.saved_auto_backup
        end
        if api_keys.saved_chat_font_idx then
          prefs.chat_font_idx = api_keys.saved_chat_font_idx
        end
        if api_keys.saved_include_snapshot ~= nil then
          prefs.include_snapshot = api_keys.saved_include_snapshot
        end
        if api_keys.saved_include_api_ref ~= nil then
          prefs.include_api_ref = api_keys.saved_include_api_ref
        end
        if api_keys.saved_cloud_request_timeout then
          prefs.cloud_request_timeout = api_keys.saved_cloud_request_timeout
        end
        _exit_settings_screen()
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, us_gap)
      if ImGui.ImGui_Button(RA.ctx, "Back##us_back", us_back_w, 0) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      -- Esc inside this popup mimics the Back button -- close the popup
      -- and stay on Settings. The outer Settings-cancel handler
      -- (around line ~7975) is gated on `UI.back_pressed()`, which
      -- returns false whenever any popup was open at frame start, so
      -- the same Esc press never bubbles into a Settings-wide Cancel
      -- (which would re-open this popup) -- no per-frame "consumed"
      -- flag needed.
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()
  end

  -- Check if at least one cloud key field has new content. Custom LLM config
  -- is managed on its own page, so it does not participate here. Hidden
  -- providers do not render an input on this page, so their key_bufs slot
  -- (if it ever got populated) cannot represent a real edit.
  local any_new_input = false
  for i, prov in ipairs(PROVIDERS) do
    if not prov.is_custom and not prov.hidden
       and api_keys.key_bufs[i] and api_keys.key_bufs[i]:match("%S") then
      any_new_input = true; break
    end
  end

  -- For first-run: need at least one new key. For re-entry: allow save with
  -- no new input (user may have only removed keys), or with new input. A
  -- key on a hidden provider does not count -- the user cannot reach it
  -- from this UI, and it would suppress the "enter a key" gate.
  local has_any_key = false
  for _, pk in ipairs(PROVIDERS) do
    if pk.is_custom or (not pk.hidden and S.api_key_map[pk.id]) then
      has_any_key = true; break
    end
  end
  -- Dirty signals across every staged setting on this screen. Each one
  -- compares prefs.* to api_keys.saved_* (the value at screen open) so
  -- the user can freely toggle back and forth without the indicator
  -- flipping permanently. `and`-chains keep nil-safety if a saved_*
  -- field isn't set for some reason.
  local scale_changed   = api_keys.saved_ui_scale_idx
    and prefs.ui_scale_idx ~= api_keys.saved_ui_scale_idx
  local theme_changed   = api_keys.saved_theme
    and prefs.theme ~= api_keys.saved_theme
  local upd_changed     = api_keys.saved_update_check ~= nil
    and prefs.update_check ~= api_keys.saved_update_check
  local bak_changed     = api_keys.saved_auto_backup ~= nil
    and prefs.auto_backup ~= api_keys.saved_auto_backup
  local font_changed    = api_keys.saved_chat_font_idx
    and prefs.chat_font_idx ~= api_keys.saved_chat_font_idx
  -- Merged from the old Advanced page:
  local snap_changed    = api_keys.saved_include_snapshot ~= nil
    and prefs.include_snapshot ~= api_keys.saved_include_snapshot
  local ref_changed     = api_keys.saved_include_api_ref ~= nil
    and prefs.include_api_ref ~= api_keys.saved_include_api_ref
  local to_changed      = api_keys.saved_cloud_request_timeout
    and prefs.cloud_request_timeout ~= api_keys.saved_cloud_request_timeout

  local any_pref_changed = scale_changed or theme_changed
    or upd_changed or bak_changed or font_changed
    or snap_changed or ref_changed or to_changed

  -- has_any_key flips true if any provider is usable: a built-in with
  -- a saved key in api_key_map, OR a custom provider record (the loop
  -- treats pk.is_custom as sufficient on its own). Allowing has_any_key
  -- on first-run is what lets a user who configured ONLY a custom LLM
  -- (e.g. Kimi) on the Local & Custom screen come back here and click
  -- Save & Continue without also pasting a cloud key they don't intend
  -- to use. Same condition serves the original re-entry semantics --
  -- a re-entry user who removed every key cannot Save unless they
  -- changed at least one preference.
  local can_submit = not api_keys.key_validating
    and (any_new_input or has_any_key or any_pref_changed)

  -- Dirty-state for the pinned footer bar's "Unsaved changes" indicator.
  local is_dirty = any_pref_changed or any_new_input

  -- Placeholder for click signals filled by the pinned bar at window
  -- bottom (drawn after the body content to overlay on top). Both
  -- feed the submit/discard handler below.
  local save_clicked, cancel_clicked = false, false

  -- Enter key anywhere on the Settings screen fires Save when submittable.
  -- Suppressed when a popup was open at the start of this frame: the
  -- popup (Factory Reset confirm, Clear Cache confirm, Unsaved Changes,
  -- etc.) owns the Enter key that frame. Without this gate, pressing
  -- Enter to confirm Factory Reset would ALSO fire the Settings Save
  -- handler right after, re-writing default prefs into the ExtState
  -- that the reset just wiped. Ctrl+S (Cmd+S on Mac) fires Save the
  -- same way; UI.is_save_shortcut shares the popup guard.
  if can_submit
    and not UI._popup_was_open
    and (ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
      or UI.is_save_shortcut()) then
    save_clicked = true
  end
  -- Escape key fires Cancel (re-entry only -- first-run has nothing
  -- to cancel TO). Suppressed when the ##unsaved_settings popup
  -- already consumed this frame's Esc (flag set inside the popup's
  -- own Esc handler); IsPopupOpen() can't be used for this check
  -- because CloseCurrentPopup pops the stack immediately, leaving
  -- IsPopupOpen() false for the rest of the same frame.
  if is_reentry and UI.back_pressed() then
    cancel_clicked = true
  end
  -- Footer-rail gear was clicked a second time while on Settings --
  -- treat it as a Cancel so the unsaved-changes prompt still fires
  -- if there are pending changes.
  if is_reentry and S._settings_request_cancel then
    S._settings_request_cancel = false
    cancel_clicked = true
  end

  UI.pop_settings_styles()

  -- (Unindent paired with Indent is handled inside the BeginChild
  -- above -- no outer Unindent here any more.)

  -- -------------------------------------------------------------------
  -- V5 Settings pinned footer bar.
  -- -------------------------------------------------------------------
  -- Fixed at the bottom of the window (via SetCursorScreenPos), bleeds
  -- edge-to-edge. Left: "Unsaved changes" mono indicator (re-entry + dirty
  -- only). Right: [Cancel] secondary + [Save] primary (accent, glowed).
  -- First-run shows just [Save & Continue] + a [Help] button on the
  -- left, since there's nothing to cancel to until the user saves a key.
  do
    -- Capture the body's end cursor BEFORE we SetCursorScreenPos into
    -- the pinned bar's region. When content overflows the window,
    -- body_end_y is below the window bottom; ImGui uses max-y-reached
    -- to size its scroll region, so we restore this at the end of the
    -- do-block to prevent SetCursorScreenPos'ing to a smaller Y from
    -- clobbering the tracker and killing the scrollbar.
    local body_end_x, body_end_y = ImGui.ImGui_GetCursorScreenPos(RA.ctx)

    local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    local win_w, win_h = ImGui.ImGui_GetWindowSize(RA.ctx)
    local BAR_H        = RA.SC(52)
    local FOOTER_RAIL_H = RA.SC(32)    -- matches UI.footer_rail_v5's ROW_H
    local BAR_PAD_X    = RA.SC(22)     -- matches the body's symmetric inset
    -- Shift the pinned Save/Cancel bar up by FOOTER_RAIL_H so the
    -- footer rail (rendered below) fits cleanly beneath it.
    local bar_sy       = win_y + win_h - BAR_H - FOOTER_RAIL_H
    local bar_mid_y    = bar_sy + BAR_H * 0.5
    local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
    -- Bg + 1px top border. The bar fills only its own BAR_H tall
    -- strip -- the footer rail below paints its own bg, so we don't
    -- extend the pinned bar all the way to the window bottom.
    ImGui.ImGui_DrawList_AddRectFilled(dl,
      win_x, bar_sy, win_x + win_w, bar_sy + BAR_H, TK.bg)
    ImGui.ImGui_DrawList_AddLine(dl,
      win_x, bar_sy, win_x + win_w, bar_sy, TK.border, 1)

    if is_reentry then
      -- Right-aligned [Cancel] [Save]. Equal widths -- the accent fill
      -- on Save carries the primary/secondary hierarchy on its own; the
      -- bold Save label reinforces it without piling on a width delta.
      local BTN_H   = RA.SC(28)
      local BTN_W   = RA.SC(80)
      local BTN_GAP = RA.SC(8)
      local btn_y_screen = bar_sy + math_floor((BAR_H - BTN_H) * 0.5)
      local save_x_screen   = win_x + win_w - BAR_PAD_X - BTN_W
      local cancel_x_screen = save_x_screen - BTN_GAP - BTN_W

      -- "Unsaved changes" mono indicator just left of the Cancel button
      -- (only when dirty). Painted in TK.accent with a small accent dot
      -- prefix so the "something is pending" signal is visually louder
      -- than a muted grey line. Placing it adjacent to the action buttons
      -- (not far-left of the bar) keeps the warning inside the same eye
      -- track as Save, so the "change -> save" feedback loop is tighter.
      if is_dirty then
        local UC_SZ = RA.SC(10)
        PushFont(RA.ctx, FONT.mono_reg, UC_SZ)
        local uc_tw, uc_h = CalcTextSize(RA.ctx, "Unsaved changes")
        PopFont(RA.ctx)
        local uc_y = bar_sy + math_floor((BAR_H - uc_h) * 0.5)
        local dot_r = RA.SC(3)
        -- Gap between the indicator block and the Cancel button's left edge.
        local UC_GAP = RA.SC(14)
        local block_right = cancel_x_screen - UC_GAP
        local text_x      = block_right - uc_tw
        local dot_cx      = text_x - RA.SC(6) - dot_r
        local dot_cy      = uc_y + math_floor(uc_h * 0.5)
        ImGui.ImGui_DrawList_AddCircleFilled(dl, dot_cx, dot_cy, dot_r, TK.accent, 16)
        ImGui.ImGui_DrawList_AddTextEx(dl, FONT.mono_reg, UC_SZ,
          text_x, uc_y, TK.accent, "Unsaved changes")
      end

      -- Shared button style: 5 radius, 14/7 padding, 1px border.
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(), RA.SC(5))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(14), RA.SC(7))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)

      -- Cancel (secondary): regular Inter, card bg.
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, cancel_x_screen, btn_y_screen)
      if ImGui.ImGui_Button(RA.ctx, "Cancel##pinned_cancel", BTN_W, BTN_H) then
        cancel_clicked = true
      end
      UI.tooltip("Discard changes and return to chat  (Esc)")
      PopStyleColor(RA.ctx, 5)
      PopFont(RA.ctx)

      -- Save (primary, accent). Bold label for visual emphasis; rect is
      -- identical SC(80) so the bold stroke stays inside the fixed width.
      PushFont(RA.ctx, FONT.inter_bold, RA.SC(12))
      ImGui.ImGui_BeginDisabled(RA.ctx, not can_submit)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.accent)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
        UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
        UI.lerp_u32(TK.accent, 0x000000FF, 0.12))
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, save_x_screen, btn_y_screen)
      if pending_focus == "save" then
        ImGui.ImGui_SetKeyboardFocusHere(RA.ctx)
      end
      if ImGui.ImGui_Button(RA.ctx, "Save##pinned_save", BTN_W, BTN_H) then
        save_clicked = true
      end
      PopStyleColor(RA.ctx, 5)
      ImGui.ImGui_EndDisabled(RA.ctx)
      PopFont(RA.ctx)
      if not can_submit then
        local tip_flags = ImGui.ImGui_HoveredFlags_AllowWhenDisabled()
        if ImGui.ImGui_IsItemHovered(RA.ctx, tip_flags) then
          UI.tooltip(api_keys.key_validating and "Key validation in progress..."
            or "Enter at least one API key to save")
        end
      else
        UI.tooltip("Save all staged changes  (Enter)")
      end

      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    else
      -- First-run: [Help] on the left, [Save & Continue] centered-ish
      -- on the right. No Cancel -- the user has to save at least one
      -- key before they can leave this screen.
      local BTN_H = RA.SC(28)
      local btn_y_screen = bar_sy + math_floor((BAR_H - BTN_H) * 0.5)

      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(), RA.SC(5))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(14), RA.SC(7))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)

      -- Help (left, secondary, regular weight).
      local HELP_W = RA.SC(70)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, win_x + BAR_PAD_X, btn_y_screen)
      if ImGui.ImGui_Button(RA.ctx, "Help##fr_help_pinned", HELP_W, BTN_H) then
        S.help_return_to = "first_run"
        api_keys.screen  = nil
        S.show_help      = true
      end
      UI.tooltip("Open the Help & Tips page (includes Report a Bug and Credits)")
      PopStyleColor(RA.ctx, 5)
      PopFont(RA.ctx)

      -- Save & Continue (right, primary accent, regular weight).
      local SAVE_W = RA.SC(160)
      local save_x_screen = win_x + win_w - BAR_PAD_X - SAVE_W
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
      ImGui.ImGui_BeginDisabled(RA.ctx, not can_submit)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.accent)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
        UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
        UI.lerp_u32(TK.accent, 0x000000FF, 0.12))
      ImGui.ImGui_SetCursorScreenPos(RA.ctx, save_x_screen, btn_y_screen)
      if pending_focus == "save" then
        ImGui.ImGui_SetKeyboardFocusHere(RA.ctx)
      end
      if ImGui.ImGui_Button(RA.ctx, "Save & Continue##pinned_save_fr", SAVE_W, BTN_H) then
        save_clicked = true
      end
      PopStyleColor(RA.ctx, 5)
      ImGui.ImGui_EndDisabled(RA.ctx)
      PopFont(RA.ctx)
      local tip_flags = ImGui.ImGui_HoveredFlags_AllowWhenDisabled()
      if ImGui.ImGui_IsItemHovered(RA.ctx, tip_flags) then
        if not can_submit then
          UI.tooltip(api_keys.key_validating and "Key validation in progress..."
            or "Enter at least one API key to save")
        else
          UI.tooltip("Save your key(s) and continue to ReaAssist  (Enter)")
        end
      end

      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    end

    -- Restore cursor to body-end so ImGui's CursorMaxPos reflects the
    -- full body content height (not the smaller Y of the pinned bar).
    -- Without this, content that overflows the window doesn't get a
    -- scrollbar because SetCursorScreenPos'ing up into the bar above
    -- clobbers the max-y tracker.
    ImGui.ImGui_SetCursorScreenPos(RA.ctx, body_end_x, body_end_y)
  end

  -- Cancel click handler (re-entry). If any staged pref differs from
  -- its saved_* stash, prompt via ##unsaved_settings. Otherwise exit
  -- directly. Any non-empty key input buffer also counts as "unsaved"
  -- so the user doesn't lose a pasted key by accident.
  if is_reentry and cancel_clicked then
    if any_pref_changed or any_new_input then
      ImGui.ImGui_OpenPopup(RA.ctx, "Unsaved Changes##unsaved_settings")
    else
      -- No staged edits and no popup needed -- exit straight back to the
      -- previous screen via the shared cleanup helper.
      _exit_settings_screen()
    end
  end

  -- Handle submit. Validate format for all non-empty new fields, then fire a
  -- test for the first newly entered valid key. If no new keys were entered
  -- (re-entry with only removals), return to the main UI immediately.
  if save_clicked and can_submit then
    -- Persist every staged Preference to ExtState. Each saved_* stash
    -- is cleared so the screen starts "clean" if the user re-enters
    -- Settings without leaving the script.
    if api_keys.saved_ui_scale_idx then
      reaper.SetExtState(CFG.EXT_NS, "ui_scale_idx",
        tostring(prefs.ui_scale_idx), true)
      api_keys.saved_ui_scale_idx = nil
    end
    if api_keys.saved_theme then
      reaper.SetExtState(CFG.EXT_NS, "theme", prefs.theme, true)
      api_keys.saved_theme = nil
    end
    if api_keys.saved_update_check ~= nil then
      reaper.SetExtState(CFG.EXT_NS, "update_check",
        prefs.update_check and "1" or "0", true)
      api_keys.saved_update_check = nil
    end
    if api_keys.saved_auto_backup ~= nil then
      reaper.SetExtState(CFG.EXT_NS, "auto_backup",
        prefs.auto_backup and "1" or "0", true)
      api_keys.saved_auto_backup = nil
    end
    if api_keys.saved_chat_font_idx then
      reaper.SetExtState(CFG.EXT_NS, "chat_font_idx",
        tostring(prefs.chat_font_idx), true)
      api_keys.saved_chat_font_idx = nil
    end
    if api_keys.saved_include_snapshot ~= nil then
      reaper.SetExtState(CFG.EXT_NS, "include_snapshot",
        prefs.include_snapshot and "1" or "0", true)
      api_keys.saved_include_snapshot = nil
    end
    if api_keys.saved_include_api_ref ~= nil then
      reaper.SetExtState(CFG.EXT_NS, "include_api_ref",
        prefs.include_api_ref and "1" or "0", true)
      api_keys.saved_include_api_ref = nil
    end
    if api_keys.saved_cloud_request_timeout then
      reaper.SetExtState(CFG.EXT_NS, "cloud_request_timeout",
        tostring(prefs.cloud_request_timeout), true)
      api_keys.saved_cloud_request_timeout = nil
    end
    api_keys.key_error    = nil
    local first_valid_idx  = nil
    local has_format_error = false
    for i, prov in ipairs(PROVIDERS) do
      api_keys.key_errors[i] = nil
      if not prov.is_custom and not prov.hidden then
        local trimmed = (api_keys.key_bufs[i] or ""):match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" then
          local valid, reason = Key.validate_format(trimmed, prov)
          if not valid then
            api_keys.key_errors[i] = reason
            has_format_error = true
          else
            -- Key format is valid: store in memory (persisted after test succeeds).
            S.api_key_map[prov.id] = trimmed
            if not first_valid_idx then first_valid_idx = i end
          end
        end
      end
    end

    if has_format_error then
      -- Stay on screen with per-field errors.
    else
      if first_valid_idx then
        -- Fire a test call for the first newly entered valid CLOUD key.
        -- Snapshot the active provider before flipping so the post-test
        -- restore in handle_key_test's success path can put the user
        -- back where they were. Without the snapshot, pasting a NEW
        -- key for a non-active provider would silently switch the
        -- active provider as a side effect of testing.
        api_keys._test_orig_provider_idx = prefs.provider_idx
        local test_prov = PROVIDERS[first_valid_idx]
        S.api_key = S.api_key_map[test_prov.id]
        prefs.provider_idx = first_valid_idx
        MODELS.refresh()
        api_keys.key_validating = true
        api_keys.key_validating_idx = first_valid_idx
        Net.fire_key_test(test_prov)
      elseif is_reentry or has_any_key then
        -- No new cloud keys to test. Re-entry: user may have only
        -- removed keys or just toggled prefs. First-run: user has a
        -- custom provider already configured (has_any_key) and isn't
        -- pasting a cloud key. Either way, exit the screen.
        -- If the active provider's key was just removed (built-in with
        -- nothing left in api_key_map), snap prefs.provider_idx to the
        -- first usable provider before exiting. Otherwise the home
        -- chip shows a stranded selection that the dropdown filter
        -- has already hidden -- the model list still populates and the
        -- send button stays disabled because S.api_key is nil. Mirrors
        -- the same failsafe in the Custom LLM save path.
        do
          local act = PROVIDERS.active()
          if act and not act.is_custom and not S.api_key_map[act.id] then
            for i, p in ipairs(PROVIDERS) do
              if not p.hidden and (p.is_custom or S.api_key_map[p.id]) then
                prefs.provider_idx = i
                reaper.SetExtState(CFG.EXT_NS, "provider_idx",
                  tostring(prefs.provider_idx), true)
                MODELS.refresh()
                break
              end
            end
          end
        end
        api_keys.screen       = nil
        api_keys.is_reentry   = false
        api_keys.key_bufs     = {}
        api_keys.key_errors   = {}
        api_keys.key_error    = nil
        api_keys.key_focused  = false
        api_keys.custom_edit = nil  -- next open re-reads from ExtState
        S.api_key = S.api_key_map[PROVIDERS.active().id]
        UI.show_float_toast("Settings saved", "ok")
      else
        api_keys.key_error = "Please enter at least one valid API key, or "
          .. "configure a custom LLM via Local & Custom LLMs."
      end
    end
  end

  Render._key_test_results_popup()
  Render._key_validation_error_popup()

  -- V5 footer rail: self-pinned to window bottom, cursor-transparent.
  UI.footer_rail_v5()
end

-- =============================================================================
-- Custom Providers list: navigation helpers + list screen
-- =============================================================================
-- Two entry points into Render.custom_llm_screen:
--   api_keys.enter_custom_edit(record)  -- edit an existing persisted record
--   api_keys.enter_custom_new()         -- start a blank new record
-- Both populate api_keys.custom_edit with string buffers the edit screen
-- expects. The record's stable id drives every persistence + provider-
-- registration call site, so renaming the label never reshuffles anything.

function api_keys.enter_custom_new()
  api_keys.custom_edit = {
    id              = Custom.gen_id(),
    is_new          = true,
    saved_label     = nil,
    endpoint        = "",
    timeout         = tostring(CUSTOM_DEFAULT_TIMEOUT),
    connect_timeout = tostring(Custom.DEFAULT_CONNECT),
    allow_insecure  = false,
    model_prefix    = "",
    headers_text    = "",   -- multi-line buffer; one "Name: value" per line
    extra_body      = "",   -- provider-wide JSON object, merged into every body
    label           = "",
    key             = "",
    errors          = {},
    models          = { {
      id = "", price_in = "0", price_cache_r = "0", price_out = "0",
      context_window = tostring(CUSTOM_DEFAULT_CTX),
      notes = "", extra_body = "",
    } },
  }
  if api_keys.custom_conn_test then
    api_keys.custom_conn_test.result = nil
  end
  api_keys.screen = "custom_llm"
end

-- Convert a record-or-provider source into the string-buffer shape the edit
-- screen expects. Accepts both raw records (Custom.load_record shape, with
-- timeout_secs) and registered providers (PROVIDERS entries, with
-- request_timeout) so callers can hand over whichever they have at reach.
local function _build_edit_models_buf(src)
  local buf = {}
  for _, m in ipairs(src.models or {}) do
    buf[#buf+1] = {
      id             = m.id or "",
      price_in       = tostring(m.price_in       or 0),
      price_cache_r  = tostring(m.price_cache_r  or 0),
      price_out      = tostring(m.price_out      or 0),
      context_window = tostring(m.context_window or CUSTOM_DEFAULT_CTX),
      notes          = m.notes      or "",
      extra_body     = m.extra_body or "",
    }
  end
  if #buf == 0 then
    buf[1] = {
      id = "", price_in = "0", price_cache_r = "0", price_out = "0",
      context_window = tostring(CUSTOM_DEFAULT_CTX),
      notes = "", extra_body = "",
    }
  end
  return buf
end

-- Pull the saved/runtime values for the four advanced fields off a record
-- OR a registered-provider source. Records use timeout_secs /
-- connect_timeout_secs; providers use request_timeout / connect_timeout.
-- Extra headers come through as a ready-made array; we serialize one per
-- line for the multi-line input buffer.
local function _build_adv_fields(src)
  local timeout_n = src.timeout_secs or src.request_timeout or CUSTOM_DEFAULT_TIMEOUT
  local connect_n = src.connect_timeout_secs or src.connect_timeout or Custom.DEFAULT_CONNECT
  local headers_text = tbl_concat(src.extra_headers or {}, "\n")
  return {
    timeout         = tostring(timeout_n),
    connect_timeout = tostring(connect_n),
    allow_insecure  = src.allow_insecure and true or false,
    model_prefix    = src.model_prefix or "",
    headers_text    = headers_text,
    extra_body      = src.extra_body or "",
  }
end

function api_keys.enter_custom_edit(record)
  -- Load the saved key so the user can edit it in-place. Key.decode is the
  -- inverse of Key.save; an empty / missing blob falls back to the empty
  -- string so the password field renders as blank rather than as "nil".
  local saved_blob = reaper.GetExtState(CFG.EXT_NS, "api_key_" .. record.id)
  local saved_key  = (saved_blob ~= "" and Key.decode(saved_blob)) or ""
  local adv        = _build_adv_fields(record)
  api_keys.custom_edit = {
    id              = record.id,
    is_new          = false,
    saved_label     = record.label,
    endpoint        = record.endpoint or "",
    timeout         = adv.timeout,
    connect_timeout = adv.connect_timeout,
    allow_insecure  = adv.allow_insecure,
    model_prefix    = adv.model_prefix,
    headers_text    = adv.headers_text,
    extra_body      = adv.extra_body,
    label           = record.label or "",
    key             = saved_key,
    orig_key        = saved_key,  -- detect "user blanked the key" on Save
    errors          = {},
    models          = _build_edit_models_buf(record),
  }
  if api_keys.custom_conn_test then
    api_keys.custom_conn_test.result = nil
  end
  api_keys.screen = "custom_llm"
end

-- Prefill the edit form with a copy of `source`'s data under a freshly-minted
-- id. Nothing is persisted until the user hits Save on the edit screen, so
-- Cancel cleanly discards the copy -- no orphan record in the list.
function api_keys.enter_custom_duplicate(source)
  local adv = _build_adv_fields(source)
  api_keys.custom_edit = {
    id              = Custom.gen_id(),
    is_new          = true,
    saved_label     = nil,
    endpoint        = source.endpoint or "",
    timeout         = adv.timeout,
    connect_timeout = adv.connect_timeout,
    allow_insecure  = adv.allow_insecure,
    model_prefix    = adv.model_prefix,
    headers_text    = adv.headers_text,
    extra_body      = adv.extra_body,
    label           = (source.label or "Custom") .. " (Copy)",
    key             = "",   -- secrets stay with source
    errors          = {},
    models          = _build_edit_models_buf(source),
  }
  if api_keys.custom_conn_test then
    api_keys.custom_conn_test.result = nil
  end
  api_keys.screen = "custom_llm"
end

-- =============================================================================
-- Render.custom_providers_screen
-- =============================================================================
-- List view for every persisted custom provider record. Shown as a column of
-- cards: label, endpoint + model count, action buttons (Edit / Duplicate /
-- Delete). A prominent "+ Add Provider" button sits at the top; when the list
-- is empty, a centered call-to-action takes its place to guide first-run.
-- Back / Cancel returns to _cllm_source (Settings or first_run).
function Render.custom_providers_screen()
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w     = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local indent_w = math_max(math_floor((stable_w - inner_w) * 0.5), 0)

  UI.push_settings_styles()

  UI.hero_band_settings_v5(
    "Local & Custom Providers",
    "LOCAL & CUSTOM PROVIDERS \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##cpl_body", _body_avail_w, _body_h, 0)
  ImGui.ImGui_Indent(RA.ctx, indent_w)

  Dummy(RA.ctx, 1, RA.SC(16))

  -- Lead-in paragraph (privacy + technical).
  local desc_wrap_x = GetCursorPosX(RA.ctx) + inner_w - RA.SC(20)
  ImGui.ImGui_PushTextWrapPos(RA.ctx, desc_wrap_x)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Running a local model keeps every session fully offline.\n"
    .. "No data leaves your machine. Ideal for confidential or high-value client work.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(6))
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Register any number of OpenAI-compatible endpoints: local servers "
    .. "(Ollama, LM Studio, llama.cpp, vLLM) and online gateways "
    .. "(OpenRouter, Groq, DeepSeek, Together AI, Mistral, etc.).")
  PopStyleColor(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(4))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
    UI.lerp_u32(TK.amber, TK.text_muted, 0.5))
  Text(RA.ctx,
    "Experimental feature. Not fully tuned, and cost estimates may be inaccurate.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  ImGui.ImGui_PopTextWrapPos(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(14))

  -- Source of truth for the list: the in-memory PROVIDERS table. Every
  -- custom record lives there as a provider entry after Custom.register_all,
  -- and that table carries all the fields the list needs (id, label,
  -- endpoint, models, request_timeout). Reading it directly avoids the
  -- per-frame ExtState re-read cost of Custom.load_all() -- the list stays
  -- in perfect sync with on-disk state because every mutation (Save,
  -- Delete, Duplicate) calls Custom.register_all before returning here.
  -- The conn-test sentinel is filtered out so it never surfaces as a card
  -- (only registered during an in-flight Test, and only ever visible from
  -- the edit screen).
  -- Cache the filtered records list keyed on Custom._records_version
  -- (bumped by every Custom.register_one / unregister_all /
  -- unregister_id mutation). The full PROVIDERS walk only re-fires on
  -- a real list change instead of every frame the page is open.
  local _rec_v = Custom._records_version or 0
  local records
  if UI._custom_records_v == _rec_v then
    records = UI._custom_records_cache
  else
    records = {}
    for _, p in ipairs(PROVIDERS) do
      if p.is_custom and p.id ~= CUSTOM_CONN_TEST_ID then
        records[#records+1] = p
      end
    end
    UI._custom_records_v     = _rec_v
    UI._custom_records_cache = records
  end

  -- Frame-local flag: set from inside a card's child-window scope when the
  -- user clicks Delete, then consumed AFTER the cards loop to call
  -- ImGui_OpenPopup in the same scope as the BeginPopupModal below. ImGui
  -- popups bind to the window active at OpenPopup time -- opening from
  -- inside the card's BeginChild scope associates the popup with that
  -- child, so the BeginPopupModal at the outer scope never sees it as
  -- "open" and the modal never renders.
  local pending_open_delete = nil

  -- "+ Add Provider" button: primary CTA, full inner-width pill.
  do
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
      UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
      UI.lerp_u32(TK.accent, 0x000000FF, 0.15))
    if ImGui.ImGui_Button(RA.ctx, "+  Add Provider##cpl_add", inner_w, 0) then
      api_keys.enter_custom_new()
    end
    UI.pressable()
    UI.tooltip("Configure a new OpenAI-compatible endpoint (local or hosted)")
    PopStyleColor(RA.ctx, 4)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)
  end

  Dummy(RA.ctx, 1, RA.SC(14))

  if #records == 0 then
    -- Empty-state: quiet helper text. The Add Provider button above is
    -- the primary CTA; no need to duplicate it here.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    ImGui.ImGui_PushTextWrapPos(RA.ctx, GetCursorPosX(RA.ctx) + inner_w - RA.SC(20))
    Text(RA.ctx,
      "No custom providers yet. Click Add Provider above to point "
      .. "ReaAssist at a local model or an OpenAI-compatible gateway.")
    ImGui.ImGui_PopTextWrapPos(RA.ctx)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  else
    -- Card per record.
    for ri, rec in ipairs(records) do
      if ri > 1 then Dummy(RA.ctx, 1, RA.SC(8)) end

      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(6))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(12), RA.SC(10))

      if ImGui.ImGui_BeginChild(RA.ctx, "##cpl_card_" .. rec.id, inner_w, 0,
          ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
        -- Header row: label (semi) + model-count chip (mono, right-aligned).
        local card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(13))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
        Text(RA.ctx, rec.label)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Model count on the same baseline, right-aligned.
        SameLine(RA.ctx)
        local mcount = #rec.models
        local chip_txt = str_format("%d MODEL%s", mcount, mcount == 1 and "" or "S")
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        local chip_w = CalcTextSize(RA.ctx, chip_txt)
        PopFont(RA.ctx)
        local avail_after = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        SetCursorPosX(RA.ctx,
          GetCursorPosX(RA.ctx) + math_max(avail_after - chip_w - RA.SC(2), 0))
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
        Text(RA.ctx, chip_txt)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Endpoint URL (mono, muted).
        Dummy(RA.ctx, 1, RA.SC(2))
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        ImGui.ImGui_PushTextWrapPos(RA.ctx, GetCursorPosX(RA.ctx) + card_w)
        Text(RA.ctx, rec.endpoint or "")
        ImGui.ImGui_PopTextWrapPos(RA.ctx)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Action row: Edit (primary-muted) / Duplicate / Delete.
        Dummy(RA.ctx, 1, RA.SC(8))
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
          UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
          UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))

        if ImGui.ImGui_Button(RA.ctx, "Edit##cpl_edit_" .. rec.id) then
          api_keys.enter_custom_edit(rec)
        end
        UI.tooltip("Edit this provider's endpoint, models, and key")
        SameLine(RA.ctx, 0, RA.SC(6))
        if ImGui.ImGui_Button(RA.ctx, "Duplicate##cpl_dup_" .. rec.id) then
          -- Prefill the edit form with a copy under a new id. Nothing
          -- persists until the user hits Save, so Cancel discards cleanly.
          api_keys.enter_custom_duplicate(rec)
        end
        UI.tooltip("Open a new provider form prefilled from this one (API key is not copied)")
        SameLine(RA.ctx, 0, RA.SC(6))

        -- Delete uses red-on-hover as with other destructive pills.
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
          (TK.red & 0xFFFFFF00) | 0x20)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
          (TK.red & 0xFFFFFF00) | 0x38)
        if ImGui.ImGui_Button(RA.ctx, "Delete##cpl_del_" .. rec.id) then
          -- Defer OpenPopup to parent scope -- see the pending_open_delete
          -- comment at the top of this function for why.
          pending_open_delete = rec.id
        end
        UI.tooltip("Remove this provider (asks for confirmation)")
        PopStyleColor(RA.ctx, 2)

        PopStyleColor(RA.ctx, 5)
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)
        PopFont(RA.ctx)

        ImGui.ImGui_EndChild(RA.ctx)
      end

      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopStyleColor(RA.ctx, 2)
    end
  end

  -- Consume the deferred Delete click from the card loop now that we're
  -- back in the body's scope -- the popup needs to bind to this scope, not
  -- the card child's scope, or BeginPopupModal below won't see it as open.
  if pending_open_delete then
    api_keys.custom_providers_confirm = pending_open_delete
    ImGui.ImGui_OpenPopup(RA.ctx, "Delete Provider##cpl_del_popup")
  end

  -- Delete-confirmation popup. Modal; if any record was flagged for delete
  -- above, this paints once per frame until the user picks Confirm / Cancel.
  do
    local del_w, del_h = RA.SC(380), RA.SC(184)
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - del_w) * 0.5,
        update._main_y + (update._main_h - del_h) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, del_w, del_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Delete Provider##cpl_del_popup", true,
        ImGui.ImGui_WindowFlags_NoResize()) then
      local del_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      local target_id = api_keys.custom_providers_confirm
      local target = nil
      for _, r in ipairs(records) do
        if r.id == target_id then target = r; break end
      end
      local del_label = target and target.label or "this provider"
      ImGui.ImGui_Spacing(RA.ctx)
      local line = 'Delete "' .. del_label .. '"?'
      local line_tw = CalcTextSize(RA.ctx, line)
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx)
        + math_floor((del_cw - line_tw) * 0.5))
      Text(RA.ctx, line)
      Dummy(RA.ctx, 1, RA.SC(6))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      ImGui.ImGui_PushTextWrapPos(RA.ctx,
        GetCursorPosX(RA.ctx) + del_cw - RA.SC(8))
      Text(RA.ctx,
        "Removes the endpoint, models, and stored API key. This can't "
        .. "be undone.")
      ImGui.ImGui_PopTextWrapPos(RA.ctx)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
      Dummy(RA.ctx, 1, RA.SC(8))

      local del_yes_w, del_no_w, del_gap = RA.SC(88), RA.SC(72), RA.SC(16)
      local del_row = del_yes_w + del_gap + del_no_w
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx)
        + math_floor((del_cw - del_row) * 0.5))
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "Confirm##cpl_del_yes", del_yes_w, 0) then
        if target_id then
          local was_active_id = PROVIDERS.active() and PROVIDERS.active().id
          local active_removed = (was_active_id == target_id)
          Custom.unregister_id(target_id)
          Custom.remove_record(target_id)
          Custom.register_all()
          if active_removed then
            prefs.provider_idx = 1
            reaper.SetExtState(CFG.EXT_NS, "provider_idx", "1", true)
            MODELS.refresh()
            S.api_key = S.api_key_map[PROVIDERS.active().id]
          elseif was_active_id and PROVIDERS._by_id[was_active_id] then
            prefs.provider_idx = PROVIDERS._by_id[was_active_id]
          end
        end
        api_keys.custom_providers_confirm = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, del_gap)
      if ImGui.ImGui_Button(RA.ctx, "Cancel##cpl_del_no", del_no_w, 0) then
        api_keys.custom_providers_confirm = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        api_keys.custom_providers_confirm = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()
  end

  Dummy(RA.ctx, 1, RA.SC(18))

  -- Footer action: single "Back" button centered. Routes to whichever
  -- screen opened this list (Settings re-entry or first-run API screen).
  local back_w
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  back_w = CalcTextSize(RA.ctx, "Back") + RA.SC(40)
  PopFont(RA.ctx)
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - back_w) * 0.5), 0))
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
  local back_clicked = ImGui.ImGui_Button(RA.ctx, "Back##cpl_back", back_w, 0)
  UI.pressable()
  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  Dummy(RA.ctx, 1, RA.SC(10))

  ImGui.ImGui_Unindent(RA.ctx, indent_w)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)
  UI.pop_settings_styles()

  if back_clicked or UI.back_pressed() then
    api_keys.screen        = api_keys._cllm_source or "settings"
    api_keys._cllm_source  = nil
  end

  UI.footer_rail_v5()
end

-- =============================================================================
-- Render.custom_llm_screen
-- =============================================================================
-- Full-window page for editing ONE custom-provider record. Opened from the
-- Custom Providers list screen -- either "+ Add Provider" (creates a blank
-- record under a freshly-minted id) or the per-card Edit button (loads the
-- existing record). All form state lives in api_keys.custom_edit so multiple
-- records can coexist without this screen having to peek at global state.
-- Styled like the other full-screen config pages (preferred_plugins, fx_cache).
function Render.custom_llm_screen()
  -- Connection-test state (one-time lazy init). Kept at top-level scope on
  -- api_keys because the watchdog + curl-exit handlers that fire mid-test
  -- live outside this function and need a stable access point. The edit
  -- record being tested is addressed by CUSTOM_CONN_TEST_ID in PROVIDERS.
  api_keys.custom_conn_test = api_keys.custom_conn_test or {
    active            = false,
    started           = nil,  -- time_precise() when the test fired
    timeout           = CUSTOM_DEFAULT_TEST_TIMEOUT,
    result            = nil,  -- { ok = bool, error = string } once complete
    orig_provider_idx = nil,  -- to restore prefs.provider_idx on finish
  }

  -- api_keys.custom_edit is populated by the list screen's Add/Edit buttons
  -- before it transitions screen to "custom_llm". A nil here means we got
  -- here via a stale navigation path -- recover by returning to the list.
  if not api_keys.custom_edit then
    api_keys.screen = "custom_providers"
    return
  end
  local edit = api_keys.custom_edit

  -- Centered column. Narrower inner_w (SC(540)) matches the Settings page
  -- for consistent left/right padding across the settings-family screens.
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w     = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local cllm_indent = math_max(math_floor((stable_w - inner_w) * 0.5), 0)

  UI.push_settings_styles()

  -- V5 hero band. Esc / Back / footer / logo click cover nav.
  UI.hero_band_settings_v5(
    "Point ReaAssist at a local or custom model.",
    "LOCAL / CUSTOM LLM \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: see Render.credits_screen for the full pattern.
  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##cllm_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, cllm_indent)

  Dummy(RA.ctx, 1, RA.SC(16))

  -- Intro copy + experimental advisory. SC(12) Inter so the block
  -- reads as a compact lead-in (not competing with the section
  -- labels). TK.text body; muted-amber advisory -- a 50/50 blend of
  -- TK.amber and TK.text_muted so the line reads as cautionary but
  -- not alarming.
  local desc_wrap_x = GetCursorPosX(RA.ctx) + inner_w - RA.SC(20)
  ImGui.ImGui_PushTextWrapPos(RA.ctx, desc_wrap_x)
  -- Privacy value-prop (inter_semi -- bold weight, TK.text) -- leads the
  -- page so users immediately see WHY they'd configure a custom LLM
  -- rather than the technical how.
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Running a local model keeps every session fully offline. No data "
    .. "leaves your machine. Ideal for confidential or high-value client work.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(6))
  -- Technical description (inter_reg, TK.text).
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Point ReaAssist at any OpenAI-compatible endpoint: a local "
    .. "server (Ollama, LM Studio, llama.cpp, vLLM) or an online "
    .. "gateway (OpenRouter, Groq, DeepSeek, Together AI, Mistral, etc.).")
  PopStyleColor(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(4))
  -- Domain-specific size advisory: ReaAssist's worst failure mode with
  -- small local models is plausible-looking code that runs cleanly,
  -- passes the API validator, and silently does nothing. Users won't
  -- predict that from "Experimental feature" alone, so this block calls
  -- it out explicitly with a size-floor recommendation. Bold lead +
  -- regular body matches the privacy/technical-description pattern above.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
  Text(RA.ctx, "Heads up: local model size matters for ReaAssist.")
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(2))
  Text(RA.ctx,
    "REAPER's ReaScript and JSFX APIs are a niche surface poorly "
    .. "represented in any model's pretraining. Small models (7-8B) "
    .. "will connect and produce code that looks right, but most "
    .. "replies will use fabricated function names or wrap real names "
    .. "around no-op logic. The API validator can't always catch this.")
  Dummy(RA.ctx, 1, RA.SC(4))
  Text(RA.ctx,
    "For usable results, use a code-specialized model with at least "
    .. "~14B parameters (e.g. Qwen 2.5 Coder 14B at ~12 GB VRAM); 32B "
    .. "coders on 24 GB VRAM work substantially better. Below 14B, "
    .. "treat the connection as \"wired up correctly\" rather than "
    .. "\"ready to use.\"")
  PopStyleColor(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(4))
  -- Muted-amber advisory: 50/50 blend of TK.amber and TK.text_muted so
  -- the line reads as cautionary but not alarming. Kept to one line so
  -- it doesn't dominate the header block.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
    UI.lerp_u32(TK.amber, TK.text_muted, 0.5))
  Text(RA.ctx,
    "Experimental feature. Not fully tuned, and cost estimates may be inaccurate.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  ImGui.ImGui_PopTextWrapPos(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(14))

  -- Card helper pair: TK.card fill + TK.border stroke + 6 px radius +
  -- SC(12,10) padding. Matches the provider cards on Settings so the
  -- ENDPOINT / MODELS / ADVANCED blocks read as the same surface
  -- family across the settings-group screens.
  local function _push_cllm_card()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(12), RA.SC(10))
  end
  local function _pop_cllm_card()
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 2)
  end

  -- Recessed-input style: TK.input_bg fill on rest + hover + active,
  -- mono SC(10) font, SC(8,5) frame padding. Pair push/pop around any
  -- ImGui_InputText* call that should read as a "text well" on a card.
  local function _push_input_style()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),         TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),  TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),   TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),            TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(), TK.text)
    PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), RA.SC(8), RA.SC(5))
  end
  local function _pop_input_style()
    ImGui.ImGui_PopStyleVar(RA.ctx)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx, 5)
  end

  -- Field-label pair: "Label" (Inter SemiBold SC(11) / TK.text) + optional
  -- "(hint)" muted suffix. Consolidates the label boilerplate used above
  -- every input on this page.
  local function _field_label(label, suffix)
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    Text(RA.ctx, label)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    if suffix and suffix ~= "" then
      SameLine(RA.ctx, 0, RA.SC(6))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
      Text(RA.ctx, suffix)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    end
  end

  -- Inline error / advisory line (Inter SC(10), TK.red or TK.amber).
  local function _inline_msg(txt, col)
    if not txt or txt == "" then return end
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col or TK.red)
    Text(RA.ctx, txt)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end

  -- Outer disable wraps every input on the page while a key test /
  -- connection test is in flight, mirroring the Settings page.
  ImGui.ImGui_BeginDisabled(RA.ctx, api_keys.key_validating)

  -- Editing-identity strip: shows whether this is an Add or Edit session and
  -- the saved label when editing. Replaces the old "Configured / Remove"
  -- banner -- Delete lives in the footer action row so it's grouped with the
  -- other commit-level actions (Cancel / Test / Save). Shown for every edit
  -- session; labels and colors disambiguate Add vs Edit.
  do
    local dot_r   = RA.SC(4)
    local dot_dia = dot_r * 2
    local row_sx, row_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
    local font_h = ImGui.ImGui_GetTextLineHeight(RA.ctx)
    ImGui.ImGui_InvisibleButton(RA.ctx, "##cllm_status_dot", dot_dia + 2, font_h)
    local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
    local dot_cy = row_sy + font_h * 0.5 - RA.SC(1)
    local dot_col = edit.is_new and TK.accent_ui or TK.green
    local halo    = (dot_col & 0xFFFFFF00) | 0x40
    ImGui.ImGui_DrawList_AddCircleFilled(dl,
      row_sx + dot_r + 1, dot_cy, dot_r * 2, halo, 20)
    ImGui.ImGui_DrawList_AddCircleFilled(dl,
      row_sx + dot_r + 1, dot_cy, dot_r, dot_col, 16)
    SameLine(RA.ctx, 0, RA.SC(8))
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
    Text(RA.ctx, edit.is_new and "New Provider" or "Editing Provider")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    if not edit.is_new then
      SameLine(RA.ctx, 0, RA.SC(8))
      PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, edit.saved_label or "")
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    end
    Dummy(RA.ctx, 1, RA.SC(12))
  end

  -- ============================================================
  -- ENDPOINT section: URL + presets + API key.
  -- ============================================================
  UI.v5_section_label("ENDPOINT")

  _push_cllm_card()
  if ImGui.ImGui_BeginChild(RA.ctx, "##cllm_endpoint_card", inner_w, 0,
      ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
    local card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

    -- Name input (required, full card width). Drives the provider label in
    -- the main model picker and every on-disk reference, so it's placed
    -- first -- users who open this card to add a provider should see "what
    -- am I naming?" before they start wiring up URLs.
    _field_label("Name")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, card_w)
    local _, new_label = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_label",
      "e.g. Ollama Local, DeepSeek, OpenRouter",
      edit.label)
    UI.focus_ring()
    _, new_label = UI.input_with_menu(RA.ctx, false, new_label)
    _pop_input_style()
    edit.label = new_label
    UI.tooltip(
      "The friendly name shown in ReaAssist's provider dropdown and in the "
      .. "Custom Providers list on this page. This is purely cosmetic; "
      .. "rename it any time without affecting the saved endpoint, models, "
      .. "or API key. Required.\n\n"
      .. "Tip: if you have several endpoints for the same service, include "
      .. "the variant in the name (e.g. 'Ollama - Llama 70B', "
      .. "'OpenRouter - Free Tier').")
    _inline_msg(edit.errors.label, TK.red)

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Endpoint URL input (full card width, mono text well).
    _field_label("Endpoint URL")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, card_w)
    local _, new_endpoint = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_endpoint",
      "http://localhost:11434/v1/chat/completions",
      edit.endpoint)
    UI.focus_ring()
    _, new_endpoint = UI.input_with_menu(RA.ctx, false, new_endpoint)
    _pop_input_style()
    edit.endpoint = new_endpoint
    UI.tooltip(
      "The full URL of the chat completions endpoint, including http:// or "
      .. "https:// and the port.\n\n"
      .. "Expected shape for OpenAI-compatible servers:\n"
      .. "  http://localhost:11434/v1/chat/completions   (Ollama)\n"
      .. "  http://localhost:1234/v1/chat/completions    (LM Studio)\n"
      .. "  http://localhost:8080/v1/chat/completions    (llama.cpp)\n"
      .. "  https://openrouter.ai/api/v1/chat/completions (OpenRouter)\n\n"
      .. "Use the preset pills below to fill in the common defaults.")
    _inline_msg(edit.errors.endpoint, TK.red)
    if edit.endpoint
       and edit.endpoint:match("^http://")
       and not edit.endpoint:match("^http://localhost[:/]")
       and not edit.endpoint:match("^http://127%.0%.0%.1[:/]") then
      _inline_msg("Unencrypted connection. Credentials sent in plain text.", TK.amber)
    end

    -- Preset pills: two labeled rows (LOCAL / HOSTED). Clicking a preset
    -- just fills the URL; hosted gateways still need an API key pasted
    -- below. One pill-button style is pushed around the whole block so
    -- both rows share identical chrome.
    Dummy(RA.ctx, 1, RA.SC(6))
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))

    -- Shared row-label font (mono SC(9), TK.text_faint) so "LOCAL" and
    -- "HOSTED" read as quiet group markers, not as primary content. A
    -- fixed label column width keeps both rows' pills left-aligned to
    -- the same x so the presets form a tidy grid.
    local PRESET_LBL_W = RA.SC(54)
    local function _preset_label(txt)
      PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
      Text(RA.ctx, txt)
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    end
    local function _preset_btn(label, id, url, tip)
      if ImGui.ImGui_Button(RA.ctx, label .. "##cus_ep_" .. id) then
        edit.endpoint        = url
        edit.errors.endpoint = nil
      end
      UI.tooltip(tip)
    end

    -- LOCAL row: three most common self-hosted servers.
    local row_start_x = GetCursorPosX(RA.ctx)
    _preset_label("LOCAL")
    SameLine(RA.ctx, row_start_x + PRESET_LBL_W)
    _preset_btn("Ollama", "ollama",
      "http://localhost:11434/v1/chat/completions",
      "Fill in the default Ollama endpoint URL")
    SameLine(RA.ctx, 0, RA.SC(6))
    _preset_btn("LM Studio", "lmstudio",
      "http://localhost:1234/v1/chat/completions",
      "Fill in the default LM Studio endpoint URL")
    SameLine(RA.ctx, 0, RA.SC(6))
    _preset_btn("llama.cpp", "llamacpp",
      "http://localhost:8080/v1/chat/completions",
      "Fill in the default llama.cpp server endpoint URL")

    Dummy(RA.ctx, 1, RA.SC(4))

    -- HOSTED row: OpenAI-compatible cloud gateways. The first three pills
    -- only fill the URL (matching the LOCAL-row convention). The Kimi pill
    -- is opinionated: it also fills the provider label, seeds a kimi-k2.6
    -- model row (prices, context, thinking-disabled extra body) if the
    -- models list is still empty / default, and never overwrites values the
    -- user has already typed.
    _preset_label("HOSTED")
    SameLine(RA.ctx, row_start_x + PRESET_LBL_W)
    _preset_btn("OpenRouter", "openrouter",
      "https://openrouter.ai/api/v1/chat/completions",
      "Fill in the OpenRouter endpoint URL (API key required)")
    SameLine(RA.ctx, 0, RA.SC(6))
    _preset_btn("Groq", "groq",
      "https://api.groq.com/openai/v1/chat/completions",
      "Fill in the Groq endpoint URL (API key required)")
    SameLine(RA.ctx, 0, RA.SC(6))
    _preset_btn("DeepSeek", "deepseek",
      "https://api.deepseek.com/v1/chat/completions",
      "Fill in the DeepSeek endpoint URL (API key required)")
    SameLine(RA.ctx, 0, RA.SC(6))
    -- Kimi (Moonshot): opinionated fill. The models list is considered
    -- "default / empty" when it has exactly one row that still matches
    -- the shape enter_custom_new() seeds (blank id, "0" prices, default
    -- context window, blank notes / extra_body). Only in that case do we
    -- replace it with a fully-configured kimi-k2.6 row -- if the user
    -- has typed ANY field on row 1 (id, prices, context, notes, extra
    -- body), we fill URL + label and leave the row alone. Without the
    -- broader check, a user who typed prices or a context window but
    -- not the id yet would lose those values just by clicking Kimi.
    if ImGui.ImGui_Button(RA.ctx, "Kimi##cus_ep_kimi") then
      edit.endpoint        = "https://api.moonshot.ai/v1/chat/completions"
      edit.errors.endpoint = nil
      if (edit.label or ""):match("^%s*$") then
        edit.label = "Kimi"
      end
      local m0 = edit.models[1]
      local models_are_default = #edit.models == 1
        and (m0.id or "")             == ""
        and (m0.price_in or "")       == "0"
        and (m0.price_cache_r or "")  == "0"
        and (m0.price_out or "")      == "0"
        and (m0.context_window or "") == tostring(CUSTOM_DEFAULT_CTX)
        and (m0.notes or "")          == ""
        and (m0.extra_body or "")     == ""
      if models_are_default then
        edit.models[1] = {
          id             = "kimi-k2.6",
          price_in       = "0.95",    -- cache-miss input
          price_cache_r  = "0.16",    -- cache-hit input
          price_out      = "4",
          context_window = "262144",
          notes          = "",
          -- Disable server-side reasoning by default. Kimi k2.6 runs a
          -- reasoning pass otherwise, which can add tens of seconds of
          -- latency and thousands of hidden output tokens on simple
          -- scripting tasks. Flip the body to {"thinking":{"type":"enabled"}}
          -- (or blank it out) for research-style work.
          extra_body     = '{"thinking":{"type":"disabled"}}',
        }
      end
    end
    UI.tooltip(
      "Fill in Kimi (Moonshot) defaults:\n"
      .. "  - Endpoint: https://api.moonshot.ai/v1/chat/completions\n"
      .. "  - Provider name: Kimi (if blank)\n"
      .. "  - Model row: kimi-k2.6, 262k context, $0.95/$0.16/$4.00 per 1M\n"
      .. "  - Extra Body: {\"thinking\":{\"type\":\"disabled\"}}\n\n"
      .. "Thinking is disabled by default because k2.6's reasoning pass "
      .. "adds tens of seconds of latency and thousands of hidden output "
      .. "tokens on simple tasks. Open the model row's Details popup to "
      .. "re-enable it (set the Extra Body to "
      .. "{\"thinking\":{\"type\":\"enabled\"}} or blank) when you need "
      .. "deeper reasoning.\n\n"
      .. "API key required. If you've already customized the default model "
      .. "row, only the URL and provider name are filled.")

    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)

    -- API Key (merged into ENDPOINT section). Optional for local servers;
    -- required for hosted OpenAI-compatible gateways (OpenRouter, Groq, etc).
    Dummy(RA.ctx, 1, RA.SC(10))
    _field_label("API Key", "(optional, required for hosted gateways)")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, card_w)
    local _, new_custom_key = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_key",
      "Paste API key...",
      edit.key,
      ImGui.ImGui_InputTextFlags_Password())
    UI.focus_ring()
    _, new_custom_key = UI.input_with_menu(RA.ctx, false, new_custom_key)
    _pop_input_style()
    edit.key = new_custom_key
    UI.tooltip(
      "The bearer token sent as 'Authorization: Bearer <key>' on every "
      .. "request.\n\n"
      .. "REQUIRED for hosted gateways: OpenRouter (sk-or-...), Groq "
      .. "(gsk_...), DeepSeek (sk-...), Together AI, Mistral, Fireworks, "
      .. "Anyscale, Cloudflare AI Gateway, etc.\n\n"
      .. "LEAVE BLANK for local servers (Ollama, LM Studio, llama.cpp, "
      .. "vLLM) that don't require auth. The Authorization header is "
      .. "omitted entirely in that case; some local servers reject a "
      .. "bare 'Bearer ' header, so empty really does mean empty.\n\n"
      .. "The key is stored XOR-obfuscated and tied to this REAPER "
      .. "install path; copying the .ini to another machine won't work.")
    _inline_msg(edit.errors.key, TK.red)

    ImGui.ImGui_EndChild(RA.ctx)
  end
  _pop_cllm_card()

  Dummy(RA.ctx, 1, RA.SC(12))

  -- ============================================================
  -- MODELS section: list of [identifier][Details][remove] rows. Prices,
  -- context, extra_body, and the dropdown-notes tag live in a per-row
  -- Details popup so the row stays clean at any number of configured models.
  -- ============================================================
  UI.v5_section_label("MODELS")

  -- Subtitle: quiet hint about what the row does and where the rest lives.
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
  Text(RA.ctx, "One row per model. Open Details to set prices, context, notes, and extra body JSON.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(4))

  _push_cllm_card()
  if ImGui.ImGui_BeginChild(RA.ctx, "##cllm_models_card", inner_w, 0,
      ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
    -- Column metrics: identifier and notes split the input zone; the three
    -- trailing icon buttons (gear/duplicate/remove) are equal-width squares.
    -- card_w is the inner width exposed by the card's content region, so
    -- the row fills regardless of padding.
    local RM_W      = RA.SC(22)
    local DET_W     = RA.SC(22)   -- gear icon (per-row Details popup)
    local DUP_W     = RA.SC(22)   -- duplicate icon (clones this row)
    local ICON_SZ   = RA.SC(15)   -- glyph size inside the 22-px icon buttons
    local row_gap   = RA.SC(4)
    local card_w    = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    -- 4 gaps between 5 widgets: [id][notes][dup][det][rm].
    local fixed_w   = DUP_W + DET_W + RM_W + row_gap * 4
    local inputs_w  = card_w - fixed_w
    local id_w      = math_floor(inputs_w * 0.62)
    local notes_w   = inputs_w - id_w

    -- Two-column mono small-caps column header. NOTES sits over the second
    -- input by absolute cursor X so it stays aligned regardless of the
    -- "MODEL IDENTIFIER" label width.
    PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
    local hdr_x0 = ImGui.ImGui_GetCursorPosX(RA.ctx)
    Text(RA.ctx, "MODEL IDENTIFIER")
    UI.tooltip("The model name as your server expects it (e.g. qwen2.5-coder-14b, "
      .. "kimi-k2.6, claude-opus-4-7). Open Details to set prices, context, "
      .. "the same notes tag shown next to it, and extra JSON body fields.")
    SameLine(RA.ctx, 0, 0)
    ImGui.ImGui_SetCursorPosX(RA.ctx, hdr_x0 + id_w + row_gap)
    Text(RA.ctx, "NOTES")
    UI.tooltip("Optional short tag appended to the model id in the main-screen "
      .. "model dropdown, so rows that share an id but differ in tuning "
      .. "(thinking on/off, temperature, etc.) are distinguishable at a glance.")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(2))

    _push_input_style()

    -- Row buttons share the input frame height so the gear / duplicate /
    -- trash glyphs sit on the same baseline as the inputs. Captured AFTER
    -- _push_input_style so it reflects the same FramePadding the inputs use,
    -- and BEFORE pushing FONT.lucide (which would otherwise change the
    -- line-height term in GetFrameHeight).
    local btn_h = ImGui.ImGui_GetFrameHeight(RA.ctx)

    -- Renders one of the three trailing icon buttons (gear/duplicate/trash)
    -- as a "ghost" affordance: transparent at rest, quiet card_hover tint on
    -- hover, slightly stronger on press, no border. The icon glyph alone is
    -- the visible UI when idle; the hover state confirms it's clickable.
    --
    -- FramePadding override (SC(2) x SC(2)) keeps the SC(15) lucide glyph
    -- inside the content rect so ButtonTextAlign(0.5, 0.5) centers it
    -- symmetrically; the inherited input style's SC(8) x SC(5) padding would
    -- otherwise shrink the content rect below the glyph width and trip
    -- ImGui's clamp-to-content-min path. btn_h stays equal to the input
    -- frame height so the click target still aligns with the input baseline.
    local function _icon_btn(label, w)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
        UI.lerp_u32(TK.card_hover, TK.text, 0.15))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),
        RA.SC(2), RA.SC(2))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
      PushFont(RA.ctx, FONT.lucide, ICON_SZ)
      local clicked = ImGui.ImGui_Button(RA.ctx, label, w, btn_h)
      PopFont(RA.ctx)
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopStyleColor(RA.ctx, 3)
      return clicked
    end

    -- Parse a parameter-count B-number out of a free-form model identifier.
    -- Returns the number (e.g. 7, 14, 32, 235) or nil if no plausible
    -- "<n>B" token is found. Used to surface the inline size advisory under
    -- the model row when the user types something like "qwen2.5-coder:7b" or
    -- a GGUF filename that includes the param count, so we can warn that
    -- ~7B is below the practical floor for ReaAssist's REAPER tasks.
    --
    -- Trailing-boundary check (next char must NOT be alphanumeric) avoids
    -- false positives on tokens like "7bee" or "7b1234" (a hash); leading
    -- side is naturally bounded by the digit class. Names without a B-token
    -- (gpt-4o, claude-sonnet-4-6, deepseek-v3, "model") return nil and the
    -- prose advisory above remains the safety net.
    local function _detect_param_b(s)
      if not s or s == "" then return nil end
      s = s:lower()
      local pos = 1
      while pos <= #s do
        local b_start, b_end, num = s:find("(%d+%.?%d*)b", pos)
        if not b_start then return nil end
        local next_ch = s:sub(b_end + 1, b_end + 1)
        if next_ch == "" or not next_ch:match("[%w]") then
          return tonumber(num)
        end
        pos = b_end + 1
      end
      return nil
    end

    local row_to_remove    = nil
    local row_to_duplicate = nil
    local open_details_ri  = nil  -- Deferred OpenPopup: ImGui requires the call
                                  -- to sit OUTSIDE the input-style push/pop
                                  -- pair to avoid style leakage into the popup.
    for ri, row in ipairs(edit.models) do
      -- Column 1: model identifier.
      ImGui.ImGui_SetNextItemWidth(RA.ctx, id_w)
      local _, new_id = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_mid_" .. ri,
        "qwen2.5-coder-14b", row.id)
      UI.focus_ring()
      _, new_id = UI.input_with_menu(RA.ctx, false, new_id)
      row.id = new_id

      SameLine(RA.ctx, 0, row_gap)

      -- Column 2: dropdown-notes tag (lives on the row so a duplicated
      -- template can be retagged in one keystroke). The 20-char cap and
      -- format rules are enforced by Custom.validate_notes on Save.
      ImGui.ImGui_SetNextItemWidth(RA.ctx, notes_w)
      local _, new_notes = ImGui.ImGui_InputTextWithHint(RA.ctx,
        "##cus_dnotes_" .. ri, "thinking, fast...", row.notes or "")
      UI.focus_ring()
      _, new_notes = UI.input_with_menu(RA.ctx, false, new_notes)
      row.notes = new_notes
      UI.tooltip(
        "Short free-text label appended to the model id in the main-screen "
        .. "model dropdown so rows that share a model id but differ in "
        .. "tuning are distinguishable at a glance.\n\n"
        .. "Examples: thinking, fast, creative, deterministic, long-ctx.\n\n"
        .. str_format("Max %d characters. No pipes (|), tabs, or newlines.",
          Custom.MAX_NOTES_LEN))

      SameLine(RA.ctx, 0, row_gap)

      -- Details (gear), Duplicate, and Trash share the same chrome: a square
      -- icon button matching the input frame height. Text alignment is the
      -- ImGui default (0.5, 0.5) for these buttons and the lucide font is
      -- pushed only around each button so the surrounding input-style font
      -- stays in scope for the inputs.
      local cache_n = tonumber(row.price_cache_r or "0") or 0

      if _icon_btn(ICON.SETTINGS .. "##cus_det_" .. ri, DET_W) then
        open_details_ri = ri
      end
      -- Tooltip summarizes what's in the popup right now. Kept short so the
      -- tooltip doesn't scroll; truncates extra_body beyond ~120 chars.
      local tip_lines = {
        "Details - prices, context, notes, extra body JSON",
        str_format("$%s in / $%s cached / $%s out per 1M tokens",
          row.price_in or "0", row.price_cache_r or "0", row.price_out or "0"),
        str_format("Context: %s tokens", row.context_window or "?"),
      }
      if (row.notes or "") ~= "" then
        tip_lines[#tip_lines+1] = "Dropdown notes: " .. row.notes
      end
      if cache_n > 0 then
        tip_lines[#tip_lines+1] = str_format("Cache-hit price: $%s",
          row.price_cache_r or "0")
      end
      if (row.extra_body or "") ~= "" then
        local eb = row.extra_body
        if #eb > 120 then eb = eb:sub(1, 117) .. "..." end
        tip_lines[#tip_lines+1] = "Extra body: " .. eb
      else
        tip_lines[#tip_lines+1] = "Extra body: (none)"
      end
      UI.tooltip(tbl_concat(tip_lines, "\n"))

      SameLine(RA.ctx, 0, row_gap)

      -- Duplicate: clones this row directly below as a template, so the user
      -- can tweak one field (e.g. flip a thinking flag in extra_body) without
      -- retyping the rest. Disabled during an active connection test for
      -- the same reason as the remove button.
      do
        local test_active = api_keys.custom_conn_test and api_keys.custom_conn_test.active
        ImGui.ImGui_BeginDisabled(RA.ctx, test_active)
        if _icon_btn(ICON.COPY_PLUS .. "##cus_mdup_" .. ri, DUP_W) then
          row_to_duplicate = ri
        end
        UI.tooltip("Duplicate this model row")
        ImGui.ImGui_EndDisabled(RA.ctx)
      end

      SameLine(RA.ctx, 0, row_gap)

      if #edit.models > 1 then
        -- Row-remove (trash icon): disabled during an active connection test
        -- so the in-flight request's target model can't vanish mid-call.
        local test_active = api_keys.custom_conn_test and api_keys.custom_conn_test.active
        ImGui.ImGui_BeginDisabled(RA.ctx, test_active)
        if _icon_btn(ICON.TRASH .. "##cus_mrm_" .. ri, RM_W) then
          row_to_remove = ri
        end
        UI.tooltip("Remove this model row")
        ImGui.ImGui_EndDisabled(RA.ctx)
      else
        Dummy(RA.ctx, RM_W, 1)
      end

      _inline_msg(edit.errors["model_notes_" .. ri], TK.red)
      _inline_msg(edit.errors["model_" .. ri],       TK.red)
      -- Soft size advisory: parses a B-number from row.id and flags anything
      -- under ~14B as likely too small. Muted-amber color (matching the
      -- Experimental advisory at the top of the page) so it reads as a
      -- caution, not a hard error. Names without a parseable size produce
      -- nothing -- the page-level prose advisory still covers those.
      do
        local b = _detect_param_b(row.id)
        if b and b < 14 then
          _inline_msg(str_format(
            "~%gB detected - usually too small for reliable REAPER output.", b),
            UI.lerp_u32(TK.amber, TK.text_muted, 0.5))
        end
      end
    end
    if row_to_remove then
      tbl_remove(edit.models, row_to_remove)
    end
    if row_to_duplicate then
      local src = edit.models[row_to_duplicate]
      table.insert(edit.models, row_to_duplicate + 1, {
        id             = src.id,
        price_in       = src.price_in,
        price_cache_r  = src.price_cache_r,
        price_out      = src.price_out,
        context_window = src.context_window,
        notes          = src.notes,
        extra_body     = src.extra_body,
      })
    end

    _pop_input_style()

    -- Open the per-row Details popup AFTER the row loop and after the input
    -- style is popped, so the popup renders with the window's default style.
    -- Each row owns its own popup id; the same api_keys.custom_edit.models[ri]
    -- buffer is edited live, so the outer Save commits everything atomically.
    --
    -- BeginPopupModal (not BeginPopup) for this dialog: the user often needs
    -- to switch tabs or another app to copy an extra-body JSON snippet out
    -- of docs, and a non-modal popup dismisses on focus loss. Modal keeps
    -- the dialog open until they hit Done (or Esc). Centered on the main
    -- ReaAssist window via the geometry captured at end of frame.
    if open_details_ri then
      ImGui.ImGui_OpenPopup(RA.ctx, "Model Details##cus_details_popup_" .. open_details_ri)
    end
    for ri, row in ipairs(edit.models) do
      local popup_id = "Model Details##cus_details_popup_" .. ri
      local pw, ph = RA.SC(460), RA.SC(600)
      if update._main_w then
        ImGui.ImGui_SetNextWindowPos(RA.ctx,
          update._main_x + (update._main_w - pw) * 0.5,
          update._main_y + (update._main_h - ph) * 0.5,
          ImGui.ImGui_Cond_Appearing())
      end
      ImGui.ImGui_SetNextWindowSize(RA.ctx, pw, ph, ImGui.ImGui_Cond_Appearing())
      UI.push_modal_style()
      if ImGui.ImGui_BeginPopupModal(RA.ctx, popup_id, true,
          ImGui.ImGui_WindowFlags_NoResize()) then
        -- Subtitle: mono-small model id so the user can see which row this
        -- dialog belongs to. The popup's window title carries the generic
        -- "Model Details" label.
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
        Text(RA.ctx, (row.id ~= "" and row.id) or "(unnamed model)")
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        Dummy(RA.ctx, 1, RA.SC(8))

        local fw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

        -- Dropdown Notes: same field as the inline row input -- both bind to
        -- row.notes, so an edit here surfaces in the row immediately and
        -- vice versa. The row carries the inline validator error, so the
        -- popup omits the redundant error display.
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        Text(RA.ctx, "Dropdown Notes")
        PopFont(RA.ctx)
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        Text(RA.ctx, str_format("(optional, max %d chars)", Custom.MAX_NOTES_LEN))
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        _push_input_style()
        ImGui.ImGui_SetNextItemWidth(RA.ctx, fw)
        local _, popup_notes = ImGui.ImGui_InputTextWithHint(RA.ctx,
          "##cus_dnotes_pop_" .. ri, "thinking, fast, creative...",
          row.notes or "")
        UI.focus_ring()
        _, popup_notes = UI.input_with_menu(RA.ctx, false, popup_notes)
        _pop_input_style()
        row.notes = popup_notes
        UI.tooltip(
          "Short free-text label appended to the model id in the main-screen "
          .. "model dropdown so rows that share a model id but differ in "
          .. "tuning are distinguishable at a glance.\n\n"
          .. "Examples: thinking, fast, creative, deterministic, long-ctx.\n\n"
          .. str_format("Max %d characters. No pipes (|), tabs, or newlines.",
            Custom.MAX_NOTES_LEN)
          .. "\n\n"
          .. "Mirrors the Notes input on the row -- editing either updates the "
          .. "other.")

        Dummy(RA.ctx, 1, RA.SC(10))

        -- Prices: three rows of single-line numeric inputs. Stacked (not in
        -- columns) because the popup is narrow enough that side-by-side
        -- price inputs would get cramped; stacking also matches the vertical
        -- reading order of the cache-miss / cache-hit / output progression.
        local function _price_field(field, lbl, hint, tip)
          PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
          Text(RA.ctx, lbl)
          PopFont(RA.ctx)
          _push_input_style()
          ImGui.ImGui_SetNextItemWidth(RA.ctx, fw)
          local _, new = ImGui.ImGui_InputTextWithHint(RA.ctx,
            "##cus_" .. field .. "_" .. ri, hint, row[field] or "")
          UI.focus_ring()
          _, new = UI.input_with_menu(RA.ctx, false, new)
          _pop_input_style()
          row[field] = new
          UI.tooltip(tip)
        end

        _price_field("price_in",
          "Input Price per 1M (Cache Miss)",
          "0",
          "Cost per million input tokens for fresh (non-cached) prompt "
          .. "content. Used for cost estimates only; the script does not "
          .. "bill you.")
        Dummy(RA.ctx, 1, RA.SC(6))
        _price_field("price_cache_r",
          "Input Price per 1M (Cache Hit)",
          "0",
          "Cost per million input tokens that the provider served from its "
          .. "automatic prompt cache (reported as "
          .. "usage.prompt_tokens_details.cached_tokens). Common providers "
          .. "and their published cache-hit rates: OpenAI ~10% of input, "
          .. "Kimi ~17% ($0.16 vs $0.95). Leave at 0 for endpoints without "
          .. "caching or unknown rates; cached tokens will then be billed "
          .. "at $0 in the cost estimate.")
        _inline_msg(edit.errors["model_cache_" .. ri], TK.red)
        Dummy(RA.ctx, 1, RA.SC(6))
        _price_field("price_out",
          "Output Price per 1M",
          "0",
          "Cost per million output tokens. For reasoning models this "
          .. "usually includes hidden thinking tokens as part of the "
          .. "completion, so a long thinking pass charges at the output "
          .. "rate even when the visible reply is short.")
        Dummy(RA.ctx, 1, RA.SC(10))

        -- Context window
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        Text(RA.ctx, "Context Window (tokens)")
        PopFont(RA.ctx)
        _push_input_style()
        ImGui.ImGui_SetNextItemWidth(RA.ctx, fw)
        local _, new_ctxw = ImGui.ImGui_InputTextWithHint(RA.ctx,
          "##cus_dctx_" .. ri, tostring(CUSTOM_DEFAULT_CTX),
          row.context_window or "")
        UI.focus_ring()
        _, new_ctxw = UI.input_with_menu(RA.ctx, false, new_ctxw)
        _pop_input_style()
        row.context_window = new_ctxw
        UI.tooltip("Maximum combined input + output token capacity for this "
          .. "model. The preflight check warns if a pending send would "
          .. "overflow this window. Kimi k2.6 = 262144, Claude Opus 4.7 = "
          .. "1000000, most local 8B models = 8192.")

        Dummy(RA.ctx, 1, RA.SC(10))

        -- Extra Body JSON
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        Text(RA.ctx, "Extra Body JSON")
        PopFont(RA.ctx)
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        Text(RA.ctx, "(optional, merged into the chat-completions request body)")
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        _push_input_style()
        local eb_h = RA.SC(96)
        local _, new_eb = ImGui.ImGui_InputTextMultiline(RA.ctx,
          "##cus_deb_" .. ri, row.extra_body or "", fw, eb_h)
        UI.focus_ring()
        _, new_eb = UI.input_with_menu(RA.ctx, false, new_eb)
        _pop_input_style()
        row.extra_body = new_eb
        UI.tooltip(
          "A JSON object merged into the outgoing chat-completions body. "
          .. "Overrides any same-named keys set in the provider-level "
          .. "Extra Body field. Use for vendor-specific knobs that don't "
          .. "map to the OpenAI schema.\n\n"
          .. "Examples:\n"
          .. "  Kimi, GLM:        {\"thinking\":{\"type\":\"disabled\"}}\n"
          .. "  Qwen3:            {\"enable_thinking\":false}\n"
          .. "  OpenRouter:       {\"reasoning\":{\"effort\":\"high\"}}\n"
          .. "  LiteLLM-Anthropic: {\"thinking\":{\"type\":\"enabled\","
          .. "\"budget_tokens\":1024}}\n"
          .. "  Any OpenAI-compat: {\"temperature\":0.3,\"top_p\":0.9}\n\n"
          .. "Must be a valid JSON object (wrapped in {...}), not an array "
          .. "or scalar. Validated on Save.")
        _inline_msg(edit.errors["model_body_" .. ri], TK.red)

        Dummy(RA.ctx, 1, RA.SC(12))

        -- Done closes the popup. Live-edits above have already written to
        -- the row buffer, so there's nothing to commit here; the outer
        -- Save button persists the whole record. Esc also closes via the
        -- modal's standard key handling.
        if ImGui.ImGui_Button(RA.ctx, "Done##cus_det_close_" .. ri,
            fw, RA.SC(26)) then
          ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        end
        if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
          ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        end
        ImGui.ImGui_EndPopup(RA.ctx)
      end
      UI.pop_modal_style()
    end

    Dummy(RA.ctx, 1, RA.SC(6))

    -- "+ Add Model" compact secondary pill, left-aligned (not full width --
    -- a narrow button reads as "add one more" rather than as a primary CTA).
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(4))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
    if ImGui.ImGui_Button(RA.ctx, "+  Add Model##cus_madd") then
      edit.models[#edit.models+1] = {
        id = "", price_in = "0", price_cache_r = "0", price_out = "0",
        context_window = tostring(CUSTOM_DEFAULT_CTX),
        notes = "", extra_body = "",
      }
    end
    UI.tooltip("Add another model row for this endpoint")
    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)

    _inline_msg(edit.errors.model_id, TK.red)

    ImGui.ImGui_EndChild(RA.ctx)
  end
  _pop_cllm_card()

  Dummy(RA.ctx, 1, RA.SC(12))

  -- ============================================================
  -- ADVANCED section: request timeout, connect timeout, TLS toggle,
  -- model prefix, custom headers. Every field here is optional -- a
  -- brand-new record saves fine with all of these left at defaults.
  -- (Name lives in ENDPOINT.)
  -- ============================================================
  UI.v5_section_label("ADVANCED")

  _push_cllm_card()
  if ImGui.ImGui_BeginChild(RA.ctx, "##cllm_adv_card", inner_w, 0,
      ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
    local adv_card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

    -- Request timeout (narrow numeric field).
    _field_label("Request Timeout", "(seconds)")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, RA.SC(140))
    local _, new_timeout = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_timeout",
      tostring(CUSTOM_DEFAULT_TIMEOUT), edit.timeout)
    UI.focus_ring()
    _, new_timeout = UI.input_with_menu(RA.ctx, false, new_timeout)
    _pop_input_style()
    edit.timeout = new_timeout
    UI.tooltip(
      "The total time allowed for a request once the connection is "
      .. "established, in seconds. Passed to curl as --max-time.\n\n"
      .. "Cloud endpoints usually reply in 2-15s. Local LLMs can take "
      .. "MINUTES on a single prompt because the whole context has to "
      .. "be re-processed each turn on consumer hardware; default "
      .. "600 (10 min) is a comfortable ceiling for most setups.\n\n"
      .. "Range: 10-3600 seconds (1 hour max). If your server replies "
      .. "correctly but ReaAssist gives up too early, raise this.")
    _inline_msg(edit.errors.timeout, TK.red)

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Connect timeout (narrow numeric field, next to request timeout in
    -- intent but laid out below so both inline errors have room). Applies
    -- only to the TCP/TLS handshake; once connected, Request Timeout takes
    -- over as the per-request ceiling.
    _field_label("Connect Timeout", "(seconds)")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, RA.SC(140))
    local _, new_ctimeout = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_ctimeout",
      tostring(Custom.DEFAULT_CONNECT), edit.connect_timeout)
    UI.focus_ring()
    _, new_ctimeout = UI.input_with_menu(RA.ctx, false, new_ctimeout)
    _pop_input_style()
    edit.connect_timeout = new_ctimeout
    UI.tooltip(
      "The time allowed for the initial TCP connection and (for https) "
      .. "the TLS handshake, in seconds. Passed to curl as "
      .. "--connect-timeout.\n\n"
      .. "Independent of Request Timeout: once the connection is up, "
      .. "the overall request timeout takes over. A short connect "
      .. "timeout fails fast when the server is unreachable or the port "
      .. "is wrong, instead of waiting the full Request Timeout.\n\n"
      .. "Range: 1-60 seconds. Default 10 is fine for localhost and "
      .. "most cloud gateways; raise it for slow CDNs or congested "
      .. "networks.")
    _inline_msg(edit.errors.connect_timeout, TK.red)

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Model ID prefix (full-width text). Most users never need this; the
    -- muted hint text explains when they would. Prepended to every model
    -- id we send (not shown in the UI model-row inputs) so the dropdown
    -- stays clean and the prefix lives in exactly one place.
    _field_label("Model ID Prefix", "(optional)")
    _push_input_style()
    ImGui.ImGui_SetNextItemWidth(RA.ctx, adv_card_w)
    local _, new_prefix = ImGui.ImGui_InputTextWithHint(RA.ctx, "##cus_model_prefix",
      "e.g. openrouter/anthropic/   or   ollama/",
      edit.model_prefix)
    UI.focus_ring()
    _, new_prefix = UI.input_with_menu(RA.ctx, false, new_prefix)
    _pop_input_style()
    edit.model_prefix = new_prefix
    UI.tooltip(
      "A string prepended to every model id just before the request is "
      .. "sent. The dropdown in ReaAssist shows the un-prefixed id, so "
      .. "the prefix lives in exactly one place instead of being typed "
      .. "into every model row.\n\n"
      .. "When to use this:\n"
      .. "  - OpenRouter routes via provider/model, e.g. "
      .. "'anthropic/claude-3.5-sonnet'. Set prefix to 'anthropic/' and "
      .. "enter 'claude-3.5-sonnet' in the model row.\n"
      .. "  - LiteLLM gateways use 'ollama/<model>' or 'openrouter/...' "
      .. "to choose the backend.\n"
      .. "  - Cloudflare Workers AI uses '@cf/<org>/<model>'.\n\n"
      .. "Leave blank if your endpoint takes the raw model id. Most "
      .. "setups (Ollama, LM Studio, llama.cpp, direct OpenAI API) "
      .. "do not need a prefix.")

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Custom request headers (multi-line text well, one header per line).
    -- Each non-blank line must match "Name: value" and must not contain
    -- triple-quotes / newlines (the save-time validator enforces both).
    _field_label("Extra HTTP Headers", "(one \"Name: value\" per line)")
    _push_input_style()
    local headers_h = RA.SC(72)  -- ~4 rows at SC(10) mono; scrolls if longer
    local _, new_headers = ImGui.ImGui_InputTextMultiline(RA.ctx, "##cus_headers",
      edit.headers_text or "", adv_card_w, headers_h)
    UI.focus_ring()
    _, new_headers = UI.input_with_menu(RA.ctx, false, new_headers)
    _pop_input_style()
    edit.headers_text = new_headers
    UI.tooltip(
      "Additional HTTP headers sent on every request to this provider. "
      .. "Enter one per line in 'Name: value' format.\n\n"
      .. "Examples:\n"
      .. "  OpenAI-Organization: org-abc123\n"
      .. "  HTTP-Referer: https://my-app.example\n"
      .. "  X-Title: ReaAssist\n"
      .. "  cf-aig-authorization: Bearer <cf-token>\n"
      .. "  api-key: <azure-key>\n\n"
      .. "Do NOT set Authorization here; use the API Key field "
      .. "above. ReaAssist builds the Authorization header itself so "
      .. "your key stays off the command line.\n\n"
      .. "Characters not allowed inside a value: newlines, null bytes, "
      .. "and the triple-quote sequence \"\"\" (these would break the "
      .. "Windows curl command line).")
    _inline_msg(edit.errors.headers, TK.red)

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Provider-level Extra Body JSON. Merged into every chat-completions
    -- request on this endpoint. Per-model extra_body (in the Details popup)
    -- overrides same-named keys here on a per-request basis. Validated as
    -- a JSON object at save time (Custom.validate_extra_body).
    _field_label("Extra Body JSON", "(optional, applies to every request)")
    _push_input_style()
    local body_h = RA.SC(72)
    local _, new_body = ImGui.ImGui_InputTextMultiline(RA.ctx, "##cus_body",
      edit.extra_body or "", adv_card_w, body_h)
    UI.focus_ring()
    _, new_body = UI.input_with_menu(RA.ctx, false, new_body)
    _pop_input_style()
    edit.extra_body = new_body
    UI.tooltip(
      "A JSON object merged into every chat-completions request body on "
      .. "this provider, on top of the standard OpenAI-compatible payload "
      .. "(model, messages, max_completion_tokens).\n\n"
      .. "Use this for vendor-specific toggles that don't map to the OpenAI "
      .. "schema. Per-model Extra Body JSON (in each model row's Details "
      .. "popup) overrides same-named keys here.\n\n"
      .. "Examples:\n"
      .. "  Kimi / GLM (disable reasoning):\n"
      .. "    {\"thinking\":{\"type\":\"disabled\"}}\n"
      .. "  Qwen3 (disable thinking):\n"
      .. "    {\"enable_thinking\":false}\n"
      .. "  OpenRouter (high reasoning effort):\n"
      .. "    {\"reasoning\":{\"effort\":\"high\"}}\n"
      .. "  LiteLLM proxy to Anthropic (budget-limited thinking):\n"
      .. "    {\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":1024}}\n"
      .. "  Any OpenAI-compat (sampling tweaks):\n"
      .. "    {\"temperature\":0.3,\"top_p\":0.9}\n\n"
      .. "Must be a valid JSON OBJECT wrapped in {...}, not an array or "
      .. "scalar. Validated and canonicalized on Save.")
    _inline_msg(edit.errors.extra_body, TK.red)

    Dummy(RA.ctx, 1, RA.SC(10))

    -- Skip TLS verification: V5 toggle-row style, matching the Preferences
    -- toggles on the Settings screen. Only meaningful for https:// URLs
    -- (http:// has no TLS layer to skip), so we hide the row entirely when
    -- the endpoint is plain http -- less noise for the common local-LLM
    -- case and no chance of the user enabling a flag that has no effect.
    if (edit.endpoint or ""):match("^https://") then
      local _, new_insecure = UI.v5_toggle(
        "##cus_insecure",
        "Skip TLS Verification",
        edit.allow_insecure,
        "Adds curl --insecure, which skips the certificate-validity check "
        .. "for https:// endpoints. Only useful when the server presents "
        .. "a self-signed, expired, or otherwise un-trusted certificate "
        .. "and you know the endpoint is yours.\n\n"
        .. "Typical legit uses:\n"
        .. "  - Local LLM behind a homelab reverse-proxy with a self-"
        .. "signed cert.\n"
        .. "  - Corporate MITM gateway re-signing traffic with an "
        .. "internal CA you haven't installed.\n"
        .. "  - Dev/staging endpoint with an expired cert.\n\n"
        .. "Never enable for a public hosted gateway (OpenRouter, Groq, "
        .. "DeepSeek, etc.). If their cert stops validating, something "
        .. "is genuinely wrong and bypassing verification exposes your "
        .. "API key to any machine on the path.",
        adv_card_w)
      edit.allow_insecure = new_insecure
      if edit.allow_insecure then
        Dummy(RA.ctx, 1, RA.SC(4))
        _inline_msg(
          "TLS verification disabled. Credentials can be intercepted. "
          .. "Only keep this on for trusted endpoints.",
          TK.amber)
      end
    end
    -- For http:// or blank URLs, the toggle row is hidden above. The
    -- saved 'allow_insecure' value is preserved in edit state so that
    -- flipping the URL back to https:// (e.g. during a typo fix) doesn't
    -- wipe the user's intent. curl's --insecure flag only affects TLS
    -- connections, so leaving it true for an http:// request is a no-op
    -- at the wire level.

    ImGui.ImGui_EndChild(RA.ctx)
  end
  _pop_cllm_card()

  ImGui.ImGui_EndDisabled(RA.ctx)  -- pair for BeginDisabled(key_validating)

  Dummy(RA.ctx, 1, RA.SC(14))

  -- Live status line: countdown while a Test Connection is in flight,
  -- pass/fail result once complete. Also doubles as a client-side
  -- watchdog: if elapsed exceeds the timeout by 3s (grace for curl to
  -- write its exit code), force-fail so the UI never hangs permanently.
  do
    local rt = api_keys.custom_conn_test
    if rt and rt.active and rt.started then
      local elapsed   = reaper.time_precise() - rt.started
      local remaining = (rt.timeout or 30) - elapsed
      if elapsed > (rt.timeout or 30) + 3 then
        if Net.kill_curl then pcall(Net.kill_curl) end
        S.key_test_pending  = false
        S.key_test_provider = nil
        S.curl_pid          = nil
        CTX.custom_conn_test_advance(false,
          "No response from server (client watchdog fired).")
      end
      if remaining < 0 then remaining = 0 end
      local txt = str_format("Testing connection...  (%.1fs remaining)", remaining)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
      Text(RA.ctx, txt)
      PopStyleColor(RA.ctx)
      Dummy(RA.ctx, 1, RA.SC(6))
    elseif rt and rt.result then
      local r   = rt.result
      local col = r.ok and TK.green or TK.red
      local txt = r.ok and "Connection OK. Server reachable."
                      or ("Connection failed: " .. (r.error or "unknown error"))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), col)
      -- r.error can carry newlines from curl/HTTP responses; route through
      -- text_multiline so TextWrapped never sees a literal \n.
      UI.text_multiline(txt)
      PopStyleColor(RA.ctx)
      Dummy(RA.ctx, 1, RA.SC(6))
    end
  end

  -- "Test with real chat/completions" checkbox. Default off so the safe
  -- GET /v1/models probe stays the one-click default. Ticking it routes
  -- Test Connection through a real chat/completions POST with max_tokens=1
  -- and "hi" -- exercises the same path real chat will, but on reasoning
  -- models like DeepSeek-R1 / o1 the thinking phase still runs (the cap
  -- only limits OUTPUT tokens), so the user pays for that one inference
  -- call. Transient: the checkbox state lives only in api_keys.custom_edit
  -- and is reset whenever the user enters/leaves the edit screen. Centered
  -- to align with the action row below.
  do
    local edit = api_keys.custom_edit
    if edit then
      local cb_label = "Test with a real chat/completions request"
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      local cb_w = CalcTextSize(RA.ctx, cb_label) + RA.SC(28)  -- text + checkbox + gap
      PopFont(RA.ctx)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - cb_w) * 0.5), 0))
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),       TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_CheckMark(),     TK.accent)
      local _changed, _new = ImGui.ImGui_Checkbox(RA.ctx,
        cb_label .. "##cllm_test_inference",
        edit.test_with_inference and true or false)
      if _changed then edit.test_with_inference = _new end
      PopStyleColor(RA.ctx, 5)
      PopFont(RA.ctx)
      UI.tooltip(
        "Off (default): GET /v1/models -- safe, free, instant. Verifies "
        .. "server reachable and auth header works.\n\n"
        .. "On: POST /v1/chat/completions with max_tokens=1 and 'hi' against "
        .. "your first model. Exercises the same path real chat uses, but "
        .. "reasoning models (DeepSeek-R1, o1, etc.) still run the full "
        .. "thinking phase -- you'll pay for one short inference call.")
      Dummy(RA.ctx, 1, RA.SC(8))
    end
  end

  -- ============================================================
  -- Action row: [Cancel]  [Test Connection]  [Save]
  -- Save is the primary (accent) call-to-action; Cancel + Test are
  -- V5 secondary (card fill, border, muted text). Centered under the
  -- cards to keep eye flow down the page.
  -- ============================================================
  local test_active = api_keys.custom_conn_test and api_keys.custom_conn_test.active
  local test_btn_lbl = test_active and "Cancel Test" or "Test Connection"

  -- Measure button widths from their real label widths so the row
  -- auto-adjusts when "Test Connection" flips to "Cancel Test".
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
  local save_w   = CalcTextSize(RA.ctx, "Save")   + RA.SC(40)
  local cancel_w = CalcTextSize(RA.ctx, "Cancel") + RA.SC(40)
  PopFont(RA.ctx)
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  local test_w = CalcTextSize(RA.ctx, test_btn_lbl) + RA.SC(36)
  PopFont(RA.ctx)
  local BTN_GAP  = RA.SC(8)
  local total_w  = cancel_w + BTN_GAP + test_w + BTN_GAP + save_w
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - total_w) * 0.5), 0))

  -- Secondary pair: Cancel + Test.
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)

  ImGui.ImGui_BeginDisabled(RA.ctx, test_active)
  local cllm_back_clicked = ImGui.ImGui_Button(RA.ctx, "Cancel##cllm_back", cancel_w, 0)
  UI.pressable()
  ImGui.ImGui_EndDisabled(RA.ctx)

  SameLine(RA.ctx, 0, BTN_GAP)
  local cllm_test_clicked = ImGui.ImGui_Button(RA.ctx,
    test_btn_lbl .. "##cllm_test", test_w, 0)
  UI.pressable()
  UI.tooltip(test_active
    and "Cancel the in-flight connection test"
    or  "Test the endpoint and key against the current form values (no save required). Default: GET /v1/models. With the checkbox above ticked: real chat/completions POST.")

  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  -- Primary: Save (accent fill, white text, no border).
  SameLine(RA.ctx, 0, BTN_GAP)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(TK.accent, 0x000000FF, 0.15))
  ImGui.ImGui_BeginDisabled(RA.ctx, api_keys.key_validating)
  -- Ctrl+S (Cmd+S on Mac) mirrors the Save button. Disabled state mirrors
  -- the button: don't fire the shortcut while a key validation curl is
  -- in flight (matches the BeginDisabled gate above).
  local cllm_save_clicked = ImGui.ImGui_Button(RA.ctx, "Save##cllm_save", save_w, 0)
    or (not api_keys.key_validating and UI.is_save_shortcut())
  UI.pressable()
  ImGui.ImGui_EndDisabled(RA.ctx)
  PopStyleColor(RA.ctx, 4)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  -- Handle Cancel (button click OR Esc / MB4 while not mid-test). Always
  -- returns to the Custom Providers list -- the list itself handles the
  -- final return to Settings / first-run so this screen only owns the
  -- edit-vs-cancel decision.
  if cllm_back_clicked
    or (not api_keys.key_validating and not test_active
        and UI.back_pressed()) then
    api_keys.screen      = "custom_providers"
    api_keys.custom_edit = nil
  end

  -- Handle Test / Cancel Test click.
  if cllm_test_clicked then
    if test_active then
      CTX.custom_conn_test_cancel()
    else
      CTX.custom_llm_start_conn_test()
    end
  end

  Dummy(RA.ctx, 1, RA.SC(10))

  ImGui.ImGui_Unindent(RA.ctx, cllm_indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding
  UI.pop_settings_styles()

  -- V5 footer rail: outside the child, pins to outer window bottom.
  UI.footer_rail_v5()

  -- Handle Save: validate, persist, register, return to the list. The list
  -- screen owns the route back to Settings / first-run, so this branch only
  -- decides Save-vs-error.
  if cllm_save_clicked and not api_keys.key_validating then
    edit.errors = {}
    local has_format_error = false

    local endpoint_t = (edit.endpoint        or ""):match("^%s*(.-)%s*$") or ""
    local timeout_t  = (edit.timeout         or ""):match("^%s*(.-)%s*$") or ""
    local ctimeout_t = (edit.connect_timeout or ""):match("^%s*(.-)%s*$") or ""
    local label_t    = (edit.label           or ""):match("^%s*(.-)%s*$") or ""
    local key_t      = (edit.key             or ""):match("^%s*(.-)%s*$") or ""
    local prefix_t   = (edit.model_prefix    or ""):match("^%s*(.-)%s*$") or ""

    local parsed_models = {}
    local any_row_input = false
    for ri, row in ipairs(edit.models or {}) do
      local id_t     = (row.id             or ""):match("^%s*(.-)%s*$") or ""
      local pin_t    = (row.price_in       or ""):match("^%s*(.-)%s*$") or ""
      local pcache_t = (row.price_cache_r  or ""):match("^%s*(.-)%s*$") or ""
      local pout_t   = (row.price_out      or ""):match("^%s*(.-)%s*$") or ""
      local ctx_t2   = (row.context_window or ""):match("^%s*(.-)%s*$") or ""
      local notes_raw = row.notes or ""
      local body_raw  = row.extra_body or ""
      -- Has the user typed anything meaningful on this row besides the id?
      -- Used for two things: feeding any_row_input (form-is-being-filled-out
      -- gate), and surfacing an explicit "Model Identifier required" error
      -- when this is true but id_t == "" -- otherwise the row would silently
      -- vanish from persistence. The default-row shape (all "0" / default
      -- ctx / blank notes / blank body) is treated as "no input" so a fresh
      -- "+ Add Model" row still drops silently when left untouched.
      local row_typed = (pin_t    ~= "" and pin_t    ~= "0")
                        or (pout_t   ~= "" and pout_t   ~= "0")
                        or (pcache_t ~= "" and pcache_t ~= "0")
                        or (ctx_t2   ~= "" and ctx_t2   ~= tostring(CUSTOM_DEFAULT_CTX))
                        or (notes_raw ~= "")
                        or (body_raw  ~= "")
      if id_t ~= "" or row_typed then
        any_row_input = true
      end
      if id_t ~= "" then
        local pin_n    = tonumber(pin_t    == "" and "0" or pin_t)
        local pcache_n = tonumber(pcache_t == "" and "0" or pcache_t)
        local pout_n   = tonumber(pout_t   == "" and "0" or pout_t)
        local ctx_n    = tonumber(ctx_t2   == "" and tostring(CUSTOM_DEFAULT_CTX) or ctx_t2)
        local notes_clean, notes_err = Custom.validate_notes(notes_raw)
        local body_clean,  body_err  = Custom.validate_extra_body(body_raw)
        if not pin_n or pin_n < 0 then
          edit.errors["model_" .. ri] = "Input price (cache miss) must be a number >= 0."
          has_format_error = true
        elseif not pcache_n or pcache_n < 0 then
          edit.errors["model_cache_" .. ri] = "Cache-hit price must be a number >= 0."
          edit.errors["model_" .. ri] = "Details has errors - reopen to fix."
          has_format_error = true
        elseif not pout_n or pout_n < 0 then
          edit.errors["model_" .. ri] = "Output price must be a number >= 0."
          has_format_error = true
        elseif not ctx_n or ctx_n < CUSTOM_MIN_CTX then
          edit.errors["model_" .. ri] = str_format(
            "Context window must be a number >= %d.", CUSTOM_MIN_CTX)
          has_format_error = true
        elseif notes_err then
          -- Notes lives on the row, so a single inline error is enough; no
          -- "reopen Details" hint required.
          edit.errors["model_notes_" .. ri] = notes_err
          has_format_error = true
        elseif body_err then
          edit.errors["model_body_" .. ri] = body_err
          edit.errors["model_" .. ri] = "Details has errors - reopen to fix."
          has_format_error = true
        else
          parsed_models[#parsed_models+1] = {
            id             = id_t,
            price_in       = pin_n,
            price_cache_r  = pcache_n,
            price_out      = pout_n,
            context_window = ctx_n,
            notes          = notes_clean or "",
            extra_body     = body_clean  or "",
          }
        end
      elseif row_typed then
        -- User typed prices / context / notes / extra body on this row but
        -- left the Model Identifier blank. Refuse the save instead of
        -- silently dropping the row from persistence -- otherwise the user
        -- looks at the saved provider later and finds the row gone with no
        -- warning. (Fresh "+ Add Model" rows are still dropped silently
        -- because row_typed stays false on a default-shape row.)
        edit.errors["model_" .. ri] =
          "Model Identifier is required for this row. Add an id, or click the trash icon to remove the row."
        has_format_error = true
      end
    end

    local any_field = label_t ~= "" or endpoint_t ~= "" or any_row_input or key_t ~= ""
    local headers_arr, headers_err = Custom.parse_headers_text(edit.headers_text or "")
    if headers_err then any_field = true end
    local prov_body_clean, prov_body_err = Custom.validate_extra_body(edit.extra_body or "")
    if prov_body_err or (prov_body_clean and prov_body_clean ~= "") then
      any_field = true
    end
    if any_field then
      if label_t == "" then
        edit.errors.label = "Name is required."
        has_format_error = true
      end
      if not endpoint_t:match("^https?://") then
        edit.errors.endpoint = "Endpoint must start with http:// or https://."
        has_format_error = true
      elseif endpoint_t:find("[\"'`%c]") then
        -- Reject characters that would break (or escape out of) the
        -- powershell + cmd quoting in Net.fire_curl.
        edit.errors.endpoint = "Endpoint may not contain quotes, backticks, or control characters."
        has_format_error = true
      end
      if #parsed_models == 0 then
        edit.errors.model_id = "At least one model with a non-empty identifier is required."
        has_format_error = true
      end
      local timeout_n = tonumber(timeout_t == "" and tostring(CUSTOM_DEFAULT_TIMEOUT) or timeout_t)
      if not timeout_n or timeout_n < CUSTOM_MIN_TIMEOUT then
        edit.errors.timeout = str_format(
          "Timeout must be a number >= %d seconds.", CUSTOM_MIN_TIMEOUT)
        has_format_error = true
      elseif timeout_n > CUSTOM_MAX_TIMEOUT then
        edit.errors.timeout = str_format(
          "Timeout must be <= %d seconds (1 hour).", CUSTOM_MAX_TIMEOUT)
        has_format_error = true
      end
      local ctimeout_n = tonumber(ctimeout_t == "" and tostring(Custom.DEFAULT_CONNECT) or ctimeout_t)
      if not ctimeout_n or ctimeout_n < Custom.MIN_CONNECT or ctimeout_n > Custom.MAX_CONNECT then
        edit.errors.connect_timeout = str_format(
          "Connect timeout must be a number between %d and %d seconds.",
          Custom.MIN_CONNECT, Custom.MAX_CONNECT)
        has_format_error = true
      end
      if headers_err then
        edit.errors.headers = headers_err
        has_format_error = true
      end
      if prov_body_err then
        edit.errors.extra_body = prov_body_err
        has_format_error = true
      end
      if key_t ~= "" then
        local lk_valid, lk_reason = Key.validate_format(key_t,
          { is_custom = true, key_prefix = "", key_min_len = 0 })
        if not lk_valid then
          edit.errors.key = lk_reason
          has_format_error = true
        end
      end

      if not has_format_error then
        -- Remember which provider was active before saving so we can
        -- keep it selected across the re-registration cycle below. If
        -- this save is an edit of the currently-selected provider, the
        -- id lookup on the re-registered PROVIDERS table snaps
        -- prefs.provider_idx back onto the right entry.
        local was_active_id = PROVIDERS.active() and PROVIDERS.active().id
        local record = {
          id                   = edit.id,
          endpoint             = endpoint_t,
          models               = parsed_models,
          timeout_secs         = timeout_n or CUSTOM_DEFAULT_TIMEOUT,
          connect_timeout_secs = ctimeout_n or Custom.DEFAULT_CONNECT,
          allow_insecure       = edit.allow_insecure and true or false,
          model_prefix         = prefix_t,
          extra_headers        = headers_arr or {},
          extra_body           = prov_body_clean or "",
          label                = label_t,  -- validated non-empty above
        }
        Custom.upsert_record(record)
        -- Clamp the persisted model_idx for this provider so it can never
        -- point past the (possibly-shrunk) models list. The runtime loader
        -- (_prefs_load_idx) already clamps at read time, so this is purely
        -- a hygiene write: it keeps reaper-extstate.ini honest about the
        -- last-selected slot. Without it, a stale "model_idx_<id>=N" sits
        -- around forever on disk pointing past the end of the list, which
        -- makes the file useless as evidence when triaging "where did my
        -- models go?" reports.
        do
          local idx_key = "model_idx_" .. edit.id
          local cur = tonumber(reaper.GetExtState(CFG.EXT_NS, idx_key))
          if cur and #parsed_models > 0 and cur > #parsed_models then
            reaper.SetExtState(CFG.EXT_NS, idx_key,
              tostring(#parsed_models), true)
          end
        end
        if key_t ~= "" then
          Key.save(key_t, "api_key_" .. edit.id)
          S.api_key_map[edit.id] = key_t
        elseif edit.orig_key and edit.orig_key ~= "" then
          -- User blanked an existing key: wipe it from ExtState + memory.
          Key.clear("api_key_" .. edit.id)
          S.api_key_map[edit.id] = nil
        end
        Custom.register_all()
        -- Restore active-provider id if possible. The re-registered list
        -- has the same ids but potentially different indices; PROVIDERS
        -- ._by_id is rebuilt by register_all so the lookup is safe.
        if was_active_id and PROVIDERS._by_id[was_active_id] then
          prefs.provider_idx = PROVIDERS._by_id[was_active_id]
        elseif prefs.provider_idx < 1 or prefs.provider_idx > #PROVIDERS then
          prefs.provider_idx = 1
        end
        -- Failsafe: if the restored active provider has no usable key
        -- (built-in with nothing in api_key_map), prefer the just-saved
        -- custom provider. Hits the post-factory-reset path where
        -- prefs.provider_idx still points at Claude (the documented
        -- default) but no Claude key was ever entered; without this
        -- snap, the home-page chip row shows Claude as active-but-
        -- grayed, the dropdown is single-entry and disabled, and the
        -- newly-added custom record is unreachable.
        do
          local stranded = PROVIDERS[prefs.provider_idx]
          if stranded and (stranded.hidden
             or (not stranded.is_custom and not S.api_key_map[stranded.id]))
             and PROVIDERS._by_id[edit.id] then
            prefs.provider_idx = PROVIDERS._by_id[edit.id]
            reaper.SetExtState(CFG.EXT_NS, "provider_idx",
              tostring(prefs.provider_idx), true)
          end
        end
        MODELS.refresh()
        -- Guard: if register_all somehow produced an empty PROVIDERS
        -- (no hardcoded entries AND every custom record was rejected),
        -- PROVIDERS.active() returns nil. Indexing .id on it would
        -- throw and prevent the user from leaving the Custom LLM screen.
        local _act = PROVIDERS.active()
        S.api_key = _act and S.api_key_map[_act.id] or nil
        api_keys.custom_edit = nil
        api_keys.screen      = "custom_providers"
        UI.show_float_toast("Provider saved", "ok")
      end
    else
      -- Nothing to save -- just go back to the list.
      api_keys.custom_edit = nil
      api_keys.screen      = "custom_providers"
    end
  end
end

-- =============================================================================
-- Render.preferred_plugins_screen
-- =============================================================================
-- Full-window page for managing preferred plugin defaults, styled like the
-- API key screen. Users enter the FX Browser name for each plugin type.
-- A "Save & Scan" button persists the preferences and scans installed FX
-- to cache parameter names and defaults into the JSON cache.

function Render.preferred_plugins_screen()
  -- Auto-exit after a successful save/scan completed on a prior frame.
  -- Return to the Settings page (not the main UI) so the user can continue
  -- adjusting other settings without having to reopen Settings.
  if pref_plugins.pending_exit then
    pref_plugins.pending_exit = false
    api_keys.screen = "settings"
    pref_plugins.initialized = false
    return  -- next frame renders the Settings page
  end

  -- Load saved preferences on first render.
  if not pref_plugins.initialized then
    -- Pre-fill rows from defaults.
    pref_plugins.rows = {}
    for _, lbl in ipairs(PREF_PLUGIN_DEFAULTS) do
      pref_plugins.rows[#pref_plugins.rows+1] =
        { label = lbl, name = "", aliases = "" }
    end
    -- Add 2 blank rows for custom types.
    pref_plugins.rows[#pref_plugins.rows+1] = { label = "", name = "", aliases = "" }
    pref_plugins.rows[#pref_plugins.rows+1] = { label = "", name = "", aliases = "" }
    CTX.load_pref_plugins()
    pref_plugins.initialized = true
    pref_plugins.scan.status = ""
    pref_plugins.scan.active = false
  end

  -- Centered column via Indent (no child window) so the main window scrollbar
  -- handles overflow -- same pattern as Render.help_screen.
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w     = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local pref_indent = math_max(math_floor((stable_w - inner_w) * 0.5), 0)

  UI.push_settings_styles()

  -- V5 hero band. Esc / Back / footer / logo click cover nav.
  UI.hero_band_settings_v5(
    "Set default plugins used for each task.",
    "PREFERRED PLUGINS \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: see Render.credits_screen for the full pattern.
  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##pref_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, pref_indent)

  -- Top padding.
  Dummy(RA.ctx, 1, RA.SC(16))

  -- Intro copy: bold value-prop headline (inter_semi SC(12)) + a regular
  -- how-to paragraph (inter_reg SC(12)). Same cadence as the Custom LLM
  -- page so the settings-family screens share a visual rhythm.
  local pp_wrap_x = GetCursorPosX(RA.ctx) + inner_w - RA.SC(20)
  ImGui.ImGui_PushTextWrapPos(RA.ctx, pp_wrap_x)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Set your preferred plugins so you can ask for an 'Equalizer' or "
    .. "'compressor' without naming a specific one. ReaAssist inserts "
    .. "your pick automatically.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(6))
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx,
    "Enter the plugin name exactly as it appears in your FX Browser "
    .. "(e.g. 'Pro-Q 4' or 'FabFilter Pro-Q 4'). Aliases let the model "
    .. "match alternate names you might use when asking for a plugin "
    .. "(e.g. 'eq' for Equalizer, 'comp' for Compressor). Leave blank "
    .. "for types you don't need.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  ImGui.ImGui_PopTextWrapPos(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(14))

  -- V5 card + input style helpers (same pattern as Custom LLM). Kept
  -- inside this function so the chrome stays local to this page.
  local function _push_pp_card()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(12), RA.SC(10))
  end
  local function _pop_pp_card()
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 2)
  end
  local function _push_pp_input()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),         TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),  TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),   TK.input_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),            TK.text)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(), TK.text)
    PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), RA.SC(8), RA.SC(5))
  end
  local function _pop_pp_input()
    ImGui.ImGui_PopStyleVar(RA.ctx)
    PopFont(RA.ctx)
    PopStyleColor(RA.ctx, 5)
  end
  -- Per-row pill button (Rescan + X). is_danger flips to a red-tinted
  -- hover for the row X. Optional font/font_size lets the Rescan button
  -- swap in the Lucide glyph (redo-2) instead of the Inter text label;
  -- pad_x/pad_y override the FramePadding so the icon button's height
  -- matches the text X button despite the larger glyph. Returns clicked.
  local function _row_pill(label, id_suffix, width, is_danger,
                           font, font_size, pad_x, pad_y)
    PushFont(RA.ctx, font or FONT.inter_reg, font_size or RA.SC(9))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),
      pad_x or RA.SC(6), pad_y or RA.SC(3))
    local text_col  = is_danger and TK.red or TK.text_muted
    local hover_bg  = is_danger and ((TK.red & 0xFFFFFF00) | 0x22) or TK.card_hover
    local active_bg = is_danger and ((TK.red & 0xFFFFFF00) | 0x3A)
                              or UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.45)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          text_col)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), hover_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  active_bg)
    local clicked = ImGui.ImGui_Button(RA.ctx, label .. id_suffix, width or 0, 0)
    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)
    return clicked
  end

  -- ============================================================
  -- PLUGIN MAPPINGS section: card containing column headers, rows,
  -- and the + Add button.
  -- ============================================================
  UI.v5_section_label("PLUGIN MAPPINGS")

  local remove_idx = nil
  local rescan_row_idx = nil

  -- Autocomplete state scoped to this render pass. Declared at the outer
  -- function scope (not inside the card's `if` block) so the owner-release
  -- logic after the card close still has visibility. ac_active_this_frame
  -- is set inside the row loop when any name field is focused.
  local ac = pref_plugins.ac
  local ac_picked_ident     = nil
  local ac_active_this_frame = false

  _push_pp_card()
  -- NoNavInputs suppresses ImGui's built-in arrow-key focus cycling INSIDE
  -- this child. Without it, pressing Down while typing in Plugin Name would
  -- move focus to the next row's Name input (ImGui's grid nav) even though
  -- our autocomplete dropdown wants the same key. The main window already
  -- carries NoNavInputs, but that flag doesn't propagate to child windows;
  -- nav re-engages inside child scopes unless explicitly suppressed.
  local row_card_open = ImGui.ImGui_BeginChild(RA.ctx, "##pref_rows_card",
    inner_w, 0,
    ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders(),
    ImGui.ImGui_WindowFlags_NoNavInputs())
  if row_card_open then
    local card_w            = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    -- window_w includes both left and right WindowPadding -- we use it to
    -- anchor the Rescan icon ACTION_RIGHT_MARG SC from the VISIBLE BORDER,
    -- not from the content-region right edge (which is SC(12) short of the
    -- border due to _push_pp_card's WindowPadding).
    local window_w          = ImGui.ImGui_GetWindowWidth(RA.ctx)
    local CARD_PAD_X        = RA.SC(12)   -- matches WindowPadding in _push_pp_card
    local TYPE_W            = RA.SC(130)
    local ALIAS_W           = RA.SC(155)
    local RESCAN_W          = RA.SC(26)   -- icon button (redo-2 glyph)
    local RM_W              = RA.SC(22)
    local ACTION_RIGHT_MARG = RA.SC(10)   -- border to Rescan right-edge margin
    local ACTION_LEFT_GAP   = RA.SC(10)   -- Plugin Name right-edge to Rescan left-edge gap
    local row_gap           = RA.SC(4)
    -- X button (row remove) is only shown when the user has added rows beyond
    -- defaults + 2, which is a row-count-global state. When it's visible, it
    -- sits between Plugin Name and Rescan, narrowing Plugin Name uniformly
    -- across all rows so column alignment stays stable.
    local x_any = #pref_plugins.rows > #PREF_PLUGIN_DEFAULTS + 2
    local x_extra_w = x_any and (RM_W + row_gap) or 0
    -- Row layout (common case, X hidden):
    --   [pad][Type][g][Aliases][g][Plugin Name][10][Rescan][10][border]
    -- When X is visible, X slots in between Plugin Name and Rescan with
    -- row_gap on each side. NAME_W is derived from window_w so the right-
    -- edge math ignores content-region padding (Rescan lives in the padding
    -- zone on the right).
    local NAME_W            = window_w - CARD_PAD_X - TYPE_W - ALIAS_W
                                       - RESCAN_W - ACTION_RIGHT_MARG
                                       - ACTION_LEFT_GAP - row_gap * 2
                                       - x_extra_w

    -- Column headers: mono small-caps TK.text_faint, aligned over
    -- TYPE, ALIASES, and PLUGIN NAME columns.
    PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
    local hdr_x = GetCursorPosX(RA.ctx)
    Text(RA.ctx, "TYPE")
    SameLine(RA.ctx, hdr_x + TYPE_W + row_gap)
    Text(RA.ctx, "ALIASES")
    SameLine(RA.ctx, hdr_x + TYPE_W + ALIAS_W + row_gap * 2)
    Text(RA.ctx, "PLUGIN NAME")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    Dummy(RA.ctx, 1, RA.SC(2))

    ImGui.ImGui_BeginDisabled(RA.ctx, pref_plugins.scan.active)

    -- Populate the installed FX list (and its VST2/VST3-dedup variant,
    -- folded into the same one-shot enumeration -- see CTX.populate_
    -- installed_fx). Done once per session.
    CTX.populate_installed_fx()

    -- `ac` / `ac_picked_ident` / `ac_active_this_frame` are declared at
    -- the outer function scope so the owner-release logic after the card
    -- close can still read them. Row loop mutates them as upvalues.

    -- Tab-navigation support. The main window has NoNavInputs (to stop arrow
    -- keys from jumping between fields while the autocomplete dropdown is
    -- open), which also disables ImGui's built-in Tab focus cycling. We
    -- reimplement it manually: when Tab (or Shift+Tab) is pressed while a
    -- Type/Name InputText is focused, schedule focus for the next (or prev)
    -- field on the following frame via SetKeyboardFocusHere(0) just before
    -- that widget is drawn. Order: row1.type -> row1.name -> row2.type -> ...
    local pending_focus = pref_plugins._pending_focus
    pref_plugins._pending_focus = nil
    -- Resolve row-table identity back to a current index. Tab scheduled
    -- pending_focus by row reference (not numeric index) so a row removed
    -- between the Tab and this frame doesn't shift the focus onto an
    -- adjacent row. If the referenced row was deleted, drop the focus
    -- request rather than land somewhere unexpected.
    if pending_focus and pending_focus.row_ref then
      local resolved
      for ri, r in ipairs(pref_plugins.rows) do
        if r == pending_focus.row_ref then resolved = ri; break end
      end
      if resolved then
        pending_focus.row = resolved
      else
        pending_focus = nil
      end
    end

    for ri, row in ipairs(pref_plugins.rows) do
      -- Default rows (labels from PREF_PLUGIN_DEFAULTS) show Type as a locked
      -- muted-text label; user-added rows keep an editable InputText so the
      -- row can be named. is_default drives both the Type widget choice and
      -- the Tab-navigation skip logic below.
      local is_default = pref_plugins.default_set[row.label or ""] == true
      local type_active = false
      -- Remember the leftmost cursor X for this row so SameLine() can pin
      -- the Aliases column to (row_x0 + TYPE_W + row_gap) regardless of the
      -- Type column's rendered width.
      local row_x0 = GetCursorPosX(RA.ctx)

      if is_default then
        -- Locked Type: plain muted text using the same mono font as inputs so
        -- baseline and size match. AlignTextToFramePadding keeps the text
        -- vertically centered in the row alongside the editable inputs.
        ImGui.ImGui_AlignTextToFramePadding(RA.ctx)
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        Text(RA.ctx, row.label or "")
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        SameLine(RA.ctx, row_x0 + TYPE_W + row_gap)
      else
        _push_pp_input()
        ImGui.ImGui_PushItemWidth(RA.ctx, TYPE_W)
        if pending_focus and pending_focus.row == ri
              and pending_focus.field == "type" then
          ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
        end
        local tc, tv = ImGui.ImGui_InputTextWithHint(RA.ctx,
          "##ptype_" .. ri, "Type", row.label or "", 0)
        type_active = ImGui.ImGui_IsItemActive(RA.ctx)
        -- Right-click context menu intentionally NOT attached on the
        -- preferred-plugin row inputs: the Name column has its own
        -- autocomplete dropdown popup that would clash visually with
        -- the Copy/Paste/Cut popup, and adding the menu only to Type
        -- and Aliases (without Name) would be inconsistent. Native
        -- Cmd+C / Cmd+V / Cmd+X still work for these fields.
        if tc then
          row.label = tv
          pref_plugins.dirty = true
        end
        UI.focus_ring()
        ImGui.ImGui_PopItemWidth(RA.ctx)
        _pop_pp_input()
        SameLine(RA.ctx, 0, row_gap)
      end

      -- ALIASES column: always editable, even on default rows. Accepts a
      -- comma-separated list; pref_plugins.alias_lookup() splits and
      -- normalizes on read.
      _push_pp_input()
      ImGui.ImGui_PushItemWidth(RA.ctx, ALIAS_W)
      if pending_focus and pending_focus.row == ri
            and pending_focus.field == "aliases" then
        ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
      end
      local alc, alv = ImGui.ImGui_InputTextWithHint(RA.ctx,
        "##palias_" .. ri, "comma-separated", row.aliases or "", 0)
      local alias_active = ImGui.ImGui_IsItemActive(RA.ctx)
      -- Right-click menu intentionally omitted; see Type column comment above.
      if alc then
        row.aliases = alv
        pref_plugins.dirty = true
      end
      -- Tooltip shows the full alias list on hover -- many default rows have
      -- enough aliases that the text is truncated inside the field. Must fire
      -- right after the InputText so IsItemHovered() inside UI.tooltip refers
      -- to the aliases widget (UI.focus_ring is DrawList-only, doesn't shift it,
      -- but placing the tooltip first keeps the intent obvious).
      if row.aliases and row.aliases ~= "" then
        UI.tooltip(row.aliases)
      end
      UI.focus_ring()
      ImGui.ImGui_PopItemWidth(RA.ctx)
      SameLine(RA.ctx, 0, row_gap)

      ImGui.ImGui_PushItemWidth(RA.ctx, NAME_W)
      if pending_focus and pending_focus.row == ri
            and pending_focus.field == "name" then
        ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
      end
      local nc, nv = ImGui.ImGui_InputTextWithHint(RA.ctx,
        "##pname_" .. ri, "Plugin name", row.name or "", 0)
      local name_active = ImGui.ImGui_IsItemActive(RA.ctx)
      local nfx1, nfy1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local nfx2, nfy2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
      -- Right-click menu intentionally omitted; the Name column has its
      -- own autocomplete dropdown popup that the menu would clash with.
      if nc then
        row.name = nv
        pref_plugins.dirty = true
      end
      UI.focus_ring()
      ImGui.ImGui_PopItemWidth(RA.ctx)

      _pop_pp_input()

      -- Autocomplete wiring: only the focused row drives the dropdown.
      if name_active then
        ac_active_this_frame = true
        -- If a different row became active, reset filter so matches rebuild.
        if ac.row_idx ~= ri then
          ac.row_idx     = ri
          ac.last_filter = nil
          ac.sel         = 0
        end
        local cur = row.name or ""
        if cur ~= ac.last_filter then
          ac.last_filter = cur
          ac.sel         = 0
          local trimmed = cur:match("^%s*(.-)%s*$") or ""
          local rank_src = CTX._installed_fx_list_deduped
            or CTX._installed_fx_list
          if trimmed == "" or not rank_src then
            ac.matches = {}
          else
            ac.matches = pref_plugins_rank_matches(trimmed, rank_src, 8)
          end
        end
        ac.field_x1 = nfx1
        ac.field_y1 = nfy1
        ac.field_y2 = nfy2
        ac.field_w  = nfx2 - nfx1
        -- Keyboard nav (arrows): handled while the field is still active
        -- (InputText doesn't consume these on single-line fields).
        if #ac.matches > 0 then
          if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_DownArrow()) then
            local n = #ac.matches
            ac.sel = ac.sel + 1
            if ac.sel > n then ac.sel = 1 end
          elseif ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_UpArrow()) then
            local n = #ac.matches
            ac.sel = ac.sel - 1
            if ac.sel < 1 then ac.sel = n end
          elseif ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
            ac.matches     = {}
            ac.sel         = 0
            ac.last_filter = cur  -- suppress rebuild until text changes
          end
        end
      end

      -- Rescan icon anchored ACTION_RIGHT_MARG from the window's VISIBLE
      -- right border (window_w is full window width; the right WindowPadding
      -- gets reclaimed for the action cluster). When X is visible, it slots
      -- in just to Rescan's left with row_gap between; when hidden, Rescan
      -- sits alone -- no Dummy, because NAME_W already absorbs the freed
      -- space (x_extra_w = 0 in the NAME_W formula above).
      --
      -- ImGui_SameLine(offset_from_start_x) is relative to cursor_start_pos.x,
      -- which is offset from the window's visible left border by
      -- WindowPadding.x (CARD_PAD_X here). Subtract it so the icon ends
      -- ACTION_RIGHT_MARG from the visible right border, not (CARD_PAD_X
      -- - ACTION_RIGHT_MARG) past it.
      local rescan_left_x = window_w - CARD_PAD_X - RESCAN_W - ACTION_RIGHT_MARG
      if x_any then
        SameLine(RA.ctx, rescan_left_x - row_gap - RM_W)
        if _row_pill("x", "##premove_" .. ri, RM_W, true) then
          remove_idx = ri
        end
        SameLine(RA.ctx, 0, row_gap)
      else
        SameLine(RA.ctx, rescan_left_x)
      end

      -- Per-row Rescan: commits this row's type->ident mapping and scans
      -- just that one plugin. Disabled for plugins with a curated section
      -- in Plugin_Ref.md -- their params are documented and preempt routes
      -- through plugin_ref:<Name>, so a Rescan would burn seconds producing
      -- data that's never read.
      local row_scan_busy =
        pref_plugins.scan.active or fx_cache_ui.rescan.active
      local row_is_curated = Code.is_curated_plugin(row.name)
      ImGui.ImGui_BeginDisabled(RA.ctx, row_scan_busy or row_is_curated)
      -- Lucide glyph at SC(14) with SC(5)/SC(2) padding gives a ~18 SC tall
      -- button -- a few SC taller than the Inter SC(9) X button (~15 SC tall)
      -- per the user's request to size Rescan up.
      if _row_pill(ICON.REDO_2, "##prescan_" .. ri, RESCAN_W, false,
                   FONT.lucide, RA.SC(14), RA.SC(5), RA.SC(2)) then
        rescan_row_idx = ri
      end
      ImGui.ImGui_EndDisabled(RA.ctx)
      if ImGui.ImGui_IsItemHovered(RA.ctx,
           ImGui.ImGui_HoveredFlags_AllowWhenDisabled()) then
        if row_is_curated then
          UI.tooltip("Curated reference used. Rescan not needed. "
            .. "Plugin params are documented in Plugin_Ref.md and injected "
            .. "directly when this type is mentioned.")
        else
          UI.tooltip("Rescan this plugin")
        end
      end

      -- Tab / Shift+Tab to move between fields. Detected while any InputText
      -- in this row is active; we schedule focus on the target field for the
      -- next frame (SetKeyboardFocusHere must run just before the widget is
      -- drawn, so we can't apply it immediately). Field order per row depends
      -- on whether Type is locked:
      --   default row: aliases -> name
      --   user row:    type -> aliases -> name
      -- Wrap from the last field of one row to the first field of the next.
      if (type_active or alias_active or name_active)
            and ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Tab()) then
        local shift_down =
             ImGui.ImGui_IsKeyDown(RA.ctx, ImGui.ImGui_Key_LeftShift())
          or ImGui.ImGui_IsKeyDown(RA.ctx, ImGui.ImGui_Key_RightShift())
        local n_rows = #pref_plugins.rows
        local cur_field = type_active and "type"
          or (alias_active and "aliases" or "name")
        -- First editable field of an arbitrary row: "aliases" for locked
        -- default rows, "type" for editable user rows.
        local function _first_field(idx)
          local r = pref_plugins.rows[idx]
          if r and pref_plugins.default_set[r.label or ""] then
            return "aliases"
          end
          return "type"
        end
        local next_row, next_field = ri, cur_field
        if shift_down then
          if cur_field == "name" then
            next_field = "aliases"
          elseif cur_field == "aliases" then
            if is_default then
              next_row = ri - 1
              if next_row < 1 then next_row = n_rows end
              next_field = "name"
            else
              next_field = "type"
            end
          else  -- type
            next_row = ri - 1
            if next_row < 1 then next_row = n_rows end
            next_field = "name"
          end
        else
          if cur_field == "type" then
            next_field = "aliases"
          elseif cur_field == "aliases" then
            next_field = "name"
          else  -- name
            next_row = ri + 1
            if next_row > n_rows then next_row = 1 end
            next_field = _first_field(next_row)
          end
        end
        -- Stash the row table identity (not just the numeric index) so a
        -- row removed in this same frame via X-button doesn't shift the
        -- scheduled focus onto an adjacent row on the next frame. The
        -- pre-loop reader resolves row_ref back to an index, or discards
        -- pending_focus if the referenced row was removed.
        pref_plugins._pending_focus = {
          row_ref = pref_plugins.rows[next_row],
          row     = next_row,  -- harmless fallback; reader overwrites from row_ref
          field   = next_field,
        }
      end
    end

    Dummy(RA.ctx, 1, RA.SC(6))

    -- "+ Add" compact secondary pill, left-aligned inside the card.
    -- Same chrome as the "+ Add Model" button on Custom LLM for family
    -- consistency across the settings-group screens.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(4))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
    if ImGui.ImGui_Button(RA.ctx, "+  Add Row##padd") then
      pref_plugins.rows[#pref_plugins.rows+1] =
        { label = "", name = "", aliases = "" }
    end
    UI.tooltip("Add a blank row for a custom plugin type")
    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)

    ImGui.ImGui_EndDisabled(RA.ctx)    -- pair for BeginDisabled(scan.active)

    ImGui.ImGui_EndChild(RA.ctx)
  end  -- close if row_card_open
  _pop_pp_card()

  -- Global Enter handler for the autocomplete. We check this OUTSIDE the
  -- row loop's `if name_active` gate because ImGui's InputText deactivates
  -- on the Enter key-press frame (IsItemActive returns false), meaning an
  -- in-loop Enter check would miss the commit. Gating on `ac.row_idx` +
  -- `ac.sel > 0` keeps this scoped to the active dropdown.
  if ac.row_idx and ac.sel > 0 and ac.matches[ac.sel]
        and ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter()) then
    ac_picked_ident = ac.matches[ac.sel]
  end

  -- Floating autocomplete dropdown for the active row. Rendered AFTER the
  -- card closes because SetNextWindowPos uses absolute screen coords
  -- captured inside the row loop (ac.field_x1, ac.field_y2, ac.field_w).
  -- Must appear before the release check below so click-to-pick survives
  -- the mouse-down frame (when the InputText loses focus).
  if ac.row_idx and #ac.matches > 0 then
    local row_h = ImGui.ImGui_GetTextLineHeightWithSpacing(RA.ctx)
    local list_h = row_h * math_min(#ac.matches, 8) + 16
    -- Flip the dropdown above the field when there isn't enough room
    -- below for the full list. Without this, an 8-match list (~144 SC
    -- px) on a row near the window bottom renders below the visible
    -- border and click-to-pick lands on nothing. Use the monitor work
    -- area (cached during main_window setup) when present; otherwise
    -- fall back to placing-below as the existing behaviour.
    local mon_b = S._monitor_b or (S._monitor_h and (S._monitor_y or 0) + S._monitor_h)
    local dy
    if mon_b and (ac.field_y2 + 2 + list_h) > mon_b
       and ac.field_y1 and (ac.field_y1 - list_h - 2) >= (S._monitor_y or 0) then
      dy = ac.field_y1 - list_h - 2
    else
      dy = ac.field_y2 + 2
    end
    ac._render_dy = dy  -- shared with the hit-test block below for click-to-pick survival
    ImGui.ImGui_SetNextWindowPos(RA.ctx, ac.field_x1, dy)
    ImGui.ImGui_SetNextWindowSize(RA.ctx, ac.field_w, list_h)
    local wflags =
        ImGui.ImGui_WindowFlags_NoTitleBar()
      | ImGui.ImGui_WindowFlags_NoResize()
      | ImGui.ImGui_WindowFlags_NoMove()
      | ImGui.ImGui_WindowFlags_NoSavedSettings()
      | ImGui.ImGui_WindowFlags_NoFocusOnAppearing()
      | ImGui.ImGui_WindowFlags_NoNavInputs()
      | ImGui.ImGui_WindowFlags_NoNavFocus()
      | ImGui.ImGui_WindowFlags_NoScrollbar()
    local opened = ImGui.ImGui_Begin(RA.ctx, "##pref_ac_popup", true, wflags)
    if opened then
      for i, ident in ipairs(ac.matches) do
        local is_sel = (i == ac.sel)
        if ImGui.ImGui_Selectable(RA.ctx, ident .. "##pac" .. i, is_sel) then
          ac_picked_ident = ident
          ac.sel = i
        end
      end
      -- ImGui_End paired with Begin only on the visible path; ReaImGui
      -- auto-pops the window when Begin returns false. Same contract as
      -- the resolve popup at line ~15432 and the main window's End at ~16387.
      ImGui.ImGui_End(RA.ctx)
    end
  end

  -- Commit a picked ident into the active row's name field.
  if ac_picked_ident and ac.row_idx
        and pref_plugins.rows[ac.row_idx] then
    pref_plugins.rows[ac.row_idx].name = ac_picked_ident
    pref_plugins.dirty    = true
    ac.matches     = {}
    ac.sel         = 0
    ac.last_filter = ac_picked_ident
  end

  -- Release the autocomplete owner if no name field is focused this frame
  -- AND no commit just happened. Guarded by a mouse-hover / mouse-down
  -- check so click-to-pick survives the mouse-down frame (when the
  -- InputText loses focus before the Selectable fires).
  local defer_release = false
  if ac.row_idx and #ac.matches > 0 then
    local row_h = ImGui.ImGui_GetTextLineHeightWithSpacing(RA.ctx)
    local list_h = row_h * math_min(#ac.matches, 8) + 16
    local dx1, dy1 = ac.field_x1, ac._render_dy or (ac.field_y2 + 2)
    local dx2, dy2 = dx1 + ac.field_w, dy1 + list_h
    local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
    if mx >= dx1 and mx <= dx2 and my >= dy1 and my <= dy2 then
      defer_release = true
    end
    if ImGui.ImGui_IsMouseDown(RA.ctx, 0) then
      defer_release = true
    end
  end
  if not ac_active_this_frame and not ac_picked_ident and not defer_release
        and ac.row_idx then
    ac.row_idx     = nil
    ac.matches     = {}
    ac.sel         = 0
    ac.last_filter = nil
  end

  if remove_idx then
    table.remove(pref_plugins.rows, remove_idx)
    pref_plugins.dirty = true
  end

  -- Per-row Rescan: resolve this row's typed name to an ident, commit the
  -- type->ident mapping, and scan just that one plugin. Inline-errors if
  -- the row's text doesn't match any installed plugin.
  if rescan_row_idx then
    local row = pref_plugins.rows[rescan_row_idx]
    local lbl  = (row and row.label or ""):match("^%s*(.-)%s*$") or ""
    local name = (row and row.name  or ""):match("^%s*(.-)%s*$") or ""
    local canonical = lbl:match("^([^,]+)") or lbl
    canonical = canonical:match("^%s*(.-)%s*$") or ""
    pref_plugins.scan.status = ""
    if canonical == "" or name == "" then
      UI.show_float_toast("Fill in type and plugin name first", "err")
    else
      CTX.populate_installed_fx()
      local ident = CTX._installed_fx_list
        and pref_plugins_best_match(name, CTX._installed_fx_list)
      if not ident then
        UI.show_float_toast(
          "\"" .. name .. "\" doesn't match an installed plugin", "err")
      else
        -- label_to_type_key applies the alias map so long-form labels like
        -- "Synthesizer" / "Equalizer" normalize to their canonical keys
        -- ("synth" / "eq"). Using an inline lowercase+gsub (the previous
        -- path) would write a DIFFERENT key than save_pref_plugins uses,
        -- leaving stale entries in cache.preferred_types.
        local rkey = label_to_type_key(canonical)
        -- Commit preferred_types for just this row, without touching the
        -- others. (Other rows may still be dirty; they'll commit on Save.)
        local cache = FXCache.load()
        cache.preferred_types[rkey] = ident
        local err = FXCache.save(cache)
        if err then
          UI.show_float_toast("Save failed: " .. err, "err")
        else
          -- fx_cache_rescan_start (sync failure) OR fx_cache_rescan_read
          -- (async completion) fires the toast directly, so no pending-
          -- ident tracking is needed on this side.
          CTX.fx_cache_rescan_start(ident, false)
          Log.line("PREF", "per-row rescan: " .. rkey .. " -> " .. ident)
        end
      end
    end
  end

  Dummy(RA.ctx, 1, RA.SC(14))

  -- ============================================================
  -- Action buttons split across two centered rows:
  --   Row 1: [Rescan All]  [Clear All]  (scan / destructive)
  --   Row 2: [Cancel]      [Save]       (exit / primary)
  -- The split separates "change-all" actions (top row) from the
  -- standard confirm-or-exit pair (bottom row), and keeps Save's
  -- primary accent on the final row so it reads as the close-out CTA.
  -- ============================================================
  local SAVE_W, RESCAN_ALL_W, CLEAR_W, CANCEL_W = RA.SC(84), RA.SC(106), RA.SC(94), RA.SC(82)
  local BTN_GAP     = RA.SC(8)
  local ACTION_ROW_GAP = RA.SC(8)

  ----------------------------------------------------------------
  -- Row 1: Rescan All + Clear All (centered)
  ----------------------------------------------------------------
  local row1_w = RESCAN_ALL_W + BTN_GAP + CLEAR_W
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - row1_w) * 0.5), 0))

  -- Secondary Rescan All (card fill, border).
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
  ImGui.ImGui_BeginDisabled(RA.ctx,
    pref_plugins.scan.active or fx_cache_ui.rescan.active)
  if ImGui.ImGui_Button(RA.ctx, "Rescan All##pref_rescan_all", RESCAN_ALL_W, 0) then
    pref_plugins.scan.status = ""
    CTX.pref_plugins_scan_start(true)
    pref_plugins.dirty = false
  end
  UI.pressable()
  UI.tooltip("Force a full re-scan of every configured row, even ones already cached")
  ImGui.ImGui_EndDisabled(RA.ctx)
  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  -- Soft-red Clear All (red text + border, red-tinted hover, card fill).
  -- The real safety gate is the confirm popup, so a soft look here
  -- reads as destructive-intent without shouting.
  SameLine(RA.ctx, 0, BTN_GAP)
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.red)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        (TK.red & 0xFFFFFF00) | 0x60)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), (TK.red & 0xFFFFFF00) | 0x22)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  (TK.red & 0xFFFFFF00) | 0x3A)
  ImGui.ImGui_BeginDisabled(RA.ctx,
    pref_plugins.scan.active or fx_cache_ui.rescan.active)
  if ImGui.ImGui_Button(RA.ctx, "Clear All##pref_clear_all", CLEAR_W, 0) then
    ImGui.ImGui_OpenPopup(RA.ctx, "Confirm Clear Preferred##popup")
  end
  UI.pressable()
  ImGui.ImGui_EndDisabled(RA.ctx)
  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  ----------------------------------------------------------------
  -- Row 2: Cancel + Save (centered)
  ----------------------------------------------------------------
  Dummy(RA.ctx, 1, ACTION_ROW_GAP)
  local row2_w = CANCEL_W + BTN_GAP + SAVE_W
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - row2_w) * 0.5), 0))

  -- Secondary Cancel (card fill, border).
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
  local pref_cancel_clicked = ImGui.ImGui_Button(RA.ctx, "Cancel##pref_cancel", CANCEL_W, 0)
  UI.pressable()
  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  -- Primary Save (accent fill, white text, no border).
  SameLine(RA.ctx, 0, BTN_GAP)
  PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.accent)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
    UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
    UI.lerp_u32(TK.accent, 0x000000FF, 0.15))
  ImGui.ImGui_BeginDisabled(RA.ctx,
    pref_plugins.scan.active or fx_cache_ui.rescan.active)
  -- Ctrl+S (Cmd+S on Mac) mirrors the Save button. The disabled-state
  -- guard matches the BeginDisabled above so the shortcut can't fire
  -- mid-scan.
  local pref_save_clicked = ImGui.ImGui_Button(RA.ctx, "Save##pref_save", SAVE_W, 0)
    or (not (pref_plugins.scan.active or fx_cache_ui.rescan.active)
        and UI.is_save_shortcut())
  if pref_save_clicked then
    pref_plugins.scan.status = ""
    -- Check if any rows have both a type label and plugin name filled in.
    local any_filled = false
    for _, row in ipairs(pref_plugins.rows) do
      local lbl  = (row.label or ""):match("^%s*(.-)%s*$") or ""
      local name = (row.name  or ""):match("^%s*(.-)%s*$") or ""
      if lbl ~= "" and name ~= "" then any_filled = true; break end
    end
    if any_filled then
      -- Incremental: skip plugins already in cache.
      CTX.pref_plugins_scan_start(false)
    else
      -- No filled rows; just save type mappings.
      local err = CTX.save_pref_plugins()
      if err then
        UI.show_float_toast("Save failed: " .. err, "err")
      else
        UI.show_float_toast("Preferences saved", "ok")
        pref_plugins.pending_exit = true
      end
    end
    pref_plugins.dirty = false
  end
  UI.pressable()
  ImGui.ImGui_EndDisabled(RA.ctx)
  PopStyleColor(RA.ctx, 4)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  if pref_cancel_clicked or UI.back_pressed() then
    api_keys.screen = "settings"
    pref_plugins.initialized = false
  end

  -- Clear All confirmation popup. Clears cache.preferred_types but
  -- deliberately leaves cache.plugins (param scan data) intact so
  -- re-picking the same plugin later does not trigger a re-scan.
  local pc_w, pc_h = RA.SC(340), RA.SC(150)
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - pc_w) * 0.5,
      update._main_y + (update._main_h - pc_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, pc_w, pc_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "Confirm Clear Preferred##popup", true,
        ImGui.ImGui_WindowFlags_NoResize()) then
    local pc_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    local pc_txt = "Clear all preferred plugins?"
    local pc_tw  = CalcTextSize(RA.ctx, pc_txt)
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((pc_cw - pc_tw) * 0.5))
    Text(RA.ctx, pc_txt)
    local pc_txt2 = "Cached parameter data will be kept."
    local pc_tw2  = CalcTextSize(RA.ctx, pc_txt2)
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((pc_cw - pc_tw2) * 0.5))
    Text(RA.ctx, pc_txt2)
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)

    local pc_do_clear = false
    local pc_yes_w, pc_no_w, pc_gap = RA.SC(88), RA.SC(72), RA.SC(16)
    local pc_row = pc_yes_w + pc_gap + pc_no_w
    SetCursorPosX(RA.ctx,
      GetCursorPosX(RA.ctx) + math_floor((pc_cw - pc_row) * 0.5))
    UI.push_modal_danger_btn()
    if ImGui.ImGui_Button(RA.ctx, "Clear All", pc_yes_w, 0) then pc_do_clear = true end
    UI.pop_modal_danger_btn()
    SameLine(RA.ctx, 0, pc_gap)
    if ImGui.ImGui_Button(RA.ctx, "Cancel", pc_no_w, 0) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
      pc_do_clear = true
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if pc_do_clear then
      FXCache.clear_preferred_types()
      -- Force the Preferred Plugins page to reload from the (now-empty)
      -- cache on its next render, which rebuilds the default row set and
      -- clears all name fields.
      pref_plugins.initialized = false
      pref_plugins.dirty       = false
      pref_plugins.scan.status = ""
      UI.show_float_toast("Preferred plugins cleared", "ok")
      Log.line("PREF", "user cleared all preferred plugin mappings")
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_modal_style()

  -- In-flight scan status ("Scanning parameters...") still renders inline
  -- so the user sees progress during the 1-2s save-with-scan window. All
  -- terminal feedback (save ok / save failed / rescan complete / rescan
  -- failed / no matching plugin / cleared) goes to UI.show_float_toast,
  -- so completion messages are no longer stamped onto scan.status.
  if pref_plugins.scan.status ~= "" then
    Dummy(RA.ctx, 1, RA.SC(4))
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    UI.text_multiline(pref_plugins.scan.status)
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
  end

  -- Bottom margin: breathing room between the last action row and the
  -- footer rail so the page doesn't feel bottom-crowded.
  Dummy(RA.ctx, 1, RA.SC(24))

  ImGui.ImGui_Unindent(RA.ctx, pref_indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding

  -- Pop global button styling.
  UI.pop_settings_styles()

  -- V5 footer rail: outside the child, pins to outer window bottom.
  UI.footer_rail_v5()
end

-- =============================================================================
-- Render.fx_cache_screen
-- =============================================================================
-- Cache management page: lists all cached plugins with Rescan/Remove per entry
-- and a Clear All button at the top.

-- Start a single-plugin rescan from the cache management page.
-- If `deep` is true, the param probe runs via the defer-paced coroutine,
-- which is the only way to get accurate data from VST3 plugins with
-- one-cycle readback lag (e.g. Soundtoys EchoBoy).
function CTX.fx_cache_rescan_start(identifier, deep)
  local rs = fx_cache_ui.rescan
  if rs.active or deep_scan.active then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  if not tr then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: rescan (failed)", 0)
    rs.status = "Failed to create temporary track."
    UI.show_float_toast("Rescan failed", "err")
    return
  end
  -- Hide from TCP and mixer so user doesn't see it flash.
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)

  local fx_idx = reaper.TrackFX_AddByName(tr, identifier, false, -1)
  if fx_idx < 0 then
    reaper.DeleteTrack(tr)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: rescan (failed)", 0)
    rs.status = "Failed to load: " .. identifier
    UI.show_float_toast("Failed to load plugin", "err")
    return
  end
  reaper.TrackFX_Show(tr, fx_idx, 2)

  rs.active = true
  rs.phase  = "reading"
  rs.track  = tr
  rs.ident  = identifier
  rs.fx_idx = fx_idx
  rs.deep   = deep and true or false
  rs.status = deep and "Deep scanning..." or "Scanning..."

  -- For deep rescans, kick off the coroutine directly; the normal
  -- fx_cache_rescan_read path (called one frame later from loop) would
  -- invoke the shallow scanner first.
  if deep then
    rs.phase = "deep"
    CTX.start_deep_scan({
      tr           = tr,
      fx_idx       = fx_idx,
      identifier   = identifier,
      search_names = { identifier },
      origin       = "fx_cache",
      on_complete  = function(dparams, dmax, dcount)
        FXCache.put_plugin(identifier, dparams, dcount, dmax, false)
        if reaper.ValidatePtr2(0, tr, "MediaTrack*") then
          reaper.DeleteTrack(tr)
        end
        -- PreventUIRefresh(-1) already done by scan_fx_params_deep_body.
        reaper.Undo_EndBlock("ReaAssist: deep rescan plugin", 0)
        rs.active = false
        rs.phase  = "done"
        rs.track  = nil
        rs.deep   = false
        rs.status = "Deep rescanned: " .. identifier
        UI.show_float_toast("Deep rescan complete", "ok")
      end,
      on_cancel    = function(reason)
        if reaper.ValidatePtr2(0, tr, "MediaTrack*") then
          reaper.DeleteTrack(tr)
        end
        -- PreventUIRefresh(-1) already done by scan_fx_params_deep_body.
        reaper.Undo_EndBlock("ReaAssist: deep rescan (cancelled)", 0)
        rs.active = false
        rs.phase  = "done"
        rs.track  = nil
        rs.deep   = false
        if reason == "cancelled" then
          rs.status = "Deep rescan cancelled: " .. identifier
          UI.show_float_toast("Deep rescan cancelled", "err")
        else
          rs.status = "Deep rescan failed: " .. tostring(reason)
          UI.show_float_toast("Deep rescan failed", "err")
        end
      end,
    })
  end
end

-- Step 2 of the rescan state machine: read params from the temp
-- plugin, update the cache, and clean up.
function CTX.fx_cache_rescan_read()
  local rs = fx_cache_ui.rescan
  if not rs.active or rs.phase ~= "reading" then return end

  local tr = rs.track
  -- ValidatePtr2: stale userdata from a project switch or explicit track
  -- deletion between scan_start and this reader would crash the scanner.
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    rs.active = false
    rs.phase  = "done"
    rs.track  = nil
    rs.status = "Rescan failed: temp track lost."
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: rescan (failed)", 0)
    return
  end

  -- Wrap the scan in xpcall so a thrown error doesn't skip the cleanup
  -- below (orphaned hidden track + stuck PreventUIRefresh + unclosed Undo
  -- block). Treat a thrown scan like the ValidatePtr2-fail path above.
  local _ok, params_list, max_group, total_count, needs_deep_scan =
    xpcall(function()
      return CTX.scan_fx_params(tr, rs.fx_idx)
    end, debug.traceback)
  if not _ok then
    Log.line("FX_CACHE_RESCAN", string.format(
      "scan_fx_params threw for %s: %s",
      rs.ident or "?", tostring(params_list)))
    if reaper.ValidatePtr2(0, tr, "MediaTrack*") then
      reaper.DeleteTrack(tr)
    end
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ReaAssist: rescan (scan error)", 0)
    rs.active = false
    rs.phase  = "done"
    rs.track  = nil
    rs.status = "Rescan failed: scan threw an error."
    if fx_cache_ui.rescan_all.active then
      fx_cache_ui.rescan_all.failures[#fx_cache_ui.rescan_all.failures+1] = rs.ident
      CTX.fx_cache_rescan_all_advance()
    else
      UI.show_float_toast("Rescan failed", "err")
    end
    return
  end
  FXCache.put_plugin(rs.ident, params_list, total_count, max_group, needs_deep_scan)

  reaper.DeleteTrack(tr)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ReaAssist: rescan plugin", 0)

  rs.active = false
  rs.phase  = "done"
  rs.track  = nil
  rs.status = "Rescanned: " .. rs.ident

  -- If a batch rescan is in flight, auto-advance to the next plugin. The
  -- batch handler fires its own toast on full completion, so suppress the
  -- per-item toast while batching (otherwise we'd flash one per plugin).
  if fx_cache_ui.rescan_all.active then
    CTX.fx_cache_rescan_all_advance()
  else
    UI.show_float_toast("Rescan complete", "ok")
  end
end

-- Kick off a batch "Rescan All" over the given list of plugin idents.
-- Scans run strictly sequentially via the single-plugin rescan machinery
-- so there's never more than one temp track / plugin load in flight.
-- Failures (missing / unloadable plugins) are captured and the batch
-- continues with the rest.
function CTX.fx_cache_rescan_all_start(idents)
  local ra = fx_cache_ui.rescan_all
  if ra.active or fx_cache_ui.rescan.active or deep_scan.active then
    return
  end
  ra.queue = {}
  for _, id in ipairs(idents or {}) do
    ra.queue[#ra.queue+1] = id
  end
  if #ra.queue == 0 then return end
  ra.total    = #ra.queue
  ra.index    = 0
  ra.current  = nil
  ra.failures = {}
  ra.active   = true
  fx_cache_ui.rescan.status = ""
  CTX.fx_cache_rescan_all_advance()
end

-- Drain the queue. Called once from rescan_all_start and again from
-- rescan_read's completion hook. Loops synchronously over idents that
-- fail to load (so the UI doesn't stall on missing plugins) and yields
-- the moment a scan goes async (rescan.active = true).
function CTX.fx_cache_rescan_all_advance()
  local ra = fx_cache_ui.rescan_all
  if not ra.active then return end
  while #ra.queue > 0 do
    local next_ident = table.remove(ra.queue, 1)
    ra.index   = ra.index + 1
    ra.current = next_ident
    CTX.fx_cache_rescan_start(next_ident, false)
    if fx_cache_ui.rescan.active then
      -- Async scan in flight; will re-enter this function when it
      -- completes via the hook in fx_cache_rescan_read.
      return
    else
      -- Synchronous failure (plugin not found / couldn't load).
      -- Capture and try the next ident.
      ra.failures[#ra.failures+1] = next_ident
    end
  end
  -- Queue drained: finalise.
  local succeeded = ra.total - #ra.failures
  local msg = str_format("Rescanned %d/%d plugin%s.",
    succeeded, ra.total, ra.total == 1 and "" or "s")
  if #ra.failures > 0 then
    msg = msg .. str_format(" %d failed (missing plugins).", #ra.failures)
  end
  ra.active  = false
  ra.current = nil
  fx_cache_ui.rescan.status = msg
  UI.show_float_toast(msg, (#ra.failures > 0) and "err" or "ok")
end

-- Cancel an in-flight batch rescan. Lets the currently-scanning plugin
-- finish (aborting mid-scan would leave an orphaned temp track); just
-- clears the queue so no further plugins are started.
function CTX.fx_cache_rescan_all_cancel()
  local ra = fx_cache_ui.rescan_all
  if not ra.active then return end
  local done_so_far = ra.index - (fx_cache_ui.rescan.active and 1 or 0)
  ra.active  = false
  ra.queue   = {}
  ra.current = nil
  local msg = str_format("Rescan cancelled at %d/%d.", done_so_far, ra.total)
  fx_cache_ui.rescan.status = msg
  UI.show_float_toast(msg, "err")
end

function Render.fx_cache_screen()
  local cache = FXCache.load()

  -- Centered column layout (same pattern as other settings screens).
  local win_w    = ImGui.ImGui_GetWindowWidth(RA.ctx)
  local pad_x    = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding())
  local sb_w     = ImGui.ImGui_GetStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize())
  local stable_w = win_w - pad_x * 2 - sb_w
  local inner_w  = math_min(RA.SC(540), stable_w)
  local cache_indent = math_max(math_floor((stable_w - inner_w) * 0.5), 0)

  UI.push_settings_styles()

  -- V5 hero band. Esc / Back / footer / logo click cover nav.
  UI.hero_band_settings_v5(
    "Cached plugin parameter data.",
    "FX PARAM CACHE \xc2\xb7 v" .. CFG.VERSION)
  Dummy(RA.ctx, 1, RA.SC(6))

  -- V5 scroll body: see Render.credits_screen for the full pattern.
  local FOOTER_RAIL_H = RA.SC(32)
  local _body_avail_w = select(1, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_avail_h = select(2, ImGui.ImGui_GetContentRegionAvail(RA.ctx))
  local _body_h = math_max(_body_avail_h - FOOTER_RAIL_H, RA.SC(1))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 0)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   0, 0)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),          0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),        TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),
    UI.lerp_u32(TK.border_str, TK.text, 0.30))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(),
    UI.lerp_u32(TK.border_str, TK.text, 0.55))
  ImGui.ImGui_BeginChild(RA.ctx, "##fx_cache_body", _body_avail_w, _body_h, 0)

  ImGui.ImGui_Indent(RA.ctx, cache_indent)

  Dummy(RA.ctx, 1, RA.SC(16))

  -- Description: two short lines at SC(12). Informational page, so no
  -- bold value-prop headline like Custom LLM / Preferred Plugins; just
  -- a quick explainer above the sections. Split into two sentences so
  -- each one reads as a distinct point (what the cache does, when to
  -- rescan) rather than one long paragraph.
  local fx_desc_wrap = GetCursorPosX(RA.ctx) + inner_w - RA.SC(20)
  ImGui.ImGui_PushTextWrapPos(RA.ctx, fx_desc_wrap)
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(12))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
  Text(RA.ctx, "Plugins are cached on first inspection for instant reuse.")
  Text(RA.ctx, "Rescan a plugin after an update changes its parameters.")
  PopStyleColor(RA.ctx)
  PopFont(RA.ctx)
  ImGui.ImGui_PopTextWrapPos(RA.ctx)
  Dummy(RA.ctx, 1, RA.SC(14))

  -- V5 card + row-pill helpers (same pattern as Custom LLM / Preferred
  -- Plugins).  Kept inside the function so the chrome stays local.
  local function _push_fx_card()
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), TK.card)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ChildRounding(),   RA.SC(6))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(),   RA.SC(12), RA.SC(10))
  end
  local function _pop_fx_card()
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopStyleColor(RA.ctx, 2)
  end
  -- Per-row pill (Rescan / Deep / Remove). is_danger flips to red-tint.
  -- is_primary flips to an accent-tint hover for the "Deep" action so
  -- power users see it stand out (deep is the "fix broken readback"
  -- escape hatch, less common than Rescan).
  local function _fx_row_pill(label, id_suffix, width, is_danger)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(9))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(8), RA.SC(3))
    local text_col  = is_danger and TK.red or TK.text_muted
    local hover_bg  = is_danger and ((TK.red & 0xFFFFFF00) | 0x22) or TK.card_hover
    local active_bg = is_danger and ((TK.red & 0xFFFFFF00) | 0x3A)
                              or UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.45)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          text_col)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), hover_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  active_bg)
    local clicked = ImGui.ImGui_Button(RA.ctx, label .. id_suffix, width or 0, 0)
    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)
    return clicked
  end

  -- Collect two lists:
  --   plugin_ids  = live-scanned, non-curated (user-scannable entries)
  --   curated_ids = plugins with a curated Plugin_Ref.md section that the
  --                 user has set as a preference (read-only display). Also
  --                 includes any curated plugin that was live-scanned before
  --                 the Rescan disable was added.
  -- Cache the assembled lists keyed on FXCache._mutation_count so we
  -- only walk + sort `cache.plugins` and `pref_types_map` when something
  -- actually changes. Previously this ran every frame while the page
  -- was open: two pairs() walks + a table.sort on each list -- on a
  -- typical install with 30+ cached plugins, ~70 string compares per
  -- frame for invariant data.
  local _mc = FXCache._mutation_count or 0
  local plugin_ids, curated_ids
  if UI._fxc_lists_mc == _mc then
    plugin_ids  = UI._fxc_lists_plugins
    curated_ids = UI._fxc_lists_curated
  else
    plugin_ids = {}
    curated_ids = {}
    local seen_curated = {}
    for ident in pairs(cache.plugins) do
      if Code.is_curated_plugin(ident) then
        if not seen_curated[ident] then
          curated_ids[#curated_ids+1] = ident
          seen_curated[ident] = true
        end
      else
        plugin_ids[#plugin_ids+1] = ident
      end
    end
    local pref_types_map = FXCache.get_preferred_types() or {}
    for _, ident in pairs(pref_types_map) do
      if ident and ident ~= ""
         and Code.is_curated_plugin(ident)
         and not seen_curated[ident] then
        curated_ids[#curated_ids+1] = ident
        seen_curated[ident] = true
      end
    end
    table.sort(plugin_ids)
    table.sort(curated_ids)
    UI._fxc_lists_mc       = _mc
    UI._fxc_lists_plugins  = plugin_ids
    UI._fxc_lists_curated  = curated_ids
  end

  ----------------------------------------------------------------
  -- SCANNED PLUGINS section
  -- Count lives inside the card's top-left (not as the section
  -- label's right_text) so it reads as part of the card content,
  -- aligned with the card's inner left edge.
  ----------------------------------------------------------------
  UI.v5_section_label("SCANNED PLUGINS")

  local remove_ident, rescan_ident, deep_ident = nil, nil, nil

  _push_fx_card()
  if ImGui.ImGui_BeginChild(RA.ctx, "##fx_scanned_card", inner_w, 0,
      ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
    local card_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

    if #plugin_ids == 0 then
      -- Empty state: muted explainer, no Clear button needed.
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, "No plugins cached yet. Use fx_inspect or Preferred "
        .. "Plugins to populate.")
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)
    else
      -- Top row layout: "N plugins" count on the left; Rescan All +
      -- Clear All pills right-aligned. Rendered on a single SameLine so
      -- vertical alignment is automatic from ImGui's per-line baseline.
      local top_row_sx = GetCursorPosX(RA.ctx)
      PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, str_format("%d plugin%s",
        #plugin_ids, #plugin_ids == 1 and "" or "s"))
      PopStyleColor(RA.ctx)
      PopFont(RA.ctx)

      -- Right-side pill block: Rescan All (secondary) | Clear All (soft red).
      local RESCAN_ALL_PW = RA.SC(86)
      local CLEAR_W       = RA.SC(78)
      local top_gap       = RA.SC(6)
      local top_pills_w   = RESCAN_ALL_PW + top_gap + CLEAR_W
      SameLine(RA.ctx)
      SetCursorPosX(RA.ctx, top_row_sx + card_w - top_pills_w)

      -- Rescan All: V5 secondary pill. Scan runs sequentially through
      -- every cached plugin; the confirm popup gates larger caches.
      local any_scan_busy = fx_cache_ui.rescan.active
        or deep_scan.active
        or fx_cache_ui.rescan_all.active
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
        UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
      ImGui.ImGui_BeginDisabled(RA.ctx, any_scan_busy)
      if ImGui.ImGui_Button(RA.ctx, "Rescan All##fx_rescan_all", RESCAN_ALL_PW, 0) then
        -- Confirm for caches with more than 10 plugins (risk of a
        -- long batch); otherwise start immediately.
        if #plugin_ids > 10 then
          ImGui.ImGui_OpenPopup(RA.ctx, "Confirm Rescan All##popup")
        else
          CTX.fx_cache_rescan_all_start(plugin_ids)
        end
      end
      UI.tooltip("Shallow-rescan every plugin listed below, one at a time")
      ImGui.ImGui_EndDisabled(RA.ctx)
      PopStyleColor(RA.ctx, 5)
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopFont(RA.ctx)

      -- Clear All: soft-red pill. The confirm popup is the real safety gate.
      SameLine(RA.ctx, 0, top_gap)
      PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.red)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        (TK.red & 0xFFFFFF00) | 0x60)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), (TK.red & 0xFFFFFF00) | 0x22)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  (TK.red & 0xFFFFFF00) | 0x3A)
      ImGui.ImGui_BeginDisabled(RA.ctx, any_scan_busy)
      if ImGui.ImGui_Button(RA.ctx, "Clear All##fx_cache_clear", CLEAR_W, 0) then
        ImGui.ImGui_OpenPopup(RA.ctx, "Confirm Clear Cache##popup")
      end
      UI.tooltip("Remove every cached plugin's parameter data. Re-scans on next use.")
      ImGui.ImGui_EndDisabled(RA.ctx)
      PopStyleColor(RA.ctx, 5)
      ImGui.ImGui_PopStyleVar(RA.ctx, 3)
      PopFont(RA.ctx)
      Dummy(RA.ctx, 1, RA.SC(4))

      -- Batch progress line (only shown while a Rescan All is in flight).
      -- Replaces the plugin row list with a live status + cancel button
      -- so the user always has an exit hatch without scrolling.
      if fx_cache_ui.rescan_all.active then
        local ra = fx_cache_ui.rescan_all
        PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
        Text(RA.ctx, str_format("Rescanning %d / %d...",
          ra.index, ra.total))
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        if ra.current then
          PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
          Text(RA.ctx, ra.current)
          PopStyleColor(RA.ctx)
          PopFont(RA.ctx)
        end

        -- Thin progress bar: manual DrawList so the bar matches TK tokens
        -- without going through ImGui_ProgressBar's theme-independent defaults.
        local bar_w = card_w - RA.SC(4)
        local bar_h = RA.SC(3)
        local bsx, bsy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        ImGui.ImGui_DrawList_AddRectFilled(dl,
          bsx, bsy, bsx + bar_w, bsy + bar_h,
          (TK.border & 0xFFFFFF00) | 0x40, RA.SC(2))
        local pct = ra.total > 0 and (ra.index / ra.total) or 0
        if pct > 1 then pct = 1 end
        local fill_w = math_floor(bar_w * pct)
        if fill_w > 0 then
          ImGui.ImGui_DrawList_AddRectFilled(dl,
            bsx, bsy, bsx + fill_w, bsy + bar_h,
            TK.accent, RA.SC(2))
        end
        Dummy(RA.ctx, bar_w, bar_h)
        Dummy(RA.ctx, 1, RA.SC(4))

        -- Cancel pill: secondary V5 pill.
        PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
          UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
          UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
        if ImGui.ImGui_Button(RA.ctx, "Cancel##fx_rescan_all_cancel") then
          CTX.fx_cache_rescan_all_cancel()
        end
        UI.tooltip("Stop after the currently-scanning plugin finishes "
          .. "(canceling mid-scan could leave an orphan temp track)")
        PopStyleColor(RA.ctx, 5)
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)
        PopFont(RA.ctx)
      else
      -- Row list: only rendered when NO batch rescan is in flight.
      -- During a batch the progress block above replaces the rows so
      -- per-row actions can't fire mid-batch.

      -- Row layout metrics. Rows are single-line: ident + param count
      -- sit on the same row as the right-aligned action pills.
      local RESCAN_PW = RA.SC(52)
      local DEEP_PW   = RA.SC(48)
      local REMOVE_PW = RA.SC(60)
      local pill_gap  = RA.SC(4)
      local pills_w   = RESCAN_PW + pill_gap + DEEP_PW + pill_gap + REMOVE_PW

      for ri, ident in ipairs(plugin_ids) do
        if ri > 1 then
          -- Subtle separator between rows.
          local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          ImGui.ImGui_DrawList_AddLine(dl,
            sx, sy, sx + card_w, sy,
            (TK.border & 0xFFFFFF00) | 0x28, 1.0)
          Dummy(RA.ctx, 1, RA.SC(4))
        end

        local pdata = cache.plugins[ident]
        local param_n = pdata and pdata.params and #pdata.params or 0
        local needs_deep = pdata and pdata.needs_deep_scan

        -- Plugin ident (mono SC(10), TK.text) on the row's left.
        local row_sx = GetCursorPosX(RA.ctx)
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
        Text(RA.ctx, ident)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Param count / deep-scan note on the same line, mono SC(9)
        -- TK.text_faint (or TK.amber when a deep scan is needed).
        SameLine(RA.ctx, 0, RA.SC(10))
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
          needs_deep and TK.amber or TK.text_faint)
        Text(RA.ctx, str_format("%d params%s",
          param_n, needs_deep and "  |  needs deep scan" or ""))
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- Right-aligned action pills (Rescan / Deep / Remove).
        SameLine(RA.ctx)
        SetCursorPosX(RA.ctx, row_sx + card_w - pills_w)

        ImGui.ImGui_BeginDisabled(RA.ctx,
          fx_cache_ui.rescan.active or deep_scan.active)
        if _fx_row_pill("Rescan", "##rc_" .. ident, RESCAN_PW, false) then
          rescan_ident = ident
        end
        UI.tooltip("Quick rescan of this plugin (shallow read)")
        SameLine(RA.ctx, 0, pill_gap)
        if _fx_row_pill("Deep", "##dc_" .. ident, DEEP_PW, false) then
          deep_ident = ident
        end
        UI.tooltip("Defer-paced deep scan (seconds). Use for VST3 plugins "
          .. "where a normal rescan returns garbage enum/range data "
          .. "(readback-lag plugins like Soundtoys).")
        SameLine(RA.ctx, 0, pill_gap)
        if _fx_row_pill("Remove", "##rm_" .. ident, REMOVE_PW, true) then
          remove_ident = ident
        end
        UI.tooltip("Delete this plugin's cached parameter data")
        ImGui.ImGui_EndDisabled(RA.ctx)
      end
      end  -- close inner else (batch-not-active row list)
    end

    ImGui.ImGui_EndChild(RA.ctx)
  end
  _pop_fx_card()

  -- Process deferred row actions from the Scanned Plugins card above
  -- before rendering the rest of the page, so a row's Deep-scan click
  -- populates deep_scan state and the progress block renders in the
  -- same frame under the card that triggered it.
  if remove_ident then
    FXCache.remove_plugin(remove_ident)
  end
  if rescan_ident then
    fx_cache_ui.rescan.status = ""
    CTX.fx_cache_rescan_start(rescan_ident, false)
  end
  if deep_ident then
    fx_cache_ui.rescan.status = ""
    CTX.fx_cache_rescan_start(deep_ident, true)
  end

  -- Deep scan progress (in flight only): rendered between Scanned Plugins
  -- and Built-in References. The "just finished" success message used to
  -- render here too; that's now a floating toast fired from the deep-scan
  -- on_complete callback, so only the in-flight progress remains inline.
  local _deep_in_flight = deep_scan.active and deep_scan.origin == "fx_cache"

  if _deep_in_flight then
    Dummy(RA.ctx, 1, RA.SC(8))
    PushFont(RA.ctx, FONT.inter_semi, RA.SC(11))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
    Text(RA.ctx, "Deep scanning " .. tostring(deep_scan.identifier) .. "...")
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
    UI.text_multiline(
      "Deep scan reads parameters with a per-probe delay to handle "
      .. "plugins that report values one frame late.")
    UI.text_multiline("Runs once. Future requests will be instant.")
    local pct = 0
    if deep_scan.total_probes and deep_scan.total_probes > 0 then
      pct = math_floor(100 * deep_scan.probes_done / deep_scan.total_probes)
      if pct > 99 then pct = 99 end
    end
    Text(RA.ctx, str_format("Probing %d/%d (%d%%)",
      deep_scan.probes_done, deep_scan.total_probes, pct))
    PopStyleColor(RA.ctx)
    PopFont(RA.ctx)
    SameLine(RA.ctx, 0, RA.SC(12))
    -- Cancel pill: secondary V5 pill so the page doesn't grow yet another
    -- color token just for this spot.
    PushFont(RA.ctx, FONT.inter_reg, RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(3))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.35))
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
      UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.55))
    if ImGui.ImGui_Button(RA.ctx, "Cancel##deep_cancel") then
      CTX.cancel_deep_scan()
    end
    PopStyleColor(RA.ctx, 5)
    ImGui.ImGui_PopStyleVar(RA.ctx, 3)
    PopFont(RA.ctx)
  end

  Dummy(RA.ctx, 1, RA.SC(12))

  -- Confirmation popup for Rescan All (shown only when the cache has
  -- more than 10 plugins -- tuned so small caches skip the extra click).
  local rc_w, rc_h = RA.SC(340), RA.SC(160)
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - rc_w) * 0.5,
      update._main_y + (update._main_h - rc_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, rc_w, rc_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "Confirm Rescan All##popup", true,
        ImGui.ImGui_WindowFlags_NoResize()) then
    local rc_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    local rc_txt = str_format("Rescan all %d cached plugins?", #plugin_ids)
    local rc_tw  = CalcTextSize(RA.ctx, rc_txt)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((rc_cw - rc_tw) * 0.5))
    Text(RA.ctx, rc_txt)
    local rc_txt2 = "Takes roughly 1-2 seconds per plugin."
    local rc_tw2  = CalcTextSize(RA.ctx, rc_txt2)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((rc_cw - rc_tw2) * 0.5))
    Text(RA.ctx, rc_txt2)
    local rc_txt3 = "You can cancel anytime during the batch."
    local rc_tw3  = CalcTextSize(RA.ctx, rc_txt3)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((rc_cw - rc_tw3) * 0.5))
    Text(RA.ctx, rc_txt3)
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)

    local rc_do_start = false
    local rc_yes_w, rc_no_w, rc_gap = RA.SC(100), RA.SC(72), RA.SC(16)
    local rc_row = rc_yes_w + rc_gap + rc_no_w
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((rc_cw - rc_row) * 0.5))
    UI.push_modal_primary_btn()
    if ImGui.ImGui_Button(RA.ctx, "Rescan All", rc_yes_w, 0) then rc_do_start = true end
    UI.pop_modal_primary_btn()
    SameLine(RA.ctx, 0, rc_gap)
    if ImGui.ImGui_Button(RA.ctx, "Cancel", rc_no_w, 0) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
      rc_do_start = true
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if rc_do_start then
      CTX.fx_cache_rescan_all_start(plugin_ids)
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_modal_style()

  -- Confirmation popup for Clear All (styled to match Factory Reset dialog).
  local cc_w, cc_h = RA.SC(340), RA.SC(150)
  if update._main_w then
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      update._main_x + (update._main_w - cc_w) * 0.5,
      update._main_y + (update._main_h - cc_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
  end
  ImGui.ImGui_SetNextWindowSize(RA.ctx, cc_w, cc_h, ImGui.ImGui_Cond_Appearing())
  UI.push_modal_style()
  if ImGui.ImGui_BeginPopupModal(RA.ctx, "Confirm Clear Cache##popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
    local cc_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)
    local cc_txt = "Remove all cached plugin data?"
    local cc_tw  = CalcTextSize(RA.ctx, cc_txt)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((cc_cw - cc_tw) * 0.5))
    Text(RA.ctx, cc_txt)
    local cc_txt2 = "Plugins will be re-scanned on next use."
    local cc_tw2  = CalcTextSize(RA.ctx, cc_txt2)
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((cc_cw - cc_tw2) * 0.5))
    Text(RA.ctx, cc_txt2)
    ImGui.ImGui_Spacing(RA.ctx)
    ImGui.ImGui_Spacing(RA.ctx)

    local cc_do_clear = false
    local cc_yes_w, cc_no_w, cc_gap = RA.SC(88), RA.SC(72), RA.SC(16)
    local cc_row = cc_yes_w + cc_gap + cc_no_w
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((cc_cw - cc_row) * 0.5))
    UI.push_modal_danger_btn()
    if ImGui.ImGui_Button(RA.ctx, "Clear All", cc_yes_w, 0) then cc_do_clear = true end
    UI.pop_modal_danger_btn()
    SameLine(RA.ctx, 0, cc_gap)
    if ImGui.ImGui_Button(RA.ctx, "Cancel", cc_no_w, 0) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
      cc_do_clear = true
    end
    if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    if cc_do_clear then
      FXCache.clear_plugins()
      plugin_ids = {}
      ImGui.ImGui_CloseCurrentPopup(RA.ctx)
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_modal_style()

  -- Escape also closes the screen and returns to Advanced (same as the X
  -- button at top-right).
  if UI.back_pressed() then
    api_keys.screen = "settings"
    fx_cache_ui.rescan.status = ""
  end

  ----------------------------------------------------------------
  -- BUILT-IN REFERENCES section (only when user has curated picks).
  -- Docs live in Plugin_Ref.md and the assistant uses them directly,
  -- so rescans never apply. Read-only display with a quiet right-side
  -- "Built-in reference" label.
  ----------------------------------------------------------------
  if #curated_ids > 0 then
    UI.v5_section_label("BUILT-IN REFERENCES")

    _push_fx_card()
    if ImGui.ImGui_BeginChild(RA.ctx, "##fx_curated_card", inner_w, 0,
        ImGui.ImGui_ChildFlags_AutoResizeY() | ImGui.ImGui_ChildFlags_Borders()) then
      local ccard_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      for ri, ident in ipairs(curated_ids) do
        if ri > 1 then
          local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          local sx, sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          ImGui.ImGui_DrawList_AddLine(dl,
            sx, sy, sx + ccard_w, sy,
            (TK.border & 0xFFFFFF00) | 0x28, 1.0)
          Dummy(RA.ctx, 1, RA.SC(4))
        end

        -- Plugin ident (mono SC(10) TK.text) on the row's left.
        local c_row_sx = GetCursorPosX(RA.ctx)
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(10))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
        Text(RA.ctx, ident)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)

        -- "Built-in reference" label on the right, plain text (no pill
        -- background). SameLine puts it on the ident's baseline so it
        -- reads as centered on the row. Mono SC(9) TK.text_faint keeps
        -- it as quiet metadata rather than a badge.
        local LBL = "Built-in reference"
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        local lbl_w = CalcTextSize(RA.ctx, LBL)
        PopFont(RA.ctx)
        SameLine(RA.ctx)
        SetCursorPosX(RA.ctx, c_row_sx + ccard_w - lbl_w)
        PushFont(RA.ctx, FONT.mono_reg, RA.SC(9))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
        Text(RA.ctx, LBL)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        if ImGui.ImGui_IsItemHovered(RA.ctx) then
          UI.tooltip("Curated parameter docs live in "
            .. "Resources/Plugin_Ref.md. The assistant uses those "
            .. "directly. No scan needed and none can be triggered.")
        end
      end
      ImGui.ImGui_EndChild(RA.ctx)
    end
    _pop_fx_card()

    Dummy(RA.ctx, 1, RA.SC(12))
  end

  -- Back button: V5 secondary pill, centered. No Save to pair with since
  -- this page's actions commit immediately, so a single Back reads right.
  Dummy(RA.ctx, 1, RA.SC(14))
  local BACK_W = RA.SC(90)
  SetCursorPosX(RA.ctx,
    GetCursorPosX(RA.ctx) + math_max(math_floor((inner_w - BACK_W) * 0.5), 0))
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(11))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(5))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(14), RA.SC(6))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), TK.card_hover)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
  if ImGui.ImGui_Button(RA.ctx, "Back##fx_cache_back", BACK_W, 0) then
    api_keys.screen = "settings"
    fx_cache_ui.rescan.status = ""
  end
  UI.pressable()
  PopStyleColor(RA.ctx, 5)
  ImGui.ImGui_PopStyleVar(RA.ctx, 3)
  PopFont(RA.ctx)

  -- Bottom margin: breathing room before the footer rail.
  Dummy(RA.ctx, 1, RA.SC(24))

  ImGui.ImGui_Unindent(RA.ctx, cache_indent)
  ImGui.ImGui_EndChild(RA.ctx)
  PopStyleColor(RA.ctx, 4)               -- scrollbar bg + grab + hovered + active
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)     -- ChildBorderSize, WindowPadding
  UI.pop_settings_styles()

  -- V5 footer rail: outside the child, pins to outer window bottom.
  UI.footer_rail_v5()
end

-- =============================================================================
-- Attachment UI renderer
-- =============================================================================
-- Renders the Attach/Screenshot/Paste button row and the attachment
-- queue strip below the prompt input.

-- Display prefix used both in the attachment-strip chips below the prompt
-- and in the user-bubble's natural-width measurement loop in the chat
-- render. Centralising lets a fourth attachment kind be added in one
-- place rather than diverging across the two consumers.
local _ATTACH_KIND_PREFIX = { image = "[IMG] ", pdf = "[PDF] " }
function Attach.kind_prefix(kind)
  return _ATTACH_KIND_PREFIX[kind] or "[TXT] "
end

Attach.render_ui = function(fhs, avail_w)
  -- V5: the old "+" button has been removed. The paperclip icon inside the
  -- prompt row now opens ##attach_menu directly. We keep BeginPopup in this
  -- function because it must be called every frame for the popup to render.

  -- V5 attach-menu styling -- mirrors the model chip popup: mono font at
  -- MONO_SIZE, padded item rows, card bg + strong border, brighter disabled
  -- text. Anchored below the paperclip icon via S._attach_anchor_{x,y}
  -- captured when the user clicked the paperclip.
  local ATT_MONO_SIZE = RA.SC(10)
  if S._attach_anchor_x then
    ImGui.ImGui_SetNextWindowPos(RA.ctx, S._attach_anchor_x, S._attach_anchor_y)
  end
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(8),  RA.SC(8))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(10), RA.SC(6))
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),   RA.SC(8),  RA.SC(4))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(),      TK.card)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),       TK.border_str)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TextDisabled(),
    UI.lerp_u32(TK.text_muted, TK.text, 0.5))
  PushFont(RA.ctx, FONT.mono_med, ATT_MONO_SIZE)
  if ImGui.ImGui_BeginPopup(RA.ctx, "##attach_menu") then
    if ImGui.ImGui_MenuItem(RA.ctx, "Attach File") then
      if reaper.JS_Dialog_BrowseForOpenFiles then
        local ret, paths = reaper.JS_Dialog_BrowseForOpenFiles(
          "Attach files", "", "",
          "All files\0*.*\0",
          true)
        if ret == 1 and paths and paths ~= "" then
          local lines = {}
          for line in paths:gmatch("[^\n]+") do lines[#lines+1] = line end
          if #lines == 1 then
            Attach.file(lines[1])
          else
            local folder = lines[1]
            if folder:sub(-1) ~= RA.SEP and folder:sub(-1) ~= "/" then
              folder = folder .. RA.SEP
            end
            for j = 2, #lines do
              Attach.file(folder .. lines[j])
            end
          end
        end
      else
        S.attach_error = "File picker requires js_ReaScriptAPI.\n"
          .. "Install via ReaPack (Extensions > ReaPack > Browse Packages)."
        S.attach_error_time = time_precise()
      end
    end
    if RA.IS_WINDOWS or RA.IS_MACOS then
      if ImGui.ImGui_MenuItem(RA.ctx, "Screenshot") then
        Attach.screenshot()
      end
      if ImGui.ImGui_MenuItem(RA.ctx, "Paste Image") then
        Attach.clipboard()
      end
    end
    ImGui.ImGui_EndPopup(RA.ctx)
  end
  UI.pop_card_popup_style()

  -- Attachment count and total estimated cost (on its own line)
  if #S.attachments > 0 then
    local total_tokens = 0
    local total_cost = 0
    for _, a in ipairs(S.attachments) do
      total_tokens = total_tokens + a.tokens
      total_cost = total_cost + a.cost
    end
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.DETAIL)
    Text(RA.ctx, str_format("%d file%s (Est. %d tokens, %s, provider may bill differently)",
      #S.attachments, #S.attachments > 1 and "s" or "",
      total_tokens, MODELS.format_cost(total_cost)))
    PopStyleColor(RA.ctx)
  end

  -- Transient error display (auto-fades after 5 seconds)
  if S.attach_error and (time_precise() - S.attach_error_time) < 5 then
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.WARN)
    local short_err = S.attach_error:match("^([^\n]+)") or S.attach_error
    Text(RA.ctx, short_err)
    PopStyleColor(RA.ctx)
  elseif S.attach_error and (time_precise() - S.attach_error_time) >= 5 then
    S.attach_error = nil
  end

  -- Attachment queue strip (shown when files are queued)
  if #S.attachments > 0 then
    ImGui.ImGui_SetCursorPosY(RA.ctx, ImGui.ImGui_GetCursorPosY(RA.ctx) + 2)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), COL.FRAME_BG)
    local strip_h = fhs * 1.3
    ImGui.ImGui_BeginChild(RA.ctx, "##attach_strip", avail_w, strip_h)

    local remove_idx = nil
    for ai, att in ipairs(S.attachments) do
      if ai > 1 then SameLine(RA.ctx, 0, 8) end

      local icon = Attach.kind_prefix(att.kind)

      local display_name = att.name
      if #display_name > 20 then
        display_name = display_name:sub(1, 17) .. "..."
      end

      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(), COL.CODE_BG)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), COL.BTN_HOV)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(), COL.BTN_ACT)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)

      local chip_label = str_format("%s%s##att_%d", icon, display_name, ai)
      ImGui.ImGui_Button(RA.ctx, chip_label, 0, 0)
      UI.tooltip(str_format("%s\n%s, Est. %d tokens (%s)",
        att.name,
        att.kind == "image" and att.media_type or att.kind,
        att.tokens, MODELS.format_cost(att.cost)))

      PopStyleColor(RA.ctx, 4)

      -- X remove button
      SameLine(RA.ctx, 0, RA.SC(2))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.ERROR)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(), 0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), COL.BTN_HOV)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(), COL.BTN_ACT)
      if ImGui.ImGui_Button(RA.ctx, str_format("x##rm_%d", ai), RA.SC(16), 0) then
        remove_idx = ai
      end
      PopStyleColor(RA.ctx, 4)
    end

    ImGui.ImGui_EndChild(RA.ctx)
    PopStyleColor(RA.ctx)  -- ChildBg

    if remove_idx then tbl_remove(S.attachments, remove_idx) end
  end
end

-- ---------------------------------------------------------------------------
-- Render.main_window
-- ---------------------------------------------------------------------------
-- Main ReaAssist ImGui window. Sets up size/pos/constraints, pushes the
-- style stack, calls ImGui_Begin, dispatches to the currently-active
-- screen (tos/first_run/settings/preferred_plugins/fx_cache/custom_llm/
-- custom_providers/help/bug_report/credits) or renders the chat body,
-- balances the pushes, then renders the Update-Available / Repair
-- dialog as a sibling window. The ::after_main_window:: boot-guard
-- label stays local to this function.
--
-- Returns `open` from ImGui_Begin so loop() can detect the X-button
-- close on frames where the window is minimised / collapsed.
function Render.main_window()
  -- Reset the per-frame text-input context-menu counter (see
  -- UI.input_with_menu). Every right-click menu call site claims a
  -- unique popup ID derived from this counter; resetting at the top of
  -- main_window guarantees the same call site gets the same ID across
  -- frames, so an open popup keeps matching its originating field.
  UI._txt_menu_count = 0
  -- Set initial window size on first open; user can freely resize thereafter.
  -- When UI scale changes, re-apply the scaled default size immediately.
  -- Minimum width matches the default so the welcome text never needs to wrap.
  local scale_cond = ImGui.ImGui_Cond_Once()
  if S._prev_ui_scale_idx and S._prev_ui_scale_idx ~= prefs.ui_scale_idx then
    scale_cond = ImGui.ImGui_Cond_Always()
  end
  if S._reset_window_size then
    scale_cond = ImGui.ImGui_Cond_Always()
    S._reset_window_size = false
  end
  S._prev_ui_scale_idx = prefs.ui_scale_idx
  -- At sub-100% scales the scaled window can be a bit too tight; nudge it up.
  local scale_val = CFG.UI_SCALE_OPTIONS[prefs.ui_scale_idx] or 1.0
  local sw_extra = scale_val < 1.0 and 30 or 0
  local sh_extra = scale_val < 1.0 and 50 or 0
  local want_w = RA.SC(CFG.WIN_W) + sw_extra
  local want_h = RA.SC(CFG.WIN_H) + sh_extra
  -- Clamp to monitor work-area saved from the previous frame.
  local max_w = S._monitor_w or math.huge
  local max_h = S._monitor_h or math.huge
  want_w = math.min(want_w, max_w)
  want_h = math.min(want_h, max_h)
  -- Minimum window width -- 600 logical pixels, scaled with the UI scale
  -- factor so smaller UI scales permit proportionally narrower windows.
  -- Minimum window height is handled in the merged constraint below.
  local min_w = math.min(RA.SC(600), max_w)
  -- Restore saved window geometry on first frame; use scaled defaults thereafter.
  if not S._win_pos_restored then
    S._win_pos_restored = true
    local sx = reaper.GetExtState(CFG.EXT_NS, "win_x")
    local sy = reaper.GetExtState(CFG.EXT_NS, "win_y")
    local sw = reaper.GetExtState(CFG.EXT_NS, "win_w")
    local sh = reaper.GetExtState(CFG.EXT_NS, "win_h")
    -- Coerce-with-fallback: a non-empty but non-numeric ExtState value
    -- (corrupted .ini or manual edit) makes tonumber return nil, and
    -- passing nil to SetNextWindowPos / SetNextWindowSize throws -- the
    -- window then fails to open with no clean recovery. Drop a bad pos
    -- silently (ImGui falls back to its default placement) and fall
    -- through to the scaled default size when sw/sh don't parse.
    local nx, ny = tonumber(sx), tonumber(sy)
    if nx and ny then
      ImGui.ImGui_SetNextWindowPos(RA.ctx, nx, ny)
    end
    local nw, nh = tonumber(sw), tonumber(sh)
    if nw and nh then
      ImGui.ImGui_SetNextWindowSize(RA.ctx, math.min(nw, max_w), math.min(nh, max_h))
    else
      ImGui.ImGui_SetNextWindowSize(RA.ctx, want_w, want_h)
    end
  else
    ImGui.ImGui_SetNextWindowSize(RA.ctx, want_w, want_h, scale_cond)
  end
  -- Apply V5 background + default text color. Window is a flat bg (the old
  -- subtle vertical gradient is dropped in favour of the hero band gradient).
  -- Push Inter Regular explicitly so every widget picks up the V5 typeface
  -- instead of Segoe UI / the ReaImGui default.
  PushFont(RA.ctx, FONT.inter_reg, RA.SC(14))
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_WindowBg(),      TK.bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(),       TK.bg)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(),       TK.bg_elev)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TitleBg(),       TK.bg_elev)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_TitleBgActive(), TK.bg_elev)
  -- Hide the thick hover stripe ImGui draws along a window edge when
  -- the user mouses over it for resize. That stripe reads as a glitch
  -- at the V5 polish level. Despite what Col_ResizeGrip* might
  -- suggest, ImGui paints EDGE resize feedback with Col_Separator*
  -- (Hovered / Active) -- those are the two we null out. The corner
  -- grip triangle (Col_ResizeGrip) is left untouched so the corner
  -- affordance stays visible. The window is still resizable from
  -- every edge; only the visual highlight on hover is suppressed.
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_SeparatorHovered(), 0x00000000)
  PushStyleColor(RA.ctx, ImGui.ImGui_Col_SeparatorActive(),  0x00000000)
  -- Suppress the 1px default window border so the hero gradient meets the
  -- Windows title bar cleanly (no faint separator line at the top).
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowBorderSize(), 0)
  -- Zero the main window's vertical padding so the V5 footer rail can sit
  -- flush against the window's bottom edge without ImGui adding an 8px
  -- bottom pad that would otherwise force a scrollbar. Horizontal padding
  -- stays at its default (8) so left/right content keeps its usual gutter.
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), 8, 0)
  -- V5 uses a solid opaque window so the hero gradient reads cleanly; the
  -- old translucent alpha (0.97) let the REAPER UI show through and created
  -- a visible hatched band around the edges.
  ImGui.ImGui_SetNextWindowBgAlpha(RA.ctx, 1.0)
  -- Enforce min width (SC(600)) and min height (SC(400)) together. Two
  -- separate SetNextWindowSizeConstraints calls don't stack -- the second
  -- overwrites the first -- so this merged call must own both axes. The
  -- 400 floor covers the full layout footprint at 1.0x scale: title bar
  -- (~22) + hero band (~122) + session strip (~56) + min chat row + the
  -- bottom reserve (162) computed in the chat block. Anything smaller
  -- and the cursor-flowed mode/model row drifts under the bottom-pinned
  -- footer rail.
  --
  -- Collapse-restore handling. Two cooperating pieces:
  --
  -- 1. While the window was collapsed last frame, suppress the size
  --    constraint. ImGui re-clamps SizeFull against the constraint
  --    every frame, and clicking the title bar of a collapsed window
  --    (which ImGui treats as a potential drag/resize) snaps SizeFull
  --    to (min_w, min_h). With the constraint off during collapse,
  --    that re-clamp can't fire.
  --
  -- 2. ImGui still clobbers SizeFull through other paths during
  --    collapse (we couldn't fully isolate which), so on every
  --    collapsed frame we also force the next Begin's size to the
  --    last size we observed while visible. Cond_Always overrides
  --    whatever ImGui has stored; on the uncollapse frame the window
  --    pops back to its pre-collapse dimensions instead of min.
  --    `_main_pre_collapse_w/h` is updated inside the if-visible
  --    block below (next to the GetWindowSize capture).
  if S._main_was_visible ~= false then
    ImGui.ImGui_SetNextWindowSizeConstraints(RA.ctx, min_w, RA.SC(400), max_w, max_h)
  elseif S._main_pre_collapse_w then
    ImGui.ImGui_SetNextWindowSize(RA.ctx,
      S._main_pre_collapse_w, S._main_pre_collapse_h,
      ImGui.ImGui_Cond_Always())
  end

  -- NoNavInputs: disables arrow-key focus cycling between widgets. Without
  -- it, Up/Down inside a single-line InputText moves focus to the next/prev
  -- widget (breaking autocomplete nav and producing a focus-flash). ReaAssist
  -- doesn't use keyboard nav as a navigation scheme anywhere, so suppressing
  -- it globally is safe.
  local visible, open = ImGui.ImGui_Begin(RA.ctx,
    CFG._PRODUCT .. " v" .. CFG.VERSION, true,
    ImGui.ImGui_WindowFlags_NoNavInputs())

  -- Track collapse state across frames so the size handling above
  -- knows whether to apply constraints or force-restore the
  -- pre-collapse size on the next Begin.
  S._main_was_visible = visible

  if visible then
    -- First-frame boot guard: skip content rendering until the window
    -- has had one frame to settle. When REAPER is under load (multiple
    -- heavy sessions open), the very first frame can paint with
    -- transitional layout values -- GetWindowPos/Size briefly return
    -- stale data before SetNextWindowSize + SetNextWindowPos take
    -- effect, and the hero + capability grid render at the wrong
    -- positions (visible as a brief "broken layout" flash on launch).
    -- One frame of empty bg-colored window is visually smoother than
    -- that flash. The goto exits the visible block, falling through
    -- to the visible-guarded End() below so the boot-skip path still
    -- pairs Begin/End correctly.
    S._boot_frames_shown = (S._boot_frames_shown or 0) + 1
    if S._boot_frames_shown < 2 then
      goto after_main_window
    end

    -- Capture popup state at frame start, before any popup body renders
    -- (and potentially closes itself via its Esc handler). UI.back_pressed
    -- reads this flag so an Esc press inside a popup doesn't also bubble
    -- up as a "go back" action on the underlying screen.
    UI._popup_was_open = ImGui.ImGui_IsPopupOpen(RA.ctx, "",
      ImGui.ImGui_PopupFlags_AnyPopup())

    -- V5 uses a flat window bg (TK.bg). The hero band paints its own gradient
    -- below the title bar, so the whole-window gradient is no longer needed.

    -- Save the current monitor's work-area each frame for next-frame clamping.
    do
      local wx, wy = ImGui.ImGui_GetWindowPos(RA.ctx)
      local cur_w, cur_h = ImGui.ImGui_GetWindowSize(RA.ctx)
      local scr_l, scr_t, scr_r, scr_b = reaper.my_getViewport(
        0, 0, 0, 0,
        wx, wy, wx + cur_w, wy + cur_h,
        true)
      S._monitor_w = scr_r - scr_l
      S._monitor_h = scr_b - scr_t
    end

    -- Escape on the main chat screen: open quit confirmation popup.
    -- Checked at the window level before any child widgets can consume the key.
    -- Only trigger on the main screen (not overlays/settings which handle Escape themselves).
    if not api_keys.screen and not S.show_help and not S.show_bug_report and not S.show_credits then
      -- Escape on the main chat screen: defer popup open to next frame so
      -- the Escape key is released before the popup renders (otherwise the
      -- popup's own Escape handler immediately closes it).
      -- UI._popup_was_open guard so an Escape pressed inside an open popup
      -- (feedback modal, key-test results, etc.) closes that popup without
      -- ALSO triggering the quit confirm here.
      if S._open_quit_confirm == "ready" then
        S._open_quit_confirm = "fire"
      elseif not S._quit_popup_open
        and not UI._popup_was_open
        and ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        S._open_quit_confirm = "ready"
      end
    end

    -- Logo / brand-mark click -> navigate to the home chat screen.
    --
    -- Fired by the clickable wordmark on hero_band_v5 (main chat) +
    -- the wordmark on hero_band_settings_v5 (Settings), and by the
    -- "+ New Chat" chip in the compact hero. Handled HERE, above the
    -- screen dispatcher, so the click works from any screen. If we
    -- consumed the flag inside the dispatcher's `else` branch (main-
    -- chat-only), a click from Settings would set the flag, Settings
    -- would render again next frame, and the flag would stay pending
    -- forever.
    --
    -- Behaviour per source screen:
    --   Settings -> route through S._settings_request_cancel so the
    --               unsaved-changes popup fires if edits are pending.
    --               Conversation stays intact (user may still want it
    --               after deciding about their prefs).
    --   Everywhere else -> hard reset: cancel in-flight request,
    --               clear all screen/modal state, discard any stale
    --               Settings staged buffers, clear conversation.
    if S._logo_click_pending then
      S._logo_click_pending = false
      -- Guard: on the mandatory onboarding screens (TOS accept, first-
      -- run API key entry) the logo click is a no-op. Letting it drop
      -- to main chat would leak the user past onboarding with no keys
      -- configured -- first send would just error. TOS has no clickable
      -- wordmark anyway, so in practice this only gates first-run.
    if not (api_keys.screen == "tos" or api_keys.screen == "first_run") then
      -- Settings special case: route through the existing cancel flow
      -- (S._settings_request_cancel) so the unsaved-changes popup
      -- fires if the user has pending edits. Point the return-to
      -- breadcrumb at "home" so the popup's Save / Discard commit
      -- paths land on the main chat instead of wherever Settings was
      -- opened from (e.g. footer gear from Help would otherwise send
      -- the user back to Help). Conversation stays intact on this
      -- path -- a user still-editing Settings isn't trying to nuke
      -- their chat too. The main-chat wordmark still clears it.
      if api_keys.screen == "settings" then
        S._settings_return_to = {
          screen       = nil,
          show_help    = false,
          show_bug     = false,
          show_credits = false,
        }
        S._settings_request_cancel = true
      else
      -- Cancel any in-flight request so a late response doesn't write
      -- back into the now-cleared conversation.
      if S.status == "waiting" then
        if deep_scan.active then CTX.cancel_deep_scan() end
        Net.kill_curl()
        S.curl_pid            = nil
        S.send_time           = nil
        S.status              = "idle"
        S.pending_display_idx = nil
        S.pending_code        = nil
        S.retry_scheduled     = false
        S.retry_count         = 0
        S.retry_saved_body    = nil
      end
      -- Drop any screen / modal navigation state so the dispatcher
      -- falls through to the main chat branch on the same frame.
      api_keys.screen     = nil
      S.show_help         = false
      S.show_bug_report   = false
      S.show_credits      = false
      -- Discard Settings staged buffers / saved-prefs stash. These
      -- would otherwise keep the old state around and confuse the
      -- next Settings open.
      api_keys.saved_ui_scale_idx         = nil
      api_keys.saved_theme                = nil
      api_keys.saved_update_check         = nil
      api_keys.saved_auto_backup          = nil
      api_keys.saved_chat_font_idx        = nil
      api_keys.saved_include_snapshot     = nil
      api_keys.saved_include_api_ref      = nil
      api_keys.saved_cloud_request_timeout = nil
      api_keys.section_open               = nil
      api_keys.is_reentry                 = false
      api_keys.key_bufs                   = {}
      api_keys.key_errors                 = {}
      api_keys.key_error                  = nil
      api_keys.key_focused                = false
      api_keys.custom_edit                = nil
      -- Clear the nav breadcrumbs the footer toggle-links set when
      -- they open Help/Credits/Settings, so a subsequent toggle from
      -- chat starts with a clean slate.
      S._settings_return_to = nil
      S._footer_help_ret    = nil
      S._footer_credits_ret = nil
      -- Clear the conversation (brand-mark semantics: "return home").
      Net.clear_conversation()
      S.refocus_prompt = true
      end  -- settings-vs-other branch
    end
    end  -- onboarding-screen guard

    -- First-run flow: when api_keys.screen is set, render one of the
    -- full-window onboarding screens INSTEAD of the main UI. The main UI
    -- chat/input/buttons/popups are all skipped until api_keys.screen is
    -- nil. The popup modals stay inside the main-UI branch -- they cannot
    -- be opened while a first-run screen is active because the buttons
    -- that open them are not rendered.
    if api_keys.screen == "tos" then
      Render.tos_screen()
    elseif api_keys.screen == "first_run" then
      Render.first_run_screen()
    elseif api_keys.screen == "settings" then
      Render.settings_screen()
    elseif api_keys.screen == "preferred_plugins" then
      Render.preferred_plugins_screen()
    elseif api_keys.screen == "fx_cache" then
      Render.fx_cache_screen()
    elseif api_keys.screen == "custom_llm" then
      Render.custom_llm_screen()
    elseif api_keys.screen == "custom_providers" then
      Render.custom_providers_screen()
    elseif S.show_help then
      Render.help_screen()
    elseif S.show_bug_report then
      Render.bug_report_screen()
    elseif S.show_credits then
      Render.credits_screen()
    else

    -- V5 hero band (persistent across empty + chat states). Target is
    -- derived from whether any messages exist; UI.transition.tick advances
    -- the phase scalar toward target each frame. The hero reads the eased
    -- phase to morph its wordmark + padding; the capability grid below
    -- uses the raw linear phase for its alpha fade-out.
    local _chat_active = (#S.display_messages > 0)
    UI.transition.target = _chat_active and 1 or 0
    UI.transition.tick()
    local _tphase = UI.transition.phase
    UI.hero_band_v5(_tphase)
    -- (Wordmark / brand-mark click is handled above the screen
    -- dispatcher so the flag fires from any screen, not just here.)
    -- Session strip renders in both home and chat states (persistent
    -- context header, per the V5 chat mockup). The strip's internal layout
    -- is identical in both states; only the hero above it changes height.
    UI.session_strip_v5()

    local avail_w, avail_h = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

    -- Pre-compute the prompt's word-wrapped line count + height so the chat
    -- scroll area below reserves exactly the right amount. When the prompt
    -- grows from 1 -> 2 lines, chat_h shrinks by the same amount -> the
    -- prompt APPEARS to expand UP (its bottom stays pinned to the controls
    -- row, its top moves up).
    local V5_ROW_INSET     = RA.SC(14)
    local V5_BTN_SEND      = RA.SC(44)
    local V5_BTN_GAP       = RA.SC(8)
    local V5_KEYCAP_GUTTER = RA.SC(40)
    local V5_CLIP_W        = RA.SC(32)
    local V5_PROMPT_FONT   = RA.SC(13)
    local V5_card_visual_w = avail_w - (V5_BTN_SEND + V5_BTN_GAP) - V5_ROW_INSET * 2
    local V5_prompt_w      = V5_card_visual_w - V5_KEYCAP_GUTTER
    -- Dynamic expand: widget is 1 line tall by default, 2 lines tall when
    -- the buffer contains a user \n (from Shift+Enter). Bottom stays pinned
    -- to the controls row so the prompt visually expands UP.
    -- Cache the newline count keyed on the input buffer's identity. The
    -- previous code re-walked the entire buffer with gmatch every frame
    -- just to count line breaks, even when the buffer hadn't changed
    -- between frames -- pure waste at 60 fps for a buffer that only
    -- mutates on actual keystrokes.
    local _ibuf = S.input_buf or ""
    if S._line_count_buf ~= _ibuf then
      local n = 1
      for _ in _ibuf:gmatch("\n") do n = n + 1 end
      S._line_count_buf = _ibuf
      S._line_count_val = n
    end
    local V5_line_count = S._line_count_val or 1
    local V5_visible_lines = math_min(V5_line_count, 2)
    local V5_PROMPT_H_1LINE = RA.SC(44)          -- V5 spec single-line height
    -- LINE_BUMP also drives the per-visible-line text-area size (via the
    -- PAD_VERT derivation below). 20px gives ~4px slack over ImGui's 13px
    -- font + line metric, enough to absorb the 1px caret-position variance
    -- that triggers scroll-bouncing on the tight single-line case.
    local V5_LINE_BUMP      = RA.SC(20)
    -- Target height based on current line count. Actual height eases toward
    -- the target over ~300ms so the expand/collapse is smooth.
    local V5_PROMPT_H_TARGET = V5_PROMPT_H_1LINE + (V5_visible_lines - 1) * V5_LINE_BUMP
    S._prompt_h_anim = S._prompt_h_anim or V5_PROMPT_H_TARGET
    local _dt = ImGui.ImGui_GetDeltaTime(RA.ctx)
    -- Exponential-decay lerp. Time constant 0.167s -> ~500ms to reach 95%
    -- of the target (3 time constants). dt clamp prevents hitch jumps.
    local _rate = math_min(1.0, _dt / 0.167)
    S._prompt_h_anim = S._prompt_h_anim + (V5_PROMPT_H_TARGET - S._prompt_h_anim) * _rate
    -- Snap when very close so we don't chase a fractional pixel forever.
    if math_abs(V5_PROMPT_H_TARGET - S._prompt_h_anim) < 0.5 then
      S._prompt_h_anim = V5_PROMPT_H_TARGET
    end
    local V5_PROMPT_H       = math_floor(S._prompt_h_anim + 0.5)
    -- FramePadding.y (total top + bottom). Sized so each visible line has
    -- text area == V5_LINE_BUMP exactly -- caret centres vertically, no
    -- scroll-bounce triggered by the cursor-visibility chase.
    local V5_PAD_VERT       = V5_PROMPT_H_1LINE - V5_LINE_BUMP  -- = 44 - 16 = 28

    -- ------ Chat scroll area ------------------------------------------------
    -- Reserve space for every bottom element (prompt row + 10px gap + mode
    -- row + 10px gap + 32px footer) so the chat child fills the remaining
    -- height exactly and the V5 footer pins to the window bottom. Extra
    -- reserve kicks in when attachments are queued (the strip sits above
    -- the input) or the update indicator is visible.
    local fhs = ImGui.ImGui_GetFrameHeightWithSpacing(RA.ctx)
    local PROMPT_TOP_PAD = 13                             -- Dummy(1, 13) above input row
    local MODE_ROW_H     = RA.SC(22)
    local MODE_ROW_GAP   = RA.SC(10)                         -- gap above AND below the mode row
    local FOOTER_H       = RA.SC(32)
    local bottom_reserve = PROMPT_TOP_PAD + V5_PROMPT_H
                         + MODE_ROW_GAP + MODE_ROW_H + MODE_ROW_GAP
                         + FOOTER_H
                         -- ItemSpacing slack + visible pad at the bottom of
                         -- the footer. 12px comes out of the chat column and
                         -- the other 7px shows as bg below the footer content
                         -- (the bg still extends to win_bottom, so this reads
                         -- as breathing room under the credits row).
                         + RA.SC(31)
    if #S.attachments > 0 then
      bottom_reserve = bottom_reserve + math_floor(fhs * 1.5)
    end
    if update.state == "downloading" or update.state == "rename_retry"
       or update.state == "done" then
      bottom_reserve = bottom_reserve + fhs
    end
    local chat_h = avail_h - bottom_reserve
    if chat_h < fhs then chat_h = fhs end
    -- Theme-aware scrollbar palette for the chat pane. Transparent track
    -- so the main window's vertical gradient continues behind the thumb.
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarBg(),         0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrab(),       COL.SCROLL_GRAB)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabHovered(),COL.SCROLL_GRAB_H)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ScrollbarGrabActive(), COL.SCROLL_GRAB_A)
    -- Transparent child bg so the main window's vertical gradient shows through.
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), 0x00000000)
    local chat_visible = ImGui.ImGui_BeginChild(RA.ctx, "chat", avail_w, chat_h)
    if chat_visible then
    -- Shadow avail_w with the INNER content region so layout accounts for the
    -- vertical scrollbar when it's present (otherwise the right cards get
    -- clipped by the scrollbar when messages are scrolled back to the top).
    local avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)

    -- Bubble layout constants (used by welcome screen and message rendering).
    local BUBBLE_PAD   = 8    -- inner vertical padding inside bubble (px)
    local BUBBLE_IND   = 12   -- left indent inside bubble (px)
    local BUBBLE_GAP   = 32   -- vertical gap between bubbles (px)
    local BUBBLE_RIGHT = 28   -- right margin for user bubble (keeps clear of scrollbar)

    -- V5 capability grid: only rendered when the chat is empty. The
    -- hero band and session strip above already carry the wordmark.
    -- The hero is persistent, so the scrolled-away mini-logo never
    -- shows; force the flag true to keep it hidden.
    S._top_logo_visible = true
    -- Grid alpha: fades out as the home<->chat transition phase climbs. Used
    -- both to multiply Text() output via StyleVar_Alpha and to scale the
    -- alpha byte of DrawList colors (which don't honor StyleVar_Alpha). Click
    -- handling is also gated by this so stale card clicks don't fire while
    -- the grid is almost-invisible.
    local _grid_alpha     = 1 - _tphase
    local _grid_clickable = _grid_alpha > 0.85
    if #S.display_messages == 0 and _grid_alpha > 0.02 then
      -- Cards grouped into three sections so the grid reads as a navigable
      -- capability menu rather than a flat tile wall. Section order reflects
      -- what ReaAssist is most uniquely good at (live session ops) first,
      -- then code generation, then info-only / boundary tiles. Hoisted to
      -- the CAPABILITY_SECTIONS constant at file scope so the static table
      -- is not rebuilt every frame the welcome grid is visible.
      local sections = CAPABILITY_SECTIONS

      -- V5 layout constants. Card grid is 2-col; each section renders a
      -- header strip (mono label + right-side rule) followed by its cards.
      local CONT_PAD_X   = RA.SC(14)
      local CONT_PAD_TOP = RA.SC(4)
      local GAP          = RA.SC(6)
      local CARD_PAD_X    = RA.SC(10)
      local CARD_PAD_Y    = RA.SC(12)                 -- top padding (title row)
      local CARD_PAD_BOT  = RA.SC(9)                  -- bottom padding (below body)
      local CARD_ROUND    = RA.SC(6)
      local DOT_SIZE      = RA.SC(4)
      local DOT_TEXT_GAP  = RA.SC(6)
      local TITLE_SIZE    = RA.SC(11)
      local BODY_SIZE     = RA.SC(10)
      local LABEL_SIZE    = RA.SC(10)
      local HEAD_BODY_GAP = RA.SC(6)                  -- vertical gap title->body
      local BODY_LINE_H   = math_floor(BODY_SIZE * 1.35 + 0.5)
      local card_h        = CARD_PAD_Y + TITLE_SIZE + HEAD_BODY_GAP + BODY_LINE_H * 2 + CARD_PAD_BOT
      local col_w        = math_floor(((avail_w - CONT_PAD_X * 2) - GAP) * 0.5)
      local SECTION_GAP_T = RA.SC(12)                 -- extra breathing room above each header (except the first)
      local SECTION_GAP_B = RA.SC(8)                  -- gap between header and its first card row

      -- Alpha fade for the whole grid block. StyleVar_Alpha multiplies
      -- Text() output; DrawList calls bypass that, so _fade() scales the
      -- alpha byte of every u32 color we hand to DrawList (card fills,
      -- borders, section rules, accent dots). Declared up here -- BEFORE
      -- draw_section_header -- so the header closure captures it lexically;
      -- if _fade were below, the closure would resolve it as a global and
      -- get nil at call time.
      local function _fade(col)
        local a = math_floor((col & 0xFF) * _grid_alpha)
        return (col & 0xFFFFFF00) | a
      end
      PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_Alpha(), _grid_alpha)

      -- Draw a section header (mono text + horizontal rule extending to the
      -- grid's right edge). Positions relative to the current cursor Y.
      local section_dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      local win_x0     = ImGui.ImGui_GetWindowPos(RA.ctx)
      local function draw_section_header(label)
        SetCursorPosX(RA.ctx, CONT_PAD_X)
        PushFont(RA.ctx, FONT.mono_reg, LABEL_SIZE)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
        Text(RA.ctx, label)
        PopStyleColor(RA.ctx)
        PopFont(RA.ctx)
        local _, label_y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
        local label_x2, label_y2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
        local label_mid_y = math_floor((label_y1 + label_y2) * 0.5)
        local rule_x1 = label_x2 + RA.SC(8)
        local rule_x2 = win_x0 + CONT_PAD_X + (avail_w - CONT_PAD_X * 2)
        if rule_x2 > rule_x1 then
          ImGui.ImGui_DrawList_AddLine(section_dl,
            rule_x1, label_mid_y, rule_x2, label_mid_y, _fade(TK.border), 1)
        end
      end

      -- ---- Sectioned capability grid (V5) ----
      Dummy(RA.ctx, 1, CONT_PAD_TOP)
      -- Reuse section_dl (same draw list -- we are still in the main
      -- window scope here, no BeginChild has run since section_dl was
      -- captured above).
      local dl    = section_dl
      local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
      local scr_y = ImGui.ImGui_GetScrollY(RA.ctx)
      local card_can_send = (S.status == "idle" or S.status == "error")
                            and (S.api_key ~= nil or PROVIDERS.active().is_custom)

      local card_uid = 0
      for si, section in ipairs(sections) do
        -- Extra top gap for every header except the first -- the first header
        -- already has CONT_PAD_TOP above it.
        if si > 1 then
          Dummy(RA.ctx, 1, SECTION_GAP_T)
        end
        draw_section_header(section.name)
        Dummy(RA.ctx, 1, SECTION_GAP_B)

        -- Walk this section's cards in 2-column rows.
        local n = #section.cards
        for row_start = 1, n, 2 do
          local row_y = ImGui.ImGui_GetCursorPosY(RA.ctx)
          for c = 0, 1 do
            local idx = row_start + c
            if idx <= n then
              card_uid = card_uid + 1
              local card  = section.cards[idx]
              local title, body, prompt = card[1], card[2], card[3]

              local cx = CONT_PAD_X + c * (col_w + GAP)
              local sx = win_x + cx
              local sy = win_y + row_y - scr_y
              local ex = sx + col_w
              local ey = sy + card_h

              ImGui.ImGui_SetCursorPos(RA.ctx, cx, row_y)
              ImGui.ImGui_InvisibleButton(RA.ctx, "##cap_" .. card_uid, col_w, card_h)
              -- Hover-test + click-handling are BOTH gated on _grid_clickable
              -- so the fading-out grid doesn't capture the hand cursor, tint
              -- to card_hover, or fire prompts while the chat state is
              -- animating in above it.
              local hovered = _grid_clickable and ImGui.ImGui_IsItemHovered(RA.ctx)
              if hovered and card_can_send then
                ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
                if ImGui.ImGui_IsItemClicked(RA.ctx) then
                  S.from_card = true
                  S.input_buf = ""
                  Net.send_to_api(prompt)
                  S.scroll_to_bottom = false
                  S.scroll_to_top = false
                  S.scroll_to_msg = #S.display_messages
                  S.scroll_to_msg_frames = nil
                end
              end

              -- Card fill + border. Colors alpha-faded so the whole tile
              -- dissolves into the main window gradient as _grid_alpha drops.
              local fill = hovered and TK.card_hover or TK.card
              ImGui.ImGui_DrawList_AddRectFilled(dl, sx, sy, ex, ey, _fade(fill), CARD_ROUND)
              ImGui.ImGui_DrawList_AddRect(dl, sx, sy, ex, ey, _fade(TK.border), CARD_ROUND, 0, 1)

              -- Accent dot in the header row. Uses the shared muted-accent
              -- so it ties visually to the pill, toggle "on"s, and send btn.
              local dot_col = TK.accent_ui
              local dot_cy  = sy + CARD_PAD_Y + math_floor(TITLE_SIZE * 0.5)
              local dot_sx  = sx + CARD_PAD_X
              ImGui.ImGui_DrawList_AddRectFilled(dl,
                dot_sx,
                dot_cy - math_floor(DOT_SIZE * 0.5),
                dot_sx + DOT_SIZE,
                dot_cy - math_floor(DOT_SIZE * 0.5) + DOT_SIZE,
                _fade(dot_col))

              -- Title.
              PushFont(RA.ctx, FONT.inter_reg, TITLE_SIZE)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
              ImGui.ImGui_SetCursorPos(RA.ctx,
                cx + CARD_PAD_X + DOT_SIZE + DOT_TEXT_GAP,
                row_y + CARD_PAD_Y - RA.SC(2))
              Text(RA.ctx, title)
              PopStyleColor(RA.ctx)
              PopFont(RA.ctx)

              -- Body (2-line wrap).
              PushFont(RA.ctx, FONT.inter_reg, BODY_SIZE)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
              ImGui.ImGui_SetCursorPos(RA.ctx,
                cx + CARD_PAD_X,
                row_y + CARD_PAD_Y + TITLE_SIZE + HEAD_BODY_GAP)
              ImGui.ImGui_PushTextWrapPos(RA.ctx, cx + col_w - CARD_PAD_X)
              Text(RA.ctx, body)
              ImGui.ImGui_PopTextWrapPos(RA.ctx)
              PopStyleColor(RA.ctx)
              PopFont(RA.ctx)
            end
          end
          ImGui.ImGui_SetCursorPosY(RA.ctx, row_y + card_h + GAP)
        end
      end
      -- Register the final cursor Y with ImGui's layout system. The last row
      -- advanced the cursor via SetCursorPosY but never submitted an item at
      -- the new Y; ImGui's BeginChild bounds check warns otherwise.
      Dummy(RA.ctx, 1, 0)
      -- Close the StyleVar_Alpha push that wraps the entire grid block above.
      ImGui.ImGui_PopStyleVar(RA.ctx)
    end

    -- Render each message in the conversation.
    -- Message bubble layout:
    --   User messages: right-aligned bubble, max 72% of window width, rounded.
    --   Assistant messages: full-width, flush left, square corners.
    --   Both use DrawList_AddRectFilled drawn BEFORE content so rects render
    --   behind widgets without draw-order issues (no BeginChild needed).
    local chat_font_px = CFG.CHAT_FONT_SIZES[prefs.chat_font_idx] or 14
    PushFont(RA.ctx, nil, RA.SC(chat_font_px))
    local USER_MAX_W   = math_floor(avail_w * 0.72) - BUBBLE_RIGHT  -- max user bubble width
    local LABEL_H      = ImGui.ImGui_GetFrameHeightWithSpacing(RA.ctx)

    local scroll_to_msg_y = nil  -- captured Y for smooth-scroll target
    for i, msg in ipairs(S.display_messages) do
      -- Extra gap between turns (larger than default Spacing).
      ImGui.ImGui_SetCursorPosY(RA.ctx, ImGui.ImGui_GetCursorPosY(RA.ctx) + BUBBLE_GAP)

      -- Capture scroll target position (content Y, not screen Y).
      if S.scroll_to_msg and i == S.scroll_to_msg then
        scroll_to_msg_y = ImGui.ImGui_GetCursorPosY(RA.ctx) - BUBBLE_GAP
      end

      if msg.role == "user" then
        -- User bubble: right-aligned, auto-sized to content up to USER_MAX_W.
        -- V5 layout: details (model/tokens/cost/etc.) are rendered OUTSIDE the
        -- bubble in a two-column mono details card below, not inflated into
        -- the bubble height, so the bubble stays visually clean regardless
        -- of show_details.
        local USER_MIN_W = RA.SC(40)          -- floor for tiny messages; small so short prompts hug their content instead of sitting in an over-sized bubble with asymmetric padding
        -- Measure the message content's natural width (max line width with
        -- no wrapping). CalcTextSize respects \n for multi-line input.
        -- Cache the result on the message itself: msg.content is immutable
        -- once added, and previously every visible user bubble re-measured
        -- it every frame plus every attachment width per attachment per
        -- frame -- an O(messages * attachments) tax for invariant data.
        -- Invalidate on font_idx change so a chat-font swap rebuilds.
        local _w_key = prefs.chat_font_idx or 2
        if msg._natural_content_w == nil or msg._natural_content_w_key ~= _w_key then
          local nw = 0
          if msg.content and msg.content ~= "" then
            nw = CalcTextSize(RA.ctx, msg.content)
          end
          if msg.attach_names then
            for _, aname in ipairs(msg.attach_names) do
              local is_img = aname:match("%.png$") or aname:match("%.jpg$")
                          or aname:match("%.jpeg$") or aname:match("%.gif$")
                          or aname:match("%.webp$") or aname == "Screenshot"
                          or aname == "Clipboard image"
              local kind = is_img and "image"
                or (aname:match("%.pdf$") and "pdf" or "text")
              local prefix = Attach.kind_prefix(kind)
              local aw = CalcTextSize(RA.ctx, prefix .. aname)
              if aw > nw then nw = aw end
            end
          end
          msg._natural_content_w = nw
          msg._natural_content_w_key = _w_key
        end
        local natural_content_w = msg._natural_content_w
        -- NOTE: BUBBLE_IND * 3, not * 2. The bubble's rendering path
        -- double-indents the text (Indent left_offset+BUBBLE_IND, then
        -- Indent BUBBLE_IND) and passes selectable_text a wrap width of
        -- `content_w - BUBBLE_IND` -- so the actual text area inside the
        -- bubble is `bubble_w - 3 * BUBBLE_IND`. Using only 2 * BUBBLE_IND
        -- here undersizes the bubble by one BUBBLE_IND, which causes short
        -- single-line prompts to wrap onto a second line that gets clipped
        -- by bubble_h (sized for msg_h at content_w, not at the narrower
        -- actual text area). +4 is a small safety buffer for subpixel math.
        -- V5 user bubble padding: equal on all four sides so the text sits
        -- centred both horizontally and vertically. USER_PAD_H drives
        -- bubble_w; short messages hug their content at natural width, and
        -- long wrapped messages hug the ACTUAL wrapped max line width (not
        -- the USER_MAX_W cap) so the bubble doesn't leave a visible right
        -- gap when word-wrap finishes shorter than the cap.
        local USER_PAD_H = 18
        local USER_PAD_V = 6
        local natural_bubble_w = natural_content_w + USER_PAD_H * 2
        local bubble_w
        -- bubble_cpl: chars_per_line to use for BOTH the measurement phase
        -- below and the render phase (passed into selectable_text). Keeping
        -- them identical is what makes the bubble hug the wrapped content
        -- without a right-side gap; if they differ, the render re-wraps
        -- tighter than measured and the bubble ends up too wide.
        local bubble_cpl
        if natural_bubble_w <= USER_MAX_W then
          -- Fits on one line -- natural width hugs content exactly. No wrap
          -- needed, no cpl override (selectable_text will no-op the wrap).
          bubble_w = math_max(USER_MIN_W, natural_bubble_w)
        else
          -- Content needs wrapping. Pick chars_per_line from the max width,
          -- wrap with it, measure each line's real pixel width, then size
          -- the bubble to hug the widest line. The same cpl is threaded into
          -- selectable_text below so render == measurement.
          local wrap_at = USER_MAX_W - USER_PAD_H * 2
          local avg_char_w = ImGui.ImGui_GetFontSize(RA.ctx) * 0.48
          bubble_cpl = math_floor(math_max(wrap_at / avg_char_w, 20))
          -- Cache max_line_w / bubble_w on the message keyed on the inputs
          -- that affect them: bubble_cpl (which already absorbs font-size
          -- changes via avg_char_w above), chat_font_idx (paranoia for
          -- callers that tweak font without touching cpl), and
          -- ui_scale_idx (RA.SC inside the bubble_w formula). Skipping
          -- the per-line CalcTextSize loop is the win on long messages
          -- with many wrapped lines, where N visible bubbles * N lines *
          -- 60fps was the dominant cost.
          local _font_idx  = prefs.chat_font_idx or 2
          local _scale_idx = prefs.ui_scale_idx or 3
          if msg._bubble_w == nil
             or msg._bubble_w_cpl   ~= bubble_cpl
             or msg._bubble_w_font  ~= _font_idx
             or msg._bubble_w_scale ~= _scale_idx then
            local _, _, wrap_lines = UI.get_wrap_cached(msg.content, bubble_cpl)
            local max_line_w = 0
            for i = 1, #wrap_lines do
              local line = wrap_lines[i]
              if #line > 0 then
                local lw = CalcTextSize(RA.ctx, line)
                if lw > max_line_w then max_line_w = lw end
              end
            end
            msg._bubble_w = math_max(USER_MIN_W,
                            math_min(USER_MAX_W,
                                     max_line_w + USER_PAD_H * 2 + RA.SC(2)))
            msg._bubble_w_cpl   = bubble_cpl
            msg._bubble_w_font  = _font_idx
            msg._bubble_w_scale = _scale_idx
          end
          bubble_w = msg._bubble_w
        end
        local content_w = bubble_w - USER_PAD_H * 2
        -- Two adjustments to measure_stripped_height's return:
        --   (a) Pass `bubble_cpl or 99999` so the no-wrap path forces the
        --       measurement to NOT wrap. Without this override, measure's
        --       internal chars_per_line derives from content_w/avg_char_w
        --       and the avg_char_w approximation over-estimates character
        --       width -- causing measure to falsely wrap text that actually
        --       fits on one line at render. That was the phantom-bottom-gap
        --       bug on one-line messages wider than ~50 chars.
        --   (b) Subtract 4 to account for measure's trailing-ItemSpacing
        --       assumption (line_count * (line_h + 2) + 2) that plain Text()
        --       doesn't actually emit for the final line.
        -- Strip markdown once per frame and cache on the message; the render
        -- block below reads the cached stripped string instead of stripping
        -- again -- previously the stripping happened in two places at 60 fps
        -- for every visible user message. The cache entry invalidates when
        -- msg.content changes (edits; streaming doesn't apply to user
        -- bubbles).
        local raw_src = msg.content or ""
        if msg._stripped_src ~= raw_src then
          msg._stripped_src = raw_src
          msg._stripped     = UI.strip_markdown(raw_src)
          msg._layout_key   = nil  -- content changed: invalidate layout cache
        end
        local stripped  = msg._stripped
        -- Cache measured height + wrapped render text keyed on
        -- (stripped-identity, content_w, bubble_cpl). Scrolling a long chat
        -- re-enters this branch every frame for every visible message; the
        -- cache drops that from two cache lookups + two ImGui calls per
        -- message per frame to a single string-compare.
        local layout_key = content_w .. ":" .. (bubble_cpl or "x")
        if msg._layout_key ~= layout_key then
          msg._layout_key     = layout_key
          msg._layout_height  = UI.measure_stripped_height(stripped, content_w, bubble_cpl or 99999) - 4
          if bubble_cpl then
            local ws, _, wl = UI.get_wrap_cached(stripped, bubble_cpl)
            msg._layout_wrapped = ws
            msg._layout_lines   = wl
          else
            -- No wrap: single-segment path. Still build the lines array
            -- so the render loop below can take the common ipairs path
            -- instead of branching on the cache shape.
            msg._layout_wrapped = stripped
            local single = {}
            local n = 0
            for line in (stripped .. "\n"):gmatch("(.-)\n") do
              n = n + 1
              single[n] = line
            end
            if n == 0 then single[1] = "" end
            msg._layout_lines = single
          end
        end
        local msg_h     = msg._layout_height
        local bubble_h  = msg_h + USER_PAD_V * 2
        -- Account for attachment indicator lines in bubble height.
        if msg.attach_names and #msg.attach_names > 0 then
          local line_h = ImGui.ImGui_GetTextLineHeightWithSpacing(RA.ctx)
          bubble_h = bubble_h + line_h * #msg.attach_names + 4  -- +4 for spacing
        end

        -- Position cursor at the right edge so the bubble is flush right.
        local left_offset = avail_w - bubble_w - BUBBLE_RIGHT
        SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + left_offset)
        local bx, by = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
        local _, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
        local bubble_bottom_y = by + bubble_h  -- screen Y of bubble bottom
        local dl_u = ImGui.ImGui_GetWindowDrawList(RA.ctx)

        -- V5 user bubble: per-theme fill / border / text tokens so light
        -- mode reads as "near-white card with accent-coloured text + subtle
        -- accent outline" and dark mode reads as "muted blue tinted tile
        -- with bright text". Asymmetric rounding (10 px on TL / TR / BL;
        -- square on BR) keeps the chat-tail convention.
        local BUBBLE_ROUND = RA.SC(10)
        local BUBBLE_ROUND_FLAGS =
            ImGui.ImGui_DrawFlags_RoundCornersTopLeft()
          | ImGui.ImGui_DrawFlags_RoundCornersTopRight()
          | ImGui.ImGui_DrawFlags_RoundCornersBottomLeft()
        ImGui.ImGui_DrawList_AddRectFilled(dl_u,
          bx, by, bx + bubble_w, by + bubble_h,
          TK.user_bg, BUBBLE_ROUND, BUBBLE_ROUND_FLAGS)
        ImGui.ImGui_DrawList_AddRect(dl_u,
          bx, by, bx + bubble_w, by + bubble_h,
          TK.user_border, BUBBLE_ROUND, BUBBLE_ROUND_FLAGS, 1)

        -- Plain Text() per wrapped line, not selectable_text. Rationale:
        -- UI.selectable_text wraps InputTextMultiline, whose internal
        -- child window + scrollbar + frame padding layers can't all be
        -- styled away and leave a stubborn asymmetric right gap. Plain
        -- Text() has no hidden padding.
        --
        -- Three things must match UI.measure_stripped_height exactly so
        -- the bubble height we pre-computed lines up with rendering:
        --   (1) the same strip_markdown pass on the text
        --   (2) the same wrap via UI.get_wrap_cached(bubble_cpl)
        --   (3) ItemSpacing.y pushed to 2 so each Text() advances by
        --       (line_height + 2) -- matching measure's line_h formula
        ImGui.ImGui_Indent(RA.ctx, left_offset + USER_PAD_H)
        -- Push ItemSpacing BEFORE Dummy so the Dummy's trailing spacing
        -- matches what Text() uses below. Otherwise Dummy uses default
        -- ItemSpacing.y (~4) and Text uses 2.
        -- Dummy height = USER_PAD_V - 2 because the pushed ItemSpacing (2)
        -- contributes to the top gap too -- so Dummy(USER_PAD_V - 2) +
        -- ItemSpacing(2) = USER_PAD_V total top pad, matching the
        -- bubble_h's bottom margin computation (which has no trailing
        -- ItemSpacing after the final text line).
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.user_text)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(), 0, 2)
        Dummy(RA.ctx, 1, USER_PAD_V - 2)
        do
          -- Pull the per-line array from the message's layout cache.
          -- Previously we walked msg._layout_wrapped with gmatch per
          -- frame, which allocated a full bubble-sized working string
          -- on every user-bubble render. The cached array makes the
          -- hot path a plain ipairs walk.
          local ws_lines = msg._layout_lines
          for li = 1, #ws_lines do
            local line = ws_lines[li]
            if #line == 0 then
              Dummy(RA.ctx, 1, ImGui.ImGui_GetTextLineHeight(RA.ctx))
            else
              Text(RA.ctx, line)
            end
          end
        end
        ImGui.ImGui_PopStyleVar(RA.ctx)
        PopStyleColor(RA.ctx)

        -- Right-click anywhere on the bubble -> Copy menu. Manual hit-test
        -- against the bubble's screen rect so we don't need an overlay
        -- InvisibleButton (which would mess with the cursor positioning
        -- we carefully set above). Popup styling matches the V5 provider /
        -- model dropdowns: TK.card fill, strong border, mono-med font, SC
        -- padding -- so context menus read as one visual family across the
        -- whole chat surface.
        do
          local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
          local popup_id = "##umenu_" .. i
          if mx >= bx and mx <= bx + bubble_w
             and my >= by and my <= by + bubble_h
             and ImGui.ImGui_IsMouseClicked(RA.ctx, 1) then
            ImGui.ImGui_OpenPopup(RA.ctx, popup_id)
          end
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), RA.SC(8),  RA.SC(8))
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),  RA.SC(10), RA.SC(6))
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(),   RA.SC(8),  RA.SC(4))
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(), RA.SC(4))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_PopupBg(), TK.card)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),  TK.border_str)
          PushFont(RA.ctx, FONT.mono_med, RA.SC(10))
          if ImGui.ImGui_BeginPopup(RA.ctx, popup_id) then
            if ImGui.ImGui_MenuItem(RA.ctx, "Copy") then
              ImGui.ImGui_SetClipboardText(RA.ctx, msg.content or "")
            end
            ImGui.ImGui_EndPopup(RA.ctx)
          end
          PopFont(RA.ctx)
          PopStyleColor(RA.ctx, 2)
          ImGui.ImGui_PopStyleVar(RA.ctx, 4)
        end

        -- Attachment indicator: show file names below the message text.
        if msg.attach_names and #msg.attach_names > 0 then
          ImGui.ImGui_Spacing(RA.ctx)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.DETAIL)
          for _, aname in ipairs(msg.attach_names) do
            local icon = aname:match("%.png$") or aname:match("%.jpg$") or
                         aname:match("%.jpeg$") or aname:match("%.gif$") or
                         aname:match("%.webp$") or aname == "Screenshot" or
                         aname == "Clipboard image"
            local prefix = icon and "[IMG] " or
                           aname:match("%.pdf$") and "[PDF] " or "[TXT] "
            Text(RA.ctx, prefix .. aname)
          end
          PopStyleColor(RA.ctx)
        end

        ImGui.ImGui_Unindent(RA.ctx, left_offset + USER_PAD_H)
        -- Force cursor to the true bottom of the drawn bubble rect so the
        -- details pill (below, if show_details is on) or next element always
        -- clears the bubble's geometry.
        local scroll_y = ImGui.ImGui_GetScrollY(RA.ctx)
        ImGui.ImGui_SetCursorPosY(RA.ctx, bubble_bottom_y - win_y + scroll_y)

        -- V5 details card: mono label/value rows in a rounded container,
        -- right-aligned below the bubble. Single-column layout so every
        -- value gets the full container width -- no wrapping into awkward
        -- second lines, and labels/values align cleanly on every row.
        --
        -- Readability hooks: labels render in TK.text_faint (quieter), values
        -- in TK.text_muted (more prominent); labels are space-padded to the
        -- list's max label length so values all start at the same x. Large
        -- integers get thousands separators for magnitude scanning + digit
        -- legibility. Container background is 50% transparent so the chat
        -- bg gradient shows through.
        if prefs.show_details and msg.ctx_label then
          -- DETAILS_W is computed below after measuring the natural width
          -- of every row -- the card hugs its content and only hits the
          -- USER_MAX_W cap when a row (usually Context with many buckets)
          -- needs to wrap. Padding + rounding + font are fixed up-front.
          local DETAILS_PAD_V  = RA.SC(8)
          local DETAILS_PAD_H  = RA.SC(12)
          local DETAILS_ROUND  = RA.SC(6)
          local ROW_GAP        = 2
          -- Font size tracks Chat Font pref: Small=9, Medium=11,
          -- Large=13 px (before DPI scaling). Falls back to 11 if the
          -- pref index is out of range.
          local FONT_SIZE      = RA.SC(CFG.DETAILS_FONT_SIZES[prefs.chat_font_idx] or 11)

          -- fmt_num (integer with thousands separators, e.g. 47414 ->
          -- "47,414") is hoisted to file scope near the top of this
          -- file so the details card does not re-create the closure
          -- per message per frame.

          -- Build name -> value map of present fields.
          -- Context aliases: "snapshot" reads as "Session" and "api_ref" as
          -- "API" so the context string uses user-facing vocabulary instead
          -- of internal bucket identifiers. Tokens + Cache values use a
          -- compact "X / Y" form (first = input/read, second = output/created)
          -- so both fit on a single line inside a paired column instead of
          -- wrapping onto a second row.
          -- Context label + model pill are static once the message lands,
          -- so cache the gsub chains on the message. Runs once per message
          -- rather than per frame the details card is open, which on a
          -- long conversation is the difference between a handful of
          -- gsubs per frame and zero.
          --
          -- The whole field_map / color_map is also cached on the message
          -- with per-input stamps -- post-completion, msg.tok_in /
          -- response_time / cost / cache counters / thinking / fx_cache
          -- never change, and ctx_label / model_label only flip on edge
          -- cases (and have their own _src checks anyway). For a long
          -- conversation with details on, this drops ~9 small string
          -- allocs + the rows-array build per visible bubble per frame
          -- to one nil-equality test chain. UI.invalidate_palette_caches
          -- nulls these on theme switch since color_map embeds u32 from
          -- TK.accent.
          if msg._details_field_map        == nil
             or msg._details_fm_ctx       ~= msg.ctx_label
             or msg._details_fm_model     ~= msg.model_label
             or msg._details_fm_tok_in    ~= msg.tok_in
             or msg._details_fm_tok_out   ~= msg.tok_out
             or msg._details_fm_cost      ~= msg.cost
             or msg._details_fm_free_tier ~= msg.free_tier
             or msg._details_fm_resp_time ~= msg.response_time
             or msg._details_fm_cache_r   ~= msg.tok_cache_read
             or msg._details_fm_cache_c   ~= msg.tok_cache_create
             or msg._details_fm_thinking  ~= msg.thinking_label
             or msg._details_fm_fx_cache  ~= msg.fx_cache_label
             or msg._details_fm_api_calls ~= msg.api_calls then
            if msg._ctx_display_src ~= msg.ctx_label then
              msg._ctx_display_src = msg.ctx_label
              msg._ctx_display     = (msg.ctx_label
                :gsub("snapshot", "Session")
                :gsub("api_ref",  "API"))
            end
            local field_map = {}
            field_map["Context"] = msg._ctx_display
            if msg.model_label then
              if msg._model_display_src ~= msg.model_label then
                msg._model_display_src = msg.model_label
                msg._model_display     = msg.model_label:gsub(" %b()", "")
              end
              field_map["Model"] = msg._model_display
            end
            if msg.tok_in and msg.cost and (msg.cost > 0 or msg.free_tier) then
              -- "~" prefix marks the value as approximate (matches the "Est."
              -- in the label -- belt-and-suspenders so scanning either side
              -- makes the estimation clear). Free-tier Gemini exchanges cost
              -- the user $0 on the actual API bill, but the token math still
              -- produces a number; frame it as "would have been" so the user
              -- sees the break they're getting without being confused into
              -- thinking they're being charged. A flat-zero cost with no
              -- free-tier flag means the active model has no per-token
              -- prices entered (local llama.cpp, custom OpenAI-compatible
              -- endpoint with empty price fields, etc.); the row would just
              -- read "~$0.000000" so we drop it entirely.
              if msg.free_tier then
                field_map["Est. Cost"] = "Free Tier (would have been ~"
                  .. MODELS.format_cost(msg.cost) .. ")"
              else
                field_map["Est. Cost"] = "~" .. MODELS.format_cost(msg.cost)
              end
            end
            if msg.tok_in then
              field_map["Tokens"] = str_format("%s in / %s out",
                fmt_num(msg.tok_in), fmt_num(msg.tok_out))
            end
            if msg.response_time then
              field_map["Time"] = str_format("%.1fs", msg.response_time)
            end
            do
              local cr = msg.tok_cache_read   or 0
              local cc = msg.tok_cache_create or 0
              if cr > 0 or cc > 0 then
                field_map["Cache"] = str_format("%s read, %s created",
                  fmt_num(cr), fmt_num(cc))
              end
            end
            if msg.thinking_label then
              field_map["Thinking"] = msg.thinking_label
            end
            if msg.fx_cache_label then
              field_map["FX Cache"] = msg.fx_cache_label
            end
            -- Always render the API Calls row when the counter is set:
            -- "1" is positive confirmation that no silent retry fired
            -- (no docs-gate, no beta-fallback, no cache-expiry refresh),
            -- which is itself useful signal -- otherwise the user can't
            -- tell whether the visible Tokens / Cache / Time / Cost are
            -- the whole story or just the last of N requests. >1 still
            -- carries the "visible numbers undercount" warning per the
            -- field tooltip.
            if msg.api_calls then
              field_map["API Calls"] = tostring(msg.api_calls)
            end

            -- Per-field value colour overrides. Est. Cost and Est. Total
            -- use a darkened accent -- the "receipt" lines visually weighted
            -- against the rest of the muted metadata. Est. Total's color is
            -- cached unconditionally because the row's value is computed
            -- per-frame outside the field_map cache (so the cumulative stays
            -- accurate if a prior turn's cost ever changes), but the colour
            -- itself is constant per palette.
            local accent_dk = UI.lerp_u32(TK.accent, 0x000000FF, 0.18)
            local color_map = {}
            if field_map["Est. Cost"] then color_map["Est. Cost"] = accent_dk end
            color_map["Est. Total"] = accent_dk

            msg._details_field_map    = field_map
            msg._details_color_map    = color_map
            msg._details_fm_ctx       = msg.ctx_label
            msg._details_fm_model     = msg.model_label
            msg._details_fm_tok_in    = msg.tok_in
            msg._details_fm_tok_out   = msg.tok_out
            msg._details_fm_cost      = msg.cost
            msg._details_fm_free_tier = msg.free_tier
            msg._details_fm_resp_time = msg.response_time
            msg._details_fm_cache_r   = msg.tok_cache_read
            msg._details_fm_cache_c   = msg.tok_cache_create
            msg._details_fm_thinking  = msg.thinking_label
            msg._details_fm_fx_cache  = msg.fx_cache_label
            msg._details_fm_api_calls = msg.api_calls
          end
          local field_map = msg._details_field_map
          local color_map = msg._details_color_map

          -- Hoisted lookup tables (file-scope constants near top of file)
          -- replace the per-frame table literals: _DETAILS_GROUP_OF for the
          -- "decision/context/usage/cost/reasoning" row groupings,
          -- _DETAILS_ROW_ORDER for the canonical order, and
          -- _DETAILS_FIELD_TOOLTIPS for the hover help.
          local group_of = _DETAILS_GROUP_OF
          local row_order = _DETAILS_ROW_ORDER
          -- Hide the Time and Est. Cost rows while this turn is still in
          -- flight. Both are set from per-call usage (msg.response_time,
          -- msg.cost) which gets overwritten on every API call within
          -- the turn. On a multi-call turn (docs-gate retry, intra-turn
          -- context_needed fetch), the cached values reflect the LAST
          -- completed call, not the in-flight one -- so Time freezes at
          -- e.g. "18.2s" while live "Thinking" climbs to "0:49", and
          -- Est. Cost shows a partial number that ticks up later. The
          -- final response_time (computed from time_precise() -
          -- S.request_start_time, with request_start_time preserved
          -- across intra-turn retries) and final cost already reflect
          -- the full turn, so when the rows reappear they match.
          local hide_inflight = (S.status == "waiting"
                                 and S.pending_display_idx == i
                                 and S.request_start_time)

          -- Running total cost across every turn up to and including this
          -- one. Computed per-frame (instead of folded into the cached
          -- field_map) so that if a prior turn's cost is ever rebuilt --
          -- e.g. via the Retry button -- this row reflects the new sum
          -- without needing to invalidate every downstream message's
          -- cache. Cheap: O(i) additions, ~once per visible bubble per
          -- frame. Hidden on turn 1 (count == 1) since it would just
          -- duplicate Est. Cost and clutter the card.
          local total_cost_value = nil
          if msg.tok_in and msg.cost then
            local total, count = 0, 0
            for j = 1, i do
              local pm = S.display_messages[j]
              if pm and pm.cost then
                total = total + pm.cost
                count = count + 1
              end
            end
            -- Suppress Est. Total when the running sum is 0 -- e.g. every
            -- turn so far ran on a local/custom model with no per-token
            -- prices entered, so a "this chat: $0.000000" line would just
            -- mirror the (already hidden) Est. Cost rows.
            if count > 1 and total > 0 then
              total_cost_value = "~" .. MODELS.format_cost(total)
            end
          end

          -- Each row is { label, value, suffix? }. The optional suffix is
          -- a faint-colour qualifier rendered after the value (e.g. the
          -- receipt rows tag "(this turn)" / "(this chat)" so users can
          -- tell the per-message Est. Cost from the running Est. Total at
          -- a glance without reading the tooltip). Free Tier wording
          -- already explains itself, so we skip the suffix in that case.
          local rows = {}
          for _, name in ipairs(row_order) do
            local hide = hide_inflight
              and (name == "Time" or name == "Est. Cost" or name == "Est. Total")
            if not hide then
              local value, suffix
              if name == "Est. Total" then
                value  = total_cost_value
                suffix = value and "(this chat)" or nil
              elseif name == "Est. Cost" then
                value = field_map[name]
                if value and not msg.free_tier then
                  suffix = "(this turn)"
                end
              else
                value = field_map[name]
              end
              if value then
                rows[#rows+1] = { name, value, suffix }
              end
            end
          end

          -- Max label length across ALL rows so every value starts at the
          -- same x. Mono font makes this pixel-exact via char_w * (max + 1).
          local max_lbl = 0
          for _, r in ipairs(rows) do
            if #r[1] > max_lbl then max_lbl = #r[1] end
          end

          -- Pre-measure heights so the container rect matches content.
          PushFont(RA.ctx, FONT.mono_reg, FONT_SIZE)
          local line_h = ImGui.ImGui_GetTextLineHeight(RA.ctx) + ROW_GAP
          local char_w = CalcTextSize(RA.ctx, "M")
          local function wrap_h(text, wrap_w)
            local _, h = CalcTextSize(RA.ctx, text, nil, nil, false, wrap_w)
            return math_max(line_h, h + ROW_GAP)
          end
          local label_px = char_w * (max_lbl + 1)
          -- Auto-size the card width to its widest row. The card only hits
          -- the USER_MAX_W cap when a row (e.g. Context with many buckets)
          -- is naturally longer than that max -- in which case it wraps
          -- inside. Short-content cards hug tightly.
          -- Suffix gap: tight space between the value and the faint-colour
          -- qualifier so they read as one phrase ("~$0.10 (this turn)")
          -- rather than separate columns. Matches the ItemSpacing.x used
          -- elsewhere in the card via SameLine below.
          local SUFFIX_GAP = RA.SC(4)
          local max_row_natural_w = 0
          for _, r in ipairs(rows) do
            local vw = CalcTextSize(RA.ctx, r[2])
            if r[3] then
              vw = vw + SUFFIX_GAP + CalcTextSize(RA.ctx, r[3])
            end
            local rw = label_px + vw
            if rw > max_row_natural_w then max_row_natural_w = rw end
          end
          local DETAILS_W = math_min(USER_MAX_W,
            max_row_natural_w + DETAILS_PAD_H * 2 + RA.SC(4))
          local full_w = DETAILS_W - DETAILS_PAD_H * 2
          local value_w = full_w - label_px
          local DIVIDER_SPACE = RA.SC(7)   -- 3 px gap + 1 px line + 3 px gap
          local content_h = 0
          do
            local prev_group
            for _, r in ipairs(rows) do
              local g = group_of[r[1]]
              if prev_group and g ~= prev_group then
                content_h = content_h + DIVIDER_SPACE
              end
              -- Measure value + suffix as one combined string so a row
              -- whose tail wraps still gets the right height. In practice
              -- the cost rows fit on one line, but Context-style long
              -- values would otherwise undercount.
              local meas = r[3] and (r[2] .. " " .. r[3]) or r[2]
              content_h = content_h + wrap_h(meas, value_w)
              prev_group = g
            end
          end
          local details_h = content_h + DETAILS_PAD_V * 2
          PopFont(RA.ctx)

          -- Gap above + container rect (right-aligned to the bubble's right
          -- edge). Fill alpha is halved so the chat bg shows through.
          Dummy(RA.ctx, 1, RA.SC(6))
          local details_left_offset = avail_w - DETAILS_W - BUBBLE_RIGHT
          local d_sx, d_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          d_sx = d_sx + details_left_offset
          ImGui.ImGui_DrawList_AddRectFilled(dl_u,
            d_sx, d_sy, d_sx + DETAILS_W, d_sy + details_h,
            TK.details_bg, DETAILS_ROUND)
          ImGui.ImGui_DrawList_AddRect(dl_u,
            d_sx, d_sy, d_sx + DETAILS_W, d_sy + details_h,
            TK.border, DETAILS_ROUND, 0, 1)

          -- Render. Label + value are two Text calls with different colours
          -- so values read as the primary info; mono char-width alignment
          -- positions every value at the same x.
          local start_local_x = GetCursorPosX(RA.ctx)
          local start_local_y = ImGui.ImGui_GetCursorPosY(RA.ctx)
          local row_x         = start_local_x + details_left_offset + DETAILS_PAD_H
          local cursor_y      = start_local_y + DETAILS_PAD_V

          PushFont(RA.ctx, FONT.mono_reg, FONT_SIZE)
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(), 8, ROW_GAP)

          -- Hoisted to file scope (_DETAILS_FIELD_TOOLTIPS) so the 9-entry
          -- table isn't reallocated every frame for every visible bubble.
          local field_tooltips = _DETAILS_FIELD_TOOLTIPS

          -- Draw a single label + value pair, then overlay an InvisibleButton
          -- on the full field rect so hovering anywhere on the row triggers
          -- the field's tooltip via UI.tooltip_v5 (300 ms delay, consistent
          -- with the rest of the V5 UI). The button is drawn LAST so its
          -- rect is the "last item" that IsItemHovered checks against.
          -- `value_color` overrides the default TK.text_muted for the value
          -- -- used for Complexity's tier colour and Est. Cost's accent.
          -- `suffix` (optional) is a faint-colour qualifier appended after
          -- the value (e.g. "(this turn)" / "(this chat)" on the cost rows)
          -- so the parenthetical reads as a hint rather than competing
          -- with the dollar amount.
          local function draw_field(x, y, label, value, label_px, wrap_w, row_h, value_color, suffix)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
            ImGui.ImGui_SetCursorPos(RA.ctx, x, y)
            Text(RA.ctx, label)
            PopStyleColor(RA.ctx)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), value_color or TK.text_muted)
            ImGui.ImGui_SetCursorPos(RA.ctx, x + label_px, y)
            ImGui.ImGui_PushTextWrapPos(RA.ctx, x + label_px + wrap_w)
            Text(RA.ctx, value)
            ImGui.ImGui_PopTextWrapPos(RA.ctx)
            PopStyleColor(RA.ctx)
            if suffix then
              SameLine(RA.ctx, 0, SUFFIX_GAP)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
              Text(RA.ctx, suffix)
              PopStyleColor(RA.ctx)
            end
            local tip = field_tooltips[label]
            if tip then
              ImGui.ImGui_SetCursorPos(RA.ctx, x, y)
              ImGui.ImGui_InvisibleButton(RA.ctx,
                str_format("##dfield_%d_%s", i, label),
                label_px + wrap_w, row_h)
              UI.tooltip_v5(tip)
            end
          end

          -- Divider line spans from the first to last text column (same
          -- inset as the field labels/values) and sits mid-way through the
          -- DIVIDER_SPACE gap so adjacent rows each get half the breathing
          -- room. TK.border keeps the tone consistent with the container
          -- outline.
          local div_sx1 = d_sx + DETAILS_PAD_H
          local div_sx2 = d_sx + DETAILS_W - DETAILS_PAD_H
          local prev_group
          for _, r in ipairs(rows) do
            local g = group_of[r[1]]
            if prev_group and g ~= prev_group then
              local div_local_y = cursor_y + math_floor(DIVIDER_SPACE * 0.5)
              local div_screen_y = d_sy + (div_local_y - start_local_y)
              ImGui.ImGui_DrawList_AddLine(dl_u,
                div_sx1, div_screen_y, div_sx2, div_screen_y, TK.border, 1)
              cursor_y = cursor_y + DIVIDER_SPACE
            end
            local meas = r[3] and (r[2] .. " " .. r[3]) or r[2]
            local rh = wrap_h(meas, value_w)
            draw_field(row_x, cursor_y, r[1], r[2], label_px, value_w, rh,
              color_map[r[1]], r[3])
            cursor_y = cursor_y + rh
            prev_group = g
          end

          ImGui.ImGui_PopStyleVar(RA.ctx)
          PopFont(RA.ctx)

          -- Jump cursor past the container so subsequent turns don't collide.
          ImGui.ImGui_SetCursorPos(RA.ctx, start_local_x, start_local_y + details_h)
        end

      else
        -- Assistant response: no bubble, flush left on the window background.
        local content_w = avail_w - BUBBLE_IND - 8
        ImGui.ImGui_Indent(RA.ctx, BUBBLE_IND)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Indent(RA.ctx, BUBBLE_IND)

        -- V5 assistant header: the model name sits inside a small card-
        -- toned pill so it reads as "here's the specific model that
        -- answered", separate from the surrounding message body. The
        -- optional AUTO badge (for auto-picked turns) appears inline to
        -- the right. Both are drawn via DrawList for pixel-exact control
        -- of pill bg / border / vertical centring.
        if msg.model_label then
          -- Cache the parenthetical-stripped display on the message so the
          -- model pill (drawn every frame for every visible assistant
          -- message) skips the per-frame gsub. Re-runs only when
          -- msg.model_label actually changes.
          if msg._model_display_src ~= msg.model_label then
            msg._model_display_src = msg.model_label
            msg._model_display     = msg.model_label:gsub(" %b()", "")
          end
          local indicator = msg._model_display
          local MP_FONT  = RA.SC(12)
          local MP_PAD_X = RA.SC(9)
          local MP_PAD_Y = RA.SC(4)
          local MP_ROUND = RA.SC(4)
          PushFont(RA.ctx, FONT.inter_light, MP_FONT)
          local mp_tw = CalcTextSize(RA.ctx, indicator)
          PopFont(RA.ctx)
          local mp_w = mp_tw + MP_PAD_X * 2
          local mp_h = MP_FONT + MP_PAD_Y * 2
          local msx0, msy0 = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          local line_h = ImGui.ImGui_GetTextLineHeight(RA.ctx)
          local y_off = math_floor((line_h - mp_h) * 0.5)
          local mdl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          ImGui.ImGui_DrawList_AddRectFilled(mdl,
            msx0, msy0 + y_off, msx0 + mp_w, msy0 + y_off + mp_h,
            TK.model_pill_bg, MP_ROUND)
          ImGui.ImGui_DrawList_AddRect(mdl,
            msx0, msy0 + y_off, msx0 + mp_w, msy0 + y_off + mp_h,
            TK.border, MP_ROUND, 0, 1)
          -- Text y shifted up SC(2) to compensate for DrawList_AddTextEx
          -- placing by the top-of-line-box (which leaves extra ascent
          -- space above the visible glyph). SC(2) puts the label at its
          -- optical centre inside the pill.
          ImGui.ImGui_DrawList_AddTextEx(mdl, FONT.inter_light, MP_FONT,
            msx0 + MP_PAD_X, msy0 + y_off + MP_PAD_Y - RA.SC(2),
            TK.text, indicator)
          Dummy(RA.ctx, mp_w, line_h)
        elseif msg.provider_id then
          local prov = PROVIDERS.get(msg.provider_id)
          if prov then
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text)
            Text(RA.ctx, prov.label)
            PopStyleColor(RA.ctx)
          end
        end

        -- 10 px breathing room between the model pill and the reply body.
        if msg.model_label or msg.provider_id then
          Dummy(RA.ctx, 1, RA.SC(10))
        end

        if msg.content and msg.content ~= "" then
          UI.selectable_text(msg.content, "##amsg_" .. i, content_w, COL.CHAT_TEXT)
        end

        -- Clickable URL link (rendered as a colored text button).
        if msg.link_url then
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.LINK)
          if ImGui.ImGui_SmallButton(RA.ctx, msg.link_label or msg.link_url) then
            UI.open_url(msg.link_url)
          end
          if ImGui.ImGui_IsItemHovered(RA.ctx) then
            ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
          end
          PopStyleColor(RA.ctx)
        end

        -- Recovery buttons for token-exhaustion errors. Both actions persist
        -- to ExtState. Thinking-level button is scoped to the provider that
        -- was active at error time (msg.provider_id), so a later provider
        -- switch does not retarget the wrong entry. Buttons auto-hide once
        -- the relevant ceiling/floor is reached.
        if msg.recovery == "token_limit" then
          -- Bump-Max-Tokens recovery has been retired: max_tokens is no longer
          -- a user-tunable knob (cloud providers send the model's published
          -- ceiling automatically; OpenAI/Gemini omit the field so the server
          -- applies its own default). For empty-output-from-thinking failures
          -- the only meaningful client-side recovery is Lower Thinking.
          local rec_prov = msg.provider_id and PROVIDERS.get(msg.provider_id) or PROVIDERS.active()
          -- Resolve which model this message was produced by so the
          -- recovery action targets the right per-(provider, model)
          -- thinking slot, even if the user has switched models since.
          -- Falls back to the currently-active model when the message
          -- predates the model_id stamp or its model has since been
          -- removed (e.g. custom-provider entry deleted).
          local rec_model
          if rec_prov and msg.model_id and rec_prov.models then
            for _, m in ipairs(rec_prov.models) do
              if m.id == msg.model_id then rec_model = m; break end
            end
          end
          if not rec_model then
            rec_model = MODELS[prefs.model_idx] or MODELS[1]
          end
          local cur_idx
          if rec_prov and rec_prov.thinking_levels then
            cur_idx = PROVIDERS.load_thinking_idx(rec_prov, rec_model)
          end
          local can_lower = cur_idx and cur_idx > 1
          -- Retry hides until the user has applied a fix (msg.recovery_used is
          -- stamped below by Lower). Also gated on idle/error status so the
          -- button can't fire mid-request.
          local can_retry = msg.recovery_used
            and (S.status == "idle" or S.status == "error")
          if msg.truncated or can_lower or can_retry then
            ImGui.ImGui_Spacing(RA.ctx)
          end
          -- Truncation banner: placed just above the recovery buttons so the
          -- cause + the fix are visually grouped at the bottom of the reply.
          if msg.truncated then
            UI.selectable_text(
              "Response cut off - the model ran out of output tokens.",
              "##trunc_" .. i, content_w, COL.WARN)
            Dummy(RA.ctx, 1, RA.SC(6))
          end
          if can_lower or can_retry then
            -- V5 secondary-button palette filled with TK.card_hover so the
            -- buttons read as tactile chips rather than outline-only ghosts.
            -- Hover / active lerp toward the accent for feedback. 1 px border,
            -- 4 px rounding, mono font match the Undo / Copy / Save row under
            -- code blocks. Shared font / border / style-vars pop once at end.
            local V5_SEC_BG  = TK.card_hover
            local V5_SEC_HOV = UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.25)
            local V5_SEC_ACT = UI.lerp_u32(TK.card_hover, TK.accent_ui, 0.45)
            local V5_SEC_TXT = TK.text_muted
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(5))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(), TK.border)
            PushFont(RA.ctx, FONT.mono_med, RA.SC(11))

            -- Accent-muted palette for the Retry button: tinted accent fill
            -- with accent_text, so Retry reads as the primary next-step action
            -- sitting under the two muted fix-settings buttons.
            local V5_ACC_BG  = TK.accent_ui
            local V5_ACC_HOV = UI.lerp_u32(TK.accent_ui, TK.accent, 0.35)
            local V5_ACC_ACT = UI.lerp_u32(TK.accent_ui, TK.accent, 0.55)
            local V5_ACC_TXT = TK.accent_text

            local drew_any = false
            local function _push_sec()
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
            end
            local function _push_acc()
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_ACC_BG)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_ACC_HOV)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_ACC_ACT)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_ACC_TXT)
            end
            if can_lower then
              local lower = rec_prov.thinking_levels[cur_idx - 1]
              _push_sec()
              if ImGui.ImGui_Button(RA.ctx, "Lower Thinking to " .. (lower.label or "?") .. "##rec_think_" .. i, 0, 0) then
                local new_idx = cur_idx - 1
                -- Save under the (provider, model) that produced the
                -- failed response so the lowered level applies to that
                -- model on its next turn, not to whichever model the
                -- user is currently looking at. Update prefs.thinking_idx
                -- in memory only when the recovery target IS the
                -- currently-active (provider, model) -- otherwise the
                -- user has already moved on and we shouldn't change
                -- their visible chip.
                PROVIDERS.save_thinking_idx(rec_prov, rec_model, new_idx)
                local active_m = MODELS[prefs.model_idx] or MODELS[1]
                if rec_prov == PROVIDERS.active() and rec_model == active_m then
                  prefs.thinking_idx = new_idx
                end
                msg.recovery_used = true
              end
              UI.tooltip("Reduce reasoning depth so more budget goes to the visible reply.")
              PopStyleColor(RA.ctx, 4)
              drew_any = true
            end
            if can_retry then
              -- Retry drops to its own line beneath the fix-settings buttons
              -- and uses the accent-muted palette so it reads as the primary
              -- next step after the user has applied a fix.
              if drew_any then Dummy(RA.ctx, 1, RA.SC(6)) end
              _push_acc()
              if ImGui.ImGui_Button(RA.ctx, "Retry Message##rec_retry_" .. i, 0, 0) then
                local last_user_text
                for j = #S.display_messages, 1, -1 do
                  local m = S.display_messages[j]
                  if m.role == "user" and m.content and m.content ~= "" then
                    last_user_text = m.content
                    break
                  end
                end
                if last_user_text then
                  Net.send_to_api(last_user_text)
                end
              end
              UI.tooltip("Re-send the last prompt with the current settings.")
              PopStyleColor(RA.ctx, 4)
            end

            PopFont(RA.ctx)
            PopStyleColor(RA.ctx, 1) -- Border
            ImGui.ImGui_PopStyleVar(RA.ctx, 3)
          end
        end

        -- Optional storage disclaimer (shown on welcome/key-entry messages).
        if msg.storage_note then
          ImGui.ImGui_Spacing(RA.ctx)
          UI.selectable_text(msg.storage_note, "##snote_" .. i, avail_w - 8, COL.DETAIL)
        end

        -- Code block: monospace font, dark background.
        -- Lua: Run Code, Undo, Backup, Copy, Save, Edit buttons.
        -- JSFX: Add To Selected Track(s), Undo, Copy, Save, Save As, Edit buttons.
        if msg.code_block then
          ImGui.ImGui_Spacing(RA.ctx)
          -- Cache the newline count on the message; code blocks are
          -- immutable post-add (or have an explicit code_changed flag
          -- on the edit path). Previously this re-walked the entire
          -- code string every visible code-block message every frame.
          if msg._code_line_count == nil
             or msg._code_line_count_src ~= msg.code_block then
            local n = 1
            for _ in msg.code_block:gmatch("\n") do n = n + 1 end
            msg._code_line_count     = n
            msg._code_line_count_src = msg.code_block
          end
          local line_count = msg._code_line_count
          local max_lines = 9
          PushFont(RA.ctx, RA.code_font, RA.SC(12))
          -- Per-line step = line_height + SC(6) inter-line gap (matches the
          -- ItemSpacing.y Code.render_highlighted pushes for breathing-room
          -- line spacing). +SC(10) is a small bottom cushion so the last
          -- row isn't flush against the container's bottom edge.
          local content_h = math_min(line_count, max_lines) * (ImGui.ImGui_GetTextLineHeight(RA.ctx) + RA.SC(6)) + RA.SC(10)
          local CODE_PAD   = RA.SC(20)         -- inner padding on sides + bottom
          local CODE_ROUND = RA.SC(8)          -- corner radius
          local HEADER_H   = RA.SC(28)         -- top strip: LANG + filename + line count
          local HEADER_BODY_GAP = RA.SC(8)     -- gap between header divider and code body
          local code_w = avail_w - 40
          local code_h = HEADER_H + HEADER_BODY_GAP + content_h + CODE_PAD

          -- V5 code box: rounded rect with a vertical gradient fill + 1 px
          -- border outline + 20 px inner padding. The gradient is composed
          -- of three bands (rounded-top solid, middle multi-colour, rounded-
          -- bottom solid) because ImGui's AddRectFilledMultiColor doesn't
          -- support corner rounding; the three bands line up seamlessly
          -- because their top/bottom colours match at each seam.
          local cb_sx, cb_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          local cb_x2 = cb_sx + code_w
          local cb_y2 = cb_sy + code_h
          local code_dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          -- _shift_col is hoisted to file scope; see the definition at
          -- the top of this file.
          local bg_top = _shift_col(COL.CODE_BG,  12)
          local bg_bot = _shift_col(COL.CODE_BG, -9)
          local top_band_y2 = cb_sy + CODE_ROUND
          local bot_band_y1 = cb_y2 - CODE_ROUND
          -- Top band: rounded top corners, solid bg_top
          ImGui.ImGui_DrawList_AddRectFilled(code_dl,
            cb_sx, cb_sy, cb_x2, top_band_y2,
            bg_top, CODE_ROUND, ImGui.ImGui_DrawFlags_RoundCornersTop())
          -- Middle: square gradient (bg_top -> bg_bot)
          ImGui.ImGui_DrawList_AddRectFilledMultiColor(code_dl,
            cb_sx, top_band_y2, cb_x2, bot_band_y1,
            bg_top, bg_top, bg_bot, bg_bot)  -- TL, TR, BR, BL
          -- Bottom band: rounded bottom corners, solid bg_bot
          ImGui.ImGui_DrawList_AddRectFilled(code_dl,
            cb_sx, bot_band_y1, cb_x2, cb_y2,
            bg_bot, CODE_ROUND, ImGui.ImGui_DrawFlags_RoundCornersBottom())
          -- Border: 1 px outline with matching rounding
          ImGui.ImGui_DrawList_AddRect(code_dl,
            cb_sx, cb_sy, cb_x2, cb_y2,
            TK.border, CODE_ROUND, 0, 1)

          -- V5 code header strip: mono LANG + midline-dot + filename on the
          -- left, "N lines" right-aligned. Detected as JSFX for eel/jsfx
          -- code types, LUA otherwise. 1 px divider separates header from
          -- code body for visual section clarity.
          do
            local is_jsfx = (msg.code_type == "jsfx" or msg.code_type == "eel")
            local lang = is_jsfx and "JSFX" or "LUA"
            local filename
            if is_jsfx then
              filename = Code.derive_filename_jsfx(msg.code_block) or "effect.jsfx"
            else
              filename = Code.derive_filename(msg.code_block) or "snippet.lua"
            end
            local header_left  = lang .. "  \xc2\xb7  " .. filename
            local header_right = tostring(line_count) .. " lines"
            local HDR_FONT = RA.SC(10)
            PushFont(RA.ctx, FONT.mono_med, HDR_FONT)
            local right_tw = CalcTextSize(RA.ctx, header_right)
            PopFont(RA.ctx)
            local hdr_text_y = cb_sy + math_floor((HEADER_H - HDR_FONT) * 0.5)
            ImGui.ImGui_DrawList_AddTextEx(code_dl, FONT.mono_med, HDR_FONT,
              cb_sx + CODE_PAD, hdr_text_y, TK.text_faint, header_left)
            ImGui.ImGui_DrawList_AddTextEx(code_dl, FONT.mono_med, HDR_FONT,
              cb_x2 - CODE_PAD - right_tw, hdr_text_y, TK.text_faint, header_right)
            -- Divider between header and body. Short insets so it doesn't
            -- touch the container's border.
            ImGui.ImGui_DrawList_AddLine(code_dl,
              cb_sx + CODE_PAD, cb_sy + HEADER_H,
              cb_x2 - CODE_PAD,  cb_sy + HEADER_H,
              TK.border, 1)
          end

          -- Shift cursor inside the container below the header strip + gap
          -- so the child window / InputTextMultiline renders in the body
          -- region with 20 px side padding.
          ImGui.ImGui_SetCursorScreenPos(RA.ctx,
            cb_sx + CODE_PAD, cb_sy + HEADER_H + HEADER_BODY_GAP)

          PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),         0x00000000)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),            COL.CODE_FG)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(), COL.CODE_FG)
          if not msg.edit_mode then
            -- Default view: non-editable syntax-highlighted render inside a
            -- scrollable child. Click the Edit button in the button row to
            -- switch this specific block to a plain editable widget (one-way
            -- -- once in edit mode the block stays editable).
            -- Defensive guard: ReaImGui's BeginChild only registers a child
            -- window when it returns true, so EndChild must be skipped on the
            -- false branch (otherwise the parent's style snapshot mismatches
            -- and ImGui asserts "Missing PopStyleColor()").
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ChildBg(), 0x00000000)
            if ImGui.ImGui_BeginChild(RA.ctx, "##code_hl_" .. i,
                                      code_w - CODE_PAD * 2, content_h, 0, 0) then
              UI.render_highlighted(msg.code_block, msg.code_type or "lua", msg)
              ImGui.ImGui_EndChild(RA.ctx)
            end
            PopStyleColor(RA.ctx)
          else
            -- Editable: capture returned buffer so manual edits persist for Run/Copy/Save.
            -- 64 KB buffer accommodates large generated scripts.
            local code_changed, new_code = ImGui.ImGui_InputTextMultiline(RA.ctx,
              "##code_" .. i, msg.code_block,
              65536, code_w - CODE_PAD * 2, content_h, 0, nil)
            code_changed, new_code = UI.input_with_menu(RA.ctx, code_changed, new_code)
            if code_changed then
              msg.code_block = new_code
              -- Keep S.pending_code in sync when editing the latest block.
              if i == #S.display_messages and S.pending_code then
                S.pending_code = new_code
              end
            end
          end
          PopStyleColor(RA.ctx, 3)  -- FrameBg, Text, InputTextCursor
          PopFont(RA.ctx)

          -- Jump cursor past the bottom padding so the action-row buttons
          -- below don't overlap the container (BeginChild / InputTextMultiline
          -- only advanced past content_h, leaving us inside the padding).
          ImGui.ImGui_SetCursorScreenPos(RA.ctx, cb_sx, cb_y2)

          -- Button row: Run Code | Backup | Copy | Save
          -- Run Code, Undo, and Backup only appear for Lua code (not JSFX/EEL).
          ImGui.ImGui_Spacing(RA.ctx)
          local is_lua = (msg.code_type or "lua") == "lua"

          -- Risky-code warning. Scan BEFORE rendering buttons so the warning
          -- string is ready when the row is drawn.
          local risk_warning = is_lua and Code.scan_risky(msg.code_block) or nil

          -- V5 action-row styling. Shared FrameBorderSize + FrameRounding so
          -- every button in the row gets a 1 px outline with matching corner
          -- radius. The per-button color triplets below supply the palette:
          -- primary ("accent fill + white text") for Run / Add To Tracks,
          -- secondary ("transparent fill + muted label") for everything else.
          local V5_RUN_BG  = TK.accent
          local V5_RUN_HOV = UI.lerp_u32(TK.accent, 0xFFFFFFFF, 0.12)
          local V5_RUN_ACT = UI.lerp_u32(TK.accent, 0x000000FF, 0.10)
          local V5_RUN_TXT = TK.accent_text
          local V5_SEC_BG  = 0x00000000
          local V5_SEC_HOV = (TK.card_hover & 0xFFFFFF00) | 0x80  -- half-alpha hover
          local V5_SEC_ACT = TK.card_hover
          local V5_SEC_TXT = TK.text_muted
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
          -- FramePadding Y = SC(5) gives button height = font_h + 10 px
          -- which is 4 px taller than ImGui's default (~FramePadding.y=3).
          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(5))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(), TK.border)
          -- Mono font for the action row so Run / Undo / Backup / Copy / Save
          -- / Edit labels pick up the technical monospace feel of the code
          -- block they sit under.
          PushFont(RA.ctx, FONT.mono_med, RA.SC(11))

          -- Lua-only buttons: Run Code, Undo, Backup.
          if is_lua then
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_RUN_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_RUN_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_RUN_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_RUN_TXT)
            if ImGui.ImGui_Button(RA.ctx, "\xe2\x96\xb6 Run##run_" .. i, 70, 0) then
              if risk_warning then
                -- Risky code: require explicit user confirmation before executing.
                S.risky_warn_code   = msg.code_block
                S.risky_warn_idx    = i
                S.risky_warn_detail = risk_warning
                S.open_risky_warn   = true
              elseif prefs.auto_backup then
                -- Only `berr` is consumed below; the success flag is implicit
                -- (no err -> backup ran). Discard the first return.
                local _, berr = Code.safety_backup()
                if berr == "unsaved" then
                  S.backup_warn_code = msg.code_block
                  S.backup_warn_idx  = i
                  S.open_backup_warn = true
                else
                  S.status = "running"
                  local ok = Code.run(msg.code_block)
                  if i == #S.display_messages then S.pending_code = nil end
                  S.status = ok and "idle" or "error"
                  S.refocus_prompt = true
                end
              else
                S.status = "running"
                local ok = Code.run(msg.code_block)
                if i == #S.display_messages then S.pending_code = nil end
                S.status = ok and "idle" or "error"
                S.refocus_prompt = true
              end
            end
            UI.tooltip("Execute this code in REAPER")
            PopStyleColor(RA.ctx, 4)  -- Run: Button/Hovered/Active/Text

            SameLine(RA.ctx, 0, RA.SC(4))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
            if ImGui.ImGui_Button(RA.ctx, "Undo##undo_" .. i, 55, 0) then
              Theme.restore_backups()
              reaper.Main_OnCommand(40029, 0)
              S.refocus_prompt = true
            end
            UI.tooltip("Undo the last REAPER action (Ctrl+Z)")
            PopStyleColor(RA.ctx, 4)

            -- Save Theme button: only on theme-related code blocks with unsaved backups.
            if msg.code_block and msg.code_block:find("SetThemeColor")
               and reaper.GetExtState("ReaAssist", "ThemeBackup__KEYS") ~= "" then
              SameLine(RA.ctx, 0, RA.SC(4))
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        COL.SEND_BTN)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), COL.SEND_HOV)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  COL.SEND_ACT)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          COL.SEND_TEXT)
              if ImGui.ImGui_Button(RA.ctx, "Save Theme##thsave_" .. i, 95, 0) then
                local ok, save_err = Theme.save_to_file()
                if ok then
                  reaper.ShowMessageBox(
                    "Theme colors saved to:\n" .. reaper.GetLastColorThemeFile(),
                    "ReaAssist", 0)
                else
                  reaper.ShowMessageBox(save_err, "ReaAssist", 0)
                end
                S.refocus_prompt = true
              end
              UI.tooltip("Save the current theme color changes permanently to the theme file")
              PopStyleColor(RA.ctx, 4)
            end

            SameLine(RA.ctx, 0, RA.SC(4))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
            if ImGui.ImGui_Button(RA.ctx, "Backup##bak_" .. i, 70, 0) then
              local bok, berr = Code.safety_backup()
              local flash_val
              if bok then flash_val = "saved"
              elseif berr == "unsaved" then flash_val = "unsaved"
              elseif berr == "unchanged" then flash_val = "unchanged"
              end
              if flash_val then
                S.backup_flash[i] = { text = flash_val, t = time_precise() }
              end
            end
            UI.tooltip("Save a backup of your project (.rpp-bak)")
            PopStyleColor(RA.ctx, 4)
            SameLine(RA.ctx, 0, RA.SC(4))
          end -- is_lua

          if is_lua then
            -- Lua buttons: Copy and Save.
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
            local copy_flash = S._btn_flash and S._btn_flash["copy_" .. i]
              and (reaper.time_precise() - S._btn_flash["copy_" .. i]) < 1.5
            local copy_label = copy_flash and "Copied!" or "Copy"
            -- Nudge "Copied!" left by shrinking FramePadding.x. ButtonTextAlign
            -- can't help here because the label (at mono_med SC(11)) fills or
            -- overflows the button's content rect, so ImGui left-aligns to
            -- content_min regardless of align. Reducing padding_x shifts
            -- content_min left directly. Y padding preserved to keep height.
            if copy_flash then
              PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), RA.SC(6), RA.SC(5))
            end
            if ImGui.ImGui_Button(RA.ctx, copy_label .. "##copy_" .. i, 60, 0) then
              ImGui.ImGui_SetClipboardText(RA.ctx, msg.code_block)
              S._btn_flash = S._btn_flash or {}
              S._btn_flash["copy_" .. i] = reaper.time_precise()
            end
            if copy_flash then ImGui.ImGui_PopStyleVar(RA.ctx) end
            if not copy_flash then UI.tooltip("Copy code to clipboard") end

            SameLine(RA.ctx, 0, RA.SC(4))
            local save_flash = S._btn_flash and S._btn_flash["save_" .. i]
              and (reaper.time_precise() - S._btn_flash["save_" .. i]) < 1.5
            local save_lbl = save_flash and "Saved!" or "Save"
            if ImGui.ImGui_Button(RA.ctx, save_lbl .. "##save_" .. i, 60, 0) then
              if not reaper.JS_Dialog_BrowseForSaveFile and not S.js_hint_shown then
                S.js_hint_shown = true
                reaper.ShowMessageBox(
                  "For a full file browser when saving scripts, install\n"
                  .. "js_ReaScriptAPI via ReaPack (Extensions menu).\n\n"
                  .. "The basic filename prompt will open now.",
                  "ReaAssist - Tip", 0)
              end
              local saved = Code.save_file(msg.code_block, Code.derive_filename(msg.code_block))
              if saved then
                S.saved_script_path  = saved
                S.open_actions_modal = true
                S._btn_flash = S._btn_flash or {}
                S._btn_flash["save_" .. i] = reaper.time_precise()
              end
            end
            if not save_flash then UI.tooltip("Save code as a .lua script file") end

            -- Edit: switches THIS code block to a plain editable widget,
            -- removing the syntax highlighting. One-way -- once edited the
            -- block stays editable for the rest of the session, so the
            -- button hides itself after a click.
            if not msg.edit_mode then
              SameLine(RA.ctx, 0, RA.SC(4))
              if ImGui.ImGui_Button(RA.ctx, "Edit##edit_" .. i, 50, 0) then
                msg.edit_mode = true
              end
              UI.tooltip("Make this code block editable (removes syntax highlighting)")
            end
            PopStyleColor(RA.ctx, 4)

            -- Inline backup status text for Lua (expires after 5 seconds).
            local flash_entry = S.backup_flash[i]
            local flash = flash_entry and (time_precise() - flash_entry.t < 5) and flash_entry.text or nil
            if not flash and flash_entry then S.backup_flash[i] = nil end
            if flash == "saved" then
              SameLine(RA.ctx, 0, RA.SC(4))
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)
              Text(RA.ctx, "Backup Saved!")
              PopStyleColor(RA.ctx)
              if S.last_backup_path then UI.tooltip(S.last_backup_path) end
            elseif flash == "unchanged" then
              SameLine(RA.ctx, 0, RA.SC(4))
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)
              Text(RA.ctx, "Backup Saved!")
              PopStyleColor(RA.ctx)
              UI.tooltip("Project unchanged since last backup")
            elseif flash == "unsaved" then
              SameLine(RA.ctx, 0, RA.SC(4))
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.WARN)
              Text(RA.ctx, "Project not saved")
              PopStyleColor(RA.ctx)
            end

          else
            -- JSFX buttons: Copy | Save | Save As | Add To Selected Track(s)
            -- Invalidate cached save path if the file was deleted externally.
            -- Throttled to once every 2 s per message: previously this hit
            -- the filesystem every frame for every visible JSFX block, which
            -- is a kernel stat at 60 fps -- noticeable on Windows or on
            -- network-mounted Effects folders.
            if msg.jsfx_saved_path then
              local _now = time_precise()
              if (msg._jsfx_path_check_t or 0) + 2 < _now then
                msg._jsfx_path_check_t = _now
                local chk = io.open(msg.jsfx_saved_path, "r")
                if chk then chk:close() else
                  msg.jsfx_saved_path = nil
                  msg.jsfx_saved_fx_name = nil
                end
              end
            end

            -- Add To Selected Track(s) button (primary accent, first in row).
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_RUN_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_RUN_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_RUN_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_RUN_TXT)
            if ImGui.ImGui_Button(RA.ctx, "Add To Selected Track(s)##jsfx_add_" .. i, 190, 0) then
              local sel_count = reaper.CountSelectedTracks(0)
              if sel_count == 0 then
                S.open_no_tracks_warn = true
              else
                -- Reuse already-saved path if available, otherwise save now.
                local fx_name = msg.jsfx_saved_fx_name
                if not msg.jsfx_saved_path then
                  local saved_path, saved_fx_name = Code.auto_save_jsfx(msg.code_block)
                  if saved_path then
                    msg.jsfx_saved_path = saved_path
                    msg.jsfx_saved_fx_name = saved_fx_name
                    fx_name = saved_fx_name
                  end
                end
                if msg.jsfx_saved_path and fx_name then
                  -- Snapshot all selected-track pointers up front. Iterating
                  -- with GetSelectedTrack(0, t) inside the AddByName loop
                  -- would be vulnerable to a defer-script edit between
                  -- iterations: a track removed mid-loop could either drop
                  -- a slot we expected to handle or hand us a stale handle
                  -- if REAPER recycles the underlying memory. The window
                  -- here is sub-millisecond but other deferred scripts
                  -- (mixer macros, control surface handlers) can land in it.
                  local trs = {}
                  for t = 0, sel_count - 1 do
                    trs[#trs+1] = reaper.GetSelectedTrack(0, t)
                  end
                  reaper.Undo_BeginBlock()
                  local added_n = 0
                  for _, tr in ipairs(trs) do
                    if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
                      reaper.TrackFX_AddByName(tr, fx_name, false, -1)
                      added_n = added_n + 1
                    end
                  end
                  reaper.Undo_EndBlock("ReaAssist: Add JSFX to selected tracks", -1)
                  msg.jsfx_status = "Added to " .. added_n .. " track(s)."
                  msg.jsfx_added_to_tracks = true
                else
                  msg.jsfx_status = "Failed to save JSFX."
                end
              end
            end
            UI.tooltip("Save JSFX and add it to all selected tracks")
            PopStyleColor(RA.ctx, 4)

            -- Undo button: only shown after "Add To Selected Track(s)" was used.
            if msg.jsfx_added_to_tracks then
              SameLine(RA.ctx, 0, RA.SC(4))
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
              if ImGui.ImGui_Button(RA.ctx, "Undo##jsfx_undo_" .. i, 55, 0) then
                reaper.Main_OnCommand(40029, 0)
                msg.jsfx_added_to_tracks = false
                msg.jsfx_status = nil
                S.refocus_prompt = true
              end
              UI.tooltip("Undo adding the JSFX to tracks (Ctrl+Z)")
              PopStyleColor(RA.ctx, 4)
            end

            SameLine(RA.ctx, 0, RA.SC(4))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        V5_SEC_BG)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), V5_SEC_HOV)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  V5_SEC_ACT)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          V5_SEC_TXT)
            local jcopy_flash = S._btn_flash and S._btn_flash["copy_" .. i]
              and (reaper.time_precise() - S._btn_flash["copy_" .. i]) < 1.5
            local jcopy_lbl = jcopy_flash and "Copied!" or "Copy"
            -- Nudge "Copied!" left by shrinking FramePadding.x (see Lua Copy
            -- button above for rationale).
            if jcopy_flash then
              PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), RA.SC(6), RA.SC(5))
            end
            if ImGui.ImGui_Button(RA.ctx, jcopy_lbl .. "##copy_" .. i, 60, 0) then
              ImGui.ImGui_SetClipboardText(RA.ctx, msg.code_block)
              S._btn_flash = S._btn_flash or {}
              S._btn_flash["copy_" .. i] = reaper.time_precise()
            end
            if jcopy_flash then ImGui.ImGui_PopStyleVar(RA.ctx) end
            if not jcopy_flash then UI.tooltip("Copy JSFX code to clipboard") end

            SameLine(RA.ctx, 0, RA.SC(4))
            if ImGui.ImGui_Button(RA.ctx, "Save##jsfx_save_" .. i, 60, 0) then
              if msg.jsfx_saved_path then
                msg.jsfx_status = "Already saved to " .. msg.jsfx_saved_path
              else
                local saved_path, fx_name = Code.auto_save_jsfx(msg.code_block)
                if saved_path then
                  msg.jsfx_saved_path = saved_path
                  msg.jsfx_saved_fx_name = fx_name
                  msg.jsfx_status = "Saved to " .. saved_path
                else
                  msg.jsfx_status = "Failed to save JSFX."
                end
              end
            end
            UI.tooltip("Save JSFX to Effects/ReaAssist/ folder")

            SameLine(RA.ctx, 0, RA.SC(4))
            if ImGui.ImGui_Button(RA.ctx, "Save As##jsfx_saveas_" .. i, 70, 0) then
              local saved = Code.save_file_jsfx(msg.code_block, Code.derive_filename_jsfx(msg.code_block))
              if saved then
                msg.jsfx_status = "Saved to " .. saved
              end
            end
            UI.tooltip("Save JSFX to a custom location (opens file browser in Effects folder)")

            -- Edit: switches THIS code block to a plain editable widget,
            -- removing the syntax highlighting. One-way -- once edited the
            -- block stays editable for the rest of the session, so the
            -- button hides itself after a click.
            if not msg.edit_mode then
              SameLine(RA.ctx, 0, RA.SC(4))
              if ImGui.ImGui_Button(RA.ctx, "Edit##edit_" .. i, 50, 0) then
                msg.edit_mode = true
              end
              UI.tooltip("Make this code block editable (removes syntax highlighting)")
            end
            PopStyleColor(RA.ctx, 4)

            -- JSFX status text on its own line (button row is already wide).
            if msg.jsfx_status then
              PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)
              Text(RA.ctx, msg.jsfx_status)
              PopStyleColor(RA.ctx)
            end
          end

          -- Risky-code warning on its own line below the buttons.
          -- The scanner output is still shown inline so the user can see it
          -- before clicking Run, but execution is blocked until confirmed.
          if risk_warning then
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.WARN)
            ImGui.ImGui_TextWrapped(RA.ctx, risk_warning
              .. "  (Run will ask for confirmation)")
            PopStyleColor(RA.ctx)
          end

          -- JSFX auto-save status (when auto-run saved it).
          if not is_lua and msg.jsfx_auto_saved then
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.CHAT_TEXT)
            Text(RA.ctx, msg.jsfx_auto_saved)
            PopStyleColor(RA.ctx)
          end

          -- Close the V5 action-row style pushed before the buttons.
          PopFont(RA.ctx)                       -- mono_med action-row font
          PopStyleColor(RA.ctx)                 -- Border
          ImGui.ImGui_PopStyleVar(RA.ctx, 3)    -- FrameBorderSize, FrameRounding, FramePadding

          -- V5 AUTO-RAN confirmation pill: small rounded pill with a subtle
          -- green-tinted background + solid TK.green check-mark label,
          -- shown only when Auto-Run actually fired and executed the code
          -- successfully. Drawn via DrawList so bg tint + text align
          -- perfectly regardless of font metrics.
          if msg.auto_ran then
            ImGui.ImGui_Spacing(RA.ctx)
            local AR_FONT    = RA.SC(10)
            local AR_ICON    = RA.SC(11)                 -- lucide check glyph
            local AR_GAP     = RA.SC(3)                  -- gap between icon and text
            local AR_PAD_X   = RA.SC(8)
            local AR_PAD_Y   = RA.SC(3)
            local AR_ROUND   = RA.SC(3)
            local AR_LIFT    = RA.SC(2)                  -- nudge glyphs up inside the pill
            local ar_text = "AUTO-RAN"
            PushFont(RA.ctx, FONT.mono_med, AR_FONT)
            local ar_tw = CalcTextSize(RA.ctx, ar_text)
            PopFont(RA.ctx)
            local ar_w = AR_ICON + AR_GAP + ar_tw + AR_PAD_X * 2
            local ar_h = AR_FONT + AR_PAD_Y * 2
            local ar_sx, ar_sy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
            local ar_dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
            -- Subtle green bg: green with ~19% alpha so the chat surface
            -- tints through. Keeps the pill quiet but clearly "success".
            local ar_bg = (TK.green & 0xFFFFFF00) | 0x30
            ImGui.ImGui_DrawList_AddRectFilled(ar_dl,
              ar_sx, ar_sy, ar_sx + ar_w, ar_sy + ar_h,
              ar_bg, AR_ROUND)
            -- Lucide check glyph (mono font has no U+2713, so we use the icon font).
            -- Icon sits 2px lower than text for optical alignment (lucide's
            -- check glyph is high in its em-box vs. the mono baseline).
            ImGui.ImGui_DrawList_AddTextEx(ar_dl, FONT.lucide, AR_ICON,
              ar_sx + AR_PAD_X,
              ar_sy + AR_PAD_Y,
              TK.green, ICON.CHECK)
            -- "AUTO-RAN" text.
            ImGui.ImGui_DrawList_AddTextEx(ar_dl, FONT.mono_med, AR_FONT,
              ar_sx + AR_PAD_X + AR_ICON + AR_GAP,
              ar_sy + AR_PAD_Y - AR_LIFT,
              TK.green, ar_text)
            Dummy(RA.ctx, ar_w, ar_h)
          end
        end

        -- "Return to home screen" link after card-triggered assistant
        -- responses. Click triggers the same hard-reset path that the
        -- wordmark click and the "+ new chat" chip use (sets
        -- S._logo_click_pending; the main loop consumes it next frame,
        -- cancels any in-flight request, clears the conversation, and
        -- restores the welcome view) so the user can pick another
        -- info card without manually starting a new chat first.
        local prev_msg = i > 1 and S.display_messages[i - 1] or nil
        if prev_msg and prev_msg.from_card and S.status ~= "waiting" then
          ImGui.ImGui_Spacing(RA.ctx)
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.FOOTER)
          local rtop = "Return to home screen"
          local rtop_w = CalcTextSize(RA.ctx, rtop)
          local rtop_h = ImGui.ImGui_GetTextLineHeight(RA.ctx)
          ImGui.ImGui_InvisibleButton(RA.ctx, "##rtop_" .. i, rtop_w, rtop_h)
          local rtop_x, rtop_y = ImGui.ImGui_GetItemRectMin(RA.ctx)
          local rtop_dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          ImGui.ImGui_DrawList_AddText(rtop_dl, rtop_x, rtop_y, COL.FOOTER, rtop)
          ImGui.ImGui_DrawList_AddLine(rtop_dl,
            rtop_x, rtop_y + rtop_h - 1,
            rtop_x + rtop_w, rtop_y + rtop_h - 1, COL.FOOTER, 1)
          if ImGui.ImGui_IsItemHovered(RA.ctx) then
            ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
          end
          if ImGui.ImGui_IsItemClicked(RA.ctx) then
            S._logo_click_pending = true
          end
          PopStyleColor(RA.ctx)
        end

        -- Two thumbs icon buttons (Helpful / Not helpful), shown below
        -- every assistant message when the Diag uploader is enabled.
        -- Click opens the feedback modal with that sentiment pre-selected.
        -- Click does NOT send; preview + Send still required.
        --
        -- Skipped while a response is still streaming. Includes code-only
        -- assistant messages (no prose, just generated code) since those
        -- are exactly the kind users may want to report on.
        --
        -- Styled as compact icon-only V5 secondary buttons (transparent
        -- fill, 1px muted border) with subtle accent-tinted hover.
        local _fb_has_text = msg.content and msg.content ~= ""
        local _fb_has_code = msg.code_block and msg.code_block ~= ""
        if Diag.uploader_enabled
           and S.status ~= "waiting"
           and (_fb_has_text or _fb_has_code) then
          Dummy(RA.ctx, 1, RA.SC(20))   -- 20px margin above

          -- Local helper: opens the modal for this assistant message,
          -- pre-selecting `with_thumb` ("up" / "down" / nil).
          local function _open_fb(with_thumb)
            S.feedback_modal_open       = true
            S.feedback_modal_target_idx = i
            S.feedback_modal_draft      = Diag.begin_draft(i)
            S.feedback_modal_comment    = ""
            S.feedback_modal_flags      = {
              thumbs_up            = (with_thumb == "up"),
              thumbs_down          = (with_thumb == "down"),
              wrong_result         = false,
              wrong_plugin         = false,
              didnt_follow_request = false,
              too_slow             = false,
            }
            S.feedback_modal_state      = "idle"
            S.feedback_modal_error      = nil
            S._feedback_modal_opened    = false
          end

          -- Local helper: renders a single thumb icon button. Returns
          -- true if clicked. Hover overlay matches the modal's chips:
          -- subtle accent-tinted bg + accent border drawn after the
          -- button when hovered.
          local function _fb_thumb_chat_btn(id, icon, tooltip)
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(8), RA.SC(4))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
              (TK.accent & 0xFFFFFF00) | 0x33)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),
              (TK.accent & 0xFFFFFF00) | 0x55)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
            PushFont(RA.ctx, FONT.lucide, RA.SC(12))
            local clicked = ImGui.ImGui_Button(RA.ctx, icon .. "##" .. id)
            PopFont(RA.ctx)
            PopStyleColor(RA.ctx, 5)
            ImGui.ImGui_PopStyleVar(RA.ctx, 3)
            if ImGui.ImGui_IsItemHovered(RA.ctx) then
              local x1, y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
              local x2, y2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
              local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
              ImGui.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2,
                TK.accent, RA.SC(4), 0, 1)
              if tooltip then UI.tooltip(tooltip) end
            end
            return clicked
          end

          if _fb_thumb_chat_btn("fbup_" .. i, ICON.THUMBS_UP, "Helpful") then
            _open_fb("up")
          end
          ImGui.ImGui_SameLine(RA.ctx, 0, RA.SC(6))
          if _fb_thumb_chat_btn("fbdown_" .. i, ICON.THUMBS_DOWN, "Not helpful") then
            _open_fb("down")
          end
        end

        ImGui.ImGui_Unindent(RA.ctx, BUBBLE_IND)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Unindent(RA.ctx, BUBBLE_IND)
      end

    end

    -- Status indicators: shown below the last user bubble in the assistant
    -- response area, with the same gap and indent as a normal response. The
    -- normal "waiting" state shows a multi-line block with elapsed time and
    -- the (provider-aware) timeout ceiling so the user can judge whether a
    -- slow local LLM is still alive or genuinely stuck. Retry-scheduled and
    -- code-running states keep their compact single-line layout.
    if S.status == "waiting" or S.status == "running" or deep_scan.active
        or S.resolve_popup then
      ImGui.ImGui_SetCursorPosY(RA.ctx, ImGui.ImGui_GetCursorPosY(RA.ctx) + BUBBLE_GAP)
      ImGui.ImGui_Indent(RA.ctx, BUBBLE_IND)

      -- Format seconds as "M:SS" for both elapsed and timeout displays.
      local function fmt_mss(s)
        s = math_max(0, math_floor(s))
        return str_format("%d:%02d", math_floor(s / 60), s % 60)
      end

      -- Cancel button renderer. Aborts the in-flight curl request, removes the
      -- pending user/assistant bubbles, and resets to idle. Inlined as a local
      -- closure so all three status branches below can place it differently
      -- (SameLine for compact rows, new line for the multi-line waiting block).
      local function render_cancel_btn()
        -- V5 secondary button style (transparent fill, 1 px border, muted
        -- label) matching the code-block action row.
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
        PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(4))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), (TK.card_hover & 0xFFFFFF00) | 0x80)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
        PushFont(RA.ctx, FONT.mono_med, RA.SC(11))
        if ImGui.ImGui_Button(RA.ctx, "Cancel") then
          -- If a deep param scan is running for this turn, signal cancel so
          -- the coroutine returns early and its on_cancel handler tears down
          -- the temp track.
          if deep_scan.active then CTX.cancel_deep_scan() end
          -- Kill the curl OS process before clearing state. Without this the
          -- request keeps running in the background and may write a late
          -- response to tmp.out that gets picked up by the next request.
          Net.kill_curl()
          S.curl_pid   = nil
          S.send_time  = nil
          S.status     = "idle"
          -- Remove the pending user bubble if the AI never responded.
          if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
            local last = #S.display_messages
            -- Remove trailing assistant placeholder and user bubble.
            if last > S.pending_display_idx then
              S.display_messages[last] = nil
            end
            S.display_messages[S.pending_display_idx] = nil
            -- Also remove from conversation history.
            if #S.history >= 1 then S.history[#S.history] = nil end
          end
          S.pending_display_idx = nil
          S.pending_code        = nil
          S.retry_scheduled     = false
          S.retry_count         = 0
          S.retry_saved_body    = nil
          S.scroll_to_bottom    = true
        end
        PopFont(RA.ctx)
        PopStyleColor(RA.ctx, 5)             -- Border, Button, Hovered, Active, Text
        ImGui.ImGui_PopStyleVar(RA.ctx, 3)   -- FrameBorderSize, FrameRounding, FramePadding
      end

      if S.resolve_popup then
        -- Blocked on user action in the resolve-type popup. Give a visible
        -- status line so the chat doesn't look stuck (and so ImGui has an
        -- item after the user bubble's SetCursorPosY call, which keeps
        -- EndChild from asserting about unextended parent bounds).
        local rsv_type = S.resolve_popup.type or "plugin"
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.STATUS)
        Text(RA.ctx,
          "Waiting for your " .. rsv_type .. " selection...")
        PopStyleColor(RA.ctx)
      elseif S.status == "waiting" or deep_scan.active then
        if S.retry_scheduled then
          -- Retry countdown stays on a single line with Cancel SameLine.
          local secs = math_max(0, math_floor(S.retry_fire_time - time_precise()))
          PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.WARN)
          Text(RA.ctx, str_format("Server busy; retrying in %ds (%d/%d)",
            secs, S.retry_count, CFG.MAX_RETRIES))
          PopStyleColor(RA.ctx)
          SameLine(RA.ctx, 0, 12)
          render_cancel_btn()
        else
          -- Multi-line "Thinking" status with elapsed time and timeout ceiling.
          -- Elapsed is whole-turn wall clock from the user's Send click
          -- (S.request_start_time); using S.send_time would reset on every
          -- <context_needed> round-trip, which looks like the timer is
          -- bouncing even though the user's turn is still in progress.
          -- The timeout value is per-curl (mirrors the watchdog in
          -- Net.try_finish_curl) -- Custom local LLMs use their per-provider
          -- timeout + 15s slack; cloud providers use prefs.cloud_request_timeout
          -- (default 180s, extendable mid-request via the "Extend by Ns"
          -- button rendered below).
          local elapsed      = (S.request_start_time and (time_precise() - S.request_start_time)) or 0
          local pa           = PROVIDERS.active()
          local poll_timeout = (pa.is_custom
            and ((tonumber(pa.request_timeout) or 600) + 15))
            or (prefs.cloud_request_timeout or CFG.CLOUD_TIMEOUT_DEFAULT)
          -- Reflect "Extend by Ns" clicks in the displayed Timeout. The watchdog
          -- already honors them by pushing S.send_time forward; this just keeps
          -- the on-screen number in sync so the user sees the deadline move.
          poll_timeout = poll_timeout + (S.timeout_extensions or 0) * CFG.EXTEND_BY_SECS

          PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(), 8, RA.SC(2))

          -- V5 pulsing accent dot -- same sine-wave fade the hero status
          -- chip uses. Drawn via DrawList at the current cursor; layout
          -- then reserves a Dummy slot so SameLine() picks up right after.
          local DOT_R   = RA.SC(3)
          local DOT_GAP = RA.SC(8)
          local tdl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
          local tphase = (time_precise() % 1.4) / 1.4
          local dot_alpha = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(tphase * 2 * math.pi))
          local tsx, tsy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
          local line_h = ImGui.ImGui_GetTextLineHeight(RA.ctx)
          local base_rgb = TK.accent & 0xFFFFFF00
          local core_a    = math_max(math_floor(0xFF  * dot_alpha), 0x80)
          local ring_hi_a = math_floor(0x40 * dot_alpha)
          local ring_lo_a = math_floor(0x20 * dot_alpha)
          local dot_cx = tsx + DOT_R
          local dot_cy = tsy + math_floor(line_h * 0.5)
          ImGui.ImGui_DrawList_AddCircleFilled(tdl, dot_cx, dot_cy, RA.SC(6),   base_rgb | ring_lo_a, 0)
          ImGui.ImGui_DrawList_AddCircleFilled(tdl, dot_cx, dot_cy, RA.SC(4.5), base_rgb | ring_hi_a, 0)
          ImGui.ImGui_DrawList_AddCircleFilled(tdl, dot_cx, dot_cy, DOT_R,   base_rgb | core_a,    0)
          Dummy(RA.ctx, DOT_R * 2 + DOT_GAP, line_h)
          SameLine(RA.ctx, 0, 0)

          if deep_scan.active then
            local dlabel = deep_scan.identifier or "plugin"
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.accent)
            Text(RA.ctx, "Deep-scanning " .. dlabel .. "...")
            PopStyleColor(RA.ctx)

            local d_el = time_precise() - (deep_scan.started_at or time_precise())
            local pct  = 0
            if deep_scan.total_probes and deep_scan.total_probes > 0 then
              pct = math_floor(
                100 * deep_scan.probes_done / deep_scan.total_probes)
              if pct > 99 then pct = 99 end
            end
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
            UI.text_multiline(
              "This plugin reports parameter values with a one-frame delay "
              .. "(common on some VST3 plugins), so a slower defer-paced "
              .. "scan is needed to read accurate data. This only runs once "
              .. "per plugin. Future requests for this plugin will use the "
              .. "cached data and respond instantly.\n\n"
              .. "If the plugin has heavy selector params (Style, Preset, "
              .. "Algorithm, Engine), the scan waits for each value to fully "
              .. "load before moving on, so it can take noticeably longer "
              .. "than a typical scan.")
            PopStyleColor(RA.ctx)

            Dummy(RA.ctx, 1, RA.SC(4))
            PushFont(RA.ctx, FONT.mono_med, RA.SC(10))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
            Text(RA.ctx, "Probing")
            PopStyleColor(RA.ctx)
            SameLine(RA.ctx, 0, RA.SC(12))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
            Text(RA.ctx, str_format("%d/%d (%d%%)",
              deep_scan.probes_done, deep_scan.total_probes, pct))
            PopStyleColor(RA.ctx)

            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
            Text(RA.ctx, "Elapsed")
            PopStyleColor(RA.ctx)
            SameLine(RA.ctx, 0, RA.SC(12))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
            Text(RA.ctx, fmt_mss(d_el))
            PopStyleColor(RA.ctx)
            PopFont(RA.ctx)
          else
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.accent)
            Text(RA.ctx, "Thinking...")
            PopStyleColor(RA.ctx)

            Dummy(RA.ctx, 1, RA.SC(4))
            PushFont(RA.ctx, FONT.mono_med, RA.SC(10))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
            Text(RA.ctx, "Elapsed")
            PopStyleColor(RA.ctx)
            SameLine(RA.ctx, 0, RA.SC(12))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
            Text(RA.ctx, fmt_mss(elapsed))
            PopStyleColor(RA.ctx)

            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_faint)
            Text(RA.ctx, "Timeout")
            PopStyleColor(RA.ctx)
            SameLine(RA.ctx, 0, RA.SC(12))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
            Text(RA.ctx, fmt_mss(poll_timeout))
            PopStyleColor(RA.ctx)
            PopFont(RA.ctx)
          end
          Dummy(RA.ctx, 1, RA.SC(4))

          render_cancel_btn()
          -- "Extend by Ns" button: appears alongside Cancel when within
          -- EXTEND_SHOW_BEFORE_TIMEOUT seconds of the watchdog firing. Each
          -- click pushes S.send_time forward by EXTEND_BY_SECS, effectively
          -- giving the model that much more time to respond. Can be clicked
          -- multiple times. Curl's --max-time is a much higher ceiling
          -- (CFG.CURL_TIMEOUT = 1800s) so the curl process won't bite first.
          if S.status == "waiting" and S.send_time
             and not deep_scan.active
             and (poll_timeout - elapsed) <= CFG.EXTEND_SHOW_BEFORE_TIMEOUT then
            SameLine(RA.ctx, 0, RA.SC(6))
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(4))
            PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),    RA.SC(10), RA.SC(4))
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        TK.border)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), (TK.card_hover & 0xFFFFFF00) | 0x80)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
            PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.text_muted)
            PushFont(RA.ctx, FONT.mono_med, RA.SC(11))
            local ext_label = "Extend by " .. CFG.EXTEND_BY_SECS .. "s"
            if ImGui.ImGui_Button(RA.ctx, ext_label) then
              S.send_time = S.send_time + CFG.EXTEND_BY_SECS
              S.timeout_extensions = (S.timeout_extensions or 0) + 1
            end
            PopFont(RA.ctx)
            PopStyleColor(RA.ctx, 5)
            ImGui.ImGui_PopStyleVar(RA.ctx, 3)
            UI.tooltip("Give the model another " .. CFG.EXTEND_BY_SECS
              .. "s before the request times out. Click again for more time.")
          end
          ImGui.ImGui_PopStyleVar(RA.ctx)
        end
      else
        -- Running code: compact single-line treatment with Cancel SameLine.
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.WARN)
        Text(RA.ctx, "Running code...")
        PopStyleColor(RA.ctx)
        SameLine(RA.ctx, 0, 12)
        render_cancel_btn()
      end

      ImGui.ImGui_Unindent(RA.ctx, BUBBLE_IND)
    end

    PopFont(RA.ctx)  -- chat font size

    -- Auto-scroll to bottom when new content is added. Force the scroll for
    -- TWO frames in a row: a single SetScrollHereY isn't enough when ImGui
    -- has just laid out a large code block or table, because the child
    -- height it computed on the first frame is still smaller than what the
    -- second frame will measure -- the visible result is a partial scroll
    -- that stops a few rows above the true bottom. The boolean set sites
    -- elsewhere in the file stay as `S.scroll_to_bottom = true`; we treat
    -- `true` here as "two frames left" and count down to false.
    if S.scroll_to_bottom then
      ImGui.ImGui_SetScrollHereY(RA.ctx, 1.0)
      if S.scroll_to_bottom == true then
        S.scroll_to_bottom = 1  -- one more frame of forced scroll
      else
        S.scroll_to_bottom = S.scroll_to_bottom - 1
        if S.scroll_to_bottom <= 0 then S.scroll_to_bottom = false end
      end
    end

    -- Smooth scroll-to-top: lerp toward 0 with ease-out.
    if S.scroll_to_top then
      local cur = ImGui.ImGui_GetScrollY(RA.ctx)
      if cur < 1 then
        ImGui.ImGui_SetScrollY(RA.ctx, 0)
        S.scroll_to_top = false
      else
        ImGui.ImGui_SetScrollY(RA.ctx, math_floor(cur * 0.8))
      end
    end

    -- Smooth scroll-to-message: lerp toward target message Y position.
    -- Uses a frame counter to auto-expire and avoid fighting user scroll.
    if S.scroll_to_msg and scroll_to_msg_y then
      if not S.scroll_to_msg_frames then S.scroll_to_msg_frames = 0 end
      S.scroll_to_msg_frames = S.scroll_to_msg_frames + 1
      local cur = ImGui.ImGui_GetScrollY(RA.ctx)
      local target = scroll_to_msg_y
      local diff = target - cur
      if (diff < 1 and diff > -1) or S.scroll_to_msg_frames > 30 then
        S.scroll_to_msg = nil
        S.scroll_to_msg_frames = nil
      else
        ImGui.ImGui_SetScrollY(RA.ctx, math_floor(cur + diff * 0.2))
      end
    end

    -- Drag-select auto-scroll: when mouse button is held and cursor is near
    -- the top or bottom edge of the chat area, scroll the parent to allow
    -- drag-selection past the visible bounds.
    -- Only activate when the drag started inside the chat child window;
    -- otherwise resizing the main window via the title bar triggers unwanted scroll.
    local chat_hovered = ImGui.ImGui_IsWindowHovered(RA.ctx, ImGui.ImGui_HoveredFlags_ChildWindows())
    if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
      S._chat_drag = chat_hovered
    elseif not ImGui.ImGui_IsMouseDown(RA.ctx, 0) then
      S._chat_drag = false
    end
    if S._chat_drag and ImGui.ImGui_IsMouseDown(RA.ctx, 0) then
      local _, mouse_y = ImGui.ImGui_GetMousePos(RA.ctx)
      local _, win_y   = ImGui.ImGui_GetWindowPos(RA.ctx)
      local _, win_h   = ImGui.ImGui_GetWindowSize(RA.ctx)
      local edge     = 30  -- px from edge to trigger scroll
      local scroll_y = ImGui.ImGui_GetScrollY(RA.ctx)
      local max_y    = ImGui.ImGui_GetScrollMaxY(RA.ctx)
      if mouse_y < win_y + edge and scroll_y > 0 then
        ImGui.ImGui_SetScrollY(RA.ctx, math_max(0, scroll_y - 12))
      elseif mouse_y > win_y + win_h - edge and scroll_y < max_y then
        ImGui.ImGui_SetScrollY(RA.ctx, math_min(max_y, scroll_y + 12))
      end
    end

    ImGui.ImGui_EndChild(RA.ctx)
    end  -- if chat_visible
    PopStyleColor(RA.ctx, 5)  -- scrollbar palette + ChildBg
    UI.drop_target()

    -- ------ Input row -------------------------------------------------------------------------
    -- Top pad shifts the whole bottom section (input + mode row + footer) down
    -- the window so the footer sits flush against the bottom. Intentionally
    -- LARGER than PROMPT_TOP_PAD in the bottom_reserve calc -- the extra
    -- pixels come out of the SC(22) ItemSpacing buffer so we don't trigger
    -- a window-level scrollbar.
    Dummy(RA.ctx, 1, 23)

    -- do...end scopes the input row and options rows locals to stay under the
    -- 200-local-per-function limit in Lua 5.x.
    do -- input + options rows

    -- Global button/checkbox colors for the entire bottom bar (STYLING section).
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        COL.BTN)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), COL.BTN_HOV)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  COL.BTN_ACT)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_CheckMark(),     COL.ASSIST)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),       COL.BTN)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),COL.BTN_HOV)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(), COL.BTN_ACT)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Border(),        COL.BORDER)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 1)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(), 6, 5)
    -- Settings-family rounded corners on every frame in the bottom bar:
    -- buttons, dropdowns, checkboxes, popups. Matches push_settings_styles.
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),  RA.SC(4))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_GrabRounding(),   RA.SC(4))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_PopupRounding(),  RA.SC(4))

    -- V5 layout -- InputTextMultiline driven by pre-computed wrap lines from
    -- the outer block. Widget grows 1 -> 2 lines as content wraps; bottom
    -- stays pinned so the prompt appears to expand upward. Constants come
    -- from the V5_* locals computed at the top of this else-branch.
    local ROW_INSET      = V5_ROW_INSET
    local PROMPT_FONT_SIZE = V5_PROMPT_FONT
    local PROMPT_H       = V5_PROMPT_H
    local PAD_VERT       = V5_PAD_VERT
    local BTN_SEND       = V5_BTN_SEND
    local BTN_GAP        = V5_BTN_GAP
    local KEYCAP_GUTTER  = V5_KEYCAP_GUTTER
    local INPUT_BUF_SIZE = 8192

    -- Auto-focus the input field when the window first opens or when
    -- returning from help/overlay screens so Enter works immediately.
    if ImGui.ImGui_IsWindowAppearing(RA.ctx) or S.refocus_prompt then
      ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
      S.refocus_prompt = false
    end

    -- Enter-to-send: Enter (without Shift) sends; Shift+Enter inserts a newline.
    -- The multiline widget naturally inserts a newline on every Enter press;
    -- when Shift is NOT held we strip that trailing newline and trigger send.
    -- All wrap + geometry computed in the outer V5_* block. Bring them into
    -- the local frame under shorter names.
    local prompt_h      = PROMPT_H
    local prompt_w      = V5_prompt_w
    local card_visual_w = V5_card_visual_w
    local CLIP_W        = V5_CLIP_W
    SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + ROW_INSET)
    -- Custom card bg + border for the FULL visual width BEFORE the widget
    -- submits. ImGui's own frame is then suppressed (transparent + 0 border)
    -- so the rounded corners read as one continuous shape rather than a
    -- widget-ends-here / keycap-starts-here seam.
    do
      local csx, csy = ImGui.ImGui_GetCursorScreenPos(RA.ctx)
      local vex, vey = csx + card_visual_w, csy + prompt_h
      local vdl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      ImGui.ImGui_DrawList_AddRectFilled(vdl, csx, csy, vex, vey,
        TK.prompt_bg, RA.SC(10))
      ImGui.ImGui_DrawList_AddRect(vdl, csx, csy, vex, vey,
        TK.border, RA.SC(10), 0, 1)
    end
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),          0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(),   0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),    0x00000000)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_InputTextCursor(),  TK.text)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameBorderSize(), 0)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(),   RA.SC(10))
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ScrollbarSize(),   0)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FramePadding(),
      CLIP_W, math_floor(PAD_VERT * 0.5) + 1)   -- +1 nudge so the text sits slightly lower in the prompt card
    PushFont(RA.ctx, FONT.inter_reg, PROMPT_FONT_SIZE)
    ImGui.ImGui_SetNextItemWidth(RA.ctx, prompt_w)
    -- Snapshot the pre-edit buffer. When the user presses Enter while a
    -- selection is active, the widget replaces the selection with \n --
    -- if we used new_buf we'd send "\n" -> stripped to ""; sending nothing.
    -- prev_buf lets the Enter handler recover the original content.
    local prev_buf = S.input_buf
    -- Char-filter signal: when Enter is pressed without Shift while the
    -- prompt is focused, tell the EEL CharFilter (RA.prompt_charfilter,
    -- created in ReaAssist.lua) to drop the \n that ImGui would insert
    -- in its internal edit buffer this frame. Without it, the widget
    -- renders one frame at 2-line height -- a visible 1->2 line jump --
    -- before the post-widget Enter handler below can roll the buffer
    -- back. Focus is read from S._prompt_focused (last frame's value)
    -- since IsItemFocused only resolves AFTER the widget call. Multi-
    -- line paste is unaffected: a paste event doesn't fire IsKeyPressed
    -- the same frame, so discard_newline stays 0 and pasted \n's pass.
    do
      local _cf_shift = (ImGui.ImGui_GetKeyMods(RA.ctx) & ImGui.ImGui_Mod_Shift())
        == ImGui.ImGui_Mod_Shift()
      local _cf_enter = ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
      local _cf_discard = (S._prompt_focused and not UI._popup_was_open
        and _cf_enter and not _cf_shift) and 1 or 0
      ImGui.ImGui_Function_SetValue(RA.prompt_charfilter, "discard_newline", _cf_discard)
    end
    -- ReaImGui's current InputTextMultiline signature is 7 args
    -- (ctx, label, buf, size_w, size_h, flags, callback). Note: earlier
    -- versions had a buf_size arg between buf and size_w; passing a stray 0
    -- there shifts all subsequent args and feeds prompt_h as the FLAGS
    -- value, which silently breaks selection + delete.
    local _, new_buf = ImGui.ImGui_InputTextMultiline(RA.ctx,
      "##prompt", S.input_buf, prompt_w, prompt_h,
      ImGui.ImGui_InputTextFlags_CallbackCharFilter(), RA.prompt_charfilter)
    PopFont(RA.ctx)
    new_buf = new_buf or ""
    -- Subtle focus ring on the FOREGROUND draw list so it renders after
    -- ImGui's per-widget clip rects have popped. Sized to the full visual
    -- card (widget + keycap gutter) so the ring outlines what the user
    -- perceives as the control, not the narrower internal text widget.
    if ImGui.ImGui_IsItemActive(RA.ctx) then
      local _fx1, _fy1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local _fx2, _fy2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
      ImGui.ImGui_DrawList_AddRect(ImGui.ImGui_GetForegroundDrawList(RA.ctx),
        _fx1, _fy1, _fx2 + KEYCAP_GUTTER, _fy2,
        (TK.accent & 0xFFFFFF00) | 0x55, RA.SC(10), 0, 1)
    end
    local prompt_focused = ImGui.ImGui_IsItemFocused(RA.ctx)
    S._prompt_focused = prompt_focused
    -- Right-click context menu (Copy/Paste/Cut). Placed AFTER all IsItem*
    -- queries above (IsItemActive, GetItemRectMin/Max, IsItemFocused) so
    -- those still resolve against the InputText, not the menu popup.
    -- Cmd+V / Ctrl+V continue to work natively for cursor-aware paste;
    -- this menu's Paste replaces the entire buffer.
    _, new_buf = UI.input_with_menu(RA.ctx, false, new_buf)
    -- Enter (no Shift) = send; Shift+Enter = insert newline. Multiline widget
    -- inserts \n on EVERY Enter press -- when the press is without Shift we
    -- also strip that trailing \n so the sent message doesn't end with a
    -- newline the user didn't intend.
    --
    -- Popup guard: suppress when any modal popup was open at the start of
    -- the frame so an Enter press inside a popup (resolve-FX, unsaved
    -- changes, etc.) can't also fire Send on the main prompt. Modal
    -- popups normally steal focus (prompt_focused goes false), but this
    -- extra guard future-proofs against non-modal popups + any race
    -- where focus state diverges from popup state.
    local shift_held = (ImGui.ImGui_GetKeyMods(RA.ctx) & ImGui.ImGui_Mod_Shift()) == ImGui.ImGui_Mod_Shift()
    local enter_raw = prompt_focused
      and not UI._popup_was_open
      and (ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()))
    local enter_pressed = enter_raw and not shift_held
    if enter_pressed then
      -- Use the PRE-edit buffer stripped of trailing \n. If a selection was
      -- active when Enter was pressed, the widget replaced it with a raw \n
      -- and new_buf would be "\n" -> stripped to "" -> empty send.
      new_buf = (prev_buf or ""):gsub("\n$", "")
      ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
    end
    S.input_buf = new_buf
    -- Decorations drawn on top of the widget: card bg extension, placeholder,
    -- paperclip, keycap. The widget itself is narrower than the visual card;
    -- we paint a card-bg rect across the right gutter so the input LOOKS
    -- continuous all the way to the keycap, then add a 1px border around
    -- the full visual rect that matches ImGui's rounded frame.
    do
      local px, py = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local ex, ey = ImGui.ImGui_GetItemRectMax(RA.ctx)
      local vex = ex + KEYCAP_GUTTER    -- extended visual right edge
      local pdl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      -- Extend card bg across the right gutter (right-side rounded corners).
      ImGui.ImGui_DrawList_AddRectFilled(pdl,
        ex, py, vex, ey,
        TK.prompt_bg, RA.SC(10), ImGui.ImGui_DrawFlags_RoundCornersRight())
      -- Border stripe across the top and bottom of the gutter, plus the
      -- rounded right end-cap, so the extended bg has a matching 1px outline.
      ImGui.ImGui_DrawList_AddLine(pdl, ex, py,     vex - RA.SC(10), py,     TK.border, 1)
      ImGui.ImGui_DrawList_AddLine(pdl, ex, ey - 1, vex - RA.SC(10), ey - 1, TK.border, 1)
      -- Right-side rounded border arc.
      ImGui.ImGui_DrawList_PathArcTo(pdl, vex - RA.SC(10), py + RA.SC(10), RA.SC(10),
        -math.pi * 0.5, 0, 12)
      ImGui.ImGui_DrawList_PathLineTo(pdl, vex, ey - RA.SC(10))
      ImGui.ImGui_DrawList_PathArcTo(pdl, vex - RA.SC(10), ey - RA.SC(10), RA.SC(10),
        0, math.pi * 0.5, 12)
      ImGui.ImGui_DrawList_PathStroke(pdl, TK.border, 0, 1)
      -- Placeholder aligned to the widget's top-inset (same position ImGui
      -- starts rendering the caret + typed text), so the placeholder and the
      -- cursor appear at the same baseline -- no visual "jump" when the
      -- user starts typing.
      if not new_buf:match("%S") then
        -- +1 to match the FramePadding.y nudge so placeholder and typed text
        -- share the same baseline (no visual jump on first keystroke).
        -- The +SC(2) horizontal offset is placeholder-only: shifts the hint
        -- slightly inboard for visual breathing room from the paperclip
        -- gutter, while the real typed text + caret stay at px + CLIP_W.
        local text_y = py + math_floor(PAD_VERT * 0.5) + 1
        ImGui.ImGui_DrawList_AddTextEx(pdl, FONT.inter_reg, PROMPT_FONT_SIZE,
          px + CLIP_W + RA.SC(4), text_y, TK.text_faint,
          "Ask anything about your session...")
      end
      -- Paperclip (left).
      do
        local icon_size = RA.SC(16)
        local ix = px + RA.SC(11)
        local iy = py + math_floor((prompt_h - icon_size) * 0.5)
        ImGui.ImGui_DrawList_AddTextEx(pdl, FONT.lucide, icon_size,
          ix, iy, TK.text_faint, ICON.PAPERCLIP)
      end
      -- Enter keycap (right, drawn in the keycap gutter outside the widget).
      do
        local kw, kh = RA.SC(18), RA.SC(14)
        local kx1 = vex - kw - RA.SC(9)
        local ky1 = py + math_floor((prompt_h - kh) * 0.5)
        local kx2 = kx1 + kw
        local ky2 = ky1 + kh
        -- Keycap outline + enter glyph intentionally faint in both themes so
        -- the enter affordance reads as a hint rather than a primary action.
        ImGui.ImGui_DrawList_AddRect(pdl, kx1, ky1, kx2, ky2,
          TK.border, RA.SC(3), 0, RA.SC(1))
        local icon_size = RA.SC(11)
        local ix = kx1 + math_floor((kw - icon_size) * 0.5)
        local iy = ky1 + math_floor((kh - icon_size) * 0.5)
        ImGui.ImGui_DrawList_AddTextEx(pdl, FONT.lucide, icon_size,
          ix, iy, TK.text_faint, ICON.CORNER_DOWN_LEFT)
      end
    end
    UI.drop_target()
    ImGui.ImGui_PopStyleVar(RA.ctx, 4)    -- FrameBorderSize, FrameRounding, ScrollbarSize, FramePadding
    PopStyleColor(RA.ctx, 4)  -- FrameBg x3, InputTextCursor
    -- Save the widget rect. The visual card extends KEYCAP_GUTTER further
    -- right than the widget; _ipx2_visual is the edge the send button
    -- positions against so the keycap gutter appears continuous with the card.
    local _ipx1, _ipy1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
    local _ipx2, _ipy2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
    local _ipx2_visual = _ipx2 + KEYCAP_GUTTER
    -- Paperclip click detection via manual mouse-pos check (avoids fighting
    -- with InputText's focus claim). Toggles: when the popup is already open
    -- ImGui auto-closes it on any outside click, including ours -- so if the
    -- popup was open at the start of this frame, we don't reopen it (second
    -- click = closed). If it was closed, we open it.
    do
      local clip_hit = RA.SC(30)
      local cb_x1 = _ipx1 + RA.SC(4)
      local cb_y1 = _ipy1 + math_floor((prompt_h - clip_hit) * 0.5)
      local cb_x2 = cb_x1 + clip_hit
      local cb_y2 = cb_y1 + clip_hit
      local mx, my = ImGui.ImGui_GetMousePos(RA.ctx)
      local over = mx >= cb_x1 and mx <= cb_x2 and my >= cb_y1 and my <= cb_y2
      local can_attach_click = (S.status == "idle" or S.status == "error")
        and (S.api_key ~= nil or PROVIDERS.active().is_custom)
      if over and can_attach_click then
        ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
        if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
          local was_open = ImGui.ImGui_IsPopupOpen(RA.ctx, "##attach_menu")
          if not was_open then
            -- Stash the paperclip rect so Attach.render_ui can anchor the
            -- popup below it (same pattern as the model chip popups).
            S._attach_anchor_x = cb_x1
            S._attach_anchor_y = cb_y2 + RA.SC(2)
            ImGui.ImGui_OpenPopup(RA.ctx, "##attach_menu")
          end
        end
      end
    end
    local has_input = S.input_buf:match("%S")
    -- Block sending while attachment base64 encoding is still in progress.
    -- Encoding runs ~256KB per frame in the main loop (see Attach.pump_encoding)
    -- so a 10MB attachment becomes ready in ~40 frames (~0.7s at 60fps), which
    -- is essentially instantaneous from the user's perspective for normal sizes.
    local attachments_ready = Attach.all_encoded()
    -- Custom providers may run without an API key, so the key check is waived.
    local needs_key = not PROVIDERS.active().is_custom
    local can_send  = (S.status == "idle" or S.status == "error")
                      and not deep_scan.active
                      and (has_input or #S.attachments > 0)
                      and (S.api_key ~= nil or not needs_key)
                      and attachments_ready

    -- V5 send button: square, accent-filled, white send-arrow glyph drawn
    -- via the draw list. Positioned flush with the visual card's right edge
    -- and anchored to the BOTTOM of the prompt so it stays a 44x44 square
    -- even when the prompt expands to 2 lines.
    ImGui.ImGui_SetCursorScreenPos(RA.ctx,
      _ipx2_visual + BTN_GAP,
      _ipy1 + prompt_h - BTN_SEND)
    ImGui.ImGui_BeginDisabled(RA.ctx, not can_send)
    local armed = (has_input or #S.attachments > 0)
    -- Armed fill uses the shared muted-accent (same voice as the pill active
    -- segment, toggle "on"s, and card dots). Disabled state uses a solid
    -- muted blue so the button still reads as a button; transparent border
    -- tones would vanish against the window.
    local send_bg        = armed and TK.accent_ui or 0x93A9D6FF
    -- Hover / pressed tints: lift toward white on hover, deepen toward black
    -- on press. Only visible when armed + can_send -- BeginDisabled(true)
    -- suppresses these slots when the button is non-interactive.
    local send_bg_hover  = UI.lerp_u32(send_bg, 0xFFFFFFFF, 0.10)
    local send_bg_active = UI.lerp_u32(send_bg, 0x000000FF, 0.12)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        send_bg)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(), send_bg_hover)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  send_bg_active)
    PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),          TK.accent_text)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_FrameRounding(), RA.SC(10))
    local send_clicked = ImGui.ImGui_Button(RA.ctx, "##send", BTN_SEND, BTN_SEND)
    -- Draw the Lucide send glyph centered over the blank button label. When
    -- inactive (no prompt, no attachments), the arrow is a darker tone so
    -- the button reads as clearly dim; when armed it's the full accent_text.
    do
      local bx1, by1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local bx2, by2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
      local adl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
      local icon_size = RA.SC(22)
      -- Nudge 1px left + 1px down for optical centering of the Lucide
      -- send glyph (arrow skews visually up-right in its em-box).
      local ix = (bx1 + bx2) * 0.5 - icon_size * 0.5 - RA.SC(1)
      local iy = (by1 + by2) * 0.5 - icon_size * 0.5 + RA.SC(1)
      local arrow_col = armed and TK.accent_text or 0xD8E1F0FF
      ImGui.ImGui_DrawList_AddTextEx(adl, FONT.lucide, icon_size,
        ix, iy, arrow_col, ICON.SEND)
    end
    -- Note: UI.pressable() intentionally skipped -- its 2px top strip reads
    -- as an errant horizontal line on this filled rounded square. Press
    -- feedback comes from Col_ButtonActive (deeper tint) instead.
    if send_clicked or (enter_pressed and can_send) then
      local trimmed = S.input_buf:match("^%s*(.-)%s*$")
      if trimmed == "" and #S.attachments > 0 then
        trimmed = "Please analyze the attached file(s)."
      end
      S.input_buf = ""
      Net.send_to_api(trimmed)
      S.refocus_prompt = true
    end
    ImGui.ImGui_PopStyleVar(RA.ctx)       -- FrameRounding (send button)
    PopStyleColor(RA.ctx, 4)
    ImGui.ImGui_EndDisabled(RA.ctx)
    if not S.api_key and needs_key then
      UI.tooltip("No API key set for " .. PROVIDERS.active().label
        .. ". Click API Keys to add one.")
    elseif not attachments_ready and #S.attachments > 0 then
      UI.tooltip("Encoding attachment(s)...")
    end
    UI.drop_target()


    -- Show a character counter inline after buttons when approaching the limit.
    local input_len = #S.input_buf
    if input_len > INPUT_BUF_SIZE * 0.8 then
      SameLine(RA.ctx, 0, BTN_GAP)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(),
        input_len >= INPUT_BUF_SIZE - 1 and COL.ERROR or COL.WARN)
      ImGui.ImGui_TextWrapped(RA.ctx, str_format("%d / %d", input_len, INPUT_BUF_SIZE))
      PopStyleColor(RA.ctx)
    end

    -- ------ Attach popup + queue strip (no button row; paperclip in prompt handles opens) ------
    Attach.render_ui(fhs, avail_w)

    -- ------ V5 Mode + Model row -------------------------------------------
    -- Ask|Auto-Run pill + provider/model/thinking chips + details toggle.
    ImGui.ImGui_SetCursorPosY(RA.ctx, ImGui.ImGui_GetCursorPosY(RA.ctx) + RA.SC(10))
    UI.mode_model_row_v5()
    -- Mirror the SC(10) gap above the row so the footer sits with symmetric
    -- breathing room below the mode/model controls.
    ImGui.ImGui_SetCursorPosY(RA.ctx, ImGui.ImGui_GetCursorPosY(RA.ctx) + RA.SC(10))

    -- Update indicator: a thin standalone line above the footer rail while a
    -- download is in progress or just completed. The old button row it used
    -- to SameLine against is gone, so this now renders on its own line.
    if update.state == "downloading" or update.state == "rename_retry" then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.DETAIL)
      local prog = update.download_idx .. "/" .. #update.download_queue
      Text(RA.ctx, "Updating (" .. prog .. ")...")
      PopStyleColor(RA.ctx)
    elseif update.state == "done" then
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), COL.ASSIST)
      Text(RA.ctx, "Updated to v" .. (update.remote_version or "?") .. ". Close and reopen ReaAssist to apply.")
      PopStyleColor(RA.ctx)
    end

    ImGui.ImGui_PopStyleVar(RA.ctx, 5)    -- FrameBorderSize, FramePadding, FrameRounding, GrabRounding, PopupRounding
    PopStyleColor(RA.ctx, 8)  -- global bottom-bar button/checkbox colors + border

    -- ------ V5 Footer rail ----------------------------------------------
    UI.footer_rail_v5()

    -- ------ Bottom-right mini logo (fades in when welcome screen scrolls away) ------
    do
      -- Show mini logo only when the top logo is scrolled out of view.
      local top_visible = S._top_logo_visible
      local target = top_visible and 0.0 or 0.7
      -- Fade in ~2s, fade out ~1s (faster rate when fading out).
      local rate = top_visible and 0.04 or 0.015
      S.logo_alpha = S.logo_alpha + (target - S.logo_alpha) * rate
      -- Clamp near-zero/near-target to avoid unnecessary drawing.
      if S.logo_alpha < 0.005 then S.logo_alpha = 0 end
      if S.logo_alpha > 0.695 then S.logo_alpha = 0.7 end

      if S.logo_alpha > 0 and update._main_w then
        local mini_size = RA.SC(25)
        local kern = -1
        local dl = ImGui.ImGui_GetWindowDrawList(RA.ctx)
        -- Measure "Rea" and "Assist" at mini size.
        PushFont(RA.ctx, nil, mini_size)
        local rea_w = CalcTextSize(RA.ctx, "Rea")
        PopFont(RA.ctx)
        PushFont(RA.ctx, RA.bold_font, mini_size)
        local assist_w = CalcTextSize(RA.ctx, "Assist")
        PopFont(RA.ctx)
        local total_w = rea_w + kern + assist_w
        local line_h  = mini_size

        -- Position: bottom-right corner with margin.
        local mx = update._main_x + update._main_w - total_w - RA.SC(24)
        local my = update._main_y + update._main_h - mini_size - RA.SC(25)

        -- Manual hit-test (no InvisibleButton to avoid affecting layout).
        local mouse_x, mouse_y = ImGui.ImGui_GetMousePos(RA.ctx)
        local logo_hovered = mouse_x >= mx and mouse_x <= mx + total_w
                         and mouse_y >= my and mouse_y <= my + line_h
        if logo_hovered then
          ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
          if ImGui.ImGui_IsMouseClicked(RA.ctx, 0) then
            S.scroll_to_top = true
          end
        end

        -- Apply fade alpha; draw the wordmark with the same horizontal
        -- left-bright -> right-dark gradient as the main wordmark, via N
        -- vertical clip-rect bands.
        local alpha     = math_floor(S.logo_alpha * 255 + 0.5)
        local dark_rgb  = UI.lerp_u32(0x000000FF, COL.ASSIST, 0.78)
        local function draw_mini(col_rgba)
          local c = (col_rgba & 0xFFFFFF00) | alpha
          PushFont(RA.ctx, nil, mini_size)
          ImGui.ImGui_DrawList_AddText(dl, mx, my, c, "Rea")
          PopFont(RA.ctx)
          PushFont(RA.ctx, RA.bold_font, mini_size)
          ImGui.ImGui_DrawList_AddText(dl, mx + rea_w + kern, my, c, "Assist")
          PopFont(RA.ctx)
        end
        local N_BANDS = 7
        local clip_y1 = my - RA.SC(4)
        local clip_y2 = my + mini_size * 1.30 + RA.SC(20)
        for b = 0, N_BANDS - 1 do
          local bx1 = mx + total_w *  b      / N_BANDS
          local bx2 = (b == N_BANDS - 1)
            and (mx + total_w + RA.SC(4))
            or  (mx + total_w * (b + 1) / N_BANDS)
          local bt  = (b + 0.5) / N_BANDS
          ImGui.ImGui_DrawList_PushClipRect(dl, bx1, clip_y1, bx2, clip_y2, false)
          draw_mini(UI.lerp_u32(COL.ASSIST, dark_rgb, bt))
          ImGui.ImGui_DrawList_PopClipRect(dl)
        end
      end
    end

    end -- input + options rows

    -- do...end scopes popup modal locals to stay under the 200-local limit.
    do -- popup modals

    -- ------ Clear confirmation popup -----------------------------------------
    -- Prevents accidental wipe of conversation history by requiring explicit
    -- confirmation. Escape or Cancel dismisses without clearing.
    local clr_w, clr_h = RA.SC(320), RA.SC(150)
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - clr_w) * 0.5,
        update._main_y + (update._main_h - clr_h) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, clr_w, clr_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Confirm Clear##popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
      local clr_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      local clr_txt = "Clear the entire conversation?"
      local clr_tw = CalcTextSize(RA.ctx, clr_txt)
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((clr_cw - clr_tw) * 0.5))
      Text(RA.ctx, clr_txt)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)

      local confirm = false
      local cfm_w, cnl_w, cfm_gap = RA.SC(88), RA.SC(72), RA.SC(16)
      local cfm_row = cfm_w + cfm_gap + cnl_w
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((clr_cw - cfm_row) * 0.5))
      -- Wipes the full conversation -- danger palette.
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "Confirm", cfm_w, 0) then confirm = true end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, cfm_gap)
      if ImGui.ImGui_Button(RA.ctx, "Cancel", cnl_w, 0) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      -- Enter confirms, Escape cancels.
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
        confirm = true
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      if confirm then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        Net.clear_conversation()
        S.refocus_prompt = true
      end

      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- (Update Available dialog is rendered as a separate window below.)

    -- ------ Project Not Saved warning popup ------------------------------------
    -- Shown when Run Code is clicked with Auto-backup on but the project has
    -- not been saved to disk yet. The user can continue without a backup or cancel.
    -- Deferred open: consumed here because OpenPopup must be in the render frame.
    if S.open_backup_warn then
      ImGui.ImGui_OpenPopup(RA.ctx, "Project Not Saved##popup")
      S.open_backup_warn = false
    end
    -- Explicitly center the popup over the main window.
    local popup_w, popup_h = RA.SC(480), RA.SC(165)
    local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    local win_w, win_h = ImGui.ImGui_GetWindowSize(RA.ctx)
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      win_x + (win_w - popup_w) * 0.5,
      win_y + (win_h - popup_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
    ImGui.ImGui_SetNextWindowSize(RA.ctx, popup_w, popup_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Project Not Saved##popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
      local bw_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "You have auto-backup turned on and your project is not saved.")
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)

      local do_continue     = false
      local do_save_project = false
      local do_disable      = false
      -- Row 1: Continue (danger -- skips backup this run) | Save Project (primary).
      -- Both rows centered using GetContentRegionAvail math, matching the
      -- pattern used by Confirm Clear / Quit / Risky-Run popups.
      local btn_h     = 0
      local r1_a, r1_b, r1_gap = RA.SC(96), RA.SC(112), RA.SC(16)
      local r1_row    = r1_a + r1_gap + r1_b
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((bw_cw - r1_row) * 0.5))
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "Continue", r1_a, btn_h) then do_continue = true end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, r1_gap)
      UI.push_modal_primary_btn()
      if ImGui.ImGui_Button(RA.ctx, "Save Project", r1_b, btn_h) then
        do_save_project = true
      end
      UI.pop_modal_primary_btn()
      ImGui.ImGui_Spacing(RA.ctx)

      -- Row 2: Disable Auto-Backup | Cancel.
      -- For users who keep hitting this on unsaved scratch projects: one-click
      -- opt-out. Persists the pref change AND runs the deferred code, so the
      -- popup stops appearing and the action they kicked off still happens.
      local r2_a, r2_b, r2_gap = RA.SC(160), RA.SC(96), RA.SC(16)
      local r2_row = r2_a + r2_gap + r2_b
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((bw_cw - r2_row) * 0.5))
      if ImGui.ImGui_Button(RA.ctx, "Disable Auto-Backup", r2_a, btn_h) then
        do_disable = true
      end
      SameLine(RA.ctx, 0, r2_gap)
      if ImGui.ImGui_Button(RA.ctx, "Cancel", r2_b, btn_h) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        S.backup_warn_code = nil
        S.backup_warn_jsfx = nil
        S.backup_warn_idx  = nil
        S.refocus_prompt   = true
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        S.backup_warn_code = nil
        S.backup_warn_jsfx = nil
        S.backup_warn_idx  = nil
        S.refocus_prompt   = true
      end
      if do_disable then
        prefs.auto_backup = false
        reaper.SetExtState(CFG.EXT_NS, "auto_backup", "0", true)
      end
      -- Save Project: trigger native "File: Save project" (40026). If the
      -- project has never been saved, REAPER puts up the native Save-As
      -- dialog and Main_OnCommand blocks until the user picks a path or
      -- cancels. After it returns, re-check EnumProjects: if a path is
      -- now set, the save succeeded and we can do the backup + run. If
      -- the user cancelled the native dialog, leave our popup open so
      -- they can pick a different option.
      local saved_now = false
      if do_save_project then
        reaper.Main_OnCommand(40026, 0)
        local _, after_path = reaper.EnumProjects(-1)
        if after_path and after_path ~= "" then
          -- Now that the project has a path, do the safety backup the
          -- popup originally blocked on. Treat a real backup failure
          -- (write_error / read_error) as a hard stop here: the user
          -- explicitly chose Save Project specifically to get the
          -- backup, and silently running the generated code without
          -- one would defeat the popup's whole purpose. "unchanged"
          -- can't happen on the first backup of a freshly-saved
          -- project, but accept it defensively as success.
          local bok, berr = Code.safety_backup()
          if bok or berr == "unchanged" then
            saved_now = true
          else
            ImGui.ImGui_CloseCurrentPopup(RA.ctx)
            S.backup_warn_code = nil
            S.backup_warn_jsfx = nil
            S.backup_warn_idx  = nil
            S.refocus_prompt   = true
            Log.add_error("Project saved, but the safety backup failed ("
              .. tostring(berr) .. "). The generated code was NOT run. "
              .. "Resolve the disk/permission issue and try again, or "
              .. "click Run manually if you want to proceed without a "
              .. "backup.")
          end
        end
      end
      if (do_continue or do_disable or saved_now) and S.backup_warn_code then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        -- If there's a JSFX to save alongside the Lua companion, save it first.
        if S.backup_warn_jsfx then
          Code.auto_save_jsfx(S.backup_warn_jsfx)
          S.backup_warn_jsfx = nil
        end
        S.status = "running"
        local ok = Code.run(S.backup_warn_code)
        if S.backup_warn_idx == #S.display_messages then S.pending_code = nil end
        S.status = ok and "idle" or "error"
        S.backup_warn_code = nil
        S.backup_warn_idx  = nil
        S.refocus_prompt   = true
      end

      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- ------ Resolve-type popup --------------------------------------------------
    -- Blocks the round when the model emits <context_needed>resolve:<type> and
    -- the user has no preference set. Three action paths:
    --   1. Install ReEQ (bundled fallback, EQ only)
    --   2. Type a plugin name + Use this -- saves as preferred_types.<type>
    --   3. Cancel -- for EQ, falls back to ReaEQ for this turn (no save);
    --      for other types, aborts the turn.
    if S.open_resolve_popup then
      ImGui.ImGui_OpenPopup(RA.ctx, "Choose a plugin to use...##resolve_popup")
      S.open_resolve_popup = false
      -- Arm a one-shot focus request so the custom-name field takes keyboard
      -- focus on the first render frame - user can start typing immediately.
      S.resolve_popup_refocus = true
    end
    -- Non-EQ variants don't render the Install CTA + hint line, so they need
    -- less vertical room. EQ stays at 340 to fit the primary button comfortably.
    local _rsv_type_peek = (S.resolve_popup and S.resolve_popup.type) or "plugin"
    local rsv_w = RA.SC(560)
    local rsv_h = (_rsv_type_peek == "eq") and RA.SC(340) or RA.SC(260)
    local rsv_wx, rsv_wy = ImGui.ImGui_GetWindowPos(RA.ctx)
    local rsv_ww, rsv_wh = ImGui.ImGui_GetWindowSize(RA.ctx)
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      rsv_wx + (rsv_ww - rsv_w) * 0.5,
      rsv_wy + (rsv_wh - rsv_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
    ImGui.ImGui_SetNextWindowSize(RA.ctx, rsv_w, rsv_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    -- (push_modal_style already centers WindowTitleAlign.)
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Choose a plugin to use...##resolve_popup", true,
        ImGui.ImGui_WindowFlags_NoResize()
        | ImGui.ImGui_WindowFlags_NoNavInputs()) then
      local rsv_type = (S.resolve_popup and S.resolve_popup.type) or "plugin"
      -- Display form: uppercase known acronyms (EQ, etc.) when they appear
      -- in body copy or button labels. Other types read naturally lowercase
      -- ("compressor", "reverb") and need no mapping.
      local RSV_ACRONYM = { eq = "EQ" }
      local rsv_type_display = RSV_ACRONYM[rsv_type] or rsv_type

      -- Consistent vertical gap between each logical section of the popup.
      -- Applied above and below every section so they breathe evenly.
      local SECTION_GAP = RA.SC(20)
      -- Left/right margin for the text input (applied symmetrically).
      local FIELD_MARGIN = RA.SC(50)

      -- Intro text, rendered as a single centered line. (The earlier
      -- follow-up sentence "Your choice will be saved..." was removed as
      -- scaffolding; the save behavior is discoverable from the Preferred
      -- Plugins page.)
      Dummy(RA.ctx, 1, SECTION_GAP)
      local intro_line = "You haven't set a preferred "
        .. rsv_type_display
        .. " plugin yet. Pick one to use for this request."
      local intro_w = CalcTextSize(RA.ctx, intro_line)
      local intro_avail = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx)
        + math_max(math_floor((intro_avail - intro_w) * 0.5), 0))
      Text(RA.ctx, intro_line)
      Dummy(RA.ctx, 1, SECTION_GAP)

      -- [Install ReEQ Instantly (Free)] -- EQ only. Styled as the PRIMARY
      -- call-to-action (SEND_BTN palette) because it's the zero-effort path
      -- for users who don't already own a preferred EQ. Centered on its row.
      if rsv_type == "eq" then
        local rsv_avail_w = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local reeq_btn_w  = RA.SC(260)
        SetCursorPosX(RA.ctx,
          GetCursorPosX(RA.ctx)
          + math_max(math_floor((rsv_avail_w - reeq_btn_w) * 0.5), 0))
        UI.push_modal_primary_btn()
        if ImGui.ImGui_Button(RA.ctx,
              "Install ReEQ Instantly (Free)##resolve_reeq",
              reeq_btn_w, 0) then
          local ok, err = Code.install_reeq()
          if ok then
            Log.line("RESOLVE",
              "user installed ReEQ from popup -- resuming")
            ImGui.ImGui_CloseCurrentPopup(RA.ctx)
            Net.resolve_popup_resume("ReEQ")
          else
            S.resolve_popup_error = "Install failed: "
              .. (err or "(unknown)")
          end
        end
        UI.pop_modal_primary_btn()

        -- Recommendation line under the Install button (faded, centered).
        local reeq_hint = "ReEQ is recommended for best results."
        local reeq_hint_w = CalcTextSize(RA.ctx, reeq_hint)
        local reeq_hint_avail = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        SetCursorPosX(RA.ctx,
          GetCursorPosX(RA.ctx)
          + math_max(math_floor((reeq_hint_avail - reeq_hint_w) * 0.5), 0))
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        Text(RA.ctx, reeq_hint)
        PopStyleColor(RA.ctx)

        Dummy(RA.ctx, 1, SECTION_GAP)
      end

      -- Text field + [Use this] button on the same row. The field+button
      -- pair sits inside the 50px side margins (FIELD_MARGIN). Field takes
      -- the remaining width after the button + inter-widget gap.
      local avail_w     = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      local use_btn_w   = RA.SC(96)
      local field_gap   = RA.SC(6)
      local row_w       = math_max(avail_w - FIELD_MARGIN * 2, RA.SC(200))
      local field_w     = math_max(row_w - use_btn_w - field_gap, RA.SC(80))
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx)
        + math_max(math_floor((avail_w - row_w) * 0.5), 0))
      ImGui.ImGui_PushItemWidth(RA.ctx, field_w)
      -- Input well fill: TK.input_bg reads as a recessed well on the
      -- TK.card modal surface, matching the V5 Settings inputs.
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBg(),        TK.input_bg)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgHovered(), TK.input_bg)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_FrameBgActive(),  TK.input_bg)
      -- NOTE: we intentionally do NOT use EnterReturnsTrue here. ReaImGui
      -- with that flag only returns the buffer contents on Enter (not per
      -- keystroke), which breaks the autocomplete's live filtering. We
      -- detect Enter manually via IsKeyPressed below.
      -- One-shot focus on popup open so the user can start typing immediately
      -- (blinking cursor appears in the field). Must be called on the frame
      -- BEFORE the InputText to take effect.
      if S.resolve_popup_refocus then
        ImGui.ImGui_SetKeyboardFocusHere(RA.ctx, 0)
        S.resolve_popup_refocus = false
      end
      local _changed, new_txt = ImGui.ImGui_InputTextWithHint(
        RA.ctx, "##resolve_name",
        "What plugin would you like to use?",
        S.resolve_popup_text or "", 0)
      PopStyleColor(RA.ctx, 3)
      local field_active = ImGui.ImGui_IsItemActive(RA.ctx)
      -- Capture the field's screen rect so the floating dropdown can be
      -- positioned directly below it (escaping the popup's clip region).
      local field_x1, field_y1 = ImGui.ImGui_GetItemRectMin(RA.ctx)
      local field_x2, field_y2 = ImGui.ImGui_GetItemRectMax(RA.ctx)
      -- Right-click context menu intentionally NOT attached: this field
      -- has its own autocomplete dropdown popup that would clash with
      -- the Copy/Paste/Cut popup (same rationale as the Preferred
      -- Plugins page). Native Cmd+V / Ctrl+V still work.
      -- Detect Enter EITHER while the field is active (classic "type + Enter"
      -- submit) OR whenever there's an arrow-selected autocomplete row. The
      -- second gate is essential because ReaImGui's InputText deactivates on
      -- the Enter key-press frame (IsItemActive returns false), meaning a
      -- field-active-only check would miss the commit for an arrow-selected
      -- dropdown row.
      -- Renamed from `enter_pressed` to disambiguate against the chat
      -- prompt's enter_pressed (line ~14995): different scopes, but
      -- both checked during a debug session creates avoidable
      -- confusion.
      local popup_enter_pressed = ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
      local has_ac_selection = (S.resolve_popup_sel or 0) > 0
        and S.resolve_popup_matches
        and S.resolve_popup_matches[S.resolve_popup_sel] ~= nil
      local submitted = popup_enter_pressed and (field_active or has_ac_selection)
      S.resolve_popup_text = new_txt
      ImGui.ImGui_PopItemWidth(RA.ctx)

      -- [Use this] button on the same row, immediately right of the field.
      SameLine(RA.ctx, 0, field_gap)
      local clicked_use = ImGui.ImGui_Button(RA.ctx, "Use this##resolve_use",
        use_btn_w, 0)

      -- Helper line under the field (faded, centered).
      local helper_text =
        "Enter the plugin name in the same way that it appears in the FX Browser."
      local helper_w = CalcTextSize(RA.ctx, helper_text)
      local helper_avail = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx)
        + math_max(math_floor((helper_avail - helper_w) * 0.5), 0))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      Text(RA.ctx, helper_text)
      PopStyleColor(RA.ctx)
      Dummy(RA.ctx, 1, SECTION_GAP)

      -- ---- Populate the installed FX cache lazily (shared by match +
      --      autocomplete). Do this early so the dropdown can use it.
      CTX.populate_installed_fx()

      -- ---- Build a filtered list for the dropdown: hide the VST2 ("VST:")
      --      entry for any plugin that ALSO ships a VST3 ("VST3:") version
      --      with the same base name. REAPER's EnumInstalledFX lists both
      --      bridges; the VST3 build is almost always what the user wants.
      --      The VST2 entries stay in _installed_fx_list so
      --      pref_plugins_best_match (used by the typed-text path in the
      --      Resolve popup) can still resolve them if someone explicitly
      --      types "VST: ...".
      -- _installed_fx_list_deduped is now built inside CTX.populate_
      -- installed_fx alongside _installed_fx_list itself, so no per-popup
      -- lazy build is needed here.

      -- ---- Rebuild the autocomplete list only when the filter string
      --      actually changes (per-frame filtering is wasted work).
      if new_txt ~= S.resolve_popup_last_filter then
        S.resolve_popup_last_filter = new_txt
        S.resolve_popup_sel = 0
        local trimmed = (new_txt or ""):match("^%s*(.-)%s*$") or ""
        local rank_src = CTX._installed_fx_list_deduped
          or CTX._installed_fx_list
        if trimmed == "" or not rank_src then
          S.resolve_popup_matches = {}
        else
          S.resolve_popup_matches = pref_plugins_rank_matches(
            trimmed, rank_src, 8)
        end
      end

      -- ---- Keyboard navigation inside the dropdown. We check arrows
      --      unconditionally (not gated by field_active) because ImGui's
      --      default nav may steal focus away from the InputText the
      --      instant the user presses an arrow, making field_active false
      --      by the time we check. After consuming the key we force focus
      --      back to the InputText so the user can keep typing.
      local picked_via_enter = false
      if #S.resolve_popup_matches > 0 then
        if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_DownArrow()) then
          local n = #S.resolve_popup_matches
          S.resolve_popup_sel = S.resolve_popup_sel + 1
          if S.resolve_popup_sel > n then S.resolve_popup_sel = 1 end
        elseif ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_UpArrow()) then
          local n = #S.resolve_popup_matches
          S.resolve_popup_sel = S.resolve_popup_sel - 1
          if S.resolve_popup_sel < 1 then S.resolve_popup_sel = n end
        end
      end

      -- ---- Render the dropdown list as a FLOATING window positioned just
      --      below the InputText, so it can extend past the popup's clip
      --      region. Uses ImGui_Begin with tooltip-ish flags rather than
      --      BeginChild (which would be clipped inside the popup).
      local picked_ident = nil
      if #S.resolve_popup_matches > 0 then
        local row_h = ImGui.ImGui_GetTextLineHeightWithSpacing(RA.ctx)
        -- +16 leaves room for the window's top/bottom padding so the last
        -- row isn't clipped and ImGui doesn't add an unnecessary scrollbar.
        local list_h = row_h * math_min(#S.resolve_popup_matches, 8) + 16
        local list_w = field_x2 - field_x1
        ImGui.ImGui_SetNextWindowPos(RA.ctx, field_x1, field_y2 + 2)
        ImGui.ImGui_SetNextWindowSize(RA.ctx, list_w, list_h)
        local wflags =
            ImGui.ImGui_WindowFlags_NoTitleBar()
          | ImGui.ImGui_WindowFlags_NoResize()
          | ImGui.ImGui_WindowFlags_NoMove()
          | ImGui.ImGui_WindowFlags_NoSavedSettings()
          | ImGui.ImGui_WindowFlags_NoFocusOnAppearing()
          | ImGui.ImGui_WindowFlags_NoNavInputs()
          | ImGui.ImGui_WindowFlags_NoNavFocus()
          | ImGui.ImGui_WindowFlags_NoScrollbar()
        local opened = ImGui.ImGui_Begin(RA.ctx, "##resolve_ac_popup", true, wflags)
        if opened then
          for i, ident in ipairs(S.resolve_popup_matches) do
            local is_sel = (i == S.resolve_popup_sel)
            local clicked = ImGui.ImGui_Selectable(
              RA.ctx, ident .. "##ac" .. i, is_sel)
            if clicked then
              picked_ident = ident
              S.resolve_popup_sel = i
            end
          end
          -- ImGui_End paired with Begin only on the visible path. ReaImGui
          -- auto-pops the window when Begin returns false (collapsed or
          -- fully clipped), so calling End on that path underflows the
          -- stack and trips "Calling End() too many times!". Matches the
          -- main-window pattern at line ~16387 below.
          ImGui.ImGui_End(RA.ctx)
        end
      end

      -- ---- Enter while a row is highlighted picks that row.
      if submitted and S.resolve_popup_sel > 0
            and S.resolve_popup_matches[S.resolve_popup_sel] then
        picked_ident = S.resolve_popup_matches[S.resolve_popup_sel]
        picked_via_enter = true
      end

      -- (No explicit refocus needed: the popup uses NoNavInputs so arrows
      -- never move ImGui focus away from the InputText in the first place.)

      local do_use_this = clicked_use or submitted or (picked_ident ~= nil)

      if do_use_this then
        local ident = picked_ident
        local typed = (S.resolve_popup_text or ""):match("^%s*(.-)%s*$") or ""
        -- If no explicit pick came from the dropdown, resolve via best-match
        -- against the typed text.
        if not ident then
          if typed == "" then
            S.resolve_popup_error = "Type a plugin name first."
          else
            local fx_list = CTX._installed_fx_list
            local best, score = nil, 0
            if fx_list then
              best, score = pref_plugins_best_match(typed, fx_list)
            end
            if best and score > 0 then
              ident = best
            else
              S.resolve_popup_error = "\"" .. typed
                .. "\" doesn't match any installed plugin. "
                .. "Try the name as it appears in REAPER's FX Browser."
            end
          end
        end
        if ident then
          FXCache.set_preferred_type(rsv_type, ident)
          Log.line("RESOLVE", "user chose \""
            .. (picked_via_enter and "[enter] " or "")
            .. (typed ~= "" and typed or ident)
            .. "\" -> " .. ident
            .. " (saved as preferred_types." .. rsv_type .. ")")
          ImGui.ImGui_CloseCurrentPopup(RA.ctx)
          -- Stash the popup type for resolve_popup_resume (which reads it
          -- before clearing). We need to clear S.resolve_popup BEFORE the
          -- scan kicks off so the chat status falls through from the
          -- "Waiting for your X selection..." line to the deep-scan
          -- progress display -- otherwise a slow deep scan (some CLAP
          -- plugins hit ~150s on first scan) looks like the script froze.
          local popup_snapshot = S.resolve_popup
          S.resolve_popup        = nil
          S.resolve_popup_text   = ""
          S.resolve_popup_error  = nil
          S.resolve_popup_matches     = {}
          S.resolve_popup_sel         = 0
          S.resolve_popup_last_filter = nil
          S.resolve_popup_refocus     = false
          -- Kick off a parameter scan before resuming so the follow-up turn
          -- sees real param data for the newly-picked plugin (instead of the
          -- LLM guessing parameter names). The rescan is 2-phase: phase 1
          -- inserts the plugin on a hidden temp track here, phase 2 runs one
          -- frame later from the main loop. We stash the ident in
          -- S.resolve_pending_resume; the main loop fires resolve_popup_resume
          -- once fx_cache_ui.rescan.active clears.
          -- Skip the rescan when the plugin is already cache-hot. Covers
          -- the common case of re-picking the same preferred plugin in
          -- a later session (or the same session) and avoids re-loading
          -- + probing a plugin we already know the params of. Double-add
          -- has also been observed to trigger plugin-level crashes on a
          -- handful of VST3s (Valhalla VintageVerb, specifically) that
          -- are perfectly stable under a single load + manual use but
          -- crash on rapid add/probe cycles. Skipping when cached avoids
          -- the whole class of trigger. If params are stale (plugin
          -- updated), user can force a fresh scan via FX Cache > Rescan.
          local cached = FXCache.get_plugin(ident)
          local is_cache_hot = cached and cached.params and #cached.params > 0
          if is_cache_hot then
            Log.line("RESOLVE", "skipping rescan -- " .. ident
              .. " already cached (" .. #cached.params .. " params)")
            S.resolve_popup = popup_snapshot
            Net.resolve_popup_resume(ident)
          elseif not fx_cache_ui.rescan.active and not deep_scan.active then
            CTX.fx_cache_rescan_start(ident, false)
            S.resolve_pending_resume = ident
            S.resolve_pending_type   = popup_snapshot and popup_snapshot.type or nil
            S.status = "waiting"
            Log.line("RESOLVE", "scanning " .. ident
              .. " before resume (so params land in cache)")
          else
            -- A scan is already in flight; skip and resume immediately.
            -- Rare edge case, not worth blocking the user over.
            Log.line("RESOLVE", "scan already active -- resuming without scan")
            -- Re-stash for resolve_popup_resume since we just cleared it.
            S.resolve_popup = popup_snapshot
            Net.resolve_popup_resume(ident)
          end
        end
      end

      -- Inline error (install failed, empty field, no match).
      if S.resolve_popup_error then
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
        -- Install errors can carry newlines from underlying installer
        -- output; text_multiline keeps TextWrapped safe.
        UI.text_multiline(S.resolve_popup_error)
        PopStyleColor(RA.ctx)
        Dummy(RA.ctx, 1, SECTION_GAP)
      end

      -- Fallback / cancel action. Types with a stock-REAPER equivalent get
      -- a positive-action label ("Use ReaComp instead") that proceeds with
      -- the stock plugin for THIS TURN ONLY -- never saved to pref_types
      -- (the user must explicitly add it on the Preferred Plugins page if
      -- they want it permanent). Types with no stock match keep a plain
      -- "Cancel" that aborts the turn. The button is styled as a ghost
      -- (transparent fill) so the primary Install CTA (EQ) or the
      -- custom-name field (others) stays the eye-lead.
      --
      -- Stock fallback data comes from the FALLBACK CHAINS block in
      -- Plugin_Ref.md -- single source of truth. See Code.get_stock_fallback.
      local rsv_stock = Code.get_stock_fallback(rsv_type)
      local rsv_stock_display = rsv_stock and rsv_stock.label
      local cancel_label, do_cancel = nil, false
      local cancel_btn_w
      if rsv_stock then
        cancel_label = "Use " .. rsv_stock_display .. " instead"
        -- Width scales with label length so longer names (chorus_stereo) don't
        -- clip.
        local label_w = CalcTextSize(RA.ctx, cancel_label)
        cancel_btn_w = math_max(RA.SC(160), math_floor(label_w + RA.SC(28)))
      else
        cancel_label = "Cancel"
        cancel_btn_w = RA.SC(88)
      end
      local cancel_row_avail = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      SetCursorPosX(RA.ctx,
        GetCursorPosX(RA.ctx)
        + math_max(math_floor((cancel_row_avail - cancel_btn_w) * 0.5), 0))
      -- Ghost styling: transparent normal, subtle hover/active so the
      -- button stays clickable-looking on hover without competing for
      -- attention at rest. The base modal style sets Button to card_hover;
      -- we override to fully transparent so the button reads as a link.
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Button(),        0x00000000)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonHovered(),
        UI.lerp_u32(TK.card, TK.card_hover, 0.6))
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_ButtonActive(),  TK.card_hover)
      if ImGui.ImGui_Button(RA.ctx, cancel_label, cancel_btn_w, 0) then
        do_cancel = true
      end
      PopStyleColor(RA.ctx, 3)
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        -- If the autocomplete dropdown is open, Esc dismisses it first
        -- (Claude Code slash-menu behavior) instead of canceling the popup.
        -- We suppress the dropdown by pinning last_filter to the current
        -- text so the match list won't rebuild until the user types again.
        if #S.resolve_popup_matches > 0 then
          S.resolve_popup_matches     = {}
          S.resolve_popup_sel         = 0
          S.resolve_popup_last_filter = S.resolve_popup_text
        else
          do_cancel = true
        end
      end
      if do_cancel then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        if rsv_stock then
          -- Stock-fallback path: use for THIS TURN ONLY. We never save the
          -- stock choice to pref_types -- users who want a stock plugin
          -- permanent must explicitly set it on the Preferred Plugins page.
          -- This keeps the popup firing on future generic requests so users
          -- don't silently end up on a stock-only setup without intent.
          -- The Plugin_Ref section key is passed through so the LLM gets
          -- curated param data on the resume turn.
          Log.line("RESOLVE",
            "user fell back to " .. rsv_stock.add
            .. " for type=" .. rsv_type
            .. " this turn only (not saved; popup will fire again)")
          Net.resolve_popup_resume(rsv_stock.ref)
        else
          -- No stock fallback for this type (saturation, chorus, phaser,
          -- deesser, pitch_correction, custom): full abort. Tear down the
          -- pending turn the same way the in-flight chat Cancel does.
          if S.pending_display_idx and S.display_messages[S.pending_display_idx] then
            local last = #S.display_messages
            if last > S.pending_display_idx then
              S.display_messages[last] = nil
            end
            S.display_messages[S.pending_display_idx] = nil
            if #S.history >= 1 then S.history[#S.history] = nil end
          end
          S.pending_display_idx  = nil
          S.pending_orig_prompt  = nil
          S.pending_snapshot     = nil
          S.pending_attachments  = nil
          S.pending_project      = nil
          S.pending_code         = nil
          S.resolve_popup        = nil
          S.resolve_popup_text   = ""
          S.resolve_popup_error  = nil
          S.status               = "idle"
          S.refocus_prompt       = true
          S.scroll_to_bottom     = true
          Log.line("RESOLVE",
            "popup cancelled (no stock fallback for " .. rsv_type
            .. ") -- turn aborted")
        end
      end

      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- ------ Risky-code confirmation modal --------------------------------------
    -- Shown when the risky-code scanner flags generated code. The user must
    -- explicitly confirm before execution proceeds. This is a hard gate, not
    -- just an advisory warning.
    if S.open_risky_warn then
      ImGui.ImGui_OpenPopup(RA.ctx, "Review Before Running##risky_popup")
      S.open_risky_warn = false
    end
    local rpop_w, rpop_h = RA.SC(450), RA.SC(260)
    local rwin_x, rwin_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    local rwin_w, rwin_h = ImGui.ImGui_GetWindowSize(RA.ctx)
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      rwin_x + (rwin_w - rpop_w) * 0.5,
      rwin_y + (rwin_h - rpop_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
    ImGui.ImGui_SetNextWindowSize(RA.ctx, rpop_w, rpop_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Review Before Running##risky_popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
      ImGui.ImGui_TextWrapped(RA.ctx,
        "This code uses operations that could affect files or system state "
        .. "outside of REAPER:")
      ImGui.ImGui_Spacing(RA.ctx)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
      ImGui.ImGui_TextWrapped(RA.ctx, S.risky_warn_detail or "")
      PopStyleColor(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "Review the code carefully before continuing.")
      ImGui.ImGui_Spacing(RA.ctx)

      local do_run = false
      local rbtn1_w, rbtn2_w, rgap = RA.SC(92), RA.SC(72), RA.SC(16)
      local rrow_w = rbtn1_w + rgap + rbtn2_w
      local rcw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + (rcw - rrow_w) * 0.5)
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "Run Anyway", rbtn1_w, 0) then do_run = true end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, rgap)
      if ImGui.ImGui_Button(RA.ctx, "Cancel", rbtn2_w, 0) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        S.risky_warn_code   = nil
        S.risky_warn_idx    = nil
        S.risky_warn_detail = nil
        S.refocus_prompt    = true
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        S.risky_warn_code   = nil
        S.risky_warn_idx    = nil
        S.risky_warn_detail = nil
        S.refocus_prompt    = true
      end
      if do_run and S.risky_warn_code then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        -- Still honour the backup-before-run preference.
        if prefs.auto_backup then
          -- Discard the success flag; only `berr == "unsaved"` is consumed.
          local _, berr = Code.safety_backup()
          if berr == "unsaved" then
            S.backup_warn_code = S.risky_warn_code
            S.backup_warn_idx  = S.risky_warn_idx
            S.open_backup_warn = true
            S.risky_warn_code   = nil
            S.risky_warn_idx    = nil
            S.risky_warn_detail = nil
            -- Control will continue through the backup modal.
          else
            S.status = "running"
            local ok = Code.run(S.risky_warn_code)
            if S.risky_warn_idx == #S.display_messages then S.pending_code = nil end
            S.status = ok and "idle" or "error"
            S.risky_warn_code   = nil
            S.risky_warn_idx    = nil
            S.risky_warn_detail = nil
            S.refocus_prompt    = true
          end
        else
          S.status = "running"
          local ok = Code.run(S.risky_warn_code)
          if S.risky_warn_idx == #S.display_messages then S.pending_code = nil end
          S.status = ok and "idle" or "error"
          S.risky_warn_code   = nil
          S.risky_warn_idx    = nil
          S.risky_warn_detail = nil
          S.refocus_prompt    = true
        end
      end

      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- ------ Add to Actions menu modal -----------------------------------------
    -- Shown after a successful script save. S.open_actions_modal is a deferred flag
    -- because the native file dialog is blocking; OpenPopup must be called the
    -- frame AFTER the dialog closes, not inside the button handler.
    if S.open_actions_modal then
      ImGui.ImGui_OpenPopup(RA.ctx, "Add to Actions##popup")
      S.open_actions_modal = false
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, RA.SC(340), RA.SC(150), ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Add to Actions##popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
      ImGui.ImGui_TextWrapped(RA.ctx, "Script saved. Add it to the REAPER Actions menu?")
      ImGui.ImGui_Spacing(RA.ctx)

      local do_add = false
      UI.push_modal_primary_btn()
      if ImGui.ImGui_Button(RA.ctx, "Add", RA.SC(72), 0) then do_add = true end
      UI.pop_modal_primary_btn()
      SameLine(RA.ctx, 0, RA.SC(10))
      if ImGui.ImGui_Button(RA.ctx, "Skip", RA.SC(72), 0) then
        S.saved_script_path = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      -- Enter confirms, Escape skips.
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
        do_add = true
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        S.saved_script_path = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      if do_add then
        if S.saved_script_path then
          -- AddRemoveReaScript returns the new command id, or 0 on
          -- failure (path not found, registration limit hit, etc.).
          -- Without checking, a failed add is silent: the user clicks
          -- "Add to Actions" and nothing happens.
          local cmd = reaper.AddRemoveReaScript(true, 0, S.saved_script_path, true)
          if cmd == 0 then
            UI.show_float_toast("Failed to add script to Actions menu.", "err")
          end
        end
        S.saved_script_path = nil
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end

      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- ------ No Tracks Selected popup ------------------------------------------
    if S.open_no_tracks_warn then
      ImGui.ImGui_OpenPopup(RA.ctx, "No Tracks Selected##popup")
      S.open_no_tracks_warn = false
    end
    local dlg_w, dlg_h = RA.SC(420), RA.SC(160)
    local win_x, win_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    local win_w, win_h = ImGui.ImGui_GetWindowSize(RA.ctx)
    ImGui.ImGui_SetNextWindowPos(RA.ctx,
      win_x + (win_w - dlg_w) * 0.5,
      win_y + (win_h - dlg_h) * 0.5,
      ImGui.ImGui_Cond_Appearing())
    ImGui.ImGui_SetNextWindowSize(RA.ctx, dlg_w, dlg_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "No Tracks Selected##popup", true, ImGui.ImGui_WindowFlags_NoResize()) then
      UI.text_multiline("No tracks are selected.\n\nPlease select one or more tracks and try again.")
      ImGui.ImGui_Spacing(RA.ctx)
      UI.push_modal_primary_btn()
      if ImGui.ImGui_Button(RA.ctx, "OK", RA.SC(72), 0)
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        S.refocus_prompt = true
      end
      UI.pop_modal_primary_btn()
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    -- Quit confirmation popup (Escape on main screen).
    if S._open_quit_confirm == "fire" then
      ImGui.ImGui_OpenPopup(RA.ctx, "Quit ReaAssist##quit_confirm")
      S._open_quit_confirm = nil
    end
    local quit_w, quit_h = RA.SC(300), RA.SC(140)
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - quit_w) * 0.5,
        update._main_y + (update._main_h - quit_h) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, quit_w, quit_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    S._quit_popup_open = false
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Quit ReaAssist##quit_confirm", true, ImGui.ImGui_WindowFlags_NoResize()) then
      S._quit_popup_open = true
      local qc_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      local qc_txt = "Quit ReaAssist?"
      local qc_tw  = CalcTextSize(RA.ctx, qc_txt)
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((qc_cw - qc_tw) * 0.5))
      Text(RA.ctx, qc_txt)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      local qok_w, qcancel_w, qgap = RA.SC(72), RA.SC(72), RA.SC(12)
      local qrow = qok_w + qgap + qcancel_w
      SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((qc_cw - qrow) * 0.5))
      -- Quit closes the script window -- treat as destructive so the
      -- commit button reads as an intentional "end this session" action.
      UI.push_modal_danger_btn()
      if ImGui.ImGui_Button(RA.ctx, "OK##quit_ok", qok_w, 0)
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
        S.script_open = false
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      UI.pop_modal_danger_btn()
      SameLine(RA.ctx, 0, qgap)
      if ImGui.ImGui_Button(RA.ctx, "Cancel##quit_cancel", qcancel_w, 0)
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    UI.pop_modal_style()

    end -- popup modals

    end  -- end of api_keys.screen else (main UI branch)

    UI.draw_drop_overlay()
    -- Finalize cursor after any SetCursorPosX calls (popups, centering, etc.)
    -- so ImGui can resolve window boundaries without warnings.
    Dummy(RA.ctx, 1, 0)
    -- Capture main window geometry for centering secondary windows
    -- and periodic position persistence.
    update._main_x, update._main_y = ImGui.ImGui_GetWindowPos(RA.ctx)
    update._main_w, update._main_h = ImGui.ImGui_GetWindowSize(RA.ctx)
    -- Remember the visible size for the collapse-restore handler at
    -- the top of this function -- on uncollapse it forces the window
    -- back to this size via SetNextWindowSize so ImGui doesn't snap
    -- to min_h.
    S._main_pre_collapse_w = update._main_w
    S._main_pre_collapse_h = update._main_h
    -- Save window geometry periodically (every ~2 seconds at 30fps).
    -- Skipped after Factory Reset so the freshly-cleared keys don't reappear
    -- mid-session; the flag is cleared on the next script reload.
    S._win_save_counter = (S._win_save_counter or 0) + 1
    if S._win_save_counter >= 60 and not S._suppress_geometry_save then
      S._win_save_counter = 0
      reaper.SetExtState(CFG.EXT_NS, "win_x", tostring(math.floor(update._main_x)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_y", tostring(math.floor(update._main_y)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_w", tostring(math.floor(update._main_w)), true)
      reaper.SetExtState(CFG.EXT_NS, "win_h", tostring(math.floor(update._main_h)), true)
    end
    -- Gemini Free Tier warning popup (top-level scope so it works from any
    -- page -- tier detection typically fires while the user is still on the
    -- Settings screen after Test API Keys or Save & Continue, and the popup
    -- needs to open on the same frame regardless of which screen is active).
    if S.show_gemini_free_warn then
      ImGui.ImGui_OpenPopup(RA.ctx, "Gemini Free Tier##warn")
      S.show_gemini_free_warn = false
    end
    local gem_w, gem_h_est = RA.SC(470), RA.SC(450)  -- h is estimated for centering
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - gem_w) * 0.5,
        update._main_y + (update._main_h - gem_h_est) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, gem_w, 0, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    -- Gemini popup uses a slightly tighter pad than the V5 default so four
    -- stacked buttons + three paragraphs fit comfortably. Overrides the
    -- WindowPadding from push_modal_style; paired with the PopStyleVar
    -- below the EndPopup call.
    local gem_pad = RA.SC(15)
    PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_WindowPadding(), gem_pad, gem_pad)
    if ImGui.ImGui_BeginPopupModal(RA.ctx, "Gemini Free Tier##warn", true, ImGui.ImGui_WindowFlags_NoResize()) then
      local inner_w = gem_w - gem_pad * 2  -- popup width minus WindowPadding
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.amber)
      local ftd_w = CalcTextSize(RA.ctx, "Free Tier Detected")
      local ftd_off = (inner_w - ftd_w) * 0.5
      if ftd_off > 0 then SetCursorPosX(RA.ctx, gem_pad + ftd_off) end
      Text(RA.ctx, "Free Tier Detected")
      PopStyleColor(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "Your Gemini API key appears to be on Google's free tier. On the free "
        .. "tier, Google may use your prompts and responses to improve their "
        .. "models. This can include human review of your data.")
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "This means project details like track names, plugin settings, and any "
        .. "code you send could be seen by reviewers or used in training data. "
        .. "Note that ReaAssist never sends or receives audio. Only text, "
        .. "code, and project metadata.")
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "For professional or client work, consider enabling billing on your "
        .. "Google account. Paid accounts are not used for training and have "
        .. "higher rate limits. The Pro model has been hidden as it requires "
        .. "a paid account. Flash and Flash Lite remain available.")
      ImGui.ImGui_Spacing(RA.ctx)
      PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
      ImGui.ImGui_TextWrapped(RA.ctx,
        "If you enable billing later, use the Test API Keys button on the Settings "
        .. "screen to update your account status.")
      PopStyleColor(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      ImGui.ImGui_Spacing(RA.ctx)
      -- Centered button rows (each on its own line).
      -- Row 1: primary acknowledgement.
      local btn1_label = "I Understand"
      local btn1_w = CalcTextSize(RA.ctx, btn1_label) + 24
      local off1 = (inner_w - btn1_w) * 0.5
      if off1 > 0 then SetCursorPosX(RA.ctx, gem_pad + off1) end
      UI.push_modal_primary_btn()
      if ImGui.ImGui_Button(RA.ctx, btn1_label, btn1_w, 0) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      UI.pop_modal_primary_btn()
      -- Row 2: Enable Billing.
      ImGui.ImGui_Spacing(RA.ctx)
      local btn2_label = "Enable Billing with Google"
      local btn2_w = CalcTextSize(RA.ctx, btn2_label) + 24
      local off2 = (inner_w - btn2_w) * 0.5
      if off2 > 0 then SetCursorPosX(RA.ctx, gem_pad + off2) end
      if ImGui.ImGui_Button(RA.ctx, btn2_label, btn2_w, 0) then
        UI.open_url("https://aistudio.google.com/billing")
      end
      if ImGui.ImGui_IsItemHovered(RA.ctx) then
        ImGui.ImGui_SetMouseCursor(RA.ctx, ImGui.ImGui_MouseCursor_Hand())
      end
      -- Recheck row (centered).
      ImGui.ImGui_Spacing(RA.ctx)
      local recheck_label = "I've Enabled Billing - Recheck Account Now"
      local recheck_w = CalcTextSize(RA.ctx, recheck_label) + 24
      local off3 = (inner_w - recheck_w) * 0.5
      if off3 > 0 then SetCursorPosX(RA.ctx, gem_pad + off3) end
      if ImGui.ImGui_Button(RA.ctx, recheck_label, recheck_w, 0) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        Net.fire_gemini_tier_test()
      end
      -- Manual override row (centered).
      ImGui.ImGui_Spacing(RA.ctx)
      local mark_label = "Incorrectly Detected as Free. Mark as Paid."
      local mark_w = CalcTextSize(RA.ctx, mark_label) + 24
      local off4 = (inner_w - mark_w) * 0.5
      if off4 > 0 then SetCursorPosX(RA.ctx, gem_pad + off4) end
      if ImGui.ImGui_Button(RA.ctx, mark_label, mark_w, 0) then
        S.gemini_paid_tier = true
        reaper.SetExtState(CFG.EXT_NS, "gemini_paid_tier", "true", true)
        if PROVIDERS.active().id == "google" then MODELS.refresh() end
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      if ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter())
        or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
        ImGui.ImGui_CloseCurrentPopup(RA.ctx)
      end
      ImGui.ImGui_EndPopup(RA.ctx)
    end
    ImGui.ImGui_PopStyleVar(RA.ctx)   -- gem_pad WindowPadding override
    UI.pop_modal_style()

    -- Scale confirmation countdown popup (top-level scope so it works from any page).
    if S._open_scale_confirm then
      ImGui.ImGui_OpenPopup(RA.ctx, "Confirm UI Scale##scale_confirm")
      S._open_scale_confirm = nil
    end
    -- Auto-revert if timer expired.
    if S._scale_confirm_deadline and reaper.time_precise() >= S._scale_confirm_deadline then
      prefs.ui_scale_idx = S._scale_prev_idx
      S._scale_confirm_deadline = nil
      S._scale_prev_idx = nil
    end
    if S._scale_confirm_deadline then
      local sc_pw, sc_ph = RA.SC(300), RA.SC(120)
      if update._main_w then
        ImGui.ImGui_SetNextWindowPos(RA.ctx,
          update._main_x + (update._main_w - sc_pw) * 0.5,
          update._main_y + (update._main_h - sc_ph) * 0.5,
          ImGui.ImGui_Cond_Appearing())
      end
      ImGui.ImGui_SetNextWindowSize(RA.ctx, sc_pw, sc_ph, ImGui.ImGui_Cond_Appearing())
      UI.push_modal_style()
      if ImGui.ImGui_BeginPopupModal(RA.ctx, "Confirm UI Scale##scale_confirm", true, ImGui.ImGui_WindowFlags_NoResize()) then
        local sc_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local remaining = math.ceil(S._scale_confirm_deadline - reaper.time_precise())
        ImGui.ImGui_Spacing(RA.ctx)
        local sc_txt = string.format("Reverting in %ds...", remaining)
        local sc_tw = CalcTextSize(RA.ctx, sc_txt)
        SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((sc_cw - sc_tw) * 0.5))
        Text(RA.ctx, sc_txt)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Spacing(RA.ctx)
        local keep_w, revert_w, sc_gap = RA.SC(84), RA.SC(92), RA.SC(12)
        local sc_row = keep_w + sc_gap + revert_w
        SetCursorPosX(RA.ctx, GetCursorPosX(RA.ctx) + math_floor((sc_cw - sc_row) * 0.5))
        UI.push_modal_primary_btn()
        if ImGui.ImGui_Button(RA.ctx, "Keep Scale", keep_w, 0)
          or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Enter())
          or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_KeypadEnter()) then
          S._scale_confirm_deadline = nil
          S._scale_prev_idx = nil
          ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        end
        UI.pop_modal_primary_btn()
        SameLine(RA.ctx, 0, sc_gap)
        if ImGui.ImGui_Button(RA.ctx, "Revert Now", revert_w, 0)
          or ImGui.ImGui_IsKeyPressed(RA.ctx, ImGui.ImGui_Key_Escape()) then
          prefs.ui_scale_idx = S._scale_prev_idx
          S._scale_confirm_deadline = nil
          S._scale_prev_idx = nil
          ImGui.ImGui_CloseCurrentPopup(RA.ctx)
        end
        ImGui.ImGui_EndPopup(RA.ctx)
      end
      UI.pop_modal_style()
    end

    -- Fade-in overlay: once content has rendered at least one real
    -- frame (i.e. we passed the boot guard), paint a TK.bg-colored
    -- rect over the window on the foreground draw list with alpha
    -- decreasing from 0xFF to 0x00 over FADE_MS ms. The user sees the
    -- content reveal as a soft fade rather than a hard pop-in. Cost
    -- is one extra rect per frame for ~12 frames at 60fps -- free.
    S._boot_fade_start = S._boot_fade_start or time_precise()
    do
      local FADE_MS   = 500
      local elapsed_ms = (time_precise() - S._boot_fade_start) * 1000
      if elapsed_ms < FADE_MS then
        local fade_alpha = 1 - (elapsed_ms / FADE_MS)
        local alpha_byte = math_floor(fade_alpha * 0xFF + 0.5)
        if alpha_byte > 0 then
          local wx, wy  = ImGui.ImGui_GetWindowPos(RA.ctx)
          local ww, wh  = ImGui.ImGui_GetWindowSize(RA.ctx)
          local fdl     = ImGui.ImGui_GetForegroundDrawList(RA.ctx)
          local overlay = (TK.bg & 0xFFFFFF00) | alpha_byte
          ImGui.ImGui_DrawList_AddRectFilled(fdl,
            wx, wy, wx + ww, wy + wh, overlay)
        end
      end
    end

    -- Floating toast: rendered while still inside the main window's Begin
    -- block (so the toast's SetNextWindowPos anchor uses fresh main-window
    -- screen coords from GetWindowPos/Size). The toast's own Begin creates
    -- a separate top-level window -- it's not nested inside the main one;
    -- ImGui just re-enters global-window mode for the nested call.
    do
      local _tx, _ty = ImGui.ImGui_GetWindowPos(RA.ctx)
      local _tw, _th = ImGui.ImGui_GetWindowSize(RA.ctx)
      UI.render_float_toast(_tx, _ty, _tw, _th)
    end

    -- Manual feedback dialog + safety output ceiling alert. Both
    -- rendered HERE (inside the main window's Begin/End) rather than
    -- after End so the popup-modals stay glued to the main script
    -- window for ReaImGui's OS-level window management. Opened from
    -- outside this scope, the popup z-orders behind the main window
    -- when REAPER focus shifts to it, leaving the dim overlay painted
    -- on the main window's surface with no visible popup to interact
    -- with -- the user has to hit Esc to recover. Same call-site
    -- pattern as the Settings page's per-row "Details" popup, which
    -- lives inside its render scope and doesn't have this z-order bug.
    Render.feedback_modal()
    Render._ceiling_alert_popup()

    -- Landing point for the first-frame boot guard at the top of this
    -- block. When content is skipped on frame 1, the goto above jumps
    -- here so End still runs on the visible-but-skipped path. Kept as
    -- the last statement in the if-visible block so the goto doesn't
    -- jump into the scope of locals declared between the goto and
    -- label (e.g. gem_w) -- Lua only allows a goto into a label that
    -- sits at the very end of its enclosing block.
    ::after_main_window::
  end
  -- ImGui_End is paired with Begin only on the visible path. ReaImGui
  -- auto-pops the window when Begin returns false (collapsed or fully
  -- clipped), so calling End on that path underflows the stack and
  -- trips "Calling End() too many times!". Style-stack pops below stay
  -- unconditional -- they balance pushes done before Begin and are
  -- independent of the window stack.
  if visible then ImGui.ImGui_End(RA.ctx) end
  PopStyleColor(RA.ctx, 8)  -- WindowBg, ChildBg, PopupBg, Text, TitleBg, TitleBgActive, SeparatorHovered, SeparatorActive
  ImGui.ImGui_PopStyleVar(RA.ctx, 2)    -- WindowPadding, WindowBorderSize
  PopFont(RA.ctx)

  -- ------ Update Available dialog (separate window) ----------------------------
  -- Show dialog when update OR repair is available (or downloading/done for
  -- progress). Both triggers surface the same popup window; the prompt copy
  -- differs ("ReaAssist vX is available" vs "N files need to be restored"),
  -- but the download progress, completion, and failure views are shared.
  if (update.state == "available" or update.state == "repair_available")
      and not update.popup_opened then
    update.show_dialog = true
    update.popup_opened = true
  end
  if update.show_dialog then
    -- Width fits the longest single line (the "Update Available"
    -- title with a version number on each side). Height varies by
    -- view shape: the update-available and repair-available prompts
    -- both carry three text rows (title, detail / desc, extra info)
    -- above the button, while the done / failed views only have a
    -- title + a one-line sub-message.
    local dlg_w = RA.SC(400)
    local dlg_h
    if update.state == "available" or update.state == "repair_available" then
      dlg_h = RA.SC(180)
    else
      dlg_h = RA.SC(150)
    end
    -- Center on the main ReaAssist window.
    if update._main_w then
      ImGui.ImGui_SetNextWindowPos(RA.ctx,
        update._main_x + (update._main_w - dlg_w) * 0.5,
        update._main_y + (update._main_h - dlg_h) * 0.5,
        ImGui.ImGui_Cond_Appearing())
    end
    ImGui.ImGui_SetNextWindowSize(RA.ctx, dlg_w, dlg_h, ImGui.ImGui_Cond_Appearing())
    UI.push_modal_style()
    PushFont(RA.ctx, nil, RA.SC(14))
    local dlg_flags = ImGui.ImGui_WindowFlags_NoResize()
      + ImGui.ImGui_WindowFlags_NoCollapse()
      + ImGui.ImGui_WindowFlags_NoDocking()
      + ImGui.ImGui_WindowFlags_NoScrollbar()
    -- Title switches between "Update Available" and "Files Need Repair"
    -- depending on whether the popup was triggered by a version bump or
    -- by the check-time SHA diff (Stage 3.2). Once a download is running,
    -- update.action_was_repair (set in download_start) drives the title
    -- so the user sees consistent framing through the progress view.
    local is_repair_prompt = (update.state == "repair_available")
    local is_repair_action = is_repair_prompt or update.action_was_repair
    local dlg_title = is_repair_action
                        and "ReaAssist - Files Need Repair"
                        or  "Update Available"
    -- No close (X) button on the repair-prompt state: we require the
    -- user to click Repair Now so they cannot operate with a broken
    -- install. All other states (update-available, downloading, done,
    -- failed) have explicit dismissal buttons, so the X is a safe
    -- redundant escape hatch there. Users who genuinely need to bail
    -- on the repair prompt can close the main ReaAssist window or
    -- quit REAPER; the next session's piggyback check re-surfaces it.
    local show_close = not is_repair_prompt
    local dlg_visible, dlg_open = ImGui.ImGui_Begin(RA.ctx,
      dlg_title, show_close or nil, dlg_flags)
    if dlg_visible then
      if update.state == "downloading" or update.state == "rename_retry" then
        -- Download progress view. Verb switches for repair sessions so the
        -- user knows we're restoring missing/corrupted files, not replacing
        -- them with a new version.
        local dlg_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local verb = update.action_was_repair and "Restoring files"
                                               or "Downloading update"
        local prog_text = verb .. " (" .. update.download_idx .. "/"
                               .. #update.download_queue .. ")..."
        local prog_w = CalcTextSize(RA.ctx, prog_text)
        SetCursorPosX(RA.ctx, (dlg_cw - prog_w) * 0.5)
        Text(RA.ctx, prog_text)
        ImGui.ImGui_Spacing(RA.ctx)
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        local entry = update.download_queue[update.download_idx]
        local fname = entry and entry.filename or ""
        local fname_w = CalcTextSize(RA.ctx, fname)
        SetCursorPosX(RA.ctx, (dlg_cw - fname_w) * 0.5)
        Text(RA.ctx, fname)
        PopStyleColor(RA.ctx)
      elseif update.state == "done" then
        -- Completion view. Different copy for repair sessions so "Updated to
        -- vX" does not mislead when the version did not change. When
        -- auto-restart is scheduled (CMD_ID is valid), the instruction line
        -- says "Restarting..." instead of "Close and reopen..." so the user
        -- knows they do not need to do anything. The OK button stays as a
        -- manual override in either case.
        local dlg_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local done_text, inst_text
        local auto_restart_pending = update.restart_after
                                       and not update.restart_fired
        if update.action_was_repair then
          local n = #(update.applied_files or {})
          done_text = string.format(
            "Restored %d file%s successfully.", n, n == 1 and "" or "s")
          inst_text = auto_restart_pending
            and "Restarting to load the restored files..."
            or  "Close and reopen ReaAssist to reload the restored files."
        else
          done_text = "Updated to v" .. (update.remote_version or "?") .. " successfully."
          inst_text = auto_restart_pending
            and "Restarting to apply the new version..."
            or  "Close and reopen ReaAssist to start using the new version."
        end
        local done_w = CalcTextSize(RA.ctx, done_text)
        SetCursorPosX(RA.ctx, (dlg_cw - done_w) * 0.5)
        Text(RA.ctx, done_text)
        ImGui.ImGui_Spacing(RA.ctx)
        local inst_w = CalcTextSize(RA.ctx, inst_text)
        SetCursorPosX(RA.ctx, (dlg_cw - inst_w) * 0.5)
        ImGui.ImGui_TextWrapped(RA.ctx, inst_text)
        ImGui.ImGui_Spacing(RA.ctx)
        local ok_w = RA.SC(72)
        SetCursorPosX(RA.ctx, (dlg_cw - ok_w) * 0.5)
        if ImGui.ImGui_Button(RA.ctx, "OK", ok_w, 0) then
          update.show_dialog = false
        end
      elseif update.state == "failed" then
        -- Failure view. Branches by failure step so the user gets a
        -- message that matches the actual cause rather than a single
        -- generic line:
        --   sha_verify     -> CDN propagation lag, retry after a wait
        --   content_verify -> downloaded file is not ReaAssist content
        --                     (proxy interception or wrong server),
        --                     no point hammering Retry without diagnosis
        --   anything else  -> generic copy with ReaPack fallback hint
        --
        -- The sha_verify branch is the common case immediately after a
        -- new release: GitHub's raw CDN serves stale bytes from edge
        -- nodes that haven't propagated yet, the downloaded file's SHA
        -- doesn't match the freshly-fetched manifest's expected value,
        -- and we surface a "files temporarily out of sync" failure.
        -- Hammering Retry within the propagation window keeps failing;
        -- waiting 1-2 minutes and then retrying succeeds. Calling that
        -- out explicitly saves users from the rapid-fire frustration.
        local dlg_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local noun = update.action_was_repair and "Repair" or "Update"
        local fail_text
        if update.last_step == "sha_verify" then
          fail_text = noun .. " files temporarily out of sync. "
                   .. "GitHub's CDN may still be propagating a new "
                   .. "release. Wait a minute or two, then click Retry."
        elseif update.last_step == "content_verify" then
          fail_text = noun .. " aborted: a downloaded file did not "
                   .. "look like ReaAssist content. This usually means "
                   .. "a captive portal, proxy, or VPN is intercepting "
                   .. "the download. Check your network, then Retry."
        else
          fail_text = noun .. " failed. Click Retry, or "
                   .. (update.action_was_repair and "reinstall"
                                                  or "sync")
                   .. " via ReaPack if the problem persists."
        end
        local fail_w = CalcTextSize(RA.ctx, fail_text)
        SetCursorPosX(RA.ctx, (dlg_cw - fail_w) * 0.5)
        ImGui.ImGui_TextWrapped(RA.ctx, fail_text)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Spacing(RA.ctx)
        -- Two-button row: Retry (primary) | OK. Retry calls
        -- force_reinstall, which re-fetches the manifest fresh and
        -- re-runs the download flow from scratch -- equivalent to
        -- the "close + reopen + Check for Updates" workaround the
        -- user previously had to do manually after a failed install.
        -- The fresh manifest fetch also gives the GitHub raw CDN a
        -- chance to propagate any stale-file mismatch that caused
        -- the initial failure. OK just dismisses; next manual Check
        -- for Updates (or next-session piggyback) re-surfaces from
        -- the standard path.
        local btn1_w, btn2_w, gap = RA.SC(80), RA.SC(72), RA.SC(16)
        local row_w = btn1_w + gap + btn2_w
        SetCursorPosX(RA.ctx, (dlg_cw - row_w) * 0.5)
        UI.push_modal_primary_btn()
        if ImGui.ImGui_Button(RA.ctx, "Retry", btn1_w, 0) then
          -- Close dialog so the auto-show guard re-fires when
          -- check_poll transitions state back to "available" /
          -- "repair_available" after the fresh manifest fetch lands.
          update.show_dialog = false
          Updater.force_reinstall()
        end
        UI.pop_modal_primary_btn()
        SameLine(RA.ctx, 0, gap)
        if ImGui.ImGui_Button(RA.ctx, "OK", btn2_w, 0) then
          update.show_dialog = false
        end
      elseif is_repair_prompt then
        -- Repair-available prompt (version matches but files missing/corrupt).
        -- N.B.: No "Remind Me Later" snooze here -- repair is not a deferrable
        -- event like a new version announcement. The user can dismiss with OK
        -- for the current session, but we want to re-prompt on the next launch
        -- if the files are still broken.
        local dlg_cw  = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local missing = #(update.repair_missing    or {})
        local mismatched = #(update.repair_mismatched or {})
        local total   = missing + mismatched
        local title_text = string.format(
          "%d ReaAssist file%s %s to be restored from v%s.",
          total,
          total == 1 and "" or "s",
          total == 1 and "needs" or "need",
          CFG.VERSION)
        local title_w = CalcTextSize(RA.ctx, title_text)
        SetCursorPosX(RA.ctx, (dlg_cw - title_w) * 0.5)
        ImGui.ImGui_TextWrapped(RA.ctx, title_text)
        ImGui.ImGui_Spacing(RA.ctx)
        -- Breakdown line (quietly styled) telling the user what was found.
        PushStyleColor(RA.ctx, ImGui.ImGui_Col_Text(), TK.text_muted)
        local detail
        if missing > 0 and mismatched > 0 then
          detail = string.format("(%d missing, %d modified or corrupted)",
                                 missing, mismatched)
        elseif missing > 0 then
          detail = string.format("(%d missing)", missing)
        else
          detail = string.format("(%d modified or corrupted)", mismatched)
        end
        local detail_w = CalcTextSize(RA.ctx, detail)
        SetCursorPosX(RA.ctx, (dlg_cw - detail_w) * 0.5)
        Text(RA.ctx, detail)
        PopStyleColor(RA.ctx)
        ImGui.ImGui_Spacing(RA.ctx)
        -- Reassurance copy: mirror the update-available dialog's
        -- "The update is quick and applies directly" framing so the
        -- user knows the Repair Now button handles everything end
        -- to end -- no manual download or install required.
        local info_text = "Automatic repair - No manual download needed."
        local info_w = CalcTextSize(RA.ctx, info_text)
        SetCursorPosX(RA.ctx, (dlg_cw - info_w) * 0.5)
        Text(RA.ctx, info_text)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Spacing(RA.ctx)
        -- Single "Repair Now" button, centered. Repair is required:
        -- a user operating a corrupted install is a bug waiting to
        -- happen, so we offer no dismissal path -- the title-bar X
        -- is also suppressed for this state (see the dlg_visible
        -- block above). Users who genuinely need to bail out can
        -- close the main ReaAssist window or quit REAPER; the next
        -- session's chat-piggyback re-surfaces the prompt.
        local btn_w = RA.SC(112)
        SetCursorPosX(RA.ctx, (dlg_cw - btn_w) * 0.5)
        UI.push_modal_primary_btn()
        if ImGui.ImGui_Button(RA.ctx, "Repair Now", btn_w, 0) then
          Updater.download_start()
        end
        UI.pop_modal_primary_btn()
      else
        -- Default: update available prompt (new version on server).
        local dlg_cw = ImGui.ImGui_GetContentRegionAvail(RA.ctx)
        local title_text = "ReaAssist v" .. (update.remote_version or "?")
          .. " is available (you have v" .. CFG.VERSION .. ")."
        local title_w = CalcTextSize(RA.ctx, title_text)
        SetCursorPosX(RA.ctx, (dlg_cw - title_w) * 0.5)
        ImGui.ImGui_TextWrapped(RA.ctx, title_text)
        ImGui.ImGui_Spacing(RA.ctx)
        local desc1 = "The update is quick and applies directly."
        local desc1_w = CalcTextSize(RA.ctx, desc1)
        SetCursorPosX(RA.ctx, (dlg_cw - desc1_w) * 0.5)
        Text(RA.ctx, desc1)
        local desc2 = "(No manual download needed)"
        local desc2_w = CalcTextSize(RA.ctx, desc2)
        SetCursorPosX(RA.ctx, (dlg_cw - desc2_w) * 0.5)
        Text(RA.ctx, desc2)
        ImGui.ImGui_Spacing(RA.ctx)
        ImGui.ImGui_Spacing(RA.ctx)
        -- Centered button row: Update Now (primary) + Later. Later
        -- dismisses AND snoozes for 7 days so the daily auto-check
        -- does not re-nag the user for a week; clicking the footer
        -- version link or hitting Settings > Check for Updates still
        -- bypasses the snooze for an on-demand check. Widths sized
        -- so both labels sit with comfortable padding (previously
        -- "Update Now" at SC(88) read as tight next to the chrome).
        local btn1_w, btn2_w, gap = RA.SC(104), RA.SC(80), RA.SC(16)
        local row1_w = btn1_w + gap + btn2_w
        SetCursorPosX(RA.ctx, (dlg_cw - row1_w) * 0.5)
        UI.push_modal_primary_btn()
        if ImGui.ImGui_Button(RA.ctx, "Update Now", btn1_w, 0) then
          Updater.download_start()
        end
        UI.pop_modal_primary_btn()
        SameLine(RA.ctx, 0, gap)
        if ImGui.ImGui_Button(RA.ctx, "Later", btn2_w, 0) then
          update.show_dialog = false
          -- Persist a 7-day snooze so the daily auto-check does not
          -- re-nag; check_poll() reads this key and (for piggyback
          -- checks only -- forced/manual paths bypass the snooze)
          -- pre-flips popup_opened so the auto-show guard treats the
          -- "available" state as already-shown. The fetch itself is
          -- not gated; we always need a fresh manifest to compute the
          -- local-vs-remote SHA diff.
          local snooze_until = os.time() + 7 * 24 * 3600
          reaper.SetExtState(CFG.EXT_NS, "update_snooze",
            tostring(snooze_until), true)
        end
      end
    end
    -- ImGui_End is called outside the visible block per the Dear ImGui
    -- contract: Begin returns false when the window is collapsed or fully
    -- clipped, but End must still be called either way.
    ImGui.ImGui_End(RA.ctx)
    -- Only react to dlg_open going false when the X button was
    -- actually rendered -- otherwise ImGui returns nil / false for
    -- the missing-p_open case and we would dismiss the repair prompt
    -- without the user touching it.
    if show_close and not dlg_open then
      update.show_dialog = false
    end
    PopFont(RA.ctx)
    UI.pop_modal_style()
  end

  return open
end

-- ---------------------------------------------------------------------------
-- Text utilities and drop target
-- ---------------------------------------------------------------------------
-- Pure-Lua text helpers used across the chat display (word wrap,
-- markdown strip, table parsing, height measurement with caching) and
-- UI.drop_target, the drag-drop hook used by the chat input.

-- =============================================================================
-- Utility: UI.text_multiline
-- =============================================================================
-- Splits a string on newlines and renders each line via ImGui_TextWrapped.
-- Required because ImGui_TextWrapped corrupts internal window state when passed
-- strings containing literal \n characters.
--
-- Also strips **bold** and *italic* markdown markers (double asterisks first to
-- avoid stray single asterisks). Inline backtick spans are temporarily replaced
-- with placeholders during stripping, then restored without the backtick markers.
--
-- NOTE: Used for status labels and short UI text only. All chat message
-- content uses UI.selectable_text() instead (click-drag selection, copy,
-- and Lua word-wrapping).
function UI.text_multiline(text)
  local t = text or ""
  if #t == 0 then ImGui.ImGui_TextWrapped(RA.ctx, " "); return end
  local pos = 1
  while pos <= #t do
    local nl   = str_find(t, "\n", pos, true)
    local line = nl and str_sub(t, pos, nl - 1) or str_sub(t, pos)

    -- Protect inline backtick spans from stripping.
    local saved = {}
    line = line:gsub("`([^`]+)`", function(code)
      saved[#saved+1] = code
      return "\0CODE" .. #saved .. "\0"
    end)

    line = line:gsub("%*%*(.-)%*%*", "%1")  -- strip **bold**
    line = line:gsub("%*(.-)%*", "%1")      -- strip *italic*

    -- Restore backtick spans (without the backtick markers for clean display).
    line = line:gsub("\0CODE(%d+)\0", function(idx)
      return saved[tonumber(idx)] or ""
    end)

    ImGui.ImGui_TextWrapped(RA.ctx, line ~= "" and line or " ")
    if not nl then break end
    pos = nl + 1
  end
end

-- =============================================================================
-- Utility: UI.strip_markdown
-- =============================================================================
-- Returns the string with **bold** and *italic* markers stripped, and inline
-- backtick content preserved (backtick delimiters removed). Used by
-- UI.selectable_text() to clean chat content before display.
--
-- Also replaces leading list markers (`- `, `* `, `+ `) with a Unicode bullet
-- and a two-space indent so the AI's bullet lists render with visual hierarchy
-- instead of as raw dashes flush against the left margin. Heading markers
-- (`#`/`##`/`###`) are NOT touched here -- selectable_text() detects heading
-- lines before strip_markdown is applied so they can be rendered in a larger
-- font.
function UI.strip_markdown(text)
  local t = text or ""
  -- Protect inline backtick spans.
  local saved = {}
  t = t:gsub("`([^`]+)`", function(code)
    saved[#saved+1] = code
    return "\0CODE" .. #saved .. "\0"
  end)
  t = t:gsub("%*%*(.-)%*%*", "%1")
  t = t:gsub("%*(.-)%*", "%1")
  -- Bullet-ify list markers at line starts. The leading "(\n)" / "^" capture
  -- ensures we only match list markers at the start of a line, not mid-text
  -- where a hyphen could be part of a word or range. The bullet "*" is a
  -- BMP character handled correctly by ImGui's default font.
  t = t:gsub("^[%-%*%+] +", "  \xE2\x80\xA2 ")
  t = t:gsub("\n[%-%*%+] +",  "\n  \xE2\x80\xA2 ")
  t = t:gsub("\0CODE(%d+)\0", function(idx)
    return saved[tonumber(idx)] or ""
  end)
  return t
end

-- =============================================================================
-- Utility: parse_md_table (file-private, forward-declared near top-of-file)
-- =============================================================================
-- Parses contiguous markdown table rows starting at lines[start_i].
-- Returns a list of rows (each a list of trimmed cell strings) and the next
-- line index. Separator rows (|---|---|) are skipped. Single caller is
-- UI.selectable_text; not exposed on UI.* because it is not part of the
-- public widget surface.
function parse_md_table(lines, start_i)
  local rows = {}
  local i = start_i
  while i <= #lines and lines[i]:match("^%s*|") do
    local row = lines[i]
    -- Skip separator rows like |---|---|
    if not row:match("^%s*|%s*[:-]+[|-]+%s*$") then
      row = row:match("^%s*|(.-)%s*$") or row
      if row:sub(-1) == "|" then row = row:sub(1, -2) end
      local cells = {}
      for cell in (row .. "|"):gmatch("(.-)|") do
        cells[#cells+1] = cell:match("^%s*(.-)%s*$") or ""
      end
      rows[#rows+1] = cells
    end
    i = i + 1
  end
  return rows, i
end

-- =============================================================================
-- Utility: UI.wrap_text
-- =============================================================================
-- Inserts explicit \n characters so no line exceeds chars_per_line characters.
-- Wraps at word boundaries; hard-breaks individual words that exceed the column.
-- Existing \n characters are preserved as paragraph separators.
function UI.wrap_text(text, chars_per_line)
  -- Defensive clamp: a 0 or negative width would never let the inner
  -- slicing loop (str_sub(combo, 1, chars_per_line) below) advance,
  -- producing an infinite loop / UI freeze. No current caller passes
  -- such a value, but the function is reusable enough to be worth
  -- guarding.
  chars_per_line = math.max(1, tonumber(chars_per_line) or 80)
  local out = {}
  local pos = 1
  local len = #text
  while pos <= len do
    -- Find end of current paragraph (next \n or end of string).
    local nl  = str_find(text, "\n", pos, true)
    local para = nl and str_sub(text, pos, nl - 1) or str_sub(text, pos)
    pos = nl and (nl + 1) or (len + 1)

    if #para == 0 then
      out[#out+1] = ""
    else
      -- Capture leading whitespace as a non-breaking indent that prefixes
      -- the first physical line of this paragraph. Without this, runs of
      -- leading spaces would each be parsed as zero-length "words" and
      -- inserted into `out` as blank lines (e.g. bullet items rendered as
      -- "  * Foo" would gain two blank lines before each bullet).
      local indent = str_match(para, "^( +)") or ""
      local i = #indent + 1
      local plen = #para
      local col = 0
      local need_indent = true  -- prepend indent to first word of paragraph
      while i <= plen do
        -- Find next word boundary (space) or end of paragraph.
        local sp = str_find(para, " ", i, true)
        local word_end = sp and (sp - 1) or plen
        local word = str_sub(para, i, word_end)
        local wlen = #word

        if wlen == 0 then
          -- Sitting on a consecutive space: skip it without emitting a
          -- blank line. Internal runs of spaces collapse to a single gap.
          i = sp + 1
        else
          if col == 0 then
            -- First word on the line.
            local prefix = need_indent and indent or ""
            need_indent = false
            local combined_len = #prefix + wlen
            if combined_len > chars_per_line then
              -- Hard-break the prefix+word combo.
              local combo = prefix .. word
              while #combo > 0 do
                out[#out+1] = str_sub(combo, 1, chars_per_line)
                combo = str_sub(combo, chars_per_line + 1)
              end
              col = 0
            else
              out[#out+1] = prefix .. word
              col = combined_len
            end
          elseif col + 1 + wlen > chars_per_line then
            -- Word doesn't fit: start a new line.
            if wlen > chars_per_line then
              -- Hard-break a very long word.
              local remaining = chars_per_line - col - 1
              if remaining > 0 then
                out[#out] = out[#out] .. " " .. str_sub(word, 1, remaining)
                word = str_sub(word, remaining + 1)
              end
              while #word > 0 do
                out[#out+1] = str_sub(word, 1, chars_per_line)
                word = str_sub(word, chars_per_line + 1)
              end
              col = 0
            else
              out[#out+1] = word
              col = wlen
            end
          else
            -- Word fits on the current line.
            out[#out] = out[#out] .. " " .. word
            col = col + 1 + wlen
          end

          i = sp and (sp + 1) or (plen + 1)
        end
      end
    end
  end
  return tbl_concat(out, "\n")
end

-- =============================================================================
-- Wrap cache
-- =============================================================================
-- Caches wrapped text and line counts to avoid re-wrapping every frame.
-- Keyed by raw text; each entry stores the chars_per_line it was wrapped at
-- so the cache auto-invalidates on resize. Cleared on Net.clear_conversation().

function UI.get_wrap_cached(raw_text, chars_per_line)
  -- Cache keyed on (text, chars_per_line, font_idx). Font index is included so
  -- that any future change making chars_per_line scale with font size (instead
  -- of the hardcoded 14px calibration currently used) auto-invalidates stale
  -- entries without needing an explicit flush on font change.
  --
  -- Returns (wrapped_string, line_count, lines_array). wrapped_string is
  -- the "\n"-joined form for callers that hand it straight to
  -- ImGui_InputTextMultiline. lines_array is the same content split into
  -- per-line segments; measurement callers that used to run
  --   for line in (wrapped .. "\n"):gmatch("(.-)\n") do ... end
  -- now iterate lines_array instead, which skips the full-bubble-sized
  -- string concatenation + gmatch pattern per frame per visible bubble.
  local font_idx = prefs.chat_font_idx or 2
  local entry = S.wrap_cache[raw_text]
  if entry and entry.cpl == chars_per_line and entry.font_idx == font_idx then
    return entry.wrapped, entry.line_count, entry.lines
  end
  local wrapped = UI.wrap_text(raw_text, chars_per_line)
  local lines = {}
  local line_count = 0
  for line in (wrapped .. "\n"):gmatch("(.-)\n") do
    line_count = line_count + 1
    lines[line_count] = line
  end
  if line_count == 0 then line_count = 1 end  -- empty input -> one empty line
  S.wrap_cache[raw_text] = {
    wrapped    = wrapped,
    line_count = line_count,
    lines      = lines,
    cpl        = chars_per_line,
    font_idx   = font_idx,
  }
  return wrapped, line_count, lines
end

-- =============================================================================
-- Utility: UI.measure_stripped_height
-- =============================================================================
-- Returns the pixel height that UI.selectable_text() would use for an
-- already-stripped (no markdown) text and widget width. Splits the measure
-- step away from stripping so callers that also render the text can run
-- strip_markdown once per frame instead of twice (measure + render).
function UI.measure_stripped_height(stripped, avail_w, chars_per_line_override)
  local t = (stripped or ""):match("^(.-)%s*$") or ""
  if #t == 0 then t = " " end
  local line_h = ImGui.ImGui_GetTextLineHeight(RA.ctx) + 2
  -- Must match UI.selectable_text's wrap config exactly -- otherwise the
  -- pre-calculated bubble height won't line up with the actual wrapped
  -- output. Accept an override cpl so the user bubble can thread the same
  -- chars_per_line through measurement, height pre-calc, and render.
  local avg_char_w     = ImGui.ImGui_GetFontSize(RA.ctx) * 0.48
  local chars_per_line = chars_per_line_override
    or math_floor(math_max(avail_w / avg_char_w, 20))
  local _, line_count = UI.get_wrap_cached(t, chars_per_line)
  -- No hard cap: the bubble renderer draws every wrapped line unconditionally
  -- via Text(), so returning a clamped height here would shrink the bubble
  -- background/hit-test rect while the text still overflowed past it. If a
  -- user message is huge, the bubble grows to match; the chat pane is
  -- already scrollable.
  return line_count * line_h + 2
end

-- =============================================================================
-- Utility: UI.drop_target
-- =============================================================================
-- Checks if the last widget is a file drop target. Call after any major widget
-- to allow drag-and-drop file attachment across the entire window.
S.drop_active = false  -- true if any drop target is hovered this frame

function UI.drop_target()
  if ImGui.ImGui_BeginDragDropTarget(RA.ctx) then
    S.drop_active = true
    local rv, count = ImGui.ImGui_AcceptDragDropPayloadFiles(RA.ctx)
    if rv then
      for fi = 0, count - 1 do
        local ok, path = ImGui.ImGui_GetDragDropPayloadFile(RA.ctx, fi)
        if ok and path and #path > 0 then Attach.file(path) end
      end
    end
    ImGui.ImGui_EndDragDropTarget(RA.ctx)
  end
end

-- =============================================================================
-- UI.render_highlighted
-- =============================================================================
-- Paints a tokenized source string at the current ImGui cursor position
-- using TextColored + SameLine(0, 0) for inline tokens, slicing multi-
-- line tokens on "\n" so each widget call handles one visual line. The
-- tokenizers (Code.tokenize_lua / Code.tokenize_jsfx) live in the main
-- chunk and are reached here via the Code global.
--
-- Caller sets up the surrounding container (BeginChild, font, padding)
-- and handles scroll; this function only emits widgets.
-- Token-type -> palette color. Lazy-built singleton so the tiny map is
-- not reallocated per call. Invalidated on theme switch by
-- UI.invalidate_palette_caches() (called from apply_palette in main),
-- otherwise existing chat code blocks would keep painting in the old
-- theme's CODE_KW/STR/NUM/COM/API colors until the script reloads.
local _HL_COLOR_MAP
local function _hl_color_map()
  -- Build lazily: COL is populated by main-chunk code that runs before
  -- the first render call, but NOT before this file loads. The first
  -- render resolves it once and the table is reused thereafter.
  if _HL_COLOR_MAP then return _HL_COLOR_MAP end
  _HL_COLOR_MAP = {
    kw    = COL.CODE_KW,
    str   = COL.CODE_STR,
    num   = COL.CODE_NUM,
    com   = COL.CODE_COM,
    api   = COL.CODE_API,
    id    = COL.CODE_FG,
    ws    = COL.CODE_FG,
    other = COL.CODE_FG,
  }
  return _HL_COLOR_MAP
end

-- Drop any palette-derived caches. Called from apply_palette in the main
-- file whenever a theme switch updates COL.* slots so stale references to
-- the old palette do not leak into subsequent renders.
function UI.invalidate_palette_caches()
  _HL_COLOR_MAP = nil
  -- Per-message highlight caches bake u32 colours into msg._hl_lines on
  -- first render; without clearing them a theme switch leaves old code
  -- blocks painting in the previous palette's identifier/whitespace
  -- colour (e.g. dark-mode CODE_FG near-white on the light-mode bg).
  if S and S.display_messages then
    for _, m in ipairs(S.display_messages) do
      m._hl_src   = nil
      m._hl_lang  = nil
      m._hl_lines = nil
      -- Details-card field/color cache: color_map embeds u32 from
      -- TK.accent (Est. Cost line). Setting field_map to nil triggers
      -- the first arm of the cache-validity check next render, which
      -- rebuilds both maps in lockstep with the new palette.
      m._details_field_map = nil
      m._details_color_map = nil
    end
  end
end

-- Optional `cache` parameter carries the per-message tokenization cache.
-- When the caller (the chat bubble loop) passes the message table, the
-- per-line segment list (the output of tokenize + newline-split, which
-- produces many small tables) is computed once and reused on subsequent
-- frames; only the ImGui widget emission runs per frame. Not passing
-- cache falls back to the original stateless behavior so one-off callers
-- are unaffected.
function UI.render_highlighted(src, lang, cache)
  local lines
  if cache and cache._hl_src == src and cache._hl_lang == lang then
    lines = cache._hl_lines
  else
    local color_map = _hl_color_map()
    local tokens = (lang == "jsfx")
      and Code.tokenize_jsfx(src) or Code.tokenize_lua(src)
    -- Group tokens into lines so blank source lines render as blank rows
    -- and TextColored never has to deal with embedded newlines.
    lines = { {} }
    local last_line = lines[1]
    for _, tok in ipairs(tokens) do
      local color = color_map[tok.type] or COL.CODE_FG
      local txt   = tok.text
      local start = 1
      while true do
        local nl = txt:find("\n", start, true)
        if nl then
          if nl > start then
            last_line[#last_line + 1] = { color, txt:sub(start, nl - 1) }
          end
          last_line       = {}
          lines[#lines+1] = last_line
          start = nl + 1
          if start > #txt then break end
        else
          if start <= #txt then
            last_line[#last_line + 1] = { color, txt:sub(start) }
          end
          break
        end
      end
    end
    if cache then
      cache._hl_src   = src
      cache._hl_lang  = lang
      cache._hl_lines = lines
    end
  end

  -- Push a slightly taller ItemSpacing.y so inter-line gaps breathe a bit
  -- in generated code blocks. Default is typically SC(4); SC(6) adds ~2
  -- scaled pixels between rows, a roughly 10-12% line-height bump for the
  -- SC(12) mono font without feeling airy. The caller's content_h math is
  -- tuned to match (see the SC(6) term when sizing the BeginChild height).
  PushStyleVar(RA.ctx, ImGui.ImGui_StyleVar_ItemSpacing(), 0, RA.SC(6))
  for _, segs in ipairs(lines) do
    if #segs == 0 then
      -- Blank source line: emit an empty Text so cursor advances by one row.
      Text(RA.ctx, "")
    else
      for si, seg in ipairs(segs) do
        if si > 1 then SameLine(RA.ctx, 0, 0) end
        ImGui.ImGui_TextColored(RA.ctx, seg[1], seg[2])
      end
    end
  end
  ImGui.ImGui_PopStyleVar(RA.ctx)
end
