import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/app_user.dart';
import '../../../models/emergency_usage.dart';
import '../../../services/firestore_service.dart';

class CancellationReviewPanel extends StatefulWidget {
  final List<AppUser> users;
  const CancellationReviewPanel({super.key, required this.users});
  @override
  State<CancellationReviewPanel> createState() =>
      _CancellationReviewPanelState();
}

class _CancellationReviewPanelState extends State<CancellationReviewPanel> {
  final Set<String> _busy = {};
  late final Stream<Map<String, EmergencyUsage>> _stream;
  @override
  void initState() {
    super.initState();
    _stream = context.read<FirestoreService>().watchAllEmergencyUsage();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<Map<String, EmergencyUsage>>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text('Cancellation review unavailable: ${snapshot.error}');
      }
      final flagged = (snapshot.data ?? {}).entries
          .where(
            (entry) =>
                entry.value.cancellationCount >= 3 || entry.value.adminBanned,
          )
          .toList();
      if (flagged.isEmpty) {
        return const SizedBox.shrink();
      }
      flagged.sort(
        (a, b) => (b.value.isBanned(DateTime.now()) ? 1 : 0).compareTo(
          a.value.isBanned(DateTime.now()) ? 1 : 0,
        ),
      );
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cancellation review · ${flagged.length} highlighted accounts',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Three cancellations trigger a 24-hour request restriction. Reviewed accounts remain highlighted until their next counting window starts.',
            ),
            const SizedBox(height: 8),
            ...flagged.map((entry) {
              final user = widget.users
                  .where((u) => u.id == entry.key)
                  .firstOrNull;
              final banned = entry.value.isBanned(DateTime.now());
              return Card(
                color: banned ? Colors.red.shade50 : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        banned ? Icons.block : Icons.flag_outlined,
                        color: banned ? Colors.red : Colors.orange,
                      ),
                      SizedBox(
                        width: 300,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SelectableText(
                              '${user?.phone ?? "No profile"} · ${entry.value.cancellationCount} cancellations',
                            ),
                            Text(
                              entry.value.adminBanned
                                  ? 'Banned by admin until unbanned'
                                  : banned
                                  ? 'Restricted until ${entry.value.bannedUntil!.toLocal()}'
                                  : 'Access restored / restriction expired',
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: !banned || _busy.contains(entry.key)
                            ? null
                            : () async {
                                setState(() => _busy.add(entry.key));
                                try {
                                  await context
                                      .read<FirestoreService>()
                                      .unbanEmergencyUser(entry.key);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Emergency request access restored.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _busy.remove(entry.key));
                                  }
                                }
                              },
                        icon: const Icon(Icons.lock_open),
                        label: Text(
                          _busy.contains(entry.key) ? 'Restoring…' : 'Unban',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}
