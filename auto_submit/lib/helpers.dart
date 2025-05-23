// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:cocoon_server/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

/// Serves [handler] on [InternetAddress.anyIPv4] using the port returned by
/// [listenPort].
///
/// The returned [Future] will complete using [terminateRequestFuture] after
/// closing the server.
Future<void> serveHandler(Handler handler) async {
  final port = listenPort();

  final server = await serve(
    LoggingHandler(handler).handle,
    InternetAddress.anyIPv4, // Allows external connections
    port,
  );
  log.info('Serving at http://${server.address.host}:${server.port}');

  await terminateRequestFuture();

  await server.close();
}

/// Wraps another [Handler], catching and logging uncaught exceptions from it.
class LoggingHandler {
  const LoggingHandler(this._delegate);

  final Handler _delegate;

  /// Handles a request.
  ///
  /// Tear off this method and pass it to [serve].
  FutureOr<Response> handle(Request request) async {
    try {
      return await _delegate(request);
    } catch (e, s) {
      log.error('Uncaught exception in HTTP handler', e, s);
      rethrow;
    }
  }
}

/// Returns the port to listen on from environment variable or uses the default
/// `8080`.
///
/// See https://cloud.google.com/run/docs/reference/container-contract#port
int listenPort() => int.parse(Platform.environment['PORT'] ?? '8080');

/// Returns a [Future] that completes when the process receives a
/// [ProcessSignal] requesting a shutdown.
///
/// [ProcessSignal.sigint] is listened to on all platforms.
///
/// [ProcessSignal.sigterm] is listened to on all platforms except Windows.
Future<void> terminateRequestFuture() {
  final completer = Completer<bool>.sync();

  // sigIntSub is copied below to avoid a race condition - ignoring this lint
  // ignore: cancel_subscriptions
  StreamSubscription? sigIntSub, sigTermSub;

  Future<void> signalHandler(ProcessSignal signal) async {
    log.info('Received signal $signal - closing');

    final subCopy = sigIntSub;
    if (subCopy != null) {
      sigIntSub = null;
      await subCopy.cancel();
      sigIntSub = null;
      if (sigTermSub != null) {
        await sigTermSub!.cancel();
        sigTermSub = null;
      }
      completer.complete(true);
    }
  }

  sigIntSub = ProcessSignal.sigint.watch().listen(signalHandler);

  // SIGTERM is not supported on Windows. Attempting to register a SIGTERM
  // handler raises an exception.
  if (!Platform.isWindows) {
    sigTermSub = ProcessSignal.sigterm.watch().listen(signalHandler);
  }

  return completer.future;
}
