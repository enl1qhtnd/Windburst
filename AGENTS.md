# AGENTS.md — Windburst

Guidance for AI agents and developers working in this repository.

## Project summary

Windburst is a native **macOS menu bar app** (Swift/SwiftUI) for fan control and system monitoring. Primary target: **Intel Hackintosh** with VirtualSMC; secondary: real Intel Macs. **Apple Silicon is out of scope for v1.**

The app reads SMC temperature/fan sensors, shows live metrics in the menu bar, and drives fans via temperature curves. Fan control uses either a **privileged root helper** (SMC/VirtualSMC fans) or **liquidctl** (USB/HID devices such as AIO pumps and fan controllers).

## Working in this repo

**Do**

- Edit `project.yml` and run `xcodegen generate` when adding/removing files or targets.
- Put shared models, SMC code, XPC protocol, and curve math in **WindburstShared**.
- Route fan control through `CurveEngineService` — it branches on `FanControlBackend`.
- Extend `SMCKeyCatalog` / `SMCDriver` instead of ad-hoc IOKit in UI code.
- Keep changes minimal; match existing naming, file placement, and `@MainActor` patterns.
- Verify SMC struct layout if touching `SMCConnection.swift` (80-byte stride, `data8` at offset 42).

**Do not**

- Add `SMAuthorizedClients` to helper Info.plist (conflicts with SMAppService).
- Route liquidctl fans through the helper or `SMCDriver` writes.
- Mix fan backends in one session — when liquidctl is selected, SMC fan discovery is skipped.
- Change `SMCParamStruct` layout without verifying offsets.
- Commit `build/`, `DerivedData/`, or `xcuserdata/`.
- Use `@Observable` — project stays on `ObservableObject` / `@Published` for macOS 13 compat.

**Common tasks**

| Task | Where to look |
|------|---------------|
| Add SMC sensor key | `WindburstShared/SMC/SMCKeyCatalog.swift` |
| Change polling / history | `MonitorEngine.swift`, `MetricChartScale.swift` |
| Fan manual / curve control | `CurveEngineService` → helper or `LiquidctlCurveLoop` |
| Settings persistence | `SettingsStore`, `AppSettings` |
| Per-fan prefs (min/max, hidden, curve) | `FanPreferencesStore`, `FanPreferences` |
| Menu bar UI | `StatusBarController`, `SparklineView` |
| Helper install path | `HelperRegistration.swift` |

## Repository layout

```
Windburst/                 # Menu bar app (SwiftUI, accessory / no dock icon)
  App/                     # WindburstApp, AppState, AppDelegate lifecycle
  Engine/                  # MonitorEngine, CurveEngineService, LiquidctlCurveLoop
  Services/                # HelperClient, LiquidctlClient, stores, alerts
  StatusBar/               # NSStatusItem + sparkline rendering
  Views/                   # Popover, Settings, curve editor, fan cards
  Utilities/               # SparklineView, PresetTheme
  Resources/               # Info.plist, entitlements, helper launchd plist
WindburstHelper/           # Root XPC helper (SMC writes, SMC curve loop)
  HelperService.swift      # XPC server
  FanController.swift      # Manual/auto mode, RPM writes
  CurveLoop.swift          # 2s temperature curve loop (SMC backend)
WindburstShared/           # Shared framework
  SMC/                     # IOKit bridge, driver, key catalog, value parsing
  Models/                  # Fan, Sensor, FanCurve, AppSettings, backends
  Engine/                  # FanCurveInterpolator, RingBuffer, MetricChartScale
  XPC/                     # WindburstXPCProtocol, XPCCodec
project.yml                # XcodeGen spec — edit this, then regenerate project
scripts/build.sh           # Produces build/Windburst.app
scripts/generate-app-icon.swift
README.md                  # User-facing docs
```

### App bundle layout

Post-build scripts in `project.yml` produce:

```
Windburst.app
├── Contents/MacOS/Windburst
├── Contents/MacOS/WindburstHelper      # embedded by post-build script
├── Contents/Frameworks/WindburstShared.framework
└── Contents/Library/LaunchDaemons/com.windburst.helper.plist
```

Mach service: `com.windburst.helper`

## Architecture

```
Menu bar app (user session)
  ├─ reads SMC directly for monitoring (no root needed)
  ├─ fan backend: SMC (default)
  │    └─ XPC → WindburstHelper (root)
  │              ├─ FanController — manual/auto mode, RPM writes
  │              └─ CurveLoop — temperature curve loop (2s interval)
  └─ fan backend: liquidctl
       ├─ LiquidctlClient — subprocess to liquidctl CLI (no root)
       └─ LiquidctlCurveLoop — temperature curve loop in app (2s interval)

WindburstShared.framework — linked by both app and helper
```

