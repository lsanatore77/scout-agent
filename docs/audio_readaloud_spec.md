# Audio Read-Aloud — Specification (Option C)

Status: spec / not yet built. Depends on the final question set being locked first.

## Principle
Every question CQ.AI asks in the intake chat is also read aloud, using audio **pre-generated once and stored inside Salesforce**. No third-party service at runtime. Works on every phone (Android app, iPhone app, browser) because the device only ever *plays* audio — it never synthesizes it. This sidesteps the confirmed Android WebView gap (SpeechSynthesis absent; see read-aloud finding in event_review_notes.md).

## 1. Scope — what gets audio
- All fixed prompts (opener + core + conditional questions) → one clip each. Current set = 9 (see event_review_notes.md question list).
- NOT the dynamic read-back ("Got it — lot 5555, 5 units…") — different every time, can't be pre-clipped; stays on-screen only. The rule is about *questions*, which are all fixed.

## 2. Storage & playback
- One MP3 per question, stored as a Salesforce File (ContentVersion) linked to the question's `Event_Question__c`.
- At load, Apex returns the clips as base64 alongside the questions (extend CqIntakeChat.start/getSetup). Component holds them in memory → playback is instant and offline, with no per-question round-trip and no URL/session/CORS issues in the app webview.
- Clip size ~10–30 KB each; all together trivial.

## 3. Generation (one-time, offline; app never calls out)
- (a) Open-source/offline TTS (e.g., Piper) or a human recording → zero vendor ever; or
- (b) A one-time cloud-TTS run → vendor used once to produce files, never at runtime.
- One consistent voice for all clips.

## 4. Staleness
- Store the exact source text per clip (`Audio_Text__c` or on an audio record). On load, if question wording != clip source text → clip is stale → silent text-only fallback + flagged for regeneration. Reworded questions never play outdated audio.

## 5. Playback UX
- "🔊 Read aloud" toggle, default ON (admin-configurable), one-tap mute, remembered per reporter.
- Browser autoplay rule: first user tap unlocks audio; opener may be silent until first interaction.
- One clip at a time (new question cancels previous). Tap a CQ.AI bubble to replay. Missing/stale → silent fallback, never an error.

## 6. Admin baseline setting
- Org-level setting ("Read aloud default: on/off"), Custom Metadata or Custom Setting. Per-reporter toggle overrides.

## 7. Reuse (future, design-for, not v1)
- Generic "clip per fixed text" mechanism → later: checklist steps, safety alerts, and multi-language (store clips keyed by question + language, pick by reporter language, no runtime translation).
- v1: English + intake only; storage shaped to allow a language dimension later (favors a child object: Question + Language + File + Source_Text).

## 8. Cost
- Zero at runtime (no vendor calls). One-time generation. Storage negligible.

## Open decisions for Lou
1. Generation source: offline/open-source TTS (no vendor ever) vs one-time cloud run (both end with owned MP3s in Salesforce).
2. Voice/accent (one consistent voice).
3. Default on/off baseline + admin-configurable? (recommended: on + configurable).
4. Storage shape: simple (file per question + Audio_Text__c) vs future-proof child object (Question + Language + File + Source_Text).
5. Deliver all clips at load (recommended) vs fetch per question.
6. v1 languages: English only? (recommend yes; design for more.)

## Sequence
Lock the final question set (text) first — the clips are generated from that exact wording. Then build this audio layer against the locked set.

## CONFIRMED technical path (2026-11-17)
Playback mechanism is settled by on-device testing in the Salesforce Android app:
- **Do NOT use the `<audio>` element or MP3** — blocked in the app WebView (NotSupportedError), even for WAV.
- **Use the Web Audio API**: base64 clip → bytes → PCM samples → `AudioContext.createBuffer` → `AudioBufferSourceNode`. Proven to play.
- Store clips as **WAV (16-bit PCM mono)**; the LWC parses the WAV header in JS to get the sample rate + PCM and fills the AudioBuffer (no decoder, no `decodeAudioData` dependency).
- Requires: a user gesture to create/resume the AudioContext (the tap that advances the chat covers this) and media volume up.

### Build pieces
1. **Storage** — one WAV clip per Event_Question (v1: English). A `Audio_Source_Text__c` field on the question records the text the clip speaks, for staleness detection. (Multi-language via a child object later.)
2. **Apex** — when a Turn asks a question, also return `askAudio` (base64 of that one question's clip) when read-aloud is enabled.
3. **LWC** — on an asking turn, decode + play via Web Audio; per-reporter mute toggle; one shared AudioContext opened on first gesture.
4. **Clips** — the 9 fixed prompts need neutral voice clips (this build env has no TTS/no network, so they're sourced once and uploaded).

## Clips as files (19 Nov 2026)
The 131,072-character field caps a clip at about 98 KB, which only fits phone-line quality (8 kHz). CqIntakeChat.clipFor now
looks for a .wav file attached to the Event_Question__c record first (latest version, up to 2 MB) and falls back to
Audio_Wav_Base64__c. Target format for the professional clips: 44.1 kHz, 16-bit PCM, mono. The LWC is unchanged; it reads the
sample rate from the WAV header. Reporters need read access to the question record for the attached file to reach them.
Tests: CqIntakeChatClipTest (3 pass).
