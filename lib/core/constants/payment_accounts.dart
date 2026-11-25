/// Where donors send money. Edit this file to change or add accounts.
///
/// Only details printed on the account's own QR card are shown in the app
/// (holder name and the masked number), never the full mobile number.
class PaymentAccount {
  final String id;
  final String provider; // shown to donors, e.g. "easypaisa"
  final String holderName;
  final String maskedNumber;
  final String qrAsset;
  final String appName;

  /// Rule for the transaction ID printed on the provider's receipt/SMS.
  final RegExp tidPattern;
  final String tidHint;

  const PaymentAccount({
    required this.id,
    required this.provider,
    required this.holderName,
    required this.maskedNumber,
    required this.qrAsset,
    required this.appName,
    required this.tidPattern,
    required this.tidHint,
  });

  /// Strips spaces, dashes and "TID:" so "TID: 3912 4455 019" == "39124455019".
  static String normalizeTid(String raw) => raw
      .toUpperCase()
      .replaceAll(RegExp(r'^\s*(TID|TRX|TXN|ID)\s*[:#]?\s*'), '')
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  String? validateTid(String raw) {
    final tid = normalizeTid(raw);
    if (tid.isEmpty) {
      return 'Paste the Transaction ID from your $appName receipt.';
    }
    if (!tidPattern.hasMatch(tid)) return tidHint;
    if (RegExp(r'^(\d)\1+$').hasMatch(tid)) {
      return 'That does not look like a real Transaction ID.';
    }
    return null;
  }
}

class PaymentAccounts {
  PaymentAccounts._();

  /// The account on the QR card supplied for this project.
  static final easypaisa = PaymentAccount(
    id: 'easypaisa',
    provider: 'easypaisa',
    holderName: 'MUHAMMAD USMAN WAQAR KHAN',
    maskedNumber: '*******9075',
    qrAsset: 'assets/images/easypaisa_qr.jpg',
    appName: 'easypaisa',
    tidPattern: RegExp(r'^\d{8,14}$'),
    tidHint:
        'An easypaisa Transaction ID is a number (usually 11 digits) shown on the success screen and in the SMS.',
  );

  static final all = [easypaisa];

  /// Smallest and largest amount accepted in the app (PKR).
  static const minAmount = 10.0;
  static const maxAmount = 1000000.0;
}
