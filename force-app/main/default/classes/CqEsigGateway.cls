/**
 * CqEsigGateway: how CqEsign asks CQ's electronic signature whether an action needs a signature, and has CQ
 * check and record one. An interface for the same reason as CqApprovalGateway: only CqEsigBridge compiles against
 * the CQ package, and it is reached by name. Saving a screen that used CQ's classes directly failed to compile.
 */
public interface CqEsigGateway {
    /** What CQ's policy asks for this action on this record. Throws when CQ cannot be asked. */
    CqEsign.Policy signFor(Id recordId, String action);
    /** CQ checks the password and records the signature. Throws AuraHandledException when it does not. */
    void sign(Id recordId, String action, String comment, String password);
}
