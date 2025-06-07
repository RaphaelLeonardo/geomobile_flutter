import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/layer.dart';

class GeoServerService {
  final String baseUrl;

  GeoServerService({required this.baseUrl});

  Future<List<Layer>> getCapabilities() async {
    try {
      final url = '$baseUrl/wms?service=WMS&version=1.1.0&request=GetCapabilities';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final layers = <Layer>[];

        final layerElements = document.findAllElements('Layer').where(
          (element) => element.findElements('Name').isNotEmpty,
        );

        for (final layerElement in layerElements) {
          layers.add(Layer.fromXml(layerElement, baseUrl));
        }

        return layers;
      } else {
        throw Exception('Falha ao carregar capabilities: ${response.statusCode}');
      }
    } catch (e) {
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
    return '$baseUrl/wms?'
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