/**
 * CqEsign: the one way the app asks CQ's electronic signature policy and signs (the standard: docs/esignature.md).
 * The screen side is the c-cq-sign-seat component.
 *
 * An action that can be signed calls CqEsign.sign first, in the same request as its own changes. When CQ's policy asks
 * for a signature, CQ checks the password, the object writes its signature row and audit trail entry (CqSignable), and
 * only then does the action go on. If any of that fails, nothing is changed. The password goes straight to CQ: never
 * stored or logged.
 */
public with sharing class CqEsign {
    /** What CQ's electronic signature policy asks for one action on one record. */
    public class Policy {
        @AuraEnabled public Boolean required = false;
        @AuraEnabled public Boolean comment = false;      // a comment is required with the signature
        @AuraEnabled public String purpose;               // the meaning of the signature, from CQ
        @AuraEnabled public Boolean sso = false;
        @AuraEnabled public Boolean mfa = false;
        @AuraEnabled public Boolean unknown = false;      // CQ could not be asked: the action is refused rather than taken unsigned
    }

    /** CQ's electronic signature, reached by name through CqEsigGateway (see there for why). Tests put in a stand-in. */
    @TestVisible
    private static CqEsigGateway gateway {
        get { if (gateway == null) { gateway = (CqEsigGateway) Type.forName('CqEsigBridge').newInstance(); } return gateway; }
        set;
    }

    /**
     * What CQ's policy asks for an action on a record. CQ is asked in the user's session (its check fails without one).
     * If it cannot be asked, the answer comes back unknown and the action is refused, never taken unsigned.
     */
    public static Policy policyFor(Id recordId, String action) {
        try {
            Policy g = gateway.signFor(recordId, action);
            return g == null ? new Policy() : g;
        } catch (Exception e) {
            Policy g = new Policy(); g.unknown = true;
            return g;
        }
    }

    /**
     * What CQ's policy asks for each of up to four actions on a record, for the signature seat. One request for all of them:
     * the seat keeps the answer for the browser tab (it only shapes the seat; every signature is checked again in sign).
     */
    @AuraEnabled
    public static Map<String, Policy> getPolicies(Id recordId, List<String> actions) {
        if (recordId == null || actions == null || actions.isEmpty() || actions.size() > 4) {
            throw new AuraHandledException('Name the record and the actions to check.');
        }
        Map<String, Policy> out = new Map<String, Policy>();
        for (String a : actions) { out.put(a, policyFor(recordId, a)); }
        return out;
    }

    /**
     * Signs an action on a record when CQ's policy asks for a signature. Call it before the action changes anything, in the
     * same request. isSigner: the running user is the person this signature belongs to; a signature is never given for
     * someone else. Returns true when a signature was recorded, false when CQ's policy asks for none. Otherwise it throws,
     * and nothing is changed.
     */
    public static Boolean sign(Id recordId, String action, String comment, String password, Boolean isSigner) {
        Policy g = policyFor(recordId, action);
        if (g.unknown) { throw new AuraHandledException('Could not check whether this needs an electronic signature, so nothing was changed. Try again.'); }
        if (!g.required) { return false; }
        if (isSigner != true) { throw new AuraHandledException('This needs the electronic signature of the person it is assigned to.'); }
        if (String.isBlank(password)) { throw new AuraHandledException('Type your password to sign.'); }
        if (g.comment && String.isBlank(comment)) { throw new AuraHandledException('A comment is required with your signature.'); }
        gateway.sign(recordId, action, comment, password);
        return true;
    }
}
