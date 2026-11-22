/**
 * CqSignable: how an object keeps its electronic signatures. Each object that can be signed has one, named in
 * CqEsigBridge.SIGNABLE (CqFarSignable for Field Action Review). Once CQ has checked the password, the object writes
 * the signature row that CQ's policy logs to, and its audit trail entry, in the same request as the action signed.
 */
public interface CqSignable {
    /** How many signature rows the record has, to tell whether CQ wrote one itself. */
    Integer signatureCount(Id recordId);
    /** Writes the signature row and its audit trail entry. tokenHash is a fingerprint of CQ's validation token. */
    void record(Id recordId, String action, String comment, String purpose, String tokenHash);
}
