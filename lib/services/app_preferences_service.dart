import 'package:flutter/material.dart';

/// Runtime accessibility and language preferences.
///
/// The state intentionally has no dependency on a platform plug-in, so the
/// emergency UI remains available in the browser, tests, and offline builds.
class AppPreferencesService extends ChangeNotifier {
  bool _isUrdu = false;
  bool _highContrast = false;
  bool _largeText = false;

  bool get isUrdu => _isUrdu;
  bool get highContrast => _highContrast;
  bool get largeText => _largeText;
  TextDirection get textDirection =>
      _isUrdu ? TextDirection.rtl : TextDirection.ltr;
  double get textScale => _largeText ? 1.18 : 1.0;

  void setUrdu(bool value) {
    if (_isUrdu == value) return;
    _isUrdu = value;
    notifyListeners();
  }

  void setHighContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();
  }

  void setLargeText(bool value) {
    if (_largeText == value) return;
    _largeText = value;
    notifyListeners();
  }

  String t(String english, String urdu) => _isUrdu ? urdu : english;
}
