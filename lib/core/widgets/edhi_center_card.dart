import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/edhi_center.dart';
import 'contact_actions.dart';

class EdhiCenterCard extends StatelessWidget {
  final EdhiCenter center;
  const EdhiCenterCard({super.key, required this.center});
  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this link. Please retry.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_city, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      center.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      center.city,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(center.address),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: center.services
                .map(
                  (s) => Chip(
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Office directory, not live ambulance availability. Call 115 for emergencies.',
            style: TextStyle(fontSize: 12),
          ),
          if (center.verifiedOn != null)
            Text(
              'Source checked ${center.verifiedOn} • call to confirm',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => openDialer(context, center.contact),
                icon: const Icon(Icons.call),
                label: Text(center.contact),
              ),
              if (!center.address.contains('not published'))
                TextButton.icon(
                  onPressed: () => _open(
                    context,
                    Uri.https('www.google.com', '/maps/search/', {
                      'api': '1',
                      'query': '${center.name}, ${center.address}',
                    }),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Find on map'),
                ),
              if (center.sourceUrl != null)
                TextButton(
                  onPressed: () => _open(context, Uri.parse(center.sourceUrl!)),
                  child: const Text('Official source'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
