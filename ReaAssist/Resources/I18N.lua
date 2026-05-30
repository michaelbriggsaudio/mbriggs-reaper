local I18N = rawget(_G, "I18N") or {}

I18N.fallback_code = "en"
I18N.active_code = I18N.active_code or I18N.fallback_code

I18N.catalogs = {
  en = {
    _meta = {
      code = "en",
      source_version = 1,
      status = "complete",
      reviewed_by = "",
    },
    strings = {
      ["common.cancel"] = "Cancel",
      ["common.save"] = "Save",
      ["common.discard"] = "Discard",
      ["common.back"] = "Back",
      ["common.help"] = "Help",
      ["common.retry"] = "Retry",
      ["common.proceed"] = "Proceed",
      ["common.ok"] = "OK",
      ["common.close"] = "Close",
      ["common.clear"] = "Clear",
      ["common.confirm"] = "Confirm",
      ["common.copy"] = "Copy",
      ["common.paste"] = "Paste",
      ["common.cut"] = "Cut",
      ["common.continue"] = "Continue",
      ["common.add"] = "Add",
      ["common.skip"] = "Skip",
      ["common.undo"] = "Undo",
      ["common.edit"] = "Edit",
      ["common.run"] = "Run",
      ["common.backup"] = "Backup",
      ["common.save_as"] = "Save As",
      ["common.copied"] = "Copied!",
      ["common.saved"] = "Saved!",
      ["common.later"] = "Later",
      ["common.dismiss"] = "Dismiss",
      ["common.try_again"] = "Try Again",
      ["common.send"] = "Send",
      ["common.open"] = "Open",
      ["common.name"] = "Name",
      ["common.email"] = "Email",
      ["file_error.title"] = "ReaAssist - File Error",
      ["file_error.write"] =
        "Could not write file:\n{path}\n\n{error}",
      ["file_error.write_temp_failed"] =
        "Failed writing temp file:\n{path}\n\n{error}",
      ["file_error.finalize"] =
        "Could not finalize file:\n{path}\n\n{error}",
      ["common.section.collapse_tooltip"] = "Click to collapse this section",
      ["common.section.expand_tooltip"] = "Click to expand this section",
      ["footer.by"] = "by",
      ["footer.author_tooltip"] = "Request a free sample master",
      ["footer.version.busy"] = "Update check in progress...",
      ["footer.version.unavailable"] =
        "Update checks not available in this build",
      ["footer.version.just_now"] = "just now",
      ["footer.version.seconds_ago"] = "{count}s ago",
      ["footer.version.minutes_ago"] = "{count}m ago",
      ["footer.version.hours_ago"] = "{count}h ago",
      ["footer.version.days_ago"] = "{count}d ago",
      ["footer.version.checked_tooltip"] =
        "Up to date (checked {ago})\nClick to check again",
      ["footer.version.check_tooltip"] = "Click to check for updates",
      ["footer.settings_tooltip"] =
        "Settings: API keys, preferences, and display options.",
      ["footer.theme.light_tooltip"] = "Switch to light mode",
      ["footer.theme.dark_tooltip"] = "Switch to dark mode",
      ["footer.help.label"] = "Help",
      ["footer.help.tooltip"] = "View help and usage guide.",
      ["footer.copy.label"] = "Copy",
      ["footer.copy.tooltip"] = "Copy full chat history to clipboard.",
      ["footer.copy.toast"] = "Chat copied to clipboard",
      ["footer.credits.label"] = "Credits",
      ["footer.credits.tooltip"] = "View credits.",
      ["footer.donate.label"] = "Donate",
      ["footer.donate.tooltip"] = "Support ReaAssist development.",
      ["credits.subtitle"] =
        "Brought to you by Michael Briggs Mastering.",
      ["credits.breadcrumb"] = "CREDITS · v{version}",
      ["credits.section.about"] = "ABOUT",
      ["credits.about.bio"] =
        "Michael Briggs is an award-winning audio engineer and producer based in Denton, Texas, available for production, mixing, recording, and mastering. He has worked with over 400 artists on more than 3,000 songs across just about every genre. Voted Best Producer and Best Audio Engineer in North Texas.",
      ["credits.about.reaassist"] =
        "ReaAssist was designed to give you modern tools that aid the technical side of your productions and improve your workflow. This is purely a workflow assistant and is not designed or intended to be used for any type of generative creative content.",
      ["credits.section.links"] = "LINKS",
      ["credits.link.production"] = "Production / mixing / recording site",
      ["credits.link.mastering"] = "Mastering site",
      ["credits.link.reaassist"] = "Project site for ReaAssist",
      ["credits.link.sample_label"] = "Request a Free Mastering Sample",
      ["credits.link.sample"] = "Submit a free mastering sample request",
      ["credits.section.contact"] = "CONTACT",
      ["credits.contact.direct"] = "Email Michael directly",
      ["credits.contact.support"] = "Email the ReaAssist support address",
      ["credits.section.support"] = "SUPPORT REAASSIST",
      ["credits.donate.caption"] =
        "Donations help keep this project moving forward.",
      ["context.copy_selection"] = "Copy Selection",
      ["context.copy_all"] = "Copy All",
      ["context.copy_table"] = "Copy Table",
      ["help.error.title"] = "Error",
      ["help.error.file_not_found"] = "Help file not found.",
      ["help.error.expected"] = "Expected: {path}",
      ["help.subtitle"] = "Guide, shortcuts, and usage tips.",
      ["help.breadcrumb"] = "HELP · v{version}",
      ["help.nav.manual"] = "Read Online Manual",
      ["help.nav.manual.tooltip"] =
        "Open the online manual at reaassist.app/manual",
      ["help.nav.feedback"] = "Feedback & Report a Bug",
      ["help.nav.feedback.tooltip"] =
        "Open the feedback / bug report form",
      ["help.search.placeholder"] = "Search Help...",
      ["help.text_size.decrease"] = "Decrease text size  ({percent}%)",
      ["help.text_size.increase"] = "Increase text size  ({percent}%)",
      ["help.contents"] = "CONTENTS",
      ["help.matches.none"] = "No matches",
      ["help.matches.one"] = "{count} match",
      ["help.matches.many"] = "{count} matches",
      ["help.no_sections_match"] =
        "No sections match \"{query}\"",
      ["attach.menu.attach_file"] = "Attach File",
      ["attach.menu.screenshot"] = "Screenshot",
      ["attach.menu.paste_image"] = "Paste Image",
      ["attach.dialog.title"] = "Attach files",
      ["attach.error.file_picker"] =
        "File picker requires js_ReaScriptAPI.\nInstall via ReaPack (Extensions > ReaPack > Browse Packages).",
      ["attach.error.screenshot_failed_popup"] =
        "Screenshot capture failed (see popup for details).",
      ["attach.error.screenshot_linux_unsupported"] =
        "Screenshot capture is not supported on Linux.",
      ["attach.screenshot.macos_permission_popup"] =
        "Screenshot capture failed (exit {code}).\n\n" ..
        "On macOS this usually means REAPER does not have Screen Recording " ..
        "permission. To grant it:\n\n" ..
        "1. Open System Settings > Privacy & Security > Screen Recording.\n" ..
        "2. Enable REAPER in the list.\n" ..
        "3. Quit and reopen REAPER (macOS requires this before the new " ..
        "permission takes effect).\n" ..
        "4. Try the screenshot attachment again.\n\n" ..
        "On macOS Sequoia / Tahoe you may also see a one-time \"bypass " ..
        "the system private window picker\" prompt the first time the " ..
        "capture runs -- click Allow.",
      ["attach.summary.one"] =
        "{count} file (Est. {tokens} tokens, {cost}, provider may bill differently)",
      ["attach.summary.many"] =
        "{count} files (Est. {tokens} tokens, {cost}, provider may bill differently)",
      ["attach.kind.image"] = "image",
      ["attach.kind.pdf"] = "PDF",
      ["attach.kind.text"] = "text",
      ["attach.tooltip"] = "{name}\n{kind}, Est. {tokens} tokens ({cost})",
      ["chat.hero.status.set_api_key"] = "SET API KEY",
      ["chat.hero.status.set_api_key.tooltip"] =
        "No API key configured. Click to open Settings.",
      ["chat.hero.status.thinking"] = "THINKING",
      ["chat.hero.status.thinking.tooltip"] =
        "Waiting on a response from the model. This can take a few seconds.",
      ["chat.hero.status.running"] = "RUNNING",
      ["chat.hero.status.running.tooltip"] =
        "Executing the returned code in REAPER.",
      ["chat.hero.status.error"] = "ERROR",
      ["chat.hero.status.error.tooltip"] =
        "The last request failed. Try again or check your connection.",
      ["chat.hero.status.ready"] = "READY",
      ["chat.hero.status.ready.tooltip"] =
        "Connected and ready. Type a prompt or pick a card to begin.",
      ["chat.hero.new_chat"] = "new chat",
      ["chat.hero.new_chat.tooltip"] =
        "Clear the current conversation and start fresh.",
      ["chat.hero.tagline.ask"] = "Ask anything.",
      ["chat.hero.tagline.automate"] = "Automate everything.",
      ["home.section.session"] = "SESSION & AUTOMATION",
      ["home.section.code"] = "CUSTOM CODE",
      ["home.section.boundaries"] = "ANSWERS & BOUNDARIES",
      ["home.card.session_awareness.title"] = "Session Awareness",
      ["home.card.session_awareness.body"] =
        "Read your session state to give advice or write custom scripts.",
      ["home.card.session_awareness.prompt"] =
        "What information do you have about my current REAPER session right now? Give me a brief summary of what you can see (tracks, items, markers, FX, etc.) and explain how you can use this information to help me. Keep your response concise with a few bullet points.",
      ["home.card.editing.title"] = "Editing",
      ["home.card.editing.body"] =
        "Item edits, splits, crossfades, time selections, markers, regions, and more.",
      ["home.card.editing.prompt"] =
        "What kinds of editing tasks can you help me with in REAPER? Give me a concise overview with specific examples of item editing, splitting, crossfades, time selections, markers, regions, and other editing operations you can perform. Use brief bullet points.",
      ["home.card.track_project.title"] = "Track & Project Mgmt",
      ["home.card.track_project.body"] =
        "Create tracks, manage folders, configure I/O, and organize your session.",
      ["home.card.track_project.prompt"] =
        "What can you help me with for track and project management in REAPER? Give me a concise overview of the types of tasks you can perform - creating tracks, setting colors, managing folders, routing, I/O configuration, project settings, and session organization. Use brief bullet points.",
      ["home.card.mixing_effects.title"] = "Mixing & Effects",
      ["home.card.mixing_effects.body"] =
        "Add and configure plugins, adjust levels, set up sends, and build FX chains.",
      ["home.card.mixing_effects.prompt"] =
        "What can you help me with for mixing and effects in REAPER? Give me a concise overview of how you can add and configure plugins, adjust levels, set up sends and routing, and build FX chains. Include a few specific examples of what I could ask you to do. Keep it brief.",
      ["home.card.lua_scripting.title"] = "Lua Scripting",
      ["home.card.lua_scripting.body"] =
        "Write custom scripts to automate tasks, batch-process tracks, and more.",
      ["home.card.lua_scripting.prompt"] =
        "What kinds of Lua scripts can you write for REAPER? Give me a concise list of practical examples organized by category (batch processing, track management, item manipulation, workflow automation, etc.). Keep it brief with short bullet points.",
      ["home.card.jsfx.title"] = "JSFX Effect Scripting",
      ["home.card.jsfx.body"] =
        "Build custom effect plugins on the fly and add them to your tracks.",
      ["home.card.jsfx.prompt"] =
        "What kinds of JSFX effects can you create for me? Give me a concise overview of the types of custom audio plugins you can build (EQ, dynamics, delay, utilities, etc.) and explain briefly how the process works - from generating the code to adding it to my tracks. Keep it short.",
      ["home.card.qa.title"] = "General REAPER Q&A",
      ["home.card.qa.body"] =
        "Ask about shortcuts, features, best practices, and workflow tips.",
      ["home.card.qa.prompt"] =
        "What kinds of REAPER questions can you help me with? Give me a brief overview of the topics you can assist with - shortcuts, features, best practices, workflow tips, recording advice, and production techniques. Include a few example questions I could ask. Keep it concise.",
      ["home.card.no_audio.title"] = "No Generative Audio",
      ["home.card.no_audio.body"] =
        "Cannot generate or process audio, music, or other creative content.",
      ["home.card.no_audio.prompt"] =
        "Explain briefly what you cannot do: you cannot generate, produce, or process audio, music, or any creative content. Then explain what you can still help with in this area - for example, setting up virtual instruments and samplers, configuring MIDI routing, advising on microphone selection and recording techniques, recommending signal chains, and other production guidance. Keep it concise with bullet points.",
      ["session.unsaved"] = "unsaved",
      ["session.tracks"] = "{count} tracks",
      ["session.items"] = "{count} items",
      ["session.fx"] = "{count} fx",
      ["session.transport.rec"] = "REC",
      ["session.transport.pause"] = "PAUSE",
      ["session.transport.play"] = "PLAY",
      ["session.transport.stop"] = "STOP",
      ["bootstrap.status.installing"] = "Installing...",
      ["bootstrap.status.checking_updates"] = "Checking for updates...",
      ["bootstrap.status.verifying_files"] = "Verifying files...",
      ["bootstrap.status.downloading"] = "Downloading...",
      ["bootstrap.status.almost_done"] = "Almost done...",
      ["bootstrap.status.restarting"] = "Restarting ReaAssist...",
      ["bootstrap.window.installer"] = "ReaAssist Installer",
      ["bootstrap.window.recovery"] = "ReaAssist Recovery",
      ["bootstrap.prompt.title"] = "Some Files Need Repair",
      ["bootstrap.prompt.files.one"] =
        "ReaAssist found 1 critical file missing, modified, or unreadable.",
      ["bootstrap.prompt.files.many"] =
        "ReaAssist found {count} critical files missing, modified, or unreadable.",
      ["bootstrap.more"] = "+ {count} more",
      ["bootstrap.recovery_unavailable"] =
        "Automatic recovery is not available (update URL not configured).",
      ["bootstrap.reinstall_manually"] = "Please reinstall ReaAssist manually.",
      ["bootstrap.previous_failed"] = "Previous attempt failed ({step}):",
      ["bootstrap.repair_prompt"] =
        "Repair these and any other modified files from the current release?",
      ["bootstrap.repair"] = "Repair",
      ["bootstrap.quit"] = "Quit",
      ["bootstrap.title.setup"] = "Setting up ReaAssist",
      ["bootstrap.title.repairing"] = "Repairing Files",
      ["bootstrap.title.setup_complete"] = "Setup Complete",
      ["bootstrap.title.repair_complete"] = "Repair Complete",
      ["bootstrap.title.setup_failed"] = "Setup Failed",
      ["bootstrap.title.repair_failed"] = "Repair Failed",
      ["bootstrap.done.installed.one"] = "Installed 1 file successfully.",
      ["bootstrap.done.installed.many"] =
        "Installed {count} files successfully.",
      ["bootstrap.done.restored.one"] = "Restored 1 file successfully.",
      ["bootstrap.done.restored.many"] =
        "Restored {count} files successfully.",
      ["bootstrap.done.reopen_setup"] =
        "Close and reopen ReaAssist to finish setup.",
      ["bootstrap.done.reopen_repair"] =
        "Close and reopen ReaAssist to finish the repair.",
      ["bootstrap.step"] = "Step: {step}",
      ["bootstrap.problem_persists"] =
        "If the problem persists, reinstall ReaAssist manually.",
      ["mode.provider.header"] = "Provider:",
      ["mode.provider.tooltip"] =
        "Provider - {label}. Choose which service ReaAssist talks to.",
      ["mode.model.header"] = "Model:",
      ["mode.model.tooltip"] =
        "Model - {label}. Pick which model handles this provider's requests.",
      ["mode.model.tooltip.generic"] =
        "Model - pick which model handles this provider's requests.",
      ["mode.model.descriptor.fast"] = "fast",
      ["mode.model.descriptor.balanced"] = "balanced",
      ["mode.model.descriptor.smart"] = "smart",
      ["mode.model.paid_only"] = "paid only",
      ["mode.model.paid_only.tooltip"] =
        "Requires Google's paid API tier. Upgrade at aistudio.google.com/apikey.",
      ["mode.model_tip.claude-haiku-4-5"] =
        "Cheapest Claude. Use High thinking. Sonnet None is faster for complex work.",
      ["mode.model_tip.claude-sonnet-4-6"] =
        "Recommended Claude default. Use None thinking. Higher levels add latency without quality gain.",
      ["mode.model_tip.claude-opus-4-8"] =
        "Premium Claude. Use None thinking. Higher levels add cost without quality gain.",
      ["mode.model_tip.gpt-5.4-nano"] =
        "Cheapest GPT. Use None thinking. Simple tasks only -- pick full GPT-5.4 for complex.",
      ["mode.model_tip.gpt-5.4-mini"] =
        "Cheap GPT. Use Low thinking. Simple tasks only -- pick full GPT-5.4 for complex.",
      ["mode.model_tip.gpt-5.4"] =
        "Recommended OpenAI default. Use None thinking. Reliable on simple and complex tasks.",
      ["mode.model_tip.gemini-3.1-flash-lite"] =
        "Cheapest Gemini. Use Low thinking. Budget pick; Flash 3.5 Minimal is stronger for scripts and edits.",
      ["mode.model_tip.gemini-3.5-flash"] =
        "Recommended Gemini default. Use Minimal thinking. Fast, strong, and bench-backed; try Low only if Minimal struggles.",
      ["mode.model_tip.gemini-3.1-pro-preview"] =
        "Premium Gemini preview. Use Medium thinking. Capacity has been unreliable; Flash 3.5 Minimal is safer for coding.",
      ["mode.model_tip.deepseek-v4-flash"] =
        "Cheapest combo in the lineup. Use Non-Thinking. Strong cheap pick.",
      ["mode.combo_hint.anthropic.claude-haiku-4-5.none"] =
        "Simple tasks | Mid-cost | Very fast | Use Sonnet for complex",
      ["mode.combo_hint.anthropic.claude-haiku-4-5.low"] =
        "Simple tasks only | Mid-cost | Very fast | Use Sonnet for complex",
      ["mode.combo_hint.anthropic.claude-haiku-4-5.medium"] =
        "Simple and complex | Mid-cost | Slow with retries | Use Sonnet for complex",
      ["mode.combo_hint.anthropic.claude-haiku-4-5.high"] =
        "Recommended Level | Simple tasks; complex with caveats | Mid-cost | Moderate speed | Use Sonnet for complex",
      ["mode.combo_hint.anthropic.claude-sonnet-4-6.none"] =
        "Recommended Level | Simple and complex | Higher cost | Fast",
      ["mode.combo_hint.anthropic.claude-sonnet-4-6.low"] =
        "Simple and complex | Higher cost | Slow | Marginal lift over None -- use None",
      ["mode.combo_hint.anthropic.claude-sonnet-4-6.medium"] =
        "Simple and complex | Higher cost | Very slow | Use only if None struggles",
      ["mode.combo_hint.anthropic.claude-sonnet-4-6.high"] =
        "Avoid long prompts | Higher cost | Very slow (hits timeouts) | Use None or Opus None",
      ["mode.combo_hint.anthropic.claude-opus-4-8.none"] =
        "Recommended Level | Simple and complex (top quality) | Most expensive | Very fast",
      ["mode.combo_hint.anthropic.claude-opus-4-8.low"] =
        "Simple and complex | Most expensive | Very fast | No gain over None -- use None",
      ["mode.combo_hint.anthropic.claude-opus-4-8.medium"] =
        "Simple and complex | Most expensive | Very fast | No gain over None -- use None",
      ["mode.combo_hint.anthropic.claude-opus-4-8.high"] =
        "Simple and complex | Most expensive | Very fast | Deepest reasoning but no gain -- use None",
      ["mode.combo_hint.openai.gpt-5.4-nano.none"] =
        "Recommended Level | Simple tasks only | Cheap | Very fast | Use full GPT-5.4 None for complex edits",
      ["mode.combo_hint.openai.gpt-5.4-nano.low"] =
        "Simple tasks only | Cheap | Very fast | None is faster -- pick None (default)",
      ["mode.combo_hint.openai.gpt-5.4-nano.medium"] =
        "Simple and some complex | Cheap | Moderate speed | Use full GPT-5.4 None for complex edits",
      ["mode.combo_hint.openai.gpt-5.4-nano.high"] =
        "Simple and some complex | Cheap | Slow | Use full GPT-5.4 None for complex edits",
      ["mode.combo_hint.openai.gpt-5.4-mini.none"] =
        "Simple tasks only | Cheap | Very fast | Use full GPT-5.4 None for complex edits",
      ["mode.combo_hint.openai.gpt-5.4-mini.low"] =
        "Recommended Level | Simple tasks only | Cheap | Very fast | Use full GPT-5.4 None for complex edits",
      ["mode.combo_hint.openai.gpt-5.4-mini.medium"] =
        "Simple and complex | Mid-cost | Moderate speed | Limited evidence; full GPT-5.4 None is faster",
      ["mode.combo_hint.openai.gpt-5.4-mini.high"] =
        "Simple and complex | Mid-cost | Moderate speed | Mini's strongest combo, but full GPT-5.4 None is faster and cleaner",
      ["mode.combo_hint.openai.gpt-5.4.none"] =
        "Recommended Level | Simple and complex | Mid-cost | Very fast",
      ["mode.combo_hint.openai.gpt-5.4.low"] =
        "Simple and complex | Mid-cost | Moderate speed | Marginal lift over None -- use None",
      ["mode.combo_hint.openai.gpt-5.4.medium"] =
        "Simple and complex | Higher cost | Very slow | Use only if None struggles",
      ["mode.combo_hint.openai.gpt-5.4.high"] =
        "Simple and complex | Higher cost | Very slow | No quality gain over None -- use None",
      ["mode.combo_hint.google.gemini-3.1-flash-lite.MINIMAL"] =
        "Simple tasks only | Cheap | Fast | Low is more reliable on complex routing",
      ["mode.combo_hint.google.gemini-3.1-flash-lite.LOW"] =
        "Recommended Level | Simple and complex | Cheap | Fast",
      ["mode.combo_hint.google.gemini-3.1-flash-lite.MEDIUM"] =
        "Simple and complex | Cheap | Slow | Flash 3.5 Minimal is usually better value",
      ["mode.combo_hint.google.gemini-3.1-flash-lite.HIGH"] =
        "Avoid complex prompts | Cheap | Very slow | Runtime-error risk; pick Flash Lite Low or Flash 3.5 Minimal",
      ["mode.combo_hint.google.gemini-3.5-flash.MINIMAL"] =
        "Recommended Level | Simple and common scripts | Fastest Flash 3.5 | Lowest cost",
      ["mode.combo_hint.google.gemini-3.5-flash.LOW"] =
        "Use if Minimal struggles | More thinking tokens | Slower | No bench win over Minimal",
      ["mode.combo_hint.google.gemini-3.5-flash.MEDIUM"] =
        "Complex code/debugging only | Higher cost | Much slower | Try Minimal first, then Low",
      ["mode.combo_hint.google.gemini-3.5-flash.HIGH"] =
        "Hard reasoning only | Highest Flash cost | Slowest | Avoid for routine ReaAssist work",
      ["mode.combo_hint.google.gemini-3.1-pro-preview.LOW"] =
        "Not recommended | Capacity-prone preview | Mid-cost | Underuses Pro -- use Flash 3.5 if 503s appear",
      ["mode.combo_hint.google.gemini-3.1-pro-preview.MEDIUM"] =
        "Model default | Premium reasoning when available | Capacity-prone preview | Use Flash 3.5 for coding",
      ["mode.combo_hint.google.gemini-3.1-pro-preview.HIGH"] =
        "Not recommended | Capacity-prone preview | Mid-cost | Marginal lift over Medium",
      ["mode.combo_hint.deepseek.deepseek-v4-flash.disabled"] =
        "Recommended Level | Simple and complex | Cheapest in lineup | Very fast | Strong cheap pick",
      ["mode.thinking.header"] = "Thinking:",
      ["mode.thinking.tooltip"] =
        "Thinking depth: higher tiers think longer (smarter, slower, more expensive).",
      ["mode.thinking.warning"] = "Warning: {hint}",
      ["mode.thinking.level.think"] = "THINK",
      ["mode.thinking.level.none"] = "None",
      ["mode.thinking.level.low"] = "Low",
      ["mode.thinking.level.medium"] = "Medium",
      ["mode.thinking.level.high"] = "High",
      ["mode.thinking.level.minimal"] = "Minimal",
      ["mode.thinking.level.disabled"] = "Non-Thinking",
      ["mode.ask"] = "ASK",
      ["mode.auto_run"] = "AUTO-RUN",
      ["mode.ask.tooltip"] =
        "Ask mode: replies only; returned code waits for you to click Run.",
      ["mode.auto_run.tooltip"] =
        "Auto-Run: returned code runs automatically after the reply arrives.",
      ["mode.backup"] = "backup",
      ["mode.details"] = "details",
      ["mode.options"] = "Options",
      ["mode.on"] = "on",
      ["mode.off"] = "off",
      ["mode.backup.tooltip"] =
        "Backup: save a timestamped .rpp-bak before Auto-Run executes returned code.",
      ["mode.details.tooltip"] =
        "Details: show model, token count, and cost under each message.",
      ["prompt.placeholder"] = "Ask anything about your session...",
      ["prompt.default_attachment"] = "Please analyze the attached file(s).",
      ["prompt.no_api_key.tooltip"] =
        "No API key set for {provider}. Click API Keys to add one.",
      ["prompt.encoding_attachments.tooltip"] = "Encoding attachment(s)...",
      ["feedback.was_helpful"] = "Was this helpful?",
      ["feedback.helpful"] = "Helpful",
      ["feedback.not_helpful"] = "Not helpful",
      ["feedback.modal.title"] = "Send Feedback",
      ["feedback.modal.subtitle"] = "Help improve ReaAssist",
      ["feedback.modal.intro"] =
        "Sends the current chat session plus your tags and comment below to help improve ReaAssist. API keys, bearer tokens, and home paths are automatically redacted before sending. Project, track, or plugin names you typed may still appear in the chat content; review the preview to verify. Audio is never sent.",
      ["feedback.modal.bug_link.before"] = "See the ",
      ["feedback.modal.bug_link.label"] = "Bug Reports",
      ["feedback.modal.bug_link.after"] =
        " screen to send an advanced report with the full log.",
      ["feedback.modal.how"] = "HOW DID IT GO?",
      ["feedback.modal.what_wrong"] = "What went wrong?",
      ["feedback.modal.tag.wrong_result"] = "Wrong result",
      ["feedback.modal.tag.wrong_plugin"] = "Wrong plugin",
      ["feedback.modal.tag.didnt_follow"] = "Didn't follow request",
      ["feedback.modal.tag.too_slow"] = "Too slow",
      ["feedback.modal.comments"] = "COMMENTS",
      ["feedback.modal.placeholder.up"] =
        "What went right? How did this help you?",
      ["feedback.modal.placeholder.down"] =
        "What went wrong? How could this chat have gone better?",
      ["feedback.modal.placeholder.neutral"] =
        "What went right, what went wrong?",
      ["feedback.modal.preview"] = "Preview feedback",
      ["feedback.modal.privacy"] = "Details & privacy",
      ["feedback.panel.included"] = "What's included",
      ["feedback.panel.included.chat"] = "Chat shown above",
      ["feedback.panel.included.comment"] = "Your comment and tags",
      ["feedback.panel.included.system"] = "App, REAPER, OS, provider/model",
      ["feedback.panel.included.diagnostic"] = "Diagnostic summary",
      ["feedback.panel.privacy"] = "Privacy",
      ["feedback.panel.privacy.keys"] =
        "API keys and bearer tokens redacted",
      ["feedback.panel.privacy.paths"] = "Home/install paths redacted",
      ["feedback.panel.privacy.audio"] =
        "Audio files and .RPP projects not sent",
      ["feedback.panel.privacy.contact"] = "No account/contact info",
      ["feedback.panel.where"] = "Where it goes",
      ["feedback.panel.where.maintainer"] =
        "Sent to ReaAssist maintainer",
      ["feedback.panel.where.use"] = "Used only to improve ReaAssist",
      ["feedback.panel.where.no_third"] = "No third parties",
      ["feedback.panel.note"] = "Note",
      ["feedback.panel.note.body"] =
        "Chat may include project, track, plugin, or names you typed.",
      ["feedback.status.sending"] = "Sending...",
      ["feedback.status.send_failed"] = "Send failed: {error}",
      ["feedback.toast.sent"] = "Feedback sent. Thanks!",
      ["bug_report.subtitle"] = "Send feedback or report an issue.",
      ["bug_report.breadcrumb"] = "FEEDBACK · v{version}",
      ["bug_report.intro"] =
        "Sends your description plus the diagnostic report and either the Advanced Log or the current chat session to the ReaAssist maintainer. API keys, bearer tokens, and home paths are automatically redacted before sending.",
      ["bug_report.describe"] = "DESCRIBE THE ISSUE",
      ["bug_report.placeholder"] =
        "What happened? What did you expect? What actually happened?",
      ["bug_report.contact"] = "OPTIONAL CONTACT",
      ["bug_report.contact_intro"] =
        "Only if you'd like a reply. These fields are sent as-is and are not redacted.",
      ["bug_report.email_invalid"] =
        "Doesn't look like an email address.",
      ["bug_report.sent_section"] = "WHAT WILL BE SENT",
      ["bug_report.item.diagnostic"] =
        "Diagnostic report (app/REAPER/OS, recent errors, metrics)",
      ["bug_report.item.log"] =
        "Advanced Log enabled - your complete log ({size}) will be attached",
      ["bug_report.item.chat.one"] =
        "Advanced Log not enabled - the current chat ({count} message) will be attached instead",
      ["bug_report.item.chat.many"] =
        "Advanced Log not enabled - the current chat ({count} messages) will be attached instead",
      ["bug_report.item.enable_log"] =
        "For richer reports, enable the Advanced Log below, reproduce the issue, and try again.",
      ["bug_report.item.none"] =
        "No log or chat available - only the diagnostic report will be sent. Enable the Advanced Log below or start a chat to reproduce the issue first.",
      ["bug_report.item.contact"] =
        "Your name / email (sent as-is, not redacted)",
      ["bug_report.status.sending"] = "Sending...",
      ["bug_report.status.note"] = "Note: {note}",
      ["bug_report.status.send_failed"] = "Send failed: {error}",
      ["bug_report.toast.sent"] = "Bug report sent. Thanks!",
      ["bug_report.preview"] = "Preview report",
      ["bug_report.privacy"] = "Details & privacy",
      ["bug_report.panel.included"] = "What's included",
      ["bug_report.panel.included.diagnostic"] =
        "Diagnostic report (app/REAPER/OS, errors, metrics)",
      ["bug_report.panel.included.attachment"] =
        "Advanced Log or current chat (whichever is available)",
      ["bug_report.panel.included.contact"] =
        "Comment, name, and email you typed (if provided)",
      ["bug_report.panel.included.model"] = "Active provider and model id",
      ["bug_report.panel.redacted"] = "Auto-redacted",
      ["bug_report.panel.redacted.keys"] =
        "API keys (yours, and any pasted into chat)",
      ["bug_report.panel.redacted.auth"] =
        "Authorization headers and Bearer tokens",
      ["bug_report.panel.redacted.paths"] = "Home-directory paths",
      ["bug_report.panel.redacted.params"] = "?key= / ?token= URL params",
      ["bug_report.panel.redacted.endpoints"] =
        "Custom-provider endpoint URLs",
      ["bug_report.panel.where"] = "Where it goes",
      ["bug_report.panel.where.maintainer"] =
        "Sent to the ReaAssist maintainer",
      ["bug_report.panel.where.use"] =
        "Used only to debug ReaAssist issues",
      ["bug_report.panel.where.no_third"] = "No third parties",
      ["bug_report.panel.not_redacted"] = "Not redacted",
      ["bug_report.panel.not_redacted.names"] =
        "Project, track, plugin, or file names you typed",
      ["bug_report.panel.not_redacted.chat"] =
        "Anything else you pasted into the chat",
      ["bug_report.panel.not_redacted.contact"] =
        "Your contact name and email (so a reply works)",
      ["bug_report.debug.section"] = "DEBUG LOG",
      ["bug_report.debug.body"] =
        "Captures full API traffic and FX scan events. When enabled, the complete log is attached to your bug report automatically. Reproduce the issue first, then send the form above.",
      ["bug_report.debug.enable"] = "Enable Advanced Log",
      ["bug_report.debug.enable_tooltip"] =
        "Log all API requests/responses (including hidden auto-follow-ups) and FX scan events to a file you can attach to a bug report.\nFile: {path}",
      ["bug_report.debug.open_tooltip"] =
        "Reveal the debug log file in your file browser",
      ["bug_report.debug.save_tooltip"] =
        "Save a copy of the log to a location of your choice",
      ["bug_report.debug.clear_tooltip"] =
        "Wipe the debug log file (useful before reproducing an issue cleanly)",
      ["bug_report.debug.log_not_found"] =
        "Log file not found at: {path}",
      ["bug_report.debug.save_dialog_title"] =
        "Save ReaAssist Debug Log",
      ["bug_report.debug.saved"] = "Saved: {path}",
      ["bug_report.debug.save_failed"] = "Save failed: {error}",
      ["bug_report.debug.cleared"] = "Log cleared.",
      ["tos.title"] = "Terms of Use",
      ["tos.body"] = [=[YOUR PRIVACY
API keys are encoded and stored locally on your machine. They are never sent to the author. Chat data is sent only to your chosen provider to fulfill your request. To provide relevant help, ReaAssist may send session data included in your prompt, such as track names, routing, and project settings. ReaAssist does not access, transmit, or create audio files. You may use a local LLM to keep all data offline and on your machine. Basic anonymous diagnostics are enabled by default and used to help improve the service. They can be turned off in Settings. The previewable manual feedback/report flows still show the exact bytes before sending.

SECURITY & SAFEGUARDS
ReaAssist scans generated code for potentially high-risk operations, such as file system changes or shell commands, and requires your confirmation before flagged code can run. Project backups can be created before execution, and REAPER Undo history is preserved. No project changes are made without your approval.

TERMS & LIABILITY
ReaAssist is provided "as is," without warranties of any kind, express or implied, including merchantability or fitness for a particular purpose. Generated code may contain errors or unintended results. You are responsible for reviewing code before execution. You are also responsible for your provider's terms, privacy practices, availability, and API charges. Some requests may be retried or escalated to a stronger model from the same provider when needed, which can increase API charges. Displayed cost estimates are approximate only.

Copyright {year} Michael Briggs. All rights reserved. ReaAssist is proprietary software; redistribution, resale, repackaging, and presenting this software as your own (modified or unmodified) are prohibited without prior written permission.

By clicking "I Agree," you confirm that you have read and agree to these Terms of Use.]=],
      ["tos.agree"] = "I Agree",
      ["tos.language.label"] = "Language",
      ["tos.language.tooltip"] =
        "Choose the language for setup and the ReaAssist interface.",
      ["chat.status.cancel"] = "Cancel",
      ["chat.status.waiting_selection"] =
        "Waiting for your {type} selection...",
      ["chat.status.server_busy"] =
        "Server busy; retrying in {seconds}s ({count}/{max})",
      ["chat.status.elapsed"] = "Elapsed",
      ["chat.status.timeout"] = "Timeout",
      ["chat.status.thinking"] = "Thinking...",
      ["chat.status.deep_scanning"] = "Deep-scanning {label}...",
      ["chat.status.deep_scan.detail"] =
        "This plugin reports parameter values with a one-frame delay (common on some VST3 plugins), so a slower defer-paced scan is needed to read accurate data. This only runs once per plugin. Future requests for this plugin will use the cached data and respond instantly.\n\nIf the plugin has heavy selector params (Style, Preset, Algorithm, Engine), the scan waits for each value to fully load before moving on, so it can take noticeably longer than a typical scan.",
      ["chat.status.probing"] = "Probing",
      ["chat.status.running_code"] = "Running code...",
      ["chat.status.extend_by"] = "Extend by {seconds}s",
      ["chat.status.extend_tooltip"] =
        "Give the model another {seconds}s before the request times out. Click again for more time.",
      ["details.field.model"] = "Model",
      ["details.field.complexity"] = "Complexity",
      ["details.field.context"] = "Context",
      ["details.field.fx_cache"] = "FX Cache",
      ["details.field.tokens"] = "Tokens",
      ["details.field.cache"] = "Cache",
      ["details.field.api_calls"] = "API Calls",
      ["details.field.time"] = "Time",
      ["details.field.thinking"] = "Thinking",
      ["details.field.est_cost"] = "Est. Cost",
      ["details.field.est_total"] = "Est. Total",
      ["details.value.session"] = "Session",
      ["details.value.tokens_io"] = "{input} in / {output} out",
      ["details.value.cache_io"] = "{read} read, {created} created",
      ["details.value.free_tier_cost"] =
        "Free Tier (would have been ~{cost})",
      ["details.suffix.this_chat"] = "(this chat)",
      ["details.suffix.this_turn"] = "(this turn)",
      ["details.tip.context"] =
        "Which source material was bundled with your prompt. 'Session' = live state of your REAPER session (tracks, items, FX, markers, etc.). 'API' = the REAPER/ReaScript API reference. 'fx:<plugin>' = per-plugin parameter reference. 'plugin_ref:<plugin>' = general plugin documentation.",
      ["details.tip.model"] = "Which model produced this response.",
      ["details.tip.est_cost"] =
        "Estimated cost for this exchange based on the provider's per-token pricing. May differ slightly from what the provider actually bills.",
      ["details.tip.est_total"] =
        "Running total of estimated cost across every turn in this chat up to and including this one. Hidden on turn 1 since it would just match Est. Cost.",
      ["details.tip.tokens"] =
        "Input tokens / output tokens used in this exchange. Input covers your prompt plus the bundled context; output is the model's reply.",
      ["details.tip.time"] = "How long the model took to return its response.",
      ["details.tip.cache"] =
        "Tokens read from the prompt cache / tokens newly written to the cache this turn. Cache reads are billed at a fraction of the normal input-token rate.",
      ["details.tip.api_calls"] =
        "How many round-trips to the model this turn took. 1 means a single clean request. >1 means a silent retry fired (docs auto-fetch, beta-header fallback, cache-expiration refresh, intra-turn context fetch); the Tokens / Cache / Time / Cost values reflect only the LAST request, so when this is >1 the visible numbers undercount the true work for the turn.",
      ["details.tip.complexity"] =
        "Auto-computed complexity score of your prompt (0-10). Higher = a more involved request. The parenthesised label shows which tier Auto mode picked for this turn: Fast (simple prompts), Balanced (mid-range), or Smart (complex work).",
      ["details.tip.thinking"] =
        "Reasoning effort level used for this response (only relevant for models that support extended thinking).",
      ["details.tip.fx_cache"] =
        "Filter applied to the FX cache this turn (limits which plugins contribute to the Context bundle).",
      ["chat.clear.title"] = "Confirm Clear",
      ["chat.clear.prompt"] = "Clear the entire conversation?",
      ["message.truncated.structured_cap"] =
        "Structured edit cut off at its compact action-token cap.",
      ["message.truncated.output_cap"] =
        "Response cut off - the model ran out of output tokens.",
      ["message.lower_thinking_to"] = "Lower Thinking to {level}",
      ["message.lower_thinking.tooltip"] =
        "Reduce reasoning depth so more budget goes to the visible reply.",
      ["message.retry"] = "Retry Message",
      ["message.retry.tooltip"] =
        "Re-send the last prompt with the current settings.",
      ["message.switch_to"] = "Switch to {label}",
      ["message.switch_resend.tooltip"] =
        "Switch Gemini to Flash 3.5 and resend the original message.",
      ["message.resend_failed"] = "Could not resend message",
      ["message.switch_failed"] = "Could not switch models",
      ["message.return_home"] = "Return to home screen",
      ["typed_actions.header"] = "STRUCTURED EDIT",
      ["typed_actions.status.undo_lua"] = "UNDO + LUA",
      ["typed_actions.status.undo_sent"] = "UNDO SENT",
      ["typed_actions.status.failed"] = "FAILED",
      ["typed_actions.status.auto_ran"] = "AUTO-RAN",
      ["typed_actions.status.validated"] = "VALIDATED",
      ["typed_actions.count.one"] = "{count} action",
      ["typed_actions.count.many"] = "{count} actions",
      ["typed_actions.kind.project_edit"] = "Project edit",
      ["typed_actions.kind.pan_automation"] = "Pan automation",
      ["typed_actions.kind.routing"] = "Routing",
      ["typed_actions.kind.folder_setup"] = "Folder setup",
      ["typed_actions.kind.fx_setup"] = "FX setup",
      ["typed_actions.kind.track_update"] = "Track update",
      ["typed_actions.kind.track_setup"] = "Track setup",
      ["typed_actions.undo.tooltip"] =
        "Undo the last REAPER action (Ctrl+Z)",
      ["typed_actions.undo_lua"] = "Undo and Request Lua",
      ["typed_actions.undo_lua.tooltip"] =
        "Undo this structured edit, then ask for the Lua/ReaScript version. Auto-run still follows your current setting.",
      ["typed_actions.no_original_prompt"] =
        "Could not find the original prompt",
      ["code.run.tooltip"] = "Execute this code in REAPER",
      ["code.run.manual_context.tooltip"] =
        "Install/run this from its REAPER toolbar action context",
      ["code.run.fragment.tooltip"] =
        "This block is a fragment or patch, not a runnable script",
      ["code.undo.tooltip"] = "Undo the last REAPER action (Ctrl+Z)",
      ["code.save_theme"] = "Save Theme",
      ["code.save_theme.tooltip"] =
        "Save the current theme color changes permanently to the theme file",
      ["code.theme_saved"] = "Theme colors saved to:\n{path}",
      ["code.theme_error.no_changes"] = "No theme changes to save.",
      ["code.theme_error.no_theme_file"] =
        "Could not determine the current theme file.",
      ["code.theme_error.zip_theme"] =
        "Your current theme is a .ReaperThemeZip file which cannot be edited directly.\n\nTo save changes: open the Theme development/tweaker window (Actions > Theme development/tweaker) and click 'Save Theme...' to export as a .ReaperTheme file.",
      ["code.theme_error.read_failed"] = "Cannot read theme file: {error}",
      ["code.theme_error.write_failed"] = "Cannot write theme file: {error}",
      ["code.theme_error.write_close_failed"] =
        "Failed to write theme file: {error}",
      ["code.theme_error.replace_failed"] =
        "Failed to replace theme file: {error}",
      ["code.backup.tooltip"] = "Save a backup of your project (.rpp-bak)",
      ["code.copy.tooltip"] = "Copy code to clipboard",
      ["code.save_jsfx.dialog_title"] = "Save JSFX Effect",
      ["code.save_jsfx.filter"] = "JSFX files (.jsfx)\0*.jsfx\0All files\0*.*\0",
      ["code.save_jsfx.fallback_title"] = "Save JSFX",
      ["code.save_jsfx.fallback_label"] =
        "Filename (saved to REAPER Effects folder):,extrawidth=260",
      ["code.save_lua.dialog_title"] = "Save Lua Script",
      ["code.save_lua.filter"] = "Lua files (.lua)\0*.lua\0All files\0*.*\0",
      ["code.save_lua.fallback_title"] = "Save Script",
      ["code.save_lua.fallback_label"] =
        "Filename (saved to REAPER Scripts folder):,extrawidth=260",
      ["code.save_lua.tooltip"] = "Save code as a .lua script file",
      ["code.save_browser_tip"] =
        "For a full file browser when saving scripts, install\njs_ReaScriptAPI via ReaPack (Extensions menu).\n\nThe basic filename prompt will open now.",
      ["code.save_browser_tip.title"] = "ReaAssist - Tip",
      ["code.edit.tooltip"] =
        "Make this code block editable (removes syntax highlighting)",
      ["code.backup_saved"] = "Backup Saved!",
      ["code.backup_unchanged.tooltip"] =
        "Project unchanged since last backup",
      ["code.project_not_saved"] = "Project not saved",
      ["code.risky.run_will_confirm"] =
        "Run will ask for confirmation",
      ["jsfx.add_selected"] = "Add To Selected Track(s)",
      ["jsfx.add.tooltip"] = "Save JSFX and add it to all selected tracks",
      ["jsfx.undo.tooltip"] = "Undo adding the JSFX to tracks (Ctrl+Z)",
      ["jsfx.copy.tooltip"] = "Copy JSFX code to clipboard",
      ["jsfx.save.tooltip"] = "Save JSFX to Effects/ReaAssist/ folder",
      ["jsfx.save_as.tooltip"] =
        "Save JSFX to a custom location (opens file browser in Effects folder)",
      ["jsfx.already_saved_to"] = "Already saved to {path}",
      ["jsfx.saved_to"] = "Saved to {path}",
      ["jsfx.save_failed"] = "Failed to save JSFX.",
      ["jsfx.added_to"] = "Added to {count} track(s).",
      ["modal.risky.title"] = "Review Before Running",
      ["modal.risky.intro"] =
        "This code uses operations that could affect files or system state outside of REAPER:",
      ["modal.risky.outro"] =
        "Review the code carefully before continuing.",
      ["modal.risky.run_anyway"] = "Run Anyway",
      ["modal.actions.title"] = "Add to Actions",
      ["modal.actions.prompt"] =
        "Script saved. Add it to the REAPER Actions menu?",
      ["modal.actions.add_failed"] =
        "Failed to add script to Actions menu.",
      ["modal.no_tracks.title"] = "No Tracks Selected",
      ["modal.no_tracks.body"] =
        "No tracks are selected.\n\nPlease select one or more tracks and try again.",
      ["dialog.reaper_old.title"] = "Older REAPER Version",
      ["dialog.reaper_old.headline"] =
        "REAPER 7 or newer is recommended",
      ["dialog.reaper_old.body"] =
        "Detected REAPER {version}. ReaAssist will still open, but newer REAPER features and APIs may not be available in this install. Upgrade when practical for the best results.",
      ["dialog.reaper_old.open_download"] = "Open Download Page",
      ["dialog.reaper_old.dont_show"] = "Don't Show Again",
      ["dialog.key_test.title"] = "API Key Test Results",
      ["dialog.key_test.all_ok"] =
        "All API Keys Tested and Working",
      ["dialog.key_test.results"] = "Test Results:",
      ["dialog.key_test.ok"] = "OK",
      ["dialog.key_test.failed"] = "FAILED",
      ["dialog.key_validation.title"] = "Key Validation Failed",
      ["dialog.key_validation.heading"] =
        "{provider}: Validation Failed",
      ["dialog.key_validation.default_provider"] = "API Key",
      ["dialog.key_validation.how_to_fix"] = "How to fix: {hint}",
      ["dialog.ceiling.title"] = "Output Ceiling Engaged",
      ["dialog.ceiling.headline"] = "Safety ceiling tripped",
      ["dialog.ceiling.body"] =
        "These effects exceeded the safety ceiling for >50 ms and self-muted to prevent runaway feedback. Mute clears on transport restart; if it re-trips, click Diagnose to attach the JSFX file and ask the model to analyze it.",
      ["dialog.ceiling.section"] = "MUTED EFFECTS",
      ["dialog.ceiling.count.one"] = "{count} effect",
      ["dialog.ceiling.count.many"] = "{count} effects",
      ["dialog.ceiling.muted_tooltip"] =
        "Muted: output ceiling tripped",
      ["dialog.ceiling.diagnose"] = "Diagnose with Model",
      ["dialog.ceiling.unknown"] = "(unknown)",
      ["dialog.ceiling.master"] = "Master",
      ["dialog.ceiling.track"] = "Track {index}",
      ["dialog.ceiling.dont_show_session"] =
        "Don't show again this session",
      ["dialog.backup.title"] = "Project Not Saved",
      ["dialog.backup.body"] =
        "You have auto-backup turned on and your project is not saved.",
      ["dialog.backup.save_project"] = "Save Project",
      ["dialog.backup.disable"] = "Disable Auto-Backup",
      ["dialog.resolve.title"] = "Choose a plugin to use...",
      ["dialog.resolve.intro"] =
        "You haven't set a preferred {type} plugin yet. Pick one to use for this request.",
      ["dialog.resolve.install_reeq"] =
        "Install ReEQ Instantly (Free)",
      ["dialog.resolve.reeq_hint"] =
        "ReEQ is recommended for best results.",
      ["dialog.resolve.placeholder"] =
        "What plugin would you like to use?",
      ["dialog.resolve.use_this"] = "Use this",
      ["dialog.resolve.use_fallback"] = "Use {plugin} instead",
      ["dialog.resolve.helper"] =
        "Enter the plugin name in the same way that it appears in the FX Browser.",
      ["dialog.resolve.empty_error"] =
        "Type a plugin name first.",
      ["dialog.resolve.no_match_error"] =
        "\"{name}\" doesn't match any installed plugin. Try the name as it appears in REAPER's FX Browser.",
      ["dialog.resolve.install_failed"] =
        "Install failed: {error}",
      ["dialog.quit.title"] = "Quit ReaAssist",
      ["dialog.quit.prompt"] = "Quit ReaAssist?",
      ["dialog.gemini.title"] = "Gemini Free Tier",
      ["dialog.gemini.headline"] = "Free Tier Detected",
      ["dialog.gemini.body1"] =
        "Your Gemini API key appears to be on Google's free tier. On the free tier, Google may use your prompts and responses to improve their models. This can include human review of your data.",
      ["dialog.gemini.body2"] =
        "This means project details like track names, plugin settings, and any code you send could be seen by reviewers or used in training data. Note that ReaAssist never sends or receives audio. Only text, code, and project metadata.",
      ["dialog.gemini.body3"] =
        "For professional or client work, consider enabling billing on your Google account. Paid accounts are not used for training and have higher rate limits. The Pro model has been hidden as it requires a paid account. Flash and Flash Lite remain available.",
      ["dialog.gemini.body4"] =
        "If you enable billing later, use the Test API Keys button on the Settings screen to update your account status.",
      ["dialog.gemini.understand"] = "I Understand",
      ["dialog.gemini.enable_billing"] =
        "Enable Billing with Google",
      ["dialog.gemini.recheck"] =
        "I've Enabled Billing - Recheck Account Now",
      ["dialog.gemini.mark_paid"] =
        "Incorrectly Detected as Free. Mark as Paid.",
      ["gemini.toast.verifying_tier"] = "Verifying Gemini tier...",
      ["gemini.toast.pro_available"] = "Gemini Pro available",
      ["gemini.toast.service_unavailable"] =
        "Gemini service unavailable - tier check will retry",
      ["gemini.toast.verify_failed_retry"] =
        "Couldn't verify Gemini tier - will retry on next start",
      ["gemini.toast.tier_timeout"] =
        "Gemini tier check timed out - will retry",
      ["gemini.toast.tier_failed"] =
        "Gemini tier check failed - will retry",
      ["network.timeout.gemini"] =
        "The request timed out while waiting for Google's Gemini service. Gemini may be overloaded or temporarily unavailable. If the rest of your internet is working, this is a provider-side availability issue, not a problem with your prompt, API key, or ReaAssist.\n\nTry again in a moment. If it keeps happening, switch to a faster Gemini model or another provider for this request.",
      ["network.timeout.generic"] =
        "The request timed out. The server may be busy, or your internet connection may have dropped.\n\nTry sending your message again.",
      ["network.key_test.timeout_short"] =
        "The server took too long to respond.",
      ["network.key_test.timeout_detail"] =
        "The server took too long to respond while checking your key. Your key is stored for this session but has not been permanently saved yet. Try sending a message to test it. Once verified, it will be saved automatically.\n\nIf that doesn't work, click the Settings button to re-enter your key.",
      ["network.curl.proxy"] =
        "Can't reach the proxy configured for {provider}. Check your network or proxy settings and try again.",
      ["network.curl.provider_unreachable"] =
        "Can't reach the {provider} servers. Please check your internet connection and try again.",
      ["network.curl.refused"] =
        "The server refused the connection. It may be temporarily down. Try again in a few minutes.",
      ["network.curl.closed_early"] =
        "The connection closed before the full response arrived. Try sending your message again.",
      ["network.curl.write_failed"] =
        "ReaAssist could not write the server response to its temporary file. Check that your REAPER resource folder is writable.",
      ["network.curl.timeout"] =
        "The connection timed out. Please check your internet connection and try again.",
      ["network.curl.secure_failed"] =
        "Couldn't establish a secure connection. A firewall or network setting may be blocking it.",
      ["network.curl.no_response"] =
        "The server closed the connection without sending a response. Try again in a moment.",
      ["network.curl.dropped"] =
        "The connection dropped while ReaAssist was receiving the response. Try again in a moment.",
      ["network.curl.certificate"] =
        "There's an issue with the server's security certificate. Please check that your computer's date and time are correct.",
      ["network.curl.cert_bundle"] =
        "curl could not read its certificate bundle. Check your curl or system certificate installation.",
      ["network.curl.http2"] =
        "The HTTP/2 connection failed while talking to the server. Try again; if it repeats, switch networks or disable VPN/proxy.",
      ["network.curl.generic"] =
        "A network error occurred. Please check your internet connection and try again.",
      ["network.curl.back_online_settings"] =
        "Once you're back online, click the Settings button to try again.",
      ["response.context_followup_failed"] =
        "Tried to load additional project info but the follow-up request didn't go through. Please try again.",
      ["response.context_loop"] =
        "The model re-requested context that was already provided. Try rephrasing your request, or switch to a different model.",
      ["response.resume_failed"] =
        "Couldn't resume the request after your selection. Please try sending the message again.",
      ["retry.failed"] =
        "Auto-retry {reason} did not go through. Please resend the last message.",
      ["retry.reason.after_empty_length_capped_reply"] =
        "after empty length-capped reply",
      ["retry.reason.after_empty_response"] =
        "after empty response",
      ["retry.reason.after_unclosed_lua_fence"] =
        "after unclosed Lua fence",
      ["retry.reason.after_unfenced_lua_response"] =
        "after unfenced Lua response",
      ["retry.reason.after_prose_only_action_response"] =
        "after prose-only action response",
      ["retry.reason.after_marker_vs_region_response"] =
        "after marker-vs-region response",
      ["retry.reason.after_void_return_api_assignment"] =
        "after void-return API assignment",
      ["retry.reason.after_inert_track_creation_script"] =
        "after inert track-creation script",
      ["retry.reason.after_unnamed_created_track"] =
        "after unnamed created track",
      ["retry.reason.after_new_track_index_mismatch"] =
        "after new-track index mismatch",
      ["retry.reason.after_literal_track_index_mismatch"] =
        "after literal track-index mismatch",
      ["retry.reason.after_numeric_target_name_guard_mismatch"] =
        "after numeric target/name-guard mismatch",
      ["retry.reason.after_folder_boundary_mismatch"] =
        "after folder-boundary mismatch",
      ["retry.reason.after_track_selection_api_write"] =
        "after track-selection API write",
      ["retry.reason.after_missing_exclusive_track_selection"] =
        "after missing exclusive track selection",
      ["retry.reason.after_missing_bus_return_sends"] =
        "after missing bus/return sends",
      ["retry.reason.after_master_send_api_misuse"] =
        "after master-send API misuse",
      ["retry.reason.after_track_pan_api_misuse"] =
        "after track-pan API misuse",
      ["retry.reason.after_lua_parse_error"] =
        "after Lua parse error",
      ["retry.reason.for_sandbox_forbidden_globals"] =
        "for sandbox-forbidden Lua APIs",
      ["retry.reason.for_typed_action_fence_label"] =
        "for typed-action fence label",
      ["retry.reason.for_missing_typed_action_block"] =
        "for missing typed-action block",
      ["retry.reason.for_typed_action_schema"] =
        "for typed-action schema",
      ["retry.reason.for_typed_action_semantics"] =
        "for typed-action semantics",
      ["retry.reason.with_api_reference"] =
        "with API reference",
      ["retry.reason.for_mistyped_reaper_global"] =
        "for mistyped reaper global",
      ["retry.reason.for_invalid_reaper_calls"] =
        "for invalid reaper.* calls",
      ["retry.reason.after_fragile_toolbar_action_pattern"] =
        "after fragile toolbar action pattern",
      ["retry.reason.after_midi_validator_issue"] =
        "after MIDI validator issue",
      ["retry.reason.after_midi_input_routing_issue"] =
        "after MIDI input routing issue",
      ["retry.reason.for_unverified_main_oncommand_ids"] =
        "for unverified Main_OnCommand ID(s)",
      ["retry.reason.for_tempo_marker_bar_alignment"] =
        "for tempo-marker bar alignment",
      ["retry.reason.for_poor_transient_stretch_marker_detector"] =
        "for poor transient stretch-marker detector",
      ["retry.reason.for_whole_item_drum_quantize"] =
        "for whole-item drum quantize",
      ["retry.reason.for_unsynchronized_drum_stretch_markers"] =
        "for unsynchronized drum stretch markers",
      ["retry.reason.for_reaper_arity_mismatch"] =
        "for reaper.* arity mismatch",
      ["retry.reason.for_media_item_label_misuse"] =
        "for MediaItem item-label misuse",
      ["retry.reason.for_ignored_createtracksend_result"] =
        "for ignored CreateTrackSend result",
      ["retry.reason.for_stock_plugin_substitution"] =
        "for stock plugin substitution",
      ["retry.reason.for_exact_fx_identifier_repair"] =
        "for exact FX identifier repair",
      ["retry.reason.for_unchecked_addbyname_result"] =
        "for unchecked AddByName result",
      ["retry.reason.for_dependent_getbyname_result"] =
        "for dependent GetByName result",
      ["retry.reason.for_chain_upsert_violation"] =
        "for chain-upsert violation",
      ["retry.reason.for_missing_reaper_defer_wrap"] =
        "for missing reaper.defer wrap",
      ["retry.reason.after_unrequested_fx_parameter_writes"] =
        "after unrequested FX parameter writes",
      ["retry.reason.for_missing_helper_definitions"] =
        "for missing helper definitions",
      ["retry.reason.for_corrupted_helper_body"] =
        "for corrupted helper body",
      ["retry.reason.for_invalid_jsfx"] =
        "for invalid JSFX",
      ["validator.track_creation_index_blocked"] =
        "The script appears to fetch a newly-created track with a GetTrack index that does not exist yet. Auto-run is blocked; review and correct the InsertTrackAtIndex/GetTrack pairing before running manually.",
      ["validator.track_index_blocked"] =
        "I blocked this script because its track targeting still does not match the current session after an automatic correction attempt. Affected line(s): {lines}. Ask ReaAssist to regenerate it before running.",
      ["validator.target_name_guard_blocked"] =
        "I blocked this script because the user targeted a numbered track, but the script still requires that track to have a specific name the user did not request. Affected line(s): {lines}. Ask ReaAssist to regenerate it before running.",
      ["validator.folder_not_closed_blocked"] =
        "The script appears to open a folder but never closes it on the requested last child `{last_child}`. Auto-run is blocked; review I_FOLDERDEPTH before running manually.",
      ["validator.folder_closed_wrong_track_blocked"] =
        "The script appears to close a folder on `{track}` instead of the requested last child `{last_child}`. Auto-run is blocked; review I_FOLDERDEPTH before running manually.",
      ["validator.bus_routing_blocked"] =
        "The user asked for tracks going into a bus or return, but the script still does not create sends with reaper.CreateTrackSend(...). Auto-run is blocked; review the routing before running manually.",
      ["validator.master_send_blocked"] =
        "The script appears to change track master/parent sends with reaper.RemoveTrackSend(..., 1, ...). Category 1 is hardware output, not the master send. Use reaper.SetMediaTrackInfo_Value(track, \"B_MAINSEND\", 0 or 1). Auto-run is blocked; review and correct the master-send API usage before running manually.",
      ["validator.mistyped_reaper_global_blocked"] =
        "The model misspelled the REAPER API global, even after a retry: {lines}. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.invalid_reaper_calls_blocked"] =
        "The model emitted REAPER API calls that don't exist on your machine, even after a retry: {calls}. Auto-run is blocked; review and edit the code before clicking Run manually, or retry with a stronger model.",
      ["validator.toolbar_action_blocked"] =
        "The model emitted a fragile toolbar/action script even after a retry: {codes}. Auto-run is blocked because this pattern can require repeated toolbar clicks or leave stale toolbar state. Review the script before saving/installing it as a REAPER action.",
      ["validator.midi_plain_item_blocked"] =
        "The script creates a plain media item with AddMediaItemToTrack but then inserts MIDI into it. Auto-run is blocked because this produces an item with no MIDI notes. Use CreateNewMIDIItemInProj for new MIDI items.",
      ["validator.midi_literal_ppq_blocked"] =
        "The script passes beat or second-looking numbers directly to MIDI_InsertNote. Auto-run is blocked because MIDI note start/end positions must be PPQ. Convert project time with MIDI_GetPPQPosFromProjTime before inserting notes.",
      ["validator.midi_table_pitch_blocked"] =
        "The script passes a table as the MIDI_InsertNote pitch argument. Auto-run is blocked because note pitch must be a number from 0 to 127.",
      ["validator.midi_bad_track_arg_blocked"] =
        "The script passes a project id or boolean as the first argument to CreateNewMIDIItemInProj. Auto-run is blocked because that argument must be a MediaTrack handle.",
      ["validator.midi_input_filter_blocked"] =
        "The script does not safely implement the requested MIDI input-device filter. REAPER cannot encode 'all MIDI devices except one named device' as a single track I_RECINPUT value, and the generated Lua still uses an unsupported map or only lists devices. Auto-run is blocked; use a name-matched helper-track workaround or set a single named input directly.",
      ["validator.action_id_blocked"] =
        "The model emitted unverified numeric REAPER action ID(s), even after a retry: {ids}. Main_OnCommand accepts any integer, so this can silently run the wrong action or do nothing. Auto-run is blocked; confirm the exact Action List ID or rewrite the script with direct REAPER API calls before running it.",
      ["validator.tempo_marker_alignment_blocked"] =
        "The model tried to align a bar/beat line to the cursor by inserting a tempo marker at the bar's existing position even after a retry. Auto-run is blocked; anchor the intended measure/beat at the edit cursor or transient instead.",
      ["validator.transient_detector_blocked"] =
        "The model tried to place drum-hit/transient stretch markers with a custom Lua audio-accessor detector even after a retry. That path tends to add false markers on decays and bleed. Auto-run is blocked; use REAPER's Dynamic Split / transient action, or explicitly ask for a custom threshold detector if you want that lower-quality approximation.",
      ["validator.drum_whole_item_quantize_blocked"] =
        "The model tried to quantize/edit drums by moving whole media items even after a retry. That can do nothing or move the wrong musical material. Auto-run is blocked; use a shared guide-track stretch-marker timing map instead.",
      ["validator.drum_marker_sync_blocked"] =
        "The model tried to write drum stretch markers without normalizing the same marker map across every affected drum item. Auto-run is blocked; the final stretch markers must be identical on guide and non-guide tracks.",
      ["validator.reaper_arity_blocked"] =
        "The model emitted REAPER API call(s) with the wrong number of arguments, even after a retry: {calls}. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.media_item_label_blocked"] =
        "The script tries to label MediaItems with P_NAME. Auto-run is blocked because MediaItem string params accept only P_NOTES/P_EXT/GUID; visible arrange labels live on the take. Use AddTakeToMediaItem or CreateNewMIDIItemInProj, then call GetSetMediaItemTakeInfo_String(take, \"P_NAME\", label, true).",
      ["validator.send_index_blocked"] =
        "The model created sends with unsafe CreateTrackSend return-value handling, even after a retry: {details}. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.stock_fx_substitution_blocked"] =
        "The model substituted third-party or JSFX plugin(s) for explicitly requested stock Cockos plugin(s), even after a retry: {plugins}. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.fx_identifier_drift_blocked"] =
        "The model stripped exact preferred plugin identifier(s), even after a retry: {plugins}. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.fx_addbyname_unchecked_blocked"] =
        "The model wrote TrackFX_AddByName / TakeFX_AddByName without checking the result, even after a retry: {vars}. If the plugin fails to load the script will silently report success. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.fx_getbyname_silent_skip_blocked"] =
        "The model wrote TrackFX_GetByName / TakeFX_GetByName dependent parameter code with no failure path, even after a retry: {vars}. If the FX is missing the script will silently report success without changing the requested plugin. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.chain_upsert_blocked"] =
        "The model wrote chain-build code with an upsert pairing violation, even after a retry. Each plugin in the chain needs both a GetByName (reuse) and an AddByName (add if missing) call. Auto-run is blocked; review and edit the code before clicking Run manually.",
      ["validator.defer_plugin_params_blocked"] =
        "The model emitted plugin parameter calls ({calls}) outside a reaper.defer() block, even after a retry. Some VST3 plugins silently ignore parameter changes that arrive in the same execution frame as TrackFX_AddByName; the script may appear to run successfully but produce no audible change. Auto-run is blocked; review the code and wrap the param calls in reaper.defer(function() ... end) before clicking Run manually.",
      ["validator.fx_param_scope_blocked"] =
        "The model wrote plugin parameter changes even though the request only asked to add/load the FX. Auto-run is blocked because those extra parameter writes may change the sound beyond the user's request. Review and remove the TrackFX_SetParam*/TakeFX_SetParam* lines before running manually.",
      ["validator.missing_helper_definitions_blocked"] =
        "The model called helper function(s) without including their definitions, even after a retry: {helpers}. These are local functions, not REAPER built-ins, so the script will crash at runtime when they are reached. Auto-run is blocked; paste the helper definitions from prompt_bundle:plugin_helpers before clicking Run, or refactor to use SetParamNormalized directly with verified values.",
      ["validator.helper_integrity_blocked"] =
        "The model rewrote bundled helper function body in a way that drops a safety guard, even after a retry: {helpers}. The corrupted helper would crash at runtime inside reaper.defer. Auto-run is blocked; review and edit the code before clicking Run manually, or paste the helper definition verbatim from prompt_bundle:plugin_helpers.",
      ["validator.jsfx_safety_blocked"] =
        "The model emitted JSFX that fails ReaAssist's safety/syntax validator, even after a retry: {codes}. Auto-save and auto-run are blocked; review the code carefully and fix the listed issues before saving manually.",
      ["validator.sandbox_api_blocked"] =
        "I blocked this script because it references Lua APIs that are unavailable in ReaAssist's execution sandbox: {apis}. Ask ReaAssist to regenerate it without those APIs.",
      ["response.html_gemini_5xx"] =
        "Google's Gemini service returned a 5xx provider error instead of a JSON API response. This usually means Gemini is overloaded or temporarily unavailable, not that your prompt, API key, or ReaAssist failed.\n\nWait a moment and retry. If it keeps happening, switch to a faster Gemini model or another provider for this request.",
      ["response.html_non_json"] =
        "The server returned an HTML page instead of a JSON response. This usually means a proxy, firewall, or captive portal (hotel/coffee shop Wi-Fi) is intercepting the request, or the API endpoint is temporarily down behind a 5xx gateway error.\n\nTry a different network, disable any VPN/proxy, or wait a few minutes and retry.",
      ["response.unreadable"] =
        "Got an unreadable response from the server. This is usually a temporary glitch.\n\nPlease try again.",
      ["response.unreadable_detail"] =
        "Got an unreadable response from the server. This is usually a temporary glitch.\n\nTechnical detail: {detail}\n\nPlease try again.",
      ["response.unexpected"] =
        "Got an unexpected response from the server. This is likely a temporary issue.\n\nPlease try again.",
      ["response.custom_unexpected_shape"] =
        "The custom provider returned JSON, but not in the OpenAI-compatible chat-completions shape ReaAssist expected. Check that this provider points to a chat-completions endpoint for the selected model, then try again.\n\nDetails were saved to the debug log.",
      ["response.gemini_cache_expired"] =
        "The Gemini context cache expired between sends. Please send your message again; a fresh cache will be created automatically.",
      ["response.gemini_paid_required"] =
        "Gemini Pro requires a paid Google account. Your account appears to be on the free tier.\n\nThe model has been switched to Flash Lite. To use Pro, enable billing at aistudio.google.com/apikey.",
      ["response.provider_rate_limited_many"] =
        "The provider is rate-limiting ReaAssist right now. This turn already used {calls} hidden context/retry API calls, so the throttle can appear even though you only sent one visible message.\n\nWait about {seconds} seconds before trying again. ReaAssist keeps the original prompt attached during automatic throttle retries; if this message appears, those retries have already been exhausted for this turn.\n\nIf this keeps happening, try switching models in the dropdown.",
      ["response.provider_rate_limited_one"] =
        "The provider is rate-limiting ReaAssist right now. This can happen after recent internal retries or provider throughput bursts, even if this is your first visible message in a while.\n\nWait about {seconds} seconds before trying again. ReaAssist keeps the original prompt attached during automatic throttle retries; if this message appears, those retries have already been exhausted for this turn.\n\nIf this keeps happening, try switching models in the dropdown.",
      ["response.openai_throttle_exhausted"] =
        "OpenAI is throttling this request because the account/model token-per-minute limit is temporarily saturated. This is a provider-side throughput limit, not a Lua or prompt failure.\n\nReaAssist retried with exponential backoff and OpenAI still returned a rate-limit error. Wait a minute and retry, or switch to a smaller model for this request.",
      ["response.google_503_recovery"] =
        "Google's Gemini service returned 503 UNAVAILABLE: this model is currently at capacity or temporarily unavailable. This is a provider-side availability issue, not a problem with your prompt, API key, or ReaAssist.\n\nReaAssist retried with exponential backoff and Google still returned 503 UNAVAILABLE. You can wait and retry later, or switch to Flash 3.5 and resend the same message.",
      ["response.google_503"] =
        "Google's Gemini service returned 503 UNAVAILABLE: this model is currently at capacity or temporarily unavailable. This is a provider-side availability issue, not a problem with your prompt, API key, or ReaAssist.\n\nReaAssist retried with exponential backoff and Google still returned 503 UNAVAILABLE. You can wait and retry later.",
      ["response.api_key_invalid"] =
        "Your {provider} API key isn't working. It may have expired or been entered incorrectly.\n\nClick the Settings button below to enter a new one.\n\nYou can find or create a key here:",
      ["response.api_key_storage_note"] =
        "Your key is obfuscated and locked to this REAPER install path. It will not work if copied to another machine.",
      ["response.credits_exhausted"] =
        "Your {provider} account has run out of credits.\n\nTo continue using ReaAssist, add funds to your account:",
      ["response.provider_overloaded"] =
        "The servers are busy right now. Wait a moment and try again; this usually clears up quickly.",
      ["response.provider_internal_error"] =
        "The provider service returned a temporary internal server error. This is a provider-side service issue, not a problem with your prompt, API key, or ReaAssist.\n\nReaAssist retried with exponential backoff and the provider still failed. Wait a moment and try again, or switch models for this request.",
      ["response.context_too_long"] =
        "This conversation has gotten too long for the model to handle.\n\nTo fix this:\n- Click + new chat to start fresh\n- Try a shorter message\n- Turn off \"Always include REAPER API reference\" or Send snapshot to reduce size",
      ["response.model_not_found"] =
        "That model doesn't seem to exist anymore. It may have been renamed or retired.\n\nTry picking a different one from the dropdown below.",
      ["response.permission_denied"] =
        "Your API key doesn't have access to this model. This usually means it requires a higher account tier.\n\nTry a different model, or check your plan here:",
      ["response.openai_rate_limit"] =
        "OpenAI is throttling this request because the account/model token-per-minute limit is temporarily saturated. This is a provider-side throughput limit, not a Lua or prompt failure.\n\nWait a minute and try again, or switch to a smaller model for this request.",
      ["response.provider_server_error"] =
        "The provider service returned a temporary server error. This is a provider-side service issue, not a problem with your prompt, API key, or ReaAssist.\n\nReaAssist retried with exponential backoff and the provider still failed. Wait a moment and try again, or switch models for this request.",
      ["response.provider_busy"] =
        "The provider service is busy right now. This is a provider-side capacity issue, not a problem with your prompt, API key, or ReaAssist.\n\nReaAssist retried with exponential backoff and the provider still failed. Wait a moment and try again, or switch models for this request.",
      ["response.google_quota_exhausted"] =
        "Your Google account has exhausted its Gemini quota.\n\nIf you're on the free tier, you may need to enable billing. If you're on a paid plan, add funds or check your usage limits:",
      ["response.google_model_not_found"] =
        "That model doesn't seem to exist anymore. Try picking a different one.",
      ["response.google_permission_denied"] =
        "Your API key doesn't have access to this model.",
      ["code.backup_failed_after_save"] =
        "Project saved, but the safety backup failed ({error}). The generated code was NOT run. Resolve the disk/permission issue and try again, or click Run manually if you want to proceed without a backup.",
      ["code.compile_error"] =
        "Lua compile error in generated code:\n\n{error}",
      ["code.runtime_error"] =
        "Runtime error in generated code:\n\n{error}",
      ["attach.error.openai_pdf_unsupported"] =
        "ChatGPT does not support PDF attachments. The file name will be sent but its content cannot be read. Try Claude or Gemini for PDF support.",
      ["attach.error.max_count"] =
        "Maximum {count} attachments per message.",
      ["attach.error.unsupported_type"] =
        "Unsupported file type{ext}. Supported: images, PDFs, and common text formats.",
      ["attach.error.read_failed"] =
        "Could not read file: {error}",
      ["attach.error.text_too_large"] =
        "Text file too large ({size} KB, max {max} KB).",
      ["attach.error.file_too_large"] =
        "File too large ({size} MB, max {max} MB).",
      ["attach.error.empty_file"] =
        "File is empty.",
      ["attach.warning.large_file"] =
        "Large file ({size} MB), estimated cost: {cost}",
      ["attach.error.screenshot_failed"] =
        "Screenshot failed.",
      ["attach.error.screenshot_empty"] =
        "Screenshot produced an empty file.",
      ["attach.error.screenshot_too_large"] =
        "Screenshot too large ({size} MB, max {max} MB).",
      ["attach.name.screenshot"] =
        "Screenshot",
      ["attach.error.clipboard_no_image"] =
        "No image found in clipboard.",
      ["attach.error.clipboard_empty"] =
        "Clipboard image is empty.",
      ["attach.error.clipboard_too_large"] =
        "Clipboard image too large ({size} MB, max {max} MB).",
      ["typed_actions.error.fallback_request_failed"] =
        "Typed-action fallback model request did not go through. Please resend the last message.",
      ["typed_actions.error.failed"] =
        "Structured edit failed: {message}",
      ["typed_actions.error.callback_failed"] =
        "Structured edit completion callback failed: {error}",
      ["typed_actions.error.param_write_failed"] =
        "Structured edit parameter write failed: {error}",
      ["typed_actions.error.executor_disabled"] =
        "Structured track edits are temporarily disabled.",
      ["typed_actions.error.executor_unavailable"] =
        "Structured track edits are unavailable in this install.",
      ["typed_actions.error.details"] =
        "Details: {detail}",
      ["typed_actions.error.blocked_before_change"] =
        "I blocked this structured edit before it changed the project because the plan did not match the request safely. No changes were made.",
      ["typed_actions.error.partial_failed"] =
        "Structured edit failed after making part of the change. ReaAssist stopped immediately; use REAPER Undo if the project is not in the state you want.",
      ["typed_actions.error.failed_before_change"] =
        "Structured edit failed before it changed the project. No changes were made.",
      ["typed_actions.status.backup_required"] =
        "Structured edit validated, but auto-run is blocked until the project is saved for safety backup.",
      ["typed_actions.status.backup_failed"] =
        "Structured edit validated, but auto-run is blocked because ReaAssist could not create a safety backup.",
      ["typed_actions.status.auto_run_off"] =
        "Structured edit validated, but it was not run because Auto-run is off.",
      ["jsfx.done"] =
        "Done.",
      ["jsfx.diagnose.read_failed"] =
        "Could not read JSFX file for diagnosis: {path}",
      ["dialog.scale.title"] = "Confirm UI Scale",
      ["dialog.scale.reverting"] = "Reverting in {seconds}s...",
      ["dialog.scale.keep"] = "Keep Scale",
      ["dialog.scale.revert"] = "Revert Now",
      ["update.strip.updating"] = "Updating ({progress})...",
      ["update.strip.done"] =
        "Updated to v{version}. Close and reopen ReaAssist to apply.",
      ["update.title.repair"] = "ReaAssist - Files Need Repair",
      ["update.title.available"] = "Update Available",
      ["update.progress.applying"] = "Applying update...",
      ["update.progress.restoring"] = "Restoring files...",
      ["update.progress.downloading"] = "Downloading update...",
      ["update.progress.file_count"] = "File {index} of {total}",
      ["update.progress.preparing"] = "Preparing file list",
      ["update.done.repair.one"] = "Restored {count} file successfully.",
      ["update.done.repair.many"] =
        "Restored {count} files successfully.",
      ["update.done.repair_restart"] =
        "Restarting to load the restored files...",
      ["update.done.repair_reopen"] =
        "Close and reopen ReaAssist to reload the restored files.",
      ["update.done.updated"] =
        "Updated to v{version} successfully.",
      ["update.done.update_restart"] =
        "Restarting to apply the new version...",
      ["update.done.update_reopen"] =
        "Close and reopen ReaAssist to start using the new version.",
      ["update.failed.noun.update"] = "Update",
      ["update.failed.noun.repair"] = "Repair",
      ["update.failed.action.sync"] = "sync",
      ["update.failed.action.reinstall"] = "reinstall",
      ["update.failed.sha"] =
        "{noun} files temporarily out of sync. GitHub's CDN may still be propagating a new release. Wait a minute or two, then click Retry.",
      ["update.failed.content"] =
        "{noun} aborted: a downloaded file did not look like ReaAssist content. This usually means a captive portal, proxy, or VPN is intercepting the download. Check your network, then Retry.",
      ["update.failed.generic"] =
        "{noun} failed. Click Retry, or {action} via ReaPack if the problem persists.",
      ["update.toast.url_missing"] = "Update URL not configured",
      ["update.toast.checking"] = "Checking for updates...",
      ["update.toast.start_failed"] = "Update check failed to start",
      ["update.toast.up_to_date"] = "Already up to date",
      ["update.repair.prompt.one"] =
        "{count} ReaAssist file needs to be restored from v{version}.",
      ["update.repair.prompt.many"] =
        "{count} ReaAssist files need to be restored from v{version}.",
      ["update.repair.detail.missing_modified"] =
        "({missing} missing, {mismatched} modified or corrupted)",
      ["update.repair.detail.missing"] = "({count} missing)",
      ["update.repair.detail.modified"] =
        "({count} modified or corrupted)",
      ["update.repair.info"] =
        "Automatic repair - No manual download needed.",
      ["update.repair.now"] = "Repair Now",
      ["update.available.prompt"] =
        "ReaAssist v{remote} is available (you have v{current}).",
      ["update.available.desc1"] =
        "The update is quick and applies directly.",
      ["update.available.desc2"] = "(No manual download needed)",
      ["update.action.update_now"] = "Update Now",
      ["update.action.view_changelog"] = "View Changelog",
      ["settings.lang.checking"] = "Checking languages...",
      ["settings.lang.download_suffix"] = "Download",
      ["settings.lang.downloading"] = "Downloading {language} language pack...",
      ["settings.lang.downloading_suffix"] = "Downloading...",
      ["settings.lang.help_downloading"] = "Downloading {language} help pack...",
      ["settings.lang.help_installed_toast"] = "{language} help pack installed.",
      ["settings.lang.installed_toast"] = "{language} language pack installed.",
      ["settings.lang.help_updated_toast"] =
        "{language} help pack updated.",
      ["settings.lang.updated_toast"] = "{language} translations updated.",
      ["settings.lang.failed"] =
        "Could not download {language}. ReaAssist will stay in {current}.",
      ["settings.lang.failed_detail"] =
        "Could not download {language}. ReaAssist will stay in {current}. {detail}",
      ["settings.lang.index_failed"] = "Could not check language packs.",
      ["settings.lang.index_failed_detail"] =
        "Could not check language packs. {detail}",
      ["settings.lang.copy_details"] = "Copy details",
      ["settings.lang.details_copied"] = "Language download details copied.",
      ["settings.lang.retry_suffix"] = "Retry",
      ["settings.lang.finish_download_first"] =
        "Finish the language pack download first",
      ["settings.font.title"] = "Download Language Font",
      ["settings.font.heading"] = "Download Language Font?",
      ["settings.font.downloading"] = "Downloading font...",
      ["settings.font.verifying"] = "Verifying font...",
      ["settings.font.installing"] = "Installing font...",
      ["settings.font.installed"] = "Font installed.",
      ["settings.font.ready_toast"] = "{language} font installed",
      ["settings.font.system_fallback"] = "Using system font.",
      ["settings.font.system_fallback_toast"] =
        "Using a system font for {language}",
      ["settings.font.body"] =
        "{language} needs a {size} font download so chat text renders correctly.",
      ["settings.font.failed"] = "Font download failed.",
      ["settings.font.start_failed"] = "Font download failed to start.",
      ["settings.font.finish_download_first"] =
        "Finish the font download first",
      ["settings.font.error.unknown"] = "Unknown font download error.",
      ["settings.font.error.no_font_needed"] =
        "No optional font is needed for this language.",
      ["settings.font.error.already_running"] =
        "A language font download is already running.",
      ["settings.font.copy_details"] = "Copy details",
      ["settings.font.details_copied"] = "Font download details copied.",
      ["settings.font.error.update_busy"] =
        "Finish the current update check before downloading a font.",
      ["settings.font.error.launch"] = "Font download could not start.",
      ["settings.font.error.no_metadata"] =
        "Missing downloaded font metadata.",
      ["settings.font.error.stage"] =
        "Could not stage downloaded font: {error}",
      ["settings.font.error.download_missing"] = "Download did not launch.",
      ["settings.font.error.download_timeout"] = "Font download timed out.",
      ["settings.font.error.download_failed"] = "Font download failed.",
      ["settings.font.error.empty"] = "Downloaded font file is empty.",
      ["settings.font.error.size_mismatch"] =
        "Downloaded font size was {actual} bytes, expected {expected}.",
      ["settings.font.error.checksum_start"] =
        "Font checksum could not start.",
      ["settings.font.error.checksum_timeout"] = "Font checksum timed out.",
      ["settings.font.error.checksum_failed"] = "Font checksum failed.",
      ["settings.font.error.checksum_mismatch"] =
        "Downloaded font checksum did not match.",
      ["settings.font.error.install_move"] =
        "Could not move the downloaded font into Data/Lang/fonts.",
      ["settings.chat_language.label"] = "Language",
      ["settings.chat_language.tooltip"] =
        "Assistant replies and newly localized local reply surfaces use this language. Code, diagnostics, plugin names, and REAPER API names stay unchanged.",
      ["settings.badge.beta"] = "Beta",
      ["settings.hero.subtitle.reentry"] = "Configure API keys & preferences.",
      ["settings.hero.subtitle.first_run"] =
        "Add at least one API key to get started.",
      ["settings.hero.breadcrumb.reentry"] = "SETTINGS",
      ["settings.hero.breadcrumb.first_run"] = "FIRST-RUN SETTINGS",
      ["settings.first_run.intro"] =
        "Keys are obfuscated and stored locally on this machine and sent only to your chosen provider. Claude has shown the best all-around results in testing. Gemini is the only provider to offer a free tier. You may also use a local or custom LLM to keep your data fully offline and private.",
      ["settings.section.api_keys"] = "API KEYS",
      ["settings.section.preferences"] = "PREFERENCES",
      ["settings.section.advanced"] = "ADVANCED",
      ["settings.status.active"] = "Active",
      ["settings.status.inactive"] = "Inactive",
      ["settings.status.connected"] = "CONNECTED",
      ["settings.status.testing"] = "TESTING",
      ["settings.toast.saved"] = "Settings saved",
      ["settings.toast.saved_need_key"] =
        "Settings saved. Add an API key or custom provider to continue.",
      ["settings.error.need_key_or_custom"] =
        "Please enter at least one valid API key, or configure a custom provider.",
      ["settings.api_key.placeholder"] = "Paste API key...",
      ["settings.api_key.tooltip"] =
        "Paste your {provider} API key here",
      ["settings.api_key.card_tooltip"] =
        "{provider} API key. Stored locally on this machine, obfuscated, and locked to this install path for security.",
      ["settings.api_key.console_tooltip"] =
        "Sign up or manage your {provider} API keys on the provider's console",
      ["settings.api_key.current"] = "Current: {key}",
      ["settings.api_key.toast.validated"] = "API key validated",
      ["settings.api_key.provider.custom"] = "Custom LLM",
      ["settings.api_key.provider.generic"] = "the provider",
      ["settings.api_key.error.install_moved"] =
        "Your REAPER install location has changed since your API key was last saved. For security, the key is locked to the install path and cannot be decoded from a different location. Please paste your API key again to continue.",
      ["settings.api_key.error.in_flight_short"] =
        "Another request is in progress. Try again in a moment.",
      ["settings.api_key.error.in_flight_detail"] =
        "Couldn't start the {provider} key test -- another request is already in flight.",
      ["settings.api_key.error.in_flight_hint"] =
        "Wait a few seconds and click Test API Keys again.",
      ["settings.api_key.error.local_start_short"] =
        "Couldn't start the {provider} key test (local error writing temp files).",
      ["settings.api_key.error.local_start_detail"] =
        "Couldn't start the {provider} key test. ReaAssist failed to write its temporary request files.",
      ["settings.api_key.error.local_start_hint"] =
        "Check that your REAPER Resources directory is writable and that no antivirus is locking files in it.",
      ["settings.api_key.error.custom_models_unexpected"] =
        "The endpoint responded but /v1/models returned an unexpected response.",
      ["settings.api_key.error.custom_model_test_failed"] =
        "The endpoint responded but the model test failed.",
      ["settings.api_key.error.server_said"] = "Server said: {message}",
      ["settings.api_key.error.auth_failed_short"] =
        "Authentication failed. The key may have expired or been revoked.",
      ["settings.api_key.error.didnt_work_short"] =
        "That key didn't work. It may have expired or been entered incorrectly.",
      ["settings.api_key.error.didnt_work_provider"] =
        "That {provider} key didn't work. It may have expired or been entered incorrectly. Please paste a valid key and try again.",
      ["settings.api_key.error.auth_detail"] =
        "The {provider} API key failed authentication. The key may have expired, been revoked, or was entered incorrectly.",
      ["settings.api_key.error.auth_hint"] =
        "Double-check the key for typos, or generate a new one at your provider's console.",
      ["settings.api_key.error.auth_chat"] =
        "That {provider} key didn't work. It may have expired or been entered incorrectly.\n\nClick the Settings button to try again.\n\nYou can find or create a key here:",
      ["settings.api_key.error.custom_connect_hint"] =
        "Check that the server is running, the URL and port are correct, and the model identifier matches what the server expects.",
      ["settings.api_key.error.custom_network_hint"] =
        "Check that the server is running and the URL/port is correct.",
      ["settings.api_key.error.builtin_network_hint"] =
        "Check your internet connection and try again.",
      ["settings.api_key.error.in_flight_timeout_short"] =
        "Another request was in progress for too long. Try Test API Keys again.",
      ["settings.api_key.error.in_flight_timeout_hint"] =
        "Wait for any in-flight request to finish, then try again.",
      ["settings.api_key.remove"] = "Remove",
      ["settings.api_key.confirm_remove"] = "Confirm?",
      ["settings.api_key.remove_tooltip"] =
        "Remove this API key. Requires a second click to confirm.",
      ["settings.api_key.confirm_remove_tooltip"] =
        "Click again to remove this key. Auto-cancels in 3s.",
      ["settings.api.test_keys.label"] = "Test API Keys",
      ["settings.api.test_keys.tooltip"] =
        "Verify all API keys (stored or newly pasted) and recheck Gemini account status",
      ["settings.api.custom_providers.label"] = "Local & Custom Providers",
      ["settings.api.custom_providers.tooltip"] =
        "Manage OpenAI-compatible providers: local servers (Ollama, LM Studio, llama.cpp, vLLM) and online gateways (OpenRouter, Groq, Together AI, Mistral, etc.)",
      ["settings.custom.list.subtitle"] = "Local & Custom Providers",
      ["settings.custom.list.breadcrumb"] = "LOCAL & CUSTOM PROVIDERS",
      ["settings.custom.privacy"] =
        "Running a local model keeps every session fully offline.\nNo data leaves your machine. Ideal for confidential or high-value client work.",
      ["settings.custom.compat"] =
        "Register any number of OpenAI-compatible endpoints: local servers (Ollama, LM Studio, llama.cpp, vLLM) and online gateways (OpenRouter, Groq, Together AI, Mistral, etc.).",
      ["settings.custom.experimental"] =
        "Experimental feature. Not fully tuned, and cost estimates may be inaccurate.",
      ["settings.custom.add_provider"] = "+  Add Provider",
      ["settings.custom.add_provider.tooltip"] =
        "Configure a new OpenAI-compatible endpoint (local or hosted)",
      ["settings.custom.empty"] =
        "No custom providers yet. Click Add Provider above to point ReaAssist at a local model or an OpenAI-compatible gateway.",
      ["settings.custom.model_count.one"] = "{count} MODEL",
      ["settings.custom.model_count.many"] = "{count} MODELS",
      ["settings.custom.edit"] = "Edit",
      ["settings.custom.edit.tooltip"] =
        "Edit this provider's endpoint, models, and key",
      ["settings.custom.duplicate"] = "Duplicate",
      ["settings.custom.duplicate.tooltip"] =
        "Open a new provider form prefilled from this one (API key is not copied)",
      ["settings.custom.delete"] = "Delete",
      ["settings.custom.delete.tooltip"] =
        "Remove this provider (asks for confirmation)",
      ["settings.custom.delete.title"] = "Delete Provider",
      ["settings.custom.delete.fallback"] = "this provider",
      ["settings.custom.delete.prompt"] = "Delete \"{label}\"?",
      ["settings.custom.delete.body"] =
        "Removes the endpoint, models, and stored API key. This can't be undone.",
      ["settings.custom.delete.confirm"] = "Confirm",
      ["settings.custom.back"] = "Back",
      ["settings.custom.edit.subtitle"] =
        "Point ReaAssist at a local or custom model.",
      ["settings.custom.edit.breadcrumb"] = "LOCAL / CUSTOM LLM",
      ["settings.custom.size.heading"] =
        "Heads up: local model size matters for ReaAssist.",
      ["settings.custom.size.body1"] =
        "REAPER's ReaScript and JSFX APIs are a niche surface poorly represented in any model's pretraining. Small models (7-8B) will connect and produce code that looks right, but most replies will use fabricated function names or wrap real names around no-op logic. The API validator can't always catch this.",
      ["settings.custom.size.body2"] =
        "For usable results, use a code-specialized model with at least ~14B parameters (e.g. Qwen 2.5 Coder 14B at ~12 GB VRAM); 32B coders on 24 GB VRAM work substantially better. Below 14B, treat the connection as \"wired up correctly\" rather than \"ready to use.\"",
      ["settings.custom.status.new"] = "New Provider",
      ["settings.custom.status.editing"] = "Editing Provider",
      ["settings.custom.section.endpoint"] = "ENDPOINT",
      ["settings.custom.section.models"] = "MODELS",
      ["settings.custom.section.advanced"] = "ADVANCED",
      ["settings.custom.field.name"] = "Name",
      ["settings.custom.field.name_hint"] =
        "e.g. Ollama Local, OpenRouter, Groq",
      ["settings.custom.tip.name"] =
        "The friendly name shown in ReaAssist's provider dropdown and in the Custom Providers list on this page. This is purely cosmetic; rename it any time without affecting the saved endpoint, models, or API key. Required.\n\nTip: if you have several endpoints for the same service, include the variant in the name (e.g. 'Ollama - Llama 70B', 'OpenRouter - Free Tier').",
      ["settings.custom.field.endpoint"] = "Endpoint URL",
      ["settings.custom.field.endpoint_hint"] =
        "http://localhost:11434/v1/chat/completions",
      ["settings.custom.tip.endpoint"] =
        "The full URL of the chat completions endpoint, including http:// or https:// and the port.\n\nExpected shape for OpenAI-compatible servers:\n  http://localhost:11434/v1/chat/completions   (Ollama)\n  http://localhost:1234/v1/chat/completions    (LM Studio)\n  http://localhost:8080/v1/chat/completions    (llama.cpp)\n  https://openrouter.ai/api/v1/chat/completions (OpenRouter)\n\nUse the preset pills below to fill in the common defaults.",
      ["settings.custom.field.api_key"] = "API Key",
      ["settings.custom.field.api_key_suffix"] =
        "(optional, required for hosted gateways)",
      ["settings.custom.field.api_key_hint"] = "Paste API key...",
      ["settings.custom.tip.api_key"] =
        "The bearer token sent as 'Authorization: Bearer <key>' on every request.\n\nREQUIRED for hosted gateways: OpenRouter (sk-or-...), Groq (gsk_...), Together AI, Mistral, Fireworks, Anyscale, Cloudflare AI Gateway, etc.\n\nLEAVE BLANK for local servers (Ollama, LM Studio, llama.cpp, vLLM) that don't require auth. The Authorization header is omitted entirely in that case; some local servers reject a bare 'Bearer ' header, so empty really does mean empty.\n\nThe key is stored XOR-obfuscated and tied to this REAPER install path; copying the .ini to another machine won't work.",
      ["settings.custom.warning.unencrypted"] =
        "Unencrypted connection. Credentials sent in plain text.",
      ["settings.custom.preset.local"] = "LOCAL",
      ["settings.custom.preset.hosted"] = "HOSTED",
      ["settings.custom.tip.preset.ollama"] =
        "Fill in the default Ollama endpoint URL",
      ["settings.custom.tip.preset.lmstudio"] =
        "Fill in the default LM Studio endpoint URL",
      ["settings.custom.tip.preset.llamacpp"] =
        "Fill in the default llama.cpp server endpoint URL",
      ["settings.custom.tip.preset.openrouter"] =
        "Fill in the OpenRouter endpoint URL (API key required)",
      ["settings.custom.tip.preset.groq"] =
        "Fill in the Groq endpoint URL (API key required)",
      ["settings.custom.tip.preset.kimi"] =
        "Fill in Kimi (Moonshot) defaults:\n  - Endpoint: https://api.moonshot.ai/v1/chat/completions\n  - Provider name: Kimi (if blank)\n  - Model row: kimi-k2.6, 262k context, $0.95/$0.16/$4.00 per 1M\n  - Extra Body: {\"thinking\":{\"type\":\"disabled\"}}\n\nThinking is disabled by default because k2.6's reasoning pass adds tens of seconds of latency and thousands of hidden output tokens on simple tasks. Open the model row's Details popup to re-enable it (set the Extra Body to {\"thinking\":{\"type\":\"enabled\"}} or blank) when you need deeper reasoning.\n\nAPI key required. If you've already customized the default model row, only the URL and provider name are filled.",
      ["settings.custom.section.models_hint"] =
        "One row per model. Open Details to set prices, context, notes, and extra body JSON.",
      ["settings.custom.header.model_id"] = "MODEL IDENTIFIER",
      ["settings.custom.header.notes"] = "NOTES",
      ["settings.custom.tip.header.model_id"] =
        "The model name as your server expects it (e.g. qwen2.5-coder-14b, kimi-k2.6, claude-opus-4-8). Open Details to set prices, context, the same notes tag shown next to it, and extra JSON body fields.",
      ["settings.custom.tip.header.notes"] =
        "Optional short tag appended to the model id in the main-screen model dropdown, so rows that share an id but differ in tuning (thinking on/off, temperature, etc.) are distinguishable at a glance.",
      ["settings.custom.field.model_id_hint"] = "qwen2.5-coder-14b",
      ["settings.custom.field.notes_hint"] = "thinking, fast...",
      ["settings.custom.tip.notes"] =
        "Short free-text label appended to the model id in the main-screen model dropdown so rows that share a model id but differ in tuning are distinguishable at a glance.\n\nExamples: thinking, fast, creative, deterministic, long-ctx.\n\nMax {count} characters. No pipes (|), tabs, or newlines.",
      ["settings.custom.details.title"] = "Model Details",
      ["settings.custom.details.unnamed"] = "(unnamed model)",
      ["settings.custom.details.dropdown_notes"] = "Dropdown Notes",
      ["settings.custom.details.optional_max"] =
        "(optional, max {count} chars)",
      ["settings.custom.details.notes_hint"] =
        "thinking, fast, creative...",
      ["settings.custom.details.price_in"] =
        "Input Price per 1M (Cache Miss)",
      ["settings.custom.details.price_cache"] =
        "Input Price per 1M (Cache Hit)",
      ["settings.custom.details.price_out"] = "Output Price per 1M",
      ["settings.custom.details.context_window"] =
        "Context Window (tokens)",
      ["settings.custom.details.extra_body"] = "Extra Body JSON",
      ["settings.custom.details.extra_body_suffix"] =
        "(optional, merged into the chat-completions request body)",
      ["settings.custom.details.done"] = "Done",
      ["settings.custom.details.summary"] =
        "Details - prices, context, notes, extra body JSON",
      ["settings.custom.details.price_summary"] =
        "${input} in / ${cache} cached / ${output} out per 1M tokens",
      ["settings.custom.details.context_summary"] =
        "Context: {tokens} tokens",
      ["settings.custom.details.dropdown_notes_summary"] =
        "Dropdown notes: {notes}",
      ["settings.custom.details.cache_price_summary"] =
        "Cache-hit price: ${price}",
      ["settings.custom.details.extra_body_summary"] =
        "Extra body: {body}",
      ["settings.custom.details.extra_body_none"] =
        "Extra body: (none)",
      ["settings.custom.tip.details.notes"] =
        "Short free-text label appended to the model id in the main-screen model dropdown so rows that share a model id but differ in tuning are distinguishable at a glance.\n\nExamples: thinking, fast, creative, deterministic, long-ctx.\n\nMax {count} characters. No pipes (|), tabs, or newlines.\n\nMirrors the Notes input on the row - editing either updates the other.",
      ["settings.custom.tip.details.price_in"] =
        "Cost per million input tokens for fresh (non-cached) prompt content. Used for cost estimates only; the script does not bill you.",
      ["settings.custom.tip.details.price_cache"] =
        "Cost per million input tokens that the provider served from its automatic prompt cache (reported as usage.prompt_tokens_details.cached_tokens). Common providers and their published cache-hit rates: OpenAI ~10% of input, Kimi ~17% ($0.16 vs $0.95). Leave at 0 for endpoints without caching or unknown rates; cached tokens will then be billed at $0 in the cost estimate.",
      ["settings.custom.tip.details.price_out"] =
        "Cost per million output tokens. For reasoning models this usually includes hidden thinking tokens as part of the completion, so a long thinking pass charges at the output rate even when the visible reply is short.",
      ["settings.custom.tip.details.context_window"] =
        "Maximum combined input + output token capacity for this model. The preflight check warns if a pending send would overflow this window. Kimi k2.6 = 262144, Claude Opus 4.8 = 1000000, most local 8B models = 8192.",
      ["settings.custom.tip.details.extra_body"] =
        "A JSON object merged into the outgoing chat-completions body. Overrides any same-named keys set in the provider-level Extra Body field. Use for vendor-specific knobs that don't map to the OpenAI schema.\n\nExamples:\n  Kimi, GLM:        {\"thinking\":{\"type\":\"disabled\"}}\n  Qwen3:            {\"enable_thinking\":false}\n  OpenRouter:       {\"reasoning\":{\"effort\":\"high\"}}\n  LiteLLM-Anthropic: {\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":1024}}\n  Any OpenAI-compat: {\"temperature\":0.3,\"top_p\":0.9}\n\nMust be a valid JSON object (wrapped in {...}), not an array or scalar. Validated on Save.",
      ["settings.custom.tip.duplicate_model"] = "Duplicate this model row",
      ["settings.custom.tip.remove_model"] = "Remove this model row",
      ["settings.custom.add_model"] = "+  Add Model",
      ["settings.custom.add_model.tooltip"] =
        "Add another model row for this endpoint",
      ["settings.custom.model.too_small"] =
        "~{size}B detected - usually too small for reliable REAPER output.",
      ["settings.custom.field.request_timeout"] = "Request Timeout",
      ["settings.custom.field.seconds_suffix"] = "(seconds)",
      ["settings.custom.field.connect_timeout"] = "Connect Timeout",
      ["settings.custom.field.model_prefix"] = "Model ID Prefix",
      ["settings.custom.field.optional_suffix"] = "(optional)",
      ["settings.custom.field.model_prefix_hint"] =
        "e.g. openrouter/anthropic/   or   ollama/",
      ["settings.custom.field.headers"] = "Extra HTTP Headers",
      ["settings.custom.field.headers_suffix"] =
        "(one \"Name: value\" per line)",
      ["settings.custom.field.extra_body_provider"] = "Extra Body JSON",
      ["settings.custom.field.extra_body_provider_suffix"] =
        "(optional, applies to every request)",
      ["settings.custom.field.skip_tls"] = "Skip TLS Verification",
      ["settings.custom.warning.tls_disabled"] =
        "TLS verification disabled. Credentials can be intercepted. Only keep this on for trusted endpoints.",
      ["settings.custom.tip.request_timeout"] =
        "The total time allowed for a request once the connection is established, in seconds. Passed to curl as --max-time.\n\nCloud endpoints usually reply in 2-15s. Local LLMs can take MINUTES on a single prompt because the whole context has to be re-processed each turn on consumer hardware; default 600 (10 min) is a comfortable ceiling for most setups.\n\nRange: 10-3600 seconds (1 hour max). If your server replies correctly but ReaAssist gives up too early, raise this.",
      ["settings.custom.tip.connect_timeout"] =
        "The time allowed for the initial TCP connection and (for https) the TLS handshake, in seconds. Passed to curl as --connect-timeout.\n\nIndependent of Request Timeout: once the connection is up, the overall request timeout takes over. A short connect timeout fails fast when the server is unreachable or the port is wrong, instead of waiting the full Request Timeout.\n\nRange: 1-60 seconds. Default 10 is fine for localhost and most cloud gateways; raise it for slow CDNs or congested networks.",
      ["settings.custom.tip.model_prefix"] =
        "A string prepended to every model id just before the request is sent. The dropdown in ReaAssist shows the un-prefixed id, so the prefix lives in exactly one place instead of being typed into every model row.\n\nWhen to use this:\n  - OpenRouter routes via provider/model, e.g. 'anthropic/claude-3.5-sonnet'. Set prefix to 'anthropic/' and enter 'claude-3.5-sonnet' in the model row.\n  - LiteLLM gateways use 'ollama/<model>' or 'openrouter/...' to choose the backend.\n  - Cloudflare Workers AI uses '@cf/<org>/<model>'.\n\nLeave blank if your endpoint takes the raw model id. Most setups (Ollama, LM Studio, llama.cpp, direct OpenAI API) do not need a prefix.",
      ["settings.custom.tip.headers"] =
        "Additional HTTP headers sent on every request to this provider. Enter one per line in 'Name: value' format.\n\nExamples:\n  OpenAI-Organization: org-abc123\n  HTTP-Referer: https://my-app.example\n  X-Title: ReaAssist\n  cf-aig-authorization: Bearer <cf-token>\n  api-key: <azure-key>\n\nDo NOT set Authorization here; use the API Key field above. ReaAssist builds the Authorization header itself so your key stays off the command line.\n\nCharacters not allowed inside a value: newlines, null bytes, and the triple-quote sequence \"\"\" (these would break the Windows curl command line).",
      ["settings.custom.tip.extra_body_provider"] =
        "A JSON object merged into every chat-completions request body on this provider, on top of the standard OpenAI-compatible payload (model, messages, max_completion_tokens).\n\nUse this for vendor-specific toggles that don't map to the OpenAI schema. Per-model Extra Body JSON (in each model row's Details popup) overrides same-named keys here.\n\nExamples:\n  Kimi / GLM (disable reasoning):\n    {\"thinking\":{\"type\":\"disabled\"}}\n  Qwen3 (disable thinking):\n    {\"enable_thinking\":false}\n  OpenRouter (high reasoning effort):\n    {\"reasoning\":{\"effort\":\"high\"}}\n  LiteLLM proxy to Anthropic (budget-limited thinking):\n    {\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":1024}}\n  Any OpenAI-compat (sampling tweaks):\n    {\"temperature\":0.3,\"top_p\":0.9}\n\nMust be a valid JSON OBJECT wrapped in {...}, not an array or scalar. Validated and canonicalized on Save.",
      ["settings.custom.tip.skip_tls"] =
        "Adds curl --insecure, which skips the certificate-validity check for https:// endpoints. Only useful when the server presents a self-signed, expired, or otherwise un-trusted certificate and you know the endpoint is yours.\n\nTypical legit uses:\n  - Local LLM behind a homelab reverse-proxy with a self-signed cert.\n  - Corporate MITM gateway re-signing traffic with an internal CA you haven't installed.\n  - Dev/staging endpoint with an expired cert.\n\nNever enable for a public hosted gateway (OpenRouter, Groq, Together AI, etc.). If their cert stops validating, something is genuinely wrong and bypassing verification exposes your API key to any machine on the path.",
      ["settings.custom.status.testing"] =
        "Testing connection...  ({seconds}s remaining)",
      ["settings.custom.status.ok"] = "Connection OK. Server reachable.",
      ["settings.custom.status.failed"] = "Connection failed: {error}",
      ["settings.custom.test_inference"] =
        "Test with a real chat/completions request",
      ["settings.custom.tip.test_inference"] =
        "Off (default): GET /v1/models -- safe, free, instant. Verifies server reachable and auth header works.\n\nOn: POST /v1/chat/completions with max_tokens=1 and 'hi' against your first model. Exercises the same path real chat uses, but reasoning models (o1, Qwen reasoning variants, etc.) still run the full thinking phase -- you'll pay for one short inference call.",
      ["settings.custom.tip.cancel_test"] =
        "Cancel the in-flight connection test",
      ["settings.custom.tip.test_connection"] =
        "Test the endpoint and key against the current form values (no save required). Default: GET /v1/models. With the checkbox above ticked: real chat/completions POST.",
      ["settings.custom.action.cancel_test"] = "Cancel Test",
      ["settings.custom.action.test_connection"] = "Test Connection",
      ["settings.custom.toast.saved"] = "Provider saved",
      ["settings.custom.error.name_required"] = "Name is required.",
      ["settings.custom.error.endpoint_scheme"] =
        "Endpoint must start with http:// or https://.",
      ["settings.custom.error.endpoint_chars"] =
        "Endpoint may not contain quotes, backticks, or control characters.",
      ["settings.custom.error.endpoint_chat_completions"] =
        "Use the full chat-completions URL, for example http://localhost:1234/v1/chat/completions.",
      ["settings.custom.error.model_required"] =
        "At least one model with a non-empty identifier is required.",
      ["settings.custom.error.model_row_required"] =
        "Model Identifier is required for this row. Add an id, or click the trash icon to remove the row.",
      ["settings.custom.error.price_in"] =
        "Input price (cache miss) must be a number >= 0.",
      ["settings.custom.error.price_cache"] =
        "Cache-hit price must be a number >= 0.",
      ["settings.custom.error.price_out"] =
        "Output price must be a number >= 0.",
      ["settings.custom.error.context_window_min"] =
        "Context window must be a number >= {min}.",
      ["settings.custom.error.notes_max"] =
        "Notes must be {count} characters or fewer.",
      ["settings.custom.error.notes_chars"] =
        "Notes cannot contain pipe (|), tab, or newline characters.",
      ["settings.custom.error.details_reopen"] =
        "Details has errors - reopen to fix.",
      ["settings.custom.error.timeout_min"] =
        "Timeout must be a number >= {min} seconds.",
      ["settings.custom.error.timeout_max"] =
        "Timeout must be <= {max} seconds (1 hour).",
      ["settings.custom.error.connect_timeout_range"] =
        "Connect timeout must be a number between {min} and {max} seconds.",
      ["settings.custom.error.register_failed"] =
        "Could not register custom provider.",
      ["settings.custom.error.watchdog"] =
        "No response from server (client watchdog fired).",
      ["settings.custom.error.endpoint_unexpected_probe"] =
        "Endpoint reachable but {probe} returned an unexpected response.",
      ["settings.custom.error.header_unsafe"] =
        "Line {line} contains a newline, null byte, or triple-quote that can't be sent safely. Remove those characters.",
      ["settings.custom.error.header_format"] =
        "Line {line} is not in \"Name: value\" format. Each header must have a name, a colon, and a value.",
      ["settings.custom.error.header_auth"] =
        "Line {line}: use the API Key field for Authorization; don't set it here.",
      ["settings.custom.error.extra_body_json"] =
        "Not valid JSON: {error}",
      ["settings.custom.error.extra_body_object"] =
        "Must be a JSON object like {\"thinking\":{\"type\":\"disabled\"}}",
      ["settings.custom.error.extra_body_null"] =
        "Must be a JSON object, got null",
      ["settings.custom.error.extra_body_array"] =
        "Must be a JSON object, got an array",
      ["settings.custom.error.extra_body_canonicalize"] =
        "Failed to canonicalize: {error}",
      ["settings.custom.error.inference_model_required"] =
        "Add at least one model id before running an inference test.",
      ["settings.custom.error.response_timeout"] =
        "Timed out waiting for response.",
      ["settings.custom.status.cancelled"] = "Test cancelled.",
      ["settings.pref_plugins.subtitle"] =
        "Set default plugins used for each task.",
      ["settings.pref_plugins.breadcrumb"] = "PREFERRED PLUGINS",
      ["settings.pref_plugins.intro"] =
        "Set your preferred plugins so you can ask for an 'Equalizer' or 'compressor' without naming a specific one. ReaAssist inserts your pick automatically.",
      ["settings.pref_plugins.body"] =
        "Enter the plugin name exactly as it appears in your FX Browser (e.g. 'Pro-Q 4' or 'FabFilter Pro-Q 4'). Aliases let the model match alternate names you might use when asking for a plugin (e.g. 'eq' for Equalizer, 'comp' for Compressor). Leave blank for types you don't need.",
      ["settings.pref_plugins.section.mappings"] = "PLUGIN MAPPINGS",
      ["settings.pref_plugins.header.type"] = "TYPE",
      ["settings.pref_plugins.header.aliases"] = "ALIASES",
      ["settings.pref_plugins.header.plugin_name"] = "PLUGIN NAME",
      ["settings.pref_plugins.hint.type"] = "Type",
      ["settings.pref_plugins.hint.aliases"] = "comma-separated",
      ["settings.pref_plugins.hint.plugin_name"] = "Plugin name",
      ["settings.pref_plugins.type.eq"] = "Equalizer",
      ["settings.pref_plugins.type.compressor"] = "Compressor",
      ["settings.pref_plugins.type.multiband_compressor"] =
        "Multiband Compressor",
      ["settings.pref_plugins.type.reverb"] = "Reverb",
      ["settings.pref_plugins.type.delay"] = "Delay",
      ["settings.pref_plugins.type.synth"] = "Synthesizer",
      ["settings.pref_plugins.type.saturation"] = "Saturation",
      ["settings.pref_plugins.type.deesser"] = "De-esser",
      ["settings.pref_plugins.type.pitch_correction"] = "Pitch Correction",
      ["settings.pref_plugins.type.limiter"] = "Limiter",
      ["settings.pref_plugins.type.gate"] = "Gate",
      ["settings.pref_plugins.type.chorus"] = "Chorus",
      ["settings.pref_plugins.type.phaser"] = "Phaser",
      ["settings.pref_plugins.type.pitch_shift"] = "Pitch Shift",
      ["settings.pref_plugins.add_row"] = "+  Add Row",
      ["settings.pref_plugins.add_row.tooltip"] =
        "Add a blank row for a custom plugin type",
      ["settings.pref_plugins.rescan.tooltip"] = "Rescan this plugin",
      ["settings.pref_plugins.rescan.curated_tooltip"] =
        "Curated reference used. Rescan not needed. Plugin params are documented in Plugin_Ref.md and injected directly when this type is mentioned.",
      ["settings.pref_plugins.toast.fill_first"] =
        "Fill in type and plugin name first",
      ["settings.pref_plugins.toast.no_match"] =
        "\"{name}\" doesn't match an installed plugin",
      ["settings.pref_plugins.toast.save_failed"] =
        "Save failed: {error}",
      ["settings.pref_plugins.toast.save_failed_short"] = "Save failed",
      ["settings.pref_plugins.toast.saved"] = "Preferences saved",
      ["settings.pref_plugins.toast.no_matches"] =
        "No matching plugins found",
      ["settings.pref_plugins.toast.scan_failed_track"] =
        "Scan failed: couldn't create temp track",
      ["settings.pref_plugins.toast.scan_failed_lost"] =
        "Scan failed: temp track lost",
      ["settings.pref_plugins.toast.saved_skipped"] =
        "Saved ({count} skipped: {preview}{more})",
      ["settings.pref_plugins.toast.more"] = ", +{count} more",
      ["settings.pref_plugins.status.scanning"] = "Scanning parameters...",
      ["settings.pref_plugins.action.rescan_all"] = "Rescan All",
      ["settings.pref_plugins.action.rescan_all.tooltip"] =
        "Force a full re-scan of every configured row, even ones already cached",
      ["settings.pref_plugins.action.clear_all"] = "Clear All",
      ["settings.pref_plugins.clear.title"] = "Confirm Clear Preferred",
      ["settings.pref_plugins.clear.prompt"] =
        "Clear all preferred plugins?",
      ["settings.pref_plugins.clear.body"] =
        "Cached parameter data will be kept.",
      ["settings.pref_plugins.clear.toast"] =
        "Preferred plugins cleared",
      ["settings.fx_cache.subtitle"] = "Cached plugin parameter data.",
      ["settings.fx_cache.breadcrumb"] = "FX PARAM CACHE",
      ["settings.fx_cache.desc.cache"] =
        "Plugins are cached on first inspection for instant reuse.",
      ["settings.fx_cache.desc.rescan"] =
        "Rescan a plugin after an update changes its parameters.",
      ["settings.fx_cache.section.scanned"] = "SCANNED PLUGINS",
      ["settings.fx_cache.empty"] =
        "No plugins cached yet. Use fx_inspect or Preferred Plugins to populate.",
      ["settings.fx_cache.count.one"] = "{count} plugin",
      ["settings.fx_cache.count.many"] = "{count} plugins",
      ["settings.fx_cache.action.rescan_all"] = "Rescan All",
      ["settings.fx_cache.action.rescan_all.tooltip"] =
        "Shallow-rescan every plugin listed below, one at a time",
      ["settings.fx_cache.action.clear_all"] = "Clear All",
      ["settings.fx_cache.action.clear_all.tooltip"] =
        "Remove every cached plugin's parameter data. Re-scans on next use.",
      ["settings.fx_cache.progress.rescanning"] =
        "Rescanning {index} / {total}...",
      ["settings.fx_cache.action.cancel"] = "Cancel",
      ["settings.fx_cache.action.cancel_batch.tooltip"] =
        "Stop after the currently-scanning plugin finishes (canceling mid-scan could leave an orphan temp track)",
      ["settings.fx_cache.param_count"] = "{count} params",
      ["settings.fx_cache.param_count.needs_deep"] =
        "{count} params  |  needs deep scan",
      ["settings.fx_cache.action.rescan"] = "Rescan",
      ["settings.fx_cache.action.rescan.tooltip"] =
        "Quick rescan of this plugin (shallow read)",
      ["settings.fx_cache.action.deep"] = "Deep",
      ["settings.fx_cache.action.deep.tooltip"] =
        "Defer-paced deep scan (seconds). Use for VST3 plugins where a normal rescan returns garbage enum/range data (readback-lag plugins like Soundtoys).",
      ["settings.fx_cache.action.remove"] = "Remove",
      ["settings.fx_cache.action.remove.tooltip"] =
        "Delete this plugin's cached parameter data",
      ["settings.fx_cache.deep.scanning"] =
        "Deep scanning {identifier}...",
      ["settings.fx_cache.deep.body1"] =
        "Deep scan reads parameters with a per-probe delay to handle plugins that report values one frame late.",
      ["settings.fx_cache.deep.body2"] =
        "Runs once. Future requests will be instant.",
      ["settings.fx_cache.deep.probing"] =
        "Probing {done}/{total} ({percent}%)",
      ["settings.fx_cache.confirm_rescan.title"] = "Confirm Rescan All",
      ["settings.fx_cache.confirm_rescan.prompt"] =
        "Rescan all {count} cached plugins?",
      ["settings.fx_cache.confirm_rescan.body"] =
        "Takes roughly 1-2 seconds per plugin.",
      ["settings.fx_cache.confirm_rescan.body_cancel"] =
        "You can cancel anytime during the batch.",
      ["settings.fx_cache.confirm_clear.title"] = "Confirm Clear Cache",
      ["settings.fx_cache.confirm_clear.prompt"] =
        "Remove all cached plugin data?",
      ["settings.fx_cache.confirm_clear.body"] =
        "Plugins will be re-scanned on next use.",
      ["settings.fx_cache.section.builtin"] = "BUILT-IN REFERENCES",
      ["settings.fx_cache.builtin.label"] = "Built-in reference",
      ["settings.fx_cache.builtin.tooltip"] =
        "Curated parameter docs live in Resources/Plugin_Ref.md. The assistant uses those directly. No scan needed and none can be triggered.",
      ["settings.fx_cache.status.failed_temp_track"] =
        "Failed to create temporary track.",
      ["settings.fx_cache.toast.rescan_failed"] = "Rescan failed",
      ["settings.fx_cache.status.failed_load"] =
        "Failed to load: {identifier}",
      ["settings.fx_cache.toast.failed_load"] = "Failed to load plugin",
      ["settings.fx_cache.status.deep_scanning"] = "Deep scanning...",
      ["settings.fx_cache.status.scanning"] = "Scanning...",
      ["settings.fx_cache.status.deep_rescanned"] =
        "Deep rescanned: {identifier}",
      ["settings.fx_cache.toast.deep_complete"] =
        "Deep rescan complete",
      ["settings.fx_cache.status.deep_cancelled"] =
        "Deep rescan cancelled: {identifier}",
      ["settings.fx_cache.toast.deep_cancelled"] =
        "Deep rescan cancelled",
      ["settings.fx_cache.status.deep_failed"] =
        "Deep rescan failed: {reason}",
      ["settings.fx_cache.toast.deep_failed"] = "Deep rescan failed",
      ["settings.fx_cache.status.rescan_lost"] =
        "Rescan failed: temp track lost.",
      ["settings.fx_cache.status.rescan_error"] =
        "Rescan failed: scan threw an error.",
      ["settings.fx_cache.status.rescanned"] =
        "Rescanned: {identifier}",
      ["settings.fx_cache.toast.rescan_complete"] = "Rescan complete",
      ["settings.fx_cache.toast.rescan_all_done"] =
        "Rescanned {succeeded}/{total}.",
      ["settings.fx_cache.toast.rescan_all_failed_suffix"] =
        " {count} failed (missing plugins).",
      ["settings.fx_cache.toast.rescan_cancelled"] =
        "Rescan cancelled at {done}/{total}.",
      ["settings.pref.update_check.label"] = "Check for updates on startup",
      ["settings.pref.update_check.tooltip"] =
        "Automatically check for new ReaAssist versions when the script starts",
      ["settings.pref.auto_backup.label"] = "Auto-backup session",
      ["settings.pref.auto_backup.tooltip"] =
        "Save a timestamped .rpp-bak before Auto-Run executes returned code",
      ["settings.pref.theme.label"] = "Theme",
      ["settings.pref.theme.auto"] = "Auto",
      ["settings.pref.theme.dark"] = "Dark",
      ["settings.pref.theme.light"] = "Light",
      ["settings.pref.theme.tooltip"] =
        "Color theme: Auto follows your OS dark/light mode setting",
      ["settings.pref.ui_scale.label"] = "UI Scale",
      ["settings.pref.ui_scale.tooltip"] =
        "Scale the entire interface (clamped to your monitor size)",
      ["settings.pref.chat_font.label"] = "Chat Font",
      ["settings.pref.chat_font.small"] = "Small",
      ["settings.pref.chat_font.medium"] = "Medium",
      ["settings.pref.chat_font.large"] = "Large",
      ["settings.pref.chat_font.tooltip"] =
        "Font size for chat messages only (does not affect the rest of the UI)",
      ["settings.pref.preferred_plugins.label"] = "Preferred Plugins",
      ["settings.pref.preferred_plugins.tooltip"] =
        "Set default plugins for each type (EQ, compressor, reverb, etc.)",
      ["settings.custom_instructions.desc"] =
        "Use this for stable personal preferences: preferred plugins, naming "
        .. "habits, project conventions, and things you often have to repeat. "
        .. "Think of it like an AGENTS.md or CLAUDE.md file for ReaAssist. "
        .. "When enabled, this text will be sent to the model with every request.",
      ["settings.custom_instructions.error.save_pref"] =
        "Could not save the Custom Instructions toggle.",
      ["settings.custom_instructions.unsaved_enabled"] =
        "Unsaved text. Save to apply it.",
      ["settings.pref.check_updates.label"] = "Check for Updates",
      ["settings.pref.check_updates.tooltip"] =
        "Check now for a newer ReaAssist release or missing files",
      ["settings.adv.snapshot.label"] =
        "Send session snapshot with each message",
      ["settings.adv.snapshot.tooltip"] =
        "Attach a live snapshot of your project (tracks, FX, tempo, markers, etc.) with every message",
      ["settings.adv.api_ref.label"] =
        "Always include REAPER API reference",
      ["settings.adv.api_ref.tooltip"] =
        "Pin the REAPER Lua API reference to every request instead of letting the model fetch it on-demand. On = zero round-trips but ~10K extra tokens every turn. Off = saves tokens on non-code turns; the model fetches docs when it needs them.",
      ["settings.adv.diagnostics.label"] = "Automatic diagnostics",
      ["settings.adv.diagnostics.off"] = "Off",
      ["settings.adv.diagnostics.basic"] = "Basic",
      ["settings.adv.diagnostics.extended"] = "Extended",
      ["settings.adv.diagnostics.tooltip"] =
        "Basic anonymous diagnostics are enabled by default and can be turned off. Extended adds redacted chat, diagnostics, and log/report detail. Sent on the next launch, never during an active request.",
      ["settings.adv.cloud_timeout.label"] = "Cloud Timeout",
      ["settings.adv.cloud_timeout.tooltip"] =
        "How long to wait for a Claude/ChatGPT/Gemini response before timing out. Default 180s. Reasoning models on large prompts may need 300+",
      ["settings.adv.fx_cache.label"] = "FX Param Cache",
      ["settings.adv.fx_cache.tooltip"] =
        "View, rescan, or remove cached plugin parameter data. Curated plugins are listed as read-only reference entries.",
      ["settings.adv.reset_window.label"] = "Reset Window Size",
      ["settings.adv.reset_window.tooltip"] =
        "Reset window to default size and clear saved position",
      ["settings.adv.factory_reset.label"] = "Factory Reset",
      ["settings.adv.factory_reset.tooltip"] =
        "Clear all keys, preferences, and settings to start fresh",
      ["settings.factory_reset.complete"] =
        "Reset complete. Close and reopen ReaAssist to finish.",
      ["settings.factory_reset.heading"] = "Delete all ReaAssist data?",
      ["settings.factory_reset.body"] =
        "This deletes settings, API keys, custom providers, feedback identity, logs, caches, and local Data files. ReaAssist will relaunch and start like a new install.",
      ["settings.diag.popup.title"] = "Enable Diagnostics",
      ["settings.diag.popup.next_launch"] =
        "{tier} diagnostics are sent on the next launch, when ReaAssist is idle.",
      ["settings.diag.popup.extended_body"] =
        "Extended includes Basic metrics plus redacted chat, diagnostics, recent errors, and redacted Advanced Log/report detail.",
      ["settings.diag.popup.basic_body"] =
        "Basic includes anonymous structured metrics only: counts, providers, model tiers, tokens, cache, latency, and outcomes.",
      ["settings.diag.popup.enable"] = "Enable {tier}",
      ["settings.unsaved.popup.title"] = "Unsaved Changes",
      ["settings.unsaved.prompt"] =
        "You have unsaved changes. Save before leaving?",
      ["settings.footer.unsaved"] = "Unsaved changes",
      ["settings.footer.cancel_tooltip"] =
        "Discard changes and return to chat  (Esc)",
      ["settings.footer.save_disabled_validating"] =
        "Key validation in progress...",
      ["settings.footer.save_disabled_need_key"] =
        "Enter at least one API key to save",
      ["settings.footer.save_tooltip"] = "Save all staged changes  (Enter)",
      ["settings.footer.save_continue"] = "Save & Continue",
      ["settings.footer.save_continue_tooltip"] =
        "Save your key(s) and continue to ReaAssist  (Enter)",
      ["settings.footer.help_tooltip"] =
        "Open the Help & Tips page (includes Report a Bug and Credits)",
      ["local.footer.free_reply"] = "ReaAssist local free reply.",
      ["local.footer.ask_provider_instead"] = "Ask {provider} instead.",
      ["local.footer.ask_provider_tooltip"] =
        "Send the same prompt to the selected provider.",
      ["local.tempo"] = "Tempo: {bpm} BPM | Time Signature: {num}/{denom}",
    },
  },
}

