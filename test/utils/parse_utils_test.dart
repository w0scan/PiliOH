import 'package:PiliPlus/utils/parse_int.dart';
import 'package:PiliPlus/utils/parse_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeToInt', () {
    test('returns int from int', () {
      expect(safeToInt(42), 42);
      expect(safeToInt(0), 0);
      expect(safeToInt(-5), -5);
    });

    test('returns int from String', () {
      expect(safeToInt('42'), 42);
      expect(safeToInt('0'), 0);
      expect(safeToInt('-5'), -5);
    });

    test('returns null from unparseable String', () {
      expect(safeToInt('abc'), isNull);
      expect(safeToInt(''), isNull);
    });

    test('returns int from double/num', () {
      expect(safeToInt(3.14), 3);
      expect(safeToInt(0.0), 0);
      expect(safeToInt(99.9), 99);
    });

    test('returns null for null', () {
      expect(safeToInt(null), isNull);
    });

    test('returns null for bool', () {
      expect(safeToInt(true), isNull);
    });

    test('returns null for list', () {
      expect(safeToInt([1, 2, 3]), isNull);
    });
  });

  group('nonNullOrEmptyString', () {
    test('returns null for null', () {
      expect(nonNullOrEmptyString(null), isNull);
    });

    test('returns null for empty string', () {
      expect(nonNullOrEmptyString(''), isNull);
    });

    test('returns the string for non-empty value', () {
      expect(nonNullOrEmptyString('hello'), 'hello');
      expect(nonNullOrEmptyString(' '), ' ');
    });
  });
}
