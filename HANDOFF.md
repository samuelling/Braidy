# Handoff: Sidekick → Braidy (continue on the Mac mini)

You're picking up an iPad/iPhone app in progress for Sam Ling. Read this whole file before changing anything. Sam communicates efficiently and wants mechanistic, honest answers. He's a parent first here: usability for other parents is the top priority.

## What the app is

A camera-based reader for kids who can't read yet. Prop an iPad (or iPhone) facing the TV or a handheld. The app reads each new dialogue box aloud as it appears in any game (Zelda, Pokémon, Mario…), giving each character a voice that fits. Consoles' own screen readers (Switch 2 included) only read system menus, never in-game text, so this works from the outside, through the camera.

It was built for Sam's 5-year-old, Everett. It runs on Everett's iPad, which shows in Xcode as **"iPad (2)"** (iPadOS 26.5.2, Developer Mode on). It's currently named **Sidekick**. Before that it was Navi, which was dropped because of Nintendo trademark risk.

## Where the code is

- **Repo:** git, 8 commits. The latest is `d74fadf Optional ElevenLabs voices`, plus this handoff file.
  - On Sam's MacBook at `~/Sidekick`.
  - Also as `braidy-repo.tgz`, sent in the chat with this file.
  - There's no GitHub repo yet. The plan is **samuelling/Braidy** (see task 8).
- **Xcode project:** `Sidekick.xcodeproj`, objectVersion 77 with file-system-synchronized groups, so any new `.swift` file in `Sidekick/` is picked up automatically. Team `Y4HDFDP479`, bundle ID `com.samuelling.sidekick`, iOS 17+, device family iPhone + iPad, Swift 5 with minimal strict concurrency. It builds with no warnings except Xcode's "Update to recommended settings". There's a GitHub Actions compile check in `.github/workflows/build.yml`.
- **The cloud session couldn't create the GitHub repo:** the automated permission check blocked it, both via `gh` and by clicking in GitHub's web UI. Sam has to click **Create repository** himself, or do it from his own terminal.

## What works today (verified on the iPad)

