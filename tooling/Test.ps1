[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -ListAvailable Pester)) { throw 'Pester is required. Install a supported version before running tests.' }
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { throw 'PSScriptAnalyzer is required. Install it before running tests.' }
Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Severity Error -ReportSummary | ForEach-Object { throw ($_ | Out-String) }
Invoke-Pester -Path (Join-Path $root 'tests') -EnableExit
