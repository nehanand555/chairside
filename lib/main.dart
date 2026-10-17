import 'package:flutter/material.dart';

import 'state/demo_store.dart';
import 'ui/app.dart';

void main() {
  runApp(ChairsideApp(store: DemoStore()));
}