I18N.PACK_SCHEMA = 1
I18N.MAX_INDEX_BYTES = 128 * 1024
I18N.MAX_UI_PACK_BYTES = 512 * 1024
I18N.MAX_HELP_PACK_BYTES = 512 * 1024
I18N.INDEX_URL = "https://reaassist.app/lang/v1/index.json"
I18N._cached_pack_miss = I18N._cached_pack_miss or {}
I18N._cached_help_miss = I18N._cached_help_miss or {}

function I18N._sep()
  if RA and RA.SEP then return RA.SEP end
  return package and package.config and package.config:sub(1, 1) or "/"
end

function I18N.lang_root_dir()
  if RA and RA.LANG_DIR then return RA.LANG_DIR end
  if RA and RA.DATA_DIR then return RA.DATA_DIR .. "Lang" .. I18N._sep() end
  return nil
end

function I18N.ui_pack_dir()
  if RA and RA.LANG_UI_DIR then return RA.LANG_UI_DIR end
  local root = I18N.lang_root_dir()
  return root and (root .. "ui" .. I18N._sep()) or nil
end

function I18N.help_pack_dir()
  if RA and RA.LANG_HELP_DIR then return RA.LANG_HELP_DIR end
  local root = I18N.lang_root_dir()
  return root and (root .. "help" .. I18N._sep()) or nil
