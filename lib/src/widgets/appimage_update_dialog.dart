import 'package:flutter/material.dart';

import '../theme/file_tile_colors.dart';

class AppImageUpdatePrompt extends StatelessWidget {
  const AppImageUpdatePrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'New update available',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(
        'Install now?',
        style: TextStyle(color: colors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Install now'),
        ),
      ],
    );
  }
}

class AppImageUpdateProgress extends StatelessWidget {
  const AppImageUpdateProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: colors.surface,
        content: Row(
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                'Installing update…',
                style: TextStyle(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppImageRestartPrompt extends StatelessWidget {
  const AppImageRestartPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Update installed',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(
        'Restart File Tile to use it.',
        style: TextStyle(color: colors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restart'),
        ),
      ],
    );
  }
}

class AppImageUpdateFailed extends StatelessWidget {
  const AppImageUpdateFailed({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        "Couldn't install the update",
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(message, style: TextStyle(color: colors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
