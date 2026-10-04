import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/brand_logo.dart';
import '../../services/auth_service.dart';
import '../../models/app_user.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _role = AppRoles.user;

  @override
  void dispose() {
    _nameController.dispose();
    _cnicController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (_formKey.currentState?.validate() ?? false) {
      final auth = context.read<AuthService>();
      final success = await auth.register(
        name: _nameController.text,
        cnic: _cnicController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        role: _role,
        password: _passwordController.text,
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _role == AppRoles.employee
                        ? 'Driver account created! Sign in with your CNIC. Admin must link your ambulance before jobs appear.'
                        : 'Account created successfully! Please sign in with your CNIC and password.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.reliefGreenMedium,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              auth.errorMessage ?? 'Registration failed. Please retry.',
            ),
            backgroundColor: AppColors.emergencyRed,
            action: (auth.errorMessage ?? '').contains('already registered')
                ? SnackBarAction(
                    label: 'Sign in',
                    textColor: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          final authService = context.read<AuthService>();
          if (authService.isAuthenticated) {
            await authService.signOut();
          }
        }
      },
      child: ResponsiveShell(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Create Account'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final authService = context.read<AuthService>();
              if (authService.isAuthenticated) {
                await authService.signOut();
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: BrandLogo(size: 62, showSurface: true)),
                  const SizedBox(height: 18),
                  const Text(
                    'Join EdhiConnect AI',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create a Citizen account or register as a Driver.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Register as',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Citizen'),
                        selected: _role == AppRoles.user,
                        onSelected: auth.isLoading
                            ? null
                            : (_) => setState(() => _role = AppRoles.user),
                      ),
                      ChoiceChip(
                        label: const Text('Driver'),
                        selected: _role == AppRoles.employee,
                        onSelected: auth.isLoading
                            ? null
                            : (_) => setState(() => _role = AppRoles.employee),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Full Name',
                    hint: 'e.g. Usman Waqar',
                    controller: _nameController,
                    prefixIcon: Icons.badge_outlined,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter your name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'CNIC Number (National ID / Username) *',
                    hint: '37405-1234567-1',
                    controller: _cnicController,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.fingerprint_rounded,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your 13-digit CNIC';
                      }
                      if (!AppUser.isValidCnic(v)) {
                        return 'CNIC must be exactly 13 digits (e.g. 37405-1234567-1)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Contact Email (Optional)',
                    hint: 'For contact only; sign in using your CNIC',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    validator: (v) {
                      if (v != null &&
                          v.trim().isNotEmpty &&
                          !RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(v.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Phone Number',
                    hint: '03xxxxxxxxx',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    validator: (v) => !AppUser.isValidPhone(v ?? '')
                        ? 'Please enter a valid phone number'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'City & Residential Address',
                    hint: 'Mandian, Abbottabad',
                    controller: _addressController,
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.reliefGreenSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.reliefGreenMedium.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.reliefGreenMedium,
                          size: 21,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _role == AppRoles.employee
                                ? 'Driver registration opens your panel. Admin links your account to an ambulance before you can view and complete its jobs.'
                                : 'Citizens can request an ambulance and use relief services. Choose Driver to manage an admin-linked ambulance.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: AppColors.reliefGreenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Password',
                    hint: '••••••••',
                    controller: _passwordController,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Password must be at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  CustomTextField(
                    label: 'Confirm Password',
                    controller: _confirmPasswordController,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline,
                    validator: (v) => v != _passwordController.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  CustomButton(
                    text: _role == AppRoles.employee
                        ? 'Register as Driver'
                        : 'Register as Citizen',
                    isLoading: auth.isLoading,
                    onPressed: _handleRegister,
                    backgroundColor: AppColors.reliefGreenMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
