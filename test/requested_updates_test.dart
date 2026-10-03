import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/core/widgets/current_location_display.dart';
import 'package:edhiconnect_ai/core/widgets/photo_picker_field.dart';
import 'package:edhiconnect_ai/features/auth/login_screen.dart';
import 'package:edhiconnect_ai/features/user/donations/donations_screen.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/models/donation.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/selected_photo.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

class _Auth extends AuthService {
  _Auth() : super(allowOffline: true);
  @override
  AppUser get currentUser => const AppUser(
    id: 'test-donor',
    name: 'Test Donor',
    email: 'test@example.com',
    phone: '+923001234567',
    role: 'user',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Photo selection accepts supported signatures and rejects disguised or oversized files',
    () {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=',
      );
      expect(SelectedPhoto.fromBytes(png).contentType, 'image/png');
      expect(
        SelectedPhoto.fromBytes(
          Uint8List.fromList([255, 216, 255, 224]),
        ).contentType,
        'image/jpeg',
      );
      expect(
        SelectedPhoto.fromBytes(
          Uint8List.fromList('RIFF1234WEBPmore'.codeUnits),
        ).contentType,
        'image/webp',
      );
      expect(
        () => SelectedPhoto.fromBytes(
          Uint8List.fromList('not an image'.codeUnits),
        ),
        throwsArgumentError,
      );
      final large = Uint8List(SelectedPhoto.maxBytes + 1)
        ..setAll(0, png.take(8));
      expect(() => SelectedPhoto.fromBytes(large), throwsArgumentError);
    },
  );

  test(
    'Clothing photo and optional campaign survive saving and status updates',
    () {
      const donation = Donation(
        donationId: 'don1',
        userId: 'citizen',
        amount: 0,
        donationType: 'clothing',
        photoUrl: 'https://example.com/photo.png',
      );
      final saved = Donation.fromMap(
        donation.toMap(),
      ).copyWith(status: 'Verified');
      expect(saved.photoUrl, donation.photoUrl);
      expect(saved.campaign, isEmpty);
      expect(
        saved.copyWith(campaign: 'Winter Warmth').campaign,
        'Winter Warmth',
      );
      expect(Donation.fromMap({'donationType': 'clothing'}).photoUrl, isEmpty);
    },
  );

  testWidgets(
    'Login switches between CNIC and phone fields without losing password',
    (tester) async {
      final auth = AuthService(allowOffline: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      expect(find.text('CNIC or staff email'), findsOneWidget);
      final password = find.byType(TextFormField).last;
      await tester.enterText(password, 'password123');
      await tester.ensureVisible(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone'));
      await tester.pump();
      expect(find.text('Mobile number'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).keyboardType,
        TextInputType.phone,
      );
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'password123',
      );
      await tester.tap(find.text('CNIC'));
      await tester.pump();
      expect(find.text('CNIC or staff email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Actual location updates, refreshes and preserves coordinates when geocoding is offline',
    (tester) async {
      final controllers = <StreamController<LatLng>>[];
      RequestLocation? current;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: CurrentLocationDisplay(
                positionStream: () {
                  final stream = StreamController<LatLng>();
                  controllers.add(stream);
                  return stream.stream;
                },
                addressLookup: (lat, lng) async => throw StateError('offline'),
                onChanged: (location) => current = location,
              ),
            ),
          ),
        ),
      );
      controllers.last.add(const LatLng(24.86, 67.01));
      await tester.pump();
      expect(find.text('24.86000, 67.01000'), findsOneWidget);
      expect(current!.latitude, 24.86);
      controllers.last.add(const LatLng(24.87, 67.02));
      await tester.pump();
      expect(find.text('24.87000, 67.02000'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh current location'));
      await tester.pump();
      expect(controllers.length, 2);
      controllers.last.add(const LatLng(24.88, 67.03));
      await tester.pump();
      expect(current!.latitude, 24.88);
      controllers.last.addError(StateError('permission denied'));
      await tester.pump();
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(current, isNull);
      expect(find.textContaining('Mandian'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final controller in controllers) {
        unawaited(controller.close());
      }
      await tester.pump();
    },
  );

  testWidgets('Reverse geocoding shows the actual place name', (tester) async {
    final controller = StreamController<LatLng>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentLocationDisplay(
            positionStream: () => controller.stream,
            addressLookup: (lat, lng) async => 'Clifton, Karachi',
          ),
        ),
      ),
    );
    controller.add(const LatLng(24.81, 67.03));
    await tester.pump();
    expect(find.text('Clifton, Karachi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(controller.close());
    await tester.pump();
  });

  testWidgets(
    'An address lookup cannot restore a location after permission failure',
    (tester) async {
      final controller = StreamController<LatLng>();
      final address = Completer<String>();
      RequestLocation? current;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentLocationDisplay(
              positionStream: () => controller.stream,
              addressLookup: (_, _) => address.future,
              onChanged: (location) => current = location,
            ),
          ),
        ),
      );
      controller.add(const LatLng(24.81, 67.03));
      await tester.pump();
      controller.addError(StateError('permission denied'));
      await tester.pump();
      address.complete('Clifton, Karachi');
      await tester.pump();
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(current, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(controller.close());
      await tester.pump();
    },
  );

  testWidgets('Clothing pickup can be submitted without a campaign or photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth();
    final service = FirestoreService(automaticSimulation: false);
    addTearDown(auth.dispose);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<FirestoreService>.value(value: service),
        ],
        child: const MaterialApp(home: Scaffold(body: DonationsScreen())),
      ),
    );
    await tester.tap(find.text('👕 Clothes'));
    await tester.pump();
    expect(find.text('No campaign'), findsOneWidget);
    expect(find.text('Clothing photo (optional)'), findsOneWidget);
    expect(find.byType(PhotoPickerField), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Clifton, Karachi',
    );
    await tester.ensureVisible(find.text('Request In-Kind Pickup'));
    await tester.tap(find.text('Request In-Kind Pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Donation Receipt'), findsOneWidget);
    final donation =
        (await service.getDonationsStream(userId: 'test-donor').first).single;
    expect(donation.campaign, isEmpty);
    expect(donation.photoUrl, isEmpty);
    expect(donation.notes, contains('Clifton, Karachi'));
    expect(donation.notes, isNot(contains('Flood Relief')));
  });
}
