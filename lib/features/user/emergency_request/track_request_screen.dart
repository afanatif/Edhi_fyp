import 'package:flutter/material.dart';
import '../../../core/widgets/emergency_detail_view.dart';

class TrackRequestScreen extends StatelessWidget {
  final String requestId;
  const TrackRequestScreen({super.key, required this.requestId});
  @override
  Widget build(BuildContext context) =>
      EmergencyDetailView(requestId: requestId, driverMode: false);
}
