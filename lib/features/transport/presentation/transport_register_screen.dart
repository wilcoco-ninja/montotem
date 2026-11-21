
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/power/power_mode_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/totem_icons.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/quick_auth_service.dart';
import '../../auth/presentation/widgets/photo_picker_field.dart';
import '../../onboarding/presentation/widgets/position_picker_screen.dart';

/// INSCRIPTION CONDUCTEUR Ã¢â‚¬â€ ZÃƒÂ©midjan (moto-taxi) et Tricycle Kloboto (fret).
///
/// Univers Ã‚Â« COCKPIT Ã‚Â» : asphalte noir, jaune safran (ou vert palme pour
/// Kloboto), boutons biseautÃƒÂ©s comme un panneau routier, et une ROUTE qui
/// sert de barre de progression : le vÃƒÂ©hicule du conducteur roule le long
/// des pointillÃƒÂ©s ÃƒÂ  chaque ÃƒÂ©tape.
///
/// Volontairement ÃƒÂ  l'opposÃƒÂ© de l'inscription des dÃƒÂ©panneurs (en-tÃƒÂªte bleu
/// dÃƒÂ©gradÃƒÂ© + carte blanche arrondie) : un conducteur ne doit jamais avoir
/// l'impression de remplir le mÃƒÂªme formulaire qu'un garagiste.
///
/// Ce que fait vraiment cet ÃƒÂ©cran (mÃƒÂªme chemin serveur que l'onboarding
/// existant, aucune modification SQL) :
///   1. envoie la photo de profil et la piÃƒÂ¨ce d'identitÃƒÂ© ;
///   2. appelle `register_profile` (rÃƒÂ´le prestataire, mÃƒÂ©tier Ã‚Â« ZÃƒÂ©midjan Ã‚Â»
///      ou Ã‚Â« Tricycle Fret Ã‚Â») ;
///   3. redirige vers la vÃƒÂ©rification d'identitÃƒÂ© `/provider/identity`.
///
/// Robustesse terrain :
///   - le brouillon (type d'engin, nom, ÃƒÂ©tape) est gardÃƒÂ© sur le tÃƒÂ©lÃƒÂ©phone Ãƒ
///     chaque frappe : batterie ÃƒÂ  plat ou rÃƒÂ©seau coupÃƒÂ© = rien n'est perdu ;
///   - les photos dÃƒÂ©jÃƒÂ  envoyÃƒÂ©es ne sont jamais renvoyÃƒÂ©es lors d'un nouvel
///     essai (ÃƒÂ©conomie de donnÃƒÂ©es) ;
///   - aucune animation si le mode ÃƒÂ©co ou l'accessibilitÃƒÂ© les coupe.
class TransportRegisterScreen extends StatefulWidget {
  const TransportRegisterScreen({super.key});

  @override
  State<TransportRegisterScreen> createState() =>
      _TransportRegisterScreenState();
}

enum _Engin {
  zemidjan('ZÃƒÂ©midjan'),
  kloboto('Tricycle Fret');

  const _Engin(this.metier);

  /// Valeur attendue par le serveur (identique ÃƒÂ  l'onboarding existant).
  final String metier;
}

class _TransportRegisterScreenState extends State<TransportRegisterScreen> {
  static const String _cleBrouillon = 'totem_brouillon_conducteur';
  static const int _nbEtapes = 4;
  static const List<String> _titres = ['Engin', 'IdentitÃƒÂ©', 'Papiers', 'Zone'];

  final _auth = AuthService();
  final _quick = QuickAuthService();
  final _formIdentite = GlobalKey<FormState>();

  int _etape = 0;
  _Engin _engin = _Engin.zemidjan;
  bool _enginChoisi = false;
  bool _envoi = false;

  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _nomAffiche = TextEditingController();
  final _ifu = TextEditingController();

  Uint8List? _photoProfil;
  Uint8List? _photoCni;
  String? _profilUrl;
  String? _cniUrl;
  bool _photosSignalees = false;

  double? _lat;
  double? _lng;

  String _telephone = '';

