# Changelog

All notable changes to **kube-tz** will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-28

### Added
- Initial public release of kube-tz.
- Kubernetes-native timezone management using `MutatingAdmissionPolicy` and `MutatingAdmissionPolicyBinding`.
- CEL-based admission policy logic for resolving and validating timezone configuration.
- Support for selecting a timezone through Pod annotations, with a chart-configured default.
- Conditional Pod mutation based on policy bindings, namespace selection, and supported workloads.
- Automatic injection of a `kube-tz` init container into eligible Pods.
- Shared `emptyDir` volume for providing timezone database files to application containers.
- Timezone configuration for application containers through the `TZ` environment variable.
- Timezone database preparation for `/usr/share/zoneinfo` and `/etc/localtime`.
- Helm chart for deploying and configuring kube-tz.
- Container image published to Quay.io.
- Architecture and sequence diagrams documenting the admission and Pod startup flow.

### Documentation
- Added project architecture documentation.
- Added Pod admission and startup sequence documentation.
- Added initial release documentation and installation guidance.

### Notes
- This is the first public release. APIs, configuration options, and deployment conventions may change in future releases.
- The Kubernetes cluster must support the admission policy APIs and CEL functionality required by kube-tz.
- Review the Helm chart configuration and cluster prerequisites before deployment.

[0.1.0]: https://github.com/kube-tz/kube-tz/releases/tag/v0.1.0