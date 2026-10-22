# Installation and verification

New to this? Follow the step-by-step [quick-start guide in the README](../README.md#quick-start-guide-no-experience-needed) instead.

Requirements: Windows with Windows PowerShell 5.1 or PowerShell 7. No elevation is required; sections that need more permission report `Partial` instead of failing silently. No internet access is needed after download.

## From a release

1. Download `ScarWinAdmin-v<version>.zip` and `SHA256SUMS.txt` from the GitHub release page.
2. Verify the checksum (the printed hash must equal the value in `SHA256SUMS.txt`):
   ```powershell
   (Get-FileHash .\ScarWinAdmin-v*.zip -Algorithm SHA256).Hash.ToLower()
   Get-Content .\SHA256SUMS.txt
   ```
   The checksum only proves the file matches what was published alongside it. Releases are **not code-signed**.
3. Remove the "downloaded from the internet" mark, then extract:
   ```powershell
   Unblock-File .\ScarWinAdmin-v*.zip
   Expand-Archive .\ScarWinAdmin-v*.zip -DestinationPath .
   ```
4. Read the scripts before running them; they are plain text.

## Use the module

```powershell
Import-Module .\ScarWinAdmin-v*\module\ScarWinAdmin\ScarWinAdmin.psd1
Get-Command -Module ScarWinAdmin
```

To keep it available, copy the `ScarWinAdmin` folder into a directory listed in `$env:PSModulePath` (for example `$HOME\Documents\PowerShell\Modules` for PowerShell 7 or `$HOME\Documents\WindowsPowerShell\Modules` for Windows PowerShell). To uninstall, delete that folder.

## Use a standalone script

Each script under `scripts\` is self-contained (it embeds the code it needs) and does not require the module:

```powershell
.\ScarWinAdmin-v*\scripts\health\Get-WindowsHealth.ps1 -ServiceName Spooler
```

If your execution policy blocks it, keep the unblock step above and use `RemoteSigned`, or run a single process with `powershell -ExecutionPolicy Bypass -File <script>`. Do not weaken the machine-wide policy for this toolkit.

## Saving results

```powershell
Get-ScarEventSummary | ConvertTo-Json -Depth 16 | Set-Content events.json -Encoding UTF8
```

Results can contain machine, account and host names, paths and event messages. Store and share them accordingly.

## Build from source

```powershell
git clone https://github.com/scardotdev/WindowsAdminToolkit.git
cd WindowsAdminToolkit
.\tooling\Build.ps1       # out\scripts\... and out\ScarWinAdmin
.\tooling\Package.ps1     # dist\ScarWinAdmin-v<version>.zip and dist\SHA256SUMS.txt
.\tooling\Test.ps1        # PSScriptAnalyzer + Pester 5 (Pester 5.7.1 and PSScriptAnalyzer must be installed)
```

The archive is deterministic for the same source and PowerShell edition; different editions may compress to different bytes.
