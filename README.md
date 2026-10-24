# gjg-landingzone-example

Enterprise-style multi-cloud landing zone **example** for business unit `example`. One JSON document per account or project is the contract. The Terraform root module decodes that document and calls shared AWS modules. Terraform `>= 1.5` (CI pins `1.9.8`). GitHub Actions runs fmt, TFLint, Checkov, a config-contract check, a Moto plan of nonprod, `terraform test`, and a real-account plan for each AWS config when repository secrets are set. Pull requests get those plans as sticky comments.

The pipeline is **plan-only**. `terraform apply` is commented out in the workflow and cannot run.

## Layout

```
.
├── .github/workflows/landing-zone-pipeline.yml
├── .github/CODEOWNERS
├── .tflint.hcl
├── requirements-dev.txt
├── scripts/plan-with-c7n-moto.sh
├── config/
│   ├── aws/example/example-prod/example-prod.json
│   ├── aws/example/example-nonprod/example-nonprod.json
│   ├── aws/example/example-preprod/example-preprod.json
│   └── gcp/example/example-prod/example-prod.json
├── modules/
│   ├── aws-iam-role/
│   └── aws-vpc-tshirt/
├── policies/
│   ├── iam-permissions/example-admin-policy.json
│   └── iam-trust/pipeline-trust.json
├── root/
│   ├── main.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── variables.tf
│   └── versions.tf
├── tests/vpc_tshirt.tftest.hcl
└── tests.tf
```

| Path | Role |
| --- | --- |
| `config/aws/example/*` | Account files for prod, nonprod, and preprod. `config_path` selects one of them. |
| `config/gcp/example/example-prod` | GCP project file. Decoded and exported. No GCP resources are created. |
| `modules/aws-vpc-tshirt` | VPC, subnets, and NAT from a T-shirt size. Removes the default VPC. |
| `modules/aws-iam-role` | Role plus customer managed policy. Both documents are loaded with `file()`. |
| `policies/` | Trust and permissions JSON, separate from the module source. |
| `root/` | Composition root. No remote backend; state stays local for this example. |
| `tests/vpc_tshirt.tftest.hcl` | `terraform test` with a mocked AWS provider. |
| `tests.tf` | Root configuration with no resources, so `terraform init` installs the module under test. |
| `scripts/plan-with-c7n-moto.sh` | Local `terraform plan` against Cloud Custodian's pinned Moto. |
| `requirements-dev.txt` | Pins that Moto release (`moto[server]==5.2.3`). |

Every `config/**/*.json` file carries `account_name` or `project_id`, plus `environment`, `business_unit`, `region`, `cost_center`, `mandatory_tags`, and `vpc`. AWS files use `account_name`. The GCP file uses `project_id` (and also sets `account_name`). CI rejects a file that drops any of those keys.

## What the root module does

`root/main.tf` reads the selected account file and the GCP file:

```hcl
aws_config = jsondecode(file(abspath("${path.module}/${var.config_path}")))
gcp_config = jsondecode(file(abspath("${path.module}/${var.gcp_config_path}")))
```

`config_path` is required. `gcp_config_path` defaults to `../config/gcp/example/example-prod/example-prod.json`.

The root module then:

- Checks the AWS business unit is `example`, the environment is `prod`, `nonprod`, or `preprod`, and `vpc.tshirt_size` is `Small`, `Medium`, or `Large`.
- Calls `modules/aws-vpc-tshirt` with the VPC name, size, CIDR, default-VPC deletion flag, flow-log flag, and `mandatory_tags`.
- Calls `modules/aws-iam-role` once per `iam_roles` entry. Trust and permission filenames in the JSON are resolved under `policies/iam-trust/` and `policies/iam-permissions/`.
- Exports the decoded GCP `project_id` and `environment` (`gcp_project_id`, `gcp_environment`). The Google provider is not configured. This example has no GCP module, so the GCP document is data only.

The AWS provider region and default tags come from the selected account file. CI authenticates with GitHub OIDC when a real-account secret is set. The provider block does not contain keys unless `aws_endpoint_url` is set for a Moto plan, and then the keys are the dummy pair `testing` / `testing` sent only to that URL.

## T-shirt sizes

`modules/aws-vpc-tshirt` maps `vpc.tshirt_size` to availability zones and NAT gateways. The module also deletes the account's default VPC with `aws_default_vpc` and `force_destroy`.

| Size | Availability zones | NAT gateways | Used by |
| --- | --- | --- | --- |
| Small | 1 | 1 | `example-nonprod` (`10.20.0.0/16`) |
| Medium | 2 | 1 | `example-preprod` (`10.30.0.0/16`) |
| Large | 3 | 1 per AZ | `example-prod` (`10.10.0.0/16`) |

