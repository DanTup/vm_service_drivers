// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'vm_service_lib.dart';

Future<VmService> vmServiceConnect(String host, int port, {Log log}) {
  return WebSocket.connect('ws://$host:$port/ws').then((WebSocket socket) {
    StreamController<String> controller = new StreamController();
    socket.listen((data) => controller.add(data));

    return new VmService(
        controller.stream, (String message) => socket.add(message),
        log: log, disposeHandler: () => socket.close());
  });
}
