"use client";

import Image from "next/image";
import { Cover } from "./cover";
import { EqBars } from "./eq-bars";
import { OriginBadge } from "./origin-badge";
import { useWavely, useIsTrackPlayable } from "@/lib/wavely/store";
import { albumCover, fmtTime } from "@/lib/wavely/data";
import type { Track } from "@/lib/wavely/types";
import {
  Album,
  ArrowRightLeft,
  Disc3,
  FolderDown,
  Heart,
  ListEnd,
  ListStart,
  MicVocal,
  MoreVertical,
  Play,
  Scissors,
  Share2,
  Trash2,
  UserRound,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";

export function SongRow({
  track,
  index,
  onPlay,
  showIndex = false,
  compact = false,
}: {
  track: Track;
  index?: number;
  onPlay: () => void;
  showIndex?: boolean;
  compact?: boolean;
}) {
  const { toast } = useToast();
  const currentTrack = useWavely((s) => s.currentTrack());
  const isPlaying = useWavely((s) => s.isPlaying);
  const favorites = useWavely((s) => s.favorites);
  const isOffline = useWavely((s) => s.isOffline);
  const toggleFavorite = useWavely((s) => s.toggleFavorite);
  const playNext = useWavely((s) => s.playNext);
  const addToQueue = useWavely((s) => s.addToQueue);
  const setNowPlayingOpen = useWavely((s) => s.setNowPlayingOpen);
  const toggleDownload = useWavely((s) => s.toggleDownload);
  const isCached = useWavely((s) => s.cachedIds.includes(track.id));
  const playable = useIsTrackPlayable(track);
  const isCurrent = currentTrack?.id === track.id;
  const isFav = favorites.includes(track.id);

  const handleUnavailable = () => {
    toast({
      description: isOffline
        ? "You're offline — download this song or go back online"
        : "This track isn't available right now",
    });
  };

  const menu = (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          className="flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          aria-label={`More options for ${track.title}`}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreVertical className="h-4 w-4" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        sideOffset={4}
        className="w-60 rounded-xl border-border/80 bg-popover/95 backdrop-blur-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-3 border-b border-border/60 px-3 py-2.5">
          <Image
            src={albumCover(track.albumId)}
            alt=""
            width={36}
            height={36}
            className="rounded-md object-cover"
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">{track.title}</p>
            <p className="truncate text-xs text-muted-foreground">
              {track.artist} • {fmtTime(track.duration)}
            </p>
          </div>
        </div>
        <DropdownMenuItem
          onClick={() => {
            toggleFavorite(track.id);
            toast({ description: isFav ? "Removed from Favorites" : "Added to Favorites" });
          }}
        >
          <Heart className={cn("h-4 w-4", isFav && "fill-primary text-primary")} />
          {isFav ? "Remove from Favorites" : "Add to Favorites"}
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => {
            playNext(track.id);
            toast({ description: `Playing next: ${track.title}` });
          }}
        >
          <ListStart className="h-4 w-4" /> Play next
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => {
            addToQueue(track.id);
            toast({ description: `Added to queue: ${track.title}` });
          }}
        >
          <ListEnd className="h-4 w-4" /> Add to queue
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => toast({ description: "Add to playlist — pick one in the full app" })}>
          <Album className="h-4 w-4" /> Add to playlist…
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        {track.origin === "online" && (
          <DropdownMenuItem
            onClick={() => {
              const wasDownloaded = !!track.downloaded;
              toggleDownload(track.id);
              toast({
                description: wasDownloaded
                  ? `Removed from device: ${track.title}`
                  : isCached
                    ? `Saved from cache — no re-download needed`
                    : `Saved to your music folder (organised by country/genre)`,
              });
            }}
          >
            <FolderDown className={cn("h-4 w-4", track.downloaded && "text-primary fill-primary/30")} />
            {track.downloaded ? "Remove download" : isCached ? "Save from cache (instant)" : "Download to device"}
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={() => toast({ description: `Album: ${track.album}` })}>
          <Disc3 className="h-4 w-4" /> Go to album
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => toast({ description: `Artist: ${track.artist}` })}>
          <UserRound className="h-4 w-4" /> Go to artist
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => toast({ description: `Genre: ${track.genre}` })}>
          <MicVocal className="h-4 w-4" /> Go to genre
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => toast({ description: "Ringtone cutter opens here in the real app" })}>
          <Scissors className="h-4 w-4" /> Use as ringtone…
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => toast({ description: "Share link copied" })}>
          <Share2 className="h-4 w-4" /> Share
        </DropdownMenuItem>
        <DropdownMenuItem
          className="text-destructive focus:text-destructive"
          onClick={() => toast({ description: "Song details — 13-field tag editor in the real app" })}
        >
          <ArrowRightLeft className="h-4 w-4" /> Song details
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => {
        if (!playable) {
          handleUnavailable();
          return;
        }
        onPlay();
        setNowPlayingOpen(true);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          if (!playable) {
            handleUnavailable();
            return;
          }
          onPlay();
          setNowPlayingOpen(true);
        }
      }}
      className={cn(
        "group flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-accent/70 focus-visible:bg-accent/70 focus-visible:outline-none",
        compact && "py-1.5",
        !playable && "opacity-55",
      )}
      title={!playable ? "Unavailable offline" : undefined}
    >
      {showIndex && (
        <span className="w-6 shrink-0 text-center text-sm text-muted-foreground tabular-nums">
          {(index ?? 0) + 1}
        </span>
      )}
      <div className="relative">
        <Cover src={albumCover(track.albumId)} alt={track.album} size={compact ? 40 : 48} />
        <div
          className={cn(
            "absolute inset-0 flex items-center justify-center rounded-md bg-black/55 opacity-0 transition-opacity group-hover:opacity-100",
            isCurrent && "opacity-100",
          )}
        >
          {isCurrent && isPlaying ? (
            <EqBars />
          ) : (
            <Play className="h-5 w-5 fill-white text-white" />
          )}
        </div>
      </div>
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            "flex items-center gap-1.5 truncate text-[15px] font-medium leading-tight",
            isCurrent && "text-primary",
          )}
        >
          <span className="truncate">{track.title}</span>
          <OriginBadge track={track} cached={isCached} compact={compact} />
        </p>
        <p className="truncate text-[13px] leading-tight text-muted-foreground">
          {track.artist} • {track.album}
        </p>
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          toggleFavorite(track.id);
        }}
        aria-label={isFav ? "Remove from favorites" : "Add to favorites"}
        className="hidden h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted-foreground transition hover:text-foreground sm:flex"
      >
        {isFav ? (
          <Heart className="h-4 w-4 fill-primary text-primary" />
        ) : (
          <Heart className="h-4 w-4 opacity-0 transition-opacity group-hover:opacity-60" />
        )}
      </button>
      <span className="w-10 shrink-0 text-right text-[13px] tabular-nums text-muted-foreground">
        {fmtTime(track.duration)}
      </span>
      {menu}
    </div>
  );
}
