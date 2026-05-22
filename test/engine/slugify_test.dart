import 'package:equation_solver_app/engine/slugify.dart';
import 'package:test/test.dart';

void main() {
  group('slugify', () {
    test('alphanumeric passes through', () {
      expect(slugify('K'), equals('K'));
      expect(slugify('Me'), equals('Me'));
      expect(slugify('Pm123'), equals('Pm123'));
    });
    test('legacy "y(t) air" → "y_t_air"', () {
      expect(slugify('y(t) air'), equals('y_t_air'));
    });
    test('starts with digit → prefixed', () {
      expect(slugify('1st'), equals('_1st'));
    });
    test('empty → underscore', () {
      expect(slugify(''), equals('_'));
    });
    test('multiple separators collapse', () {
      expect(slugify('a b  c'), equals('a_b_c'));
    });
    test('trims leading/trailing separators', () {
      expect(slugify(' x '), equals('x'));
    });
  });

  group('SlugAllocator', () {
    test('first slug unchanged', () {
      final a = SlugAllocator();
      expect(a.allocate('y(t) air'), equals('y_t_air'));
    });
    test('second collision gets _2 suffix', () {
      final a = SlugAllocator();
      a.allocate('y(t) air');
      expect(a.allocate('y t air'), equals('y_t_air_2'));
    });
    test('third collision _3, etc.', () {
      final a = SlugAllocator();
      a.allocate('x');
      a.allocate('x');
      expect(a.allocate('x'), equals('x_3'));
    });
    test('preallocated identifiers are reserved', () {
      final a = SlugAllocator(reserved: {'K'});
      expect(a.allocate('K'), equals('K_2'));
    });
  });
}
