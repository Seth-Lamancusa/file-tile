import 'dart:io';

/// A terminal emulator File Tile can spawn.
class TerminalApp {
  final String id;
  final String name;
  final String executable;

  const TerminalApp({
    required this.id,
    required this.name,
    required this.executable,
  });

  @override
  bool operator ==(Object other) =>
      other is TerminalApp &&
      other.id == id &&
      other.name == name &&
      other.executable == executable;

  @override
  int get hashCode => Object.hash(id, name, executable);
}

/// Process arguments for opening a terminal or running a command in one.
class TerminalInvocation {
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  const TerminalInvocation({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });
}

class _TerminalSpec {
  final String id;
  final String name;
  final String command;

  const _TerminalSpec({
    required this.id,
    required this.name,
    required this.command,
  });
}

const _linuxTerminalSpecs = [
  _TerminalSpec(
      id: 'gnome-terminal', name: 'GNOME Terminal', command: 'gnome-terminal'),
  _TerminalSpec(id: 'kitty', name: 'kitty', command: 'kitty'),
  _TerminalSpec(id: 'konsole', name: 'Konsole', command: 'konsole'),
  _TerminalSpec(
      id: 'x-terminal-emulator',
      name: 'X Terminal Emulator',
      command: 'x-terminal-emulator'),
];

const macOsTerminalId = 'Terminal';
const windowsTerminalId = 'wt';
const windowsCmdId = 'cmd';

String _appleScriptEscape(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String posixSingleQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String windowsQuote(String value) => '"${value.replaceAll('"', '\\"')}"';

/// Builds the argv used to spawn [terminalId] at [workingDirectory].
///
/// [command] is an already-formatted shell snippet to run inside the
/// emulator. When null, the emulator opens an interactive shell at that
/// directory.
TerminalInvocation buildTerminalInvocation({
  required String terminalId,
  required String executable,
  required String workingDirectory,
  String? command,
}) {
  switch (terminalId) {
    case 'gnome-terminal':
      return TerminalInvocation(
        executable: executable,
        arguments: [
          '--working-directory=$workingDirectory',
          if (command != null) ...['--', 'bash', '-c', command],
        ],
        workingDirectory: workingDirectory,
      );
    case 'kitty':
      return TerminalInvocation(
        executable: executable,
        arguments: [
          '--directory',
          workingDirectory,
          if (command != null) ...['bash', '-c', command],
        ],
        workingDirectory: workingDirectory,
      );
    case 'konsole':
      return TerminalInvocation(
        executable: executable,
        arguments: [
          '--workdir',
          workingDirectory,
          if (command != null) ...['-e', 'bash', '-c', command],
        ],
        workingDirectory: workingDirectory,
      );
    case 'x-terminal-emulator':
      return TerminalInvocation(
        executable: executable,
        arguments: [
          if (command != null) ...['-e', 'bash', '-c', command],
        ],
        workingDirectory: workingDirectory,
      );
    case macOsTerminalId:
      if (command == null) {
        return TerminalInvocation(
          executable: executable,
          arguments: ['-a', 'Terminal', workingDirectory],
          workingDirectory: workingDirectory,
        );
      }
      final inner = 'cd ${posixSingleQuote(workingDirectory)} && $command';
      final script =
          'tell application "Terminal" to do script "${_appleScriptEscape(inner)}"';
      return TerminalInvocation(
        executable: 'osascript',
        arguments: ['-e', script],
        workingDirectory: workingDirectory,
      );
    case windowsTerminalId:
      return TerminalInvocation(
        executable: executable,
        arguments: [
          '-d',
          workingDirectory,
          if (command != null) ...['cmd', '/k', command],
        ],
        workingDirectory: workingDirectory,
      );
    case windowsCmdId:
      return TerminalInvocation(
        executable: executable,
        arguments: command == null ? const ['/k'] : ['/k', command],
        workingDirectory: workingDirectory,
      );
    default:
      throw ArgumentError('Unknown terminal id: $terminalId');
  }
}

String posixHoldCommand(String tool, String filePath) =>
    '$tool ${posixSingleQuote(filePath)}; echo; read -p "Process finished. Press Enter to close..."';

String windowsHoldCommand(String tool, String filePath) =>
    '$tool ${windowsQuote(filePath)} & echo. & pause';

/// Discovers and launches terminal emulators.
class TerminalLauncher {
  final bool isLinux;
  final bool isMacOS;
  final bool isWindows;
  final Future<String?> Function(String command) resolveCommand;
  final Future<void> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) startProcess;

  TerminalLauncher({
    bool? isLinux,
    bool? isMacOS,
    bool? isWindows,
    Future<String?> Function(String command)? resolveCommand,
    Future<void> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })? startProcess,
  })  : isLinux = isLinux ?? Platform.isLinux,
        isMacOS = isMacOS ?? Platform.isMacOS,
        isWindows = isWindows ?? Platform.isWindows,
        resolveCommand = resolveCommand ?? _resolveCommandOnPath,
        startProcess = startProcess ?? _startProcess;

  Future<List<TerminalApp>> detectAvailable() async {
    if (isLinux) {
      final found = <TerminalApp>[];
      for (final spec in _linuxTerminalSpecs) {
        final executable = await resolveCommand(spec.command);
        if (executable != null) {
          found.add(TerminalApp(
            id: spec.id,
            name: spec.name,
            executable: executable,
          ));
        }
      }
      return found;
    }
    if (isMacOS) {
      final openExec = await resolveCommand('open');
      if (openExec == null) return const [];
      return [
        TerminalApp(
            id: macOsTerminalId, name: 'Terminal', executable: openExec),
      ];
    }
    if (isWindows) {
      final found = <TerminalApp>[];
      final wt = await resolveCommand('wt');
      if (wt != null) {
        found.add(TerminalApp(
          id: windowsTerminalId,
          name: 'Windows Terminal',
          executable: wt,
        ));
      }
      final cmd = await resolveCommand('cmd');
      if (cmd != null) {
        found.add(TerminalApp(
          id: windowsCmdId,
          name: 'Command Prompt',
          executable: cmd,
        ));
      }
      return found;
    }
    return const [];
  }

  Future<void> openShell({
    required TerminalApp app,
    required String workingDirectory,
  }) {
    final invocation = buildTerminalInvocation(
      terminalId: app.id,
      executable: app.executable,
      workingDirectory: workingDirectory,
    );
    return startProcess(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
    );
  }

  Future<void> runTool({
    required TerminalApp app,
    required String workingDirectory,
    required String tool,
    required String filePath,
  }) {
    final command = isWindows
        ? windowsHoldCommand(tool, filePath)
        : posixHoldCommand(tool, filePath);
    final invocation = buildTerminalInvocation(
      terminalId: app.id,
      executable: app.executable,
      workingDirectory: workingDirectory,
      command: command,
    );
    return startProcess(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
    );
  }
}

