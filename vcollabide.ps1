# -------------------------------------------------------------------------
# VCOLLAB IDE AUTOMATED INSTALLER & LAUNCHER
# -------------------------------------------------------------------------
$ErrorActionPreference = "Stop"

# --- CONFIGURATION (EDIT THIS LINK) ---
# Paste your MinIO direct download link or Presigned URL here:
$minioUrl = "http://YOUR_MINIO_IP:9000/bucket/VCollab_IDE_Full.zip" 
$zipName = "VCollab_IDE_Full.zip"
$installRoot = "C:\TheiaSource"
$tempDir = "C:\VCollab_Temp"

# --- STEP 1: CHECK ADMINISTRATOR ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Please run this script as Administrator!"
    exit
}

# --- STEP 2: INSTALL NODE.JS 18 (If Missing) ---
Write-Host "--- 1. Checking Environment ---" -ForegroundColor Cyan
try {
    $nodeVer = node -v
    Write-Host "Node.js detected: $nodeVer" -ForegroundColor Gray
    if ($nodeVer -notmatch "v18") {
        Write-Warning "Node version is not v18. Theia requires Node 18."
        # Optional: Force install logic could go here, but usually safer to warn first
    }
} catch {
    Write-Host "Node.js not found. Installing Node 18 LTS..." -ForegroundColor Yellow
    
    # Create temp dir
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    
    # Download Node 18 MSI
    $nodeUrl = "https://nodejs.org/dist/v18.19.0/node-v18.19.0-x64.msi"
    $nodeInstaller = "$tempDir\node18.msi"
    Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller
    
    # Silent Install
    Write-Host "Installing Node.js... (This takes a minute)" -ForegroundColor Cyan
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeInstaller`" /quiet /norestart" -Wait -PassThru
    
    if ($proc.ExitCode -eq 0) {
        Write-Host "Node.js installed successfully." -ForegroundColor Green
        # REFRESH PATH (Crucial step so we don't need to reboot)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "Path refreshed."
    } else {
        Write-Error "Node.js install failed with exit code $($proc.ExitCode)."
    }
}

# --- STEP 3: INSTALL YARN ---
Write-Host "--- 2. Checking Yarn ---" -ForegroundColor Cyan
try {
    yarn --version | Out-Null
} catch {
    Write-Host "Yarn not found. Installing global yarn..." -ForegroundColor Yellow
    npm install --global yarn
}

# --- STEP 4: DOWNLOAD & EXTRACT APP ---
Write-Host "--- 3. Setting up VCollab IDE ---" -ForegroundColor Cyan

# Check if already installed
if (Test-Path $installRoot) {
    Write-Host "Installation found at $installRoot." -ForegroundColor Gray
    $choice = Read-Host "Do you want to re-download and update? (y/n)"
    if ($choice -eq 'y') {
        Remove-Item -Recurse -Force $installRoot
    } else {
        Write-Host "Skipping download. Launching existing app..." -ForegroundColor Green
        goto LaunchPhase
    }
}

# Download from MinIO
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
$zipPath = "$tempDir\$zipName"

Write-Host "Downloading VCollab IDE from MinIO..." -ForegroundColor Yellow
Write-Host "Source: $minioUrl"
try {
    # Increase timeout for large files
    Invoke-WebRequest -Uri $minioUrl -OutFile $zipPath -TimeoutSec 600
} catch {
    Write-Error "Download failed! Check your MinIO URL. Error: $_"
}

# Extract
Write-Host "Extracting to C:\ (Golden Path)..." -ForegroundColor Yellow
# We extract to C:\ because the zip already contains the folder 'TheiaSource'
Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force

# --- STEP 5: LAUNCH ---
:LaunchPhase
Write-Host "------------------------------------------------" -ForegroundColor Green
Write-Host "SUCCESS! Starting VCollab IDE..." -ForegroundColor Green
Write-Host "------------------------------------------------" -ForegroundColor Green

# Navigate to the browser example folder where the runner is
Set-Location "$installRoot\examples\browser"

# Launch on all interfaces so it's accessible
yarn start --hostname 0.0.0.0 --port 3000