import 'package:chore_app/features/shopping/quick_add_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitQuickAddInput (F7)', () {
    test('splits on commas and newlines, trims, drops empties', () {
      expect(splitQuickAddInput('Milch, Eier\nBrot'), [
        'Milch',
        'Eier',
        'Brot',
      ]);
      expect(splitQuickAddInput(' a ,, b ,\n\n c '), ['a', 'b', 'c']);
      expect(splitQuickAddInput('Windows\r\nLinux'), ['Windows', 'Linux']);
    });

    test('a single name is returned as is', () {
      expect(splitQuickAddInput('  Oat milk '), ['Oat milk']);
    });

    test('empty or separator-only input yields nothing', () {
      expect(splitQuickAddInput(''), isEmpty);
      expect(splitQuickAddInput(' , \n ,'), isEmpty);
    });
  });
}
