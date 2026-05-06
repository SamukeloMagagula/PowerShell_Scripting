# ================= PRE-FLIGHT =================
$ScriptVersion = "2.0"
$StartTime = Get-Date

# PowerShell version check
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "Requires PowerShell 5.0 or later. Found: $($PSVersionTable.PSVersion)"
    exit 1
}

# Logging via transcript
$LogPath = "$env:USERPROFILE\Downloads\PC_Audit_$(Get-Date -Format yyyyMMdd_HHmmss).log"
Start-Transcript -Path $LogPath -Append | Out-Null

Write-Host "Starting PC Audit v$ScriptVersion (Production Mode)..." -ForegroundColor Cyan

# Admin detection
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdmin) {
    Write-Warning "Not running as Administrator. Some checks (BitLocker, TPM, Defender details) may be limited."
}

# ================= CONFIG =================
$Config = [PSCustomObject]@{
    Gateway              = $null
    DNSServer            = $null
    FileServer           = $null
    ExternalIP           = "8.8.8.8"
    TestDomain           = (Get-CimInstance Win32_ComputerSystem).Domain
    # Thresholds (centralised)
    MinFreeDiskGB        = 20
    MaxUptimeHoursWarn   = 168    # 1 week
    MinFreeMemoryPercent = 15
    PingTimeoutMs        = 1000
}

# Detect Gateway
try {
    $Config.Gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
        Sort-Object RouteMetric |
        Select-Object -First 1 -ExpandProperty NextHop)
} catch {
    $Config.Gateway = "192.168.1.1"
}

# Detect DNS
try {
    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object ServerAddresses |
        Select-Object -First 1 -ExpandProperty ServerAddresses
    $Config.DNSServer = if ($dns) { $dns -join ", " } else { "8.8.8.8" }
} catch {
    $Config.DNSServer = "8.8.8.8"
}

# Detect File Server / Domain Controller
try {
    if ($Config.TestDomain -and $Config.TestDomain -ne "WORKGROUP") {
        if (Get-Module -ListAvailable ActiveDirectory) {
            Import-Module ActiveDirectory -ErrorAction SilentlyContinue
            $dc = Get-ADDomainController -Discover -ErrorAction SilentlyContinue
            $Config.FileServer = if ($dc) { $dc.HostName } else { "fileserver.$($Config.TestDomain)" }
        } else {
            $Config.FileServer = "fileserver.$($Config.TestDomain)"
        }
    } else {
        $Config.FileServer = "fileserver.local"
    }
} catch {
    $Config.FileServer = "fileserver.local"
}

Write-Host "Configuration Loaded:" -ForegroundColor Green
$Config | Format-List

