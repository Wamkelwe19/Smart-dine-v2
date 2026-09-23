/// Formatting helpers.
///
/// `'R ${price.toStringAsFixed(2)}'` was hand-written at three call sites, each
/// reading a `double` straight from the database. Money is integer cents now
/// (migration 0002), so there is exactly one conversion point.
class Money {
  const Money._();

  /// REQ-2: South African rand, always two decimal places.
  static String format(int cents) {
    final negative = cents < 0;
    final abs = cents.abs();
    final rands = abs ~/ 100;
    final remainder = abs % 100;
    final grouped = _groupThousands(rands);
    return '${negative ? '-' : ''}R $grouped.${remainder.toString().padLeft(2, '0')}';
  }

  /// Accepts the legacy `price` double during the cents migration.
  static int centsFromRands(num rands) => (rands * 100).round();

  static String _groupThousands(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// Relative timestamps for order and notification lists.
class TimeAgo {
  const TimeAgo._();

  static String format(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')}/${time.year}';
  }

  /// Wall-clock time for the staff queue, where "how long has this been
  /// waiting" matters more than the date.
  static String clock(DateTime? time) {
    if (time == null) return '';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// A special's start or end: "Today 14:00", "Tomorrow 09:30", "Fri 26 Sep 14:00".
  static String dayClock(DateTime time, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final clock = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    final day = DateTime(time.year, time.month, time.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;

    if (day == 0) return 'Today $clock';
    if (day == 1) return 'Tomorrow $clock';
    return '${_weekdays[time.weekday - 1]} ${time.day} '
        '${_months[time.month - 1]} $clock';
  }
}

/// Field validation shared by the sign-up and profile-completion forms.
///
/// The sign-up form previously held a `_formKey` and called `validate()`, but
/// no field was ever given a validator, so it always returned true and empty
/// submissions went straight to the network (REQ-17, REQ-21, REQ-22).
class Validators {
  const Validators._();

  static String? required(String? value, String field) {
    if (value == null || value.trim().isEmpty) return 'Please enter your $field.';
    return null;
  }

  /// REQ-21: rejected before any network call.
  static String? email(String? value) {
    final missing = required(value, 'email address');
    if (missing != null) return missing;

    final pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
    if (!pattern.hasMatch(value!.trim())) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  /// REQ-22: minimum eight characters, stated at the point of failure.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Please enter a password.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? identifier(String? value, {required bool isStudent}) {
    final label = isStudent ? 'student number' : 'staff number';
    final missing = required(value, label);
    if (missing != null) return missing;

    final trimmed = value!.trim();
    if (trimmed.length < 4) return 'That $label looks too short.';
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(trimmed)) {
      return 'A $label may only contain letters, numbers and hyphens.';
    }
    return null;
  }

  static String? phone(String? value) {
    final missing = required(value, 'phone number');
    if (missing != null) return missing;

    final digits = value!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 15) {
      return 'Please enter a valid phone number.';
    }
    return null;
  }

  /// REQ-74: rejects a negative or non-numeric price at the form, matching the
  /// database constraint added in migration 0001.
  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter a price.';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Please enter a valid amount.';
    if (parsed < 0) return 'Price cannot be negative.';
    if (parsed > 100000) return 'That price looks too high.';
    return null;
  }

  static String? stock(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter a stock count.';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Please enter a whole number.';
    if (parsed < 0) return 'Stock cannot be negative.';
    return null;
  }

  /// A variety's name ("Sweet Chilli"): required, and short enough for a chip.
  static String? varietyName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name this variety.';
    if (value.trim().length > 40) return 'Keep it under 40 characters.';
    return null;
  }

  /// A variety's price difference: empty means the same price; otherwise a
  /// positive or negative amount in rand.
  static String? priceDelta(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter an amount, e.g. 5 or -2.50.';
    if (parsed.abs() > 10000) return 'That difference looks too large.';
    return null;
  }

  /// A percentage-off special, matching the 1-90 check in migration 0008.
  static String? percent(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter a percentage.';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Please enter a whole number.';
    if (parsed < 1 || parsed > 90) return 'Choose between 1% and 90% off.';
    return null;
  }

  /// A fixed special price must actually be a saving on [baseCents].
  static String? specialPrice(String? value, int baseCents) {
    final invalid = price(value);
    if (invalid != null) return invalid;
    final cents = Money.centsFromRands(double.parse(value!.trim()));
    if (cents >= baseCents) {
      return 'Must be below the usual ${Money.format(baseCents)}.';
    }
    return null;
  }
}
