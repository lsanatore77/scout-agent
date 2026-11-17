/**
 * Resolve a (possibly partial) lot number to its part, the way CQ links part-from-lot on its own records.
 * Lot drives the part: exact match first, then a bounded LIKE for shorthand like "0908" -> "L26-0908".
 * Returns the completed lot name and the part when the match is unambiguous; a short candidate list when
 * several lots match (review-time pick); nothing when the lot is unknown (reviewer handles, never blocks).
 */
public with sharing class CqEventLotLink {

    public class Cand {
        @AuraEnabled public String lotName;
        @AuraEnabled public Id partId;
        @AuraEnabled public String partLabel;
    }
    public class LotMatch {
        @AuraEnabled public String input;        // what was entered
        @AuraEnabled public String lotName;      // completed lot name, when unambiguous
        @AuraEnabled public Id partId;           // the part, when unambiguous
        @AuraEnabled public String partLabel;
        @AuraEnabled public Integer matches = 0; // distinct lots matched
        @AuraEnabled public List<Cand> candidates = new List<Cand>();
    }

    @AuraEnabled(cacheable=true)
    public static LotMatch resolve(String lotRaw) {
        List<LotMatch> r = resolveAll(new List<String>{ lotRaw });
        return r.isEmpty() ? new LotMatch() : r[0];
    }

    /** One match per input, in order. Exact matches are batched in one query; LIKE fallback runs per
     *  unmatched input and is skipped for large batches (keeps bulk inserts within SOQL limits). */
    public static List<LotMatch> resolveAll(List<String> raws) {
        List<String> cleaned = new List<String>();
        Set<String> exact = new Set<String>();
        for (String s : raws) {
            String v = (s == null) ? '' : s.trim();
            cleaned.add(v);
            if (v.length() >= 2) { exact.add(v); }
        }
        Boolean allowLike = cleaned.size() <= 10;

        Map<String, List<compliancequest__SQX_Lot_Info__c>> byName = new Map<String, List<compliancequest__SQX_Lot_Info__c>>();
        if (!exact.isEmpty()) {
            for (compliancequest__SQX_Lot_Info__c l : [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
                    WHERE Name IN :exact AND compliancequest__Part_Number__c != null WITH USER_MODE]) {
                if (!byName.containsKey(l.Name)) { byName.put(l.Name, new List<compliancequest__SQX_Lot_Info__c>()); }
                byName.get(l.Name).add(l);
            }
        }

        List<LotMatch> out = new List<LotMatch>();
        for (String v : cleaned) {
            LotMatch m = new LotMatch();
            m.input = v;
            out.add(m);
            if (v.length() < 2) { continue; }
            List<compliancequest__SQX_Lot_Info__c> lots = byName.get(v);
            if ((lots == null || lots.isEmpty()) && allowLike) {
                lots = [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
                    WHERE Name LIKE :('%' + v + '%') AND compliancequest__Part_Number__c != null
                    WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST LIMIT 25];
            }
            if (lots == null || lots.isEmpty()) { continue; }
            fill(m, lots);
        }
        return out;
    }

    static void fill(LotMatch m, List<compliancequest__SQX_Lot_Info__c> lots) {
        Set<String> keys = new Set<String>();
        for (compliancequest__SQX_Lot_Info__c l : lots) { keys.add(l.compliancequest__Part_Number__c); }
        Map<String, compliancequest__SQX_Part__c> parts = new Map<String, compliancequest__SQX_Part__c>();
        for (compliancequest__SQX_Part__c p : [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                WHERE compliancequest__Part_Number__c IN :keys WITH USER_MODE]) {
            parts.put(p.compliancequest__Part_Number__c, p);
        }
        Map<String, Cand> distinct = new Map<String, Cand>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            if (distinct.containsKey(l.Name)) { continue; }
            Cand c = new Cand();
            c.lotName = l.Name;
            compliancequest__SQX_Part__c p = parts.get(l.compliancequest__Part_Number__c);
            if (p != null) { c.partId = p.Id; c.partLabel = p.compliancequest__Part_Number__c + ' · ' + p.Name; }
            distinct.put(l.Name, c);
        }
        m.candidates = distinct.values();
        m.matches = m.candidates.size();
        if (m.matches == 1) {
            m.lotName = m.candidates[0].lotName;
            m.partId = m.candidates[0].partId;
            m.partLabel = m.candidates[0].partLabel;
        }
    }
}
