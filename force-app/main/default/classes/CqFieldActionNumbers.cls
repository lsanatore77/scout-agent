/**
 * The Field Action's numbers, written to the record so a standard page and reports can show them: scope (lots in scope,
 * units shipped and on hand, lots on hold), notifications (customers listed, notified, responded, closed without a
 * response, overdue, first notice sent) and recovery (units returned, destroyed, corrected, used, unaccounted, recovery %,
 * check target met).
 *
 * Worked out here and nowhere else, so the switch to updating straight away (backlog) only changes who calls refresh().
 * Callers today: the nightly job (CqFieldActionNumbersJob) and the Refresh Numbers button in the workspace header.
 * The rules follow the workspace's own: customers are those How Far It Goes lists (CqFieldActionDepth), the units come
 * from the lots approved in scope, and a lot's recovered units never count above what was shipped (CqFieldActionRecovery).
 */
public inherited sharing class CqFieldActionNumbers {

    public class Numbers {
        public Decimal lotsInScope = 0, shipped = 0, onHand = 0, lotsOnHold = 0;
        public Decimal customers = 0, notified = 0, responded = 0, noResponse = 0, overdue = 0;
        public Decimal returned = 0, destroyed = 0, corrected = 0, used = 0, recovered = 0;
        public Boolean shippedKnown = false;
        public Date firstNotice;
    }

    private static Decimal n(Decimal d) { return d == null ? 0 : d; }

    /** The share of customers the check level needs to hear from (as CqFieldActionRecovery). */
    public static Decimal targetOf(String level, Decimal percent) {
        switch on level {
            when 'Level A' { return 100; }
            when 'Level B' { return percent == null ? 100 : percent; }
            when 'Level C' { return 10; }
            when 'Level D' { return 2; }
            when 'Level E' { return 0; }
            when else { return 100; }
        }
    }

    /** Works out the numbers for these field actions without saving them. */
    public static Map<Id, Numbers> compute(Set<Id> ids) {
        Map<Id, Numbers> out = new Map<Id, Numbers>();
        Map<Id, Field_Action__c> fas = new Map<Id, Field_Action__c>([SELECT Id, Depth__c FROM Field_Action__c WHERE Id IN :ids]);
        for (Id i : fas.keySet()) { out.put(i, new Numbers()); }
        if (fas.isEmpty()) { return out; }
        Date today = Date.today();

        // units used, as customers reported, per field action and lot
        Map<String, Decimal> usedOf = new Map<String, Decimal>();
        for (Customer_Response_Line__c l : [SELECT Field_Action_Customer__r.Field_Action__c, Lot_Number__c, Units_Used__c FROM Customer_Response_Line__c
                                            WHERE Field_Action_Customer__r.Field_Action__c IN :fas.keySet() AND Units_Used__c != null]) {
            String k = l.Field_Action_Customer__r.Field_Action__c + '|' + l.Lot_Number__c;
            usedOf.put(k, n(usedOf.get(k)) + l.Units_Used__c);
        }

        // scope and recovery, from the lots approved in scope
        for (Field_Action_Lot__c l : [SELECT Field_Action__c, Lot_Number__c, Units_Shipped__c, Units_On_Hand__c, Units_Returned__c, Units_Destroyed__c, Units_Corrected__c
                                      FROM Field_Action_Lot__c WHERE Field_Action__c IN :fas.keySet() AND Approved_In_Scope__c = true]) {
            Numbers x = out.get(l.Field_Action__c);
            Decimal used = n(usedOf.get(l.Field_Action__c + '|' + l.Lot_Number__c));
            x.lotsInScope++;
            x.onHand += n(l.Units_On_Hand__c);
            x.returned += n(l.Units_Returned__c); x.destroyed += n(l.Units_Destroyed__c); x.corrected += n(l.Units_Corrected__c); x.used += used;
            if (l.Units_Shipped__c != null) {
                x.shippedKnown = true;
                x.shipped += l.Units_Shipped__c;
                x.recovered += Math.min(n(l.Units_Returned__c) + n(l.Units_Destroyed__c) + n(l.Units_Corrected__c) + used, l.Units_Shipped__c);
            }
        }

        // lots this field action holds
        Map<Id, Set<String>> held = new Map<Id, Set<String>>();
        for (Field_Action_Hold__c h : [SELECT Field_Action__c, Lot_Number__c FROM Field_Action_Hold__c WHERE Field_Action__c IN :fas.keySet() AND Held__c = true]) {
            if (!held.containsKey(h.Field_Action__c)) { held.put(h.Field_Action__c, new Set<String>()); }
            held.get(h.Field_Action__c).add(h.Lot_Number__c);
        }
        for (Id i : held.keySet()) { out.get(i).lotsOnHold = held.get(i).size(); }

        // notifications: the customers How Far It Goes lists
        for (Field_Action_Customer__c c : [SELECT Field_Action__c, Kind__c, Status__c, Notice_Sent_On__c, Response_Due__c, Closed_Without_Response_On__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c IN :fas.keySet()]) {
            if (!CqFieldActionDepth.listed(fas.get(c.Field_Action__c).Depth__c, c.Kind__c)) { continue; }
            Numbers x = out.get(c.Field_Action__c);
            Boolean acked = c.Status__c == CqFieldActionNotify.ACK;
            Boolean noResponse = !acked && c.Closed_Without_Response_On__c != null;
            x.customers++;
            if (c.Notice_Sent_On__c != null || acked) { x.notified++; }
            if (acked) { x.responded++; }
            if (noResponse) { x.noResponse++; }
            if (!acked && !noResponse && c.Response_Due__c != null && c.Response_Due__c < today) { x.overdue++; }
            if (c.Notice_Sent_On__c != null && (x.firstNotice == null || c.Notice_Sent_On__c < x.firstNotice)) { x.firstNotice = c.Notice_Sent_On__c; }
        }
        return out;
    }

    /** Works out and saves the numbers for these field actions. */
    public static void refresh(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) { return; }
        Map<Id, Numbers> nums = compute(ids);
        Map<Id, Field_Action__c> fas = new Map<Id, Field_Action__c>([SELECT Id, Check_Level__c, Check_Percent__c, Quantity_Shipped__c FROM Field_Action__c WHERE Id IN :nums.keySet()]);
        Datetime now = Datetime.now();
        List<Field_Action__c> ups = new List<Field_Action__c>();
        for (Id i : nums.keySet()) {
            Numbers x = nums.get(i);
            Field_Action__c fa = fas.get(i);
            Decimal target = targetOf(fa.Check_Level__c, fa.Check_Percent__c);
            Field_Action__c up = new Field_Action__c(Id = i,
                Lots_in_Scope__c = x.lotsInScope, Units_on_Hand__c = x.onHand, Lots_on_Hold__c = x.lotsOnHold,
                Customers__c = x.customers, Customers_Notified__c = x.notified, Customers_Responded__c = x.responded,
                Closed_Without_Response__c = x.noResponse, Responses_Overdue__c = x.overdue, Notices_Sent_On__c = x.firstNotice,
                Units_Returned__c = x.returned, Units_Destroyed__c = x.destroyed, Units_Corrected__c = x.corrected, Units_Used__c = x.used,
                Units_Unaccounted__c = x.shippedKnown ? Math.max(x.shipped - x.recovered, 0) : null,
                Recovery_Percent__c = x.shippedKnown && x.shipped > 0 ? (x.recovered * 100 / x.shipped).setScale(0, System.RoundingMode.FLOOR) : null,
                Check_Target_Met__c = target == 0 || (x.customers > 0 && x.responded * 100 >= target * x.customers),
                Numbers_Updated_On__c = now);
            // Units Shipped follows the lots in scope once their shipments are known
            if (x.shippedKnown) { up.Quantity_Shipped__c = x.shipped; }
            ups.add(up);
        }
        update ups;
    }

    /** The Refresh Numbers button in the workspace header. Returns when the numbers were worked out. */
    @AuraEnabled
    public static Datetime refreshNumbers(Id recordId) {
        try {
            refresh(new Set<Id>{ recordId });
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return [SELECT Numbers_Updated_On__c FROM Field_Action__c WHERE Id = :recordId].Numbers_Updated_On__c;
    }

    /** When the numbers were last worked out, for the workspace header. */
    @AuraEnabled
    public static Datetime updatedOn(Id recordId) {
        return [SELECT Numbers_Updated_On__c FROM Field_Action__c WHERE Id = :recordId].Numbers_Updated_On__c;
    }
}
