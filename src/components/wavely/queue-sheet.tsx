"use client";

import { useMemo, useState } from "react";
import { Drawer, DrawerContent, DrawerHeader, DrawerTitle } from "@/components/ui/drawer";
import { useWavely, useActiveQueue, useCurrentTrack } from "@/lib/wavely/store";
import { trackById } from "@/lib/wavely/data";
import { Cover } from "./cover";
import { EqBars } from "./eq-bars";
import { fmtTime } from "@/lib/wavely/data";
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  GripVertical,
  ListMusic,
  Plus,
  Shuffle,
  Trash2,
  X,
  Play,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import type { Track } from "@/lib/wavely/types";

function QueueItem({
  track,
  index,
  isCurrent,
}: {
  track: Track;
  index: number;
  isCurrent: boolean;
}) {
  const removeFromQueue = useWavely((s) => s.removeFromQueue);
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: track.id + ":" + index,
  });

  return (
    <div
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={cn(
        "group flex items-center gap-2.5 rounded-xl px-2 py-1.5 transition-colors",
        isCurrent ? "bg-primary/10" : "hover:bg-accent/60",
        isDragging && "z-10 bg-accent shadow-lg",
      )}
    >
      <button
        {...attributes}
        {...listeners}
        className="flex h-8 w-5 shrink-0 cursor-grab touch-none items-center justify-center text-muted-foreground/50 hover:text-foreground active:cursor-grabbing"
        aria-label="Reorder"
      >
        <GripVertical className="h-4 w-4" />
      </button>
      <QueueItemCover track={track} />
      <div className="min-w-0 flex-1">
        <p className={cn("truncate text-sm font-medium", isCurrent && "text-primary")}>{track.title}</p>
        <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
      </div>
      <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{fmtTime(track.duration)}</span>
      <button
        onClick={() => removeFromQueue(index)}
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted-foreground/60 opacity-0 transition hover:text-destructive group-hover:opacity-100"
        aria-label={`Remove ${track.title} from queue`}
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}

function QueueItemCover({ track }: { track: Track }) {
  const covers: Record<string, string> = {
    al1: "neon-horizon", al2: "midnight-bloom", al3: "green-circuit", al4: "paper-planes",
    al5: "deep-focus", al6: "velvet-static", al7: "golden-hour", al8: "persian-echoes",
  };
  return <Cover src={`/covers/${covers[track.albumId] ?? "neon-horizon"}.png`} alt={track.album} size={38} />;
}

