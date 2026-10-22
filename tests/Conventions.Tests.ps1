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

# Guards against documentation drifting from the shipped version.
Describe 'Release documentation' {
 BeforeAll {
  $script:root=Join-Path $PSScriptRoot '..'
  $script:version=(Import-PowerShellDataFile -LiteralPath (Join-Path $script:root 'src/ScarWinAdmin/ScarWinAdmin.psd1')).ModuleVersion
 }
 It 'has a dated changelog section for the module version' {
  Get-Content -Raw -LiteralPath (Join-Path $script:root 'CHANGELOG.md') | Should -Match ('(?m)^## '+[regex]::Escape($script:version)+' - \d{4}-\d{2}-\d{2}\s*$')
 }
 It 'does not carry stale status wording in the README or specifications' {
  $text=(Get-Content -Raw -LiteralPath (Join-Path $script:root 'README.md'))+(Get-ChildItem -Path (Join-Path $script:root 'docs') -Recurse -Filter *.md | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName })
  $text | Should -Not -Match '(?i)neither is yet validated|Proposed for v0|Early development\. No stable release'
 }
 It 'links every relative Markdown target in the README' {
  $readme=Get-Content -Raw -LiteralPath (Join-Path $script:root 'README.md')
  $targets=[regex]::Matches($readme,'\]\(((?!https?:|#)[^)\s]+)\)') | ForEach-Object { ($_.Groups[1].Value -split '#')[0] } | Sort-Object -Unique
  foreach($target in $targets){ Test-Path -LiteralPath (Join-Path $script:root $target) | Should -BeTrue -Because "README links to $target" }
 }
}
