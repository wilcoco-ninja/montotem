import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration centralisée des services externes MONTOTEM
/// (Supabase + KKiaPay). Plus aucun backend Django.
class ApiConfig {
  ApiConfig._();

  // KKiaPay
  static String get kkiapayPublicKey => dotenv.env['KKIAPAY_PUBLIC_KEY'] ?? '';

  static bool get isKkiapaySandbox {
    final value = dotenv.env['KKIAPAY_SANDBOX']?.toLowerCase();
    if (value == null) return true;
    return value == 'true' || value == '1' || value == 'yes';
  }

  // Supabase
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ??
      dotenv.env['SUPABASE_ANON_KEY'] ??
      '';

  static bool get isProduction => kReleaseMode && !isKkiapaySandbox;

  static bool get isDebug => kDebugMode;

  /// Vérifie que les variables critiques sont présentes.
  static bool validateConfig({bool requirePayment = false}) {
    final missing = <String>[];

    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabasePublishableKey.isEmpty) {
      missing.add('SUPABASE_PUBLISHABLE_KEY (ou SUPABASE_ANON_KEY)');
    }
    if (requirePayment && kkiapayPublicKey.isEmpty) {
      missing.add('KKIAPAY_PUBLIC_KEY');
    }

    if (missing.isNotEmpty) {
      debugPrint('⚠️ Configuration manquante : ${missing.join(', ')}');
      return false;
    }
    return true;
  }

  static Map<String, dynamic> getDebugInfo() => {
    'isProduction': isProduction,
    'isDebug': isDebug,
    'isKkiapaySandbox': isKkiapaySandbox,
    'kkiapayConfigured': kkiapayPublicKey.isNotEmpty,
    'supabaseConfigured': supabaseUrl.isNotEmpty,
  };

  static void logConfig() {
    if (!kDebugMode) return;
    debugPrint('╔══════════════════════════════════════════╗');
    debugPrint('║         MONTOTEM Configuration           ║');
    debugPrint('╠══════════════════════════════════════════╣');
    debugPrint('║ Environment: ${isProduction ? 'PRODUCTION' : 'DEVELOPMENT'}');
    debugPrint('║ KKiaPay: ${isKkiapaySandbox ? 'Sandbox' : 'Production'}');
    debugPrint('║ Supabase: ${supabaseUrl.isNotEmpty ? 'OK' : 'Missing'}');
    debugPrint('╚══════════════════════════════════════════╝');
  }
}
