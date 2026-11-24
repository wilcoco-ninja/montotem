import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart' show AuthInfoBanner;
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/presentation/widgets/photo_picker_field.dart';
import 'package:montotem/features/onboarding/presentation/widgets/position_picker_screen.dart';

/// Inscription conducteur en 2 ÃƒÂ©tapes :
///  1. IdentitÃƒÂ© (type de conduite + nom + photos)
///  2. ActivitÃƒÂ© (nom affichÃƒÂ© + ville + zone de travail)
class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key, this.kindInitial});

  /// 'zemidjan' | 'tricycle_passenger' | 'tricycle_fret' | null
  final String? kindInitial;

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  static const _types = {
    'zemidjan': (
      'ZÃƒÂ©midjan',
      'Moto-taxi Ã‚Â· 1 passager',
      Icons.two_wheeler_rounded,
    ),
    'tricycle_passenger': (
      'Cloboto',
      'Tricycle Ã‚Â· 2 ÃƒÂ  3 passagers',
      Icons.electric_rickshaw_rounded,
    ),
    'tricycle_fret': (
      'Kloboto',
      'Tricycle Ã‚Â· bagages et colis',
      Icons.inventory_2_rounded,
    ),
  };

  final _auth = AuthService();
  final _keys = [GlobalKey<FormState>(), GlobalKey<FormState>()];

  int _etape = 0;
  bool _envoi = false;
  String? _kind;
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _nomAffiche = TextEditingController();
  final _ville = TextEditingController();
  Uint8List? _photoProfil;
  Uint8List? _photoCni;
  bool _photosSignalees = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _kind = widget.kindInitial;
    final user = Supabase.instance.client.auth.currentSession?.user;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? context.go('/register/quick?role=provider') : null,
      );
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _nomAffiche.dispose();
    _ville.dispose();
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), duration: const Duration(seconds: 5)),
  );

  bool _valider() {
    if (!(_keys[_etape].currentState?.validate() ?? true)) return false;
    if (_etape == 0) {
      if (_kind == null) {
        _msg('Choisissez votre type de conduite');
        return false;
      }
      if (_photoProfil == null || _photoCni == null) {
        setState(() => _photosSignalees = true);
        _msg('Photo de profil et piÃƒÂ¨ce d\'identitÃƒÂ© obligatoires');
        return false;
      }
    } else if (_etape == 1) {
      if (_lat == null || _lng == null) {
        _msg('Placez votre zone de travail sur la carte');
        return false;
      }
    }
    return true;
  }

  void _suivant() {
    if (!_valider()) return;
    if (_etape < 1) {
      setState(() => _etape++);
    } else {
      _soumettre();
    }
  }

  void _retour() {
    if (_etape > 0) {
      setState(() => _etape--);
    } else {
      context.go('/welcome');
    }
  }

  Future<void> _choisirPosition() async {
    final actuelle = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : null;
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
  }

  Future<void> _soumettre() async {
    setState(() => _envoi = true);
    try {
      final profilUrl = await _auth.uploaderDocument(
        _photoProfil!,
        'profil.jpg',
        kind: UploadKind.avatar,
        folder: 'providers',
      );
      final cniUrl = await _auth.uploaderDocument(
        _photoCni!,
        'cni.jpg',
        kind: UploadKind.identity,
        folder: 'providers',
      );

      await Supabase.instance.client.rpc(
        'register_driver',
        params: {
          'p_kind': _kind!,
          'p_first_name': _prenom.text.trim(),
          'p_last_name': _nom.text.trim(),
          'p_business_name': _nomAffiche.text.trim().isEmpty
              ? null
              : _nomAffiche.text.trim(),
          'p_ville': _ville.text.trim().isEmpty ? null : _ville.text.trim(),
          'p_photo_profil_url': profilUrl,
          'p_photo_cni_url': cniUrl,
          'p_latitude': _lat,
          'p_longitude': _lng,
        },
      );

      if (!mounted) return;
      context.go('/driver/home');
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('ROLE_IMMUABLE')) {
        _msg(
          'Ce compte est dÃƒÂ©jÃƒÂ  inscrit comme client. '
          'Contactez le support pour changer de rÃƒÂ´le.',
        );
      } else if (m.contains('KIND_INVALIDE')) {
        _msg('Type de conduite invalide.');
      } else {
        _msg('Erreur : ${e.message}');
      }
    } catch (e) {
      if (mounted) _msg('Erreur inattendue. RÃƒÂ©essayez.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titres = ['IdentitÃƒÂ©', 'ActivitÃƒÂ©'];
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
          title: Text('Ãƒâ€°tape ${_etape + 1}/2 Ã‚Â· ${titres[_etape]}'),
        ),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 560,
            child: AbsorbPointer(
              absorbing: _envoi,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Form(
                        key: _keys[_etape],
                        child: _etape == 0
                            ? _etapeIdentite()
                            : _etapeActivite(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: AppButton(
                      label: _etape < 1
                          ? 'Continuer'
                          : 'CrÃƒÂ©er mon compte conducteur',
                      icon: _etape < 1
                          ? Icons.arrow_forward_rounded
                          : Icons.check_rounded,
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

  Widget _etapeIdentite() {
    Widget carteKind(String code) {
      final data = _types[code]!;
      final selected = _kind == code;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () => setState(() => _kind = code),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: selected
                      ? AppColors.amber
                      : Theme.of(context).colorScheme.outline
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
                    child: Icon(data.$3, color: AppColors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.$1,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          data.$2,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Votre type de conduite',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final code in _types.keys) carteKind(code),
        const SizedBox(height: 22),
        AppTextField(
          label: 'Nom',
          icon: Icons.person_outline,
          controller: _nom,
          textInputAction: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'PrÃƒÂ©nom',
          icon: Icons.person_outline,
          controller: _prenom,
          textInputAction: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
        ),
        const SizedBox(height: 22),
        const SectionTitle('VÃƒÂ©rification'),
        Row(
          children: [
            Expanded(
              child: _photo(
                'Photo de profil',
                Icons.person_outline,
                _photoProfil,
                (b) => setState(() => _photoProfil = b),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _photo(
                'PiÃƒÂ¨ce d\'identitÃƒÂ©',
                Icons.badge_outlined,
                _photoCni,
                (b) => setState(() => _photoCni = b),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _etapeActivite() {
    final scheme = Theme.of(context).colorScheme;
    final aPos = _lat != null && _lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthInfoBanner(
          title: _types[_kind]?.$1 ?? 'Conducteur',
          message:
              'Vous recevrez des courses autour de vous. '
              'Passez en ligne pour commencer ÃƒÂ  recevoir.',
          icon: _types[_kind]?.$3 ?? Icons.two_wheeler_rounded,
          color: scheme.primary,
        ),
        const SizedBox(height: 18),
        AppTextField(
          label: 'Nom affichÃƒÂ© (facultatif)',
          hint: 'Ex: Jean ZÃƒÂ©midjan Pro',
          icon: Icons.badge_outlined,
          controller: _nomAffiche,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Ville (facultatif)',
          hint: 'Cotonou, Porto-NovoÃ¢â‚¬Â¦',
          icon: Icons.location_city_outlined,
          controller: _ville,
          textInputAction: TextInputAction.done,
        ),
        const SectionTitle('Votre zone de travail'),
        SoftCard(
          onTap: _choisirPosition,
          child: Row(
            children: [
              Icon(
                aPos ? Icons.check_circle_rounded : Icons.location_off_outlined,
                color: aPos ? scheme.secondary : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  aPos
                      ? 'Position dÃƒÂ©finie (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'
                      : 'Placer votre zone sur la carte',
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

  Widget _photo(
    String label,
    IconData icon,
    Uint8List? bytes,
    ValueChanged<Uint8List?> onChanged,
  ) {
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
        onChanged: onChanged,
      ),
    );
  }
}
