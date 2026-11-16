/**
 * CqInvestigationWorkspace: the CQ.AI Investigation workspace on an NC's Investigation (or on the NC itself).
 *
 * getView() gives what the steps show: the investigation, its NC (problem, triage, disposition), root causes,
 * action plans and analysis tools, and whether it is complete or waiting for approval.
 *
 * saveActions() saves the Actions step as CQ action plans on the investigation.
 *
 * completeInvestigation() follows CQ's own path for an NC investigation:
 *   1. a Draft investigation is opened first (Activity Code 'initiate', as CQ's Perform Investigation does);
 *   2. the conclusion and summary are saved, and any open analysis tool is completed (Activity Code 'complete');
 *   3. a Response of type Investigation is made, with the investigation included for Publish, and submitted.
 * With no investigation approval, CQ then completes the response and the investigation in the background
 * (a few seconds later), moves the NC to Implement and turns the action plans into actions. With approval,
 * CQ starts its approval on the response instead.
 */
public with sharing class CqInvestigationWorkspace {
    public static final String INITIATE = 'initiate';
    public static final String COMPLETE = 'complete';
    public static final String SUBMIT = 'submitforapproval';

    public class Cause {
        @AuraEnabled public Id id; @AuraEnabled public String category; @AuraEnabled public String code;
        @AuraEnabled public String description; @AuraEnabled public Boolean verified = false;
    }
    public class Plan {
        @AuraEnabled public Id id; @AuraEnabled public String title; @AuraEnabled public String type;
        @AuraEnabled public String description; @AuraEnabled public Date due;
        @AuraEnabled public Id userId; @AuraEnabled public String userName;
    }
    public class Tool {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String type; @AuraEnabled public String status;
    }
    public class View {
        @AuraEnabled public Id investigationId; @AuraEnabled public String investigationName;
        @AuraEnabled public String status; @AuraEnabled public String stage;
        @AuraEnabled public String conclusion; @AuraEnabled public String summary;
        @AuraEnabled public String completedBy; @AuraEnabled public Date completedOn;
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public String title; @AuraEnabled public String description;
        @AuraEnabled public Id partId; @AuraEnabled public String partNumber; @AuraEnabled public String lot;
        @AuraEnabled public String ncStage; @AuraEnabled public String owner; @AuraEnabled public String risk; @AuraEnabled public String path;
        @AuraEnabled public Decimal defective; @AuraEnabled public Date due;
        @AuraEnabled public Boolean needsApproval = false;
        @AuraEnabled public Boolean dispositionRequired = false; @AuraEnabled public Boolean dispositionComplete = false;
        @AuraEnabled public String dispositionText;
        @AuraEnabled public Boolean isComplete = false; @AuraEnabled public Boolean inApproval = false; @AuraEnabled public Boolean submitted = false;
        @AuraEnabled public String responseName;
        @AuraEnabled public List<String> conclusions = new List<String>();
        @AuraEnabled public List<String> planTypes = new List<String>();
        @AuraEnabled public List<Cause> causes = new List<Cause>();
        @AuraEnabled public List<Plan> plans = new List<Plan>();
        @AuraEnabled public List<Tool> tools = new List<Tool>();
        @AuraEnabled public Integer openActions = 0;
    }
    public class Result {
        @AuraEnabled public String responseName; @AuraEnabled public Boolean needsApproval = false;
        @AuraEnabled public List<String> toolsCompleted = new List<String>();
    }

    /** The workspace can sit on the Investigation or on the NC; either way it works on the NC's investigation. */
    public static Id investigationFor(Id recordId) {
        if (recordId == null) { throw new AuraHandledException('No record.'); }
        if (recordId.getSObjectType() == compliancequest__SQX_Nonconformance__c.SObjectType) {
            compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
            if (nc.compliancequest__SQX_Investigation__c == null) { throw new AuraHandledException('This nonconformance has no investigation yet.'); }
            return nc.compliancequest__SQX_Investigation__c;
        }
        return recordId;
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        Id invId = investigationFor(recordId);
        compliancequest__SQX_Investigation__c inv = [
            SELECT Id, Name, compliancequest__Status__c, toLabel(compliancequest__Record_Stage__c), compliancequest__Conclusion__c,
                   compliancequest__Investigation_Summary__c, compliancequest__Completed_By__c, compliancequest__Completed_On__c,
                   compliancequest__SQX_Nonconformance__c
            FROM compliancequest__SQX_Investigation__c WHERE Id = :invId];
        View v = new View();
        v.investigationId = inv.Id; v.investigationName = inv.Name;
        v.status = inv.compliancequest__Status__c; v.stage = inv.compliancequest__Record_Stage__c;
        v.conclusion = inv.compliancequest__Conclusion__c; v.summary = CqInvestigationSummary.toPlain(inv.compliancequest__Investigation_Summary__c);
        v.completedBy = inv.compliancequest__Completed_By__c; v.completedOn = inv.compliancequest__Completed_On__c;
        v.isComplete = inv.compliancequest__Status__c == 'Completed';
        v.inApproval = inv.compliancequest__Status__c == 'In Approval';
        for (Schema.PicklistEntry p : compliancequest__SQX_Investigation__c.compliancequest__Conclusion__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) { v.conclusions.add(p.getValue()); }
        }
        for (Schema.PicklistEntry p : compliancequest__SQX_Action_Plan__c.compliancequest__Plan_Type__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) { v.planTypes.add(p.getValue()); }
        }

        Id ncId = inv.compliancequest__SQX_Nonconformance__c;
        if (ncId != null) {
            compliancequest__SQX_Nonconformance__c nc = [
                SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Part__c,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__Lot_Number__c,
                       toLabel(compliancequest__Record_Stage__c), Owner.Name, Triage_Risk__c, Triage_Path__c, compliancequest__Defective_Quantity__c,
                       compliancequest__Due_Date_Investigation__c, compliancequest__Investigation_Approval__c,
                       compliancequest__Disposition_Required__c, compliancequest__Is_Disposition_Complete__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
            v.ncId = nc.Id; v.ncName = nc.Name; v.title = nc.compliancequest__NC_Title__c; v.description = nc.compliancequest__Description__c;
            v.partId = nc.compliancequest__SQX_Part__c; v.lot = nc.compliancequest__Lot_Number__c;
            v.partNumber = nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            v.ncStage = nc.compliancequest__Record_Stage__c; v.owner = nc.Owner.Name; v.risk = nc.Triage_Risk__c; v.path = nc.Triage_Path__c;
            v.defective = nc.compliancequest__Defective_Quantity__c; v.due = nc.compliancequest__Due_Date_Investigation__c;
            v.needsApproval = nc.compliancequest__Investigation_Approval__c == true;
            v.dispositionComplete = nc.compliancequest__Is_Disposition_Complete__c == true;

            // what was done with the units, from the completed dispositions: "Scrap 4 · Rework 1"
            Map<String, Decimal> byType = new Map<String, Decimal>();
            Integer dispositions = 0;
            for (compliancequest__SQX_Disposition__c d : [
                    SELECT compliancequest__Disposition_Type__c, compliancequest__Actual_Quantity_Disposed__c, compliancequest__Disposition_Quantity__c, compliancequest__Status__c
                    FROM compliancequest__SQX_Disposition__c WHERE compliancequest__SQX_Nonconformance__c = :ncId ORDER BY CreatedDate]) {
                dispositions++;
                if (d.compliancequest__Status__c != 'Complete') { continue; }
                if (d.compliancequest__Disposition_Type__c == null) { continue; }
                Decimal q = d.compliancequest__Actual_Quantity_Disposed__c != null ? d.compliancequest__Actual_Quantity_Disposed__c : d.compliancequest__Disposition_Quantity__c;
                Decimal had = byType.containsKey(d.compliancequest__Disposition_Type__c) ? byType.get(d.compliancequest__Disposition_Type__c) : 0;
                byType.put(d.compliancequest__Disposition_Type__c, had + (q == null ? 0 : q));
            }
            v.dispositionRequired = nc.compliancequest__Disposition_Required__c == true || dispositions > 0;
            List<String> parts = new List<String>();
            for (String t : byType.keySet()) { parts.add(t + ' ' + byType.get(t).stripTrailingZeros().toPlainString()); }
            v.dispositionText = parts.isEmpty() ? null : String.join(parts, ' · ');

            // an investigation response that CQ has not finished yet: submitted and waiting (approval or CQ's background step)
            for (compliancequest__SQX_Response_Inclusion__c x : [
                    SELECT compliancequest__SQX_Response__r.Name, compliancequest__SQX_Response__r.compliancequest__Status__c
                    FROM compliancequest__SQX_Response_Inclusion__c
                    WHERE compliancequest__SQX_Investigation__c = :invId AND compliancequest__Type__c = 'Investigation'
                    ORDER BY CreatedDate DESC LIMIT 1]) {
                v.responseName = x.compliancequest__SQX_Response__r.Name;
                String rs = x.compliancequest__SQX_Response__r.compliancequest__Status__c;
                if (rs == 'In Approval') { v.inApproval = true; }
                v.submitted = rs == 'In Approval' || rs == 'Completed';
            }
            v.openActions = [SELECT COUNT() FROM compliancequest__SQX_Action__c WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Status__c = 'Open'];
        }

        for (compliancequest__SQX_Root_Cause__c r : [
                SELECT Id, toLabel(compliancequest__Category__c), compliancequest__SQX_Root_Cause_Code__r.Name, compliancequest__Description__c, compliancequest__Verified__c
                FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate]) {
            Cause c = new Cause();
            c.id = r.Id; c.category = r.compliancequest__Category__c; c.description = r.compliancequest__Description__c;
            c.code = r.compliancequest__SQX_Root_Cause_Code__r == null ? null : r.compliancequest__SQX_Root_Cause_Code__r.Name;
            c.verified = r.compliancequest__Verified__c == true;
            v.causes.add(c);
        }
        for (compliancequest__SQX_Action_Plan__c a : [
                SELECT Id, compliancequest__Title__c, compliancequest__Plan_Type__c, compliancequest__Description__c, compliancequest__Due_Date__c,
                       compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name
                FROM compliancequest__SQX_Action_Plan__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate]) {
            v.plans.add(plan(a));
        }
        for (compliancequest__SQX_Investigation_Tool__c t : [
                SELECT Id, Name, RecordType.Name, compliancequest__Status__c
                FROM compliancequest__SQX_Investigation_Tool__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate]) {
            Tool x = new Tool();
            x.id = t.Id; x.name = t.Name; x.type = t.RecordType == null ? null : t.RecordType.Name; x.status = t.compliancequest__Status__c;
            v.tools.add(x);
        }
        return v;
    }

    static Plan plan(compliancequest__SQX_Action_Plan__c a) {
        Plan p = new Plan();
        p.id = a.Id; p.title = a.compliancequest__Title__c; p.type = a.compliancequest__Plan_Type__c; p.description = a.compliancequest__Description__c;
        p.due = a.compliancequest__Due_Date__c; p.userId = a.compliancequest__SQX_User__c;
        p.userName = a.compliancequest__SQX_User__r == null ? null : a.compliancequest__SQX_User__r.Name;
        return p;
    }

    /** Saves the Actions step: each row becomes (or updates) a CQ action plan; plans removed from the list are deleted. */
    @AuraEnabled
    public static List<Plan> saveActions(Id recordId, String payload) {
        Id invId = investigationFor(recordId);
        refuseIfDone(invId);
        List<Object> raw = String.isBlank(payload) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(payload);
        Set<String> types = new Set<String>();
        for (Schema.PicklistEntry p : compliancequest__SQX_Action_Plan__c.compliancequest__Plan_Type__c.getDescribe().getPicklistValues()) { types.add(p.getValue()); }
        List<compliancequest__SQX_Action_Plan__c> keep = new List<compliancequest__SQX_Action_Plan__c>();
        Integer n = 0;
        for (Object o : raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            n++;
            String title = str(m.get('title'));
            String type = str(m.get('type'));
            String due = str(m.get('due'));
            String label = 'Action ' + n + ': ';
            if (String.isBlank(title)) { throw new AuraHandledException(label + 'enter what is to be done.'); }
            if (!types.contains(type)) { throw new AuraHandledException(label + 'choose Correction, Corrective or Preventive.'); }
            if (String.isBlank(due)) { throw new AuraHandledException(label + 'enter a due date.'); }
            compliancequest__SQX_Action_Plan__c a = new compliancequest__SQX_Action_Plan__c(
                compliancequest__Title__c = title.left(255), compliancequest__Plan_Type__c = type,
                compliancequest__Description__c = String.isBlank(str(m.get('description'))) ? title : str(m.get('description')),
                compliancequest__Due_Date__c = Date.valueOf(due));
            String userId = str(m.get('userId'));
            a.compliancequest__SQX_User__c = String.isBlank(userId) ? UserInfo.getUserId() : (Id) userId;
            String id = str(m.get('id'));
            if (String.isBlank(id)) { a.compliancequest__SQX_Investigation__c = invId; } else { a.Id = (Id) id; }
            keep.add(a);
        }
        Set<Id> kept = new Set<Id>();
        for (compliancequest__SQX_Action_Plan__c a : keep) { if (a.Id != null) { kept.add(a.Id); } }
        List<compliancequest__SQX_Action_Plan__c> gone = [
            SELECT Id FROM compliancequest__SQX_Action_Plan__c WHERE compliancequest__SQX_Investigation__c = :invId AND Id NOT IN :kept];
        try {
            if (!gone.isEmpty()) { delete gone; }
            upsert keep;
        } catch (DmlException e) {
            throw new AuraHandledException('The actions were not saved: ' + e.getDmlMessage(0));
        }
        List<Plan> out = new List<Plan>();
        for (compliancequest__SQX_Action_Plan__c a : [
                SELECT Id, compliancequest__Title__c, compliancequest__Plan_Type__c, compliancequest__Description__c, compliancequest__Due_Date__c,
                       compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name
                FROM compliancequest__SQX_Action_Plan__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate]) {
            out.add(plan(a));
        }
        return out;
    }

    /**
     * Complete Investigation (or Submit for Approval when the NC needs investigation approval): saves the actions,
     * conclusion and summary, then submits the investigation through a CQ response as described at the top.
     */
    @AuraEnabled
    public static Result completeInvestigation(Id recordId, String conclusion, String summary, String actionsPayload) {
        Id invId = investigationFor(recordId);
        refuseIfDone(invId);
        if (String.isBlank(conclusion)) { throw new AuraHandledException('Choose a conclusion.'); }
        if (String.isBlank(summary)) { throw new AuraHandledException('Write the investigation summary.'); }
        compliancequest__SQX_Investigation__c inv = [
            SELECT Id, compliancequest__Status__c, compliancequest__SQX_Nonconformance__c,
                   compliancequest__SQX_Nonconformance__r.compliancequest__Investigation_Approval__c
            FROM compliancequest__SQX_Investigation__c WHERE Id = :invId];
        if (inv.compliancequest__SQX_Nonconformance__c == null) { throw new AuraHandledException('This investigation is not on a nonconformance.'); }

        Result res = new Result();
        res.needsApproval = inv.compliancequest__SQX_Nonconformance__r.compliancequest__Investigation_Approval__c == true;
        Savepoint sp = Database.setSavepoint();
        try {
            if (actionsPayload != null) { saveActions(invId, actionsPayload); }
            // 1. open a Draft investigation, as CQ's Perform Investigation does
            if (inv.compliancequest__Status__c == 'Draft') {
                update new compliancequest__SQX_Investigation__c(Id = invId, compliancequest__Activity_Code__c = INITIATE);
            }
            // 2. the conclusion and summary; then any open analysis tool, since CQ refuses to submit with one open
            update new compliancequest__SQX_Investigation__c(Id = invId, compliancequest__Conclusion__c = conclusion,
                compliancequest__Investigation_Summary__c = CqInvestigationSummary.toHtml(summary));
            for (compliancequest__SQX_Investigation_Tool__c t : [
                    SELECT Id, Name FROM compliancequest__SQX_Investigation_Tool__c
                    WHERE compliancequest__SQX_Investigation__c = :invId AND compliancequest__Status__c != 'Complete']) {
                update new compliancequest__SQX_Investigation_Tool__c(Id = t.Id, compliancequest__Activity_Code__c = COMPLETE);
                res.toolsCompleted.add(t.Name);
            }
            // 3. a response that publishes the investigation, submitted
            compliancequest__SQX_Finding_Response__c r = new compliancequest__SQX_Finding_Response__c(
                compliancequest__SQX_Nonconformance__c = inv.compliancequest__SQX_Nonconformance__c,
                compliancequest__Response_Type__c = 'Investigation', compliancequest__Response_Summary__c = summary.left(255));
            insert r;
            insert new compliancequest__SQX_Response_Inclusion__c(compliancequest__SQX_Response__c = r.Id, compliancequest__Type__c = 'Investigation',
                compliancequest__SQX_Investigation__c = invId, compliancequest__Inclusion_Reason__c = 'Publish');
            update new compliancequest__SQX_Finding_Response__c(Id = r.Id, compliancequest__Activity_Code__c = SUBMIT,
                compliancequest__Activity_Comment__c = res.needsApproval ? 'Submitted for approval from the CQ.AI Investigation workspace' : 'Completed from the CQ.AI Investigation workspace');
            res.responseName = [SELECT Name FROM compliancequest__SQX_Finding_Response__c WHERE Id = :r.Id].Name;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The investigation was not submitted: ' + e.getDmlMessage(0));
        }
        return res;
    }

    static void refuseIfDone(Id invId) {
        compliancequest__SQX_Investigation__c inv = [SELECT compliancequest__Status__c FROM compliancequest__SQX_Investigation__c WHERE Id = :invId];
        if (inv.compliancequest__Status__c == 'Completed' || inv.compliancequest__Status__c == 'In Approval' || inv.compliancequest__Status__c == 'Void') {
            throw new AuraHandledException('This investigation is ' + inv.compliancequest__Status__c + ', so it can no longer be changed here.');
        }
        Integer waiting = [SELECT COUNT() FROM compliancequest__SQX_Response_Inclusion__c
            WHERE compliancequest__SQX_Investigation__c = :invId AND compliancequest__Type__c = 'Investigation'
              AND compliancequest__SQX_Response__r.compliancequest__Status__c IN ('In Approval', 'Completed')];
        if (waiting > 0) { throw new AuraHandledException('This investigation has already been submitted.'); }
    }

    static String str(Object o) { return o == null ? null : String.valueOf(o); }
}
