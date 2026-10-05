# mt-ios

Native iOS app (SwiftUI) for [Missing Table](https://github.com/silverbeer/missing-table):
league tables, match scores, team follows, push notifications on score updates.
For club managers, fans and players. Read-only — live scoring stays in the Android app.

Linear: epic **MT iOS App**, repo label `MTI`.

## What's in the app

Login is required (MT is invite-only). Tabs, by role (ported from the web app):

| Tab | Who | What |
|---|---|---|
| **LIVE** | everyone, only while a match is live | live scoreboard + clock, activity stream, chat (Supabase Realtime) |
| **Table** | everyone | standings (GP W D L PTS) · top scorers |
| **Matches** | everyone | week navigation, multi-select divisions (remembered), match view: scorers, cards, timeline, lineups |
| **My Club** | club roles incl. club fans (parents) | club teams → Matches / Roster / Stats (Golden Boot) → player page |
| **Profile** | everyone | player card + season stats and editor (players), follows, notifications, switch account |

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `App/` | SwiftUI app target (`io.silverbeer.mt`). |
| `AppTests/` | App unit tests (run on simulator). |
| `MTKit/` | Swift package: models + API client. No UIKit/SwiftUI — testable with `swift test`. |
| `scripts/` | `test.sh`, `run-sim.sh`, `sim-destination.sh`. |

## Toolchain

- Xcode (from the App Store), then once:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app
  sudo xcodebuild -license accept
  xcodebuild -runFirstLaunch
  xcodebuild -downloadPlatform iOS
  ```
  The standalone Command Line Tools are not enough — they lack the iOS SDK and simulator.
- `brew install xcodegen`

## Run

```bash
swift test --package-path MTKit   # fast: models + client
scripts/test.sh                   # everything, on a simulator
scripts/run-sim.sh                # build + launch in the Simulator
xcodegen generate && open MissingTable.xcodeproj   # work in Xcode
```

## TestFlight

`.github/workflows/testflight.yml` archives a Release build and uploads it to TestFlight, on manual
dispatch or a `v*` tag. Signing is automatic via an App Store Connect API key; the build number is the
workflow run number.

One-time setup (needs the Apple Developer account):
1. App Store Connect → Users and Access → Integrations → App Store Connect API → new key with **App Manager** role.
2. Store it in 1Password `agents` vault, item `mt-ios-asc`, fields `key_id`, `issuer_id`, `team_id`, `private_key` (the `.p8` contents).
3. Create the app record in App Store Connect with bundle id `io.silverbeer.mt`.
4. `scripts/set-release-secrets.sh`
5. `gh workflow run TestFlight`, then add testers in App Store Connect → TestFlight → Internal Testing.
## Debug launch arguments

Debug builds read these (via `scripts/run-sim.sh <args>` or `xcrun simctl launch … <args>`) so screens can be
opened and screenshotted without tapping:

| Argument | Opens |
|---|---|
| `-MTTab live\|table\|matches\|club\|profile` | that tab |
| `-MTTableMode "Top Scorers"` | Table tab mode |
| `-club.selectedId <id> -MTTeam <id> -MTTeamSection roster\|stats` | a team page (My Club tab) |
| `-MTMatch <id>` | a match, as from a notification |
| `-MTLiveMatch <id>` | the LIVE view for a match |
| `-MTStatsCompetitions "League,Flex"` | Stats tab with those competitions selected (with `-MTTeamSection stats`) |
| `-MTEditProfile 1` | the profile editor |

## CI

GitHub Actions runs `swift test` (MTKit) and the app tests on a simulator. While Actions is unavailable
(SB-1254: account spending limit), PRs are merged after running the same checks locally:

```bash
swift test --package-path MTKit && scripts/test.sh
```

## Push notifications

Score updates arrive via APNs for teams you follow (backend: missing-table `notifications/apns_sender.py`).
Permission is requested after the first follow. Debug builds register as `sandbox`, release builds as
`production` — a mismatch makes Apple reject the token and the backend drops it.

Simulate a push in the Simulator (tapping it opens match 1):

```bash
xcrun simctl push booted io.silverbeer.mt push/goal.apns
```
