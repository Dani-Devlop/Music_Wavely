// Persistent runtime state (no secrets here — token lives only in .env).
import { readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export interface BotState {
  lastHash: string;
  paused: boolean;
  updatesOffset: number;
  lastSentAt: number;
  testRunAt: number;
  perFileOk: Record<string, boolean>;
  testSummary: string;
}

const DEFAULT: BotState = {
  lastHash: '',
  paused: false,
  updatesOffset: 0,
  lastSentAt: 0,
  testRunAt: 0,
  perFileOk: {},
  testSummary: '',
};

const STATE_PATH = join(import.meta.dir, 'state.json');

export function loadState(): BotState {
  try {
    if (existsSync(STATE_PATH)) {
      const raw = JSON.parse(readFileSync(STATE_PATH, 'utf8')) as Partial<BotState>;
      return { ...DEFAULT, ...raw };
    }
  } catch { /* corrupt state — reset */ }
  return { ...DEFAULT };
}

export function saveState(s: BotState): void {
  try {
    const tmp = STATE_PATH + '.tmp';
    writeFileSync(tmp, JSON.stringify(s));
    renameSync(tmp, STATE_PATH);
  } catch { /* best effort */ }
}
