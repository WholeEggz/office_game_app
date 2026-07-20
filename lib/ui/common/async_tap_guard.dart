import 'package:flutter/material.dart';

/// Disables the button [builder] renders for the duration of [onTap] —
/// without this, a network round-trip slow enough to notice (Firebase
/// Cloud Functions latency in particular, versus the near-instant Local
/// backend) leaves a window where an impatient extra tap or two fires the
/// same action again before anything visibly changed: a second
/// `Navigator.push` stacking another case dashboard on the back stack, a
/// second passphrase dialog, a wasted duplicate vote. [builder] gets
/// `null` for `onPressed` while busy (any button type disables itself the
/// normal way) and `busy` in case it wants to swap in a spinner.
class AsyncTapGuard extends StatefulWidget {
  final Future<void> Function() onTap;
  final Widget Function(BuildContext context, VoidCallback? onPressed, bool busy) builder;

  const AsyncTapGuard({super.key, required this.onTap, required this.builder});

  @override
  State<AsyncTapGuard> createState() => _AsyncTapGuardState();
}

class _AsyncTapGuardState extends State<AsyncTapGuard> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _busy ? null : _run, _busy);
  }
}

/// A small inline spinner sized to sit where a button's label normally
/// goes, for [AsyncTapGuard.builder] implementations that want one.
const asyncTapGuardSpinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);
