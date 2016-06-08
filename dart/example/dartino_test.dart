import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';

import 'vm_service_assert.dart';

main(List<String> args) async {
  if (args.length != 2) {
    print('usage: dart example/dartino_test.dart'
        ' </path/to/dartino/sdk> </path/to/dartino/samples/lines.dart>');
    exit(1);
  }
  DartinoDebugTest test = new DartinoDebugTest(args[0], args[1]);
  await test.quit();
  // await test.downloadTools();
  await test.flash();
  try {
    await test.startDebugSession();
    String bpId = await test.addBreakpoint(line: 85);
    for (int count = 0; count < 20; ++count) {
      await test.resume();
      Event event = await test.paused();
      if (event.kind != EventKind.kPauseBreakpoint) throw 'incorrect event';
      await test.verifyFrame(test.lastTopFrame);
      await test.verifyStack();
      await new Future.delayed(new Duration(milliseconds: 250));
    }
    await test.removeBreakpoint(bpId);
    for (int count = 0; count < 20; ++count) {
      await test.resume();
      await new Future.delayed(new Duration(milliseconds: 250));
      test.pause();
      Event event = await test.paused();
      if (event.kind != EventKind.kPauseInterrupted) throw 'incorrect event';
      if (test.lastTopFrame != null) {
        await test.verifyFrame(test.lastTopFrame);
      }
      await test.verifyStack();
    }
  } finally {
    await test.quit();
  }
}

class DartinoDebugTest {
  String sdkPath;
  String appPath;
  String dartinoPath;

  VmService serviceClient;
  List<IsolateRef> _isolateRefs;
  String _mainScriptUri;

  Completer _paused;
  Event _lastPauseEvent;
  Frame lastTopFrame;

  DartinoDebugTest(String sdkPath, this.appPath)
      : this.sdkPath = sdkPath,
        this.dartinoPath = '${sdkPath}/bin/dartino';

  downloadTools() => run(dartinoPath, ['x-download-tools']);
  flash() => run(dartinoPath, ['flash', '--debugging-mode', appPath]);
  quit() {
    serviceClient?.dispose();
    serviceClient = null;
    return run(dartinoPath, ['quit']);
  }

  /// Request that the VM pause.
  /// Return a future that completes when the request completes.
  pause({String isolateId}) async {
    assertSuccess(
        await serviceClient.pause(isolateId ?? await mainIsolateId()));
  }

  /// Return a future that completes when a "Pause*" event is received
  /// or `null` if already paused and not yet resumed.
  Future<Event> paused() async =>
      _paused != null ? _paused.future : _lastPauseEvent;

  /// Start the debugging process and connect to the debugger.
  /// Return a future that completes when connected.
  startDebugSession() async {
    Process process = await start(
        dartinoPath, ['debug', 'serve', appPath, 'on', 'tty', '/dev/ttyACM0']);

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

    serviceClient.onIsolateEvent.listen((Event event) {
      print('<-- isolate event: ${event}');
      assertIsolateEvent(event);
    });
    serviceClient.onDebugEvent.listen((Event event) {
      print('<-- debug event: ${event}');
      assertDebugEvent(event);
      if (event.kind.startsWith('Pause')) {
        _paused?.complete(event);
        lastTopFrame = event.topFrame;
        _lastPauseEvent = event;
      }
    });
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

  resume([String isolateId]) async {
    _paused = new Completer();
    assertSuccess(
        await serviceClient.resume(isolateId ?? await mainIsolateId()));
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
