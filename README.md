# SCAR.DEV Windows Administrator Toolkit

Free, open-source Windows diagnostics, troubleshooting and automation with standalone PowerShell scripts and an optional module.

**Status:** Early development. No stable release. Windows PowerShell 5.1 and PowerShell 7 compatibility are targets; neither is yet validated.

## First utility: Pending Reboot Inspector

Standalone:
```powershell
.\scripts\maintenance\Test-PendingReboot.ps1
```
Module:
```powershell
Import-Module .\src\ScarWinAdmin\ScarWinAdmin.psd1
Test-ScarPendingReboot
```
Both return an object with `Status` (`Pending`, `NotDetected`, or `Indeterminate`) and per-indicator evidence. Read-only; no network access or telemetry. Some reboot conditions are not represented by these indicators.

See [roadmap](docs/roadmap.md), [contributing](CONTRIBUTING.md), [security](SECURITY.md), and [agent instructions](AGENTS.md).
