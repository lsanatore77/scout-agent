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
