import { LightningElement, api } from 'lwc';

/**
 * A clickable ✦ CQ.AI Suggests marker. Clicking it asks Ask CQ.AI why CQ.AI suggests this item:
 * the Ask CQ.AI popover on the page picks up the question and answers it. The marker never selects
 * the card or row it sits in.
 *   variant: pill (purple chip), tag (purple text), label (bold purple text before a suggestion), star (✦ only)
 *   question: the full question, or lead + subject + tail ("Why does CQ.AI suggest " + subject + "?")
 */
export default class CqAiWhy extends LightningElement {
    @api variant = 'pill';
    @api text = 'CQ.AI Suggests';
    @api subject;
    @api question;
    @api lead = 'Why does CQ.AI suggest ';
    @api tail = '?';
    @api tip = 'Ask CQ.AI why';

    // the pill is the shared CQ.AI pill (.cq-pill.ai in cqStyles); the other variants are plain purple text
    get cls() { const v = this.variant || 'pill'; return 'b ' + v + (v === 'pill' ? ' cq-pill ai' : ''); }
    get hasText() { return this.variant !== 'star' && !!this.text; }
    get ask() { return this.question || (this.lead || '') + (this.subject || 'this') + (this.tail || ''); }

    handleClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('cqaiask', { detail: { question: this.ask }, bubbles: true, composed: true }));
    }
    handleKey(event) { event.stopPropagation(); }
}