### Fan control backends

Selected in Settings → General → **Fan control backend**.

| Backend | Discovery | Control | Curve loop | Helper required |
|---------|-----------|---------|------------|-----------------|
| **SMC (VirtualSMC)** | `SMCDriver` + helper XPC | Helper XPC, RPM writes | `WindburstHelper/CurveLoop` | Yes |
| **liquidctl** | `LiquidctlClient` CLI | `liquidctl set … speed <percent>` | `Windburst/Engine/LiquidctlCurveLoop` | No |

- **Monitoring** runs in the app via `SMCDriver` (IOKit `AppleSMC` / `VirtualSMC`).
- When liquidctl is active, **only liquidctl fan channels are shown**; SMC fans are hidden. Temperature curves still read VirtualSMC sensors for control input.
- On quit: SMC backend restores all fans to **automatic** mode via helper; liquidctl backend stops active curves only (last speed remains).

### Startup and lifecycle

1. `WindburstApp` sets `.accessory` activation policy (menu bar only, no dock icon).
2. `AppState.bootstrap()` creates `StatusBarController`, starts `MonitorEngine`, requests notification auth.
3. Helper connects if registered (`HelperClient`); discovery runs; assigned curves apply.
4. `applicationWillTerminate` calls `helperClient.shutdown()` (helper restores SMC fans to auto).

Central wiring lives in `AppState` — it owns `MonitorEngine`, stores, `HelperClient`, `LiquidctlClient`, and `CurveEngineService`.

### Key files

| Path | Purpose |
|------|---------|
| `Windburst/App/AppState.swift` | Central app state, fan override/curve orchestration, window management |
| `Windburst/App/WindburstApp.swift` | App entry, `AppDelegate`, quit → helper shutdown |
| `Windburst/Engine/MonitorEngine.swift` | Polling, history buffers, SMC/liquidctl fan discovery |
| `Windburst/Engine/CurveEngine.swift` | `CurveEngineService` — routes control to helper or liquidctl |
| `Windburst/Engine/LiquidctlCurveLoop.swift` | In-app temperature curve loop for liquidctl fans |
| `Windburst/Services/SettingsStore.swift` | `SettingsStore`, `PresetStore` — JSON persistence |
| `Windburst/Services/FanPreferencesStore.swift` | Per-fan min/max, hidden, assigned curve |
| `Windburst/Services/HelperClient.swift` | XPC client to helper |
| `Windburst/Services/HelperRegistration.swift` | SMAppService + ad-hoc launchctl fallback |
| `Windburst/Services/LiquidctlClient.swift` | liquidctl CLI wrapper: list/status/set speed |
| `Windburst/Services/AlertManager.swift` | High-temperature UserNotifications |
| `Windburst/StatusBar/StatusBarController.swift` | Menu bar item, popover, sparkline |
| `WindburstShared/SMC/SMCConnection.swift` | IOKit SMC bridge; **must use 80-byte `SMCParamStruct`** |
| `WindburstShared/SMC/SMCDriver.swift` | Sensor/fan discovery, read/write wrappers |
| `WindburstShared/SMC/SMCKeyCatalog.swift` | Known VirtualSMC/Intel key names |
| `WindburstShared/SMC/SMCValueParser.swift` | sp78/fpe2/flt type parsing |
| `WindburstShared/Models/FanControlBackend.swift` | `FanControlBackend`, `LiquidctlIdentity` |
| `WindburstShared/Models/AppSettings.swift` | User settings model (refresh interval, backend, alerts) |
| `WindburstShared/Engine/FanCurveInterpolator.swift` | Temperature → fan % interpolation with hysteresis |
| `WindburstShared/XPC/WindburstXPCProtocol.swift` | XPC protocol, `XPCCodec`, Mach service constants |
| `WindburstHelper/HelperService.swift` | XPC server, SMC writes, delegates to `CurveLoop` |
| `WindburstHelper/FanController.swift` | SMC fan mode and RPM control |
| `WindburstHelper/CurveLoop.swift` | Helper-side curve execution loop |
| `Windburst/Resources/com.windburst.helper.plist` | Embedded launchd plist for SMAppService |

## Persistence

All user data is stored under `~/Library/Application Support/Windburst/`:

