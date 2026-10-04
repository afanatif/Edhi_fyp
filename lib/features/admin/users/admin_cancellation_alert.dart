import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/emergency_usage.dart';
import '../../../services/firestore_service.dart';

class AdminCancellationAlert extends StatefulWidget {
  final VoidCallback onReview;
  const AdminCancellationAlert({super.key, required this.onReview});
  @override
  State<AdminCancellationAlert> createState() => _AdminCancellationAlertState();
}

class _AdminCancellationAlertState extends State<AdminCancellationAlert> {
  late final Stream<Map<String, EmergencyUsage>> _usage;
  @override
  void initState() {
    super.initState();
    _usage = context.read<FirestoreService>().watchAllEmergencyUsage();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<Map<String, EmergencyUsage>>(
    stream: _usage,
    builder: (context, snapshot) {
      final flagged = (snapshot.data ?? {}).values
          .where((u) => u.cancellationCount >= 3 || u.adminBanned)
          .toList();
      if (flagged.isEmpty) return const SizedBox.shrink();
      final restricted = flagged
          .where((u) => u.isBanned(DateTime.now()))
          .length;
      return Card(
        color: Colors.orange.shade50,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.flag, color: Colors.orange),
              Text(
                '${flagged.length} accounts flagged or banned · $restricted currently restricted',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextButton.icon(
                onPressed: widget.onReview,
                icon: const Icon(Icons.manage_accounts),
                label: const Text('Review / unban'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
