import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/app_user.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/firestore_service.dart';

Future<void> showAdminUserDialog(BuildContext context, {AppUser? user}) async {
  final service = context.read<FirestoreService>();
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UserDialog(service: service, user: user),
  );
  if (result != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
  }
}

class _UserDialog extends StatefulWidget {
  final FirestoreService service;
  final AppUser? user;
  const _UserDialog({required this.service, this.user});
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _cnic, _phone, _email, _address;
  final _password = TextEditingController();
  String _role = AppRoles.user;
  String? _error;
  bool _busy = false, _showPassword = false;
  bool get adding => widget.user == null;
  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user?.name);
    _cnic = TextEditingController(text: user?.cnic);
    _phone = TextEditingController(text: user?.phone);
    _email = TextEditingController(text: user?.email);
    _address = TextEditingController(text: user?.address);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _cnic,
      _phone,
      _email,
      _address,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (adding) {
        await widget.service.createManagedUser(
          name: _name.text,
          cnic: _cnic.text,
          phone: _phone.text,
          email: _email.text,
          address: _address.text,
          password: _password.text,
          role: _role,
        );
      } else {
        await widget.service.updateUserProfile(
          widget.user!.id,
          name: _name.text,
          address: _address.text,
        );
      }
      if (mounted) {
        Navigator.pop(
          context,
          adding
              ? widget.service.isLiveFirebase
                    ? 'Account created. The user can sign in with CNIC or phone and the password you entered.'
                    : 'Demo profile added.'
              : 'Profile updated.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst(
            RegExp(r'^(Bad state: |Invalid argument\(s\): )'),
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(adding ? 'Add user' : 'Edit user'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (adding) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: AppRoles.user,
                        child: Text('Citizen'),
                      ),
                      DropdownMenuItem(
                        value: AppRoles.employee,
                        child: Text('Driver'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _role = value!),
                  ),
                  const SizedBox(height: 12),
                ],
                _field(
                  _name,
                  'Full name',
                  validate: (v) => (v ?? '').trim().length < 2
                      ? 'Enter the full name.'
                      : null,
                ),
                _field(
                  _cnic,
                  'CNIC',
                  readOnly: !adding,
                  keyboard: TextInputType.number,
                  validate: (v) => adding && !AppUser.isValidCnic(v ?? '')
                      ? 'Enter a valid 13-digit CNIC.'
                      : null,
                ),
                _field(
                  _phone,
                  'Phone number',
                  readOnly: !adding,
                  keyboard: TextInputType.phone,
                  validate: (v) => adding && !AppUser.isValidPhone(v ?? '')
                      ? 'Enter a Pakistani mobile number.'
                      : null,
                ),
                if (adding)
                  _field(
                    _email,
                    'Contact email (optional)',
                    keyboard: TextInputType.emailAddress,
                  ),
                _field(_address, 'Station / address'),
                if (adding) ...[
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Initial password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Show password',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) => (value ?? '').length < 8
                        ? 'Use at least 8 characters.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Share the initial password privately with the user. Driver accounts can be linked to an ambulance in Fleet.',
                    style: TextStyle(fontSize: 12),
                  ),
                ] else
                  const Text(
                    'Login phone and CNIC are managed with account identity.',
                    style: TextStyle(fontSize: 12),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : adding
                ? 'Create account'
                : 'Save changes',
          ),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool readOnly = false,
    TextInputType? keyboard,
    String? Function(String?)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      readOnly: readOnly,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validate,
    ),
  );
}

Future<void> showAdminDeleteUserDialog(
  BuildContext context,
  AppUser user,
) async {
  final service = context.read<FirestoreService>();
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeleteDialog(service: service, user: user),
  );
  if (deleted == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${user.name} from the app.')),
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  final FirestoreService service;
  final AppUser user;
  const _DeleteDialog({required this.service, required this.user});
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Delete ${widget.user.name}?'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Removes the app profile, login aliases and ambulance link. Historical reports remain. The Firebase Authentication record remains in the project console.',
              ),
              const SizedBox(height: 12),
              Text('Type DELETE to remove ${widget.user.name}.'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Confirmation',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _busy || _confirm.text.trim() != 'DELETE'
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await widget.service.deleteManagedUser(widget.user.id);
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (error) {
                    if (mounted) setState(() => _error = '$error');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? 'Deleting…' : 'Delete user'),
        ),
      ],
    ),
  );
}
