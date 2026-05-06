<#
.SYNOPSIS
    Loads .env file and sets environment variables + generates test-config.json.
.DESCRIPTION
    Call this before running any workshop scripts:
      . .\scripts\load-env.ps1
    
    Reads .env from repo root, sets env vars, and updates config/test-config.json.
#>

$envFile = "$PSScriptRoot\..\\.env"

if (-not (Test-Path $envFile)) {
    Write-Host "`n❌ Plik .env nie istnieje!" -ForegroundColor Red
    Write-Host "   Skopiuj .env.example → .env i uzupełnij wartości:" -ForegroundColor Yellow
    Write-Host "   cp .env.example .env" -ForegroundColor Cyan
    Write-Host ""
    return
}

# Load .env
$loaded = 0
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') {
        $key = $matches[1]
        $val = $matches[2]
        [Environment]::SetEnvironmentVariable($key, $val, "Process")
        $loaded++
    }
}

# Update test-config.json from env vars
$configPath = "$PSScriptRoot\..\config\test-config.json"
$config = @{
    subscription_id = $env:AZURE_SUBSCRIPTION_ID
    resource_group  = $env:AZURE_RESOURCE_GROUP
    location        = $env:AZURE_LOCATION
}
$config | ConvertTo-Json | Out-File $configPath -Encoding utf8

Write-Host "`n✅ Załadowano $loaded zmiennych z .env" -ForegroundColor Green
Write-Host "   Subscription: $($env:AZURE_SUBSCRIPTION_ID)" -ForegroundColor Cyan
Write-Host "   RG:           $($env:AZURE_RESOURCE_GROUP)" -ForegroundColor Cyan
Write-Host "   Location:     $($env:AZURE_LOCATION)" -ForegroundColor Cyan
Write-Host "   Config:       $configPath" -ForegroundColor Cyan
Write-Host ""
