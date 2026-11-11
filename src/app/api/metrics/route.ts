/** S29-8 — Prometheus-format metrics endpoint. */
import { db } from "@/lib/db";

export async function GET() {
  const [users, sessions, playlists, auditCount] = await Promise.all([
    db.user.count().catch(() => -1),
    db.session.count({ where: { revokedAt: null } }).catch(() => -1),
    db.playlist.count().catch(() => -1),
    db.auditLog.count().catch(() => -1),
  ]);
  const body = [
    "# HELP wavely_users_total Registered users",
    "# TYPE wavely_users_total gauge",
    `wavely_users_total ${users}`,
    "# HELP wavely_sessions_active Active sessions",
    "# TYPE wavely_sessions_active gauge",
    `wavely_sessions_active ${sessions}`,
    "# HELP wavely_playlists_total Playlists",
    "# TYPE wavely_playlists_total gauge",
    `wavely_playlists_total ${playlists}`,
    "# HELP wavely_audit_events_total Audit events",
    "# TYPE wavely_audit_events_total counter",
    `wavely_audit_events_total ${auditCount}`,
    "# HELP wavely_uptime_seconds Process uptime",
    "# TYPE wavely_uptime_seconds gauge",
    `wavely_uptime_seconds ${Math.floor(process.uptime())}`,
    "",
  ].join("\n");
  return new Response(body, { headers: { "content-type": "text/plain; version=0.0.4", "cache-control": "no-store" } });
}
