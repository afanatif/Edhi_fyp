import 'package:flutter/material.dart';
import '../../../core/widgets/emergency_detail_view.dart';

class DriverMissionScreen extends StatelessWidget {
  final String requestId;
  const DriverMissionScreen({super.key, required this.requestId});
  @override
  Widget build(BuildContext context) =>
      EmergencyDetailView(requestId: requestId, driverMode: true);
}
