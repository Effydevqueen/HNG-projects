A simple, low‑cost, open‑sourced deployment that lets developers run one command from the Claude Code CLI and have code live at https://backend.im

Using Git as the canonical source of truth, a lightweight build step that produces a container image (or uses Buildpacks to avoid an explicit Dockerfile), a single Linux VM running Docker + a reverse proxy (Traefik or Caddy) to serve HTTPS, and a tiny deploy hook on the VM that pulls the new image and restarts the service.
For the “one‑command” experience: the Claude Code CLI pushes code to the repository (or opens a PR) and triggers CI (GitHub Actions or a small self‑hosted runner) which builds and pushes the image, then calls the server to deploy (over an authenticated webhook or SSH). The CLI can hide these steps behind a single command.
Minimal custom code: a deploy.sh on the server (pull image, recreate service), a very small GitHub Actions workflow (or Drone/Drone runner), and a one‑line Claude CLI action mapping.


For the “one‑command” experience: the Claude Code CLI pushes code to the repository (or opens a PR) and triggers CI (GitHub Actions or a small self‑hosted runner) which builds and pushes the image, then calls the server to deploy (over an authenticated webhook or SSH). The CLI can hide these steps behind a single command.
Minimal custom code: a deploy.sh on the server (pull image, recreate service), a very small GitHub Actions workflow (or Drone/Drone runner), and a one‑line Claude CLI action mapping.
