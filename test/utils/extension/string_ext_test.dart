import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NullableStringExt.http2https', () {
    test('converts http:// to https://', () {
      expect('http://example.com'.http2https, 'https://example.com');
    });

    test('converts protocol-relative // to https://', () {
      expect('//example.com/path'.http2https, 'https://example.com/path');
    });

    test('keeps https:// unchanged', () {
      expect('https://example.com'.http2https, 'https://example.com');
    });

    test('returns empty string for null', () {
      const String? value = null;
      expect(value.http2https, '');
    });

    test('handles empty string', () {
      expect(''.http2https, '');
    });
  });

  group('NullableStringExt.isNullOrEmpty', () {
    test('returns true for null', () {
      const String? value = null;
      expect(value.isNullOrEmpty, isTrue);
    });

    test('returns true for empty string', () {
      expect(''.isNullOrEmpty, isTrue);
    });

    test('returns false for non-empty string', () {
      expect('hello'.isNullOrEmpty, isFalse);
      expect(' '.isNullOrEmpty, isFalse);
    });
  });

  group('StringExt.subLength', () {
    test('returns full string if shorter than length', () {
      expect('hi'.subLength(10), 'hi');
    });

    test('truncates to specified length', () {
      expect('hello world'.subLength(5), 'hello');
    });

    test('returns exact string when length matches', () {
      expect('abc'.subLength(3), 'abc');
    });

    test('handles empty string', () {
      expect(''.subLength(5), '');
    });
  });
}
