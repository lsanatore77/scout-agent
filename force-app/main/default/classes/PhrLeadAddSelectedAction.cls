/**
 * PhrLeadAddSelectedAction
 * ---------------------------
 * Same job as PhrLeadAddAction (add what is ticked, store every record as a PHR
 * Lead), but the input is the PhrLeadSelection object, so the agent can show the
 * tick-box component (phrLeadSelect) and pass the user's choice straight in.
 *
 * No selection at all (the component never showed) = add everything worth reviewing.
 * "Nothing selected" = add nothing; every record is still stored as Not added.
 */
global with sharing class PhrLeadAddSelectedAction {

    global class Request {
        @InvocableVariable(label='Selection' description='The records the user left ticked, from the selection component.' required=true)
        global PhrLeadSelection selection;
    }

    @InvocableMethod(
        label='Add Selected Leads (Tick Boxes)'
        description='Shows the user the records worth reviewing with tick boxes (everything worth reviewing ticked), then adds the ticked ones to the Product History Review and stores every record as a PHR Lead. Run only after the user confirms.'
    )
    global static List<PhrLeadAddAction.Response> run(List<Request> requests) {
        List<PhrLeadAddAction.Request> calls = new List<PhrLeadAddAction.Request>();
        for (Request req : requests) {
            PhrLeadSelection s = req.selection == null ? new PhrLeadSelection() : req.selection;
            PhrLeadAddAction.Request r = new PhrLeadAddAction.Request();
            r.lotNumber = s.lotNumber;
            if (String.isNotBlank(s.recordId)) {
                try { r.recordId = Id.valueOf(s.recordId.trim()); } catch (Exception ex) { r.recordId = null; }
            }
            if (s.noneSelected == true) {
                r.selectedRecordIds = new List<String>{ 'none' };   // matches nothing: adds none, stores all
            } else {
                r.selectedRecordIds = s.selectedRecordIds;
            }
            calls.add(r);
        }
        List<PhrLeadAddAction.Response> out = new List<PhrLeadAddAction.Response>();
        for (PhrLeadAddAction.Request r : calls) {
            if (r.recordId == null) {
                PhrLeadAddAction.Response bad = new PhrLeadAddAction.Response();
                bad.success = false;
                bad.recordsAdded = 0;
                bad.leadsStored = 0;
                bad.summary = 'I could not tell which complaint to add these to.';
                out.add(bad);
            } else {
                out.addAll(PhrLeadAddAction.run(new List<PhrLeadAddAction.Request>{ r }));
            }
        }
        return out;
    }
}
