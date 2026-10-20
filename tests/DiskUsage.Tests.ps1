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

Describe 'Reparse point protections' -Skip:($env:OS -ne 'Windows_NT') {
 BeforeAll { Import-Module $modulePath -Force }
 It 'rejects a reparse-point root and reports a partial collection' {
  $dir=Join-Path $TestDrive 'linked-root'
  New-Item -ItemType Directory -Path $dir | Out-Null
  Mock -ModuleName ScarWinAdmin Get-Item {
   [pscustomobject]@{
    FullName=$dir
    PSIsContainer=$true
    Attributes=[IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
   }
  }
  $result=Get-ScarDiskUsage -Path $dir
  $result.CollectionStatus | Should -Be 'Partial'
  $result.CollectionErrors -join ' ' | Should -Match 'reparse point'
  $result.ScannedItems | Should -Be 0
 }
 It 'reports a skipped reparse-point child as partial' {
  $dir=Join-Path $TestDrive 'linked-child'
  New-Item -ItemType Directory -Path $dir | Out-Null
  Mock -ModuleName ScarWinAdmin Get-ChildItem {
   @([pscustomobject]@{
    FullName=(Join-Path $dir 'junction')
    PSIsContainer=$true
    Attributes=[IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint
   })
  }
  $result=Get-ScarDiskUsage -Path $dir -MaxDepth 1
  $result.CollectionStatus | Should -Be 'Partial'
  $result.ScanTruncated | Should -BeTrue
  $result.CollectionErrors -join ' ' | Should -Match 'Skipped reparse point'
 }
}
