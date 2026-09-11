# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[
        'mutagen.mp3',
        'mutagen.flac',
        'mutagen.oggvorbis',
        'mutagen.mp4',
        'mutagen.asf',
        'customtkinter',
        'PIL',
        # grpcio 的 Cython 扩展为动态加载，PyInstaller 静态分析无法完全覆盖，
        # 显式声明以免打包后运行时报 ModuleNotFoundError。
        'grpc',
        'grpc._cython.cygrpc',
        'google.protobuf',
        # proto 生成代码位于 generated 包内，显式声明保证被收集
        'generated.musicsync_pb2',
        'generated.musicsync_pb2_grpc',
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=[
        'tkinter.test',
        'matplotlib',
        'numpy',
        'pandas',
        # grpc_tools 仅用于开发期生成 proto 代码，运行时不需要，排除以减小体积
        'grpc_tools',
    ],
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='MusicSync',
    icon=None,
    console=False,
    onefile=True,
)