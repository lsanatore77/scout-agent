# Scout Agent — ComplianceQuest Product History Review

Salesforce DX project for the **Scout Agent**: an Agentforce agent that does the searching on a
ComplianceQuest complaint's Product History Review (PHR) so the people can do the deciding.

**This branch (`aicomp-2026-11-01`) is the code as deployed to the AI Competition org
(`aiconfigurationworkshoporg06`) on 1 November 2026.** It merges `package-2026-10-23-no-enba`,
`checklist-scrapped-quantity` and `report-chart-apex`. Earlier notes are in `docs/README_history_2026-10.md`.

## What Scout does

| Persona | Job | Main classes | Shown by |
|---|---|---|---|
| Complaint Reviewer | **Missing data check** — one line per check, tick or warning; reads the description for a lot, part, model, date, quantity or patient detail that never reached the fields. Read only. | `PhrMissingDataAction`, `PhrDescriptionCheck`, `PhrMissingCheck`, `PhrMissingDataResult` | LWC `phrMissingData` |
| PHR Assignee | **Relevant records** — one search across the complaint part, its BOM (Part → Revision → Assembly → Line Items), products sharing a component, and the lot; nonconformances, CAPAs, change orders and inspections scored Red / Yellow / Grey. The user ticks what to add; every result is stored as a `PHR_Lead__c`. | `PhrQmsRelevance`, `PhrQmsRelevanceSettings`, `PhrQmsPanelController`, `PhrLeadPackageAction`, `PhrLeadSelectController`, `PhrLeadAddSelectedAction`, `PhrLeadRecord`, `PhrLeadSection`, `PhrLeadSelection`, `PhrLeadPackageData` | LWCs `phrLeadPackage`, `phrLeadSelect`, `phrLeadLists`, `phrQmsRecordsPanel` |
| PHR Assignee | **PHR Summary** — grounded on the complaint, PHR, tasks and associated items via a Prompt Builder template; saved to the complaint, the PHR and the primary investigation. | `GenerateDraftInvestigationSummary`, `SaveDraftInvestigationSummary`, `ComplaintInvestigationGrounding`, `FindComplaintForSummary`, `PhrSummarySections`, `PhrSummaryText`, `SummaryRichText`, `SummaryHtmlRepair` | — |
| PHR Assignee | **PDF report** — rendered from the XHTML template on controlled document `PHR-TEMPLATE-001` (fallback: static resource `PHR_Report_Default_Template`); attached to the complaint and the primary investigation. | `PhrTemplateReportAction`, `PhrReportRenderer`, `PhrReportData`, `PhrReportSettings`, `PhrReportLink`, `ComplaintTaskProgress` | — |
| PHR Assignee | **Checklist** — answers every PHR checklist question from the relevant-record search and plain formulas (scrap rate first); saves only the sure answers, only after confirmation. | `PhrChecklistAction`, `PhrChecklistItem`, `PhrChecklistResult` | LWC `phrChecklist` |
| Investigator | Sees the relevant records and summary on the primary investigation and can generate a fresh report there. | `PhrLeadListController`, `PhrRecordContext` | LWC `phrLeadLists` |
| Triage | Complete Triage with the draft summary shown alongside. | `PhrCompleteTriageController`, `TriageDraftSummaryController` | LWC `triageStepsWithSummary` |

### Rules worth knowing
- **Scoring**: three criteria (product link, descriptor match, recency). Criteria met set the colour (3 Red, 2 Yellow, 1 Grey); points (0–100) rank within a colour. A record in the complaint's lot is always kept; others need two of three, and records on a component or another product must also match the descriptor. Set-aside records keep a reason. All weights and thresholds are constants in `PhrQmsRelevanceSettings` (`MAX_ROWS = 200` newest records per object).
- **Lot matching** is by lot-number text: the complaint's Lot Number field and its Lot Info name, against the record's own Lot Number. Lot Info also supplies the manufacture date for the optional date window (PHR Report Setting).
- **Scrap rate** (checklist): sum of `Actual Quantity Disposed` on dispositions with Type = Scrap, Status = Complete, Part = the complaint's own part (components do not count), ÷ 2,000 × 100, against a 5 % threshold.
- **Primary investigation**: CQ sets it when the investigation is created from the complaint's Investigation step. Summary and report writes go only to that investigation.
- Scout never changes a record without the user confirming in the conversation.

