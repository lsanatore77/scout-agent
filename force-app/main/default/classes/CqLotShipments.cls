/**
 * CqLotShipments: keeps field actions in step with the Lot Shipment records (units of a lot shipped to a customer,
 * loaded from the ERP).
 *  - shipped(): Units Shipped on each Field Action Lot is the total shipped for that lot number. Called by the trigger
 *    on Lot Shipment, and when a field action is read, for lots that came into scope after their shipments.
 *  - customers(): the customers that received the lots in scope, one row per customer with their units and lots,
 *    for the Recovery and Effectiveness step.
 */
public with sharing class CqLotShipments {
    public class Consignee {
        public Id accountId; public String name; public Decimal units = 0; public List<String> lots = new List<String>();
    }

    /** Units shipped per lot number, from the shipments. */
    public static Map<String, Decimal> totals(Set<String> lotNumbers) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        if (lotNumbers == null || lotNumbers.isEmpty()) { return out; }
        for (AggregateResult r : [SELECT Lot_Number__c lot, SUM(Units__c) units FROM Lot_Shipment__c
                                  WHERE Lot_Number__c IN :lotNumbers GROUP BY Lot_Number__c]) {
            out.put((String) r.get('lot'), (Decimal) r.get('units'));
        }
        return out;
    }

    /** Sets Units Shipped on the open field actions' lots for these lot numbers to the shipment totals. */
    public static void shipped(Set<String> lotNumbers) {
        lotNumbers.remove(null);
        if (lotNumbers.isEmpty()) { return; }
        Map<String, Decimal> t = totals(lotNumbers);
        List<Field_Action_Lot__c> ups = new List<Field_Action_Lot__c>();
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c, Units_Shipped__c FROM Field_Action_Lot__c
                                      WHERE Lot_Number__c IN :lotNumbers AND Field_Action__c != null AND Field_Action__r.Status__c != 'Closed']) {
            Decimal want = t.get(l.Lot_Number__c);
            if (want != null && want != l.Units_Shipped__c) { ups.add(new Field_Action_Lot__c(Id = l.Id, Units_Shipped__c = want)); }
        }
        if (!ups.isEmpty()) { update ups; }
    }

    /** Fills Units Shipped for lots of one field action that have shipments but no shipped figure yet. */
    public static void fillShipped(Id fieldActionId) {
        Map<String, Field_Action_Lot__c> blank = new Map<String, Field_Action_Lot__c>();
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c FROM Field_Action_Lot__c
                                      WHERE Field_Action__c = :fieldActionId AND Units_Shipped__c = null AND Lot_Number__c != null]) {
            blank.put(l.Lot_Number__c, l);
        }
        if (blank.isEmpty()) { return; }
        Map<String, Decimal> t = totals(blank.keySet());
        List<Field_Action_Lot__c> ups = new List<Field_Action_Lot__c>();
        for (String n : t.keySet()) { ups.add(new Field_Action_Lot__c(Id = blank.get(n).Id, Units_Shipped__c = t.get(n))); }
        if (!ups.isEmpty()) { update ups; }
    }

    /** The customers that received these lots, with the units and lots each received. */
    public static List<Consignee> customers(Set<String> lotNumbers) {
        Map<String, Consignee> byKey = new Map<String, Consignee>();
        List<String> order = new List<String>();
        if (lotNumbers == null || lotNumbers.isEmpty()) { return new List<Consignee>(); }
        for (Lot_Shipment__c s : [SELECT Lot_Number__c, Units__c, Customer__c, Customer__r.Name FROM Lot_Shipment__c
                                  WHERE Lot_Number__c IN :lotNumbers AND Customer__c != null ORDER BY Customer__r.Name, Lot_Number__c LIMIT 5000]) {
            String key = s.Customer__c;
            if (!byKey.containsKey(key)) {
                Consignee c = new Consignee(); c.accountId = s.Customer__c; c.name = s.Customer__r.Name;
                byKey.put(key, c); order.add(key);
            }
            Consignee c = byKey.get(key);
            c.units += s.Units__c == null ? 0 : s.Units__c;
            if (!c.lots.contains(s.Lot_Number__c)) { c.lots.add(s.Lot_Number__c); }
        }
        List<Consignee> out = new List<Consignee>();
        for (String k : order) { out.add(byKey.get(k)); }
        return out;
    }

    /** Trigger on Lot Shipment: fill Lot Number from the lot record, and roll units up to the field actions. */
    public static void onChange(List<Lot_Shipment__c> rows, Map<Id, Lot_Shipment__c> before, Boolean isBefore) {
        if (isBefore) {
            Set<Id> lotIds = new Set<Id>();
            for (Lot_Shipment__c s : rows) { if (s.Lot__c != null && String.isBlank(s.Lot_Number__c)) { lotIds.add(s.Lot__c); } }
            if (!lotIds.isEmpty()) {
                Map<Id, compliancequest__SQX_Lot_Info__c> lots = new Map<Id, compliancequest__SQX_Lot_Info__c>(
                    [SELECT Id, Name FROM compliancequest__SQX_Lot_Info__c WHERE Id IN :lotIds]);
                for (Lot_Shipment__c s : rows) { if (lots.containsKey(s.Lot__c) && String.isBlank(s.Lot_Number__c)) { s.Lot_Number__c = lots.get(s.Lot__c).Name; } }
            }
            return;
        }
        Set<String> touched = new Set<String>();
        if (rows != null) { for (Lot_Shipment__c s : rows) { touched.add(s.Lot_Number__c); } }
        if (before != null) { for (Lot_Shipment__c s : before.values()) { touched.add(s.Lot_Number__c); } }
        shipped(touched);
    }
}