Flow logs are enabled for prod and preprod (`enable_flow_logs: true`). Nonprod leaves them disabled. Every AWS account file sets `delete_default_vpc: true`.

## IAM documents

Policies stay out of the module as JSON so a reviewer can read them without the HCL. `modules/aws-iam-role` loads them with `file(var.trust_policy_path)` and `file(var.permission_policy_path)` and attaches the customer managed policy to the role.

`policies/iam-trust/pipeline-trust.json` is an assume-role policy. The AWS principal is `arn:aws:iam::123456789012:role/GitHubActionsDeploymentRole`. `123456789012` is a placeholder account, not a live one. The same statement also trusts `lambda.amazonaws.com`.

`policies/iam-permissions/example-admin-policy.json` is a teaching policy for the `example-admin` role. The actions are a short platform set (`ec2:Describe*`, `ec2:CreateVpc`, `ec2:DeleteVpc`, `iam:PassRole`). The statement still uses `"Resource": "*"`. That wildcard is the least-privilege seam: a production policy would name resource ARNs and drop unused actions. Checkov runs with no skip list, so this document stays in the review path.

## Plan locally

From the repo root, with AWS credentials available to the process that runs Terraform:

```bash
terraform -chdir=root init -backend=false
terraform -chdir=root plan -var='config_path=../config/aws/example/example-prod/example-prod.json'
```

Swap the path for `example-nonprod` or `example-preprod` to plan those accounts. `init -backend=false` matches this example: `root/versions.tf` has no backend block.

`terraform plan` refreshes AWS. It does not apply. There is no apply command in the local flow above.

## Plan against Cloud Custodian's Moto

