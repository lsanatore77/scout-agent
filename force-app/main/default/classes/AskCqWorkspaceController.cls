/**
 * AskCqWorkspaceController
 * --------------------------
 * Backs the PHR workspace table (askCqRecordsDemo): the live relevance package for the
 * complaint of the Product History Review on screen, and adding the records the user switched on.
 *
 * Nothing new is calculated here. getPackage reuses PhrQmsPanelController.getPanelData (the same
 * relevance model the agent's Relevance Package action reads) and addSelected reuses
 * PhrLeadAddAction (the same add the agent's tick list used), so the workspace and Ask CQ see the
 * same records and the same scores.
 */
public with sharing class AskCqWorkspaceController {

    public class Row {
        @AuraEnabled public String id;
        @AuraEnabled public String recordNumber;
        @AuraEnabled public String recordType;
        @AuraEnabled public String status;
        @AuraEnabled public String title;
        @AuraEnabled public String colour;
        @AuraEnabled public Integer relevance;
        @AuraEnabled public String criteriaMet;
        @AuraEnabled public String matchedBy;
        @AuraEnabled public String relatedBy;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean added;
        @AuraEnabled public Boolean suggested;   // red: met every criterion, pre-selected in the workspace
        @AuraEnabled public String link;
    }

    public class PackageData {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String partName;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public List<Row> rows = new List<Row>();
    }

    public class AddResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer recordsAdded;
        @AuraEnabled public String message;
    }

    /** The live package: nonconformances, CAPAs, change orders, inspections and investigations, best first inside each type. */
    @AuraEnabled
    public static PackageData getPackage(Id recordId) {
        PackageData p = new PackageData();
        try {
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(recordId, null);
            if (!d.success) {
                p.success = false;
                p.errorMessage = d.errorMessage;
                return p;
            }
            p.complaintName = d.complaintName;
            p.partName = d.partName;
            p.partNumber = d.partNumber;
            p.lotNumber = d.lotNumber;
            List<PhrQmsPanelController.Row> all = new List<PhrQmsPanelController.Row>();
            all.addAll(d.nonconformances);
            all.addAll(d.capas);
            all.addAll(d.changeOrders);
            all.addAll(d.inspections);
            all.addAll(d.investigations);
            Map<Id, String> titles = loadTitles(all);
            for (PhrQmsPanelController.Row r : all) {
                p.rows.add(toRow(r, titles));
            }
        } catch (Exception ex) {
            p.success = false;
            p.errorMessage = ex.getMessage();
        }
        return p;
    }

    /** Adds the switched-on records to the Product History Review and stores every record as a PHR Lead. */
    @AuraEnabled
    public static AddResult addSelected(Id recordId, List<String> selectedIds) {
        PhrLeadAddAction.Request req = new PhrLeadAddAction.Request();
        req.recordId = recordId;
        req.selectedRecordIds = (selectedIds == null || selectedIds.isEmpty()) ? new List<String>{ 'none' } : selectedIds;
        PhrLeadAddAction.Response res = PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ req })[0];
        AddResult out = new AddResult();
        out.success = res.success == true;
        out.recordsAdded = res.recordsAdded;
        out.message = res.summary;
        if (!out.success) { throw new AuraHandledException(String.isBlank(res.summary) ? 'The records could not be added.' : res.summary); }
        return out;
    }

    // ---------- review steps ----------

    public class StepStatus {
        @AuraEnabled public String phrName;
        @AuraEnabled public String complaintId;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String phrStatus;
        @AuraEnabled public Integer recordsAdded = 0;      // Related Products on the PHR
        @AuraEnabled public Integer questionsTotal = 0;
        @AuraEnabled public Integer questionsAnswered = 0;
        @AuraEnabled public Boolean summarySaved = false;
        @AuraEnabled public String summaryHtml;
        @AuraEnabled public Integer reportCount = 0;
        @AuraEnabled public List<ReportFile> reports = new List<ReportFile>();
    }

    public class ReportFile {
        @AuraEnabled public String title;
        @AuraEnabled public String link;
        @AuraEnabled public Datetime modified;
        @AuraEnabled public Integer version;
    }

    public class Question {
        @AuraEnabled public String id;
        @AuraEnabled public String number_x;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean answered;
    }

    /** Where each review step stands, read from the PHR itself. */
    @AuraEnabled
    public static StepStatus getStatus(Id phrId) {
        StepStatus st = new StepStatus();
        compliancequest__SQX_Product_History_Review__c phr = [
            SELECT Id, Name, compliancequest__Status__c, compliancequest__Product_History_Review_Summary__c,
                   compliancequest__SQX_Complaint__c, compliancequest__SQX_Complaint__r.Name
            FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :phrId LIMIT 1
        ];
        st.phrName = phr.Name;
        st.phrStatus = phr.compliancequest__Status__c;
        st.complaintId = phr.compliancequest__SQX_Complaint__c;
        st.complaintName = phr.compliancequest__SQX_Complaint__r == null ? null : phr.compliancequest__SQX_Complaint__r.Name;
        st.summarySaved = String.isNotBlank(phr.compliancequest__Product_History_Review_Summary__c);
        st.summaryHtml = phr.compliancequest__Product_History_Review_Summary__c;
        st.recordsAdded = [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c WHERE compliancequest__SQX_Product_History_Review__c = :phrId];
        for (compliancequest__SQX_Product_History_Answer__c a : [
            SELECT compliancequest__Answer__c FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :phrId
        ]) {
            st.questionsTotal++;
            if (String.isNotBlank(a.compliancequest__Answer__c)) { st.questionsAnswered++; }
        }
        if (st.complaintId != null) {
            List<String> titles = PhrReportSettings.phrTitles();
            for (ContentDocumentLink l : [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.LatestPublishedVersionId,
                       ContentDocument.LastModifiedDate, ContentDocument.LatestPublishedVersion.VersionNumber
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :st.complaintId AND ContentDocument.Title IN :titles
                ORDER BY ContentDocument.LastModifiedDate DESC
            ]) {
                ReportFile f = new ReportFile();
                f.title = l.ContentDocument.Title;
                f.link = '/' + l.ContentDocumentId;
                f.modified = l.ContentDocument.LastModifiedDate;
                f.version = l.ContentDocument.LatestPublishedVersion == null ? null : Integer.valueOf(l.ContentDocument.LatestPublishedVersion.VersionNumber);
                st.reports.add(f);
            }
            st.reportCount = st.reports.size();
        }
        return st;
    }

    /** The checklist questions on the PHR with their current answers. Read only. */
    @AuraEnabled
    public static List<Question> getChecklist(Id phrId) {
        List<Question> out = new List<Question>();
        for (compliancequest__SQX_Product_History_Answer__c a : [
            SELECT Id, compliancequest__Question_Number__c, compliancequest__Question__c, compliancequest__Answer__c, compliancequest__Notes__c
            FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :phrId
            ORDER BY compliancequest__Question_Number__c, Name
        ]) {
            Question q = new Question();
            q.id = a.Id;
            q.number_x = a.compliancequest__Question_Number__c;
            q.question = a.compliancequest__Question__c;
            q.answer = a.compliancequest__Answer__c;
            q.notes = a.compliancequest__Notes__c;
            q.answered = String.isNotBlank(a.compliancequest__Answer__c);
            out.add(q);
        }
        return out;
    }

    private static Row toRow(PhrQmsPanelController.Row r, Map<Id, String> titles) {
        Row w = new Row();
        w.id = r.id;
        w.recordNumber = r.name;
        w.recordType = r.recordType;
        w.status = r.status;
        w.title = titles.get(r.id);
        w.colour = r.colour;
        w.relevance = r.relevance;
        w.criteriaMet = r.criteriaMet;
        w.matchedBy = r.matchedBy;
        w.relatedBy = r.relatedBy;
        w.reason = r.reason;
        w.added = r.alreadyAdded == true;
        w.suggested = r.colour == 'Red';
        w.link = '/' + r.id;
        return w;
    }

    /** Titles for NCs, CAPAs and change orders. Inspections and investigations have none. */
    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
            else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [
            SELECT Id, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc
        ]) { m.put(x.Id, x.compliancequest__NC_Title__c); }
        for (compliancequest__SQX_CAPA__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capa
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        for (compliancequest__SQX_Change_Order__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :co
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        return m;
    }
}
