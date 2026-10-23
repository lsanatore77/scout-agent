/**
 * PhrDescriptionCheck
 * --------------------
 * Reads a complaint's Description (and Description As Reported) and points out details the text
 * mentions that are missing from the complaint's fields, or that differ from them:
 *
 *   lot or serial number  -> Lot/Serial Number
 *   part, catalog, model  -> Part, Catalog Number, Model Number
 *   a date                -> Occurrence Date
 *   a quantity            -> Complaint Quantity
 *   a patient or injury   -> Complaint Patient Data
 *
 * Plain pattern rules, no AI: the same text always gives the same suggestions. Read only.
 * These are suggestions for the user to check, never changes.
 */
public with sharing class PhrDescriptionCheck {

    public class Finding {
        public String label;
        public Boolean isGap;
        public String detail;
        Finding(String label, Boolean isGap, String detail) {
            this.label = label;
            this.isGap = isGap;
            this.detail = detail;
        }
    }

    // A code must contain a digit, so ordinary words after "lot" or "part" are not picked up.
    static final String CODE = '([A-Za-z0-9][A-Za-z0-9\\-_/.]*[0-9][A-Za-z0-9\\-_/]*)';
    static final String NUM_WORD = '\\s*(?:number|no\\.?|num\\.?|#)?\\s*[:#=\\-]?\\s*';
    static final Pattern LOT = Pattern.compile('(?i)\\b(?:lot|batch|serial)' + NUM_WORD + CODE);
    static final Pattern PART = Pattern.compile('(?i)\\b(?:part|catalog|catalogue|cat\\.|model|ref\\.?|reference|item|sku|product code)' + NUM_WORD + CODE);
    static final String MONTH = '(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
    static final Pattern DATE_TEXT = Pattern.compile('(?i)\\b(\\d{1,2}[/\\-.]\\d{1,2}[/\\-.]\\d{2,4}|\\d{4}-\\d{2}-\\d{2}|'
        + MONTH + '\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?(?:,?\\s+\\d{4})?|\\d{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?' + MONTH + '(?:,?\\s+\\d{4})?)\\b');
    static final Pattern QUANTITY = Pattern.compile('(?i)\\b(\\d{1,6})\\s+(?:units?|pieces?|pcs|devices?|items?|boxes|cases|parts|bottles|kits|pumps|catheters|syringes|samples)\\b');
    static final Pattern PATIENT = Pattern.compile('(?i)\\b(patient|injur(?:y|ies|ed)|hurt|harm(?:ed)?|hospitali[sz](?:ed|ation)|hospital|burn(?:ed|s)?|bleed(?:ing)?|laceration|death|died|surgery|surgical|adverse event|medical attention|emergency room)\\b');

    /** One finding per kind of detail the description mentions; an "all good" line when nothing is missing. */
    public static List<Finding> check(compliancequest__SQX_Complaint__c c) {
        List<Finding> out = new List<Finding>();
        String text = textOf(c);
        if (String.isBlank(text)) {
            out.add(new Finding('Description', true, 'The complaint has no description, so it could not be checked for missing details.'));
            return out;
        }

        String lot = firstGroup(LOT, text);
        if (lot != null) {
            String have = c.compliancequest__Lot_Number__c;
            if (String.isBlank(have)) {
                out.add(gap('Description: lot or serial', 'The description mentions ' + lot + ', but Lot/Serial Number is empty.'));
            } else if (!same(have, lot)) {
                out.add(gap('Description: lot or serial', 'The description mentions ' + lot + ', but the complaint has ' + have + '. Check which is right.'));
            }
        }

        String part = firstGroup(PART, text);
        if (part != null && !same(part, lot)) {
            String partNumber = c.compliancequest__SQX_Part__r == null ? null : c.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            Boolean known = same(part, partNumber) || same(part, c.compliancequest__Catalog_Number__c) || same(part, c.compliancequest__Model_Name__c);
            if (c.compliancequest__SQX_Part__c == null && String.isBlank(c.compliancequest__Catalog_Number__c) && String.isBlank(c.compliancequest__Model_Name__c)) {
                out.add(gap('Description: part', 'The description mentions ' + part + ', but no Part, Catalog Number or Model Number is set.'));
            } else if (!known) {
                out.add(gap('Description: part', 'The description mentions ' + part + ', which does not match the Part'
                    + (String.isBlank(partNumber) ? '' : ' (' + partNumber + ')') + ', Catalog Number or Model Number. Check which is right.'));
            }
        }

        String dt = firstGroup(DATE_TEXT, text);
        if (dt != null && c.compliancequest__Occurrence_Date__c == null) {
            out.add(gap('Description: date', 'The description mentions a date (' + dt + '), but Occurrence Date is empty.'));
        }

        Matcher q = QUANTITY.matcher(text);
        if (q.find()) {
            Decimal n = Decimal.valueOf(q.group(1));
            Decimal have = c.compliancequest__Complaint_Quantity__c;
            if (have == null) {
                out.add(gap('Description: quantity', 'The description mentions ' + q.group(0).trim() + ', but Complaint Quantity is empty.'));
            } else if (have != n) {
                out.add(gap('Description: quantity', 'The description mentions ' + q.group(0).trim() + ', but Complaint Quantity is ' + have.stripTrailingZeros().toPlainString() + '. Check which is right.'));
            }
        }

        List<String> words = allGroups(PATIENT, text, 3);
        if (!words.isEmpty() && c.compliancequest__SQX_Patient_Data__c == null) {
            out.add(gap('Description: patient or injury', 'The description mentions ' + quoteList(words)
                + ', but no Complaint Patient Data is linked. Check whether patient details and reportability need to be recorded.'));
        }

        if (out.isEmpty()) {
            out.add(new Finding('Description', false, 'Nothing the description mentions is missing from the complaint.'));
        }
        return out;
    }

    static Finding gap(String label, String detail) {
        return new Finding(label, true, detail);
    }

    static String textOf(compliancequest__SQX_Complaint__c c) {
        String a = c.compliancequest__Description__c == null ? '' : c.compliancequest__Description__c;
        String b = c.compliancequest__Description_As_Reported__c == null ? '' : c.compliancequest__Description_As_Reported__c;
        if (String.isBlank(b) || a.contains(b)) { return a; }
        if (String.isBlank(a) || b.contains(a)) { return b; }
        return a + '\n' + b;
    }

    @TestVisible
    static String firstGroup(Pattern p, String text) {
        Matcher m = p.matcher(text);
        return m.find() ? m.group(1).replaceAll('[.,;:]+$', '') : null;
    }

    static List<String> allGroups(Pattern p, String text, Integer max) {
        List<String> out = new List<String>();
        Set<String> seen = new Set<String>();
        Matcher m = p.matcher(text);
        while (m.find() && out.size() < max) {
            String w = m.group(1).toLowerCase();
            if (seen.add(w)) { out.add(w); }
        }
        return out;
    }

    static String quoteList(List<String> words) {
        List<String> q = new List<String>();
        for (String w : words) { q.add('"' + w + '"'); }
        return String.join(q, ', ');
    }

    /** Same code, ignoring case, spaces and dashes; or one contains the other. */
    @TestVisible
    static Boolean same(String a, String b) {
        if (String.isBlank(a) || String.isBlank(b)) { return false; }
        String x = a.toUpperCase().replaceAll('[\\s\\-_/.]', '');
        String y = b.toUpperCase().replaceAll('[\\s\\-_/.]', '');
        return x == y || x.contains(y) || y.contains(x);
    }
}
