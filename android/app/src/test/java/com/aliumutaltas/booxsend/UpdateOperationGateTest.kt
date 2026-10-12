package com.aliumutaltas.booxsend

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class UpdateOperationGateTest {
    @Test fun concurrentScreensCanStartOnlyOneOperation() {
        val gate = UpdateOperationGate()
        val start = CountDownLatch(1)
        val finished = CountDownLatch(16)
        val accepted = AtomicInteger()
        repeat(16) {
            thread {
                start.await()
                if (gate.tryStart()) accepted.incrementAndGet()
                finished.countDown()
            }
        }
        start.countDown()
        assertTrue(finished.await(5, TimeUnit.SECONDS))
        assertEquals(1, accepted.get())
        assertTrue(gate.isBusy)
        gate.finish()
        assertTrue(gate.tryStart())
    }

    @Test fun successfulChecksAreDailyButFailuresCanRetryOnLaterOpen() {
        val now = 200_000_000L
        assertFalse(UpdatePolicy.shouldAutomaticallyCheck(now, now - 1000, now - 1000))
        assertFalse(UpdatePolicy.shouldAutomaticallyCheck(now, 0, now - 1000))
        assertTrue(UpdatePolicy.shouldAutomaticallyCheck(now, 0, now - 900_000))
        assertTrue(UpdatePolicy.shouldAutomaticallyCheck(now, now - 86_400_000, now - 900_000))
        assertTrue(UpdatePolicy.shouldAutomaticallyCheck(now, 0, 0))
    }
}