export function QueueSheet() {
  const open = useWavely((s) => s.queueSheetOpen);
  const setOpen = useWavely((s) => s.setQueueSheetOpen);
  const queues = useWavely((s) => s.queues);
  const activeQueue = useActiveQueue();
  const activeQueueId = useWavely((s) => s.activeQueueId);
  const selectQueue = useWavely((s) => s.selectQueue);
  const createQueue = useWavely((s) => s.createQueue);
  const index = useWavely((s) => s.index);
  const reorderQueue = useWavely((s) => s.reorderQueue);
  const clearQueue = useWavely((s) => s.clearQueue);
  const toggleShuffle = useWavely((s) => s.toggleShuffle);
  const shuffle = useWavely((s) => s.shuffle);
  const currentTrack = useCurrentTrack();
  const { toast } = useToast();

  const [newName, setNewName] = useState("");
  const [adding, setAdding] = useState(false);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const tracks = useMemo(
    () => (activeQueue?.trackIds ?? []).map((id) => trackById.get(id)!).filter(Boolean),
    [activeQueue],
  );

  function onDragEnd(e: DragEndEvent) {
    const { active, over } = e;
    if (!over || active.id === over.id || !activeQueue) return;
    const from = activeQueue.trackIds.findIndex((_, i) => `${activeQueue.trackIds[i]}:${i}` === active.id);
    const to = activeQueue.trackIds.findIndex((_, i) => `${activeQueue.trackIds[i]}:${i}` === over.id);
    if (from < 0 || to < 0) return;
    reorderQueue(arrayMove(activeQueue.trackIds, from, to));
  }

  return (
    <Drawer open={open} onOpenChange={setOpen}>
      <DrawerContent className="z-[70] mx-auto max-h-[85dvh] w-full max-w-lg rounded-t-2xl border-border bg-popover/95 backdrop-blur-2xl">
        <DrawerHeader className="pb-2 pt-3">
          <DrawerTitle className="flex items-center justify-center gap-2 font-display text-base">
            <ListMusic className="h-4 w-4 text-primary" /> Queue
          </DrawerTitle>
        </DrawerHeader>

        {/* Queue switcher — Musicolet multi-queue */}
        <div className="no-scrollbar mb-2 flex gap-2 overflow-x-auto px-4">
          {queues.map((q) => (
            <button
              key={q.id}
              onClick={() => selectQueue(q.id)}
              className={cn(
                "flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition",
                q.id === activeQueueId
                  ? "bg-primary text-primary-foreground"
                  : "bg-secondary text-secondary-foreground hover:bg-accent",
              )}
            >
              {q.name}
              <span className={cn("rounded-full px-1 text-[10px]", q.id === activeQueueId ? "bg-black/20" : "bg-accent")}>
                {q.trackIds.length}
              </span>
            </button>
          ))}
          {adding ? (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                if (newName.trim()) {
                  createQueue(newName.trim());
                  toast({ description: `Queue "${newName.trim()}" created` });
                  setNewName("");
                  setAdding(false);
                }
              }}
              className="flex shrink-0 items-center gap-1"
            >
              <Input
                autoFocus
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                onBlur={() => setAdding(false)}
                placeholder="Name…"
                className="h-7 w-28 rounded-full text-xs"
              />
            </form>
          ) : (
            <button
              onClick={() => setAdding(true)}
              className="flex shrink-0 items-center gap-1 rounded-full border border-dashed border-border px-3 py-1.5 text-xs font-medium text-muted-foreground transition hover:text-foreground"
            >
              <Plus className="h-3 w-3" /> New
            </button>
          )}
        </div>

        <div className="wavely-scroll min-h-0 flex-1 overflow-y-auto px-3 pb-6">
          {/* Current */}
          {currentTrack && (
            <div className="mb-1 mt-1 flex items-center gap-2.5 rounded-xl bg-primary/10 px-2 py-2 ring-1 ring-primary/30">
              <span className="ml-2 text-[10px] font-bold uppercase tracking-widest text-primary">Now</span>
              <QueueItemCover track={currentTrack} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold text-primary">{currentTrack.title}</p>
                <p className="truncate text-xs text-muted-foreground">{currentTrack.artist}</p>
              </div>
              <EqBars />
            </div>
          )}

          <div className="flex items-center justify-between px-2 pb-1 pt-2">
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Next up • {Math.max(0, tracks.length - index - 1)} songs
            </p>
            <div className="flex items-center gap-1">
              <Button
                variant="ghost"
                size="icon"
                className={cn("h-8 w-8 rounded-full", shuffle && "text-primary")}
                onClick={toggleShuffle}
                aria-label="Toggle shuffle"
              >
                <Shuffle className="h-3.5 w-3.5" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 rounded-full text-muted-foreground hover:text-destructive"
                onClick={() => {
                  clearQueue();
                  toast({ description: "Queue cleared" });
                }}
                aria-label="Clear queue"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          </div>

          {tracks.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
              <ListMusic className="h-8 w-8" />
              <p className="text-sm">Queue is empty — play something!</p>
            </div>
          ) : (
            <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
              <SortableContext
                items={tracks.map((t, i) => `${t.id}:${i}`)}
                strategy={verticalListSortingStrategy}
              >
                {tracks.map((t, i) =>
                  i === index ? (
                    <div key={`${t.id}:${i}`} className="h-0" />
                  ) : (
                    <QueueItem key={`${t.id}:${i}`} track={t} index={i} isCurrent={false} />
                  ),
                )}
              </SortableContext>
            </DndContext>
          )}

          {tracks.length > 0 && (
            <p className="pt-3 text-center text-xs text-muted-foreground">
              Playing {index + 1} of {tracks.length} • drag to reorder
            </p>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  );
}
