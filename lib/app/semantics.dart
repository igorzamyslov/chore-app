/// Stable-identifier plumbing for E2E and widget-test selectors.
library;

import 'package:flutter/widgets.dart';

/// Wraps [child] with a stable identifier for E2E selectors.
///
/// Implemented as `Semantics(identifier: id, container: true, child: ...)`.
/// [id] follows the `<screen>.<element>[.<qualifier>]` convention documented
/// in `docs/specs/ui-foundation-chores.md`; every interactive widget in the
/// app is wrapped with one. Tests (widget or E2E) locate the wrapped widget
/// via `find.bySemanticsIdentifier(id)`.
Widget semantic(String id, {required Widget child}) {
  return Semantics(identifier: id, container: true, child: child);
}
