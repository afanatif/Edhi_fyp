import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/services/photo_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Selected photos are re-encoded within the Firestore size limit',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xffff0000),
      );
      final picture = recorder.endRecording();
      final original = await picture.toImage(1, 1);
      final png = await original.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      original.dispose();
      final encoded = await PhotoCodec.compress(png!.buffer.asUint8List());
      expect(encoded.length, lessThanOrEqualTo(PhotoCodec.maxStoredBytes));
      final codec = await ui.instantiateImageCodec(encoded);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 1);
      expect(image.height, 1);
      image.dispose();
      codec.dispose();
    },
  );
  test(
    'A detailed image is resized, preserving aspect ratio and producing valid PNG bytes',
    () async {
      const width = 900;
      const height = 600;
      final random = Random(42);
      final pixels = Uint8List(width * height * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = random.nextInt(256);
        pixels[i + 1] = random.nextInt(256);
        pixels[i + 2] = random.nextInt(256);
        pixels[i + 3] = 255;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final rawCodec = await descriptor.instantiateCodec();
      final original = (await rawCodec.getNextFrame()).image;
      final source = await original.toByteData(format: ui.ImageByteFormat.png);
      final result = await PhotoCodec.compress(source!.buffer.asUint8List());
      expect(result.length, lessThanOrEqualTo(PhotoCodec.maxStoredBytes));
      final codec = await ui.instantiateImageCodec(result);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, lessThan(width));
      expect(image.width / image.height, closeTo(width / height, 0.01));
      image.dispose();
      codec.dispose();
      original.dispose();
      rawCodec.dispose();
      descriptor.dispose();
      buffer.dispose();
    },
  );
}
