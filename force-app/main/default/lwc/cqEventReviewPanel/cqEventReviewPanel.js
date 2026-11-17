import { LightningElement, api, wire } from 'lwc';
import getReview from '@salesforce/apex/CqEventReview.getReview';

export default class CqEventReviewPanel extends LightningElement {
    @api recordId;
    review;
    error;

    @wire(getReview, { eventId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.review = this.shape(data);
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) ? error.body.message : 'Could not load the review.';
            this.review = undefined;
        }
    }

    shape(d) {
        const becomes = d.suggestion ? d.suggestion.becomes : '';
        const choices = [
            { key: 'nc', label: 'New Nonconformance', ai: becomes === 'New Nonconformance' },
            { key: 'cp', label: 'New Complaint', ai: becomes === 'New Complaint' },
            { key: 'add', label: 'Add to an Open Record', ai: false },
            { key: 'no', label: 'Not a Quality Issue', ai: false }
        ].map((c) => ({ ...c, cls: c.ai ? 'choice ai' : 'choice', mark: c.ai ? '✦' : '' }));
        return {
            ...d,
            reasons: (d.suggestion && d.suggestion.reasons) || [],
            choices,
            hasOpen: (d.openOnPart || []).length > 0,
            hasSimilar: (d.similarEvents || []).length > 0,
            partLine: d.partNumber ? (d.partNumber + (d.partName ? ' · ' + d.partName : '')) : '—'
        };
    }

    get hasReview() { return !!this.review; }
}