  ThemeData get _theme => AppTheme.darkTheme;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentSession?.user;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register/quick?role=provider');
      });
    } else {
      _telephone = user.phone ?? user.email ?? '';
    }
    for (final c in [_prenom, _nom, _nomAffiche, _ifu]) {
      c.addListener(_sauverBrouillon);
    }
    _chargerBrouillon();
  }

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _nomAffiche, _ifu]) {
      c.dispose();
    }
    super.dispose();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Brouillon local (survit ÃƒÂ  une extinction du tÃƒÂ©lÃƒÂ©phone) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _chargerBrouillon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brut = prefs.getString(_cleBrouillon);
      if (brut == null) return;
      final j = jsonDecode(brut) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _enginChoisi = j['engin_choisi'] == true;
        _engin = j['engin'] == 'kloboto' ? _Engin.kloboto : _Engin.zemidjan;
        _prenom.text = '${j['prenom'] ?? ''}';
        _nom.text = '${j['nom'] ?? ''}';
        _nomAffiche.text = '${j['nom_affiche'] ?? ''}';
        _ifu.text = '${j['ifu'] ?? ''}';
        final e = (j['etape'] as num?)?.toInt() ?? 0;
        _etape = e.clamp(0, _nbEtapes - 1);
        // Les photos ne sont pas gardÃƒÂ©es : on ne reste pas sur Ã‚Â« Zone Ã‚Â»
        // sans pouvoir les redonner.
        if (_etape > 2) _etape = 2;
        _lat = (j['lat'] as num?)?.toDouble();
        _lng = (j['lng'] as num?)?.toDouble();
      });
    } catch (_) {
      // Brouillon illisible : on repart de zÃƒÂ©ro, sans bruit.
    }
  }

  Future<void> _sauverBrouillon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cleBrouillon,
        jsonEncode({
          'engin': _engin == _Engin.kloboto ? 'kloboto' : 'zemidjan',
          'engin_choisi': _enginChoisi,
          'prenom': _prenom.text,
          'nom': _nom.text,
          'nom_affiche': _nomAffiche.text,
          'ifu': _ifu.text,
          'etape': _etape,
          'lat': _lat,
          'lng': _lng,
        }),
      );
    } catch (_) {}
  }

  Future<void> _effacerBrouillon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cleBrouillon);
    } catch (_) {}
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Navigation entre ÃƒÂ©tapes Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 6)),
      );

  String? _requis(String? v) =>
      (v == null || v.trim().length < 2) ? 'Requis' : null;

  bool _valider() {
    switch (_etape) {
      case 0:
        if (!_enginChoisi) {
          _msg('Touchez votre engin : ZÃƒÂ©midjan ou Kloboto.');
          return false;
        }
        return true;
      case 1:
        return _formIdentite.currentState?.validate() ?? false;
      case 2:
        if (_photoProfil == null || _photoCni == null) {
          setState(() => _photosSignalees = true);
          _msg('Photo de profil et piÃƒÂ¨ce d\'identitÃƒÂ© obligatoires.');
          return false;
        }
        return true;
      default:
        if (_lat == null || _lng == null) {
          _msg('Placez votre zone de travail sur la carte.');
          return false;
        }
        return true;
    }
  }

  void _suivant() {
    FocusScope.of(context).unfocus();
    if (!_valider()) return;
    if (_etape < _nbEtapes - 1) {
      HapticFeedback.selectionClick();
      setState(() => _etape++);
      _sauverBrouillon();
    } else {
      _soumettre();
    }
  }

  void _retour() {
    if (_etape > 0) {
      setState(() => _etape--);
      _sauverBrouillon();
    } else {
      context.go('/register/provider');
    }
  }

  Future<void> _choisirPosition() async {
    final actuelle =
        (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => PositionPickerScreen(positionInitiale: actuelle),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _lat = r.latitude;
      _lng = r.longitude;
    });
    _sauverBrouillon();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Envoi Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _soumettre() async {
    setState(() => _envoi = true);
    try {
      _profilUrl ??= await _auth.uploaderDocument(
        _photoProfil!,
        'profil.jpg',
        kind: UploadKind.avatar,
        folder: 'providers',
      );
      _cniUrl ??= await _auth.uploaderDocument(
        _photoCni!,
        'cni.jpg',
        kind: UploadKind.identity,
        folder: 'providers',
      );

      final affiche = _nomAffiche.text.trim();
      await _quick.registerProvider(
        firstName: _prenom.text,
        lastName: _nom.text,
        businessName: affiche.isNotEmpty
            ? affiche
            : '${_prenom.text.trim()} ${_nom.text.trim()}'.trim(),
        metier: _engin.metier,
        ville: '',
        ifu: _ifu.text,
        photoProfilUrl: _profilUrl!,
        photoCniUrl: _cniUrl!,
        latitude: _lat!,
        longitude: _lng!,
      );

      await _verifierTypeConducteur();
      await _effacerBrouillon();
      if (!mounted) return;
      context.go('/provider/identity');
    } on UploadException catch (e) {
      if (mounted) _msg(e.message);
    } on QuickAuthException catch (e) {
      if (mounted) _msg(e.message);
    } catch (_) {
      if (!mounted) return;
      final horsLigne =
          Provider.of<PowerModeController>(context, listen: false).horsLigne;
      _msg(horsLigne
          ? 'Pas de rÃƒÂ©seau. Votre dossier est gardÃƒÂ© sur ce tÃƒÂ©lÃƒÂ©phone : '
              'rÃƒÂ©essayez dÃƒÂ¨s que le rÃƒÂ©seau revient.'
          : 'Erreur rÃƒÂ©seau. RÃƒÂ©essayez dans un instant.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Filet de sÃƒÂ©curitÃƒÂ© : les courses sont proposÃƒÂ©es d'aprÃƒÂ¨s
  /// `providers.provider_kind`. Si le serveur ne l'a pas dÃƒÂ©duit du mÃƒÂ©tier,
  /// on le renseigne (ÃƒÂ©chec silencieux : l'administrateur peut le corriger).
  Future<void> _verifierTypeConducteur() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final code = _engin == _Engin.kloboto ? 'tricycle_fret' : 'zemidjan';
      final row = await sb
          .from('providers')
          .select('provider_kind')
          .eq('id', uid)
          .maybeSingle();
      if (row != null && row['provider_kind'] != code) {
        await sb
            .from('providers')
            .update({'provider_kind': code}).eq('id', uid);
      }
    } catch (_) {}
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Interface Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    final dureeAnim = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);

    return Theme(
      data: _theme,
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !_envoi) _retour();
          },
          child: Scaffold(
            // Ã¢â€ Â corrigÃƒÂ© : skin.bg Ã¢â€ â€™ scaffoldBackgroundColor du thÃƒÂ¨me courant
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: SafeArea(
              child: AbsorbPointer(
                absorbing: _envoi,
                child: Column(
                  children: [
                    _EnTete(
                      etape: _etape,
                      nbEtapes: _nbEtapes,
                      titre: _titres[_etape],
                      engin: _engin,
                      onBack: _retour,
                    ),
                    _RouteProgress(
                      progression: _etape / (_nbEtapes - 1),
                      engin: _engin,
                      couleur: scheme.primary,
                      duree: dureeAnim,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                            child: AnimatedSwitcher(
                              duration: dureeAnim,
                              child: KeyedSubtree(
                                key: ValueKey(_etape),
                                child: switch (_etape) {
                                  0 => _etapeEngin(scheme),
                                  1 => _etapeIdentite(),
                                  2 => _etapePapiers(),
                                  _ => _etapeZone(scheme),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _envoi ? null : _suivant,
                            icon: _envoi
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: scheme.onPrimary,
                                    ),
                                  )
                                : Icon(_etape < _nbEtapes - 1
                                    ? Icons.arrow_forward_rounded
                                    : Icons.flag_rounded),
                            label: Text(
                              _etape < _nbEtapes - 1
                                  ? 'CONTINUER'
                                  : 'ENVOYER MON DOSSIER',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _titreEtape(String titre, String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              texte,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  // Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°tape 1 : l'engin Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _etapeEngin(ColorScheme scheme) {
    Widget tuile({
      required _Engin e,
      required TotemGlyph glyphe,
      required String titre,
      required String sous,
      required Color couleur,
    }) {
      final choisi = _enginChoisi && _engin == e;
      return Expanded(
        child: Semantics(
          button: true,
          selected: choisi,
          label: '$titre. $sous',
          excludeSemantics: true,
          child: Material(
            color: choisi ? couleur.withValues(alpha: 0.16) : scheme.surface,
            shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: choisi ? couleur : scheme.outline,
                width: choisi ? 3 : 1.4,
              ),
            ),
            child: InkWell(
              customBorder: BeveledRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _engin = e;
                  _enginChoisi = true;
                });
                _sauverBrouillon();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 22, 10, 18),
                child: Column(
                  children: [
                    TotemIcon(
                      glyphe,
                      size: 84,
                      color: scheme.onSurface,
                      accent: couleur,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      titre,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sous,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Icon(
                      choisi
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: choisi ? couleur : scheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreEtape('Quel est votre engin ?',
            'Touchez le vÃƒÂ´tre. Vous recevrez les courses qui lui correspondent.'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tuile(
                e: _Engin.zemidjan,
                glyphe: TotemGlyph.zemidjan,
                titre: 'ZÃƒÂ©midjan',
                sous: 'Moto-taxi\nPassagers',
                couleur: AppColors.brandYellow,
              ),
              const SizedBox(width: 12),
              tuile(
                e: _Engin.kloboto,
                glyphe: TotemGlyph.kloboto,
                titre: 'Kloboto',
                sous: 'Tricycle fret\nMarchandises',
                couleur: AppColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Astuce(
          icone: Icons.payments_rounded,
          texte: 'Course payÃƒÂ©e en Mobile Money : aucune commission. '
              'Course payÃƒÂ©e en espÃƒÂ¨ces : une commission est prÃƒÂ©levÃƒÂ©e sur '
              'votre portefeuille MonTotem.',
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°tape 2 : identitÃƒÂ© Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _etapeIdentite() {
    return Form(
      key: _formIdentite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreEtape('Qui conduit ?',
              'Comme sur votre piÃƒÂ¨ce d\'identitÃƒÂ©. Les clients verront votre prÃƒÂ©nom.'),
          TextFormField(
            controller: _prenom,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            decoration: const InputDecoration(
              labelText: 'PrÃƒÂ©nom',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: _requis,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nom,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            decoration: const InputDecoration(
              labelText: 'Nom',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: _requis,
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: _telephone,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'NumÃƒÂ©ro vÃƒÂ©rifiÃƒÂ© par SMS',
              prefixIcon: Icon(Icons.verified_rounded),
              suffixIcon: Icon(Icons.lock_outline, size: 18),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nomAffiche,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Surnom affichÃƒÂ© (facultatif)',
              hintText: 'Ex. : Jean Express',
              prefixIcon: Icon(Icons.badge_outlined),
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ifu,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'NumÃƒÂ©ro IFU (facultatif)',
              prefixIcon: Icon(Icons.numbers_rounded),
            ),
          ),
        ],
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°tape 3 : papiers Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _cadrePhoto(Uint8List? bytes, Widget champ) {
    final erreur = _photosSignalees && bytes == null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: erreur
            ? Border.all(color: Theme.of(context).colorScheme.error, width: 2)
            : null,
      ),
      child: champ,
    );
  }

  Widget _etapePapiers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreEtape('Vos papiers',
            'Une seule fois. Visage dÃƒÂ©couvert, piÃƒÂ¨ce lisible, bien ÃƒÂ©clairÃƒÂ©e.'),
        _cadrePhoto(
          _photoProfil,
          PhotoPickerField(
            label: 'Photo de votre visage',
            icon: Icons.face_rounded,
            bytes: _photoProfil,
            onChanged: (b) => setState(() {
              _photoProfil = b;
              _profilUrl = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        _cadrePhoto(
          _photoCni,
          PhotoPickerField(
            label: 'PiÃƒÂ¨ce d\'identitÃƒÂ©',
            icon: Icons.badge_outlined,
            bytes: _photoCni,
            onChanged: (b) => setState(() {
              _photoCni = b;
              _cniUrl = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        const _Astuce(
          icone: Icons.save_rounded,
          texte:
              'Vos rÃƒÂ©ponses sont gardÃƒÂ©es sur ce tÃƒÂ©lÃƒÂ©phone. Si la batterie '
              'lÃƒÂ¢che, vous reprenez ici (seules les photos sont ÃƒÂ  refaire).',
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°tape 4 : zone + rÃƒÂ©capitulatif Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _etapeZone(ColorScheme scheme) {
    final aPos = _lat != null && _lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreEtape('Votre zone', 'LÃƒÂ  oÃƒÂ¹ vous travaillez le plus souvent.'),
        Material(
          color: scheme.surface,
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: aPos ? scheme.primary : scheme.outline,
              width: aPos ? 2.4 : 1.4,
            ),
          ),
          child: InkWell(
            customBorder:
                BeveledRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onTap: _choisirPosition,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    aPos
                        ? Icons.check_circle_rounded
                        : Icons.add_location_alt_rounded,
                    color: aPos ? scheme.primary : scheme.onSurfaceVariant,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      aPos
                          ? 'Zone dÃƒÂ©finie\n'
                              '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'
                          : 'Placer ma zone sur la carte',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 30),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Recap(
          engin: _engin,
          nom: '${_prenom.text.trim()} ${_nom.text.trim()}'.trim(),
          telephone: _telephone,
        ),
        const SizedBox(height: 14),
        const _Astuce(
          icone: Icons.verified_user_rounded,
          texte: 'AprÃƒÂ¨s l\'envoi : vÃƒÂ©rification de votre identitÃƒÂ© (selfie), '
              'puis validation par l\'ÃƒÂ©quipe MonTotem avant vos premiÃƒÂ¨res '
              'courses.',
        ),
      ],
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Widgets du cockpit Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.etape,
    required this.nbEtapes,
    required this.titre,
    required this.engin,
    required this.onBack,
  });

  final int etape;
  final int nbEtapes;
  final String titre;
  final _Engin engin;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour',
            iconSize: 28,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const TotemIcon(TotemGlyph.mark, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSCRIPTION CONDUCTEUR',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  titre,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Ãƒâ€°tape ${etape + 1} sur $nbEtapes',
            excludeSemantics: true,
            child: Text(
              '${etape + 1}/$nbEtapes',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La route : bitume, pointillÃƒÂ©s, et le vÃƒÂ©hicule du conducteur qui avance.
class _RouteProgress extends StatelessWidget {
  const _RouteProgress({
    required this.progression,
    required this.engin,
    required this.couleur,
    required this.duree,
  });

  final double progression;
  final _Engin engin;
  final Color couleur;
  final Duration duree;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: LayoutBuilder(builder: (context, c) {
        const vehicule = 44.0;
        final largeur = c.maxWidth;
        final x = (largeur - vehicule) * progression.clamp(0.0, 1.0);
        return SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                top: 20,
                bottom: 8,
                child: CustomPaint(
                  painter: _RoutePainter(
                    progression: progression,
                    couleur: couleur,
                    bitume: scheme.surface,
                    bord: scheme.outline,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duree,
                curve: Curves.easeOutCubic,
                left: x,
                top: 0,
                width: vehicule,
                height: vehicule,
                child: TotemIcon(
                  engin == _Engin.kloboto
                      ? TotemGlyph.kloboto
                      : TotemGlyph.zemidjan,
                  size: vehicule,
                  color: scheme.onSurface,
                  accent: couleur,
                  semanticLabel: 'Progression de l\'inscription',
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.progression,
    required this.couleur,
    required this.bitume,
    required this.bord,
  });

  final double progression;
  final Color couleur;
  final Color bitume;
  final Color bord;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(r, Paint()..color = bitume);
    canvas.drawRRect(
      r,
      Paint()
        ..color = bord
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final y = size.height / 2;
    final fait = size.width * progression.clamp(0.0, 1.0);
    const tiret = 12.0;
    const vide = 9.0;
    final base = Paint()
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    var x = 14.0;
    while (x < size.width - 14) {
      final fin = (x + tiret).clamp(0.0, size.width - 14).toDouble();
      base.color = x <= fait ? couleur : bord;
      canvas.drawLine(Offset(x, y), Offset(fin, y), base);
      x += tiret + vide;
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.progression != progression ||
      old.couleur != couleur ||
      old.bitume != bitume ||
      old.bord != bord;
}

class _Astuce extends StatelessWidget {
  const _Astuce({required this.icone, required this.texte});
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: scheme.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 14.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Recap extends StatelessWidget {
  const _Recap({
    required this.engin,
    required this.nom,
    required this.telephone,
  });

  final _Engin engin;
  final String nom;
  final String telephone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget ligne(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(k,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 14.5)),
              ),
              Expanded(
                child: Text(
                  v.isEmpty ? 'Ã¢â‚¬â€' : v,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            ligne('Engin', engin.metier),
            ligne('Conducteur', nom),
            ligne('TÃƒÂ©lÃƒÂ©phone', telephone),
          ],
        ),
      ),
    );
  }
}
