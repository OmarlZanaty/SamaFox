import 'package:flutter/widgets.dart';

/// Lets a screen know when another route covers it and when it is back on top
/// (see HomeScreen, which lets go of its room covers while a room is open).
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
