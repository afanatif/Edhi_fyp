import 'dart:typed_data';

class SelectedPhoto {
  static const maxBytes = 5 * 1024 * 1024;
  final Uint8List bytes;
  final String contentType;

  const SelectedPhoto._(this.bytes, this.contentType);

  factory SelectedPhoto.fromBytes(Uint8List bytes) {
    final String type;
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      type = 'image/jpeg';
    } else if (bytes.length >= 8 &&
        String.fromCharCodes(bytes.take(8)) == '\x89PNG\r\n\x1a\n') {
      type = 'image/png';
    } else if (bytes.length > 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      type = 'image/webp';
    } else {
      type = '';
    }
    if (type.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Choose a JPEG, PNG or WebP photo up to 5 MB.');
    }
    return SelectedPhoto._(bytes, type);
  }
}
