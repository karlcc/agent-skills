import importlib.util
import tempfile
import unittest
from pathlib import Path


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


INIT_MODULE = _load_module(
    "obsidian_init_local_vault",
    "/Users/karlchow/Documents/obsidian_vault/agent-skills/skills/obsidian-gh-knowledge/scripts/init_local_vault.py",
)
LOCAL_MODULE = _load_module(
    "obsidian_local_knowledge",
    "/Users/karlchow/Documents/obsidian_vault/agent-skills/skills/obsidian-gh-knowledge/scripts/local_obsidian_knowledge.py",
)


class InitLocalVaultTests(unittest.TestCase):
    def test_relative_submodule_path_accepts_simple_path(self):
        self.assertEqual(INIT_MODULE._relative_submodule_path("raw"), "raw")
        self.assertEqual(INIT_MODULE._relative_submodule_path("raw/inbox"), "raw/inbox")

    def test_relative_submodule_path_rejects_parent_traversal(self):
        with self.assertRaises(SystemExit):
            INIT_MODULE._relative_submodule_path("../raw")


class CaptureRawNoteTests(unittest.TestCase):
    def test_capture_raw_note_writes_markdown_inside_raw_submodule(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "raw" / "inbox").mkdir(parents=True)

            LOCAL_MODULE._capture_raw_note(
                vault_dir,
                title="Example Source",
                folder="raw/inbox",
                name=None,
                body="Copied source content.",
                source="https://example.com/post",
                extension="md",
                overwrite=False,
                dry_run=False,
            )

            created = vault_dir / "raw" / "inbox" / "example-source.md"
            self.assertTrue(created.exists())
            content = created.read_text(encoding="utf-8")
            self.assertIn("# Example Source", content)
            self.assertIn("Source: https://example.com/post", content)
            self.assertIn("Copied source content.", content)

    def test_capture_raw_note_rejects_non_raw_destination(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_dir = Path(tmpdir)
            (vault_dir / "0️⃣-Inbox").mkdir(parents=True)

            with self.assertRaises(SystemExit):
                LOCAL_MODULE._capture_raw_note(
                    vault_dir,
                    title="Bad Target",
                    folder="0️⃣-Inbox",
                    name=None,
                    body="Should fail.",
                    source=None,
                    extension="md",
                    overwrite=False,
                    dry_run=False,
                )


if __name__ == "__main__":
    unittest.main()
