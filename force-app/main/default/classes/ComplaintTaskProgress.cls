/**
 * ComplaintTaskProgress
 * ---------------------
 * Reads the CQ Tasks (Complaint Steps, compliancequest__SQX_Complaint_Task__c)
 * on a Complaint and summarises their progress. Shared by the PDF report
 * controller and the draft-summary grounding so both describe tasks the same
 * way.
 *
 * Overdue rule: any task that is not Complete and whose Due Date is before
 * today, whatever its status (Draft, Open, Ready, Under Submission, ...).
 */
public inherited sharing class ComplaintTaskProgress {

    public static final String STATUS_COMPLETE = 'Complete';
    private static final List<String> STATUS_ORDER =
        new List<String>{ 'Draft', 'Open', 'Ready', 'Under Submission', 'Complete' };

    public class TaskRow {
        public Decimal step { get; set; }
        public String taskName { get; set; }
        public String linkedRecord { get; set; }
        public String assignee { get; set; }
        public String status { get; set; }
        public String statusClass { get; set; }
        public String startDate { get; set; }
        public String dueDate { get; set; }
        public String completionDate { get; set; }
        public Boolean overdue { get; set; }
        public Integer daysOverdue { get; set; }
        public String overdueLabel { get; set; }
    }

    public class StatusCount {
        public String status { get; set; }
        public String statusClass { get; set; }
        public Integer total { get; set; }
    }

    public class Summary {
        public Integer total { get; set; }
        public Integer completeCount { get; set; }
        public Integer overdueCount { get; set; }
        public Integer completePct { get; set; }
        public Integer remainingPct { get; set; }
        public String progressLabel { get; set; }
        public String overdueLabel { get; set; }
        public List<StatusCount> counts { get; set; }
        public List<TaskRow> rows { get; set; }
    }

    /** Loads and summarises the Complaint's applicable CQ Tasks. */
    public static Summary getForComplaint(Id complaintId, AccessLevel level) {
        List<compliancequest__SQX_Complaint_Task__c> tasks = new List<compliancequest__SQX_Complaint_Task__c>();
        if (complaintId != null) {
            tasks = (List<compliancequest__SQX_Complaint_Task__c>) Database.queryWithBinds(
                'SELECT Id, Name, compliancequest__Step__c, compliancequest__Status__c, ' +
                'compliancequest__SQX_User__r.Name, compliancequest__Start_Date__c, ' +
                'compliancequest__Due_Date__c, compliancequest__Completion_Date__c, ' +
                'compliancequest__SQX_Task__r.Name, compliancequest__SQX_Product_History_Review__r.Name, ' +
                'compliancequest__SQX_Investigation__r.Name ' +
                'FROM compliancequest__SQX_Complaint_Task__c ' +
                'WHERE compliancequest__SQX_Complaint__c = :complaintId ' +
                'AND compliancequest__Applicable__c = true ' +
                'ORDER BY compliancequest__Step__c NULLS LAST, CreatedDate',
                new Map<String, Object>{ 'complaintId' => complaintId },
                level
            );
        }
        return summarize(tasks, Date.today());
    }

    /** Pure function over already-loaded rows, so it can be unit tested. */
    public static Summary summarize(List<compliancequest__SQX_Complaint_Task__c> tasks, Date today) {
        Summary s = new Summary();
        s.rows = new List<TaskRow>();
        s.counts = new List<StatusCount>();
        s.total = 0;
        s.completeCount = 0;
        s.overdueCount = 0;

        Map<String, Integer> byStatus = new Map<String, Integer>();
        for (String st : STATUS_ORDER) {
            byStatus.put(st, 0);
        }

        for (compliancequest__SQX_Complaint_Task__c t : tasks) {
            TaskRow r = new TaskRow();
            r.step = t.compliancequest__Step__c;
            r.taskName = t.compliancequest__SQX_Task__r != null && String.isNotBlank(t.compliancequest__SQX_Task__r.Name)
                ? t.compliancequest__SQX_Task__r.Name : t.Name;
            if (t.compliancequest__SQX_Product_History_Review__r != null) {
                r.linkedRecord = t.compliancequest__SQX_Product_History_Review__r.Name;
            } else if (t.compliancequest__SQX_Investigation__r != null) {
                r.linkedRecord = t.compliancequest__SQX_Investigation__r.Name;
            }
            r.assignee = t.compliancequest__SQX_User__r != null ? t.compliancequest__SQX_User__r.Name : null;
            r.status = t.compliancequest__Status__c;
            r.statusClass = statusClass(r.status);
            r.startDate = formatDate(t.compliancequest__Start_Date__c);
            r.dueDate = formatDate(t.compliancequest__Due_Date__c);
            r.completionDate = formatDate(t.compliancequest__Completion_Date__c);
            r.overdue = isOverdue(r.status, t.compliancequest__Due_Date__c, today);
            r.daysOverdue = r.overdue ? t.compliancequest__Due_Date__c.daysBetween(today) : 0;
            r.overdueLabel = r.overdue
                ? r.daysOverdue + (r.daysOverdue == 1 ? ' day overdue' : ' days overdue')
                : null;
            s.rows.add(r);

            s.total++;
            if (r.status == STATUS_COMPLETE) {
                s.completeCount++;
            }
            if (r.overdue) {
                s.overdueCount++;
            }
            if (r.status != null) {
                byStatus.put(r.status, (byStatus.containsKey(r.status) ? byStatus.get(r.status) : 0) + 1);
            }
        }

        List<String> statuses = new List<String>(STATUS_ORDER);
        for (String st : byStatus.keySet()) {
            if (!statuses.contains(st)) {
                statuses.add(st);
            }
        }
        for (String st : statuses) {
            StatusCount c = new StatusCount();
            c.status = st;
            c.statusClass = statusClass(st);
            c.total = byStatus.get(st);
            s.counts.add(c);
        }

        s.completePct = s.total == 0 ? 0 : Math.roundToLong(100.0 * s.completeCount / s.total).intValue();
        s.remainingPct = 100 - s.completePct;
        s.progressLabel = s.completeCount + ' of ' + s.total + ' complete';
        s.overdueLabel = s.overdueCount == 0 ? null : s.overdueCount + ' overdue';
        return s;
    }

    /** Not Complete and past the Due Date, regardless of status. */
    @TestVisible
    private static Boolean isOverdue(String status, Date dueDate, Date today) {
        return status != STATUS_COMPLETE && dueDate != null && today != null && dueDate < today;
    }

    @TestVisible
    private static String statusClass(String status) {
        if (status == 'Open') { return 'st-open'; }
        if (status == 'Ready') { return 'st-ready'; }
        if (status == 'Under Submission') { return 'st-sub'; }
        if (status == STATUS_COMPLETE) { return 'st-done'; }
        return 'st-draft';
    }

    private static String formatDate(Date d) {
        return d == null ? null : Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('MMM d, yyyy');
    }
}
