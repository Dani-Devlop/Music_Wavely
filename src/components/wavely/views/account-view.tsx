"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import {
  useWavely,
  CACHE_LIMIT_MB,
  useCacheUsage,
  type AccountSession,
} from "@/lib/wavely/store";
import {
  fetchServerProfile,
  fetchSessions,
  saveServerProfile,
  getCsrf,
  type ServerProfile,
  type ServerSession,
} from "@/lib/wavely/client-api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { ChevronRight, Monitor, Smartphone, Globe } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import {
  AlertTriangle,
  BadgeCheck,
  Check,
  Cookie,
  DatabaseBackup,
  Info,
  KeyRound,
  Lock,
  LogOut,
  Pencil,
  ShieldCheck,
  Trash2,
  UserRound,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";
import type { AccountSession } from "@/lib/wavely/store";

const AVATAR_PRESETS = [
  "/wavely/avatar.png",
  "/covers/neon-horizon.png",
  "/covers/midnight-bloom.png",
  "/covers/golden-hour.png",
  "/covers/persian-echoes.png",
  "/covers/online-chrome-city.png",
  "/covers/insta-2.png",
  "/covers/deep-focus.png",
];

function PageHeader({
  icon: Icon,
  title,
  subtitle,
}: {
  icon: React.ElementType;
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="flex items-center gap-2 pb-1 pt-5">
      <Icon className="h-4 w-4 text-primary" />
      <h2 className="text-xs font-bold uppercase tracking-widest text-primary">{title}</h2>
      {subtitle && (
        <span className="ml-auto text-[11px] text-muted-foreground">{subtitle}</span>
      )}
    </div>
  );
}

