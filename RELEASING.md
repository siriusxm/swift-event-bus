# Releasing EventBus

`EventBus` releases are immutable Git tags published through the repository's `Release` workflow. Swift Package Manager resolves those tags directly from the source repository.

## Prepare a release

1. Choose a Semantic Versioning tag without a `v` prefix, such as `1.0.0-beta.1` or `1.0.0`.
2. Add `Documentation/Releases/<version>.md` with the GitHub release notes.
3. Update `RELEASES.md` so the current supported prerelease, stable release, and previous-version table are accurate.
4. Update the README and website installation snippets when the recommended version changes.
5. Refresh the GitHub line anchors in DocC links to test examples. From the repository root, run:

   ```bash
   ruby scripts/update_docc_test_links.rb
   ```

   Commit any resulting documentation changes. CI and the `Release` workflow run the same script with `--check` and fail if committed anchors are stale.

6. Push or update the release-preparation pull request and wait for CI and Pages validation to pass.
7. Run the `Release` workflow manually from the release-preparation branch, entering the planned version. Confirm that its validation, release build, and tests pass without publishing.
8. Merge the release-preparation pull request into `main`.

## Publish a release

After the release-preparation pull request and dry run pass, tag the reviewed commit on `main` and push the tag:

```bash
git switch main
git pull --ff-only origin main
git tag -a 1.0.0-beta.1 -m "EventBus 1.0.0-beta.1"
git push origin 1.0.0-beta.1
```

The `Release` workflow validates the tag format, requires the matching release-notes file, builds the release configuration, runs the tests, and creates the GitHub release. Tags containing a prerelease suffix, such as `-beta.1`, are automatically marked as prereleases.

If validation fails, correct the release-preparation commit and use a new version tag. Do not move or replace a published release tag.

## Release channels

- Stable releases use tags such as `1.0.0` and are the default recommendation after stable availability begins.
- Supported prereleases use tags such as `1.0.0-beta.1` and are installed with an exact SwiftPM requirement.
- Tip-of-tree consumers follow `main` at their own risk and are unsupported.
- Prior tags remain available for back-revision consumers; their support status is maintained in `RELEASES.md`.
