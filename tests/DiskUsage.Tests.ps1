$modulePath=Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1'
Describe 'Disk Space Investigator' {
 BeforeAll { Import-Module $modulePath -Force }
 It 'exports Get-ScarDiskUsage' {
  (Get-Command Get-ScarDiskUsage -ErrorAction Stop).Name | Should -Be 'Get-ScarDiskUsage'
 }
 It 'rejects inverted thresholds' {
  { Get-ScarDiskUsage -WarningFreePercent 10 -CriticalFreePercent 20 } | Should -Throw
 }
 It 'uses byte counts and thresholds for volume severity on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-CimInstance { @([pscustomobject]@{DeviceID='C:';Size=1000;FreeSpace=50}) }
  $r=Get-ScarDiskUsage
  $r.Volumes[0].FreePercent | Should -Be 5
  $r.Volumes[0].Severity | Should -Be 'Critical'
 }
 It 'uses a read-only bounded scan of a fixture directory on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $dir=Join-Path $TestDrive 'fixture'
  New-Item -ItemType Directory -Path $dir | Out-Null
  Set-Content -LiteralPath (Join-Path $dir 'sample.txt') -Value 'sample'
  $r=Get-ScarDiskUsage -Path $dir -MaxDepth 1 -MaxItems 20 -TimeoutSeconds 5
  $r.ScannedItems | Should -BeGreaterThan 0
  $r.TopFiles.Count | Should -BeGreaterThan 0
 }
 It 'reports an invalid path as Partial rather than a passing scan on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $r=Get-ScarDiskUsage -Path (Join-Path $TestDrive 'missing')
  $r.CollectionStatus | Should -Be 'Partial'
  $r.CollectionErrors.Count | Should -BeGreaterThan 0
 }
}
