
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:montotem/features/requests/data/mission_service.dart';

Future<void> showMissionChatSheet(BuildContext context, String missionId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _MissionChat(missionId: missionId),
    ),
  );
}

class _MissionChat extends StatefulWidget {
  const _MissionChat({required this.missionId});

  final String missionId;

  @override
  State<_MissionChat> createState() => _MissionChatState();
}

class _MissionChatState extends State<_MissionChat> {
  final MissionService _service = MissionService();
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final texte = _controller.text.trim();
    if (texte.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.envoyerMessage(widget.missionId, texte);
      _controller.clear();
    } on MissionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final uid = _service.currentUserId;
    final disponible =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final hauteur = math.min(disponible * 0.9, 720.0);

    return SizedBox(
      height: hauteur,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Discussion',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeurMax = constraints.maxWidth * 0.78;
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _service.messages(widget.missionId),
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 40,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Aucun message. Ãƒâ€°crivez le premier.',
                              style: TextStyle(
                                fontSize: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final msg = items[items.length - 1 - i];
                        final mine = msg['sender_id'] == uid;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(maxWidth: largeurMax),
                            decoration: BoxDecoration(
                              color: mine
                                  ? scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(mine ? 18 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 18),
                              ),
                            ),
                            child: Text(
                              '${msg['body']}',
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.35,
                                color:
                                    mine ? scheme.onPrimary : scheme.onSurface,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _envoyer(),
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Votre message',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    iconSize: 26,
                    onPressed: _sending ? null : _envoyer,
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'Envoyer',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
