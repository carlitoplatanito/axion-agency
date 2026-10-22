# Contributing to Axiom Agency

Thank you for contributing! This document provides guidelines and setup instructions for working on the project.

## 🐛 Decentralized Issue Tracking (`git-bug`)

We use [`git-bug`](https://github.com/git-bug/git-bug) for embedded, distributed, and offline-first issue tracking natively inside Git. Issues are stored as Git objects under `refs/bugs/` without polluting branch histories or working trees.

### 1. Developer Tool Installation

Install `git-bug` using Go or download a pre-built binary:

```bash
# Build directly from source
go install github.com/git-bug/git-bug@latest
export PATH="$HOME/go/bin:$PATH"

# Verify installation
git bug version
```

### 2. Identity Initialization

Create your `git-bug` identity resolved from your Git configuration (`user.name` and `user.email`):

```bash
git bug user new -n "$(git config user.name)" -e "$(git config user.email)"
```

Confirm identity resolution:

```bash
git bug user
```

### 3. Git Remote Configuration

Ensure bug refspecs are configured in `.git/config` for automatic syncing:

```ini
[remote "origin"]
    fetch = +refs/bugs/*:refs/bugs/*
    push = +refs/bugs/*:refs/bugs/*
```

Or configure via CLI:

```bash
git config --add remote.origin.fetch "+refs/bugs/*:refs/bugs/*"
git config --add remote.origin.push "+refs/bugs/*:refs/bugs/*"
```

Verify sync commands:

```bash
git bug push origin
git bug pull origin
```

### 4. Git Hooks & Workflow Automation

Automated pull and push hooks are provided in `.githooks/`. Activate them locally using:

```bash
git config core.hooksPath .githooks
# or run project setup:
mise run setup
```

- **post-merge hook**: Automatically pulls latest bug state after merging.
- **pre-push hook**: Automatically pushes local bug updates when pushing commits.

### 5. Core Issue Tracking Commands

- **Create a new issue**:
  ```bash
  git bug bug new -t "Issue Title" -m "Detailed issue description"
  # or interactively: git bug new
  ```
- **List issues**:
  ```bash
  git bug bug
  # or git bug ls
  ```
- **Add comment to an issue**:
  ```bash
  git bug bug comment new <issue-id> -m "Updating issue status"
  # or git bug comment <id>
  ```
- **View issue details**:
  ```bash
  git bug bug show <issue-id>
  ```
- **Launch Web Interface**:
  ```bash
  git bug webui
  ```
  Spins up the interactive web UI (default `http://localhost:3000`) for visual triage and management.
