import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class QuickTunnel {
  QuickTunnel({this.onUnexpectedExit});
  final void Function()? onUnexpectedExit;
  Process? _process;
  bool _stopped = false;
  Future<String> start(int port) async {
    final executable = File(
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}cloudflared.exe',
    );
    if (!await executable.exists()) {
      throw const FormatException(
        'Thiếu cloudflared.exe. Dùng bản ZIP đầy đủ hoặc cấu hình địa chỉ HTTPS cố định.',
      );
    }
    final ready = Completer<String>();
    final process = await Process.start(executable.path, [
      'tunnel',
      '--no-autoupdate',
      '--url',
      'http://127.0.0.1:$port',
      '--protocol',
      'http2',
    ]);
    _process = process;
    if (_stopped) {
      process.kill();
      throw const FormatException('Đã dừng kết nối.');
    }
    try {
      // Native job object closes this child even if the Flutter window is closed abruptly.
      await const MethodChannel('fap_helper/process')
          .invokeMethod<void>('trackChild', process.pid);
      void log(String line) {
        final url = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com')
            .firstMatch(line)
            ?.group(0);
        if (url != null && !ready.isCompleted) ready.complete(url);
      }

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log);
      unawaited(
        process.exitCode.then((_) {
          if (!ready.isCompleted) {
            ready.completeError(
              const FormatException(
                'Không tạo được kết nối Internet. Kiểm tra mạng hoặc dùng địa chỉ HTTPS cố định.',
              ),
            );
          }
          if (!_stopped) onUnexpectedExit?.call();
        }),
      );
      return await ready.future.timeout(
        const Duration(seconds: 40),
        onTimeout: () => throw const FormatException(
          'Kết nối Internet chưa sẵn sàng. Hãy thử lại.',
        ),
      );
    } catch (_) {
      process.kill();
      rethrow;
    }
  }

  bool get stopped => _stopped;
  void stop() {
    _stopped = true;
    _process?.kill();
  }
}
