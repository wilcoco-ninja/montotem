
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart'
    show AuthService, UploadException, UploadKind;
import 'package:montotem/features/auth/data/quick_auth_service.dart';
import 'package:montotem/features/auth/presentation/widgets/photo_picker_field.dart';
import 'package:montotem/features/provider/data/provider_catalog_service.dart';
import 'package:montotem/features/provider/data/provider_skills_service.dart';
import 'package:montotem/features/provider/domain/provider_trades.dart';
import 'package:montotem/features/provider/presentation/widgets/position_picker_screen.dart';

class _Svc {
  _Svc({required this.id, required this.nom, required this.categorie});
  final int id;
  String nom;
  String categorie;
  bool fixe = true;
  int? prix;
}

class ProviderRegistrationScreen extends StatefulWidget {
  const ProviderRegistrationScreen({super.key});

  @override
  State<ProviderRegistrationScreen> createState() =>
      _ProviderRegistrationScreenState();
}

class _ProviderRegistrationScreenState
    extends State<ProviderRegistrationScreen> {
  final AuthService _authService = AuthService();
  final QuickAuthService _quick = QuickAuthService();
  final ProviderCatalogService _catalogue = ProviderCatalogService();
  final ProviderSkillsService _skillsService = ProviderSkillsService();
  final _formKey = GlobalKey<FormState>();

  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _ifuController = TextEditingController();
  late final TextEditingController _phoneController;

  final _garageController = TextEditingController();
  final _adresseController = TextEditingController();
  final _whatsappController = TextEditingController();
  String? _metier;
  final Set<String> _vehicules = {};
  double? _latitude;
  double? _longitude;

  final _competenceController = TextEditingController();
  final List<String> _competences = [];

  final List<_Svc> _services = [];
  int _svcSeq = 0;
  final _tarifKmController = TextEditingController(text: '150');
  final _fraisMinController = TextEditingController(text: '500');
  double _rayon = 15;
  double _simuKm = 5;

  Uint8List? _photoProfil;
  Uint8List? _photoCni;
  String? _profilUrl;
  String? _cniUrl;

  bool _isLoading = false;
  bool _isGeocodage = false;
  bool _photosManquantesSignalees = false;

  int get _tarifKm => int.tryParse(_tarifKmController.text.trim()) ?? 0;
  int get _fraisMin => int.tryParse(_fraisMinController.text.trim()) ?? 0;

  bool get _transport => estMetierTransport(_metier);

  @override
  void initState() {
    super.initState();

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      _phoneController = TextEditingController();
      return;
    }

    final user = session.user;
    if (user.email != null &&
        user.email!.isNotEmpty &&
        !user.email!.contains('@phone.fake') &&
        !user.email!.contains('@privaterelay')) {
      _emailController.text = user.email!;
    }
    _phoneController = TextEditingController(text: user.phone ?? '');

    if ((user.phone ?? '').isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register/phone?role=provider');
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nomController,
      _prenomController,
      _emailController,
      _ifuController,
      _phoneController,
      _garageController,
      _adresseController,
      _whatsappController,
      _competenceController,
      _tarifKmController,
      _fraisMinController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _afficherMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  String? _requis(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requis' : null;

  void _basculerVehicule(String type, bool actif) {
    setState(() {
      if (actif) {
        _vehicules.add(type);
      } else {
        _vehicules.remove(type);
        _services.removeWhere((s) => s.categorie == type);
      }
    });
  }

  void _ajouterService(String categorie, [String nom = '']) {
    if (nom.isNotEmpty &&
        _services.any((s) =>
            s.categorie == categorie &&
            s.nom.toLowerCase() == nom.toLowerCase())) {
      return;
    }
    setState(() =>
        _services.add(_Svc(id: _svcSeq++, nom: nom, categorie: categorie)));
  }

  void _ajouterCompetence(String brut) {
    final texte = brut.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (texte.isEmpty) return;
    if (texte.length < kCompetenceMin || texte.length > kCompetenceMax) {
      _afficherMessage(
          'Une compÃƒÂ©tence doit faire entre $kCompetenceMin et $kCompetenceMax caractÃƒÂ¨res.');
      return;
    }
    if (_competences.length >= kCompetencesMaxParPrestataire) {
      _afficherMessage('Maximum $kCompetencesMaxParPrestataire compÃƒÂ©tences.');
      return;
    }
    if (_competences.any((c) => c.toLowerCase() == texte.toLowerCase())) {
      _competenceController.clear();
      return;
    }
    setState(() => _competences.add(texte));
    _competenceController.clear();
  }

  Future<void> _choisirPosition() async {
    final positionActuelle = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : null;

    final resultat = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PositionPickerScreen(positionInitiale: positionActuelle),
      ),
    );

    if (resultat == null || !mounted) return;

    setState(() {
      _latitude = resultat.latitude;
      _longitude = resultat.longitude;
    });

    _tenterGeocodageInverse(resultat);
  }

  Future<void> _tenterGeocodageInverse(LatLng point) async {
    setState(() => _isGeocodage = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': point.latitude,
          'lon': point.longitude,
          'format': 'jsonv2',
        },
        options: Options(headers: {
          'User-Agent': 'MonTotemApp/1.0 (contact@montotem.com)',
        }),
      );
      final adresse = response.data?['display_name'] as String?;
      if (adresse != null &&
          mounted &&
          _adresseController.text.trim().isEmpty) {
        setState(() => _adresseController.text = adresse);
      }
    } catch (e, stackTrace) {
      developer.log(
        'Erreur de gÃƒÂ©ocodage inverse',
        error: e,
        stackTrace: stackTrace,
        name: 'ProviderRegistrationScreen',
      );
    } finally {
      if (mounted) setState(() => _isGeocodage = false);
    }
  }

  String? _verifierLogique() {
    if (_metier == null) return 'Choisissez votre corps de mÃƒÂ©tier.';
    if (!_transport && _vehicules.isEmpty) {
      return 'Choisissez au moins un type de vÃƒÂ©hicule.';
    }
    if (_latitude == null || _longitude == null) {
      return 'Placez votre position sur la carte.';
    }
    if (!_transport) {
      if (_services.isEmpty) return 'Ajoutez au moins une prestation express.';
      for (final s in _services) {
        if (s.nom.trim().length < 2) {
          return 'Chaque prestation doit avoir un nom.';
        }
        if (!_vehicules.contains(s.categorie)) {
          return 'Ã‚Â« ${s.nom} Ã‚Â» : type de vÃƒÂ©hicule non pris en charge.';
        }
        if (s.fixe && (s.prix == null || s.prix! <= 0)) {
          return 'Ã‚Â« ${s.nom} Ã‚Â» : indiquez un prix fixe supÃƒÂ©rieur ÃƒÂ  0.';
        }
      }
    }
    return null;
  }

  Future<void> _soumettre() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_photoProfil == null || _photoCni == null) {
      setState(() => _photosManquantesSignalees = true);
      _afficherMessage('Photo de profil et piÃƒÂ¨ce d\'identitÃƒÂ© obligatoires.');
      return;
    }
    final erreur = _verifierLogique();
    if (erreur != null) {
      _afficherMessage(erreur);
      return;
    }

    setState(() => _isLoading = true);

    try {
      _profilUrl ??= await _authService.uploaderDocument(
        _photoProfil!,
        'profil.jpg',
        kind: UploadKind.avatar,
        folder: 'providers',
      );
      _cniUrl ??= await _authService.uploaderDocument(
        _photoCni!,
        'cni.jpg',
        kind: UploadKind.identity,
        folder: 'providers',
      );

      await _quick.registerProvider(
        firstName: _prenomController.text,
        lastName: _nomController.text,
        businessName: _garageController.text.trim().isNotEmpty
            ? _garageController.text
            : '${_prenomController.text} ${_nomController.text}'.trim(),
        metier: _metier!,
        ville: _adresseController.text,
        ifu: _ifuController.text,
        photoProfilUrl: _profilUrl!,
        photoCniUrl: _cniUrl!,
        latitude: _latitude!,
        longitude: _longitude!,
      );

      if (!_transport) {
        await _catalogue.enregistrer(
          vehicleTypes: _vehicules.toList(),
          services: _services
              .map((s) => ServiceTarif(
                    nom: s.nom.trim(),
                    categorieVehicule: s.categorie,
                    prixFcfa: s.fixe ? (s.prix ?? 0) : 0,
                  ))
              .toList(),
          tarifKmFcfa: _tarifKm,
          fraisMinFcfa: _fraisMin,
          rayonKm: _rayon.round(),
          whatsapp: _whatsappController.text,
        );
      }

      var echecs = 0;
      for (final c in _competences) {
        try {
          await _skillsService.ajouter(c);
        } on SkillException {
          echecs++;
        }
      }

      if (!mounted) return;
      if (echecs > 0) {
        _afficherMessage(
            '$echecs compÃƒÂ©tence(s) non enregistrÃƒÂ©e(s). Ajoutez-les depuis votre profil.');
      }
      context.go('/provider/identity');
    } on UploadException catch (e) {
      if (mounted) _afficherMessage(e.message);
    } on QuickAuthException catch (e) {
      if (mounted) _afficherMessage(e.message);
    } catch (e, st) {
      developer.log('Inscription prestataire',
          error: e, stackTrace: st, name: 'ProviderRegistrationScreen');
      if (mounted) {
        _afficherMessage('Erreur inattendue ou rÃƒÂ©seau. RÃƒÂ©essayez.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.75);

    return AuthShell(
      title: 'Devenez prestataire',
      subtitle: 'Recevez des demandes de dÃƒÂ©pannage prÃƒÂ¨s de chez vous',
      icon: Icons.build_circle_outlined,
      onBack: _isLoading ? null : () => context.go('/welcome'),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('DÃƒÂ©jÃƒÂ  un compte ?', style: TextStyle(color: muted)),
          TextButton(
            onPressed: _isLoading ? null : () => context.go('/login'),
            child: const Text(
              'Me connecter',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      child: AbsorbPointer(
        absorbing: _isLoading,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthInfoBanner(
                title: 'Compte sÃƒÂ©curisÃƒÂ©',
                message:
                    'TÃƒÂ©lÃƒÂ©phone dÃƒÂ©jÃƒÂ  vÃƒÂ©rifiÃƒÂ©. ComplÃƒÂ©tez votre profil : l\'ÃƒÂ©tape suivante '
                    'est la vÃƒÂ©rification d\'identitÃƒÂ©.',
              ),
              const SizedBox(height: 22),
              ..._blocIdentite(),
              const SizedBox(height: 26),
              ..._blocAtelier(),
              const SizedBox(height: 26),
              ..._blocCompetences(),
              if (!_transport) ...[
                const SizedBox(height: 26),
                ..._blocPrestations(),
                const SizedBox(height: 26),
                ..._blocDeplacement(),
              ],
              const SizedBox(height: 26),
              ..._blocPhotos(),
              const SizedBox(height: 28),
              AppButton(
                label: 'Envoyer ma demande',
                icon: Icons.send_rounded,
                loading: _isLoading,
                onPressed: _soumettre,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _blocIdentite() => [
        const AuthSectionHeader(
          icon: Icons.person_outline_rounded,
          title: 'Informations personnelles',
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Nom',
          icon: Icons.person_outline,
          controller: _nomController,
          textInputAction: TextInputAction.next,
          validator: _requis,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'PrÃƒÂ©nom',
          icon: Icons.person_outline,
          controller: _prenomController,
          textInputAction: TextInputAction.next,
          validator: _requis,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Email du compte',
          helper: 'Modifiable depuis les paramÃƒÂ¨tres du compte',
          icon: Icons.email_outlined,
          controller: _emailController,
          readOnly: true,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'TÃƒÂ©lÃƒÂ©phone vÃƒÂ©rifiÃƒÂ©',
          helper: 'NumÃƒÂ©ro validÃƒÂ© par SMS',
          icon: Icons.phone_outlined,
          controller: _phoneController,
          readOnly: true,
        ),
      ];

  List<Widget> _blocAtelier() {
    final scheme = Theme.of(context).colorScheme;
    final hasPosition = _latitude != null && _longitude != null;
    final color = hasPosition ? scheme.secondary : scheme.primary;

    Widget groupeMetiers(String titre, List<String> metiers) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in metiers)
                  ChoiceChip(
                    avatar: Icon(kIconesMetier[m] ?? Icons.build_outlined,
                        size: 20),
                    label: Text(m),
                    selected: _metier == m,
                    onSelected: (_) => setState(() => _metier = m),
                  ),
              ],
            ),
          ],
        );

    return [
      const AuthSectionHeader(
        icon: Icons.storefront_outlined,
        title: 'Votre activitÃƒÂ©',
        subtitle: 'MÃƒÂ©tier, vÃƒÂ©hicules et position',
      ),
      const SizedBox(height: 16),
      AppTextField(
        label: _transport
            ? 'Nom affichÃƒÂ© (facultatif)'
            : 'Nom du garage / atelier',
        hint: _transport ? 'Par dÃƒÂ©faut : prÃƒÂ©nom et nom' : null,
        icon: Icons.store_outlined,
        controller: _garageController,
        textInputAction: TextInputAction.next,
        validator: _transport ? null : _requis,
      ),
      const SizedBox(height: 14),
      AppTextField(
        label: _transport ? 'NumÃƒÂ©ro IFU (facultatif)' : 'NumÃƒÂ©ro IFU',
        icon: Icons.badge_outlined,
        controller: _ifuController,
        textInputAction: TextInputAction.next,
        validator: _transport ? null : _requis,
      ),
      const SizedBox(height: 14),
      AppTextField(
        label: 'WhatsApp (optionnel)',
        helper: 'Jamais affichÃƒÂ© publiquement',
        icon: Icons.chat_outlined,
        controller: _whatsappController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))
        ],
        maxLength: 20,
      ),
      const SectionTitle('Corps de mÃƒÂ©tier'),
      groupeMetiers('DÃƒÂ©pannage', kMetiersDepannage),
      const SizedBox(height: 14),
      groupeMetiers('Transport (courses)', kMetiersTransport),
      if (!_transport) ...[
        const SectionTitle('VÃƒÂ©hicules pris en charge'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in kVehicules.entries)
              FilterChip(
                avatar: Icon(e.value.icon, size: 20),
                label: Text(e.value.label),
                tooltip: e.value.detail,
                selected: _vehicules.contains(e.key),
                onSelected: (v) => _basculerVehicule(e.key, v),
              ),
          ],
        ),
      ],
      const SectionTitle('Position'),
      SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              hasPosition
                  ? Icons.check_circle_rounded
                  : Icons.location_off_outlined,
              color: color,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasPosition
                    ? 'Position dÃƒÂ©finie\n'
                        '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                    : 'Obligatoire : oÃƒÂ¹ vous serez localisÃƒÂ©',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppButton(
        label: hasPosition ? 'Modifier la position' : 'Placer sur la carte',
        icon:
            hasPosition ? Icons.edit_location_alt_outlined : Icons.map_outlined,
        variant: AppButtonVariant.secondary,
        onPressed: _choisirPosition,
      ),
      if (_isGeocodage) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(minHeight: 3),
        ),
      ],
      if (_adresseController.text.trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        AppTextField(
          label: 'Adresse dÃƒÂ©tectÃƒÂ©e',
          icon: Icons.location_city_outlined,
          controller: _adresseController,
          maxLines: 2,
        ),
      ],
    ];
  }

  List<Widget> _blocCompetences() {
    final suggestions = kCompetencesSuggerees
        .where(
            (s) => !_competences.any((c) => c.toLowerCase() == s.toLowerCase()))
        .toList();

    return [
      AuthSectionHeader(
        icon: Icons.psychology_alt_outlined,
        title: 'CompÃƒÂ©tences',
        subtitle:
            'Visibles par les clients (${_competences.length}/$kCompetencesMaxParPrestataire)',
      ),
      const SizedBox(height: 14),
      if (_competences.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _competences)
              InputChip(
                label: Text(c),
                onDeleted: () => setState(() => _competences.remove(c)),
                deleteButtonTooltipMessage: 'Retirer',
              ),
          ],
        ),
      if (_competences.isNotEmpty) const SizedBox(height: 12),
      AppTextField(
        label: 'Ajouter une compÃƒÂ©tence',
        hint: 'Ex. : Climatisation auto',
        icon: Icons.edit_outlined,
        controller: _competenceController,
        maxLength: kCompetenceMax,
        textInputAction: TextInputAction.done,
        onSubmitted: _ajouterCompetence,
        suffix: IconButton(
          tooltip: 'Ajouter',
          icon: const Icon(Icons.add_circle_rounded),
          onPressed: () => _ajouterCompetence(_competenceController.text),
        ),
      ),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(s),
                onPressed: () => _ajouterCompetence(s),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _blocPrestations() {
    final scheme = Theme.of(context).colorScheme;
    return [
      const AuthSectionHeader(
        icon: Icons.bolt_rounded,
        title: 'Tarifs express',
        subtitle:
            'Prix fixe par prestation, vu par les clients avant de vous contacter',
      ),
      const SizedBox(height: 14),
      if (_vehicules.isEmpty)
        StatusPill(
          label: 'Choisissez d\'abord vos vÃƒÂ©hicules',
          color: scheme.tertiary,
          icon: Icons.info_outline_rounded,
        )
      else
        for (final type in _vehicules) ...[
          Text(kVehicules[type]!.label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in kServicesExpress[type] ?? const <String>[])
                if (!_services.any((x) =>
                    x.categorie == type &&
                    x.nom.toLowerCase() == s.toLowerCase()))
                  ActionChip(
                    avatar: Icon(kVehicules[type]!.icon, size: 18),
                    label: Text(s),
                    onPressed: () => _ajouterService(type, s),
                  ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Autre prestation'),
                onPressed: () => _ajouterService(type),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      for (final s in _services) _carteService(s),
    ];
  }

  Widget _carteService(_Svc s) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(kVehicules[s.categorie]?.icon ?? Icons.build_outlined,
                    size: 26, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('nom-${s.id}'),
                    initialValue: s.nom,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Prestation', counterText: ''),
                    onChanged: (v) => s.nom = v,
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => setState(() => _services.remove(s)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('prix-${s.id}'),
              initialValue: s.prix?.toString() ?? '',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 7,
              decoration: const InputDecoration(
                  labelText: 'Prix fixe', suffixText: 'FCFA', counterText: ''),
              onChanged: (v) => s.prix = int.tryParse(v),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _blocDeplacement() {
    final scheme = Theme.of(context).colorScheme;
    final frais = TravelFee.estimate(
        km: _simuKm, tarifKmFcfa: _tarifKm, minimumFcfa: _fraisMin);

    return [
      const AuthSectionHeader(
        icon: Icons.route_outlined,
        title: 'Frais de dÃƒÂ©placement',
        subtitle: 'CalculÃƒÂ©s selon la distance jusqu\'au client',
      ),
      const SizedBox(height: 16),
      AppTextField(
        label: 'Tarif par kilomÃƒÂ¨tre (FCFA)',
        icon: Icons.route_outlined,
        controller: _tarifKmController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 4,
        onChanged: (_) => setState(() {}),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return (n == null || n > 5000) ? '0 ÃƒÂ  5000 FCFA/km' : null;
        },
      ),
      const SizedBox(height: 14),
      AppTextField(
        label: 'Frais minimum de dÃƒÂ©placement (FCFA)',
        icon: Icons.payments_outlined,
        controller: _fraisMinController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        onChanged: (_) => setState(() {}),
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
        onChanged: (v) => setState(() {
          _rayon = v;
          if (_simuKm > v) _simuKm = v;
        }),
      ),
      Text('Jusqu\'ÃƒÂ  ${_rayon.round()} km',
          style: const TextStyle(fontSize: 15)),
      const SizedBox(height: 14),
      SoftCard(
        child: Column(
          children: [
            Text('Simulation : client ÃƒÂ  ${_simuKm.round()} km',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: _simuKm.clamp(1, _rayon < 2 ? 2 : _rayon).toDouble(),
              min: 1,
              max: _rayon < 2 ? 2 : _rayon,
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
    ];
  }

  Widget _photo({
    required String label,
    required IconData icon,
    required Uint8List? bytes,
    required ValueChanged<Uint8List?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = _photosManquantesSignalees && bytes == null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: hasError ? Border.all(color: scheme.error, width: 1.6) : null,
      ),
      child: PhotoPickerField(
        label: label,
        icon: icon,
        bytes: bytes,
        onChanged: onChanged,
      ),
    );
  }

  List<Widget> _blocPhotos() => [
        const AuthSectionHeader(
          icon: Icons.photo_camera_outlined,
          title: 'Photos',
          subtitle: 'Requis pour la sÃƒÂ©curitÃƒÂ© de vos futurs clients',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 380) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _photo(
                    label: 'Photo de profil',
                    icon: Icons.person_outline,
                    bytes: _photoProfil,
                    onChanged: (b) => setState(() {
                      _photoProfil = b;
                      _profilUrl = null;
                      if (b != null && _photoCni != null) {
                        _photosManquantesSignalees = false;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  _photo(
                    label: 'PiÃƒÂ¨ce d\'identitÃƒÂ©',
                    icon: Icons.badge_outlined,
                    bytes: _photoCni,
                    onChanged: (b) => setState(() {
                      _photoCni = b;
                      _cniUrl = null;
                      if (b != null && _photoProfil != null) {
                        _photosManquantesSignalees = false;
                      }
                    }),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _photo(
                    label: 'Photo de profil',
                    icon: Icons.person_outline,
                    bytes: _photoProfil,
                    onChanged: (b) => setState(() {
                      _photoProfil = b;
                      _profilUrl = null;
                      if (b != null && _photoCni != null) {
                        _photosManquantesSignalees = false;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _photo(
                    label: 'PiÃƒÂ¨ce d\'identitÃƒÂ©',
                    icon: Icons.badge_outlined,
                    bytes: _photoCni,
                    onChanged: (b) => setState(() {
                      _photoCni = b;
                      _cniUrl = null;
                      if (b != null && _photoProfil != null) {
                        _photosManquantesSignalees = false;
                      }
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ];
}
