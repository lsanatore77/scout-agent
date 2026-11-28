/**
 * CqImplementWorkspace: the NC owner's page on a nonconformance in Implement (Lou, 27 Nov). Every correction on the NC
 * with who has it, when it is due and where it stands; the owner chases what is late (Send Reminder, Reassign) and
 * verifies what is done when CQ asks for verification. An owner who is also an assignee completes their own correction
 * here, through the same code as the assignee's page (CqCorrectionWorkspace), so the checks and the signature are the same.
 *
 * Verify follows CQ's own Verify (CQ_Quick_Action__mdt CQUI_Action_verify): Activity Code 'implementation_verify' with the
 * comment in Verified Comments. Send Back opens CQ's own Reopen. Reassign changes the action's assignee. Send Reminder
 * sends CQ's own task notification (CQ_Task_Custom_Notification) to the assignee: the bell, and the mobile app.
 * In Verification (every correction done, CQ has completed the NC) the owner closes it here: Resolution Effective or
 * Ineffective (the only values CQ allows once the NC is Complete), the closing summary in CQ's Comments, and the owner's
 * signature, through CQ's own Close (Activity Code 'close'). No override: while a correction is open the NC is not
 * Complete and close() refuses. Reopen Implementation and Escalate to CAPA open CQ's own actions.
 */
