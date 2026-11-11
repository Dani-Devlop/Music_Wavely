/**
 * S46 / S29-6 — three-layer rate limiting (IP / user / endpoint) with a
 * sliding window, 429 + Retry-After and adaptive-CAPTCHA signalling.
 * Store is the server-side cache table keyed per subject; in production this
 * maps onto Redis token buckets (same API).
 */

interface Bucket {
  hits: number[];
  captchaAfter: number; // hit count that starts triggering adaptive CAPTCHA
}

const buckets = new Map<string, Bucket>();

export interface RateVerdict {
  allowed: boolean;
  remaining: number;
  retryAfter: number; // seconds
  captcha: boolean;
}

/**
 * Sliding-window limiter. S46-2 defaults are strict for sensitive endpoints
 * (login/register/forgot/2FA/email-change).
 */
export function rateLimit(
  subject: string, // e.g. "ip:1.2.3.4" | "user:u123" | "endpoint:POST /api/auth/login:ip:1.2.3.4"
  limit: number,
  windowSec: number,
  captchaThreshold = Math.ceil(limit * 0.8),
): RateVerdict {
  const now = Date.now();
  const windowMs = windowSec * 1000;
  const b = buckets.get(subject) ?? { hits: [], captchaAfter: captchaThreshold };
  b.hits = b.hits.filter((t) => now - t < windowMs);
  if (b.hits.length >= limit) {
    const oldest = b.hits[0];
    const retryAfter = Math.max(1, Math.ceil((oldest + windowMs - now) / 1000));
    buckets.set(subject, b);
    return { allowed: false, remaining: 0, retryAfter, captcha: b.hits.length >= b.captchaAfter };
  }
  b.hits.push(now);
  buckets.set(subject, b);
  return {
    allowed: true,
    remaining: limit - b.hits.length,
    retryAfter: 0,
    captcha: b.hits.length > b.captchaAfter,
  };
}

/** S46-3/S46-4: preset tiers — values follow the S29-6/S46 section semantics. */
export const RATE_TIERS = {
  sensitive: { limit: 5, windowSec: 300 }, // login/register/forgot/2FA/email change: 5 per 5min
  search: { limit: 60, windowSec: 60 },
  stream: { limit: 120, windowSec: 60 },
  ai: { limit: 20, windowSec: 300 },
  general: { limit: 240, windowSec: 60 },
} as const;

export function checkRate(
  kind: keyof typeof RATE_TIERS,
  ip: string,
  userId: string | null,
  endpoint: string,
): RateVerdict {
  const tier = RATE_TIERS[kind];
  // Layer 1 — IP
  const byIp = rateLimit(`ip:${ip}`, tier.limit, tier.windowSec);
  if (!byIp.allowed) return byIp;
  // Layer 2 — user (when authenticated)
  if (userId) {
    const byUser = rateLimit(`user:${userId}:${kind}`, tier.limit, tier.windowSec);
    if (!byUser.allowed) return byUser;
  }
  // Layer 3 — endpoint-specific
  const byEndpoint = rateLimit(`ep:${endpoint}:${ip}`, tier.limit, tier.windowSec);
  return byEndpoint;
}

export function resetRateLimits() {
  buckets.clear();
}
