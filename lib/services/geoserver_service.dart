import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/layer.dart';

class GeoServerService {
  final String baseUrl;
  final String username;
  final String password;

  GeoServerService({
    required this.baseUrl,
    this.username = 'admin',
    this.password = 'geodados',
  });

  String get _basicAuth {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  Future<List<Layer>> getCapabilities() async {
    try {
      final url = '$baseUrl/wms?service=WMS&version=1.1.0&request=GetCapabilities';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': _basicAuth,
        },
      );

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final layers = <Layer>[];

        // Busca por todas as camadas (Layer) que possuem um elemento Name
        final layerElements = document.findAllElements('Layer');
        
        for (final layerElement in layerElements) {
          final nameElements = layerElement.findElements('Name');
          if (nameElements.isNotEmpty) {
            try {
              final layer = Layer.fromXml(layerElement, baseUrl);
              // Filtrar apenas camadas do workspace JalesC2245
              if (layer.name.startsWith('JalesC2245:') || layer.workspace == 'JalesC2245') {
                layers.add(layer);
              }
            } catch (e) {
              print('Erro ao processar camada: $e');
              continue;
            }
          }
        }

        return layers;
      } else {
        throw Exception('Falha ao carregar capabilities: ${response.statusCode}');
      }
    } catch (e) {
      print('Erro detalhado: $e');
      throw Exception('Erro ao conectar com GeoServer: $e');
    }
  }

  String getWmsUrl(String layerName, {
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
    required int width,
    required int height,
    String srs = 'EPSG:4326',
  }) {
    final credentials = Uri.encodeComponent('$username:$password');
    final baseUrlWithAuth = baseUrl.replaceFirst('http://', 'http://$credentials@');
    
    return '$baseUrlWithAuth/wms?'
        'service=WMS&'
        'version=1.1.0&'
        'request=GetMap&'
        'layers=$layerName&'
        'styles=&'
        'bbox=$minX,$minY,$maxX,$maxY&'
        'width=$width&'
        'height=$height&'
        'srs=$srs&'
        'format=image/png&'
        'transparent=true';
  }
}