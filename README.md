# SCAR.DEV Windows Administrator Toolkit

Free, open-source, **read-only** Windows diagnostics. Every utility ships twice with the same behavior: as a standalone PowerShell script and as a function in the `ScarWinAdmin` module. Results are structured objects (schema version `1.0`) that you can pipe to `ConvertTo-Json`, `Export-Csv` or a report.

**Status:** v0.1.0, first release. See the [changelog](CHANGELOG.md).

## Compatibility and validation

| Environment | Validation |
| --- | --- |
| Windows PowerShell 5.1 | Automated tests on every push and pull request (GitHub `windows-latest`), plus a manual end-to-end run of every command and standalone script on a physical Windows 11 machine as a standard (non-elevated) user. |
| PowerShell 7 | Automated tests on every push and pull request (GitHub `windows-latest`). Not yet run by hand on a physical machine. |
| Not validated | Windows Server and older client versions, domain-joined or non-English systems, elevated runs, Linux/macOS (the tools require Windows and say so). |

The CI matrix runs the build, PSScriptAnalyzer, the Pester suite and the packaged-artifact checks (each standalone script runs alone in a fresh process, and the extracted module imports) on both editions. Results on your systems may differ; please [report problems](CONTRIBUTING.md).

## Install

Download `ScarWinAdmin-v0.1.0.zip` and `SHA256SUMS.txt` from the GitHub release, verify, unblock, and extract. Details, uninstall and execution-policy notes are in [docs/installation.md](docs/installation.md).

```powershell
(Get-FileHash .\ScarWinAdmin-v0.1.0.zip -Algorithm SHA256).Hash.ToLower()   # compare with SHA256SUMS.txt
Unblock-File .\ScarWinAdmin-v0.1.0.zip
Expand-Archive .\ScarWinAdmin-v0.1.0.zip -DestinationPath .
Import-Module .\ScarWinAdmin-v0.1.0\module\ScarWinAdmin\ScarWinAdmin.psd1
```

From a clone of this repository: `.\tooling\Build.ps1` creates `out\` (standalone scripts and a module copy); `.\tooling\Package.ps1` creates the release zip in `dist\`.

## Utilities

| Question | Module command | Standalone script (in `scripts\`) | Guide |
| --- | --- | --- | --- |
| Is a restart pending? | `Test-ScarPendingReboot` | `maintenance\Test-PendingReboot.ps1` | below |
| Where did the disk space go? | `Get-ScarDiskUsage` | `storage\Get-DiskUsage.ps1` | [disk-usage](docs/tools/disk-usage.md) |
| What keeps failing in the event logs? | `Get-ScarEventSummary` | `diagnostics\Get-WindowsEventSummary.ps1` | [event-summary](docs/tools/event-summary.md) |
| What is the network configuration? | `Get-ScarNetworkDiagnostics` | `network\Get-NetworkDiagnostics.ps1` | [network-diagnostics](docs/tools/network-diagnostics.md) |
| What needs attention on this host? | `Get-ScarWindowsHealth` | `health\Get-WindowsHealth.ps1` | [windows-health](docs/tools/windows-health.md) |

```powershell
Test-ScarPendingReboot                       # Status: Pending | NotDetected | Indeterminate, with per-indicator evidence
Get-ScarDiskUsage                            # volumes only; add -Path to opt in to a bounded file scan
Get-ScarEventSummary -LookbackHours 24       # grouped System/Application errors
Get-ScarNetworkDiagnostics                   # local inventory; DNS/TCP probes only for targets you name
Get-ScarWindowsHealth -ServiceName Spooler -OutputJsonPath .\health.json -OutputHtmlPath .\health.html
.\scripts\storage\Get-DiskUsage.ps1 -Path C:\Logs    # same result from the standalone script
```

The pending reboot check reads five indicators (component servicing, Windows Update, pending file renames, computer rename). Some reboot conditions are not covered by them.

## How results should be read

- `CollectionStatus` is `Complete` or `Partial`: whether the evidence was fully gathered. Access failures, caps, skipped items and timeouts make a result `Partial`; it is never presented as healthy.
- `HealthStatus` (health snapshot only) reflects observed threshold findings and is independent of collection. `NoFindings` means no threshold was crossed with complete coverage, not "healthy".
- Findings state evidence and a suggested next step. They are not diagnoses. CPU is a single instantaneous sample.
- Time budgets are best-effort: a running Windows API call cannot be cancelled, so a call can overrun and the result then says so.

## Safety, privacy and output

The tools make no changes, run no remediation, and send no telemetry. They write files only when you pass `-OutputJsonPath` / `-OutputHtmlPath` to the health snapshot (never overwriting without `-Force`). Network probes happen only for DNS/TCP targets you list. Output can include computer and account names, hostnames, paths, service names and event-log messages; **review before sharing**. See [SECURITY.md](SECURITY.md) for reporting vulnerabilities and handling output.

## Project

[Roadmap](docs/roadmap.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Agent instructions](AGENTS.md) · MIT licensed ([LICENSE](LICENSE)).
