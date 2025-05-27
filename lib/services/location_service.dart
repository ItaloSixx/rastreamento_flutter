import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

class LocationService {
  WebSocketChannel? _channel;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastPosition;
  String _statusMessage = 'Desconectado';
  bool _isActive = false;
  bool _isWindows = false;
  String _webSocketUrl = '';
  String _httpUrl = '';
  String _deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';
  String _deviceName = '';
  Map<String, dynamic>? _lastResponse;
  Function(String)? _logCallback;
  Function(String)? _onStatusChange;
  Function(Map<String, dynamic>?)? _onResponseChange;
  Function(String)? _onLogMessage;

  // Setters para callbacks
  set onStatusChange(Function(String)? callback) {
    _onStatusChange = callback;
  }

  set onResponseChange(dynamic callback) {
    if (callback is Function(Map<String, dynamic>?)) {
      _onResponseChange = callback;
    } else if (callback is Function(String)) {
      // Adapta função que espera String para Map
      _onResponseChange = (Map<String, dynamic>? response) {
        final Function(String) stringCallback = callback;
        stringCallback(response?.toString() ?? 'null');
      };
    } else {
      _onResponseChange = null;
    }
  }

  set onLogMessage(Function(String)? callback) {
    _onLogMessage = callback;
    setLogCallback(callback ?? (String message) {});
  }

  // Método para definir o nome do dispositivo
  void setDeviceName(String name) {
    if (name.isNotEmpty) {
      _deviceName = name;
      // Atualiza o deviceId com o formato apropriado baseado no tipo de conexão
      if (_webSocketUrl.isNotEmpty) {
        _deviceId = 'ws-$_deviceName';
      } else if (_httpUrl.isNotEmpty) {
        _deviceId = 'http-$_deviceName';
      } else {
        _deviceId = _deviceName;
      }
      _log('Nome do dispositivo definido: $_deviceName, ID: $_deviceId');
    }
  }

  // Método para registrar o callback de log
  void setLogCallback(Function(String) callback) {
    _logCallback = callback;
  }
  
  // Método para logar com callback se disponível
  void _log(String message) {
    print(message); // Sempre imprime no console
    _logCallback?.call(message); // Chama o callback se estiver definido
    _onLogMessage?.call(message); // Chama o callback onLogMessage se estiver definido
  }

  // Método para atualizar status
  void _updateStatus(String status) {
    _statusMessage = status;
    _onStatusChange?.call(status);
  }

  // Método para atualizar resposta
  void _updateResponse(Map<String, dynamic>? response) {
    _lastResponse = response;
    _onResponseChange?.call(response);
  }

