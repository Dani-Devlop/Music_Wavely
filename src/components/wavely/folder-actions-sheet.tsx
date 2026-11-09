"use client";

import { useEffect, useState } from "react";
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer";
import { useWavely } from "@/lib/wavely/store";
import { TRACKS, fmtLongTime, trackById } from "@/lib/wavely/data";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  Ban,
  ChevronLeft,
  Folder,
  FolderRoot,
  Gauge,
  ListEnd,
  ListMusic,
  ListPlus,
  PenLine,
  Play,
  Share2,
  Shuffle,
  SkipForward,
  Smartphone,
  SquarePlus,
} from "lucide-react";

/**
 * Musicolet-style folder sheet — long-press (or ⋯) on a folder:
 * folder management on top, then "options for all songs in this folder
 * and its subfolders". Playing a folder creates a queue named after it,
 * exactly like Musicolet's "5. En(+)" — number = slot, (+) = shuffled.
 */
export function FolderActionsSheet() {
  const { toast } = useToast();
  const path = useWavely((s) => s.folderActionsPath);
  const closeActions = useWavely((s) => s.closeFolderActions);
  const playContext = useWavely((s) => s.playContext);
  const playNextMany = useWavely((s) => s.playNextMany);
  const addToQueueMany = useWavely((s) => s.addToQueueMany);
  const addIdsToQueue = useWavely((s) => s.addIdsToQueue);
  const createQueue = useWavely((s) => s.createQueue);
  const toggleShuffle = useWavely((s) => s.toggleShuffle);
  const shuffle = useWavely((s) => s.shuffle);
  const setNowPlayingOpen = useWavely((s) => s.setNowPlayingOpen);
  const queues = useWavely((s) => s.queues);

  /** "Add to a queue" opens a nested picker inside the same sheet */
  const [pickerOpen, setPickerOpen] = useState(false);

  // a fresh folder always opens the main menu, never a stale picker
  useEffect(() => {
    setPickerOpen(false);
  }, [path]);

  const open = !!path;
  const short = path ? path.split("/").filter(Boolean).slice(-1)[0] : "";
  // Musicolet semantics: the folder AND everything inside it
  const folderTracks = path
    ? TRACKS.filter((t) => t.folder === path || t.folder.startsWith(path + "/"))
    : [];
  const ids = folderTracks.map((t) => t.id);
  const totalTime = folderTracks.reduce((a, t) => a + t.duration, 0);
  const nextSlot = queues.filter((q) => !q.pinned).length + 1;

  const act = (fn: () => void, { keepOpen = false } = {}) => {
    fn();
    if (!keepOpen) closeActions();
  };

  /** play the folder as a fresh Musicolet-numbered queue: "6. En" / "6. En(+)" */
  const playFolder = (shuffled: boolean) => {
    const name = `${nextSlot}. ${short}${shuffled ? " (+)" : ""}`;
    playContext(name, ids, shuffled ? Math.floor(Math.random() * Math.max(1, ids.length)) : 0);
    if (shuffled && !useWavely.getState().shuffle) toggleShuffle();
    setNowPlayingOpen(true);
    toast({ description: `Queue “${name}” — ${folderTracks.length} songs` });
  };

  return (
    <Drawer
      open={open}
      onOpenChange={(v) => {
        if (!v) {
          closeActions();
          setPickerOpen(false);
        }
      }}
    >
      <DrawerContent
        aria-describedby={undefined}
        className="z-[70] mx-auto max-h-[85dvh] w-full max-w-lg rounded-t-2xl border-border bg-popover/95 backdrop-blur-2xl"
      >
        <DrawerTitle className="sr-only">Folder options</DrawerTitle>

        {/* folder header — like Musicolet's long-press dialog title */}
        {path && (
          <div className="flex items-center gap-3.5 px-4 pb-3 pt-2">
            <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
              <Folder className="h-6 w-6" />
            </span>
            <div className="min-w-0">
              <p className="truncate text-[15px] font-semibold leading-tight">{short}</p>
              <p className="truncate text-[12px] leading-tight text-muted-foreground">
                {folderTracks.length} songs • {fmtLongTime(totalTime)}
              </p>
            </div>
          </div>
        )}

        <div className="wavely-scroll min-h-0 flex-1 overflow-y-auto px-2 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {path && !pickerOpen && (
            <>
              <ActionRow
                icon={<FolderRoot className="h-6 w-6" />}
                label="Set as main music folder"
                onClick={() =>
                  act(() => toast({ description: `“${short}” set as main music folder` }))
                }
              />
              <ActionRow
                icon={<Ban className="h-6 w-6" />}
                label="Exclude this folder from scanning"
                onClick={() =>
                  act(() => toast({ description: `“${short}” excluded from scanning` }))
                }
              />
              <ActionRow
                icon={<Smartphone className="h-6 w-6" />}
                label="Add shortcut to Home screen"
                onClick={() =>
                  act(() => toast({ description: `Shortcut to “${short}” added on the real device` }))
                }
              />

              <p className="px-4 pb-1 pt-3 text-[11px] font-medium text-muted-foreground">
                Options for all {folderTracks.length} songs in this folder and its subfolders
              </p>

              <ActionRow
                icon={<Shuffle className="h-6 w-6" />}
                label="Shuffle and play"
                onClick={() => act(() => playFolder(true))}
              />
              <ActionRow
                icon={<Play className="h-6 w-6" />}
                label="Play"
                onClick={() => act(() => playFolder(false))}
              />
              <ActionRow
                icon={<SkipForward className="h-6 w-6" />}
                label="Play after current song"
                onClick={() =>
                  act(() => {
                    playNextMany(ids);
                    toast({
                      description: `${folderTracks.length} songs queued after the current one`,
                    });
                  })
                }
              />
              <ActionRow
                icon={<ListEnd className="h-6 w-6" />}
                label="Add to currently playing queue"
                onClick={() =>
                  act(() => {
                    addToQueueMany(ids);
                    toast({ description: `${folderTracks.length} songs added to the queue` });
                  })
                }
              />
              <ActionRow
                icon={<ListPlus className="h-6 w-6" />}
                label="Add to a queue"
                onClick={() => setPickerOpen(true)}
              />
              <ActionRow
                icon={<SquarePlus className="h-6 w-6" />}
                label="Add to playlists"
                onClick={() =>
                  act(() => toast({ description: "Add to playlists — pick one in the full app" }))
                }
              />
              <ActionRow
                icon={<PenLine className="h-6 w-6" />}
                label="Edit tags"
                onClick={() =>
                  act(() => toast({ description: "Batch tag editor opens here in the real app" }))
                }
              />
              <ActionRow
                icon={<Gauge className="h-6 w-6" />}
                label="Play speed and Pitch"
                onClick={() =>
                  act(() => toast({ description: "Speed & pitch picker opens here in the real app" }))
                }
              />
              <ActionRow
                icon={<Share2 className="h-6 w-6" />}
                label="Share"
                onClick={() => act(() => toast({ description: "Folder link copied" }))}
              />
            </>
          )}

          {path && pickerOpen && (
            <>
              <button
                onClick={() => setPickerOpen(false)}
                className="flex min-h-[52px] w-full items-center gap-3 rounded-xl px-3 text-left transition-colors hover:bg-accent/60"
              >
                <ChevronLeft className="h-5 w-5 text-muted-foreground" />
                <span className="text-sm font-semibold">
                  Add {folderTracks.length} songs to…
                </span>
              </button>
              {queues.map((q) => (
                <ActionRow
                  key={q.id}
                  icon={
                    <ListMusic
                      className={cn("h-5 w-5", q.id === useWavely.getState().activeQueueId && "text-primary")}
                    />
                  }
                  label={
                    <span className="flex items-center gap-2">
                      <span className="truncate">{q.name}</span>
                      <span className="rounded-full bg-accent px-1.5 text-[10px] font-bold text-muted-foreground">
                        {q.trackIds.length}
                      </span>
                    </span>
                  }
                  onClick={() =>
                    act(() => {
                      addIdsToQueue(q.id, ids);
                      toast({ description: `${folderTracks.length} songs added to “${q.name}”` });
                    })
                  }
                />
              ))}
              <ActionRow
                icon={<ListPlus className="h-6 w-6" />}
                label={`New queue “${short}”`}
                onClick={() =>
                  act(() => {
                    const s = useWavely.getState();
                    if (s.queues.length >= 20) {
                      toast({ description: "All 20 queue slots are full" });
                      return;
                    }
                    createQueue(short);
                    const created = useWavely.getState().queues.slice(-1)[0];
                    addIdsToQueue(created.id, ids);
                    toast({
                      description: `Queue “${short}” created with ${folderTracks.length} songs`,
                    });
                  })
                }
              />
            </>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  );
}

/** One tall row: plain icon left, label, generous touch area (Spotify sheet style). */
function ActionRow({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex min-h-[56px] w-full items-center gap-5 rounded-xl px-3 text-left transition-colors hover:bg-accent/60 active:bg-accent"
    >
      <span className="flex w-8 shrink-0 items-center justify-center text-foreground/85">
        {icon}
      </span>
      <span className="min-w-0 flex-1 truncate text-[15px] font-medium">{label}</span>
    </button>
  );
}

/** Resolve folder path → track ids (shared with the folder list view). */
export function tracksInFolder(folder: string) {
  return TRACKS.filter((t) => t.folder === folder || t.folder.startsWith(folder + "/")).map(
    (t) => trackById.get(t.id)!,
  );
}
