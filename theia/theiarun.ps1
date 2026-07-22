Set-Location "C:\theia-ide-master\examples\browser"
Write-Output "Starting Theia server on port 3000..."
$logFile = "C:\VCollab\logs\Theia.log"
$errorFile = "C:\VCollab\logs\TheiaError.log"

Start-Process -FilePath "npm.cmd" -ArgumentList "run start" -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $errorFile

Set-Location ..
Write-Output "Started Theia server on port 3000..."
