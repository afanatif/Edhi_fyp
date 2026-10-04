import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/chatbot_reply.dart';
import '../models/blood_donor.dart';
import 'app_chat_guide.dart';
import 'chat_context_service.dart';

class _KnowledgeEntry {
  final String provider, title, text, url, keywords;
  final String? fetchedAt;
  late final Set<String> terms = WelfareKnowledgeService._tokens(
    '$title $keywords $text',
  );
  late final Set<String> titleTerms = WelfareKnowledgeService._tokens(title);
  late final Set<String> keywordTerms = WelfareKnowledgeService._tokens(
    keywords,
  );
  _KnowledgeEntry(
    this.provider,
    this.title,
    this.text,
    this.url,
    this.keywords, [
    this.fetchedAt,
  ]);
}

/// Cached local retrieval: public source data never receives private chat text.
/// External reference material stays internal; replies use implemented app workflows.
class WelfareKnowledgeService {
  static Future<void>? _loading;
  static final List<_KnowledgeEntry> _scraped = [];
  static Future<void> initialize() => _loading ??= _load();
  static Future<void> _load() async {
    try {
      final corpus =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/knowledge/welfare_sources.json',
                ),
              )
              as Map<String, dynamic>;
      for (final doc in corpus['documents'] as List) {
        for (final paragraph in doc['paragraphs'] as List) {
          final text = paragraph as String;
          if (text.length < 70) continue;
          _scraped.add(
            _KnowledgeEntry(
              doc['provider'],
              doc['title'],
              text,
              doc['url'],
              '',
              doc['fetchedAt'],
            ),
          );
        }
      }
    } catch (_) {
      /* Reviewed offline answers remain available. */
    }
  }

  static final _aliases = <String, String>{
    'eidhi': 'edhi',
    'ambulanse': 'ambulance',
    'ambulence': 'ambulance',
    'ambullance': 'ambulance',
    'ambulances': 'ambulance',
    'donations': 'donation',
    'donors': 'donor',
    'centres': 'center',
    'centers': 'center',
    'centre': 'center',
    'shelters': 'shelter',
    'meals': 'food',
    'volunteering': 'volunteer',
    'madad': 'help',
    'imdad': 'help',
    'khoon': 'blood',
    'khun': 'blood',
    'atiya': 'donation',
    'atyat': 'donation',
    'paisa': 'money',
    'paise': 'money',
    'khana': 'food',
    'rashan': 'ration',
    'raashan': 'ration',
    'markaz': 'center',
    'bachay': 'children',
    'bacha': 'child',
    'bachon': 'children',
    'yateem': 'orphan',
    'buzurg': 'elderly',
    'behosh': 'unconscious',
    'behoshi': 'unconscious',
    'ایدھی': 'edhi',
    'ایمبولینس': 'ambulance',
    'خون': 'blood',
    'عطیہ': 'donation',
    'زکوٰۃ': 'zakat',
    'راشن': 'ration',
    'کھانا': 'food',
    'بےہوش': 'unconscious',
    'بچے': 'children',
    'مدد': 'help',
  };
  static final _stop = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'of',
    'to',
    'for',
    'and',
    'in',
    'i',
    'me',
    'my',
    'you',
    'your',
    'can',
    'do',
    'does',
    'what',
    'how',
    'tell',
    'about',
    'it',
    'this',
    'that',
    'please',
    'ka',
    'ki',
    'ke',
    'hai',
    'hain',
    'mujhe',
    'kya',
    'se',
    'ko',
    'aur',
    'batao',
    'karein',
  };
  static Set<String> _tokens(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
      .split(' ')
      .where((t) => t.isNotEmpty && !_stop.contains(t))
      .map((t) => _aliases[t] ?? t)
      .toSet();

  static ChatbotReply answer(
    String message, {
    List<String> history = const [],
    List<BloodDonor>? donors,
  }) {
    final relevant = ChatContextService.topicHistory(message, history);
    final guide = AppChatGuide.reply(message, history: relevant);
    if (guide.isEmergencyIntent) return guide;
    if (hasBloodIntent(message, history: relevant)) {
      return _bloodReply(message, history: relevant, donors: donors);
    }
    return guide;
  }

  static String _language(String text) {
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(text)) return 'ur';
    if (RegExp(
      r'\b(mujhe|mujhay|chahiye|chahye|chaiye|khoon|khun|hai|kahan|kaise|karna|karein|batao|nahi|saans|behosh|chayie|krna|chahie|chaye|chayye)\b',
    ).hasMatch(text.toLowerCase())) {
      return 'roman';
    }
    return 'en';
  }

  static String? bloodGroupFor(
    String message, {
    List<String> history = const [],
  }) {
    String? extract(String raw) {
      var text = raw
          .toUpperCase()
          .replaceAll(RegExp(r'\b(POSITIVE|PLUS|POS)\b'), '+')
          .replaceAll(RegExp(r'\b(NEGATIVE|MINUS|NEG)\b'), '-')
          .replaceAll('اے بی', 'AB')
          .replaceAll('اے', 'A')
          .replaceAll('بی', 'B')
          .replaceAll('او', 'O')
          .replaceAll(RegExp(r'مثبت|پازیٹو'), '+')
          .replaceAll(RegExp(r'منفی|نیگیٹو'), '-');
      final match = RegExp(
        r'(?:^|[^A-Z0-9])(AB|A|B|O|0)\s*([+-])(?=$|[^A-Z0-9])',
      ).firstMatch(text);
      return match == null
          ? null
          : '${match.group(1) == '0' ? 'O' : match.group(1)}${match.group(2)}';
    }

    final explicit = extract(message);
    if (explicit != null) return explicit;
    for (final previous in history.reversed.take(8)) {
      final group = extract(previous);
      if (group != null) return group;
    }
    return null;
  }

  static final _cities = <String, String>{
    'abbottabad': 'Abbottabad',
    'abt': 'Abbottabad',
    'ایبٹ آباد': 'Abbottabad',
    'karachi': 'Karachi',
    'کراچی': 'Karachi',
    'lahore': 'Lahore',
    'لاہور': 'Lahore',
    'islamabad': 'Islamabad',
    'اسلام آباد': 'Islamabad',
    'rawalpindi': 'Rawalpindi',
    'راولپنڈی': 'Rawalpindi',
    'peshawar': 'Peshawar',
    'پشاور': 'Peshawar',
    'mansehra': 'Mansehra',
    'مانسہرہ': 'Mansehra',
    'haripur': 'Haripur',
    'ہری پور': 'Haripur',
    'quetta': 'Quetta',
    'کوئٹہ': 'Quetta',
    'faisalabad': 'Faisalabad',
    'فیصل آباد': 'Faisalabad',
    'multan': 'Multan',
    'ملتان': 'Multan',
    'hyderabad': 'Hyderabad',
    'حیدر آباد': 'Hyderabad',
  };
  static String? _city(String text) {
    final lower = text.toLowerCase();
    for (final entry in _cities.entries) {
      if (RegExp(
        '(?:^|[\\s,])${RegExp.escape(entry.key)}(?=\$|[\\s,.!?])',
      ).hasMatch(lower)) {
        return entry.value;
      }
    }
    return null;
  }

  static bool hasBloodIntent(
    String message, {
    List<String> history = const [],
  }) {
    final tokens = _tokens(message);
    if (tokens.any(
      {'blood', 'donor', 'plasma', 'platelet', 'platelets'}.contains,
    )) {
      return true;
    }
    if (bloodGroupFor(message) != null) return true;
    final previousTopic = history.reversed.firstWhere(
      (m) => RegExp(
        r'blood|donor|khoon|خون|missing|ambulance|donation|payment',
        caseSensitive: false,
      ).hasMatch(m),
      orElse: () => '',
    );
    return _tokens(previousTopic).any({'blood', 'donor'}.contains) &&
        (_city(message) != null ||
            RegExp(
              r'\b(yes|haan|han|units|unit|donate|register|where|how|kahan|kaise|many|available|availability|there|post|submit|status|any)\b',
            ).hasMatch(message.toLowerCase()));
  }

  static String? cityFor(String message, {List<String> history = const []}) {
    final city = _city(message);
    if (city != null) return city;
    for (final previous in history.reversed) {
      final saved = _city(previous);
      if (saved != null) return saved;
    }
    return null;
  }

  static ChatbotReply _bloodReply(
    String message, {
    required List<String> history,
    List<BloodDonor>? donors,
  }) {
    final group = bloodGroupFor(message, history: history);
    String? city = _city(message);
    for (final previous in history.reversed) {
      city ??= _city(previous);
    }
    final language =
        _language(message) == 'en' &&
            history.isNotEmpty &&
            _city(message) != null
        ? _language(history.last)
        : _language(message);
    final lower = message.toLowerCase();
    if (RegExp(
          r'my availability|my donor availability|available for immediate|turn (off|on)|toggle|update my donor',
        ).hasMatch(lower) &&
        !RegExp(r'need|required|find|chahiye|chayie').hasMatch(lower)) {
      return const ChatbotReply(
        text:
            'Update your donor availability\n\nOpen Blood Bank → Donate. Set Available for Immediate Donation on or off, review your city and contact number, then tap Save & Register as Blood Donor to save the change.',
        quickSuggestions: ['Open Blood Bank', 'Find blood donors'],
      );
    }
    final registering =
        RegExp(
          r'register|become|as a donor|donate blood|blood donate|khoon dena|خون دینا|عطیہ خون',
        ).hasMatch(lower) &&
        !RegExp(
          r'need|required|chahiye|chayie|chahye|zaroorat|ضرورت|چاہیے',
        ).hasMatch(lower);
    final label =
        group ??
        (language == 'roman'
            ? 'apne blood group'
            : language == 'ur'
            ? 'اپنے بلڈ گروپ'
            : 'your blood group');
    final heading = registering
        ? language == 'roman'
              ? 'Blood donor registration'
              : language == 'ur'
              ? 'خون کے عطیے کے لیے رجسٹریشن'
              : 'Become a blood donor'
        : language == 'roman'
        ? '$label khoon ki zaroorat${city == null ? '' : ' — $city'}'
        : language == 'ur'
        ? '$label خون کی ضرورت${city == null ? '' : ' — $city'}'
        : '$label blood request${city == null ? '' : ' — $city'}';
    final steps = registering
        ? language == 'roman'
              ? 'Blood Bank → Donate kholein. $label select karein, apna shehar aur contact number dalein, aur availability on karein.'
              : language == 'ur'
              ? 'Blood Bank میں Donate کھولیں۔ $label منتخب کریں، شہر اور رابطہ نمبر درج کریں اور دستیابی فعال کریں۔'
              : 'Open Blood Bank → Donate. Select $label, enter your city and contact number, turn on availability, then tap Save & Register as Blood Donor.'
        : language == 'roman'
        ? 'Blood Bank → Donors kholein aur ${group ?? 'required blood group'} ka filter lagayein${city == null ? '' : ', city $city rakhein'}. Listed donors ko contact karein. Requests → Post Need mein hospital, required units aur contact number ke saath request post karein.'
        : language == 'ur'
        ? 'Blood Bank → Donors کھولیں اور ${group ?? 'مطلوبہ بلڈ گروپ'} کا فلٹر لگائیں${city == null ? '' : '، شہر $city منتخب کریں'}۔ درج شدہ عطیہ دہندگان سے رابطہ کریں۔ Requests → Post Need میں ہسپتال، مطلوبہ یونٹس اور رابطہ نمبر کے ساتھ درخواست درج کریں۔'
        : 'Open Blood Bank → Donors and filter by ${group ?? 'the required blood group'}${city == null ? '' : ' and $city'}. Contact listed donors. Open Requests → Post Need to enter the hospital, required units and contact number.';
    var text = '$heading\n\n$steps';
    if (!registering && donors != null) {
      final matches = donors
          .where(
            (d) =>
                d.availability &&
                (group == null || d.bloodGroup == group) &&
                (city == null ||
                    d.city.toLowerCase().contains(city.toLowerCase())),
          )
          .toList();
      if (matches.isNotEmpty) {
        text +=
            '\n\n${language == 'roman'
                ? 'Listed donors'
                : language == 'ur'
                ? 'درج شدہ عطیہ دہندگان'
                : 'Listed donors'} (${matches.length} available in the records checked):\n';
        text += matches
            .take(3)
            .map(
              (d) =>
                  '• ${d.userName} · ${d.bloodGroup} · ${d.city}${d.userPhone.isEmpty ? '' : ' · ${d.userPhone}'}',
            )
            .join('\n');
      } else {
        text += language == 'roman'
            ? '\n\nCheck kiye gaye records mein is filter ke liye abhi koi available donor listed nahi. Blood Bank → Donors mein mazeed records dekhein.'
            : language == 'ur'
            ? '\n\nاس فلٹر کے لیے فی الحال کوئی دستیاب عطیہ دہندہ درج نہیں۔ Urgent Need میں درخواست درج کریں۔'
            : '\n\nNo available donor was found in the records checked for these filters. Open Blood Bank → Donors to browse further.';
      }
    }
    if (!registering && donors == null) {
      text +=
          '\n\nDonor availability could not be checked here. Open Blood Bank → Donors for current listings.';
    }
    return ChatbotReply(
      text: text,
      quickSuggestions: registering
          ? [
              'Open Blood Bank',
              'Update my donor availability',
              'Find ${group ?? 'blood'} donors',
            ]
          : [
              'Open Blood Bank',
              'Find ${group ?? 'blood'} donors',
              'Post ${group ?? 'blood'} blood request',
              'Become a blood donor',
            ],
    );
  }

  // Clean up old persisted replies without changing the stored conversation.
  static String displayText(String text) {
    final clean = text.replaceAll(RegExp(r'\n\nSource:[^\n]*'), '').trim();
    if (RegExp(
      r'\bedhi\b|\bchh?ipa\b|\bchhipa\b|ایدھی|چھیپا',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return AppChatGuide.reply(clean).text;
    }
    return clean.replaceAll(
      'The simulated journey changes',
      'The request status changes',
    );
  }

  static List<String> displaySuggestions(List<String> suggestions) =>
      suggestions
          .where(
            (text) => !RegExp(
              r'edhi|chh?ipa|chhipa|ایدھی|چھیپا',
              caseSensitive: false,
            ).hasMatch(text),
          )
          .toList();
}
