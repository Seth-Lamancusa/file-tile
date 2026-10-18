import 'package:file_tile/src/theme/file_tile_colors.dart';
import 'package:file_tile/src/widgets/appimage_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPrompt(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [FileTileColors.dark],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (context) => const AppImageUpdatePrompt(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('asks to install and returns true from Install now',
      (tester) async {
    await pumpPrompt(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New update available'), findsOneWidget);
    expect(find.text('Install now?'), findsOneWidget);

    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();

    expect(find.text('New update available'), findsNothing);
  });

  testWidgets('Not now dismisses the prompt', (tester) async {
    await pumpPrompt(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Install now?'), findsNothing);
  });
}
