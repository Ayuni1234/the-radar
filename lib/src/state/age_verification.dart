/// Age verification and minor location privacy.
///
/// Pure functions only, so they can be unit-tested without Supabase or GPS.
/// Minor status is derived from a verified birth year at signup rather than
/// a self-declared switch.
library;

/// Age at which a player is no longer treated as a minor.
const int kAdultAge = 18;

/// Coordinates for minors are rounded to this many decimal places
/// (0.1° ≈ 11 km), so a minor's position is only ever known to an
/// approximate radius of roughly 5–6 km.
const int kMinorCoordinateDecimals = 1;

/// Earliest birth year accepted at signup. Anything older is rejected as
/// an invalid entry.
const int kEarliestBirthYear = 1900;

/// Result of checking a birth year against the current date.
enum AgeCheck { valid, missing, invalid, future }

/// Classifies a birth-year entry. A null or blank entry is [AgeCheck.missing].
AgeCheck checkBirthYear(int? birthYear, {DateTime? now}) {
  if (birthYear == null) return AgeCheck.missing;
  final year = (now ?? DateTime.now()).year;
  if (birthYear < kEarliestBirthYear) return AgeCheck.invalid;
  if (birthYear > year) return AgeCheck.future;
  return AgeCheck.valid;
}

/// Approximate age in whole years from a birth year, or null when the
/// birth year is not valid.
///
/// Uses the year difference, which is the same approximation the profile
/// model uses, so an age-18 boundary may be off by one for birthdays later
/// in the year. Signup asks only for the birth year, so that is the
/// accuracy the app has.
int? ageFromBirthYear(int? birthYear, {DateTime? now}) {
  if (checkBirthYear(birthYear, now: now) != AgeCheck.valid) return null;
  return (now ?? DateTime.now()).year - birthYear!;
}

/// True when the birth year gives an age below [kAdultAge].
///
/// Returns false when the birth year is missing or invalid. Callers must
/// require a valid birth year before finishing signup, so a missing value
/// never silently marks someone as an adult.
bool isMinorFromBirthYear(int? birthYear, {DateTime? now}) {
  final age = ageFromBirthYear(birthYear, now: now);
  return age != null && age < kAdultAge;
}

/// Generalizes a coordinate for a minor so that the exact position is
/// never stored or shown.
///
/// Rounds to [kMinorCoordinateDecimals] decimal places. Adults get the
/// unchanged value back.
({double lat, double lon}) generalizeForMinor(
  double lat,
  double lon, {
  required bool isMinor,
}) {
  if (!isMinor) return (lat: lat, lon: lon);
  double round(double v) {
    final factor = _pow10(kMinorCoordinateDecimals);
    return (v * factor).roundToDouble() / factor;
  }

  return (lat: round(lat), lon: round(lon));
}

double _pow10(int n) {
  var result = 1.0;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}
