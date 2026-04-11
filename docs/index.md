# OCP (Community Repo)

Welcome! 👋
This repository is a community-driven collection of **useful enablement resources** designed to support **peer engineers, open-source practitioners, and platform communities**—things like:

* 📊 Dashboards / dashboarding references
* 🧭 Tutorials and step-by-step guides
* 📚 Documentation, notes, and quick references
* 🧰 Tools, scripts, templates, and examples
* ✅ Best practices, runbooks, and checklists

The goal: **make it easy for engineers and the open-source community to learn, reuse, collaborate, and contribute back**.

---

## Who This Repo Is For

* Engineers looking for practical enablement materials
* Open-source practitioners who want to share knowledge and improvements
* Platform, DevOps, SRE, and infrastructure teams collaborating on reusable patterns
* Community members who want a central place to exchange operational and technical practices

---

## Repository Structure (Suggested)

> Adjust these folders to match your setup.

* `dashboards/` — Dashboard examples, screenshots, JSON exports, setup notes
* `tutorials/` — Hands-on guides and walkthroughs
* `docs/` — General documentation and references
* `templates/` — Reusable templates (slides, workshop outlines, checklists)
* `scripts/` — Helper scripts and automation
* `CHANGELOG.md` — Change history (required for contributions)

---

## How to Use This Repo

1. Browse folders for topics you need.
2. Follow any README files inside each folder.
3. Reuse and adapt resources for your own environments.
4. If you improve something, please contribute back 🙌

---

# Contribution Instructions

We welcome contributions from peers across the engineering and open-source ecosystem! 🚀
This is an **open community repository**, and knowledge sharing is strongly encouraged.

---

## Contributor Access

* If you **know me personally**, please contact me directly so I can add you as a contributor.
* If you do not know me personally, you can still contribute through Pull Requests.

---

## Contribution Workflow

### Step 1 — Create a Feature Branch

Please create a new branch from `main` using the naming convention below:

```
feature/<branch-name>
```

Example:

```
git checkout main
git pull
git checkout -b feature/<branch-name>
```

---

### Step 2 — Implement Your Changes

* Add or update content in the relevant folder(s).
* Ensure documentation is clear, structured, and reusable.
* Assume readers may be new to the topic.

---

### Step 3 — Update the Change Log (Required)

Before pushing your changes, **you must update the `CHANGELOG.md` file**.

This ensures contributors can track updates, especially when multiple people are editing content simultaneously.

Please include:

* Summary of changes
* Location of change (folder/file)
* Notes or assumptions
* Contributor name or handle (optional)

---

### Step 4 — Push Your Branch

```
git push -u origin feature/<branch-name>
```

---

### Step 5 — Create a Pull Request

* Create a Pull Request from your branch into `main`.
* Please tag **`betterthanbot`** as a reviewer for now.
* Provide a clear description of your changes in the PR.

---

## Pull Request Review and Merge

* PRs will be reviewed before merging.
* If feedback is provided, please update your branch and push changes.
* Once approved, the PR will be merged into `main`.

---

## Release and Tagging Process (After PR Approval)

After your Pull Request has been merged into `main`, please follow these steps:

### Create a Release

1. Create a new GitHub Release.
2. Create a new version tag (example: `v0.1.0`, `v0.2.0`, etc.).
3. Tag the release against the `main` branch.

This means the release tag should reference the latest merged commit in `main`.

---

### Release Notes and Branch Notes

For release notes and branch notes:

* Copy and paste the relevant content directly from `CHANGELOG.md`.
* Ensure release notes accurately reflect what was added, changed, or fixed.

---

# Content Contribution Guidelines

Please follow these best practices:

* Prefer Markdown (`.md`) format for documentation and tutorials.
* Use clear headings, structure, and step-by-step instructions.
* Avoid including sensitive or internal-only information.
* Do not include credentials, tokens, private URLs, or environment-specific secrets.
* Keep screenshots relevant and optimized for size.
* Specify version dependencies when applicable.

---

# Community Culture and Collaboration Principles

This repository is built around open-source engineering culture and peer collaboration.

Please:

* Share knowledge openly and responsibly
* Keep contributions practical and reusable
* Maintain clarity and quality in documentation
* Support and uplift fellow contributors
* Encourage learning and experimentation

---

# Support and Contact

If you have questions, suggestions, or would like contributor access, please contact me directly if you have my details.

Thank you for helping strengthen the shared engineering knowledge community! 🙏
