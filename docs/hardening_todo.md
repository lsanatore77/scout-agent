# Hardening backlog

A running list of what to tighten **before a real pilot user or a package upload** —
whichever comes first. We're in build-for-speed mode on the `cqse-golden` dev sandbox;
this file is where deferred "make it solid" work gets parked so nothing is forgotten
when we flip to hardening mode.

**How we use this**
- When we knowingly skip hardening to move fast, add a line here instead of losing it.
- Review this list at the next milestone (first real user / first managed-package upload).
- Harden **per feature, once it stops changing** — not all at once.

**Status:** ☐ open · ◐ in progress · ☑ done
**Priority:** 🔴 trap (data loss / security / a hard gate) · 🟡 rough (quality, UX, robustness)

_Last updated: 2026-11-17_

---

## 🔴 Hard gates (can't ship past these)

- ☐ 🔴 **Apex test coverage ≥ 75%** — required to upload a managed package. Current: only
  `CqIntakeChatTest` (9 tests) covers the intake engine. **No tests** for `CqEventIntake`
  (submitReport), `CqEventExtract`, `CqEventLotLink`, the review-panel Apex, or the audio
  path. Tests must *assert behavior*, not just run lines for coverage.
- ☐ 🔴 **Validation rules re-enabled** — we keep rules off while bulk-loading sample data.
  Confirm every validation rule intended for production is ON and tested before a pilot.
- ☐ 🔴 **AppExchange security review** — needed for a public managed package (CRUD/FLS
  enforcement, no SOQL/DML injection, sharing). Plan for lead time.

## 🔴 Data safety

- ☐ 🔴 **Intake report not lost on error/offline** — if `submitReport` fails or the device
  drops connection, the reporter's story + answers should survive (local draft / retry),
  not vanish. Today a failure just shows an error bubble.
- ☐ 🟡 **Mid-report app kill** — reopening Intake starts fresh; a partially-entered report
  is lost. Decide whether to persist an in-progress draft.

## Intake component (compose → chat)

- ☐ 🟡 **iOS live-dictation check** — SpeechRecognition verified on Android; **not yet on
  iPhone**. Confirm the big-box dictation + the text-question mic both work in the iOS
  Salesforce app.
- ☐ 🟡 **Dictation smoothing** — interim words rewrite the box live; may feel jumpy on a
  long narrative. Option to commit only finalized phrases.
- ☐ 🟡 **Graceful states** — mic blocked/denied, no network on `respond`, empty/garbled
  transcription. Some handling exists (micError); audit the full set.
- ☐ 🟡 **Accessibility** — screen-reader labels on the mic / read-aloud / chips, keyboard
  operation, focus management when the stage switches compose → chat, color contrast.
- ☐ 🟡 **Governor limits** — `respond` runs CqEventExtract (LLM) + lot/part resolution each
  turn. Confirm limits hold under a long conversation; consider caching within a session.

## Audio read-aloud

- ☐ 🟡 **Real voice clips** — currently the Windows built-in voice (v1). Swap to a female
  voice (Zira, or a cloud TTS) via `tools/generate_prompt_clips.ps1` → re-upload clips.json.
- ☐ 🟡 **Clip staleness** — `Audio_Source_Text__c` records what each clip says, but nothing
  warns an admin when a question is reworded and its clip no longer matches. Add a check.
- ☐ 🟡 **Opening / "ready" lines have no clip** — only the gap questions speak. Decide if the
  intro and the "that's everything I need" line should too.
- ☐ 🟡 **Admin-level read-aloud default** — today it's a per-reporter toggle (default on).
  Consider an org/perm-set setting for the default.
- ☐ 🟡 **Remove any remaining temp scaffolding** — test-tone / diag code already removed;
  re-scan before packaging.

## Reviewer side (not built yet)

- ☐ 🟡 **Decision actions** — the review panel should actually create the NC/Complaint AND the
  parallel Safety Event + Injury (using the captured "Who was hurt?" → Personnel), then close
  the event. Design noted; build pending.

## Packaging hygiene (ongoing)

- ☐ 🟡 Queries use `WITH USER_MODE`; no hard-coded IDs; no namespace prefix in strings —
  keep auditing as new Apex lands.
- ☐ 🔴 Secrets (Ask CQ consumer key/secret) stay in the `Ask_CQ` External Credential only —
  never committed, never logged.
