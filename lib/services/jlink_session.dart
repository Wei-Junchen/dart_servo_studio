import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// Owns only the Commander child started here. Never kills existing debugger processes.
class JLinkSession {
  Process? _process;
  final List<StreamSubscription<String>> _readers = [];
  final StringBuffer _output = StringBuffer();
  void Function(String)? onLog;
  Future<int?> resolveAddress(ConnectionSettings settings) async {
    if (settings.rttAddress.trim().isNotEmpty) {
      final raw = settings.rttAddress.trim();
      final addr = int.tryParse(
        raw.replaceFirst(RegExp(r'^0[xX]'), ''),
        radix: 16,
      );
      if (addr == null || addr < 0x20000000 || addr >= 0x20020000) {
        throw const FormatException(
          'RTT 地址必须位于 STM32F411 SRAM：0x20000000..0x2001FFFF',
        );
      }
      return addr;
    }
    if (settings.elf.trim().isEmpty) return null;
    if (!await File(settings.elf).exists()) {
      throw FileSystemException('找不到 ELF；也可清空路径并填写 RTT 地址', settings.elf);
    }
    ProcessResult? result;
    for (final executable in ['arm-none-eabi-nm', 'nm', 'llvm-nm']) {
      try {
        final current = await Process.run(executable, [
          '-g',
          '--defined-only',
          settings.elf,
        ]);
        if (current.exitCode == 0) {
          result = current;
          break;
        }
      } on ProcessException {
        /* Try the next installed tool, never execute the ELF. */
      }
    }
    if (result == null) throw StateError('不能解析 ELF，请安装 nm 或手填 RTT 地址');
    final match = RegExp(
      r'^([0-9a-fA-F]+)\s+\w\s+_SEGGER_RTT\s*$',
      multiLine: true,
    ).firstMatch(result.stdout as String);
    if (match == null) {
      throw const FormatException('ELF 中没有 _SEGGER_RTT；请选板上固件对应的 ELF');
    }
    final address = int.parse(match[1]!, radix: 16);
    if (address < 0x20000000 || address >= 0x20020000) {
      throw const FormatException('ELF 的 RTT 符号不在 F411 SRAM 中');
    }
    return address;
  }

  Future<void> start(ConnectionSettings settings) async {
    if (_process != null) throw StateError('Commander 已经启动');
    if (settings.speed < 1 ||
        settings.speed > 50000 ||
        settings.port < 1 ||
        settings.port > 65535) {
      throw const FormatException('SWD speed 范围 1..50000 kHz，端口范围 1..65535');
    }
    if (!['localhost', '127.0.0.1', '::1'].contains(settings.host)) {
      throw const FormatException('自动启动仅支持本机；远程连接请关闭“启动 Commander”');
    }
    try {
      final existing = await Socket.connect(
        settings.host,
        settings.port,
        timeout: const Duration(milliseconds: 350),
      );
      existing.destroy();
      throw StateError('端口 ${settings.port} 已有服务，请关闭“启动 Commander”连接已有服务');
    } on SocketException {
      /* Refused is expected before starting our own child. */
    }
    final args = [
      '-device',
      settings.device,
      '-if',
      'SWD',
      '-speed',
      '${settings.speed}',
      '-autoconnect',
      '1',
      '-RTTTelnetPort',
      '${settings.port}',
      '-NoGui',
      '1',
      '-ExitOnError',
      '1',
      if (settings.serial.isNotEmpty) ...['-USB', settings.serial],
    ];
    onLog?.call('启动 ${settings.commander} ${args.join(' ')}');
    final ready = Completer<void>();
    final process = _process = await Process.start(settings.commander, args);
    // Keep stdin open for the GUI lifetime; no g / halt / reset / download commands.
    for (final stream in [process.stdout, process.stderr]) {
      _readers.add(
        stream.transform(const Utf8Decoder(allowMalformed: true)).listen((
          text,
        ) {
          if (_output.length < 32768) _output.write(text);
          onLog?.call(text.trim());
          if (text.contains('Cortex-M4 identified') ||
              _output.toString().contains('Cortex-M4 identified')) {
            if (!ready.isCompleted) ready.complete();
          }
        }),
      );
    }
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Commander 退出 ($code)\n$_output'));
        }
      }),
    );
    try {
      await ready.future.timeout(const Duration(seconds: 18));
    } catch (error) {
      await stop();
      rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.stdin.writeln('exit');
        await process.stdin.flush();
        await process.stdin.close();
      } catch (_) {
        /* Child may already be gone. */
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
      }
    }
    for (final reader in _readers) {
      await reader.cancel();
    }
    _readers.clear();
    _output.clear();
  }
}
