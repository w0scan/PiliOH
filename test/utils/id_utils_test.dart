import 'package:PiliPlus/utils/id_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdUtils.av2bv', () {
    test('generates valid BV id format', () {
      final bv = IdUtils.av2bv(170001);
      expect(bv.startsWith('BV1'), isTrue);
      expect(bv.length, 12);
    });

    test('generates different BV ids for different aids', () {
      expect(IdUtils.av2bv(1), isNot(equals(IdUtils.av2bv(2))));
      expect(IdUtils.av2bv(100), isNot(equals(IdUtils.av2bv(200))));
    });

    test('generates consistent BV ids', () {
      expect(IdUtils.av2bv(170001), IdUtils.av2bv(170001));
    });
  });

  group('IdUtils.bv2av', () {
    test('converts bv back to original av', () {
      final bv = IdUtils.av2bv(170001);
      expect(IdUtils.bv2av(bv), 170001);
    });
  });

  group('av2bv and bv2av roundtrip', () {
    test('roundtrip conversions are consistent', () {
      for (final aid in [1, 100, 12345, 170001, 455017605, 999999999]) {
        final bvid = IdUtils.av2bv(aid);
        final roundtripped = IdUtils.bv2av(bvid);
        expect(roundtripped, aid, reason: 'roundtrip failed for aid=$aid');
      }
    });
  });

  group('IdUtils.matchAvorBv', () {
    test('returns null for null input', () {
      final result = IdUtils.matchAvorBv(input: null);
      expect(result.av, isNull);
      expect(result.bv, isNull);
    });

    test('returns null for empty input', () {
      final result = IdUtils.matchAvorBv(input: '');
      expect(result.av, isNull);
      expect(result.bv, isNull);
    });

    test('matches av format', () {
      final result = IdUtils.matchAvorBv(input: 'av170001');
      expect(result.av, 170001);
      expect(result.bv, isNull);
    });

    test('matches bv format', () {
      final result = IdUtils.matchAvorBv(input: 'BV17x411w7KC');
      expect(result.av, isNull);
      expect(result.bv, 'BV17x411w7KC');
    });

    test('matches bv in URL', () {
      final result = IdUtils.matchAvorBv(
        input: 'https://www.bilibili.com/video/BV17x411w7KC',
      );
      expect(result.bv, 'BV17x411w7KC');
    });

    test('matches av in URL', () {
      final result = IdUtils.matchAvorBv(
        input: 'https://www.bilibili.com/video/av170001',
      );
      expect(result.av, 170001);
    });

    test('returns null for unrelated string', () {
      final result = IdUtils.matchAvorBv(input: 'hello world');
      expect(result.av, isNull);
      expect(result.bv, isNull);
    });

    test('prefers bv when both present', () {
      final result = IdUtils.matchAvorBv(
        input: 'BV17x411w7KC av12345',
      );
      expect(result.bv, 'BV17x411w7KC');
      expect(result.av, isNull);
    });
  });

  group('AvBvExt.isNotEmpty', () {
    test('returns false for empty result', () {
      const result = (av: null, bv: null);
      expect(result.isNotEmpty, isFalse);
    });

    test('returns true when av is set', () {
      final AvBvRes result = (av: 123, bv: null);
      expect(result.isNotEmpty, isTrue);
    });

    test('returns true when bv is set', () {
      final AvBvRes result = (av: null, bv: 'BV17x411w7KC');
      expect(result.isNotEmpty, isTrue);
    });
  });

  group('IdUtils.genAuroraEid', () {
    test('returns empty string for uid=0', () {
      expect(IdUtils.genAuroraEid(0), '');
    });

    test('returns non-empty base64 string for valid uid', () {
      final eid = IdUtils.genAuroraEid(12345);
      expect(eid.isNotEmpty, isTrue);
      expect(eid.contains('='), isFalse);
    });

    test('produces consistent results for same uid', () {
      expect(IdUtils.genAuroraEid(12345), IdUtils.genAuroraEid(12345));
    });

    test('produces different results for different uids', () {
      expect(
        IdUtils.genAuroraEid(12345) != IdUtils.genAuroraEid(67890),
        isTrue,
      );
    });
  });

  group('IdUtils.genTraceId', () {
    test('produces correctly formatted trace id', () {
      final traceId = IdUtils.genTraceId();
      final parts = traceId.split(':');
      expect(parts.length, 4);
      expect(parts[0].length, 32);
      expect(parts[1].length, 16);
      expect(parts[2], '0');
      expect(parts[3], '0');
    });

    test('second part is substring of first part', () {
      final traceId = IdUtils.genTraceId();
      final parts = traceId.split(':');
      expect(parts[0].substring(16, 32), parts[1]);
    });
  });

  group('IdUtils regex patterns', () {
    test('bvRegex matches valid BV ids', () {
      expect(IdUtils.bvRegex.hasMatch('BV17x411w7KC'), isTrue);
      expect(IdUtils.bvRegex.hasMatch('bv17x411w7KC'), isTrue);
    });

    test('bvRegex does not match invalid strings', () {
      expect(IdUtils.bvRegex.hasMatch('BV1'), isFalse);
      expect(IdUtils.bvRegex.hasMatch('hello'), isFalse);
    });

    test('bvRegexExact matches exactly', () {
      expect(IdUtils.bvRegexExact.hasMatch('BV17x411w7KC'), isTrue);
      expect(IdUtils.bvRegexExact.hasMatch('xxxBV17x411w7KCxxx'), isFalse);
    });

    test('avRegex matches av ids', () {
      expect(IdUtils.avRegex.hasMatch('av170001'), isTrue);
      expect(IdUtils.avRegex.hasMatch('AV170001'), isTrue);
    });

    test('avRegexExact matches exactly', () {
      expect(IdUtils.avRegexExact.hasMatch('av170001'), isTrue);
      expect(IdUtils.avRegexExact.hasMatch('xxxav170001xxx'), isFalse);
    });

    test('digitOnlyRegExp matches digits only', () {
      expect(IdUtils.digitOnlyRegExp.hasMatch('12345'), isTrue);
      expect(IdUtils.digitOnlyRegExp.hasMatch('abc'), isFalse);
      expect(IdUtils.digitOnlyRegExp.hasMatch('12a34'), isFalse);
    });
  });

  group('IdUtils.swap', () {
    test('swaps two elements in a list', () {
      final list = [1, 2, 3, 4, 5];
      IdUtils.swap(list, 0, 4);
      expect(list, [5, 2, 3, 4, 1]);
    });

    test('swap same index is no-op', () {
      final list = ['a', 'b', 'c'];
      IdUtils.swap(list, 1, 1);
      expect(list, ['a', 'b', 'c']);
    });
  });

  group('IdUtils.genBuvid3', () {
    test('ends with infoc', () {
      final buvid = IdUtils.genBuvid3();
      expect(buvid.endsWith('infoc'), isTrue);
    });

    test('has correct format', () {
      final buvid = IdUtils.genBuvid3();
      expect(buvid.length, greaterThan(30));
    });
  });
}
