import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DurationUtils.formatDuration', () {
    test('formats null as 00:00', () {
      expect(DurationUtils.formatDuration(null), '00:00');
    });

    test('formats 0 as 00:00', () {
      expect(DurationUtils.formatDuration(0), '00:00');
    });

    test('formats seconds only', () {
      expect(DurationUtils.formatDuration(5), '00:05');
      expect(DurationUtils.formatDuration(59), '00:59');
    });

    test('formats minutes and seconds', () {
      expect(DurationUtils.formatDuration(60), '01:00');
      expect(DurationUtils.formatDuration(125), '02:05');
      expect(DurationUtils.formatDuration(3599), '59:59');
    });

    test('formats hours, minutes and seconds', () {
      expect(DurationUtils.formatDuration(3600), '01:00:00');
      expect(DurationUtils.formatDuration(3661), '01:01:01');
      expect(DurationUtils.formatDuration(7200), '02:00:00');
    });

    test('formats double seconds with milliseconds', () {
      expect(DurationUtils.formatDuration(1.5), '00:01.500');
      expect(DurationUtils.formatDuration(61.123), '01:01.123');
    });
  });

  group('DurationUtils.parseDuration', () {
    test('returns 0 for null', () {
      expect(DurationUtils.parseDuration(null), 0);
    });

    test('returns 0 for empty string', () {
      expect(DurationUtils.parseDuration(''), 0);
    });

    test('parses seconds only', () {
      expect(DurationUtils.parseDuration('30'), 30);
    });

    test('parses minutes:seconds', () {
      expect(DurationUtils.parseDuration('1:30'), 90);
      expect(DurationUtils.parseDuration('02:05'), 125);
      expect(DurationUtils.parseDuration('59:59'), 3599);
    });

    test('parses hours:minutes:seconds', () {
      expect(DurationUtils.parseDuration('1:00:00'), 3600);
      expect(DurationUtils.parseDuration('1:01:01'), 3661);
      expect(DurationUtils.parseDuration('2:00:00'), 7200);
    });

    test('parses with full-width colon', () {
      expect(DurationUtils.parseDuration('1：30'), 90);
    });
  });

  group('DurationUtils.formatTimeDuration', () {
    test('formats minutes', () {
      expect(
        DurationUtils.formatTimeDuration(const Duration(minutes: 30)),
        '30分钟',
      );
    });

    test('formats hours and minutes', () {
      expect(
        DurationUtils.formatTimeDuration(const Duration(hours: 2, minutes: 30)),
        '2小时30分钟',
      );
    });

    test('formats days', () {
      expect(
        DurationUtils.formatTimeDuration(const Duration(days: 5)),
        '5天',
      );
    });

    test('formats months and days', () {
      expect(
        DurationUtils.formatTimeDuration(const Duration(days: 45)),
        '1月15天',
      );
    });

    test('formats years', () {
      expect(
        DurationUtils.formatTimeDuration(const Duration(days: 400)),
        '1年1月5天',
      );
    });

    test('formats zero duration as empty string', () {
      expect(
        DurationUtils.formatTimeDuration(Duration.zero),
        '',
      );
    });
  });

  group('DurationUtils.formatDurationBetween', () {
    test('formats difference between timestamps', () {
      const start = 0;
      const end = 3600000; // 1 hour in millis
      expect(DurationUtils.formatDurationBetween(start, end), '1小时');
    });

    test('formats multi-unit difference', () {
      const start = 0;
      const end = 5400000; // 1.5 hours in millis
      expect(DurationUtils.formatDurationBetween(start, end), '1小时30分钟');
    });
  });
}
