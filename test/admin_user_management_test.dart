import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/features/admin/users/admin_users_view.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/models/blood_donor.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/services/welfare_knowledge_service.dart';

class _AdminAuth extends AuthService {
  _AdminAuth() : super(allowOffline: true);
  @override
  AppUser get currentUser => const AppUser(id: 'admin_test', name: 'Admin', email: '', phone: '', role: 'admin');
}

Future<AppUser> addUser(FirestoreService service, {String role = 'user'}) => service.createManagedUser(
  name: 'Muhammad Usman Waqar Khan', cnic: '61101-9998765-1', phone: '03009998765',
  password: 'fixture-password', role: role, address: 'Test address',
);

EmergencyRequest requestFor(AppUser user) => EmergencyRequest(requestId: '', userId: user.id,
  emergencyType: 'Medical Emergency', description: 'Patient needs an ambulance',
  location: const RequestLocation(latitude: 34.2, longitude: 73.2, address: 'Patient location'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Managed profiles reject duplicate identities and delete safely', () async {
    final service = FirestoreService(automaticSimulation: false);
    addTearDown(service.dispose);
    final user = await addUser(service);
    await expectLater(addUser(service), throwsStateError);
    final id = await service.submitEmergencyRequest(requestFor(user));
    await expectLater(service.deleteManagedUser(user.id), throwsStateError);
    await service.cancelEmergencyRequest(id, user.id);
    await service.deleteManagedUser(user.id);
    expect((await service.getUsersStream().first).any((u) => u.id == user.id), false);
    expect((await service.watchAllEmergencyUsage().first).containsKey(user.id), false);
    expect((await service.getRequestsStream().first).any((r) => r.requestId == id), true);
    expect((await addUser(service)).phone, '+923009998765');
  });
  test('Manual bans last until unbanned and block new emergencies', () async {
    var now = DateTime(2026, 10, 4);
    final service = FirestoreService(automaticSimulation: false, clock: () => now);
    addTearDown(service.dispose);
    final user = await addUser(service);
    await service.banEmergencyUser(user.id);
    now = now.add(const Duration(days: 2));
    expect((await service.getEmergencyUsage(user.id)).isBanned(now), true);
    await expectLater(service.submitEmergencyRequest(requestFor(user)), throwsStateError);
    await service.unbanEmergencyUser(user.id);
    expect((await service.getEmergencyUsage(user.id)).isBanned(now), false);
    expect(await service.submitEmergencyRequest(requestFor(user)), isNotEmpty);
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets('Flagged row is yellow with functioning unban and add dialog at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FirestoreService(automaticSimulation: false);
      final auth = _AdminAuth();
      addTearDown(service.dispose);
      addTearDown(auth.dispose);
      final user = await addUser(service);
      for (var i = 0; i < 3; i++) {
        final id = await service.submitEmergencyRequest(requestFor(user));
        await service.cancelEmergencyRequest(id, user.id);
      }
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<FirestoreService>.value(value: service),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ], child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: AdminUsersView()))))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'Usman');
      await tester.pump();
      final card = tester.widget<Container>(find.byKey(ValueKey('user-card-${user.id}')));
      expect((card.decoration as BoxDecoration).color, const Color(0xFFFFF3CD));
      expect(find.text('3 cancellations'), findsOneWidget);
      await tester.ensureVisible(find.byKey(ValueKey('ban-${user.id}')));
      await tester.tap(find.byKey(ValueKey('ban-${user.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect((await service.getEmergencyUsage(user.id)).isBanned(DateTime.now()), false);
      expect(tester.widget<Switch>(find.byKey(ValueKey('active-${user.id}'))).value, true);
      expect((tester.widget<Container>(find.byKey(ValueKey('user-card-${user.id}'))).decoration as BoxDecoration).color, const Color(0xFFFFF3CD));
      await tester.ensureVisible(find.text('Add user'));
      await tester.tap(find.text('Add user'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Initial password'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('Blood group signs, city follow-up, language and donor availability are preserved', () {
    final donor = BloodDonor(donorId: 'available', userId: 'donor', userName: 'Listed donor', userPhone: '03001112222', bloodGroup: 'A+', city: 'Abbottabad');
    final unavailable = donor.copyWith(donorId: 'unavailable', userName: 'Unavailable donor', availability: false);
    final wrongGroup = donor.copyWith(donorId: 'wrong', userName: 'Wrong group', bloodGroup: 'A-');
    final wrongCity = donor.copyWith(donorId: 'wrong-city', userName: 'Wrong city', city: 'Karachi');
    final reply = WelfareKnowledgeService.answer('Abbottabad', history: ['mujhe a+ khoon chayie'], donors: [donor, unavailable, wrongGroup, wrongCity]);
    expect(reply.text, contains('A+ khoon'));
    expect(reply.text, contains('Abbottabad'));
    expect(reply.text, contains('Listed donor'));
    for (final excluded in ['Unavailable donor', 'Wrong group', 'Wrong city', 'Source:', 'simulated']) { expect(reply.text, isNot(contains(excluded))); }
    expect(WelfareKnowledgeService.bloodGroupFor('AB negative'), 'AB-');
    expect(WelfareKnowledgeService.bloodGroupFor('0 positive'), 'O+');
    expect(WelfareKnowledgeService.bloodGroupFor('مجھے اے پازیٹو خون چاہیے'), 'A+');
    expect(WelfareKnowledgeService.answer('مجھے A+ خون چاہیے').text, contains('خون کی ضرورت'));
    expect(WelfareKnowledgeService.answer('mujhe a+ khoon chayie', donors: []).text, contains('koi available donor listed nahi'));
    expect(WelfareKnowledgeService.answer('how to request an ambulance').text, isNot(contains('simulated')));
    expect(WelfareKnowledgeService.displayText('Answer\n\nSource: EdhiConnect app guide'), 'Answer');
  });
}
