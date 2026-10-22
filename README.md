# SCAR.DEV Windows Administrator Toolkit

[![Validate](https://github.com/scardotdev/WindowsAdminToolkit/actions/workflows/validate.yml/badge.svg)](https://github.com/scardotdev/WindowsAdminToolkit/actions/workflows/validate.yml)
[![Latest release](https://img.shields.io/github/v/release/scardotdev/WindowsAdminToolkit)](https://github.com/scardotdev/WindowsAdminToolkit/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/scardotdev/WindowsAdminToolkit/total)](https://github.com/scardotdev/WindowsAdminToolkit/releases)
[![License: MIT](https://img.shields.io/github/license/scardotdev/WindowsAdminToolkit)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6)
![Read-only](https://img.shields.io/badge/read--only-no%20changes%20made-brightgreen)
[![Last commit](https://img.shields.io/github/last-commit/scardotdev/WindowsAdminToolkit)](https://github.com/scardotdev/WindowsAdminToolkit/commits/main)
[![Open issues](https://img.shields.io/github/issues/scardotdev/WindowsAdminToolkit)](https://github.com/scardotdev/WindowsAdminToolkit/issues)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

Free, open-source, **read-only** Windows diagnostics. Five small tools that look at a Windows PC and tell you what they found and how sure they are. They never fix, delete or change anything, and nothing is sent anywhere.

Each tool comes twice with identical behavior: a standalone PowerShell script (nothing to install) and a function in the `ScarWinAdmin` module. Results are structured objects (schema version `1.0`) that you can pipe to `ConvertTo-Json`, `Export-Csv` or a report.

**Status:** v0.1.0, first release. See the [changelog](CHANGELOG.md).

**Jump to:** [Quick-start guide](#quick-start-guide-no-experience-needed) · [When to use which tool](#1-when-should-i-use-this) · [Reading results](#6-how-to-read-the-results) · [Troubleshooting](#7-if-something-goes-wrong) · [Reference](#reference)

---

# Quick-start guide (no experience needed)

This guide takes you from nothing to your first report in about ten minutes. You do not need to be an administrator, install anything, or know PowerShell. You only copy and paste the commands shown in grey boxes.

## 1. When should I use this?

Use it when you are looking at **one Windows PC** (the one you are sitting at) and want facts before you guess, escalate a ticket, or change something.

| What is happening | Run this | What it tells you |
| --- | --- | --- |
| "Something is wrong with this PC" and you are not sure what, or you want a note to attach to a ticket | **Health Snapshot** (start here) | One summary: memory, CPU, disk space, pending restart, recent errors, and anything that needs attention |
| Windows keeps asking for a restart, or an update or install says "restart required" | **Pending Reboot Check** | Whether a restart is waiting, and which reason triggered it |
| The C: drive is nearly full, or saving files fails | **Disk Space Check** | Free space on each drive and, if you point it at a folder, the biggest files in it |
| Things keep crashing, services fail, or Windows Update misbehaves | **Event Log Summary** | The errors and warnings that repeat most in the last day |
| No internet, cannot reach a server or website, or slow network | **Network Check** | Network adapters, addresses, gateway, proxy; optionally tests a name or port you choose |

**Not what this toolkit is for:** it does not repair anything, scan for viruses, check other computers over the network, or replace your IT team's monitoring. It is a one-time snapshot of this PC. If you are not authorized to look at a computer, do not run it on it.

## 2. What you need

- A Windows 10 or Windows 11 PC. Windows PowerShell 5.1 is already built in, so nothing to install.
- About 1 MB of space and an internet connection **only for the download**.
- Administrator rights are **not** needed. (Running as administrator can show a few extra details; see [troubleshooting](#7-if-something-goes-wrong).)

## 3. Download

1. Open **[the latest release page](https://github.com/scardotdev/WindowsAdminToolkit/releases/latest)**.
2. Under **Assets**, click `ScarWinAdmin-v….zip` to download it, and also `SHA256SUMS.txt` (used in step 4).
3. They normally land in your **Downloads** folder. The version number in the file name may be newer than the examples here; that is fine.

## 4. Unpack it

1. Press the **Windows key**, type **PowerShell**, and open **Windows PowerShell** (the blue window). Do not choose "Run as administrator".
2. Copy the whole grey box below, paste it into the window (right-click pastes), and press **Enter**:

```powershell
cd $HOME\Downloads
(Get-FileHash .\ScarWinAdmin-v*.zip).Hash -eq (Get-Content .\SHA256SUMS.txt).Split(' ')[0]
```

It must print **`True`**. That means the file is exactly the one published. If it prints `False` or an error, delete the download and get it again from the release page; do not use it.

3. Now unpack it and move into the folder:

```powershell
Unblock-File .\ScarWinAdmin-v*.zip
Expand-Archive .\ScarWinAdmin-v*.zip -DestinationPath ([Environment]::GetFolderPath('MyDocuments'))
cd ([Environment]::GetFolderPath('MyDocuments'))
cd .\ScarWinAdmin-v*
```

You are now inside the toolkit folder in your **Documents**. Type `dir` and press Enter: you should see `docs`, `module` and `scripts`.

4. Allow the scripts to run **in this window only** (nothing is changed on the PC, and it resets when you close the window):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

> Closed the window later? Repeat just these steps: open PowerShell, `cd` to the folder (for example `cd ([Environment]::GetFolderPath('MyDocuments')); cd .\ScarWinAdmin-v*`), then the `Set-ExecutionPolicy` line above.

## 5. Run it

### First run: the Health Snapshot (recommended)

This creates a readable web page report on your Desktop and prints a short summary. It takes a few seconds.

```powershell
$r = .\scripts\health\Get-WindowsHealth.ps1 -OutputHtmlPath "$([Environment]::GetFolderPath('Desktop'))\health-report.html" -Force
$r | Format-List CollectionStatus,HealthStatus
$r.Findings | Format-Table Severity,Title,Evidence -AutoSize -Wrap
$r.SourceStatus | Format-Table Source,Status,Error -AutoSize
```

Then double-click **health-report.html** on your Desktop to read the full report in your browser. See [how to read the results](#6-how-to-read-the-results) for what the words mean. To also check specific Windows services, add for example `-ServiceName Spooler,W32Time` after the script name.

### The other tools

Run only what matches your situation (see the table in section 1). Each box is independent; paste one at a time.

**Pending Reboot Check**

```powershell
$r = .\scripts\maintenance\Test-PendingReboot.ps1
$r.Status
$r.Indicators | Format-Table Name,Status,Error -AutoSize
```

`Pending` = a restart is waiting; `NotDetected` = none of the checks found one; `Indeterminate` = a check could not be read, so you cannot be sure.

**Disk Space Check**

```powershell
$r = .\scripts\storage\Get-DiskUsage.ps1
$r.Volumes | Format-Table Drive,FreePercent,Severity -AutoSize
```

To find the biggest files in a folder you choose (replace the path; it only looks, it never deletes):

```powershell
$r = .\scripts\storage\Get-DiskUsage.ps1 -Path "C:\Users\Public"
$r.TopFiles | Format-Table @{n='MB';e={[math]::Round($_.Bytes/1MB,1)}},Path -AutoSize -Wrap
```

`Severity` is `Warning` below 20% free and `Critical` below 10% free.

**Event Log Summary** (last 24 hours of System and Application errors/warnings)

```powershell
$r = .\scripts\diagnostics\Get-WindowsEventSummary.ps1
$r.GroupedEvents | Format-Table Count,LogName,ProviderName,EventId,Level -AutoSize
```

The same event repeated many times is the one to look into first. `Level` 1 = critical, 2 = error, 3 = warning. A high count points you at something to research; it does not by itself prove the cause. Searching the web for the `ProviderName` and `EventId` together is a good next step.

**Network Check**

```powershell
$r = .\scripts\network\Get-NetworkDiagnostics.ps1
$r.Adapters | Format-Table Name,Status,IPv4Addresses,DnsServers -AutoSize
$r.DefaultRoutes | Format-Table NextHop,InterfaceIndex,RouteMetric -AutoSize
```

Look for an adapter with `Status` **Up** that has an address. Entries marked `Not Present` or `Disconnected` are normally unused adapters and can be ignored. An address starting `169.254` means the PC did not get an address from the network. To test one specific server you are allowed to test (replace the name and port):

```powershell
$r = .\scripts\network\Get-NetworkDiagnostics.ps1 -DnsTarget server.example.com -TcpTarget server.example.com -TcpPort 443
$r.DnsTests | Format-Table Target,Status,Answers -AutoSize
$r.TcpTests | Format-Table Target,Port,Status,ElapsedMs -AutoSize
```

The network tool only contacts names you type here; otherwise it makes no connections.

## 6. How to read the results

| You see | It means | What to do |
| --- | --- | --- |
| `CollectionStatus: Complete` | Everything it tried to look at was read | Trust the findings as complete for what the tool covers |
| `CollectionStatus: Partial` | Something could not be read, ran out of time, or hit a limit | Read the `Error` column; **do not treat the result as "all clear"**. Try again, or run as administrator |
| `HealthStatus: Critical` / `Warning` | A measurement crossed a threshold (for example disk almost full) | Read the finding's title, evidence and suggested next step |
| `HealthStatus: NoFindings` | No threshold was crossed **and** everything was read | Good sign, but not proof the PC is healthy |
| `HealthStatus: Unknown` | Nothing alarming was seen, but some checks could not be read | Treat as "not enough information" and see the `Error` column |
| Source `Skipped` | You did not ask for it (for example services or network) or time ran out | Add the option or run again if you need it |
| Finding severity `Informational` | A note, not a problem (for example "service not found") | Read it; usually no action |

Findings are **observations, not diagnoses**. CPU is a single instant, so a high number once does not mean the PC is always busy.

## 7. If something goes wrong

| Message or problem | What to do |
| --- | --- |
| `False` when checking the download | The file is damaged or not the published one. Delete it and download again from the release page. |
| `... cannot be loaded because running scripts is disabled` | Repeat the `Set-ExecutionPolicy -Scope Process ...` line from step 4 in the same window. If it still fails, your organization blocks scripts: ask your IT team. |
| `... is not digitally signed` or a security warning about the file | Run `Unblock-File` on the zip (step 4) **before** extracting. The scripts are not code-signed (see [Security](SECURITY.md)); read them first if you want, they are plain text. |
| `Cannot find path ... because it does not exist` | You are in the wrong folder. Type `dir`; you should see `scripts`. Use `cd` to move into the `ScarWinAdmin-v…` folder (step 4). |
| `The term '.\scripts\...' is not recognized` | Same cause: wrong folder. |
| Result says `Partial` with "access denied" | Close PowerShell, open it again with **right-click > Run as administrator**, repeat step 4's `cd` and `Set-ExecutionPolicy` lines, and run again. Still read-only. |
| The health report shows `Output directory does not exist` | Your Desktop is in an unusual place. Use another folder you can write to, for example `-OutputHtmlPath "$HOME\Documents\health-report.html"`. |
| `Output already exists (specify -Force)` | A report with that name exists. Add `-Force` to replace it, or choose a different name. |
| Anything else | Copy the red text, remove any private names or addresses, and [open an issue](https://github.com/scardotdev/WindowsAdminToolkit/issues). |

## 8. Staying safe

- **It only looks.** No tool changes settings, installs, deletes, or restarts anything. The only files it ever writes are the report files you ask for with `-OutputHtmlPath` or `-OutputJsonPath`.
- **Results can be private.** They can include the computer and user names, addresses, folder and file names, and the text of event-log messages. Look through a result before pasting it into a ticket, chat or email, and delete reports you no longer need.
- **Only test what you may test.** The Network Check's `-DnsTarget` and `-TcpTarget` options make real connections to the names you type. Use them only on systems you are allowed to test.
- **Only run it on PCs you are authorized to look at.** Run it on the PC in front of you; it does not inspect other computers.
- **Cleaning up:** close the PowerShell window and delete the `ScarWinAdmin-v…` folder from Documents, the zip from Downloads, and any report files you made. Nothing else was installed.
- **Not code-signed:** because the release is not code-signed, the checksum check in step 4 is how you know you have the genuine file.

Next: [technical reference](#reference) for module use, saving results as JSON/CSV, building from source, and what each tool covers.

---

# Reference

## Compatibility and validation

| Environment | Validation |
| --- | --- |
| Windows PowerShell 5.1 | Automated tests on every push and pull request (GitHub `windows-latest`), plus a manual end-to-end run of every command and standalone script on a physical Windows 11 machine as a standard (non-elevated) user. |
| PowerShell 7 | Automated tests on every push and pull request (GitHub `windows-latest`). Not yet run by hand on a physical machine. |
| Not validated | Windows Server and older client versions, domain-joined or non-English systems, elevated runs, Linux/macOS (the tools require Windows and say so). |

The CI matrix runs the build, PSScriptAnalyzer, the Pester suite and the packaged-artifact checks (each standalone script runs alone in a fresh process, and the extracted module imports) on both editions. Results on your systems may differ; please [report problems](CONTRIBUTING.md).

## Using the PowerShell module instead of the scripts

After extracting (see the guide above), from inside the toolkit folder:

```powershell
Import-Module .\module\ScarWinAdmin\ScarWinAdmin.psd1
Get-Command -Module ScarWinAdmin
```

More options (permanent install, uninstall, execution policy, building from source) are in [docs/installation.md](docs/installation.md). From a clone of this repository: `.\tooling\Build.ps1` creates `out\` (standalone scripts and a module copy); `.\tooling\Package.ps1` creates the release zip in `dist\`.

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

## How results are built

- `CollectionStatus` is `Complete` or `Partial`: whether the evidence was fully gathered. Access failures, caps, skipped items and timeouts make a result `Partial`; it is never presented as healthy.
- `HealthStatus` (health snapshot only) reflects observed threshold findings and is independent of collection. `NoFindings` means no threshold was crossed with complete coverage, not "healthy".
- Findings state evidence and a suggested next step. They are not diagnoses. CPU is a single instantaneous sample.
- Time budgets are best-effort: a running Windows API call cannot be cancelled, so a call can overrun and the result then says so.

## Safety, privacy and output

The tools make no changes, run no remediation, and send no telemetry. They write files only when you pass `-OutputJsonPath` / `-OutputHtmlPath` to the health snapshot (never overwriting without `-Force`). Network probes happen only for DNS/TCP targets you list. Output can include computer and account names, hostnames, paths, service names and event-log messages; **review before sharing**. See [SECURITY.md](SECURITY.md) for reporting vulnerabilities and handling output.

## Project

[Roadmap](docs/roadmap.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md) · [Agent instructions](AGENTS.md) · MIT licensed ([LICENSE](LICENSE)).
