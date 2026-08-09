import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import 'security/security_screen.dart';
import 'vault/vault_screen.dart';

/// Codes ⇄ Security tab shell. The bar floats over a paper-to-transparent
/// gradient. (The prototype's third "Replay" affordance is not shipped.)
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tab,
              children: const [VaultScreen(), SecurityScreen()],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .4],
                  colors: [Color(0x00F7F5F1), TkColors.paper],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                  26, 10, 26, 14 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  _TabButton(
                    label: 'Codes',
                    active: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 6),
                  _TabButton(
                    label: 'Security',
                    active: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: TkMotion.feedback,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? TkColors.ink : Colors.transparent,
            border: Border.all(
                color: active ? TkColors.ink : const Color.fromRGBO(27, 26, 23, .14),
                width: 1.5),
            borderRadius: BorderRadius.circular(TkRadius.row),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TkFonts.sans,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: active ? TkColors.paper : TkColors.ink50,
            ),
          ),
        ),
      ),
    );
  }
}
