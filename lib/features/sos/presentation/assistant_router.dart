import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pointe vers le bon assistant selon le bouton cliqué.
Future<void> ouvrirAssistantPanne(BuildContext context) async {
  context.push('/assistant/panne');
}

Future<void> ouvrirAssistantCourse(BuildContext context) async {
  context.push('/assistant/course');
}
