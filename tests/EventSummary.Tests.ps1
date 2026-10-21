BeforeAll { Import-Module (Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1') -Force }
Describe 'Windows Event Log Investigator' {
 It 'exports the public command' {
  (Get-Command Get-ScarEventSummary).Name | Should -Be 'Get-ScarEventSummary'
 }
 It 'groups recurring events and retains evidence on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-WinEvent {
   @(
    [pscustomobject]@{ProviderName='Example';Id=42;Level=2;TimeCreated=[datetime]'2026-10-20T12:00:00Z';RecordId=2;MachineName='PC';Message='two'}
    [pscustomobject]@{ProviderName='Example';Id=42;Level=2;TimeCreated=[datetime]'2026-10-20T11:00:00Z';RecordId=1;MachineName='PC';Message='one'}
   )
  }
  $result=Get-ScarEventSummary -LogName System -MaxEventsPerLog 20
  $result.CollectionStatus | Should -Be 'Complete'
  $result.GroupedEvents[0].Count | Should -Be 2
  $result.GroupedEvents[0].EventId | Should -Be 42
 }
 It 'does not report access failures as complete on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-WinEvent { throw 'Access denied' }
  $result=Get-ScarEventSummary -LogName System
  $result.CollectionStatus | Should -Be 'Partial'
  $result.CollectionErrors.Count | Should -Be 1
 }
 It 'marks capped results partial on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-WinEvent {
   @(
    [pscustomobject]@{ProviderName='Example';Id=1;Level=2;TimeCreated=[datetime]::UtcNow;RecordId=1;MachineName='PC';Message='one'}
    [pscustomobject]@{ProviderName='Example';Id=1;Level=2;TimeCreated=[datetime]::UtcNow;RecordId=2;MachineName='PC';Message='two'}
   )
  }
  $result=Get-ScarEventSummary -LogName System -MaxEventsPerLog 1
  $result.CollectionStatus | Should -Be 'Partial'
  $result.Logs[0].Capped | Should -BeTrue
 }
}