| File | Store | Contents |
|------|-------|----------|
| `settings.json` | `SettingsStore` | `AppSettings` (sensor, backend, refresh interval, alerts, etc.) |
| `presets.json` | `PresetStore` | Custom fan presets (built-ins are seeded, not persisted) |
| `fan-preferences.json` | `FanPreferencesStore` | Per-fan min/max RPM, hidden flag, assigned curve ID |

Preset import/export (Settings → Presets) uses `WindburstPresets.json` as the interchange format.

## Build and run

Requires **macOS 13+**, **Xcode 15+**, Swift 5.9. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is optional if `Windburst.xcodeproj` already exists; `scripts/build.sh` auto-runs `xcodegen generate` when available.

```bash
./scripts/build.sh                    # Release → build/Windburst.app
./scripts/build.sh --config Debug
./scripts/build.sh --clean --output dist
xcodegen generate                     # After editing project.yml
```

Open `Windburst.xcodeproj`, scheme **Windburst**. Ad-hoc signing is configured for local dev (`CODE_SIGN_IDENTITY = "-"`).

Manual xcodebuild:

```bash
xcodebuild -scheme Windburst -configuration Debug -destination 'platform=macOS' build
```

Polling interval defaults to **2 seconds** (`AppSettings.refreshIntervalSeconds`); configurable in Settings (1, 2, 5, 10, 30 s). Chart history window: **3 minutes** (`MetricChartScale.historyWindowSeconds`).

## Helper registration (two paths)

1. **Ad-hoc builds** (`./scripts/build.sh`): "Register Helper" prompts for admin password and installs via `launchctl` to `/Library/LaunchDaemons/`. Does not appear in Background Items.
2. **Signed builds** (Xcode + dev team): uses `SMAppService.daemon(plistName: "com.windburst.helper.plist")`. User approves in System Settings → Background Items.

Implementation: `Windburst/Services/HelperRegistration.swift`. `bundledHelperURL()` checks `Contents/MacOS/WindburstHelper` first, then legacy `Contents/Resources/WindburstHelper`.

**Do not** add `SMAuthorizedClients` to helper Info.plist — it conflicts with SMAppService.

## SMC / IOKit — critical constraints

This is the most failure-prone area. Follow strictly:

