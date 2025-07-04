/// Represents the information of an open-source license for a package.
class OssLicense {
  /// The name of the package.
  final String name;

  /// The version of the package.
  final String version;

  /// The full text content of the license.
  final String licenseText;

  /// A summarized type of the license (e.g., "MIT", "Apache-2.0").
  final String licenseSummary;

  /// The URL of the package's repository, if available.
  final String? repositoryUrl;

  /// The description of the package, if available.
  final String? description;

  /// Creates an [OssLicense] instance.
  const OssLicense({
    required this.name,
    required this.version,
    required this.licenseText,
    required this.licenseSummary,
    this.repositoryUrl,
    this.description,
  });
}
