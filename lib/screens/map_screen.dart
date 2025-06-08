import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/geoserver_service.dart';
import '../models/layer.dart';
import '../widgets/wms_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<Layer> _layers = [];
  List<Layer> _activeLayers = [];
  bool _loading = false;
  String? _error;
  
  final GeoServerService _geoServerService = GeoServerService(
    baseUrl: 'http://186.237.132.58:15124/geoserver',
  );

  @override
  void initState() {
    super.initState();
    _loadLayers();
  }

  Future<void> _loadLayers() async {
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
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }


  void _showLayersDrawer() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Camadas - Workspace JalesC2245',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF084783)),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Column(
                children: [
                  Text('Erro: $_error'),
                  ElevatedButton(
                    onPressed: _loadLayers,
                    child: const Text('Tentar Novamente'),
                  ),
                ],
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _layers.length,
                  itemBuilder: (context, index) {
                    final layer = _layers[index];
                    return ListTile(
                      title: Text(layer.title),
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
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.info, color: Color(0xFF084783)),
                            onPressed: () => _testLayerUrl(layer),
                          ),
                          const Icon(Icons.add, color: Color(0xFF0083e2)),
                        ],
                      ),
                      onTap: () => _addLayerToMap(layer),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
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

  void _addLayerToMap(Layer layer) {
    setState(() {
      _activeLayers.add(layer);
    });

    print('Camada adicionada: ${layer.name}');
    print('Total de camadas ativas: ${_activeLayers.length}');

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camada ${layer.title} adicionada (${_activeLayers.length} ativas)'),
        backgroundColor: const Color(0xFF084783),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeomobileApp'),
        backgroundColor: const Color(0xFF084783),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _showLayersDrawer,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLayers,
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
              minZoom: 3.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geomobile',
              ),
              ..._activeLayers.map((layer) {
                print('Renderizando camada: ${layer.name}');
                return WMSLayerWidget(layer: layer);
              }),
            ],
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