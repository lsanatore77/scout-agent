/**
 * CqTriageNext: the Next Steps step of CQ.AI Triage, and Complete triage.
 *
 * getNext() gives what the step shows: whether CQ.AI suggests a disposition and an investigation (and why),
 * the default due dates, and the Nonconformance approval matrices (CQ's Approval Matrix records) with which
 * approvals each covers. Default NC is picked unless the user changes it.
 *
 * completeTriage() saves our triage (CqTriageAssistant.saveTriage), then fills in CQ's own Completing Triage
 * fields and runs CQ's Complete Triage, so CQ moves the NC to Disposition / Investigate by its own rules.
 * If CQ refuses, the triage stays saved and the reason comes back as a warning.
 *
 * If a queue still owns the NC (CQ's Submit routes it there), the person completing triage becomes the owner.
 *
 * startTriage() moves a Draft NC to Triage with CQ's own Submit the moment someone starts triage in the workspace,
 * so Draft means not started and Triage means someone is working on it.
 *
 * Defaults live here until the NC settings page exists. E-signature is not asked for yet.
 */
public with sharing class CqTriageNext {
    public static final Integer CONTAINMENT_DAYS = 5;
    public static final Integer DISPOSITION_DAYS = 5;
    public static final Integer INVESTIGATION_DAYS = 60;
    public static final String DEFAULT_MATRIX = 'Default NC';
    public static final String MATRIX_TYPE = 'Nonconformance';
    public static final String INVESTIGATION_LEVEL = 'NC Investigation';
    public static final String COMPLETE_TRIAGE = 'takeownershipandinitiate';
    public static final String SUBMIT = 'submit';

    public class Matrix {
        @AuraEnabled public Id id; @AuraEnabled public String name;
        @AuraEnabled public Boolean disp = false; @AuraEnabled public Boolean inv = false;
    }
    public class Next {
        @AuraEnabled public String dispSuggest;      // 'req' or 'no'
        @AuraEnabled public String dispWhy;
        @AuraEnabled public String invSuggest;       // 'inv' or 'log'
        @AuraEnabled public String invWhy;
        @AuraEnabled public Date containmentDue; @AuraEnabled public Date dispDue; @AuraEnabled public Date invDue;
        @AuraEnabled public Id defaultMatrixId;
        @AuraEnabled public List<Matrix> matrices = new List<Matrix>();
        @AuraEnabled public CqTriageRepeat.Repeat repeat;   // the problem happened before after a CAPA closed
        @AuraEnabled public String capaWhy;                 // why Escalate to CAPA is suggested
    }
    public class Choice {
        public String risk; public String notes; public Integer severity;
        public Boolean containment; public List<String> containmentTitles; public String containmentDue;
        public Boolean disposition; public String dispositionDue; public Boolean dispositionApproval;
        public Boolean investigate; public String investigationDue; public Boolean investigationApproval;
        public Id matrixId;
        public String repeatDecision; public String repeatReason; public Id repeatOfId; public Id repeatCapaId;
    }
    public static final List<String> REPEAT_DECISIONS = new List<String>{ 'Escalate to CAPA', 'Link to Earlier CAPA', 'Not Needed' };
    public class Done {
        @AuraEnabled public String risk; @AuraEnabled public String path;
        @AuraEnabled public List<String> created = new List<String>();
        @AuraEnabled public Boolean moved = false;
        @AuraEnabled public String warning;
    }

    @AuraEnabled
    public static Next getNext(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT compliancequest__Lot_Number__c, compliancequest__Defective_Quantity__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
        Next n = new Next();
        n.containmentDue = Date.today().addDays(CONTAINMENT_DAYS);
        n.dispDue = Date.today().addDays(DISPOSITION_DAYS);
        n.invDue = Date.today().addDays(INVESTIGATION_DAYS);

        // Disposition: something has to be decided when units are defective or stock of the lot is on hand
        Decimal defective = nc.compliancequest__Defective_Quantity__c;
        Decimal onHand = 0;
        String lot = nc.compliancequest__Lot_Number__c;
        if (lot != null) {
            CqLotStock.Stock st = CqLotStock.forLots(new Set<String>{ lot }).get(lot);
            if (st != null && st.total != null) { onHand = st.total; }
        }
        List<String> why = new List<String>();
        if (defective != null && defective > 0) { why.add(num(defective) + (defective == 1 ? ' unit is' : ' units are') + ' defective'); }
        if (onHand > 0) { why.add(num(onHand) + ' units of lot ' + lot + ' are on hand'); }
        if (!why.isEmpty()) {
            n.dispSuggest = 'req';
            n.dispWhy = String.join(why, ' and ') + '.';
        } else {
            n.dispSuggest = 'no';
            n.dispWhy = (defective == null ? 'No defective quantity is recorded' : 'No units are recorded as defective')
                + (lot == null ? ' and no lot is set.' : ' and no stock of lot ' + lot + ' is on hand.');
        }

        // Investigation: needed when the risk is Medium or High, or the problem repeats on the part
        CqTriageRisk.Risk rr = CqTriageRisk.getRisk(recordId);
        Integer score = rr.severity * rr.likelihood;
        String level = rr.escaped ? 'High' : CqTriageRisk.band(score);
        Integer repeats = rr.count == null ? 0 : rr.count;
        Boolean again = rr.repeat != null && rr.repeat.found == true;
        if (level != 'Low' || repeats > 0 || again) {
            n.invSuggest = 'inv';
            List<String> w = new List<String>();
            if (level != 'Low') { w.add('Risk is ' + level + ' (score ' + score + ' of 25)'); }
            if (again) { w.add('the same problem happened before (' + rr.repeat.ncName + ')'); }
            if (repeats > 0) { w.add(repeats + ' other ' + (repeats == 1 ? 'NC was' : 'NCs were') + ' raised on this part in the last ' + CqTriageRisk.WINDOW_DAYS + ' days'); }
            n.invWhy = String.join(w, ' and ') + '.';
        } else {
            n.invSuggest = 'log';
            n.invWhy = 'Risk is Low (score ' + score + ' of 25) and no other NCs were raised on this part in the last ' + CqTriageRisk.WINDOW_DAYS + ' days.';
        }

        if (again) {
            n.repeat = rr.repeat;
            n.capaWhy = 'The same problem came back after ' + rr.repeat.capaName
                + (rr.repeat.effective ? ' was marked effective' : ' closed')
                + ', so that fix did not deal with why it happened. An investigation of this NC alone would likely repeat the same fix.';
        }
        n.matrices = matrices();
        for (Matrix m : n.matrices) { if (m.name == DEFAULT_MATRIX) { n.defaultMatrixId = m.id; } }
        return n;
    }

    /** CQ's Approval Matrix records for nonconformances, with the approvals each covers. */
    public static List<Matrix> matrices() {
        List<Matrix> out = new List<Matrix>();
        Schema.RecordTypeInfo rt = Schema.SObjectType.compliancequest__SQX_Approval_Matrix__c.getRecordTypeInfosByDeveloperName().get(MATRIX_TYPE);
        Id rtId = rt == null ? null : rt.getRecordTypeId();
        for (compliancequest__SQX_Approval_Matrix__c a : [
                SELECT Id, Name,
                       (SELECT compliancequest__Disposition_Approval__c, compliancequest__Investigation_Approval__c FROM compliancequest__SQX_Approval_Matrix_Steps__r)
                FROM compliancequest__SQX_Approval_Matrix__c WHERE RecordTypeId = :rtId WITH USER_MODE ORDER BY Name LIMIT 200]) {
            Matrix m = new Matrix(); m.id = a.Id; m.name = a.Name;
            for (compliancequest__SQX_Approval_Matrix_Step__c s : a.compliancequest__SQX_Approval_Matrix_Steps__r) {
                if (s.compliancequest__Disposition_Approval__c == true) { m.disp = true; }
                if (s.compliancequest__Investigation_Approval__c == true) { m.inv = true; }
            }
            out.add(m);
        }
        return out;
    }

    @AuraEnabled
    public static Done completeTriage(Id recordId, String payload) {
        Choice c = (Choice) JSON.deserialize(payload, Choice.class);
        Boolean disp = c.disposition == true; Boolean inv = c.investigate == true;
        Boolean dispAppr = disp && c.dispositionApproval == true; Boolean invAppr = inv && c.investigationApproval == true;
        if (c.disposition == null) { throw new AuraHandledException('Say whether a disposition is needed.'); }
        if (c.investigate == null) { throw new AuraHandledException('Choose Investigate or Log Only.'); }
        if (disp && String.isBlank(c.dispositionDue)) { throw new AuraHandledException('Set the disposition due date.'); }
        if (inv && String.isBlank(c.investigationDue)) { throw new AuraHandledException('Set the investigation due date.'); }
        if ((dispAppr || invAppr) && c.matrixId == null) { throw new AuraHandledException('Choose an approval matrix.'); }
        if (c.repeatOfId != null) {
            if (String.isBlank(c.repeatDecision) || !REPEAT_DECISIONS.contains(c.repeatDecision)) { throw new AuraHandledException('Choose what to do about the repeat: Escalate to CAPA, Link to Earlier CAPA or Not Needed.'); }
            if (c.repeatDecision != 'Escalate to CAPA' && String.isBlank(c.repeatReason)) { throw new AuraHandledException('Say why the repeat is not escalated to a CAPA.'); }
        }

        // a triage finished without the workspace's start (the popup, say) still goes through Triage first
        Started st = startTriage(recordId);
        compliancequest__SQX_Nonconformance__c cur = [SELECT compliancequest__SQX_Investigation__c, compliancequest__SQX_CAPA__c, OwnerId FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
        String path = !inv ? 'Log Only' : cur.compliancequest__SQX_Investigation__c != null ? 'Continue with Investigation' : 'New Investigation';
        Boolean contain = c.containment == true;

        // 1. our triage, as before (risk, path, notes, containment records)
        CqTriageAssistant.Triage t = CqTriageAssistant.saveTriage(recordId, c.risk, path, c.notes, contain, inv,
            c.containmentTitles, c.containmentDue, false);
        Done d = new Done();
        d.risk = t.risk; d.path = t.path; d.created = t.created;
        List<String> warnings = new List<String>();
        if (st.warning != null) { warnings.add(st.warning); }
        if (t.warning != null) { warnings.add(t.warning.removeStart('Triage saved. ')); }

        // 2. CQ's own Complete Triage, so CQ moves the NC on
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(Id = recordId);
        nc.compliancequest__Triage_Result__c = 'Proceed';
        nc.compliancequest__Priority__c = c.risk == 'High' ? '3 - High' : c.risk == 'Medium' ? '2 - Medium' : '1 - Low';
        if (c.severity != null && c.severity >= 1 && c.severity <= 5) { nc.compliancequest__Defect_Severity__c = CqTriageRisk.SEV[c.severity - 1]; }
        nc.compliancequest__Containment_Required__c = contain;
        nc.compliancequest__Due_Date_Containment__c = contain ? toDate(c.containmentDue, CONTAINMENT_DAYS) : null;
        // CQ's flag makes CQ raise its own 'Please create Disposition' task (twice, inside CQ). We create the draft
        // dispositions ourselves instead and keep the flag off, except when disposition approval is chosen (CQ ties approval to the flag)
        // or when disposition is the only thing chosen (CQ refuses Complete Triage unless at least one of its policies is on).
        Boolean dispFlag = dispAppr || (disp && !inv && !contain);
        nc.compliancequest__Disposition_Required__c = dispFlag;
        nc.compliancequest__Due_Date_Disposition__c = disp ? toDate(c.dispositionDue, DISPOSITION_DAYS) : null;
        nc.compliancequest__Disposition_Approval__c = dispAppr;
        nc.compliancequest__Investigation_Required__c = inv;
        nc.compliancequest__Due_Date_Investigation__c = inv ? toDate(c.investigationDue, INVESTIGATION_DAYS) : null;
        nc.compliancequest__Investigation_Approval__c = invAppr;
        nc.compliancequest__Suggested_Investigation_Level__c = inv ? INVESTIGATION_LEVEL : null;
        nc.compliancequest__SQX_Approval_Matrix__c = dispAppr || invAppr ? c.matrixId : null;
        nc.compliancequest__Activity_Comment__c = String.isBlank(c.notes) ? 'Completed in CQ.AI Triage.' : c.notes.left(4000);
        nc.compliancequest__Activity_Code__c = COMPLETE_TRIAGE;
        nc.Triage_Draft__c = null;      // the work in progress goes in the same save: one save after the stage change
        // CQ's Submit hands the NC to a queue; whoever completes triage takes it, as CQ's take-ownership would. A person owner stays.
        if (cur.OwnerId != null && cur.OwnerId.getSObjectType() == Group.SObjectType) { nc.OwnerId = UserInfo.getUserId(); }
        Savepoint sp = Database.setSavepoint();
        try {
            update as user nc;
            d.moved = true;
        } catch (DmlException e) {
            Database.rollback(sp);
            warnings.add('CQ did not move the NC to Disposition / Investigate: ' + e.getDmlMessage(0));
            // still record what was decided, in CQ's own Required flags
            try {
                update as user new compliancequest__SQX_Nonconformance__c(Id = recordId, compliancequest__Containment_Required__c = contain,
                    compliancequest__Disposition_Required__c = dispFlag, compliancequest__Investigation_Required__c = inv, Triage_Draft__c = null);
            } catch (Exception e2) { /* the triage is saved; the warning above says CQ refused the move */ }
        }

        // the repeat: CQ's Initiate CAPA, or the earlier CAPA as Related CAPA (a closed CAPA is never reopened), and what was decided
        if (c.repeatOfId != null) {
            compliancequest__SQX_Nonconformance__c rp = new compliancequest__SQX_Nonconformance__c(Id = recordId, Repeat_Of__c = c.repeatOfId,
                Repeat_Decision__c = c.repeatDecision, Repeat_Decision_Reason__c = c.repeatDecision == 'Escalate to CAPA' ? null : c.repeatReason.left(255));
            if (c.repeatDecision == 'Escalate to CAPA') { rp.compliancequest__Initiate_CAPA__c = true; }
            if (c.repeatDecision == 'Link to Earlier CAPA' && c.repeatCapaId != null && cur.compliancequest__SQX_CAPA__c == null) { rp.compliancequest__SQX_CAPA__c = c.repeatCapaId; }
            try {
                update as user rp;
            } catch (DmlException e) {
                warnings.add('The repeat decision was not saved: ' + e.getDmlMessage(0));
            }
        }

        // 3. one draft disposition per impacted part and lot, for the Disposition workspace to pick up
        if (disp) {
            try {
                List<String> made = createDraftDispositions(recordId, toDate(c.dispositionDue, DISPOSITION_DAYS));
                if (made.isEmpty()) { warnings.add('No impacted parts or lots are left to dispose, so no disposition was created.'); }
                d.created.addAll(made);
            } catch (DmlException e) {
                warnings.add('The draft dispositions were not created: ' + e.getDmlMessage(0));
            }
        }

        d.warning = warnings.isEmpty() ? null : 'Triage saved. ' + String.join(warnings, ' ');
        return d;
    }

    public class Started {
        @AuraEnabled public Boolean moved = false;
        @AuraEnabled public String stage;
        @AuraEnabled public String warning;
    }

    /** Triage has started: a Draft NC goes to Triage through CQ's own Submit. Any other stage is left as it is. */
    @AuraEnabled
    public static Started startTriage(Id recordId) {
        compliancequest__SQX_Nonconformance__c cur = [SELECT compliancequest__Record_Stage__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
        Started s = new Started();
        s.stage = cur.compliancequest__Record_Stage__c;
        if (s.stage != 'Draft') { return s; }
        try {
            update as user new compliancequest__SQX_Nonconformance__c(Id = recordId, compliancequest__Activity_Code__c = SUBMIT,
                compliancequest__Activity_Comment__c = 'Triage started in CQ.AI Triage.');
            s.moved = true;
            s.stage = [SELECT compliancequest__Record_Stage__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE].compliancequest__Record_Stage__c;
        } catch (DmlException e) {
            s.warning = 'CQ did not move the NC to Triage: ' + e.getDmlMessage(0);
        }
        return s;
    }

    /** A Draft disposition for each impacted part and lot with quantity left, unless one is already open for it. */
    public static List<String> createDraftDispositions(Id recordId, Date due) {
        Set<Id> covered = new Set<Id>();
        for (compliancequest__SQX_Disposition__c x : [SELECT compliancequest__SQX_NC_Impacted_Product__c FROM compliancequest__SQX_Disposition__c
                WHERE compliancequest__SQX_Nonconformance__c = :recordId AND compliancequest__Status__c NOT IN ('Complete', 'Void') WITH USER_MODE]) {
            covered.add(x.compliancequest__SQX_NC_Impacted_Product__c);
        }
        List<compliancequest__SQX_Disposition__c> ins = new List<compliancequest__SQX_Disposition__c>();
        List<String> made = new List<String>();
        for (compliancequest__SQX_NC_Impacted_Product__c ip : [
                SELECT Id, compliancequest__SQX_Impacted_Part__c, compliancequest__Lot_Number__c, compliancequest__Quantity_Left_To_Dispose__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE ORDER BY Name]) {
            Decimal left = ip.compliancequest__Quantity_Left_To_Dispose__c;
            if (covered.contains(ip.Id) || left == null || left <= 0 || ip.compliancequest__Lot_Number__c == null) { continue; }
            String label = 'Disposition for Lot ' + ip.compliancequest__Lot_Number__c;
            ins.add(new compliancequest__SQX_Disposition__c(Name = label.left(80),
                compliancequest__SQX_Nonconformance__c = recordId, compliancequest__SQX_NC_Impacted_Product__c = ip.Id,
                compliancequest__SQX_Part__c = ip.compliancequest__SQX_Impacted_Part__c, compliancequest__Lot_Number__c = ip.compliancequest__Lot_Number__c,
                compliancequest__Disposition_Quantity__c = left, compliancequest__Status__c = 'Draft',
                compliancequest__Due_Date__c = due, compliancequest__SQX_User__c = UserInfo.getUserId()));
            made.add(label + ' (' + num(left) + ')');
        }
        if (!ins.isEmpty()) { insert as user ins; }
        return made;
    }

    static Date toDate(String v, Integer fallbackDays) {
        try { return String.isBlank(v) ? Date.today().addDays(fallbackDays) : Date.valueOf(v); } catch (Exception e) { return Date.today().addDays(fallbackDays); }
    }
    static String num(Decimal v) { return v.stripTrailingZeros().toPlainString(); }
}
