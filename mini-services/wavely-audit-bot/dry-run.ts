// Dry-run: build the audit locally and print a one-line summary + criticals (no Telegram send).
import { runAudit } from './audit';
import { buildReport } from './report';

const root = process.env.PROJECT_ROOT || '/home/z/my-project';
const audit = await runAudit(root);
const { parts } = buildReport(audit);
console.log(`percent=${audit.percent}% done=${audit.counts.done} partial=${audit.counts.partial} notDone=${audit.counts.notDone} blocked=${audit.counts.blocked} parts=${parts.length}`);
console.log('tests:', audit.testSummary);
for (const c of audit.critical) console.log(`${c.pass ? 'PASS' : 'FAIL'} ${c.label} | ${c.evidence}`);
const byId = (id: string) => audit.sections.find((s) => s.id === id);
for (const id of ['S01', 'S05', 'S15', 'S19', 'S21', 'S22', 'S27', 'S31', 'S38', 'S43', 'S52', 'S68', 'S70', 'S71', 'R01', 'R16']) {
  const s = byId(id);
  if (s) console.log(`${id}: ${s.status} | ev=${s.codeEvidence.length} tests=${s.testFiles.join(',') || '-'} | ${s.title.slice(0, 40)}`);
}
