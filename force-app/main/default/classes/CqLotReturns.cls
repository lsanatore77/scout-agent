/**
 * CqLotReturns: units received back from customers (Lot Return, one record per RMA receipt line, loaded from the ERP
 * or entered by hand), for the Recovery step of a field action.
 *  - Before save, a return without a Field Action is matched to the open field action whose customers include its
 *    customer and whose lots in scope include its lot.
 *  - After save, the lot's Returned is the sum of its returns (CqFieldActionTasks.sync), so Still in Field draws down on
 *    its own. Track return tasks are plain to-dos and carry no units. A customer who has now returned every unit shipped
 *    is acknowledged on the returns alone (CqFieldActionCases).
 */
public with sharing class CqLotReturns {

    /** Trigger: match the field action (before), then bring the lots' Returned into line with the returns (after). */
    public static void onChange(List<Lot_Return__c> rows, Map<Id, Lot_Return__c> before, Boolean isBefore) {
        if (isBefore) { match(rows); return; }
        cache.clear();   // the returns just changed
        Set<Id> fas = new Set<Id>();
        if (rows != null) { for (Lot_Return__c r : rows) { if (r.Field_Action__c != null) { fas.add(r.Field_Action__c); } } }
        if (before != null) { for (Lot_Return__c r : before.values()) { if (r.Field_Action__c != null) { fas.add(r.Field_Action__c); } } }
        CqFieldActionTasks.returnsChanged = true;
        for (Id fa : fas) { CqFieldActionTasks.sync(fa); CqFieldActionCases.fullReturns(fa); }
        CqFieldActionTasks.returnsChanged = false;
    }

    private static void match(List<Lot_Return__c> rows) {
        Set<Id> accs = new Set<Id>(); Set<String> lots = new Set<String>();
        for (Lot_Return__c r : rows) {
            if (r.Field_Action__c == null && r.Customer__c != null && String.isNotBlank(r.Lot_Number__c)) { accs.add(r.Customer__c); lots.add(r.Lot_Number__c); }
        }
        if (accs.isEmpty()) { return; }
        Map<String, Id> faOf = new Map<String, Id>();   // account|lot -> open field action
        Map<Id, Set<String>> lotsOf = new Map<Id, Set<String>>();
        for (Field_Action_Lot__c l : [SELECT Field_Action__c, Lot_Number__c FROM Field_Action_Lot__c
                                      WHERE Lot_Number__c IN :lots AND Approved_In_Scope__c = true AND Field_Action__r.Status__c != 'Closed']) {
            if (!lotsOf.containsKey(l.Field_Action__c)) { lotsOf.put(l.Field_Action__c, new Set<String>()); }
            lotsOf.get(l.Field_Action__c).add(l.Lot_Number__c);
        }
        if (lotsOf.isEmpty()) { return; }
        for (Field_Action_Customer__c c : [SELECT Field_Action__c, Customer__c FROM Field_Action_Customer__c
                                           WHERE Customer__c IN :accs AND Field_Action__c IN :lotsOf.keySet() ORDER BY CreatedDate DESC]) {
            for (String lot : lotsOf.get(c.Field_Action__c)) {
                String k = c.Customer__c + '|' + lot;
                if (!faOf.containsKey(k)) { faOf.put(k, c.Field_Action__c); }
            }
        }
        for (Lot_Return__c r : rows) {
            if (r.Field_Action__c == null) { r.Field_Action__c = faOf.get(r.Customer__c + '|' + r.Lot_Number__c); }
        }
    }

    /** A field action's returns, read once a transaction (the Recovery screen asks several times): units and RMAs per customer and lot. */
    private class Got {
        Map<String, Decimal> units = new Map<String, Decimal>();
        Map<String, List<String>> rmas = new Map<String, List<String>>();
        Map<String, Decimal> byLot = new Map<String, Decimal>();   // every return on the field action, whoever sent it
    }
    private static Map<Id, Got> cache = new Map<Id, Got>();
    private static Got got(Id fieldActionId) {
        if (cache.containsKey(fieldActionId)) { return cache.get(fieldActionId); }
        Got g = new Got();
        List<Lot_Return__c> rs = [SELECT Customer__c, Lot_Number__c, RMA_Number__c, Name, Units_Received__c FROM Lot_Return__c
                                  WHERE Field_Action__c = :fieldActionId ORDER BY Date_Received__c NULLS LAST, CreatedDate];
        if (!rs.isEmpty()) {
            Map<Id, Id> custOf = new Map<Id, Id>();   // account -> field action customer
            for (Field_Action_Customer__c c : [SELECT Id, Customer__c FROM Field_Action_Customer__c WHERE Field_Action__c = :fieldActionId AND Customer__c != null]) {
                custOf.put(c.Customer__c, c.Id);
            }
            for (Lot_Return__c r : rs) {
                if (String.isNotBlank(r.Lot_Number__c)) {
                    g.byLot.put(r.Lot_Number__c, (g.byLot.containsKey(r.Lot_Number__c) ? g.byLot.get(r.Lot_Number__c) : 0) + (r.Units_Received__c == null ? 0 : r.Units_Received__c));
                }
                Id c = custOf.get(r.Customer__c);
                if (c == null) { continue; }
                String k = c + '|' + r.Lot_Number__c;
                g.units.put(k, (g.units.containsKey(k) ? g.units.get(k) : 0) + (r.Units_Received__c == null ? 0 : r.Units_Received__c));
                if (!g.rmas.containsKey(k)) { g.rmas.put(k, new List<String>()); }
                g.rmas.get(k).add(String.isBlank(r.RMA_Number__c) ? r.Name : r.RMA_Number__c);
            }
        }
        cache.put(fieldActionId, g);
        return g;
    }

    /** Units received per customer and lot on a field action, keyed by Field Action Customer id | lot. */
    public static Map<String, Decimal> received(Id fieldActionId) { return got(fieldActionId).units; }

    /** The RMA numbers behind each customer and lot, keyed as received(). */
    public static Map<String, List<String>> rmas(Id fieldActionId) { return got(fieldActionId).rmas; }

    /** Units received per lot on a field action, from every return, keyed by lot number. */
    public static Map<String, Decimal> receivedByLot(Id fieldActionId) { return got(fieldActionId).byLot; }
}
