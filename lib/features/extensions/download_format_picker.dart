import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/pressable.dart';
import 'extension_controller.dart';
import 'extension_models.dart';

/// User selection from the Mornye-style Download Service & Format/Quality Picker.
typedef ExtensionDownloadSelection = ({
  String providerId,
  String providerName,
  String qualityId,
  String qualityLabel,
});

/// Opens a Mornye-style modal bottom sheet to choose which download service /
/// extension and audio format / quality (`FLAC`, `Hi-Res FLAC`, `AAC 320 kbps`,
/// `M4A`, `MP3`, etc.) to use before downloading [track] or an album.
Future<ExtensionDownloadSelection?> showExtensionDownloadPicker(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String artist,
  required String coverUrl,
  required String recommendedProviderId,
}) {
  return showModalBottomSheet<ExtensionDownloadSelection>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _DownloadFormatPickerSheet(
      title: title,
      artist: artist,
      coverUrl: coverUrl,
      recommendedProviderId: recommendedProviderId,
    ),
  );
}

class _DownloadFormatPickerSheet extends ConsumerStatefulWidget {
  const _DownloadFormatPickerSheet({
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.recommendedProviderId,
  });

  final String title;
  final String artist;
  final String coverUrl;
  final String recommendedProviderId;

  @override
  ConsumerState<_DownloadFormatPickerSheet> createState() =>
      _DownloadFormatPickerSheetState();
}

class _DownloadFormatPickerSheetState
    extends ConsumerState<_DownloadFormatPickerSheet> {
  String? _selectedServiceId;

  String _resolveSelectedService(List<InstalledExtension> downloaders) {
    if (downloaders.isEmpty) return '';
    final current = _selectedServiceId;
    if (current != null && downloaders.any((e) => e.id == current)) {
      return current;
    }
    if (widget.recommendedProviderId.isNotEmpty &&
        downloaders.any((e) => e.id == widget.recommendedProviderId)) {
      return widget.recommendedProviderId;
    }
    return downloaders.first.id;
  }

  List<ExtensionQualityOption> _qualitiesFor(InstalledExtension? ext) {
    if (ext != null && ext.qualityOptions.isNotEmpty) {
      return ext.qualityOptions;
    }
    return const [
      ExtensionQualityOption(
        id: 'LOSSLESS',
        label: 'FLAC Lossless',
        description: '16-bit / 44.1 kHz lossless FLAC audio',
      ),
      ExtensionQualityOption(
        id: 'HIGH',
        label: 'High Quality (320 kbps)',
        description: 'AAC / M4A or MP3 320 kbps',
      ),
    ];
  }

  IconData _qualityIcon(String id, String label) {
    final s = '$id $label'.toLowerCase();
    if (s.contains('hi-res') || s.contains('hires') || s.contains('24')) {
      return Icons.hd_rounded;
    }
    if (s.contains('flac') || s.contains('lossless')) {
      return Icons.high_quality_rounded;
    }
    return Icons.audiotrack_rounded;
  }

  String _formatBadge(String id, String label) {
    final s = '$id $label'.toLowerCase();
    if (s.contains('flac') || s.contains('lossless')) return 'FLAC';
    if (s.contains('aac') || s.contains('m4a')) return 'M4A';
    if (s.contains('mp3')) return 'MP3';
    if (s.contains('opus') || s.contains('best')) return 'M4A / OPUS';
    return id.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final downloaders = ref.watch(
      extensionControllerProvider.select(
        (state) => state.enabledDownloadExtensions,
      ),
    );
    final selectedId = _resolveSelectedService(downloaders);
    final selectedExt = downloaders
        .where((e) => e.id == selectedId)
        .firstOrNull;
    final qualities = _qualitiesFor(selectedExt);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: palette.glassSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: palette.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Artwork(
                      path: widget.coverUrl.isNotEmpty ? widget.coverUrl : null,
                      size: 52,
                      radius: 12,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.artist.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: palette.glassBorder),
                const SizedBox(height: 14),
                Text(
                  'Download from',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (downloaders.isEmpty)
                  Text(
                    'No download extension is enabled. Enable one in Settings › Extensions.',
                    style: text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ext in downloaders)
                        _ServiceChip(
                          key: ValueKey('picker-service-${ext.id}'),
                          label: ext.displayName,
                          recommended: ext.id == widget.recommendedProviderId,
                          selected: ext.id == selectedId,
                          onTap: () =>
                              setState(() => _selectedServiceId = ext.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Select format & quality',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: palette.glass,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: palette.glassBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (idx, q) in qualities.indexed) ...[
                          if (idx > 0)
                            Divider(
                              height: 1,
                              indent: 52,
                              color: palette.glassBorder,
                            ),
                          ListTile(
                            key: ValueKey('picker-quality-${q.id}'),
                            leading: Icon(
                              _qualityIcon(q.id, q.label),
                              color: palette.accent,
                            ),
                            title: Text(
                              q.label,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: q.description.isNotEmpty
                                ? Text(
                                    q.description,
                                    style: text.bodySmall?.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: ShapeDecoration(
                                color: palette.accent.withValues(alpha: 0.16),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                _formatBadge(q.id, q.label),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop((
                                providerId: selectedId,
                                providerName:
                                    selectedExt?.displayName ?? selectedId,
                                qualityId: q.id,
                                qualityLabel: q.label,
                              ));
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final fg = selected ? palette.onAccent : palette.textPrimary;
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          color: selected ? palette.accent : palette.glass,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? palette.accent : palette.glassBorder,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recommended ? Icons.auto_awesome_rounded : Icons.extension_rounded,
              size: 15,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
