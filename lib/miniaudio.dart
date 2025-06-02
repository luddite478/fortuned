import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = () {
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('libminiaudio.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libminiaudio.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('miniaudio.dll');
  } else {
    throw UnsupportedError('Platform not supported');
  }
}();


final void Function() initEngine = _lib
    .lookup<NativeFunction<Void Function()>>('init_engine')
    .asFunction();

final void Function(Pointer<Utf8>) playSample = _lib
    .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('play_sample')
    .asFunction();
