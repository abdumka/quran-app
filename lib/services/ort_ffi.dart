import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The slice of the ONNX Runtime C API that `ZipformerPosterior` needs,
/// bound by hand over `OrtGetApiBase`. The function table is append-only,
/// so the slot numbers below (the order of `struct OrtApi` in
/// onnxruntime_c_api.h since 1.0) hold for every runtime version that
/// answers [OrtApi.load].
///
/// Android: `libonnxruntime.so` ships inside the sherpa_onnx plugin, so no
/// new binary is added. Windows (tests): the DLL of the Python package.
/// iOS: sherpa's static framework does not export the symbol; [OrtApi.load]
/// returns null there and the caller keeps the plain re-decode.
class OrtApi {
  OrtApi._(this._api, this.version);

  final Pointer<Pointer<Void>> _api;

  /// Runtime version string, e.g. `1.17.1`.
  final String version;

  /// Highest API version the runtime answers, tried from 22 down.
  static OrtApi? load({String? libraryPath}) {
    DynamicLibrary lib;
    try {
      if (libraryPath != null) {
        lib = DynamicLibrary.open(libraryPath);
      } else if (Platform.isAndroid) {
        lib = DynamicLibrary.open('libonnxruntime.so');
      } else if (Platform.isWindows) {
        lib = DynamicLibrary.open('onnxruntime.dll');
      } else if (Platform.isLinux) {
        lib = DynamicLibrary.open('libonnxruntime.so');
      } else {
        lib = DynamicLibrary.process();
      }
    } catch (_) {
      return null;
    }
    Pointer<_OrtApiBase> base;
    try {
      final getBase = lib.lookupFunction<Pointer<_OrtApiBase> Function(),
          Pointer<_OrtApiBase> Function()>('OrtGetApiBase');
      base = getBase();
    } catch (_) {
      return null;
    }
    if (base == nullptr) return null;
    final getApi = base.ref.getApi
        .asFunction<Pointer<Pointer<Void>> Function(int)>();
    final versionOf = base.ref.getVersionString
        .asFunction<Pointer<Utf8> Function()>();
    for (var v = 22; v >= 11; v--) {
      final api = getApi(v);
      if (api != nullptr) {
        return OrtApi._(api, versionOf().toDartString());
      }
    }
    return null;
  }

  // ---- function slots -------------------------------------------------------

  Pointer<NativeFunction<T>> _slot<T extends Function>(int i) =>
      _api[i].cast<NativeFunction<T>>();

