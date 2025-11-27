import 'package:example/oss_licenses.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OSS Licenses Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LicenseListPage(),
    );
  }
}

class LicenseListPage extends StatelessWidget {
  const LicenseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Source Licenses'),
      ),
      body: ListView.builder(
        itemCount: ossLicenses.length,
        itemBuilder: (context, index) {
          final license = ossLicenses[index];
          return Card(
            margin: const EdgeInsets.all(8.0),
            child: ExpansionTile(
              title: Text('${license.name} v${license.version}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(license.licenseSummary),
                  if (license.description != null) Text(license.description!),
                  if (license.repositoryUrl != null)
                    InkWell(
                      onTap: () async {
                        final url = Uri.parse(license.repositoryUrl!);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        } else {
                          if (context.mounted) {
                            /// Handle error: could not launch URL
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Could not launch ${license.repositoryUrl}')),
                            );
                          }
                        }
                      },
                      child: Text(
                        license.repositoryUrl!,
                        style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: Colors.blue),
                      ),
                    ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(license.licenseText),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
