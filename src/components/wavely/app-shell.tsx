"use client";

import { useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { useWavely, useCurrentTrack } from "@/lib/wavely/store";
import { PLAYLISTS } from "@/lib/wavely/data";
import { useIsMobile } from "@/hooks/use-mobile";
import { useToast } from "@/hooks/use-toast";
import { WavelyLogo } from "./logo";
import { HomeView } from "./views/home-view";
import { ExploreView } from "./views/explore-view";
import { LibraryView } from "./views/library-view";
import { SearchView } from "./views/search-view";
import { AiChatView } from "./views/ai-chat-view";
import { SettingsView } from "./views/settings-view";
import { EqualizerView } from "./views/equalizer-view";
import { NowPlaying } from "./now-playing";
import { NowPlayingPanel } from "./now-playing-panel";
import { QueueSheet } from "./queue-sheet";
import { TrackActionsSheet } from "./track-actions-sheet";
import { FolderActionsSheet } from "./folder-actions-sheet";
import { SleepTimerDialog } from "./sleep-timer";
import { PlayerBar } from "./player-bar";
import { MiniPlayer } from "./mini-player";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import {
  Bot,
  Compass,
  Home,
  LibraryBig,
  PanelLeftClose,
  PanelLeftOpen,
  Search,
  Settings,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { AppView } from "@/lib/wavely/types";

/* Names stay deliberately distinct: "My Music" = on-device player world,
   "Explore" = streaming discovery world — no Library/Discovery confusion. */
const NAV: { id: AppView; label: string; icon: React.ElementType }[] = [
  { id: "home", label: "Home", icon: Home },
  { id: "explore", label: "Explore", icon: Compass },
  { id: "library", label: "My Music", icon: LibraryBig },
  { id: "search", label: "Search", icon: Search },
  { id: "ai", label: "Wavely AI", icon: Bot },
  { id: "settings", label: "Settings", icon: Settings },
];

/** Advances simulated playback. */
function PlaybackTicker() {
  useEffect(() => {
    const id = setInterval(() => {
      useWavely.getState().tick(0.25);
    }, 250);
    return () => clearInterval(id);
  }, []);
  return null;
}

/** Surfaces store-level notices (offline blocks, download results) as toasts. */
function NoticeBridge() {
  const notice = useWavely((s) => s.playbackNotice);
  const clear = useWavely((s) => s.clearPlaybackNotice);
  const { toast } = useToast();
  useEffect(() => {
    if (notice) {
      toast({ description: notice });
      clear();
    }
  }, [notice, toast, clear]);
  return null;
}

function Sidebar() {
  const view = useWavely((s) => s.view);
  const setView = useWavely((s) => s.setView);
  const setLibraryTab = useWavely((s) => s.setLibraryTab);
  const queues = useWavely((s) => s.queues);
  const selectQueue = useWavely((s) => s.selectQueue);
  const setQueueSheetOpen = useWavely((s) => s.setQueueSheetOpen);
  const collapsed = useWavely((s) => s.sidebarCollapsed);
  const setCollapsed = useWavely((s) => s.setSidebarCollapsed);

  return (
    <aside
      className={cn(
        "wavely-scroll flex h-full shrink-0 flex-col overflow-hidden rounded-2xl bg-sidebar transition-[width] duration-300 ease-in-out",
        collapsed ? "w-[76px]" : "w-64",
      )}
      aria-label="Primary"
    >
      {/* brand + collapse toggle */}
      <div className={cn("flex items-center pt-5", collapsed ? "flex-col gap-3 px-2" : "justify-between px-4")}>
        <button
          className="shrink-0"
          onClick={() => setView("home")}
          aria-label="Wavely home"
        >
          <WavelyLogo size={32} showWordmark={!collapsed} />
        </button>
        <button
          onClick={() => setCollapsed(!collapsed)}
          className={cn(
            "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted-foreground transition hover:bg-accent/60 hover:text-foreground",
            collapsed && "",
          )}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          aria-expanded={!collapsed}
          title={collapsed ? "Expand" : "Collapse"}
        >
          {collapsed ? <PanelLeftOpen className="h-[18px] w-[18px]" /> : <PanelLeftClose className="h-[18px] w-[18px]" />}
        </button>
      </div>

      <nav
        className={cn("mt-5 space-y-1", collapsed && "flex flex-col items-center space-y-1.5")}
        aria-label="Main"
      >
        {NAV.map((n) => {
          const Icon = n.icon;
          const active = view === n.id;
          return (
            <button
              key={n.id}
              onClick={() => setView(n.id)}
              title={n.label}
              className={cn(
                "flex items-center rounded-lg text-sm font-semibold transition-colors",
                collapsed
                  ? cn("h-11 w-11 justify-center", active && "bg-accent/70")
                  : "w-full gap-3.5 px-3 py-2.5",
                active ? "text-foreground" : "text-muted-foreground hover:text-foreground",
              )}
              aria-current={active ? "page" : undefined}
            >
              <Icon className={cn("h-5 w-5 shrink-0", active && "text-primary")} />
              {!collapsed && n.label}
              {!collapsed && n.id === "ai" && (
                <span className="ml-auto rounded-full bg-primary/15 px-1.5 py-0.5 text-[9px] font-bold text-primary">
                  DJ
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {!collapsed && (
        <>
          <div className="my-4 border-t border-border" />

          {/* queues quick access */}
          <p className="px-3 pb-1.5 text-[10px] font-bold uppercase tracking-widest text-muted-foreground">
            My Music — queues
          </p>
          <div className="space-y-0.5">
            {queues.slice(0, 5).map((q) => (
              <button
                key={q.id}
                onClick={() => {
                  selectQueue(q.id);
                  setQueueSheetOpen(true);
                }}
                className="flex w-full items-center gap-2.5 rounded-md px-3 py-1.5 text-left text-[13px] text-muted-foreground transition hover:bg-accent/60 hover:text-foreground"
              >
                <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary/60" />
                <span className="truncate">{q.name}</span>
              </button>
            ))}
          </div>

          <p className="px-3 pb-1.5 pt-4 text-[10px] font-bold uppercase tracking-widest text-muted-foreground">
            Playlists
          </p>
          <div className="space-y-0.5">
            {PLAYLISTS.map((p) => (
              <button
                key={p.id}
                onClick={() => {
                  setLibraryTab("playlists");
                  setView("library");
                }}
                className="flex w-full items-center gap-2.5 rounded-md px-3 py-1.5 text-left text-[13px] text-muted-foreground transition hover:bg-accent/60 hover:text-foreground"
              >
                <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary/60" />
                <span className="truncate">{p.name}</span>
              </button>
            ))}
          </div>

          <div className="mt-auto px-3 pb-2 pt-5">
            <p className="text-[11px] leading-relaxed text-muted-foreground/70">
              Wavely prototype
              <br />
              My Music × Explore
            </p>
          </div>
        </>
      )}
    </aside>
  );
}

function BottomNav() {
  const view = useWavely((s) => s.view);
  const setView = useWavely((s) => s.setView);
  return (
    <nav
      className="glass-strong fixed inset-x-3 bottom-[max(0.75rem,env(safe-area-inset-bottom))] z-40 flex h-14 items-center justify-around rounded-full shadow-[0_10px_36px_rgba(0,0,0,0.65)]"
      aria-label="Main"
    >
      {NAV.map((n) => {
        const Icon = n.icon;
        const active = view === n.id;
        return (
          <button
            key={n.id}
            onClick={() => setView(n.id)}
            className={cn(
              "flex h-10 w-10 items-center justify-center rounded-full transition-all duration-200",
              active
                ? "scale-105 bg-primary text-primary-foreground shadow-md shadow-primary/30"
                : "text-muted-foreground hover:text-foreground",
            )}
            aria-current={active ? "page" : undefined}
          >
            <Icon className="h-5 w-5" />
            <span className="sr-only">{n.label}</span>
          </button>
        );
      })}
    </nav>
  );
}

function ViewContent() {
  const view = useWavely((s) => s.view);
  return (
    <AnimatePresence mode="wait">
      <motion.main
        key={view}
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -8 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
        className="wavely-scroll min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain"
      >
        {view === "home" && <HomeView />}
        {view === "explore" && <ExploreView />}
        {view === "library" && <LibraryView />}
        {view === "search" && <SearchView />}
        {view === "ai" && <AiChatView />}
        {view === "settings" && <SettingsView />}
      </motion.main>
    </AnimatePresence>
  );
}

export function AppShell() {
  const isMobile = useIsMobile();
  const currentTrack = useCurrentTrack();
  const nowPlayingOpen = useWavely((s) => s.nowPlayingOpen);
  const nowPlayingPanelOpen = useWavely((s) => s.nowPlayingPanelOpen);
  const eqOpen = useWavely((s) => s.eqOpen);
  const setEqOpen = useWavely((s) => s.setEqOpen);
  const showMini = !!currentTrack && !nowPlayingOpen;

  /* tablets (768–1023px) share the phone's OS but get the desktop shell —
     Spotify-iPad style. Auto-collapse the sidebar to the icon rail so the
     content keeps room; the user can still expand it manually. */
  useEffect(() => {
    const mql = window.matchMedia("(min-width: 768px) and (max-width: 1023px)");
    const apply = () => {
      if (mql.matches) useWavely.getState().setSidebarCollapsed(true);
    };
    apply();
    mql.addEventListener("change", apply);
    return () => mql.removeEventListener("change", apply);
  }, []);

  return (
    <div
      className={cn(
        "flex h-dvh flex-col overflow-hidden text-foreground",
        isMobile ? "bg-background" : "bg-black md:gap-2",
      )}
    >
      <PlaybackTicker />
      <NoticeBridge />

      {/* desktop/tablet: sidebar (+ optional now-playing panel) + content float as rounded panels on black (Spotify shell) */}
      <div className={cn("flex min-h-0 flex-1", !isMobile && "gap-2 px-2 pt-2")}>
        {!isMobile && <Sidebar />}
        <AnimatePresence>
          {!isMobile && nowPlayingPanelOpen && <NowPlayingPanel key="np-panel" />}
        </AnimatePresence>
        <div
          className={cn(
            // flex + overflow-hidden on every size: on phones without them the
            // content pane grows past the shell and the page can never scroll
            "flex min-w-0 flex-1 overflow-hidden",
            !isMobile && "rounded-2xl bg-background",
          )}
        >
          <ViewContent />
        </div>
      </div>

      {/* bottom of screen: player + nav (mobile) or player bar (desktop) */}
      {isMobile ? (
        <>
          <AnimatePresence>{showMini && <MiniPlayer />}</AnimatePresence>
          <div className={cn("shrink-0", showMini ? "h-[8.75rem]" : "h-[4.5rem]")} aria-hidden="true" />
          <BottomNav />
        </>
      ) : (
        <PlayerBar />
      )}

      {/* overlays */}
      <AnimatePresence>{nowPlayingOpen && <NowPlaying key="np" />}</AnimatePresence>
      <QueueSheet />
      <TrackActionsSheet />
      <FolderActionsSheet />
      <SleepTimerDialog />

      <Dialog open={eqOpen} onOpenChange={setEqOpen}>
        <DialogContent className="max-h-[90dvh] max-w-lg overflow-y-auto rounded-2xl border-border bg-background p-5">
          <DialogTitle className="sr-only">Equalizer</DialogTitle>
          <EqualizerView embedded />
        </DialogContent>
      </Dialog>
    </div>
  );
}
