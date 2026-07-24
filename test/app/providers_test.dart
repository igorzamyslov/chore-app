import 'package:chore_app/app/providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveClock', () {
    test('empty E2E_TODAY returns the real system clock', () {
      final clock = resolveClock('');
      expect(clock, const Clock());
    });

    test('a date pins the clock to that date at 09:00 local', () {
      final clock = resolveClock('2026-07-24');
      expect(clock.now(), DateTime(2026, 7, 24, 9));
    });

    test('a malformed date throws', () {
      expect(() => resolveClock('not-a-date'), throwsFormatException);
    });
  });
}
