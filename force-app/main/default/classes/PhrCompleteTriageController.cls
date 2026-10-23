/**
 * Backs the custom Complete Triage popup (triageStepsWithSummary LWC) that replaces CQ's triage button in eNBA.
 *
 * load()           - the complaint, its draft workflow steps that come from CQ Tasks flagged Transfer To Workflow,
 *                    and the CQ Tasks that can be added.
 * saveSteps()      - updates assignees and the Applicable flag on existing draft steps and creates new draft steps.
 * generateDraft()  - writes a new draft investigation summary with the agent's generator, without saving it,
 *                    formatted the way the save will store it, for screen 1 of the popup.
 * saveDraft()      - saves the (possibly edited) draft once, through the same save the agent uses
 *                    (formatting, report link, copy to linked investigations).
 * completeTriage() - moves the complaint forward the CQ way: it saves the complaint with Activity Code
 *                    'initiate' (or 'takeownershipandinitiate' while a queue owns it) and CQ performs the move
 *                    (stage, status, steps to Open, triage task closed). Nothing here writes the stage directly.
 *
 * Each method is its own transaction because CQ allows only one activity per transaction.
 * DML runs in USER_MODE so the running user's access is enforced.
 */
public with sharing class PhrCompleteTriageController {

    static final String DRAFT = 'Draft';
    static final String CODE_INITIATE = 'initiate';
    static final String CODE_TAKE_AND_INITIATE = 'takeownershipandinitiate';

    public class StepRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id templateId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal step;
        @AuraEnabled public Id assigneeId;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public Decimal allowedDays;
        @AuraEnabled public Boolean include;
    }

    public class TemplateOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal step;
        @AuraEnabled public Decimal allowedDays;
        @AuraEnabled public Id defaultAssigneeId;
        @AuraEnabled public String defaultAssigneeName;
    }

    public class TriageData {
        @AuraEnabled public Id complaintId;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String stage;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean ownerIsQueue;
        @AuraEnabled public Boolean hasDraft;
        @AuraEnabled public String draftHtml;
        @AuraEnabled public List<StepRow> steps = new List<StepRow>();
        @AuraEnabled public List<TemplateOption> templates = new List<TemplateOption>();
    }

    public class Outcome {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String stage;
    }

    @AuraEnabled
    public static TriageData load(String recordId) {
        Id complaintId = TriageDraftSummaryController.resolveComplaintId(recordId);
        if (complaintId == null) { throw new AuraHandledException('The complaint for this task could not be found.'); }

        TriageData d = new TriageData();
        compliancequest__SQX_Complaint__c c = [
            SELECT Id, Name, OwnerId, Owner.Name, compliancequest__Record_Stage__c, Draft_Investigation_Summaries__c
            FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId WITH USER_MODE LIMIT 1
        ];
        d.complaintId = c.Id;
        d.complaintName = c.Name;
        d.stage = c.compliancequest__Record_Stage__c;
        d.ownerName = c.Owner.Name;
        d.ownerIsQueue = isQueue(c.OwnerId);
        d.hasDraft = !String.isBlank(c.Draft_Investigation_Summaries__c);
        d.draftHtml = c.Draft_Investigation_Summaries__c;

        for (compliancequest__SQX_Complaint_Task__c s : [
            SELECT Id, Name, compliancequest__Step__c, compliancequest__SQX_Task__c, compliancequest__SQX_User__c,
                   compliancequest__SQX_User__r.Name, compliancequest__User_Queue_Name__c,
                   compliancequest__Allowed_Days__c, compliancequest__Applicable__c
            FROM compliancequest__SQX_Complaint_Task__c
            WHERE compliancequest__SQX_Complaint__c = :complaintId
              AND compliancequest__Status__c = :DRAFT
              AND compliancequest__SQX_Task__r.compliancequest__Transfer_To_Workflow__c = true
            WITH USER_MODE
            ORDER BY compliancequest__Step__c, Name
        ]) {
            StepRow r = new StepRow();
            r.id = s.Id;
            r.templateId = s.compliancequest__SQX_Task__c;
            r.name = s.Name;
            r.step = s.compliancequest__Step__c;
            r.assigneeId = s.compliancequest__SQX_User__c;
            r.assigneeName = s.compliancequest__SQX_User__c != null
                ? s.compliancequest__SQX_User__r.Name : s.compliancequest__User_Queue_Name__c;
            r.allowedDays = s.compliancequest__Allowed_Days__c;
            r.include = s.compliancequest__Applicable__c != false;
            d.steps.add(r);
        }

        for (compliancequest__SQX_Task__c t : templates(null)) {
            TemplateOption o = new TemplateOption();
            o.id = t.Id;
            o.name = t.Name;
            o.step = t.compliancequest__Step__c;
            o.allowedDays = t.compliancequest__Allowed_Days__c;
            o.defaultAssigneeId = t.compliancequest__SQX_User__c;
            o.defaultAssigneeName = t.compliancequest__SQX_User__r.Name;
            d.templates.add(o);
        }
        return d;
    }

    public class DraftOutcome {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String html;
        @AuraEnabled public String message;
    }

    /** Generates a new draft without saving it. The text is formatted the way the save stores it. */
    @AuraEnabled
    public static DraftOutcome generateDraft(String recordId) {
        DraftOutcome o = new DraftOutcome();
        Id complaintId = TriageDraftSummaryController.resolveComplaintId(recordId);
        if (complaintId == null) {
            o.success = false;
            o.message = 'The complaint for this task could not be found.';
            return o;
        }
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.saveToRecord = false;
        GenerateDraftInvestigationSummary.Result r =
            GenerateDraftInvestigationSummary.generate(new List<GenerateDraftInvestigationSummary.Request>{ req })[0];
        if (String.isBlank(r.summary)) {
            o.success = false;
            o.message = String.isBlank(r.message) ? 'No draft was generated.' : r.message;
            return o;
        }
        o.success = true;
        o.html = format(r.summary);
        o.message = r.message;
        return o;
    }

    /** Saves the draft once, through the agent's save (formatting, report link, copy to linked investigations). */
    @AuraEnabled
    public static Outcome saveDraft(String recordId, String html) {
        Outcome o = new Outcome();
        Id complaintId = TriageDraftSummaryController.resolveComplaintId(recordId);
        if (complaintId == null || String.isBlank(html)) {
            o.success = false;
            o.message = complaintId == null ? 'The complaint for this task could not be found.' : 'There is no draft to save.';
            return o;
        }
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.summary = html;
        SaveDraftInvestigationSummary.Result r =
            SaveDraftInvestigationSummary.save(new List<SaveDraftInvestigationSummary.Request>{ req })[0];
        o.success = r.success;
        o.message = r.message;
        return o;
    }

    /** Same formatting steps as SaveDraftInvestigationSummary, so screen 1 shows what will be saved. */
    @TestVisible
    static String format(String text) {
        return SummaryRichText.boldRecordIds(SummaryRichText.boldHeadings(
            SummaryRichText.fromAgent(SummaryHtmlRepair.repair(text))));
    }

    /** stepsJson is the list of StepRow from the popup. Rows without an id are new steps. */
    @AuraEnabled
    public static Outcome saveSteps(String recordId, String stepsJson) {
        Id complaintId = TriageDraftSummaryController.resolveComplaintId(recordId);
        if (complaintId == null) { throw new AuraHandledException('The complaint for this task could not be found.'); }
        List<StepRow> rows = String.isBlank(stepsJson)
            ? new List<StepRow>() : (List<StepRow>) JSON.deserialize(stepsJson, List<StepRow>.class);

        Set<Id> templateIds = new Set<Id>();
        for (StepRow r : rows) { if (r.id == null && r.templateId != null && r.include == true) { templateIds.add(r.templateId); } }
        Map<Id, compliancequest__SQX_Task__c> tmpl = new Map<Id, compliancequest__SQX_Task__c>(templates(templateIds));

        List<compliancequest__SQX_Complaint_Task__c> updates = new List<compliancequest__SQX_Complaint_Task__c>();
        List<compliancequest__SQX_Complaint_Task__c> inserts = new List<compliancequest__SQX_Complaint_Task__c>();
        for (StepRow r : rows) {
            if (r.id != null) {
                compliancequest__SQX_Complaint_Task__c s = new compliancequest__SQX_Complaint_Task__c(
                    Id = r.id, compliancequest__Applicable__c = r.include == true);
                if (r.assigneeId != null) {
                    s.compliancequest__SQX_User__c = r.assigneeId;
                    s.compliancequest__User_Queue__c = String.valueOf(r.assigneeId);
                }
                updates.add(s);
            } else if (r.include == true && tmpl.containsKey(r.templateId)) {
                inserts.add(newStep(complaintId, tmpl.get(r.templateId), r.assigneeId));
            }
        }

        Outcome o = new Outcome();
        try {
            if (!updates.isEmpty()) { Database.update(updates, true, AccessLevel.USER_MODE); }
            if (!inserts.isEmpty()) { Database.insert(inserts, true, AccessLevel.USER_MODE); }
            o.success = true;
            o.message = 'Steps saved: ' + updates.size() + ' updated, ' + inserts.size() + ' added.';
        } catch (Exception e) {
            o.success = false;
            o.message = 'The steps could not be saved: ' + e.getMessage();
        }
        return o;
    }

    /** Moves the complaint out of triage through CQ's own Initiate activity. */
    @AuraEnabled
    public static Outcome completeTriage(String recordId, String comment) {
        Id complaintId = TriageDraftSummaryController.resolveComplaintId(recordId);
        if (complaintId == null) { throw new AuraHandledException('The complaint for this task could not be found.'); }
        compliancequest__SQX_Complaint__c c = [
            SELECT Id, OwnerId FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId WITH USER_MODE LIMIT 1
        ];
        Outcome o = new Outcome();
        try {
            Database.update(new compliancequest__SQX_Complaint__c(
                Id = complaintId,
                compliancequest__Activity_Code__c = activityCodeFor(c.OwnerId),
                compliancequest__Activity_Comment__c = String.isBlank(comment) ? null : comment
            ), true, AccessLevel.USER_MODE);
            o.success = true;
        } catch (Exception e) {
            o.success = false;
            o.message = 'Triage could not be completed: ' + e.getMessage();
            return o;
        }
        o.stage = [SELECT compliancequest__Record_Stage__c FROM compliancequest__SQX_Complaint__c
                   WHERE Id = :complaintId WITH USER_MODE LIMIT 1].compliancequest__Record_Stage__c;
        o.message = 'Triage completed. The complaint stage is now ' + o.stage + '.';
        return o;
    }

    @TestVisible
    static String activityCodeFor(Id ownerId) {
        return isQueue(ownerId) ? CODE_TAKE_AND_INITIATE : CODE_INITIATE;
    }

    static Boolean isQueue(Id ownerId) {
        return ownerId != null && ownerId.getSobjectType() == Group.SObjectType;
    }

    static List<compliancequest__SQX_Task__c> templates(Set<Id> onlyIds) {
        String q = 'SELECT Id, Name, compliancequest__Step__c, compliancequest__Allowed_Days__c, compliancequest__SQX_User__c, '
            + 'compliancequest__SQX_User__r.Name, compliancequest__SQX_Job_Function__c, compliancequest__Description__c, '
            + 'compliancequest__Step_Record_Type__c, compliancequest__Review_Required__c '
            + 'FROM compliancequest__SQX_Task__c '
            + 'WHERE compliancequest__Record_Type__c = \'Complaint\' AND compliancequest__Active__c = true '
            + 'AND compliancequest__Transfer_To_Workflow__c = true'
            + (onlyIds == null ? '' : ' AND Id IN :onlyIds')
            + ' ORDER BY compliancequest__Step__c, Name';
        return Database.queryWithBinds(q, new Map<String, Object>{ 'onlyIds' => onlyIds }, AccessLevel.USER_MODE);
    }

    @TestVisible
    static compliancequest__SQX_Complaint_Task__c newStep(Id complaintId, compliancequest__SQX_Task__c t, Id assigneeId) {
        Id userId = assigneeId != null ? assigneeId : t.compliancequest__SQX_User__c;
        compliancequest__SQX_Complaint_Task__c s = new compliancequest__SQX_Complaint_Task__c(
            compliancequest__SQX_Complaint__c = complaintId,
            compliancequest__SQX_Task__c = t.Id,
            Name = t.Name.left(80),
            compliancequest__Step__c = t.compliancequest__Step__c,
            compliancequest__Allowed_Days__c = t.compliancequest__Allowed_Days__c,
            compliancequest__Review_Required__c = t.compliancequest__Review_Required__c,
            compliancequest__Task_Description__c = t.compliancequest__Description__c,
            compliancequest__Status__c = DRAFT,
            compliancequest__Applicable__c = true
        );
        if (userId != null) {
            s.compliancequest__SQX_User__c = userId;
            s.compliancequest__User_Queue__c = String.valueOf(userId);
        } else if (t.compliancequest__SQX_Job_Function__c != null) {
            s.compliancequest__SQX_Job_Function__c = t.compliancequest__SQX_Job_Function__c;
        }
        Id rt = recordTypeId(t.compliancequest__Step_Record_Type__c);
        if (rt != null) { s.RecordTypeId = rt; }
        return s;
    }

    static Id recordTypeId(String developerName) {
        if (String.isBlank(developerName)) { return null; }
        Schema.RecordTypeInfo info = compliancequest__SQX_Complaint_Task__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }
}
