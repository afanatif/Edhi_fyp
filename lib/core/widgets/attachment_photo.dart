import 'package:flutter/material.dart';
import 'stored_photo.dart';

class AttachmentPhoto extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  const AttachmentPhoto({
    super.key,
    required this.url,
    this.width = 180,
    this.height = 120,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close photo',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: StoredPhoto(url: url, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: StoredPhoto(url: url, height: height, width: width, fit: fit),
        ),
      ),
    );
  }
}
