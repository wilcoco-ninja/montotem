import 'package:supabase_flutter/supabase_flutter.dart';

class SkillException implements Exception {
  const SkillException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProviderSkill {
  const ProviderSkill({required this.id, required this.label});
  final String id;
  final String label;
}

class ProviderSkillsService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<List<ProviderSkill>> lister() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _sb
          .from('provider_skills')
          .select('id,label')
          .eq('provider_id', uid)
          .order('created_at');
      return rows
          .map<ProviderSkill>(
            (r) => ProviderSkill(id: '${r['id']}', label: '${r['label']}'),
          )
          .toList();
    } on PostgrestException {
      throw const SkillException('Impossible de charger vos compétences.');
    }
  }

  Future<void> ajouter(String label) async {
    try {
      await _sb.rpc('add_provider_skill', params: {'p_label': label});
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('COMPETENCE_INVALIDE')) {
        throw const SkillException('Écrivez entre 2 et 60 caractères.');
      }
      if (m.contains('TROP_DE_COMPETENCES')) {
        throw const SkillException('Maximum 30 compétences.');
      }
      if (m.contains('PAS_PRESTATAIRE')) {
        throw const SkillException('Dossier prestataire introuvable.');
      }
      throw const SkillException('Impossible d\'ajouter la compétence.');
    }
  }

  Future<void> supprimer(String id) async {
    try {
      await _sb.rpc('remove_provider_skill', params: {'p_id': id});
    } on PostgrestException {
      throw const SkillException('Impossible de supprimer la compétence.');
    }
  }
}
