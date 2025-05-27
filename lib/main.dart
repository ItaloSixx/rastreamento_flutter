import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar a verificação de permissões
  try {
    // Verificação inicial das permissões de localização
    await Geolocator.checkPermission();
  } catch (e) {
    print('Aviso: Verificação inicial de permissões: $e');
  }
  
  runApp(const MyApp());
}