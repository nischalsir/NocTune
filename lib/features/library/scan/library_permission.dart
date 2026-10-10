import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import 'library_sources.dart';

enum LibraryAccess {
  granted,

  /// Refused this time; asking again will show the system prompt.
  denied,

  /// Refused for good; only the system Settings app can change it.
  permanentlyDenied,
}

/// The permission to read music from the device's shared storage.
class LibraryPermission {
  const LibraryPermission();

  /// Asks the user for access, showing the system prompt if needed.
  Future<LibraryAccess> request() async {
    final permission = await _permission();
    if (permission == null) return LibraryAccess.granted;
    return _access(await permission.request());
  }

  /// Reports the current access without prompting.
  Future<LibraryAccess> check() async {
    final permission = await _permission();
    if (permission == null) return LibraryAccess.granted;
    return _access(await permission.status);
  }

  /// Opens this app's page in system Settings.
  Future<void> openSettings() => openAppSettings();

  // iOS needs no permission: the app only reads files inside its own folder.
  Future<Permission?> _permission() async {
    if (!Platform.isAndroid) return null;
    // Android 13 replaced the broad storage permission with an audio-only one.
    return await androidSdkInt() >= 33 ? Permission.audio : Permission.storage;
  }

  LibraryAccess _access(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return LibraryAccess.granted;
    if (status.isPermanentlyDenied) return LibraryAccess.permanentlyDenied;
    return LibraryAccess.denied;
  }
}
