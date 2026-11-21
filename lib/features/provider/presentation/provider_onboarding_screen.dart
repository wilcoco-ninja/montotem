
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/utils/ifu_validator.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart' show AuthInfoBanner;
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/data/quick_auth_service.dart';
import 'package:montotem/features/auth/presentation/widgets/photo_picker_field.dart';
import 'package:montotem/features/provider/data/provider_catalog_service.dart';
import 'package:montotem/features/provider/domain/provider_trades.dart';
import 'package:montotem/features/onboarding/presentation/widgets/position_picker_screen.dart';

/// Onboarding prestataire optimisÃƒÂ© et ultra-visuel.
///  - DÃƒÂ©pannage (4 ÃƒÂ©tapes) : IdentitÃƒÂ© Ã‚Â· Atelier Ã‚Â· Prestations Ã‚Â· DÃƒÂ©placement.
///  - Transport, ZÃƒÂ©midjan / Tricycle Fret (2 ÃƒÂ©tapes) : IdentitÃƒÂ© Ã‚Â· ActivitÃƒÂ©.
class ProviderOnboardingScreen extends StatefulWidget {
  const ProviderOnboardingScreen({super.key});

  @override
  State<ProviderOnboardingScreen> createState() =>
      _ProviderOnboardingScreenState();
}

class _Svc {
  _Svc(
      {this.nom = '', this.categorie = 'voiture', this.fixe = true, this.prix});
  String nom;
  String categorie;
  bool fixe;
  int? prix;
}

const _vehicules = {
  'moto': ('Moto', Icons.two_wheeler_rounded),
  'voiture': ('Auto', Icons.directions_car_rounded),
  'camion': ('Camion', Icons.local_shipping_rounded),
};

const _suggestions = [
  'Crevaison / pneu',
  'Batterie / dÃƒÂ©marrage',
  'Remorquage',
  'Panne d\'essence',
  'Diagnostic ÃƒÂ©lectrique',
  'RÃƒÂ©paration sur place',
];

class _ProviderOnboardingScreenState extends State<ProviderOnboardingScreen> {
  static const _titresDepannage = [
    'IdentitÃƒÂ©',
    'Atelier',
    'Prestations',
    'DÃƒÂ©placement',
  ];
  static const _titresTransport = ['IdentitÃƒÂ©', 'ActivitÃƒÂ©'];
  static const _cleBrouillon = 'totem_brouillon_depanneur';

  final _auth = AuthService();
  final _catalogue = ProviderCatalogService();
  final _quick = QuickAuthService();

  // Correction de bug : ClÃƒÂ©s fixes pour ÃƒÂ©viter la rÃƒÂ©initialisation de l'ÃƒÂ©tat du formulaire
  late final List<GlobalKey<FormState>> _keys =
      List.generate(4, (_) => GlobalKey<FormState>());

  int _etape = 0;
  bool _envoi = false;

  // Ãƒâ€°tape 1
  String? _metier;
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _ifu = TextEditingController();
  Uint8List? _photoProfil;
  Uint8List? _photoCni;
  bool _photosSignalees = false;

  // Ãƒâ€°tape 2
  final _garage = TextEditingController();
  final _whatsapp = TextEditingController();
  final _adresse = TextEditingController();
  final Set<String> _vehicleTypes = {};
  double? _lat;
  double? _lng;

  // Ãƒâ€°tape 3 (dÃƒÂ©pannage)
  final List<_Svc> _services = [];

  // Ãƒâ€°tape 4 (dÃƒÂ©pannage)
  final _tarifKm = TextEditingController(text: '150');
  final _fraisMin = TextEditingController(text: '500');
  double _rayon = 15;
  double _simuKm = 5;

  late final String _phone;
  late final TextEditingController _contact;

