import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/core/widgets/simulated_fleet_dialog.dart';
import 'package:edhiconnect_ai/core/widgets/emergency_detail_view.dart';
import 'package:edhiconnect_ai/core/widgets/interactive_map_widget.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/features/employee/dashboard/employee_dashboard_screen.dart';
import 'package:edhiconnect_ai/features/user/blood_bank/blood_bank_screen.dart';
import 'package:edhiconnect_ai/features/user/missing_persons/missing_person_form.dart';
import 'package:edhiconnect_ai/features/auth/login_screen.dart';
import 'package:edhiconnect_ai/features/auth/register_screen.dart';
import 'package:edhiconnect_ai/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:edhiconnect_ai/features/user/home/user_home_screen.dart';
import 'package:edhiconnect_ai/features/user/donations/donations_screen.dart';
import 'package:edhiconnect_ai/features/user/quick_help/edhi_centers_screen.dart';
import 'package:edhiconnect_ai/features/admin/manage_requests/admin_dispatch_map_view.dart';

class _TestAuth extends AuthService {
  final AppUser profile;
  _TestAuth(this.profile) : super(allowOffline: true);
  @override
  AppUser get currentUser => profile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final screen in [
      'login',
      'register',
      'driver',
      'admin',
      'admin-missing',
      'admin-database',
      'blood',
      'missing',
      'home',
      'donations',
      'centers',
      'map',
      'fleet-add',
      'driver-link',
      'tracker',
      'tracker-arrived',
    ]) {
      testWidgets('$screen fits width $width without overflow', (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FirestoreService(automaticSimulation: false);
        final auth = _TestAuth(
          AppUser(
            id: screen == 'driver'
                ? 'driver_mock_1'
                : screen.startsWith('tracker')
                ? 'user_mock_1'
                : screen.startsWith('admin')
                ? 'admin_test'
                : 'citizen',
            name: 'Test User',
            email: 'test@example.com',
            phone: '03001112222',
            role: screen == 'driver'
                ? 'employee'
                : screen.startsWith('admin')
                ? 'admin'
                : 'user',
          ),
        );
        if (screen == 'tracker-arrived') {
          final unit = service.getAvailableDrivers().first;
          await service.assignRequest(
            requestId: 'REQ-101',
            employeeId: unit.employeeId,
            employeeName: unit.name,
          );
          await service.updateRequestStatus(
            'REQ-101',
            EmergencyStatus.inProgress,
          );
          await service.updateRequestStatus('REQ-101', EmergencyStatus.arrived);
        }
        final key = GlobalKey();
        final widget = switch (screen) {
          'login' => const LoginScreen(),
          'register' => const RegisterScreen(),
          'tracker' ||
          'tracker-arrived' => const EmergencyDetailView(requestId: 'REQ-101'),
          'driver' => const EmployeeDashboardScreen(),
          'admin' ||
          'admin-missing' ||
          'admin-database' => const AdminDashboardScreen(),
          'blood' => const Scaffold(body: BloodBankScreen()),
          'home' => const UserHomeScreen(),
          'donations' => const Scaffold(body: DonationsScreen()),
          'centers' => const EdhiCentersScreen(),
          'map' => const Scaffold(body: AdminDispatchMapView()),
          'fleet-add' => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showSimulatedFleetDialog(
                    context,
                    stagingPoint: const LatLng(34.1986, 73.2312),
                  ),
                  child: const Text('Add fleet'),
                ),
              ),
            ),
          ),
          'driver-link' => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showLinkDriverDialog(
                    context,
                    service.getAllEmployees().first,
                  ),
                  child: const Text('Link driver'),
                ),
              ),
            ),
          ),
          _ => const Scaffold(body: MissingPersonForm()),
        };
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              ChangeNotifierProvider<FirestoreService>.value(value: service),
            ],
            child: MaterialApp(
              home: RepaintBoundary(key: key, child: widget),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (screen == 'admin-missing') {
          await tester.tap(find.text('Welfare'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.ensureVisible(find.text('Missing persons'));
          await tester.tap(find.text('Missing persons'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Missing-person reports'), findsOneWidget);
          expect(find.text('Ali Raza'), findsOneWidget);
          expect(find.text('Contact phone'), findsNWidgets(3));
        }
        if (screen == 'admin-database') {
          await tester.tap(find.text('More'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.ensureVisible(find.text('Database'));
          await tester.tap(find.text('Database'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Database management'), findsOneWidget);
          expect(find.text('Add document'), findsOneWidget);
        }
        if (screen == 'map') {
          await tester.tap(find.textContaining('402').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          var map = tester.widget<InteractiveMapWidget>(
            find.byType(InteractiveMapWidget),
          );
          expect(
            map.markers
                .firstWhere(
                  (m) => m.key == const ValueKey('ambulance_driver_mock_1'),
                )
                .width,
            106,
          );
          expect(
            (map.markers
                        .firstWhere(
                          (m) => m.key == const ValueKey('incident_REQ-102'),
                        )
                        .child
                    as Semantics)
                .properties
                .selected,
            isTrue,
          );
          expect(find.textContaining('SIMULATED'), findsNothing);
          expect(
            map.polylineMarkerKeys.values.every(
              (key) => key == const ValueKey('ambulance_driver_mock_1'),
            ),
            isTrue,
          );
          if (width == 1280) {
            await tester.ensureVisible(find.text('Inspect'));
            await tester.tap(find.text('Inspect'));
            await tester.pump();
            map = tester.widget<InteractiveMapWidget>(
              find.byType(InteractiveMapWidget),
            );
            expect(
              map.markers
                  .firstWhere(
                    (m) => m.key == const ValueKey('ambulance_driver_mock_1'),
                  )
                  .width,
              106,
            );
            expect(
              (map.markers
                          .firstWhere(
                            (m) => m.key == const ValueKey('incident_REQ-102'),
                          )
                          .child
                      as Semantics)
                  .properties
                  .selected,
              isTrue,
            );
          }
        }
        if (screen == 'fleet-add') {
          await tester.tap(find.text('Add fleet'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Generate random drivers'));
          await tester.pumpAndSettle();
          expect(find.text('Generate fleet'), findsOneWidget);
        }
        if (screen == 'register') {
          await tester.tap(find.text('Driver'));
          await tester.pump();
          expect(find.text('Register as Driver'), findsOneWidget);
        }
        if (screen == 'driver-link') {
          await tester.tap(find.text('Link driver'));
          await tester.pumpAndSettle();
          expect(find.text('Link registered driver'), findsOneWidget);
        }
        if (screen == 'tracker') {
          expect(find.textContaining('SIMULATED FLEET'), findsNothing);
          expect(find.text('Dispatch progress'), findsOneWidget);
          expect(find.text('Confirm help received'), findsNothing);
        }
        if (screen == 'tracker-arrived') {
          expect(find.text('Confirm help received'), findsOneWidget);
          await tester.tap(find.text('Confirm help received'));
          await tester.pumpAndSettle();
          expect(find.text('Confirm help received?'), findsOneWidget);
          expect(
            find.textContaining('no longer need this ambulance'),
            findsOneWidget,
          );
          await tester.tap(find.text('Confirm'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Confirm help received'), findsNothing);
          expect(
            find.text('Response completed. The ambulance is available again.'),
            findsOneWidget,
          );
          final unit = service.getAllEmployees().firstWhere(
            (e) => e.employeeId == 'driver_mock_2',
          );
          expect(unit.status, 'available');
          expect(unit.activeRequestId, isEmpty);
        }
        final error = tester.takeException();
        if (error != null) {
          for (final element in find.byType(Row).evaluate()) {
            final render = element.findRenderObject();
            if (render is! RenderFlex || !render.hasSize) continue;
            var child = render.firstChild;
            while (child != null) {
              final data = child.parentData! as FlexParentData;
              if (child.hasSize &&
                  data.offset.dx + child.size.width > render.size.width + 0.1) {
                debugPrint(
                  'Overflow row: ${render.debugCreator}, width ${render.size.width}, child $child',
                );
              }
              child = data.nextSibling;
            }
          }
        }
        expect(error, isNull);
        if ((screen == 'driver' ||
                screen == 'login' ||
                screen == 'home' ||
                screen == 'missing' ||
                screen == 'donations' ||
                screen == 'tracker-arrived' ||
                screen == 'map') &&
            width == 390) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/ui_checks/${screen}_390.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (screen == 'admin' && width == 1280) {
          expect(find.byType(NavigationRail), findsOneWidget);
        }
        if (screen == 'admin' && width == 320) {
          expect(find.byType(NavigationBar), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        service.dispose();
      });
    }
  }
}
