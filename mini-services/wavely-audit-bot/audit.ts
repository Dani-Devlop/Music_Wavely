// Wavely audit engine — evidence-based audit of r-prompt-wavely.md sections S01..S74 / R01..R16
// against the actual code in PROJECT_ROOT. No guessing: a section is only "done" when both
// code evidence AND a dedicated passing test file exist.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, extname, basename } from 'node:path';

export type Status = 'done' | 'partial' | 'not-done' | 'blocked';

export interface SectionResult {
  id: string;
  title: string;
  status: Status;
  codeEvidence: string[];
  testFiles: string[];
  reason: string;
}

export interface CriticalResult {
  label: string;
  pass: boolean;
  evidence: string;
}

export interface AuditResult {
  sections: SectionResult[];
  percent: number;
  counts: { done: number; partial: number; notDone: number; blocked: number };
  critical: CriticalResult[];
  testSummary: string;
  perFileOk: Record<string, boolean>;
}

const ROOT_FILES = ['package.json', 'next.config.ts', 'next.config.js', 'next.config.mjs'];
const SCAN_DIRS = ['src', 'prisma', 'tests', 'scripts'];
const ALLOWED_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.json', '.prisma', '.sh', '.yml', '.yaml']);
const SKIP_DIR_NAMES = new Set(['node_modules', '.next', '.git', 'tool-results', 'upload', 'mini-services']);
const SKIP_FILE_NAMES = new Set(['r-prompt-wavely.md', 'TASKS.md', 'dev.log', 'bun.lock', 'package-lock.json']);
const MAX_FILE_BYTES = 400_000;

