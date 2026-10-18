import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/coordinate_space.dart';
import 'package:file_tile/src/widgets/os_drop_target_overlay.dart';

void main() {
  testWidgets('shows one add-file icon on the anchor cell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: OsDropTargetOverlay(
            cells: [Offset.zero, Offset(160, 80)],
            anchor: Offset.zero,
            coords: CoordinateSpace(scale: 1, panOffset: Offset.zero),
            color: Colors.blue,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
  });
}
