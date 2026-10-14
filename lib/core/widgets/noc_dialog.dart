import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';
import 'pill_button.dart';

/// Presents [builder]'s content as a NocTune popup: dimmed, blurred backdrop
/// and a card that materialises with a short scale-and-fade. With reduced
/// motion on it only fades.
Future<T?> showNocDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.noc.scrim,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, _) => PopScope(
      canPop: dismissible,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: builder(context),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = FadeTransition(opacity: curved, child: child);
      if (MediaQuery.disableAnimationsOf(context)) return fade;
      return ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: fade,
      );
    },
  );
}

/// The popup card: a branded eyebrow, a headline, content and stacked
/// actions, which are [PillButton]s like the rest of the app's buttons.
class NocDialogCard extends StatelessWidget {
  const NocDialogCard({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;

  /// Buttons, most important first. They are stacked full-width.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(28);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Material(
          color: highContrast ? palette.glassSolid : palette.glassChrome,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: highContrast ? palette.textSecondary : palette.glassBorder,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOCTUNE',
                  style: text.labelSmall?.copyWith(
                    color: palette.accent,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  header: true,
                  child: Text(title, style: text.headlineSmall),
                ),
                const SizedBox(height: 14),
                ...children,
                const SizedBox(height: 22),
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
