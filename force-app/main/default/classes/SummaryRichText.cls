/**
 * SummaryRichText
 * ----------------
 * Turns the text Agentforce returns into HTML that is safe to store in a Rich
 * Text Area field (Draft_Investigation_Summaries__c).
 *
 *  - Markdown (headings, **bold**, *italic*, bullets, numbered and nested
 *    lists, links, `code`, horizontal rules, blank-line paragraphs) is
 *    converted to HTML.
 *  - Text that already contains HTML is kept as HTML.
 *  - Either way the result is sanitized: only a fixed set of formatting tags
 *    survives, attributes are dropped (links keep a safe href), and scripts,
 *    styles, comments and event handlers are removed.
 *  - The result is cut at a complete block (never mid-tag) when it would
 *    exceed the field length.
 */
public with sharing class SummaryRichText {

    public static final Integer MAX_LENGTH = 32768;

    @TestVisible static final String TRUNCATION_NOTE = '<p><em>(Summary shortened to fit the field.)</em></p>';

    static final Set<String> ALLOWED = new Set<String>{
        'p', 'br', 'hr', 'b', 'strong', 'i', 'em', 'u', 's', 'strike', 'sub', 'sup', 'code', 'pre',
        'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'a', 'span', 'div',
        'table', 'thead', 'tbody', 'tr', 'th', 'td'
    };

    private class ListLevel {
        String tag;
        Integer indent;
        ListLevel(String tag, Integer indent) { this.tag = tag; this.indent = indent; }
    }

    public static String fromAgent(String input) {
        return fromAgent(input, MAX_LENGTH);
    }

    public static String fromAgent(String input, Integer maxLength) {
        if (String.isBlank(input)) {
            return '';
        }
        String s = input.replace('\r\n', '\n').replace('\r', '\n').trim();
        if (!looksLikeHtml(s)) {
            s = anchorsToMarkdown(s);
            s = restoreLineBreaks(s);
        }
        String html = looksLikeHtml(s) ? s : markdownToHtml(s);
        return fit(sanitize(html), maxLength);
    }

    /** Section titles the summary prompt produces; used only to repair text whose line breaks were lost. */
    @TestVisible static final List<String> SECTION_TITLES = new List<String>{
        'Complaint Overview', 'Associated Items', 'Product History Review', 'Analysis and Next Steps',
        'Trends, gaps and next steps'
    };

    static final String RECORD_ROW = '((?:NC|CAPA|CHG|INS|INV|PHR|COM)-\\d+\\s+\\|)';

    /**
     * Agent output often arrives with line breaks missing or only partly kept. This repairs it:
     * lines that are just a section title become headings, an inline " - item" after a
     * sentence becomes a bullet, record rows ("NC-000055 | ...") become bullets and the closing
     * disclaimer becomes its own paragraph. When there are no line breaks at all, titles and
     * "  - item" runs inside the text are split out as well.
     */
    @TestVisible
    static String restoreLineBreaks(String s) {
        if (s == null || s.length() < 120) { return s; }
        List<String> quoted = new List<String>();
        for (String h : SECTION_TITLES) { quoted.add(Pattern.quote(h)); }
        String titles = String.join(quoted, '|');
        if (!s.contains('\n')) {
            s = s.replaceAll('(^|[.!?:]\\s+)(' + titles + ')(?=\\s)', '$1\n\n## $2\n');
            s = s.replaceAll('\\s{2,}([-*\u2022])\\s+', '\n$1 ');
        }
        s = s.replaceAll('(?im)^[ \\t]*(' + titles + ')[ \\t]*:?[ \\t]*$', '## $1');
        s = s.replaceAll('(?<=[.:;!?])[ \\t]+[-\u2022][ \\t]+(?=[A-Z0-9])', '\n- ');
        s = s.replaceAll(';\\s+' + RECORD_ROW, '\n- $1');
        s = s.replaceAll(':[ \\t]+' + RECORD_ROW, ':\n- $1');
        s = s.replaceAll('[ \\t]+(This is an AI-generated draft)', '\n\n$1');
        return s.trim();
    }

    /** Plain text that only carries <a href> links (no other HTML) is turned into markdown links so it is escaped safely. */
    @TestVisible
    static String anchorsToMarkdown(String s) {
        return s.replaceAll('(?is)<a\\s+[^>]*?href\\s*=\\s*[\'\"]([^\'\"]+)[\'\"][^>]*>(.*?)</a>', '[$2]($1)');
    }

    @TestVisible
    static Boolean looksLikeHtml(String s) {
        return Pattern.compile('(?i)<(p|br|ul|ol|li|strong|b|em|i|u|h[1-6]|div|table|blockquote)(\\s[^>]*)?/?>')
            .matcher(s).find();
    }

    // ---------- Markdown -> HTML ----------

    @TestVisible
    static String markdownToHtml(String md) {
        Pattern headingP = Pattern.compile('^(#{1,6})\\s+(.*?)\\s*#*$');
        Pattern ruleP = Pattern.compile('^(-{3,}|\\*{3,}|_{3,})$');
        Pattern bulletP = Pattern.compile('^(\\s*)[-*+\u2022]\\s+(.*)$');
        Pattern numberP = Pattern.compile('^(\\s*)\\d{1,3}[.)]\\s+(.*)$');

        List<String> out = new List<String>();
        List<String> para = new List<String>();
        List<ListLevel> stack = new List<ListLevel>();

        for (String raw : md.split('\n', -1)) {
            String line = raw.replace('\t', '    ');
            String trimmed = line.trim();

            if (trimmed.length() == 0) {
                flushPara(out, para);
                closeLists(out, stack, 0);
                continue;
            }

            Matcher hm = headingP.matcher(trimmed);
            if (hm.matches()) {
                flushPara(out, para);
                closeLists(out, stack, 0);
                Integer level = Math.min(hm.group(1).length() + 1, 6);
                out.add('<h' + level + '><strong>' + inline(hm.group(2)) + '</strong></h' + level + '>');
                continue;
            }
            if (ruleP.matcher(trimmed).matches()) {
                flushPara(out, para);
                closeLists(out, stack, 0);
                out.add('<hr/>');
                continue;
            }

            String listTag = null;
            Integer indent = 0;
            String itemText = null;
            Matcher bm = bulletP.matcher(line);
            Matcher nm = numberP.matcher(line);
            if (bm.matches()) {
                listTag = 'ul';
                indent = bm.group(1).length();
                itemText = bm.group(2);
            } else if (nm.matches()) {
                listTag = 'ol';
                indent = nm.group(1).length();
                itemText = nm.group(2);
            }

            if (listTag != null) {
                flushPara(out, para);
                openListItem(out, stack, listTag, indent);
                out.add('<li>' + inline(itemText.trim()));
            } else {
                closeLists(out, stack, 0);
                para.add(trimmed);
            }
        }
        flushPara(out, para);
        closeLists(out, stack, 0);
        return String.join(out, '');
    }

    private static void flushPara(List<String> out, List<String> para) {
        if (para.isEmpty()) { return; }
        List<String> lines = new List<String>();
        for (String p : para) { lines.add(inline(p)); }
        out.add('<p>' + String.join(lines, '<br/>') + '</p>');
        para.clear();
    }

    /** Opens the right list level for an item; the previous item stays open when nesting. */
    private static void openListItem(List<String> out, List<ListLevel> stack, String tag, Integer indent) {
        if (stack.isEmpty()) {
            out.add('<' + tag + '>');
            stack.add(new ListLevel(tag, indent));
            return;
        }
        ListLevel top = stack[stack.size() - 1];
        if (indent > top.indent) {
            out.add('<' + tag + '>');
            stack.add(new ListLevel(tag, indent));
            return;
        }
        // Same or shallower level: close deeper lists first.
        while (stack.size() > 1 && stack[stack.size() - 1].indent > indent) {
            ListLevel l = stack.remove(stack.size() - 1);
            out.add('</li></' + l.tag + '>');
        }
        ListLevel cur = stack[stack.size() - 1];
        out.add('</li>');
        if (cur.tag != tag && cur.indent >= indent) {
            // A different list type at the same level starts a new list.
            out.add('</' + cur.tag + '><' + tag + '>');
            cur.tag = tag;
        }
    }

    private static void closeLists(List<String> out, List<ListLevel> stack, Integer keep) {
        while (stack.size() > keep) {
            ListLevel l = stack.remove(stack.size() - 1);
            out.add('</li></' + l.tag + '>');
        }
    }

    /** Escapes text, then applies inline markdown. */
    @TestVisible
    static String inline(String text) {
        String s = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
        s = Pattern.compile('\\[([^\\]]+)\\]\\((https?://[^\\s)]+|mailto:[^\\s)]+|/[^\\s)/][^\\s)]*)\\)')
            .matcher(s).replaceAll('<a href="$2">$1</a>');
        s = Pattern.compile('`([^`]+)`').matcher(s).replaceAll('<code>$1</code>');
        s = Pattern.compile('\\*\\*(.+?)\\*\\*').matcher(s).replaceAll('<strong>$1</strong>');
        s = Pattern.compile('__(.+?)__').matcher(s).replaceAll('<strong>$1</strong>');
        s = Pattern.compile('(?<![\\w*])\\*(?![\\s*])(.+?)(?<![\\s*])\\*(?![\\w*])').matcher(s).replaceAll('<em>$1</em>');
        s = Pattern.compile('(?<![\\w_])_(?![\\s_])(.+?)(?<![\\s_])_(?![\\w_])').matcher(s).replaceAll('<em>$1</em>');
        return s;
    }

    /**
     * Bolds every record number (NC, CAPA, CHG, INS, INV, PHR, PHA, COM) that is plain text.
     * Numbers already inside <strong>, <b> or <a> are left alone, and tags are never touched.
     */
    public static String boldRecordIds(String html) {
        if (String.isBlank(html)) { return html; }
        Matcher m = Pattern.compile(
            '(?is)<(strong|b|a)\\b[^>]*>.*?</\\1>|<[^>]+>|(?<![\\w-])((?:NC|CAPA|CHG|INS|INV|PHR|PHA|COM)-\\d+)(?![\\w-])'
        ).matcher(html);
        String out = '';
        Integer last = 0;
        while (m.find()) {
            out += html.substring(last, m.start());
            out += m.group(2) != null ? '<strong>' + m.group(2) + '</strong>' : m.group(0);
            last = m.end();
        }
        return out + html.substring(last);
    }

    // ---------- Sanitizer ----------

    @TestVisible
    public static String sanitize(String html) {
        if (String.isBlank(html)) { return ''; }
        String s = html.replaceAll('(?is)<!--.*?-->', '');
        s = s.replaceAll('(?is)<(script|style|iframe|object|embed)\\b.*?</\\1\\s*>', '');
        s = s.replaceAll('(?is)<(script|style|iframe|object|embed)\\b[^>]*>', '');

        Matcher m = Pattern.compile('<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>').matcher(s);
        List<String> parts = new List<String>();
        Integer last = 0;
        while (m.find()) {
            parts.add(s.substring(last, m.start()).replace('<', '&lt;'));
            parts.add(rebuildTag(m.group(1) == '/', m.group(2).toLowerCase(), m.group(3)));
            last = m.end();
        }
        parts.add(s.substring(last).replace('<', '&lt;'));
        return String.join(parts, '');
    }

    private static String rebuildTag(Boolean closing, String tag, String attrs) {
        if (!ALLOWED.contains(tag)) { return ''; }
        if (tag == 'br' || tag == 'hr') { return closing ? '' : '<' + tag + '/>'; }
        if (closing) { return '</' + tag + '>'; }
        if (tag == 'a') {
            Matcher hm = Pattern.compile('(?is)href\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')').matcher(attrs == null ? '' : attrs);
            if (hm.find()) {
                String href = (hm.group(1) != null ? hm.group(1) : hm.group(2)).trim();
                String lower = href.toLowerCase();
                if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('mailto:')
                    || (lower.startsWith('/') && !lower.startsWith('//'))) {
                    return '<a href="' + href.replace('"', '&quot;') + '">';
                }
            }
            return '<a>';
        }
        return '<' + tag + '>';
    }

    // ---------- Length ----------

    /** Cuts at the end of a complete top-level block so no tag is left open. */
    @TestVisible
    static String fit(String html, Integer maxLength) {
        if (html == null || html.length() <= maxLength) { return html; }
        Integer cap = maxLength - TRUNCATION_NOTE.length();
        Matcher m = Pattern.compile('(?i)<(/?)(ul|ol|table|blockquote|pre|p|h[1-6])\\b[^>]*>').matcher(html);
        Integer depth = 0;
        Integer safe = -1;
        while (m.find()) {
            if (m.end() > cap) { break; }
            Boolean closing = m.group(1) == '/';
            String tag = m.group(2).toLowerCase();
            Boolean container = tag == 'ul' || tag == 'ol' || tag == 'table' || tag == 'blockquote' || tag == 'pre';
            if (container) {
                depth += closing ? -1 : 1;
                if (closing && depth <= 0) { depth = 0; safe = m.end(); }
            } else if (closing && depth == 0) {
                safe = m.end();
            }
        }
        if (safe > 0) {
            return html.substring(0, safe) + TRUNCATION_NOTE;
        }
        String plain = html.replaceAll('<[^>]*>', '').left(cap - 7).replaceAll('&[a-zA-Z0-9#]{0,8}$', '');
        return '<p>' + plain + '</p>' + TRUNCATION_NOTE;
    }
}
