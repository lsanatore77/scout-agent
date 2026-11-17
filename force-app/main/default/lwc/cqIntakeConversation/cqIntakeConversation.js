import { LightningElement, track } from 'lwc';
import startChat from '@salesforce/apex/CqIntakeChat.start';
import respond from '@salesforce/apex/CqIntakeChat.respond';
import submitReport from '@salesforce/apex/CqEventIntake.submitReport';

export default class CqIntakeConversation extends LightningElement {
    @track messages = [];
    @track choices = [];
    @track understood = [];
    @track stillNeeded = [];

    description = '';
    answers = [];
    pendingQuestionId = null;

    draftJson = null;
    ready = false;
    busy = false;
    done = false;
    sentName = '';
    sentUrgent = false;

    draft = '';
    seq = 0;
    canSpeak = false;
    listening = false;
    micStatus = '';
    micTone = 'idle';   // idle | live | good | bad
    recognition;

    canSpeakOut = false;   // the browser can read questions aloud
    speakOut = true;       // the reporter wants it to

    connectedCallback() {
        this.canSpeak = typeof (window.SpeechRecognition || window.webkitSpeechRecognition) === 'function';
        if (this.canSpeak) { this.micStatus = 'Tap Speak to talk instead of typing.'; this.micTone = 'idle'; }
        this.canSpeakOut = typeof window.speechSynthesis !== 'undefined';
        startChat()
            .then((t) => { this.pushAi(t.reply); this.speak(t.reply); })
            .catch((e) => this.pushAi(this.msg(e)));
    }

    disconnectedCallback() {
        try { if (this.canSpeakOut) { window.speechSynthesis.cancel(); } } catch (e) { /* ignore */ }
    }

