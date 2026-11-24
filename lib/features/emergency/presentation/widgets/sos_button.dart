import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const Color _rougeSos = Color(0xFFC62828);

/// Petit bouton SOS pour les barres d'application. [type] ouvre directement
/// les questions d'une situation (ex. `accident`).
class SosAppBarButton extends StatelessWidget {
  const SosAppBarButton({super.key, this.type});

  final String? type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilledButton.icon(
        onPressed: () =>
            context.push(type == null ? '/sos' : '/sos?type=$type'),
        icon: const Icon(Icons.emergency_rounded, size: 22),
        label: const Text('SOS'),
        style: FilledButton.styleFrom(
          backgroundColor: _rougeSos,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

/// Grande bannière SOS pour les pages d'accueil.
class SosBanner extends StatelessWidget {
  const SosBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      label: 'Urgence vitale, ouvrir le SOS',
      child: Material(
        color: _rougeSos,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => context.push('/sos'),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.emergency_rounded, color: Colors.white, size: 44),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Urgence vitale ?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Accident, pompiers, police, ambulance : appuyez ici',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lien discret pour les écrans de connexion et d'inscription.
class SosLink extends StatelessWidget {
  const SosLink({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.push('/sos'),
      icon: const Icon(Icons.emergency_rounded, size: 22),
      label: const Text('Urgence ? SOS'),
      style: TextButton.styleFrom(
        foregroundColor: _rougeSos,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}
