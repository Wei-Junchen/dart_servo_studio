import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RttCommandError implements Exception {
  RttCommandError(this.message);
  final String message;
  @override
  String toString() => '固件拒绝：$message';
}

/// Exactly one in-flight request. Never retries writes, including an ambiguous timeout.
class RttClient {
  RttClient({this.onLog, this.onDisconnect});
  final void Function(String)? onLog;
  final void Function(Object)? onDisconnect;
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Completer<String>? _pending;
  Timer? _timeout;
  int _id = 0;
  bool _waitFlash = false;
  bool get busy => _pending != null;
  bool get connected => _socket != null;
  String _line = '';
  int _telnet = 0;
  bool _closing = false;

  Future<void> connect(String host, int port, {int? address}) async {
    if (_socket != null) throw StateError('已经连接');
    if (port < 1 || port > 65535) throw const FormatException('端口范围为 1..65535');
    _closing = false;
    _socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 4),
    );
    // SEGGER expects the configuration within 100 ms of accepting a connection.
    final addr = address == null
        ? ''
        : ';SetRTTAddr;0x${address.toRadixString(16)}';
    _socket!.add(ascii.encode('\$\$SEGGER_TELNET_ConfigStr=RTTCh;1$addr\$\$'));
    _subscription = _socket!.listen(
      _receive,
      onError: _lost,
      onDone: () => _lost(const SocketException('RTT 服务断开')),
    );
    await _socket!.flush();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<String> command(String text, {bool flash = false}) {
    if (_socket == null) return Future.error(StateError('尚未连接 RTT'));
    if (_pending != null) return Future.error(StateError('另一个 RTT 请求仍在进行'));
    if (text.contains('\n') ||
        text.contains('\r') ||
        !ascii.encoder.convert(text).every((b) => b >= 32 && b <= 126)) {
      return Future.error(const FormatException('无效的命令'));
    }
    final frame = '@${++_id} $text\n';
    if (frame.length > 127) {
      return Future.error(const FormatException('命令超过固件行缓冲区'));
    }
    _waitFlash = flash;
    final pending = _pending = Completer<String>();
    _timeout = Timer(Duration(milliseconds: flash ? 10000 : 800), () {
      _lost(TimeoutException('命令应答超时；结果不确定，未自动重发：$text'));
    });
    if (!text.contains('keepalive') &&
        text != 'status' &&
        !text.endsWith(' info')) {
      onLog?.call('→ $text');
    }
    _socket!.add(ascii.encode(frame));
    return pending.future;
  }

  void _receive(List<int> bytes) {
    for (final b in bytes) {
      // Strip Telnet IAC negotiation/subnegotiation, including split TCP frames.
      if (_telnet == 1) {
        if (b >= 251 && b <= 254) {
          _telnet = 2;
        } else if (b == 250) {
          _telnet = 3;
        } else {
          _telnet = 0;
        }
        continue;
      }
      if (_telnet == 2) {
        _telnet = 0;
        continue;
      }
      if (_telnet == 3) {
        if (b == 255) _telnet = 4;
        continue;
      }
      if (_telnet == 4) {
        _telnet = b == 240 ? 0 : 3;
        continue;
      }
      if (b == 255) {
        _telnet = 1;
        continue;
      }
      if (b == 10) {
        _accept(_line);
        _line = '';
      } else if (b != 13 && b >= 32 && b < 127) {
        _line += String.fromCharCode(b);
        if (_line.length > 8192) _line = _line.substring(_line.length - 4096);
      }
    }
  }

  void _accept(String line) {
    final match = RegExp(r'\[DART\] (\d+) (OK|ERR|DONE) (.*)$')
        .firstMatch(line);
    if (match == null) {
      if (line.isNotEmpty) onLog?.call(line);
      return;
    }
    final id = int.parse(match[1]!);
    final kind = match[2]!;
    final payload = match[3]!;
    if (id != _id || _pending == null) return;
    if (_waitFlash && kind == 'OK' && payload == 'FLASH_PENDING') {
      onLog?.call('← Flash 写入中…');
      return;
    }
    if (_waitFlash &&
        (kind != 'DONE' || payload != 'FLASH status=OK') &&
        kind != 'ERR') {
      _lost(const FormatException('Flash 返回异常；不能认为已保存'));
      return;
    }
    final pending = _pending!;
    _pending = null;
    _timeout?.cancel();
    if (!payload.startsWith('STATUS ') &&
        !payload.startsWith('MANUAL ') &&
        !payload.startsWith('CONTROL ') &&
        !payload.startsWith('CAL_ICM ') &&
        !payload.startsWith('CAL_ADXL ') &&
        !payload.startsWith('CAL_SAVED ')) {
      onLog?.call('← $kind $payload');
    }
    if (kind == 'ERR') {
      pending.completeError(RttCommandError(payload));
    } else {
      pending.complete(payload);
    }
  }

  void _lost(Object error) {
    if (_closing) return;
    _closing = true;
    _timeout?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
    _socket?.destroy();
    _socket = null;
    onDisconnect?.call(error);
  }

  Future<void> close() async {
    _closing = true;
    _timeout?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('连接已关闭'));
    }
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _line = '';
    _telnet = 0;
  }
}
