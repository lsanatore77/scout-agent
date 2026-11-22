/**
 * CqFarSignable: the signatures of a Field Action Review (committee approve and send back), kept in its Record Activity
 * and in its audit trail. Reached by name from CqEsigBridge.SIGNABLE.
 */
public with sharing class CqFarSignable implements CqSignable {
    public Integer signatureCount(Id recordId) {
        return [SELECT COUNT() FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :recordId WITH USER_MODE];
    }

    /**
     * The signature row, written once CQ has confirmed the password, and its entry in the audit trail.
     * CreatedBy and CreatedDate are the signer and time. Signed Content is a fingerprint of the recommendation as it stood
     * when signed, so a later change to the review shows the signature no longer matches it.
     */
    public void record(Id recordId, String action, String comment, String purpose, String tokenHash) {
        String said = comment == null ? '' : comment;
        Field_Action_Review__c r = [
            SELECT Name, Outcome__c, Outcome_Rationale__c, Risk_Level__c, Risk_Score__c, Health_Hazard_Summary__c,
                   Review_Summary__c, Emergency__c, Emergency_Reason__c
            FROM Field_Action_Review__c WHERE Id = :recordId WITH USER_MODE];
        Field_Action_Review_Record_Activity__c row = new Field_Action_Review_Record_Activity__c(
            Field_Action_Review__c = recordId,
            Activity_Code__c = action,
            Type_of_Activity__c = 'E-Signature',
            Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            Comment__c = said.left(255),
            Comment_Long__c = said.left(32768),
            Modified_By__c = UserInfo.getName() + ' (' + UserInfo.getUserName() + ')',
            Verified_By__c = CqEsigBridge.PASSWORD,
            Signed_Content__c = fingerprint(r),
            Transaction_Id__c = tokenHash);
        Database.insert(row, AccessLevel.USER_MODE);
        CqFarAudit.signed(row, r.Name);
    }

    /** SHA-256 of what the committee signs: outcome, rationale, risk, hazard, summary and emergency, in a fixed order. */
    @TestVisible
    private static String fingerprint(Field_Action_Review__c r) {
        String content = String.join(new List<String>{
            'outcome=' + r.Outcome__c, 'rationale=' + r.Outcome_Rationale__c, 'risk=' + r.Risk_Level__c + '/' + r.Risk_Score__c,
            'hazard=' + r.Health_Hazard_Summary__c, 'summary=' + r.Review_Summary__c,
            'emergency=' + r.Emergency__c + '/' + r.Emergency_Reason__c }, '\n');
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(content)));
    }
}
