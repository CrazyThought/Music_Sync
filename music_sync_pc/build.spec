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
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=[
        'tkinter.test',
        'matplotlib',
        'numpy',
        'pandas',
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