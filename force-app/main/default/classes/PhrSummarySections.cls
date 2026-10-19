/**
 * PhrSummarySections
 * -------------------
 * Removes sections of a draft investigation summary that the PHR Report Setting turns off.
 * Works on the text the prompt returns (Markdown, plain text or HTML), by finding the section headings.
 *
 *   Complaint Overview                                   -> Summary: Complaint Overview
 *   Associated Items (or Product History Review)         -> Summary: Product History Review
 *   Analysis and Next Steps (or Trends, gaps and next steps) -> Summary: Analysis and Next Steps
 *
 * If no known heading is found, the text is returned unchanged.
 */
public with sharing class PhrSummarySections {

    private static final String TITLES =
        'Complaint Overview|Associated Items|Product History Review|Analysis and Next Steps|Trends, gaps and next steps';

    private class Hit implements Comparable {
        Integer start;
        String title;
        public Integer compareTo(Object other) { return start - ((Hit) other).start; }
    }

    /** True when at least one section is turned on. */
    public static Boolean anySectionOn(PhrReportSettings.Values v) {
        return v.summaryOverview || v.summaryAssociatedItems || v.summaryAnalysis;
    }

    public static String apply(String summary, PhrReportSettings.Values v) {
        if (String.isBlank(summary) || v == null) { return summary; }
        if (v.summaryOverview && v.summaryAssociatedItems && v.summaryAnalysis) { return summary; }

        List<Hit> hits = findHeadings(summary);
        if (hits.isEmpty()) { return summary; }
        hits.sort();

        String out = summary.substring(0, hits[0].start);
        for (Integer i = 0; i < hits.size(); i++) {
            Integer endAt = i + 1 < hits.size() ? hits[i + 1].start : summary.length();
            if (isOn(hits[i].title, v)) { out += summary.substring(hits[i].start, endAt); }
        }
        return out.trim();
    }

    @TestVisible
    private static Boolean isOn(String title, PhrReportSettings.Values v) {
        String t = title.toLowerCase();
        if (t == 'complaint overview') { return v.summaryOverview; }
        if (t == 'associated items' || t == 'product history review') { return v.summaryAssociatedItems; }
        return v.summaryAnalysis;
    }

    private static List<Hit> findHeadings(String s) {
        List<Hit> hits = new List<Hit>();
        Set<Integer> seen = new Set<Integer>();
        List<String> patterns = new List<String>{
            // Markdown or plain line: optional # or ** then the title alone on the line
            '(?im)^[ \\t]*(?:#{1,6}[ \\t]*)?(?:\\*\\*|__)?(' + TITLES + ')(?:\\*\\*|__)?[ \\t]*:?[ \\t]*$',
            // HTML heading
            '(?is)<h[1-6][^>]*>\\s*(?:<(?:strong|b)>\\s*)?(' + TITLES + ')\\s*:?\\s*(?:</(?:strong|b)>)?\\s*</h[1-6]>',
            // HTML paragraph that starts with a bold title
            '(?is)<p[^>]*>\\s*<(?:strong|b)>\\s*(' + TITLES + ')\\s*:?\\s*</(?:strong|b)>'
        };
        for (String p : patterns) {
            Matcher m = Pattern.compile(p).matcher(s);
            while (m.find()) {
                Integer at = m.start();
                if (seen.contains(at)) { continue; }
                seen.add(at);
                Hit h = new Hit();
                h.start = at;
                h.title = m.group(1);
                hits.add(h);
            }
        }
        return hits;
    }
}
