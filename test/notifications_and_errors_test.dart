import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ump_smart_dine/core/error/app_error.dart';
import 'package:ump_smart_dine/core/notifications/notification_prefs.dart';
import 'package:ump_smart_dine/data/models/models.dart';

/// The two causes of "something went wrong" at checkout, and the notification
/// rules for order updates.
void main() {
  group(
    'AppError — payment function failures (was: "Something went wrong")',
    () {
      AppError fn(int status, [Object? details]) =>
          AppError.from(FunctionException(status: status, details: details));

      test('payment service not set up yet reads as such', () {
        expect(
          fn(503, {'error': 'YOCO_NOT_CONFIGURED'}).message,
          contains("Card payment isn't available yet"),
        );
      });

      test('a function that is not deployed (404) is not a generic error', () {
        expect(fn(404).message, contains("Card payment isn't available yet"));
      });

      test('known codes get their own sentence', () {
        expect(
          fn(409, {'error': 'ALREADY_PAID'}).message,
          contains('already been paid'),
        );
        expect(
          fn(502, {'error': 'YOCO_INIT_FAILED'}).message,
          contains('Yoco could not start'),
        );
        expect(fn(401).message, contains('sign in again'));
      });

      test('anything else still names the payment service', () {
        expect(
          fn(500, {'error': 'INTERNAL_ERROR'}).message,
          contains('payment service is unavailable'),
        );
      });
    },
  );

  group('AppError — database behind the app', () {
    test('a missing column (the live orders bug) asks for the migration', () {
      final error = AppError.from(
        const PostgrestException(
          message:
              'column "payment_method" of relation "orders" does not exist',
          code: '42703',
        ),
      );
      expect(error.message, contains('database update'));
      expect(error.isRecoverable, isFalse);
    });

    test('a missing function asks for the migration', () {
      final error = AppError.from(
        const PostgrestException(
          message: 'Could not find the function public.reserve_line',
          code: 'PGRST202',
        ),
      );
      expect(error.message, contains('database update'));
    });

    test('RPC error tokens still map to their sentences', () {
      final error = AppError.from(
        const PostgrestException(message: 'INSUFFICIENT_STOCK', code: 'P0001'),
      );
      expect(error.message, 'Sorry, that item just sold out.');
    });

    test('coded Dart errors are mapped too', () {
      expect(
        AppError.from(StateError('CART_SPANS_CAFETERIAS')).message,
        contains('more than one cafeteria'),
      );
    });
  });

  group('Order.paymentLabel', () {
    Order order(String method, String state) => Order.fromMap({
      'id': 'o',
      'payment_method': method,
      'payment_state': state,
      'collection_ref': 'K7P2QX',
    });

    test('"Pay at counter" only for cash', () {
      expect(order('cash', 'pending').paymentLabel, 'Pay at counter');
      expect(order('card', 'pending').paymentLabel, 'Awaiting card payment');
      expect(order('card', 'paid').paymentLabel, 'Paid');
      expect(order('card', 'failed').paymentLabel, 'Card payment failed');
    });
  });

  group('NotificationKind', () {
    test('students and staff each see only their kinds', () {
      final student = NotificationKind.forRole(UserRole.student);
      final staff = NotificationKind.forRole(UserRole.staff);

      expect(student, contains(NotificationKind.orderReady));
      expect(student, isNot(contains(NotificationKind.newOrder)));
      expect(staff, contains(NotificationKind.newOrder));
      expect(staff, isNot(contains(NotificationKind.orderReady)));
      expect(staff, contains(NotificationKind.announcement));
    });

    test('parses the database kinds, falling back to announcement', () {
      expect(
        NotificationKind.parse('order_ready'),
        NotificationKind.orderReady,
      );
      expect(NotificationKind.parse('new_order'), NotificationKind.newOrder);
      expect(
        NotificationKind.parse('something_else'),
        NotificationKind.announcement,
      );
    });

    test('a user notification row parses', () {
      final n = UserNotification.fromMap({
        'id': 'n1',
        'kind': 'order_ready',
        'title': 'Order K7P2QX is ready!',
        'body': 'Collect it at the Great Hall.',
        'order_id': 'o1',
        'created_at': '2026-09-23T10:00:00Z',
      });
      expect(n.kind, NotificationKind.orderReady);
      expect(n.isRead, isFalse);
      expect(n.orderId, 'o1');
    });
  });

  group('NotificationPrefs', () {
    test('everything is on by default', () {
      const prefs = NotificationPrefs();
      for (final kind in NotificationKind.values) {
        expect(prefs.allows(kind), isTrue);
      }
    });

    test('muting one kind leaves the others', () {
      final prefs = const NotificationPrefs().toggled(
        NotificationKind.orderPlaced,
        false,
      );
      expect(prefs.allows(NotificationKind.orderPlaced), isFalse);
      expect(prefs.allows(NotificationKind.orderReady), isTrue);
      expect(
        prefs
            .toggled(NotificationKind.orderPlaced, true)
            .allows(NotificationKind.orderPlaced),
        isTrue,
      );
    });

    test('the master switch silences every kind', () {
      final prefs = const NotificationPrefs().copyWith(enabled: false);
      expect(NotificationKind.values.any(prefs.allows), isFalse);
    });

    test('choices survive a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await const NotificationPrefs(
        enabled: true,
        soundAndVibration: false,
        muted: {NotificationKind.announcement},
        permissionAsked: true,
      ).save();

      final loaded = await NotificationPrefs.load();
      expect(loaded.soundAndVibration, isFalse);
      expect(loaded.muted, {NotificationKind.announcement});
      expect(loaded.permissionAsked, isTrue);
    });

    test('dismissed notices persist per account', () async {
      SharedPreferences.setMockInitialValues({});
      await NotificationPrefs.saveDismissal('student-1', 'personal:n1');
      await NotificationPrefs.saveDismissal('student-1', 'announcement:n2');
      await NotificationPrefs.saveDismissal('student-1', 'personal:n1');

      expect(await NotificationPrefs.dismissedIds('student-1'), {
        'personal:n1',
        'announcement:n2',
      });
      expect(await NotificationPrefs.dismissedIds('student-2'), isEmpty);
    });
  });
}
