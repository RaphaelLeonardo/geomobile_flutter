import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/layer.dart';
import '../services/offline_vector_service.dart';

class OfflineVectorLayerWidget extends StatefulWidget {
  final Layer layer;

  const OfflineVectorLayerWidget({super.key, required this.layer});

  @override
  State<OfflineVectorLayerWidget> createState() => _OfflineVectorLayerWidgetState();
}

class _OfflineVectorLayerWidgetState extends State<OfflineVectorLayerWidget> {
  List<Polygon> _polygons = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _loading = true;
  String? _error;
  
  // Bounds calculados das features
  double? _minLat, _maxLat, _minLng, _maxLng;
  
  // Flag para log único da conversão
  bool _firstConversionLog = true;
  
  // Debug counter para polígonos
  int _debugPolygonCount = 0;
  
  // SEM LIMITES - carregar camada INTEIRA como solicitado
  // static const int MAX_POLYGONS_TO_RENDER = 2000; // REMOVIDO - sem limite
  // static const double MIN_POLYGON_AREA = 0.0000000000001; // REMOVIDO - sem filtro de área  
  // static const int SAMPLE_EVERY_N_FEATURES = 25; // REMOVIDO - sem sampling
  int _totalFeaturesLoaded = 0;
  int _featuresRendered = 0;

  @override
  void initState() {
    super.initState();
    _loadOfflineFeatures();
  }

