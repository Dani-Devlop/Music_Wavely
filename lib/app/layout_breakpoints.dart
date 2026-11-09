/// Shared responsive-layout breakpoints (v1.0.2 platform-adaptive UI).
///
/// The owner spec mandates a strict split:
/// - **width < [kDesktopLayoutMinWidth]** → the MOBILE shell: a
///   Musicolet-style Android layout (floating bottom nav, bottom sheets,
///   solid-black now playing).
/// - **width >= [kDesktopLayoutMinWidth]** → the DESKTOP shell: a
///   Spotify-style three-column layout with a glass bottom playbar.
library;

/// Viewport width (logical px) at or above which the DESKTOP shell is
/// used. Below this, the Musicolet-style Android layout is used.
const double kDesktopLayoutMinWidth = 800;

/// True when the given viewport width should render the desktop
/// (Spotify-style) shell.
bool isDesktopLayout(double width) => width >= kDesktopLayoutMinWidth;
