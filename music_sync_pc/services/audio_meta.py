"""音频元数据提取 —— 基于 mutagen 的 ID3/Vorbis/FLAC 标签解析。"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from mutagen import File as MutagenFile
from mutagen.mp3 import MP3
from mutagen.flac import FLAC
from mutagen.oggvorbis import OggVorbis
from mutagen.mp4 import MP4

logger = logging.getLogger("musicsync")


def extract_audio_meta(file_path: Path) -> dict[str, Any]:
    try:
        audio = MutagenFile(str(file_path))
        if audio is None:
            return _build_empty_meta(file_path)

        if isinstance(audio, MP3):
            return _from_mp3(audio, file_path)
        elif isinstance(audio, FLAC):
            return _from_flac(audio, file_path)
        elif isinstance(audio, OggVorbis):
            return _from_vorbis(audio, file_path)
        elif isinstance(audio, MP4):
            return _from_mp4(audio, file_path)
        else:
            return _from_generic(audio, file_path)
    except Exception:
        logger.warning("无法提取元数据: %s", file_path)
        return _build_empty_meta(file_path)


def _from_mp3(audio: MP3, file_path: Path) -> dict[str, Any]:
    tags = audio.tags or {}
    return {
        "title": _safe_tag(tags, "TIT2", file_path.stem),
        "artist": _safe_tag(tags, "TPE1", ""),
        "album": _safe_tag(tags, "TALB", None),
        "duration_ms": int(audio.info.length * 1000) if audio.info else 0,
        "bitrate_kbps": audio.info.bitrate // 1000 if audio.info and hasattr(audio.info, "bitrate") else None,
    }


def _from_flac(audio: FLAC, file_path: Path) -> dict[str, Any]:
    tags = audio.tags or {}
    return {
        "title": _safe_vorbis(tags, "title", file_path.stem),
        "artist": _safe_vorbis(tags, "artist", ""),
        "album": _safe_vorbis(tags, "album", None),
        "duration_ms": int(audio.info.length * 1000) if audio.info else 0,
        "bitrate_kbps": None,
    }


def _from_vorbis(audio: OggVorbis, file_path: Path) -> dict[str, Any]:
    tags = audio.tags or {}
    return {
        "title": _safe_vorbis(tags, "title", file_path.stem),
        "artist": _safe_vorbis(tags, "artist", ""),
        "album": _safe_vorbis(tags, "album", None),
        "duration_ms": int(audio.info.length * 1000) if audio.info else 0,
        "bitrate_kbps": audio.info.bitrate // 1000 if audio.info and hasattr(audio.info, "bitrate") else None,
    }


def _from_mp4(audio: MP4, file_path: Path) -> dict[str, Any]:
    tags = audio.tags or {}
    return {
        "title": _safe_mp4(tags, "\xa9nam", file_path.stem),
        "artist": _safe_mp4(tags, "\xa9ART", ""),
        "album": _safe_mp4(tags, "\xa9alb", None),
        "duration_ms": int(audio.info.length * 1000) if audio.info else 0,
        "bitrate_kbps": audio.info.bitrate // 1000 if audio.info and hasattr(audio.info, "bitrate") else None,
    }


def _from_generic(audio: Any, file_path: Path) -> dict[str, Any]:
    duration = 0
    if audio.info and hasattr(audio.info, "length"):
        duration = int(audio.info.length * 1000)
    return _build_empty_meta(file_path, duration)


def _safe_tag(tags: dict, key: str, default: Any) -> Any:
    try:
        return str(tags.get(key, default))
    except Exception:
        return default


def _safe_vorbis(tags: dict, key: str, default: Any) -> Any:
    try:
        values = tags.get(key, [])
        return str(values[0]) if values else default
    except Exception:
        return default


def _safe_mp4(tags: dict, key: str, default: Any) -> Any:
    try:
        values = tags.get(key, [])
        return str(values[0]) if values else default
    except Exception:
        return default


def _build_empty_meta(file_path: Path, duration_ms: int = 0) -> dict[str, Any]:
    return {
        "title": file_path.stem,
        "artist": "",
        "album": None,
        "duration_ms": duration_ms,
        "bitrate_kbps": None,
    }