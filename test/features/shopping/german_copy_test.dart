import 'package:chore_app/l10n/app_localizations_de.dart';
import 'package:flutter_test/flutter_test.dart';

/// F13 (persona review 2026-10-06, tom-shopping Q2): the German shopping and
/// sync copy. Pinned because the wording is the whole fix.
void main() {
  final de = AppLocalizationsDe();

  test('the cart button speaks the cart metaphor, like its header', () {
    expect(de.shoppingClearButton, 'Einkaufswagen leeren');
    expect(de.shoppingCartHeader(2), 'Im Einkaufswagen (2)');
    expect(de.shoppingUncheckAll, 'Alles zurücklegen');
  });

  test('the sync banner is short, du-form and uses an em dash', () {
    expect(
      de.syncHealthBannerMessage,
      'Gerade keine Verbindung zum Haushalt. Deine Änderungen sind '
      'gespeichert — zieh die Liste nach unten, um es erneut zu versuchen.',
    );
  });

  test('no sync string mixes in an en dash', () {
    final syncStrings = [
      de.syncHealthBannerMessage,
      de.syncRefreshError,
      de.syncRefreshErrorRevoked,
      de.syncRefreshErrorRejected,
    ];
    for (final text in syncStrings) {
      expect(text, isNot(contains('–')), reason: text);
    }
  });

  test('the new shopping strings are du-form German', () {
    expect(de.shoppingRemainingCount(7), 'Noch 7');
    expect(de.shoppingRemainingCount(0), 'Nichts mehr offen');
    expect(de.shoppingCheckedSnackbar, 'Im Einkaufswagen');
    expect(de.shoppingPutBackSnackbar(1), '1 Artikel zurückgelegt');
    expect(de.shoppingPutBackSnackbar(3), '3 Artikel zurückgelegt');
    expect(de.shoppingAddedCount(3), '3 Artikel hinzugefügt');
    expect(de.shoppingSuggestionForget, 'Vorschlag vergessen');
    expect(de.syncPendingItemTooltip, 'Wartet aufs Senden');
    expect(
      de.shoppingSyncedAgo(de.relativeTimeMinutesAgo(5)),
      'synchronisiert vor 5 Min.',
    );
    expect(de.relativeTimeJustNow, 'gerade eben');
  });
}
