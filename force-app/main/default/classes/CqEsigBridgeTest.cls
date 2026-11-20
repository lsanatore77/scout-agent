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
            SELECT Activity_Code__c, Type_of_Activity__c, Purpose_Of_Signature__c, Comment__c, Comment_Long__c, Modified_By__c, Transaction_Id__c
            FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :review.Id];
        System.assertEquals('approve', row.Activity_Code__c);
        System.assertEquals('E-Signature', row.Type_of_Activity__c);
        System.assertEquals('Committee Approve', row.Purpose_Of_Signature__c);
        System.assertEquals('Agree, no field action needed', row.Comment__c);
        System.assert(row.Modified_By__c.contains(UserInfo.getUserName()));
        System.assertEquals(64, row.Transaction_Id__c.length(), 'a fingerprint of the token');
        System.assert(!row.Transaction_Id__c.contains('token'), 'the token itself is not kept');
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

    /** CQ refuses a wrong password, or cannot run without a user session in a test: either way nothing is recorded. */
    @IsTest
    static void nothingRecordedWithoutCq() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Signature row');
        insert review;
        CqEsigBridge b = new CqEsigBridge();
        try { b.signFor(review.Id, 'approve'); } catch (Exception e) { System.debug('CQ unavailable in tests: ' + e.getMessage()); }
        Boolean refused = false;
        try { b.sign(review.Id, 'approve', 'ok', 'not-the-password'); } catch (Exception e) { refused = true; }
        System.assert(refused, 'an unconfirmed signature is refused');
        System.assertEquals(0, [SELECT COUNT() FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :review.Id]);
    }
}
