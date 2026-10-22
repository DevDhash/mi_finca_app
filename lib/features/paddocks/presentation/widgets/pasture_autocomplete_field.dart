import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mi_finca_app/features/paddocks/presentation/utils/pasture_search.dart';

/// A free-text form field. The caller owns [controller]; suggestions are optional.
class PastureAutocompleteField extends StatefulWidget {
  const PastureAutocompleteField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<PastureAutocompleteField> createState() =>
      _PastureAutocompleteFieldState();
}

class _PastureAutocompleteFieldState extends State<PastureAutocompleteField>
    with WidgetsBindingObserver {
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  ScrollPosition? _position;
  OptionsViewOpenDirection _direction = OptionsViewOpenDirection.up;
  double _availableHeight = 0;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_revealField);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_position != position) {
      _position?.removeListener(_scheduleGeometry);
      _position = position;
      _position?.addListener(_scheduleGeometry);
    }
    _scheduleGeometry();
  }

  @override
  void didChangeMetrics() => _revealField();

  void _revealField() {
    if (!_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = _fieldKey.currentContext;
      if (!mounted || !_focus.hasFocus || fieldContext == null) return;
      // Near the bottom of the visible viewport leaves room above the field,
      // including after the keyboard has resized the form.
      Scrollable.ensureVisible(fieldContext, alignment: 1);
      _scheduleGeometry();
    });
  }

  void _scheduleGeometry() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = _fieldKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final media = MediaQuery.of(context);
      final top = box.localToGlobal(Offset.zero).dy;
      var visibleTop = media.padding.top;
      var visibleBottom =
          media.size.height -
          math.max(media.viewInsets.bottom, media.padding.bottom);
      final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (viewport is RenderBox && viewport.hasSize) {
        final viewportTop = viewport.localToGlobal(Offset.zero).dy;
        visibleTop = math.max(visibleTop, viewportTop);
        visibleBottom = math.min(
          visibleBottom,
          viewportTop + viewport.size.height,
        );
      }
      final above = math.max(0.0, top - visibleTop - 4);
      final below = math.max(0.0, visibleBottom - top - box.size.height - 4);
      final direction = above >= below
          ? OptionsViewOpenDirection.up
          : OptionsViewOpenDirection.down;
      final height = math.min(240.0, math.max(above, below));
      if (_direction != direction || (_availableHeight - height).abs() > .5) {
        setState(() {
          _direction = direction;
          _availableHeight = height;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_scheduleGeometry);
    _focus.removeListener(_revealField);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsViewOpenDirection: _direction,
    optionsBuilder: (value) => searchPastureTypes(value.text),
    onSelected: (value) {
      // RawAutocomplete writes the controller programmatically; TextFormField's
      // onChanged is not called. Explicitly preserve the form's patch tracking.
      widget.onChanged(value);
      _focus.unfocus();
    },
    fieldViewBuilder: (context, controller, focus, onSubmitted) => TextFormField(
      key: _fieldKey,
      controller: controller,
      focusNode: focus,
      decoration: const InputDecoration(labelText: 'Tipo de pastura'),
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.done,
      // Do not call RawAutocomplete's submit callback: it implicitly accepts
      // the highlighted option, overwriting custom text.
      onFieldSubmitted: (_) => focus.unfocus(),
      onTapOutside: (_) => focus.unfocus(),
    ),
    optionsViewBuilder: (context, select, options) {
      final items = options.toList(growable: false);
      final field = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
      return Align(
        alignment: _direction == OptionsViewOpenDirection.up
            ? Alignment.bottomLeft
            : Alignment.topLeft,
        child: SizedBox(
          width: field?.size.width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _availableHeight),
            child: Material(
              key: const ValueKey('pasture-suggestions'),
              elevation: 4,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                itemExtent: 48,
                itemBuilder: (context, index) => InkWell(
                  onTap: () => select(items[index]),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          items[index],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
