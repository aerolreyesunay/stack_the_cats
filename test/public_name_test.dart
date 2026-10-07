import 'package:flutter_test/flutter_test.dart';
import 'package:stack_the_cats/services/public_name.dart';

void main() {
  test('non-friends see first name and last initial', () {
    // The same cases as the server's boardName.
    expect(publicName('Aerol Unay'), 'Aerol U.');
    expect(publicName('  Maria  Clara de la Cruz '), 'Maria C.');
    expect(publicName('Madonna'), 'Madonna');
    expect(publicName('juan dela cruz'), 'juan C.');
    expect(publicName(''), 'Cat stacker');
    expect(publicName(null), 'Cat stacker');
  });
}
