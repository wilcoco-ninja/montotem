/// Rôles proposés à l'inscription. La valeur circule dans l'URL (?role=...).
class RegistrationRole {
  RegistrationRole._();

  static const String client = 'client';
  static const String provider = 'provider';

  static bool isValid(String? role) => role == client || role == provider;

  /// Retourne le rôle s'il est connu, sinon null.
  static String? parse(String? role) => isValid(role) ? role : null;

  /// Formulaire d'inscription du rôle (sélecteur de rôle si inconnu).
  static String formRoute(String? role) => switch (role) {
        'provider' => '/register/provider',
        'client' => '/register/client',
        _ => '/register/role',
      };

  /// Ajoute ?role=... à un chemin quand le rôle est connu.
  static String withRole(String path, String? role) =>
      isValid(role) ? '$path?role=$role' : path;
}
