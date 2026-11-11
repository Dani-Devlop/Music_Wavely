/**
 * S43 / S50 / S55 — security headers on every response:
 * HSTS (full), CSP (strict in production), nosniff, X-Frame-Options DENY,
 * Referrer-Policy, Permissions-Policy, COOP/CORP, no disclosure headers.
 */
import { NextResponse, type NextRequest } from "next/server";
import { buildCsp } from "@/lib/wavely/server/csp";

export function middleware(request: NextRequest) {
  const res = NextResponse.next();
  const isProduction = process.env.NODE_ENV === "production";

  res.headers.set("strict-transport-security", "max-age=31536000; includeSubDomains; preload");
  res.headers.set("content-security-policy", buildCsp(isProduction));
  res.headers.set("x-content-type-options", "nosniff");
  res.headers.set("x-frame-options", "DENY");
  res.headers.set("referrer-policy", "strict-origin-when-cross-origin");
  res.headers.set("permissions-policy", "camera=(), microphone=(), geolocation=(), payment=()");
  res.headers.set("cross-origin-opener-policy", "same-origin");
  res.headers.set("cross-origin-resource-policy", "same-origin");

  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