public with sharing class CqImplementWorkspace {
    public static final String VERIFY = 'implementation_verify';
    public static final String CLOSE = 'close';
    static final Set<String> RESOLUTIONS = new Set<String>{ 'Effective', 'Ineffective' };
    static final String NOTIFY_TYPE = 'CQ_Task_Custom_Notification';

    public class Row {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String description;
        @AuraEnabled public String type; @AuraEnabled public String status; @AuraEnabled public Date due; @AuraEnabled public Date completedOn;
        @AuraEnabled public String completedBy; @AuraEnabled public String remark; @AuraEnabled public String skipReason;
        @AuraEnabled public Id assigneeId; @AuraEnabled public String assignee; @AuraEnabled public Boolean mine = false;
        @AuraEnabled public Boolean needsVerification = false; @AuraEnabled public Id verifierId; @AuraEnabled public String verifier;
        @AuraEnabled public Date verifiedOn; @AuraEnabled public String verifiedBy; @AuraEnabled public String verifiedComment;
        @AuraEnabled public Boolean toVerify = false;     // done, CQ asks for verification, and nobody has verified it yet
        @AuraEnabled public Boolean canVerify = false;    // the running user is the one to verify it
        @AuraEnabled public List<String> files = new List<String>();
    }
    public class View {
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public String ncTitle; @AuraEnabled public String stage;
        @AuraEnabled public String stageKey; @AuraEnabled public String partNumber; @AuraEnabled public String lot; @AuraEnabled public String owner;
        @AuraEnabled public Boolean isOwner = false; @AuraEnabled public String rootCause;
        @AuraEnabled public List<Row> rows = new List<Row>();
        @AuraEnabled public Boolean canNotify = false;    // CQ's task notification type is in the org
        @AuraEnabled public String status; @AuraEnabled public String resolution; @AuraEnabled public String closeComment;
        @AuraEnabled public Date closedOn; @AuraEnabled public Id capaId; @AuraEnabled public String capaName;
        @AuraEnabled public Boolean canClose = false;     // Complete (in Verification) and the running user owns it
        @AuraEnabled public Boolean closed = false;
    }
    public class Result { @AuraEnabled public String message; @AuraEnabled public Boolean signed = false; }

    @AuraEnabled
    public static View getView(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = nc(recordId);
        View v = new View();
        v.ncId = nc.Id; v.ncName = nc.Name; v.ncTitle = nc.compliancequest__NC_Title__c;
        v.stageKey = nc.compliancequest__Record_Stage__c;
        v.partNumber = nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
        v.lot = nc.compliancequest__Lot_Number__c; v.owner = nc.Owner.Name;
        v.isOwner = isOwner(nc);
        v.status = nc.compliancequest__Status__c; v.resolution = nc.compliancequest__Resolution__c; v.closeComment = nc.compliancequest__Closure_Comment__c;
        v.closedOn = nc.compliancequest__Close_Date__c; v.capaId = nc.compliancequest__SQX_CAPA__c;
        v.capaName = nc.compliancequest__SQX_CAPA__r == null ? null : nc.compliancequest__SQX_CAPA__r.Name;
        v.closed = nc.compliancequest__Status__c == 'Closed';
        v.canClose = v.isOwner && nc.compliancequest__Status__c == 'Complete';
        for (compliancequest__SQX_Nonconformance__c s : [SELECT toLabel(compliancequest__Record_Stage__c) FROM compliancequest__SQX_Nonconformance__c WHERE Id = :nc.Id WITH USER_MODE]) {
            v.stage = s.compliancequest__Record_Stage__c;
        }
        if (nc.compliancequest__SQX_Investigation__c != null) {
            for (compliancequest__SQX_Root_Cause__c r : [
                    SELECT compliancequest__SQX_Root_Cause_Code__r.Name, toLabel(compliancequest__Category__c), compliancequest__Description__c
                    FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :nc.compliancequest__SQX_Investigation__c
                    WITH USER_MODE ORDER BY CreatedDate LIMIT 1]) {
                String head = r.compliancequest__SQX_Root_Cause_Code__r != null ? r.compliancequest__SQX_Root_Cause_Code__r.Name : r.compliancequest__Category__c;
                v.rootCause = String.isNotBlank(r.compliancequest__Description__c) ? r.compliancequest__Description__c.stripHtmlTags().left(200) : head;
            }
        }
        Id me = UserInfo.getUserId();
        Map<Id, Row> byId = new Map<Id, Row>();
        for (compliancequest__SQX_Action__c a : [
                SELECT Id, Name, compliancequest__Title__c, compliancequest__Description__c, compliancequest__Plan_Type__c, compliancequest__Status__c,
                       compliancequest__Due_Date__c, compliancequest__Completion_Date__c, compliancequest__Completed_By__c, compliancequest__Remark__c,
                       compliancequest__Activity_Comment__c, compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name,
                       compliancequest__Verification_Required__c, compliancequest__SQX_Verification_User__c, compliancequest__SQX_Verification_User__r.Name,
                       compliancequest__Verified_Date__c, compliancequest__Verified_By__c, compliancequest__Verified_Comments__c
                FROM compliancequest__SQX_Action__c
                WHERE compliancequest__SQX_Nonconformance__c = :nc.Id AND compliancequest__Status__c != null
                WITH USER_MODE ORDER BY compliancequest__Due_Date__c NULLS LAST, Name LIMIT 200]) {
            Row r = new Row();
            r.id = a.Id; r.name = a.Name; r.title = a.compliancequest__Title__c; r.description = a.compliancequest__Description__c;
            r.type = a.compliancequest__Plan_Type__c; r.status = a.compliancequest__Status__c; r.due = a.compliancequest__Due_Date__c;
            r.completedOn = a.compliancequest__Completion_Date__c; r.completedBy = a.compliancequest__Completed_By__c;
            r.remark = a.compliancequest__Remark__c; r.skipReason = a.compliancequest__Status__c == 'Skipped' ? a.compliancequest__Activity_Comment__c : null;
            r.assigneeId = a.compliancequest__SQX_User__c; r.assignee = a.compliancequest__SQX_User__r == null ? null : a.compliancequest__SQX_User__r.Name;
            r.mine = a.compliancequest__SQX_User__c == me;
            r.needsVerification = a.compliancequest__Verification_Required__c == 'Yes';
            r.verifierId = a.compliancequest__SQX_Verification_User__c;
            r.verifier = a.compliancequest__SQX_Verification_User__r == null ? null : a.compliancequest__SQX_Verification_User__r.Name;
            r.verifiedOn = a.compliancequest__Verified_Date__c; r.verifiedBy = a.compliancequest__Verified_By__c; r.verifiedComment = a.compliancequest__Verified_Comments__c;
            r.toVerify = r.needsVerification && r.status == 'Complete' && r.verifiedOn == null;
            // the named verifier verifies; with nobody named, the NC owner does
            r.canVerify = r.toVerify && (r.verifierId != null ? r.verifierId == me : v.isOwner);
            v.rows.add(r);
            byId.put(a.Id, r);
        }
        if (!byId.isEmpty()) {
            for (ContentDocumentLink l : [SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension FROM ContentDocumentLink
                                          WHERE LinkedEntityId IN :byId.keySet() ORDER BY SystemModstamp LIMIT 200]) {
                Row r = byId.get(l.LinkedEntityId);
                if (r != null && r.files.size() < 5) {
                    r.files.add(l.ContentDocument.Title + (String.isBlank(l.ContentDocument.FileExtension) ? '' : '.' + l.ContentDocument.FileExtension));
                }
            }
        }
        v.canNotify = notifyTypeId() != null;
        return v;
    }

    /** The owner's own correction, completed or skipped from the NC: the assignee's page does the work and the checks. */
    @AuraEnabled
    public static Result complete(Id actionId, String whatWasDone, String completedOn, String comment, String password) {
        CqCorrectionWorkspace.Result r = CqCorrectionWorkspace.complete(actionId, whatWasDone, completedOn, comment, password);
        Result res = new Result(); res.signed = r.signed; res.message = 'Completed.'; return res;
    }
    @AuraEnabled
    public static Result skip(Id actionId, String reason, String comment, String password) {
        CqCorrectionWorkspace.Result r = CqCorrectionWorkspace.skip(actionId, reason, comment, password);
        Result res = new Result(); res.signed = r.signed; res.message = 'Skipped.'; return res;
    }

    /** Verify a done correction: the verifier confirms it was done and worked, signing first when CQ's policy asks. */
    @AuraEnabled
    public static Result verify(Id actionId, String verifiedComment, String comment, String password) {
        compliancequest__SQX_Action__c a = action(actionId);
        compliancequest__SQX_Nonconformance__c nc = nc(a.compliancequest__SQX_Nonconformance__c);
        Boolean waiting = a.compliancequest__Verification_Required__c == 'Yes' && a.compliancequest__Status__c == 'Complete' && a.compliancequest__Verified_Date__c == null;
        if (!waiting) { throw new AuraHandledException(a.Name + ' is not waiting for verification.'); }
        Boolean mineToVerify = a.compliancequest__SQX_Verification_User__c != null ? a.compliancequest__SQX_Verification_User__c == UserInfo.getUserId() : isOwner(nc);
        if (!mineToVerify) {
            throw new AuraHandledException('Only ' + (a.compliancequest__SQX_Verification_User__r == null ? 'the NC owner' : a.compliancequest__SQX_Verification_User__r.Name) + ' can verify ' + a.Name + '.');
        }
        if (String.isBlank(verifiedComment)) { throw new AuraHandledException('Say how you checked it.'); }
        Result res = new Result();
        Savepoint sp = Database.setSavepoint();
        CqActionSignable.signing = ('verifying ' + a.Name + ', ' + a.compliancequest__Title__c).left(1000);
        try {
            res.signed = CqEsign.sign(a.Id, VERIFY, comment, password, true);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        }
        try {
            update as user new compliancequest__SQX_Action__c(Id = a.Id, compliancequest__Activity_Code__c = VERIFY,
                compliancequest__Verified_Comments__c = verifiedComment.trim().left(32768));
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(a.Name + ' was not verified: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            Database.rollback(sp);
            throw new AuraHandledException(a.Name + ' was not verified: ' + CqSave.DENIED);
        }
        res.message = a.Name + ' verified.';
        return res;
    }

    /** The owner closes the NC once every correction is done: the resolution, the closing summary, and their signature. */
    @AuraEnabled
    public static Result close(Id recordId, String resolution, String summary, String comment, String password) {
        compliancequest__SQX_Nonconformance__c nc = nc(recordId);
        if (!isOwner(nc)) { throw new AuraHandledException('Only the NC owner can close ' + nc.Name + '.'); }
        if (nc.compliancequest__Status__c != 'Complete') {
            throw new AuraHandledException(nc.compliancequest__Status__c == 'Closed' ? nc.Name + ' is already closed.' : nc.Name + ' is not ready to close: every correction has to be done first.');
        }
        if (!RESOLUTIONS.contains(resolution)) { throw new AuraHandledException('Pick Effective or Ineffective.'); }
        if (String.isBlank(summary)) { throw new AuraHandledException('Write the closing summary.'); }
        Result res = new Result();
        Savepoint sp = Database.setSavepoint();
        CqNcSignable.signing = ('closing ' + nc.Name + ' as ' + resolution).left(1000);
        try {
            res.signed = CqEsign.sign(nc.Id, CLOSE, comment, password, true);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        }
        try {
            update as user new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = CLOSE,
                compliancequest__Resolution__c = resolution, compliancequest__Closure_Comment__c = summary.trim().left(32768));
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(nc.Name + ' was not closed: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            Database.rollback(sp);
            throw new AuraHandledException(nc.Name + ' was not closed: ' + CqSave.DENIED);
        }
        res.message = nc(nc.Id).compliancequest__Status__c == 'Closed' ? nc.Name + ' closed, ' + resolution + '.' : nc.Name + ' was saved, but CQ did not close it.';
        return res;
    }

    /** The owner gives an open correction to someone else. */
    @AuraEnabled
    public static Result reassign(Id actionId, Id userId) {
        compliancequest__SQX_Action__c a = ownersOpen(actionId);
        if (userId == null || userId.getSObjectType() != User.SObjectType) { throw new AuraHandledException('Pick the person to give it to.'); }
        if (userId == a.compliancequest__SQX_User__c) { throw new AuraHandledException('It is already assigned to them.'); }
        List<User> u = Database.query('SELECT Id, Name FROM User WHERE Id = :userId AND IsActive = true LIMIT 1');   // dynamic, as elsewhere: IsActive does not compile here
        if (u.isEmpty()) { throw new AuraHandledException('That person is not an active user.'); }
        try {
            update as user new compliancequest__SQX_Action__c(Id = a.Id, compliancequest__SQX_User__c = userId);
        } catch (DmlException e) {
            throw new AuraHandledException(a.Name + ' was not reassigned: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            throw new AuraHandledException(a.Name + ' was not reassigned: ' + CqSave.DENIED);
        }
        Result res = new Result(); res.message = a.Name + ' is now assigned to ' + u[0].Name + '.'; return res;
    }

    /** The owner nudges the assignee of an open correction: CQ's task notification, in the bell and the mobile app. */
    @AuraEnabled
    public static Result sendReminder(Id actionId) {
        compliancequest__SQX_Action__c a = ownersOpen(actionId);
        if (a.compliancequest__SQX_User__c == null) { throw new AuraHandledException(a.Name + ' has no assignee to remind.'); }
        Id typeId = notifyTypeId();
        if (typeId == null) { throw new AuraHandledException('This org has no CQ task notification type, so reminders cannot be sent.'); }
        String due = a.compliancequest__Due_Date__c == null ? '' : a.compliancequest__Due_Date__c < Date.today()
            ? ', overdue since ' + a.compliancequest__Due_Date__c.format() : ', due ' + a.compliancequest__Due_Date__c.format();
        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setNotificationTypeId(typeId);
        n.setTargetId(a.Id);
        n.setTitle(('Reminder: ' + a.Name + due).left(250));
        n.setBody((UserInfo.getName() + ' asks you to complete ' + a.Name + ': ' + a.compliancequest__Title__c).left(750));
        try {
            n.send(new Set<String>{ String.valueOf(a.compliancequest__SQX_User__c) });
        } catch (Exception e) {
            throw new AuraHandledException('The reminder was not sent: ' + e.getMessage());
        }
        Result res = new Result(); res.message = 'Reminder sent to ' + a.compliancequest__SQX_User__r.Name + '.'; return res;
    }

    static compliancequest__SQX_Action__c ownersOpen(Id actionId) {
        compliancequest__SQX_Action__c a = action(actionId);
        if (!isOwner(nc(a.compliancequest__SQX_Nonconformance__c))) { throw new AuraHandledException('Only the NC owner can do this.'); }
        if (a.compliancequest__Status__c != 'Open') { throw new AuraHandledException(a.Name + ' is ' + a.compliancequest__Status__c + ', so it can no longer be changed here.'); }
        return a;
    }

    static Boolean isOwner(compliancequest__SQX_Nonconformance__c nc) {
        if (nc.OwnerId == UserInfo.getUserId()) { return true; }
        // an administrator stands in for the owner (dynamic, as in CqFieldActionClose: the field does not compile here)
        List<SObject> p = Database.query('SELECT PermissionsModifyAllData FROM Profile WHERE Id = \'' + UserInfo.getProfileId() + '\'');
        return !p.isEmpty() && (Boolean) p[0].get('PermissionsModifyAllData');
    }

    static Id notifyTypeId() {
        String typeName = NOTIFY_TYPE;   // a local for the dynamic query's bind
        for (SObject t : Database.query('SELECT Id FROM CustomNotificationType WHERE DeveloperName = :typeName LIMIT 1')) { return t.Id; }
        return null;
    }

    static compliancequest__SQX_Nonconformance__c nc(Id recordId) {
        if (recordId == null || recordId.getSObjectType() != compliancequest__SQX_Nonconformance__c.SObjectType) { throw new AuraHandledException('This page works on a CQ nonconformance.'); }
        return [SELECT Id, Name, OwnerId, Owner.Name, compliancequest__NC_Title__c, compliancequest__Record_Stage__c, compliancequest__Lot_Number__c,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__SQX_Investigation__c, compliancequest__Status__c,
                       compliancequest__Resolution__c, compliancequest__Closure_Comment__c, compliancequest__Close_Date__c,
                       compliancequest__SQX_CAPA__c, compliancequest__SQX_CAPA__r.Name
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
    }

    static compliancequest__SQX_Action__c action(Id actionId) {
        if (actionId == null || actionId.getSObjectType() != compliancequest__SQX_Action__c.SObjectType) { throw new AuraHandledException('Pick a correction.'); }
        return [SELECT Id, Name, compliancequest__Title__c, compliancequest__Status__c, compliancequest__Due_Date__c, compliancequest__SQX_Nonconformance__c,
                       compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name, compliancequest__Verification_Required__c,
                       compliancequest__SQX_Verification_User__c, compliancequest__SQX_Verification_User__r.Name, compliancequest__Verified_Date__c
                FROM compliancequest__SQX_Action__c WHERE Id = :actionId WITH USER_MODE];
    }
}
