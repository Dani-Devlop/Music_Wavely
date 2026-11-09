import { NextRequest, NextResponse } from "next/server";
import ZAI from "z-ai-web-dev-sdk";

export const runtime = "nodejs";
export const maxDuration = 60;

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const messages: ChatMessage[] = Array.isArray(body?.messages) ? body.messages : [];
    const nowPlaying: string | undefined = body?.nowPlaying;

    if (messages.length === 0) {
      return NextResponse.json({ error: "messages required" }, { status: 400 });
    }

    const zai = await ZAI.create();

    const system = [
      "You are Wavely AI — the friendly music assistant and DJ built into the Wavely music player.",
      "The user is a music enthusiast who uses Wavely to play their local library (and legal online sources).",
      nowPlaying ? `The track currently playing is: ${nowPlaying}.` : "Nothing is playing right now.",
      "Your style: warm, concise, a little playful — like a great radio DJ. Keep answers short (2-5 sentences) unless asked for more.",
      "You help with: playlist ideas, 'songs like X', artist facts, music trivia, mood-based picks, and player tips (queues, equalizer, sleep timer, lyrics).",
      "When suggesting music, format as a tight list of 'Song — Artist' lines (max 6).",
      "You cannot control playback directly; if asked, explain which Wavely screen to use instead.",
      "Never invent features Wavely does not have.",
    ].join(" ");

    const completion = await zai.chat.completions.create({
      messages: [
        { role: "assistant", content: system },
        ...messages.slice(-12).map((m) => ({ role: m.role, content: m.content })),
      ],
      thinking: { type: "disabled" },
    });

    const reply = completion.choices[0]?.message?.content ?? "Hmm, my circuits hiccuped — try again?";

    return NextResponse.json({ reply });
  } catch (err) {
    console.error("[/api/chat] error:", err);
    return NextResponse.json(
      { error: "Wavely AI is unavailable right now. Please try again." },
      { status: 500 },
    );
  }
}
