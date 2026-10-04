import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../core/constants/app_constants.dart';
import '../firebase_options.dart';

class AuthService extends ChangeNotifier {
  fb.FirebaseAuth? _fbAuth;
  FirebaseFirestore? _firestore;
  StreamSubscription<fb.User?>? _authSubscription;
  AppUser? _currentUser;
  bool _isLoading = false;
  bool _isRegistering = false;
  String? _errorMessage;
  final bool allowOffline;
  static final List<AppUser> _offlineUsers = [];
  static final Map<String, String> _offlinePasswords = {};

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get isLiveFirebase =>
      DefaultFirebaseOptions.isConfigured && _fbAuth != null;

  /// Offline credentials are available only to explicitly opted-in tests.
  AuthService({this.allowOffline = false}) {
    try {
      if (DefaultFirebaseOptions.isConfigured) {
        _fbAuth = fb.FirebaseAuth.instance;
        _firestore = FirebaseFirestore.instance;
        _authSubscription = _fbAuth!.authStateChanges().listen(
          _onAuthStateChanged,
        );
      }
    } catch (e) {
      _fbAuth = null;
      _firestore = null;
      debugPrint('Firebase Auth unavailable: $e');
    }
  }

  Future<AppUser> _loadProfile(fb.User user) async {
    final doc = await _firestore!
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();
    if (!doc.exists || doc.data() == null) {
      throw StateError('Account profile is missing. Contact Operations.');
    }
    final profile = AppUser.fromMap(doc.data()!, docId: doc.id);
    if (!profile.isActive) {
      throw StateError('This account is disabled. Contact Operations.');
    }
    if (!AppRoles.allRoles.contains(profile.role)) {
      throw StateError('Invalid account role. Contact Operations.');
    }
    return profile;
  }

  Future<void> _onAuthStateChanged(fb.User? user) async {
    if (_isRegistering || _isLoading) return;
    if (user == null) {
      _currentUser = null;
      notifyListeners();
      return;
    }
    try {
      final profile = await _loadProfile(user);
      if (_fbAuth?.currentUser?.uid != user.uid) return;
      _currentUser = profile;
    } catch (e) {
      _currentUser = null;
      _errorMessage = _message(e);
      await _fbAuth?.signOut();
    }
    notifyListeners();
  }

  // Public aliases contain only an opaque Auth email. Personal profiles and
  // roles remain private, and Firebase Auth always verifies the password.
  Future<String> _resolveAuthEmail(String identifier, bool usePhone) async {
    if (!usePhone && identifier.contains('@')) return identifier;
    final key = usePhone
        ? 'phone_${AppUser.normalizePhone(identifier)}'
        : 'cnic_${AppUser.cleanCnic(identifier)}';
    final alias = await _firestore!.collection('login_aliases').doc(key).get();
    final email = alias.data()?['authEmail'];
    if (email is String && email.endsWith('@citizen.edhi.org')) return email;
    // Existing CNIC accounts can continue using their original identity.
    if (!usePhone) {
      return '${AppUser.cleanCnic(identifier)}@citizen.edhi.org';
    }
    throw StateError('Invalid phone number or password.');
  }

