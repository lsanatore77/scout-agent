@IsTest
private class CqInvestigationHistoryTest {

    static compliancequest__SQX_Nonconformance__c newNc(Id partId, String title, String body, Date occurred, String lot) {
        return new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = title, compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = '<p>' + body + '</p>', compliancequest__SQX_Part__c = partId,
            compliancequest__Lot_Number__c = lot, compliancequest__Defective_Quantity__c = 3, compliancequest__Occurrence_Date__c = occurred);
    }

    /** A past closed NC with the same leak and a closed CAPA marked effective, and the current NC triaged to investigation. */
    static Id setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'History Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'History Part', cqext__Title__c = 'History Part',
            compliancequest__Part_Number__c = 'HIS-PART-1', compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        String leak = 'Catheters leaked at the hub bond during pressure testing; adhesive coverage thin on one side of the joint from bonding fixture BF-02';
        compliancequest__SQX_Nonconformance__c past = newNc(part.Id, 'Hub bond leak at pressure test', leak, Date.today().addDays(-150), 'HIS-LOT-0');
        insert past;
        compliancequest__SQX_CAPA__c capa = new compliancequest__SQX_CAPA__c(compliancequest__Title__c = 'Replace pin', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Issued_Date__c = Date.today().addDays(-140), compliancequest__Target_Due_Date__c = Date.today().addDays(-120));
        insert capa;
        update new compliancequest__SQX_CAPA__c(Id = capa.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed',
            compliancequest__Closed_Date__c = Date.today().addDays(-118));
        try {
            compliancequest__SQX_Effectiveness_Review__c r = new compliancequest__SQX_Effectiveness_Review__c(compliancequest__SQX_CAPA__c = capa.Id,
                compliancequest__Review_Started_On__c = Date.today().addDays(-100));
            insert r;
            update new compliancequest__SQX_Effectiveness_Review__c(Id = r.Id, compliancequest__Status__c = 'Complete', compliancequest__Resolution__c = 'Closed-Effective',
                compliancequest__Review_Completed_On__c = Date.today().addDays(-98));
        } catch (Exception e) { System.debug(e.getMessage()); }
        update new compliancequest__SQX_Nonconformance__c(Id = past.Id, compliancequest__SQX_CAPA__c = capa.Id);
        update new compliancequest__SQX_Nonconformance__c(Id = past.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed');

        compliancequest__SQX_Nonconformance__c nc = newNc(part.Id, 'Hub bond leak at pressure test', leak, Date.today(), 'HIS-LOT-1');
        insert nc;
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = 'submit');
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Investigation_Required__c = true,
            compliancequest__Activity_Code__c = 'takeownershipandinitiate');
        return nc.Id;
    }

    @IsTest
    static void findsTheRecurrenceAndDismisses() {
        Id ncId = setup();
        Test.startTest();
        CqInvestigationHistory.View v = CqInvestigationHistory.getHistory(ncId);
        Test.stopTest();
        System.assertEquals(Date.today(), v.startDate);
        System.assert(!v.categories.isEmpty());
        CqInvestigationHistory.Item past;
        for (CqInvestigationHistory.Item it : v.items) { if (it.type == 'Nonconformance') { past = it; } }
        System.assertNotEquals(null, past, 'the past leak matches the problem');
        System.assertNotEquals(null, past.capaName);
        System.assertEquals(1, v.recurrences.size(), 'closed CAPA, same problem, earlier: the fix did not hold');

        CqInvestigationHistory.markNotRelevant(ncId, past.recordId, past.name, 'Different line');
        v = CqInvestigationHistory.getHistory(ncId);
        System.assertEquals(1, v.dismissed.size());
        for (CqInvestigationHistory.Item it : v.items) { System.assertNotEquals(past.recordId, it.recordId, 'dismissed records drop off'); }
        CqInvestigationHistory.restore(v.dismissed[0].id);
        System.assertEquals(0, CqInvestigationHistory.getHistory(ncId).dismissed.size());
    }

    @IsTest
    static void recurrenceRule() {
        CqInvestigationHistory.Item it = new CqInvestigationHistory.Item();
        it.type = 'Nonconformance';
        System.assert(!CqInvestigationHistory.isRecurrence(it, Date.today()), 'no CAPA');
        it.capaId = UserInfo.getUserId(); it.capaStatus = 'Open';
        System.assert(!CqInvestigationHistory.isRecurrence(it, Date.today()), 'CAPA still open');
        it.capaStatus = 'Closed'; it.day = Date.today().addDays(1);
        System.assert(!CqInvestigationHistory.isRecurrence(it, Date.today()), 'after the start');
        it.day = Date.today().addDays(-30);
        System.assert(CqInvestigationHistory.isRecurrence(it, Date.today()));
        try { CqInvestigationHistory.markNotRelevant(null, null, null, null); System.assert(false); } catch (Exception e) { System.assert(true); }
    }
}
