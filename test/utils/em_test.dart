import 'package:PiliPlus/utils/em.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Em.regCate', () {
    test('extracts text from HTML tags', () {
      expect(Em.regCate('<em>hello</em>'), 'hello');
    });

    test('extracts last match from multiple tags', () {
      expect(Em.regCate('<em>first</em><em>second</em>'), 'second');
    });

    test('returns original string when no tags', () {
      expect(Em.regCate('hello'), 'hello');
    });

    test('returns original for empty string', () {
      expect(Em.regCate(''), '');
    });
  });

  group('Em.regTitle', () {
    test('parses plain text', () {
      final result = Em.regTitle('hello world');
      expect(result.length, 1);
      expect(result[0].isEm, isFalse);
      expect(result[0].text, 'hello world');
    });

    test('parses text with em tags', () {
      final result = Em.regTitle('before <em>highlighted</em> after');
      expect(result.length, 3);
      expect(result[0].isEm, isFalse);
      expect(result[0].text, 'before ');
      expect(result[1].isEm, isTrue);
      expect(result[1].text, 'highlighted');
      expect(result[2].isEm, isFalse);
      expect(result[2].text, ' after');
    });

    test('parses only em content', () {
      final result = Em.regTitle('<em>only</em>');
      expect(result.length, 1);
      expect(result[0].isEm, isTrue);
      expect(result[0].text, 'only');
    });

    test('handles multiple em tags', () {
      final result = Em.regTitle('<em>a</em> and <em>b</em>');
      expect(result.length, 3);
      expect(result[0].isEm, isTrue);
      expect(result[0].text, 'a');
      expect(result[1].isEm, isFalse);
      expect(result[1].text, ' and ');
      expect(result[2].isEm, isTrue);
      expect(result[2].text, 'b');
    });

    test('decodes HTML entities in non-em text', () {
      final result = Em.regTitle('a &lt; b &gt; c');
      expect(result.length, 1);
      expect(result[0].text, 'a < b > c');
    });

    test('decodes &amp; entity', () {
      final result = Em.regTitle('a &amp; b');
      expect(result.length, 1);
      expect(result[0].text, 'a & b');
    });

    test('decodes &quot; entity', () {
      final result = Em.regTitle('say &quot;hello&quot;');
      expect(result.length, 1);
      expect(result[0].text, 'say "hello"');
    });

    test('decodes &apos; entity', () {
      final result = Em.regTitle("it&apos;s");
      expect(result.length, 1);
      expect(result[0].text, "it's");
    });

    test('decodes &nbsp; entity', () {
      final result = Em.regTitle('a&nbsp;b');
      expect(result.length, 1);
      expect(result[0].text, 'a b');
    });

    test('decodes hex entity', () {
      final result = Em.regTitle('&#x41;'); // 'A'
      expect(result.length, 1);
      expect(result[0].text, 'A');
    });

    test('returns empty list for empty string', () {
      final result = Em.regTitle('');
      expect(result, isEmpty);
    });
  });
}
