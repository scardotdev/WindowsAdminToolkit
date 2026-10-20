[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
Import-Module PSScriptAnalyzer -ErrorAction Stop
$issues=@(Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Severity Error)
if ($issues.Count -gt 0) { throw ($issues | Out-String) }
$config=New-PesterConfiguration
$config.Run.Path=Join-Path $root 'tests'
$config.Run.PassThru=$true
$config.Output.Verbosity='Detailed'
$result=Invoke-Pester -Configuration $config
if ($null -eq $result -or $result.FailedCount -gt 0) { throw 'Pester validation failed.' }