// ---------------------------------------------------------------------------
// Evidence rules. Regex lists per section id; a match in scanned code counts
// as implementation evidence for that requirement.
// ---------------------------------------------------------------------------
const R_S01 = [/tgcloud/i, /Wavely_MusicBot/i, /is_?[Mm]ixed/, /ai_?[Dd]j|\/dj\b/];
const R_S02 = [/TGCloud_CLI_TOKEN|TGCLI_TOKEN/, /BOT_TOKEN/, /STRING_SESSION/];
const R_S03 = [/initData/, /PKCE|Authorization Code/i, /argon2|bcrypt/i, /TOTP|two_?[Ff]actor/i, /next-auth|NextAuth/];
const R_S04 = [/PyTgCalls/i, /room_?[Ll]isteners|roomListeners/, /share_?[Tt]oken/, /socket\.io/i, /listening.?party/i];
const R_S05 = [/lrclib/i, /syncedLyrics/, /karaoke/i];
const R_S06 = [/player\/control|playerControl/, /player\/state|playerState/, /queue\/next|queueNext/, /queue\/add|queueAdd/];
const R_S07 = [/getMixedPlaylists|get_?[Mm]ixed/, /is_?[Mm]ixed/, /dj_?play|dj_?stop|aiDj/i];
const R_S08 = [/ai_search_enabled|aiSearchEnabled/, /audio_recognition_enabled|audioRecognition/, /ai_dj_personalization/, /bot_?[Cc]onfig/];
const R_S09 = [/\/start\b/, /\/help\b/, /\/dmca\b/, /\/privacy\b/, /\/admin\b/, /2040835005/];
const R_S10 = [/Türkçe|Turkce/, /Русский/, /العربية/, /users\??\.language|user\??\.language/];
const R_S11 = [/InlineQueryResultAudio|InlineQueryResultPhoto/i, /inline_?[Qq]uery/, /next_?[Oo]ffset/, /cache_?[Tt]ime/];
const R_S12 = [/BotQueue|botQueue/, /retry_?[Aa]fter/, /allSettled/, /concurrency/, /backoff/i];
const R_S13 = [/jamendo/i, /free.?music.?archive|archive\.org/i, /providers\//, /active_music_provider/];
const R_S14 = [/force_?[Jj]oin|forceJoin/];
const R_S15 = [/model\s+users\b/, /model\s+sessions\b/, /model\s+playlists\b/, /is_?[Mm]ixed/, /bot_?[Cc]onfig/];
const R_S16 = [/tgcloud\s+(push|login|migrate)/i, /deploy-tgcloud/];
const R_S17 = [/argon2|bcrypt/i, /HttpOnly/, /TOTP|two_?[Ff]actor/i, /clearCache|clear.?cache/i, /profile/i];
const R_S18 = [/argon2|bcrypt/i, /TOTP|two_?[Ff]actor/i, /email.?verif|verif.?email/i, /lockout/i, /remember.?me/i];
const R_S19 = [/profile/i, /display.?name|displayName/i, /avatar/i, /optimistic.?lock/i];
const R_S20 = [/HttpOnly/, /SameSite/i, /csrf/i, /refresh.?token/i];
const R_S21 = [/clearCache|clear.?cache/i, /CACHE_LIMIT|cache.?limit/i, /autoCache|auto.?cache/i, /invalidate/i];
const R_S22 = [/agent.?policy|policyLayer|policy_?[Ll]ayer/i, /allowlist|allow_?[Ll]ist/i, /system.?prompt/i, /non.?music|music.?only|nonMusic/i];
const R_S23 = [/seed/i, /\bplay\b.*\bpause\b|\bpause\b.*\bseek\b|play\/pause/i];
const R_S24 = [/audit_?[Ll]og|auditLog/, /data.?export|export.?data/i, /delete.?account|account.?delet/i, /grace/i];
const R_S25 = [/Telegram\.WebApp|telegram\.webapp/i, /initData/];
const R_S26 = [/redis/i, /stateless/i, /rate.?limit/i, /\/health\b/, /\/ready\b/];
const R_S28 = [/k6|locust/i, /load.?test/i, /docker-compose/i];
const R_S29 = [/pgbouncer/i, /connection.?pool/i, /stampede/i, /\/ready\b/, /circuit.?breaker/i];
const R_S30 = [/playwright/i, /throttl/i, /slow.?network/i];
const R_S31 = [/\bvus\b/, /30.?(users?|کاربر)/i, /\bsoak\b|\bspike\b/i];
const R_S32 = [/artillery/i, /owasp|\bzap\b/i, /semgrep|codeql|snyk/i, /nightly/i];
const R_S33 = [/bottleneck|گلوگاه/i, /lesson.?learned|درس.?آموخته/i];
const R_S34 = [/acceptance|شروط.?پذیرش/i];
const R_S35 = [/scal|مقیاس/i];
const R_S36 = [/defense.?in.?depth|zero.?trust/i];
const R_S37 = [/threat.?model|credential.?stuffing/i, /prompt.?injection/i];
const R_S38 = [/cost\s*[:=]?\s*(1[2-9]|[2-9]\d)/i, /pepper/i, /HIBP/i, /timingSafe|timing.?equal|constant.?time/i];
const R_S39 = [/recovery.?code/i, /WebAuthn|FIDO2/i];
const R_S40 = [/session.?fixation/i, /\bjti\b/, /RS256|ES256/, /rotat/i];
const R_S41 = [/__Host-|__Secure-/, /maxAge|max.?age/i];
const R_S42 = [/csrf/i];
const R_S43 = [/Content-Security-Policy/i, /nosniff/i, /X-Frame-Options/i, /dangerouslySetInnerHTML/];
const R_S44 = [/SSRF/i, /path.?traversal/i, /NoSQL/i, /parameteriz/i];
const R_S45 = [/IDOR|BOLA/i, /least.?privilege/i, /unguessable/i, /uuid/i];
const R_S46 = [/sliding.?window|token.?bucket/i, /Retry-After/i, /\b429\b/];
const R_S47 = [/enumerat/i, /uniform.*(message|error|response)/i];
const R_S48 = [/\bzod\b/i, /magic.?bytes/i, /Content-Type/i];
const R_S49 = [/ClamAV/i, /magic.?bytes/i, /allowlist|allow_?[Ll]ist/i, /re.?encod/i];
const R_S50 = [/HSTS/i, /\bTLS\b/i, /KMS|secret.?manager/i];
const R_S51 = [/prompt.?injection/i, /output.?filter/i, /token.?quota|token.?limit|daily.?limit/i];
const R_S52 = [/HMAC[- ]?SHA-?256/i, /auth_?[Dd]ate/, /query_?[Ii]d/, /\bhash\b/];
const R_S53 = [/cache.?poisoning/i, /per.?user/i, /\bTTL\b|ttl\b/i];
const R_S54 = [/audit/i, /SIEM/i, /immutable/i];
const R_S55 = [/Permissions-Policy/i, /COOP|CORP|COEP/i, /X-Powered-By/i, /nosniff/i];
const R_S56 = [/mass.?assignment/i, /stack.?trace|stackTrace/i, /api.?version|\/v1\b|\/v2\b/i];
const R_S57 = [/email.?change|change.?email/i, /grace/i, /retention/i];
const R_S58 = [/GDPR|CCPA/i, /PII/i, /data.?minimi/i];
const R_S59 = [/non.?root/i, /Trivy/i, /SBOM/i, /Dependabot|Renovate/i, /seccomp/i];
const R_S60 = [/Semgrep|CodeQL/i, /gitleaks|trufflehog/i, /Snyk/i, /Checkov|tfsec/i];
const R_S61 = [/incident.?response|IR.?plan/i, /breach/i, /post.?mortem|postmortem/i];
const R_S62 = [/checklist/i];
const R_S63 = [/acceptance|پذیرش/i];
const R_S64 = [/defense|لایه/i];
const R_S65 = [/Music_Lyrics_Embedder|Lyrics.?Embedder/i, /profile/i, /clearCache|cache/i, /TOTP|two_?[Ff]actor/i];
const R_S66 = [/register/i, /forgot.?password/i, /lockout/i, /CAPTCHA/i, /disposable/i, /\bterms\b/i];
const R_S67 = [/TOTP/i, /recovery.?code/i, /WebAuthn|FIDO2/i];
const R_S68 = [/allowlist|allow_?[Ll]ist/i, /prompt.?injection/i, /non.?music|music.?only/i];
const R_S69 = [/seed/i, /offline/i, /playback/i];
const R_S70 = [/Music_Lyrics_Embedder|Lyrics.?Embedder/i, /lyric.*cache|cache.*lyric/i, /embed.*lyric|lyric.*embed/i];
const R_S71 = [/optimistic.?lock/i, /invalidate|revalidate/i, /profile/i];
const R_S72 = [/clearCache|clear.?cache/i, /CACHE_LIMIT|cache.?limit/i, /autoCache|auto.?cache/i, /lyric.*cache|cache.*lyric/i];
const R_S73 = [/acceptance|پذیرش/i];
const R_S74 = [/account|اکانت/i];

const RULES: Record<string, RegExp[]> = {
  S01: R_S01, S02: R_S02, S03: R_S03, S04: R_S04, S05: R_S05, S06: R_S06, S07: R_S07, S08: R_S08,
  S09: R_S09, S10: R_S10, S11: R_S11, S12: R_S12, S13: R_S13, S14: R_S14, S15: R_S15, S16: R_S16,
  S17: R_S17, S18: R_S18, S19: R_S19, S20: R_S20, S21: R_S21, S22: R_S22, S23: R_S23, S24: R_S24,
  S25: R_S25, S26: R_S26, S27: [], // special (badge removal)
  S28: R_S28, S29: R_S29, S30: R_S30, S31: R_S31, S32: R_S32, S33: R_S33, S34: R_S34, S35: R_S35,
  S36: R_S36, S37: R_S37, S38: R_S38, S39: R_S39, S40: R_S40, S41: R_S41, S42: R_S42, S43: R_S43,
  S44: R_S44, S45: R_S45, S46: R_S46, S47: R_S47, S48: R_S48, S49: R_S49, S50: R_S50, S51: R_S51,
  S52: R_S52, S53: R_S53, S54: R_S54, S55: R_S55, S56: R_S56, S57: R_S57, S58: R_S58, S59: R_S59,
  S60: R_S60, S61: R_S61, S62: R_S62, S63: R_S63, S64: R_S64,
  S65: R_S65, S66: R_S66, S67: R_S67, S68: R_S68, S69: R_S69, S70: R_S70, S71: R_S71, S72: R_S72,
  S73: R_S73, S74: R_S74,
  R01: R_S01, R02: R_S02, R03: R_S03, R04: R_S04, R05: R_S05, R06: R_S06, R07: R_S07, R08: R_S08,
  R09: R_S09, R10: R_S10, R11: R_S11, R12: R_S12, R13: R_S13, R14: R_S14, R15: R_S15, R16: R_S16,
};

// Sections that map to the same tests as their S## twin (R## twins of S01..S16).
const TWIN: Record<string, string> = {
  R01: 'S01', R02: 'S02', R03: 'S03', R04: 'S04', R05: 'S05', R06: 'S06', R07: 'S07', R08: 'S08',
  R09: 'S09', R10: 'S10', R11: 'S11', R12: 'S12', R13: 'S13', R14: 'S14', R15: 'S15', R16: 'S16',
};

const BLOCKED_REASONS: Record<string, string> = {
  S16: 'نیازمند اکانت/هدف دیپلوی tgcloud مالک (تصمیم کاربر)',
  R16: 'نیازمند اکانت/هدف دیپلوی tgcloud مالک (تصمیم کاربر)',
};

const WEIGHT_GROUPS = [
  { from: 1, to: 16, prefix: 'S', weight: 20 },
  { from: 17, to: 27, prefix: 'S', weight: 20 },
  { from: 28, to: 35, prefix: 'S', weight: 15 },
  { from: 36, to: 64, prefix: 'S', weight: 20 },
  { from: 65, to: 74, prefix: 'S', weight: 15 },
  { from: 1, to: 16, prefix: 'R', weight: 10 },
];

interface RepoFile { path: string; rel: string; lines: string[] }

function collectFiles(root: string): RepoFile[] {
  const out: RepoFile[] = [];
  const pushFile = (abs: string) => {
    const b = basename(abs);
    if (SKIP_FILE_NAMES.has(b)) return;
    if (!ALLOWED_EXT.has(extname(b))) return;
    try {
      const st = statSync(abs);
      if (!st.isFile() || st.size > MAX_FILE_BYTES) return;
      const content = readFileSync(abs, 'utf8');
      out.push({ path: abs, rel: relative(root, abs), lines: content.split('\n') });
    } catch { /* unreadable — skip */ }
  };
  const walk = (dir: string, depth: number) => {
    if (depth > 12) return;
    let entries: string[];
    try { entries = readdirSync(dir); } catch { return; }
    for (const e of entries) {
      if (SKIP_DIR_NAMES.has(e) || e.startsWith('.')) continue;
      const abs = join(dir, e);
      let st; try { st = statSync(abs); } catch { continue; }
      if (st.isDirectory()) walk(abs, depth + 1);
      else pushFile(abs);
    }
  };
  for (const d of SCAN_DIRS) walk(join(root, d), 0);
  for (const f of ROOT_FILES) { const abs = join(root, f); if (existsSync(abs)) pushFile(abs); }
  return out;
}

function parseSections(md: string): Map<string, string> {
  const map = new Map<string, string>();
  const re = /^#{2,3}\s+(.+?)\s*[—–-]\s*شناسه\s+([SR]\d{2})\s*$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(md)) !== null) {
    let title = m[1].trim();
    title = title.replace(/^[^\p{L}]+/u, '').trim(); // strip leading numbering like "۱۵)" or "۱."
    map.set(m[2], title);
  }
  return map;
}

