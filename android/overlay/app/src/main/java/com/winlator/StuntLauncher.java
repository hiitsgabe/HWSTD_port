package com.winlator;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.view.Gravity;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import androidx.preference.PreferenceManager;

import com.winlator.container.Container;
import com.winlator.container.ContainerManager;
import com.winlator.core.AppUtils;
import com.winlator.core.FileUtils;
import com.winlator.renderer.GLRenderer;
import com.winlator.xserver.Drawable;
import com.winlator.xserver.Window;
import com.winlator.xserver.XLock;
import com.winlator.xserver.XServer;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.util.concurrent.Executors;

/**
 * Boots Hot Wheels: Stunt Track Driver straight from the launcher:
 * container (created once) -> game files (copied once from the user's ISO) -> XServerDisplayActivity.
 */
public final class StuntLauncher {
    private static final String CONTAINER_NAME = "Stunt Track Driver";
    private static final String ISO_GAME_DIR = "SETUP/HOT98";
    private static final String CONTROLS_PROFILE_ID = "5"; // assets/inputcontrols/profiles/controls-5.icp

    public static void start(MainActivity activity) {
        // Only autostart on a plain launch, not when Winlator restarts itself into a specific screen.
        Intent intent = activity.getIntent();
        if (intent.hasExtra("container_id") || intent.hasExtra("selected_menu_item_id") || intent.getBooleanExtra("edit_input_controls", false)) return;

        ContainerManager manager = new ContainerManager(activity);
        for (Container container : manager.getContainers()) {
            if (CONTAINER_NAME.equals(container.getName())) {
                withGameFiles(activity, container);
                return;
            }
        }

        try {
            JSONObject data = new JSONObject();
            data.put("name", CONTAINER_NAME);
            data.put("screenSize", "640x480");
            // Builtin ddraw on the GDI renderer: the game draws 8-bit software 3D, no GPU needed.
            // Winlator turns this into WINE_D3D_CONFIG, which overrides HKCU\Software\Wine\Direct3D.
            data.put("dxwrapper", "wined3d");
            data.put("dxwrapperConfig", "renderer=gdi");
            data.put("wincomponents", Container.FALLBACK_WINCOMPONENTS); // plain builtin Wine DLLs
            activity.preloaderDialog.show(R.string.creating_container);
            manager.createContainerAsync(data, (container) -> {
                activity.preloaderDialog.close();
                if (container == null) {
                    AppUtils.showToast(activity, "Could not create the game container");
                    return;
                }
                addRegistryKeys(container);
                withGameFiles(activity, container);
            });
        }
        catch (JSONException e) {}
    }

    private static File gameDir(Container container) {
        return new File(container.getRootDir(), ".wine/drive_c/hot98");
    }

    private static void withGameFiles(MainActivity activity, Container container) {
        if (new File(gameDir(container), "stunt.exe").isFile()) {
            launch(activity, container);
            return;
        }

        AppUtils.showToast(activity, "Select your Hot Wheels Stunt Track Driver ISO");
        activity.setOpenFileCallback((uri) -> copyFromIso(activity, container, uri));
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("*/*");
        activity.startActivityForResult(picker, MainActivity.OPEN_FILE_REQUEST_CODE);
    }

    private static void copyFromIso(MainActivity activity, Container container, Uri uri) {
        AppUtils.keepScreenOn(activity);
        activity.preloaderDialog.show(R.string.loading);
        Executors.newSingleThreadExecutor().execute(() -> {
            File tmpDir = new File(gameDir(container).getPath() + ".tmp");
            FileUtils.delete(tmpDir);
            String error = null;
            try (ParcelFileDescriptor fd = activity.getContentResolver().openFileDescriptor(uri, "r");
                 FileInputStream in = new FileInputStream(fd.getFileDescriptor())) {
                if (!new IsoExtractor(in.getChannel()).extract(ISO_GAME_DIR, tmpDir, null)) error = "This ISO has no " + ISO_GAME_DIR + " folder";
                else if (!tmpDir.renameTo(gameDir(container))) error = "Could not install the game files";
            }
            catch (IOException | RuntimeException e) {
                error = "Could not read the ISO: " + e.getMessage();
            }
            if (error != null) FileUtils.delete(tmpDir);

            final String message = error;
            activity.runOnUiThread(() -> {
                activity.preloaderDialog.close();
                if (message != null) AppUtils.showToast(activity, message);
                else launch(activity, container);
            });
        });
    }

    /** The game refuses to start without its install key; an empty key is enough. */
    private static void addRegistryKeys(Container container) {
        // 32-bit apps on a WoW64 prefix read HKLM\Software through Wow6432Node, so write both views.
        String keys = "\n[Software\\\\Mattel\\\\Stunt Track Driver\\\\1.0] 0\n" +
                      "\n[Software\\\\Wow6432Node\\\\Mattel\\\\Stunt Track Driver\\\\1.0] 0\n";
        try (FileWriter writer = new FileWriter(new File(container.getRootDir(), ".wine/system.reg"), true)) {
            writer.write(keys);
        }
        catch (IOException e) {}
    }

    // --- In-game settings (gear button or the gamepad's Select). Stored in the default SharedPreferences.
    private static final String[] SETTING_KEYS = {"stunt_show_touch_controls", "stunt_stretch_screen", "stunt_gamepad"};
    private static final String[] SETTING_LABELS = {"Show touch controls", "Stretch to fill screen (off: keep 4:3)", "Gamepad support"};
    private static final boolean[] SETTING_DEFAULTS = {true, false, true};
    /** Read by ControlsProfile: when false, gamepads are not mapped to keys/mouse. */
    public static boolean gamepadEnabled = true;

