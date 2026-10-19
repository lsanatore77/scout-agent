/**
 * AssociatedItemsReportData
 * ----------------------------
 * Top-level, global, @JsonAccess-serializable data class -- this is the
 * actual type the associatedItemsReportType Custom Lightning Type's
 * schema.json binds to (@apexClassType/c__AssociatedItemsReportData).
 *
 * Renamed from the old nested "Response" inner class: Salesforce's
 * Apex-based Custom Lightning Types require the bound class to be
 * top-level (not nested inside the action class), global, annotated
 * @JsonAccess(serializable='always' deserializable='always'), with its
 * fields marked @AuraEnabled rather than @InvocableVariable. The
 * @InvocableVariable-based action schema (AssociatedItemsReportAction.
 * ActionResponse) still wraps this class as its single output field, but
 * the two annotation sets serve different layers: @InvocableVariable is
 * what Agent Builder shows as the action's input/output; @AuraEnabled +
 * @JsonAccess is what the Custom Lightning Type renderer needs to
 * serialize this object into the associatedItemsReport LWC.
 */
@JsonAccess(serializable='always' deserializable='always')
global class AssociatedItemsReportData {
    @AuraEnabled global String reportTitle;
    @AuraEnabled global String generatedAt;
    // Lot Number taken from the Complaint (blank when none / not applicable).
    @AuraEnabled global String lotNumber;
    // Display text for the Created Date range that was applied (blank when none).
    @AuraEnabled global String dateRangeLabel;
    @AuraEnabled global Boolean hasPrimaryPart;
    @AuraEnabled global AssociatedItemsPartInfo primaryPart;
    @AuraEnabled global List<AssociatedItemsAssemblyInfo> assemblies = new List<AssociatedItemsAssemblyInfo>();
    @AuraEnabled global List<AssociatedItemsLineItemInfo> assemblyLineItems = new List<AssociatedItemsLineItemInfo>();
    @AuraEnabled global List<AssociatedItemsRecordInfo> nonconformances = new List<AssociatedItemsRecordInfo>();
    @AuraEnabled global List<AssociatedItemsRecordInfo> capas = new List<AssociatedItemsRecordInfo>();
    @AuraEnabled global List<AssociatedItemsRecordInfo> changeOrders = new List<AssociatedItemsRecordInfo>();
    @AuraEnabled global List<AssociatedItemsRecordInfo> inspections = new List<AssociatedItemsRecordInfo>();
    // Investigations on the same Part (or component Part) or Lot Number, excluding
    // the Complaint's own Investigations.
    @AuraEnabled global List<AssociatedItemsInvestigationInfo> investigations = new List<AssociatedItemsInvestigationInfo>();
    @AuraEnabled global Boolean success;
    @AuraEnabled global String errorMessage;
}
