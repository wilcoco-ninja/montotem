import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/power/power_mode_controller.dart';
import '../../../core/services/distress_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/totem_icons.dart';

/// KIT DE SURVIE EN PANNE Ã¢â‚¬â€ route `/survie` (publique, sans compte).
///
/// Cet ÃƒÂ©cran est volontairement 100 % statique : aucun appel rÃƒÂ©seau, aucune
/// image ÃƒÂ  charger, aucune police ÃƒÂ  tÃƒÂ©lÃƒÂ©charger. Il s'ouvre donc instantanÃƒÂ©ment
/// mÃƒÂªme sans internet, sous l'orage, la nuit, avec 3 % de batterie.
/// Il est toujours sombre (noir OLED = ÃƒÂ©conomie de batterie + pas
/// d'ÃƒÂ©blouissement la nuit).
class SurvivalKitScreen extends StatefulWidget {
  const SurvivalKitScreen({super.key});

  @override
  State<SurvivalKitScreen> createState() => _SurvivalKitScreenState();
}

class _SurvivalKitScreenState extends State<SurvivalKitScreen> {
  final _contact = TextEditingController();
  bool _contactEnregistre = false;

  @override
  void initState() {
    super.initState();
    DistressService.contact().then((v) {
      if (!mounted) return;
      setState(() {
        _contact.text = v;
        _contactEnregistre = v.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _enregistrerContact() async {
    FocusScope.of(context).unfocus();
    await DistressService.enregistrerContact(_contact.text);
    if (!mounted) return;
    setState(() => _contactEnregistre = _contact.text.trim().isNotEmpty);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _contactEnregistre
              ? 'Contact de confiance enregistrÃƒÂ© sur ce tÃƒÂ©lÃƒÂ©phone.'
              : 'Contact supprimÃƒÂ©.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final power = context.watch<PowerModeController>();

    return Theme(
      data: AppTheme.darkTheme,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Kit de survie en panne'),
              leading: IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/explore'),
              ),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  // Ã¢â€â‚¬Ã¢â€â‚¬ Bandeau d'ÃƒÂ©tat Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  _EtatTelephone(power: power),
                  const SizedBox(height: 16),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Action nÃ‚Â°1 : la plus importante Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  _GrosBoutonSos(
                    onTap: () =>
                        DistressService.envoyerDetresse(context, power),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Le SMS part par le rÃƒÂ©seau tÃƒÂ©lÃƒÂ©phonique : il marche mÃƒÂªme sans '
                    'internet. Le GPS du tÃƒÂ©lÃƒÂ©phone marche aussi sans internet.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Contact de confiance Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  _Bloc(
                    titre: 'Contact de confiance',
                    icone: Icons.favorite_rounded,
                    enfant: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Le SMS de dÃƒÂ©tresse s\'adressera directement ÃƒÂ  cette '
                          'personne. EnregistrÃƒÂ© sur ce tÃƒÂ©lÃƒÂ©phone uniquement.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _contact,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+ ]'),
                            ),
                          ],
                          maxLength: 20,
                          decoration: InputDecoration(
                            labelText: 'NumÃƒÂ©ro (ex. +229 01 97 00 00 00)',
                            counterText: '',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            suffixIcon: _contactEnregistre
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: scheme.secondary,
                                  )
                                : null,
                          ),
                          onSubmitted: (_) => _enregistrerContact(),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _enregistrerContact,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('ENREGISTRER'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Balise lumineuse (nuit) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  _Bloc(
                    titre: 'Balise lumineuse',
                    icone: Icons.flashlight_on_rounded,
                    enfant: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'L\'ÃƒÂ©cran clignote en plein ÃƒÂ©cran pour ÃƒÂªtre vu de loin '
                          'la nuit. Consomme de la batterie : ÃƒÂ  utiliser '
                          'seulement quand des vÃƒÂ©hicules approchent.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => const _BaliseScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.flash_on_rounded),
                          label: const Text('ALLUMER LA BALISE'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°conomie d'ÃƒÂ©nergie Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  _Bloc(
                    titre: 'Ãƒâ€°conomie d\'ÃƒÂ©nergie',
                    icone: Icons.battery_saver_rounded,
                    enfant: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: power.ecoManuel,
                      onChanged: (v) => power.definirEcoManuel(v),
                      title: const Text(
                        'Mode ÃƒÂ©co MonTotem',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'Fond noir pur, animations coupÃƒÂ©es. S\'active seul ÃƒÂ  20 % '
                        'de batterie.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ TÃƒÂ©lÃƒÂ©phone qui va s'ÃƒÂ©teindre Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  const _TitreSection(
                    'Votre tÃƒÂ©lÃƒÂ©phone va s\'ÃƒÂ©teindre ?',
                  ),
                  const _Fiche(
                    icone: Icons.battery_alert_rounded,
                    titre: 'Les 6 gestes qui sauvent la batterie',
                    ouverte: true,
                    etapes: [
                      'Envoyez votre position par SMS MAINTENANT (bouton jaune '
                          'en haut), pendant qu\'il reste de la batterie.',
                      'Activez le mode ÃƒÂ©co MonTotem et l\'ÃƒÂ©conomiseur de batterie '
                          'du tÃƒÂ©lÃƒÂ©phone.',
                      'Baissez la luminositÃƒÂ© au minimum. Fermez les applications '
                          'ouvertes. Ãƒâ€°vitez vidÃƒÂ©o et GPS en continu.',
                      'Sans rÃƒÂ©seau, le tÃƒÂ©lÃƒÂ©phone s\'ÃƒÂ©puise ÃƒÂ  chercher du signal : '
                          'passez en mode avion et ne le quittez que pour envoyer '
                          'un message ou passer un appel.',
                      'Notez sur papier (ou dites ÃƒÂ  quelqu\'un) le numÃƒÂ©ro de votre '
                          'contact et celui du dÃƒÂ©panneur.',
                      'Gardez le tÃƒÂ©lÃƒÂ©phone ÃƒÂ  l\'ombre, pas en plein soleil sur le '
                          'tableau de bord.',
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Situations Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  const _TitreSection('Selon votre situation'),
                  const _Fiche(
                    icone: Icons.nightlight_round,
                    titre: 'En panne la nuit',
                    etapes: [
                      'Allumez les feux de dÃƒÂ©tresse et garez-vous le plus loin '
                          'possible de la circulation.',
                      'Sortez du cÃƒÂ´tÃƒÂ© opposÃƒÂ© ÃƒÂ  la route et attendez derriÃƒÂ¨re le '
                          'vÃƒÂ©hicule ou le talus, jamais devant les phares.',
                      'Rendez-vous visible : vÃƒÂªtement clair ou rÃƒÂ©flÃƒÂ©chissant, '
                          'lampe du tÃƒÂ©lÃƒÂ©phone par intermittence seulement.',
                      'Ne montez pas dans un vÃƒÂ©hicule inconnu. Restez prÃƒÂ¨s d\'un '
                          'endroit ÃƒÂ©clairÃƒÂ© ou habitÃƒÂ© si vous en voyez un.',
                      'PrÃƒÂ©venez une personne de confiance avec votre position.',
                    ],
                  ),
                  const _Fiche(
                    icone: Icons.thunderstorm_rounded,
                    titre: 'Pluie forte, orage, inondation',
                    etapes: [
                      'Ne traversez jamais une route inondÃƒÂ©e, ÃƒÂ  pied ou en '
                          'vÃƒÂ©hicule : environ 15 cm d\'eau qui court peuvent faire '
                          'tomber un adulte, et 30 cm suffisent ÃƒÂ  emporter une '
                          'voiture.',
                      'Pendant l\'orage, ÃƒÂ©loignez-vous des arbres isolÃƒÂ©s, des '
                          'poteaux et des fils ÃƒÂ©lectriques tombÃƒÂ©s.',
                      'En moto ou en zÃƒÂ©midjan : abritez-vous sous un auvent solide '
                          '(station-service, bÃƒÂ¢timent), pas sous un arbre.',
                      'ProtÃƒÂ©gez le tÃƒÂ©lÃƒÂ©phone de l\'eau (sac plastique) et coupez '
                          'les applications inutiles.',
                    ],
                  ),
                  const _Fiche(
                    icone: Icons.add_road_rounded,
                    titre: 'Route rapide ou forte circulation',
                    etapes: [
                      'Feux de dÃƒÂ©tresse, rangez-vous le plus ÃƒÂ  droite possible.',
                      'Tous les passagers sortent cÃƒÂ´tÃƒÂ© opposÃƒÂ© ÃƒÂ  la circulation et '
                          'attendent ÃƒÂ  l\'ÃƒÂ©cart de la chaussÃƒÂ©e.',
                      'Si vous avez un triangle, placez-le bien en arriÃƒÂ¨re du '
                          'vÃƒÂ©hicule (environ 30 m, davantage sur voie rapide).',
                      'Ne rÃƒÂ©parez jamais sur la voie. Appelez un dÃƒÂ©panneur.',
                    ],
                  ),
                  const _Fiche(
                    icone: Icons.tire_repair_rounded,
                    titre: 'Pneu crevÃƒÂ©',
                    etapes: [
                      'Roulez le moins possible sur la jante : cherchez un sol '
                          'plat et dur, frein ÃƒÂ  main serrÃƒÂ©.',
                      'Ne vous placez pas cÃƒÂ´tÃƒÂ© circulation pour changer la roue.',
                      'Pas de roue de secours ? Appelez un vulcanisateur proche : '
                          'bouton Ã‚Â« Trouver un dÃƒÂ©panneur Ã‚Â» ci-dessous.',
                    ],
                  ),
                  const _Fiche(
                    icone: Icons.car_repair_rounded,
                    titre: 'Moteur qui ne dÃƒÂ©marre plus, batterie',
                    etapes: [
                      'N\'insistez pas sur le dÃƒÂ©marreur : de courts essais de '
                          'quelques secondes, avec des pauses.',
                      'FumÃƒÂ©e, odeur de brÃƒÂ»lÃƒÂ© ou d\'essence : ÃƒÂ©loignez-vous du '
                          'vÃƒÂ©hicule, n\'ouvrez pas le capot, pas de flamme ni de '
                          'cigarette. Appelez les secours depuis l\'ÃƒÂ©cran SOS.',
                      'Coupez radio, climatisation et feux inutiles pour garder '
                          'la batterie du vÃƒÂ©hicule.',
                    ],
                  ),
                  const _Fiche(
                    icone: Icons.wb_sunny_rounded,
                    titre: 'Forte chaleur',
                    etapes: [
                      'Cherchez l\'ombre, buvez rÃƒÂ©guliÃƒÂ¨rement de petites quantitÃƒÂ©s '
                          'd\'eau.',
                      'Ne laissez jamais un enfant ou un animal dans un vÃƒÂ©hicule '
                          'fermÃƒÂ©, mÃƒÂªme quelques minutes.',
                      'Malaise, vertiges, confusion : appelez les secours tout de '
                          'suite depuis l\'ÃƒÂ©cran SOS.',
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Script pour le dÃƒÂ©panneur Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  const _TitreSection('Quoi dire au dÃƒÂ©panneur'),
                  const _Script(),
                  const SizedBox(height: 24),

                  // Ã¢â€â‚¬Ã¢â€â‚¬ Sorties Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emergencyStrong,
                      foregroundColor: AppColors.navyOnDark,
                    ),
                    onPressed: () => context.push('/sos'),
                    icon: TotemIcon(
                      TotemGlyph.sos,
                      size: 30,
                      accent: AppColors.navyOnDark,
                    ),
                    label: const Text('NUMÃƒâ€°ROS D\'URGENCE Ã‚Â· SOS'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/explore'),
                    icon: TotemIcon(
                      TotemGlyph.depannage,
                      size: 28,
                      color: AppColors.brandYellow,
                    ),
                    label: const Text('TROUVER UN DÃƒâ€°PANNEUR'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Ãƒâ€°lÃƒÂ©ments d'interface Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _EtatTelephone extends StatelessWidget {
  const _EtatTelephone({required this.power});
  final PowerModeController power;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final batterie = power.batterieConnue ? '${power.niveau} %' : 'inconnue';
    final critique = power.alerte == PowerLevel.critical;

    Widget puce({
      required Widget icone,
      required String titre,
      required String valeur,
      Color? couleur,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              icone,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      valeur,
                      style: TextStyle(
                        color: couleur ?? scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        puce(
          icone: TotemIcon(
            TotemGlyph.batterie,
            size: 34,
            color: scheme.onSurface,
            accent: scheme.primary,
            level: power.batterieConnue ? power.niveau / 100 : 1,
          ),
          titre: power.enCharge ? 'Batterie Ã‚Â· en charge' : 'Batterie',
          valeur: batterie,
          couleur: critique ? AppColors.emergencyTextDark : null,
        ),
        const SizedBox(width: 10),
        puce(
          icone: power.horsLigne
              ? TotemIcon(
                  TotemGlyph.horsLigne,
                  size: 30,
                  color: scheme.onSurface,
                  accent: AppColors.emergencyTextDark,
                )
              : Icon(Icons.network_check_rounded, color: scheme.secondary),
          titre: 'Internet',
          valeur: power.horsLigne ? 'Absent' : 'Disponible',
          couleur: power.horsLigne ? AppColors.emergencyTextDark : null,
        ),
      ],
    );
  }
}

class _GrosBoutonSos extends StatelessWidget {
  const _GrosBoutonSos({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Envoyer ma position par SMS. Fonctionne sans internet.',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.brandYellow,
        shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          customBorder: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          onTap: () {
            HapticFeedback.heavyImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Row(
              children: [
                const TotemIcon(
                  TotemGlyph.panne,
                  size: 54,
                  color: AppColors.navy,
                  accent: AppColors.navy,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ENVOYER MA POSITION',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'SMS avec GPS + batterie Ã‚Â· sans internet',
                        style: TextStyle(
                          color: AppColors.navy.withValues(alpha: 0.92),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.navy,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          texte.toUpperCase(),
          style: TextStyle(
            color: AppColors.brandYellow,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.icone, required this.enfant});
  final String titre;
  final IconData icone;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icone, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  titre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            enfant,
          ],
        ),
      ),
    );
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.icone,
    required this.titre,
    required this.etapes,
    this.ouverte = false,
  });

  final IconData icone;
  final String titre;
  final List<String> etapes;
  final bool ouverte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: ouverte,
          leading: Icon(icone, color: scheme.primary, size: 28),
          title: Text(
            titre,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          children: [
            for (var i = 0; i < etapes.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        etapes[i],
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Script extends StatelessWidget {
  const _Script();

  static const String _texte =
      'Bonjour, je suis en panne.\n'
      'OÃƒÂ¹ : [route, quartier, repÃƒÂ¨re connu]. Ma position GPS arrive par SMS.\n'
      'VÃƒÂ©hicule : [moto / voiture / tricycle].\n'
      'ProblÃƒÂ¨me : [pneu / batterie / ne dÃƒÂ©marre plus / autre].\n'
      'Mon tÃƒÂ©lÃƒÂ©phone va bientÃƒÂ´t s\'ÃƒÂ©teindre : si je ne rÃƒÂ©ponds pas, '
      'venez ÃƒÂ  la position envoyÃƒÂ©e.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(_texte, style: TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _texte));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Texte copiÃƒÂ©.')),
                );
              },
              icon: Icon(Icons.copy_rounded, color: scheme.primary),
              label: const Text('COPIER LE TEXTE'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balise lumineuse : l'ÃƒÂ©cran clignote safran / noir (1 Hz) pour signaler
/// le vÃƒÂ©hicule en panne la nuit. Garde l'ÃƒÂ©cran allumÃƒÂ© tant qu'elle est
/// ouverte ; un toucher la ferme.
class _BaliseScreen extends StatefulWidget {
  const _BaliseScreen();

  @override
  State<_BaliseScreen> createState() => _BaliseScreenState();
}

class _BaliseScreenState extends State<_BaliseScreen> {
  Timer? _timer;
  bool _allume = true;

  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable();
    } catch (_) {}
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _allume = !_allume);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _allume ? AppColors.brandYellow : scheme.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: Center(
            child: Text(
              'TOUCHEZ POUR Ãƒâ€°TEINDRE',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _allume ? AppColors.navy : AppColors.brandYellow,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
