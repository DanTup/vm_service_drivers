import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';

import 'vm_service_assert.dart';

main(List<String> args) async {
  DartinoDebugTest test = new DartinoDebugTest();
  test.parseArgs(args);
  await test.quit();
  // await test.downloadTools();
  await test.flashIfNecessary();
  try {
    await test.startDebugSession();

    String bpId = await test.addBreakpoint(line: test.breakpointLine);
    for (int count = 0; count < 2; ++count) {
      await test.resume();
      await test.resumed();
      Event event = await test.paused();
      if (event.kind != EventKind.kPauseBreakpoint) throw 'incorrect event';
      await test.verifyFrame(test.lastTopFrame);
      await test.verifyStack();
      await new Future.delayed(new Duration(milliseconds: 20));
    }
    await test.removeBreakpoint(bpId);

    for (int count = 0; count < 2; ++count) {
      await test.resume();
      await test.resumed();
      await new Future.delayed(new Duration(milliseconds: 20));
      test.pause();
      Event event = await test.paused();
      if (event.kind != EventKind.kPauseInterrupted) throw 'incorrect event';
      if (test.lastTopFrame != null) {
        await test.verifyFrame(test.lastTopFrame);
      }
      await test.verifyStack();
    }

    print('test complete');
  } finally {
    await test.quit();
  }
}

class DartinoDebugTest {
  String sdkPath;
  String appPath;
  String dartinoPath;
  int breakpointLine;
  String ttyPath;

  VmService serviceClient;
  List<IsolateRef> _isolateRefs;
  String _mainScriptUri;

  Completer _paused;
  Event _lastPauseEvent;
  Completer _resumed;
  Event _lastResumeEvent;
  Frame lastTopFrame;

  void parseArgs(List<String> args) {
    showHelpAndExit([String message]) {
      if (message != null) print(message);
      print('Usage: dart example/dartino_test.dart'
          ' </path/to/dartino/sdk> </path/to/dartino/app.dart>'
          '<breakpoint-line-number> [on tty </dev/tty-path>]');
      exit(1);
    }
    int index = 0;
    String next(String expected) {
      if (index == args.length) showHelpAndExit('Expected $expected');
      return args[index++];
    }
    int nextInt(String expected) {
      return int.parse(next(expected), onError: (String text) {
        showHelpAndExit('Expected $expected but found "$text"');
      });
    }
    expect(String expected) {
      String text = next('"$expected"');
      if (text != expected) {
        showHelpAndExit('Expected "$expected" but found "$text"');
      }
    }
    sdkPath = next('sdk path');
    appPath = next('application path');
    dartinoPath = '${sdkPath}/bin/dartino';
    breakpointLine = nextInt('breakpoint line number');
    if (index == args.length) return;
    expect('on');
    expect('tty');
    ttyPath = next('tty path');
    if (!ttyPath.startsWith('/dev/tty')) {
      showHelpAndExit('expected tty path but found "${args[4]}"');
    }
    if (index == args.length) return;
    showHelpAndExit('too many arguments');
  }

  downloadTools() => run(dartinoPath, ['x-download-tools']);
  flashIfNecessary() {
    if (ttyPath == null) return null;
    return run(dartinoPath, ['flash', '--debugging-mode', appPath]);
  }
  quit() {
    serviceClient?.dispose();
    serviceClient = null;
    return run(dartinoPath, ['quit']);
  }

  /// Request that the VM pause.
  /// Return a future that completes when the request completes.
  pause({String isolateId}) async {
    _resumed = new Completer();
    assertSuccess(
        await serviceClient.pause(isolateId ?? await mainIsolateId()));
  }

  /// Return a future that completes when a "Pause*" event is received.
  Future<Event> paused() async =>
      _paused != null ? _paused.future : _lastPauseEvent;

  /// Request that the VM pause.
  /// Return a future that completes when the request completes.
  resume([String isolateId]) async {
    _paused = new Completer();
    assertSuccess(
        await serviceClient.resume(isolateId ?? await mainIsolateId()));
  }

  /// Return a future that completes when a "Resume" event is received.
  Future<Event> resumed() async =>
      _resumed != null ? _resumed.future : _lastResumeEvent;

  /// Start the debugging process and connect to the debugger.
  /// Return a future that completes when connected.
  startDebugSession() async {
    var args = ['debug', 'serve', appPath];
    if (ttyPath != null) args.addAll(['on', 'tty', ttyPath]);
    Process process = await start(dartinoPath, args);

    print('dartino process started');

    Completer<int> debugPort = new Completer<int>();
    process.exitCode.then((code) => print('vm exited: ${code}'));
    // ignore: strong_mode_down_cast_composite
    process.stdout.transform(UTF8.decoder).listen((String text) {
      print(text);
      if (text.startsWith('localhost:')) {
        if (!debugPort.isCompleted) {
          debugPort.complete(int.parse(text.substring(10).trim()));
        }
      }
    });
    // ignore: strong_mode_down_cast_composite
    process.stderr.transform(UTF8.decoder).listen(print);

    serviceClient = await vmServiceConnect('localhost', await debugPort.future,
        log: new StdoutLog());

    print('debug session started');

    serviceClient.onSend.listen((str) => print('--> ${str}'));
    serviceClient.onReceive.listen((str) => print('<-- ${str}'));

    serviceClient.onIsolateEvent.listen(_handleIsolateEvent);
    serviceClient.onDebugEvent.listen(_handleDebugEvent);
    // serviceClient.onGCEvent.listen((e) => print('onGCEvent: ${e}'));
    serviceClient.onStdoutEvent.listen((e) => print('<-- stdout: ${e}'));
    serviceClient.onStderrEvent.listen((e) => print('<-- stderr: ${e}'));

    assertSuccess(await serviceClient.streamListen('Isolate'));
    assertSuccess(await serviceClient.streamListen('Debug'));
    assertSuccess(await serviceClient.streamListen('Stdout'));

    print('connected to debug session');
  }

