# CQ.AI Permissions Log

What a user needs to run the CQ.AI app, kept as we build. Add a line to the **Change Log** whenever a class, object, field, page, credential, agent or CQ object we read or write is added or changed, and update the inventory below it.

Sources: the repo (`force-app/main/default`) and the dev org (cqse-golden--dev), 15 Nov 2026. All our Apex runs `with sharing` except where marked, so users also need the CQ record access their CQ role gives them.

## Proposed Permission Sets

One base set for everyone, one per module, one for admins. Assign them through a permission set group per role.

| Permission set | Who | Status | Covers |
| --- | --- | --- | --- |
| CQ.AI Base | Every CQ.AI user | To build | Ask CQ.AI (AskCq* classes, the Ask_CQ external credential principal), shared helpers (CqRichText, CqLotStock), our fields on CQ objects that every module shows |
| CQ.AI Quality (NC) | Triage, disposition and investigation users | To build | Triage, Disposition and Investigation workspaces: CqTriage*, CqDispositionWorkspace, NC fields Triage_*, write access to the CQ objects below |
| CQ.AI Approvals | Anyone who submits or approves through our screens | To build | CQ Approval and Approval Step read and edit (approve or reject a step), CqFarCommittee and the shared approval service |
| Field Actions User | Field action and recall team | Exists (`Field_Actions_User`) | Field Action objects, apps Field Actions and Signal Detection; check against the inventory: Apex classes are not in it yet |
| PHR Lead Access | Product History Review users | Exists (`PHR_Lead_Access`) | PHR_Lead__c, PHR Apex actions, PhrLeadReportPDF page |
| Complaint Investigation Summary Access | Complaint investigators | Exists in the org only, not in the repo | Draft investigation summary on complaints |
| CQ.AI Admin | Admins | To build | Settings (PHR Report Setting), Signal Rules, Signal Job scheduling |

Agent access is separate: each Agentforce agent has its own generated set (below), assigned to the users who chat with it.

## Inventory

### Apex Classes Users Must Be Able to Run

Every class a component or agent calls (`@AuraEnabled`, `@InvocableMethod`, `@RemoteAction`) needs class access in a permission set.

| Area | Classes | Set |
| --- | --- | --- |
| Ask CQ.AI | AskCqAgents, AskCqService, AskCqWorkspaceController | Base |
| NC triage | CqTriageController, CqTriageAssistant, CqTriageContainment, CqTriageDraft, CqTriageLinks, CqTriageNext, CqTriagePhoto, CqTriageRisk | Quality |
| NC disposition | CqDispositionWorkspace | Quality |
| NC investigation | CqInvestigationWorkspace, CqInvestigationChanges, CqInvestigationHistory | Quality |
| NC triage, the repeat | CqTriageRepeat | Quality |
| Agents' context | CqQualityAgentContext (CQAI_Quality), CqFieldActionAgentContext (CQAI_Field_Action) | the agent's set |
| Field actions | CqFieldActionReview, CqFieldActionScope, CqFieldActionStrategy, CqFieldActionLots, CqFieldActionRecovery, CqFieldActionTasks, CqLotStock, CqFarCommittee | Field Actions User (+ Approvals for CqFarCommittee) |
| Signals | CqSignalJob | Admin |
| PHR | PhrLeadListController, PhrLeadSelectController, PhrQmsPanelController, PhrChecklistAction, PhrLeadAddAction, PhrLeadAddSelectedAction, PhrLeadPackageAction, PhrLeadReportAction, PhrMissingDataAction, PhrQmsRelatedRecordsAction, PhrTemplateReportAction (+ their data classes) | PHR Lead Access |
| Complaints | FindComplaintForSummary, GenerateDraftInvestigationSummary, SaveDraftInvestigationSummary, AssociatedItems* , GenerateAssociatedItemsReportAction | Complaint Investigation Summary Access |
| Dev only | CqEsigTest (pages CqEsigTest, CqEsigCallback) | none: remove before release |

