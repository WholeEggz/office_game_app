import 'dart:async';

import 'package:flutter/material.dart';

/// A text field that suggests already-registered values as the user
/// types, backed by an async [suggest] lookup (e.g. a Firestore
/// prefix-range query) rather than a fixed, synchronous option list.
/// Renders its own inline suggestion list below the field (not an
/// overlay) — simpler to reason about than `Autocomplete`'s
/// synchronous-only `optionsBuilder`, and avoids depending on its
/// internal re-fetch-on-rebuild timing. Debounced so a fast typist
/// doesn't fire a lookup per keystroke. Suggestions are always just a
/// convenience: whatever's typed is accepted as-is, matched or not.
class AutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final Future<List<String>> Function(String prefix) suggest;

  const AutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggest,
  });

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  static const _debounce = Duration(milliseconds: 300);

  List<String> _options = const [];
  Timer? _debounceTimer;
  final _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _debounceTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    final query = widget.controller.text;
    _debounceTimer = Timer(_debounce, () async {
      List<String> results;
      try {
        results = await widget.suggest(query);
      } catch (e) {
        // Suggestions are a pure convenience — a failed lookup (e.g. a
        // transient network blip) should never block typing or surface
        // an error to the player, just leave the list empty. Logged
        // rather than swallowed outright so a real, persistent failure
        // (the wrong Firestore rules, a missing session, ...) is at
        // least visible in the console instead of just "no suggestions,
        // no idea why."
        debugPrint('AutocompleteField(${widget.label}): suggest failed: $e');
        return;
      }
      // The controller may have moved on to different text while this
      // lookup was in flight — a stale result showing up now would look
      // like a wrong or flickering suggestion list.
      if (!mounted || widget.controller.text != query) return;
      setState(() => _options = results);
    });
  }

  void _select(String option) {
    widget.controller.text = option;
    setState(() => _options = const []);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final showOptions = _hasFocus && _options.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(labelText: widget.label),
        ),
        if (showOptions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in _options)
                  ListTile(dense: true, title: Text(option), onTap: () => _select(option)),
              ],
            ),
          ),
      ],
    );
  }
}
