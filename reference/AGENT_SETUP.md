# Agent setup (manual): what the metadata deploy does not carry

Agents, topics, actions and prompt templates could not be exported from the source org with read-only access, so they are described here to rebuild in Agent Builder / Prompt Builder. Everything they call is in this package.

## 1. Associated Items agent (PHR_Agent / "Scout Agent")
Type Agentforce Employee Agent. Full script of the published version: `PHR_Agent_v12.agent` (in this folder).
- Topic **Associated Items**: "Finds the complaint's primary part, its assembly and line items, and related Nonconformances, Inspections, CAPAs and Change Orders." Instructions: display results with the associatedItemsReport component and the associatedItemsReportType lightning type.
- Action **Associated Items** -> Apex `AssociatedItemsReportAction`. Description: "Runs the apex class to return all records in our search. A user can define a date range before getting the records."
  - Inputs: `targetRecordId` (required), `startDate` and `endDate` (optional, YYYY-MM-DD; pass them only if the user gives a range), plus the legacy optional `primaryPartId`, `nonconformanceIds`, `capaIds`, `changeOrderIds`, `inspectionIds`, `reportTitle`.
  - Output `report`, complex type `c__associatedItemsReportType`.
  - No agent change is needed for lot number, line-item lot match, or related investigations: they come from the Complaint inside the Apex.
- Context variables: currentAppName, currentObjectApiName, currentPageType, currentRecordId.

## 2. Summary agent ("Scout Draft Investigation Agent")
- Topic **Draft Investigation Summary Generator**: "This generates a draft investigation summary for the user."
- Actions (all Apex, no confirmation):
  | Action | Apex class | Purpose |
  |---|---|---|
  | Find Complaint by Number | FindComplaintForSummary | Looks up a Complaint by its number and returns its Id |
  | Generate Draft Investigation Summary | GenerateDraftInvestigationSummary | Builds the grounding text and runs the prompt template; input Complaint Record Id, optional Save to Complaint |
  | Save Draft Investigation Summary | SaveDraftInvestigationSummary | Saves approved text to Draft_Investigation_Summary__c |
- Flow of use: find the complaint, generate the draft, show it for review, then save only after approval (save plain text, not markdown).

## 3. Prompt template
- Prompt Builder template developer name **`Complaint_Draft_Investigation_Summary`**, one text input **`Complaint_Data`** (called as `Input:Complaint_Data`). `GenerateDraftInvestigationSummary` fills it with `ComplaintInvestigationGrounding.buildGroundingText`.
- Not exportable here. Recreate it, then add this to its instructions so the model uses the new sections:
  > The data includes "## CQ TASKS" (progress and overdue tasks), "Lot Match" on assembly line items, and "Related Investigations" with their source and match reason. Summarize task progress and overdue tasks, mention related investigations on the same part or lot (the complaint's own are excluded), and note component parts that have records on the complaint's lot. Do not claim a component came from the lot.

## 4. PDF generation
- Apex `GenerateAssociatedItemsReportAction` renders the page `ComplaintInvestigationReportPDF` for a Complaint and attaches the PDF to it. It is `@InvocableMethod`, so call it from a Flow (the source org used the autolaunched flow `Associated_Items_Competition`, which was not found when this package was assembled and is not included) or add it as an agent action.
- Inputs: Target Record Id (required), optional Report Title, Start Date, End Date. Output: the saved file details.
- Browser preview: `/apex/ComplaintInvestigationReportPDF?id=<ComplaintId>&format=html`.

## 5. After deploy
1. Deploy the metadata (README). 2. Assign the optional permission set. 3. Recreate the prompt template, then topics and actions above. 4. Publish and activate the agents.
