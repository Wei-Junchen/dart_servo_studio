import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sandbox RTT peer; never opens a J-Link or talks to the physical target.
class FakeTarget {
  FakeTarget({this.protocol = 4});
  final int protocol;
  ServerSocket? server;
  final List<Socket> sockets = [];
  final List<String> commands = [];
  final List<String> configurations = [];
  bool manual = false, control = false;
  bool supportsCalSaved = true;
  List<double> offsets = [-28, -5, -18, -28], angles = [0, 0, 0, 0];
  List<int> mapping = [3, 1, 2, 4];
  List<double>? savedOffsets;
  List<int>? savedMapping;
  int icmStatus = 0, adxlStatus = 0, icmMask = 0, calibrationFlashSaves = 0;
  List<int> icmLiveRaw = [0, 2048, 0];
  int icmOneGLsb = 2048, icmLiveSamples = 100;
  bool savedIcm = false, savedAdxl = false;
  int savedIcmRange = 16;
  List<double> savedIcmFaces = [2200, -2000, 2100, -1900, 2300, -2100];
  List<double> savedAdxlOffset = [1, 2, 3];
  List<double> appliedAdxlOffset = [0, 0, 0];
  bool silent = false, fragment = false;
  bool idle = true, rejectOffsets = false;
  Duration offsetAckDelay = Duration.zero;
  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((socket) {
      sockets.add(socket);
      String input = '';
      bool configured = false;
      socket.listen((bytes) {
        input += ascii.decode(bytes);
        if (!configured) {
          final end = input.indexOf('\$\$', 2);
          if (end < 0) return;
          configurations.add(input.substring(0, end + 2));
          input = input.substring(end + 2);
          configured = true;
        }
        while (input.contains('\n')) {
          final end = input.indexOf('\n');
          final line = input.substring(0, end);
          input = input.substring(end + 1);
          final match = RegExp(r'^@(\d+) (.*)$').firstMatch(line);
          if (match == null) continue;
          final id = match[1]!, command = match[2]!;
          commands.add(command);
          if (silent) continue;
          String response;
          if (command == 'ping') {
            response =
                'OK PONG protocol=${protocol >= 4 ? 'v$protocol' : protocol}';
          } else if (command == 'status') {
            response =
                'OK STATUS state=${idle ? 0 : 1} idle=${idle ? 1 : 0} profile=9 flash_busy=0 save_pending=0 manual=${manual ? 1 : 0} control=${control ? 1 : 0} lease_ms=1500';
          } else if (command == 'servo control acquire') {
            control = idle;
            response = control
                ? 'OK CONTROL active=1 lease_ms=1500'
                : 'ERR CONTROL_COMMAND_OR_BUSY';
          } else if (command == 'servo control keepalive') {
            response = control
                ? 'OK CONTROL active=1 lease_ms=1500'
                : 'ERR CONTROL_COMMAND_OR_BUSY';
          } else if (command == 'servo control release') {
            control = false;
            response = 'OK CONTROL active=0 lease_ms=1500';
          } else if (command == 'servo get') {
            response = 'OK SERVO offset_deg=${offsets.join(',')} profile=9';
          } else if (command == 'servo saved') {
            response = savedOffsets == null
                ? 'ERR NO_SAVED_SERVO'
                : 'OK SERVO_SAVED offset_deg=${savedOffsets!.join(',')} profile=9';
          } else if (command == 'servo map saved') {
            response = savedMapping == null
                ? 'ERR NO_SAVED_MAPPING'
                : 'OK SERVO_MAP pwm_index=${savedMapping!.join(',')}';
          } else if (command == 'servo angles get') {
            response =
                'OK SERVO_ANGLES angle_deg=${angles.join(',')} max_deg=30.000 pwm_index=${mapping.join(',')}';
          } else if (command == 'servo manual start') {
            manual = true;
            angles = [0, 0, 0, 0];
            response = 'OK MANUAL active=1 lease_ms=1500';
          } else if (command == 'servo manual stop') {
            manual = false;
            angles = [0, 0, 0, 0];
            response = 'OK MANUAL active=0 lease_ms=1500';
          } else if (command == 'servo manual keepalive') {
            response = manual
                ? 'OK MANUAL active=1 lease_ms=1500'
                : 'ERR MANUAL_COMMAND_OR_BUSY';
          } else if (command.startsWith('servo angles set ')) {
            if (!manual || !idle) {
              response = 'ERR MANUAL_NOT_ARMED';
            } else {
              angles = command.split(' ').skip(3).map(double.parse).toList();
              response =
                  'OK SERVO_ANGLES angle_deg=${angles.join(',')} max_deg=30.000 pwm_index=${mapping.join(',')}';
            }
          } else if (command.startsWith('servo map set ')) {
            mapping = command.split(' ').skip(3).map(int.parse).toList();
            response = 'OK SERVO_MAP pwm_index=${mapping.join(',')}';
          } else if (command.startsWith('servo setall ')) {
            if (rejectOffsets || !idle) {
              response = 'ERR BUSY_OR_NOT_IDLE';
            } else {
              offsets = command.split(' ').skip(2).map(double.parse).toList();
              response = 'OK SERVO offset_deg=${offsets.join(',')}';
            }
          } else if (command == 'servo neutral') {
            angles = [0, 0, 0, 0];
            response = 'OK SERVO_ANGLES angle_deg=0,0,0,0';
          } else if (command == 'servo save') {
            savedOffsets = List.of(offsets);
            savedMapping = List.of(mapping);
            response = 'OK FLASH_PENDING';
            Timer(
              const Duration(milliseconds: 40),
              () =>
                  socket.add(ascii.encode('[DART] $id DONE FLASH status=OK\n')),
            );
          } else if (protocol >= 5 && command == 'cal saved') {
            response = supportsCalSaved
                ? 'OK CAL_SAVED valid=${(savedIcm ? 1 : 0) | (savedAdxl ? 4 : 0)} icm_range_g=${savedIcm ? savedIcmRange : 0} current_range_g=16 basis_valid=1 icm_lsb=${savedIcm ? savedIcmFaces.join(',') : '0,0,0,0,0,0'} adxl_offset=${savedAdxl ? savedAdxlOffset.join(',') : '0,0,0'} applied_adxl=${appliedAdxlOffset.join(',')}'
                : 'ERR UNKNOWN_COMMAND';
          } else if (protocol >= 5 && command == 'cal icm info') {
            response =
                'OK CAL_ICM status=$icmStatus faces=${_bitCount(icmMask)} active=255 samples=0 target=32 valid=$icmMask raw_lsb=2200,-2000,2100,-1900,2300,-2100 live_mps2=9.800,0.000,0.000 live_raw_lsb=${icmLiveRaw.join(',')} one_g_lsb=$icmOneGLsb live_samples=$icmLiveSamples';
          } else if (protocol >= 5 && command == 'cal adxl info') {
            response =
                'OK CAL_ADXL status=$adxlStatus icm_samples=64 adxl_samples=64 rejected=0 p2p=0.010,0.010,0.010 offset=1.000,2.000,3.000 icm_live=9.800,0.000,0.000 adxl_live=10.800,2.000,3.000';
          } else if (protocol >= 5 && command.startsWith('cal icm ')) {
            final face = [
              'x+',
              'x-',
              'y+',
              'y-',
              'z+',
              'z-',
            ].indexOf(command.substring(8));
            if (face >= 0) {
              icmMask |= 1 << face;
              icmStatus = icmMask == 63 ? 11 : 1;
              response = 'OK CAL_REQUESTED';
            } else if (command == 'cal icm reset') {
              icmMask = 0;
              icmStatus = 1;
              response = 'OK CAL_REQUESTED';
            } else if (command == 'cal icm save' && icmStatus == 11) {
              icmStatus = 5;
              calibrationFlashSaves++;
              response = 'OK FLASH_PENDING';
              Timer(const Duration(milliseconds: 40), () {
                savedIcm = true;
                savedAdxl = false;
                appliedAdxlOffset = [0, 0, 0];
                socket.add(ascii.encode('[DART] $id DONE FLASH status=OK\n'));
              });
            } else {
              response = 'ERR CAL_COMMAND_OR_BUSY';
            }
          } else if (protocol >= 5 && command.startsWith('cal adxl ')) {
            if (command == 'cal adxl start') {
              adxlStatus = 9;
              response = 'OK CAL_REQUESTED';
            } else if (command == 'cal adxl save' &&
                adxlStatus == 9 &&
                icmStatus != 11) {
              adxlStatus = 4;
              calibrationFlashSaves++;
              response = 'OK FLASH_PENDING';
              Timer(const Duration(milliseconds: 40), () {
                savedAdxl = true;
                appliedAdxlOffset = List.of(savedAdxlOffset);
                socket.add(ascii.encode('[DART] $id DONE FLASH status=OK\n'));
              });
            } else {
              response = 'ERR CAL_COMMAND_OR_BUSY';
            }
          } else {
            response = 'ERR UNKNOWN_COMMAND';
          }
          final frame = '[DART] $id $response\r\n';
          if (command.startsWith('servo setall ') &&
              offsetAckDelay > Duration.zero) {
            Timer(offsetAckDelay, () {
              if (sockets.contains(socket)) socket.add(ascii.encode(frame));
            });
          } else if (fragment) {
            socket.add([255, 251, 1]);
            socket.add(ascii.encode('[DART] 99999 OK stale\n'));
            socket.add(ascii.encode(frame.substring(0, 8)));
            Timer(
              const Duration(milliseconds: 5),
              () => socket.add(ascii.encode(frame.substring(8))),
            );
          } else {
            socket.add(ascii.encode(frame));
          }
        }
      });
    });
  }

  int _bitCount(int value) {
    var count = 0;
    while (value != 0) {
      count += value & 1;
      value >>= 1;
    }
    return count;
  }

  int get port => server!.port;
  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await server?.close();
  }
}
