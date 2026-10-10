"""Create an installable RBZ using only Python's standard library."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
src = root / "src"
target = root / "dist" / "buildable-envelope-0.1.3.rbz"
target.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(target, "w", ZIP_DEFLATED) as archive:
    for path in sorted(src.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(src).as_posix())
with ZipFile(target) as archive:
    assert archive.testzip() is None
    assert "buildable_envelope.rb" in archive.namelist()
    assert "buildable_envelope/main.rb" in archive.namelist()
    assert "buildable_envelope/ui.html" in archive.namelist()
print(target)
