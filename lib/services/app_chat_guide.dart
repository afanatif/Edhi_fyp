import '../models/chatbot_reply.dart';

/// Only features implemented in the app can become user-facing guidance.
class AppChatGuide {
  static const _home = [
    'Open Emergency Request',
    'Open Blood Bank',
    'Open Donations',
  ];

  static ChatbotReply reply(String message, {List<String> history = const []}) {
    final query = message.toLowerCase();
    final roman = RegExp(
      r'\b(kaise|kahan|mujhe|hai|karna|karein|chahiye|batao|madad|rashan|paise)\b',
    ).hasMatch(query);
    final urdu = RegExp(r'[\u0600-\u06ff]').hasMatch(query);
    String choose(String en, String romanText, String ur) => urdu
        ? ur
        : roman
        ? romanText
        : en;
    ChatbotReply response(
      String heading,
      String body,
      List<String> suggestions,
    ) => ChatbotReply(text: '$heading\n\n$body', quickSuggestions: suggestions);
    bool has(String pattern) => RegExp(pattern).hasMatch(query);

    if (has(
      r'^(hi|hello|hey|salam|assalam.?o.?alaikum|السلام علیکم)[!.\s]*$',
    )) {
      return ChatbotReply(
        text: choose(
          'Hello! You can request an ambulance, find blood donors, make a donation, or report a missing person here. Choose a shortcut below to open a service.',
          'Assalam o Alaikum! Yahan ambulance request, blood donors, donations aur missing person report ki sahulat hai. Neeche shortcut se service kholein.',
          'السلام علیکم! یہاں ایمبولینس کی درخواست، خون کے عطیہ دہندگان، عطیات اور گمشدہ فرد کی رپورٹ کی سہولت ہے۔ نیچے موجود بٹن سے متعلقہ سروس کھولیں۔',
        ),
        quickSuggestions: _home,
      );
    }
    if (has(
          r'not breathing|cannot breathe|can.t breathe|saans nahi|sans nahi|سانس نہیں|heart attack|severe bleeding|heavy bleeding|chest pain|unconscious|behosh|بے\s?ہوش|dying|accident|حادثہ|\bsos\b',
        ) ||
        (has(r'ambulance|ایمبولینس') &&
            has(r'\b(now|immediately|urgent|jaldi)\b'))) {
      return ChatbotReply(
        text: choose(
          'Open Home → Emergency Request now. Choose the emergency type, place the pin at the patient’s location, and enter a callback number and the patient’s condition. Submit once, then open your request to track its status and assigned ambulance. For immediate phone assistance, use Home → Quick Help → SOS Contacts or call 115. This chat does not submit a request for you.',
          'Abhi Home → Emergency Request kholein. Emergency type select karein, patient ki location par pin lagayein aur contact number aur halat likhein. Ek dafa submit karein, phir request khol kar status aur ambulance track karein. Fori phone rabtay ke liye Quick Help → SOS Contacts kholein ya 115 call karein. Chat khud request submit nahi karta.',
          'ابھی Home → Emergency Request کھولیں۔ ایمرجنسی کی قسم، مریض کا مقام، رابطہ نمبر اور حالت درج کریں۔ ایک بار جمع کریں، پھر درخواست کھول کر اسٹیٹس اور ایمبولینس دیکھیں۔ فوری فون رابطے کے لیے Quick Help → SOS Contacts کھولیں یا 115 پر کال کریں۔ چیٹ خود درخواست جمع نہیں کرتی۔',
        ),
        isEmergencyIntent: true,
        quickSuggestions: [
          'Open Emergency Request',
          'Open SOS Contacts',
          'Open First Aid',
        ],
      );
    }
    if (has(r'cancel|ban\b|banned|unban|blocked|restriction|منسوخ|پابندی')) {
      return response(
        'Cancellation and account restrictions',
        choose(
          'Open your request and use Cancel within 60 seconds of submission. Driver assignment does not restart that timer. Three cancellations within 24 hours block new requests for 24 hours. Admins can review and unban the highlighted account in People. A manual admin ban lasts until an admin removes it.',
          'Request kholein aur submit karne ke 60 seconds ke andar Cancel karein. Driver assign hone se timer restart nahi hota. 24 ghanton mein 3 cancellations se nayi requests 24 ghantay block hoti hain. Admin People mein highlighted account review karke unban kar sakta hai. Manual ban admin hatata hai.',
          'درخواست جمع کرنے کے 60 سیکنڈ کے اندر Cancel استعمال کریں۔ ڈرائیور ملنے سے وقت دوبارہ شروع نہیں ہوتا۔ 24 گھنٹوں میں 3 منسوخیوں پر نئی درخواستیں 24 گھنٹے بند ہوتی ہیں۔ ایڈمن People میں نشان زد اکاؤنٹ کی پابندی ہٹا سکتا ہے۔',
        ),
        ['Open Home', 'Request status', 'Open Profile'],
      );
    }
    // A short follow-up inherits the latest service, without inventing live status.
    final followUp = has(
      r'^(where|how|status|what next|and now|what about their number|their number|what about it|kahan|kaise|aur|charges|cost|price|fees|kitna)[?.!\s]*$',
    );
    final context = followUp && history.isNotEmpty
        ? '${history.last.toLowerCase()} $query'
        : query;
    bool topic(String pattern) => RegExp(pattern).hasMatch(context);
    if (topic(r'cpr|burn|fracture|choking|first.?aid|ابتدائی طبی')) {
      return response(
        'First aid in the app',
        choose(
          'Open Home → Quick Help → First Aid Tips and choose the relevant topic. For an urgent incident, submit an Emergency Request with the patient’s location and condition. Use SOS Contacts for immediate phone assistance.',
          'Home → Quick Help → First Aid Tips mein relevant topic kholein. Urgent incident ke liye patient ki location aur halat ke saath Emergency Request submit karein. Phone rabtay ke liye SOS Contacts kholein.',
          'Home → Quick Help → First Aid Tips میں متعلقہ موضوع کھولیں۔ فوری ضرورت میں مریض کے مقام اور حالت کے ساتھ Emergency Request جمع کریں۔ فون رابطے کے لیے SOS Contacts کھولیں۔',
        ),
        ['Open First Aid', 'Open Emergency Request', 'Open SOS Contacts'],
      );
    }
    if (topic(
      r'ambulance|ambulanse|track|arrival|arrived|request status|dispatch|ایمبولینس|ٹریک|درخواست',
    )) {
      return response(
        'Request and track your ambulance',
        choose(
          'Open Home → Emergency Request. Select the emergency type, place the patient pin accurately, add a contact number and describe the situation, then submit. Open the request card on Home to see its current status, assigned ambulance and map. Arrived appears five seconds after the ambulance reaches the destination; confirm completion when the response is finished. If no unit is assigned yet, keep checking that request rather than creating duplicates.',
          'Home → Emergency Request kholein. Emergency type, patient ka sahi map pin, contact number aur details dal kar submit karein. Home par request card kholein: status, assigned ambulance aur map yahin milega. Destination par pohanchne ke 5 seconds baad Arrived hota hai. Response mukammal hone par completion confirm karein. Assignment ka intezar ho to isi request ko check karein.',
          'Home → Emergency Request کھولیں۔ ایمرجنسی کی قسم، درست مقام، رابطہ نمبر اور تفصیل درج کرکے جمع کریں۔ Home پر درخواست کا کارڈ کھول کر اسٹیٹس، ایمبولینس اور نقشہ دیکھیں۔ منزل پر پہنچنے کے 5 سیکنڈ بعد Arrived آتا ہے۔ کارروائی مکمل ہونے پر تکمیل کی تصدیق کریں۔',
        ),
        ['Open Emergency Request', 'Open Home', 'Cancellation rules'],
      );
    }
    if (topic(
      r'donat|payment|receipt|money|ration|rashan|food|clothes|clothing|zakat|sadqa|sadaq|jazzcash|easypaisa|bank|عطیہ|راشن|زکو|پیس',
    )) {
      return response(
        'Make and review a donation',
        choose(
          'Open Donate → Donate Now. Choose money, ration or clothing and complete the matching details. For money, select the payment method and provide the transaction reference for admin verification; choosing a method does not charge your account automatically. Submit, then open My History to check the recorded donation and verification status. For ration or clothes, include the items, quantity and pickup details requested by the form.',
          'Donate → Donate Now kholein. Money, ration ya clothing select karke details bharein. Money ke liye payment method aur transaction reference dein; sirf method select karne se payment nahi hoti. Submit ke baad My History mein record aur verification status dekhein. Ration ya clothes ke items, quantity aur pickup details form mein dalein.',
          'Donate → Donate Now کھولیں۔ رقم، راشن یا کپڑے منتخب کرکے تفصیلات درج کریں۔ رقم کے لیے ادائیگی کا طریقہ اور ٹرانزیکشن حوالہ دیں؛ طریقہ منتخب کرنے سے خودکار ادائیگی نہیں ہوتی۔ جمع کرنے کے بعد My History میں ریکارڈ اور تصدیق دیکھیں۔',
        ),
        ['Open Donations', 'Donation receipt', 'Donate ration'],
      );
    }
    if (topic(r'missing|lost|found|reunit|گمشدہ|لاپتہ')) {
      return response(
        'Report or find a missing person',
        choose(
          'Open Home → Quick Help → Missing Persons. Browse existing reports or add a report with the person’s name, description, clear photo, last-seen place and time, and contact number. Check the report for updates and mark it found when the person is reunited. Only submit details you can verify.',
          'Home → Quick Help → Missing Persons kholein. Reports dekhein ya naam, description, clear photo, last-seen location aur time, aur contact number ke saath report add karein. Person milne par report found mark karein.',
          'Home → Quick Help → Missing Persons کھولیں۔ موجودہ رپورٹس دیکھیں یا نام، تفصیل، واضح تصویر، آخری مقام اور وقت، اور رابطہ نمبر کے ساتھ رپورٹ درج کریں۔ فرد ملنے پر رپورٹ Found کریں۔',
        ),
        ['Open Missing Persons', 'Open Home'],
      );
    }
    if (topic(
      r'center|centre|nearest|nearby|office|address|location|markaz|مرکز|قریب',
    )) {
      return response(
        'Find a nearby center',
        choose(
          'Open Home → Quick Help → the Centers directory. Search your city, choose a listed center, and view its address and contact details. Use the location shown for directions and the listed contact to check opening hours. The chat does not know your current GPS location.',
          'Home → Quick Help mein Centers directory kholein. Apna shehar search karein aur listed center ka address aur contact dekhein. Directions ke liye listed location use karein. Chat aapki current GPS location nahi janta.',
          'Home → Quick Help میں Centers directory کھولیں۔ شہر تلاش کرکے مرکز کا پتہ اور رابطہ دیکھیں۔ راستے کے لیے درج شدہ مقام استعمال کریں۔ چیٹ کو آپ کا موجودہ GPS مقام معلوم نہیں۔',
        ),
        ['Open Centers', 'Open SOS Contacts'],
      );
    }
    if (topic(r'contact|helpline|phone number|number|rabta|رابطہ')) {
      return response(
        'Contact options',
        choose(
          'Open Home → Quick Help → SOS Contacts to choose and call a listed emergency number. For a center’s address or phone, open the Centers directory. For a donor’s number, use Blood Bank and the donor’s contact details.',
          'Home → Quick Help → SOS Contacts mein listed emergency number par call karein. Center ke rabtay ke liye Centers aur donor ke liye Blood Bank kholein.',
          'Home → Quick Help → SOS Contacts میں درج نمبر منتخب کریں۔ مرکز کے رابطے کے لیے Centers اور عطیہ دہندہ کے لیے Blood Bank کھولیں۔',
        ),
        ['Open SOS Contacts', 'Open Centers', 'Open Blood Bank'],
      );
    }
    if (topic(
      r'login|sign.?in|register|account|password|cnic|profile|لاگ|اکاؤنٹ',
    )) {
      return response(
        'Your account and profile',
        choose(
          'Sign in using your registered CNIC or Pakistani mobile number and password. To create an account, choose Citizen or Driver and use a unique CNIC and phone number. If the form says they are already registered, sign in with the existing account. Open Profile to review your account and edit the details available there.',
          'Registered CNIC ya Pakistani phone number aur password se sign in karein. Naya account banate waqt Citizen ya Driver select karein aur unique CNIC aur phone dein. Already registered ho to existing account se sign in karein. Account details ke liye Profile kholein.',
          'اپنے رجسٹرڈ شناختی کارڈ یا پاکستانی موبائل نمبر اور پاس ورڈ سے سائن اِن کریں۔ نئے اکاؤنٹ کے لیے Citizen یا Driver منتخب کریں اور منفرد شناختی کارڈ اور فون دیں۔ پہلے سے رجسٹرڈ ہونے پر موجودہ اکاؤنٹ سے سائن اِن کریں۔ تفصیلات کے لیے Profile کھولیں۔',
        ),
        ['Open Profile', 'Open Home'],
      );
    }
    if (topic(r'price|cost|fee|charges|available|availability|kitna|stock')) {
      return response(
        'Check details inside the app',
        choose(
          'For ambulance availability and assignment, open your request on Home. For available blood donors, use the group and city filters in Blood Bank. For donation amounts and verification, open Donations. I cannot confirm an unlisted price or availability.',
          'Ambulance assignment ke liye Home par apni request kholein. Available donors ke liye Blood Bank mein group aur city filters use karein. Donation amount aur verification Donations mein dekhein. Unlisted price ya availability confirm nahi ki ja sakti.',
          'ایمبولینس کی دستیابی کے لیے Home پر اپنی درخواست دیکھیں۔ عطیہ دہندگان کے لیے Blood Bank میں گروپ اور شہر کے فلٹر استعمال کریں۔ عطیات کی رقم اور تصدیق Donations میں دیکھیں۔ غیر درج قیمت یا دستیابی کی تصدیق نہیں کی جا سکتی۔',
        ),
        _home,
      );
    }
    return ChatbotReply(
      text: choose(
        'I can guide you through this app: Emergency Request, ambulance tracking, Blood Bank, Donations, Missing Persons, Centers, First Aid, and Profile. Choose a shortcut below to open the feature you need.',
        'Main is app ke Emergency Request, ambulance tracking, Blood Bank, Donations, Missing Persons, Centers, First Aid aur Profile mein guide kar sakta hoon. Neeche shortcut se feature kholein.',
        'میں اس ایپ کی Emergency Request، ایمبولینس ٹریکنگ، Blood Bank، Donations، Missing Persons، Centers، First Aid اور Profile میں رہنمائی کر سکتا ہوں۔ نیچے متعلقہ بٹن منتخب کریں۔',
      ),
      quickSuggestions: _home,
    );
  }
}
