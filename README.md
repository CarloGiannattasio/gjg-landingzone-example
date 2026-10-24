# gjg-landingzone-example

Enterprise-style multi-cloud landing zone **example** for business unit `example`. One JSON document per account or project is the contract. The Terraform root module decodes those documents and calls shared AWS and GCP modules. Terraform `>= 1.5` (CI pins `1.9.8`). GitHub Actions runs fmt, TFLint, Checkov, a config-contract check, a Moto plan of the same AWS account files as the real-credential plan, a credential-free GCP mock plan of the same GCP project list, `terraform test`, a real-account AWS plan when AWS secrets are set, and a real GCP plan of root when both GCP and AWS plan secrets are set. Pull requests get one sticky comment: a table of each plan, the account name, and the add, change, and destroy counts.

The pipeline is **plan-only**. `terraform apply` is commented out in the workflow and cannot run.

## Layout

```
.
├── .github/workflows/landing-zone-pipeline.yml
├── .github/CODEOWNERS
├── .tflint.hcl
├── requirements-dev.txt
├── scripts/plan-with-c7n-moto.sh
├── scripts/plan-with-gcp-mock.sh
├── config/
│   ├── aws/example/example-prod/example-prod.json
│   ├── aws/example/example-nonprod/example-nonprod.json
│   ├── aws/example/example-preprod/example-preprod.json
│   └── gcp/example/example-prod/example-prod.json
├── modules/
│   ├── aws-iam-role/
│   ├── aws-vpc-tshirt/
│   └── gcp-vpc-tshirt/
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
├── tests/gcp_vpc_tshirt.tftest.hcl
└── tests.tf
```

| Path | Role |
| --- | --- |
| `config/aws/example/*` | Account files for prod, nonprod, and preprod. `config_path` selects one of them. |
| `config/gcp/example/example-prod` | GCP project file. `gcp_config_path` selects it. |
| `modules/aws-vpc-tshirt` | VPC, subnets, and NAT from a T-shirt size. Removes the default VPC. |
| `modules/gcp-vpc-tshirt` | Custom-mode VPC, deny-all ingress firewall, subnets, Cloud Router, and Cloud NAT from a T-shirt size. Does not delete the GCP default network. |
| `modules/aws-iam-role` | Role plus customer managed policy. Both documents are loaded with `file()`. |
| `policies/` | Trust and permissions JSON, separate from the module source. |
| `root/` | Composition root. No remote backend; state stays local for this example. |
| `tests/vpc_tshirt.tftest.hcl` | `terraform test` with a mocked AWS provider. |
| `tests/gcp_vpc_tshirt.tftest.hcl` | `terraform test` with a mocked Google provider. |
| `tests.tf` | Root configuration with no resources, so `terraform init` installs the modules under test. |
| `scripts/plan-with-c7n-moto.sh` | Local `terraform plan` against Moto and a loopback Compute stub. The first argument is the AWS config path. |
| `scripts/plan-with-gcp-mock.sh` | Same mock plan. Forwards the AWS config path and an optional GCP project path. Dummy credentials. Compute is loopback; provider init still calls Google userinfo. |
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
- Checks the GCP file has `account_name` or `project_name`, `project_id`, `environment`, `business_unit`, `region`, `cost_center`, `mandatory_tags`, and `vpc.name`, `vpc.cidr_block`, and `vpc.tshirt_size`.
- Calls `modules/gcp-vpc-tshirt` with the network name, size, CIDR, region, project, and flow-log flag. `mandatory_tags` stays on the JSON contract. These Compute resources do not accept labels in hashicorp/google 8.8.1.
- Exports the decoded GCP `project_id` and `environment` (`gcp_project_id`, `gcp_environment`) and the network outputs.

The AWS provider region and default tags come from the selected account file. CI authenticates with GitHub OIDC when a real-account secret is set. The provider block does not contain keys unless `aws_endpoint_url` is set for a Moto plan, and then the keys are the dummy pair `testing` / `testing` sent only to that URL.

