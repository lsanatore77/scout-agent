/**
 * CqNcSignable: the signatures of a Nonconformance made in our screens (the dispositioner completing the disposition), kept
 * in CQ's own NC Record Activity with CQ's action code, so they sit with the NC's other signatures. Reached by name from
 * CqEsigBridge.SIGNABLE. When CQ writes the row itself while checking the password, nothing more is written.
 */
public with sharing class CqNcSignable implements CqSignable {
    /** What is being signed, set by the action just before it signs (each lot and its split): it is kept with the signature. */
    public static String signing;
    // the same words as CqEsigBridge.PASSWORD and CqFaSignable.DEMO, kept here so this class compiles on its own
    static final String VERIFIED = 'Password (CQ)';
    static final String DEMO_NOTE = ' · Demo mode';

    public Integer signatureCount(Id recordId) {
        return [SELECT COUNT() FROM compliancequest__SQX_NC_Record_Activity__c WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE];
    }

    /** The signature row, written once CQ has confirmed the password. CreatedBy and CreatedDate are the signer and time. */
    public void record(Id recordId, String action, String comment, String purpose, String tokenHash) {
        List<String> said = new List<String>();
        if (String.isNotBlank(signing)) { said.add('Signed for: ' + signing + '.'); }
        if (String.isNotBlank(comment)) { said.add('Comment: ' + comment); }
        String text = String.join(said, '\n');
        // Demo Mode (Field Action Settings): read directly, so this class does not depend on CQ's signature classes to compile
        Field_Action_Settings__c fs = Field_Action_Settings__c.getOrgDefaults();
        Boolean demo = fs != null && fs.Demo_Mode__c == true;
        compliancequest__SQX_NC_Record_Activity__c row = new compliancequest__SQX_NC_Record_Activity__c(
            compliancequest__SQX_Nonconformance__c = recordId,
            compliancequest__Activity_Code2__c = action,
            compliancequest__Type_of_Activity__c = 'E-Signature',
            compliancequest__Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            compliancequest__Comment_Long__c = text.left(32768),
            compliancequest__Modified_By__c = (UserInfo.getName() + ' (' + UserInfo.getUserName() + ') · ' + VERIFIED + (demo ? DEMO_NOTE : '')).left(255),
            compliancequest__Transaction_Id__c = tokenHash == null ? null : tokenHash.left(80));
        Database.insert(row, AccessLevel.USER_MODE);
    }
}
