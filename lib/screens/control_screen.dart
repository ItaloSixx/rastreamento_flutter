import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class ControlScreen extends StatefulWidget {
  final String title;
  final IconData icon;

  const ControlScreen({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final LocationService _locationService = LocationService();
  final TextEditingController _urlController = TextEditingController();
  final List<String> _logs = [];
  bool _isActive = false;
  bool _isLoading = false;
  String _statusMessage = 'Desconectado';
  Timer? _uiUpdateTimer;
  bool _hasError = false;
  String _responseText = '';
  bool _showDebugMode = false;

  @override
  void initState() {
    super.initState();
    // Definir URL padrão baseado no tipo
    if (widget.title == 'WEBSOCKET') {
      _urlController.text = 'ws://localhost:8080/ws';
    } else {
      _urlController.text = 'http://localhost:8080/api/location';
    }
    
    // Timer para atualizar a UI a cada segundo com os dados mais recentes do serviço
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isActive) {
        setState(() {
          _statusMessage = _locationService.statusMessage;
          _hasError = _statusMessage.toLowerCase().contains('erro');
          _updateResponseText();
        });
      }
    });
  }

  void _updateResponseText() {
    final response = _locationService.lastResponse;
    if (response != null) {
      if (response.containsKey('status') && response['status'] == 'sucesso') {
        _responseText = 'Resposta: Sucesso (ID: ${response['id']})';
      } else {
        _responseText = 'Resposta: $response';
      }
    }
  }

  // Método para adicionar logs
  void _addLog(String log) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $log');
      if (_logs.length > 20) {
        _logs.removeAt(0); // Manter apenas os últimos 20 logs
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _statusMessage = status;
        _hasError = status.toLowerCase().contains('erro');
        _updateResponseText();
        _addLog(status); // Adicionar ao log
      });
    }
  }

  void _toggleState() {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _logs.clear(); // Limpar logs ao iniciar nova conexão
    });

    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        final bool newState = !_isActive;
        
        if (newState) {
          bool success = false;
          try {
            _addLog('Iniciando conexão com ${_urlController.text}');
            if (widget.title == 'WEBSOCKET') {
              success = await _locationService.startWebSocketConnection(
                _urlController.text,
                _updateStatus
              );
            } else {
              success = await _locationService.startHttpTracking(
                _urlController.text,
                _updateStatus
              );
            }
          } catch (e) {
            _updateStatus('Erro: $e');
            success = false;
          }
          
          setState(() {
            _isActive = success;
            _isLoading = false;
          });
        } else {
          try {
            _addLog('Parando rastreamento');
            _locationService.stopTracking(_updateStatus);
          } catch (e) {
            _updateStatus('Erro ao parar rastreamento: $e');
          }
          setState(() {
            _isActive = false;
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Obter a posição atual do serviço de localização
    final Position? currentPosition = _locationService.lastPosition;
    final bool isSimulation = _isActive && _statusMessage.toLowerCase().contains('simulação');
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_showDebugMode ? Icons.settings : Icons.settings_outlined),
          onPressed: () {
            setState(() {
              _showDebugMode = !_showDebugMode;
            });
          },
          tooltip: 'Modo de depuração',
        ),
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: _showDebugMode 
            ? _buildDebugView(context, currentPosition) 
            : _buildMainView(context, currentPosition, isSimulation),
      ),
    );
  }
  
  Widget _buildDebugView(BuildContext context, Position? currentPosition) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título do modo depuração
          Center(
            child: Text(
              'Modo Depuração',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Card de configuração
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuração:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('URL', _urlController.text.isEmpty ? 'Não definido' : _urlController.text),
                  _buildInfoRow('Tipo', widget.title),
                  _buildInfoRow('Ativo', _isActive ? 'true' : 'false'),
                  _buildInfoRow('Tem erro', _hasError ? 'true' : 'false'),
                  if (currentPosition != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Última posição:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Latitude', currentPosition.latitude.toString()),
                    _buildInfoRow('Longitude', currentPosition.longitude.toString()),
                    _buildInfoRow('Velocidade', currentPosition.speed.toString()),
                    _buildInfoRow('Direção', currentPosition.heading.toString()),
                    _buildInfoRow('Precisão', currentPosition.accuracy.toString()),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Card de logs
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Logs de comunicação:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 20),
                        onPressed: () {
                          setState(() {
                            _logs.clear();
                          });
                        },
                        tooltip: 'Limpar logs',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Nenhum log disponível',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_logs.length, (index) {
                      final log = _logs[_logs.length - 1 - index]; // Inverso para mais recente primeiro
                      final isError = log.toLowerCase().contains('erro');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: isError
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Botão de ação
          Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _toggleState,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isActive
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: _isActive
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isActive ? 'ATIVAR' : 'ATIVAR',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMainView(BuildContext context, Position? currentPosition, bool isSimulation) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hasError 
                ? Theme.of(context).colorScheme.errorContainer 
                : isSimulation
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : _isActive
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Icon(
            _hasError 
                ? Icons.error_outline 
                : isSimulation
                    ? Icons.computer
                    : widget.icon,
            size: 64,
            color: _hasError 
                ? Theme.of(context).colorScheme.error 
                : isSimulation
                    ? Theme.of(context).colorScheme.tertiary
                    : _isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _hasError 
              ? 'ERRO' 
              : isSimulation
                  ? 'MODO SIMULAÇÃO'
                  : _isActive ? 'CONECTADO' : 'DESCONECTADO',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _hasError 
                ? Theme.of(context).colorScheme.error 
                : isSimulation
                    ? Theme.of(context).colorScheme.tertiary
                    : _isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _hasError 
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_responseText.isNotEmpty && _isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: Text(
              _responseText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        const SizedBox(height: 24),
        // Campo de texto para a URL
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: TextField(
            controller: _urlController,
            enabled: !_isActive, // Desabilitar durante conexão ativa
            decoration: InputDecoration(
              labelText: widget.title == 'WEBSOCKET' ? 'URL do WebSocket' : 'URL HTTP',
              hintText: widget.title == 'WEBSOCKET' 
                  ? 'ws://endereço:porta/caminho' 
                  : 'http://endereço:porta/caminho',
              helperText: widget.title == 'WEBSOCKET'
                  ? 'Exemplo: ws://localhost:8080/ws'
                  : 'Exemplo: http://localhost:8080/api/location',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: _isActive 
                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5)
                  : Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _isLoading
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _toggleState,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isActive
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: _isActive
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  _isActive ? 'DESLIGAR' : 'LIGAR',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
        const SizedBox(height: 24),
        if (_isActive && currentPosition != null && !_hasError)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Ativo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Modo',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Latitude',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      currentPosition.latitude.toStringAsFixed(6),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Longitude',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      currentPosition.longitude.toStringAsFixed(6),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (currentPosition.speed > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Velocidade',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${currentPosition.speed.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                if (currentPosition.heading > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Direção',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${currentPosition.heading.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}