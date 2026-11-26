@IsTest
private class CqApprovalsTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = true; Boolean accept = true; Integer signed = 0;
        public CqEsign.Policy signFor(Id recordId, String action) {
            CqEsign.Policy g = new CqEsign.Policy();
            g.required = required; g.purpose = 'Approve';
            return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (!accept) { throw new AuraHandledException('Signature not accepted: wrong password'); }
            signed++;
        }
    }

    /** A review with an open CQ Approval step assigned to the running user, submitted through CQ's engine as the app does. */
    private static cqext__CQAPR_Approval_Step__c openStep(Field_Action_Review__c review) {
        cqext__CQAPR_Approval__c a = new cqext__CQAPR_Approval__c(cqext__Approval_Record__c = 'CQ Record', cqext__Approval_Type__c = 'Committee Approval',
            cqext__Main_Record_Id__c = review.Id, cqext__Child_Record_Id__c = review.Id);
        List<cqext__CQAPR_Approval_Step__c> steps = new List<cqext__CQAPR_Approval_Step__c>{ new cqext__CQAPR_Approval_Step__c(cqext__Step__c = 1,
            cqext__CQAPR_Assignee_User__c = UserInfo.getUserId(), cqext__Assignee_Id__c = UserInfo.getUserId()) };
        new CqApprovalBridge().submit(review, a, steps);
        return [SELECT Id, cqext__Status__c, cqext__CQAPR_Approval__c FROM cqext__CQAPR_Approval_Step__c
                WHERE cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c = :review.Id ORDER BY CreatedDate DESC LIMIT 1];
    }

    @IsTest
    static void myOpenStepsAreListedWithTheirRecord() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Approve me');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        Test.startTest();
        List<CqApprovals.Item> items = CqApprovals.mine();
        Test.stopTest();
        CqApprovals.Item mineItem;
        for (CqApprovals.Item i : items) { if (i.stepId == step.Id) { mineItem = i; } }
        System.assertNotEquals(null, mineItem, 'the open step is listed');
        System.assertEquals(review.Id, mineItem.recordId);
        System.assertEquals('Approve me', mineItem.recordTitle);
        System.assertEquals('Committee Approval', mineItem.what);
        System.assert(mineItem.canSign, 'field action reviews keep a signature log');
    }

    @IsTest
    static void approveSignsThenActs() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign and approve');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        FakeEsig f = new FakeEsig();
        CqEsign.gateway = f;
        Boolean refused = false;
        try { CqApprovals.act(step.Id, 'approve', null, null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'no password: refused');
        System.assertEquals(0, f.signed);
        Test.startTest();
        CqApprovals.act(step.Id, 'approve', null, 'pw');
        Test.stopTest();
        System.assertEquals(1, f.signed, 'signed once');
        System.assertNotEquals('Open', [SELECT cqext__Status__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :step.Id].cqext__Status__c);
    }

    @IsTest
    static void rejectNeedsAReason() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Reject me');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        FakeEsig f = new FakeEsig();
        CqEsign.gateway = f;
        Boolean refused = false;
        try { CqApprovals.act(step.Id, 'reject', '  ', 'pw'); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a rejection needs a reason');
        Test.startTest();
        CqApprovals.act(step.Id, 'reject', 'Wrong lot on the disposition.', 'pw');
        Test.stopTest();
        System.assertEquals(1, f.signed);
        System.assertEquals('Rejected', [SELECT cqext__Status__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :step.Id].cqext__Status__c);
    }

    @IsTest
    static void idsAreReadSafely() {
        System.assertEquals(null, CqApprovals.toId('not an id'));
        System.assertEquals(null, CqApprovals.toId(null));
    }
}
