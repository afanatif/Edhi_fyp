import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/services/welfare_knowledge_service.dart';
import 'package:edhiconnect_ai/features/user/chatbot/ai_chatbot_screen.dart';
import 'package:edhiconnect_ai/features/user/donations/donations_screen.dart';
import 'package:edhiconnect_ai/features/user/blood_bank/blood_bank_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Replies stay in implemented app features even for provider and unrelated queries',
    () {
      for (final message in [
        'Edhi founder',
        'Chhipa ambulance',
        'Chipa WhatsApp',
        'shelter admission',
        'jazzcash payment',
        'nearest center',
        'مجھ کو ایدھی کے بارے میں بتاؤ',
        'Chhipa blood bank',
        'quantum engines',
        'missing person',
        'mujhe rashan chahiye',
      ]) {
        final reply = WelfareKnowledgeService.answer(message);
        expect(
          reply.text,
          isNot(
            matches(
              RegExp(
                r'\bedhi\b|chh?ipa|chhipa|ایدھی|چھیپا|Source:|simulated',
                caseSensitive: false,
              ),
            ),
          ),
          reason: message,
        );
        expect(reply.sourceUrls, isEmpty);
        expect(reply.quickSuggestions, isNotEmpty);
      }
      expect(
        WelfareKnowledgeService.answer('donate money').text,
        contains('does not charge'),
      );
      expect(
        WelfareKnowledgeService.answer('saans nahi aa rahi').isEmergencyIntent,
        true,
      );
      expect(
        WelfareKnowledgeService.answer('ambulance available?').text,
        contains('request card'),
      );
      expect(
        WelfareKnowledgeService.answer(
          'status?',
          history: ['track ambulance'],
        ).text,
        contains('assigned ambulance'),
      );
    },
  );

  test(
    'Old organization replies and buttons are adapted without exposing references',
    () {
      expect(
        WelfareKnowledgeService.displayText(
          'Chhipa donation channels\n\nSource: Chhipa',
        ),
        contains('Donate'),
      );
      expect(
        WelfareKnowledgeService.displaySuggestions([
          'Chhipa services',
          'Edhi contact',
          'Open Blood Bank',
        ]),
        ['Open Blood Bank'],
      );
    },
  );

  for (final destination in ['Open Donations', 'Open Blood Bank']) {
    testWidgets('Chat shortcut navigates directly to $destination', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FirestoreService(automaticSimulation: false);
      final auth = AuthService(allowOffline: true);
      addTearDown(service.dispose);
      addTearDown(auth.dispose);
      await tester.runAsync(() => service.sendChatMessage('hello'));
      final before = (await service.getChatStream().first).length;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: service),
            ChangeNotifierProvider.value(value: auth),
          ],
          child: const MaterialApp(home: AIChatbotScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(destination).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byType(
          destination == 'Open Donations' ? DonationsScreen : BloodBankScreen,
        ),
        findsOneWidget,
      );
      expect((await service.getChatStream().first).length, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
