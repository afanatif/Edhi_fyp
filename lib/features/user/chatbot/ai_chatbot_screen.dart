import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../services/firestore_service.dart';
import '../../../models/chat_message.dart';
import '../../../services/welfare_knowledge_service.dart';
import '../../../core/widgets/skeleton_loader.dart';
import 'package:url_launcher/url_launcher.dart';
import '../home/user_home_screen.dart';
import '../blood_bank/blood_bank_screen.dart';
import '../donations/donations_screen.dart';
import '../missing_persons/missing_persons_screen.dart';
import '../profile/user_profile_screen.dart';
import '../quick_help/first_aid_screen.dart';
import '../quick_help/edhi_centers_screen.dart';
import '../quick_help/emergency_contacts_sheet.dart';

class AIChatbotScreen extends StatefulWidget {
  const AIChatbotScreen({super.key});

  @override
  State<AIChatbotScreen> createState() => _AIChatbotScreenState();
}

class _AIChatbotScreenState extends State<AIChatbotScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  void _selectSuggestion(String text) {
    if (text == 'Open SOS Contacts') {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const EmergencyContactsSheet(),
      );
      return;
    }
    final Widget? screen = switch (text) {
      'Open Emergency Request' => const UserHomeScreen(
        openEmergencyRequest: true,
      ),
      'Open Home' => const UserHomeScreen(),
      'Open Blood Bank' => const BloodBankScreen(),
      'Open Donations' => const DonationsScreen(),
      'Open Missing Persons' => const MissingPersonsScreen(),
      'Open Profile' => const UserProfileScreen(),
      'Open First Aid' => const FirstAidScreen(),
      'Open Centers' => const EdhiCentersScreen(),
      _ => null,
    };
    if (screen == null) {
      _sendMessage(text);
    } else {
      final embedded = {
        'Open Blood Bank',
        'Open Donations',
        'Open Profile',
      }.contains(text);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => embedded
              ? Scaffold(
                  appBar: AppBar(title: Text(text.substring(5))),
                  body: screen,
                )
              : screen,
        ),
      );
    }
  }

  final List<String> _defaultChips = [
    'How do I request an ambulance?',
    'Available blood donors',
    'Missing person reports',
    'Blood requests available',
    'Find Nearest Center',
    'Register as Blood Donor',
    'How to donate ration/food?',
    'First Aid for Burns',
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    final firestore = context.read<FirestoreService>();
    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await firestore.sendChatMessage(text.trim());
    } catch (error) {
      if (mounted) {
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message could not be saved: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
    if (!mounted) return;

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return ResponsiveShell(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.reliefGreenMedium.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: AppColors.reliefGreenMedium,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'App Assistant',
                    style: GoogleFonts.outfit(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.reliefGreenGlow,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'App records and helpful guidance',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: Column(
        children: [
          // Messages Feed
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: firestore.getChatStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 240, height: 48, borderRadius: 16),
                        SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SkeletonBox(
                            width: 180,
                            height: 40,
                            borderRadius: 16,
                          ),
                        ),
                        SizedBox(height: 12),
                        SkeletonBox(width: 260, height: 60, borderRadius: 16),
                      ],
                    ),
                  );
                }
                final messages = snapshot.data ?? [];

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isUser = msg.isUser;
                    final isEmergency =
                        msg.isEmergency ||
                        msg.message.contains('EMERGENCY DETECTED');

                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.82,
                        ),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AppColors.emergencyRed
                              : (isEmergency
                                    ? Colors.red.shade50
                                    : Colors.white),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isUser ? 20 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 20),
                          ),
                          border: Border.all(
                            color: isEmergency
                                ? AppColors.emergencyRed.withValues(alpha: 0.4)
                                : (isUser
                                      ? Colors.transparent
                                      : AppColors.border),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isUser
                                  ? AppColors.emergencyRed.withValues(
                                      alpha: 0.2,
                                    )
                                  : Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isEmergency
                                          ? AppColors.emergencyRed
                                          : AppColors.reliefGreenMedium,
                                    ),
                                    child: Icon(
                                      isEmergency
                                          ? Icons.warning_rounded
                                          : Icons.auto_awesome,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isEmergency
                                        ? 'CRITICAL DISPATCH NOTICE'
                                        : 'App Assistant',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: isEmergency
                                          ? AppColors.emergencyRed
                                          : AppColors.reliefGreenDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              isUser
                                  ? msg.message
                                  : WelfareKnowledgeService.displayText(
                                      msg.message,
                                    ),
                              style: GoogleFonts.inter(
                                color: isUser
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontSize: 13.5,
                                height: 1.45,
                                fontWeight: isUser
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                            if (!isUser && msg.quickSuggestions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children:
                                    WelfareKnowledgeService.displaySuggestions(
                                          msg.quickSuggestions,
                                        )
                                        .map(
                                          (suggestion) => ActionChip(
                                            label: Text(suggestion),
                                            onPressed: _isSending
                                                ? null
                                                : () => _selectSuggestion(
                                                    suggestion,
                                                  ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ],
                            if (isEmergency && !isUser) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.emergencyRed,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(110, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(
                                      Icons.phone_in_talk_rounded,
                                      size: 15,
                                    ),
                                    label: Text(
                                      'Call 115',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    onPressed: () =>
                                        launchUrl(Uri.parse('tel:115')),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppColors.emergencyRed,
                                        width: 1.2,
                                      ),
                                      minimumSize: const Size(120, 36),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.sos_rounded,
                                      size: 16,
                                      color: AppColors.emergencyRed,
                                    ),
                                    label: Text(
                                      'Instant SOS',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.emergencyRed,
                                      ),
                                    ),
                                    onPressed: () => _selectSuggestion(
                                      'Open Emergency Request',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Suggestion Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _defaultChips.map((chip) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _sendMessage(chip),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Text(
                          chip,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: GoogleFonts.inter(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText:
                          'Ask about triage, blood donation, or relief...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) => _sendMessage(val),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: AppColors.emergencyGradient,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                    onPressed: () => _sendMessage(_messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
