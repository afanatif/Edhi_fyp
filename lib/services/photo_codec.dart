import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/selected_photo.dart';

class PhotoCodec {
  static const maxStoredBytes = 256 * 1024;

  // A bounded preview fits comfortably inside Firestore's document limit.
  // Re-encoding also strips metadata from the selected camera/gallery file.
  static Future<Uint8List> compress(Uint8List bytes) async {
    SelectedPhoto.fromBytes(bytes);
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? original;
    try {
      original = (await codec.getNextFrame()).image;
      for (var edge = 1024; edge >= 64; edge = (edge * 0.75).floor()) {
        final scale = math.min(
          1.0,
          edge / math.max(original.width, original.height),
        );
        final width = math.max(1, (original.width * scale).round());
        final height = math.max(1, (original.height * scale).round());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          original,
          ui.Rect.fromLTWH(
            0,
            0,
            original.width.toDouble(),
            original.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        final resized = await picture.toImage(width, height);
        picture.dispose();
        try {
          final encoded = await resized.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (encoded != null && encoded.lengthInBytes <= maxStoredBytes) {
            return encoded.buffer.asUint8List(
              encoded.offsetInBytes,
              encoded.lengthInBytes,
            );
          }
        } finally {
          resized.dispose();
        }
      }
      throw StateError('Could not prepare this photo. Choose another image.');
    } finally {
      original?.dispose();
      codec.dispose();
    }
  }
}
