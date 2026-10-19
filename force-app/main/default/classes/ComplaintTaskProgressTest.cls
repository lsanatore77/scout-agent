@isTest
private class ComplaintTaskProgressTest {

    private static compliancequest__SQX_Complaint_Task__c task(Decimal step, String status, Date due) {
        return new compliancequest__SQX_Complaint_Task__c(
            compliancequest__Step__c = step,
            compliancequest__Status__c = status,
            compliancequest__Due_Date__c = due
        );
    }

    @isTest
    static void summarize_countsProgressAndOverdueForAnyStatus() {
        Date today = Date.newInstance(2026, 10, 9);
        List<compliancequest__SQX_Complaint_Task__c> tasks = new List<compliancequest__SQX_Complaint_Task__c>{
            task(1, 'Complete', today.addDays(-30)),
            task(2, 'Open', today.addDays(-3)),
            task(3, 'Draft', today.addDays(-1)),
            task(4, 'Ready', today.addDays(5)),
            task(5, 'Under Submission', null)
        };
        ComplaintTaskProgress.Summary s = ComplaintTaskProgress.summarize(tasks, today);

        System.assertEquals(5, s.total, 'total');
        System.assertEquals(1, s.completeCount, 'complete');
        System.assertEquals(2, s.overdueCount, 'a Draft and an Open task are both overdue; Complete never is');
        System.assertEquals(20, s.completePct, 'percent complete');
        System.assertEquals(80, s.remainingPct, 'percent remaining');
        System.assertEquals('1 of 5 complete', s.progressLabel, 'label');
        System.assertEquals('2 overdue', s.overdueLabel, 'overdue label');
        System.assertEquals(5, s.rows.size(), 'rows');
        System.assertEquals(true, s.rows[1].overdue, 'open past due');
        System.assertEquals(3, s.rows[1].daysOverdue, 'days overdue');
        System.assertEquals('3 days overdue', s.rows[1].overdueLabel, 'overdue text');
        System.assertEquals('1 day overdue', s.rows[2].overdueLabel, 'singular');
        System.assertEquals(false, s.rows[3].overdue, 'future due date');
        System.assertEquals(false, s.rows[4].overdue, 'no due date');
        System.assertEquals(5, s.counts.size(), 'one count per standard status');
    }

    @isTest
    static void summarize_emptyComplaint() {
        ComplaintTaskProgress.Summary s = ComplaintTaskProgress.summarize(
            new List<compliancequest__SQX_Complaint_Task__c>(), Date.today());
        System.assertEquals(0, s.total, 'no tasks');
        System.assertEquals(0, s.completePct, 'no percent');
        System.assertEquals('0 of 0 complete', s.progressLabel, 'label');
        System.assertEquals(null, s.overdueLabel, 'no overdue');
    }

    @isTest
    static void getForComplaint_withoutComplaintReturnsEmptySummary() {
        ComplaintTaskProgress.Summary s = ComplaintTaskProgress.getForComplaint(null, AccessLevel.SYSTEM_MODE);
        System.assertEquals(0, s.total, 'null complaint');
    }

    @isTest
    static void getForComplaint_unknownComplaintReturnsEmptySummary() {
        ComplaintTaskProgress.Summary s = ComplaintTaskProgress.getForComplaint(
            '001000000000001AAA', AccessLevel.SYSTEM_MODE);
        System.assertEquals(0, s.total, 'no steps for an unknown id');
    }

    @isTest
    static void helpers_mapStatusesAndOverdue() {
        Date today = Date.newInstance(2026, 10, 9);
        System.assertEquals(true, ComplaintTaskProgress.isOverdue('Draft', today.addDays(-1), today), 'draft overdue');
        System.assertEquals(false, ComplaintTaskProgress.isOverdue('Complete', today.addDays(-1), today), 'complete');
        System.assertEquals(false, ComplaintTaskProgress.isOverdue('Open', today, today), 'due today is not overdue');
        System.assertEquals('st-open', ComplaintTaskProgress.statusClass('Open'), 'open');
        System.assertEquals('st-done', ComplaintTaskProgress.statusClass('Complete'), 'complete');
        System.assertEquals('st-draft', ComplaintTaskProgress.statusClass(null), 'default');
    }
}
