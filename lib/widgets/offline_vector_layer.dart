import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/layer.dart';
import '../services/offline_vector_service.dart';

class OfflineVectorLayerWidget extends StatefulWidget {
  final Layer layer;
  final MapController? mapController; // Para viewport culling

  const OfflineVectorLayerWidget({super.key, required this.layer, this.mapController});

  @override
  State<OfflineVectorLayerWidget> createState() => _OfflineVectorLayerWidgetState();
}

class _OfflineVectorLayerWidgetState extends State<OfflineVectorLayerWidget> {
  List<Polygon> _polygons = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  bool _loading = true;
  String? _error;
  
  // Cache de coordenadas convertidas para evitar reprocessamento
  final Map<String, LatLng> _coordinateCache = {};
  
  // Bounds calculados das features
  double? _minLat, _maxLat, _minLng, _maxLng;
  
  // Flag para log único da conversão
  bool _firstConversionLog = true;
  
  // Debug counter para polígonos
  int _debugPolygonCount = 0;
  
  // RENDERIZAÇÃO SIMPLES - deixar flutter_map otimizar nativamente
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
                    // Log apenas do primeiro polígono para confirmar funcionamento
                    if (polygons.length == 1) {
                      print('✅ Primeiro polígono criado com ${polygon.points.length} pontos');
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
            // RENDERIZAR TUDO DE UMA VEZ - deixar flutter_map otimizar
            _polygons = polygons;
            _polylines = polylines;
            _markers = markers;
            _loading = false;
            _featuresRendered = polygons.length + polylines.length + markers.length;
          });
          
          print('✅ CAMADA OFFLINE CARREGADA: ${polygons.length} polígonos, ${polylines.length} linhas, ${markers.length} pontos');
          print('📊 Cache de coordenadas: ${_coordinateCache.length} pontos únicos convertidos');
          
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
            
            // Primeira coordenada apenas para debug inicial
            
            // Verificar se coordenadas estão em metros (UTM) ou graus
            if (x.abs() > 180 || y.abs() > 90) {
              // Coordenadas em metros - converter de UTM para lat/lng
              final latLng = _convertFromUTM(x, y);
              if (latLng != null) {
                points.add(latLng);
                _updateBounds(latLng.latitude, latLng.longitude);
              }
            } else {
              // Coordenadas já em graus decimais
              final latLng = LatLng(y, x); // Note: y=lat, x=lng
              points.add(latLng);
              _updateBounds(latLng.latitude, latLng.longitude);
            }
          }
        }
        
        if (points.length >= 3) {
          // Debug limitado apenas para verificação inicial
          if (_debugPolygonCount < 1) {
            print('✅ Primeira conversão completa: ${points.length} pontos processados');
            _debugPolygonCount++;
          }
          
          // SEM FILTRO DE ÁREA - aceitar TODOS os polígonos
          
          return Polygon(
            points: points,
            color: _getPolygonColor(properties).withOpacity(0.4),
            borderColor: _getPolygonBorderColor(properties),
            borderStrokeWidth: 1.0, // Borda reduzida para performance (era 2.0)
            // Sem outras propriedades de borda para máxima performance
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

  // Conversão CACHED de UTM para Lat/Lng - executa apenas uma vez por coordenada
  LatLng? _convertFromUTM(double x, double y) {
    // Criar chave única para cache
    final String cacheKey = '${x.toStringAsFixed(2)}_${y.toStringAsFixed(2)}';
    
    // Verificar se já foi convertida
    if (_coordinateCache.containsKey(cacheKey)) {
      return _coordinateCache[cacheKey]!;
    }
    
    try {
      // Conversão otimizada para região de Jales/SP
      const double refEasting = 610000.0;
      const double refNorthing = 7760000.0; 
      const double refLat = -20.2667;
      const double refLng = -50.5500;
      
      final double deltaEasting = x - refEasting;
      final double deltaNorthing = y - refNorthing;
      
      final double lat = refLat + (deltaNorthing / 111000.0);
      final double lngDegreeDistance = 111000.0 * math.cos(refLat * math.pi / 180.0);
      final double lng = refLng + (deltaEasting / lngDegreeDistance);
      
      // Debug apenas da primeira conversão
      if (_firstConversionLog) {
        print('🗺️ Conversão UTM CACHED: x=$x, y=$y → lat=$lat, lng=$lng');
        _firstConversionLog = false;
      }
      
      final LatLng result = LatLng(lat, lng);
      
      // Armazenar no cache para próximas utilizações
      _coordinateCache[cacheKey] = result;
      
      return result;
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

    // Print removido para evitar piscar - log apenas no initState/setState

    // RENDERIZAÇÃO OTIMIZADA - flutter_map nativo com todas as features
    return Stack(
      children: [
        if (_polygons.isNotEmpty)
          PolygonLayer(
            polygons: _polygons,
            // ✅ MÁXIMA PERFORMANCE para grandes datasets:
            useAltRendering: true, // Triangulação otimizada para 25k+ polígonos
            simplificationTolerance: 1.5, // Simplificação mais agressiva para performance
            polygonCulling: true, // Culling automático de polígonos fora da tela
          ),
        if (_polylines.isNotEmpty)
          PolylineLayer(
            polylines: _polylines,
            simplificationTolerance: 1.2,
          ),
        if (_markers.isNotEmpty)
          MarkerLayer(markers: _markers),
      ],
    );
  }
}