package main

# Translates skills/harness-gates/references/policies.md
# "Infrastructure Policies > Kubernetes" section into Conftest/OPA rules
# evaluated against rendered manifests (`helm template` / `kubectl` YAML).
# Complements kube-score/Polaris (best-practice scoring) with hard blocks
# specific to this repo's policy, not general advice.

import rego.v1

containers contains c if {
	c := input.spec.template.spec.containers[_]
}

containers contains c if {
	c := input.spec.containers[_]
}

# --- NEVER use `latest` as image tag ---
deny contains msg if {
	c := containers[_]
	image := c.image
	endswith(image, ":latest")
	msg := sprintf("container %v uses ':latest' tag (%v) — see policies.md > Kubernetes", [c.name, image])
}

deny contains msg if {
	c := containers[_]
	not contains(c.image, ":")
	msg := sprintf("container %v has no explicit image tag (defaults to :latest) — see policies.md > Kubernetes", [c.name])
}

# --- NEVER create pod without resource limits ---
deny contains msg if {
	c := containers[_]
	not c.resources.limits.cpu
	msg := sprintf("container %v has no CPU resource limit — see policies.md > Kubernetes", [c.name])
}

deny contains msg if {
	c := containers[_]
	not c.resources.limits.memory
	msg := sprintf("container %v has no memory resource limit — see policies.md > Kubernetes", [c.name])
}

# --- NEVER create pod without health checks (liveness + readiness) ---
deny contains msg if {
	c := containers[_]
	not c.livenessProbe
	msg := sprintf("container %v has no livenessProbe — see policies.md > Kubernetes", [c.name])
}

deny contains msg if {
	c := containers[_]
	not c.readinessProbe
	msg := sprintf("container %v has no readinessProbe — see policies.md > Kubernetes", [c.name])
}

# --- NEVER expose service without TLS ---
deny contains msg if {
	input.kind == "Ingress"
	not input.spec.tls
	msg := sprintf("Ingress %v has no spec.tls — see policies.md > Kubernetes", [input.metadata.name])
}

# NOTE — deliberately NOT translated (out of scope for static manifest
# analysis, see .specs/QUESTIONS.md):
#   - "NEVER deploy to production without passing in staging" -> CI pipeline sequencing/environment-promotion rule, not a manifest-content rule