end

function I18N.font_pack_dir()
  if RA and RA.LANG_FONT_DIR then return RA.LANG_FONT_DIR end
  local root = I18N.lang_root_dir()
  return root and (root .. "fonts" .. I18N._sep()) or nil
end

function I18N.tmp_pack_dir()
  if RA and RA.LANG_TMP_DIR then return RA.LANG_TMP_DIR end
  local root = I18N.lang_root_dir()
  return root and (root .. "tmp" .. I18N._sep()) or nil
end

function I18N.index_path()
  local root = I18N.lang_root_dir()
  return root and (root .. "index.json") or nil
end

function I18N._safe_code(code)
  code = tostring(code or "")
  if code == "" or not code:match("^[%w][%w%-]*$") then return nil end
  return code
end

function I18N.ensure_cache_dirs()
  if not (reaper and reaper.RecursiveCreateDirectory) then return false end
  local root = I18N.lang_root_dir()
  local ui = I18N.ui_pack_dir()
  local help = I18N.help_pack_dir()
  local fonts = I18N.font_pack_dir()
  local tmp = I18N.tmp_pack_dir()
  if not (root and ui and help and fonts and tmp) then return false end
  reaper.RecursiveCreateDirectory(root, 0)
  reaper.RecursiveCreateDirectory(ui, 0)
  reaper.RecursiveCreateDirectory(help, 0)
  reaper.RecursiveCreateDirectory(fonts, 0)
  reaper.RecursiveCreateDirectory(tmp, 0)
  return true
