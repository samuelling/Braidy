# Sidekick

An iPad (and iPhone) app that reads video game text out loud for kids who are just learning to read. Prop the iPad up facing the TV or handheld, and Sidekick reads each new dialogue box as it appears, with a different voice for each character. It works with Pokémon, Mario, Zelda, Kirby, Animal Crossing, or anything else with text on screen.

Consoles' own screen readers (the Switch 2's included) only read their system menus, never in-game text. Sidekick works from the outside, through the camera, so it isn't tied to any console or game.

## How it reads

1. **Camera → text.** The back camera runs at 1080p. Several times a second, Apple's on-device text recognition (Vision, accurate mode) reads whatever falls inside the **reading box**, a region you drag over where the game prints its text so maps, HUDs and menus are ignored. Every game puts its text somewhere different, so the box is remembered per game.
2. **Waiting for the box to finish.** Most games type their text out a few letters at a time, and camera OCR jitters from frame to frame. A line counts as *settled* once three consecutive reads agree (≥ 90% similar by edit distance) and the text has stopped growing, which takes about half a second.
3. **Once per box.** Each settled line is compared with the last one spoken, and repeats (≥ 80% similar) are skipped. If a line pauses partway and then continues, only the new words are spoken. When the box disappears for a few seconds, the memory clears, so a repeated line gets read again.
4. **Who's talking.** Many games print the speaker's name on a short line above the dialogue. If the first row matches a known character, or looks like a name label (≤ 3 capitalized words, no punctuation, narrower than the text under it), Sidekick uses that character's voice and doesn't read the label aloud. You can turn "say the character's name first" on if you want it read. Narration and battle text ("Pikachu used Thunderbolt!") use the narrator voice.
5. **Speech.** Lines are spoken with AVSpeechSynthesizer and play even with the silent switch on. A newer line interrupts an older one, so mashing through dialogue keeps up. Game words are respelled so the voice pronounces them right (see below).
6. **Not talking over voice acting.** Some games mix text-only dialogue with voiced cutscenes that also show subtitles. Sidekick listens through the microphone with Apple's on-device sound classifier (SoundAnalysis), which scores speech every ~0.25 s. When a line settles, Sidekick waits 0.7 s and checks whether the game spoke from 1.5 s before the line settled until then. If it heard at least ~0.75 s of speech, the line is shown marked "The game said this" but not read aloud. Grunts and one-word exclamations are too short to count. Sidekick ignores the mic while it's speaking itself, plus a second after, and nothing is recorded or sent anywhere. People talking in the room can trip it too, so Settings › Voiced cutscenes has a sensitivity slider and an off switch.

The big cyan button says the last line again. **Read now** forces a read of whatever is in the box.

## Each game's characters and words (with Claude)

Set the game: type it, pick it from the list, or tap **Ask Claude which game is on screen**, which sends one camera frame to Claude. Then:

- **Look up characters with Claude** asks Claude, with web search, for the game's main speaking characters and its own vocabulary:
  - **Characters** come with gender, species, age, a short description, and a suggested pitch (0.5 for a huge rock creature, 2.0 for a tiny sprite) and speed.
  - **Pronunciations** are respellings for names a standard voice would mangle ("Pikachu" → "Pee-kah-choo").
  - **Up to 80 game words** (places, items, creatures, moves) are added to the OCR dictionary, so English autocorrect doesn't "fix" them, and respelled for speech where needed.
- **Newcomers get looked up automatically.** When a name Sidekick hasn't met shows up in a dialogue box, it's added to the cast and Claude is asked about that character in the background.
- **Voices are cast by gender.** Each character gets an installed voice of matching gender. Choices are spread across the available voices, stable per name, and avoid the narrator's voice. Pitch and speed come from Claude's suggestion.
- **Everything is editable.** Settings › Characters lists the cast for the current game, where you can change any character's voice, pitch, speed, gender, species or age. A voice you pick by hand is locked, so later lookups won't override it.

Casts, vocabularies and reading boxes are saved per game on the device. The more Enhanced or Premium voices are downloaded (iPad Settings › Accessibility › Spoken Content › Voices › English), the more distinct the characters sound.

### The Claude API key

Only the lookups use Claude. Reading the screen, listening and speaking happen entirely on the device. Lookups need a **Claude API key** from [platform.claude.com](https://platform.claude.com/settings/keys), entered in Settings › Claude and stored in the device's Keychain. Requests go straight from the device to `api.anthropic.com` (model `claude-sonnet-5-5`, web search tool `web_search_20260318`), billed per use: a whole-game lookup costs a few cents.

Claude.ai subscriptions (Pro, Max) can't be used to sign in to third-party apps under Anthropic's terms, so anyone you share Sidekick with brings their own API key. Without a key, Sidekick still works: each character it sees still gets its own voice (just not matched to gender until you set it), and every voice can be set by hand.

## Setting up

Open `Sidekick.xcodeproj` in Xcode 26 or later, choose the iPad as the run destination, and press ▶. The first launch asks for camera and microphone access. The camera and microphone only work on a real device, not in the simulator.

Tips:
- Put the iPad far enough back to see the whole screen, then use **Move the reading box** to cover just the text area. If it's far away, use the zoom slider.
- Glare and moiré from TV screens are the main enemies. Tilt the iPad slightly off-axis from lamps and windows.
- The screen stays awake while Sidekick is open.

## Files

| File | What it does |
|---|---|
| `CameraModel.swift` | Capture session, rotation, zoom, Vision text recognition inside the reading box, row assembly, snapshots |
| `DialogueTracker.swift` | Waiting for a line to settle, skipping repeats, continuations, text similarity |
| `SpeakerParser.swift` | Splitting the speaker's name label off the dialogue |
| `VoiceListener.swift` | Listening for the game's own voice acting (SoundAnalysis) |
| `Cast.swift` | Character profiles, per-game casts and vocabulary, voice casting |
| `ClaudeClient.swift` | Claude API calls (cast and vocabulary lookup, one-character lookup, game identification) and Keychain |
| `Speaker.swift` | Speech, voice list, pronunciation fixes |
| `Reader.swift` | Ties it all together; settings |
| `ContentView.swift`, `CameraStage.swift`, `SettingsView.swift` | UI |
