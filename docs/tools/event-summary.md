# WAT-005 — Windows Event Log Investigator

Read-only triage for Windows System and Application event logs. Uses Get-WinEvent and groups events by log, provider, event ID and level; returns first/last occurrence and representative messages.

```powershell
Import-Module ./src/ScarWinAdmin/ScarWinAdmin.psd1
Get-ScarEventSummary -LookbackHours 24 -MaxEventsPerLog 1000
Get-ScarEventSummary -LogName System -EventId 7031,7034
Get-ScarEventSummary | ConvertTo-Json -Depth 10 | Set-Content events.json
./tooling/Build.ps1
./out/scripts/diagnostics/Get-WindowsEventSummary.ps1 -LogName System
```

**Controls:** bounded per-log count, lookback, timeout checks, top groups and samples. Access failures and capped queries produce `Partial` status, not a healthy result. High event frequency is not proof of causation.

**Limitations:** A Get-WinEvent call itself is not cancellable by the time budget; some log providers may take longer than the configured timeout. Messages can contain hostnames, account names or other sensitive data: review reports before sharing. No automated remediation or telemetry. The command does not claim that an incomplete query is exhaustive.
