import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/flavor/app_flavor.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart'
    show AuthErrorBanner, AuthInfoBanner;
import 'package:montotem/features/auth/data/auth_service.dart'
    show UploadException;
import 'package:montotem/features/provider/data/image_quality_service.dart';
import 'package:montotem/features/provider/data/provider_identity_service.dart';
import 'package:montotem/features/provider/presentation/widgets/verified_photo_field.dart';

/// Vérification d'identité : type de pièce, numéro, photos contrôlées,
/// visage entier et garage (dépanneur) ou véhicule (Zémidjan, Tricycle Fret)[cite: 29].
class ProviderIdentityScreen extends StatefulWidget {
  const ProviderIdentityScreen({super.key});

  @override
  State<ProviderIdentityScreen> createState() => _ProviderIdentityScreenState();
}

class _ProviderIdentityScreenState extends State<ProviderIdentityScreen> {
  final ProviderIdentityService _service = ProviderIdentityService();
  final ImageQualityService _quality = ImageQualityService();
  final TextEditingController _numero = TextEditingController();
  final TextEditingController _description = TextEditingController();

  IdDocumentType? _type;
  VerifiedPhoto? _selfie;
  VerifiedPhoto? _recto;
  VerifiedPhoto? _verso;
  VerifiedPhoto? _garage;
  IdentityStatus? _statut;
  bool _chargement = true;
  bool _envoi = false;

  bool get _transport => _statut?.estTransport ?? false;

  @override
  void initState() {
    super.initState();
    _numero.addListener(() => setState(() {}));
    _charger();
  }

