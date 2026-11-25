import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/core/constants/payment_accounts.dart';
import 'package:edhiconnect_ai/features/user/donations/pay_by_qr_card.dart';
import 'package:edhiconnect_ai/models/donation.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

Donation _paid(String tid, {String user = 'donor-1'}) => Donation(
  donationId: '',
  userId: user,
  userName: 'Donor',
  amount: 2500,
  donationType: 'monetary',
  paymentMethod: 'easypaisa',
  transactionReference: PaymentAccount.normalizeTid(tid),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final account = PaymentAccounts.easypaisa;

  group('Transaction ID checks', () {
    test('Pasted receipt text is cleaned up', () {
      expect(PaymentAccount.normalizeTid('TID: 3912 4455 019'), '39124455019');
      expect(PaymentAccount.normalizeTid(' 39124-455019 '), '39124455019');
    });

    test('Valid and invalid easypaisa TIDs', () {
      expect(account.validateTid('39124455019'), isNull);
      expect(account.validateTid(''), isNotNull);
      expect(account.validateTid('ABC123'), isNotNull);
      expect(account.validateTid('123'), isNotNull);
      expect(account.validateTid('11111111111'), isNotNull);
    });

    test('Lock ids are stable per provider and TID', () {
      expect(
        FirestoreService.paymentRefId('easypaisa', '39124455019'),
        'easypaisa_39124455019',
      );
    });
  });

  group('Submitting and reviewing payments', () {
    late FirestoreService service;
    setUp(() => service = FirestoreService(automaticSimulation: false));
    tearDown(() => service.dispose());

    test('A paid donation waits for HQ verification', () async {
      final id = await service.submitDonation(_paid('39124455019'));
      final saved = (await service.getDonationsStream().first).firstWhere(
        (d) => d.donationId == id,
      );
      expect(saved.isAwaitingVerification, isTrue);
      expect(saved.transactionReference, '39124455019');
    });

    test('The same TID cannot be claimed twice, even by another donor', () async {
      await service.submitDonation(_paid('39124455019'));
      await expectLater(
        service.submitDonation(_paid('TID: 3912 4455 019', user: 'donor-2')),
        throwsA(isA<StateError>()),
      );
    });

    test('HQ can reject a payment with a reason the donor sees', () async {
      final id = await service.submitDonation(_paid('39124455020'));
      await service.rejectDonation(id, 'TID not in statement.');
      final saved = (await service.getDonationsStream().first).firstWhere(
        (d) => d.donationId == id,
      );
      expect(saved.isRejected, isTrue);
      expect(saved.reviewNote, 'TID not in statement.');
    });
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('QR card fits $width px with download and guide', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PayByQrCard(account: account, amount: 2500),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('downloadQr')), findsOneWidget);
      expect(find.text('How to send PKR 2500'), findsOneWidget);
      expect(find.textContaining(account.holderName), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
