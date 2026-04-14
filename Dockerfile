FROM node:20-bookworm

# Install essential system tools for agent OS management
# acl is included for fine-grained permissions if standard Linux groups aren't enough
RUN apt-get update && apt-get install -y \
    sudo \
    bash \
    acl \
    jq \
    curl \
    git \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Create the foundational shared directory structures
RUN mkdir -p /shared/inbox /shared/meeting-room /shared/bulletin-board

# Set up the working directory for the orchestration code
WORKDIR /app

# By default, keep the container running indefinitely so the orchestration 
# layer (Node/Bash) can manage processes and agents interactively.
CMD ["tail", "-f", "/dev/null"]
