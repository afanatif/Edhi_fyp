import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../models/selected_photo.dart';
import '../../../models/app_user.dart';
import '../../../models/missing_person_report.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';

class MissingPersonForm extends StatefulWidget {
  const MissingPersonForm({super.key});
  @override
  State<MissingPersonForm> createState() => _MissingPersonFormState();
}

class _MissingPersonFormState extends State<MissingPersonForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  String _gender = 'Male';
  DateTime? _lastSeen;
  SelectedPhoto? _photo;
  String? _uploadedUrl;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _contact.text = user?.name ?? '';
    _phone.text = user?.phone ?? '';
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _lastSeen ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_lastSeen ?? now),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (selected.isAfter(DateTime.now())) {
        _error = 'Last seen time cannot be in the future.';
      } else {
        _lastSeen = selected;
        _error = null;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null || _lastSeen == null) {
      setState(
        () => _error = 'Sign in and select the last seen date and time.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = context.read<FirestoreService>();
      if (_photo != null) {
        _uploadedUrl ??= await service.uploadMissingPersonPhoto(
          _photo!.bytes,
          _photo!.contentType,
        );
      }
      final id = await service.submitMissingPersonReport(
        MissingPersonReport(
          reportId: '',
          userId: user.id,
          personName: _name.text.trim(),
          age: int.parse(_age.text),
          gender: _gender,
          lastSeenLocation: _location.text.trim(),
          lastSeenAt: _lastSeen,
          description: _description.text.trim(),
          contactName: _contact.text.trim(),
          contactPhone: AppUser.normalizePhone(_phone.text),
          reportedAt: DateTime.now(),
          photoUrl: _uploadedUrl ?? '',
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not publish. Check your connection and retry. Your form is preserved.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _age,
      _location,
      _description,
      _contact,
      _phone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    int lines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboard,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ?? (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Report missing person',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PhotoPickerField(
                  value: _photo,
                  enabled: !_busy,
                  label: 'Missing person photo (optional)',
                  onChanged: (photo) => setState(() {
                    _photo = photo;
                    _uploadedUrl = null;
                  }),
                ),
                const SizedBox(height: 16),
                _field(_name, 'Full name'),
                _field(
                  _age,
                  'Age in years',
                  keyboard: TextInputType.number,
                  validator: (v) {
                    final age = int.tryParse(v ?? '');
                    return age == null || age < 0 || age > 130
                        ? 'Enter an age between 0 and 130'
                        : null;
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: ['Male', 'Female', 'Not specified']
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: _busy ? null : (g) => setState(() => _gender = g!),
                ),
                const SizedBox(height: 14),
                _field(_location, 'Last seen location and city'),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    _lastSeen == null
                        ? 'Select last seen date and time'
                        : formatLastSeen(context, _lastSeen!),
                  ),
                ),
                const SizedBox(height: 14),
                _field(
                  _description,
                  'Clothing / identifying details',
                  lines: 3,
                ),
                _field(_contact, 'Reporter name'),
                _field(
                  _phone,
                  'Contact mobile number',
                  keyboard: TextInputType.phone,
                  validator: (v) => AppUser.isValidPhone(v ?? '')
                      ? null
                      : 'Enter a valid Pakistani mobile number',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish),
                  label: Text(_busy ? 'Publishing…' : 'Publish report'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatLastSeen(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatMediumDate(local)} • ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
