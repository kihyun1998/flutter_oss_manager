import 'licenses/apache_license_info.dart';
import 'licenses/bsd_license_info.dart';
import 'licenses/isc_license_info.dart';
import 'licenses/mit_license_info.dart';
import 'template_license_info.dart';

/// 지원하는 모든 라이선스 정보를 담고 있는 Map
/// 우선순위 순으로 정렬되어 있음 (낮은 숫자가 높은 우선순위)
final Map<String, TemplateLicenseInfo> allLicenses = () {
  final licenses = <TemplateLicenseInfo>[
    MitLicenseInfo(),
    ApacheLicenseInfo(),
    IscLicenseInfo(),
    Bsd3ClauseLicenseInfo(),
    Bsd2ClauseLicenseInfo(),
  ];

  // 우선순위로 정렬 (낮은 숫자가 먼저)
  licenses.sort((a, b) => a.priority.compareTo(b.priority));

  // Map으로 변환
  return Map.fromEntries(
      licenses.map((license) => MapEntry(license.licenseId, license)));
}();

/// 휴리스틱 매칭을 위해 우선순위 순으로 라이선스를 반환
List<TemplateLicenseInfo> getLicensesByPriority() {
  final licenses = allLicenses.values.toList();
  licenses.sort((a, b) => a.priority.compareTo(b.priority));
  return licenses;
}
