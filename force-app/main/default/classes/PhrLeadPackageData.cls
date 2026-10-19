/**
 * PhrLeadPackageData
 * Output of the lead package: what is worth reviewing for a complaint. This is
 * the top-level type the phrLeadPackageType Custom Lightning Type binds to.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrLeadPackageData {
    // Plain sentence above the tables (counts, lot note, what was set aside).
    @AuraEnabled global String intro;
    // High, Medium, Low or None, and the 0 to 100 overall score.
    @AuraEnabled global String overallRating;
    @AuraEnabled global Integer overallScore;
    @AuraEnabled global List<PhrLeadSection> sections = new List<PhrLeadSection>();
    // Records set aside, each with a reason. Shown on request.
    @AuraEnabled global List<PhrLeadRecord> setAside = new List<PhrLeadRecord>();
    @AuraEnabled global Boolean success;
    @AuraEnabled global String errorMessage;
}
