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
import '../providers/offline_tile_provider.dart';

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
      urlTemplate: 'cache://{z}/{x}/{y}', // Template placeholder  
      tileProvider: OfflineTileProvider(layerName: widget.layer.name),
      userAgentPackageName: 'com.example.geomobile',
    );
  }
}

