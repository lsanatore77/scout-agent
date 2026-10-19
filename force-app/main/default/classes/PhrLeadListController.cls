/**
 * PhrLeadListController
 * -----------------------
 * Backs the phrLeadLists component on the Product History Review page: the
 * three tier lists (Top, Next, Set aside) of PHR Lead rows, and adding leads
 * that were stored as Not added.
 */
public with sharing class PhrLeadListController {

    public class LeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String tier;
        @AuraEnabled public String recordId;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String recordType;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String colour;
        @AuraEnabled public Integer relevance;
        @AuraEnabled public String match;
        @AuraEnabled public String relatedBy;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean added;
        @AuraEnabled public String addedLabel;
        @AuraEnabled public String link;
    }

    public class AddResult {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String message;
        @AuraEnabled public Integer added = 0;
    }

    /** Every lead on the PHR: NC, CAPA and Change Order first, then the rest, best first inside each group. */
    @AuraEnabled
    public static List<LeadRow> getLeads(Id phrId) {
        List<LeadRow> priority = new List<LeadRow>();
        List<LeadRow> others = new List<LeadRow>();
        for (PHR_Lead__c l : [
            SELECT Id, Tier__c, Record_Id__c, Record_Number__c, Record_Type__c, Record_Title__c, Record_Status__c,
                   Colour__c, Relevance__c, Related_By__c, Reason__c, Added__c
            FROM PHR_Lead__c
            WHERE PHR__c = :phrId
            ORDER BY Relevance__c DESC NULLS LAST, Record_Number__c
            LIMIT 2000
        ]) {
            LeadRow r = new LeadRow();
            r.id = l.Id;
            r.tier = l.Tier__c;
            r.recordId = l.Record_Id__c;
            r.recordNumber = l.Record_Number__c;
            r.recordType = l.Record_Type__c;
            r.title = l.Record_Title__c;
            r.status = l.Record_Status__c;
            r.colour = l.Colour__c;
            r.relevance = l.Relevance__c == null ? null : Integer.valueOf(l.Relevance__c);
            r.match = String.isBlank(l.Colour__c) ? '' : l.Colour__c + (r.relevance == null ? '' : ' (' + r.relevance + ')');
            r.relatedBy = l.Related_By__c;
            r.reason = l.Reason__c;
            r.added = l.Added__c == true;
            r.addedLabel = r.added ? 'Added' : 'Not added';
            r.link = '/' + l.Record_Id__c;
            if (isPriorityType(r.recordType)) {
                priority.add(r);
            } else {
                others.add(r);
            }
        }
        // Nonconformances, CAPAs and Change Orders first; each group keeps the
        // relevance order from the query. With no such records the order is unchanged.
        List<LeadRow> rows = new List<LeadRow>(priority);
        rows.addAll(others);
        return rows;
    }

    @TestVisible
    private static Boolean isPriorityType(String recordType) {
        return recordType == 'Nonconformance' || recordType == 'CAPA' || recordType == 'Change Order';
    }

    /** Adds the chosen leads as formal records and marks them Added. */
    @AuraEnabled
    public static AddResult addLeads(Id phrId, List<Id> leadIds) {
        AddResult res = new AddResult();
        try {
            if (leadIds == null || leadIds.isEmpty()) {
                res.success = false;
                res.message = 'Select at least one record to add.';
                return res;
            }
            List<PHR_Lead__c> leads = [
                SELECT Id, Record_Id__c, Added__c FROM PHR_Lead__c
                WHERE PHR__c = :phrId AND Id IN :leadIds AND Added__c = false
            ];
            List<Id> nc = new List<Id>();
            List<Id> capa = new List<Id>();
            List<Id> co = new List<Id>();
            List<Id> insp = new List<Id>();
            List<Id> inv = new List<Id>();
            for (PHR_Lead__c l : leads) {
                Id rid;
                try { rid = Id.valueOf(l.Record_Id__c); } catch (Exception e) { continue; }
                String t = String.valueOf(rid.getSobjectType());
                if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(rid); }
                else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(rid); }
                else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(rid); }
                else if (t == 'compliancequest__SQX_Inspection__c') { insp.add(rid); }
                else if (t == 'compliancequest__SQX_Investigation__c') { inv.add(rid); }
            }
            PhrQmsPanelController.CreateResult cr = PhrQmsPanelController.createRelatedRecords(
                phrId, nc, capa, co, insp, inv);
            if (!cr.success) {
                res.success = false;
                res.message = cr.message;
                return res;
            }
            for (PHR_Lead__c l : leads) {
                l.Added__c = true;
                l.Added_On__c = System.now();
            }
            update leads;
            res.added = leads.size();
            res.message = 'Added ' + leads.size() + ' record(s) to the Product History Review.';
        } catch (Exception ex) {
            res.success = false;
            res.message = ex.getMessage();
        }
        return res;
    }
}
