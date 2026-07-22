# --- Setup ---
$dir = "C:\theia-setup-temp"
if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# --- 1. Node.js v22.22.0 and Yarn (classic 1.x) ---
Write-Host "Installing Node.js..."
$url = "https://nodejs.org/dist/v22.22.0/node-v22.22.0-x64.msi"
Invoke-WebRequest $url -OutFile "$dir\node.msi"
Start-Process "msiexec.exe" -ArgumentList "/i `"$dir\node.msi`" /qn" -Wait

Write-Host "Installing Yarn..."
$url = "https://classic.yarnpkg.com/latest.msi"
Invoke-WebRequest $url -OutFile "$dir\yarn.msi"
Start-Process "msiexec.exe" -ArgumentList "/i `"$dir\yarn.msi`" /qn" -Wait

# --- 2. Python 3.12.10 (needed by node-gyp for native module builds) ---
Write-Host "Installing Python..."
$url = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
Invoke-WebRequest $url -OutFile "$dir\python.exe"
Start-Process "$dir\python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait

# --- 3. Git (Using v2.47.1 as example) ---
Write-Host "Installing Git..."
$url = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
Invoke-WebRequest $url -OutFile "$dir\git.exe"
Start-Process "$dir\git.exe" -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS" -Wait

# --- 4. Visual Studio Build Tools (C++ workload) ---
# Required to compile Theia's native Node modules (e.g. nsfw) via node-gyp during `yarn install`.
Write-Host "Installing Visual Studio Build Tools..."
$url = "https://aka.ms/vs/17/release/vs_buildtools.exe"
Invoke-WebRequest $url -OutFile "$dir\vs_buildtools.exe"
Start-Process "$dir\vs_buildtools.exe" -ArgumentList "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" -Wait

# Silent installers above update the Machine/User PATH in the registry, but not this process's
# environment. Refresh it now so node/yarn/git/python are usable for the rest of this script.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# --- 5. Download theiarun.ps1 from MinIO ---
$minioUrl = "http://minio-api.apps.vcollab-cl1.cloud.vssi.com/theia/theiarun.ps1"
$theiaRunScriptPath = "C:\theiarun.ps1"
Invoke-WebRequest -Uri $minioUrl -OutFile $theiaRunScriptPath

# --- 6. Clone latest stable Theia and build the browser IDE ---
$theiaVersion = "v1.73.1"   # pinned eclipse-theia/theia release; bump this when updating Theia
$theiaDir = "C:\theia-ide-master"
if (Test-Path $theiaDir) { Remove-Item $theiaDir -Recurse -Force }

Write-Host "Cloning eclipse-theia/theia $theiaVersion..."
# core.longpaths is required: some test-fixture paths under examples/api-samples exceed Windows'
# default 260-character path limit.
git clone -c core.longpaths=true --depth 1 --branch $theiaVersion https://github.com/eclipse-theia/theia.git $theiaDir

Write-Host "Branding the browser app as VCollab IDE..."
$browserPkgPath = "$theiaDir\examples\browser\package.json"
$pkg = Get-Content $browserPkgPath -Raw | ConvertFrom-Json
$pkg.theia | Add-Member -NotePropertyName "appName" -NotePropertyValue "VCollab IDE" -Force
$pkg.theia.frontend.config.applicationName = "VCollab IDE"
$pkg | ConvertTo-Json -Depth 20 | Set-Content $browserPkgPath

Set-Location $theiaDir
Write-Host "Installing Theia dependencies (this can take a while)..."
yarn install --network-timeout 600000

Write-Host "Compiling Theia packages..."
yarn compile

Write-Host "Building the browser IDE (production)..."
yarn browser build:production

# Define task action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\theiarun.ps1"'

# Define trigger
$trigger = New-ScheduledTaskTrigger -AtStartup

# Register the task
Register-ScheduledTask -TaskName "TheiaRun" -Action $action -Trigger $trigger -Description "Run Theia script at startup" -User "SYSTEM" -RunLevel Highest -Force

# Run Theia From Task Scheduler
Start-ScheduledTask -TaskName "TheiaRun"
