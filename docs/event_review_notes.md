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