  /// Set a breakpoint on the given line.
  /// Return a future that completes with the breakpoint id.
  Future<String> addBreakpoint(
      {String isolateId, String scriptId, String scriptUri, int line}) async {
    if (line == null) throw 'must specify line number';
    Breakpoint bp;
    if (scriptId != null) {
      bp = await serviceClient.addBreakpoint(
          isolateId ?? await mainIsolateId(), scriptId, line);
    } else {
      bp = await serviceClient.addBreakpointWithScriptUri(
          isolateId ?? await mainIsolateId(),
          scriptUri ?? await mainScriptUri(),
          line);
    }
    return assertBreakpoint(bp).id;
  }

  removeBreakpoint(String breakpointId, {String isolateId}) async {
    assertSuccess(
        await serviceClient.removeBreakpoint(isolateId, breakpointId));
  }

  Future<List<IsolateRef>> isolateRefs() async {
    if (_isolateRefs == null) {
      VM vm = assertVM(await serviceClient.getVM());
      Version version = assertVersion(await serviceClient.getVersion());
      print('VM Version is $version');
      _isolateRefs = assertIsolateRefs(await vm.isolates);
      print('Current isolates: $_isolateRefs');
    }
    return _isolateRefs;
  }

  Future<String> mainIsolateId() async {
    return (await isolateRefs())[0].id;
  }

  Future<String> mainScriptUri() async {
    if (_mainScriptUri == null) {
      String isolateId = await mainIsolateId();
      Isolate isolate =
          assertIsolate(await serviceClient.getIsolate(isolateId));
      Library library = assertLibrary(
          await serviceClient.getObject(isolateId, isolate.libraries[0].id));
      _mainScriptUri = library.uri;
      print('main script uri is $_mainScriptUri');
    }
    return _mainScriptUri;
  }

  verifyInstanceRef(InstanceRef ref, {String isolateId}) async {
    assertInstance(await serviceClient.getObject(
        isolateId ?? await mainIsolateId(), ref.id));
  }

  verifyFrame(Frame frame, {String isolateId}) async {
    assertFrame(frame);
    await verifyVariables(frame.vars, isolateId: isolateId);
  }

  verifyStack({String isolateId}) async {
    Stack stack = assertStack(
        await serviceClient.getStack(isolateId ?? await mainIsolateId()));
    for (Frame frame in stack.frames) {
      await verifyFrame(frame);
    }
  }

  verifyVariable(var variable, {String isolateId}) async {
    if (variable is BoundVariable) {
      assertBoundVariable(variable);
      var valueRef = variable.value;
      if (valueRef is InstanceRef) {
        await verifyInstanceRef(valueRef, isolateId: isolateId);
      } else if (valueRef is Sentinel) {
        assertSentinel(valueRef);
      } else {
        throw 'Unknown value reference: $valueRef';
      }
    } else {
      throw 'Unknown var type: $variable';
    }
  }

  verifyVariables(List list, {String isolateId}) async {
    for (var each in list) {
      await verifyVariable(each, isolateId: isolateId);
    }
  }

  _handleDebugEvent(Event event) {
    print('<-- debug event: ${event}');
    assertDebugEvent(event);
    if (event.kind.startsWith('Pause')) {
      _paused?.complete(event);
      _paused = null;
      lastTopFrame = event.topFrame;
      _lastPauseEvent = event;
    }
    if (event.kind == EventKind.kResume) {
      _resumed?.complete(event);
      _resumed = null;
      _lastResumeEvent = event;
    }
  }

  _handleIsolateEvent(Event event) {
    print('<-- isolate event: ${event}');
    assertIsolateEvent(event);
  }
}

/// Launch the specified process
/// and return a Future that completes when the process terminates.
/// Throw an exception if the process terminates with non-zero exit code.
Future run(String appPath, List<String> args) async {
  String cmdline = '$appPath ${args.join(' ')}';
  print('Running $cmdline');
  ProcessResult result = await Process.runSync(appPath, args);
  if (result.exitCode != 0) {
    throw 'Process failed with exit code: ${result.exitCode}'
        '\n$appPath\n${result.stderr}\n${result.stdout}';
  }
}

/// Launch and return the specified process
Future<Process> start(String appPath, List<String> args) async {
  String cmdline = '$appPath ${args.join(' ')}';
  print('Starting $cmdline');
  return await Process.start(appPath, args);
}

class StdoutLog extends Log {
  void warning(String message) => print(message);
  void severe(String message) => print(message);
}
