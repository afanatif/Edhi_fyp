import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/chatbot_reply.dart';
import '../models/blood_donor.dart';

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
/// Reviewed answers take precedence; scraped paragraphs extend topic coverage.
class WelfareKnowledgeService {
  static Future<void>? _loading;
  static final List<_KnowledgeEntry> _scraped = [];
  static final _reviewed = <_KnowledgeEntry>[
    _KnowledgeEntry(
      'Edhi',
      'Ambulance services',
      'Edhi provides ambulance transport across Pakistan, including land ambulances and air and marine rescue services. Ambulance helpline: 115. Give dispatch the patient location, a nearby landmark and a callback number.',
      'https://www.edhi.org/ambulance',
      'ambulance transport air marine boat rescue helpline contact number 115 emergency fleet hours coverage',
    ),
    _KnowledgeEntry(
      'Edhi',
      'About Edhi and its founders',
      'Abdul Sattar Edhi and Bilquis Edhi built a humanitarian welfare organization serving people without discrimination. Its work includes healthcare, child welfare, shelters, education, disaster relief and ambulance services.',
      'https://www.edhi.org/about-us',
      'founder founded history who sattar bilquis foundation mission services welfare',
    ),
    _KnowledgeEntry(
      'Edhi',
      'Shelters, children and family support',
      'Edhi describes care for abandoned newborns through cradles, support for orphaned children, women, older people and people with disabilities. Contact Edhi for admission, safeguarding and family tracing procedures; the app cannot confirm a shelter place or adoption eligibility.',
      'https://www.edhi.org/about-us',
      'shelter orphan orphanage child children baby babies newborn cradle jhoola old elderly women adoption missing lost family',
    ),
    _KnowledgeEntry(
      'Edhi',
      'Disaster relief and community support',
      'Edhi’s welfare work includes disaster relief, food, clothing, medical support and rescue assistance for people affected by floods and other emergencies. Ask the organization about current relief locations and collection arrangements.',
      'https://www.edhi.org/about-us',
      'flood disaster relief food ration clothes clothing blanket earthquake rescue',
    ),
    _KnowledgeEntry(
      'Chhipa',
      'Chhipa ambulance and emergency contact',
      'Chhipa’s ambulance helpline is 1020. Its official website also lists +92 300 3631020 for WhatsApp contact. Give dispatch your city, exact location, a nearby landmark and the patient’s condition. Confirm coverage and availability directly with Chhipa.',
      'https://www.chhipa.org/services/chhipa-ambulance/',
      'ambulance helpline contact phone number emergency 1020 whatsapp transport rescue hours coverage',
    ),
    _KnowledgeEntry(
      'Chhipa',
      'Chhipa welfare services',
      'Chhipa lists ambulances, free food through Dastarkhwan and kitchens, ration support, an orphanage, newborn and old homes, a women’s shelter, Jhoola, morgue and burial services. Select a service and contact Chhipa for current arrangements.',
      'https://www.chhipa.org/',
      'services food kitchen dastarkhwan ration orphanage orphan shelter women old elderly child newborn jhoola cradle morgue burial graveyard',
    ),
    _KnowledgeEntry(
      'Chhipa',
      'Chhipa head office',
      'Chhipa’s website lists its Karachi office at Plot ZC-5, Sector 8/A, FTC Bridge, Shahrah-e-Faisal, Karachi 74400. The listed UAN is +92 21 111-92-1020. Call before visiting to confirm the correct office for the service you need.',
      'https://www.chhipa.org/',
      'office address location center centre branch karachi contact',
    ),
    _KnowledgeEntry(
      'Chhipa',
      'Official Chhipa donation channels',
      'Chhipa lists online donations, bank transfers, collection, JazzCash, Easypaisa and other payment channels on its official website. Open the official donation page to verify the recipient and current instructions before sending money. Never share a wallet PIN or OTP.',
      'https://www.chhipa.org/',
      'donate donation charity zakat sadqa sadaqah money bank jazzcash easypaisa payment qurbani aqiqah',
    ),
    _KnowledgeEntry(
      'App',
      'Request and track an ambulance in EdhiConnect',
      'Open Home → Emergency Request. Choose the emergency type, place the patient pin on the map, and enter the contact number and description. After submitting, open the request to track the assigned unit and status. The status changes to Arrived five seconds after the unit reaches the destination. Confirm completion after the response is finished.',
      '',
      'app request ambulance dispatch track tracking status arrived arrival how book sos',
    ),
    _KnowledgeEntry(
      'App',
      'Cancellation and request restrictions',
      'Cancel an open request within 60 seconds of submitting it. Driver assignment does not restart the timer. Three cancellations within 24 hours block new requests for 24 hours. Admins can unban the yellow-highlighted account from People. A manual admin ban stays in place until the admin turns it off.',
      '',
      'cancel cancellation cancelled ban banned unban blocked restriction three 3 timer',
    ),
    _KnowledgeEntry(
      'App',
      'Blood Bank requests and donors',
      'Open Blood Bank to register as a blood donor or post an urgent blood need with the blood group, hospital, required units and contact. Ask the hospital to confirm compatibility and screening. A listing does not guarantee a donor or available stock.',
      '',
      'blood donor donate donation plasma platelet platelets group hospital units register',
    ),
    _KnowledgeEntry(
      'App',
      'Record and verify a donation',
      'Open Donations, choose money, ration or clothing, enter the details and submit. Monetary donations currently record an Easypaisa, JazzCash or bank transaction reference for administrator verification. Selecting a payment channel in this app does not charge your wallet. Check official recipient details before transferring money.',
      '',
      'app donate donation payment money easypaisa jazzcash bank receipt reference ration clothing',
    ),
    _KnowledgeEntry(
      'App',
      'Nearby Edhi centers',
      'Open Quick Help → Edhi Centers to search the directory and view locations and contact details. Share your city for a more specific directory search. Call the listed center to confirm hours and availability before travelling.',
      '',
      'nearby nearest center centre station branch office address location find city',
    ),
    _KnowledgeEntry(
      'App',
      'Report a missing person',
      'Open Missing Persons to submit the person’s details, a clear photo, last seen place and time, and a contact number. Update the report when found or reunited. Contact local police when someone is at immediate risk; the app does not automatically search private shelter records.',
      '',
      'missing person lost found report child reunite family photo',
    ),
  ];

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
    'chipa': 'chhipa',
    'chipha': 'chhipa',
    'chippa': 'chhipa',
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
    'چھیپا': 'chhipa',
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
    final lower = message.toLowerCase().trim();
    final tokens = _tokens(lower);
    // Detect distress first, but an informational ambulance FAQ is not an incident.
    final distress =
        RegExp(
          r'not breathing|cannot breathe|can.t breathe|saans nahi|sans nahi|سانس نہیں|heart attack|severe bleeding|heavy bleeding|chest pain|unconscious|behosh|بے\s?ہوش|dying|accident|حادثہ',
        ).hasMatch(lower) ||
        tokens.contains('unconscious') ||
        (tokens.contains('ambulance') &&
            RegExp(r'\b(immediately|now|urgent|jaldi)\b').hasMatch(lower)) ||
        RegExp(r'\bsos\b').hasMatch(lower) ||
        (tokens.contains('emergency') &&
            !tokens.any(
              {
                'contacts',
                'contact',
                'services',
                'number',
                'helpline',
                'guide',
              }.contains,
            ));
    if (distress) {
      return ChatbotReply(
        text: _language(message) == 'ur'
            ? 'فوراً ایدھی 115 یا چھیپا 1020 پر کال کریں۔ مریض کا مقام، قریبی نشان، رابطہ نمبر اور حالت بتائیں۔ خطرناک جگہ سے محفوظ مقام پر جائیں اور ڈسپیچر کی ہدایات پر عمل کریں۔'
            : _language(message) == 'roman'
            ? 'Abhi Edhi 115 ya Chhipa 1020 par call karein. Patient ki exact location, qareebi nishani, contact number aur halat batayein. Jagah khatarnak ho to mehfooz jagah par jayein aur dispatcher ki hidayat par amal karein.'
            : 'Call Edhi 115 or Chhipa 1020 now. Give the patient’s location, nearby landmark, callback number and condition. Move to safety if the scene is unsafe and follow the dispatcher’s instructions.',
        isEmergencyIntent: true,
        quickSuggestions: [
          'How to request an ambulance?',
          'Emergency contacts',
          'First Aid Guide',
        ],
        sourceUrls: [
          'https://www.edhi.org/ambulance',
          'https://www.chhipa.org/services/chhipa-ambulance/',
        ],
      );
    }
    if (hasBloodIntent(message, history: history)) {
      return _bloodReply(message, history: history, donors: donors);
    }
    if (RegExp(
      r'^(hi|hello|hey|salam|assalam.?o.?alaikum|السلام علیکم)[!.\s]*$',
    ).hasMatch(lower)) {
      return const ChatbotReply(
        text:
            'Wa Alaikum Assalam! Ambulance requests, blood donors, donations, welfare services and nearby centers are available here.',
        quickSuggestions: [
          'Edhi ambulance services',
          'Chhipa services',
          'How to donate?',
          'Nearby Edhi centers',
        ],
      );
    }
    if (tokens.any({'cpr', 'burn', 'burns', 'fracture', 'choking'}.contains) ||
        lower.contains('first aid')) {
      return const ChatbotReply(
        text:
            'For an urgent injury or breathing problem, call 115 or 1020 and follow the dispatcher’s instructions. Open Quick Help → First Aid Guide for the app’s first-aid information. I cannot diagnose a condition or prescribe treatment.',
        quickSuggestions: [
          'Emergency contacts',
          'How to request an ambulance?',
        ],
      );
    }
    String? provider;
    if (tokens.contains('chhipa')) {
      provider = 'Chhipa';
    }
    if (tokens.contains('edhi')) {
      provider = provider == null ? 'Edhi' : null;
    }
    final topicTokens = tokens.difference({'edhi', 'chhipa'});
    final followUp =
        topicTokens.length <= 5 &&
        (lower.contains('what about') ||
            lower.contains('and ') ||
            lower.contains('their') ||
            lower.contains('uska') ||
            topicTokens.every(
              {
                'number',
                'contact',
                'phone',
                'address',
                'donation',
                'payment',
                'hours',
                'timing',
                'cost',
                'charges',
                'fees',
              }.contains,
            ));
    if (followUp && history.isNotEmpty) {
      final previous = _tokens(history.last);
      if (provider == null) {
        if (previous.contains('chhipa')) {
          provider = 'Chhipa';
        } else if (previous.contains('edhi')) {
          provider = 'Edhi';
        }
      }
      if (topicTokens.isEmpty ||
          topicTokens.every({'number', 'phone', 'their', 'it'}.contains)) {
        tokens.addAll(previous.difference({'edhi', 'chhipa'}));
      }
    }
    if (tokens.any(
      {
        'fees',
        'fee',
        'charges',
        'price',
        'cost',
        'stock',
        'available',
      }.contains,
    )) {
      return ChatbotReply(
        text:
            'I cannot verify live prices, ambulance availability, blood stock or shelter spaces. Contact ${provider == 'Chhipa'
                ? 'Chhipa on 1020'
                : provider == 'Edhi'
                ? 'Edhi on 115'
                : 'Edhi on 115 or Chhipa on 1020'} and give your city and service. The official site may describe a service without guaranteeing current availability.',
        quickSuggestions: ['Emergency contacts', 'Nearby Edhi centers'],
      );
    }
    if (lower.contains('emergency contacts') ||
        lower.contains('helplines') ||
        (provider == null &&
            tokens.any({'helpline', 'phone', 'number', 'contact'}.contains))) {
      return const ChatbotReply(
        text:
            'Edhi ambulance: 115. Chhipa ambulance: 1020. For Chhipa WhatsApp contact, the official site lists +92 300 3631020. Call dispatch for urgent help rather than waiting for a chat reply.',
        sourceUrls: ['https://www.edhi.org/punjab', 'https://www.chhipa.org/'],
      );
    }
    final terms = tokens.difference({'edhi', 'chhipa', 'their', 'they', 'app'});
    if (terms.isEmpty && provider != null) {
      terms.add('services');
    }
    final ranked = <(_KnowledgeEntry, double)>[];
    for (final entry in [..._reviewed, ..._scraped]) {
      if (provider != null && entry.provider != provider) continue;
      final overlap = terms.intersection(entry.terms);
      if (overlap.isEmpty) continue;
      double score = 0;
      for (final term in overlap) {
        final df = _reviewed.where((e) => e.terms.contains(term)).length;
        score += log(1 + (_reviewed.length + 1) / (df + 1));
        if (entry.titleTerms.contains(term)) score += 2;
        if (entry.keywordTerms.contains(term)) score += 1;
      }
      score *= overlap.length / max(1, terms.length);
      if (_reviewed.contains(entry)) score *= 1.8;
      if (tokens.contains('app') && entry.provider == 'App') score *= 2;
      ranked.add((entry, score));
    }
    ranked.sort((a, b) => b.$2.compareTo(a.$2));
    if (ranked.isEmpty || ranked.first.$2 < 1.2) {
      return const ChatbotReply(
        text:
            'That topic is outside this welfare assistant’s coverage. Available topics include ambulance requests, blood donors, donations, shelters, food support and nearby centers.',
        quickSuggestions: [
          'Edhi services',
          'Chhipa services',
          'Emergency contacts',
        ],
      );
    }
    final match = ranked.first.$1;
    final text = match.text.length > 950
        ? '${match.text.substring(0, 950)}…'
        : match.text;
    return ChatbotReply(
      text: '${match.title}\n\n$text',
      sourceUrls: match.url.isEmpty ? const [] : [match.url],
      quickSuggestions: match.provider == 'App'
          ? match.title.contains('ambulance')
                ? [
                    'Track my ambulance',
                    'Cancellation rules',
                    'Emergency contacts',
                  ]
                : match.title.contains('donation')
                ? ['Donation receipt', 'Donate ration', 'Donate clothes']
                : match.title.contains('Cancellation')
                ? ['How to request an ambulance?', 'Request status']
                : ['Nearby Edhi centers', 'Edhi services', 'Chhipa services']
          : [
              '${match.provider} contact number',
              '${match.provider} donations',
              '${match.provider} services',
            ],
    );
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
    return history.isNotEmpty &&
        _tokens(history.last).any({'blood', 'donor'}.contains) &&
        (_city(message) != null ||
            RegExp(
              r'\b(yes|haan|han|units|unit|donate|register)\b',
            ).hasMatch(message.toLowerCase()));
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
              ? 'Blood Bank → Register as Donor kholein. $label select karein, apna shehar aur contact number dalein, aur availability on karein.'
              : language == 'ur'
              ? 'Blood Bank میں Register as Donor کھولیں۔ $label منتخب کریں، شہر اور رابطہ نمبر درج کریں اور دستیابی فعال کریں۔'
              : 'Open Blood Bank → Register as Donor. Select $label, enter your city and contact number, and turn on availability.'
        : language == 'roman'
        ? 'Blood Bank kholein aur ${group ?? 'required blood group'} ka filter lagayein${city == null ? '' : ', city $city rakhein'}. Listed donors ko contact karein. Urgent Need mein hospital, required units aur contact number ke saath request post karein.'
        : language == 'ur'
        ? 'Blood Bank کھولیں اور ${group ?? 'مطلوبہ بلڈ گروپ'} کا فلٹر لگائیں${city == null ? '' : '، شہر $city منتخب کریں'}۔ درج شدہ عطیہ دہندگان سے رابطہ کریں۔ Urgent Need میں ہسپتال، مطلوبہ یونٹس اور رابطہ نمبر کے ساتھ درخواست درج کریں۔'
        : 'Open Blood Bank and filter by ${group ?? 'the required blood group'}${city == null ? '' : ' and $city'}. Contact listed donors. Post an Urgent Need with the hospital, required units and contact number.';
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
          .take(3)
          .toList();
      if (matches.isNotEmpty) {
        text +=
            '\n\n${language == 'roman'
                ? 'Listed donors'
                : language == 'ur'
                ? 'درج شدہ عطیہ دہندگان'
                : 'Listed donors'}:\n';
        text += matches
            .map(
              (d) =>
                  '• ${d.userName} · ${d.bloodGroup} · ${d.city}${d.userPhone.isEmpty ? '' : ' · ${d.userPhone}'}',
            )
            .join('\n');
      } else {
        text += language == 'roman'
            ? '\n\nIs filter ke liye abhi koi available donor listed nahi. Urgent Need post karein.'
            : language == 'ur'
            ? '\n\nاس فلٹر کے لیے فی الحال کوئی دستیاب عطیہ دہندہ درج نہیں۔ Urgent Need میں درخواست درج کریں۔'
            : '\n\nNo available donor is currently listed for these filters. Post an Urgent Need.';
      }
    }
    return ChatbotReply(
      text: text,
      quickSuggestions: registering
          ? ['Blood donor availability', 'Find ${group ?? 'blood'} donors']
          : [
              'Find ${group ?? 'blood'} donors',
              'Post ${group ?? 'blood'} blood request',
              'Become a blood donor',
            ],
    );
  }

  // Clean up old persisted replies without changing the stored conversation.
  static String displayText(String text) => text
      .replaceAll(RegExp(r'\n\nSource:[^\n]*'), '')
      .replaceAll('The simulated journey changes', 'The request status changes')
      .replaceAll(
        'For actual emergency help, call Edhi 115 or Chhipa 1020.',
        '',
      )
      .trim();
}
