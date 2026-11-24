import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/provider/data/provider_identity_service.dart'
    show libelleDocument;
import 'package:montotem/features/admin/data/admin_service.dart';

/// Ãƒâ€°cran de production pour la validation et l'audit des dossiers prestataires.
class AdminProvidersScreen extends StatefulWidget {
  const AdminProvidersScreen({super.key});

  @override
  State<AdminProvidersScreen> createState() => _AdminProvidersScreenState();
}

class _AdminProvidersScreenState extends State<AdminProvidersScreen> {
  final AdminService _adminService = AdminService();

  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _pendingOnly = false;
  String? _errorMessage;
  String? _actionEnCoursId;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _providers.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final providers = await _adminService.obtenirPrestatairesBrut(
        pendingOnly: _pendingOnly,
      );
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Ãƒâ€°chec du chargement des prestataires : $e';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _changerFiltre(bool pendingOnly) {
    if (pendingOnly == _pendingOnly) return;
    setState(() => _pendingOnly = pendingOnly);
    _chargerDonnees();
  }

  void _afficherMessage(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            texte,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: erreur
              ? AppColors.emergencyStrong
              : AppColors.successText,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _approuverPrestataire(String id, String nom) async {
    setState(() => _actionEnCoursId = id);
    try {
      await _adminService.approuverPrestataire(id);
      _afficherMessage('Dossier de $nom approuvÃƒÂ© avec succÃƒÂ¨s.');
      await _chargerDonnees(silencieux: true);
    } catch (e) {
      _afficherMessage(
        'Erreur lors de lÃ¢â‚¬â„¢approbation : $e',
        erreur: true,
      );
    } finally {
      if (mounted) setState(() => _actionEnCoursId = null);
    }
  }

  Future<void> _rejeterPrestataire(String id, String nom) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rejeter le dossier de $nom ?',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Le prestataire ne pourra pas recevoir de missions sur la plateforme MonTotem. '
          'Vous pourrez rÃƒÂ©ÃƒÂ©valuer ou lÃ¢â‚¬â„¢approuver ultÃƒÂ©rieurement.',
          style: TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emergencyStrong,
            ),
            child: const Text('Confirmer le rejet'),
          ),
        ],
      ),
    );

    if (confirme != true || !mounted) return;

    setState(() => _actionEnCoursId = id);
    try {
      await _adminService.rejeterPrestataire(id);
      _afficherMessage('Dossier de $nom rejetÃƒÂ©.', erreur: true);
      await _chargerDonnees(silencieux: true);
    } catch (e) {
      _afficherMessage('Erreur : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCoursId = null);
    }
  }

  Future<void> _appeler(String? tel) async {
    if (tel == null || tel.isEmpty) return;
    final cleanPhone = tel.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Prestataires'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : () => _chargerDonnees(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ContentWidth(
        maxWidth: 900,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Tous les prestataires'),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('En attente de validation'),
                  ),
                ],
                selected: {_pendingOnly},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _changerFiltre(s.first),
              ),
            ),
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildCorps()),
          ],
        ),
      ),
    );
  }

  Widget _buildCorps() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(
            message: _errorMessage!,
            onRetry: () => _chargerDonnees(),
          ),
        ),
      );
    }

    if (_providers.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _chargerDonnees(silencieux: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.verified_user_outlined,
              title: _pendingOnly
                  ? 'Aucun dossier en attente'
                  : 'Aucun prestataire enregistrÃƒÂ©',
              message: 'Les inscriptions de prestataires sÃ¢â‚¬â„¢afficheront ici en temps rÃƒÂ©el.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _chargerDonnees(silencieux: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _providers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _construireCartePrestataire(_providers[index]),
      ),
    );
  }

  Widget _avatar(String? url, {double size = 56}) {
    final placeholder = Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.person_outline, color: Colors.grey),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }

  Widget _construireCartePrestataire(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final user = (p['user'] as Map<String, dynamic>?) ?? {};
    final isApproved = (user['is_approved'] as bool?) ?? false;
    final businessName = (p['business_name'] as String?) ?? '';
    final metier = (p['metier'] as String?) ?? '';
    final ville = (p['ville'] as String?) ?? '';

    final phone = (user['phone'] as String?) ?? '';
    final firstName = (user['first_name'] as String?) ?? '';
    final lastName = (user['last_name'] as String?) ?? '';
    final photoProfil = user['photo_profil_url'] as String?;

    final nomAffiche = businessName.isNotEmpty
        ? businessName
        : '$firstName $lastName'.trim().isNotEmpty
        ? '$firstName $lastName'.trim()
        : phone;

    final enCours = _actionEnCoursId == id;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return SoftCard(
      onTap: () => _afficherFicheDetaillee(p),
      child: Row(
        children: [
          _avatar(photoProfil),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomAffiche,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metier.isNotEmpty ? metier : 'MÃƒÂ©tier non spÃƒÂ©cifiÃƒÂ©',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.7),
                    fontSize: 13.5,
                  ),
                ),
                if (ville.isNotEmpty)
                  Text(
                    ville,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  ),
                const SizedBox(height: 8),
                StatusPill(
                  label: isApproved
                      ? 'ApprouvÃƒÂ©'
                      : 'En attente de validation',
                  color: isApproved ? scheme.secondary : scheme.error,
                  icon: isApproved
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (enCours)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton.filledTonal(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Examiner le dossier complet',
              onPressed: () => _afficherFicheDetaillee(p),
            ),
        ],
      ),
    );
  }

  Widget _blocImage(String? url, double height, String messageErreur) {
    if (url == null || url.isEmpty) {
      return Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Aucun document fourni',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) => SizedBox(
          height: height,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 40,
                color: Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(messageErreur, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  String _analyserControles(dynamic checks) {
    if (checks is! Map || checks.isEmpty) return '';
    const noms = {
      'selfie': 'Visage',
      'recto': 'PiÃƒÂ¨ce dÃ¢â‚¬â„¢identitÃƒÂ© (recto)',
      'verso': 'PiÃƒÂ¨ce dÃ¢â‚¬â„¢identitÃƒÂ© (verso)',
      'garage': 'Garage / Atelier',
    };
    final lignes = <String>[];
    for (final e in noms.entries) {
      final c = checks[e.key];
      if (c is! Map) continue;
      final visages = c['faces'] == null ? '' : ', visages : ${c['faces']}';
      lignes.add(
        '${e.value} : nettetÃƒÂ© ${c['sharpness'] ?? '-'}, '
        'luminositÃƒÂ© ${c['brightness'] ?? '-'}$visages',
      );
    }
    return lignes.join('\n');
  }

  void _afficherFicheDetaillee(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final user = (p['user'] as Map<String, dynamic>?) ?? {};
    final isApproved = (user['is_approved'] as bool?) ?? false;
    final businessName = (p['business_name'] as String?) ?? '';
    final metier = (p['metier'] as String?) ?? '';
    final ifu = (p['ifu'] as String?) ?? '';
    final ville = (p['ville'] as String?) ?? '';
    final email = (user['email'] as String?) ?? '';
    final phone = (user['phone'] as String?) ?? '';
    final firstName = (user['first_name'] as String?) ?? '';
    final lastName = (user['last_name'] as String?) ?? '';
    final photoProfil = user['photo_profil_url'] as String?;
    final photoCni = p['photo_cni_url'] as String?;
    final lat = (p['latitude'] as num?)?.toDouble();
    final lng = (p['longitude'] as num?)?.toDouble();

    final docType = p['id_document_type'] as String?;
    final docNumero = (p['id_document_number'] as String?) ?? '';
    final photoCniVerso = p['photo_cni_back_url'] as String?;
    final photoGarage = p['photo_garage_url'] as String?;
    final descGarage = (p['garage_description'] as String?) ?? '';
    final controles = _analyserControles(p['id_checks']);
    final identiteComplete = p['identity_submitted_at'] != null;

    final nomAffiche = businessName.isNotEmpty
        ? businessName
        : '$firstName $lastName'.trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  nomAffiche.isEmpty ? 'Dossier Prestataire' : nomAffiche,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: isApproved ? 'ApprouvÃƒÂ©' : 'En attente',
                    color: isApproved ? scheme.secondary : scheme.error,
                    icon: isApproved
                        ? Icons.verified_rounded
                        : Icons.hourglass_top_rounded,
                  ),
                ),
                const SectionTitle('Photo de profil'),
                _blocImage(photoProfil, 180, 'Impossible de charger la photo'),
                const SectionTitle('PiÃƒÂ¨ce dÃ¢â‚¬â„¢identitÃƒÂ© officielle'),
                if (!identiteComplete)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Attention : Le dossier dÃ¢â‚¬â„¢identitÃƒÂ© nÃ¢â‚¬â„¢est pas complÃƒÂ¨tement soumis.',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.error,
                      ),
                    ),
                  ),
                InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Type de piÃƒÂ¨ce',
                  value: docType == null ? '' : libelleDocument(docType),
                ),
                InfoRow(
                  icon: Icons.pin_outlined,
                  label: 'NumÃƒÂ©ro',
                  value: docNumero,
                ),
                const SizedBox(height: 8),
                _blocImage(photoCni, 200, 'Recto introuvable'),
                if (photoCniVerso != null && photoCniVerso.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _blocImage(photoCniVerso, 200, 'Verso introuvable'),
                ],
                const SectionTitle('Garage / Atelier'),
                _blocImage(photoGarage, 180, 'Photo du garage indisponible'),
                InfoRow(
                  icon: Icons.notes_outlined,
                  label: 'Description',
                  value: descGarage,
                ),
                if (controles.isNotEmpty) ...[
                  const SectionTitle('Analyse technique automatique'),
                  Text(
                    controles,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ],
                const SectionTitle('Informations gÃƒÂ©nÃƒÂ©rales'),
                InfoRow(
                  icon: Icons.person_outline,
                  label: 'Nom complet',
                  value: '$firstName $lastName'.trim(),
                ),
                InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'TÃƒÂ©lÃƒÂ©phone',
                  value: phone,
                ),
                InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                InfoRow(
                  icon: Icons.build_outlined,
                  label: 'MÃƒÂ©tier',
                  value: metier,
                ),
                InfoRow(
                  icon: Icons.store_outlined,
                  label: 'Nom du Garage',
                  value: businessName,
                ),
                InfoRow(
                  icon: Icons.location_city_outlined,
                  label: 'Ville',
                  value: ville,
                ),
                InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'NumÃƒÂ©ro IFU',
                  value: ifu,
                ),
                if (lat != null && lng != null)
                  InfoRow(
                    icon: Icons.place_outlined,
                    label: 'CoordonnÃƒÂ©es GPS',
                    value:
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  ),
                const SizedBox(height: 28),
                if (!isApproved)
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Rejeter',
                          icon: Icons.close_rounded,
                          variant: AppButtonVariant.secondary,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _rejeterPrestataire(id, nomAffiche);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Approuver',
                          icon: Icons.check_rounded,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _approuverPrestataire(id, nomAffiche);
                          },
                        ),
                      ),
                    ],
                  )
                else
                  AppButton(
                    label: 'RÃƒÂ©voquer lÃ¢â‚¬â„¢approbation',
                    icon: Icons.block_rounded,
                    variant: AppButtonVariant.danger,
                    onPressed: () async {
                      Navigator.pop(context);
                      await _rejeterPrestataire(id, nomAffiche);
                    },
                  ),
                const SizedBox(height: 8),
                AppButton(
                  label: phone.isEmpty
                      ? 'TÃƒÂ©lÃƒÂ©phone indisponible'
                      : 'Appeler $phone',
                  icon: Icons.call_outlined,
                  variant: AppButtonVariant.text,
                  onPressed: phone.isEmpty ? null : () => _appeler(phone),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
