/**
 * PhrLeadSelectController
 * --------------------------
 * Backs the phrLeadSelect tick-box component shown in the agent conversation.
 * Returns every record found for the complaint (Top, Next, Set aside) with the
 * default ticks: everything worth reviewing that is not already on the PHR is
 * ticked, set-aside records are not, and records already on the PHR are locked.
 * Read only.
 */
public with sharing class PhrLeadSelectController {

    public class Candidate implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String recordType;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String tier;
        @AuraEnabled public String colour;
        @AuraEnabled public Integer relevance;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean alreadyAdded;
        @AuraEnabled public Boolean selected;

        public Integer compareTo(Object o) {
            Candidate other = (Candidate) o;
            Integer a = rank(tier);
            Integer b = rank(other.tier);
            if (a != b) { return a < b ? -1 : 1; }
            Integer ra = relevance == null ? -1 : relevance;
            Integer rb = other.relevance == null ? -1 : other.relevance;
            if (ra != rb) { return ra > rb ? -1 : 1; }
            String na = recordNumber == null ? '' : recordNumber;
            String nb = other.recordNumber == null ? '' : other.recordNumber;
            return na.compareTo(nb);
        }
    }

    public class Candidates {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String recordId;
        @AuraEnabled public List<Candidate> rows = new List<Candidate>();
    }

    @TestVisible
    private static Integer rank(String tier) {
        if (tier == 'Top') { return 0; }
        if (tier == 'Set aside') { return 2; }
        return 1;
    }

    @AuraEnabled
    public static Candidates getCandidates(String recordId, String lotNumber) {
        Candidates out = new Candidates();
        try {
            Id rid = Id.valueOf(recordId);
            out.recordId = String.valueOf(rid);
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(rid, lotNumber);
            if (!d.success) {
                out.success = false;
                out.errorMessage = d.errorMessage;
                return out;
            }
            out.complaintName = d.complaintName;

            List<PhrQmsPanelController.Row> worth = new List<PhrQmsPanelController.Row>();
            worth.addAll(d.nonconformances);
            worth.addAll(d.capas);
            worth.addAll(d.changeOrders);
            worth.addAll(d.inspections);
            worth.addAll(d.investigations);
            List<PhrQmsPanelController.Row> all = new List<PhrQmsPanelController.Row>(worth);
            all.addAll(d.setAside);
            Map<Id, String> titles = loadTitles(all);

            Set<Id> setAsideIds = new Set<Id>();
            for (PhrQmsPanelController.Row r : d.setAside) { setAsideIds.add(r.id); }

            for (PhrQmsPanelController.Row r : all) {
                Candidate c = new Candidate();
                c.id = String.valueOf(r.id);
                c.recordNumber = r.name;
                c.recordType = String.isBlank(r.recordType) ? typeLabel(r.id) : r.recordType;
                c.title = titles.get(r.id);
                c.status = r.status;
                Boolean isSetAside = setAsideIds.contains(r.id);
                c.tier = isSetAside ? 'Set aside' : (String.isBlank(r.tier) ? 'Next' : r.tier);
                c.colour = r.colour;
                c.relevance = r.relevance;
                c.reason = isSetAside ? r.reason : null;
                c.alreadyAdded = r.alreadyAdded == true;
                c.selected = c.alreadyAdded || !isSetAside;
                out.rows.add(c);
            }
            out.rows.sort();
        } catch (Exception ex) {
            out.success = false;
            out.errorMessage = 'Could not load the records: ' + ex.getMessage();
        }
        return out;
    }

    private static String typeLabel(Id i) {
        String t = String.valueOf(i.getSobjectType());
        if (t == 'compliancequest__SQX_Nonconformance__c') { return 'Nonconformance'; }
        if (t == 'compliancequest__SQX_CAPA__c') { return 'CAPA'; }
        if (t == 'compliancequest__SQX_Change_Order__c') { return 'Change Order'; }
        if (t == 'compliancequest__SQX_Inspection__c') { return 'Inspection'; }
        if (t == 'compliancequest__SQX_Investigation__c') { return 'Investigation'; }
        return t;
    }

    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
            else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [
            SELECT Id, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc
        ]) { m.put(x.Id, x.compliancequest__NC_Title__c); }
        for (compliancequest__SQX_CAPA__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capa
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        for (compliancequest__SQX_Change_Order__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :co
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        return m;
    }
}
