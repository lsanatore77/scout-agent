/**
 * Agent action: looks up a ComplianceQuest Complaint by its complaint number so
 * the agent can work from a number the user types instead of a record Id.
 */
public with sharing class FindComplaintForSummary {

    static final String COMPLAINT_OBJ = 'compliancequest__SQX_Complaint__c';

    public class Request {
        @InvocableVariable(required=true label='Complaint Number'
            description='The complaint number shown on the record, for example COMP-0001.')
        public String complaintNumber;
    }

    public class Result {
        @InvocableVariable(label='Complaint Record Id')
        public Id complaintId;

        @InvocableVariable(label='Complaint Number')
        public String complaintNumber;

        @InvocableVariable(label='Found')
        public Boolean found;
    }

    @InvocableMethod(
        label='Find Complaint by Number'
        description='Finds a Complaint record by its complaint number and returns its record Id.')
    public static List<Result> find(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request req : requests) {
            if (String.isNotBlank(req.complaintNumber)) {
                numbers.add(req.complaintNumber.trim());
            }
        }
        Map<String, SObject> byNumber = new Map<String, SObject>();
        if (!numbers.isEmpty()) {
            for (SObject c : Database.queryWithBinds(
                    'SELECT Id, Name FROM ' + COMPLAINT_OBJ
                    + ' WHERE Name IN :numbers',
                    new Map<String, Object>{ 'numbers' => numbers }, AccessLevel.USER_MODE)) {
                byNumber.put(((String) c.get('Name')).toUpperCase(), c);
            }
        }
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            SObject match = req.complaintNumber == null ? null
                : byNumber.get(req.complaintNumber.trim().toUpperCase());
            r.found = match != null;
            if (match != null) {
                r.complaintId = match.Id;
                r.complaintNumber = (String) match.get('Name');
            }
            results.add(r);
        }
        return results;
    }
}
