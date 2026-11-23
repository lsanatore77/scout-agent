/**
 * CqEsigBridge: the one class that calls CQ's electronic signature (compliancequest.SQX_Esig_Policy_Provider).
 * CqEsign creates it by name through CqEsigGateway, so no other class depends on the CQ package's Apex.
 * The password is passed straight to CQ: never stored or logged.
 */
public with sharing class CqEsigBridge implements CqEsigGateway {
    public static final String PASSWORD = 'Password (CQ)';

    /** The class that keeps each signable object's signatures (CqSignable). A new signable object is added here. */
    private static final Map<String, String> SIGNABLE = new Map<String, String>{
        'Field_Action_Review__c' => 'CqFarSignable',
        'Field_Action__c' => 'CqFaSignable',
        'compliancequest__SQX_Nonconformance__c' => 'CqNcSignable'
    };
    public static CqSignable signable(Id recordId) {
        String n = recordId == null ? null : SIGNABLE.get(String.valueOf(recordId.getSObjectType()));
        if (n == null) { throw new AuraHandledException('This record cannot be signed.'); }
        return (CqSignable) Type.forName(n).newInstance();
    }

    /**
     * CQ's answer for each record and action, kept for this request only. Asking CQ takes it about three seconds (it runs
     * its signature flows each time), and a signature asked twice: once to check a signature is needed, once for its meaning.
     */
    private Map<String, compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting> asked =
        new Map<String, compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting>();
    private compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting setting(Id recordId, String action) {
        String key = recordId + '|' + action;
        if (!asked.containsKey(key)) { asked.put(key, compliancequest.SQX_Esig_Policy_Provider.retriveEsigSetting(recordId, action)); }
        return asked.get(key);
    }

    public CqEsign.Policy signFor(Id recordId, String action) {
        CqEsign.Policy g = new CqEsign.Policy();
        compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting c = setting(recordId, action);
        if (c != null) {
            g.required = c.enabled == true && c.required == true;
            g.comment = g.required && c.comment == true;
            g.purpose = c.purposeOfSignature; g.sso = c.sso_enabled == true; g.mfa = c.mfa_enabled == true;
        }
        return g;
    }

    /**
     * CQ checks the password and returns a validation token. For an add-on record type CQ does not write the
     * signature itself, so once CQ has confirmed the token the object writes its signature row (CqSignable): who signed,
     * when, the action, its meaning and the comment. Nothing is recorded, and nothing acted on, unless CQ confirms.
     */
    public void sign(Id recordId, String action, String comment, String password) {
        CqSignable keeper = signable(recordId);
        Integer before = keeper.signatureCount(recordId);
        String token;
        try {
            token = compliancequest.SQX_Esig_Policy_Provider.validateEsig(recordId, action, UserInfo.getUserName(), password, comment);
        } catch (Exception e) {
            throw new AuraHandledException('Signature not accepted. Check your password and try again.');
        }
        if (keeper.signatureCount(recordId) > before) { return; }      // CQ recorded it
        if (String.isBlank(token) || compliancequest.SQX_Esig_Policy_Provider.isTokenValid(token) != true) {
            throw new AuraHandledException('Signature not accepted: CQ did not confirm it. Try again.');
        }
        String purpose;
        try {
            compliancequest.SQX_Esig_Policy_Provider.SQX_Esig_Signature_Setting c = setting(recordId, action);   // already asked when the action was checked
            purpose = c == null ? null : c.purposeOfSignature;
        } catch (Exception e) {
            purpose = null;
        }
        record(recordId, action, comment, purpose, token);
    }

    /** The object's signature row and audit trail entry, with a fingerprint of CQ's token (the token itself is not kept). */
    @TestVisible
    private static void record(Id recordId, String action, String comment, String purpose, String token) {
        signable(recordId).record(recordId, action, comment, purpose,
            EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token))).left(64));
    }
}
