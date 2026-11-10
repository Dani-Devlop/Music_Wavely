import { NextRequest, NextResponse } from "next/server";
import ZAI from "z-ai-web-dev-sdk";

/**
 * Optional lyrics translation (user rule 9): the user taps "Translate" and the
 * lyrics are translated into their app language. Line order is preserved so
 * translations can render under every original line (language-learning view).
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const MAX_LINES = 80;

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => null);
    const lines: unknown = body?.lines;
    const target: string =
      typeof body?.target === "string" && body.target.trim() ? body.target.trim() : "Persian (Farsi)";

    if (!Array.isArray(lines) || lines.length === 0 || lines.some((l) => typeof l !== "string")) {
      return NextResponse.json({ ok: false, reason: "bad_request" }, { status: 400 });
    }
    const src = (lines as string[]).slice(0, MAX_LINES);

    const zai = await ZAI.create();
    const completion = await zai.chat.completions.create({
      messages: [
        {
          role: "assistant",
          content:
            `You are a professional song-lyric translator. Translate each numbered line into ${target}. ` +
            "Keep the poetic feel and all proper nouns. An empty line stays empty. Never merge or split lines — " +
            "the translation must stay aligned with the original, line by line. " +
            "Respond with STRICT JSON only: a single array of translated strings in the same order. No commentary, no markdown fences.",
        },
        {
          role: "user",
          content: src.map((t, i) => `${i + 1}. ${t}`).join("\n"),
        },
      ],
      thinking: { type: "disabled" },
    });

    const raw = completion.choices[0]?.message?.content ?? "";
    const match = raw.match(/\[[\s\S]*\]/);
    if (!match) throw new Error("no json array in model response");
    const parsed: unknown = JSON.parse(match[0]);
    if (!Array.isArray(parsed)) throw new Error("model did not return an array");

    /* strip an accidental "N." prefix the model may copy from the numbering */
    const out = src.map((_, i) => {
      const v = typeof parsed[i] === "string" ? (parsed[i] as string) : "";
      return v.replace(new RegExp(`^\\s*${i + 1}\\s*[.)\\-]\\s*`), "");
    });
    return NextResponse.json({ ok: true, target, lines: out });
  } catch {
    return NextResponse.json({ ok: false, reason: "translate_failed" }, { status: 502 });
  }
}
