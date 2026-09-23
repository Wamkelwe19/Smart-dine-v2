import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

/// One place that turns any thrown object into something a student should read.
///
/// The old screens had 27 `ScaffoldMessenger` call sites with no shared helper.
/// Nine of them interpolated the raw exception into the message
/// (`'Error updating stock: $e'`), which once RLS is enabled would print
/// Postgres policy-violation text straight onto a student's phone. Several
/// others used the default grey snackbar for failures, so `'Save failed'` looked
/// identical to `'Item successfully saved!'`.
class AppError implements Exception {
  const AppError(this.message, {this.isRecoverable = true, this.debugDetail});

  /// Shown to the user. Plain language, no exception text (REQ-14).
  final String message;

  /// Whether retrying the same action could reasonably succeed.
  final bool isRecoverable;

  /// Kept for the log, never shown.
  final String? debugDetail;

  @override
  String toString() => 'AppError($message)${debugDetail == null ? '' : ': $debugDetail'}';

  /// Maps the error codes raised by the database functions in migration 0004
  /// and 0005 onto human sentences.
  static AppError from(Object error) {
    final mapped = _map(error);
    // REQ-115: detail only in debug builds (see showAppError).
    if (kDebugMode && error is! AppError) {
      debugPrint('AppError.from(${error.runtimeType}): ${mapped.debugDetail}');
    }
    return mapped;
  }

  static AppError _map(Object error) {
    if (error is AppError) return error;

    if (error is FunctionException) return _fromFunction(error);

    if (error is PostgrestException) {
      final mapped = _postgrestMessages[_codeOf(error.message)];
      if (mapped != null) {
        return AppError(mapped, debugDetail: error.message);
      }
      // A function, table or column the app needs is missing: the database is
      // behind the app, which no amount of retrying will fix.
      if (_schemaCodes.contains(error.code)) {
        return AppError(
          'The app needs a database update before this works. Please ask the '
          'administrator to run the latest migrations.',
          isRecoverable: false,
          debugDetail: '${error.code}: ${error.message}',
        );
      }
      // A policy violation means the UI offered something the user may not do.
      if (error.code == '42501' ||
          error.message.toLowerCase().contains('row-level security')) {
        return AppError(
          'You do not have permission to do that.',
          isRecoverable: false,
          debugDetail: error.message,
        );
      }
      return AppError(
        'Something went wrong on our side. Please try again.',
        debugDetail: error.message,
      );
    }

    if (error is AuthException) {
      return AppError(_authMessage(error), debugDetail: error.message);
    }

    if (error is StorageException) {
      return AppError(
        'That image could not be uploaded. Please try again.',
        debugDetail: error.message,
      );
    }

    // Errors raised in Dart with a known code, e.g. StateError('CART_SPANS_CAFETERIAS').
    final coded = _postgrestMessages[_codeOf(error.toString())];
    if (coded != null) return AppError(coded, debugDetail: error.toString());

    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup') ||
        text.contains('connection')) {
      // REQ-14: plain language, and the caller's UI stays retryable.
      return AppError(
        'No internet connection. Check your network and try again.',
        debugDetail: error.toString(),
      );
    }

