
import 'package:flutter/material.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/report_motifs.dart';

Future<void> showReportProviderSheet(
  BuildContext context, {
  required String providerId,
  String? missionId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ReportSheet(providerId: providerId, missionId: missionId),
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.providerId, this.missionId});
  final String providerId;
  final String? missionId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final MissionService _service = MissionService();
  final TextEditingController _details = TextEditingController();
  String? _motif;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final motif = _motif;
    if (motif == null) return;
    setState(() => _sending = true);
    try {
      await _service.signaler(
        providerId: widget.providerId,
        missionId: widget.missionId,
        motif: motif,
        details: _details.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Signalement envoyÃƒÂ©. L\'ÃƒÂ©quipe MONTOTEM va l\'examiner.'),
        duration: Duration(seconds: 6),
      ));
    } on MissionException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const Text('Signaler ce prestataire',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Choisissez le motif. Votre signalement est confidentiel.',
              style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.8))),
          const SizedBox(height: 16),
          for (final m in kReportMotifs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                onTap: () => setState(() => _motif = m.code),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    color: _motif == m.code
                        ? scheme.primary.withValues(alpha: 0.09)
                        : null,
                    border: Border.all(
                      color: _motif == m.code
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.2),
                      width: _motif == m.code ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(m.icone, color: scheme.primary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.libelle,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(m.aide,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                      Icon(
                        _motif == m.code
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: _motif == m.code ? scheme.primary : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _details,
            maxLines: 4,
            maxLength: 1000,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Que s\'est-il passÃƒÂ© ? (facultatif)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Envoyer le signalement',
            icon: Icons.flag_rounded,
            variant: AppButtonVariant.danger,
            loading: _sending,
            onPressed: _motif == null ? null : _envoyer,
          ),
        ],
      ),
    );
  }
}
