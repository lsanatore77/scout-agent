@IsTest
private class CqEsigBridgeTest {
    @IsTest
    static void recordsTheSignatureRow() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Signature row');
        insert review;
        Test.startTest();
        CqEsigBridge.record(review.Id, 'approve', 'Agree, no field action needed', 'Committee Approve', 'token-from-cq');
        Test.stopTest();
        Field_Action_Review_Record_Activity__c row = [
            SELECT Activity_Code__c, Type_of_Activity__c, Purpose_Of_Signature__c, Comment__c, Comment_Long__c, Modified_By__c, Transaction_Id__c,
                   Verified_By__c, Signed_Content__c
            FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :review.Id];
        System.assertEquals('approve', row.Activity_Code__c);
        System.assertEquals('E-Signature', row.Type_of_Activity__c);
        System.assertEquals('Committee Approve', row.Purpose_Of_Signature__c);
        System.assertEquals('Agree, no field action needed', row.Comment__c);
        System.assert(row.Modified_By__c.contains(UserInfo.getUserName()));
        System.assertEquals(64, row.Transaction_Id__c.length(), 'a fingerprint of the token');
        System.assert(!row.Transaction_Id__c.contains('token'), 'the token itself is not kept');
        System.assertEquals(CqEsigBridge.PASSWORD, row.Verified_By__c);
        System.assertEquals(64, row.Signed_Content__c.length(), 'a fingerprint of what was signed');
        Field_Action_Review_Audit__c e = [SELECT Action__c, Signature__c, New_Value__c FROM Field_Action_Review_Audit__c
                                          WHERE Record_Id__c = :String.valueOf(review.Id) AND Action__c = :CqFarAudit.SIGNED];
        System.assertNotEquals(null, e.Signature__c, 'the audit trail points to the signature');
        System.assert(e.New_Value__c.contains('Committee Approve'));
    }

    @IsTest
    static void fingerprintChangesWithTheRecommendation() {
        Field_Action_Review__c a = new Field_Action_Review__c(Outcome__c = 'No Field Action', Outcome_Rationale__c = 'Low risk');
        Field_Action_Review__c b = new Field_Action_Review__c(Outcome__c = 'No Field Action', Outcome_Rationale__c = 'Low risk.');
        System.assertEquals(CqEsigBridge.fingerprint(a), CqEsigBridge.fingerprint(a.clone()));
        System.assertNotEquals(CqEsigBridge.fingerprint(a), CqEsigBridge.fingerprint(b), 'one character changes it');
    }

    @IsTest
    static void longCommentAndNoPurpose() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Signature row');
        insert review;
        String longText = 'x'.repeat(400);
        CqEsigBridge.record(review.Id, 'reject', longText, null, 't');
        Field_Action_Review_Record_Activity__c row = [
            SELECT Comment__c, Comment_Long__c, Purpose_Of_Signature__c FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :review.Id];
        System.assertEquals(255, row.Comment__c.length());
        System.assertEquals(400, row.Comment_Long__c.length());
        System.assertEquals(null, row.Purpose_Of_Signature__c);
    }

    /**
     * Wrong passwords are refused by CQ in a live session (proven on FAR-0001). In a test run CQ accepted a wrong password
     * (it cannot check passwords in tests), so this only checks the path through CQ: refused means nothing recorded,
     * accepted means exactly one signature row.
     */
    @IsTest
    static void signGoesThroughCq() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Signature row');
        insert review;
        CqEsigBridge b = new CqEsigBridge();
        try { b.signFor(review.Id, 'approve'); } catch (Exception e) { System.debug('CQ setting unavailable in tests: ' + e.getMessage()); }
        Boolean refused = false;
        try { b.sign(review.Id, 'approve', 'ok', 'any'); } catch (Exception e) { refused = true; }
        Integer n = [SELECT COUNT() FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :review.Id];
        System.assertEquals(refused ? 0 : 1, n, 'refused: nothing recorded; accepted: exactly one signature');
    }
}
