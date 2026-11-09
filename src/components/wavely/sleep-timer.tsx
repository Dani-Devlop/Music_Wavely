"use client";

import { useState } from "react";
import { useWavely } from "@/lib/wavely/store";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Moon, Timer } from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";

const PRESETS = [5, 10, 15, 30, 45, 60];

export function SleepTimerDialog() {
  const open = useWavely((s) => s.sleepTimerOpen);
  const setOpen = useWavely((s) => s.setSleepTimerOpen);
  const setSleepTimer = useWavely((s) => s.setSleepTimer);
  const sleepEndsAt = useWavely((s) => s.sleepEndsAt);
  const [custom, setCustom] = useState("");
  const { toast } = useToast();

  function apply(minutes: number | "track" | null, label: string) {
    setSleepTimer(minutes);
    setOpen(false);
    toast({
      description: minutes === null ? "Sleep timer cancelled" : `Sleep timer: ${label}`,
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-w-sm rounded-2xl border-border bg-popover p-5">
        <DialogHeader className="flex-row items-center gap-2.5 space-y-0 text-left">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/15 text-primary">
            <Moon className="h-4.5 w-4.5" />
          </div>
          <DialogTitle className="font-display text-lg">Sleep timer</DialogTitle>
        </DialogHeader>

        {sleepEndsAt && (
          <div className="flex items-center gap-2 rounded-xl bg-primary/10 px-3 py-2.5 text-sm text-primary">
            <Timer className="h-4 w-4" />
            Timer active — music will stop automatically.
          </div>
        )}

        <div className="grid grid-cols-3 gap-2">
          {PRESETS.map((m) => (
            <Button
              key={m}
              variant="outline"
              className={cn("h-11 rounded-xl", sleepEndsAt && "border-primary/40")}
              onClick={() => apply(m, `${m} minutes`)}
            >
              {m} min
            </Button>
          ))}
        </div>

        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            const v = parseInt(custom, 10);
            if (!isNaN(v) && v > 0) apply(v, `${v} minutes`);
          }}
        >
          <Input
            value={custom}
            onChange={(e) => setCustom(e.target.value.replace(/\D/g, ""))}
            placeholder="Custom minutes…"
            inputMode="numeric"
            className="h-10 rounded-xl"
          />
          <Button type="submit" variant="secondary" className="h-10 rounded-xl px-4">
            Set
          </Button>
        </form>

        <div className="flex gap-2">
          <Button
            variant="secondary"
            className="h-10 flex-1 rounded-xl"
            onClick={() => apply("track", "End of track")}
          >
            End of track
          </Button>
          <Button
            variant="ghost"
            className="h-10 flex-1 rounded-xl text-destructive hover:text-destructive"
            onClick={() => apply(null, "")}
          >
            Cancel timer
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
