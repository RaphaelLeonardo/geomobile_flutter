# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GeomobileApp is a Flutter mobile application for geospatial data visualization with GeoServer integration. The app displays interactive maps with WMS layers from a specific GeoServer workspace (JalesC2245) centered on Jales/SP, Brazil.

### Key Features
- Interactive map visualization using flutter_map
- WMS layer integration with GeoServer
- Real-time layer toggle (on/off) functionality
- OpenStreetMap as base map service
- Layer management modal with status indicators

## Development Commands

### Running the Application
- `flutter run` - Run the app on connected device/emulator
- `flutter run -d chrome` - Run on web browser
- `flutter run -d windows` - Run on Windows desktop
- `flutter run --hot-reload` - Run with hot reload enabled

### Building
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build iOS app (requires macOS)
- `flutter build web` - Build web application
- `flutter build windows` - Build Windows executable

### Testing and Quality
- `flutter test` - Run all unit tests
- `flutter analyze` - Run static analysis with flutter_lints rules
- `flutter doctor` - Check Flutter installation and dependencies

### Package Management
- `flutter pub get` - Install dependencies from pubspec.yaml
- `flutter pub upgrade` - Upgrade dependencies to latest versions
- `flutter clean` - Clean build artifacts

## Architecture

### Project Structure
- `lib/main.dart` - Application entry point with basic MaterialApp setup
- Platform-specific configurations in `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` directories
- Uses Material Design components (`uses-material-design: true`)

### Dependencies
- `flutter_map: ^7.0.2` - Native Flutter mapping library (no WebView/JavaScript)
- `latlong2: ^0.9.1` - Coordinate manipulation
- `http: ^1.1.0` - HTTP requests for GeoServer
- `xml: ^6.3.0` - XML parsing for WMS GetCapabilities
- `proj4dart: ^2.1.0` - Coordinate projection transformations
- `flutter_lints` for code quality enforcement

### Mapping Technology
- **flutter_map**: Flutter-native mapping solution
  - Dart/Flutter native (no WebView or JavaScript)
  - API inspired by Leaflet
  - Widget-based rendering
  - Native WMS/TMS support
- **OpenStreetMap**: Free, open-source base map tiles
- **Web Mercator (EPSG:3857)**: Standard projection for web mapping

### GeoServer Integration
- **Base URL**: `http://186.237.132.58:15124/geoserver`
- **Authentication**: HTTP Basic Auth (peça ao usuário essa informaçao)
- **Workspace**: JalesC2245
- **Protocol**: WMS (Web Map Service)
- **Coordinates**: Jales/SP, Brazil (-20.2667, -50.5500)

### Code Quality
- Follows `flutter_lints` rules as defined in `analysis_options.yaml`
- Use `flutter analyze` to verify code compliance before commits