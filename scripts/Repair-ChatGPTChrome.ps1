[CmdletBinding()]
param(
    [ValidateSet('Diagnose', 'Repair')]
    [string]$Mode = 'Diagnose',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StableExtensionIds = @(
    'hehggadaopoacecdllhhajmbjkdcmajg',
    'odlomjlbamekndcpllcnffbgeohgkmjh'
)
$NativeHostName = 'com.openai.codexextension'

function Get-UserProfileDirectory {
    $profileDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($profileDirectory)) {
        throw 'Unable to resolve the current user profile.'
    }
    return [IO.Path]::GetFullPath($profileDirectory)
}

function Get-CodexHomeDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return [IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    return Join-Path (Get-UserProfileDirectory) '.codex'
}

function Assert-ChildPath {
    param([Parameter(Mandatory)][string]$Parent, [Parameter(Mandatory)][string]$Child)
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $childFull = [IO.Path]::GetFullPath($Child)
    if (-not $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the expected directory: $childFull"
    }
}

function Get-CurrentPackageContext {
    $package = Get-AppxPackage -Name 'OpenAI.Codex' |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $package) {
        throw 'The OpenAI ChatGPT/Codex AppX package is not installed for this user.'
    }

    $resourcesPath = Join-Path $package.InstallLocation 'app\resources'
    $pluginSource = Join-Path $resourcesPath 'plugins\openai-bundled\plugins\chrome'
    $pluginManifest = Join-Path $pluginSource '.codex-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $pluginManifest -PathType Leaf)) {
        throw "The installed desktop app does not contain the bundled Chrome plugin: $pluginManifest"
    }
    $pluginVersion = (Get-Content -LiteralPath $pluginManifest -Raw | ConvertFrom-Json).version
    if ([string]::IsNullOrWhiteSpace($pluginVersion)) {
        throw 'The bundled Chrome plugin has no version.'
    }

    [pscustomobject]@{
        Package = $package
        ResourcesPath = $resourcesPath
        PluginSource = $pluginSource
        PluginVersion = [string]$pluginVersion
    }
}

function Get-CurrentRuntimeContext {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $runtimeRoot = Join-Path $localAppData 'OpenAI\Codex\runtimes\cua_node'
    $runtime = Get-ChildItem -LiteralPath $runtimeRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\node.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\node_repl.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\node_modules') -PathType Container)
        } |
        Select-Object -First 1
    if (-not $runtime) {
        throw 'No complete ChatGPT/Codex Node runtime was found.'
    }

    $codexRoot = Join-Path $localAppData 'OpenAI\Codex\bin'
    $codex = Get-ChildItem -LiteralPath $codexRoot -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $codex) {
        throw 'No ChatGPT/Codex CLI runtime was found.'
    }

    [pscustomobject]@{
        LocalAppData = $localAppData
        NodePath = Join-Path $runtime.FullName 'bin\node.exe'
        NodeReplPath = Join-Path $runtime.FullName 'bin\node_repl.exe'
        NodeModuleDirectory = Join-Path $runtime.FullName 'bin\node_modules'
        CodexCliPath = $codex.FullName
    }
}

function Get-FileInventory {
    param([Parameter(Mandatory)][string]$Root)
    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)
    [pscustomobject]@{
        Files = $files
        Count = $files.Count
        Bytes = [long](($files | Measure-Object Length -Sum).Sum)
    }
}

function Test-TreeEquivalent {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { return $false }
    $sourceInventory = Get-FileInventory -Root $Source
    $generatedConfigRelativePath = 'extension-host\windows\x64\extension-host-config.json'
    $destinationFiles = @(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force |
        Where-Object {
            $_.FullName.Substring($Destination.Length).TrimStart('\') -ne
                $generatedConfigRelativePath
        })
    $destinationInventory = [pscustomobject]@{
        Files = $destinationFiles
        Count = $destinationFiles.Count
        Bytes = [long](($destinationFiles | Measure-Object Length -Sum).Sum)
    }
    if ($sourceInventory.Count -ne $destinationInventory.Count -or
        $sourceInventory.Bytes -ne $destinationInventory.Bytes) {
        return $false
    }
    foreach ($file in $sourceInventory.Files) {
        $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return $false }
        if ($file.Length -ne (Get-Item -LiteralPath $target).Length) { return $false }
        if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) { return $false }
    }
    return $true
}

