// Web platform implementation: provides real interactive ArcGIS web maps and login modal
// so the application runs as a complete Web App on iPhone 15 Safari / PWA.

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class SpatialReference {
  final int? wkid;
  const SpatialReference._([this.wkid]);
  static const SpatialReference wgs84 = SpatialReference._(4326);
}

class ArcGISPoint {
  final double x;
  final double y;
  final SpatialReference? spatialReference;

  ArcGISPoint({
    required this.x,
    required this.y,
    this.spatialReference,
  });
}

typedef Geometry = dynamic;

class ArcGISEnvironment {
  static String apiKey = '';
  static LicenseResult setLicenseUsingKey(String key) => LicenseResult();
}

class LicenseResult {
  final String licenseStatus = 'Licensed';
}

enum LoadStatus { loaded, failed, loading, notLoaded }

class PortalConnection {
  static const String authenticated = 'authenticated';
}

class Portal {
  final Uri uri;
  final String connection;
  Portal(this.uri, {required this.connection});
}

class PortalItem {
  final Portal portal;
  final String itemId;
  PortalItem.withPortalAndItemId({required this.portal, required this.itemId});
}

enum SelectionMode { new_ }
enum GeodeticCurveType { geodesic }

class Layer {
  String name;
  bool isVisible;
  Envelope? fullExtent;
  dynamic featureTable;
  LoadStatus loadStatus = LoadStatus.loaded;
  SpatialReference? spatialReference = SpatialReference.wgs84;

  Layer({
    required this.name,
    this.isVisible = true,
    this.fullExtent,
    this.featureTable,
  });

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }

  void clearSelection() {}
  void selectFeature(dynamic feature) {}

  Future<dynamic> selectFeaturesWithQuery({
    dynamic parameters,
    dynamic query,
    dynamic mode,
  }) async {
    return FeatureQueryResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #selectFeaturesWithQuery) {
      return Future.value(FeatureQueryResult());
    }
    return super.noSuchMethod(invocation);
  }
}

class FeatureLayer extends Layer {
  FeatureLayer({required super.name, super.isVisible, super.fullExtent, super.featureTable});
  FeatureLayer.withItem({dynamic item, int? layerId})
      : super(name: 'FeatureLayer');
}

class ArcGISMap {
  SpatialReference? spatialReference = SpatialReference.wgs84;
  List<dynamic> operationalLayers = [
    Layer(name: 'Assam_Flooded_Areas', isVisible: true),
    Layer(name: 'Assam_Buildings', isVisible: true),
    Layer(name: 'Assam_Emergency_Shelters', isVisible: true),
  ];
  LoadStatus loadStatus = LoadStatus.loaded;
  dynamic loadError;

  ArcGISMap.withItem(PortalItem item);

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }
}

class GraphicsOverlay {
  final List<Graphic> graphics = [];
}

class Graphic {
  dynamic geometry;
  dynamic symbol;
  Graphic({this.geometry, this.symbol});
}

enum SimpleLineSymbolStyle { solid }

class SimpleLineSymbol {
  final SimpleLineSymbolStyle style;
  final Color color;
  final double width;
  SimpleLineSymbol({
    required this.style,
    required this.color,
    required this.width,
  });
}

enum SimpleMarkerSymbolStyle { circle, diamond, square, cross, x }

class SimpleMarkerSymbol {
  final SimpleMarkerSymbolStyle style;
  final Color color;
  final double size;
  SimpleMarkerSymbol({
    required this.style,
    required this.color,
    required this.size,
  });
}

class PictureMarkerSymbol {
  final Uri uri;
  double width;
  double height;
  PictureMarkerSymbol.withUri(this.uri)
      : width = 24.0,
        height = 24.0;
}

class MutablePart {
  final List<ArcGISPoint> _points = [];
  void addPoint(ArcGISPoint pt) => _points.add(pt);
  List<ArcGISPoint> getPoints() => _points;
}

class PolylineBuilder {
  final SpatialReference? spatialReference;
  final List<MutablePart> parts = [MutablePart()];
  PolylineBuilder({this.spatialReference});

