Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# GUI
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "PC Audit Tool"
$form.Size = New-Object System.Drawing.Size(520,400)
$form.StartPosition = "CenterScreen"

$title = New-Object System.Windows.Forms.Label
$title.Text = "PC Handover Audit"
$title.Font = New-Object System.Drawing.Font("Arial",16,[System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(150,15)
$form.Controls.Add($title)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.Size = New-Object System.Drawing.Size(460,220)
$statusBox.Location = New-Object System.Drawing.Point(20,60)
$statusBox.ReadOnly = $true
$form.Controls.Add($statusBox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Run Audit"
$button.Size = New-Object System.Drawing.Size(160,40)
$button.Location = New-Object System.Drawing.Point(170,300)
$form.Controls.Add($button)

# =========================
# RESULT FUNCTION
# =========================
function Add-Result {
    param($Results, $Category, $Item, $Status, $Notes = "")

    $Results.Add([PSCustomObject]@{
        Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Category     = $Category
        Item         = $Item
        Status       = $Status
        Notes        = $Notes
        ComputerName = $env:COMPUTERNAME
        User         = $env:USERNAME
    })
}

# =========================
# AUDIT FUNCTION
# =========================
function Run-Audit {

    $statusBox.Clear()
    $statusBox.AppendText("Running audit...`r`n")

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Downloads = "$env:USERPROFILE\Downloads"
    $ReportPath = "$Downloads\PC_Audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    # ================= SYSTEM =================
    try {
        $OS = Get-CimInstance Win32_OperatingSystem
        $CS = Get-CimInstance Win32_ComputerSystem

        Add-Result $Results "System" "Device Name" $env:COMPUTERNAME
        Add-Result $Results "System" "User" $env:USERNAME
        Add-Result $Results "System" "Model" "$($CS.Manufacturer) $($CS.Model)"
        Add-Result $Results "System" "Windows Version" $OS.Caption

        $statusBox.AppendText("Device: $env:COMPUTERNAME`r`n")
        $statusBox.AppendText("User: $env:USERNAME`r`n")

    } catch {
        Add-Result $Results "System" "Error" "Failed" $_.Exception.Message
    }

    # ================= WINDOWS ACTIVATION =================
    try {
        $license = Get-CimInstance SoftwareLicensingProduct | Where-Object {$_.PartialProductKey}
        $activated = ($license | Where-Object {$_.LicenseStatus -eq 1})
        $status = if ($activated) {"Activated"} else {"Not Activated"}
        Add-Result $Results "System" "Windows Activation" $status
        $statusBox.AppendText("Windows: $status`r`n")
    } catch {
        Add-Result $Results "System" "Windows Activation" "Check Failed"
    }

    # ================= DEFENDER =================
    try {
        $def = Get-MpComputerStatus
        $defStatus = if ($def.AntivirusEnabled) {"Enabled"} else {"Disabled"}
        Add-Result $Results "Security" "Windows Defender" $defStatus
        $statusBox.AppendText("Defender: $defStatus`r`n")
    } catch {
        Add-Result $Results "Security" "Windows Defender" "Unavailable"
    }

    # ================= TEAMS =================
    try {
        $teams = Get-Process -Name "Teams" -ErrorAction SilentlyContinue
        $teamsStatus = if ($teams) {"Running"} else {"Not Running"}
        Add-Result $Results "Applications" "Microsoft Teams" $teamsStatus
        $statusBox.AppendText("Teams: $teamsStatus`r`n")
    } catch {
        Add-Result $Results "Applications" "Microsoft Teams" "Check Failed"
    }

    # ================= NETWORK =================
    try {
        $net = Get-NetIPConfiguration | Where-Object {$_.IPv4Address}

        foreach ($n in $net) {
            Add-Result $Results "Network" "IP Address" $n.IPv4Address.IPAddress
            Add-Result $Results "Network" "Gateway" $n.IPv4DefaultGateway.NextHop
            Add-Result $Results "Network" "DNS" ($n.DNSServer.ServerAddresses -join ", ")
            
            $statusBox.AppendText("IP: $($n.IPv4Address.IPAddress)`r`n")
            $statusBox.AppendText("DNS: $($n.DNSServer.ServerAddresses -join ', ')`r`n")
        }
    } catch {
        Add-Result $Results "Network" "Error" "Failed"
    }

    # ================= INTERNET =================
    try {
        $internet = Test-Connection 8.8.8.8 -Count 2 -Quiet
        Add-Result $Results "Network" "Internet" $(if($internet){"Connected"}else{"No Internet"})
    } catch {}

    # ================= EXPORT =================
    try {
        $Results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        $statusBox.AppendText("`r`nSaved to:`r`n$ReportPath")
    } catch {
        $statusBox.AppendText("Failed to save report.")
    }
}

# =========================
# BUTTON
# =========================
$button.Add_Click({
    Run-Audit
})

$form.ShowDialog()