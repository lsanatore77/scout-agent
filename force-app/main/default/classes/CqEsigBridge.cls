/**
 * CqEsigBridge: the one class that calls CQ's electronic signature (compliancequest.SQX_Esig_Policy_Provider).
 * CqFarCommittee creates it by name through CqEsigGateway, so no other class depends on the CQ package's Apex.
 * The password is passed straight to CQ: never stored or logged.
 */
public with sharing class CqEsigBridge implements CqEsigGateway {
    public CqFarCommittee.Sign signFor(Id recordId, String action) {
        CqFarCommittee.Sign g = new CqFarCommittee.Sign();
        compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting c = compliancequest.SQX_Esig_Policy_Provider.retriveEsigSetting(recordId, action);
        if (c != null) {
            g.required = c.enabled == true && c.required == true;
            g.comment = g.required && c.comment == true;
            g.purpose = c.purposeOfSignature; g.sso = c.sso_enabled == true; g.mfa = c.mfa_enabled == true;
        }
        return g;
    }

    /**
     * CQ checks the password and returns a validation token. For an add-on record type CQ does not write the
     * signature itself, so once CQ has confirmed the token we write the signature row on the review: who signed,
     * when, the action, its meaning and the comment. Nothing is recorded, and nothing acted on, unless CQ confirms.
     */
    public void sign(Id recordId, String action, String comment, String password) {
        Integer before = rows(recordId);
        String token;
        try {
            token = compliancequest.SQX_Esig_Policy_Provider.validateEsig(recordId, action, UserInfo.getUserName(), password, comment);
        } catch (Exception e) {
            throw new AuraHandledException('Signature not accepted. Check your password and try again.');
        }
        if (rows(recordId) > before) { return; }      // CQ recorded it
        if (String.isBlank(token) || compliancequest.SQX_Esig_Policy_Provider.isTokenValid(token) != true) {
            throw new AuraHandledException('Signature not accepted: CQ did not confirm it. Try again.');
        }
        String purpose;
        try {
            compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting c = compliancequest.SQX_Esig_Policy_Provider.retriveEsigSetting(recordId, action);
            purpose = c == null ? null : c.purposeOfSignature;
        } catch (Exception e) {
            purpose = null;
        }
        String said = comment == null ? '' : comment;
        Field_Action_Review_Record_Activity__c row = new Field_Action_Review_Record_Activity__c(
            Field_Action_Review__c = recordId,
            Activity_Code__c = action,
            Type_of_Activity__c = 'E-Signature',
            Purpose_Of_Signature__c = purpose == null ? null : purpose.left(80),
            Comment__c = said.left(255),
            Comment_Long__c = said.left(32768),
            Modified_By__c = UserInfo.getName() + ' (' + UserInfo.getUserName() + ')',
            // a fingerprint of CQ's token, so the row ties to that validation without keeping the token
            Transaction_Id__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token))).left(64));
        Database.insert(row, AccessLevel.USER_MODE);
    }

    private static Integer rows(Id recordId) {
        return [SELECT COUNT() FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :recordId WITH USER_MODE];
    }
}