    handleInput(e) { this.draft = e.target.value; }
    handleKey(e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.send(this.draft); } }
    handleSendClick() { this.send(this.draft); }
    handleChoice(e) { this.send(e.target.dataset.value); }

    send(text) {
        const said = (text || '').trim();
        if (!said || this.busy || this.done) { return; }
        this.pushMe(said);
        this.draft = '';
        if (this.pendingQuestionId) {
            // Answering a specific question: record the answer, keep it out of the narrative.
            this.answers = this.answers
                .filter((a) => a.questionId !== this.pendingQuestionId)
                .concat([{ questionId: this.pendingQuestionId, answer: said }]);
        } else {
            // Free description of what happened.
            this.description = this.description ? this.description + ' ' + said : said;
        }
        this.turn();
    }

    turn() {
        this.busy = true;
        this.choices = [];
        const state = JSON.stringify({ description: this.description, answers: this.answers });
        respond({ stateJson: state })
            .then((t) => {
                this.understood = (t.understood || []).map((f, i) => ({ ...f, k: 'u' + i }));
                this.stillNeeded = (t.stillNeeded || []).map((s, i) => ({ k: 's' + i, text: s }));
                this.choices = (t.choices || []).map((c, i) => ({ k: 'c' + i, value: c }));
                this.pendingQuestionId = t.askQuestionId || null;
                this.ready = t.ready === true;
                this.draftJson = t.draftJson || null;
                this.pushAi(t.reply);
                this.speak(t.reply);
                this.busy = false;
            })
            .catch((e) => { this.pushAi(this.msg(e)); this.busy = false; });
    }

    handleSubmit() {
        if (!this.draftJson || this.busy) { return; }
        this.busy = true;
        submitReport({ payload: this.draftJson })
            .then((sent) => {
                this.done = true;
                this.sentName = sent.name;
                this.sentUrgent = sent.urgent === true;
                const note = 'Sent. This is ' + sent.name + ', now waiting for a reviewer' +
                    (sent.urgent ? ' — flagged urgent, so it goes to the top of the queue.' : '.');
                this.pushAi(note);
                this.speak(note);
                this.busy = false;
            })
            .catch((e) => { this.pushAi(this.msg(e)); this.busy = false; });
    }

    // ---- voice out ----

    speak(text) {
        if (!this.canSpeakOut || !this.speakOut || !text) { return; }
        try {
            window.speechSynthesis.cancel();   // don't let replies pile up
            const u = new SpeechSynthesisUtterance(text);
            u.lang = 'en-US';
            u.rate = 1;
            window.speechSynthesis.speak(u);
        } catch (e) { /* ignore */ }
    }

    toggleSpeak() {
        this.speakOut = !this.speakOut;
        if (!this.speakOut) { try { window.speechSynthesis.cancel(); } catch (e) { /* ignore */ } }
    }

    handleReplay(e) {
        const id = Number(e.currentTarget.dataset.id);
        const m = this.messages.find((x) => x.id === id);
        if (m && m.isAi) { this.speak(m.text); }
    }

    // ---- voice ----

    handleMic() {
        if (!this.canSpeak) { return; }
        if (this.listening) { this.stopListening(); return; }

        const Rec = window.SpeechRecognition || window.webkitSpeechRecognition;
        this.recognition = new Rec();
        this.recognition.lang = 'en-US';
        this.recognition.interimResults = true;   // show words as they come, and catch short phrases
        this.recognition.continuous = false;

        let captured = '';   // everything finalized this session

        this.setMic('live', 'Starting the microphone…');

        this.recognition.onstart = () => { this.listening = true; this.setMic('live', 'Listening… speak now.'); };
        this.recognition.onaudiostart = () => { this.setMic('live', 'Listening… I can hear the mic.'); };
        this.recognition.onspeechstart = () => { this.setMic('live', 'Got your voice—keep going…'); };
        this.recognition.onresult = (ev) => {
            let interim = '';
            for (let i = ev.resultIndex; i < ev.results.length; i++) {
                const r = ev.results[i];
                if (r.isFinal) { captured += (captured ? ' ' : '') + r[0].transcript.trim(); }
                else { interim += r[0].transcript; }
            }
            if (interim.trim()) { this.setMic('live', 'Hearing: “' + interim.trim() + '”…'); }
            if (captured.trim()) { this.setMic('good', 'Got it: “' + captured.trim() + '” — check it, then hit Send.'); }
        };
        this.recognition.onnomatch = () => { this.setMic('bad', 'Didn’t catch any words—tap Speak and talk clearly.'); };
        this.recognition.onerror = (ev) => { this.listening = false; this.setMic('bad', this.micError(ev && ev.error)); };
        this.recognition.onend = () => {
            this.listening = false;
            const said = captured.trim();
            if (said) {
                this.draft = this.draft ? this.draft + ' ' + said : said;
                this.setMic('good', 'Added: “' + said + '” — check it, then hit Send.');
            } else if (this.micTone !== 'bad') {
                this.setMic('bad', 'I didn’t catch anything—tap Speak and talk clearly.');
            }
        };

        try { this.recognition.start(); }
        catch (e) { this.listening = false; this.setMic('bad', 'Couldn’t start the mic—tap Speak to try again.'); }
    }

    stopListening() {
        this.listening = false;
        if (this.recognition) { try { this.recognition.stop(); } catch (e) { /* ignore */ } }
        this.setMic('idle', 'Stopped. Tap Speak to talk again.');
    }

    micError(code) {
        switch (code) {
            case 'not-allowed':
            case 'service-not-allowed':
                return 'Microphone is blocked. Allow mic access for this site in your browser, then tap Speak.';
            case 'no-speech':
                return 'I didn’t hear anything—tap Speak and talk a little louder.';
            case 'audio-capture':
                return 'No microphone found. Check your input device in system sound settings.';
            case 'network':
                return 'Speech service couldn’t be reached—check your connection and try again.';
            case 'aborted':
                return 'Stopped. Tap Speak to talk again.';
            default:
                return 'Mic trouble—tap Speak to try again.';
        }
    }

    setMic(tone, text) { this.micTone = tone; this.micStatus = text; }

    pushAi(text) { if (text) { this.messages = this.messages.concat([{ id: ++this.seq, who: 'ai', text, isAi: true }]); } }
    pushMe(text) { this.messages = this.messages.concat([{ id: ++this.seq, who: 'me', text, isAi: false }]); }
    msg(e) { return (e && e.body && e.body.message) ? e.body.message : 'Something went wrong. Try again.'; }

    get hasChoices() { return this.choices.length > 0 && !this.done; }
    get hasUnderstood() { return this.understood.length > 0; }
    get hasStillNeeded() { return this.stillNeeded.length > 0 && !this.ready; }
    get showSubmit() { return this.ready && !this.done; }
    get inputDisabled() { return this.busy || this.done; }
    get inputPlaceholder() {
        if (this.pendingQuestionId) { return 'Type your answer…'; }
        if (this.ready) { return 'Add anything else, or tap Send…'; }
        return 'Type what happened…';
    }
    get showMicStatus() { return this.canSpeak && this.micStatus && !this.done; }
    get soundLabel() { return this.speakOut ? '🔊 Sound on' : '🔇 Sound off'; }
    get soundClass() { return this.speakOut ? 'sound on' : 'sound'; }
    get micStatusClass() { return 'micstatus ' + this.micTone; }
    get micClass() { return this.listening ? 'mic listening' : 'mic'; }
    get micLabel() { return this.listening ? 'Stop' : 'Speak'; }
}
