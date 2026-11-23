import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _updateEnv = 'ARCH_UPDATE_BASELINE';
const String _baselinePath = 'test/architecture/baseline.txt';

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Appels backend littéraux : .from('table'), .rpc('fn'), .channel('nom').
final RegExp _backendCall = RegExp(r'''\.(?:from|rpc|channel)\(\s*['"]''');

const List<String> _pureForbidden = <String>[
  'package:flutter/',
  'package:flutter_',
  'package:supabase',
  'package:dio/',
  'package:provider/',
  'package:go_router/',
];

const List<String> _backendAllowedDirs = <String>[
  'core/supabase/',
  'core/realtime/',
  'bootstrap/',
];

const List<String> _layers = <String>[
  'domain',
  'data',
  'application',
  'presentation',
];

const Map<String, Set<String>> _forbiddenLayers = <String, Set<String>>{
  'domain': <String>{'data', 'application', 'presentation'},
  'data': <String>{'application', 'presentation'},
  'application': <String>{'data', 'presentation'},
  'presentation': <String>{'data'},
};

class _Source {
  const _Source(this.path, this.content);

  final String path; // relatif à lib/
  final String content;
}

class _Violation {
  const _Violation(this.rule, this.file, this.target);

  final String rule;
  final String file;
  final String target;

  String get key => '$rule|$file|$target';
}

String _packageName() {
  final String pubspec = File('pubspec.yaml').readAsStringSync();
  final RegExpMatch? m =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  if (m == null) {
    throw StateError('Nom du package introuvable dans pubspec.yaml');
  }
  return m.group(1)!;
}

List<_Source> _readSources() {
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) {
    throw StateError('Lancer les tests depuis la racine du projet.');
  }
  final List<_Source> out = <_Source>[];
  for (final FileSystemEntity e
      in lib.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final String p = e.path.replaceAll('\\', '/');
    if (!p.endsWith('.dart') ||
        p.endsWith('.g.dart') ||
        p.endsWith('.freezed.dart')) {
      continue;
    }
    out.add(_Source(p.replaceFirst('lib/', ''), e.readAsStringSync()));
  }
  return out;
}

String _normalize(String path) {
  final List<String> out = <String>[];
  for (final String s in path.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(s);
  }
  return out.join('/');
}

/// Chemin interne relatif à lib/, ou null pour dart: et les packages externes.
String? _resolve(String pkg, String from, String raw) {
  final String prefix = 'package:$pkg/';
  if (raw.startsWith(prefix)) {
    return _normalize(raw.substring(prefix.length));
  }
  if (raw.contains(':')) return null;
  final int slash = from.lastIndexOf('/');
  final String dir = slash < 0 ? '' : from.substring(0, slash);
  return _normalize('$dir/$raw');
}

/// 'ride' pour features/services/ride/..., 'ordering' pour features/ordering/...
String? _featureKey(String p) {
  final List<String> s = p.split('/');
  if (s.length < 3 || s[0] != 'features') return null;
  if (s[1] == 'services') return s.length >= 4 ? 'services/${s[2]}' : null;
  return s[1];
}

String _publicApi(String key) => 'features/$key/${key.split('/').last}.dart';

String? _layerOf(String p) {
  final String? key = _featureKey(p);
  if (key == null) return null;
  final String rest = p.substring('features/$key/'.length);
  for (final String layer in _layers) {
    if (rest.startsWith('$layer/')) return layer;
  }
  return null;
}

bool _isDatasource(String p) =>
    RegExp(r'^features/[^/]+/data/datasources/').hasMatch(p) ||
    RegExp(r'^features/services/[^/]+/data/datasources/').hasMatch(p);

