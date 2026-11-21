package io.github.al3x1n0.keepassmobile

import android.os.Build
import android.view.MotionEvent
import android.view.Window

internal fun Window.hideUntrustedOverlays() {
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setHideOverlayWindows(true)
}

internal fun MotionEvent.isObscured(): Boolean =
  flags and (MotionEvent.FLAG_WINDOW_IS_OBSCURED or
    MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0
