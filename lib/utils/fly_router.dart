import 'package:flutter/material.dart';

typedef RouteWidgetBuilder = Widget Function(BuildContext context, RouteSettings settings);
typedef LinkParamMapper = Map<String, dynamic> Function(Map<String, dynamic> params);

class AppRoute {
  const AppRoute({
    required this.name,
    required this.builder,
    this.options = const {},
  });

  final String name;
  final RouteWidgetBuilder builder;
  final Map<String, dynamic> options;
}

abstract class FlyRouteModule {
  List<AppRoute> get routes;
}

abstract class RouteInterceptor {
  String get key;

  RouteSettings? beforeRoute(RouteSettings settings, Map<String, dynamic> routeOptions);
}

class FlyUniLink {
  const FlyUniLink({
    required this.path,
    required this.route,
    this.beforePush,
  });

  final String path;
  final String route;
  final LinkParamMapper? beforePush;
}

class FlyUniLinkOptions {
  const FlyUniLinkOptions({
    this.httpHost,
    this.customScheme,
    this.links = const [],
  });

  final String? httpHost;
  final String? customScheme;
  final List<FlyUniLink> links;
}

class FlyRouter {
  factory FlyRouter() => _instance;

  FlyRouter._();

  static final FlyRouter _instance = FlyRouter._();

  final navigatorKey = GlobalKey<NavigatorState>();

  final Map<String, AppRoute> _routeMap = {};
  List<RouteInterceptor> _interceptors = [];
  FlyUniLinkOptions? _uniLinkOptions;

  void initRoutes(
    List<FlyRouteModule> modules, {
    List<RouteInterceptor> interceptors = const [],
    FlyUniLinkOptions? uniLinkOptions,
  }) {
    _routeMap
      ..clear()
      ..addEntries(
        modules
            .expand((module) => module.routes)
            .map((route) => MapEntry(route.name, route)),
      );
    _interceptors = interceptors;
    _uniLinkOptions = uniLinkOptions;
  }

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final requestedName = settings.name ?? '/';
    final route = _routeMap[requestedName] ?? _routeMap['/'];

    if (route == null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _UnknownRoutePage(routeName: requestedName),
      );
    }

    final nextSettings = _applyInterceptors(settings, route.options);
    if (nextSettings != null && nextSettings.name != requestedName) {
      return onGenerateRoute(nextSettings);
    }

    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (context) => route.builder(context, settings),
    );
  }

  RouteSettings? _applyInterceptors(
    RouteSettings settings,
    Map<String, dynamic> routeOptions,
  ) {
    for (final interceptor in _interceptors) {
      final next = interceptor.beforeRoute(settings, routeOptions);
      if (next != null) return next;
    }
    return null;
  }

  BuildContext? getContext() => navigatorKey.currentContext;

  Future<T?> push<T extends Object?>(String name, {Object? arguments}) {
    return navigatorKey.currentState!.pushNamed<T>(name, arguments: arguments);
  }

  Future<T?> replace<T extends Object?, TO extends Object?>(
    String name, {
    Object? arguments,
    TO? result,
  }) {
    return navigatorKey.currentState!.pushReplacementNamed<T, TO>(
      name,
      arguments: arguments,
      result: result,
    );
  }

  void pop<T extends Object?>([T? result]) {
    return navigatorKey.currentState!.pop<T>(result);
  }

  bool canPop() => navigatorKey.currentState?.canPop() ?? false;

  Future<bool> openUri(Uri uri) {
    final options = _uniLinkOptions;
    if (options == null) return Future.value(false);

    final isSchemeMatch = options.customScheme != null && uri.scheme == options.customScheme;
    final isHostMatch = options.httpHost != null && uri.host == options.httpHost;
    if (!isSchemeMatch && !isHostMatch) return Future.value(false);

    for (final link in options.links) {
      if (link.path != uri.path) continue;
      final params = Map<String, dynamic>.from(uri.queryParameters);
      final mapped = link.beforePush?.call(params) ?? params;
      push<void>(link.route, arguments: mapped);
      return Future.value(true);
    }

    return Future.value(false);
  }
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.routeName});

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(child: Text('未注册路由：$routeName')),
    );
  }
}