List<_Violation> _analyze(String pkg, List<_Source> sources) {
  final List<_Violation> out = <_Violation>[];

  for (final _Source s in sources) {
    final String f = s.path;
    final String? fk = _featureKey(f);
    final String? fl = _layerOf(f);

    // Appels backend uniquement dans data/datasources (et core dédié).
    if (_backendCall.hasMatch(s.content) &&
        !_isDatasource(f) &&
        !_backendAllowedDirs.any(f.startsWith)) {
      out.add(_Violation('BACKEND_CALL_OUTSIDE_DATASOURCE', f, '-'));
    }

    for (final RegExpMatch m in _directive.allMatches(s.content)) {
      final String raw = m.group(1)!;
      final String? t = _resolve(pkg, f, raw);
      final String? tk = t == null ? null : _featureKey(t);

      // Domain et shared_kernel : Dart pur.
      if ((fl == 'domain' || f.startsWith('shared_kernel/')) &&
          _pureForbidden.any(raw.startsWith)) {
        out.add(_Violation('PURE_DART', f, raw));
      }

      if (t == null) continue;

      // core/ et shared_kernel/ n'importent jamais l'application.
      if ((f.startsWith('core/') || f.startsWith('shared_kernel/')) &&
          (t.startsWith('features/') ||
              t.startsWith('apps/') ||
              t.startsWith('bootstrap/'))) {
        out.add(_Violation('CORE_DEPENDS_ON_APP', f, t));
      }
      if (f.startsWith('shared_kernel/') && t.startsWith('core/')) {
        out.add(_Violation('KERNEL_DEPENDS_ON_CORE', f, t));
      }

      if (tk != null && tk != fk) {
        // Entre features : API publique uniquement.
        if (t != _publicApi(tk)) {
          out.add(_Violation('NON_PUBLIC_IMPORT', f, t));
        }
        // Les capacités n'importent jamais les services.
        if (fk != null && !fk.startsWith('services/') &&
            tk.startsWith('services/')) {
          out.add(_Violation('CAPABILITY_IMPORTS_SERVICE', f, t));
        }
        // Les services ne se connaissent pas entre eux.
        if (fk != null && fk.startsWith('services/') &&
            tk.startsWith('services/')) {
          out.add(_Violation('SERVICE_DEPENDS_ON_SERVICE', f, t));
        }
      }

      // Sens des couches dans une même feature.
      if (tk != null && tk == fk && fl != null) {
        final String? tl = _layerOf(t);
        if (tl != null && _forbiddenLayers[fl]!.contains(tl)) {
          out.add(_Violation('LAYER_VIOLATION', f, t));
        }
      }
    }
  }
  return out;
}

Set<String> _loadBaseline() {
  final File f = File(_baselinePath);
  if (!f.existsSync()) return <String>{};
  return f
      .readAsLinesSync()
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
}

void main() {
  final String pkg = _packageName();
  final List<_Source> sources = _readSources();
  final List<_Violation> all = _analyze(pkg, sources);

  test('règles de dépendance et de couches', () {
    final Set<String> keys = all.map((_Violation v) => v.key).toSet();

    if (Platform.environment[_updateEnv] == '1') {
      Directory('test/architecture').createSync(recursive: true);
      final List<String> lines = keys.toList()..sort();
      File(_baselinePath).writeAsStringSync(
        '# Violations héritées gelées pendant la migration. '
        'Ne jamais en ajouter à la main : en retirer.\n'
        '${lines.join('\n')}\n',
      );
      return;
    }

    final Set<String> baseline = _loadBaseline();
    final Set<String> stale = baseline.difference(keys);
    if (stale.isNotEmpty) {
      // ignore: avoid_print
      print('Baseline : ${stale.length} entrée(s) résolue(s), à retirer.');
    }

    final List<_Violation> fresh =
        all.where((_Violation v) => !baseline.contains(v.key)).toList();
    if (fresh.isNotEmpty) {
      fail(
        'Nouvelles violations d\'architecture :\n'
        '${fresh.map((_Violation v) => '  [${v.rule}] ${v.file} -> ${v.target}').join('\n')}',
      );
    }
  });

  test('aucun secret dans lib/', () {
    final RegExp secrets = RegExp(
      r'service_role|sk_live_|sk_test_|R2_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY',
    );
    final List<String> hits = <String>[
      for (final _Source s in sources)
        if (secrets.hasMatch(s.content)) s.path,
    ];
    expect(hits, isEmpty, reason: 'Secrets potentiels dans : $hits');
  });
}