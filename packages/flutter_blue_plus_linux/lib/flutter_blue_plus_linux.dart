import 'dart:async';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

import 'raspberry_pi_improvements.dart';

final class FlutterBluePlusLinux extends FlutterBluePlusPlatform {
  final _client = BlueZClient();

  var _initialized = false;
  var _logLevel = LogLevel.none;

  final _onCharacteristicReadController =
      StreamController<BmCharacteristicData>.broadcast();
  final _onCharacteristicWrittenController =
      StreamController<BmCharacteristicData>.broadcast();
  final _onDescriptorReadController =
      StreamController<BmDescriptorData>.broadcast();
  final _onDescriptorWrittenController =
      StreamController<BmDescriptorData>.broadcast();
  final _onDiscoveredServicesController =
      StreamController<BmDiscoverServicesResult>.broadcast();
  final _onReadRssiController = StreamController<BmReadRssiResult>.broadcast();
  final _onTurnOnResponseController =
      StreamController<BmTurnOnResponse>.broadcast();

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged {
    return _client.adaptersChanged.where(
      (adapters) {
        return adapters.length > 0;
      },
    ).switchMap(
      (adapters) {
        return adapters.first.propertiesChanged.where(
          (properties) {
            return properties.contains('Powered');
          },
        ).map(
          (properties) {
            return BmBluetoothAdapterState(
              adapterState: adapters.first.powered
                  ? BmAdapterStateEnum.on
                  : BmAdapterStateEnum.off,
            );
          },
        );
      },
    );
  }

