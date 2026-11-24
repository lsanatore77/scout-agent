/**
 * CqFieldActionDepth: who a field action lists, from How Far It Goes (Strategy) and each customer's kind.
 *  - Distributor and Direct Customer: we shipped to them. They are listed at every depth, because nobody else will
 *    tell a customer who bought direct.
 *  - Customer: a distributor shipped to them (from the distributor's own shipping list). Listed at Hospital and
 *    Patient depth; at Distributor depth the distributor deals with its own stock and they are left off.
 * A customer with no kind (added by hand) is always listed.
 */
public with sharing class CqFieldActionDepth {
    public static final String DISTRIBUTOR = 'Distributor';
    public static final String DIRECT = 'Direct Customer';
    public static final String CUSTOMER = 'Customer';

    /** Whether a customer of this kind is on the list at this depth. */
    public static Boolean listed(String depth, String kind) {
        return !(depth == DISTRIBUTOR && kind == CUSTOMER);
    }
    /** Whether this depth lists the distributors' own customers. */
    public static Boolean listsCustomers(String depth) { return depth != DISTRIBUTOR; }

    /** The kind of a customer we shipped to, from the Customer Type on its Account. */
    public static String kindOf(String customerType) { return customerType == DISTRIBUTOR ? DISTRIBUTOR : DIRECT; }

}
