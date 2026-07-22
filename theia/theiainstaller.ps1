$dir = "C:\theia-setup-temp"
if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# --- 1. Node.js v22.22.0 (runtime for `npm run browser start`; bundles npm) ---
Write-Host "Installing Node.js..."
$url = "https://nodejs.org/dist/v22.22.0/node-v22.22.0-x64.msi"
Invoke-WebRequest $url -OutFile "$dir\node.msi"
Start-Process "msiexec.exe" -ArgumentList "/i `"$dir\node.msi`" /qn" -Wait

# --- 2. Git ---
Write-Host "Installing Git..."
$url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
Invoke-WebRequest $url -OutFile "$dir\git.exe"
Start-Process "$dir\git.exe" -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS" -Wait

# --- 3. Download theiarun.ps1 from MinIO ---
$minioUrl = "http://minio-api.apps.vcollab-cl1.cloud.vssi.com/theia/theiarun.ps1"
$theiaRunScriptPath = "C:\theiarun.ps1"
Invoke-WebRequest -Uri $minioUrl -OutFile $theiaRunScriptPath

# Define task action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\theiarun.ps1"'

# Define trigger
$trigger = New-ScheduledTaskTrigger -AtStartup

# Register the task
Register-ScheduledTask -TaskName "TheiaRun" -Action $action -Trigger $trigger -Description "Run Theia script at startup" -User "SYSTEM" -RunLevel Highest -Force

# Run Theia From Task Scheduler
Start-ScheduledTask -TaskName "TheiaRun"
