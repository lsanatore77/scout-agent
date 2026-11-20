import { LightningElement, api } from 'lwc';

/**
 * cqWsSuggestion: the CQ.AI Suggests card. Label, the verdict (red when tone is "crit"), the reason in small text,
 * then What We Know: questions, where each answer came from, and the answer in bold.
 */
export default class CqWsSuggestion extends LightningElement {
    @api verdict;
    @api why;
    /** "crit" shows the verdict in red (an action is needed); anything else in ink */
    @api tone;
    /** the question the label's "why" asks CQ.AI; defaults to asking about the verdict */
    @api question;
    @api knowTitle = 'What We Know';
    /** [{ q, a, src, unknown }] */
    @api know = [];

    get verdictCls() { return 'cq-ai-verdict' + (this.tone === 'crit' ? ' crit' : ''); }
    get hasKnow() { return (this.know || []).length > 0; }
    get knowRows() { return this.know || []; }
}
