import 'package:flutter/material.dart';
import '../models/layer.dart';
import '../services/offline_cache_service.dart';

class CachedWMSLayerWidget extends StatelessWidget {
  final Layer layer;

  const CachedWMSLayerWidget({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    print('Criando TileLayer Cached para: ${layer.name}');

    return OfflineCacheService.createTileLayerForOffline(layer.name);
  }
}

