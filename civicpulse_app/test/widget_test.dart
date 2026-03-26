import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:civicpulse_app/main.dart';

void main() {
  testWidgets('CivicPulse app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const CivicPulseApp());

    // Verify MaterialApp is loaded
    expect(find.byType(MaterialApp), findsOneWidget);

    // Verify loading indicator appears initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}