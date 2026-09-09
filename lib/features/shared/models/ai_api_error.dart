import '../models/ai_provider.dart';

class AiApiErrorInfo {
  final int? statusCode;
  final String title;
  final String advice;
  final String detail;
  final bool isKnown;
  final String googleQuery;

  const AiApiErrorInfo({
    this.statusCode,
    required this.title,
    required this.advice,
    this.detail = '',
    required this.isKnown,
    required this.googleQuery,
  });

  Uri get googleUrl => Uri.parse(
    'https://www.google.com/search?q=${Uri.encodeComponent(googleQuery)}',
  );

  String get displayMessage =>
      detail.isEmpty ? '$title\n$advice' : '$title\n$advice\n\n$detail';
}

AiApiErrorInfo describeAiError(Object error, {AiProvider? provider}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  final codeMatch = RegExp(r'API error (\d+)').firstMatch(raw);
  final code = codeMatch != null
      ? int.tryParse(codeMatch.group(1)!)
      : _codeFromText(lower);
  final detail = _stripPrefix(raw);
  final tag = provider == null ? '' : ' ${provider.displayName}';
  String q(String s) => '${provider?.displayName ?? 'Gemini OpenAI'} $s $detail'
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  if (_isAuthError(lower)) {
    return AiApiErrorInfo(
      statusCode: code ?? 401,
      title: 'Invalid API key${code != null ? ' ($code)' : ''}',
      advice:
          'Your API key was rejected$tag. Open Settings, paste a fresh key, and check for extra spaces.',
      detail: detail,
      isKnown: true,
      googleQuery: q('401 invalid API key'),
    );
  }
  if (_isBillingError(lower)) {
    return AiApiErrorInfo(
      statusCode: code,
      title: 'Quota or billing limit${code != null ? ' ($code)' : ''}',
      advice:
          'Your plan ran out of credit$tag. Check billing/quota, top up, or switch to a free model.',
      detail: detail,
      isKnown: true,
      googleQuery: q('insufficient quota billing limit'),
    );
  }
  if (_isContextError(lower)) {
    return AiApiErrorInfo(
      statusCode: code,
      title: 'Request too large${code != null ? ' ($code)' : ''}',
      advice:
          'The prompt exceeds the model context. Shorten the question, start a new chat, or pick a larger-context model.',
      detail: detail,
      isKnown: true,
      googleQuery: q('context length exceeded maximum context'),
    );
  }
  if (_isSafetyError(lower)) {
    return AiApiErrorInfo(
      statusCode: code,
      title: 'Blocked by safety filter',
      advice: 'The model refused to answer. Rephrase neutrally and try again.',
      detail: detail,
      isKnown: true,
      googleQuery: q('response blocked safety filter finishReason SAFETY'),
    );
  }

  switch (code) {
    case 400:
      return AiApiErrorInfo(
        statusCode: 400,
        title: 'Bad request (400)',
        advice:
            'The request was rejected$tag. Check the model name, endpoint URL, and try a shorter prompt.',
        detail: detail,
        isKnown: true,
        googleQuery: q('400 bad request invalid argument'),
      );
    case 401:
    case 403:
      return AiApiErrorInfo(
        statusCode: code,
        title: 'Access denied ($code)',
        advice:
            'Your API key lacks permission$tag. Verify the key, project billing, and region support in Settings.',
        detail: detail,
        isKnown: true,
        googleQuery: q('$code permission denied API key'),
      );
    case 404:
      return AiApiErrorInfo(
        statusCode: 404,
        title: 'Model not found (404)',
        advice:
            'The model was renamed or retired$tag. Open Settings and pick an available model from the list.',
        detail: detail,
        isKnown: true,
        googleQuery: q('404 model not found'),
      );
    case 408:
    case 504:
      return AiApiErrorInfo(
        statusCode: code,
        title: 'Request timed out ($code)',
        advice:
            'The server took too long. Try again, shorten the prompt, or use a faster model.',
        detail: detail,
        isKnown: true,
        googleQuery: q('$code deadline exceeded timeout'),
      );
    case 409:
      return AiApiErrorInfo(
        statusCode: 409,
        title: 'Conflict (409)',
        advice: 'The request conflicted. Wait a moment and retry.',
        detail: detail,
        isKnown: true,
        googleQuery: q('409 conflict API error'),
      );
    case 413:
    case 422:
      return AiApiErrorInfo(
        statusCode: code,
        title: 'Payload too large ($code)',
        advice:
            'The input is too big. Shorten the text, split the job, or pick a larger-context model.',
        detail: detail,
        isKnown: true,
        googleQuery: q('$code payload too large context length'),
      );
    case 429:
      return AiApiErrorInfo(
        statusCode: 429,
        title: 'Rate limit hit (429)',
        advice:
            'Too many requests$tag. Wait a minute and retry. Free keys are heavily throttled — retry later or add another key.',
        detail: detail,
        isKnown: true,
        googleQuery: q('429 resource exhausted rate limit'),
      );
    case 500:
    case 502:
      return AiApiErrorInfo(
        statusCode: code,
        title: 'Server error ($code)',
        advice: 'The AI service failed internally. Wait a moment and retry.',
        detail: detail,
        isKnown: true,
        googleQuery: q('$code internal server error Gemini OpenAI'),
      );
    case 503:
      return AiApiErrorInfo(
        statusCode: 503,
        title: 'Server overloaded (503)',
        advice:
            'The AI servers are under heavy load. Wait 1–2 minutes and try again — this usually clears by itself.',
        detail: detail,
        isKnown: true,
        googleQuery: q('503 service unavailable overloaded model'),
      );
    case 529:
      return AiApiErrorInfo(
        statusCode: 529,
        title: 'Server overloaded (529)',
        advice: 'The provider is overloaded. Wait a minute and retry.',
        detail: detail,
        isKnown: true,
        googleQuery: q('529 overloaded API error'),
      );
  }

  if (_isNetworkError(lower)) {
    return AiApiErrorInfo(
      statusCode: code,
      title: 'No connection',
      advice: 'Could not reach the AI service. Check internet and retry.',
      detail: detail,
      isKnown: true,
      googleQuery: q('failed host lookup socket exception'),
    );
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return AiApiErrorInfo(
      statusCode: code,
      title: 'Request timed out',
      advice: 'The AI service took too long. Try again with a shorter prompt.',
      detail: detail,
      isKnown: true,
      googleQuery: q('API request timed out'),
    );
  }

  final short = detail.length > 220 ? '${detail.substring(0, 220)}…' : detail;
  return AiApiErrorInfo(
    statusCode: code,
    title: code != null ? 'AI error ($code)' : 'Unexpected AI error',
    advice:
        'This error is not in the known list. The full message is shown below — tap Search Google for help.',
    detail: short.isEmpty ? raw : short,
    isKnown: false,
    googleQuery: q(short.isEmpty ? raw : short),
  );
}

