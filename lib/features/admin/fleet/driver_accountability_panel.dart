import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/dispatch_offer.dart';
import '../../../services/firestore_service.dart';

String _ago(DateTime? time, DateTime now) {
  if (time == null) return 'Never';
  final d = now.difference(time);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}

/// HQ table: who answers emergencies quickly, who declines, who misses.
class DriverAccountabilityPanel extends StatefulWidget {
  const DriverAccountabilityPanel({super.key});

  @override
  State<DriverAccountabilityPanel> createState() =>
      _DriverAccountabilityPanelState();
}

class _DriverAccountabilityPanelState extends State<DriverAccountabilityPanel> {
  int _sortColumn = 5; // Missed
  bool _ascending = false;
  bool _linkedOnly = true;

  List<DriverAccountability> _sorted(List<DriverAccountability> rows) {
    int cmp(DriverAccountability a, DriverAccountability b) =>
        switch (_sortColumn) {
          0 => a.unit.name.compareTo(b.unit.name),
          1 => a.unit.vehicleNumber.compareTo(b.unit.vehicleNumber),
          2 => a.unit.status.compareTo(b.unit.status),
          3 => a.offers.compareTo(b.offers),
          4 => a.accepted.compareTo(b.accepted),
          5 => a.missed.compareTo(b.missed),
          6 => a.declined.compareTo(b.declined),
          7 => (a.lastAcceptedAt ?? DateTime(1970)).compareTo(
            b.lastAcceptedAt ?? DateTime(1970),
          ),
          _ => (a.avgResponseSeconds ?? 999).compareTo(
            b.avgResponseSeconds ?? 999,
          ),
        };
    final list = [...rows]..sort(cmp);
    return _ascending ? list : list.reversed.toList();
  }

