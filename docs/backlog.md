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

## Work queue
- Field Action Review and the other screens onto the shared grey `.cq-card` (list in cqstyles_centralising.md).
- Sorting rollout: Triage Assistant (5 tables), then the rest.
- Customers and Tasks table rework (Recovery).
- Case page: Response by Lot.
- "Not Sent" status for customers added automatically from shipments (decide first; reminder set for 25 Nov).
- FA-0001 Notifications: 5 acknowledged without the submit flow ("0 submitted to Recovery").
- Data cleanup: CoC documents, and the 11-account roster.
- Salesforce bell notifications.
