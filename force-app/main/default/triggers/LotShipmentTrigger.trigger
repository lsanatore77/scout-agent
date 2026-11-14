/** Lot Shipment: fills Lot Number from the lot record, and keeps Units Shipped on open field actions in step. */
trigger LotShipmentTrigger on Lot_Shipment__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        CqLotShipments.onChange(Trigger.new, null, true);
    } else {
        CqLotShipments.onChange(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap, false);
    }
}
