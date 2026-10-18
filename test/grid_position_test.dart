import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/grid_position.dart';

void main() {
  const cell = 80.0;

  test('a lone cell keeps a full outline', () {
    expect(
      outerCellOutlineSides(Offset.zero, const [Offset.zero], cell),
      CellOutlineSide.values.toSet(),
    );
  });

  test('adjacent cells drop only the shared edge', () {
    const left = Offset(0, 0);
    const right = Offset(80, 0);
    final cells = [left, right];

    expect(
      outerCellOutlineSides(left, cells, cell),
      {
        CellOutlineSide.top,
        CellOutlineSide.bottom,
        CellOutlineSide.left,
      },
    );
    expect(
      outerCellOutlineSides(right, cells, cell),
      {
        CellOutlineSide.top,
        CellOutlineSide.bottom,
        CellOutlineSide.right,
      },
    );
  });

  test('cells that do not touch stay disjoint outlines', () {
    const origin = Offset(0, 0);
    const diagonal = Offset(160, 80);
    final cells = [origin, diagonal];

    expect(
      outerCellOutlineSides(origin, cells, cell),
      CellOutlineSide.values.toSet(),
    );
    expect(
      outerCellOutlineSides(diagonal, cells, cell),
      CellOutlineSide.values.toSet(),
    );
  });
}
