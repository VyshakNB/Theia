Set-Location "C:\theia-ide-master\examples\browser"
Write-Output "Starting Theia server on port 3000..."
$logFile = "C:\VCollab\logs\Theia.log"
$errorFile = "C:\VCollab\logs\TheiaError.log"


$env:NODE_USE_ENV_PROXY = "1"
$env:HTTP_PROXY = "http://10.38.107.203:3120"
$env:HTTPS_PROXY = "http://10.38.107.203:3120"
$env:NO_PROXY = "localhost,127.0.0.1,::1"

Start-Process -FilePath "npm.cmd" -ArgumentList "run start" -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $errorFile

Set-Location ..
Write-Output "Started Theia server on port 3000..."
