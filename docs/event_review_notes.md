# Event Review: design notes (not settled)

Working ideas from Lou, 16 Nov 2026. Nothing here is decided or built yet.

## How the reviewer works (Lou's current thinking)
- The event reviewer logs into Salesforce and opens an **Events app**, which has a **workspace just for event reviewers**.
- New events are owned by a **review queue**. Anyone in the reviewer group can see the queue.
- In the workspace the reviewer sees two lists on the same screen:
  1. **The queue**: every event waiting for review (urgent first, then oldest). Each one has **Take Ownership and Initiate**, which makes that reviewer the owner and starts the review. Once taken, the event leaves the queue so two people never review the same one.
  2. **My event reviews**: the events assigned to that reviewer, worked one by one.
- How the review itself is performed is still being worked out. The 25 Oct mockup and mock_events_v2 (Event Review: what it becomes, CQ.AI suggests, confirm) are the starting point.

## Decided (16 Nov 2026)
- **Quality Event stays its own object, not Case.** Case is the inspiration: we replicate what is needed (queues, team, escalation, a clock) inside Quality Event, so it ships as part of CQ, not as Salesforce standard Case.
- **Queues:** built to handle several review queues, but start with one.
- **Give it back:** a reviewer who took ownership and initiated can give the event back; it returns to the queue for anyone in the group to take.
- **E-signature:** the Reviewed e-signature belongs at this step, and comes in with the approvals work.

## Think of an event like a case (16 Nov 2026)
Lou: an event works like a Salesforce Case: queues, a case team working it together, and escalation when it waits too long.
What Case has that we would otherwise build: queues and assignment rules, case teams (roles on one record), escalation rules (reassign or notify when it sits too long), Omni-Channel routing, and entitlements with milestones (a clock, which fits the complaint clock from the aware date).