  late final _getErrorMessage = _slot<Pointer<Utf8> Function(Pointer<Void>)>(2)
      .asFunction<Pointer<Utf8> Function(Pointer<Void>)>();
  late final _createEnv =
      _slot<Pointer<Void> Function(Int32, Pointer<Utf8>, Pointer<Pointer<Void>>)>(3)
          .asFunction<Pointer<Void> Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>)>();
  late final _createSession = _slot<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>)>(7)
      .asFunction<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _createSessionFromArray = _slot<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Void>,
              Pointer<Pointer<Void>>)>(8)
      .asFunction<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _run = _slot<
          Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>,
              Size,
              Pointer<Pointer<Utf8>>,
              Size,
              Pointer<Pointer<Void>>)>(9)
      .asFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>, int, Pointer<Pointer<Utf8>>, int, Pointer<Pointer<Void>>)>();
  late final _createSessionOptions =
      _slot<Pointer<Void> Function(Pointer<Pointer<Void>>)>(10)
          .asFunction<Pointer<Void> Function(Pointer<Pointer<Void>>)>();
  late final _setGraphOptimizationLevel =
      _slot<Pointer<Void> Function(Pointer<Void>, Int32)>(23)
          .asFunction<Pointer<Void> Function(Pointer<Void>, int)>();
  late final _setIntraOpNumThreads =
      _slot<Pointer<Void> Function(Pointer<Void>, Int32)>(24)
          .asFunction<Pointer<Void> Function(Pointer<Void>, int)>();
  late final _setInterOpNumThreads =
      _slot<Pointer<Void> Function(Pointer<Void>, Int32)>(25)
          .asFunction<Pointer<Void> Function(Pointer<Void>, int)>();
  late final _sessionGetInputCount =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>(30)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>();
  late final _sessionGetOutputCount =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>(31)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>();
  late final _sessionGetInputTypeInfo =
      _slot<Pointer<Void> Function(Pointer<Void>, Size, Pointer<Pointer<Void>>)>(33)
          .asFunction<Pointer<Void> Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>();
  late final _sessionGetInputName = _slot<
          Pointer<Void> Function(
              Pointer<Void>, Size, Pointer<Void>, Pointer<Pointer<Utf8>>)>(36)
      .asFunction<
          Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Utf8>>)>();
  late final _sessionGetOutputName = _slot<
          Pointer<Void> Function(
              Pointer<Void>, Size, Pointer<Void>, Pointer<Pointer<Utf8>>)>(37)
      .asFunction<
          Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Utf8>>)>();
  late final _createTensorWithData = _slot<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Int64>, Size,
              Int32, Pointer<Pointer<Void>>)>(49)
      .asFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Int64>, int, int,
              Pointer<Pointer<Void>>)>();
  late final _getTensorMutableData =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(51)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _castTypeInfoToTensorInfo =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(55)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _getTensorElementType =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Int32>)>(60)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Int32>)>();
  late final _getDimensionsCount =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>(61)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>();
  late final _getDimensions =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, Size)>(62)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, int)>();
  late final _getTensorTypeAndShape =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(65)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _createCpuMemoryInfo =
      _slot<Pointer<Void> Function(Int32, Int32, Pointer<Pointer<Void>>)>(69)
          .asFunction<Pointer<Void> Function(int, int, Pointer<Pointer<Void>>)>();
  late final _allocatorFree =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>(76)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>();
  late final _getAllocatorWithDefaultOptions =
      _slot<Pointer<Void> Function(Pointer<Pointer<Void>>)>(78)
          .asFunction<Pointer<Void> Function(Pointer<Pointer<Void>>)>();
  late final _releaseEnv = _release(92);
  late final _releaseStatus = _release(93);
  late final _releaseMemoryInfo = _release(94);
  late final _releaseSession = _release(95);
  late final _releaseValue = _release(96);
  late final _releaseTypeInfo = _release(98);
  late final _releaseTensorTypeAndShapeInfo = _release(99);
  late final _releaseSessionOptions = _release(100);
  late final _sessionGetModelMetadata =
      _slot<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(111)
          .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _modelMetadataLookup = _slot<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(116)
      .asFunction<
          Pointer<Void> Function(
              Pointer<Void>, Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>();
  late final _releaseModelMetadata = _release(118);

  void Function(Pointer<Void>) _release(int slot) =>
      _slot<Void Function(Pointer<Void>)>(slot)
          .asFunction<void Function(Pointer<Void>)>();

  /// Throws [OrtException] when [status] is an error, and frees it.
  void _check(Pointer<Void> status) {
    if (status == nullptr) return;
    final message = _getErrorMessage(status).toDartString();
    _releaseStatus(status);
    throw OrtException(message);
  }

  // ---- public surface --------------------------------------------------------

  static const int typeFloat = 1;
  static const int typeInt64 = 7;

  Pointer<Void> createEnv() {
    final out = calloc<Pointer<Void>>();
    final id = 'tasmee'.toNativeUtf8();
    try {
      _check(_createEnv(2 /* warning */, id, out));
      return out.value;
    } finally {
      calloc.free(id);
      calloc.free(out);
    }
  }

  void releaseEnv(Pointer<Void> env) => _releaseEnv(env);

  Pointer<Void> createSessionOptions({int threads = 1}) {
    final out = calloc<Pointer<Void>>();
    try {
      _check(_createSessionOptions(out));
      final o = out.value;
      _check(_setIntraOpNumThreads(o, threads));
      _check(_setInterOpNumThreads(o, 1));
      _check(_setGraphOptimizationLevel(o, 99 /* all */));
      return o;
    } finally {
      calloc.free(out);
    }
  }

  void releaseSessionOptions(Pointer<Void> o) => _releaseSessionOptions(o);

  /// Opens the model at [path]. On Windows the runtime wants a wide-char
  /// path, so the file is read and handed over as bytes instead.
  Pointer<Void> createSession(Pointer<Void> env, String path, Pointer<Void> options) {
    final out = calloc<Pointer<Void>>();
    try {
      if (Platform.isWindows) {
        final bytes = File(path).readAsBytesSync();
        final buf = calloc<Uint8>(bytes.length);
        try {
          buf.asTypedList(bytes.length).setAll(0, bytes);
          _check(_createSessionFromArray(env, buf.cast(), bytes.length, options, out));
        } finally {
          calloc.free(buf);
        }
      } else {
        final p = path.toNativeUtf8();
        try {
          _check(_createSession(env, p, options, out));
        } finally {
          calloc.free(p);
        }
      }
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void releaseSession(Pointer<Void> s) => _releaseSession(s);

  Pointer<Void> defaultAllocator() {
    final out = calloc<Pointer<Void>>();
    try {
      _check(_getAllocatorWithDefaultOptions(out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  Pointer<Void> cpuMemoryInfo() {
    final out = calloc<Pointer<Void>>();
    try {
      _check(_createCpuMemoryInfo(1 /* arena */, 0 /* default */, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void releaseMemoryInfo(Pointer<Void> m) => _releaseMemoryInfo(m);

  int inputCount(Pointer<Void> session) => _count(_sessionGetInputCount, session);
  int outputCount(Pointer<Void> session) => _count(_sessionGetOutputCount, session);

  int _count(Pointer<Void> Function(Pointer<Void>, Pointer<Size>) f, Pointer<Void> s) {
    final out = calloc<Size>();
    try {
      _check(f(s, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  String inputName(Pointer<Void> session, int i, Pointer<Void> allocator) =>
      _name(_sessionGetInputName, session, i, allocator);
  String outputName(Pointer<Void> session, int i, Pointer<Void> allocator) =>
      _name(_sessionGetOutputName, session, i, allocator);

  String _name(
      Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Utf8>>) f,
      Pointer<Void> s,
      int i,
      Pointer<Void> allocator) {
    final out = calloc<Pointer<Utf8>>();
    try {
      _check(f(s, i, allocator, out));
      final name = out.value.toDartString();
      _check(_allocatorFree(allocator, out.value.cast()));
      return name;
    } finally {
      calloc.free(out);
    }
  }

  /// (element type, dims) of input [i]; symbolic dims come back as -1.
  (int, List<int>) inputTypeAndShape(Pointer<Void> session, int i) {
    final info = calloc<Pointer<Void>>();
    try {
      _check(_sessionGetInputTypeInfo(session, i, info));
      try {
        final tensor = calloc<Pointer<Void>>();
        try {
          _check(_castTypeInfoToTensorInfo(info.value, tensor));
          return _typeAndDims(tensor.value);
        } finally {
          calloc.free(tensor);
        }
      } finally {
        _releaseTypeInfo(info.value);
      }
    } finally {
      calloc.free(info);
    }
  }

  (int, List<int>) _typeAndDims(Pointer<Void> tensorInfo) {
    final type = calloc<Int32>();
    final count = calloc<Size>();
    try {
      _check(_getTensorElementType(tensorInfo, type));
      _check(_getDimensionsCount(tensorInfo, count));
      final dims = calloc<Int64>(count.value);
      try {
        _check(_getDimensions(tensorInfo, dims, count.value));
        return (type.value, List<int>.generate(count.value, (k) => dims[k]));
      } finally {
        calloc.free(dims);
      }
    } finally {
      calloc.free(type);
      calloc.free(count);
    }
  }

  /// Dims of a tensor value.
  List<int> valueDims(Pointer<Void> value) {
    final info = calloc<Pointer<Void>>();
    try {
      _check(_getTensorTypeAndShape(value, info));
      try {
        return _typeAndDims(info.value).$2;
      } finally {
        _releaseTensorTypeAndShapeInfo(info.value);
      }
    } finally {
      calloc.free(info);
    }
  }

  /// A tensor over caller-owned native memory [data] of [byteLength] bytes.
  Pointer<Void> tensorOver(Pointer<Void> memoryInfo, Pointer<Void> data, int byteLength,
      List<int> dims, int type) {
    final shape = calloc<Int64>(dims.length);
    final out = calloc<Pointer<Void>>();
    try {
      for (var k = 0; k < dims.length; k++) {
        shape[k] = dims[k];
      }
      _check(_createTensorWithData(memoryInfo, data, byteLength, shape, dims.length, type, out));
      return out.value;
    } finally {
      calloc.free(shape);
      calloc.free(out);
    }
  }

  Pointer<Void> tensorData(Pointer<Void> value) {
    final out = calloc<Pointer<Void>>();
    try {
      _check(_getTensorMutableData(value, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void releaseValue(Pointer<Void> v) => _releaseValue(v);

  /// Runs the session; the returned values are owned by the caller.
  List<Pointer<Void>> run(Pointer<Void> session, Pointer<Pointer<Utf8>> inputNames,
      List<Pointer<Void>> inputs, Pointer<Pointer<Utf8>> outputNames, int outputCount) {
    final ins = calloc<Pointer<Void>>(inputs.length);
    final outs = calloc<Pointer<Void>>(outputCount);
    try {
      for (var k = 0; k < inputs.length; k++) {
        ins[k] = inputs[k];
      }
      _check(_run(session, nullptr, inputNames, ins, inputs.length, outputNames, outputCount, outs));
      return List<Pointer<Void>>.generate(outputCount, (k) => outs[k]);
    } finally {
      calloc.free(ins);
      calloc.free(outs);
    }
  }

  /// Custom metadata entry [key] of the model, or null.
  String? metadata(Pointer<Void> session, Pointer<Void> allocator, String key) {
    final meta = calloc<Pointer<Void>>();
    final out = calloc<Pointer<Utf8>>();
    final k = key.toNativeUtf8();
    try {
      _check(_sessionGetModelMetadata(session, meta));
      try {
        _check(_modelMetadataLookup(meta.value, allocator, k, out));
        if (out.value == nullptr) return null;
        final v = out.value.toDartString();
        _check(_allocatorFree(allocator, out.value.cast()));
        return v;
      } finally {
        _releaseModelMetadata(meta.value);
      }
    } finally {
      calloc.free(meta);
      calloc.free(out);
      calloc.free(k);
    }
  }

  /// Native array of C strings for [names]; free with [freeNames].
  static Pointer<Pointer<Utf8>> names(List<String> names) {
    final arr = calloc<Pointer<Utf8>>(names.length);
    for (var k = 0; k < names.length; k++) {
      arr[k] = names[k].toNativeUtf8();
    }
    return arr;
  }

  static void freeNames(Pointer<Pointer<Utf8>> arr, int count) {
    for (var k = 0; k < count; k++) {
      calloc.free(arr[k]);
    }
    calloc.free(arr);
  }
}

final class _OrtApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>> getApi;
  external Pointer<NativeFunction<Pointer<Utf8> Function()>> getVersionString;
}

class OrtException implements Exception {
  OrtException(this.message);
  final String message;
  @override
  String toString() => 'OrtException: $message';
}

/// Byte-copy helper for state tensors.
extension NativeFloat32 on Pointer<Void> {
  Float32List asFloat32(int count) => cast<Float>().asTypedList(count);
  Int64List asInt64(int count) => cast<Int64>().asTypedList(count);
}
