import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/brand_logo.dart';
import '../../services/auth_service.dart';
import '../../models/app_user.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _usePhone = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      final auth = context.read<AuthService>();
      final success = await auth.signIn(
        _emailController.text,
        _passwordController.text,
        usePhone: _usePhone,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'Invalid email or password.'),
            backgroundColor: AppColors.emergencyRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return ResponsiveShell(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 30,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: AppColors.emergencyRed.withValues(alpha: 0.03),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const BrandLogo(size: 88, showSurface: true),
                      const SizedBox(height: 16),

                      // Brand Typography
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'EDHI',
                              style: GoogleFonts.outfit(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: AppColors.emergencyRed,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CONNECT',
                              style: GoogleFonts.outfit(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.reliefGreenMedium,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColors.reliefGradient,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'AI',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.reliefGreenSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '24/7 EMERGENCY & RELIEF NETWORK',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            letterSpacing: 0.7,
                            fontWeight: FontWeight.w800,
                            color: AppColors.reliefGreenDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in securely to access live emergency coordination.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),

                      SegmentedButton<bool>(
                        expandedInsets: EdgeInsets.zero,
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('CNIC', maxLines: 1, softWrap: false),
                            icon: Icon(Icons.badge_outlined),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Phone', maxLines: 1, softWrap: false),
                            icon: Icon(Icons.phone_outlined),
                          ),
                        ],
                        selected: {_usePhone},
                        onSelectionChanged: auth.isLoading
                            ? null
                            : (selection) {
                                setState(() {
                                  _usePhone = selection.single;
                                  _emailController.clear();
                                });
                              },
                      ),
                      const SizedBox(height: 20),

                      // Input Fields
                      CustomTextField(
                        key: ValueKey(_usePhone),
                        label: _usePhone
                            ? 'Mobile number'
                            : 'CNIC or staff email',
                        hint: _usePhone
                            ? '03001234567 or +923001234567'
                            : '13-digit CNIC or staff email',
                        controller: _emailController,
                        keyboardType: _usePhone
                            ? TextInputType.phone
                            : TextInputType.text,
                        prefixIcon: _usePhone
                            ? Icons.phone_outlined
                            : Icons.badge_outlined,
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (_usePhone) {
                            return AppUser.isValidPhone(value)
                                ? null
                                : 'Enter a valid Pakistani mobile number';
                          }
                          return AppUser.isValidCnic(value) ||
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value)
                              ? null
                              : 'Enter your 13-digit CNIC or staff email';
                        },
                      ),
                      const SizedBox(height: 18),

                      CustomTextField(
                        label: 'Password',
                        hint: '••••••••',
                        controller: _passwordController,
                        isPassword: true,
                        prefixIcon: Icons.lock_outline_rounded,
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Password must be at least 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 26),

                      // Sign In Button
                      CustomButton(
                        text: 'Sign In to Dashboard',
                        icon: Icons.arrow_forward_rounded,
                        isLoading: auth.isLoading,
                        onPressed: _handleLogin,
                        backgroundColor: AppColors.emergencyRed,
                      ),
                      const SizedBox(height: 18),

                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Register with CNIC',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                color: AppColors.reliefGreenMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
