/**
 * CqFieldActionReview: data and saves for the Field Action Review workspace.
 * A review covers one Nonconformance or one Complaint. CQ.AI gathers the records on the same part and lot,
 * scores the field action risk out of 100 and suggests an outcome; the reviewer decides.
 * A review that needs a field action either starts a new Field Action or joins an open one.
 */
public with sharing class CqFieldActionReview {
    public static final Integer REPEAT_DAYS = 90;

    public class Rec {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String kind; @AuraEnabled public String title;
        @AuraEnabled public String status; @AuraEnabled public String lot;
        @AuraEnabled public Boolean sameLot = false; @AuraEnabled public Boolean suggested = false; @AuraEnabled public String why;
    }
    public class Factor {
        @AuraEnabled public String name; @AuraEnabled public String detail; @AuraEnabled public Integer pts; @AuraEnabled public Integer max;
        public Factor(String name, String detail, Integer pts, Integer max) { this.name = name; this.detail = detail; this.pts = pts; this.max = max; }
    }
    public class Fa {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String status;
        @AuraEnabled public String actionType; @AuraEnabled public String lots; @AuraEnabled public Boolean suggested = false; @AuraEnabled public String why;
    }
    /** A signal on this review's part, with the records behind it. Shown in full: the reviewer does not pick. */
    public class Sig {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String rule; @AuraEnabled public String summary;
        @AuraEnabled public String label; @AuraEnabled public String strength; @AuraEnabled public Decimal score; @AuraEnabled public String trend;
        @AuraEnabled public String status; @AuraEnabled public String lot; @AuraEnabled public Datetime firstSeen;
        @AuraEnabled public Boolean thisLot = false; @AuraEnabled public Boolean counts = false;
        @AuraEnabled public String raisedBy;   // set on a signal a person raised by hand
        @AuraEnabled public List<Rec> records = new List<Rec>();
    }
    /** One line of "What We Know": a question, its answer, and where the answer came from. */
    public class Know {
        @AuraEnabled public String q; @AuraEnabled public String a; @AuraEnabled public String src; @AuraEnabled public Boolean unknown;
        public Know(String q, String a, String src) {
            this.q = q; this.src = src;
            this.unknown = String.isBlank(a) || a == 'Not Known';
            this.a = this.unknown ? 'Not known' : a;
        }
    }
    public class View {
        @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String status;
        @AuraEnabled public String reason; @AuraEnabled public String requestedBy; @AuraEnabled public Datetime requestedOn;
        @AuraEnabled public String reviewer; @AuraEnabled public Date due;
        @AuraEnabled public String sourceKind; @AuraEnabled public Id sourceId; @AuraEnabled public String sourceName; @AuraEnabled public String sourceTitle;
        @AuraEnabled public String problem;
        @AuraEnabled public Id partId; @AuraEnabled public String partName; @AuraEnabled public String lot;
        @AuraEnabled public Decimal qtyAffected; @AuraEnabled public Decimal qtyShipped;
        @AuraEnabled public String riskLevel; @AuraEnabled public String hazard;
        @AuraEnabled public String outcome; @AuraEnabled public String rationale; @AuraEnabled public String decidedBy; @AuraEnabled public Datetime decidedOn;
        @AuraEnabled public Id faId; @AuraEnabled public String faName; @AuraEnabled public String summary;
        @AuraEnabled public List<Rec> records = new List<Rec>();
        @AuraEnabled public List<Factor> factors = new List<Factor>();
        @AuraEnabled public Integer score = 0; @AuraEnabled public String band;
        @AuraEnabled public Boolean reachedField = false;
        @AuraEnabled public String suggestedOutcome; @AuraEnabled public String suggestedWhy;
        @AuraEnabled public List<Fa> fieldActions = new List<Fa>();
        @AuraEnabled public List<Know> know = new List<Know>();
        @AuraEnabled public List<Sig> signals = new List<Sig>();        // Assess or Escalate, not dismissed
        @AuraEnabled public List<Sig> moreSignals = new List<Sig>();    // Watch, or dismissed earlier
        @AuraEnabled public String draft;
    }

    public static String band(Integer score) { return score >= 70 ? 'High' : score >= 40 ? 'Medium' : 'Low'; }

    private static Field_Action_Review__c load(Id recordId) {
        return [SELECT Id, Name, Title__c, Status__c, Reason_for_Review__c, Requested_By__r.Name, Requested_On__c, Reviewer__c, Reviewer__r.Name, Due_Date__c,
                       Part__c, Part__r.Name, Part__r.compliancequest__Part_Number__c, Lot_Number__c, Quantity_Affected__c, Quantity_Shipped__c,
                       Risk_Level__c, Health_Hazard_Summary__c, Outcome__c, Outcome_Rationale__c, Decided_By__r.Name, Decided_On__c,
                       Field_Action__c, Field_Action__r.Name, Review_Summary__c, Review_Draft__c,
                       Nonconformance__c, Nonconformance__r.Name, Nonconformance__r.compliancequest__NC_Title__c, Nonconformance__r.compliancequest__Description__c,
                       Nonconformance__r.compliancequest__Description_RT__c,
                       Nonconformance__r.compliancequest__Lot_Number__c, Nonconformance__r.compliancequest__SQX_Part__c, Nonconformance__r.Triage_Risk__c,
                       Nonconformance__r.compliancequest__SQX_Part__r.Name, Nonconformance__r.compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                       Complaint__c, Complaint__r.Name, Complaint__r.compliancequest__Complaint_Title__c, Complaint__r.compliancequest__Description__c,
                       Complaint__r.compliancequest__Lot_Number__c, Complaint__r.compliancequest__SQX_Part__c,
                       Complaint__r.compliancequest__SQX_Part__r.Name, Complaint__r.compliancequest__SQX_Part__r.compliancequest__Part_Number__c
                FROM Field_Action_Review__c WHERE Id = :recordId];
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action_Review__c r = load(recordId);
        View v = new View();
        v.name = r.Name; v.title = r.Title__c; v.status = r.Status__c; v.reason = r.Reason_for_Review__c;
        v.requestedBy = r.Requested_By__r?.Name; v.requestedOn = r.Requested_On__c; v.reviewer = r.Reviewer__r?.Name; v.due = r.Due_Date__c;
        v.qtyAffected = r.Quantity_Affected__c; v.qtyShipped = r.Quantity_Shipped__c;
        v.riskLevel = r.Risk_Level__c; v.hazard = r.Health_Hazard_Summary__c;
        v.outcome = r.Outcome__c; v.rationale = r.Outcome_Rationale__c; v.decidedBy = r.Decided_By__r?.Name; v.decidedOn = r.Decided_On__c;
        v.faId = r.Field_Action__c; v.faName = r.Field_Action__r?.Name; v.summary = r.Review_Summary__c; v.draft = r.Review_Draft__c;

        Id partId = r.Part__c; String partName = r.Part__r?.compliancequest__Part_Number__c != null ? r.Part__r.compliancequest__Part_Number__c : r.Part__r?.Name;
        String lot = r.Lot_Number__c; String sourceRisk;
        if (r.Nonconformance__c != null) {
            v.sourceKind = 'Nonconformance'; v.sourceId = r.Nonconformance__c; v.sourceName = r.Nonconformance__r.Name;
            v.sourceTitle = r.Nonconformance__r.compliancequest__NC_Title__c; v.problem = CqRichText.toText(r.Nonconformance__r.compliancequest__Description_RT__c, r.Nonconformance__r.compliancequest__Description__c);
            sourceRisk = r.Nonconformance__r.Triage_Risk__c;
            if (lot == null) { lot = r.Nonconformance__r.compliancequest__Lot_Number__c; }
            if (partId == null) {
                partId = r.Nonconformance__r.compliancequest__SQX_Part__c;
                compliancequest__SQX_Part__c p = r.Nonconformance__r.compliancequest__SQX_Part__r;
                partName = p == null ? null : p.compliancequest__Part_Number__c != null ? p.compliancequest__Part_Number__c : p.Name;
            }
        } else if (r.Complaint__c != null) {
            v.sourceKind = 'Complaint'; v.sourceId = r.Complaint__c; v.sourceName = r.Complaint__r.Name;
            v.sourceTitle = r.Complaint__r.compliancequest__Complaint_Title__c; v.problem = CqRichText.toText(null, r.Complaint__r.compliancequest__Description__c);
            if (lot == null) { lot = r.Complaint__r.compliancequest__Lot_Number__c; }
            if (partId == null) {
                partId = r.Complaint__r.compliancequest__SQX_Part__c;
                compliancequest__SQX_Part__c p = r.Complaint__r.compliancequest__SQX_Part__r;
                partName = p == null ? null : p.compliancequest__Part_Number__c != null ? p.compliancequest__Part_Number__c : p.Name;
            }
        }
        v.partId = partId; v.partName = partName; v.lot = lot;

        // Signals and evidence: other records on the same part
        Integer lotNcs = 0; Integer lotComplaints = 0; Integer recentNcs = 0;
        if (partId != null) {
            Datetime since = Datetime.now().addDays(-REPEAT_DAYS);
            List<Rec> same = new List<Rec>(); List<Rec> rest = new List<Rec>();
            for (compliancequest__SQX_Complaint__c c : [
                    SELECT Id, Name, compliancequest__Complaint_Title__c, compliancequest__Status__c, compliancequest__Lot_Number__c
                    FROM compliancequest__SQX_Complaint__c WHERE compliancequest__SQX_Part__c = :partId AND Id != :r.Complaint__c
                    ORDER BY CreatedDate DESC LIMIT 40]) {
                Rec x = new Rec(); x.id = c.Id; x.name = c.Name; x.kind = 'Complaint'; x.title = c.compliancequest__Complaint_Title__c;
                x.status = c.compliancequest__Status__c; x.lot = c.compliancequest__Lot_Number__c;
                x.sameLot = lot != null && x.lot == lot;
                if (x.sameLot) { lotComplaints++; x.suggested = true; x.why = 'Same lot'; same.add(x); } else { x.why = 'Same part'; rest.add(x); }
            }
            for (compliancequest__SQX_Nonconformance__c n : [
                    SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Status__c, compliancequest__Lot_Number__c, CreatedDate
                    FROM compliancequest__SQX_Nonconformance__c WHERE compliancequest__SQX_Part__c = :partId AND Id != :r.Nonconformance__c
                    ORDER BY CreatedDate DESC LIMIT 40]) {
                Rec x = new Rec(); x.id = n.Id; x.name = n.Name; x.kind = 'Nonconformance'; x.title = n.compliancequest__NC_Title__c;
                x.status = n.compliancequest__Status__c; x.lot = n.compliancequest__Lot_Number__c;
                x.sameLot = lot != null && x.lot == lot;
                if (n.CreatedDate >= since) { recentNcs++; }
                if (x.sameLot) { lotNcs++; x.suggested = true; x.why = 'Same lot'; same.add(x); } else { x.why = 'Same part'; rest.add(x); }
            }
            v.records.addAll(same); v.records.addAll(rest);

            for (Field_Action__c f : [SELECT Id, Name, Title__c, Status__c, Action_Type__c, Lot_Numbers__c FROM Field_Action__c
                                      WHERE Part__c = :partId AND Status__c != 'Closed' ORDER BY CreatedDate DESC LIMIT 20]) {
                Fa x = new Fa(); x.id = f.Id; x.name = f.Name; x.title = f.Title__c; x.status = f.Status__c; x.actionType = f.Action_Type__c; x.lots = f.Lot_Numbers__c;
                x.suggested = lot != null && f.Lot_Numbers__c != null && f.Lot_Numbers__c.containsIgnoreCase(lot);
                x.why = x.suggested ? 'Already covers lot ' + lot : 'Same part, different lots';
                v.fieldActions.add(x);
            }
        }

        // Field action risk score out of 100. Each factor is a simple rule over the data above.
        Boolean isComplaint = v.sourceKind == 'Complaint';
        Boolean shipped = v.qtyShipped != null && v.qtyShipped > 0;
        v.reachedField = isComplaint || lotComplaints > 0 || shipped;
        Integer reach = isComplaint || lotComplaints > 0 ? 30 : shipped ? 20 : 0;
        v.factors.add(new Factor('Reached the field',
            isComplaint ? 'This review came from a complaint, so the product was with a customer'
                : lotComplaints > 0 ? lotComplaints + ' complaint(s) on the same lot'
                : shipped ? v.qtyShipped.format() + ' units recorded as shipped' : 'No complaint on the lot and nothing recorded as shipped', reach, 30));

        String sev = sourceRisk != null ? sourceRisk : r.Risk_Level__c;
        Integer sevPts = sev == 'High' ? 25 : sev == 'Medium' ? 15 : sev == 'Low' ? 5 : 10;
        v.factors.add(new Factor('Severity',
            sourceRisk != null ? 'Risk set to ' + sourceRisk + ' at triage of ' + v.sourceName : r.Risk_Level__c != null ? 'Risk Level on this review is ' + r.Risk_Level__c : 'No risk recorded yet, so a middle value is assumed',
            sevPts, 25));

        // Signals: is the problem repeating or spreading? Worth 35, from the strongest signal on this lot or part.
        Sig top = loadSignals(v, partId, lot);
        v.factors.add(new Factor('Signals',
            top == null ? 'No signals on this lot or part' : top.rule + ' at ' + top.strength + ': ' + top.label,
            top == null || top.score == null ? 0 : (35 * top.score).round(System.RoundingMode.HALF_UP).intValue(), 35));
        Decimal q = v.qtyAffected;
        v.factors.add(new Factor('Quantity affected',
            q == null ? 'Not recorded' : q.format() + ' units', q == null ? 0 : q >= 100 ? 10 : q >= 10 ? 5 : q > 0 ? 2 : 0, 10));
        for (Factor f : v.factors) { v.score += f.pts; }
        v.band = band(v.score);

        if (v.score >= 70 || (v.reachedField && v.score >= 40)) {
            v.suggestedOutcome = 'Field Action Needed';
            v.suggestedWhy = 'Score ' + v.score + ' of 100' + (v.reachedField ? ' and the product has reached the field.' : '.');
        } else {
            v.suggestedOutcome = 'No Field Action';
            v.suggestedWhy = 'Score ' + v.score + ' of 100' + (v.reachedField ? '.' : ' and nothing shows the product reached the field.');
        }

        // What We Know: the questions a coordinator needs answered, each with its source. Unknowns are shown, not hidden.
        Quality_Event__c ev;
        if (v.sourceId != null) {
            List<Quality_Event__c> evs = [
                SELECT Name, Where_Found__c, Injury__c, Safety_Risk__c, Aware_Date__c FROM Quality_Event__c
                WHERE (Nonconformance__c != null AND Nonconformance__c = :r.Nonconformance__c) OR (Complaint__c != null AND Complaint__c = :r.Complaint__c)
                ORDER BY CreatedDate LIMIT 1];
            if (!evs.isEmpty()) { ev = evs[0]; }
        }
        String evSrc = ev == null ? 'No event recorded' : 'Reported at intake, ' + ev.Name;
        String contained; String containedSrc = 'Not tracked for complaints';
        if (r.Nonconformance__c != null) {
            Integer total = 0; Integer stillOpen = 0;
            for (compliancequest__SQX_Containment__c c : [
                    SELECT compliancequest__Is_Complete__c FROM compliancequest__SQX_Containment__c
                    WHERE compliancequest__SQX_Nonconformance__c = :r.Nonconformance__c AND compliancequest__Status__c != 'Void' LIMIT 50]) {
                total++; if (c.compliancequest__Is_Complete__c != true) { stillOpen++; }
            }
            contained = total == 0 ? 'No, none recorded' : stillOpen == 0 ? 'Yes, containment complete' : 'In progress, ' + stillOpen + ' not yet complete';
            containedSrc = 'Containment records on ' + v.sourceName;
        }
        // Order: the three that carry most weight in a field action decision first, then the rest.
        v.know.add(new Know('Was anyone injured?', ev?.Injury__c, evSrc));
        v.know.add(new Know('Is there a safety risk?', ev?.Safety_Risk__c, evSrc));
        v.know.add(new Know('Has product shipped?',
            v.qtyShipped == null ? null : shipped ? 'Yes, ' + v.qtyShipped.format() + ' units' : 'No, none recorded',
            v.qtyShipped == null ? 'No shipment data connected' : 'Quantity Shipped on this review'));
        v.know.add(new Know('Are there complaints on this lot?', lot == null ? null : lotComplaints == 0 ? 'None' : String.valueOf(lotComplaints),
            lot == null ? 'No lot recorded' : 'Complaints in CQ on lot ' + lot));
        v.know.add(new Know('Is the lot contained?', contained, containedSrc));
        v.know.add(new Know('Where was it found?', ev?.Where_Found__c, evSrc));
        v.know.add(new Know('What did triage set the risk at?', sourceRisk,
            sourceRisk != null ? 'NC triage of ' + v.sourceName : isComplaint ? 'Complaints are not triaged here' : 'Not triaged yet'));
        v.know.add(new Know('When did we become aware?', ev?.Aware_Date__c == null ? null : ev.Aware_Date__c.format('MMM d, yyyy h:mm a'), evSrc));
        return v;
    }

    /** Fills the signals on this part, strongest first, and returns the strongest one that counts toward the score. */
    private static Sig loadSignals(View v, Id partId, String lot) {
        Sig top;
        if (partId == null) { return top; }
        List<Sig> here = new List<Sig>(); List<Sig> elsewhere = new List<Sig>();
        for (Signal__c s : [
                SELECT Id, Name, Rule__r.Name, Rule__r.Code__c, Summary__c, Value_Label__c, Strength__c, Score__c, Trend__c, Status__c,
                       Lot_Number__c, First_Seen__c, Rule__c, CreatedBy.Name, CreatedDate,
                       (SELECT Complaint__c, Complaint__r.Name, Complaint__r.compliancequest__Complaint_Title__c,
                               Complaint__r.compliancequest__Status__c, Complaint__r.compliancequest__Lot_Number__c,
                               Nonconformance__c, Nonconformance__r.Name, Nonconformance__r.compliancequest__NC_Title__c,
                               Nonconformance__r.compliancequest__Status__c, Nonconformance__r.compliancequest__Lot_Number__c,
                               Field_Action_Review__c, Field_Action_Review__r.Name, Field_Action_Review__r.Title__c,
                               Field_Action_Review__r.Status__c, Field_Action_Review__r.Lot_Number__c
                        FROM Signal_Events__r WHERE Removed__c = false ORDER BY Record_Number__c LIMIT 200)
                FROM Signal__c WHERE Part__c = :partId AND Status__c != 'Closed'
                ORDER BY Score__c DESC NULLS LAST, First_Seen__c LIMIT 50]) {
            Sig g = new Sig();
            Boolean manual = s.Rule__c == null;
            g.id = s.Id; g.name = s.Name; g.rule = manual ? 'Manual' : s.Rule__r.Name; g.summary = s.Summary__c;
            g.label = s.Value_Label__c != null ? s.Value_Label__c : s.Summary__c;
            g.strength = s.Strength__c == null ? 'Watch' : s.Strength__c; g.trend = s.Trend__c; g.status = s.Status__c; g.lot = s.Lot_Number__c;
            g.score = s.Score__c != null ? s.Score__c : g.strength == 'Escalate' ? 1 : g.strength == 'Assess' ? 0.60 : 0.20;
            g.firstSeen = s.First_Seen__c != null ? s.First_Seen__c : s.CreatedDate;
            if (manual) { g.raisedBy = s.CreatedBy.Name; }
            List<Rec> same = new List<Rec>(); List<Rec> rest = new List<Rec>();
            for (Signal_Event__c e : s.Signal_Events__r) {
                Rec x = new Rec();
                if (e.Complaint__c != null) {
                    x.id = e.Complaint__c; x.kind = 'Complaint'; x.name = e.Complaint__r.Name; x.title = e.Complaint__r.compliancequest__Complaint_Title__c;
                    x.status = e.Complaint__r.compliancequest__Status__c; x.lot = e.Complaint__r.compliancequest__Lot_Number__c;
                } else if (e.Nonconformance__c != null) {
                    x.id = e.Nonconformance__c; x.kind = 'Nonconformance'; x.name = e.Nonconformance__r.Name; x.title = e.Nonconformance__r.compliancequest__NC_Title__c;
                    x.status = e.Nonconformance__r.compliancequest__Status__c; x.lot = e.Nonconformance__r.compliancequest__Lot_Number__c;
                } else if (e.Field_Action_Review__c != null) {
                    x.id = e.Field_Action_Review__c; x.kind = 'Field Action Review'; x.name = e.Field_Action_Review__r.Name; x.title = e.Field_Action_Review__r.Title__c;
                    x.status = e.Field_Action_Review__r.Status__c; x.lot = e.Field_Action_Review__r.Lot_Number__c;
                } else { continue; }
                x.sameLot = lot != null && x.lot == lot;
                if (x.sameLot) { g.thisLot = true; same.add(x); } else { rest.add(x); }
            }
            g.records.addAll(same); g.records.addAll(rest);
            if (lot != null && g.lot == lot) { g.thisLot = true; }
            // counts toward the score when it is about the part as a whole, or touches this review's lot
            Boolean dismissed = g.status == 'Dismissed';
            g.counts = !dismissed && (g.thisLot || g.lot == null);
            if (g.counts && (top == null || (g.score != null && (top.score == null || g.score > top.score)))) { top = g; }
            if (dismissed || g.strength == 'Watch') { v.moreSignals.add(g); }
            else if (g.thisLot) { here.add(g); } else { elsewhere.add(g); }
        }
        v.signals.addAll(here); v.signals.addAll(elsewhere);
        return top;
    }

    @AuraEnabled
    public static void saveDraft(Id recordId, String draft) {
        Field_Action_Review__c r = [SELECT Status__c FROM Field_Action_Review__c WHERE Id = :recordId];
        r.Review_Draft__c = String.isBlank(draft) ? null : draft.left(20000);
        if (r.Status__c == 'New' && r.Review_Draft__c != null) { r.Status__c = 'In Review'; }
        update r;
    }

    @AuraEnabled
    public static View reopen(Id recordId) {
        update new Field_Action_Review__c(Id = recordId, Status__c = 'In Review');
        return getView(recordId);
    }

    @AuraEnabled
    public static View submit(Id recordId, String hazard, String summary, Integer score, String riskLevel, String outcome, String rationale,
                              Id fieldActionId, String faTitle, String actionType, String recallClass) {
        if (outcome != 'No Field Action' && outcome != 'Field Action Needed') { throw new AuraHandledException('Choose an outcome.'); }
        if (String.isBlank(rationale)) { throw new AuraHandledException('A rationale is required.'); }
        View v = getView(recordId);
        Field_Action_Review__c r = new Field_Action_Review__c(Id = recordId);
        r.Health_Hazard_Summary__c = hazard; r.Review_Summary__c = summary; r.Risk_Score__c = score; r.Risk_Level__c = riskLevel;
        r.Outcome__c = outcome; r.Outcome_Rationale__c = rationale;
        r.Decided_By__c = UserInfo.getUserId(); r.Decided_On__c = Datetime.now();
        r.Status__c = 'Decided'; r.Review_Draft__c = null;
        if ([SELECT Reviewer__c FROM Field_Action_Review__c WHERE Id = :recordId].Reviewer__c == null) { r.Reviewer__c = UserInfo.getUserId(); }

        if (outcome == 'Field Action Needed') {
            if (fieldActionId != null) {
                Field_Action__c f = [SELECT Id, Lot_Numbers__c FROM Field_Action__c WHERE Id = :fieldActionId];
                if (v.lot != null && (f.Lot_Numbers__c == null || !f.Lot_Numbers__c.containsIgnoreCase(v.lot))) {
                    f.Lot_Numbers__c = ((f.Lot_Numbers__c == null ? '' : f.Lot_Numbers__c + ', ') + v.lot).left(255);
                    update f;
                }
                r.Field_Action__c = fieldActionId;
            } else {
                if (String.isBlank(actionType)) { throw new AuraHandledException('Choose the type of field action.'); }
                Field_Action__c f = new Field_Action__c(
                    Title__c = String.isBlank(faTitle) ? v.title : faTitle.left(255), Status__c = 'New', Action_Type__c = actionType,
                    Recall_Class__c = String.isBlank(recallClass) ? null : recallClass,
                    Description__c = v.problem == null ? v.reason : v.problem.left(10000),
                    Part__c = v.partId, Lot_Numbers__c = v.lot, Quantity_Affected__c = v.qtyAffected, Quantity_Shipped__c = v.qtyShipped,
                    Decision_Rationale__c = rationale, Decided_By__c = UserInfo.getUserId(), Decided_On__c = Datetime.now());
                insert f;
                r.Field_Action__c = f.Id;
            }
        } else {
            r.Field_Action__c = null;
        }
        update r;
        return getView(recordId);
    }
}
