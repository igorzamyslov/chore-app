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

  group('parseQuantity (F6)', () {
    void expectParsed(String raw, String name, String? note) {
      final parsed = parseQuantity(raw);
      expect(parsed.name, name, reason: raw);
      expect(parsed.quantityNote, note, reason: raw);
    }

    test('leading count: "2 Milch", "2x Milch", "2 x Milch", "2× Milch"', () {
      expectParsed('2 Milch', 'Milch', '2');
      expectParsed('2x Milch', 'Milch', '2');
      expectParsed('2 x Milch', 'Milch', '2');
      expectParsed('2× Milch', 'Milch', '2');
      expectParsed('12 Oat milk', 'Oat milk', '12');
    });

    test('trailing count: "Milch x2", "Milch ×2", "Milch x 2"', () {
      expectParsed('Milch x2', 'Milch', '2');
      expectParsed('Milch ×2', 'Milch', '2');
      expectParsed('Milch x 2', 'Milch', '2');
      expectParsed('Oat milk X3', 'Oat milk', '3');
    });

    test('trims and leaves everything else alone', () {
      expectParsed('  3 Eier ', 'Eier', '3');
      expectParsed('Milch', 'Milch', null);
      expectParsed('7up', '7up', null);
      expectParsed('2', '2', null);
      expectParsed('3,5 % Milch', '3,5 % Milch', null);
      expectParsed('Milch 2', 'Milch 2', null);
      expectParsed('Vitamin x', 'Vitamin x', null);
    });

    test('an "x" that starts a word is part of the name', () {
      expectParsed('2 xylophone', 'xylophone', '2');
    });
  });
}
