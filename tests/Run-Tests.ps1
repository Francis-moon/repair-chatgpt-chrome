# No dependency on Pester; runs in Windows PowerShell 5.1 and PowerShell 7.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Repair-ChatGPTChrome.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('chrome-repair-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$script:passed = 0
function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Output "PASS: $Name"
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Name) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-Test ($null -ne $caught -and $caught -like $Pattern) $Name
}
function Set-FixtureFile([string]$Path, [string]$Text = 'fixture') {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
# Registry and process discovery are OS boundaries; fixtures never write HKCU or stop processes.
function Get-ItemPropertyValue { param($LiteralPath, $Name) return $script:fixtureRegistry }
function Get-DesktopRootProcess { param($InstallLocation) return [pscustomobject]@{ ProcessId = $PID } }
$package = [pscustomobject]@{
    PluginVersion = '1.2.3'
    PluginSource = Join-Path $fixtureRoot 'package\chrome'
    ResourcesPath = Join-Path $fixtureRoot 'package'
    Package = [pscustomobject]@{ Version = '1.0.0.0'; InstallLocation = Join-Path $fixtureRoot 'package' }
}
$testCodex = Join-Path $fixtureRoot 'profile with spaces\codex'
$runtime = [pscustomobject]@{
    LocalAppData = Join-Path $fixtureRoot 'local'
    NodePath = Join-Path $fixtureRoot 'runtime\node.exe'
    NodeReplPath = Join-Path $fixtureRoot 'runtime\node_repl.exe'
    CodexCliPath = Join-Path $fixtureRoot 'runtime\codex.exe'
    NodeModuleDirectory = Join-Path $fixtureRoot 'runtime\node_modules'
}
$cache = Join-Path $testCodex 'plugins\cache\openai-bundled\chrome'
$target = Join-Path $cache '1.2.3'
$latest = Join-Path $cache 'latest'
function Report { Get-DiagnosticReport -PackageContext $package -RuntimeContext $runtime -CodexHome $testCodex }
try {
    foreach ($relative in @('scripts\installManifest.mjs','scripts\browser-client.mjs','scripts\browser-service.mjs','extension-host\windows\x64\extension-host.exe')) {
        Set-FixtureFile (Join-Path $package.PluginSource $relative)
    }
    foreach ($path in @($runtime.NodePath,$runtime.NodeReplPath,$runtime.CodexCliPath)) { Set-FixtureFile $path }
    [IO.Directory]::CreateDirectory($runtime.NodeModuleDirectory) | Out-Null
    Copy-PlainTree $package.PluginSource $target
    New-Item -ItemType Junction -Path $latest -Target $target | Out-Null
    $paths = [ordered]@{
        nodePath = $runtime.NodePath
        nodeReplPath = $runtime.NodeReplPath
        codexCliPath = $runtime.CodexCliPath
        browserClientPath = Join-Path $latest 'scripts\browser-client.mjs'
        extensionHostPath = Join-Path $latest 'extension-host\windows\x64\extension-host.exe'
        resourcesPath = $package.ResourcesPath
    }
    $configPath = Join-Path $latest 'extension-host\windows\x64\extension-host-config.json'
    Write-JsonAtomic $configPath $paths
    $script:fixtureRegistry = Join-Path $runtime.LocalAppData "OpenAI\extension\$NativeHostName.json"
    $native = [ordered]@{ name = $NativeHostName; type = 'stdio'; path = $paths.extensionHostPath; allowed_origins = @($StableExtensionIds | ForEach-Object { "chrome-extension://$_/" }) }
    Write-JsonAtomic $script:fixtureRegistry $native
    $v2 = [ordered]@{ schemaVersion = 2; entries = @([ordered]@{ appVersion = '1.2.3'; paths = $paths }) }
    $appV2 = Join-Path $runtime.LocalAppData 'OpenAI\Codex\chrome-native-hosts-v2.json'
    $codexV2 = Join-Path $testCodex 'chrome-native-hosts-v2.json'
    Write-JsonAtomic $appV2 $v2
    Write-JsonAtomic $codexV2 $v2
    Assert-Test (Test-ReportHealthy (Report)) 'complete current fixture passes all six checks'
    $before = (Get-FileHash $configPath).Hash
    Report | Out-Null
    Assert-Test ((Get-FileHash $configPath).Hash -eq $before) 'diagnose does not rewrite config'
    Set-FixtureFile $configPath '{'
    Assert-Test (-not (Report).HostConfigPathsValid) 'malformed host JSON is a failed check, not a crash'
    Write-JsonAtomic $configPath @{}
    Assert-Test (-not (Report).HostConfigPathsValid) 'missing host fields do not crash strict mode'
    Write-JsonAtomic $configPath $paths
    $oldNode = Join-Path $fixtureRoot 'old\node.exe'
    Set-FixtureFile $oldNode
    $stale = [ordered]@{}; foreach ($key in $paths.Keys) { $stale[$key] = $paths[$key] }; $stale.nodePath = $oldNode
    Write-JsonAtomic $configPath $stale
    Assert-Test (-not (Report).HostConfigPathsValid) 'existing stale Node is rejected'
    Write-JsonAtomic $configPath $paths
    $v2.entries[0].paths = $stale
    Write-JsonAtomic $appV2 $v2
    Assert-Test (-not (Report).AppDataV2ManifestCurrent) 'v2 current version with old runtime fails'
    $v2.entries[0].paths = $paths
    Write-JsonAtomic $appV2 $v2
    Set-FixtureFile $codexV2 '{'
    Assert-Test (-not (Report).CodexHomeV2ManifestCurrent) 'malformed v2 JSON remains diagnosable'
    $Force = $true
    Assert-Throws { Invoke-Repair $package $runtime $testCodex } '*Unreadable JSON*' 'repair refuses corrupt input before mutation'
    Assert-Test (-not (Test-Path (Join-Path $testCodex 'repair-backups'))) 'rejected preflight creates no backup or changes'
    Write-JsonAtomic $codexV2 $v2
    $native.allowed_origins = @('chrome-extension://invalid/')
    Write-JsonAtomic $script:fixtureRegistry $native
    Assert-Test (-not (Report).NativeManifestValid) 'wrong extension origins fail registration check'
    $native.allowed_origins = @($StableExtensionIds | ForEach-Object { "chrome-extension://$_/" })
    Write-JsonAtomic $script:fixtureRegistry $native
    $result = Invoke-Repair $package $runtime $testCodex
    Assert-Test ($result.AlreadyHealthy -and -not $result.Repaired) 'healthy repair is a no-op'
    Assert-Test (-not (Test-Path (Join-Path $testCodex 'repair-backups'))) 'healthy repair creates no backups'
    $v2.entries = @($v2.entries[0], $v2.entries[0])
    Write-JsonAtomic $appV2 $v2
    Assert-Test (-not (Report).AppDataV2ManifestCurrent) 'duplicate current entries do not pass'
    $v2.entries = @($v2.entries[0])
    $v2.schemaVersion = 99
    Write-JsonAtomic $appV2 $v2
    Assert-Test (-not (Report).AppDataV2ManifestCurrent) 'unknown v2 schema fails diagnosis'
    Assert-Throws { Invoke-Repair $package $runtime $testCodex } '*Unsupported v2 manifest schema*' 'unknown schema is not rewritten'
    $v2.schemaVersion = 2
    Write-JsonAtomic $appV2 $v2
    $v2.entries = @([ordered]@{ appVersion = '0.9.0'; custom = 'preserve' })
    Write-JsonAtomic $appV2 $v2
    Add-CurrentV2Entry -ManifestPath $appV2 -PackageContext $package -RuntimeContext $runtime -CodexHome $testCodex -CacheRoot $cache -DesktopProcess ([pscustomobject]@{ ProcessId = $PID })
    $updated = Read-JsonIfPresent $appV2
    Assert-Test ($updated.entries.Count -eq 2 -and $updated.entries[1].custom -eq 'preserve') 'v2 update retains unrelated old-version data'
    Assert-Test (Report).AppDataV2ManifestCurrent 'v2 update produces a current valid record'
    $Force = $false
    Assert-Throws { Invoke-Repair $package $runtime $testCodex } '*explicitly authorizes*' 'repair requires Force'
    $Force = $true
    [IO.Directory]::Delete($latest)
    [IO.Directory]::CreateDirectory($latest) | Out-Null
    Set-FixtureFile (Join-Path $latest 'keep.txt')
    Assert-Throws { Invoke-Repair $package $runtime $testCodex } '*non-junction*' 'ordinary latest directory is rejected before changes'
    Assert-Test (Test-Path (Join-Path $latest 'keep.txt')) 'ordinary latest contents preserved'
    Assert-Test (Test-Path (Join-Path $target 'scripts\browser-client.mjs')) 'unlink preserved cache target'
    Assert-Throws { Assert-ChildPath $cache (Join-Path $fixtureRoot 'outside') } '*outside*' 'path escape rejected'
    $redirect = Join-Path $fixtureRoot 'redirect'
    New-Item -ItemType Junction -Path $redirect -Target $target | Out-Null
    Assert-Throws { Assert-PlainPath (Join-Path $redirect 'file') } '*redirected*' 'redirected write ancestors rejected'
    [IO.Directory]::Delete($redirect)
    Set-FixtureFile (Join-Path $target 'scripts\browser-client.mjs') 'fixturX'
    Assert-Test (-not (Test-TreeEquivalent $package.PluginSource $target)) 'same-length cache corruption caught by SHA256'
    Write-Output "Passed $script:passed tests. No browser configuration changed."
} finally {
    # The absolute GUID fixture path is checked before recursive cleanup; unlink junctions first.
    Assert-ChildPath ([IO.Path]::GetTempPath()) $fixtureRoot
    foreach ($link in @($latest, (Join-Path $fixtureRoot 'redirect'))) {
        $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction') { [IO.Directory]::Delete($link) }
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
