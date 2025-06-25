import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/layer.dart';
import '../providers/offline_tile_provider.dart';

class OfflineCacheService {
  // Área de Jales/SP
  static const double _minLat = -20.3;
  static const double _maxLat = -20.2;
  static const double _minLng = -50.6;
  static const double _maxLng = -50.5;
  
  // Níveis de zoom para cache
  static const int _minZoom = 10;
  static const int _maxZoom = 16;

  static Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) || 
           connectivityResult.contains(ConnectivityResult.wifi);
  }

  static Future<void> downloadLayerTiles(
    Layer layer, 
    {Function(int current, int total)? onProgress}
  ) async {
    print('Iniciando download de tiles para: ${layer.name}');
    
    final tilesDir = await getTilesDirectory(layer.name);
    
    // Garantir que o diretório existe
    if (!await tilesDir.exists()) {
      await tilesDir.create(recursive: true);
    }
    
    final tiles = <TileCoordinate>[];
    
    // Gerar coordenadas dos tiles para a área de Jales
    for (int z = _minZoom; z <= _maxZoom; z++) {
      final bounds = _latLngToTileBounds(_minLat, _minLng, _maxLat, _maxLng, z);
      for (int x = bounds.minX; x <= bounds.maxX; x++) {
        for (int y = bounds.minY; y <= bounds.maxY; y++) {
          tiles.add(TileCoordinate(x: x, y: y, z: z));
        }
      }
    }
    
    print('Total de tiles para download: ${tiles.length}');
    
    int downloaded = 0;
    int skipped = 0;
    
    for (final tile in tiles) {
      try {
        final tileFile = File('${tilesDir.path}/${tile.z}_${tile.x}_${tile.y}.png');
        
        if (!await tileFile.exists()) {
          final tileData = await _downloadTile(layer, tile);
          if (tileData != null && tileData.isNotEmpty) {
            // Validar se é uma imagem válida (verificar header PNG)
            if (_isValidPng(tileData)) {
              await tileFile.writeAsBytes(tileData);
              downloaded++;
              
              // Verificar se o tile tem dados reais
              final hasData = _tileHasRealData(tileData);
              if (hasData) {
                print('✓ Tile COM DADOS salvo: ${tile.z}_${tile.x}_${tile.y}.png (${tileData.length} bytes) 🎨');
              } else {
                print('○ Tile vazio salvo: ${tile.z}_${tile.x}_${tile.y}.png (${tileData.length} bytes)');
              }
            } else {
              print('✗ Tile inválido: ${tile.z}_${tile.x}_${tile.y} - não é PNG válido');
              skipped++;
            }
          } else {
            print('✗ Tile vazio: ${tile.z}_${tile.x}_${tile.y}');
            skipped++;
          }
        } else {
          skipped++;
        }
        
        onProgress?.call(downloaded + skipped, tiles.length);
        
        // Pequeno delay para não sobrecarregar
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('Erro ao baixar tile ${tile.x},${tile.y},${tile.z}: $e');
        skipped++;
      }
    }
    
    print('Download concluído: $downloaded novos, $skipped existentes/erro');
  }

  static TileLayer createTileLayerForOffline(String layerName) {
    return TileLayer(
      urlTemplate: 'cache://{z}/{x}/{y}',
      tileProvider: OfflineTileProvider(layerName: layerName),
      userAgentPackageName: 'com.example.geomobile',
    );
  }

  static Future<bool> hasOfflineData(String layerName) async {
    try {
      final tilesDir = await getTilesDirectory(layerName);
      if (!await tilesDir.exists()) return false;
      
      final files = await tilesDir.list().where((f) => f.path.endsWith('.png')).toList();
      return files.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<int> getCachedTileCount(String layerName) async {
    try {
      final tilesDir = await getTilesDirectory(layerName);
      if (!await tilesDir.exists()) return 0;
      
      final files = await tilesDir.list().where((f) => f.path.endsWith('.png')).toList();
      return files.length;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> clearCache(String layerName) async {
    try {
      final tilesDir = await getTilesDirectory(layerName);
      if (await tilesDir.exists()) {
        await tilesDir.delete(recursive: true);
        print('Cache limpo para: $layerName');
      }
    } catch (e) {
      print('Erro ao limpar cache: $e');
    }
  }
  
  static Future<Directory> getTilesDirectory(String layerName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final safeName = layerName.replaceAll(':', '_').replaceAll('/', '_');
    return Directory('${appDir.path}/tiles/$safeName');
  }
  
  static Future<Uint8List?> _downloadTile(Layer layer, TileCoordinate tile) async {
    final bounds = _tileToLatLngBounds(tile.x, tile.y, tile.z);
    
    final url = 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
        'service=WMS&'
        'version=1.1.0&'
        'request=GetMap&'
        'layers=${Uri.encodeComponent(layer.name)}&'
        'styles=&'
        'bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}&'
        'width=256&'
        'height=256&'
        'srs=EPSG:3857&'
        'format=image/png&'
        'transparent=true';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final responseText = response.body;
        
        // Verificar se é uma resposta de erro
        if (responseText.contains('ServiceException') || 
            responseText.contains('java.io.IOException') ||
            responseText.contains('<ows:ExceptionReport') ||
            responseText.contains('<!DOCTYPE html>')) {
          print('✗ Resposta de erro do servidor para tile ${tile.z}_${tile.x}_${tile.y}');
          return null;
        }
        
        // Verificar se tem dados suficientes para ser uma imagem
        if (response.bodyBytes.length < 100) {
          print('✗ Resposta muito pequena para tile ${tile.z}_${tile.x}_${tile.y}: ${response.bodyBytes.length} bytes');
          return null;
        }
        
        return response.bodyBytes;
      } else {
        print('✗ Status HTTP ${response.statusCode} para tile ${tile.z}_${tile.x}_${tile.y}');
      }
    } catch (e) {
      print('✗ Erro ao baixar tile ${tile.z}_${tile.x}_${tile.y}: $e');
    }
    return null;
  }
  
  static bool _isValidPng(Uint8List data) {
    // Verificar header PNG: 89 50 4E 47 0D 0A 1A 0A
    if (data.length < 8) return false;
    
    return data[0] == 0x89 &&
           data[1] == 0x50 &&
           data[2] == 0x4E &&
           data[3] == 0x47 &&
           data[4] == 0x0D &&
           data[5] == 0x0A &&
           data[6] == 0x1A &&
           data[7] == 0x0A;
  }
  
  static bool _tileHasRealData(Uint8List data) {
    // Contar variação nos bytes para detectar se há dados reais
    var uniqueBytes = <int>{};
    for (int i = 100; i < math.min(data.length, 1000); i += 10) {
      uniqueBytes.add(data[i]);
      if (uniqueBytes.length > 15) return true; // Muita variação = tem dados
    }
    return uniqueBytes.length > 8; // Alguma variação = provavelmente tem dados
  }
  
  static Future<Uint8List?> getCachedTile(String layerName, int x, int y, int z) async {
    try {
      final tilesDir = await getTilesDirectory(layerName);
      final tileFile = File('${tilesDir.path}/${z}_${x}_${y}.png');
      
      if (await tileFile.exists()) {
        return await tileFile.readAsBytes();
      }
    } catch (e) {
      print('Erro ao ler tile cached: $e');
    }
    return null;
  }

  // Utilitários de conversão de coordenadas
  static TileBounds _latLngToTileBounds(double minLat, double minLng, double maxLat, double maxLng, int zoom) {
    final minTile = _latLngToTile(minLat, minLng, zoom);
    final maxTile = _latLngToTile(maxLat, maxLng, zoom);
    
    return TileBounds(
      minX: math.min(minTile.x, maxTile.x),
      maxX: math.max(minTile.x, maxTile.x),
      minY: math.min(minTile.y, maxTile.y),
      maxY: math.max(minTile.y, maxTile.y),
    );
  }

  static TileCoordinate _latLngToTile(double lat, double lng, int zoom) {
    final n = 1 << zoom;
    final x = ((lng + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n).floor();
    return TileCoordinate(x: x, y: y, z: zoom);
  }

  static LatLngBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = 1 << z;
    final west = x / n * 360.0 - 180.0;
    final east = (x + 1) / n * 360.0 - 180.0;
    final north = (math.atan(math.exp(math.pi * (1 - 2 * y / n))) - math.pi / 2) * 180.0 / math.pi;
    final south = (math.atan(math.exp(math.pi * (1 - 2 * (y + 1) / n))) - math.pi / 2) * 180.0 / math.pi;
    
    return LatLngBounds(west: west, south: south, east: east, north: north);
  }
}

// Classes auxiliares
class TileCoordinate {
  final int x, y, z;
  TileCoordinate({required this.x, required this.y, required this.z});
}

class TileBounds {
  final int minX, maxX, minY, maxY;
  TileBounds({required this.minX, required this.maxX, required this.minY, required this.maxY});
}

class LatLngBounds {
  final double west, south, east, north;
  LatLngBounds({required this.west, required this.south, required this.east, required this.north});
}