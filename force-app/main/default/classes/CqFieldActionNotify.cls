/**
 * CqFieldActionNotify: data and actions for the Notifications step of the Field Action workspace (step 4).
 * Customer service works one Case per customer on the list (CqFieldActionCases); this step follows them.
 *  1. Customer notice: the key message confirmed in Strategy, and how many customers it has gone to. Mark Notice Sent
 *     and Log Follow-Up record that on every open Case; nothing is emailed from here.
 *  2. Customers: each one's Case, what we shipped them, what they reported back (entered on the Case, per lot), when
 *     the response is due, and whether they have acknowledged. The coordinator submits the acknowledged customers to
 *     Recovery in batches; a customer who never answers is closed without a response, with a reason, and can be reopened.
 * Who is listed follows How Far It Goes (CqFieldActionDepth): everyone we shipped to, and a distributor's own
 * customers from Hospital depth down.
 */
public with sharing class CqFieldActionNotify {
    public static final String ACK = 'Acknowledged';
    public static final String PENDING = 'Pending Acknowledgment';
    public static final String CLOSED_NO_RESPONSE = 'Closed Without Response';
    public static final String REPORT = 'Field_Action_Cases';   // the report behind the View Cases links, when the org has it

    public class Line {
        @AuraEnabled public String lot; @AuraEnabled public Decimal shipped;
        @AuraEnabled public Decimal used; @AuraEnabled public Decimal returning; @AuraEnabled public Decimal destroyed;
        @AuraEnabled public Decimal unknown;   // shipped less used, returning and destroyed; null until any is recorded
    }
    public class Cust {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String kind;
        @AuraEnabled public Id caseId; @AuraEnabled public String caseNumber;
        @AuraEnabled public Decimal shipped; @AuraEnabled public Decimal returning; @AuraEnabled public Decimal unknown;
        @AuraEnabled public Date due; @AuraEnabled public Date sentOn; @AuraEnabled public Date respondedOn;
        @AuraEnabled public String status;                      // Acknowledged, Pending Acknowledgment, Closed Without Response
        @AuraEnabled public Boolean acked = false; @AuraEnabled public Boolean overdue = false;
        @AuraEnabled public Boolean submitted = false;          // handed to Recovery
        @AuraEnabled public Boolean noResponse = false;         // closed without a response
        @AuraEnabled public String reason; @AuraEnabled public String ackedBy;
        @AuraEnabled public List<Line> lines = new List<Line>();
    }
    public class View {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Boolean closed = false; @AuraEnabled public Boolean strategyConfirmed = false;
        @AuraEnabled public String action; @AuraEnabled public String message; @AuraEnabled public Date sentOn; @AuraEnabled public Date dueOn;
        @AuraEnabled public List<Cust> customers = new List<Cust>();
        @AuraEnabled public Integer total = 0; @AuraEnabled public Integer notified = 0; @AuraEnabled public Integer acked = 0;
        @AuraEnabled public Integer pending = 0; @AuraEnabled public Integer overdue = 0;
        @AuraEnabled public Integer submitted = 0; @AuraEnabled public Integer noResponse = 0;
        @AuraEnabled public Integer toSubmit = 0;               // acknowledged, not yet submitted
        @AuraEnabled public Integer unsent = 0;                 // open Cases with no notice date
        @AuraEnabled public Id reportId;
    }

    private static Field_Action__c load(Id recordId) {
        return [SELECT Id, Name, Status__c, Strategy_Status__c, Action_Type__c, Key_Message__c, Depth__c FROM Field_Action__c WHERE Id = :recordId];
    }
    private static Decimal n(Decimal d) { return d == null ? 0 : d; }

    /** The counts the workspace rail shows: customers listed, notified, acknowledged, and settled (submitted or closed without a response). */
    @AuraEnabled
    public static Map<String, Integer> counts(Id recordId) {
        Integer total = 0, notified = 0, responded = 0, settled = 0;
        for (Field_Action_Customer__c c : [SELECT Status__c, Notice_Sent_On__c, Kind__c, Submitted_On__c, Closed_Without_Response_On__c, Case__c,
                                                  Field_Action__r.Depth__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId]) {
            if (!CqFieldActionDepth.listed(c.Field_Action__r.Depth__c, c.Kind__c)) { continue; }
            total++;
            if (c.Notice_Sent_On__c != null || c.Status__c == ACK) { notified++; }
            if (c.Status__c == ACK) { responded++; }
            if (c.Submitted_On__c != null || c.Closed_Without_Response_On__c != null || (c.Case__c == null && c.Status__c == ACK)) { settled++; }
        }
        return new Map<String, Integer>{ 'total' => total, 'notified' => notified, 'responded' => responded, 'settled' => settled };
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action__c fa = load(recordId);
        View v = new View();
        v.id = fa.Id; v.name = fa.Name; v.closed = fa.Status__c == 'Closed'; v.strategyConfirmed = fa.Strategy_Status__c == 'Confirmed';
        v.action = fa.Action_Type__c; v.message = fa.Key_Message__c;
        if (!v.closed && v.strategyConfirmed) { CqFieldActionCases.sync(recordId); }   // the list, each customer's kind, and a Case for anyone without one
        Date today = Date.today();

        Map<String, Decimal> shipped = CqFieldActionCases.shippedByLine(recordId);
        Map<String, Customer_Response_Line__c> said = new Map<String, Customer_Response_Line__c>();
        for (Customer_Response_Line__c l : [SELECT Field_Action_Customer__c, Lot_Number__c, Units_Used__c, Units_Returning__c, Units_Destroyed__c
                                            FROM Customer_Response_Line__c WHERE Field_Action_Customer__r.Field_Action__c = :recordId]) {
            said.put(l.Field_Action_Customer__c + '|' + l.Lot_Number__c, l);
        }
        for (Field_Action_Customer__c c : [SELECT Id, Customer_Name__c, Kind__c, Lots__c, Status__c, Notice_Sent_On__c, Responded_On__c, Response_Due__c,
                                                  Case__c, Case__r.CaseNumber, Case__r.IsClosed, Submitted_On__c, Closed_Without_Response_On__c,
                                                  No_Response_Reason__c, Acknowledged_By__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId ORDER BY Customer_Name__c]) {
            if (!CqFieldActionDepth.listed(fa.Depth__c, c.Kind__c)) { continue; }
            Cust x = new Cust();
            x.id = c.Id; x.name = c.Customer_Name__c; x.kind = c.Kind__c; x.caseId = c.Case__c; x.caseNumber = c.Case__r?.CaseNumber;
            x.due = c.Response_Due__c; x.sentOn = c.Notice_Sent_On__c; x.respondedOn = c.Responded_On__c;
            x.acked = c.Status__c == ACK; x.noResponse = !x.acked && c.Closed_Without_Response_On__c != null;
            x.submitted = x.acked && (c.Submitted_On__c != null || c.Case__c == null);   // acknowledged before Cases: already with Recovery
            x.reason = c.No_Response_Reason__c; x.ackedBy = c.Acknowledged_By__c;
            x.status = x.acked ? ACK : x.noResponse ? CLOSED_NO_RESPONSE : PENDING;
            x.overdue = !x.acked && !x.noResponse && x.due != null && x.due < today;
            Boolean anySaid = false, anyShipped = false;
            Decimal ship = 0, ret = 0, unk = 0;
            if (String.isNotBlank(c.Lots__c)) {
                for (String s : c.Lots__c.split(',\\s*')) {
                    if (String.isBlank(s)) { continue; }
                    Line l = new Line();
                    l.lot = s.trim(); l.shipped = shipped.get(c.Id + '|' + l.lot);
                    if (l.shipped != null) { anyShipped = true; ship += l.shipped; }
                    Customer_Response_Line__c r = said.get(c.Id + '|' + l.lot);
                    if (r != null && (r.Units_Used__c != null || r.Units_Returning__c != null || r.Units_Destroyed__c != null)) {
                        l.used = r.Units_Used__c; l.returning = r.Units_Returning__c; l.destroyed = r.Units_Destroyed__c;
                        anySaid = true; ret += n(l.returning);
                        if (l.shipped != null) { l.unknown = Math.max(0, l.shipped - n(l.used) - n(l.returning) - n(l.destroyed)); unk += l.unknown; }
                    }
                    x.lines.add(l);
                }
            }
            if (anyShipped) { x.shipped = ship; }
            if (anySaid) { x.returning = ret; if (anyShipped) { x.unknown = unk; } }
            v.customers.add(x); v.total++;
            if (x.sentOn != null || x.acked) { v.notified++; }
            if (x.acked) { v.acked++; if (x.submitted) { v.submitted++; } else { v.toSubmit++; } }
            else if (x.noResponse) { v.noResponse++; }
            else {
                v.pending++;
                if (x.overdue) { v.overdue++; }
                if (x.sentOn == null && c.Case__c != null && !c.Case__r.IsClosed) { v.unsent++; }
                if (x.due != null && (v.dueOn == null || x.due > v.dueOn)) { v.dueOn = x.due; }
            }
            if (x.sentOn != null && (v.sentOn == null || x.sentOn < v.sentOn)) { v.sentOn = x.sentOn; }
        }
        // dynamic: Report is not queryable by every user
        try {
            String devName = REPORT;
            List<SObject> rs = Database.query('SELECT Id FROM Report WHERE DeveloperName = :devName LIMIT 1');
            if (!rs.isEmpty()) { v.reportId = rs[0].Id; }
        } catch (Exception e) { v.reportId = null; }
        return v;
    }

    // ---------------------------------------------------------------- actions (each records on the Cases; CqFieldActionCases)

    /** Mark Notice Sent: today's date on every open Case that has none. */
    @AuraEnabled
    public static View markSent(Id recordId) { CqFieldActionCases.markNoticeSent(recordId); return getView(recordId); }

    /** Log Follow-Up: one more follow-up on every customer still pending, and a completed activity on their Case. */
    @AuraEnabled
    public static View followUp(Id recordId) { CqFieldActionCases.followUp(recordId); return getView(recordId); }

    /** Submit: hands every acknowledged customer not yet submitted to Recovery. */
    @AuraEnabled
    public static View submit(Id recordId) { CqFieldActionCases.submit(recordId); return getView(recordId); }

    /** Close Without Response: the customer never answered; the reason is required and their Case closes as No Response. */
    @AuraEnabled
    public static View closeWithoutResponse(Id recordId, Id customerId, String reason) {
        CqFieldActionCases.closeWithoutResponse(recordId, customerId, reason); return getView(recordId);
    }

    /** Reopen a customer closed without a response: a late reply came in. */
    @AuraEnabled
    public static View reopen(Id recordId, Id customerId) { CqFieldActionCases.reopen(recordId, customerId); return getView(recordId); }
}
