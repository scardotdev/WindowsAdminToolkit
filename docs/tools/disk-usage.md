# WAT-003 — Disk Space Investigator

Read-only volume inventory and optional bounded file scan.

## Use

```powershell
Import-Module ./src/ScarWinAdmin/ScarWinAdmin.psd1
Get-ScarDiskUsage
Get-ScarDiskUsage -Path 'C:\Logs' -MaxDepth 2 -MaxItems 10000 -TimeoutSeconds 30 -Top 10
./tooling/Build.ps1
./out/scripts/storage/Get-DiskUsage.ps1 -Path 'C:\Logs'
```

No file traversal occurs unless `-Path` is provided. The scanner avoids reparse-point traversal, and never deletes files. It counts discovered entries and limits scanning by depth, item count and duration. Directory sizes are not presented as exhaustive if any directories are skipped, the time budget is exceeded or permissions fail. TopFiles ranks observed files only, not every file on the disk.

Volume free-space severity uses configurable percentages; thresholds are heuristics and can be inappropriate for some workloads. The output is a structured PowerShell object suitable for ConvertTo-Json/Export-Csv projections. External volumes, cluster storage, inaccessible trees and filesystem features may need specialized tools.

## Known limitations
- Scans collect directory entries in batches via Get-ChildItem; a single huge directory listing may exceed the requested time budget before control returns.
- Listing files exposes names and paths that may be sensitive.
- No directory aggregation or longitudinal growth detection in this version.
- The tool does not attempt privileged filesystem bypass.
