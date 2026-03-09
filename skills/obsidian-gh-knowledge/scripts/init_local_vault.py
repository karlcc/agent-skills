#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


CONFIG_PATH = Path("~/.config/obsidian-gh-knowledge/config.json").expanduser()


def _expand_path(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path)))


def _display_path(path: str) -> str:
    home = str(Path.home())
    normalized = os.path.abspath(path)
    if normalized == home:
        return "~"
    if normalized.startswith(home + os.sep):
        return "~/" + os.path.relpath(normalized, home)
    return normalized


def _die(message: str, exit_code: int = 2) -> None:
    print(message, file=sys.stderr)
    sys.exit(exit_code)


def _run(cmd: list[str], *, cwd: str | None = None) -> None:
    try:
        subprocess.run(cmd, cwd=cwd, capture_output=True, check=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        details = "\n".join(part for part in [stdout, stderr] if part)
        message = f"Command failed ({exc.returncode}): {' '.join(cmd)}"
        if details:
            message = f"{message}\n{details}"
        _die(message, exit_code=exc.returncode)


def _run_capture(cmd: list[str], *, cwd: str) -> str:
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, check=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        details = "\n".join(part for part in [stdout, stderr] if part)
        message = f"Command failed ({exc.returncode}): {' '.join(cmd)}"
        if details:
            message = f"{message}\n{details}"
        _die(message, exit_code=exc.returncode)
    return result.stdout.strip()


def _parse_repo_url(repo_url: str) -> tuple[str, str]:
    candidate = repo_url.strip()
    if not candidate:
        _die("Missing repo URL.")

    if candidate.startswith("git@github.com:"):
        path = candidate.split(":", 1)[1]
    elif "://" in candidate:
        parsed = urlparse(candidate)
        if parsed.netloc.lower() != "github.com":
            _die(f"Only github.com repo URLs are supported for bootstrap: {repo_url}")
        path = parsed.path
    else:
        path = candidate

    path = path.strip().strip("/")
    if path.endswith(".git"):
        path = path[:-4]

    parts = [part for part in path.split("/") if part]
    if len(parts) != 2:
        _die(
            "Repo must be in one of these forms: https://github.com/<owner>/<repo>, "
            "git@github.com:<owner>/<repo>.git, or <owner>/<repo>."
        )
    return parts[0], parts[1]


def _clone_url(owner: str, repo: str, original: str) -> str:
    if "://" in original or original.startswith("git@github.com:"):
        return original
    return f"https://github.com/{owner}/{repo}.git"


def _load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        _die(f"Failed to read config: {CONFIG_PATH}\n{exc}")
    if not isinstance(data, dict):
        _die(f"Config must contain a JSON object: {CONFIG_PATH}")
    return data


def _write_config(config: dict, *, dry_run: bool) -> None:
    if dry_run:
        return
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CONFIG_PATH.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")


def _origin_matches(vault_dir: str, repo_slug: str) -> bool:
    git_dir = os.path.join(vault_dir, ".git")
    if not os.path.isdir(git_dir):
        return False
    origin = _run_capture(["git", "config", "--get", "remote.origin.url"], cwd=vault_dir)
    try:
        owner, repo = _parse_repo_url(origin)
    except SystemExit:
        return False
    return f"{owner.lower()}/{repo.lower()}" == repo_slug.lower()


def _ensure_clone(repo_url: str, repo_slug: str, vault_dir: str, *, dry_run: bool) -> str:
    if os.path.exists(vault_dir) and not os.path.isdir(vault_dir):
        _die(f"Vault path exists but is not a directory: {vault_dir}")

    if os.path.isdir(vault_dir):
        entries = os.listdir(vault_dir)
        if entries:
            if _origin_matches(vault_dir, repo_slug):
                return "reuse"
            _die(
                "Vault directory already exists and is not an empty clone of the confirmed repo:\n"
                f"  {vault_dir}\n"
                "Choose another --vault-dir or clean the directory first."
            )
        if dry_run:
            return "clone"
    else:
        if dry_run:
            return "clone"
        os.makedirs(os.path.dirname(vault_dir), exist_ok=True)

    if shutil.which("git") is None:
        _die("git is required for bootstrap but was not found in PATH.")

    if dry_run:
        return "clone"

    _run(["git", "clone", repo_url, vault_dir])
    return "clone"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Clone a confirmed Obsidian vault repo into ~/Documents and update obsidian-gh-knowledge config."
    )
    parser.add_argument(
        "--repo-url",
        required=True,
        help="Confirmed GitHub repo URL or owner/repo slug for the vault repo.",
    )
    parser.add_argument(
        "--vault-dir",
        default=None,
        help="Destination vault directory. Default: ~/Documents/<repo-name>",
    )
    parser.add_argument(
        "--vault-name",
        default=None,
        help="Optional Obsidian vault name to write to config when missing.",
    )
    parser.add_argument(
        "--repo-key",
        default=None,
        help="Optional repos.<key> alias to store in config.",
    )
    parser.add_argument(
        "--force-default-repo",
        action="store_true",
        help="Overwrite config.default_repo with the confirmed repo.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print planned changes without cloning or writing config.")

    args = parser.parse_args()

    owner, repo = _parse_repo_url(args.repo_url)
    repo_slug = f"{owner}/{repo}"
    clone_url = _clone_url(owner, repo, args.repo_url.strip())
    vault_dir = _expand_path(args.vault_dir or f"~/Documents/{repo}")

    clone_action = _ensure_clone(clone_url, repo_slug, vault_dir, dry_run=args.dry_run)

    config = _load_config()
    config["local_vault_path"] = _display_path(vault_dir)
    config["prefer_local"] = True

    if args.force_default_repo or not isinstance(config.get("default_repo"), str) or not config.get("default_repo"):
        config["default_repo"] = repo_slug

    if args.repo_key:
        repos = config.get("repos")
        if not isinstance(repos, dict):
            repos = {}
        repos[args.repo_key] = repo_slug
        config["repos"] = repos

    if args.vault_name:
        config["vault_name"] = args.vault_name
    elif not isinstance(config.get("vault_name"), str) or not config.get("vault_name"):
        config["vault_name"] = os.path.basename(vault_dir)

    _write_config(config, dry_run=args.dry_run)

    print("Bootstrap plan complete.")
    print(f"Repo: {repo_slug}")
    print(f"Clone URL: {clone_url}")
    print(f"Vault directory: {vault_dir}")
    print(f"Config path: {CONFIG_PATH}")
    print(f"Clone action: {clone_action}")
    if args.dry_run:
        print("Dry run only. No files were changed.")
    else:
        print("Config updated with local_vault_path and prefer_local.")
    print("Next checks:")
    print(f"  cd {vault_dir}")
    print("  command -v obsidian")
    print("  obsidian help")


if __name__ == "__main__":
    main()