The Google provider project and region come from the GCP file. Credentials come from the environment when `gcp_endpoint_url` is null. A non-null URL sets the dummy access token `testing` and `compute_custom_endpoint` to that URL. `hashicorp/google` has no single API host; that field covers the Compute resources in the VPC module (network, subnets, router, Cloud NAT).

## T-shirt sizes

`modules/aws-vpc-tshirt` maps `vpc.tshirt_size` to availability zones and NAT gateways. The module also deletes the account's default VPC with `aws_default_vpc` and `force_destroy`.

| Size | Availability zones | NAT gateways | Used by |
| --- | --- | --- | --- |
| Small | 1 | 1 | `example-nonprod` (`10.20.0.0/16`) |
| Medium | 2 | 1 | `example-preprod` (`10.30.0.0/16`) |
| Large | 3 | 1 per AZ | `example-prod` (`10.10.0.0/16`) |

Flow logs are enabled for prod and preprod (`enable_flow_logs: true`). Nonprod leaves them disabled. Every AWS account file sets `delete_default_vpc: true`.

`modules/gcp-vpc-tshirt` uses the same sizes. Small is one zone and one Cloud NAT, Medium is two zones and one shared Cloud NAT, and Large is three zones and one Cloud NAT per zone. The example GCP project is Large (`10.50.0.0/16`, flow logs on). The module does not delete the GCP default network. It defines a deny-all ingress firewall and does not open `0.0.0.0/0`. Private Google Access is on for every subnet.

## IAM documents

Policies stay out of the module as JSON so a reviewer can read them without the HCL. `modules/aws-iam-role` loads them with `file(var.trust_policy_path)` and `file(var.permission_policy_path)` and attaches the customer managed policy to the role.

`policies/iam-trust/pipeline-trust.json` is an assume-role policy. The AWS principal is `arn:aws:iam::123456789012:role/GitHubActionsDeploymentRole`. `123456789012` is a placeholder account, not a live one. The same statement also trusts `lambda.amazonaws.com`.

`policies/iam-permissions/example-admin-policy.json` is a teaching policy for the `example-admin` role. The actions are a short platform set (`ec2:Describe*`, `ec2:CreateVpc`, `ec2:DeleteVpc`, `iam:PassRole`). The statement still uses `"Resource": "*"`. That wildcard is the least-privilege seam: a production policy would name resource ARNs and drop unused actions. Checkov runs with no skip list, so this document stays in the review path.

## Plan locally

From the repo root, with AWS and GCP credentials available to the process that runs Terraform (a plan of root talks to both providers):

```bash
terraform -chdir=root init -backend=false
terraform -chdir=root plan -var='config_path=../config/aws/example/example-prod/example-prod.json'
```

Swap the path for `example-nonprod` or `example-preprod` to plan those accounts. `init -backend=false` matches this example: `root/versions.tf` has no backend block.

`terraform plan` refreshes AWS and GCP. It does not apply. There is no apply command in the local flow above. `gcp_config_path` defaults to the example GCP project file.

## Plan against Cloud Custodian's Moto

