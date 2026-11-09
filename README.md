# aigifmaker

Turn text into animated GIFs with AI GIF Maker. Native GIF generation — no video conversion. Type what you want and download your GIF in about a minute.

This is the official Dart client for [AI GIF Maker](https://aigifmaker.ai/?utm_source=pub&utm_medium=package). One call sends your prompt, waits for the GIF and returns its URL. Works in Dart and Flutter apps.

```bash
dart pub add aigifmaker
```

```dart
import 'package:aigifmaker/aigifmaker.dart';

Future<void> main() async {
  final gif = Aigifmaker(); // reads AIGIFMAKER_API_KEY
  print(await gif.generate('a corgi in sunglasses dancing on a beach, looping'));
  gif.close();
}
```

The only dependency is `package:http`.

## API key

Create a key at https://aigifmaker.ai/settings/apikeys, then pass it as `apiKey:` or export it:

```bash
export AIGIFMAKER_API_KEY=sk-...
```

Each GIF costs 1 credit on your AI GIF Maker account, the same as on the website. New accounts get one free GIF (it carries a small aigifmaker.ai badge). A GIF that fails to generate gives its credit back. Credit packs are on the [pricing](https://aigifmaker.ai/pricing?utm_source=pub&utm_medium=package) page.

```dart
print(await gif.credits()); // remaining credits, free to call
```

## Options

```dart
final gif = Aigifmaker(apiKey: 'sk-...', timeout: const Duration(minutes: 15)); // 15 minutes by default
```

## Submit now, collect later

```dart
final taskId = await gif.submit('happy birthday text bouncing in rainbow letters');
final st = await gif.status(taskId); // st.status: pending | processing | success | failed
final url = await gif.wait(taskId);  // polls every 3 seconds
```

A run from an account that has not bought credits yet may wait in a short queue first (`st.queued` is true while `status` stays `processing`). That is normal; `generate()` and `wait()` keep polling.

## Errors worth catching

Each failure is its own subclass of `AigifmakerException`:

- `AuthError`: no key, or the key is wrong or deleted
- `QuotaError`: the account is out of credits
- `RejectedError`: the content filter refused the prompt, or a cooldown is active; reword it
- `GenerationFailed`: the run was accepted but failed; the message says why
- `TimeoutError`: still running when the timeout passed; the GIF may finish later in your history
- `NetworkError`: the request never got an answer; safe to retry

Any other refusal throws `AigifmakerException` with the server's message.

## Tests

```bash
dart test --exclude-tags live   # mocked, offline
dart test --tags live           # two free live checks, no generation
```

MIT licensed. Questions: support@aigifmaker.ai
