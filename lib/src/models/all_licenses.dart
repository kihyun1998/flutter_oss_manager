import 'licenses/apache_license_info.dart';
import 'licenses/bsd_license_info.dart';
import 'licenses/gpl_license_info.dart';
import 'licenses/isc_license_info.dart';
import 'licenses/lgpl_license_info.dart';
import 'licenses/mit_license_info.dart';
import 'licenses/mpl_license_info.dart';
import 'template_license_info.dart';

/// A map containing all supported license information, keyed by their [licenseId].
///
/// The licenses are sorted by their [priority] (lower number indicates higher priority).
final Map<String, TemplateLicenseInfo> allLicenses = () {
  final licenses = <TemplateLicenseInfo>[
    ApacheLicenseInfo(),
    MITLicenseInfo(),
    ISCLicenseInfo(),
    BSD4ClauseLicenseInfo(),
    BSD3ClauseLicenseInfo(),
    BSD2ClauseLicenseInfo(),
    GPLV3LicenseInfo(),
    GPLV2LicenseInfo(),
    LGPLV3LicenseInfo(),
    LGPLV2LicenseInfo(),
    MPLLicenseInfo(),
  ];

  // Sort by priority (lower number first)
  licenses.sort((a, b) => a.priority.compareTo(b.priority));

  // Convert to Map
  return Map.fromEntries(
      licenses.map((license) => MapEntry(license.licenseId, license)));
}();

/// Returns a list of all supported license templates, sorted by their priority.
///
/// This list is used for heuristic matching, ensuring that higher-priority
/// licenses are checked first.
List<TemplateLicenseInfo> getLicensesByPriority() {
  final licenses = allLicenses.values.toList();
  licenses.sort((a, b) => a.priority.compareTo(b.priority));
  return licenses;
}
