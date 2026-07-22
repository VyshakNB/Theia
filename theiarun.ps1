Set-Location "C:\theia-ide-master"
Write-Output "Starting Theia server on port 3000..."
$command = "npm"
$arguments = "run browser start" 
$logFile = "C:\VCollab\logs\Theia.log"
$errorFile = "C:\VCollab\logs\TheiaError.log"

Start-Process -FilePath "npm.cmd" -ArgumentList "run browser start" -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $errorFile

#npm run browser start
cd ..
Write-Output "Started Theia server on port 3000..."