Future<String?> _resolveCommandOnPath(String command) async {
  try {
    final environment = Map<String, String>.from(Platform.environment);
    if (!Platform.isWindows) {
      final home = environment['HOME'];
      final extras = <String>[
        '/usr/bin',
        '/usr/local/bin',
        if (home != null) '$home/.local/bin',
      ];
      final existing = environment['PATH'] ?? '';
      environment['PATH'] = [...extras, existing].join(':');
    }
    final result = Platform.isWindows
        ? await Process.run('where', [command], environment: environment)
        : await Process.run('which', [command], environment: environment);
    if (result.exitCode != 0) return _fallbackAbsolutePath(command);
    final line = result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
    if (line.isEmpty) return _fallbackAbsolutePath(command);
    return line;
  } catch (_) {
    return _fallbackAbsolutePath(command);
  }
}

Future<String?> _fallbackAbsolutePath(String command) async {
  if (Platform.isWindows) {
    if (command == 'cmd') {
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final path = '$systemRoot\\System32\\cmd.exe';
      if (await File(path).exists()) return path;
    }
    return null;
  }
  final home = Platform.environment['HOME'];
  final candidates = <String>[
    '/usr/bin/$command',
    '/usr/local/bin/$command',
    if (home != null) '$home/.local/bin/$command',
  ];
  for (final path in candidates) {
    if (await File(path).exists()) return path;
  }
  return null;
}

Future<void> _startProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.detached,
  );
}
