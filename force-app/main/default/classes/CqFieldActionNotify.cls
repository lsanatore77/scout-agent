/**
 * CqFieldActionNotify: data and saves for the Notifications step of the Field Action workspace (step 4).
 *  1. Customer notice: the key message confirmed in Strategy, and when the notice went to each customer
 *     (Field Action Customer . Notice Sent On). Mark Sent records today for the customers not yet notified.
 *  2. Customer responses: what each customer reported on its response form, per lot it received (Customer Response
 *     Line: units used, returning, destroyed). Unknown is the units shipped less those three. Recording the response marks
 *     the customer Acknowledged; Recovery expects back the units returning.
 * The Send notice and Collect response tasks (CqFieldActionTasks) show here: completing a notice task records the date
 * sent, completing a response task records the response. CQ.AI suggests the ones still missing (not for a customer
 * already notified, or already responded); the coordinator reviews and creates them here.
 * Who is listed follows How Far It Goes (CqFieldActionDepth): at distributor level, only the distributors.
 */
public with sharing class CqFieldActionNotify {
    public static final String ACK = 'Acknowledged';
    public static final String SENT = 'Sent';
    public static final String NO_REPLY = 'No reply';

    public class Line {
        @AuraEnabled public Id id; @AuraEnabled public String lot; @AuraEnabled public Decimal shipped;
        @AuraEnabled public Decimal used; @AuraEnabled public Decimal returning; @AuraEnabled public Decimal destroyed;
        @AuraEnabled public Decimal unknown;   // shipped less used, returning and destroyed; null until any is recorded
    }
    public class Step {
        @AuraEnabled public Id id; @AuraEnabled public String subject; @AuraEnabled public String type; @AuraEnabled public Boolean done = false;
        @AuraEnabled public Date due; @AuraEnabled public String owner; @AuraEnabled public Boolean overdue = false;
    }
    public class Cust {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String status; @AuraEnabled public Decimal units;
        @AuraEnabled public String type;   // Customer Type on the Account: Distributor, Hospital, Clinic
        @AuraEnabled public Date sentOn; @AuraEnabled public Date respondedOn; @AuraEnabled public Boolean overdue = false;
        @AuraEnabled public List<Line> lines = new List<Line>();
        @AuraEnabled public List<Step> tasks = new List<Step>();
    }
    public class View {
        @AuraEnabled public Id id; @AuraEnabled public Boolean closed = false; @AuraEnabled public Boolean strategyConfirmed = false;
        @AuraEnabled public String action; @AuraEnabled public String message; @AuraEnabled public Date sentOn; @AuraEnabled public Date dueOn;
        @AuraEnabled public List<Cust> customers = new List<Cust>();
        @AuraEnabled public Integer total = 0; @AuraEnabled public Integer notified = 0; @AuraEnabled public Integer responded = 0;
        @AuraEnabled public Integer waiting = 0; @AuraEnabled public Integer overdue = 0;
        @AuraEnabled public String aiLine;
        @AuraEnabled public List<CqFieldActionTasks.Suggestion> suggestions = new List<CqFieldActionTasks.Suggestion>();
        @AuraEnabled public String suggestLine;
        @AuraEnabled public String depth; @AuraEnabled public String leftOut;   // who How Far It Goes leaves out (CQ.AI)
    }

    private static Field_Action__c load(Id recordId) {
        return [SELECT Id, Status__c, Strategy_Status__c, Action_Type__c, Key_Message__c, Check_By__c, Check_Level__c, Depth__c FROM Field_Action__c WHERE Id = :recordId];
    }
    private static void openForChange(Field_Action__c fa) {
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (fa.Strategy_Status__c != 'Confirmed') { throw new AuraHandledException('Confirm the strategy first.'); }
    }
    private static Decimal n(Decimal d) { return d == null ? 0 : d; }

    /** The counts the workspace rail shows: customers, notified and responded. */
    @AuraEnabled
    public static Map<String, Integer> counts(Id recordId) {
        Integer total = 0, notified = 0, responded = 0;
        for (Field_Action_Customer__c c : [SELECT Status__c, Notice_Sent_On__c, Customer__c, Customer__r.Customer_Type__c, Field_Action__r.Depth__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId]) {
            if (!CqFieldActionDepth.includes(c.Field_Action__r.Depth__c, c.Customer__r?.Customer_Type__c, c.Customer__c)) { continue; }
            total++;
            if (c.Notice_Sent_On__c != null || c.Status__c == ACK) { notified++; }
            if (c.Status__c == ACK) { responded++; }
        }
        return new Map<String, Integer>{ 'total' => total, 'notified' => notified, 'responded' => responded };
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action__c fa = load(recordId);
        View v = new View();
        v.id = fa.Id; v.closed = fa.Status__c == 'Closed'; v.strategyConfirmed = fa.Strategy_Status__c == 'Confirmed';
        v.action = fa.Action_Type__c; v.message = fa.Key_Message__c; v.depth = fa.Depth__c;
        if (!v.closed && v.strategyConfirmed) {
            CqFieldActionRecovery.syncCustomers(recordId);   // the customers that received the lots in scope, from the lot shipments
            CqFieldActionTasks.sync(recordId);               // a response task done elsewhere marks the customer
        }
        Date today = Date.today();

        // who How Far It Goes reaches: at distributor level, hospitals and clinics that bought direct are left out
        List<Field_Action_Customer__c> custs = new List<Field_Action_Customer__c>();
        Map<String, Integer> outByType = new Map<String, Integer>();
        Integer untyped = 0;
        for (Field_Action_Customer__c c : [SELECT Id, Customer__c, Customer__r.Customer_Type__c, Customer_Name__c, Units__c, Lots__c, Status__c,
                                                  Notice_Sent_On__c, Responded_On__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId ORDER BY Customer_Name__c]) {
            String t = c.Customer__r?.Customer_Type__c;
            if (!CqFieldActionDepth.includes(fa.Depth__c, t, c.Customer__c)) { outByType.put(t, (outByType.containsKey(t) ? outByType.get(t) : 0) + 1); continue; }
            if (CqFieldActionDepth.untyped(fa.Depth__c, t, c.Customer__c)) { untyped++; }
            custs.add(c);
        }
        if (fa.Depth__c != null) { v.leftOut = CqFieldActionDepth.leftOutLine(fa.Depth__c, outByType, untyped); }
        // what each customer received, from the lot shipments of the lots in scope
        Set<String> lots = new Set<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true]) {
            lots.add(l.Lot_Number__c);
        }
        Map<Id, Id> custByAccount = new Map<Id, Id>();
        for (Field_Action_Customer__c c : custs) { if (c.Customer__c != null) { custByAccount.put(c.Customer__c, c.Id); } }
        Map<String, Decimal> shipped = new Map<String, Decimal>();   // customerId|lot -> units
        if (!lots.isEmpty() && !custByAccount.isEmpty()) {
            for (AggregateResult r : [SELECT Customer__c acc, Lot_Number__c lot, SUM(Units__c) units FROM Lot_Shipment__c
                                      WHERE Lot_Number__c IN :lots AND Customer__c IN :custByAccount.keySet() GROUP BY Customer__c, Lot_Number__c]) {
                shipped.put(custByAccount.get((Id) r.get('acc')) + '|' + (String) r.get('lot'), (Decimal) r.get('units'));
            }
        }
        Map<String, Customer_Response_Line__c> said = new Map<String, Customer_Response_Line__c>();
        for (Customer_Response_Line__c l : [SELECT Id, Field_Action_Customer__c, Lot_Number__c, Units_Used__c, Units_Returning__c, Units_Destroyed__c
                                            FROM Customer_Response_Line__c WHERE Field_Action_Customer__r.Field_Action__c = :recordId]) {
            said.put(l.Field_Action_Customer__c + '|' + l.Lot_Number__c, l);
        }
        Map<Id, List<Step>> stepsOf = new Map<Id, List<Step>>();
        for (Task t : [SELECT Id, Subject, Recall_Task_Type__c, IsClosed, ActivityDate, Owner.Name, Field_Action_Customer__c FROM Task
                       WHERE WhatId = :recordId AND Recall_Task_Type__c IN (:CqFieldActionTasks.NOTICE, :CqFieldActionTasks.RESPONSE)
                       ORDER BY ActivityDate NULLS LAST, CreatedDate]) {
            Step s = new Step();
            s.id = t.Id; s.subject = t.Subject; s.type = t.Recall_Task_Type__c; s.done = t.IsClosed; s.due = t.ActivityDate; s.owner = t.Owner?.Name;
            s.overdue = !s.done && s.due != null && s.due < today;
            if (t.Recall_Task_Type__c == CqFieldActionTasks.RESPONSE && t.ActivityDate != null && (v.dueOn == null || t.ActivityDate > v.dueOn)) { v.dueOn = t.ActivityDate; }
            if (!stepsOf.containsKey(t.Field_Action_Customer__c)) { stepsOf.put(t.Field_Action_Customer__c, new List<Step>()); }
            stepsOf.get(t.Field_Action_Customer__c).add(s);
        }

        List<String> waitingNames = new List<String>();
        for (Field_Action_Customer__c c : custs) {
            Cust x = new Cust();
            x.id = c.Id; x.name = c.Customer_Name__c; x.units = c.Units__c; x.status = c.Status__c == null ? SENT : c.Status__c;
            x.type = c.Customer__r?.Customer_Type__c;
            x.sentOn = c.Notice_Sent_On__c; x.respondedOn = c.Responded_On__c;
            List<String> ls = new List<String>();
            if (String.isNotBlank(c.Lots__c)) { for (String s : c.Lots__c.split(',\\s*')) { if (String.isNotBlank(s)) { ls.add(s.trim()); } } }
            for (String lot : ls) {
                Line l = new Line();
                l.lot = lot; l.shipped = shipped.get(c.Id + '|' + lot);
                Customer_Response_Line__c r = said.get(c.Id + '|' + lot);
                if (r != null) {
                    l.id = r.Id; l.used = r.Units_Used__c; l.returning = r.Units_Returning__c; l.destroyed = r.Units_Destroyed__c;
                    if (l.shipped != null && (l.used != null || l.returning != null || l.destroyed != null)) {
                        l.unknown = Math.max(0, l.shipped - n(l.used) - n(l.returning) - n(l.destroyed));
                    }
                }
                x.lines.add(l);
            }
            if (stepsOf.containsKey(c.Id)) { x.tasks = stepsOf.get(c.Id); }
            for (Step s : x.tasks) { if (s.type == CqFieldActionTasks.RESPONSE && s.overdue) { x.overdue = true; } }
            if (x.sentOn == null) { for (Step s : x.tasks) { if (s.type == CqFieldActionTasks.NOTICE && s.done) { x.sentOn = today; } } }
            v.customers.add(x); v.total++;
            Boolean acked = x.status == ACK;
            if (x.sentOn != null || acked) { v.notified++; }
            if (acked) { v.responded++; }
            else if (x.sentOn != null) {
                v.waiting++; waitingNames.add(x.name);
                if (x.overdue || x.status == NO_REPLY) { v.overdue++; }
            }
            if (x.sentOn != null && (v.sentOn == null || x.sentOn < v.sentOn)) { v.sentOn = x.sentOn; }
        }

        // CQ.AI: who to chase, and when
        if (!v.closed && v.strategyConfirmed) {
            if (v.total > 0 && v.notified < v.total) {
                Integer left = v.total - v.notified;
                v.aiLine = left + ' customer' + (left == 1 ? ' has' : 's have') + ' not been sent the notice yet. Mark it sent once it goes out.';
            } else if (!waitingNames.isEmpty()) {
                String names = waitingNames.size() <= 2 ? String.join(waitingNames, ' and ') : waitingNames.size() + ' customers';
                v.aiLine = names + (waitingNames.size() == 1 ? ' hasn\'t' : ' haven\'t') + ' replied. '
                    + (v.dueOn != null && v.dueOn > today.addDays(3) ? 'Send a follow-up 3 days before the ' + v.dueOn.format() + ' due date.'
                       : 'Follow up now: the response is due' + (v.dueOn == null ? '.' : ' ' + v.dueOn.format() + '.'));
            }
            suggest(v, fa);
        }
        return v;
    }

    /** CQ.AI's notice and response tasks still missing, leaving out a notice already sent and a response already in. */
    private static void suggest(View v, Field_Action__c fa) {
        Map<Id, Cust> byId = new Map<Id, Cust>();
        for (Cust c : v.customers) { byId.put(c.id, c); }
        Integer notices = 0, responses = 0;
        for (CqFieldActionTasks.Suggestion s : CqFieldActionTasks.board(fa.Id, fa, false).suggestions) {
            Cust c = byId.get(s.customerId);
            if (c == null) { continue; }
            if (s.type == CqFieldActionTasks.NOTICE && c.sentOn == null && c.status != ACK) { v.suggestions.add(s); notices++; }
            if (s.type == CqFieldActionTasks.RESPONSE && c.status != ACK) { v.suggestions.add(s); responses++; }
        }
        if (v.suggestions.isEmpty()) { return; }
        String word = fa.Action_Type__c == CqFieldActionStrategy.WITHDRAWAL ? 'withdrawal notice' : 'recall notice';
        List<String> parts = new List<String>();
        if (notices > 0) { parts.add(notices + ' ' + word + (notices == 1 ? '' : 's')); }
        if (responses > 0) { parts.add(responses + ' response' + (responses == 1 ? '' : 's') + ' to collect'); }
        v.suggestLine = String.join(parts, ' and ') + (fa.Check_Level__c == null ? '' : ' for a ' + fa.Check_Level__c + ' check') + '.';
    }

    /** Creates the suggested notice and response tasks the coordinator kept, owned by the coordinator. */
    @AuraEnabled
    public static View createTasks(Id recordId, List<String> keys) {
        openForChange(load(recordId));
        CqFieldActionTasks.createSuggested(recordId, keys);
        return getView(recordId);
    }

    // ---------------------------------------------------------------- saves

    /** Mark Sent: today's date on the given customers (all not yet notified when none are given), and their notice tasks done. */
    @AuraEnabled
    public static View markSent(Id recordId, List<Id> customerIds) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        Date today = Date.today();
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        Set<Id> ids = new Set<Id>();
        for (Field_Action_Customer__c c : [SELECT Id, Notice_Sent_On__c, Customer__c, Customer__r.Customer_Type__c FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId]) {
            // with no customers given: everyone this depth reaches who has not been sent the notice
            Boolean want = customerIds == null || customerIds.isEmpty()
                ? c.Notice_Sent_On__c == null && CqFieldActionDepth.includes(fa.Depth__c, c.Customer__r?.Customer_Type__c, c.Customer__c)
                : customerIds.contains(c.Id);
            if (want) { ups.add(new Field_Action_Customer__c(Id = c.Id, Notice_Sent_On__c = today)); ids.add(c.Id); }
        }
        if (ups.isEmpty()) { throw new AuraHandledException('Every customer has already been sent the notice.'); }
        update ups;
        List<Task> ts = new List<Task>();
        for (Task t : [SELECT Id FROM Task WHERE WhatId = :recordId AND IsClosed = false AND Recall_Task_Type__c = :CqFieldActionTasks.NOTICE
                       AND Field_Action_Customer__c IN :ids]) {
            ts.add(new Task(Id = t.Id, Status = CqFieldActionTasks.DONE));
        }
        if (!ts.isEmpty()) { update ts; }
        return getView(recordId);
    }

    /** One figure on a customer's response for a lot: used, returning or destroyed (blank clears it). */
    @AuraEnabled
    public static View saveLine(Id recordId, Id customerId, String lot, String field, Decimal value) {
        openForChange(load(recordId));
        Field_Action_Customer__c c = [SELECT Id, Field_Action__c FROM Field_Action_Customer__c WHERE Id = :customerId];
        if (c.Field_Action__c != recordId) { throw new AuraHandledException('That customer belongs to another field action.'); }
        if (String.isBlank(lot)) { throw new AuraHandledException('Choose the lot.'); }
        if (value != null && value < 0) { throw new AuraHandledException('Units cannot be negative.'); }
        List<Customer_Response_Line__c> have = [SELECT Id FROM Customer_Response_Line__c WHERE Field_Action_Customer__c = :customerId AND Lot_Number__c = :lot LIMIT 1];
        Customer_Response_Line__c l = have.isEmpty() ? new Customer_Response_Line__c(Field_Action_Customer__c = customerId, Lot_Number__c = lot) : have[0];
        switch on field {
            when 'used' { l.Units_Used__c = value; }
            when 'returning' { l.Units_Returning__c = value; }
            when 'destroyed' { l.Units_Destroyed__c = value; }
            when else { throw new AuraHandledException('Unknown figure: ' + field); }
        }
        upsert l;
        return getView(recordId);
    }

    /** Records the customer's response (Acknowledged, today, its response task done), or takes it back. */
    @AuraEnabled
    public static View setResponded(Id recordId, Id customerId, Boolean responded) {
        openForChange(load(recordId));
        Field_Action_Customer__c c = [SELECT Id, Field_Action__c, Notice_Sent_On__c FROM Field_Action_Customer__c WHERE Id = :customerId];
        if (c.Field_Action__c != recordId) { throw new AuraHandledException('That customer belongs to another field action.'); }
        Date today = Date.today();
        update new Field_Action_Customer__c(Id = c.Id, Status__c = responded ? ACK : SENT, Responded_On__c = responded ? today : null,
            Notice_Sent_On__c = c.Notice_Sent_On__c == null && responded ? today : c.Notice_Sent_On__c);
        List<Task> ts = new List<Task>();
        for (Task t : [SELECT Id, IsClosed FROM Task WHERE WhatId = :recordId AND Recall_Task_Type__c = :CqFieldActionTasks.RESPONSE
                       AND Field_Action_Customer__c = :customerId]) {
            if (t.IsClosed != responded) { ts.add(new Task(Id = t.Id, Status = responded ? CqFieldActionTasks.DONE : CqFieldActionTasks.OPEN)); }
        }
        if (!ts.isEmpty()) { update ts; }
        return getView(recordId);
    }

    /** Ticks a notice or response task on this step: a notice records the date sent, a response the customer's response. */
    @AuraEnabled
    public static View setTask(Id recordId, Id taskId, Boolean done) {
        openForChange(load(recordId));
        Task t = [SELECT Id, WhatId, Recall_Task_Type__c, Field_Action_Customer__c FROM Task WHERE Id = :taskId];
        if (t.WhatId != recordId) { throw new AuraHandledException('That task belongs to another record.'); }
        if (t.Recall_Task_Type__c == CqFieldActionTasks.RESPONSE && t.Field_Action_Customer__c != null) {
            return setResponded(recordId, t.Field_Action_Customer__c, done);
        }
        update new Task(Id = taskId, Status = done ? CqFieldActionTasks.DONE : CqFieldActionTasks.OPEN);
        if (done && t.Recall_Task_Type__c == CqFieldActionTasks.NOTICE && t.Field_Action_Customer__c != null) {
            Field_Action_Customer__c c = [SELECT Id, Notice_Sent_On__c FROM Field_Action_Customer__c WHERE Id = :t.Field_Action_Customer__c];
            if (c.Notice_Sent_On__c == null) { update new Field_Action_Customer__c(Id = c.Id, Notice_Sent_On__c = Date.today()); }
        }
        return getView(recordId);
    }
}
