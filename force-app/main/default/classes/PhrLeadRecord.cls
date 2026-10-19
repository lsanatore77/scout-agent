/**
 * PhrLeadRecord
 * One record in the lead package (a nonconformance, CAPA, change order,
 * inspection or investigation). Bound to the phrLeadPackageType renderer.
 */
@JsonAccess(serializable='always' deserializable='always')
global class PhrLeadRecord {
    @AuraEnabled global String id;
    @AuraEnabled global String recordType;
    @AuraEnabled global String name;
    @AuraEnabled global String status;
    @AuraEnabled global String title;
    // Short extra line, for example "Power Supply Board shares Capacitor, Fuse".
    @AuraEnabled global String note;
    // Red, Yellow or Grey: how many of the three criteria were met.
    @AuraEnabled global String colour;
    // 0 to 100, strength inside the colour.
    @AuraEnabled global Integer relevance;
    // Set-aside rows only: why the record was set aside.
    @AuraEnabled global String reason;
}
