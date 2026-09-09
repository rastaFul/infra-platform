package main

# Translates skills/harness-gates/references/policies.md
# "Infrastructure Policies > Cloud" and "> Terraform" sections into
# Conftest/OPA rules evaluated against `terraform show -json plan.out`.
#
# This is policy-AS-CODE: it blocks mechanically. It does not replace
# tfsec/checkov (which scan resource config for known bad patterns) —
# it enforces THIS repo's specific hard rules, which are opinions, not
# universal CVE-style findings.

import rego.v1

resource_changes contains rc if {
	rc := input.resource_changes[_]
}

# --- NEVER SG ingress 0.0.0.0/0 (except explicitly tagged public ALB) ---
deny contains msg if {
	rc := resource_changes[_]
	rc.type == "aws_security_group_rule"
	rc.change.after.type == "ingress"
	cidr := rc.change.after.cidr_blocks[_]
	cidr == "0.0.0.0/0"
	not rc.change.after.description == "public-alb-approved"
	msg := sprintf("security group rule %v allows ingress from 0.0.0.0/0 without 'public-alb-approved' description — see policies.md > Cloud", [rc.address])
}

# --- NEVER remove stateful resources without confirmed backup ---
# Static plan analysis can't confirm a backup exists — it CAN catch the
# irreversible action itself and force a human decision, which is the point.
deny contains msg if {
	rc := resource_changes[_]
	rc.type in {"aws_db_instance", "aws_s3_bucket", "aws_rds_cluster", "aws_dynamodb_table"}
	rc.change.actions[_] == "delete"
	msg := sprintf("%v (%v) is a stateful resource being DELETED — requires explicit human approval + confirmed backup per policies.md, plan alone cannot verify a backup exists", [rc.address, rc.type])
}

# --- NEVER create resources without mandatory tags ---
required_tags := {"Environment", "Team", "App"}

taggable_types := {"aws_instance", "aws_db_instance", "aws_s3_bucket", "aws_lambda_function", "aws_eks_cluster", "aws_vpc"}

deny contains msg if {
	rc := resource_changes[_]
	rc.type in taggable_types
	rc.change.actions[_] == "create"
	tags := object.get(rc.change.after, "tags", {})
	missing := required_tags - {k | some k, _ in tags}
	count(missing) > 0
	msg := sprintf("%v is missing mandatory tags: %v — see policies.md > Cloud", [rc.address, missing])
}

# --- NEVER use static credentials ---
deny contains msg if {
	rc := resource_changes[_]
	rc.type == "aws_iam_access_key"
	rc.change.actions[_] == "create"
	msg := sprintf("%v creates a static IAM access key — use IAM roles / workload identity per policies.md > Cloud", [rc.address])
}

# --- NEVER create public storage buckets ---
deny contains msg if {
	rc := resource_changes[_]
	rc.type == "aws_s3_bucket_acl"
	acl := rc.change.after.acl
	acl in {"public-read", "public-read-write"}
	msg := sprintf("%v sets a public ACL (%v) — see policies.md > Cloud", [rc.address, acl])
}

# --- NEVER disable encryption at rest ---
deny contains msg if {
	rc := resource_changes[_]
	rc.type == "aws_db_instance"
	rc.change.actions[_] == "create"
	rc.change.after.storage_encrypted == false
	msg := sprintf("%v creates an RDS instance with storage_encrypted = false — see policies.md > Cloud", [rc.address])
}

deny contains msg if {
	rc := resource_changes[_]
	rc.type == "aws_s3_bucket_server_side_encryption_configuration"
	rc.change.actions[_] == "delete"
	msg := sprintf("%v removes S3 server-side encryption — see policies.md > Cloud", [rc.address])
}

# NOTE — deliberately NOT translated into Rego (out of scope for static
# plan analysis, see .specs/QUESTIONS.md):
#   - "NEVER run terraform destroy without explicit approval"     -> CI/process gate, not a plan-content rule
#   - "NEVER run terraform apply without plan first"               -> CI pipeline ordering, not plan-content
#   - "NEVER commit state file"                                    -> .gitignore + git-secrets scope, not OPA
