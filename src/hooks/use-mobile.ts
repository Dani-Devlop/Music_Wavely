import * as React from "react"

const MOBILE_BREAKPOINT = 768
const LAPTOP_BREAKPOINT = 1280

/** Live viewport size (SSR-safe: undefined until mounted). */
export function useViewport() {
  const [vp, setVp] = React.useState<{ width: number; height: number } | undefined>(undefined)

  React.useEffect(() => {
    const read = () => setVp({ width: window.innerWidth, height: window.innerHeight })
    read()
    window.addEventListener("resize", read)
    window.addEventListener("orientationchange", read)
    return () => {
      window.removeEventListener("resize", read)
      window.removeEventListener("orientationchange", read)
    }
  }, [])

  return vp
}

/** ≥1280px in landscape — "laptop landscape = Android-like" (user spec). */
export function useIsBigLandscape() {
  const vp = useViewport()
  if (!vp) return false
  return vp.width >= LAPTOP_BREAKPOINT && vp.width > vp.height
}

/**
 * Wavely adaptive layout (user spec):
 * - < 768px                 → phone layout (Android-like)
 * - 768–1279px              → Spotify shell, any orientation (tablets)
 * - ≥ 1280px in LANDSCAPE   → phone layout too — laptop landscape = Android
 * - ≥ 1280px in PORTRAIT    → Spotify shell with the left side panel (Now playing)
 */
export function useIsMobile() {
  const vp = useViewport()
  if (!vp) return false
  const { width, height } = vp
  return width < MOBILE_BREAKPOINT || (width >= LAPTOP_BREAKPOINT && width > height)
}
