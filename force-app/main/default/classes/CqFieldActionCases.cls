/**
 * CqFieldActionCases: customer notification on a field action runs on Cases, one per customer on the list.
 *  - sync(): once the strategy is confirmed, lists the customers (we shipped to them: Distributor or Direct Customer;
 *    a distributor shipped to them: Customer, listed at Hospital and Patient depth) and opens a Case for each one that
 *    has none, with the response due date.
 *  - The Case is the record of the communication. What happens on it is written to the customer's row on the field
 *    action (onCase): notice sent, response due, and how it closed. Closed as Response Received = Acknowledged (every
 *    lot must have what the customer reported first); closed as No Response = closed without a response, still not
 *    acknowledged; reopened = pending again.
 *  - A customer who returns every unit shipped is acknowledged without a form (fullReturns).
 *  - The coordinator submits acknowledged customers to Recovery in batches (submit), and can close a customer who
 *    never answers, with a reason (closeWithoutResponse) or reopen them (reopen).
 */
public with sharing class CqFieldActionCases {
    public static final String ORIGIN = 'Field Action';
    public static final String RECEIVED = 'Response Received';
    public static final String NO_RESPONSE = 'No Response';
    public static final String ACK = 'Acknowledged';
    public static final String PENDING = 'Sent';
    public static final Integer RESPONSE_DAYS = 14;

    private static Boolean byFullReturn = false;   // the Case being closed is closed by a full return
    private static Set<String> closedStatuses;
    private static Set<String> closed() {
        if (closedStatuses == null) {
            closedStatuses = new Set<String>();
            for (CaseStatus s : [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = true]) { closedStatuses.add(s.MasterLabel); }
        }
        return closedStatuses;
    }
    private static String closedStatus() { return closed().contains('Closed') || closed().isEmpty() ? 'Closed' : new List<String>(closed())[0]; }
    private static String openStatus() {
        List<CaseStatus> s = [SELECT MasterLabel FROM CaseStatus WHERE IsDefault = true LIMIT 1];
        return s.isEmpty() ? 'New' : s[0].MasterLabel;
    }
    private static Decimal n(Decimal d) { return d == null ? 0 : d; }
    private static Set<String> lotsInScope(Id faId) {
        Set<String> lots = new Set<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :faId AND Approved_In_Scope__c = true]) {
            lots.add(l.Lot_Number__c);
        }
        return lots;
    }
    private static List<String> lotList(String lots) {
        List<String> out = new List<String>();
        if (String.isNotBlank(lots)) { for (String s : lots.split(',\\s*')) { if (String.isNotBlank(s)) { out.add(s.trim()); } } }
        return out;
    }

    // ---------------------------------------------------------------- the list and its Cases

    /** Brings the customer list, each customer's kind and their Cases up to date. Does nothing until the strategy is confirmed. */
    public static void sync(Id faId) {
        Field_Action__c fa = [SELECT Id, Name, Status__c, Strategy_Status__c, Strategy_Confirmed_On__c, Action_Type__c, Depth__c, Check_By__c, Key_Message__c
                              FROM Field_Action__c WHERE Id = :faId];
        if (fa.Status__c == 'Closed' || fa.Strategy_Status__c != 'Confirmed') { return; }
        CqFieldActionRecovery.syncCustomers(faId);
        kinds(faId);
        openCases(fa);
    }

    /** Sets each customer's kind, and adds the customers a distributor shipped to (from the distributor's shipping list). */
    private static void kinds(Id faId) {
        Set<String> lots = lotsInScope(faId);
        Map<Id, Field_Action_Customer__c> byAccount = new Map<Id, Field_Action_Customer__c>();
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        for (Field_Action_Customer__c c : [SELECT Id, Customer__c, Customer__r.Customer_Type__c, Kind__c, Distributor__c, Units__c, Lots__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :faId AND Customer__c != null]) {
            byAccount.put(c.Customer__c, c);
            if (c.Kind__c == CqFieldActionDepth.CUSTOMER) { continue; }
            String want = CqFieldActionDepth.kindOf(c.Customer__r.Customer_Type__c);
            if (c.Kind__c != want) { c.Kind__c = want; ups.add(new Field_Action_Customer__c(Id = c.Id, Kind__c = want)); }
        }
        if (!ups.isEmpty()) { update ups; }
        if (lots.isEmpty()) { return; }

        // the distributors' own shipments: who they passed the lots on to
        Map<Id, Field_Action_Customer__c> onward = new Map<Id, Field_Action_Customer__c>();
        Map<Id, List<String>> lotsOf = new Map<Id, List<String>>();
        for (Lot_Shipment__c s : [SELECT Customer__c, Customer__r.Name, Shipped_By__c, Lot_Number__c, Units__c FROM Lot_Shipment__c
                                  WHERE Lot_Number__c IN :lots AND Shipped_By__c != null AND Customer__c != null
                                  ORDER BY Customer__r.Name, Lot_Number__c LIMIT 5000]) {
            Field_Action_Customer__c dist = byAccount.get(s.Shipped_By__c);
            Field_Action_Customer__c have = byAccount.get(s.Customer__c);
            if (dist == null || dist.Kind__c == CqFieldActionDepth.CUSTOMER) { continue; }        // the distributor is not on this field action
            if (have != null && have.Kind__c != CqFieldActionDepth.CUSTOMER) { continue; }        // we also ship to them direct: they are listed once, as that
            if (!onward.containsKey(s.Customer__c)) {
                onward.put(s.Customer__c, new Field_Action_Customer__c(Id = have == null ? null : have.Id, Field_Action__c = faId, Customer__c = s.Customer__c,
                    Customer_Name__c = s.Customer__r.Name, Kind__c = CqFieldActionDepth.CUSTOMER, Distributor__c = dist.Id, Units__c = 0));
                lotsOf.put(s.Customer__c, new List<String>());
            }
            onward.get(s.Customer__c).Units__c += n(s.Units__c);
            if (!lotsOf.get(s.Customer__c).contains(s.Lot_Number__c)) { lotsOf.get(s.Customer__c).add(s.Lot_Number__c); }
        }
        List<Field_Action_Customer__c> adds = new List<Field_Action_Customer__c>(), changes = new List<Field_Action_Customer__c>();
        for (Id acc : onward.keySet()) {
            Field_Action_Customer__c c = onward.get(acc);
            c.Lots__c = String.join(lotsOf.get(acc), ', ').left(255);
            Field_Action_Customer__c have = byAccount.get(acc);
            if (have == null) { c.Status__c = PENDING; c.Follow_Ups__c = 0; c.Source__c = 'Shipment'; adds.add(c); }
            else if (have.Units__c != c.Units__c || have.Lots__c != c.Lots__c || have.Distributor__c != c.Distributor__c) {
                changes.add(new Field_Action_Customer__c(Id = have.Id, Units__c = c.Units__c, Lots__c = c.Lots__c, Distributor__c = c.Distributor__c));
            }
        }
        if (!adds.isEmpty()) { insert adds; }
        if (!changes.isEmpty()) { update changes; }
    }

    /** The response due date: 14 days after the strategy was confirmed, or the check-by date when that comes sooner. */
    public static Date dueFor(Field_Action__c fa) {
        Date d = (fa.Strategy_Confirmed_On__c == null ? Date.today() : fa.Strategy_Confirmed_On__c.date()).addDays(RESPONSE_DAYS);
        return fa.Check_By__c != null && fa.Check_By__c < d ? fa.Check_By__c : d;
    }

    /** Opens a Case for each listed customer that has none. */
    private static void openCases(Field_Action__c fa) {
        List<Field_Action_Customer__c> need = new List<Field_Action_Customer__c>();
        for (Field_Action_Customer__c c : [SELECT Id, Customer__c, Customer_Name__c, Kind__c, Notice_Sent_On__c FROM Field_Action_Customer__c
                                           WHERE Field_Action__c = :fa.Id AND Case__c = null AND Closed_Without_Response_On__c = null AND Status__c != :ACK
                                           ORDER BY Customer_Name__c]) {
            if (CqFieldActionDepth.listed(fa.Depth__c, c.Kind__c)) { need.add(c); }
        }
        if (need.isEmpty()) { return; }
        Date due = dueFor(fa);
        String word = fa.Action_Type__c == CqFieldActionStrategy.WITHDRAWAL ? 'Withdrawal notice' : 'Recall notice';
        List<Case> cases = new List<Case>();
        for (Field_Action_Customer__c c : need) {
            cases.add(new Case(AccountId = c.Customer__c, Subject = (word + ' ' + fa.Name + ': ' + c.Customer_Name__c).left(255), Origin = ORIGIN,
                Description = fa.Key_Message__c, Field_Action__c = fa.Id, Field_Action_Customer__c = c.Id, Response_Due__c = due,
                Notice_Sent_On__c = c.Notice_Sent_On__c));   // a notice already recorded on the customer carries to the Case
        }
        insert cases;
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        for (Integer i = 0; i < need.size(); i++) { ups.add(new Field_Action_Customer__c(Id = need[i].Id, Case__c = cases[i].Id, Response_Due__c = due)); }
        update ups;
    }

    /**
     * Units shipped per customer row and lot (row id | lot). A Distributor or Direct Customer: what we shipped them. A
     * Customer: what its distributor shipped them. Where the depth lists the distributors' customers, a distributor's own
     * figure is what it still holds (shipped to it, less what it passed on), so no unit is counted twice.
     */
    public static Map<String, Decimal> shippedByLine(Id faId) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        Set<String> lots = lotsInScope(faId);
        Map<Id, Field_Action_Customer__c> byAccount = new Map<Id, Field_Action_Customer__c>();
        String depth;
        for (Field_Action_Customer__c c : [SELECT Id, Customer__c, Kind__c, Field_Action__r.Depth__c FROM Field_Action_Customer__c
                                           WHERE Field_Action__c = :faId AND Customer__c != null]) {
            byAccount.put(c.Customer__c, c); depth = c.Field_Action__r.Depth__c;
        }
        if (lots.isEmpty() || byAccount.isEmpty()) { return out; }
        Boolean split = CqFieldActionDepth.listsCustomers(depth);
        for (AggregateResult r : [SELECT Customer__c acc, Shipped_By__c dist, Lot_Number__c lot, SUM(Units__c) units FROM Lot_Shipment__c
                                  WHERE Lot_Number__c IN :lots AND (Customer__c IN :byAccount.keySet() OR Shipped_By__c IN :byAccount.keySet())
                                  GROUP BY Customer__c, Shipped_By__c, Lot_Number__c]) {
            Id acc = (Id) r.get('acc'), dist = (Id) r.get('dist');
            String lot = (String) r.get('lot'); Decimal u = n((Decimal) r.get('units'));
            Field_Action_Customer__c to = byAccount.get(acc), sender = dist == null ? null : byAccount.get(dist);
            if (dist == null) {
                if (to != null && to.Kind__c != CqFieldActionDepth.CUSTOMER) { add(out, to.Id + '|' + lot, u); }
            } else {
                if (to != null && to.Kind__c == CqFieldActionDepth.CUSTOMER) { add(out, to.Id + '|' + lot, u); }
                if (split && sender != null && to != null && to.Kind__c == CqFieldActionDepth.CUSTOMER) { add(out, sender.Id + '|' + lot, -u); }
            }
        }
        for (String k : out.keySet()) { if (out.get(k) < 0) { out.put(k, 0); } }
        return out;
    }
    private static void add(Map<String, Decimal> m, String k, Decimal u) { m.put(k, (m.containsKey(k) ? m.get(k) : 0) + u); }

    // ---------------------------------------------------------------- the Case writes to the customer's row

    /** Case trigger. Before: a reopened Case loses its outcome; closing needs an outcome and the reported figures. After: the row follows. */
    public static void onCase(List<Case> rows, Map<Id, Case> old, Boolean isBefore) {
        List<Case> mine = new List<Case>();
        for (Case c : rows) { if (c.Field_Action_Customer__c != null) { mine.add(c); } }
        if (mine.isEmpty()) { return; }
        Set<String> shut = closed();
        if (isBefore) {
            List<Case> closing = new List<Case>();
            for (Case c : mine) {
                Boolean was = shut.contains(old.get(c.Id).Status), now = shut.contains(c.Status);
                if (was && !now) { c.Response_Outcome__c = null; }
                if (!was && now) {
                    if (c.Response_Outcome__c == null) { c.Response_Outcome__c = RECEIVED; }
                    if (c.Response_Outcome__c == RECEIVED) { closing.add(c); }
                }
            }
            if (!closing.isEmpty()) { needFigures(closing); }
            return;
        }
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        for (Case c : mine) {
            Case o = old.get(c.Id);
            Boolean was = shut.contains(o.Status), now = shut.contains(c.Status);
            Field_Action_Customer__c up = new Field_Action_Customer__c(Id = c.Field_Action_Customer__c);
            Boolean change = false;
            if (c.Notice_Sent_On__c != o.Notice_Sent_On__c) { up.Notice_Sent_On__c = c.Notice_Sent_On__c; change = true; }
            if (c.Response_Due__c != o.Response_Due__c) { up.Response_Due__c = c.Response_Due__c; change = true; }
            if (!was && now && c.Response_Outcome__c == RECEIVED) {
                up.Status__c = ACK; up.Responded_On__c = Date.today(); up.Acknowledged_By__c = byFullReturn ? 'Full Return' : 'Response';
                up.Closed_Without_Response_On__c = null; up.No_Response_Reason__c = null;
                if (c.Notice_Sent_On__c == null) { up.Notice_Sent_On__c = Date.today(); }
                change = true;
            } else if (!was && now) {
                up.Status__c = 'No reply'; up.Closed_Without_Response_On__c = Date.today(); change = true;
            } else if (was && !now) {
                up.Status__c = PENDING; up.Responded_On__c = null; up.Acknowledged_By__c = null; up.Submitted_On__c = null; up.Submitted_By__c = null;
                up.Closed_Without_Response_On__c = null; up.No_Response_Reason__c = null; change = true;
            }
            if (change) { ups.add(up); }
        }
        if (!ups.isEmpty()) { update ups; }
    }

    /** A Case closes as Response Received only when every lot the customer received has what they reported. */
    private static void needFigures(List<Case> closing) {
        Set<Id> ids = new Set<Id>();
        for (Case c : closing) { ids.add(c.Field_Action_Customer__c); }
        Map<Id, Set<String>> said = new Map<Id, Set<String>>();
        for (Customer_Response_Line__c l : [SELECT Field_Action_Customer__c, Lot_Number__c, Units_Used__c, Units_Returning__c, Units_Destroyed__c
                                            FROM Customer_Response_Line__c WHERE Field_Action_Customer__c IN :ids]) {
            if (l.Units_Used__c == null && l.Units_Returning__c == null && l.Units_Destroyed__c == null) { continue; }
            if (!said.containsKey(l.Field_Action_Customer__c)) { said.put(l.Field_Action_Customer__c, new Set<String>()); }
            said.get(l.Field_Action_Customer__c).add(l.Lot_Number__c);
        }
        Map<Id, Field_Action_Customer__c> rows = new Map<Id, Field_Action_Customer__c>([SELECT Id, Lots__c FROM Field_Action_Customer__c WHERE Id IN :ids]);
        for (Case c : closing) {
            Field_Action_Customer__c row = rows.get(c.Field_Action_Customer__c);
            if (row == null) { continue; }
            List<String> missing = new List<String>();
            for (String lot : lotList(row.Lots__c)) {
                if (!said.containsKey(row.Id) || !said.get(row.Id).contains(lot)) { missing.add(lot); }
            }
            if (!missing.isEmpty()) {
                c.addError('Enter what the customer reported for ' + (missing.size() == 1 ? 'lot ' : 'lots ') + String.join(missing, ', ')
                    + ' before closing this Case as Response Received.');
            }
        }
    }

    /** A customer who has returned every unit shipped to them is acknowledged without a form: their Case closes on the returns. */
    public static void fullReturns(Id faId) {
        Map<String, Decimal> got = CqLotReturns.received(faId);
        if (got.isEmpty()) { return; }
        Map<String, Decimal> shipped = shippedByLine(faId);
        Set<String> haveLine = new Set<String>();
        for (Customer_Response_Line__c l : [SELECT Field_Action_Customer__c, Lot_Number__c FROM Customer_Response_Line__c
                                            WHERE Field_Action_Customer__r.Field_Action__c = :faId]) {
            haveLine.add(l.Field_Action_Customer__c + '|' + l.Lot_Number__c);
        }
        List<Customer_Response_Line__c> lines = new List<Customer_Response_Line__c>();
        List<Case> toClose = new List<Case>();
        List<Field_Action_Customer__c> direct = new List<Field_Action_Customer__c>();
        for (Field_Action_Customer__c c : [SELECT Id, Lots__c, Case__c, Case__r.IsClosed, Notice_Sent_On__c FROM Field_Action_Customer__c
                                           WHERE Field_Action__c = :faId AND Status__c != :ACK AND Closed_Without_Response_On__c = null]) {
            List<String> lots = lotList(c.Lots__c);
            Boolean all = !lots.isEmpty();
            for (String lot : lots) {
                Decimal s = shipped.get(c.Id + '|' + lot), g = got.get(c.Id + '|' + lot);
                if (s == null || s <= 0 || g == null || g < s) { all = false; break; }
            }
            if (!all) { continue; }
            for (String lot : lots) {
                if (!haveLine.contains(c.Id + '|' + lot)) {
                    lines.add(new Customer_Response_Line__c(Field_Action_Customer__c = c.Id, Lot_Number__c = lot, Units_Used__c = 0,
                        Units_Returning__c = got.get(c.Id + '|' + lot), Units_Destroyed__c = 0));
                }
            }
            if (c.Case__c != null && !c.Case__r.IsClosed) { toClose.add(new Case(Id = c.Case__c, Status = closedStatus(), Response_Outcome__c = RECEIVED)); }
            else if (c.Case__c == null) {
                direct.add(new Field_Action_Customer__c(Id = c.Id, Status__c = ACK, Responded_On__c = Date.today(), Acknowledged_By__c = 'Full Return',
                    Notice_Sent_On__c = c.Notice_Sent_On__c == null ? Date.today() : c.Notice_Sent_On__c));
            }
        }
        if (!lines.isEmpty()) { insert lines; }
        if (!direct.isEmpty()) { update direct; }
        if (!toClose.isEmpty()) { byFullReturn = true; update toClose; byFullReturn = false; }
    }

    // ---------------------------------------------------------------- the coordinator's actions

    private static void openForChange(Id faId) {
        Field_Action__c fa = [SELECT Status__c, Strategy_Status__c FROM Field_Action__c WHERE Id = :faId];
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (fa.Strategy_Status__c != 'Confirmed') { throw new AuraHandledException('Confirm the strategy first.'); }
    }
    private static Field_Action_Customer__c rowOf(Id faId, Id customerId) {
        Field_Action_Customer__c c = [SELECT Id, Field_Action__c, Case__c, Case__r.IsClosed, Status__c FROM Field_Action_Customer__c WHERE Id = :customerId];
        if (c.Field_Action__c != faId) { throw new AuraHandledException('That customer belongs to another field action.'); }
        return c;
    }

    /** Records today as the date the notice went out, on every open Case that has none. Returns how many. */
    public static Integer markNoticeSent(Id faId) {
        openForChange(faId);
        List<Case> ups = new List<Case>();
        for (Case c : [SELECT Id FROM Case WHERE Field_Action__c = :faId AND IsClosed = false AND Notice_Sent_On__c = null]) {
            ups.add(new Case(Id = c.Id, Notice_Sent_On__c = Date.today()));
        }
        if (ups.isEmpty()) { throw new AuraHandledException('Every customer has already been sent the notice.'); }
        update ups;
        return ups.size();
    }

    /** Logs a follow-up on every customer still pending: one more on the row's count, and a completed activity on the Case. */
    public static Integer followUp(Id faId) {
        openForChange(faId);
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        List<Task> log = new List<Task>();
        for (Field_Action_Customer__c c : [SELECT Id, Follow_Ups__c, Case__c FROM Field_Action_Customer__c
                                           WHERE Field_Action__c = :faId AND Case__c != null AND Case__r.IsClosed = false]) {
            ups.add(new Field_Action_Customer__c(Id = c.Id, Follow_Ups__c = n(c.Follow_Ups__c) + 1));
            log.add(new Task(WhatId = c.Case__c, Subject = 'Follow-up sent', Status = CqFieldActionTasks.DONE, Priority = 'Normal', ActivityDate = Date.today()));
        }
        if (ups.isEmpty()) { throw new AuraHandledException('Nobody is pending a response.'); }
        update ups; insert log;
        return ups.size();
    }

    /** Submits every acknowledged customer not yet submitted to Recovery. Returns how many. */
    public static Integer submit(Id faId) {
        openForChange(faId);
        List<Field_Action_Customer__c> ups = new List<Field_Action_Customer__c>();
        for (Field_Action_Customer__c c : [SELECT Id FROM Field_Action_Customer__c WHERE Field_Action__c = :faId AND Status__c = :ACK AND Submitted_On__c = null]) {
            ups.add(new Field_Action_Customer__c(Id = c.Id, Submitted_On__c = Datetime.now(), Submitted_By__c = UserInfo.getUserId()));
        }
        if (ups.isEmpty()) { throw new AuraHandledException('No acknowledged customers are waiting to be submitted.'); }
        update ups;
        return ups.size();
    }

    /** Closes a customer who never answered: the reason is required, the Case closes as No Response, and they stay not acknowledged. */
    public static void closeWithoutResponse(Id faId, Id customerId, String reason) {
        openForChange(faId);
        if (String.isBlank(reason)) { throw new AuraHandledException('Say why this customer is being closed without a response.'); }
        Field_Action_Customer__c c = rowOf(faId, customerId);
        if (c.Status__c == ACK) { throw new AuraHandledException('This customer has already acknowledged.'); }
        update new Field_Action_Customer__c(Id = c.Id, No_Response_Reason__c = reason.trim().left(255), Status__c = 'No reply',
            Closed_Without_Response_On__c = Date.today());
        if (c.Case__c != null && !c.Case__r.IsClosed) { update new Case(Id = c.Case__c, Status = closedStatus(), Response_Outcome__c = NO_RESPONSE); }
    }

    /** Reopens a customer closed without a response (a late reply came in): their Case opens again and they are pending. */
    public static void reopen(Id faId, Id customerId) {
        openForChange(faId);
        Field_Action_Customer__c c = rowOf(faId, customerId);
        if (c.Case__c != null && c.Case__r.IsClosed) { update new Case(Id = c.Case__c, Status = openStatus()); }
        else {
            update new Field_Action_Customer__c(Id = c.Id, Status__c = PENDING, Responded_On__c = null, Acknowledged_By__c = null, Submitted_On__c = null,
                Submitted_By__c = null, Closed_Without_Response_On__c = null, No_Response_Reason__c = null);
        }
    }

    // ---------------------------------------------------------------- on the Case page: what the customer reported, by lot

    public class Line {
        @AuraEnabled public String lot; @AuraEnabled public Decimal shipped;
        @AuraEnabled public Decimal used; @AuraEnabled public Decimal returning; @AuraEnabled public Decimal destroyed;
        @AuraEnabled public Decimal unknown;   // shipped less used, returning and destroyed; null until any is recorded
    }
    public class CaseView {
        @AuraEnabled public Boolean fieldAction = false;   // false: an ordinary Case, the panel shows nothing
        @AuraEnabled public Id fieldActionId; @AuraEnabled public String fieldActionName; @AuraEnabled public String customer;
        @AuraEnabled public Boolean locked = false;        // the field action is closed
        @AuraEnabled public List<Line> lines = new List<Line>();
    }

    /** The lots this Case's customer received, with what they reported for each. */
    @AuraEnabled
    public static CaseView caseView(Id caseId) {
        CaseView v = new CaseView();
        List<Case> cs = [SELECT Id, Field_Action_Customer__c FROM Case WHERE Id = :caseId AND Field_Action_Customer__c != null];
        if (cs.isEmpty()) { return v; }
        Field_Action_Customer__c c = [SELECT Id, Customer_Name__c, Lots__c, Field_Action__c, Field_Action__r.Name, Field_Action__r.Status__c
                                      FROM Field_Action_Customer__c WHERE Id = :cs[0].Field_Action_Customer__c];
        v.fieldAction = true; v.fieldActionId = c.Field_Action__c; v.fieldActionName = c.Field_Action__r.Name; v.customer = c.Customer_Name__c;
        v.locked = c.Field_Action__r.Status__c == 'Closed';
        Map<String, Decimal> shipped = shippedByLine(c.Field_Action__c);
        Map<String, Customer_Response_Line__c> said = new Map<String, Customer_Response_Line__c>();
        for (Customer_Response_Line__c l : [SELECT Lot_Number__c, Units_Used__c, Units_Returning__c, Units_Destroyed__c
                                            FROM Customer_Response_Line__c WHERE Field_Action_Customer__c = :c.Id]) {
            said.put(l.Lot_Number__c, l);
        }
        for (String lot : lotList(c.Lots__c)) {
            Line l = new Line();
            l.lot = lot; l.shipped = shipped.get(c.Id + '|' + lot);
            Customer_Response_Line__c r = said.get(lot);
            if (r != null) {
                l.used = r.Units_Used__c; l.returning = r.Units_Returning__c; l.destroyed = r.Units_Destroyed__c;
                if (l.shipped != null && (l.used != null || l.returning != null || l.destroyed != null)) {
                    l.unknown = Math.max(0, l.shipped - n(l.used) - n(l.returning) - n(l.destroyed));
                }
            }
            v.lines.add(l);
        }
        return v;
    }

    /** One figure the customer reported for a lot: used, returning or destroyed (blank clears it). */
    @AuraEnabled
    public static CaseView saveCaseLine(Id caseId, String lot, String field, Decimal value) {
        List<Case> cs = [SELECT Id, Field_Action__c, Field_Action_Customer__c FROM Case WHERE Id = :caseId AND Field_Action_Customer__c != null];
        if (cs.isEmpty()) { throw new AuraHandledException('This Case is not a field action notification.'); }
        if ([SELECT Status__c FROM Field_Action__c WHERE Id = :cs[0].Field_Action__c].Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (String.isBlank(lot)) { throw new AuraHandledException('Choose the lot.'); }
        if (value != null && value < 0) { throw new AuraHandledException('Units cannot be negative.'); }
        Id customerId = cs[0].Field_Action_Customer__c;
        List<Customer_Response_Line__c> have = [SELECT Id FROM Customer_Response_Line__c WHERE Field_Action_Customer__c = :customerId AND Lot_Number__c = :lot LIMIT 1];
        Customer_Response_Line__c l = have.isEmpty() ? new Customer_Response_Line__c(Field_Action_Customer__c = customerId, Lot_Number__c = lot) : have[0];
        switch on field {
            when 'used' { l.Units_Used__c = value; }
            when 'returning' { l.Units_Returning__c = value; }
            when 'destroyed' { l.Units_Destroyed__c = value; }
            when else { throw new AuraHandledException('Unknown figure: ' + field); }
        }
        upsert l;
        return caseView(caseId);
    }
}
