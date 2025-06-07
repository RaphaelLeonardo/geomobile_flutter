import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/geoserver_service.dart';
import '../models/layer.dart';

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
              'Camadas Disponíveis',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                      subtitle: Text(layer.name),
                      trailing: const Icon(Icons.add),
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

  void _addLayerToMap(Layer layer) {
    setState(() {
      _activeLayers.add(layer);
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Camada ${layer.title} adicionada')),
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
              initialCenter: LatLng(-15.7942, -47.8822), // Brasília
              initialZoom: 10.0,
              minZoom: 3.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geomobile',
              ),
              ..._activeLayers.map((layer) => TileLayer(
                urlTemplate: '${layer.url}/wms?'
                    'service=WMS&'
                    'version=1.1.0&'
                    'request=GetMap&'
                    'layers=${layer.name}&'
                    'styles=&'
                    'bbox={west},{south},{east},{north}&'
                    'width={width}&'
                    'height={height}&'
                    'srs=EPSG:4326&'
                    'format=image/png&'
                    'transparent=true',
              )),
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
                const LatLng(-15.7942, -47.8822),
                10.0,
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