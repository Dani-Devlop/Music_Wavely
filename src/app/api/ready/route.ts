/** S29-6 — readiness probe (DB reachable). */
import { db } from "@/lib/db";

export async function GET() {
  try {
    await db.$queryRaw`SELECT 1`;
    return Response.json({ ok: true, status: "ready" }, { headers: { "cache-control": "no-store" } });
  } catch {
    return Response.json({ ok: false, status: "db-unreachable" }, { status: 503, headers: { "cache-control": "no-store" } });
  }
}
