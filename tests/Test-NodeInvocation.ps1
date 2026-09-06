param([string]$NodePath = 'node')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Repair-ChatGPTChrome.ps1')
$sample = 'C:\example user\中文\quoted "name"\node.exe'
$encoded = $sample | ConvertTo-Json -Compress
$result = Invoke-NodeModule -NodePath $NodePath -JavaScript "console.log(JSON.stringify(Array.from($encoded, c => c.charCodeAt(0))));"
if (((($result | ConvertFrom-Json) -join ',') -cne ([int[]][char[]]$sample -join ','))) { throw 'Node invocation changed Unicode, quotes or backslashes.' }
$failed = $false
try { Invoke-NodeModule -NodePath $NodePath -JavaScript 'process.exit(7)' }
catch { $failed = $_.Exception.Message -like '*code 7*' }
if (-not $failed) { throw 'Node exit failure was not propagated.' }
Write-Output 'PASS: real Node preserves quotes, Unicode and backslashes; nonzero exit is propagated.'

# The intentional failure above must not leak into CI's wrapper exit status.
exit 0
