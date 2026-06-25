import 'package:PiliPlus/utils/extension/map_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapExt.fromCast', () {
    test('casts map types', () {
      final map = {'a': 1, 'b': 2};
      final result = map.fromCast<String, num>();
      expect(result, isA<Map<String, num>>());
      expect(result['a'], 1);
      expect(result['b'], 2);
    });

    test('casts empty map', () {
      final map = <String, int>{};
      final result = map.fromCast<String, num>();
      expect(result, isEmpty);
    });
  });
}
