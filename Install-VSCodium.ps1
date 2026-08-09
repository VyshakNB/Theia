<#
.SYNOPSIS
    Installs the VSCodium web IDE: unzips it, registers a scheduled task that
    runs it at every boot, and starts it.

.DESCRIPTION
    Keep this file next to vscodium.zip. Run once per VM from an elevated
    PowerShell:

        powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-VSCodium.ps1

    Four steps, nothing else:
        1. check it is elevated
        2. unzip to C:\vscodium
        3. register scheduled task 'VSCodiumWebServer' (at startup, as SYSTEM,
           unlimited runtime, auto-restart on failure)
        4. start it and confirm the port answers

    Everything the IDE needs at runtime - the Copilot login persistence patch and
    the bundled extensions - is handled by scripts\Start-VSCodium.ps1 inside the
    zip, on every start.

.EXAMPLE
    .\Install-VSCodium.ps1

.EXAMPLE
    .\Install-VSCodium.ps1 -Port 3000 -WorkspaceDir 'D:\projects'
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]    $Port        = 3000,
    [string] $BindAddress = '0.0.0.0',
    [string] $TaskName    = 'VSCodiumWebServer',

    # Path prefix the IDE is served under. Defaults to '/code' to match the
    # V-Collab agent, which reverse-proxies :9000/code/... to this server on :3000
    # without stripping the /code segment. Without it the IDE 404s every request,
    # because its router only knows /, /static and /callback.
    #
    # This is only half the job: the workspace gateway must also send
    #   X-Forwarded-Prefix: /api/v1/workspaces/<workspaceid>/apps/code
    # so generated asset URLs (/stable-<commit>/static/...) carry the full
    # browser-visible prefix. '/code' alone makes the IDE reachable but its assets
    # resolve to the wrong place. Pass '' to serve at the root instead.
    [string] $ServerBasePath = '/code',

    # All of these default to siblings of the Codium-files folder, so dropping
    # Codium-files into C:\VCollab gives C:\VCollab\vscodium, C:\VCollab\vscodium-server
    # and C:\VCollab\workspace. Resolved in the body - see the note below.
    [string] $BaseDir,
    [string] $InstallDir,
    [string] $ServerDataDir,
    [string] $WorkspaceDir,
    [string] $ZipPath
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------- script folder
# $PSScriptRoot is empty in param() defaults when [CmdletBinding()] is present,
# and also whenever the script is not run from a file at all - pasted into the
# console, run through Invoke-Expression, or ISE with unsaved content. Falling
# back here is what stops "Cannot bind argument to parameter 'Path' because it is
# an empty string".
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir) -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ZipPath))   { $ZipPath   = Join-Path $scriptDir 'vscodium.zip' }

# --------------------------------------------------------------- target layout
# Everything hangs off the folder that contains Codium-files, so the whole
# install stays together: drop Codium-files into C:\VCollab and you get
#   C:\VCollab\Codium-files\   this script + the zip
#   C:\VCollab\vscodium\       the IDE            (replaced on re-install)
#   C:\VCollab\vscodium-server\ settings, extensions, logs  (kept across re-installs)
#   C:\VCollab\workspace\      default folder the IDE opens
# vscodium-server is a *sibling* of vscodium on purpose: a re-install deletes the
# install folder, and user settings/extensions must survive that.
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = Split-Path -Parent $scriptDir }
if ([string]::IsNullOrWhiteSpace($BaseDir)) { $BaseDir = $scriptDir }   # script sat at a drive root
if ([string]::IsNullOrWhiteSpace($InstallDir))    { $InstallDir    = Join-Path $BaseDir 'vscodium' }
if ([string]::IsNullOrWhiteSpace($ServerDataDir)) { $ServerDataDir = Join-Path $BaseDir 'vscodium-server' }
if ([string]::IsNullOrWhiteSpace($WorkspaceDir))  { $WorkspaceDir  = Join-Path $BaseDir 'workspace' }

function Write-Step { param([string] $m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string] $m) Write-Host "    $m" -ForegroundColor Green }
function Write-Info { param([string] $m) Write-Host "    $m" -ForegroundColor Gray }

Write-Host ''
Write-Host 'VSCodium web IDE installer' -ForegroundColor White
Write-Host '--------------------------' -ForegroundColor White
Write-Info ("base        {0}" -f $BaseDir)
Write-Info ("IDE         {0}" -f $InstallDir)
Write-Info ("state       {0}" -f $ServerDataDir)
Write-Info ("workspace   {0}" -f $WorkspaceDir)
Write-Info ("port        {0} on {1}" -f $Port, $BindAddress)

