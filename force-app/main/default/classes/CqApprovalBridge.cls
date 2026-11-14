/**
 * CqApprovalBridge: the one class that calls CQ's approval engine (cqext.CQAPR_Approval_API).
 * CqFarCommittee creates it by name through CqApprovalGateway, so no other class depends on the CQ package's Apex.
 */
public with sharing class CqApprovalBridge implements CqApprovalGateway {
    public void submit(SObject record, cqext__CQAPR_Approval__c approval, List<cqext__CQAPR_Approval_Step__c> steps) {
        cqext.CQAPR_Submission_Request q = new cqext.CQAPR_Submission_Request();
        q.record = record; q.approval = approval; q.steps = steps;
        new cqext.CQAPR_Approval_API().submitForApproval(q);
    }
}
