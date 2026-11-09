import type { Metadata, Viewport } from "next";
import { Inter, Sora } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

const sora = Sora({
  variable: "--font-sora",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Wavely — Your Music, Your Way",
  description:
    "A free, open-source music player with local library, synced lyrics, multiple queues, AI DJ and legal online sources. Dark, fast, beautiful.",
  keywords: ["Wavely", "music player", "local music", "queue", "lyrics", "AI DJ"],
  authors: [{ name: "Wavely" }],
  icons: {
    icon: "/wavely-icon.svg",
  },
  openGraph: {
    title: "Wavely — Your Music, Your Way",
    description: "Local-first music player with a modern dark UI",
    siteName: "Wavely",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0c0a",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <body
        className={`${inter.variable} ${sora.variable} antialiased bg-background text-foreground`}
      >
        {children}
        <Toaster />
      </body>
    </html>
  );
}
