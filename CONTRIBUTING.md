## Releases

### Prerequisites

Add missing rust targets by running either `rustup target add x86_64-apple-darwin` or `rustup target add aarch64-apple-darwin`

Please note that this should be automated in the future if the app gets more traction.

### Update version

1. Update the version number in`package.json` and `tauri.conf.json`.
2. Run `pnpm run release`.
3. Install the release (`src-tauri/target/[arch]/release/bundle/dmg`) and test.
4. Update the changelog.
5. Commit the updated changelog and json files. The commit message should be `Echo@<version>`.
6. Create the release on GitHub and upload the binaries.

## Testing

1. Delete existing `~/Library/Application Support/io.littlecove.echo` folder.
2. Run `pnpm run tauri build` and copy the app to the `Applications` folder.
3. Perform the test cases below.

#### Sound

- Turn off sound
- Enable sound
- Change the sound to "None" for each event
- Change the sound to "Tick" for each event
- Change the volume to 10%
- Change the volume to 100%

#### Startup

- Enable "Start at login" and logout/login
- Disable "Start at login" and logout/login

#### Model

- Download a model
- Delete a model
- Download 2 models at the same time
- Change the model
