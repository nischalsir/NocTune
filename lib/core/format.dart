/// Formats a position or track length as `m:ss`, or `h:mm:ss` past an hour.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$seconds';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
}

/// Formats a total listening time for library summaries, e.g. `12 h 5 min`.
String formatLongDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours h $minutes min';
}

/// Formats a whole number with thousands separators, e.g. `19,588`.
String formatCount(int value) => '$value'.replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);
