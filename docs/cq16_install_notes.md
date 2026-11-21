# CQ 16 (Summer 2026) fresh install: what the script does and what it does not

From CQ's Confluence manuals (SQE space, "Installation Qualification - Summer 26", page 6105923896, and each
extension's fresh-install manual). `scripts/install-cq16.ps1` installs the managed packages, in the order below.
Everything else on this page is still done by hand, or by a later script step.

## 1. Before installing
- Enhanced Email on (scratch: in `cq16-ai-fresh-def.json`).
- EHS and Supplier Central: Salesforce Files settings (Libraries; skip triggers on asset files).
- Supplier Central: Digital Experiences on (ExperienceBundle API, standard external profiles), User Access Policies,
  Partner Community licenses.
- Licenses CRM Analytics Plus (or Analytics Platform): Ratings, Supplier Performance, MRD (also Analytics View Only
  Embedded App), Regulatory Reports, CQ.AI.
- CQ.AI also: Einstein on, Agentforce on, Messaging User, Agent platform builder, Einstein Prompt Templates,
  AgentforceEmployeeAgentAddOn, FlexCredits.

## 2. Managed packages (the script), in dependency order
CQ, UI, Approval, Document Extensions, Forms, Ratings, **CQ.AI** (Process needs it), Process, Design, PLM, EBR,
Lab Issues, myCQ, EHS, EHS Integration, EHS AI, Supplier Mgmt, Supplier Central, Supplier Perf, Reg Reports, MRD,
Backup and Restore.

## 3. External packages (metadata ZIPs from Confluence)
Deployed with Workbench or `sf project deploy start --metadata-dir <unzipped> --test-level RunSpecifiedTests
--tests compliancequest.SQX_Test_1931_ContentVersionPerm`.

| Package | Fresh-install ZIPs | Picklist ZIP | PESC (edit Default Workflow User username) |
|---|---|---|---|
| Core | `extPkg_CQSummer26_Fresh_Installation`, `_CQDocument_Extensions_Fresh_Installation` | — | `_CQPlatformEventSubscriberConfigs_Fresh_Installation` |
| CQ.AI | `_CQ.AI_Extension_Fresh_Installation_For_16.0.x`, `_For_CQPE_16.0.x`, `_For_CQDE_16.0.x` | — | — |
| Process | Fresh | yes | — |
| Forms | Fresh | yes | — |
| myCQ | Fresh | — | — |
| Design | Fresh | yes | 1 file |
| PLM | Fresh | yes | — |
| Lab Issues | Fresh | yes | — |
| EBR | Fresh | yes | 1 file |
| EHS | Fresh, `_CQmyCQ_Extension_Fresh_Installation_For_EHS` | yes | — |
| EHS AI | `_CQEHS_Extension_AI_Object_Transformations_Package` | — | — |
| Ratings | Fresh | yes | 1 file |
| Supplier Mgmt | Fresh | — | 2 files |
| Supplier Perf | Fresh | yes | — |
| Supplier Central | Fresh, `_For_CQSPFE` (with Supplier Perf and Forms) | — | — |
| MRD | Fresh | yes | — |
| Reg Reports | `_Fresh_Installation_For_16.0.x`, `ExclusivePackage_..._For_16.0.x` | Picklist_1, Picklist_2 | — |
| Backup and Restore | none for 16.0 | — | — |

The core `_Upgrade_Picklist_Package` and object transformation packages are for upgrades only. The only object
transformation ZIP in a fresh install is EHS AI's.

## 4. Picklist packages
Not deployable with sf: Setup → Visualforce Pages → SQX_Post_Actions → Preview → Picklist Update tab, one ZIP at a time.

## 5. After installing
- Page layout assignment (SQX_Post_Actions).
- Setup data (anonymous Apex, one file can run them all):
  `cqext.CQPLA_SetupDataProcessor.execute();` `cqext.CQF_Forms_SetupDataProcessor.execute();`
  `cqext.CQDC_SetupDataProcessor.execute();` `cqext.CQPLM_SetupDataProcessor.execute();`
  `compliancequest.SQX_SetupData_Processor.execute('CQLIInstaller');` `cqext.CQEBR_SetupDataProcessor.execute();`
  `cqext.CQ_EHS_SetupDataProcessor.execute();` `cqext.CQSPE_SetupData_Processor.execute();`
  `cqext.CQMRD_SetupData_Processor.execute();` `cqext.CQREG_SetupDataProcessor.execute();`
  `cqext.CQEE_Announcement_Group.insertCollaborationGroup('myCQ Announcement Group');`
- Schedulers: EHS (permits, recurring tasks, weather), CQ.AI similarity batch, Supplier Performance.
- Connected apps, External Client Apps, Auth Providers, Named Credentials (Ratings, EBR BOM).
- CRM Analytics apps (CQRF, CQSP, CQCT).
- CQ.AI: Agentforce agent mapping.
