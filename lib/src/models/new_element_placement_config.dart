class NewElementPlacementConfig {
  final int anchorCol;
  final int anchorRow;
  final ConstrainedAxis constrainedAxis;
  final int constrainedCount;
  final String constrainedDirection;
  final String unconstrainedDirection;

  NewElementPlacementConfig({
    required this.anchorCol,
    required this.anchorRow,
    required this.constrainedAxis,
    required this.constrainedCount,
    required this.constrainedDirection,
    required this.unconstrainedDirection,
  }) {
    _validate();
  }

  void _validate() {
    if (constrainedAxis == ConstrainedAxis.columns) {
      if (!['left', 'right'].contains(constrainedDirection)) {
        throw ArgumentError(
          'constrainedDirection must be "left" or "right" when constrainedAxis is columns',
        );
      }
      if (!['up', 'down'].contains(unconstrainedDirection)) {
        throw ArgumentError(
          'unconstrainedDirection must be "up" or "down" when constrainedAxis is columns',
        );
      }
    } else {
      if (!['up', 'down'].contains(constrainedDirection)) {
        throw ArgumentError(
          'constrainedDirection must be "up" or "down" when constrainedAxis is rows',
        );
      }
      if (!['left', 'right'].contains(unconstrainedDirection)) {
        throw ArgumentError(
          'unconstrainedDirection must be "left" or "right" when constrainedAxis is rows',
        );
      }
    }
  }

  factory NewElementPlacementConfig.fromJson(Map<String, dynamic> json) {
    return NewElementPlacementConfig(
      anchorCol: json['anchor']['col'] as int? ?? 0,
      anchorRow: json['anchor']['row'] as int? ?? 0,
      constrainedAxis: json['constrainedAxis'] == 'rows'
          ? ConstrainedAxis.rows
          : ConstrainedAxis.columns,
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
        'constrainedAxis': constrainedAxis == ConstrainedAxis.rows ? 'rows' : 'columns',
        'constrainedCount': constrainedCount,
        'constrainedDirection': constrainedDirection,
        'unconstrainedDirection': unconstrainedDirection,
      };

  factory NewElementPlacementConfig.defaultConfig() {
    return NewElementPlacementConfig(
      anchorCol: 0,
      anchorRow: 0,
      constrainedAxis: ConstrainedAxis.columns,
      constrainedCount: 5,
      constrainedDirection: 'right',
      unconstrainedDirection: 'down',
    );
  }
}

enum ConstrainedAxis {
  columns,
  rows,
}
