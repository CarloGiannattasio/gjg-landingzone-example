"use strict";

// Sticky pull-request comment for the GCP mock plan matrix.
// Marker: <!-- landing-zone-plan-gcp-mock -->
// comment-gcp-mock calls postGcpMockPlanComment only for pull_request events.
// One comment covers every matrix cell. The section layout matches
// <!-- landing-zone-plan-gcp -->.

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

function planHtml(body, limit) {
  const clipped = truncate(redact(body), limit);
  let escaped = escapeHtml(clipped);
  if (escaped.length > limit) escaped = truncate(escaped, limit);
  return escaped;
}

function detailsBlock(summary, body, limit) {
  return [
    "<details>",
    `<summary>${escapeHtml(summary)}</summary>`,
    "",
    `<pre><code>${planHtml(body, limit)}</code></pre>`,
    "</details>",
  ].join("\n");
}

function walkTxt(dir, found) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkTxt(full, found);
    else if (entry.isFile() && entry.name.endsWith(".txt")) found.push(full);
  }
}

function planSummaryLine(text) {
  const plan = text.match(/^Plan:\s+\d+\s+to add,\s+\d+\s+to change,\s+\d+\s+to destroy\.?\s*$/m);
  if (plan) return plan[0].trim();
  const none = text.match(/^No changes\..+$/m);
  if (none) return none[0].trim();
  return "";
}

function sectionsUnder(dir) {
  if (!dir || !fs.existsSync(dir)) return [];
  const files = [];
  walkTxt(dir, files);
  files.sort();
  return files.map((file) => {
    const raw = stripAnsi(fs.readFileSync(file, "utf8").slice(0, 80000));
    const name = path.basename(file, ".txt");
    const summaryLine = planSummaryLine(raw);
    return {
      summary: summaryLine ? `${name}: ${summaryLine}` : name,
      body: raw.trim() ? raw : "(no output)",
    };
  });
}

function render(marker, header, sections) {
  const wrapper = (summary) =>
    `<details>\n<summary>${escapeHtml(summary)}</summary>\n\n<pre><code></code></pre>\n</details>\n\n`.length;
  let overhead = marker.length + 1 + header.length + 2;
  for (const section of sections) overhead += wrapper(section.summary);
  const per =
    sections.length === 0
      ? MAX_PLAN
      : Math.max(2000, Math.min(MAX_PLAN, Math.floor((MAX_COMMENT - overhead) / sections.length)));
  const blocks = sections.map((section) => detailsBlock(section.summary, section.body, per));
  let body = `${marker}\n${header}`;
  if (blocks.length) body += `\n\n${blocks.join("\n\n")}`;
  if (body.length > MAX_COMMENT && sections.length) {
    const overflow = body.length - MAX_COMMENT;
    const tighter = Math.max(500, per - Math.ceil(overflow / sections.length) - 80);
    const again = sections.map((section) => detailsBlock(section.summary, section.body, tighter));
    body = `${marker}\n${header}\n\n${again.join("\n\n")}`;
  }
  if (body.length > MAX_COMMENT) {
    body = `${body.slice(0, MAX_COMMENT - 28)}\n… comment truncated`;
  }
  return body;
}

function headerFor(result) {
  const value = result || "unknown";
  return (
    "## Terraform plan (GCP mock)\n\n" +
    "This is a mock plan. It uses no cloud credentials and it is not a live apply. " +
    "The matrix matches the real GCP config list. " +
    "AWS calls go to Cloud Custodian's pinned Moto, and Compute calls go to a loopback URL. " +
    `Job \`terraform-plan-gcp-mock\` result: \`${value}\`.`
  );
}

function buildGcpMockPlanComment({ dir, result } = {}) {
  const sections = sectionsUnder(dir);
  let header = headerFor(result);
  if (sections.length === 0) {
    header += "\n\nThe GCP mock plan job did not upload plan output.";
  }
  return render(MARKER, header, sections);
}

function resolvePlanDir() {
  const root = process.env.GITHUB_WORKSPACE || process.cwd();
  const given = process.env.PLAN_DIR;
  if (!given) return path.join(root, "plans", "gcp-mock");
  return path.isAbsolute(given) ? given : path.resolve(root, given);
}

async function postGcpMockPlanComment({ github, context, core }) {
  const dir = resolvePlanDir();
  const result = process.env.PLAN_RESULT || process.env.PLAN_OUTCOME || "unknown";
  const body = buildGcpMockPlanComment({ dir, result });
  if (core) core.info(`GCP mock plan comment for ${result} from ${dir}`);

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
  redact,
  sectionsUnder,
};
