import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_servo_studio/services/rtt_client.dart';
import 'package:dart_servo_studio/services/jlink_session.dart';
import 'package:dart_servo_studio/models.dart';

import 'fake_target.dart';

void main() {
  test(
    'SEGGER channel config precedes RPC; split frames, Telnet and stale IDs',
    () async {
      final peer = FakeTarget()..fragment = true;
      await peer.start();
      final client = RttClient();
      try {
        await client.connect('127.0.0.1', peer.port, address: 0x20004404);
        expect(await client.command('ping'), 'PONG protocol=v4');
        expect(
          peer.configurations.single,
          '\$\$SEGGER_TELNET_ConfigStr=RTTCh;1;SetRTTAddr;0x20004404\$\$',
        );
        expect(peer.commands, ['ping']);
      } finally {
        await client.close();
        await peer.close();
      }
    },
  );
  test('Flash waits for DONE, errors do not poison connection', () async {
    final peer = FakeTarget();
    await peer.start();
    final client = RttClient();
    try {
      await client.connect('127.0.0.1', peer.port);
      await expectLater(
        client.command('unknown'),
        throwsA(isA<RttCommandError>()),
      );
      expect(
        await client.command('servo save', flash: true),
        'FLASH status=OK',
      );
      expect(await client.command('ping'), 'PONG protocol=v4');
    } finally {
      await client.close();
      await peer.close();
    }
  });
  test('ambiguous write timeout closes connection and never resends', () async {
    final peer = FakeTarget()..silent = true;
    await peer.start();
    final client = RttClient();
    try {
      await client.connect('127.0.0.1', peer.port);
      await expectLater(
        client.command('servo setall 1 2 3 4'),
        throwsA(isA<TimeoutException>()),
      );
      expect(peer.commands, ['servo setall 1 2 3 4']);
      expect(client.connected, false);
    } finally {
      await client.close();
      await peer.close();
    }
  });
  test('address override validation and missing ELF fail locally', () async {
    final session = JLinkSession(), settings = ConnectionSettings();
    settings.elf = '/missing/firmware.elf';
    settings.rttAddress = '0x20004404';
    expect(await session.resolveAddress(settings), 0x20004404);
    settings.rttAddress = '0x08000000';
    await expectLater(session.resolveAddress(settings), throwsFormatException);
    settings.rttAddress = '';
    await expectLater(
      session.resolveAddress(settings),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('owned Commander lifetime and cleanup with fake child, no USB', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('servo-commander-test-');
    final child = File('${dir.path}/commander');
    final sentinel = File('${dir.path}/exited');
    await child.writeAsString(
      '#!/bin/sh\necho "Cortex-M4 identified."\nwhile read line; do\n if [ "\$line" = exit ]; then touch "${sentinel.path}"; exit 0; fi\ndone\n',
    );
    await Process.run('chmod', ['+x', child.path]);
    final unused = await ServerSocket.bind('127.0.0.1', 0);
    final port = unused.port;
    await unused.close();
    final settings = ConnectionSettings()
      ..commander = child.path
      ..port = port;
    final session = JLinkSession();
    try {
      await session.start(settings);
      expect(await sentinel.exists(), false);
      await session.stop();
      expect(await sentinel.exists(), true);
    } finally {
      await session.stop();
      await dir.delete(recursive: true);
    }
  });
  test('does not start another Commander on an occupied port', () async {
    final peer = FakeTarget();
    await peer.start();
    final session = JLinkSession();
    final settings = ConnectionSettings()
      ..port = peer.port
      ..commander = '/must-not-run';
    try {
      await expectLater(session.start(settings), throwsStateError);
    } finally {
      await session.stop();
      await peer.close();
    }
  });
}
