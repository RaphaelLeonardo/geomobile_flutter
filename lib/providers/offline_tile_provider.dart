import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../services/offline_cache_service.dart';

class OfflineTileProvider extends TileProvider {
  final String layerName;

  OfflineTileProvider({required this.layerName});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImageProvider(
      layerName: layerName,
      coordinates: coordinates,
    );
  }
}

class OfflineTileImageProvider extends ImageProvider<OfflineTileKey> {
  final String layerName;
  final TileCoordinates coordinates;

  const OfflineTileImageProvider({
    required this.layerName,
    required this.coordinates,
  });

  @override
  Future<OfflineTileKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<OfflineTileKey>(
      OfflineTileKey(
        layerName: layerName,
        x: coordinates.x,
        y: coordinates.y,
        z: coordinates.z,
      ),
    );
  }

  @override
  ImageStreamCompleter loadImage(OfflineTileKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(OfflineTileKey key, ImageDecoderCallback decode) async {
    try {
      final isOnline = await OfflineCacheService.isOnline();
      
      // Tentar cache primeiro
      final cachedData = await OfflineCacheService.getCachedTile(
        key.layerName, key.x, key.y, key.z,
      );

      if (cachedData != null) {
        try {
          print('📥 Carregando tile cached: ${key.layerName} ${key.x},${key.y},${key.z} (${cachedData.length} bytes)');
          
          // Verificar se todos os bytes são iguais (tile vazio/transparente)
          final isBlank = _isTileBlank(cachedData);
          if (isBlank) {
            print('⚪ Tile em branco detectado: ${key.x},${key.y},${key.z}');
          } else {
            print('🎨 Tile com dados detectado: ${key.x},${key.y},${key.z}');
          }
          
          // Verificar se o arquivo cached é válido
          if (_isValidPng(cachedData)) {
            print('✓ PNG header válido para tile ${key.x},${key.y},${key.z}');
            final buffer = await ui.ImmutableBuffer.fromUint8List(cachedData);
            print('✓ Buffer criado para tile ${key.x},${key.y},${key.z}');
            final codec = await decode(buffer);
            print('✓ Tile decodificado com sucesso: ${key.x},${key.y},${key.z}');
            return codec;
          } else {
            print('✗ Tile cached com header PNG inválido: ${key.layerName} ${key.x},${key.y},${key.z}');
            print('   Primeiros 16 bytes: ${cachedData.take(16).toList()}');
            // Remover arquivo corrompido
            await _removeCachedTile(key.layerName, key.x, key.y, key.z);
          }
        } catch (e) {
          print('✗ Erro ao decodificar tile cached: ${key.layerName} ${key.x},${key.y},${key.z} - $e');
          print('   Tamanho do arquivo: ${cachedData.length} bytes');
          print('   Primeiros 16 bytes: ${cachedData.take(16).toList()}');
          await _removeCachedTile(key.layerName, key.x, key.y, key.z);
        }
      }

      // Se não está no cache e está online, baixar
      if (isOnline) {
        final url = _buildWmsUrl(key);
        final response = await http.get(Uri.parse(url));
        
        if (response.statusCode == 200 && !response.body.contains('ServiceException')) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
          return await decode(buffer);
        }
      }

      // Fallback: tile transparente
      print('🔄 Usando tile transparente para: ${key.layerName} ${key.x},${key.y},${key.z}');
      return await _createTransparentCodec(decode);

    } catch (e) {
      print('❌ Erro ao carregar tile: ${key.layerName} ${key.x},${key.y},${key.z} - $e');
      return await _createTransparentCodec(decode);
    }
  }

  String _buildWmsUrl(OfflineTileKey key) {
    final bounds = _tileToLatLngBounds(key.x, key.y, key.z);
    return 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
        'service=WMS&'
        'version=1.1.0&'
        'request=GetMap&'
        'layers=${Uri.encodeComponent(key.layerName)}&'
        'styles=&'
        'bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}&'
        'width=256&'
        'height=256&'
        'srs=EPSG:3857&'
        'format=image/png&'
        'transparent=true';
  }

  _TileBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = 1 << z;
    final west = x / n * 360.0 - 180.0;
    final east = (x + 1) / n * 360.0 - 180.0;
    final north = (math.atan(math.exp(math.pi * (1 - 2 * y / n))) - math.pi / 2) * 180.0 / math.pi;
    final south = (math.atan(math.exp(math.pi * (1 - 2 * (y + 1) / n))) - math.pi / 2) * 180.0 / math.pi;
    
    return _TileBounds(west: west, south: south, east: east, north: north);
  }

  bool _isValidPng(Uint8List data) {
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
  
  bool _isTileBlank(Uint8List data) {
    // Verificar se todos os tiles têm o mesmo tamanho (indicativo de tiles vazios)
    if (data.length == 1784) {
      // Contar variação nos bytes para detectar se há dados reais
      var uniqueBytes = <int>{};
      for (int i = 100; i < math.min(data.length, 500); i++) {
        uniqueBytes.add(data[i]);
        if (uniqueBytes.length > 10) return false; // Tem variação = tem dados
      }
      return uniqueBytes.length <= 5; // Poucos bytes únicos = provavelmente vazio
    }
    return false;
  }
  
  Future<void> _removeCachedTile(String layerName, int x, int y, int z) async {
    try {
      final tilesDir = await OfflineCacheService.getTilesDirectory(layerName);
      final tileFile = File('${tilesDir.path}/${z}_${x}_${y}.png');
      if (await tileFile.exists()) {
        await tileFile.delete();
        print('🗑️ Tile corrompido removido: ${layerName} ${x},${y},${z}');
      }
    } catch (e) {
      print('Erro ao remover tile corrompido: $e');
    }
  }

  Future<ui.Codec> _createTransparentCodec(ImageDecoderCallback decode) async {
    print('🎨 Criando tile transparente programático');
    return await _createProgrammaticTransparentCodec();
  }
  
  Future<ui.Codec> _createProgrammaticTransparentCodec() async {
    // Criar uma imagem 256x256 transparente programaticamente
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));
    
    // Desenhar um retângulo transparente
    final paint = Paint()
      ..color = const Color(0x00000000) // Transparente
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 256), paint);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    
    print('🖼️ Tile transparente programático criado (${bytes.length} bytes)');
    
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return await ui.instantiateImageCodecFromBuffer(buffer);
  }
}

class OfflineTileKey {
  final String layerName;
  final int x, y, z;

  const OfflineTileKey({
    required this.layerName,
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OfflineTileKey &&
        other.layerName == layerName &&
        other.x == x &&
        other.y == y &&
        other.z == z;
  }

  @override
  int get hashCode => Object.hash(layerName, x, y, z);
}

class _TileBounds {
  final double west, south, east, north;
  _TileBounds({required this.west, required this.south, required this.east, required this.north});
}