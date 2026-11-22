@IsTest
private class CqFarEsigPoliciesTest {
    @IsTest
    static void actionsAndParentForAReview() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Esig review');
        insert review;
        CqFarEsigPolicies p = new CqFarEsigPolicies();

        System.assertEquals('approve', p.getApplicableActionForExtensionObject(review.Id, true));
        System.assertEquals('reject', p.getApplicableActionForExtensionObject(review.Id, false));

        Field_Action_Review_Record_Activity__c row = new Field_Action_Review_Record_Activity__c();
        p.setParentByChildRecordId(row, review.Id);
        System.assertEquals(review.Id, row.Field_Action_Review__c);
    }

    @IsTest
    static void otherRecordsAreNotOurs() {
        CqFarEsigPolicies p = new CqFarEsigPolicies();
        System.assertEquals(null, p.getApplicableActionForExtensionObject(null, true));
        System.assertEquals(null, p.getApplicableActionForExtensionObject(UserInfo.getUserId(), true));

        Field_Action_Review_Record_Activity__c row = new Field_Action_Review_Record_Activity__c();
        p.setParentByChildRecordId(row, UserInfo.getUserId());
        System.assertEquals(null, row.Field_Action_Review__c);
        p.setParentByChildRecordId(null, UserInfo.getUserId());
        p.setParentByChildRecordId(new Account(), UserInfo.getUserId());
    }

    @IsTest
    static void approvalStepLeadsBackToTheReview() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Esig review');
        insert review;
        // ids of an approval and a step that do not exist: the lookups find nothing and return null
        Id fakeStep = cqext__CQAPR_Approval_Step__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        Id fakeApproval = cqext__CQAPR_Approval__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        System.assertEquals(null, CqFarEsigPolicies.reviewFor(fakeStep));
        System.assertEquals(null, CqFarEsigPolicies.reviewFor(fakeApproval));
        System.assertEquals(review.Id, CqFarEsigPolicies.reviewFor(review.Id));
    }

    @IsTest
    static void oneProviderEachForReviewAndFieldAction() {
        List<compliancequest.SQX_Extension_Object_Policy_Provider> all = new CqFarEsigPolicies().getAllESigPolicyProviders();
        System.assertEquals(2, all.size());
    }

    @IsTest
    static void aFieldActionSignatureRowLinksToItsFieldAction() {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Esig field action');
        insert fa;
        Field_Action_Record_Activity__c row = new Field_Action_Record_Activity__c();
        new CqFarEsigPolicies().setParentByChildRecordId(row, fa.Id);
        System.assertEquals(fa.Id, row.Field_Action__c);
        System.assertEquals(null, new CqFarEsigPolicies().getApplicableActionForExtensionObject(fa.Id, true), 'no CQ approvals on a field action');
    }
}
