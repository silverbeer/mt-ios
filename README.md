# mt-ios

Native iOS app (SwiftUI) for [Missing Table](https://github.com/silverbeer/missing-table):
league tables, match scores, team follows, push notifications on score updates.
For club managers, fans and players. Read-only — live scoring stays in the Android app.

Linear: epic **MT iOS App**, repo label `MTI`.

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
