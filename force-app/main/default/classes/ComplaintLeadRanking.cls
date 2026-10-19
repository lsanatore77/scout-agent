/**
 * Adds the lead package's ranking to the draft investigation summary data, so the
 * summary names the same "most relevant" records the lead package and PDF report show.
 * Only the Top tier is listed (at most 5), highest score first.
 */
public with sharing class ComplaintLeadRanking {

    @TestVisible static final Integer MAX_TOP = 5;

    public static String buildText(Id complaintId) {
        List<String> out = new List<String>{
            '## MOST RELEVANT RECORDS (from the Product History lead package ranking)',
            'When the summary names the most relevant records, use ONLY the records in this list, in this order. '
                + 'Do not pick other records as the most relevant. Other records may still be mentioned as background.'
        };
        try {
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(complaintId, null);
            if (d == null || d.success != true) {
                out.add('The ranking could not be read' + (d == null || String.isBlank(d.errorMessage) ? '.' : ': ' + d.errorMessage));
                return String.join(out, '\n');
            }
            List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>();
            for (List<PhrQmsPanelController.Row> bucket : new List<List<PhrQmsPanelController.Row>>{
                    d.nonconformances, d.capas, d.changeOrders, d.inspections }) {
                if (bucket == null) { continue; }
                for (PhrQmsPanelController.Row r : bucket) {
                    if (r.tier == 'Top') { rows.add(r); }
                }
            }
            rows = sortByRelevance(rows);
            if (rows.isEmpty()) {
                out.add('No records ranked as Top relevance, so the summary should not call any record the most relevant.');
                return String.join(out, '\n');
            }
            for (Integer i = 0; i < rows.size() && i < MAX_TOP; i++) {
                PhrQmsPanelController.Row r = rows[i];
                out.add((i + 1) + '. ' + r.recordType + ' ' + r.name + ' | status: ' + r.status
                    + ' | relevance score: ' + r.relevance
                    + (String.isBlank(r.criteriaMet) ? '' : ' | matched on: ' + r.criteriaMet));
            }
        } catch (Exception e) {
            out.add('The ranking could not be read: ' + e.getMessage());
        }
        return String.join(out, '\n');
    }

    @TestVisible
    static List<PhrQmsPanelController.Row> sortByRelevance(List<PhrQmsPanelController.Row> rows) {
        List<PhrQmsPanelController.Row> sorted = new List<PhrQmsPanelController.Row>(rows);
        for (Integer i = 0; i < sorted.size(); i++) {
            Integer best = i;
            for (Integer j = i + 1; j < sorted.size(); j++) {
                Integer a = sorted[j].relevance == null ? -1 : sorted[j].relevance;
                Integer b = sorted[best].relevance == null ? -1 : sorted[best].relevance;
                if (a > b || (a == b && String.valueOf(sorted[j].name) < String.valueOf(sorted[best].name))) { best = j; }
            }
            PhrQmsPanelController.Row t = sorted[i];
            sorted[i] = sorted[best];
            sorted[best] = t;
        }
        return sorted;
    }
}
