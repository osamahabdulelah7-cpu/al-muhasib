import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  test('formatNumber removes unnecessary decimals', () {
    expect(formatNumber(100.0), '100');
    expect(formatNumber(187645.50), '187645.5');
    expect(formatNumber(0.25), '0.25');
  });
}