# ================= HELPERS =================
function HtmlEncode {
    param($s)
    if ($null -eq $s) { return "-" }
    return ($s.ToString() `
        -replace '&', '&amp;' `
        -replace '<', '&lt;' `
        -replace '>', '&gt;' `
        -replace '"', '&quot;' `
        -replace "'", '&#39;')
}

function New-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Notes = "-",
        [string]$Category = "General"
    )
    [PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Status   = $Status
        Notes    = if ($Notes) { $Notes } else { "-" }
    }
}

function Get-Color($status) {
    switch ($status) {
        "OK"    { "#28a745" }
        "FAIL"  { "#dc3545" }
        "ERROR" { "#fd7e14" }
        "WARN"  { "#ffc107" }
        "INFO"  { "#007bff" }
        default { "#6c757d" }
    }
}

# Faster, timeout-aware ping using .NET
function Test-Ping {
    param($Target, $TimeoutMs = $Config.PingTimeoutMs)
    if (-not $Target) { return "ERROR" }
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($Target, $TimeoutMs)
        if ($reply.Status -eq 'Success') { return "OK" } else { return "FAIL" }
    } catch {
        return "ERROR"
    }
}

function Test-DNS {
    try {
        $server = $Config.DNSServer.Split(",")[0].Trim()
        Resolve-DnsName "google.com" -Server $server -ErrorAction Stop | Out-Null
        return "OK"
    } catch { return "FAIL" }
}

# ================= PARALLEL NETWORK TESTS =================
# Kick off network pings in parallel using runspace jobs 
Write-Host "Running network checks in parallel..." -ForegroundColor Cyan

$pingTargets = @(
    @{ Name = "Gateway";     Target = $Config.Gateway }
    @{ Name = "File Server"; Target = $Config.FileServer }
    @{ Name = "Internet";    Target = $Config.ExternalIP }
)

$pingJobs = foreach ($t in $pingTargets) {
    Start-Job -ScriptBlock {
        param($Target, $TimeoutMs)
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($Target, $TimeoutMs)
            if ($reply.Status -eq 'Success') { "OK" } else { "FAIL" }
        } catch { "ERROR" }
    } -ArgumentList $t.Target, $Config.PingTimeoutMs |
    Add-Member -NotePropertyName CheckName -NotePropertyValue $t.Name -PassThru
}

# DNS check runs locally 
$dnsResult = Test-DNS

# Wait for all ping jobs 
$pingJobs | Wait-Job -Timeout 5 | Out-Null
$pingResults = @{}
foreach ($job in $pingJobs) {
    $pingResults[$job.CheckName] = if ($job.State -eq 'Completed') {
        Receive-Job $job
    } else {
        "ERROR"
    }
    Remove-Job $job -Force
}

# ================= COLLECT DATA =================
$Results = @()
$CS = Get-CimInstance Win32_ComputerSystem
$OS = Get-CimInstance Win32_OperatingSystem

# --- System Info ---
$Results += New-Result "Device Name" "INFO" $env:COMPUTERNAME "System"
$Results += New-Result "User" "INFO" $env:USERNAME "System"
$Results += New-Result "Manufacturer" "INFO" $CS.Manufacturer "System"
$Results += New-Result "Model" "INFO" $CS.Model "System"
$Results += New-Result "Serial Number" "INFO" (Get-CimInstance Win32_BIOS).SerialNumber "System"
$Results += New-Result "OS" "INFO" $OS.Caption "System"
$Results += New-Result "OS Version" "INFO" $OS.Version "System"
$Results += New-Result "Last Boot" "INFO" $OS.LastBootUpTime "System"
$Results += New-Result "Domain" "INFO" $Config.TestDomain "System"
$Results += New-Result "Privilege Level" $(if ($IsAdmin) { "OK" } else { "WARN" }) `
    $(if ($IsAdmin) { "Administrator" } else { "Standard user - some checks limited" }) "System"

# --- Uptime (with threshold) ---
$uptime = (Get-Date) - $OS.LastBootUpTime
$uptimeHours = [math]::Round($uptime.TotalHours, 1)
$uptimeStatus = if ($uptimeHours -gt $Config.MaxUptimeHoursWarn) { "WARN" } else { "OK" }
$Results += New-Result "Uptime" $uptimeStatus "$uptimeHours hours" "System"

# --- Pending Reboot ---
try {
    $rebootPending = $false
    $reasons = @()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $rebootPending = $true; $reasons += "CBS"
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $rebootPending = $true; $reasons += "WindowsUpdate"
    }
    if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) {
        $rebootPending = $true; $reasons += "FileRename"
    }
    $Results += New-Result "Pending Reboot" $(if ($rebootPending) { "WARN" } else { "OK" }) `
        $(if ($rebootPending) { "Reasons: $($reasons -join ', ')" } else { "No reboot pending" }) "System"
} catch {
    $Results += New-Result "Pending Reboot" "ERROR" "Unable to check" "System"
}

# --- Memory pressure ---
try {
    $totalMB = [math]::Round($OS.TotalVisibleMemorySize / 1024, 0)
    $freeMB = [math]::Round($OS.FreePhysicalMemory / 1024, 0)
    $freePct = [math]::Round(($freeMB / $totalMB) * 100, 1)
    $memStatus = if ($freePct -lt $Config.MinFreeMemoryPercent) { "WARN" } else { "OK" }
    $Results += New-Result "Memory" $memStatus "$freeMB MB free of $totalMB MB ($freePct%)" "System"
} catch {
    $Results += New-Result "Memory" "ERROR" "Unable to check" "System"
}

# --- Windows Activation ---
try {
    $lic = Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
    $act = if ($lic) { "OK" } else { "FAIL" }
    $actNotes = if ($lic) { "Licensed" } else { "Not activated" }
} catch {
    $act = "ERROR"; $actNotes = "Check failed"
}
$Results += New-Result "Windows Activation" $act $actNotes "Security"

# --- Defender ---
try {
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $d = Get-MpComputerStatus -ErrorAction Stop
        $defStatus = if ($d.AntivirusEnabled -and $d.RealTimeProtectionEnabled) { "OK" } else { "FAIL" }
        $defNotes = "AV:$($d.AntivirusEnabled) RTP:$($d.RealTimeProtectionEnabled) SigAge:$($d.AntivirusSignatureAge)d"
    } else {
        $defStatus = "ERROR"; $defNotes = "Not Available"
    }
} catch {
    $defStatus = "ERROR"; $defNotes = "Failed (admin required?)"
}
$Results += New-Result "Windows Defender" $defStatus $defNotes "Security"

# --- Firewall ---
try {
    $fw = Get-NetFirewallProfile -ErrorAction Stop
    $disabled = $fw | Where-Object { -not $_.Enabled }
    if ($disabled) {
        $Results += New-Result "Firewall" "FAIL" "Disabled profiles: $($disabled.Name -join ', ')" "Security"
    } else {
        $Results += New-Result "Firewall" "OK" "All profiles enabled" "Security"
    }
} catch {
    $Results += New-Result "Firewall" "ERROR" "Unable to check" "Security"
}

# --- BitLocker ---
try {
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        $blStatus = if ($bl.ProtectionStatus -eq 'On') { "OK" } else { "WARN" }
        $Results += New-Result "BitLocker (C:)" $blStatus "Status: $($bl.ProtectionStatus), Encryption: $($bl.EncryptionPercentage)%" "Security"
    } else {
        $Results += New-Result "BitLocker (C:)" "INFO" "Module not available" "Security"
    }
} catch {
    $Results += New-Result "BitLocker (C:)" "ERROR" "Unable to check (admin required)" "Security"
}

# --- TPM ---
try {
    if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
        $tpm = Get-Tpm -ErrorAction Stop
        $tpmStatus = if ($tpm.TpmPresent -and $tpm.TpmReady) { "OK" } else { "WARN" }
        $Results += New-Result "TPM" $tpmStatus "Present:$($tpm.TpmPresent) Ready:$($tpm.TpmReady) Enabled:$($tpm.TpmEnabled)" "Security"
    } else {
        $Results += New-Result "TPM" "INFO" "Module not available" "Security"
    }
} catch {
    $Results += New-Result "TPM" "ERROR" "Unable to check (admin required)" "Security"
}

# --- SMB1 ---
try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    if ($smb1.State -eq 'Enabled') {
        $Results += New-Result "SMB1 Protocol" "FAIL" "Enabled - security risk" "Security"
    } else {
        $Results += New-Result "SMB1 Protocol" "OK" "Disabled" "Security"
    }
} catch {
    $Results += New-Result "SMB1 Protocol" "ERROR" "Unable to check" "Security"
}

# --- Local admin count ---
try {
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    $count = $admins.Count
    $adminStatus = if ($count -gt 5) { "WARN" } else { "OK" }
    $Results += New-Result "Local Administrators" $adminStatus "$count members" "Security"
} catch {
    $Results += New-Result "Local Administrators" "ERROR" "Unable to enumerate" "Security"
}

# --- Network: parallel results ---
$Results += New-Result "Gateway"     $pingResults["Gateway"]     $Config.Gateway      "Network"
$Results += New-Result "File Server" $pingResults["File Server"] $Config.FileServer   "Network"
$Results += New-Result "DNS"         $dnsResult                   $Config.DNSServer    "Network"
$Results += New-Result "Internet"    $pingResults["Internet"]    $Config.ExternalIP   "Network"

# Network adapter info
$net = Get-NetIPConfiguration | Where-Object IPv4Address | Select-Object -First 1
if ($net) {
    $Results += New-Result "IP Address" "INFO" $net.IPv4Address.IPAddress "Network"
    $Results += New-Result "Gateway Config" "INFO" $net.IPv4DefaultGateway.NextHop "Network"
    $Results += New-Result "Adapter" "INFO" $net.InterfaceAlias "Network"
}

# --- Disk ---
try {
    $disk = Get-PSDrive C
    $freeGB = [math]::Round($disk.Free / 1GB, 2)
    $totalGB = [math]::Round(($disk.Free + $disk.Used) / 1GB, 2)
    $diskStatus = if ($freeGB -lt $Config.MinFreeDiskGB) { "FAIL" } else { "OK" }
    $Results += New-Result "C Drive Space" $diskStatus "$freeGB GB free of $totalGB GB" "Storage"
} catch {
    $Results += New-Result "C Drive Space" "ERROR" "Unavailable" "Storage"
}

# --- Battery---
try {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if ($battery) {
        $Results += New-Result "Battery" "INFO" "Charge: $($battery.EstimatedChargeRemaining)%, Status: $($battery.BatteryStatus)" "Hardware"
    }
} catch { }

# ================= EXPORT JSON =================
$Timestamp = Get-Date -Format yyyyMMdd_HHmmss
$BasePath = "$env:USERPROFILE\Downloads\PC_Audit_$Timestamp"
$JsonPath = "$BasePath.json"
$HtmlPath = "$BasePath.html"

$jsonExport = [PSCustomObject]@{
    ScriptVersion = $ScriptVersion
    GeneratedAt   = $StartTime
    Computer      = $env:COMPUTERNAME
    User          = $env:USERNAME
    Domain        = $Config.TestDomain
    IsAdmin       = $IsAdmin
    Results       = $Results
    Summary       = @{
        OK    = ($Results | Where-Object Status -eq 'OK').Count
        FAIL  = ($Results | Where-Object Status -eq 'FAIL').Count
        WARN  = ($Results | Where-Object Status -eq 'WARN').Count
        ERROR = ($Results | Where-Object Status -eq 'ERROR').Count
        INFO  = ($Results | Where-Object Status -eq 'INFO').Count
    }
}

$jsonExport | ConvertTo-Json -Depth 5 | Out-File $JsonPath -Encoding UTF8
Write-Host "JSON report: $JsonPath" -ForegroundColor Green

# ================= HTML BUILD =================
# Sort: FAIL first, then WARN, ERROR, OK, INFO
$statusOrder = @{ FAIL = 0; WARN = 1; ERROR = 2; OK = 3; INFO = 4 }
$sortedResults = $Results | Sort-Object @{Expression = { $statusOrder[$_.Status] }}, Category, Name

# Group by category
$grouped = $sortedResults | Group-Object Category

# Summary tile
$summary = $jsonExport.Summary
$summaryHtml = @"
<div class="summary">
    <div class="tile" style="background:$(Get-Color 'OK')">
        <div class="num">$($summary.OK)</div><div class="lbl">OK</div>
    </div>
    <div class="tile" style="background:$(Get-Color 'WARN')">
        <div class="num">$($summary.WARN)</div><div class="lbl">WARN</div>
    </div>
    <div class="tile" style="background:$(Get-Color 'FAIL')">
        <div class="num">$($summary.FAIL)</div><div class="lbl">FAIL</div>
    </div>
    <div class="tile" style="background:$(Get-Color 'ERROR')">
        <div class="num">$($summary.ERROR)</div><div class="lbl">ERROR</div>
    </div>
    <div class="tile" style="background:$(Get-Color 'INFO')">
        <div class="num">$($summary.INFO)</div><div class="lbl">INFO</div>
    </div>
</div>
"@

# Build collapsible category sections
$sectionsHtml = foreach ($group in $grouped) {
    $rows = foreach ($r in $group.Group) {
        $color = Get-Color $r.Status
        "<tr>
            <td>$(HtmlEncode $r.Name)</td>
            <td><span class='badge' style='background:$color'>$(HtmlEncode $r.Status)</span></td>
            <td>$(HtmlEncode $r.Notes)</td>
        </tr>"
    }
    @"
<details open>
    <summary><strong>$(HtmlEncode $group.Name)</strong> ($($group.Count) checks)</summary>
    <table>
        <thead><tr><th>Check</th><th>Status</th><th>Details</th></tr></thead>
        <tbody>
            $($rows -join "`n")
        </tbody>
    </table>
</details>
"@
}

