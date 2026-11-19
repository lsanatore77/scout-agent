import { LightningElement, track } from 'lwc';
import respond from '@salesforce/apex/CqIntakeChat.respond';
import submitReport from '@salesforce/apex/CqEventIntake.submitReport';
import fetchClip from '@salesforce/apex/CqIntakeChat.clip';

/**
 * Intake in two stages:
 *   compose  - one big box where the reporter tells the whole story (typed or spoken, live).
 *   chat     - on Submit the story compacts into a "Your report" card and CQ.AI asks only for
 *              what's still missing, one gap at a time. A later thought typed in the chat folds
 *              back into the report (the engine re-reads the whole description each turn).
 */
export default class CqIntakeConversation extends LightningElement {
    @track messages = [];
    @track choices = [];
    @track understood = [];
    @track stillNeeded = [];

    stage = 'compose';     // compose (big box) -> chat (clarifying Q&A)
    story = '';            // the big description box, compose stage
    description = '';      // the narrative the engine reads; grows as details are added through chat
    answers = [];
    pendingQuestionId = null;
    pendingFeedsDescription = false;   // the lot/part prompt: its answer is also description
    lotGate = null;        // the lot prompt is a Yes/No first: 'ask' shows the chips, 'open' shows the box for the number

    draftJson = null;
    ready = false;
    busy = false;
    done = false;
    sentName = '';
    sentUrgent = false;

    draft = '';            // chat composer
    seq = 0;
    canSpeak = false;
    listening = false;
    micTarget = 'story';   // where live dictation writes: 'story' | 'draft'
    micStatus = '';
    micTone = 'idle';      // idle | live | good | bad
    recognition;

    canSpeakOut = false;   // the browser has speech synthesis (TTS fallback for messages with no clip)
    readAloud = true;      // the reporter wants prompts read aloud
    audioCtx;              // one Web Audio context, unlocked on the first user gesture
    clipSrc;               // the clip currently playing, so a new prompt can stop the old one
    clips = {};            // read-aloud clips by question id, loaded ahead so each question speaks at once ('' = none)
    clipsQueued = false;   // the background load has been started
    exJson = null;         // the last AI read of the description, handed back so a tapped answer skips a re-read
    exFor = null;          // the exact description that read was made for

    // Reach the speech engine however the sandbox exposes it.
    getSynth() {
        try { if (typeof window !== 'undefined' && window.speechSynthesis) { return window.speechSynthesis; } } catch (e) { /* ignore */ }
        try { if (typeof globalThis !== 'undefined' && globalThis.speechSynthesis) { return globalThis.speechSynthesis; } } catch (e) { /* ignore */ }
        try { if (typeof speechSynthesis !== 'undefined' && speechSynthesis) { return speechSynthesis; } } catch (e) { /* ignore */ }
        return null;
    }
    getUtter(text) {
        try { if (typeof window !== 'undefined' && window.SpeechSynthesisUtterance) { return new window.SpeechSynthesisUtterance(text); } } catch (e) { /* ignore */ }
        try { if (typeof globalThis !== 'undefined' && globalThis.SpeechSynthesisUtterance) { return new globalThis.SpeechSynthesisUtterance(text); } } catch (e) { /* ignore */ }
        try { if (typeof SpeechSynthesisUtterance !== 'undefined') { return new SpeechSynthesisUtterance(text); } } catch (e) { /* ignore */ }
        return null;
    }

    connectedCallback() {
        this.canSpeak = typeof (window.SpeechRecognition || window.webkitSpeechRecognition) === 'function';
        const synth = this.getSynth();
        this.canSpeakOut = !!synth && !!this.getUtter('x');
    }

    disconnectedCallback() {
        try { const s = this.getSynth(); if (s) { s.cancel(); } } catch (e) { /* ignore */ }
    }

    // ---- compose stage ----
    handleStoryInput(e) { this.story = e.target.value; }

    clearStory() { this.stopListening(); this.story = ''; this.reflect('story'); }

    // LWC does not reliably push a programmatic value change into a rendered <textarea>,
    // so when dictation (or clear) changes the text, set the element's value directly too.
    reflect(which) {
        const ta = this.template.querySelector(which === 'story' ? 'textarea.story' : 'textarea.draftbox');
        if (ta) { ta.value = (which === 'story' ? this.story : this.draft) || ''; }
    }

    submitStory() {
        const s = (this.story || '').trim();
        if (!s || this.busy) { return; }
        this.stopListening();
        this.ensureAudio();   // first gesture unlocks Web Audio for the read-aloud clips
        this.description = s;
        // fresh conversation each time the story is (re)submitted
        this.messages = []; this.answers = []; this.understood = []; this.stillNeeded = []; this.choices = [];
        this.pendingQuestionId = null; this.pendingFeedsDescription = false; this.lotGate = null;
        this.ready = false; this.done = false; this.draftJson = null;
        this.stage = 'chat';
        this.turn();
    }

