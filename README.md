# Customer Enablement Hub (Community Repo)

Welcome! 👋
This repository is a community-driven collection of **useful enablement resources** I use and share with customers—things like:

* 📊 Dashboards / dashboarding references
* 🧭 Tutorials and step-by-step guides
* 📚 Documentation, notes, and quick references
* 🧰 Tools, scripts, templates, and examples
* ✅ Best practices, runbooks, and checklists

The goal: **make it easy for customers (and the wider community) to learn, reuse, and contribute back**.

---

## Who this repo is for

* Customers looking for practical enablement materials
* Community members who want to share improvements or new content
* Folks who want a central place to collaborate on reusable knowledge

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
3. Reuse/modify resources for your environment.
4. If you improve something, please contribute back 🙌

---

# Contribution Instructions

We welcome contributions from the community! 🚀
This is an **open community repository**, and contributions are highly encouraged.

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
git checkout -b feature/add-openshift-dashboard-guide
```

---

### Step 2 — Implement Your Changes

* Add or update content in the relevant folder(s).
* Ensure documentation is clear and easy to follow.
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
* Do not include credentials, tokens, private URLs, or customer-specific data.
* Keep screenshots relevant and optimized for size.
* Specify version dependencies when applicable.

---

# Community Expectations

This repository is built on collaboration and shared learning.

Please:

* Be respectful and constructive
* Keep contributions practical and reusable
* Maintain clarity and quality in documentation

---

# Support and Contact

If you have questions, suggestions, or would like contributor access, please contact me directly if you have my details.

Thank you for helping improve this knowledge hub for the community! 🙏
