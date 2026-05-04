import 'package:url_launcher/url_launcher.dart';
import '../core/utils/phone_formatter.dart';

class WhatsAppService {
  const WhatsAppService();

  Future<bool> openChat({
    required String? phone,
    required String message,
  }) async {
    final formatted = PhoneFormatter.toWhatsAppNumber(phone);
    if (formatted == null) return false;

    final uri = Uri.parse(
      'https://wa.me/$formatted?text=${Uri.encodeComponent(message)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
