// Web platform implementation: provides web-compatible Gemma/LLM types
// so the application compiles and runs smoothly as a Web App on iPhone 15 Safari / PWA.

import 'package:flutter/foundation.dart';

enum ModelType { qwen, gemma }
enum ModelFileType { task, litertlm }

class FlutterGemma {
  static Future<void> initialize() async {
    debugPrint('FlutterGemma web adapter initialized');
  }

  static Future<InferenceModel> getActiveModel() async {
    return InferenceModel();
  }
}

class InferenceModel {
  static Future<InferenceModel> createModel({
    required String modelPath,
    double? temperature,
    int? topK,
    int? maxTokens,
  }) async {
    return InferenceModel();
  }

  Future<InferenceChat> createChat() async => InferenceChat();
  void close() {}
}

class Message {
  final String text;
  final bool isUser;
  Message({required this.text, required this.isUser});
}

class InferenceChat {
  Future<String> generateResponse(String prompt) async {
    return "Assam Flood Assistant (Web Mode): Processing rescue request for prompt '$prompt'.";
  }

  void close() {}
}
