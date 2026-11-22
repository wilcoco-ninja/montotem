import 'devise.dart';

export 'devise.dart' show Devise, Money, MoneyFormat, ArrondiMode;

/// Couche d'affichage multi-devise cote client : resolution de la devise de
/// la zone (miroir de la table PostgreSQL `zones`) et formatage des montants
/// en unites entieres, jamais en double flottant.
///
/// La devise est dictee par la zone / pays du service (XOF a Cotonou,
/// Abomey-Calavi, Porto-Novo ; NGN a Lagos ; KES a Nairobi...), jamais par un
/// taux de change calcule cote client. Le montant definitif reste calcule par
/// le serveur : cette couche ne fait qu'afficher, dans la devise de la zone,
/// des montants deja exprimes en unites de cette devise (FCFA entiers
/// aujourd'hui : le XOF n'a pas de centimes).
class MontantLocal {
  MontantLocal._();

  /// Devise de la zone pour une course / prestation passee ou a venir.
  ///
  /// [ville] : ville de prise en charge quand elle est connue du parcours
  /// client (profil, adresse, geocodage). `null` ou ville non repertoriee
  /// dans les zones -> XOF (defaut projet, jamais un taux cote client).
  static Devise deCourse({String? ville}) => Devise.depuisVille(ville);

  /// Formate un montant entier (unites majeures de la devise : FCFA entiers,
  /// nairas entiers...) dans la devise de la zone.
  ///
  /// Exemples :
  /// - formater(2500, devise: Devise.xof) => "2 500 FCFA" ;
  /// - formater(2500, devise: Devise.ngn) => "2 500,00 ₦".
  static String formater(int montantUnites, {Devise? devise}) {
    final d = devise ?? Devise.defaut;
    return Money.depuisParties(montantUnites, 0, d).formatter();
  }

  /// Formate un montant deja exprime en unites mineures (kobo, cents...).
  /// Usage rare cote client : reserve aux champs renvoyes par le serveur
  /// explicitement en unites mineures, jamais via un nombre a virgule flottante.
  static String formaterMinor(int montantMinor, {Devise? devise}) {
    final d = devise ?? Devise.defaut;
    return Money.zero(d).fromMinor(montantMinor).formatter();
  }
}
