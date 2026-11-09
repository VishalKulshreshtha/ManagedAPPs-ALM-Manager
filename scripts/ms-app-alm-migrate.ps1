[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AppIdentifier,

    [string]$SourceEnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$TargetEnvironmentId,

    [ValidateSet("check-only", "execute")]
    [string]$Mode = "check-only",

    [string]$TargetDisplayName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-MsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [string]$WorkingDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        Push-Location $WorkingDirectory
    }

    try {
        $output = & ms @Args --json 2>&1
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Pop-Location
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: ms $($Args -join ' ')`n$output"
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Invoke-Ms {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [string]$WorkingDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        Push-Location $WorkingDirectory
    }

    try {
        & ms @Args
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Pop-Location
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: ms $($Args -join ' ')"
    }
}

function Normalize-List {
    param($Raw)
    if ($null -eq $Raw) { return @() }
    if ($Raw -is [System.Array]) { return @($Raw) }
    if ($Raw.PSObject.Properties.Name -contains "value") { return @($Raw.value) }
    if ($Raw.PSObject.Properties.Name -contains "items") { return @($Raw.items) }
    return @($Raw)
}

function Find-AppMatches {
    param(
        [Parameter(Mandatory = $true)]
        [System.Array]$Apps,
        [Parameter(Mandatory = $true)]
        [string]$Identifier
    )

    $byId = @($Apps | Where-Object { $_.appId -eq $Identifier })
    if ($byId.Count -gt 0) { return $byId }

    $byNameExact = @($Apps | Where-Object { $_.displayName -ieq $Identifier })
    if ($byNameExact.Count -gt 0) { return $byNameExact }

    return @($Apps | Where-Object { $_.displayName -like "*$Identifier*" })
}

function Get-ConfigEnvironmentId {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }

    $cfg = Get-Content -Path $Path -Raw | ConvertFrom-Json
    if ($cfg.PSObject.Properties.Name -contains "environmentId") { return [string]$cfg.environmentId }
    if (($cfg.PSObject.Properties.Name -contains "app") -and ($cfg.app.PSObject.Properties.Name -contains "environmentId")) { return [string]$cfg.app.environmentId }
    if (($cfg.PSObject.Properties.Name -contains "environment") -and ($cfg.environment.PSObject.Properties.Name -contains "id")) { return [string]$cfg.environment.id }
    return $null
}

function Write-Step {
    param(
        [string]$Step,
        [string]$Status,
        [string]$Notes
    )
    Write-Host ("{0,-34} {1,-10} {2}" -f $Step, $Status, $Notes)
}

function Get-DataSourcesFromShow {
    param($AppShow)

    if ($null -eq $AppShow) { return @() }
    if ($AppShow.PSObject.Properties.Name -contains "dataSources") { return Normalize-List $AppShow.dataSources }
    if (($AppShow.PSObject.Properties.Name -contains "resources") -and ($AppShow.resources.PSObject.Properties.Name -contains "dataSources")) { return Normalize-List $AppShow.resources.dataSources }
    if (($AppShow.PSObject.Properties.Name -contains "boundResources") -and ($AppShow.boundResources.PSObject.Properties.Name -contains "dataSources")) { return Normalize-List $AppShow.boundResources.dataSources }

    return @()
}

function Get-ConnectorIdFromDataSource {
    param($DataSource)

    if ($DataSource.PSObject.Properties.Name -contains "connectorId") { return [string]$DataSource.connectorId }
    if ($DataSource.PSObject.Properties.Name -contains "connector") {
        if ($DataSource.connector -is [string]) { return [string]$DataSource.connector }
        if ($DataSource.connector.PSObject.Properties.Name -contains "id") { return [string]$DataSource.connector.id }
        if ($DataSource.connector.PSObject.Properties.Name -contains "name") { return [string]$DataSource.connector.name }
    }
    return $null
}

function Build-AddDataSourceArgs {
    param($DataSource)

    $connector = Get-ConnectorIdFromDataSource -DataSource $DataSource
    if ([string]::IsNullOrWhiteSpace($connector)) { return $null }

    $args = New-Object System.Collections.Generic.List[string]
    $args.AddRange(@("app", "add", "data-source", "--connector", $connector))

    $mode = $null
    if ($DataSource.PSObject.Properties.Name -contains "as") { $mode = [string]$DataSource.as }
    elseif ($DataSource.PSObject.Properties.Name -contains "mode") { $mode = [string]$DataSource.mode }
    elseif ($DataSource.PSObject.Properties.Name -contains "kind") { $mode = [string]$DataSource.kind }
    if (($mode -eq "table") -or ($mode -eq "action")) {
        $args.Add("--as")
        $args.Add($mode)
    }

    if ($DataSource.PSObject.Properties.Name -contains "connectionId" -and -not [string]::IsNullOrWhiteSpace([string]$DataSource.connectionId)) {
        $args.Add("--connection-id")
        $args.Add([string]$DataSource.connectionId)
    }
    if ($DataSource.PSObject.Properties.Name -contains "dataset" -and -not [string]::IsNullOrWhiteSpace([string]$DataSource.dataset)) {
        $args.Add("--dataset")
        $args.Add([string]$DataSource.dataset)
    }
    if ($DataSource.PSObject.Properties.Name -contains "table" -and -not [string]::IsNullOrWhiteSpace([string]$DataSource.table)) {
        $args.Add("--table")
        $args.Add([string]$DataSource.table)
    }
    if ($DataSource.PSObject.Properties.Name -contains "dataverseEnvironmentId" -and -not [string]::IsNullOrWhiteSpace([string]$DataSource.dataverseEnvironmentId)) {
        $args.Add("--dataverse-environment-id")
        $args.Add([string]$DataSource.dataverseEnvironmentId)
    }

    return ,$args.ToArray()
}

if (-not (Get-Command ms -ErrorAction SilentlyContinue)) {
    throw "Managed Apps CLI not found. Install with: npm install -g @microsoft/managed-apps-cli"
}

Write-Host "Status: Ready"
Write-Host "Step                               Status     Notes"
Write-Host "---------------------------------- ---------- -----------------------------------------------"

& ms --version | Out-Null
Write-Step -Step "ms --version" -Status "OK" -Notes "CLI available"

$authRaw = & ms auth status --json 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Authentication check failed: `n$authRaw"
}
Write-Step -Step "ms auth status" -Status "OK" -Notes "Authenticated session found"

