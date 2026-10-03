import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Citizen identity checks', () {
    test(
      'CNIC accepts digits and standard hyphens, rejects malformed input',
      () {
        expect(AppUser.isValidCnic('3740512345671'), isTrue);
        expect(AppUser.isValidCnic('37405-1234567-1'), isTrue);
        for (final value in [
          '',
          '12345',
          '0000000000000',
          'abc3740512345671',
          '37405-1234567-12',
        ]) {
          expect(AppUser.isValidCnic(value), isFalse);
        }
        expect(AppUser.cleanCnic('37405-1234567-1'), '3740512345671');
        expect(AppUser.formatCnic('3740512345671'), '37405-1234567-1');
      },
    );
    test('Mobile numbers normalize to one identity', () {
      for (final value in ['0300-1234567', '+923001234567', '00923001234567']) {
        expect(AppUser.isValidPhone(value), isTrue);
        expect(AppUser.normalizePhone(value), '+923001234567');
      }
      for (final value in ['', '0300', '12345678901', 'abc03001234567']) {
        expect(AppUser.isValidPhone(value), isFalse);
      }
    });
  });
  group('Authentication without quick-login bypasses', () {
    late AuthService auth;
    setUp(() => auth = AuthService(allowOffline: true));
    tearDown(() => auth.dispose());
    test(
      'Unregistered admin, driver and citizen credentials do not grant access',
      () async {
        for (final credentials in [
          ['hq@example.test', 'fixture-admin-password'],
          ['driver@edhi.org', 'driver123'],
          ['37405-1234567-1', 'citizen123'],
        ]) {
          expect(await auth.signIn(credentials[0], credentials[1]), isFalse);
          expect(auth.currentUser, isNull);
        }
      },
    );
    test('Production auth fails closed when Firebase is unavailable', () async {
      final production = AuthService();
      expect(
        await production.signIn('hq@example.test', 'fixture-admin-password'),
        isFalse,
      );
      expect(
        await production.register(
          name: 'Test Citizen',
          cnic: '6110199911111',
          phone: '03009991111',
          password: 'password123',
          role: AppRoles.user,
        ),
        isFalse,
      );
      expect(production.isAuthenticated, isFalse);
      production.dispose();
    });
    test('Registration validates CNIC, mobile and password', () async {
      for (final values in [
        ['12345', '03001112222', 'password123'],
        ['6110111122221', 'not-a-phone', 'password123'],
        ['6110111122221', '03001112222', 'short'],
      ]) {
        expect(
          await auth.register(
            name: 'New Citizen',
            cnic: values[0],
            phone: values[1],
            password: values[2],
            role: AppRoles.user,
          ),
          isFalse,
        );
        expect(auth.isLoading, isFalse);
      }
    });
    test(
      'Registration signs out; CNIC login works and wrong password fails',
      () async {
        expect(
          await auth.register(
            name: 'Farhan Zaidi',
            cnic: '1350144556679',
            phone: '03459988776',
            password: ' securePass123 ',
            role: AppRoles.user,
          ),
          isTrue,
        );
        expect(auth.currentUser, isNull);
        expect(await auth.signIn('13501-4455667-9', 'securePass123'), isFalse);
        expect(await auth.signIn('13501-4455667-9', ' securePass123 '), isTrue);
        expect(auth.currentUser!.phone, '+923459988776');
        await auth.signOut();
        expect(await auth.signIn('1350144556679', ' securePass123 '), isTrue);
      },
    );
    test('Duplicate CNIC and equivalent phone formats are rejected', () async {
      expect(
        await auth.register(
          name: 'First Citizen',
          cnic: '6110188888811',
          phone: '03007776666',
          password: 'password123',
          role: AppRoles.user,
        ),
        isTrue,
      );
      expect(
        await auth.register(
          name: 'Duplicate CNIC',
          cnic: '61101-8888881-1',
          phone: '03007776667',
          password: 'password123',
          role: AppRoles.user,
        ),
        isFalse,
      );
      expect(
        await auth.register(
          name: 'Duplicate Mobile',
          cnic: '6110188888821',
          phone: '+923007776666',
          password: 'password123',
          role: AppRoles.user,
        ),
        isFalse,
      );
    });
    test(
      'Phone login uses the same account and password as CNIC login',
      () async {
        expect(
          await auth.register(
            name: 'Phone Login Citizen',
            cnic: '6110196654321',
            phone: '03125554321',
            password: ' phonePass123 ',
            role: AppRoles.user,
          ),
          isTrue,
        );
        expect(await auth.signIn('6110196654321', ' phonePass123 '), isTrue);
        final id = auth.currentUser!.id;
        await auth.signOut();
        for (final phone in [
          '03125554321',
          '+923125554321',
          '00923125554321',
        ]) {
          expect(
            await auth.signIn(phone, ' phonePass123 ', usePhone: true),
            isTrue,
          );
          expect(auth.currentUser!.id, id);
          expect(auth.currentUser!.role, AppRoles.user);
          await auth.signOut();
        }
        expect(
          await auth.signIn('03125554321', 'wrong-password', usePhone: true),
          isFalse,
        );
        expect(auth.currentUser, isNull);
        expect(await auth.signIn('03125554321', ' phonePass123 '), isTrue);
        expect(auth.currentUser!.id, id);
        await auth.signOut();
        expect(
          await auth.signIn('invalid-phone', ' phonePass123 ', usePhone: true),
          isFalse,
        );
      },
    );
    test('Public registration cannot request an admin role', () async {
      expect(
        await auth.register(
          name: 'Public Citizen',
          cnic: '6110144556673',
          phone: '03009998877',
          password: 'password123',
          role: AppRoles.admin,
        ),
        isFalse,
      );
      expect(await auth.signIn('6110144556673', 'password123'), isFalse);
      expect(auth.currentUser, isNull);
    });
    test('Driver signup uses CNIC login and retains the driver role', () async {
      expect(
        await auth.register(
          name: 'Registered Driver',
          cnic: '6110177556681',
          phone: '03007755881',
          password: 'password123',
          role: AppRoles.employee,
        ),
        isTrue,
      );
      expect(auth.currentUser, isNull);
      expect(await auth.signIn('61101-7755668-1', 'password123'), isTrue);
      expect(auth.currentUser!.isEmployee, isTrue);
      expect(auth.currentUser!.isAdmin, isFalse);
    });
  });
}
