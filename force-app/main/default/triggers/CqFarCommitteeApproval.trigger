/**
 * When a CQ Approval closes, tell the Field Action Review or Field Action it belongs to.
 * Approved decides the review and starts or joins the Field Action; anything else returns it to the coordinator.
 * Runs wherever the approval was closed from, so it also covers approvals completed on CQ's own screens.
 */
trigger CqFarCommitteeApproval on cqext__CQAPR_Approval__c (after update) {
    Map<Id, String> closed = new Map<Id, String>();
    for (cqext__CQAPR_Approval__c a : Trigger.new) {
        cqext__CQAPR_Approval__c was = Trigger.oldMap.get(a.Id);
        if (a.cqext__Approval_Type__c == 'CQ Approval' && a.cqext__Status__c == 'Closed' && was.cqext__Status__c != 'Closed') {
            closed.put(a.Id, a.cqext__Approval_Status__c);
        }
    }
    if (!closed.isEmpty()) {
        CqFarCommittee.onClosed(closed);        // decides the review, which starts or joins the Field Action
        CqFieldActionScope.onClosed(closed);    // then the Field Action's scope: the review's lot, or a scope approval
    }
}
