// node scripts/tests/cqWsDraft.test.mjs  (no packages needed)
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const src = readFileSync(new URL('../../force-app/main/default/lwc/cqWsDraft/cqWsDraft.js', import.meta.url), 'utf8');
const dir = mkdtempSync(join(tmpdir(), 'cqws-'));
writeFileSync(join(dir, 'd.mjs'), src);
const { readDraft, writeDraft, upTo } = await import(join(dir, 'd.mjs'));

const KEEP = ['hazard', 'level', 'checks'];
const OPTS = { version: 3, keep: KEEP, maps: { 1: [0, 1, 1, 1, 2, 3], 2: [0, 1, 1, 2, 3] } };
let n = 0; const t = (name, fn) => { fn(); n++; console.log('ok', name); };

t('no draft', () => assert.equal(readDraft(null, OPTS), null));
t('bad json', () => assert.equal(readDraft('{x', OPTS), null));
t('future version ignored', () => assert.equal(readDraft(JSON.stringify({ v: 4, step: 1 }), OPTS), null));
t('round trip v3', () => {
    const json = writeDraft({ step: 2, maxStep: 2, seen: { 0: true, 1: true, 2: true }, hazard: 'h', level: 'High', checks: { a: 'Yes' } }, OPTS);
    const r = readDraft(json, OPTS);
    assert.equal(r.step, 2); assert.equal(r.maxStep, 2);
    assert.deepEqual(r.values, { hazard: 'h', level: 'High', checks: { a: 'Yes' } });
});
t('v2 on Signals moves to Assessment', () => {
    const r = readDraft(JSON.stringify({ v: 2, step: 1, maxStep: 1, seen: { 0: true, 1: true } }), OPTS);
    assert.equal(r.step, 1); assert.deepEqual(r.seen, { 0: true, 1: true });
});
t('v2 on Committee moves to 3', () => {
    const r = readDraft(JSON.stringify({ v: 2, step: 4, maxStep: 4, seen: { 0: true, 1: true, 2: true, 3: true, 4: true } }), OPTS);
    assert.equal(r.step, 3); assert.equal(r.maxStep, 3); assert.deepEqual(r.seen, { 0: true, 1: true, 2: true, 3: true });
});
t('v1 without seen: all up to max', () => {
    const r = readDraft(JSON.stringify({ v: 1, step: 4, maxStep: 4 }), OPTS);
    assert.equal(r.step, 2); assert.deepEqual(r.seen, upTo(2));
});
t('current step always seen', () => {
    const r = readDraft(JSON.stringify({ v: 3, step: 2, maxStep: 2, seen: { 0: true } }), OPTS);
    assert.equal(r.seen[2], true);
});
console.log(n, 'passed');
