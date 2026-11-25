import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/payment_accounts.dart';
import '../../../core/theme/app_colors.dart';

/// QR to scan, account check, download and a numbered "how to pay" guide.
class PayByQrCard extends StatelessWidget {
  final PaymentAccount account;
  final double amount;
  const PayByQrCard({super.key, required this.account, required this.amount});

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await rootBundle.load(account.qrAsset);
      await FileSaver.instance.saveFile(
        name: '${account.provider}-donation-qr',
        bytes: data.buffer.asUint8List(),
        fileExtension: 'jpg',
        mimeType: MimeType.jpeg,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'QR saved to your Downloads. In the easypaisa app choose "Scan QR" then the gallery/upload icon to pick it.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save the QR. Take a screenshot instead.'),
        ),
      );
    }
  }

  void _zoom(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: Image.asset(account.qrAsset, fit: BoxFit.contain),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final amountText = amount > 0 ? 'PKR ${amount.toStringAsFixed(0)}' : '—';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.reliefGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pay with ${account.appName} QR',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => _zoom(context),
              child: Semantics(
                image: true,
                label: 'Payment QR code. Tap to enlarge.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Image.asset(account.qrAsset, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Tap the QR to enlarge',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.reliefGreenSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Money goes to', style: TextStyle(fontSize: 11.5)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.holderName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.reliefGreenDark,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy name',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () =>
                          _copy(context, account.holderName, 'Account name'),
                    ),
                  ],
                ),
                Text(
                  '${account.provider} · ${account.maskedNumber}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('downloadQr'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.reliefGreen,
                ),
                onPressed: () => _download(context),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download QR'),
              ),
              OutlinedButton.icon(
                onPressed: () => _zoom(context),
                icon: const Icon(Icons.zoom_in_rounded, size: 18),
                label: const Text('Full screen'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'How to send $amountText',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _Step(
            1,
            'Open the ${account.appName} app and tap "Scan QR".',
            detail:
                'Paying from this same phone? Tap Download QR, then in the scanner pick the image from your gallery.',
          ),
          _Step(
            2,
            'Check the name shown is ${account.holderName}.',
            detail: 'If the name is different, stop and do not pay.',
          ),
          _Step(3, 'Enter $amountText and confirm with your own PIN.'),
          _Step(
            4,
            'Copy the Transaction ID (TID) from the success screen or SMS and paste it below.',
            detail:
                'Edhi HQ matches the TID with the account before your receipt is confirmed.',
          ),
          const SizedBox(height: 6),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppColors.emergencyRed,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Never share your PIN or OTP with anyone, including Edhi staff.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.emergencyRedDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;
  final String? detail;
  const _Step(this.number, this.text, {this.detail});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.reliefGreen,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
