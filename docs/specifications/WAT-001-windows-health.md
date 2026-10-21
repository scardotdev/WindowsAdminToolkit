# WAT-001 — Windows Health Snapshot: Implementation Specification

**Status:** Proposed for v0.1 · **Type:** implementation contract · **Dependency:** WAT-002, WAT-003, WAT-005; WAT-004 optional  
**Primary command:** `Get-ScarWindowsHealth`

## 1. Outcome

Provide a bounded, read-only Windows host-health snapshot that answers: **what needs attention, why, and what evidence supports it?** Aggregate existing toolkit utilities rather than cloning their implementations. Return a machine-readable report and a concise prioritized finding list. Severity reflects configured thresholds and direct evidence, **not a verified diagnosis**.

**Included in v0.1**
- Computer/OS identity, OS version/build and last-boot timestamp/uptime.
- CPU load and memory pressure from supported local counters/CIM sources, with measurement timestamps and clearly labeled instantaneous sampling.
- Fixed-disk free-space summary using `Get-ScarDiskUsage` *without* optional directory traversal.
- Pending reboot evidence from `Test-ScarPendingReboot` (preserve `Pending`, `NotDetected`, `Indeterminate`).
- Bounded recent error/critical event summary using `Get-ScarEventSummary` with System/Application defaults.
- Selected service status: explicit `ServiceName` input only; absent services or access failures are evidence, not silent success.
- Optional network diagnostics via `Get-ScarNetworkDiagnostics` **local inventory only by default**, when WAT-004 exists and user opts in.
- Aggregated finding list, data-source statuses, explicit partial/error accounting, JSON output and *optional* local HTML report generated only when an output path is passed.

**Excluded:** continuous monitoring, trend analysis, alert scheduling, automatic fixes/reboots, software inventory, AD domain analysis, remote orchestration, antivirus assertions, arbitrary security scoring, cloud connectivity and unattended upload/email.

## 2. Public interface

```powershell
Get-ScarWindowsHealth
Get-ScarWindowsHealth -EventLookbackHours 24 -ServiceName 'Spooler','W32Time'
Get-ScarWindowsHealth -OutputJsonPath '.\health.json' -OutputHtmlPath '.\health.html'
Get-ScarWindowsHealth -IncludeNetwork
```

Proposed parameters:

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `EventLookbackHours` | `int` | 24 | 1–168; forwarded to WAT-005 |
| `MaxEventsPerLog` | `int` | 500 | 1–5000; forwarded to WAT-005 |
| `ServiceName` | `string[]` | none | At most 30 explicit service names; inventory their observed status |
| `WarningDiskFreePercent` | `double` | 20 | Warn when at/below threshold |
| `CriticalDiskFreePercent` | `double` | 10 | Critical when at/below threshold; must not exceed warning |
| `WarningMemoryUsedPercent` | `double` | 85 | Observational threshold, not a performance diagnosis |
| `CriticalMemoryUsedPercent` | `double` | 95 | Must not be below warning |
| `WarningCpuPercent` | `double` | 90 | Single sample only; label low confidence |
| `TimeoutSeconds` | `int` | 90 | Overall best-effort budget, range 10–600 |
| `IncludeNetwork` | `switch` | false | Opt into WAT-004 local inventory; never implied external probes |
| `OutputJsonPath` | `string` | none | User-requested local JSON artifact only |
| `OutputHtmlPath` | `string` | none | User-requested local HTML artifact only |

Output paths are optional; without them the command must not write files. Validate threshold ordering, caps, service names and output paths before collection. `-WhatIf` is unnecessary for a read-only command, but writing report files must never overwrite silently: explicitly document and test overwrite behavior (prefer `-Force` switch to allow replace).

## 3. Source adapters and collection rules

| Section | Source | Key rules |
| --- | --- | --- |
| Host/OS/uptime | `Win32_OperatingSystem`, `Win32_ComputerSystem` | Capture query failures independently; last boot can be missing |
| CPU | supported performance counter/CIM sample | Record exact source and time; do not describe one sample as sustained |
| Memory | available physical memory vs total physical memory from CIM | Reject zero/invalid denominators, report unavailable rather than normal |
| Disk | `Get-ScarDiskUsage` | No directory scan; retain volume thresholds and raw evidence |
| Reboot | `Test-ScarPendingReboot` | `Indeterminate` cannot be mapped to `NotDetected` |
| Events | `Get-ScarEventSummary` | Retain per-log caps, errors, counts and timestamps |
| Services | `Get-Service -Name` for specified names | Explicit desired-state assumptions forbidden; stopped ≠ bad unless caller-defined expectation exists |
| Network (optional) | `Get-ScarNetworkDiagnostics` | Invoked without DNS/TCP targets; never automatic Internet probing |

**Dependency behavior:** use commands loaded from the module and validate output schemas. Catch each source separately; preserve a `SourceStatus` entry for all attempted sections. Missing WAT-004 with `-IncludeNetwork` yields `Partial` with `Unavailable` section (never silently omit). A failed child collection is retained as a partial child object; do not overwrite its status. Stop starting new collectors when budget exhausted, reporting skipped sections, but note that synchronous CIM/event calls cannot always be force-cancelled.

## 4. Result schema v1

Return one `[pscustomobject]` with `PSTypeName='ScarWinAdmin.WindowsHealthResult'`:

