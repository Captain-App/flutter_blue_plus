import 'dart:async';
import 'dart:io';
import 'dart:convert';

/// Utility class for Raspberry Pi specific BLE improvements
///
/// This class provides additional functionality to help with BLE operations
/// on Raspberry Pi OS, which may have different behavior than other Linux distributions.
class RaspberryPiBlueZHelper {
  /// Check if we're running on a Raspberry Pi
  static Future<bool> isRaspberryPi() async {
    try {
      // Check for Raspberry Pi model in /proc/cpuinfo
      final result = await Process.run('grep', ['Model', '/proc/cpuinfo']);
      return result.exitCode == 0 &&
          result.stdout.toString().toLowerCase().contains('raspberry pi');
    } catch (e) {
      print('[RaspberryPi] Error checking for Raspberry Pi: $e');
      return false;
    }
  }

  /// Get the Bluetooth adapter status using system commands
  static Future<Map<String, dynamic>> getAdapterStatus() async {
    final result = await Process.run('hciconfig', ['-a']);
    final output = result.stdout.toString();

    final status = <String, dynamic>{
      'available': result.exitCode == 0 && output.contains('hci'),
      'powered': output.contains('UP RUNNING'),
      'address': _extractAdapterAddress(output),
    };

    return status;
  }

  /// Extract the Bluetooth adapter address from hciconfig output
  static String? _extractAdapterAddress(String output) {
    final regex = RegExp(r'BD Address: ([0-9A-F:]{17})');
    final match = regex.firstMatch(output);
    return match?.group(1);
  }

  /// Reset the Bluetooth adapter using system commands
  static Future<bool> resetAdapter() async {
    try {
      print('[RaspberryPi] Resetting Bluetooth adapter...');

      // Down the adapter
      await Process.run('sudo', ['hciconfig', 'hci0', 'down']);
      await Future.delayed(Duration(milliseconds: 500));

      // Up the adapter
      await Process.run('sudo', ['hciconfig', 'hci0', 'up']);
      await Future.delayed(Duration(milliseconds: 500));

      // Set to scan mode
      await Process.run('sudo', ['hciconfig', 'hci0', 'piscan']);

      // Enable LE advertising
      await Process.run('sudo', ['hciconfig', 'hci0', 'leadv']);

      print('[RaspberryPi] Bluetooth adapter reset complete');
      return true;
    } catch (e) {
      print('[RaspberryPi] Error resetting adapter: $e');
      return false;
    }
  }

