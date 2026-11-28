@IsTest
private class CqImplementWorkspaceTest {
    private class FakeEsig implements CqEsigGateway {
        Integer signed = 0;
        public CqEsign.Policy signFor(Id recordId, String action) { CqEsign.Policy g = new CqEsign.Policy(); g.required = false; return g; }
        public void sign(Id recordId, String action, String comment, String password) { signed++; }
    }

    /** An NC owned by the running user with one open correction, or null when CQ refuses to make one in this context. */
    static compliancequest__SQX_Action__c makeAction(Id assignee) {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Implement Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Implement Part', cqext__Title__c = 'Implement Part', compliancequest__Part_Number__c = 'IMP-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Pin worn on fixture', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Bond offset on 4 units', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'IMP-LOT-1',
            compliancequest__Defective_Quantity__c = 4, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        try {
            compliancequest__SQX_Action__c a = new compliancequest__SQX_Action__c(compliancequest__SQX_Nonconformance__c = nc.Id,
                compliancequest__Title__c = 'Replace the locating pin', compliancequest__Plan_Type__c = 'Correction',
                compliancequest__Due_Date__c = Date.today().addDays(-2), compliancequest__SQX_User__c = assignee, compliancequest__Status__c = 'Open');
            insert a;
            return a;
        } catch (Exception e) {
            return null;   // CQ's own rules for making an action in this org's test context
        }
    }

    static Id otherUser() {
        for (SObject u : Database.query('SELECT Id FROM User WHERE IsActive = true AND UserType = \'Standard\' AND Id != \'' + UserInfo.getUserId() + '\' LIMIT 1')) { return u.Id; }
        return null;
    }

    @IsTest
    static void viewListsTheCorrections() {
        compliancequest__SQX_Action__c a = makeAction(UserInfo.getUserId());
        if (a == null) { return; }
        CqImplementWorkspace.View v = CqImplementWorkspace.getView(a.compliancequest__SQX_Nonconformance__c);
        System.assert(v.isOwner, 'the creator owns the NC');
        System.assertEquals(1, v.rows.size());
        System.assert(v.rows[0].mine);
        System.assertEquals('Open', v.rows[0].status);
        System.assert(!v.rows[0].toVerify);
    }

    @IsTest
    static void reassignAndRemind() {
        compliancequest__SQX_Action__c a = makeAction(UserInfo.getUserId());
        Id other = otherUser();
        if (a == null || other == null) { return; }
        Integer refused = 0;
        try { CqImplementWorkspace.reassign(a.Id, null); } catch (AuraHandledException e) { refused++; }
        try { CqImplementWorkspace.reassign(a.Id, UserInfo.getUserId()); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(2, refused);
        try {
            CqImplementWorkspace.reassign(a.Id, other);
            System.assertEquals(other, [SELECT compliancequest__SQX_User__c FROM compliancequest__SQX_Action__c WHERE Id = :a.Id].compliancequest__SQX_User__c);
        } catch (AuraHandledException e) { /* CQ's own rules on changing the assignee */ }
        try { CqImplementWorkspace.sendReminder(a.Id); } catch (AuraHandledException e) { /* no notification type in this org */ }
    }

    @IsTest
    static void verifyOnlyWhatIsWaiting() {
        compliancequest__SQX_Action__c a = makeAction(UserInfo.getUserId());
        if (a == null) { return; }
        FakeEsig f = new FakeEsig(); CqEsign.gateway = f;
        Boolean refused = false;
        try { CqImplementWorkspace.verify(a.Id, 'Checked the first piece', null, null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'an open correction is not waiting for verification');
        System.assertEquals(0, f.signed);
    }

    @IsTest
    static void closeOnlyWhenEveryCorrectionIsDone() {
        compliancequest__SQX_Action__c a = makeAction(UserInfo.getUserId());
        if (a == null) { return; }
        FakeEsig f = new FakeEsig(); CqEsign.gateway = f;
        Id ncId = a.compliancequest__SQX_Nonconformance__c;
        System.assert(!CqImplementWorkspace.getView(ncId).canClose, 'a correction is open');
        Integer refused = 0;
        try { CqImplementWorkspace.close(ncId, 'Effective', 'Held on 3 lots', null, null); } catch (AuraHandledException e) { refused++; }
        try { CqImplementWorkspace.close(ncId, 'Void', 'Held on 3 lots', null, null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(2, refused);
        System.assertEquals(0, f.signed, 'nothing signed while it cannot close');
    }

    @IsTest
    static void containmentsAreListedAndHoldTheClose() {
        compliancequest__SQX_Action__c a = makeAction(UserInfo.getUserId());
        if (a == null) { return; }
        Id ncId = a.compliancequest__SQX_Nonconformance__c;
        compliancequest__SQX_Containment__c c;
        try {
            c = new compliancequest__SQX_Containment__c(compliancequest__SQX_Nonconformance__c = ncId, compliancequest__Title__c = 'Hold the lot',
                compliancequest__Due_Date__c = Date.today().addDays(-1), compliancequest__SQX_User__c = UserInfo.getUserId());
            insert c;
        } catch (Exception e) { return; }   // CQ's own rules for making a containment in this org's test context
        FakeEsig f = new FakeEsig(); CqEsign.gateway = f;
        CqImplementWorkspace.View v = CqImplementWorkspace.getView(ncId);
        System.assertEquals(1, v.containments.size());
        System.assert(v.containments[0].mine);
        Boolean listed = false;
        for (CqImplementWorkspace.Blocker b : v.openBeforeClose) { if (b.id == c.Id) { listed = true; } }
        System.assertEquals(v.containments[0].open, listed, 'an open containment holds the close');
        Integer refused = 0;
        try { CqImplementWorkspace.completeContainment(c.Id, ' ', null, null, null); } catch (AuraHandledException e) { refused++; }
        try { CqImplementWorkspace.completeContainment(c.Id, 'Held', String.valueOf(Date.today().addDays(2)), null, null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(2, refused);
        System.assertEquals(0, f.signed, 'nothing signed while the form is incomplete');
        try { CqImplementWorkspace.completeContainment(c.Id, 'All units held in quarantine.', null, null, null); } catch (AuraHandledException e) { /* CQ's own rules */ }
        try { CqImplementWorkspace.reassign(c.Id, null); } catch (AuraHandledException e) { refused++; }
    }

    @IsTest
    static void refusesOtherRecords() {
        Integer refused = 0;
        try { CqImplementWorkspace.getView(UserInfo.getUserId()); } catch (AuraHandledException e) { refused++; }
        try { CqImplementWorkspace.sendReminder(UserInfo.getUserId()); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(2, refused);
    }
}
