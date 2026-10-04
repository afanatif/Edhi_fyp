import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/app_preferences_service.dart';
import 'features/auth/auth_wrapper.dart';
import 'services/welfare_knowledge_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WelfareKnowledgeService.initialize();

  // Initialize Firebase if configured, otherwise run in offline demo mode
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase initialization notice: $e');
    }
  }

  runApp(const EdhiConnectApp());
}

class EdhiConnectApp extends StatelessWidget {
  const EdhiConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => AppPreferencesService()),
        ChangeNotifierProxyProvider2<
          AuthService,
          NotificationService,
          FirestoreService
        >(
          create: (ctx) =>
              FirestoreService()
                ..attachNotificationService(ctx.read<NotificationService>()),
          update: (_, auth, notif, firestore) =>
              (firestore ?? FirestoreService())
                ..attachNotificationService(notif)
                ..bindSession(
                  auth.currentUser?.isActive == true
                      ? auth.currentUser?.id
                      : null,
                  role: auth.currentUser?.role,
                ),
        ),
      ],
      child: Consumer<AppPreferencesService>(
        builder: (context, preferences, _) => MaterialApp(
          title: preferences.t('EdhiConnect AI', 'ایدھی کنیکٹ اے آئی'),
          debugShowCheckedModeBanner: false,
          theme: preferences.highContrast
              ? AppTheme.highContrastTheme
              : AppTheme.lightTheme,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(preferences.textScale),
                boldText: preferences.highContrast || media.boldText,
              ),
              child: Directionality(
                textDirection: preferences.textDirection,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}
