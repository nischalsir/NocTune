import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';
import 'frosted.dart';
import 'pressable.dart';

/// A wide pill with a word, and an icon before it if given: filled for the
/// main action, glass for the other. [destructive] fills it with the theme's
/// error colour instead, for an action that deletes something.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.destructive = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final scheme = Theme.of(context).colorScheme;
    final solid = filled || destructive;
    final color = destructive
        ? scheme.onError
        : (filled ? palette.background : palette.textPrimary);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Shrinks rather than overflowing when the text is very large.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: solid
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: destructive ? scheme.error : palette.textPrimary,
                shape: const StadiumBorder(),
              ),
              child: content,
            )
          : Frosted(child: content),
    );
  }
}
