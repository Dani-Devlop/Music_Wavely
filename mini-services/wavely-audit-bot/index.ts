// Wavely audit reporter bot — polls commands, sends weighted audit report every 10 min.
// Secrets live ONLY in .env. Report goes only to OWNER_ID via Telegram; chat here stays one-line.
import { createHash } from 'node:crypto';
import { runAudit, runTestFiles, type AuditResult } from './audit';
import { buildReport } from './report';
import { loadState, saveState, type BotState } from './state';
import { api, sendMessage, sendMessageChunks, OWNER_ID } from './telegram';

const PROJECT_ROOT = process.env.PROJECT_ROOT || '/home/z/my-project';
const INTERVAL_MIN = Number(process.env.REPORT_INTERVAL_MIN || 10);
const TEST_CACHE_TTL_MS = 6 * 60 * 60 * 1000; // re-run test suite every 6h

const state: BotState = loadState();
let ticking = false;

function log(scope: string, msg: string): void {
  console.log(`[${new Date().toISOString()}] [${scope}] ${msg}`);
}

function oneLine(a: AuditResult): string {
  const remain = a.counts.notDone;
  return `percent=${a.percent}% | done=${a.counts.done} | remain=${remain} | blocked=${a.counts.blocked}`;
}

async function getTests(state: BotState): Promise<{ perFileOk: Record<string, boolean>; summary: string }> {
  if (state.testRunAt && Date.now() - state.testRunAt < TEST_CACHE_TTL_MS && state.perFileOk) {
    return { perFileOk: state.perFileOk, summary: state.testSummary };
  }
  const fresh = await runTestFiles(PROJECT_ROOT);
  state.testRunAt = Date.now();
  state.perFileOk = fresh.perFileOk;
  state.testSummary = fresh.summary;
  saveState(state);
  return fresh;
}

async function tick(force: boolean): Promise<void> {
  if (ticking) return;
  ticking = true;
  try {
    const tests = await getTests(state);
    const audit = await runAudit(PROJECT_ROOT, tests);
    const { full, parts } = buildReport(audit);
    // dedupe must ignore the timestamp line, otherwise every tick looks "changed"
    const contentForHash = full.split('\n').filter((ln) => !ln.startsWith('🕒')).join('\n');
    const hash = createHash('sha256').update(contentForHash).digest('hex');
    log('tick', `${oneLine(audit)} | partial=${audit.counts.partial} hash=${hash.slice(0, 8)} paused=${state.paused} force=${force}`);

    const shouldSend = force || (!state.paused && hash !== state.lastHash);
    if (!shouldSend) return;

    const ok = await sendMessageChunks(OWNER_ID, parts);
    if (ok) {
      state.lastHash = hash;
      state.lastSentAt = Date.now();
      saveState(state);
      log('send', `report sent (${parts.length} part/s)`);
    } else {
      log('send', 'send failed — will retry next tick');
    }
  } catch (e) {
    log('tick', `error: ${e instanceof Error ? e.message : String(e)}`);
  } finally {
    ticking = false;
  }
}

interface TgMessage { chat?: { id?: number }; text?: string }

async function handleMessage(msg: TgMessage): Promise<void> {
  const chatId = msg.chat?.id;
  if (!chatId || chatId !== OWNER_ID) return; // owner-only
  const raw = (msg.text || '').trim();
  const cmd = raw.split(/\s+/)[0].split('@')[0].toLowerCase();
  switch (cmd) {
    case '/start':
      state.paused = false;
      saveState(state);
      await sendMessage(chatId, '✅ گزارش‌ده ممیزی Wavely فعال شد. گزارش اولیه در راه است…');
      await tick(true);
      break;
    case '/status':
      await tick(true);
      break;
    case '/pause':
      state.paused = true;
      saveState(state);
      await sendMessage(chatId, '⏸ ارسال خودکار متوقف شد. برای ادامه /resume بزنید.');
      break;
    case '/resume':
      state.paused = false;
      saveState(state);
      await sendMessage(chatId, '▶️ ارسال خودکار ادامه یافت (هر ' + INTERVAL_MIN + ' دقیقه، فقط در صورت تغییر گزارش).');
      break;
    default:
      if (cmd.startsWith('/')) await sendMessage(chatId, 'دستور ناشناخته. دستورها: /start /status /pause /resume');
      break;
  }
}

async function pollLoop(): Promise<void> {
  let offset = state.updatesOffset || 0;
  for (;;) {
    try {
      const r = await api<{ update_id: number; message?: TgMessage }[]>('getUpdates', {
        timeout: 25,
        offset,
        allowed_updates: ['message'],
      });
      if (r.ok && r.result) {
        for (const u of r.result) {
          offset = u.update_id + 1;
          state.updatesOffset = offset;
          saveState(state);
          if (u.message) await handleMessage(u.message).catch((e) => log('msg', String(e)));
        }
      } else {
        await new Promise((res) => setTimeout(res, 3000));
      }
    } catch (e) {
      log('poll', `error: ${e instanceof Error ? e.message : String(e)}`);
      await new Promise((res) => setTimeout(res, 5000));
    }
  }
}

async function boot(): Promise<void> {
  if (!OWNER_ID) {
    log('boot', 'OWNER_ID missing in .env — refusing to start');
    process.exit(1);
  }
  log('boot', `audit reporter starting (interval=${INTERVAL_MIN}min, owner set)`);
  await api('deleteWebhook', { drop_pending_updates: false });
  await api('setMyCommands', {
    commands: [
      { command: 'start', description: 'فعال‌سازی و گزارش اولیه' },
      { command: 'status', description: 'گزارش فوری' },
      { command: 'pause', description: 'توقف ارسال خودکار' },
      { command: 'resume', description: 'ادامه ارسال خودکار' },
    ],
  });
  // first audit right after boot — dedupe applies (only send when content changed);
  // explicit /start or /status still force-send.
  setTimeout(() => { void tick(false); }, 3000);
  setInterval(() => { void tick(false); }, INTERVAL_MIN * 60_000);
  void pollLoop();
}

void boot();
