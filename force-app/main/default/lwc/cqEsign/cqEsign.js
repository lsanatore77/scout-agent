import getPolicies from '@salesforce/apex/CqEsign.getPolicies';

/**
 * What CQ's electronic signature policy asks for each action on a record (the standard: docs/esignature.md).
 * CQ takes several seconds to answer (it runs its signature flows for each action), so a full answer is kept in this
 * browser tab for 8 hours under the key (usually the object's API name), and a question already being asked is shared.
 * The kept answer only shapes the screen: every signature is checked against CQ's policy again on the server.
 */
const KEEP = 8 * 3600000;
const asking = new Map();

export function askPolicies(recordId, actions, key, fresh) {
    const k = 'cqSign:' + (key || recordId) + ':' + actions.join(',');
    if (!fresh) {
        try {
            const kept = JSON.parse(window.sessionStorage.getItem(k) || 'null');
            if (kept && Date.now() - kept.at < KEEP) { return Promise.resolve(kept.signs); }
        } catch (e) { /* no storage: ask CQ */ }
        if (asking.has(k)) { return asking.get(k); }
    }
    const unknown = () => actions.reduce((o, a) => ({ ...o, [a]: { unknown: true } }), {});
    const p = getPolicies({ recordId, actions }).then((g) => {
        const signs = g || {};
        if (actions.every((a) => signs[a] && !signs[a].unknown)) {
            try { window.sessionStorage.setItem(k, JSON.stringify({ at: Date.now(), signs })); } catch (e) { /* not kept */ }
        }
        return signs;
    }).catch(unknown).finally(() => { asking.delete(k); });
    asking.set(k, p);
    return p;
}

/** Whether any of the actions needs a signature, or could not be checked. */
export function anyRequired(signs) { return Object.values(signs || {}).some((g) => g && g.required); }
export function anyUnknown(signs) { return Object.values(signs || {}).some((g) => g && g.unknown); }
