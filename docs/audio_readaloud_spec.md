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