    editReport() { this.stopListening(); this.story = this.description; this.stage = 'compose'; }

    // ---- chat composer ----
    handleInput(e) { this.draft = e.target.value; }
    handleKey(e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.send(this.draft); } }
    handleSendClick() { this.send(this.draft); }
    handleChoice(e) {
        const v = e.target.dataset.value;
        // "Do you have a lot or batch number?" Yes opens the box to type or speak it, with no extra prompt.
        if (this.lotGate === 'ask' && v === 'Yes') {
            if (this.busy || this.done) { return; }
            this.ensureAudio();
            this.pushMe('Yes');
            this.choices = [];
            this.lotGate = 'open';
            return;
        }
        this.send(v);
    }

    send(text) {
        const said = (text || '').trim();
        if (!said || this.busy || this.done) { return; }
        this.ensureAudio();
        this.pushMe(said);
        this.draft = '';
        this.reflect('draft');
        if (this.pendingQuestionId) {
            // Answering a specific question: record the answer, keep it out of the narrative.
            this.answers = this.answers
                .filter((a) => a.questionId !== this.pendingQuestionId)
                .concat([{ questionId: this.pendingQuestionId, answer: said }]);
            // The lot/part prompt's answer is also description, so the part/lot can resolve —
            // but a "no / don't know" shouldn't get appended to the reporter's narrative.
            if (this.pendingFeedsDescription && !this.isNegative(said)) {
                // After the Yes chip the reply is often just the number, so name it as a lot for the reader.
                const bare = this.lotGate === 'open' && /\d/.test(said) && !/\b(lot|batch|part)\b/i.test(said);
                const extra = bare ? 'Lot ' + said + '.' : said;
                this.description = this.description ? this.description + ' ' + extra : extra;
            }
        } else {
            // A free thought in the chat folds into the report narrative.
            this.description = this.description ? this.description + ' ' + said : said;
        }
        this.turn();
    }

    turn() {
        this.busy = true;
        this.choices = [];
        this.lotGate = null;
        const sentDescription = this.description;
        const payload = { description: sentDescription, answers: this.answers, noAudio: true };
        if (this.exJson && this.exFor === sentDescription) { payload.exJson = this.exJson; payload.exFor = this.exFor; }
        const state = JSON.stringify(payload);
        respond({ stateJson: state })
            .then((t) => {
                if (t.exJson) { this.exJson = t.exJson; this.exFor = sentDescription; }
                this.understood = (t.understood || []).map((f, i) => ({ ...f, k: 'u' + i }));
                this.stillNeeded = (t.stillNeeded || []).map((s, i) => ({ k: 's' + i, text: s }));
                this.choices = (t.choices || []).map((c, i) => ({ k: 'c' + i, value: c }));
                this.pendingQuestionId = t.askQuestionId || null;
                this.pendingFeedsDescription = t.askFeedsDescription === true;
                if (this.pendingFeedsDescription && this.choices.length === 0) {
                    this.choices = [{ k: 'c0', value: 'Yes' }, { k: 'c1', value: 'No' }];
                    this.lotGate = 'ask';
                }
                this.ready = t.ready === true;
                this.draftJson = t.draftJson || null;
                this.pushAi(t.reply);
                if (t.askQuestionId) { this.sayQuestion(t.askQuestionId, t.reply); } else { this.speak(t.reply); }
                this.busy = false;
                this.preloadClips(t.clipQuestionIds);
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

    // ---- voice out (read aloud) ----
    speak(text) {
        if (!this.canSpeakOut || !this.readAloud || !text) { return; }
        try {
            const s = this.getSynth();
            if (!s) { return; }
            s.cancel();
            const u = this.getUtter(text);
            if (!u) { return; }
            u.lang = 'en-US';
            u.rate = 1;
            s.speak(u);
        } catch (e) { /* ignore */ }
    }

    toggleReadAloud() {
        this.readAloud = !this.readAloud;
        if (!this.readAloud) {
            try { const s = this.getSynth(); if (s) { s.cancel(); } } catch (e) { /* ignore */ }
            if (this.clipSrc) { try { this.clipSrc.stop(); } catch (e) { /* ignore */ } }
        }
    }

    handleReplay(e) {
        const id = Number(e.currentTarget.dataset.id);
        const m = this.messages.find((x) => x.id === id);
        if (m && m.isAi) { this.speak(m.text); }
    }

    // Read-aloud playback. The Salesforce mobile WebView blocks the <audio> element and
    // file decoders (MP3/WAV both NotSupportedError), so clips play through the Web Audio API:
    // the stored PCM WAV is parsed here and its samples are written into an AudioBuffer.
    ensureAudio() {
        try {
            if (!this.audioCtx) {
                const Ctx = window.AudioContext || window.webkitAudioContext;
                if (Ctx) { this.audioCtx = new Ctx(); }
            }
            if (this.audioCtx && this.audioCtx.state === 'suspended' && this.audioCtx.resume) { this.audioCtx.resume(); }
        } catch (e) { /* ignore */ }
    }

    // Speak the asked question: from memory when its clip is already loaded, otherwise fetch that one clip now.
    sayQuestion(qid, reply) {
        if (!this.readAloud) { return; }
        const have = this.clips[qid];
        if (have) { this.playClip(have); return; }
        if (have === '') { this.speak(reply); return; }
        fetchClip({ questionId: qid })
            .then((b64) => {
                this.clips[qid] = b64 || '';
                if (this.pendingQuestionId !== qid) { return; }   // the chat has moved on
                if (b64) { this.playClip(b64); } else { this.speak(reply); }
            })
            .catch(() => { /* silent: the question is on screen */ });
    }

    // Load the other questions' clips one at a time in the background, while the reporter reads and answers.
    preloadClips(ids) {
        if (this.clipsQueued || !ids || !ids.length) { return; }
        this.clipsQueued = true;
        const todo = ids.filter((id) => this.clips[id] === undefined);
        const next = () => {
            const id = todo.shift();
            if (!id) { return; }
            if (this.clips[id] !== undefined) { next(); return; }
            fetchClip({ questionId: id })
                .then((b64) => { if (this.clips[id] === undefined) { this.clips[id] = b64 || ''; } next(); })
                .catch(() => { next(); });
        };
        next();
    }

    playClip(b64) {
        if (!this.readAloud || !b64 || !this.audioCtx) { return; }
        try {
            const buf = this.wavToBuffer(this.audioCtx, b64);
            if (!buf) { return; }
            if (this.clipSrc) { try { this.clipSrc.stop(); } catch (e) { /* ignore */ } }
            const src = this.audioCtx.createBufferSource();
            src.buffer = buf;
            src.connect(this.audioCtx.destination);
            src.start();
            this.clipSrc = src;
        } catch (e) { /* ignore */ }
    }

    // Decode a base64 PCM WAV into an AudioBuffer. Scans the RIFF chunks and reads 16-bit samples.
    wavToBuffer(ctx, b64) {
        try {
            const bin = atob(b64);
            const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }
            const dv = new DataView(bytes.buffer);
            if (bytes.length < 44 || dv.getUint32(0, false) !== 0x52494646) { return null; }  // 'RIFF'
            let rate = 8000, channels = 1, bits = 16, dataOff = -1, dataLen = 0;
            let p = 12;
            while (p + 8 <= bytes.length) {
                const id = dv.getUint32(p, false);
                const size = dv.getUint32(p + 4, true);
                const body = p + 8;
                if (id === 0x666d7420) {          // 'fmt '
                    channels = dv.getUint16(body + 2, true) || 1;
                    rate = dv.getUint32(body + 4, true) || 8000;
                    bits = dv.getUint16(body + 14, true) || 16;
                } else if (id === 0x64617461) {   // 'data'
                    dataOff = body; dataLen = size; break;
                }
                p = body + size + (size & 1);
            }
            if (dataOff < 0 || bits !== 16) { return null; }
            const bytesPerSample = 2;
            // Clamp to the bytes actually present so a short/truncated clip still plays.
            const available = Math.max(0, bytes.length - dataOff);
            const usableLen = Math.min(dataLen, available);
            const frames = Math.floor(usableLen / (bytesPerSample * channels));
            if (frames <= 0) { return null; }
            const buf = ctx.createBuffer(channels, frames, rate);
            for (let ch = 0; ch < channels; ch++) {
                const out = buf.getChannelData(ch);
                for (let i = 0; i < frames; i++) {
                    out[i] = dv.getInt16(dataOff + (i * channels + ch) * bytesPerSample, true) / 32768;
                }
            }
            return buf;
        } catch (e) { return null; }
    }

    // ---- voice in (live dictation) ----
    micStory() { this.listen('story'); }
    micChat() { this.listen('draft'); }

    // Dictation REPLACES the target and fills it live as the reporter speaks.
    listen(target) {
        if (!this.canSpeak) { return; }
        if (this.listening) { this.stopListening(); return; }

        const Rec = window.SpeechRecognition || window.webkitSpeechRecognition;
        this.recognition = new Rec();
        this.recognition.lang = 'en-US';
        this.recognition.interimResults = true;
        this.recognition.continuous = true;   // let a longer narrative run; Stop ends it
        this.micTarget = target;
        if (target === 'story') { this.story = ''; } else { this.draft = ''; }

        let finalText = '';
        this.listening = true;
        this.setMic('live', 'Listening… speak now.');

        this.recognition.onresult = (ev) => {
            let interim = '';
            for (let i = ev.resultIndex; i < ev.results.length; i++) {
                const r = ev.results[i];
                if (r.isFinal) { finalText += (finalText ? ' ' : '') + r[0].transcript.trim(); }
                else { interim += r[0].transcript; }
            }
            const text = (finalText + ' ' + interim).trim();
            if (target === 'story') { this.story = text; } else { this.draft = text; }
            this.reflect(target);
            this.setMic('live', interim.trim() ? ('Hearing: “' + interim.trim() + '”') : 'Listening…');
        };
        this.recognition.onerror = (ev) => { this.listening = false; this.setMic('bad', this.micError(ev && ev.error)); };
        this.recognition.onend = () => { this.listening = false; if (this.micTone !== 'bad') { this.setMic('idle', 'Tap Speak to talk.'); } };

        try { this.recognition.start(); }
        catch (e) { this.listening = false; this.setMic('bad', 'Couldn’t start the mic—tap Speak to try again.'); }
    }

    stopListening() {
        this.listening = false;
        if (this.recognition) { try { this.recognition.stop(); } catch (e) { /* ignore */ } }
    }

    micError(code) {
        switch (code) {
            case 'not-allowed':
            case 'service-not-allowed':
                return 'Microphone is blocked. Allow mic access for this site, then tap Speak.';
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

    // A "no / none / don't know" answer to the lot prompt: record it, but keep it out of the narrative.
    isNegative(s) {
        const n = (s || '').toLowerCase().replace(/[^a-z ]+/g, ' ').replace(/\s+/g, ' ').trim();
        if (!n) { return false; }
        const exact = ['no', 'none', 'nope', 'na', 'nan', 'unknown', 'dont know', 'do not know', 'not sure', 'no idea', 'dunno', 'no lot', 'no number', 'dont have one', 'dont have it'];
        if (exact.indexOf(n) !== -1) { return true; }
        return /\b(dont know|not sure|no idea|dont have|dunno|unknown)\b/.test(n);
    }

    // ---- compose getters ----
    get isCompose() { return this.stage === 'compose'; }
    get isChat() { return this.stage === 'chat'; }
    get hasStory() { return (this.story || '').trim().length > 0; }
    get submitDisabled() { return this.busy || !this.hasStory; }
    get bigboxClass() { return (this.listening && this.micTarget === 'story') ? 'bigbox live' : 'bigbox'; }
    get storyMicClass() { return (this.listening && this.micTarget === 'story') ? 'btn speak on' : 'btn speak'; }
    get storyMicLabel() { return (this.listening && this.micTarget === 'story') ? '■ Stop' : '🎙 Speak'; }
    get showStoryMicStatus() { return this.canSpeak && this.listening && this.micTarget === 'story'; }

    // ---- chat getters ----
    get hasChoices() { return this.choices.length > 0 && !this.done; }
    get hasUnderstood() { return this.understood.length > 0; }
    get hasStillNeeded() { return this.stillNeeded.length > 0 && !this.ready; }
    get showQHeader() { return !this.ready && !this.done; }
    get showSubmit() { return this.ready && !this.done; }
    get inputDisabled() { return this.busy || this.done; }
    get showComposer() { return !this.done && this.lotGate !== 'ask'; }
    get inputPlaceholder() {
        if (this.lotGate === 'open') { return 'Type or speak the lot or batch number…'; }
        if (this.pendingQuestionId) { return 'Type your answer…'; }
        if (this.ready) { return 'Remembered something? Add it…'; }
        return 'Type your answer…';
    }
    // Voice only for free-text turns: when a turn offers tap choices, hide the mic.
    get showMic() { return this.canSpeak && !this.hasChoices && !this.done; }
    get showMicStatus() { return this.canSpeak && this.micStatus && !this.done && !this.hasChoices && this.listening && this.micTarget === 'draft'; }
    get micClass() { return (this.listening && this.micTarget === 'draft') ? 'mic listening' : 'mic'; }
    get micLabel() { return (this.listening && this.micTarget === 'draft') ? 'Stop' : 'Speak'; }
    get micStatusClass() { return 'micstatus ' + this.micTone; }
    get readAloudLabel() { return this.readAloud ? '🔊 Read aloud' : '🔇 Muted'; }
    get readAloudClass() { return this.readAloud ? 'sound on' : 'sound'; }
}
