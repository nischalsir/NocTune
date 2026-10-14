import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pressable.dart';
import 'equalizer_controller.dart';
import 'equalizer_settings.dart';

/// The equaliser: a switch, ready-made and saved shapes, a slider for each
/// band the phone has, and a preamp.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(equalizerProvider);
    final controller = ref.read(equalizerProvider.notifier);
    final on = settings.enabled;
    // The name of the shape in use, when it is one the user saved.
    final name = settings.curve.name;
    final savedName = settings.saved.any((curve) => curve.name == name)
        ? name
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Equaliser'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: NocBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Card(
                // Read out as one switch with its title.
                child: MergeSemantics(
                  child: ListTile(
                    // The same inset as the preamp card, so the switch ends
                    // where its figure does.
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(on ? 'On' : 'Off'),
                    subtitle: Text(
                      on
                          ? 'The sound is shaped by the settings below.'
                          : 'Files are played as they are.',
                    ),
                    onTap: () => controller.setEnabled(!on),
                    trailing: CupertinoSwitch(
                      value: on,
                      onChanged: controller.setEnabled,
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Switched off, the rest is shown but cannot be changed.
              IgnorePointer(
                ignoring: !on,
                child: Opacity(
                  opacity: on ? 1 : 0.5,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        for (final curve in [
                          ...builtInCurves,
                          ...settings.saved,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ShapeChip(
                              label: curve.name!,
                              selected: curve.name == settings.curve.name,
                              onTap: () => controller.choose(curve),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                  child: ref
                      .watch(equalizerBandsProvider)
                      .when(
                        data: (bands) => _Bands(
                          bands: bands,
                          levels: settings.curve.levelsFor(bands),
                          onChanged: on
                              ? (index, db) =>
                                    controller.setBand(bands, index, db)
                              : null,
                        ),
                        loading: () => const _Note(
                          'Play a song first. The phone gives NocTune its '
                          'equaliser bands once a song is loaded.',
                        ),
                        error: (_, _) => const _Note(
                          'This device has no equaliser NocTune can use.',
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 16),
              _Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Preamp', style: text.bodyLarge),
                          ),
                          Text(
                            formatDb(settings.preampDb),
                            style: text.titleSmall,
                          ),
                        ],
                      ),
                      Slider(
                        key: const ValueKey('equalizer-preamp'),
                        // The track starts and ends with the text.
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        value: settings.preampDb,
                        min: EqualizerSettings.minPreampDb,
                        max: EqualizerSettings.maxPreampDb,
                        divisions:
                            (EqualizerSettings.maxPreampDb -
                                    EqualizerSettings.minPreampDb)
                                .round(),
                        semanticFormatterCallback: formatDb,
                        onChanged: on ? controller.setPreamp : null,
                      ),
                      Text(
                        'Lower it if the sound distorts when it is loud or '
                        'after raising bands. Raising it makes quiet '
                        'songs louder, and can distort loud ones.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: !on,
                child: Opacity(
                  opacity: on ? 1 : 0.5,
                  // The buttons' words start on the cards' text edge.
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final name = await _askName(context);
                            if (name != null) controller.save(name);
                          },
                          child: const Text('Save as preset'),
                        ),
                        if (savedName != null)
                          TextButton(
                            onPressed: () => controller.delete(savedName),
                            child: Text('Delete "$savedName"'),
                          ),
                        TextButton(
                          onPressed: controller.reset,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks what to call a saved shape. Null when the user backs out.
Future<String?> _askName(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _NameDialog(),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The name as typed, or null while it is blank or belongs to a
  /// ready-made shape, which keeps its name to itself.
  String? get _usable {
    final name = _name.text.trim();
    final taken = builtInCurves.any(
      (curve) => curve.name!.toLowerCase() == name.toLowerCase(),
    );
    return name.isEmpty || taken ? null : name;
  }

  void _submit() {
    final name = _usable;
    if (name != null) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as preset'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _usable == null ? null : _submit,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// One upright slider for each band, its level above it and its pitch below.
class _Bands extends StatelessWidget {
  const _Bands({
    required this.bands,
    required this.levels,
    required this.onChanged,
  });

  final EqualizerBands bands;
  final List<double> levels;

  /// Null while the equaliser is switched off.
  final void Function(int index, double db)? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onChanged = this.onChanged;
    return Row(
      children: [
        for (final (index, hz) in bands.centers.indexed)
          Expanded(
            // Read out as one slider named by its pitch.
            child: MergeSemantics(
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatDb(levels[index]),
                        style: text.labelMedium,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        key: ValueKey('equalizer-band-$index'),
                        value: levels[index],
                        min: bands.minDb,
                        max: bands.maxDb,
                        divisions: (bands.maxDb - bands.minDb).round(),
                        semanticFormatterCallback: formatDb,
                        onChanged: onChanged == null
                            ? null
                            : (db) => onChanged(index, db),
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatHz(hz), style: text.bodySmall),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
  );
}

/// The glass panel the Settings page groups its rows on.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}

/// A shape to pick, as a pill like the Library's sections.
class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? palette.onAccent : palette.textPrimary,
        ),
      ),
    );
    return Semantics(
      selected: selected,
      child: Pressable(
        semanticLabel: label,
        onTap: onTap,
        child: selected
            ? DecoratedBox(
                decoration: ShapeDecoration(
                  color: palette.accent,
                  shape: const StadiumBorder(),
                ),
                child: content,
              )
            : Frosted(child: content),
      ),
    );
  }
}
