/**
 * CqTriageRisk: suggests CQ's own Severity and Probability for a Nonconformance from data already in CQ.
 * CQ's Risk Level formula (Severity x Probability, 1 to 25) does the scoring; this class only fills the inputs.
 *
 * Likelihood: other NCs on the same part in the last 14 days. 5 or more = 5 Frequent, 2 to 4 = 3 Occasional, else 1 Improbable.
 * Severity:   first of Severity on the NC, Failure Severity on the NC, the failure code's severity, the part's risk level.
 *             If none is set, Moderate is assumed and flagged.
 * Bands:      1 to 5 Low, 6 to 12 Medium, 15 to 25 High. Complaints on the same lot make it High.
 */
public with sharing class CqTriageRisk {
    public static final Integer WINDOW_DAYS = 14;
    public static final List<String> SEV = new List<String>{ '1 - Negligible', '2 - Low', '3 - Moderate', '4 - Significant', '5 - Catastrophic' };
    public static final List<String> LIK = new List<String>{ '1 - Improbable', '2 - Remote', '3 - Occasional', '4 - Probable', '5 - Frequent' };

    public class Risk {
        @AuraEnabled public Integer count; @AuraEnabled public List<String> recent = new List<String>();
        @AuraEnabled public Integer severity; @AuraEnabled public String severityWhy; @AuraEnabled public Boolean severityAssumed = false;
        @AuraEnabled public Integer likelihood; @AuraEnabled public String likelihoodWhy;
        @AuraEnabled public Integer score; @AuraEnabled public String level;
        @AuraEnabled public Boolean escaped = false; @AuraEnabled public String escapedWhy;
    }

    public static String band(Integer score) { return score >= 15 ? 'High' : score >= 6 ? 'Medium' : 'Low'; }

    /** '4 - Significant' -> 4; null or anything else -> null. */
    private static Integer lead(String v) {
        if (String.isBlank(v) || !v.left(1).isNumeric()) { return null; }
        Integer n = Integer.valueOf(v.left(1));
        return n >= 1 && n <= 5 ? n : null;
    }

    @AuraEnabled
    public static Risk getRisk(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT Id, compliancequest__Severity__c, compliancequest__Defect_Severity__c, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Defect_Code__r.Name, compliancequest__SQX_Defect_Code__r.compliancequest__Impact__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Risk_Level__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
        Risk r = new Risk();

        // Likelihood from recent NCs on the same part (this NC is not counted)
        r.count = 0;
        if (nc.compliancequest__SQX_Part__c != null) {
            Datetime since = Datetime.now().addDays(-WINDOW_DAYS);
            for (compliancequest__SQX_Nonconformance__c o : [
                    SELECT Name FROM compliancequest__SQX_Nonconformance__c
                    WHERE compliancequest__SQX_Part__c = :nc.compliancequest__SQX_Part__c AND Id != :nc.Id AND CreatedDate >= :since
                    ORDER BY CreatedDate DESC LIMIT 200]) {
                r.count++;
                if (r.recent.size() < 5) { r.recent.add(o.Name); }
            }
        }
        r.likelihood = r.count >= 5 ? 5 : r.count >= 2 ? 3 : 1;
        r.likelihoodWhy = r.count + ' other NC(s) on this part in the last ' + WINDOW_DAYS + ' days';

        // Severity from the first place CQ already holds it
        Integer s = lead(nc.compliancequest__Severity__c);
        if (s != null) { r.severityWhy = 'Severity on the NC'; }
        if (s == null) { s = lead(nc.compliancequest__Defect_Severity__c); if (s != null) { r.severityWhy = 'Failure severity on the NC'; } }
        if (s == null && nc.compliancequest__SQX_Defect_Code__r != null) {
            s = lead(nc.compliancequest__SQX_Defect_Code__r.compliancequest__Impact__c);
            if (s != null) { r.severityWhy = 'Failure code ' + nc.compliancequest__SQX_Defect_Code__r.Name; }
        }
        if (s == null && nc.compliancequest__SQX_Part__r != null && nc.compliancequest__SQX_Part__r.compliancequest__Part_Risk_Level__c != null) {
            Integer p = nc.compliancequest__SQX_Part__r.compliancequest__Part_Risk_Level__c.intValue();
            if (p >= 1 && p <= 5) { s = p; r.severityWhy = 'Part risk level'; }
        }
        if (s == null) { s = 3; r.severityAssumed = true; r.severityWhy = 'Assumed: nothing on the NC, its failure code or the part sets it'; }
        r.severity = s;

        // Escape: complaints on the same part and lot
        if (nc.compliancequest__SQX_Part__c != null && nc.compliancequest__Lot_Number__c != null) {
            Integer c = [SELECT COUNT() FROM compliancequest__SQX_Complaint__c
                         WHERE compliancequest__SQX_Part__c = :nc.compliancequest__SQX_Part__c AND compliancequest__Lot_Number__c = :nc.compliancequest__Lot_Number__c];
            if (c > 0) { r.escaped = true; r.escapedWhy = c + ' complaint(s) on lot ' + nc.compliancequest__Lot_Number__c + ': it has reached customers'; }
        }

        r.score = r.severity * r.likelihood;
        r.level = r.escaped ? 'High' : band(r.score);
        return r;
    }

    /** Writes the confirmed values into CQ's own Severity and Probability fields. */
    @AuraEnabled
    public static void saveRisk(Id recordId, Integer severity, Integer likelihood) {
        if (severity == null || severity < 1 || severity > 5 || likelihood == null || likelihood < 1 || likelihood > 5) {
            throw new AuraHandledException('Severity and likelihood must each be 1 to 5.');
        }
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(Id = recordId);
        nc.compliancequest__Severity__c = SEV[severity - 1];
        nc.compliancequest__Probability__c = LIK[likelihood - 1];
        try {
            update nc;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not accept Severity and Probability: ' + e.getDmlMessage(0));
        }
    }
}
