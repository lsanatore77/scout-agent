/**
 * cqWsDraft: saving and resuming a workspace's work in progress, the same way on every workspace.
 *
 * A draft is JSON on the record: { v: <version>, step, maxStep, seen, ...the workspace's own keys }.
 * When a workspace changes its steps, it bumps its version and gives a map per older version
 * (old step number -> new step number); drafts saved before are moved onto the new steps.
 */

/** Steps 0..n all marked as seen. */
export function upTo(n) {
    const m = {};
    for (let i = 0; i <= n; i++) { m[i] = true; }
    return m;
}

/**
 * Reads a saved draft.
 * @param {string} json      the draft as stored on the record
 * @param {object} opts      { version, keep: [keys], maps: { <older version>: [old step -> new step] } }
 * @returns {object|null}    { values, step, maxStep, seen } or null when there is no usable draft
 */
export function readDraft(json, opts) {
    let d;
    try { d = json ? JSON.parse(json) : null; } catch (e) { d = null; }
    if (!d || typeof d.v !== 'number' || d.v < 1 || d.v > opts.version) { return null; }
    const values = {};
    (opts.keep || []).forEach((k) => { if (d[k] !== undefined) { values[k] = d[k]; } });
    let step = Number(d.step) || 0;
    let maxStep = Number(d.maxStep) || 0;
    let seen = d.seen || null;
    const map = d.v < opts.version ? (opts.maps || {})[d.v] : null;
    if (map) {
        step = map[step] || 0;
        maxStep = map[maxStep] || 0;
        if (seen) {
            const moved = {};
            Object.keys(seen).forEach((k) => { if (seen[k]) { moved[map[Number(k)] || 0] = true; } });
            seen = moved;
        }
    }
    // a draft saved before steps could be opened in any order: every step up to the furthest one was seen
    if (!seen) { seen = upTo(maxStep); }
    seen = { ...seen, [step]: true };
    return { values, step, maxStep, seen };
}

/** The draft to store: the version, where the reviewer is, and the workspace's own keys. */
export function writeDraft(state, opts) {
    const d = { v: opts.version, step: state.step, maxStep: state.maxStep, seen: state.seen };
    (opts.keep || []).forEach((k) => { d[k] = state[k]; });
    return JSON.stringify(d);
}
