/// Minimal real audio fixtures for the tag-editor tests.
///
/// Both builders produce files `audio_metadata_reader` can genuinely parse
/// and write back (no mocking of the tag layer):
/// - MP3: a real ID3v2.3 tag (TIT2/TPE1/TALB) followed by one silent
///   MPEG-1 Layer III frame.
/// - FLAC: the `fLaC` marker + a complete STREAMINFO block (44.1 kHz,
///   stereo, 16-bit, 44100 samples).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Sync-safe (7-bit) big-endian integer, ID3 style.
Uint8List _syncSafe32(int value) => Uint8List(4)
  ..[0] = (value >> 21) & 0x7F
  ..[1] = (value >> 14) & 0x7F
  ..[2] = (value >> 7) & 0x7F
  ..[3] = value & 0x7F;

Uint8List _ascii(String text) => Uint8List.fromList(latin1.encode(text));

/// One ID3v2.3 text frame (ISO-8859-1 encoding byte 0x00).
Uint8List _id3TextFrame(String id, String value) {
  final Uint8List body = Uint8List.fromList(<int>[
    0x00, // encoding: ISO-8859-1
    ..._ascii(value),
  ]);
  final BytesBuilder builder = BytesBuilder();
  builder.add(_ascii(id));
  builder.add(Uint8List(4)..buffer.asByteData().setUint32(0, body.length));
  builder.add(Uint8List(2)); // flags
  builder.add(body);
  return builder.toBytes();
}

/// Builds a minimal MP3: ID3v2.3 header with the given text frames plus a
/// single silent MPEG-1 Layer III frame (128 kbps / 44.1 kHz).
Uint8List minimalMp3Bytes({required Map<String, String> textFrames}) {
  final BytesBuilder tagBody = BytesBuilder();
  textFrames.forEach((String id, String value) {
    tagBody.add(_id3TextFrame(id, value));
  });
  final Uint8List body = tagBody.toBytes();

  final BytesBuilder file = BytesBuilder();
  file.add(_ascii('ID3'));
  file.add(<int>[0x03, 0x00, 0x00]); // v2.3, no flags
  file.add(_syncSafe32(body.length));
  file.add(body);

  // One silent MPEG-1 Layer III frame: 0xFFFB9000 + 413 zero bytes
  // (frame length 417 for 128 kbps @44.1 kHz, no padding).
  file.add(Uint8List.fromList(<int>[0xFF, 0xFB, 0x90, 0x00]));
  file.add(Uint8List(413));
  return file.toBytes();
}

/// Builds a minimal FLAC file (fLaC + STREAMINFO only).
Uint8List minimalFlacBytes() {
  final BytesBuilder streamInfo = BytesBuilder();
  final ByteData data = ByteData(34);
  data.setUint16(0, 4096); // min blocksize
  data.setUint16(2, 4096); // max blocksize
  // min/max framesize (3 bytes each) stay zero.
  // Packed: 20-bit sample rate 44100, 3-bit channels-1 = 1, 5-bit
  // bits-per-sample-1 = 15, 36-bit total samples = 44100.
  data.setUint8(10, 0x0A);
  data.setUint8(11, 0xC4);
  data.setUint8(12, 0x42);
  data.setUint8(13, 0xF0);
  data.setUint32(14, 44100); // total samples (low 32 of 36 bits)
  streamInfo.add(data.buffer.asUint8List());

  final BytesBuilder file = BytesBuilder();
  file.add(_ascii('fLaC'));
  file.add(<int>[
    0x80, // last-metadata-block flag | block type 0 (STREAMINFO)
    0x00,
    0x00,
    0x22, // 34-byte body
  ]);
  file.add(streamInfo.toBytes());
  return file.toBytes();
}

/// Writes [bytes] into a uniquely-named temp file under the system temp
/// dir; returns its path.
Future<String> writeTempAudio(
  String fileName,
  Uint8List bytes,
) async {
  final Directory dir = await Directory.systemTemp.createTemp('wavely-tags');
  final String path = '${dir.path}/$fileName';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
