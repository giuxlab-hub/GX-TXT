"""Private filesystem transaction for CORE New Experiment; no scientific logic."""
import os
import shutil
import sys
from pathlib import Path

def main():
    mode, stage_s, target_s = sys.argv[1:]
    stage, target = Path(stage_s), Path(target_s)
    if mode == 'reserve':
        # mkdir is an exclusive reservation; a collision cannot become a nested
        # copy or an overwrite, including the interval between validation/commit.
        target.mkdir()
        try:
            stage.mkdir()
        except BaseException:
            target.rmdir()
            raise
    elif mode == 'commit':
        if target.is_symlink() or list(target.iterdir()):
            raise RuntimeError('New Experiment destination changed during creation')
        os.replace(stage, target)
    elif mode == 'abort':
        shutil.rmtree(stage, ignore_errors=True)
        # Never delete somebody else's files in a changed reservation.
        try:
            target.rmdir()
        except (FileNotFoundError, OSError):
            pass
    else:
        raise ValueError(mode)

if __name__ == '__main__':
    main()
