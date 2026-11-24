import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import 'extension_controller.dart';
import 'extension_downloads_screen.dart';
import 'extension_models.dart';
import 'extension_provider_icon.dart';

/// Manages Mornye / SpotiFLAC extension packages (`.spotiflac-ext`, `.sflx`,
/// `.mornye-ext`) on the device, using the same cards and switches as Settings
/// and the Equaliser.
class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(extensionControllerProvider.notifier).checkForUpdates(),
      );
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkAndUpdateAllExtensions() async {
    try {
      final count = await ref
          .read(extensionControllerProvider.notifier)
          .checkForUpdates();
      if (!mounted) return;
      if (count > 0) {
        _say('Updating $count extension${count == 1 ? '' : 's'} from Mornye…');
        await ref
            .read(extensionControllerProvider.notifier)
            .updateFromRegistry();
        _say('All Mornye extensions updated to latest versions.');
      } else {
        await ref
            .read(extensionControllerProvider.notifier)
            .updateFromRegistry();
        _say('All Mornye extensions are up to date.');
      }
    } on Exception catch (e) {
      _say('Could not update extensions: $e');
    }
  }

  Future<void> _updateSingleExtension(InstalledExtension ext) async {
    try {
      _say('Updating ${ext.displayName} from Mornye…');
      await ref
          .read(extensionControllerProvider.notifier)
          .updateFromRegistry(id: ext.id);
      _say('Updated ${ext.displayName}.');
    } on Exception catch (e) {
      _say('Could not update ${ext.displayName}: $e');
    }
  }

  Future<void> _pickAndInstallFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null) return;
    try {
      await ref.read(extensionControllerProvider.notifier).installFile(path);
      _say('Extension installed.');
    } on Exception catch (e) {
      _say('Could not install extension: $e');
    }
  }

  Future<void> _scanDeviceFolders() async {
    try {
      final added = await ref
          .read(extensionControllerProvider.notifier)
          .discoverOnDevice();
      _say(
        added > 0
            ? 'Installed $added extension${added == 1 ? '' : 's'} found on device.'
            : 'No new extension files found on device.',
      );
    } on Exception catch (e) {
      _say('Could not scan device folders: $e');
    }
  }

  Future<void> _installFromUrlDialog() async {
    final urlController = TextEditingController();
    final url = await showNocDialog<String>(
      context,
      builder: (context) => NocDialogCard(
        title: 'Install from repository or URL',
        actions: [
          PillButton(
            label: 'Install',
            filled: true,
            onTap: () => Navigator.of(context).pop(urlController.text.trim()),
          ),
          PillButton(label: 'Cancel', onTap: () => Navigator.of(context).pop()),
        ],
        children: [
          Text(
            'Enter a Mornye / SpotiFLAC extension repository URL or a direct '
            '.spotiflac-ext / .sflx link.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://…'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      await ref.read(extensionControllerProvider.notifier).installFromUrl(url);
      _say('Extension installed.');
    } on Exception catch (e) {
      _say('Could not install from URL: $e');
    }
  }

  Future<void> _openExtensionOptions(
    InstalledExtension ext,
    List<InstalledExtension> all,
  ) async {
    final values = <String, Object?>{
      for (final s in ext.settings) s.key: s.value ?? s.defaultValue,
    };
    final textControllers = <String, TextEditingController>{
      for (final s in ext.settings)
        if (s.type != 'boolean' && s.options.isEmpty)
          s.key: TextEditingController(text: (values[s.key] ?? '').toString()),
    };
    String? selectedQuality = ext.qualityOptions.isNotEmpty
        ? ext.qualityOptions.first.id
        : null;

    await showNocDialog<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final index = all.indexWhere((item) => item.id == ext.id);
          return NocDialogCard(
            title: ext.displayName,
            actions: [
              if (ext.settings.isNotEmpty || ext.qualityOptions.isNotEmpty)
                PillButton(
                  label: 'Save',
                  filled: true,
                  onTap: () async {
                    for (final entry in textControllers.entries) {
                      values[entry.key] = entry.value.text.trim();
                    }
                    if (selectedQuality != null) {
                      values['quality'] = selectedQuality;
                    }
                    await ref
                        .read(extensionControllerProvider.notifier)
                        .updateSettings(ext.id, values);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              if (index > 0)
                PillButton(
                  label: 'Move higher in priority',
                  onTap: () async {
                    final ids = [for (final item in all) item.id];
                    final id = ids.removeAt(index);
                    ids.insert(index - 1, id);
                    await ref
                        .read(extensionControllerProvider.notifier)
                        .setPriority(ids);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              PillButton(
                label: ext.hasUpdate
                    ? 'Update to v${ext.latestVersion}'
                    : 'Update from Mornye',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _updateSingleExtension(ext);
                },
              ),
              PillButton(
                label: 'Remove extension',
                destructive: true,
                onTap: () async {
                  await ref
                      .read(extensionControllerProvider.notifier)
                      .remove(ext.id);
                  if (context.mounted) Navigator.of(context).pop();
                  _say('Removed ${ext.displayName}.');
                },
              ),
              PillButton(
                label: 'Close',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
            children: [
              Text(
                ext.description.isNotEmpty
                    ? '${ext.capabilitySummary}\n${ext.description}'
                    : ext.capabilitySummary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (ext.errorMessage != null && ext.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ext.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (ext.qualityOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Download quality',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in ext.qualityOptions)
                      ChoiceChip(
                        label: Text(q.label),
                        selected: selectedQuality == q.id,
                        onSelected: (_) =>
                            setModalState(() => selectedQuality = q.id),
                      ),
                  ],
                ),
              ],
              for (final s in ext.settings) ...[
                const SizedBox(height: 12),
                if (s.type == 'boolean')
                  Row(
                    children: [
                      Expanded(child: Text(s.label)),
                      CupertinoSwitch(
                        value: values[s.key] == true,
                        onChanged: (v) =>
                            setModalState(() => values[s.key] = v),
                      ),
                    ],
                  )
                else if (s.options.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final opt in s.options)
                            ChoiceChip(
                              label: Text(opt),
                              selected: values[s.key]?.toString() == opt,
                              onSelected: (_) =>
                                  setModalState(() => values[s.key] = opt),
                            ),
                        ],
                      ),
                    ],
                  )
                else
                  TextField(
                    controller: textControllers[s.key],
                    obscureText: s.secret,
                    decoration: InputDecoration(
                      labelText: s.label,
                      helperText: s.description.isNotEmpty
                          ? s.description
                          : null,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
    for (final c in textControllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final state = ref.watch(extensionControllerProvider);
    final controller = ref.read(extensionControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Extensions'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: NocBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Card(
                children: [
                  ListTile(
                    leading: const Icon(Icons.downloading_rounded),
                    title: const Text('Download queue'),
                    subtitle: Text(
                      state.downloadQueue.isEmpty
                          ? 'View active and completed extension downloads'
                          : '${state.activeDownloadCount} active · ${state.completedDownloadCount} completed',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ExtensionDownloadsScreen(),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56, color: palette.glassBorder),
                  ListTile(
                    leading: const Icon(Icons.system_update_alt_rounded),
                    title: const Text('Update built-in Mornye extensions'),
                    subtitle: Text(
                      state.extensions.any((e) => e.hasUpdate)
                          ? '${state.extensions.where((e) => e.hasUpdate).length} extension update(s) available from Mornye registry'
                          : 'All Mornye extensions pre-installed · tap to check & sync latest',
                    ),
                    trailing: state.extensions.any((e) => e.hasUpdate)
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: ShapeDecoration(
                              color: palette.accent.withValues(alpha: 0.18),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              'Update all',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    onTap: state.loading ? null : _checkAndUpdateAllExtensions,
                  ),
                  Divider(height: 1, indent: 56, color: palette.glassBorder),
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('Install extension from file'),
                    subtitle: const Text(
                      'Pick a .spotiflac-ext, .sflx or .mornye-ext file on '
                      'this device',
                    ),
                    onTap: state.loading ? null : _pickAndInstallFile,
                  ),
                  Divider(height: 1, indent: 56, color: palette.glassBorder),
                  ListTile(
                    leading: const Icon(Icons.travel_explore_rounded),
                    title: const Text('Scan device for extensions'),
                    subtitle: const Text(
                      'Finds extension files in Download, Documents and Music',
                    ),
                    onTap: state.loading ? null : _scanDeviceFolders,
                  ),
                  Divider(height: 1, indent: 56, color: palette.glassBorder),
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Install from repository or URL'),
                    subtitle: const Text(
                      'Load from a Mornye / SpotiFLAC extension registry URL',
                    ),
                    onTap: state.loading ? null : _installFromUrlDialog,
                  ),
                ],
              ),
              if (state.loading) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (state.extensions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'INSTALLED (IN PRIORITY ORDER)',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                _Card(
                  children: [
                    for (final (index, ext) in state.extensions.indexed) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: 56,
                          color: palette.glassBorder,
                        ),
                      ListTile(
                        leading: ExtensionProviderIcon(
                          extensionId: ext.id,
                          iconPath: ext.iconPath,
                          size: 40,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                ext.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (ext.hasUpdate) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: state.loading
                                    ? null
                                    : () => _updateSingleExtension(ext),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: ShapeDecoration(
                                    color: palette.accent.withValues(
                                      alpha: 0.18,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Text(
                                    'Update',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          ext.description.isNotEmpty
                              ? '${ext.capabilitySummary}\n${ext.description}'
                              : ext.capabilitySummary,
                        ),
                        isThreeLine: ext.description.isNotEmpty,
                        onTap: () =>
                            _openExtensionOptions(ext, state.extensions),
                        trailing: CupertinoSwitch(
                          value: ext.enabled,
                          activeTrackColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          onChanged: (value) =>
                              controller.setEnabled(ext.id, value),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Material(
      color: palette.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: palette.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
