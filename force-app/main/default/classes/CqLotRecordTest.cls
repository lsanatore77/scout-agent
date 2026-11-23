/** The Lot record screen's data (CqLotRecord): a purchased lot's fields and supply, blank fields left out, stock, and the CQ.AI phrase match. */
@IsTest
private class CqLotRecordTest {

    @IsTest
    static void purchasedLotShowsItsSupplyAndLeavesBlanksOut() {
        Account sup = new Account(Name = 'Lot Record Supplier');
        insert sup;
        compliancequest__SQX_Lot_Info__c l = new compliancequest__SQX_Lot_Info__c(Name = 'LRT-001', compliancequest__Part_Number__c = 'LRT-PART',
            Lot_Type__c = 'Purchased', Release_Status__c = 'On Hold', Hold_Reason__c = 'Test hold', Supplier__c = sup.Id,
            Supplier_Lot__c = 'S-1', Received_Date__c = Date.newInstance(2026, 4, 5), Receiving_Inspection__c = 'Accepted');
        insert l;
        insert new Lot_Stock__c(Lot__c = l.Id, Lot_Number__c = 'LRT-001', Units_On_Hand__c = 7);

        Test.startTest();
        CqLotRecord.View v = CqLotRecord.get(l.Id);
        Test.stopTest();

        System.assertEquals('LRT-001', v.name);
        System.assertEquals('warn', v.statusTone, 'On Hold is a warning');
        System.assertEquals(null, v.batchId);
        Map<String, CqLotRecord.Item> head = new Map<String, CqLotRecord.Item>();
        for (CqLotRecord.Item i : v.header) { head.put(i.key, i); }
        System.assert(head.containsKey('hold'), 'the hold reason shows');
        System.assert(!head.containsKey('steril'), 'a blank sterilization lot is left out');
        System.assert(!head.containsKey('batch'), 'no batch record, no batch field');
        System.assertEquals(4, v.supply.size(), 'supplier, supplier lot, received and inspection');
        System.assertEquals('pos', v.supply[3].tone, 'an accepted inspection is good');
        System.assertEquals(7, v.onHand);
        System.assert(v.subAssemblies.isEmpty() && v.materials.isEmpty(), 'no batch, no components');
    }

    @IsTest
    static void releasedLotWithNothingAgainstIt() {
        compliancequest__SQX_Lot_Info__c l = new compliancequest__SQX_Lot_Info__c(Name = 'LRT-002', Lot_Type__c = 'Finished', Release_Status__c = 'Released');
        insert l;
        CqLotRecord.View v = CqLotRecord.get(l.Id);
        System.assertEquals('pos', v.statusTone);
        System.assert(v.complaints.isEmpty() && v.ncs.isEmpty() && v.fieldActions.isEmpty() && v.usedIn.isEmpty());
        System.assert(v.supply.isEmpty(), 'a finished lot has no supply data');
        System.assertEquals(null, v.onHand, 'no stock record, no on hand');
    }

    @IsTest
    static void phraseMatchIsATwoWordPhraseFromThePartName() {
        String text = ' distal marker band hard to see under fluoroscopy. ';
        System.assertEquals('marker band', CqLotRecord.matchPhrase('Radiopaque marker band, Pt/Ir 90/10', text));
        System.assertEquals(null, CqLotRecord.matchPhrase('Balloon Sub-Assembly, Nylon 12', ' balloon slow to deflate '), 'one shared word is not enough');
        System.assertEquals(null, CqLotRecord.matchPhrase(null, text));
    }
}
