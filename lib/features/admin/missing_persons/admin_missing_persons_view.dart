import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/attachment_photo.dart';
import '../../../models/missing_person_report.dart';
import '../../../services/firestore_service.dart';

class AdminMissingPersonsView extends StatefulWidget {
  const AdminMissingPersonsView({super.key});

  @override
  State<AdminMissingPersonsView> createState() =>
      _AdminMissingPersonsViewState();
}

class _AdminMissingPersonsViewState extends State<AdminMissingPersonsView> {
  late final Stream<List<MissingPersonReport>> _reports;
  String _query = '';
  String _status = 'All';

  @override
  void initState() {
    super.initState();
    _reports = context.read<FirestoreService>().getMissingPersonsStream();
  }

  String _date(BuildContext context, DateTime date) {
    final local = date.toLocal();
    final formats = MaterialLocalizations.of(context);
    return '${formats.formatMediumDate(local)} · ${formats.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(value.trim().isEmpty ? 'Not provided' : value),
      ],
    ),
  );

  Widget _card(BuildContext context, MissingPersonReport report) {
    final color = report.isSearching
        ? AppColors.statusPending
        : report.isReunited
        ? AppColors.reliefGreen
        : AppColors.statusApproved;
    return Container(
      key: ValueKey(report.reportId),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                report.personName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  report.status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (report.photoUrl.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AttachmentPhoto(
                url: report.photoUrl,
                width: 260,
                height: 200,
                fit: BoxFit.contain,
              ),
            ),
            const Text(
              'Tap the photo to enlarge',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else
            const Row(
              children: [
                Icon(Icons.person_outline, color: AppColors.textMuted),
                SizedBox(width: 8),
                Expanded(child: Text('No photo attached')),
              ],
            ),
          Wrap(
            spacing: 30,
            runSpacing: 4,
            children: [
              _detail('Age', '${report.age} years'),
              _detail('Gender', report.gender),
            ],
          ),
          _detail('Last seen location', report.lastSeenLocation),
          _detail(
            'Last seen time',
            report.lastSeenAt == null
                ? 'Not provided'
                : _date(context, report.lastSeenAt!),
          ),
          _detail('Description', report.description),
          const Divider(height: 24),
          _detail('Contact name', report.contactName),
          _detail('Contact phone', report.contactPhone),
          _detail('Reported', _date(context, report.reportedAt)),
          _detail('Report number', report.reportId),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<MissingPersonReport>>(
    stream: _reports,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Could not load missing-person reports. Check your connection and try again.',
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final reports = [...snapshot.data!]
        ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      final filtered = reports
          .where(
            (r) =>
                (_status == 'All' || r.status == _status) &&
                [
                    r.personName,
                  r.lastSeenLocation,
                  r.description,
                  r.contactName,
                  r.contactPhone,
                  r.reportId,
                ].any((value) => value.toLowerCase().contains(_query)),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${reports.length} missing-person reports',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('admin-missing-search'),
            decoration: const InputDecoration(
              labelText: 'Search missing-person reports',
              hintText: 'Name, location, contact, or report number',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in ['All', 'Searching', 'Found', 'Reunited'])
                ChoiceChip(
                  label: Text(
                    '$status (${status == 'All' ? reports.length : reports.where((r) => r.status == status).length})',
                  ),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
            ],
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                reports.isEmpty
                    ? 'No missing-person reports yet.'
                    : 'No reports match this search or status.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final report in filtered) _card(context, report),
        ],
      );
    },
  );
}
