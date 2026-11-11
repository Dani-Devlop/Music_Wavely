/** S29-6 — health check endpoint for load balancers. */
export async function GET() {
  return Response.json({ ok: true, status: "healthy", ts: Date.now() }, { headers: { "cache-control": "no-store" } });
}
