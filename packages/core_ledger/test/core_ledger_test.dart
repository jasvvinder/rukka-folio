@Tags(['A'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

void main() {
  // M0 hello-world gate (10 M0). Real suites arrive with the milestone that owns them.
  test('A-10-1 package identifies itself', () {
    expect(packageName, 'core_ledger');
  });
}
