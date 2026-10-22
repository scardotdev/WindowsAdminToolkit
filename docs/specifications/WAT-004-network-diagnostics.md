# WAT-004 — Network Diagnostics Bundle: Implementation Specification

**Status:** Implemented in v0.1.0 (known gaps below) · **Type:** implementation contract  
**Primary command:** `Get-ScarNetworkDiagnostics` · **Owner:** SCAR.DEV Windows Administrator Toolkit

## 1. Outcome and scope

Produce a single, read-only, structured network troubleshooting report for a local Windows host. An administrator should be able to distinguish local interface/configuration issues, DNS failures, missing routes/gateways, and TCP reachability failures without interpreting a collection of unrelated console transcripts.

**v0.1 in scope**
- Local physical/virtual interface inventory: description, adapter status, MAC (where available), IPv4/IPv6 addresses, prefix, DNS server addresses, gateway association and interface indices.
- Local routing overview: active default IPv4/IPv6 routes and next hops, interface association, and metrics; *no* routing-table changes.
- DNS resolution for explicitly provided targets (A/AAAA by default), including resolver errors and returned answers.
- TCP connection tests to explicitly specified target/port pairs; record resolved target, outcome, elapsed time and failure classification when available.
- Current effective WinHTTP proxy configuration (inventory only); flag unsupported/unavailable retrieval without implying “no proxy.”
- Optional gateway TCP/DNS checks only when a target and port are expressly supplied; do **not** infer that ICMP or TCP gateway responsiveness is a prerequisite for network health.
- Per-check timestamps, statuses, errors, and an overall collection status; short human-readable hints based only on verified facts.

**Out of scope:** packet capture, traceroute/continuous ping, port scanning, throughput tests, remote execution, external public-IP lookup, adapter resets, DNS flush, route changes, proxy changes, credential retrieval, telemetry and remediation.

## 2. Interface and execution semantics

```powershell
Get-ScarNetworkDiagnostics
Get-ScarNetworkDiagnostics -DnsTarget 'intranet.example' -TcpTarget 'intranet.example' -TcpPort 443
Get-ScarNetworkDiagnostics -DnsTarget 'example.org','example.net' -TimeoutSeconds 20
```

Proposed parameters (explicit defaults; prefer a single canonical interface in both distributions):

| Parameter | Type | Default | Contract |
| --- | --- | --- | --- |
| `DnsTarget` | `string[]` | none | Only names explicitly provided; cap at 20 unique non-empty values |
| `TcpTarget` | `string[]` | none | Hosts/IPs paired positionally with `TcpPort`; no Cartesian-product scanning |
| `TcpPort` | `int[]` | none | One port per target; range 1–65535; reject unequal counts |
| `TimeoutSeconds` | `int` | 30 | Overall best-effort budget, range 1–120 |
| `PerTestTimeoutSeconds` | `int` | 5 | Per-network-operation budget, 1–30; effective limit is remaining overall budget |
| `IncludeRoutes` | `switch` | true | For simplicity use `-SkipRoutes` switch if opt-out is desired; avoid ambiguous switch defaults |
| `IncludeProxy` | `switch` | true | Use `-SkipProxy` opt-out if required |
| `IncludeIPv6` | `switch` | false | Include IPv6 route/address details; DNS AAAA results may still be captured by resolver |

Network tests must be **opt-in**; no outbound DNS query or TCP connection when only running local inventory. A DNS query that is part of a requested TCP test is permitted, and must be recorded as part of that test's evidence. Do not automatically contact third-party endpoints or use example.org as a default probe.

Use native Windows APIs / available PowerShell cmdlets with PS 5.1 support (`Get-NetAdapter`, `Get-NetIPConfiguration`, `Get-NetRoute`, `Get-DnsClientServerAddress` and scoped resolver/TCP methods); capability-detect absent cmdlets and degrade to `Unavailable`. Avoid depending on `Test-NetConnection` for strict timeouts or machine-parsable errors. A cancellable / deadline-bounded TCP implementation using `.NET Socket` async connect is preferable, and sockets **must be disposed**. Do not treat a task timeout as permission to leave uncontrolled concurrent work.

Validate parameters before collecting. Support local machine only in v0.1. A query may exceed the overall budget if an underlying OS call cannot be cancelled; document that limitation and report `TimedOut`/partial where observable.

## 3. Structured output v1

One `[pscustomobject]` with `PSTypeName='ScarWinAdmin.NetworkDiagnosticsResult'` and:

