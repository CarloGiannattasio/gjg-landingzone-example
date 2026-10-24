"use strict";

// One sticky pull-request comment for every plan in the run.
// Marker: <!-- landing-zone-plans -->
// pipeline calls postPlanTable only for pull_request events.
// The body is a table: plan, account, add, change, destroy.
// Push to main and workflow_dispatch do not call this script.

const fs = require("fs");
const path = require("path");

const MARKER = "<!-- landing-zone-plans -->";
const OLD_MARKERS = [
  "<!-- landing-zone-plan -->",
  "<!-- landing-zone-plan-real -->",
  "<!-- landing-zone-plan-gcp -->",
  "<!-- landing-zone-plan-gcp-mock -->",
];

const GROUPS = [
  {
    plan: "Moto",
    prefix: "plan-moto",
    accountsKey: "AWS_ACCOUNTS",
    resultKey: "MOTO_RESULT",
    configuredKey: "",
  },
  {
    plan: "Real AWS",
    prefix: "plan-real",
    accountsKey: "AWS_ACCOUNTS",
    resultKey: "AWS_PLAN_RESULT",
    configuredKey: "AWS_CONFIGURED",
  },
  {
    plan: "GCP mock",
    prefix: "plan-gcp-mock",
    accountsKey: "GCP_ACCOUNTS",
    resultKey: "GCP_MOCK_RESULT",
    configuredKey: "",
  },
  {
    plan: "Real GCP",
    prefix: "plan-gcp",
    accountsKey: "GCP_ACCOUNTS",
    resultKey: "GCP_PLAN_RESULT",
    configuredKey: "GCP_CONFIGURED",
  },
];

function stripAnsi(text) {
  return String(text)
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g, "");
}

function listCsv(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function walkTxt(dir, found) {
  if (!dir || !fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkTxt(full, found);
    else if (entry.isFile() && entry.name.endsWith(".txt")) found.push(full);
  }
}

function groupOf(file) {
  const parts = file.split(path.sep);
  // plan-gcp-mock must win over plan-gcp.
  const ordered = ["plan-gcp-mock", "plan-moto", "plan-real", "plan-gcp"];
  for (const prefix of ordered) {
    if (parts.some((part) => part === prefix || part.startsWith(`${prefix}-`))) {
      return GROUPS.find((group) => group.prefix === prefix);
    }
  }
  return null;
}

function countsFrom(text) {
  const plan = text.match(/^Plan:\s+(\d+)\s+to add,\s+(\d+)\s+to change,\s+(\d+)\s+to destroy\.?\s*$/m);
  if (plan) return { add: plan[1], change: plan[2], destroy: plan[3] };
  if (/^No changes\./m.test(text)) return { add: "0", change: "0", destroy: "0" };
  return null;
}

function cell(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\n/g, " ");
}

function skipped(group, env) {
  if (!group.configuredKey) return false;
  return env[group.configuredKey] !== "true" || env[group.resultKey] === "skipped";
}

function rowsFor(group, files, env) {
  const expected = listCsv(env[group.accountsKey]);
  const byAccount = new Map();
  for (const file of files) {
    const account = path.basename(file, ".txt");
    const raw = stripAnsi(fs.readFileSync(file, "utf8").slice(0, 80000));
    const counts = countsFrom(raw);
    const previous = byAccount.get(account);
    if (!previous || (!previous.counts && counts)) byAccount.set(account, { counts });
  }

  const names = expected.slice();
  for (const account of [...byAccount.keys()].sort()) {
    if (!names.includes(account)) names.push(account);
  }
  if (names.length === 0) names.push("(none)");

  const isSkipped = skipped(group, env);
  const result = env[group.resultKey] || "unknown";
  return names.map((account) => {
    if (isSkipped) return { plan: group.plan, account, add: "skipped", change: "skipped", destroy: "skipped" };
    const found = byAccount.get(account);
    if (found && found.counts) {
      return { plan: group.plan, account, ...found.counts };
    }
    const label = result === "success" ? "no output" : result;
    return { plan: group.plan, account, add: label, change: label, destroy: label };
  });
}

