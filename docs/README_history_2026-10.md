# Complaint Investigation Report + PHR QMS Records Panel

Everything is source-format (SFDX). Nothing in it has been compiled or run: it was written and statically reviewed only, with no deploy or validation against any org. **Run a check-only deploy in a sandbox first.**

## What is in it
- **Agent reference** (`reference/`): `PHR_Agent_v12.agent` script and `AGENT_SETUP.md` (topics, actions, prompt template, PDF action) for the parts that cannot be deployed as metadata here.
- **Custom fields:** `Draft_Investigation_Summaries__c` (rich text, written by the agent; the PDF reads it) and the older `Draft_Investigation_Summary__c` on Complaint and `Has_NC__c` on Part, so they no longer need to be created first.
- **Associated Items card now has collapsible sections** (all open by default, Expand all / Collapse all, chevron toggles, count and a short hint when closed).
- **PDF report** (Visualforce `ComplaintInvestigationReportPDF`, controller `ComplaintReportPDFController`): saved Draft Investigation Summary, CQ Task progress strip (page 1), associated items with a Lot Match column (page 2), CQ Tasks table and related investigations (page 3).
- **Associated Items card** (LWC `associatedItemsReport`, Lightning type `associatedItemsReportType`, Apex `AssociatedItemsReportAction` and info classes): adds Related Investigations and the line-item Lot Match column.
- **Draft summary agent classes**: `ComplaintInvestigationGrounding` (now includes CQ Tasks, Lot Match and Related Investigations), `GenerateDraftInvestigationSummary`, `SaveDraftInvestigationSummary`, `FindComplaintForSummary`, `GenerateAssociatedItemsReportAction`.
- `ComplaintTaskProgress` helper plus tests for every class.

- **PHR QMS Records panel** (LWC `phrQmsRecordsPanel`, Apex `PhrQmsPanelController`, `PhrQmsRelatedRecordsAction`, `PhrQmsPanelControllerTest`): panel for the Product History Review or Complaint record page. Lists Nonconformances, CAPAs, Change Orders, Inspections and Related Investigations tied to the Complaint part (assembly components included) and lot, with a lot search box, Previous/Next paging, Part Number, Status and Created columns. Ranking: Part + Lot match first, then Lot, then Part; newest first within a group, with a small boost for records created in the last 30 days and for open statuses; the top three relevant rows per section are highlighted. **Create Related Records** adds one Related Products Review row per ticked record: NC and CAPA via their lookups; Change Order and Inspection as Reference Type plus the record number in `Other Reference Number`. Records already on the PHR are flagged and skipped. Investigations are view-only (the Reference Type picklist has no Investigation value). The invocable action's `Apply` mode additionally creates Linked Investigations on the Complaint; `Preview` (default) writes nothing. The standard PHR record page is managed, so clone it in Lightning App Builder before adding the panel.

## Rules built in
- Complaint's own investigations are excluded (matched on the Investigation's Complaint lookup and on Source Id).
- A task is overdue when it is not Complete and its Due Date is before today, whatever its status.
- Line-item Lot Match is the simple version: counts of Nonconformances and Inspections carrying the Complaint's lot that are filed against that component part. The bill of materials has no lot data, so this does not prove a component came from that lot. Blank when the complaint has no lot.
- Related investigations: same part (primary or component) or same lot, newest first, max 50, within the created-date range.

## Prerequisites in the target org
- ComplianceQuest managed package (`compliancequest__`, `cqext__`) with Complaint Steps, Investigations, Inspections, Nonconformances, Assemblies.
- The two custom fields are included in the package.
- Agentforce enabled (the Lightning type targets `lightning__AgentforceOutput`).
- The Prompt Builder template `Complaint_Draft_Investigation_Summary` and the agents themselves are **not** in this package; see `reference/AGENT_SETUP.md`.

## Open in VS Code
Salesforce DX project (Salesforce Extension Pack). `Ctrl/Cmd+Shift+P` -> **SFDX: Authorize an Org**, then right-click `manifest/package.xml` -> **SFDX: Deploy Source in Manifest to Org** (or run the commands below). `.vscode/extensions.json` lists the recommended extensions. Commit everything in this folder to GitHub; `.gitignore` already excludes caches and logs.

## What is in this version (2026-10-17)

- **Relevance model** (`PhrQmsRelevance`, `PhrQmsRelevanceSettings`, `PhrQmsRelevanceTest`): ranks related records by product link, symptom and currency (Red / Yellow / Grey chips, 0 to 100 score, Top / Next / Set aside). `PhrQmsPanelController` uses it when `PhrQmsRelevanceSettings.useNewModel` is true. Set it to `false` and redeploy that one class to return to the original ranking. All weights are placeholders in that class.
- **New agent output renderers** (Lightning types + LWCs + Apex data classes): `phrLeadPackage` (lead package and set-aside list), `phrMissingData` (missing-data check) and `phrChecklist` (checklist suggestions). They only display data. No action returns these data classes yet, so they will not appear in the agent until an action is built for each.
- Unchanged: the agent action `PhrQmsRelatedRecordsAction`, the summary, the PDF.

## Deploy from Visual Studio Code (dev sandbox)

1. Open this folder in VS Code (File > Open Folder). Install the Salesforce Extension Pack if prompted.
2. Ctrl/Cmd+Shift+P > **SFDX: Authorize an Org** > choose **Project Default** and a sandbox login, and sign in to the dev sandbox (cqse-golden--dev).
3. Right-click `manifest/package.xml` > **SFDX: Deploy Source in Manifest to Org**.

Or from a terminal in this folder:

```
sf project deploy start --manifest manifest/package.xml --target-org <dev alias> --test-level NoTestRun
```

`NoTestRun` is allowed in a sandbox. To run the tests afterwards:

```
sf apex run test --class-names PhrQmsRelevanceTest PhrQmsPanelControllerTest PhrQmsAutoCreateTest --target-org <dev alias> --result-format human --wait 10
```

The Lightning types, their components and the Apex data classes deploy together in one package, so no second step is needed. The dev org already holds these classes and components (deployed 2026-10-17); a redeploy overwrites them with identical content.

Do not deploy to production without a validate run first.

## Deploy
```
sf project deploy validate -o <alias> --manifest manifest/package.xml --test-level RunLocalTests
sf project deploy start    -o <alias> --manifest manifest/package.xml --test-level RunLocalTests
```
Optional (outside `force-app`, so not part of the manifest deploy): `optional/permissionsets/Complaint_Investigation_Report_Access.permissionset-meta.xml` grants class and page access; deploy it separately and assign it.

Several tests insert Complaints, Parts, and Nonconformances using the sandbox's required fields. If your org has extra required fields or validation rules, adjust the `@TestSetup` data.

## Use
- Preview in a browser: `/apex/ComplaintInvestigationReportPDF?id=<ComplaintId>&format=html`
- PDF: drop `format=html`. Optional `startDate` and `endDate` (yyyy-MM-dd).

## Update the Prompt Builder template
Add to the template instructions so the model uses the new sections:
> The data includes "## CQ TASKS" (progress and overdue tasks), "Lot Match" on assembly line items, and "Related Investigations" with their source and match reason. Summarize task progress and overdue tasks, mention related investigations on the same part or lot (the complaint's own are excluded), and note component parts that have records on the complaint's lot. Do not claim a component came from the lot.