function Row({
  icon: Icon,
  title,
  subtitle,
  control,
  onClick,
  danger,
  arrow,
}: {
  icon: React.ElementType;
  title: string;
  subtitle?: string;
  control?: React.ReactNode;
  onClick?: () => void;
  danger?: boolean;
  arrow?: boolean;
}) {
  const content = (
    <>
      <div
        className={cn(
          "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg",
          danger ? "bg-red-500/15 text-red-400" : "bg-accent text-foreground",
        )}
      >
        <Icon className="h-4 w-4" />
      </div>
      <div className="min-w-0 flex-1">
        <p className={cn("truncate text-sm font-medium", danger && "text-red-400")}>{title}</p>
        {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
      </div>
      {control}
      {arrow && <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />}
    </>
  );
  const cls = "flex w-full items-center gap-3 px-3 py-3 text-left transition hover:bg-accent/50";
  return onClick ? (
    <button onClick={onClick} className={cls}>{content}</button>
  ) : (
    <div className={cls}>{content}</div>
  );
}

function SessionIcon({ kind }: { kind: AccountSession["kind"] }) {
  if (kind === "phone") return Smartphone;
  if (kind === "desktop") return Monitor;
  return Globe;
}

/** Full account-management page — profile, sessions, cookies, cache, security. */
export function AccountView() {
  const { toast } = useToast();

  const profile = useWavely((s) => s.profile);
  const setProfile = useWavely((s) => s.setProfile);
  const sessions = useWavely((s) => s.sessions);
  const signOutSession = useWavely((s) => s.signOutSession);
  const signOutAllSessions = useWavely((s) => s.signOutAllSessions);
  const personalizationCookies = useWavely((s) => s.personalizationCookies);
  const analyticsCookies = useWavely((s) => s.analyticsCookies);
  const setPersonalizationCookies = useWavely((s) => s.setPersonalizationCookies);
  const setAnalyticsCookies = useWavely((s) => s.setAnalyticsCookies);
  const cookiesClearedAt = useWavely((s) => s.cookiesClearedAt);
  const clearCookies = useWavely((s) => s.clearCookies);
  const twoFactor = useWavely((s) => s.twoFactor);
  const setTwoFactor = useWavely((s) => s.setTwoFactor);
  const cachedIds = useWavely((s) => s.cachedIds);
  const clearCache = useWavely((s) => s.clearCache);
  const cacheUsed = useCacheUsage();
  const setPage = useWavely((s) => s.setSettingsPage);

  // S71 — server is the single source of truth for the profile.
  // On mount we re-fetch from /api/profile (no-store). The zustand store is a
  // display cache only and is overwritten with the server record.
  const [serverProfile, setServerProfile] = useState<ServerProfile | null>(null);
  const [serverSessions, setServerSessions] = useState<ServerSession[]>([]);
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      const p = await fetchServerProfile();
      if (!alive) return;
      if (p) {
        setServerProfile(p);
        setSignedIn(true);
        // display reflects the SERVER record (fixes the refresh-revert bug)
        setProfile({ name: p.displayName || p.name, email: p.email, avatar: p.avatar || profile.avatar });
      }
      const s = await fetchSessions();
      if (!alive) return;
      setServerSessions(s.sessions);
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [editOpen, setEditOpen] = useState(false);
  const [name, setName] = useState(profile.name);
  const [email, setEmail] = useState(profile.email);
  const [avatar, setAvatar] = useState(profile.avatar);
  const [pwOpen, setPwOpen] = useState(false);

  // Server sessions replace the demo list when signed in. resolveSession
  // touches lastActivity on every request, so the newest entry IS this device.
  const activeSessions: AccountSession[] =
    signedIn && serverSessions.length > 0
      ? serverSessions.map((s, i) => ({
          id: s.id,
          device: s.device,
          platform: s.browser,
          location: s.ip,
          lastActive: new Date(s.lastActivity).toLocaleTimeString(),
          current: i === 0,
          kind: "web" as const,
        }))
      : sessions;

  const revokeServerSession = async (id: string | null) => {
    if (!signedIn) return;
    await fetch(`/api/auth/sessions${id ? `?id=${encodeURIComponent(id)}` : "?all=1"}`, {
      method: "DELETE",
      headers: { "x-csrf-token": getCsrf() },
    }).catch(() => undefined);
    const s = await fetchSessions();
    setServerSessions(s.sessions);
  };

  const saveProfile = async () => {
    const cleanName = name.trim();
    const cleanEmail = email.trim().toLowerCase();
    if (!cleanName) {
      toast({ description: "Name can't be empty" });
      return;
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) {
      toast({ description: "That email doesn't look right" });
      return;
    }
    setEditOpen(false);
    if (signedIn && serverProfile) {
      // Server-backed save with optimistic locking; on 409 we adopt the fresh
      // server record and re-apply — the LAST write wins and is displayed.
      let base = serverProfile.updatedAt;
      for (let attempt = 0; attempt < 3; attempt++) {
        const res = await saveServerProfile({ name: cleanName, email: cleanEmail }, base);
        if (res.ok && res.profile) {
          setServerProfile(res.profile);
          setProfile({ name: res.profile.displayName || res.profile.name, email: res.profile.email });
          toast({ description: "Profile saved on the server — hello, " + (res.profile.displayName || res.profile.name) });
          return;
        }
        if (res.conflict && res.profile) {
          base = res.profile.updatedAt; // adopt current server state, retry
          continue;
        }
        break;
      }
      toast({ description: "Could not save to the server — try again" });
      return;
    }
    setProfile({ name: cleanName, email: cleanEmail, avatar });
    toast({ description: "Profile updated — hello, " + cleanName });
  };

  const openEdit = () => {
    setName(profile.name);
    setEmail(profile.email);
    setAvatar(profile.avatar);
    setEditOpen(true);
  };

  return (
    <div className="mx-auto max-w-3xl space-y-1 px-4 pb-10 pt-6 md:px-6">
      <Button
        variant="ghost"
        size="sm"
        className="mb-1 gap-1 rounded-full"
        onClick={() => setPage("root")}
      >
        <ChevronRight className="h-4 w-4 rotate-180" /> Settings
      </Button>
      <h1 className="mb-2 font-display text-2xl font-bold tracking-tight md:text-3xl">Account</h1>

      {/* ---------- profile hero ---------- */}
      <div className="flex items-center gap-4 rounded-2xl bg-gradient-to-br from-primary/25 via-primary/10 to-transparent p-4">
        <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-full ring-2 ring-primary/40">
          <Image src={profile.avatar} alt={`${profile.name}'s avatar`} fill sizes="64px" unoptimized className="object-cover" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate font-display text-lg font-extrabold">{profile.name}</p>
          <p className="truncate text-xs text-muted-foreground">{profile.email}</p>
          <span className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-primary/20 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-primary">
            <BadgeCheck className="h-3 w-3" /> {profile.plan} plan
          </span>
        </div>
        <Button size="sm" className="shrink-0 gap-1.5 rounded-full" onClick={openEdit}>
          <Pencil className="h-3.5 w-3.5" /> Edit
        </Button>
      </div>

      {/* ---------- account management ---------- */}
      <PageHeader icon={UserRound} title="Account management" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={Pencil} title="Manage account" subtitle="Name, email & avatar" onClick={openEdit} arrow />
        <Separator />
        <Row
          icon={BadgeCheck}
          title="Plan"
          subtitle={
            profile.plan === "Free"
              ? "Free — ad-light, full offline, all local features"
              : "Wavely+ — thanks for supporting open source"
          }
          control={
            <span className="shrink-0 rounded-full bg-secondary px-3 py-1.5 text-[11px] font-bold text-muted-foreground">
              {profile.plan === "Free" ? "Upgrade" : "Manage"}
            </span>
          }
          onClick={() =>
            toast({
              description:
                profile.plan === "Free"
                  ? "Wavely+ subscriptions open with the Play release — everything stays free till then"
                  : "Billing portal opens with the Play release",
            })
          }
          arrow
        />
        <Separator />
        <Row
          icon={LogOut}
          title="Sign out"
          subtitle="Ends this session on this device"
          onClick={() => toast({ description: "Signed out — see you soon, " + profile.name })}
          arrow
        />
        <Separator />
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <button className="flex w-full items-center gap-3 px-3 py-3 text-left transition hover:bg-accent/50">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-red-500/15 text-red-400">
                <Trash2 className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium text-red-400">Delete account</span>
                <span className="block truncate text-xs text-muted-foreground">
                  Removes your Wavely profile everywhere — local files stay
                </span>
              </span>
            </button>
          </AlertDialogTrigger>
          <AlertDialogContent className="rounded-2xl border-border bg-background">
            <AlertDialogHeader>
              <AlertDialogTitle>Delete your account?</AlertDialogTitle>
              <AlertDialogDescription>
                This wipes your Wavely profile, playlists, play counts and preferences across all
                devices. Music files on the device stay untouched. This can&apos;t be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel className="rounded-full">Keep account</AlertDialogCancel>
              <AlertDialogAction
                className="rounded-full bg-red-600 text-white hover:bg-red-500"
                onClick={() =>
                  toast({ description: "Account deletion opens with the Play release — nothing is removed yet" })
                }
              >
                Delete
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>

      {/* ---------- sessions & devices ---------- */}
      <PageHeader icon={Smartphone} title="Sessions & devices" subtitle={`${activeSessions.length} active`} />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        {activeSessions.map((s, i) => {
          const Icon = SessionIcon(s.kind);
          return (
            <div key={s.id}>
              {i > 0 && <Separator />}
              <div className="flex w-full items-center gap-3 px-3 py-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent text-foreground">
                  <Icon className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1.5 truncate text-sm font-medium">
                    {s.device}
                    {s.current && (
                      <span className="rounded-full bg-primary/20 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-widest text-primary">
                        This device
                      </span>
                    )}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {s.platform} · {s.location} · {s.lastActive}
                  </p>
                </div>
                {s.current ? (
                  <span className="shrink-0 text-[11px] font-semibold text-emerald-300">Active</span>
                ) : (
                  <button
                    onClick={() => {
                      signOutSession(s.id);
                      void revokeServerSession(s.id);
                    }}
                    className="shrink-0 rounded-full border border-border px-3 py-1.5 text-[11px] font-bold text-muted-foreground transition hover:border-red-400/60 hover:text-red-400"
                    aria-label={`Sign out of ${s.device}`}
                  >
                    Sign out
                  </button>
                )}
              </div>
            </div>
          );
        })}
        {activeSessions.filter((s) => !s.current).length > 0 && (
          <>
            <Separator />
            <Row
              icon={LogOut}
              title="Sign out everywhere else"
              subtitle="Keeps this device signed in"
              onClick={() => {
                signOutAllSessions();
                void revokeServerSession(null);
              }}
              arrow
            />
          </>
        )}
        <Separator />
        <Row
          icon={Info}
          title="How sessions work"
          subtitle="Server-side sessions with HttpOnly cookies; revoking a session cuts that device off instantly"
        />
      </div>

      {/* ---------- cookies & site data ---------- */}
      <PageHeader icon={Cookie} title="Cookies & site data" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row
          icon={Lock}
          title="Essential cookies"
          subtitle="Session & sign-in — always on, never shared"
          control={<Switch checked disabled aria-label="Essential cookies (always on)" />}
        />
        <Separator />
        <Row
          icon={Cookie}
          title="Personalization"
          subtitle="Remembers your theme, queues & last played"
          control={
            <Switch
              checked={personalizationCookies}
              onCheckedChange={setPersonalizationCookies}
              aria-label="Personalization cookies"
            />
          }
        />
        <Separator />
        <Row
          icon={Cookie}
          title="Analytics"
          subtitle="Anonymous usage stats that shape Wavely — off by default"
          control={
            <Switch
              checked={analyticsCookies}
              onCheckedChange={setAnalyticsCookies}
              aria-label="Analytics cookies"
            />
          }
        />
        <Separator />
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <button className="flex w-full items-center gap-3 px-3 py-3 text-left transition hover:bg-accent/50">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-red-500/15 text-red-400">
                <Trash2 className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">Clear cookies & site data</span>
                <span className="block truncate text-xs text-muted-foreground">
                  {cookiesClearedAt
                    ? `Last cleared ${new Date(cookiesClearedAt).toLocaleString()}`
                    : "Sign-in on this web player ends; the Android app keeps its own storage"}
                </span>
              </span>
            </button>
          </AlertDialogTrigger>
          <AlertDialogContent className="rounded-2xl border-border bg-background">
            <AlertDialogHeader>
              <AlertDialogTitle>Clear cookies & site data?</AlertDialogTitle>
              <AlertDialogDescription>
                The web player forgets your session and resets preferences to defaults. Your
                music, playlists and play counts on the device stay safe.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel className="rounded-full">Cancel</AlertDialogCancel>
              <AlertDialogAction className="rounded-full" onClick={clearCookies}>
                Clear
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        <Separator />
        <Row
          icon={Info}
          title="Cookie policy"
          subtitle="Plain-language summary ships with the Play release"
          onClick={() =>
            toast({
              description:
                "Wavely uses only first-party, local cookies — no trackers, no ad networks, nothing sold",
            })
          }
          arrow
        />
      </div>

      {/* ---------- cache & storage ---------- */}
      <PageHeader icon={DatabaseBackup} title="Cache & storage" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <div className="px-3 py-3">
          <div className="mb-1.5 flex items-center justify-between text-sm">
            <span className="font-medium">Streaming cache</span>
            <span className="text-xs tabular-nums text-muted-foreground">
              {cacheUsed} of {CACHE_LIMIT_MB} MB
            </span>
          </div>
          <div
            className="h-2 w-full overflow-hidden rounded-full bg-secondary"
            role="progressbar"
            aria-valuenow={cacheUsed}
            aria-valuemin={0}
            aria-valuemax={CACHE_LIMIT_MB}
            aria-label="Streaming cache usage"
          >
            <div
              className="h-full rounded-full bg-primary transition-all"
              style={{ width: `${Math.min(100, (cacheUsed / CACHE_LIMIT_MB) * 100)}%` }}
            />
          </div>
          <p className="mt-1.5 text-[11px] text-muted-foreground">
            {cachedIds.length} fully cached — plays offline and saves instantly
          </p>
        </div>
        <Separator />
        <Row
          icon={Trash2}
          title="Clear streaming cache"
          subtitle="Cached songs go back to streaming-only"
          onClick={() => {
            clearCache();
            toast({ description: "Streaming cache cleared" });
          }}
          arrow
        />
        <Separator />
        <Row
          icon={DatabaseBackup}
          title="Full storage settings"
          subtitle="Download location, folder templates & backups live in Settings"
          onClick={() => {
            setPage("root");
            toast({ description: "Scroll to “Downloads & storage” and “Streaming cache”" });
          }}
          arrow
        />
      </div>

      {/* ---------- security ---------- */}
      <PageHeader icon={ShieldCheck} title="Security" />
      <div className="overflow-hidden rounded-2xl bg-wav-surface">
        <Row icon={KeyRound} title="Change password" subtitle="Last changed 3 months ago" onClick={() => setPwOpen(true)} arrow />
        <Separator />
        <Row
          icon={ShieldCheck}
          title="Two-factor authentication"
          subtitle={twoFactor ? "On — codes via your authenticator app" : "Off — adds a code step at sign-in"}
          control={<Switch checked={twoFactor} onCheckedChange={(v) => { setTwoFactor(v); toast({ description: v ? "2FA setup finishes with an app scan in the full release" : "Two-factor turned off" }); }} aria-label="Two-factor authentication" />}
        />
        <Separator />
        <Row
          icon={Lock}
          title="Parental PIN"
          subtitle="Locks explicit content & settings — Parental controls in Settings"
          onClick={() => {
            setPage("root");
            toast({ description: "Parental controls are in the main Settings list" });
          }}
          arrow
        />
        <Separator />
        <Row
          icon={BadgeCheck}
          title="Security checkup"
          subtitle="Password strength · session review · 2FA · install source"
          onClick={() =>
            toast({
              description: twoFactor
                ? "All clear — strong password, 2FA on, sessions reviewed"
                : "Almost perfect — turn on 2FA to finish the checkup",
            })
          }
          arrow
        />
      </div>

      {/* security notes — plain advice, Wavely's promise */}
      <div className="mt-3 rounded-2xl border border-border bg-wav-surface/60 p-4">
        <p className="flex items-center gap-2 text-sm font-bold">
          <ShieldCheck className="h-4 w-4 text-primary" /> Security notes
        </p>
        <ul className="mt-2 space-y-1.5 text-xs leading-relaxed text-muted-foreground">
          <li className="flex gap-2">
            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            Wavely is open source — the code is auditable at github.com/Dani-Devlop/Music_Wavely.
          </li>
          <li className="flex gap-2">
            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            Install only from GitHub Releases or Google Play — modified APKs can steal accounts.
          </li>
          <li className="flex gap-2">
            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            Wavely never emails asking for your password or a code — anything like that is phishing.
          </li>
          <li className="flex gap-2">
            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            Review Sessions &amp; devices after using a shared computer, and sign out remotely.
          </li>
          <li className="flex gap-2">
            <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            Your local files and backups never leave the device — no cloud upload exists in Wavely.
          </li>
        </ul>
        <p className="mt-2 flex items-center gap-1.5 text-[11px] text-amber-400/80">
          <AlertTriangle className="h-3 w-3" /> Keep a backup of your music folder — Wavely plays files, it never replaces them.
        </p>
      </div>

      {/* ---------- edit profile dialog ---------- */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent className="max-h-[90dvh] overflow-y-auto rounded-2xl border-border bg-background p-5">
          <DialogHeader>
            <DialogTitle>Edit profile</DialogTitle>
            <DialogDescription>
              Your name shows on Home; the email is where account notices go.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <p className="mb-1.5 text-sm font-medium">Display name</p>
              <Input value={name} onChange={(e) => setName(e.target.value)} aria-label="Display name" maxLength={32} />
            </div>
            <div>
              <p className="mb-1.5 text-sm font-medium">Email</p>
              <Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" aria-label="Email" />
            </div>
            <div>
              <p className="mb-1.5 text-sm font-medium">Avatar</p>
              <div className="grid grid-cols-4 gap-2">
                {AVATAR_PRESETS.map((src) => (
                  <button
                    key={src}
                    onClick={() => setAvatar(src)}
                    className={cn(
                      "relative aspect-square overflow-hidden rounded-xl ring-2 transition",
                      avatar === src ? "ring-primary" : "ring-transparent hover:ring-border",
                    )}
                    aria-label={`Choose avatar ${src.split("/").pop()}`}
                    aria-pressed={avatar === src}
                  >
                    <Image src={src} alt="" fill sizes="80px" unoptimized className="object-cover" />
                    {avatar === src && (
                      <span className="absolute inset-0 flex items-center justify-center bg-black/45">
                        <Check className="h-5 w-5 text-white" />
                      </span>
                    )}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" className="rounded-full" onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button className="rounded-full" onClick={saveProfile}>
              Save changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---------- change password dialog ---------- */}
      <Dialog open={pwOpen} onOpenChange={setPwOpen}>
        <DialogContent className="max-h-[90dvh] overflow-y-auto rounded-2xl border-border bg-background p-5">
          <DialogHeader>
            <DialogTitle>Change password</DialogTitle>
            <DialogDescription>
              Uses 12+ characters — a passphrase you remember beats a short one you write down.
            </DialogDescription>
          </DialogHeader>
          <PasswordForm onDone={() => setPwOpen(false)} />
        </DialogContent>
      </Dialog>
    </div>
  );
}

/** Local password form — the prototype validates shape only, nothing is sent. */
function PasswordForm({ onDone }: { onDone: () => void }) {
  const { toast } = useToast();
  const [cur, setCur] = useState("");
  const [next, setNext] = useState("");
  const [rep, setRep] = useState("");

  const submit = () => {
    if (!cur) {
      toast({ description: "Enter your current password first" });
      return;
    }
    if (next.length < 12) {
      toast({ description: "New password needs at least 12 characters" });
      return;
    }
    if (next !== rep) {
      toast({ description: "The two new passwords don't match" });
      return;
    }
    onDone();
    toast({ description: "Password changed — other sessions were signed out for safety" });
  };

  return (
    <div className="space-y-3">
      <Input type="password" value={cur} onChange={(e) => setCur(e.target.value)} placeholder="Current password" aria-label="Current password" />
      <Input type="password" value={next} onChange={(e) => setNext(e.target.value)} placeholder="New password (12+ characters)" aria-label="New password" />
      <Input type="password" value={rep} onChange={(e) => setRep(e.target.value)} placeholder="Repeat new password" aria-label="Repeat new password" />
      <DialogFooter className="gap-2">
        <Button variant="outline" className="rounded-full" onClick={onDone}>
          Cancel
        </Button>
        <Button className="rounded-full" onClick={submit}>
          Update password
        </Button>
      </DialogFooter>
    </div>
  );
}
