import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/terminal_launcher.dart';

void main() {
  group('buildTerminalInvocation', () {
    test('gnome-terminal opens at the working directory', () {
      final invocation = buildTerminalInvocation(
        terminalId: 'gnome-terminal',
        executable: '/usr/bin/gnome-terminal',
        workingDirectory: '/home/user/proj',
      );

      expect(invocation.executable, '/usr/bin/gnome-terminal');
      expect(invocation.arguments, ['--working-directory=/home/user/proj']);
      expect(invocation.workingDirectory, '/home/user/proj');
    });

    test('gnome-terminal runs a command after --', () {
      final invocation = buildTerminalInvocation(
        terminalId: 'gnome-terminal',
        executable: '/usr/bin/gnome-terminal',
        workingDirectory: '/tmp',
        command: 'bash /tmp/script.sh',
      );

      expect(invocation.arguments, [
        '--working-directory=/tmp',
        '--',
        'bash',
        '-c',
        'bash /tmp/script.sh',
      ]);
    });

    test('kitty, konsole, and x-terminal-emulator use their cwd flags', () {
      expect(
        buildTerminalInvocation(
          terminalId: 'kitty',
          executable: 'kitty',
          workingDirectory: '/a',
        ).arguments,
        ['--directory', '/a'],
      );
      expect(
        buildTerminalInvocation(
          terminalId: 'konsole',
          executable: 'konsole',
          workingDirectory: '/a',
          command: 'ls',
        ).arguments,
        ['--workdir', '/a', '-e', 'bash', '-c', 'ls'],
      );
      expect(
        buildTerminalInvocation(
          terminalId: 'x-terminal-emulator',
          executable: 'x-terminal-emulator',
          workingDirectory: '/a',
          command: 'ls',
        ).arguments,
        ['-e', 'bash', '-c', 'ls'],
      );
    });

    test('macOS Terminal uses open -a for a directory', () {
      final invocation = buildTerminalInvocation(
        terminalId: 'Terminal',
        executable: '/usr/bin/open',
        workingDirectory: '/Users/me',
      );
      expect(invocation.arguments, ['-a', 'Terminal', '/Users/me']);
    });

    test('Windows Terminal and cmd open at the given directory', () {
      expect(
        buildTerminalInvocation(
          terminalId: 'wt',
          executable: 'wt',
          workingDirectory: r'C:\src',
        ).arguments,
        ['-d', r'C:\src'],
      );
      expect(
        buildTerminalInvocation(
          terminalId: 'cmd',
          executable: 'cmd',
          workingDirectory: r'C:\src',
          command: 'dir',
        ).arguments,
        ['/k', 'dir'],
      );
    });
  });

  group('hold commands', () {
    test('posix quoting survives spaces and single quotes', () {
      expect(
        posixHoldCommand('python3', "/tmp/it's a file.py"),
        "python3 '/tmp/it'\\''s a file.py'; echo; read -p \"Process finished. Press Enter to close...\"",
      );
    });
  });

  group('TerminalLauncher.detectAvailable', () {
    test('returns Linux emulators whose commands resolve', () async {
      final launcher = TerminalLauncher(
        isLinux: true,
        isMacOS: false,
        isWindows: false,
        resolveCommand: (cmd) async {
          if (cmd == 'kitty' || cmd == 'konsole') return '/usr/bin/$cmd';
          return null;
        },
        startProcess: (exe, args, {workingDirectory}) async {},
      );

      final found = await launcher.detectAvailable();
      expect(found.map((t) => t.id).toList(), ['kitty', 'konsole']);
    });

    test('macOS returns Terminal when open is on PATH', () async {
      final launcher = TerminalLauncher(
        isLinux: false,
        isMacOS: true,
        isWindows: false,
        resolveCommand: (cmd) async => cmd == 'open' ? '/usr/bin/open' : null,
        startProcess: (exe, args, {workingDirectory}) async {},
      );

      final found = await launcher.detectAvailable();
      expect(found, [
        const TerminalApp(
            id: 'Terminal', name: 'Terminal', executable: '/usr/bin/open'),
      ]);
    });
  });
}
