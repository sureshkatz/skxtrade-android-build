param([string]$SigningDirectory = (Join-Path $PSScriptRoot '..\SKXTRADE_Private_Signing'))
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Install Flutter stable and add its bin folder to PATH. See README.md.' }
$key = Join-Path $SigningDirectory 'skxtrade-release.jks'
$passwordFile = Join-Path $SigningDirectory 'signing-password.txt'
if (-not (Test-Path -LiteralPath $key) -or -not (Test-Path -LiteralPath $passwordFile)) { throw 'Extract SKXTRADE_Private_Signing.zip beside SKXTRADE_Android, or pass -SigningDirectory with that extracted folder.' }
$resolvedKey = (Resolve-Path -LiteralPath $key).Path.Replace('\','/')
$password = (Get-Content -LiteralPath $passwordFile -Raw).Trim()
@("storeFile=$resolvedKey", "storePassword=$password", 'keyAlias=skxtrade', "keyPassword=$password") | Set-Content -LiteralPath 'android\key.properties' -Encoding Ascii
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
try {
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency preparation failed.' }
  & flutter analyze --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
  & flutter test --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
  & flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
  $apk = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
  if (-not (Test-Path -LiteralPath $apk)) { throw 'Build returned without the expected APK.' }
  Write-Host "APK ready: $apk"
} finally {
  Remove-Item -LiteralPath 'android\key.properties' -Force -ErrorAction SilentlyContinue
}