1. **Struct size must be exactly 80 bytes**, matching [SMCKit](https://github.com/beltex/SMCKit) layout.
2. **`data8` (command selector) is at offset 42**, not 40. There is a `UInt16 padding` field before `result`.
3. Use nested `keyInfo.dataSize` / `keyInfo.dataType` — not flat offsets.
4. **Key index enumeration** (`getKeyFromIndex`): success = IOKit `KERN_SUCCESS` only; do **not** check `output.result`.
5. **Key reads**: two-step flow — `getKeyInfo` (selector 9), then `readKey` (selector 5). Check `output.result == 0` only on the read step.
6. **Four-char keys**: big-endian packing — `string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }`.
7. Open via `IOServiceMatching("AppleSMC")` first, then `"VirtualSMC"`.
8. Do not change struct layout without verifying `MemoryLayout<SMCParamStruct>.stride == 80` and `offset(of: \.data8) == 42`.

Reference: VirtualSMC `Tools/smcread/smcread.c`, beltex/SMCKit `SMCParamStruct`.

## Hackintosh sensor keys

Expected kexts: VirtualSMC, SMCProcessor (temps), SMCSuperIO (fans).

Common keys: `TC0D`, `TC0P`, `TC*C` (CPU), `F*nAc` (fan RPM), `F*nMd` (mode), `F*nTg` (target). SuperIO may also expose `Tm0P`, `TN0P`, etc.

Settings → Sensors → **Dump SMC Keys** reads locally (no helper required). Use for debugging key discovery.

## liquidctl backend

Use when fans are on USB/HID controllers supported by [liquidctl](https://github.com/liquidctl/liquidctl) (e.g. Lian Li, Corsair Commander, NZXT Kraken) rather than SuperIO SMC keys.

**Settings:** General → **Fan control backend** → `liquidctl`. Optional custom path; otherwise auto-detects `/opt/homebrew/bin/liquidctl`, `/usr/local/bin/liquidctl`, or `$PATH`.

**Discovery:** `LiquidctlClient` runs `liquidctl --json list` and `liquidctl --json -n <index> status`. Fan channels are parsed from status keys like `Fan 1 speed` → channel `fan1`. Each fan gets a stable index via `LiquidctlIdentity.fanIndex(deviceIndex:channel:)` (base `10000 + deviceIndex * 100 + channelNumber`) and a `LiquidctlIdentity` stored on the `Fan` model.

**Control:** `liquidctl -n <deviceIndex> set <channel> speed <percent>`. liquidctl uses **percentage**, not RPM. UI sliders map RPM ↔ percent using per-fan min/max (defaults 0–2400 RPM). Do not route liquidctl fans through the helper or `SMCDriver` writes.

**Curves:** `LiquidctlCurveLoop` (in app, not helper) polls every 2s, reads temperature from SMC sensors via a callback wired in `MonitorEngine`, interpolates curve percent with `FanCurveInterpolator`, and calls `LiquidctlClient.setSpeedPercent`. `CurveEngineService` branches on `FanControlBackend`.

**Initialize:** Some devices need `liquidctl initialize all` once — exposed in Settings when liquidctl backend is selected.

## Code conventions

- **Swift 5.9**, macOS 13 deployment target.
- UI: SwiftUI + Swift Charts; menu bar via `StatusBarController` (custom `NSStatusItem` for sparklines).
- State: `ObservableObject` / `@Published` / Combine (not `@Observable`).
- Shared types live in **WindburstShared**; avoid duplicating models in app/helper.
- XPC payloads: JSON encoded via `XPCCodec` in `WindburstShared/XPC/` (ObjC-safe `[String: Any]` avoided).
- `@MainActor` on app-side engines, stores, and UI coordinators.
- Comments only for non-obvious SMC/protocol behavior — not for self-explanatory UI.

## Safety

- **SMC backend:** fan writes require manual mode; quitting Windburst restores **automatic** fan control via the helper.
- **liquidctl backend:** quitting stops active curves; fan speed remains at the last setting (no SMC-style auto restore).
- High-temp alerts default to 85°C (`AppSettings.highTempThreshold`); debounced in `AlertManager`.
- `safeStartupEnabled` avoids applying aggressive curves immediately on launch.

## Testing checklist

On a Hackintosh or Intel Mac with VirtualSMC:

1. `./scripts/build.sh && open build/Windburst.app`
2. Settings → Sensors → Dump SMC Keys shows keys with hex values
3. Menu bar shows temperature + CPU sparkline
4. Register Helper → fan manual/curve control works (SMC backend)
5. Quit app → fans return to auto

**liquidctl backend** (USB/HID fan controllers):

1. `brew install liquidctl`
2. Settings → General → Fan control backend → **liquidctl**
3. Initialize devices if needed; popover shows liquidctl fan channels only
4. Manual override and presets drive speed via liquidctl (helper not required for fan control)
5. Quit app → active liquidctl curves stop (no SMC auto-restore)

Console.app: filter `WindburstHelper` for helper logs.

## Troubleshooting

| Issue | Action |
|-------|--------|
| No temperatures | Verify VirtualSMC sensor kexts; dump SMC keys |
| Helper not connected | Re-register helper; check Background Items approval (SMC backend only) |
| Fans don't change (SMC) | Confirm `F*nMd`/`F*nTg` keys exist; check helper logs in Console |
| liquidctl not available | `brew install liquidctl`; set path in Settings → General |
| No liquidctl fans shown | Run `liquidctl list` in Terminal; initialize devices; select liquidctl backend |
| liquidctl speed wrong | Adjust per-fan min/max RPM in fan card settings (liquidctl uses percent) |
| Build fails on CI/non-Mac | Expected — requires macOS + Xcode |

## Out of scope (v1)

- Apple Silicon SMC paths
- App Store / notarization (local dev only)
- iCloud sync, GPU-driven curves, non-Intel hardware

## When editing project structure

1. Change `project.yml`
2. Run `xcodegen generate`
3. Verify all three targets still build: Windburst, WindburstHelper, WindburstShared
4. Confirm helper lands at `Contents/MacOS/WindburstHelper` and launchd plist at `Contents/Library/LaunchDaemons/`

## References

- [README.md](README.md) — user setup and troubleshooting
- [VirtualSMC](https://github.com/acidanthera/VirtualSMC) — SMC key documentation
- [liquidctl](https://github.com/liquidctl/liquidctl) — USB/HID device control CLI
- [ChillMac](https://github.com/idevtim/chillmac), [MacFansControl](https://github.com/beyondthecode-bc/MacFansControl) — helper/XPC/curve patterns
- [ffan](https://github.com/mohamadlounnas/ffan) — SMC key map