| Property | Type / meaning |
| --- | --- |
| `SchemaVersion` | `'1.0'` |
| `Tool` | `'ScarWinAdmin.NetworkDiagnostics'` |
| `ComputerName`, `CollectedAtUtc` | host and ISO-8601 UTC timestamp |
| `CollectionStatus` | `Complete` or `Partial` (fatal parameter/platform errors terminate) |
| `TimedOut` | Boolean |
| `Adapters` | structured inventory rows, preserving empty/unknown values |
| `DefaultRoutes` | family, destination, next hop, index and metric |
| `DnsTests` | target, answers, success/failure, elapsed ms, error and timestamp |
| `TcpTests` | target, port, attempted address(es), success/failure, elapsed ms, error and timestamp |
| `Proxy` | source, settings, `Status` (`Collected`/`Unavailable`/`Failed`) |
| `Checks` | each check's `Status`, `Source`, `StartedAtUtc`, `EndedAtUtc`, `Evidence`, `Error` |
| `Findings` | evidence-backed observations, `Severity` and `CheckIds`; do not infer root cause |
| `CollectionErrors` | errors with stage, target and message, never swallowed |
 
Per-check status vocabulary: `Passed`, `Failed`, `Unavailable`, `Skipped`, `TimedOut`. A failed DNS lookup/TCP connection is a **test outcome**, not necessarily a failed collection; `CollectionStatus` may remain `Complete` if all requested checks ran and failures were faithfully recorded. `Partial` means the requested collection was not completed (permissions, unsupported functionality, timeout, truncation, unexpected exception). Overall “network healthy” should **not** be asserted from a small sample of successful tests.

`ConvertTo-Json -Depth 10` must yield a stable shape (arrays remain arrays for zero, one and many items); CSV export requires a documented flattened view, not serialization of nested objects directly.

## 4. Security, privacy and performance

- Read-only local inspection; DNS/TCP probes only for explicitly provided destinations.
- Reject URL schemes, wildcards, IP ranges, CIDR blocks and port ranges as test targets; no implicit network scans.
- Target caps, deadline checks, per-operation timeouts and no unbounded concurrency.
- Do not request elevation by default. On insufficient privilege, produce explicit partial results.
- Proxy, routes, addresses, hostnames and DNS answers may identify internal infrastructure: don't log/upload/transmit results; avoid secrets in exception output.
- No hidden retries, telemetry, network downloads, persistent configuration changes or automatic firewall changes.
- Optional findings are advisory and must cite raw evidence, not speculative diagnosis.

## 5. Packaging / repository changes

- Single source: `src/ScarWinAdmin/Public/Get-ScarNetworkDiagnostics.ps1`.
- Dot-source and export from `ScarWinAdmin.psm1`; update module manifest `FunctionsToExport`.
- Generate standalone `out/scripts/network/Get-NetworkDiagnostics.ps1` via `tooling/Build.ps1`; standalone and module entry points accept the same arguments and emit equivalent schemas.
- Tests in `tests/NetworkDiagnostics.Tests.ps1`; published usage in `docs/tools/network-diagnostics.md`, plus README and changelog updates.
- PowerShell 5.1 and 7 on Windows; PSScriptAnalyzer, Pester and build in GitHub Actions.

## 6. Acceptance criteria / test matrix

Ticked items are covered by an automated test or CI; unticked items are implemented but have no dedicated test yet, or are known gaps (see the [changelog](../../CHANGELOG.md)).

- [x] No user-supplied targets ⇒ no outbound DNS/TCP probes (mock/spy).
- [x] Adapter/route/proxy inventory populates expected typed fields when supported.
- [ ] Zero, one and multiple adapters/routes/targets preserve JSON array shapes.
- [ ] Requested DNS success, NXDOMAIN, timeout and resolver exception are distinguishable.
- [ ] TCP open, refused, unroutable and deadline-expired results contain target+port+evidence.
- [x] Unavailable cmdlets, access-denied, per-check exceptions and exceeded budget yield `Partial` as appropriate rather than a false success.
- [x] Reject unmatched targets/ports, invalid ports, wildcard/range targets and oversized lists before any collection.
- [ ] A failed reachability probe is not conflated with failed collection.
- [ ] Repeated tests respect caps and do not leave undisposed sockets.
- [x] Read-only behavior and opt-in network traffic covered by tests.
- [ ] Both packaged standalone and imported module pass parameter-parity and schema-contract tests.
- [x] Both Windows PowerShell 5.1 and PowerShell 7 CI checks pass; Codex findings addressed before merge.

## 7. Delivery plan

Implement inventory and schema first; add bounded opt-in probes second; then failure handling and tests; finally standalone packaging and docs. Keep each independently testable; avoid a generic networking framework in v0.1. This tool provides **optional network evidence** for WAT-001, not a mandatory prerequisite for the host-health report.
