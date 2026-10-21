# SCAR.DEV Windows Administrator Toolkit

Free, open-source Windows diagnostics, troubleshooting and automation with standalone PowerShell scripts and an optional module.

**Status:** Early development. No stable release. Windows PowerShell 5.1 and PowerShell 7 compatibility are targets; neither is yet validated.

## First utility: Pending Reboot Inspector

Standalone (generated from the module source):
```powershell
.\tooling\Build.ps1
.\out\scripts\maintenance\Test-PendingReboot.ps1
```
Module:
```powershell
Import-Module .\src\ScarWinAdmin\ScarWinAdmin.psd1
Test-ScarPendingReboot
```
Both return an object with `Status` (`Pending`, `NotDetected`, or `Indeterminate`) and per-indicator evidence. Read-only; no network access or telemetry. Some reboot conditions are not represented by these indicators.

See [roadmap](docs/roadmap.md), [contributing](CONTRIBUTING.md), [security](SECURITY.md), and [agent instructions](AGENTS.md).

## Disk Space Investigator

Read-only, bounded diagnostics with volume capacity and an opt-in file scan. See [usage and limitations](docs/tools/disk-usage.md).

## Windows Event Log Investigator

Read-only event triage, grouping, and evidence collection. See [usage and limitations](docs/tools/event-summary.md).

## Network Diagnostics Bundle

Local adapter, route and proxy inventory, with explicit opt-in DNS and TCP probes. See [usage](docs/tools/network-diagnostics.md).

## Windows Health Snapshot

Use `Get-ScarWindowsHealth` to aggregate host, CPU, memory, disk, reboot, event and optional local network evidence. See [health snapshot guide](docs/tools/windows-health.md).
