Describe 'Release package' -Skip:($env:OS -ne 'Windows_NT') {
 BeforeDiscovery {
  $scripts=@(
   @{ Name='Pending Reboot'; Relative='scripts/maintenance/Test-PendingReboot.ps1'; Arguments=''; Tool='ScarWinAdmin.PendingReboot' }
   @{ Name='Disk Usage'; Relative='scripts/storage/Get-DiskUsage.ps1'; Arguments=''; Tool='ScarWinAdmin.DiskUsage' }
   @{ Name='Event Summary'; Relative='scripts/diagnostics/Get-WindowsEventSummary.ps1'; Arguments='-LookbackHours 1 -MaxEventsPerLog 5 -TimeoutSeconds 30'; Tool='ScarWinAdmin.EventSummary' }
   @{ Name='Network Diagnostics'; Relative='scripts/network/Get-NetworkDiagnostics.ps1'; Arguments='-SkipProxy -TimeoutSeconds 30'; Tool='ScarWinAdmin.NetworkDiagnostics' }
   @{ Name='Windows Health'; Relative='scripts/health/Get-WindowsHealth.ps1'; Arguments='-EventLookbackHours 1 -MaxEventsPerLog 5 -TimeoutSeconds 60'; Tool='ScarWinAdmin.WindowsHealth' }
  )
 }
 BeforeAll {
  $script:dist=Join-Path $TestDrive 'dist'
  & (Join-Path $PSScriptRoot '../tooling/Package.ps1') -OutputDirectory $script:dist | Out-Null
  $script:version=(Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1')).ModuleVersion
  $script:name="ScarWinAdmin-v$($script:version)"
  $script:zip=Join-Path $script:dist "$($script:name).zip"
  $script:extract=Join-Path $TestDrive 'extracted'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($script:zip,$script:extract)
  $script:package=Join-Path $script:extract $script:name
  # Same PowerShell edition as the one running the tests (Windows PowerShell 5.1 or PowerShell 7).
  $script:shellExe=(Get-Process -Id $PID).Path
  function script:Invoke-Isolated {
   param([string]$Command)
   $isolated=Join-Path $TestDrive ('isolated-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $isolated | Out-Null
   $output=& $script:shellExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $Command 2>&1
   [pscustomobject]@{ExitCode=$LASTEXITCODE;Text=($output | Out-String)}
  }
 }
 It 'publishes a checksum file that matches the archive' {
  $line=(Get-Content -LiteralPath (Join-Path $script:dist 'SHA256SUMS.txt') -Raw).Trim()
  $line | Should -Be ((Get-FileHash -LiteralPath $script:zip -Algorithm SHA256).Hash.ToLowerInvariant()+"  $($script:name).zip")
 }
 It 'contains the module, all standalone scripts, docs and license and nothing else' {
  $zip=[IO.Compression.ZipFile]::OpenRead($script:zip)
  try { $entries=@($zip.Entries | ForEach-Object FullName) } finally { $zip.Dispose() }
  $entries | Where-Object { $_ -match '\\' } | Should -BeNullOrEmpty -Because 'entry names must use forward slashes'
  foreach($required in 'LICENSE','README.md','CHANGELOG.md','SECURITY.md','module/ScarWinAdmin/ScarWinAdmin.psd1','module/ScarWinAdmin/ScarWinAdmin.psm1','module/ScarWinAdmin/Public/Get-ScarWindowsHealth.ps1','scripts/health/Get-WindowsHealth.ps1','docs/tools/windows-health.md','docs/installation.md'){
   $entries | Should -Contain "$($script:name)/$required"
  }
  @($entries | Where-Object { $_ -match '/(tests|tooling|\.git|\.github|out|dist)/|AGENTS\.md' }) | Should -BeNullOrEmpty
 }
 It 'rebuilds byte-identical output from the same source on the same PowerShell edition' {
  $again=Join-Path $TestDrive 'dist-again'
  & (Join-Path $PSScriptRoot '../tooling/Package.ps1') -OutputDirectory $again | Out-Null
  (Get-FileHash -LiteralPath (Join-Path $again "$($script:name).zip")).Hash | Should -Be (Get-FileHash -LiteralPath $script:zip).Hash
 }
 It 'imports the extracted module in a fresh process and exports every command' {
  $manifest=Join-Path $script:package 'module/ScarWinAdmin/ScarWinAdmin.psd1'
  $run=Invoke-Isolated "Import-Module '$manifest' -ErrorAction Stop; (Get-Command -Module ScarWinAdmin | Sort-Object Name | ForEach-Object Name) -join ','"
  $run.ExitCode | Should -Be 0
  $run.Text.Trim() | Should -Be 'Get-ScarDiskUsage,Get-ScarEventSummary,Get-ScarNetworkDiagnostics,Get-ScarWindowsHealth,Test-ScarPendingReboot'
 }
 It 'runs the standalone <Name> script alone, without the module, and returns schema v1 output' -ForEach $scripts {
  # Copy only the one script into an empty directory so nothing else from the package or repo is reachable.
  $alone=Join-Path $TestDrive ('alone-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $alone | Out-Null
  $file=Join-Path $alone (Split-Path -Leaf $Relative)
  Copy-Item -LiteralPath (Join-Path $script:package $Relative) -Destination $file
  $command="Set-Location -LiteralPath '$alone'; if((Get-Module ScarWinAdmin) -or (Get-Command Get-Scar* -ErrorAction SilentlyContinue)){throw 'module commands already available'}; & '$file' $Arguments | ConvertTo-Json -Depth 16 -Compress"
  $run=Invoke-Isolated $command
  $run.ExitCode | Should -Be 0 -Because $run.Text
  $result=$run.Text | ConvertFrom-Json
  $result.SchemaVersion | Should -Be '1.0'
  $result.Tool | Should -Be $Tool
  (Get-Content -LiteralPath $file -TotalCount 1) | Should -Match '^# Generated from|^\[CmdletBinding\(\)\]'
 }
}
