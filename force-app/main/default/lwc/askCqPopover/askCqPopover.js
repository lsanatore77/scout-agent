import { LightningElement, api, track } from 'lwc';
import startSession from '@salesforce/apex/AskCqService.startSession';
import sendMessage from '@salesforce/apex/AskCqService.sendMessage';
import endSession from '@salesforce/apex/AskCqService.endSession';
import agentIdFor from '@salesforce/apex/AskCqAgents.idFor';

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

    /** Optional: an agent's API name (CQAI_Field_Action, say), looked up in this org. Used when no agentId is given. */
    _agentName;
    @api get agentName() { return this._agentName; }
    set agentName(v) {
        if (v !== this._agentName) {
            this._agentName = v;
            this._namedId = undefined;
            if (this.sessionId) { this.close(); }
        }
    }
    _namedId;
    /** Optional: the step or tab the user has open. Sent ahead of a question when it has changed, never shown. */
    @api step;
    _sentStep;

    @track messages = [];
    open = false;
    busy = false;
    draft = '';
    error;
    sessionId;
    sequence = 1;
    _seq = 0;
    asked = false;        // the user has sent a first question
    _starting;            // the in-flight startSession, so two callers share one session

    get suggestionList() {
        return (this.suggestions || '').split(',').map((s) => s.trim()).filter(Boolean).map((q) => ({ key: q, label: q }));
    }
    get hasMessages() { return this.messages.length > 0; }
    /** The ready questions stay until the user asks something, whatever the agent has said. */
    get showSuggestions() { return !this.asked; }
    get sendDisabled() { return this.busy || !this.draft; }

    toggle() {
        if (this.open) { this.close(); } else { this.openPanel(); }
    }

    async openPanel() {
        // Open on the ready questions. The session starts quietly behind them; the agent speaks only when asked.
        this.open = true;
        this.error = undefined;
        this.focusInput();
        this.ensureSession();
    }

    async close() {
        this.open = false;
        const id = this.sessionId;
        this.sessionId = undefined;
        this.sequence = 1;
        this.messages = [];
        this.asked = false;
        this._starting = undefined;
        this._sentStep = undefined;
        if (id) { try { await endSession({ sessionId: id }); } catch (e) { /* session will expire on its own */ } }
    }

    @api
    async ask(question) {
        // Show the question at once; if the session is still starting, wait for it rather than drop the click.
        if (!question) { return; }
        this.open = true;
        this.error = undefined;
        this.push('user', question);
        this.asked = true;
        this.draft = '';
        this.busy = true;
        await this.ensureSession();
        if (this.sessionId) { await this.send(question, true); } else { this.busy = false; }
        this.focusInput();
    }

    /** Starts the agent session once; later callers share the same promise. The greeting is not shown. */
    ensureSession() {
        if (this.sessionId) { return Promise.resolve(); }
        if (!this._starting) {
            const p = this.resolveAgent()
                .then((agentId) => startSession({ recordId: this.recordId, agentId }))
                .then((r) => {
                    if (this._starting !== p) { endSession({ sessionId: r.sessionId }).catch(() => {}); return; }   // closed meanwhile
                    this.sessionId = r.sessionId; this.sequence = r.nextSequence;
                })
                .catch((e) => { if (this._starting === p) { this.error = this.errorText(e); } })
                .finally(() => { if (this._starting === p) { this._starting = undefined; } });
            this._starting = p;
        }
        return this._starting;
    }

    /** The agent to talk to: the agentId given, else the named agent's Id, else blank (the default agent). */
    async resolveAgent() {
        if (this._agentId || !this._agentName) { return this._agentId; }
        if (!this._namedId) {
            this._namedId = await agentIdFor({ developerName: this._agentName });
            if (!this._namedId) { throw new Error('The ' + this._agentName.replace(/_/g, ' ') + ' agent is not set up in this org yet.'); }
        }
        return this._namedId;
    }

    async send(text, alreadyShown) {
        if (!text || !this.sessionId) { return; }
        if (!alreadyShown) { this.push('user', text); }
        this.draft = '';
        this.busy = true;
        try {
            // The step goes ahead of the question only when it has changed; the user sees just their question.
            const step = this.step && this.step !== this._sentStep ? this.step : '';
            const sent = step ? '(I am on the ' + step + ' step.) ' + text : text;
            const r = await sendMessage({ sessionId: this.sessionId, sequenceId: this.sequence, text: sent, recordId: this.recordId });
            if (step) { this._sentStep = step; }
            this.sequence = r.nextSequence;
            this.push('agent', r.text || '(no answer)');
            if (/\b(saved|added|attached|updated)\b/i.test(r.text || '')) {
                this.dispatchEvent(new CustomEvent('changed', { bubbles: true, composed: true }));
            }
        } catch (e) {
            this.error = this.errorText(e);
        } finally {
            this.busy = false;
            this.scrollToEnd();
        }
    }

    handleSuggestion(event) { this.ask(event.currentTarget.dataset.q); }
    handleDraft(event) { this.draft = event.target.value; }
    handleKey(event) { if (event.key === 'Enter' && !this.sendDisabled) { this.ask(this.draft); } }
    handleSend() { this.ask(this.draft); }

    push(role, text) {
        this._seq += 1;
        const key = 'm' + this._seq;
        this.messages = [...this.messages, {
            key,
            text,
            cls: role === 'user' ? 'msg user' : 'msg agent',
            isAgent: role === 'agent',
            blocks: role === 'agent' ? this.blocks(text, key) : []
        }];
        this.scrollToEnd();
    }

    /**
     * An answer as rows: "- " lines become bullets with a hanging indent (wrapped text lines up under the text,
     * not the marker), other lines stay paragraphs, a blank line leaves a small gap. Record numbers such as
     * L26-0922 get a non-breaking hyphen so they never split across lines.
     */
    blocks(text, key) {
        const keep = (s) => s.replace(/([A-Za-z0-9])-(?=[A-Za-z0-9])/g, '$1‑');
        const out = [];
        (text || '').split('\n').forEach((line, i) => {
            const m = line.match(/^(\s*)[-*•]\s+(.*)$/);
            const b = { key: key + 'b' + i, first: out.length === 0 };
            if (m) {
                const nested = m[1].length >= 2;
                out.push({ ...b, isItem: true, text: keep(m[2]), cls: 'blk li' + (nested ? ' sub' : '') });
            } else if (!line.trim()) {
                if (out.length) { out.push({ ...b, first: false, isGap: true, cls: 'blk gap' }); }
            } else {
                out.push({ ...b, isPara: true, text: keep(line), cls: 'blk p' });
            }
        });
        while (out.length && out[out.length - 1].isGap) { out.pop(); }
        return out;
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
        return (e && e.body && e.body.message) || (e && e.message) || 'Ask CQ.AI could not reach the agent.';
    }
}
