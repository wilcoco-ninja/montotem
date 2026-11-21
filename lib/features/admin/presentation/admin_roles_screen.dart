
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';

class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  final SupabaseClient _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _admins = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _chargerAdmins();
  }

  Future<void> _chargerAdmins({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _admins.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final response = await _sb
          .from('profiles')
          .select(
              'id, first_name, last_name, phone, email, admin_role, is_super_admin, created_at')
          .eq('is_admin', true)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _admins = (response as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur lors du chargement de lÃ¢â‚¬â„¢ÃƒÂ©quipe admin : $e';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _afficherMessage(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(texte, style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: erreur
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _creerOuModifierAdmin(
      {Map<String, dynamic>? adminExistant}) async {
    final isNew = adminExistant == null;
    final idAdmin = adminExistant?['id'] as String?;
    final emailController =
        TextEditingController(text: adminExistant?['email'] as String? ?? '');
    final prenomController = TextEditingController(
        text: adminExistant?['first_name'] as String? ?? '');
    final nomController = TextEditingController(
        text: adminExistant?['last_name'] as String? ?? '');
    final telController =
        TextEditingController(text: adminExistant?['phone'] as String? ?? '');
    final passwordController = TextEditingController();

    String roleSelectionne =
        (adminExistant?['admin_role'] as String?) ?? 'support';

    final rolesDisponibles = {
      'support': 'Support & Signalements (Client/Prestataire)',
      'finance': 'Finances & Validation Mobile Money',
      'validator': 'Validation des Dossiers Prestataires',
      'supervisor': 'Superviseur GÃƒÂ©nÃƒÂ©ral (Tour de contrÃƒÂ´le)',
      'super_admin': 'Administrateur Principal (AccÃƒÂ¨s total)',
    };

    final resultat = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isNew ? 'CrÃƒÂ©er un nouveau poste admin' : 'Modifier le rÃƒÂ´le admin',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isNew) ...[
                    AppTextField(
                      label: 'Email professionnel',
                      icon: Icons.email_outlined,
                      controller: emailController,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Mot de passe initial (8+ caractÃƒÂ¨res)',
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: passwordController,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'PrÃƒÂ©nom',
                          icon: Icons.person_outline,
                          controller: prenomController,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          label: 'Nom',
                          icon: Icons.person_outline,
                          controller: nomController,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'TÃƒÂ©lÃƒÂ©phone (optionnel)',
                    icon: Icons.phone_outlined,
                    controller: telController,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),
                  const Text('RÃƒÂ´le et permissions de lÃ¢â‚¬â„¢ÃƒÂ©quipe :',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: roleSelectionne,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: rolesDisponibles.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value,
                            style: const TextStyle(fontSize: 13.5)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => roleSelectionne = val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Annuler', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final prenom = prenomController.text.trim();
                final nom = nomController.text.trim();

                if (isNew &&
                    (email.isEmpty || passwordController.text.length < 8)) {
                  _afficherMessage(
                      'Email et mot de passe (8+ car.) obligatoires.',
                      erreur: true);
                  return;
                }

                try {
                  if (isNew) {
                    final authRes = await _sb.auth.signUp(
                      email: email,
                      password: passwordController.text,
                      data: {
                        'first_name': prenom,
                        'last_name': nom,
                        'is_admin': true,
                        'admin_role': roleSelectionne
                      },
                    );
                    if (authRes.user == null) {
                      throw Exception('Ãƒâ€°chec de crÃƒÂ©ation du compte auth.');
                    }
                  } else if (idAdmin != null) {
                    await _sb.from('profiles').update({
                      'first_name': prenom,
                      'last_name': nom,
                      'phone': telController.text.trim(),
                      'admin_role': roleSelectionne,
                      'is_super_admin': roleSelectionne == 'super_admin',
                    }).eq('id', idAdmin);
                  }

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                  await _chargerAdmins(silencieux: true);
                  _afficherMessage(isNew
                      ? 'Compte admin crÃƒÂ©ÃƒÂ© avec succÃƒÂ¨s.'
                      : 'RÃƒÂ´le mis ÃƒÂ  jour.');
                } catch (e) {
                  _afficherMessage('Erreur : $e', erreur: true);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    prenomController.dispose();
    nomController.dispose();
    telController.dispose();
    passwordController.dispose();

    if (resultat == true) await _chargerAdmins(silencieux: true);
  }

  Future<void> _revoquerAdmin(Map<String, dynamic> admin) async {
    final prenom = admin['first_name'] as String? ?? '';
    final nom = admin['last_name'] as String? ?? '';
    final nomComplet = '$prenom $nom'.trim();
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('RÃƒÂ©voquer les accÃƒÂ¨s de $nomComplet ?',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Cet utilisateur ne pourra plus se connecter au tableau de bord administrateur de MonTotem.',
          style: TextStyle(fontSize: 14.5, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('RÃƒÂ©voquer lÃ¢â‚¬â„¢accÃƒÂ¨s'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    try {
      await _sb.from('profiles').update({
        'is_admin': false,
        'admin_role': null,
        'is_super_admin': false,
      }).eq('id', admin['id'] as Object);

      _afficherMessage('AccÃƒÂ¨s admin rÃƒÂ©voquÃƒÂ© pour $nomComplet.');
      await _chargerAdmins(silencieux: true);
    } catch (e) {
      _afficherMessage('Erreur lors de la rÃƒÂ©vocation : $e', erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ãƒâ€°quipe Administrative & Postes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'CrÃƒÂ©er un nouveau poste admin',
            onPressed: () => _creerOuModifierAdmin(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : () => _chargerAdmins(),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 900,
        child: Column(
          children: [
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildCorps()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _creerOuModifierAdmin(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau poste admin'),
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
              message: _errorMessage!, onRetry: () => _chargerAdmins()),
        ),
      );
    }

    if (_admins.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _chargerAdmins(silencieux: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Aucun administrateur secondaire',
              message:
                  'CrÃƒÂ©ez des postes administratifs pour dÃƒÂ©lÃƒÂ©guer la gestion de MonTotem.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _chargerAdmins(silencieux: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: _admins.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _carteAdmin(_admins[index]),
      ),
    );
  }

  Widget _carteAdmin(Map<String, dynamic> admin) {
    final scheme = Theme.of(context).colorScheme;
    final prenom = (admin['first_name'] as String?) ?? '';
    final nom = (admin['last_name'] as String?) ?? '';
    final nomComplet = '$prenom $nom'.trim();
    final role = (admin['admin_role'] as String?) ?? 'support';
    final estSuperAdmin = admin['is_super_admin'] == true;

    final libelleRole = switch (role) {
      'finance' => 'Finances & MoMo',
      'validator' => 'Validation Prestataires',
      'supervisor' => 'Superviseur Tour de ContrÃƒÂ´le',
      'super_admin' => 'Administrateur Principal',
      _ => 'Support Client & Signalements',
    };

    final couleurRole = switch (role) {
      'finance' => scheme.secondary,
      'validator' => scheme.primary,
      'supervisor' => Colors.teal,
      'super_admin' => AppColors.gold,
      _ => Colors.blueGrey,
    };

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: couleurRole.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              estSuperAdmin
                  ? Icons.star_rounded
                  : Icons.admin_panel_settings_rounded,
              color: couleurRole,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomComplet.isEmpty
                      ? ((admin['email'] as String?) ?? 'Admin')
                      : nomComplet,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  (admin['email'] as String?) ??
                      (admin['phone'] as String?) ??
                      '',
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                StatusPill(label: libelleRole, color: couleurRole),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'edit') {
                _creerOuModifierAdmin(adminExistant: admin);
              } else if (val == 'revoke') {
                _revoquerAdmin(admin);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'edit', child: Text('Modifier le poste')),
              if (!estSuperAdmin)
                PopupMenuItem(
                  value: 'revoke',
                  child: Text('RÃƒÂ©voquer lÃ¢â‚¬â„¢accÃƒÂ¨s',
                      style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
