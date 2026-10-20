$modulePath=Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1'
Describe 'ScarWinAdmin Pending Reboot' {
 It 'exports the pending reboot command' {
  Import-Module $modulePath -Force
  (Get-Command Test-ScarPendingReboot -ErrorAction Stop).Name | Should -Be 'Test-ScarPendingReboot'
 }
 It 'returns the expected status and evidence on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  $r=Test-ScarPendingReboot
  @('Pending','NotDetected','Indeterminate') | Should -Contain $r.Status
  $r.Indicators.Count | Should -Be 5
 }
}
