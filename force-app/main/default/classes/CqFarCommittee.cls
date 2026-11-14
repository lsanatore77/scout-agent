/**
 * CqFarCommittee: the committee approval stage of a Field Action Review, run on CQ Approvals.
 *
 * The recall coordinator builds a committee by functional role (CQ Job Functions named
 * "Field Action Committee - ..."), then submits the recommendation. That creates a CQ Approval
 * with one step per member, all open at once. Members approve or send back through CQ's
 * approval engine. When every step is approved the approval closes and the review is decided,
 * which starts or joins the Field Action. A send back returns the review to the coordinator.
 *
 * In an emergency the coordinator escalates: the approval then has a single step, for one person
 * who holds the "Field Action Emergency Approver" function, and is otherwise a normal approval.
 *
 * CQ's engine does not accept the same person on two open steps, so a person holds one seat.
 */
public with sharing class CqFarCommittee {
    public static final String EMERGENCY_FUNCTION = 'Field Action Emergency Approver';
    public static final String SEAT_PREFIX = 'Field Action Committee - ';

    public class Person { @AuraEnabled public Id id; @AuraEnabled public String name; }
    public class Seat {
        @AuraEnabled public Id functionId; @AuraEnabled public String name; @AuraEnabled public Boolean emergency = false;
        @AuraEnabled public List<Person> people = new List<Person>();
    }
    public class Step {
        @AuraEnabled public Id id; @AuraEnabled public String seat; @AuraEnabled public String person; @AuraEnabled public String status;
        @AuraEnabled public Datetime doneOn; @AuraEnabled public String doneBy; @AuraEnabled public String comment;
        @AuraEnabled public Boolean canAct = false;
    }
    public class Info {
        @AuraEnabled public List<Seat> seats = new List<Seat>();
        @AuraEnabled public Id approvalId; @AuraEnabled public String approvalName; @AuraEnabled public String approvalStatus;
        @AuraEnabled public List<Step> steps = new List<Step>();
        @AuraEnabled public Boolean emergency = false; @AuraEnabled public String emergencyReason;
        @AuraEnabled public String recommendedBy; @AuraEnabled public Datetime recommendedOn;
        @AuraEnabled public String sentBack;    // the committee's comments when the last approval was sent back
    }
    public class Member { public Id functionId; public Id userId; }

    private static String seatName(String functionName) {
        return functionName == EMERGENCY_FUNCTION ? 'Emergency Approver' : functionName.removeStart(SEAT_PREFIX);
    }

    /** Dynamic queries here and in info(): saving the trigger or the workspace would not compile these fields in a static query. */
    private static Boolean isAdmin() {
        List<SObject> p = Database.query('SELECT PermissionsModifyAllData FROM Profile WHERE Id = \'' + UserInfo.getProfileId() + '\'');
        return !p.isEmpty() && (Boolean) p[0].get('PermissionsModifyAllData');
    }

    /** The seats a coordinator can fill, and where the committee's approval stands. */
    public static Info info(Field_Action_Review__c r) {
        Info x = new Info();
        x.emergency = r.Emergency__c == true; x.emergencyReason = r.Emergency_Reason__c;
        x.recommendedBy = r.Recommended_By__r?.Name; x.recommendedOn = r.Recommended_On__c;
        Seat urgent;
        Set<Id> working = new Map<Id, SObject>(Database.query('SELECT Id FROM User WHERE IsActive = true AND UserType = \'Standard\' LIMIT 5000')).keySet();
        for (compliancequest__SQX_Job_Function__c f : [
                SELECT Id, Name,
                       (SELECT compliancequest__SQX_User__c, compliancequest__SQX_User__r.Name FROM compliancequest__SQX_User_Job_Functions__r
                        WHERE compliancequest__Active__c = true ORDER BY compliancequest__SQX_User__r.Name)
                FROM compliancequest__SQX_Job_Function__c
                WHERE compliancequest__Active__c = true AND (Name LIKE :(SEAT_PREFIX + '%') OR Name = :EMERGENCY_FUNCTION)
                ORDER BY Name]) {
            Seat s = new Seat(); s.functionId = f.Id; s.name = seatName(f.Name); s.emergency = f.Name == EMERGENCY_FUNCTION;
            for (compliancequest__SQX_User_Job_Function__c u : f.compliancequest__SQX_User_Job_Functions__r) {
                if (!working.contains(u.compliancequest__SQX_User__c)) { continue; }
                Person p = new Person(); p.id = u.compliancequest__SQX_User__c; p.name = u.compliancequest__SQX_User__r.Name; s.people.add(p);
            }
            if (s.emergency) { urgent = s; } else { x.seats.add(s); }
        }
        if (urgent != null) { x.seats.add(urgent); }
        if (r.Committee_Approval__c == null) { return x; }

        Boolean admin = isAdmin();
        List<String> back = new List<String>();
        for (cqext__CQAPR_Approval__c a : [
                SELECT Id, Name, cqext__Approval_Status__c,
                       (SELECT Id, cqext__Status__c, cqext__CQAPR_Job_Function__r.Name, cqext__CQAPR_Assignee_User__c, cqext__Assignee_Name__c,
                               cqext__CQAPR_Delegate_User__c, cqext__Achieved_On__c, cqext__CQAPR_Achieved_By__r.Name, cqext__Remark__c
                        FROM cqext__CQAPR_Approval_Steps__r ORDER BY cqext__CQAPR_Job_Function__r.Name, Name)
                FROM cqext__CQAPR_Approval__c WHERE Id = :r.Committee_Approval__c]) {
            x.approvalId = a.Id; x.approvalName = a.Name; x.approvalStatus = a.cqext__Approval_Status__c;
            for (cqext__CQAPR_Approval_Step__c t : a.cqext__CQAPR_Approval_Steps__r) {
                Step s = new Step();
                s.id = t.Id; s.seat = t.cqext__CQAPR_Job_Function__r == null ? 'Member' : seatName(t.cqext__CQAPR_Job_Function__r.Name);
                s.person = t.cqext__Assignee_Name__c; s.status = t.cqext__Status__c; s.doneOn = t.cqext__Achieved_On__c;
                s.doneBy = t.cqext__CQAPR_Achieved_By__r?.Name; s.comment = t.cqext__Remark__c;
                // the assigned person or their delegate acts; an administrator can act for them
                s.canAct = r.Status__c == 'With Committee' && t.cqext__Status__c == 'Open'
                    && (t.cqext__CQAPR_Assignee_User__c == UserInfo.getUserId() || t.cqext__CQAPR_Delegate_User__c == UserInfo.getUserId() || admin);
                x.steps.add(s);
                if (t.cqext__Status__c == 'Rejected') { back.add(s.person + ' (' + s.seat + '): ' + (String.isBlank(s.comment) ? 'no comment' : s.comment)); }
            }
        }
        if (r.Status__c == 'In Review' && x.approvalStatus == 'Rejected' && !back.isEmpty()) { x.sentBack = String.join(back, '\n'); }
        return x;
    }

    /** The coordinator's recommendation goes to the committee as a CQ Approval, one open step per member. */
    @AuraEnabled
    public static CqFieldActionReview.View submitToCommittee(Id recordId, String hazard, String summary, Integer score, String riskLevel,
                                                             String outcome, String rationale, String draft, String team,
                                                             Boolean emergency, String emergencyReason) {
        if (outcome != 'No Field Action' && outcome != 'Field Action Needed') { throw new AuraHandledException('Choose an outcome.'); }
        if (String.isBlank(rationale)) { throw new AuraHandledException('A rationale is required.'); }
        if (emergency == true && String.isBlank(emergencyReason)) { throw new AuraHandledException('Give the reason for the emergency.'); }
        List<Member> members = String.isBlank(team) ? new List<Member>() : (List<Member>) JSON.deserialize(team, List<Member>.class);
        if (members.isEmpty()) { throw new AuraHandledException('Choose the committee.'); }
        if (emergency == true && members.size() != 1) { throw new AuraHandledException('An emergency approval has one approver.'); }

        Field_Action_Review__c r = [SELECT Id, Name, Status__c, Reviewer__c FROM Field_Action_Review__c WHERE Id = :recordId];
        if (r.Status__c == 'With Committee') { throw new AuraHandledException('This review is already with the committee.'); }
        if (r.Status__c == 'Decided' || r.Status__c == 'Closed') { throw new AuraHandledException('This review is already decided.'); }

        // every member must hold the function of the seat they are given, and a person holds one seat
        Set<Id> functionIds = new Set<Id>(); Set<Id> userIds = new Set<Id>();
        for (Member m : members) {
            if (m.functionId == null || m.userId == null) { throw new AuraHandledException('Choose a person for every seat.'); }
            if (userIds.contains(m.userId)) { throw new AuraHandledException('One person can hold only one seat on the committee.'); }
            functionIds.add(m.functionId); userIds.add(m.userId);
        }
        Set<String> holds = new Set<String>(); Map<Id, String> functionName = new Map<Id, String>();
        for (compliancequest__SQX_User_Job_Function__c u : [
                SELECT compliancequest__SQX_User__c, compliancequest__SQX_Job_Function__c, compliancequest__SQX_Job_Function__r.Name
                FROM compliancequest__SQX_User_Job_Function__c
                WHERE compliancequest__Active__c = true AND compliancequest__SQX_Job_Function__c IN :functionIds AND compliancequest__SQX_User__c IN :userIds]) {
            holds.add(u.compliancequest__SQX_Job_Function__c + '|' + u.compliancequest__SQX_User__c);
            functionName.put(u.compliancequest__SQX_Job_Function__c, u.compliancequest__SQX_Job_Function__r.Name);
        }
        for (Member m : members) {
            if (!holds.contains(m.functionId + '|' + m.userId)) { throw new AuraHandledException('A chosen person does not hold the function for their seat.'); }
            Boolean urgentSeat = functionName.get(m.functionId) == EMERGENCY_FUNCTION;
            if (emergency == true && !urgentSeat) { throw new AuraHandledException('An emergency approval needs an Emergency Approver.'); }
            if (emergency != true && urgentSeat) { throw new AuraHandledException('The Emergency Approver seat is for emergency approvals only.'); }
        }

        r.Health_Hazard_Summary__c = hazard; r.Review_Summary__c = summary; r.Risk_Score__c = score; r.Risk_Level__c = riskLevel;
        r.Outcome__c = outcome; r.Outcome_Rationale__c = rationale;
        r.Emergency__c = emergency == true; r.Emergency_Reason__c = emergency == true ? emergencyReason : null;
        r.Recommended_By__c = UserInfo.getUserId(); r.Recommended_On__c = Datetime.now();
        r.Review_Draft__c = String.isBlank(draft) ? null : draft.left(20000);     // kept: it holds the field action to start or join
        r.Status__c = 'With Committee';
        if (r.Reviewer__c == null) { r.Reviewer__c = UserInfo.getUserId(); }
        update r;

        cqext__CQAPR_Approval__c approval = new cqext__CQAPR_Approval__c(
            cqext__Approval_Record__c = 'CQ Record', cqext__Approval_Type__c = 'CQ Approval',
            cqext__Main_Record_Id__c = r.Id, cqext__Child_Record_Id__c = r.Id,
            cqext__Submission_Remark__c = (r.Name + ': ' + outcome + '. ' + rationale).left(30000));
        List<cqext__CQAPR_Approval_Step__c> steps = new List<cqext__CQAPR_Approval_Step__c>();
        for (Member m : members) {
            steps.add(new cqext__CQAPR_Approval_Step__c(
                cqext__Step__c = 1, cqext__CQAPR_Assignee_User__c = m.userId, cqext__Assignee_Id__c = m.userId, cqext__CQAPR_Job_Function__c = m.functionId));
        }
        // CQ's engine is reached by name through CqApprovalGateway: see that interface for why.
        ((CqApprovalGateway) Type.forName('CqApprovalBridge').newInstance()).submit(r, approval, steps);

        List<cqext__CQAPR_Approval__c> made = [SELECT Id FROM cqext__CQAPR_Approval__c
                                               WHERE cqext__Main_Record_Id__c = :r.Id AND cqext__Status__c = 'Open' ORDER BY CreatedDate DESC LIMIT 1];
        if (made.isEmpty()) { throw new AuraHandledException('CQ Approvals did not accept the submission.'); }
        update new Field_Action_Review__c(Id = r.Id, Committee_Approval__c = made[0].Id);
        return CqFieldActionReview.getView(recordId);
    }

    /** A member approves or sends back. The last approval closes the CQ Approval; a send back closes it as rejected. */
    @AuraEnabled
    public static CqFieldActionReview.View act(Id recordId, Id stepId, String action, String comment) {
        if (action != 'approve' && action != 'reject') { throw new AuraHandledException('Choose Approve or Send Back.'); }
        if (action == 'reject' && String.isBlank(comment)) { throw new AuraHandledException('Say why you are sending it back.'); }
        cqext__CQAPR_Approval_Step__c t = [
            SELECT Id, cqext__Status__c, cqext__CQAPR_Approval__c, cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c,
                   cqext__CQAPR_Assignee_User__c, cqext__CQAPR_Delegate_User__c
            FROM cqext__CQAPR_Approval_Step__c WHERE Id = :stepId];
        if (t.cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c != String.valueOf(recordId).left(15)
                && t.cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c != String.valueOf(recordId)) {
            throw new AuraHandledException('That approval step belongs to another record.');
        }
        if (t.cqext__Status__c != 'Open') { throw new AuraHandledException('That step is no longer open.'); }
        Boolean admin = isAdmin();
        if (t.cqext__CQAPR_Assignee_User__c != UserInfo.getUserId() && t.cqext__CQAPR_Delegate_User__c != UserInfo.getUserId() && !admin) {
            throw new AuraHandledException('This step is assigned to someone else.');
        }
        update new cqext__CQAPR_Approval_Step__c(Id = stepId, cqext__Activity_Code__c = action, cqext__Remark__c = String.isBlank(comment) ? null : comment.left(1024));
        if (action == 'reject') {
            update new cqext__CQAPR_Approval__c(Id = t.cqext__CQAPR_Approval__c, cqext__Activity_Code__c = 'reject', cqext__Activity_Comment__c = comment.left(1024));
        } else if ([SELECT COUNT() FROM cqext__CQAPR_Approval_Step__c WHERE cqext__CQAPR_Approval__c = :t.cqext__CQAPR_Approval__c AND cqext__Status__c = 'Open'] == 0) {
            update new cqext__CQAPR_Approval__c(Id = t.cqext__CQAPR_Approval__c, cqext__Activity_Code__c = 'approve');
        }
        return CqFieldActionReview.getView(recordId);
    }

    /**
     * Called by the trigger on CQ Approval when an approval closes, wherever it was approved from.
     * Approved: the review is decided, which starts or joins the Field Action. Anything else returns it to the coordinator.
     */
    public static void onClosed(Map<Id, String> statusByApproval) {
        for (Field_Action_Review__c r : [
                SELECT Id, Committee_Approval__c, Health_Hazard_Summary__c, Review_Summary__c, Risk_Score__c, Risk_Level__c,
                       Outcome__c, Outcome_Rationale__c, Review_Draft__c
                FROM Field_Action_Review__c WHERE Committee_Approval__c IN :statusByApproval.keySet() AND Status__c = 'With Committee']) {
            if (statusByApproval.get(r.Committee_Approval__c) != 'Approved') {
                update new Field_Action_Review__c(Id = r.Id, Status__c = 'In Review');
                continue;
            }
            Map<String, Object> d = new Map<String, Object>();
            try { if (r.Review_Draft__c != null) { d = (Map<String, Object>) JSON.deserializeUntyped(r.Review_Draft__c); } } catch (Exception e) { d = new Map<String, Object>(); }
            String choice = (String) d.get('faChoice');
            Id joinId = r.Outcome__c == 'Field Action Needed' && choice != null && choice != 'new' && choice != '' ? (Id) choice : null;
            CqFieldActionReview.submit(r.Id, r.Health_Hazard_Summary__c, r.Review_Summary__c,
                r.Risk_Score__c == null ? null : r.Risk_Score__c.intValue(), r.Risk_Level__c, r.Outcome__c, r.Outcome_Rationale__c,
                joinId, (String) d.get('faTitle'), (String) d.get('actionType'), (String) d.get('recallClass'));
        }
    }
}
