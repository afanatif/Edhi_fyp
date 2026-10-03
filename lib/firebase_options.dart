import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// DefaultFirebaseOptions provides the default configuration for connecting to Firebase.
///
/// You can paste your Firebase Web/Mobile keys below from the Firebase Console:
/// Project Settings -> General -> Your apps -> Web / Android / iOS app.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    final options = switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for this platform.',
      ),
    };
    if (options.projectId != web.projectId) {
      throw UnsupportedError(
        'Firebase configuration for this platform must be downloaded from project ${web.projectId}.',
      );
    }
    return options;
  }

  /// Connect only when this platform is configured for the selected project.
  static bool get isConfigured {
    try {
      final options = currentPlatform;
      return options.apiKey.isNotEmpty && options.apiKey != 'YOUR_WEB_API_KEY';
    } on UnsupportedError {
      return false;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA3jf2svmaJHrFAHii8i9Q_kVrvrG7eQyU',
    appId: '1:519155114080:web:5899fe5fbeedf98f862305',
    messagingSenderId: '519155114080',
    projectId: 'eedhi-b08e1',
    authDomain: 'eedhi-b08e1.firebaseapp.com',
    storageBucket: 'eedhi-b08e1.firebasestorage.app',
    measurementId: 'G-Y4TVN1Z0R9',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCLbqlwXRgTJ5ManZGdxsjft-hMOY1-GiU',
    appId: '1:519155114080:android:57c05b1661c6db3b862305',
    messagingSenderId: '519155114080',
    projectId: 'eedhi-b08e1',
    storageBucket: 'eedhi-b08e1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC9MsT1xiw2WNuLb3QWDwczrgPIBOTkfew',
    appId: '1:494845694652:ios:a7545db375cc11212bf6b9',
    messagingSenderId: '494845694652',
    projectId: 'eedhi-b0999',
    storageBucket: 'eedhi-b0999.firebasestorage.app',
    iosBundleId: 'com.example.edhiconnectAi',
  );
}
