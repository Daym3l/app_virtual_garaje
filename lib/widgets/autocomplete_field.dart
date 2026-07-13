import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/suggestions_service.dart';

/// Campo de texto con sugerencias de valores ya usados por el usuario
/// (RPC get_field_suggestions). Mismo estilo que los _FormField de los forms.
class AutocompleteField extends StatefulWidget {
  const AutocompleteField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.kind,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String kind;

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    SuggestionsService.get(widget.kind).then((values) {
      if (mounted) setState(() => _suggestions = values);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        RawAutocomplete<String>(
          textEditingController: widget.controller,
          focusNode: _focusNode,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (_suggestions.isEmpty) return const Iterable<String>.empty();
            if (q.isEmpty) return _suggestions.take(6);
            return _suggestions
                .where((s) => s.toLowerCase().contains(q) && s.toLowerCase() != q)
                .take(6);
          },
          onSelected: (_) {},
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onFieldSubmitted(),
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent)),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 180, maxWidth: 320),
                  decoration: BoxDecoration(
                    color: AppColors.cardHover,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final option = options.elementAt(i);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.history, size: 14, color: AppColors.textTertiary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option,
                                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
