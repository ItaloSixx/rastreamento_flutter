import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LocationService {
  WebSocketChannel? _channel;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastPosition;
  String _statusMessage = 'Desconectado';
  bool _isActive = false;
  bool _isWindows = false;

  // Getters
  Position? get lastPosition => _lastPosition;
  String get statusMessage => _statusMessage;
  bool get isActive => _isActive;

  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  
  factory LocationService() {
    return _instance;
  }
  
  LocationService._internal() {
    _isWindows = !kIsWeb && Platform.isWindows;
  }

  // Métodos para gerenciar permissões e localização
  Future<bool> requestLocationPermission() async {
    // No Windows e Web, não precisamos solicitar permissão via permission_handler
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // No desktop/web, usamos apenas o Geolocator
      return true;
    }
    
    // Nos dispositivos móveis, usamos o permission_handler
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.location.request();
      return status.isGranted;
    }
    
    return false;
  }

  Future<bool> checkLocationService() async {
    // Verifica se o serviço de localização está ativado
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      _statusMessage = 'Erro ao verificar serviço de localização: $e';
      return false;
    }
  }

  Future<Position?> getCurrentLocation() async {
    try {
      // No desktop/web, primeiro precisamos verificar a permissão usando o Geolocator
      if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            _statusMessage = 'Permissão de localização negada';
            return null;
          }
        }
        
        if (permission == LocationPermission.deniedForever) {
          _statusMessage = 'Permissão de localização negada permanentemente';
          return null;
        }
      }
      
      // No Windows, pode ser que não consigamos obter a localização real,
      // então usamos uma localização simulada em caso de erro
      if (_isWindows) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          _lastPosition = position;
          return position;
        } catch (e) {
          print('Erro ao obter localização no Windows: $e');
          print('Usando localização simulada para Windows');
          
          // Localização simulada para Windows (coordenadas de Brasília)
          final Position simulatedPosition = Position(
            latitude: -15.7801,
            longitude: -47.9292,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
          
          _lastPosition = simulatedPosition;
          return simulatedPosition;
        }
      } else {
        // Para outras plataformas, obtemos normalmente
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _lastPosition = position;
        return position;
      }
    } catch (e) {
      _statusMessage = 'Erro ao obter localização: $e';
      return null;
    }
  }

  // Métodos para WebSocket
  Future<bool> startWebSocketConnection(Function(String) onStatusChange) async {
    if (_isActive) return true;
    
    // Verificar serviço de localização antes de pedir permissão
    final serviceEnabled = await checkLocationService();
    if (!serviceEnabled) {
      _statusMessage = 'Serviço de localização desabilitado';
      onStatusChange(_statusMessage);
      return false;
    }
    
    // Nos dispositivos móveis, pedimos permissão via permission_handler
    // No desktop/web, a permissão será solicitada dentro de getCurrentLocation
    if (Platform.isAndroid || Platform.isIOS) {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        _statusMessage = 'Permissão de localização negada';
        onStatusChange(_statusMessage);
        return false;
      }
    }

    try {
      // Tentar estabelecer a conexão WebSocket
      try {
        _channel = WebSocketChannel.connect(
          Uri.parse('ws://echo.websocket.events'),
        );
        
        // Verificamos se conseguimos conectar tentando ler o stream
        // Isso força uma tentativa de conexão 
        await _channel!.stream.timeout(
          const Duration(seconds: 5),
          onTimeout: (sink) => sink.close(),
        ).first;
        
        _statusMessage = 'WebSocket conectado com sucesso';
      } catch (e) {
        print('Aviso ao conectar WebSocket: $e');
        _statusMessage = 'Usando modo de simulação (sem WebSocket)';
        // Podemos prosseguir mesmo sem o WebSocket, apenas simulando
        _channel = null;
      }
      
      // Configurar o timer para atualizações periódicas
      _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
        await _sendLocationUpdate(onStatusChange);
      });
      
      // Primeira leitura imediata
      await _sendLocationUpdate(onStatusChange);
      
      _isActive = true;
      
      if (_channel != null) {
        _statusMessage = 'Conectado! Enviando localização a cada 20 segundos';
      } else {
        _statusMessage = 'Modo simulação! Obtendo localização a cada 20 segundos';
      }
      
      onStatusChange(_statusMessage);
      return true;
    } catch (e) {
      _statusMessage = 'Erro ao iniciar rastreamento: $e';
      onStatusChange(_statusMessage);
      return false;
    }
  }

  Future<void> _sendLocationUpdate(Function(String) onStatusChange) async {
    final position = await getCurrentLocation();
    if (position != null) {
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'isSimulated': _isWindows, // Indicar se é uma localização simulada
      };
      
      // Enviar para WebSocket se disponível
      if (_channel != null) {
        try {
          _channel!.sink.add(jsonEncode(locationData));
          _statusMessage = 'Localização enviada: ${position.latitude}, ${position.longitude}';
        } catch (e) {
          print('Erro ao enviar para WebSocket: $e');
          _statusMessage = 'Erro no envio. Obtida: ${position.latitude}, ${position.longitude}';
        }
      } else {
        // Apenas registrar a localização obtida
        _statusMessage = 'Localização obtida: ${position.latitude}, ${position.longitude}';
      }
      
      if (_isWindows) {
        _statusMessage += ' (simulada)';
      }
      
      onStatusChange(_statusMessage);
    }
  }

  Future<bool> startHttpTracking(Function(String) onStatusChange) async {
    if (_isActive) return true;
    
    // Verificar serviço de localização antes de pedir permissão
    final serviceEnabled = await checkLocationService();
    if (!serviceEnabled) {
      _statusMessage = 'Serviço de localização desabilitado';
      onStatusChange(_statusMessage);
      return false;
    }
    
    // Nos dispositivos móveis, pedimos permissão via permission_handler
    // No desktop/web, a permissão será solicitada dentro de getCurrentLocation
    if (Platform.isAndroid || Platform.isIOS) {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        _statusMessage = 'Permissão de localização negada';
        onStatusChange(_statusMessage);
        return false;
      }
    }

    // Para o modo HTTP, apenas obter a localização atual
    final position = await getCurrentLocation();
    if (position != null) {
      _isActive = true;
      _statusMessage = 'HTTP: Localização atual: ${position.latitude}, ${position.longitude}';
      if (_isWindows) {
        _statusMessage += ' (simulada)';
      }
      onStatusChange(_statusMessage);
      return true;
    }
    
    return false;
  }

  void stopTracking(Function(String) onStatusChange) {
    _locationTimer?.cancel();
    _locationTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _closeWebSocket();
    _isActive = false;
    _statusMessage = 'Desconectado';
    onStatusChange(_statusMessage);
  }

  void _closeWebSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    stopTracking((_) {});
  }
} 