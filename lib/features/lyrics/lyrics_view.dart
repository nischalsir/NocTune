import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/track.dart';
import '../settings/settings_controller.dart';
import 'lyrics.dart';
import 'lyrics_source.dart';

/// Lyrics for [track]. Synced lyrics highlight the line being sung and keep
/// it in view, following the real playback position; tapping a line seeks to
/// it. Plain lyrics are shown as text, without pretending to follow along.
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await importLyricsFor(track, ref);
    } on InvalidLyricsFile {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "That file has no lyrics NocTune can read. Try another file.",
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(
      lyricsProvider((trackId: track.id, uri: track.uri)),
    );
    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't read the lyrics",
        message: 'The lyrics stored with this track could not be opened.',
        action: FilledButton.icon(
          onPressed: () => _import(context, ref),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Import lyrics file'),
        ),
      ),
      data: (loaded) {
        if (loaded == null) {
          return EmptyState(
            icon: Icons.lyrics_outlined,
            title: 'No lyrics available',
            message:
                'This track has no lyrics embedded in it. You can add them '
                'from an .lrc or text file.',
            action: FilledButton.icon(
              onPressed: () => _import(context, ref),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import lyrics file'),
            ),
          );
        }
        return Column(
          children: [
            _Toolbar(
              loaded: loaded,
              onImport: () => _import(context, ref),
              onRemove: loaded.origin == LyricsOrigin.imported
                  ? () async {
                      await ref
                          .read(libraryRepositoryProvider)
                          .removeImportedLyrics(track.id);
                      ref.invalidate(
                        lyricsProvider((trackId: track.id, uri: track.uri)),
                      );
                    }
                  : null,
            ),
            Expanded(
              child: _LyricsBody(
                // A new track starts scrolled to the top with fresh state.
                key: ValueKey(track.id),
                lyrics: loaded.lyrics,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where the lyrics came from, text size, and import.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.loaded,
    required this.onImport,
    required this.onRemove,
  });

  final LoadedLyrics loaded;
  final VoidCallback onImport;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.lyricsScale));
    final settings = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            loaded.lyrics.synced
                ? loaded.origin.label.toUpperCase()
                : '${loaded.origin.label} · not time-synced'.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: context.noc.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Smaller text',
          visualDensity: VisualDensity.compact,
          onPressed: scale <= SettingsController.minLyricsScale
              ? null
              : () => settings.stepLyricsScale(larger: false),
          icon: const Icon(Icons.text_decrease_rounded),
        ),
        IconButton(
          tooltip: 'Larger text',
          visualDensity: VisualDensity.compact,
          onPressed: scale >= SettingsController.maxLyricsScale
              ? null
              : () => settings.stepLyricsScale(larger: true),
          icon: const Icon(Icons.text_increase_rounded),
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Lyrics options',
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            PopupMenuItem(value: onImport, child: const Text('Import a file…')),
            if (onRemove != null)
              PopupMenuItem(
                value: onRemove,
                child: const Text('Remove imported lyrics'),
              ),
          ],
        ),
      ],
    );
  }
}

class _LyricsBody extends ConsumerStatefulWidget {
  const _LyricsBody({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  ConsumerState<_LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends ConsumerState<_LyricsBody> {
  late List<GlobalKey> _lineKeys = _keysFor(widget.lyrics);

  /// Auto-follow pauses until this moment after the user scrolls by hand, so
  /// the view doesn't yank itself back while they are reading ahead.
  DateTime _followAfter = DateTime.fromMillisecondsSinceEpoch(0);

  static List<GlobalKey> _keysFor(Lyrics lyrics) => [
    for (var i = 0; i < lyrics.lines.length; i++) GlobalKey(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(_active()));
  }

  @override
  void didUpdateWidget(_LyricsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lineKeys = _keysFor(widget.lyrics);
    }
  }

  int _active() => widget.lyrics.indexAt(
    ref.read(playbackPositionProvider).value ?? Duration.zero,
  );

  /// Brings the active line to a third of the way down the view.
  void _follow(int index, {bool force = false}) {
    if (!mounted || index < 0 || index >= _lineKeys.length) return;
    if (!force && DateTime.now().isBefore(_followAfter)) return;
    final target = _lineKeys[index].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.32,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final scale = ref.watch(settingsProvider.select((s) => s.lyricsScale));
    // Only the active line's index is watched, so the position ticking
    // several times a second rebuilds this view once per line, not per tick.
    final positionIndex = playbackPositionProvider.select(
      (position) => lyrics.indexAt(position.value ?? Duration.zero),
    );
    final active = ref.watch(positionIndex);
    ref.listen(positionIndex, (_, index) => _follow(index));

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) {
          _followAfter = DateTime.now().add(const Duration(seconds: 3));
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          // Room above and below so the first and last lines can sit at the
          // focal point too.
          padding: EdgeInsets.symmetric(
            vertical: lyrics.synced ? box.maxHeight * 0.3 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, line) in lyrics.lines.indexed)
                _LyricLineTile(
                  key: _lineKeys[index],
                  text: line.text,
                  scale: scale,
                  // Plain lyrics are all shown at full strength.
                  emphasis: !lyrics.synced
                      ? _Emphasis.plain
                      : index == active
                      ? _Emphasis.active
                      : _Emphasis.dim,
                  onTap: line.time == null
                      ? null
                      : () {
                          ref.read(audioHandlerProvider).seek(line.time!);
                          _followAfter = DateTime.now();
                          _follow(index, force: true);
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Emphasis { active, dim, plain }

class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    super.key,
    required this.text,
    required this.scale,
    required this.emphasis,
    required this.onTap,
  });

  final String text;
  final double scale;
  final _Emphasis emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final plain = emphasis == _Emphasis.plain;
    // Built on the theme's text style so the lyrics use the app's typeface.
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: (plain ? 18 : 24) * scale,
      height: 1.25,
      fontWeight: plain ? FontWeight.w600 : FontWeight.w800,
      letterSpacing: plain ? 0 : -0.4,
      color: palette.textPrimary.withValues(
        alpha: emphasis == _Emphasis.dim ? 0.36 : 1,
      ),
    );

    final line = AnimatedScale(
      // The active line comes slightly forward; the rest sit back.
      scale: emphasis == _Emphasis.dim && !reduceMotion ? 0.96 : 1,
      alignment: Alignment.centerLeft,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedDefaultTextStyle(
        style: style,
        duration: duration,
        curve: Curves.easeOutCubic,
        // An empty timed line is an instrumental break, shown as a note.
        child: text.isEmpty && !plain
            ? Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.music_note_rounded,
                  size: 22 * scale,
                  color: style.color,
                  semanticLabel: 'Instrumental',
                ),
              )
            : Text(text),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: emphasis == _Emphasis.active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: plain ? 3 : 9, horizontal: 4),
          child: line,
        ),
      ),
    );
  }
}
