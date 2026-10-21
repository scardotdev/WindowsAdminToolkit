# WAT-001 — Windows Health Snapshot

Aggregates existing read-only diagnostic utilities, plus instantaneous OS/CPU/memory data and explicitly selected service state, into an evidence-backed report.

```powershell
Import-Module ./src/ScarWinAdmin/ScarWinAdmin.psd1
Get-ScarWindowsHealth
Get-ScarWindowsHealth -ServiceName 'Spooler','W32Time' -IncludeNetwork
Get-ScarWindowsHealth -OutputJsonPath ./health.json -OutputHtmlPath ./health.html
./tooling/Build.ps1
./out/scripts/health/Get-WindowsHealth.ps1
```

**Meaning of statuses:** `CollectionStatus` indicates whether evidence was successfully gathered; `HealthStatus` indicates observed findings. Confirmed critical evidence remains Critical even when unrelated checks fail. Missing sources are not automatically considered healthy.

**Boundaries:** no remediation, automatic outbound probes, credentials or telemetry. `-IncludeNetwork` gathers local inventory only. CPU values are single samples. Existing utility partial results remain partial. Overall timeouts are best-effort for synchronous CIM and event API calls.

**Collection details**
- Missing or out-of-range CPU/memory measurements are never treated as zero; the section is `Unavailable` (CPU is `Partial` if only some processors report).
- `Reboot` is `Partial` when any indicator is `Indeterminate`, even if another indicator is `Detected`; the pending-reboot warning is kept and an informational `reboot.indeterminate` finding explains the gap.
- `-ServiceName` takes explicit names only (no wildcards). Each service is `Running`/`Stopped`/etc., `NotFound` (an observation, reported as an informational finding), `Unavailable` (lookup failed, makes `Services` Partial) or `Skipped` (time budget exhausted; no new lookups start once it is).
- Sections not started because the budget ran out are listed in `SourceStatus` as `Skipped`; every entry has `ElapsedMs`.

**Reports**
- Paths are validated before collection (directory must exist, JSON and HTML paths must differ, existing files need `-Force`; without `-Force` files are created exclusively, so nothing is overwritten).
- Write outcomes are returned in `ReportOutputs` (`Kind`, `Path`, `Status` = `Written`/`Failed`, `Error`) and a failed write emits a warning. They never change `CollectionStatus`. The JSON file holds the evidence only, so its `ReportOutputs` is empty.
- The HTML report includes summary, source coverage, findings, collection errors and compact evidence (host, CPU, memory, reboot indicators, disks, services, top event groups, network adapters). Every dynamic value is HTML-encoded; there is no script or remote content.

**Report security:** Offline HTML encodes displayed dynamic values. JSON may expose internal hostnames, event messages, and service names. Files are created only with explicit output paths; `-Force` permits replacement. Review reports before distributing them.

[Authoritative implementation specification](../specifications/WAT-001-windows-health.md).
