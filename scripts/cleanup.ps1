# MusicSync 项目清理脚本
# 清理编译缓存、Python 缓存、临时文件（不包含 Gradle）
# 用法: .\scripts\cleanup.ps1

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "=== MusicSync 项目清理 ===" -ForegroundColor Cyan
Write-Host ""

# 1. Flutter 构建缓存
Write-Host "[1/4] 清理 Flutter 构建缓存..." -ForegroundColor Yellow
$flutterAppDir = Join-Path $projectRoot "music_sync_app"
if (Test-Path (Join-Path $flutterAppDir "pubspec.yaml")) {
    Push-Location $flutterAppDir
    try {
        flutter clean 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  flutter clean 完成" -ForegroundColor Green
        } else {
            Write-Host "  flutter clean 跳过（Flutter 不可用）" -ForegroundColor DarkYellow
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  未找到 Flutter 项目目录，跳过" -ForegroundColor DarkYellow
}
Write-Host ""

# 2. Python 缓存目录
Write-Host "[2/4] 清理 Python 缓存..." -ForegroundColor Yellow
$deletedCount = 0
Get-ChildItem -Path $projectRoot -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  已删除: $($_.FullName)" -ForegroundColor Gray
    $deletedCount++
}
Get-ChildItem -Path $projectRoot -Recurse -Directory -Filter ".pytest_cache" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  已删除: $($_.FullName)" -ForegroundColor Gray
    $deletedCount++
}
if ($deletedCount -eq 0) {
    Write-Host "  没有找到 Python 缓存目录" -ForegroundColor DarkYellow
} else {
    Write-Host "  共删除 $deletedCount 个缓存目录" -ForegroundColor Green
}
Write-Host ""

# 3. Flutter pub 缓存（清理未被当前项目引用的包）
Write-Host "[3/4] 清理 Flutter pub 缓存..." -ForegroundColor Yellow
Push-Location $flutterAppDir
try {
    flutter pub cache clean 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  flutter pub cache clean 完成" -ForegroundColor Green
    } else {
        Write-Host "  flutter pub cache clean 跳过（Flutter 不可用）" -ForegroundColor DarkYellow
    }
} finally {
    Pop-Location
}
Write-Host ""

# 4. Windows 临时文件（Flutter 工具残留）
Write-Host "[4/4] 清理 Windows 临时文件..." -ForegroundColor Yellow
$tempCleanCount = 0
@("$env:TEMP\flutter_tools.*", "$env:TEMP\gradle*.lock", "$env:TEMP\dart_test.*") | ForEach-Object {
    Get-Item $_ -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  已删除: $($_.FullName)" -ForegroundColor Gray
        $tempCleanCount++
    }
}
if ($tempCleanCount -eq 0) {
    Write-Host "  没有找到 Flutter 临时文件" -ForegroundColor DarkYellow
} else {
    Write-Host "  共删除 $tempCleanCount 个临时文件/目录" -ForegroundColor Green
}
Write-Host ""

Write-Host "=== 清理完成 ===" -ForegroundColor Cyan