  // Getters
  Position? get lastPosition => _lastPosition;
  String get statusMessage => _statusMessage;
  bool get isActive => _isActive;
  Map<String, dynamic>? get lastResponse => _lastResponse;
  String get webSocketUrl => _webSocketUrl;
  String get httpUrl => _httpUrl;

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
      _updateStatus('Erro ao verificar serviço de localização: $e');
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
            _updateStatus('Permissão de localização negada');
            return null;
          }
        }
        
        if (permission == LocationPermission.deniedForever) {
          _updateStatus('Permissão de localização negada permanentemente');
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
          _log('Erro ao obter localização no Windows: $e');
          _log('Usando localização simulada para Windows');
          
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
      _updateStatus('Erro ao obter localização: $e');
      return null;
    }
  }

  // Métodos para WebSocket
  Future<bool> startWebSocketConnection(String url, [Function(String)? onStatusChange]) async {
    if (_isActive) return true;
    
    _webSocketUrl = url.trim();
    if (_webSocketUrl.isEmpty) {
      final status = 'URL do WebSocket não pode estar vazia';
      _updateStatus(status);
      onStatusChange?.call(status);
      return false;
    }
    
    // Atualiza o deviceId para refletir o tipo de conexão
    if (_deviceName.isNotEmpty) {
      _deviceId = 'ws-$_deviceName';
      _log('ID do dispositivo atualizado: $_deviceId');
    }
    
    // Verifica se a URL tem o formato correto
    if (!_webSocketUrl.startsWith('ws://') && !_webSocketUrl.startsWith('wss://')) {
      final status = 'URL do WebSocket deve começar com ws:// ou wss://';
      _updateStatus(status);
      onStatusChange?.call(status);
      return false;
    }
    
    // Verificar serviço de localização antes de pedir permissão
    final serviceEnabled = await checkLocationService();
    if (!serviceEnabled) {
      final status = 'Serviço de localização desabilitado';
      _updateStatus(status);
      onStatusChange?.call(status);
      return false;
    }
    
    // Nos dispositivos móveis, pedimos permissão via permission_handler
    // No desktop/web, a permissão será solicitada dentro de getCurrentLocation
    if (Platform.isAndroid || Platform.isIOS) {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        final status = 'Permissão de localização negada';
        _updateStatus(status);
        onStatusChange?.call(status);
        return false;
      }
    }

    try {
      bool connectionSuccessful = false;
      
      // Teste de conexão WebSocket com mensagem de teste
      _log('Iniciando conexão WebSocket com $_webSocketUrl');
      final connectingStatus = 'Conectando a $_webSocketUrl...';
      _updateStatus(connectingStatus);
      onStatusChange?.call(connectingStatus);
      
      try {
        // Criar o canal WebSocket
        _channel = WebSocketChannel.connect(Uri.parse(_webSocketUrl));
        
        // Aguardar um pouco para a conexão estabelecer
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Teste de conexão com mensagem específica
        final testMessage = {
          'tipo': 'teste_conexao',
          'dados': {
            'dispositivo_id': _deviceId,
            'timestamp': DateTime.now().millisecondsSinceEpoch
          }
        };
        
        // Configurar listener para mensagens recebidas
        bool receivedResponse = false;
        final completer = Completer<bool>();
        
        // Criar uma subscription para ouvir a resposta
        final subscription = _channel!.stream.listen(
          (message) {
            try {
              _log('Recebido do WebSocket: $message');
              receivedResponse = true;
              
              try {
                final Map<String, dynamic> response = jsonDecode(message);
                _updateResponse(response);
                if (response.containsKey('status') && response['status'] == 'sucesso') {
                  final status = 'Resposta recebida: Sucesso! ID: ${response['id']}';
                  _updateStatus(status);
                  onStatusChange?.call(status);
                } else {
                  final status = 'Resposta recebida: $response';
                  _updateStatus(status);
                  onStatusChange?.call(status);
                }
              } catch (e) {
                _log('Resposta não é um JSON válido: $e');
                final status = 'Resposta recebida (não-JSON): $message';
                _updateStatus(status);
                onStatusChange?.call(status);
              }
              
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            } catch (e) {
              _log('Erro ao processar mensagem: $e');
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            }
          },
          onError: (error) {
            _log('Erro no stream do WebSocket: $error');
            final status = 'Erro na conexão WebSocket: $error';
            _updateStatus(status);
            onStatusChange?.call(status);
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          },
          onDone: () {
            _log('Conexão WebSocket fechada');
            if (_isActive) {
              final status = 'Conexão WebSocket encerrada';
              _updateStatus(status);
              onStatusChange?.call(status);
            }
            if (!completer.isCompleted && !receivedResponse) {
              completer.complete(false);
            }
          },
        );
        
        // Enviar a mensagem de teste
        _log('Enviando mensagem de teste: ${jsonEncode(testMessage)}');
        _channel!.sink.add(jsonEncode(testMessage));
        
        // Tentar verificar se a conexão está realmente aberta
        // Usar ready como um indicador adicional
        bool readyState = false;
        try {
          await _channel!.ready.timeout(const Duration(seconds: 2));
          readyState = true;
          _log('WebSocket ready state: OK');
        } catch (e) {
          _log('WebSocket ready falhou: $e');
        }
        
        // Esperar por uma resposta ou timeout
        bool gotResponse = false;
        try {
          gotResponse = await completer.future.timeout(const Duration(seconds: 5));
        } catch (e) {
          _log('Timeout esperando resposta do servidor');
        }
        
        // Verificar se recebemos uma resposta ou se o ready state está ok
        connectionSuccessful = gotResponse || readyState;
        
        if (connectionSuccessful) {
          _log('Conexão WebSocket estabelecida com sucesso');
          final status = 'WebSocket conectado com sucesso!';
          _updateStatus(status);
          onStatusChange?.call(status);
        } else {
          // Se não recebemos resposta mas o WebSocket está "ready", avisar que ele pode
          // estar conectado mas o servidor não está respondendo
          if (readyState) {
            _log('WebSocket conectado, mas servidor não está respondendo');
            final status = 'WebSocket conectado, mas servidor não responde. Funcionando em modo unidirecional.';
            _updateStatus(status);
            onStatusChange?.call(status);
            connectionSuccessful = true; // Consideramos como sucesso parcial, podemos enviar, mas não receber
          } else {
            // Cancelar a assinatura existente se não tivermos sucesso
            subscription.cancel();
            _closeWebSocket();
            _log('Falha na conexão WebSocket');
            final status = 'Falha na conexão WebSocket. Usando modo simulação.';
            _updateStatus(status);
            onStatusChange?.call(status);
          }
        }
        
      } catch (e) {
        _log('Exceção ao conectar WebSocket: $e');
        String status;
        if (e.toString().contains('No element')) {
          status = 'Servidor WebSocket não respondeu. Usando modo simulação.';
        } else {
          status = 'Erro na conexão WebSocket: $e. Usando modo simulação.';
        }
        _updateStatus(status);
        onStatusChange?.call(status);
        _closeWebSocket();
      }
      
      // Configurar o timer para atualizações periódicas de qualquer forma
      _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
        await _sendLocationUpdate(onStatusChange);
      });
      
      // Primeira leitura imediata
      await _sendLocationUpdate(onStatusChange);
      
      _isActive = true;
      
      if (!connectionSuccessful) {
        final status = 'Modo simulação! Obtendo localização a cada 20 segundos';
        _updateStatus(status);
        onStatusChange?.call(status);
      }
      
      return true;
    } catch (e) {
      final status = 'Erro ao iniciar rastreamento: $e';
      _updateStatus(status);
      onStatusChange?.call(status);
      return false;
    }
  }

  Future<void> _sendLocationUpdate([Function(String)? onStatusChange]) async {
    final position = await getCurrentLocation();
    if (position != null) {
      // Novo formato de mensagem conforme especificado
      final locationData = {
        'tipo': 'localizacao',
        'dados': {
          'dispositivo_id': _deviceId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'velocidade': position.speed.round(), // em km/h, arredondado para inteiro
          'direcao': position.heading.round(), // direção em graus, arredondado para inteiro
        }
      };
      
      // Enviar para WebSocket se disponível
      if (_channel != null) {
        try {
          // Converte para JSON e imprime para depuração
          final String jsonData = jsonEncode(locationData);
          _log('Enviando dados para WebSocket: $jsonData');
          
          // Verificar se o WebSocket ainda está aberto
          if (_channel!.closeCode != null) {
            _log('WebSocket está fechado. Code: ${_channel!.closeCode}');
            final status = 'Erro: WebSocket fechado. Reconectando...';
            _updateStatus(status);
            onStatusChange?.call(status);
            
            // Fechar o canal antigo
            _closeWebSocket();
            
            // Tentar reconectar
            try {
              _channel = WebSocketChannel.connect(Uri.parse(_webSocketUrl));
              await Future.delayed(const Duration(seconds: 1)); // Aguardar conexão
              _log('Reconectado ao WebSocket');
            } catch (reconnectError) {
              _log('Erro ao reconectar: $reconnectError');
              final status = 'Erro na reconexão. Modo simulação ativado.';
              _updateStatus(status);
              onStatusChange?.call(status);
              return;
            }
          }
          
          // Tentar enviar a mensagem
          try {
            _channel!.sink.add(jsonData);
            _log('Mensagem enviada com sucesso');
            final status = 'Localização enviada: ${position.latitude}, ${position.longitude}';
            _updateStatus(status);
          } catch (sendError) {
            _log('Exceção ao enviar dados: $sendError');
            final status = 'Erro ao enviar dados: $sendError';
            _updateStatus(status);
            onStatusChange?.call(status);
            _closeWebSocket();
            return;
          }
          
          // Verificar se o WebSocket está conectado após enviar (detecção de problemas)
          try {
            await _channel!.ready.timeout(const Duration(milliseconds: 500));
            _log('WebSocket ainda conectado após envio');
          } catch (e) {
            _log('WebSocket não está mais conectado após envio: $e');
            final status = 'Perda de conexão após envio. Modo simulação ativado.';
            _updateStatus(status);
            onStatusChange?.call(status);
            _closeWebSocket();
            return;
          }
          
          // Adiciona um ping após o envio para verificar se o servidor está recebendo
          Future.delayed(const Duration(seconds: 1), () {
            try {
              if (_channel != null && _channel!.closeCode == null) {
                _log('Enviando ping de verificação');
                _channel!.sink.add(jsonEncode({
                  'tipo': 'ping',
                  'dados': {
                    'dispositivo_id': _deviceId,
                    'timestamp': DateTime.now().millisecondsSinceEpoch
                  }
                }));
              }
            } catch (pingError) {
              _log('Erro ao enviar ping: $pingError');
            }
          });
        } catch (e) {
          _log('Erro ao enviar para WebSocket: $e');
          final status = 'Erro no envio: $e. Usando modo simulação.';
          _updateStatus(status);
          // Fechamos o canal com erro e continuamos em modo simulação
          _closeWebSocket();
        }
      } else {
        // Apenas registrar a localização obtida
        final status = 'Localização obtida: ${position.latitude}, ${position.longitude} (modo simulação)';
        _updateStatus(status);
      }
      
      String currentStatus = _statusMessage;
      if (_isWindows) {
        currentStatus += ' (simulada)';
      }
      
      _updateStatus(currentStatus);
      onStatusChange?.call(currentStatus);
    }
  }

  // Método para iniciar conexão HTTP (nome atualizado para compatibilidade)
  Future<bool> startHttpConnection(String url) async {
    return await startHttpTracking(url, (status) {
      _updateStatus(status);
    });
  }

  Future<bool> startHttpTracking(String url, Function(String) onStatusChange) async {
    if (_isActive) return true;
    
    _httpUrl = url.trim();
    if (_httpUrl.isEmpty) {
      final status = 'URL HTTP não pode estar vazia';
      _updateStatus(status);
      onStatusChange(status);
      return false;
    }
    
    // Atualiza o deviceId para refletir o tipo de conexão
    if (_deviceName.isNotEmpty) {
      _deviceId = 'http-$_deviceName';
      _log('ID do dispositivo atualizado: $_deviceId');
    }
    
    // Verifica se a URL tem o formato correto
    if (!_httpUrl.startsWith('http://') && !_httpUrl.startsWith('https://')) {
      final status = 'URL HTTP deve começar com http:// ou https://';
      _updateStatus(status);
      onStatusChange(status);
      return false;
    }
    
    // Verificar serviço de localização antes de pedir permissão
    final serviceEnabled = await checkLocationService();
    if (!serviceEnabled) {
      final status = 'Serviço de localização desabilitado';
      _updateStatus(status);
      onStatusChange(status);
      return false;
    }
    
    // Nos dispositivos móveis, pedimos permissão via permission_handler
    // No desktop/web, a permissão será solicitada dentro de getCurrentLocation
    if (Platform.isAndroid || Platform.isIOS) {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        final status = 'Permissão de localização negada';
        _updateStatus(status);
        onStatusChange(status);
        return false;
      }
    }

    try {
      // Testar conexão e enviar dados iniciais
      _log('Iniciando HTTP tracking para $_httpUrl');
      final connectingStatus = 'Conectando a $_httpUrl...';
      _updateStatus(connectingStatus);
      onStatusChange(connectingStatus);
      
      // Para o modo HTTP, obter a localização e enviar a cada 20 segundos
      final position = await getCurrentLocation();
      if (position != null) {
        _isActive = true;
        
        // Tentar fazer uma requisição HTTP para verificar se o servidor está acessível
        try {
          // Prepara os dados no formato correto
          final requestData = {
            'tipo': 'localizacao',
            'dados': {
              'dispositivo_id': _deviceId,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'velocidade': position.speed.round(),
              'direcao': position.heading.round(),
            }
          };
          
          // Converte para JSON
          final String jsonData = jsonEncode(requestData);
          _log('Enviando teste HTTP: $jsonData');
          
          // Define os headers corretamente
          final Map<String, String> headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          };
          
          // Faz a requisição HTTP
          final testResponse = await http.post(
            Uri.parse(_httpUrl),
            headers: headers,
            body: jsonData,
          ).timeout(const Duration(seconds: 10));
          
          _log('Resposta HTTP status: ${testResponse.statusCode}');
          _log('Resposta HTTP body: ${testResponse.body}');
          
          String status;
          if (testResponse.statusCode >= 200 && testResponse.statusCode < 300) {
            try {
              final Map<String, dynamic> responseData = jsonDecode(testResponse.body);
              _updateResponse(responseData);
              if (responseData.containsKey('status') && responseData['status'] == 'sucesso') {
                status = 'Servidor HTTP respondeu com sucesso! ID: ${responseData['id']}';
              } else {
                status = 'Servidor HTTP respondeu: $responseData';
              }
            } catch (e) {
              status = 'Servidor HTTP respondeu, mas com formato inválido: ${testResponse.body}';
            }
          } else {
            status = 'Erro HTTP ${testResponse.statusCode}: ${testResponse.body}. Usando modo simulação.';
          }
          _updateStatus(status);
        } catch (e) {
          _log('Erro ao testar conexão HTTP: $e');
          final status = 'Erro ao conectar ao servidor HTTP: $e. Usando modo simulação.';
          _updateStatus(status);
        }
        
        onStatusChange(_statusMessage);
        
        // Configurar o timer para atualizações periódicas
        _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
          await _sendHttpUpdate(onStatusChange);
        });
        
        return true;
      }
    } catch (e) {
      final status = 'Erro ao iniciar rastreamento HTTP: $e';
      _updateStatus(status);
      onStatusChange(status);
    }
    
    return false;
  }
  
  Future<void> _sendHttpUpdate(Function(String) onStatusChange) async {
    final position = await getCurrentLocation();
    if (position != null) {
      // Novo formato de mensagem conforme especificado
      final requestData = {
        'tipo': 'localizacao',
        'dados': {
          'dispositivo_id': _deviceId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'velocidade': position.speed.round(), // em km/h, arredondado para inteiro
          'direcao': position.heading.round(), // direção em graus, arredondado para inteiro
        }
      };
      
      bool httpSuccess = false;
      
      try {
        // Converte para JSON e imprime para depuração
        final String jsonData = jsonEncode(requestData);
        _log('Enviando dados HTTP: $jsonData');
        _log('URL destino: $_httpUrl');
        
        // Define os headers corretamente
        final Map<String, String> headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        
        // Faz a requisição HTTP
        final response = await http.post(
          Uri.parse(_httpUrl),
          headers: headers,
          body: jsonData,
        ).timeout(const Duration(seconds: 10));
        
        _log('Resposta HTTP: Status ${response.statusCode}');
        _log('Resposta HTTP: Body ${response.body}');
        
        String status;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final Map<String, dynamic> responseData = jsonDecode(response.body);
            _updateResponse(responseData);
            if (responseData.containsKey('status') && responseData['status'] == 'sucesso') {
              status = 'Enviado com sucesso! ID: ${responseData['id']}';
            } else {
              status = 'Resposta: $responseData';
            }
            httpSuccess = true;
          } catch (e) {
            _log('Erro ao processar resposta JSON: $e');
            status = 'Enviado, mas erro ao processar resposta: ${response.body}';
            httpSuccess = true; // Consideramos sucesso mesmo se não conseguirmos processar a resposta
          }
        } else {
          status = 'Erro HTTP ${response.statusCode}: ${response.body}. Usando modo simulação.';
        }
        _updateStatus(status);
      } catch (e) {
        _log('Exceção ao enviar HTTP: $e');
        final status = 'Erro ao enviar HTTP: $e. Usando modo simulação.';
        _updateStatus(status);
      }
      
      // Se não tivermos sucesso, apenas registramos a localização em modo simulação
      if (!httpSuccess) {
        final status = 'Modo simulação! Localização obtida: ${position.latitude}, ${position.longitude}';
        _updateStatus(status);
      }
      
      String currentStatus = _statusMessage;
      if (_isWindows) {
        currentStatus += ' (simulada)';
      }
      
      _updateStatus(currentStatus);
      onStatusChange(currentStatus);
    }
  }

  // Método para parar conexão WebSocket (nome atualizado para compatibilidade)
  Future<void> stopWebSocketConnection() async {
    stopTracking((status) => _updateStatus(status));
  }

  // Método para parar conexão HTTP (nome atualizado para compatibilidade)
  Future<void> stopHttpConnection() async {
    stopTracking((status) => _updateStatus(status));
  }

  void stopTracking(Function(String) onStatusChange) {
    _locationTimer?.cancel();
    _locationTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _closeWebSocket();
    _isActive = false;
    final status = 'Desconectado';
    _updateStatus(status);
    _updateResponse(null);
    onStatusChange(status);
  }

  void _closeWebSocket() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    stopTracking((_) {});
  }
}