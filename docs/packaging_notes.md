# Packaging notes (CQ.AI Quality and Field Actions)

Not now; at some point. Kept so packaging is a known list, not a discovery.

## Decided (16 Nov 2026)
- Package as a **managed package in the `enablement` namespace**, the same packaging set up for "Enablement - Document Agent" (Developer Edition org `enablement-ns`, Dev Hub golden). It depends on the CQ package (compliancequest), installed first.

## What changes when it is packaged
- **Names get the namespace.** Our objects and fields become `enablement__Quality_Event__c`, `enablement__Triage_Risk__c` and so on, including the fields we add to CQ objects (Nonconformance, Investigation, CAPA, Root Cause). Code written in the namespace org needs no change; anything that builds names as text (LWC field paths such as the part picker's `compliancequest__Part_Number__c`, dynamic SOQL, the agent scripts, the prompt template name `CQAI_Investigation_Summary`) must be checked.
- **The dev org will not adopt the package.** dev (cqse-golden--dev) has these components unmanaged and without a namespace; installing the managed package there would add a second, namespaced copy. Test the package in a scratch org or a fresh sandbox, not over dev.
- **Data does not travel.** Setup records (Event Questions, Quick Log Categories, Signal Rules, settings) need an install script (a post-install Apex class) or Custom Metadata to arrive with the package.
- **Shortcuts agreed for dev** need a packaged form: closing quick-log NCs directly; agent scripts pasted by hand; the prompt template made through the API (GenAiPromptTemplate is packageable).
- **Permission sets** (CQ.AI Quality, Field Actions User) package; assignments do not.
- **Tests:** 75% coverage in the packaging org, no reliance on org data, and field-level security in a fresh org (the Document Agent package hit this: fields created by metadata are hidden until a permission set grants them).
- **API version:** Lightning Types and agent metadata need API 66.0 or later (golden notes say 67.0 for Lightning Types).
- **CQ version:** build against the oldest CQ version customers run (Master is on 15.6).

## Running list of things to check before packaging
- Hard-coded CQ picklist values and activity codes (submit, takeownershipandinitiate, Closed).
- Record-type and app names referenced by name.
- The Report a Problem tab (created by hand in dev).

## Purpose of the enablement package, and CQ adoption (decided 16 Nov 2026)
- The `enablement` package is for our work and demos (CQ's development team and leadership), not for wide customer installs.
- If CQ adopts it, they repackage our source under their own namespace (compliancequest) in their packaging org. A namespace cannot be changed on a managed package and an upgrade cannot move components between namespaces (verify before relying on this), so it is a source hand-over, not a package upgrade.
- What makes the hand-over cheap: keep names namespace-neutral (no prefix written out in strings, field paths, agent scripts or prompt references), keep setup data in an install script or Custom Metadata, and keep installs to demo orgs so no customer data needs migrating.
- On their side: our fields on CQ objects become native CQ fields (no extension dependency), and CQ's code standards, coverage, security review and release schedule apply.
- CQ may also rename objects, fields and classes to their own conventions. That is a find-and-replace across the source, so keep a name map (docs/data_model_log.md and tools/data_model.py already list every object and field), keep API names consistent, and keep wording in labels rather than in code.

## When to do what (decided 16 Nov 2026)
- Habits from now on: queries run as the user, with sharing and permission checks; no hard-coded record IDs; no namespace prefix written out in names; keep the logs current.
- Wait until ComplianceQuest shows real interest: Custom Labels for screen text, replacing the dev shortcuts, Custom Metadata, the scratch-org build and install script, matching CQ's conventions, security review.
- The read-through audit (security and shortcuts) fits the planned cleanup pause after Event Review; findings go on this list.
