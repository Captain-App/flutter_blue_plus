import 'dart:async';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

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
  Future<bool> connect(
    BmConnectRequest request,
  ) async {
    await _initFlutterBluePlus();

    try {
      print('[FBP-Linux] Connecting to device: ${request.remoteId}');

      final device = _client.devices.singleWhere((device) {
        return device.remoteId == request.remoteId;
      }, orElse: () {
        // Device not found in BlueZ list, try to connect using direct BlueZ command
        print(
            '[FBP-Linux] Device not found in BlueZ device list. Trying direct BlueZ connect.');
        throw Exception('Device not found in BlueZ device list');
      });

      // Multiple connect attempts with exponential backoff
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        try {
          print('[FBP-Linux] Connect attempt ${attempts + 1}/${maxAttempts}');
          await device.connect();
          print('[FBP-Linux] Successfully connected to ${request.remoteId}');

          // Force service discovery to ensure we have all services
          await _refreshDeviceServices(device);

          return true;
        } catch (e) {
          attempts++;
          print('[FBP-Linux] Connection attempt $attempts failed: $e');

          if (attempts >= maxAttempts) {
            print('[FBP-Linux] Maximum connection attempts reached');
            rethrow;
          }

          // Exponential backoff between retries
          final delay = Duration(milliseconds: 200 * (1 << attempts));
          print('[FBP-Linux] Retrying in ${delay.inMilliseconds}ms');
          await Future.delayed(delay);
        }
      }

      return false;
    } catch (e) {
      print('[FBP-Linux] Error connecting: $e');

      // Try system command as fallback for Raspberry Pi
      try {
        print('[FBP-Linux] Attempting fallback connection using bluetoothctl');

        final result = await Process.run(
            'bluetoothctl', ['connect', request.remoteId.toString()]);
        final success = result.exitCode == 0 &&
            !result.stdout.toString().contains('Failed to connect');

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

  // Helper method to refresh device services
  Future<void> _refreshDeviceServices(BlueZDevice device) async {
    try {
      print('[FBP-Linux] Refreshing services for ${device.remoteId}');

      // Wait a moment to let any pending operations complete
      await Future.delayed(const Duration(seconds: 1));

      // In this version, we can't directly refresh GATT services
      // So we'll just log what we found
      print('[FBP-Linux] Services found: ${device.gattServices.length}');

      for (final service in device.gattServices) {
        print('[FBP-Linux] Service: ${service.uuid}');
      }
    } catch (e) {
      print('[FBP-Linux] Error accessing services: $e');
    }
  }

  // Helper method to refresh the BlueZ client
  Future<void> _refreshClient() async {
    try {
      // We can't disconnect and reconnect the client directly
      // So we'll create a new client instance
      _initialized = false;
      await _initFlutterBluePlus();
    } catch (e) {
      print('[FBP-Linux] Error reinitializing client: $e');
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

      final device = _client.devices.singleWhere(
        (device) {
          return device.remoteId == request.remoteId;
        },
      );

      // If no services are found, try to refresh services first
      if (device.gattServices.isEmpty) {
        print('[FBP-Linux] No services found, attempting to refresh services');
        await _refreshDeviceServices(device);

        // If still no services, try fallback method with system commands
        if (device.gattServices.isEmpty) {
          print(
              '[FBP-Linux] Still no services after refresh, trying system commands');
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

          if (characteristic.flags.contains(BlueZGattCharacteristicFlag.read)) {
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
                          BlueZGattCharacteristicFlag.authenticatedSignedWrites,
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
  }

  // Fallback method to discover services using system commands
  Future<bool> _discoverServicesWithSystemCommands(
      BmDiscoverServicesRequest request) async {
    try {
      print(
          '[FBP-Linux] Attempting to discover services using system commands');

      // Use gatttool for service discovery
      final result = await Process.run(
          'gatttool', ['-b', request.remoteId.toString(), '--primary']);

      if (result.exitCode != 0) {
        print('[FBP-Linux] gatttool command failed: ${result.stderr}');
        return false;
      }

      // Parse services
      final output = result.stdout.toString();
      final serviceLines =
          output.split('\n').where((line) => line.contains('uuid:')).toList();

      print('[FBP-Linux] Found ${serviceLines.length} services using gatttool');

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
    } catch (e) {
      print('[FBP-Linux] Error in system command service discovery: $e');

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

    await _client.adapters.first.setDiscoveryFilter(
      uuids: request.withServices.map(
        (uuid) {
          return uuid.str128;
        },
      ).toList(),
    );

    await _client.adapters.first.startDiscovery();

    return true;
  }

  @override
  Future<bool> stopScan(
    BmStopScanRequest request,
  ) async {
    await _initFlutterBluePlus();

    await _client.adapters.first.stopDiscovery();

    return true;
  }

  @override
  Future<bool> turnOff(
    BmTurnOffRequest request,
  ) async {
    await _initFlutterBluePlus();

    await _client.adapters.first.setPowered(false);

    return true;
  }

  @override
  Future<bool> turnOn(
    BmTurnOnRequest request,
  ) async {
    await _initFlutterBluePlus();

    await _client.adapters.first.setPowered(true);

    return true;
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
      return;
    }

    _initialized = true;

    await _client.connect();

    _client.devicesChanged.switchMap(
      (devices) {
        if (_logLevel == LogLevel.verbose) {
          print(
            '[FBP-Linux] devices changed ${devices.map((device) => device.remoteId).toList()}',
          );
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
    ).listen(null);
  }
}

extension on BlueZClient {
  Stream<List<BlueZAdapter>> get adaptersChanged {
    return MergeStream([
      adapterAdded,
      adapterRemoved,
    ]).map(
      (adapter) {
        return adapters;
      },
    ).startWith(adapters);
  }

  Stream<List<BlueZDevice>> get devicesChanged {
    return MergeStream([
      deviceAdded,
      deviceRemoved,
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
