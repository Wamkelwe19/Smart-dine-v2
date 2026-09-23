import 'package:flutter_test/flutter_test.dart';
import 'package:ump_smart_dine/core/utils/formatters.dart';

/// REQ-2 and REQ-54: cart arithmetic in rand, two decimal places.
///
/// Money used to be a Dart `double` read straight from a numeric column and
/// multiplied by quantity, which is exactly the shape of bug these tests exist
/// to catch. It is integer cents now.
void main() {
  group('Money.format', () {
    test('always shows two decimal places', () {
      expect(Money.format(0), 'R 0.00');
      expect(Money.format(5), 'R 0.05');
      expect(Money.format(50), 'R 0.50');
      expect(Money.format(100), 'R 1.00');
      expect(Money.format(1050), 'R 10.50');
    });

    test('groups thousands', () {
      expect(Money.format(100000), 'R 1 000.00');
      expect(Money.format(1234567), 'R 12 345.67');
    });

    test('handles negatives', () {
      expect(Money.format(-1050), '-R 10.50');
    });
  });

  group('Money.centsFromRands', () {
    test('converts without floating point drift', () {
      expect(Money.centsFromRands(10.50), 1050);
      expect(Money.centsFromRands(0.1), 10);
      expect(Money.centsFromRands(19.99), 1999);
    });

    test('rounds rather than truncates', () {
      // 0.1 + 0.2 == 0.30000000000000004 in binary floating point. Truncating
      // would give 30 cents here only by luck; rounding is what makes it safe.
      expect(Money.centsFromRands(0.1 + 0.2), 30);
      expect(Money.centsFromRands(2.675), 268);
    });

    test('a line total in cents never drifts, however many units', () {
      const unitPriceCents = 1999; // R19.99
      var total = 0;
      for (var i = 0; i < 100; i++) {
        total += unitPriceCents;
      }
      expect(total, 199900);
      expect(Money.format(total), 'R 1 999.00');

      // The same sum done in floating point rand does drift.
      var floating = 0.0;
      for (var i = 0; i < 100; i++) {
        floating += 19.99;
      }
      expect(floating == 1999.0, isFalse,
          reason: 'demonstrates why prices are stored as integer cents');
    });
  });

  group('TimeAgo', () {
    test('describes recent times in words', () {
      final now = DateTime.now();
      expect(TimeAgo.format(now), 'Just now');
      expect(TimeAgo.format(now.subtract(const Duration(minutes: 1))), '1 min ago');
      expect(TimeAgo.format(now.subtract(const Duration(minutes: 5))), '5 mins ago');
      expect(TimeAgo.format(now.subtract(const Duration(hours: 1))), '1 hour ago');
      expect(TimeAgo.format(now.subtract(const Duration(days: 2))), '2 days ago');
    });

    test('returns an empty string for a null timestamp', () {
      expect(TimeAgo.format(null), '');
      expect(TimeAgo.clock(null), '');
    });

    test('formats midnight and noon correctly on a 12-hour clock', () {
      expect(TimeAgo.clock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(TimeAgo.clock(DateTime(2026, 1, 1, 12, 5)), '12:05 PM');
      expect(TimeAgo.clock(DateTime(2026, 1, 1, 13, 30)), '1:30 PM');
    });
  });
}
