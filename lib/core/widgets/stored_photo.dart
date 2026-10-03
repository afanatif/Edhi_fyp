import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StoredPhoto extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  const StoredPhoto({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<StoredPhoto> createState() => _StoredPhotoState();
}

class _StoredPhotoState extends State<StoredPhoto> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StoredPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) _load();
  }

  void _load() {
    _bytes = widget.url.startsWith('firestore-photo:') ? _readBytes() : null;
  }

  Future<Uint8List> _readBytes() async {
    final id = widget.url.substring('firestore-photo:'.length);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw StateError('Invalid photo reference.');
    }
    final doc = await FirebaseFirestore.instance
        .collection('photo_attachments')
        .doc(id)
        .get();
    final bytes = doc.data()?['image'];
    if (bytes is! Blob) throw StateError('Photo unavailable.');
    return bytes.bytes;
  }

  Widget _unavailable() => SizedBox(
    width: widget.width,
    height: widget.height ?? 100,
    child: const Center(child: Text('Photo unavailable')),
  );

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _unavailable(),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _unavailable();
        if (!snapshot.hasData) {
          return SizedBox(
            width: widget.width,
            height: widget.height ?? 120,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, _, _) => _unavailable(),
        );
      },
    );
  }
}
