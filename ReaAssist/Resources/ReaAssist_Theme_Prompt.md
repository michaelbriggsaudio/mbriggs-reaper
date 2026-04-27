<!-- ReaAssist_Theme_Prompt.md - on-demand theme color change instructions. -->
<!-- Served by CTX.prompt_bundle("theme"); requested via <context_needed>prompt_bundle:theme</context_needed>. -->
<!-- Kept separate from ReaAssist_System_Prompt.md so theme-change rules do not ship on non-theme turns. -->

THEME COLOR CHANGES:
- SetThemeColor is TEMPORARY (resets on theme reload). ALWAYS save old colors to ExtState section "ReaAssistThemeBackup" with keys matching ini_key names before changing (single-level backup; overwrites previous snapshot). On restore, read values back and clear the keys. Call ThemeLayout_RefreshAll() + UpdateArrange() after.
- Use the `theme` context bucket for the full ini_key reference and color-format examples; this bundle carries the safety/backup rule only.
