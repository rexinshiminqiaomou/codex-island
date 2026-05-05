# Changelog

User-facing changes per release. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); dates are when the
tag was cut.

## [0.1.0] - 2026-05-05

Three changes on top of the 0.0.10 baseline. The minor-version bump signals
that the 0.0.x bootstrap series is over — not that this single release is
big. Per-tag detail for the 0.0.x series lives on the
[GitHub Releases page](https://github.com/ericjypark/codex-island/releases).

### Added

- **Token counting toggle.** Settings → Providers → Tokens picks between
  *All tokens* (input + output + cache_creation + cache_read — ccusage
  parity, the prior default and the only mode in 0.0.x) and *Input + output*
  (matches Anthropic's claude.ai stats panel, which excludes cache reads).
  Both totals are computed every scan and cached, so flipping the segment
  is instant — no rescan.
- **`CHANGELOG.md`.** Going forward, each release ships with a curated
  user-facing changelog in this file.

### Changed

- **Continuous (squircle) corners on the island silhouette.** Replaces the
  hand-rolled circular-arc + straight-line path with
  `UnevenRoundedRectangle(style: .continuous)`, eliminating the small kink
  at the tangent point that was visible against the hardware notch.
- **Peek pill always shows window context.** When a provider didn't return
  an active `resetAt`, the pill used to drop the separator and render bare
  percentage — making the layout shift between hovers. It now always renders
  `<percent> · <label>`. With an active countdown the label is the live time
  remaining at full opacity; otherwise it falls back to the window length
  (`5h`) at reduced opacity, so countdown vs. passive label stays visually
  distinct without changing geometry.

### Internal

- `MacIsland.costCache.v2` → `v3`. First launch on 0.1.0 backfills the
  billable-tokens column with one fresh local-log scan; existing dollar +
  total-tokens rollups remain valid.