function Copy-PlainTree {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        $inputStream = [IO.File]::Open(
            $file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read
        )
        try {
            $outputStream = [IO.File]::Open(
                $target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None
            )
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
    }
}

function Read-JsonIfPresent {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-PathsObject {
    param($Paths)
    if (-not $Paths) { return $false }
    foreach ($name in @(
        'nodePath', 'nodeReplPath', 'codexCliPath',
        'browserClientPath', 'extensionHostPath', 'resourcesPath'
    )) {
        if (-not $Paths.PSObject.Properties[$name] -or
            [string]::IsNullOrWhiteSpace([string]$Paths.$name) -or
            -not (Test-Path -LiteralPath $Paths.$name)) {
            return $false
        }
    }
    return $true
}

function Get-DiagnosticReport {
    param($PackageContext, $RuntimeContext, [string]$CodexHome)
    $cacheRoot = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome'
    $currentCache = Join-Path $cacheRoot $PackageContext.PluginVersion
    $latest = Join-Path $cacheRoot 'latest'
    $latestItem = Get-Item -LiteralPath $latest -Force -ErrorAction SilentlyContinue
    $latestTarget = if ($latestItem -and $latestItem.LinkType -eq 'Junction') {
        [string]$latestItem.Target
    } else {
        $null
    }

    $hostConfigPath = Join-Path $latest 'extension-host\windows\x64\extension-host-config.json'
    $hostConfig = Read-JsonIfPresent -Path $hostConfigPath
    $hostConfigValid = [bool]($hostConfig -and
        (Test-Path -LiteralPath $hostConfig.nodePath) -and
        (Test-Path -LiteralPath $hostConfig.nodeReplPath) -and
        (Test-Path -LiteralPath $hostConfig.codexCliPath) -and
        (Test-Path -LiteralPath $hostConfig.browserClientPath))

    $nativeManifestPath = Join-Path $RuntimeContext.LocalAppData "OpenAI\extension\$NativeHostName.json"
    $nativeManifest = Read-JsonIfPresent -Path $nativeManifestPath
    $registryPath = "Registry::HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\$NativeHostName"
    $registryValue = try {
        Get-ItemPropertyValue -LiteralPath $registryPath -Name '(default)'
    } catch {
        $null
    }
    $nativeManifestValid = [bool]($nativeManifest -and
        (Test-Path -LiteralPath $nativeManifest.path -PathType Leaf) -and
        $registryValue -and
        ([IO.Path]::GetFullPath($registryValue) -eq [IO.Path]::GetFullPath($nativeManifestPath)))

    $appDataManifest = Join-Path $RuntimeContext.LocalAppData 'OpenAI\Codex\chrome-native-hosts-v2.json'
    $codexManifest = Join-Path $CodexHome 'chrome-native-hosts-v2.json'
    $appDataDoc = Read-JsonIfPresent -Path $appDataManifest
    $codexDoc = Read-JsonIfPresent -Path $codexManifest
    $appDataEntry = @(if ($appDataDoc) {
        $appDataDoc.entries |
            Where-Object appVersion -eq $PackageContext.PluginVersion |
            Select-Object -First 1
    })
    $codexEntry = @(if ($codexDoc) {
        $codexDoc.entries |
            Where-Object appVersion -eq $PackageContext.PluginVersion |
            Select-Object -First 1
    })

    [pscustomobject]@{
        PackageVersion = [string]$PackageContext.Package.Version
        PluginVersion = $PackageContext.PluginVersion
        PluginCacheComplete = Test-TreeEquivalent -Source $PackageContext.PluginSource -Destination $currentCache
        LatestTargetsCurrentPlugin = [bool]($latestTarget -and
            ([IO.Path]::GetFullPath($latestTarget) -eq [IO.Path]::GetFullPath($currentCache)))
        HostConfigPathsValid = $hostConfigValid
        NativeManifestValid = $nativeManifestValid
        AppDataV2ManifestCurrent = [bool]($appDataEntry.Count -eq 1 -and
            (Test-PathsObject -Paths $appDataEntry[0].paths))
        CodexHomeV2ManifestCurrent = [bool]($codexEntry.Count -eq 1 -and
            (Test-PathsObject -Paths $codexEntry[0].paths))
        NodePath = $RuntimeContext.NodePath
        CodexCliPath = $RuntimeContext.CodexCliPath
        CacheRoot = $cacheRoot
        BackupRoot = Join-Path $CodexHome 'repair-backups\chatgpt-chrome'
    }
}

function Write-JsonAtomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $temporary = "$Path.repair-$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText(
        $temporary,
        ($Value | ConvertTo-Json -Depth 20),
        (New-Object Text.UTF8Encoding($false))
    )
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-DesktopRootProcess {
    param([Parameter(Mandatory)][string]$InstallLocation)
    $allProcesses = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'ChatGPT.exe' -and
        $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($InstallLocation, [StringComparison]::OrdinalIgnoreCase)
    })
    $processIds = @($allProcesses.ProcessId)
    return $allProcesses |
        Where-Object { $_.ParentProcessId -notin $processIds } |
        Select-Object -First 1
}

