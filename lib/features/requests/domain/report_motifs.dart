import 'package:flutter/material.dart';

@immutable
class ReportMotif {
  const ReportMotif(this.code, this.libelle, this.aide, this.icone);
  final String code;
  final String libelle;
  final String aide;
  final IconData icone;
}

/// Les codes doivent rester identiques à la contrainte SQL de provider_reports.
const List<ReportMotif> kReportMotifs = [
  ReportMotif('violence', 'Menaces ou violence',
      'Le prestataire m\'a menacé ou agressé.', Icons.warning_amber_rounded),
  ReportMotif(
      'harcelement',
      'Harcèlement ou propos déplacés',
      'Comportement gênant, insistant ou à caractère sexuel.',
      Icons.report_gmailerrorred_rounded),
  ReportMotif(
      'insulte',
      'Insultes ou manque de respect',
      'Paroles ou attitude irrespectueuses.',
      Icons.sentiment_very_dissatisfied_rounded),
  ReportMotif(
      'discrimination',
      'Discrimination',
      'Traitement différent à cause de mon âge, mon origine ou mon genre.',
      Icons.balance_rounded),
  ReportMotif(
      'surfacturation',
      'Prix supérieur à celui annoncé',
      'Le montant demandé ne correspond pas à la grille tarifaire.',
      Icons.money_off_rounded),
  ReportMotif(
      'paiement_hors_app',
      'Paiement demandé hors de l\'application',
      'Le prestataire exige un paiement en dehors du circuit MONTOTEM.',
      Icons.payments_outlined),
  ReportMotif(
      'fraude',
      'Arnaque ou fraude',
      'Fausse panne, pièce non remplacée, faux justificatif.',
      Icons.gpp_bad_outlined),
  ReportMotif(
      'faux_profil',
      'Faux profil ou identité différente',
      'La personne venue ne correspond pas à la photo ou au profil.',
      Icons.badge_outlined),
  ReportMotif(
      'travail_mal_fait',
      'Travail mal fait',
      'La panne persiste ou la réparation est de mauvaise qualité.',
      Icons.build_circle_outlined),
  ReportMotif(
      'travail_dangereux',
      'Travail dangereux',
      'Gestes ou matériel mettant en danger ma sécurité.',
      Icons.health_and_safety_outlined),
  ReportMotif(
      'vol_dommage',
      'Vol ou dommage causé',
      'Objet disparu ou véhicule abîmé pendant l\'intervention.',
      Icons.car_crash_outlined),
  ReportMotif(
      'retard_absence',
      'Retard important ou absence',
      'Le prestataire n\'est pas venu ou est arrivé beaucoup trop tard.',
      Icons.schedule_rounded),
  ReportMotif(
      'abandon',
      'Chantier abandonné',
      'Le prestataire est parti avant la fin de la réparation.',
      Icons.exit_to_app_rounded),
  ReportMotif(
      'fausse_arrivee',
      'Fausse arrivée signalée',
      'L\'application indique « arrivé » alors qu\'il n\'est pas là.',
      Icons.wrong_location_outlined),
  ReportMotif('autre', 'Autre problème', 'Un autre motif non listé.',
      Icons.more_horiz_rounded),
];

String libelleMotif(String code) => kReportMotifs
    .firstWhere((m) => m.code == code,
        orElse: () =>
            const ReportMotif('autre', 'Autre problème', '', Icons.flag))
    .libelle;