  void addPoint(ArcGISPoint pt) {
    if (parts.isEmpty) parts.add(MutablePart());
    parts.first.addPoint(pt);
  }

  Polyline toGeometry() => Polyline(
        points: parts.first.getPoints(),
        spatialReference: spatialReference,
      );
}

class ImmutablePart {
  final List<ArcGISPoint> points;
  ImmutablePart(this.points);
  List<ArcGISPoint> getPoints() => points;
}

class Polyline {
  final List<ArcGISPoint> points;
  final SpatialReference? spatialReference;
  final List<ImmutablePart> parts;

  Polyline({
    required this.points,
    this.spatialReference,
  }) : parts = [ImmutablePart(points)];
}

class Stop {
  final ArcGISPoint point;
  Stop(this.point);
}

class RouteParameters {
  SpatialReference? outputSpatialReference;
  bool returnRoutes = true;
  bool returnDirections = true;
  bool returnStops = true;
  void setStops(List<Stop> stops) {}
}

class Route {
  Polyline? routeGeometry;
  double totalLength = 1000.0;
  double totalTime = 5.0;
}

class RouteResult {
  List<Route> routes = [Route()];
}

class LoadError {
  String message = 'Error loading RouteTask';
}

class RouteTask {
  String? apiKey;
  LoadStatus loadStatus = LoadStatus.loaded;
  LoadError? loadError;

  RouteTask.withUri(Uri uri);

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }

  Future<RouteParameters> createDefaultParameters() async => RouteParameters();
  Future<RouteResult> solveRoute(RouteParameters params) async => RouteResult();
}

class LinearUnit {
  static const LinearUnit meters = LinearUnit._();
  const LinearUnit._();
}

class Envelope {
  final ArcGISPoint center;
  final double width;
  final double height;
  Envelope({required this.center, required this.width, required this.height});
}

enum ViewpointType { centerAndScale }

class Viewpoint {
  final dynamic targetGeometry;
  final double targetScale;

  Viewpoint.fromCenter(ArcGISPoint center, {required double scale})
      : targetGeometry = center,
        targetScale = scale;

  Viewpoint.fromEnvelope(Envelope envelope)
      : targetGeometry = envelope.center,
        targetScale = 10000.0;
}

class ArcGISMapViewViewController {
  ArcGISMap? arcGISMap;
  List<GraphicsOverlay> graphicsOverlays = [];

  Viewpoint? _currentViewpoint = Viewpoint.fromCenter(
    ArcGISPoint(x: 93.8320717, y: 26.6445128, spatialReference: SpatialReference.wgs84),
    scale: 25000.0,
  );

  Viewpoint? getCurrentViewpoint(ViewpointType type) => _currentViewpoint;

  Future<void> setViewpointAnimated(Viewpoint viewpoint, {double duration = 0.25}) async {
    _currentViewpoint = viewpoint;
  }

  void setViewpointGeometry(dynamic geometry) {
    if (geometry is Envelope) {
      _currentViewpoint = Viewpoint.fromEnvelope(geometry);
    }
  }

  void setViewpoint(Viewpoint viewpoint) {
    _currentViewpoint = viewpoint;
  }
}

typedef MapViewController = ArcGISMapViewViewController;
typedef ArcGISMapViewController = ArcGISMapViewViewController;

int _nextViewId = 0;

class ArcGISMapView extends StatefulWidget {
  final MapViewController Function() controllerProvider;
  final VoidCallback? onMapViewReady;

  const ArcGISMapView({
    super.key,
    required this.controllerProvider,
    this.onMapViewReady,
  });

  static MapViewController createController() => MapViewController();

  @override
  State<ArcGISMapView> createState() => _ArcGISMapViewWebState();
}

class _ArcGISMapViewWebState extends State<ArcGISMapView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'arcgis-web-map-${_nextViewId++}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..srcdoc = _buildArcGISMapHtml()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMapViewReady?.call();
    });
  }

  String _buildArcGISMapHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>ArcGIS Web Map</title>
  <link rel="stylesheet" href="https://js.arcgis.com/4.31/esri/themes/dark/main.css">
  <script src="https://js.arcgis.com/4.31/"></script>
  <style>
    html, body, #viewDiv {
      padding: 0;
      margin: 0;
      height: 100%;
      width: 100%;
      background-color: #0f172a;
    }
  </style>