function notesFor(env) {
  const notes = [];
  if (env.AWS_CONFIGURED !== "true") {
    notes.push("Real AWS was skipped because AWS plan secrets are unset.");
  } else if (env.AWS_PLAN_RESULT && env.AWS_PLAN_RESULT !== "success") {
    notes.push(`Real AWS job result: \`${env.AWS_PLAN_RESULT}\`.`);
  }
  if (env.GCP_CONFIGURED !== "true") {
    const gcp = env.GCP_MODE || "unset";
    const aws = env.AWS_MODE || "unset";
    if (gcp === "unset" && aws === "unset") {
      notes.push("Real GCP was skipped because GCP credentials and AWS plan secrets are unset.");
    } else if (gcp === "unset") {
      notes.push("Real GCP was skipped because GCP credentials are unset.");
    } else if (aws === "unset") {
      notes.push("Real GCP was skipped because AWS plan secrets are unset.");
    } else {
      notes.push("Real GCP was skipped.");
    }
  } else if (env.GCP_PLAN_RESULT && env.GCP_PLAN_RESULT !== "success") {
    notes.push(`Real GCP job result: \`${env.GCP_PLAN_RESULT}\`.`);
  }
  if (env.MOTO_RESULT && env.MOTO_RESULT !== "success") {
    notes.push(`Moto job result: \`${env.MOTO_RESULT}\`.`);
  }
  if (env.GCP_MOCK_RESULT && env.GCP_MOCK_RESULT !== "success") {
    notes.push(`GCP mock job result: \`${env.GCP_MOCK_RESULT}\`.`);
  }
  return notes;
}

function buildPlanComment({ root, env }) {
  const files = [];
  walkTxt(root, files);
  const grouped = new Map(GROUPS.map((group) => [group.prefix, []]));
  for (const file of files) {
    const group = groupOf(file);
    if (group) grouped.get(group.prefix).push(file);
  }

  const rows = GROUPS.flatMap((group) => rowsFor(group, grouped.get(group.prefix), env));
  const table = [
    "| Plan | Account | Add | Change | Destroy |",
    "| --- | --- | ---: | ---: | ---: |",
    ...rows.map(
      (row) =>
        `| ${cell(row.plan)} | ${cell(row.account)} | ${cell(row.add)} | ${cell(row.change)} | ${cell(row.destroy)} |`
    ),
  ].join("\n");

  const header = [
    MARKER,
    "## Terraform plans",
    "",
    "Each row is one plan for one account. Add, change, and destroy come from that plan's summary. Destroy is the delete count. This run does not apply. Mock plans use no cloud credentials. Full logs stay in the workflow artifacts.",
  ].join("\n");

  const notes = notesFor(env);
  let body = `${header}\n\n${table}`;
  if (notes.length) body += `\n\n${notes.join(" ")}`;
  body += "\n\nSecret values are not printed.";
  return body;
}

function envFromProcess() {
  return {
    AWS_ACCOUNTS: process.env.AWS_ACCOUNTS || "",
    GCP_ACCOUNTS: process.env.GCP_ACCOUNTS || "",
    MOTO_RESULT: process.env.MOTO_RESULT || "",
    AWS_PLAN_RESULT: process.env.AWS_PLAN_RESULT || "",
    AWS_CONFIGURED: process.env.AWS_CONFIGURED || "",
    GCP_MOCK_RESULT: process.env.GCP_MOCK_RESULT || "",
    GCP_PLAN_RESULT: process.env.GCP_PLAN_RESULT || "",
    GCP_CONFIGURED: process.env.GCP_CONFIGURED || "",
    GCP_MODE: process.env.GCP_MODE || "",
    AWS_MODE: process.env.AWS_MODE || "",
  };
}

function resolvePlanRoot() {
  const root = process.env.GITHUB_WORKSPACE || process.cwd();
  const given = process.env.PLAN_ROOT;
  if (!given) return path.join(root, "plans");
  return path.isAbsolute(given) ? given : path.resolve(root, given);
}

async function postPlanTable({ github, context, core }) {
  const body = buildPlanComment({ root: resolvePlanRoot(), env: envFromProcess() });
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
    if (core) core.info(`Updated plans table ${existing.id}`);
  } else {
    const created = await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: context.issue.number,
      body,
    });
    if (core) core.info(`Created plans table ${created.data.id}`);
  }

  for (const comment of comments) {
    if (typeof comment.body !== "string") continue;
    if (comment.body.startsWith(MARKER)) continue;
    const stale = OLD_MARKERS.some((marker) => comment.body.startsWith(marker));
    if (!stale) continue;
    try {
      await github.rest.issues.deleteComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        comment_id: comment.id,
      });
      if (core) core.info(`Removed previous plan comment ${comment.id}`);
    } catch (error) {
      if (core) core.warning(`Could not remove previous plan comment ${comment.id}: ${error.message}`);
    }
  }
}

module.exports = {
  MARKER,
  OLD_MARKERS,
  buildPlanComment,
  postPlanTable,
  countsFrom,
};
