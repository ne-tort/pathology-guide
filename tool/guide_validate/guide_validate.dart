import 'dart:convert';
import 'dart:io';

/// Validates the bundled Guide content pack under assets/guide/.
///
/// Usage:
/// - `dart run tool/guide_validate.dart`
/// - `dart run tool/guide_validate/guide_validate.dart`
/// Usage:
/// - guide repo: `dart run tool/guide_validate.dart .` (pack at repo root)
/// - client repo: `dart run tool/guide_validate.dart` (assets/guide)
void main(List<String> args) {
  final guideDir = args.isNotEmpty
      ? Directory(args[0])
      : Directory.fromUri(Directory.current.uri.resolve('assets/guide/'));
  final errors = <String>[];

  final manifestFile = File.fromUri(guideDir.uri.resolve('manifest.json'));
  final tocFile = File.fromUri(guideDir.uri.resolve('toc.json'));
  if (!manifestFile.existsSync()) {
    errors.add('missing assets/guide/manifest.json');
  }
  if (!tocFile.existsSync()) {
    errors.add('missing assets/guide/toc.json');
  }
  if (errors.isNotEmpty) {
    _fail(errors);
  }

  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final toc = jsonDecode(tocFile.readAsStringSync()) as Map<String, dynamic>;

  final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt();
  if (schemaVersion == null) {
    errors.add('manifest.schemaVersion is required');
  } else if (schemaVersion < 1) {
    errors.add('manifest.schemaVersion must be >= 1');
  }
  for (final key in ['packId', 'version', 'minAppVersion', 'defaultLocale']) {
    final v = manifest[key];
    if (v is! String || v.isEmpty) {
      errors.add('manifest.$key is required');
    }
  }
  final localesRaw = manifest['locales'];
  if (localesRaw is! List || localesRaw.isEmpty) {
    errors.add('manifest.locales must be a non-empty list');
  }
  final locales = localesRaw is List ? localesRaw.map((e) => e.toString()).toList() : <String>[];

  final sections = toc['sections'];
  if (sections is! List || sections.isEmpty) {
    errors.add('toc.sections must be a non-empty list');
  }

  final pageIds = <String>{};
  if (sections is List) {
    for (final s in sections.whereType<Map>()) {
      final pages = s['pages'];
      if (pages is! List) continue;
      for (final p in pages.whereType<Map>()) {
        final id = p['id']?.toString();
        if (id == null || id.isEmpty) {
          errors.add('toc page missing id');
          continue;
        }
        pageIds.add(id);
      }
    }
  }

  const knownTypes = {
    'heading',
    'paragraph',
    'richText',
    'list',
    'link',
    'routeLink',
    'guideLink',
    'navTile',
    'callout',
    'icon',
    'image',
    'demoStub',
    'interactive',
    'expandable',
    'video',
    'illustration',
    'anchorRef',
  };

  const knownStubs = {
    'filledButton',
    'listTile',
    'switchListTile',
    'statusBanner',
    'preferenceTile',
    'connectionButton',
    'iconButton',
  };

  const knownInteractiveIds = {
    'serverCreateInstall',
  };

  void validateBlocks(List<dynamic> blocks, String ctx) {
    for (final b in blocks.whereType<Map>()) {
      final type = b['type']?.toString() ?? '';
      if (!knownTypes.contains(type)) {
        errors.add('$ctx: unknown block type "$type"');
      }
      if (type == 'demoStub') {
        final stub = b['stub']?.toString() ?? '';
        if (stub.isEmpty || !knownStubs.contains(stub)) {
          errors.add('$ctx: unknown or empty demoStub "$stub"');
        }
      }
      if (type == 'interactive') {
        final id = b['id']?.toString() ?? '';
        if (id.isEmpty || !knownInteractiveIds.contains(id)) {
          errors.add('$ctx: unknown or empty interactive id "$id"');
        }
      }
      if (type == 'image') {
        final src = b['src']?.toString() ?? '';
        if (src.isEmpty) {
          errors.add('$ctx: image.src is required');
        } else {
          final name = src
              .replaceFirst(RegExp(r'^/?media/'), '')
              .replaceFirst(RegExp(r'^assets/guide/media/'), '');
          final mediaFile = File.fromUri(guideDir.uri.resolve('media/$name'));
          if (!mediaFile.existsSync()) {
            errors.add('$ctx: missing media file media/$name');
          }
        }
      }
      if (type == 'anchorRef') {
        final aid = b['anchorId']?.toString() ?? '';
        if (aid.isEmpty) {
          errors.add('$ctx: anchorRef.anchorId is required');
        }
      }
      if (type == 'expandable') {
        final title = b['title']?.toString() ?? '';
        final id = b['id']?.toString() ?? '';
        final leadBlock = b['leadBlock'] == true;
        if (title.isEmpty && id.isEmpty) {
          errors.add('$ctx: expandable needs title or id');
        }
        if (leadBlock && id.isEmpty) {
          errors.add('$ctx: leadBlock expandable requires id');
        }
        final nested = b['blocks'];
        if (nested is! List) {
          errors.add('$ctx: expandable.blocks must be a list');
        } else {
          validateBlocks(nested, '$ctx>expandable');
        }
      }
    }
  }

  for (final pageId in pageIds) {
    for (final locale in locales) {
      final pageFile = File.fromUri(guideDir.uri.resolve('pages/$pageId.$locale.json'));
      if (!pageFile.existsSync()) {
        errors.add('missing page file: pages/$pageId.$locale.json');
        continue;
      }
      try {
        final page = jsonDecode(pageFile.readAsStringSync()) as Map<String, dynamic>;
        final blocks = page['blocks'];
        if (blocks is! List) {
          errors.add('$pageId.$locale: blocks must be a list');
          continue;
        }
        validateBlocks(blocks, '$pageId.$locale');
        final pageTitle = page['title']?.toString().trim() ?? '';
        var leadCount = 0;
        for (final b in blocks.whereType<Map>()) {
          if (b['type']?.toString() != 'expandable') continue;
          if (b['leadBlock'] != true) continue;
          leadCount++;
          final title = b['title']?.toString().trim() ?? '';
          final collapsed = b['collapsedTitle']?.toString().trim() ?? '';
          if (title.isEmpty && collapsed.isEmpty && pageTitle.isEmpty) {
            errors.add(
              '$pageId.$locale: leadBlock "${b['id']}" needs collapsedTitle or page title',
            );
          }
        }
        if (leadCount > 1) {
          errors.add('$pageId.$locale: at most one leadBlock expandable per page');
        }
      } catch (e) {
        errors.add('invalid JSON pages/$pageId.$locale.json: $e');
      }
    }
  }

  // Collect expandable ids per page+locale for hotspot expandableId checks.
  final expandableIds = <String, Set<String>>{};
  void collectExpandables(dynamic node, String pageKey, Set<String> out) {
    if (node is Map) {
      if (node['type']?.toString() == 'expandable') {
        final id = node['id']?.toString();
        if (id != null && id.isNotEmpty) out.add(id);
      }
      for (final v in node.values) {
        collectExpandables(v, pageKey, out);
      }
    } else if (node is List) {
      for (final e in node) {
        collectExpandables(e, pageKey, out);
      }
    }
  }

  for (final pageId in pageIds) {
    for (final locale in locales) {
      final pageFile = File.fromUri(guideDir.uri.resolve('pages/$pageId.$locale.json'));
      if (!pageFile.existsSync()) continue;
      try {
        final page = jsonDecode(pageFile.readAsStringSync()) as Map<String, dynamic>;
        final ids = <String>{};
        collectExpandables(page['blocks'], pageId, ids);
        expandableIds['$pageId.$locale'] = ids;
      } catch (_) {
        // page JSON errors already reported above
      }
    }
  }

  final hotspotsFile = File.fromUri(guideDir.uri.resolve('training/hotspots.json'));
  if (hotspotsFile.existsSync()) {
    try {
      final hotspots = jsonDecode(hotspotsFile.readAsStringSync()) as Map<String, dynamic>;
      final list = hotspots['hotspots'];
      if (list is! List) {
        errors.add('training/hotspots.json: hotspots must be a list');
      } else {
        for (final h in list.whereType<Map>()) {
          final aid = h['anchorId']?.toString() ?? '';
          if (aid.isEmpty) {
            errors.add('training/hotspots.json: hotspot missing anchorId');
            continue;
          }
          final action = h['action'];
          if (action is! Map) {
            errors.add('training/hotspots.json: $aid missing action');
            continue;
          }
          final kind = action['kind']?.toString() ?? '';
          if (kind == 'openGuidePage') {
            final target = action['pageId']?.toString() ?? '';
            if (target.isEmpty || !pageIds.contains(target)) {
              errors.add('training/hotspots.json: $aid → unknown pageId "$target"');
            }
            final exp = action['expandableId']?.toString() ?? '';
            if (exp.isNotEmpty && target.isNotEmpty) {
              for (final locale in locales) {
                final ids = expandableIds['$target.$locale'] ?? const <String>{};
                if (!ids.contains(exp)) {
                  errors.add(
                    'training/hotspots.json: $aid → missing expandableId "$exp" on $target.$locale',
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      errors.add('invalid JSON training/hotspots.json: $e');
    }
  }

  if (errors.isNotEmpty) {
    _fail(errors);
  }
  stdout.writeln('guide pack OK (${pageIds.length} pages, locales=${locales.join(",")})');
}

void _fail(List<String> errors) {
  stderr.writeln('guide_validate failed:');
  for (final e in errors) {
    stderr.writeln('  - $e');
  }
  exit(1);
}
