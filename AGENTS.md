# AGENTS.md — Windburst

Guidance for AI agents and developers working in this repository.

## Project summary

Windburst is a native **macOS menu bar app** (Swift/SwiftUI) for fan control and system monitoring. Primary target: **Intel Hackintosh** with VirtualSMC; secondary: real Intel Macs. **Apple Silicon is out of scope for v1.**

The app reads SMC temperature/fan sensors, shows live metrics in the menu bar, and drives fans via temperature curves executed by a **privileged root helper**.

## Repository layout

```
Windburst/                 # Menu bar app (SwiftUI, no dock icon)
WindburstHelper/           # Root XPC helper (SMC writes, curve loop)
WindburstShared/           # Shared framework: SMC, models, XPC, curve math
project.yml                # XcodeGen spec — edit this, then regenerate project
scripts/build.sh           # Produces build/Windburst.app
README.md                  # User-facing docs
```

### Key files

| Path | Purpose |
|------|---------|
| `WindburstShared/SMC/SMCConnection.swift` | IOKit SMC bridge; **must use 80-byte `SMCParamStruct`** |
| `WindburstShared/SMC/SMCDriver.swift` | Sensor/fan discovery, read/write wrappers |
| `WindburstShared/SMC/SMCKeyCatalog.swift` | Known VirtualSMC/Intel key names |
| `WindburstShared/SMC/SMCValueParser.swift` | sp78/fpe2/flt type parsing |
| `Windburst/Engine/MonitorEngine.swift` | 2s polling, history buffers, discovery |
| `Windburst/Services/HelperRegistration.swift` | SMAppService + ad-hoc launchctl fallback |
| `Windburst/Services/HelperClient.swift` | XPC client to helper |
| `WindburstHelper/HelperService.swift` | XPC server, SMC writes, curve loop |
| `Windburst/Resources/com.windburst.helper.plist` | Embedded launchd plist for SMAppService |

## Architecture

```
Menu bar app (user session)
  ├─ reads SMC directly for monitoring (no root needed)
  └─ XPC → WindburstHelper (root)
              ├─ fan manual/auto mode, RPM writes
              └─ temperature curve loop (2s interval)

WindburstShared.framework — linked by both app and helper
Mach service: com.windburst.helper
```

- **Monitoring** runs in the app via `SMCDriver` (IOKit `AppleSMC` / `VirtualSMC`).
- **Fan control** requires the helper; app sends curve config over XPC.
- On quit, helper restores all fans to **automatic** mode.

## Build and run

Requires **macOS 13+**, **Xcode 15+**, Swift 5.9.

```bash
./scripts/build.sh              # Release → build/Windburst.app
./scripts/build.sh --config Debug
xcodegen generate               # After editing project.yml
```

Open `Windburst.xcodeproj`, scheme **Windburst**. Ad-hoc signing is configured for local dev (`CODE_SIGN_IDENTITY = "-"`).

Do not commit `build/`, `DerivedData/`, or `xcuserdata/`.

## Helper registration (two paths)

1. **Ad-hoc builds** (`./scripts/build.sh`): "Register Helper" prompts for admin password and installs via `launchctl` to `/Library/LaunchDaemons/`. Does not appear in Background Items.
2. **Signed builds** (Xcode + dev team): uses `SMAppService.daemon(plistName: "com.windburst.helper.plist")`. User approves in System Settings → Background Items.

Implementation: `Windburst/Services/HelperRegistration.swift`.

**Do not** add `SMAuthorizedClients` to helper Info.plist — it conflicts with SMAppService.

Helper binary must live at `Contents/MacOS/WindburstHelper` (set by post-build script in `project.yml`).

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

## Code conventions

- **Swift 5.9**, macOS 13 deployment target.
- UI: SwiftUI + Swift Charts; menu bar via `StatusBarController` (custom `NSStatusItem` for sparklines).
- State: `ObservableObject` / `@Published` / Combine (not `@Observable` — keeps macOS 13 compat).
- Shared types live in **WindburstShared**; avoid duplicating models in app/helper.
- XPC payloads: JSON encoded via `XPCCodec` in `WindburstShared/XPC/` (ObjC-safe `[String: Any]` avoided).
- Prefer extending `SMCKeyCatalog` and `SMCDriver` over ad-hoc IOKit calls in UI code.
- Keep changes minimal and focused; match existing naming and file placement.
- Comments only for non-obvious SMC/protocol behavior — not for self-explanatory UI.

## Testing checklist

On a Hackintosh or Intel Mac with VirtualSMC:

1. `./scripts/build.sh && open build/Windburst.app`
2. Settings → Sensors → Dump SMC Keys shows keys with hex values
3. Menu bar shows temperature + CPU sparkline
4. Register Helper → fan manual/curve control works
5. Quit app → fans return to auto

Console.app: filter `WindburstHelper` for helper logs.

## Out of scope (v1)

- Apple Silicon SMC paths
- App Store / notarization (local dev only)
- iCloud sync, GPU-driven curves, non-Intel hardware

## When editing project structure

1. Change `project.yml`
2. Run `xcodegen generate`
3. Verify all three targets still build: Windburst, WindburstHelper, WindburstShared
4. Confirm helper lands in `Contents/MacOS/WindburstHelper` and launchd plist in `Contents/Library/LaunchDaemons/`

## References

- [README.md](README.md) — user setup and troubleshooting
- [VirtualSMC](https://github.com/acidanthera/VirtualSMC) — SMC key documentation
- [ChillMac](https://github.com/idevtim/chillmac), [MacFansControl](https://github.com/beyondthecode-bc/MacFansControl) — helper/XPC/curve patterns
