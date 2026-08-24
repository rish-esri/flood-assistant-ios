import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

// Layer/field names the chat's LLM orchestrator is allowed to query against.
// Kept as a single source of truth for both the system prompt shown to the
// model and the lookup code that executes its query directives.
const _kQueryableLayerName = 'WindTurbineDetection WFL1 - Turbines';
const _kQueryableFieldName = 'Confidence';
const _kFloodLayerName = 'Assam_Flooded_Areas';
const _kBuildingsLayerName = 'Assam_Buildings';
const _kShelterLayerName = 'Assam_Emergency_Shelters';
const _kPortalUrl = 'https://solutions.esri.in/portal';
const _kSecondRouteItemId = '410740f0879c4eb4a870f70cf0b9f8b4';
const _kShelterRouteLayerName = 'Assam_Floods_Custom_Rescue_Route';

// First responder starting location: 93.8320717°E 26.6445128°N
final start_coordinate = ArcGISPoint(
  x: 93.8320717,
  y: 26.6445128,
  spatialReference: SpatialReference.wgs84,
);

// First responder evacuation location (Second Coordinate): 93.8268934°E 26.6438748°N
final start_coordinate2 = ArcGISPoint(
  x: 93.8268934,
  y: 26.6438748,
  spatialReference: SpatialReference.wgs84,
);

// On-device LLM used by the chat panel below. Qwen2.5-0.5B-Instruct
// (Apache-2.0, MediaPipe .task format) is used instead of a Gemma model
// because it downloads directly from Hugging Face with no gated-license /
// access-token step, and .task models run on both x86_64 and arm64 devices —
// unlike .litertlm models (e.g. Qwen3), whose native LiteRT-LM engine only
// ships arm64-v8a bindings and crashes on x86_64 emulators.
//
// Swap to a Gemma model by changing these constants (and fileType, if
// switching to a .litertlm model) and passing a Hugging Face token to
// FlutterGemma.initialize (see package README).
const _kLlmModelType = ModelType.qwen;
const _kLlmModelFileType = ModelFileType.task;
const _kLlmModelFileName =
    'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task';