Cloud Custodian does not publish a package, image, or file named moto3. Its dev dependency group pins `moto>=5.0,<6.0`, and `uv.lock` on `main` resolves `moto==5.2.3`. The AWS tests that mock the API call `moto.mock_aws` in-process (`tests/test_org.py`, `tests/test_kms.py`, `tests/test_sns.py` in [cloud-custodian/cloud-custodian](https://github.com/cloud-custodian/cloud-custodian)). That decorator only intercepts boto3. Terraform speaks HTTP, so `scripts/plan-with-c7n-moto.sh` installs that same pinned release (`requirements-dev.txt`) and serves it with `moto.server.ThreadedMotoServer`.

This is not a substitute for the OIDC plan against real AWS. `tests/vpc_tshirt.tftest.hcl` still uses Terraform's `mock_provider "aws"`.

```bash
./scripts/plan-with-c7n-moto.sh
```

The script plans `config/aws/example/example-nonprod/example-nonprod.json` (Small, flow logs off). Pass another config path, relative to the `root` module, as the first argument. It does not apply. With `aws_endpoint_url` unset, the provider stays on real AWS.

A plan of the nonprod config against this server succeeded: 16 to add, 0 to change, 0 to destroy. Moto answered EC2 `DescribeAvailabilityZones` (`us-east-1a`). The plan includes the VPC, public and private subnets, the default security group with no rules, internet gateway, route tables and associations, NAT EIP, NAT gateway, default VPC adoption (`aws_default_vpc`), the `example-admin` IAM role, its customer managed policy, and the attachment. Flow logs and CloudWatch Logs are not in that plan because nonprod sets `enable_flow_logs` to false. Plan does not call the create APIs, and this repo does not apply, so default-VPC adoption was not executed against Moto. No resource was removed from the real-AWS path.

## Real account

To point `terraform-plan` at a real account later, add secrets in the GitHub repo under Settings → Secrets and variables → Actions. Type the values there. They are not committed, and they do not go in JSON config or tfvars.

- Preferred: `AWS_PLAN_ROLE_ARN`. The plan job assumes that role with GitHub OIDC.
- Or, if you choose long-lived keys instead of a role: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
- Optional: `AWS_REGION`. When that secret is unset, the credentials step uses `us-east-1`.

If `AWS_PLAN_ROLE_ARN` is set, the job uses OIDC. Otherwise, if both access key secrets are set, the job uses those static keys. If neither is configured, the real-account plan job is skipped and the Moto plan job still runs.

The account id `123456789012` in `policies/iam-trust/pipeline-trust.json` is a placeholder in the example trust policy. It is unrelated to these secrets and is still not a live account.

## Tests

From the repo root:

```bash
terraform init -backend=false
terraform test
```

`terraform init` installs the module the test file references. `tests.tf` declares no resources; Terraform 1.9 needs that file to load the test. A directory with only `.tftest.hcl` files is treated as empty and skips the install. `tests/vpc_tshirt.tftest.hcl` mocks the AWS provider, so the test does not need credentials or a cloud account.

## Pipeline

Workflow: `.github/workflows/landing-zone-pipeline.yml` (`Landing Zone Pipeline`).

Triggers: push to `main`, pull requests targeting `main`, and manual `workflow_dispatch`.

Permissions at the workflow level are `contents: read` and `id-token: write`. The workflow does not request write-all, and it does not store static AWS keys. `terraform-plan-moto` sets `contents: read` and `pull-requests: write` so that job can comment its plan on pull requests. `comment-plans` uses those same two permissions for the real-account comment and does not check out the pull request.

| Job | What it does | AWS credentials |
| --- | --- | --- |
| `lint-and-scan` | `terraform fmt -check -recursive`, `tflint --init` and `tflint --recursive`, Checkov (`framework: terraform`) on `modules/` and `root/`, then a Python check that every `config/**/*.json` has the contract keys (AWS and GCP). | None |
| `aws-credentials-present` | Checks whether real-account secrets are set. Prints `oidc`, `static`, or `unset`. Does not print secret values. | Reads secret names only |
| `terraform-plan (real AWS account)` | Skipped when neither `AWS_PLAN_ROLE_ARN` nor both access key secrets are set. Otherwise a matrix of the three AWS account files. Working directory `root`. `terraform init -backend=false`, `terraform validate`, `terraform plan -var=config_path=... -out=tfplan`. OIDC when the role secret is set; static keys only when the role secret is empty and both key secrets are set. | OIDC role, or the two key secrets |
| `terraform-plan-moto` | `./scripts/plan-with-c7n-moto.sh` for the nonprod config. No apply. On pull requests, posts or updates one sticky comment (`<!-- landing-zone-plan -->`) with the plan summary and the plan text. | None |
| `terraform-test` | `terraform init -backend=false`, then `terraform test` from the repo root. | None |
| `comment-plans` | Pull requests only. Posts or updates the real-account sticky comment (`<!-- landing-zone-plan-real -->`). Says the real plan was skipped when AWS secrets are unset. Does not check out code. | None |

`terraform apply -input=false tfplan` is present only as a YAML comment on the plan job. GitHub Actions does not parse it, so apply is not a step and cannot run. Promoting a plan to apply would be a separate, reviewed change.

On a pull request, `terraform-plan-moto` updates `<!-- landing-zone-plan -->` with the Moto plan for nonprod. The comment states that the run does not use AWS credentials and is not a live apply. The plan summary line (for example `Plan: N to add`) is visible, and the plan text is in a collapsed details block, truncated near 60k characters. `comment-plans` updates `<!-- landing-zone-plan-real -->` with the real-account plan, or a note that the real-account plan was skipped when AWS secrets are unset. Secret values are not printed. Pushes to `main` and manual `workflow_dispatch` runs do not comment, because those events are not pull requests.

`.github/CODEOWNERS` names `@CarloGiannattasio` as the owner of every path. Merges to `main` are meant to require that code owner's approval, dismiss stale approvals, block force pushes and deletions, and require `lint-and-scan`, `terraform-test`, `terraform-plan-moto`, and `real-account credentials check`. `terraform-plan (real AWS account)` is not required, because that job is skipped when secrets are unset and a skipped required check would block merges. Admin bypass stays available so the code owner is not locked out of a pull request they opened. Everyone else still needs that code-owner approval.

Those rules are not enforced yet. Branch protection and repository rulesets both returned HTTP 403: `Upgrade to GitHub Pro or make this repository public to enable this feature.` The repository is private, and making it public was not used as a workaround. Apply the settings above once GitHub Pro (or a public repository) is available, and leave "Do not allow bypassing the above settings" unchecked.

## CIS-oriented choices

- **No default VPC.** Account configs set `delete_default_vpc`, and the VPC module removes it with `aws_default_vpc` (`force_destroy`).
- **Flow logs on prod and preprod.** Those two files set `enable_flow_logs` to true. Nonprod is the explicit exception in config.
- **No long-lived cloud keys in CI.** The plan job uses GitHub OIDC. The workflow file has no access key id or secret.
- **Least privilege is unfinished on purpose.** `example-admin-policy` is a teaching document and still allows `Resource: *`. The workflow passes no Checkov skip list, so a reviewer can see that seam.
- **Policies are data.** Trust and permissions are external JSON loaded with `file()`, and the trust policy's account id is the placeholder `123456789012`.
