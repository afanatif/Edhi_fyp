import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/selected_photo.dart';

class PhotoPickerField extends StatefulWidget {
  final SelectedPhoto? value;
  final ValueChanged<SelectedPhoto?> onChanged;
  final String label;
  final bool enabled;

  const PhotoPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Photo (optional)',
    this.enabled = true,
  });

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  final _picker = ImagePicker();
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _recoverPhoto();
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.files?.isNotEmpty == true) {
        await _usePhoto(response.files!.first);
      }
    } catch (_) {}
  }

  Future<void> _usePhoto(XFile file) async {
    if (await file.length() > SelectedPhoto.maxBytes) {
      throw ArgumentError('Choose a JPEG, PNG or WebP photo up to 5 MB.');
    }
    final photo = SelectedPhoto.fromBytes(await file.readAsBytes());
    if (!mounted || !widget.enabled) return;
    widget.onChanged(photo);
    setState(() => _error = null);
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking || !widget.enabled) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file != null) await _usePhoto(file);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ArgumentError
              ? error.message.toString()
              : 'Could not open the camera or photos. Check permissions and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        if (widget.value != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              widget.value!.bytes,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 80,
                child: Center(child: Text('Photo preview unavailable')),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? () => _pick(ImageSource.gallery) : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(widget.value == null ? 'Add photo' : 'Change photo'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => _pick(ImageSource.camera) : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Camera'),
            ),
            if (widget.value != null)
              TextButton(
                onPressed: enabled
                    ? () {
                        widget.onChanged(null);
                        setState(() => _error = null);
                      }
                    : null,
                child: const Text('Remove'),
              ),
            if (_picking)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const Text(
          'JPEG, PNG or WebP • Maximum 5 MB',
          style: TextStyle(fontSize: 12),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
