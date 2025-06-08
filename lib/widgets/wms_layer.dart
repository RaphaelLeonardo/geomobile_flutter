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
      wmsOptions: WMSTileLayerOptions(
        baseUrl: 'http://admin:geodados@186.237.132.58:15124/geoserver/wms?',
        layers: [widget.layer.name],
      ),
      tileSize: 256,
    );
  }
}