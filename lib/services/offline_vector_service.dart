import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/layer.dart';
import '../services/geoserver_service.dart';

class OfflineVectorService {
  // Área de Jales/SP
  static const double _minLat = -20.3;
  static const double _maxLat = -20.2;
  static const double _minLng = -50.6;
  static const double _maxLng = -50.5;

  static Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) || 
           connectivityResult.contains(ConnectivityResult.wifi);
  }

  static Future<void> downloadLayerFeatures(
    Layer layer,
    GeoServerService geoServerService,
    {Function(int current, int total)? onProgress}
  ) async {
    print('🌐 Iniciando download WFS para: ${layer.name}');
    
    final featuresDir = await getFeaturesDirectory(layer.name);
    
    // Garantir que o diretório existe
    if (!await featuresDir.exists()) {
      await featuresDir.create(recursive: true);
    }
    
    try {
      // Etapa 1: Iniciando requisição (10%)
      onProgress?.call(1, 10);
      print('📡 Fazendo requisição WFS...');
      await Future.delayed(const Duration(milliseconds: 100)); // UI responsiva
      
      // Fazer requisição WFS para a área de Jales/SP
      final geoJson = await geoServerService.getFeatures(
        layer.name,
        minX: _minLng,
        minY: _minLat,
        maxX: _maxLng,
        maxY: _maxLat,
        srs: 'EPSG:4326',
      );

      // Etapa 2: Requisição concluída (40%)
      onProgress?.call(4, 10);
      print('📦 Dados WFS recebidos, processando...');
      await Future.delayed(const Duration(milliseconds: 200));

      if (geoJson != null && geoJson.containsKey('features')) {
        final features = geoJson['features'] as List;
        
        if (features.isNotEmpty) {
          // Etapa 3: Processando features (60%)
          onProgress?.call(6, 10);
          print('🔄 Processando ${features.length} features...');
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Etapa 4: Salvando GeoJSON (80%)
          onProgress?.call(8, 10);
          print('💾 Salvando dados...');
          await Future.delayed(const Duration(milliseconds: 200));
          
          final featuresFile = File('${featuresDir.path}/features.geojson');
          await featuresFile.writeAsString(jsonEncode(geoJson));
          
          // Etapa 5: Salvando metadata (90%)
          onProgress?.call(9, 10);
          await Future.delayed(const Duration(milliseconds: 200));
          
          final metadata = {
            'layerName': layer.name,
            'layerTitle': layer.title,
            'workspace': layer.workspace,
            'featureCount': features.length,
            'downloadDate': DateTime.now().toIso8601String(),
            'bbox': {
              'minLng': _minLng,
              'minLat': _minLat,
              'maxLng': _maxLng,
              'maxLat': _maxLat,
            },
            'geometryTypes': _analyzeGeometryTypes(features),
          };
          
          final metadataFile = File('${featuresDir.path}/metadata.json');
          await metadataFile.writeAsString(jsonEncode(metadata));
          
          // Etapa 6: Concluído (100%)
          onProgress?.call(10, 10);
          await Future.delayed(const Duration(milliseconds: 100));
          print('✅ Download WFS concluído: ${features.length} features salvas para ${layer.name}');
          print('📍 Tipos de geometria: ${metadata['geometryTypes']}');
        } else {
          print('⚠️ Nenhuma feature encontrada para ${layer.name} na área especificada');
          onProgress?.call(10, 10);
        }
      } else {
        throw Exception('Resposta WFS inválida ou vazia');
      }
    } catch (e) {
      print('❌ Erro no download WFS: $e');
      rethrow;
    }
  }

  static List<String> _analyzeGeometryTypes(List features) {
    final types = <String>{};
    for (final feature in features) {
      if (feature is Map && feature.containsKey('geometry')) {
        final geometry = feature['geometry'];
        if (geometry is Map && geometry.containsKey('type')) {
          types.add(geometry['type'].toString());
        }
      }
    }
    return types.toList();
  }

  static Future<Map<String, dynamic>?> getCachedFeatures(String layerName) async {
    try {
      final featuresDir = await getFeaturesDirectory(layerName);
      final featuresFile = File('${featuresDir.path}/features.geojson');
      
      if (await featuresFile.exists()) {
        final content = await featuresFile.readAsString();
        final geoJson = jsonDecode(content) as Map<String, dynamic>;
        
        print('📦 Features cached carregadas: ${layerName}');
        if (geoJson.containsKey('features')) {
          final features = geoJson['features'] as List;
          print('📍 ${features.length} features encontradas no cache');
        }
        
        return geoJson;
      }
    } catch (e) {
      print('❌ Erro ao ler features cached: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getCachedMetadata(String layerName) async {
    try {
      final featuresDir = await getFeaturesDirectory(layerName);
      final metadataFile = File('${featuresDir.path}/metadata.json');
      
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      print('❌ Erro ao ler metadata: $e');
    }
    return null;
  }

  static Future<bool> hasOfflineData(String layerName) async {
    try {
      final featuresDir = await getFeaturesDirectory(layerName);
      final featuresFile = File('${featuresDir.path}/features.geojson');
      
      if (await featuresFile.exists()) {
        // Verificar se o arquivo tem conteúdo válido
        final content = await featuresFile.readAsString();
        final geoJson = jsonDecode(content) as Map<String, dynamic>;
        
        if (geoJson.containsKey('features')) {
          final features = geoJson['features'] as List;
          return features.isNotEmpty;
        }
      }
    } catch (e) {
      print('❌ Erro ao verificar dados offline: $e');
    }
    return false;
  }

  static Future<int> getCachedFeatureCount(String layerName) async {
    try {
      final metadata = await getCachedMetadata(layerName);
      if (metadata != null && metadata.containsKey('featureCount')) {
        return metadata['featureCount'] as int;
      }
      
      // Fallback: contar features diretamente
      final geoJson = await getCachedFeatures(layerName);
      if (geoJson != null && geoJson.containsKey('features')) {
        final features = geoJson['features'] as List;
        return features.length;
      }
    } catch (e) {
      print('❌ Erro ao contar features: $e');
    }
    return 0;
  }

  static Future<void> clearCache(String layerName) async {
    try {
      final featuresDir = await getFeaturesDirectory(layerName);
      if (await featuresDir.exists()) {
        await featuresDir.delete(recursive: true);
        print('🗑️ Cache vetorial limpo para: $layerName');
      }
    } catch (e) {
      print('❌ Erro ao limpar cache vetorial: $e');
    }
  }

  static Future<List<String>> getAvailableOfflineLayers() async {
    try {
      final baseDir = await getBaseFeaturesDirectory();
      if (!await baseDir.exists()) return [];
      
      final layers = <String>[];
      await for (final entity in baseDir.list()) {
        if (entity is Directory) {
          final layerName = _restoreLayerName(entity.path.split('/').last);
          final hasData = await hasOfflineData(layerName);
          if (hasData) {
            layers.add(layerName);
          }
        }
      }
      
      return layers;
    } catch (e) {
      print('❌ Erro ao listar camadas offline: $e');
      return [];
    }
  }

  static Future<Directory> getFeaturesDirectory(String layerName) async {
    final baseDir = await getBaseFeaturesDirectory();
    final safeName = _sanitizeLayerName(layerName);
    return Directory('${baseDir.path}/$safeName');
  }

  static Future<Directory> getBaseFeaturesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/features');
  }

  static String _sanitizeLayerName(String layerName) {
    return layerName.replaceAll(':', '_').replaceAll('/', '_').replaceAll(' ', '_');
  }

  static String _restoreLayerName(String safeName) {
    // Assumindo formato JalesC2245_layer_name -> JalesC2245:layer_name
    if (safeName.startsWith('JalesC2245_')) {
      return safeName.replaceFirst('JalesC2245_', 'JalesC2245:');
    }
    return safeName.replaceAll('_', ':');
  }

  static Future<void> clearAllCache() async {
    try {
      final baseDir = await getBaseFeaturesDirectory();
      if (await baseDir.exists()) {
        await baseDir.delete(recursive: true);
        print('🗑️ Todo cache vetorial limpo');
      }
    } catch (e) {
      print('❌ Erro ao limpar todo cache vetorial: $e');
    }
  }
}