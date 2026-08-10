# Haze

A calm, editorial weather app for iPhone. Big serif numerals, soft skies
that shift with the time of day and the conditions, and accurate forecasts
with no ads and no accounts.

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

## Structure

- `Weather/` — the app: views, view models, services, and the typography
  and material systems (`Views/Components/GlassCard.swift`,
  `Views/Components/VariableBlur.swift`).
- `WeatherWidget/` — the home-screen widgets (small, medium, and a large
  with a 5-day outlook), which fetch on their own schedule.

Typefaces are licensed under the SIL Open Font License —
[FONTLICENSES.md](FONTLICENSES.md).

Designed and built by Aniketh Bandlamudi.