  bool get _transport => estMetierTransport(_metier);
  List<String> get _titres => _transport ? _titresTransport : _titresDepannage;
  int get _dernier => _titres.length - 1;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentSession?.user;
    _phone = user?.phone ?? '';
    _contact = TextEditingController(
      text: _phone.isNotEmpty ? _phone : (user?.email ?? ''),
    );
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? context.go('/register/quick?role=provider') : null);
    }

    _restaurerBrouillon();
    _ajouterListeners();
  }

  void _ajouterListeners() {
    for (final c in [
      _nom,
      _prenom,
      _ifu,
      _garage,
      _whatsapp,
      _adresse,
      _tarifKm,
      _fraisMin,
    ]) {
      c.addListener(_sauver);
    }
  }

  Future<void> _restaurerBrouillon() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cleBrouillon);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _metier = data['metier'] as String?;
        _nom.text = data['nom'] as String? ?? '';
        _prenom.text = data['prenom'] as String? ?? '';
        _ifu.text = data['ifu'] as String? ?? '';
        _garage.text = data['garage'] as String? ?? '';
        _whatsapp.text = data['whatsapp'] as String? ?? '';
        _vehicleTypes
            .addAll((data['vehicules'] as List?)?.cast<String>() ?? []);
        _lat = data['lat'] as double?;
        _lng = data['lng'] as double?;
        _tarifKm.text = data['tarif_km'] as String? ?? '150';
        _fraisMin.text = data['frais_min'] as String? ?? '500';
        _rayon = (data['rayon'] as num?)?.toDouble() ?? 15;
        _etape = data['etape'] as int? ?? 0;

        final rawServices = data['services'] as List?;
        if (rawServices != null) {
          _services.clear();
          for (final s in rawServices) {
            _services.add(_Svc(
              nom: s['nom'] as String? ?? '',
              categorie: s['cat'] as String? ?? 'voiture',
              fixe: s['fixe'] as bool? ?? true,
              prix: s['prix'] as int?,
            ));
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _sauver() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _cleBrouillon,
        jsonEncode({
          'metier': _metier,
          'nom': _nom.text,
          'prenom': _prenom.text,
          'ifu': _ifu.text,
          'garage': _garage.text,
          'whatsapp': _whatsapp.text,
          'vehicules': _vehicleTypes.toList(),
          'lat': _lat,
          'lng': _lng,
          'tarif_km': _tarifKm.text,
          'frais_min': _fraisMin.text,
          'rayon': _rayon,
          'etape': _etape,
          'services': [
            for (final s in _services)
              {
                'nom': s.nom,
                'cat': s.categorie,
                'fixe': s.fixe,
                'prix': s.prix,
              }
          ],
        }),
      );
    } catch (_) {}
  }

  Future<void> _effacerBrouillon() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cleBrouillon);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [
      _nom,
      _prenom,
      _ifu,
      _garage,
      _whatsapp,
      _adresse,
      _tarifKm,
      _fraisMin,
      _contact,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _tarifKmVal => int.tryParse(_tarifKm.text.trim()) ?? 0;
  int get _fraisMinVal => int.tryParse(_fraisMin.text.trim()) ?? 0;

  String get _nomAffiche {
    final saisi = _garage.text.trim();
    if (saisi.isNotEmpty) return saisi;
    return '${_prenom.text.trim()} ${_nom.text.trim()}'.trim();
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 5)));

  String? _requis(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requis' : null;

  bool _valider() {
    if (_etape > _dernier) _etape = _dernier;
    if (!(_keys[_etape].currentState?.validate() ?? true)) return false;

    switch (_etape) {
      case 0:
        if (_metier == null) {
          _msg('Choisissez votre activitÃƒÂ©');
          return false;
        }
        if (_photoProfil == null || _photoCni == null) {
          setState(() => _photosSignalees = true);
          _msg('Photo de profil et piÃƒÂ¨ce d\'identitÃƒÂ© obligatoires');
          return false;
        }
        break;
      case 1:
        if (_transport) {
          if (_lat == null || _lng == null) {
            _msg('Placez votre zone de travail sur la carte');
            return false;
          }
        } else {
          if (_vehicleTypes.isEmpty) {
            _msg('Choisissez au moins un type de vÃƒÂ©hicule');
            return false;
          }
          if (_lat == null || _lng == null) {
            _msg('Placez votre atelier sur la carte');
            return false;
          }
        }
        break;
      case 2:
        if (_services.isEmpty) {
          _msg('Ajoutez au moins une prestation');
          return false;
        }
        for (final s in _services) {
          if (s.nom.trim().length < 2) {
            _msg('Chaque prestation doit avoir un nom');
            return false;
          }
          if (!_vehicleTypes.contains(s.categorie)) {
            _msg('Ã‚Â« ${s.nom} Ã‚Â» : type de vÃƒÂ©hicule non pris en charge');
            return false;
          }
          if (s.fixe && (s.prix == null || s.prix! <= 0)) {
            _msg(
                'Ã‚Â« ${s.nom} Ã‚Â» : indiquez un prix ou passez en Ã‚Â« Sur devis Ã‚Â»');
            return false;
          }
        }
        break;
    }
    return true;
  }

  void _suivant() {
    if (!_valider()) return;
    if (_etape < _dernier) {
      setState(() => _etape++);
      _sauver();
    } else {
      _soumettre();
    }
  }

  void _retour() {
    _sauver();
    if (_etape > 0) {
      setState(() => _etape--);
    } else {
      context.go('/welcome');
    }
  }

  Future<void> _choisirPosition() async {
    final actuelle =
        (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
          builder: (_) => PositionPickerScreen(positionInitiale: actuelle)),
    );
    if (r == null || !mounted) return;
    setState(() {
      _lat = r.latitude;
      _lng = r.longitude;
    });
    _sauver();
  }

  Future<void> _soumettre() async {
    if (!_transport && (_tarifKmVal < 0 || _fraisMinVal < 0)) {
      _msg('Tarifs invalides');
      return;
    }
    setState(() => _envoi = true);
    try {
      final profilUrl = await _auth.uploaderDocument(
          _photoProfil!, 'profil.jpg',
          kind: UploadKind.avatar, folder: 'providers');
      final cniUrl = await _auth.uploaderDocument(_photoCni!, 'cni.jpg',
          kind: UploadKind.identity, folder: 'providers');

      await _quick.registerProvider(
        firstName: _prenom.text,
        lastName: _nom.text,
        businessName: _nomAffiche,
        metier: _metier!,
        ville: _adresse.text,
        ifu: _ifu.text,
        photoProfilUrl: profilUrl,
        photoCniUrl: cniUrl,
        latitude: _lat!,
        longitude: _lng!,
      );

      if (!_transport) {
        await _catalogue.enregistrer(
          vehicleTypes: _vehicleTypes.toList(),
          services: _services
              .map((s) => ServiceTarif(
                    nom: s.nom.trim(),
                    categorieVehicule: s.categorie,
                    prixFcfa: s.fixe ? (s.prix ?? 0) : 0,
                  ))
              .toList(),
          tarifKmFcfa: _tarifKmVal,
          fraisMinFcfa: _fraisMinVal,
          rayonKm: _rayon.round(),
          whatsapp: _whatsapp.text,
        );
      }

      await _effacerBrouillon();

      if (!mounted) return;
      context.go('/provider/identity');
    } on UploadException catch (e) {
      if (mounted) _msg(e.message);
    } on QuickAuthException catch (e) {
      if (mounted) _msg(e.message);
    } catch (e) {
      if (mounted) _msg('Erreur inattendue ou rÃƒÂ©seau. RÃƒÂ©essayez.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titres = _titres;
    if (_etape > _dernier) _etape = _dernier;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_envoi) _retour();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _envoi ? null : _retour,
          ),
          title: Text(
              'Ãƒâ€°tape ${_etape + 1}/${titres.length} Ã‚Â· ${titres[_etape]}'),
        ),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 560,
            child: AbsorbPointer(
              absorbing: _envoi,
              child: Column(
                children: [
                  _StepHeader(current: _etape, titres: titres),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Form(
                        key: _keys[_etape],
                        child: switch (_etape) {
                          0 => _etape1(),
                          1 => _etape2(),
                          2 => _etape3(),
                          _ => _etape4(),
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: AppButton(
                      label: _etape < _dernier
                          ? 'Continuer'
                          : 'Envoyer ma demande',
                      icon: _etape < _dernier
                          ? Icons.arrow_forward_rounded
                          : Icons.send_rounded,
                      loading: _envoi,
                      onPressed: _suivant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(String titre, String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(texte,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65))),
          ],
        ),
      );

  Widget _photo(String label, IconData icon, Uint8List? bytes,
      ValueChanged<Uint8List?> onChanged) {
    final scheme = Theme.of(context).colorScheme;
    final erreur = _photosSignalees && bytes == null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: erreur ? Border.all(color: scheme.error, width: 1.6) : null,
      ),
      child: PhotoPickerField(
          label: label,
          icon: icon,
          bytes: bytes,
          onChanged: (b) {
            onChanged(b);
            _sauver();
          }),
    );
  }

  Widget _choixActivite() {
    Widget carteMetier(String nomMetier, String description, IconData icone) {
      final selected = _metier == nomMetier;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () {
              setState(() => _metier = nomMetier);
              _sauver();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: selected
                      ? AppColors.amber
                      : Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.2),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icone, color: AppColors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nomMetier,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(description,
                            style: TextStyle(
                                fontSize: 13, color: context.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.amber : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transport & Courses',
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: context.textSecondary)),
        const SizedBox(height: 8),
        carteMetier('ZÃƒÂ©midjan', 'Transport rapide de passagers ÃƒÂ  moto',
            Icons.two_wheeler_rounded),
        carteMetier('Tricycle Fret', 'Transport de marchandises et bagages',
            Icons.local_shipping_rounded),
        const SizedBox(height: 14),
        Text('DÃƒÂ©pannage & Garage',
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: context.textSecondary)),
        const SizedBox(height: 8),
        for (final m in kMetiersDepannage)
          carteMetier(m, 'Assistance et rÃƒÂ©paration technique',
              kIconesMetier[m] ?? Icons.build_outlined),
      ],
    );
  }

  Widget _etape1() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro('Qui ÃƒÂªtes-vous ?',
              'VÃƒÂ©rifiÃƒÂ©e une seule fois, votre identitÃƒÂ© rassure les clients.'),
          const Text('Votre activitÃƒÂ©',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _choixActivite(),
          const SizedBox(height: 22),
          AppTextField(
              label: 'Nom',
              icon: Icons.person_outline,
              controller: _nom,
              textInputAction: TextInputAction.next,
              validator: _requis),
          const SizedBox(height: 14),
          AppTextField(
              label: 'PrÃƒÂ©nom',
              icon: Icons.person_outline,
              controller: _prenom,
              textInputAction: TextInputAction.next,
              validator: _requis),
          const SizedBox(height: 14),
          AppTextField(
              label: _phone.isNotEmpty
                  ? 'TÃƒÂ©lÃƒÂ©phone vÃƒÂ©rifiÃƒÂ©'
                  : 'Email du compte',
              icon: _phone.isNotEmpty
                  ? Icons.phone_outlined
                  : Icons.email_outlined,
              controller: _contact,
              readOnly: true),
          const SizedBox(height: 14),
          AppTextField(
            label: _transport
                ? 'NumÃƒÂ©ro IFU (facultatif)'
                : 'NumÃƒÂ©ro IFU (13 chiffres)',
            icon: Icons.badge_outlined,
            controller: _ifu,
            keyboardType: TextInputType.number,
            inputFormatters: IfuValidator.formatters,
            maxLength: 13,
            validator: (v) => IfuValidator.validate(v, required: !_transport),
          ),
          const SizedBox(height: 22),
          const SectionTitle('VÃƒÂ©rification'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _photo('Photo de profil', Icons.person_outline,
                      _photoProfil, (b) => setState(() => _photoProfil = b))),
              const SizedBox(width: 12),
              Expanded(
                  child: _photo('PiÃƒÂ¨ce d\'identitÃƒÂ©', Icons.badge_outlined,
                      _photoCni, (b) => setState(() => _photoCni = b))),
            ],
          ),
        ],
      );

  Widget _etape2() => _transport ? _etapeActivite() : _etapeAtelier();

  Widget _carteLieu({required String vide, required String titreSection}) {
    final scheme = Theme.of(context).colorScheme;
    final aPos = _lat != null && _lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(titreSection),
        SoftCard(
          onTap: _choisirPosition,
          child: Row(
            children: [
              Icon(
                  aPos
                      ? Icons.check_circle_rounded
                      : Icons.location_off_outlined,
                  color: aPos ? scheme.secondary : scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  aPos
                      ? 'Position dÃƒÂ©finie (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'
                      : vide,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _etapeActivite() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _intro('Votre zone d\'activitÃƒÂ©',
            'DÃƒÂ©finissez votre secteur pour recevoir les courses instantanÃƒÂ©ment.'),
        AuthInfoBanner(
          title: _metier ?? 'Transport',
          message: 'Vous recevez les courses autour de vous en temps rÃƒÂ©el. '
              'Les paiements en espÃƒÂ¨ces impliquent une commission sur votre wallet, '
              'tandis que les paiements Mobile Money sont sans commission.',
          icon: _metier == 'Tricycle Fret'
              ? Icons.local_shipping_rounded
              : Icons.two_wheeler_rounded,
          color: scheme.primary,
        ),
        const SizedBox(height: 18),
        AppTextField(
          label: 'Nom affichÃƒÂ© (facultatif)',
          hint: 'Ex: Jean ZÃƒÂ©midjan Pro',
          icon: Icons.badge_outlined,
          controller: _garage,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 14),
        _carteLieu(
          titreSection: 'Votre zone habituelle',
          vide: 'Placer votre zone de travail sur la carte',
        ),
      ],
    );
  }

  Widget _etapeAtelier() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _intro('Votre atelier',
            'Dites aux clients ce que vous rÃƒÂ©parez et oÃƒÂ¹ vous trouver.'),
        AppTextField(
            label: 'Nom de l\'atelier / garage',
            icon: Icons.store_outlined,
            controller: _garage,
            textInputAction: TextInputAction.next,
            validator: _requis),
        const SectionTitle('VÃƒÂ©hicules pris en charge'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _vehicules.entries.map((e) {
            final on = _vehicleTypes.contains(e.key);
            return FilterChip(
              avatar: Icon(e.value.$2, size: 18),
              label: Text(e.value.$1),
              selected: on,
              onSelected: (v) => setState(() {
                v ? _vehicleTypes.add(e.key) : _vehicleTypes.remove(e.key);
                _services
                    .removeWhere((s) => !_vehicleTypes.contains(s.categorie));
                _sauver();
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        AppTextField(
          label: 'WhatsApp (optionnel)',
          helper: 'Jamais affichÃƒÂ© publiquement',
          icon: Icons.chat_outlined,
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))
          ],
          maxLength: 20,
        ),
        _carteLieu(
          titreSection: 'Position de l\'atelier',
          vide: 'Placer l\'atelier sur la carte',
        ),
      ],
    );
  }

  Widget _etape3() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro('Vos prestations',
              'Prix fixe ou sur devis : les clients voient votre grille avant de vous contacter.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .where((s) => !_services.any((x) => x.nom == s))
                .map((s) => ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(s),
                      onPressed: () {
                        setState(() => _services.add(_Svc(
                            nom: s,
                            categorie: _vehicleTypes.isNotEmpty
                                ? _vehicleTypes.first
                                : 'voiture')));
                        _sauver();
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _services.length; i++) _carteService(i),
          const SizedBox(height: 8),
          AppButton(
            label: 'Ajouter une prestation',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () {
              setState(() => _services.add(_Svc(
                  categorie: _vehicleTypes.isNotEmpty
                      ? _vehicleTypes.first
                      : 'voiture')));
              _sauver();
            },
          ),
        ],
      );

  Widget _carteService(int i) {
    final s = _services[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('nom-${s.hashCode}'),
                    initialValue: s.nom,
                    maxLength: 80,
                    decoration: const InputDecoration(
                        labelText: 'Prestation', counterText: ''),
                    onChanged: (v) {
                      s.nom = v;
                      _sauver();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    setState(() => _services.removeAt(i));
                    _sauver();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _vehicleTypes
                  .map((v) => ChoiceChip(
                        label: Text(_vehicules[v]!.$1),
                        selected: s.categorie == v,
                        onSelected: (_) {
                          setState(() => s.categorie = v);
                          _sauver();
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Prix fixe')),
                ButtonSegment(value: false, label: Text('Sur devis')),
              ],
              selected: {s.fixe},
              onSelectionChanged: (v) {
                setState(() => s.fixe = v.first);
                _sauver();
              },
            ),
            if (s.fixe) ...[
              const SizedBox(height: 10),
              TextFormField(
                key: ValueKey('prix-${s.hashCode}'),
                initialValue: s.prix?.toString() ?? '',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 7,
                decoration: const InputDecoration(
                    labelText: 'Prix', suffixText: 'FCFA', counterText: ''),
                onChanged: (v) {
                  s.prix = int.tryParse(v);
                  _sauver();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _etape4() {
    final scheme = Theme.of(context).colorScheme;
    final frais = TravelFee.estimate(
        km: _simuKm, tarifKmFcfa: _tarifKmVal, minimumFcfa: _fraisMinVal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _intro('Frais de dÃƒÂ©placement',
            'CalculÃƒÂ©s automatiquement selon la distance entre vous et le client en panne.'),
        AppTextField(
          label: 'Tarif par kilomÃƒÂ¨tre',
          icon: Icons.route_outlined,
          controller: _tarifKm,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 4,
          onChanged: (_) {
            setState(() {});
            _sauver();
          },
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return (n == null || n > 5000) ? '0 ÃƒÂ  5000 FCFA/km' : null;
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Frais minimum de dÃƒÂ©placement',
          icon: Icons.payments_outlined,
          controller: _fraisMin,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          onChanged: (_) {
            setState(() {});
            _sauver();
          },
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return (n == null || n > 100000) ? 'Montant invalide' : null;
          },
        ),
        const SectionTitle('Rayon d\'intervention'),
        Slider(
          value: _rayon,
          min: 1,
          max: 50,
          divisions: 49,
          label: '${_rayon.round()} km',
          onChanged: (v) {
            setState(() => _rayon = v);
            _sauver();
          },
        ),
        Text('Jusqu\'ÃƒÂ  ${_rayon.round()} km de votre atelier'),
        const SectionTitle('Simulateur'),
        SoftCard(
          child: Column(
            children: [
              Text('Client ÃƒÂ  ${_simuKm.round()} km',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(
                value: _simuKm,
                min: 1,
                max: _rayon.clamp(2, 50).toDouble(),
                onChanged: (v) => setState(() => _simuKm = v),
              ),
              Text(
                TravelFee.fcfa(frais),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary),
              ),
              const SizedBox(height: 2),
              const Text('DÃƒÂ©placement estimÃƒÂ© affichÃƒÂ© au client'),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.titres});
  final int current;
  final List<String> titres;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < titres.length; i++)
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current
                          ? scheme.secondary
                          : (i == current
                              ? scheme.primary
                              : Colors.transparent),
                      border: Border.all(
                        color: i <= current
                            ? Colors.transparent
                            : scheme.onSurface.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: i < current
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 24)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: i == current
                                  ? scheme.onPrimary
                                  : scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        titres[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              i == current ? FontWeight.w800 : FontWeight.w600,
                          color: i == current
                              ? scheme.onSurface
                              : scheme.onSurface.withValues(alpha: 0.8),
                        ),
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
}
