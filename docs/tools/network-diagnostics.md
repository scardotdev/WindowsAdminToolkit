# WAT-004 — Network Diagnostics Bundle

Read-only local adapter, IP configuration, route and WinHTTP proxy inventory, with **opt-in** DNS and TCP tests.

```powershell
Import-Module ./src/ScarWinAdmin/ScarWinAdmin.psd1
Get-ScarNetworkDiagnostics
Get-ScarNetworkDiagnostics -DnsTarget 'intranet.example' -TcpTarget 'intranet.example' -TcpPort 443
./tooling/Build.ps1
./out/scripts/network/Get-NetworkDiagnostics.ps1 -SkipProxy
```

No outbound probes are issued unless `-DnsTarget` or `-TcpTarget` is supplied. Outputs are structured and can be converted with `ConvertTo-Json -Depth 10`. A failed explicit TCP/DNS probe is a valid observed test outcome; unavailable inventory or uncollected requested tests produce partial results.

## Limitations and privacy

- `TimeoutSeconds` is best-effort. Synchronous DNS lookup and Windows inventory calls cannot be forcibly interrupted, and may exceed the requested time budget. TCP attempts use per-test deadlines and disposed clients.
- `-SkipRoutes` and `-SkipProxy` omit those inventories. `-IncludeIPv6` adds IPv6 default routes.
- The WinHTTP proxy setting is not a complete picture of browser/user proxy configurations.
- Adapters, DNS, proxy and routes may expose internal infrastructure. Review results before sharing.
- No configuration changes, telemetry, external public-IP lookups or automatic remediation.
- This initial implementation does not yet cover every acceptance criterion in the [WAT-004 specification](../specifications/WAT-004-network-diagnostics.md); CI and review are release gates.
