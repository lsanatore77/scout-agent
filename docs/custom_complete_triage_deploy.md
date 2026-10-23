# Custom Complete Triage (dev test only)

Replaces CQ's Complete Triage popup in eNBA with our own screen. It reuses the purpose
`phr_triage_with_summary`, the CQ Action and CQ Quick Action records and the override flow branch
that are already in dev, so only Apex and the component change.

## Deploy from VS Code (this order)
1. classes/TriageDraftSummaryController.cls (resolveComplaintId is now public)
2. classes/PhrCompleteTriageController.cls and PhrCompleteTriageControllerTest.cls
3. lwc/triageStepsWithSummary (all four files, replaces the earlier version)
(SaveDraftInvestigationSummary is included for completeness; it is unchanged.)

## Check these are in place in dev
- LPA ENBA Action Override: the version with the Complaint Triage outcome (purpose phr_triage_with_summary) is Active.
  If you re-activated version 8, activate that version again.
- CQ Quick Action "PHR Triage With Summary": Esig unticked (the screen has its own Comment box).
- CQ Action "PHR Triage With Summary": component triageStepsWithSummary, namespace c.

## What Complete triage does
1. Saves the step changes: assignees, the Include tick (Applicable), and new steps from CQ Tasks flagged Transfer To Workflow.
2. Saves the complaint with Activity Code `initiate` (`takeownershipandinitiate` while a queue owns it).
   CQ then does its normal Initiate: Stage Triage -> In Progress, Status Draft -> Open, steps Draft -> Open,
   triage task closed, ownership taken.
3. If Include draft summary is ticked and the complaint has a draft, saves it to the complaint and copies it to the
   linked investigation(s). It retries for a few seconds in case CQ creates the investigation a moment later.
Each step is its own transaction (CQ allows one activity per transaction).

The button only appears while the CQ triage task is open, which is only in the Triage stage. The screen also
checks the stage and shows a message instead of the form if the complaint is not in Triage.

## Test (COM-0000000006 is in Triage with one draft step)
1. Optional: generate a draft summary on the complaint first.
2. Refresh, click Complete Triage. Check the step list, change an assignee, try Add step.
3. Enter a comment, click Complete triage.
4. Expect: toast, stage In Progress, step Open, triage task Completed, and the summary on the complaint and its
   investigation (if CQ created or linked one).
5. Check an LPA audit and a non-complaint record: their eNBA buttons are unchanged.

## Roll back
Activate version 8 of LPA ENBA Action Override. CQ's own triage button returns.
