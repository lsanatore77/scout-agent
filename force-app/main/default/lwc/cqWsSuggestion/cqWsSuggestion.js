import { LightningElement, api } from 'lwc';

/**
 * cqWsSuggestion: the CQ.AI Suggests card. Label, the verdict (red when tone is "crit"), the reason in small text,
 * the person's justification for the review, then What We Know: questions, where each answer came from, and the
 * answer in bold, with a red mark on a Yes that needs attention.
 */
export default class CqWsSuggestion extends LightningElement {
    @api verdict;
    @api why;
    /** "crit" shows the verdict in red (an action is needed); anything else in ink */
    @api tone;
    /** the question the label's "why" asks CQ.AI; defaults to asking about the verdict */
    @api question;
    /** the person's reason for the review, quoted under the verdict */
    @api justification;
    @api knowTitle = 'What We Know';
    /** questions, separated by |, whose Yes answer gets a red mark (e.g. "Is there a safety risk?|Was anyone injured?") */
    @api flagWhenYes;
    /** [{ q, a, src, unknown }] */
    @api know = [];

    get verdictCls() { return 'cq-ai-verdict' + (this.tone === 'crit' ? ' crit' : ''); }
    get hasKnow() { return (this.know || []).length > 0; }
    get knowRows() {
        const flagged = new Set(String(this.flagWhenYes || '').split('|').map((q) => q.trim()).filter(Boolean));
        return (this.know || []).map((k) => ({ ...k, flag: !k.unknown && flagged.has(k.q) && /^yes\b/i.test(String(k.a || '')) }));
    }
}
