import 'guide_validate/guide_validate.dart' as guide_validate;

/// Guide-repo entry: `dart run tool/guide_validate.dart .`
/// (pack root defaults to `assets/guide` when no argument is given, matching
/// the client repo layout).
void main(List<String> args) => guide_validate.main(args);
