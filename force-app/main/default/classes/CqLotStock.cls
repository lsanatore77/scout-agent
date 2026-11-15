/**
 * CqLotStock: units on hand by lot and CQ Location, from the Lot Stock records (loaded from the ERP).
 *  - forScope() / forLots(): per lot number, the total on hand, each location with its units, and when and where the figures came from.
 *    The Scope step shows these read-only.
 *  - refresh(): keeps Units On Hand and Location on open field actions' lots in step, so Strategy holds and Recovery's
 *    held stock show the same figures. Called by the trigger on Lot Stock.
 */
public with sharing class CqLotStock {
    public class Place { @AuraEnabled public String location; @AuraEnabled public Id locationId; @AuraEnabled public Decimal units; }
    public class Stock {
        @AuraEnabled public Decimal total = 0;
        @AuraEnabled public List<Place> places = new List<Place>();
        @AuraEnabled public Datetime asOf;
        @AuraEnabled public String source;
        @AuraEnabled public String summary;
        @AuraEnabled public Boolean hasRecord = false;   // false: no stock record for the lot at all
        @AuraEnabled public Decimal shipped;              // from the Lot Shipment records
    }

    /** For the Scope step: stock and units shipped for each lot listed. */
    @AuraEnabled
    public static Map<String, Stock> forScope(List<String> lots) {
        Set<String> names = new Set<String>(lots == null ? new List<String>() : lots);
        names.remove(null);
        Map<String, Stock> out = forLots(names);
        Map<String, Decimal> sent = CqLotShipments.totals(names);
        for (String n : sent.keySet()) {
            if (!out.containsKey(n)) { Stock s = new Stock(); s.total = null; out.put(n, s); }
            out.get(n).shipped = sent.get(n);
        }
        return out;
    }

    public static Map<String, Stock> forLots(Set<String> lotNumbers) {
        Map<String, Stock> out = new Map<String, Stock>();
        if (lotNumbers == null || lotNumbers.isEmpty()) { return out; }
        for (Lot_Stock__c r : [SELECT Lot_Number__c, Location__c, Location__r.Name, Units_On_Hand__c, As_Of__c, Source__c
                               FROM Lot_Stock__c WHERE Lot_Number__c IN :lotNumbers ORDER BY Units_On_Hand__c DESC NULLS LAST, Location__r.Name]) {
            Stock s = out.containsKey(r.Lot_Number__c) ? out.get(r.Lot_Number__c) : new Stock();
            s.hasRecord = true;
            Decimal u = r.Units_On_Hand__c == null ? 0 : r.Units_On_Hand__c;
            s.total += u;
            if (u > 0) {
                Place p = new Place(); p.location = r.Location__r == null ? 'No location' : r.Location__r.Name; p.locationId = r.Location__c; p.units = u;
                s.places.add(p);
            }
            if (r.As_Of__c != null && (s.asOf == null || r.As_Of__c < s.asOf)) { s.asOf = r.As_Of__c; }   // the oldest figure
            s.source = s.source == null || s.source == r.Source__c ? r.Source__c : 'Mixed';
            out.put(r.Lot_Number__c, s);
        }
        for (Stock s : out.values()) {
            List<String> parts = new List<String>();
            for (Place p : s.places) { parts.add(p.location + ' ' + p.units.intValue()); }
            s.summary = parts.isEmpty() ? 'None in stock' : String.join(parts, ' · ');
        }
        return out;
    }

    /** Sets Units On Hand and Location on the open field actions' lots for these lot numbers from the stock records. */
    public static void refresh(Set<String> lotNumbers) {
        lotNumbers.remove(null);
        if (lotNumbers.isEmpty()) { return; }
        Map<String, Stock> st = forLots(lotNumbers);
        List<Field_Action_Lot__c> ups = new List<Field_Action_Lot__c>();
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c, Units_On_Hand__c, Location__c FROM Field_Action_Lot__c
                                      WHERE Lot_Number__c IN :lotNumbers AND Field_Action__r.Status__c != 'Closed']) {
            Stock s = st.get(l.Lot_Number__c);
            Decimal onHand = s == null ? null : s.total;
            String loc = s == null ? null : s.summary.left(255);
            if (onHand != l.Units_On_Hand__c || loc != l.Location__c) { ups.add(new Field_Action_Lot__c(Id = l.Id, Units_On_Hand__c = onHand, Location__c = loc)); }
        }
        if (!ups.isEmpty()) { update ups; }
    }

    /** Trigger: fills Lot Number from the lot record (before), then refreshes the field actions' lots (after). */
    public static void onChange(List<Lot_Stock__c> rows, Map<Id, Lot_Stock__c> beforeMap, Boolean isBefore) {
        if (isBefore) {
            Set<Id> lotIds = new Set<Id>();
            for (Lot_Stock__c r : rows) { if (r.Lot__c != null && String.isBlank(r.Lot_Number__c)) { lotIds.add(r.Lot__c); } }
            if (lotIds.isEmpty()) { return; }
            Map<Id, compliancequest__SQX_Lot_Info__c> lots = new Map<Id, compliancequest__SQX_Lot_Info__c>([SELECT Id, Name FROM compliancequest__SQX_Lot_Info__c WHERE Id IN :lotIds]);
            for (Lot_Stock__c r : rows) { if (r.Lot__c != null && String.isBlank(r.Lot_Number__c) && lots.containsKey(r.Lot__c)) { r.Lot_Number__c = lots.get(r.Lot__c).Name; } }
            return;
        }
        Set<String> names = new Set<String>();
        if (rows != null) { for (Lot_Stock__c r : rows) { names.add(r.Lot_Number__c); } }
        if (beforeMap != null) { for (Lot_Stock__c r : beforeMap.values()) { names.add(r.Lot_Number__c); } }
        refresh(names);
    }
}
