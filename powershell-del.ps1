$folderPath = "C:\User\Z"
$currentTime = Get-Date

# Set trigger time (08:00 AM today)
$triggerTime = Get-Date -Hour 8 -Minute 0 -Second 0

if ($currentTime -gt $triggerTime) {
    Write-Output "The time is $currentTime — starting deletion..."

    # Check if folder exists
    if (Test-Path $folderPath) {
        
        # Delete files inside folder
        Get-ChildItem -Path $folderPath -File | Remove-Item -Force
        
        Write-Output "Files deleted successfully."
    }
    else {
        Write-Output "Folder does not exist."
    }
}
else {
    Write-Output "Too early. Current time: $currentTime"
}