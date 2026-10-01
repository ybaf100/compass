"""Print Kakao's Base64(SHA1(DER signing certificate)) for an APK/keystore.

Examples:
  python3 tool/print_android_kakao_key_hash.py --apk build/app/outputs/flutter-apk/app-debug.apk
  python3 tool/print_android_kakao_key_hash.py --keystore /secure/release.jks --alias release
"""

import argparse
import base64
import hashlib
from pathlib import Path
import re
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apk', type=Path)
    group.add_argument('--keystore', type=Path)
    parser.add_argument('--alias', help='Required with --keystore')
    args = parser.parse_args()
    if args.apk:
        output = subprocess.check_output(
            ['apksigner', 'verify', '--print-certs', str(args.apk)], text=True)
        digests = re.findall(r'certificate SHA-1 digest:\s*([0-9a-fA-F:]+)', output)
        if not digests:
            parser.error('apksigner did not report a signing certificate')
        for digest in digests:
            print(base64.b64encode(bytes.fromhex(digest.replace(':', ''))).decode())
    else:
        if not args.alias:
            parser.error('--alias is required with --keystore')
        certificate = subprocess.check_output(
            ['keytool', '-exportcert', '-keystore', str(args.keystore),
             '-alias', args.alias])
        print(base64.b64encode(hashlib.sha1(certificate).digest()).decode())


if __name__ == '__main__':
    main()