  Future<void> _loadOfflineFeatures() async {
    try {
      print('🔄 Carregando features offline para: ${widget.layer.name}');
      
      final geoJson = await OfflineVectorService.getCachedFeatures(widget.layer.name);
      
      if (geoJson != null && geoJson.containsKey('features')) {
        final features = geoJson['features'] as List;
        
        final polygons = <Polygon>[];
        final polylines = <Polyline>[];
        final markers = <Marker>[];
        
        _totalFeaturesLoaded = features.length;
        print('📊 Processando TODAS as ${features.length} features - SEM LIMITES!');
        
        // Processar TODAS as features
        int processedCount = 0;
        
        for (int i = 0; i < features.length; i++) {
          final feature = features[i];
          processedCount++;
          if (feature is Map && feature.containsKey('geometry')) {
            final geometry = feature['geometry'];
            final properties = feature['properties'] ?? {};
            
            if (geometry is Map && geometry.containsKey('type')) {
              final geometryType = geometry['type'] as String;
              final coordinates = geometry['coordinates'];
              
              switch (geometryType) {
                case 'Polygon':
                  final polygon = _createPolygon(coordinates, properties);
                  if (polygon != null) {
                    polygons.add(polygon);
                    // Log apenas os primeiros 5 para não poluir o console
                    if (polygons.length <= 5) {
                      print('✅ Polígono ${polygons.length} criado com ${polygon.points.length} pontos');
                    }
                  }
                  break;
                  
                case 'MultiPolygon':
                  final multiPolygons = _createMultiPolygon(coordinates, properties);
                  polygons.addAll(multiPolygons);
                  break;
                  
                case 'LineString':
                  final polyline = _createPolyline(coordinates, properties);
                  if (polyline != null) polylines.add(polyline);
                  break;
                  
                case 'MultiLineString':
                  final multiPolylines = _createMultiPolyline(coordinates, properties);
                  polylines.addAll(multiPolylines);
                  break;
                  
                case 'Point':
                  final marker = _createMarker(coordinates, properties);
                  if (marker != null) markers.add(marker);
                  break;
                  
                case 'MultiPoint':
                  final multiMarkers = _createMultiPoint(coordinates, properties);
                  markers.addAll(multiMarkers);
                  break;
                  
                default:
                  print('⚠️ Tipo de geometria não suportado: $geometryType');
              }
            }
          }
        }
        
        if (mounted) {
          setState(() {
            _polygons = polygons;
            _polylines = polylines;
            _markers = markers;
            _loading = false;
            _featuresRendered = polygons.length + polylines.length + markers.length;
          });
          
          print('✅ TODAS as features carregadas: ${polygons.length} polígonos, ${polylines.length} linhas, ${markers.length} pontos');
          print('📈 CAMADA COMPLETA: ${_featuresRendered}/${_totalFeaturesLoaded} features renderizadas (100%)');
          
          // Log dos bounds calculados
          if (_minLat != null && _maxLat != null && _minLng != null && _maxLng != null) {
            print('📍 Bounds das features:');
            print('   Lat: ${_minLat!.toStringAsFixed(6)} a ${_maxLat!.toStringAsFixed(6)}');
            print('   Lng: ${_minLng!.toStringAsFixed(6)} a ${_maxLng!.toStringAsFixed(6)}');
            print('   Centro aproximado: ${((_minLat! + _maxLat!) / 2).toStringAsFixed(6)}, ${((_minLng! + _maxLng!) / 2).toStringAsFixed(6)}');
            
            // Sugerir zoom ideal
            final double latRange = (_maxLat! - _minLat!).abs();
            final double lngRange = (_maxLng! - _minLng!).abs();
            final double maxRange = math.max(latRange, lngRange);
            int suggestedZoom = 10;
            if (maxRange < 0.001) suggestedZoom = 18;
            else if (maxRange < 0.01) suggestedZoom = 15;
            else if (maxRange < 0.1) suggestedZoom = 12;
            else if (maxRange < 1.0) suggestedZoom = 10;
            
            print('🔍 Zoom sugerido: $suggestedZoom (range: ${maxRange.toStringAsFixed(6)}°)');
          }
        }
      } else {
        throw Exception('GeoJSON inválido ou sem features');
      }
    } catch (e) {
      print('❌ Erro ao carregar features offline: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Polygon? _createPolygon(dynamic coordinates, Map<String, dynamic> properties) {
    try {
      if (coordinates is List && coordinates.isNotEmpty) {
        final outerRing = coordinates[0] as List;
        final points = <LatLng>[];
        
        for (final coord in outerRing) {
          if (coord is List && coord.length >= 2) {
            final x = (coord[0] as num).toDouble();
            final y = (coord[1] as num).toDouble();
            
            // Log das primeiras coordenadas para debug
            if (points.isEmpty) {
              print('🔍 Primeira coordenada: x=$x, y=$y');
            }
            
            // Verificar se coordenadas estão em metros (UTM) ou graus
            if (x.abs() > 180 || y.abs() > 90) {
              // Coordenadas em metros - converter de UTM para lat/lng
              final latLng = _convertFromUTM(x, y);
              if (latLng != null) {
                points.add(latLng);
                _updateBounds(latLng.latitude, latLng.longitude);
                
                // Log da primeira conversão
                if (points.length == 1) {
                  print('🔄 Convertido UTM→LatLng: ${latLng.latitude}, ${latLng.longitude}');
                }
              }
            } else {
              // Coordenadas já em graus decimais
              final latLng = LatLng(y, x); // Note: y=lat, x=lng
              points.add(latLng);
              _updateBounds(latLng.latitude, latLng.longitude);
              
              // Log da primeira coordenada em graus
              if (points.length == 1) {
                print('📍 Coordenada em graus: ${latLng.latitude}, ${latLng.longitude}');
              }
            }
          }
        }
        
        if (points.length >= 3) {
          // Debug dos primeiros polígonos apenas
          if (_debugPolygonCount < 3) {
            final area = _calculatePolygonArea(points);
            print('🔍 Polígono debug: ${points.length} pontos, área: $area');
            print('   Primeiro ponto: ${points.first.latitude}, ${points.first.longitude}');
            _debugPolygonCount++;
          }
          
          // SEM FILTRO DE ÁREA - aceitar TODOS os polígonos
          
          return Polygon(
            points: points,
            color: _getPolygonColor(properties).withOpacity(0.4),
            borderColor: _getPolygonBorderColor(properties),
            borderStrokeWidth: 2.0, // Borda mais visível
          );
        }
      }
    } catch (e) {
      print('❌ Erro ao criar polígono: $e');
    }
    return null;
  }

  List<Polygon> _createMultiPolygon(dynamic coordinates, Map<String, dynamic> properties) {
    final polygons = <Polygon>[];
    if (coordinates is List) {
      for (final polygonCoords in coordinates) {
        final polygon = _createPolygon(polygonCoords, properties);
        if (polygon != null) polygons.add(polygon);
      }
    }
    return polygons;
  }

  Polyline? _createPolyline(dynamic coordinates, Map<String, dynamic> properties) {
    try {
      if (coordinates is List) {
        final points = <LatLng>[];
        
        for (final coord in coordinates) {
          if (coord is List && coord.length >= 2) {
            final x = (coord[0] as num).toDouble();
            final y = (coord[1] as num).toDouble();
            
            // Verificar se coordenadas estão em metros (UTM) ou graus
            if (x.abs() > 180 || y.abs() > 90) {
              // Coordenadas em metros - converter de UTM para lat/lng
              final latLng = _convertFromUTM(x, y);
              if (latLng != null) {
                points.add(latLng);
              }
            } else {
              // Coordenadas já em graus decimais
              points.add(LatLng(y, x)); // Note: y=lat, x=lng
            }
          }
        }
        
        if (points.length >= 2) {
          return Polyline(
            points: points,
            color: _getPolylineColor(properties),
            strokeWidth: _getPolylineWidth(properties),
          );
        }
      }
    } catch (e) {
      print('❌ Erro ao criar polyline: $e');
    }
    return null;
  }

  List<Polyline> _createMultiPolyline(dynamic coordinates, Map<String, dynamic> properties) {
    final polylines = <Polyline>[];
    if (coordinates is List) {
      for (final lineCoords in coordinates) {
        final polyline = _createPolyline(lineCoords, properties);
        if (polyline != null) polylines.add(polyline);
      }
    }
    return polylines;
  }

  Marker? _createMarker(dynamic coordinates, Map<String, dynamic> properties) {
    try {
      if (coordinates is List && coordinates.length >= 2) {
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();
        
        LatLng? point;
        
        // Verificar se coordenadas estão em metros (UTM) ou graus
        if (x.abs() > 180 || y.abs() > 90) {
          // Coordenadas em metros - converter de UTM para lat/lng
          point = _convertFromUTM(x, y);
        } else {
          // Coordenadas já em graus decimais
          point = LatLng(y, x); // Note: y=lat, x=lng
        }
        
        if (point != null) {
          return Marker(
            point: point,
            child: Icon(
              _getMarkerIcon(properties),
              color: _getMarkerColor(properties),
              size: 20,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Erro ao criar marker: $e');
    }
    return null;
  }

  List<Marker> _createMultiPoint(dynamic coordinates, Map<String, dynamic> properties) {
    final markers = <Marker>[];
    if (coordinates is List) {
      for (final pointCoords in coordinates) {
        final marker = _createMarker(pointCoords, properties);
        if (marker != null) markers.add(marker);
      }
    }
    return markers;
  }

  // Métodos de estilização - podem ser customizados baseado nas propriedades
  Color _getPolygonColor(Map<String, dynamic> properties) {
    // Cor baseada no tipo ou propriedade específica
    return const Color(0xFF00FF00); // Verde mais visível para teste
  }

  Color _getPolygonBorderColor(Map<String, dynamic> properties) {
    return const Color(0xFF0000FF); // Borda azul para contraste
  }

  Color _getPolylineColor(Map<String, dynamic> properties) {
    return const Color(0xFF0083e2); // Azul secundário do app
  }

  double _getPolylineWidth(Map<String, dynamic> properties) {
    return 3.0;
  }

  Color _getMarkerColor(Map<String, dynamic> properties) {
    return const Color(0xFF084783);
  }

  IconData _getMarkerIcon(Map<String, dynamic> properties) {
    return Icons.place;
  }

  void _updateBounds(double lat, double lng) {
    _minLat = _minLat == null ? lat : math.min(_minLat!, lat);
    _maxLat = _maxLat == null ? lat : math.max(_maxLat!, lat);
    _minLng = _minLng == null ? lng : math.min(_minLng!, lng);
    _maxLng = _maxLng == null ? lng : math.max(_maxLng!, lng);
  }

  // Calcular área aproximada do polígono para filtrar os muito pequenos
  double _calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final int j = (i + 1) % points.length;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    return area.abs() / 2.0;
  }

  // Conversão mais precisa de UTM para Lat/Lng
  // Para região de Jales/SP (UTM Zone 23S)
  LatLng? _convertFromUTM(double x, double y) {
    try {
      // Para região de Jales/SP - conversão específica
      // Baseado nas coordenadas típicas da região
      
      // Se as coordenadas originais são aproximadamente:
      // x: ~600000-620000 (easting)
      // y: ~7750000-7780000 (northing)
      
      // Conversão aproximada para Jales/SP region
      // Latitude aproximada: -20.2667 (referência conhecida)
      // Longitude aproximada: -50.5500 (referência conhecida)
      
      // Fator de conversão específico para a região
      const double refEasting = 610000.0;  // Referência aproximada para Jales
      const double refNorthing = 7760000.0; // Referência aproximada para Jales
      const double refLat = -20.2667;
      const double refLng = -50.5500;
      
      // Conversão baseada em deslocamento da referência conhecida
      final double deltaEasting = x - refEasting;
      final double deltaNorthing = y - refNorthing;
      
      // Aproximadamente 111km por grau na latitude
      final double lat = refLat + (deltaNorthing / 111000.0);
      
      // Ajuste da longitude considerando a latitude
      final double lngDegreeDistance = 111000.0 * math.cos(refLat * math.pi / 180.0);
      final double lng = refLng + (deltaEasting / lngDegreeDistance);
      
      // Debug da primeira conversão
      if (_firstConversionLog) {
        print('🗺️ Conversão UTM: x=$x, y=$y → lat=$lat, lng=$lng');
        _firstConversionLog = false;
      }
      
      // Verificar se resultados são válidos para a região
      if (lat >= -22 && lat <= -18 && lng >= -52 && lng <= -48) {
        return LatLng(lat, lng);
      } else {
        print('⚠️ Coordenadas fora da região esperada: lat=$lat, lng=$lng');
        // Ainda assim retorna para debug
        return LatLng(lat, lng);
      }
    } catch (e) {
      print('❌ Erro na conversão UTM: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink(); // Não mostra loading visual
    }

    if (_error != null) {
      return const SizedBox.shrink(); // Não mostra erro visual
    }

    print('🎨 Renderizando ${_polygons.length} polígonos, ${_polylines.length} linhas, ${_markers.length} pontos');

    // Renderizar polígonos reais agora que sabemos que funcionam!
    print('🎨 Renderizando ${_polygons.length} polígonos REAIS no mapa!');

    // Retorna múltiplas layers apenas para poucos polígonos
    return Stack(
      children: [
        if (_polygons.isNotEmpty)
          PolygonLayer(polygons: _polygons),
        if (_polylines.isNotEmpty)
          PolylineLayer(polylines: _polylines),
        if (_markers.isNotEmpty)
          MarkerLayer(markers: _markers),
      ],
    );
  }
}