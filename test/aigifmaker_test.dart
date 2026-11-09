import 'dart:convert';

import 'package:aigifmaker/aigifmaker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// Mocked unit tests in the real response shapes (every response is HTTP 200;
// the JSON code decides).
const gifUrl = 'https://cdn.aigifmaker.ai/out/a.gif';

Map<String, dynamic> ok(Map<String, dynamic> data) =>
    {'code': 0, 'message': 'ok', 'data': data};
Map<String, dynamic> err(String msg, [int code = -1]) =>
    {'code': code, 'message': msg};

class Call {
  final String path;
  final Object? body;
  final Map<String, String> headers;
  Call(this.path, this.body, this.headers);
}

/// submit -> each poll answers the next element of [polls] (the last repeats).
Aigifmaker fake(List<Call> calls, List<Map<String, dynamic>> polls,
    {String apiKey = 'sk-test',
    Duration timeout = const Duration(minutes: 5)}) {
  var i = 0;
  return Aigifmaker(
      apiKey: apiKey,
      timeout: timeout,
      pollEvery: Duration.zero,
      client: MockClient((r) async {
        calls.add(Call(r.url.toString(), jsonDecode(r.body), r.headers));
        Map<String, dynamic> reply;
        switch (r.url.path) {
          case '/api/ai/generate':
            reply = ok({'id': 't1', 'status': 'pending', 'taskId': 'up-1'});
          case '/api/user/get-user-credits':
            reply = ok({'remainingCredits': 7, 'made': 2});
          default:
            reply = polls[i < polls.length ? i : polls.length - 1];
            i++;
        }
        return http.Response.bytes(utf8.encode(jsonEncode(reply)), 200);
      }));
}

Aigifmaker answering(Map<String, dynamic> reply,
        {String apiKey = 'sk-test', List<Call>? calls}) =>
    Aigifmaker(
        apiKey: apiKey,
        pollEvery: Duration.zero,
        client: MockClient((r) async {
          calls?.add(Call(r.url.toString(), jsonDecode(r.body), r.headers));
          return http.Response.bytes(utf8.encode(jsonEncode(reply)), 200);
        }));

void main() {
  test('success: fixed body, bearer key, GIF URL', () async {
    final calls = <Call>[];
    final c = fake(calls, [
      ok({'id': 't1', 'status': 'processing'}),
      ok({
        'id': 't1',
        'status': 'success',
        'images': [gifUrl],
        'watermarked': [false]
      }),
    ]);
    expect(await c.generate('a dancing cat'), gifUrl);
    expect(calls[0].path, 'https://aigifmaker.ai/api/ai/generate');
    expect(calls[0].body, {
      'provider': 'openlux',
      'mediaType': 'image',
      'model': 'gif-maker-v1',
      'scene': 'text-to-image',
      'prompt': 'a dancing cat',
      'options': {'output_format': 'gif'},
    });
    expect(calls[0].headers['Authorization'], 'Bearer sk-test');
    expect(calls[1].path, 'https://aigifmaker.ai/api/ai/query');
    expect(calls[1].body, {'taskId': 't1'});
    expect(await c.credits(), 7);
  });

  test('queued: keeps polling', () async {
    final calls = <Call>[];
    final q = ok(
        {'id': 't1', 'status': 'processing', 'queued': true, 'queueEta': 30});
    final c = fake(calls, [
      q,
      q,
      ok({
        'id': 't1',
        'status': 'success',
        'images': [gifUrl],
        'watermarked': [true]
      }),
    ]);
    expect(await c.generate('x'), gifUrl);
    expect(calls.length, 4);
    expect((await fake([], [q]).status('t1')).queued, isTrue);
  });

  test('failed run', () async {
    final c = fake([], [
      ok({'id': 't1', 'status': 'failed', 'errorMessage': 'upstream error'})
    ]);
    await expectLater(
        c.generate('x'),
        throwsA(isA<GenerationFailed>()
            .having((e) => e.message, 'message', 'upstream error')));
  });

  test('moderation failure is RejectedError', () async {
    final c = fake([], [
      ok({
        'id': 't1',
        'status': 'failed',
        'errorMessage': 'blocked',
        'failureKind': 'moderation'
      })
    ]);
    await expectLater(c.generate('x'), throwsA(isA<RejectedError>()));
  });

  test('invalid key', () async {
    final c = answering(err(
        'invalid API key — create one at https://aigifmaker.ai/settings/apikeys'));
    await expectLater(c.credits(), throwsA(isA<AuthError>()));
  });

  test('wall without key', () async {
    final calls = <Call>[];
    final c = answering(ok({'wall': true, 'reason': 'anon_credits'}),
        apiKey: '', calls: calls);
    await expectLater(
        c.submit('x'),
        throwsA(isA<AuthError>().having(
            (e) => e.message, 'message', contains('settings/apikeys'))));
    if (c.apiKey.isEmpty) {
      expect(calls.single.headers.containsKey('Authorization'), isFalse);
    }
  });

  test('insufficient credits', () async {
    final c = answering(err('insufficient credits'));
    await expectLater(
        c.submit('x'),
        throwsA(isA<QuotaError>().having(
            (e) => e.message, 'message', contains('aigifmaker.ai/pricing'))));
  });

  test('cooldown and generic refusals', () async {
    await expectLater(answering(err('slow down', 429)).submit('x'),
        throwsA(isA<RejectedError>()));
    await expectLater(
        answering(err('something else')).submit('x'),
        throwsA(predicate(
            (e) => e.runtimeType == AigifmakerException, 'base class')));
  });

  test('timeout', () async {
    final c = fake([], [
      ok({'id': 't1', 'status': 'processing'})
    ], timeout: Duration.zero);
    await expectLater(c.generate('x'), throwsA(isA<TimeoutError>()));
  });

  test('empty prompt', () async {
    await expectLater(fake([], []).submit('  '), throwsArgumentError);
  });
}
