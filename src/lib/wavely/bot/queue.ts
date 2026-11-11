/**
 * S12 / R12 — BotQueue: batched outbound sends (concurrency 25, 1000ms
 * spacing), exponential backoff on 429 up to 60s, Telegram rate limits
 * (30/s global, 1/s private, 20/min group), Promise.allSettled helpers.
 */
export interface QueueJob {
  id: string;
  run: () => Promise<{ ok: boolean; retryAfter?: number }>;
}

export interface QueueResult {
  id: string;
  ok: boolean;
  attempts: number;
  error?: string;
}

export const QUEUE_CONCURRENCY = 25;
export const QUEUE_DELAY_MS = 1000;
export const MAX_BACKOFF_SEC = 60;

/** Telegram limits (S12-1). */
export const TG_LIMITS = { globalPerSec: 30, privatePerSec: 1, groupPerMin: 20 } as const;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class BotQueue {
  private queue: QueueJob[] = [];
  private processing = false;
  /** every handler must run through allSettled (T-S12-4) */
  static async runAll<T>(tasks: (() => Promise<T>)[]): Promise<PromiseSettledResult<T>[]> {
    return Promise.allSettled(tasks.map((t) => t()));
  }

  enqueue(job: QueueJob): void {
    this.queue.push(job);
  }

  get size(): number {
    return this.queue.length;
  }

  /** Drain the queue in batches of 25 with 1s between sends (T-S12-1). */
  async drain(batchSize = QUEUE_CONCURRENCY, delayMs = QUEUE_DELAY_MS): Promise<QueueResult[]> {
    const results: QueueResult[] = [];
    this.processing = true;
    try {
      while (this.queue.length > 0) {
        const batch = this.queue.splice(0, batchSize);
        const settled = await Promise.allSettled(batch.map((job) => this.execute(job)));
        settled.forEach((outcome, i) => {
          if (outcome.status === "fulfilled") {
            results.push(outcome.value);
          } else {
            results.push({ id: batch[i].id, ok: false, attempts: 1, error: String(outcome.reason) });
          }
        });
        if (this.queue.length > 0) await sleep(delayMs);
      }
    } finally {
      this.processing = false;
    }
    return results;
  }

  /** Execute one job with 429-aware exponential backoff capped at 60s (T-S12-2). */
  async execute(job: QueueJob, maxAttempts = 5): Promise<QueueResult> {
    let attempt = 0;
    let backoffMs = 1000;
    for (;;) {
      attempt++;
      let res: { ok: boolean; retryAfter?: number };
      try {
        res = await job.run();
      } catch (e) {
        res = { ok: false, retryAfter: undefined };
        if (attempt >= maxAttempts) return { id: job.id, ok: false, attempts: attempt, error: String(e) };
      }
      if (res.ok) return { id: job.id, ok: true, attempts: attempt };
      const retryAfter = typeof res.retryAfter === "number" && res.retryAfter > 0 ? res.retryAfter : Math.floor(backoffMs / 1000);
      if (retryAfter >= MAX_BACKOFF_SEC) {
        // capped: wait at most 60s then give up after remaining attempts
        if (attempt >= maxAttempts) return { id: job.id, ok: false, attempts: attempt, error: "backoff-cap" };
        await sleep(MAX_BACKOFF_SEC * 1000);
        continue;
      }
      await sleep(retryAfter * 1000);
      backoffMs = Math.min(backoffMs * 2, MAX_BACKOFF_SEC * 1000);
      if (attempt >= maxAttempts) return { id: job.id, ok: false, attempts: attempt, error: "max-attempts" };
    }
  }
}

/** Group-chat rate limiter: 20/min (T-S12-3 / T-R12-3). */
export class GroupRateGuard {
  private hits = new Map<string, number[]>();
  allow(chatId: string, now = Date.now()): boolean {
    const window = 60_000;
    const hits = (this.hits.get(chatId) ?? []).filter((t) => now - t < window);
    if (hits.length >= TG_LIMITS.groupPerMin) {
      this.hits.set(chatId, hits);
      return false;
    }
    hits.push(now);
    this.hits.set(chatId, hits);
    return true;
  }
}

/** Private-chat limiter: 1/s. */
export class PrivateRateGuard {
  private last = new Map<string, number>();
  allow(chatId: string, now = Date.now()): boolean {
    const prev = this.last.get(chatId) ?? 0;
    if (now - prev < 1000) return false;
    this.last.set(chatId, now);
    return true;
  }
}
