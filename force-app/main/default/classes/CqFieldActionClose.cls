/**
 * CqFieldActionClose: closing a Field Action, signed by its recall coordinator (the field action's owner) through CqEsign,
 * the standard electronic signature (docs/esignature.md). CQ's signature policy for Field Action, Close Field Action, decides
 * whether a password and a comment are needed. The signature, the closure and the audit trail entry are one request: if any
 * part fails, nothing changes. An administrator may close for the coordinator only when CQ's policy asks for no signature.
 */
public with sharing class CqFieldActionClose {
    public static final String ACTION = 'close';

    /** Who signs, and the signature once made, for the Signature card on Closure. */
    public class Signer {
        @AuraEnabled public String name;                 // the recall coordinator: the field action's owner
        @AuraEnabled public Boolean mine = false;        // the person looking is the coordinator
        @AuraEnabled public Boolean canAdmin = false;    // an administrator, who may close for them when no signature is needed
        @AuraEnabled public Boolean closed = false;
        @AuraEnabled public String closedBy; @AuraEnabled public Datetime closedOn;
        @AuraEnabled public Boolean signed = false;
        @AuraEnabled public String signedBy; @AuraEnabled public Datetime signedOn;
        @AuraEnabled public String comment; @AuraEnabled public String meaning;
    }

    @AuraEnabled
    public static Signer getSigner(Id recordId) {
        Field_Action__c fa = [SELECT OwnerId, Owner.Name, Status__c, Closed_By__r.Name, Closed_On__c FROM Field_Action__c WHERE Id = :recordId WITH USER_MODE];
        Signer s = new Signer();
        s.name = fa.Owner.Name; s.mine = fa.OwnerId == UserInfo.getUserId(); s.canAdmin = !s.mine && isAdmin();
        s.closed = fa.Status__c == 'Closed'; s.closedBy = fa.Closed_By__r?.Name; s.closedOn = fa.Closed_On__c;
        for (Field_Action_Record_Activity__c a : [
                SELECT CreatedBy.Name, CreatedDate, Comment__c, Comment_Long__c, Purpose_Of_Signature__c FROM Field_Action_Record_Activity__c
                WHERE Field_Action__c = :recordId AND Activity_Code__c = :ACTION WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1]) {
            s.signed = true; s.signedBy = a.CreatedBy.Name; s.signedOn = a.CreatedDate;
            s.comment = String.isNotBlank(a.Comment_Long__c) ? a.Comment_Long__c : a.Comment__c; s.meaning = a.Purpose_Of_Signature__c;
        }
        return s;
    }

    /**
     * Signs (when CQ's policy asks) and closes. The checklist is checked first, so a field action that cannot close is never
     * signed. The coordinator signs their own field action; nobody signs for them.
     */
    @AuraEnabled
    public static CqFieldActionRecovery.View signAndClose(Id recordId, String summary, String comment, String password) {
        Field_Action__c fa = [SELECT OwnerId FROM Field_Action__c WHERE Id = :recordId WITH USER_MODE];
        Boolean mine = fa.OwnerId == UserInfo.getUserId();
        if (!mine && !isAdmin()) { throw new AuraHandledException('Only the recall coordinator, who owns this field action, can close it.'); }
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(recordId);
        if (v.closed || !v.canClose) { return CqFieldActionRecovery.closeFieldAction(recordId, summary); }   // says why it cannot close
        CqFaSignable.signing = String.isNotBlank(summary) ? summary : String.isNotBlank(v.summary) ? v.summary : v.sSummary;
        CqEsign.sign(recordId, ACTION, comment, password, mine);
        CqFieldActionRecovery.View closed = CqFieldActionRecovery.closeFieldAction(recordId, summary);
        // the record shows the workspace as Complete and keeps its final numbers
        update new Field_Action__c(Id = recordId, Workspace_Step__c = CqFieldActionProgress.COMPLETE);
        CqFieldActionNumbers.refresh(new Set<Id>{ recordId });
        return closed;
    }

    private static Boolean isAdmin() {
        List<SObject> p = Database.query('SELECT PermissionsModifyAllData FROM Profile WHERE Id = \'' + UserInfo.getProfileId() + '\'');
        return !p.isEmpty() && (Boolean) p[0].get('PermissionsModifyAllData');
    }
}
