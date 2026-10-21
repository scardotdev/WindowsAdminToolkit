# Guards against two bugs that passed local review but broke CI (see PRs #2, #3, #5).
Describe 'Repository conventions' {
 BeforeDiscovery {
  $root=Join-Path $PSScriptRoot '..'
  $sources=@(Get-ChildItem -Path (Join-Path $root 'src') -Recurse -Filter *.ps1 | ForEach-Object { @{ Name=$_.Name; Path=$_.FullName } })
  $tests=@(Get-ChildItem -Path $PSScriptRoot -Filter *.Tests.ps1 | ForEach-Object { @{ Name=$_.Name; Path=$_.FullName } })
 }
 It 'does not wrap a generic List in @() (throws "Argument types do not match" in a result object): <Name>' -ForEach $sources {
  $text=Get-Content -Raw -LiteralPath $Path
  $lists=[regex]::Matches($text,'\$(\w+)\s*=\s*New-Object\s+.System\.Collections\.Generic\.List') | ForEach-Object { $_.Groups[1].Value }
  foreach($name in $lists){ $text | Should -Not -Match ('@\(\s*\$'+$name+'\s*\)') -Because "use `$$name.ToArray() instead" }
 }
 It 'does not set variables at file level in test files (not visible during Run in Pester 5): <Name>' -ForEach $tests {
  $lines=Get-Content -LiteralPath $Path | Where-Object { $_ -match '^\$\w+\s*=' }
  $lines | Should -BeNullOrEmpty -Because 'assign inside BeforeAll'
 }
}
