/**
 * CqFieldActionScope: data and saves for the Field Action workspace, steps 1 and 2.
 *
 * Step 1, Field Action at a Glance: what was decided and why, the reviews that led here, their committee approvals,
 * the signals and the risk.
 *
 * Step 2, Scope: the lots the field action covers.
 *  - Full covers every lot of the part, including lots that appear later. It needs no scope approval; sync() adds any
 *    new lot automatically each time the workspace opens. syncFull() does the same for every open Full field action,
 *    for a scheduled job to call.
 *  - Partial is chosen by the coordinator, then approved on CQ Approvals by the committee or, in an emergency,
 *    by one emergency approver. A change after approval returns the scope to Being Defined until it is approved again.
 * Every lot added or removed is logged as a Field Action Scope Change. Lot genealogy, from the batch records, shows
 * the component lots a lot was built from and the other finished lots that used them.
 */
public with sharing class CqFieldActionScope {
    public static final String FULL = 'Full';
    public static final String PARTIAL = 'Partial';

    public class Review {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String source; @AuraEnabled public Id sourceId;
        @AuraEnabled public String lot; @AuraEnabled public String outcome; @AuraEnabled public Decimal score; @AuraEnabled public String risk;
        @AuraEnabled public Datetime decidedOn; @AuraEnabled public String decidedBy; @AuraEnabled public String rationale;
        @AuraEnabled public Id approvalId; @AuraEnabled public String approvalName; @AuraEnabled public String approvedBy;
        @AuraEnabled public Boolean emergency = false;
    }
    public class Sig {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String rule; @AuraEnabled public String strength;
        @AuraEnabled public String label; @AuraEnabled public String lot;
    }
    public class LotRow {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Id lotId; @AuraEnabled public Boolean known = false;
        @AuraEnabled public Boolean inScope = false; @AuraEnabled public Boolean approved = false;
        @AuraEnabled public String how; @AuraEnabled public String reason;
        @AuraEnabled public Decimal built; @AuraEnabled public Date made;
        @AuraEnabled public Decimal shipped; @AuraEnabled public Decimal onHand; @AuraEnabled public String location;
        @AuraEnabled public Integer records = 0; @AuraEnabled public String firstRecord;
        @AuraEnabled public Integer signals = 0;
        @AuraEnabled public Boolean suggested = false; @AuraEnabled public String why;
    }
    public class Change {
        @AuraEnabled public String lot; @AuraEnabled public String change; @AuraEnabled public String how; @AuraEnabled public String reason;
        @AuraEnabled public String doneBy; @AuraEnabled public Datetime doneAt;
    }
    public class View {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String status;
        @AuraEnabled public String actionType; @AuraEnabled public String recallClass; @AuraEnabled public String description;
        @AuraEnabled public String rationale; @AuraEnabled public String decidedBy; @AuraEnabled public Datetime decidedOn;
        @AuraEnabled public Id partId; @AuraEnabled public String partNumber; @AuraEnabled public String partName;
        @AuraEnabled public Decimal qtyAffected; @AuraEnabled public Decimal qtyShipped;
        @AuraEnabled public String scope; @AuraEnabled public String scopeStatus; @AuraEnabled public Datetime scopeApprovedOn;
        @AuraEnabled public Boolean scopeEmergency = false; @AuraEnabled public String scopeEmergencyReason;
        @AuraEnabled public List<Review> reviews = new List<Review>();
        @AuraEnabled public Integer score; @AuraEnabled public String riskLevel; @AuraEnabled public String hazard;
        @AuraEnabled public List<Sig> signals = new List<Sig>();
        @AuraEnabled public List<LotRow> inScope = new List<LotRow>();
        @AuraEnabled public List<LotRow> outOfScope = new List<LotRow>();   // suggested first
        @AuraEnabled public List<Change> changes = new List<Change>();
        @AuraEnabled public CqFarCommittee.Info committee;
        @AuraEnabled public List<CqFarCommittee.Member> defaultTeam = new List<CqFarCommittee.Member>();
        @AuraEnabled public Boolean defaultEmergency = false;
        @AuraEnabled public String sentBack;
    }
    public class Sister { @AuraEnabled public String lot; @AuraEnabled public String part; @AuraEnabled public Boolean samePart = false; @AuraEnabled public Boolean inScope = false; }
    public class Component {
        @AuraEnabled public String lot; @AuraEnabled public String part; @AuraEnabled public String partName;
        @AuraEnabled public List<Sister> sisters = new List<Sister>();
    }
    public class Genealogy {
        @AuraEnabled public String lot; @AuraEnabled public String batch; @AuraEnabled public String note;
        @AuraEnabled public List<Component> components = new List<Component>();
    }

    private static Field_Action__c load(Id recordId) {
        return [SELECT Id, Name, Title__c, Status__c, Action_Type__c, Recall_Class__c, Description__c, Decision_Rationale__c,
                       Decided_By__r.Name, Decided_On__c, Part__c, Part__r.Name, Part__r.compliancequest__Part_Number__c,
                       Quantity_Affected__c, Quantity_Shipped__c, Lot_Numbers__c,
                       Scope__c, Scope_Status__c, Scope_Approval__c, Scope_Emergency__c, Scope_Emergency_Reason__c, Scope_Approved_On__c
                FROM Field_Action__c WHERE Id = :recordId];
    }

    // ---------------------------------------------------------------- lots of a part

    /** Every lot of the part: CQ lot records, and lot numbers found on its complaints and nonconformances. */
    private static Map<String, LotRow> lotsOfPart(Id partId, String partNumber) {
        Map<String, LotRow> out = new Map<String, LotRow>();
        if (partNumber != null) {
            for (compliancequest__SQX_Lot_Info__c l : [
                    SELECT Id, Name, compliancequest__Manufacturing_Date__c, Batch__r.cqext__Quantity__c, Batch__r.cqext__Actual_Yield__c
                    FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c = :partNumber ORDER BY Name LIMIT 1000]) {
                LotRow x = new LotRow(); x.name = l.Name; x.lotId = l.Id; x.known = true; x.made = l.compliancequest__Manufacturing_Date__c;
                Decimal yield = l.Batch__r?.cqext__Actual_Yield__c;
                x.built = yield != null && yield > 0 ? yield : l.Batch__r?.cqext__Quantity__c;
                out.put(x.name, x);
            }
        }
        if (partId == null) { return out; }
        List<SObject> recs = new List<SObject>();
        recs.addAll([SELECT Name, compliancequest__Lot_Number__c FROM compliancequest__SQX_Nonconformance__c
                     WHERE compliancequest__SQX_Part__c = :partId AND compliancequest__Lot_Number__c != null ORDER BY CreatedDate LIMIT 2000]);
        recs.addAll([SELECT Name, compliancequest__Lot_Number__c FROM compliancequest__SQX_Complaint__c
                     WHERE compliancequest__SQX_Part__c = :partId AND compliancequest__Lot_Number__c != null ORDER BY CreatedDate LIMIT 2000]);
        for (SObject r : recs) {
            String n = (String) r.get('compliancequest__Lot_Number__c');
            if (!out.containsKey(n)) { LotRow x = new LotRow(); x.name = n; out.put(n, x); }
            LotRow x = out.get(n);
            x.records++;
            if (x.firstRecord == null) { x.firstRecord = (String) r.get('Name'); }
        }
        return out;
    }

    private static void log(List<Field_Action_Scope_Change__c> logs, Id faId, String lot, String change, String how, String reason) {
        logs.add(new Field_Action_Scope_Change__c(Field_Action__c = faId, Lot_Number__c = lot, Change__c = change, How__c = how,
            Reason__c = reason == null ? null : reason.left(255)));
    }

    /** Keeps the Lot Numbers text on the Field Action equal to the lots in scope. */
    private static void syncText(Set<Id> faIds) {
        Map<Id, List<String>> names = new Map<Id, List<String>>();
        for (Id f : faIds) { names.put(f, new List<String>()); }
        for (Field_Action_Lot__c l : [SELECT Field_Action__c, Lot_Number__c FROM Field_Action_Lot__c
                                      WHERE Field_Action__c IN :faIds AND In_Scope__c = true ORDER BY Lot_Number__c]) {
            names.get(l.Field_Action__c).add(l.Lot_Number__c);
        }
        List<Field_Action__c> ups = new List<Field_Action__c>();
        for (Id f : faIds) { ups.add(new Field_Action__c(Id = f, Lot_Numbers__c = String.join(names.get(f), ', ').left(255))); }
        update ups;
    }

    /**
     * Full scope widens itself: every lot of the part that is not yet in scope is added, with the reason.
     * The first fill, straight after the decision, says the scope is Full; a later one says where the new lot was found.
     */
    public static void sync(Set<Id> faIds) {
        List<Field_Action_Lot__c> adds = new List<Field_Action_Lot__c>();
        List<Field_Action_Scope_Change__c> logs = new List<Field_Action_Scope_Change__c>();
        Set<Id> touched = new Set<Id>();
        for (Field_Action__c fa : [SELECT Id, Part__c, Part__r.compliancequest__Part_Number__c,
                                          (SELECT Lot_Number__c, Added_How__c FROM Lots_In_Scope__r)
                                   FROM Field_Action__c WHERE Id IN :faIds AND Scope__c = :FULL AND Status__c != 'Closed' LIMIT 20]) {
            Set<String> has = new Set<String>();
            Boolean first = true;     // the first fill: only the lot the review brought is there so far
            for (Field_Action_Lot__c l : fa.Lots_In_Scope__r) { has.add(l.Lot_Number__c); if (l.Added_How__c == 'Automatic') { first = false; } }
            String part = fa.Part__r?.compliancequest__Part_Number__c;
            for (LotRow x : lotsOfPart(fa.Part__c, part).values()) {
                if (has.contains(x.name)) { continue; }
                String why = first ? 'Full scope covers every lot of ' + part
                    : x.known ? 'New lot of ' + part + ' found in CQ' : 'Lot number found on ' + x.firstRecord;
                adds.add(new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot__c = x.lotId, Lot_Number__c = x.name, Units_Built__c = x.built,
                    In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic', Reason__c = why));
                log(logs, fa.Id, x.name, 'Added', 'Automatic', why);
                touched.add(fa.Id);
            }
        }
        if (adds.isEmpty()) { return; }
        insert adds; insert logs;
        syncText(touched);
    }

    /** Called by the signal job: brings every open Full field action up to date. */
    public static void syncFull() {
        sync(new Map<Id, Field_Action__c>([SELECT Id FROM Field_Action__c WHERE Scope__c = :FULL AND Status__c != 'Closed' LIMIT 20]).keySet());
    }

    // ---------------------------------------------------------------- the view

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action__c probe = [SELECT Scope__c FROM Field_Action__c WHERE Id = :recordId];
        if (probe.Scope__c == FULL) { sync(new Set<Id>{ recordId }); }
        Field_Action__c fa = load(recordId);
        View v = new View();
        v.id = fa.Id; v.name = fa.Name; v.title = fa.Title__c; v.status = fa.Status__c; v.actionType = fa.Action_Type__c;
        v.recallClass = fa.Recall_Class__c; v.description = fa.Description__c; v.rationale = fa.Decision_Rationale__c;
        v.decidedBy = fa.Decided_By__r?.Name; v.decidedOn = fa.Decided_On__c;
        v.partId = fa.Part__c; v.partNumber = fa.Part__r?.compliancequest__Part_Number__c; v.partName = fa.Part__r?.Name;
        v.qtyAffected = fa.Quantity_Affected__c; v.qtyShipped = fa.Quantity_Shipped__c;
        v.scope = fa.Scope__c; v.scopeStatus = fa.Scope_Status__c; v.scopeApprovedOn = fa.Scope_Approved_On__c;
        v.scopeEmergency = fa.Scope_Emergency__c == true; v.scopeEmergencyReason = fa.Scope_Emergency_Reason__c;

        // the reviews that led here, with the committee approvals behind them
        Set<Id> approvals = new Set<Id>();
        Map<Id, Review> byApproval = new Map<Id, Review>();
        Decimal top;
        for (Field_Action_Review__c r : [
                SELECT Id, Name, Lot_Number__c, Outcome__c, Risk_Score__c, Risk_Level__c, Health_Hazard_Summary__c, Outcome_Rationale__c,
                       Decided_On__c, Decided_By__r.Name, Committee_Approval__c, Committee_Approval__r.Name, Emergency__c,
                       Nonconformance__c, Nonconformance__r.Name, Nonconformance__r.compliancequest__Lot_Number__c,
                       Complaint__c, Complaint__r.Name, Complaint__r.compliancequest__Lot_Number__c
                FROM Field_Action_Review__c WHERE Field_Action__c = :recordId ORDER BY Decided_On__c NULLS LAST, Name LIMIT 50]) {
            Review x = new Review();
            x.id = r.Id; x.name = r.Name; x.outcome = r.Outcome__c; x.score = r.Risk_Score__c; x.risk = r.Risk_Level__c;
            x.decidedOn = r.Decided_On__c; x.decidedBy = r.Decided_By__r?.Name; x.rationale = r.Outcome_Rationale__c;
            x.sourceId = r.Nonconformance__c != null ? r.Nonconformance__c : r.Complaint__c;
            x.source = r.Nonconformance__c != null ? r.Nonconformance__r.Name : r.Complaint__r?.Name;
            x.lot = r.Lot_Number__c != null ? r.Lot_Number__c : r.Nonconformance__c != null ? r.Nonconformance__r.compliancequest__Lot_Number__c : r.Complaint__r?.compliancequest__Lot_Number__c;
            x.approvalId = r.Committee_Approval__c; x.approvalName = r.Committee_Approval__r?.Name; x.emergency = r.Emergency__c == true;
            if (r.Committee_Approval__c != null) { approvals.add(r.Committee_Approval__c); byApproval.put(r.Committee_Approval__c, x); }
            v.reviews.add(x);
            if (r.Risk_Score__c != null && (top == null || r.Risk_Score__c > top)) {
                top = r.Risk_Score__c; v.score = r.Risk_Score__c.intValue(); v.riskLevel = r.Risk_Level__c; v.hazard = r.Health_Hazard_Summary__c;
            }
            if (v.hazard == null) { v.hazard = r.Health_Hazard_Summary__c; v.riskLevel = r.Risk_Level__c; }
        }
        // who approved each decision; the latest decision's members are the default committee for the scope
        Id latest = v.reviews.isEmpty() ? null : v.reviews[v.reviews.size() - 1].approvalId;
        Map<Id, List<String>> who = new Map<Id, List<String>>();
        for (cqext__CQAPR_Approval_Step__c t : [
                SELECT cqext__CQAPR_Approval__c, cqext__Status__c, cqext__Assignee_Name__c, cqext__CQAPR_Assignee_User__c,
                       cqext__CQAPR_Job_Function__c, cqext__CQAPR_Job_Function__r.Name
                FROM cqext__CQAPR_Approval_Step__c WHERE cqext__CQAPR_Approval__c IN :approvals ORDER BY cqext__CQAPR_Job_Function__r.Name]) {
            String seat = t.cqext__CQAPR_Job_Function__r == null ? 'Member'
                : t.cqext__CQAPR_Job_Function__r.Name == CqFarCommittee.EMERGENCY_FUNCTION ? 'Emergency Approver'
                : t.cqext__CQAPR_Job_Function__r.Name.removeStart(CqFarCommittee.SEAT_PREFIX);
            if (t.cqext__Status__c == 'Approved') {
                if (!who.containsKey(t.cqext__CQAPR_Approval__c)) { who.put(t.cqext__CQAPR_Approval__c, new List<String>()); }
                who.get(t.cqext__CQAPR_Approval__c).add(t.cqext__Assignee_Name__c + ' (' + seat + ')');
            }
            if (t.cqext__CQAPR_Approval__c == latest && t.cqext__CQAPR_Job_Function__c != null) {
                CqFarCommittee.Member m = new CqFarCommittee.Member(); m.functionId = t.cqext__CQAPR_Job_Function__c; m.userId = t.cqext__CQAPR_Assignee_User__c;
                v.defaultTeam.add(m);
                if (seat == 'Emergency Approver') { v.defaultEmergency = true; }
            }
        }
        for (Id a : who.keySet()) { byApproval.get(a).approvedBy = String.join(who.get(a), ', '); }

        // signals on the part at Assess or Escalate
        Map<String, List<String>> sigByLot = new Map<String, List<String>>();
        if (fa.Part__c != null) {
            for (Signal__c s : [SELECT Id, Name, Rule__r.Name, Strength__c, Value_Label__c, Summary__c, Lot_Number__c, Rule__r.Code__c
                                FROM Signal__c WHERE Part__c = :fa.Part__c AND Status__c NOT IN ('Closed', 'Dismissed')
                                  AND Strength__c IN ('Assess', 'Escalate') ORDER BY Score__c DESC NULLS LAST, Name LIMIT 50]) {
                Sig g = new Sig(); g.id = s.Id; g.name = s.Name; g.rule = s.Rule__r == null ? 'Manual' : s.Rule__r.Name; g.strength = s.Strength__c;
                g.label = s.Value_Label__c != null ? s.Value_Label__c : s.Summary__c; g.lot = s.Lot_Number__c;
                v.signals.add(g);
                if (s.Lot_Number__c != null && s.Rule__r?.Code__c != 'SHARED_COMPONENT_LOT') {
                    if (!sigByLot.containsKey(s.Lot_Number__c)) { sigByLot.put(s.Lot_Number__c, new List<String>()); }
                    sigByLot.get(s.Lot_Number__c).add(g.rule + ' at ' + g.strength);
                }
            }
        }

        // lots: every lot of the part, merged with the rows in scope
        Map<String, LotRow> lots = lotsOfPart(fa.Part__c, v.partNumber);
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c, Lot__c, In_Scope__c, Approved_In_Scope__c, Added_How__c, Reason__c,
                                             Units_Built__c, Units_Shipped__c, Units_On_Hand__c, Location__c
                                      FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId]) {
            LotRow x = lots.containsKey(l.Lot_Number__c) ? lots.get(l.Lot_Number__c) : new LotRow();
            x.id = l.Id; x.name = l.Lot_Number__c; x.inScope = l.In_Scope__c; x.approved = l.Approved_In_Scope__c; x.how = l.Added_How__c; x.reason = l.Reason__c;
            if (x.lotId == null) { x.lotId = l.Lot__c; }
            if (x.built == null) { x.built = l.Units_Built__c; }
            x.shipped = l.Units_Shipped__c; x.onHand = l.Units_On_Hand__c; x.location = l.Location__c;
            lots.put(x.name, x);
        }
        // CQ.AI suggests a lot left out when it has a signal of its own or shares a component lot with a lot in scope
        Set<String> inNames = new Set<String>();
        for (LotRow x : lots.values()) { if (x.inScope) { inNames.add(x.name); } }
        Map<String, String> sharesWith = sharedComponents(lots, inNames);
        List<String> order = new List<String>(lots.keySet()); order.sort();
        List<LotRow> picked = new List<LotRow>(); List<LotRow> rest = new List<LotRow>();
        for (String n : order) {
            LotRow x = lots.get(n);
            List<String> why = sigByLot.containsKey(n) ? sigByLot.get(n) : new List<String>();
            x.signals = why.size();
            if (x.inScope) { v.inScope.add(x); continue; }
            if (sharesWith.containsKey(n)) { why.add(sharesWith.get(n)); }
            x.suggested = !why.isEmpty();
            if (x.suggested) { x.why = String.join(why.size() > 2 ? new List<String>{ why[0], why[1] } : why, '; '); picked.add(x); } else { rest.add(x); }
        }
        v.outOfScope.addAll(picked); v.outOfScope.addAll(rest);

        for (Field_Action_Scope_Change__c c : [SELECT Lot_Number__c, Change__c, How__c, Reason__c, CreatedBy.Name, CreatedDate
                                               FROM Field_Action_Scope_Change__c WHERE Field_Action__c = :recordId
                                               ORDER BY CreatedDate DESC, Name DESC LIMIT 200]) {
            Change x = new Change(); x.lot = c.Lot_Number__c; x.change = c.Change__c; x.how = c.How__c; x.reason = c.Reason__c;
            x.doneBy = c.CreatedBy.Name; x.doneAt = c.CreatedDate;
            v.changes.add(x);
        }

        // the scope approval, on CQ Approvals
        CqFarCommittee.Info x = new CqFarCommittee.Info();
        x.seats = CqFarCommittee.seats();
        x.emergency = v.scopeEmergency; x.emergencyReason = v.scopeEmergencyReason;
        if (fa.Scope_Approval__c != null) {
            List<String> back = CqFarCommittee.loadApproval(x, fa.Scope_Approval__c, fa.Scope_Status__c == 'With Committee');
            if (fa.Scope_Status__c == 'Being Defined' && x.approvalStatus == 'Rejected' && !back.isEmpty()) { v.sentBack = String.join(back, '\n'); }
        }
        v.committee = x;
        return v;
    }

    /**
     * Lots left out of scope that share a component lot with a lot in scope, from the batch records.
     * Returns lot -> one line saying which component and which lot in scope.
     */
    private static Map<String, String> sharedComponents(Map<String, LotRow> lots, Set<String> inNames) {
        Map<String, String> out = new Map<String, String>();
        Map<Id, String> lotByBatch = new Map<Id, String>();
        Set<Id> lotIds = new Set<Id>();
        for (LotRow x : lots.values()) { if (x.lotId != null) { lotIds.add(x.lotId); } }
        if (lotIds.isEmpty() || inNames.isEmpty()) { return out; }
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name, Batch__c FROM compliancequest__SQX_Lot_Info__c WHERE Id IN :lotIds AND Batch__c != null]) {
            lotByBatch.put(l.Batch__c, l.Name);
        }
        if (lotByBatch.isEmpty()) { return out; }
        Map<String, Set<String>> finishedByComp = new Map<String, Set<String>>();
        Map<String, String> compPart = new Map<String, String>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c,
                       cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c != null
                  AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c IN :lotByBatch.keySet() LIMIT 10000]) {
            String finished = lotByBatch.get(m.cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c);
            if (!finishedByComp.containsKey(m.cqext__Lot_Number__c)) { finishedByComp.put(m.cqext__Lot_Number__c, new Set<String>()); }
            finishedByComp.get(m.cqext__Lot_Number__c).add(finished);
            compPart.put(m.cqext__Lot_Number__c, m.cqext__CQEBR_Operator_Product__r?.compliancequest__Part_Number__c);
        }
        List<String> comps = new List<String>(finishedByComp.keySet()); comps.sort();
        for (String c : comps) {
            Set<String> fin = finishedByComp.get(c);
            String inLot;
            for (String f : fin) { if (inNames.contains(f)) { inLot = f; break; } }
            if (inLot == null) { continue; }
            for (String f : fin) {
                if (inNames.contains(f) || out.containsKey(f)) { continue; }
                out.put(f, 'Shares component lot ' + c + (compPart.get(c) == null ? '' : ' (' + compPart.get(c) + ')') + ' with ' + inLot);
            }
        }
        return out;
    }

    /** Lot genealogy from the batch records: the component lots a lot was built from, and the other finished lots that used them. */
    @AuraEnabled
    public static Genealogy genealogy(Id recordId, String lot) {
        Genealogy g = new Genealogy(); g.lot = lot;
        Field_Action__c fa = load(recordId);
        Set<String> inNames = new Set<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND In_Scope__c = true]) { inNames.add(l.Lot_Number__c); }
        List<compliancequest__SQX_Lot_Info__c> mine = [SELECT Batch__c, Batch__r.Name FROM compliancequest__SQX_Lot_Info__c
                                                       WHERE Name = :lot AND Batch__c != null LIMIT 1];
        if (mine.isEmpty()) { g.note = 'No batch record is linked to lot ' + lot + ', so its components are not known.'; return g; }
        g.batch = mine[0].Batch__r.Name;
        Map<String, Component> comps = new Map<String, Component>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c, cqext__CQEBR_Operator_Product__r.Name
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c != null AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c = :mine[0].Batch__c
                ORDER BY cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c LIMIT 500]) {
            if (comps.containsKey(m.cqext__Lot_Number__c)) { continue; }
            Component c = new Component(); c.lot = m.cqext__Lot_Number__c;
            c.part = m.cqext__CQEBR_Operator_Product__r?.compliancequest__Part_Number__c; c.partName = m.cqext__CQEBR_Operator_Product__r?.Name;
            comps.put(c.lot, c);
        }
        if (comps.isEmpty()) { g.note = 'The batch record for lot ' + lot + ' lists no component lots.'; return g; }
        Map<Id, Set<String>> compsByBatch = new Map<Id, Set<String>>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c IN :comps.keySet()
                  AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c != :mine[0].Batch__c LIMIT 5000]) {
            Id b = m.cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c;
            if (!compsByBatch.containsKey(b)) { compsByBatch.put(b, new Set<String>()); }
            compsByBatch.get(b).add(m.cqext__Lot_Number__c);
        }
        if (!compsByBatch.isEmpty()) {
            String partNumber = fa.Part__r?.compliancequest__Part_Number__c;
            for (compliancequest__SQX_Lot_Info__c l : [SELECT Name, Batch__c, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
                                                       WHERE Batch__c IN :compsByBatch.keySet() ORDER BY Name]) {
                for (String c : compsByBatch.get(l.Batch__c)) {
                    Sister s = new Sister(); s.lot = l.Name; s.part = l.compliancequest__Part_Number__c;
                    s.samePart = s.part == partNumber; s.inScope = s.samePart && inNames.contains(l.Name);
                    comps.get(c).sisters.add(s);
                }
            }
        }
        g.components = comps.values();
        return g;
    }

    // ---------------------------------------------------------------- scope changes

    private static void openForChange(Field_Action__c fa) {
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (fa.Scope__c == FULL) { throw new AuraHandledException('A Full scope covers every lot of the part, so lots are not added or removed by hand.'); }
        if (fa.Scope_Status__c == 'With Committee') { throw new AuraHandledException('The scope is with the committee. Wait for their decision, or ask a member to send it back.'); }
    }

    /** The coordinator adds a lot to a Partial scope, with the reason. A change after approval needs approval again. */
    @AuraEnabled
    public static View addLot(Id recordId, String lot, String reason) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        if (String.isBlank(lot)) { throw new AuraHandledException('Choose a lot.'); }
        if (String.isBlank(reason)) { throw new AuraHandledException('Give the reason for adding lot ' + lot + '.'); }
        List<Field_Action_Lot__c> rows = [SELECT Id, In_Scope__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Lot_Number__c = :lot LIMIT 1];
        if (!rows.isEmpty() && rows[0].In_Scope__c) { throw new AuraHandledException('Lot ' + lot + ' is already in scope.'); }
        if (rows.isEmpty()) {
            LotRow x = lotsOfPart(fa.Part__c, fa.Part__r?.compliancequest__Part_Number__c).get(lot);
            insert new Field_Action_Lot__c(Field_Action__c = recordId, Lot_Number__c = lot, Lot__c = x?.lotId, Units_Built__c = x?.built,
                In_Scope__c = true, Approved_In_Scope__c = false, Added_How__c = 'Coordinator', Reason__c = reason.left(255));
        } else {
            update new Field_Action_Lot__c(Id = rows[0].Id, In_Scope__c = true, Added_How__c = 'Coordinator', Reason__c = reason.left(255));
        }
        List<Field_Action_Scope_Change__c> logs = new List<Field_Action_Scope_Change__c>();
        log(logs, recordId, lot, 'Added', 'Coordinator', reason);
        insert logs;
        afterChange(fa);
        return getView(recordId);
    }

    /** The coordinator removes a lot from a Partial scope, with the reason. The row stays, marked out of scope. */
    @AuraEnabled
    public static View removeLot(Id recordId, String lot, String reason) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        if (String.isBlank(reason)) { throw new AuraHandledException('Give the reason for removing lot ' + lot + '.'); }
        List<Field_Action_Lot__c> rows = [SELECT Id FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Lot_Number__c = :lot AND In_Scope__c = true LIMIT 1];
        if (rows.isEmpty()) { throw new AuraHandledException('Lot ' + lot + ' is not in scope.'); }
        update new Field_Action_Lot__c(Id = rows[0].Id, In_Scope__c = false, Reason__c = reason.left(255));
        List<Field_Action_Scope_Change__c> logs = new List<Field_Action_Scope_Change__c>();
        log(logs, recordId, lot, 'Removed', 'Coordinator', reason);
        insert logs;
        afterChange(fa);
        return getView(recordId);
    }

    private static void afterChange(Field_Action__c fa) {
        syncText(new Set<Id>{ fa.Id });
        if (fa.Scope_Status__c == 'Approved' || fa.Scope_Status__c == null) {
            update new Field_Action__c(Id = fa.Id, Scope_Status__c = 'Being Defined');
        }
    }

    /** Units shipped, on hand and where they are, for one lot in scope. Not a scope change, so no approval is needed. */
    @AuraEnabled
    public static View saveLot(Id recordId, Id rowId, Decimal shipped, Decimal onHand, String location) {
        Field_Action_Lot__c l = [SELECT Id, Field_Action__c FROM Field_Action_Lot__c WHERE Id = :rowId];
        if (l.Field_Action__c != recordId) { throw new AuraHandledException('That lot belongs to another field action.'); }
        if ((shipped != null && shipped < 0) || (onHand != null && onHand < 0)) { throw new AuraHandledException('Units cannot be negative.'); }
        update new Field_Action_Lot__c(Id = rowId, Units_Shipped__c = shipped, Units_On_Hand__c = onHand,
            Location__c = String.isBlank(location) ? null : location.left(255));
        return getView(recordId);
    }

    // ---------------------------------------------------------------- scope approval

    /** A Partial scope goes for approval: to the committee, or in an emergency to one emergency approver. */
    @AuraEnabled
    public static View submitScope(Id recordId, String team, Boolean emergency, String emergencyReason) {
        Field_Action__c fa = load(recordId);
        if (fa.Scope__c != PARTIAL) { throw new AuraHandledException('Only a Partial scope needs approval.'); }
        if (fa.Scope_Status__c == 'With Committee') { throw new AuraHandledException('The scope is already with the committee.'); }
        if (emergency == true && String.isBlank(emergencyReason)) { throw new AuraHandledException('Give the reason for the emergency.'); }
        List<String> inNow = new List<String>(); List<String> added = new List<String>(); List<String> removed = new List<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c, In_Scope__c, Approved_In_Scope__c FROM Field_Action_Lot__c
                                      WHERE Field_Action__c = :recordId ORDER BY Lot_Number__c]) {
            if (l.In_Scope__c) { inNow.add(l.Lot_Number__c); }
            if (l.In_Scope__c && !l.Approved_In_Scope__c) { added.add(l.Lot_Number__c); }
            if (!l.In_Scope__c && l.Approved_In_Scope__c) { removed.add(l.Lot_Number__c); }
        }
        if (inNow.isEmpty()) { throw new AuraHandledException('Put at least one lot in scope.'); }
        if (fa.Scope_Status__c == 'Approved' || (added.isEmpty() && removed.isEmpty())) {
            throw new AuraHandledException('Nothing has changed since the scope was approved.');
        }
        String remark = fa.Name + ' scope (Partial): ' + String.join(inNow, ', ')
            + (fa.Scope_Approved_On__c == null ? '' : '. Changes since approval: '
               + (added.isEmpty() ? '' : 'added ' + String.join(added, ', ')) + (added.isEmpty() || removed.isEmpty() ? '' : '; ')
               + (removed.isEmpty() ? '' : 'removed ' + String.join(removed, ', ')));
        Id made = CqFarCommittee.submitApproval(fa, remark, team, emergency);
        update new Field_Action__c(Id = recordId, Scope_Status__c = 'With Committee', Scope_Approval__c = made,
            Scope_Emergency__c = emergency == true, Scope_Emergency_Reason__c = emergency == true ? emergencyReason : null);
        return getView(recordId);
    }

    /** A member approves or sends back the scope. */
    @AuraEnabled
    public static View act(Id recordId, Id stepId, String action, String comment) {
        CqFarCommittee.decide(recordId, stepId, action, comment);
        return getView(recordId);
    }

    // ---------------------------------------------------------------- when an approval closes

    /**
     * Called by the trigger on CQ Approval, after CqFarCommittee has decided any review.
     *  - A scope approval: approved makes the lots in scope the approved scope; sent back returns it to Being Defined.
     *  - A review decision that starts or joins a field action: the Field Action takes the review's scope if it has none,
     *    and the review's lot comes into scope. A Full scope then fills itself with every lot of the part.
     */
    public static void onClosed(Map<Id, String> statusByApproval) {
        // scope approvals
        List<Field_Action__c> faUps = new List<Field_Action__c>();
        Set<Id> approvedFas = new Set<Id>();
        for (Field_Action__c fa : [SELECT Id, Scope_Approval__c, Scope_Approved_On__c FROM Field_Action__c
                                   WHERE Scope_Approval__c IN :statusByApproval.keySet() AND Scope_Status__c = 'With Committee']) {
            Boolean ok = statusByApproval.get(fa.Scope_Approval__c) == 'Approved';
            // sent back: a scope approved before keeps its last approval date
            faUps.add(new Field_Action__c(Id = fa.Id, Scope_Status__c = ok ? 'Approved' : 'Being Defined', Scope_Approved_On__c = ok ? Datetime.now() : fa.Scope_Approved_On__c));
            if (ok) { approvedFas.add(fa.Id); }
        }
        if (!approvedFas.isEmpty()) {
            List<Field_Action_Lot__c> rows = [SELECT Id, In_Scope__c FROM Field_Action_Lot__c WHERE Field_Action__c IN :approvedFas];
            for (Field_Action_Lot__c l : rows) { l.Approved_In_Scope__c = l.In_Scope__c; }
            update rows;
        }
        if (!faUps.isEmpty()) { update faUps; }

        // review decisions
        List<Field_Action_Review__c> decided = [
            SELECT Id, Name, Scope__c, Committee_Approval__c, Committee_Approval__r.Name, Field_Action__c, Lot_Number__c,
                   Nonconformance__r.compliancequest__Lot_Number__c, Complaint__r.compliancequest__Lot_Number__c
            FROM Field_Action_Review__c WHERE Committee_Approval__c IN :statusByApproval.keySet() AND Status__c = 'Decided'];
        if (decided.isEmpty()) { return; }
        Set<Id> faIds = new Set<Id>(); Set<Id> reviewIds = new Set<Id>();
        for (Field_Action_Review__c r : decided) { reviewIds.add(r.Id); if (r.Field_Action__c != null) { faIds.add(r.Field_Action__c); } }
        delete [SELECT Id FROM Field_Action_Lot__c WHERE Field_Action_Review__c IN :reviewIds AND Field_Action__c = null];   // left from an earlier design
        if (faIds.isEmpty()) { return; }
        Map<Id, Field_Action__c> fas = new Map<Id, Field_Action__c>([
            SELECT Id, Scope__c, Scope_Status__c, Part__c, Part__r.compliancequest__Part_Number__c,
                   (SELECT Id, Lot_Number__c, In_Scope__c FROM Lots_In_Scope__r)
            FROM Field_Action__c WHERE Id IN :faIds]);
        List<Field_Action_Lot__c> adds = new List<Field_Action_Lot__c>(); List<Field_Action_Lot__c> ups = new List<Field_Action_Lot__c>();
        List<Field_Action_Scope_Change__c> logs = new List<Field_Action_Scope_Change__c>();
        Map<Id, Field_Action__c> scopeUps = new Map<Id, Field_Action__c>();
        for (Field_Action_Review__c r : decided) {
            if (statusByApproval.get(r.Committee_Approval__c) != 'Approved' || r.Field_Action__c == null) { continue; }
            Field_Action__c fa = fas.get(r.Field_Action__c);
            String scope = fa.Scope__c;
            if (scope == null && r.Scope__c != null) {
                scope = r.Scope__c;
                scopeUps.put(fa.Id, new Field_Action__c(Id = fa.Id, Scope__c = scope, Scope_Status__c = scope == FULL ? 'Full Scope' : 'Being Defined'));
            }
            String lot = r.Lot_Number__c != null ? r.Lot_Number__c
                : r.Nonconformance__r?.compliancequest__Lot_Number__c != null ? r.Nonconformance__r.compliancequest__Lot_Number__c
                : r.Complaint__r?.compliancequest__Lot_Number__c;
            if (lot == null) { continue; }
            // a lot brought by a review that joins an approved scope was approved by that review's own committee
            Boolean approved = scope == FULL || fa.Scope_Status__c == 'Approved';
            String why = 'The lot on ' + r.Name + ', approved in ' + r.Committee_Approval__r?.Name;
            Field_Action_Lot__c have;
            for (Field_Action_Lot__c l : fa.Lots_In_Scope__r) { if (l.Lot_Number__c == lot) { have = l; } }
            if (have != null && have.In_Scope__c) { continue; }
            if (have != null) {
                ups.add(new Field_Action_Lot__c(Id = have.Id, In_Scope__c = true, Approved_In_Scope__c = approved, Added_How__c = 'Review', Reason__c = why.left(255)));
            } else {
                String partNumber = fa.Part__r?.compliancequest__Part_Number__c;
                List<compliancequest__SQX_Lot_Info__c> info = [
                    SELECT Id, Batch__r.cqext__Quantity__c, Batch__r.cqext__Actual_Yield__c FROM compliancequest__SQX_Lot_Info__c
                    WHERE Name = :lot AND compliancequest__Part_Number__c = :partNumber LIMIT 1];
                Decimal built = info.isEmpty() ? null : info[0].Batch__r?.cqext__Actual_Yield__c != null && info[0].Batch__r.cqext__Actual_Yield__c > 0
                    ? info[0].Batch__r.cqext__Actual_Yield__c : info[0].Batch__r?.cqext__Quantity__c;
                adds.add(new Field_Action_Lot__c(Field_Action__c = fa.Id, Field_Action_Review__c = r.Id, Lot__c = info.isEmpty() ? null : info[0].Id,
                    Lot_Number__c = lot, Units_Built__c = built, In_Scope__c = true, Approved_In_Scope__c = approved, Added_How__c = 'Review', Reason__c = why.left(255)));
            }
            log(logs, fa.Id, lot, 'Added', 'Review', why);
        }
        if (!scopeUps.isEmpty()) { update scopeUps.values(); }
        insert adds; update ups; insert logs;
        sync(faIds);       // a Full scope fills itself
        syncText(faIds);
    }
}
