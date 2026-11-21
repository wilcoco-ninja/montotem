
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/emergency/data/emergency_actions.dart';
import 'package:montotem/features/emergency/data/emergency_connectivity.dart';
import 'package:montotem/features/emergency/data/emergency_numbers_repository.dart';
import 'package:montotem/features/emergency/data/emergency_places_repository.dart';
import 'package:montotem/features/emergency/data/emergency_preparation.dart';
import 'package:montotem/features/emergency/domain/emergency_models.dart';

/// SOS : situation, questions, choix du service, confirmation, appel.
/// Aucun appel n'est lancÃƒÂ© sans que l'utilisateur l'ait confirmÃƒÂ©.
/// Aucun compte requis, aucune requÃƒÂªte rÃƒÂ©seau nÃƒÂ©cessaire.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key, this.initialType});

  /// Ouvre directement les questions d'une situation (ex. accident de la route).
  final EmergencyType? initialType;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _Etape { choix, questions, resume }

class _SosScreenState extends State<SosScreen> {
  final EmergencyNumbersRepository _numeros =
      EmergencyNumbersRepository.instance;
  final EmergencyPlacesRepository _lieux = EmergencyPlacesRepository.instance;

  _Etape _etape = _Etape.choix;
  EmergencyType? _type;
  int _index = 0;
  final Map<String, Reponse> _reponses = {};
  SosPlan? _plan;

  Position? _pos;
  bool _horsLigne = false;
  StreamSubscription<bool>? _connSub;
  String? _contact;
  String? _appelLance;

  ResolutionPays get _resolution =>
      _numeros.resolution(lat: _pos?.latitude, lng: _pos?.longitude);

