[CmdletBinding()]
param([string]$OutputDirectory)
# Builds dist/ScarWinAdmin-v<version>.zip and SHA256SUMS.txt from the repository. Read-only for the source tree.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
# $PSScriptRoot is empty inside param defaults on Windows PowerShell 5.1, so default here.
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root 'dist' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$version=(Import-PowerShellDataFile -LiteralPath (Join-Path $root 'src/ScarWinAdmin/ScarWinAdmin.psd1')).ModuleVersion
$name="ScarWinAdmin-v$version"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work=Join-Path ([IO.Path]::GetTempPath()) ('scar-package-'+[guid]::NewGuid().ToString('N'))
try {
 $built=Join-Path $work 'build'
 & (Join-Path $PSScriptRoot 'Build.ps1') -OutputDirectory $built | Out-Null
 # (source file, path inside the archive). Sorted so the archive layout is deterministic.
 $entries=New-Object 'System.Collections.Generic.List[object]'
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $built 'ScarWinAdmin') -Recurse -File){
  $relative=$file.FullName.Substring((Join-Path $built 'ScarWinAdmin').Length).TrimStart('\','/') -replace '\\','/'
  $entries.Add(@{Source=$file.FullName;Entry="$name/module/ScarWinAdmin/$relative"})
 }
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $built 'scripts') -Recurse -File){
  $relative=$file.FullName.Substring((Join-Path $built 'scripts').Length).TrimStart('\','/') -replace '\\','/'
  $entries.Add(@{Source=$file.FullName;Entry="$name/scripts/$relative"})
 }
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'docs/tools') -File -Filter *.md){
  $entries.Add(@{Source=$file.FullName;Entry="$name/docs/tools/$($file.Name)"})
 }
 $entries.Add(@{Source=(Join-Path $root 'docs/installation.md');Entry="$name/docs/installation.md"})
 foreach($top in 'LICENSE','README.md','CHANGELOG.md','SECURITY.md'){
  $entries.Add(@{Source=(Join-Path $root $top);Entry="$name/$top"})
 }
 $zipPath=Join-Path $OutputDirectory "$name.zip"
 if(Test-Path -LiteralPath $zipPath){Remove-Item -LiteralPath $zipPath -Force}
 $fixedTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
 $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
 try {
  foreach($item in ($entries | Sort-Object { $_.Entry })){
   $entry=$zip.CreateEntry($item.Entry,[IO.Compression.CompressionLevel]::Optimal)
   $entry.LastWriteTime=$fixedTime
   $in=[IO.File]::OpenRead($item.Source)
   try{$out=$entry.Open();try{$in.CopyTo($out)}finally{$out.Dispose()}}finally{$in.Dispose()}
  }
 } finally {$zip.Dispose()}
 $hash=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
 $sumsPath=Join-Path $OutputDirectory 'SHA256SUMS.txt'
 [IO.File]::WriteAllText($sumsPath,"$hash  $name.zip`n",[Text.UTF8Encoding]::new($false))
 Write-Output "Packaged $zipPath"
 Write-Output "SHA256 $hash"
} finally {
 if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
}
