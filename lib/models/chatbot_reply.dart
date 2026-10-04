class ChatbotReply {
  final String text;
  final bool isEmergencyIntent;
  final List<String> quickSuggestions;
  final List<String> sourceUrls;
  const ChatbotReply({
    required this.text,
    this.isEmergencyIntent = false,
    this.quickSuggestions = const [],
    this.sourceUrls = const [],
  });
}
