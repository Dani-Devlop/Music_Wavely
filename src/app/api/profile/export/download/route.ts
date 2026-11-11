/**
 * S24-3 — one-time, expiring export download. Token is validated hashed; the
 * file is streamed from outside the web root and deleted after download.
 */
import { db } from "@/lib/db";
import { errorResponse } from "@/lib/wavely/server/api-guard";
import { hashToken } from "@/lib/wavely/server/tokens";
import { readFileSync, unlinkSync, existsSync } from "fs";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const t = url.searchParams.get("t");
  if (!t) return errorResponse(400, "invalid_link");
  const mapping = await db.botConfig.findUnique({ where: { key: `export-hash:${hashToken(t)}` } });
  if (!mapping) return errorResponse(404, "not_found");
  const filePath = mapping.value;
  if (!existsSync(filePath)) return errorResponse(404, "expired");
  const row = await db.dataExport.findFirst({ where: { filePath } });
  if (!row || row.usedAt || row.expiresAt.getTime() < Date.now()) return errorResponse(410, "expired");

  await db.dataExport.update({ where: { id: row.id }, data: { usedAt: new Date() } });
  await db.botConfig.delete({ where: { key: mapping.key } }).catch(() => undefined);

  const data = readFileSync(filePath);
  try {
    unlinkSync(filePath); // one-time download — file removed
  } catch {
    /* best-effort */
  }
  return new Response(new Uint8Array(data), {
    headers: {
      "content-type": "application/zip",
      "content-disposition": "attachment; filename=wavely-export.zip",
      "cache-control": "no-store",
    },
  });
}
