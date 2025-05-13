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
  bool _isActive = false;
  bool _isLoading = false;
  String _statusMessage = 'Desconectado';
  Timer? _uiUpdateTimer;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // Timer para atualizar a UI a cada segundo com os dados mais recentes do serviço
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isActive) {
        setState(() {
          _statusMessage = _locationService.statusMessage;
          _hasError = _statusMessage.toLowerCase().contains('erro');
        });
      }
    });
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _statusMessage = status;
        _hasError = status.toLowerCase().contains('erro');
      });
    }
  }

  void _toggleState() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        final bool newState = !_isActive;
        
        if (newState) {
          bool success = false;
          try {
            if (widget.title == 'WEBSOCKET') {
              success = await _locationService.startWebSocketConnection(_updateStatus);
            } else {
              success = await _locationService.startHttpTracking(_updateStatus);
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
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasError 
                    ? Theme.of(context).colorScheme.errorContainer 
                    : _isActive
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: Icon(
                _hasError 
                    ? Icons.error_outline 
                    : widget.icon,
                size: 64,
                color: _hasError 
                    ? Theme.of(context).colorScheme.error 
                    : _isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _hasError 
                  ? 'ERRO' 
                  : _isActive ? 'CONECTADO' : 'DESCONECTADO',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _hasError 
                    ? Theme.of(context).colorScheme.error 
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
            const SizedBox(height: 32),
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
                  color: Theme.of(context).colorScheme.surfaceVariant,
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
} 