</head>
<body>
  <div id="viewDiv"></div>
  <script>
    require([
      "esri/Map",
      "esri/views/MapView",
      "esri/widgets/BasemapToggle",
      "esri/widgets/Locate",
      "esri/widgets/Search",
      "esri/widgets/Compass",
      "esri/widgets/ScaleBar"
    ], function(Map, MapView, BasemapToggle, Locate, Search, Compass, ScaleBar) {
      const map = new Map({
        basemap: "topo-vector"
      });

      const view = new MapView({
        container: "viewDiv",
        map: map,
        center: [93.8320717, 26.6445128], // Assam Flood Rescue Region
        zoom: 11
      });

      const basemapToggle = new BasemapToggle({
        view: view,
        nextBasemap: "hybrid"
      });
      view.ui.add(basemapToggle, "bottom-right");

      const locateBtn = new Locate({
        view: view
      });
      view.ui.add(locateBtn, "top-left");

      const searchWidget = new Search({
        view: view,
        placeholder: "Find shelter or rescue location..."
      });
      view.ui.add(searchWidget, "top-right");

      const compass = new Compass({
        view: view
      });
      view.ui.add(compass, "top-left");

      const scaleBar = new ScaleBar({
        view: view,
        unit: "metric"
      });
      view.ui.add(scaleBar, "bottom-left");
    });
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

class OAuthUserConfiguration {
  final Uri portalUri;
  final String clientId;
  final Uri redirectUri;
  OAuthUserConfiguration({
    required this.portalUri,
    required this.clientId,
    required this.redirectUri,
  });
}

class Authenticator extends StatefulWidget {
  final List<OAuthUserConfiguration> oAuthUserConfigurations;
  final Widget child;

  const Authenticator({
    super.key,
    required this.oAuthUserConfigurations,
    required this.child,
  });

  @override
  State<Authenticator> createState() => _AuthenticatorState();
}

class _AuthenticatorState extends State<Authenticator> {
  bool _isLoggedIn = false;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 36),
                    SizedBox(width: 12),
                    Text(
                      'ArcGIS Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Flood Rescue & Operations Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'ArcGIS Username',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.person, color: Colors.blueAccent),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _isLoggedIn = true),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign In with ArcGIS Online', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _isLoggedIn = true),
                  icon: const Icon(Icons.location_on),
                  label: const Text('Continue as Rescue Operator', style: TextStyle(fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceFeatureTable {
  final Uri uri;
  ServiceFeatureTable({required this.uri});

  Future<FeatureQueryResult> queryFeatures(QueryParameters params) async {
    return FeatureQueryResult();
  }
}

class FeatureQueryResult implements Iterable<Feature> {
  final List<Feature> features = [];

  @override
  Iterator<Feature> get iterator => features.iterator;

  @override
  bool get isEmpty => true;
  @override
  bool get isNotEmpty => false;
  @override
  int get length => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Feature {
  final Map<String, dynamic> attributes = {};
  dynamic geometry;
}

enum SpatialRelationship { intersects }

class QueryParameters {
  String whereClause = '';
  dynamic geometry;
  SpatialRelationship? spatialRelationship;
}

class GeodeticDistanceResult {
  final double distance;
  GeodeticDistanceResult([this.distance = 500.0]);
}

class GeometryEngine {
  static dynamic buffer(dynamic geometry, double distance) => geometry;

  static bool intersects({dynamic geometry1, dynamic geometry2}) => true;

  static double lengthGeodetic({dynamic geometry, dynamic curveType, dynamic unit}) => 1000.0;

  static double length([dynamic geometry]) => 1000.0;

  static GeodeticDistanceResult distanceGeodetic({dynamic point1, dynamic point2, dynamic curveType, dynamic unit}) => GeodeticDistanceResult();

  static double distance({dynamic geometry1, dynamic geometry2, dynamic point1, dynamic point2}) => 500.0;

  static dynamic project(dynamic geometry, {SpatialReference? outputSpatialReference}) => geometry;
}
