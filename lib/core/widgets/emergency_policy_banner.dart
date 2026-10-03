import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/emergency_usage.dart';
import '../../services/firestore_service.dart';
import 'contact_actions.dart';

class EmergencyPolicyBanner extends StatefulWidget {
  final String userId;
  const EmergencyPolicyBanner({super.key, required this.userId});
  @override
  State<EmergencyPolicyBanner> createState() => _EmergencyPolicyBannerState();
}

class _EmergencyPolicyBannerState extends State<EmergencyPolicyBanner> {
  Stream<EmergencyUsage>? _stream;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= context.read<FirestoreService>().watchEmergencyUsage(
      widget.userId,
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<EmergencyUsage>(
    stream: _stream,
    builder: (context, snapshot) {
      final usage = snapshot.data;
      if (snapshot.hasError) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Unable to load the request policy. Check your connection or Firebase rules setup. Call Edhi 115 for urgent help.',
            ),
          ),
        );
      }
      if (usage == null) return const SizedBox.shrink();
      final banned = usage.isBanned(DateTime.now());
      if (!banned && usage.countAt(DateTime.now()) == 0) {
        return const SizedBox.shrink();
      }
      return Card(
        color: banned ? const Color(0xFFFFE8E8) : const Color(0xFFFFF5DF),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                banned
                    ? 'Ambulance requests blocked until ${usage.bannedUntil!.toLocal()}'
                    : '${usage.countAt(DateTime.now())}/3 cancellations in 24 hours',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Three cancellations block new ambulance requests for 24 hours. Other services and the emergency helpline remain available.',
              ),
              TextButton.icon(
                onPressed: () => openDialer(context, '115'),
                icon: const Icon(Icons.call),
                label: const Text('Call Edhi 115'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
