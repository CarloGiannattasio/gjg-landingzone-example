resource "aws_iam_role" "this" {
  name               = var.role_name
  description        = "Assumable IAM role. Trust policy is loaded from an external JSON document."
  assume_role_policy = file(var.trust_policy_path)
  tags               = var.tags
}

resource "aws_iam_policy" "custom" {
  name        = "${var.role_name}-policy"
  description = "Customer managed permissions for ${var.role_name}. Policy document is loaded from an external JSON file."
  policy      = file(var.permission_policy_path)
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.custom.arn
}
