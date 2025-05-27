// Implementação temporária usando memória em vez de SharedPreferences
// devido a erros com o plugin

class SettingsService {
  // Dados em memória
  String _deviceName = '';
  String _webSocketUrl = '';
  String _httpUrl = '';

  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();
  
  factory SettingsService() {
    return _instance;
  }
  
  SettingsService._internal();

  // Salvar nome do dispositivo
  Future<void> saveDeviceName(String name) async {
    _deviceName = name;
  }

  // Obter nome do dispositivo
  Future<String> getDeviceName() async {
    return _deviceName;
  }

  // Salvar URL do WebSocket
  Future<void> saveWebSocketUrl(String url) async {
    _webSocketUrl = url;
  }

  // Obter URL do WebSocket
  Future<String> getWebSocketUrl() async {
    return _webSocketUrl;
  }

  // Salvar URL HTTP
  Future<void> saveHttpUrl(String url) async {
    _httpUrl = url;
  }

  // Obter URL HTTP
  Future<String> getHttpUrl() async {
    return _httpUrl;
  }
} 