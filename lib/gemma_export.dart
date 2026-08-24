// Conditional export: uses gemma_web on web platforms and gemma_native on native platforms.
export 'gemma_native.dart'
    if (dart.library.js_interop) 'gemma_web.dart';
