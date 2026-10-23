// 流用元: reference/agari_cam/lib/ml/reshape.dart（2026-10-21 時点）
extension ReshapeList<T> on List<T> {
  /// Reshape a 1-D list to a nested List with the given [shape].
  /// Example: List.filled(6, 0).reshape([2,3]) -> [[0,0,0],[0,0,0]]
  dynamic reshape(List<int> shape) {
    if (shape.isEmpty) return this;
    int total = 1;
    for (final d in shape) {
      total *= d;
    }
    if (length < total) {
      throw ArgumentError(
        'reshape: input length $length < required $total for shape $shape',
      );
    }
    int idx = 0;
    dynamic build(int dim) {
      final cnt = shape[dim];
      if (dim == shape.length - 1) {
        // leaf
        final out = List<T>.filled(cnt, this[idx]);
        for (int i = 0; i < cnt; i++) {
          out[i] = this[idx++];
        }
        return out;
      } else {
        return List.generate(cnt, (_) => build(dim + 1));
      }
    }

    return build(0);
  }
}
