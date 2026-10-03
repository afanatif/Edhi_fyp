import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/features/admin/fleet/registered_drivers_panel.dart';
import 'package:edhiconnect_ai/core/widgets/interactive_map_widget.dart';
import 'package:edhiconnect_ai/features/employee/dashboard/employee_dashboard_screen.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/models/employee.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

class _DriverAuth extends AuthService {
  final AppUser driver;
  _DriverAuth(this.driver) : super(allowOffline: true);
  @override
  AppUser get currentUser => driver;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FirestoreService service;
  late AppUser driver;
  late Employee previous;
  setUp(() async {
    service = FirestoreService(
      automaticSimulation: false,
      roadSnapper: (p) async => p,
    );
    previous = service.getAllEmployees().firstWhere(
      (e) => e.status != 'busy' && e.userId.isNotEmpty,
    );
    driver = (await service.getUsersStream().first).firstWhere(
      (u) => u.id == previous.userId,
    );
    await service.linkDriverAccount(previous.employeeId, '');
  });
  tearDown(() => service.dispose());

  Future<void> panel(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FirestoreService>.value(
        value: service,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer<FirestoreService>(
                builder: (context, service, _) => RegisteredDriversPanel(
                  ambulances: service.getAllEmployees(),
                  stagingPoint: const LatLng(34.1986, 73.2312),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('HQ shows unassigned drivers and links an existing ambulance', (
    tester,
  ) async {
    await panel(tester);
    expect(find.text(driver.name), findsOneWidget);
    expect(find.text('Awaiting ambulance assignment'), findsOneWidget);
    expect(find.textContaining('1 awaiting an ambulance'), findsOneWidget);
    expect(find.text('Assign ambulance'), findsOneWidget);
    await tester.tap(find.text('Assign ambulance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('${previous.vehicleNumber} · ${previous.status}').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save assignment'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting ambulance assignment'), findsNothing);
    expect(find.text('Assigned to ${previous.vehicleNumber}'), findsOneWidget);
    expect(
      service
          .getAllEmployees()
          .firstWhere((e) => e.employeeId == previous.employeeId)
          .userId,
      driver.id,
    );
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Create and assign updates the driver dashboard at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final count = service.getAllEmployees().length;
        await panel(tester);
        await tester.tap(find.text('Assign ambulance'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create ambulance and assign driver'));
        await tester.pumpAndSettle();
        expect(find.text('Add and assign ambulance'), findsOneWidget);
        final plate = find.widgetWithText(
          TextFormField,
          'Unique vehicle number',
        );
        await tester.ensureVisible(plate);
        await tester.enterText(plate, 'EDHI-NEW-01');
        await tester.tap(find.text('Add and assign'));
        await tester.pumpAndSettle();
        expect(
          find.text('Choose a parking spot on the map before saving.'),
          findsOneWidget,
        );
        expect(service.getAllEmployees().length, count);
        expect(find.text('Staging latitude'), findsNothing);
        expect(find.text('Staging longitude'), findsNothing);
        final chooseMap = find.text('Choose on map');
        await tester.ensureVisible(chooseMap);
        await tester.tap(chooseMap);
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(
          FilledButton,
          'Use this parking spot',
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        const parking = LatLng(34.2173, 73.2511);
        tester
            .widget<InteractiveMapWidget>(find.byType(InteractiveMapWidget))
            .onTap!(parking);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Use this parking spot'));
        await tester.pumpAndSettle();
        expect(find.text('Parking spot selected on the map.'), findsOneWidget);
        await tester.tap(find.text('Change map pin'));
        await tester.pumpAndSettle();
        tester
            .widget<InteractiveMapWidget>(find.byType(InteractiveMapWidget))
            .onTap!(const LatLng(34.25, 73.3));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Cancel map selection'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add and assign'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(service.getAllEmployees().length, count + 1);
        final added = service.getAllEmployees().firstWhere(
          (e) => e.vehicleNumber == 'EDHI-NEW-01',
        );
        expect(added.userId, driver.id);
        expect(added.name, driver.name);
        expect(added.currentLat, parking.latitude);
        expect(added.currentLng, parking.longitude);
        expect(find.text('Assigned to EDHI-NEW-01'), findsOneWidget);

        final auth = _DriverAuth(driver);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<FirestoreService>.value(value: service),
              ChangeNotifierProvider<AuthService>.value(value: auth),
            ],
            child: const MaterialApp(home: EmployeeDashboardScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ambulance EDHI-NEW-01'), findsOneWidget);
        expect(find.textContaining('awaiting an ambulance'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
      },
    );
  }
}
