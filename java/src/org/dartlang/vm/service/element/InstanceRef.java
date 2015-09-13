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

import com.google.gson.JsonObject;

/**
 * [InstanceRef] is a reference to an [Instance].
 */
public class InstanceRef extends Element {

  public InstanceRef(JsonObject json) {
    super(json);
  }

  /**
   * Instance references always include their class.
   */
  public ClassRef getClassRef() {
    return new ClassRef((JsonObject) json.get("class"));
  }

  /**
   * The id of this instance.
   */
  public String getId() {
    return json.get("id").getAsString();
  }

  /**
   * What kind of instance is this?
   */
  public InstanceKind getKind() {
    return InstanceKind.valueOf(json.get("kind").getAsString());
  }

  /**
   * The length of a List instance. Provided for instance kinds: List Map Uint8ClampedList
   * Uint8List Uint16List Uint32List Uint64List Int8List Int16List Int32List Int64List Float32List
   * Float64List Int32x4List Float32x4List Float64x2List
   */
  public int getLength() {
    return json.get("length").getAsInt();
  }

  /**
   * The name of a Type instance. Provided for instance kinds: Type
   */
  public String getName() {
    return json.get("name").getAsString();
  }

  /**
   * The parameterized class of a type parameter: Provided for instance kinds: TypeParameter
   */
  public ClassRef getParameterizedClass() {
    return new ClassRef((JsonObject) json.get("parameterizedClass"));
  }

  /**
   * The pattern of a RegExp instance. Provided for instance kinds: RegExp
   */
  public String getPattern() {
    return json.get("pattern").getAsString();
  }

  /**
   * The corresponding Class if this Type is canonical. Provided for instance kinds: Type
   */
  public ClassRef getTypeClass() {
    return new ClassRef((JsonObject) json.get("typeClass"));
  }

  /**
   * The value of this instance as a string. Provided for the instance kinds: Null (null) Bool
   * (true or false) Double (suitable for passing to Double.parse()) Int (suitable for passing to
   * int.parse()) String (value may be truncated) Float32x4 Float64x2 Int32x4 StackTrace
   */
  public String getValueAsString() {
    return json.get("valueAsString").getAsString();
  }

  /**
   * The valueAsString for String references may be truncated. If so, this property is added with
   * the value 'true'.
   */
  public boolean getValueAsStringIsTruncated() {
    return json.get("valueAsStringIsTruncated").getAsBoolean();
  }
}
