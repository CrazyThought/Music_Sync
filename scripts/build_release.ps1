# MusicSync 一键发布构建脚本（App + PC）
# ============================================================
# 功能：读取 App 与 PC 当前版本 → 询问新版本名(x.y.z，App 构建号自动+1) →
#       同步更新两端版本文件 → 依次构建 Android APK 与 PC exe →
#       统一重命名归档到项目根 dist/
# 用法: .\scripts\build_release.ps1
# 前置: flutter 可用；Python + PyInstaller 已就绪（PC 打包含 PyInstaller）
#       已配置 android/key.properties(signingConfigs.release)
# 产物: dist\MusicSync-Vx.y.z.apk 与 dist\MusicSync-Vx.y.z.exe
# ============================================================

$ErrorActionPreference = "Stop"

# 项目根目录 = scripts 的上层目录
$projectRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $projectRoot "music_sync_app"
$pcDir = Join-Path $projectRoot "music_sync_pc"

# 统一发布目录（项目根，.gitignore 已忽略，不会误提交）
$distDir = Join-Path $projectRoot "dist"

# ---- App 端版本文件 ----
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$appSettingsPath = Join-Path $appDir "lib\screens\settings_screen.dart"
$flutterApkPath = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"

# ---- PC 端版本文件 ----
$constantsPath = Join-Path $pcDir "utils\constants.py"
$pcSettingsPath = Join-Path $pcDir "pages\settings_page.py"
$pcBuildSpecPath = Join-Path $pcDir "build.spec"
$pcExePath = Join-Path $pcDir "dist\MusicSync.exe"

# ============================================================
# 步骤 1：解析两端当前版本
# ============================================================
Write-Host "=== MusicSync 一键发布构建 (App + PC) ===" -ForegroundColor Cyan
Write-Host ""

foreach ($p in @($pubspecPath, $constantsPath)) {
    if (-not (Test-Path $p)) {
        Write-Host "错误：未找到 $p" -ForegroundColor Red
        exit 1
    }
}

# 统一用 .NET 读写：UTF-8 无 BOM 的读写在各版本 PowerShell 下行为一致
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$pubspecContent = [System.IO.File]::ReadAllText($pubspecPath)
$constantsContent = [System.IO.File]::ReadAllText($constantsPath)

# App：解析 version: x.y.z+build（$ 在 .NET 正则中只匹配字符串结尾，故不限定行尾）
$appRegex = [regex]'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)'
$appMatch = $appRegex.Match($pubspecContent)
if (-not $appMatch.Success) {
    Write-Host "错误：无法从 pubspec.yaml 解析 version 字段（预期格式 x.y.z+build）" -ForegroundColor Red
    exit 1
}
$appName = "$($appMatch.Groups[1].Value).$($appMatch.Groups[2].Value).$($appMatch.Groups[3].Value)"
$currentBuild = [int]$appMatch.Groups[4].Value

# PC：解析 APP_VERSION = "x.y.z"
$pcRegex = [regex]'APP_VERSION\s*=\s*"(\d+\.\d+\.\d+)"'
$pcMatch = $pcRegex.Match($constantsContent)
if (-not $pcMatch.Success) {
    Write-Host "错误：无法从 constants.py 解析 APP_VERSION（预期格式 x.y.z）" -ForegroundColor Red
    exit 1
}
$pcName = $pcMatch.Groups[1].Value

Write-Host "当前版本: App v$appName +$currentBuild | PC $pcName" -ForegroundColor Yellow

# ============================================================
# 步骤 2：前置工具链检查（此步不修改任何文件）
# ============================================================
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到 flutter 命令，请先配置 Flutter 环境。" -ForegroundColor Red
    exit 1
}

# PyInstaller 探测：优先 pyinstaller 命令，回退 python -m PyInstaller
$pyInstallerOk = $false
if (Get-Command pyinstaller -ErrorAction SilentlyContinue) {
    $pyInstallerOk = $true
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python -m PyInstaller --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $pyInstallerOk = $true }
}
if (-not $pyInstallerOk) {
    Write-Host "错误：未找到 PyInstaller，请先安装（pip install pyinstaller 或在相应环境中配置）。" -ForegroundColor Red
    exit 1
}

Write-Host "工具链检查通过（flutter / PyInstaller）" -ForegroundColor Green
Write-Host ""

