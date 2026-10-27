#!/usr/bin/env python3
"""Generates the Stage 1.1 audio test fixtures under test/fixtures/audio/.

Ten byte-level valid audio files (6 MP3 + 4 FLAC), each carrying:
- real metadata tags (title / artist / album / genre / track no),
- embedded synced lyrics (ID3v2.3 USLT on MP3, Vorbis `LYRICS=` on FLAC),
- an embedded 24x24 PNG front cover (ID3v2.3 APIC / FLAC PICTURE block).

Only the Python standard library is used. The generated files are consumed
by `flutter test` (library scan / metadata / lyrics tests) — they are small
(tag-bearing) but NOT listenable music: audio payloads are silent filler
frames with structurally valid headers.

Run:  python3 tools/gen_fixtures.py   (idempotent — rewrites in place)
"""

from __future__ import annotations

import os
import struct
import zlib

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "test", "fixtures", "audio",
)

# --------------------------------------------------------------------------- #
# Minimal PNG encoder (solid colour 24x24)                                     #
# --------------------------------------------------------------------------- #


def tiny_png(rgb: tuple[int, int, int] = (128, 90, 200), size: int = 24) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(rgb) * size  # filter byte 0 + one RGB line
    idat = zlib.compress(row * size, 9)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


COVER = tiny_png()

SAMPLE_LRC = (
    "[ar:{artist}]\n[ti:{title}]\n[offset:0]\n"
    "[00:01.00]First line of {title}\n"
    "[00:04.50]Second line of {title}\n"
    "[00:09.25]Third line of {title}\n"
)

# --------------------------------------------------------------------------- #
# ID3v2.3 (MP3)                                                                #
# --------------------------------------------------------------------------- #


def _id3_frame(frame_id: str, payload: bytes) -> bytes:
    # ID3v2.3 uses plain big-endian uint32 sizes (NOT synchsafe).
    return (frame_id.encode("ascii") + struct.pack(">I", len(payload))
            + b"\x00\x00" + payload)


def _text_frame(frame_id: str, text: str) -> bytes:
    return _id3_frame(frame_id, b"\x00" + text.encode("latin-1"))


def _uslt_frame(lrc: str) -> bytes:
    body = (b"\x00"            # encoding: ISO-8859-1 (lyrics stay ASCII)
            + b"eng"           # 3-letter language
            + b"\x00"          # empty content descriptor
            + lrc.encode("ascii"))
    return _id3_frame("USLT", body)


def _apic_frame(png: bytes) -> bytes:
    body = (b"\x00"                      # encoding
            + b"image/png\x00"           # MIME
            + b"\x03"                    # picture type: front cover
            + b"\x00"                    # empty description
            + png)
    return _id3_frame("APIC", body)


def id3v2_tag(title: str, artist: str, album: str, genre: str,
              track_no: int, lrc: str) -> bytes:
    frames = b"".join([
        _text_frame("TIT2", title),
        _text_frame("TPE1", artist),
        _text_frame("TALB", album),
        _text_frame("TCON", genre),
        _text_frame("TRCK", str(track_no)),
        _text_frame("TLAN", "eng"),
        _uslt_frame(lrc),
        _apic_frame(COVER),
    ])
    # v2.3 tag header size is synchsafe (7 bits per byte).
    size = len(frames)
    syncsafe = bytes(((size >> 21) & 0x7F, (size >> 14) & 0x7F,
                      (size >> 7) & 0x7F, size & 0x7F))
    return b"ID3\x03\x00\x00" + syncsafe + frames


def mp3_audio(seconds: float = 1.0) -> bytes:
    """Silent-but-valid MPEG-1 Layer III frames (128 kbps, 44.1 kHz, no CRC)."""
    # header: 0xFF 0xFB 0x90 0x00 -> frame length = 144*128000/44100 = 417
    frame_len = 417
    frame = b"\xff\xfb\x90\x00" + b"\x00" * (frame_len - 4)
    # 1152 samples/frame @44100 Hz = ~26.1 ms -> ceil for the requested span
    count = max(1, int(seconds * 44100 / 1152) + 1)
    return frame * count


def build_mp3(title: str, artist: str, album: str, genre: str,
              track_no: int) -> bytes:
    lrc = SAMPLE_LRC.format(artist=artist, title=title)
    return id3v2_tag(title, artist, album, genre, track_no, lrc) + mp3_audio()


# --------------------------------------------------------------------------- #
# FLAC                                                                         #
# --------------------------------------------------------------------------- #


