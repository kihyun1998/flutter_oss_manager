import 'dart:convert';
import 'dart:io';

/// The `Process.run`-shaped call the probe depends on. Injectable so the
/// probe's parsing and memoization can be tested without a real Flutter.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// The Flutter SDK facts a scan needs, resolved together from one
/// `flutter --version --machine` invocation.
class FlutterSdkInfo {
  const FlutterSdkInfo({required this.root, required this.version});

  final String root;
  final String version;
}

/// Resolves [FlutterSdkInfo], or `null` when Flutter is unavailable.
abstract class FlutterSdkProbe {
  Future<FlutterSdkInfo?> probe();
}

/// Runs `flutter --version --machine` at most once and caches the result.
class ProcessFlutterSdkProbe implements FlutterSdkProbe {
  ProcessFlutterSdkProbe({RunProcess? runProcess})
      : _runProcess = runProcess ?? Process.run;

  final RunProcess _runProcess;

  bool _probed = false;
  FlutterSdkInfo? _cached;

  @override
  Future<FlutterSdkInfo?> probe() async {
    if (_probed) return _cached;
    _probed = true;
    _cached = await _resolve();
    return _cached;
  }

  Future<FlutterSdkInfo?> _resolve() async {
    final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
    try {
      final result = await _runProcess(executable, ['--version', '--machine']);
      if (result.exitCode != 0) return null;
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      return FlutterSdkInfo(
        root: json['flutterRoot'] as String,
        version: json['frameworkVersion'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