  Future<bool> signIn(
    String identifier,
    String password, {
    bool? usePhone,
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final raw = identifier.trim();
      final phoneLogin = usePhone ?? AppUser.isValidPhone(raw);
      if (phoneLogin && !AppUser.isValidPhone(raw)) {
        throw ArgumentError('Enter a valid Pakistani mobile number.');
      }
      if (isLiveFirebase) {
        if (!phoneLogin && !AppUser.isValidCnic(raw) && !raw.contains('@')) {
          throw ArgumentError('Use your 13-digit CNIC or staff account email.');
        }
        final email = await _resolveAuthEmail(raw, phoneLogin);
        final credential = await _fbAuth!.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (credential.user == null) {
          throw StateError('Sign in did not complete.');
        }
        _currentUser = await _loadProfile(credential.user!);
      } else {
        if (!allowOffline) {
          throw StateError('Firebase is unavailable. Reconnect and try again.');
        }
        final user = _offlineUsers
            .where(
              (u) => phoneLogin
                  ? AppUser.normalizePhone(u.phone) ==
                        AppUser.normalizePhone(raw)
                  : (AppUser.isValidCnic(raw) &&
                            AppUser.cleanCnic(u.cnic) ==
                                AppUser.cleanCnic(raw)) ||
                        u.email.toLowerCase() == raw.toLowerCase(),
            )
            .firstOrNull;
        if (user == null ||
            _offlinePasswords[user.id] != password ||
            !user.isActive) {
          throw StateError(
            'Invalid credentials. Check your CNIC, phone or staff email and password.',
          );
        }
        _currentUser = user;
      }
      return true;
    } catch (e) {
      _currentUser = null;
      _errorMessage = _message(e);
      try {
        await _fbAuth?.signOut();
      } catch (_) {}
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String cnic,
    required String password,
    required String phone,
    required String role,
    String email = '',
    String address = '',
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _isRegistering = true;
    _errorMessage = null;
    notifyListeners();
    fb.User? createdAuthUser;
    bool profileSaved = false;
    try {
      if (![AppRoles.user, AppRoles.employee].contains(role)) {
        throw ArgumentError(
          'Choose Citizen or Driver registration. Admin accounts are created by Operations.',
        );
      }
      if (name.trim().length < 2) throw ArgumentError('Enter your full name.');
      if (!AppUser.isValidCnic(cnic)) {
        throw ArgumentError('Enter a valid 13-digit Pakistani CNIC.');
      }
      if (!AppUser.isValidPhone(phone)) {
        throw ArgumentError('Enter a valid Pakistani mobile number.');
      }
      if (password.length < 8) {
        throw ArgumentError('Password must be at least 8 characters.');
      }
      if (email.trim().isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
        throw ArgumentError('Enter a valid contact email.');
      }
      final digits = AppUser.cleanCnic(cnic);
      final normalizedPhone = AppUser.normalizePhone(phone);
      if (isLiveFirebase) {
        // Catch duplicates before creating an Auth account.
        final aliases = await Future.wait([
          _firestore!.collection('login_aliases').doc('cnic_$digits').get(),
          _firestore!
              .collection('login_aliases')
              .doc('phone_$normalizedPhone')
              .get(),
        ]);
        if (aliases.any((alias) => alias.exists)) {
          throw StateError(
            'This CNIC or phone number is already registered. Please sign in instead.',
          );
        }
      }
      // A random Auth identity prevents the public alias from exposing a CNIC,
      // phone number, contact email, UID, role or password.
      final random = Random.secure();
      final opaqueId = base64UrlEncode(
        List.generate(16, (_) => random.nextInt(256)),
      ).replaceAll('=', '').toLowerCase();
      final authEmail = 'account_$opaqueId@citizen.edhi.org';
      String id;
      if (isLiveFirebase) {
        final credential = await _fbAuth!.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
        createdAuthUser = credential.user;
        if (createdAuthUser == null) {
          throw StateError('Registration did not complete.');
        }
        id = createdAuthUser.uid;
      } else {
        if (!allowOffline) {
          throw StateError('Firebase is unavailable. Reconnect and try again.');
        }
        if (_offlineUsers.any(
          (u) =>
              AppUser.cleanCnic(u.cnic) == digits || u.phone == normalizedPhone,
        )) {
          throw StateError('This CNIC or phone number is already registered.');
        }
        id = 'test_${DateTime.now().microsecondsSinceEpoch}';
      }
      final user = AppUser(
        id: id,
        name: name.trim(),
        email: email.trim().isEmpty ? authEmail : email.trim().toLowerCase(),
        phone: normalizedPhone,
        cnic: AppUser.formatCnic(cnic),
        role: role,
        address: address.trim(),
        createdAt: DateTime.now(),
      );
      if (isLiveFirebase) {
        final claimed = await _firestore!.runTransaction<bool>((
          transaction,
        ) async {
          final claimRef = _firestore!
              .collection('phone_claims')
              .doc(normalizedPhone);
          final claim = await transaction.get(claimRef);
          final cnicAliasRef = _firestore!
              .collection('login_aliases')
              .doc('cnic_$digits');
          final phoneAliasRef = _firestore!
              .collection('login_aliases')
              .doc('phone_$normalizedPhone');
          final cnicAlias = await transaction.get(cnicAliasRef);
          final phoneAlias = await transaction.get(phoneAliasRef);
          if (claim.exists || cnicAlias.exists || phoneAlias.exists) {
            // Throwing a Dart error inside this web SDK callback can lose the
            // message across the JavaScript Future bridge. Return an outcome.
            return false;
          }
          transaction.set(claimRef, {'userId': user.id});
          transaction.set(cnicAliasRef, {'authEmail': authEmail});
          transaction.set(phoneAliasRef, {'authEmail': authEmail});
          transaction.set(
            _firestore!.collection(AppConstants.usersCollection).doc(user.id),
            {...user.toMap(), 'authEmail': authEmail},
          );
          return true;
        });
        if (!claimed) {
          throw StateError(
            'This CNIC or phone number is already registered. Please sign in instead.',
          );
        }
      } else {
        _offlineUsers.add(user);
        _offlinePasswords[id] = password;
      }
      profileSaved = true;
      return true;
    } catch (e) {
      _errorMessage = _message(e);
      // Roll back the new Auth account if the profile/unique phone claim failed.
      if (createdAuthUser != null && !profileSaved) {
        try {
          await createdAuthUser.delete();
        } catch (_) {
          _errorMessage =
              'Profile setup failed and account cleanup could not complete. Contact Operations before retrying.';
        }
      }
      return false;
    } finally {
      try {
        await _fbAuth?.signOut();
      } catch (_) {}
      _currentUser = null;
      _isRegistering = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  String _message(Object error) {
    if (error is fb.FirebaseAuthException) {
      return switch (error.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Invalid credentials. Check your CNIC, phone or staff email and password.',
        'email-already-in-use' =>
          'This CNIC is already registered. Please sign in.',
        'network-request-failed' =>
          'Connection failed. Check your internet and retry.',
        'operation-not-allowed' =>
          'Enable Email/Password authentication in your Firebase project.',
        'weak-password' =>
          'Choose a stronger password of at least 8 characters.',
        'too-many-requests' => 'Too many attempts. Please wait and retry.',
        _ => error.message ?? 'Authentication failed. Please retry.',
      };
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Firebase permissions blocked account setup. Ask Operations to deploy the project rules.';
    }
    return error.toString().replaceFirst(
      RegExp(r'^(Bad state: |Invalid argument\(s\): )'),
      '',
    );
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _fbAuth?.signOut();
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
