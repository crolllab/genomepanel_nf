# Release checklist

1. **Bump version** in `CITATION.cff` and `nextflow.config` (`manifest.version`).
2. **Update docs** — add a section to `docs/changelog.md` and `docs/index.md` (Release notes).
3. **Commit & tag** on `dev-version`:
   ```bash
   git add <files>
   git commit -m "Release vX.Y.Z"
   git tag vX.Y.Z
   git push origin dev-version
   git push origin vX.Y.Z
   ```
4. **Merge `dev-version` into `main`** — required to trigger the GitHub Pages rebuild:
   ```bash
   git checkout main
   git merge --ff-only dev-version
   git push origin main
   git checkout dev-version
   ```
5. **Create the GitHub release** (triggers Zenodo archival and the `update-latest-tag` workflow):
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."
   ```
6. **Verify** with `gh run list --limit 5` — expect two green runs: *Deploy docs* and *Update latest tag*.