| Property | Definition |
| --- | --- |
| `SchemaVersion`, `Tool` | `'1.0'`, `'ScarWinAdmin.WindowsHealth'` |
| `ComputerName`, `CollectedAtUtc`, `DurationMs` | identity and observed times |
| `CollectionStatus` | `Complete` / `Partial` (collection completeness only) |
| `HealthStatus` | `Critical` / `Warning` / `NoFindings` / `Unknown`; never assert 'Healthy' with missing coverage |
| `SourceStatus` | array of section identifiers, `Complete` / `Partial` / `Unavailable` / `Skipped`, elapsed ms, error |
| `Host`, `Cpu`, `Memory`, `Disk`, `Reboot`, `Events`, `Services`, `Network` | typed section objects; unavailable sections null plus status |
| `Findings` | array of `FindingId`, `Severity`, `Title`, `Evidence`, `Source`, `ObservedAtUtc`, `SuggestedNextStep` |
| `CollectionErrors`, `TimedOut` | array of structured errors and Boolean |

Severity of findings: `Critical`, `Warning`, `Informational`. Priority sort: severity, then source and stable identifier (deterministic); findings must include evidence and should avoid predicting incident causes. Rules:
- Disk threshold findings based on observed free percentage; honor configured critical/warning ordering.
- Memory threshold from a valid observed utilization percentage.
- CPU threshold from valid instantaneous reading; state that it is one sample.
- Reboot `Pending` yields an informational or warning operational finding; `Indeterminate` yields a collection-uncertainty finding rather than “no reboot.”
- Frequent event IDs are *observations*, not automatic critical findings solely by frequency; include top groups with timestamps and source coverage.
- Service `Stopped` is observational unless explicit expected-running config is added in a later version.
- `NoFindings` only when core sources complete and no threshold triggered; otherwise `Unknown` if no critical/warning finding and evidence is incomplete. Critical/warning observed findings take precedence even if collection is partial.

Schema must have consistent types and arrays for zero/one/many entries. Include schema-contract regression tests so child tool updates cannot silently break integrations.

## 5. JSON and HTML reporting

JSON is canonical; serialize at sufficient depth for nested child evidence with stable ISO UTC timestamps. Do not serialize exception objects. File writes must honor `-Force` overwrite semantics, fail safely when location inaccessible, and surface output-path failure rather than treating it as successful collection. Report file status separately from health collection.

HTML is a **static offline report** generated locally: summary, source coverage, findings and compact evidence tables. Encode *every* dynamic string (event messages, service names, hostnames, paths, errors) using HTML escaping; no CDN, JavaScript, remote assets or active content. Never open a browser automatically. Redact nothing silently; warn that raw event messages/hostnames may contain sensitive information. Tests must include HTML injection payloads and JSON round-trip.

## 6. Packaging and design

- Authoritative implementation under `src/ScarWinAdmin/Public/Get-ScarWindowsHealth.ps1` (small internal helper functions may go under `Private/`).
- Export from `ScarWinAdmin.psm1` and `.psd1`.
- Standalone build target `out/scripts/health/Get-WindowsHealth.ps1` must embed required functions/helpers *in dependency order*, without requiring installation of the module, and preserve command parameters/results.
- No elevation requirement by default; preserve permission failures as incomplete checks.
- No writes to the host except user-requested local reports. No telemetry, remote calls or downloads.
- Support Windows PowerShell 5.1 + PowerShell 7 on Windows; avoid cross-platform assumptions and PowerShell 7-only syntax.
- Integrate with `tooling/Build.ps1`, existing GitHub Actions, PSScriptAnalyzer, Pester, README, changelog and `docs/tools/windows-health.md`.
- Incremental implementation: collectors → schema → findings → report rendering → packaging, with automated tests throughout.

## 7. Acceptance criteria

- [ ] Invoking the command with defaults is read-only, generates no files and performs no external network probes.
- [ ] Host/CPU/memory collection reports units, timestamp, provenance and missing-data semantics.
- [ ] Disk/reboot/events data is consumed from existing commands, **not reimplemented**.
- [ ] Service collection only runs for explicit names; missing/stopped/error cases are distinguishable.
- [ ] `-IncludeNetwork` off means WAT-004 is not invoked; on means *inventory only*.
- [ ] Child `Partial`/`Indeterminate`, failure and missing-command scenarios propagate accurately.
- [ ] Whole-tool timeout and section skip logic do not present incomplete coverage as `NoFindings`.
- [ ] Threshold ordering and 0/100 boundary cases tested; no divide-by-zero results.
- [ ] Health and collection statuses are independent; observed critical findings remain visible with partial collection.
- [ ] Findings deterministic, evidence-backed and never assert inferred root cause.
- [ ] JSON schema round-trip, zero/one/many arrays, and static HTML escaping tested.
- [ ] Reporting failures are explicit, no file overwrite without `-Force`, no automatic browser opening.
- [ ] Generated standalone operates without module installation, has parameter/output parity with module.
- [ ] Pester/ScriptAnalyzer/build pass on both Windows PowerShell 5.1 and 7; Codex review resolved before merge.

## 8. Dependencies and sequencing

**Hard dependencies:** existing WAT-002 `Test-ScarPendingReboot`, WAT-003 `Get-ScarDiskUsage`, WAT-005 `Get-ScarEventSummary`. **Optional dependency:** WAT-004 `Get-ScarNetworkDiagnostics` for an opt-in section. Implement WAT-004 first so the full v0.1 feature set is available, but WAT-001 must degrade predictably if optional network support is missing.

**Definition of done:** tested module and standalone script, example output schema, documented privilege/performance/privacy limits, and green CI on both Windows PowerShell versions. Merge and release are separate decisions.
