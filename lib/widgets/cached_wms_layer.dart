import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/layer.dart';
import '../services/offline_cache_service.dart';

class CachedWMSLayerWidget extends StatelessWidget {
  final Layer layer;

  const CachedWMSLayerWidget({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    print('Criando TileLayer Cached para: ${layer.name}');

    return TileLayer(
      tileProvider: CachedTileProvider(layerName: layer.name),
      tileSize: 256,
    );
  }
}

class CachedTileProvider extends TileProvider {
  final String layerName;

  CachedTileProvider({required this.layerName});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedTileImageProvider(
      layerName: layerName,
      coordinates: coordinates,
      options: options,
    );
  }
}

class CachedTileImageProvider extends ImageProvider<CachedTileKey> {
  final String layerName;
  final TileCoordinates coordinates;
  final TileLayer options;

  const CachedTileImageProvider({
    required this.layerName,
    required this.coordinates,
    required this.options,
  });

  @override
  Future<CachedTileKey> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedTileKey>(
      CachedTileKey(
        layerName: layerName,
        x: coordinates.x,
        y: coordinates.y,
        z: coordinates.z,
      ),
    );
  }

  @override
  ImageStreamCompleter loadImage(CachedTileKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(CachedTileKey key, ImageDecoderCallback decode) async {
    try {
      // Tentar carregar do cache
      final cachedData = await OfflineCacheService.getCachedTile(
        key.layerName, key.x, key.y, key.z,
      );

      if (cachedData != null) {
        print('Carregando tile offline: ${key.layerName} ${key.x},${key.y},${key.z}');
        try {
          final buffer = await ui.ImmutableBuffer.fromUint8List(cachedData);
          return await decode(buffer);
        } catch (e) {
          print('Erro ao decodificar tile cached: $e');
          // Remove tile corrompido do cache
          await OfflineCacheService.database.then((db) {
            db.delete('cached_tiles', 
              where: 'layer_name = ? AND x = ? AND y = ? AND z = ?',
              whereArgs: [key.layerName, key.x, key.y, key.z]
            );
          });
        }
      }

      // Tile não encontrado - usar um tile vazio de 1x1 pixel
      print('Tile não encontrado no cache: ${key.layerName} ${key.x},${key.y},${key.z}');
      return _createEmptyCodec(decode);

    } catch (e) {
      print('Erro ao carregar tile cached: $e');
      return _createEmptyCodec(decode);
    }
  }

  Future<ui.Codec> _createEmptyCodec(ImageDecoderCallback decode) async {
    // Usa PNG transparente válido e simples
    final transparentPng = _createTransparentTile();
    final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
    return await decode(buffer);
  }

  Uint8List _createTransparentTile() {
    // PNG transparente válido de 1x1 pixel (comprovado)
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, // IHDR length
      0x49, 0x48, 0x44, 0x52, // IHDR
      0x00, 0x00, 0x00, 0x01, // width = 1
      0x00, 0x00, 0x00, 0x01, // height = 1
      0x08, 0x06, 0x00, 0x00, 0x00, // bit depth, color type, compression, filter, interlace
      0x1F, 0x15, 0xC4, 0x89, // CRC
      0x00, 0x00, 0x00, 0x0A, // IDAT length
      0x49, 0x44, 0x41, 0x54, // IDAT
      0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // compressed data
      0x0D, 0x0A, 0x2D, 0xB4, // CRC
      0x00, 0x00, 0x00, 0x00, // IEND length
      0x49, 0x45, 0x4E, 0x44, // IEND
      0xAE, 0x42, 0x60, 0x82  // CRC
    ]);
  }
}

class CachedTileKey {
  final String layerName;
  final int x, y, z;

  const CachedTileKey({
    required this.layerName,
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CachedTileKey &&
        other.layerName == layerName &&
        other.x == x &&
        other.y == y &&
        other.z == z;
  }

  @override
  int get hashCode => Object.hash(layerName, x, y, z);
}