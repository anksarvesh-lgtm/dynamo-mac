// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad

import android.view.MotionEvent

class MotionEventHandler(
    val classifier: GestureClassifier
) {
    fun handleMotionEvent(event: MotionEvent): Boolean {
        val action = event.actionMasked
        val actionIndex = event.actionIndex
        val timeMs = event.eventTime

        when (action) {
            MotionEvent.ACTION_DOWN -> {
                val ptrId = event.getPointerId(0)
                classifier.onPointerDown(ptrId, event.getX(0), event.getY(0), timeMs)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                val ptrId = event.getPointerId(actionIndex)
                classifier.onPointerDown(ptrId, event.getX(actionIndex), event.getY(actionIndex), timeMs)
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    val ptrId = event.getPointerId(i)
                    classifier.onPointerMove(ptrId, event.getX(i), event.getY(i), timeMs)
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                val ptrId = event.getPointerId(actionIndex)
                classifier.onPointerUp(ptrId, event.getX(actionIndex), event.getY(actionIndex), timeMs)
            }
            MotionEvent.ACTION_UP -> {
                val ptrId = event.getPointerId(0)
                classifier.onPointerUp(ptrId, event.getX(0), event.getY(0), timeMs)
            }
            MotionEvent.ACTION_CANCEL -> {
                classifier.onCancel()
            }
        }
        return true
    }
}

