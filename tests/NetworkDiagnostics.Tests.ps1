Describe 'Network Diagnostics Bundle' {
 BeforeAll {
  $modulePath=Join-Path $PSScriptRoot '../src/ScarWinAdmin/ScarWinAdmin.psd1'
  Import-Module $modulePath -Force
 }
 It 'exports the network diagnostics command' {
  (Get-Command Get-ScarNetworkDiagnostics).Name | Should -Be 'Get-ScarNetworkDiagnostics'
 }
 It 'rejects unmatched TCP host and port arguments without probing' {
  {Get-ScarNetworkDiagnostics -TcpTarget 'localhost'} | Should -Throw
 }
 It 'rejects scanning ranges' {
  {Get-ScarNetworkDiagnostics -DnsTarget '192.168.0.0/24'} | Should -Throw
 }
 It 'collects a local-only inventory without DNS or TCP probes on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-NetAdapter {@([pscustomobject]@{Name='Ethernet';InterfaceDescription='Test';ifIndex=1;Status='Up';MacAddress='00-00'})}
  Mock -ModuleName ScarWinAdmin Get-NetIPConfiguration {@()}
  Mock -ModuleName ScarWinAdmin Get-NetRoute {@()}
  $result=Get-ScarNetworkDiagnostics -SkipProxy
  $result.Adapters.Count | Should -Be 1
  $result.DnsTests.Count | Should -Be 0
  $result.TcpTests.Count | Should -Be 0
 }
 It 'treats missing inventory capability as partial on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-NetAdapter {throw 'Unavailable'}
  Mock -ModuleName ScarWinAdmin Get-NetIPConfiguration {@()}
  Mock -ModuleName ScarWinAdmin Get-NetRoute {@()}
  $result=Get-ScarNetworkDiagnostics -SkipProxy
  $result.CollectionStatus | Should -Be 'Partial'
 }
 It 'reports a connected address for a TCP probe on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-NetAdapter {@()}
  Mock -ModuleName ScarWinAdmin Get-NetIPConfiguration {@()}
  Mock -ModuleName ScarWinAdmin Get-NetRoute {@()}
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $listener.Start()
  try {
   $port=([Net.IPEndPoint]$listener.LocalEndpoint).Port
   $result=Get-ScarNetworkDiagnostics -SkipProxy -TcpTarget '127.0.0.1' -TcpPort $port
  } finally { $listener.Stop() }
  $result.TcpTests[0].Status | Should -Be 'Passed'
  $result.TcpTests[0].ConnectedAddress | Should -Be '127.0.0.1'
 }
 It 'resolves an explicit DNS target within the deadline on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-NetAdapter {@()}
  Mock -ModuleName ScarWinAdmin Get-NetIPConfiguration {@()}
  Mock -ModuleName ScarWinAdmin Get-NetRoute {@()}
  $result=Get-ScarNetworkDiagnostics -SkipProxy -DnsTarget '127.0.0.1'
  $result.DnsTests[0].Status | Should -Be 'Passed'
  $result.DnsTests[0].Answers | Should -Contain '127.0.0.1'
 }
 It 'reports a budget overrun even when no probe was skipped on Windows' -Skip:($env:OS -ne 'Windows_NT') {
  Mock -ModuleName ScarWinAdmin Get-NetAdapter { Start-Sleep -Milliseconds 1200; @() }
  Mock -ModuleName ScarWinAdmin Get-NetIPConfiguration {@()}
  Mock -ModuleName ScarWinAdmin Get-NetRoute {@()}
  $result=Get-ScarNetworkDiagnostics -SkipProxy -TimeoutSeconds 1
  $result.TimedOut | Should -BeTrue
  $result.CollectionStatus | Should -Be 'Partial'
 }
}
