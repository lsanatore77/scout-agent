# Backlog (parked, not forgotten)

Things agreed to come back to. Newest at the top of each section.

## Ideas

### CQ.AI fills in the record, the person confirms (24 Nov 2026, Lou)
AI in quality so far sits beside the form; the bigger step is CQ.AI drafting records from evidence that already exists,
with the person reviewing, correcting and signing. Rules: every AI-filled value shows as a suggestion until confirmed,
the source evidence is kept and linked to each value, the audit trail records who confirmed or changed what, signatures stay human.

**First pilot (chosen): CoC documents filling in lot records.** Claude reads a certificate of conformance, fills the lot's
fields and points to where each value came from; the person confirms. Ties in with the CoC data cleanup below.
Builds on the Google Vision text extraction CQ already uses on PDFs (Lou, 24 Nov). Not in this repo or the dev org yet:
find out where it runs, whether it returns text with positions on the page, and where the text is stored.
Salesforce options (checked 24 Nov): **Data 360 Document AI** (OCR + LLM to fields from a JSON schema, confidence per field;
needs Data 360 credits, an LLM enabled, and Agentforce switched on, which clashes with "leave Agentforce alone");
**Intelligent Document Reader** (Amazon Textract OCR per page, needs an add-on licence; text only, the field mapping is ours).
Either way the new work is the same: map text to the lot's fields and show each value for a person to confirm.
Dev org check (24 Nov, read only, nothing changed): Agentforce, Data Cloud (Starter) with its default data space, and
Einstein generative AI are all on. Document AI is not offered anywhere (Setup search, Data Cloud Feature Manager, App
Launcher), and Digital Wallet opens "Page doesn't exist", so the org shows no credit balance. Intelligent Document Reader
is not provisioned. Agentforce is fine to use (Lou, 24 Nov). Next: ask Salesforce what turns Document AI on for this org
(likely a Data 360 edition with credits beyond Starter). **Decision (Lou, 24 Nov): Lou is requesting Document AI; until it
arrives the pilot uses Google Vision.** Keep the reader behind one step so Document AI can replace it later without changing the screens.
Other candidates: customer response emails filling Field Action cases; supplier replies; failure and severity coding;
regulatory report drafts from a complaint and its investigation.

### Claude for Manufacturing plugin (Nov 2026)
Anthropic's plugin for plant teams (17 skills; quality skill covers a failed inspection to a corrective action report; no
QMS connectors). Early version, aimed at manufacturers. Later: compare its full skill list with CQ.AI, and consider a CQ connector.

### Field Action Review: record fields, and our own approval matrix (24 Nov 2026, Lou)
- **Record fields.** The review's progress lives in the workspace and a draft field; a standard record page shows "In Review"
  and little else. Write each step's values to real fields as the step is completed, add Review Step (picklist), Started On,
  Submitted On, Days Open and Overdue, rename status Closed to Withdrawn, and put a Path on the record page. Then check the
  other workspaces (Triage, Investigation, Disposition, Field Action) for the same gap. Lou: needed for analytics and reports.
- **Approval matrix.** Neither CQ's Approval Matrix (no Field Action record type) nor CQ's approval engine (no CQAPR Approval
  Setup record for Field_Action_Review__c) knows the object; our code builds the CQ Approval from the coordinator's picks among
  the "Field Action Committee - " job functions. Lou: we need our own approval matrix for now.
  Checked 24 Nov (read only): the CQAPR Approval Setup custom metadata shows a **New** button in Setup, so the org can add its
  own setup record. Plan: our own matrix object (seats per step, chosen by risk level, recall class or emergency) plus a CQAPR
  Approval Setup record for Field_Action_Review__c whose steps flow reads it, so CQ's engine handles submit, emails, locking and
  field updates. Waits on Lou's signature review.

