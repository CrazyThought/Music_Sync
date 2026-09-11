# MusicSync proto 代码生成脚本
#
# 依据 proto/musicsync.proto 生成两端 gRPC 代码：
#   - PC 端（Python）：music_sync_pc/generated/musicsync_pb2.py + musicsync_pb2_grpc.py
#   - 手机端（Dart）  ：music_sync_app/lib/generated/musicsync.pb.dart + musicsync.pbgrpc.dart 等
#
# 前置依赖：
#   - Python 端：pip install grpcio-tools（版本需与 grpcio 一致）
#   - Dart 端  ：dart pub global activate protoc_plugin（提供 protoc-gen-dart）
#
# 用法：在项目根目录执行
#   powershell -ExecutionPolicy Bypass -File scripts/generate_proto.ps1

$ErrorActionPreference = "Stop"

# 切换到项目根目录（脚本所在目录的上一级）
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $protoFile = "proto/musicsync.proto"
    if (-not (Test-Path $protoFile)) {
        throw "未找到 proto 文件: $protoFile"
    }

    $pyOut = "music_sync_pc/generated"
    $dartOut = "music_sync_app/lib/generated"
    New-Item -ItemType Directory -Force -Path $pyOut | Out-Null
    New-Item -ItemType Directory -Force -Path $dartOut | Out-Null

    # 1) 生成 Python 代码
    Write-Host "[1/3] 生成 Python gRPC 代码 ..."
    python -m grpc_tools.protoc `
        -I proto `
        --python_out=$pyOut `
        --grpc_python_out=$pyOut `
        $protoFile

    # 生成代码默认使用绝对导入，改为包内相对导入以适配 generated 包结构。
    # 该文件每次生成都会被覆盖，故此处自动修正，避免手工维护。
    Write-Host "[2/3] 修正 Python 生成代码的相对导入 ..."
    $grpcPy = Join-Path $pyOut "musicsync_pb2_grpc.py"
    $content = Get-Content -Path $grpcPy -Raw -Encoding UTF8
    $content = $content -replace "(?m)^import musicsync_pb2 as musicsync__pb2$", "from . import musicsync_pb2 as musicsync__pb2"
    Set-Content -Path $grpcPy -Value $content -Encoding UTF8 -NoNewline

    # 2) 生成 Dart 代码
    Write-Host "[3/3] 生成 Dart gRPC 代码 ..."
    $dartPlugin = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\protoc-gen-dart.bat"
    if (-not (Test-Path $dartPlugin)) {
        throw "未找到 protoc-gen-dart，请先执行: dart pub global activate protoc_plugin"
    }
    python -m grpc_tools.protoc `
        -I proto `
        --plugin=protoc-gen-dart="$dartPlugin" `
        --dart_out=grpc:$dartOut `
        $protoFile

    Write-Host "代码生成完成。"
}
finally {
    Pop-Location
}
