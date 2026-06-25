import 'dart:ui' show Color;

import 'package:PiliPlus/utils/color_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColourUtils.parse2Int', () {
    test('parses hex color string to int with full opacity', () {
      expect(ColourUtils.parse2Int('#FF0000'), 0xFFFF0000);
      expect(ColourUtils.parse2Int('#00FF00'), 0xFF00FF00);
      expect(ColourUtils.parse2Int('#0000FF'), 0xFF0000FF);
      expect(ColourUtils.parse2Int('#000000'), 0xFF000000);
      expect(ColourUtils.parse2Int('#FFFFFF'), 0xFFFFFFFF);
    });
  });

  group('ColourUtils.parseColor', () {
    test('parses hex string to Color', () {
      final color = ColourUtils.parseColor('#FF0000');
      expect(color, const Color(0xFFFF0000));
    });

    test('parses black', () {
      final color = ColourUtils.parseColor('#000000');
      expect(color, const Color(0xFF000000));
    });
  });

  group('ColourUtils.index2Color', () {
    test('returns gold for index 0', () {
      expect(
        ColourUtils.index2Color(0, const Color(0xFF000000)),
        const Color(0xFFfdad13),
      );
    });

    test('returns blue for index 1', () {
      expect(
        ColourUtils.index2Color(1, const Color(0xFF000000)),
        const Color(0xFF8aace1),
      );
    });

    test('returns bronze for index 2', () {
      expect(
        ColourUtils.index2Color(2, const Color(0xFF000000)),
        const Color(0xFFdfa777),
      );
    });

    test('returns fallback color for other indices', () {
      const fallback = Color(0xFF123456);
      expect(ColourUtils.index2Color(3, fallback), fallback);
      expect(ColourUtils.index2Color(99, fallback), fallback);
    });
  });
}
