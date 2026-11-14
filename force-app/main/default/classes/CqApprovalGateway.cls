/**
 * CqApprovalGateway: how CqFarCommittee hands a submission to CQ's approval engine.
 * It is an interface so that nothing else compiles against the CQ package: the only class that does is
 * CqApprovalBridge, and it is reached by name. Saving a trigger or a screen that used the CQ classes directly failed to compile.
 */
public interface CqApprovalGateway {
    void submit(SObject record, cqext__CQAPR_Approval__c approval, List<cqext__CQAPR_Approval_Step__c> steps);
}
