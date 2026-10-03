import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String relationship;
  final String phone;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phone,
  });
}

class EmergencyContactsSheet extends StatefulWidget {
  const EmergencyContactsSheet({super.key});

  @override
  State<EmergencyContactsSheet> createState() => _EmergencyContactsSheetState();
}

class _EmergencyContactsSheetState extends State<EmergencyContactsSheet> {
  // Pre-seeded with user's initial contacts matching SDD Figure 11
  final List<EmergencyContact> _contacts = [
    const EmergencyContact(
      id: 'c1',
      name: 'USMAN WAQAR',
      relationship: 'Brother',
      phone: '03122435235',
    ),
  ];

  void _showAddContactDialog() {
    if (_contacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 emergency contacts allowed.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String relationship = 'Parent';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Add Emergency Contact',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                controller: nameController,
                label: 'Contact Full Name',
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: phoneController,
                label: 'Phone Number',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: relationship,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                          'Parent',
                          'Spouse',
                          'Brother',
                          'Sister',
                          'Friend',
                          'Guardian',
                          'Other',
                        ]
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                onChanged: (val) => setDialogState(() => relationship = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergencyRed,
              ),
              onPressed: () {
                if (nameController.text.trim().isEmpty ||
                    phoneController.text.trim().isEmpty) {
                  return;
                }
                setState(() {
                  _contacts.add(
                    EmergencyContact(
                      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
                      name: nameController.text.trim().toUpperCase(),
                      relationship: relationship,
                      phone: phoneController.text.trim(),
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save Contact'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_contacts.length} of 5 contacts added',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          if (_contacts.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No emergency contacts saved yet.'),
            )
          else
            ...List.generate(_contacts.length, (index) {
              final c = _contacts[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.emergencyRed.withValues(
                        alpha: 0.12,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c.relationship} • ${c.phone}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _contacts.removeAt(index)),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 16),

          CustomButton(
            text: '+ Add Contact',
            color: AppColors.reliefGreenMedium,
            onPressed: _showAddContactDialog,
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: AppColors.emergencyRed),
            ),
            icon: const Icon(Icons.sos, color: AppColors.emergencyRed),
            label: const Text(
              'Alert All Contacts Now (SMS Broadcast)',
              style: TextStyle(
                color: AppColors.emergencyRed,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'SOS message with your GPS coordinates sent to ${_contacts.length} contact(s).',
                  ),
                  backgroundColor: AppColors.emergencyRed,
                ),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
