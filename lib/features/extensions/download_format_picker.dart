import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import 'extension_controller.dart';
import 'extension_models.dart';

/// User selection from the Mornye-style Download Service & Format/Quality Picker.
typedef ExtensionDownloadSelection = ({
  String providerId,
  String providerName,
  String qualityId,
  String qualityLabel,
});

const _kBuiltInYouTubeDownloader = InstalledExtension(
  id: 'ytmusic',
  name: 'ytmusic',
  displayName: 'YouTube Music',
  version: '1.0.0',
  hasMetadataProvider: true,
  hasDownloadProvider: true,
  qualityOptions: [
    ExtensionQualityOption(
      id: 'm4a',
      label: 'AAC High Quality (M4A)',
      description: 'Best available M4A / AAC audio stream',
    ),
    ExtensionQualityOption(
      id: 'opus',
      label: 'Opus High Bitrate',
      description: 'High-efficiency WebM / Opus audio stream',
    ),
  ],
);

/// Opens a Mornye-style modal bottom sheet to choose which download extension
/// (when multiple are enabled) and which audio format / quality mode (`FLAC`,
/// `Hi-Res FLAC`, `AAC 320 kbps`, `M4A`, `MP3`, etc.) to use before downloading
/// [track] or an album, without switching providers in the middle.
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
  String? _selectedProviderId;

  List<InstalledExtension> _buildAvailableDownloaders(
    List<InstalledExtension> enabledDownloaders,
  ) {
    if (enabledDownloaders.isEmpty) {
      return const [_kBuiltInYouTubeDownloader];
    }
    final hasYtDownloader = enabledDownloaders.any(
      (ext) => ext.id == 'ytmusic-spotiflac' || ext.id == 'ytmusic',
    );
    if (!hasYtDownloader) {
      return [...enabledDownloaders, _kBuiltInYouTubeDownloader];
    }
    return enabledDownloaders;
  }

  InstalledExtension? _resolveSelectedExtension(
    List<InstalledExtension> downloaders,
  ) {
    if (downloaders.isEmpty) return null;
    final explicit = _selectedProviderId;
    if (explicit != null && explicit.isNotEmpty) {
      for (final ext in downloaders) {
        if (ext.id == explicit) return ext;
      }
    }
    final rec = widget.recommendedProviderId.trim();
    if (rec.isNotEmpty) {
      for (final ext in downloaders) {
        if (ext.id == rec) return ext;
      }
      if (rec == 'ytmusic') {
        for (final ext in downloaders) {
          if (ext.id == 'ytmusic-spotiflac') return ext;
        }
      }
    }
    return downloaders.first;
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
    final enabledDownloaders = ref.watch(
      extensionControllerProvider.select(
        (state) => state.enabledDownloadExtensions,
      ),
    );
    final downloaders = _buildAvailableDownloaders(enabledDownloaders);
    final selectedExt = _resolveSelectedExtension(downloaders);
    final selectedId = selectedExt?.id ?? '';
    final qualities = _qualitiesFor(selectedExt);
    final subtitleParts = <String>[
      if (widget.artist.isNotEmpty) widget.artist,
      if (selectedExt != null &&
          selectedExt.displayName.isNotEmpty &&
          selectedExt.displayName.toLowerCase() != widget.artist.toLowerCase())
        selectedExt.displayName,
    ];

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
                          if (subtitleParts.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitleParts.join(' · '),
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
                if (downloaders.isNotEmpty) ...[
                  Text(
                    'Download extension',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final ext in downloaders)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('picker-provider-${ext.id}'),
                              label: Text(ext.displayName),
                              selected: ext.id == selectedId,
                              onSelected: (_) {
                                setState(() => _selectedProviderId = ext.id);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
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
            ),
          ),
        ),
      ),
    );
  }
}
