// Builds the Persian Telegram report from an AuditResult, exactly per owner's format.
import type { AuditResult, SectionResult } from './audit';

const CRIT_LABELS: Record<string, string> = {
  'رفع باگ پروفایل بعد از رفرش (T-S19-1)': 'رفع باگ پروفایل',
  'حذف بج local/online از سرچ (T-S27-1)': 'حذف بج local/online',
  'کش فقط در تنظیمات، نه Explore (T-S21-2)': 'کش فقط در تنظیمات',
  'عدم افشای توکن ربات به کلاینت (T-S25-2)': 'عدم افشای توکن',
  'تست ۳۰ کاربر همزمان (T-S31-1)': 'تست ۳۰ کاربر',
};

function progressBar(percent: number): string {
  const cells = 20;
  const filled = Math.max(0, Math.min(cells, Math.round((percent / 100) * cells)));
  return '█'.repeat(filled) + '░'.repeat(cells - filled) + ' ' + percent + '%';
}

function tehranNow(): string {
  const d = new Date();
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tehran',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
  });
  const parts = fmt.formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')} ${get('hour')}:${get('minute')} (Tehran)`;
}

function shortTitle(s: SectionResult): string {
  return `${s.id} — ${s.title}`;
}

export function buildReport(a: AuditResult): { full: string; parts: string[] } {
  const lines: string[] = [];
  lines.push('📊 گزارش پیشرفت Wavely');
  lines.push('🕒 ' + tehranNow());
  lines.push('');
  lines.push(progressBar(a.percent));
  lines.push('');

  const done = a.sections.filter((s) => s.status === 'done');
  const notDone = a.sections.filter((s) => s.status === 'not-done');
  const partial = a.sections.filter((s) => s.status === 'partial');
  const blocked = a.sections.filter((s) => s.status === 'blocked');

  lines.push('✅ کارهای انجام شده:');
  if (done.length === 0) lines.push('• —');
  for (const s of done) lines.push('• ' + shortTitle(s));
  lines.push('');

  lines.push('⏳ کارهای انجام نشده:');
  if (notDone.length === 0) lines.push('• —');
  for (const s of notDone) lines.push('• ' + shortTitle(s));
  lines.push('');

  lines.push('🟡 نیمه‌کاره:');
  if (partial.length === 0) lines.push('• —');
  for (const s of partial) lines.push(`• ${shortTitle(s)} — مانده: ${s.reason || 'تست اختصاصی'}`);
  lines.push('');

  lines.push('🚧 بلاک‌شده:');
  if (blocked.length === 0) lines.push('• —');
  for (const s of blocked) lines.push(`• ${shortTitle(s)} — ${s.reason}`);
  lines.push('');

  lines.push('🔐 الزامات حیاتی:');
  for (const c of a.critical) {
    const label = CRIT_LABELS[c.label] || c.label;
    lines.push(`${c.pass ? '✅' : '⛔'} ${label} — ${c.evidence}`);
  }
  lines.push('');
  lines.push(`🧪 تست‌ها: ${a.testSummary}`);

  const full = lines.join('\n');

  // split into <=3400-char chunks on line boundaries for Telegram's 4096 limit
  const parts: string[] = [];
  let cur: string[] = [];
  let curLen = 0;
  for (const ln of lines) {
    if (curLen + ln.length + 1 > 3400 && cur.length > 0) {
      parts.push(cur.join('\n'));
      cur = [];
      curLen = 0;
    }
    cur.push(ln);
    curLen += ln.length + 1;
  }
  if (cur.length > 0) parts.push(cur.join('\n'));
  const withHeaders = parts.map((p, i) => (i === 0 ? p : `… (ادامه ${i + 1}/${parts.length})\n${p}`));
  return { full, parts: withHeaders };
}
