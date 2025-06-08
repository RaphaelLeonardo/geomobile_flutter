import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/geoserver_service.dart';
import '../models/layer.dart';
import '../widgets/wms_layer.dart';
import '../widgets/cached_wms_layer.dart';
import '../services/offline_cache_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<Layer> _layers = [];
  List<Layer> _activeLayers = [];
  List<Layer> _offlineLayers = [];
  bool _loading = false;
  String? _error;
  bool _isOnline = true;
  Map<String, bool> _downloadingLayers = {};
  Map<String, double> _downloadProgress = {};
  Function? _modalUpdateCallback;
  
  final GeoServerService _geoServerService = GeoServerService(
    baseUrl: 'http://186.237.132.58:15124/geoserver',
  );

  @override
  void initState() {
    super.initState();
    _loadLayers();
    _checkConnectivity();
    _loadOfflineLayers();
    
    // Verificar conectividade periodicamente
    _startConnectivityMonitoring();
  }

  void _startConnectivityMonitoring() {
    // Verifica conectividade a cada 5 segundos
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _checkConnectivity();
        _startConnectivityMonitoring();
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final wasOnline = _isOnline;
    final isOnline = await OfflineCacheService.isOnline();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
      
      // Se voltou a ficar online e não tinha camadas carregadas
      if (!wasOnline && isOnline && _layers.isEmpty) {
        _loadLayers();
      }
      
      // Se ficou offline, carrega camadas offline
      if (wasOnline && !isOnline) {
        _loadOfflineLayers();
      }
    }
  }

  Future<void> _loadOfflineLayers() async {
    final offlineLayers = <Layer>[];
    
    // Se não tem camadas online carregadas, criar camadas básicas dos caches existentes
    if (_layers.isEmpty && !_isOnline) {
      final db = await OfflineCacheService.database;
      final cachedLayerNames = await db.rawQuery(
        'SELECT DISTINCT layer_name FROM cached_tiles'
      );
      
      for (final row in cachedLayerNames) {
        final layerName = row['layer_name'] as String;
        final layer = Layer(
          name: layerName,
          title: layerName.split(':').last.replaceAll('_', ' '),
          workspace: layerName.split(':').first,
          url: 'http://186.237.132.58:15124/geoserver',
        );
        offlineLayers.add(layer);
      }
    } else {
      // Lógica normal: verificar quais das camadas online têm cache
      for (final layer in _layers) {
        final hasOfflineData = await OfflineCacheService.hasOfflineData(layer.name);
        if (hasOfflineData) {
          offlineLayers.add(layer);
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _offlineLayers = offlineLayers;
      });
    }
  }

  Future<void> _loadLayers() async {
    if (!_isOnline) {
      // Se offline, não tenta carregar do GeoServer
      setState(() {
        _loading = false;
        _error = null;
      });
      _loadOfflineLayers();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final layers = await _geoServerService.getCapabilities();
      setState(() {
        _layers = layers;
        _loading = false;
      });
      _loadOfflineLayers();
    } catch (e) {
      print('Erro detalhado: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }


  void _showLayersDrawer() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Conecta o callback para atualizações dinâmicas
          _modalUpdateCallback = () => setModalState(() {});
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isOnline ? 'Camadas Online' : 'Camadas Disponíveis Offline',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF084783)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0083e2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_activeLayers.length} ativas',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              
                // Content
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null && _isOnline)
                  Column(
                    children: [
                      Text('Erro: $_error'),
                      ElevatedButton(
                        onPressed: _loadLayers,
                        child: const Text('Tentar Novamente'),
                      ),
                    ],
                  )
                else if (!_isOnline && _offlineLayers.isEmpty)
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Sem conexão',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Nenhuma camada disponível offline.\nBaixe camadas quando estiver online.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _isOnline ? _layers.length : _offlineLayers.length,
                      itemBuilder: (context, index) {
                        final layer = _isOnline ? _layers[index] : _offlineLayers[index];
                        final isActive = _activeLayers.any((l) => l.name == layer.name);
                        final isDownloading = _downloadingLayers[layer.name] == true;
                        final progress = _downloadProgress[layer.name] ?? 0.0;
                      
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          child: ListTile(
                          title: Text(
                            layer.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isActive ? const Color(0xFF084783) : Colors.black87,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nome: ${layer.name}'),
                              Text('Workspace: ${layer.workspace}', 
                                style: const TextStyle(
                                  fontSize: 12, 
                                  color: Color(0xFF084783),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  if (isActive)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4, right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF084783),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'ATIVA',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (!_isOnline)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4, right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'OFFLINE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (_isOnline && isDownloading)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'BAIXANDO ${(progress * 100).toInt()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (_isOnline && isDownloading)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isOnline)
                                FutureBuilder<bool>(
                                  future: OfflineCacheService.hasOfflineData(layer.name),
                                  builder: (context, snapshot) {
                                    final hasCache = snapshot.data == true;
                                    return IconButton(
                                      onPressed: isDownloading ? null : () async {
                                        if (hasCache) {
                                          _clearLayerCache(layer);
                                        } else {
                                          _downloadLayer(layer);
                                        }
                                        setModalState(() {});
                                      },
                                      icon: Icon(
                                        hasCache ? Icons.delete : Icons.download,
                                        color: hasCache ? Colors.red : const Color(0xFF0083e2),
                                      ),
                                      tooltip: hasCache ? 'Limpar cache' : 'Baixar para offline',
                                    );
                                  },
                                ),
                              Switch(
                                value: isActive,
                                onChanged: _isOnline || (!_isOnline && _offlineLayers.contains(layer))
                                    ? (value) {
                                        _toggleLayer(layer);
                                        setModalState(() {});
                                      }
                                    : null,
                                activeColor: const Color(0xFF0083e2),
                                activeTrackColor: const Color(0xFF0083e2).withOpacity(0.3),
                              ),
                            ],
                          ),
                          onTap: () {
                            if (_isOnline || (!_isOnline && _offlineLayers.contains(layer))) {
                              _toggleLayer(layer);
                              setModalState(() {});
                            }
                          },
                        ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Limpa o callback quando o modal fechar
      _modalUpdateCallback = null;
    });
  }

  void _testLayerUrl(Layer layer) {
    // Coordenadas corretas para Jales/SP em EPSG:31982 (UTM)
    final testUrl = 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?'
        'service=WMS&'
        'version=1.1.0&'
        'request=GetMap&'
        'layers=${Uri.encodeComponent(layer.name)}&'
        'styles=&'
        'bbox=600000,7760000,620000,7780000&'  // Bbox em UTM para região de Jales
        'width=512&'
        'height=512&'
        'crs=EPSG%3A31982&'  // EPSG:31982 para Jales/SP
        'format=image%2Fjpeg&'  // JPEG mais compatível
        'transparent=false';
    
    print('URL de teste para ${layer.name}:');
    print(testUrl);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('URL de teste para ${layer.title} gerada no console'),
        backgroundColor: const Color(0xFF0083e2),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleLayer(Layer layer) {
    setState(() {
      final isActive = _activeLayers.any((l) => l.name == layer.name);
      if (isActive) {
        _activeLayers.removeWhere((l) => l.name == layer.name);
      } else {
        _activeLayers.add(layer);
      }
    });

    final isActive = _activeLayers.any((l) => l.name == layer.name);
    print('Camada ${isActive ? 'adicionada' : 'removida'}: ${layer.name}');
    print('Total de camadas ativas: ${_activeLayers.length}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camada ${layer.title} ${isActive ? 'ativada' : 'desativada'} (${_activeLayers.length} ativas)'),
        backgroundColor: isActive ? const Color(0xFF084783) : const Color(0xFF666666),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _downloadLayer(Layer layer) async {
    if (_downloadingLayers[layer.name] == true) return;

    setState(() {
      _downloadingLayers[layer.name] = true;
      _downloadProgress[layer.name] = 0.0;
    });

    try {
      await OfflineCacheService.downloadLayerTiles(
        layer,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _downloadProgress[layer.name] = current / total;
            });
            // Atualiza o modal se estiver aberto
            _modalUpdateCallback?.call();
          }
        },
      );

      if (mounted) {
        _loadOfflineLayers(); // Atualiza lista de camadas offline
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download da camada ${layer.title} concluído!'),
            backgroundColor: const Color(0xFF084783),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingLayers[layer.name] = false;
          _downloadProgress.remove(layer.name);
        });
        // Atualiza o modal se estiver aberto
        _modalUpdateCallback?.call();
      }
    }
  }

  Future<void> _clearLayerCache(Layer layer) async {
    await OfflineCacheService.clearCache(layer.name);
    if (mounted) {
      _loadOfflineLayers(); // Atualiza lista de camadas offline
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cache da camada ${layer.title} limpo!'),
          backgroundColor: const Color(0xFF666666),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeomobileApp'),
        backgroundColor: const Color(0xFF084783),
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isOnline ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isOnline ? Icons.wifi : Icons.wifi_off,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _isOnline ? 'Online' : 'Offline',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _showLayersDrawer,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadLayers();
              _checkConnectivity();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(-20.2667, -50.5500), // Jales/SP
              initialZoom: 12.0,
              minZoom: 10.0,
              maxZoom: 18.0,
            ),
            children: [
              // Só mostra OpenStreetMap quando online
              if (_isOnline)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.geomobile',
                )
              else
                // Fundo simples quando offline
                TileLayer(
                  urlTemplate: 'about:blank', // URL inválida para forçar fallback
                  backgroundColor: const Color(0xFFF0F0F0),
                  errorTileCallback: (tile, error, stackTrace) {
                    return Container(
                      width: 256,
                      height: 256,
                      color: const Color(0xFFF0F0F0),
                    );
                  },
                ),
              ..._activeLayers.map((layer) {
                print('Renderizando camada: ${layer.name} (${_isOnline ? 'online' : 'offline'})');
                if (_isOnline) {
                  return WMSLayerWidget(layer: layer);
                } else {
                  // Só renderiza se tem cache offline
                  if (_offlineLayers.any((l) => l.name == layer.name)) {
                    return CachedWMSLayerWidget(layer: layer);
                  } else {
                    return const SizedBox.shrink();
                  }
                }
              }),
            ],
          ),
          // Indicador de modo offline
          if (!_isOnline)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'MODO OFFLINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: "zoom_in",
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom + 1,
                    );
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF084783),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: "zoom_out",
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom - 1,
                    );
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF084783),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "layers",
            onPressed: _showLayersDrawer,
            backgroundColor: const Color(0xFF084783),
            child: const Icon(Icons.layers, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "location",
            onPressed: () {
              _mapController.move(
                const LatLng(-20.2667, -50.5500),
                12.0,
              );
            },
            backgroundColor: const Color(0xFF0083e2),
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}