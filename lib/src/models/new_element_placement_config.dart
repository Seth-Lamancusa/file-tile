class NewElementPlacementConfig {
  final int anchorCol;
  final int anchorRow;
  final int constrainedCount;
  final String constrainedDirection;
  final String unconstrainedDirection;

  NewElementPlacementConfig({
    required this.anchorCol,
    required this.anchorRow,
    required this.constrainedCount,
    required this.constrainedDirection,
    required this.unconstrainedDirection,
  }) {
    _validate();
  }

  bool get isConstrainedAxisColumns => ['left', 'right'].contains(constrainedDirection);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewElementPlacementConfig &&
          runtimeType == other.runtimeType &&
          anchorCol == other.anchorCol &&
          anchorRow == other.anchorRow &&
          constrainedCount == other.constrainedCount &&
          constrainedDirection == other.constrainedDirection &&
          unconstrainedDirection == other.unconstrainedDirection;

  @override
  int get hashCode => Object.hash(anchorCol, anchorRow, constrainedCount, constrainedDirection, unconstrainedDirection);

  void _validate() {
    final validConstrainedDirs = ['left', 'right', 'up', 'down'];
    final validUnconstrainedDirs = ['left', 'right', 'up', 'down'];

    if (!validConstrainedDirs.contains(constrainedDirection)) {
      throw ArgumentError(
        'constrainedDirection must be one of: left, right, up, down',
      );
    }
    if (!validUnconstrainedDirs.contains(unconstrainedDirection)) {
      throw ArgumentError(
        'unconstrainedDirection must be one of: left, right, up, down',
      );
    }

    final constrainedIsHorizontal = ['left', 'right'].contains(constrainedDirection);
    final unconstrainedIsHorizontal = ['left', 'right'].contains(unconstrainedDirection);

    if (constrainedIsHorizontal == unconstrainedIsHorizontal) {
      throw ArgumentError(
        'constrainedDirection and unconstrainedDirection must be on perpendicular axes',
      );
    }
  }

  factory NewElementPlacementConfig.fromJson(Map<String, dynamic> json) {
    return NewElementPlacementConfig(
      anchorCol: json['anchor']['col'] as int? ?? 0,
      anchorRow: json['anchor']['row'] as int? ?? 0,
      constrainedCount: json['constrainedCount'] as int? ?? 5,
      constrainedDirection: json['constrainedDirection'] as String? ?? 'right',
      unconstrainedDirection: json['unconstrainedDirection'] as String? ?? 'down',
    );
  }

  Map<String, dynamic> toJson() => {
        'anchor': {
          'col': anchorCol,
          'row': anchorRow,
        },
        'constrainedCount': constrainedCount,
        'constrainedDirection': constrainedDirection,
        'unconstrainedDirection': unconstrainedDirection,
      };

  factory NewElementPlacementConfig.defaultConfig() {
    return NewElementPlacementConfig(
      anchorCol: 2,
      anchorRow: -2,
      constrainedCount: 5,
      constrainedDirection: 'right',
      unconstrainedDirection: 'up',
    );
  }
}
