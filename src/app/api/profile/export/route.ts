/**
 * S24-3 / S57-4 — data export: strong auth (password re-auth + 2FA when
 * enabled), ZIP archive (store mode, pure JS) written OUTSIDE the web root,
 * one-time expiring download link (15min).
 */
import { db } from "@/lib/db";
import { requireAuth, requireCsrf, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { verifyPassword } from "@/lib/wavely/server/password";
import { audit } from "@/lib/wavely/server/audit";
import { newToken, hashToken } from "@/lib/wavely/server/tokens";
import { z } from "zod";
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";

const ExportSchema = z.object({ password: z.string().min(1).max(128) }).strict();

const EXPORT_DIR = "/home/z/my-project/db/exports"; // outside web root (T-S49-6 semantics)

/** Minimal STORE-mode ZIP writer (no deps, real archive). */
function crc32(buf: Uint8Array): number {
  let table = crc32Table;
  let c = ~0;
  for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return ~c >>> 0;
}
let crc32Table: number[] | null = null;
function ensureTable() {
  if (crc32Table) return crc32Table;
  crc32Table = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc32Table[n] = c >>> 0;
  }
  return crc32Table;
}
crc32Table = ensureTable();

export function buildZip(files: { name: string; data: Uint8Array }[]): Uint8Array {
  const chunks: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const enc = new TextEncoder();
  for (const f of files) {
    ensureTable();
    const nameBytes = enc.encode(f.name);
    const crc = crc32(f.data);
    const local = new Uint8Array(30 + nameBytes.length);
    const dv = new DataView(local.buffer);
    dv.setUint32(0, 0x04034b50, true);
    dv.setUint16(4, 20, true);
    dv.setUint16(6, 0, true);
    dv.setUint16(8, 0, true); // stored
    dv.setUint16(10, 0, true);
    dv.setUint16(12, 0, true);
    dv.setUint32(14, crc, true);
    dv.setUint32(18, f.data.length, true);
    dv.setUint32(22, f.data.length, true);
    dv.setUint16(26, nameBytes.length, true);
    dv.setUint16(28, 0, true);
    local.set(nameBytes, 30);
    chunks.push(local, f.data);
    const cd = new Uint8Array(46 + nameBytes.length);
    const cdv = new DataView(cd.buffer);
    cdv.setUint32(0, 0x02014b50, true);
    cdv.setUint16(4, 20, true);
    cdv.setUint16(6, 20, true);
    cdv.setUint32(16, crc, true);
    cdv.setUint32(20, f.data.length, true);
    cdv.setUint32(24, f.data.length, true);
    cdv.setUint16(28, nameBytes.length, true);
    cdv.setUint32(42, offset, true);
    cd.set(nameBytes, 46);
    central.push(cd);
    offset += local.length + f.data.length;
  }
  const centralSize = central.reduce((a, c) => a + c.length, 0);
  const end = new Uint8Array(22);
  const ev = new DataView(end.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(8, files.length, true);
  ev.setUint16(10, files.length, true);
  ev.setUint32(12, centralSize, true);
  ev.setUint32(16, offset, true);
  const total = offset + centralSize + 22;
  const out = new Uint8Array(total);
  let pos = 0;
  for (const c of [...chunks, ...central, end]) {
    out.set(c, pos);
    pos += c.length;
  }
  return out;
}

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(ExportSchema, body);
  if (!parsed.ok) return errorResponse(400, "invalid_input");

  const user = await db.user.findUnique({ where: { id: auth.auth.userId } });
  if (!user) return errorResponse(404, "not_found");
  const pwOk = user.passwordHash ? await verifyPassword(parsed.data.password, user.passwordHash) : false;
  if (!pwOk) return errorResponse(401, "reauth-failed");
  // 2FA mandatory for export when enabled (sensitive op)
  if (user.twoFactorEnabled) {
    const otp = request.headers.get("x-2fa-code");
    if (!otp) return errorResponse(403, "2fa-required");
    const { totpVerify, hashCode } = await import("@/lib/wavely/server/totp");
    const { decryptSecret } = await import("@/lib/wavely/server/crypto");
    const secret = user.twoFactorSecret ? decryptSecret(user.twoFactorSecret) : null;
    const codeOk = secret ? totpVerify(secret, otp).ok : false;
    const rec = codeOk ? null : await db.recoveryCode.findFirst({ where: { userId: user.id, codeHash: hashCode(otp), usedAt: null } });
    if (!codeOk && !rec) return errorResponse(403, "2fa-required");
    if (rec) await db.recoveryCode.update({ where: { id: rec.id }, data: { usedAt: new Date() } });
  }

  // assemble the export payload — only the caller's own data
  const [playlists, downloads, sessions, settings, audits] = await Promise.all([
    db.playlist.findMany({ where: { userId: user.id } }),
    db.download.findMany({ where: { userId: user.id } }),
    db.session.findMany({ where: { userId: user.id }, select: { deviceInfo: true, createdAt: true } }),
    db.userSetting.findUnique({ where: { userId: user.id } }),
    db.auditLog.findMany({ where: { userId: user.id }, take: 200, select: { event: true, createdAt: true } }),
  ]);
  const manifest = {
    exportedAt: new Date().toISOString(),
    account: { email: user.email, name: user.name, displayName: user.displayName, language: user.language, theme: user.theme },
    counts: { playlists: playlists.length, downloads: downloads.length, sessions: sessions.length, auditEvents: audits.length },
  };

  const enc = new TextEncoder();
  const zip = buildZip([
    { name: "manifest.json", data: enc.encode(JSON.stringify(manifest, null, 2)) },
    { name: "playlists.json", data: enc.encode(JSON.stringify(playlists, null, 2)) },
    { name: "downloads.json", data: enc.encode(JSON.stringify(downloads, null, 2)) },
    { name: "sessions.json", data: enc.encode(JSON.stringify(sessions, null, 2)) },
    { name: "settings.json", data: enc.encode(JSON.stringify(settings ?? {}, null, 2)) },
    { name: "audit-log.json", data: enc.encode(JSON.stringify(audits, null, 2)) },
  ]);

  mkdirSync(EXPORT_DIR, { recursive: true });
  const exportId = newToken(12);
  const fileName = `wavely-export-${exportId}.zip`;
  const filePath = join(EXPORT_DIR, fileName);
  writeFileSync(filePath, zip);

  const linkToken = newToken(16);
  await db.dataExport.create({
    data: { userId: user.id, filePath, expiresAt: new Date(Date.now() + 15 * 60 * 1000) },
  });
  await db.botConfig.upsert({ where: { key: `export-link:${linkToken}` }, create: { key: `export-link:${linkToken}`, value: `${filePath}:${Date.now() + 15 * 60 * 1000}` }, update: { value: `${filePath}:${Date.now() + 15 * 60 * 1000}` } });
  // store hash mapping for one-time validation
  await db.botConfig.upsert({ where: { key: `export-hash:${hashToken(linkToken)}` }, create: { key: `export-hash:${hashToken(linkToken)}`, value: filePath }, update: { value: filePath } });

  await audit({ userId: user.id, event: "data_export", ip: clientIp(request) });

  return Response.json(
    { ok: true, downloadPath: `/api/profile/export?t=${linkToken}`, expiresInSec: 900 },
    { headers: { "cache-control": "no-store" } },
  );
}
