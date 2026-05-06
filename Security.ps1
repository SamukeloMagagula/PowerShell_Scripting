# Output file
$reportFile = "$env:USERPROFILE\Desktop\SecurityAudit_Report.html"

Write-Output "Running Local Security & User Audit..."

#Get Administrator accounts
$Admins = (Get-LocalGroupMember -Group "Administrators" |
           Where-Object ObjectClass -eq "User").Name |
           ForEach-Object { $_.Split('\')[-1] }

#Get all local users with last login
$Users = Get-LocalUser | Select-Object `
    Name,
    Enabled,
    @{Name="LastLogin"; Expression={
        if ($_.LastLogon) { $_.LastLogon.ToString("yyyy-MM-dd HH:mm:ss") }
        else { "Never" }
    }},
    @{Name="IsAdministrator"; Expression={
        if ($Admins -contains $_.Name) { "Yes" } else { "No" }
    }}

#Check Windows Defender status 
$Def = Get-MpComputerStatus
$Defender = [PSCustomObject]@{
    AntivirusEnabled     = $Def.AntivirusEnabled
    RealTimeProtection   = $Def.RealTimeProtectionEnabled
    SignaturesUpToDate   = if (((Get-Date) - $Def.AntivirusSignatureLastUpdated).Days -le 3) { "Yes" } else { "No" }
}

#Create HTML report
$style = @"
<style>
body { font-family: Arial; margin:40px; background:#f4f4f4; }
h1 { color:#1a73e8; }
table { width:100%; border-collapse:collapse; background:white; }
th, td { padding:10px; border-bottom:1px solid #ddd; }
th { background:#1a73e8; color:white; }
</style>
"@

$html = @"
$style
<h1>Local Security & User Audit Report</h1>
<p><b>Date:</b> $(Get-Date)</p>
<p><b>Computer Name:</b> $env:COMPUTERNAME</p>

<h2>1. Local User Accounts</h2>
$($Users | ConvertTo-Html -Fragment)

<h2>2. Windows Defender Status</h2>
$($Defender | ConvertTo-Html -Fragment)
"@

#Save report
$html | Out-File $reportFile -Encoding utf8
Write-Output "Audit complete. Report saved to: $reportFile"