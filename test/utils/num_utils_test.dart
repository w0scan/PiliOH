import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NumUtils.parseNum', () {
    test('parses plain integers', () {
      expect(NumUtils.parseNum('123'), 123);
      expect(NumUtils.parseNum('0'), 0);
      expect(NumUtils.parseNum('999999'), 999999);
    });

    test('parses numbers with Chinese units', () {
      expect(NumUtils.parseNum('1.5万'), 15000);
      expect(NumUtils.parseNum('2万'), 20000);
      expect(NumUtils.parseNum('1亿'), 100000000);
      expect(NumUtils.parseNum('3.5亿'), 350000000);
      expect(NumUtils.parseNum('5千'), 5000);
    });

    test('returns 0 for dash', () {
      expect(NumUtils.parseNum('-'), 0);
    });

    test('returns 0 for unparseable string', () {
      expect(NumUtils.parseNum('abc'), 0);
      expect(NumUtils.parseNum(''), 0);
    });

    test('parses decimal numbers', () {
      expect(NumUtils.parseNum('1.5'), 1);
      expect(NumUtils.parseNum('99.9'), 99);
    });
  });

  group('NumUtils.numFormat', () {
    test('formats null as 0', () {
      expect(NumUtils.numFormat(null), '0');
    });

    test('formats small numbers as-is', () {
      expect(NumUtils.numFormat(0), '0');
      expect(NumUtils.numFormat(999), '999');
      expect(NumUtils.numFormat(9999), '9999');
    });

    test('formats numbers >= 10000 with wan', () {
      expect(NumUtils.numFormat(10000), '1万');
      expect(NumUtils.numFormat(15000), '1.5万');
      expect(NumUtils.numFormat(100000), '10万');
      expect(NumUtils.numFormat(1234567), '123.5万');
    });

    test('formats numbers >= 100000000 with yi', () {
      expect(NumUtils.numFormat(100000000), '1亿');
      expect(NumUtils.numFormat(150000000), '1.5亿');
      expect(NumUtils.numFormat(1000000000), '10亿');
    });

    test('formats string numbers', () {
      expect(NumUtils.numFormat('10000'), '1万');
      expect(NumUtils.numFormat('999'), '999');
    });

    test('returns non-numeric strings as-is', () {
      expect(NumUtils.numFormat('abc'), 'abc');
    });
  });

  group('NumUtils.formatPositiveDecimal', () {
    test('formats numbers < 1000 without commas', () {
      expect(NumUtils.formatPositiveDecimal(0), '0');
      expect(NumUtils.formatPositiveDecimal(1), '1');
      expect(NumUtils.formatPositiveDecimal(999), '999');
    });

    test('formats thousands with commas', () {
      expect(NumUtils.formatPositiveDecimal(1000), '1,000');
      expect(NumUtils.formatPositiveDecimal(1234), '1,234');
      expect(NumUtils.formatPositiveDecimal(12345), '12,345');
      expect(NumUtils.formatPositiveDecimal(123456), '123,456');
    });

    test('formats millions with commas', () {
      expect(NumUtils.formatPositiveDecimal(1000000), '1,000,000');
      expect(NumUtils.formatPositiveDecimal(1234567), '1,234,567');
    });

    test('formats large numbers correctly', () {
      expect(NumUtils.formatPositiveDecimal(1000000000), '1,000,000,000');
    });
  });
}
