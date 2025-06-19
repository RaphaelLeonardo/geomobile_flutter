import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../models/layer.dart';

class WMSLayerWidget extends StatefulWidget {
  final Layer layer;

  const WMSLayerWidget({super.key, required this.layer});

  @override
  State<WMSLayerWidget> createState() => _WMSLayerWidgetState();
}

class _WMSLayerWidgetState extends State<WMSLayerWidget> {
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkLayerHealth();
  }

  Future<void> _checkLayerHealth() async {
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
    if (_hasError) {
      return const SizedBox.shrink();
    }

    print('Criando TileLayer WMS para: ${widget.layer.name}');

    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', // Placeholder - não será usado
      tileProvider: WMSTileProvider(
        baseUrl: 'http://admin:geodados@186.237.132.58:15124/geoserver/wms',
        layerName: widget.layer.name,
      ),
      tileSize: 256,
      userAgentPackageName: 'com.example.geomobile',
    );
  }
}

class WMSTileProvider extends TileProvider {
  final String baseUrl;
  final String layerName;

  WMSTileProvider({
    required this.baseUrl,
    required this.layerName,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final bounds = _tileToLatLngBounds(coordinates.x, coordinates.y, coordinates.z);
    
    // Incluir credenciais diretamente na URL para maior compatibilidade
    final url = 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
        'service=WMS&'
        'version=1.1.0&'
        'request=GetMap&'
        'layers=${Uri.encodeComponent(layerName)}&'
        'styles=&'
        'bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}&'
        'width=256&'
        'height=256&'
        'srs=EPSG:3857&'
        'format=image/png&'
        'transparent=true';

    print('WMS URL: $url');
    print('Tile coordinates: x=${coordinates.x}, y=${coordinates.y}, z=${coordinates.z}');
    print('Bounds: west=${bounds.west}, south=${bounds.south}, east=${bounds.east}, north=${bounds.north}');

    // Teste direto da URL
    _testWMSUrl(url);

    // Usar credenciais na URL em vez de headers para melhor compatibilidade
    return NetworkImage(url);
  }

  Future<void> _testWMSUrl(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('admin:geodados'))}',
        },
      );
      print('WMS Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('WMS Response body: ${response.body}');
      } else {
        print('WMS Response length: ${response.bodyBytes.length} bytes');
      }
    } catch (e) {
      print('WMS Request error: $e');
    }
  }

  WMSBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = 1 << z;
    final west = _tileToLng(x, z);
    final east = _tileToLng(x + 1, z);
    final north = _tileToLat(y, z);
    final south = _tileToLat(y + 1, z);
    
    // Converter para Web Mercator (EPSG:3857)
    final westMercator = _lngToWebMercator(west);
    final eastMercator = _lngToWebMercator(east);
    final northMercator = _latToWebMercator(north);
    final southMercator = _latToWebMercator(south);
    
    return WMSBounds(
      west: westMercator,
      south: southMercator,
      east: eastMercator,
      north: northMercator,
    );
  }

  double _tileToLng(int x, int z) {
    return x / (1 << z) * 360.0 - 180.0;
  }

  double _tileToLat(int y, int z) {
    final n = math.pi - 2.0 * math.pi * y / (1 << z);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  double _lngToWebMercator(double lng) {
    return lng * 20037508.34 / 180.0;
  }

  double _latToWebMercator(double lat) {
    final latRad = lat * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4 + latRad / 2)) * 20037508.34 / math.pi;
  }
}

class WMSBounds {
  final double west, south, east, north;
  WMSBounds({required this.west, required this.south, required this.east, required this.north});
}