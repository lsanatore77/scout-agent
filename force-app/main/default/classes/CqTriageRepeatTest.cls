@IsTest
private class CqTriageRepeatTest {

    static compliancequest__SQX_Nonconformance__c newNc(Id partId, String body, Date occurred, String lot) {
        return new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Hub bond leak at pressure test', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = '<p>' + body + '</p>', compliancequest__SQX_Part__c = partId,
            compliancequest__Lot_Number__c = lot, compliancequest__Defective_Quantity__c = 3, compliancequest__Occurrence_Date__c = occurred);
    }

    /** A past closed NC with the same leak and a closed CAPA marked effective; the new NC is submitted for triage. */
    static Map<String, Id> setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Repeat Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Repeat Part', cqext__Title__c = 'Repeat Part',
            compliancequest__Part_Number__c = 'REP-PART-1', compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        String leak = 'Catheters leaked at the hub bond during pressure testing; adhesive coverage thin on one side of the joint from bonding fixture BF-02';
        compliancequest__SQX_Nonconformance__c past = newNc(part.Id, leak, Date.today().addDays(-150), 'REP-LOT-0');
        insert past;
        compliancequest__SQX_CAPA__c capa = new compliancequest__SQX_CAPA__c(compliancequest__Title__c = 'Replace pin', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Issued_Date__c = Date.today().addDays(-140), compliancequest__Target_Due_Date__c = Date.today().addDays(-120));
        insert capa;
        update new compliancequest__SQX_CAPA__c(Id = capa.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed',
            compliancequest__Closed_Date__c = Date.today().addDays(-118));
        update new compliancequest__SQX_Nonconformance__c(Id = past.Id, compliancequest__SQX_CAPA__c = capa.Id);
        update new compliancequest__SQX_Nonconformance__c(Id = past.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed');
        compliancequest__SQX_Nonconformance__c nc = newNc(part.Id, leak, Date.today(), 'REP-LOT-1');
        insert nc;
        return new Map<String, Id>{ 'nc' => nc.Id, 'past' => past.Id, 'capa' => capa.Id };
    }

    @IsTest
    static void findsRaisesAndSuggests() {
        Map<String, Id> ids = setup();
        Test.startTest();
        CqTriageRepeat.Repeat r = CqTriageRepeat.getRepeat(ids.get('nc'));
        CqTriageRisk.Risk rk = CqTriageRisk.getRisk(ids.get('nc'));
        CqTriageNext.Next n = CqTriageNext.getNext(ids.get('nc'));
        Test.stopTest();
        System.assert(r.found, 'the past leak with a closed CAPA is a repeat');
        System.assertEquals(ids.get('past'), r.ncId);
        System.assertEquals(ids.get('capa'), r.capaId);
        System.assert(rk.repeatRaised);
        System.assertEquals(rk.baseLikelihood + 1, rk.likelihood);
        System.assertNotEquals(null, n.capaWhy);
        System.assertEquals('inv', n.invSuggest);
    }

    @IsTest
    static void notSameAndRestore() {
        Map<String, Id> ids = setup();
        Test.startTest();
        CqTriageRepeat.Repeat r = CqTriageRepeat.notSame(ids.get('nc'), ids.get('past'), 'NC-PAST');
        System.assert(!r.found, 'marked not the same problem');
        System.assertEquals(1, r.dismissed.size());
        r = CqTriageRepeat.restore(ids.get('nc'), r.dismissed[0].id);
        Test.stopTest();
        System.assert(r.found);
        System.assertEquals(0, r.dismissed.size());
        System.assert(CqTriageRepeat.isEffective('Closed-Effective'));
        System.assert(!CqTriageRepeat.isEffective('Closed-Ineffective'));
        try { CqTriageRepeat.notSame(null, null, null); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest
    static void completeRecordsTheDecision() {
        Map<String, Id> ids = setup();
        Map<String, Object> p = new Map<String, Object>{
            'risk' => 'High', 'notes' => 'x', 'severity' => 4, 'containment' => false, 'containmentTitles' => new List<String>(),
            'containmentDue' => String.valueOf(Date.today().addDays(5)), 'disposition' => false, 'dispositionApproval' => false,
            'investigate' => true, 'investigationDue' => String.valueOf(Date.today().addDays(60)), 'investigationApproval' => false,
            'repeatOfId' => ids.get('past'), 'repeatCapaId' => ids.get('capa'), 'repeatDecision' => 'Link to Earlier CAPA' };
        try { CqTriageNext.completeTriage(ids.get('nc'), JSON.serialize(p)); System.assert(false, 'a reason is needed'); } catch (AuraHandledException e) { System.assert(true); }
        p.put('repeatReason', 'Different adhesive lot');
        Test.startTest();
        CqTriageNext.Done d = CqTriageNext.completeTriage(ids.get('nc'), JSON.serialize(p));
        Test.stopTest();
        compliancequest__SQX_Nonconformance__c nc = [SELECT Repeat_Of__c, Repeat_Decision__c, Repeat_Decision_Reason__c, compliancequest__SQX_CAPA__c, compliancequest__Initiate_CAPA__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ids.get('nc')];
        System.assertEquals(ids.get('past'), nc.Repeat_Of__c, 'warning: ' + d.warning);
        System.assertEquals('Link to Earlier CAPA', nc.Repeat_Decision__c);
        System.assertEquals('Different adhesive lot', nc.Repeat_Decision_Reason__c);
        System.assertEquals(ids.get('capa'), nc.compliancequest__SQX_CAPA__c);
        System.assertEquals(false, nc.compliancequest__Initiate_CAPA__c);
    }
}
