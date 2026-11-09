/// Official Dart SDK for AI GIF Maker (https://aigifmaker.ai): turn text into
/// animated GIFs.
///
/// ```dart
/// final gif = Aigifmaker(); // reads AIGIFMAKER_API_KEY
/// final url = await gif.generate('a corgi in sunglasses dancing on a beach');
/// ```
///
/// Create a key at https://aigifmaker.ai/settings/apikeys. Each GIF costs
/// 1 credit on your AI GIF Maker account, the same as on the website.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// The service this package talks to.
const baseUrl = 'https://aigifmaker.ai';

/// Where an API key is created.
const keysUrl = 'https://aigifmaker.ai/settings/apikeys';

/// Where credits are bought.
const pricingUrl = 'https://aigifmaker.ai/pricing';

/// Base of every error this package throws. Catch a subclass to decide what
/// to do next; any other refusal is this class itself, with the server's
/// message.
class AigifmakerException implements Exception {
  final String message;

  /// The JSON `code` of the response, when there was one.
  final int? code;

  const AigifmakerException(this.message, {this.code});

  @override
  String toString() => '$runtimeType: $message';
}

/// No API key, or the key is invalid or deleted.
class AuthError extends AigifmakerException {
  const AuthError(super.message, {super.code});
}

/// The account is out of credits.
class QuotaError extends AigifmakerException {
  const QuotaError(super.message, {super.code});
}

/// The content filter refused the prompt, or a cooldown is active. Reword it.
class RejectedError extends AigifmakerException {
  const RejectedError(super.message, {super.code});
}

/// The GIF was accepted but the run ended as failed or canceled.
class GenerationFailed extends AigifmakerException {
  const GenerationFailed(super.message, {super.code});
}

/// The deadline passed; the GIF may still finish in your AI GIF Maker history.
class TimeoutError extends AigifmakerException {
  const TimeoutError(super.message, {super.code});
}

/// The request never got an answer (DNS, TLS, connection reset). Safe to retry.
class NetworkError extends AigifmakerException {
  const NetworkError(super.message, {super.code});
}

/// Return `data` for `code: 0`; otherwise throw the error that says what to do
/// next. Every response is HTTP 200; the JSON `code` tells success from refusal.
Map<String, dynamic> unwrap(int httpStatus, Object? env) {
  final m = env is Map ? env : const {};
  final code = m['code'];
  final data = m['data'] is Map
      ? Map<String, dynamic>.from(m['data'] as Map)
      : <String, dynamic>{};
  if (code == 0) {
    if (data['wall'] == true) {
      throw AuthError(
          'an API key is required; create one at $keysUrl and set AIGIFMAKER_API_KEY',
          code: 0);
    }
    return data;
  }
  final msg = '${m['message'] ?? m['error'] ?? 'HTTP $httpStatus'}';
  final low = msg.toLowerCase();
  final c = code is int ? code : null;
  if (low.contains('invalid api key') ||
      low.contains('no auth') ||
      httpStatus == 401) {
    throw AuthError(msg, code: c);
  }
  if (low.contains('insufficient credits')) {
    throw QuotaError('$msg. Top up at $pricingUrl', code: c);
  }
  if (c != null && c != -1) throw RejectedError(msg, code: c);
  throw AigifmakerException(msg, code: c);
}

/// One task as `/api/ai/query` reports it.
class GifStatus {
  /// Task id.
  final String id;

  /// 'pending', 'processing', 'success' or 'failed'.
  final String status;

  /// The finished GIF once [status] is 'success'.
  final String? url;

  /// True while a run from an account without purchased credits waits its turn.
  final bool queued;

  /// The failure reason when [status] is 'failed'.
  final String? errorMessage;

  /// The whole `data` object as the API sent it.
  final Map<String, dynamic> raw;

  GifStatus(this.raw)
      : id = '${raw['id'] ?? ''}',
        status = '${raw['status'] ?? ''}'.toLowerCase(),
        url = raw['images'] is List && (raw['images'] as List).isNotEmpty
            ? '${(raw['images'] as List).first}'
            : null,
        queued = raw['queued'] == true,
        errorMessage = raw['errorMessage'] as String?;
}

/// A client bound to one API key.
class Aigifmaker {
  /// The key sent as `Authorization: Bearer`; empty sends none.
  final String apiKey;
  final String base;
  final http.Client _client;

  /// How long [generate] and [wait] keep polling (5 minutes by default).
  Duration timeout;

  /// Time between status checks.
  Duration pollEvery;

  /// A missing or empty [apiKey] reads `AIGIFMAKER_API_KEY`.
  Aigifmaker(
      {String? apiKey,
      String? baseUrl,
      this.timeout = const Duration(minutes: 5),
      this.pollEvery = const Duration(seconds: 3),
      http.Client? client})
      : apiKey = (apiKey == null || apiKey.trim().isEmpty)
            ? _envKey()
            : apiKey.trim(),
        base = (baseUrl ?? _defaultBase).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  static const _defaultBase = baseUrl;

  static String _envKey() {
    try {
      return (Platform.environment['AIGIFMAKER_API_KEY'] ?? '').trim();
    } catch (_) {
      return ''; // web: no environment
    }
  }

  /// Generate one animated GIF and return its URL.
  Future<String> generate(String prompt) async => wait(await submit(prompt));

  /// Start one GIF and return its task id without waiting.
  Future<String> submit(String prompt) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'prompt is required');
    }
    final data = await _post('/api/ai/generate', {
      'provider': 'openlux',
      'mediaType': 'image',
      'model': 'gif-maker-v1',
      'scene': 'text-to-image',
      'prompt': prompt,
      'options': {'output_format': 'gif'},
    });
    final id = data['id'];
    if (id == null || '$id'.isEmpty) {
      throw const AigifmakerException('the service returned no task id');
    }
    return '$id';
  }

  /// Look up a task.
  Future<GifStatus> status(String taskId) async =>
      GifStatus(await _post('/api/ai/query', {'taskId': taskId}));

  /// Poll a task every 3 seconds until it finishes and return the GIF URL.
  Future<String> wait(String taskId, {Duration? timeout}) async {
    final limit = timeout ?? this.timeout;
    final deadline = DateTime.now().add(limit);
    while (true) {
      GifStatus? st;
      try {
        st = await status(taskId);
      } on NetworkError {
        st = null; // a dropped poll is not a failed generation
      }
      if (st != null) {
        if (st.status == 'success' && st.url != null) return st.url!;
        if (st.status == 'failed' || st.status == 'canceled') {
          final msg = st.errorMessage ?? 'the GIF ${st.status}';
          if (st.raw['failureKind'] == 'moderation') throw RejectedError(msg);
          throw GenerationFailed(msg);
        }
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw TimeoutError(
            'still running after ${limit.inSeconds}s; task $taskId may finish later in your AI GIF Maker history');
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  /// Remaining credits on the account. Free to call.
  Future<int> credits() async {
    final data = await _post('/api/user/get-user-credits', const {});
    final left = data['remainingCredits'];
    return left is num ? left.toInt() : 0;
  }

  /// Close the underlying HTTP client.
  void close() => _client.close();

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final http.Response res;
    try {
      res = await _client.post(Uri.parse('$base$path'),
          headers: {
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'User-Agent': 'aigifmaker-dart/0.1.0',
          },
          body: jsonEncode(body));
    } catch (e) {
      throw NetworkError(e.toString());
    }
    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      parsed = {'code': -1, 'message': 'HTTP ${res.statusCode}'};
    }
    return unwrap(res.statusCode, parsed);
  }
}
