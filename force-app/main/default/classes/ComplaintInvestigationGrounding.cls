/**
 * Grounding data for the "Complaint Draft Investigation Summary" prompt template.
 *
 * Reads every populated, user-accessible field on a ComplianceQuest Complaint,
 * every linked Product History Review, each review's checklist items, the
 * Complaint's CQ Tasks (progress and overdue), and the records returned by the
 * Associated Items Report (primary Part, assemblies, line items with lot match,
 * Nonconformances, CAPAs, Change Orders, Inspections and related Investigations),
 * and returns them as labeled plain text. Fields are discovered at run time from
 * the object describe, so fields added to these objects later are included
 * automatically. Queries run in USER_MODE, so sharing and field-level security
 * of the running user are enforced.
 */
public with sharing class ComplaintInvestigationGrounding {

    @TestVisible static final String COMPLAINT_OBJ = 'compliancequest__SQX_Complaint__c';
    @TestVisible static final String PHR_OBJ = 'compliancequest__SQX_Product_History_Review__c';
    @TestVisible static final String CHECKLIST_OBJ = 'compliancequest__SQX_Product_History_Answer__c';
    static final String PHR_COMPLAINT_FIELD = 'compliancequest__SQX_Complaint__c';
    static final String CHECKLIST_PHR_FIELD = 'compliancequest__SQX_Product_History_Review__c';

    // System or noise fields that add nothing to an investigation summary.
    static final Set<String> SKIP_FIELDS = new Set<String>{
        'id', 'isdeleted', 'systemmodstamp', 'lastvieweddate', 'lastreferenceddate',
        'userrecordaccessid', 'draft_investigation_summary__c'
    };
    static final Integer MAX_VALUE_LENGTH = 8000;

    // Objects returned by the Associated Items Report.
    @TestVisible static final String PART_OBJ = 'compliancequest__SQX_Part__c';
    static final String ASSEMBLY_OBJ = 'cqext__CQPLM_Assembly__c';
    static final String LINE_ITEM_OBJ = 'cqext__CQPLM_Assembly_line_Item__c';
    static final String NC_OBJ = 'compliancequest__SQX_Nonconformance__c';
    static final String CAPA_OBJ = 'compliancequest__SQX_CAPA__c';
    static final String CHANGE_ORDER_OBJ = 'compliancequest__SQX_Change_Order__c';
    static final String INSPECTION_OBJ = 'compliancequest__SQX_Inspection__c';
    static final String INV_OBJ = 'compliancequest__SQX_Investigation__c';
    // Keeps the prompt a manageable size when a part has a long history.
    @TestVisible static final Integer MAX_RECORDS_PER_TYPE = 25;
    static final Integer MAX_LINE_ITEMS = 100;
    // The lookup on each quality record that names the Part it was filed against.
    static final Map<String, String> PART_FIELD_BY_OBJ = new Map<String, String>{
        NC_OBJ => 'compliancequest__SQX_Part__c',
        CAPA_OBJ => 'compliancequest__SQX_Part__c',
        CHANGE_ORDER_OBJ => 'compliancequest__SQX_Product__c',
        INSPECTION_OBJ => 'compliancequest__SQX_Part__c',
        INV_OBJ => 'compliancequest__SQX_Part__c'
    };
    static final String STATUS_FIELD = 'compliancequest__Status__c';
    // Short title shown in each record's one-line index entry (Inspections have none).
    static final Map<String, String> TITLE_FIELD_BY_OBJ = new Map<String, String>{
        NC_OBJ => 'compliancequest__NC_Title__c',
        CAPA_OBJ => 'compliancequest__Title__c',
        CHANGE_ORDER_OBJ => 'compliancequest__Title__c'
    };

    public static String buildGroundingText(Id complaintId) {
        List<String> out = new List<String>();

        List<SObject> complaints = queryAll(COMPLAINT_OBJ, 'Id = :recordId',
            new Map<String, Object>{ 'recordId' => complaintId }, null);
        if (complaints.isEmpty()) {
            return 'No complaint was found for record Id ' + complaintId + '.';
        }
        out.add('## COMPLAINT');
        out.add(formatRecord(COMPLAINT_OBJ, complaints[0]));

        List<SObject> reviews = queryAll(PHR_OBJ, PHR_COMPLAINT_FIELD + ' = :recordId',
            new Map<String, Object>{ 'recordId' => complaintId }, 'CreatedDate ASC');

        Map<Id, List<SObject>> checklistByReview = new Map<Id, List<SObject>>();
        if (!reviews.isEmpty()) {
            Set<Id> reviewIds = new Map<Id, SObject>(reviews).keySet();
            for (SObject item : queryAll(CHECKLIST_OBJ, CHECKLIST_PHR_FIELD + ' IN :reviewIds',
                    new Map<String, Object>{ 'reviewIds' => reviewIds }, 'Name ASC')) {
                Id reviewId = (Id) item.get(CHECKLIST_PHR_FIELD);
                if (!checklistByReview.containsKey(reviewId)) {
                    checklistByReview.put(reviewId, new List<SObject>());
                }
                checklistByReview.get(reviewId).add(item);
            }
        }

        out.add('');
        out.add('## PRODUCT HISTORY REVIEWS (' + reviews.size() + ')');
        if (reviews.isEmpty()) {
            out.add('No Product History Review records are linked to this complaint.');
        }
        Integer n = 1;
        for (SObject review : reviews) {
            out.add('');
            out.add('### Review ' + n++);
            out.add(formatRecord(PHR_OBJ, review));
            List<SObject> items = checklistByReview.get(review.Id);
            if (items != null && !items.isEmpty()) {
                out.add('#### Checklist Items (' + items.size() + ')');
                Integer i = 1;
                for (SObject item : items) {
                    out.add('- Item ' + i++);
                    out.add(formatRecord(CHECKLIST_OBJ, item));
                }
            }
        }

        out.add('');
        out.add(buildTasksText(complaintId));

        out.add('');
        out.add(buildAssociatedItemsText(complaintId));
        return String.join(out, '\n');
    }

    // ---------------------------------------------------------------- CQ tasks

    /**
     * The Complaint's CQ Tasks (Complaint Steps): overall progress, then one line
     * per task. A task is overdue when it is not Complete and past its due date,
     * whatever its status. Runs in USER_MODE like the rest of the grounding.
     */
    @TestVisible
    static String buildTasksText(Id complaintId) {
        ComplaintTaskProgress.Summary s;
        try {
            s = ComplaintTaskProgress.getForComplaint(complaintId, AccessLevel.USER_MODE);
        } catch (Exception e) {
            return '## CQ TASKS\nCQ Tasks could not be read: ' + e.getMessage();
        }
        List<String> out = new List<String>{ '## CQ TASKS (' + s.total + ')' };
        if (s.total == 0) {
            out.add('No CQ Tasks are recorded on this complaint.');
            return String.join(out, '\n');
        }
        out.add('Progress: ' + s.progressLabel + ' (' + s.completePct + '%). '
            + (s.overdueCount == 0 ? 'No tasks are overdue.' : s.overdueCount + ' overdue.'));
        List<String> byStatus = new List<String>();
        for (ComplaintTaskProgress.StatusCount c : s.counts) {
            byStatus.add(c.status + ' ' + c.total);
        }
        out.add('By status: ' + String.join(byStatus, ', '));
        out.add('Task index (one line per task: step | task | linked record | assignee | status | started | due | completed):');
        for (ComplaintTaskProgress.TaskRow r : s.rows) {
            out.add('- Step ' + (r.step == null ? '?' : String.valueOf(r.step.intValue()))
                + ' | ' + blankAs(r.taskName)
                + ' | ' + blankAs(r.linkedRecord)
                + ' | ' + blankAs(r.assignee)
                + ' | ' + blankAs(r.status)
                + ' | ' + blankAs(r.startDate)
                + ' | ' + blankAs(r.dueDate)
                + ' | ' + (r.completionDate == null ? 'Not completed' : r.completionDate)
                + (r.overdue ? ' | OVERDUE by ' + r.daysOverdue + (r.daysOverdue == 1 ? ' day' : ' days') : ''));
        }
        return String.join(out, '\n');
    }

    // ------------------------------------------------------- associated items

    /**
     * Runs the existing Associated Items Report (Part -> Revision -> Assembly ->
     * Line Items, plus NCs, CAPAs, Change Orders, Inspections and related
     * Investigations filed against the primary Part or any component Part, or
     * sharing the Complaint's lot) and expands each record it returns.
     *
     * AssociatedItemsReportAction runs without sharing, so every record it
     * returns is re-queried here in USER_MODE: the summary only shows records
     * and fields the running user can see.
     */
    @TestVisible
    static String buildAssociatedItemsText(Id complaintId) {
        List<String> out = new List<String>{ '## ASSOCIATED ITEMS (from the Associated Items Report)' };

        AssociatedItemsReportData report;
        try {
            AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
            req.targetRecordId = complaintId;
            report = AssociatedItemsReportAction.getAssociatedItemsReport(
                new List<AssociatedItemsReportAction.Request>{ req })[0].report;
        } catch (Exception e) {
            out.add('The Associated Items Report could not be run: ' + e.getMessage());
            return String.join(out, '\n');
        }
        if (report == null || report.success != true) {
            out.add('The Associated Items Report returned an error: '
                + (report == null ? 'no response' : report.errorMessage));
            return String.join(out, '\n');
        }
        if (report.hasPrimaryPart != true || report.primaryPart == null) {
            out.add('No primary Part is set on this complaint, so the report found no associated items.');
            return String.join(out, '\n');
        }
        List<AssociatedItemsAssemblyInfo> assemblies =
            report.assemblies == null ? new List<AssociatedItemsAssemblyInfo>() : report.assemblies;
        List<AssociatedItemsLineItemInfo> lineItems =
            report.assemblyLineItems == null ? new List<AssociatedItemsLineItemInfo>() : report.assemblyLineItems;

        // Primary Part: every populated field.
        out.add('');
        out.add('### Primary Part');
        try {
            List<SObject> parts = queryAll(PART_OBJ, 'Id = :recordId',
                new Map<String, Object>{ 'recordId' => report.primaryPart.id }, null);
            out.add(parts.isEmpty()
                ? 'The primary Part is not visible to the current user.'
                : formatRecord(PART_OBJ, parts[0]));
        } catch (Exception e) {
            out.add('The primary Part could not be read: ' + e.getMessage());
        }

        // Assemblies and line items: the bill of materials, kept to the
        // report's summary columns because a BOM can be very large.
        out.add('');
        try {
            Set<Id> visibleAssemblies = visibleIds(ASSEMBLY_OBJ, idsOfAssemblies(assemblies));
            out.add('### Assemblies (' + visibleAssemblies.size() + ')');
            if (visibleAssemblies.isEmpty()) {
                out.add('None found.');
            }
            for (AssociatedItemsAssemblyInfo a : assemblies) {
                if (a != null && visibleAssemblies.contains(a.id)) {
                    out.add('- ' + blankAs(a.name));
                }
            }
        } catch (Exception e) {
            out.add('### Assemblies');
            out.add('Assemblies could not be read: ' + e.getMessage());
        }

        out.add('');
        try {
            Set<Id> visibleLines = visibleIds(LINE_ITEM_OBJ, idsOfLineItems(lineItems));
            out.add('### Assembly Line Items (' + visibleLines.size() + ')');
            if (visibleLines.isEmpty()) {
                out.add('None found.');
            } else if (String.isNotBlank(report.lotNumber)) {
                out.add('Lot Match = Nonconformances and Inspections carrying lot ' + report.lotNumber
                    + ' that are filed against that component Part. The bill of materials has no lot data, '
                    + 'so this does not show which lot a component came from.');
            }
            Integer shown = 0;
            for (AssociatedItemsLineItemInfo li : lineItems) {
                if (li == null || !visibleLines.contains(li.id)) {
                    continue;
                }
                if (shown == MAX_LINE_ITEMS) {
                    out.add('(' + (visibleLines.size() - shown) + ' more line items not listed.)');
                    break;
                }
                out.add('- Assembly: ' + blankAs(li.assemblyName) + ' | Part: ' + blankAs(li.partName)
                    + ' | Part Number: ' + blankAs(li.partNumber)
                    + (String.isBlank(li.lotMatch) ? '' : ' | Lot Match: ' + li.lotMatch));
                shown++;
            }
        } catch (Exception e) {
            out.add('### Assembly Line Items');
            out.add('Assembly line items could not be read: ' + e.getMessage());
        }

        // Quality records: every populated field on each record, plus exact
        // counts by part and status so the summary never has to count itself.
        Map<String, Map<String, Map<String, Integer>>> counts =
            new Map<String, Map<String, Map<String, Integer>>>();
        addRecordSection(out, 'Nonconformances', 'Nonconformance', NC_OBJ, report.nonconformances, counts);
        addRecordSection(out, 'CAPAs', 'CAPA', CAPA_OBJ, report.capas, counts);
        addRecordSection(out, 'Change Orders', 'Change Order', CHANGE_ORDER_OBJ, report.changeOrders, counts);
        addRecordSection(out, 'Inspections', 'Inspection', INSPECTION_OBJ, report.inspections, counts);

        // Related Investigations: same part (including component parts) or same lot.
        // Investigations started from this complaint are already excluded.
        List<AssociatedItemsRecordInfo> invInfos = new List<AssociatedItemsRecordInfo>();
        if (report.investigations != null) {
            for (AssociatedItemsInvestigationInfo inv : report.investigations) {
                if (inv != null && inv.id != null) {
                    AssociatedItemsRecordInfo ri = new AssociatedItemsRecordInfo();
                    ri.id = inv.id;
                    ri.name = inv.name;
                    invInfos.add(ri);
                }
            }
        }
        addRecordSection(out, 'Related Investigations', 'Investigation', INV_OBJ, invInfos, counts);
        if (report.investigations != null && !report.investigations.isEmpty()) {
            out.add('Investigations on the same Part or Lot as this complaint (the complaint\'s own investigations are excluded).');
            out.add('Source and match (investigation | source | matched by):');
            for (AssociatedItemsInvestigationInfo inv : report.investigations) {
                if (inv != null) {
                    out.add('- ' + blankAs(inv.name) + ' | ' + blankAs(inv.sourceName)
                        + ' | ' + blankAs(inv.matchedBy));
                }
            }
        }

        out.add('');
        out.add('### Counts by Part (exact counts of all visible records above, by status)');
        if (counts.isEmpty()) {
            out.add('No Nonconformances, CAPAs, Change Orders, Inspections or Investigations.');
        }
        for (String part : counts.keySet()) {
            List<String> pieces = new List<String>();
            for (String title : counts.get(part).keySet()) {
                Map<String, Integer> byStatus = counts.get(part).get(title);
                Integer total = 0;
                List<String> statusParts = new List<String>();
                for (String status : byStatus.keySet()) {
                    total += byStatus.get(status);
                    statusParts.add(status + ' ' + byStatus.get(status));
                }
                pieces.add(title + ' ' + total + ' (' + String.join(statusParts, ', ') + ')');
            }
            out.add('- ' + part + ': ' + String.join(pieces, '; '));
        }

        return String.join(out, '\n');
    }

    // Tallies every visible record of one type by the part it was filed against and its
    // status, and writes one index line per record: number | status | created | part | title.
    static void tally(String title, String objectName, List<Id> ids,
                      Map<String, Map<String, Map<String, Integer>>> counts,
                      List<String> indexLines) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        String partField = PART_FIELD_BY_OBJ.get(objectName);
        String partRel;
        if (partField != null && fieldMap.containsKey(partField.toLowerCase())) {
            Schema.DescribeFieldResult pd = fieldMap.get(partField.toLowerCase()).getDescribe();
            if (pd.isAccessible() && pd.getRelationshipName() != null) {
                partRel = pd.getRelationshipName();
            }
        }
        Boolean hasStatus = fieldMap.containsKey(STATUS_FIELD.toLowerCase())
            && fieldMap.get(STATUS_FIELD.toLowerCase()).getDescribe().isAccessible();
        String titleField = TITLE_FIELD_BY_OBJ.get(objectName);
        if (titleField != null && !(fieldMap.containsKey(titleField.toLowerCase())
                && fieldMap.get(titleField.toLowerCase()).getDescribe().isAccessible())) {
            titleField = null;
        }

        String soql = 'SELECT Id, Name, CreatedDate'
            + (partRel == null ? '' : ', ' + partRel + '.Name')
            + (hasStatus ? ', ' + STATUS_FIELD : '')
            + (titleField == null ? '' : ', ' + titleField)
            + ' FROM ' + objectName + ' WHERE Id IN :ids ORDER BY CreatedDate DESC';
        for (SObject rec : Database.queryWithBinds(soql,
                new Map<String, Object>{ 'ids' => ids }, AccessLevel.USER_MODE)) {
            String part = 'No part recorded';
            if (partRel != null) {
                SObject p = rec.getSObject(partRel);
                if (p != null && p.get('Name') != null) {
                    part = String.valueOf(p.get('Name'));
                }
            }
            String status = 'No status';
            if (hasStatus && rec.get(STATUS_FIELD) != null) {
                status = String.valueOf(rec.get(STATUS_FIELD));
            }
            String recTitle = titleField == null || rec.get(titleField) == null
                ? 'No title' : String.valueOf(rec.get(titleField)).trim();
            indexLines.add('- ' + rec.get('Name') + ' | ' + status + ' | '
                + ((Datetime) rec.get('CreatedDate')).format('yyyy-MM-dd') + ' | '
                + part + ' | ' + recTitle);
            if (!counts.containsKey(part)) {
                counts.put(part, new Map<String, Map<String, Integer>>());
            }
            if (!counts.get(part).containsKey(title)) {
                counts.get(part).put(title, new Map<String, Integer>());
            }
            Map<String, Integer> byStatus = counts.get(part).get(title);
            byStatus.put(status, (byStatus.containsKey(status) ? byStatus.get(status) : 0) + 1);
        }
    }

    static void addRecordSection(List<String> out, String title, String singular,
                                 String objectName, List<AssociatedItemsRecordInfo> infos,
                                 Map<String, Map<String, Map<String, Integer>>> counts) {
        List<Id> ids = new List<Id>();
        if (infos != null) {
            for (AssociatedItemsRecordInfo ri : infos) {
                if (ri != null && ri.id != null) {
                    ids.add(ri.id);
                }
            }
        }
        out.add('');
        if (ids.isEmpty()) {
            out.add('### ' + title + ' (0)');
            out.add('None found.');
            return;
        }
        Integer visible;
        List<SObject> records;
        List<String> indexLines = new List<String>();
        try {
            visible = visibleIds(objectName, ids).size();
            records = queryAll(objectName, 'Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                'CreatedDate DESC LIMIT ' + MAX_RECORDS_PER_TYPE);
            tally(title, objectName, ids, counts, indexLines);
        } catch (Exception e) {
            out.add('### ' + title);
            out.add(title + ' could not be read: ' + e.getMessage());
            return;
        }
        out.add('### ' + title + ' (' + visible + ')');
        if (records.isEmpty()) {
            out.add('None visible to the current user.');
            return;
        }
        out.add('Record index (one line per record: number | status | created | part | title):');
        out.addAll(indexLines);
        out.add('Full record details:');
        Integer n = 1;
        for (SObject rec : records) {
            out.add('- ' + singular + ' ' + n++);
            out.add(formatRecord(objectName, rec));
        }
        if (visible > records.size()) {
            out.add('(' + (visible - records.size()) + ' older ' + title.toLowerCase()
                + ' not included; only the ' + MAX_RECORDS_PER_TYPE + ' most recent are shown.)');
        }
    }

    // Ids from the report that the running user can actually see.
    static Set<Id> visibleIds(String objectName, List<Id> ids) {
        Set<Id> result = new Set<Id>();
        if (ids == null || ids.isEmpty()) {
            return result;
        }
        for (SObject rec : Database.queryWithBinds(
                'SELECT Id FROM ' + objectName + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids }, AccessLevel.USER_MODE)) {
            result.add(rec.Id);
        }
        return result;
    }

    static List<Id> idsOfAssemblies(List<AssociatedItemsAssemblyInfo> items) {
        List<Id> ids = new List<Id>();
        for (AssociatedItemsAssemblyInfo a : items) {
            if (a != null && a.id != null) ids.add(a.id);
        }
        return ids;
    }

    static List<Id> idsOfLineItems(List<AssociatedItemsLineItemInfo> items) {
        List<Id> ids = new List<Id>();
        for (AssociatedItemsLineItemInfo li : items) {
            if (li != null && li.id != null) ids.add(li.id);
        }
        return ids;
    }

    static String blankAs(String s) {
        return String.isBlank(s) ? 'Not documented' : s;
    }

    // ---------------------------------------------------------------- helpers

    @TestVisible
    static List<SObject> queryAll(String objectName, String whereClause,
                                  Map<String, Object> binds, String orderBy) {
        List<String> selectList = new List<String>();
        for (Schema.DescribeFieldResult d : fieldsFor(objectName)) {
            selectList.add(d.getName());
            String nameRef = relatedNameField(d);
            if (nameRef != null) {
                selectList.add(nameRef);
            }
        }
        String soql = 'SELECT ' + String.join(selectList, ', ') + ' FROM ' + objectName
            + ' WHERE ' + whereClause
            + (orderBy == null ? '' : ' ORDER BY ' + orderBy);
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    // Accessible, meaningful fields in a stable order: name field first, then by label.
    @TestVisible
    static List<Schema.DescribeFieldResult> fieldsFor(String objectName) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        Map<String, Schema.DescribeFieldResult> byKey = new Map<String, Schema.DescribeFieldResult>();
        Schema.DescribeFieldResult nameField;
        for (Schema.SObjectField f : fieldMap.values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!include(d)) {
                continue;
            }
            if (d.isNameField()) {
                nameField = d;
            } else {
                byKey.put(d.getLabel().toLowerCase() + '|' + d.getName(), d);
            }
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Schema.DescribeFieldResult> ordered = new List<Schema.DescribeFieldResult>();
        if (nameField != null) {
            ordered.add(nameField);
        }
        for (String k : keys) {
            ordered.add(byKey.get(k));
        }
        return ordered;
    }

    static Boolean include(Schema.DescribeFieldResult d) {
        String lower = d.getName().toLowerCase();
        if (!d.isAccessible()) return false;
        if (SKIP_FIELDS.contains(lower)) return false;
        if (lower.endsWith('draft_investigation_summary__c')) return false;
        Schema.DisplayType t = d.getType();
        return t != Schema.DisplayType.BASE64
            && t != Schema.DisplayType.ADDRESS
            && t != Schema.DisplayType.LOCATION;
    }

    // For lookups, also query the related record's Name so the summary shows names, not Ids.
    static String relatedNameField(Schema.DescribeFieldResult d) {
        if (d.getType() != Schema.DisplayType.REFERENCE || d.getRelationshipName() == null) {
            return null;
        }
        List<Schema.SObjectType> targets = d.getReferenceTo();
        if (targets.isEmpty()) {
            return null;
        }
        if (targets.size() == 1) {
            Schema.SObjectField nameF = targets[0].getDescribe().fields.getMap().get('name');
            if (nameF == null || !nameF.getDescribe().isAccessible()) {
                return null;
            }
        }
        return d.getRelationshipName() + '.Name';
    }

    @TestVisible
    static String formatRecord(String objectName, SObject rec) {
        List<String> lines = new List<String>();
        for (Schema.DescribeFieldResult d : fieldsFor(objectName)) {
            String value = displayValue(d, rec);
            if (String.isNotBlank(value)) {
                lines.add(d.getLabel() + ': ' + value);
            }
        }
        return String.join(lines, '\n');
    }

    static String displayValue(Schema.DescribeFieldResult d, SObject rec) {
        Object raw;
        try {
            raw = rec.get(d.getName());
        } catch (SObjectException e) {
            return null;
        }
        if (raw == null) {
            return null;
        }
        String value;
        if (d.getType() == Schema.DisplayType.REFERENCE && d.getRelationshipName() != null) {
            SObject related;
            try {
                related = rec.getSObject(d.getRelationshipName());
            } catch (SObjectException e) {
                related = null;
            }
            Object relatedName = related == null ? null : related.get('Name');
            value = relatedName == null ? String.valueOf(raw) : String.valueOf(relatedName);
        } else if (d.getType() == Schema.DisplayType.DATETIME) {
            // Show date/times in the running user's time zone, as the UI does.
            value = ((Datetime) raw).format('yyyy-MM-dd HH:mm z');
        } else if (d.getType() == Schema.DisplayType.TEXTAREA && d.isHtmlFormatted()) {
            value = String.valueOf(raw).stripHtmlTags();
        } else {
            value = String.valueOf(raw);
        }
        value = value.trim();
        if (value.length() > MAX_VALUE_LENGTH) {
            value = value.left(MAX_VALUE_LENGTH) + ' …[truncated]';
        }
        return value;
    }
}
