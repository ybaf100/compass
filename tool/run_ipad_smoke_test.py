"""Run the iPad plugin smoke test with bounded simulator-launch recovery.

Flutter's simulator VM-service discovery can hang after a successful build.
Retry a timed-out launch once, never retry an assertion/plugin test failure.
"""

import json
import os
import signal
import subprocess
import sys
import threading

ATTEMPT_TIMEOUT_SECONDS = 720
MAX_ATTEMPTS = 2


def run_attempt(device):
    command = ['flutter', 'test', 'integration_test/plugin_registration_test.dart',
               '-d', device, '--verbose']
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True,
                               start_new_session=True, bufsize=1)
    test_started = threading.Event()

    def relay():
        for line in process.stdout:
            # No dart-defines or service credentials are passed to this test.
            print(line, end='', flush=True)
            if 'UIScene engine registers plugins and custom native bridges' in line:
                test_started.set()

    output = threading.Thread(target=relay, daemon=True)
    output.start()
    try:
        code = process.wait(timeout=ATTEMPT_TIMEOUT_SECONDS)
        output.join(timeout=5)
        return code, False
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
        output.join(timeout=5)
        print('::error::iPad smoke timeout: ' +
              ('test started but did not complete' if test_started.is_set()
               else 'test did not start; simulator/VM-service launch stalled'), flush=True)
        return 124, not test_started.is_set()


def main():
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    ipads = [device for group in devices['devices'].values() for device in group
             if 'iPad' in device['name']]
    if not ipads:
        raise SystemExit('No available iPad simulator')
    device = ipads[0]['udid']
    for attempt in range(MAX_ATTEMPTS):
        print(f'iPad smoke launch attempt {attempt + 1}/{MAX_ATTEMPTS}', flush=True)
        # Only this job's selected simulator is stopped; no device data is erased.
        if attempt:
            subprocess.run(['xcrun', 'simctl', 'shutdown', device],
                           check=True, timeout=60)
        if attempt or ipads[0]['state'] != 'Booted':
            subprocess.run(['xcrun', 'simctl', 'boot', device], check=True, timeout=60)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'],
                       check=True, timeout=240)
        code, recoverable_launch_timeout = run_attempt(device)
        if code == 0:
            return 0
        if not recoverable_launch_timeout:
            return code
    return 124


if __name__ == '__main__':
    sys.exit(main())
