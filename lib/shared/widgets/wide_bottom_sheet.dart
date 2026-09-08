import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screens wider than this are treated as "wide" for modal bottom sheets:
/// the sheet is capped at [kWideBottomSheetFraction] of the app width
/// instead of the framework's 640 px default (which leaves it looking small
/// in the middle of a big window). Phones and other narrow windows keep the
/// default full-width sheet.
const double kWideBottomSheetMinScreenWidth = 640;

/// Fraction of the app width a wide-screen bottom sheet may span.
const double kWideBottomSheetFraction = 0.8;

/// [showModalBottomSheet] `constraints` for sheets that should be wider than
/// Material's 640 px default cap on large screens while leaving phones
/// (which are narrower than that cap anyway) at full width.
///
/// Returns null on narrow windows so the framework default stays in effect;
/// on wide screens it caps the sheet at [kWideBottomSheetFraction] of the
/// app width — never narrower than the 640 px default cap, so mid-size
/// windows look unchanged.
BoxConstraints? wideBottomSheetConstraints(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width <= kWideBottomSheetMinScreenWidth) return null;
  return BoxConstraints(
    maxWidth: math.max(
      kWideBottomSheetMinScreenWidth,
      width * kWideBottomSheetFraction,
    ),
  );
}
