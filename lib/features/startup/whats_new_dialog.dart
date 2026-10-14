import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import 'update_service.dart';
import 'whats_new.dart';

/// Remembers, on the device, which version of NocTune last ran, so the first
/// launch after an update can say what changed.
class WhatsNewStore {
  WhatsNewStore(this._prefs);

  static const _key = 'last_version_run';

  final SharedPreferences _prefs;

  /// Whether [installed] is newer than the version that ran before. With no
  /// record, only an app that was already set up counts as updated: the
  /// versions before this one kept none. A new installation does not.
  bool isPending(AppVersion installed, {required bool newInstallation}) {
    final stored = _prefs.getString(_key);
    if (stored == null) return !newInstallation;
    final last = AppVersion.tryParse(stored);
    return last == null || last < installed;
  }

  Future<void> markSeen(AppVersion installed) =>
      _prefs.setString(_key, '$installed');
}

/// Shown once after NocTune has been updated: the version it is now and
/// what this version brings.
Future<void> showWhatsNewDialog(BuildContext context, AppVersion version) {
  return showNocDialog<void>(
    context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return NocDialogCard(
        title: 'Updated to ${version.label}',
        actions: [
          PillButton(
            label: 'Got it',
            filled: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
        children: [
          Text("WHAT'S NEW", style: text.labelSmall),
          const SizedBox(height: 6),
          for (final note in kWhatsNew)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: text.bodyMedium),
                  Expanded(child: Text(note, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
      );
    },
  );
}
