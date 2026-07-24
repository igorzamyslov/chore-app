import 'package:chore_app/features/shopping/shopping_edit_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateItemName', () {
    test('empty name returns ItemNameError.required', () {
      expect(validateItemName(''), ItemNameError.required);
    });

    test('non-empty name returns null', () {
      expect(validateItemName('Milk'), isNull);
    });
  });
}