def _flac_streaminfo(total_samples: int, sample_rate: int = 44100) -> bytes:
    min_block, max_block = 4096, 4096
    min_frame, max_frame = 100, 8000
    # 8-byte packed field: sample_rate(20) | channels-1(3) |
    # bits_per_sample-1(5) | total_samples(36). 8 bytes total, NOT 7 —
    # this was the Stage 1.1 bit-packing bug (see worklog).
    packed = (sample_rate << 44) | ((2 - 1) << 41) | ((16 - 1) << 36) | total_samples
    packed_bytes = packed.to_bytes(8, "big")
    md5 = b"\x00" * 16  # no audio checksum for synthetic payloads
    return (struct.pack(">HH", min_block, max_block)
            + min_frame.to_bytes(3, "big") + max_frame.to_bytes(3, "big")
            + packed_bytes + md5)


def _vorbis_comment_block(comments: dict[str, str]) -> bytes:
    vendor = b"WavelyFixtureGen/1.0"
    out = struct.pack("<I", len(vendor)) + vendor
    out += struct.pack("<I", len(comments))
    for key, value in comments.items():
        entry = "{}={}".format(key, value).encode("utf-8")
        out += struct.pack("<I", len(entry)) + entry
    return out


def _flac_picture_block(png: bytes) -> bytes:
    mime = b"image/png"
    return (struct.pack(">I", 3)                    # front cover
            + struct.pack(">I", len(mime)) + mime
            + struct.pack(">I", 0)                  # empty description
            + struct.pack(">IIII", 24, 24, 24, 0)   # w, h, depth, colors
            + struct.pack(">I", len(png)) + png)


def build_flac(title: str, artist: str, album: str, genre: str,
               total_samples: int = 220500) -> bytes:
    lrc = SAMPLE_LRC.format(artist=artist, title=title)
    comments = {
        "TITLE": title, "ARTIST": artist, "ALBUM": album,
        "GENRE": genre, "LANGUAGE": "eng", "LYRICS": lrc,
    }
    # Metadata block headers are 1 byte (last-flag | type) + 3-byte BE length.
    def block(block_type: int, payload: bytes, last: bool = False) -> bytes:
        return (bytes(((0x80 if last else 0) | block_type,))
                + len(payload).to_bytes(3, "big") + payload)

    streaminfo = block(0, _flac_streaminfo(total_samples))
    vorbis = block(4, _vorbis_comment_block(comments))
    picture = block(6, _flac_picture_block(COVER), last=True)
    return b"fLaC" + streaminfo + vorbis + picture


# --------------------------------------------------------------------------- #
# Fixture plan (10 files)                                                      #
# --------------------------------------------------------------------------- #

MP3_TRACKS = [
    ("01_neon_rivers.mp3", "Neon Rivers", "Aria Wave", "Chromatic", "Electronic"),
    ("02_glass_harbour.mp3", "Glass Harbour", "Aria Wave", "Chromatic", "Electronic"),
    ("03_midnight_transit.mp3", "Midnight Transit", "Kodo Line", "Night Drive", "Ambient"),
    ("04_copper_skies.mp3", "Copper Skies", "Kodo Line", "Night Drive", "Ambient"),
    ("05_violet_static.mp3", "Violet Static", "Mirren Vale", "Hush", "Indie"),
    ("06_paper_lanterns.mp3", "Paper Lanterns", "Mirren Vale", "Hush", "Indie"),
]

FLAC_TRACKS = [
    ("07_paper_boats.flac", "Paper Boats", "Marina Fold", "Tidelines", "Indie"),
    ("08_tideline.flac", "Tideline", "Marina Fold", "Tidelines", "Indie"),
    ("09_salt_and_cedar.flac", "Salt and Cedar", "Jonah Reave", "Northlight", "Folk"),
    ("10_northbound.flac", "Northbound", "Jonah Reave", "Northlight", "Folk"),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    written: list[tuple[str, int]] = []
    for i, (name, title, artist, album, genre) in enumerate(MP3_TRACKS, 1):
        data = build_mp3(title, artist, album, genre, i)
        with open(os.path.join(OUT_DIR, name), "wb") as fh:
            fh.write(data)
        written.append((name, len(data)))
    for i, (name, title, artist, album, genre) in enumerate(FLAC_TRACKS, 7):
        data = build_flac(title, artist, album, genre)
        with open(os.path.join(OUT_DIR, name), "wb") as fh:
            fh.write(data)
        written.append((name, len(data)))
    for name, size in written:
        print(f"wrote {name} ({size} bytes)")
    print(f"total: {len(written)} fixtures in {OUT_DIR}")


if __name__ == "__main__":
    main()