## The clock (Lou likes it, 16 Nov 2026; to design)
- Starts at the event's **aware date**, not when it was typed in or picked up.
- Targets per kind of event, set in setup (for example: urgent reviewed within 1 day, others within 5; a complaint's reporting deadline counted from the aware date).
- Shown on the queue and the reviewer's own list as time left, amber when close, red when overdue.
- **Decided:** when the clock runs out, the event escalates **automatically** (a scheduled job checks the clocks; no one has to press anything). What escalation does (notify whom, reassign to whom, how many levels) is still to design.

## Open questions
- Can a reviewer pass an event straight to a named person, or only back to the queue?
- Does Take Ownership and Initiate change the event's status (for example to In Review)?

## CQ's own dynamic questions (looked at 16 Nov 2026, for the Device Event follow-ups)
CQ already has a question engine we can sit our UI on:
- **Question** (`compliancequest__SQX_Task_Question__c`) belongs to a CQ **Task** (`SQX_Task__c`, Task Type e.g. Decision Tree, PHR). Record types Dynamic Question, Group Question, Simple Question. Answer types: radio options, picklist, text, date, datetime, number, custom component. Has Guide (help text) and Parent Question (groups).
- **Answer Option** (`SQX_Answer_Option__c`): the choices. Each has **Next Question** (the branch: which question this answer leads to) and **Actionable** (the answer makes it a complaint).
- **Answer Option Attribute** (`SQX_Answer_Option_Attribute__c`): what an answer means: **Reportable**, **Regulatory Body** (FDA, EMA, Health Canada, PMDA, TGA, Brazil), **Report Name** (US 30-Day MDR, EU 2/10/15/30-Day MIR, CA MDPR, AU MDIR...), **Report Type**, **Due In Days**, Country; it can also create tasks (assignee, job function).
- Answers are recorded as **Script Execution** (linked to Complaint, Case or Complaint Task; Actionable; Non Actionable Reason) with **Script Responses** (question, answer option, response, sequence, comment), and linked to complaints by **Complaint Script Execution Link**. Decision Trees have their own Decision Tree and Decision Tree Answer records on the complaint.
- Dev has one example, Task "FDA" (Decision Tree, 3 dynamic questions): death or serious injury? Yes = reportable, US 30-Day MDR, 30 days; No -> malfunction? No = not reportable; Yes -> likely to cause death or serious injury if it recurs? Yes = reportable 30-Day MDR; No = not reportable.

Direction (not decided): the Device Event questions come from CQ question sets (tasks) instead of our Event Questions; our intake shows the follow-ups inline as you answer (CQ shows one question at a time); reportability, report name and due days come from CQ's answer attributes, not from CQ.AI. Answers saved as a Script Execution and linked to the complaint when the event becomes one.
To check before building: how CQ runs Decision Trees on a complaint (Decision Tree and DT Answer fields, and what creates the regulatory report); whether a Script Execution can exist before the complaint does; Task Type values for intake scripts.

## Guiding principle and reusable AI (16 Nov)

Lou: intake is where we take AI out for a spin. CQ is good at making it work, not at making it easy. So: CQ's engines underneath, our experience on top.

**Voice first.** Lou uses speech on his phone because it is easier than typing. Intake headline: tap, say what happened, confirm. Use the standard **Convert Speech to Text** action (needs a ContentDocument ID for the audio).

**Reusable pieces found (not tested yet):**
- Salesforce standard actions: Extract Fields And Values From User Input (built to run before Update Record), Identify Record by Name (part from words), Convert Speech to Text, Get User Profile Details, Manage User Memory, Query Records / with Aggregate, Get Record Details, Summarize Record, Answer Questions with Knowledge / Agentic Retriever, Render LiveCard By Name, Slack messages. Only standard create is Create Case, so the Quality Event is still created by our Apex.
- CQ prompt templates: CQSS 5W2H Extraction, CQSS Entity Extraction, CQSS Paraphraser, CQSS Dynamic Prompt.
- CQ agent actions: Immediate Causes and Action Suggestion; Get Similar FMEA Details and Investigations; Get Similar Root Cause and Action Plan (both start from an Investigation).
- CQSS Similarity (cqext classes, runs on CQ's AWS service). Settings flows exist for Controlled Doc, Defect Code, FMEA Detail, Investigation, Root Cause Code, PRD. None for NC, Complaint or Quality Event; we would add one following CQ's pattern. Ask CQ how data is handled given AWS.
- CQ question engine (SQX_Task_Question__c etc.), see section above.
- myCQ app (cqext, for lite users): Home has CQEE_Report_Issue, Recently Created Issues. Possible entry point for our intake. Need a screenshot of what Report Issue creates.
- Our own pattern to copy: Controlled Document Agent and Scout Checklist (suggest each value, accept / edit / clear, save after one confirmation).

**To test before deciding:** Extract Fields on Quality Event custom fields; CQ 5W2H template on the NC-000162 description; Waiver - Get Similar Records (ours) to see if it calls CQ Similarity.

**Voice intake mockup (16 Nov):** v1 chosen (scratchpad mock_voice_v1). Three phone screens: Tap and Speak (big mic, live words, Type Instead), From What You Said (each answer with the words it came from, ✎ edit, × clear), Answer What Is Missing (only unanswered required questions, Device Event switch, Good to Know note). Lou: the voice screen is "awesome". v2 (styled like the document agent's review card) was rejected as too heavy for a phone. Open: whether to add a small "looks like EV-xxxx" note on screen 3.

**Voice intake v5 (16 Nov, current):** scratchpad mock_voice_v5. Three screens — (1) Tap and Speak [unchanged, Lou loves it]; (2) Check What CQ.AI Filled In, split into two banded sections "Details CQ.AI Filled In" (Part, Lot, Units — value fields with edit pencil) and "Questions CQ.AI Answered" (Where, Product Affected — choice questions), each ✦ CQ.AI Suggests with the source phrase; (3) Answer What's Missing (Injury, Safety — Needs your answer) + "Looks Like EV-0002" + Send.
- One unified question model: CQ.AI pre-answers the event questions it can from the description; the rest stay blank (it does not guess). On submit, answers set the Quality Event fields as the form does today; question set stays the customer's Event Questions.
- Sources: 5W2H template gives What/Where/How Many (PROVEN tonight via generations API, GPT-4o-mini, returns clean JSON); Part/Lot need Entity Extraction template or parse; Defect from CQSS Similarity on defect codes.
- Design principle (Lou): minimize scrolling — each screen should fit one phoneful. Lever: collapse "What You Said" to a tappable one-line strip, tighten row spacing.
- Open: AI-suggested answers shown pre-selected (fast) vs require an active confirm tap (deliberate, better for regulated). Carry same section-band header onto screen 3? (optional)

**Voice intake v6 (16 Nov, current — supersedes v5):** scratchpad mock_voice_v6. Four no-scroll steps, Next/Back only, progress dots: (1) Speak; (2) Details CQ.AI Filled In — Part, Lot, Units (editable values; "What You Said" collapsed to a one-line View strip); (3) Questions — Where + Product (✦ CQ.AI Suggests) then Injury + Safety (Your answer), Next gated until answered; (4) Review & Send — plain summary (summary icon) + Looks Like EV-0002 + Send.
- The fields-vs-questions break is now whole steps (values = step 2, questions = step 3).
- STANDING DESIGN RULE (Lou, applies to whole suite, desktop + mobile): minimize scrolling. Prefer stepped screens with Next/Back, one screenful per step; scroll only when genuinely unavoidable. Buttons, not swipe (swipe risks accidental taps / OS back-gesture conflict / skipping required answers). Matches Field Action + Disposition workspaces.
- BOTH CQ.AI engines PROVEN tonight against cqse-golden--dev via /einstein/prompt-templates/{devname}/generations (POST), GPT-4o-mini, temperature 0:
  - CQSS_5W2H_Extraction_Prompt (inputs: Instruction_Prompt, Input_Example, Output_Example, Entities, Target_Data) → returned {"What":"CardioFlow balloons were slow to deflate","Where":"Final test","How Many":"3", When/Who/Why blank,"How":"Found during final test"}.
  - CQSS_Entity_Extraction_Prompt (inputs: Description, Entities, Date_Entities, Reason_Required; output shape {ENTITY:{value,reason}}) → returned TITLE "CardioFlow Balloons Deflation Issue", PART "CardioFlow", LOT "0908", UNITS AFFECTED "3", DEFECT "Slow deflation during final test".
  - Both return raw words; resolve PART/LOT to real records via Identify Record by Name / CqEventParts.search (part) + lot lookup.
- Next build (not started): CqEventExtract Apex (call these templates, parse, map to question answers by role) + test; role-mapper; responsive stepped LWC for desktop+mobile.

**Conversational intake (16 Nov):** scratchpad mock_voice_v7. After Speak, a "CQ.AI Checks In" step: AI extracts first, confirms what it caught (checkmark chips: Part/Lot/Units/Where), then asks ONLY the gaps (injury, safety) with quick buttons + a mic (answer by voice or tap). Branches via CQ's conditional question engine (e.g., injury Yes -> severity follow-up) from the customer's own question set. Then Review & Send (v6). If description already covered everything, no gaps -> straight to Send ("speak and done").
- Fast path ("Send Now"): Lou's call = handle injury/safety via training (teach reporters to always state them) + the on-screen hint; CQ.AI catches them live when stated. No hard UI gate.
- Reviewer loop: speak-and-send files Quality Event (Waiting for Review) with Reported By (Get User Profile Details). Reviewer has "Ask the Reporter" action -> event to "Waiting on Reporter"; reporter answers one thing (by voice) -> back to reviewer. First version of escalation/routing. This is where the Units ambiguity gets resolved.
- PROVEN tonight (Entity Extraction, same endpoint): with injury/safety stated ("Nobody was hurt, but could be a safety risk"), returned INJURY "No", SAFETY RISK "Yes" correctly. CAVEAT: with two numbers in the sentence ("three slow... other five on hold") it returned UNITS AFFECTED "5" (on-hold) not "3" (failed) — quantity is ambiguous; sharpen prompt to ask for defective/failed count AND keep the number glanceable on review. Entities can be passed with allowed-value hints (e.g. "SAFETY RISK (answer No, Yes, or Not Sure)") and it respects them.

**Chat intake (16 Nov, current for the FLOOR REPORTER):** scratchpad mock_voice_v8. Single scrolling chat thread. Mic is the ONLY control — tap to talk, tap to stop; STOPPING THE MIC is the trigger for CQ.AI to respond (no Next button — Lou: a reporter would forget to press it; they just want to talk and get feedback). CQ.AI replies on its own: confirms what it caught (checkmark chips), asks only the gaps, branches from the customer's question set, flags EV-0002 inline. Mic + "Review & Send" stay docked at the bottom. ~1-2s extraction shows as a typing indicator.
- NO-SCROLL RULE EXCEPTION (Lou): a conversation may scroll because it's append-only like a text thread — newest at bottom, nothing above shifts under a thumb. The no-scroll rule still holds for the reviewer's structured screens and the rest of the suite.
- Two surfaces, one data model: FLOOR REPORTER = chat (v8); REVIEWER (desk) = structured no-scroll stepped screens (v6). "Review & Send" from the chat opens the v6 structured summary, or files straight off on the fast path.
- TTS read-aloud of CQ.AI replies: still needs a real-phone check (SpeechSynthesis in the SF mobile webview). On-screen is certain.

**KEYSTONE PROVEN (16 Nov): Apex can drive CQ's prompt templates natively.** executeAnonymous confirmed ConnectApi prompt-template classes exist and a full generation runs from Apex — no named-credential self-callout needed. Working pattern:
  ConnectApi.EinsteinPromptTemplateGenerationsInput inp = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
  inp.isPreview = false;
  ConnectApi.EinsteinLlmAdditionalConfigInput cfg = new ConnectApi.EinsteinLlmAdditionalConfigInput();
  cfg.applicationName = 'PromptTemplateGenerationsInvocable';
  inp.additionalConfig = cfg;
  inp.inputParams = Map<String, ConnectApi.WrappedValue>  (key 'Input:<ApiName>', WrappedValue.value = String);
  ConnectApi.EinsteinPromptTemplateGenerationsRepresentation r = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('<DevName>', inp);
  r.generations[0].text  -> the model's text (our templates return JSON).
  NOTE: ConnectApi.EinsteinLLM is not callable in test context — CqEventExtract must isolate the generate() call behind a @TestVisible seam that returns canned JSON under Test.isRunningTest().
  Build simplification: ONE Entity Extraction call can cover all intake fields (TITLE, PART, LOT, UNITS, WHERE FOUND, PRODUCT AFFECTED, INJURY, SAFETY RISK, DEFECT) by passing a rich Entities list with allowed values; no need to also call 5W2H for v1.
- BUILD VERDICT: extraction engine = afternoon (known method + known JSON + existing CqEventParts resolution). Time sinks = chat LWC, on-phone voice capture, device testing. Multi-session; Lou knows.

**BUILD: CqEventExtract engine DEPLOYED + PROVEN LIVE (16 Nov).** force-app/.../classes/CqEventExtract.cls (dev id 01pW4000003UgePIAS) + CqEventExtractTest (01pW4000003Ugg1IAC). fromDescription(String) calls CQSS_Entity_Extraction_Prompt natively (ConnectApi), parses {ENTITY:{value}}, resolves Part via CqEventParts.search, maps answers to real Event_Question__c Ids by Role, flags required-but-missing in stillNeeded. Units always needsConfirm. LLM call behind Test.isRunningTest() seam (mockJson). Both unit tests pass.
- LIVE run (real template) on the balloon+safety sentence returned: title, part(raw "CardioFlow balloons"), lot 0908, units 3 (quantity hint fixed 3-vs-5), defect, Where Found=In Our Plant, Product Affected=Yes, Injury=No, Safety Risk=Yes, stillNeeded=[]. Answers carried real question Ids. UNITS came back as JSON number; String.valueOf handles it.
- TO-DO (part resolution quality): raw PART "CardioFlow balloons" did NOT resolve (recordId null) because "balloons" breaks the LIKE search. Fix: strip generic nouns from the part term, progressive search, or use the Identify Record by Name action. needsConfirm already flags it so UX is safe.
- NEXT: (a) permissions — grant intake users Apex access to CqEventExtract when wiring the LWC (log in permissions_log then); (b) the chat LWC (cqEventIntakeChat) calling fromDescription then CqEventIntake.submitReport; (c) part-term cleanup; (d) lot resolution; (e) on-phone voice capture + device test.

**Part resolution — decided approach (16 Nov, Lou):** resolve LOT -> PART first (a lot belongs to one part, so it disambiguates), then fall back to name search only when no lot. Candidate suggestions are a FALLBACK TIER, not the default: one strong match -> pre-fill/confirm; a few plausible -> 2-3 ranked candidate chips (rank by parts recently used on events/NCs/complaints at the reporter's site/line, via CqEventParts.suggested()); too many/none -> hand to the search box (cqPartPicker, already built) or to the reviewer with CQ.AI's raw guess attached (Ask the Reporter loop). Never dump a long undifferentiated list. Reporter picks first (they're holding the part); defer to reviewer when ambiguous even to them.

**BUILD: cqEventIntakeChat LWC DEPLOYED (16 Nov).** New bundle (dev id 0RbW4000000Sqq5KAC), exposed on Tab/AppPage/HomePage, masterLabel "CQ.AI Report a Problem (Chat)". Text-first (voice later). Flow: describe -> CqEventExtract.fromDescription -> review (Title/Part/Lot/Units editable + questions pre-answered by CQ.AI, gaps flagged, uses c-cq-part-picker when part unresolved) -> submit via CqEventIntake.submitReport -> done. New component, does NOT touch the working cqEventIntake. Deploy order lesson: create the base .js resource FIRST, then html/css/js-meta.xml (js-meta fails with "No base file" if added before .js).
- TO TEST (desktop, as admin): Setup > Lightning App Builder > New > App Page (one region) > drag "CQ.AI Report a Problem (Chat)" on > Save + Activate (add as a tab) > open it, type a description, Continue, review, Send. Lou is sys admin so no Apex perms needed for his own testing.
- PENDING perms (for lite/intake users later, log in permissions_log then): Apex class access to CqEventExtract + CqEventIntake, and the component on their app/page.
- KNOWN v1 limits: part resolves by name only (lot-first resolution still TODO); no voice yet (keyboard only); styling is functional, not yet the v8 chat look.

**MILESTONE — full intake loop PROVEN LIVE IN UI (16 Nov, ~11:20pm).** cqEventIntakeChat on an App Page ("Intake"). Typed the balloon+safety sentence -> CQ.AI filled Title "CardioFlow Balloons Slow Deflation Issue", Lot 0908, Units 3 (quantity hint held), Defect, Where Found=In Our Plant, Product Affected=Yes, Injury=No, Safety Risk=Yes -> Send -> created EV-0003 (a8wW4000003Jx5tIAC), Status Waiting for Review, Urgent=true (fired from Safety Risk), Problem Statement verbatim, 4 Event_Answer rows with correct roles. Record verified by query. Part was null = Lou didn't pick one (optional, correct behavior; part-picker SELECTION->bind not yet exercised, submit path proven).
- NEXT: (a) exercise part-picker selection binds partId; (b) lot-first part resolution; (c) voice capture + phone test; (d) chat styling to v8; (e) permissions for lite users; (f) Send Now fast path + reviewer ask-back loop.

**Part/Lot resolution — FINAL design (16 Nov, Lou approved):** Lot drives the part. The AI engine captures the lot; it does NOT fuzzy-match the part by name (that guessing is demoted to a rare last resort).
- (a) Quality Event gets a lot -> part link AT SAVE (in submitReport), mirroring what CQ does on NC/Complaint (our Quality Event is custom, so we add it). Only when part is blank (don't override a part the user picked).
- Lot match outcomes (handle, never block submit):
  1. Lot clean / exact -> link part directly, no guessing.
  2. Lot partial but unique (e.g. "0908" -> only L26-0908) -> complete the lot to the full name AND link the part.
  3. Lot partial AND ambiguous (matches 2-3 lots, maybe different parts) -> short candidate pick-list at REVIEW time; picking the lot picks the part. This is the only "best guess" case; small and self-labeled because lot numbers are specific.
  4. Lot matches nothing (typo or new lot not yet in system) -> keep lot as entered, part blank, flag for reviewer.
- WHERE: review-time lot lookup in the LWC shows match/candidates/not-found so the reporter confirms the completed lot; save-time link in submitReport is the backstop for clean cases.
- Lot object: compliancequest__SQX_Lot_Info__c (Name = lot number, compliancequest__Part_Number__c = part number key, compliancequest__Manufacturing_Date__c). Resolve: match lot Name (exact then LIKE) -> Part_Number -> SQX_Part__c.
- NOTE: building this updates existing working classes (CqEventIntake.submitReport) + likely a new CqEventLots.resolve(); needs the Apex MetadataContainer update flow for existing classes, and a lot-insert pattern for tests (CqEventLotsTest currently inserts no lot).

**BUILD: lot->part link DEPLOYED + PROVEN (16 Nov).** New: CqEventLotLink.cls (dev 01pW4000003UhAfIAK) + CqEventLotLinkTest (01pW4000003UhCHIA0, 4 tests pass) + trigger QualityEventLotLink (before insert, 01qW4000007aLujIAE). No change to submitReport (trigger approach, so it applies to ALL Quality Event creation). Logic: Part blank + Lot set -> resolve lot (exact then bounded LIKE) -> if unique, set Part__c and complete Lot_Number__c to the full lot name; never overrides a chosen part; ambiguous -> candidates list (for review UI); unknown -> left as-is (never blocks). resolve()/resolveAll() are @AuraEnabled so the SAME resolver powers the future review-time lot lookup in the LWC.
- LIVE: CqEventLotLink.resolve('0908') on real data -> matches 1, lotName 'L26-0908', part 'PTCA-1000 · CardioFlow 3.0 ... Balloon Catheter' (a3FW4000002NzG9MAK). So re-running the chat intake with lot 0908 and no part now auto-links PTCA-1000 and stores L26-0908.
- Design note (Lou raised before-save flow): a before-save record-triggered flow is the declarative equivalent for the save-link and is lighter for simple cases, but we used Apex because the resolver is reused by the LWC review UI (@AuraEnabled) and the multi-hop + partial-match + candidate logic is cleaner/testable in Apex. Flow would duplicate the logic.
- STILL TODO: review-time lot lookup in the LWC (show completed lot / candidate pick / not-found) using CqEventLotLink.resolve; then voice; chat styling; permissions.

**BUILD: review-time lot lookup in the LWC (16 Nov).** cqEventIntakeChat now calls CqEventLotLink.resolve at review (and on lot edit): unique match -> shows "Lot {lot} -> {part} · linked from the lot" and fills part + completes the lot; several -> candidate buttons (pick lot -> sets part); none -> part picker + "that lot isn't in the system, reviewer will confirm". Same resolver the trigger uses, so reporter sees the link before saving; trigger is the backstop. Resources PATCHed (js 0RdW4000000b4KnKAI, html ...b4O1, css ...b4Pd).

## Reviewer Event Review panel — built (from mock_events_v5)

Built the heart of v5 first: the open-review panel, droppable on a Quality Event record page. No ownership model or new fields needed yet.

**Apex `CqEventReview`** (01pW4000003UjZ3IAK) + `CqEventReviewTest` (01pW4000003UhSSIA0, 2 tests pass).
`@AuraEnabled(cacheable=true) getReview(Id eventId)` → Review{problem card fields, answers, suggestion{becomes, reasons}, openOnPart, similarEvents}. All queries WITH USER_MODE.
- suggest(): becomes = 'New Complaint' if Where Found == 'At a Customer', else 'New Nonconformance'; reasons drawn from Where/Product Affected/Safety/Injury.
- openNcs(): open NCs on the same part (notes same-part vs same-part-same-lot).
- similar(): other non-closed Quality Events on the same part.

**LWC `cqEventReviewPanel`** (bundle 0RbW4000000SqzlKAC; js 0RdW4000000b4ZJKAY, html 0RdW4000000b4avKAA, css 0RdW4000000b4awKAA, js-meta 0RdW4000000b4cXKAQ). masterLabel "CQ.AI Event Review". Targets lightning__RecordPage [Quality_Event__c] + lightning__AppPage.
Two columns: Problem card left (statement, Where/Product/Lot/Units/Urgent, reporter's answers) · CQ.AI Suggests right (becomes + reasons, Open Records on This Part, Similar Events). Below: the four choice buttons (New Nonconformance ✦ / New Complaint / Add to an Open Record / Not a Quality Issue) with the AI-suggested one marked. Buttons are disabled — read-only for now.

**Deferred (the hard part):** the decision actions — confirming a choice actually creates the NC/Complaint, adds to an open record, or closes the event — and the queue/tabs/Take-Ownership wrapper from v5.

## Conversational intake — started (new component, text now / voice-ready)

Lou's clarification: this is the INTAKE chat, not the reviewer. The reporter describes a problem in their own words; CQ.AI reads it, says what it understood, and asks only for what's still missing — a real back-and-forth, not the suggestions form. Text for now; ideally the reporter can *speak* it. Confirmed: a new component, separate from cqEventIntakeChat (the describe→review→suggestions flow).

**Apex `CqIntakeChat`** (01pW4000003UjlxIAC) + `CqIntakeChatTest` (01pW4000003UjnZIAS, 4 tests pass). Stateless turn engine — the LWC holds the conversation, sends the running description + direct answers each turn.
- `start()` → opening prompt + reporter name.
- `respond(String stateJson)` where stateJson = {description, answers:[{questionId, answer}]}. Each turn: re-reads the whole description via CqEventExtract (the proven CQSS entity-extraction prompt template), builds a readback ("Got it — a CardioFlow balloon, lot L26-0908, slow to deflate, 8 units."), finds the first required question not yet answered (extracted or given), and asks it conversationally with its choices. When nothing required is missing → ready=true + draftJson for CqEventIntake.submitReport.
- Reuses the understanding engine rather than duplicating it, so the chat and the form stay in sync.

**LWC `cqIntakeConversation`** (bundle 0RbW4000000Sr1NKAS; js 0RdW4000000b4e9KAA, html 0RdW4000000b4flKAA, css 0RdW4000000b4hNKAQ, js-meta 0RdW4000000b4izKAA). masterLabel "CQ.AI Report an Event". Targets AppPage/HomePage/Tab.
Chat bubbles (reporter right, CQ.AI left), quick-reply chips for choice questions, a live "So far CQ.AI has / Still need" panel, and "Send to a Reviewer" when ready. Includes a **Speak** mic button wired to the browser SpeechRecognition API — fills the input so the reporter reviews before sending; hidden when the browser doesn't support it. That's the first cut of the voice Lou wants.

**Next on this:** LLM-phrased questions (instead of the question text verbatim) so it feels less like a form read aloud; confirm-the-part step when the match is fuzzy; and decide whether to auto-send on voice or always let them review. Lou testing tomorrow.

## Direction: the conversational chat is for MOBILE (2026-11-17)

Lou, after testing: "We don't need chat for desktop — the suggestions form already suffices. We need chat for mobile."

So the two intakes split by device:
- **Desktop → the suggestions form** (cqEventIntakeChat: describe → review suggestions → submit). Already good enough; leave it.
- **Mobile → the conversational chat** (cqIntakeConversation: back-and-forth, read-back, one gap at a time). This is where the chat belongs, and where voice matters most (talking > thumb-typing a defect on the floor/in the field).

Implications for the chat's next work:
- Treat it as mobile-first: tune layout/tap targets for a phone, make sure it's in the mobile nav.
- Voice is a real deliverable here, not a desktop afterthought. Desktop Lightning blocks the mic (iframe permission); the open question is whether the Salesforce mobile app's webview passes the mic through (iOS webview historically doesn't support the Web Speech API; Android maybe). Needs a real-device test; if the built-in speech API won't run in the app, fall back to a speech-to-text service.
- Desktop refinements to the chat are no longer a priority (desktop uses the form).

Status: text flow working; reviewer panel + chat deployed. Voice parked until tested on a phone.

## CONFIRMED: voice works via the Speak button in the Salesforce MOBILE app (2026-11-17)

Lou tested on a real phone: tapped the Speak button in cqIntakeConversation inside the Salesforce mobile app, spoke the problem, and it created **EV-0005** end to end — free speech → structured Quality Event, with the part (PTCA-1000 CardioFlow) and lot (L26-0908) linked from just "0908". 

So the mobile app's webview DOES pass the microphone through to the Web Speech API — the iframe restriction that blocks the Speak button on desktop Lightning does NOT apply in the mobile app. This is the opposite of the cautious prediction; mobile voice via our own Speak button is viable, no speech-to-text service needed as a fallback (at least on the device/OS Lou tested).

Net: the mobile-first direction is proven. Desktop keeps the suggestions form; mobile gets the conversational chat with working voice. 
Confirmed on: **Android** (webview passes the mic through with audio permission). **iOS: untested** — Apple's WKWebView has historically not supported the Web Speech API, so test on an iPhone before relying on voice for iOS users; if it fails there, add a fallback for iPhone only (e.g. native keyboard dictation into the text box), no rebuild needed.

## Refinement list from mobile voice test of EV-0005 (2026-11-17)

Seen in the real voice run ("three cardio flow balloons from 0908 were slow to deflate during final test nobody was hurt"):

1. **Safety/injury should always be asked, never inferred (IMPORTANT, compliance).** The LLM extraction filled all four required answers from the description, so the chat jumped straight to "ready" without asking anything. It inferred Safety Risk = No from "nobody was hurt" — but "nobody was hurt" ≠ "nobody could get hurt." EV-0003 (typed, explicit "could be a safety risk") correctly got Safety = Yes. For a QMS, don't let the AI guess safety/injury. Plan: in CqIntakeChat, treat the safety (and likely injury) questions as always-ask even when extraction produced a value — surface the AI's guess as a default but make the reporter confirm. Ties to Lou's earlier "train people to say if there was an injury or not."
2. **Read-back should show the RESOLVED part, not the raw spoken words.** It said "Cardio Flow Balloons (is that right?)" while the record correctly linked PTCA-1000 · CardioFlow 3.0. Show what it matched so the reporter can confirm the real part.
3. **Tidy the problem statement.** Stored verbatim lowercase/no-punctuation ("three cardio flow balloons from 0908..."). Have CQ.AI lightly clean it into a readable sentence for the reviewer while keeping the reporter's meaning. (Pairs with the LLM-phrasing pass.)
4. (Still queued) LLM-phrased follow-up questions; iPhone voice test.

### Addendum (from the "SO FAR CQ.AI HAS" panel screenshot)
The panel already shows a ❓ "needs confirm" marker on Part and Units, but NOT on the inferred question answers (Where/Injured/Safety all show clean). So inferred guesses look like confirmed facts. Fix: carry needsConfirm onto any question answer the AI inferred (not explicitly stated by the reporter) so it shows the same ❓, and force an explicit confirm on safety/injury. Reuse the existing ❓ convention — no new UI pattern needed.

### Confirmed + nit (mobile test, script 5 "Lot L26-0803 failed inspection", 2026-11-17 AM)
- CONFIRMED: the conversational ASK-branch works. With too little to infer, CQ.AI asked "Where did this happen?", showed the choice chips, and listed all four required items in "Still need." Both halves (infer-and-finish AND ask-when-unsure) now proven on mobile via voice.
- NIT: the lot displays lowercase ("l26-0803") in the read-back and the SO FAR panel. It normalizes to uppercase on save (lot-link trigger), but the live display should uppercase it too for consistency. Cheap fix in CqIntakeChat readback / the understood values.
- Minor: "Where did this happen?" chips show 3 options (In Our Plant, At a Supplier, At a Customer) — confirm whether "Not Known" should be offered too, or is intentionally omitted.

### Verified: always-ask + resolution fixes on mobile (2026-11-17 AM)
- Script #6 ("couple of balloons from 0901..."): read-back now shows resolved part (PTCA-1000 · CardioFlow 3.0...) and canonical lot (L26-0901). Injury/safety now ASKED with the AI's guess as a one-tap default; panel marks the unconfirmed guesses with ❓.
- Script #3 ("cracked hubs somebody could get hurt"): Safety correctly = Yes (last night it wrongly inferred No) and flagged ❓. Title "Cracked Hubs Present Safety Risk".
- Observation: for #3 the model also guessed Injury = Yes — a conflation of "could get hurt" (potential/safety) with "was anyone injured" (actual). Always-ask catches it (reporter taps No), so no bad data lands. Reinforces that injury/safety must be human-confirmed. Low priority: could tighten the extraction prompt so "could get hurt" maps to safety, not injury — but confirmation already protects the record.

## Injury = a second axis: Safety Event + Injury (design, 2026-11-17)

Lou's insight on the explosion test (5 units exploded + a person's arm injured): a serious event can create TWO records, not one. CQ's model confirms it:
- **cqext__SQX_Safety_Event__c** (Safety Event) — top-level personnel/EHS incident.
- **cqext__SQX_Injury__c** (Injury) — child of a Safety Event; links the injured person via cqext__SQX_Name_Of_Employee__c → compliancequest__SQX_Personnel__c. (Also links cqext__SQX_Safety_Event__c.)
- Product side stays NC / Complaint as today. Regulatory/MDR rides on the Complaint (SQX_Complaint_Regulatory__c; SQX_Canada_Report__c for Canada MDR).

So the reviewer decision is really two axes:
- **Product outcome:** New NC / New Complaint / Add to open record / Not a QE (what the panel has).
- **Safety outcome (when Injury = Yes):** create a Safety Event + Injury for the hurt person — IN PARALLEL with the product outcome, not instead of it.

Open design questions (for the reviewer decision-actions build):
1. When Injury = Yes, auto-propose a Safety Event + Injury alongside the product outcome?
2. The Injury needs WHO was hurt (Personnel). Add an intake follow-up "Who was hurt?" when injury = Yes (reporter names them; reviewer maps to Personnel), or leave the person for the reviewer?
3. Confirm Safety Event required fields before building the create action.
Belongs in the reviewer workspace decision-actions (the deferred build), not the intake — intake already captures injury = Yes correctly.

### Built: intake "Who was hurt?" follow-up (2026-11-17)
When Injury is confirmed Yes, the chat now asks one more question — "Who was hurt?" (free text) — and captures the name as an Event_Answer (Role "Injured Person"). Only asked on injury = Yes; skipped otherwise. 6 Apex tests pass (new: asksWhoWasHurtOnlyWhenInjured). This feeds the reviewer's parallel Safety Event + Injury creation, which is still ahead (decision-actions build). Injury = Yes already escalates to Urgent (Urgent_When = "Yes" on the Injury question — verified in CqEventIntake.submitReport).
