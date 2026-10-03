import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../core/widgets/edhi_center_card.dart';
import '../../../core/widgets/contact_actions.dart';
import '../../../services/firestore_service.dart';

class EdhiCentersScreen extends StatefulWidget {
  const EdhiCentersScreen({super.key});
  @override
  State<EdhiCentersScreen> createState() => _EdhiCentersScreenState();
}

class _EdhiCentersScreenState extends State<EdhiCentersScreen> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final centers = context
        .watch<FirestoreService>()
        .getEdhiCenters()
        .where(
          (c) => '${c.name} ${c.city} ${c.address}'.toLowerCase().contains(
            _search.toLowerCase(),
          ),
        )
        .toList();
    return ResponsiveShell(
      appBar: AppBar(title: const Text('Edhi office directory')),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search city or office',
                  ),
                  onChanged: (value) => setState(() => _search = value.trim()),
                ),
                TextButton.icon(
                  onPressed: () => openDialer(context, '115'),
                  icon: const Icon(Icons.call),
                  label: const Text('Emergency? Call Edhi 115'),
                ),
              ],
            ),
          ),
          Expanded(
            child: centers.isEmpty
                ? const Center(
                    child: Text('No matching offices. Try another city.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: centers.length,
                    itemBuilder: (_, i) => EdhiCenterCard(center: centers[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