    private static boolean[] loadSettings(Activity activity) {
        SharedPreferences preferences = PreferenceManager.getDefaultSharedPreferences(activity);
        boolean[] values = new boolean[SETTING_KEYS.length];
        for (int i = 0; i < values.length; i++) values[i] = preferences.getBoolean(SETTING_KEYS[i], SETTING_DEFAULTS[i]);
        return values;
    }

    /** Called by XServerDisplayActivity when the game starts and after the settings dialog. */
    public static void applySettings(XServerDisplayActivity activity) {
        boolean[] values = loadSettings(activity);
        activity.getInputControlsView().setShowTouchscreenControls(values[0]);
        activity.getInputControlsView().invalidate();
        GLRenderer renderer = activity.getXServerView().getRenderer();
        if (renderer.isFullscreen() != values[1]) renderer.toggleFullscreen();
        gamepadEnabled = values[2];
    }

    public static void showSettingsDialog(XServerDisplayActivity activity) {
        final boolean[] values = loadSettings(activity);
        new AlertDialog.Builder(activity)
            .setTitle("Game Settings")
            .setMultiChoiceItems(SETTING_LABELS, values, (dialog, which, checked) -> values[which] = checked)
            .setNegativeButton(android.R.string.cancel, null)
            .setNeutralButton("Quit game", (dialog, which) -> activity.exit())
            .setPositiveButton(android.R.string.ok, (dialog, which) -> {
                SharedPreferences.Editor editor = PreferenceManager.getDefaultSharedPreferences(activity).edit();
                for (int i = 0; i < values.length; i++) editor.putBoolean(SETTING_KEYS[i], values[i]);
                editor.apply();
                applySettings(activity);
            })
            .show();
    }

    /** Gear in the top right corner, over the bar above the 4:3 picture. Always shown, so hidden touch controls can come back. */
    public static void addSettingsButton(XServerDisplayActivity activity, FrameLayout rootView) {
        float density = activity.getResources().getDisplayMetrics().density;
        ImageButton button = new ImageButton(activity);
        button.setImageResource(R.drawable.icon_settings);
        button.setColorFilter(Color.WHITE);
        button.setScaleType(ImageButton.ScaleType.FIT_CENTER);
        button.setBackground(null);
        button.setPadding((int)(10 * density), (int)(10 * density), (int)(10 * density), (int)(10 * density));
        button.setAlpha(0.7f);
        button.setFocusable(false); // gamepad keys keep going to the game
        button.setOnClickListener((view) -> showSettingsDialog(activity));
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams((int)(48 * density), (int)(48 * density), Gravity.TOP | Gravity.END);
        params.setMargins(0, (int)(4 * density), (int)(4 * density), 0); // clear of rounded screen corners
        rootView.addView(button, params);
    }

    // --- B button. Esc quits the game from its menus, so the profile binds B to F12 and InputControlsView sends
    // Esc during a race, Space elsewhere (skips the intro, harmless on the menus). Same idea as the handheld's tools/bkey.py.
    // A race is recognised by the Hot Wheels logo on the HUD: {x, y, 0xRRGGBB} in game coordinates (640x480).
    private static final int[][] RACE_PIXELS = {
        {142, 440, 0xfcfcfc}, {96, 436, 0xfcfc00}, {148, 442, 0xf4f4f4}, {88, 448, 0xfcfc00}, {102, 440, 0xfcfc7c}, {84, 448, 0xfcfc7c}
    };

    public static boolean isRace(XServer xServer) {
        try (XLock lock = xServer.lock(XServer.Lockable.WINDOW_MANAGER, XServer.Lockable.DRAWABLE_MANAGER)) {
            return isRace(xServer.windowManager.rootWindow);
        }
    }

    private static boolean isRace(Window window) {
        Drawable content = window.getContent();
        if (window.getMapState() == Window.MapState.VIEWABLE && content != null && content.width >= 640 && content.height >= 480) {
            int hits = 0;
            for (int[] pixel : RACE_PIXELS) {
                int rgb = content.getImage((short)pixel[0], (short)pixel[1], (short)1, (short)1).getInt(0); // BGRA bytes
                boolean match = true;
                for (int shift = 0; shift <= 16; shift += 8) match &= Math.abs(((rgb >> shift) & 255) - ((pixel[2] >> shift) & 255)) <= 24;
                if (match) hits++;
            }
            if (hits >= 5) return true;
        }
        for (Window child : window.getChildren()) if (isRace(child)) return true;
        return false;
    }

    private static void launch(Activity activity, Container container) {
        File desktopDir = new File(container.getUserDir(), "Desktop");
        desktopDir.mkdirs();
        File shortcut = new File(desktopDir, CONTAINER_NAME + ".desktop");
        if (!shortcut.isFile()) {
            FileUtils.writeString(shortcut, "[Desktop Entry]\n" +
                "Name=" + CONTAINER_NAME + "\n" +
                "Exec=env WINEPREFIX=\"/home/xuser/.wine\" wine C:\\\\\\\\hot98\\\\\\\\stunt.exe\n" + // escaped twice, like winemenubuilder
                "Type=Application\n" +
                "StartupWMClass=stunt.exe\n" +
                "\n[Extra Data]\n" +
                "controlsProfile=" + CONTROLS_PROFILE_ID + "\n");
        }

        Intent intent = new Intent(activity, XServerDisplayActivity.class);
        intent.putExtra("container_id", container.id);
        intent.putExtra("shortcut_path", shortcut.getPath());
        intent.putExtra("quit_on_exit", true);
        activity.startActivity(intent);
        activity.finish();
    }
}
