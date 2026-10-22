# Triage "Include draft summary" - deployment (dev only)

## 1. Deploy from VS Code (in this order)
1. `classes/TriageDraftSummaryController.cls` and its test `TriageDraftSummaryControllerTest.cls`
   (needs `SaveDraftInvestigationSummary` with the investigation update; deploy that first if dev does not have it).
2. `lwc/triageStepsWithSummary` (all four files).
3. `customMetadata/compliancequest__CQ_Action.PHR_Triage_With_Summary.md-meta.xml`
   (or create it by hand: Setup > Custom Metadata Types > CQ Action > Manage Records, copy the values from the file).

## 2. Edit the override flow in Flow Builder (flows are not deployed from here)
Open `LPA ENBA Action Override`, Save As New Version, then:
1. Decision `Is LPA Task`: add an outcome `Complaint Triage`.
   Condition: `{!task.compliancequest__CQ_Task_Code__c}` Equals `nba__Complaint_Triage`.
2. Add an Assignment `Set Triage Purpose` after that outcome:
   - `{!varPrimary}` Equals `{!nbaAction.primaryAction}`  (keeps CQ's own label, title and message)
   - `{!varPrimary.purpose}` Equals `phr_triage_with_summary`
   - `{!varPrimary.immediateComplete}` Equals `False`
   - `{!nbaAction.primaryAction}` Equals `{!varPrimary}`
3. Connect it to the end. Leave the default path ("Other Task") untouched.
4. Activate the new version.

## 3. Test
1. Open a complaint that has a triage task assigned to you (status Not Started). Refresh.
2. Click the triage button. The popup should show CQ's steps grid and the Include draft summary box.
3. Tick the box, finish the grid. The complaint should show the draft summary and any linked investigation's Investigation Summary should match.
4. Untick the box and repeat on another complaint: nothing is copied.
5. Open a non-complaint record (for example an audit or NC): its eNBA buttons must be unchanged.

## 4. Roll back
Activate the previous version of `LPA ENBA Action Override` (the triage button returns to CQ's own behavior).
