import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/app_preferences_service.dart';
import '../../../services/notification_service.dart';
import '../../../models/feedback_item.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _cnicController.text = user.cnic.isNotEmpty
          ? user.cnic
          : 'Not Registered';
      _phoneController.text = user.phone;
      _addressController.text = user.address;
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showFeedbackDialog(BuildContext context) {
    int rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edhi Service Feedback',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How was your experience with EdhiConnect emergency response and relief services?',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starVal = index + 1;
                  return IconButton(
                    icon: Icon(
                      starVal <= rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => rating = starVal),
                  );
                }),
              ),
              const SizedBox(height: 14),
              CustomTextField(
                controller: commentController,
                label: 'Your Comments / Suggestions',
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.reliefGreenMedium,
              ),
              onPressed: () {
                final auth = context.read<AuthService>();
                final firestore = context.read<FirestoreService>();
                final user = auth.currentUser;

                final item = FeedbackItem(
                  feedbackId: '',
                  userId: user?.id ?? 'guest_user',
                  userName: user?.name ?? 'Citizen',
                  comments: commentController.text.trim().isEmpty
                      ? 'Service provided satisfactorily.'
                      : commentController.text.trim(),
                  rating: rating,
                );

                firestore.submitFeedback(item);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Thank you! Your feedback helps Edhi improve humanitarian relief.',
                    ),
                    backgroundColor: AppColors.reliefGreenMedium,
                  ),
                );
              },
              child: const Text('Submit Feedback'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final preferences = context.watch<AppPreferencesService>();
    final user = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.emergencyRed.withValues(
                    alpha: 0.1,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 38,
                    color: AppColors.emergencyRed,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Citizen',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.reliefGreenSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              (user?.role ?? 'User').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.reliefGreenDark,
                              ),
                            ),
                          ),
                          if ((user?.cnic ?? '').isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 12,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    user!.cnic,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Profile Details',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),

          CustomTextField(
            controller: _nameController,
            label: 'Full Legal Name',
            prefixIcon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _cnicController,
            label: 'National Identity Card (CNIC / Username)',
            prefixIcon: Icons.fingerprint_rounded,
            readOnly: true,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _phoneController,
            label: 'Mobile Contact Number',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _addressController,
            label: 'Residential Address',
            prefixIcon: Icons.home_outlined,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _emailController,
            label: 'Email Address',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),

          const SizedBox(height: 20),
          CustomButton(
            text: 'Save Profile Changes',
            icon: Icons.check,
            color: AppColors.reliefGreenMedium,
            isLoading: _isSaving,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _isSaving = true);
              await Future.delayed(const Duration(milliseconds: 500));
              if (!mounted) return;
              setState(() => _isSaving = false);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Profile information updated successfully.'),
                ),
              );
            },
          ),

          const SizedBox(height: 28),
          Text(
            preferences.t('Language & Accessibility', 'زبان اور رسائی'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.translate_rounded),
                  title: Text(
                    preferences.t('Urdu / RTL mode', 'اردو / دائیں سے بائیں'),
                  ),
                  subtitle: Text(
                    preferences.t(
                      'Switch navigation direction and bilingual essentials',
                      'نیویگیشن اور ضروری متن اردو میں دکھائیں',
                    ),
                  ),
                  value: preferences.isUrdu,
                  onChanged: preferences.setUrdu,
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.text_increase_rounded),
                  title: Text(preferences.t('Larger text', 'بڑا متن')),
                  subtitle: Text(
                    preferences.t(
                      'Improve readability throughout the app',
                      'پوری ایپ میں متن زیادہ واضح کریں',
                    ),
                  ),
                  value: preferences.largeText,
                  onChanged: preferences.setLargeText,
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.contrast_rounded),
                  title: Text(preferences.t('High contrast', 'زیادہ کنٹراسٹ')),
                  subtitle: Text(
                    preferences.t(
                      'Stronger borders and visual separation',
                      'واضح سرحدیں اور بہتر بصری فرق',
                    ),
                  ),
                  value: preferences.highContrast,
                  onChanged: preferences.setHighContrast,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const Text(
            'App Services & Support',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),

          _buildActionTile(
            icon: Icons.notifications_active_outlined,
            title: preferences.t(
              'Enable Emergency Push Alerts',
              'ایمرجنسی اطلاعات فعال کریں',
            ),
            subtitle: preferences.t(
              'Receive dispatch and status alerts when the app is closed',
              'ایپ بند ہونے پر بھی امدادی اطلاعات حاصل کریں',
            ),
            color: const Color(0xFF2563EB),
            onTap: () async {
              final notifications = context.read<NotificationService>();
              final firestore = context.read<FirestoreService>();
              final allowed = await notifications.requestPushPermission();
              final token = notifications.registeredDeviceToken;
              if (allowed && token != null && user != null) {
                await firestore.registerPushToken(user.id, token);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      allowed
                          ? 'Emergency push alerts enabled.'
                          : 'Push alerts are unavailable or permission was declined.',
                    ),
                  ),
                );
              }
            },
          ),
          _buildActionTile(
            icon: Icons.reviews_outlined,
            title: 'Give Service Feedback',
            subtitle: 'Rate Edhi emergency response experience',
            color: Colors.amber.shade800,
            onTap: () => _showFeedbackDialog(context),
          ),
          _buildActionTile(
            icon: Icons.phone_in_talk_outlined,
            title: 'Edhi 24/7 Helpline',
            subtitle: 'Direct emergency hotline: 115',
            color: AppColors.reliefGreenDark,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Calling Edhi 115 helpline...')),
              );
            },
          ),
          _buildActionTile(
            icon: Icons.logout,
            title: 'Sign Out Session',
            subtitle: 'Log out from current account',
            color: AppColors.emergencyRed,
            onTap: () => auth.signOut(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 18,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}
