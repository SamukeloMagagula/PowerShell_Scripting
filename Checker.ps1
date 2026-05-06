# FUNCTIONS
function Get-SafeDiskStatus {
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop | Select-Object `
            FriendlyName,
            MediaType,
            OperationalStatus,
            HealthStatus,
            @{ Name = 'SizeGB'; Expression = { [math]::Round($_.Size / 1GB, 2) } }

        return $disks
    }
    catch {
        Write-Warning "Failed to retrieve disk status: $_"
        return $null
    }
}

function Get-ModuleStatus {

    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    $module = Get-Module -Name $ModuleName

    if (-not $module) {
        Write-Verbose "Module '$ModuleName' not loaded. Attempting import..."
        try {
            Import-Module -Name $ModuleName -ErrorAction Stop
            $module = Get-Module -Name $ModuleName
        }
        catch {
            Write-Warning "Could not import module '$ModuleName': $_"
        }
    }

    return [PSCustomObject]@{
        ModuleName = $ModuleName
        Loaded     = $null -ne $module
        Version    = if ($module) { $module.Version.ToString() } else { 'N/A' }
    }
}

function Get-DomainInfo {
    
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return [PSCustomObject]@{
            Name         = $cs.Domain
            PartOfDomain = $cs.PartOfDomain
        }
    }
    catch {
        Write-Warning "Failed to retrieve domain information: $_"
        return $null
    }
}

function Get-DnsInfo {

    try {
        $dnsEntries = Get-DnsClientServerAddress -ErrorAction Stop |
            Where-Object { $_.ServerAddresses.Count -gt 0 } |
            Select-Object InterfaceAlias, AddressFamily, ServerAddresses

        return $dnsEntries
    }
    catch {
        Write-Warning "Failed to retrieve DNS client addresses: $_"
        return $null
    }
}

# MAIN
function Invoke-EnvironmentCheck {
    [CmdletBinding()]
    param()

    Write-Verbose "Starting environment preflight check..."

    $results = [PSCustomObject]@{
        DNS        = Get-DnsInfo
        Domain     = Get-DomainInfo
        Disks      = Get-SafeDiskStatus
        ADModule   = Get-ModuleStatus -ModuleName 'ActiveDirectory'
        DHCPModule = Get-ModuleStatus -ModuleName 'DhcpServer'
        Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    #SUMMARY OUTPUT
    Write-Host "`n===== ENVIRONMENT CHECK RESULTS =====" -ForegroundColor Cyan

    Write-Host "`n[Domain]" -ForegroundColor Yellow
    if ($results.Domain) {
        Write-Host "  Name        : $($results.Domain.Name)"
        Write-Host "  Part of Domain: $($results.Domain.PartOfDomain)"
    } else {
        Write-Host "  Unable to retrieve domain info." -ForegroundColor Red
    }

    Write-Host "`n[DNS Servers]" -ForegroundColor Yellow
    if ($results.DNS) {
        $results.DNS | ForEach-Object {
            Write-Host "  [$($_.InterfaceAlias)] -> $($_.ServerAddresses -join ', ')"
        }
    } else {
        Write-Host "  Unable to retrieve DNS info." -ForegroundColor Red
    }

    Write-Host "`n[Disk Status]" -ForegroundColor Yellow
    if ($results.Disks) {
        $results.Disks | ForEach-Object {
            $color = if ($_.HealthStatus -eq 'Healthy') { 'Green' } else { 'Red' }
            Write-Host "  $($_.FriendlyName) | $($_.SizeGB) GB | $($_.OperationalStatus) | Health: $($_.HealthStatus)" -ForegroundColor $color
        }
    } else {
        Write-Host "  Unable to retrieve disk info." -ForegroundColor Red
    }

    Write-Host "`n[Modules]" -ForegroundColor Yellow
    @($results.ADModule, $results.DHCPModule) | ForEach-Object {
        $color  = if ($_.Loaded) { 'Green' } else { 'Red' }
        $status = if ($_.Loaded) { 'Loaded' } else { 'NOT FOUND' }
        Write-Host "  $($_.ModuleName) : $status $(if ($_.Loaded) { "v$($_.Version)" })" -ForegroundColor $color
    }

    Write-Host "`n[Timestamp] $($results.Timestamp)" -ForegroundColor Gray
    Write-Host "======================================`n" -ForegroundColor Cyan

    # Return structured object for pipeline use
    return $results
}

# ENTRY POINT
$EnvironmentStatus = Invoke-EnvironmentCheck -Verbose