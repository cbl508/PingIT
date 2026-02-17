# PingIT

Cross-platform infrastructure monitoring dashboard built with Flutter. Track the health and availability of your servers, databases, routers, and services in real time.

## Features

- **Multi-protocol health checks** - ICMP ping, TCP port connect, and HTTP/HTTPS monitoring
- **Real-time dashboard** - Live status indicators, latency sparklines, and system HUD with pie chart breakdown
- **Network topology** - Interactive drag-and-drop node graph with animated packet flow visualization
- **Smart alerting** - Desktop notifications (Windows, Linux, macOS), email alerts via SMTP, and intelligent parent-based alert suppression
- **Event stream** - Searchable, filterable log of all status change events with timestamps
- **Device management** - Group devices into infrastructure zones, tag for categorization, configure per-device check intervals (5s to 10m)
- **Stability scoring** - Combined uptime + packet loss reliability metric (70/30 weighted)
- **Data portability** - CSV import/export for device configurations and audit telemetry
- **Automatic updates** - Checks GitHub Releases for new versions and applies updates in-place without a separate installer
- **Secure credential storage** - Email passwords stored in OS-backed secure storage (Keychain, Keystore, etc.)
- **Dark/light/system theme** - Material 3 design with custom color scheme

## Supported Platforms

| Platform | Status |
|----------|--------|
| Windows  | Supported (10+) |
| Linux    | Supported |
| macOS    | Supported |
| Web      | Experimental |

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Dart 3.9.2+)
- For Windows builds: Visual Studio 2022 with C++ desktop workload
- For Linux builds: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

### Build & Run

```bash
# Install dependencies
flutter pub get

# Run in development mode
flutter run -d windows   # or linux, macos
```

### Build Release

```bash
# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/

# Linux
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

## CI/CD

GitHub Actions automatically builds Windows and Linux releases when you push a version tag:

```bash
git tag v1.1.0
git push origin v1.1.0
```

The workflow produces `pingit-windows.zip` and `pingit-linux.tar.gz` and attaches them to the GitHub Release. The built-in auto-updater checks these releases and applies updates in-place.

## Project Structure

```
lib/
  main.dart                        # Entry point and theme configuration
  models/
    device_model.dart              # Device, DeviceGroup, StatusHistory models
  screens/
    home_screen.dart               # App shell with navigation and state management
    device_list_screen.dart        # Dashboard overview with status HUD
    topology_screen.dart           # Interactive network topology graph
    logs_screen.dart               # Event stream / audit log
    settings_screen.dart           # App config, email alerts, import/export, updates
    add_device_screen.dart         # Device creation and editing form
    device_details_screen.dart     # Per-device monitoring dashboard
  services/
    ping_service.dart              # ICMP/TCP/HTTP health checking engine
    storage_service.dart           # File-based data persistence
    email_service.dart             # SMTP alert notifications
    notification_service.dart      # OS-level desktop notifications
    alert_service.dart             # Status change logging
    update_service.dart            # GitHub-based automatic updates
```

## Notes

- Email passwords are stored via OS-backed secure storage.
- Deep scan and traceroute features require local system tools (`nmap`, `traceroute`/`tracert`).
- On Windows, ICMP checks use `ping.exe` (no administrator privileges required).

## License

All rights reserved.
