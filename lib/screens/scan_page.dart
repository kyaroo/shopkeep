import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shared full-screen barcode scanner with a scan reticle, a steady hint, and
/// a torch toggle. Pops the raw barcode string.
///
/// Replaces the two duplicated bare `BarcodeScanPage` classes that had no
/// framing affordance — a framing overlay with a large perceived-quality
/// payoff that also helps cheap Android cameras lock on.
///
/// The controller is created ONCE in initState and disposed in dispose().
/// Creating it inside build() (a mistake that causes a black screen: every
/// rebuild — torch toggle, locale change — tears down and re-inits the camera
/// and it never stabilizes) is deliberately avoided.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('scanBarcode'.tr()),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
                tooltip: torchOn ? 'torchOff'.tr() : 'torchOn'.tr(),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null) Navigator.pop(context, code);
            },
          ),
          // Framing reticle + steady hint. IgnorePointer so taps pass
          // through to the camera preview (e.g. tap-to-focus).
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'scanHint'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54)
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
