# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter mobile application project named "geomobile" configured for cross-platform development (Android, iOS, Web, Windows, macOS, Linux).

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
- Core Flutter framework with Material Design
- `flutter_lints` for code quality enforcement
- Standard Flutter testing framework

### Code Quality
- Follows `flutter_lints` rules as defined in `analysis_options.yaml`
- Use `flutter analyze` to verify code compliance before commits