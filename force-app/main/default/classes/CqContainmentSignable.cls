/**
 * CqContainmentSignable: the signatures of a CQ Containment made in our screens (the assignee completing it). CQ keeps no
 * activity log of its own for containments, which belong to a Nonconformance, so the signature goes in the NC's Record
 * Activity with CQ's action code (containment_complete, in the text Activity Code) and the containment named in the text. Reached by name from
 * CqEsigBridge.SIGNABLE. When CQ writes the row itself while checking the password, nothing more is written.
 */
public with sharing class CqContainmentSignable implements CqSignable {
    /** What is being signed, set by the action just before it signs: it is kept with the signature. */
    public static String signing;
    // the same words as CqEsigBridge.PASSWORD, kept here so this class compiles on its own
    static final String VERIFIED = 'Password (CQ)';

    static Id ncOf(Id containmentId) {
        return [SELECT compliancequest__SQX_Nonconformance__c FROM compliancequest__SQX_Containment__c WHERE Id = :containmentId WITH USER_MODE].compliancequest__SQX_Nonconformance__c;
    }

    public Integer signatureCount(Id recordId) {
        Id ncId = ncOf(recordId);
        return ncId == null ? 0 : [SELECT COUNT() FROM compliancequest__SQX_NC_Record_Activity__c WHERE compliancequest__SQX_Nonconformance__c = :ncId WITH USER_MODE];
    }

    /** The signature row, written once CQ has confirmed the password. CreatedBy and CreatedDate are the signer and time. */
    public void record(Id recordId, String action, String comment, String purpose, String tokenHash) {
        Id ncId = ncOf(recordId);
        if (ncId == null) { throw new AuraHandledException('This containment is not on a nonconformance, so its signature has nowhere to be kept.'); }
        List<String> said = new List<String>();
        if (String.isNotBlank(signing)) { said.add('Signed for: ' + signing + '.'); }
        if (String.isNotBlank(comment)) { said.add('Comment: ' + comment); }
        compliancequest__SQX_NC_Record_Activity__c row = new compliancequest__SQX_NC_Record_Activity__c(
            compliancequest__SQX_Nonconformance__c = ncId,
            compliancequest__Activity_Code__c = action,   // the text code: containment_complete is not among the NC's Activity Code2 values
            compliancequest__Type_of_Activity__c = 'E-Signature',
            compliancequest__Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            compliancequest__Comment_Long__c = String.join(said, '\n').left(32768),
            compliancequest__Modified_By__c = (UserInfo.getName() + ' (' + UserInfo.getUserName() + ') · ' + VERIFIED).left(255),
            compliancequest__Transaction_Id__c = tokenHash == null ? null : tokenHash.left(80));
        Database.insert(row, AccessLevel.USER_MODE);
    }
}
