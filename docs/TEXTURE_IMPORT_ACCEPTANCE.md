# Imported Item Art Acceptance

This check covers the real Files picker handoff, then confirms that imported art survives saving and reopening a project, a revision, and a fresh `.mcaddon` export. XCTest currently checks only that the PNG picker opens and can be cancelled. Selecting a real Files provider item is a manual checkpoint: the app does not expose its private Documents folder to Files, and this flow does not change that privacy setting to make a test fixture visible.

## Prepare the fixture

From the repository root, run:

```sh
python3 scripts/generate-texture-import-fixture.py
```

The script creates `.scratch/Craftberry-Texture-Import-32x32.png`, a 32×32 transparent RGBA sword image below the app's 256 KiB import limit. It uses only the Python standard library and overwrites the same ignored scratch file on every run.

Transfer that PNG to the iPhone with AirDrop. On the phone, choose **Save to Files** and save it to a location visible in the Files picker, such as **On My iPhone** or **iCloud Drive**. Keep the file name unchanged so it is easy to identify.

## Run the iPhone acceptance

Use the Debug app on the calibrated iPhone 13 Pro. Live generation and revision need the local Debug API key from `Config/Secrets.xcconfig`.

1. Launch Craftberry and generate an item with this prompt: “Create a cyan sword with 14 damage and 500 durability, crafted from diamonds.”
2. In the ready project, choose **Import item art**, select the sword, and pick `Craftberry-Texture-Import-32x32.png` from Files. Wait for the build to finish. Confirm the preview now shows the distinctive cyan blade with a gold guard and that the app reports **BUILD COMPLETE**.
3. Tap **Save project.json** and save it to Files as `Craftberry-Texture-Import-project.json`.
4. Tap **Start over**, choose **Open saved project**, and select the saved JSON file. Confirm the imported sword image is still shown.
5. Choose **Revise this add-on**, enter “Increase the sword’s damage to 18,” and apply it. Confirm the revision completes at build version `1.0.2` and the same imported sword image remains visible.
6. Tap **Save .mcaddon** and save the exported artifact to Files as `Craftberry-Texture-Import.mcaddon`.
7. Return the `.mcaddon` to the Mac by AirDrop. Import it into Minecraft on the same iPhone, activate its behavior and resource packs in a test world, then inspect the sword in the creative inventory and in hand. Check the Minecraft Content Log for pack or texture errors. Keep a screenshot of the imported preview and the Minecraft result with the test record.

The first texture import builds version `1.0.1`; revising the reopened project builds `1.0.2`. The final `.mcaddon` contains the resource pack with the imported icon and is the artifact to use for Minecraft verification.

## Automated evidence and limits

- `swift test` covers PNG dimension/decoding, imported pixel preservation through revision and sidecar round-trip, and compiler output containing the rendered imported icon.
- The UI test `testTextureDocumentPickerPresentsAndCancelsForCalibration` confirms the PNG picker is presented, retains a screenshot for calibration, and cancels cleanly. It intentionally does not count as file selection or import acceptance.
- The actual Files selection, preview after import, reopen/revision on iPhone, and Minecraft rendering remain unverified until the manual checkpoint above is completed on the physical device.
