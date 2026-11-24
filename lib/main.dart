import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ✅ corrigé
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/accessibility/accessibility_controller.dart';
import 'core/constants/app_constants.dart';
import 'core/flavor/app_flavor.dart'; // ✅ ajouté
import 'core/notifications/push_service.dart';
import 'core/offline/outbox_service.dart';
import 'core/power/power_mode_controller.dart';
import 'core/router/app_router.dart';
import 'core/storage/local_cache.dart';
import 'core/storage/session_securisee.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/sos_button.dart';
import 'core/widgets/survival_shell.dart';
import 'features/emergency/data/emergency_numbers_repository.dart';
import 'features/emergency/data/emergency_places_repository.dart';
import 'features/requests/data/mission_service.dart';
import 'features/rides/data/ride_service.dart';

/// ✅ Nouveau : point d'entrée commun aux 3 apps (client / driver / pro).
/// Fixe le flavor AVANT tout accès à AppRouter.router.
Future<void> bootstrap(AppFlavor flavor) async {
  AppFlavor.current = flavor;
  await runMonTotemApp();
}

/// Ancien `main()` renommé pour éviter le conflit avec les fichiers
/// `main_client.dart` / `main_driver.dart` / `main_pro.dart`.
Future<void> runMonTotemApp() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      ErrorWidget.builder = (FlutterErrorDetails details) {
        if (kReleaseMode) return const SizedBox.shrink();
        return _InlineErrorBox(details: details);
      };

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        developer.log(
          'FlutterError: ${details.exceptionAsString()}',
          error: details.exception,
          stackTrace: details.stack,
          name: 'Main',
        );
      };

      String? startupError;
      bool envLoaded = false;

      try {
        await dotenv.load(fileName: 'assets/.env');
        debugPrint('✅ .env chargé depuis assets/');
        envLoaded = true;
      } catch (e) {
        debugPrint('⚠️ Échec assets/.env : $e');
      }

      if (!envLoaded && kIsWeb) {
        try {
          await dotenv.load(fileName: '.env');
          debugPrint('✅ .env chargé depuis web/');
          envLoaded = true;
        } catch (e) {
          debugPrint('⚠️ Échec web/.env : $e');
        }
      }

      if (!envLoaded) {
        startupError =
            'Impossible de charger le fichier .env.\n\n'
            'Assurez-vous que :\n'
            '1. Le fichier existe à assets/.env\n'
            '2. Il est déclaré dans pubspec.yaml sous "assets:"\n'
            '3. Il contient SUPABASE_URL et SUPABASE_ANON_KEY';
      }

      if (startupError == null) {
        try {
          final url = dotenv.env['SUPABASE_URL'];
          final key =
              dotenv.env['SUPABASE_ANON_KEY'] ??
              dotenv.env['SUPABASE_PUBLISHABLE_KEY'];

          if (url == null || url.isEmpty || key == null || key.isEmpty) {
            startupError =
                'SUPABASE_URL ou SUPABASE_ANON_KEY manquant dans assets/.env.';
          } else {
            await Supabase.initialize(
              url: url,
              publishableKey: key,
              authOptions: const FlutterAuthClientOptions(
                localStorage: SessionSecuriseeLecture(),
                authFlowType: AuthFlowType.pkce,
              ),
            );
            debugPrint('✅ Supabase initialisé : $url');
          }
        } catch (e, stackTrace) {
          developer.log(
            'Erreur initialisation Supabase',
            error: e,
            stackTrace: stackTrace,
            name: 'Main',
          );
          startupError = 'Impossible d\'initialiser Supabase : $e';
        }
      }

      if (startupError == null) {
        try {
          await EmergencyNumbersRepository.instance.init();
          unawaited(EmergencyPlacesRepository.instance.charger());
        } catch (e, stackTrace) {
          developer.log(
            'Erreur chargement données urgence',
            error: e,
            stackTrace: stackTrace,
            name: 'Main',
          );
        }
      }

      if (startupError == null) {
        try {
          await PushService.instance.init();
        } catch (e, stackTrace) {
          developer.log(
            'Erreur initialisation PushService',
            error: e,
            stackTrace: stackTrace,
            name: 'Main',
          );
        }
      }

      if (startupError == null) {
        try {
          await LocalCache.instance.init();
          await OutboxService.instance.init();
          OutboxService.instance
            ..enregistrerHandler('create_ride', RideService().rejouerCreation)
            ..enregistrerHandler(
              'create_mission',
              MissionService().rejouerCreation,
            );
          OutboxService.instance.demarrer();
        } catch (e, stackTrace) {
          developer.log(
            'Erreur initialisation stockage local / outbox',
            error: e,
            stackTrace: stackTrace,
            name: 'Main',
          );
        }
      }

      runApp(
        startupError != null
            ? _StartupErrorApp(message: startupError)
            : MultiProvider(
                providers: [
                  ChangeNotifierProvider(
                    create: (_) => AccessibilityController()..load(),
                  ),
                  ChangeNotifierProvider(
                    create: (_) => PowerModeController()..demarrer(),
                  ),
                ],
                child: const MonTotemApp(),
              ),
      );
    },
    (error, stackTrace) {
      developer.log(
        'Unhandled async error in runZonedGuarded',
        error: error,
        stackTrace: stackTrace,
        name: 'Main',
      );
    },
  );
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class MonTotemApp extends StatelessWidget {
  const MonTotemApp({super.key});

  static const double _maxContentWidth = 1280;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final power = context.watch<PowerModeController>();
        final router = AppRouter.router;

        final Widget routed = child ?? const SizedBox.shrink();

        return MediaQuery(
          data: media.copyWith(
            disableAnimations: media.disableAnimations || power.ecoActive,
          ),
          child: SosOverlay(
            routerListenable: router.routerDelegate,
            currentPath: () =>
                router.routerDelegate.currentConfiguration.uri.path,
            onSos: () => router.push('/sos'),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: SurvivalShell(
                  onOpenKit: () => router.push('/survie'),
                  child: routed,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFF3F3),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Color(0xFFE53935),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Erreur au démarrage',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineErrorBox extends StatelessWidget {
  const _InlineErrorBox({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFFFF3F3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFE53935), size: 18),
              SizedBox(width: 6),
              Text(
                'Erreur d\'affichage',
                style: TextStyle(
                  color: Color(0xFFE53935),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            details.exceptionAsString(),
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
