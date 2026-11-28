/**
 * CqCorrectionWorkspace: the assignee's page on a CQ Action, usually a correction on an NC (Implement): what to do, why it
 * matters, the procedure to follow, and Complete or Skip. Others see it read-only.
 *
 * complete() and skip() follow CQ's own Complete and Skip actions (CQ_Quick_Action__mdt CQUI_Action_Complete and
 * CQUI_Action_Skip): Activity Code 'implementation_complete' with the sign-off comment in Remark and the completion date,
 * or 'implementation_skip' with the reason in Activity Comment. CQ then closes the action and, when nothing is left on the
 * NC, completes the NC. The assignee signs first when CQ's policy asks (CqEsign; logged by CqActionSignable).
 * Request Extension opens CQ's own action, since extensions go through CQ's approval.
 *
 * The procedure to follow is optional: a current controlled document linked on the NC, or named in the correction's title
 * or description (for example SOP-PTCA-060). Its PDF (secondary content) is shown if it has one, otherwise its primary file.
 */
public with sharing class CqCorrectionWorkspace {
    public static final String COMPLETE = 'implementation_complete';
    public static final String SKIP = 'implementation_skip';
    // a document number: letters, then dash-separated parts with at least one more part, for example SOP-PTCA-060 or WI-000001
    static final Pattern DOC_NO = Pattern.compile('\\b[A-Z]{2,}[A-Z0-9]*(?:-[A-Z0-9]+)+\\b');

    public class Procedure {
        @AuraEnabled public Id id; @AuraEnabled public String docNumber; @AuraEnabled public String title;
        @AuraEnabled public String revision; @AuraEnabled public Date effective;
        @AuraEnabled public Id contentDocumentId; @AuraEnabled public Id versionId; @AuraEnabled public String fileType;
        @AuraEnabled public String source;   // where it came from: Linked on the NC, Named in the correction
    }
    public class View {
        @AuraEnabled public Id actionId; @AuraEnabled public String name; @AuraEnabled public String title;
        @AuraEnabled public String description; @AuraEnabled public String type; @AuraEnabled public String status;
        @AuraEnabled public Date due; @AuraEnabled public Date opened; @AuraEnabled public Date completedOn;
        @AuraEnabled public String remark; @AuraEnabled public String completedBy; @AuraEnabled public String assignedBy;
        @AuraEnabled public Id assigneeId; @AuraEnabled public String assignee;
        @AuraEnabled public Boolean mine = false; @AuraEnabled public Boolean canAct = false;
        @AuraEnabled public Boolean needsVerification = false; @AuraEnabled public String verifier;
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public String ncTitle; @AuraEnabled public String problem;
        @AuraEnabled public Id partId; @AuraEnabled public String partNumber; @AuraEnabled public String lot; @AuraEnabled public String ncOwner;
        @AuraEnabled public String ncStage; @AuraEnabled public String conclusion;
        @AuraEnabled public List<String> rootCauses = new List<String>();
        @AuraEnabled public List<Procedure> procedures = new List<Procedure>();
        @AuraEnabled public Boolean viewerOk = true;   // CQ's print and download control lets the file open in the page
        @AuraEnabled public Integer othersOpen = 0;    // other open actions on the same NC
    }
    public class Result {
        @AuraEnabled public String status; @AuraEnabled public Boolean signed = false;
        @AuraEnabled public String ncStage; @AuraEnabled public Integer othersOpen = 0;
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        compliancequest__SQX_Action__c a = action(recordId);
        View v = new View();
        v.actionId = a.Id; v.name = a.Name; v.title = a.compliancequest__Title__c; v.description = a.compliancequest__Description__c;
        v.type = a.compliancequest__Plan_Type__c; v.status = a.compliancequest__Status__c;
        v.due = a.compliancequest__Due_Date__c; v.opened = a.compliancequest__Date_Opened__c; v.completedOn = a.compliancequest__Completion_Date__c;
        v.remark = a.compliancequest__Remark__c; v.completedBy = a.compliancequest__Completed_By__c; v.assignedBy = a.CreatedBy.Name;
        v.assigneeId = a.compliancequest__SQX_User__c; v.assignee = a.compliancequest__SQX_User__r == null ? null : a.compliancequest__SQX_User__r.Name;
        v.mine = a.compliancequest__SQX_User__c == UserInfo.getUserId();
        v.canAct = v.mine && a.compliancequest__Status__c == 'Open';
        v.needsVerification = a.compliancequest__Verification_Required__c == 'Yes';
        v.verifier = a.compliancequest__SQX_Verification_User__r == null ? null : a.compliancequest__SQX_Verification_User__r.Name;

        Id ncId = a.compliancequest__SQX_Nonconformance__c;
        compliancequest__SQX_Nonconformance__c nc;
        if (ncId != null) {
            nc = [SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Part__c,
                         compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__Lot_Number__c, Owner.Name,
                         toLabel(compliancequest__Record_Stage__c), compliancequest__SQX_Investigation__c,
                         compliancequest__SQX_Investigation__r.compliancequest__Conclusion__c, compliancequest__SQX_Controlled_Document__c
                  FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId WITH USER_MODE];
            v.ncId = nc.Id; v.ncName = nc.Name; v.ncTitle = nc.compliancequest__NC_Title__c; v.problem = nc.compliancequest__Description__c;
            v.partId = nc.compliancequest__SQX_Part__c;
            v.partNumber = nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            v.lot = nc.compliancequest__Lot_Number__c; v.ncOwner = nc.Owner.Name; v.ncStage = nc.compliancequest__Record_Stage__c;
            v.conclusion = nc.compliancequest__SQX_Investigation__r == null ? null : nc.compliancequest__SQX_Investigation__r.compliancequest__Conclusion__c;
            if (nc.compliancequest__SQX_Investigation__c != null) {
                for (compliancequest__SQX_Root_Cause__c r : [
                        SELECT compliancequest__SQX_Root_Cause_Code__r.Name, toLabel(compliancequest__Category__c), compliancequest__Description__c
                        FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :nc.compliancequest__SQX_Investigation__c
                        WITH USER_MODE ORDER BY CreatedDate LIMIT 3]) {
                    String head = r.compliancequest__SQX_Root_Cause_Code__r != null ? r.compliancequest__SQX_Root_Cause_Code__r.Name : r.compliancequest__Category__c;
                    List<String> bits = new List<String>();
                    if (String.isNotBlank(head)) { bits.add(head); }
                    if (String.isNotBlank(r.compliancequest__Description__c)) { bits.add(r.compliancequest__Description__c.stripHtmlTags()); }
                    if (!bits.isEmpty()) { v.rootCauses.add(String.join(bits, ': ').left(300)); }
                }
            }
            v.othersOpen = [SELECT COUNT() FROM compliancequest__SQX_Action__c WHERE compliancequest__SQX_Nonconformance__c = :ncId
                            AND compliancequest__Status__c = 'Open' AND Id != :a.Id WITH USER_MODE];
        }
        v.procedures = procedures(nc == null ? null : nc.compliancequest__SQX_Controlled_Document__c,
            (a.compliancequest__Title__c == null ? '' : a.compliancequest__Title__c) + ' ' + (a.compliancequest__Description__c == null ? '' : a.compliancequest__Description__c));
        v.viewerOk = viewerOk();
        return v;
    }

    /** The assignee completes their correction: what was done becomes CQ's sign-off comment. */
    @AuraEnabled
    public static Result complete(Id recordId, String whatWasDone, String completedOn, String comment, String password) {
        compliancequest__SQX_Action__c a = refuseUnlessMine(recordId);
        if (String.isBlank(whatWasDone)) { throw new AuraHandledException('Say what was done.'); }
        Date d;
        try { d = String.isBlank(completedOn) ? Date.today() : Date.valueOf(completedOn); }
        catch (Exception e) { throw new AuraHandledException('Enter the date it was completed.'); }
        if (d > Date.today()) { throw new AuraHandledException('The completion date cannot be in the future.'); }
        return act(a, COMPLETE, 'completing ' + a.Name + ', ' + a.compliancequest__Title__c, comment, password,
            new compliancequest__SQX_Action__c(Id = a.Id, compliancequest__Activity_Code__c = COMPLETE,
                compliancequest__Remark__c = whatWasDone.trim().left(32768), compliancequest__Completion_Date__c = d),
            'The correction was not completed: ');
    }

    /** The assignee skips their correction when it is no longer needed, with the reason. */
    @AuraEnabled
    public static Result skip(Id recordId, String reason, String comment, String password) {
        compliancequest__SQX_Action__c a = refuseUnlessMine(recordId);
        if (String.isBlank(reason)) { throw new AuraHandledException('Say why it is no longer needed.'); }
        return act(a, SKIP, 'skipping ' + a.Name + ', ' + a.compliancequest__Title__c, comment, password,
            new compliancequest__SQX_Action__c(Id = a.Id, compliancequest__Activity_Code__c = SKIP,
                compliancequest__Activity_Comment__c = reason.trim().left(32768)),
            'The correction was not skipped: ');
    }

    static Result act(compliancequest__SQX_Action__c a, String code, String what, String comment, String password,
                      compliancequest__SQX_Action__c change, String failed) {
        Result res = new Result();
        Savepoint sp = Database.setSavepoint();
        // the assignee signs for this action before anything is saved (the password goes straight to CQ)
        CqActionSignable.signing = what.left(1000);
        try {
            res.signed = CqEsign.sign(a.Id, code, comment, password, true);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        }
        try {
            update as user change;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(failed + e.getDmlMessage(0));
        } catch (SecurityException e) {
            Database.rollback(sp);
            throw new AuraHandledException(failed + CqSave.DENIED);
        }
        compliancequest__SQX_Action__c after = action(a.Id);
        res.status = after.compliancequest__Status__c;
        if (after.compliancequest__SQX_Nonconformance__c != null) {
            Id ncId = after.compliancequest__SQX_Nonconformance__c;
            res.ncStage = [SELECT toLabel(compliancequest__Record_Stage__c) FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId WITH USER_MODE].compliancequest__Record_Stage__c;
            res.othersOpen = [SELECT COUNT() FROM compliancequest__SQX_Action__c WHERE compliancequest__SQX_Nonconformance__c = :ncId
                              AND compliancequest__Status__c = 'Open' WITH USER_MODE];
        }
        return res;
    }

    static compliancequest__SQX_Action__c refuseUnlessMine(Id recordId) {
        compliancequest__SQX_Action__c a = action(recordId);
        if (a.compliancequest__SQX_User__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only ' + (a.compliancequest__SQX_User__r == null ? 'the assignee' : a.compliancequest__SQX_User__r.Name) + ' can complete this correction.');
        }
        if (a.compliancequest__Status__c != 'Open') { throw new AuraHandledException('This correction is ' + a.compliancequest__Status__c + ', so it can no longer be changed here.'); }
        return a;
    }

    static compliancequest__SQX_Action__c action(Id recordId) {
        if (recordId == null || recordId.getSObjectType() != compliancequest__SQX_Action__c.SObjectType) { throw new AuraHandledException('This page works on a CQ action.'); }
        return [SELECT Id, Name, compliancequest__Title__c, compliancequest__Description__c, compliancequest__Plan_Type__c, compliancequest__Status__c,
                       compliancequest__Due_Date__c, compliancequest__Date_Opened__c, compliancequest__Completion_Date__c, compliancequest__Remark__c,
                       compliancequest__Completed_By__c, CreatedBy.Name, compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name,
                       compliancequest__Verification_Required__c, compliancequest__SQX_Verification_User__r.Name, compliancequest__SQX_Nonconformance__c
                FROM compliancequest__SQX_Action__c WHERE Id = :recordId WITH USER_MODE];
    }

    /** Document numbers named in text, for example SOP-PTCA-060. */
    @TestVisible
    static List<String> docNumbers(String text) {
        List<String> out = new List<String>();
        if (String.isBlank(text)) { return out; }
        Matcher m = DOC_NO.matcher(text);
        while (m.find() && out.size() < 5) { if (!out.contains(m.group())) { out.add(m.group()); } }
        return out;
    }

    /** The current revision of each procedure: the one linked on the NC first, then those named in the correction. */
    static List<Procedure> procedures(Id linkedDoc, String text) {
        Map<String, String> source = new Map<String, String>();
        if (linkedDoc != null) {
            for (compliancequest__SQX_Controlled_Document__c d : [SELECT compliancequest__Document_Number__c FROM compliancequest__SQX_Controlled_Document__c WHERE Id = :linkedDoc WITH USER_MODE]) {
                if (d.compliancequest__Document_Number__c != null) { source.put(d.compliancequest__Document_Number__c, 'Linked on the NC'); }
            }
        }
        for (String n : docNumbers(text)) { if (!source.containsKey(n)) { source.put(n, 'Named in the correction'); } }
        List<Procedure> out = new List<Procedure>();
        if (source.isEmpty()) { return out; }
        List<compliancequest__SQX_Controlled_Document__c> docs = [
            SELECT Id, compliancequest__Document_Number__c, compliancequest__Title__c, compliancequest__Revision__c, compliancequest__Effective_Date__c,
                   compliancequest__Content_Reference__c, compliancequest__Secondary_Content_Reference__c
            FROM compliancequest__SQX_Controlled_Document__c
            WHERE compliancequest__Document_Number__c IN :source.keySet() AND compliancequest__Document_Status__c = 'Current' WITH USER_MODE LIMIT 5];
        Set<Id> files = new Set<Id>();
        for (compliancequest__SQX_Controlled_Document__c d : docs) {
            Id f = contentOf(d);
            if (f != null) { files.add(f); }
        }
        Map<Id, ContentDocument> cd = new Map<Id, ContentDocument>();
        if (!files.isEmpty()) {
            cd = new Map<Id, ContentDocument>([SELECT Id, LatestPublishedVersionId, FileType FROM ContentDocument WHERE Id IN :files]);
        }
        for (String n : source.keySet()) {
            for (compliancequest__SQX_Controlled_Document__c d : docs) {
                if (d.compliancequest__Document_Number__c != n) { continue; }
                Procedure p = new Procedure();
                p.id = d.Id; p.docNumber = n; p.title = d.compliancequest__Title__c; p.revision = d.compliancequest__Revision__c;
                p.effective = d.compliancequest__Effective_Date__c; p.source = source.get(n);
                ContentDocument c = cd.get(contentOf(d));
                if (c != null) { p.contentDocumentId = c.Id; p.versionId = c.LatestPublishedVersionId; p.fileType = c.FileType; }
                out.add(p);
            }
        }
        return out;
    }

    /** The PDF (secondary content) when there is one, otherwise the primary file. */
    static Id contentOf(compliancequest__SQX_Controlled_Document__c d) {
        String s = String.isNotBlank(d.compliancequest__Secondary_Content_Reference__c) ? d.compliancequest__Secondary_Content_Reference__c : d.compliancequest__Content_Reference__c;
        if (String.isBlank(s)) { return null; }
        try { return Id.valueOf(s); } catch (Exception e) { return null; }
    }

    /** CQ's default print and download control: the file opens in the page only when it allows both, since the viewer can download. */
    static Boolean viewerOk() {
        for (compliancequest__CQ_Print_and_Download_Control_Settings__mdt s : [
                SELECT compliancequest__Restrict_Download__c, compliancequest__Restrict_Print__c
                FROM compliancequest__CQ_Print_and_Download_Control_Settings__mdt WHERE compliancequest__Default__c = true AND compliancequest__Active__c = true LIMIT 1]) {
            return s.compliancequest__Restrict_Download__c != true && s.compliancequest__Restrict_Print__c != true;
        }
        return true;
    }
}