end

function I18N.ensure_cache_dir(kind)
  if not (reaper and reaper.RecursiveCreateDirectory) then return false end
  kind = tostring(kind or "root")
  local dir
  if kind == "root" then
    dir = I18N.lang_root_dir()
  elseif kind == "ui" then
    dir = I18N.ui_pack_dir()
  elseif kind == "help" then
    dir = I18N.help_pack_dir()
  elseif kind == "fonts" then
    dir = I18N.font_pack_dir()
  elseif kind == "tmp" then
    dir = I18N.tmp_pack_dir()
  end
  if not dir then return false end
  reaper.RecursiveCreateDirectory(dir, 0)
  return true
end

function I18N.cached_ui_pack_path(code)
  code = I18N._safe_code(code)
  local dir = I18N.ui_pack_dir()
  if not (code and dir) then return nil end
  return dir .. code .. ".v" .. tostring(I18N.PACK_SCHEMA) .. ".json"
end

function I18N.cached_help_pack_path(code)
  code = I18N._safe_code(code)
  local dir = I18N.help_pack_dir()
  if not (code and dir) then return nil end
  return dir .. code .. ".v" .. tostring(I18N.PACK_SCHEMA) .. ".md"
end

function I18N._read_file_limited(path, max_bytes)
  if not (path and path ~= "") then return nil, "missing_path" end
  local f, err = io.open(path, "rb")
  if not f then return nil, err or "open_failed" end
  local size = f:seek("end") or 0
  if size > max_bytes then
    f:close()
    return nil, "oversize"
  end
  f:seek("set", 0)
  local raw = f:read("*a") or ""
  f:close()
  if #raw > max_bytes then return nil, "oversize" end
  return raw
