# Changelog

All notable user-facing changes. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); dates are when the
tag was cut.

## [0.1.0] - 2026-05-05

First minor release. The 0.0.x series got the app into a working,
self-updating state. 0.1.0 promotes it to a coherent product: peek + click +
swipe interaction, a real Cost screen, and the polish to back both up.

### Added

- **Cost screen.** Swipe horizontally from the Usage panel (or use the
  indicator dots) to reveal today + month-to-date dollar spend and token
  throughput, aggregated locally from `~/.claude/projects/**/*.jsonl` and
  `~/.codex/sessions/...`. Same data path as `ccusage`. No extra auth.
- **Cost display modes.** Cycle USD / VALUE (vs your subscription baseline) /
  TOKENS / TREND with Cmd-click on the Cost screen, or pin a default in
  Settings → Display → Cost view.
- **Token counting toggle.** Settings → Providers → Tokens picks between
  *All tokens* (input + output + cache_creation + cache_read — ccusage parity)
  and *Input + output* (matches Anthropic's claude.ai stats panel, which
  excludes cache reads). Both totals are computed every scan, so flipping is
  instant.
- **Hover-to-peek silhouette.** Hover the notch and the island widens just
  enough to show each visible provider's 5-hour percentage and reset
  countdown — without committing to expand.
- **On-demand refresh.** Click `synced Xs ago` in the panel header to refetch
  immediately; the next scheduled poll re-arms from there.
- **Cobalt glow + Low Power Mode.** A soft glow around the island signals an
  in-flight refresh. Low Power Mode (Settings → General) hides the
  steady-state glow so it only pulses during active work.
- **Light + dark app icon variants.** The Dock / About icon now adapts to the
  system appearance.
- **Auto-update infrastructure.** Built atop Sparkle 2.9.1 with EdDSA
  signatures and an appcast attached to every GitHub Release. Toggle the
  background check in Settings → Updates, or trigger a manual one with
  *Check now*.
- **Demo mode.** `CODEXISLAND_DEMO=1 ./build/CodexIsland.app/Contents/MacOS/CodexIsland`
  injects narrative-tuned numbers for screen recordings without persisting
  any state.

### Changed

- **Continuous (squircle) corners on the island.** The hand-rolled silhouette
  used circular arcs that produced a visible kink at the tangent point.
  Replaced with `UnevenRoundedRectangle(style: .continuous)` so curvature
  ramps in the way Apple draws the hardware notch and the Dynamic Island.
- **Peek pill no longer collapses on missing reset.** When a provider doesn't
  return an active `resetAt`, the pill shows the window length (`5h`) at
  reduced opacity instead of dropping the separator entirely. Geometry stays
  fixed regardless of which state we're in.
- **Cobalt glow defaults to on.** Previously hidden behind a "developer mode"
  flag; now the steady-state cue everyone sees, with Low Power Mode as the
  opt-out.
- **First-mouse handling.** Clicking the island from another app's focus now
  expands in a single tap instead of needing two.
- **Sparkle key + version hardening.** `CFBundleVersion` is locked to the
  semver in `VERSION` (it had been hardcoded to `"1"`, which made every
  signed update appear *older* than the installed build). The EdDSA public
  key is now embedded in `Info.plist` directly. See `docs/SPARKLE.md` for the
  rotation runbook — TL;DR don't.

### Fixed

- Cost bar chart no longer overflows into the Today/Month header on heavy
  spend days.
- Notch silhouette geometry — height matches the menu bar, not the deeper
  physical notch; bottom edge aligns flush with the menu bar.
- Hover jank when the panel re-renders frequently — overlays now live outside
  `TimelineView` so animation rebuilds don't churn the layout tree.

### Internal

- `MacIsland.costCache.v2` → `v3`. First launch on 0.1.0 backfills the
  billable-tokens column with one fresh local-log scan; existing dollar +
  total-tokens rollups remain valid.
- New `Sources/Cost/` module: `ClaudeLogReader`, `CodexLogReader`,
  `CostStore`, `Pricing`, `TokenEvent`. Pure, side-effect-free aggregation —
  the network surface is still confined to `Sources/Usage/UsageFetcher.swift`.

---

## [0.0.1 - 0.0.10] - bootstrap

The 0.0.x series got CodexIsland from a single-file prototype to a
distributable, self-updating macOS overlay. Highlights, in chronological
order:

- **0.0.1 - 0.0.4.** Initial single-island layout, Claude + Codex usage
  fetchers, expand-on-click panel, Settings window, custom chart styles.
- **0.0.5 - 0.0.6.** Universal binary (arm64 + x86_64), Homebrew Cask
  distribution, Sparkle auto-update plumbing, GitHub Actions release pipeline.
- **0.0.7.** First Cost-view + horizontal-swipe interaction.
- **0.0.8.** Hover-to-peek glance state, click-through outside the
  silhouette, accept-first-mouse, Low Power Mode toggle.
- **0.0.9.** On-demand refresh from the header, notch silhouette geometry
  fixes, cost-tile overflow fix.
- **0.0.10.** Light/dark app icon variants, alpha-aware logo assets, demo
  mode for screen recordings.
