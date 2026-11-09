"use client";

import Image from "next/image";
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer";
import { useWavely } from "@/lib/wavely/store";
import { albumCover, fmtTime, trackById } from "@/lib/wavely/data";
import { useToast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import {
  Disc3,
  FolderDown,
  Heart,
  Info,
  ListEnd,
  ListMusic,
  ListStart,
  MicVocal,
  Radio,
  Scissors,
  Share2,
  SquarePlus,
  UserRound,
} from "lucide-react";

/**
 * Spotify-style "⋯" sheet — every track action lives here:
 * share, like, add to playlist, queue, go to album/artist, download…
 * The row itself stays clean: no inline heart button anymore.
 *
 * Matches the reference: drag handle → track header → tall icon rows,
 * and the gradient "Liked Songs" tile that flips its label in place.
 */
export function TrackActionsSheet() {
  const { toast } = useToast();
  const actionsTrackId = useWavely((s) => s.actionsTrackId);
  const closeActions = useWavely((s) => s.closeActions);
  const favorites = useWavely((s) => s.favorites);
  const toggleFavorite = useWavely((s) => s.toggleFavorite);
  const playNext = useWavely((s) => s.playNext);
  const addToQueue = useWavely((s) => s.addToQueue);
  const setQueueSheetOpen = useWavely((s) => s.setQueueSheetOpen);
  const toggleDownload = useWavely((s) => s.toggleDownload);
  const isOffline = useWavely((s) => s.isOffline);
  const cachedIds = useWavely((s) => s.cachedIds);

  const open = !!actionsTrackId;
  const track = actionsTrackId ? trackById.get(actionsTrackId) : undefined;
  const isFav = !!track && favorites.includes(track.id);
  const isCached = !!track && cachedIds.includes(track.id);
  const onDevice = !!track && (track.origin === "local" || !!track.downloaded);

  /** most actions dismiss the sheet; the like toggle stays open (Spotify does too) */
  const act = (fn: () => void, { keepOpen = false } = {}) => {
    fn();
    if (!keepOpen) closeActions();
  };

  return (
    <Drawer open={open} onOpenChange={(v) => (!v ? closeActions() : undefined)}>
      <DrawerContent
        aria-describedby={undefined}
        className="z-[70] mx-auto max-h-[85dvh] w-full max-w-lg rounded-t-2xl border-border bg-popover/95 backdrop-blur-2xl"
      >
        <DrawerTitle className="sr-only">Song options</DrawerTitle>
        {/* track header — cover, title, artist (like the Spotify reference) */}
        {track && (
          <div className="flex items-center gap-3.5 px-4 pb-3 pt-2">
            <Image
              src={albumCover(track.albumId)}
              alt=""
              width={48}
              height={48}
              className="rounded-md object-cover"
            />
            <div className="min-w-0">
              <p className="truncate text-[15px] font-semibold leading-tight">{track.title}</p>
              <p className="truncate text-[13px] leading-tight text-muted-foreground">
                {track.artist}
                {track.origin === "online" && !track.downloaded && ` • ${fmtTime(track.duration)}`}
              </p>
            </div>
          </div>
        )}

        {/* action rows */}
        <div className="wavely-scroll min-h-0 flex-1 overflow-y-auto px-2 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {track && (
            <>
              <ActionRow
                icon={<Share2 className="h-6 w-6" />}
                label="Share"
                onClick={() =>
                  act(() => toast({ description: `Link to “${track.title}” copied` }))
                }
              />
              <ActionRow
                icon={
                  <span
                    className={cn(
                      "flex h-8 w-8 items-center justify-center rounded-md bg-gradient-to-br from-emerald-200 via-primary to-emerald-600 shadow",
                      isFav && "ring-1 ring-primary/60",
                    )}
                  >
                    <Heart className="h-4.5 w-4.5 fill-white text-white" />
                  </span>
                }
                label={isFav ? "Remove from Liked Songs" : "Add to Liked Songs"}
                onClick={() =>
                  act(() => {
                    toggleFavorite(track.id);
                    toast({
                      description: isFav
                        ? "Removed from Liked Songs"
                        : "Added to Liked Songs",
                    });
                  }, { keepOpen: true })
                }
              />
              <ActionRow
                icon={<SquarePlus className="h-6 w-6" />}
                label="Add to playlist"
                onClick={() =>
                  act(() => toast({ description: "Add to playlist — pick one in the full app" }))
                }
              />
              <ActionRow
                icon={<ListEnd className="h-6 w-6" />}
                label="Add to Queue"
                onClick={() =>
                  act(() => {
                    addToQueue(track.id);
                    toast({ description: `Added to queue: ${track.title}` });
                  })
                }
              />
              <ActionRow
                icon={<ListStart className="h-6 w-6" />}
                label="Play next"
                onClick={() =>
                  act(() => {
                    playNext(track.id);
                    toast({ description: `Playing next: ${track.title}` });
                  })
                }
              />
              <ActionRow
                icon={<ListMusic className="h-6 w-6" />}
                label="Go to Queue"
                onClick={() =>
                  act(() => setQueueSheetOpen(true))
                }
              />
              {track.origin === "online" && (
                <ActionRow
                  icon={
                    <FolderDown
                      className={cn("h-6 w-6", track.downloaded && "text-primary")}
                    />
                  }
                  label={
                    track.downloaded
                      ? "Remove download"
                      : isCached
                        ? "Save from cache (instant)"
                        : "Download to device"
                  }
                  onClick={() =>
                    act(() => {
                      if (isOffline && !track.downloaded) {
                        toast({
                          description: "You're offline — go back online to download",
                        });
                        return;
                      }
                      toggleDownload(track.id);
                    })
                  }
                />
              )}
              <ActionRow
                icon={<Disc3 className="h-6 w-6" />}
                label="Go to album"
                onClick={() => act(() => toast({ description: `Album: ${track.album}` }))}
              />
              <ActionRow
                icon={<UserRound className="h-6 w-6" />}
                label="Go to artist"
                onClick={() => act(() => toast({ description: `Artist: ${track.artist}` }))}
              />
              {track.origin === "online" && (
                <ActionRow
                  icon={<Radio className="h-6 w-6" />}
                  label="Go to song radio"
                  onClick={() =>
                    act(() => toast({ description: `Song radio from “${track.title}” starts here` }))
                  }
                />
              )}
              {onDevice && (
                <ActionRow
                  icon={<Scissors className="h-6 w-6" />}
                  label="Use as ringtone…"
                  onClick={() =>
                    act(() => toast({ description: "Ringtone cutter opens here in the real app" }))
                  }
                />
              )}
              <ActionRow
                icon={<Info className="h-6 w-6" />}
                label="View song credits"
                onClick={() =>
                  act(() =>
                    toast({
                      description: `${track.artist} • ${track.album} • ${track.year} • ${track.quality === "FLAC" ? "FLAC lossless" : `${track.quality} kbps`}`,
                    }),
                  )
                }
              />
              <ActionRow
                icon={<MicVocal className="h-6 w-6" />}
                label="Song details"
                onClick={() =>
                  act(() =>
                    toast({
                      description: "13-field tag editor opens here in the real app",
                    }),
                  )
                }
              />
            </>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  );
}

/** One tall Spotify-style row: plain icon left, single label, generous touch area. */
function ActionRow({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
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
      <span className="truncate text-[15px] font-medium">{label}</span>
    </button>
  );
}
