# Security policy

Do not submit security vulnerabilities as public issues. Use GitHub private vulnerability reporting when available or contact the repository maintainers privately. Never attach unredacted diagnostic logs, credentials, or enterprise configurations. Version 0.x releases have no guaranteed maintenance window.

## Design properties

- **Read-only.** The utilities do not change system state, run remediation, execute downloaded content, or call external services. The only child process is `netsh.exe` (read-only `winhttp show proxy`), started from the Windows system directory.
- **No telemetry, no implicit network traffic.** DNS lookups and TCP connections happen only for targets the caller lists (at most 20 of each). Scanning a UNC path with `Get-ScarDiskUsage -Path` contacts that server, so only scan paths you trust.
- **Bounded work.** Depth, item, event, target and time limits apply everywhere; results that hit a limit or failed to read something are `Partial`. A running Windows API call cannot be cancelled, so a call can overrun its budget.
- **Files written only on request.** The sole writer is `Get-ScarWindowsHealth` with `-OutputJsonPath` / `-OutputHtmlPath`. Paths are validated before collection, existing files are never replaced without `-Force`, and files are created exclusively otherwise. Reports inherit the permissions of the destination folder; choose a location only you or your team can read.
- **HTML reports are static.** Every dynamic value is HTML-encoded; no script, CDN or remote asset is included, and a browser is never opened.
- **Releases are not code-signed** (v0.1.0). Verify the published SHA-256 checksum and read the scripts before running them.

## Handling diagnostic output

Results can contain computer, domain and account names, hostnames and IP addresses, file paths, service names, proxy settings, and event-log messages (which may include user names or file names). JSON output keeps event samples; the HTML report omits event messages. Review and redact output before attaching it to an issue, chat or ticket, and treat saved reports as sensitive.