`without sharing` (see all records regardless of the user): ComplaintReportPDFController, PhrLeadReportController, PhrReportData, PhrReportRenderer, AssociatedItemsReportAction, GenerateAssociatedItemsReportAction. Review before release: each should check the user can see the record it reports on.

### Our Objects

| Object | Users need | Set |
| --- | --- | --- |
| Field_Action__c, Field_Action_Review__c, Field_Action_Lot__c, Field_Action_Hold__c, Field_Action_Customer__c, Field_Action_Scope_Change__c | Read, Create, Edit | Field Actions User |
| Lot_Shipment__c, Lot_Stock__c | Read (loaded from the ERP) | Field Actions User; the ERP integration user needs Create and Edit |
| Signal__c, Signal_Event__c, Signal_Rule__c, Quality_Event__c | Read; Signal_Rule__c Edit for admins | Field Actions User / Admin |
| PHR_Lead__c | Read, Create, Edit | PHR Lead Access |
| Investigation_Hypothesis__c, Investigation_Change__c | Read, Create, Edit (all fields) | Quality |
| Investigation_Not_Relevant__c | Read, Create, Delete (all fields) | Quality |
| PHR_Report_Setting__mdt | Read | Base |

### Our Fields on CQ Objects

| Object | Fields | Access | Set |
| --- | --- | --- | --- |
| Nonconformance | Triage_Risk__c, Triage_Path__c, Triage_Notes__c, Triage_By__c, Triage_On__c, Triage_Draft__c | Read, Edit | Quality |
| Nonconformance | Field_Action_Review__c, Field_Action_Review_Reason__c, Field_Action_Review_By__c, Field_Action_Review_On__c | Read, Edit | Quality |
| CAPA | Field_Action__c | Read, Edit | Field Actions User |
| Complaint | Draft_Investigation_Summary__c, Draft_Investigation_Summaries__c | Read, Edit | Complaint Investigation Summary Access |
| Lot Info | Batch__c | Read | Base |
| Part | Has_NC__c | Read | Base |
| Activity (Task) | Recall_Task_Type__c, Field_Action_Customer__c, Lot_Number__c, Units__c | Read, Edit | Field Actions User |

### CQ Objects Our Code Writes

Users get these from their CQ permission sets today; listed so the CQ role we require is clear.

| CQ object | What we do | From |
| --- | --- | --- |
| Nonconformance | Edit (submit, complete triage, triage fields, owner) | CqTriage* |
| Containment | Create | CqTriageAssistant, CqTriageContainment |
| Disposition | Create, Edit (complete) | CqTriageNext, CqDispositionWorkspace |
| Investigation | Edit (open, conclusion, summary) | CqInvestigationWorkspace |
| Action Plan | Create, Edit, Delete | CqInvestigationWorkspace |
| Investigation Tool | Edit (complete) | CqInvestigationWorkspace |
| Response, Response Inclusion | Create, Edit (submit) | CqInvestigationWorkspace (Disposition approval later) |
| NC Investigation (link) | Create | CqTriageLinks |
| Investigation | Edit (draft summary) | SaveDraftInvestigationSummary, PhrReportLink |
| Product History Review, PHR Answer, Related Product | Edit / Create | PHR classes |
| CAPA | Create | CqFieldActionRecovery |
| CQ Approval, CQ Approval Step | Create (submit), Edit (approve, reject, close) | CqFarCommittee via CqApprovalBridge |
| Task | Create | CqFieldActionTasks |
| Files (ContentVersion, ContentDocumentLink) | Create | CqTriagePhoto, PHR report actions |

Read only: Root Cause, Root Cause Code, NC Action, Change Order, Controlled Document, Supplier Deviation, Equipment, Calibration, PLM Part Revision, Assembly and Assembly Line Item, Part, Lot Info, Impacted Part/Lot, Approval Matrix, Job Function and User Job Function, Inspection, Change Order, Controlled Document, Complaint Task, Root Cause, Linked Investigation, assembly and part revision (CQPLM), batch measurements (CQEBR).

### Credentials, Pages, Apps and Agents