int? _codeFromText(String lower) {
  for (final c in [
    400,
    401,
    403,
    404,
    408,
    409,
    413,
    422,
    429,
    500,
    502,
    503,
    504,
    529,
  ]) {
    if (lower.contains(' $c ') ||
        lower.contains('($c)') ||
        lower.contains(':$c') ||
        lower.contains('error $c')) {
      return c;
    }
  }
  return null;
}

String _stripPrefix(String raw) {
  var s = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  s = s.replaceFirst(RegExp(r'^API error \d+:\s*'), '').trim();
  s = s.replaceAll(RegExp(r'key=[^&\s]+'), 'key=***');
  return s;
}

bool _isAuthError(String l) =>
    l.contains('invalid api key') ||
    l.contains('incorrect api key') ||
    l.contains('api key not valid') ||
    l.contains('unauthenticated') ||
    l.contains('account deactivated') ||
    l.contains('permission_denied') && l.contains('key');

bool _isBillingError(String l) =>
    l.contains('insufficient_quota') ||
    l.contains('insufficient quota') ||
    l.contains('billing') ||
    l.contains('credit balance') ||
    l.contains('plan and billing');

bool _isContextError(String l) =>
    l.contains('context_length_exceeded') ||
    l.contains('context length') ||
    l.contains('maximum context') ||
    l.contains('max_tokens') && l.contains('context') ||
    l.contains('token limit') ||
    l.contains('too many tokens') ||
    l.contains('prompt is too long');

bool _isSafetyError(String l) =>
    l.contains('safety') ||
    l.contains('blocked') && l.contains('finish') ||
    l.contains('finish_reason') ||
    l.contains('content filter') ||
    l.contains('content_filter') ||
    l.contains('recitation');

bool _isNetworkError(String l) =>
    l.contains('socketexception') ||
    l.contains('connection refused') ||
    l.contains('connection reset') ||
    l.contains('connection closed') ||
    l.contains('before full header') ||
    l.contains('failed host lookup') ||
    l.contains('unable to connect') ||
    l.contains('network is unreachable') ||
    l.contains('handshake') ||
    l.contains('certificate');
