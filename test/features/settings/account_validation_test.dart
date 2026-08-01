import 'package:chore_app/features/settings/account_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPlausibleEmail', () {
    test('empty string is not plausible', () {
      expect(isPlausibleEmail(''), isFalse);
    });

    test('missing @ is not plausible', () {
      expect(isPlausibleEmail('not-an-email'), isFalse);
    });

    test('missing local part is not plausible', () {
      expect(isPlausibleEmail('@example.com'), isFalse);
    });

    test('missing domain is not plausible', () {
      expect(isPlausibleEmail('me@'), isFalse);
    });

    test('domain without a dot is not plausible', () {
      expect(isPlausibleEmail('me@localhost'), isFalse);
    });

    test('domain with a leading or trailing dot is not plausible', () {
      expect(isPlausibleEmail('me@.com'), isFalse);
      expect(isPlausibleEmail('me@example.'), isFalse);
    });

    test('a normal address is plausible', () {
      expect(isPlausibleEmail('me@example.com'), isTrue);
    });
  });
}
