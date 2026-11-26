# Navi

An iPad (and iPhone) app that reads game dialogue out loud. Prop the iPad up facing the TV or the Switch, and Navi reads each new dialogue box as it appears, giving each character their own voice. It was built for a kid who's playing Zelda but can't read yet.

The Switch 2's screen reader only covers the console's own menus, so it never reads in-game text. Navi works from the outside, through the camera, so it works with any game on any screen.

## How it reads

1. **Camera → text.** The back camera runs at 1080p. Several times a second, Apple's on-device text recognition (Vision, accurate mode, with Zelda/Pokémon vocabulary added) reads whatever falls inside the **reading box**, a region you drag over the game's dialogue area so the map, hearts and menus are ignored.
2. **Waiting for the box to finish.** Games type their dialogue out a few letters at a time, and camera OCR jitters from frame to frame. A line counts as *settled* once three consecutive reads agree (≥ 90% similar by edit distance) and the text has stopped growing. That takes about half a second.
3. **Once per box.** Each settled line is compared with the last one spoken, and repeats (≥ 80% similar) are skipped. If a line pauses partway and then continues, only the new words are spoken. When the box disappears for a few seconds, the memory clears, so a repeated line gets read again.
4. **Who's talking.** Zelda prints the speaker's name on a short line above the dialogue. If the first row matches a known character, or looks like a name label (≤ 3 capitalized words, no punctuation, narrower than the text under it), Navi uses that character's voice and doesn't read the label aloud. You can turn "say the character's name first" on if you want it read.
5. **Speech.** Lines are spoken with AVSpeechSynthesizer and play even with the silent switch on. A newer line interrupts an older one, so mashing through dialogue keeps up. A few names get respelled so they're pronounced right (Hyrule, Zonai, Sheikah, Korok, Purah, Pokémon…).

The big cyan button says the last line again. **Read now** forces a read of whatever is in the box.

## Character voices (with Claude)

Set the game (type it, pick it from the list, or tap **Ask Claude which game is on screen**, which sends one camera frame to Claude). Then:

- **Look up characters with Claude** asks Claude, with web search, for the game's main speaking characters. For each one it gets their gender, species, age, a short description, and a suggested pitch (0.5 for a huge rock creature, 2.0 for a tiny sprite) and speed.
- **Newcomers get looked up automatically.** When a name Navi hasn't met shows up in a dialogue box, it's added to the cast and Claude is asked about that character in the background.
- **Voices are cast by gender.** Each character gets an installed voice of matching gender. Choices are spread across the available voices, stable per name, and avoid the narrator's voice. Pitch and speed come from Claude's suggestion.
- **Everything is editable.** Settings › Characters lists the cast for the current game, where you can change any character's voice, pitch, speed, gender, species or age. A voice you pick by hand is locked, so later lookups won't override it.

Cast lists are saved per game on the device. The more Enhanced or Premium voices are downloaded (iPad Settings › Accessibility › Spoken Content › Voices › English), the more distinct the characters sound. The built-in compact voices only offer a handful of male and female voices.

### The Claude API key

Only the character and game lookups use Claude. Reading the screen and speaking happen entirely on the device. Lookups need a **Claude API key** from [platform.claude.com](https://platform.claude.com/settings/keys), entered in Settings › Claude and stored in the device's Keychain. Requests go straight from the device to `api.anthropic.com` (model `claude-sonnet-5-5`, web search tool `web_search_20260318`), billed per use: a whole-cast lookup is a few cents.

Claude.ai subscriptions (Pro, Max) can't be used to sign in to third-party apps under Anthropic's terms, so anyone you share Navi with brings their own API key. Without a key, Navi still works: each character it sees still gets its own voice (just not matched to gender until you set it), and every voice can be set by hand.

## Setting up

Open `Navi.xcodeproj` in Xcode 16 or later, choose your iPad as the run destination, and press ▶. The team is already set to the same one as Aether. The first launch asks for camera access.

Tips:
- Put the iPad far enough back to see the whole screen, then use **Move the reading box** to cover just the dialogue area. If it's far away, use the zoom slider.
- Glare and moiré from TV screens are the main enemies. Tilt the iPad slightly off-axis from lamps and windows.
- The screen stays awake while Navi is open.

## Files

| File | What it does |
|---|---|
| `CameraModel.swift` | Capture session, rotation, zoom, Vision text recognition inside the reading box, row assembly, snapshots |
| `DialogueTracker.swift` | Waiting for a line to settle, skipping repeats, continuations, text similarity |
| `SpeakerParser.swift` | Splitting the speaker's name label off the dialogue |
| `Cast.swift` | Character profiles, per-game cast storage, voice casting |
| `ClaudeClient.swift` | Claude API calls (cast lookup, one-character lookup, game identification) and Keychain |
| `Speaker.swift` | Speech, voice list, pronunciation fixes |
| `Reader.swift` | Ties it all together; settings |
| `ContentView.swift`, `CameraStage.swift`, `SettingsView.swift` | UI |
