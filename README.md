# GeomobileApp

Uma aplicação Flutter para visualização de dados geoespaciais com integração ao GeoServer.

## Visão Geral

O GeomobileApp é um aplicativo móvel desenvolvido em Flutter para visualizar camadas geoespaciais do GeoServer em mapas interativos. O aplicativo permite ativar/desativar camadas WMS, navegar pelo mapa e gerenciar múltiplas camadas simultaneamente.

## Tecnologias

### Mapeamento
- **flutter_map**: Biblioteca Flutter nativa para renderização de mapas
  - Flutter/Dart nativo (sem WebView ou JavaScript)
  - API inspirada no Leaflet
  - Renderização via widgets Flutter
  - Suporte nativo a WMS/TMS
- **OpenStreetMap**: Serviço de mapa base gratuito e open source
- **Projeção**: Web Mercator (EPSG:3857)

### Integração GeoServer
- **WMS (Web Map Service)**: Protocolo para servir mapas georreferenciados
- **Workspace**: JalesC2245
- **Formato**: PNG com transparência
- **Autenticação**: HTTP Basic Auth

### Dependências
- `flutter_map: ^7.0.2` - Renderização de mapas
- `latlong2: ^0.9.1` - Manipulação de coordenadas
- `http: ^1.1.0` - Requisições HTTP
- `xml: ^6.3.0` - Parser XML para GetCapabilities
- `proj4dart: ^2.1.0` - Transformações de projeção

## Funcionalidades

- ✅ Visualização de mapa interativo (OpenStreetMap)
- ✅ Integração com GeoServer via WMS
- ✅ Carregamento dinâmico de camadas do workspace
- ✅ Toggle on/off para camadas ativas
- ✅ Interface responsiva com modal de camadas
- ✅ Detecção automática de camadas com problemas
- ✅ Zoom e navegação no mapa
- ✅ Sobreposição transparente de camadas WMS

## Configuração

### GeoServer
- **URL**: `http://186.237.132.58:15124/geoserver`
- **Workspace**: `JalesC2245`

### Coordenadas
- **Centro**: Jales/SP (-20.2667, -50.5500)
- **Zoom inicial**: 12
- **Projeção**: EPSG:3857 (Web Mercator)
