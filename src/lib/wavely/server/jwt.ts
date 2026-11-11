/**
 * S40 — JWT (RS256, never HS256): short-lived access tokens with jti/iss/aud/
 * exp/nbf, no sensitive payload, rotatable server-held key (S50-7).
 * Key material is generated server-side and held in bot_config (secret store)
 * — never shipped to any client.
 */
import { createSign, createVerify, generateKeyPairSync, createPublicKey } from "crypto";
import { db } from "@/lib/db";

export const JWT_ISSUER = "wavely";
export const JWT_AUDIENCE = "wavely-miniapp";
export const ACCESS_TOKEN_TTL_SEC = 15 * 60; // S40: 15min access token

interface KeyPairPem {
  privateKeyPem: string;
  publicKeyPem: string;
}

const KEY_ID = "jwt_rs256_current";

async function loadKeyPair(): Promise<KeyPairPem> {
  const row = await db.botConfig.findUnique({ where: { key: KEY_ID } });
  if (row) {
    const parsed = JSON.parse(row.value) as KeyPairPem;
    return parsed;
  }
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const pair: KeyPairPem = {
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
  };
  await db.botConfig.upsert({
    where: { key: KEY_ID },
    create: { key: KEY_ID, value: JSON.stringify(pair) },
    update: { value: JSON.stringify(pair) },
  });
  return pair;
}

/** S50-7: rotation — replace the signing pair (old tokens die naturally via TTL). */
export async function rotateSigningKey(): Promise<void> {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const pair: KeyPairPem = {
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
  };
  await db.botConfig.upsert({
    where: { key: KEY_ID },
    create: { key: KEY_ID, value: JSON.stringify(pair) },
    update: { value: JSON.stringify(pair) },
  });
}

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

export interface JwtClaims {
  sub: string; // user id
  sid: string; // session id
  jti: string;
  iss: string;
  aud: string;
  iat: number;
  exp: number;
  nbf: number;
}

/** Sign an access token. Payload contains NO sensitive data (T-S40-10). */
export async function signAccessToken(sub: string, sid: string, jti: string): Promise<string> {
  const { privateKeyPem } = await loadKeyPair();
  const now = Math.floor(Date.now() / 1000);
  const claims: JwtClaims = {
    sub,
    sid,
    jti,
    iss: JWT_ISSUER,
    aud: JWT_AUDIENCE,
    iat: now,
    exp: now + ACCESS_TOKEN_TTL_SEC,
    nbf: now - 5,
  };
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(claims));
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${body}`);
  const sig = signer.sign(privateKeyPem).toString("base64url");
  return `${header}.${body}.${sig}`;
}

export interface JwtVerdict {
  ok: boolean;
  reason?: string;
  claims?: JwtClaims;
}

/** Full validation: alg, iss, aud, exp, nbf, jti presence (T-S40-9). */
export async function verifyAccessToken(token: string): Promise<JwtVerdict> {
  const parts = token.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed" };
  const [header, body, sig] = parts;
  let h: { alg?: string };
  try {
    h = JSON.parse(Buffer.from(header, "base64url").toString("utf8"));
  } catch {
    return { ok: false, reason: "bad-header" };
  }
  if (h.alg !== "RS256") return { ok: false, reason: "alg-not-allowed" }; // HS256 never accepted
  const { publicKeyPem } = await loadKeyPair();
  const verifier = createVerify("RSA-SHA256");
  verifier.update(`${header}.${body}`);
  const sigBuf = Buffer.from(sig, "base64url");
  const pub = createPublicKey(publicKeyPem);
  if (!verifier.verify({ key: pub, padding: undefined }, sigBuf)) return { ok: false, reason: "bad-signature" };
  let claims: JwtClaims;
  try {
    claims = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return { ok: false, reason: "bad-payload" };
  }
  const now = Math.floor(Date.now() / 1000);
  if (claims.iss !== JWT_ISSUER) return { ok: false, reason: "bad-iss" };
  if (claims.aud !== JWT_AUDIENCE) return { ok: false, reason: "bad-aud" };
  if (!claims.jti) return { ok: false, reason: "missing-jti" };
  if (claims.exp <= now) return { ok: false, reason: "expired" };
  if (claims.nbf > now + 5) return { ok: false, reason: "not-yet-valid" };
  return { ok: true, claims };
}
