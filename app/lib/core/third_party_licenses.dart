import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// あがりかむから流用したコードの著作権表示を配布アプリにも保持する。
/// このMIT表記は、別ライセンスの学習データ・モデル・画像へ適用しない。
void registerThirdPartyLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks([
      'AgariCam (reused application code)',
    ], agariCamMitLicense);
    final agpl = await rootBundle.loadString(
      'assets/licenses/ultralytics-AGPL-3.0.txt',
    );
    yield LicenseEntryWithLineBreaks(
      const ['Nanikiru Cam', 'Ultralytics YOLO11 (tile recognition models)'],
      '''Nanikiru Cam: Copyright (c) 2026 aile.
Licensed under the GNU Affero General Public License v3.0.
Corresponding source: https://github.com/nomuyu00/nanikirucam-source
Third-party copyright notices and licenses remain applicable.

$agpl''',
    );
  });
}

const agariCamMitLicense = '''
MIT License

Copyright (c) 2025 AgariCam Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';
