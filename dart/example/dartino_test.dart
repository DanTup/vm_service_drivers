import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';

import 'vm_service_assert.dart';

VmService serviceClient;

main(List<String> args) async {
  if (args.length != 2) {
    print('usage: dart example/dartino_test.dart'
        ' <dartino sdk location> <dartino application location>');
    exit(1);
  }

  String sdkPath = args.first;
  String appPath = args[1];

  print('Using sdk at ${sdkPath}.');

  // flash device
  ProcessResult result = await Process.runSync(
      '${sdkPath}/bin/dartino', ['flash', '--debugging-mode', appPath]);
  if (result.exitCode != 0) throw 'flash failed: $exitCode';

  // launch debug process
  Process process = await Process.start('${sdkPath}/bin/dartino',
      ['debug', 'serve', appPath, 'on', 'tty', '/dev/ttyACM0']);

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

  //await new Future.delayed(new Duration(milliseconds: 500));

  serviceClient = await vmServiceConnect('localhost', await debugPort.future,
      log: new StdoutLog());

  print('socket connected');

  serviceClient.onSend.listen((str) => print('--> ${str}'));
  serviceClient.onReceive.listen((str) => print('<-- ${str}'));

  Completer isolateRunnable = new Completer();
  serviceClient.onIsolateEvent.listen((Event event) {
    print('onIsolateEvent: ${event}');
    assertIsolateEvent(event);
    if (event.kind == EventKind.kIsolateRunnable &&
        !isolateRunnable.isCompleted) {
      isolateRunnable.complete();
    }
  });
  Completer pauseStart = new Completer();
  serviceClient.onDebugEvent.listen((Event event) {
    print('onDebugEvent: ${event}');
    assertDebugEvent(event);
    if (event.kind == EventKind.kPauseStart && !pauseStart.isCompleted) {
      pauseStart.complete();
    }
  });
  // serviceClient.onGCEvent.listen((e) => print('onGCEvent: ${e}'));
  serviceClient.onStdoutEvent.listen((e) => print('onStdoutEvent: ${e}'));
  serviceClient.onStderrEvent.listen((e) => print('onStderrEvent: ${e}'));

  assertSuccess(await serviceClient.streamListen('Isolate'));
  assertSuccess(await serviceClient.streamListen('Debug'));
  assertSuccess(await serviceClient.streamListen('Stdout'));

  await isolateRunnable.future;
  await pauseStart.future;
  print('paused');

  VM vm = assertVM(await serviceClient.getVM());
  print(assertVersion(await serviceClient.getVersion()));
  List<IsolateRef> isolates = assertIsolateRefs(await vm.isolates);
  print(isolates);

  print('resuming');
  IsolateRef isolateRef = isolates.first;
  print(assertSuccess(await serviceClient.resume(isolateRef.id)));

  await new Future.delayed(new Duration(seconds: 2));

  print('pausing');
  print(assertSuccess(await serviceClient.pause(isolateRef.id)));

  serviceClient.dispose();
  process.kill();
}

class StdoutLog extends Log {
  void warning(String message) => print(message);
  void severe(String message) => print(message);
}
