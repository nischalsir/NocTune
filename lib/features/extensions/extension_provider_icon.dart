import 'dart:io';

import 'package:flutter/material.dart';

/// Displays an extension's unpacked package icon (`icon.png` / `icon.jpg`) when
/// present on disk, or a branded service badge matching Mornye's provider
/// palette and iconography for all built-in Mornye extensions.
class ExtensionProviderIcon extends StatelessWidget {
  const ExtensionProviderIcon({
    super.key,
    required this.extensionId,
    this.iconPath = '',
    this.size = 38,
  });

  final String extensionId;
  final String iconPath;
  final double size;

  static ({Color bg, Color fg, IconData icon, String? monogram}) _brandFor(
    String rawId,
  ) {
    final id = rawId.trim().toLowerCase();
    return switch (id) {
      'deezer' => (
        bg: const Color(0xFFA238FF),
        fg: Colors.white,
        icon: Icons.equalizer_rounded,
        monogram: null,
      ),
      'tidal-web' || 'tidal' => (
        bg: const Color(0xFF14161A),
        fg: const Color(0xFF00FFFF),
        icon: Icons.diamond_rounded,
        monogram: null,
      ),
      'qobuz-web' || 'qobuz' => (
        bg: const Color(0xFF005596),
        fg: Colors.white,
        icon: Icons.album_rounded,
        monogram: null,
      ),
      'jiosaavn' => (
        bg: const Color(0xFF2BC5B4),
        fg: Colors.white,
        icon: Icons.graphic_eq_rounded,
        monogram: null,
      ),
      'ytmusic-spotiflac' || 'ytmusic' => (
        bg: const Color(0xFFFF0033),
        fg: Colors.white,
        icon: Icons.play_circle_fill_rounded,
        monogram: null,
      ),
      'soundcloud' => (
        bg: const Color(0xFFFF5500),
        fg: Colors.white,
        icon: Icons.cloud_rounded,
        monogram: null,
      ),
      'amazon' || 'amzn' => (
        bg: const Color(0xFF00A8E1),
        fg: Colors.white,
        icon: Icons.headphones_rounded,
        monogram: null,
      ),
      'beatport' => (
        bg: const Color(0xFF01FF95),
        fg: const Color(0xFF0B0D10),
        icon: Icons.speaker_rounded,
        monogram: null,
      ),
      'spotify-web' || 'spotify' => (
        bg: const Color(0xFF1DB954),
        fg: Colors.white,
        icon: Icons.wifi_tethering_rounded,
        monogram: null,
      ),
      'apple-music' => (
        bg: const Color(0xFFFA2D48),
        fg: Colors.white,
        icon: Icons.music_note_rounded,
        monogram: null,
      ),
      'bugs-music' => (
        bg: const Color(0xFFFF3B2F),
        fg: Colors.white,
        icon: Icons.queue_music_rounded,
        monogram: 'B',
      ),
      'melon-music' => (
        bg: const Color(0xFF00CD3C),
        fg: Colors.white,
        icon: Icons.music_video_rounded,
        monogram: 'M',
      ),
      'genie-music' => (
        bg: const Color(0xFF0095FF),
        fg: Colors.white,
        icon: Icons.spatial_audio_off_rounded,
        monogram: 'G',
      ),
      'jellyfin' => (
        bg: const Color(0xFF00A4DC),
        fg: Colors.white,
        icon: Icons.dns_rounded,
        monogram: null,
      ),
      _ => (
        bg: const Color(0xFF2D323E),
        fg: Colors.white,
        icon: Icons.extension_rounded,
        monogram: null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    if (iconPath.isNotEmpty) {
      final file = File(iconPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildBrandBadge(radius),
          ),
        );
      }
    }
    return _buildBrandBadge(radius);
  }

  Widget _buildBrandBadge(BorderRadius radius) {
    final brand = _brandFor(extensionId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brand.bg,
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: brand.monogram != null
          ? Text(
              brand.monogram!,
              style: TextStyle(
                color: brand.fg,
                fontSize: size * 0.48,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            )
          : Icon(brand.icon, color: brand.fg, size: size * 0.56),
    );
  }
}
