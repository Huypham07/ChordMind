// app/lib/core/breakpoints.dart
enum FormFactor { compact, medium, expanded }

FormFactor formFactorFor(double width) {
  if (width < 600) return FormFactor.compact;
  if (width < 1024) return FormFactor.medium;
  return FormFactor.expanded;
}
