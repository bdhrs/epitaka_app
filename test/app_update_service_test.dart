import 'package:flutter_test/flutter_test.dart';

import 'package:epitaka/features/update/app_update_service.dart';

void main() {
  group('Version', () {
    test('parses release tags with or without v prefix', () {
      expect(Version.parse('v1.2.3'), const Version(1, 2, 3));
      expect(Version.parse('1.2.3'), const Version(1, 2, 3));
      expect(Version.parse('v1.2.3-beta.1'), const Version(1, 2, 3));
    });

    test('rejects malformed versions', () {
      expect(Version.parse('latest'), isNull);
      expect(Version.parse('1.2'), isNull);
      expect(Version.parse(''), isNull);
    });

    test('compares major, minor, and patch components', () {
      expect(Version.parse('1.10.0')! > Version.parse('1.9.9')!, isTrue);
      expect(Version.parse('2.0.0')! > Version.parse('1.99.99')!, isTrue);
      expect(Version.parse('1.2.3')! <= Version.parse('1.2.3')!, isTrue);
    });
  });
}
