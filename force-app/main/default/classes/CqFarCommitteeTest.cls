@IsTest
private class CqFarCommitteeTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Boolean comment = false; Boolean fail = false; Boolean accept = true;
        Integer signed = 0;
        public CqFarCommittee.Sign signFor(Id recordId, String action) {
            if (fail) { throw new CalloutException('no session'); }
            CqFarCommittee.Sign g = new CqFarCommittee.Sign();
            g.required = required; g.comment = comment; g.purpose = 'Committee Approve';
            return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (!accept) { throw new AuraHandledException('Signature not accepted: wrong password'); }
            signed++;
        }
    }

    /** A review with an open CQ Approval step assigned to the running user. */
    private static cqext__CQAPR_Approval_Step__c openStep(Field_Action_Review__c review) {
        cqext__CQAPR_Approval__c a = new cqext__CQAPR_Approval__c(cqext__Approval_Record__c = 'CQ Record', cqext__Approval_Type__c = 'CQ Approval',
            cqext__Main_Record_Id__c = review.Id, cqext__Child_Record_Id__c = review.Id, cqext__Status__c = 'Open');
        insert a;
        cqext__CQAPR_Approval_Step__c s = new cqext__CQAPR_Approval_Step__c(cqext__CQAPR_Approval__c = a.Id, cqext__Step__c = 1,
            cqext__CQAPR_Assignee_User__c = UserInfo.getUserId(), cqext__Assignee_Id__c = UserInfo.getUserId(), cqext__Status__c = 'Open');
        insert s;
        return [SELECT Id, cqext__Status__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :s.Id];
    }

    private static String error(Id reviewId, Id stepId, String action, String comment, String password) {
        try { CqFarCommittee.decide(reviewId, stepId, action, comment, password); } catch (AuraHandledException e) { return e.getMessage(); }
        return null;
    }

    @IsTest
    static void signatureSettingsComeFromCq() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign review');
        insert review;
        FakeEsig f = new FakeEsig(); f.required = true; f.comment = true;
        CqFarCommittee.esig = f;
        CqFarCommittee.Sign g = CqFarCommittee.signFor(review.Id, 'approve');
        System.assert(g.required && g.comment && !g.unknown);

        f.fail = true;
        System.assert(CqFarCommittee.signFor(review.Id, 'approve').unknown, 'when CQ cannot be asked the answer is unknown');
    }

    @IsTest
    static void refusesWithoutASignature() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign review');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        FakeEsig f = new FakeEsig(); f.required = true; f.comment = true;
        CqFarCommittee.esig = f;

        System.assertNotEquals(null, error(review.Id, step.Id, 'approve', 'ok', null), 'no password: refused');
        System.assertNotEquals(null, error(review.Id, step.Id, 'approve', '', 'pw'), 'comment required: refused');
        f.accept = false;
        System.assertNotEquals(null, error(review.Id, step.Id, 'approve', 'ok', 'wrong'), 'CQ did not accept: refused');
        f.fail = true;
        System.assertNotEquals(null, error(review.Id, step.Id, 'approve', 'ok', 'pw'), 'CQ could not be asked: refused');
        System.assertEquals(0, f.signed);
        System.assertEquals('Open', [SELECT cqext__Status__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :step.Id].cqext__Status__c);
    }

    @IsTest
    static void signsThenActs() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign review');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        FakeEsig f = new FakeEsig(); f.required = true;
        CqFarCommittee.esig = f;
        String err = error(review.Id, step.Id, 'approve', 'agree', 'pw');
        System.assertEquals(1, f.signed, 'CQ signed first: ' + err);
    }

    @IsTest
    static void noPolicyNoSignature() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign review');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        FakeEsig f = new FakeEsig();
        CqFarCommittee.esig = f;
        error(review.Id, step.Id, 'approve', null, null);
        System.assertEquals(0, f.signed);
        System.assertNotEquals(null, error(review.Id, step.Id, 'reject', '', null), 'sending back needs a comment');
        System.assertNotEquals(null, error(review.Id, step.Id, 'other', 'x', null), 'unknown action');
    }

    @IsTest
    static void viewCarriesTheSignatureSettings() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sign review');
        insert review;
        cqext__CQAPR_Approval_Step__c step = openStep(review);
        update new Field_Action_Review__c(Id = review.Id, Status__c = 'With Committee',
            Committee_Approval__c = [SELECT cqext__CQAPR_Approval__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :step.Id].cqext__CQAPR_Approval__c);
        FakeEsig f = new FakeEsig(); f.required = true;
        CqFarCommittee.esig = f;
        CqFarCommittee.Info x = CqFarCommittee.info([SELECT Id, Status__c, Emergency__c, Emergency_Reason__c, Recommended_By__r.Name, Recommended_On__c,
            Committee_Approval__c FROM Field_Action_Review__c WHERE Id = :review.Id]);
        System.assert(x.sign.get('approve').required);
        System.assertEquals(1, x.steps.size());
        System.assert(x.steps[0].mine);
    }
}
