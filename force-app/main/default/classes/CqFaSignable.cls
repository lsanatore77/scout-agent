/**
 * CqFaSignable: the signatures of a Field Action (closing it), kept in its Record Activity, which the Field Action's
 * audit trail lists. Reached by name from CqEsigBridge.SIGNABLE.
 */
public with sharing class CqFaSignable implements CqSignable {
    /** What is being signed, set by the action just before it signs (the closing summary): it goes into the fingerprint. */
    public static String signing;
    /** Added to Verified By when the signature was made in Demo Mode, so the audit trail shows it. */
    public static final String DEMO = ' · Demo mode';

    public Integer signatureCount(Id recordId) {
        return [SELECT COUNT() FROM Field_Action_Record_Activity__c WHERE Field_Action__c = :recordId WITH USER_MODE];
    }

    /**
     * The signature row, written once CQ has confirmed the password. CreatedBy and CreatedDate are the signer and time.
     * Signed Content is a fingerprint of the closing summary, the CAPA and the verdict as they stood when signed.
     */
    public void record(Id recordId, String action, String comment, String purpose, String tokenHash) {
        String said = comment == null ? '' : comment;
        Field_Action__c fa = [SELECT Name, Verdict__c, CAPA__c, Closure_Summary__c FROM Field_Action__c WHERE Id = :recordId WITH USER_MODE];
        Field_Action_Record_Activity__c row = new Field_Action_Record_Activity__c(
            Field_Action__c = recordId,
            Activity_Code__c = action,
            Type_of_Activity__c = 'E-Signature',
            Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            Comment__c = said.left(255),
            Comment_Long__c = said.left(32768),
            Modified_By__c = UserInfo.getName() + ' (' + UserInfo.getUserName() + ')',
            Verified_By__c = CqEsigBridge.PASSWORD + (CqFieldActionRecovery.demoMode() ? DEMO : ''),
            Signed_Content__c = fingerprint(fa, signing),
            Transaction_Id__c = tokenHash);
        Database.insert(row, AccessLevel.USER_MODE);
    }

    /** SHA-256 of what closing signs: the closing summary, the CAPA and the verdict, in a fixed order. */
    @TestVisible
    private static String fingerprint(Field_Action__c fa, String summary) {
        String content = String.join(new List<String>{
            'summary=' + (summary != null ? summary : fa.Closure_Summary__c), 'capa=' + fa.CAPA__c, 'verdict=' + fa.Verdict__c }, '\n');
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(content)));
    }
}
