import 'package:flutter/material.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import 'update_service.dart';

/// What the user chose in the update popup.
enum UpdateChoice { updateNow, later, dontRemind }

/// Tells the user about a newer release. An optional update can be put off
/// or silenced; a required one offers only the update, and can't be
/// dismissed by tapping outside or pressing back.
Future<UpdateChoice?> showUpdateDialog(
  BuildContext context,
  UpdatePrompt prompt,
) {
  return showNocDialog<UpdateChoice>(
    context,
    dismissible: !prompt.required,
    builder: (context) {
      final palette = context.noc;
      final text = Theme.of(context).textTheme;
      final release = prompt.release;
      return NocDialogCard(
        title: prompt.required ? 'Update required' : 'Update available',
        actions: [
          PillButton(
            label: 'Update now',
            filled: true,
            onTap: () => Navigator.of(context).pop(UpdateChoice.updateNow),
          ),
          if (!prompt.required) ...[
            PillButton(
              label: 'Later',
              onTap: () => Navigator.of(context).pop(UpdateChoice.later),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpdateChoice.dontRemind),
              style: TextButton.styleFrom(
                foregroundColor: palette.textSecondary,
              ),
              child: const Text("Don't remind me about this version"),
            ),
          ],
        ],
        children: [
          Text(
            prompt.required
                ? 'This version of NocTune is no longer supported. Update '
                      'to keep using the app.'
                : 'A newer version of NocTune is ready.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _VersionTile(
                label: 'INSTALLED',
                version: prompt.installed.label,
                color: palette.textSecondary,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: palette.textTertiary,
                ),
              ),
              _VersionTile(
                label: 'LATEST',
                version: release.version.label,
                color: palette.accent,
              ),
            ],
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text("WHAT'S NEW", style: text.labelSmall),
            const SizedBox(height: 6),
            for (final note in release.notes)
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
        ],
      );
    },
  );
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.label,
    required this.version,
    required this.color,
  });

  final String label;
  final String version;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall),
        Text(version, style: text.titleLarge?.copyWith(color: color)),
      ],
    );
  }
}
