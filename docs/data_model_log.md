## Change log

Newest first. Add a line here whenever an object or field is created, changed or removed, then run `python3 tools/data_model.py`.

### 14 Nov 2026
- **CAPA (CQ object `compliancequest__SQX_CAPA__c`)**: added Field Action (lookup to Field Action, relationship CAPAs) and the record type **CAPA - Field Action** (`CAPA_Field_Action`). A field action's Closure step creates a skeleton CAPA of this type (title, part, field action, Target Due Date 60 days out) and links it back in the field action's CAPA field.
- **Field Action**: Other Records is no longer shown on the Closure step (the field stays for now). The CAPA check blocks closing only until a CAPA is linked; the CAPA's own status does not hold the field action open.
- **New object Lot Stock** (`Lot_Stock__c`): units of a lot on hand at a CQ Location, one record per lot per location, loaded from the ERP. Fields: Lot (Lot Info lookup), Lot Number, Location (CQ Location lookup), Units On Hand, As Of, Source (ERP, Manual). `LotStockTrigger` fills Lot Number from the lot and keeps open field action lots up to date. Eleven test records (Source Manual) were added in dev for the FA-0001 lots and a few others.
- **Field Action Lot**: Units On Hand and Location are now filled from Lot Stock (Location is a text summary of the CQ Locations) and are no longer typed on the Scope step; Units Shipped is read-only there too. Logic in `CqLotStock`.
- **Activity (standard Task and Event) — existing object**: added Recall Task Type, Field Action Customer (lookup), Lot Number, Units. Field action work is tracked as standard Tasks on the Field Action; return and destruction task units add up to the lot's Returned and Destroyed, and a completed Collect response marks the customer Acknowledged.
- **Field Action Customer**: Status now follows the customer's Collect response task; Follow Ups is no longer used (follow-ups are tasks).
- **Field Action Lot**: Units Returned, Destroyed and Corrected now add up from the units on the lot's recall tasks (lots whose tasks carry no units keep the figures typed before). The Recovery step no longer edits them directly. Logic in `CqFieldActionTasks`.
- **New object Lot Shipment** (`Lot_Shipment__c`): units of a lot shipped to a customer, loaded from the ERP. Fields: Lot, Lot Number, Customer, Units, Ship Date, Ship To, Contact Name, Order Number. A trigger keeps Units Shipped on open field action lots equal to the shipments.
- **Field Action Customer**: added Customer (Account lookup) and Source (Shipment, Added by hand). Customers now fill from the lot shipments.
- **New object Field Action Customer** (`Field_Action_Customer__c`): customers in a field action's effectiveness check.
- **Field Action Lot**: added Units Returned, Units Destroyed, Units Corrected.
- **Field Action Hold**: added Disposition, Disposition On.
- **Field Action**: added Recovery Status, Verdict, Next Step, Verdict By, Verdict On, Closure Summary, CAPA, Other Records, Closed By, Closed On.
- **New object Field Action Hold** (`Field_Action_Hold__c`): holds on finished and component lots placed by the Strategy step.
- **Field Action**: added Depth, Customer Instruction, Key Message, Check Level, Check Percent, Check Method, Check By, Strategy Status, Strategy Confirmed By, Strategy Confirmed On.
- **Field Action**: added Scope Confirmed By, Scope Confirmed On; Scope Status gained Confirmed. Field Action Lot: Approved In Scope relabelled Confirmed In Scope.

### Before 14 Nov 2026
Objects and fields from earlier work are listed below; their history is in git (`git log -- force-app/main/default/objects`).
