import 'package:flutter_test/flutter_test.dart';
import 'package:ump_smart_dine/core/utils/formatters.dart';

/// REQ-17, REQ-21, REQ-22, REQ-74.
///
/// The old sign-up form held a `_formKey` and called `validate()`, but no field
/// was given a validator, so it always returned true and an entirely empty form
/// went straight to the network. These tests exist so that cannot regress
/// silently.
void main() {
  group('required', () {
    test('rejects empty and whitespace-only input', () {
      expect(Validators.required('', 'name'), isNotNull);
      expect(Validators.required('   ', 'name'), isNotNull);
      expect(Validators.required(null, 'name'), isNotNull);
    });

    test('accepts real input', () {
      expect(Validators.required('Tshepo', 'name'), isNull);
    });

    test('names the field in the message', () {
      expect(Validators.required('', 'surname'), contains('surname'));
    });
  });

  group('email (REQ-21)', () {
    test('rejects malformed addresses before any network call', () {
      for (final bad in [
        'not-an-email',
        'missing@domain',
        '@ump.ac.za',
        'spaces in@ump.ac.za',
        'trailing@dot.',
      ]) {
        expect(Validators.email(bad), isNotNull, reason: 'should reject "$bad"');
      }
    });

    test('accepts valid addresses', () {
      for (final good in [
        '231112009@ump.ac.za',
        'first.last@ump.ac.za',
        'user+tag@example.co.za',
      ]) {
        expect(Validators.email(good), isNull, reason: 'should accept "$good"');
      }
    });
  });

  group('password (REQ-22)', () {
    test('rejects anything shorter than eight characters', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('1234567'), isNotNull);
    });

    test('states the requirement at the point of failure', () {
      expect(Validators.password('abc'), contains('8 characters'));
    });

    test('accepts eight characters or more', () {
      expect(Validators.password('12345678'), isNull);
    });
  });

  group('confirmPassword', () {
    test('rejects a mismatch', () {
      expect(Validators.confirmPassword('abc12345', 'abc12346'), isNotNull);
    });

    test('accepts a match', () {
      expect(Validators.confirmPassword('abc12345', 'abc12345'), isNull);
    });
  });

  group('identifier', () {
    test('labels the field by role', () {
      expect(Validators.identifier('', isStudent: true), contains('student number'));
      expect(Validators.identifier('', isStudent: false), contains('staff number'));
    });

    test('rejects too-short and illegal characters', () {
      expect(Validators.identifier('12', isStudent: true), isNotNull);
      expect(Validators.identifier('2311 12009', isStudent: true), isNotNull);
      expect(Validators.identifier('231@112009', isStudent: true), isNotNull);
    });

    test('accepts a real student number', () {
      expect(Validators.identifier('231112009', isStudent: true), isNull);
      expect(Validators.identifier('STAFF-0042', isStudent: false), isNull);
    });
  });

  group('phone', () {
    test('rejects too few or too many digits', () {
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('1234567890123456'), isNotNull);
    });

    test('accepts common South African formats', () {
      expect(Validators.phone('0721234567'), isNull);
      expect(Validators.phone('+27 72 123 4567'), isNull);
    });
  });

  group('price (REQ-74)', () {
    test('rejects a negative price', () {
      expect(Validators.price('-1'), contains('negative'));
      expect(Validators.price('-0.01'), isNotNull);
    });

    test('rejects non-numeric input', () {
      // The old editor validated only for emptiness, so text like this reached
      // double.parse and threw inside the save handler.
      expect(Validators.price('abc'), isNotNull);
      expect(Validators.price(''), isNotNull);
    });

    test('accepts a valid amount', () {
      expect(Validators.price('0'), isNull);
      expect(Validators.price('19.99'), isNull);
    });
  });

  group('stock (REQ-74)', () {
    test('rejects negative and fractional counts', () {
      expect(Validators.stock('-1'), contains('negative'));
      expect(Validators.stock('1.5'), isNotNull);
    });

    test('accepts zero and positive whole numbers', () {
      expect(Validators.stock('0'), isNull);
      expect(Validators.stock('25'), isNull);
    });
  });

  group('percent (specials)', () {
    test('accepts 1 to 90', () {
      expect(Validators.percent('1'), isNull);
      expect(Validators.percent('90'), isNull);
    });

    test('rejects out of range, empty and non-numeric input', () {
      expect(Validators.percent('0'), isNotNull);
      expect(Validators.percent('91'), isNotNull);
      expect(Validators.percent(''), isNotNull);
      expect(Validators.percent('ten'), isNotNull);
      expect(Validators.percent('12.5'), isNotNull);
    });
  });

  group('specialPrice', () {
    test('must be a saving on the usual price', () {
      expect(Validators.specialPrice('35', 4500), isNull);
      expect(Validators.specialPrice('45', 4500), isNotNull);
      expect(Validators.specialPrice('50', 4500), isNotNull);
    });

    test('still applies the ordinary price rules', () {
      expect(Validators.specialPrice('', 4500), isNotNull);
      expect(Validators.specialPrice('-1', 4500), isNotNull);
      expect(Validators.specialPrice('abc', 4500), isNotNull);
    });
  });

  group('varieties', () {
    test('a variety needs a short name', () {
      expect(Validators.varietyName('Sweet Chilli'), isNull);
      expect(Validators.varietyName(' '), isNotNull);
      expect(Validators.varietyName('x' * 41), isNotNull);
    });

    test('price difference may be empty, positive or negative', () {
      expect(Validators.priceDelta(''), isNull);
      expect(Validators.priceDelta('5'), isNull);
      expect(Validators.priceDelta('-2.50'), isNull);
      expect(Validators.priceDelta('five'), isNotNull);
    });
  });
}

