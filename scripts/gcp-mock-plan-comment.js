"use strict";

// Sticky pull-request comment for the GCP mock plan.
// Marker: <!-- landing-zone-plan-gcp-mock -->
// The workflow calls postGcpMockPlanComment only for pull_request events.

const fs = require("fs");
const path = require("path");

const MARKER = "<!-- landing-zone-plan-gcp-mock -->";
const MAX_PLAN = 60000;
const MAX_COMMENT = 65000;

function stripAnsi(text) {
  return String(text)
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g, "");
}

function redact(text) {
  return stripAnsi(text)
    .replace(/\u0000/g, "")
    .replace(/\b(AKIA|ASIA|AROA|AIDA)[0-9A-Z]{16}\b/g, "[redacted]")
    .replace(/\bgithub_pat_[A-Za-z0-9_]{20,}\b/g, "[redacted]")
    .replace(/\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b/g, "[redacted]")
    .replace(/(aws_secret_access_key|aws_access_key_id|aws_session_token)\s*[:=]\s*\S+/gi, "$1=[redacted]")
    .replace(/"private_key"\s*:\s*"[^"]*"/g, '"private_key":"[redacted]"')
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[redacted]")
    .replace(/\bya29\.[0-9A-Za-z\-_]+\b/g, "[redacted]");
}

function truncate(text, limit) {
  const value = String(text);
  if (value.length <= limit) return value;
  const suffix = `\n… truncated to ${limit} characters`;
  const keep = Math.max(0, limit - suffix.length);
  return value.slice(0, keep) + suffix;
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function planSummary(text) {
  const plan = text.match(/^Plan:\s+\d+\s+to add,\s+\d+\s+to change,\s+\d+\s+to destroy\.?\s*$/m);
  if (plan) return plan[0].trim();
  const none = text.match(/^No changes\..+$/m);
  if (none) return none[0].trim();
  const err = text.match(/^Error: .+$/m);
  if (err) return err[0].trim().slice(0, 300);
  return "Plan summary was not found in the output.";
}

function headerFor(outcome) {
  const lines = [
    "## Terraform plan (GCP mock)",
    "",
    "This is the mock plan of `root` (nonprod AWS config plus the example GCP project). " +
      "It runs `./scripts/plan-with-gcp-mock.sh`. " +
      "AWS calls use dummy keys against Cloud Custodian's pinned Moto. " +
      "Compute calls use the dummy access token `testing` against a loopback URL (`gcp_endpoint_url` → `compute_custom_endpoint`). " +
      "It does not use real Google or AWS credentials and it is not a live apply. " +
      "The Google provider has no single API host; only Compute is pointed at the stub. " +
      "Provider init still calls the Google userinfo endpoint on googleapis.com and continues if that request fails. " +
      "That call is not a mock. An empty-state plan does not call compute.googleapis.com.",
  ];
  if (outcome === "failure") {
    lines.push("", "The GCP mock plan step failed. The output below is from that run.");
  } else if (outcome && outcome !== "success") {
    lines.push("", `The GCP mock plan step result was \`${outcome}\`.`);
  }
  return lines.join("\n");
}

function assemble(header, summary, escapedPlan) {
  const visible = summary.replace(/[*_`\\[\]]/g, "");
  return [
    MARKER,
    header,
    "",
    `**${visible}**`,
    "",
    "<details>",
    `<summary>${escapeHtml(summary)}</summary>`,
    "",
    `<pre><code>${escapedPlan}</code></pre>`,
    "</details>",
    "",
  ].join("\n");
}

function buildGcpMockPlanComment(raw, outcome) {
  const cleaned = redact(raw).trim();
  const text = cleaned || "(no output)";
  const summary = planSummary(text);
  const header = headerFor(outcome || "unknown");
  let escaped = escapeHtml(truncate(text, MAX_PLAN));
  if (escaped.length > MAX_PLAN) escaped = truncate(escaped, MAX_PLAN);

  let body = assemble(header, summary, escaped);
  if (body.length > MAX_COMMENT) {
    const overflow = body.length - MAX_COMMENT;
    const tighter = Math.max(500, escaped.length - overflow - 80);
    escaped = truncate(escaped, tighter);
    body = assemble(header, summary, escaped);
  }
  if (body.length > MAX_COMMENT) {
    body = `${body.slice(0, MAX_COMMENT - 28)}\n… comment truncated`;
  }
  return { body, summary };
}

function planFilePath() {
  const root = process.env.GITHUB_WORKSPACE || process.cwd();
  return path.join(root, "plan-gcp-mock.txt");
}

async function postGcpMockPlanComment({ github, context, core }) {
  const file = planFilePath();
  const raw = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "GCP mock plan produced no output.";
  const { body, summary } = buildGcpMockPlanComment(raw, process.env.PLAN_OUTCOME || "unknown");
  if (core) core.info(`GCP mock plan comment summary: ${summary}`);

  const comments = await github.paginate(github.rest.issues.listComments, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
    per_page: 100,
  });
  const existing = comments.find(
    (comment) => typeof comment.body === "string" && comment.body.startsWith(MARKER)
  );
  if (existing) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: existing.id,
      body,
    });
    if (core) core.info(`Updated GCP mock plan comment ${existing.id}`);
    return existing.id;
  }
  const created = await github.rest.issues.createComment({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
    body,
  });
  if (core) core.info(`Created GCP mock plan comment ${created.data.id}`);
  return created.data.id;
}

module.exports = {
  MARKER,
  MAX_PLAN,
  MAX_COMMENT,
  buildGcpMockPlanComment,
  postGcpMockPlanComment,
  planSummary,
  redact,
};
