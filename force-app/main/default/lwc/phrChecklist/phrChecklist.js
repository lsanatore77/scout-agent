import { LightningElement, api } from 'lwc';

/**
 * phrChecklist
 * Agentforce output renderer for PhrChecklistResult: every Product History Review checklist question,
 * the suggested answer, whether the agent is sure, and what the suggestion is based on.
 * After the answers are saved, saved rows show a tick. Display only: saving is done by the action
 * once the person confirms in the conversation.
 */
const PILL = {
    suggested: { text: 'Suggested', cls: 'pill pill-suggested' },
    unsure: { text: 'Not sure – please answer', cls: 'pill pill-unsure' },
    saved: { text: '✓ Saved', cls: 'pill pill-saved' }
};

export default class PhrChecklist extends LightningElement {
    @api value;

    get _data() {
        return this.value || {};
    }

    get intro() {
        return this._data.intro;
    }

    get cardTitle() {
        return this._data.checklistName || 'PHR checklist';
    }

    get items() {
        const list = Array.isArray(this._data.items) ? this._data.items : [];
        return list.map((q, index) => {
            const status = q.status || (q.sure === false ? 'unsure' : 'suggested');
            const pill = PILL[status] || PILL.suggested;
            const answer = q.suggestedAnswer || '';
            return {
                key: 'q-' + index,
                number: q.questionNumber || String(index + 1).padStart(3, '0'),
                question: q.question,
                answer,
                sure: status !== 'unsure' && !!answer,
                basis: q.basis,
                pill: pill.text,
                pillClass: pill.cls,
                chipClass: 'chip ' + (answer.toLowerCase() === 'yes' ? 'chip-yes' : answer.toLowerCase() === 'no' ? 'chip-no' : 'chip-other'),
                rowClass: 'row' + (status === 'unsure' ? ' row-unsure' : '')
            };
        });
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get footer() {
        const d = this._data;
        const unsure = d.unsureCount || 0;
        if (d.saved) {
            const saved = d.savedCount || 0;
            return saved + (saved === 1 ? ' answer saved' : ' answers saved') + (unsure ? ' · ' + unsure + ' left for you to answer' : '');
        }
        const sure = d.sureCount || 0;
        return sure + (sure === 1 ? ' answer ready to save' : ' answers ready to save') + (unsure ? ' · ' + unsure + ' not sure' : '');
    }

    get errorText() {
        const d = this._data;
        if (d.success === false) return d.errorMessage || 'Something went wrong.';
        return d.errorMessage || '';
    }

    get hasError() {
        return !!this.errorText;
    }
}
