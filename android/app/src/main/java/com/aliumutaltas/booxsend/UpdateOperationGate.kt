package com.aliumutaltas.booxsend

import java.util.concurrent.atomic.AtomicBoolean

/** Shared by all setup screens so rotation cannot start competing downloads. */
class UpdateOperationGate {
    private val active = AtomicBoolean(false)
    val isBusy get() = active.get()
    fun tryStart(): Boolean = active.compareAndSet(false, true)
    fun finish() { active.set(false) }
}
