
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/provider/data/image_quality_service.dart';

/// Photo avec contrÃƒÂ´le de qualitÃƒÂ© immÃƒÂ©diat et consignes en gros caractÃƒÂ¨res.
class VerifiedPhotoField extends StatefulWidget {
  const VerifiedPhotoField({
    super.key,
    required this.label,
    required this.consigne,
    required this.icon,
    required this.photo,
    required this.analyser,
    required this.onChanged,
    this.cameraOnly = false,
    this.frontCamera = false,
  });

  final String label;
  final String consigne;
  final IconData icon;
  final VerifiedPhoto? photo;
  final Future<PhotoCheck> Function(Uint8List bytes) analyser;
  final ValueChanged<VerifiedPhoto?> onChanged;

  /// Pas de galerie (photo du visage) : ÃƒÂ©vite l'envoi d'une photo d'un tiers.
  final bool cameraOnly;
  final bool frontCamera;

  @override
  State<VerifiedPhotoField> createState() => _VerifiedPhotoFieldState();
}

class _VerifiedPhotoFieldState extends State<VerifiedPhotoField> {
  bool _analyse = false;

  Future<void> _prendre(ImageSource source) async {
    if (_analyse) return;
    setState(() => _analyse = true);
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice:
            widget.frontCamera ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 90,
        maxWidth: 2000,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final check = await widget.analyser(bytes);
      if (!mounted) return;
      widget.onChanged(VerifiedPhoto(bytes: bytes, check: check));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de charger la photo. RÃƒÂ©essayez.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _analyse = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = widget.photo;
    final ok = photo?.check.ok ?? false;
    final couleur = photo == null
        ? scheme.onSurface.withValues(alpha: 0.25)
        : (ok ? scheme.secondary : scheme.error);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(widget.consigne,
              style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.85))),
          const SizedBox(height: 14),
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: couleur, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: _analyse
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Analyse de la photoÃ¢â‚¬Â¦',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  )
                : photo == null
                    ? Center(
                        child: Icon(widget.icon,
                            size: 72,
                            color: scheme.onSurface.withValues(alpha: 0.35)),
                      )
                    : Image.memory(photo.bytes,
                        fit: BoxFit.contain, gaplessPlayback: true),
          ),
          const SizedBox(height: 12),
          if (photo != null && !_analyse) _resultat(photo.check),
          const SizedBox(height: 12),
          if (widget.cameraOnly || kIsWeb)
            AppButton(
              label: photo == null ? 'Prendre la photo' : 'Reprendre la photo',
              icon: Icons.photo_camera_rounded,
              onPressed: _analyse ? null : () => _prendre(ImageSource.camera),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: photo == null ? 'Appareil photo' : 'Reprendre',
                    icon: Icons.photo_camera_rounded,
                    onPressed:
                        _analyse ? null : () => _prendre(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Galerie',
                    icon: Icons.photo_library_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed:
                        _analyse ? null : () => _prendre(ImageSource.gallery),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultat(PhotoCheck c) {
    final scheme = Theme.of(context).colorScheme;
    if (c.ok) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: scheme.secondary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Photo de bonne qualitÃƒÂ©',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.readable(scheme.secondary))),
              ),
            ],
          ),
          if (!c.visageControle)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Le visage sera contrÃƒÂ´lÃƒÂ© par notre ÃƒÂ©quipe.',
                style: TextStyle(fontSize: 15),
              ),
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photo ÃƒÂ  refaire',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scheme.error)),
          const SizedBox(height: 8),
          for (final p in c.problemes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 22, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p,
                        style: const TextStyle(fontSize: 16, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
