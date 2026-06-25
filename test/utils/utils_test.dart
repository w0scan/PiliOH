import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Utils.isStringNumeric', () {
    test('returns true for integer strings', () {
      expect(Utils.isStringNumeric('123'), isTrue);
      expect(Utils.isStringNumeric('0'), isTrue);
    });

    test('returns true for decimal strings', () {
      expect(Utils.isStringNumeric('1.5'), isTrue);
      expect(Utils.isStringNumeric('0.01'), isTrue);
    });

    test('returns false for non-numeric strings', () {
      expect(Utils.isStringNumeric('abc'), isFalse);
      expect(Utils.isStringNumeric(''), isFalse);
      expect(Utils.isStringNumeric('12a34'), isFalse);
    });

    test('returns false for negative numbers', () {
      expect(Utils.isStringNumeric('-1'), isFalse);
    });
  });

  group('Utils.generateRandomString', () {
    test('generates string of correct length', () {
      expect(Utils.generateRandomString(0).length, 0);
      expect(Utils.generateRandomString(1).length, 1);
      expect(Utils.generateRandomString(10).length, 10);
      expect(Utils.generateRandomString(32).length, 32);
    });

    test('generates string with valid characters', () {
      final result = Utils.generateRandomString(100);
      expect(
        RegExp(r'^[0-9a-z]+$').hasMatch(result),
        isTrue,
      );
    });

    test('generates different strings on consecutive calls', () {
      final a = Utils.generateRandomString(32);
      final b = Utils.generateRandomString(32);
      // Extremely unlikely to be equal
      expect(a, isNot(equals(b)));
    });
  });

  group('Utils.getFileName', () {
    test('extracts filename from URL', () {
      expect(
        Utils.getFileName('https://example.com/path/file.jpg'),
        'file.jpg',
      );
    });

    test('extracts filename without extension', () {
      expect(
        Utils.getFileName(
          'https://example.com/path/file.jpg',
          fileExt: false,
        ),
        'file',
      );
    });

    test('extracts filename from URL with query params', () {
      expect(
        Utils.getFileName('https://example.com/path/file.jpg?w=100&h=200'),
        'file.jpg',
      );
    });

    test('extracts filename without ext from URL with query params', () {
      expect(
        Utils.getFileName(
          'https://example.com/path/file.jpg?w=100',
          fileExt: false,
        ),
        'file',
      );
    });

    test('handles URL with multiple dots', () {
      expect(
        Utils.getFileName('https://cdn.example.com/path/image.thumb.png'),
        'image.thumb.png',
      );
    });

    test('handles URL without extension', () {
      expect(
        Utils.getFileName('https://example.com/path/filename'),
        'filename',
      );
    });
  });

  group('Utils.makeHeroTag', () {
    test('produces string starting with input', () {
      final tag = Utils.makeHeroTag('video');
      expect(tag.startsWith('video'), isTrue);
    });

    test('produces unique tags', () {
      final tags = List.generate(100, (_) => Utils.makeHeroTag('test'));
      // With random suffix, most should be unique
      expect(tags.toSet().length, greaterThan(50));
    });
  });

  group('Utils.generateRandomBytes', () {
    test('generates bytes within length range', () {
      final bytes = Utils.generateRandomBytes(5, 10);
      expect(bytes.length, inInclusiveRange(5, 10));
    });

    test('generates bytes in valid range', () {
      final bytes = Utils.generateRandomBytes(10, 20);
      for (final b in bytes) {
        expect(b, greaterThanOrEqualTo(0x26));
        expect(b, lessThanOrEqualTo(0x7E));
      }
    });
  });

  group('Utils.base64EncodeRandomString', () {
    test('produces non-empty string', () {
      final result = Utils.base64EncodeRandomString(5, 10);
      expect(result.isNotEmpty, isTrue);
    });

    test('removes trailing padding', () {
      final result = Utils.base64EncodeRandomString(10, 20);
      expect(result.endsWith('=='), isFalse);
    });
  });
}
