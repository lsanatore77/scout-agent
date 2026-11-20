# CQ Mobile Intake (unlocked package)

The mobile intake on its own: the reporter talks the problem through with CQ.AI (read-aloud questions), and it is sent
as a **Quality Event** for review, or as a **Case** for customer service when the problem was found at a customer
(each answer into its question's Case field, story and answers in the Description, the org's Case assignment rules route it).

No dependency on the CQ Triage Agent package: when its fields (Product, Product Caused Harm, Impact on Safety or
Environment) are in the org they are filled too; otherwise they are skipped.

The source here is **built from the main project** (`force-app`). Do not edit `force-app` in this folder: change the
main project, then rebuild:

    python3 scripts/build_mobile_intake_package.py          # from the repo root
    python3 scripts/build_mobile_intake_package.py --check  # is the package copy current?

## What is in it

| | |
|---|---|
| Screen | `cqIntakeConversation` (CQ.AI Report an Event) and its tab **Report an Event** |
| Apex | CqEventIntake (send: Quality Event or Case, quick log), CqIntakeChat (questions, clips), CqEventExtract (CQ.AI reads the story), CqEventParts, CqEventLotLink, all with tests |
| Trigger | QualityEventLotLink (fills the part from the lot) |
| Objects | Quality Event, Event Question (with Case Field), Event Answer, Quick Log Category, Quality Event tab |
| Fields on others | Case: Lot Number, Aware Date, Reported By, Where Found, Customer (As Reported), Supplier (As Reported), Product Affected, Injury Reported, Safety Risk Reported, Found By (Test or Inspection), Who Was Hurt. Nonconformance: Quick Log, Quick Log Category, Trend Event |
| Permission sets | CQ Mobile Intake User (report), CQ Mobile Intake Admin (questions, clips, categories) |

Not in it (on purpose): the desktop Report a Problem form, the Quality Event review panel (it needs Ask CQ), agents.

## Needs in the org first

- ComplianceQuest 16.0, ComplianceQuest User Interface 16.0, CQ.AI Extension 16.0 (`sfdx-project.json` lists their versions in dev).
  If CQ protects them with installation keys, ask CQ for them.
- For CQ.AI to read the story: Einstein generative AI on, and CQ's prompt template **CQSS Entity Extraction** (comes with CQ.AI Extension).
  Without it the questions still work; the reporter just answers more of them.

## Test in a scratch org (you run these; log in yourself)

**One command** (PowerShell, from this folder): `.\setup-intake-test.ps1 -From <your dev alias>` runs steps 1 to 4 below
(it reuses the scratch org if `intake-test` already exists, and stops at the first step that fails).

Or step by step, from this folder (`packages/cq-mobile-intake`), with the Dev Hub logged in as `golden`. The scratch org comes from the
**CQ16BaseSnap** snapshot (the same one atlas-seed uses), so CQ 16 is already installed: no package installs.

```
# 1. scratch org from the CQ 16 snapshot
sf org create scratch --definition-file config\cq16-snapshot-def.json --alias intake-test --duration-days 7 --target-dev-hub golden --no-namespace --wait 30

# 2. deploy the intake and run its tests
sf project deploy start --source-dir force-app --target-org intake-test --test-level RunLocalTests --wait 30

# 3. access, setup data (questions, clips, categories) copied from dev
sf org assign permset --name CQ_Mobile_Intake_User --name CQ_Mobile_Intake_Admin --target-org intake-test
.\scripts\copy-intake-data.ps1 -From <your dev alias> -To intake-test

# 4. try it
sf org open --target-org intake-test --path /lightning/n/Report_an_Event
```

Without the snapshot (`config/project-scratch-def.json`, an empty Enterprise org), install CQ first, in this order
(add `--installation-key <key>` if CQ gave you one):
`04tRn000000qxC5IAI` (ComplianceQuest), `04tRn000000qznNIAQ` (ComplianceQuest User Interface), `04tRn000000r0MsIAI` (CQ.AI Extension),
each with `sf package install --package <id> --target-org intake-test --wait 60 --no-prompt`.

Then in the scratch org: Setup > Object Manager > Case > Fields > Case Origin: add **Mobile Intake** (Case Origin
accepts it without, but reports and list views read better with it), and set a Case assignment rule if you want
customer reports routed to a queue.

## Make the package (after the scratch org test passes)

```bash
sf package create --name "CQ Mobile Intake" --package-type Unlocked --path force-app --no-namespace --target-dev-hub golden
sf package version create --package "CQ Mobile Intake" --code-coverage --installation-key-bypass --wait 60 --target-dev-hub golden
```

The version create prints an install link (`04t...`). Test it in a fresh scratch org: step 1, then
`sf package install --package <04t...> --target-org <new alias> --wait 30 --no-prompt`, then step 3.

## After installing in a demo org

1. Assign CQ Mobile Intake User (reporters) and CQ Mobile Intake Admin (whoever sets up questions).
2. Copy the setup data: `.\scripts\copy-intake-data.ps1 -From <dev> -To <demo>` (or the Node version, `scripts/copy-intake-data.mjs`, where Node is installed).
3. Add Mobile Intake to Case Origin; set the Case assignment rule.
4. Add the Report an Event tab to the app (and the mobile navigation) people use.
5. If the CQ Triage Agent package is there too, its own permission set gives access to its fields.
