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
        // Flag the answers CQ.AI is calling out (affirmative risk signals for now).
        const answers = (d.answers || []).map((a) => {
            const v = (a.answer || '').trim().toLowerCase();
            const hot = v === 'yes';
            return { question: a.question, answer: a.answer, cls: hot ? 'qarow hot' : 'qarow' };
        });
        return {
            ...d,
            answers,
            summary: this.buildSummary(d, answers, becomes),
            reasons: (d.suggestion && d.suggestion.reasons) || [],
            choices,
            hasOpen: (d.openOnPart || []).length > 0,
            hasSimilar: (d.similarEvents || []).length > 0,
            partLine: d.partNumber ? (d.partNumber + (d.partName ? ' · ' + d.partName : '')) : '—'
        };
    }

    buildSummary(d, answers, becomes) {
        const low = (s) => (s || '').toLowerCase();
        const flagged = (re) => answers.some((a) => a.cls.indexOf('hot') >= 0 && re.test(low(a.question)));
        const prod = flagged(/product/);
        const injury = flagged(/injur|hurt/);
        const safety = flagged(/safety|risk/);
        const where = d.whereFound ? ' (' + d.whereFound + ')' : '';
        const internal = !/customer/.test(low(d.whereFound));
        if (becomes === 'New Complaint') {
            return 'A Complaint fits better than a Nonconformance here: the problem was raised by a customer' + where + ' rather than caught internally. A product was affected, so it is a genuine quality issue, not one to dismiss.';
        }
        if (becomes === 'New Nonconformance') {
            let s = 'A Nonconformance fits better than a Complaint: the problem was caught ' + (internal ? 'inside our own operations' : 'internally') + where + ', not raised by a customer. ';
            s += (prod || injury)
                ? 'A product was affected' + (injury ? ' and an injury was reported' : '') + ', so this is clearly a quality issue, not something to dismiss. '
                : 'There is product-quality impact, so it should not be dismissed. ';
            if (safety) { s += 'With safety at risk, triage should start High.'; }
            return s.trim();
        }
        return 'There is little sign of a product-quality or safety impact, so this may not be a quality issue. Confirm the answers below before dismissing it.';
    }

    get hasReview() { return !!this.review; }
}
