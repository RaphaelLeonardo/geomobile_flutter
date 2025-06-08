import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../models/layer.dart';
import '../services/offline_cache_service.dart';

class OfflineWMSLayerWidget extends StatefulWidget {
  final Layer layer;

  const OfflineWMSLayerWidget({super.key, required this.layer});

  @override
  State<OfflineWMSLayerWidget> createState() => _OfflineWMSLayerWidgetState();
}

class _OfflineWMSLayerWidgetState extends State<OfflineWMSLayerWidget> {
  bool _hasError = false;
  String? _errorMessage;
  bool _hasOfflineData = false;

  @override
  void initState() {
    super.initState();
    _checkLayerHealth();
    _checkOfflineData();
  }

  Future<void> _checkOfflineData() async {
    final hasData = await OfflineCacheService.hasOfflineData(widget.layer.name);
    if (mounted) {
      setState(() {
        _hasOfflineData = hasData;
      });
    }
  }

  Future<void> _checkLayerHealth() async {
    final isOnline = await OfflineCacheService.isOnline();
    if (!isOnline) return; // Skip health check when offline
    
    try {
      final testUrl = 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
          'service=WMS&'
          'version=1.1.0&'
          'request=GetMap&'
          'layers=${Uri.encodeComponent(widget.layer.name)}&'
          'styles=&'
          'srs=EPSG:3857&'
          'bbox=-5650000,-2350000,-5630000,-2330000&'
          'width=256&'
          'height=256&'
          'format=image/png&'
          'transparent=true';

      final response = await http.get(Uri.parse(testUrl));
      
      if (response.body.contains('ServiceException') || 
          response.body.contains('java.io.IOException')) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Fonte de dados indisponível';
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Erro de conexão';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError && !_hasOfflineData) {
      return const SizedBox.shrink();
    }

    print('Criando TileLayer WMS/Offline para: ${widget.layer.name}');

    return TileLayer(
      wmsOptions: WMSTileLayerOptions(
        baseUrl: 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?',
        layers: [widget.layer.name],
      ),
      tileProvider: OfflineTileProvider(layerName: widget.layer.name),
      tileSize: 256,
    );
  }
}

class OfflineTileProvider extends TileProvider {
  final String layerName;

  OfflineTileProvider({required this.layerName});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImageProvider(
      layerName: layerName,
      coordinates: coordinates,
      options: options,
    );
  }
}

class OfflineTileImageProvider extends ImageProvider<OfflineTileKey> {
  final String layerName;
  final TileCoordinates coordinates;
  final TileLayer options;

  const OfflineTileImageProvider({
    required this.layerName,
    required this.coordinates,
    required this.options,
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
        print('Carregando tile do cache: ${key.layerName} ${key.x},${key.y},${key.z}');
        final buffer = await ui.ImmutableBuffer.fromUint8List(cachedData);
        return await decode(buffer);
      }

      // Se não está no cache e está online, baixar
      if (isOnline) {
        final bounds = _tileToLatLngBounds(key.x, key.y, key.z);
        final url = 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
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

        final response = await http.get(Uri.parse(url));
        
        if (response.statusCode == 200 && !response.body.contains('ServiceException')) {
          print('Baixando tile online: ${key.layerName} ${key.x},${key.y},${key.z}');
          final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
          return await decode(buffer);
        }
      }

      // Fallback: tile transparente
      print('Usando tile transparente para: ${key.layerName} ${key.x},${key.y},${key.z}');
      final transparentTile = _createTransparentTile();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparentTile);
      return await decode(buffer);

    } catch (e) {
      print('Erro ao carregar tile: $e');
      final transparentTile = _createTransparentTile();
      final buffer = await ui.ImmutableBuffer.fromUint8List(transparentTile);
      return await decode(buffer);
    }
  }

  Uint8List _createTransparentTile() {
    // PNG transparente mínimo (1x1 pixel)
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x5C, 0x72, 0xA8, 0x66, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
  }

  LatLngBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = 1 << z;
    final west = x / n * 360.0 - 180.0;
    final east = (x + 1) / n * 360.0 - 180.0;
    final north = (math.atan(math.exp(math.pi * (1 - 2 * y / n))) - math.pi / 2) * 180.0 / math.pi;
    final south = (math.atan(math.exp(math.pi * (1 - 2 * (y + 1) / n))) - math.pi / 2) * 180.0 / math.pi;
    
    return LatLngBounds(west: west, south: south, east: east, north: north);
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

class LatLngBounds {
  final double west, south, east, north;
  LatLngBounds({required this.west, required this.south, required this.east, required this.north});
}