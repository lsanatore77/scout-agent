/**
 * CqActionSignable: the signatures of a CQ Action made in our screens (the assignee completing or skipping a correction),
 * kept in CQ's own Action Record Activity with CQ's action code, so they sit with the action's other activity. Reached by
 * name from CqEsigBridge.SIGNABLE. When CQ writes the row itself while checking the password, nothing more is written.
 */
public with sharing class CqActionSignable implements CqSignable {
    /** What is being signed, set by the action just before it signs: it is kept with the signature. */
    public static String signing;
    // the same words as CqEsigBridge.PASSWORD, kept here so this class compiles on its own
    static final String VERIFIED = 'Password (CQ)';

    public Integer signatureCount(Id recordId) {
        return [SELECT COUNT() FROM compliancequest__SQX_Action_Record_Activity__c
                WHERE compliancequest__SQX_Action__c = :recordId AND compliancequest__Type_of_Activity__c = 'E-Signature' WITH USER_MODE];
    }

    /** The signature row, written once CQ has confirmed the password. CreatedBy and CreatedDate are the signer and time. */
    public void record(Id recordId, String action, String comment, String purpose, String tokenHash) {
        List<String> said = new List<String>();
        if (String.isNotBlank(signing)) { said.add('Signed for: ' + signing + '.'); }
        if (String.isNotBlank(comment)) { said.add('Comment: ' + comment); }
        compliancequest__SQX_Action_Record_Activity__c row = new compliancequest__SQX_Action_Record_Activity__c(
            compliancequest__SQX_Action__c = recordId,
            compliancequest__Activity_Code__c = action,
            compliancequest__Type_of_Activity__c = 'E-Signature',
            compliancequest__Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            compliancequest__Comment_Long__c = String.join(said, '\n').left(32768),
            compliancequest__Modified_By__c = (UserInfo.getName() + ' (' + UserInfo.getUserName() + ') · ' + VERIFIED).left(255),
            compliancequest__Transaction_Id__c = tokenHash == null ? null : tokenHash.left(80));
        Database.insert(row, AccessLevel.USER_MODE);
    }
}