Cloud Custodian does not publish a package, image, or file named moto3. Its dev dependency group pins `moto>=5.0,<6.0`, and `uv.lock` on `main` resolves `moto==5.2.3`. The AWS tests that mock the API call `moto.mock_aws` in-process (`tests/test_org.py`, `tests/test_kms.py`, `tests/test_sns.py` in [cloud-custodian/cloud-custodian](https://github.com/cloud-custodian/cloud-custodian)). That decorator only intercepts boto3. Terraform speaks HTTP, so `scripts/plan-with-c7n-moto.sh` installs that same pinned release (`requirements-dev.txt`) and serves it with `moto.server.ThreadedMotoServer`.

This is not a substitute for the OIDC plan against real AWS. `tests/vpc_tshirt.tftest.hcl` still uses Terraform's `mock_provider "aws"`.

```bash
./scripts/plan-with-c7n-moto.sh
```

With no arguments, the script plans `config/aws/example/example-nonprod/example-nonprod.json` (Small, flow logs off) and the default GCP project file. That default is only for a local run with no arguments. Pass an AWS config path, relative to the `root` module, as the first argument. Pass a GCP project path as the second argument when the plan should not use the default GCP file. It does not apply. It sets `aws_endpoint_url` and `gcp_endpoint_url`. With both unset, the providers stay on real AWS and real Google.

`./scripts/plan-with-gcp-mock.sh` runs that same plan and forwards those arguments. It does not need real Google or AWS credentials.

CI does not stop at the no-argument default. The Moto matrix matches the real-credential AWS config list (`example-prod`, `example-nonprod`, and `example-preprod`). The GCP mock matrix matches the real GCP config list (today `config/gcp/example/example-prod/example-prod.json`). Each cell plans that cell's config and does not apply. The pull request comment is one table with a row per plan and account.

For example, a plan of the nonprod config against Moto and the loopback Compute stub succeeded: 29 to add, 0 to change, 0 to destroy. Moto answered EC2 `DescribeAvailabilityZones` (`us-east-1a`). The plan includes the AWS VPC, subnets, NAT, default VPC adoption, and the `example-admin` role, plus the GCP network, subnets, Cloud Routers, and Cloud NAT from the example project (Large). Provider init still requests Google userinfo on googleapis.com and continues after a 401 for the dummy token. No Compute request was sent to compute.googleapis.com or to the stub on that empty-state plan. The script does not apply.

## Real account

To point `terraform-plan` at a real account later, add secrets in the GitHub repo under Settings → Secrets and variables → Actions. Type the values there. They are not committed, and they do not go in JSON config or tfvars.

- Preferred: `AWS_PLAN_ROLE_ARN`. The plan job assumes that role with GitHub OIDC.
- Or, if you choose long-lived keys instead of a role: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
- Optional: `AWS_REGION`. When that secret is unset, the credentials step uses `us-east-1`.

If `AWS_PLAN_ROLE_ARN` is set, the job uses OIDC. Otherwise, if both access key secrets are set, the job uses those static keys. If neither is configured, the real-account plan job is skipped and the Moto matrix still runs.

The real GCP plan (`terraform-plan (real GCP)`) runs only when both sets of credentials are present, because that plan talks to AWS and GCP:

- Preferred: `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` (Workload Identity Federation).
- Or, if you choose a key instead: `GCP_SA_KEY`.
- And the AWS plan secrets above (`AWS_PLAN_ROLE_ARN`, or both access key secrets).

If only one side is set, the real GCP job is skipped. The pull request comment says which side was missing. Secret values are not printed. The mock plans do not read these secrets.

The account id `123456789012` in `policies/iam-trust/pipeline-trust.json` is a placeholder in the example trust policy. It is unrelated to these secrets and is still not a live account.

## Tests

From the repo root:

```bash
terraform init -backend=false
terraform test
```

`terraform init` installs the module the test file references. `tests.tf` declares no resources; Terraform 1.9 needs that file to load the test. A directory with only `.tftest.hcl` files is treated as empty and skips the install. `tests/vpc_tshirt.tftest.hcl` mocks the AWS provider and `tests/gcp_vpc_tshirt.tftest.hcl` mocks the Google provider, so the tests do not need credentials or a cloud account.

## Pipeline

Workflow: `.github/workflows/landing-zone-pipeline.yml` (`Landing Zone Pipeline`).

Triggers: push to `main`, pull requests targeting `main`, and manual `workflow_dispatch`.

Permissions at the workflow level are `contents: read` and `id-token: write`. The workflow does not request write-all, and it does not store static AWS or GCP keys. `terraform-plan-moto` and `terraform-plan-gcp-mock` set `contents: read` only. They do not receive AWS or GCP secrets, and they do not comment. `pipeline` sets `contents: read`, `pull-requests: write`, and `issues: write`. On a pull request it posts one plans table and deletes the older per-plan comments. Push to `main` and `workflow_dispatch` do not comment, so those graphs have no comment jobs.

| Job | What it does | AWS credentials |
| --- | --- | --- |
| `lint-and-scan` | `terraform fmt -check -recursive`, `tflint --init` and `tflint --recursive`, Checkov (`framework: terraform`) on `modules/` and `root/`, then a Python check that every `config/**/*.json` has the contract keys (AWS and GCP). | None |
| `aws-credentials-present` | Checks whether real-account secrets are set. Prints `oidc`, `static`, or `unset`. Does not print secret values. | Reads secret names only |
| `terraform-plan (real AWS account)` | Skipped when neither `AWS_PLAN_ROLE_ARN` nor both access key secrets are set. Otherwise a matrix of the three AWS account files. Working directory `root`. `terraform init -backend=false`, `terraform validate`, `terraform plan -var=config_path=... -out=tfplan`. OIDC when the role secret is set; static keys only when the role secret is empty and both key secrets are set. Also authenticates to GCP when those secrets are set, because root plans GCP resources too. | OIDC role, or the two key secrets. GCP auth when configured |
| `gcp-credentials-present` | Checks GCP and AWS plan secrets. Prints `wif`, `sa_key`, or `unset` for GCP and `oidc`, `static`, or `unset` for AWS. Does not print secret values. | Reads secret names only |
| `terraform-plan (real GCP)` | Skipped unless GCP credentials (`GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT`, or `GCP_SA_KEY`) and AWS plan credentials are both set. Matrix of the GCP project list (today `config/gcp/example/example-prod/example-prod.json`), the same list as the mock. Also passes the example-prod AWS account file because root plans both providers. No apply. | Both GCP and AWS plan credentials |
| `terraform-plan-moto` | Matrix of the same three AWS account files as the real plan. `./scripts/plan-with-c7n-moto.sh` with that cell's config path, Moto, and a loopback Compute URL. No secrets. No apply. Does not comment. | None |
| `terraform-plan-gcp-mock` | Matrix of the same GCP project list as the real GCP plan. `./scripts/plan-with-gcp-mock.sh` with that cell's GCP path and the example-prod AWS account file. No secrets. No apply. Does not comment. | None |
| `terraform-test` | `terraform init -backend=false`, then `terraform test` from the repo root. | None |
| `pipeline` | Needs every other job, so the Actions graph is one pipeline. Fails when any needed job failed. A skipped real plan does not fail it. On a pull request, posts or updates one sticky comment (`<!-- landing-zone-plans -->`): a table with plan, account, add, change, and destroy. | None |

`terraform apply -input=false tfplan` is present only as a YAML comment on the real AWS plan job and the real GCP plan job. GitHub Actions does not parse it, so apply is not a step and cannot run. Promoting a plan to apply would be a separate, reviewed change.

On a pull request, `pipeline` updates `<!-- landing-zone-plans -->` with one table. Each row is one plan and one account (`example-prod`, `example-nonprod`, `example-preprod` for AWS; `example-prod` for GCP). The count columns are the plan summary: add, change, and destroy. A skipped real plan shows `skipped` in those columns and a sentence under the table says which credential set was missing. Secret values are not printed. The full plan text stays in the workflow artifacts. Pushes to `main` and manual `workflow_dispatch` runs still plan and do not comment, because those events are not pull requests.

`.github/CODEOWNERS` names `@CarloGiannattasio` as the owner of every path. `main` is protected. A merge requires that code owner's approval, dismisses stale approvals, blocks force pushes and deletions, and requires the `pipeline` check on an up-to-date branch. That job needs every other job, so one required check covers lint, tests, mock plans, and the real plans. `terraform-plan (real AWS account)` stays skipped when secrets are unset, and a skipped needed job does not fail `pipeline`. Admins can bypass these rules, so the code owner is not locked out of a pull request they opened. Everyone else still needs that code-owner approval.

## CIS-oriented choices

- **No default VPC.** Account configs set `delete_default_vpc`, and the VPC module removes it with `aws_default_vpc` (`force_destroy`).
- **Flow logs on prod and preprod.** Those two files set `enable_flow_logs` to true. Nonprod is the explicit exception in config.
- **No long-lived cloud keys in CI.** The plan job uses GitHub OIDC. The workflow file has no access key id or secret.
- **Least privilege is unfinished on purpose.** `example-admin-policy` is a teaching document and still allows `Resource: *`. The workflow passes no Checkov skip list, so a reviewer can see that seam.
- **Policies are data.** Trust and permissions are external JSON loaded with `file()`, and the trust policy's account id is the placeholder `123456789012`.