function Add-CurrentV2Entry {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)]$PackageContext,
        [Parameter(Mandatory)]$RuntimeContext,
        [Parameter(Mandatory)][string]$CodexHome,
        [Parameter(Mandatory)][string]$CacheRoot,
        [Parameter(Mandatory)]$DesktopProcess
    )
    $document = Read-JsonIfPresent -Path $ManifestPath
    if (-not $document) {
        $document = [pscustomobject]@{ schemaVersion = 2; entries = @() }
    }
    $now = [DateTime]::UtcNow.ToString('o')
    $startedAt = (Get-Process -Id $DesktopProcess.ProcessId).StartTime.ToUniversalTime().ToString('o')
    $latest = Join-Path $CacheRoot 'latest'
    $entry = [ordered]@{
        schemaVersion = 2
        appServerProtocolVersion = 2
        appVersion = $PackageContext.PluginVersion
        channel = 'prod'
        cliVersion = $PackageContext.PluginVersion
        entryId = 'codex-runtime-' + [guid]::NewGuid().ToString('N')
        extensionBuildChannels = @('prod')
        extensionIds = $StableExtensionIds
        installId = 'codex-install-' + [guid]::NewGuid().ToString('N')
        nativeHostNames = @($NativeHostName)
        nativeHostProtocolVersion = 2
        nativeHostVersion = $PackageContext.PluginVersion
        paths = [ordered]@{
            browserClientPath = Join-Path $latest 'scripts\browser-client.mjs'
            browserServicePath = Join-Path $latest 'scripts\browser-service.mjs'
            codexCliPath = $RuntimeContext.CodexCliPath
            codexHome = $CodexHome
            extensionHostPath = Join-Path $latest 'extension-host\windows\x64\extension-host.exe'
            nodePath = $RuntimeContext.NodePath
            nodeModuleDirs = @($RuntimeContext.NodeModuleDirectory)
            nodeReplPath = $RuntimeContext.NodeReplPath
            resourcesPath = $PackageContext.ResourcesPath
        }
        presence = [ordered]@{
            lastSeenAt = $now
            pid = [int]$DesktopProcess.ProcessId
            startedAt = $startedAt
        }
        proxyHost = '127.0.0.1'
        proxyPort = 0
        updatedAt = $now
    }
    $document.entries = @([pscustomobject]$entry) +
        @($document.entries | Where-Object appVersion -ne $PackageContext.PluginVersion)
    Write-JsonAtomic -Path $ManifestPath -Value $document
}

