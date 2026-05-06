Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CONFIGURATION
$Config = @{
    Gateway     = ""
    DNSServer   = ""
    FileServer  = ""
    TestDomain  = (Get-WmiObject Win32_ComputerSystem).Domain
    ExternalIP  = ""
    RefreshRate = 10
}

# SAFE UTILITY FUNCTIONS
function Test-SafeConnection($target) {
    try {
        if ([string]::IsNullOrWhiteSpace($target)) { return "ERROR" }
        $result = Test-Connection $target -Count 1 -Quiet -ErrorAction Stop
        if ($result) {
            return "OK"
        } else {
            return "FAIL"
        }
    } catch {
        return "ERROR"
    }
}

function Test-SafeDNS {
    try {
        if (-not $Config.TestDomain -or -not $Config.DNSServer) { return "ERROR" }
        Resolve-DnsName $Config.TestDomain -Server $Config.DNSServer -ErrorAction Stop | Out-Null
        return "OK"
    } catch {
        return "FAIL"
    }
}

function Get-SafeDiskStatus {
    try {
        $disk = Get-PSDrive C -ErrorAction Stop
        $freeGB = [math]::Round($disk.Free/1GB,2)

        if ($freeGB -lt 0) { return @{Status="ERROR"; Value="Unknown"} }
        elseif ($freeGB -lt 10) { return @{Status="FAIL"; Value="$freeGB GB"} }
        else { return @{Status="OK"; Value="$freeGB GB"} }

    } catch {
        return @{Status="ERROR"; Value="Unavailable"}
    }
}

# FORM SETUP
$form = New-Object System.Windows.Forms.Form
$form.Text = "NetSentinel - Enterprise Monitor"
$form.Size = New-Object System.Drawing.Size(800,500)
$form.StartPosition = "CenterScreen"

# UI HELPERS
function New-StatusLabel($text, $yPos) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "$text : Checking..."
    $label.Size = "700,30"
    $label.Location = "20,$yPos"
    $label.Font = "Segoe UI,12"
    $form.Controls.Add($label)
    return $label
}

function Set-Status($label, $name, $state, $extra="") {
    switch ($state) {
        "OK" {
            $label.ForeColor = "Green"
            $label.Text = "$name : OK $extra"
        }
        "FAIL" {
            $label.ForeColor = "Red"
            $label.Text = "$name : FAIL $extra"
        }
        "ERROR" {
            $label.ForeColor = "Orange"
            $label.Text = "$name : ERROR $extra"
        }
        default {
            $label.ForeColor = "Gray"
            $label.Text = "$name : UNKNOWN"
        }
    }
}
# CREATE LABELS
$lblGateway = New-StatusLabel "Gateway" 30
$lblServer  = New-StatusLabel "File Server" 70
$lblDNS     = New-StatusLabel "DNS" 110
$lblInternet= New-StatusLabel "Internet" 150
$lblDisk    = New-StatusLabel "Disk Space" 190

# MAIN HEALTH CHECK
function RunHealthCheck {

    try {

        # Gateway
        $gwStatus = Test-SafeConnection $Config.Gateway
        Set-Status $lblGateway "Gateway" $gwStatus

        # File Server
        $fsStatus = Test-SafeConnection $Config.FileServer
        Set-Status $lblServer "File Server" $fsStatus

        # DNS
        $dnsStatus = Test-SafeDNS
        Set-Status $lblDNS "DNS" $dnsStatus

        # Internet
        $netStatus = Test-SafeConnection $Config.ExternalIP
        Set-Status $lblInternet "Internet" $netStatus

        # Disk
        $disk = Get-SafeDiskStatus
        Set-Status $lblDisk "Disk Space" $disk.Status "($($disk.Value) free)"

    } catch {
        # Global fallback (nothing crashes)
        $lblGateway.Text = "Critical Error in Health Check"
        $lblGateway.ForeColor = "Red"
    }
}

# TIMER (AUTO REFRESH)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $Config.RefreshRate * 1000
$timer.Add_Tick({ RunHealthCheck })
$timer.Start()

# REFRESH BUTTON
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh Now"
$btnRefresh.Size = "150,40"
$btnRefresh.Location = "300,250"
$btnRefresh.Add_Click({ Run-HealthCheck })
$form.Controls.Add($btnRefresh)

# INITIAL RUN
RunHealthCheck

# START UI
$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()