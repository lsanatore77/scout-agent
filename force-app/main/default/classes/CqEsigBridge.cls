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
            g.detail = 'action=' + action + ' enabled=' + c.enabled + ' required=' + c.required + ' comment=' + c.comment
                + ' purpose=' + c.purposeOfSignature + ' sso=' + c.sso_enabled + ' mfa=' + c.mfa_enabled + ' cqAction=' + c.action;
        } else {
            g.detail = 'action=' + action + ' CQ returned no setting';
        }
        return g;
    }

    /** Recorded when CQ adds its Record Activity row on the review; never treated as signed otherwise. */
    public void sign(Id recordId, String action, String comment, String password) {
        Integer before = rows(recordId);
        String result;
        try {
            result = compliancequest.SQX_Esig_Policy_Provider.validateEsig(recordId, action, UserInfo.getUserName(), password, comment);
        } catch (Exception e) {
            throw new AuraHandledException('Signature not accepted: ' + e.getMessage());
        }
        // CQ's two-step route: a validation token, then the signed action, which writes the signature row
        if (rows(recordId) == before && String.isNotBlank(result) && compliancequest.SQX_Esig_Policy_Provider.isTokenValid(result)) {
            try {
                compliancequest.SQX_Esig_Policy_Provider.performActionOnObject(recordId, action, comment, result);
            } catch (Exception e) {
                throw new AuraHandledException('Signature not recorded: ' + e.getMessage());
            }
        }
        if (rows(recordId) == before) {
            // nothing recorded: never act unsigned. CQ's answer is shown so the cause can be found.
            throw new AuraHandledException('Signature not accepted' + (String.isBlank(result) ? '.' : ': ' + result.left(200)));
        }
    }

    private static Integer rows(Id recordId) {
        return [SELECT COUNT() FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c = :recordId];
    }
}