  /// Connect to a device using bluetoothctl with extended timeout and retries
  static Future<bool> connectWithBluetoothtcl(String address,
      {int retries = 3, int timeout = 10}) async {
    print('[RaspberryPi] Attempting connection to $address with bluetoothctl');

    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        final connectProcess = await Process.start('bluetoothctl', []);
        final completer = Completer<bool>();

        // Set timeout
        Timer(Duration(seconds: timeout), () {
          if (!completer.isCompleted) {
            print('[RaspberryPi] Connection attempt ${attempt + 1} timed out');
            connectProcess.kill();
            completer.complete(false);
          }
        });

        bool connected = false;
        bool attemptComplete = false;

        // Monitor output
        connectProcess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          print('[RaspberryPi] bluetoothctl: $line');

          if (line.contains('Connection successful') ||
              line.contains('already connected')) {
            connected = true;
            attemptComplete = true;
          } else if (line.contains('Failed to connect')) {
            connected = false;
            attemptComplete = true;
          }

          if (attemptComplete && !completer.isCompleted) {
            completer.complete(connected);
          }
        });

        // Send commands
        connectProcess.stdin.writeln('remove $address');
        await Future.delayed(Duration(milliseconds: 500));
        connectProcess.stdin.writeln('scan on');
        await Future.delayed(Duration(seconds: 2));
        connectProcess.stdin.writeln('scan off');
        await Future.delayed(Duration(milliseconds: 500));
        connectProcess.stdin.writeln('pair $address');
        await Future.delayed(Duration(seconds: 3));
        connectProcess.stdin.writeln('connect $address');

        // Wait for result
        final result = await completer.future;

        if (!attemptComplete) {
          connectProcess.stdin.writeln('quit');
        }

        if (result) {
          print(
              '[RaspberryPi] bluetoothctl connection successful on attempt ${attempt + 1}');
          return true;
        } else {
          print(
              '[RaspberryPi] bluetoothctl connection failed on attempt ${attempt + 1}');

          // Wait before retrying
          if (attempt < retries - 1) {
            await Future.delayed(Duration(seconds: 2));
          }
        }
      } catch (e) {
        print(
            '[RaspberryPi] Error during bluetoothctl connection attempt ${attempt + 1}: $e');

        // Wait before retrying
        if (attempt < retries - 1) {
          await Future.delayed(Duration(seconds: 2));
        }
      }
    }

    return false;
  }

  /// Discover services using gatttool
  static Future<List<Map<String, dynamic>>> discoverServicesWithGatttool(
      String address) async {
    print('[RaspberryPi] Discovering services for $address with gatttool');

    final services = <Map<String, dynamic>>[];

    try {
      // First try to connect with gatttool
      final connectResult = await Process.run(
          'timeout', ['5', 'gatttool', '-b', address, '-I'],
          runInShell: true);

      // Then discover primary services
      final primaryResult = await Process.run(
          'timeout', ['5', 'gatttool', '-b', address, '--primary'],
          runInShell: true);

      if (primaryResult.exitCode == 0) {
        final lines = primaryResult.stdout.toString().split('\n');

        for (final line in lines) {
          if (line.contains('uuid:')) {
            // Parse the service UUID
            final uuidMatch = RegExp(r'uuid: ([0-9a-f-]+)').firstMatch(line);
            if (uuidMatch != null) {
              final uuid = uuidMatch.group(1);

              // Parse the handle range
              final handleMatch = RegExp(
                      r'attr handle: (0x[0-9a-f]+), end grp handle: (0x[0-9a-f]+)')
                  .firstMatch(line);
              final startHandle = handleMatch?.group(1);
              final endHandle = handleMatch?.group(2);

              if (uuid != null) {
                services.add({
                  'uuid': uuid,
                  'startHandle': startHandle,
                  'endHandle': endHandle,
                });
              }
            }
          }
        }
      }

      // If no services found, try bluetoothctl info as fallback
      if (services.isEmpty) {
        final infoResult = await Process.run('bluetoothctl', ['info', address]);

        if (infoResult.exitCode == 0) {
          final lines = infoResult.stdout.toString().split('\n');

          for (final line in lines) {
            if (line.contains('UUID:')) {
              final uuidMatch = RegExp(r'UUID: ([0-9a-f-]+)').firstMatch(line);
              if (uuidMatch != null) {
                final uuid = uuidMatch.group(1);
                if (uuid != null) {
                  services.add({
                    'uuid': uuid,
                    'fromBluetoothtcl': true,
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[RaspberryPi] Error discovering services: $e');
    }

    print('[RaspberryPi] Discovered ${services.length} services');
    return services;
  }

  /// Check if D-Bus is properly configured
  static Future<bool> checkDBusConfiguration() async {
    try {
      // Check if D-Bus session is running
      final sessionBus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
      if (sessionBus == null || sessionBus.isEmpty) {
        print('[RaspberryPi] Warning: DBUS_SESSION_BUS_ADDRESS not set');
        return false;
      }

      // Test D-Bus connection
      final result = await Process.run('dbus-send', [
        '--session',
        '--dest=org.freedesktop.DBus',
        '--type=method_call',
        '--print-reply',
        '/org/freedesktop/DBus',
        'org.freedesktop.DBus.ListNames'
      ]);

      return result.exitCode == 0;
    } catch (e) {
      print('[RaspberryPi] Error checking D-Bus configuration: $e');
      return false;
    }
  }

  /// Start a D-Bus session if one is not already running
  static Future<bool> startDBusSession() async {
    try {
      final result = await Process.run('dbus-launch', ['--sh-syntax']);

      if (result.exitCode == 0) {
        // Parse the output to get the environment variables
        final output = result.stdout.toString();
        final addressMatch =
            RegExp(r'DBUS_SESSION_BUS_ADDRESS=([^;]+);').firstMatch(output);
        final pidMatch =
            RegExp(r'DBUS_SESSION_BUS_PID=([0-9]+);').firstMatch(output);

        if (addressMatch != null) {
          final address = addressMatch.group(1);
          if (address != null) {
            // Set the environment variable
            Platform.environment['DBUS_SESSION_BUS_ADDRESS'] = address;
            print('[RaspberryPi] Started D-Bus session: $address');
            return true;
          }
        }
      }

      print('[RaspberryPi] Failed to start D-Bus session');
      return false;
    } catch (e) {
      print('[RaspberryPi] Error starting D-Bus session: $e');
      return false;
    }
  }
}
