import 'dart:convert';

import 'package:chore_app/application/digest_action_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('round trip', () {
    test('an attributed payload survives encode -> decode', () {
      final decoded = decodeDigestActionPayload(
        encodeDigestActionPayload(
          occurrenceId: 'occ-1',
          actingMemberId: 'member-7',
        ),
      );
      expect(decoded!.occurrenceId, 'occ-1');
      expect(decoded.actingMemberId, 'member-7');
    });

    test('an UNATTRIBUTED payload survives too, keeping null a null', () {
      // The important half: `by: null` means "identity genuinely unknown" and
      // must arrive as null, not as an empty string or a guessed member --
      // that guess is the misattribution backlog A-5 closed.
      final decoded = decodeDigestActionPayload(
        encodeDigestActionPayload(occurrenceId: 'occ-1', actingMemberId: null),
      );
      expect(decoded!.occurrenceId, 'occ-1');
      expect(decoded.actingMemberId, isNull);
    });

    test('the encoded form is a JSON object with the versioned schema', () {
      expect(
        jsonDecode(
          encodeDigestActionPayload(
            occurrenceId: 'occ-1',
            actingMemberId: 'member-7',
          ),
        ),
        {'v': digestActionPayloadVersion, 'occ': 'occ-1', 'by': 'member-7'},
      );
    });
  });

  group('decode tolerates garbage instead of throwing', () {
    // The payload crosses a process boundary from the OS and may have been
    // written by a version of this app the user has since upgraded past.
    // Every one of these means the same thing: do nothing. There is no UI in
    // the background isolate to report an error to.
    test('null and empty', () {
      expect(decodeDigestActionPayload(null), isNull);
      expect(decodeDigestActionPayload(''), isNull);
    });

    test('malformed JSON', () {
      expect(decodeDigestActionPayload('{not json'), isNull);
      expect(decodeDigestActionPayload('occ-1'), isNull);
    });

    test('valid JSON that is not an object', () {
      expect(decodeDigestActionPayload('[1,2,3]'), isNull);
      expect(decodeDigestActionPayload('42'), isNull);
      expect(decodeDigestActionPayload('null'), isNull);
    });

    test('an unknown schema version', () {
      expect(
        decodeDigestActionPayload('{"v":99,"occ":"occ-1","by":null}'),
        isNull,
        reason:
            'a future version may mean something else entirely; acting on a '
            'payload this build only half-understands is worse than ignoring '
            'it',
      );
      expect(decodeDigestActionPayload('{"occ":"occ-1","by":null}'), isNull);
      expect(
        decodeDigestActionPayload('{"v":"1","occ":"occ-1","by":null}'),
        isNull,
      );
    });

    test('a missing, blank, or non-string occurrence id', () {
      expect(decodeDigestActionPayload('{"v":1,"by":null}'), isNull);
      expect(decodeDigestActionPayload('{"v":1,"occ":"","by":null}'), isNull);
      expect(decodeDigestActionPayload('{"v":1,"occ":7,"by":null}'), isNull);
      expect(decodeDigestActionPayload('{"v":1,"occ":null,"by":null}'), isNull);
    });

    test('a non-string `by` degrades to unattributed rather than losing the '
        'whole tap', () {
      final decoded = decodeDigestActionPayload('{"v":1,"occ":"occ-1","by":7}');
      expect(decoded!.occurrenceId, 'occ-1');
      expect(decoded.actingMemberId, isNull);
    });
  });
}
