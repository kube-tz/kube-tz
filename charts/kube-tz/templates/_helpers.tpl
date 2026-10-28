{{/* Chart name. */}}
{{- define "kube-tz.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified name. */}}
{{- define "kube-tz.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart name and version, used by the helm.sh/chart label. */}}
{{- define "kube-tz.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Default MutatingAdmissionPolicy name (cluster-scoped). */}}
{{- define "kube-tz.policyName" -}}
{{- include "kube-tz.fullname" . -}}
{{- end -}}

{{/* Default MutatingAdmissionPolicyBinding name (cluster-scoped). */}}
{{- define "kube-tz.bindingName" -}}
{{- printf "%s-binding" (include "kube-tz.fullname" . | trunc 54 | trimSuffix "-") -}}
{{- end -}}

{{/* Common labels. */}}
{{- define "kube-tz.labels" -}}
helm.sh/chart: {{ include "kube-tz.chart" . | quote }}
app.kubernetes.io/name: {{ include "kube-tz.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
CEL: the kube-tz init container (a Pod initContainer object constructor).
Expects a dict context built in policy.yaml.
*/}}
{{- define "kube-tz.cel.initContainer" -}}
Object.spec.initContainers{
  name: {{ .initName | quote }},
  image: {{ .imageRef | quote }},
  imagePullPolicy: {{ .imagePullPolicy | quote }},
  command: {{ .initCommand | toJson }},
  env: [
    Object.spec.initContainers.env{name: "TIMEZONE", value: variables.timezone},
    Object.spec.initContainers.env{name: "TZ", value: variables.timezone},
    Object.spec.initContainers.env{name: "ZONEINFO_SRC", value: {{ .zoneInfoSrc | quote }}}
  ],
  volumeMounts: [
    {{- if .hostPathEnabled }}
    Object.spec.initContainers.volumeMounts{name: {{ .hostPathVolumeName | quote }}, mountPath: {{ .hostPathMount | quote }}, readOnly: true},
    {{- end }}
    Object.spec.initContainers.volumeMounts{name: {{ .volumeName | quote }}, mountPath: "/work"}
  ],
  resources: Object.spec.initContainers.resources{
    requests: {"cpu": {{ .cpuRequest | quote }}, "memory": {{ .memoryRequest | quote }}},
    limits: {"cpu": {{ .cpuLimit | quote }}, "memory": {{ .memoryLimit | quote }}}
  },
  securityContext: Object.spec.initContainers.securityContext{
    allowPrivilegeEscalation: {{ .scAllowPrivEsc }},
    readOnlyRootFilesystem: {{ .scReadOnlyRoot }},
    runAsNonRoot: {{ .scRunAsNonRoot }},
    runAsUser: {{ .scRunAsUser | int64 }},
    runAsGroup: {{ .scRunAsGroup | int64 }},
    capabilities: Object.spec.initContainers.securityContext.capabilities{drop: {{ .scCapDrop | toJson }}},
    seccompProfile: Object.spec.initContainers.securityContext.seccompProfile{type: {{ .scSeccomp | quote }}}
  }
}
{{- end -}}

{{/*
CEL: map over containers or initContainers and add TZ + the zoneinfo/localtime mounts.
Only NEW entries are emitted; the result is merged by the API server (server-side apply),
so existing env vars / mounts are never rewritten and the expression is idempotent.
Context keys: field (containers|initContainers), excludeName (skip this container name, may be ""),
volumeName, zoneInfoMountPath, localtimeMountPath.
*/}}
{{- define "kube-tz.cel.mapContainers" -}}
object.spec.?{{ .field }}.orValue([])
{{- if .excludeName }}
.filter(c, c.name != {{ .excludeName | quote }})
{{- end }}
.map(c, Object.spec.{{ .field }}{
  name: c.name,
  env: c.?env.orValue([]).exists(e, e.name == "TZ")
    ? []
    : [Object.spec.{{ .field }}.env{name: "TZ", value: variables.timezone}],
  volumeMounts:
    (c.?volumeMounts.orValue([]).exists(m, m.mountPath == {{ .zoneInfoMountPath | quote }})
      ? []
      : [Object.spec.{{ .field }}.volumeMounts{
          name: {{ .volumeName | quote }},
          mountPath: {{ .zoneInfoMountPath | quote }},
          readOnly: true
        }]) +
    (c.?volumeMounts.orValue([]).exists(m, m.mountPath == {{ .localtimeMountPath | quote }})
      ? []
      : [Object.spec.{{ .field }}.volumeMounts{
          name: {{ .volumeName | quote }},
          mountPath: {{ .localtimeMountPath | quote }},
          subPath: variables.timezone,
          readOnly: true
        }])
})
{{- end -}}