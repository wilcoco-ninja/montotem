import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// SÃƒÂ©lecteur de photo Ã¢â‚¬â€ le parent est la source de vÃƒÂ©ritÃƒÂ© via [bytes].
/// Le widget ne conserve en interne que l'ÃƒÂ©tat "en cours de sÃƒÂ©lection".
class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.bytes,
  });

  final String label;
  final IconData icon;
  final ValueChanged<Uint8List?> onChanged;
  final Uint8List? bytes;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  bool _isPicking = false;

  Future<void> _choisir() async {
    final source = await _afficherMenuSource();
    if (source == null || !mounted) return;
    await _pick(source);
  }

  Future<ImageSource?> _afficherMenuSource() {
    final colorScheme = Theme.of(context).colorScheme;

    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choisir la source',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.photo_camera_outlined,
                iconColor: colorScheme.primary,
                title: 'Prendre une photo',
                subtitle: kIsWeb
                    ? 'Utiliser la camÃƒÂ©ra du navigateur'
                    : 'Prendre une nouvelle photo',
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.photo_library_outlined,
                iconColor: colorScheme.secondary,
                title: 'Choisir dans la galerie',
                subtitle: kIsWeb
                    ? 'SÃƒÂ©lectionner un fichier'
                    : 'Choisir une photo existante',
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Future<void> _pick(ImageSource source) async {
    setState(() => _isPicking = true);
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (xfile == null) {
        if (mounted) setState(() => _isPicking = false);
        return;
      }

      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      setState(() => _isPicking = false);

      developer.log(
        '${widget.label} Ã¢â€ â€™ ${bytes.length} bytes',
        name: 'PhotoPickerField',
      );
      widget.onChanged(bytes);
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() => _isPicking = false);

      developer.log(
        'Erreur lors de la sÃƒÂ©lection/lecture de la photo',
        name: 'PhotoPickerField',
        error: e,
        stackTrace: stackTrace,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de charger la photo. Veuillez rÃƒÂ©essayer.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _supprimerPhoto() {
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: bytes == null
          ? 'Ajouter : ${widget.label}'
          : 'Modifier : ${widget.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isPicking ? null : _choisir,
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: bytes == null
                  ? theme.dividerColor
                  : theme.colorScheme.primary,
              width: 2,
            ),
            color: bytes == null
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  )
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: _isPicking
              ? const Center(child: CircularProgressIndicator())
              : bytes != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, size: 36),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _supprimerPhoto,
                          borderRadius: BorderRadius.circular(12),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.error.withValues(
                              alpha: 0.9,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Appuyez pour ajouter',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
