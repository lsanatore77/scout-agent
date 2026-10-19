import { LightningElement, api } from 'lwc';

/**
 * phrChecklist
 * Agentforce output renderer for PhrChecklistResult: the reviewer checklist,
 * one question per row, with the answer suggested from the lead records and
 * the records it is based on. Display only; the person reviews and answers
 * on the Product History Review.
 */
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
        return list.map((q, index) => ({
            key: 'q-' + index,
            number: q.questionNumber || String(index + 1).padStart(2, '0'),
            question: q.question,
            answer: q.suggestedAnswer || 'No suggestion',
            basis: q.basis,
            answerClass: q.suggestedAnswer ? 'answer' : 'answer answer-none'
        }));
    }

    get hasItems() {
        return this.items.length > 0;
    }

    get errorText() {
        return this._data.success === false ? this._data.errorMessage || 'Something went wrong.' : '';
    }

    get hasError() {
        return !!this.errorText;
    }
}
