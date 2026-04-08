"""
llm_backend.py - Pluggable LLM backends for the verification agent.

Supports:
- Codex CLI through a local `codex exec` command
"""

from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path


class LLMBackend:
    """Shared interface for text generation backends."""

    def complete(
        self,
        system_prompt: str,
        user_content: str,
        temperature: float = 0.2,
        want_json: bool = True,
    ) -> str:
        raise NotImplementedError


class CodexCLIBackend(LLMBackend):
    """Local Codex CLI backend using a non-interactive `codex exec` command."""

    def __init__(self, model: str | None, cwd: str | None = None, timeout_seconds: int = 180):
        self.model = model or os.environ.get("CODEX_MODEL")
        self.cwd = cwd or str(Path(__file__).parent)
        self.timeout_seconds = int(os.environ.get("CODEX_TIMEOUT_SECONDS", timeout_seconds))
        self.base_command = self._resolve_base_command()

    def _resolve_base_command(self) -> list[str]:
        command_text = os.environ.get("CODEX_CLI_COMMAND", "codex exec")
        return shlex.split(command_text, posix=False)

    def _build_prompt(self, system_prompt: str, user_content: str, want_json: bool) -> str:
        prompt = (
            f"{system_prompt}\n\n"
            f"User request:\n{user_content}\n"
        )
        if want_json:
            prompt += "\nReturn valid JSON only. Do not wrap it in markdown."
        return prompt

    def complete(
        self,
        system_prompt: str,
        user_content: str,
        temperature: float = 0.2,
        want_json: bool = True,
    ) -> str:
        del temperature

        prompt = self._build_prompt(system_prompt, user_content, want_json)
        command = list(self.base_command)

        if self.model and "--model" not in command:
            command.extend(["--model", self.model])

        command.append(prompt)

        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                cwd=self.cwd,
                timeout=self.timeout_seconds,
            )
        except FileNotFoundError as exc:
            raise RuntimeError(
                "Codex CLI was not found. Install it or set CODEX_CLI_COMMAND to the right launcher."
            ) from exc
        except PermissionError as exc:
            raise RuntimeError(
                "Codex CLI exists but could not be launched on this machine (permission denied). "
                "On Windows, try running through WSL or a shell where `codex exec` works."
            ) from exc
        except OSError as exc:
            if getattr(exc, "winerror", None) == 5:
                raise RuntimeError(
                    "Codex CLI launch was blocked with Windows access denied. "
                    "Set CODEX_CLI_COMMAND to a working launcher, such as a WSL-based command."
                ) from exc
            raise
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                f"Codex CLI timed out after {self.timeout_seconds}s. "
                "Increase CODEX_TIMEOUT_SECONDS or reduce prompt size."
            ) from exc

        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            detail = stderr or stdout or f"exit code {result.returncode}"
            raise RuntimeError(f"Codex CLI request failed: {detail}")

        output = (result.stdout or "").strip()
        if not output:
            raise RuntimeError("Codex CLI returned no output.")
        return output


def get_default_provider() -> str:
    """Return the default LLM provider name."""
    return "codex-cli"


def get_default_model(provider: str) -> str | None:
    """Return the default model for the selected provider."""
    del provider
    return os.environ.get("CODEX_MODEL")


def create_backend(provider: str, model: str | None = None, cwd: str | None = None) -> LLMBackend:
    """Construct an LLM backend from CLI/env configuration."""
    normalized = provider.strip().lower()
    if normalized == "codex-cli":
        return CodexCLIBackend(model or get_default_model("codex-cli"), cwd=cwd)
    raise ValueError(f"Unsupported provider: {provider}")