function allExpectedIds(): string[] {
  const ids: string[] = [];
  for (let i = 1; i <= 74; i++) ids.push('S' + String(i).padStart(2, '0'));
  for (let i = 1; i <= 16; i++) ids.push('R' + String(i).padStart(2, '0'));
  return ids;
}

function matchEvidence(files: RepoFile[], id: string): string[] {
  const rules = RULES[id] || [];
  const ev: string[] = [];
  for (const f of files) {
    for (let i = 0; i < f.lines.length; i++) {
      const line = f.lines[i];
      for (const re of rules) {
        if (re.test(line)) {
          const snippet = line.trim().replace(/\s+/g, ' ').slice(0, 70);
          ev.push(`${f.rel}:${i + 1} — ${snippet}`);
          break;
        }
      }
      if (ev.length >= 6) return ev;
    }
  }
  return ev;
}

// S27 special: local/online badges must NOT appear in search UI.
function searchBadgeCheck(files: RepoFile[]): CriticalResult & { hasSearch: boolean } {
  // scan src implementation files only (test assertions mention badges to assert their absence)
  const searchFiles = files.filter((f) => f.rel.startsWith('src/') && /views\/search|search-view/i.test(f.rel));
  let directBadge = false;
  let hideChip = false;
  for (const f of searchFiles) {
    for (let i = 0; i < f.lines.length; i++) {
      const ln = f.lines[i];
      if (/hideOriginChip/.test(ln)) hideChip = true;
      if (/<OriginBadge|origin-badge["']/.test(ln)) directBadge = true;
    }
  }
  const pass = searchFiles.length > 0 && !directBadge;
  const ev = pass
    ? `search rows بدون بج origin${hideChip ? ' (hideOriginChip فعال)' : ''}؛ grep بدون تطابق`
    : 'بج local/online در سرچ یافت شد';
  return { label: 'حذف بج local/online از سرچ (T-S27-1)', pass, evidence: ev, hasSearch: searchFiles.length > 0 };
}

function tokenLeakScan(files: RepoFile[]): CriticalResult {
  const realToken = (process.env.BOT_TOKEN || '').trim();
  const generic = /\b\d{8,12}:AA[\w-]{30,}\b/;
  const hits: string[] = [];
  for (const f of files) {
    for (let i = 0; i < f.lines.length; i++) {
      const ln = f.lines[i];
      const real = realToken.length > 10 && ln.includes(realToken);
      const fakePattern = generic.test(ln) && !/\.test\.ts$/.test(f.rel); // synthetic fixtures in tests are allowed
      if (real || fakePattern) hits.push(`${f.rel}:${i + 1}`);
      if (hits.length >= 5) break;
    }
    if (hits.length >= 5) break;
  }
  // BOT_TOKEN may only be referenced inside server-side code / deploy scripts.
  const badBotToken = files
    .filter((f) => f.lines.some((ln) => /BOT_TOKEN/.test(ln)))
    .filter((f) => !/server\/|scripts\/|\.sh$|tests\//i.test(f.rel))
    .map((f) => f.rel);
  const pass = hits.length === 0 && badBotToken.length === 0;
  const ev = pass
    ? 'اسکن کد و تست‌ها: بدون توکن واقعی؛ الگوهای ساختگی فقط داخل fixtures تست‌ها'
    : `نشتی: ${[...hits, ...badBotToken].slice(0, 4).join(', ')}`;
  return { label: 'عدم افشای توکن ربات به کلاینت (T-S25-2)', pass, evidence: ev };
}

function profileRefreshCheck(files: RepoFile[], perFileOk: Record<string, boolean>): CriticalResult {
  const codeFiles = files.filter((f) => f.rel.includes('profile') || f.rel.includes('sessions'));
  let atomic = false;
  let cacheInv = false;
  for (const f of codeFiles) {
    const body = f.lines.join('\n');
    if (/optimistic.?lock|atomic|SELECT after UPDATE|update.*where.*version/i.test(body)) atomic = true;
    if (/invalidate|revalidate|no-?store|must-?revalidate/i.test(body)) cacheInv = true;
  }
  const testFile = 'tests/profile.test.ts';
  const testRef = files.some((f) => f.rel === testFile && /T-S19-1|T-S71-1/.test(f.lines.join('\n')));
  const testOk = perFileOk[testFile] === true;
  const pass = atomic && cacheInv && testRef && testOk;
  const ev = pass
    ? 'api/profile اتمیک + invalidate کش + tests/profile.test.ts pass'
    : `شواهد: atomic=${atomic} cacheInvalidate=${cacheInv} testRef=${testRef} testPass=${testOk}`;
  return { label: 'رفع باگ پروفایل بعد از رفرش (T-S19-1)', pass, evidence: ev };
}

function cacheSettingsCheck(files: RepoFile[]): CriticalResult {
  const has = (rel: RegExp) => files.find((f) => rel.test(f.rel));
  const settings = has(/settings-view/);
  const explore = has(/explore-view/);
  const apiCache = has(/api\/cache/);
  let settingsCache = false;
  if (settings) settingsCache = /clearCache|CACHE_LIMIT|autoCache|cache/i.test(settings.lines.join('\n'));
  let exploreCache = false;
  if (explore) exploreCache = /clearCache|CACHE_LIMIT|cache.?management|autoCache/i.test(explore.lines.join('\n'));
  const pass = settingsCache && !exploreCache && !!apiCache;
  const ev = pass
    ? 'مدیریت کش فقط در Settings (+ /api/cache)؛ Explore بدون مدیریت کش'
    : `settingsCache=${settingsCache} exploreCache=${exploreCache} apiCache=${!!apiCache}`;
  return { label: 'کش فقط در تنظیمات، نه Explore (T-S21-2)', pass, evidence: ev };
}

function loadTestCheck(files: RepoFile[]): CriticalResult {
  const hit = files.find((f) => /k6|load|perf|docker-compose/i.test(f.rel) || /\bvus\s*[:=]\s*30\b/.test(f.lines.join('\n')));
  const inScripts = files.find((f) => f.rel.startsWith('scripts/') && /\bk6\b|vus/i.test(f.lines.join('\n')));
  const pass = !!hit && !!inScripts;
  const ev = pass ? `اسکریپت بار: ${hit!.rel}` : 'اسکریپت k6/۳۰ کاربر یافت نشد';
  return { label: 'تست ۳۰ کاربر همزمان (T-S31-1)', pass, evidence: ev };
}

export async function runTestFiles(root: string): Promise<{ perFileOk: Record<string, boolean>; summary: string }> {
  const testDir = join(root, 'tests');
  let files: string[] = [];
  try { files = readdirSync(testDir).filter((f) => f.endsWith('.test.ts')); } catch { /* no tests dir */ }
  const perFileOk: Record<string, boolean> = {};
  let pass = 0, fail = 0;
  for (const f of files) {
    try {
      const p = Bun.spawn(['bun', 'test', join('tests', f)], { cwd: root, stdout: 'pipe', stderr: 'pipe', stdin: 'ignore' });
      const timer = setTimeout(() => { try { p.kill(9); } catch { /* already dead */ } }, 60_000);
      const [outS, errS] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()]);
      const code = await p.exited;
      clearTimeout(timer);
      const out = outS + '\n' + errS;
      const mPass = out.match(/(\d+)\s+pass/);
      const mFail = out.match(/(\d+)\s+fail/);
      const ok = code === 0;
      perFileOk['tests/' + f] = ok;
      pass += mPass ? Number(mPass[1]) : ok ? 0 : 0;
      fail += mFail ? Number(mFail[1]) : 0;
    } catch {
      perFileOk['tests/' + f] = false;
    }
  }
  const summary = `pass=${pass} fail=${fail} در ${files.length} فایل تست`;
  return { perFileOk, summary };
}

function groupWeight(id: string): number {
  const prefix = id[0];
  const n = Number(id.slice(1));
  for (const g of WEIGHT_GROUPS) {
    if (g.prefix === prefix && n >= g.from && n <= g.to) return g.weight;
  }
  return 0;
}

function classify(id: string, codeEv: string[], testFiles: string[], perFileOk: Record<string, boolean>): { status: Status; reason: string } {
  const blocked = BLOCKED_REASONS[id];
  const hasCode = codeEv.length > 0;
  const hasTest = testFiles.length > 0;
  if (!hasCode && blocked) return { status: 'blocked', reason: blocked };
  if (!hasCode && !hasTest) return { status: 'not-done', reason: '' };
  if (!hasCode && hasTest) return { status: 'partial', reason: 'فقط تست نوشته شده؛ کد پیاده‌سازی یافت نشد' };
  if (hasCode && !hasTest) return { status: 'partial', reason: 'کد موجود؛ تست اختصاصی T-… نوشته نشده' };
  const allOk = testFiles.every((t) => perFileOk[t] === true);
  if (allOk) return { status: 'done', reason: '' };
  return { status: 'partial', reason: 'کد و تست موجود؛ اجرای تست مربوط fail است' };
}

export async function runAudit(root: string, cachedTests?: { perFileOk: Record<string, boolean>; summary: string }): Promise<AuditResult> {
  const promptPath = existsSync(join(root, 'r-prompt-wavely.md'))
    ? join(root, 'r-prompt-wavely.md')
    : join(root, 'upload', 'r-prompt-wavely.md');
  let md = '';
  try { md = readFileSync(promptPath, 'utf8'); } catch { md = ''; }

  const titles = parseSections(md);
  const files = collectFiles(root);

  const tests = cachedTests ?? (await runTestFiles(root));

  // test-ID references: map section id -> test files that mention its T-IDs
  const testRefs: Record<string, string[]> = {};
  for (const f of files) {
    if (!f.rel.startsWith('tests/') || !f.rel.endsWith('.test.ts')) continue;
    const body = f.lines.join('\n');
    const ids = new Set<string>();
    const re = /T-([SR]\d{2})-\d+/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(body)) !== null) ids.add(m[1]);
    for (const sid of ids) {
      (testRefs[sid] ||= []).push(f.rel);
      const twin = Object.entries(TWIN).find(([, s]) => s === sid);
      if (twin && sid.startsWith('S')) {
        const rid = Object.keys(TWIN).find((k) => TWIN[k] === sid);
        if (rid) (testRefs[rid] ||= []).push(f.rel);
      }
    }
  }
  // R sections also inherit their S twin's tests
  for (const [rid, sid] of Object.entries(TWIN)) {
    if (testRefs[sid]) testRefs[rid] = [...new Set([...(testRefs[rid] || []), ...testRefs[sid]])];
  }

  const badge = searchBadgeCheck(files);
  const sections: SectionResult[] = [];
  for (const id of allExpectedIds()) {
    const title = titles.get(id) || 'بدون عنوان در فایل';
    const codeEv = id === 'S27' ? (badge.pass && badge.hasSearch ? ['search rows: hideOriginChip — بدون بج origin'] : badge.hasSearch ? ['بج origin در سرچ یافت شد'] : []) : matchEvidence(files, id);
    const tFiles = testRefs[id] || [];
    const { status, reason } = classify(id, codeEv, tFiles, tests.perFileOk);
    sections.push({ id, title, status, codeEvidence: codeEv.slice(0, 4), testFiles: tFiles, reason });
  }

  // Critical checks
  const token = tokenLeakScan(files);
  const cacheC = cacheSettingsCheck(files);
  const loadC = loadTestCheck(files);
  const crit = [
    profileRefreshCheck(files, tests.perFileOk),
    badge,
    cacheC,
    token,
    loadC,
  ];

  // Weighted percent
  let earned = 0, total = 0;
  for (const s of sections) {
    const w = groupWeight(s.id);
    total += w;
    if (s.status === 'done') earned += w;
    else if (s.status === 'partial') earned += w * 0.5;
  }
  const percent = total > 0 ? Math.round((earned / total) * 100) : 0;

  const counts = { done: 0, partial: 0, notDone: 0, blocked: 0 };
  for (const s of sections) {
    if (s.status === 'done') counts.done++;
    else if (s.status === 'partial') counts.partial++;
    else if (s.status === 'blocked') counts.blocked++;
    else counts.notDone++;
  }

  return { sections, percent, counts, critical: crit, testSummary: tests.summary, perFileOk: tests.perFileOk };
}
