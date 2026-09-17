import 'package:flutter/services.dart';

class WindowsFilePicker {
  static const _channel = MethodChannel('fap_helper/files');
  Future<String?> pickExcel() => _channel.invokeMethod<String>('pickExcel');
  Future<String?> saveCsv(String fileName) =>
      _channel.invokeMethod<String>('saveCsv', fileName);
}
