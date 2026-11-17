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
