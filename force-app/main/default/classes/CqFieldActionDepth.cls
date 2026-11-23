/**
 * CqFieldActionDepth: who a field action reaches, from How Far It Goes (Strategy) and the Customer Type on each Account.
 *  - Distributor: only the distributors that received the lots. Hospitals and clinics that bought direct are left out.
 *  - Hospital or Patient: every customer that received the lots; distributors pass the notice on to their own customers.
 * A customer whose Account has no Customer Type, or one added by hand, is always included, so the list never comes up
 * empty just because Accounts are not typed yet.
 */
public with sharing class CqFieldActionDepth {
    public static final String DISTRIBUTOR = 'Distributor';

    /** Whether a customer of this type is notified at this depth. */
    public static Boolean includes(String depth, String customerType, Id accountId) {
        if (depth != DISTRIBUTOR || accountId == null || String.isBlank(customerType)) { return true; }
        return customerType == DISTRIBUTOR;
    }
    /** Included only because its Account has no Customer Type, at a depth that filters by type. */
    public static Boolean untyped(String depth, String customerType, Id accountId) {
        return depth == DISTRIBUTOR && accountId != null && String.isBlank(customerType);
    }

    /** CQ.AI's line on who the depth leaves out, and who is included only because they have no type; null when neither. */
    public static String leftOutLine(String depth, Map<String, Integer> outByType, Integer untypedCount) {
        List<String> parts = new List<String>();
        Integer out = 0;
        for (String t : new List<String>{ 'Hospital', 'Clinic' }) {
            Integer n = outByType.get(t);
            if (n == null || n == 0) { continue; }
            out += n;
            parts.add(n + ' ' + t.toLowerCase() + (n == 1 ? '' : 's'));
        }
        List<String> s = new List<String>();
        if (out > 0) {
            s.add(String.join(parts, ' and ') + ' bought these lots direct and ' + (out == 1 ? 'is' : 'are') + ' not notified at '
                + depth.toLowerCase() + ' level. Choose Hospital in Strategy to include ' + (out == 1 ? 'it' : 'them') + '.');
        }
        if (untypedCount != null && untypedCount > 0) {
            s.add(untypedCount + ' customer' + (untypedCount == 1 ? ' has' : 's have') + ' no Customer Type on the Account, so '
                + (untypedCount == 1 ? 'it is' : 'they are') + ' included.');
        }
        return s.isEmpty() ? null : String.join(s, ' ');
    }
}