  @override
  void dispose() {
    _numero.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final s = await _service.statut();
    if (!mounted) return;
    setState(() {
      _statut = s;
      _chargement = false;
    });
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), duration: const Duration(seconds: 6)),
  );

  bool get _numeroOk =>
      RegExp(r'^[A-Za-z0-9\- ]{4,30}$').hasMatch(_numero.text.trim());

  List<bool> get _etapes => [
    _type != null,
    _numeroOk,
    _recto?.check.ok ?? false,
    if (_type?.avecVerso ?? false) _verso?.check.ok ?? false,
    _selfie?.check.ok ?? false,
    _garage?.check.ok ?? false,
  ];

  bool get _pret => _etapes.every((e) => e);

  Future<void> _envoyer() async {
    if (!_pret || _envoi) return;
    FocusScope.of(context).unfocus();
    setState(() => _envoi = true);
    try {
      await _service.soumettre(
        type: _type!,
        numero: _numero.text,
        selfie: _selfie!,
        recto: _recto!,
        verso: _type!.avecVerso ? _verso : null,
        garage: _garage!,
        description: _description.text,
      );
      if (!mounted) return;
      _msg('Dossier envoyé. Vous serez prévenu dès sa validation.');
      // L'app conducteur revient à son profil, l'app Pro au sien.
      context.go(
        AppFlavor.current.isDriver ? '/driver/profile' : '/provider/profile',
      );
    } on IdentityException catch (e) {
      if (mounted) _msg(e.message);
    } on UploadException catch (e) {
      if (mounted) _msg(e.message);
    } catch (_) {
      if (mounted) _msg('Erreur réseau. Réessayez.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final etapes = _etapes;
    final faites = etapes.where((e) => e).length;
    final refuse =
        _statut?.statutValidation == 'rejected' &&
        (_statut?.motifRefus ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Vérification d\'identité')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ContentWidth(
                maxWidth: 760,
                child: AbsorbPointer(
                  absorbing: _envoi,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      const AuthInfoBanner(
                        title: 'Pourquoi cette étape ?',
                        message:
                            'Les clients veulent être sûrs que vous êtes un vrai '
                            'professionnel. Votre dossier est vérifié par notre équipe.',
                        icon: Icons.verified_user_outlined,
                        color: AppTheme.primaryColor,
                      ),
                      if (refuse) ...[
                        const SizedBox(height: 12),
                        AuthErrorBanner(
                          message: 'Dossier refusé : ${_statut!.motifRefus}',
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '$faites sur ${etapes.length} étapes terminées',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: faites / etapes.length,
                          minHeight: 10,
                          backgroundColor: scheme.onSurface.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ),
                      const SectionTitle('1. Votre pièce d\'identité'),
                      AdaptiveGrid(
                        minItemWidth: 280,
                        maxColumns: 2,
                        spacing: 10,
                        children: [
                          for (final t in IdDocumentType.values)
                            _TypeTile(
                              type: t,
                              selected: _type == t,
                              onTap: () => setState(() {
                                _type = t;
                                if (!t.avecVerso) _verso = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Numéro du document',
                        hint: 'Tel qu\'il est écrit sur la pièce',
                        icon: Icons.pin_outlined,
                        controller: _numero,
                        maxLength: 30,
                        textInputAction: TextInputAction.done,
                      ),
                      const SectionTitle('2. Photos de la pièce'),
                      AdaptiveGrid(
                        minItemWidth: 320,
                        maxColumns: 2,
                        spacing: 12,
                        children: [
                          VerifiedPhotoField(
                            label: _type == IdDocumentType.passeport
                                ? 'Passeport : page avec la photo'
                                : 'Document : recto (face avec la photo)',
                            consigne:
                                'Posez le document à plat sur une table claire, en '
                                'pleine lumière, sans reflet. Tout le document doit '
                                'être visible et le texte lisible.',
                            icon: Icons.badge_outlined,
                            photo: _recto,
                            analyser: (b) =>
                                _quality.analyserDocument(b, recto: true),
                            onChanged: (p) => setState(() => _recto = p),
                          ),
                          if (_type?.avecVerso ?? false)
                            VerifiedPhotoField(
                              label: 'Document : verso (face arrière)',
                              consigne:
                                  'Retournez le document et prenez-le en '
                                  'photo de la même façon.',
                              icon: Icons.flip_rounded,
                              photo: _verso,
                              analyser: (b) =>
                                  _quality.analyserDocument(b, recto: false),
                              onChanged: (p) => setState(() => _verso = p),
                            ),
                        ],
                      ),
                      const SectionTitle('3. Votre visage'),
                      VerifiedPhotoField(
                        label: 'Photo de votre visage',
                        consigne:
                            'Tenez le téléphone à hauteur des yeux. Visage entier '
                            'visible, de face, sans lunettes de soleil ni casquette, '
                            'face à la lumière. Vous seul sur la photo.',
                        icon: Icons.face_rounded,
                        photo: _selfie,
                        cameraOnly: true,
                        frontCamera: true,
                        analyser: _quality.analyserSelfie,
                        onChanged: (p) => setState(() => _selfie = p),
                      ),
                      SectionTitle(
                        _transport ? '4. Votre véhicule' : '4. Votre garage',
                      ),
                      VerifiedPhotoField(
                        label: _transport
                            ? 'Photo de votre moto ou tricycle'
                            : 'Photo de votre garage ou atelier',
                        consigne: _transport
                            ? 'Photographiez votre véhicule en entier, de côté, '
                                  'en pleine lumière. La plaque doit être visible si '
                                  'possible.'
                            : 'Prenez la façade ou l\'intérieur de votre '
                                  'atelier, avec l\'enseigne si possible.',
                        icon: _transport
                            ? Icons.two_wheeler_rounded
                            : Icons.store_mall_directory_outlined,
                        photo: _garage,
                        analyser: _quality.analyserLieu,
                        onChanged: (p) => setState(() => _garage = p),
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: _transport
                            ? 'Présentation (facultatif)'
                            : 'Présentation du garage (facultatif)',
                        hint: _transport
                            ? 'Zone de travail, expérience…'
                            : 'Services, horaires, expérience…',
                        icon: Icons.notes_outlined,
                        controller: _description,
                        maxLines: 4,
                        maxLength: 500,
                      ),
                      const SizedBox(height: 22),
                      AppButton(
                        label: 'Envoyer mon dossier',
                        icon: Icons.send_rounded,
                        loading: _envoi,
                        onPressed: _pret ? _envoyer : null,
                      ),
                      if (!_pret)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Le bouton s\'active quand les étapes ci-dessus sont terminées.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      const SizedBox(height: 6),
                      AppButton(
                        label: 'Continuer plus tard',
                        variant: AppButtonVariant.text,
                        onPressed: () => context.go(
                          AppFlavor.current.isDriver
                              ? '/driver/profile'
                              : '/provider/profile',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final IdDocumentType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          color: selected ? scheme.primary.withValues(alpha: 0.09) : null,
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.badge_outlined, color: scheme.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                type.libelle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? scheme.primary : null,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
