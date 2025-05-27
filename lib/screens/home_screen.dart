import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import 'control_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _deviceNameController = TextEditingController();
  final LocationService _locationService = LocationService();
  final SettingsService _settingsService = SettingsService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final deviceName = await _settingsService.getDeviceName();
      if (mounted) {
        setState(() {
          _deviceNameController.text = deviceName;
          // Configura o nome do dispositivo no serviço de localização
          if (deviceName.isNotEmpty) {
            _locationService.setDeviceName(deviceName);
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações: $e');
      // Continuar sem mostrar erro ao usuário
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveDeviceName() async {
    final name = _deviceNameController.text.trim();
    if (name.isNotEmpty) {
      try {
        await _settingsService.saveDeviceName(name);
        _locationService.setDeviceName(name);
      } catch (e) {
        debugPrint('Erro ao salvar nome do dispositivo: $e');
        // Continuar sem mostrar erro ao usuário
      }
    }
  }

  void _navigateToControlScreen(String title, IconData icon) {
    try {
      _saveDeviceName();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ControlScreen(
            title: title,
            icon: icon,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao navegar: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir a tela de controle: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.tertiary,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Icon(
                        Icons.sensors,
                        size: 80,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'RASTREAMENTO',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Campo para o nome do dispositivo
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: TextField(
                          controller: _deviceNameController,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nome do Dispositivo',
                            labelStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
                            ),
                            hintText: 'Ex: Meu Smartphone',
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                            ),
                            prefixIcon: Icon(
                              Icons.devices,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.onPrimary,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            // Salvar automaticamente quando o texto mudar
                            _saveDeviceName();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Selecione o modo de conexão',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            _buildOptionCard(
                              context,
                              title: 'HTTP',
                              icon: Icons.http,
                              onTap: () => _navigateToControlScreen('HTTP', Icons.http),
                            ),
                            const SizedBox(height: 16),
                            _buildOptionCard(
                              context,
                              title: 'WEBSOCKET',
                              icon: Icons.wifi_tethering,
                              onTap: () => _navigateToControlScreen('WEBSOCKET', Icons.wifi_tethering),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toque para configurar',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 