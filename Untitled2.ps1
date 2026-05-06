# Folder path
$folder = "C:/tEST"

if (Test-Path $folder) {

    Write-Output "Folder does exist"

    # List of destination folders to create
    $destFolders = @("Documents", "Images", "Installers")

    # Loop through each folder name
    foreach ($d in $destFolders) {

        # Create full path for each folder
        $path = Join-Path $folder $d

        # Check if the folder already exists
        if (!(Test-Path $path)) {
            # Create the folder if it does not exist
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }

    # Get all files in the main folder (ignore subfolders)
    $files = Get-ChildItem -Path $folder -File

    # Check if there are no files
    if ($files.Count -eq 0) {

        # Display message if folder is empty
        Write-Output "No files in the folder"
    }

    # Loop through each file
    foreach ($file in $files) {

        # Check if file is a document
        if ($file.Extension -in ".pdf", ".docx") {

            # Move file to Documents folder
            Move-Item $file.FullName -Destination (Join-Path $folder "Documents")
        }

        # Check if file is an image
        elseif ($file.Extension -in ".jpg", ".png") {

            # Move file to Images folder
            Move-Item $file.FullName -Destination (Join-Path $folder "Images")
        }

        # Check if file is an installer
        elseif ($file.Extension -in ".zip", ".exe") {

            # Move file to Installers folder
            Move-Item $file.FullName -Destination (Join-Path $folder "Installers")
        }

        # If file type does not match any category
        else {

            # Display skipped file name
            Write-Output "Skipped: $($file.Name)"
        }
    }

    # Get files older than 30 days
    $oldFiles = Get-ChildItem -Path $folder -File | Where-Object {

        # Compare file date with today's date minus 30 days
        $_.LastWriteTime -lt (Get-Date).AddDays(-30)
    }

    # Loop through old files
    foreach ($oldFile in $oldFiles) {

        # Delete the old file
        Remove-Item $oldFile.FullName -Force

        # Display deleted file name
        Write-Output "Deleted: $($oldFile.Name)"
    }

}
else {

    # Display message if folder does not exist
    Write-Output "Folder does not exist"
}