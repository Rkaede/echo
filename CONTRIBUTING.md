## Releases

### Prerequisites

Add missing rust by running either `rustup target add x86_64-apple-darwin` or `rustup target add aarch64-apple-darwin`

### Steps

1. Update the version number in`package.json` and `tauri.conf.json`.
2. Update & commit the changelog. The commit message should be `Echo@<version>`.
3. Run `pnpm run release`.
4. Create the release on GitHub and upload the binaries (located in `src-tauri/target/[arch]/release/bundle/dmg`).
