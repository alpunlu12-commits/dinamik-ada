# Dinamik Ada (Windows) kurulum betiği.
#
# Ne yapar:
#   1. Windows sürümünü ve .NET SDK'yı kontrol eder
#   2. Kaynaktan derler (tek dosyalık DinamikAda.exe)
#   3. %LOCALAPPDATA%\Programs\DinamikAda altına kurar, Başlat menüsüne kısayol ekler
#   4. Uygulamayı açar
#
# Yönetici yetkisi istemez. Çalıştırmadan önce bu dosyayı okuyabilirsin —
# kısa tutuldu, hepsi burada.
#
# Kullanım (depo kökünden):
#   powershell -ExecutionPolicy Bypass -File Windows\install.ps1
# Kaldırmak için:
#   powershell -ExecutionPolicy Bypass -File Windows\install.ps1 -Uninstall

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

function Ok($m)   { Write-Host "  √ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  x $m" -ForegroundColor Red; exit 1 }

$dest     = Join-Path $env:LOCALAPPDATA 'Programs\DinamikAda'
$exe      = Join-Path $dest 'DinamikAda.exe'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Dinamik Ada.lnk'
$runKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Write-Host ''
Write-Host 'Dinamik Ada (Windows) kurulumu' -ForegroundColor White
Write-Host ''

# Çalışan bir kopya varsa dosya kilitli olur.
if (Get-Process -Name 'DinamikAda' -ErrorAction SilentlyContinue) {
    Die 'Dinamik Ada çalışıyor. Önce bildirim alanındaki simgesine sağ tıklayıp "Çık" de.'
}

if ($Uninstall) {
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKey -Name 'DinamikAda' -ErrorAction SilentlyContinue
    Ok 'Uygulama, kısayol ve başlangıç kaydı kaldırıldı.'
    Write-Host ''
    Write-Host "  Ayarlar ve raf listesi duruyor: $env:APPDATA\DinamikAda"
    Write-Host '  Onları da silmek istersen klasörü elle sil.'
    exit 0
}

# --- 1. Windows sürümü ---
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Die "Windows 10 sürüm 2004 (derleme 19041) veya üstü gerekiyor. Sende: derleme $build"
}
Ok "Windows derleme $build"

# --- 2. .NET SDK ---
$hasSdk = $false
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    foreach ($line in (& dotnet --list-sdks)) {
        if ($line -match '^(\d+)\.' -and [int]$Matches[1] -ge 10) { $hasSdk = $true }
    }
}
if (-not $hasSdk) {
    Warn '.NET 10 SDK kurulu değil.'
    Write-Host ''
    Write-Host '  Şu komutu çalıştır, kurulum bitince yeni bir PowerShell penceresinde bu betiği tekrar çalıştır:'
    Write-Host '    winget install Microsoft.DotNet.SDK.10' -ForegroundColor White
    Write-Host ''
    exit 1
}
Ok '.NET SDK bulundu'

# --- 3. Derle ---
$rid = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$out = Join-Path $PSScriptRoot "bin\publish\$rid"
Write-Host "  Derleniyor ($rid)… ilk seferde paketler indirildiği için birkaç dakika sürebilir."
& dotnet publish (Join-Path $PSScriptRoot 'DinamikAda.Windows.csproj') -c Release -r $rid -o $out --nologo -v quiet
if ($LASTEXITCODE -ne 0) { Die 'Derleme başarısız. Yukarıdaki hata mesajına bak.' }
Ok 'Derlendi'

# --- 4. Kur ---
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $out 'DinamikAda.exe') $exe -Force
Ok "Kuruldu: $exe"

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($shortcut)
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $dest
$lnk.Description = 'Dinamik Ada — ekranın üstünde Dynamic Island tarzı ada'
$lnk.Save()
Ok 'Başlat menüsüne kısayol eklendi'

# --- 5. Aç ---
Start-Process $exe
Write-Host ''
Ok 'Dinamik Ada açıldı: ekranın üst ortasına bak, ayarlar bildirim alanındaki simgede.'
Write-Host ''
