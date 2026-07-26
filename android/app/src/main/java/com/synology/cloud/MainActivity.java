package com.synology.cloud;

import android.content.Intent;
import android.database.Cursor;
import android.util.Log;
import android.net.Uri;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String SHARE_CHANNEL = "app.share_intents";
    private static final String TAG = "ShareIntent";
    private MethodChannel channel;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHARE_CHANNEL);

        Log.d(TAG, "configureFlutterEngine, intent="
                + (getIntent() == null ? "null" : getIntent().getAction()));

        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);

        Log.d(TAG, "onNewIntent, action=" + (intent == null ? "null" : intent.getAction()));

        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        if (intent == null || channel == null) {
            return;
        }

        Log.d(
                TAG,
                "handleIntent"
                        + ", action=" + intent.getAction()
                        + ", flags=0x" + Integer.toHexString(intent.getFlags())
                        + ", hasStream=" + intent.hasExtra(Intent.EXTRA_STREAM)
                        + ", hasText=" + intent.hasExtra(Intent.EXTRA_TEXT)
        );

        String action = intent.getAction();
        if (!Intent.ACTION_SEND.equals(action) && !Intent.ACTION_SEND_MULTIPLE.equals(action)) {
            return;
        }

        List<Map<String, String>> payload = new ArrayList<>();
        if (Intent.ACTION_SEND.equals(action)) {
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (uri != null) {
                payload.add(buildShareItem(uri));
            }
        } else {
            ArrayList<Uri> uris = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (uris != null) {
                for (Uri uri : uris) {
                    if (uri != null) {
                        payload.add(buildShareItem(uri));
                    }
                }
            }
        }

        List<Map<String, String>> validPayload = new ArrayList<>();
        for (Map<String, String> item : payload) {
            if (item != null && item.get("path") != null && !item.get("path").isEmpty()) {
                validPayload.add(item);
            }
        }

        if (!validPayload.isEmpty()) {
            Log.d(TAG,
                    "dispatch share, count=" + validPayload.size());

            channel.invokeMethod("onShareIntent", validPayload);
        } else {
            Log.d(TAG, "share payload empty");
        }
    }

    private Map<String, String> buildShareItem(Uri uri) {
        Map<String, String> item = new HashMap<>();
        String path = copyUriToCache(uri);
        if (path != null) {
            item.put("path", path);
            item.put("name", resolveDisplayName(uri));
        }
        return item;
    }

    private String copyUriToCache(Uri uri) {
        if (uri == null) {
            return null;
        }

        String displayName = resolveDisplayName(uri);
        String safeName = displayName == null || displayName.trim().isEmpty()
                ? "shared_file"
                : displayName.replaceAll("[^a-zA-Z0-9._-]", "_");
        File target = new File(getCacheDir(), "share_" + System.currentTimeMillis() + "_" + safeName);

        try (InputStream inputStream = getContentResolver().openInputStream(uri);
             OutputStream outputStream = new FileOutputStream(target)) {
            if (inputStream == null) {
                return null;
            }
            byte[] buffer = new byte[8192];
            int read;
            while ((read = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, read);
            }
            return target.getAbsolutePath();
        } catch (Exception ignored) {
            return null;
        }
    }

    private String resolveDisplayName(Uri uri) {
        String displayName = null;
        try (Cursor cursor = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    displayName = cursor.getString(index);
                }
            }
        } catch (Exception ignored) {
            // Ignore and fall back to the URI path.
        }

        if (displayName != null && !displayName.trim().isEmpty()) {
            return displayName;
        }

        String lastSegment = uri != null ? uri.getLastPathSegment() : null;
        if (lastSegment != null && !lastSegment.trim().isEmpty()) {
            return lastSegment;
        }
        return "shared_file";
    }
}
