import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

class GameSocketDataSource {
  GameSocketDataSource(
    String url, {
    String? bearerToken,
  }) : _controller = StreamController<dynamic>.broadcast(),
       _bearerToken = bearerToken?.trim(),
       _socket = io.io(
         url,
         io.OptionBuilder()
             .setTransports(['websocket'])
             .disableAutoConnect()
             .enableReconnection()
             .setReconnectionAttempts(10)
             .setReconnectionDelay(1000)
             .setAuth({
               if (bearerToken != null && bearerToken.isNotEmpty) 'token': bearerToken,
             })
             .setExtraHeaders({
               if (bearerToken != null && bearerToken.isNotEmpty)
                 'Authorization': 'Bearer $bearerToken',
             })
             .build(),
       ) {
    _socket.onAny((event, data) {
      _controller.add({'event': event, 'data': data});
    });
  }

  final io.Socket _socket;
  final StreamController<dynamic> _controller;
  final String? _bearerToken;

  Stream<dynamic> get stream => _controller.stream;

  bool get isConnected => _socket.connected;

  void connect() {
    if (_socket.connected) {
      return;
    }
    if (_bearerToken?.isNotEmpty == true) {
      final options = _socket.io.options ?? <String, dynamic>{};
      options['auth'] = {'token': _bearerToken};
      options['extraHeaders'] = {
        'Authorization': 'Bearer $_bearerToken',
      };
      _socket.io.options = options;
    }
    _socket.connect();
  }

  void disconnect() {
    if (!_socket.connected) {
      return;
    }
    _socket.disconnect();
  }

  void onConnected(void Function() listener) {
    _socket.onConnect((_) => listener());
  }

  void onReconnected(void Function() listener) {
    _socket.onReconnect((_) => listener());
  }

  void onDisconnected(void Function(String? reason) listener) {
    _socket.onDisconnect((reason) => listener(reason));
  }

  void emit(String event, [dynamic data]) {
    _socket.emit(event, data);
  }

  void emitJson(String event, Map<String, dynamic> payload) {
    _socket.emit(event, payload);
  }

  Future<void> close() async {
    _socket.dispose();
    await _controller.close();
  }
}
