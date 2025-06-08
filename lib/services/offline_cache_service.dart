import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/layer.dart';

class OfflineCacheService {
  static Database? _database;
  static const String _tableName = 'cached_tiles';
  
  // Área de Jales/SP em coordenadas Web Mercator
  static const double _minLat = -20.3;
  static const double _maxLat = -20.2;
  static const double _minLng = -50.6;
  static const double _maxLng = -50.5;
  
  // Níveis de zoom para cache
  static const int _minZoom = 10;
  static const int _maxZoom = 18;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = '${documentsDirectory.path}/offline_cache.db';
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            layer_name TEXT NOT NULL,
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            z INTEGER NOT NULL,
            tile_data BLOB NOT NULL,
            downloaded_at INTEGER NOT NULL,
            UNIQUE(layer_name, x, y, z)
          )
        ''');
      },
    );
  }

  static Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) || 
           connectivityResult.contains(ConnectivityResult.wifi);
  }

  static Future<void> downloadLayerTiles(
    Layer layer, 
    {Function(int current, int total)? onProgress}
  ) async {
    final db = await database;
    
    print('Iniciando download de tiles para: ${layer.name}');
    
    final tiles = <TileCoordinate>[];
    
    // Calcular tiles necessários para a área de Jales com zoom limitado
    for (int z = _minZoom; z <= 16; z++) { // Limita até zoom 16 por performance
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
    final total = tiles.length;

    for (final tile in tiles) {
      try {
        final exists = await _tileExists(db, layer.name, tile.x, tile.y, tile.z);
        if (!exists) {
          final tileData = await _downloadTile(layer, tile);
          if (tileData != null && tileData.isNotEmpty) {
            await _saveTile(db, layer.name, tile.x, tile.y, tile.z, tileData);
            downloaded++;
          } else {
            skipped++;
          }
        } else {
          skipped++;
        }
        onProgress?.call(downloaded + skipped, total);
        
        // Pequeno delay para não sobrecarregar o servidor
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('Erro ao baixar tile ${tile.x},${tile.y},${tile.z}: $e');
        skipped++;
      }
    }
    
    print('Download concluído: $downloaded novos, $skipped existentes/erro, $total total');
  }

  static Future<bool> _tileExists(Database db, String layerName, int x, int y, int z) async {
    final result = await db.query(
      _tableName,
      where: 'layer_name = ? AND x = ? AND y = ? AND z = ?',
      whereArgs: [layerName, x, y, z],
      limit: 1,
    );
    return result.isNotEmpty;
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
      if (response.statusCode == 200 && 
          !response.body.contains('ServiceException')) {
        return response.bodyBytes;
      }
    } catch (e) {
      print('Erro ao baixar tile: $e');
    }
    return null;
  }

  static Future<void> _saveTile(Database db, String layerName, int x, int y, int z, Uint8List data) async {
    await db.insert(
      _tableName,
      {
        'layer_name': layerName,
        'x': x,
        'y': y,
        'z': z,
        'tile_data': data,
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Uint8List?> getCachedTile(String layerName, int x, int y, int z) async {
    final db = await database;
    final result = await db.query(
      _tableName,
      columns: ['tile_data'],
      where: 'layer_name = ? AND x = ? AND y = ? AND z = ?',
      whereArgs: [layerName, x, y, z],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['tile_data'] as Uint8List;
    }
    return null;
  }

  static Future<bool> hasOfflineData(String layerName) async {
    final db = await database;
    final result = await db.query(
      _tableName,
      where: 'layer_name = ?',
      whereArgs: [layerName],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  static Future<int> getCachedTileCount(String layerName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE layer_name = ?',
      [layerName],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> clearCache(String layerName) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'layer_name = ?',
      whereArgs: [layerName],
    );
  }

  // Utilitários para conversão de coordenadas
  static TileBounds _latLngToTileBounds(double minLat, double minLng, double maxLat, double maxLng, int zoom) {
    final minTile = _latLngToTile(minLat, minLng, zoom);
    final maxTile = _latLngToTile(maxLat, maxLng, zoom);
    
    return TileBounds(
      minX: minTile.x < maxTile.x ? minTile.x : maxTile.x,
      maxX: minTile.x > maxTile.x ? minTile.x : maxTile.x,
      minY: minTile.y < maxTile.y ? minTile.y : maxTile.y,
      maxY: minTile.y > maxTile.y ? minTile.y : maxTile.y,
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