    return AppError(
      'Something went wrong. Please try again.',
      debugDetail: error.toString(),
    );
  }

  /// PostgREST / Postgres codes for "the schema is not what the app expects":
  /// function not found, relationship not found, column not found, undefined
  /// function / table / column.
  static const Set<String> _schemaCodes = {
    'PGRST202', 'PGRST200', 'PGRST204', '42883', '42P01', '42703',
  };

  /// Edge Function failures (the Paystack functions). The body carries an
  /// `error` code; the status says what kind of failure it was.
  static AppError _fromFunction(FunctionException error) {
    final details = error.details;
    final code = details is Map ? details['error']?.toString() : null;
    final detail = 'FunctionException(${error.status}, $code, ${error.details})';

    final message = switch (code) {
      'PAYSTACK_NOT_CONFIGURED' =>
        'Card payment isn\'t available yet. Please pay with cash at the counter.',
      'PAYSTACK_INIT_FAILED' =>
        'Paystack could not start the payment. Please try again, or pay with cash.',
      'ALREADY_PAID' => 'This order has already been paid.',
      'ORDER_CANCELLED' => 'This order was cancelled, so there is nothing to pay.',
      'NOTHING_TO_PAY' => 'This order has nothing to pay.',
      'ORDER_NOT_FOUND' || 'UNKNOWN_REFERENCE' =>
        'That order or payment could not be found.',
      'NOT_YOUR_ORDER' || 'NOT_YOUR_PAYMENT' =>
        'You do not have permission to do that.',
      'EMAIL_REQUIRED' =>
        'Your account needs an email address before you can pay by card.',
      'AUTH_REQUIRED' => 'Please sign in again.',
      _ => switch (error.status) {
          // Not deployed: the service simply is not there yet.
          404 =>
            'Card payment isn\'t available yet. Please pay with cash at the counter.',
          401 || 403 => 'Please sign in again.',
          _ =>
            'The payment service is unavailable right now. Please try again, '
                'or pay with cash.',
        },
    };
    return AppError(message, debugDetail: detail);
  }

  /// The RPCs raise bare uppercase tokens; PostgREST wraps them in prose.
  static String _codeOf(String raw) {
    final match = RegExp(r'\b([A-Z][A-Z_]{3,})\b').firstMatch(raw);
    return match?.group(1) ?? '';
  }

  static String _authMessage(AuthException error) {
    final text = error.message.toLowerCase();
    if (text.contains('invalid login') || text.contains('invalid credentials')) {
      // REQ-30: identical wording whether or not the number is registered.
      return 'Incorrect student/staff number or password.';
    }
    if (text.contains('email not confirmed')) {
      return 'Please verify your email address first. Check your inbox for the link.';
    }
    if (text.contains('already registered') || text.contains('already exists')) {
      return 'An account with that email address already exists.';
    }
    if (text.contains('rate limit') || text.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (text.contains('weak password') || text.contains('at least')) {
      return 'That password is too weak. Use at least 8 characters.';
    }
    return 'Sign-in failed. Please try again.';
  }

  static const Map<String, String> _postgrestMessages = {
    'AUTH_REQUIRED': 'Please sign in again.',
    'INVALID_QUANTITY': 'That quantity is not valid.',
    'ITEM_NOT_FOUND': 'That item is no longer on the menu.',
    'CAFETERIA_CLOSED':
        'That cafeteria has just closed and is not taking orders.',
    'CAFETERIA_NOT_FOUND': 'That cafeteria is no longer available.',
    'INSUFFICIENT_STOCK': 'Sorry, that item just sold out.',
    'NO_RESERVATION': 'That item is no longer in your cart.',
    'SELECTION_REQUIRED': 'Please choose an option before adding this item.',
    'INVALID_SELECTION': 'That option is not available for this item.',
    'COMBO_EMPTY': 'This combo has no items in it yet.',
    'INVALID_COMBO_COMPONENT':
        'A combo can only include non-combo items from the same cafeteria.',
    'MENU_ITEM_NOT_FOUND': 'That item is no longer on the menu.',
    'CART_EMPTY': 'Your cart is empty.',
    'CART_SPANS_CAFETERIAS':
        'Your cart has items from more than one cafeteria. Please order from one at a time.',
    'ILLEGAL_TRANSITION': 'That order cannot be moved to that stage.',
    'ORDER_NOT_FOUND': 'That order could not be found.',
    'NOT_AUTHORISED': 'You do not have permission to do that.',
    'NOT_AUTHORISED_FOR_CAFETERIA':
        'You are not assigned to that cafeteria. Ask an administrator for access.',
    'IDENTIFIER_ALREADY_REGISTERED':
        'That student/staff number is already registered.',
    'PROFILE_ALREADY_COMPLETE': 'Your profile has already been set up.',
    'INVALID_IDENTIFIER': 'Please enter a valid student or staff number.',
    'INVALID_ROLE': 'Please choose either student or staff.',
    'ROLE_IS_IMMUTABLE': 'Your role cannot be changed from the app.',
    'IDENTIFIER_IS_IMMUTABLE':
        'Your student/staff number cannot be changed from the app.',
    'COLLECTION_REF_COLLISION':
        'Could not create your order just now. Please try again.',
  };
}

/// Feedback helpers. Colour is never the only signal — each carries an icon and
/// its own wording (REQ-4).
extension AppMessenger on BuildContext {
  void showAppError(Object error) {
    final appError = AppError.from(error);
    // REQ-115: diagnostic detail stays out of release builds. A Postgres error
    // can carry a row's contents — an email address in a unique-violation
    // message, for instance — and that must not reach the device log.
    if (kDebugMode) {
      debugPrint('AppError: ${appError.debugDetail ?? appError.message}');
    }
    _show(
      appError.message,
      icon: Icons.error_outline,
      background: AppColors.danger,
    );
  }

  void showAppSuccess(String message) => _show(
        message,
        icon: Icons.check_circle_outline,
        background: AppColors.success,
      );

  void showAppInfo(String message) =>
      _show(message, icon: Icons.info_outline, background: AppColors.secondary);

  void _show(String message, {required IconData icon, required Color background}) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: background,
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