function Invoke-Repair {
    param($PackageContext, $RuntimeContext, [string]$CodexHome)
    if (-not $Force) {
        throw 'Repair mode changes local integration files. Rerun with -Force only after the user explicitly authorizes the repair.'
    }

    $cacheRoot = Join-Path $CodexHome 'plugins\cache\openai-bundled\chrome'
    [IO.Directory]::CreateDirectory($cacheRoot) | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $CodexHome "repair-backups\chatgpt-chrome\$stamp"
    [IO.Directory]::CreateDirectory($backup) | Out-Null

    $appDataV2 = Join-Path $RuntimeContext.LocalAppData 'OpenAI\Codex\chrome-native-hosts-v2.json'
    $codexV2 = Join-Path $CodexHome 'chrome-native-hosts-v2.json'
    $nativeManifest = Join-Path $RuntimeContext.LocalAppData "OpenAI\extension\$NativeHostName.json"
    $currentHostConfig = Join-Path $cacheRoot 'latest\extension-host\windows\x64\extension-host-config.json'
    foreach ($item in @(
        @{ Source = $appDataV2; Name = 'appdata-chrome-native-hosts-v2.json' },
        @{ Source = $codexV2; Name = 'codex-home-chrome-native-hosts-v2.json' },
        @{ Source = $nativeManifest; Name = "$NativeHostName.json" },
        @{ Source = $currentHostConfig; Name = 'extension-host-config.json' }
    )) {
        if (Test-Path -LiteralPath $item.Source -PathType Leaf) {
            Copy-Item -LiteralPath $item.Source -Destination (Join-Path $backup $item.Name)
        }
    }

    $target = Join-Path $cacheRoot $PackageContext.PluginVersion
    $staging = Join-Path $cacheRoot ('.repair-staging-' + [guid]::NewGuid().ToString('N'))
    Assert-ChildPath -Parent $cacheRoot -Child $staging
    Copy-PlainTree -Source $PackageContext.PluginSource -Destination $staging
    if (-not (Test-TreeEquivalent -Source $PackageContext.PluginSource -Destination $staging)) {
        throw "The copied plugin failed verification. Staging data was retained at $staging"
    }

    $cachePrefix = [IO.Path]::GetFullPath($cacheRoot).TrimEnd('\') + '\'
    $extensionHosts = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'extension-host.exe' -and $_.ExecutablePath
    })
    foreach ($process in $extensionHosts) {
        $executable = [IO.Path]::GetFullPath($process.ExecutablePath)
        if ($executable.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.ProcessId -Force
        }
    }

    if (Test-Path -LiteralPath $target) {
        Assert-ChildPath -Parent $cacheRoot -Child $target
        $savedTarget = "$target.pre-repair-$stamp"
        Move-Item -LiteralPath $target -Destination $savedTarget
    }
    Move-Item -LiteralPath $staging -Destination $target

    $latest = Join-Path $cacheRoot 'latest'
    if (Test-Path -LiteralPath $latest) {
        $latestItem = Get-Item -LiteralPath $latest -Force
        if ($latestItem.LinkType -ne 'Junction') {
            throw "Refusing to replace a non-junction path: $latest"
        }
        Remove-Item -LiteralPath $latest -Force
    }
    New-Item -ItemType Junction -Path $latest -Target $target | Out-Null

    $installer = Join-Path $target 'scripts\installManifest.mjs'
    $moduleJson = ([Uri]$installer).AbsoluteUri | ConvertTo-Json -Compress
    $codexJson = $RuntimeContext.CodexCliPath | ConvertTo-Json -Compress
    $nodeJson = $RuntimeContext.NodePath | ConvertTo-Json -Compress
    $nodeReplJson = $RuntimeContext.NodeReplPath | ConvertTo-Json -Compress
    $javascript = "import { install } from $moduleJson; await install({appServerRuntimePaths:{codexCliPath:$codexJson,nodePath:$nodeJson,nodeReplPath:$nodeReplJson}});"
    & $RuntimeContext.NodePath --input-type=module -e $javascript
    if ($LASTEXITCODE -ne 0) {
        throw "The bundled manifest installer exited with code $LASTEXITCODE"
    }

    $desktopProcess = Get-DesktopRootProcess -InstallLocation $PackageContext.Package.InstallLocation
    if (-not $desktopProcess) {
        throw 'The desktop app root process was not found. Keep the app open while repairing.'
    }
    Add-CurrentV2Entry -ManifestPath $appDataV2 -PackageContext $PackageContext -RuntimeContext $RuntimeContext -CodexHome $CodexHome -CacheRoot $cacheRoot -DesktopProcess $desktopProcess
    Add-CurrentV2Entry -ManifestPath $codexV2 -PackageContext $PackageContext -RuntimeContext $RuntimeContext -CodexHome $CodexHome -CacheRoot $cacheRoot -DesktopProcess $desktopProcess

    [pscustomobject]@{
        Repaired = $true
        PluginVersion = $PackageContext.PluginVersion
        BackupDirectory = $backup
        NextAction = 'Click Try again or reopen the ChatGPT side panel. Restart Chrome only after saving browser work.'
    }
}

$codexHome = Get-CodexHomeDirectory
$packageContext = Get-CurrentPackageContext
$runtimeContext = Get-CurrentRuntimeContext

if ($Mode -eq 'Repair') {
    Invoke-Repair -PackageContext $packageContext -RuntimeContext $runtimeContext -CodexHome $codexHome |
        Format-List
}

Get-DiagnosticReport -PackageContext $packageContext -RuntimeContext $runtimeContext -CodexHome $codexHome |
    Format-List
