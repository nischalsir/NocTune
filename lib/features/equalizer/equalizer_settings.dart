import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// The bands a phone's equaliser offers: how far each can go, in decibels,
/// and the pitch at the middle of each, in hertz.
typedef EqualizerBands = ({double minDb, double maxDb, List<double> centers});

/// A level in decibels at a pitch in hertz.
typedef CurvePoint = ({double hz, double db});

/// The shape of an equaliser setting. It is kept as levels at pitches, not
/// as band numbers, so one shape fits whatever bands a phone has.
class EqualizerCurve {
  const EqualizerCurve(this.points, {this.name});

  /// What it is called in the list; null for a setting made by hand.
  final String? name;

  /// From the lowest pitch to the highest. Never empty.
  final List<CurvePoint> points;

  /// The level at [hz]: a straight line between the two points around it,
  /// measured by pitch (100 Hz to 1 kHz is the same step to the ear as
  /// 1 kHz to 10 kHz), and level beyond the first and last point.
  double levelAt(double hz) {
    if (hz <= points.first.hz) return points.first.db;
    for (var i = 1; i < points.length; i++) {
      final low = points[i - 1], high = points[i];
      if (hz <= high.hz) {
        final along = math.log(hz / low.hz) / math.log(high.hz / low.hz);
        return low.db + (high.db - low.db) * along;
      }
    }
    return points.last.db;
  }

  /// The level of each of [bands], kept within what they can do.
  List<double> levelsFor(EqualizerBands bands) => [
    for (final hz in bands.centers)
      levelAt(hz).clamp(bands.minDb, bands.maxDb).toDouble(),
  ];

  String _encode() => jsonEncode({
    'name': name,
    'points': [
      for (final point in points) [point.hz, point.db],
    ],
  });

  /// Null when [source] is not a curve written by [_encode].
  static EqualizerCurve? _decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (json case {
      'name': final Object? name,
      'points': final List<Object?> entries,
    }) {
      final points = <CurvePoint>[];
      for (final entry in entries) {
        if (entry case [final num hz, final num db] when hz > 0) {
          points.add((hz: hz.toDouble(), db: db.toDouble()));
        } else {
          return null;
        }
      }
      if (points.isEmpty) return null;
      points.sort((a, b) => a.hz.compareTo(b.hz));
      return EqualizerCurve(points, name: name is String ? name : null);
    }
    return null;
  }
}

/// Level everywhere: the sound as the file has it.
const flatCurve = EqualizerCurve([
  (hz: 60, db: 0),
  (hz: 14000, db: 0),
], name: 'Flat');

/// The ready-made shapes, each given at five pitches from deep bass to the
/// top of the treble.
final List<EqualizerCurve> builtInCurves = [
  flatCurve,
  _shape('Bass boost', [6, 4, 0, 0, 0]),
  _shape('Treble boost', [0, 0, 0, 3, 6]),
  _shape('Vocal', [-2, 0, 3, 3, 0]),
  _shape('Rock', [5, 3, -1, 3, 4]),
  _shape('Pop', [-1, 2, 4, 2, -1]),
  _shape('Jazz', [3, 2, -1, 2, 4]),
  _shape('Classical', [4, 2, -2, 2, 3]),
  // A phone's speaker cannot play deep bass. Sending it there anyway is
  // what makes it rattle when the volume is high.
  _shape('Small speaker', [-10, -4, 0, 0, 0]),
];

const _shapePitches = [60.0, 230.0, 910.0, 3600.0, 14000.0];

EqualizerCurve _shape(String name, List<double> levels) => EqualizerCurve([
  for (final (index, hz) in _shapePitches.indexed) (hz: hz, db: levels[index]),
], name: name);

/// "+3 dB", "0 dB", "-5 dB": a level to the nearest decibel.
String formatDb(double db) {
  final rounded = db.round();
  return '${rounded > 0 ? '+' : ''}$rounded dB';
}

/// "60 Hz", "3.6 kHz", "14 kHz".
String formatHz(double hz) {
  if (hz < 1000) return '${hz.round()} Hz';
  final thousands = hz / 1000;
  final whole = thousands == thousands.roundToDouble();
  return '${whole ? thousands.round() : thousands.toStringAsFixed(1)} kHz';
}

const _enabledKey = 'equalizer_enabled';
const _curveKey = 'equalizer_curve';
const _preampKey = 'equalizer_preamp';
const _savedKey = 'equalizer_saved';

/// What the user chose on the Equaliser page.
class EqualizerSettings {
  const EqualizerSettings({
    this.enabled = false,
    this.curve = flatCurve,
    this.preampDb = 0,
    this.saved = const [],
  });

  /// Reads what [store] wrote. Anything missing or unreadable falls back to
  /// off, flat and no preamp.
  factory EqualizerSettings.load(SharedPreferences preferences) {
    final saved = <EqualizerCurve>[];
    for (final source in preferences.getStringList(_savedKey) ?? const []) {
      final curve = EqualizerCurve._decode(source);
      if (curve?.name != null) saved.add(curve!);
    }
    return EqualizerSettings(
      enabled: preferences.getBool(_enabledKey) ?? false,
      curve:
          EqualizerCurve._decode(preferences.getString(_curveKey) ?? '') ??
          flatCurve,
      preampDb: (preferences.getDouble(_preampKey) ?? 0)
          .clamp(minPreampDb, maxPreampDb)
          .toDouble(),
      saved: saved,
    );
  }

  /// How far the preamp goes either way. It lowers much further than it
  /// raises: lowering is always clean, raising is not.
  static const minPreampDb = -12.0;
  static const maxPreampDb = 6.0;

  /// Off means nothing touches the sound, the preamp included.
  final bool enabled;

  final EqualizerCurve curve;

  /// The level of the whole sound, in decibels from the file's own.
  final double preampDb;

  /// The shapes the user saved under a name of their own.
  final List<EqualizerCurve> saved;

  EqualizerSettings copyWith({
    bool? enabled,
    EqualizerCurve? curve,
    double? preampDb,
    List<EqualizerCurve>? saved,
  }) => EqualizerSettings(
    enabled: enabled ?? this.enabled,
    curve: curve ?? this.curve,
    preampDb: preampDb ?? this.preampDb,
    saved: saved ?? this.saved,
  );

  void store(SharedPreferences preferences) {
    preferences
      ..setBool(_enabledKey, enabled)
      ..setString(_curveKey, curve._encode())
      ..setDouble(_preampKey, preampDb)
      ..setStringList(_savedKey, [for (final curve in saved) curve._encode()]);
  }

  /// One line for the Settings page.
  String get summary {
    if (!enabled) {
      return 'Off. Files are played as they are; a track is labelled '
          'lossless only when its format is.';
    }
    final shape = curve.name ?? 'your own setting';
    return preampDb == 0
        ? 'On: $shape'
        : 'On: $shape, preamp ${formatDb(preampDb)}';
  }
}
