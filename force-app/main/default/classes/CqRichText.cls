/**
 * CqRichText: turns a CQ rich-text description into plain text that keeps its paragraphs.
 * CQ keeps a plain copy of the NC description, but that copy drops paragraph breaks, so the
 * workspaces read the rich-text field through here instead.
 */
public with sharing class CqRichText {
    /** Plain text with a blank line between paragraphs. Falls back to the plain copy when there is no rich text. */
    public static String toText(String rich, String plain) {
        if (String.isBlank(rich)) { return plain == null ? null : plain.stripHtmlTags(); }
        String s = rich.replaceAll('(?i)<br\\s*/?>', '[[BR]]').replaceAll('(?i)</(p|div|li|h[1-6])>', '[[P]]');
        s = s.stripHtmlTags();
        if (s == null) { return plain; }
        s = s.replace('[[BR]]', '\n').replace('[[P]]', '\n\n');
        s = s.replaceAll('[ \\t]*\\n[ \\t]*', '\n').replaceAll('\\n{3,}', '\n\n').trim();
        return String.isBlank(s) ? plain : s;
    }
}
