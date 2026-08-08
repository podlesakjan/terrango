import 'package:web_socket_channel/web_socket_channel.dart';

class GameSocketDataSource {
  GameSocketDataSource(String url)
    : _channel = WebSocketChannel.connect(Uri.parse(url));

  final WebSocketChannel _channel;

  Stream<dynamic> get stream => _channel.stream;

  void send(String payload) {
    _channel.sink.add(payload);
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}