$resolved = $null
$resolvedSourceEnvironmentId = $SourceEnvironmentId

if (-not [string]::IsNullOrWhiteSpace($SourceEnvironmentId)) {
    $appsInSourceEnv = Normalize-List (Invoke-MsJson -Args @("app", "list", "--permission", "edit", "--environment-id", $SourceEnvironmentId))
    $sourceMatches = Find-AppMatches -Apps $appsInSourceEnv -Identifier $AppIdentifier
    if ($sourceMatches.Count -eq 1) {
        $resolved = $sourceMatches[0]
        Write-Step -Step "Source env (user provided)" -Status "OK" -Notes $SourceEnvironmentId
    } elseif ($sourceMatches.Count -gt 1) {
        throw "Multiple apps matched '$AppIdentifier' in source environment '$SourceEnvironmentId'. Use exact app ID."
    } else {
        throw "No app matched '$AppIdentifier' in source environment '$SourceEnvironmentId'."
    }
} else {
    $configPath = Join-Path -Path (Get-Location) -ChildPath "ms.config.json"
    $configEnvironmentId = Get-ConfigEnvironmentId -Path $configPath

    if (-not [string]::IsNullOrWhiteSpace($configEnvironmentId)) {
        $appsInConfigEnv = Normalize-List (Invoke-MsJson -Args @("app", "list", "--permission", "edit", "--environment-id", $configEnvironmentId))
        $configMatches = Find-AppMatches -Apps $appsInConfigEnv -Identifier $AppIdentifier
        if ($configMatches.Count -eq 1) {
            $resolved = $configMatches[0]
            $resolvedSourceEnvironmentId = $configEnvironmentId
            Write-Step -Step "Source env (dev/default)" -Status "OK" -Notes $configEnvironmentId
        } elseif ($configMatches.Count -gt 1) {
            throw "Multiple apps matched '$AppIdentifier' in default developer environment '$configEnvironmentId'. Use exact app ID."
        } else {
            Write-Step -Step "Source env (dev/default)" -Status "WARN" -Notes "App not found in $configEnvironmentId"
        }
    } else {
        Write-Step -Step "Source env (dev/default)" -Status "WARN" -Notes "No ms.config.json environmentId found"
    }

    if ($null -eq $resolved) {
        $allApps = Normalize-List (Invoke-MsJson -Args @("app", "list", "--permission", "edit"))
        $globalMatches = Find-AppMatches -Apps $allApps -Identifier $AppIdentifier
        if ($globalMatches.Count -eq 1) {
            $resolved = $globalMatches[0]
            $resolvedSourceEnvironmentId = [string]$resolved.environmentId
            Write-Step -Step "Source env (auto-discovery)" -Status "OK" -Notes $resolvedSourceEnvironmentId
        } elseif ($globalMatches.Count -gt 1) {
            throw "Found multiple matches for '$AppIdentifier' across environments. Provide -SourceEnvironmentId."
        } else {
            throw "Could not find '$AppIdentifier'. Provide -SourceEnvironmentId explicitly."
        }
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedSourceEnvironmentId)) {
    throw "Source environment could not be resolved. Provide -SourceEnvironmentId."
}

