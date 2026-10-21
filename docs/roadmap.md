# Roadmap

## v0.1: first five utilities (released as 0.1.0)
1. Pending Reboot Inspector
2. Disk Space Investigator
3. Event Log Investigator
4. [Network Diagnostics Bundle (WAT-004)](specifications/WAT-004-network-diagnostics.md)
5. [Windows Health Snapshot (WAT-001)](specifications/WAT-001-windows-health.md)

The WAT-004 and WAT-001 specifications are the implementation contracts. Known gaps against them are listed in the [changelog](../CHANGELOG.md#010---2026-10-21).

## v0.2: security and inventory
Certificate expiration, local administrator membership, scheduled tasks, service health, remote inventory.

## v0.3: enterprise maintenance
AD account lockout, stale AD objects, Windows Update diagnostics, BitLocker, installed software.

## v0.4 and v1.0
Uptime history, file-server cleanup, permissions, GPO, and configuration comparison. Stable release depends on validation rather than tool counts.

All utilities are free, open source, and initially read-only. Standalone scripts and a PowerShell module must have equivalent behavior.