  void _sort(int column, bool ascending) => setState(() {
    _sortColumn = column;
    _ascending = ascending;
  });

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FirestoreService>();
    final now = service.clockNow;
    final all = service.driverAccountability();
    final rows = _sorted(
      all.where((r) => !_linkedOnly || !r.autoAccepts).toList(),
    );
    final totalMissed = all.fold<int>(0, (sum, r) => sum + r.missed);
    final waiting = service.dispatchOffers.where((o) => o.isLive(now)).length;
    final answered = all.fold<int>(0, (sum, r) => sum + r.offers);
    final accepted = all.fold<int>(0, (sum, r) => sum + r.accepted);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fact_check_rounded,
                    color: AppColors.emergencyRed,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Driver accountability',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              FilterChip(
                label: const Text('Drivers with accounts only'),
                selected: _linkedOnly,
                onSelected: (v) => setState(() => _linkedOnly = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Drivers get 60 seconds to accept an automatic assignment. A missed offer is a penalty; a decline passes the job on at once and is not a penalty. Two misses in a row take a driver off duty automatically. Tap a row for its history.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Kpi(
                'Waiting for answer',
                '$waiting',
                AppColors.statusPending,
                Icons.timer_outlined,
              ),
              _Kpi(
                'Acceptance rate',
                answered == 0 ? '—' : '${(accepted * 100 / answered).round()}%',
                AppColors.reliefGreen,
                Icons.thumb_up_alt_outlined,
              ),
              _Kpi(
                'Penalties (missed)',
                '$totalMissed',
                AppColors.emergencyRed,
                Icons.report_gmailerrorred_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No drivers with accounts yet. Link a registered driver to an ambulance under Registered drivers.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumn,
                sortAscending: _ascending,
                showCheckboxColumn: false,
                headingRowHeight: 44,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                headingTextStyle: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                columns: [
                  DataColumn(label: const Text('Driver'), onSort: _sort),
                  DataColumn(label: const Text('Ambulance'), onSort: _sort),
                  DataColumn(label: const Text('Status'), onSort: _sort),
                  DataColumn(
                    label: const Text('Offers'),
                    numeric: true,
                    onSort: _sort,
                  ),
                  DataColumn(
                    label: const Text('Accepted'),
                    numeric: true,
                    onSort: _sort,
                  ),
                  DataColumn(
                    label: const Text('Missed'),
                    numeric: true,
                    onSort: _sort,
                  ),
                  DataColumn(
                    label: const Text('Declined'),
                    numeric: true,
                    onSort: _sort,
                  ),
                  DataColumn(label: const Text('Last accepted'), onSort: _sort),
                  DataColumn(
                    label: const Text('Avg response'),
                    numeric: true,
                    onSort: _sort,
                  ),
                ],
                rows: rows.map((r) => _row(context, r, now)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  DataRow _row(BuildContext context, DriverAccountability r, DateTime now) {
    final highlight = r.riskLevel == 'high'
        ? AppColors.emergencyRed.withValues(alpha: 0.07)
        : r.riskLevel == 'watch'
        ? AppColors.statusPendingBg.withValues(alpha: 0.6)
        : null;
    return DataRow(
      color: highlight == null ? null : WidgetStatePropertyAll(highlight),
      onSelectChanged: (_) => _showHistory(context, r),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.riskLevel == 'high')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.emergencyRed,
                    size: 18,
                  ),
                ),
              Text(
                r.unit.name.isEmpty ? 'Unnamed' : r.unit.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (r.autoAccepts) ...[
                const SizedBox(width: 6),
                const _Pill('Auto', AppColors.textMuted),
              ],
            ],
          ),
        ),
        DataCell(Text(r.unit.vehicleNumber)),
        DataCell(
          r.unit.isAutoOffline
              ? const _Pill('Auto-offline', AppColors.statusPending)
              : _StatusPill(r.unit.status),
        ),
        DataCell(Text('${r.offers}')),
        DataCell(
          Text(
            '${r.accepted}',
            style: const TextStyle(
              color: AppColors.reliefGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Text(
            '${r.missed}',
            style: TextStyle(
              color: r.missed > 0
                  ? AppColors.emergencyRed
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        DataCell(Text('${r.declined}')),
        DataCell(Text(_ago(r.lastAcceptedAt, now))),
        DataCell(
          Text(
            r.avgResponseSeconds == null
                ? '—'
                : '${r.avgResponseSeconds!.round()} s',
          ),
        ),
      ],
    );
  }

  Future<void> _showHistory(BuildContext context, DriverAccountability r) {
    final service = context.read<FirestoreService>();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.unit.name} · offer history'),
        content: SizedBox(
          width: 460,
          child: r.history.isEmpty
              ? const Text('No offers since the last reset.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: r.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final o = r.history[i];
                    final (color, icon) = switch (o.outcome) {
                      DispatchOffer.accepted => (
                        AppColors.reliefGreen,
                        Icons.check_circle,
                      ),
                      DispatchOffer.missed => (
                        AppColors.emergencyRed,
                        Icons.timer_off,
                      ),
                      DispatchOffer.declined => (
                        AppColors.statusApproved,
                        Icons.do_not_disturb_on,
                      ),
                      _ => (AppColors.statusPending, Icons.hourglass_top),
                    };
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: color),
                      title: Text(
                        '${o.emergencyType} · ${o.distanceKm.toStringAsFixed(1)} km',
                      ),
                      subtitle: Text(
                        '${o.address}\n${_ago(o.offeredAt, service.clockNow)}${o.responseSeconds == null ? '' : ' · answered in ${o.responseSeconds} s'}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        o.outcome.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (r.missed > 0)
            TextButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset penalties'),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await service.resetDriverPenalties(r.unit.employeeId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Penalties reset for ${r.unit.name}.'),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not reset: $error')),
                    );
                  }
                }
              },
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Kpi(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'available' => AppColors.reliefGreen,
      'busy' => AppColors.statusInProgress,
      _ => AppColors.statusCancelled,
    };
    final label = switch (status) {
      'available' => 'Available',
      'busy' => 'Busy',
      _ => 'Offline',
    };
    return _Pill(label, color);
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}
