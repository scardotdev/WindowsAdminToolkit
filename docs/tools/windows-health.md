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

**Report security:** Offline HTML encodes displayed dynamic values. JSON may expose internal hostnames, event messages, and service names. Files are created only with explicit output paths; `-Force` permits replacement. Review reports before distributing them.

[Authoritative implementation specification](../specifications/WAT-001-windows-health.md).