end

function I18N._json_decode(raw)
  local decoder = RA and RA.JSON and RA.JSON.decode
  if not decoder and JSON and JSON.decode then decoder = JSON.decode end
  if not decoder then return nil, "json_unavailable" end
  local ok, data, err = pcall(decoder, raw)
  if not ok then return nil, data end
  if err then return nil, err end
  return data
end

function I18N._placeholders(text)
  local out = {}
  for name in tostring(text or ""):gmatch("{([%w_]+)}") do out[name] = true end
  return out
end

function I18N._placeholder_mismatch(source, translated)
  local src = I18N._placeholders(source)
  local dst = I18N._placeholders(translated)
  for name in pairs(src) do
    if not dst[name] then return name end
  end
  for name in pairs(dst) do
    if not src[name] then return name end
  end
  return nil
end

function I18N._version_parts(v)
  local out = {}
  for n in tostring(v or ""):gmatch("(%d+)") do out[#out + 1] = tonumber(n) or 0 end
  return out
end

function I18N._version_cmp(a, b)
  local av, bv = I18N._version_parts(a), I18N._version_parts(b)
  local n = (#av > #bv) and #av or #bv
  for i = 1, n do
    local ai, bi = av[i] or 0, bv[i] or 0
    if ai < bi then return -1 end
    if ai > bi then return 1 end
  end
  return 0
end

function I18N._app_compatible(meta)
  if type(meta) ~= "table" then return false end
  local current = tostring(CFG and CFG.VERSION or "0")
  if meta.app_min and I18N._version_cmp(current, meta.app_min) < 0 then
    return false
  end
  local app_max = tostring(meta.app_max or "")
  if app_max ~= "" then
    if app_max:match("^%d+%.x$") then
      local major = tonumber(current:match("^(%d+)")) or 0
      local wanted = tonumber(app_max:match("^(%d+)")) or -1
      if major ~= wanted then return false end
    elseif I18N._version_cmp(current, app_max) > 0 then
      return false
    end
  end
  return true
end

function I18N.parse_help_pack(raw, requested_code)
  requested_code = I18N._safe_code(requested_code)
  if not requested_code then return nil, "invalid_code" end
  if type(raw) ~= "string" then return nil, "raw_not_string" end
  if #raw > I18N.MAX_HELP_PACK_BYTES then return nil, "oversize" end
  local header, body = raw:match("^(RA_HELP_PACK.-)\r?\n\r?\n(.*)$")
  if not header or not body then return nil, "missing_header" end
  local meta = {}
  for line in header:gmatch("[^\r\n]+") do
    if line ~= "RA_HELP_PACK" then
      local key, value = line:match("^([%w_]+):%s*(.-)%s*$")
      if key then meta[key] = value end
    end
  end
  if tonumber(meta.schema) ~= I18N.PACK_SCHEMA then return nil, "unsupported_schema" end
  if tostring(meta.code or "") ~= requested_code then return nil, "wrong_code" end
  if meta.status ~= "complete" then return nil, "incomplete_pack" end
  if not I18N._app_compatible(meta) then return nil, "app_incompatible" end
  if not body:match("\n##%s+") and not body:match("^##%s+") then
    return nil, "missing_sections"
  end
  return body, meta
end

function I18N.load_cached_help_pack(code, opts)
  code = I18N._safe_code(code)
  if not code or code == I18N.fallback_code then return nil, "not_remote_code" end
  opts = type(opts) == "table" and opts or {}
  if I18N._cached_help_miss[code] and not opts.force then
    return nil, "cached_miss"
  end
  local path = I18N.cached_help_pack_path(code)
  local raw, read_err = I18N._read_file_limited(path, I18N.MAX_HELP_PACK_BYTES)
  if not raw then
    I18N._cached_help_miss[code] = true
    return nil, read_err or "read_failed"
  end
  local body, meta = I18N.parse_help_pack(raw, code)
  if not body then
    I18N._cached_help_miss[code] = true
    return nil, meta or "invalid_help_pack"
  end
  I18N._cached_help_miss[code] = nil
  return body, meta
end

function I18N.validate_ui_pack(doc, requested_code)
  requested_code = I18N._safe_code(requested_code)
  if not requested_code then return nil, "invalid_code" end
  if type(doc) ~= "table" then return nil, "pack_not_object" end
  if doc.schema ~= I18N.PACK_SCHEMA then return nil, "unsupported_schema" end
  if tostring(doc.code or "") ~= requested_code then return nil, "wrong_code" end
  if doc.status ~= "complete" then return nil, "incomplete_pack" end
  if CFG and CFG.is_valid_language_code
      and not CFG.is_valid_language_code(requested_code) then
    return nil, "unknown_language"
  end
  if type(doc.strings) ~= "table" then return nil, "strings_not_object" end
  local english = I18N.catalogs and I18N.catalogs[I18N.fallback_code]
  local english_strings = type(english) == "table" and english.strings or nil
  if type(english_strings) ~= "table" then return nil, "english_missing" end
  local strings = {}
  for key, value in pairs(doc.strings) do
    if type(key) ~= "string" or key == "" or key:sub(1, 1) == "_" then
      return nil, "invalid_key"
    end
    if type(value) ~= "string" then
      return nil, "invalid_value"
    end
    local source = english_strings[key]
    if source ~= nil then
      local missing = I18N._placeholder_mismatch(source, value)
      if missing then return nil, "placeholder_mismatch:" .. key end
    end
    strings[key] = value
  end
  return {
    _meta = {
      code = requested_code,
      status = "complete",
      schema = I18N.PACK_SCHEMA,
      source_version = tostring(doc.source_version or ""),
      remote = true,
    },
    strings = strings,
  }
end

function I18N.parse_ui_pack_json(raw, requested_code)
  if type(raw) ~= "string" then return nil, "raw_not_string" end
  if #raw > I18N.MAX_UI_PACK_BYTES then return nil, "oversize" end
  local doc, err = I18N._json_decode(raw)
  if not doc then return nil, err or "json_decode_failed" end
  return I18N.validate_ui_pack(doc, requested_code)
end

function I18N.load_cached_ui_pack(code, opts)
  code = I18N._safe_code(code)
  if not code or code == I18N.fallback_code or code == "qps-ploc" then
    return false, "not_remote_code"
  end
  opts = type(opts) == "table" and opts or {}
  if I18N.catalogs and I18N.catalogs[code] and not opts.force then
    return true, I18N.catalogs[code]
  end
  if I18N._cached_pack_miss[code] and not opts.force then
    return false, "cached_miss"
  end
  local path = I18N.cached_ui_pack_path(code)
  local raw, read_err = I18N._read_file_limited(path, I18N.MAX_UI_PACK_BYTES)
  if not raw then
    I18N._cached_pack_miss[code] = true
    return false, read_err or "read_failed"
  end
  local catalog, parse_err = I18N.parse_ui_pack_json(raw, code)
  if not catalog then
    I18N._cached_pack_miss[code] = true
    if Log and Log.line then
      Log.line("I18N", "cached UI pack rejected for " .. tostring(code)
        .. ": " .. tostring(parse_err))
    end
    return false, parse_err or "invalid_pack"
  end
  I18N.catalogs[code] = catalog
  I18N._cached_pack_miss[code] = nil
  return true, catalog
end

function I18N.load_cached_index(opts)
  opts = type(opts) == "table" and opts or {}
  if I18N.remote_index and not opts.force then return I18N.remote_index end
  local path = I18N.index_path()
  local raw, read_err = I18N._read_file_limited(path, I18N.MAX_INDEX_BYTES)
  if not raw then return nil, read_err or "read_failed" end
  local doc, err = I18N._json_decode(raw)
  if not doc then return nil, err or "json_decode_failed" end
  if type(doc) ~= "table" or doc.schema ~= I18N.PACK_SCHEMA
      or type(doc.languages) ~= "table" then
    return nil, "invalid_index"
  end
  I18N.remote_index = doc
  return doc
end

function I18N.load_catalog(code)
  code = tostring(code or "")
  local catalog = I18N.catalogs and I18N.catalogs[code]
  if catalog then return catalog end
  I18N.load_cached_ui_pack(code)
  return I18N.catalogs and I18N.catalogs[code]
end

function I18N.catalog_available(code)
  code = tostring(code or "")
  local catalog = I18N.load_catalog(code)
  if not catalog then return false end
  if code == "qps-ploc" then return true end
  local meta = type(catalog) == "table" and catalog._meta or nil
  return type(meta) == "table" and meta.status == "complete"
end

function I18N.lang_code()
  if type(prefs) == "table" then
    local pref_code = tostring(prefs.language_code or "")
    if pref_code == "qps-ploc" and I18N.catalog_available("qps-ploc") then
      return "qps-ploc"
    end
    if pref_code ~= "" then
      local valid_code = (CFG and CFG.is_valid_language_code
        and CFG.is_valid_language_code(pref_code))
        or I18N.load_catalog(pref_code) ~= nil
      if valid_code then
        if I18N.catalog_available(pref_code) then return pref_code end
        return I18N.fallback_code
      end
    end
    if CFG and CFG.language_code_for_legacy_idx then
      local code = CFG.language_code_for_legacy_idx(prefs.reply_language_idx)
      if code and I18N.catalog_available(code) then return code end
    end
  end
  return I18N.fallback_code
end

function I18N.set_language_code(code)
  code = tostring(code or "")
  if not I18N.catalog_available(code) then return false end
  I18N.active_code = code
  if type(prefs) == "table" then
    prefs.language_code = code
    if CFG and CFG.legacy_idx_for_language_code then
      prefs.reply_language_idx =
        CFG.legacy_idx_for_language_code(code) or prefs.reply_language_idx
    end
  end
  return true
end

function I18N.reload_language(code)
  if code ~= nil then I18N.set_language_code(code) end
  return I18N.load_catalog(I18N.lang_code())
end

function I18N.language_label(code)
  if CFG and CFG.language_label_for_code then
    return CFG.language_label_for_code(code or I18N.lang_code())
  end
  return tostring(code or I18N.lang_code())
end

function I18N.prompt_language_name(code)
  code = code or I18N.lang_code()
  if CFG and CFG.prompt_language_name then
    return CFG.prompt_language_name(code) or "English"
  end
  return code == "en" and "English" or tostring(code or "English")
end

function I18N.has_key(code, key)
  local catalog = I18N.load_catalog(code)
  local strings = type(catalog) == "table" and catalog.strings or nil
  return type(strings) == "table" and strings[tostring(key or "")] ~= nil
end

function I18N.interpolate(text, values)
  text = tostring(text or "")
  if type(values) ~= "table" then return text end
  return (text:gsub("{([%w_]+)}", function(name)
    local value = values[name]
    if value == nil then return "{" .. name .. "}" end
    return tostring(value)
  end))
end

I18N.local_overrides = I18N.local_overrides or {}
I18N.local_overrides.ja = {
    ["footer.credits.label"] = "クレジット",
    ["footer.donate.label"] = "寄付",
    ["footer.help.label"] = "ヘルプ",
    ["footer.help.tooltip"] = "ヘルプと使い方ガイドを表示",
    ["mode.off"] = "オフ",
    ["mode.on"] = "オン",
    ["common.undo"] = "元に戻す",
    ["typed_actions.status.auto_ran"] = "自動実行済み",
    ["typed_actions.status.failed"] = "失敗",
    ["typed_actions.status.undo_lua"] = "元に戻す + Lua",
    ["typed_actions.status.undo_sent"] = "元に戻しました",
    ["typed_actions.status.validated"] = "検証済み",
    ["typed_actions.undo.tooltip"] =
      "最後のREAPERアクションを元に戻す (Ctrl+Z)",
    ["typed_actions.undo_lua"] = "元に戻してLuaを依頼",
    ["typed_actions.undo_lua.tooltip"] =
      "この構造化編集を元に戻してから、Lua/ReaScript版を依頼します。自動実行は現在の設定に従います。",
}
I18N.local_overrides.ko = {
    ["footer.credits.label"] = "크레딧",
    ["footer.donate.label"] = "후원",
    ["footer.help.label"] = "도움말",
    ["footer.help.tooltip"] = "도움말과 사용 가이드 보기",
    ["mode.off"] = "끔",
    ["mode.on"] = "켬",
    ["common.undo"] = "실행 취소",
    ["typed_actions.status.auto_ran"] = "자동 실행됨",
    ["typed_actions.status.failed"] = "실패",
    ["typed_actions.status.undo_lua"] = "실행 취소 + Lua",
    ["typed_actions.status.undo_sent"] = "실행 취소됨",
    ["typed_actions.status.validated"] = "검증됨",
    ["typed_actions.undo.tooltip"] =
      "마지막 REAPER 동작 실행 취소 (Ctrl+Z)",
    ["typed_actions.undo_lua"] = "실행 취소 후 Lua 요청",
    ["typed_actions.undo_lua.tooltip"] =
      "이 구조화 편집을 실행 취소한 다음 Lua/ReaScript 버전을 요청합니다. 자동 실행은 현재 설정을 따릅니다.",
}
I18N.local_overrides.id = {
    ["common.run"] = "Jalankan",
    ["common.saved"] = "Tersimpan!",
    ["footer.version.unavailable"] =
      "Pemeriksaan pembaruan tidak tersedia dalam versi ini",
    ["local.footer.free_reply"] = "Balasan lokal ReaAssist gratis.",
    ["settings.adv.api_ref.label"] =
      "Selalu sertakan referensi REAPER API",
    ["settings.adv.api_ref.tooltip"] =
      "Sematkan referensi API Lua REAPER ke setiap permintaan, bukan membiarkan model mengambilnya saat diperlukan. Aktif = tanpa perjalanan tambahan, tetapi sekitar 10 ribu token ekstra setiap giliran. Nonaktif = hemat token pada giliran non-kode; model mengambil dokumentasi saat membutuhkannya.",
    ["settings.adv.cloud_timeout.label"] = "Batas waktu awan",
    ["settings.adv.diagnostics.tooltip"] =
      "Diagnostik anonim dasar aktif secara bawaan dan dapat dimatikan. Diperluas menambahkan obrolan, diagnostik, serta detail log/laporan yang disamarkan. Dikirim pada peluncuran berikutnya, tidak pernah saat permintaan aktif.",
    ["settings.adv.factory_reset.label"] = "Setel ulang pabrik",
    ["settings.adv.factory_reset.tooltip"] =
      "Hapus semua kunci, preferensi, dan pengaturan untuk memulai dari awal",
    ["settings.adv.fx_cache.label"] = "Tembolok parameter FX",
    ["settings.adv.fx_cache.tooltip"] =
      "Lihat, pindai ulang, atau hapus data parameter pengaya yang tersimpan. Pengaya kurasi ditampilkan sebagai entri referensi baca-saja.",
    ["settings.adv.reset_window.label"] = "Setel ulang ukuran jendela",
    ["settings.adv.reset_window.tooltip"] =
      "Kembalikan jendela ke ukuran bawaan dan hapus posisi tersimpan",
    ["settings.adv.snapshot.label"] =
      "Kirim cuplikan sesi bersama setiap pesan",
    ["settings.adv.snapshot.tooltip"] =
      "Lampirkan cuplikan langsung proyek Anda (trek, FX, tempo, penanda, dan lainnya) bersama setiap pesan",
    ["settings.footer.help_tooltip"] =
      "Buka halaman Bantuan & Tips (termasuk Laporkan Bug dan Kredit)",
    ["settings.footer.save_tooltip"] =
      "Simpan semua perubahan bertahap (Enter)",
    ["settings.hero.breadcrumb.first_run"] = "PENGATURAN AWAL",
    ["settings.hero.subtitle.first_run"] =
      "Tambahkan setidaknya satu kunci API untuk memulai.",
    ["settings.hero.subtitle.reentry"] =
      "Atur kunci API dan preferensi.",
    ["settings.pref.auto_backup.tooltip"] =
      "Simpan .rpp-bak bertanda waktu sebelum Auto-Run menjalankan kode yang dikembalikan",
    ["settings.pref.chat_font.label"] = "Fonta obrolan",
    ["settings.pref.chat_font.tooltip"] =
      "Ukuran fonta untuk pesan obrolan saja (tidak memengaruhi bagian antarmuka lainnya)",
    ["settings.pref.check_updates.label"] = "Periksa pembaruan",
    ["settings.pref.check_updates.tooltip"] =
      "Periksa sekarang apakah ada rilis ReaAssist baru atau berkas yang hilang",
    ["settings.pref.preferred_plugins.label"] = "Pengaya pilihan",
    ["settings.pref.preferred_plugins.tooltip"] =
      "Tetapkan pengaya bawaan untuk setiap jenis (EQ, kompresor, reverb, dan lainnya)",
    ["settings.pref.theme.light"] = "Terang",
    ["settings.pref.theme.tooltip"] =
      "Tema warna: Otomatis mengikuti pengaturan mode gelap/terang sistem operasi Anda",
    ["settings.pref.ui_scale.label"] = "Skala antarmuka",
    ["settings.pref.ui_scale.tooltip"] =
      "Skalakan seluruh antarmuka (dibatasi sesuai ukuran monitor Anda)",
    ["settings.pref.update_check.label"] =
      "Periksa pembaruan saat mulai",
    ["settings.pref.update_check.tooltip"] =
      "Periksa versi ReaAssist baru secara otomatis saat skrip dimulai",
}

do
  local options_labels = {
    bg = "Опции",
    cs = "Možnosti",
    da = "Valg",
    de = "Optionen",
    el = "Επιλογές",
    es = "Opciones",
    fi = "Valinnat",
    fr = "Options",
    hu = "Opciók",
    id = "Opsi",
    it = "Opzioni",
    ja = "オプション",
    ko = "옵션",
    mk = "Опции",
    nl = "Opties",
    no = "Valg",
    pl = "Opcje",
    pt = "Opções",
    ro = "Opțiuni",
    ru = "Опции",
    sk = "Možnosti",
    sr = "Опције",
    sv = "Alternativ",
    tr = "Seçenekler",
    uk = "Опції",
    vi = "Tùy chọn",
    ["zh-Hans"] = "选项",
    ["zh-Hant"] = "選項",
  }
  for code, label in pairs(options_labels) do
    I18N.local_overrides[code] = I18N.local_overrides[code] or {}
    I18N.local_overrides[code]["mode.options"] = label
  end
end

function I18N.t(key, values, opts)
  key = tostring(key or "")
  local code = type(opts) == "table" and opts.code or I18N.lang_code()
  local overrides = I18N.local_overrides and I18N.local_overrides[code]
  local text = type(overrides) == "table" and overrides[key] or nil
  if text ~= nil then return I18N.interpolate(text, values) end
  local catalog = I18N.load_catalog(code)
  local strings = type(catalog) == "table" and catalog.strings or nil
  text = type(strings) == "table" and strings[key] or nil
  if text == nil and code ~= I18N.fallback_code then
    catalog = I18N.load_catalog(I18N.fallback_code)
    strings = type(catalog) == "table" and catalog.strings or nil
    text = type(strings) == "table" and strings[key] or nil
  end
  if text == nil then text = key end
  return I18N.interpolate(text, values)
end

-- Remote language cache folders are created lazily so English-only installs
-- do not get an empty Data/Lang tree at startup.
I18N.load_cached_index()

_G.I18N = I18N
return I18N
