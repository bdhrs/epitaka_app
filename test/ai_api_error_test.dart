import 'package:epitaka/features/shared/models/ai_api_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeAiError', () {
    test('429 maps to rate limit', () {
      final info = describeAiError(Exception('API error 429: Quota exceeded'));
      expect(info.statusCode, 429);
      expect(info.isKnown, isTrue);
      expect(info.title.toLowerCase(), contains('rate limit'));
      expect(info.googleQuery, isNotEmpty);
      expect(info.googleUrl.toString(), contains('google.com/search'));
    });

    test('404 maps to model not found', () {
      final info = describeAiError(
        Exception('API error 404: models/x not found'),
      );
      expect(info.statusCode, 404);
      expect(info.isKnown, isTrue);
    });

    test('503 advises retry later', () {
      final info = describeAiError(Exception('API error 503: overloaded'));
      expect(info.statusCode, 503);
      expect(info.advice.toLowerCase(), contains('heavy load'));
    });

    test('401 maps to invalid key', () {
      final info = describeAiError(Exception('API error 401: invalid key'));
      expect(info.isKnown, isTrue);
    });

    test('unknown code shows full error and google fallback', () {
      final info = describeAiError(Exception('API error 418: teapot'));
      expect(info.isKnown, isFalse);
      expect(info.detail, contains('teapot'));
      expect(info.googleQuery, contains('teapot'));
    });

    test('network error is known', () {
      final info = describeAiError(
        Exception('SocketException: Failed host lookup'),
      );
      expect(info.isKnown, isTrue);
    });

    test('connection closed before header is a known network error', () {
      final info = describeAiError(
        Exception(
          'ClientException: Connection closed before full header was '
          'received, uri=https://generativelanguage.googleapis.com/v1beta/models/x:streamGenerateContent?alt=sse&key=SECRET123',
        ),
      );
      expect(info.isKnown, isTrue);
      expect(info.title.toLowerCase(), contains('connection'));
    });

    test('api key is redacted from detail and query', () {
      final info = describeAiError(
        Exception('ClientException: oops, uri=https://x.test/?key=SECRET123'),
      );
      expect(info.detail, isNot(contains('SECRET123')));
      expect(info.googleQuery, isNot(contains('SECRET123')));
    });
  });
}
