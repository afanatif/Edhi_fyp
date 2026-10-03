import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/core/widgets/emergency_detail_view.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

class _CitizenAuth extends AuthService {
  _CitizenAuth() : super(allowOffline: true);
  @override
  AppUser get currentUser => const AppUser(
    id: 'cancel-ui-citizen',
    name: 'Citizen',
    email: 'citizen@example.com',
    phone: '+923001234567',
    role: AppRoles.user,
  );
}

void main() {
  for (final expired in [false, true]) {
    testWidgets(
      expired
          ? 'Moving request displays a disabled cancellation button after one minute'
          : 'Moving request keeps the cancellation button enabled and confirms cancellation',
      (tester) async {
        final service = FirestoreService(
          automaticSimulation: false,
          clock: expired
              ? () => DateTime.now().subtract(const Duration(seconds: 61))
              : DateTime.now,
        );
        final auth = _CitizenAuth();
        addTearDown(service.dispose);
        addTearDown(auth.dispose);
        final id = await service.submitEmergencyRequest(
          const EmergencyRequest(
            requestId: '',
            userId: 'cancel-ui-citizen',
            emergencyType: 'Medical Emergency',
            description: 'Patient needs ambulance assistance',
            location: RequestLocation(
              latitude: 34.1986,
              longitude: 73.2312,
              address: 'Patient location',
            ),
          ),
        );
        final unit = service.getAvailableDrivers().first;
        await service.assignRequest(
          requestId: id,
          employeeId: unit.employeeId,
          employeeName: unit.name,
        );
        await service.updateRequestStatus(id, EmergencyStatus.inProgress);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              ChangeNotifierProvider<FirestoreService>.value(value: service),
            ],
            child: MaterialApp(home: EmergencyDetailView(requestId: id)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final label = expired
            ? find.text('Cancellation window closed')
            : find.textContaining('Cancel request •');
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          label,
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' | '),
        );
        final button = find.ancestor(
          of: label,
          matching: find.byType(OutlinedButton),
        );
        expect(
          tester.widget<OutlinedButton>(button).onPressed,
          expired ? isNull : isNotNull,
        );
        expect(
          find.textContaining('even if a driver is assigned or on the way'),
          findsOneWidget,
        );
        if (!expired) {
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Cancel this request?'), findsOneWidget);
          await tester.tap(find.text('Confirm'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            (await service.getRequestStream(id).first)!.status,
            EmergencyStatus.cancelled,
          );
          expect(
            service
                .getAllEmployees()
                .firstWhere((e) => e.employeeId == unit.employeeId)
                .activeRequestId,
            isEmpty,
          );
          expect(
            (await service.getEmergencyUsage(
              'cancel-ui-citizen',
            )).cancellationCount,
            1,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
