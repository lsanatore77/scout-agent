/**
 * PhrReportSettings
 * ------------------
 * Reads the PHR Report Setting custom metadata record: the one named Default if there is one,
 * otherwise the first record (so the record can be renamed). Its Label is the report title when
 * PHR Report Title is blank.
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
        public String templateDocument;   // Document Number or record Id of the report template controlled document; blank = PHR-TEMPLATE-001
        public String phrReportTitle;            // report title when run from a complaint or PHR; blank = DEFAULT_PHR_TITLE
        public String investigationReportTitle;  // report title when run from an investigation; blank = DEFAULT_INVESTIGATION_TITLE
        public String label;                     // the setting record's Label; used as the report title when PHR Report Title is blank
    }

    public static final String DEFAULT_PHR_TITLE = 'Product History Report';
    public static final String DEFAULT_INVESTIGATION_TITLE = 'Customer Report';
    /** The report file's earliest name; files with it are still found, and renamed on their next version. */
    public static final String OLDEST_PHR_TITLE = 'Product History Review Report';

    /** Title of the report (and its file) when run from a complaint or PHR. */
    public static String phrTitle() {
        Values v = get();
        if (String.isNotBlank(v.phrReportTitle)) { return v.phrReportTitle.trim(); }
        // A renamed setting record names the report, for example "Complaint Summary Report".
        if (String.isNotBlank(v.label) && v.label.trim() != 'Default') { return v.label.trim(); }
        return DEFAULT_PHR_TITLE;
    }

    /** Title of the report (and its file) when run from an investigation. */
    public static String investigationTitle() {
        String t = get().investigationReportTitle;
        return String.isBlank(t) ? DEFAULT_INVESTIGATION_TITLE : t.trim();
    }

    /** Every name the complaint's report file may have: the current title first, then the earlier ones. */
    public static List<String> phrTitles() {
        return distinct(new List<String>{ phrTitle(), DEFAULT_PHR_TITLE, OLDEST_PHR_TITLE });
    }

    /** Every name the investigation's report file may have. */
    public static List<String> investigationTitles() {
        return distinct(new List<String>{ investigationTitle(), DEFAULT_INVESTIGATION_TITLE });
    }

    private static List<String> distinct(List<String> names) {
        List<String> out = new List<String>();
        for (String n : names) { if (!out.contains(n)) { out.add(n); } }
        return out;
    }

    @TestVisible private static Values testValues;
    /** Read once per transaction: the report asks for the settings many times. */
    private static Values cached;

    public static Values get() {
        if (testValues != null) { return testValues; }
        if (cached != null) { return cached; }
        Values v = new Values();
        recordName = pickRecord(v);
        if (recordName == null) { cached = v; return v; }
        String name = recordName;
        try {
            List<SObject> rows = Database.query(
                'SELECT Use_Manufacture_Date_Window__c, Days_After_Manufacture__c, Days_Before_Manufacture__c, '
                + 'Summary_Complaint_Overview__c, Summary_Product_History_Review__c, Summary_Analysis_and_Next_Steps__c '
                + 'FROM PHR_Report_Setting__mdt WHERE DeveloperName = :name LIMIT 1');
            if (!rows.isEmpty()) {
            SObject r = rows[0];
            v.useWindow = flag(r, 'Use_Manufacture_Date_Window__c', v.useWindow);
            v.daysAfter = whole(r, 'Days_After_Manufacture__c', v.daysAfter);
            v.daysBefore = whole(r, 'Days_Before_Manufacture__c', v.daysBefore);
            v.summaryOverview = flag(r, 'Summary_Complaint_Overview__c', v.summaryOverview);
            v.summaryAssociatedItems = flag(r, 'Summary_Product_History_Review__c', v.summaryAssociatedItems);
            v.summaryAnalysis = flag(r, 'Summary_Analysis_and_Next_Steps__c', v.summaryAnalysis);
            }
        } catch (Exception ex) {
            // Type not deployed yet, or no access: keep the defaults.
        }
        v.templateDocument = readTemplateDocument();
        v.phrReportTitle = readText('PHR_Report_Title__c');
        v.investigationReportTitle = readText('Investigation_Report_Title__c');
        cached = v;
        return v;
    }

    // DeveloperName of the setting record in use (bound in the queries below).
    private static String recordName;

    /** The record named Default if there is one, otherwise the first record by name; null when there is none. */
    private static String pickRecord(Values v) {
        try {
            List<SObject> rows = Database.query('SELECT DeveloperName, MasterLabel FROM PHR_Report_Setting__mdt ORDER BY DeveloperName LIMIT 50');
            if (rows.isEmpty()) { return null; }
            SObject chosen = rows[0];
            for (SObject r : rows) {
                if (String.valueOf(r.get('DeveloperName')) == 'Default') { chosen = r; break; }
            }
            v.label = String.valueOf(chosen.get('MasterLabel'));
            return String.valueOf(chosen.get('DeveloperName'));
        } catch (Exception ex) {
            return null;
        }
    }

    /** Read on its own so the other settings still work in an org where this field is not deployed yet. */
    private static String readTemplateDocument() {
        String name = recordName;
        try {
            List<SObject> rows = Database.query(
                'SELECT Template_Controlled_Document__c FROM PHR_Report_Setting__mdt WHERE DeveloperName = :name LIMIT 1');
            if (rows.isEmpty() || rows[0].get('Template_Controlled_Document__c') == null) { return null; }
            String t = String.valueOf(rows[0].get('Template_Controlled_Document__c')).trim();
            return String.isBlank(t) ? null : t;
        } catch (Exception ex) {
            return null;
        }
    }

    /** One text field of the setting record, read on its own so a field not deployed yet only loses itself. */
    private static String readText(String field) {
        String name = recordName;
        try {
            List<SObject> rows = Database.query(
                'SELECT ' + field + ' FROM PHR_Report_Setting__mdt WHERE DeveloperName = :name LIMIT 1');
            if (rows.isEmpty() || rows[0].get(field) == null) { return null; }
            String t = String.valueOf(rows[0].get(field)).trim();
            return String.isBlank(t) ? null : t;
        } catch (Exception ex) {
            return null;
        }
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
