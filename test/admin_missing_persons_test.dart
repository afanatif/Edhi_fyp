import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/core/widgets/attachment_photo.dart';
import 'package:edhiconnect_ai/core/widgets/stored_photo.dart';
import 'package:edhiconnect_ai/features/admin/missing_persons/admin_missing_persons_view.dart';
import 'package:edhiconnect_ai/models/missing_person_report.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

class _ReportsService extends FirestoreService {
  final updates = StreamController<List<MissingPersonReport>>.broadcast();
  final List<MissingPersonReport> initial;
  _ReportsService(this.initial) : super(automaticSimulation: false);
  @override
  Stream<List<MissingPersonReport>> getMissingPersonsStream() async* {
    yield initial;
    yield* updates.stream;
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

MissingPersonReport _report(
  String name, {
  String id = 'MP-1',
  String status = 'Searching',
  String photo = '',
}) => MissingPersonReport(
  reportId: id,
  personName: name,
  age: 17,
  gender: 'Male',
  lastSeenLocation: 'Abbottabad bus station',
  description: 'Blue jacket and black backpack',
  contactName: 'Family contact',
  contactPhone: '+923001112233',
  lastSeenAt: DateTime(2026, 10, 2, 18, 30),
  reportedAt: DateTime(2026, 10, 3, 9),
  status: status,
  photoUrl: photo,
);

void main() {
  testWidgets(
    'HQ shows all report details, opens its photo and receives new reports live',
    (tester) async {
      final service = _ReportsService([
        _report('Reported person', photo: 'firestore-photo:missing-photo'),
      ]);
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<FirestoreService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AdminMissingPersonsView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final value in [
        'Reported person',
        '17 years',
        'Male',
        'Abbottabad bus station',
        'Blue jacket and black backpack',
        'Family contact',
        '+923001112233',
        'MP-1',
        'Last seen time',
        'Reported',
      ]) {
        expect(find.text(value), findsOneWidget);
      }
      expect(
        tester.widget<AttachmentPhoto>(find.byType(AttachmentPhoto)).url,
        'firestore-photo:missing-photo',
      );
      await tester.ensureVisible(find.byType(AttachmentPhoto));
      await tester.tap(find.byType(AttachmentPhoto));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        tester
            .widget<StoredPhoto>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(StoredPhoto),
              ),
            )
            .url,
        'firestore-photo:missing-photo',
      );
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      service.updates.add([
        _report('Reported person', photo: 'firestore-photo:missing-photo'),
        _report('New report', id: 'MP-2', status: 'Found'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New report'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-missing-search')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-missing-search')),
        'new report',
      );
      await tester.pumpAndSettle();
      expect(find.text('New report'), findsOneWidget);
      expect(find.text('Reported person'), findsNothing);
      await tester.tap(find.text('Searching (1)'));
      await tester.pumpAndSettle();
      expect(
        find.text('No reports match this search or status.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
