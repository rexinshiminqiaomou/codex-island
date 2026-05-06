# Homebrew tap clones → PostHog (daily cron)

`brew install` against a third-party tap performs a `git clone` of the
tap repo. GitHub exposes 14 days of clone history per repo via
`/repos/{owner}/{tap}/traffic/clones`, after which the data is gone.

This workflow lives in the **homebrew-tap repo**
(`ericjypark/homebrew-tap`), not in the landing repo. It runs daily,
fetches yesterday's clone count, and pushes one PostHog event per
unique cloner so the data is preserved in PostHog Insights alongside
DMG-download events from the landing page.

## One-time setup

1. In `ericjypark/homebrew-tap`, add two repository secrets:
   - `POSTHOG_KEY` — same project key the landing site uses
     (`NEXT_PUBLIC_POSTHOG_KEY`)
   - `POSTHOG_HOST` — `https://us.i.posthog.com` (or the EU host)
2. Add the workflow file below at
   `.github/workflows/clones-to-posthog.yml`.
3. Trigger manually once via the Actions tab to confirm a
   `homebrew_tap_cloned` event lands in PostHog.

## Workflow

```yaml
name: Push Homebrew tap clone stats to PostHog

on:
  schedule:
    - cron: "17 2 * * *" # 02:17 UTC daily — well after midnight everywhere
  workflow_dispatch: {}

permissions:
  contents: read

jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - name: Fetch clone stats and push to PostHog
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          POSTHOG_KEY: ${{ secrets.POSTHOG_KEY }}
          POSTHOG_HOST: ${{ secrets.POSTHOG_HOST }}
        run: |
          set -euo pipefail
          repo="${GITHUB_REPOSITORY}"
          yesterday=$(date -u -d 'yesterday' +%Y-%m-%dT00:00:00Z)
          payload=$(gh api "repos/${repo}/traffic/clones" \
            --jq --arg ts "$yesterday" \
              '.clones[] | select(.timestamp == $ts)')
          if [ -z "$payload" ]; then
            echo "No clone data for $yesterday yet — exiting cleanly."
            exit 0
          fi
          count=$(echo "$payload" | jq '.count')
          uniques=$(echo "$payload" | jq '.uniques')
          for i in $(seq 1 "$count"); do
            curl -fsS -X POST "${POSTHOG_HOST}/i/v0/e/" \
              -H "content-type: application/json" \
              -d "$(jq -n \
                --arg key "$POSTHOG_KEY" \
                --arg ts "$yesterday" \
                --arg repo "$repo" \
                --argjson count "$count" \
                --argjson uniques "$uniques" \
                '{
                  api_key: $key,
                  event: "homebrew_tap_cloned",
                  distinct_id: ("homebrew-cloner-" + $ts + "-" + (now|tostring)),
                  timestamp: $ts,
                  properties: {
                    surface_app: "homebrew_tap",
                    tap_repo: $repo,
                    day: $ts,
                    day_clone_count: $count,
                    day_unique_count: $uniques,
                    "$lib": "homebrew-tap-cron"
                  }
                }')"
          done
          echo "Pushed $count clone events for $yesterday."
```

## Caveats

- **`brew update` also clones the tap.** If a user installed once and
  `brew update`s daily, they show up every day. Treat
  `day_unique_count` as the more honest signal — it's the number of
  unique IPs that hit the tap that day.
- **GitHub returns at most 14 days of history.** This cron preserves
  the data going forward, but **anything older than today minus 14 is
  permanently gone**. Backfill what you can from the current
  `traffic/clones` response on first run if you care.
- Run the cron manually once a day for a week to confirm it doesn't
  double-count, then leave it alone.
