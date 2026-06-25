import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoubleExt.toPrecision', () {
    test('rounds to 1 decimal place', () {
      expect(1.55.toPrecision(1), 1.6);
      expect(1.54.toPrecision(1), 1.5);
      expect(1.0.toPrecision(1), 1.0);
    });

    test('rounds to 2 decimal places', () {
      expect(1.555.toPrecision(2), 1.56);
      expect(1.551.toPrecision(2), 1.55);
    });

    test('rounds to 0 decimal places', () {
      expect(1.5.toPrecision(0), 2.0);
      expect(1.4.toPrecision(0), 1.0);
    });
  });

  group('DoubleExt.equals', () {
    test('returns true for equal values', () {
      expect(1.0.equals(1.0), isTrue);
    });

    test('returns true for values within epsilon', () {
      expect((0.1 + 0.2).equals(0.3), isTrue);
    });

    test('returns false for values outside epsilon', () {
      expect(1.0.equals(2.0), isFalse);
    });

    test('custom epsilon', () {
      expect(1.0.equals(1.5, 1.0), isTrue);
      expect(1.0.equals(2.5, 1.0), isFalse);
    });
  });

  group('DoubleExt.lerp', () {
    test('interpolates at 0', () {
      expect(0.0.lerp(10.0, 20.0), 10.0);
    });

    test('interpolates at 1', () {
      expect(1.0.lerp(10.0, 20.0), 20.0);
    });

    test('interpolates at 0.5', () {
      expect(0.5.lerp(10.0, 20.0), 15.0);
    });

    test('interpolates at 0.25', () {
      expect(0.25.lerp(0.0, 100.0), 25.0);
    });
  });

  group('IntExt nullable operators', () {
    test('adds to non-null int', () {
      const int? value = 5;
      expect(value + 3, 8);
    });

    test('returns null when adding to null', () {
      const int? value = null;
      expect(value + 3, isNull);
    });

    test('subtracts from non-null int', () {
      const int? value = 10;
      expect(value - 3, 7);
    });

    test('returns null when subtracting from null', () {
      const int? value = null;
      expect(value - 3, isNull);
    });
  });
}
