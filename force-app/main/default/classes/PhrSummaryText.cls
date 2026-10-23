/** Small text clean-ups for the PHR Summary. */
public with sharing class PhrSummaryText {

    /**
     * Removes the "This is an AI-generated draft ..." line that the prompt may add, whether it is its own
     * paragraph or the last sentence of one. Works on markdown, plain text or HTML.
     */
    public static String stripDisclaimer(String s) {
        if (s == null) { return null; }
        String out = s.replaceAll('(?is)<p>\\s*(?:<(?:em|i|strong|b)>\\s*)*[*_]{0,2}\\s*This is an AI-generated draft.*?</p>', '');
        out = out.replaceAll('(?i)[ \\t]*[*_]{0,2}This is an AI-generated draft[^.<\\n]*\\.?[*_]{0,2}', '');
        out = out.replaceAll('(?is)(<p>\\s*(?:<br\\s*/?>)?\\s*</p>\\s*)+$', '');
        return out.trim();
    }
}
