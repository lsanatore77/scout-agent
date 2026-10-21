/**
 * SummaryHtmlRepair
 * ------------------
 * The summary prompt can return HTML in which each section title is only a bold
 * word at the start of a paragraph and lists of records run on inside a sentence.
 * That saves as one wall of text. This puts the structure back before
 * SummaryRichText sanitizes the result:
 *
 *  - "<p><strong>Complaint Overview</strong> text" becomes a bold heading, with a blank line before it, then a paragraph.
 *  - record numbers (NC-000072, CAPA-000006 and so on) are bolded.
 *  - the Associated Items section becomes a bulleted list, one bullet per sentence, with the record list nested under its sentence.
 *  - "are: NC-000072 (Draft, ...), CAPA-000006 (...), and INS-0000000019 (...)" becomes a bullet list.
 *  - "*word*" left over from markdown becomes italic.
 *  - the closing "This is an AI-generated draft ..." line gets its own paragraph.
 *
 * Text without HTML is returned unchanged, because SummaryRichText already repairs that.
 */
public with sharing class SummaryHtmlRepair {

    static final String ID = '(?:NC|CAPA|CHG|INS|INV|PHR|PHA|COM)-\\d+';

    static final List<String> TITLES = new List<String>{
        'Complaint Overview', 'Associated Items', 'Product History Review', 'Analysis and Next Steps',
        'Trends, gaps and next steps'
    };

    static Boolean looksLikeHtml(String s) {
        return Pattern.compile('(?i)<(p|br|ul|ol|li|strong|b|em|i|h[1-6]|div)(\\s[^>]*)?/?>').matcher(s).find();
    }

    public static String repair(String input) {
        if (String.isBlank(input) || input.length() < 120) { return input; }
        if (!looksLikeHtml(input)) { return input; }

        List<String> quoted = new List<String>();
        for (String h : TITLES) { quoted.add(Pattern.quote(h)); }
        String titles = String.join(quoted, '|');

        String s = input.replace('\r\n', '\n').replace('\r', '\n');
        s = s.replaceAll('(?is)<p>\\s*<(?:strong|b)>\\s*(' + titles + ')\\s*:?\\s*</(?:strong|b)>\\s*', '<h3><strong>$1</strong></h3><p>');
        s = s.replaceAll('(?i)(<h3><strong>)', '<p><br></p>$1');
        if (s.startsWith('<p><br></p>')) { s = s.substring(11); }
        s = s.replaceAll('(?<![\\w*])\\*(?![\\s*])([^*<>]+?)(?<![\\s*])\\*(?![\\w*])', '<em>$1</em>');
        s = recordListsToBullets(s);
        s = associatedItemsToBullets(s);
        s = s.replaceAll('(?<![\\w-])(?<!<strong>)(' + ID + ')(?![\\w-])', '<strong>$1</strong>');
        s = s.replaceAll('[ \\t]+(This is an AI-generated draft)', '</p><p>$1');
        s = s.replaceAll('(?is)<p>\\s*</p>', '');
        return s;
    }

    /** ": NC-1 (...), CAPA-2 (...), and INS-3 (...)." becomes a list; needs at least two entries. */
    @TestVisible
    static String recordListsToBullets(String s) {
        Matcher m = Pattern.compile(
            ':\\s+(' + ID + '\\s\\([^)]*\\)(?:,\\s+(?:and\\s+)?' + ID + '\\s\\([^)]*\\))+)\\.?'
        ).matcher(s);
        String out = '';
        Integer last = 0;
        while (m.find()) {
            String items = m.group(1).replaceAll('\\),\\s+(?:and\\s+)?(?=' + ID + '\\s\\()', ')</li><li>');
            out += s.substring(last, m.start()) + ':</p><ul><li>' + items + '</li></ul><p>';
            last = m.end();
        }
        return out + s.substring(last);
    }

    /** Turns the Associated Items paragraph into bullets, one per sentence; a record list stays nested under its lead-in sentence. */
    @TestVisible
    static String associatedItemsToBullets(String s) {
        Matcher m = Pattern.compile('(?s)(<h3><strong>Associated Items</strong></h3>)(.*?)(?=<p><br></p><h3>|$)').matcher(s);
        String out = '';
        Integer last = 0;
        while (m.find()) {
            String body = m.group(2);
            String bullets = null;
            String tail = '';
            Integer ulAt = body.indexOf('</p><ul>');
            if (body.startsWith('<p>') && ulAt > 0) {
                String lead = body.substring(3, ulAt);
                String rest = body.substring(ulAt + 4);
                Integer ulEnd = rest.indexOf('</ul>');
                if (ulEnd > 0) {
                    String listHtml = rest.substring(0, ulEnd + 5);
                    tail = rest.substring(ulEnd + 5);
                    List<String> parts = sentences(lead);
                    if (!parts.isEmpty()) {
                        bullets = '';
                        for (Integer i = 0; i < parts.size(); i++) {
                            bullets += '<li>' + parts[i] + (i == parts.size() - 1 ? listHtml : '') + '</li>';
                        }
                    }
                }
            } else if (body.startsWith('<p>') && body.endsWith('</p>') && body.indexOf('</p><') < 0) {
                List<String> parts = sentences(body.substring(3, body.length() - 4));
                if (!parts.isEmpty()) {
                    bullets = '';
                    for (String part : parts) { bullets += '<li>' + part + '</li>'; }
                }
            }
            out += s.substring(last, m.start()) + m.group(1)
                + (bullets == null ? body : '<ul>' + bullets + '</ul>' + tail);
            last = m.end();
        }
        return out + s.substring(last);
    }

    @TestVisible
    static List<String> sentences(String text) {
        List<String> parts = new List<String>();
        for (String p : text.trim().split('(?<=[.!?])\\s+(?=[A-Z])')) {
            if (String.isNotBlank(p)) { parts.add(p.trim()); }
        }
        return parts;
    }
}
