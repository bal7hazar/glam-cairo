import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "affected.py"
SPEC = importlib.util.spec_from_file_location("affected", SCRIPT)
affected = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(affected)


class AffectedTests(unittest.TestCase):
    targets = ["test_mat3", "test_quat", "test_vec2", "test_vec3", "test_vec4"]
    files = {
        "test_mat3.cairo": "test_mat3",
        "golden_mat3.cairo": "test_mat3",
        "test_quat.cairo": "test_quat",
        "golden_quat.cairo": "test_quat",
        "test_vec2.cairo": "test_vec2",
        "golden_vec2.cairo": "test_vec2",
        "test_vec3.cairo": "test_vec3",
        "golden_vec3.cairo": "test_vec3",
        "test_vec4.cairo": "test_vec4",
        "golden_vec4.cairo": "test_vec4",
    }
    reverse = {"vec2": {"vec3"}, "vec3": {"mat3"}}
    modules = {"mat3", "quat", "vec2", "vec3", "vec4"}
    benches = modules

    def plan(self, *paths):
        return affected.plan_paths(
            list(paths), self.targets, self.files, self.reverse, self.modules, self.benches
        )

    def test_table(self):
        cases = [
            (("docs/DESIGN.md", "README.md"), False, True, [], []),
            (
                ("packages/glam/src/vec2.cairo",),
                False,
                False,
                ["test_mat3", "test_vec2", "test_vec3"],
                ["mat3", "vec2", "vec3"],
            ),
            (("packages/glam/tests/test_vec2.cairo",), False, False, ["test_vec2"], []),
            (("packages/benches/tests/bench_vec3.cairo",), False, False, [], ["vec3"]),
            (
                ("tools/codegen/fvec_tests.py",),
                False,
                False,
                ["test_vec2", "test_vec3", "test_vec4"],
                ["vec2", "vec3", "vec4"],
            ),
            (("tools/refgen/specs/quat.toml",), False, False, ["test_quat"], []),
            (
                ("packages/glam/Scarb.toml",),
                True,
                False,
                self.targets,
                sorted(self.benches),
            ),
            (("unknown.file",), True, False, self.targets, sorted(self.benches)),
        ]
        for paths, all_, docs_only, tests, benches in cases:
            with self.subTest(paths=paths):
                plan = self.plan(*paths)
                self.assertEqual((plan.all, plan.docs_only), (all_, docs_only))
                self.assertEqual(plan.tests, tests)
                self.assertEqual(plan.benches, benches)

    def test_target_index_pairs_wrapper_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "tests"
            tests.mkdir()
            (tests / "target_vec2.cairo").write_text(
                '#[path("golden_vec2.cairo")]\nmod golden_vec2;\n'
                '#[path("test_vec2.cairo")]\nmod test_vec2;\n'
            )
            (tests / "test_vec2.cairo").write_text("// test\n")
            (tests / "golden_vec2.cairo").write_text("// golden\n")
            manifest = root / "Scarb.toml"
            manifest.write_text(
                '[[test]]\nname = "test_vec2"\nsource-path = "tests/target_vec2.cairo"\n'
                'test-type = "integration"\n'
            )
            targets, files = affected.target_index(manifest, tests)
            self.assertEqual(targets, ["test_vec2"])
            self.assertEqual(
                files,
                {"golden_vec2.cairo": "test_vec2", "test_vec2.cairo": "test_vec2"},
            )


if __name__ == "__main__":
    unittest.main()
