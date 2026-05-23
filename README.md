# Windburst

Native macOS menu bar fan control for **Intel Hackintosh** (VirtualSMC) and **real Intel Macs**. Windburst monitors SMC temperature and fan sensors, displays live metrics in the menu bar, and drives fan curves through either a privileged helper (SMC fans) or [liquidctl](https://github.com/liquidctl/liquidctl) (USB/HID fan controllers and AIOs).

Apple Silicon is not supported in v1.

## Features

- Menu bar dashboard: temperature, CPU sparkline, fan mode dots, optional RPM
- Popover with Swift Charts mini-graphs and per-fan cards
- Multi-point temperature → fan % curve editor with hysteresis
- Presets: Silent, Balanced, Performance (+ custom import/export)
- Privileged helper for SMC manual mode and RPM writes
- **liquidctl** backend for USB/HID devices (Lian Li, Corsair, NZXT, etc.) — no helper required for fan control
- Sensor debug panel for Hackintosh key discovery
- High-temperature notifications, launch at login, dark mode native UI

## Hackintosh prerequisites

Install via OpenCore:

1. **VirtualSMC.kext** — SMC device emulation
2. **SMCProcessor.kext** — CPU temperature sensors (`TC0D`, `TC0P`, `TC*C`, etc.)
3. **SMCSuperIO.kext** — Super I/O fan headers (`F*Ac`, `F*Mn`, `F*Mx`, `F*Md`, `F*Tg`)

Without sensor plugins, Windburst may see fans but no usable temperature keys. Use **Settings → Sensors → Dump SMC Keys** to inspect exposed keys.

## liquidctl backend (USB/HID fans)

Use this when your fans are on a USB controller supported by [liquidctl](https://github.com/liquidctl/liquidctl) instead of SuperIO SMC headers.

1. Install liquidctl: `brew install liquidctl`
2. Open **Settings → General → Fan control backend** and select **liquidctl**
3. Optionally set a custom `liquidctl` path; otherwise Windburst auto-detects Homebrew installs
4. Click **Initialize liquidctl Devices** if your hardware requires first-time setup
5. liquidctl fan channels appear in the menu bar popover and **Settings → Fans**

When liquidctl is selected, **only liquidctl devices are shown** — SMC motherboard fans are hidden. Temperature monitoring and curve input still use VirtualSMC sensors. Fan speed is controlled as a percentage via liquidctl; RPM is read from device status and mapped using per-fan min/max limits (default 0–2400 RPM).

The privileged helper is **not** required for liquidctl fan control, but SMC sensor reads still work without it.

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

## First run — helper approval (SMC backend)

Windburst uses a root helper (`WindburstHelper`) for **SMC fan control**. Skip this section if you use the **liquidctl** backend exclusively.

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

- **SMC backend:** fan writes require manual mode; quitting Windburst restores **automatic** fan control via the helper
- **liquidctl backend:** quitting stops active curves; fan speed remains at the last setting (no SMC-style auto restore)
- Test new curves while monitoring temperatures
- Use per-fan min/max clamps in fan cards before aggressive curves
- High-temp alerts default to 85°C (configurable in Settings)

## Architecture

| Target | Role |
|--------|------|
| **Windburst** | Menu bar SwiftUI app, monitoring, UI, liquidctl control |
| **WindburstHelper** | Root XPC helper: SMC writes, SMC curve loop |
| **WindburstShared** | Models, SMC driver, XPC protocol, curve math, backend types |

**Fan control backends** (Settings → General):

| Backend | Discovery | Control | Curve loop |
|---------|-----------|---------|------------|
| **SMC (VirtualSMC)** | `SMCDriver` + helper | Helper XPC, RPM writes | `WindburstHelper/CurveLoop` |
| **liquidctl** | `LiquidctlClient` CLI | `liquidctl set … speed <percent>` | `Windburst/Engine/LiquidctlCurveLoop` |

Key implementation files: `Windburst/Services/LiquidctlClient.swift`, `Windburst/Engine/LiquidctlCurveLoop.swift`, `WindburstShared/Models/FanControlBackend.swift`.

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
| Helper not connected | Re-register helper; check Background Items approval (SMC backend only) |
| Fans don't change (SMC) | Confirm `F*nMd`/`F*nTg` keys exist; check helper logs in Console |
| liquidctl not available | Install with `brew install liquidctl`; set path in Settings → General |
| No liquidctl fans shown | Run `liquidctl list` in Terminal; initialize devices; select liquidctl backend |
| liquidctl speed wrong | Adjust per-fan min/max RPM in fan card settings (liquidctl uses percent) |
| Build fails on CI/non-Mac | Expected — requires macOS + Xcode |

## References

SMC patterns inspired by open-source projects:

- [ChillMac](https://github.com/idevtim/chillmac) — helper + XPC
- [MacFansControl](https://github.com/beyondthecode-bc/MacFansControl) — curve editor
- [ffan](https://github.com/mohamadlounnas/ffan) — SMC key map
- [VirtualSMC key docs](https://github.com/acidanthera/VirtualSMC)
- [liquidctl](https://github.com/liquidctl/liquidctl) — USB/HID fan and AIO control