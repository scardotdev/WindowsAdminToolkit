BeforeAll { Import-Module (Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1') -Force }
Describe 'ScarWinAdmin Pending Reboot' {
 It 'exports the pending reboot command' {
  (Get-Command Test-ScarPendingReboot -ErrorAction Stop).Name | Should -Be 'Test-ScarPendingReboot'
 }
 It 'returns the expected status and evidence on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $r=Test-ScarPendingReboot
  @('Pending','NotDetected','Indeterminate') | Should -Contain $r.Status
  $r.Indicators.Count | Should -Be 5
 }
}

Describe 'Pending file rename registry probe' -Skip:($env:OS -ne 'Windows_NT') {
 It 'returns Indeterminate when registry reads fail instead of a false negative' {
  Mock -ModuleName ScarWinAdmin Test-Path { $false }
  Mock -ModuleName ScarWinAdmin Get-ItemProperty { throw 'Simulated registry access denied' }
  $result=Test-ScarPendingReboot
  $result.Status | Should -Be 'Indeterminate'
  ($result.Indicators | Where-Object Name -eq 'SessionManager.PendingFileRenameOperations').Status | Should -Be 'Indeterminate'
 }
 It 'reports a genuinely missing pending file rename value as NotDetected' {
  Mock -ModuleName ScarWinAdmin Test-Path { $false }
  Mock -ModuleName ScarWinAdmin Get-ItemProperty {
   if ($LiteralPath -like '*Session Manager') { return [pscustomobject]@{} }
   return [pscustomobject]@{ ComputerName='TESTPC' }
  }
  $result=Test-ScarPendingReboot
  ($result.Indicators | Where-Object Name -eq 'SessionManager.PendingFileRenameOperations').Status | Should -Be 'NotDetected'
 }
 It 'detects pending file rename operations when present' {
  Mock -ModuleName ScarWinAdmin Test-Path { $false }
  Mock -ModuleName ScarWinAdmin Get-ItemProperty {
   if ($LiteralPath -like '*Session Manager') { return [pscustomobject]@{ PendingFileRenameOperations=@('a','b') } }
   return [pscustomobject]@{ ComputerName='TESTPC' }
  }
  $result=Test-ScarPendingReboot
  $result.Status | Should -Be 'Pending'
  ($result.Indicators | Where-Object Name -eq 'SessionManager.PendingFileRenameOperations').Status | Should -Be 'Detected'
 }
}