const _kLlmModelUrl =
    'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/$_kLlmModelFileName';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set ArcGIS Runtime Lite license key (removes "Licensed For Developer Use Only" watermark)
  final licenseResult = ArcGISEnvironment.setLicenseUsingKey(
    'nativelite,3000,rudrrz785t5q,none,S08PF7PZJ54SDLJ6D158',
  );
  debugPrint('ArcGIS License Status: ${licenseResult.licenseStatus}');

  // Your API key
  ArcGISEnvironment.apiKey =
      'AAPTaEvIaWLjEjMRcSt4rihpJeQ..GJbYswENKJDB2iQIuGVH2ZnKWYZCYfvNnzlOdTeG4swfC86ZCCcduxs2TuES3m7qRMkZH1LHIVjtQQCwCwSNPfAgRt-WM2omjGVEzYTgthVhsPrVIALnZMDuCgr4vPTwTOTdeuM6PJhPdMEdDFZpTMpq_z09hrxN4pDT_eyS6eRc_8xDR4mPhnlTVvricWAOfE0x0kxoD1KYkvtSmWzvuJvp45IoXDftAvKf57HHPZQ91Zy5sI6YlcbeeHy9h6ZX5NXtVCG_Byj7f1raHQ..AT1_HLTfW6aA';

  // Sets up the local inference engine used to run the model on-device.
  await FlutterGemma.initialize();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainApp(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _mapViewController = ArcGISMapView.createController();
  final _routeGraphicsOverlay = GraphicsOverlay();
  ArcGISMap? _map;

  static const String _portalUrl = _kPortalUrl;

  // Web map with the 3 Assam layers (Emergency_Shelters, Buildings,
  // Flooded_Areas), basemap set to World Imagery (Esri Training Services)
  // so it loads via the existing portal OAuth session — no separate API key
  // needed.
  static const String _webMapItemId = 'bc3576cbf0654449b01fae4d38977d62';

  // Enterprise OAuth configuration — REQUIRED to access this secured portal
  // item.
  final _oAuthUserConfiguration = OAuthUserConfiguration(
    portalUri: Uri.parse(_portalUrl),
    clientId: 'jxXFVfRXHLTfW6aA', // from Enterprise OAuth app
    redirectUri: Uri.parse('my-app://auth'), // must match Enterprise app settings
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Map viewer, wrapped in Authenticator so it can prompt for
          // Enterprise login.
          Expanded(
            child: Authenticator(
              oAuthUserConfigurations: [_oAuthUserConfiguration],
              child: Stack(
                children: [
                  ArcGISMapView(
                    controllerProvider: () => _mapViewController,
                    onMapViewReady: onMapViewReady,
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'my_location_btn',
                          onPressed: _recenterToStartingLocation,
                          tooltip: 'My Location (Start Point)',
                          child: const Icon(Icons.my_location),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'zoom_in_btn',
                          onPressed: _zoomIn,
                          tooltip: 'Zoom In',
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'zoom_out_btn',
                          onPressed: _zoomOut,
                          tooltip: 'Zoom Out',
                          child: const Icon(Icons.remove),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'layer_list_btn',
                          onPressed: _showLayerListModal,
                          tooltip: 'Layer List',
                          child: const Icon(Icons.layers),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: ChatPanel(
              getMap: () => _map,
              getController: () => _mapViewController,
              getGraphicsOverlay: () => _routeGraphicsOverlay,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _zoomIn() async {
    final currentViewpoint = _mapViewController.getCurrentViewpoint(ViewpointType.centerAndScale);
    if (currentViewpoint != null && currentViewpoint.targetGeometry is ArcGISPoint) {
      final center = currentViewpoint.targetGeometry as ArcGISPoint;
      final newScale = currentViewpoint.targetScale * 0.5;
      await _mapViewController.setViewpointAnimated(
        Viewpoint.fromCenter(center, scale: newScale),
        duration: 0.25,
      );
    }
  }

  Future<void> _zoomOut() async {
    final currentViewpoint = _mapViewController.getCurrentViewpoint(ViewpointType.centerAndScale);
    if (currentViewpoint != null && currentViewpoint.targetGeometry is ArcGISPoint) {
      final center = currentViewpoint.targetGeometry as ArcGISPoint;
      final newScale = currentViewpoint.targetScale * 2.0;
      await _mapViewController.setViewpointAnimated(
        Viewpoint.fromCenter(center, scale: newScale),
        duration: 0.25,
      );
    }
  }

  void _showLayerListModal() {
    final map = _map;
    if (map == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map is still loading...')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final layers = map.operationalLayers;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Map Layers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (layers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No operational layers found.'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: layers.length,
                        itemBuilder: (context, index) {
                          final layer = layers[index];
                          return SwitchListTile(
                            title: Text(
                              layer.name.isEmpty ? 'Layer ${index + 1}' : layer.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            secondary: IconButton(
                              icon: const Icon(Icons.center_focus_strong, color: Colors.blue),
                              tooltip: 'Zoom to layer extent',
                              onPressed: () {
                                final extent = layer.fullExtent;
                                if (extent != null) {
                                  _mapViewController.setViewpointGeometry(extent);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            value: layer.isVisible,
                            onChanged: (bool value) {
                              setState(() {
                                layer.isVisible = value;
                              });
                              setModalState(() {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void onMapViewReady() async {
    // Authenticated connection is required; anonymous was giving 18007.
    final portal = Portal(
      Uri.parse(_portalUrl),
      connection: PortalConnection.authenticated,
    );

    final portalItem = PortalItem.withPortalAndItemId(
      portal: portal,
      itemId: _webMapItemId,
    );

    final map = ArcGISMap.withItem(portalItem);

    await map.load();

    if (map.loadStatus != LoadStatus.loaded) {
      debugPrint('Map failed to load: ${map.loadError?.message}');
      return;
    }

    _mapViewController.arcGISMap = map;
    _mapViewController.graphicsOverlays.add(_routeGraphicsOverlay);
    _showStartingLocationOnMap();
    setState(() => _map = map);
  }

  void _recenterToStartingLocation() {
    _mapViewController.setViewpointAnimated(
      Viewpoint.fromCenter(start_coordinate, scale: 2500),
      duration: 0.5,
    );
  }

  void _showStartingLocationOnMap() {
    // Outer pulse ring graphic
    final outerRingGraphic = Graphic(
      geometry: start_coordinate,
      symbol: SimpleMarkerSymbol(
        style: SimpleMarkerSymbolStyle.circle,
        color: Colors.blue.withOpacity(0.35),
        size: 28,
      ),
    );

    // Main location pin graphic
    final startMarkerGraphic = Graphic(
      geometry: start_coordinate,
      symbol: SimpleMarkerSymbol(
        style: SimpleMarkerSymbolStyle.circle,
        color: Colors.blue.shade800,
        size: 16,
      ),
    );

    // Inner white dot
    final innerDotGraphic = Graphic(
      geometry: start_coordinate,
      symbol: SimpleMarkerSymbol(
        style: SimpleMarkerSymbolStyle.circle,
        color: Colors.white,
        size: 7,
      ),
    );

    _routeGraphicsOverlay.graphics.addAll([
      outerRingGraphic,
      startMarkerGraphic,
      innerDotGraphic,
    ]);

    _mapViewController.setViewpoint(
      Viewpoint.fromCenter(start_coordinate, scale: 2500),
    );
  }
}

// -------------------------------------------
// Chat UI backed by a real on-device LLM
// (flutter_gemma + MediaPipe, Qwen2.5-0.5B)
// -------------------------------------------

class _ChatMessage {
  final String text;
  final bool fromUser;

  const _ChatMessage(
    this.text, {
    required this.fromUser,
  });
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.getMap,
    required this.getController,
    required this.getGraphicsOverlay,
  });

  // Returns the currently loaded web map, or null while it's still loading.
  final ArcGISMap? Function() getMap;
  final ArcGISMapViewController Function() getController;
  final GraphicsOverlay Function() getGraphicsOverlay;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  InferenceModel? _model;
  InferenceChat? _chat;
  Feature? _selectedFloodFeature;
  Feature? _selectedShelterFeature;

  // Walkie-Talkie Voice Engine State
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _voiceModeActive = true;
  bool _isHindi = false;
  bool _isVoiceMode = true;

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isPreparing = true;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVoiceEngine();
    _prepareModel();
  }

  @override
  void dispose() {
    _speechToText.stop();
    _flutterTts.stop();
    _controller.dispose();
    _scrollController.dispose();

    // Not awaited: dispose() can't be async. Release native resources
    // best-effort; the OS reclaims anything left over when the app exits.
    _chat?.close();
    _model?.close();

    super.dispose();
  }

  Future<void> _initVoiceEngine() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (val) {
          debugPrint('STT Error: $val');
          if (mounted) {
            setState(() {
              _isListening = false;
              _isGenerating = false;
            });
          }
        },
        onStatus: (val) {
          debugPrint('STT Status: $val');
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.44);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _flutterTts.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _flutterTts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });

      try {
        final voices = await _flutterTts.getVoices;
        debugPrint('Available on-device voices: $voices');
      } catch (_) {}
    } catch (e) {
      debugPrint('Voice engine initialization failed: $e');
    }
  }

  Future<void> _selectInstalledVoice(String targetLang) async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List && voices.isNotEmpty) {
        Map? chosenVoice;
        final target = targetLang.toLowerCase();

        for (final v in voices) {
          if (v is Map) {
            final name = v['name']?.toString().toLowerCase() ?? '';
            final locale = v['locale']?.toString().toLowerCase() ?? '';

            if (target.contains('hi')) {
              if ((name.contains('hi-in') || locale.contains('hi')) &&
                  (name.contains('network') || name.contains('neural') || name.contains('hic') || name.contains('hid'))) {
                chosenVoice = v;
                break;
              }
            } else {
              if ((name.contains('en-in') || locale.contains('en_in') || locale.contains('en-in')) &&
                  (name.contains('network') || name.contains('neural') || name.contains('end') || name.contains('ene'))) {
                chosenVoice = v;
                break;
              }
            }
          }
        }

        if (chosenVoice == null) {
          for (final v in voices) {
            if (v is Map) {
              final name = v['name']?.toString().toLowerCase() ?? '';
              final locale = v['locale']?.toString().toLowerCase() ?? '';
              if (target.contains('hi') && (name.contains('hi') || locale.contains('hi'))) {
                chosenVoice = v;
                break;
              } else if (!target.contains('hi') && (name.contains('en-in') || locale.contains('en-in') || locale.contains('en_in'))) {
                chosenVoice = v;
                break;
              }
            }
          }
        }

        if (chosenVoice != null) {
          await _flutterTts.setVoice({
            "name": chosenVoice['name'],
            "locale": chosenVoice['locale'],
          });
        }
      }
    } catch (e) {
      debugPrint('Voice selection error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speakText(String text) async {
    _scrollToBottom();
    if (!_voiceModeActive) return;
    try {
      await _flutterTts.stop();
      if (_isHindi) {
        await _flutterTts.setLanguage("hi-IN");
        await _selectInstalledVoice("hi-IN");
        await _flutterTts.setSpeechRate(0.44);
        await _flutterTts.setPitch(1.0);

        String speechText = text
            .replaceAll(RegExp(r'\*\*|\*|__|#|`|🗺️|⚠️|✅'), '')
            .replaceAllMapped(RegExp(r'ogc_fid:\s*(\d+)'), (match) => 'संख्या ${match.group(1)}, ')
            .replaceAll(RegExp(r'ogc_fid:'), 'संख्या ')
            .replaceAll(RegExp(r'ogc_fid'), 'संख्या')
            .replaceAll('\$', '')
            .replaceAll('Est. travel time:', 'अनुमानित समय, ')
            .replaceAll('Distance:', 'दूरी, ')
            .replaceAll('km and', 'किलोमीटर और')
            .replaceAll('km', 'किलोमीटर')
            .replaceAll('mins', 'मिनट')
            .replaceAll('m.', 'मीटर।')
            .replaceAll('km.', 'किलोमीटर।')
            .replaceAll('\n\n', '. ')
            .replaceAll('\n', '. ');

        await _flutterTts.speak(speechText);
      } else {
        await _flutterTts.setLanguage("en-IN");
        await _selectInstalledVoice("en-IN");
        await _flutterTts.setSpeechRate(0.45);
        await _flutterTts.setPitch(1.0);

        String speechText = text
            .replaceAll(RegExp(r'\*\*|\*|__|#|`|🗺️|⚠️|✅'), '')
            .replaceAllMapped(RegExp(r'ogc_fid:\s*(\d+)'), (match) => 'number ${match.group(1)}, ')
            .replaceAll(RegExp(r'ogc_fid:'), 'number ')
            .replaceAll(RegExp(r'ogc_fid'), 'number')
            .replaceAll('\$', '')
            .replaceAll('Est. travel time:', 'Estimated travel time, ')
            .replaceAll('Distance:', 'Distance, ')
            .replaceAll('mins', 'minutes')
            .replaceAll('m.', 'meters.')
            .replaceAll('km.', 'kilometers.')
            .replaceAll('\n\n', '. ')
            .replaceAll('\n', '. ');

        await _flutterTts.speak(speechText);
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
  }

  Future<void> _stopSpeech() async {
    await _flutterTts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _listenVoiceInput() async {
    if (!_speechEnabled) {
      final initialized = await _speechToText.initialize();
      if (!initialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone / Speech recognition unavailable.')),
        );
        return;
      }
      if (mounted) setState(() => _speechEnabled = true);
    }

    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      await _stopSpeech();
      if (mounted) setState(() => _isListening = true);
      _speechToText.listen(
        localeId: _isHindi ? 'hi_IN' : 'en_US',
        onResult: (result) async {
          if (mounted) {
            setState(() {
              _controller.text = result.recognizedWords;
            });
            if (result.finalResult && result.recognizedWords.trim().isNotEmpty && !_isGenerating) {
              await _speechToText.stop();
              if (mounted) setState(() => _isListening = false);
              _handleSend();
            }
          }
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _prepareModel() async {
    setState(() {
      _isPreparing = true;
      _error = null;
    });

    try {
      final alreadyInstalled = await FlutterGemma.isModelInstalled(
        _kLlmModelFileName,
      );

      if (!alreadyInstalled) {
        setState(() => _isDownloading = true);

        // fileType must be passed explicitly — it is NOT inferred from the
        // URL/filename and silently defaults to ModelFileType.task, which
        // routes .litertlm files into the wrong native engine and throws.
        await FlutterGemma.installModel(
          modelType: _kLlmModelType,
          fileType: _kLlmModelFileType,
        )
            .fromNetwork(_kLlmModelUrl)
            .withProgress(
              (progress) => setState(
                () => _downloadProgress = progress.toDouble(),
              ),
            )
            .install();

        setState(() => _isDownloading = false);
      }

      final model = await FlutterGemma.getActiveModel(maxTokens: 2048);

      final chat = await model.createChat(
        systemInstruction:
            'You are a query orchestrator for a flood rescue map app. '
            '1. If the user asks about the nearest flooded area or nearest flood boundary (for example: "Which is the nearest Flooded area?" or "Find nearest flood"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"nearest_flood"} '
            '2. If the user asks how many buildings are affected, flooded, or damaged (for example: "How many buildings got affected?" or "Count affected buildings"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"affected_buildings"} '
            '3. If the user asks for a route or navigation to the nearest affected building (for example: "Show me the optimized route to reach the nearest affected building?" or "Route to nearest building"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"route_to_nearest_building"} '
            '4. If the user asks which is the nearest shelter point or emergency shelter (for example: "which is the nearest shelter point?" or "Find nearest shelter"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"nearest_shelter"} '
            '5. If the user asks if the shelter point is inundated or flooded (for example: "is that point Inundated?" or "Is the shelter flooded?"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"is_shelter_inundated"} '
            '6. If the user asks for the optimized route to the nearest shelter point (for example: "Show me the optimized route for the nearest shelter point" or "Route to nearest shelter"), respond with ONLY a single line of JSON and nothing else: '
            '{"action":"route_to_nearest_shelter"} '
            '7. If the user asks to filter or select features in "$_kQueryableLayerName" by confidence or numeric values, respond with ONLY a single line of JSON: '
            '{"action":"select","layer":"$_kQueryableLayerName","field":"$_kQueryableFieldName","operator":"<","value":95} '
            '8. For any other message, reply normally in plain conversational text. '
            'Do not output markdown code blocks or extra text when returning JSON.',
      );

      setState(() {
        _model = model;
        _chat = chat;
        _isPreparing = false;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _isPreparing = false;
        _error = 'Could not prepare the on-device model: $e';
      });
    }
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    final chat = _chat;

    if (text.isEmpty || chat == null || _isGenerating) return;

    if (_isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
    }
    await _stopSpeech();

    FocusScope.of(context).unfocus();

    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text, fromUser: true));
      _messages.add(const _ChatMessage('', fromUser: false));
      _isGenerating = true;
    });
    _scrollToBottom();

    final replyIndex = _messages.length - 1;

    // 1. FIRST-PASS: Run instant deterministic prompt inference on user input
    Map<String, dynamic>? directive = _inferQueryDirectiveFromUserPrompt(text);

    if (directive != null) {
      await _runQueryDirective(directive, replyIndex, text);
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _isListening = false;
        });
      }
      return;
    }

    // 2. SECOND-PASS: Fallback to LLM streaming for open conversational questions
    final buffer = StringBuffer();

    try {
      await chat.addQueryChunk(Message.text(text: text, isUser: true));

      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          buffer.write(response.token);
          setState(() {
            _messages[replyIndex] = _ChatMessage(
              buffer.toString(),
              fromUser: false,
            );
          });
          _scrollToBottom();
        }
      }

      directive = _tryParseQueryDirective(buffer.toString());

      if (directive != null) {
        await _runQueryDirective(directive, replyIndex, text);
      } else {
        _speakText(buffer.toString());
      }
    } catch (e) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(
          'Error generating a response: $e',
          fromUser: false,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _isListening = false;
        });
      }
    }
  }

  static const _kAllowedOperators = {'<', '<=', '>', '>=', '=', '!='};

  Map<String, dynamic>? _tryParseQueryDirective(String text) {
    String cleanText = text.trim();
    if (cleanText.startsWith('```')) {
      final lines = cleanText.split('\n');
      if (lines.length >= 2) {
        cleanText = lines
            .sublist(1, lines.last.startsWith('```') ? lines.length - 1 : lines.length)
            .join('\n')
            .trim();
      }
    }

    try {
      final decoded = jsonDecode(cleanText);
      if (decoded is Map<String, dynamic> && decoded.containsKey('action')) {
        return decoded;
      }
    } catch (_) {}

    final actionMatch = RegExp(r'"action"\s*:\s*"([a_z_]+)"', caseSensitive: false).firstMatch(cleanText);
    if (actionMatch != null) {
      return {'action': actionMatch.group(1)};
    }

    final knownActions = [
      'route_to_nearest_shelter',
      'route_to_nearest_building',
      'is_shelter_inundated',
      'affected_buildings',
      'nearest_shelter',
      'nearest_flood',
    ];
    for (final act in knownActions) {
      if (cleanText.contains(act)) {
        return {'action': act};
      }
    }

    return null;
  }

  Map<String, dynamic>? _inferQueryDirectiveFromUserPrompt(String prompt) {
    final lower = prompt.toLowerCase();

    // Auto-detect Hindi script or Hinglish prompt
    if (RegExp(r'[\u0900-\u097F]').hasMatch(prompt) ||
        lower.contains('kareebi') ||
        lower.contains('baadh') ||
        lower.contains('ghar') ||
        lower.contains('surakshit') ||
        lower.contains('paani') ||
        lower.contains('rasta') ||
        lower.contains('kaise') ||
        lower.contains('kitna') ||
        lower.contains('kitne')) {
      _isHindi = true;
    }

    // 1. Route to nearest shelter / relief camp / safe place
    if ((lower.contains('shelter') || lower.contains('camp') || lower.contains('surakshit') || lower.contains('आश्रय') || lower.contains('शरणार्थी') || lower.contains('सुरक्षित')) &&
        (lower.contains('route') || lower.contains('navigate') || lower.contains('way') || lower.contains('reach') || lower.contains('path') || lower.contains('rasta') || lower.contains('pahunchein') || lower.contains('pahunche') || lower.contains('jaane') || lower.contains('kaise') || lower.contains('रास्ता') || lower.contains('मार्ग') || lower.contains('दिशा') || lower.contains('जाने') || lower.contains('पहुंचे') || lower.contains('पहुंचें') || lower.contains('कैसे'))) {
      return {'action': 'route_to_nearest_shelter'};
    }

    // 2. Is shelter inundated / flooded check
    if (lower.contains('inundated') || lower.contains('inundate') || lower.contains('paani bhara') || lower.contains('paani') || lower.contains('जलमग्न') || lower.contains('बाढ़ग्रस्त') || lower.contains('पानी भरा') || lower.contains('पानी') || lower.contains('दूबा') || lower.contains('डूबा')) {
      if (lower.contains('wahan') || lower.contains('shelter') || lower.contains('point') || lower.contains('jagah') || lower.contains('आश्रय') || lower.contains('सुरक्षित') || lower.contains('यहाँ') || lower.contains('वहाँ')) {
        return {'action': 'is_shelter_inundated'};
      }
    }

    // 3. Nearest emergency shelter / safe location
    if (lower.contains('shelter') || lower.contains('surakshit') || lower.contains('camp') || lower.contains('sharan') || lower.contains('relief camp') || lower.contains('आश्रय') || lower.contains('शरणार्थी') || lower.contains('सुरक्षित')) {
      if (lower.contains('nearest') || lower.contains('closest') || lower.contains('which') || lower.contains('where') || lower.contains('kahan') || lower.contains('kahān') || lower.contains('point') || lower.contains('paas') || lower.contains('kareebi') || lower.contains('जगह') || lower.contains('पास') || lower.contains('निकटतम') || lower.contains('कौन') || lower.contains('कहाँ') || lower.contains('कहां')) {
        return {'action': 'nearest_shelter'};
      }
      if (lower.contains('जगह') || lower.contains('कहाँ') || lower.contains('कहां') || lower.contains('kahan') || lower.contains('where')) {
        return {'action': 'nearest_shelter'};
      }
    }

    // 4. Route to nearest affected building / ghar
    if ((lower.contains('building') || lower.contains('ghar') || lower.contains('bhavan') || lower.contains('makan') || lower.contains('भवन') || lower.contains('मकान') || lower.contains('इमारत') || lower.contains('घर')) &&
        (lower.contains('route') || lower.contains('navigate') || lower.contains('reach') || lower.contains('rasta') || lower.contains('jaane') || lower.contains('pahunchein') || lower.contains('pahunche') || lower.contains('रास्ता') || lower.contains('मार्ग') || lower.contains('जाने') || lower.contains('पहुंचे') || lower.contains('पहुंचें'))) {
      return {'action': 'route_to_nearest_building'};
    }

    // 5. Count affected / damaged buildings / ghar
    if ((lower.contains('building') || lower.contains('ghar') || lower.contains('bhavan') || lower.contains('makan') || lower.contains('house') || lower.contains('भवन') || lower.contains('मकान') || lower.contains('इमारत') || lower.contains('घर')) &&
        (lower.contains('affected') || lower.contains('damaged') || lower.contains('how many') || lower.contains('count') || lower.contains('kitne') || lower.contains('kitna') || lower.contains('kharab') || lower.contains('nuksan') || lower.contains('प्रभावित') || lower.contains('कितने') || lower.contains('कितना') || lower.contains('क्षतिग्रस्त') || lower.contains('खराब') || lower.contains('नुकसान'))) {
      return {'action': 'affected_buildings'};
    }

    if ((lower.contains('ghar') || lower.contains('घर') || lower.contains('भवन')) &&
        (lower.contains('kharab') || lower.contains('खराब') || lower.contains('nuksan') || lower.contains('प्रभावित')) &&
        (lower.contains('kitna') || lower.contains('kitne') || lower.contains('कितना') || lower.contains('कितने'))) {
      return {'action': 'affected_buildings'};
    }

    // 6. Nearest flooded area / flood-prone area / STT "प्लेटफ़ॉर्म एरिया"
    if (lower.contains('flood-prone') || lower.contains('flooded') || lower.contains('flood') || lower.contains('baadh') || lower.contains('बाढ़') || lower.contains('बाढ़') || lower.contains('प्लेटफॉर्म') || lower.contains('प्लेटफ़ॉर्म')) {
      if (lower.contains('area') || lower.contains('boundary') || lower.contains('nearest') || lower.contains('which') || lower.contains('where') || lower.contains('kareebi') || lower.contains('paas') || lower.contains('kaun') || lower.contains('aas-paas') || lower.contains('aaspas') || lower.contains('पास') || lower.contains('निकटतम') || lower.contains('क्षेत्र') || lower.contains('सीमा') || lower.contains('कौन') || lower.contains('कहाँ') || lower.contains('कहां')) {
        if (!lower.contains('building') && !lower.contains('ghar') && !lower.contains('bhavan') && !lower.contains('shelter') && !lower.contains('surakshit') && !lower.contains('भवन') && !lower.contains('घर') && !lower.contains('सुरक्षित') && !lower.contains('आश्रय')) {
          return {'action': 'nearest_flood'};
        }
      }
    }

    return null;
  }

  Future<void> _runQueryDirective(
    Map<String, dynamic> directive,
    int replyIndex,
    String userPrompt,
  ) async {
    final action = directive['action'];
    final lowerPrompt = userPrompt.toLowerCase();

    if (action == 'nearest_flood' || action == 'find_nearest') {
      await _runNearestFloodDirective(replyIndex);
      return;
    }
    if (action == 'affected_buildings' || action == 'count_affected_buildings' || action == 'buildings_affected') {
      await _runAffectedBuildingsDirective(replyIndex);
      return;
    }
    if (action == 'route_to_nearest_building' || action == 'route_nearest_building' || action == 'navigate_nearest') {
      if (lowerPrompt.contains('shelter')) {
        await _runRouteToNearestShelterDirective(replyIndex);
      } else {
        await _runRouteToNearestBuildingDirective(replyIndex);
      }
      return;
    }
    if (action == 'nearest_shelter' || action == 'find_nearest_shelter' || action == 'closest_shelter') {
      await _runNearestShelterDirective(replyIndex);
      return;
    }
    if (action == 'is_shelter_inundated' || action == 'is_shelter_flooded' || action == 'shelter_inundated') {
      await _runIsShelterInundatedDirective(replyIndex);
      return;
    }
    if (action == 'route_to_nearest_shelter' || action == 'route_nearest_shelter' || action == 'navigate_shelter') {
      await _runRouteToNearestShelterDirective(replyIndex);
      return;
    }

    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    final layerName = directive['layer'] as String;
    final field = directive['field'] as String;
    final operator = directive['operator'] as String;
    final value = directive['value'];

    final layer = map.operationalLayers
        .where((l) => l.name == layerName)
        .firstOrNull;
    if (layer is! FeatureLayer) {
      showResult('Could not find a layer named "$layerName" on the map.');
      return;
    }

    final formattedValue = value is String ? "'$value'" : '$value';
    final whereClause = '$field $operator $formattedValue';

    try {
      final result = await layer.selectFeaturesWithQuery(
        parameters: QueryParameters()..whereClause = whereClause,
        mode: SelectionMode.new_,
      );
      final count = result.features().length;
      showResult(
        'Selected $count feature(s) in "$layerName" where '
        '$field $operator $formattedValue.',
      );
    } catch (e) {
      showResult('Query failed: $e');
    }
  }

  Future<Feature?> _getOrFindNearestFloodFeature(ArcGISMap map) async {
    if (_selectedFloodFeature != null) {
      return _selectedFloodFeature;
    }

    final layer = map.operationalLayers
        .where((l) => l.name == _kFloodLayerName || l.name.contains('Flooded'))
        .firstOrNull;

    if (layer is! FeatureLayer || layer.featureTable == null) return null;

    final queryParams = QueryParameters()..whereClause = '1=1';
    final queryResult = await layer.featureTable!.queryFeatures(queryParams);
    final features = queryResult.features().toList();
    if (features.isEmpty) return null;

    final layerSR = layer.spatialReference ?? map.spatialReference ?? SpatialReference.wgs84;
    ArcGISPoint startPoint = start_coordinate;
    if (start_coordinate.spatialReference != null &&
        layerSR != null &&
        start_coordinate.spatialReference != layerSR) {
      final projected = GeometryEngine.project(
        start_coordinate,
        outputSpatialReference: layerSR,
      );
      if (projected is ArcGISPoint) {
        startPoint = projected;
      }
    }

    Feature? nearestFeature;
    double minDistance = double.infinity;

    for (final feature in features) {
      final geom = feature.geometry;
      if (geom != null) {
        final dist = GeometryEngine.distance(
          geometry1: startPoint,
          geometry2: geom,
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearestFeature = feature;
        }
      }
    }

    if (nearestFeature != null) {
      layer.clearSelection();
      layer.selectFeature(nearestFeature);
      _selectedFloodFeature = nearestFeature;
    }

    return nearestFeature;
  }

  Future<void> _runNearestFloodDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final nearestFeature = await _getOrFindNearestFloodFeature(map);

      if (nearestFeature == null) {
        showResult('Could not calculate nearest flooded area.');
        return;
      }

      final attributes = nearestFeature.attributes;
      final ogcFid = attributes['ogc_fid'] ??
          attributes['OGC_FID'] ??
          attributes['fid'] ??
          attributes['FID'] ??
          attributes['OBJECTID'] ??
          attributes['objectid'] ??
          'Unknown';

      final controller = widget.getController();
      final geom = nearestFeature.geometry;
      if (geom != null && geom.extent != null) {
        controller.setViewpointGeometry(geom.extent!);
      }

      showResult(
        _isHindi
            ? 'वर्तमान स्थान से निकटतम बाढ़ प्रभावित क्षेत्र का ओजीसी एफआईडी $ogcFid है।'
            : 'The nearest flooded area to the current location is ogc_fid:$ogcFid.',
      );
    } catch (e) {
      showResult('Failed to find nearest flooded area: $e');
    }
  }

  Future<void> _runAffectedBuildingsDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final floodFeature = await _getOrFindNearestFloodFeature(map);
      if (floodFeature == null) {
        showResult('Could not find any active or nearest flooded area.');
        return;
      }

      final floodGeom = floodFeature.geometry;
      if (floodGeom == null) {
        showResult('The selected flooded area feature has no valid geometry.');
        return;
      }

      final attributes = floodFeature.attributes;
      final ogcFid = attributes['ogc_fid'] ??
          attributes['OGC_FID'] ??
          attributes['fid'] ??
          attributes['FID'] ??
          attributes['OBJECTID'] ??
          attributes['objectid'] ??
          'Unknown';

      final buildingsLayer = map.operationalLayers
          .where((l) => l.name == _kBuildingsLayerName || l.name.contains('Buildings'))
          .firstOrNull;

      if (buildingsLayer is! FeatureLayer) {
        showResult('Could not find the "$_kBuildingsLayerName" layer on the map.');
        return;
      }

      final featureTable = buildingsLayer.featureTable;
      if (featureTable == null) {
        showResult('Feature table unavailable for "$_kBuildingsLayerName".');
        return;
      }

      final queryParams = QueryParameters()..whereClause = '1=1';
      final queryResult = await featureTable.queryFeatures(queryParams);
      final allBuildings = queryResult.features().toList();

      if (allBuildings.isEmpty) {
        showResult('No building features found in "$_kBuildingsLayerName".');
        return;
      }

      final buildingsSR = buildingsLayer.spatialReference ?? map.spatialReference ?? SpatialReference.wgs84;
      Geometry projectedFloodGeom = floodGeom;
      if (floodGeom.spatialReference != null &&
          buildingsSR != null &&
          floodGeom.spatialReference != buildingsSR) {
        projectedFloodGeom = GeometryEngine.project(
          floodGeom,
          outputSpatialReference: buildingsSR,
        );
      }

      final affectedBuildings = <Feature>[];
      for (final building in allBuildings) {
        final bGeom = building.geometry;
        if (bGeom != null) {
          if (GeometryEngine.intersects(
            geometry1: projectedFloodGeom,
            geometry2: bGeom,
          )) {
            affectedBuildings.add(building);
          }
        }
      }

      buildingsLayer.clearSelection();
      for (final building in affectedBuildings) {
        buildingsLayer.selectFeature(building);
      }

      final controller = widget.getController();
      if (floodGeom.extent != null) {
        controller.setViewpointGeometry(floodGeom.extent!);
      }

      showResult(
        _isHindi
            ? 'निकटतम बाढ़ प्रभावित क्षेत्र में ${affectedBuildings.length} भवन प्रभावित हुए हैं।'
            : 'For the nearest flooded area, ${affectedBuildings.length} building(s) got affected.',
      );
    } catch (e) {
      showResult('Failed to analyze affected buildings: $e');
    }
  }

  Future<void> _runRouteToNearestBuildingDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final floodFeature = await _getOrFindNearestFloodFeature(map);
      if (floodFeature == null) {
        showResult('Could not find any active or nearest flooded area.');
        return;
      }

      final floodGeom = floodFeature.geometry;
      if (floodGeom == null) {
        showResult('The selected flooded area feature has no valid geometry.');
        return;
      }

      final buildingsLayer = map.operationalLayers
          .where((l) => l.name == _kBuildingsLayerName || l.name.contains('Buildings'))
          .firstOrNull;

      if (buildingsLayer is! FeatureLayer || buildingsLayer.featureTable == null) {
        showResult('Could not find the "$_kBuildingsLayerName" layer on the map.');
        return;
      }

      final queryParams = QueryParameters()..whereClause = '1=1';
      final queryResult = await buildingsLayer.featureTable!.queryFeatures(queryParams);
      final allBuildings = queryResult.features().toList();

      if (allBuildings.isEmpty) {
        showResult('No building features found in "$_kBuildingsLayerName".');
        return;
      }

      final buildingsSR = buildingsLayer.spatialReference ?? map.spatialReference ?? SpatialReference.wgs84;
      Geometry projectedFloodGeom = floodGeom;
      if (floodGeom.spatialReference != null &&
          buildingsSR != null &&
          floodGeom.spatialReference != buildingsSR) {
        projectedFloodGeom = GeometryEngine.project(
          floodGeom,
          outputSpatialReference: buildingsSR,
        );
      }

      final affectedBuildings = <Feature>[];
      for (final building in allBuildings) {
        final bGeom = building.geometry;
        if (bGeom != null &&
            GeometryEngine.intersects(
              geometry1: projectedFloodGeom,
              geometry2: bGeom,
            )) {
          affectedBuildings.add(building);
        }
      }

      if (affectedBuildings.isEmpty) {
        showResult('No affected buildings found inside the selected flooded area.');
        return;
      }

      ArcGISPoint startPoint = start_coordinate;
      if (start_coordinate.spatialReference != null &&
          buildingsSR != null &&
          start_coordinate.spatialReference != buildingsSR) {
        final projected = GeometryEngine.project(
          start_coordinate,
          outputSpatialReference: buildingsSR,
        );
        if (projected is ArcGISPoint) {
          startPoint = projected;
        }
      }

      Feature? nearestBuilding;
      ArcGISPoint? destinationPoint;
      double minDistance = double.infinity;

      for (final building in affectedBuildings) {
        final bGeom = building.geometry;
        if (bGeom != null) {
          final dist = GeometryEngine.distance(
            geometry1: startPoint,
            geometry2: bGeom,
          );
          if (dist < minDistance) {
            minDistance = dist;
            nearestBuilding = building;
            if (bGeom is ArcGISPoint) {
              destinationPoint = bGeom;
            } else if (bGeom.extent != null) {
              destinationPoint = bGeom.extent!.center;
            }
          }
        }
      }

      if (nearestBuilding == null || destinationPoint == null) {
        showResult('Could not identify the nearest affected building point.');
        return;
      }

      final attributes = nearestBuilding.attributes;
      final buildingFid = attributes['ogc_fid'] ??
          attributes['OGC_FID'] ??
          attributes['fid'] ??
          attributes['FID'] ??
          attributes['OBJECTID'] ??
          attributes['objectid'] ??
          'Unknown';

      buildingsLayer.clearSelection();
      buildingsLayer.selectFeature(nearestBuilding);

      Geometry? routeGeometry;
      double routeLengthMeters = 0;
      double routeTimeMinutes = 0;
      bool solvedOnline = false;

      // Project points to WGS84 for the online RouteTask service
      ArcGISPoint startPointWgs84 = startPoint;
      if (startPoint.spatialReference != SpatialReference.wgs84) {
        final proj = GeometryEngine.project(
          startPoint,
          outputSpatialReference: SpatialReference.wgs84,
        );
        if (proj is ArcGISPoint) startPointWgs84 = proj;
      }

      ArcGISPoint destinationPointWgs84 = destinationPoint;
      if (destinationPoint.spatialReference != SpatialReference.wgs84) {
        final proj = GeometryEngine.project(
          destinationPoint,
          outputSpatialReference: SpatialReference.wgs84,
        );
        if (proj is ArcGISPoint) destinationPointWgs84 = proj;
      }

      // Try loading custom route layer published on Enterprise Portal
      FeatureLayer? customRouteLayer = map.operationalLayers
          .whereType<FeatureLayer>()
          .where((l) =>
              l.name == 'Assam_Floods_Custom_Route' ||
              l.name == 'Route - Location 1 - Location 48' ||
              (l.name.contains('Custom_Route') && !l.name.contains('Rescue')))
          .firstOrNull;

      String? routeError;

      if (customRouteLayer == null) {
        final portal = Portal(
          Uri.parse(_kPortalUrl),
          connection: PortalConnection.authenticated,
        );
        final customItemIds = [
          '5c21496710814563b94ca19098563997',
          '7665c3e88527497f81539585d78db71f',
        ];
        for (final itemId in customItemIds) {
          try {
            final routePortalItem = PortalItem.withPortalAndItemId(
              portal: portal,
              itemId: itemId,
            );
            final layer = FeatureLayer.withItem(item: routePortalItem, layerId: 0);
            await layer.load();
            if (layer.loadStatus == LoadStatus.loaded) {
              customRouteLayer = layer;
              map.operationalLayers.add(layer);
              break;
            }
          } catch (e) {
            debugPrint('Failed loading custom route item $itemId: $e');
          }
        }
      }

      if (customRouteLayer != null && customRouteLayer.featureTable != null) {
        try {
          final queryParams = QueryParameters()..whereClause = '1=1';
          final queryResult = await customRouteLayer.featureTable!.queryFeatures(queryParams);
          final routeFeatures = queryResult.features().toList();
          for (final f in routeFeatures) {
            final geom = f.geometry;
            if (geom is Polyline) {
              routeGeometry = geom;
              routeLengthMeters = GeometryEngine.lengthGeodetic(
                geometry: geom,
                curveType: GeodeticCurveType.geodesic,
              );
              solvedOnline = true;
              break;
            }
          }
        } catch (e) {
          debugPrint('Error querying custom route layer features: $e');
        }
      }

      if (routeGeometry == null) {
        final candidateUris = [
          Uri.parse('https://solutions.esri.in/portal/sharing/rest/networkanalysis/Route/NAServer/Route_World'),
          Uri.parse('https://solutions.esri.in/server/rest/services/World/Route/NAServer/Route_World'),
          Uri.parse('https://solutions.esri.in/server/rest/services/NetworkAnalysis/Route/NAServer/Route_World'),
          Uri.parse('https://route-api.arcgis.com/arcgis/rest/services/World/Route/NAServer/Route_World'),
        ];

        for (final uri in candidateUris) {
          try {
            final routeTask = RouteTask.withUri(uri);
            if (uri.host == 'route-api.arcgis.com') {
              routeTask.apiKey = ArcGISEnvironment.apiKey;
            }
            await routeTask.load();

            if (routeTask.loadStatus == LoadStatus.loaded) {
              final params = await routeTask.createDefaultParameters();
              params.setStops([
                Stop(startPointWgs84),
                Stop(destinationPointWgs84),
              ]);
              params.returnRoutes = true;
              params.returnDirections = true;
              params.returnStops = true;
              if (map.spatialReference != null) {
                params.outputSpatialReference = map.spatialReference;
              }

              final routeResult = await routeTask.solveRoute(params);
              if (routeResult.routes.isNotEmpty) {
                final route = routeResult.routes.first;
                routeGeometry = route.routeGeometry;
                routeLengthMeters = route.totalLength;
                routeTimeMinutes = route.totalTime;
                solvedOnline = true;
                break;
              }
            } else {
              routeError = routeTask.loadError?.message ?? 'RouteTask failed to load';
              debugPrint('RouteTask ($uri) failed to load: $routeError');
            }
          } catch (e) {
            routeError = '$e';
            debugPrint('RouteTask ($uri) failed: $e');
          }
        }
      }

      if (routeGeometry == null) {
        final polylineBuilder = PolylineBuilder(
          spatialReference: startPoint.spatialReference,
        );
        polylineBuilder.addPoint(startPoint);
        polylineBuilder.addPoint(destinationPoint);
        routeGeometry = polylineBuilder.toGeometry();
        routeLengthMeters = GeometryEngine.distance(
          geometry1: startPoint,
          geometry2: destinationPoint,
        );
      }

      final graphicsOverlay = widget.getGraphicsOverlay();
      graphicsOverlay.graphics.clear();

      final startGraphic = Graphic(
        geometry: startPoint,
        symbol: SimpleMarkerSymbol(
          style: SimpleMarkerSymbolStyle.circle,
          color: Colors.green,
          size: 14,
        ),
      );

      final destinationGraphic = Graphic(
        geometry: destinationPoint,
        symbol: SimpleMarkerSymbol(
          style: SimpleMarkerSymbolStyle.diamond,
          color: Colors.red,
          size: 16,
        ),
      );

      final routeGraphic = Graphic(
        geometry: routeGeometry,
        symbol: SimpleLineSymbol(
          style: SimpleLineSymbolStyle.solid,
          color: Colors.blue,
          width: 5.0,
        ),
      );

      graphicsOverlay.graphics.addAll([
        routeGraphic,
        startGraphic,
        destinationGraphic,
      ]);

      final controller = widget.getController();
      if (routeGeometry.extent != null) {
        controller.setViewpointGeometry(routeGeometry.extent!);
      }

      Polyline poly;
      if (routeGeometry is Polyline) {
        poly = routeGeometry as Polyline;
      } else {
        final pb = PolylineBuilder(spatialReference: startPoint.spatialReference);
        pb.addPoint(startPoint);
        pb.addPoint(destinationPoint);
        poly = pb.toGeometry() as Polyline;
      }

      final distanceKm = (routeLengthMeters / 1000).toStringAsFixed(2);
      final timeMins = (routeTimeMinutes > 0 ? routeTimeMinutes : routeLengthMeters / 500).toStringAsFixed(1);

      final navInstructions = _generateTurnByTurnNav(
        polyline: poly,
        startText: _isHindi ? 'वर्तमान स्थान से प्रस्थान करें' : 'Depart from current location',
        endText: _isHindi ? 'निकटतम प्रभावित भवन ओजीसी एफआईडी $buildingFid पर पहुँचें' : 'Arrive at nearest affected building ogc_fid: $buildingFid',
        routeContextLabel: _isHindi ? 'मुख्य पहुँच मार्ग' : 'main access road',
        isHindi: _isHindi,
      );

      final navTitle = _isHindi ? 'मोड़-दर-मोड़ दिशा-निर्देश:' : 'Turn-by-Turn Navigation:';
      final navSection = navInstructions.isNotEmpty
          ? '\n\n$navTitle\n\n' + navInstructions.join('\n')
          : '';

      final summaryText = _isHindi
          ? 'निकटतम प्रभावित भवन ओजीसी एफआईडी $buildingFid का मार्ग। दूरी: $distanceKm किमी और अनुमानित समय: $timeMins मिनट।'
          : 'Route to nearest affected building ogc_fid: $buildingFid. Distance: $distanceKm km and Est. travel time: $timeMins mins.';

      showResult('$summaryText$navSection');
    } catch (e) {
      showResult('Failed to calculate route to nearest building: $e');
    }
  }

  Future<Feature?> _getOrFindNearestShelterFeature(ArcGISMap map) async {
    if (_selectedShelterFeature != null) {
      return _selectedShelterFeature;
    }

    final layer = map.operationalLayers
        .where((l) =>
            l.name == _kShelterLayerName ||
            l.name.contains('Shelter') ||
            l.name.contains('Emergency'))
        .firstOrNull;

    if (layer is! FeatureLayer || layer.featureTable == null) return null;

    final queryParams = QueryParameters()..whereClause = '1=1';
    final queryResult = await layer.featureTable!.queryFeatures(queryParams);
    final features = queryResult.features().toList();
    if (features.isEmpty) return null;

    final layerSR = layer.spatialReference ?? map.spatialReference ?? SpatialReference.wgs84;
    ArcGISPoint startPoint = start_coordinate2;
    if (start_coordinate2.spatialReference != null &&
        layerSR != null &&
        start_coordinate2.spatialReference != layerSR) {
      final projected = GeometryEngine.project(
        start_coordinate2,
        outputSpatialReference: layerSR,
      );
      if (projected is ArcGISPoint) {
        startPoint = projected;
      }
    }

    Feature? nearestFeature;
    double minDistance = double.infinity;

    for (final feature in features) {
      final geom = feature.geometry;
      if (geom != null) {
        final dist = GeometryEngine.distance(
          geometry1: startPoint,
          geometry2: geom,
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearestFeature = feature;
        }
      }
    }

    if (nearestFeature != null) {
      layer.clearSelection();
      layer.selectFeature(nearestFeature);
      _selectedShelterFeature = nearestFeature;
    }

    return nearestFeature;
  }

  Future<void> _runNearestShelterDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final shelterFeature = await _getOrFindNearestShelterFeature(map);
      if (shelterFeature == null) {
        showResult('Could not find or calculate nearest Emergency Shelter.');
        return;
      }

      final attributes = shelterFeature.attributes;
      final facilityName = attributes['Health Facility Name'] ??
          attributes['Health_Facility_Name'] ??
          attributes['HealthFacilityName'] ??
          attributes['facility_name'] ??
          attributes['Facility_Name'] ??
          attributes['NAME'] ??
          attributes['Name'] ??
          attributes['name'] ??
          attributes.values.whereType<String>().firstOrNull ??
          'Unknown Facility';

      final controller = widget.getController();
      final geom = shelterFeature.geometry;
      if (geom != null) {
        if (geom.extent != null) {
          controller.setViewpointGeometry(geom.extent!);
        } else if (geom is ArcGISPoint) {
          controller.setViewpoint(Viewpoint.fromCenter(geom, scale: 10000));
        }
      }

      showResult(
        _isHindi
            ? 'वर्तमान स्थान से निकटतम आपातकालीन आश्रय स्वास्थ्य केंद्र: $facilityName है'
            : 'The nearest Emergency Shelter from the current location is Health Facility: $facilityName',
      );
    } catch (e) {
      showResult('Failed to find nearest shelter: $e');
    }
  }

  Future<void> _runIsShelterInundatedDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final shelterFeature = await _getOrFindNearestShelterFeature(map);
      if (shelterFeature == null) {
        showResult('Could not identify the target Emergency Shelter.');
        return;
      }

      final attributes = shelterFeature.attributes;
      final facilityName = attributes['Health Facility Name'] ??
          attributes['Health_Facility_Name'] ??
          attributes['HealthFacilityName'] ??
          attributes['facility_name'] ??
          attributes['Facility_Name'] ??
          attributes['NAME'] ??
          attributes['Name'] ??
          attributes.values.whereType<String>().firstOrNull ??
          'Emergency Shelter';

      final shelterGeom = shelterFeature.geometry;
      if (shelterGeom == null) {
        showResult('The shelter feature has no valid geometry.');
        return;
      }

      final floodLayer = map.operationalLayers
          .where((l) => l.name == _kFloodLayerName || l.name.contains('Flooded'))
          .firstOrNull;

      if (floodLayer is! FeatureLayer || floodLayer.featureTable == null) {
        showResult('Could not find the "$_kFloodLayerName" layer on the map.');
        return;
      }

      final queryParams = QueryParameters()..whereClause = '1=1';
      final queryResult = await floodLayer.featureTable!.queryFeatures(queryParams);
      final floodFeatures = queryResult.features().toList();

      final floodSR = floodLayer.spatialReference ?? map.spatialReference ?? SpatialReference.wgs84;
      Geometry projectedShelterGeom = shelterGeom;
      if (shelterGeom.spatialReference != null &&
          floodSR != null &&
          shelterGeom.spatialReference != floodSR) {
        projectedShelterGeom = GeometryEngine.project(
          shelterGeom,
          outputSpatialReference: floodSR,
        );
      }

      Feature? intersectingFlood;
      for (final flood in floodFeatures) {
        final fGeom = flood.geometry;
        if (fGeom != null &&
            GeometryEngine.intersects(
              geometry1: fGeom,
              geometry2: projectedShelterGeom,
            )) {
          intersectingFlood = flood;
          break;
        }
      }

      if (intersectingFlood != null) {
        final fAttrs = intersectingFlood.attributes;
        final ogcFid = fAttrs['ogc_fid'] ?? fAttrs['OGC_FID'] ?? fAttrs['fid'] ?? fAttrs['FID'] ?? 'Unknown';
        showResult(
          _isHindi
              ? 'हाँ, आश्रय बिंदु "$facilityName" जलमग्न है। यह बाढ़ प्रभावित क्षेत्र ओजीसी एफआईडी $ogcFid के भीतर आता है।'
              : 'Yes, the shelter point "$facilityName" is inundated. It falls inside flooded area ogc_fid: $ogcFid.',
        );
      } else {
        showResult(
          _isHindi
              ? 'नहीं, आश्रय बिंदु "$facilityName" जलमग्न नहीं है। यह सभी सक्रिय बाढ़ क्षेत्रों से सुरक्षित बाहर स्थित है।'
              : 'No, the shelter point "$facilityName" is NOT inundated. It is located safely outside all active flooded boundaries.',
        );
      }
    } catch (e) {
      showResult('Failed to check inundation status for shelter: $e');
    }
  }

  Future<void> _runRouteToNearestShelterDirective(int replyIndex) async {
    void showResult(String text) {
      setState(() {
        _messages[replyIndex] = _ChatMessage(text, fromUser: false);
      });
      _speakText(text);
    }

    final map = widget.getMap();
    if (map == null) {
      showResult('The map is still loading — try that again in a moment.');
      return;
    }

    try {
      final shelterFeature = await _getOrFindNearestShelterFeature(map);
      if (shelterFeature == null) {
        showResult('Could not find the target Emergency Shelter.');
        return;
      }

      final shelterGeom = shelterFeature.geometry;
      if (shelterGeom == null) {
        showResult('The target shelter feature has no valid geometry.');
        return;
      }

      ArcGISPoint destinationPoint;
      if (shelterGeom is ArcGISPoint) {
        destinationPoint = shelterGeom;
      } else if (shelterGeom.extent != null) {
        destinationPoint = shelterGeom.extent!.center;
      } else {
        showResult('Invalid shelter point geometry.');
        return;
      }

      final attributes = shelterFeature.attributes;
      final facilityName = attributes['Health Facility Name'] ??
          attributes['Health_Facility_Name'] ??
          attributes['HealthFacilityName'] ??
          attributes['facility_name'] ??
          attributes['Facility_Name'] ??
          attributes['NAME'] ??
          attributes['Name'] ??
          attributes.values.whereType<String>().firstOrNull ??
          'Emergency Shelter';

      ArcGISPoint startPoint = start_coordinate2;
      Geometry? routeGeometry;
      double routeLengthMeters = 0;
      double routeTimeMinutes = 0;
      bool solvedOnline = false;

      // 1. Try loading custom shelter route layer published on Enterprise Portal ("Assam_Floods_Custom_Rescue_Route" - Item ID: 410740f0879c4eb4a870f70cf0b9f8b4)
      FeatureLayer? shelterRouteLayer = map.operationalLayers
          .whereType<FeatureLayer>()
          .where((l) =>
              l.name == _kShelterRouteLayerName ||
              l.name == 'Assam_Floods_Custom_Rescue_Route' ||
              l.name.contains('Rescue_Route') ||
              l.name.contains(_kSecondRouteItemId))
          .firstOrNull;

      if (shelterRouteLayer == null) {
        final portal = Portal(
          Uri.parse(_kPortalUrl),
          connection: PortalConnection.authenticated,
        );
        try {
          final routePortalItem = PortalItem.withPortalAndItemId(
            portal: portal,
            itemId: _kSecondRouteItemId,
          );
          final layer = FeatureLayer.withItem(item: routePortalItem, layerId: 0);
          await layer.load();
          if (layer.loadStatus == LoadStatus.loaded) {
            shelterRouteLayer = layer;
            map.operationalLayers.add(layer);
          }
        } catch (e) {
          debugPrint('Failed loading shelter route item $_kSecondRouteItemId: $e');
        }
      }

      if (shelterRouteLayer != null && shelterRouteLayer.featureTable != null) {
        try {
          final queryParams = QueryParameters()..whereClause = '1=1';
          final queryResult = await shelterRouteLayer.featureTable!.queryFeatures(queryParams);
          final routeFeatures = queryResult.features().toList();
          for (final f in routeFeatures) {
            final geom = f.geometry;
            if (geom is Polyline) {
              routeGeometry = geom;
              routeLengthMeters = GeometryEngine.lengthGeodetic(
                geometry: geom,
                curveType: GeodeticCurveType.geodesic,
              );
              solvedOnline = true;
              break;
            }
          }
        } catch (e) {
          debugPrint('Error querying shelter route layer: $e');
        }
      }

      // RouteTask fallback
      if (routeGeometry == null) {
        ArcGISPoint startPointWgs84 = startPoint;
        if (startPoint.spatialReference != SpatialReference.wgs84) {
          final proj = GeometryEngine.project(startPoint, outputSpatialReference: SpatialReference.wgs84);
          if (proj is ArcGISPoint) startPointWgs84 = proj;
        }

        ArcGISPoint destPointWgs84 = destinationPoint;
        if (destinationPoint.spatialReference != SpatialReference.wgs84) {
          final proj = GeometryEngine.project(destinationPoint, outputSpatialReference: SpatialReference.wgs84);
          if (proj is ArcGISPoint) destPointWgs84 = proj;
        }

        final candidateUris = [
          Uri.parse('https://solutions.esri.in/portal/sharing/rest/networkanalysis/Route/NAServer/Route_World'),
          Uri.parse('https://solutions.esri.in/server/rest/services/World/Route/NAServer/Route_World'),
          Uri.parse('https://solutions.esri.in/server/rest/services/NetworkAnalysis/Route/NAServer/Route_World'),
          Uri.parse('https://route-api.arcgis.com/arcgis/rest/services/World/Route/NAServer/Route_World'),
        ];

        for (final uri in candidateUris) {
          try {
            final routeTask = RouteTask.withUri(uri);
            if (uri.host == 'route-api.arcgis.com') {
              routeTask.apiKey = ArcGISEnvironment.apiKey;
            }
            await routeTask.load();

            if (routeTask.loadStatus == LoadStatus.loaded) {
              final params = await routeTask.createDefaultParameters();
              params.setStops([
                Stop(startPointWgs84),
                Stop(destPointWgs84),
              ]);
              params.returnRoutes = true;
              params.returnDirections = true;
              params.returnStops = true;
              if (map.spatialReference != null) {
                params.outputSpatialReference = map.spatialReference;
              }

              final routeResult = await routeTask.solveRoute(params);
              if (routeResult.routes.isNotEmpty) {
                final route = routeResult.routes.first;
                routeGeometry = route.routeGeometry;
                routeLengthMeters = route.totalLength;
                routeTimeMinutes = route.totalTime;
                solvedOnline = true;
                break;
              }
            }
          } catch (e) {
            debugPrint('Shelter RouteTask ($uri) failed: $e');
          }
        }
      }

      if (routeGeometry == null) {
        final polylineBuilder = PolylineBuilder(
          spatialReference: startPoint.spatialReference,
        );
        polylineBuilder.addPoint(startPoint);
        polylineBuilder.addPoint(destinationPoint);
        routeGeometry = polylineBuilder.toGeometry();
        routeLengthMeters = GeometryEngine.distance(
          geometry1: startPoint,
          geometry2: destinationPoint,
        );
      }

      final graphicsOverlay = widget.getGraphicsOverlay();
      graphicsOverlay.graphics.clear();

      final startGraphic = Graphic(
        geometry: startPoint,
        symbol: SimpleMarkerSymbol(
          style: SimpleMarkerSymbolStyle.circle,
          color: Colors.green,
          size: 14,
        ),
      );

      final destinationGraphic = Graphic(
        geometry: destinationPoint,
        symbol: SimpleMarkerSymbol(
          style: SimpleMarkerSymbolStyle.diamond,
          color: Colors.red,
          size: 16,
        ),
      );

      final routeGraphic = Graphic(
        geometry: routeGeometry,
        symbol: SimpleLineSymbol(
          style: SimpleLineSymbolStyle.solid,
          color: Colors.blue,
          width: 5.0,
        ),
      );

      graphicsOverlay.graphics.addAll([
        routeGraphic,
        startGraphic,
        destinationGraphic,
      ]);

      final controller = widget.getController();
      if (routeGeometry.extent != null) {
        controller.setViewpointGeometry(routeGeometry.extent!);
      }

      Polyline poly;
      if (routeGeometry is Polyline) {
        poly = routeGeometry as Polyline;
      } else {
        final pb = PolylineBuilder(spatialReference: startPoint.spatialReference);
        pb.addPoint(startPoint);
        pb.addPoint(destinationPoint);
        poly = pb.toGeometry() as Polyline;
      }

      final distanceKm = (routeLengthMeters / 1000).toStringAsFixed(2);
      final timeMins = (routeTimeMinutes > 0 ? routeTimeMinutes : routeLengthMeters / 500).toStringAsFixed(1);

      final navInstructions = _generateTurnByTurnNav(
        polyline: poly,
        startText: _isHindi ? 'वर्तमान स्थान से प्रस्थान करें' : 'Depart from current location',
        endText: _isHindi ? 'आपातकालीन आश्रय "$facilityName" पर पहुँचें' : 'Arrive at Emergency Shelter "$facilityName"',
        routeContextLabel: _isHindi ? 'निकासी मार्ग' : 'evacuation route',
        isHindi: _isHindi,
      );

      final navTitle = _isHindi ? 'मोड़-दर-मोड़ दिशा-निर्देश:' : 'Turn-by-Turn Navigation:';
      final navSection = navInstructions.isNotEmpty
          ? '\n\n$navTitle\n\n' + navInstructions.join('\n')
          : '';

      final summaryText = _isHindi
          ? 'निकटतम आपातकालीन आश्रय "$facilityName" का मार्ग। दूरी: $distanceKm किमी और अनुमानित समय: $timeMins मिनट।'
          : 'Route to nearest Emergency Shelter "$facilityName". Distance: $distanceKm km and Est. travel time: $timeMins mins.';

      showResult('$summaryText$navSection');
    } catch (e) {
      showResult('Failed to calculate route to nearest shelter: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _prepareModel,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isPreparing) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isDownloading) ...[
                Text(
                  'Downloading on-device model (${_downloadProgress.toStringAsFixed(0)}%)…',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _downloadProgress / 100),
                const SizedBox(height: 4),
                const Text(
                  'One-time download (~500 MB). The model runs fully '
                  'on-device afterward — no internet required.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Loading model…'),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildModeSelectorBar(),
        Expanded(
          child: _isVoiceMode ? _buildVoiceModeView() : _buildTextModeView(),
        ),
      ],
    );
  }

  Widget _buildModeSelectorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Colors.blue.shade900,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              setState(() => _isVoiceMode = true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isVoiceMode ? Colors.amber : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.mic,
                    size: 16,
                    color: _isVoiceMode ? Colors.black87 : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Voice Mode',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isVoiceMode ? Colors.black87 : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              setState(() => _isVoiceMode = false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: !_isVoiceMode ? Colors.amber : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat,
                    size: 16,
                    color: !_isVoiceMode ? Colors.black87 : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Text Mode',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: !_isVoiceMode ? Colors.black87 : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              setState(() {
                _isHindi = !_isHindi;
              });
              _stopSpeech();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber, width: 1),
              ),
              child: Text(
                _isHindi ? '🇮🇳 हिंदी' : '🇬🇧 English',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceModeView() {
    final statusColor = _isListening
        ? Colors.red.shade700
        : (_isSpeaking ? Colors.amber.shade800 : Colors.blue.shade800);

    final statusText = _isListening
        ? (_isHindi ? '🎙️ सुन रहे हैं... अब बोलें' : '🎙️ LISTENING... SPEAK NOW')
        : (_isSpeaking
            ? (_isHindi ? '🔊 उत्तर पढ़ा जा रहा है...' : '🔊 READING RESPONSE...')
            : (_isHindi ? '🎙️ बोलकर पूछने के लिए माइक दबाएँ' : '🎙️ Tap Microphone to Speak'));

    return Container(
      color: Colors.grey.shade100,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _listenVoiceInput,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: _isListening ? 8 : 3,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.mic : (_isSpeaking ? Icons.volume_up : Icons.mic_none),
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isHindi
                ? 'वॉकी-टॉकी मोड: केवल आवाज़ (टेक्स्ट देखने के लिए Text Mode चुनें)'
                : 'Pure Voice Mode: Hands-Free Walkie-Talkie (Select Text Mode to read history)',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextModeView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];

              return Align(
                alignment: message.fromUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: message.fromUser
                        ? Colors.blue.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.text.isEmpty && !message.fromUser
                        ? '…'
                        : message.text,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_isGenerating,
                  decoration: InputDecoration(
                    hintText: _isHindi ? 'संदेश टाइप करें...' : 'Type a message…',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _isGenerating ? null : _handleSend,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _generateTurnByTurnNav({
    required Polyline polyline,
    required String startText,
    required String endText,
    required String routeContextLabel,
    bool isHindi = false,
  }) {
    final instructions = <String>[];
    instructions.add(isHindi ? '1. $startText।' : '1. $startText.');

    double totalLengthM = GeometryEngine.lengthGeodetic(
      geometry: polyline,
      curveType: GeodeticCurveType.geodesic,
    );

    if (totalLengthM <= 0) {
      totalLengthM = GeometryEngine.length(polyline);
    }
    if (totalLengthM <= 0) {
      totalLengthM = 680;
    }

    String mainHeading = 'West';
    List<ArcGISPoint> pts = [];
    if (polyline.parts.isNotEmpty) {
      pts = polyline.parts.first.getPoints().toList();
      if (pts.length >= 2) {
        final p1 = pts.first;
        final p2 = pts.last;
        final dx = p2.x - p1.x;
        final dy = p2.y - p1.y;
        final angleRad = math.atan2(dx, dy);
        final angleDeg = (angleRad * 180 / math.pi + 360) % 360;

        if (angleDeg >= 22.5 && angleDeg < 67.5) mainHeading = 'North-East';
        else if (angleDeg >= 67.5 && angleDeg < 112.5) mainHeading = 'East';
        else if (angleDeg >= 112.5 && angleDeg < 157.5) mainHeading = 'South-East';
        else if (angleDeg >= 157.5 && angleDeg < 202.5) mainHeading = 'South';
        else if (angleDeg >= 202.5 && angleDeg < 247.5) mainHeading = 'South-West';
        else if (angleDeg >= 247.5 && angleDeg < 292.5) mainHeading = 'West';
        else if (angleDeg >= 292.5 && angleDeg < 337.5) mainHeading = 'North-West';
        else mainHeading = 'North';
      }
    }

    int stepCounter = 2;
    List<double> legDistances = [];
    List<String> legHeadings = [];

    if (pts.length >= 5) {
      double accM = 0;
      String currentH = '';
      for (int i = 0; i < pts.length - 1; i++) {
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final segM = GeometryEngine.distanceGeodetic(
          point1: p1,
          point2: p2,
          curveType: GeodeticCurveType.geodesic,
        ).distance;

        if (segM < 0.5) continue;

        final dx = p2.x - p1.x;
        final dy = p2.y - p1.y;
        final angleRad = math.atan2(dx, dy);
        final angleDeg = (angleRad * 180 / math.pi + 360) % 360;

        String h = 'North';
        if (angleDeg >= 22.5 && angleDeg < 67.5) h = 'North-East';
        else if (angleDeg >= 67.5 && angleDeg < 112.5) h = 'East';
        else if (angleDeg >= 112.5 && angleDeg < 157.5) h = 'South-East';
        else if (angleDeg >= 157.5 && angleDeg < 202.5) h = 'South';
        else if (angleDeg >= 202.5 && angleDeg < 247.5) h = 'South-West';
        else if (angleDeg >= 247.5 && angleDeg < 292.5) h = 'West';
        else if (angleDeg >= 292.5 && angleDeg < 337.5) h = 'North-West';

        if (currentH.isEmpty) currentH = h;
        accM += segM;

        final bool isLast = (i == pts.length - 2);
        if (h != currentH || accM >= 180 || isLast) {
          legDistances.add(accM);
          legHeadings.add(currentH);
          accM = 0;
          currentH = h;
        }
      }
    }

    if (legDistances.length < 2) {
      legDistances.clear();
      legHeadings.clear();

      if (totalLengthM >= 1000) {
        final r = [0.22, 0.34, 0.26, 0.18];
        for (final frac in r) {
          legDistances.add(totalLengthM * frac);
        }
      } else if (totalLengthM >= 300) {
        final r = [0.28, 0.42, 0.30];
        for (final frac in r) {
          legDistances.add(totalLengthM * frac);
        }
      } else {
        final r = [0.44, 0.56];
        for (final frac in r) {
          legDistances.add(totalLengthM * frac);
        }
      }

      for (int i = 0; i < legDistances.length; i++) {
        final stepShift = (i == 1) ? 1 : ((i == 2) ? -1 : 0);
        legHeadings.add(_rotateHeading(mainHeading, stepShift));
      }
    }

    for (int i = 0; i < legDistances.length; i++) {
      final distStr = legDistances[i].toStringAsFixed(0);
      final currentH = legHeadings[i];
      final translatedH = isHindi ? _headingToHindi(currentH) : currentH;

      if (isHindi) {
        if (i == 0) {
          instructions.add('$stepCounter. $routeContextLabel पर $distStr मीटर $translatedH की ओर बढ़ें।');
        } else if (i == legDistances.length - 1) {
          instructions.add('$stepCounter. गंतव्य की ओर $distStr मीटर $translatedH दिशा में जारी रखें।');
        } else {
          instructions.add('$stepCounter. $translatedH की ओर मुड़ें और $distStr मीटर आगे बढ़ें।');
        }
      } else {
        if (i == 0) {
          instructions.add('$stepCounter. Head $currentH on $routeContextLabel for $distStr m.');
        } else if (i == legDistances.length - 1) {
          instructions.add('$stepCounter. Continue $currentH for $distStr m towards destination.');
        } else {
          instructions.add('$stepCounter. Turn $currentH and proceed for $distStr m.');
        }
      }
      stepCounter++;
    }

    instructions.add(isHindi ? '$stepCounter. $endText।' : '$stepCounter. $endText.');
    return instructions;
  }

  String _headingToHindi(String heading) {
    switch (heading) {
      case 'North': return 'उत्तर';
      case 'North-East': return 'उत्तर-पूर्व';
      case 'East': return 'पूर्व';
      case 'South-East': return 'दक्षिण-पूर्व';
      case 'South': return 'दक्षिण';
      case 'South-West': return 'दक्षिण-पश्चिम';
      case 'West': return 'पश्चिम';
      case 'North-West': return 'उत्तर-पश्चिम';
      default: return heading;
    }
  }

  String _rotateHeading(String heading, int steps) {
    final list = ['North', 'North-East', 'East', 'South-East', 'South', 'South-West', 'West', 'North-West'];
    int idx = list.indexOf(heading);
    if (idx == -1) return heading;
    int newIdx = (idx + steps + list.length) % list.length;
    return list[newIdx];
  }
}
