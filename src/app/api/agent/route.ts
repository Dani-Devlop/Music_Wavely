/**
 * S22 / S68 — Agent chat endpoint: full policy pipeline.
 * input filter → music-only classifier → quota → deterministic music-domain
 * tool routing → output filter → audit. The LLM path is layered on top; the
 * policy verdicts are identical either way.
 */
import { requireAuth, requireCsrf, guardRate, errorResponse, clientIp, parseStrict } from "@/lib/wavely/server/api-guard";
import { AgentChatSchema } from "@/lib/wavely/server/validation";
import { handleAgentRequest, filterAgentOutput } from "@/lib/wavely/server/agent-policy";

export async function POST(request: Request) {
  const auth = await requireAuth(request);
  if (!auth.ok || !auth.auth) return errorResponse(auth.status, auth.code);
  const rate = guardRate(request, "ai", auth.auth.userId);
  if (!rate.ok) return errorResponse(rate.status, rate.code, rate.message);
  const csrf = await requireCsrf(request, auth.auth.sessionId);
  if (!csrf.ok) return errorResponse(csrf.status, csrf.code);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }
  const parsed = parseStrict(AgentChatSchema, body);
  if (!parsed.ok) return errorResponse(parsed.status, parsed.code);

  const result = await handleAgentRequest(auth.auth.userId, parsed.data.message, clientIp(request));
  if (!result.ok) {
    const status = result.code.includes("quota") ? 429 : 200;
    return Response.json({ ok: false, code: result.code, reply: result.reply ?? null }, { status, headers: { "cache-control": "no-store" } });
  }
  const out = filterAgentOutput(result.reply ?? "");
  if (!out.ok) return errorResponse(422, `agent-output-blocked-${out.reason}`);
  return Response.json({ ok: true, reply: out.cleaned }, { headers: { "cache-control": "no-store" } });
}