# ============================================================
# 步骤 3：输入并校验新版本名（x.y.z），App 构建号自动 +1
# ============================================================
$newName = $null
while ($true) {
    # 注意：不要使用 $input（PowerShell 自动变量），用独立变量名保存用户输入
    $versionInput = Read-Host "请输入新版本号 (格式 x.y.z，如 1.2.0)，输入 q 取消"

    if ($versionInput -eq "q" -or $versionInput -eq "quit" -or $versionInput -eq "Q") {
        Write-Host "已取消，未修改任何文件。" -ForegroundColor DarkYellow
        exit 0
    }

    if ($versionInput -notmatch '^\d+\.\d+\.\d+$') {
        Write-Host "格式非法：应为 x.y.z（数字.数字.数字），请重新输入。" -ForegroundColor Red
        continue
    }

    $newName = $versionInput

    # 版本名与任一当前版本相同，额外确认，避免误操作
    if ($newName -eq $appName -or $newName -eq $pcName) {
        $confirm = Read-Host "新版本名与当前版本相同($newName)，确认继续？(y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "已取消，未修改任何文件。" -ForegroundColor DarkYellow
            exit 0
        }
    }
    break
}

$newBuild = $currentBuild + 1
$newFullVersion = "${newName}+${newBuild}"
$apkFileName = "MusicSync-V$newName.apk"
$exeFileName = "MusicSync-V$newName.exe"

Write-Host ""
Write-Host "目标版本: App v$newName +$newBuild ($newFullVersion) | PC $newName" -ForegroundColor Yellow

# ============================================================
# 步骤 4：同步更新两端版本信息文件 (UTF-8 无 BOM)
# ============================================================
$changedFiles = @()

# 通用替换函数：命中则写回并记录，未命中则黄字警告
function Update-FileContent {
    param(
        [string]$Path,
        [string]$OldText,
        [string]$NewText,
        [string]$Label
    )
    $content = [System.IO.File]::ReadAllText($Path)
    $updated = $content.Replace($OldText, $NewText)
    if ($updated -eq $content) {
        Write-Host "警告：$Label 中未匹配到 '$OldText'，已跳过该文件" -ForegroundColor DarkYellow
    } else {
        [System.IO.File]::WriteAllText($Path, $updated, $utf8NoBom)
        $script:changedFiles += $Label
        Write-Host "已更新 $Label" -ForegroundColor Green
    }
}

# 4.1 App: pubspec.yaml
Update-FileContent -Path $pubspecPath -OldText "version: $appName+$currentBuild" -NewText "version: $newFullVersion" -Label "pubspec.yaml"

# 4.2 App: 关于页
Update-FileContent -Path $appSettingsPath -OldText "版本: $appName" -NewText "版本: $newName" -Label "settings_screen.dart"

# 4.3 PC: constants.py
Update-FileContent -Path $constantsPath -OldText "APP_VERSION = `"$pcName`"" -NewText "APP_VERSION = `"$newName`"" -Label "constants.py"

# 4.4 PC: 关于页
Update-FileContent -Path $pcSettingsPath -OldText "版本: $pcName" -NewText "版本: $newName" -Label "settings_page.py"

Write-Host ""

# ============================================================
# 步骤 5：依次构建 App 与 PC
# ============================================================
Write-Host "[1/2] 构建 Android APK ..." -ForegroundColor Yellow
Push-Location $appDir
try {
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误：flutter build 失败（退出码 $LASTEXITCODE）。版本文件已修改，请用 git diff 检查。" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $flutterApkPath)) {
        Write-Host "错误：未找到构建产物 $flutterApkPath" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host "[2/2] 构建 PC exe ..." -ForegroundColor Yellow
Push-Location $pcDir
try {
    pyinstaller build.spec --clean --noconfirm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "错误：pyinstaller 构建失败（退出码 $LASTEXITCODE）。版本文件已修改，请用 git diff 检查。" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $pcExePath)) {
        Write-Host "错误：未找到构建产物 $pcExePath" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

# ============================================================
# 步骤 6：归档到统一发布目录
# ============================================================
if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$targetApk = Join-Path $distDir $apkFileName
$targetExe = Join-Path $distDir $exeFileName
Copy-Item -LiteralPath $flutterApkPath -Destination $targetApk -Force
Copy-Item -LiteralPath $pcExePath -Destination $targetExe -Force

Write-Host ""
Write-Host "=== 发布完成 ===" -ForegroundColor Cyan
Write-Host "版本: App v$newName +$newBuild | PC $newName" -ForegroundColor Green
Write-Host "已更新文件: $($changedFiles -join ', ')" -ForegroundColor Green
Write-Host "APK: $targetApk" -ForegroundColor Green
Write-Host "EXE: $targetExe" -ForegroundColor Green