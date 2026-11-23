# Project overview — start here

A one-page map of this project: what it is, how the pieces fit, and where to read more.
For the authoritative data model see `docs/DATA_MODEL.md`; for what's prototype vs.
production-ready see `docs/hardening_todo.md`.

> **Status:** a working prototype on the `cqse-golden` dev sandbox, built for speed and
> demoed on real devices. Several areas are deep; a few are placeholder. This is a layer
> **on top of** the ComplianceQuest managed package (`compliancequest__`, `cqext__`) — it
> extends CQ's QMS objects (Nonconformance, Complaint, CAPA, Investigation, Field Action…),
> it does not replace them.

## What it is

An **AI-assisted quality management** layer: it helps a reporter file a quality event, helps
a reviewer triage and dispose it, and helps investigators and quality engineers work the
downstream processes (investigation, CAPA, field action/recall, complaint reports), with
"CQ.AI Suggests" assistance throughout. The AI **drafts and suggests; people decide.**

### Design principle: works as is, flexible if wanted

The core system must work **out of the box, with little to no customization or configuration**.
Flexibility is welcome, but only as an optional layer on top of good defaults (Lou, 2026-11-22):

- **Defaults first.** Every workspace works as soon as it is on the page: steps, CQ.AI suggestions
  and rules are built in. Nothing has to be set up before it is usable.
- **Settings are optional.** An empty setting means the standard behaviour (CQ.AI Workspace Settings
  blank = standard look, steps on the left; Demo Mode off = the strict rules).
- **Themes are optional.** Without one, everything falls back to the standard cqStyles colours.
- **Never require configuration to fix a gap.** If something only works after an admin configures
  it, the default is wrong; fix the default.
- **Future builders stay optional.** Anything that lets customers rearrange workspaces (for example the
  parked drag-and-drop workspace builder) changes the standard workspaces; it never replaces them or
  becomes a setup step.

## The pieces (each is one area; the key classes/LWCs and its deeper doc are noted)

**1. Report a Problem (intake)** — the reporter's front door, mobile-first.
A big "tell your story" box (typed or spoken, live dictation) → CQ.AI reads it, resolves the
part/lot, and asks only for what's missing → creates a **Quality Event**. Questions are
admin-configured (`Event_Question__c`), answers saved (`Event_Answer__c`), safety/injury
always asked, injury auto-escalates to Urgent. Prompts can be **read aloud** on the device.
Apex: `CqIntakeChat` (conversation engine), `CqEventExtract` (entity extraction),
`CqEventLotLink` (canonical lot/part), `CqEventIntake` (saves the event).
LWC: `cqIntakeConversation` (current redesign), `cqEventIntake`, `cqEventIntakeChat`.
Docs: `event_review_notes.md`, `audio_readaloud_spec.md`, `sample_data_log.md`.

**2. Event review** — the reviewer turns a submitted event into the right QMS record
(NC / Complaint / Trend) and closes it. Apex `CqEventReview`, LWC `cqEventReviewPanel`.
_(Decision-actions build — creating the NC/Complaint + parallel Safety Event/Injury — is
still pending; see hardening backlog.)_

**3. Triage** — guided triage of an NC: containment, risk, repeat-of detection, photos,
next steps. Apex `CqTriage*`, LWC `cqTriageWorkspace` / `cqTriageAssistant` / `cqTriageGlance`.

**4. Investigation (Find the Cause)** — hypotheses, what-changed, check-history, evidence,
5-Why, root cause — writing back into CQ's investigation objects. Apex `CqInvestigation*`,
objects `Investigation_Hypothesis__c` / `Investigation_Change__c` / `Investigation_Evidence__c`
/ `Investigation_Not_Relevant__c`, LWC `cqInvestigationWorkspace` / `cqInvestigationCause`.

**5. Field action / recall** — scope, strategy, recovery, review, closure; lots, shipments,
stock, customers, recall tasks. Apex `CqFieldAction*` / `CqLotStock` / `CqLotShipments`,
objects `Field_Action_*` / `Lot_*`, LWC `cqFieldActionWorkspace` and step components.

**6. Complaint report + PHR QMS panel** — the Associated Items report, the related-records
panel for a Product History Review / Complaint, relevance ranking, and a PDF.
Apex `Complaint*` / `Phr*` / `AssociatedItems*`, LWC `associatedItemsReport` /
`phrQmsRecordsPanel` / `phrLead*`. Docs: `README_history_2026-10.md`.

**7. Ask CQ** — an "ask CQ.AI a question" workspace/popover, backed by the **`Ask_CQ`
External Credential** (consumer key/secret live there only). Apex `AskCq*`, LWC `askCqWorkspace`
/ `askCqPopover`.

**8. Disposition & shared bits** — disposition workspace (`CqDisposition*`), signal/trend
jobs (`CqSignalJob`, `Signal_Event__c`), the "why did CQ.AI suggest this" explainer
(`cqAiWhy`), rich text, approvals (`CqApproval*`), e-signature (`CqEsig*`).

## Shared data model (the spine)

`Quality_Event__c` is the intake record (Report/Trend, Urgent, Product Affected, Status
New → Waiting for Review → Reviewed → Closed). Around it: `Event_Question__c` / `Event_Answer__c`
(the intake Q&A), and **fields this project adds to CQ's managed objects** (NC, Complaint,
CAPA, Field Action, Lots…). Full detail, always current: `docs/DATA_MODEL.md` (generated by
`tools/data_model.py` from the metadata — don't hand-edit it; log changes in `data_model_log.md`).

## Conventions a newcomer needs

- **UI says "CQ.AI Suggests"**; agents never write the literal string "CQ.AI". Green = positive
  only. Title Case headings/buttons. "Relevant records," not "related."
- **AI boundary:** suggestions and drafts are assistive; a person confirms every decision.
  Safety/injury is never silently inferred.
- **Packaging habits:** SOQL uses `WITH USER_MODE`; no hard-coded IDs; no namespace prefix in
  strings; new fields need FLS on the `CQAI_Quality` permission set.
- **Secrets** live only in the `Ask_CQ` External Credential — never committed or logged.
- **Dev-sandbox shortcuts:** validation rules are sometimes toggled off to bulk-load data;
  turn them back on before a pilot. A managed-package upload needs ≥75% Apex coverage.

## Where to read next

- `DATA_MODEL.md` — every object/field (generated). `data_model_log.md` — the change narrative.
- `event_review_notes.md` — the intake/review build log (most active area).
- `audio_readaloud_spec.md` — how read-aloud works (Web Audio, stored PCM clips).
- `README_history_2026-10.md` — complaint report + PHR QMS panel.
- `packaging_notes.md` / `PACKAGE_2026-10-23.md` — packaging.
- `permissions_log.md`, `login_notes.md` — access.
- `hardening_todo.md` — what's prototype vs. production, and what's left before a pilot/package.
- Git history is the deepest record: `git log -- force-app/main/default/<path>`.
