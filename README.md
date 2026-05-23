# Windburst

Native macOS menu bar fan control for **Intel Hackintosh** (VirtualSMC) and **real Intel Macs**. Windburst monitors SMC temperature and fan sensors, displays live metrics in the menu bar, and drives fan curves through a privileged helper.

Apple Silicon is not supported in v1.

## Features

- Menu bar dashboard: temperature, CPU sparkline, fan mode dots, optional RPM
- Popover with Swift Charts mini-graphs and per-fan cards
- Multi-point temperature → fan % curve editor with hysteresis
- Presets: Silent, Balanced, Performance (+ custom import/export)
- Privileged helper for SMC manual mode and RPM writes
- Sensor debug panel for Hackintosh key discovery
- High-temperature notifications, launch at login, dark mode native UI

## Hackintosh prerequisites

Install via OpenCore:

1. **VirtualSMC.kext** — SMC device emulation
2. **SMCProcessor.kext** — CPU temperature sensors (`TC0D`, `TC0P`, `TC*C`, etc.)
3. **SMCSuperIO.kext** — Super I/O fan headers (`F*Ac`, `F*Mn`, `F*Mx`, `F*Md`, `F*Tg`)

Without sensor plugins, Windburst may see fans but no usable temperature keys. Use **Settings → Sensors → Dump SMC Keys** to inspect exposed keys.

## Build

Requirements:

- macOS 13 Ventura or later
- Xcode 15+ (Swift 5.9+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional if `Windburst.xcodeproj` already exists)

```bash
cd /Users/nico/Development/Windburst
xcodegen generate
open Windburst.xcodeproj
```

Select the **Windburst** scheme and build (`⌘B`). Run (`⌘R`) from Xcode.

Command-line build:

```bash
./scripts/build.sh
```

This produces `build/Windburst.app` (Release by default). Options: `--config Debug`, `--clean`, `--output dist`.

Manual xcodebuild:

```bash
xcodebuild -scheme Windburst -configuration Debug -destination 'platform=macOS' build
```

Ad-hoc signing is configured for local development (`CODE_SIGN_IDENTITY = "-"`). No notarization is required for personal use.

## First run — helper approval

Windburst uses a root helper (`WindburstHelper`) for fan control.

1. Build Windburst (`./scripts/build.sh` or Xcode)
2. Launch Windburst and click **Register Helper**
3. **Ad-hoc builds** (from `./scripts/build.sh`): macOS prompts for your administrator password and installs the helper via `launchd`. No Background Items entry is created.
4. **Signed builds** (Xcode with a development team): registration uses `SMAppService`. Approve **WindburstHelper** under **System Settings → General → Login Items & Extensions → Background Items**.

The helper exposes Mach service `com.windburst.helper` for XPC fan control.

## Choosing a temperature sensor

1. Open **Settings → Sensors**
2. Pick the sensor that tracks load sensibly (often `TC0D` or `TC0P` on Hackintosh)
3. Use the debug table to compare live values while stressing the CPU

Default selection prefers known CPU keys from the VirtualSMC/Intel catalog.

## Safety

- Fan writes require manual mode; quitting Windburst restores **automatic** fan control
- Test new curves while monitoring temperatures
- Use per-fan min/max clamps in fan cards before aggressive curves
- High-temp alerts default to 85°C (configurable in Settings)

## Architecture

| Target | Role |
|--------|------|
| **Windburst** | Menu bar SwiftUI app, monitoring, UI |
| **WindburstHelper** | Root XPC helper: SMC writes, curve loop |
| **WindburstShared** | Models, SMC driver, XPC protocol, curve math |

```
Windburst.app
├── Contents/MacOS/Windburst
├── Contents/Frameworks/WindburstShared.framework
├── Contents/Resources/WindburstHelper
└── Contents/Library/LaunchDaemons/com.windburst.helper.plist
```

Polling interval: **2 seconds** for UI and curve execution.

## Presets import/export

**Settings → Presets → Export/Import** saves custom curves as JSON (`WindburstPresets.json`). Built-in presets are not exported.

## Troubleshooting

| Issue | Action |
|-------|--------|
| No temperatures | Verify VirtualSMC sensor kexts; dump SMC keys |
| Helper not connected | Re-register helper; check Background Items approval |
| Fans don't change | Confirm `F*nMd`/`F*nTg` keys exist; check helper logs in Console |
| Build fails on CI/non-Mac | Expected — requires macOS + Xcode |

## References

SMC patterns inspired by open-source projects:

- [ChillMac](https://github.com/idevtim/chillmac) — helper + XPC
- [MacFansControl](https://github.com/beyondthecode-bc/MacFansControl) — curve editor
- [ffan](https://github.com/mohamadlounnas/ffan) — SMC key map
- [VirtualSMC key docs](https://github.com/acidanthera/VirtualSMC)

## License

Personal / local dev use. No warranty — monitor hardware temperatures when testing fan curves.
