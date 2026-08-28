# BOOX Go 10.3 hardware acceptance test

Run these checks before treating background delivery as reliable. BOOX firmware
power management is outside the Android compatibility contract and cannot be
validated in an emulator.

## First setup

1. Pair Mac and BOOX in the system Bluetooth settings.
2. Complete BOOX Send setup and companion association.
3. Disable Freeze for BOOX Send and enable App Startup.
4. Leave **Stay active in the background** off for the first test.
5. Disable BOOX auto-shutdown; normal sleep is allowed.

## Presence and wake tests

1. Force-stop neither app. Swipe BOOX Send away and let the BOOX sleep for ten
   minutes.
2. Right-click a 1 KiB text file on the Mac and choose **Hızlı İşlemler >
   BOOX’a Gönder**.
3. Confirm that the file is delivered without opening the BOOX app. Automatic
   boot mode can run without a persistent foreground notification.
4. Repeat after one hour of BOOX sleep.
5. If the companion callback is suppressed, enable BOOX's **Stay active in the
   background** setting and repeat. Do not add polling or a periodic worker.

## Transfer tests

- Send empty, 1 KiB, 1 MiB, and 20 MiB files.
- Send multiple files with the same basename and verify `(1)`, `(2)` naming.
- Disable Bluetooth halfway through a 20 MiB transfer, enable it again, then use
  **Yeniden Dene** on the Mac. Verify that the partial transfer resumes.
- Disconnect immediately after BOOX commits the file but before Mac receives
  the result; retry and verify no duplicate is created.
- Fill BOOX storage and verify the Mac retains the failed queue item.
- Test Turkish and composed/decomposed Unicode filenames.

## Idle power check

With the Mac absent, use Android developer tools or BOOX battery statistics to
confirm that BOOX Send has no scheduled job, alarm, periodic wake-up, or
Bluetooth scan, running receiver service, or open RFCOMM socket. During a send
attempt, a temporary receiver is expected to stop immediately after success or
after a two-minute idle window. Bluetooth being enabled has its own baseline
cost.