## Work queue
- **Roadmap (Lou, 25 Nov): CQ's core modules, in order.** Nonconformance (finish over the Thanksgiving break), then
  Complaints, CAPA, Audits, Controlled Documents, Training, Personnel. Finishing NC means the whole path: Event Review's
  decision actions (create the NC or Complaint, and the Safety Event), Triage, Investigation and Disposition each getting
  the Field Action treatment (step and progress on the record, CQ.AI's suggestions kept beside the choice with a reason,
  page layout), then the NC's own close. Start with a gap survey of the three workspaces, as for Field Action.
  Survey done 25 Nov (doc "Nonconformance: Workspace Survey"). **Decision (Lou, 25 Nov): keep building on CQ's NC, not a
  ground-up NC of our own.** Use CQ's unused NC fields where they fit (Risk Justification, Conclusion, Risk Assessment,
  Recommended Action, Invalid Nonconformance, Corrective / Preventive Action) before adding our own.
  **Report a Nonconformance (built 25 Nov: CqNcReport + CqNcReportTest 10/10; LWC cqNcReport is the launcher and cqNcReportModal the LightningModal popup; placed in the Quality Management and Field Actions utility bars and on the Report_a_Nonconformance tab, which opens the popup on arrival; CQAI_Quality grants the tab and the CqNcReport/CqEventParts classes; mockup "Report a Nonconformance Mockup"). Still to do: the NC list view button (WebLink to /lightning/n/Report_a_Nonconformance) could not be created through the API and needs adding in Setup; browser test of Create (does CQ's submit move it to Triage?), Merge, files and the part picker.** A two-step popup anyone can
  use: describe it, Next, then check and Create and Send to Triage (submitted on create, no Submit task). Step 1: a
  one-line Possible Duplicate check under the description while typing (lot numbers in the text matched against open NCs'
  impacted lots, no AI; Merge or Create; merging skips step 2). Step 2 repeats the check only when CQ.AI finds a lot step 1
  missed. Step 2: CQ.AI Suggested Description (CQ's CQSS_Paraphraser prompt, Use This / Keep Mine) and CQ.AI Filled In
  6 Fields (Title, Part, Lot, Defective Quantity, Type, Failure; one Edit).
  CQ.AI runs on Next (5W2H, part and lot, paraphrase and title, side by side); measure the wait in dev and only start it
  early (on a pause) if it feels slow. Nothing is saved before Create. CQ's 5W2H extractor and risk action both work on unsaved values (tested in dev).
  Risk and the lot hold stay in Triage, not creation.
  **Title rule (Lou, 25 Nov):** item, defect, where found ("Balloon burst below rated pressure at final inspection"); no
  lot, quantity, date, part number or names; under 80 characters; sentence case, no full stop; the product's own words.
  Written by our own prompt, not CQ's 5W2H "What".
  **Type (Lou, 25 Nov):** all three stay. Customer NCs are used on purpose as a light complaint record. CQ.AI rule:
  Customer if it came from the field (hospital, patient, procedure, returned device), Supplier if found at incoming
  inspection on supplier material, otherwise Internal.
  **Accuracy test (25 Nov, 30 dev NCs, nothing saved):** lot 4/4 where written, never invented; quantity right every
  time it was in the text; part exact 1/30 (generic words otherwise), so part comes from the lot record; type 21/30 (all
  4 Customer missed: needs the rule above); Failure from the extractor's DEFECT, not 5W2H How; titles from CQ's
  default 0/30 to the rule, with the rule as the entity definition 10/10 in form, 5/10 with where found (add FOUND AT
  when missing). One CQ entity extraction call with our own entity definitions replaces 5W2H and a new prompt
  template; CQ's 5W2H action handles only one input per call.
  Build notes: Merge (addToExisting) posts the report on the NC's feed and gives its owner a task (people only, not queues);
  CQ.AI's suggestions are kept as a note "CQ.AI at creation" and the words as reported as a Quick NC "As Reported" row;
  files are held in the popup and attached after Create or Merge (3 MB each). CQ's Submit did not move a new NC to
  Triage when run from anonymous Apex (nor an existing Draft NC); check from the popup in the browser. If it stays in
  Draft the done screen says so, and Triage's start submits it anyway.
- **@ in the Report a Nonconformance description (Lou, 25 Nov; built, new NCs only; standardise later if it works).**
  Optional: typing @ then the start of a lot or part lists up to five lots (number starts with the term, each with its
  part) and five active parts (number or name contains it), just under the box; arrows, Enter or Tab, Esc; click works.
  Picking writes "lot L26-0915" or the part number into the text and records the real record; on Next a pick still in
  the text wins over what CQ.AI read (a lot brings its part). Plain typing works as before. CqNcReport.mentions.
  Parts are ranked: number or name starting with the term first, then parts that have lots. Spellcheck is off on the
  description box (lot and part numbers were underlined). The list opens at the @ (mockup "At-Cursor Picker Mockup"),
  one line per item, moved left near the right edge, above the line when the popup has no room below (it never
  makes the popup grow or scroll; a long list scrolls inside itself); a hidden copy of the box finds where the @ is.
- **New NCs go straight to Triage (Lou, 25 Nov; built).** Every new NC, wherever it is created, skips Submit: an
  after-insert trigger (CqNcAutoTriage) sets Record Stage Triage, Submitted By the creator, and the owner the queue
  (the Department's Queue Id, else CQ's Default Queue Name setting, else the CQ Nonconformance Default Queue).
  Report a Nonconformance defers it until its children are saved, then sends it. Left alone: Quick Log NCs and loads by
  users with CQ's Data Migration permission. Why not CQ's Submit: setting Activity Code 'submit' from Apex or the API is
  not processed in this org (tested on NC-000192 and fresh NCs, several ways; CQ's Submit quick action needs an
  e-signature and runs in CQ's own component). The workspace's startTriage now moves an older Draft NC with the same
  code and keeps its owner. Follow-up: confirm with CQ whether an API-level Submit exists, and whether CQ's own
  audit trail (NC Record Activity) should get a "submitted" row.
  Open (Lou, 25 Nov; resolve later, it will come up): imported Draft NCs. A load by a user with CQ's Data Migration
  permission keeps its Draft NCs in Draft (CQ's own rule for imports); a load by anyone else sends them to Triage and
  the queue. NCs imported already past Draft keep their stage either way. Decide whether migrated Draft NCs should
  stay in Draft or go to Triage (a one-line change in CqNcAutoTriage.afterInsert).
  Rule (Lou, 25 Nov): people using our UI do not use CQ's standard screens for NCs. So CQ's own create paths (the
  New button, the "Report NC" list button / NC wizard, Report Issue) should be replaced by Report a Nonconformance or
  hidden for regular users. Known risk if they stay: CQ's wizard opens an edit screen after the save, and by then the
  NC belongs to the queue, so a non-admin creator likely cannot save it (untested).
  Packaging (Lou, 25 Nov): CQ's standard NC screens are an Enterprise-tier feature; customers on our UI who want
  them upgrade to Enterprise. Our tier ships with CQ's standard create paths replaced or hidden.
  New button (built 25 Nov): Aura wrapper cqNcNewOverride (standard button overrides take Aura) holds LWC
  cqNcNewRouter, which opens the Report a Nonconformance tab, or CQ's wizard (SQX_Nonconformance_Wizard) for users
  with the custom permission CQAI_CQ_Standard_NC_Screens (Enterprise tier; not assigned to anyone). The object's New
  override stays CQ's compliancequest:SQX_Action_Override, which reads CQ's CQ Action Override custom metadata; our
  record CQAI_Nonconformance_Create (create, Order 0, c:cqNcNewOverride) sits beside CQ's CQUI_Nonconformance_Create
  (cqext:cquiNonconformanceCreate). Untested which record CQ picks when two match: if CQ's still opens, deactivate
  CQ's record (IsDeactivated) or switch the object override in Setup to c:cqNcNewOverride. Still to do: remove the
  "Report NC" and Import list buttons for our tier.
- **NC ownership and access (Lou, 25 Nov; decided, not built).** The rule: only the owner can edit; everyone else is
  view only. Today the triage workspace has no such check: it shows to anyone who can open an NC in Draft or Triage and
  saves as the user, so read-only users hit permission errors partway through, and anyone with edit access (admins,
  CQ shares) can triage, take ownership from the queue on Complete, and leave a partial triage when CQ refuses the move.
  Findings: CQ submit hands the NC to a queue (dev: CQ Nonconformance Default Queue, 7 members); CQ's Department has a
  Queue Id (blank in dev) that appears to route by department; CQ's Qualified Owner rule already requires Can Own NC to own
  an NC from Triage on. Salesforce admins can override, as always (Lou). Triage Inbox (Lou, 25 Nov): Submit puts the NC in Triage owned by the queue; a Triage Inbox (Quality Management home) lists them; queue members click "Take Ownership" (that wording for now), which lets them triage it. No release back to the queue: it must be reassigned, and for now queue members reassign themselves (supervisor rules later if it becomes a problem). Take Ownership takes one NC and leaves you on the inbox: the row moves to My NCs, a message says it is yours with an Open link, and one already taken says who took it (Lou, 25 Nov). Taking several at once is for a future version. Open: a supervisor override, read-only users adding a note
  or photo, the reporter's view, the draft on owner change, routing rules beyond department (Type, Site, part family),
  and applying the same check to Disposition, Investigation and agent actions. Mock the read-only states before building.
- **Later (Lou, 24 Nov): Field Action numbers kept current straight away.** For now a nightly job and a Refresh Numbers
  button work them out. Records change in many places (workspace, tasks, cases, ERP loads), and the numbers being right
  matters, so move to updating on change, handing large loads to a background job (bulk limits, record locks).
- **Field Action record fields (24 Nov, built).** 26 fields (doc "Field Action: Proposed Fields"): Workspace Step, Started On,
  Days Open, Days to Notify, Check Overdue, the scope, notification and recovery numbers, Numbers Updated On, CQ.AI's suggested
  action, depth and check level, and Strategy Reason. Numbers: CqFieldActionNumbers (one place), the nightly
  CqFieldActionNumbersJob (2:17 am) and Refresh Numbers in the workspace header. Strategy needs a reason when it differs from
  CQ.AI; the audit trail shows the latest confirm against CQ.AI's suggestion. Page layout rebuilt in sections. Status unchanged;
  regulatory report fields wait for that step. Note: the audit trail entry is read from the record, so only the latest
  confirm shows; a log of every confirm would need its own rows (later, with the approval matrix work if wanted).
- Field Action Review: page layout done 24 Nov (Progress, Checklist, Recommendation and Committee sections). Lou: no Path,
  related lists as they are, no field history (the Audit Trail is the record). FAR-0004 restored. Design system on hold.
- Field Action Review and the other screens onto the shared grey `.cq-card` (list in cqstyles_centralising.md).
- Sorting rollout: Triage Assistant (5 tables), then the rest.
- Customers and Tasks table rework (Recovery).
- Case page: Response by Lot.
- "Not Sent" status for customers added automatically from shipments (decide first; reminder set for 25 Nov).
- FA-0001 Notifications: 5 acknowledged without the submit flow ("0 submitted to Recovery").
- Data cleanup: CoC documents, and the 11-account roster.
- Salesforce bell notifications.
- **Quality Management home and Triage Inbox (Lou, 25 Nov; mockup "Triage Inbox Mockup"; built).** Quality Home tab
  (cqQmHome, CqQmHome) is the Quality Management app's landing tab: one card per process (unbuilt ones "Coming Soon"),
  the Nonconformance card with a line per role (Triage: waiting, yours; My NCs: past triage, overdue; else Reported by
  You), each opening its view of the Triage Inbox. Waiting for Your Approval (CqApprovals): open CQ approval steps
  assigned or delegated to the person, any object; Approve and Reject open the signature seat (c-cq-sign-seat) in a
  popup and sign first through CqEsign, then act on the step as the FA committee does; only objects with a signature log
  (CqApprovals.SIGNABLE, kept in step with CqEsigBridge) can be signed there, others say "Approve on the record". Needs
  You: records, not workflow tasks (overdue, due within 7 days, triage waits of 3+ days). Triage Inbox tab
  (cqTriageInbox, CqTriageInbox), list view style: Waiting for Triage (queues you are a direct member of; admins see all
  NC queues) with flags (possible duplicate on the lot, repeat on the part in 90 days) and Take Ownership one at a time
  (Can Own NC required, stays on the page, says who took it first); My NCs by stage with the nearest due date, Reassign
  (owner only, to queue members who can own NCs, note to the feed) and Continue Triage / Open. Open: members through
  public groups or roles are not followed; investigation and disposition roles and My Investigations; owner-only
  editing.
- **cqStyles: small buttons sit low (Lou, 25 Nov; for when the design system resumes).** `cq-btn-sm` cuts the buttons'
  0.1875rem bottom lift to 1px, so the text sits low in the pill, and the filled button is 1px shorter than the outline
  one (no border). Quality Home's approval card overrides both locally (cqQmHome.css, `.aacts`); fix `cq-btn-sm` in
  cqStyles and remove the override.
- **NC record page in Disposition / Investigate: one workspace at a time (Lou, 27 Nov; mockup "Disposition /
  Investigation Switch Mockup"; built: cqNcWorkspaces).** A tab switch (the selected tab filled light blue, no due dates):
  custom permissions CQAI_Can_Investigate and CQAI_Can_Disposition, each in its own permission set (CQ.AI Can
  Investigate / CQ.AI Can Disposition, with its workspace's Apex); administrators (Modify All Data) always see both.
  Investigation opens first; one role shows just its tab; neither shows a note. Each workspace loads on first open and is
  kept. Page state c__part = investigation or disposition opens a side. To finish: on CQEA_NC_Record_Page1, replace the
  Disposition workspace (header, Stage = Disposition_Investigate) with CQ.AI NC Workspaces (Lou in App Builder), and
  assign the permission sets. Later: the home page's Investigation and Disposition lines open their side.
  Update 27 Nov: the tabs became a small Change Workspace link at the bottom right of the workspace header (cqWsShell asks
  the page with the cqworkspacehost event; only cqNcWorkspaces answers). The App Builder swap is done.
- Investigation, What Changed (built 27 Nov, mockup "What Changed Side-by-Side Mockup"): the chart and the table side by
  side; Look back is a link on the chart with a menu (14/30/60/90 days); the table shows 5 changes a page (cqStyles
  cq-pager), one line each with an ellipsis, numbered; each number marks the change on the chart with a label for the kind
  of record and a bubble on hover or focus; other pages' changes are faint dots. Page-local styles (wc-*) to fold into
  cqStyles with the design-system work. Next: go through the other Investigation steps, then e-signature on Complete
  Investigation.

## Find the Cause: side by side (27 Nov, built)
- Hypotheses tab is a list (left) beside the one being tested (right, "Testing H1 · Category"), in four steps: 1 Evidence (cqStyles table: Kind, What It Shows, Source, Supports It?), 2 Could This Be the Root Cause?, 3 How Do You Know?, 4 Decide (Rule Out / Mark Confirmed / Reopen, off until How Do You Know is filled).
- One "+ Add Evidence" button. Link a CQ Record folded into the test popup: a Check Records test can attach the CQ record it checked (Record_Id__c on the same Evidence row). Old CQ Record rows still show. 5 Why: "+ Add Evidence" per why.
- What Stands Out removed from all five tabs. Root Causes keeps the "still Open" warning in its save note; an infobox shows when there is no root cause yet.
- Later: optimize the Add Evidence popup (suggested records, search by title).

## Footer arrows and suggestions card (27 Nov, built)
- cqWsShell: Back and Next are arrow icons side by side at the bottom right of every workspace footer, after the blocker and the step's own buttons. A Next that names an action (Submit to Committee, Complete Triage) shows as its button and greys the forward arrow. Page-local CSS (.navarrows, .arrow) while cqStyles is on hold: move into cqStyles later.
- Find the Cause: CQ.AI's suggested hypotheses moved into a card under the Hypotheses list (+ Add as Hypothesis link, Not Relevant). Rule Out / Mark Confirmed kept as buttons.
- Still open: the footer standard (one blue button, saves in the footer, tab-aware Next), Decide as a menu.
- 27 Nov, later: the footer is two rows at the right: the blocker and the step's own buttons (Save Actions, Save Root Causes, Complete Investigation, a named Next) on top, the Back / Next arrows underneath. The row hides when it has nothing in it.
- Tidy next time cqInvestigationCause.js is deployed: cantSaveRoots / saveRootsLabel / handleSaveRoots are unused (Save Root Causes stayed in the workspace footer); remove them and their comment.
- 27 Nov: Glance cards (Investigation and Disposition) match: the CQ.AI card title is 15px (--cq-fs-body) like The Problem's title, and The Problem's text is 13px muted (--cq-fs-meta) like the CQ.AI card text. Page-local rules (.cq-cols.wide .cq-ai-head, .cq-cols.wide .cq-prob) in both workspaces. When cqStyles resumes: decide whether .cq-ai-head is 15px everywhere and .cq-prob is muted everywhere, put that in cqStyles, and delete the page-local rules.

## NC actions are corrections only (Lou, 27 Nov)
- Decision: an NC fixes what is wrong now. Corrective and preventive actions (removing the cause) go to a CAPA, where CQ checks they worked; effectiveness is developed in CAPA, not NC. The Investigation's Actions step adds Corrections only (server refuses a new non-correction plan); plans of another type made on CQ's own screens still show and can be edited.
- Escalate to CAPA opens CQ's own Escalate CAPA quick action on the NC in a new tab (/lightning/action/quick/...cqext__cqui_Escalatecapa). Not yet tried in a browser.
- Still to do: "Link to an Open CAPA" (mocked, not built). Page-local CSS .capabox / .capatitle in cqInvestigationWorkspace.css while cqStyles is on hold.
- Next: Implement, two views (NC owner on the NC; assignee on the CQ action) and the Quality Home tasks (Complete, Verify, Overdue; extension approvals). Optional "Procedure to Follow" card (linked controlled document, PDF thumbnail, Salesforce file viewer); check first whether CQ records or watermarks document views. Mockups: Find the Cause Side-by-Side canvas, boards Actions, Implement, Correction, HomeTasks.

## Implement: the assignee's Correction workspace (27 Nov)
- Built: cqCorrectionWorkspace (on the CQ action) with CqCorrectionWorkspace, CqActionSignable (Action added to CqEsigBridge.SIGNABLE; not yet to CqApprovals.SIGNABLE, which is for approvals from Quality Home). Complete (implementation_complete: Remark, Completion Date) and Skip (implementation_skip: Activity Comment) as CQ's own actions; Request Extension opens CQ's quick action (setting the extension fields directly does nothing: CQ routes extensions through cqaprExtensionRequest).
- Procedure to Follow: a Current controlled document linked on the NC or named in the correction's title or description (document number pattern). PDF (secondary) first, else the primary file; thumbnail from the Salesforce rendition; the file opens in Salesforce's viewer only when CQ's default Print and Download Control allows both, else CQ's document page.
- The bundle was created through the Tooling API with targets only: the object restriction (compliancequest__SQX_Action__c) in the local js-meta.xml is not in the org yet. Lou adds the component to the Action record page in App Builder.
- Next: the NC owner's view on the NC (all corrections, reminders, reassign, verify) and the Quality Home tasks.
