import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  // M0 hello-world gate (10 M0). Real suites arrive with the milestone that owns them.
  test('package identifies itself', () {
    expect(packageName, 'sync_engine');
  });
}
