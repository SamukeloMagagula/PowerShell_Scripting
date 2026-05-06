# Folder path
$folder = "C:/tEST"

# Check if folder exists before continuing
if (-not (Test-Path $folder)) {
    Write-Output "Downloads folder not found!"
    exit
}

Write-Output "Starting organization in: $folder"

# List of destination folders to create
$destFolders = @("Documents", "Images", "Installers")

# Loop through each folder name
foreach ($d in $destFolders) {
    # Build full path
    $path = Join-Path $folder $d

    # Create folder only if it doesn't already exist
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
        Write-Output "Created folder: $d"
    }
}

# Get only files in the root folder while ignoring subfolders
$files = Get-ChildItem -Path $folder -File  

# Loop through each file
foreach ($file in $files) {
    # Destination variable set based on file type
    $dest = $null

    # Documents file types
    if ($file.Extension -in ".pdf", ".docx", ".doc", ".txt", ".xlsx", ".xls", ".pptx") {
        $dest = Join-Path $folder "Documents"
    }
    # Image file types
    elseif ($file.Extension -in ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp") {
        $dest = Join-Path $folder "Images"
    }
    # Installer file types
    elseif ($file.Extension -in ".exe", ".zip", ".rar", ".msi", ".7z") {
        $dest = Join-Path $folder "Installers"
    }

    # If a destination was assigned the file will be moved
    if ($dest) {
        try {
            Move-Item $file.FullName -Destination $dest -Force -ErrorAction Stop
            Write-Output "Moved: $($file.Name) → $dest"
        }
        catch {
            # Handle any errors during move 
            Write-Output "Failed to move $($file.Name): $_"
        }
    }
    else {
        # File type not recognized
        Write-Output "Skipped: $($file.Name)  (Unknown type)"
    }
}

# Find all files older than 30 days including subfolders
$oldFiles = Get-ChildItem -Path $folder -File -Recurse | 
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }

# Loop through old files and delete them
foreach ($oldFile in $oldFiles) {
    try {
        Remove-Item $oldFile.FullName -Force -ErrorAction Stop
        Write-Output "Deleted (old): $($oldFile.FullName)"
    }
    catch {
        # Handle deletion errors
        Write-Output "Failed to delete $($oldFile.FullName): $_"
    }
}

Write-Output "Organization & Cleanup Complete"