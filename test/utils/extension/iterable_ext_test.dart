import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NullableIterableExt.isNullOrEmpty', () {
    test('returns true for null', () {
      const List<int>? list = null;
      expect(list.isNullOrEmpty, isTrue);
    });

    test('returns true for empty list', () {
      expect(<int>[].isNullOrEmpty, isTrue);
    });

    test('returns false for non-empty list', () {
      expect([1, 2, 3].isNullOrEmpty, isFalse);
    });
  });

  group('IterableExt.reduceOrNull', () {
    test('returns null for empty iterable', () {
      expect(<int>[].reduceOrNull((a, b) => a + b), isNull);
    });

    test('returns single element for single-element iterable', () {
      expect([42].reduceOrNull((a, b) => a + b), 42);
    });

    test('reduces multiple elements', () {
      expect([1, 2, 3, 4].reduceOrNull((a, b) => a + b), 10);
    });
  });

  group('ListExt.removeFirstWhere', () {
    test('removes first matching element and returns true', () {
      final list = [1, 2, 3, 2, 4];
      final removed = list.removeFirstWhere((e) => e == 2);
      expect(removed, isTrue);
      expect(list, [1, 3, 2, 4]);
    });

    test('returns false when no match', () {
      final list = [1, 2, 3];
      final removed = list.removeFirstWhere((e) => e == 5);
      expect(removed, isFalse);
      expect(list, [1, 2, 3]);
    });

    test('works on empty list', () {
      final list = <int>[];
      expect(list.removeFirstWhere((e) => e == 1), isFalse);
    });
  });

  group('ListExt.fromCast', () {
    test('casts list elements', () {
      final list = [1, 2, 3];
      final result = list.fromCast<num>();
      expect(result, isA<List<num>>());
      expect(result, [1, 2, 3]);
    });
  });

  group('ListExt.getOrNull', () {
    test('returns element at valid index', () {
      expect([10, 20, 30].getOrNull(0), 10);
      expect([10, 20, 30].getOrNull(2), 30);
    });

    test('returns null for negative index', () {
      expect([10, 20, 30].getOrNull(-1), isNull);
    });

    test('returns null for out-of-bounds index', () {
      expect([10, 20, 30].getOrNull(3), isNull);
    });

    test('returns null for empty list', () {
      expect(<int>[].getOrNull(0), isNull);
    });
  });

  group('ListExt.getOrFirst', () {
    test('returns element at valid index', () {
      expect([10, 20, 30].getOrFirst(1), 20);
    });

    test('returns first element for out-of-bounds index', () {
      expect([10, 20, 30].getOrFirst(5), 10);
    });

    test('returns first element for negative index', () {
      expect([10, 20, 30].getOrFirst(-1), 10);
    });
  });

  group('ListExt.lowerBoundByKey', () {
    test('finds insertion point in sorted list', () {
      final list = [1, 3, 5, 7, 9];
      expect(list.lowerBoundByKey((e) => e, 5), 2);
      expect(list.lowerBoundByKey((e) => e, 6), 3);
      expect(list.lowerBoundByKey((e) => e, 0), 0);
      expect(list.lowerBoundByKey((e) => e, 10), 5);
    });

    test('works with empty list', () {
      expect(<int>[].lowerBoundByKey((e) => e, 5), 0);
    });

    test('works with start parameter', () {
      final list = [1, 3, 5, 7, 9];
      expect(list.lowerBoundByKey((e) => e, 3, 2), 2);
    });
  });

  group('ListExt.findClosestTarget', () {
    test('finds closest matching target', () {
      final list = [1, 5, 10, 15, 20];
      final result = list.findClosestTarget(
        (e) => e >= 8,
        (a, b) => (a - 12).abs() < (b - 12).abs() ? a : b,
      );
      expect(result, 10);
    });

    test('falls back to reduce when no elements match test', () {
      final list = [1, 5, 10];
      final result = list.findClosestTarget(
        (e) => e > 100,
        (a, b) => a < b ? a : b,
      );
      expect(result, 1);
    });
  });
}