  @override
  Stream<BmBondStateResponse> get onBondStateChanged {
    return _client.devicesChanged.switchMap(
      (devices) {
        return MergeStream(
          devices.map(
            (device) {
              return device.propertiesChanged.where(
                (properties) {
                  return properties.contains('Paired');
                },
              ).map(
                (properties) {
                  return BmBondStateResponse(
                    remoteId: device.remoteId,
                    bondState: device.paired
                        ? BmBondStateEnum.bonded
                        : BmBondStateEnum.none,
                    prevState: null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived {
    return _onCharacteristicReadController.stream.mergeWith([
      _client.devicesChanged.switchMap(
        (devices) {
          final streams = <Stream<BmCharacteristicData>>[];

          for (final device in devices) {
            for (final service in device.gattServices) {
              for (final characteristic in service.characteristics) {
                streams.add(
                  characteristic.propertiesChanged.where(
                    (properties) {
                      return properties.contains('Value');
                    },
                  ).map(
                    (properties) {
                      return BmCharacteristicData(
                        remoteId: device.remoteId,
                        serviceUuid: Guid.fromBytes(
                          service.uuid.value,
                        ),
                        characteristicUuid: Guid.fromBytes(
                          characteristic.uuid.value,
                        ),
                        primaryServiceUuid: null,
                        value: characteristic.value,
                        success: true,
                        errorCode: 0,
                        errorString: '',
                      );
                    },
                  ),
                );
              }
            }
          }

          return MergeStream(streams);
        },
      ),
    ]);
  }

  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten {
    return _onCharacteristicWrittenController.stream;
  }

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged {
    return _client.devicesChanged.switchMap(
      (devices) {
        return MergeStream(
          devices.map(
            (device) {
              return device.propertiesChanged.where(
                (properties) {
                  return properties.contains('Connected');
                },
              ).map(
                (properties) {
                  return BmConnectionStateResponse(
                    remoteId: device.remoteId,
                    connectionState: device.connected
                        ? BmConnectionStateEnum.connected
                        : BmConnectionStateEnum.disconnected,
                    disconnectReasonCode: null,
                    disconnectReasonString: null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Stream<BmDescriptorData> get onDescriptorRead {
    return _onDescriptorReadController.stream;
  }

  @override
  Stream<BmDescriptorData> get onDescriptorWritten {
    return _onDescriptorWrittenController.stream;
  }

  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices {
    return _onDiscoveredServicesController.stream;
  }

  @override
  Stream<BmMtuChangedResponse> get onMtuChanged {
    return Stream.empty();
  }

  @override
  Stream<BmNameChanged> get onNameChanged {
    return _client.devicesChanged.switchMap(
      (devices) {
        return MergeStream(
          devices.map(
            (device) {
              return device.propertiesChanged.where(
                (properties) {
                  return properties.contains('Name');
                },
              ).map(
                (properties) {
                  return BmNameChanged(
                    remoteId: device.remoteId,
                    name: device.name,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Stream<BmReadRssiResult> get onReadRssi {
    return _onReadRssiController.stream;
  }

  @override
  Stream<BmScanResponse> get onScanResponse {
    return _client.deviceAdded.map(
      (device) {
        // Add debug logging for device discovery
        print(
            '[FBP-Linux] Debug: Scan discovered device: ${device.address} (${device.name}), RSSI: ${device.rssi}');

        // Special logging for target devices
        final deviceName = device.name.toLowerCase();
        if (deviceName.contains('micro') ||
            deviceName.contains('node') ||
            deviceName.contains('glamox') ||
            deviceName.contains('mate')) {
          print(
              '[FBP-Linux] Debug: *** IMPORTANT: Target device found in scan: ${device.address} (${device.name}) ***');
        }

        return BmScanResponse(
          advertisements: [
            BmScanAdvertisement(
              remoteId: device.remoteId,
              platformName: device.name,
              advName: null,
              connectable: true,
              txPowerLevel: device.txPower,
              appearance: device.appearance,
              manufacturerData: device.manufacturerData.map(
                (id, value) {
                  return MapEntry(id.id, value);
                },
              ),
              serviceData: device.serviceData.map(
                (uuid, value) {
                  return MapEntry(Guid.fromBytes(uuid.value), value);
                },
              ),
              serviceUuids: device.uuids.map(
                (uuid) {
                  return Guid.fromBytes(uuid.value);
                },
              ).toList(),
              rssi: device.rssi,
            ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        );
      },
    );
  }

  @override
  Stream<BmBluetoothDevice> get onServicesReset {
    return _client.devicesChanged.switchMap(
      (devices) {
        return MergeStream(
          devices.map(
            (device) {
              return device.propertiesChanged.where(
                (properties) {
                  return properties.contains('UUIDs');
                },
              ).map(
                (properties) {
                  return BmBluetoothDevice(
                    remoteId: device.remoteId,
                    platformName: device.name,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Stream<BmTurnOnResponse> get onTurnOnResponse {
    return _onTurnOnResponseController.stream;
  }

  @override
  Future<bool> connect(
    BmConnectRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      print('[FBP-Linux] Attempting to connect to device: ${request.remoteId}');
      print(
          '[FBP-Linux] Debug: Total devices in BlueZ: ${_client.devices.length}');

      // First handle the case where remoteId might be just the raw MAC address
      String deviceAddress = request.remoteId.toString();
      print('[FBP-Linux] Debug: Parsed device address: $deviceAddress');
      BlueZDevice? targetDevice;

      // Try to find the device with max retry attempts
      int maxRetries = 3;
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          print(
              '[FBP-Linux] Debug: Search attempt ${attempt + 1}, looking for device with ID/address: $deviceAddress');

          // List all available devices with their addresses for debugging
          if (_client.devices.isNotEmpty) {
            print('[FBP-Linux] Debug: Available devices:');
            for (final device in _client.devices) {
              print(
                  '[FBP-Linux] Debug:   - ${device.address} (${device.name})');
            }
          } else {
            print('[FBP-Linux] Debug: No devices found in BlueZ registry');
          }

          targetDevice = _client.devices.singleWhere(
            (device) {
              final match = device.remoteId == request.remoteId ||
                  device.address.toLowerCase() == deviceAddress.toLowerCase();
              print(
                  '[FBP-Linux] Debug: Checking device ${device.address}, name: ${device.name}, match: $match');
              return match;
            },
          );

          print(
              '[FBP-Linux] Found device, attempting connection to ${targetDevice.address} (${targetDevice.name})');
          break;
        } catch (e) {
          // If device not found and we're not on final attempt, scan again
          print(
              '[FBP-Linux] Debug: Device not found on attempt ${attempt + 1}: $e');
          if (attempt < maxRetries - 1) {
            print('[FBP-Linux] Debug: Rescanning for devices...');
            await _client.adapters.first.startDiscovery();
            await Future.delayed(const Duration(seconds: 2));
            await _client.adapters.first.stopDiscovery();
          }
        }
      }

      // If we couldn't find the device, try fallback methods
      if (targetDevice == null) {
        print('[FBP-Linux] Device not found in BlueZ, trying fallbacks');

        // Try to find by address using a more tolerant approach
        try {
          print(
              '[FBP-Linux] Debug: Attempting fallback device lookup with address: $deviceAddress');
          for (final device in _client.devices) {
            print(
                '[FBP-Linux] Debug: Checking if ${device.address} matches $deviceAddress');
            if (device.address
                    .toLowerCase()
                    .contains(deviceAddress.toLowerCase()) ||
                deviceAddress
                    .toLowerCase()
                    .contains(device.address.toLowerCase())) {
              print(
                  '[FBP-Linux] Debug: Found partial match: ${device.address}');
              targetDevice = device;
              break;
            }
          }
        } catch (e) {
          print('[FBP-Linux] Debug: Error in fallback device lookup: $e');
        }

        // If still null, try system commands
        if (targetDevice == null) {
          print(
              '[FBP-Linux] Debug: Device not found in BlueZ, trying direct system commands');
          throw Exception('Device not found in BlueZ');
        }
      }

      print(
          '[FBP-Linux] Debug: Device found, proceeding with connection to ${targetDevice.address}');
      print(
          '[FBP-Linux] Debug: Device status before connection - paired: ${targetDevice.paired}, trusted: ${targetDevice.trusted}, connected: ${targetDevice.connected}');

      // Now connect to the device
      try {
        print('[FBP-Linux] Debug: Calling connect() on BlueZ device');
        await targetDevice.connect();
        print('[FBP-Linux] Debug: BlueZ connect() call completed');
      } catch (e) {
        print('[FBP-Linux] Debug: BlueZ connect() method failed: $e');
        print('[FBP-Linux] Debug: Attempting to pair before connecting');

        try {
          await targetDevice.pair();
          print('[FBP-Linux] Debug: Pairing successful, retrying connection');
          await targetDevice.connect();
        } catch (pairError) {
          print('[FBP-Linux] Debug: Pairing failed: $pairError');
          throw pairError;
        }
      }

      // Wait for a moment to allow services to be discovered
      print('[FBP-Linux] Debug: Waiting for services to be discovered');
      await Future.delayed(Duration(seconds: 1));

      // Verify that the device is connected
      print(
          '[FBP-Linux] Debug: Checking connection status after connect attempt');
      if (targetDevice.connected) {
        print('[FBP-Linux] Connection successful');

        // Get available services
        print(
            '[FBP-Linux] Debug: Available services: ${targetDevice.gattServices.length}');
        for (var service in targetDevice.gattServices) {
          print('[FBP-Linux] Debug: Service: ${service.uuid.value}');
        }

        // Try to refresh device services to ensure they're available
        print('[FBP-Linux] Debug: Refreshing device services');
        await _refreshDeviceServices(targetDevice);

        return true;
      } else {
        print('[FBP-Linux] Connection failed, device reports not connected');
        print(
            '[FBP-Linux] Debug: Device status after failed connection - paired: ${targetDevice.paired}, trusted: ${targetDevice.trusted}, connected: ${targetDevice.connected}');
        return false;
      }
    } catch (e) {
      print('[FBP-Linux] Error connecting: $e');

      // Check if we're running on a Raspberry Pi for enhanced fallback
      final isRaspberryPi = await RaspberryPiBlueZHelper.isRaspberryPi();

      if (isRaspberryPi) {
        print(
            '[FBP-Linux] Detected Raspberry Pi environment, using optimized connection approach');

        // Check D-Bus configuration and start a session if needed
        final dbusConfigured =
            await RaspberryPiBlueZHelper.checkDBusConfiguration();
        if (!dbusConfigured) {
          print(
              '[FBP-Linux] D-Bus session not properly configured, attempting to start one');
          await RaspberryPiBlueZHelper.startDBusSession();
        }

        // Reset the adapter to ensure it's in a clean state
        await RaspberryPiBlueZHelper.resetAdapter();

        // Use the enhanced connection method with retries and extended timeout
        final success = await RaspberryPiBlueZHelper.connectWithBluetoothtcl(
            request.remoteId.toString(),
            retries: 3,
            timeout: 15);

        if (success) {
          print('[FBP-Linux] Raspberry Pi optimized connection successful');

          // Wait a moment for BlueZ to register the connection
          await Future.delayed(Duration(seconds: 2));

          // Force client refresh to pick up the new connection
          await _refreshClient();

          return true;
        } else {
          print('[FBP-Linux] Raspberry Pi optimized connection failed');
          return false;
        }
      } else {
        // Standard fallback for non-Raspberry Pi systems
        try {
          print(
              '[FBP-Linux] Attempting fallback connection using bluetoothctl');
          print(
              '[FBP-Linux] Debug: Using address: ${request.remoteId.toString()}');

          final result = await Process.run(
              'bluetoothctl', ['connect', request.remoteId.toString()]);
          final success = result.exitCode == 0 &&
              !result.stdout.toString().contains('Failed to connect');

          print(
              '[FBP-Linux] Debug: Bluetoothctl result - exit code: ${result.exitCode}');
          print('[FBP-Linux] Debug: Bluetoothctl output: ${result.stdout}');
          if (result.stderr.toString().isNotEmpty) {
            print('[FBP-Linux] Debug: Bluetoothctl error: ${result.stderr}');
          }

          if (success) {
            print('[FBP-Linux] Fallback connection successful');

            // Wait a moment for BlueZ to register the connection
            await Future.delayed(Duration(seconds: 2));

            // Force client refresh to pick up the new connection
            await _refreshClient();

            return true;
          } else {
            print('[FBP-Linux] Fallback connection failed: ${result.stderr}');
            return false;
          }
        } catch (fallbackError) {
          print('[FBP-Linux] Fallback connection error: $fallbackError');
          return false;
        }
      }
    }
  }

  // Helper method to refresh device services
  Future<void> _refreshDeviceServices(BlueZDevice device) async {
    try {
      print('[FBP-Linux] Refreshing services for ${device.remoteId}');

      // Wait a moment to let any pending operations complete
      await Future.delayed(const Duration(seconds: 1));

      // In this version, we can't directly refresh GATT services
      // So we'll just log what we found
      print('[FBP-Linux] Services found: ${device.gattServices.length}');

      if (device.gattServices.isEmpty) {
        print(
            '[FBP-Linux] WARNING: No services found for device ${device.remoteId}');
        print(
            '[FBP-Linux] Debug: Attempting to trigger service discovery via BlueZ');

        try {
          // Try to force discovery through direct DBus examination
          print('[FBP-Linux] Debug: Examining device object paths');

          // Check device properties to ensure it's in a good state
          print(
              '[FBP-Linux] Debug: Device properties - connected: ${device.connected}, paired: ${device.paired}, trusted: ${device.trusted}');

          // Try to force service discovery through other mechanisms
          await device
              .connect(); // Try reconnecting to trigger service discovery
        } catch (e) {
          print('[FBP-Linux] Debug: Error in service discovery: $e');
        }
      }

      for (final service in device.gattServices) {
        print('[FBP-Linux] Service: ${service.uuid}');

        // Log characteristics for each service
        print(
            '[FBP-Linux] Debug: Characteristics for service ${service.uuid}: ${service.characteristics.length}');
        for (final characteristic in service.characteristics) {
          print(
              '[FBP-Linux] Debug:   - Characteristic: ${characteristic.uuid}, flags: ${characteristic.flags}');
        }
      }
    } catch (e) {
      print('[FBP-Linux] Error accessing services: $e');
      print('[FBP-Linux] Debug: Stack trace: ${StackTrace.current}');
    }
  }

  // Helper method to refresh the BlueZ client
  Future<void> _refreshClient() async {
    try {
      print('[FBP-Linux] Debug: Refreshing BlueZ client connection');
      // We can't disconnect and reconnect the client directly
      // So we'll create a new client instance
      _initialized = false;
      await _initFlutterBluePlus();
      print('[FBP-Linux] Debug: BlueZ client refreshed successfully');
    } catch (e) {
      print('[FBP-Linux] Error reinitializing client: $e');
      print('[FBP-Linux] Debug: Stack trace: ${StackTrace.current}');
    }
  }

  @override
  Future<bool> createBond(
    BmCreateBondRequest request,
  ) async {
    await _initFlutterBluePlus();

    final device = _client.devices.singleWhere(
      (device) {
        return device.remoteId == request.remoteId;
      },
    );

    await device.pair();

    return true;
  }

  @override
  Future<bool> disconnect(
    BmDisconnectRequest request,
  ) async {
    await _initFlutterBluePlus();

    final device = _client.devices.singleWhere(
      (device) {
        return device.remoteId == request.remoteId;
      },
    );

    await device.disconnect();

    return true;
  }

  @override
  Future<bool> discoverServices(
    BmDiscoverServicesRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      print('[FBP-Linux] Discovering services for device: ${request.remoteId}');
      print(
          '[FBP-Linux] Debug: Total known devices: ${_client.devices.length}');

      // Print list of devices we know about first
      print('[FBP-Linux] Debug: Known devices:');
      for (final d in _client.devices) {
        print(
            '[FBP-Linux] Debug: - Device ${d.address} (${d.name}), Connected: ${d.connected}');
      }

      try {
        final device = _client.devices.singleWhere(
          (device) {
            final matches = device.remoteId == request.remoteId;
            print(
                '[FBP-Linux] Debug: Checking if device ${device.address} matches target ${request.remoteId}: $matches');
            return matches;
          },
        );

        // If no services are found, try to refresh services first
        if (device.gattServices.isEmpty) {
          print(
              '[FBP-Linux] No services found, attempting to refresh services');
          await _refreshDeviceServices(device);

          // If still no services, try fallback method with system commands
          if (device.gattServices.isEmpty) {
            print(
                '[FBP-Linux] Still no services after refresh, trying system commands');
            print('[FBP-Linux] Debug: Using device address: ${device.address}');
            return await _discoverServicesWithSystemCommands(request);
          }
        }

        print('[FBP-Linux] Found ${device.gattServices.length} services');

        // For debugging, log all found services and characteristics
        for (final service in device.gattServices) {
          final serviceUuid = Guid.fromBytes(service.uuid.value);
          print('[FBP-Linux] Service: $serviceUuid');

          for (final characteristic in service.characteristics) {
            final charUuid = Guid.fromBytes(characteristic.uuid.value);
            final properties = <String>[];

            if (characteristic.flags
                .contains(BlueZGattCharacteristicFlag.read)) {
              properties.add('read');
            }
            if (characteristic.flags
                .contains(BlueZGattCharacteristicFlag.write)) {
              properties.add('write');
            }
            if (characteristic.flags
                .contains(BlueZGattCharacteristicFlag.notify)) {
              properties.add('notify');
            }
            if (characteristic.flags
                .contains(BlueZGattCharacteristicFlag.indicate)) {
              properties.add('indicate');
            }

            print(
                '[FBP-Linux]   - Characteristic: $charUuid (${properties.join(', ')})');
          }
        }

        _onDiscoveredServicesController.add(
          BmDiscoverServicesResult(
            remoteId: device.remoteId,
            services: device.gattServices.map(
              (service) {
                return BmBluetoothService(
                  serviceUuid: Guid.fromBytes(
                    service.uuid.value,
                  ),
                  remoteId: device.remoteId,
                  characteristics: service.characteristics.map(
                    (characteristic) {
                      return BmBluetoothCharacteristic(
                        remoteId: device.remoteId,
                        serviceUuid: Guid.fromBytes(
                          service.uuid.value,
                        ),
                        characteristicUuid: Guid.fromBytes(
                          characteristic.uuid.value,
                        ),
                        primaryServiceUuid: null,
                        descriptors: characteristic.descriptors.map(
                          (descriptor) {
                            return BmBluetoothDescriptor(
                              remoteId: device.remoteId,
                              serviceUuid: Guid.fromBytes(
                                service.uuid.value,
                              ),
                              characteristicUuid: Guid.fromBytes(
                                characteristic.uuid.value,
                              ),
                              descriptorUuid: Guid.fromBytes(
                                descriptor.uuid.value,
                              ),
                              primaryServiceUuid: null,
                            );
                          },
                        ).toList(),
                        properties: BmCharacteristicProperties(
                          broadcast: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.broadcast,
                          ),
                          read: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.read,
                          ),
                          writeWithoutResponse: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.writeWithoutResponse,
                          ),
                          write: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.write,
                          ),
                          notify: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.notify,
                          ),
                          indicate: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.indicate,
                          ),
                          authenticatedSignedWrites:
                              characteristic.flags.contains(
                            BlueZGattCharacteristicFlag
                                .authenticatedSignedWrites,
                          ),
                          extendedProperties: characteristic.flags.contains(
                            BlueZGattCharacteristicFlag.extendedProperties,
                          ),
                          notifyEncryptionRequired: false,
                          indicateEncryptionRequired: false,
                        ),
                      );
                    },
                  ).toList(),
                  primaryServiceUuid: null,
                );
              },
            ).toList(),
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );

        return true;
      } catch (e) {
        print('[FBP-Linux] Error discovering services: $e');

        // Try system command fallback
        return await _discoverServicesWithSystemCommands(request);
      }
    } catch (e) {
      print('[FBP-Linux] Error discovering services: $e');

      // Try system command fallback
      return await _discoverServicesWithSystemCommands(request);
    }
  }

  // Fallback method to discover services using system commands
  Future<bool> _discoverServicesWithSystemCommands(
      BmDiscoverServicesRequest request) async {
    try {
      print(
          '[FBP-Linux] Attempting to discover services using system commands');
      print('[FBP-Linux] Debug: Device ID: ${request.remoteId}');

      // Check if we're running on a Raspberry Pi
      final isRaspberryPi = await RaspberryPiBlueZHelper.isRaspberryPi();
      if (isRaspberryPi) {
        print(
            '[FBP-Linux] Detected Raspberry Pi environment, using optimized approach');

        // First try to connect with bluetoothctl using the enhanced method
        await RaspberryPiBlueZHelper.connectWithBluetoothtcl(
            request.remoteId.toString(),
            retries: 3,
            timeout: 15);

        // Use the enhanced service discovery method
        final services =
            await RaspberryPiBlueZHelper.discoverServicesWithGatttool(
                request.remoteId.toString());

        print(
            '[FBP-Linux] Found ${services.length} services using Raspberry Pi helper');

        // Convert the discovered services to BmBluetoothService objects
        final bmServices = <BmBluetoothService>[];

        for (final service in services) {
          final uuid = service['uuid'] as String?;
          if (uuid != null) {
            try {
              // Try to create a Guid from the UUID string
              final serviceUuid = Guid(uuid);

              // Create a service object
              bmServices.add(
                BmBluetoothService(
                  serviceUuid: serviceUuid,
                  remoteId: request.remoteId,
                  characteristics: [], // We don't have characteristic info from gatttool
                  primaryServiceUuid: null,
                ),
              );
            } catch (e) {
              print('[FBP-Linux] Error creating service from UUID $uuid: $e');
            }
          }
        }

        // Send the result with the discovered services
        _onDiscoveredServicesController.add(
          BmDiscoverServicesResult(
            remoteId: request.remoteId,
            services: bmServices,
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );

        return true;
      } else {
        // Fall back to the original implementation for non-Raspberry Pi systems
        // First try with bluetoothctl to see if we can connect
        print(
            '[FBP-Linux] Debug: Attempting to connect with bluetoothctl first');
        final connectResult = await Process.run(
            'bluetoothctl', ['connect', request.remoteId.toString()]);
        print(
            '[FBP-Linux] Debug: Bluetoothctl connect result: ${connectResult.exitCode}');
        print(
            '[FBP-Linux] Debug: Bluetoothctl output: ${connectResult.stdout}');
        if (connectResult.stderr.toString().isNotEmpty) {
          print(
              '[FBP-Linux] Debug: Bluetoothctl stderr: ${connectResult.stderr}');
        }

        // Use gatttool for service discovery
        print('[FBP-Linux] Debug: Running gatttool primary service discovery');
        final result = await Process.run(
            'gatttool', ['-b', request.remoteId.toString(), '--primary']);

        if (result.exitCode != 0) {
          print('[FBP-Linux] gatttool command failed: ${result.stderr}');
          print('[FBP-Linux] Debug: Exit code: ${result.exitCode}');

          // Try alternate approach with timeout
          print(
              '[FBP-Linux] Debug: Trying alternative service discovery approach');
          final altResult = await Process.run('sh', [
            '-c',
            'timeout 5 gatttool -b ${request.remoteId.toString()} --primary'
          ]);
          print(
              '[FBP-Linux] Debug: Alternative approach exit code: ${altResult.exitCode}');
          print('[FBP-Linux] Debug: Alternative output: ${altResult.stdout}');

          if (altResult.stderr.toString().isNotEmpty) {
            print('[FBP-Linux] Debug: Alternative stderr: ${altResult.stderr}');
          }

          // If still failing, return false
          if (altResult.exitCode != 0) {
            return false;
          }
        }

        // Parse services
        final output = result.stdout.toString();
        print('[FBP-Linux] Debug: Gatttool raw output: $output');

        final serviceLines =
            output.split('\n').where((line) => line.contains('uuid:')).toList();

        print(
            '[FBP-Linux] Found ${serviceLines.length} services using gatttool');
        for (final line in serviceLines) {
          print('[FBP-Linux] Debug: Service: $line');
        }

        // Create a fake services list
        final services = <BmBluetoothService>[];

        // Handle the case where no services were found
        if (serviceLines.isEmpty) {
          print('[FBP-Linux] No services found with gatttool');

          // Create a result with no services
          _onDiscoveredServicesController.add(
            BmDiscoverServicesResult(
              remoteId: request.remoteId,
              services: [],
              success: true,
              errorCode: 0,
              errorString: '',
            ),
          );

          return true;
        }

        // TODO: Parse service UUIDs and attempt to create service objects
        // For now, just sending an empty list as we need more complex parsing

        // Send the result with the discovered services
        _onDiscoveredServicesController.add(
          BmDiscoverServicesResult(
            remoteId: request.remoteId,
            services: services,
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );

        return true;
      }
    } catch (e) {
      print('[FBP-Linux] Error in system command service discovery: $e');
      print('[FBP-Linux] Debug: Stack trace: ${StackTrace.current}');

      // Create a failed result
      _onDiscoveredServicesController.add(
        BmDiscoverServicesResult(
          remoteId: request.remoteId,
          services: [],
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  @override
  Future<BmBluetoothAdapterName> getAdapterName(
    BmBluetoothAdapterNameRequest request,
  ) async {
    await _initFlutterBluePlus();

    return BmBluetoothAdapterName(
      adapterName: _client.adapters.first.name,
    );
  }

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async {
    await _initFlutterBluePlus();

    return BmBluetoothAdapterState(
      adapterState: _client.adapters.firstOrNull?.powered == true
          ? BmAdapterStateEnum.on
          : BmAdapterStateEnum.off,
    );
  }

  @override
  Future<BmBondStateResponse> getBondState(
    BmBondStateRequest request,
  ) async {
    await _initFlutterBluePlus();

    final device = _client.devices.singleWhere(
      (device) {
        return device.remoteId == request.remoteId;
      },
    );

    return BmBondStateResponse(
      remoteId: device.remoteId,
      bondState: device.paired ? BmBondStateEnum.bonded : BmBondStateEnum.none,
      prevState: null,
    );
  }

  @override
  Future<BmDevicesList> getBondedDevices(
    BmBondedDevicesRequest request,
  ) async {
    await _initFlutterBluePlus();

    return BmDevicesList(
      devices: _client.devices.where(
        (device) {
          return device.paired;
        },
      ).map(
        (device) {
          return BmBluetoothDevice(
            remoteId: device.remoteId,
            platformName: device.name,
          );
        },
      ).toList(),
    );
  }

  @override
  Future<BmDevicesList> getSystemDevices(
    BmSystemDevicesRequest request,
  ) async {
    await _initFlutterBluePlus();

    return BmDevicesList(
      devices: _client.devices.map(
        (device) {
          return BmBluetoothDevice(
            remoteId: device.remoteId,
            platformName: device.name,
          );
        },
      ).toList(),
    );
  }

  @override
  Future<bool> isSupported(
    BmIsSupportedRequest request,
  ) async {
    await _initFlutterBluePlus();

    return _client.adapters.length > 0;
  }

  @override
  Future<bool> readCharacteristic(
    BmReadCharacteristicRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      final service = device.gattServices.singleWhere(
        (service) {
          final uuid = Guid.fromBytes(
            service.uuid.value,
          );

          return uuid == request.serviceUuid;
        },
      );

      final characteristic = service.characteristics.singleWhere(
        (characteristic) {
          final uuid = Guid.fromBytes(
            characteristic.uuid.value,
          );

          return uuid == request.characteristicUuid;
        },
      );

      final value = await characteristic.readValue();

      _onCharacteristicReadController.add(
        BmCharacteristicData(
          remoteId: device.remoteId,
          serviceUuid: Guid.fromBytes(
            service.uuid.value,
          ),
          characteristicUuid: Guid.fromBytes(
            characteristic.uuid.value,
          ),
          primaryServiceUuid: null,
          value: value,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );

      return true;
    } catch (e) {
      _onCharacteristicReadController.add(
        BmCharacteristicData(
          remoteId: request.remoteId,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          primaryServiceUuid: null,
          value: [],
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  @override
  Future<bool> readDescriptor(
    BmReadDescriptorRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      final service = device.gattServices.singleWhere(
        (service) {
          final uuid = Guid.fromBytes(
            service.uuid.value,
          );

          return uuid == request.serviceUuid;
        },
      );

      final characteristic = service.characteristics.singleWhere(
        (characteristic) {
          final uuid = Guid.fromBytes(
            characteristic.uuid.value,
          );

          return uuid == request.characteristicUuid;
        },
      );

      final descriptor = characteristic.descriptors.singleWhere(
        (descriptor) {
          final uuid = Guid.fromBytes(
            descriptor.uuid.value,
          );

          return uuid == request.descriptorUuid;
        },
      );

      final value = await characteristic.readValue();

      _onDescriptorReadController.add(
        BmDescriptorData(
          remoteId: device.remoteId,
          serviceUuid: Guid.fromBytes(
            service.uuid.value,
          ),
          characteristicUuid: Guid.fromBytes(
            characteristic.uuid.value,
          ),
          descriptorUuid: Guid.fromBytes(
            descriptor.uuid.value,
          ),
          primaryServiceUuid: null,
          value: value,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );

      return true;
    } catch (e) {
      _onDescriptorReadController.add(
        BmDescriptorData(
          remoteId: request.remoteId,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          descriptorUuid: request.descriptorUuid,
          primaryServiceUuid: null,
          value: [],
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  @override
  Future<bool> readRssi(
    BmReadRssiRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      _onReadRssiController.add(
        BmReadRssiResult(
          remoteId: device.remoteId,
          rssi: device.rssi,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );

      return true;
    } catch (e) {
      _onReadRssiController.add(
        BmReadRssiResult(
          remoteId: request.remoteId,
          rssi: 0,
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  @override
  Future<bool> setLogLevel(
    BmSetLogLevelRequest request,
  ) async {
    await _initFlutterBluePlus();

    _logLevel = request.logLevel;

    return true;
  }

  @override
  Future<bool> setNotifyValue(
    BmSetNotifyValueRequest request,
  ) async {
    await _initFlutterBluePlus();

    try {
      print(
          '[FBP-Linux] Setting notify value ${request.enable} for ${request.characteristicUuid}');

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      final service = device.gattServices.singleWhere(
        (service) {
          final uuid = Guid.fromBytes(
            service.uuid.value,
          );

          return uuid == request.serviceUuid;
        },
        orElse: () {
          print('[FBP-Linux] Service ${request.serviceUuid} not found');
          throw Exception('Service not found');
        },
      );

      final characteristic = service.characteristics.singleWhere(
        (characteristic) {
          final uuid = Guid.fromBytes(
            characteristic.uuid.value,
          );

          return uuid == request.characteristicUuid;
        },
        orElse: () {
          print(
              '[FBP-Linux] Characteristic ${request.characteristicUuid} not found');
          throw Exception('Characteristic not found');
        },
      );

      // Multiple attempts for notification setup
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          if (request.enable) {
            await characteristic.startNotify();
            print('[FBP-Linux] Successfully enabled notifications');
          } else {
            await characteristic.stopNotify();
            print('[FBP-Linux] Successfully disabled notifications');
          }
          return true;
        } catch (e) {
          print(
              '[FBP-Linux] Notification setup attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          } else {
            rethrow;
          }
        }
      }

      return false;
    } catch (e) {
      print('[FBP-Linux] Error setting notify value: $e');

      // Try system command fallback for notification setup
      try {
        print('[FBP-Linux] Trying fallback notification setup');

        // Convert the UUIDs to lowercase strings without dashes
        final characteristicUuidStr = request.characteristicUuid
            .toString()
            .toLowerCase()
            .replaceAll('-', '');

        // Get the handle using gatttool (this is a simplification - in practice you'd need to parse the handle)
        final cmdResult = await Process.run('gatttool', [
          '-b',
          request.remoteId.toString(),
          '--char-read',
          '--uuid=$characteristicUuidStr'
        ]);

        // This is just a placeholder for a proper implementation that would parse the handle
        // and then use it to enable notifications via gatttool

        return false; // Fallback not fully implemented
      } catch (fallbackError) {
        print('[FBP-Linux] Fallback notification setup failed: $fallbackError');
        return false;
      }
    }
  }

  @override
  Future<bool> startScan(
    BmScanSettings request,
  ) async {
    await _initFlutterBluePlus();

    print(
        '[FBP-Linux] Debug: Starting scan with service UUIDs: ${request.withServices.map((uuid) => uuid.str128).join(', ')}');
    print(
        '[FBP-Linux] Debug: Adapter state: ${_client.adapters.first.powered ? 'powered' : 'unpowered'}');
    print(
        '[FBP-Linux] Debug: Known devices before scan: ${_client.devices.length}');

    try {
      await _client.adapters.first.setDiscoveryFilter(
        uuids: request.withServices.map(
          (uuid) {
            return uuid.str128;
          },
        ).toList(),
      );

      print('[FBP-Linux] Debug: Discovery filter set successfully');

      // Start discovery and log results
      await _client.adapters.first.startDiscovery();
      print('[FBP-Linux] Debug: Discovery started, waiting for devices...');

      // Schedule a delayed check to see what was found
      Future.delayed(Duration(seconds: 5), () {
        print(
            '[FBP-Linux] Debug: Devices found after 5s: ${_client.devices.length}');
        for (final device in _client.devices) {
          print(
              '[FBP-Linux] Debug: - Device: ${device.address} (${device.name}), RSSI: ${device.rssi}');
        }
      });

      return true;
    } catch (e) {
      print('[FBP-Linux] Error starting scan: $e');
      return false;
    }
  }

  @override
  Future<bool> stopScan(
    BmStopScanRequest request,
  ) async {
    await _initFlutterBluePlus();

    print('[FBP-Linux] Debug: Stopping scan');
    print('[FBP-Linux] Debug: Final device count: ${_client.devices.length}');

    // Log all discovered devices
    if (_client.devices.isNotEmpty) {
      print('[FBP-Linux] Debug: Discovered devices:');
      for (final device in _client.devices) {
        print(
            '[FBP-Linux] Debug: - ${device.address} (${device.name}), RSSI: ${device.rssi}, Connected: ${device.connected}');
      }
    }

    await _client.adapters.first.stopDiscovery();
    return true;
  }

  @override
  Future<bool> turnOff(
    BmTurnOffRequest request,
  ) async {
    await _initFlutterBluePlus();

    if (_client.adapters.first.powered == true) {
      await _client.adapters.first.setPowered(false);

      return true;
    }

    return false;
  }

  @override
  Future<bool> turnOn(
    BmTurnOnRequest request,
  ) async {
    await _initFlutterBluePlus();

    if (_client.adapters.first.powered == false) {
      await _client.adapters.first.setPowered(true);

      _onTurnOnResponseController.add(
        BmTurnOnResponse(
          userAccepted: true,
        ),
      );

      return true;
    }

    return false;
  }

  @override
  Future<bool> writeCharacteristic(
    BmWriteCharacteristicRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      final service = device.gattServices.singleWhere(
        (service) {
          final uuid = Guid.fromBytes(
            service.uuid.value,
          );

          return uuid == request.serviceUuid;
        },
      );

      final characteristic = service.characteristics.singleWhere(
        (characteristic) {
          final uuid = Guid.fromBytes(
            characteristic.uuid.value,
          );

          return uuid == request.characteristicUuid;
        },
      );

      await characteristic.writeValue(
        request.value,
        type: request.writeType == BmWriteType.withResponse
            ? BlueZGattCharacteristicWriteType.request
            : BlueZGattCharacteristicWriteType.command,
      );

      _onCharacteristicWrittenController.add(
        BmCharacteristicData(
          remoteId: device.remoteId,
          serviceUuid: Guid.fromBytes(
            service.uuid.value,
          ),
          characteristicUuid: Guid.fromBytes(
            characteristic.uuid.value,
          ),
          primaryServiceUuid: null,
          value: request.value,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );

      return true;
    } catch (e) {
      _onCharacteristicWrittenController.add(
        BmCharacteristicData(
          remoteId: request.remoteId,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          primaryServiceUuid: null,
          value: request.value,
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  @override
  Future<bool> writeDescriptor(
    BmWriteDescriptorRequest request,
  ) async {
    try {
      await _initFlutterBluePlus();

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      final service = device.gattServices.singleWhere(
        (service) {
          final uuid = Guid.fromBytes(
            service.uuid.value,
          );

          return uuid == request.serviceUuid;
        },
      );

      final characteristic = service.characteristics.singleWhere(
        (characteristic) {
          final uuid = Guid.fromBytes(
            characteristic.uuid.value,
          );

          return uuid == request.characteristicUuid;
        },
      );

      final descriptor = characteristic.descriptors.singleWhere(
        (descriptor) {
          final uuid = Guid.fromBytes(
            descriptor.uuid.value,
          );

          return uuid == request.descriptorUuid;
        },
      );

      await descriptor.writeValue(request.value);

      _onDescriptorWrittenController.add(
        BmDescriptorData(
          remoteId: device.remoteId,
          serviceUuid: Guid.fromBytes(
            service.uuid.value,
          ),
          characteristicUuid: Guid.fromBytes(
            characteristic.uuid.value,
          ),
          descriptorUuid: Guid.fromBytes(
            descriptor.uuid.value,
          ),
          primaryServiceUuid: null,
          value: request.value,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );

      return true;
    } catch (e) {
      _onDescriptorWrittenController.add(
        BmDescriptorData(
          remoteId: request.remoteId,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          descriptorUuid: request.descriptorUuid,
          primaryServiceUuid: null,
          value: request.value,
          success: false,
          errorCode: 0,
          errorString: e.toString(),
        ),
      );

      return false;
    }
  }

  static void registerWith() {
    FlutterBluePlusPlatform.instance = FlutterBluePlusLinux();
  }

  Future<void> _initFlutterBluePlus() async {
    if (_initialized) {
      print('[FBP-Linux] Debug: BlueZ client already initialized, skipping');
      return;
    }

    print('[FBP-Linux] Debug: Initializing BlueZ client connection');

    try {
      print('[FBP-Linux] Debug: Connecting to BlueZ D-Bus service');
      await _client.connect();
      print('[FBP-Linux] Debug: Connected to BlueZ successfully');

      // Check adapter state
      if (_client.adapters.isEmpty) {
        print('[FBP-Linux] Debug: WARNING - No Bluetooth adapters found');
      } else {
        final adapter = _client.adapters.first;
        print(
            '[FBP-Linux] Debug: Found adapter: ${adapter.address}, powered: ${adapter.powered}');

        // Try to power on the adapter if it's not already on
        if (!adapter.powered) {
          print(
              '[FBP-Linux] Debug: Adapter not powered, attempting to power on');
          try {
            await adapter.setPowered(true);
            print('[FBP-Linux] Debug: Adapter powered on successfully');
          } catch (e) {
            print('[FBP-Linux] Debug: Failed to power on adapter: $e');
          }
        }
      }

      // Debug existing devices
      print(
          '[FBP-Linux] Debug: Devices known to BlueZ at initialization: ${_client.devices.length}');
      for (final device in _client.devices) {
        print(
            '[FBP-Linux] Debug: Device ${device.address} (${device.name}), connected: ${device.connected}');
      }

      _initialized = true;
      print('[FBP-Linux] Debug: BlueZ client initialization complete');
    } catch (e) {
      print('[FBP-Linux] Debug: Error initializing BlueZ client: $e');
      print('[FBP-Linux] Debug: Stack trace: ${StackTrace.current}');
      rethrow;
    }

    _client.devicesChanged.switchMap(
      (devices) {
        if (_logLevel == LogLevel.verbose) {
          print(
            '[FBP-Linux] devices changed ${devices.map((device) => device.remoteId).toList()}',
          );
        } else {
          print(
              '[FBP-Linux] Debug: Device list changed, count: ${devices.length}');
        }

        return MergeStream(
          devices.map(
            (device) {
              return device.propertiesChanged.switchMap(
                (properties) {
                  if (_logLevel == LogLevel.verbose) {
                    print(
                      '[FBP-Linux] device ${device.remoteId} properties changed $properties',
                    );
                  } else {
                    print(
                        '[FBP-Linux] Debug: Device ${device.address} properties changed');
                  }

                  final streams = <Stream<void>>[];

                  for (final service in device.gattServices) {
                    for (final characteristic in service.characteristics) {
                      streams.add(
                        characteristic.propertiesChanged.map(
                          (properties) {
                            if (_logLevel == LogLevel.verbose) {
                              print(
                                '[FBP-Linux] device ${device.remoteId} service ${service.uuid} characteristic ${characteristic.uuid} properties changed $properties',
                              );
                            } else {
                              print(
                                  '[FBP-Linux] Debug: Characteristic property changed for ${characteristic.uuid}');
                            }
                          },
                        ),
                      );
                    }
                  }

                  return MergeStream(streams);
                },
              );
            },
          ),
        );
      },
    ).listen((event) {
      print('[FBP-Linux] Debug: Received BLE event');
    }, onError: (e) {
      print('[FBP-Linux] Debug: Error in BLE event stream: $e');
    });
  }
}

extension on BlueZClient {
  Stream<List<BlueZAdapter>> get adaptersChanged {
    return MergeStream([
      adapterAdded.map((adapter) {
        print('[FBP-Linux] Debug: Bluetooth adapter added: ${adapter.name}');
        return adapter;
      }),
      adapterRemoved.map((adapter) {
        print('[FBP-Linux] Debug: Bluetooth adapter removed: ${adapter.name}');
        return adapter;
      }),
    ]).map(
      (adapter) {
        return adapters;
      },
    ).startWith(adapters);
  }

  Stream<List<BlueZDevice>> get devicesChanged {
    return MergeStream([
      deviceAdded.map((device) {
        print(
            '[FBP-Linux] Debug: BlueZ device added: ${device.address} (${device.name})');

        // Special logging for target devices
        if (device.name.toLowerCase().contains('micro') ||
            device.name.toLowerCase().contains('node') ||
            device.name.toLowerCase().contains('glamox')) {
          print(
              '[FBP-Linux] Debug: *** POTENTIAL TARGET DEVICE DETECTED: ${device.address} (${device.name}) ***');
        }

        return device;
      }),
      deviceRemoved.map((device) {
        print(
            '[FBP-Linux] Debug: BlueZ device removed: ${device.address} (${device.name})');
        return device;
      }),
    ]).map(
      (device) {
        return devices;
      },
    ).startWith(devices);
  }
}

extension on BlueZDevice {
  DeviceIdentifier get remoteId {
    return DeviceIdentifier(address);
  }
}

// Extension to help with direct connection by address
extension DeviceIdentifierHelpers on DeviceIdentifier {
  // Get the raw MAC address from the DeviceIdentifier
  String get rawAddress => id;

  // Checks if this is a valid Bluetooth MAC address
  bool get isValidBluetoothAddress {
    // Check if it matches the pattern XX:XX:XX:XX:XX:XX
    final regex =
        RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$', caseSensitive: false);
    return regex.hasMatch(id);
  }
}

// Additional helper to find a BlueZDevice by raw MAC address
extension BlueZClientHelpers on BlueZClient {
  BlueZDevice? findDeviceByAddress(String address) {
    try {
      return devices.firstWhere(
          (device) => device.address.toLowerCase() == address.toLowerCase());
    } catch (e) {
      return null;
    }
  }
}
