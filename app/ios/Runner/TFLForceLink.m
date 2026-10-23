// 流用元: agari_cam/ios/Runner/TFLForceLink.m（2025-09-03）。中身は変えていない（この 1 行目からのコメントだけ追記）。
#import <Foundation/Foundation.h>

// Ensure the TensorFlowLite C API symbols are linked into the final binary
// even in Release/TestFlight where dead-code stripping is aggressive.
// We reference a well-known C API symbol (TfLiteVersion) in a constructor
// so the linker cannot strip the object file that contains the C API.

// Avoid depending on specific pod headers; declare symbol manually.
extern const char *TfLiteVersion(void);

__attribute__((constructor)) static void TFLForceLinkCAPI(void) {
  const char *ver = TfLiteVersion();
  (void)ver; // prevent unused warning; forces reference to C API
}