| Item | Users need | Set |
| --- | --- | --- |
| External credential Ask_CQ (named credential Ask_CQ_Agent_API) | Principal access | Base |
| Visualforce pages PhrLeadReportPDF, ComplaintInvestigationReportPDF | Page access | PHR Lead Access / Complaint set |
| Apps Field Actions, Signal Detection; tabs for Field Action, Field Action Review, Signal, Signal Event, Signal Rule, Quality Event | App and tab visibility | Field Actions User / Admin |
| Agent CQAI_Quality | Its generated set `NextGen_1bYW40000000IEfMAM_Permissions` | assign with Quality |
| Agent CQAI_Field_Action | Its generated set `NextGen_1bYW40000000ID3MAM_Permissions` | assign with Field Actions User |

## Open Questions

- Which CQ permission sets or licence a CQ.AI user must already hold (for example CQ Standard Extended Permission); to confirm with CQ.
- Whether the ERP load runs as an integration user, and that user's set for Lot Shipment and Lot Stock.
- Org-only items to bring into the repo: Complaint Investigation Summary Access, the Ask_CQ credentials (definitions only, never secrets), the agents' generated sets.

## Change Log

Newest first.

### 15 Nov 2026
- **CqInvestigationCause** (new): Apex access; Investigation Hypothesis Read and Edit; Investigation Evidence Create, Read, Edit and Delete (and its fields); Root Cause Create and Edit (with Cause Role); 5W2H Create and Edit; Investigation Tool Create; Why Create, Edit and Delete; Root Cause Code, Category and Sub-Category Read; read of the CQ records that can be linked as evidence (NC, CAPA, Change Order, Document, Equipment, Calibration, Inspection, Supplier Deviation). Set: Quality.
- **cqInvestigationCause Fishbone tab**: a view of the hypotheses; + Add a Hypothesis uses CqInvestigationChanges.addHypothesis (Investigation Hypothesis Create). Reads the investigation's NC number, title and lot through Lightning Data Service, so users need Read on those NC fields.
- **askCqPopover**: Add to Evidence under an answer (no new access; the page saves it through CqInvestigationCause).
- **CqInvestigationChanges** (new, What Changed step): Apex access; Investigation Hypothesis and Investigation Change Read, Create, Edit; reads change orders, controlled documents, part revisions, assemblies, supplier deviations, lots, equipment and calibrations. The two new objects have no permission set yet: Apex reads and writes them, but users need object and field access in CQ.AI Quality to see them in reports and record pages. Set: Quality.
- **CqTriageRepeat** (new, NC triage): Apex access; uses CqInvestigationHistory (same reads); Investigation Not Relevant Create and Delete with the new Nonconformance field. CqTriageRisk now reads the repeat; CqTriageNext writes the NC's Repeat Of, Repeat Decision, Repeat Decision Reason, CQ's Initiate CAPA and Related CAPA at Complete Triage. Set: Quality.
- **CqInvestigationHistory** (new, Check History step): Apex access; reuses PhrQmsRelevance (Nonconformance, CAPA, Change Order and Inspection Read); reads Investigations, Root Causes, Effectiveness Reviews and the bill of materials; Investigation Not Relevant Read, Create and Delete; Investigation Hypothesis Read. Set: Quality.
- **CqInvestigationWorkspace** (new): Apex access; Investigation Edit; Action Plan Create, Edit and Delete; Investigation Tool Edit; Response and Response Inclusion Create and Edit; Root Cause, NC Action, Disposition and Nonconformance Read. Users also need the User object in the Owner picker. Set: Quality.
- Log started from the repo and the dev org. Two permission sets exist in the repo (Field Actions User, PHR Lead Access); nothing yet covers NC triage, disposition, Ask CQ.AI or approvals.
- **CqDispositionWorkspace** (new): Apex access; Disposition Create and Edit; Impacted Part/Lot and Nonconformance Read. Set: Quality.
- **CqTriageNext**: now creates draft Dispositions at Complete Triage and changes the NC owner from the queue to the person completing triage. Set: Quality.
- **Approvals (planned)**: approving or rejecting in our screens edits CQ Approval Steps and closes CQ Approvals. Set: Approvals.
