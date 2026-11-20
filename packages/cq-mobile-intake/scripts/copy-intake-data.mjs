#!/usr/bin/env node
/**
 * Copies the mobile intake setup data from one org to another, using your existing sf CLI logins:
 *   - Event Questions (with Case Field, roles, urgent answers, help text)
 *   - each question's read-aloud .wav clip (a file on the question)
 *   - Quick Log Categories (Approved By is left blank: users differ between orgs)
 *
 *   node scripts/copy-intake-data.mjs --from dev --to intake-test
 *
 * Safe to run again: a question or category that already exists in the target (same text / name) is left alone,
 * and a clip is added only to a question that has none. Needs Node 18 or later.
 */
import { execFileSync } from 'node:child_process';

const API = 'v66.0';
const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
const from = arg('--from'), to = arg('--to');
if (!from || !to) { console.error('Usage: node scripts/copy-intake-data.mjs --from <source org alias> --to <target org alias>'); process.exit(1); }

function login(alias) {
  const out = execFileSync('sf', ['org', 'display', '--target-org', alias, '--json'], { encoding: 'utf8', shell: process.platform === 'win32' });
  const r = JSON.parse(out).result;
  return { url: r.instanceUrl, token: r.accessToken, alias };
}
async function call(org, method, path, body) {
  const res = await fetch(org.url + path, { method, headers: { Authorization: 'Bearer ' + org.token, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined });
  if (!res.ok) { throw new Error(`${org.alias} ${method} ${path}: ${res.status} ${await res.text()}`); }
  return res.status === 204 ? null : res.json();
}
async function query(org, soql) {
  let r = await call(org, 'GET', `/services/data/${API}/query?q=` + encodeURIComponent(soql)), rows = r.records;
  while (!r.done) { r = await call(org, 'GET', r.nextRecordsUrl); rows = rows.concat(r.records); }
  return rows;
}
async function insert(org, type, rows) {
  const ids = [];
  for (let i = 0; i < rows.length; i += 200) {
    const res = await call(org, 'POST', `/services/data/${API}/composite/sobjects`,
      { allOrNone: true, records: rows.slice(i, i + 200).map((r) => ({ attributes: { type }, ...r })) });
    res.forEach((x) => { if (!x.success) { throw new Error(JSON.stringify(x.errors)); } ids.push(x.id); });
  }
  return ids;
}
const clean = (r, fields) => Object.fromEntries(fields.filter((f) => r[f] !== undefined && r[f] !== null).map((f) => [f, r[f]]));

const Q_FIELDS = ['Order__c', 'Question__c', 'Answer_Type__c', 'Choices__c', 'Role__c', 'Urgent_When__c', 'Help_Text__c', 'Required__c',
  'Active__c', 'Case_Field__c', 'Audio_Source_Text__c', 'Audio_Wav_Base64__c'];
const C_FIELDS = ['Name', 'Description__c', 'Disposition__c', 'Limit__c', 'Days__c', 'Scope__c', 'Active__c', 'Approved_On__c'];

const src = login(from), dst = login(to);
console.log(`Copying intake setup from ${src.url} to ${dst.url}`);

// Questions
const sq = await query(src, `SELECT Id, ${Q_FIELDS.join(', ')} FROM Event_Question__c ORDER BY Order__c`);
const tq = await query(dst, `SELECT Id, Question__c FROM Event_Question__c`);
const have = new Map(tq.map((r) => [r.Question__c, r.Id]));
const toAdd = sq.filter((r) => !have.has(r.Question__c));
const newIds = await insert(dst, 'Event_Question__c', toAdd.map((r) => clean(r, Q_FIELDS)));
toAdd.forEach((r, i) => have.set(r.Question__c, newIds[i]));
console.log(`Questions: ${toAdd.length} added, ${sq.length - toAdd.length} already there`);

// Clips: the newest .wav on each source question, added where the target question has no file
let clips = 0;
for (const q of sq) {
  const target = have.get(q.Question__c);
  const already = await query(dst, `SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = '${target}'`);
  if (already.length) { continue; }
  const links = await query(src, `SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = '${q.Id}'`);
  if (!links.length) { continue; }
  const ids = links.map((l) => `'${l.ContentDocumentId}'`).join(',');
  const v = await query(src, `SELECT Id, Title, PathOnClient FROM ContentVersion WHERE ContentDocumentId IN (${ids}) AND IsLatest = true AND FileExtension = 'wav' ORDER BY CreatedDate DESC LIMIT 1`);
  if (!v.length) { continue; }
  const bin = await fetch(src.url + `/services/data/${API}/sobjects/ContentVersion/${v[0].Id}/VersionData`, { headers: { Authorization: 'Bearer ' + src.token } });
  if (!bin.ok) { throw new Error(`clip ${v[0].Title}: ${bin.status}`); }
  const data = Buffer.from(await bin.arrayBuffer()).toString('base64');
  await call(dst, 'POST', `/services/data/${API}/sobjects/ContentVersion`,
    { Title: v[0].Title, PathOnClient: v[0].PathOnClient || v[0].Title + '.wav', VersionData: data, FirstPublishLocationId: target });
  clips++;
}
console.log(`Clips: ${clips} added`);

// Quick Log Categories
const sc = await query(src, `SELECT ${C_FIELDS.join(', ')} FROM Quick_Log_Category__c`);
const tc = new Set((await query(dst, `SELECT Name FROM Quick_Log_Category__c`)).map((r) => r.Name));
const cAdd = sc.filter((r) => !tc.has(r.Name));
await insert(dst, 'Quick_Log_Category__c', cAdd.map((r) => clean(r, C_FIELDS)));
console.log(`Quick Log Categories: ${cAdd.length} added, ${sc.length - cAdd.length} already there`);
console.log('Done.');
