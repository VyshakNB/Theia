# --- 1. Node.js v22.22.0 and Yarn ---
Write-Host "Installing Node.js..."
$url = "https://nodejs.org/dist/v22.22.0/node-v22.22.0-x64.msi"
Invoke-WebRequest $url -OutFile "$dir\node.msi"
Start-Process "msiexec.exe" -ArgumentList "/i `"$dir\node.msi`" /qn" -Wait

Write-Host "Installing Yarn..."
$url = "https://classic.yarnpkg.com/latest.msi"
Invoke-WebRequest $url -OutFile "$dir\yarn.msi"
Start-Process "msiexec.exe" -ArgumentList "/i `"$dir\yarn.msi`" /qn" -Wait
 
# --- 2. Python 3.12.10 ---
Write-Host "Installing Python..."
$url = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
Invoke-WebRequest $url -OutFile "$dir\python.exe"
Start-Process "$dir\python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
 
# --- 3. Git (Using v2.47.1 as example) ---
Write-Host "Installing Git..."
$url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
Invoke-WebRequest $url -OutFile "$dir\git.exe"
Start-Process "$dir\git.exe" -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS" -Wait
 
# --- 4. 7-Zip (Using v24.09 as example) ---
Write-Host "Installing 7-Zip..."
$url = "https://www.7-zip.org/a/7z2409-x64.exe"
Invoke-WebRequest $url -OutFile "$dir\7z.exe"
Start-Process "$dir\7z.exe" -ArgumentList "/S" -Wait

# Step 5: Download Theiarun PS1 file from MinIO
$minioUrl = "http://minio-api.apps.vcollab-cl1.cloud.vssi.com/theia/theiarun.ps1"
$zipPath = "C:\theiarun.ps1"
#Write-Host "Downloading Theiarun package from MinIO..."
# $ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $minioUrl -OutFile $zipPath

# Step 6: Download ZIP file from MinIO
#$minioUrl = "http://minio-api.apps.vcollab-cl1.cloud.vssi.com/theia/theia-ide-master.zip"
#$zipPath = "C:\theia.zip"
#Write-Host "Downloading Theia package from MinIO..."
#$ProgressPreference = 'SilentlyContinue'
#Start-BitsTransfer -Source $minioUrl -Destination $zipPath -DisplayName "TheiaDownload" -Description "Downloading #Theia IDE" -Priority Foreground
#Invoke-WebRequest -Uri $minioUrl -OutFile $zipPath

# Step 7: Extract ZIP to C:\theia
# $extractPath = "C:\theia"
# if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
# Expand-Archive -Path $zipPath -DestinationPath $extractPath
# Add-Type -AssemblyName System.IO.Compression.FileSystem
# [System.IO.Compression.ZipFile]::ExtractToDirectory("C:\theia.zip", "C:\theia")

# Define task action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\theiarun.ps1"'

# Define trigger
$trigger = New-ScheduledTaskTrigger -AtStartup

# Register the task
Register-ScheduledTask -TaskName "TheiaRun" -Action $action -Trigger $trigger -Description "Run Theia script at startup" -User "SYSTEM" -RunLevel Highest -Force

# Run Theia From Task Scheduler
Start-ScheduledTask -TaskName "TheiaRun"

