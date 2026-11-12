"""No game assets: a rejected input must remain byte-identical."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("scene", Path(__file__).resolve().parents[1] / "tools/patch_scene.py")
scene = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scene)


class ScenePatchTests(unittest.TestCase):
    def test_unrecognized_image_is_untouched(self):
        with tempfile.TemporaryDirectory() as root:
            image = Path(root) / "image.bin"
            original = b"This is deliberately not a supported game image."
            image.write_bytes(original)
            with self.assertRaisesRegex(ValueError, "Unsupported image"):
                scene.patch(image)
            self.assertEqual(image.read_bytes(), original)
            self.assertEqual([p.name for p in Path(root).iterdir()], ["image.bin"])

    def test_missing_image_does_not_create_an_output(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(FileNotFoundError):
                scene.patch(Path(root) / "missing.bin")
            self.assertEqual(list(Path(root).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