## Metadata in this package
- Apex classes and tests (`force-app/main/default/classes`)
- LWCs and Lightning types for agent output (`lwc`, `lightningTypes`)
- Custom object `PHR_Lead__c` and its permission set `PHR_Lead_Access`
- Custom metadata type `PHR_Report_Setting__mdt` with the `Default` record (report titles, template document, summary sections, date window)
- Custom fields on Complaint (`Draft_Investigation_Summaries__c`) and Part
- Static resource `PHR_Report_Default_Template` (fallback report layout)
- Agent scripts (`PHR_Agent_Script_TickList_v25*.txt`, `Scout_Checklist_Agent_Script_v1*.txt`) — the `_AICompetition` copies are the ones in that org
- `reference/phr-report-template-v2.xhtml` — the current report template to upload to `PHR-TEMPLATE-001`
- `reference/AGENT_SETUP.md` — the pieces that are not metadata (agents, topics, prompt template)

### Superseded — still deployed, no longer used
Kept so the branch matches the org. Removing them is a separate, tested deploy.
- `ComplaintLeadRanking` (+ test) — first scoring model, replaced by `PhrQmsRelevance`.
- `PhrLeadReportAction`, `PhrLeadReportController`, `PhrLeadReport*Test`, `ComplaintReportPDFController` (+ test), pages `PhrLeadReportPDF`, `ComplaintInvestigationReportPDF` — the Interim Report (Visualforce PDF), replaced by the template report.
- `PhrQmsRelatedRecordsAction` — preview/apply action, replaced by `PhrLeadPackageAction` + `PhrLeadAddSelectedAction`.
- `PhrLeadAddAction` (+ test) — replaced by `PhrLeadAddSelectedAction`.
- `GenerateAssociatedItemsReportAction` (+ test), LWC `associatedItemsReport`, Lightning type `associatedItemsReportType` — early Associated Items PDF and card. `AssociatedItemsReportAction`/`*Info`/`*Data` are still used by the summary grounding.
- Agent scripts v11–v24 and `optional/permissionsets/Complaint_Investigation_Report_Access`.
- `docs/*_deploy.md` — notes for two older changes.

## Deploy
From this folder, one command at a time (PowerShell: never paste `<placeholders>`).

```
sf project deploy validate --manifest manifest/package.xml --test-level RunLocalTests --target-org <alias>
sf project deploy quick --use-most-recent --target-org <alias>
```

For a single class change, replace `--manifest …` with `--source-dir <path to .cls>` and
`RunLocalTests` with `RunSpecifiedTests --tests <TestClass>`.

After deploying: upload `reference/phr-report-template-v2.xhtml` to controlled document `PHR-TEMPLATE-001`
(new revision, or a new version of its primary file) and make sure it is Current.

## Not in this package
- Prompt Builder template `Complaint_Draft_Investigation_Summary`, the agents, topics and actions (see `reference/AGENT_SETUP.md`).
- Any eNBA override flows — deliberately excluded; AI Competition does not have them.
- The dev-only flows `PHR_Dev_Set_Primary_Investigation` and `Calculate_Scrap_Rate_From_Scrapped_Quantity` (dev sandbox only, inactive).

## Branches
- `aicomp-2026-11-01` — this branch: AI Competition as deployed.
- `dev-sandbox-current-build` — the dev sandbox (`cqse-golden--dev`), which runs ahead of AI Competition.
- Feature branches (`report-template-v2`, `checklist-scrapped-quantity`, `report-chart-apex`, …) hold the individual changes.
- `main` — last merged baseline; merge to it only on request.
