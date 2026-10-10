import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/features/library/scan/discovered_file.dart';
import 'package:noctune/features/library/scan/library_permission.dart';
import 'package:noctune/features/library/scan/library_scanner.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Permission extends LibraryPermission {
  _Permission(this.access);

  LibraryAccess access;
  int requests = 0;

  @override
  Future<LibraryAccess> request() async {
    requests++;
    return access;
  }

  @override
  Future<LibraryAccess> check() async => access;
}

class _Source implements LibrarySource {
  Object? error;

  @override
  Future<List<DiscoveredFile>> discover() async {
    if (error case final error?) throw error;
    return const [
      DiscoveredFile(path: '/music/a.flac', sizeBytes: 1, modifiedMs: 1),
    ];
  }
}

void main() {
  late Database db;
  late _Source source;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    source = _Source();
  });

  tearDown(() => db.close());

  ProviderContainer container(_Permission permission) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        libraryPermissionProvider.overrideWithValue(permission),
        libraryScannerProvider.overrideWith(
          (ref) => LibraryScanner(
            repository: ref.watch(libraryRepositoryProvider),
            sources: [source],
            artworkDir: Directory.systemTemp.createTempSync('art').path,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('scans once access is granted', () async {
    final c = container(_Permission(LibraryAccess.granted));

    await c.read(scanControllerProvider.notifier).scan();

    final state = c.read(scanControllerProvider) as ScanIdle;
    expect(state.lastScan!.scanned, 1);
    expect(await c.read(libraryRepositoryProvider).tracks(), hasLength(1));
  });

  test('asks for access instead of scanning when it is denied', () async {
    final c = container(_Permission(LibraryAccess.denied));

    await c.read(scanControllerProvider.notifier).scan();

    final state = c.read(scanControllerProvider) as ScanNeedsPermission;
    expect(state.permanentlyDenied, isFalse);
    expect(await c.read(libraryRepositoryProvider).tracks(), isEmpty);
  });

  test('points to Settings when access is permanently denied', () async {
    final c = container(_Permission(LibraryAccess.permanentlyDenied));

    await c.read(scanControllerProvider.notifier).scan();

    final state = c.read(scanControllerProvider) as ScanNeedsPermission;
    expect(state.permanentlyDenied, isTrue);
  });

  test('the launch refresh never prompts for access', () async {
    final permission = _Permission(LibraryAccess.denied);
    final c = container(permission);

    await c.read(scanControllerProvider.notifier).refreshIfPermitted();

    expect(permission.requests, 0);
    expect(c.read(scanControllerProvider), isA<ScanIdle>());
  });

  test('the launch refresh scans when access already exists', () async {
    final c = container(_Permission(LibraryAccess.granted));

    await c.read(scanControllerProvider.notifier).refreshIfPermitted();

    expect(await c.read(libraryRepositoryProvider).tracks(), hasLength(1));
  });

  test('reports a failed media query', () async {
    source.error = PlatformException(code: 'query_failed', message: 'Boom');
    final c = container(_Permission(LibraryAccess.granted));

    await c.read(scanControllerProvider.notifier).scan();

    expect((c.read(scanControllerProvider) as ScanFailed).message, 'Boom');
  });

  test('treats a revoked permission as needing access again', () async {
    source.error = PlatformException(code: 'permission_denied');
    final c = container(_Permission(LibraryAccess.granted));

    await c.read(scanControllerProvider.notifier).scan();

    expect(c.read(scanControllerProvider), isA<ScanNeedsPermission>());
  });
}
