# MoniTuner

A macOS menu bar app for controlling external monitor brightness on Apple Silicon Macs. Automatically syncs external monitor brightness with your MacBook's built-in display.

## Features

- **MacBook-following brightness** — External monitors mirror MacBook brightness with per-monitor calibration factors
- **Dual DDC backend** — Uses `m1ddc` CLI for USB-C monitors and direct I2C (IOAVService) for HDMI monitors
- **Software dimming fallback** — Gamma-table-based dimming for monitors that don't support DDC writes
- **Keyboard control** — Intercepts brightness keys (F1/F2) and custom hotkeys (Control+F1/F2) to adjust the monitor under the mouse cursor
- **Per-monitor calibration** — One-click calibration from the menu bar to match perceived brightness across different monitors
- **Native OSD** — Shows macOS brightness overlay when adjusting

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon Mac (M1/M2/M3)
- Swift 5.9+
- [`m1ddc`](https://github.com/waydabber/m1ddc) installed at `/opt/homebrew/bin/m1ddc`

## Install m1ddc

```bash
brew install m1ddc
```

## Build & Run

```bash
cd MoniTuner
swift build
swift run
```

To run tests:

```bash
swift test
```

## Usage

1. **Launch** — MoniTuner appears as a menu bar icon
2. **Auto-brightness** — When enabled, external monitors follow MacBook brightness changes automatically
3. **Calibrate** — Set all monitors to your preferred brightness, then click **Calibrate Now** in the menu bar to save the ratios
4. **Manual adjust** — Use brightness keys while hovering over a monitor to adjust it individually. Manual adjustment pauses auto-brightness for 5 minutes

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Brightness Up/Down | Adjust monitor under cursor |
| Control + F1 | Decrease brightness |
| Control + F2 | Increase brightness |

## Permissions

| Permission | Purpose |
|-----------|---------|
| **Accessibility** | Required for keyboard brightness key interception (System Settings > Privacy & Security > Accessibility) |

## Architecture

```
MoniTunerCore (library)
├── DisplayManager      — Display enumeration, mouse routing, DDC dispatch
├── DDCService          — m1ddc CLI wrapper with serial queue
├── Arm64DDC            — Direct I2C DDC/CI via IOAVService (HDMI support)
├── SoftwareDimming     — Gamma-table fallback for non-DDC monitors
├── AutoBrightnessLoop  — MacBook-following brightness with calibration
├── BrightnessEngine    — Brightness curve and step calculations
├── MediaKeyTap         — CGEvent tap for brightness keys
├── AmbientSensor       — IOKit ambient light sensor
└── OSDHelper           — Native macOS brightness OSD

MoniTuner (app)
├── AppDelegate         — Menu bar, settings, calibration persistence
└── Views/              — SwiftUI window with per-monitor brightness cards
```

## Known Limitations

- **HDMI DDC writes** — `m1ddc` cannot write to displays on the built-in HDMI port. MoniTuner uses direct I2C via IOAVService as a fallback, but some monitors may still not respond. In that case, gamma-based software dimming is used automatically.
- **App Store** — Uses private macOS frameworks (`DisplayServices`) and is not suitable for App Store distribution.

## License

MIT
