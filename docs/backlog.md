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
