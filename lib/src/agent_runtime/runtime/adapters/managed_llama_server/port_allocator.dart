import 'dart:async';
import 'dart:io';

/// Contratto per l'allocazione controllata della porta TCP di loopback.
abstract interface class PortAllocator {
  Future<int> allocatePort({int? preferredPort, String host = '127.0.0.1'});
}

/// Implementazione concreta basata sul bind temporaneo a porta 0 via [ServerSocket].
class LoopbackPortAllocator implements PortAllocator {
  const LoopbackPortAllocator();

  @override
  Future<int> allocatePort(
      {int? preferredPort, String host = '127.0.0.1'}) async {
    if (preferredPort != null) {
      try {
        final socket = await ServerSocket.bind(host, preferredPort);
        final port = socket.port;
        await socket.close();
        return port;
      } catch (_) {
        // Preferred port non disponibile, fallback su allocazione automatica
      }
    }

    try {
      final socket = await ServerSocket.bind(host, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (e) {
      throw Exception(
          'Impossibile allocare una porta di loopback libera su $host: $e');
    }
  }
}
