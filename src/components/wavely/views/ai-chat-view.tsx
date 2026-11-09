"use client";

import { useEffect, useRef, useState } from "react";
import { useWavely } from "@/lib/wavely/store";
import { WavelyMark } from "../logo";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { ArrowUp, Sparkles, SquareDashedBottomCode } from "lucide-react";
import { cn } from "@/lib/utils";

interface Msg {
  role: "user" | "assistant";
  content: string;
}

const SUGGESTIONS = [
  "Make me a focus playlist",
  "Songs like Neon Horizon",
  "What is gapless playback?",
  "Surprise me 🎧",
];

const WELCOME: Msg = {
  role: "assistant",
  content:
    "Hey! I'm Wavely AI — your built-in DJ. 🎧\nI can build playlists for your mood, dig up songs like the one you're playing, or explain anything about your player.\nWhat are we listening to today?",
};

function formatReply(text: string): string[] {
  return text.split("\n").filter((l) => l.trim().length > 0);
}

export function AiChatView() {
  const [messages, setMessages] = useState<Msg[]>([WELCOME]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const currentTrack = useWavely((s) => s.currentTrack());

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, busy]);

  async function send(text: string) {
    const content = text.trim();
    if (!content || busy) return;
    const next: Msg[] = [...messages, { role: "user", content }];
    setMessages(next);
    setInput("");
    setBusy(true);
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: next.filter((m) => m !== WELCOME).slice(-10),
          nowPlaying: currentTrack ? `${currentTrack.title} — ${currentTrack.artist} (${currentTrack.album}, ${currentTrack.genre})` : undefined,
        }),
      });
      const data = await res.json();
      setMessages((m) => [
        ...m,
        {
          role: "assistant",
          content: data.reply ?? data.error ?? "Something went wrong — try again.",
        },
      ]);
    } catch {
      setMessages((m) => [
        ...m,
        { role: "assistant", content: "I couldn't reach the server. Check your connection and try again." },
      ]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto flex h-[calc(100dvh-9.5rem)] max-w-3xl flex-col px-4 pb-4 pt-6 md:h-[calc(100dvh-6rem)] md:px-6">
      {/* Header */}
      <div className="mb-4 flex items-center gap-3">
        <div className="relative">
          <WavelyMark size={40} />
          <span className="absolute -bottom-0.5 -right-0.5 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-primary-foreground">
            <Sparkles className="h-2.5 w-2.5" />
          </span>
        </div>
        <div>
          <h1 className="font-display text-lg font-bold leading-tight">Wavely AI</h1>
          <p className="text-xs text-muted-foreground">
            Your music assistant {busy ? "• thinking…" : "• online"}
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="ml-auto rounded-full text-muted-foreground"
          onClick={() => setMessages([WELCOME])}
        >
          <SquareDashedBottomCode className="h-4 w-4" /> New chat
        </Button>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="wavely-scroll flex-1 space-y-4 overflow-y-auto rounded-2xl bg-wav-surface/60 p-4">
        {messages.map((m, i) => (
          <div key={i} className={cn("flex", m.role === "user" ? "justify-end" : "justify-start")}>
            <div
              className={cn(
                "max-w-[85%] whitespace-pre-wrap rounded-2xl px-4 py-3 text-[15px] leading-relaxed",
                m.role === "user"
                  ? "rounded-br-md bg-primary text-primary-foreground"
                  : "rounded-bl-md border border-border bg-wav-elevated text-foreground",
              )}
            >
              {formatReply(m.content).map((line, j) => (
                <p key={j} className={j > 0 ? "mt-1.5" : undefined}>
                  {line}
                </p>
              ))}
            </div>
          </div>
        ))}
        {busy && (
          <div className="flex justify-start">
            <div className="flex items-center gap-1.5 rounded-2xl rounded-bl-md border border-border bg-wav-elevated px-4 py-3.5">
              <span className="h-2 w-2 animate-bounce rounded-full bg-primary [animation-delay:0ms]" />
              <span className="h-2 w-2 animate-bounce rounded-full bg-primary [animation-delay:150ms]" />
              <span className="h-2 w-2 animate-bounce rounded-full bg-primary [animation-delay:300ms]" />
            </div>
          </div>
        )}
      </div>

      {/* Suggestions (only at start) */}
      {messages.length === 1 && !busy && (
        <div className="mt-3 flex flex-wrap gap-2">
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => send(s)}
              className="rounded-full border border-border bg-secondary px-3.5 py-1.5 text-xs font-medium text-secondary-foreground transition hover:border-primary/50 hover:bg-accent"
            >
              {s}
            </button>
          ))}
        </div>
      )}

      {/* Input */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(input);
        }}
        className="mt-3 flex items-end gap-2"
      >
        <Textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send(input);
            }
          }}
          rows={1}
          placeholder="Ask Wavely AI…"
          className="max-h-32 min-h-11 flex-1 resize-none rounded-2xl bg-secondary py-3"
          aria-label="Message Wavely AI"
        />
        <Button
          type="submit"
          size="icon"
          disabled={!input.trim() || busy}
          className="h-11 w-11 shrink-0 rounded-full"
          aria-label="Send message"
        >
          <ArrowUp className="h-5 w-5" />
        </Button>
      </form>
    </div>
  );
}
