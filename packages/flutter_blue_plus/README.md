# Flutter Blue Plus for Wireless Radio

The `flutter_blue_plus` package provides a Flutter Blue Plus implementation of the communication interface required by the Wireless Radio SDK. It enables Flutter applications to use Bluetooth Low Energy for communicating with Glamox Wireless Radio systems.

## Overview

This package:
- Implements the `CommunicationInterface` using Flutter Blue Plus
- Provides Flutter-specific BLE functionality for mobile platforms (iOS and Android)
- Handles platform-specific BLE quirks and differences
- Manages permissions and Bluetooth state monitoring
- Provides a seamless BLE experience for Flutter applications

## Installation

Add the following to your `pubspec.yaml` file:

```yaml
dependencies:
  flutter_blue_plus_wr:
    git:
      url: [repository URL]
      path: packages/flutter_blue_plus
  wireless_radio_dart_sdk:
    git:
      url: [repository URL]
      path: packages/sdk
```

## Platform Support

This package supports:
- iOS 10.0+
- Android 4.4+
- macOS 10.13+

## Usage

```dart
import 'package:flutter_blue_plus_wr/flutter_blue_plus_wr.dart';
import 'package:wireless_radio_dart_sdk/wireless_radio_dart_sdk.dart';

void main() async {
  // Create the Flutter Blue Plus communication client
  FlutterBluePlusCommunicationClient bleClient = FlutterBluePlusCommunicationClient();
  
  // Initialize the Wireless Radio client
  WirelessClient wirelessClient = WirelessClient(bleClient);
  
  // Check Bluetooth state
  bool isBluetoothOn = await bleClient.isBluetoothEnabled();
  if (!isBluetoothOn) {
    // Request user to turn on Bluetooth
    await bleClient.requestBluetoothEnable();
  }
  
  // Request necessary permissions
  await bleClient.requestPermissions();
  
  // Start scanning for devices
  await bleClient.startScan();
  
  // Listen for discovered devices
  bleClient.deviceStream.listen((device) {
    print('Found device: ${device.name} (${device.id})');
  });
  
  // Connect to a specific device
  await bleClient.connect('device_id');
  
  // Use the wireless client with the connected BLE device
  GetVersionRequest request = GetVersionRequest();
  VersionResponse response = await wirelessClient.send(request);
}
```

## Features

### Bluetooth State Management

```dart
// Get the current Bluetooth state
BluetoothState state = await bleClient.getBluetoothState();

// Listen for Bluetooth state changes
bleClient.bluetoothStateStream.listen((state) {
  if (state == BluetoothState.on) {
    print('Bluetooth is on');
  } else {
    print('Bluetooth is off or unavailable');
  }
});
```

### Permission Handling

The package automatically handles the necessary permissions for BLE:

```dart
// Request all necessary permissions
bool permissionsGranted = await bleClient.requestPermissions();

// Check if all permissions are granted
bool hasPermissions = await bleClient.hasPermissions();
```

### Device Discovery

```dart
// Start scanning with options
await bleClient.startScan(
  timeout: Duration(seconds: 10),
  withServices: ['service_uuid'],
  scanMode: ScanMode.lowLatency,
);

// Stop scanning
await bleClient.stopScan();
```

### Connection Management

```dart
// Connect with options
await bleClient.connect(
  'device_id',
  autoConnect: true,
  timeout: Duration(seconds: 5),
);

// Disconnect
await bleClient.disconnect('device_id');

// Check connection status
bool isConnected = await bleClient.isConnected('device_id');

// Listen for connection state changes
bleClient.connectionStateStream.listen((state) {
  print('Connection state changed: $state');
});
```

## Configuration

You can configure the BLE client behavior:

```dart
bleClient.configure(
  scanTimeout: Duration(seconds: 10),
  connectionTimeout: Duration(seconds: 5),
  mtu: 512,
  autoConnect: true,
);
```

## Integration with Flutter Apps

### Adding to your Flutter App

1. Add dependencies to `pubspec.yaml`
2. Setup platform-specific configurations
3. Initialize the BLE client
4. Implement UI for Bluetooth state monitoring

### Platform-Specific Setup

#### iOS

Add to `Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Need BLE permission to connect to wireless devices</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Need BLE permission to connect to wireless devices</string>
```

#### Android

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

## Troubleshooting

- **Scan not working**: Check location permission on Android
- **Connection issues**: Ensure device is in range and advertising
- **iOS connection failures**: Verify Info.plist has the proper usage descriptions
- **Android compatibility**: For Android 12+, ensure you have BLUETOOTH_SCAN and BLUETOOTH_CONNECT permissions
