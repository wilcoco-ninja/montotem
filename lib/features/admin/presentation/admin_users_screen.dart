
import 'package:flutter/material.dart';

import 'package:montotem/core/models/app_user.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/admin/data/admin_service.dart';

/// Module d'administration pour la consultation et la recherche d'utilisateurs.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AdminService _adminService = AdminService();
  List<AppUser> _users = [];
  String _recherche = '';
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _chargerUtilisateurs();
  }

  Future<void> _chargerUtilisateurs({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _users.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final users = await _adminService.obtenirUtilisateurs();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de charger la liste des utilisateurs.';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  List<AppUser> get _utilisateursFiltres {
    final q = _recherche.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      return (u.name ?? '').toLowerCase().contains(q) ||
          (u.firstName ?? '').toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q) ||
          u.role.value.contains(q);
    }).toList();
  }

  Color _couleurRole(UserRole role) {
    final scheme = Theme.of(context).colorScheme;
    return switch (role) {
      UserRole.admin => Colors.deepPurple,
      UserRole.provider => scheme.onSecondary,
      UserRole.client => scheme.primary,
    };
  }

  String _libelleRole(UserRole role) => switch (role) {
        UserRole.admin => 'Admin',
        UserRole.provider => 'Prestataire',
        UserRole.client => 'Client',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annuaire des Utilisateurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : () => _chargerUtilisateurs(),
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
              child: TextField(
                onChanged: (v) => setState(() => _recherche = v),
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom, tÃƒÂ©lÃƒÂ©phone ou rÃƒÂ´le...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_utilisateursFiltres.length} utilisateur(s) trouvÃƒÂ©(s)',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ),
            Expanded(child: _buildCorps()),
          ],
        ),
      ),
    );
  }

  Widget _buildCorps() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(
              message: _errorMessage!, onRetry: () => _chargerUtilisateurs()),
        ),
      );
    }

    if (_users.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _chargerUtilisateurs(silencieux: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'Aucun utilisateur enregistrÃƒÂ©',
            ),
          ],
        ),
      );
    }

    final liste = _utilisateursFiltres;

    return RefreshIndicator(
      onRefresh: () => _chargerUtilisateurs(silencieux: true),
      child: liste.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Aucun rÃƒÂ©sultat pour cette recherche',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: liste.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final u = liste[index];
                final couleur = _couleurRole(u.role);
                final nom = u.name ?? u.phone;
                final initiale = nom.isNotEmpty ? nom[0].toUpperCase() : '?';

                return SoftCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: couleur.withValues(alpha: 0.15),
                        child: Text(
                          initiale,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: couleur),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              u.phone,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: _libelleRole(u.role),
                        color: couleur,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
