/**
 * CqTriageRepeat: in NC triage, finds the problem that happened before on the same part after a CAPA closed
 * (the same rule as Check History in the Investigation workspace, ranked by the Product History Review model).
 *
 * When found, CqTriageRisk raises the suggested likelihood one step and CqTriageNext suggests Escalate to CAPA.
 * A closed CAPA is never reopened: Escalate sets CQ's Initiate CAPA, Link sets the earlier CAPA as the NC's Related CAPA.
 * notSame() marks the earlier NC Not the Same Problem for this NC (Investigation Not Relevant, Nonconformance set);
 * the investigation made later honours it too.
 */
public with sharing class CqTriageRepeat {

    public class Repeat {
        @AuraEnabled public Boolean found = false;
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public Date ncDay; @AuraEnabled public String whatHappened;
        @AuraEnabled public String causeHead; @AuraEnabled public String causeNote;
        @AuraEnabled public Id capaId; @AuraEnabled public String capaName; @AuraEnabled public String capaTitle; @AuraEnabled public Date capaClosed;
        @AuraEnabled public Id efrId; @AuraEnabled public String efrName; @AuraEnabled public String efrResolution; @AuraEnabled public Date efrDate;
        @AuraEnabled public Boolean effective = false;
        @AuraEnabled public Date startDate;
        @AuraEnabled public List<CqInvestigationHistory.Dismissed> dismissed = new List<CqInvestigationHistory.Dismissed>();
    }

    /** Found once per NC per transaction: the risk, the next steps and the agent's facts all ask for it, and it runs the PHR ranking. */
    static Map<Id, Repeat> cache = new Map<Id, Repeat>();

    /** The first recurrence for the NC, or found = false. Never throws: triage carries on without it. */
    public static Repeat find(Id ncId) {
        if (ncId != null && cache.containsKey(ncId)) { return cache.get(ncId); }
        Repeat r = rank(ncId);
        if (ncId != null) { cache.put(ncId, r); }
        return r;
    }

    static Repeat rank(Id ncId) {
        Repeat r = new Repeat();
        try {
            CqInvestigationHistory.View v = CqInvestigationHistory.forNc(ncId);
            r.startDate = v.startDate;
            for (CqInvestigationHistory.Dismissed d : v.dismissed) { if (d.atTriage == true) { r.dismissed.add(d); } }
            if (v.recurrences.isEmpty()) { return r; }
            CqInvestigationHistory.Item it = v.recurrences[0];
            r.found = true;
            r.ncId = it.recordId; r.ncName = it.name; r.ncDay = it.day; r.whatHappened = it.whatHappened;
            r.causeHead = it.causeHead; r.causeNote = it.causeHead == null ? null : it.causeNote;
            r.capaId = it.capaId; r.capaName = it.capaName; r.capaTitle = it.capaTitle; r.capaClosed = it.capaClosed;
            r.efrId = it.efrId; r.efrName = it.efrName; r.efrResolution = it.efrResolution; r.efrDate = it.efrDate;
            r.effective = isEffective(it.efrResolution);
        } catch (Exception e) {
            r = new Repeat();
        }
        return r;
    }

    public static Boolean isEffective(String resolution) {
        return resolution != null && resolution.contains('Effective') && !resolution.contains('Ineffective');
    }

    @AuraEnabled
    public static Repeat getRepeat(Id recordId) { return find(recordId); }

    /** The earlier NC is not the same problem: it drops off for this NC, here and in its investigation later. */
    @AuraEnabled
    public static Repeat notSame(Id recordId, Id targetId, String targetName) {
        if (recordId == null || targetId == null) { throw new AuraHandledException('No record to mark.'); }
        try {
            insert new Investigation_Not_Relevant__c(Nonconformance__c = recordId, Record_Id__c = targetId,
                Record_Name__c = targetName == null ? null : targetName.left(80), Reason__c = 'Not the same problem (triage)');
        } catch (DmlException e) { throw new AuraHandledException('It was not saved: ' + e.getDmlMessage(0)); }
        cache.remove(recordId);
        return find(recordId);
    }

    @AuraEnabled
    public static Repeat restore(Id recordId, Id dismissedId) {
        CqInvestigationHistory.restore(dismissedId);
        cache.remove(recordId);
        return find(recordId);
    }
}
