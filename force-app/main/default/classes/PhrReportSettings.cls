/**
 * PhrReportSettings
 * ------------------
 * Reads the PHR Report Setting custom metadata record named Default.
 *
 * The record is read with a dynamic query, so this class compiles and runs even in an org where the
 * custom metadata type has not been deployed yet. If the type or the record is missing, or a value
 * is blank, the defaults below apply (window off, all summary sections on).
 */
public with sharing class PhrReportSettings {

    public class Values {
        public Boolean useWindow = false;
        public Integer daysAfter = 90;
        public Integer daysBefore = 30;
        public Boolean summaryOverview = true;
        public Boolean summaryAssociatedItems = true;   // the "Summary: Product History Review" checkbox
        public Boolean summaryAnalysis = true;
    }

    @TestVisible private static Values testValues;

    public static Values get() {
        if (testValues != null) { return testValues; }
        Values v = new Values();
        try {
            List<SObject> rows = Database.query(
                'SELECT Use_Manufacture_Date_Window__c, Days_After_Manufacture__c, Days_Before_Manufacture__c, '
                + 'Summary_Complaint_Overview__c, Summary_Product_History_Review__c, Summary_Analysis_and_Next_Steps__c '
                + 'FROM PHR_Report_Setting__mdt WHERE DeveloperName = \'Default\' LIMIT 1');
            if (rows.isEmpty()) { return v; }
            SObject r = rows[0];
            v.useWindow = flag(r, 'Use_Manufacture_Date_Window__c', v.useWindow);
            v.daysAfter = whole(r, 'Days_After_Manufacture__c', v.daysAfter);
            v.daysBefore = whole(r, 'Days_Before_Manufacture__c', v.daysBefore);
            v.summaryOverview = flag(r, 'Summary_Complaint_Overview__c', v.summaryOverview);
            v.summaryAssociatedItems = flag(r, 'Summary_Product_History_Review__c', v.summaryAssociatedItems);
            v.summaryAnalysis = flag(r, 'Summary_Analysis_and_Next_Steps__c', v.summaryAnalysis);
        } catch (Exception ex) {
            // Type not deployed yet, or no access: keep the defaults.
        }
        return v;
    }

    private static Boolean flag(SObject r, String field, Boolean fallback) {
        Object o = r.get(field);
        return o == null ? fallback : (Boolean) o;
    }

    private static Integer whole(SObject r, String field, Integer fallback) {
        Object o = r.get(field);
        if (o == null) { return fallback; }
        Integer n = Integer.valueOf(Math.round(Double.valueOf(String.valueOf(o))));
        return n < 0 ? 0 : n;
    }

    /** First moment of the window, or a very early date when the window is not in use. */
    public static Datetime windowStart(Values v, Date manufactureDate) {
        if (v == null || !v.useWindow || manufactureDate == null) { return Datetime.newInstance(1900, 1, 1); }
        return Datetime.newInstance(manufactureDate.addDays(-v.daysBefore), Time.newInstance(0, 0, 0, 0));
    }

    /** First moment AFTER the window (use with less-than), or a very late date when not in use. */
    public static Datetime windowEnd(Values v, Date manufactureDate) {
        if (v == null || !v.useWindow || manufactureDate == null) { return Datetime.newInstance(2999, 1, 1); }
        return Datetime.newInstance(manufactureDate.addDays(v.daysAfter + 1), Time.newInstance(0, 0, 0, 0));
    }
}