$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 1)

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>PC Audit Report - $(HtmlEncode $env:COMPUTERNAME)</title>
<style>
    body { font-family: -apple-system, Segoe UI, Arial, sans-serif; background:#f4f6f8; padding:30px; color:#222; }
    h1 { margin:0 0 5px 0; }
    .meta { color:#666; margin-bottom:20px; font-size:14px; }
    .summary { display:flex; gap:15px; margin-bottom:30px; flex-wrap:wrap; }
    .tile { color:white; padding:20px; border-radius:8px; min-width:100px; text-align:center; box-shadow:0 2px 4px rgba(0,0,0,0.1); }
    .tile .num { font-size:32px; font-weight:bold; }
    .tile .lbl { font-size:13px; opacity:0.9; }
    details { background:white; margin-bottom:15px; border-radius:8px; padding:15px; box-shadow:0 1px 3px rgba(0,0,0,0.08); }
    summary { cursor:pointer; padding:5px; font-size:16px; }
    table { width:100%; border-collapse:collapse; margin-top:10px; }
    th, td { padding:10px; border-bottom:1px solid #eee; text-align:left; }
    thead th { background:#343a40; color:white; position:sticky; top:0; }
    tbody tr:hover { background:#f9f9f9; }
    .badge { color:white; padding:4px 10px; border-radius:4px; font-size:12px; font-weight:bold; }
    footer { margin-top:30px; color:#888; font-size:12px; text-align:center; }
</style>
</head>
<body>
<h1>PC Audit Report</h1>
<div class="meta">
    <strong>$(HtmlEncode $env:COMPUTERNAME)</strong> &middot;
    User: $(HtmlEncode $env:USERNAME) &middot;
    Domain: $(HtmlEncode $Config.TestDomain) &middot;
    Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
</div>

$summaryHtml

$($sectionsHtml -join "`n")

<footer>
    PC Audit Script v$ScriptVersion &middot;
    Completed in $Duration seconds &middot;
    Admin: $IsAdmin &middot;
    Log: $(HtmlEncode $LogPath)
</footer>
</body>
</html>
"@

$html | Out-File $HtmlPath -Encoding UTF8
Write-Host "HTML report: $HtmlPath" -ForegroundColor Green
Write-Host "Audit completed in $Duration seconds." -ForegroundColor Cyan

Stop-Transcript | Out-Null

Start-Process $HtmlPath