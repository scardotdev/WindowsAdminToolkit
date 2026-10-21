# Changelog

All notable changes are recorded here. The project follows [Semantic Versioning](https://semver.org/); `0.x` releases may change result schemas.

## Unreleased

## 0.1.0 - 2026-10-21

First release. Five read-only utilities, each available as a `ScarWinAdmin` module command and as an equivalent standalone script (schema version `1.0` for all results).

### Added
- **Pending Reboot Inspector** (`Test-ScarPendingReboot`): five reboot indicators with `Pending` / `NotDetected` / `Indeterminate` status and per-indicator evidence.
- **Disk Space Investigator** (`Get-ScarDiskUsage`): fixed-volume capacity with warning/critical thresholds and an opt-in bounded scan (depth, item and time limits; reparse points are not followed and make the result partial).
- **Windows Event Log Investigator** (`Get-ScarEventSummary`): bounded per-log queries grouped by log, provider, event ID and level, with samples and explicit partial/capped/timeout reporting.
- **Network Diagnostics Bundle** (`Get-ScarNetworkDiagnostics`): adapter, IP configuration, default route and WinHTTP proxy inventory; opt-in DNS and TCP probes with per-test deadlines and connected-address evidence.
- **Windows Health Snapshot** (`Get-ScarWindowsHealth`): host, CPU, memory, disk, reboot, events, explicit services and optional local network inventory, with independent `CollectionStatus` and `HealthStatus`, evidence-backed findings, and optional JSON and offline HTML reports (HTML-encoded, never overwriting without `-Force`).
- Build (`tooling/Build.ps1`), release packaging (`tooling/Package.ps1`: zip plus SHA-256 checksum), PSScriptAnalyzer and Pester 5 tests, and GitHub Actions validation on Windows PowerShell 5.1 and PowerShell 7, including checks that every standalone script runs alone in a fresh process and that the packaged module imports.
- Installation guide, per-tool guides and security/output-handling guidance.

### Security
- The WinHTTP proxy lookup runs `netsh.exe` from the Windows system directory rather than resolving it through `PATH`.

### Known limitations
- Releases are not code-signed.
- Time budgets are best-effort; running CIM, event-log, filesystem and DNS calls cannot be cancelled.
- Network diagnostics do not record the full list of addresses attempted for a hostname, or an address for failed probes.
- Validated by automated tests on GitHub-hosted Windows runners (5.1 and 7) and by hand on one Windows 11 machine with Windows PowerShell 5.1 as a standard user. Servers, older Windows versions, domain-joined machines, non-English locales and elevated runs are untested.
