import { LightningElement, api, track } from 'lwc';
import startSession from '@salesforce/apex/AskCqService.startSession';
import sendMessage from '@salesforce/apex/AskCqService.sendMessage';
import endSession from '@salesforce/apex/AskCqService.endSession';

/**
 * Ask CQ: the Scout agent in a popover on any record page. Other components call `ask(question)`
 * to open it already focused on a question (a row's ✦ button, for example).
 */
export default class AskCqPopover extends LightningElement {
    @api recordId;
    /** Comma-separated ready questions for this page or step. */
    @api suggestions = 'Why are these records relevant?,What is the scrap rate?,What is left on this review?';
    /** Optional: another agent's Id (the Scout Checklist agent, say). Blank = the Id in AskCqSecrets. */
    _agentId;
    @api get agentId() { return this._agentId; }
    set agentId(v) {
        if (v !== this._agentId) {
            this._agentId = v;
            if (this.sessionId) { this.close(); }   // a different agent needs a new session
        }
    }

    @track messages = [];
    open = false;
    busy = false;
    draft = '';
    error;
    sessionId;
    sequence = 1;
    _seq = 0;

    get suggestionList() {
        return (this.suggestions || '').split(',').map((s) => s.trim()).filter(Boolean).map((q) => ({ key: q, label: q }));
    }
    get hasMessages() { return this.messages.length > 0; }
    get sendDisabled() { return this.busy || !this.draft; }

    toggle() {
        if (this.open) { this.close(); } else { this.openPanel(); }
    }

    async openPanel() {
        this.open = true;
        this.error = undefined;
        if (!this.sessionId) { await this.start(); }
        this.focusInput();
    }

    async close() {
        this.open = false;
        const id = this.sessionId;
        this.sessionId = undefined;
        this.sequence = 1;
        this.messages = [];
        if (id) { try { await endSession({ sessionId: id }); } catch (e) { /* session will expire on its own */ } }
    }

    @api
    async ask(question) {
        await this.openPanel();
        if (this.sessionId) { await this.send(question); }
    }

    async start() {
        this.busy = true;
        try {
            const r = await startSession({ recordId: this.recordId, agentId: this._agentId });
            this.sessionId = r.sessionId;
            this.sequence = r.nextSequence;
            if (r.text) { this.push('agent', r.text); }
        } catch (e) {
            this.error = this.errorText(e);
        } finally {
            this.busy = false;
        }
    }

    async send(text) {
        if (!text || !this.sessionId) { return; }
        this.push('user', text);
        this.draft = '';
        this.busy = true;
        try {
            const r = await sendMessage({ sessionId: this.sessionId, sequenceId: this.sequence, text, recordId: this.recordId });
            this.sequence = r.nextSequence;
            this.push('agent', r.text || '(no answer)');
        } catch (e) {
            this.error = this.errorText(e);
        } finally {
            this.busy = false;
            this.scrollToEnd();
        }
    }

    handleSuggestion(event) { this.send(event.currentTarget.dataset.q); }
    handleDraft(event) { this.draft = event.target.value; }
    handleKey(event) { if (event.key === 'Enter' && !this.sendDisabled) { this.send(this.draft); } }
    handleSend() { this.send(this.draft); }

    push(role, text) {
        this._seq += 1;
        this.messages = [...this.messages, {
            key: 'm' + this._seq,
            text,
            cls: role === 'user' ? 'msg user' : 'msg agent',
            isAgent: role === 'agent'
        }];
        this.scrollToEnd();
    }

    scrollToEnd() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { const el = this.template.querySelector('.log'); if (el) { el.scrollTop = el.scrollHeight; } }, 0);
    }
    focusInput() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { const el = this.template.querySelector('lightning-input'); if (el) { el.focus(); } }, 0);
    }
    errorText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Ask CQ could not reach the agent.';
    }
}