# ------------------------------------------------------------------ 1. elevated
Write-Step 'Checking privileges'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw ("Run this from an Administrator PowerShell. Registering a SYSTEM " +
           "scheduled task and writing to $InstallDir both require elevation.")
}
Write-Ok ("elevated as {0}" -f $identity.Name)

# -------------------------------------------------------------------- 2. unzip
Write-Step "Unzipping to $InstallDir"
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw ("Cannot find '$ZipPath'. Keep vscodium.zip in the same folder as this " +
           "script, or pass -ZipPath 'C:\path\to\vscodium.zip'.")
}
Write-Info ("source: {0} ({1:N0} MB)" -f $ZipPath, ((Get-Item -LiteralPath $ZipPath).Length / 1MB))

# Release any previous install so its files are not locked.
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*Start-VSCodium*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
# Match on the command line, not on $InstallDir\node.exe: an earlier install at a
# different path would otherwise keep holding the port, and the launcher treats a
# busy port as "already running" and exits quietly. Only codium-server processes
# have out\server-main.js on their command line, so unrelated node apps are safe.
Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*server-main.js*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

if (Test-Path -LiteralPath $InstallDir) {
    Write-Info "replacing existing $InstallDir"
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}

# .NET rather than Expand-Archive: ~2800 files, and Expand-Archive is very slow
# at that count on PowerShell 5.1.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('vscodium-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $tmp)
    $sw.Stop()

    # Tolerate both layouts: a single wrapper folder, or files at the zip root.
    $roots = @(Get-ChildItem -LiteralPath $tmp -Force)
    $src = $tmp
    if ($roots.Count -eq 1 -and $roots[0].PSIsContainer) { $src = $roots[0].FullName }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'node.exe'))) {
        throw "'$ZipPath' does not look like a VSCodium server build (no node.exe inside)."
    }

    $parent = Split-Path -Parent $InstallDir
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Move-Item -LiteralPath $src -Destination $InstallDir -Force
    Write-Ok ("unzipped in {0:N0}s" -f $sw.Elapsed.TotalSeconds)
} finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$launcher = Join-Path $InstallDir 'scripts\Start-VSCodium.ps1'
if (-not (Test-Path -LiteralPath $launcher)) { throw "Missing $launcher" }
# A zip that arrived over a network share marks its scripts, and PowerShell then
# refuses to run them.
Get-ChildItem -LiteralPath $InstallDir -Recurse -Filter '*.ps1' -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }

# --------------------------------------------------------------------- 3. task
Write-Step "Registering scheduled task '$TaskName'"
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden ' +
              ('-File "{0}" -Port {1} -BindAddress {2} -ServerDataDir "{3}" -WorkspaceDir "{4}"' -f `
                  $launcher, $Port, $BindAddress, $ServerDataDir.TrimEnd('\'), $WorkspaceDir.TrimEnd('\'))

if (-not [string]::IsNullOrWhiteSpace($ServerBasePath)) {
    $bp = '/' + $ServerBasePath.Trim().Trim('/')   # exactly one leading slash, no trailing one
    $launchArgs += (' -ServerBasePath "{0}"' -f $bp)
    Write-Info ("serving under sub-path {0}" -f $bp)
}

$action  = New-ScheduledTaskAction -Execute $psExe -Argument $launchArgs
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT30S'    # let networking and disks settle before binding

# ExecutionTimeLimit 0 = unlimited. Task Scheduler's default is 72 hours, which
# would silently kill the IDE after three days of VM uptime.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Ok 'runs at startup as SYSTEM, unlimited runtime, auto-restart every minute'

# -------------------------------------------------------------------- 4. start
Write-Step 'Starting'
Start-ScheduledTask -TaskName $TaskName

$deadline  = (Get-Date).AddSeconds(120)
$listening = $false
while ((Get-Date) -lt $deadline) {
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
        $listening = $true; break
    }
    Start-Sleep -Seconds 2
}

if ($listening) {
    Write-Ok "listening on port $Port"
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 30
        Write-Ok ("HTTP {0} from the web workbench" -f $r.StatusCode)
    } catch {
        Write-Info ("port open but HTTP probe failed: {0}" -f $_.Exception.Message)
    }
} else {
    Write-Info "nothing listening on port $Port yet - check the log below"
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host ("  URL      http://{0}:{1}/    (no token)" -f $env:COMPUTERNAME, $Port)
Write-Host ("  Logs     {0}\logs\launcher.log" -f $ServerDataDir)
Write-Host ("  Stop     {0}\scripts\Stop-VSCodium.ps1" -f $InstallDir)
Write-Host ("  Start    Start-ScheduledTask -TaskName '{0}'" -f $TaskName)
Write-Host ''
