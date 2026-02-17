# PingIT

Cross-platform infrastructure monitoring dashboard built with Flutter. Track the health and availability of your servers, databases, routers, and services in real time.

## Features

### Monitoring
- **Multi-protocol health checks** — ICMP ping, TCP port connect, and HTTP/HTTPS monitoring
- **Configurable polling** — Per-device check intervals from 5 seconds to 10 minutes
- **Failure thresholds** — Set consecutive failure count before triggering offline alerts (reduces false positives)
- **Exponential backoff** — Automatic poll rate reduction on repeated failures (up to 300s) to avoid hammering unreachable hosts
- **Latency & packet loss thresholds** — Mark devices as degraded when user-defined thresholds are exceeded (max 10,000ms)

### Dashboard
- **Real-time status HUD** — Live pie chart breakdown with clickable status filters (online, degraded, offline, paused)
- **Latency sparklines** — Mini charts on each device tile showing recent latency trends
- **Check type badges** — ICMP / TCP / HTTP label displayed on each device tile
- **Stability scoring** — Combined uptime + packet loss reliability metric (70/30 weighted)
- **Sort options** — Sort devices by status, health score, latency, or name

### SLA & Reporting
- **Split SLA metrics** — "Available" (non-offline) and "Perfect Uptime" (online only) tracked separately
- **Time windows** — 24-hour, 7-day, and 30-day uptime percentages per device
- **Total downtime tracking** — Cumulative downtime duration calculated from history
- **Persistent history** — Status history survives app restarts (configurable per-device, default 2000 entries)

### Event Stream
- **Searchable log** — Filter events by device name or address
- **Status filters** — Filter by All, Online, Degraded, Offline, or Paused
- **Font size control** — Small / Medium / Large toggle for readability
- **CSV export** — Export currently filtered logs with device, timestamp, status, latency, and packet loss columns
- **Dark theme optimized** — All text uses theme-aware colors for readability

### Alerting & Notifications
- **Desktop notifications** — Native OS notifications on Windows, Linux, and macOS
- **Platform alert sounds** — OS-native sounds (Linux: paplay/aplay, macOS: afplay, Windows: PowerShell SystemSounds)
- **Recovery detection** — "RECOVERED" distinction when a device comes back online after an outage
- **Email alerts** — SMTP-based email notifications with HTML formatting and downtime duration
- **Webhook integration** — Slack, Discord, and generic JSON webhooks with recovery event support
- **Quiet hours** — Suppress notifications during scheduled windows with per-day granularity
- **Maintenance windows** — Per-device scheduled maintenance with date/time picker; alerts suppressed during window
- **Smart suppression** — Parent-based alert suppression (child alerts silenced when parent is offline)

### Network Tools
- **Quick Scan** — Built-in TCP port scanner with DNS resolution, ping latency, and service banner grabbing (no external tools required)
- **Deep Scan** — Full nmap enumeration: open ports, services, OS detection, MAC address, NSE scripts, traceroute
- **Dependency check** — Actionable dialog with OS-specific install instructions if nmap/traceroute is missing
- **Traceroute** — Live terminal-style network path diagnostics
- **Scan results** — Last deep scan report saved and displayed on device details

### Device Management
- **Groups** — Organize devices into infrastructure zones with collapsible sections
- **Tags** — Free-form metadata tags for categorization
- **Clone device** — Duplicate a device from the details screen with "(Copy)" suffix and clean history
- **Bulk operations** — Multi-select mode for batch pause, resume, delete, and group reassignment
- **Device types** — Server, Database, Router, Workstation, IoT, Website, Cloud with distinct icons

### Topology
- **Interactive graph** — Drag-and-drop network topology with animated packet flow visualization
- **Parent-child relationships** — Define dependencies between nodes for alert suppression

### Data & Configuration
- **CSV import/export** — Device configurations and audit telemetry
- **Automatic updates** — Checks GitHub Releases for new versions and applies updates in-place
- **Secure credential storage** — Email passwords stored in OS-backed secure storage (Keychain, Keystore, libsecret)
- **Keyboard shortcuts** — Ctrl+N (new device), Ctrl+G (new group), Enter/Escape on dialogs

### UI/UX
- **Dark / Light / System theme** — Material 3 design
- **Latency distribution chart** — Scrollable line chart with rotated time labels and tooltips
- **Status heatmap** — Last 60 ticks visualized as a color bar with tooltips
- **Chart optimization** — Details screen only redraws when history changes

## Supported Platforms

| Platform | Status |
|----------|--------|
| Windows  | Supported (10+) |
| Linux    | Supported |
| macOS    | Supported |

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Dart 3.9.2+)
- For Windows builds: Visual Studio 2022 with C++ desktop workload
- For Linux builds: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libsecret-1-dev`

### Optional Dependencies

These are **not required** for core functionality but enable advanced features:

| Tool | Feature | Install |
|------|---------|---------|
| `nmap` | Deep Scan (ports, OS, services) | `sudo apt install nmap` / `brew install nmap` / [nmap.org](https://nmap.org/download.html) |
| `traceroute` | Network path diagnostics | `sudo apt install traceroute` / included with macOS / `tracert` built into Windows |
| `notify-send` | Desktop notifications (Linux) | Usually pre-installed; `sudo apt install libnotify-bin` if missing |

### Build & Run

```bash
# Install dependencies
flutter pub get

# Run in development mode
flutter run -d linux   # or windows, macos
```

### Build Release

```bash
# Linux
flutter build linux --release
# Output: build/linux/x64/release/bundle/pingit

# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

### Download Pre-built Release

Download the latest release from the [Releases page](https://github.com/cbl508/PingIT/releases):

| File | Platform | Description |
|------|----------|-------------|
| `pingit-1.2.0-setup.exe` | Windows | Installer with Start Menu/Desktop shortcuts and optional Nmap download prompt |
| `pingit-windows-portable.zip` | Windows | Portable — extract and run, no installation needed |
| `pingit-linux.tar.gz` | Linux | Extract and run `./pingit` |

```bash
# Linux
tar -xzf pingit-linux.tar.gz
./pingit

# Windows (portable)
# Extract pingit-windows-portable.zip and run pingit.exe
```

## Project Structure

```
lib/
  main.dart                        # Entry point and theme configuration
  models/
    device_model.dart              # Device, DeviceGroup, StatusHistory models
    device_model.g.dart            # JSON serialization (hand-maintained)
  screens/
    home_screen.dart               # App shell with navigation and state management
    device_list_screen.dart        # Dashboard with status HUD and device tiles
    device_details_screen.dart     # Per-device monitoring with SLA, charts, events
    topology_screen.dart           # Interactive network topology graph
    logs_screen.dart               # Event stream with filters, font size, CSV export
    settings_screen.dart           # App config, email, webhooks, import/export, updates
    add_device_screen.dart         # Device creation/editing with maintenance windows
  services/
    ping_service.dart              # ICMP/TCP/HTTP health checking with backoff
    storage_service.dart           # File-based persistence with race condition safety
    email_service.dart             # SMTP alert notifications with HTML templates
    webhook_service.dart           # Slack, Discord, generic webhook alerts
    notification_service.dart      # OS-level desktop notifications
    alert_service.dart             # Platform-specific alert sounds
    update_service.dart            # GitHub-based automatic updates
    logging_service.dart           # Structured logging to file
  widgets/
    scan_dialog.dart               # Quick/Deep scan dialogs with dependency checking
```

## License

All rights reserved.
