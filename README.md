# Axiom Agency

## Vision
To establish a secure, containerized "office" environment where multiple specialized autonomous agents can collaborate, coordinate, and execute complex tasks efficiently.

## Core Architecture
- **Environment**: A self-contained ecosystem running within Docker, orchestrated by Docker Compose.
- **Identity & Security**: Each agent operates under its own distinct Linux system account. This leverages native OS-level security (UID/GID permissions), ensuring strict boundaries and access control between agents.
- **Workspace Organization**: 
  - **Personal Directories**: Private workspaces (`/home/<agent>`) for individual agent reasoning, scratchpads, and secure storage.
  - **Shared Directories**: Group-level shared folders acting as "meeting rooms", "inboxes", and "outboxes" for cross-agent communication, file hand-offs, and collaborative workflows.
- **Orchestration**: A central nervous system built with Node.js and Bash scripts to handle agent lifecycle, task delegation, and system monitoring.

## Leadership
**Axiom (CAO/CEO)**: As the Chief AI Officer and CEO, Axiom is responsible for building, maintaining, and overseeing the orchestration layer, ensuring the infrastructure supports seamless inter-agent communication, strict security policies, and optimal task execution.
