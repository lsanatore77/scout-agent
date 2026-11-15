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
    }
    public class Choice {
        public String risk; public String notes; public Integer severity;
        public Boolean containment; public List<String> containmentTitles; public String containmentDue;
        public Boolean disposition; public String dispositionDue; public Boolean dispositionApproval;
        public Boolean investigate; public String investigationDue; public Boolean investigationApproval;
        public Id matrixId;
    }
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
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
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
        if (level != 'Low' || repeats > 0) {
            n.invSuggest = 'inv';
            List<String> w = new List<String>();
            if (level != 'Low') { w.add('Risk is ' + level + ' (score ' + score + ' of 25)'); }
            if (repeats > 0) { w.add(repeats + ' other ' + (repeats == 1 ? 'NC was' : 'NCs were') + ' raised on this part in the last ' + CqTriageRisk.WINDOW_DAYS + ' days'); }
            n.invWhy = String.join(w, ' and ') + '.';
        } else {
            n.invSuggest = 'log';
            n.invWhy = 'Risk is Low (score ' + score + ' of 25) and no other NCs were raised on this part in the last ' + CqTriageRisk.WINDOW_DAYS + ' days.';
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
                FROM compliancequest__SQX_Approval_Matrix__c WHERE RecordTypeId = :rtId ORDER BY Name LIMIT 200]) {
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

        // a triage finished without the workspace's start (the popup, say) still goes through Triage first
        Started st = startTriage(recordId);
        compliancequest__SQX_Nonconformance__c cur = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
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
        nc.compliancequest__Disposition_Required__c = disp;
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
        Savepoint sp = Database.setSavepoint();
        try {
            update nc;
            d.moved = true;
        } catch (DmlException e) {
            Database.rollback(sp);
            warnings.add('CQ did not move the NC to Disposition / Investigate: ' + e.getDmlMessage(0));
            // still record what was decided, in CQ's own Required flags
            try {
                update new compliancequest__SQX_Nonconformance__c(Id = recordId, compliancequest__Containment_Required__c = contain,
                    compliancequest__Disposition_Required__c = disp, compliancequest__Investigation_Required__c = inv, Triage_Draft__c = null);
            } catch (Exception e2) { /* the triage is saved; the warning above says CQ refused the move */ }
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
        compliancequest__SQX_Nonconformance__c cur = [SELECT compliancequest__Record_Stage__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
        Started s = new Started();
        s.stage = cur.compliancequest__Record_Stage__c;
        if (s.stage != 'Draft') { return s; }
        try {
            update new compliancequest__SQX_Nonconformance__c(Id = recordId, compliancequest__Activity_Code__c = SUBMIT,
                compliancequest__Activity_Comment__c = 'Triage started in CQ.AI Triage.');
            s.moved = true;
            s.stage = [SELECT compliancequest__Record_Stage__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId].compliancequest__Record_Stage__c;
        } catch (DmlException e) {
            s.warning = 'CQ did not move the NC to Triage: ' + e.getDmlMessage(0);
        }
        return s;
    }

    static Date toDate(String v, Integer fallbackDays) {
        try { return String.isBlank(v) ? Date.today().addDays(fallbackDays) : Date.valueOf(v); } catch (Exception e) { return Date.today().addDays(fallbackDays); }
    }
    static String num(Decimal v) { return v.stripTrailingZeros().toPlainString(); }
}