Write-Step -Step "Resolve source app" -Status "OK" -Notes ("{0} ({1})" -f $resolved.displayName, $resolved.appId)

$sourceAppName = [string]$resolved.displayName
$sourceAppId = [string]$resolved.appId
$sourceInfo = Invoke-MsJson -Args @("app", "info", "--app", $sourceAppName, "--environment-id", $resolvedSourceEnvironmentId)
Write-Step -Step "ms app info (source)" -Status "OK" -Notes "Fetched source metadata"

if ([string]::IsNullOrWhiteSpace($TargetDisplayName)) {
    $TargetDisplayName = "$sourceAppName-migrated"
}

$repoUrl = $null
if ($sourceInfo.PSObject.Properties.Name -contains "repositoryUrl") {
    $repoUrl = [string]$sourceInfo.repositoryUrl
}

$workRoot = Join-Path -Path (Get-Location) -ChildPath "_alm_migration"
$sourceDir = Join-Path -Path $workRoot -ChildPath ("source_{0}" -f $sourceAppId)
$targetDir = Join-Path -Path $workRoot -ChildPath ("target_{0}" -f $sourceAppId)

$plan = New-Object System.Collections.Generic.List[string]
if ([string]::IsNullOrWhiteSpace($repoUrl)) {
    $plan.Add("ms app clone --app $sourceAppId `"$sourceDir`"")
} else {
    $plan.Add("git clone `"$repoUrl`" `"$sourceDir`"")
}
$plan.Add("Copy-Item -Path `"$sourceDir`" -Destination `"$targetDir`" -Recurse")
$plan.Add("Set-Location `"$sourceDir`"; ms app show --json; ms app get-settings --json")
$plan.Add("Set-Location `"$targetDir`"; ms app init --display-name `"$TargetDisplayName`" --environment-id `"$TargetEnvironmentId`"")
$plan.Add("ms connector list --environment-id `"$TargetEnvironmentId`" --json")
$plan.Add("For each source data source: ms app add data-source --connector <id> [--as table|action] [--dataset ...] [--table ...] [--connection-id ...]")
$plan.Add("ms app refresh data-source")
$plan.Add("Apply supported app settings (e.g., --show-header) via ms app set-setting")
$plan.Add("ms app build --app `"$TargetDisplayName`"")
$plan.Add("ms app deploy --app `"$TargetDisplayName`"")
$plan.Add("ms app info --app `"$TargetDisplayName`" --environment-id `"$TargetEnvironmentId`" --json")
$plan.Add("ms app play --app `"$TargetDisplayName`" --mode live --no-browser")

Write-Step -Step "Build plan" -Status "OK" -Notes "Includes dependency migration"

Write-Host ""
Write-Host "Source environment: $resolvedSourceEnvironmentId"
Write-Host "Planned commands:"
for ($i = 0; $i -lt $plan.Count; $i++) {
    Write-Host ("{0}. {1}" -f ($i + 1), $plan[$i])
}

if ($Mode -eq "check-only") {
    Write-Host ""
    Write-Host "Status: Completed (check-only)"
    exit 0
}

$confirm = Read-Host "Type YES to execute migration (including dependency migration)"
if ($confirm -ne "YES") {
    Write-Host "Status: Blocked (confirmation not provided)"
    exit 2
}

if (Test-Path $workRoot) {
    Write-Step -Step "Workspace check" -Status "WARN" -Notes "$workRoot already exists"
} else {
    New-Item -Path $workRoot -ItemType Directory | Out-Null
    Write-Step -Step "Workspace create" -Status "OK" -Notes $workRoot
}

if (Test-Path $sourceDir -or Test-Path $targetDir) {
    throw "Source or target directory already exists. Delete or choose a clean workspace first."
}

if ([string]::IsNullOrWhiteSpace($repoUrl)) {
    Invoke-Ms -Args @("app", "clone", "--app", $sourceAppId, $sourceDir)
    Write-Step -Step "Clone source app" -Status "OK" -Notes $sourceDir
} else {
    & git clone $repoUrl $sourceDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    Write-Step -Step "Clone source repo" -Status "OK" -Notes $sourceDir
}

Copy-Item -Path $sourceDir -Destination $targetDir -Recurse
Write-Step -Step "Copy source->target" -Status "OK" -Notes $targetDir

$sourceShow = Invoke-MsJson -Args @("app", "show") -WorkingDirectory $sourceDir
$sourceSettings = Invoke-MsJson -Args @("app", "get-settings") -WorkingDirectory $sourceDir
$sourceDataSources = Get-DataSourcesFromShow -AppShow $sourceShow
Write-Step -Step "Inventory dependencies" -Status "OK" -Notes ("Data sources: {0}" -f $sourceDataSources.Count)

Invoke-Ms -Args @("app", "init", "--display-name", $TargetDisplayName, "--environment-id", $TargetEnvironmentId) -WorkingDirectory $targetDir
Write-Step -Step "Register target app" -Status "OK" -Notes $TargetDisplayName

$targetConnectors = Normalize-List (Invoke-MsJson -Args @("connector", "list", "--environment-id", $TargetEnvironmentId))
$targetConnectorKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($c in $targetConnectors) {
    if ($c.PSObject.Properties.Name -contains "id" -and -not [string]::IsNullOrWhiteSpace([string]$c.id)) { [void]$targetConnectorKeys.Add([string]$c.id) }
    if ($c.PSObject.Properties.Name -contains "name" -and -not [string]::IsNullOrWhiteSpace([string]$c.name)) { [void]$targetConnectorKeys.Add([string]$c.name) }
    if ($c.PSObject.Properties.Name -contains "displayName" -and -not [string]::IsNullOrWhiteSpace([string]$c.displayName)) { [void]$targetConnectorKeys.Add([string]$c.displayName) }
}

$datasourceMigrationCount = 0
foreach ($ds in $sourceDataSources) {
    $dsArgs = Build-AddDataSourceArgs -DataSource $ds
    if ($null -eq $dsArgs) { continue }

    $connectorId = Get-ConnectorIdFromDataSource -DataSource $ds
    if (-not $targetConnectorKeys.Contains($connectorId)) {
        throw "Target environment '$TargetEnvironmentId' is missing connector '$connectorId' required by a source data source."
    }

    Invoke-Ms -Args $dsArgs -WorkingDirectory $targetDir
    $datasourceMigrationCount++
}
Write-Step -Step "Migrate data sources" -Status "OK" -Notes ("Migrated: {0}" -f $datasourceMigrationCount)

Invoke-Ms -Args @("app", "refresh", "data-source") -WorkingDirectory $targetDir
Write-Step -Step "Refresh data sources" -Status "OK" -Notes "Bindings regenerated"

if ($sourceSettings.PSObject.Properties.Name -contains "showHeader") {
    $showHeaderValue = [string]$sourceSettings.showHeader
    Invoke-Ms -Args @("app", "set-setting", "--show-header", $showHeaderValue) -WorkingDirectory $targetDir
    Write-Step -Step "Apply app settings" -Status "OK" -Notes ("show-header={0}" -f $showHeaderValue)
} else {
    Write-Step -Step "Apply app settings" -Status "WARN" -Notes "No supported scalar settings detected for automatic apply"
}

Invoke-Ms -Args @("app", "build", "--app", $TargetDisplayName) -WorkingDirectory $targetDir
Write-Step -Step "Build target app" -Status "OK" -Notes "Build submitted/completed"

Invoke-Ms -Args @("app", "deploy", "--app", $TargetDisplayName) -WorkingDirectory $targetDir
Write-Step -Step "Deploy target app" -Status "OK" -Notes "Deployment completed"

$targetInfo = Invoke-MsJson -Args @("app", "info", "--app", $TargetDisplayName, "--environment-id", $TargetEnvironmentId)
Write-Step -Step "Validate target app" -Status "OK" -Notes ("AppId: {0}" -f $targetInfo.appId)

& ms app play --app $TargetDisplayName --mode live --no-browser
if ($LASTEXITCODE -ne 0) {
    Write-Step -Step "Play URL check" -Status "WARN" -Notes "Unable to fetch live URL"
} else {
    Write-Step -Step "Play URL check" -Status "OK" -Notes "Live URL printed"
}

Write-Host "Status: Completed"

