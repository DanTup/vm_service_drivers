/*
 * Copyright (c) 2015, the Dart project authors.
 *
 * Licensed under the Eclipse Public License v1.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 */
package org.dartlang.vm.service.element;

// This is a generated file.

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.math.BigDecimal;

/**
 * An [Isolate] object provides information about one isolate in the VM.
 */
public class Isolate extends Response {

  public Isolate(JsonObject json) {
    super(json);
  }

  /**
   * A list of all breakpoints for this isolate.
   */
  public ElementList<Breakpoint> getBreakpoints() {
    return new ElementList<Breakpoint>(json.get("breakpoints").getAsJsonArray()) {
      @Override
      protected Breakpoint basicGet(JsonArray array, int index) {
        return new Breakpoint(array.get(index).getAsJsonObject());
      }
    };
  }

  /**
   * The entry function for this isolate. Guaranteed to be initialized when the IsolateRunnable
   * event fires.
   */
  public FuncRef getEntry() {
    return new FuncRef((JsonObject) json.get("entry"));
  }

  /**
   * The error that is causing this isolate to exit, if applicable.
   */
  public Error getError() {
    return new Error((JsonObject) json.get("error"));
  }

  /**
   * The id which is passed to the getIsolate RPC to reload this isolate.
   */
  public String getId() {
    return json.get("id").getAsString();
  }

  /**
   * A list of all libraries for this isolate. Guaranteed to be initialized when the
   * IsolateRunnable event fires.
   */
  public ElementList<LibraryRef> getLibraries() {
    return new ElementList<LibraryRef>(json.get("libraries").getAsJsonArray()) {
      @Override
      protected LibraryRef basicGet(JsonArray array, int index) {
        return new LibraryRef(array.get(index).getAsJsonObject());
      }
    };
  }

  /**
   * The number of live ports for this isolate.
   */
  public int getLivePorts() {
    return json.get("livePorts").getAsInt();
  }

  /**
   * A name identifying this isolate. Not guaranteed to be unique.
   */
  public String getName() {
    return json.get("name").getAsString();
  }

  /**
   * A numeric id for this isolate, represented as a string. Unique.
   */
  public String getNumber() {
    return json.get("number").getAsString();
  }

  /**
   * The last pause event delivered to the isolate. If the isolate is running, this will be a
   * resume event.
   */
  public Event getPauseEvent() {
    return new Event((JsonObject) json.get("pauseEvent"));
  }

  /**
   * Will this isolate pause when exiting?
   */
  public boolean getPauseOnExit() {
    return json.get("pauseOnExit").getAsBoolean();
  }

  /**
   * The root library for this isolate. Guaranteed to be initialized when the IsolateRunnable event
   * fires.
   */
  public LibraryRef getRootLib() {
    return new LibraryRef((JsonObject) json.get("rootLib"));
  }

  /**
   * The time that the VM started in milliseconds since the epoch. Suitable to pass to
   * DateTime.fromMillisecondsSinceEpoch.
   */
  public BigDecimal getStartTime() {
    return json.get("startTime").getAsBigDecimal();
  }
}
