Describe 'Windows Health Snapshot' {
 BeforeAll {
  $modulePath=Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1'
  Import-Module $modulePath -Force
 }
 It 'exports the health command' {
  (Get-Command Get-ScarWindowsHealth).Name | Should -Be 'Get-ScarWindowsHealth'
 }
 It 'rejects inverted thresholds before collection' {
  {Get-ScarWindowsHealth -CriticalDiskFreePercent 50 -WarningDiskFreePercent 20} | Should -Throw
  {Get-ScarWindowsHealth -CriticalMemoryUsedPercent 80 -WarningMemoryUsedPercent 95} | Should -Throw
 }
 It 'builds the result and propagates partial child coverage on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-CimInstance {
   if($ClassName -eq 'Win32_OperatingSystem') {
    return [pscustomobject]@{Caption='Windows';Version='10';BuildNumber='1';LastBootUpTime=[datetime]::Now.AddHours(-8);FreePhysicalMemory=500000}
   }
   if($ClassName -eq 'Win32_ComputerSystem') {
    return [pscustomobject]@{TotalPhysicalMemory=1000000000;Manufacturer='Test';Model='Machine'}
   }
   return [pscustomobject]@{LoadPercentage=5}
  }
  Mock -ModuleName ScarWinAdmin Get-ScarDiskUsage {
   [pscustomobject]@{CollectionStatus='Partial';Volumes=@([pscustomobject]@{Drive='C:';FreePercent=4;Severity='Critical'})}
  }
  Mock -ModuleName ScarWinAdmin Test-ScarPendingReboot {[pscustomobject]@{Status='Indeterminate'}}
  Mock -ModuleName ScarWinAdmin Get-ScarEventSummary {[pscustomobject]@{CollectionStatus='Complete';GroupedEvents=@()}}
  $result=Get-ScarWindowsHealth
  $result.CollectionStatus | Should -Be 'Partial'
  $result.HealthStatus | Should -Be 'Critical'
  $result.Findings.Count | Should -BeGreaterThan 0
  $result.SourceStatus.Count | Should -BeGreaterThan 2
  $result.CollectionErrors.Count | Should -BeGreaterThan 0
 }
 It 'rejects existing report paths without Force on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $path=Join-Path $TestDrive 'existing.json'
  Set-Content -LiteralPath $path -Value 'existing'
  {Get-ScarWindowsHealth -OutputJsonPath $path} | Should -Throw
 }
 It 'does not run optional network inventory by default on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-ScarNetworkDiagnostics {throw 'Network should not run'}
  Mock -ModuleName ScarWinAdmin Get-CimInstance {throw 'Not available'}
  Mock -ModuleName ScarWinAdmin Get-ScarDiskUsage {throw 'Unavailable'}
  Mock -ModuleName ScarWinAdmin Test-ScarPendingReboot {throw 'Unavailable'}
  Mock -ModuleName ScarWinAdmin Get-ScarEventSummary {throw 'Unavailable'}
  $result=Get-ScarWindowsHealth
  $result.HealthStatus | Should -Be 'Unknown'
  Should -Invoke Get-ScarNetworkDiagnostics -ModuleName ScarWinAdmin -Exactly -Times 0
 }
}