| Area | Status |
|---|---|
| Camera → Vision OCR inside a draggable **reading box**, remembered per game | Working on device |
| Waits for typewriter text to settle (3 matching reads), speaks each box once, speaks only new words if a line continues, forgets after ~3 s blank | Built; tuned by reasoning, not yet by real play |
| **Layout-aware reading order**: fragments → lines (horizontally close) → blocks (stacked, overlapping); blocks read left→right, each top→bottom, with a pause between. Fixes Zelda choices being read before the dialogue | Built after Sam reported the bug; awaiting his confirmation |
| Speaker name label detection → per-character voice | Built |
| **Voiced-cutscene detection**: SoundAnalysis speech classifier; a settled subtitle waits 0.7 s and is shown but not spoken if ≥ ~0.75 s of game speech was heard from 1.5 s before it settled. Mic ignored while the app itself speaks | Built (Switch 2 Zelda editions mix voiced and unvoiced lines) |
| Apple TTS with per-character voice, softened pitch/speed (extremes sounded robotic), game-word respellings, "Use the best voices" | Working; Sam found the default compact voices robotic |
| **ElevenLabs** (user's own key, Keychain): loads the account's voices, picks a narrator, casts characters by gender/age, per-character override, Flash (half price) or v4, **on-device audio cache** (each line paid once), characters-this-month counter, falls back to Apple TTS on any error | **Working in the app with Sam's key** |
| **Claude** (user's own API key, Keychain): platform-first game picker (Switch 2 / Switch / PS5 / Xbox / PC / iPad / other) → search with Claude + web search → green "best match" card; popular games per platform; identify the game from a camera frame; cast lookup (gender, species, age, pitch, rate, pronunciation) + up to 80 game words for OCR and speech | Built; Sam has used the picker |

Key files: `CameraModel` (capture, OCR, layout assembly), `DialogueTracker`, `SpeakerParser`, `VoiceListener`, `Cast`, `ClaudeClient` (+Keychain), `ElevenLabs` (client, cache, casting), `Speaker` (both engines), `Reader` (orchestration and settings), `ContentView`, `CameraStage`, `SettingsView`, `GamePicker`.

## API facts already verified (Nov 2026)

- **Claude:**
  - Endpoint and model: `POST https://api.anthropic.com/v1/messages`, model `claude-sonnet-5-5`, header `anthropic-version: 2023-06-01`.
  - Web search tool: `{"type":"web_search_20260318","name":"web_search","max_uses":5}`. Handle `stop_reason: pause_turn` by resending with the assistant content (this is already done).
  - Logins: Claude.ai subscriptions **cannot** be used to sign in to third-party apps under Anthropic's terms, so each user needs an API key from platform.claude.com.
- **ElevenLabs:**
  - Text to speech: `POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128`, header `xi-api-key`. Body: `text`, `model_id`, `voice_settings{stability, similarity_boost, speed}`, with speed limited to 0.7–1.2.
  - Models: `eleven_flash_v2_5` ($0.04/1K characters, ~100 ms latency) and `eleven_v4` ($0.08/1K characters, most expressive). Also available: `eleven_v4_turbo` and `eleven_v3`.
  - Voice list: `GET /v2/voices?page_size=100`, which includes the default voices.
  - Voice design: `POST /v1/text-to-voice/design` with `voice_description` (20–1000 chars), optional `text` (100–1000) or `auto_generate_text`, and `model_id` `eleven_multilingual_ttv_v2` or `eleven_ttv_v3`. It returns `previews[{audio_base_64, generated_voice_id}]`. Save one with `POST /v1/text-to-voice` and `{voice_name, voice_description, generated_voice_id, labels?}`, which returns `voice_id`.
  - Custom voice slots: Free 3, Starter 10, Creator 30, Pro 160. **Voice Library voices don't use slots.** Adding and editing voices counts against a monthly quota of voice operations (Free 55, Starter 65, Creator 95).
  - Sam's key currently has only **Text to Speech: Access** and **Voices: Read**. Custom voices also need **Voice Generation** and **Voices: Write**.
  - The ElevenLabs connector (MCP) is connected in Sam's Claude account, which is useful for exploring voices.

## What to build next

These are Sam's latest requests, in his words where quoted. Do them in this order, building and running on the iPad after each.

1. **Rename to "Braidy".** Change the display name, target, scheme, folder (`Sidekick/` → `Braidy/`), project file, app struct, strings, queue labels and bundle ID (`com.samuelling.braidy`). Also change the Keychain services, and **migrate the existing keys** from `com.samuelling.sidekick.claude` and `.elevenlabs` so Sam doesn't have to paste them again. Rename `~/Sidekick` to `~/Braidy`. The test line becomes something like "Hi, I'm Braidy! I'll read the words on the screen for you."
2. **"Fun yet cool, video-game-like vibe… right now it feels like a boring app."**
   - **Overall:** restyle the whole UI as a game HUD. Use a dark backdrop, bold rounded heavy type (SF Rounded, black weight), one or two saturated neon accents, and chunky controller-style buttons (round "A"-style primary for **Repeat**, pill buttons with icons).
   - **Caption:** make it a game-style **dialogue box** with a character **name tag**, a small typewriter reveal synced to speech, and a bouncing ▼ "next" indicator.
   - **Feedback:** add satisfying micro-animations and haptics (button press, "game set", "voice ready").
   - **Settings:** present it as an "Options" menu with clear sections and icons.
   - **Originality:** keep it all original. No Nintendo or other game trade dress, fonts or characters.
3. **New icon, "more inviting and less generic".** It should be an original, friendly mascot built around the name "Braidy", warm and characterful at small sizes (the current one is a generic speech bubble). The renderer is `AppStore/make_icon.py` (PIL, 1024×1024 into the asset catalog). Show Sam two or three directions before committing.
4. **Onboarding, "very pro yet easy"**, on first run, skippable, and replayable from Options › "How Braidy works":
   1. Welcome: what Braidy does, in one sentence and with one picture.
   2. Set up the space: prop the device so the whole TV is visible, with an animated diagram.
   3. Permissions primer: explain *why* before iOS asks for the camera (to see the words) and the microphone (only to hear when the game is talking, so Braidy doesn't talk over it).
   4. Choose the game, using the platform-first picker.
   5. Place the reading box, as a guided drag with a live preview.
   6. Test voice → done.
5. **"How it works" and Privacy, because "parents freak out about that".** A plain-language page that is accurate to the code:
   - **On device:** camera frames, OCR, the microphone (speech-vs-not classification only), reading and speaking. Nothing is recorded or stored except per-game settings.
   - **No tracking:** no accounts, no analytics, no ads, no tracking.
   - **Optional services:** Claude receives only the game name and character names, plus **one camera frame** when you tap "Ask Claude which game is on screen". ElevenLabs receives only the text being read. Both happen only if the parent adds their own key. Keys stay in the device Keychain.
   - **Audio cache:** stays on the device and can be cleared.
   - **App Store:** this should qualify as "Data Not Collected". Note the third-party processors.
6. **Advanced setup that's easy, because "API keys are confusing".**
   - **Guided cards:** one for Claude and one for ElevenLabs, each with what it adds (with an audio sample for ElevenLabs), what it costs (with real numbers), step-by-step key creation with exact menu names and the minimal permissions, and a **Paste** button.
   - **Instant validation:** after pasting, make a cheap test call and show a green ✓ or a plain-English error.
   - **No jargon:** say "secret code" style wording rather than talking about tokens.
7. **iPhone works too, and must be checked.** The control row is currently ~440 pt wide, too wide for a 393 pt phone. Make the layout adaptive, consider landscape phone mounting, and test in the iPhone simulator and on a real phone if one is available.
8. **GitHub:** create **samuelling/Braidy**, which needs Sam's click (see above), push all the history, and set the build workflow's target name to `Braidy`.
9. **Per-game custom ElevenLabs voices.** Sam said "would be incredible, per game that's being played". The agreed design:
   - **Descriptions:** the cast lookup also asks Claude for a `voice_description` per character ("huge, warm, booming, slow and gravelly") and 2–3 search words.
   - **Supporting cast:** search the **Voice Library** for a fitting shared voice and add it to the account. This uses no slots. Verify the shared-voices search and add endpoints against current docs before use.
   - **Stars:** the top N characters (N = free slots, keeping some spare) get **designed** voices from Claude's description, previewed and saved.
   - **Bookkeeping:** track which designed voices belong to which game. When switching games, offer to free the old game's slots.
   - **Permissions:** tell Sam to add Voice Generation and Voices: Write to the key, and ask which ElevenLabs plan he's on.

## How to work on this Mac

- Build and run on the iPad from Xcode (destination **iPad (2)**, ▶ Run). The iPad must be unlocked to launch, and the first run per device needed Developer Mode, which is now done.
- Camera and microphone only work on a real device. The simulator is fine for layout.
- Harmless log noise: `FigCaptureSourceRemote err=-17281` at launch, and `AVAudioBuffer mDataByteSize (0)`.
- Commit after each working step, with clear messages.

## Tone of the product

The audience is parents setting it up and a 5-year-old using it. The kid-facing screen should be big, bright, almost wordless and fun. Everything parent-facing should be calm, clear and trustworthy. Never show a raw error to the kid. Errors go in a small status line or in Options.