  @override
  void initState() {
    super.initState();
    final t = widget.initialType;
    if (t != null) {
      _type = t;
      _etape = _Etape.questions;
    }
    _numeros.init().then((_) {
      if (mounted) setState(() {});
    });
    _lieux.charger().then((_) {
      if (mounted) setState(() {});
    });
    SosContactStore.lire().then((c) {
      if (mounted) setState(() => _contact = c);
    });
    estHorsLigne().then((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _connSub = horsLigneStream().listen((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _localiser();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _localiser() async {
    final d = await SosLocator.derniere();
    if (mounted && d != null) setState(() => _pos = d);
    final a = await SosLocator.actuelle();
    if (mounted && a != null) {
      setState(() => _pos = a);
      unawaited(EmergencyPreparation.lancer(LatLng(a.latitude, a.longitude)));
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // Ã¢â€â‚¬Ã¢â€â‚¬ DÃƒÂ©roulement Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _choisir(EmergencyType t) {
    setState(() {
      _type = t;
      _index = 0;
      _reponses.clear();
      _etape = _Etape.questions;
    });
  }

  void _repondre(Reponse r) {
    final qs = kQuestions[_type!]!;
    _reponses[qs[_index].id] = r;
    if (_index + 1 < qs.length) {
      setState(() => _index++);
    } else {
      _terminer();
    }
  }

  void _terminer() {
    setState(() {
      _plan = evaluer(_type!, _reponses);
      _appelLance = null;
      _etape = _Etape.resume;
    });
  }

  void _surRetour() {
    switch (_etape) {
      case _Etape.choix:
        Navigator.maybePop(context);
      case _Etape.questions:
        if (_index > 0) {
          setState(() => _index--);
        } else {
          setState(() => _etape = _Etape.choix);
        }
      case _Etape.resume:
        setState(() => _etape = _Etape.choix);
    }
  }

  /// Demande toujours confirmation : le client dÃƒÂ©cide.
  Future<void> _confirmerEtAppeler(String libelle, String numero) async {
    final res = _resolution;
    final pays = res.pays;
    final attention = <String>[
      if (res.ambigu && !res.choisi)
        'Vous ÃƒÂªtes prÃƒÂ¨s d\'une frontiÃƒÂ¨re : vÃƒÂ©rifiez le pays (${pays.nom}).',
      if (pays.confiance == Confiance.aConfirmer && pays.code != '--')
        'NumÃƒÂ©ro ÃƒÂ  confirmer pour ${pays.nom}. Si l\'appel n\'aboutit pas, '
            'essayez le 112.',
    ];

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer l\'appel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appeler le $numero ?',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(libelle, style: const TextStyle(fontSize: 18)),
            for (final a in attention)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(a,
                    style: TextStyle(
                        fontSize: 15.5,
                        height: 1.35,
                        color:
                            ctx.readable(Theme.of(ctx).colorScheme.tertiary))),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Oui, appeler'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final lance = await appelerNumero(numero);
    if (!mounted) return;
    setState(() => _appelLance = lance
        ? 'Appel du $numero lancÃƒÂ©. Si la communication est coupÃƒÂ©e, rappelez.'
        : null);
    if (!lance) {
      _msg('Impossible de lancer l\'appel. Composez le $numero ÃƒÂ  la main.');
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Position, proche, pays Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<bool> _definirContact() async {
    final c = TextEditingController(text: _contact ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PrÃƒÂ©venir un proche'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            labelText: 'NumÃƒÂ©ro du proche',
            hintText: '+229 01 97 00 00 00',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    c.dispose();
    if (res == null || res.isEmpty) return false;
    await SosContactStore.ecrire(res);
    if (mounted) setState(() => _contact = res);
    return true;
  }

  Future<void> _sms() async {
    if (_contact == null && !await _definirContact()) return;
    final ok = await envoyerPositionSms(
      contact: _contact!,
      situation: _type?.libelle ?? 'urgence',
      lat: _pos?.latitude,
      lng: _pos?.longitude,
    );
    if (!ok && mounted) _msg('Impossible d\'ouvrir l\'application de SMS.');
  }

  Future<void> _copier() async {
    final p = _pos;
    if (p == null) return;
    await Clipboard.setData(ClipboardData(
        text:
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'));
    if (mounted) _msg('CoordonnÃƒÂ©es copiÃƒÂ©es.');
  }

  Future<void> _confirmerPays(CountryNumbers c) async {
    await _numeros.choisirPays(c.code,
        lat: _pos?.latitude, lng: _pos?.longitude);
    if (mounted) setState(() {});
  }

  void _changerPays() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shrinkWrap: true,
        children: [
          const Text('Pays des secours',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _ligneChoixPays(
              ctx, null, 'DÃƒÂ©tection automatique', 'Selon votre position GPS'),
          for (final p in _numeros.pays)
            _ligneChoixPays(
              ctx,
              p.code,
              p.nom,
              'Police ${p.police} Ã‚Â· Pompiers ${p.fire} Ã‚Â· Urgences ${p.ambulance}'
              '${p.confiance == Confiance.officiel ? '' : ' Ã‚Â· ÃƒÂ  confirmer'}',
            ),
          _ligneChoixPays(ctx, '--', 'NumÃƒÂ©ro international',
              'Appel du 112 (fonctionne sur de nombreux rÃƒÂ©seaux)'),
        ],
      ),
    );
  }

  Widget _ligneChoixPays(
      BuildContext ctx, String? code, String titre, String sous) {
    final actif = _numeros.choixManuel == code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () async {
          await _numeros.choisirPays(code,
              lat: _pos?.latitude, lng: _pos?.longitude);
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) setState(() {});
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(sous,
                      style: TextStyle(
                          fontSize: 14.5, color: context.textSecondary)),
                ],
              ),
            ),
            Icon(actif
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded),
          ],
        ),
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ UI Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    final res = _resolution;
    final pays = res.pays;
    return PopScope(
      canPop: _etape == _Etape.choix,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _surRetour();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SOS Urgence'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Retour',
            onPressed: _surRetour,
          ),
        ),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 960,
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(context.gutter, 4, context.gutter, 32),
              children: [
                if (_horsLigne) _banniereHorsLigne(),
                _lignePays(res),
                const SizedBox(height: 8),
                if (_etape == _Etape.questions)
                  ContentWidth(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _questions(),
                    ),
                  )
                else
                  ...switch (_etape) {
                    _Etape.choix => _choix(pays),
                    _Etape.resume => _resume(pays),
                    _Etape.questions => const <Widget>[],
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _banniereHorsLigne() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              color: context.readable(scheme.tertiary), size: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Hors ligne : le SOS fonctionne quand mÃƒÂªme. Les appels passent '
              'par le rÃƒÂ©seau tÃƒÂ©lÃƒÂ©phonique.',
              style: TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lignePays(ResolutionPays res) {
    final scheme = Theme.of(context).colorScheme;
    final pays = res.pays;
    final avertissement = context.readable(scheme.tertiary);

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded,
                  size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pays des secours',
                        style: TextStyle(
                            fontSize: 14, color: context.textSecondary)),
                    Text(pays.nom,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              TextButton(onPressed: _changerPays, child: const Text('Changer')),
            ],
          ),
          if (res.ambigu && !res.choisi) ...[
            const SizedBox(height: 8),
            Text('Vous ÃƒÂªtes prÃƒÂ¨s d\'une frontiÃƒÂ¨re : confirmez votre pays.',
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: avertissement)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in res.candidats)
                  ChoiceChip(
                    label: Text(c.nom, style: const TextStyle(fontSize: 16)),
                    selected: c.code == pays.code,
                    onSelected: (_) => _confirmerPays(c),
                  ),
              ],
            ),
          ],
          if (pays.code == '--')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Pays non reconnu : choisissez-le pour appeler le bon service.',
                  style: TextStyle(fontSize: 14.5, color: avertissement)),
            )
          else if (pays.confiance == Confiance.recoupe)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'NumÃƒÂ©ros recoupÃƒÂ©s entre plusieurs sources publiques, pas encore '
                  'confirmÃƒÂ©s par l\'autoritÃƒÂ© nationale.',
                  style: TextStyle(fontSize: 14, color: context.textSecondary)),
            )
          else if (pays.confiance == Confiance.aConfirmer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'NumÃƒÂ©ros ÃƒÂ  confirmer pour ce pays : vÃƒÂ©rifiez avant d\'appeler.',
                  style: TextStyle(fontSize: 14.5, color: avertissement)),
            ),
        ],
      ),
    );
  }

  List<Widget> _choix(CountryNumbers pays) {
    return [
      const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 6),
        child: Text('Quelle est votre urgence ?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'RÃƒÂ©pondez ÃƒÂ  quelques questions, puis vous choisirez qui appeler. '
          'Rien n\'est appelÃƒÂ© sans votre confirmation.',
          style: TextStyle(
              fontSize: 16, height: 1.4, color: context.textSecondary),
        ),
      ),
      AdaptiveGrid(
        minItemWidth: 300,
        maxColumns: 2,
        spacing: 12,
        children: [
          for (final t in EmergencyType.values)
            _TuileUrgence(type: t, onTap: () => _choisir(t)),
        ],
      ),
      const SectionTitle('Vous connaissez dÃƒÂ©jÃƒÂ  le numÃƒÂ©ro ?'),
      AdaptiveGrid(
        minItemWidth: 260,
        maxColumns: 3,
        spacing: 10,
        children: [
          for (final k in ServiceKind.values)
            AppButton(
              label: '${k.libelle} : ${pays.numero(k)}',
              icon: Icons.call_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () => _confirmerEtAppeler(k.libelle, pays.numero(k)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Ce bouton prÃƒÂ©pare l\'appel au service de secours officiel de votre '
        'pays. MONTOTEM n\'est pas un service de secours.',
        style: TextStyle(
            fontSize: 14.5, height: 1.4, color: context.textSecondary),
      ),
    ];
  }

  List<Widget> _questions() {
    final type = _type!;
    final qs = kQuestions[type]!;
    final q = qs[_index];
    final scheme = Theme.of(context).colorScheme;

    return [
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(type.icone, color: type.couleur, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(type.libelle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text('Question ${_index + 1} sur ${qs.length}',
          style: TextStyle(fontSize: 15.5, color: context.textSecondary)),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _index / qs.length,
          minHeight: 10,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      const SizedBox(height: 22),
      Text(q.texte,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w800, height: 1.25)),
      const SizedBox(height: 24),
      AppButton(
        label: 'Oui',
        icon: Icons.check_rounded,
        onPressed: () => _repondre(Reponse.oui),
      ),
      const SizedBox(height: 12),
      AppButton(
        label: 'Non',
        icon: Icons.close_rounded,
        variant: AppButtonVariant.secondary,
        onPressed: () => _repondre(Reponse.non),
      ),
      const SizedBox(height: 12),
      AppButton(
        label: 'Je ne sais pas',
        variant: AppButtonVariant.text,
        onPressed: () => _repondre(Reponse.nsp),
      ),
      const SizedBox(height: 18),
      Divider(color: scheme.onSurface.withValues(alpha: 0.14)),
      const SizedBox(height: 12),
      AppButton(
        label: 'Passer les questions',
        icon: Icons.skip_next_rounded,
        variant: AppButtonVariant.secondary,
        onPressed: _terminer,
      ),
    ];
  }

  Widget? _avertissementNumeros(ResolutionPays res) {
    if (res.ambigu && !res.choisi) {
      return _carteConsigne(
          'Vous ÃƒÂªtes prÃƒÂ¨s d\'une frontiÃƒÂ¨re : confirmez votre pays en haut de '
          'l\'ÃƒÂ©cran avant d\'appeler.');
    }
    if (res.pays.confiance == Confiance.aConfirmer && res.pays.code != '--') {
      return _carteConsigne(
          'NumÃƒÂ©ros ÃƒÂ  confirmer pour ${res.pays.nom}. VÃƒÂ©rifiez le numÃƒÂ©ro avant '
          'd\'appeler. Si l\'appel n\'aboutit pas, essayez le numÃƒÂ©ro gÃƒÂ©nÃƒÂ©ral '
          'ou le 112.');
    }
    return null;
  }

  List<Widget> _resume(CountryNumbers pays) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan!;
    final avert = _avertissementNumeros(_resolution);
    const ordre = [ServiceKind.ambulance, ServiceKind.police, ServiceKind.fire];
    final general = pays.general ?? '112';

    return [
      const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 6),
        child: Text('Que voulez-vous faire ?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      ),
      Text(
        'C\'est vous qui dÃƒÂ©cidez. Rien n\'est appelÃƒÂ© sans votre confirmation.',
        style: TextStyle(
            fontSize: 16.5, height: 1.4, color: context.textSecondary),
      ),
      const SizedBox(height: 14),
      if (avert != null) ...[avert, const SizedBox(height: 12)],
      if (_appelLance != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.secondary.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: context.readable(scheme.secondary), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_appelLance!,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.35)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      AdaptiveGrid(
        minItemWidth: 280,
        maxColumns: 3,
        spacing: 12,
        children: [
          for (final k in ordre)
            _CarteService(
              kind: k,
              numero: pays.numero(k),
              suggere: plan.suggeres.contains(k),
              onAppeler: () => _confirmerEtAppeler(k.libelle, pays.numero(k)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (pays.confiance == Confiance.aConfirmer)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppButton(
            label: 'Essayer le numÃƒÂ©ro gÃƒÂ©nÃƒÂ©ral : $general',
            icon: Icons.call_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _confirmerEtAppeler('NumÃƒÂ©ro gÃƒÂ©nÃƒÂ©ral', general),
          ),
        ),
      if (plan.consigne != null) ...[
        _carteConsigne(plan.consigne!),
      ],
      const SectionTitle('Ce que vous pouvez dire ÃƒÂ  l\'opÃƒÂ©rateur'),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ligne in plan.aDire) _puce(ligne),
            if (_pos != null)
              _puce(
                'Ma position : latitude ${_pos!.latitude.toStringAsFixed(5)}, '
                'longitude ${_pos!.longitude.toStringAsFixed(5)}.',
              ),
          ],
        ),
      ),
      const SectionTitle('Ma position'),
      _cartePosition(),
      const SectionTitle('Secours les plus proches'),
      AdaptiveGrid(
        minItemWidth: 320,
        maxColumns: 3,
        spacing: 10,
        children: [for (final k in ordre) _carteProche(k)],
      ),
      const SizedBox(height: 10),
      AppButton(
        label: 'Recommencer',
        icon: Icons.refresh_rounded,
        variant: AppButtonVariant.text,
        onPressed: () => setState(() => _etape = _Etape.choix),
      ),
    ];
  }

  Widget _puce(String texte) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.chevron_right_rounded, size: 22),
          ),
          Expanded(
            child:
                Text(texte, style: const TextStyle(fontSize: 17, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _carteConsigne(String texte) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: context.readable(scheme.primary), size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texte,
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _cartePosition() {
    final p = _pos;
    return SoftCard(
      child: p == null
          ? const Row(
              children: [
                SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Recherche de votre position GPSÃ¢â‚¬Â¦',
                      style: TextStyle(fontSize: 16.5)),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Latitude : ${p.latitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800)),
                Text('Longitude : ${p.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800)),
                Text('PrÃƒÂ©cision : environ ${p.accuracy.round()} m',
                    style:
                        TextStyle(fontSize: 15, color: context.textSecondary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Copier',
                        icon: Icons.copy_rounded,
                        variant: AppButtonVariant.secondary,
                        onPressed: _copier,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: 'SMS ÃƒÂ  un proche',
                        icon: Icons.sms_outlined,
                        onPressed: _sms,
                      ),
                    ),
                  ],
                ),
                if (_contact != null)
                  TextButton(
                    onPressed: _definirContact,
                    child: Text('Proche enregistrÃƒÂ© : $_contact (changer)'),
                  ),
              ],
            ),
    );
  }

  Widget _carteProche(ServiceKind kind) {
    final p = _pos;
    if (p == null) {
      return SoftCard(
        child: Row(
          children: [
            Icon(kind.icone, color: kind.couleur, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  '${kind.libelleLieu} : disponible dÃƒÂ¨s que votre position est trouvÃƒÂ©e.',
                  style: const TextStyle(fontSize: 15.5)),
            ),
          ],
        ),
      );
    }
    final res = _lieux.plusProches(LatLng(p.latitude, p.longitude),
        kind: kind, limite: 1);
    if (res.isEmpty) {
      return SoftCard(
        onTap: () => context.push('/emergency'),
        child: Row(
          children: [
            Icon(kind.icone, color: kind.couleur, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${kind.libelleLieu} : aucun ÃƒÂ©tablissement enregistrÃƒÂ©. Ouvrez les '
                'services d\'urgence avec internet pour prÃƒÂ©parer votre zone.',
                style: const TextStyle(fontSize: 15.5, height: 1.35),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }
    final r = res.first;
    return SoftCard(
      onTap: () => context.push('/emergency/route', extra: r.lieu),
      child: Row(
        children: [
          Icon(kind.icone, color: kind.couleur, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.lieu.nom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                Text(
                    '${r.km.toStringAsFixed(1)} km ÃƒÂ  vol d\'oiseau Ã‚Â· ItinÃƒÂ©raire',
                    style:
                        TextStyle(fontSize: 15, color: context.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _TuileUrgence extends StatelessWidget {
  const _TuileUrgence({required this.type, required this.onTap});

  final EmergencyType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Semantics(
      button: true,
      label: type.libelle,
      child: Material(
        color: type.couleur,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(type.icone, color: Colors.white, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type.libelle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(type.description,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un service de secours : numÃƒÂ©ro et bouton d'appel (avec confirmation).
class _CarteService extends StatelessWidget {
  const _CarteService({
    required this.kind,
    required this.numero,
    required this.suggere,
    required this.onAppeler,
  });

  final ServiceKind kind;
  final String numero;
  final bool suggere;
  final VoidCallback onAppeler;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kind.couleur.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(kind.icone, color: kind.couleur, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.libelle,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('NumÃƒÂ©ro : $numero',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: context.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (suggere)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: 'Utile d\'aprÃƒÂ¨s vos rÃƒÂ©ponses',
                  color: kind.couleur,
                  icon: Icons.info_outline_rounded,
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAppeler,
            icon: const Icon(Icons.call_rounded, size: 26),
            label: Text('Appeler le $numero'),
            style: FilledButton.styleFrom(
              backgroundColor: kind.couleur,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
