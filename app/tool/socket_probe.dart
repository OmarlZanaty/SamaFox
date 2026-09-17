import 'dart:async';
import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main(List<String> args) async {
  final url = args.first;
  final s = io.io(url, io.OptionBuilder()
      .setTransports(['websocket', 'polling'])
      .disableAutoConnect()
      .disableReconnection()
      .setAuth({'token': 'probe'})
      .build());
  s.onConnect((_) => print('CONNECT ok transport=${s.io.engine?.transport?.name}'));
  s.onConnectError((e) => print('CONNECT_ERROR: $e'));
  s.onError((e) => print('ERROR: $e'));
  s.io.on('error', (e) => print('MANAGER_ERROR: $e'));
  s.io.on('reconnect_error', (e) => print('RECONNECT_ERROR: $e'));
  s.connect();
  await Future.delayed(const Duration(seconds: 12));
  print('engine state: ${s.io.engine?.readyState} transport=${s.io.engine?.transport?.name}');
  exit(0);
}
