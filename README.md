# Haze

A calm, editorial weather app for iPhone and Mac. Big serif numerals, soft
skies that shift with the time of day and the conditions, and accurate
forecasts with no ads and no accounts.

> **Source-visible, not open source.** This repository is public so the
> code can be read and learned from. All rights are reserved — see
> [LICENSE](LICENSE). Please don't republish the app or derivatives of it.

## Design

Haze is set like a magazine, not a dashboard.

- **Type**: EB Garamond for every word and number, with lining figures
  frozen into the font files (SwiftUI can't enable OpenType features on
  custom fonts, so `pyftfeatfreeze` bakes `lnum` in). Instrument Serif is
  kept for one job: the oversized display temperatures.
- **Sky**: every screen sits on a gradient derived from the current
  conditions and the sun's position — night, dawn, day, dusk — deepened by
  a constant scrim so white type always reads.
- **Material**: one signature glass surface (`GlassSurface`) shared by
  every control — real backdrop blur clipped to the shape, a light frost,
  a diagonal sheen, a specular top glow, an eased bottom shade, and a
  wrap-around rim.
- **Motion & haptics**: a six-page onboarding with choreographed haptic
  beats, a scrubbable radar timeline, and reduce-motion/contrast/
  transparency accessibility settings that actually change the rendering.

## Data

- **Forecast**: [Open-Meteo](https://open-meteo.com) — a blend of the
  ECMWF, GFS, and ICON models.
- **Current conditions**: the nearest NWS station observation overrides
  the modeled "now" when it reports active weather (US), so a
  thunderstorm overhead never shows as "partly cloudy".
- **Radar**: Iowa Environmental Mesonet NEXRAD composites for observed
  frames and HRRR for the forecast ahead (US), RainViewer elsewhere.
- **Air quality**: Open-Meteo's air-quality API (US AQI).

## The Mac app

The `HazeMac` target builds the same app for macOS from the same `Weather/`
sources, with the handful of UIKit-bound files carrying an AppKit branch
(the glass backdrop, chart scrubbing, haptics, the radar map). What's Mac
about it lives in `HazeMac/`:

- One sky across the whole window, no system toolbar or sidebar material:
  the locations column and the floating controls are drawn in the app's
  own glass and serif.
- On a wide window the page becomes a spread: the hero holds the left
  page while the cards scroll on the right. Narrow it and it folds back
  into the iPhone's single column.
- The radar opens in its own window, Settings under ⌘,, and the current
  temperature sits in the menu bar with a small page beneath it.
- Menu commands with keys for everything: ⌘F to find a city, ⌘1 to ⌘9 to
  jump between saved places, ⌘R to refresh, ⇧⌘R for the radar, ⇧⌘S for
  the sun page, ⌃⌘S to fold the locations column.
- Charts read under the pointer; rows lift on hover; Escape closes sheets.

## Structure

- `Weather/` — the app: views, view models, services, and the typography
  and material systems (`Views/Components/GlassCard.swift`,
  `Views/Components/VariableBlur.swift`). Shared by the iPhone and Mac
  targets; `WeatherApp.swift` and `ContentView.swift` are iPhone-only.
- `HazeMac/` — the Mac app's entry point, window layout, locations column,
  menu commands, and menu bar extra.
- `WeatherWidget/` — the home-screen widgets (small, medium, and a large
  with a 5-day outlook), which fetch on their own schedule.

Typefaces are licensed under the SIL Open Font License —
[FONTLICENSES.md](FONTLICENSES.md).

Designed and built by Aniketh Bandlamudi.
